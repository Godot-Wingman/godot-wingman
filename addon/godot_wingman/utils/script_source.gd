@tool
extends RefCounted
## Turns a snippet of GDScript written by the AI into a complete script, and makes the
## errors Godot reports about it easy to read. Used by execute_editor_script (in the
## editor) and execute_game_script (in the running game).


## Wraps `code` into a script that extends `base_script_path`. Unless the code defines
## `func run():` itself, it becomes the body of run(). Returns the source and how many
## lines were added before the AI's first line (to correct error line numbers).
static func prepare(code: String, base_script_path: String, needs_tool_annotation: bool) -> Dictionary:
	var has_run_function := RegEx.create_from_string("(?m)^func\\s+run\\s*\\(").search(code) != null
	var has_extends_line := RegEx.create_from_string("(?m)^extends\\s").search(code) != null
	var has_tool_annotation := RegEx.create_from_string("(?m)^@tool").search(code) != null

	var header_lines: Array[String] = []
	# Without @tool, Godot does not run scripts inside the editor.
	if needs_tool_annotation and not has_tool_annotation:
		header_lines.append("@tool")
	if not has_extends_line:
		header_lines.append("extends \"%s\"" % base_script_path)

	var body := code
	if not has_run_function:
		header_lines.append("func run():")
		var indented_lines: Array[String] = []
		for code_line in code.split("\n"):
			indented_lines.append("\t" + code_line)
		body = "\n".join(indented_lines)

	return {"source": "\n".join(header_lines) + "\n" + body + "\n", "line_offset": header_lines.size()}


## Makes log entries about the AI's code easy to read:
## - errors of the in-memory script ("gdscript://...") report lines of the wrapped
##   source, so they are shifted to match the lines the AI wrote;
## - the in-memory file name and the addon's own stack frames are noise, so they go.
static func clean_log_entries(entries: Array, line_offset: int) -> Array:
	for entry in entries:
		var file_name := String(entry.get("file", ""))
		if file_name == "" or file_name.begins_with("gdscript://"):
			entry["file"] = "<your code>"
			if entry.has("line") and int(entry["line"]) > line_offset:
				entry["line"] = int(entry["line"]) - line_offset
		if entry.has("stack"):
			var useful_frames: Array[String] = []
			for frame in entry["stack"]:
				if String(frame).contains("addons/godot_wingman/"):
					continue
				if String(frame).begins_with("gdscript://"):
					var frame_line := int(String(frame).get_slice(":", 2).get_slice(" ", 0))
					useful_frames.append("<your code>:%d" % (frame_line - line_offset))
				else:
					useful_frames.append(frame)
			if useful_frames.is_empty():
				entry.erase("stack")
			else:
				entry["stack"] = useful_frames
		entry.erase("function")
	return entries


## Splits log entries into printed lines and problems (errors and warnings).
static func split_printed_and_problems(entries: Array) -> Dictionary:
	var printed_lines: Array[String] = []
	var problems: Array = []
	for entry in entries:
		if entry["level"] == "info":
			printed_lines.append(entry["message"])
		else:
			problems.append(entry)
	return {"printed": printed_lines, "problems": problems}
