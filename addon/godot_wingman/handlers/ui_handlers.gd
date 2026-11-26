@tool
extends RefCounted
## Handlers of the "ui" toolset: user interfaces made of Control nodes. Reading the layout
## (where every control is, and what looks wrong), anchor presets, theme overrides, and
## building a whole tree of controls in one undoable step.

const WingmanError := preload("../utils/wingman_error.gd")
const ValueCodec := preload("../utils/value_codec.gd")
const PropertyEditing := preload("../utils/property_editing.gd")
const SceneHandlers := preload("scene_handlers.gd")

## Anchor presets by name, with their anchors (left, top, right, bottom).
const LAYOUT_PRESETS := {
	"top_left": [Control.PRESET_TOP_LEFT, [0.0, 0.0, 0.0, 0.0]],
	"top_right": [Control.PRESET_TOP_RIGHT, [1.0, 0.0, 1.0, 0.0]],
	"bottom_left": [Control.PRESET_BOTTOM_LEFT, [0.0, 1.0, 0.0, 1.0]],
	"bottom_right": [Control.PRESET_BOTTOM_RIGHT, [1.0, 1.0, 1.0, 1.0]],
	"center_left": [Control.PRESET_CENTER_LEFT, [0.0, 0.5, 0.0, 0.5]],
	"center_top": [Control.PRESET_CENTER_TOP, [0.5, 0.0, 0.5, 0.0]],
	"center_right": [Control.PRESET_CENTER_RIGHT, [1.0, 0.5, 1.0, 0.5]],
	"center_bottom": [Control.PRESET_CENTER_BOTTOM, [0.5, 1.0, 0.5, 1.0]],
	"center": [Control.PRESET_CENTER, [0.5, 0.5, 0.5, 0.5]],
	"left_wide": [Control.PRESET_LEFT_WIDE, [0.0, 0.0, 0.0, 1.0]],
	"top_wide": [Control.PRESET_TOP_WIDE, [0.0, 0.0, 1.0, 0.0]],
	"right_wide": [Control.PRESET_RIGHT_WIDE, [1.0, 0.0, 1.0, 1.0]],
	"bottom_wide": [Control.PRESET_BOTTOM_WIDE, [0.0, 1.0, 1.0, 1.0]],
	"vcenter_wide": [Control.PRESET_VCENTER_WIDE, [0.0, 0.5, 1.0, 0.5]],
	"hcenter_wide": [Control.PRESET_HCENTER_WIDE, [0.5, 0.0, 0.5, 1.0]],
	"full_rect": [Control.PRESET_FULL_RECT, [0.0, 0.0, 1.0, 1.0]],
}
const RESIZE_MODES := {
	"minsize": Control.PRESET_MODE_MINSIZE,
	"keep_width": Control.PRESET_MODE_KEEP_WIDTH,
	"keep_height": Control.PRESET_MODE_KEEP_HEIGHT,
	"keep_size": Control.PRESET_MODE_KEEP_SIZE,
}
## Theme override groups and the property prefix Godot uses for them.
const THEME_OVERRIDE_PREFIXES := {
	"colors": "theme_override_colors/",
	"constants": "theme_override_constants/",
	"font_sizes": "theme_override_font_sizes/",
	"fonts": "theme_override_fonts/",
	"styles": "theme_override_styles/",
	"icons": "theme_override_icons/",
}
const LAYOUT_PROPERTIES := ["anchor_left", "anchor_top", "anchor_right", "anchor_bottom", "offset_left", "offset_top", "offset_right", "offset_bottom", "grow_horizontal", "grow_vertical"]
const MAXIMUM_LAYOUT_LINES := 300

var _context: RefCounted


func _init(context: RefCounted) -> void:
	_context = context


func register_methods(dispatcher: RefCounted) -> void:
	dispatcher.register_method("get_ui_layout", _get_ui_layout)
	dispatcher.register_method("set_layout_preset", _set_layout_preset)
	dispatcher.register_method("set_theme_overrides", _set_theme_overrides)
	dispatcher.register_method("build_ui", _build_ui)


## One line per control: type, rectangle on screen, anchors, size flags, text, and
## warnings for common mistakes (zero size, off screen, text cut off).
func _get_ui_layout(params: Dictionary) -> Variant:
	var start_node: Variant = _context.find_node_in_edited_scene(String(params.get("node_path", ".")))
	if start_node is WingmanError:
		return start_node
	var screen_size := Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width", 1152)),
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 648))
	)
	var layout_lines: Array[String] = []
	var problem_lines: Array[String] = []
	_describe_controls(start_node, 0, screen_size, layout_lines, problem_lines)
	if layout_lines.is_empty():
		return {"layout": [], "hint": "No Control nodes here. Build a UI with build_ui (put it under a CanvasLayer in game scenes)."}
	var result := {"screen_size": [screen_size.x, screen_size.y], "layout": layout_lines}
	if not problem_lines.is_empty():
		result["problems"] = problem_lines
	return result


func _describe_controls(node: Node, depth: int, screen_size: Vector2, layout_lines: Array[String], problem_lines: Array[String]) -> void:
	if layout_lines.size() >= MAXIMUM_LAYOUT_LINES:
		return
	var child_depth := depth
	if node is Control:
		var control: Control = node
		var rectangle := control.get_global_rect()
		var line := "%s%s (%s) rect=(%d, %d, %d x %d)" % ["  ".repeat(depth), _context.describe_node_path(control), control.get_class(), rectangle.position.x, rectangle.position.y, rectangle.size.x, rectangle.size.y]
		var in_container := control.get_parent() is Container
		if in_container:
			line += " in container, size_flags h=%s v=%s" % [_describe_size_flags(control.size_flags_horizontal), _describe_size_flags(control.size_flags_vertical)]
		else:
			line += " anchors=%s" % _describe_anchors(control)
		if control.custom_minimum_size != Vector2.ZERO:
			line += " min_size=(%d, %d)" % [control.custom_minimum_size.x, control.custom_minimum_size.y]
		if "text" in control and String(control.get("text")) != "":
			line += " text=\"%s\"" % String(control.get("text")).left(60).replace("\n", "\\n")
		if not control.visible:
			line += " hidden"
		if control.mouse_filter == Control.MOUSE_FILTER_IGNORE:
			line += " ignores_mouse"
		layout_lines.append(line)
		child_depth = depth + 1

		if control.is_visible_in_tree():
			var path_text: String = _context.describe_node_path(control)
			if rectangle.size.x < 1.0 or rectangle.size.y < 1.0:
				problem_lines.append("%s has zero size, so it is invisible." % path_text)
			elif not Rect2(Vector2.ZERO, screen_size).intersects(rectangle) and not _is_inside_scroll_or_subviewport(control):
				problem_lines.append("%s is outside the %dx%d screen." % [path_text, screen_size.x, screen_size.y])
			var label := control as Label
			if label != null and label.autowrap_mode == TextServer.AUTOWRAP_OFF and not label.clip_text and label.get_minimum_size().x > rectangle.size.x + 1.0:
				problem_lines.append("%s: its text is wider than the control." % path_text)
	for child in node.get_children():
		if child.owner == _context.get_edited_scene_root() or child.owner == node.owner:
			_describe_controls(child, child_depth, screen_size, layout_lines, problem_lines)


func _set_layout_preset(params: Dictionary) -> Variant:
	var preset_name := String(params.get("preset", ""))
	if not LAYOUT_PRESETS.has(preset_name):
		return WingmanError.new("INVALID_PRESET", "Unknown layout preset '%s'." % preset_name, "Use one of: %s." % ", ".join(LAYOUT_PRESETS.keys()))
	var resize_mode: int = RESIZE_MODES.get(String(params.get("resize_mode", "minsize")), Control.PRESET_MODE_MINSIZE)
	var margin := int(params.get("margin", 0))
	var node_paths: Array = params.get("node_paths", []) if params.get("node_paths") is Array else []
	var controls: Array[Control] = []
	for node_path: Variant in node_paths:
		var node: Variant = _context.find_node_in_edited_scene(String(node_path))
		if node is WingmanError:
			return node
		if not node is Control:
			return WingmanError.new("NOT_A_CONTROL", "%s is a %s; layout presets are for Control nodes." % [node.name, node.get_class()])
		if node.get_parent() is Container:
			return WingmanError.new("INSIDE_CONTAINER", "%s is inside a %s, which places it; anchors are ignored there." % [node.name, node.get_parent().get_class()], "Change size_flags_horizontal / size_flags_vertical with set_properties instead (fill, expand, shrink_center...).")
		controls.append(node)
	if controls.is_empty():
		return WingmanError.new("NOTHING_TO_DO", "Pass node_paths.")

	var undo_redo: EditorUndoRedoManager = _context.get_undo_redo()
	undo_redo.create_action("Layout preset %s" % preset_name, UndoRedo.MERGE_DISABLE, controls[0])
	for control in controls:
		var values_before := _read_layout(control)
		control.set_anchors_and_offsets_preset(LAYOUT_PRESETS[preset_name][0], resize_mode, margin)
		var values_after := _read_layout(control)
		for property_name in LAYOUT_PROPERTIES:
			undo_redo.add_do_property(control, property_name, values_after[property_name])
			undo_redo.add_undo_property(control, property_name, values_before[property_name])
	undo_redo.commit_action()
	var changed: Array[String] = []
	for control in controls:
		var rectangle := control.get_global_rect()
		changed.append("%s rect=(%d, %d, %d x %d)" % [_context.describe_node_path(control), rectangle.position.x, rectangle.position.y, rectangle.size.x, rectangle.size.y])
	return {"preset": preset_name, "changed": changed}


## Theme overrides change one look item of one control (its font color, a margin, the
## panel style...) without a Theme resource. null removes an override.
func _set_theme_overrides(params: Dictionary) -> Variant:
	var node: Variant = _context.find_node_in_edited_scene(String(params.get("node_path", "")))
	if node is WingmanError:
		return node
	if not node is Control:
		return WingmanError.new("NOT_A_CONTROL", "%s is a %s; theme overrides are for Control nodes." % [node.name, node.get_class()])
	var override_values: Variant = _theme_overrides_to_properties(node, params)
	if override_values is WingmanError:
		return override_values
	if override_values.is_empty():
		return WingmanError.new("NOTHING_TO_DO", "Pass colors, constants, font_sizes, fonts, styles or icons.")
	var outcome := PropertyEditing.set_properties_with_undo(node, override_values, _context.get_undo_redo(), _context.get_edited_scene_root(), "Theme overrides of %s" % node.name)
	if outcome.has("errors"):
		return WingmanError.new("INVALID_VALUE", "Nothing was changed. " + " ".join(outcome["errors"]))
	return {"node_path": _context.describe_node_path(node), "changed": outcome["changed"]}


## Maps {"colors": {"font_color": "red"}} to {"theme_override_colors/font_color": "red"},
## checking that the control really has each item.
func _theme_overrides_to_properties(control: Control, overrides: Dictionary) -> Variant:
	var property_values := {}
	for group_name in THEME_OVERRIDE_PREFIXES:
		if not overrides.get(group_name) is Dictionary:
			continue
		var prefix: String = THEME_OVERRIDE_PREFIXES[group_name]
		for item_name in overrides[group_name]:
			var property_name := prefix + String(item_name)
			if PropertyEditing.find_property_information(control, property_name).is_empty():
				return WingmanError.new("UNKNOWN_THEME_ITEM", "%s has no %s item '%s'." % [control.get_class(), group_name, item_name], "Items of this control: %s." % ", ".join(_list_theme_items(control, prefix)))
			property_values[property_name] = overrides[group_name][item_name]
	return property_values


func _list_theme_items(control: Control, prefix: String) -> Array[String]:
	var item_names: Array[String] = []
	for property in control.get_property_list():
		if String(property["name"]).begins_with(prefix):
			item_names.append(String(property["name"]).trim_prefix(prefix))
	return item_names


## Builds a tree of nodes from a nested description, in one undo step. Made for UIs but
## works for any nodes.
func _build_ui(params: Dictionary) -> Variant:
	var scene_root: Node = _context.get_edited_scene_root()
	var parent: Variant = _context.find_node_in_edited_scene(String(params.get("parent_path", ".")))
	if parent is WingmanError:
		return parent
	var descriptions: Array = params.get("nodes", []) if params.get("nodes") is Array else []
	if descriptions.is_empty():
		return WingmanError.new("NOTHING_TO_DO", "Pass nodes: a list of {\"type\", \"name\", \"properties\", \"children\"}.")

	var built_roots: Array[Node] = []
	var created_nodes: Array[Node] = []
	var presets_to_apply: Array[Array] = []
	for description: Variant in descriptions:
		var built: Variant = _build_node(description, scene_root, created_nodes, presets_to_apply, "nodes")
		if built is WingmanError:
			for built_root in built_roots:
				built_root.free()
			return built
		built_roots.append(built)

	var undo_redo: EditorUndoRedoManager = _context.get_undo_redo()
	undo_redo.create_action("Build UI", UndoRedo.MERGE_DISABLE, parent)
	for built_root in built_roots:
		undo_redo.add_do_method(parent, "add_child", built_root, true)
	for created_node in created_nodes:
		undo_redo.add_do_property(created_node, "owner", scene_root)
	for preset in presets_to_apply:
		undo_redo.add_do_method(preset[0], "set_anchors_and_offsets_preset", preset[1], preset[2], preset[3])
	for built_root in built_roots:
		undo_redo.add_do_reference(built_root)
		undo_redo.add_undo_method(parent, "remove_child", built_root)
	undo_redo.commit_action()

	var created_paths: Array[String] = []
	for created_node in created_nodes:
		created_paths.append("%s (%s)" % [_context.describe_node_path(created_node), created_node.get_class()])
	return {"created": created_paths}


func _build_node(description: Variant, scene_root: Node, created_nodes: Array[Node], presets_to_apply: Array[Array], location: String) -> Variant:
	if not description is Dictionary or not description.has("type"):
		return WingmanError.new("INVALID_NODE", "%s: each node needs a type, for example {\"type\": \"Button\", \"name\": \"Play\", \"properties\": {\"text\": \"Play\"}}." % location)
	var node: Variant = SceneHandlers.instantiate_node_type(String(description["type"]))
	if node is WingmanError:
		node.message = "%s: %s" % [location, node.message]
		return node
	if description.has("name"):
		node.name = String(description["name"])
	var property_values: Dictionary = description.get("properties", {}).duplicate() if description.get("properties") is Dictionary else {}
	if node is Control and description.get("theme_overrides") is Dictionary:
		var override_values: Variant = _theme_overrides_to_properties(node, description["theme_overrides"])
		if override_values is WingmanError:
			node.free()
			return override_values
		property_values.merge(override_values, true)
	for property_path in property_values:
		var conversion := PropertyEditing.convert_for_property(node, String(property_path), property_values[property_path], scene_root)
		if not conversion["ok"]:
			node.free()
			return WingmanError.new("INVALID_PROPERTY", "%s (%s): %s" % [location, node.name, conversion["error"]])
		node.set_indexed(NodePath(String(property_path)), conversion["value"])
	created_nodes.append(node)

	if description.has("layout_preset"):
		var preset_name := String(description["layout_preset"])
		if not LAYOUT_PRESETS.has(preset_name) or not node is Control:
			node.free()
			return WingmanError.new("INVALID_PRESET", "%s (%s): layout_preset '%s' needs a Control and one of: %s." % [location, node.name, preset_name, ", ".join(LAYOUT_PRESETS.keys())])
		presets_to_apply.append([node, LAYOUT_PRESETS[preset_name][0], RESIZE_MODES.get(String(description.get("resize_mode", "minsize")), Control.PRESET_MODE_MINSIZE), int(description.get("margin", 0))])

	var children: Array = description.get("children", []) if description.get("children") is Array else []
	for child_index in children.size():
		var child: Variant = _build_node(children[child_index], scene_root, created_nodes, presets_to_apply, "%s > %s.children[%d]" % [location, node.name, child_index])
		if child is WingmanError:
			node.free()
			return child
		node.add_child(child, true)
	return node


func _read_layout(control: Control) -> Dictionary:
	var values := {}
	for property_name in LAYOUT_PROPERTIES:
		values[property_name] = control.get(property_name)
	return values


func _describe_anchors(control: Control) -> String:
	var anchors := [control.anchor_left, control.anchor_top, control.anchor_right, control.anchor_bottom]
	for preset_name in LAYOUT_PRESETS:
		if LAYOUT_PRESETS[preset_name][1] == anchors:
			return preset_name
	return "custom(%s)" % ", ".join(anchors.map(func(anchor: float) -> String: return str(snappedf(anchor, 0.01))))


func _describe_size_flags(flags: int) -> String:
	var parts: Array[String] = []
	if flags & Control.SIZE_EXPAND:
		parts.append("expand")
	match flags & ~Control.SIZE_EXPAND:
		Control.SIZE_FILL:
			parts.append("fill")
		Control.SIZE_SHRINK_CENTER:
			parts.append("center")
		Control.SIZE_SHRINK_END:
			parts.append("end")
		_:
			parts.append("begin")
	return "+".join(parts)


func _is_inside_scroll_or_subviewport(control: Control) -> bool:
	var ancestor := control.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer or ancestor is SubViewport:
			return true
		ancestor = ancestor.get_parent()
	return false
