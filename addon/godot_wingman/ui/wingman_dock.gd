@tool
extends VBoxContainer
## The "Godot Wingman" panel at the bottom of the editor.
##
## Left: one card per connected AI, stacked, each with what it is doing and its own
## permission mode, then the mode for AIs that connect later and "Connect AI apps".
## Right, in two tabs:
## - Changes: every change an AI made, newest first. The project can go back to how
##   it was before any of them.
## - Chat: the person talks to every AI or to one of them (ui/chat_view.gd). Clicking
##   an AI's card opens its conversation.

const AiAppsDialog := preload("ai_apps_dialog.gd")
const ConfirmationPrompt := preload("confirmation_prompt.gd")
const ChatView := preload("chat_view.gd")
const WingmanSession := preload("../session/wingman_session.gd")

const MODE_TOOLTIP := "Full access: the AI changes the project freely.\nAsk first: Godot asks you before every change.\nRead-only: the AI can only look.\nIf the AI's own --mode setting is stricter, that one applies."
const TAB_CHANGES := 0
const TAB_CHAT := 1
const COLUMN_TIME := 0
const COLUMN_AI := 1
const COLUMN_CHANGE := 2
const COLUMN_RESULT := 3
const SIDEBAR_WIDTH := 340

var _session: RefCounted
var _addon_version: String
var _editor_scale: float
var _theme: Theme

var _version_banner: PanelContainer
var _version_label: Label
var _ai_card_list: VBoxContainer
var _no_ai_hint: Label
var _default_mode_menu: PopupMenu
var _tab_bar: TabBar
var _changes_view: VBoxContainer
var _activity_tree: Tree
var _no_changes_hint: Label
var _go_back_button: Button
var _chat_view: VBoxContainer
## connection id -> {"status": Label}, to update cards without rebuilding them.
var _card_parts: Dictionary = {}


func _init(session: RefCounted, addon_version: String) -> void:
	name = "GodotWingmanDock"
	_session = session
	_addon_version = addon_version
	_editor_scale = EditorInterface.get_editor_scale()
	_theme = EditorInterface.get_editor_theme()
	custom_minimum_size = Vector2(0, 220 * _editor_scale)
	add_theme_constant_override("separation", 0)
	_build_version_banner()
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)
	split.add_child(_build_sidebar())
	split.add_child(_build_main_area())
	_session.activity_changed.connect(_refresh_activity)
	_session.connections_changed.connect(_rebuild_ai_cards)
	_session.settings_changed.connect(_refresh_default_mode)
	_session.listening_changed.connect(_refresh_ai_card_status)
	_rebuild_ai_cards()
	_refresh_default_mode()
	_refresh_activity()


# --- Building -------------------------------------------------------------------------

func _build_version_banner() -> void:
	_version_banner = PanelContainer.new()
	_version_banner.add_theme_stylebox_override("panel", _make_box(_color("warning_color").darkened(0.6), 0, 6))
	_version_label = Label.new()
	_version_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_version_label.add_theme_color_override("font_color", _color("warning_color"))
	_version_banner.add_child(_version_label)
	_version_banner.visible = false
	add_child(_version_banner)


func _build_sidebar() -> Control:
	var sidebar := PanelContainer.new()
	sidebar.custom_minimum_size.x = SIDEBAR_WIDTH * _editor_scale
	sidebar.add_theme_stylebox_override("panel", _make_box(_sidebar_color(), 0, 8))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", int(6 * _editor_scale))
	sidebar.add_child(column)

	var title_row := HBoxContainer.new()
	column.add_child(title_row)
	var title := Label.new()
	title.text = "AI assistants"
	title.tooltip_text = "Godot Wingman %s" % _addon_version
	title.mouse_filter = Control.MOUSE_FILTER_PASS
	title.add_theme_font_override("font", _theme.get_font("bold", "EditorFonts"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	var connect_button := Button.new()
	connect_button.text = "Connect AI apps"
	connect_button.icon = _icon("Add")
	connect_button.flat = true
	connect_button.tooltip_text = "Add Godot Wingman to Claude, Codex, Cursor, Gemini CLI, Windsurf or VS Code."
	connect_button.pressed.connect(_open_ai_apps_dialog)
	title_row.add_child(connect_button)
	title_row.add_child(_build_settings_menu())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_ai_card_list = VBoxContainer.new()
	_ai_card_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ai_card_list.add_theme_constant_override("separation", int(6 * _editor_scale))
	scroll.add_child(_ai_card_list)
	_no_ai_hint = Label.new()
	_no_ai_hint.text = "No AI is connected. Start your AI app and ask it to use Godot. Not set up yet? Click Connect AI apps."
	_no_ai_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_no_ai_hint.custom_minimum_size.x = (SIDEBAR_WIDTH - 24) * _editor_scale
	_no_ai_hint.add_theme_color_override("font_color", _dim_text_color())
	_ai_card_list.add_child(_no_ai_hint)
	return sidebar


## The menu behind the gear: the mode for AI apps that connect for the first time.
func _build_settings_menu() -> MenuButton:
	var settings_button := MenuButton.new()
	settings_button.icon = _icon("Tools")
	settings_button.flat = true
	settings_button.tooltip_text = "Settings"
	_default_mode_menu = settings_button.get_popup()
	_default_mode_menu.add_separator("New AIs start with")
	for mode: String in WingmanSession.MODES:
		_default_mode_menu.add_radio_check_item(WingmanSession.MODE_LABELS[mode])
	_default_mode_menu.add_separator("Godot Wingman %s" % _addon_version)
	_default_mode_menu.index_pressed.connect(func(index: int) -> void:
		var mode_index := index - 1
		if mode_index >= 0 and mode_index < WingmanSession.MODES.size():
			_session.set_default_mode(WingmanSession.MODES[mode_index])
	)
	return settings_button


func _open_ai_apps_dialog() -> void:
	var ai_apps_dialog := AiAppsDialog.new()
	EditorInterface.get_base_control().add_child(ai_apps_dialog)
	ai_apps_dialog.open()


func _build_main_area() -> Control:
	var main_area := VBoxContainer.new()
	main_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_area.add_theme_constant_override("separation", int(4 * _editor_scale))
	_tab_bar = TabBar.new()
	_tab_bar.add_tab("Changes", _icon("History"))
	_tab_bar.add_tab("Chat", _icon("Signals"))
	_style_tab_bar()
	_tab_bar.tab_changed.connect(_show_tab)
	main_area.add_child(_tab_bar)
	main_area.add_child(_build_changes_view())
	_chat_view = ChatView.new(_session)
	_chat_view.unread_count_changed.connect(func(unread_count: int) -> void:
		_tab_bar.set_tab_title(TAB_CHAT, "Chat" if unread_count <= 0 else "Chat (%d new)" % unread_count)
	)
	main_area.add_child(_chat_view)
	_tab_bar.set_tab_title(TAB_CHAT, "Chat" if _chat_view.get_unread_count() <= 0 else "Chat (%d new)" % _chat_view.get_unread_count())
	_show_tab(TAB_CHANGES)
	return main_area


## The editor's own tab look makes the open tab the same grey as the panel, so it looks
## like the closed one. Here the open tab gets an accent line and bright text, and the
## other tab stays flat and dim.
func _style_tab_bar() -> void:
	var tab_padding := 10.0
	var selected_box := _make_box(_card_color(), 0, tab_padding)
	selected_box.border_width_bottom = int(maxf(2.0, 2 * _editor_scale))
	selected_box.border_color = _color("accent_color")
	selected_box.content_margin_top = 4 * _editor_scale
	selected_box.content_margin_bottom = 4 * _editor_scale
	var unselected_box := _make_box(Color(0, 0, 0, 0), 0, tab_padding)
	unselected_box.content_margin_top = 4 * _editor_scale
	unselected_box.content_margin_bottom = 4 * _editor_scale + selected_box.border_width_bottom
	var hovered_box := unselected_box.duplicate()
	hovered_box.bg_color = Color(_color("font_color"), 0.05)
	_tab_bar.add_theme_stylebox_override("tab_selected", selected_box)
	_tab_bar.add_theme_stylebox_override("tab_focus", StyleBoxEmpty.new())
	_tab_bar.add_theme_stylebox_override("tab_unselected", unselected_box)
	_tab_bar.add_theme_stylebox_override("tab_hovered", hovered_box)
	_tab_bar.add_theme_color_override("font_selected_color", _color("font_color"))
	_tab_bar.add_theme_color_override("font_hovered_color", _color("font_color"))
	_tab_bar.add_theme_color_override("font_unselected_color", _dim_text_color())


func _build_changes_view() -> Control:
	_changes_view = VBoxContainer.new()
	_changes_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_activity_tree = Tree.new()
	_activity_tree.columns = 4
	_activity_tree.hide_root = true
	_activity_tree.select_mode = Tree.SELECT_ROW
	_activity_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_activity_tree.set_column_expand(COLUMN_TIME, false)
	_activity_tree.set_column_custom_minimum_width(COLUMN_TIME, int(120 * _editor_scale))
	_activity_tree.set_column_expand(COLUMN_AI, false)
	_activity_tree.set_column_custom_minimum_width(COLUMN_AI, int(130 * _editor_scale))
	_activity_tree.set_column_expand_ratio(COLUMN_CHANGE, 3)
	_activity_tree.set_column_expand_ratio(COLUMN_RESULT, 2)
	for column_index in _activity_tree.columns:
		_activity_tree.set_column_clip_content(column_index, true)
	_activity_tree.item_selected.connect(_update_go_back_button)
	_changes_view.add_child(_activity_tree)
	_no_changes_hint = _make_empty_hint("No changes yet. Every change an AI makes is listed here, and you can take the project back to how it was before any of them.")
	_changes_view.add_child(_no_changes_hint)

	var footer := HBoxContainer.new()
	_changes_view.add_child(footer)
	_go_back_button = Button.new()
	_go_back_button.text = "Go back to before this step"
	_go_back_button.icon = _icon("Reload")
	_go_back_button.tooltip_text = "Puts scripts, scenes, resources and settings back as they were before the selected change.\nFiles created after it are deleted. Images and sounds are not covered."
	_go_back_button.disabled = true
	_go_back_button.pressed.connect(_on_go_back_pressed)
	footer.add_child(_go_back_button)
	var hint := Label.new()
	hint.text = "Select a change first. Ctrl+Z also undoes single changes, and the AIs are told."
	hint.add_theme_color_override("font_color", _dim_text_color())
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.clip_text = true
	footer.add_child(hint)
	var clear_button := Button.new()
	clear_button.text = "Clear list"
	clear_button.flat = true
	clear_button.pressed.connect(func() -> void: _session.clear_activity())
	footer.add_child(clear_button)
	return _changes_view


## One card per connected AI. Rebuilt only when AIs connect, leave or change mode, so an
## open mode menu is not closed while the AI works.
func _rebuild_ai_cards() -> void:
	for child in _ai_card_list.get_children():
		if child != _no_ai_hint:
			child.queue_free()
	_card_parts.clear()
	var connection_ids: Array = _session.connections.keys()
	connection_ids.sort()
	_no_ai_hint.visible = connection_ids.is_empty()
	for connection_id: int in connection_ids:
		_ai_card_list.add_child(_build_ai_card(connection_id, _session.connections[connection_id]))
	_refresh_ai_card_status()
	_refresh_version_banner()


func _build_ai_card(connection_id: int, connection: Dictionary) -> Control:
	var card := PanelContainer.new()
	var card_box := _make_box(_card_color(), 6, 8)
	card_box.set_border_width_all(1)
	card_box.border_color = Color(_color("font_color"), 0.08)
	card.add_theme_stylebox_override("panel", card_box)
	card.tooltip_text = "Click to chat with %s." % connection["name"]
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.gui_input.connect(func(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			open_chat_with(connection_id)
	)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", int(3 * _editor_scale))
	card.add_child(rows)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", int(8 * _editor_scale))
	rows.add_child(name_row)
	name_row.add_child(_build_name_field(connection_id, connection))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(spacer)
	var mode_button := _make_mode_button()
	mode_button.select(WingmanSession.MODES.find(connection["mode"]))
	mode_button.tooltip_text = "What %s may do in this editor. %s keeps this choice in this project.\n\n%s" % [connection["name"], WingmanSession.get_app_display_name(connection["ai_client"]), MODE_TOOLTIP]
	mode_button.item_selected.connect(func(index: int) -> void: _session.set_connection_mode(connection_id, WingmanSession.MODES[index]))
	name_row.add_child(mode_button)

	var details_label := _make_small_label("")
	rows.add_child(details_label)

	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", int(6 * _editor_scale))
	rows.add_child(status_row)
	var status_badge := PanelContainer.new()
	status_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	status_row.add_child(status_badge)
	var badge_label := Label.new()
	var badge_font_size := int(_theme.get_font_size("main_size", "EditorFonts") * 0.85)
	badge_label.add_theme_font_size_override("font_size", badge_font_size)
	badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# As wide as the longest badge text, so the text after it does not move when the
	# status changes.
	var badge_font: Font = _theme.get_font("main", "EditorFonts")
	var widest_badge := 0.0
	for badge_text: String in ["Ready", "Working", "Needs you", "Listening"]:
		widest_badge = maxf(widest_badge, badge_font.get_string_size(badge_text, HORIZONTAL_ALIGNMENT_LEFT, -1, badge_font_size).x)
	badge_label.custom_minimum_size.x = ceilf(widest_badge)
	status_badge.add_child(badge_label)
	var status_label := _make_small_label("")
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_row.add_child(status_label)

	var effective_mode := WingmanSession.stricter_mode(connection["server_mode"], connection["mode"])
	if effective_mode != connection["mode"]:
		var limit_label := _make_small_label("Limited to %s by its own --mode setting." % String(WingmanSession.MODE_LABELS[effective_mode]).to_lower())
		limit_label.add_theme_color_override("font_color", _color("warning_color"))
		rows.add_child(limit_label)

	# Shown while this AI waits for the person: answer right here, or open the dialog
	# with every detail of the change.
	var approval_row := HBoxContainer.new()
	approval_row.add_theme_constant_override("separation", int(6 * _editor_scale))
	approval_row.visible = false
	rows.add_child(approval_row)
	for approval_button_text: String in ["Allow", "Deny", "Details"]:
		var approval_button := Button.new()
		approval_button.text = approval_button_text
		approval_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		match approval_button_text:
			"Allow":
				approval_button.pressed.connect(func() -> void: ConfirmationPrompt.answer_open_dialog(ConfirmationPrompt.ANSWER_ALLOW))
			"Deny":
				approval_button.pressed.connect(func() -> void: ConfirmationPrompt.answer_open_dialog(ConfirmationPrompt.ANSWER_DENY))
			"Details":
				approval_button.tooltip_text = "Show the approval dialog with every argument of this change."
				approval_button.pressed.connect(func() -> void: ConfirmationPrompt.bring_open_dialog_to_front())
		approval_row.add_child(approval_button)

	# Tools the person allowed for the rest of the session ("Allow ... for this session"
	# in the approval dialog). One line however many there are; the names are in the
	# tooltip.
	var allowed_tools: Array = connection["tools_allowed"].keys()
	if not allowed_tools.is_empty():
		var approvals_row := HBoxContainer.new()
		rows.add_child(approvals_row)
		var approvals_label := _make_small_label("%d %s allowed without asking" % [allowed_tools.size(), "tool" if allowed_tools.size() == 1 else "tools"])
		approvals_label.tooltip_text = "Allowed for this session without asking:
%s" % "
".join(PackedStringArray(allowed_tools))
		approvals_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		approvals_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		approvals_row.add_child(approvals_label)
		var ask_again_button := Button.new()
		ask_again_button.text = "Ask again"
		ask_again_button.flat = true
		ask_again_button.tooltip_text = "Forget these permissions: Godot asks before every change again."
		ask_again_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ask_again_button.pressed.connect(func() -> void: _session.forget_session_approvals(connection_id))
		approvals_row.add_child(ask_again_button)

	_card_parts[connection_id] = {"details": details_label, "badge": status_badge, "badge_label": badge_label, "status": status_label, "approval": approval_row}
	return card


## The name looks like a title and becomes a text field when clicked, so the person can
## call each AI after the model it uses.
func _build_name_field(connection_id: int, connection: Dictionary) -> LineEdit:
	var name_field := LineEdit.new()
	name_field.text = connection["name"]
	name_field.flat = true
	name_field.max_length = 40
	name_field.select_all_on_focus = true
	name_field.tooltip_text = "%s. Click to rename, for example after the model this AI uses.
The other AIs see this name too." % WingmanSession.get_app_display_name(connection["ai_client"])
	name_field.expand_to_text_length = true
	name_field.add_theme_font_override("font", _theme.get_font("bold", "EditorFonts"))
	var save_name := func() -> void:
		if name_field.text.strip_edges().is_empty():
			name_field.text = connection["name"]
		else:
			_session.rename_connection(connection_id, name_field.text)
	name_field.text_submitted.connect(func(_text: String) -> void: name_field.release_focus())
	name_field.focus_exited.connect(save_name)
	return name_field


# --- Refreshing -----------------------------------------------------------------------

func _refresh_default_mode() -> void:
	for mode_index in WingmanSession.MODES.size():
		_default_mode_menu.set_item_checked(mode_index + 1, WingmanSession.MODES[mode_index] == _session.default_mode)


func _refresh_version_banner() -> void:
	var other_versions := PackedStringArray()
	for connection: Dictionary in _session.connections.values():
		var server_version := String(connection["server_version"])
		if server_version != "" and server_version != _addon_version and not other_versions.has(server_version):
			other_versions.append(server_version)
	_version_banner.visible = not other_versions.is_empty()
	_version_label.text = "This addon is version %s, but the Godot Wingman program the AI uses is %s. Ask the AI to run install_addon, then restart the editor." % [_addon_version, ", ".join(other_versions)]


## The lower lines of every card: app, connection time and changes, then a colored
## badge (Ready, Working, Needs you) with the AI's current or last step.
func _refresh_ai_card_status() -> void:
	for connection_id: int in _card_parts:
		var parts: Dictionary = _card_parts[connection_id]
		var latest_entry := {}
		var change_count := 0
		for entry: Dictionary in _session.activity:
			if int(entry["connection_id"]) != connection_id:
				continue
			latest_entry = entry
			if entry["status"] == WingmanSession.STATUS_DONE:
				change_count += 1
		var connection: Dictionary = _session.connections.get(connection_id, {})
		var details_label: Label = parts["details"]
		details_label.text = "%s  ·  since %s  ·  %d %s" % [
			WingmanSession.get_app_display_name(String(connection.get("ai_client", ""))),
			connection.get("connected_time", ""),
			change_count, "change" if change_count == 1 else "changes"]
		var status := String(latest_entry.get("status", ""))
		var badge_text := "Ready"
		var badge_color := _color("success_color")
		var status_text := "Nothing done yet" if latest_entry.is_empty() else "Last: %s" % latest_entry["title"]
		if _session.listening.has(connection_id):
			badge_text = "Listening"
			status_text = "Waiting for your message in the chat"
		elif status == WingmanSession.STATUS_RUNNING:
			badge_text = "Working"
			badge_color = _color("accent_color")
			status_text = latest_entry["title"]
		elif status == WingmanSession.STATUS_WAITING:
			badge_text = "Needs you"
			badge_color = _color("warning_color")
			status_text = latest_entry["title"]
		var badge: PanelContainer = parts["badge"]
		var badge_box := _make_box(Color(badge_color, 0.16), 4, 0)
		badge_box.content_margin_left = 6 * _editor_scale
		badge_box.content_margin_right = 6 * _editor_scale
		badge_box.content_margin_top = 1 * _editor_scale
		badge_box.content_margin_bottom = 1 * _editor_scale
		badge.add_theme_stylebox_override("panel", badge_box)
		var badge_label: Label = parts["badge_label"]
		badge_label.text = badge_text
		badge_label.add_theme_color_override("font_color", badge_color)
		var approval_row: HBoxContainer = parts["approval"]
		var is_dialog_open_for_it: bool = status == WingmanSession.STATUS_WAITING and int(latest_entry["id"]) == _session.open_approval_entry_id
		approval_row.visible = is_dialog_open_for_it
		if status == WingmanSession.STATUS_WAITING and not is_dialog_open_for_it:
			status_text = "In line for approval: %s" % latest_entry["title"]
		var status_label: Label = parts["status"]
		status_label.text = status_text
		status_label.tooltip_text = status_text


func _refresh_activity() -> void:
	var selected_id := _get_selected_activity_id()
	_activity_tree.clear()
	var root := _activity_tree.create_item()
	# Newest first: the latest change is what people look for.
	for entry_index in range(_session.activity.size() - 1, -1, -1):
		var entry: Dictionary = _session.activity[entry_index]
		var row := _activity_tree.create_item(root)
		var status := String(entry["status"])
		row.set_icon(COLUMN_TIME, _status_icon(status))
		row.set_icon_max_width(COLUMN_TIME, int(16 * _editor_scale))
		row.set_text(COLUMN_TIME, String(entry["time"]).get_slice(" ", 1))
		row.set_custom_color(COLUMN_TIME, _dim_text_color())
		row.set_text(COLUMN_AI, entry["client"])
		row.set_text(COLUMN_CHANGE, entry["title"])
		row.set_text(COLUMN_RESULT, _describe_result(entry))
		row.set_custom_color(COLUMN_RESULT, _result_color(status))
		var details := "%s\nTool: %s\nStatus: %s" % [entry["title"], entry["tool"], status]
		if String(entry["result"]) != "":
			details += "\nResult: %s" % entry["result"]
		if not (String(entry["input"]) in ["", "{}"]):
			details += "\n\nInput: %s" % String(entry["input"]).left(2000)
		for column_index in _activity_tree.columns:
			row.set_tooltip_text(column_index, details)
		row.set_metadata(0, entry["id"])
		if int(entry["id"]) == selected_id:
			row.select(0)
	var has_changes: bool = not _session.activity.is_empty()
	_activity_tree.visible = has_changes
	_no_changes_hint.visible = not has_changes
	_update_go_back_button()
	_refresh_ai_card_status()


func _show_tab(tab_index: int) -> void:
	_changes_view.visible = tab_index == TAB_CHANGES
	_chat_view.visible = tab_index == TAB_CHAT


## Shows the Chat tab with the conversation with one AI.
func open_chat_with(connection_id: int) -> void:
	_tab_bar.current_tab = TAB_CHAT
	_show_tab(TAB_CHAT)
	_chat_view.select_conversation(connection_id)


# --- Actions --------------------------------------------------------------------------

func _get_selected_activity_id() -> int:
	var selected_row := _activity_tree.get_selected()
	return int(selected_row.get_metadata(0)) if selected_row != null else -1


func _update_go_back_button() -> void:
	var selected_id := _get_selected_activity_id()
	var entry: Dictionary = _session.find_entry(selected_id) if selected_id != -1 else {}
	_go_back_button.disabled = not _session.checkpoints.has_checkpoint(int(entry.get("checkpoint_id", -1)))


func _on_go_back_pressed() -> void:
	var activity_id := _get_selected_activity_id()
	var planned_changes: Dictionary = _session.preview_going_back(activity_id)
	if planned_changes.is_empty():
		return
	var changed_paths: Array = planned_changes["changed"]
	var removed_paths: Array = planned_changes["removed"]
	if changed_paths.is_empty() and removed_paths.is_empty():
		_show_message("Nothing to change: the files are already as they were before this step.")
		return
	var description := "Put the project back to how it was before step %d?\n\n" % activity_id
	if not changed_paths.is_empty():
		description += "Restored:\n  %s\n\n" % "\n  ".join(_shorten_list(changed_paths))
	if not removed_paths.is_empty():
		description += "Deleted (created after this step):\n  %s\n\n" % "\n  ".join(_shorten_list(removed_paths))
	description += "Open scenes are reloaded from disk; their unsaved changes are lost."
	var allowed: bool = await ConfirmationPrompt.ask("Go back to before this step", description, 600.0)
	if allowed:
		var outcome: Dictionary = await _session.go_back_to_before(activity_id)
		if not Array(outcome.get("failed", [])).is_empty():
			_show_message("These files could not be restored:\n%s" % "\n".join(outcome["failed"]))


func _show_message(text: String) -> void:
	var message_dialog := AcceptDialog.new()
	message_dialog.title = "Godot Wingman"
	message_dialog.dialog_text = text
	message_dialog.confirmed.connect(message_dialog.queue_free)
	message_dialog.canceled.connect(message_dialog.queue_free)
	EditorInterface.get_base_control().add_child(message_dialog)
	message_dialog.popup_centered()


# --- Look -----------------------------------------------------------------------------

func _make_mode_button() -> OptionButton:
	var mode_button := OptionButton.new()
	for mode: String in WingmanSession.MODES:
		mode_button.add_item(WingmanSession.MODE_LABELS[mode])
	mode_button.fit_to_longest_item = true
	return mode_button


func _make_small_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	label.add_theme_color_override("font_color", _dim_text_color())
	return label


func _make_empty_hint(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	label.add_theme_color_override("font_color", _dim_text_color())
	return label


func _make_box(background: Color, corner_radius: int, padding: float) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.set_corner_radius_all(int(corner_radius * _editor_scale) if corner_radius < 99 else 99)
	box.set_content_margin_all(padding * _editor_scale)
	box.anti_aliasing = true
	return box


func _color(color_name: String) -> Color:
	return _theme.get_color(color_name, "Editor")


func _is_dark_theme() -> bool:
	return _color("base_color").get_luminance() < 0.5


func _sidebar_color() -> Color:
	return _color("dark_color_1") if _is_dark_theme() else _color("base_color").darkened(0.04)


func _card_color() -> Color:
	return _color("base_color").lerp(_color("font_color"), 0.06)


func _dim_text_color() -> Color:
	return Color(_color("font_color"), 0.6)


func _icon(icon_name: String) -> Texture2D:
	return _theme.get_icon(icon_name, "EditorIcons")


func _status_icon(status: String) -> Texture2D:
	match status:
		WingmanSession.STATUS_DONE:
			return _icon("StatusSuccess")
		WingmanSession.STATUS_FAILED:
			return _icon("StatusError")
		WingmanSession.STATUS_DENIED, WingmanSession.STATUS_BLOCKED:
			return _icon("StatusWarning")
		WingmanSession.STATUS_WAITING:
			return _icon("Time")
	return _icon("Progress1")


func _describe_result(entry: Dictionary) -> String:
	var result := String(entry["result"])
	match String(entry["status"]):
		WingmanSession.STATUS_RUNNING:
			return "Running..."
		WingmanSession.STATUS_WAITING:
			return "Waiting for your approval"
		WingmanSession.STATUS_DENIED:
			return "Denied" + (": " + result if result != "" else " by you")
		WingmanSession.STATUS_BLOCKED:
			return "Blocked: this AI is read-only"
	return result


func _result_color(status: String) -> Color:
	match status:
		WingmanSession.STATUS_FAILED:
			return _color("error_color")
		WingmanSession.STATUS_DENIED, WingmanSession.STATUS_BLOCKED, WingmanSession.STATUS_WAITING:
			return _color("warning_color")
	return _dim_text_color()


static func _shorten_list(paths: Array, maximum_count: int = 15) -> Array:
	if paths.size() <= maximum_count:
		return paths
	return paths.slice(0, maximum_count) + ["... and %d more" % (paths.size() - maximum_count)]
