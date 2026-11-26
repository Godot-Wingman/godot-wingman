@tool
extends RefCounted
## Handlers of the "viewport" toolset: switching the editor's main screen and rendering
## the scene from any camera angle.
##
## render_view does not move the person's editor camera. It renders a copy of the scene
## in a hidden viewport with its own camera, framed around the chosen node.

const WingmanError := preload("../utils/wingman_error.gd")
const CoreHandlers := preload("core_handlers.gd")
const FrameWaiter := preload("../utils/frame_waiter.gd")

const DEFAULT_RENDER_WIDTH := 960
const DEFAULT_RENDER_HEIGHT := 540
const MAIN_SCREENS := ["2D", "3D", "Script", "Game", "AssetLib"]
## Named camera directions for 3D: [yaw degrees, pitch degrees].
const NAMED_VIEWS := {
	"front": [0.0, 0.0], "back": [180.0, 0.0], "left": [-90.0, 0.0], "right": [90.0, 0.0],
	"top": [0.0, -89.0], "bottom": [0.0, 89.0], "perspective": [35.0, -30.0],
}

var _context: RefCounted


func _init(context: RefCounted) -> void:
	_context = context


func register_methods(dispatcher: RefCounted) -> void:
	dispatcher.register_method("set_main_screen", _set_main_screen)
	dispatcher.register_method("render_view", _render_view)


func _set_main_screen(params: Dictionary) -> Variant:
	var screen_name := String(params.get("screen", ""))
	if not MAIN_SCREENS.has(screen_name):
		return WingmanError.new("UNKNOWN_SCREEN", "Unknown screen '%s'. Use one of: %s." % [screen_name, ", ".join(MAIN_SCREENS)])
	EditorInterface.set_main_screen_editor(screen_name)
	return {"main_screen": screen_name}


func _render_view(params: Dictionary) -> Variant:
	if DisplayServer.get_name() == "headless":
		return WingmanError.new("NO_DISPLAY", "This editor runs headless and cannot render.", "Open the project in a normal editor window.")
	var scene_root: Node = _context.get_edited_scene_root()
	var target: Variant = _context.find_node_in_edited_scene(String(params.get("node_path", ".")))
	if target is WingmanError:
		return target

	var render_viewport := SubViewport.new()
	render_viewport.size = Vector2i(int(params.get("width", DEFAULT_RENDER_WIDTH)), int(params.get("height", DEFAULT_RENDER_HEIGHT)))
	render_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	render_viewport.own_world_3d = true
	var scene_copy: Node = scene_root.duplicate(Node.DUPLICATE_USE_INSTANTIATION)
	render_viewport.add_child(scene_copy)
	_context.plugin.add_child(render_viewport)

	var is_3d: bool = target is Node3D or (target == scene_root and _contains_class(scene_root, "Node3D"))
	if is_3d:
		_set_up_3d_camera(render_viewport, scene_copy, target, params)
	else:
		_set_up_2d_camera(render_viewport, target, params)

	# Two frames: one to process the new nodes, one to draw them.
	await FrameWaiter.wait_for_drawn_frame(_context.get_scene_tree())
	await FrameWaiter.wait_for_drawn_frame(_context.get_scene_tree())
	var image := render_viewport.get_texture().get_image()
	render_viewport.queue_free()
	if image == null or image.is_empty():
		return WingmanError.new("EMPTY_IMAGE", "The render was empty.")
	var encoded := CoreHandlers.encode_image(image, params)
	encoded["mode"] = "3d" if is_3d else "2d"
	return encoded


func _set_up_3d_camera(render_viewport: SubViewport, scene_copy: Node, target: Node, params: Dictionary) -> void:
	var bounds := _measure_3d_bounds(target)
	var radius := maxf(bounds.size.length() / 2.0, 0.5)
	var view: Array = NAMED_VIEWS.get(String(params.get("view", "perspective")), NAMED_VIEWS["perspective"])
	var yaw := deg_to_rad(float(params.get("yaw_degrees", view[0])))
	var pitch := deg_to_rad(float(params.get("pitch_degrees", view[1])))
	var distance := radius * 2.5 / maxf(float(params.get("zoom", 1.0)), 0.05)

	# Start in front (+Z) of the target, then turn around it by yaw and pitch.
	var camera_direction := Vector3(0, 0, 1).rotated(Vector3.RIGHT, pitch).rotated(Vector3.UP, yaw)
	var camera := Camera3D.new()
	camera.far = maxf(distance * 10.0, 1000.0)
	render_viewport.add_child(camera)
	var camera_position := bounds.get_center() + camera_direction * distance
	# Looking straight down or up, "up" cannot be Vector3.UP; use forward instead.
	var up_direction := Vector3.UP if absf(pitch) < deg_to_rad(85) else Vector3.FORWARD
	camera.look_at_from_position(camera_position, bounds.get_center(), up_direction)
	camera.current = true

	# A scene without lights would render black; add neutral light like the editor preview does.
	if not _contains_class(scene_copy, "Light3D"):
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-50, 30, 0)
		render_viewport.add_child(sun)
	if not _contains_class(scene_copy, "WorldEnvironment"):
		var environment := Environment.new()
		environment.background_mode = Environment.BG_COLOR
		environment.background_color = Color(0.3, 0.3, 0.35)
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.ambient_light_color = Color(0.6, 0.6, 0.6)
		var world_environment := WorldEnvironment.new()
		world_environment.environment = environment
		render_viewport.add_child(world_environment)


func _set_up_2d_camera(render_viewport: SubViewport, target: Node, params: Dictionary) -> void:
	var bounds := _measure_2d_bounds(target)
	var padded_bounds := bounds.grow(maxf(bounds.size.length() * 0.1, 16.0))
	var fit_zoom := minf(render_viewport.size.x / padded_bounds.size.x, render_viewport.size.y / padded_bounds.size.y)
	var camera := Camera2D.new()
	camera.position = padded_bounds.get_center()
	camera.zoom = Vector2.ONE * fit_zoom * float(params.get("zoom", 1.0))
	render_viewport.add_child(camera)
	camera.make_current()


## Combined world-space box of every visible 3D mesh under `target`.
func _measure_3d_bounds(target: Node) -> AABB:
	var bounds := AABB()
	var has_bounds := false
	for node in [target] + target.find_children("*", "VisualInstance3D", true, false):
		if node is VisualInstance3D:
			var node_bounds: AABB = node.global_transform * node.get_aabb()
			bounds = node_bounds if not has_bounds else bounds.merge(node_bounds)
			has_bounds = true
	if not has_bounds:
		var center: Vector3 = target.global_position if target is Node3D else Vector3.ZERO
		return AABB(center - Vector3.ONE, Vector3.ONE * 2.0)
	return bounds


## Combined screen-space rectangle of sprites, controls and other 2D nodes under `target`.
func _measure_2d_bounds(target: Node) -> Rect2:
	var bounds := Rect2()
	var has_bounds := false
	for node in [target] + target.find_children("*", "CanvasItem", true, false):
		var node_rect := Rect2()
		if node is Control:
			node_rect = node.get_global_rect()
		elif node.has_method("get_rect") and node is Node2D:
			var local_rect: Rect2 = node.get_rect()
			node_rect = node.get_global_transform() * local_rect
		elif node is Node2D:
			node_rect = Rect2(node.global_position, Vector2.ZERO)
		else:
			continue
		bounds = node_rect if not has_bounds else bounds.merge(node_rect)
		has_bounds = true
	if not has_bounds or bounds.size.length() < 1.0:
		var center: Vector2 = bounds.position if has_bounds else Vector2.ZERO
		return Rect2(center - Vector2(160, 90), Vector2(320, 180))
	return bounds


func _contains_class(root: Node, wanted_class: String) -> bool:
	return root.is_class(wanted_class) or not root.find_children("*", wanted_class, true, false).is_empty()
