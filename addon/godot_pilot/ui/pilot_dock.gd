@tool
extends VBoxContainer
## The "Godot Pilot" panel at the bottom of the editor.
##
## It shows which AIs are connected, lets the person choose the permission mode for
## this project, lists every change the AI made, and can put the project back to how
## it was before any of those changes. The person can also write to the AIs: they get
## the message with their next tool result.

const ConfirmationPrompt := preload("confirmation_prompt.gd")
const PilotSession := preload("../session/pilot_session.gd")

const MODE_LABELS := {"full": "Full", "confirm": "Confirm each change", "read-only": "Read-only"}
const COLUMN_TIME := 0
const COLUMN_CLIENT := 1
const COLUMN_CHANGE := 2
const COLUMN_STATUS := 3
const COLUMN_RESULT := 4

var _session: RefCounted
var _addon_version: String

var _connection_label: Label
var _version_warning_label: Label
var _mode_button: OptionButton
var _approvals_label: Label
var _forget_approvals_button: Button
var _activity_tree: Tree
var _go_back_button: Button
var _message_field: LineEdit


func _init(session: RefCounted, addon_version: String) -> void:
	name = "GodotPilotDock"
	_session = session
	_addon_version = addon_version
	custom_minimum_size = Vector2(0, 240 * EditorInterface.get_editor_scale())
	_build_header()
	_build_activity_tree()
	_build_footer()
	_session.activity_changed.connect(_refresh_activity)
	_session.settings_changed.connect(_refresh_settings)
	show_connected_clients([])
	_refresh_settings()
	_refresh_activity()


## `clients` are the descriptions from the bridge server: {ai_client, server_version, permission_mode}.
func show_connected_clients(clients: Array) -> void:
	if clients.is_empty():
		_connection_label.text = "Godot Pilot %s · no AI connected" % _addon_version
		_version_warning_label.visible = false
		return
	var client_texts: Array[String] = []
	var outdated_versions: Array[String] = []
	for client: Dictionary in clients:
		client_texts.append("%s (server mode: %s)" % [client.get("ai_client", "AI"), client.get("permission_mode", "?")])
		var server_version := String(client.get("server_version", ""))
		if server_version != "" and server_version != _addon_version and not outdated_versions.has(server_version):
			outdated_versions.append(server_version)
	_connection_label.text = "Godot Pilot %s · connected: %s" % [_addon_version, ", ".join(client_texts)]
	_version_warning_label.visible = not outdated_versions.is_empty()
	_version_warning_label.text = "This addon is version %s, but the MCP server is %s. Ask the AI to run install_addon, then restart the editor." % [_addon_version, ", ".join(outdated_versions)]


func _build_header() -> void:
	var header := HBoxContainer.new()
	add_child(header)
	_connection_label = Label.new()
	_connection_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_connection_label.clip_text = true
	header.add_child(_connection_label)

	_approvals_label = Label.new()
	_approvals_label.clip_text = true
	header.add_child(_approvals_label)
	_forget_approvals_button = Button.new()
	_forget_approvals_button.text = "Ask again for everything"
	_forget_approvals_button.pressed.connect(func() -> void: _session.forget_session_approvals())
	header.add_child(_forget_approvals_button)

	var mode_label := Label.new()
	mode_label.text = "Permission mode:"
	header.add_child(mode_label)
	_mode_button = OptionButton.new()
	for mode: String in PilotSession.MODES:
		_mode_button.add_item(MODE_LABELS[mode])
	_mode_button.tooltip_text = "Full: the AI changes the project freely.\nConfirm each change: Godot asks you before every change.\nRead-only: the AI can only look.\nThe MCP server's --mode also applies; the stricter one wins."
	_mode_button.item_selected.connect(func(index: int) -> void: _session.set_editor_mode(PilotSession.MODES[index]))
	header.add_child(_mode_button)

	_version_warning_label = Label.new()
	_version_warning_label.add_theme_color_override("font_color", EditorInterface.get_base_control().get_theme_color("warning_color", "Editor"))
	_version_warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_version_warning_label)


func _build_activity_tree() -> void:
	_activity_tree = Tree.new()
	_activity_tree.columns = 5
	_activity_tree.column_titles_visible = true
	_activity_tree.hide_root = true
	_activity_tree.select_mode = Tree.SELECT_ROW
	_activity_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var editor_scale := EditorInterface.get_editor_scale()
	var column_titles := ["Time", "AI", "Change", "Status", "Result"]
	# Fixed width for short columns; the change and its result share the rest.
	var column_widths := [80, 120, 0, 150, 0]
	for column_index in column_titles.size():
		_activity_tree.set_column_title(column_index, column_titles[column_index])
		var is_wide_column: bool = column_widths[column_index] == 0
		_activity_tree.set_column_expand(column_index, is_wide_column)
		_activity_tree.set_column_clip_content(column_index, true)
		if not is_wide_column:
			_activity_tree.set_column_custom_minimum_width(column_index, int(column_widths[column_index] * editor_scale))
	_activity_tree.item_selected.connect(_update_go_back_button)
	add_child(_activity_tree)


func _build_footer() -> void:
	var footer := HBoxContainer.new()
	add_child(footer)
	_go_back_button = Button.new()
	_go_back_button.text = "Go back to before this step"
	_go_back_button.tooltip_text = "Puts scripts, scenes, resources and settings back as they were before the selected change.\nFiles created after it are deleted. Images and sounds are not covered."
	_go_back_button.disabled = true
	_go_back_button.pressed.connect(_on_go_back_pressed)
	footer.add_child(_go_back_button)
	var clear_button := Button.new()
	clear_button.text = "Clear list"
	clear_button.pressed.connect(func() -> void: _session.clear_activity())
	footer.add_child(clear_button)
	var hint := Label.new()
	hint.text = "Ctrl+Z also undoes single changes; the AIs are told."
	hint.modulate = Color(1, 1, 1, 0.6)
	footer.add_child(hint)

	_message_field = LineEdit.new()
	_message_field.placeholder_text = "Tell the AIs something (they read it with their next step)"
	_message_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_message_field.text_submitted.connect(func(_text: String) -> void: _send_message())
	footer.add_child(_message_field)
	var send_button := Button.new()
	send_button.text = "Send"
	send_button.pressed.connect(_send_message)
	footer.add_child(send_button)


func _send_message() -> void:
	var message := _message_field.text.strip_edges()
	if message.is_empty():
		return
	_session.post_message(_session.notices.PERSON, "You", message)
	_message_field.clear()


func _refresh_settings() -> void:
	_mode_button.select(PilotSession.MODES.find(_session.editor_mode))
	var allowed_tools: PackedStringArray = _session.get_tools_allowed_for_session()
	_approvals_label.text = "Allowed for this session: %s" % ", ".join(allowed_tools) if not allowed_tools.is_empty() else ""
	_forget_approvals_button.visible = not allowed_tools.is_empty()


func _refresh_activity() -> void:
	var selected_id := _get_selected_activity_id()
	_activity_tree.clear()
	var root := _activity_tree.create_item()
	# Newest first: the latest change is what people look for.
	for entry_index in range(_session.activity.size() - 1, -1, -1):
		var entry: Dictionary = _session.activity[entry_index]
		var row := _activity_tree.create_item(root)
		row.set_text(COLUMN_TIME, String(entry["time"]).get_slice(" ", 1))
		row.set_text(COLUMN_CLIENT, entry["client"])
		row.set_text(COLUMN_CHANGE, "%s (%s)" % [entry["title"], entry["tool"]])
		row.set_tooltip_text(COLUMN_CHANGE, String(entry["input"]).left(2000))
		row.set_text(COLUMN_STATUS, entry["status"])
		row.set_text(COLUMN_RESULT, entry["result"])
		row.set_tooltip_text(COLUMN_RESULT, entry["result"])
		row.set_metadata(0, entry["id"])
		if int(entry["id"]) == selected_id:
			row.select(0)
	_update_go_back_button()


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
	message_dialog.title = "Godot Pilot"
	message_dialog.dialog_text = text
	message_dialog.confirmed.connect(message_dialog.queue_free)
	message_dialog.canceled.connect(message_dialog.queue_free)
	EditorInterface.get_base_control().add_child(message_dialog)
	message_dialog.popup_centered()


static func _shorten_list(paths: Array, maximum_count: int = 15) -> Array:
	if paths.size() <= maximum_count:
		return paths
	return paths.slice(0, maximum_count) + ["... and %d more" % (paths.size() - maximum_count)]
