@tool
extends RefCounted
## What the AI is allowed to do in this editor, and what it has done.
##
## - Permission mode per connected AI, chosen in the Godot Wingman panel. Each AI app
##   (Claude Code, Codex...) remembers its last mode in this project; an app seen for
##   the first time gets the project's default mode. The MCP server has its own mode
##   (its --mode option); the stricter of the two applies, so neither side can loosen
##   the other.
## - In "confirm" mode the person can allow one tool for the rest of the session, for
##   that AI only.
## - Activity: every change the AI asks for and its result. Shown in the panel and
##   appended to .godot/godot_wingman/activity.log; nothing leaves the computer.
## - Checkpoints: before each change the project's text files are remembered, so the
##   panel can put the project back to how it was before any step.
##
## - News for the AIs (notice_board.gd): undo, changes by hand, going back, messages.
##
## The MCP server calls authorize() before every tool that changes something, and
## finish() after it.

signal activity_changed
signal settings_changed
signal connections_changed
signal messages_changed
## An AI started or stopped listening to the panel's chat (wait_for_person_message).
signal listening_changed

const ConfirmationPrompt := preload("../ui/confirmation_prompt.gd")
const CheckpointStore := preload("checkpoint_store.gd")
const NoticeBoard := preload("notice_board.gd")
const EditorChangeWatcher := preload("editor_change_watcher.gd")

## From the least to the most strict.
const MODES: Array[String] = ["full", "confirm", "read-only"]
const MODE_LABELS := {"full": "Full access", "confirm": "Ask first", "read-only": "Read-only"}
const MODE_DESCRIPTIONS_FOR_AI := {
	"full": "full access, you may change the project",
	"confirm": "the person approves each change you make",
	"read-only": "read-only, you may only look",
}
const DATA_DIRECTORY := "res://.godot/godot_wingman"
const SETTINGS_PATH := DATA_DIRECTORY + "/settings.cfg"
const ACTIVITY_LOG_PATH := DATA_DIRECTORY + "/activity.log"
## The chat, kept between editor sessions. Godot never exports the .godot folder's own
## files, so the chat does not end up in the game.
const CHAT_PATH := DATA_DIRECTORY + "/chat.json"
const MAXIMUM_ACTIVITY_ENTRIES := 300
const MAXIMUM_RESULT_LENGTH := 300
const MAXIMUM_MESSAGES := 200
## Message receiver for "every AI". NoticeBoard.PERSON (0) is the person at the editor.
const EVERYONE := -1
## Longest wait of wait_for_person_message.
const MAXIMUM_LISTEN_SECONDS := 600.0
## Connection ids restart at 1 in every editor session. AIs from earlier sessions get
## ids from here downwards in the saved chat, so their messages are not mixed up with
## a new connection that happens to get the same number.
const PAST_ID_BASE := -1000

const STATUS_WAITING := "waiting for approval"
const STATUS_RUNNING := "running"
const STATUS_DONE := "done"
const STATUS_FAILED := "failed"
const STATUS_DENIED := "denied"
const STATUS_BLOCKED := "blocked (read-only)"
## A tool call still "running" after this long has lost its MCP server.
const RUNNING_CALL_LIMIT_MILLISECONDS := 5 * 60 * 1000

## Display names of known AI apps. The key is a part of the name the app's MCP client
## reports, in lower case; the first match wins.
const AI_APP_NAMES := [
	["claude-code", "Claude Code"],
	["claude", "Claude Desktop"],
	["codex", "Codex"],
	["cursor", "Cursor"],
	["gemini", "Gemini CLI"],
	["antigravity", "Antigravity"],
	["windsurf", "Windsurf"],
	["visual studio code", "VS Code"],
	["vscode", "VS Code"],
]

## Mode for AI apps that have none saved yet in this project.
var default_mode := "full"
## Connected AIs: connection id -> {"ai_client", "name", "mode", "server_mode",
## "server_version", "tools_allowed": {tool name: true}}. "name" is shown to the person.
var connections: Dictionary = {}
var checkpoints: CheckpointStore
var notices := NoticeBoard.new()
## True while files are being put back, so the editor's reloads are not reported as
## the person's changes.
var is_going_back := false
## Entries, oldest first: {id, time, client, connection_id, tool, title, input, status,
## result, checkpoint_id, started_milliseconds}.
var activity: Array[Dictionary] = []
## The chat: what the AIs and the person wrote to each other, and events (AIs
## connecting, leaving, renamed, their mode changed), oldest first:
## {id, time, sender, from_id, receiver, to_id, text, attachments, is_event, about_id,
## read_by}. from_id and to_id are connection ids, NoticeBoard.PERSON for the person
## and EVERYONE for every AI. Events have from_id -1 and about_id the AI they concern.
## read_by: connection id -> clock time the AI got the message.
var messages: Array[Dictionary] = []
## Connection ids of the AIs waiting for the person's next chat message right now.
var listening: Dictionary = {}
var _next_message_id := 1
var _is_chat_save_planned := false

## AI app (ai_client) -> the mode last chosen for it, saved in the project.
var _saved_app_modes: Dictionary = {}
var _next_activity_id := 1
var _is_dialog_open := false
## The activity entry whose approval dialog is open now, or -1. Other waiting entries
## are in line behind it.
var open_approval_entry_id := -1
var _tree: SceneTree
var _change_watcher: EditorChangeWatcher


func _init(tree: SceneTree, addon_directory: String) -> void:
	_tree = tree
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DATA_DIRECTORY))
	checkpoints = CheckpointStore.new(DATA_DIRECTORY.path_join("checkpoints"), addon_directory)
	var settings := ConfigFile.new()
	if settings.load(SETTINGS_PATH) == OK:
		var saved_mode := String(settings.get_value("permissions", "mode", "full"))
		default_mode = saved_mode if MODES.has(saved_mode) else "full"
		var saved_app_modes: Variant = settings.get_value("permissions", "ai_modes", {})
		if saved_app_modes is Dictionary:
			for ai_client: String in saved_app_modes:
				if MODES.has(String(saved_app_modes[ai_client])):
					_saved_app_modes[ai_client] = String(saved_app_modes[ai_client])
	_load_chat()
	_change_watcher = EditorChangeWatcher.new(self, notices)


func shut_down() -> void:
	_change_watcher.disconnect_from_editor()


## The editor shows another scene: its undo history becomes the one to watch.
func on_scene_changed() -> void:
	_change_watcher.remember_current_state()


static func stricter_mode(first_mode: String, second_mode: String) -> String:
	return MODES[maxi(MODES.find(first_mode), MODES.find(second_mode))]


## The name people know an AI app by, from the name its MCP client reports.
static func get_app_display_name(ai_client: String) -> String:
	var lowered := ai_client.to_lower()
	for known_app: Array in AI_APP_NAMES:
		if lowered.contains(known_app[0]):
			return known_app[1]
	if ai_client.strip_edges().is_empty() or lowered == "unknown":
		return "AI"
	return ai_client


## An AI connected to the editor. `description` is what its MCP server said in its
## hello: {ai_client, server_version, permission_mode}.
func add_connection(connection_id: int, description: Dictionary) -> void:
	var ai_client := String(description.get("ai_client", "unknown"))
	var display_name := get_app_display_name(ai_client)
	var same_name_count := 0
	for connection: Dictionary in connections.values():
		if String(connection["name"]).begins_with(display_name):
			same_name_count += 1
	if same_name_count > 0:
		display_name = "%s %d" % [display_name, same_name_count + 1]
	var server_mode := String(description.get("permission_mode", "full"))
	_continue_past_conversation(display_name, connection_id)
	connections[connection_id] = {
		"ai_client": ai_client,
		"name": display_name,
		"mode": String(_saved_app_modes.get(ai_client, default_mode)),
		"server_mode": server_mode if MODES.has(server_mode) else "full",
		"server_version": String(description.get("server_version", "")),
		"tools_allowed": {},
		"connected_time": Time.get_time_string_from_system().left(5),
	}
	_add_event(connection_id, "%s connected (%s)." % [display_name, MODE_LABELS[get_effective_mode(connection_id, server_mode)]])
	connections_changed.emit()


func remove_connection(connection_id: int) -> void:
	var connection: Dictionary = connections.get(connection_id, {})
	if connection.is_empty():
		return
	connections.erase(connection_id)
	listening.erase(connection_id)
	_add_event(connection_id, "%s disconnected." % connection["name"])
	connections_changed.emit()


## The name shown for a connection, or `fallback` when it is not connected.
func get_connection_name(connection_id: int, fallback: String) -> String:
	return String(connections.get(connection_id, {}).get("name", get_app_display_name(fallback)))


## The person names a connected AI in the panel, for example after the model it uses
## ("Astra"), so two sessions of the same app are easy to tell apart. The name lasts
## while the AI stays connected.
func rename_connection(connection_id: int, new_name: String) -> void:
	var connection: Dictionary = connections.get(connection_id, {})
	var cleaned_name := new_name.strip_edges().left(40)
	if connection.is_empty() or cleaned_name.is_empty() or cleaned_name == connection["name"]:
		return
	_add_event(connection_id, "You renamed %s to %s." % [connection["name"], cleaned_name])
	connection["name"] = cleaned_name
	# Earlier changes and messages of this AI show the new name too.
	for entry in activity:
		if int(entry["connection_id"]) == connection_id:
			entry["client"] = cleaned_name
	for message in messages:
		if int(message["from_id"]) == connection_id:
			message["sender"] = cleaned_name
		if int(message["to_id"]) == connection_id:
			message["receiver"] = cleaned_name
	notices.rename_connection(connection_id, cleaned_name)
	_plan_chat_save()
	connections_changed.emit()
	activity_changed.emit()
	messages_changed.emit()


## Changes what one connected AI may do. Its app keeps the mode in this project, and
## the AI is told with its next tool result.
func set_connection_mode(connection_id: int, mode: String) -> void:
	var connection: Dictionary = connections.get(connection_id, {})
	if connection.is_empty() or not MODES.has(mode) or connection["mode"] == mode:
		return
	connection["mode"] = mode
	connection["tools_allowed"] = {}
	_saved_app_modes[connection["ai_client"]] = mode
	_save_settings()
	var effective_mode := stricter_mode(connection["server_mode"], mode)
	_add_event(connection_id, "You set %s to %s." % [connection["name"], MODE_LABELS[effective_mode]])
	notices.tell_one(connection_id, NoticeBoard.KIND_PERMISSION_CHANGED, "The person changed what you may do in this editor: %s." % MODE_DESCRIPTIONS_FOR_AI[effective_mode])
	connections_changed.emit()


## The mode for AI apps that have none saved yet.
func set_default_mode(mode: String) -> void:
	if not MODES.has(mode) or mode == default_mode:
		return
	default_mode = mode
	_save_settings()
	settings_changed.emit()


## Sets the default and the mode of every connected AI (the bridge method
## set_editor_permission_mode, used by the tests).
func set_mode_for_everyone(mode: String) -> void:
	if not MODES.has(mode):
		return
	for connection_id: int in connections:
		set_connection_mode(connection_id, mode)
	_saved_app_modes.clear()
	set_default_mode(mode)
	_save_settings()


## The mode that applies to a connection: the stricter of the panel and its --mode.
func get_effective_mode(connection_id: int, server_mode: String) -> String:
	var connection: Dictionary = connections.get(connection_id, {})
	var panel_mode := String(connection.get("mode", default_mode))
	return stricter_mode(server_mode if MODES.has(server_mode) else "full", panel_mode)


func forget_session_approvals(connection_id: int) -> void:
	var connection: Dictionary = connections.get(connection_id, {})
	if not connection.is_empty():
		connection["tools_allowed"] = {}
		connections_changed.emit()


func _save_settings() -> void:
	var settings := ConfigFile.new()
	settings.load(SETTINGS_PATH)
	settings.set_value("permissions", "mode", default_mode)
	settings.set_value("permissions", "ai_modes", _saved_app_modes)
	settings.save(SETTINGS_PATH)


## Decides whether a tool call may run, asking the person if needed, and takes a
## checkpoint first. Returns {"allowed": bool, "activity_id": int, "mode": String,
## "reason": String}.
func authorize(request: Dictionary) -> Dictionary:
	var tool_name := String(request.get("tool", ""))
	var caller: Dictionary = request.get("_caller", {}) if request.get("_caller") is Dictionary else {}
	var connection_id := int(caller.get("connection_id", -1))
	var effective_mode := get_effective_mode(connection_id, String(request.get("server_mode", "full")))
	var tool_input: Dictionary = request.get("input", {}) if request.get("input") is Dictionary else {}
	var entry := _add_entry(get_connection_name(connection_id, String(request.get("client", "AI"))), tool_name, String(request.get("title", tool_name)), tool_input)
	entry["connection_id"] = connection_id

	if effective_mode == "read-only":
		_update_entry(entry, STATUS_BLOCKED, "")
		return _refusal(entry, effective_mode, "The person set this AI to read-only in the Godot Wingman panel, so it may only look.")

	var tools_allowed: Dictionary = connections.get(connection_id, {}).get("tools_allowed", {})
	if effective_mode == "confirm" and not tools_allowed.has(tool_name):
		_update_entry(entry, STATUS_WAITING, "")
		var answer := await _ask_person(entry, tool_input, float(request.get("timeout_seconds", ConfirmationPrompt.DEFAULT_TIMEOUT_SECONDS)))
		if answer == ConfirmationPrompt.ANSWER_ALLOW_FOR_SESSION:
			tools_allowed[tool_name] = true
			connections_changed.emit()
		elif answer != ConfirmationPrompt.ANSWER_ALLOW:
			var no_answer := answer == ConfirmationPrompt.ANSWER_NO_ANSWER
			_update_entry(entry, STATUS_DENIED, "no answer in time" if no_answer else "")
			return _refusal(entry, effective_mode, "Nobody answered the approval dialog in the Godot editor in time." if no_answer else "The person at the Godot editor denied this change.")

	entry["checkpoint_id"] = checkpoints.take()
	# Start from the current undo state, so this call's changes are known to be the AI's.
	_change_watcher.remember_current_state()
	entry["started_milliseconds"] = Time.get_ticks_msec()
	_update_entry(entry, STATUS_RUNNING, "")
	return {"allowed": true, "activity_id": entry["id"], "mode": effective_mode, "reason": ""}


## Records how a tool call ended.
func finish(activity_id: int, succeeded: bool, result_text: String) -> void:
	var entry := find_entry(activity_id)
	if entry.is_empty():
		return
	var shortened_result := result_text.strip_edges().replace("\n", " ")
	if shortened_result.length() > MAXIMUM_RESULT_LENGTH:
		shortened_result = shortened_result.left(MAXIMUM_RESULT_LENGTH) + "..."
	_update_entry(entry, STATUS_DONE if succeeded else STATUS_FAILED, shortened_result)
	_append_to_log_file(entry)


## The newest AI tool call that is still running, or {} when none is.
func get_running_ai_call() -> Dictionary:
	for entry_index in range(activity.size() - 1, -1, -1):
		var entry := activity[entry_index]
		if entry["status"] != STATUS_RUNNING:
			continue
		if Time.get_ticks_msec() - int(entry.get("started_milliseconds", 0)) < RUNNING_CALL_LIMIT_MILLISECONDS:
			return entry
	return {}


## A message from an AI to every other AI (tell_other_ais). Returns the names of the
## AIs that will get it.
func post_message(from_connection_id: int, from_name: String, text: String) -> PackedStringArray:
	var message := _add_message({"sender": from_name, "from_id": from_connection_id, "receiver": "everyone", "to_id": EVERYONE, "text": text})
	_append_to_log_file({"time": Time.get_datetime_string_from_system(false, true), "client": from_name, "tool": "tell_other_ais", "title": text, "status": "message"})
	return notices.post_message(from_connection_id, from_name, text, int(message["id"]))


## The person writes in the panel's chat, to one AI (its connection id) or to EVERYONE.
## `attachments`: [{kind: "file" | "folder" | "node" | "image", path, scene?}].
## Listening AIs get it right away, the others with their next tool result.
func send_from_person(to_id: int, text: String, attachments: Array = []) -> void:
	var receiver := "everyone" if to_id == EVERYONE else get_connection_name(to_id, "AI")
	var message := _add_message({"sender": "You", "from_id": NoticeBoard.PERSON, "receiver": receiver, "to_id": to_id, "text": text, "attachments": attachments})
	_append_to_log_file({"time": Time.get_datetime_string_from_system(false, true), "client": "person to %s" % receiver, "tool": "chat", "title": text, "status": "message"})
	if to_id == EVERYONE:
		notices.post_message(NoticeBoard.PERSON, "You", text, int(message["id"]), attachments)
	else:
		notices.send_from_person(to_id, text, int(message["id"]), attachments)


## An AI answers the person in the chat (reply_to_person). `files` are project paths
## the person can open from the message.
func post_reply(from_connection_id: int, from_name: String, text: String, files: Array = []) -> void:
	var attachments := []
	for file_path: String in files:
		attachments.append({"kind": "folder" if file_path.ends_with("/") else "file", "path": file_path})
	_add_message({"sender": from_name, "from_id": from_connection_id, "receiver": "You", "to_id": NoticeBoard.PERSON, "text": text, "attachments": attachments})
	_append_to_log_file({"time": Time.get_datetime_string_from_system(false, true), "client": from_name, "tool": "reply_to_person", "title": text, "status": "message"})


## The news for one AI, attached to its next answer by the bridge. Chat messages in it
## count as read by that AI from now on.
func take_notices(connection_id: int) -> Array:
	var pending: Array = notices.take_pending(connection_id)
	var read_ids := {}
	for notice: Dictionary in pending:
		if notice.has("message_id"):
			read_ids[int(notice["message_id"])] = true
	if not read_ids.is_empty():
		var read_time := Time.get_time_string_from_system().left(5)
		for message in messages:
			if read_ids.has(int(message["id"])):
				message["read_by"][connection_id] = read_time
		_plan_chat_save()
		messages_changed.emit()
	return pending


## Waits until the person writes to this AI (or to every AI) in the chat, at most
## `timeout_seconds`. The message itself reaches the AI as news with the answer.
func wait_for_person_message(connection_id: int, timeout_seconds: float) -> bool:
	if notices.has_message_from_person(connection_id):
		return true
	listening[connection_id] = true
	listening_changed.emit()
	var deadline_milliseconds := Time.get_ticks_msec() + int(clampf(timeout_seconds, 1.0, MAXIMUM_LISTEN_SECONDS) * 1000.0)
	var has_message := false
	while connections.has(connection_id) and Time.get_ticks_msec() < deadline_milliseconds:
		if notices.has_message_from_person(connection_id):
			has_message = true
			break
		await _tree.process_frame
	if listening.erase(connection_id):
		listening_changed.emit()
	return has_message


## The messages of one conversation in the chat: with one AI (its connection id), or
## EVERYONE for messages to every AI and events.
func get_conversation(conversation_id: int) -> Array[Dictionary]:
	var conversation: Array[Dictionary] = []
	for message in messages:
		var from_id := int(message["from_id"])
		var to_id := int(message["to_id"])
		var belongs := false
		if message["is_event"]:
			belongs = conversation_id == EVERYONE or int(message["about_id"]) == conversation_id
		elif conversation_id == EVERYONE:
			belongs = to_id == EVERYONE
		else:
			belongs = (from_id == conversation_id and to_id == NoticeBoard.PERSON) or (from_id == NoticeBoard.PERSON and to_id == conversation_id)
		if belongs:
			conversation.append(message)
	return conversation


func _add_event(about_id: int, text: String) -> void:
	_add_message({"from_id": -1, "to_id": EVERYONE, "text": text, "is_event": true, "about_id": about_id})


func _add_message(fields: Dictionary) -> Dictionary:
	var message := {
		"id": _next_message_id,
		"time": Time.get_time_string_from_system().left(5),
		"sender": "",
		"from_id": -1,
		"receiver": "",
		"to_id": EVERYONE,
		"text": "",
		"attachments": [],
		"is_event": false,
		"about_id": -1,
		"read_by": {},
	}
	message.merge(fields, true)
	_next_message_id += 1
	messages.append(message)
	while messages.size() > MAXIMUM_MESSAGES:
		messages.pop_front()
	_plan_chat_save()
	messages_changed.emit()
	return message


## Saves the chat once at the end of the frame, however many messages changed in it.
func _plan_chat_save() -> void:
	if not _is_chat_save_planned:
		_is_chat_save_planned = true
		_save_chat.call_deferred()


func _save_chat() -> void:
	_is_chat_save_planned = false
	var file := FileAccess.open(CHAT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"next_message_id": _next_message_id, "messages": messages}, "\t"))


## Reads the chat of earlier editor sessions. Every AI in it gets a past id (see
## PAST_ID_BASE) until an AI with the same name connects again.
func _load_chat() -> void:
	if not FileAccess.file_exists(CHAT_PATH):
		return
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(CHAT_PATH))
	if not saved is Dictionary or not saved.get("messages") is Array:
		return
	var past_ids := {}
	var to_past_id := func(saved_id: int) -> int:
		if saved_id <= 0 and saved_id > PAST_ID_BASE:
			return saved_id
		if not past_ids.has(saved_id):
			past_ids[saved_id] = PAST_ID_BASE - past_ids.size()
		return past_ids[saved_id]
	for saved_message: Variant in saved["messages"]:
		if not saved_message is Dictionary:
			continue
		var message: Dictionary = saved_message
		for id_key: String in ["id", "from_id", "to_id", "about_id"]:
			message[id_key] = int(message.get(id_key, -1))
		for id_key: String in ["from_id", "to_id", "about_id"]:
			message[id_key] = to_past_id.call(message[id_key])
		var read_by := {}
		var saved_read_by: Variant = message.get("read_by", {})
		if saved_read_by is Dictionary:
			for reader_id: Variant in saved_read_by:
				read_by[to_past_id.call(int(reader_id))] = String(saved_read_by[reader_id])
		message["read_by"] = read_by
		if not message.get("attachments") is Array:
			message["attachments"] = []
		message["is_event"] = bool(message.get("is_event", false))
		messages.append(message)
	while messages.size() > MAXIMUM_MESSAGES:
		messages.pop_front()
	_next_message_id = maxi(int(saved.get("next_message_id", 1)), 1)
	for message in messages:
		_next_message_id = maxi(_next_message_id, int(message["id"]) + 1)


## An AI connects under the name of an AI from an earlier session ("Claude Code"): its
## conversation goes on where that one left off.
func _continue_past_conversation(display_name: String, connection_id: int) -> void:
	var past_id := 0
	for index in range(messages.size() - 1, -1, -1):
		var message: Dictionary = messages[index]
		if int(message["from_id"]) <= PAST_ID_BASE and message["sender"] == display_name:
			past_id = int(message["from_id"])
		elif int(message["to_id"]) <= PAST_ID_BASE and message["receiver"] == display_name:
			past_id = int(message["to_id"])
		if past_id != 0:
			break
	if past_id == 0:
		return
	for message in messages:
		for id_key: String in ["from_id", "to_id", "about_id"]:
			if int(message[id_key]) == past_id:
				message[id_key] = connection_id
		if message["read_by"].has(past_id):
			message["read_by"][connection_id] = message["read_by"][past_id]
			message["read_by"].erase(past_id)


func find_entry(activity_id: int) -> Dictionary:
	for entry in activity:
		if int(entry["id"]) == activity_id:
			return entry
	return {}


## What going back to before a step would change: {"changed": [...], "removed": [...]}.
func preview_going_back(activity_id: int) -> Dictionary:
	var entry := find_entry(activity_id)
	var checkpoint_id := int(entry.get("checkpoint_id", -1))
	if not checkpoints.has_checkpoint(checkpoint_id):
		return {}
	return checkpoints.preview_restore(checkpoint_id)


## Puts every text file back as it was before the step, then updates the editor: open
## scenes are reloaded, project settings and import options applied. Unsaved changes
## in open scenes are lost. Returns {"changed", "removed", "failed"} or {} when the
## step has no checkpoint.
func go_back_to_before(activity_id: int) -> Dictionary:
	var entry := find_entry(activity_id)
	var checkpoint_id := int(entry.get("checkpoint_id", -1))
	if not checkpoints.has_checkpoint(checkpoint_id):
		return {}
	is_going_back = true
	var project_file_before := FileAccess.get_file_as_string("res://project.godot")
	var outcome := checkpoints.restore(checkpoint_id)
	var changed_paths: Array = outcome["changed"]
	if changed_paths.has("res://project.godot"):
		_apply_restored_project_settings(project_file_before, FileAccess.get_file_as_string("res://project.godot"))
	await _refresh_editor_after_restore(changed_paths)
	_change_watcher.remember_current_state()
	is_going_back = false
	notices.report_went_back("step %d (\"%s\" by %s)" % [activity_id, entry["title"], entry["client"]], outcome)

	var restore_entry := _add_entry("You", "go_back", "Went back to before step %d" % activity_id, {})
	_update_entry(restore_entry, STATUS_DONE if Array(outcome["failed"]).is_empty() else STATUS_FAILED,
		"%d files restored, %d removed, %d failed" % [changed_paths.size(), Array(outcome["removed"]).size(), Array(outcome["failed"]).size()])
	_append_to_log_file(restore_entry)
	return outcome


func clear_activity() -> void:
	activity.clear()
	activity_changed.emit()


## Only one approval dialog at a time: two AIs (or parallel calls) wait in line.
func _ask_person(entry: Dictionary, tool_input: Dictionary, timeout_seconds: float) -> String:
	var deadline_milliseconds := Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while _is_dialog_open:
		if Time.get_ticks_msec() > deadline_milliseconds:
			return ConfirmationPrompt.ANSWER_NO_ANSWER
		await _tree.process_frame
	# Another dialog may have allowed this tool for the session while we waited.
	var tools_allowed: Dictionary = connections.get(int(entry["connection_id"]), {}).get("tools_allowed", {})
	if tools_allowed.has(entry["tool"]):
		return ConfirmationPrompt.ANSWER_ALLOW
	_is_dialog_open = true
	open_approval_entry_id = int(entry["id"])
	activity_changed.emit()
	var remaining_seconds := maxf(1.0, (deadline_milliseconds - Time.get_ticks_msec()) / 1000.0)
	var answer: String = await ConfirmationPrompt.ask_about_tool(entry["client"], entry["tool"], entry["title"], tool_input, remaining_seconds)
	_is_dialog_open = false
	open_approval_entry_id = -1
	return answer


func _add_entry(client_name: String, tool_name: String, title: String, tool_input: Dictionary) -> Dictionary:
	var entry := {
		"id": _next_activity_id,
		"time": Time.get_datetime_string_from_system(false, true),
		"client": client_name,
		"connection_id": -1,
		"tool": tool_name,
		"title": title,
		"input": JSON.stringify(tool_input),
		"status": STATUS_RUNNING,
		"result": "",
		"checkpoint_id": -1,
	}
	_next_activity_id += 1
	activity.append(entry)
	while activity.size() > MAXIMUM_ACTIVITY_ENTRIES:
		activity.pop_front()
	activity_changed.emit()
	return entry


func _update_entry(entry: Dictionary, status: String, result_text: String) -> void:
	entry["status"] = status
	entry["result"] = result_text
	activity_changed.emit()


func _refusal(entry: Dictionary, effective_mode: String, reason: String) -> Dictionary:
	_append_to_log_file(entry)
	return {"allowed": false, "activity_id": entry["id"], "mode": effective_mode, "reason": reason}


func _append_to_log_file(entry: Dictionary) -> void:
	var log_file := FileAccess.open(ACTIVITY_LOG_PATH, FileAccess.READ_WRITE)
	if log_file == null:
		log_file = FileAccess.open(ACTIVITY_LOG_PATH, FileAccess.WRITE)
	if log_file == null:
		return
	log_file.seek_end()
	var logged_entry := entry.duplicate()
	logged_entry.erase("checkpoint_id")
	logged_entry.erase("connection_id")
	logged_entry.erase("started_milliseconds")
	log_file.store_line(JSON.stringify(logged_entry))
	log_file.close()


## The editor keeps project settings in memory and writes them back on save, so a
## restored project.godot alone would be overwritten. Apply the restored values to the
## in-memory settings instead, and remove settings that were added after the checkpoint.
func _apply_restored_project_settings(text_before: String, restored_text: String) -> void:
	var settings_before := _read_settings(text_before)
	var restored_settings := _read_settings(restored_text)
	for setting_name: String in restored_settings:
		ProjectSettings.set_setting(setting_name, restored_settings[setting_name])
	for setting_name: String in settings_before:
		if restored_settings.has(setting_name):
			continue
		# Built-in settings go back to their default; settings the project added are removed.
		if ProjectSettings.property_can_revert(setting_name):
			ProjectSettings.set_setting(setting_name, ProjectSettings.property_get_revert(setting_name))
		else:
			ProjectSettings.set_setting(setting_name, null)
	ProjectSettings.save()


static func _read_settings(project_file_text: String) -> Dictionary:
	var project_file := ConfigFile.new()
	var settings := {}
	if project_file.parse(project_file_text) != OK:
		return settings
	for section_name in project_file.get_sections():
		if section_name == "":
			continue
		for key in project_file.get_section_keys(section_name):
			settings["%s/%s" % [section_name, key]] = project_file.get_value(section_name, key)
	return settings


func _refresh_editor_after_restore(changed_paths: Array) -> void:
	var file_system := EditorInterface.get_resource_filesystem()
	file_system.scan()
	while file_system.is_scanning():
		await _tree.process_frame

	var open_scene_paths := EditorInterface.get_open_scenes()
	var sources_to_reimport := PackedStringArray()
	for changed_path: String in changed_paths:
		if changed_path.get_extension() == "import":
			var source_path := changed_path.trim_suffix(".import")
			if FileAccess.file_exists(source_path):
				sources_to_reimport.append(source_path)
		elif open_scene_paths.has(changed_path):
			EditorInterface.reload_scene_from_path(changed_path)
		elif ResourceLoader.has_cached(changed_path):
			ResourceLoader.load(changed_path, "", ResourceLoader.CACHE_MODE_REPLACE)
	if not sources_to_reimport.is_empty():
		file_system.reimport_files(sources_to_reimport)
