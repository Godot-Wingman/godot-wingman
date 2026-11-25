@tool
extends RefCounted
## Handlers that are always available: health check, editor state, running GDScript
## in the editor, reading logs, screenshots and the confirmation dialog.

const PilotError := preload("../utils/pilot_error.gd")
const ValueCodec := preload("../utils/value_codec.gd")
const ConfirmationPrompt := preload("../ui/confirmation_prompt.gd")

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
		"unsaved_scenes": Array(EditorInterface.get_unsaved_scenes()),
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

func _execute_script(params: Dictionary) -> Variant:
	var code := String(params.get("code", ""))
	if code.strip_edges() == "":
		return PilotError.new("EMPTY_CODE", "The code is empty.")

	var prepared_source := _prepare_script_source(code)
	var first_log_id: int = _context.get_next_log_id()

	var script := GDScript.new()
	script.source_code = prepared_source["source"]
	var compile_result := script.reload()
	if compile_result != OK:
		var compile_errors := _clean_script_log_entries(_context.get_logs_since(first_log_id, ["error", "script_error", "warning"]), prepared_source["line_offset"])
		return PilotError.new(
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
		return PilotError.new("NO_RUN_FUNCTION", "The script has no run() function.")

	var returned_value: Variant = await script_instance.run()

	var logged_entries: Array = _clean_script_log_entries(_context.get_logs_since(first_log_id), prepared_source["line_offset"])
	var printed_lines: Array[String] = []
	var problems: Array = []
	for entry in logged_entries:
		if entry["level"] == "info":
			printed_lines.append(entry["message"])
		else:
			problems.append(entry)

	var result := {"result": ValueCodec.to_json_value(returned_value, _context.get_edited_scene_root())}
	if script_instance.has_method("get_output_lines") and not script_instance.get_output_lines().is_empty():
		result["output"] = Array(script_instance.get_output_lines())
	if not printed_lines.is_empty():
		result["printed"] = printed_lines
	if not problems.is_empty():
		result["errors_and_warnings"] = problems
	return result


## Wraps the AI's code into a complete script. Returns the source and how many lines
## were added before the first line of the AI's code (to fix error line numbers).
func _prepare_script_source(code: String) -> Dictionary:
	var has_run_function := RegEx.create_from_string("(?m)^func\\s+run\\s*\\(").search(code) != null
	var has_extends_line := RegEx.create_from_string("(?m)^extends\\s").search(code) != null
	var has_tool_annotation := RegEx.create_from_string("(?m)^@tool").search(code) != null

	var header_lines: Array[String] = []
	# Without @tool, Godot does not run scripts inside the editor.
	if not has_tool_annotation:
		header_lines.append("@tool")
	if not has_extends_line:
		header_lines.append("extends \"%s\"" % _context.addon_directory.path_join("scripting/script_context.gd"))

	var body := code
	if not has_run_function:
		header_lines.append("func run():")
		var indented_lines: Array[String] = []
		for code_line in code.split("\n"):
			indented_lines.append("\t" + code_line)
		body = "\n".join(indented_lines)

	return {"source": "\n".join(header_lines) + "\n" + body + "\n", "line_offset": header_lines.size()}


## Makes log entries about the AI's code easy to read:
## - errors of the in-memory script ("gdscript://...") report lines of the wrapped
##   source, so they are shifted to match the lines the AI wrote;
## - the in-memory file name and the addon's own stack frames are noise, so they go.
func _clean_script_log_entries(entries: Array, line_offset: int) -> Array:
	for entry in entries:
		var file_name := String(entry.get("file", ""))
		var is_from_executed_code := file_name == "" or file_name.begins_with("gdscript://")
		if is_from_executed_code:
			entry["file"] = "<your code>"
			if entry.has("line") and int(entry["line"]) > line_offset:
				entry["line"] = int(entry["line"]) - line_offset
		if entry.has("stack"):
			var useful_frames: Array[String] = []
			for frame in entry["stack"]:
				if String(frame).contains("addons/godot_pilot/"):
					continue
				if String(frame).begins_with("gdscript://"):
					var frame_line := int(String(frame).get_slice(":", 2).get_slice(" ", 0))
					useful_frames.append("<your code>:%d" % (frame_line - line_offset))
				else:
					useful_frames.append(frame)
			if useful_frames.is_empty():
				entry.erase("stack")
			else:
				entry["stack"] = useful_frames
		entry.erase("function")
	return entries

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
		return PilotError.new(
			"NO_DISPLAY",
			"This editor runs without a window (headless), so there is nothing to capture.",
			"Open the project in a normal editor window with the launch_editor tool."
		)

	# Wait until the current frame is drawn so the picture is up to date.
	await RenderingServer.frame_post_draw

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
			return PilotError.new("INVALID_VIEW", "Unknown view '%s'." % view, "Use \"editor\", \"2d\" or \"3d\".")

	if image == null or image.is_empty():
		return PilotError.new("EMPTY_IMAGE", "The %s view returned an empty image." % view, "Switch the editor to that view first, or capture \"editor\".")

	return encode_image(image, params)


## Scales the image down to `max_size` and encodes it. Shared with other handlers.
static func encode_image(image: Image, params: Dictionary) -> Dictionary:
	var max_size := int(params.get("max_size", DEFAULT_SCREENSHOT_MAX_SIZE))
	var longest_side := maxi(image.get_width(), image.get_height())
	if max_size > 0 and longest_side > max_size:
		var scale_factor := float(max_size) / float(longest_side)
		image.resize(
			maxi(1, roundi(image.get_width() * scale_factor)),
			maxi(1, roundi(image.get_height() * scale_factor)),
			Image.INTERPOLATE_LANCZOS
		)

	var format := String(params.get("format", "jpeg"))
	var encoded_bytes: PackedByteArray
	var mime_type := "image/jpeg"
	if format == "png":
		encoded_bytes = image.save_png_to_buffer()
		mime_type = "image/png"
	elif format == "webp":
		encoded_bytes = image.save_webp_to_buffer(true, float(params.get("quality", DEFAULT_JPEG_QUALITY)))
		mime_type = "image/webp"
	else:
		image.convert(Image.FORMAT_RGB8)
		encoded_bytes = image.save_jpg_to_buffer(float(params.get("quality", DEFAULT_JPEG_QUALITY)))

	return {
		"mime_type": mime_type,
		"data_base64": Marshalls.raw_to_base64(encoded_bytes),
		"width": image.get_width(),
		"height": image.get_height(),
	}

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

	return PilotError.new(
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
