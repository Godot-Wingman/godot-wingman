@tool
extends RefCounted
## What the AI is allowed to do in this editor, and what it has done.
##
## - Permission mode chosen in the Godot Pilot panel. The MCP server has its own mode
##   (its --mode option); the stricter of the two applies, so neither side can loosen
##   the other.
## - In "confirm" mode the person can allow one tool for the rest of the session.
## - Activity: every change the AI asks for and its result. Shown in the panel and
##   appended to .godot/godot_pilot/activity.log; nothing leaves the computer.
## - Checkpoints: before each change the project's text files are remembered, so the
##   panel can put the project back to how it was before any step.
##
## The MCP server calls authorize() before every tool that changes something, and
## finish() after it.

signal activity_changed
signal settings_changed

const ConfirmationPrompt := preload("../ui/confirmation_prompt.gd")
const CheckpointStore := preload("checkpoint_store.gd")

## From the least to the most strict.
const MODES: Array[String] = ["full", "confirm", "read-only"]
const DATA_DIRECTORY := "res://.godot/godot_pilot"
const SETTINGS_PATH := DATA_DIRECTORY + "/settings.cfg"
const ACTIVITY_LOG_PATH := DATA_DIRECTORY + "/activity.log"
const MAXIMUM_ACTIVITY_ENTRIES := 300
const MAXIMUM_RESULT_LENGTH := 300

const STATUS_WAITING := "waiting for approval"
const STATUS_RUNNING := "running"
const STATUS_DONE := "done"
const STATUS_FAILED := "failed"
const STATUS_DENIED := "denied"
const STATUS_BLOCKED := "blocked (read-only)"

## Mode chosen in the panel for this project.
var editor_mode := "full"
var checkpoints: CheckpointStore
## Entries, oldest first: {id, time, client, tool, title, input, status, result, checkpoint_id}.
var activity: Array[Dictionary] = []

var _tools_allowed_for_session: Dictionary = {}
var _next_activity_id := 1
var _is_dialog_open := false
var _tree: SceneTree


func _init(tree: SceneTree, addon_directory: String) -> void:
	_tree = tree
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DATA_DIRECTORY))
	checkpoints = CheckpointStore.new(DATA_DIRECTORY.path_join("checkpoints"), addon_directory)
	var settings := ConfigFile.new()
	if settings.load(SETTINGS_PATH) == OK:
		var saved_mode := String(settings.get_value("permissions", "mode", "full"))
		editor_mode = saved_mode if MODES.has(saved_mode) else "full"


static func stricter_mode(first_mode: String, second_mode: String) -> String:
	return MODES[maxi(MODES.find(first_mode), MODES.find(second_mode))]


func set_editor_mode(mode: String) -> void:
	if not MODES.has(mode) or mode == editor_mode:
		return
	editor_mode = mode
	_tools_allowed_for_session.clear()
	var settings := ConfigFile.new()
	settings.load(SETTINGS_PATH)
	settings.set_value("permissions", "mode", mode)
	settings.save(SETTINGS_PATH)
	settings_changed.emit()


func get_tools_allowed_for_session() -> PackedStringArray:
	return PackedStringArray(_tools_allowed_for_session.keys())


func forget_session_approvals() -> void:
	_tools_allowed_for_session.clear()
	settings_changed.emit()


## Decides whether a tool call may run, asking the person if needed, and takes a
## checkpoint first. Returns {"allowed": bool, "activity_id": int, "mode": String,
## "reason": String}.
func authorize(request: Dictionary) -> Dictionary:
	var tool_name := String(request.get("tool", ""))
	var server_mode := String(request.get("server_mode", "full"))
	var effective_mode := stricter_mode(server_mode if MODES.has(server_mode) else "full", editor_mode)
	var tool_input: Dictionary = request.get("input", {}) if request.get("input") is Dictionary else {}
	var entry := _add_entry(String(request.get("client", "AI")), tool_name, String(request.get("title", tool_name)), tool_input)

	if effective_mode == "read-only":
		_update_entry(entry, STATUS_BLOCKED, "")
		return _refusal(entry, effective_mode, "The person set Godot Pilot to read-only in the Godot Pilot panel, so the AI may only look.")

	if effective_mode == "confirm" and not _tools_allowed_for_session.has(tool_name):
		_update_entry(entry, STATUS_WAITING, "")
		var answer := await _ask_person(entry, tool_input, float(request.get("timeout_seconds", ConfirmationPrompt.DEFAULT_TIMEOUT_SECONDS)))
		if answer == ConfirmationPrompt.ANSWER_ALLOW_FOR_SESSION:
			_tools_allowed_for_session[tool_name] = true
			settings_changed.emit()
		elif answer != ConfirmationPrompt.ANSWER_ALLOW:
			var no_answer := answer == ConfirmationPrompt.ANSWER_NO_ANSWER
			_update_entry(entry, STATUS_DENIED, "no answer in time" if no_answer else "")
			return _refusal(entry, effective_mode, "Nobody answered the approval dialog in the Godot editor in time." if no_answer else "The person at the Godot editor denied this change.")

	entry["checkpoint_id"] = checkpoints.take()
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
	var project_file_before := FileAccess.get_file_as_string("res://project.godot")
	var outcome := checkpoints.restore(checkpoint_id)
	var changed_paths: Array = outcome["changed"]
	if changed_paths.has("res://project.godot"):
		_apply_restored_project_settings(project_file_before, FileAccess.get_file_as_string("res://project.godot"))
	await _refresh_editor_after_restore(changed_paths)

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
	if _tools_allowed_for_session.has(entry["tool"]):
		return ConfirmationPrompt.ANSWER_ALLOW
	_is_dialog_open = true
	var remaining_seconds := maxf(1.0, (deadline_milliseconds - Time.get_ticks_msec()) / 1000.0)
	var answer: String = await ConfirmationPrompt.ask_about_tool(entry["client"], entry["tool"], entry["title"], tool_input, remaining_seconds)
	_is_dialog_open = false
	return answer


func _add_entry(client_name: String, tool_name: String, title: String, tool_input: Dictionary) -> Dictionary:
	var entry := {
		"id": _next_activity_id,
		"time": Time.get_datetime_string_from_system(false, true),
		"client": client_name,
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
