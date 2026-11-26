@tool
extends RefCounted
## Converts Godot values to JSON-friendly values and back.
##
## Output rules (Godot -> JSON):
## - bool, int, float and String stay as they are.
## - Math types are written as Godot literals, for example "Vector2(10, 20)" or
##   "Color(1, 0, 0, 1)". The same text can be sent back to set a value.
## - Resources saved in a file become their path ("res://player.tres").
## - Nodes become {"node": "path/in/scene", "class": "Sprite2D"}.
##
## Input rules (JSON -> Godot) depend on the type of the property being set, so the
## AI can write values the natural way: [10, 20] or {"x": 10, "y": 20} or
## "Vector2(10, 20)" for a Vector2, "#ff8800" or "red" for a Color, "res://icon.svg"
## for a Texture, and so on.

const MAX_NESTING_DEPTH := 8
const MAX_COLLECTION_ITEMS := 500

## Godot literal constructors we accept in strings. Object() is deliberately missing:
## turning text into arbitrary objects could run code.
const LITERAL_CONSTRUCTOR_NAMES := [
	"Vector2", "Vector2i", "Vector3", "Vector3i", "Vector4", "Vector4i", "Rect2", "Rect2i",
	"Transform2D", "Transform3D", "Plane", "Quaternion", "AABB", "Basis", "Projection",
	"Color", "NodePath", "StringName", "PackedByteArray", "PackedInt32Array",
	"PackedInt64Array", "PackedFloat32Array", "PackedFloat64Array", "PackedStringArray",
	"PackedVector2Array", "PackedVector3Array", "PackedColorArray", "PackedVector4Array",
	"Array", "Dictionary",
]


## Turns any Godot value into something JSON.stringify can write.
## `scene_root` (optional) makes node paths relative to the edited scene.
static func to_json_value(value: Variant, scene_root: Node = null, depth: int = 0) -> Variant:
	if depth > MAX_NESTING_DEPTH:
		return "<too deeply nested>"

	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return value
		TYPE_FLOAT:
			if is_nan(value) or is_inf(value):
				return var_to_str(value)
			return value
		TYPE_STRING_NAME, TYPE_NODE_PATH:
			return String(value)
		TYPE_OBJECT:
			return describe_object(value, scene_root)
		TYPE_DICTIONARY:
			var converted_dictionary := {}
			var item_count := 0
			for key in value:
				if item_count >= MAX_COLLECTION_ITEMS:
					converted_dictionary["<truncated>"] = "%d more entries" % (value.size() - item_count)
					break
				converted_dictionary[str(key)] = to_json_value(value[key], scene_root, depth + 1)
				item_count += 1
			return converted_dictionary
		TYPE_ARRAY:
			return _convert_array_items(value, scene_root, depth)
		TYPE_PACKED_BYTE_ARRAY:
			return "PackedByteArray(%d bytes)" % value.size()
		TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY:
			return _convert_array_items(Array(value), scene_root, depth)
		_:
			# Vectors, colors, transforms, packed vector arrays...
			return var_to_str(value)


static func _convert_array_items(items: Array, scene_root: Node, depth: int) -> Array:
	var converted_items := []
	for item_index in mini(items.size(), MAX_COLLECTION_ITEMS):
		converted_items.append(to_json_value(items[item_index], scene_root, depth + 1))
	if items.size() > MAX_COLLECTION_ITEMS:
		converted_items.append("<%d more items>" % (items.size() - MAX_COLLECTION_ITEMS))
	return converted_items


static func describe_object(object: Object, scene_root: Node = null) -> Variant:
	if object == null or not is_instance_valid(object):
		return null
	if object is Node:
		return {"node": describe_node_path(object, scene_root), "class": object.get_class()}
	if object is Resource:
		var resource_path: String = object.resource_path
		# Sub-resources have paths like "res://scene.tscn::Resource_abc12"; they are not files.
		if resource_path != "" and not resource_path.contains("::"):
			return resource_path
		var description := {"resource": object.get_class()}
		if resource_path != "":
			description["embedded_in"] = resource_path.get_slice("::", 0)
		if object.resource_name != "":
			description["name"] = object.resource_name
		return description
	return {"object": object.get_class(), "instance_id": object.get_instance_id()}


## Path of `node` relative to `scene_root` ("." for the root itself).
## Nodes outside the edited scene get their absolute tree path.
static func describe_node_path(node: Node, scene_root: Node) -> String:
	if scene_root != null and (node == scene_root or scene_root.is_ancestor_of(node)):
		return String(scene_root.get_path_to(node))
	return String(node.get_path())


## Converts `input` (parsed from JSON) into a value of `target_type` (a Variant.Type).
## Returns {"ok": true, "value": ...} or {"ok": false, "error": "..."}.
## `target_class` helps for objects: a Texture2D property gets a loaded texture.
static func from_json_value(input: Variant, target_type: int, target_class: String = "", scene_root: Node = null) -> Dictionary:
	if target_type == TYPE_NIL:
		return _success(_parse_untyped_value(input))

	if input is String and target_type != TYPE_STRING and _looks_like_godot_literal(input):
		var literal_value: Variant = str_to_var(input)
		if literal_value == null:
			return _failure("Could not parse the Godot literal '%s'." % input)
		return _convert_variant(literal_value, target_type, target_class, scene_root)

	match target_type:
		TYPE_BOOL:
			if input is bool:
				return _success(input)
			if input is String and input.to_lower() in ["true", "false"]:
				return _success(input.to_lower() == "true")
			if input is float or input is int:
				return _success(input != 0)
		TYPE_INT:
			if input is float or input is int:
				return _success(int(input))
			if input is String and input.is_valid_int():
				return _success(input.to_int())
		TYPE_FLOAT:
			if input is float or input is int:
				return _success(float(input))
			if input is String and input.is_valid_float():
				return _success(input.to_float())
		TYPE_STRING:
			return _success(input if input is String else str(input))
		TYPE_STRING_NAME:
			return _success(StringName(str(input)))
		TYPE_NODE_PATH:
			if input is Dictionary and input.has("node"):
				return _success(NodePath(str(input["node"])))
			return _success(NodePath(str(input)))
		TYPE_COLOR:
			return _parse_color(input)
		TYPE_VECTOR2, TYPE_VECTOR2I, TYPE_VECTOR3, TYPE_VECTOR3I, TYPE_VECTOR4, TYPE_VECTOR4I:
			return _parse_vector(input, target_type)
		TYPE_OBJECT:
			return _parse_object(input, target_class, scene_root)
		TYPE_ARRAY:
			if input is Array:
				return _success(input)
		TYPE_DICTIONARY:
			if input is Dictionary:
				return _success(input)
		_:
			if input is Array and _is_packed_array_type(target_type):
				return _success(type_convert(input, target_type))

	return _failure(
		"Expected a %s but got %s. Tip: any value can be written as a Godot literal string, for example \"Vector2(1, 2)\"."
		% [type_string(target_type), JSON.stringify(input)]
	)


static func _convert_variant(value: Variant, target_type: int, target_class: String, scene_root: Node) -> Dictionary:
	if typeof(value) == target_type:
		return _success(value)
	if target_type == TYPE_OBJECT:
		return _parse_object(value, target_class, scene_root)
	return _success(type_convert(value, target_type))


static func _parse_untyped_value(input: Variant) -> Variant:
	if input is String and _looks_like_godot_literal(input):
		var literal_value: Variant = str_to_var(input)
		if literal_value != null:
			return literal_value
	if input is String and (input.begins_with("res://") or input.begins_with("uid://")) and ResourceLoader.exists(input):
		return load(input)
	return input


static func _looks_like_godot_literal(text: String) -> bool:
	var opening_parenthesis_index := text.find("(")
	if opening_parenthesis_index <= 0 or not text.strip_edges().ends_with(")"):
		return false
	return LITERAL_CONSTRUCTOR_NAMES.has(text.substr(0, opening_parenthesis_index).strip_edges())


static func _parse_color(input: Variant) -> Dictionary:
	if input is Color:
		return _success(input)
	if input is String:
		var invalid_marker := Color(-1, -1, -1, -1)
		var parsed_color := Color.from_string(input, invalid_marker)
		if parsed_color != invalid_marker:
			return _success(parsed_color)
		return _failure("'%s' is not a color. Use \"#rrggbb\", \"#rrggbbaa\", a name like \"red\", or [r, g, b, a] with values from 0 to 1." % input)
	if input is Array and input.size() >= 3:
		var alpha: float = float(input[3]) if input.size() >= 4 else 1.0
		return _success(Color(float(input[0]), float(input[1]), float(input[2]), alpha))
	if input is Dictionary and input.has("r") and input.has("g") and input.has("b"):
		return _success(Color(float(input["r"]), float(input["g"]), float(input["b"]), float(input.get("a", 1.0))))
	return _failure("Could not read %s as a color." % JSON.stringify(input))


static func _parse_vector(input: Variant, target_type: int) -> Dictionary:
	var component_names: Array[String] = ["x", "y"]
	if target_type in [TYPE_VECTOR3, TYPE_VECTOR3I]:
		component_names = ["x", "y", "z"]
	elif target_type in [TYPE_VECTOR4, TYPE_VECTOR4I]:
		component_names = ["x", "y", "z", "w"]

	var components: Array[float] = []
	if input is Array and input.size() == component_names.size():
		for component in input:
			components.append(float(component))
	elif input is Dictionary:
		for component_name in component_names:
			if not input.has(component_name):
				return _failure("Missing '%s' in %s." % [component_name, JSON.stringify(input)])
			components.append(float(input[component_name]))
	elif input is float or input is int:
		for component_name in component_names:
			components.append(float(input))
	else:
		return _failure("Expected %d numbers for a %s, for example [1, 2]." % [component_names.size(), type_string(target_type)])

	match target_type:
		TYPE_VECTOR2:
			return _success(Vector2(components[0], components[1]))
		TYPE_VECTOR2I:
			return _success(Vector2i(int(components[0]), int(components[1])))
		TYPE_VECTOR3:
			return _success(Vector3(components[0], components[1], components[2]))
		TYPE_VECTOR3I:
			return _success(Vector3i(int(components[0]), int(components[1]), int(components[2])))
		TYPE_VECTOR4:
			return _success(Vector4(components[0], components[1], components[2], components[3]))
		_:
			return _success(Vector4i(int(components[0]), int(components[1]), int(components[2]), int(components[3])))


static func _parse_object(input: Variant, target_class: String, scene_root: Node) -> Dictionary:
	if input == null:
		return _success(null)
	if input is Object:
		return _success(input)
	if input is Dictionary and input.has("type"):
		return build_resource(input, target_class, scene_root)
	if input is Dictionary and input.has("node"):
		input = String(input["node"])
	if not input is String:
		return _failure("Expected a resource path (\"res://...\"), a node path or null, got %s." % JSON.stringify(input))

	var text: String = input
	if text.begins_with("res://") or text.begins_with("uid://") or text.begins_with("user://"):
		if not ResourceLoader.exists(text):
			return _failure("No resource exists at '%s'." % text)
		var resource := load(text)
		if target_class != "" and ClassDB.class_exists(target_class) and not resource.is_class(target_class):
			return _failure("'%s' is a %s, but this property needs a %s." % [text, resource.get_class(), target_class])
		return _success(resource)

	if target_class != "" and ClassDB.class_exists(target_class) and ClassDB.is_parent_class(target_class, "Resource"):
		if ClassDB.class_exists(text) and ClassDB.can_instantiate(text) and ClassDB.is_parent_class(text, target_class):
			# A class name creates a new, empty resource of that class, like "New ..." in the inspector.
			return _success(ClassDB.instantiate(text))
		return _failure("'%s' is not a resource path or a %s class name." % [text, target_class])

	if scene_root != null:
		var node := scene_root if text == "." else scene_root.get_node_or_null(NodePath(text))
		if node != null:
			return _success(node)
	return _failure("Could not find a node or resource named '%s'." % text)


static func _is_packed_array_type(variant_type: int) -> bool:
	return variant_type >= TYPE_PACKED_BYTE_ARRAY and variant_type <= TYPE_PACKED_VECTOR4_ARRAY


static func _success(value: Variant) -> Dictionary:
	return {"ok": true, "value": value}


static func _failure(error_message: String) -> Dictionary:
	return {"ok": false, "error": error_message}


## Creates a new resource from {"type": "StyleBoxFlat", "properties": {"bg_color": "#222"}}.
## Property values are converted like any other value, so resources can be nested.
static func build_resource(description: Dictionary, target_class: String = "", scene_root: Node = null) -> Dictionary:
	var resource_type := String(description.get("type", ""))
	if not ClassDB.class_exists(resource_type) or not ClassDB.is_parent_class(resource_type, "Resource"):
		return _failure("'%s' is not a resource class." % resource_type)
	if not ClassDB.can_instantiate(resource_type):
		return _failure("%s is a base class and cannot be created directly." % resource_type)
	if target_class != "" and ClassDB.class_exists(target_class) and not ClassDB.is_parent_class(resource_type, target_class):
		return _failure("This property needs a %s, but %s is not one." % [target_class, resource_type])
	var resource: Resource = ClassDB.instantiate(resource_type)
	var properties: Variant = description.get("properties", {})
	if not properties is Dictionary:
		return _failure("\"properties\" of a %s must be an object." % resource_type)
	for property_name in properties:
		var property_information := {}
		for property in resource.get_property_list():
			if property["name"] == property_name:
				property_information = property
				break
		if property_information.is_empty():
			return _failure("%s has no property '%s'." % [resource_type, property_name])
		var property_class := String(property_information.get("class_name", ""))
		if int(property_information["type"]) == TYPE_OBJECT and int(property_information.get("hint", 0)) == PROPERTY_HINT_RESOURCE_TYPE:
			property_class = String(property_information.get("hint_string", "")).get_slice(",", 0)
		var conversion := from_json_value(properties[property_name], int(property_information["type"]), property_class, scene_root)
		if not conversion["ok"]:
			return _failure("%s.%s: %s" % [resource_type, property_name, conversion["error"]])
		resource.set(property_name, conversion["value"])
	return _success(resource)
