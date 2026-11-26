@tool
extends RefCounted
## Handlers of the "animation" toolset: animations of AnimationPlayer nodes (tracks and
## keys) and state machines of AnimationTree nodes.
##
## An animation is never changed in place: the change is made on a copy, and the copy
## replaces the original in its library. That makes every change one undo step
## (Ctrl+Z puts the original back), exactly like edits in the Animation panel.

const PilotError := preload("../utils/pilot_error.gd")
const ValueCodec := preload("../utils/value_codec.gd")
const PropertyEditing := preload("../utils/property_editing.gd")

const TRACK_TYPES_BY_NAME := {
	"value": Animation.TYPE_VALUE,
	"position_3d": Animation.TYPE_POSITION_3D,
	"rotation_3d": Animation.TYPE_ROTATION_3D,
	"scale_3d": Animation.TYPE_SCALE_3D,
	"blend_shape": Animation.TYPE_BLEND_SHAPE,
	"method": Animation.TYPE_METHOD,
	"bezier": Animation.TYPE_BEZIER,
	"audio": Animation.TYPE_AUDIO,
	"animation": Animation.TYPE_ANIMATION,
}
const LOOP_MODES_BY_NAME := {"none": Animation.LOOP_NONE, "linear": Animation.LOOP_LINEAR, "pingpong": Animation.LOOP_PINGPONG}
const INTERPOLATIONS_BY_NAME := {
	"nearest": Animation.INTERPOLATION_NEAREST,
	"linear": Animation.INTERPOLATION_LINEAR,
	"cubic": Animation.INTERPOLATION_CUBIC,
	"linear_angle": Animation.INTERPOLATION_LINEAR_ANGLE,
	"cubic_angle": Animation.INTERPOLATION_CUBIC_ANGLE,
}
const UPDATE_MODES_BY_NAME := {"continuous": Animation.UPDATE_CONTINUOUS, "discrete": Animation.UPDATE_DISCRETE, "capture": Animation.UPDATE_CAPTURE}
const SWITCH_MODES_BY_NAME := {
	"immediate": AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE,
	"sync": AnimationNodeStateMachineTransition.SWITCH_MODE_SYNC,
	"at_end": AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END,
}
const ADVANCE_MODES_BY_NAME := {
	"disabled": AnimationNodeStateMachineTransition.ADVANCE_MODE_DISABLED,
	"enabled": AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED,
	"auto": AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO,
}
const MAXIMUM_KEYS_SHOWN_PER_TRACK := 200
## Distance between states when the caller gives no positions (state machine graph).
const STATE_SPACING := Vector2(180, 100)

var _context: RefCounted


func _init(context: RefCounted) -> void:
	_context = context


func register_methods(dispatcher: RefCounted) -> void:
	dispatcher.register_method("list_animations", _list_animations)
	dispatcher.register_method("get_animation", _get_animation)
	dispatcher.register_method("create_animation", _create_animation)
	dispatcher.register_method("edit_animation", _edit_animation)
	dispatcher.register_method("delete_animation", _delete_animation)
	dispatcher.register_method("preview_animation", _preview_animation)
	dispatcher.register_method("setup_animation_state_machine", _setup_animation_state_machine)
	dispatcher.register_method("get_animation_tree", _get_animation_tree)


func _list_animations(params: Dictionary) -> Variant:
	var scene_root: Node = _context.get_edited_scene_root()
	if scene_root == null:
		return PilotError.new("NO_OPEN_SCENE", "No scene is open in the editor.")
	var players: Array[Node] = []
	var trees: Array[Node] = []
	if params.has("node_path"):
		var player: Variant = _find_animation_player(String(params["node_path"]))
		if player is PilotError:
			return player
		players.append(player)
	else:
		_collect_nodes_of_class(scene_root, "AnimationPlayer", players)
		_collect_nodes_of_class(scene_root, "AnimationTree", trees)

	var player_descriptions: Array[Dictionary] = []
	for player: AnimationPlayer in players:
		var animation_lines: Array[String] = []
		for animation_name in player.get_animation_list():
			var animation := player.get_animation(animation_name)
			animation_lines.append("%s (%s s, loop %s, %d tracks)" % [animation_name, snappedf(animation.length, 0.001), _name_of(LOOP_MODES_BY_NAME, animation.loop_mode), animation.get_track_count()])
		player_descriptions.append({
			"node_path": _context.describe_node_path(player),
			"root_node": String(player.root_node),
			"autoplay": player.autoplay,
			"animations": animation_lines,
		})
	var tree_descriptions: Array[String] = []
	for tree: AnimationTree in trees:
		var root_class: String = tree.tree_root.get_class() if tree.tree_root != null else "none"
		tree_descriptions.append("%s (tree_root %s, anim_player %s)" % [_context.describe_node_path(tree), root_class, tree.anim_player])
	var result := {"players": player_descriptions}
	if not tree_descriptions.is_empty():
		result["animation_trees"] = tree_descriptions
	if players.is_empty():
		result["hint"] = "No AnimationPlayer in this scene. Add one with add_node (type AnimationPlayer), then create_animation."
	return result


func _get_animation(params: Dictionary) -> Variant:
	var player: Variant = _find_animation_player(String(params.get("node_path", "")))
	if player is PilotError:
		return player
	var animation_name := String(params.get("animation", ""))
	if not player.has_animation(animation_name):
		return _animation_not_found(player, animation_name)
	var animation: Animation = player.get_animation(animation_name)
	var track_descriptions: Array[Dictionary] = []
	for track_index in animation.get_track_count():
		track_descriptions.append(_describe_track(animation, track_index))
	return {
		"animation": animation_name,
		"length": animation.length,
		"loop_mode": _name_of(LOOP_MODES_BY_NAME, animation.loop_mode),
		"step": animation.step,
		"tracks": track_descriptions,
	}


func _create_animation(params: Dictionary) -> Variant:
	var player: Variant = _find_animation_player(String(params.get("node_path", "")))
	if player is PilotError:
		return player
	var full_name := String(params.get("animation", ""))
	var library_name := _library_name_of(full_name)
	var animation_name := _short_name_of(full_name)
	if animation_name == "" or animation_name.contains("/") or animation_name.contains(":") or animation_name.contains(","):
		return PilotError.new("INVALID_NAME", "'%s' is not a valid animation name." % full_name, "Use a name like \"walk\", or \"library/walk\" for a named library.")
	var original: Animation = null
	if player.has_animation(full_name):
		if not bool(params.get("overwrite", false)):
			return PilotError.new("ALREADY_EXISTS", "The animation '%s' already exists." % full_name, "Use edit_animation to change it, or pass overwrite: true.")
		original = player.get_animation(full_name)

	var animation := Animation.new()
	animation.length = 1.0
	var warnings: Array[String] = []
	var edit_error: Variant = _apply_animation_edits(animation, params, player, warnings)
	if edit_error is PilotError:
		return edit_error

	var undo_redo: EditorUndoRedoManager = _context.get_undo_redo()
	if player.has_animation_library(library_name):
		var library: AnimationLibrary = player.get_animation_library(library_name)
		undo_redo.create_action("Create animation %s" % full_name, UndoRedo.MERGE_DISABLE, player)
		undo_redo.add_do_method(library, "add_animation", StringName(animation_name), animation)
		if original != null:
			undo_redo.add_undo_method(library, "add_animation", StringName(animation_name), original)
		else:
			undo_redo.add_undo_method(library, "remove_animation", StringName(animation_name))
	else:
		var new_library := AnimationLibrary.new()
		new_library.add_animation(StringName(animation_name), animation)
		undo_redo.create_action("Create animation %s" % full_name, UndoRedo.MERGE_DISABLE, player)
		undo_redo.add_do_method(player, "add_animation_library", StringName(library_name), new_library)
		undo_redo.add_undo_method(player, "remove_animation_library", StringName(library_name))
	if params.has("autoplay"):
		undo_redo.add_do_property(player, "autoplay", full_name if bool(params["autoplay"]) else "")
		undo_redo.add_undo_property(player, "autoplay", player.autoplay)
	undo_redo.commit_action()
	_save_external_library(player, library_name)

	var result := {"created": full_name, "length": animation.length, "tracks": animation.get_track_count()}
	if not warnings.is_empty():
		result["warnings"] = warnings
	return result


func _edit_animation(params: Dictionary) -> Variant:
	var player: Variant = _find_animation_player(String(params.get("node_path", "")))
	if player is PilotError:
		return player
	var full_name := String(params.get("animation", ""))
	if not player.has_animation(full_name):
		return _animation_not_found(player, full_name)
	var original: Animation = player.get_animation(full_name)
	var edited: Animation = original.duplicate(true)
	var warnings: Array[String] = []
	var edit_error: Variant = _apply_animation_edits(edited, params, player, warnings)
	if edit_error is PilotError:
		return edit_error

	var library_name := _library_name_of(full_name)
	var library: AnimationLibrary = player.get_animation_library(library_name)
	var animation_name := StringName(_short_name_of(full_name))
	var undo_redo: EditorUndoRedoManager = _context.get_undo_redo()
	undo_redo.create_action("Edit animation %s" % full_name, UndoRedo.MERGE_DISABLE, player)
	undo_redo.add_do_method(library, "add_animation", animation_name, edited)
	undo_redo.add_undo_method(library, "add_animation", animation_name, original)
	undo_redo.commit_action()
	_save_external_library(player, library_name)

	var result := {"edited": full_name, "length": edited.length, "tracks": edited.get_track_count()}
	if not warnings.is_empty():
		result["warnings"] = warnings
	return result


func _delete_animation(params: Dictionary) -> Variant:
	var player: Variant = _find_animation_player(String(params.get("node_path", "")))
	if player is PilotError:
		return player
	var full_name := String(params.get("animation", ""))
	if not player.has_animation(full_name):
		return _animation_not_found(player, full_name)
	var library_name := _library_name_of(full_name)
	var library: AnimationLibrary = player.get_animation_library(library_name)
	var animation_name := StringName(_short_name_of(full_name))
	var undo_redo: EditorUndoRedoManager = _context.get_undo_redo()
	undo_redo.create_action("Delete animation %s" % full_name, UndoRedo.MERGE_DISABLE, player)
	undo_redo.add_do_method(library, "remove_animation", animation_name)
	undo_redo.add_undo_method(library, "add_animation", animation_name, player.get_animation(full_name))
	if player.autoplay == full_name:
		undo_redo.add_do_property(player, "autoplay", "")
		undo_redo.add_undo_property(player, "autoplay", full_name)
	undo_redo.commit_action()
	_save_external_library(player, library_name)
	return {"deleted": full_name}


## Shows the pose of an animation at a moment, like dragging the Animation panel's time
## cursor. The animated properties really change in the editor, so render_view and
## get_properties show that pose. "RESET" (when it exists) brings the scene back.
func _preview_animation(params: Dictionary) -> Variant:
	var player: Variant = _find_animation_player(String(params.get("node_path", "")))
	if player is PilotError:
		return player
	var full_name := String(params.get("animation", ""))
	if not player.has_animation(full_name):
		return _animation_not_found(player, full_name)
	var animation: Animation = player.get_animation(full_name)
	var time := clampf(float(params.get("time", 0.0)), 0.0, animation.length)
	player.assigned_animation = full_name
	player.seek(time, true)

	var animated_values := {}
	var animation_root: Node = player.get_node_or_null(player.root_node)
	for track_index in animation.get_track_count():
		var track_type := animation.track_get_type(track_index)
		if track_type == Animation.TYPE_METHOD or track_type == Animation.TYPE_AUDIO or track_type == Animation.TYPE_ANIMATION:
			continue
		var track_path := animation.track_get_path(track_index)
		var target: Node = animation_root.get_node_or_null(NodePath(track_path.get_concatenated_names())) if animation_root != null else null
		if target == null:
			continue
		var property_path := String(track_path.get_concatenated_subnames())
		match track_type:
			Animation.TYPE_POSITION_3D:
				property_path = "position"
			Animation.TYPE_ROTATION_3D:
				property_path = "quaternion"
			Animation.TYPE_SCALE_3D:
				property_path = "scale"
		if property_path == "":
			continue
		animated_values[String(track_path) if track_type in [Animation.TYPE_VALUE, Animation.TYPE_BEZIER] else "%s (%s)" % [track_path, property_path]] = ValueCodec.to_json_value(target.get_indexed(NodePath(property_path)), _context.get_edited_scene_root())
	var result := {"animation": full_name, "time": time, "values": animated_values}
	if player.has_animation("RESET") and full_name != "RESET":
		result["hint"] = "The scene now shows this pose. Saving keeps it; preview \"RESET\" at time 0 first to go back."
	return result


## Builds (or replaces) the state machine of an AnimationTree: states that play
## animations, and transitions between them (with conditions or expressions).
func _setup_animation_state_machine(params: Dictionary) -> Variant:
	var tree: Variant = _context.find_node_in_edited_scene(String(params.get("node_path", "")))
	if tree is PilotError:
		return tree
	if not tree is AnimationTree:
		return PilotError.new("NOT_AN_ANIMATION_TREE", "%s is a %s, not an AnimationTree." % [tree.name, tree.get_class()], "Add one with add_node (type AnimationTree) next to the AnimationPlayer.")

	var player_path: NodePath = tree.anim_player
	if params.has("animation_player"):
		var player_node: Variant = _context.find_node_in_edited_scene(String(params["animation_player"]))
		if player_node is PilotError:
			return player_node
		player_path = tree.get_path_to(player_node)
	var player: AnimationPlayer = tree.get_node_or_null(player_path) as AnimationPlayer
	if player == null:
		return PilotError.new("NO_ANIMATION_PLAYER", "The AnimationTree has no AnimationPlayer.", "Pass animation_player: the path of the AnimationPlayer whose animations the states play.")

	var state_machine: AnimationNodeStateMachine
	if bool(params.get("keep_existing", false)) and tree.tree_root is AnimationNodeStateMachine:
		state_machine = tree.tree_root.duplicate(true)
	else:
		state_machine = AnimationNodeStateMachine.new()

	var warnings: Array[String] = []
	var states: Array = params.get("states", []) if params.get("states") is Array else []
	for state_index in states.size():
		var state: Variant = states[state_index]
		if not state is Dictionary or String(state.get("name", "")) == "":
			return PilotError.new("INVALID_STATE", "Each state needs a name, for example {\"name\": \"Idle\", \"animation\": \"idle\"}.")
		var state_name := StringName(String(state["name"]))
		var animation_name := String(state.get("animation", state["name"]))
		if not player.has_animation(animation_name):
			warnings.append("State %s plays '%s', which the AnimationPlayer does not have (yet)." % [state_name, animation_name])
		var animation_node := AnimationNodeAnimation.new()
		animation_node.animation = StringName(animation_name)
		var position := Vector2(STATE_SPACING.x * (state_index % 4 + 1), STATE_SPACING.y * floorf(state_index / 4.0))
		if state.has("position"):
			var position_conversion := ValueCodec.from_json_value(state["position"], TYPE_VECTOR2)
			if position_conversion["ok"]:
				position = position_conversion["value"]
		if state_machine.has_node(state_name):
			state_machine.replace_node(state_name, animation_node)
		else:
			state_machine.add_node(state_name, animation_node, position)

	var transitions: Array = params.get("transitions", []) if params.get("transitions") is Array else []
	if params.has("start_state"):
		transitions.push_front({"from": "Start", "to": String(params["start_state"]), "advance_mode": "auto"})
	for transition_description: Variant in transitions:
		if not transition_description is Dictionary:
			continue
		var from_state := StringName(String(transition_description.get("from", "")))
		var to_state := StringName(String(transition_description.get("to", "")))
		for state_name in [from_state, to_state]:
			if not state_machine.has_node(state_name):
				return PilotError.new("STATE_NOT_FOUND", "There is no state '%s' for the transition %s -> %s." % [state_name, from_state, to_state], "Add it in states. \"Start\" and \"End\" always exist.")
		var transition := AnimationNodeStateMachineTransition.new()
		transition.switch_mode = SWITCH_MODES_BY_NAME.get(String(transition_description.get("switch_mode", "immediate")), AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE)
		var default_advance_mode := "enabled"
		if transition_description.has("condition") or transition_description.has("expression"):
			default_advance_mode = "auto"
		transition.advance_mode = ADVANCE_MODES_BY_NAME.get(String(transition_description.get("advance_mode", default_advance_mode)), AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED)
		if transition_description.has("condition"):
			transition.advance_condition = StringName(String(transition_description["condition"]))
		if transition_description.has("expression"):
			transition.advance_expression = String(transition_description["expression"])
		transition.xfade_time = float(transition_description.get("xfade_time", 0.0))
		if state_machine.has_transition(from_state, to_state):
			state_machine.remove_transition(from_state, to_state)
		state_machine.add_transition(from_state, to_state, transition)

	var undo_redo: EditorUndoRedoManager = _context.get_undo_redo()
	undo_redo.create_action("Set up animation state machine", UndoRedo.MERGE_DISABLE, tree)
	undo_redo.add_do_property(tree, "anim_player", player_path)
	undo_redo.add_undo_property(tree, "anim_player", tree.anim_player)
	undo_redo.add_do_property(tree, "tree_root", state_machine)
	undo_redo.add_undo_property(tree, "tree_root", tree.tree_root)
	undo_redo.add_do_property(tree, "active", true)
	undo_redo.add_undo_property(tree, "active", tree.active)
	undo_redo.commit_action()

	var result: Dictionary = _describe_animation_tree(tree)
	result["usage"] = "In the game: tree.get(\"parameters/playback\").travel(\"State\") changes state; tree.set(\"parameters/conditions/<name>\", true) fires a condition transition. Expressions are evaluated on the AnimationTree's advance_expression_base_node."
	if not warnings.is_empty():
		result["warnings"] = warnings
	return result


func _get_animation_tree(params: Dictionary) -> Variant:
	var tree: Variant = _context.find_node_in_edited_scene(String(params.get("node_path", "")))
	if tree is PilotError:
		return tree
	if not tree is AnimationTree:
		return PilotError.new("NOT_AN_ANIMATION_TREE", "%s is a %s, not an AnimationTree." % [tree.name, tree.get_class()])
	return _describe_animation_tree(tree)


func _describe_animation_tree(tree: AnimationTree) -> Dictionary:
	var description := {
		"node_path": _context.describe_node_path(tree),
		"anim_player": String(tree.anim_player),
		"active": tree.active,
		"tree_root": tree.tree_root.get_class() if tree.tree_root != null else null,
	}
	var root := tree.tree_root
	if root is AnimationNodeStateMachine:
		var state_lines: Array[String] = []
		for state_name in _list_child_node_names(root, "states/"):
			var state_node: AnimationNode = root.get_node(state_name)
			var animation_text := " plays %s" % state_node.animation if state_node is AnimationNodeAnimation else ""
			state_lines.append("%s (%s)%s" % [state_name, state_node.get_class(), animation_text])
		var transition_lines: Array[String] = []
		for transition_index in root.get_transition_count():
			var transition: AnimationNodeStateMachineTransition = root.get_transition(transition_index)
			var transition_text := "%s -> %s (%s, advance %s" % [root.get_transition_from(transition_index), root.get_transition_to(transition_index), _name_of(SWITCH_MODES_BY_NAME, transition.switch_mode), _name_of(ADVANCE_MODES_BY_NAME, transition.advance_mode)]
			if transition.advance_condition != &"":
				transition_text += ", condition %s" % transition.advance_condition
			if transition.advance_expression != "":
				transition_text += ", expression \"%s\"" % transition.advance_expression
			if transition.xfade_time > 0.0:
				transition_text += ", xfade %s s" % transition.xfade_time
			transition_lines.append(transition_text + ")")
		description["states"] = state_lines
		description["transitions"] = transition_lines
	elif root is AnimationNodeBlendTree:
		description["nodes"] = _list_child_node_names(root, "nodes/")
	var parameters := {}
	for property in tree.get_property_list():
		var property_name := String(property["name"])
		if property_name.begins_with("parameters/") and int(property["usage"]) & PROPERTY_USAGE_EDITOR != 0:
			parameters[property_name] = ValueCodec.to_json_value(tree.get(property_name))
	description["parameters"] = parameters
	return description


## State machines and blend trees list their children as properties like "states/Idle/node".
func _list_child_node_names(animation_node: AnimationNode, prefix: String) -> Array[String]:
	var names: Array[String] = []
	for property in animation_node.get_property_list():
		var property_name := String(property["name"])
		if property_name.begins_with(prefix) and property_name.ends_with("/node"):
			names.append(property_name.trim_prefix(prefix).trim_suffix("/node"))
	return names


## Applies length, loop mode, step, track/key additions and removals to `animation`.
## Returns a PilotError, or null when everything worked.
func _apply_animation_edits(animation: Animation, params: Dictionary, player: AnimationPlayer, warnings: Array[String]) -> Variant:
	if params.has("length"):
		animation.length = maxf(float(params["length"]), 0.001)
	if params.has("loop_mode"):
		var loop_mode_name := String(params["loop_mode"])
		if not LOOP_MODES_BY_NAME.has(loop_mode_name):
			return PilotError.new("INVALID_LOOP_MODE", "Unknown loop mode '%s'." % loop_mode_name, "Use none, linear or pingpong.")
		animation.loop_mode = LOOP_MODES_BY_NAME[loop_mode_name]
	if params.has("step"):
		animation.step = maxf(float(params["step"]), 0.0)

	for track_path_text: Variant in params.get("remove_tracks", []):
		var removed := false
		for track_index in range(animation.get_track_count() - 1, -1, -1):
			if String(animation.track_get_path(track_index)) == String(track_path_text):
				animation.remove_track(track_index)
				removed = true
		if not removed:
			warnings.append("No track '%s' to remove." % track_path_text)

	for key_to_remove: Variant in params.get("remove_keys", []):
		if not key_to_remove is Dictionary:
			continue
		var track_index := _find_track_by_path(animation, String(key_to_remove.get("path", "")), String(key_to_remove.get("type", "")))
		if track_index == -1:
			warnings.append("No track '%s' to remove a key from." % key_to_remove.get("path", ""))
			continue
		var key_index := animation.track_find_key(track_index, float(key_to_remove.get("time", 0.0)), Animation.FIND_MODE_APPROX)
		if key_index == -1:
			warnings.append("Track '%s' has no key at %s s." % [key_to_remove.get("path", ""), key_to_remove.get("time", 0.0)])
			continue
		animation.track_remove_key(track_index, key_index)

	var scene_root: Node = _context.get_edited_scene_root()
	var animation_root: Node = player.get_node_or_null(player.root_node)
	for track_description: Variant in params.get("tracks", []):
		if not track_description is Dictionary:
			return PilotError.new("INVALID_TRACK", "Each track must be an object like {\"path\": \"Sprite2D:modulate\", \"keys\": [{\"time\": 0, \"value\": \"white\"}]}.")
		var track_error: Variant = _apply_track_description(animation, track_description, animation_root, scene_root, warnings)
		if track_error is PilotError:
			return track_error
	return null


func _apply_track_description(animation: Animation, track_description: Dictionary, animation_root: Node, scene_root: Node, warnings: Array[String]) -> Variant:
	var track_path := String(track_description.get("path", ""))
	var type_name := String(track_description.get("type", "value"))
	if not TRACK_TYPES_BY_NAME.has(type_name):
		return PilotError.new("INVALID_TRACK_TYPE", "Unknown track type '%s'." % type_name, "Use one of: %s." % ", ".join(TRACK_TYPES_BY_NAME.keys()))
	var track_type: int = TRACK_TYPES_BY_NAME[type_name]
	var node_path_part := String(NodePath(track_path).get_concatenated_names())
	var property_part := String(NodePath(track_path).get_concatenated_subnames())
	if track_path == "":
		return PilotError.new("INVALID_TRACK_PATH", "A track needs a path.", "Value tracks: \"NodePath:property\" relative to the AnimationPlayer's root node (its parent by default), for example \"Sprite2D:modulate\" or \".:position\". Transform tracks (position_3d...) and method tracks: just the node path.")
	if track_type in [Animation.TYPE_VALUE, Animation.TYPE_BEZIER, Animation.TYPE_BLEND_SHAPE] and property_part == "":
		return PilotError.new("INVALID_TRACK_PATH", "The %s track path '%s' needs a property after ':'." % [type_name, track_path], "For example \"Sprite2D:modulate\" or \"Player:position:x\".")

	var target: Node = null
	if animation_root != null:
		target = animation_root.get_node_or_null(NodePath(node_path_part)) if node_path_part != "" else animation_root
	if target == null:
		warnings.append("Track '%s': no node at '%s' from the AnimationPlayer's root node, so values are not type-checked." % [track_path, node_path_part])

	var track_index := animation.find_track(NodePath(track_path), track_type)
	if track_index == -1:
		track_index = animation.add_track(track_type)
		animation.track_set_path(track_index, NodePath(track_path))
	if track_description.has("interpolation"):
		var interpolation_name := String(track_description["interpolation"])
		if not INTERPOLATIONS_BY_NAME.has(interpolation_name):
			return PilotError.new("INVALID_INTERPOLATION", "Unknown interpolation '%s'." % interpolation_name, "Use one of: %s." % ", ".join(INTERPOLATIONS_BY_NAME.keys()))
		animation.track_set_interpolation_type(track_index, INTERPOLATIONS_BY_NAME[interpolation_name])
	if track_description.has("update_mode") and track_type == Animation.TYPE_VALUE:
		animation.value_track_set_update_mode(track_index, UPDATE_MODES_BY_NAME.get(String(track_description["update_mode"]), Animation.UPDATE_CONTINUOUS))
	if bool(track_description.get("replace_keys", false)):
		for key_index in range(animation.track_get_key_count(track_index) - 1, -1, -1):
			animation.track_remove_key(track_index, key_index)

	for key: Variant in track_description.get("keys", []):
		if not key is Dictionary or not key.has("time"):
			return PilotError.new("INVALID_KEY", "Each key needs a time, for example {\"time\": 0.5, \"value\": [10, 20]}.")
		var key_time := float(key["time"])
		if key_time > animation.length + 0.0001:
			warnings.append("Track '%s' has a key at %s s, after the animation's length (%s s)." % [track_path, key_time, animation.length])
		var conversion := _convert_key_value(track_type, key.get("value"), target, property_part, scene_root)
		if not conversion["ok"]:
			return PilotError.new("INVALID_KEY_VALUE", "Track '%s' at %s s: %s" % [track_path, key_time, conversion["error"]])
		var value: Variant = conversion["value"]
		var existing_key := animation.track_find_key(track_index, key_time, Animation.FIND_MODE_APPROX)
		if existing_key != -1:
			animation.track_remove_key(track_index, existing_key)
		match track_type:
			Animation.TYPE_POSITION_3D:
				animation.position_track_insert_key(track_index, key_time, value)
			Animation.TYPE_ROTATION_3D:
				animation.rotation_track_insert_key(track_index, key_time, value)
			Animation.TYPE_SCALE_3D:
				animation.scale_track_insert_key(track_index, key_time, value)
			Animation.TYPE_BLEND_SHAPE:
				animation.blend_shape_track_insert_key(track_index, key_time, value)
			Animation.TYPE_BEZIER:
				animation.bezier_track_insert_key(track_index, key_time, value, Vector2(-0.25, 0), Vector2(0.25, 0))
			Animation.TYPE_AUDIO:
				animation.audio_track_insert_key(track_index, key_time, value["stream"], value["start_offset"], value["end_offset"])
			_:
				animation.track_insert_key(track_index, key_time, value, float(key.get("transition", 1.0)))
	return null


## Converts a key value from JSON into what the track type stores.
func _convert_key_value(track_type: int, raw_value: Variant, target: Node, property_path: String, scene_root: Node) -> Dictionary:
	match track_type:
		Animation.TYPE_POSITION_3D, Animation.TYPE_SCALE_3D:
			return ValueCodec.from_json_value(raw_value, TYPE_VECTOR3)
		Animation.TYPE_ROTATION_3D:
			# Degrees like [0, 90, 0] are easier to write than a Quaternion.
			if raw_value is Array and raw_value.size() == 3:
				var euler_degrees := Vector3(float(raw_value[0]), float(raw_value[1]), float(raw_value[2]))
				return {"ok": true, "value": Quaternion.from_euler(euler_degrees * (PI / 180.0))}
			return ValueCodec.from_json_value(raw_value, TYPE_QUATERNION)
		Animation.TYPE_BLEND_SHAPE, Animation.TYPE_BEZIER:
			return ValueCodec.from_json_value(raw_value, TYPE_FLOAT)
		Animation.TYPE_METHOD:
			if raw_value is Dictionary and raw_value.has("method"):
				return {"ok": true, "value": {"method": StringName(String(raw_value["method"])), "args": raw_value.get("args", [])}}
			return {"ok": false, "error": "Method keys look like {\"method\": \"queue_free\", \"args\": []}."}
		Animation.TYPE_AUDIO:
			var stream_path: Variant = raw_value.get("stream") if raw_value is Dictionary else raw_value
			var stream_conversion := ValueCodec.from_json_value(stream_path, TYPE_OBJECT, "AudioStream")
			if not stream_conversion["ok"]:
				return stream_conversion
			var offsets: Dictionary = raw_value if raw_value is Dictionary else {}
			return {"ok": true, "value": {"stream": stream_conversion["value"], "start_offset": float(offsets.get("start_offset", 0.0)), "end_offset": float(offsets.get("end_offset", 0.0))}}
		Animation.TYPE_ANIMATION:
			return {"ok": true, "value": StringName(str(raw_value))}
	if target != null:
		return PropertyEditing.convert_for_property(target, property_path, raw_value, scene_root)
	return ValueCodec.from_json_value(raw_value, TYPE_NIL)


func _describe_track(animation: Animation, track_index: int) -> Dictionary:
	var track_type := animation.track_get_type(track_index)
	var key_lines: Array[String] = []
	var key_count := animation.track_get_key_count(track_index)
	for key_index in mini(key_count, MAXIMUM_KEYS_SHOWN_PER_TRACK):
		var key_time := snappedf(animation.track_get_key_time(track_index, key_index), 0.0001)
		var value_text := _describe_key_value(animation, track_index, key_index, track_type)
		var transition := animation.track_get_key_transition(track_index, key_index)
		key_lines.append("%s: %s%s" % [key_time, value_text, "" if is_equal_approx(transition, 1.0) else " (easing %s)" % transition])
	var description := {
		"index": track_index,
		"type": _name_of(TRACK_TYPES_BY_NAME, track_type),
		"path": String(animation.track_get_path(track_index)),
		"interpolation": _name_of(INTERPOLATIONS_BY_NAME, animation.track_get_interpolation_type(track_index)),
		"keys": key_lines,
	}
	if track_type == Animation.TYPE_VALUE:
		description["update_mode"] = _name_of(UPDATE_MODES_BY_NAME, animation.value_track_get_update_mode(track_index))
	if not animation.track_is_enabled(track_index):
		description["enabled"] = false
	if key_count > MAXIMUM_KEYS_SHOWN_PER_TRACK:
		description["keys_not_shown"] = key_count - MAXIMUM_KEYS_SHOWN_PER_TRACK
	return description


func _describe_key_value(animation: Animation, track_index: int, key_index: int, track_type: int) -> String:
	match track_type:
		Animation.TYPE_BEZIER:
			return str(animation.bezier_track_get_key_value(track_index, key_index))
		Animation.TYPE_AUDIO:
			var stream := animation.audio_track_get_key_stream(track_index, key_index)
			return stream.resource_path if stream != null else "null"
		Animation.TYPE_METHOD:
			return "%s(%s)" % [animation.method_track_get_name(track_index, key_index), ", ".join(animation.method_track_get_params(track_index, key_index).map(func(argument: Variant) -> String: return var_to_str(argument)))]
	var json_value: Variant = ValueCodec.to_json_value(animation.track_get_key_value(track_index, key_index))
	return json_value if json_value is String else JSON.stringify(json_value)


func _find_track_by_path(animation: Animation, track_path: String, type_name: String) -> int:
	for track_index in animation.get_track_count():
		if String(animation.track_get_path(track_index)) != track_path:
			continue
		if type_name == "" or TRACK_TYPES_BY_NAME.get(type_name, -1) == animation.track_get_type(track_index):
			return track_index
	return -1


func _find_animation_player(node_path: String) -> Variant:
	var node: Variant = _context.find_node_in_edited_scene(node_path)
	if node is PilotError:
		return node
	if not node is AnimationPlayer:
		return PilotError.new("NOT_AN_ANIMATION_PLAYER", "%s is a %s, not an AnimationPlayer." % [node.name, node.get_class()], "list_animations finds the AnimationPlayer nodes. Add one with add_node (type AnimationPlayer).")
	return node


func _animation_not_found(player: AnimationPlayer, animation_name: String) -> PilotError:
	var known_names := ", ".join(Array(player.get_animation_list()))
	return PilotError.new("ANIMATION_NOT_FOUND", "%s has no animation '%s'." % [player.name, animation_name], "Animations: %s. Use create_animation for a new one." % (known_names if known_names != "" else "none"))


## When the library is its own file (.tres/.res), the change is saved to that file too.
func _save_external_library(player: AnimationPlayer, library_name: String) -> void:
	if not player.has_animation_library(library_name):
		return
	var library: AnimationLibrary = player.get_animation_library(library_name)
	if library.resource_path != "" and not library.resource_path.contains("::"):
		ResourceSaver.save(library)


func _library_name_of(full_name: String) -> String:
	return full_name.get_slice("/", 0) if full_name.contains("/") else ""


func _short_name_of(full_name: String) -> String:
	return full_name.get_slice("/", 1) if full_name.contains("/") else full_name


func _collect_nodes_of_class(node: Node, class_name_text: String, found_nodes: Array[Node]) -> void:
	if node.is_class(class_name_text):
		found_nodes.append(node)
	for child in node.get_children():
		_collect_nodes_of_class(child, class_name_text, found_nodes)


func _name_of(names_to_values: Dictionary, value: int) -> String:
	for name_text in names_to_values:
		if names_to_values[name_text] == value:
			return name_text
	return str(value)
