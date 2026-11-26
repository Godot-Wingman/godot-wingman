@tool
extends Logger
## Collects everything the editor prints (messages, warnings, errors) into a ring buffer.
##
## The MCP server reads this buffer with the get_logs tool, so the AI can see the
## Output panel and errors with file, line and stack trace, the same way a person would.
##
## Requires Godot 4.5 or newer (the Logger class). The plugin only loads this file
## when the Logger class exists.
##
## Godot may call these methods from any thread, so every access to the buffer is
## protected by a mutex.

const MAX_STORED_ENTRIES := 3000

var _entries: Array[Dictionary] = []
var _next_entry_id: int = 1
var _entries_mutex := Mutex.new()
## Terminal color codes such as "\u001b[1;31m" that Godot adds to console output.
var _terminal_color_pattern := RegEx.create_from_string("\\x{1b}\\[[0-9;]*[A-Za-z]")


func _log_message(message: String, is_error: bool) -> void:
	var trimmed_message := _terminal_color_pattern.sub(message, "", true).strip_edges(false, true)
	if trimmed_message == "":
		return
	_append_entry({"level": "error" if is_error else "info", "message": trimmed_message})


func _log_error(
	function: String,
	file: String,
	line: int,
	code: String,
	rationale: String,
	_editor_notify: bool,
	error_type: int,
	script_backtraces: Array[ScriptBacktrace]
) -> void:
	var level := "error"
	match error_type:
		ERROR_TYPE_WARNING:
			level = "warning"
		ERROR_TYPE_SCRIPT:
			level = "script_error"
		ERROR_TYPE_SHADER:
			level = "shader_error"

	var entry := {
		"level": level,
		"message": rationale if rationale != "" else code,
		"file": file,
		"line": line,
		"function": function,
	}
	# `code` is the failed check inside the engine (for example "p_node == nullptr").
	# It only adds information when there is also a human-readable rationale.
	if rationale != "" and code != "":
		entry["engine_check"] = code

	var stack_frames: Array[String] = []
	for backtrace in script_backtraces:
		for frame_index in backtrace.get_frame_count():
			stack_frames.append(
				"%s:%d in %s()" % [
					backtrace.get_frame_file(frame_index),
					backtrace.get_frame_line(frame_index),
					backtrace.get_frame_function(frame_index),
				]
			)
	if not stack_frames.is_empty():
		entry["stack"] = stack_frames

	_append_entry(entry)


func _append_entry(entry: Dictionary) -> void:
	_entries_mutex.lock()
	entry["id"] = _next_entry_id
	entry["time"] = Time.get_time_string_from_system()
	_next_entry_id += 1
	_entries.append(entry)
	if _entries.size() > MAX_STORED_ENTRIES:
		_entries.pop_front()
	_entries_mutex.unlock()


## The id the next entry will get. Remember it before an action, then ask for
## entries from it to see only what that action printed.
func get_next_entry_id() -> int:
	_entries_mutex.lock()
	var next_id := _next_entry_id
	_entries_mutex.unlock()
	return next_id


## Returns stored entries, oldest first.
## `from_id`: only entries with an id greater than or equal to this.
## `levels`: only these levels (empty = all). `search`: case-insensitive text filter.
## `limit`: maximum number of entries; the newest ones are kept.
func get_entries(from_id: int, levels: Array, search: String, limit: int) -> Array[Dictionary]:
	var lowercase_search := search.to_lower()
	var matching_entries: Array[Dictionary] = []

	_entries_mutex.lock()
	for entry in _entries:
		if int(entry["id"]) < from_id:
			continue
		if not levels.is_empty() and not levels.has(entry["level"]):
			continue
		if lowercase_search != "" and not String(entry["message"]).to_lower().contains(lowercase_search):
			continue
		matching_entries.append(entry.duplicate(true))
	_entries_mutex.unlock()

	if limit > 0 and matching_entries.size() > limit:
		return matching_entries.slice(matching_entries.size() - limit)
	return matching_entries
