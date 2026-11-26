@tool
extends RefCounted
## Handlers of the "resources" toolset: creating resources (materials, shapes, themes,
## curves...) and reading or changing resource files (.tres).
##
## Resources inside a node (for example the shape of a CollisionShape2D) can also be
## changed with set_properties and paths like "shape:radius".

const WingmanError := preload("../utils/wingman_error.gd")
const ValueCodec := preload("../utils/value_codec.gd")
const PropertyEditing := preload("../utils/property_editing.gd")

var _context: RefCounted


func _init(context: RefCounted) -> void:
	_context = context


func register_methods(dispatcher: RefCounted) -> void:
	dispatcher.register_method("create_resource", _create_resource)
	dispatcher.register_method("get_resource_properties", _get_resource_properties)
	dispatcher.register_method("set_resource_properties", _set_resource_properties)


## Creates a resource, sets its properties, then saves it to a file and/or assigns it to a
## node property (both can be done at once).
func _create_resource(params: Dictionary) -> Variant:
	var resource_type := String(params.get("type", ""))
	if not ClassDB.class_exists(resource_type) or not ClassDB.is_parent_class(resource_type, "Resource"):
		return WingmanError.new("UNKNOWN_RESOURCE_TYPE", "'%s' is not a resource class." % resource_type, "Examples: StandardMaterial3D, CircleShape2D, Theme, Gradient, AudioStreamRandomizer. Use search_docs to find others.")
	if not ClassDB.can_instantiate(resource_type):
		return WingmanError.new("ABSTRACT_CLASS", "%s is a base class and cannot be created directly." % resource_type)

	var resource: Resource = ClassDB.instantiate(resource_type)
	var scene_root: Node = _context.get_edited_scene_root()
	var initial_properties: Dictionary = params.get("properties", {}) if params.get("properties") is Dictionary else {}
	for property_path in initial_properties:
		var conversion := PropertyEditing.convert_for_property(resource, String(property_path), initial_properties[property_path], scene_root)
		if not conversion["ok"]:
			return WingmanError.new("INVALID_PROPERTY", String(conversion["error"]))
		resource.set_indexed(NodePath(String(property_path)), conversion["value"])

	var result := {"type": resource_type}
	var save_path := String(params.get("path", ""))
	if save_path != "":
		if not save_path.begins_with("res://"):
			return WingmanError.new("INVALID_PATH", "The path must start with res://, for example \"res://materials/grass.tres\".")
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(save_path.get_base_dir()))
		var save_error := ResourceSaver.save(resource, save_path)
		if save_error != OK:
			return WingmanError.new("SAVE_FAILED", "Could not save '%s': %s." % [save_path, error_string(save_error)])
		resource.take_over_path(save_path)
		EditorInterface.get_resource_filesystem().update_file(save_path)
		result["saved"] = save_path

	if params.get("assign_to") is Dictionary:
		var assignment: Dictionary = params["assign_to"]
		var node: Variant = _context.find_node_in_edited_scene(String(assignment.get("node_path", ".")))
		if node is WingmanError:
			return node
		var property_name := String(assignment.get("property", ""))
		var outcome := PropertyEditing.set_properties_with_undo(node, {property_name: resource}, _context.get_undo_redo(), scene_root, "Assign %s" % resource_type)
		if outcome.has("errors"):
			return WingmanError.new("INVALID_PROPERTY", " ".join(outcome["errors"]))
		result["assigned_to"] = "%s.%s" % [_context.describe_node_path(node), property_name]
	return result


func _get_resource_properties(params: Dictionary) -> Variant:
	var resource: Variant = _find_resource(params)
	if resource is WingmanError:
		return resource
	var include_defaults := bool(params.get("include_defaults", false))
	var property_lines: Array[String] = []
	for property in PropertyEditing.list_inspector_properties(resource):
		var property_name := String(property["name"])
		var value: Variant = resource.get(property_name)
		if not include_defaults and PropertyEditing.is_default_value(resource, property_name, value):
			continue
		var json_value: Variant = ValueCodec.to_json_value(value)
		property_lines.append("%s: %s = %s" % [property_name, PropertyEditing.describe_type(property), json_value if json_value is String else JSON.stringify(json_value)])
	return {"resource": resource.resource_path, "class": resource.get_class(), "properties": property_lines}


func _set_resource_properties(params: Dictionary) -> Variant:
	var resource: Variant = _find_resource(params)
	if resource is WingmanError:
		return resource
	var outcome := PropertyEditing.set_properties_with_undo(
		resource, params.get("properties", {}), _context.get_undo_redo(), _context.get_edited_scene_root(), "Change %s" % resource.get_class()
	)
	if outcome.has("errors"):
		return WingmanError.new("INVALID_PROPERTY", "Nothing was changed. " + " ".join(outcome["errors"]))
	# Resource files are saved right away; embedded resources are saved with their scene.
	if resource.resource_path != "" and not resource.resource_path.contains("::"):
		ResourceSaver.save(resource)
	return {"resource": resource.resource_path, "changed": outcome["changed"]}


## A resource file ("path") or a resource stored in a node property ("node_path" + "property").
func _find_resource(params: Dictionary) -> Variant:
	if params.has("path"):
		var resource_path := String(params["path"])
		if not ResourceLoader.exists(resource_path):
			return WingmanError.new("FILE_NOT_FOUND", "No resource at '%s'." % resource_path)
		return load(resource_path)
	var node: Variant = _context.find_node_in_edited_scene(String(params.get("node_path", ".")))
	if node is WingmanError:
		return node
	var property_value: Variant = node.get_indexed(NodePath(String(params.get("property", ""))))
	if not property_value is Resource:
		return WingmanError.new("NOT_A_RESOURCE", "%s.%s does not hold a resource." % [node.name, params.get("property", "")], "Pass path for a resource file, or node_path + property for a resource inside a node.")
	return property_value
