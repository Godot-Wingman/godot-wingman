@tool
extends RefCounted
## Handlers of the "inspector" toolset: reading and changing node properties and groups,
## like a person does in the Inspector dock.

const WingmanError := preload("../utils/wingman_error.gd")
const ValueCodec := preload("../utils/value_codec.gd")
const PropertyEditing := preload("../utils/property_editing.gd")

var _context: RefCounted


func _init(context: RefCounted) -> void:
	_context = context


func register_methods(dispatcher: RefCounted) -> void:
	dispatcher.register_method("get_properties", _get_properties)
	dispatcher.register_method("set_properties", _set_properties)
	dispatcher.register_method("reset_properties", _reset_properties)
	dispatcher.register_method("set_groups", _set_groups)


## Lists inspector properties as "name: Type = value" lines.
## Without include_defaults only changed properties are listed, which is usually what
## matters and saves a lot of space.
func _get_properties(params: Dictionary) -> Variant:
	var node: Variant = _context.find_node_in_edited_scene(String(params.get("node_path", ".")))
	if node is WingmanError:
		return node
	var scene_root: Node = _context.get_edited_scene_root()
	var include_defaults := bool(params.get("include_defaults", false))
	var name_filter := String(params.get("filter", "")).to_lower()
	var requested_names: Array = params.get("names", []) if params.get("names") is Array else []

	var property_lines: Array[String] = []
	var hidden_default_count := 0
	for property in PropertyEditing.list_inspector_properties(node):
		var property_name := String(property["name"])
		if not requested_names.is_empty() and not requested_names.has(property_name):
			continue
		if name_filter != "" and not property_name.to_lower().contains(name_filter):
			continue
		var value: Variant = node.get(property_name)
		var is_requested_explicitly := requested_names.has(property_name)
		if not include_defaults and not is_requested_explicitly and PropertyEditing.is_default_value(node, property_name, value):
			hidden_default_count += 1
			continue
		property_lines.append("%s: %s = %s" % [property_name, PropertyEditing.describe_type(property), _format_value(value, scene_root)])

	var result := {
		"node": _context.describe_node_path(node),
		"class": node.get_class(),
		"properties": property_lines,
	}
	if node.get_script() != null:
		result["script"] = node.get_script().resource_path
	if hidden_default_count > 0:
		result["note"] = "%d properties with default values not shown (include_defaults: true shows them)." % hidden_default_count
	return result


func _format_value(value: Variant, scene_root: Node) -> String:
	var json_value: Variant = ValueCodec.to_json_value(value, scene_root)
	return json_value if json_value is String and not value is String else JSON.stringify(json_value)


func _set_properties(params: Dictionary) -> Variant:
	var node: Variant = _context.find_node_in_edited_scene(String(params.get("node_path", ".")))
	if node is WingmanError:
		return node
	var new_values: Variant = params.get("properties", {})
	if not new_values is Dictionary or new_values.is_empty():
		return WingmanError.new("NO_PROPERTIES", "properties must be an object like {\"position\": [100, 50]}.")
	var outcome := PropertyEditing.set_properties_with_undo(
		node, new_values, _context.get_undo_redo(), _context.get_edited_scene_root(), "Set properties of %s" % node.name
	)
	if outcome.has("errors"):
		return WingmanError.new("INVALID_PROPERTY", "Nothing was changed. " + " ".join(outcome["errors"]))
	return {"node": _context.describe_node_path(node), "changed": outcome["changed"]}


func _reset_properties(params: Dictionary) -> Variant:
	var node: Variant = _context.find_node_in_edited_scene(String(params.get("node_path", ".")))
	if node is WingmanError:
		return node
	var default_values := {}
	for property_name in params.get("names", []):
		if PropertyEditing.find_property_information(node, String(property_name)).is_empty():
			return WingmanError.new("INVALID_PROPERTY", "%s has no property '%s'." % [node.get_class(), property_name])
		default_values[String(property_name)] = PropertyEditing.get_default_value(node, String(property_name))

	var undo_redo: EditorUndoRedoManager = _context.get_undo_redo()
	undo_redo.create_action("Reset properties of %s" % node.name)
	for property_name in default_values:
		undo_redo.add_do_property(node, property_name, default_values[property_name])
		undo_redo.add_undo_property(node, property_name, node.get(property_name))
	undo_redo.commit_action()
	return {"node": _context.describe_node_path(node), "reset": default_values.keys()}


## Groups let scripts find nodes ("enemies", "coins"). Persistent groups are saved with the scene.
func _set_groups(params: Dictionary) -> Variant:
	var node: Variant = _context.find_node_in_edited_scene(String(params.get("node_path", ".")))
	if node is WingmanError:
		return node
	var undo_redo: EditorUndoRedoManager = _context.get_undo_redo()
	undo_redo.create_action("Change groups of %s" % node.name)
	for group_name in params.get("add", []):
		if not node.is_in_group(StringName(group_name)):
			undo_redo.add_do_method(node, "add_to_group", StringName(group_name), true)
			undo_redo.add_undo_method(node, "remove_from_group", StringName(group_name))
	for group_name in params.get("remove", []):
		if node.is_in_group(StringName(group_name)):
			undo_redo.add_do_method(node, "remove_from_group", StringName(group_name))
			undo_redo.add_undo_method(node, "add_to_group", StringName(group_name), true)
	undo_redo.commit_action()
	var groups: Array = node.get_groups().filter(func(group_name: StringName) -> bool: return not String(group_name).begins_with("_"))
	return {"node": _context.describe_node_path(node), "groups": groups.map(func(group_name: StringName) -> String: return String(group_name))}
