extends Node
## Runs inside the game while it is started from the Godot editor, and lets the AI
## look at the game and play it.
##
## The editor adds this script as a temporary autoload right before the game starts
## and removes it when the game stops. It talks to the editor over Godot's own
## debugger connection (EngineDebugger), so it opens no network port. In a game that
## is not started from the editor (exported or run by hand) there is no debugger, and
## this node removes itself immediately.

const CAPTURE_NAME := "godot_wingman"
const WingmanError := preload("../utils/wingman_error.gd")
const NodeSearch := preload("../utils/node_search.gd")
const ValueCodec := preload("../utils/value_codec.gd")
const ImageEncoding := preload("../utils/image_encoding.gd")
const ScriptSource := preload("../utils/script_source.gd")
const InputSequencePlayer := preload("input_sequence_player.gd")

const DEFAULT_TREE_DEPTH := 6
const MAX_TREE_NODES := 600
const MAX_UI_ELEMENTS := 200
const MAX_CAPTURED_FRAMES := 12
## Shown by get_game_properties when no names are given, if the node has them.
const COMMON_PROPERTY_NAMES := ["position", "global_position", "rotation", "scale", "velocity", "visible", "text", "modulate", "current_animation"]

var _log_capture: Object
var _handlers_by_method: Dictionary = {}
var _input_player: InputSequencePlayer


func _ready() -> void:
	if not EngineDebugger.is_active():
		queue_free()
		return
	# Keep answering while the game is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_start_log_capture()
	_input_player = InputSequencePlayer.new(get_tree(), self)
	_register_handlers()
	EngineDebugger.register_message_capture(CAPTURE_NAME, _on_debugger_message)
	EngineDebugger.send_message("%s:ready" % CAPTURE_NAME, [OS.get_process_id()])


func _exit_tree() -> void:
	if EngineDebugger.has_capture(CAPTURE_NAME):
		EngineDebugger.unregister_message_capture(CAPTURE_NAME)
	if _log_capture != null and OS.has_method("remove_logger"):
		OS.call("remove_logger", _log_capture)


func _start_log_capture() -> void:
	if not ClassDB.class_exists("Logger") or not OS.has_method("add_logger"):
		return
	# This script lives in addons/godot_wingman/runtime; the logger is in addons/godot_wingman/logging.
	var addon_directory: String = get_script().resource_path.get_base_dir().get_base_dir()
	_log_capture = load(addon_directory.path_join("logging/log_capture.gd")).new()
	OS.call("add_logger", _log_capture)


func _register_handlers() -> void:
	_handlers_by_method = {
		"get_state": _get_state,
		"get_tree": _get_game_tree,
		"get_properties": _get_properties,
		"set_properties": _set_properties,
		"call_method": _call_method,
		"execute_script": _execute_script,
		"screenshot": _screenshot,
		"capture_frames": _capture_frames,
		"list_ui_elements": _list_ui_elements,
		"play_input": _play_input,
		"click_ui_element": _click_ui_element,
		"wait_until": _wait_until,
		"wait": _wait,
		"set_paused": _set_paused,
		"step_frames": _step_frames,
		"set_time_scale": _set_time_scale,
		"get_logs": _get_logs,
		"get_performance": _get_performance,
	}


## Called by Godot for every debugger message starting with "godot_wingman:".
func _on_debugger_message(message: String, data: Array) -> bool:
	if message != "request" or data.size() < 3:
		return false
	_run_request(int(data[0]), String(data[1]), data[2] if data[2] is Dictionary else {})
	return true


func _run_request(request_id: int, method_name: String, params: Dictionary) -> void:
	var result: Variant
	if _handlers_by_method.has(method_name):
		result = await _handlers_by_method[method_name].call(params)
	else:
		result = WingmanError.new("UNKNOWN_METHOD", "The game bridge does not know '%s'." % method_name)
	if result is WingmanError:
		EngineDebugger.send_message("%s:response" % CAPTURE_NAME, [request_id, false, result.to_dictionary()])
	else:
		EngineDebugger.send_message("%s:response" % CAPTURE_NAME, [request_id, true, result])


#region Finding nodes

## "." or "" = current scene, "Player/Sprite2D" = relative to it, "/root/GameState" = absolute.
func _find_node(node_path: String) -> Variant:
	var current_scene := get_tree().current_scene
	var found_node: Node = null
	if node_path.begins_with("/"):
		found_node = get_tree().root.get_node_or_null(NodePath(node_path))
	elif node_path == "" or node_path == ".":
		found_node = current_scene
	elif current_scene != null:
		found_node = current_scene.get_node_or_null(NodePath(node_path))
	if found_node == null:
		var hint := "Use get_game_tree to see the live nodes. Paths are relative to the current scene; use /root/Name for autoloads."
		var similar_paths: Array[String] = []
		if current_scene != null:
			similar_paths = NodeSearch.find_similar_node_paths(current_scene, node_path)
		if not similar_paths.is_empty():
			hint = "Did you mean: %s? " % ", ".join(similar_paths) + hint
		return WingmanError.new("NODE_NOT_FOUND", "No node at '%s' in the running game." % node_path, hint)
	return found_node


func _describe_path(node: Node) -> String:
	var current_scene := get_tree().current_scene
	if current_scene != null and (node == current_scene or current_scene.is_ancestor_of(node)):
		return String(current_scene.get_path_to(node))
	return String(node.get_path())

#endregion


#region Looking at the game

func _get_state(_params: Dictionary) -> Dictionary:
	var current_scene := get_tree().current_scene
	return {
		"current_scene": current_scene.scene_file_path if current_scene != null else null,
		"paused": get_tree().paused,
		"time_scale": Engine.time_scale,
		"fps": Engine.get_frames_per_second(),
		"frames_drawn": Engine.get_frames_drawn(),
		"seconds_running": Time.get_ticks_msec() / 1000.0,
		"viewport_size": var_to_str(get_viewport().get_visible_rect().size),
		"headless": DisplayServer.get_name() == "headless",
	}


func _get_game_tree(params: Dictionary) -> Variant:
	var start_node: Variant = _find_node(String(params.get("node_path", ".")))
	if start_node is WingmanError:
		return start_node
	var tree_lines: Array[String] = []
	_append_tree_lines(start_node, 0, int(params.get("max_depth", DEFAULT_TREE_DEPTH)), tree_lines)
	var autoload_names: Array[String] = []
	for root_child in get_tree().root.get_children():
		if root_child != get_tree().current_scene and root_child != self:
			autoload_names.append(String(root_child.name))
	return {"tree": "\n".join(tree_lines), "autoloads": autoload_names}


func _append_tree_lines(node: Node, depth: int, max_depth: int, tree_lines: Array[String]) -> void:
	if tree_lines.size() >= MAX_TREE_NODES:
		return
	var line := "%s (%s)" % [node.name, node.get_class()]
	if node is Node2D or node is Node3D:
		line += " at %s" % var_to_str(node.global_position)
	if "visible" in node and node.get("visible") == false:
		line += " hidden"
	tree_lines.append("  ".repeat(depth) + line)
	if depth >= max_depth:
		if node.get_child_count() > 0:
			tree_lines.append("  ".repeat(depth + 1) + "... %d children" % node.get_child_count())
		return
	for child in node.get_children():
		_append_tree_lines(child, depth + 1, max_depth, tree_lines)


func _get_properties(params: Dictionary) -> Variant:
	var node: Variant = _find_node(String(params.get("node_path", ".")))
	if node is WingmanError:
		return node
	var requested_names: Array = params.get("names", []) if params.get("names") is Array else []
	var name_filter := String(params.get("filter", "")).to_lower()
	var values := {}
	for property in node.get_property_list():
		var property_name := String(property["name"])
		var is_script_variable := int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE != 0
		var is_wanted := false
		if not requested_names.is_empty():
			is_wanted = requested_names.has(property_name)
		elif name_filter != "":
			is_wanted = property_name.to_lower().contains(name_filter) and int(property["usage"]) & PROPERTY_USAGE_EDITOR != 0
		else:
			is_wanted = is_script_variable or COMMON_PROPERTY_NAMES.has(property_name)
		if is_wanted:
			values[property_name] = ValueCodec.to_json_value(node.get(property_name), get_tree().current_scene)
	return {"node": _describe_path(node), "class": node.get_class(), "values": values}


func _screenshot(params: Dictionary) -> Variant:
	if DisplayServer.get_name() == "headless":
		return WingmanError.new("NO_DISPLAY", "The game runs headless, so there is no picture.", "Run the game with a window.")
	await RenderingServer.frame_post_draw
	var encoded := ImageEncoding.encode_bytes(get_viewport().get_texture().get_image(), params)
	encoded["viewport_size"] = var_to_str(get_viewport().get_visible_rect().size)
	return encoded


## Several screenshots over time, to see movement and animation.
func _capture_frames(params: Dictionary) -> Variant:
	if DisplayServer.get_name() == "headless":
		return WingmanError.new("NO_DISPLAY", "The game runs headless, so there is no picture.")
	var frame_count := clampi(int(params.get("count", 4)), 2, MAX_CAPTURED_FRAMES)
	var interval_seconds := maxf(float(params.get("interval_seconds", 0.25)), 0.0)
	var frames: Array = []
	for frame_index in frame_count:
		if frame_index > 0:
			await get_tree().create_timer(interval_seconds, true, false, true).timeout
		await RenderingServer.frame_post_draw
		var encoded := ImageEncoding.encode_bytes(get_viewport().get_texture().get_image(), params)
		encoded["seconds"] = snappedf(frame_index * interval_seconds, 0.01)
		frames.append(encoded)
	return {"frames": frames, "viewport_size": var_to_str(get_viewport().get_visible_rect().size)}


## Visible buttons, labels and other controls with their text and screen rectangle, so
## the AI can find what to click without guessing coordinates.
func _list_ui_elements(params: Dictionary) -> Dictionary:
	var include_hidden := bool(params.get("include_hidden", false))
	var elements: Array = []
	for control in get_tree().root.find_children("*", "Control", true, false):
		if elements.size() >= MAX_UI_ELEMENTS:
			break
		if not include_hidden and not control.is_visible_in_tree():
			continue
		var element := {"path": _describe_path(control), "class": control.get_class(), "rect": var_to_str(control.get_global_rect())}
		if "text" in control and String(control.get("text")) != "":
			element["text"] = String(control.get("text"))
		if control is BaseButton:
			element["disabled"] = control.disabled
		elements.append(element)
	return {"elements": elements}

#endregion


#region Changing the game

func _set_properties(params: Dictionary) -> Variant:
	var node: Variant = _find_node(String(params.get("node_path", ".")))
	if node is WingmanError:
		return node
	var changed := {}
	var new_values: Dictionary = params.get("properties", {}) if params.get("properties") is Dictionary else {}
	for property_path in new_values:
		var current_value: Variant = node.get_indexed(NodePath(String(property_path)))
		var value_class: String = current_value.get_class() if current_value is Object else ""
		var conversion := ValueCodec.from_json_value(new_values[property_path], typeof(current_value), value_class, get_tree().current_scene)
		if not conversion["ok"]:
			return WingmanError.new("INVALID_VALUE", "%s: %s" % [property_path, conversion["error"]])
		node.set_indexed(NodePath(String(property_path)), conversion["value"])
		changed[property_path] = ValueCodec.to_json_value(node.get_indexed(NodePath(String(property_path))))
	return {"node": _describe_path(node), "changed": changed}


func _call_method(params: Dictionary) -> Variant:
	var node: Variant = _find_node(String(params.get("node_path", ".")))
	if node is WingmanError:
		return node
	var method_name := String(params.get("method", ""))
	if not node.has_method(method_name):
		return WingmanError.new("METHOD_NOT_FOUND", "%s has no method '%s'." % [node.name, method_name])
	var arguments: Array = []
	for argument in params.get("arguments", []):
		arguments.append(ValueCodec.from_json_value(argument, TYPE_NIL)["value"])
	var returned_value: Variant = await node.callv(method_name, arguments)
	return {"result": ValueCodec.to_json_value(returned_value, get_tree().current_scene)}


func _execute_script(params: Dictionary) -> Variant:
	var code := String(params.get("code", ""))
	var base_script_path: String = get_script().resource_path.get_base_dir().path_join("game_script_context.gd")
	var prepared_source := ScriptSource.prepare(code, base_script_path, false)
	var first_log_id := _next_log_id()

	var script := GDScript.new()
	script.source_code = prepared_source["source"]
	var compile_result := script.reload()
	if compile_result != OK:
		return WingmanError.new(
			"SCRIPT_COMPILE_ERROR",
			"The code did not compile (%s)." % error_string(compile_result),
			"Line numbers refer to your code. Use tabs for indentation.",
			ScriptSource.clean_log_entries(_logs_since(first_log_id), prepared_source["line_offset"])
		)

	var script_instance: RefCounted = script.new()
	if "tree" in script_instance:
		script_instance.tree = get_tree()
		script_instance.root = get_tree().root
		script_instance.scene = get_tree().current_scene
	var returned_value: Variant = await script_instance.run()

	var log_summary := ScriptSource.split_printed_and_problems(ScriptSource.clean_log_entries(_logs_since(first_log_id), prepared_source["line_offset"]))
	var result := {"result": ValueCodec.to_json_value(returned_value, get_tree().current_scene)}
	if script_instance.has_method("get_output_lines") and not script_instance.get_output_lines().is_empty():
		result["output"] = Array(script_instance.get_output_lines())
	if not log_summary["printed"].is_empty():
		result["printed"] = log_summary["printed"]
	if not log_summary["problems"].is_empty():
		result["errors_and_warnings"] = log_summary["problems"]
	return result

#endregion


#region Playing

func _play_input(params: Dictionary) -> Variant:
	var outcome: Dictionary = await _input_player.play(params.get("steps", []))
	if outcome.has("error"):
		return WingmanError.new("INVALID_INPUT_STEP", String(outcome["error"]), "", outcome.get("performed"))
	return outcome


func _click_ui_element(params: Dictionary) -> Variant:
	var target: Control = null
	if params.has("node_path"):
		var found: Variant = _find_node(String(params["node_path"]))
		if found is WingmanError:
			return found
		target = found as Control
	elif params.has("text"):
		var wanted_text := String(params["text"]).to_lower()
		for control in get_tree().root.find_children("*", "Control", true, false):
			if control.is_visible_in_tree() and "text" in control and String(control.get("text")).to_lower() == wanted_text:
				target = control
				break
	if target == null:
		return WingmanError.new("UI_ELEMENT_NOT_FOUND", "No visible control matches.", "Use list_ui_elements to see the controls and their text.")
	var center := target.get_global_rect().get_center()
	return await _input_player.play([{"mouse_click": [center.x, center.y]}])


## Waits until a GDScript expression is true, checking every frame. The expression can
## use `scene`, `tree` and node("path"), for example: node("Player").is_on_floor()
func _wait_until(params: Dictionary) -> Variant:
	var condition := String(params.get("condition", ""))
	var expression := Expression.new()
	if expression.parse(condition, ["scene", "tree"]) != OK:
		return WingmanError.new("INVALID_EXPRESSION", "Could not parse '%s': %s" % [condition, expression.get_error_text()])
	var timeout_seconds := float(params.get("timeout_seconds", 10.0))
	var start_milliseconds := Time.get_ticks_msec()
	var last_value: Variant = null
	while (Time.get_ticks_msec() - start_milliseconds) / 1000.0 < timeout_seconds:
		last_value = expression.execute([get_tree().current_scene, get_tree()], self, false)
		if expression.has_execute_failed():
			return WingmanError.new("EXPRESSION_FAILED", "'%s' failed: %s" % [condition, expression.get_error_text()])
		if last_value:
			return {"met": true, "after_seconds": snappedf((Time.get_ticks_msec() - start_milliseconds) / 1000.0, 0.01)}
		await get_tree().process_frame
	return {"met": false, "timeout_seconds": timeout_seconds, "last_value": ValueCodec.to_json_value(last_value)}


## Used inside wait_until expressions: node("Player") finds a node of the current scene.
func node(node_path: String) -> Node:
	var found: Variant = _find_node(node_path)
	return found if found is Node else null


func _wait(params: Dictionary) -> Dictionary:
	if params.has("frames"):
		for frame_index in int(params["frames"]):
			await get_tree().process_frame
		return {"waited_frames": int(params["frames"])}
	var seconds := float(params.get("seconds", 1.0))
	await get_tree().create_timer(seconds, true, false, true).timeout
	return {"waited_seconds": seconds}


func _set_paused(params: Dictionary) -> Dictionary:
	get_tree().paused = bool(params.get("paused", true))
	return {"paused": get_tree().paused}


## Runs the paused game for exactly `count` physics frames, then pauses it again.
func _step_frames(params: Dictionary) -> Dictionary:
	var frame_count := maxi(int(params.get("count", 1)), 1)
	get_tree().paused = false
	for frame_index in frame_count:
		await get_tree().physics_frame
	get_tree().paused = true
	return {"stepped_frames": frame_count, "paused": true}


func _set_time_scale(params: Dictionary) -> Dictionary:
	Engine.time_scale = clampf(float(params.get("time_scale", 1.0)), 0.0, 100.0)
	return {"time_scale": Engine.time_scale}

#endregion


#region Diagnostics

func _get_logs(params: Dictionary) -> Dictionary:
	if _log_capture == null:
		return {"captured": false, "entries": [], "note": "Log capture needs Godot 4.5 or newer."}
	var levels: Array = params.get("levels", []) if params.get("levels") is Array else []
	return {
		"captured": true,
		"entries": _log_capture.get_entries(int(params.get("from_id", 0)), levels, String(params.get("search", "")), int(params.get("limit", 100))),
		"next_id": _next_log_id(),
	}


func _get_performance(_params: Dictionary) -> Dictionary:
	return {
		"fps": Performance.get_monitor(Performance.TIME_FPS),
		"frame_time_ms": snappedf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.01),
		"physics_time_ms": snappedf(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, 0.01),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"orphan_nodes": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		"objects": Performance.get_monitor(Performance.OBJECT_COUNT),
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"memory_static_mb": snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1),
		"video_memory_mb": snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1),
		"physics_2d_active_objects": Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS),
		"physics_3d_active_objects": Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),
	}


func _next_log_id() -> int:
	return _log_capture.get_next_entry_id() if _log_capture != null else 0


func _logs_since(from_id: int) -> Array:
	return _log_capture.get_entries(from_id, [], "", 0) if _log_capture != null else []

#endregion
