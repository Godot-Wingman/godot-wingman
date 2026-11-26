@tool
extends RefCounted
## Shows the dialog that asks the person whether the AI may make a change.
##
## Used in the "confirm" permission mode. The dialog shows which AI asks, which tool it
## wants to use and every argument in full: code and file contents in scrollable text
## boxes, so nothing runs that the person could not read first.
## Buttons: "Allow", "Allow <tool> for this session" and "Deny".

const DEFAULT_TIMEOUT_SECONDS := 120.0
## Text arguments longer than this, or with several lines, get their own text box.
const LONG_TEXT_LENGTH := 100

const ANSWER_ALLOW := "allow"
const ANSWER_ALLOW_FOR_SESSION := "allow_for_session"
const ANSWER_DENY := "deny"
const ANSWER_NO_ANSWER := "no_answer"


## Shows the dialog and waits. Returns one of the ANSWER_* constants. Closing the
## dialog counts as "deny", waiting longer than `timeout_seconds` as "no_answer".
static func ask_about_tool(
	client_name: String,
	tool_name: String,
	tool_title: String,
	tool_input: Dictionary,
	timeout_seconds: float = DEFAULT_TIMEOUT_SECONDS
) -> String:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Godot Pilot: the AI wants to make a change"
	dialog.ok_button_text = "Allow"
	dialog.cancel_button_text = "Deny"
	dialog.add_button("Allow \"%s\" for this session" % tool_name, false, ANSWER_ALLOW_FOR_SESSION)
	var editor_scale := EditorInterface.get_editor_scale()
	dialog.min_size = Vector2i(Vector2(560, 300) * editor_scale)
	dialog.add_child(_build_content(client_name, tool_name, tool_title, tool_input, editor_scale))
	return await _show_and_wait(dialog, timeout_seconds, Vector2i(Vector2(900, 560) * editor_scale))


## The older, plain form: a title and a text. Returns true when allowed.
static func ask(title: String, description: String, timeout_seconds: float = DEFAULT_TIMEOUT_SECONDS) -> bool:
	var dialog := ConfirmationDialog.new()
	dialog.title = "AI request: %s" % title
	dialog.dialog_text = description
	dialog.dialog_autowrap = true
	dialog.ok_button_text = "Allow"
	dialog.cancel_button_text = "Deny"
	dialog.min_size = Vector2i(Vector2(520, 0) * EditorInterface.get_editor_scale())
	return await _show_and_wait(dialog, timeout_seconds) == ANSWER_ALLOW


static func _build_content(client_name: String, tool_name: String, tool_title: String, tool_input: Dictionary, editor_scale: float) -> Control:
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", int(8 * editor_scale))

	var summary := Label.new()
	summary.text = "%s wants to use \"%s\" (%s)." % [client_name, tool_name, tool_title]
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# An autowrapped label without a width asks for one line per word, which makes the
	# dialog as tall as the screen.
	summary.custom_minimum_size = Vector2(520, 0) * editor_scale
	content.add_child(summary)

	var short_arguments := {}
	for argument_name: String in tool_input:
		var argument_value: Variant = tool_input[argument_name]
		if argument_value is String and (argument_value.contains("\n") or argument_value.length() > LONG_TEXT_LENGTH):
			content.add_child(_build_heading(argument_name))
			content.add_child(_build_text_box(argument_value, editor_scale, argument_name in ["code", "content", "source"]))
		else:
			short_arguments[argument_name] = argument_value

	if not short_arguments.is_empty():
		content.add_child(_build_heading("Arguments"))
		content.add_child(_build_text_box(JSON.stringify(short_arguments, "  "), editor_scale, false))
	elif tool_input.is_empty():
		content.add_child(_build_heading("No arguments."))
	return content


static func _build_heading(text: String) -> Label:
	var heading := Label.new()
	heading.text = text
	heading.add_theme_color_override("font_color", EditorInterface.get_base_control().get_theme_color("accent_color", "Editor"))
	return heading


static func _build_text_box(text: String, editor_scale: float, is_code: bool) -> TextEdit:
	var text_box: TextEdit = CodeEdit.new() if is_code else TextEdit.new()
	text_box.text = text
	text_box.editable = false
	# Code keeps its lines (scroll sideways); other text wraps.
	text_box.wrap_mode = TextEdit.LINE_WRAPPING_NONE if is_code else TextEdit.LINE_WRAPPING_BOUNDARY
	text_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_box.size_flags_stretch_ratio = 3.0 if is_code else 1.0
	text_box.custom_minimum_size = Vector2(0, 70 * editor_scale)
	text_box.add_theme_font_override("font", EditorInterface.get_base_control().get_theme_font("source", "EditorFonts"))
	if text_box is CodeEdit:
		(text_box as CodeEdit).gutters_draw_line_numbers = true
	return text_box


## `wanted_size` zero means: as small as the content allows.
static func _show_and_wait(dialog: ConfirmationDialog, timeout_seconds: float, wanted_size: Vector2i = Vector2i.ZERO) -> String:
	# The buttons and the timer report into this small state object, and we wait until
	# one of them has written an answer.
	var decision := {"answer": ""}
	var remember_answer := func(answer: String) -> void:
		if decision["answer"] == "":
			decision["answer"] = answer
	dialog.confirmed.connect(remember_answer.bind(ANSWER_ALLOW))
	dialog.canceled.connect(remember_answer.bind(ANSWER_DENY))
	dialog.custom_action.connect(func(action: StringName) -> void: remember_answer.call(String(action)))

	var base_control := EditorInterface.get_base_control()
	base_control.add_child(dialog)
	if wanted_size == Vector2i.ZERO:
		dialog.popup_centered()
	else:
		# Never larger than 85% of the screen, so the buttons stay visible.
		dialog.popup_centered_clamped(wanted_size, 0.85)
	if DisplayServer.has_method("window_request_attention"):
		DisplayServer.window_request_attention()

	var tree := base_control.get_tree()
	var deadline_milliseconds := Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while decision["answer"] == "" and Time.get_ticks_msec() < deadline_milliseconds:
		await tree.process_frame

	dialog.queue_free()
	return decision["answer"] if decision["answer"] != "" else ANSWER_NO_ANSWER
