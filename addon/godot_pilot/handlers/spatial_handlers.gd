@tool
extends RefCounted
## Handlers of the "3d" toolset: quick 3D building blocks (meshes with materials and
## collision, sky and sun, collision for imported models), measuring the size of things
## and pointing cameras or lights at a target. get_bounds also works for 2D nodes.

const PilotError := preload("../utils/pilot_error.gd")
const ValueCodec := preload("../utils/value_codec.gd")
const PropertyEditing := preload("../utils/property_editing.gd")

const BODY_TYPES := {"static": "StaticBody3D", "rigid": "RigidBody3D", "character": "CharacterBody3D", "area": "Area3D", "animatable": "AnimatableBody3D"}
const MESH_TYPES := {
	"box": "BoxMesh", "sphere": "SphereMesh", "capsule": "CapsuleMesh", "cylinder": "CylinderMesh",
	"plane": "PlaneMesh", "prism": "PrismMesh", "torus": "TorusMesh", "quad": "QuadMesh",
}
## Sky and sun settings of the environment presets.
const ENVIRONMENT_PRESETS := {
	"day": {"sky_top": Color(0.38, 0.56, 0.85), "sky_horizon": Color(0.72, 0.8, 0.9), "ground": Color(0.25, 0.22, 0.2), "sun_color": Color(1.0, 0.97, 0.9), "sun_energy": 1.0, "sun_rotation": Vector3(-50, -30, 0), "ambient_energy": 1.0},
	"sunset": {"sky_top": Color(0.25, 0.3, 0.55), "sky_horizon": Color(1.0, 0.55, 0.3), "ground": Color(0.18, 0.13, 0.12), "sun_color": Color(1.0, 0.6, 0.35), "sun_energy": 0.8, "sun_rotation": Vector3(-8, -60, 0), "ambient_energy": 0.7},
	"night": {"sky_top": Color(0.01, 0.02, 0.06), "sky_horizon": Color(0.05, 0.07, 0.15), "ground": Color(0.02, 0.02, 0.03), "sun_color": Color(0.55, 0.65, 1.0), "sun_energy": 0.15, "sun_rotation": Vector3(-60, 40, 0), "ambient_energy": 0.3},
	"overcast": {"sky_top": Color(0.55, 0.58, 0.62), "sky_horizon": Color(0.7, 0.72, 0.75), "ground": Color(0.3, 0.3, 0.3), "sun_color": Color(0.9, 0.92, 0.95), "sun_energy": 0.35, "sun_rotation": Vector3(-70, 0, 0), "ambient_energy": 1.2},
}

var _context: RefCounted


func _init(context: RefCounted) -> void:
	_context = context


func register_methods(dispatcher: RefCounted) -> void:
	dispatcher.register_method("add_mesh", _add_mesh)
	dispatcher.register_method("setup_environment", _setup_environment)
	dispatcher.register_method("generate_collision", _generate_collision)
	dispatcher.register_method("get_bounds", _get_bounds)
	dispatcher.register_method("look_at", _look_at)


## A primitive mesh (box, sphere...) with a color or material, optionally inside a
## physics body with a matching collision shape. Size is in meters: [width, height, depth].
func _add_mesh(params: Dictionary) -> Variant:
	var scene_root: Node = _context.get_edited_scene_root()
	var parent: Variant = _context.find_node_in_edited_scene(String(params.get("parent_path", ".")))
	if parent is PilotError:
		return parent
	var shape_name := String(params.get("shape", "box"))
	if not MESH_TYPES.has(shape_name):
		return PilotError.new("INVALID_SHAPE", "Unknown mesh shape '%s'." % shape_name, "Use one of: %s. For models, add the .glb/.gltf scene with add_node (type \"res://model.glb\")." % ", ".join(MESH_TYPES.keys()))
	var size_conversion := ValueCodec.from_json_value(params.get("size", [1, 1, 1]), TYPE_VECTOR3)
	if params.get("size") is float or params.get("size") is int:
		size_conversion = {"ok": true, "value": Vector3.ONE * float(params["size"])}
	if not size_conversion["ok"]:
		return PilotError.new("INVALID_SIZE", String(size_conversion["error"]))
	var size: Vector3 = size_conversion["value"]
	var mesh: PrimitiveMesh = ClassDB.instantiate(MESH_TYPES[shape_name])
	_apply_mesh_size(mesh, shape_name, size)
	if params.get("mesh_properties") is Dictionary:
		for property_name in params["mesh_properties"]:
			var conversion := PropertyEditing.convert_for_property(mesh, String(property_name), params["mesh_properties"][property_name], scene_root)
			if not conversion["ok"]:
				return PilotError.new("INVALID_PROPERTY", String(conversion["error"]))
			mesh.set(String(property_name), conversion["value"])

	if params.has("material"):
		var material_conversion := ValueCodec.from_json_value(params["material"], TYPE_OBJECT, "Material", scene_root)
		if not material_conversion["ok"]:
			return PilotError.new("INVALID_MATERIAL", String(material_conversion["error"]))
		mesh.material = material_conversion["value"]
	elif params.has("color"):
		var color_conversion := ValueCodec.from_json_value(params["color"], TYPE_COLOR)
		if not color_conversion["ok"]:
			return PilotError.new("INVALID_COLOR", String(color_conversion["error"]))
		var material := StandardMaterial3D.new()
		material.albedo_color = color_conversion["value"]
		if material.albedo_color.a < 1.0:
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mesh.material = material

	var node_name := String(params.get("name", shape_name.capitalize()))
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	var top_node: Node3D = mesh_instance
	var created_nodes: Array[Node] = [mesh_instance]
	var body_name := String(params.get("body", "none"))
	if body_name != "none":
		if not BODY_TYPES.has(body_name):
			mesh_instance.free()
			return PilotError.new("INVALID_BODY", "Unknown body '%s'." % body_name, "Use none, %s." % ", ".join(BODY_TYPES.keys()))
		var body: Node3D = ClassDB.instantiate(BODY_TYPES[body_name])
		body.name = node_name
		mesh_instance.name = "Mesh"
		var collision := CollisionShape3D.new()
		collision.name = "Collision"
		collision.shape = _make_collision_shape(mesh, shape_name, size, body_name == "static" or body_name == "area")
		body.add_child(mesh_instance)
		body.add_child(collision)
		top_node = body
		created_nodes = [body, mesh_instance, collision]
	else:
		mesh_instance.name = node_name

	for transform_property in ["position", "rotation_degrees", "scale"]:
		if params.has(transform_property):
			var conversion := ValueCodec.from_json_value(params[transform_property], TYPE_VECTOR3)
			if not conversion["ok"]:
				top_node.free()
				return PilotError.new("INVALID_TRANSFORM", "%s: %s" % [transform_property, conversion["error"]])
			top_node.set(transform_property, conversion["value"])

	_add_nodes_with_undo(parent, top_node, created_nodes, "Add %s" % node_name)
	var result := {"added": _context.describe_node_path(top_node), "class": top_node.get_class(), "mesh": mesh.get_class()}
	if body_name != "none":
		result["children"] = ["Mesh (MeshInstance3D)", "Collision (CollisionShape3D, %s)" % _describe_shape((created_nodes[2] as CollisionShape3D).shape)]
	if parent is Node2D or parent is Control:
		result["warning"] = "The parent is a 2D node; 3D nodes are only drawn under a Node3D (or a SubViewport)."
	return result


## Sky, ambient light, tone mapping and a sun (DirectionalLight3D) in one step. Existing
## WorldEnvironment and sun nodes of the scene are updated instead of duplicated.
func _setup_environment(params: Dictionary) -> Variant:
	var scene_root: Node = _context.get_edited_scene_root()
	if scene_root == null:
		return PilotError.new("NO_OPEN_SCENE", "No scene is open in the editor.")
	var preset_name := String(params.get("preset", "day"))
	if not ENVIRONMENT_PRESETS.has(preset_name):
		return PilotError.new("INVALID_PRESET", "Unknown preset '%s'." % preset_name, "Use one of: %s." % ", ".join(ENVIRONMENT_PRESETS.keys()))
	var preset: Dictionary = ENVIRONMENT_PRESETS[preset_name]

	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = preset["sky_top"]
	sky_material.sky_horizon_color = preset["sky_horizon"]
	sky_material.ground_bottom_color = preset["ground"]
	sky_material.ground_horizon_color = preset["sky_horizon"].darkened(0.3)
	var sky := Sky.new()
	sky.sky_material = sky_material
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = preset["ambient_energy"]
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.glow_enabled = bool(params.get("glow", true))
	environment.fog_enabled = bool(params.get("fog", false))
	environment.fog_light_color = preset["sky_horizon"]
	environment.ssao_enabled = bool(params.get("ambient_occlusion", false))
	if params.get("environment_properties") is Dictionary:
		for property_name in params["environment_properties"]:
			var conversion := PropertyEditing.convert_for_property(environment, String(property_name), params["environment_properties"][property_name], scene_root)
			if not conversion["ok"]:
				return PilotError.new("INVALID_PROPERTY", String(conversion["error"]))
			environment.set_indexed(NodePath(String(property_name)), conversion["value"])

	var undo_redo: EditorUndoRedoManager = _context.get_undo_redo()
	undo_redo.create_action("Set up environment (%s)" % preset_name, UndoRedo.MERGE_DISABLE, scene_root)
	var result := {"preset": preset_name}
	var world_environment := _find_first_of_class(scene_root, "WorldEnvironment") as WorldEnvironment
	if world_environment != null:
		undo_redo.add_do_property(world_environment, "environment", environment)
		undo_redo.add_undo_property(world_environment, "environment", world_environment.environment)
		result["world_environment"] = "updated %s" % _context.describe_node_path(world_environment)
	else:
		world_environment = WorldEnvironment.new()
		world_environment.name = "WorldEnvironment"
		world_environment.environment = environment
		_add_do_new_node(undo_redo, scene_root, world_environment, [world_environment])
		result["world_environment"] = "added WorldEnvironment"

	if bool(params.get("sun", true)):
		var sun := _find_first_of_class(scene_root, "DirectionalLight3D") as DirectionalLight3D
		var is_new_sun := sun == null
		if is_new_sun:
			sun = DirectionalLight3D.new()
			sun.name = "Sun"
		var sun_values := {
			"light_color": preset["sun_color"],
			"light_energy": preset["sun_energy"],
			"rotation_degrees": preset["sun_rotation"],
			"shadow_enabled": bool(params.get("shadows", true)),
		}
		if params.has("sun_rotation_degrees"):
			var rotation_conversion := ValueCodec.from_json_value(params["sun_rotation_degrees"], TYPE_VECTOR3)
			if rotation_conversion["ok"]:
				sun_values["rotation_degrees"] = rotation_conversion["value"]
		if is_new_sun:
			for property_name in sun_values:
				sun.set(property_name, sun_values[property_name])
			_add_do_new_node(undo_redo, scene_root, sun, [sun])
			result["sun"] = "added Sun (DirectionalLight3D)"
		else:
			for property_name in sun_values:
				undo_redo.add_do_property(sun, property_name, sun_values[property_name])
				undo_redo.add_undo_property(sun, property_name, sun.get(property_name))
			result["sun"] = "updated %s" % _context.describe_node_path(sun)
	undo_redo.commit_action()
	if scene_root is Node2D or scene_root is Control:
		result["warning"] = "This is a 2D scene; the sky and sun only affect 3D."
	return result


## Collision shapes made from the meshes under a node (works for imported .glb models).
func _generate_collision(params: Dictionary) -> Variant:
	var node: Variant = _context.find_node_in_edited_scene(String(params.get("node_path", "")))
	if node is PilotError:
		return node
	if not node is Node3D:
		return PilotError.new("NOT_A_3D_NODE", "%s is a %s, not a 3D node." % [node.name, node.get_class()])
	var shape_kind := String(params.get("shape", "trimesh"))
	var body_name := String(params.get("body", "static"))
	if shape_kind == "trimesh" and body_name in ["rigid", "character"]:
		return PilotError.new("CONCAVE_ON_MOVING_BODY", "Moving bodies cannot use trimesh (concave) shapes.", "Use shape: \"convex\" for rigid and character bodies.")
	var mesh_instances: Array[Node] = []
	_collect_mesh_instances(node, mesh_instances)
	if mesh_instances.is_empty():
		return PilotError.new("NO_MESHES", "There is no MeshInstance3D with a mesh under %s." % node.name)

	var holder: Node3D = node
	var created_nodes: Array[Node] = []
	if body_name != "none":
		if not BODY_TYPES.has(body_name):
			return PilotError.new("INVALID_BODY", "Unknown body '%s'." % body_name, "Use none (add shapes to this node, which must be a physics body), %s." % ", ".join(BODY_TYPES.keys()))
		holder = ClassDB.instantiate(BODY_TYPES[body_name])
		holder.name = String(params.get("name", BODY_TYPES[body_name].trim_suffix("3D")))
		created_nodes.append(holder)
	elif not node is CollisionObject3D:
		return PilotError.new("NOT_A_BODY", "%s is not a physics body, so it cannot hold collision shapes." % node.name, "Pass body: \"static\" (or another body) to add one.")

	var shape_lines: Array[String] = []
	for mesh_instance: MeshInstance3D in mesh_instances:
		var shape: Shape3D = mesh_instance.mesh.create_trimesh_shape() if shape_kind == "trimesh" else mesh_instance.mesh.create_convex_shape(true, shape_kind == "simplified_convex")
		if shape == null:
			continue
		var collision := CollisionShape3D.new()
		collision.name = "Shape" + mesh_instance.name.to_pascal_case()
		collision.shape = shape
		# Shapes go under the node itself, so they must keep each mesh's offset from it.
		collision.transform = (node as Node3D).global_transform.affine_inverse() * mesh_instance.global_transform
		if holder != node:
			holder.add_child(collision)
		created_nodes.append(collision)
		shape_lines.append("%s from %s" % [collision.name, mesh_instance.name])
	if shape_lines.is_empty():
		for created_node in created_nodes:
			created_node.free()
		return PilotError.new("NO_SHAPES", "Godot could not build collision shapes from these meshes.")

	var undo_redo: EditorUndoRedoManager = _context.get_undo_redo()
	undo_redo.create_action("Generate collision", UndoRedo.MERGE_DISABLE, node)
	if holder != node:
		_add_do_new_node(undo_redo, node, holder, created_nodes)
	else:
		for collision in created_nodes:
			_add_do_new_node(undo_redo, node, collision, [collision])
	undo_redo.commit_action()
	return {"body": _context.describe_node_path(holder), "shapes": shape_lines}


## The space a node and its children take: a box in 3D (meters), a rectangle in 2D (pixels).
func _get_bounds(params: Dictionary) -> Variant:
	var node: Variant = _context.find_node_in_edited_scene(String(params.get("node_path", ".")))
	if node is PilotError:
		return node
	if node is Node3D:
		var bounds := AABB()
		var has_bounds := false
		var visual_instances: Array[Node] = []
		_collect_nodes_of_class(node, "VisualInstance3D", visual_instances)
		for visual_instance: VisualInstance3D in visual_instances:
			if not visual_instance.is_visible_in_tree():
				continue
			var global_box: AABB = visual_instance.global_transform * visual_instance.get_aabb()
			bounds = global_box if not has_bounds else bounds.merge(global_box)
			has_bounds = true
		if not has_bounds:
			return {"node_path": _context.describe_node_path(node), "bounds": null, "note": "Nothing visible under this node."}
		return {
			"node_path": _context.describe_node_path(node),
			"space": "3d (meters, global)",
			"min": _vector_to_array(bounds.position),
			"max": _vector_to_array(bounds.end),
			"size": _vector_to_array(bounds.size),
			"center": _vector_to_array(bounds.get_center()),
			"bottom_center": _vector_to_array(Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)),
		}
	if node is CanvasItem:
		var rectangle := Rect2()
		var has_rectangle := false
		var canvas_items: Array[Node] = []
		_collect_nodes_of_class(node, "CanvasItem", canvas_items)
		for canvas_item: CanvasItem in canvas_items:
			var local_rectangle: Variant = _local_rectangle_of(canvas_item)
			if local_rectangle == null or not canvas_item.is_visible_in_tree():
				continue
			var global_rectangle: Rect2 = canvas_item.get_global_transform() * (local_rectangle as Rect2)
			rectangle = global_rectangle if not has_rectangle else rectangle.merge(global_rectangle)
			has_rectangle = true
		if not has_rectangle:
			return {"node_path": _context.describe_node_path(node), "bounds": null, "note": "Nothing with a size under this node (sprites, controls, shapes, tiles)."}
		return {
			"node_path": _context.describe_node_path(node),
			"space": "2d (pixels, global)",
			"min": [rectangle.position.x, rectangle.position.y],
			"max": [rectangle.end.x, rectangle.end.y],
			"size": [rectangle.size.x, rectangle.size.y],
			"center": [rectangle.get_center().x, rectangle.get_center().y],
		}
	return PilotError.new("NO_SPACE", "%s is a %s, which has no position in 2D or 3D." % [node.name, node.get_class()])


## Turns a 3D node (camera, light, character...) so its front (-Z) faces a target point
## or node. Optionally moves it first.
func _look_at(params: Dictionary) -> Variant:
	var node: Variant = _context.find_node_in_edited_scene(String(params.get("node_path", "")))
	if node is PilotError:
		return node
	if not node is Node3D:
		return PilotError.new("NOT_A_3D_NODE", "%s is a %s; look_at is for 3D nodes." % [node.name, node.get_class()], "In 2D, set rotation with set_properties (look_at is a 3D helper).")
	var node_3d: Node3D = node
	var new_position := node_3d.global_position
	if params.has("position"):
		var position_conversion := ValueCodec.from_json_value(params["position"], TYPE_VECTOR3)
		if not position_conversion["ok"]:
			return PilotError.new("INVALID_POSITION", String(position_conversion["error"]))
		new_position = position_conversion["value"]
	var target_point: Vector3
	if params.has("target_node"):
		var target_node: Variant = _context.find_node_in_edited_scene(String(params["target_node"]))
		if target_node is PilotError:
			return target_node
		if not target_node is Node3D:
			return PilotError.new("NOT_A_3D_NODE", "The target %s is not a 3D node." % target_node.name)
		target_point = (target_node as Node3D).global_position
	elif params.has("target"):
		var target_conversion := ValueCodec.from_json_value(params["target"], TYPE_VECTOR3)
		if not target_conversion["ok"]:
			return PilotError.new("INVALID_TARGET", String(target_conversion["error"]))
		target_point = target_conversion["value"]
	else:
		return PilotError.new("MISSING_TARGET", "Pass target ([x, y, z]) or target_node.")
	if new_position.is_equal_approx(target_point):
		return PilotError.new("SAME_POSITION", "The node is already at the target point, so there is no direction to look at.")
	var direction := (target_point - new_position).normalized()
	var up := Vector3.UP if absf(direction.dot(Vector3.UP)) < 0.999 else Vector3.FORWARD
	var new_transform := Transform3D(node_3d.global_basis.orthonormalized(), new_position).looking_at(target_point, up)
	new_transform.basis = new_transform.basis.scaled(node_3d.global_basis.get_scale())

	var undo_redo: EditorUndoRedoManager = _context.get_undo_redo()
	undo_redo.create_action("Look at", UndoRedo.MERGE_DISABLE, node_3d)
	undo_redo.add_do_property(node_3d, "global_transform", new_transform)
	undo_redo.add_undo_property(node_3d, "global_transform", node_3d.global_transform)
	undo_redo.commit_action()
	return {
		"node_path": _context.describe_node_path(node_3d),
		"position": _vector_to_array(node_3d.global_position),
		"rotation_degrees": _vector_to_array(node_3d.rotation_degrees),
		"distance_to_target": snappedf(new_position.distance_to(target_point), 0.001),
	}


func _apply_mesh_size(mesh: PrimitiveMesh, shape_name: String, size: Vector3) -> void:
	match shape_name:
		"box", "prism":
			mesh.set("size", size)
		"sphere":
			mesh.set("radius", size.x / 2.0)
			mesh.set("height", size.y)
		"capsule":
			mesh.set("radius", size.x / 2.0)
			mesh.set("height", maxf(size.y, size.x))
		"cylinder":
			mesh.set("top_radius", size.x / 2.0)
			mesh.set("bottom_radius", size.x / 2.0)
			mesh.set("height", size.y)
		"plane":
			mesh.set("size", Vector2(size.x, size.z))
		"quad":
			mesh.set("size", Vector2(size.x, size.y))
		"torus":
			mesh.set("outer_radius", size.x / 2.0)
			mesh.set("inner_radius", size.x / 4.0)


## A collision shape that matches the primitive mesh exactly.
func _make_collision_shape(mesh: PrimitiveMesh, shape_name: String, size: Vector3, can_be_concave: bool) -> Shape3D:
	match shape_name:
		"box":
			var box_shape := BoxShape3D.new()
			box_shape.size = size
			return box_shape
		"sphere":
			var sphere_shape := SphereShape3D.new()
			sphere_shape.radius = size.x / 2.0
			return sphere_shape
		"capsule":
			var capsule_shape := CapsuleShape3D.new()
			capsule_shape.radius = size.x / 2.0
			capsule_shape.height = maxf(size.y, size.x)
			return capsule_shape
		"cylinder":
			var cylinder_shape := CylinderShape3D.new()
			cylinder_shape.radius = size.x / 2.0
			cylinder_shape.height = size.y
			return cylinder_shape
	return mesh.create_trimesh_shape() if can_be_concave else mesh.create_convex_shape()


func _describe_shape(shape: Shape3D) -> String:
	if shape is BoxShape3D:
		return "BoxShape3D size %s" % shape.size
	if shape is SphereShape3D:
		return "SphereShape3D radius %s" % shape.radius
	return shape.get_class()


func _add_nodes_with_undo(parent: Node, top_node: Node, created_nodes: Array[Node], action_name: String) -> void:
	var undo_redo: EditorUndoRedoManager = _context.get_undo_redo()
	undo_redo.create_action(action_name, UndoRedo.MERGE_DISABLE, parent)
	_add_do_new_node(undo_redo, parent, top_node, created_nodes)
	undo_redo.commit_action()


## Adds the "do" and "undo" steps for a new node (and the new nodes inside it).
func _add_do_new_node(undo_redo: EditorUndoRedoManager, parent: Node, top_node: Node, created_nodes: Array[Node]) -> void:
	var scene_root: Node = _context.get_edited_scene_root()
	undo_redo.add_do_method(parent, "add_child", top_node, true)
	for created_node in created_nodes:
		undo_redo.add_do_property(created_node, "owner", scene_root)
	undo_redo.add_do_reference(top_node)
	undo_redo.add_undo_method(parent, "remove_child", top_node)


func _local_rectangle_of(canvas_item: CanvasItem) -> Variant:
	if canvas_item is Control:
		return Rect2(Vector2.ZERO, (canvas_item as Control).size)
	if canvas_item is Sprite2D:
		var sprite: Sprite2D = canvas_item
		return sprite.get_rect() if sprite.texture != null else null
	if canvas_item is CollisionShape2D:
		var collision: CollisionShape2D = canvas_item
		return collision.shape.get_rect() if collision.shape != null else null
	if canvas_item is Polygon2D:
		var polygon: PackedVector2Array = (canvas_item as Polygon2D).polygon
		if polygon.is_empty():
			return null
		var polygon_rectangle := Rect2(polygon[0], Vector2.ZERO)
		for point in polygon:
			polygon_rectangle = polygon_rectangle.expand(point)
		return polygon_rectangle
	if canvas_item is TileMapLayer:
		var layer: TileMapLayer = canvas_item
		var used_cells := layer.get_used_rect()
		if used_cells.size == Vector2i.ZERO or layer.tile_set == null:
			return null
		var tile_size := Vector2(layer.tile_set.tile_size)
		return Rect2(layer.map_to_local(used_cells.position) - tile_size / 2.0, Vector2(used_cells.size) * tile_size)
	return null


func _collect_mesh_instances(node: Node, found_nodes: Array[Node]) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		found_nodes.append(node)
	for child in node.get_children():
		_collect_mesh_instances(child, found_nodes)


func _collect_nodes_of_class(node: Node, class_name_text: String, found_nodes: Array[Node]) -> void:
	if node.is_class(class_name_text):
		found_nodes.append(node)
	for child in node.get_children():
		_collect_nodes_of_class(child, class_name_text, found_nodes)


func _find_first_of_class(node: Node, class_name_text: String) -> Node:
	var found_nodes: Array[Node] = []
	_collect_nodes_of_class(node, class_name_text, found_nodes)
	return found_nodes[0] if not found_nodes.is_empty() else null


func _vector_to_array(vector: Vector3) -> Array:
	return [snappedf(vector.x, 0.001), snappedf(vector.y, 0.001), snappedf(vector.z, 0.001)]
