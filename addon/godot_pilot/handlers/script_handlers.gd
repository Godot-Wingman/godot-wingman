@tool
extends RefCounted
## Handlers of the "script" toolset: creating, reading, editing, checking and attaching
## scripts (GDScript and C#).
##
## Scripts are written through Godot's resource system, not only to disk, so the open
## Script editor shows the new text and Godot does not ask "the file changed on disk".
## Every GDScript change is checked by Godot's own parser and errors come back at once.

const PilotError := preload("../utils/pilot_error.gd")

const SCRIPT_EXTENSIONS := ["gd", "cs"]
const MAX_READ_LINES := 2000

var _context: RefCounted


func _init(context: RefCounted) -> void:
	_context = context


func register_methods(dispatcher: RefCounted) -> void:
	dispatcher.register_method("create_script", _create_script)
	dispatcher.register_method("read_script", _read_script)
	dispatcher.register_method("edit_script", _edit_script)
	dispatcher.register_method("validate_script", _validate_script)
	dispatcher.register_method("attach_script", _attach_script)


func _create_script(params: Dictionary) -> Variant:
	var script_path := String(params.get("path", ""))
	var path_problem := _check_script_path(script_path)
	if path_problem != null:
		return path_problem
	if FileAccess.file_exists(script_path) and not bool(params.get("overwrite", false)):
		return PilotError.new("ALREADY_EXISTS", "'%s' already exists." % script_path, "Change it with edit_script, or pass overwrite: true.")

	var base_type := String(params.get("base_type", "Node"))
	var source_code := String(params.get("content", ""))
	if source_code == "":
		source_code = _make_template(script_path, base_type)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(script_path.get_base_dir()))
	var write_result: Variant = _write_script_source(script_path, source_code)
	if write_result is PilotError:
		return write_result

	var result := {"created": script_path}
	result.merge(_check_script(script_path))
	if params.has("attach_to"):
		var attach_result: Variant = _attach_script({"node_path": params["attach_to"], "script_path": script_path})
		if attach_result is PilotError:
			return attach_result
		result["attached_to"] = attach_result["node"]
	return result


func _read_script(params: Dictionary) -> Variant:
	var script_path := String(params.get("path", ""))
	if not FileAccess.file_exists(script_path):
		return PilotError.new("FILE_NOT_FOUND", "No file at '%s'." % script_path)
	var lines := FileAccess.get_file_as_string(script_path).split("\n")
	var first_line := maxi(1, int(params.get("start_line", 1)))
	var last_line := mini(lines.size(), int(params.get("end_line", first_line + MAX_READ_LINES - 1)))

	var numbered_lines: Array[String] = []
	for line_number in range(first_line, last_line + 1):
		numbered_lines.append("%d\t%s" % [line_number, lines[line_number - 1]])
	var result := {"path": script_path, "total_lines": lines.size(), "content": "\n".join(numbered_lines)}
	if last_line < lines.size():
		result["note"] = "Showing lines %d-%d. Pass start_line to read further." % [first_line, last_line]
	return result


## Replaces an exact piece of text, or a range of lines, then checks the script.
func _edit_script(params: Dictionary) -> Variant:
	var script_path := String(params.get("path", ""))
	if not FileAccess.file_exists(script_path):
		return PilotError.new("FILE_NOT_FOUND", "No file at '%s'." % script_path)
	var source_code := FileAccess.get_file_as_string(script_path)
	var new_source_code: String

	if params.has("old_text"):
		var old_text := String(params["old_text"])
		var new_text := String(params.get("new_text", ""))
		var occurrence_count := source_code.count(old_text)
		if old_text == "" or occurrence_count == 0:
			return PilotError.new("TEXT_NOT_FOUND", "old_text was not found in '%s'." % script_path, "Copy the text exactly, including tabs. Read the script with read_script first.")
		if occurrence_count > 1 and not bool(params.get("replace_all", false)):
			return PilotError.new("TEXT_NOT_UNIQUE", "old_text appears %d times." % occurrence_count, "Include more surrounding lines to make it unique, or pass replace_all: true.")
		new_source_code = source_code.replace(old_text, new_text)
	elif params.has("start_line"):
		var lines := source_code.split("\n")
		var first_line := int(params["start_line"])
		var last_line := int(params.get("end_line", first_line))
		if first_line < 1 or last_line < first_line - 1 or last_line > lines.size():
			return PilotError.new("INVALID_RANGE", "Lines %d-%d are outside the file (%d lines)." % [first_line, last_line, lines.size()])
		var replacement_lines := String(params.get("new_text", "")).split("\n")
		var kept_before := lines.slice(0, first_line - 1)
		var kept_after := lines.slice(last_line)
		new_source_code = "\n".join(kept_before + replacement_lines + kept_after)
	elif params.has("content"):
		new_source_code = String(params["content"])
	else:
		return PilotError.new("NOTHING_TO_EDIT", "Pass old_text + new_text, start_line + end_line + new_text, or content.")

	var write_result: Variant = _write_script_source(script_path, new_source_code)
	if write_result is PilotError:
		return write_result
	var result := {"edited": script_path, "total_lines": new_source_code.count("\n") + 1}
	result.merge(_check_script(script_path))
	return result


func _validate_script(params: Dictionary) -> Variant:
	var script_path := String(params.get("path", ""))
	if not FileAccess.file_exists(script_path):
		return PilotError.new("FILE_NOT_FOUND", "No file at '%s'." % script_path)
	var result := {"path": script_path}
	result.merge(_check_script(script_path))
	return result


func _attach_script(params: Dictionary) -> Variant:
	var node: Variant = _context.find_node_in_edited_scene(String(params.get("node_path", ".")))
	if node is PilotError:
		return node
	var script_path: Variant = params.get("script_path")
	var new_script: Script = null
	if script_path != null and String(script_path) != "":
		if not ResourceLoader.exists(String(script_path)):
			return PilotError.new("FILE_NOT_FOUND", "No script at '%s'." % script_path)
		new_script = load(String(script_path))
		var script_base := new_script.get_instance_base_type()
		if script_base != "" and not node.is_class(script_base):
			return PilotError.new("WRONG_BASE_TYPE", "The script extends %s, but the node is a %s." % [script_base, node.get_class()], "Change the script's extends line or attach it to a matching node.")

	var undo_redo: EditorUndoRedoManager = _context.get_undo_redo()
	undo_redo.create_action("Attach script to %s" % node.name)
	undo_redo.add_do_method(node, "set_script", new_script)
	undo_redo.add_undo_method(node, "set_script", node.get_script())
	undo_redo.commit_action()
	return {"node": _context.describe_node_path(node), "script": script_path}


#region Helpers

func _check_script_path(script_path: String) -> Variant:
	if not script_path.begins_with("res://"):
		return PilotError.new("INVALID_PATH", "Script paths must start with res://, for example \"res://scripts/player.gd\".")
	if not SCRIPT_EXTENSIONS.has(script_path.get_extension()):
		return PilotError.new("INVALID_EXTENSION", "Scripts must end with .gd (GDScript) or .cs (C#).")
	if script_path.get_extension() == "cs" and not ClassDB.class_exists("CSharpScript"):
		return PilotError.new("NO_CSHARP", "This Godot editor is not the .NET build, so it cannot use C# scripts.", "Use GDScript, or open the project with the .NET (mono) build of Godot.")
	return null


func _make_template(script_path: String, base_type: String) -> String:
	if script_path.get_extension() == "cs":
		var class_name_text := script_path.get_file().get_basename().to_pascal_case()
		return "using Godot;\n\npublic partial class %s : %s\n{\n\tpublic override void _Ready()\n\t{\n\t}\n}\n" % [class_name_text, base_type]
	return "extends %s\n\n\nfunc _ready() -> void:\n\tpass\n" % base_type


## Saves the new source through the resource system so the editor sees it everywhere.
func _write_script_source(script_path: String, source_code: String) -> Variant:
	var file := FileAccess.open(script_path, FileAccess.WRITE)
	if file == null:
		return PilotError.new("WRITE_FAILED", "Could not write '%s': %s." % [script_path, error_string(FileAccess.get_open_error())])
	file.store_string(source_code)
	file.close()

	EditorInterface.get_resource_filesystem().update_file(script_path)
	if ResourceLoader.has_cached(script_path):
		var cached_script: Script = load(script_path)
		cached_script.source_code = source_code
	_update_open_script_editors(script_path, source_code)
	return null


## A script that is open in the Script editor keeps its own copy of the text. Replace it,
## and mark it as saved, so the editor never overwrites our change with old text.
func _update_open_script_editors(script_path: String, source_code: String) -> void:
	var script_editor := EditorInterface.get_script_editor()
	if script_editor == null:
		return
	var open_scripts := script_editor.get_open_scripts()
	var open_editors := script_editor.get_open_script_editors()
	for editor_index in mini(open_scripts.size(), open_editors.size()):
		if open_scripts[editor_index].resource_path != script_path:
			continue
		var code_editor := open_editors[editor_index].get_base_editor()
		if code_editor is TextEdit and code_editor.text != source_code:
			code_editor.text = source_code
			code_editor.tag_saved_version()


## Reloads a GDScript and collects the parse errors Godot reports for it.
func _check_script(script_path: String) -> Dictionary:
	if script_path.get_extension() != "gd":
		return {"check": "C# is checked when the project is built (dotnet build or the editor's Build button)."}
	var first_log_id: int = _context.get_next_log_id()
	var script: GDScript = load(script_path)
	var reload_result := script.reload(true)
	var problems: Array = []
	for entry in _context.get_logs_since(first_log_id, ["error", "script_error", "warning"]):
		if String(entry.get("file", "")) == script_path or String(entry.get("message", "")).contains(script_path):
			entry.erase("stack")
			problems.append(entry)
	if reload_result == OK and problems.is_empty():
		return {"valid": true}
	return {"valid": reload_result == OK, "problems": problems if not problems.is_empty() else ["Parse error (%s). Open the script in the editor to see it." % error_string(reload_result)]}

#endregion
