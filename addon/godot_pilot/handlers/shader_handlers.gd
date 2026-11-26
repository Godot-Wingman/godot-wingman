@tool
extends RefCounted
## Handlers of the "shader" toolset: writing .gdshader files (with Godot's compile errors
## when a renderer is available), reading their uniforms, and setting the uniform values
## of ShaderMaterials.

const PilotError := preload("../utils/pilot_error.gd")
const ValueCodec := preload("../utils/value_codec.gd")

## Starting code for a new shader of each type.
const SHADER_TEMPLATES := {
	"canvas_item": "shader_type canvas_item;\n\nuniform vec4 tint : source_color = vec4(1.0);\n\nvoid fragment() {\n\tCOLOR = texture(TEXTURE, UV) * tint;\n}\n",
	"spatial": "shader_type spatial;\n\nuniform vec4 albedo : source_color = vec4(1.0);\nuniform float roughness : hint_range(0.0, 1.0) = 0.8;\n\nvoid fragment() {\n\tALBEDO = albedo.rgb;\n\tROUGHNESS = roughness;\n}\n",
	"particles": "shader_type particles;\n\nvoid start() {\n\tVELOCITY = vec3(0.0, 1.0, 0.0);\n}\n\nvoid process() {\n}\n",
	"sky": "shader_type sky;\n\nuniform vec3 top_color : source_color = vec3(0.3, 0.5, 0.9);\nuniform vec3 bottom_color : source_color = vec3(0.8, 0.85, 0.9);\n\nvoid sky() {\n\tCOLOR = mix(bottom_color, top_color, clamp(EYEDIR.y, 0.0, 1.0));\n}\n",
	"fog": "shader_type fog;\n\nuniform float density = 0.5;\n\nvoid fog() {\n\tDENSITY = density;\n}\n",
}
## Godot shading language types and the Variant type their values have.
const UNIFORM_VALUE_TYPES := {
	"bool": TYPE_BOOL, "int": TYPE_INT, "uint": TYPE_INT, "float": TYPE_FLOAT,
	"vec2": TYPE_VECTOR2, "vec3": TYPE_VECTOR3, "vec4": TYPE_VECTOR4,
	"ivec2": TYPE_VECTOR2I, "ivec3": TYPE_VECTOR3I, "ivec4": TYPE_VECTOR4I,
	"mat2": TYPE_NIL, "mat3": TYPE_BASIS, "mat4": TYPE_PROJECTION,
	"sampler2D": TYPE_OBJECT, "sampler2DArray": TYPE_OBJECT, "sampler3D": TYPE_OBJECT, "samplerCube": TYPE_OBJECT,
	"isampler2D": TYPE_OBJECT, "usampler2D": TYPE_OBJECT,
}

var _context: RefCounted
var _uniform_pattern := RegEx.create_from_string("(?m)^\\s*(?:global\\s+|instance\\s+)?uniform\\s+(?:(?:lowp|mediump|highp)\\s+)?(\\w+)\\s+(\\w+)\\s*(?:\\[[^\\]]*\\])?\\s*(?::\\s*([^=;]+?))?\\s*(?:=\\s*([^;]+))?;")
var _shader_type_pattern := RegEx.create_from_string("shader_type\\s+(\\w+)\\s*;")


func _init(context: RefCounted) -> void:
	_context = context


func register_methods(dispatcher: RefCounted) -> void:
	dispatcher.register_method("write_shader", _write_shader)
	dispatcher.register_method("get_shader_info", _get_shader_info)
	dispatcher.register_method("set_shader_parameters", _set_shader_parameters)


## Creates or replaces a .gdshader file, reports compile errors, and can put the shader on
## a node (in a new ShaderMaterial) in the same step.
func _write_shader(params: Dictionary) -> Variant:
	var shader_path := String(params.get("path", ""))
	if not shader_path.begins_with("res://") or shader_path.get_extension() != "gdshader":
		return PilotError.new("INVALID_PATH", "The path must be a res:// path ending in .gdshader, for example \"res://shaders/outline.gdshader\".")
	var code := String(params.get("code", ""))
	if code == "":
		var template_name := String(params.get("template", "canvas_item"))
		if not SHADER_TEMPLATES.has(template_name):
			return PilotError.new("INVALID_TEMPLATE", "Unknown template '%s'." % template_name, "Use one of: %s, or pass code." % ", ".join(SHADER_TEMPLATES.keys()))
		code = SHADER_TEMPLATES[template_name]
	if _shader_type_pattern.search(code) == null:
		return PilotError.new("MISSING_SHADER_TYPE", "The code must start with a shader_type line, for example \"shader_type canvas_item;\".")

	var shader: Shader = load(shader_path) if ResourceLoader.exists(shader_path) else Shader.new()
	var first_log_id: int = _context.get_next_log_id()
	shader.code = code
	# Asking for the uniforms makes the renderer compile the shader now.
	shader.get_shader_uniform_list()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(shader_path.get_base_dir()))
	var save_error := ResourceSaver.save(shader, shader_path)
	if save_error != OK:
		return PilotError.new("SAVE_FAILED", "Could not save '%s': %s." % [shader_path, error_string(save_error)])
	shader.take_over_path(shader_path)
	EditorInterface.get_resource_filesystem().update_file(shader_path)

	var result := {"saved": shader_path, "uniforms": _describe_uniforms(code)}
	result.merge(_collect_compile_errors(first_log_id))

	if params.get("assign_to") is Dictionary:
		var node: Variant = _context.find_node_in_edited_scene(String(params["assign_to"].get("node_path", "")))
		if node is PilotError:
			return node
		var property_name := String(params["assign_to"].get("property", _default_material_property(node)))
		if property_name == "":
			return PilotError.new("NO_MATERIAL_PROPERTY", "%s (%s) has no obvious material property." % [node.name, node.get_class()], "Pass assign_to.property, for example \"material\" or \"material_override\".")
		var material := ShaderMaterial.new()
		material.shader = shader
		var undo_redo: EditorUndoRedoManager = _context.get_undo_redo()
		undo_redo.create_action("Assign shader", UndoRedo.MERGE_DISABLE, node)
		undo_redo.add_do_property(node, property_name, material)
		undo_redo.add_undo_property(node, property_name, node.get(property_name))
		undo_redo.commit_action()
		result["assigned_to"] = "%s.%s" % [_context.describe_node_path(node), property_name]
	return result


func _get_shader_info(params: Dictionary) -> Variant:
	var material: ShaderMaterial = null
	var shader: Shader = null
	if params.has("path"):
		var resource_path := String(params["path"])
		if not ResourceLoader.exists(resource_path):
			return PilotError.new("FILE_NOT_FOUND", "No file at '%s'." % resource_path)
		var resource := load(resource_path)
		if resource is ShaderMaterial:
			material = resource
			shader = material.shader
		elif resource is Shader:
			shader = resource
		else:
			return PilotError.new("NOT_A_SHADER", "'%s' is a %s, not a Shader or ShaderMaterial." % [resource_path, resource.get_class()])
	else:
		var found_material: Variant = _find_node_material(params)
		if found_material is PilotError:
			return found_material
		material = found_material
		shader = material.shader
	if shader == null:
		return {"material": true, "shader": null, "hint": "The ShaderMaterial has no shader. Use write_shader with assign_to."}

	var match_result := _shader_type_pattern.search(shader.code)
	var result := {
		"shader": shader.resource_path if shader.resource_path != "" else "(embedded)",
		"shader_type": match_result.get_string(1) if match_result != null else "unknown",
		"uniforms": _describe_uniforms(shader.code),
		"line_count": shader.code.count("\n") + 1,
	}
	if material != null:
		var values := {}
		for uniform in _parse_uniforms(shader.code):
			var value: Variant = material.get_shader_parameter(uniform["name"])
			if value != null:
				values[uniform["name"]] = ValueCodec.to_json_value(value)
		result["material_values"] = values
	return result


func _set_shader_parameters(params: Dictionary) -> Variant:
	var material: ShaderMaterial = null
	if params.has("path"):
		var material_path := String(params["path"])
		material = load(material_path) as ShaderMaterial if ResourceLoader.exists(material_path) else null
		if material == null:
			return PilotError.new("NOT_A_SHADER_MATERIAL", "'%s' is not a ShaderMaterial file." % material_path)
	else:
		var found_material: Variant = _find_node_material(params)
		if found_material is PilotError:
			return found_material
		material = found_material
	if material.shader == null:
		return PilotError.new("NO_SHADER", "The ShaderMaterial has no shader yet.", "Use write_shader with assign_to first.")

	var uniforms_by_name := {}
	for uniform in _parse_uniforms(material.shader.code):
		uniforms_by_name[uniform["name"]] = uniform
	var new_values := {}
	var parameter_values: Dictionary = params.get("parameters", {}) if params.get("parameters") is Dictionary else {}
	for parameter_name in parameter_values:
		if not uniforms_by_name.has(parameter_name):
			return PilotError.new("UNKNOWN_UNIFORM", "The shader has no uniform '%s'." % parameter_name, "Uniforms: %s." % ", ".join(uniforms_by_name.keys()))
		var uniform: Dictionary = uniforms_by_name[parameter_name]
		var value_type: int = UNIFORM_VALUE_TYPES.get(uniform["type"], TYPE_NIL)
		var hints := String(uniform["hints"])
		if hints.contains("source_color") and uniform["type"] in ["vec3", "vec4"]:
			value_type = TYPE_COLOR
		var conversion := ValueCodec.from_json_value(parameter_values[parameter_name], value_type, "Texture" if value_type == TYPE_OBJECT else "", _context.get_edited_scene_root())
		if not conversion["ok"]:
			return PilotError.new("INVALID_VALUE", "%s (%s): %s" % [parameter_name, uniform["type"], conversion["error"]])
		new_values[parameter_name] = conversion["value"]
	if new_values.is_empty():
		return PilotError.new("NOTHING_TO_DO", "Pass parameters, for example {\"tint\": \"#ff8800\"}.")

	var undo_redo: EditorUndoRedoManager = _context.get_undo_redo()
	undo_redo.create_action("Set shader parameters", UndoRedo.MERGE_DISABLE, _context.get_edited_scene_root())
	for parameter_name in new_values:
		undo_redo.add_do_method(material, "set_shader_parameter", parameter_name, new_values[parameter_name])
		undo_redo.add_undo_method(material, "set_shader_parameter", parameter_name, material.get_shader_parameter(parameter_name))
	undo_redo.commit_action()
	if material.resource_path != "" and not material.resource_path.contains("::"):
		ResourceSaver.save(material)
	var changed := {}
	for parameter_name in new_values:
		changed[parameter_name] = ValueCodec.to_json_value(material.get_shader_parameter(parameter_name))
	return {"changed": changed}


func _find_node_material(params: Dictionary) -> Variant:
	var node: Variant = _context.find_node_in_edited_scene(String(params.get("node_path", "")))
	if node is PilotError:
		return node
	var property_name := String(params.get("property", _default_material_property(node)))
	var material: Variant = node.get(property_name) if property_name != "" else null
	if not material is ShaderMaterial:
		return PilotError.new("NO_SHADER_MATERIAL", "%s.%s is not a ShaderMaterial." % [node.name, property_name], "Put a shader on the node with write_shader (assign_to), or pass property.")
	return material


func _default_material_property(node: Node) -> String:
	if node is GeometryInstance3D:
		return "material_override"
	if node is CanvasItem:
		return "material"
	if node is WorldEnvironment:
		return ""
	return "material" if "material" in node else ""


## Uniforms found in the code: name, type, hints and default value.
func _parse_uniforms(code: String) -> Array[Dictionary]:
	var uniforms: Array[Dictionary] = []
	for match_result in _uniform_pattern.search_all(code):
		uniforms.append({
			"type": match_result.get_string(1),
			"name": match_result.get_string(2),
			"hints": match_result.get_string(3).strip_edges(),
			"default": match_result.get_string(4).strip_edges(),
		})
	return uniforms


func _describe_uniforms(code: String) -> Array[String]:
	var lines: Array[String] = []
	for uniform in _parse_uniforms(code):
		var line := "%s %s" % [uniform["type"], uniform["name"]]
		if uniform["hints"] != "":
			line += " : " + uniform["hints"]
		if uniform["default"] != "":
			line += " = " + uniform["default"]
		lines.append(line)
	return lines


## Shader errors printed by the renderer since `first_log_id`. Without a renderer
## (headless editor) shaders are not compiled, which the result says.
func _collect_compile_errors(first_log_id: int) -> Dictionary:
	if DisplayServer.get_name() == "headless":
		return {"compile_check": "skipped: the editor runs without a renderer (headless), so Godot does not compile shaders."}
	if _context.log_capture == null:
		return {"compile_check": "skipped: this Godot version cannot capture the renderer's messages."}
	var error_lines: Array[String] = []
	for entry in _context.get_logs_since(first_log_id):
		var message := String(entry.get("message", ""))
		if String(entry.get("level", "")) == "shader_error" or message.to_lower().contains("shader"):
			if String(entry.get("level", "")) != "info":
				error_lines.append(message)
	if error_lines.is_empty():
		return {"compile_check": "ok"}
	return {"compile_check": "failed", "compile_errors": error_lines}
