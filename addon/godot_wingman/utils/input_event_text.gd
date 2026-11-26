@tool
extends RefCounted
## Converts between short text descriptions and Godot input events.
##
##   "key:W"  "key:Space"  "key:Ctrl+S"  "key:Shift+Up"
##   "mouse:left"  "mouse:right"  "mouse:middle"  "mouse:wheel_up"
##   "joy_button:a"  "joy_button:start"  "joy_button:3"
##   "joy_axis:left_x-"  "joy_axis:trigger_right+"
##
## Used for the input map (project settings) and for simulated player input.

const MOUSE_BUTTONS := {
	"left": MOUSE_BUTTON_LEFT, "right": MOUSE_BUTTON_RIGHT, "middle": MOUSE_BUTTON_MIDDLE,
	"wheel_up": MOUSE_BUTTON_WHEEL_UP, "wheel_down": MOUSE_BUTTON_WHEEL_DOWN,
	"wheel_left": MOUSE_BUTTON_WHEEL_LEFT, "wheel_right": MOUSE_BUTTON_WHEEL_RIGHT,
	"extra_1": MOUSE_BUTTON_XBUTTON1, "extra_2": MOUSE_BUTTON_XBUTTON2,
}
const JOYPAD_BUTTONS := {
	"a": JOY_BUTTON_A, "b": JOY_BUTTON_B, "x": JOY_BUTTON_X, "y": JOY_BUTTON_Y,
	"back": JOY_BUTTON_BACK, "guide": JOY_BUTTON_GUIDE, "start": JOY_BUTTON_START,
	"left_stick": JOY_BUTTON_LEFT_STICK, "right_stick": JOY_BUTTON_RIGHT_STICK,
	"left_shoulder": JOY_BUTTON_LEFT_SHOULDER, "right_shoulder": JOY_BUTTON_RIGHT_SHOULDER,
	"dpad_up": JOY_BUTTON_DPAD_UP, "dpad_down": JOY_BUTTON_DPAD_DOWN,
	"dpad_left": JOY_BUTTON_DPAD_LEFT, "dpad_right": JOY_BUTTON_DPAD_RIGHT,
}
const JOYPAD_AXES := {
	"left_x": JOY_AXIS_LEFT_X, "left_y": JOY_AXIS_LEFT_Y,
	"right_x": JOY_AXIS_RIGHT_X, "right_y": JOY_AXIS_RIGHT_Y,
	"trigger_left": JOY_AXIS_TRIGGER_LEFT, "trigger_right": JOY_AXIS_TRIGGER_RIGHT,
}
const MODIFIER_NAMES := ["ctrl", "shift", "alt", "meta", "cmd"]


## Returns an InputEvent, or a String with an error message.
static func parse(description: String) -> Variant:
	var kind := description.get_slice(":", 0).strip_edges().to_lower()
	var detail := description.substr(description.find(":") + 1).strip_edges()
	if not description.contains(":") or detail == "":
		return "'%s' is not an input description. Examples: \"key:Space\", \"mouse:left\", \"joy_button:a\", \"joy_axis:left_x-\"." % description

	match kind:
		"key":
			return _parse_key(detail)
		"mouse":
			if not MOUSE_BUTTONS.has(detail.to_lower()):
				return "Unknown mouse button '%s'. Use one of: %s." % [detail, ", ".join(MOUSE_BUTTONS.keys())]
			var mouse_event := InputEventMouseButton.new()
			mouse_event.button_index = MOUSE_BUTTONS[detail.to_lower()]
			return mouse_event
		"joy_button":
			var joypad_button_event := InputEventJoypadButton.new()
			if detail.is_valid_int():
				joypad_button_event.button_index = int(detail)
			elif JOYPAD_BUTTONS.has(detail.to_lower()):
				joypad_button_event.button_index = JOYPAD_BUTTONS[detail.to_lower()]
			else:
				return "Unknown joypad button '%s'. Use a number or one of: %s." % [detail, ", ".join(JOYPAD_BUTTONS.keys())]
			return joypad_button_event
		"joy_axis":
			var direction := -1.0 if detail.ends_with("-") else 1.0
			var axis_name := detail.trim_suffix("-").trim_suffix("+").to_lower()
			var joypad_motion_event := InputEventJoypadMotion.new()
			if axis_name.is_valid_int():
				joypad_motion_event.axis = int(axis_name)
			elif JOYPAD_AXES.has(axis_name):
				joypad_motion_event.axis = JOYPAD_AXES[axis_name]
			else:
				return "Unknown joypad axis '%s'. Use a number or one of: %s, followed by + or -." % [detail, ", ".join(JOYPAD_AXES.keys())]
			joypad_motion_event.axis_value = direction
			return joypad_motion_event
	return "Unknown input kind '%s'. Use key, mouse, joy_button or joy_axis." % kind


static func _parse_key(detail: String) -> Variant:
	var parts := detail.split("+", false)
	var key_name := parts[parts.size() - 1].strip_edges() if not parts.is_empty() else ""
	# "Ctrl++" means the plus key.
	if detail.ends_with("++") or detail == "+":
		key_name = "Plus"
	var keycode := OS.find_keycode_from_string(key_name)
	if keycode == KEY_NONE:
		return "Unknown key '%s'. Use names like A, Space, Enter, Escape, Up, Left, F1, Shift." % key_name

	var key_event := InputEventKey.new()
	key_event.keycode = keycode
	key_event.physical_keycode = keycode
	for part in parts.slice(0, parts.size() - 1):
		match part.strip_edges().to_lower():
			"ctrl":
				key_event.ctrl_pressed = true
			"shift":
				key_event.shift_pressed = true
			"alt":
				key_event.alt_pressed = true
			"meta", "cmd":
				key_event.meta_pressed = true
	return key_event


## The opposite of parse(): "key:Ctrl+S", "joy_axis:left_x-"...
static func describe(event: InputEvent) -> String:
	if event is InputEventKey:
		var key_code: int = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		var modifiers: Array[String] = []
		if event.ctrl_pressed:
			modifiers.append("Ctrl")
		if event.shift_pressed:
			modifiers.append("Shift")
		if event.alt_pressed:
			modifiers.append("Alt")
		if event.meta_pressed:
			modifiers.append("Meta")
		modifiers.append(OS.get_keycode_string(key_code))
		return "key:" + "+".join(modifiers)
	if event is InputEventMouseButton:
		var button_name: Variant = MOUSE_BUTTONS.find_key(event.button_index)
		return "mouse:%s" % (button_name if button_name != null else str(event.button_index))
	if event is InputEventJoypadButton:
		var joypad_button_name: Variant = JOYPAD_BUTTONS.find_key(event.button_index)
		return "joy_button:%s" % (joypad_button_name if joypad_button_name != null else str(event.button_index))
	if event is InputEventJoypadMotion:
		var axis_name: Variant = JOYPAD_AXES.find_key(event.axis)
		return "joy_axis:%s%s" % [axis_name if axis_name != null else str(event.axis), "-" if event.axis_value < 0 else "+"]
	return event.as_text()
