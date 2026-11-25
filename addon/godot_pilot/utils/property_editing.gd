@tool
extends RefCounted
## Reading and changing properties of nodes and resources, the way the inspector does.
##
## Shared by the inspector tools, add_node (initial properties) and batch edits.
## Every change goes through the editor's undo history.

const ValueCodec := preload("value_codec.gd")

## Property lists also contain group and category headers; those are not properties.
const HEADER_USAGE_FLAGS := PROPERTY_USAGE_CATEGORY | PROPERTY_USAGE_GROUP | PROPERTY_USAGE_SUBGROUP


## The property description from get_property_list(), or an empty Dictionary.
## For a path like "position:x" or "material:albedo_color" the first part is used.
static func find_property_information(object: Object, property_path: String) -> Dictionary:
	var base_property_name := property_path.get_slice(":", 0)
	for property in object.get_property_list():
		if property["name"] == base_property_name:
			return property
	return {}


## Properties a person can see in the inspector.
static func list_inspector_properties(object: Object) -> Array[Dictionary]:
	var properties: Array[Dictionary] = []
	for property in object.get_property_list():
		var usage := int(property["usage"])
		if usage & HEADER_USAGE_FLAGS != 0 or usage & PROPERTY_USAGE_EDITOR == 0:
			continue
		properties.append(property)
	return properties


## Converts a JSON value into the type of the property. Returns {"ok", "value"} or {"ok": false, "error"}.
static func convert_for_property(object: Object, property_path: String, input: Variant, scene_root: Node) -> Dictionary:
	if property_path.contains(":"):
		# A sub-property like "position:x" or "material:albedo_color": its current value tells the type.
		var current_value: Variant = object.get_indexed(NodePath(property_path))
		var value_class: String = current_value.get_class() if current_value is Object else ""
		return ValueCodec.from_json_value(input, typeof(current_value), value_class, scene_root)

	var property_information := find_property_information(object, property_path)
	if property_information.is_empty():
		if property_path.begins_with("metadata/"):
			return ValueCodec.from_json_value(input, TYPE_NIL, "", scene_root)
		return {"ok": false, "error": "%s has no property '%s'.%s" % [object.get_class(), property_path, suggest_property_names(object, property_path)]}

	var property_type := int(property_information["type"])
	var property_class := String(property_information.get("class_name", ""))
	if property_type == TYPE_OBJECT and int(property_information.get("hint", 0)) == PROPERTY_HINT_RESOURCE_TYPE:
		# For resources the accepted class is in the hint, for example "Texture2D".
		property_class = String(property_information.get("hint_string", "")).get_slice(",", 0)
	return ValueCodec.from_json_value(input, property_type, property_class, scene_root)


## Sets several properties as one undoable action. Nothing changes if any value is invalid.
## Returns {"changed": {name: new value}} or {"errors": [...]}.
static func set_properties_with_undo(
	object: Object, new_values: Dictionary, undo_redo: EditorUndoRedoManager, scene_root: Node, action_name: String
) -> Dictionary:
	var converted_values := {}
	var errors: Array[String] = []
	for property_path in new_values:
		var conversion := convert_for_property(object, String(property_path), new_values[property_path], scene_root)
		if conversion["ok"]:
			converted_values[String(property_path)] = conversion["value"]
		else:
			errors.append(String(conversion["error"]))
	if not errors.is_empty():
		return {"errors": errors}

	undo_redo.create_action(action_name, UndoRedo.MERGE_DISABLE, object)
	for property_path in converted_values:
		var old_value: Variant = object.get_indexed(NodePath(property_path))
		undo_redo.add_do_method(object, "set_indexed", NodePath(property_path), converted_values[property_path])
		undo_redo.add_undo_method(object, "set_indexed", NodePath(property_path), old_value)
	undo_redo.commit_action()

	var changed := {}
	for property_path in converted_values:
		changed[property_path] = ValueCodec.to_json_value(object.get_indexed(NodePath(property_path)), scene_root)
	return {"changed": changed}


## The value a property has when nobody changed it, or null when unknown.
static func get_default_value(object: Object, property_name: String) -> Variant:
	var script: Script = object.get_script()
	if script != null:
		for script_property in script.get_script_property_list():
			if script_property["name"] == property_name:
				return script.get_property_default_value(property_name)
	if _class_declares_property(object.get_class(), property_name):
		return ClassDB.class_get_property_default_value(object.get_class(), property_name)
	return null


static func is_default_value(object: Object, property_name: String, value: Variant) -> bool:
	var default_value: Variant = get_default_value(object, property_name)
	return typeof(default_value) == typeof(value) and default_value == value


## "Vector2", "Texture2D", "int (Idle, Walk, Run)"...
static func describe_type(property_information: Dictionary) -> String:
	var property_type := int(property_information.get("type", TYPE_NIL))
	var hint := int(property_information.get("hint", PROPERTY_HINT_NONE))
	var hint_string := String(property_information.get("hint_string", ""))
	if property_type == TYPE_OBJECT:
		if hint == PROPERTY_HINT_RESOURCE_TYPE and hint_string != "":
			return hint_string
		var object_class := String(property_information.get("class_name", ""))
		return object_class if object_class != "" else "Object"
	var type_name := "Variant" if property_type == TYPE_NIL else type_string(property_type)
	if hint == PROPERTY_HINT_ENUM and hint_string != "":
		return "%s (one of: %s)" % [type_name, hint_string]
	if hint == PROPERTY_HINT_FLAGS and hint_string != "":
		return "%s (flags: %s)" % [type_name, hint_string]
	if hint == PROPERTY_HINT_RANGE and hint_string != "" and not hint_string.contains("or_greater"):
		# Only real limits are useful; "-99999,99999,or_greater" just means "any number".
		return "%s (range %s to %s)" % [type_name, hint_string.get_slice(",", 0), hint_string.get_slice(",", 1)]
	return type_name


static func suggest_property_names(object: Object, wrong_name: String) -> String:
	var search_word := wrong_name.get_slice(":", 0).to_lower()
	# Score every property name by how similar it is (catches typos like "postion")
	# and whether one name contains the other (catches "color" -> "modulate_color").
	var scored_candidates: Array = []
	for property in list_inspector_properties(object):
		var candidate := String(property["name"])
		var similarity := candidate.to_lower().similarity(search_word)
		if candidate.to_lower().contains(search_word) or search_word.contains(candidate.to_lower()):
			similarity += 0.5
		if similarity >= 0.5:
			scored_candidates.append([similarity, candidate])
	if scored_candidates.is_empty():
		return " Use get_properties to see all properties."
	scored_candidates.sort_custom(func(first: Array, second: Array) -> bool: return first[0] > second[0])
	var suggestions: Array[String] = []
	for scored_candidate in scored_candidates.slice(0, 6):
		suggestions.append(scored_candidate[1])
	return " Did you mean: %s?" % ", ".join(suggestions)


static func _class_declares_property(class_name_text: String, property_name: String) -> bool:
	for property in ClassDB.class_get_property_list(class_name_text):
		if property["name"] == property_name:
			return true
	return false
