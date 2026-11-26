@tool
extends RefCounted
## Handlers that are always available: health check, editor state, running GDScript
## in the editor, reading logs, screenshots and the confirmation dialog.

const WingmanError := preload("../utils/wingman_error.gd")
const ValueCodec := preload("../utils/value_codec.gd")
const ConfirmationPrompt := preload("../ui/confirmation_prompt.gd")
const ImageEncoding := preload("../utils/image_encoding.gd")
const ScriptSource := preload("../utils/script_source.gd")
const FrameWaiter := preload("../utils/frame_waiter.gd")

const DEFAULT_LOG_LIMIT := 100
const DEFAULT_SCREENSHOT_MAX_SIZE := 1280
const DEFAULT_JPEG_QUALITY := 0.8

var _context: RefCounted


func _init(context: RefCounted) -> void:
	_context = context


func register_methods(dispatcher: RefCounted) -> void:
	dispatcher.register_method("ping", _ping)
	dispatcher.register_method("get_editor_state", _get_editor_state)
	dispatcher.register_method("execute_script", _execute_script)
	dispatcher.register_method("check_game_script", _check_game_script)
	dispatcher.register_method("get_logs", _get_logs)
	dispatcher.register_method("take_screenshot", _take_screenshot)
	dispatcher.register_method("confirm_action", _confirm_action)
	dispatcher.register_method("get_class_info", _get_class_info)


func _ping(_params: Dictionary) -> Dictionary:
	return {"pong": true, "addon_version": _context.addon_version}


func _get_editor_state(_params: Dictionary) -> Dictionary:
	var scene_root: Node = _context.get_edited_scene_root()
	var selected_node_paths: Array[String] = []
	for selected_node in EditorInterface.get_selection().get_selected_nodes():
		selected_node_paths.append(_context.describe_node_path(selected_node))

	return {
		"project_name": ProjectSettings.get_setting("application/config/name", ""),
		"project_path": ProjectSettings.globalize_path("res://"),
		"godot_version": Engine.get_version_info().string,
		"addon_version": _context.addon_version,
		"edited_scene": scene_root.scene_file_path if scene_root != null else null,
		"edited_scene_root": {"name": scene_root.name, "class": scene_root.get_class()} if scene_root != null else null,
		"open_scenes": Array(EditorInterface.get_open_scenes()),
		"unsaved_scenes": Array(_context.call_editor_interface("get_unsaved_scenes", [], PackedStringArray())),
		"selected_nodes": selected_node_paths,
		"is_playing": EditorInterface.is_playing_scene(),
		"playing_scene": EditorInterface.get_playing_scene(),
		"main_scene": ProjectSettings.get_setting("application/run/main_scene", ""),
		"headless": DisplayServer.get_name() == "headless",
		"logs_captured": _context.log_capture != null,
		"csharp_available": ClassDB.class_exists("CSharpScript"),
		"gdextensions": Array(GDExtensionManager.get_loaded_extensions()),
	}


#region execute_script

## Compiles code meant for the running game (execute_game_script) without running it.
## In a game started from the editor, a parse error stops the whole game in Godot's
## debugger until someone presses Continue, so the code is checked here first.
func _check_game_script(params: Dictionary) -> Variant:
	var code := String(params.get("code", ""))
	if code.strip_edges() == "":
		return WingmanError.new("EMPTY_CODE", "The code is empty.")

	var prepared_source := ScriptSource.prepare(code, _context.addon_directory.path_join("runtime/game_script_context.gd"), false)
	var first_log_id: int = _context.get_next_log_id()
	var script := GDScript.new()
	script.source_code = prepared_source["source"]
	var compile_result := script.reload()
	if compile_result == OK:
		return {"compiles": true}
	var compile_errors := ScriptSource.clean_log_entries(_context.get_logs_since(first_log_id, ["error", "script_error", "warning"]), prepared_source["line_offset"])
	return WingmanError.new(
		"SCRIPT_COMPILE_ERROR",
		"The code did not compile (%s), so it was not sent to the game." % error_string(compile_result),
		"Line numbers refer to your code. The code is the body of `func run():` unless you write `func run():` yourself. Use tabs for indentation inside blocks.",
		compile_errors
	)


func _execute_script(params: Dictionary) -> Variant:
	var code := String(params.get("code", ""))
	if code.strip_edges() == "":
		return WingmanError.new("EMPTY_CODE", "The code is empty.")

	var prepared_source := ScriptSource.prepare(code, _context.addon_directory.path_join("scripting/script_context.gd"), true)
	var first_log_id: int = _context.get_next_log_id()

	var script := GDScript.new()
	script.source_code = prepared_source["source"]
	var compile_result := script.reload()
	if compile_result != OK:
		var compile_errors := ScriptSource.clean_log_entries(_context.get_logs_since(first_log_id, ["error", "script_error", "warning"]), prepared_source["line_offset"])
		return WingmanError.new(
			"SCRIPT_COMPILE_ERROR",
			"The code did not compile (%s)." % error_string(compile_result),
			"Line numbers refer to your code. The code is the body of `func run():` unless you write `func run():` yourself. Use tabs for indentation inside blocks.",
			compile_errors
		)

	var script_instance: RefCounted = script.new()
	if "editor" in script_instance:
		script_instance.editor = EditorInterface
		script_instance.scene_root = _context.get_edited_scene_root()
		script_instance.undo_redo = _context.get_undo_redo()
		script_instance.tree = _context.get_scene_tree()

	if not script_instance.has_method("run"):
		return WingmanError.new("NO_RUN_FUNCTION", "The script has no run() function.")

	var returned_value: Variant = await script_instance.run()

	var log_summary := ScriptSource.split_printed_and_problems(ScriptSource.clean_log_entries(_context.get_logs_since(first_log_id), prepared_source["line_offset"]))
	var printed_lines: Array = log_summary["printed"]
	var problems: Array = log_summary["problems"]

	var result := {"result": ValueCodec.to_json_value(returned_value, _context.get_edited_scene_root())}
	if script_instance.has_method("get_output_lines") and not script_instance.get_output_lines().is_empty():
		result["output"] = Array(script_instance.get_output_lines())
	if not printed_lines.is_empty():
		result["printed"] = printed_lines
	if not problems.is_empty():
		result["errors_and_warnings"] = problems
	return result


#endregion


func _get_logs(params: Dictionary) -> Dictionary:
	if _context.log_capture == null:
		return {
			"captured": false,
			"entries": [],
			"note": "Log capture needs Godot 4.5 or newer. Look at the Output panel in a screenshot instead.",
		}
	var levels: Array = params.get("levels", []) if params.get("levels") is Array else []
	var entries: Array = _context.log_capture.get_entries(
		int(params.get("from_id", 0)),
		levels,
		String(params.get("search", "")),
		int(params.get("limit", DEFAULT_LOG_LIMIT))
	)
	return {"captured": true, "entries": entries, "next_id": _context.get_next_log_id()}


#region take_screenshot

func _take_screenshot(params: Dictionary) -> Variant:
	if DisplayServer.get_name() == "headless":
		return WingmanError.new(
			"NO_DISPLAY",
			"This editor runs without a window (headless), so there is nothing to capture.",
			"Open the project in a normal editor window with the launch_editor tool."
		)

	# Wait until the current frame is drawn so the picture is up to date.
	await FrameWaiter.wait_for_drawn_frame(_context.get_scene_tree())

	var view := String(params.get("view", "editor"))
	var image: Image
	match view:
		"2d":
			image = EditorInterface.get_editor_viewport_2d().get_texture().get_image()
		"3d":
			image = EditorInterface.get_editor_viewport_3d(int(params.get("viewport_index", 0))).get_texture().get_image()
		"editor":
			image = EditorInterface.get_base_control().get_viewport().get_texture().get_image()
		_:
			return WingmanError.new("INVALID_VIEW", "Unknown view '%s'." % view, "Use \"editor\", \"2d\" or \"3d\".")

	if image == null or image.is_empty():
		return WingmanError.new("EMPTY_IMAGE", "The %s view returned an empty image." % view, "Switch the editor to that view first, or capture \"editor\".")

	return encode_image(image, params)


## Scales the image down to `max_size` and encodes it. Shared with other handlers.
static func encode_image(image: Image, params: Dictionary) -> Dictionary:
	var encoded := ImageEncoding.encode_bytes(image, params)
	encoded["data_base64"] = Marshalls.raw_to_base64(encoded["bytes"])
	encoded.erase("bytes")
	return encoded
#endregion


#region get_class_info

## Describes a class from the running engine. Unlike the offline documentation, this
## also knows classes added by GDExtensions (Rust, C++...) and scripts with class_name.
func _get_class_info(params: Dictionary) -> Variant:
	var requested_class := String(params.get("class_name", ""))
	if ClassDB.class_exists(requested_class):
		var property_names_seen := {}
		var properties: Array[String] = []
		for property in ClassDB.class_get_property_list(requested_class, true):
			if _is_real_property(property) and not property_names_seen.has(property["name"]):
				property_names_seen[property["name"]] = true
				properties.append("%s: %s" % [property["name"], describe_property_type(property)])
		var methods: Array[String] = []
		for method in ClassDB.class_get_method_list(requested_class, true):
			methods.append(describe_method(method))
		var signals: Array[String] = []
		for signal_information in ClassDB.class_get_signal_list(requested_class, true):
			signals.append(describe_method(signal_information, false))
		return {
			"class": requested_class,
			"source": "engine or GDExtension (ClassDB)",
			"inherits": ClassDB.get_parent_class(requested_class),
			"can_instantiate": ClassDB.can_instantiate(requested_class),
			"properties": properties,
			"methods": methods,
			"signals": signals,
		}

	for global_class in ProjectSettings.get_global_class_list():
		if String(global_class["class"]) != requested_class:
			continue
		var script: Script = load(String(global_class["path"]))
		var script_properties: Array[String] = []
		for property in script.get_script_property_list():
			if _is_real_property(property):
				script_properties.append("%s: %s" % [property["name"], describe_property_type(property)])
		var script_methods: Array[String] = []
		for method in script.get_script_method_list():
			script_methods.append(describe_method(method))
		var script_signals: Array[String] = []
		for signal_information in script.get_script_signal_list():
			script_signals.append(describe_method(signal_information, false))
		return {
			"class": requested_class,
			"source": "script with class_name",
			"path": global_class["path"],
			"language": global_class["language"],
			"inherits": global_class["base"],
			"properties": script_properties,
			"methods": script_methods,
			"signals": script_signals,
		}

	return WingmanError.new(
		"CLASS_NOT_FOUND",
		"No class named '%s' exists in the engine, in GDExtensions or in scripts with class_name." % requested_class,
		"Class names are case-sensitive. Use search_docs to find the right name."
	)


## Property lists also contain group and category headers; those are not properties.
static func _is_real_property(property: Dictionary) -> bool:
	var header_usage := PROPERTY_USAGE_CATEGORY | PROPERTY_USAGE_GROUP | PROPERTY_USAGE_SUBGROUP
	return int(property["usage"]) & header_usage == 0


## "Vector2", "Texture2D", "Array[Node]"... for a property or argument dictionary.
static func describe_property_type(property: Dictionary) -> String:
	var variant_type := int(property.get("type", TYPE_NIL))
	var type_class := String(property.get("class_name", ""))
	if variant_type == TYPE_OBJECT:
		return type_class if type_class != "" else "Object"
	if variant_type == TYPE_NIL:
		return "Variant"
	if variant_type == TYPE_ARRAY and int(property.get("hint", 0)) == PROPERTY_HINT_ARRAY_TYPE:
		return "Array[%s]" % property.get("hint_string", "")
	if type_class != "" and variant_type == TYPE_INT:
		return type_class  # an enum
	return type_string(variant_type)


## "move_toward(target: Vector2, delta: float) -> Vector2"
static func describe_method(method: Dictionary, include_return_type: bool = true) -> String:
	var argument_descriptions: Array[String] = []
	for argument in method.get("args", []):
		argument_descriptions.append("%s: %s" % [argument["name"], describe_property_type(argument)])
	var signature := "%s(%s)" % [method["name"], ", ".join(argument_descriptions)]
	if include_return_type and method.has("return"):
		var return_information: Dictionary = method["return"]
		var returns_nothing := int(return_information.get("type", TYPE_NIL)) == TYPE_NIL \
			and int(return_information.get("usage", 0)) & PROPERTY_USAGE_NIL_IS_VARIANT == 0
		signature += " -> %s" % ("void" if returns_nothing else describe_property_type(return_information))
	return signature

#endregion


func _confirm_action(params: Dictionary) -> Dictionary:
	var allowed: bool = await ConfirmationPrompt.ask(
		String(params.get("title", "Change the project")),
		String(params.get("description", "")),
		float(params.get("timeout_seconds", ConfirmationPrompt.DEFAULT_TIMEOUT_SECONDS))
	)
	return {"allowed": allowed}
