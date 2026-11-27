@tool
extends VBoxContainer
## The Chat tab of the Godot Wingman panel: the person talks to the connected AIs.
##
## Top: who the message goes to, every AI or one of them, with the number of unread
## answers. Middle: the conversation as message bubbles, the person's on the right,
## with who wrote to whom, when, and whether the AI has read it. AI answers are shown
## as formatted Markdown, code blocks with a Copy button. Bottom: whether the AI gets
## the message right away (it is listening, wait_for_person_message) or with its next
## step, then the attachments and the text field.
##
## Attachments: project files and folders, selected nodes, a screenshot of the editor,
## files from this computer. Files and nodes can be dragged in from the FileSystem and
## Scene docks.

signal unread_count_changed(unread_count: int)

const WingmanSession := preload("../session/wingman_session.gd")
const NoticeBoard := preload("../session/notice_board.gd")
const MarkdownText := preload("markdown_text.gd")

const LISTEN_REQUEST := "Listen to me in the Godot Wingman chat."
const ATTACHMENT_DIRECTORY := "res://.godot/godot_wingman/attachments"
const IMAGE_EXTENSIONS := ["png", "jpg", "jpeg", "webp", "bmp", "svg"]
const MENU_PROJECT_FILE := 0
const MENU_SELECTED_NODES := 1
const MENU_SCREENSHOT := 2
const MENU_COMPUTER_FILE := 3
## Widest a message bubble gets, before the editor scale.
const MAXIMUM_BUBBLE_WIDTH := 720.0
const MINIMUM_COMPOSER_LINES := 1
const MAXIMUM_COMPOSER_LINES := 8

var _session: RefCounted
var _editor_scale: float
var _theme: Theme

var _recipient_row: HBoxContainer
var _recipient_group := ButtonGroup.new()
var _thread_scroll: ScrollContainer
var _thread_list: VBoxContainer
var _status_label: Label
var _copy_request_button: Button
var _attachment_row: HFlowContainer
var _composer: TextEdit
var _send_button: Button
var _file_dialog: EditorFileDialog

var _conversation_id := WingmanSession.EVERYONE
var _attachments: Array[Dictionary] = []
## conversation id -> id of the newest message the person has seen in it.
var _seen_up_to: Dictionary = {}
## [bubble, wanted width], so bubbles can be fitted again when the panel is resized.
var _bubbles: Array = []


func _init(session: RefCounted) -> void:
	_session = session
	_editor_scale = EditorInterface.get_editor_scale()
	_theme = EditorInterface.get_editor_theme()
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", int(4 * _editor_scale))
	_build_recipient_row()
	_build_thread()
	_build_composer()
	_session.messages_changed.connect(refresh)
	_session.connections_changed.connect(refresh)
	_session.listening_changed.connect(_refresh_status)
	_session.activity_changed.connect(_refresh_status)
	visibility_changed.connect(func() -> void:
		if is_visible_in_tree():
			_mark_conversation_seen()
	)
	refresh()


## Opens the conversation with one AI (its connection id) or with every AI.
func select_conversation(conversation_id: int) -> void:
	_conversation_id = conversation_id
	refresh()
	_composer.grab_focus.call_deferred()


## The "To" buttons. The panel puts them next to its tabs, so they take no row of
## their own, and shows them while the Chat tab is open.
func get_recipient_row() -> Control:
	return _recipient_row


func get_unread_count() -> int:
	var unread_count := 0
	for conversation_id: int in _get_conversation_ids():
		unread_count += _count_unread(conversation_id)
	return unread_count


func refresh() -> void:
	if _conversation_id != WingmanSession.EVERYONE and not _session.connections.has(_conversation_id) and _session.get_conversation(_conversation_id).is_empty():
		_conversation_id = WingmanSession.EVERYONE
	if is_visible_in_tree():
		_mark_conversation_seen()
	_rebuild_recipients()
	_rebuild_thread()
	_refresh_status()
	unread_count_changed.emit(get_unread_count())


# --- Building -------------------------------------------------------------------------

func _build_recipient_row() -> void:
	_recipient_row = HBoxContainer.new()
	_recipient_row.add_theme_constant_override("separation", int(4 * _editor_scale))
	_recipient_row.alignment = BoxContainer.ALIGNMENT_END
	_recipient_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_recipient_row.clip_contents = true


func _build_thread() -> void:
	_thread_scroll = ScrollContainer.new()
	_thread_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_thread_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_thread_scroll.add_theme_stylebox_override("panel", _make_box(_thread_color(), 4, 10))
	_thread_scroll.resized.connect(_fit_bubbles)
	add_child(_thread_scroll)
	_thread_list = VBoxContainer.new()
	_thread_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_thread_list.add_theme_constant_override("separation", int(10 * _editor_scale))
	_thread_scroll.add_child(_thread_list)


## One box, like the message field of a chat app: the attachments, the text, and under
## it a toolbar with the attach button, whether the AI hears the message right away,
## and Send. Nothing of it takes a row outside the box.
func _build_composer() -> void:
	var composer_box := PanelContainer.new()
	var box_style := _make_box(_composer_color(), 6, 6)
	box_style.set_border_width_all(int(maxf(1.0, _editor_scale)))
	box_style.border_color = Color(_color("font_color"), 0.12)
	var focused_box_style := box_style.duplicate()
	focused_box_style.border_color = _color("accent_color")
	composer_box.add_theme_stylebox_override("panel", box_style)
	add_child(composer_box)
	var box_column := VBoxContainer.new()
	box_column.add_theme_constant_override("separation", int(2 * _editor_scale))
	composer_box.add_child(box_column)

	_attachment_row = HFlowContainer.new()
	_attachment_row.add_theme_constant_override("h_separation", int(4 * _editor_scale))
	_attachment_row.visible = false
	box_column.add_child(_attachment_row)

	_composer = TextEdit.new()
	_composer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_composer.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	for style_name: String in ["normal", "focus", "read_only"]:
		_composer.add_theme_stylebox_override(style_name, StyleBoxEmpty.new())
	_composer.gui_input.connect(_on_composer_input)
	_composer.text_changed.connect(_fit_composer_height)
	_composer.text_changed.connect(_refresh_send_button)
	_composer.focus_entered.connect(func() -> void: composer_box.add_theme_stylebox_override("panel", focused_box_style))
	_composer.focus_exited.connect(func() -> void: composer_box.add_theme_stylebox_override("panel", box_style))
	_composer.set_drag_forwarding(Callable(), _can_drop_on_composer, _drop_on_composer)
	box_column.add_child(_composer)

	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", int(4 * _editor_scale))
	box_column.add_child(toolbar)
	var add_button := MenuButton.new()
	add_button.icon = _icon("Add")
	add_button.flat = true
	add_button.tooltip_text = "Attach files, folders, nodes or a screenshot. You can also drag files and nodes onto the text field."
	var add_menu := add_button.get_popup()
	add_menu.add_icon_item(_icon("Load"), "File or folder of the project...", MENU_PROJECT_FILE)
	add_menu.add_icon_item(_icon("Node"), "Selected nodes", MENU_SELECTED_NODES)
	add_menu.add_icon_item(_icon("Image"), "Screenshot of the editor", MENU_SCREENSHOT)
	add_menu.add_icon_item(_icon("Folder"), "File from this computer...", MENU_COMPUTER_FILE)
	add_menu.id_pressed.connect(_on_add_menu_pressed)
	toolbar.add_child(add_button)

	_status_label = Label.new()
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_label.clip_text = true
	_status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status_label.mouse_filter = Control.MOUSE_FILTER_PASS
	_status_label.add_theme_font_size_override("font_size", _small_font_size())
	toolbar.add_child(_status_label)
	_copy_request_button = Button.new()
	_copy_request_button.text = "Copy request"
	_copy_request_button.icon = _icon("ActionCopy")
	_copy_request_button.flat = true
	_copy_request_button.add_theme_font_size_override("font_size", _small_font_size())
	_copy_request_button.tooltip_text = "Copies \"%s\" to paste into the AI's own app." % LISTEN_REQUEST
	_copy_request_button.pressed.connect(func() -> void: DisplayServer.clipboard_set(LISTEN_REQUEST))
	toolbar.add_child(_copy_request_button)

	_send_button = Button.new()
	_send_button.text = "Send"
	_send_button.icon = _icon("ArrowRight")
	_send_button.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_send_button.pressed.connect(_send)
	_style_send_button()
	toolbar.add_child(_send_button)
	_fit_composer_height()


func _rebuild_recipients() -> void:
	for child in _recipient_row.get_children():
		child.queue_free()
	var to_label := Label.new()
	to_label.text = "To"
	to_label.add_theme_color_override("font_color", _dim_text_color())
	_recipient_row.add_child(to_label)
	for conversation_id: int in _get_conversation_ids():
		var title := "Every AI" if conversation_id == WingmanSession.EVERYONE else _get_name(conversation_id)
		if conversation_id != WingmanSession.EVERYONE and not _session.connections.has(conversation_id):
			title += " (left)"
		var unread_count := _count_unread(conversation_id)
		if unread_count > 0:
			title += "  %d" % unread_count
		var recipient_button := Button.new()
		recipient_button.text = title
		recipient_button.toggle_mode = true
		recipient_button.button_group = _recipient_group
		recipient_button.button_pressed = conversation_id == _conversation_id
		recipient_button.focus_mode = Control.FOCUS_NONE
		_style_recipient_button(recipient_button, unread_count > 0)
		recipient_button.pressed.connect(select_conversation.bind(conversation_id))
		_recipient_row.add_child(recipient_button)


func _rebuild_thread() -> void:
	for child in _thread_list.get_children():
		child.queue_free()
	_bubbles.clear()
	var conversation: Array[Dictionary] = _session.get_conversation(_conversation_id)
	if conversation.is_empty():
		_thread_list.add_child(_make_hint(_empty_conversation_text()))
	for message in conversation:
		_thread_list.add_child(_build_event_row(message) if message["is_event"] else _build_message_row(message))
	_fit_bubbles()
	_scroll_to_bottom.call_deferred()


func _build_event_row(message: Dictionary) -> Control:
	var event_label := Label.new()
	event_label.text = "%s   %s" % [message["time"], message["text"]]
	event_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	event_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	event_label.add_theme_color_override("font_color", _dim_text_color())
	event_label.add_theme_font_size_override("font_size", _small_font_size())
	return event_label


func _build_message_row(message: Dictionary) -> Control:
	var is_mine := int(message["from_id"]) == NoticeBoard.PERSON
	var row := HBoxContainer.new()
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bubble := PanelContainer.new()
	var bubble_box := _make_box(Color(_color("accent_color"), 0.2) if is_mine else _bubble_color(), 8, 10)
	bubble_box.content_margin_top = 7 * _editor_scale
	bubble_box.content_margin_bottom = 7 * _editor_scale
	bubble.add_theme_stylebox_override("panel", bubble_box)
	if is_mine:
		row.add_child(spacer)
		row.add_child(bubble)
	else:
		row.add_child(bubble)
		row.add_child(spacer)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", int(4 * _editor_scale))
	bubble.add_child(column)
	column.add_child(_build_message_header(message))

	var wanted_width := 0.0
	var font: Font = _theme.get_font("main", "EditorFonts")
	var font_size := _theme.get_font_size("main_size", "EditorFonts")
	var text := String(message["text"])
	# The person's messages are shown as written; the AIs write Markdown.
	var parts: Array[Dictionary] = []
	if is_mine:
		parts.append({"type": MarkdownText.PART_TEXT, "bbcode": _escape_bbcode(text)})
	else:
		parts = MarkdownText.to_parts(text, {"dim": _dim_text_color(), "code_background": _code_background_color(), "link": _color("accent_color").lightened(0.2)}, font_size)
	for part in parts:
		if part["type"] == MarkdownText.PART_CODE:
			column.add_child(_build_code_block(String(part["code"]), String(part["language"])))
			wanted_width = INF
		else:
			column.add_child(_build_text_block(String(part["bbcode"])))
			if String(part["bbcode"]).contains("[table="):
				wanted_width = INF
	var plain_text := text if is_mine else MarkdownText.to_plain_text(text)
	for line in plain_text.split("\n"):
		wanted_width = maxf(wanted_width, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x * 1.08)
	if not Array(message["attachments"]).is_empty():
		column.add_child(_build_attachment_list(message["attachments"], false))
		wanted_width = maxf(wanted_width, 260 * _editor_scale)
	if is_mine:
		var read_label := Label.new()
		read_label.text = _describe_read_state(message)
		read_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		read_label.add_theme_color_override("font_color", _dim_text_color())
		read_label.add_theme_font_size_override("font_size", _small_font_size())
		column.add_child(read_label)
	var header_width := font.get_string_size("%s to %s   %s" % [message["sender"], message["receiver"], message["time"]], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	_bubbles.append([bubble, maxf(wanted_width, header_width + 24 * _editor_scale)])
	return row


## "Claude Code to You · 14:02" in the AI's bubble, "You to Claude Code" in the person's.
func _build_message_header(message: Dictionary) -> Control:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", int(6 * _editor_scale))
	var sender_label := Label.new()
	sender_label.text = String(message["sender"])
	sender_label.add_theme_font_override("font", _theme.get_font("bold", "EditorFonts"))
	sender_label.add_theme_font_size_override("font_size", _small_font_size())
	header.add_child(sender_label)
	var receiver_label := Label.new()
	receiver_label.text = "to %s" % ("every AI" if int(message["to_id"]) == WingmanSession.EVERYONE else String(message["receiver"]))
	receiver_label.add_theme_color_override("font_color", _dim_text_color())
	receiver_label.add_theme_font_size_override("font_size", _small_font_size())
	receiver_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(receiver_label)
	var time_label := Label.new()
	time_label.text = String(message["time"])
	time_label.add_theme_color_override("font_color", _dim_text_color())
	time_label.add_theme_font_size_override("font_size", _small_font_size())
	header.add_child(time_label)
	return header


func _build_text_block(bbcode: String) -> RichTextLabel:
	var text_block := RichTextLabel.new()
	text_block.bbcode_enabled = true
	text_block.fit_content = true
	text_block.scroll_active = false
	text_block.selection_enabled = true
	text_block.context_menu_enabled = true
	text_block.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# The editor theme gives rich text a dark box; in a bubble the text sits on the bubble.
	text_block.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	text_block.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	text_block.add_theme_font_override("mono_font", _theme.get_font("source", "EditorFonts"))
	text_block.add_theme_font_override("bold_font", _theme.get_font("bold", "EditorFonts"))
	text_block.add_theme_constant_override("line_separation", int(2 * _editor_scale))
	text_block.meta_clicked.connect(_open_link)
	text_block.text = bbcode
	return text_block


func _build_code_block(code: String, language: String) -> Control:
	var code_panel := PanelContainer.new()
	code_panel.add_theme_stylebox_override("panel", _make_box(_code_background_color(), 4, 8))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", int(2 * _editor_scale))
	code_panel.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var language_label := Label.new()
	language_label.text = language if language != "" else "code"
	language_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	language_label.add_theme_color_override("font_color", _dim_text_color())
	language_label.add_theme_font_size_override("font_size", _small_font_size())
	header.add_child(language_label)
	var copy_button := Button.new()
	copy_button.text = "Copy"
	copy_button.icon = _icon("ActionCopy")
	copy_button.flat = true
	copy_button.add_theme_font_size_override("font_size", _small_font_size())
	copy_button.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(code)
		copy_button.text = "Copied"
	)
	header.add_child(copy_button)
	var code_scroll := ScrollContainer.new()
	code_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(code_scroll)
	var code_label := Label.new()
	# A Label draws tabs without width.
	code_label.text = code.replace(char(9), "    ")
	code_label.mouse_filter = Control.MOUSE_FILTER_PASS
	code_label.add_theme_font_override("font", _theme.get_font("source", "EditorFonts"))
	code_scroll.add_child(code_label)
	return code_panel


## Attachments as small buttons that open them. In the composer they have a remove
## button too.
func _build_attachment_list(attachments: Array, can_remove: bool) -> Control:
	var attachment_flow := HFlowContainer.new()
	attachment_flow.add_theme_constant_override("h_separation", int(4 * _editor_scale))
	attachment_flow.add_theme_constant_override("v_separation", int(4 * _editor_scale))
	for attachment_index in attachments.size():
		var attachment: Dictionary = attachments[attachment_index]
		var chip := HBoxContainer.new()
		chip.add_theme_constant_override("separation", 0)
		var open_button := Button.new()
		open_button.text = _describe_attachment(attachment)
		open_button.icon = _attachment_icon(attachment)
		open_button.tooltip_text = String(attachment["path"]) if attachment["kind"] != "node" else "%s in %s" % [attachment["path"], attachment.get("scene", "")]
		open_button.add_theme_font_size_override("font_size", _small_font_size())
		open_button.focus_mode = Control.FOCUS_NONE
		open_button.pressed.connect(_open_attachment.bind(attachment))
		chip.add_child(open_button)
		if can_remove:
			var remove_button := Button.new()
			remove_button.icon = _icon("Close")
			remove_button.tooltip_text = "Remove"
			remove_button.focus_mode = Control.FOCUS_NONE
			remove_button.pressed.connect(func() -> void:
				_attachments.remove_at(attachment_index)
				_refresh_attachment_row()
			)
			chip.add_child(remove_button)
		attachment_flow.add_child(chip)
	return attachment_flow


# --- Refreshing -----------------------------------------------------------------------

func _refresh_status() -> void:
	var has_ai: bool = not _session.connections.is_empty()
	_composer.editable = has_ai
	_copy_request_button.visible = false
	var status_color := _dim_text_color()
	var status_text := ""
	var status_tooltip := ""
	if not has_ai:
		status_text = "No AI connected. Start your AI app and ask it to use Godot."
		_composer.placeholder_text = ""
	elif _conversation_id == WingmanSession.EVERYONE:
		var listening_names := PackedStringArray()
		for connection_id: int in _session.listening:
			listening_names.append(_get_name(connection_id))
		if listening_names.is_empty():
			status_text = "Each AI reads it with its next step"
		else:
			status_text = "Listening: %s. The others read it with their next step" % ", ".join(listening_names)
			status_color = _color("success_color")
		_composer.placeholder_text = "Write to every AI. Shift+Enter for a new line."
	elif not _session.connections.has(_conversation_id):
		status_text = "%s has left" % _get_name(_conversation_id)
		_composer.editable = false
	else:
		var ai_name := _get_name(_conversation_id)
		_composer.placeholder_text = "Write to %s. Shift+Enter for a new line." % ai_name
		if _session.listening.has(_conversation_id):
			status_text = "%s is listening" % ai_name
			status_tooltip = "%s gets your message right away." % ai_name
			status_color = _color("success_color")
		elif _is_working(_conversation_id):
			status_text = "%s reads it after its current step" % ai_name
		else:
			status_text = "%s reads it with its next step" % ai_name
			status_tooltip = "%s reads your message the next time it uses Godot. To talk to it from here, ask it once in its own app: \"%s\"" % [ai_name, LISTEN_REQUEST]
			_copy_request_button.visible = true
	_status_label.text = status_text
	_status_label.tooltip_text = status_tooltip if not status_tooltip.is_empty() else status_text
	_status_label.add_theme_color_override("font_color", status_color)
	_refresh_send_button()


func _refresh_send_button() -> void:
	_send_button.disabled = not _composer.editable or (_composer.text.strip_edges().is_empty() and _attachments.is_empty())


func _refresh_attachment_row() -> void:
	for child in _attachment_row.get_children():
		child.queue_free()
	_attachment_row.visible = not _attachments.is_empty()
	_refresh_send_button()
	if not _attachments.is_empty():
		_attachment_row.add_child(_build_attachment_list(_attachments, true))


func _fit_bubbles() -> void:
	var available_width := _thread_scroll.size.x - 24 * _editor_scale
	var maximum_width := minf(available_width * 0.8, MAXIMUM_BUBBLE_WIDTH * _editor_scale)
	for bubble_entry: Array in _bubbles:
		var bubble: PanelContainer = bubble_entry[0]
		if is_instance_valid(bubble):
			bubble.custom_minimum_size.x = clampf(float(bubble_entry[1]) + 20 * _editor_scale, 120 * _editor_scale, maxf(maximum_width, 120 * _editor_scale))


func _fit_composer_height() -> void:
	var line_count := clampi(_composer.get_total_visible_line_count(), MINIMUM_COMPOSER_LINES, MAXIMUM_COMPOSER_LINES)
	_composer.custom_minimum_size.y = line_count * _composer.get_line_height() + 6 * _editor_scale


func _scroll_to_bottom() -> void:
	await get_tree().process_frame
	_thread_scroll.scroll_vertical = int(_thread_scroll.get_v_scroll_bar().max_value)


func _mark_conversation_seen() -> void:
	var conversation: Array[Dictionary] = _session.get_conversation(_conversation_id)
	if not conversation.is_empty():
		_seen_up_to[_conversation_id] = int(conversation.back()["id"])
	unread_count_changed.emit(get_unread_count())


# --- Actions --------------------------------------------------------------------------

func _send() -> void:
	var text := _composer.text.strip_edges()
	if text.is_empty() and _attachments.is_empty():
		return
	if text.is_empty():
		text = "(see the attachments)"
	_session.send_from_person(_conversation_id, text, _attachments.duplicate(true))
	_composer.clear()
	_attachments.clear()
	_refresh_attachment_row()
	_fit_composer_height()
	_scroll_to_bottom.call_deferred()


func _on_composer_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event != null and key_event.pressed and not key_event.echo and key_event.keycode in [KEY_ENTER, KEY_KP_ENTER] and not key_event.shift_pressed:
		_send()
		_composer.accept_event()


func _on_add_menu_pressed(menu_id: int) -> void:
	match menu_id:
		MENU_PROJECT_FILE:
			_open_file_dialog(EditorFileDialog.ACCESS_RESOURCES)
		MENU_COMPUTER_FILE:
			_open_file_dialog(EditorFileDialog.ACCESS_FILESYSTEM)
		MENU_SELECTED_NODES:
			_attach_selected_nodes()
		MENU_SCREENSHOT:
			_attach_screenshot()


func _open_file_dialog(access: EditorFileDialog.Access) -> void:
	if _file_dialog == null:
		_file_dialog = EditorFileDialog.new()
		_file_dialog.title = "Attach"
		_file_dialog.file_selected.connect(_attach_path)
		_file_dialog.files_selected.connect(func(paths: PackedStringArray) -> void:
			for path in paths:
				_attach_path(path)
		)
		_file_dialog.dir_selected.connect(_attach_path)
		EditorInterface.get_base_control().add_child(_file_dialog)
	_file_dialog.access = access
	_file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_ANY if access == EditorFileDialog.ACCESS_RESOURCES else EditorFileDialog.FILE_MODE_OPEN_FILES
	_file_dialog.popup_file_dialog()


func _attach_path(path: String) -> void:
	var is_folder := DirAccess.dir_exists_absolute(path)
	var kind := "folder" if is_folder else ("image" if path.get_extension().to_lower() in IMAGE_EXTENSIONS else "file")
	if is_folder and not path.ends_with("/"):
		path += "/"
	# Pictures reach the AI as images, so the MCP server needs a path it can read.
	if kind == "image" and path.begins_with("res://"):
		path = ProjectSettings.globalize_path(path)
	_add_attachment({"kind": kind, "path": path})


func _attach_selected_nodes() -> void:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return
	for node in EditorInterface.get_selection().get_top_selected_nodes():
		_add_attachment({"kind": "node", "path": String(scene_root.get_path_to(node)), "scene": scene_root.scene_file_path})


func _attach_screenshot() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ATTACHMENT_DIRECTORY))
	var image := EditorInterface.get_base_control().get_viewport().get_texture().get_image()
	var file_name := "screenshot-%s.png" % Time.get_datetime_string_from_system().replace(":", "-")
	var path := ProjectSettings.globalize_path(ATTACHMENT_DIRECTORY.path_join(file_name))
	if image.save_png(path) == OK:
		_add_attachment({"kind": "image", "path": path, "label": "Editor screenshot"})


func _add_attachment(attachment: Dictionary) -> void:
	for existing in _attachments:
		if existing["path"] == attachment["path"] and existing["kind"] == attachment["kind"]:
			return
	_attachments.append(attachment)
	_refresh_attachment_row()


func _can_drop_on_composer(_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and String(data.get("type", "")) in ["files", "files_and_dirs", "nodes"]


func _drop_on_composer(_position: Vector2, data: Variant) -> void:
	var drag_data: Dictionary = data
	if drag_data["type"] == "nodes":
		var scene_root := EditorInterface.get_edited_scene_root()
		for node_path: NodePath in drag_data.get("nodes", []):
			var node := get_tree().root.get_node_or_null(node_path)
			if scene_root != null and node != null:
				_add_attachment({"kind": "node", "path": String(scene_root.get_path_to(node)), "scene": scene_root.scene_file_path})
		return
	for path: String in drag_data.get("files", []):
		_attach_path(path)


func _open_attachment(attachment: Dictionary) -> void:
	var path := String(attachment["path"])
	match String(attachment["kind"]):
		"node":
			var scene_root := EditorInterface.get_edited_scene_root()
			if scene_root != null and scene_root.scene_file_path != attachment.get("scene", ""):
				EditorInterface.open_scene_from_path(String(attachment["scene"]))
				scene_root = EditorInterface.get_edited_scene_root()
			var node := scene_root.get_node_or_null(path) if scene_root != null else null
			if node != null:
				EditorInterface.get_selection().clear()
				EditorInterface.get_selection().add_node(node)
				EditorInterface.edit_node(node)
		_:
			_open_link(path)


## Project paths open in the editor; web links in the browser. Other files are only
## shown in the file manager, so nothing on the computer runs from a click in the chat.
func _open_link(link: Variant) -> void:
	var target := String(link)
	if target.begins_with("http://") or target.begins_with("https://"):
		OS.shell_open(target)
	elif target.begins_with("res://"):
		var extension := target.get_extension().to_lower()
		if target.ends_with("/") or DirAccess.dir_exists_absolute(target):
			EditorInterface.select_file(target)
		elif not FileAccess.file_exists(target):
			return
		elif extension in ["tscn", "scn"]:
			EditorInterface.open_scene_from_path(target)
		elif extension in ["gd", "cs", "gdshader", "txt", "md", "json", "cfg"]:
			var resource := load(target)
			if resource is Script:
				EditorInterface.edit_script(resource)
			else:
				EditorInterface.select_file(target)
		else:
			EditorInterface.select_file(target)
	elif FileAccess.file_exists(target) or DirAccess.dir_exists_absolute(target):
		OS.shell_show_in_file_manager(target)


# --- Helpers --------------------------------------------------------------------------

## Every AI first, then the connected AIs, then AIs that left but have messages here.
func _get_conversation_ids() -> Array[int]:
	var conversation_ids: Array[int] = [WingmanSession.EVERYONE]
	var connection_ids: Array = _session.connections.keys()
	connection_ids.sort()
	for connection_id: int in connection_ids:
		conversation_ids.append(connection_id)
	for message: Dictionary in _session.messages:
		for connection_id: int in [int(message["from_id"]), int(message["to_id"])]:
			var is_ai := connection_id > 0 or connection_id <= WingmanSession.PAST_ID_BASE
			if is_ai and not message["is_event"] and not conversation_ids.has(connection_id):
				conversation_ids.append(connection_id)
	return conversation_ids


func _count_unread(conversation_id: int) -> int:
	var seen_id := int(_seen_up_to.get(conversation_id, 0))
	var unread_count := 0
	for message in _session.get_conversation(conversation_id):
		if int(message["id"]) > seen_id and not message["is_event"] and int(message["from_id"]) != NoticeBoard.PERSON:
			unread_count += 1
	return unread_count


func _get_name(connection_id: int) -> String:
	if _session.connections.has(connection_id):
		return String(_session.connections[connection_id]["name"])
	for message: Dictionary in _session.messages:
		if int(message["from_id"]) == connection_id:
			return String(message["sender"])
		if int(message["to_id"]) == connection_id:
			return String(message["receiver"])
	return "AI"


func _is_working(connection_id: int) -> bool:
	for entry: Dictionary in _session.activity:
		if int(entry["connection_id"]) == connection_id and entry["status"] in [WingmanSession.STATUS_RUNNING, WingmanSession.STATUS_WAITING]:
			return true
	return false


func _describe_read_state(message: Dictionary) -> String:
	var read_by: Dictionary = message["read_by"]
	if int(message["to_id"]) != WingmanSession.EVERYONE:
		return "Read %s" % read_by.values()[0] if not read_by.is_empty() else "Not read yet"
	if read_by.is_empty():
		return "Not read yet"
	var reader_names := PackedStringArray()
	for connection_id: int in read_by:
		reader_names.append(_get_name(connection_id))
	return "Read by %s" % ", ".join(reader_names)


func _empty_conversation_text() -> String:
	if _session.connections.is_empty():
		return "No AI is connected yet."
	if _conversation_id == WingmanSession.EVERYONE:
		return "Messages to every AI, and what the AIs tell each other, show up here."
	return "Write to %s below. Its answers show up here." % _get_name(_conversation_id)


func _describe_attachment(attachment: Dictionary) -> String:
	if attachment.has("label"):
		return String(attachment["label"])
	var path := String(attachment["path"])
	match String(attachment["kind"]):
		"node":
			return path.get_file() if path != "." else "Scene root"
		"folder":
			return path.trim_suffix("/").get_file() + "/"
	return path.get_file()


func _attachment_icon(attachment: Dictionary) -> Texture2D:
	match String(attachment["kind"]):
		"folder":
			return _icon("Folder")
		"node":
			return _icon("Node")
		"image":
			return _icon("Image")
	var extension := String(attachment["path"]).get_extension().to_lower()
	match extension:
		"gd":
			return _icon("GDScript")
		"tscn", "scn":
			return _icon("PackedScene")
	return _icon("File")


func _style_recipient_button(recipient_button: Button, has_unread: bool) -> void:
	var normal_box := _make_box(Color(0, 0, 0, 0), 4, 6)
	normal_box.content_margin_top = 3 * _editor_scale
	normal_box.content_margin_bottom = 3 * _editor_scale
	var hover_box := normal_box.duplicate()
	hover_box.bg_color = Color(_color("font_color"), 0.06)
	var pressed_box := normal_box.duplicate()
	pressed_box.bg_color = Color(_color("accent_color"), 0.22)
	recipient_button.add_theme_stylebox_override("normal", normal_box)
	recipient_button.add_theme_stylebox_override("hover", hover_box)
	recipient_button.add_theme_stylebox_override("pressed", pressed_box)
	recipient_button.add_theme_stylebox_override("hover_pressed", pressed_box)
	recipient_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	recipient_button.add_theme_color_override("font_color", _color("accent_color") if has_unread else _dim_text_color())
	recipient_button.add_theme_color_override("font_hover_color", _color("font_color"))
	recipient_button.add_theme_color_override("font_pressed_color", _color("font_color"))
	recipient_button.add_theme_color_override("font_hover_pressed_color", _color("font_color"))


func _make_hint(text: String) -> Label:
	var hint := Label.new()
	hint.text = text
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", _dim_text_color())
	return hint


func _make_box(background: Color, corner_radius: int, padding: float) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.set_corner_radius_all(int(corner_radius * _editor_scale))
	box.set_content_margin_all(padding * _editor_scale)
	box.anti_aliasing = true
	return box


func _color(color_name: String) -> Color:
	return _theme.get_color(color_name, "Editor")


func _is_dark_theme() -> bool:
	return _color("base_color").get_luminance() < 0.5


func _thread_color() -> Color:
	return _color("dark_color_1") if _is_dark_theme() else _color("base_color").darkened(0.04)


func _bubble_color() -> Color:
	return _color("base_color").lerp(_color("font_color"), 0.08)


func _composer_color() -> Color:
	return _color("dark_color_2") if _is_dark_theme() else _color("base_color").lightened(0.6)


## Send stands out in the accent color while there is something to send.
func _style_send_button() -> void:
	var normal_box := _make_box(_color("accent_color"), 4, 8)
	normal_box.content_margin_top = 3 * _editor_scale
	normal_box.content_margin_bottom = 3 * _editor_scale
	var hover_box := normal_box.duplicate()
	hover_box.bg_color = _color("accent_color").lightened(0.12)
	var disabled_box := normal_box.duplicate()
	disabled_box.bg_color = Color(_color("font_color"), 0.08)
	_send_button.add_theme_stylebox_override("normal", normal_box)
	_send_button.add_theme_stylebox_override("hover", hover_box)
	_send_button.add_theme_stylebox_override("pressed", normal_box)
	_send_button.add_theme_stylebox_override("disabled", disabled_box)
	_send_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var on_accent := Color.WHITE if _color("accent_color").get_luminance() < 0.6 else Color.BLACK
	for color_name: String in ["font_color", "font_hover_color", "font_pressed_color", "icon_normal_color", "icon_hover_color", "icon_pressed_color"]:
		_send_button.add_theme_color_override(color_name, on_accent)
	_send_button.add_theme_color_override("font_disabled_color", _dim_text_color())
	_send_button.add_theme_color_override("icon_disabled_color", _dim_text_color())


func _code_background_color() -> Color:
	return Color(0, 0, 0, 0.28) if _is_dark_theme() else Color(0, 0, 0, 0.06)


func _dim_text_color() -> Color:
	return Color(_color("font_color"), 0.6)


func _small_font_size() -> int:
	return int(_theme.get_font_size("main_size", "EditorFonts") * 0.88)


func _icon(icon_name: String) -> Texture2D:
	return _theme.get_icon(icon_name, "EditorIcons")


static func _escape_bbcode(text: String) -> String:
	return text.replace("[", "[lb]")
