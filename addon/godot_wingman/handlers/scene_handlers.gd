@tool
extends RefCounted
## Handlers of the "scene" toolset: reading the scene tree, opening and saving scenes,
## and adding, removing, moving, renaming and duplicating nodes.
##
## Every change goes through the editor's undo history, so Ctrl+Z works, and new nodes
## get the scene root as owner, so they are saved with the scene.

const WingmanError := preload("../utils/wingman_error.gd")
const ValueCodec := preload("../utils/value_codec.gd")
const PropertyEditing := preload("../utils/property_editing.gd")

const DEFAULT_TREE_DEPTH := 8
const MAX_TREE_NODES := 600

var _context: RefCounted


func _init(context: RefCounted) -> void:
	_context = context


func register_methods(dispatcher: RefCounted) -> void:
	dispatcher.register_method("get_scene_tree", _get_scene_tree)
	dispatcher.register_method("open_scene", _open_scene)
	dispatcher.register_method("save_scene", _save_scene)
	dispatcher.register_method("create_scene", _create_scene)
	dispatcher.register_method("close_scene", _close_scene)
	dispatcher.register_method("add_node", _add_node)
	dispatcher.register_method("delete_nodes", _delete_nodes)
	dispatcher.register_method("duplicate_node", _duplicate_node)
	dispatcher.register_method("move_node", _move_node)
	dispatcher.register_method("rename_node", _rename_node)
	dispatcher.register_method("select_nodes", _select_nodes)
	dispatcher.register_method("batch_edit", _batch_edit)


#region Reading

func _get_scene_tree(params: Dictionary) -> Variant:
	var start_node: Variant = _context.find_node_in_edited_scene(String(params.get("node_path", ".")))
	if start_node is WingmanError:
		return start_node
	var scene_root: Node = _context.get_edited_scene_root()
	var max_depth := int(params.get("max_depth", DEFAULT_TREE_DEPTH))
	var tree_lines: Array[String] = []
	var is_truncated := _append_tree_lines(start_node, scene_root, 0, max_depth, tree_lines)
	var result := {
		"scene": scene_root.scene_file_path,
		"tree": "\n".join(tree_lines),
		"node_count": tree_lines.size(),
	}
	if is_truncated:
		result["note"] = "Output was shortened. Pass node_path to see one branch, or raise max_depth."
	return result


## Writes one line per node, indented by depth: "Name (Class) script=... instance=...".
## Returns true when nodes were left out because of the depth or size limits.
func _append_tree_lines(node: Node, scene_root: Node, depth: int, max_depth: int, tree_lines: Array[String]) -> bool:
	if tree_lines.size() >= MAX_TREE_NODES:
		return true
	tree_lines.append("  ".repeat(depth) + _describe_node_line(node, scene_root))

	var is_instanced_scene := node != scene_root and node.scene_file_path != ""
	if is_instanced_scene and not scene_root.is_editable_instance(node):
		return false
	var visible_children := node.get_children().filter(func(child: Node) -> bool: return _belongs_to_scene(child, scene_root))
	if visible_children.is_empty():
		return false
	if depth >= max_depth:
		tree_lines.append("  ".repeat(depth + 1) + "... %d children not shown" % visible_children.size())
		return true

	var is_truncated := false
	for child in visible_children:
		is_truncated = _append_tree_lines(child, scene_root, depth + 1, max_depth, tree_lines) or is_truncated
	return is_truncated


func _describe_node_line(node: Node, scene_root: Node) -> String:
	var line := "%s (%s)" % [node.name, node.get_class()]
	var script: Script = node.get_script()
	if script != null:
		line += " script=%s" % (script.resource_path if script.resource_path != "" else "<built-in>")
	if node != scene_root and node.scene_file_path != "":
		line += " instance=%s" % node.scene_file_path
	var persistent_groups := node.get_groups().filter(func(group_name: StringName) -> bool: return not String(group_name).begins_with("_"))
	if not persistent_groups.is_empty():
		line += " groups=[%s]" % ", ".join(persistent_groups)
	if "visible" in node and node.get("visible") == false:
		line += " hidden"
	return line


## Nodes created internally by other nodes (or inside instanced scenes) are not part of
## the scene a person edits.
func _belongs_to_scene(node: Node, scene_root: Node) -> bool:
	return node.owner == scene_root or (node.owner != null and scene_root.is_editable_instance(node.owner))

#endregion


#region Scenes

func _open_scene(params: Dictionary) -> Variant:
	var scene_path := String(params.get("path", ""))
	if not ResourceLoader.exists(scene_path):
		return WingmanError.new("SCENE_NOT_FOUND", "No scene at '%s'." % scene_path, "Use list_files with filter \"*.tscn\" to find scenes.")
	EditorInterface.open_scene_from_path(scene_path)
	await _context.get_scene_tree().process_frame
	return {"opened": scene_path, "root": _describe_root()}


func _save_scene(params: Dictionary) -> Variant:
	if _context.get_edited_scene_root() == null:
		return WingmanError.new("NO_OPEN_SCENE", "No scene is open.")
	var new_path := String(params.get("path", ""))
	if new_path != "":
		EditorInterface.save_scene_as(new_path)
		return {"saved_as": new_path}
	var save_error := EditorInterface.save_scene()
	if save_error != OK:
		return WingmanError.new("SAVE_FAILED", "Saving failed: %s." % error_string(save_error), "A new scene needs a path: pass path, for example \"res://levels/level_1.tscn\".")
	return {"saved": _context.get_edited_scene_root().scene_file_path}


func _create_scene(params: Dictionary) -> Variant:
	var scene_path := String(params.get("path", ""))
	if not scene_path.begins_with("res://") or not (scene_path.ends_with(".tscn") or scene_path.ends_with(".scn")):
		return WingmanError.new("INVALID_PATH", "The scene path must start with res:// and end with .tscn.")
	if FileAccess.file_exists(scene_path) and not bool(params.get("overwrite", false)):
		return WingmanError.new("ALREADY_EXISTS", "'%s' already exists." % scene_path, "Open it with open_scene, or pass overwrite: true.")

	var root_type := String(params.get("root_type", "Node2D"))
	var root_node: Variant = instantiate_node_type(root_type)
	if root_node is WingmanError:
		return root_node
	root_node.name = String(params.get("root_name", scene_path.get_file().get_basename().to_pascal_case()))

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(scene_path.get_base_dir()))
	var packed_scene := PackedScene.new()
	packed_scene.pack(root_node)
	var save_error := ResourceSaver.save(packed_scene, scene_path)
	root_node.free()
	if save_error != OK:
		return WingmanError.new("SAVE_FAILED", "Could not save '%s': %s." % [scene_path, error_string(save_error)])

	EditorInterface.get_resource_filesystem().update_file(scene_path)
	EditorInterface.open_scene_from_path(scene_path)
	await _context.get_scene_tree().process_frame
	return {"created": scene_path, "root": _describe_root()}


func _close_scene(params: Dictionary) -> Variant:
	var scene_root: Node = _context.get_edited_scene_root()
	if scene_root == null:
		return WingmanError.new("NO_OPEN_SCENE", "No scene is open.")
	var unsaved_scenes: PackedStringArray = _context.call_editor_interface("get_unsaved_scenes", [], PackedStringArray())
	var has_unsaved_changes := unsaved_scenes.has(scene_root.scene_file_path)
	if has_unsaved_changes and not bool(params.get("discard_changes", false)):
		return WingmanError.new("UNSAVED_CHANGES", "The scene has unsaved changes.", "Save it with save_scene first, or pass discard_changes: true.")
	var closed_path := scene_root.scene_file_path
	if not EditorInterface.has_method("close_scene"):
		return WingmanError.new("NOT_SUPPORTED", "This Godot version cannot close scenes from a plugin.", "Close the tab by hand, or update Godot.")
	_context.call_editor_interface("close_scene")
	await _context.get_scene_tree().process_frame
	return {"closed": closed_path}


func _describe_root() -> Variant:
	var scene_root: Node = _context.get_edited_scene_root()
	if scene_root == null:
		return null
	return {"name": scene_root.name, "class": scene_root.get_class(), "child_count": scene_root.get_child_count()}

#endregion


#region Changing nodes

func _add_node(params: Dictionary) -> Variant:
	var scene_root: Node = _context.get_edited_scene_root()
	var parent: Variant = _context.find_node_in_edited_scene(String(params.get("parent_path", ".")))
	if parent is WingmanError:
		return parent

	var node_type := String(params.get("type", ""))
	var new_node: Variant = instantiate_node_type(node_type)
	if new_node is WingmanError:
		return new_node
	if params.has("name"):
		new_node.name = String(params["name"])

	# Initial properties are set before the node enters the tree, so they need no undo step.
	var initial_properties: Dictionary = params.get("properties", {}) if params.get("properties") is Dictionary else {}
	for property_path in initial_properties:
		var conversion := PropertyEditing.convert_for_property(new_node, String(property_path), initial_properties[property_path], scene_root)
		if not conversion["ok"]:
			new_node.free()
			return WingmanError.new("INVALID_PROPERTY", String(conversion["error"]))
		new_node.set_indexed(NodePath(String(property_path)), conversion["value"])

	var undo_redo: EditorUndoRedoManager = _context.get_undo_redo()
	undo_redo.create_action("Add %s" % new_node.name)
	undo_redo.add_do_method(parent, "add_child", new_node, true)
	if params.has("index"):
		undo_redo.add_do_method(parent, "move_child", new_node, int(params["index"]))
	undo_redo.add_do_property(new_node, "owner", scene_root)
	undo_redo.add_do_reference(new_node)
	undo_redo.add_undo_method(parent, "remove_child", new_node)
	undo_redo.commit_action()

	return {"added": _context.describe_node_path(new_node), "class": new_node.get_class()}


## Creates a node from a class name ("Sprite2D"), a script class ("Player") or a scene
## file ("res://enemy.tscn", which becomes an instance of that scene).
## Shared with the ui handlers (build_ui).
static func instantiate_node_type(node_type: String) -> Variant:
	if node_type == "":
		return WingmanError.new("MISSING_TYPE", "No node type given.", "Use a class like \"Sprite2D\" or a scene path like \"res://enemy.tscn\".")

	if node_type.begins_with("res://") or node_type.begins_with("uid://"):
		if not ResourceLoader.exists(node_type):
			return WingmanError.new("SCENE_NOT_FOUND", "No file at '%s'." % node_type)
		var packed_scene := load(node_type) as PackedScene
		if packed_scene == null:
			return WingmanError.new("NOT_A_SCENE", "'%s' is not a scene." % node_type)
		return packed_scene.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)

	if ClassDB.class_exists(node_type):
		if not ClassDB.is_parent_class(node_type, "Node"):
			return WingmanError.new("NOT_A_NODE", "%s is not a node class." % node_type, "Resources like materials are created with create_resource.")
		if not ClassDB.can_instantiate(node_type):
			return WingmanError.new("ABSTRACT_CLASS", "%s cannot be created directly (it is a base class)." % node_type, "Use get_class_docs to find classes that inherit from it.")
		return ClassDB.instantiate(node_type)

	for global_class in ProjectSettings.get_global_class_list():
		if String(global_class["class"]) == node_type:
			var script: Script = load(String(global_class["path"]))
			var native_base_class := script.get_instance_base_type()
			if not ClassDB.is_parent_class(native_base_class, "Node"):
				return WingmanError.new("NOT_A_NODE", "%s is not a node class." % node_type)
			var script_node: Node = ClassDB.instantiate(native_base_class)
			script_node.set_script(script)
			script_node.name = node_type
			return script_node

	return WingmanError.new("UNKNOWN_TYPE", "Unknown node type '%s'." % node_type, "Class names are case-sensitive, for example \"CharacterBody2D\". Use search_docs to find the right class.")


func _delete_nodes(params: Dictionary) -> Variant:
	var scene_root: Node = _context.get_edited_scene_root()
	var nodes_to_delete: Array[Node] = []
	for node_path in params.get("node_paths", []):
		var node: Variant = _context.find_node_in_edited_scene(String(node_path))
		if node is WingmanError:
			return node
		if node == scene_root:
			return WingmanError.new("CANNOT_DELETE_ROOT", "The scene root cannot be deleted.", "Create a new scene with create_scene instead.")
		nodes_to_delete.append(node)
	if nodes_to_delete.is_empty():
		return WingmanError.new("NOTHING_TO_DELETE", "node_paths is empty.")

	var deleted_paths: Array[String] = []
	var undo_redo: EditorUndoRedoManager = _context.get_undo_redo()
	undo_redo.create_action("Delete %d node(s)" % nodes_to_delete.size())
	for node in nodes_to_delete:
		deleted_paths.append(_context.describe_node_path(node))
		var parent := node.get_parent()
		undo_redo.add_do_method(parent, "remove_child", node)
		undo_redo.add_undo_method(parent, "add_child", node, true)
		undo_redo.add_undo_method(parent, "move_child", node, node.get_index())
		# Removing a node clears the owner of everything inside it; undo must restore them.
		for owned_node in _collect_owned_nodes(node, scene_root):
			undo_redo.add_undo_property(owned_node, "owner", scene_root)
		undo_redo.add_undo_reference(node)
	undo_redo.commit_action()
	return {"deleted": deleted_paths}


func _duplicate_node(params: Dictionary) -> Variant:
	var scene_root: Node = _context.get_edited_scene_root()
	var original: Variant = _context.find_node_in_edited_scene(String(params.get("node_path", "")))
	if original is WingmanError:
		return original
	if original == scene_root:
		return WingmanError.new("CANNOT_DUPLICATE_ROOT", "The scene root cannot be duplicated.")

	var copy: Node = original.duplicate(Node.DUPLICATE_SIGNALS | Node.DUPLICATE_GROUPS | Node.DUPLICATE_SCRIPTS | Node.DUPLICATE_USE_INSTANTIATION)
	if params.has("new_name"):
		copy.name = String(params["new_name"])
	var parent: Node = original.get_parent()

	var undo_redo: EditorUndoRedoManager = _context.get_undo_redo()
	undo_redo.create_action("Duplicate %s" % original.name)
	undo_redo.add_do_method(parent, "add_child", copy, true)
	undo_redo.add_do_method(parent, "move_child", copy, original.get_index() + 1)
	undo_redo.add_do_property(copy, "owner", scene_root)
	for copied_node in _find_copies_of_owned_nodes(original, copy, scene_root):
		undo_redo.add_do_property(copied_node, "owner", scene_root)
	undo_redo.add_do_reference(copy)
	undo_redo.add_undo_method(parent, "remove_child", copy)
	undo_redo.commit_action()
	return {"duplicate": _context.describe_node_path(copy)}


func _move_node(params: Dictionary) -> Variant:
	var scene_root: Node = _context.get_edited_scene_root()
	var node: Variant = _context.find_node_in_edited_scene(String(params.get("node_path", "")))
	if node is WingmanError:
		return node
	if node == scene_root:
		return WingmanError.new("CANNOT_MOVE_ROOT", "The scene root cannot be moved.")

	var old_parent: Node = node.get_parent()
	var old_index: int = node.get_index()
	var new_parent: Node = old_parent
	if params.has("new_parent_path"):
		var found_parent: Variant = _context.find_node_in_edited_scene(String(params["new_parent_path"]))
		if found_parent is WingmanError:
			return found_parent
		new_parent = found_parent
		if new_parent == node or node.is_ancestor_of(new_parent):
			return WingmanError.new("INVALID_PARENT", "A node cannot be moved inside itself.")

	var owned_nodes := _collect_owned_nodes(node, scene_root)
	var undo_redo: EditorUndoRedoManager = _context.get_undo_redo()
	undo_redo.create_action("Move %s" % node.name)
	if new_parent != old_parent:
		undo_redo.add_do_method(node, "reparent", new_parent, bool(params.get("keep_global_transform", true)))
		undo_redo.add_undo_method(node, "reparent", old_parent, bool(params.get("keep_global_transform", true)))
		undo_redo.add_undo_method(old_parent, "move_child", node, old_index)
		for owned_node in [node] + owned_nodes:
			undo_redo.add_do_property(owned_node, "owner", scene_root)
			undo_redo.add_undo_property(owned_node, "owner", scene_root)
	if params.has("index"):
		undo_redo.add_do_method(new_parent, "move_child", node, int(params["index"]))
		if new_parent == old_parent:
			undo_redo.add_undo_method(old_parent, "move_child", node, old_index)
	undo_redo.commit_action()
	return {"moved": _context.describe_node_path(node), "index": node.get_index()}


func _rename_node(params: Dictionary) -> Variant:
	var node: Variant = _context.find_node_in_edited_scene(String(params.get("node_path", "")))
	if node is WingmanError:
		return node
	var new_name := String(params.get("new_name", "")).validate_node_name()
	if new_name == "":
		return WingmanError.new("INVALID_NAME", "The new name is empty or only has characters that names cannot contain (. : @ / \" %).")
	var parent: Node = node.get_parent()
	if parent != null and parent.has_node(NodePath(new_name)) and parent.get_node(NodePath(new_name)) != node:
		return WingmanError.new("NAME_TAKEN", "'%s' already has a child named '%s'." % [parent.name, new_name])

	var undo_redo: EditorUndoRedoManager = _context.get_undo_redo()
	undo_redo.create_action("Rename %s to %s" % [node.name, new_name])
	undo_redo.add_do_property(node, "name", new_name)
	undo_redo.add_undo_property(node, "name", node.name)
	undo_redo.commit_action()
	return {"renamed": _context.describe_node_path(node)}


func _select_nodes(params: Dictionary) -> Variant:
	var selection := EditorInterface.get_selection()
	selection.clear()
	var selected_paths: Array[String] = []
	var last_node: Node = null
	for node_path in params.get("node_paths", []):
		var node: Variant = _context.find_node_in_edited_scene(String(node_path))
		if node is WingmanError:
			return node
		selection.add_node(node)
		selected_paths.append(_context.describe_node_path(node))
		last_node = node
	if last_node != null:
		EditorInterface.edit_node(last_node)
	return {"selected": selected_paths}


## Owned descendants of `node` (not `node` itself).
func _collect_owned_nodes(node: Node, scene_root: Node) -> Array[Node]:
	var owned_nodes: Array[Node] = []
	for child in node.get_children():
		if child.owner == scene_root:
			owned_nodes.append(child)
		owned_nodes.append_array(_collect_owned_nodes(child, scene_root))
	return owned_nodes


## Walks the original and its copy side by side and returns the copies of nodes that
## were owned by the scene root, because duplicates do not keep that owner.
func _find_copies_of_owned_nodes(original: Node, copy: Node, scene_root: Node) -> Array[Node]:
	var copies: Array[Node] = []
	var child_count := mini(original.get_child_count(), copy.get_child_count())
	for child_index in child_count:
		var original_child := original.get_child(child_index)
		var copied_child := copy.get_child(child_index)
		if original_child.owner == scene_root:
			copies.append(copied_child)
		copies.append_array(_find_copies_of_owned_nodes(original_child, copied_child, scene_root))
	return copies

#endregion


#region Batch

## Runs several scene operations in order. Each one is its own undo step.
func _batch_edit(params: Dictionary) -> Variant:
	var handlers_by_action := {
		"add_node": _add_node,
		"delete_nodes": _delete_nodes,
		"duplicate_node": _duplicate_node,
		"move_node": _move_node,
		"rename_node": _rename_node,
		"set_properties": _set_properties_for_batch,
	}
	var stop_on_error := bool(params.get("stop_on_error", true))
	var results: Array = []
	for operation in params.get("operations", []):
		if not operation is Dictionary or not handlers_by_action.has(operation.get("action")):
			results.append({"error": "Unknown action %s. Use one of: %s." % [JSON.stringify(operation.get("action") if operation is Dictionary else operation), ", ".join(handlers_by_action.keys())]})
			if stop_on_error:
				break
			continue
		var result: Variant = await handlers_by_action[operation["action"]].call(operation)
		if result is WingmanError:
			results.append({"action": operation["action"], "error": result.to_dictionary()})
			if stop_on_error:
				break
		else:
			results.append({"action": operation["action"], "result": result})
	return {"results": results, "completed": results.filter(func(entry: Dictionary) -> bool: return not entry.has("error")).size()}


func _set_properties_for_batch(params: Dictionary) -> Variant:
	var node: Variant = _context.find_node_in_edited_scene(String(params.get("node_path", "")))
	if node is WingmanError:
		return node
	var outcome := PropertyEditing.set_properties_with_undo(node, params.get("properties", {}), _context.get_undo_redo(), _context.get_edited_scene_root(), "Set properties of %s" % node.name)
	if outcome.has("errors"):
		return WingmanError.new("INVALID_PROPERTY", "; ".join(outcome["errors"]))
	return outcome

#endregion
