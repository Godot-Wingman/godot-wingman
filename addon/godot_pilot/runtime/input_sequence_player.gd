extends RefCounted
## Plays a list of input steps inside the running game, like a person at the keyboard,
## mouse or gamepad would. Timing happens in the game itself (frame by frame), so holds
## and sequences are exact no matter how slow the connection to the AI is.
##
## Events go through Input.parse_input_event(), the same path real devices use, so
## _input(), _unhandled_input(), GUI controls and Input.is_action_pressed() all see them.
##
## Steps (one key per step):
##   {"press": "key:Space"}            {"release": "key:Space"}
##   {"tap": "action:jump"}            {"hold": "key:Right", "seconds": 1.5}
##   {"wait_seconds": 0.5}             {"wait_frames": 10}
##   {"mouse_move": [x, y]}            {"mouse_click": [x, y], "button": "left", "double": false}
##   {"mouse_drag": {"from": [x, y], "to": [x, y], "seconds": 0.3}}
##   {"type_text": "hello"}
##   {"wait_until": "node(\"Player\").position.x > 200", "timeout_seconds": 5}
## wait_until is checked every physics frame, so a sequence can react to the game (jump
## when the player reaches the edge) instead of guessing times. If a step fails, the
## inputs the sequence still holds are released.
## Mouse positions are pixels of the game viewport (the size shown with screenshots).

const InputEventText := preload("../utils/input_event_text.gd")

const DRAG_STEPS_PER_SECOND := 60
const DEFAULT_CONDITION_TIMEOUT_SECONDS := 10.0

var _tree: SceneTree
var _viewport: Viewport
## Object whose methods wait_until expressions can call, like node("Player").
var _expression_base: Object


func _init(tree: SceneTree, expression_base: Object = null) -> void:
	_tree = tree
	_viewport = tree.root
	_expression_base = expression_base


## Plays every step and returns a log of what happened, or {"error": ...} on a bad step.
func play(steps: Array) -> Dictionary:
	var performed_steps: Array[String] = []
	var held_inputs: Array[String] = []
	for step_index in steps.size():
		var step: Variant = steps[step_index]
		if not step is Dictionary:
			await _release_all(held_inputs)
			return {"error": "Step %d is not an object." % step_index, "performed": performed_steps}
		var outcome: Variant = await _play_step(step)
		if outcome is String and outcome.begins_with("ERROR:"):
			var released_text := await _release_all(held_inputs)
			return {"error": "Step %d: %s%s" % [step_index, outcome.trim_prefix("ERROR: "), released_text], "performed": performed_steps}
		if step.has("press"):
			held_inputs.append(String(step["press"]))
		elif step.has("release"):
			held_inputs.erase(String(step["release"]))
		performed_steps.append(outcome)
	# A press without a matching release would keep the player running after the sequence.
	var released_at_end := await _release_all(held_inputs)
	if released_at_end != "":
		performed_steps.append("end of sequence" + released_at_end)
	return {"performed": performed_steps}


## Lets go of inputs that are still held when a sequence ends or fails, so the game
## does not keep running.
func _release_all(held_inputs: Array[String]) -> String:
	if held_inputs.is_empty():
		return ""
	for input_text in held_inputs:
		await _send_input(input_text, false, "")
	return " (released %s)" % ", ".join(held_inputs)


func _wait_until_condition(condition: String, timeout_seconds: float) -> String:
	var expression := Expression.new()
	if expression.parse(condition, ["scene", "tree"]) != OK:
		return "ERROR: could not parse '%s': %s" % [condition, expression.get_error_text()]
	var start_milliseconds := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - start_milliseconds) / 1000.0 < timeout_seconds:
		var value: Variant = expression.execute([_tree.current_scene, _tree], _expression_base, false)
		if expression.has_execute_failed():
			return "ERROR: '%s' failed: %s" % [condition, expression.get_error_text()]
		if value:
			return "waited until %s (%ss)" % [condition, snappedf((Time.get_ticks_msec() - start_milliseconds) / 1000.0, 0.01)]
		await _tree.physics_frame
	return "ERROR: '%s' was still false after %ss" % [condition, timeout_seconds]


func _play_step(step: Dictionary) -> String:
	if step.has("press"):
		return await _send_input(String(step["press"]), true, "pressed")
	if step.has("release"):
		return await _send_input(String(step["release"]), false, "released")
	if step.has("tap"):
		var pressed_outcome := await _send_input(String(step["tap"]), true, "tapped")
		if pressed_outcome.begins_with("ERROR:"):
			return pressed_outcome
		# Also held for two physics ticks: games often read is_action_just_pressed() in
		# _physics_process, which runs less often than frames on fast screens.
		await _wait_frames(2)
		for physics_tick in 2:
			await _tree.physics_frame
		await _send_input(String(step["tap"]), false, "")
		return pressed_outcome
	if step.has("hold"):
		var held_outcome := await _send_input(String(step["hold"]), true, "held")
		if held_outcome.begins_with("ERROR:"):
			return held_outcome
		await _wait_seconds(float(step.get("seconds", 0.5)))
		await _send_input(String(step["hold"]), false, "")
		return "%s for %ss" % [held_outcome, step.get("seconds", 0.5)]
	if step.has("wait_seconds"):
		await _wait_seconds(float(step["wait_seconds"]))
		return "waited %ss" % step["wait_seconds"]
	if step.has("wait_until"):
		return await _wait_until_condition(String(step["wait_until"]), float(step.get("timeout_seconds", DEFAULT_CONDITION_TIMEOUT_SECONDS)))
	if step.has("wait_frames"):
		await _wait_frames(int(step["wait_frames"]))
		return "waited %d frames" % int(step["wait_frames"])
	if step.has("mouse_move"):
		var target_position: Variant = _read_position(step["mouse_move"])
		if target_position is String:
			return target_position
		_move_mouse(target_position, Vector2.ZERO, 0)
		await _wait_frames(1)
		return "mouse moved to %s" % target_position
	if step.has("mouse_click"):
		return await _click(step)
	if step.has("mouse_drag"):
		return await _drag(step["mouse_drag"])
	if step.has("type_text"):
		return await _type_text(String(step["type_text"]))
	return "ERROR: unknown step %s. Use press, release, tap, hold, wait_seconds, wait_frames, wait_until, mouse_move, mouse_click, mouse_drag or type_text." % JSON.stringify(step)


## Sends a press or release of "key:...", "mouse:...", "joy_button:...", "joy_axis:..." or "action:...".
func _send_input(description: String, pressed: bool, verb: String) -> String:
	var event: InputEvent
	if description.begins_with("action:"):
		var action_name := description.trim_prefix("action:")
		if not InputMap.has_action(action_name):
			return "ERROR: the game has no input action '%s'." % action_name
		var action_event := InputEventAction.new()
		action_event.action = action_name
		action_event.pressed = pressed
		action_event.strength = 1.0 if pressed else 0.0
		event = action_event
	else:
		var parsed: Variant = InputEventText.parse(description)
		if parsed is String:
			return "ERROR: " + parsed
		event = parsed
		if event is InputEventJoypadMotion:
			if not pressed:
				event.axis_value = 0.0
		elif event is InputEventMouseButton:
			event.position = _viewport.get_mouse_position()
			event.global_position = event.position
			event.pressed = pressed
		else:
			event.pressed = pressed
	Input.parse_input_event(event)
	await _wait_frames(1)
	return "%s %s" % [verb, description]


func _click(step: Dictionary) -> String:
	var click_position: Variant = _read_position(step["mouse_click"])
	if click_position is String:
		return click_position
	var button_name := String(step.get("button", "left"))
	if not InputEventText.MOUSE_BUTTONS.has(button_name):
		return "ERROR: unknown mouse button '%s'." % button_name
	_move_mouse(click_position, Vector2.ZERO, 0)
	await _wait_frames(1)
	var click_count := 2 if bool(step.get("double", false)) else 1
	for click_index in click_count:
		for pressed in [true, false]:
			var button_event := InputEventMouseButton.new()
			button_event.button_index = InputEventText.MOUSE_BUTTONS[button_name]
			button_event.pressed = pressed
			button_event.double_click = click_index == 1 and pressed
			_set_event_position(button_event, click_position)
			Input.parse_input_event(button_event)
			await _wait_frames(1)
	return "%s-clicked at %s%s" % [button_name, click_position, " (double)" if click_count == 2 else ""]


func _drag(drag: Variant) -> String:
	if not drag is Dictionary:
		return "ERROR: mouse_drag needs {\"from\": [x, y], \"to\": [x, y], \"seconds\": 0.3}."
	var start_position: Variant = _read_position(drag.get("from"))
	var end_position: Variant = _read_position(drag.get("to"))
	if start_position is String:
		return start_position
	if end_position is String:
		return end_position
	var step_count := maxi(2, int(float(drag.get("seconds", 0.3)) * DRAG_STEPS_PER_SECOND))

	_move_mouse(start_position, Vector2.ZERO, 0)
	var press_event := InputEventMouseButton.new()
	press_event.button_index = MOUSE_BUTTON_LEFT
	press_event.pressed = true
	_set_event_position(press_event, start_position)
	Input.parse_input_event(press_event)
	await _wait_frames(1)

	var previous_position: Vector2 = start_position
	for step_number in range(1, step_count + 1):
		var current_position: Vector2 = start_position.lerp(end_position, float(step_number) / step_count)
		_move_mouse(current_position, current_position - previous_position, MOUSE_BUTTON_MASK_LEFT)
		previous_position = current_position
		await _wait_frames(1)

	var release_event := InputEventMouseButton.new()
	release_event.button_index = MOUSE_BUTTON_LEFT
	release_event.pressed = false
	_set_event_position(release_event, end_position)
	Input.parse_input_event(release_event)
	await _wait_frames(1)
	return "dragged from %s to %s" % [start_position, end_position]


func _type_text(text: String) -> String:
	for character in text:
		for pressed in [true, false]:
			var key_event := InputEventKey.new()
			key_event.pressed = pressed
			key_event.unicode = character.unicode_at(0)
			key_event.keycode = OS.find_keycode_from_string(character.to_upper())
			Input.parse_input_event(key_event)
		await _wait_frames(1)
	return "typed %d characters" % text.length()


func _move_mouse(viewport_position: Vector2, relative_motion: Vector2, button_mask: int) -> void:
	var motion_event := InputEventMouseMotion.new()
	motion_event.relative = relative_motion
	motion_event.button_mask = button_mask
	_set_event_position(motion_event, viewport_position)
	Input.parse_input_event(motion_event)


## Events from Input.parse_input_event() are in window pixels; convert from viewport
## pixels so clicks land where they appear in screenshots, whatever the stretch mode.
func _set_event_position(event: InputEventMouse, viewport_position: Vector2) -> void:
	var window_position := _viewport.get_screen_transform() * viewport_position
	event.position = window_position
	event.global_position = window_position


func _read_position(value: Variant) -> Variant:
	if value is Array and value.size() == 2:
		return Vector2(float(value[0]), float(value[1]))
	return "ERROR: a position must be [x, y] in game viewport pixels, got %s." % JSON.stringify(value)


func _wait_frames(frame_count: int) -> void:
	for frame_index in maxi(frame_count, 0):
		await _tree.process_frame


## Waits in game time; works while the game is paused too, because it counts real time.
func _wait_seconds(seconds: float) -> void:
	await _tree.create_timer(maxf(seconds, 0.0), true, false, true).timeout
