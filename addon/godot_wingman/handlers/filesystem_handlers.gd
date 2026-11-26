@tool
extends RefCounted
## Handlers of the "filesystem" toolset: listing, reading, writing, searching, moving and
## deleting project files, like the FileSystem dock.
##
## Moving keeps references working: Godot's .uid and .import companion files move along,
## and text references ("res://old/path") in scenes, resources and scripts are updated.
## Deleting moves files to the operating system's trash, so they can be restored.

const WingmanError := preload("../utils/wingman_error.gd")

const DEFAULT_LIST_LIMIT := 500
const DEFAULT_SEARCH_LIMIT := 100
## Files whose text may contain "res://" references.
const TEXT_FILE_EXTENSIONS := ["gd", "cs", "tscn", "tres", "gdshader", "gdshaderinc", "cfg", "godot", "json", "md", "txt", "import", "gdextension", "csv", "xml", "yaml", "yml", "ini"]
const COMPANION_SUFFIXES := [".uid", ".import"]

const MAXIMUM_SCAN_WAIT_SECONDS := 20.0
const SCAN_POLL_SECONDS := 0.1

var _context: RefCounted


func _init(context: RefCounted) -> void:
	_context = context


func register_methods(dispatcher: RefCounted) -> void:
	dispatcher.register_method("list_files", _list_files)
	dispatcher.register_method("read_file", _read_file)
	dispatcher.register_method("write_file", _write_file)
	dispatcher.register_method("search_project", _search_project)
	dispatcher.register_method("move_file", _move_file)
	dispatcher.register_method("delete_file", _delete_file)
	dispatcher.register_method("create_folder", _create_folder)
	dispatcher.register_method("get_dependencies", _get_dependencies)
	dispatcher.register_method("reimport_files", _reimport_files)


#region Listing and reading

## Uses the editor's file index, so it is fast and knows each file's resource type.
func _list_files(params: Dictionary) -> Variant:
	var folder_path := String(params.get("path", "res://"))
	var file_system := EditorInterface.get_resource_filesystem()
	var folder := file_system.get_filesystem_path(folder_path)
	if folder == null:
		return WingmanError.new("FOLDER_NOT_FOUND", "No folder '%s' in the project." % folder_path)
	var name_filter := String(params.get("filter", "*"))
	var limit := int(params.get("limit", DEFAULT_LIST_LIMIT))
	var entries: Array[String] = []
	_collect_files(folder, bool(params.get("recursive", true)), name_filter, limit, entries)
	var result := {"path": folder_path, "files": entries}
	if entries.size() >= limit:
		result["note"] = "Stopped at %d entries. Use a narrower path or filter." % limit
	return result


func _collect_files(folder: EditorFileSystemDirectory, recursive: bool, name_filter: String, limit: int, entries: Array[String]) -> void:
	for file_index in folder.get_file_count():
		if entries.size() >= limit:
			return
		var file_name := folder.get_file(file_index)
		if file_name.matchn(name_filter):
			entries.append("%s (%s)" % [folder.get_file_path(file_index), folder.get_file_type(file_index)])
	if not recursive:
		for subfolder_index in folder.get_subdir_count():
			entries.append(folder.get_subdir(subfolder_index).get_path() + " (folder)")
		return
	for subfolder_index in folder.get_subdir_count():
		var subfolder := folder.get_subdir(subfolder_index)
		if subfolder.get_name() == ".godot":
			continue
		_collect_files(subfolder, recursive, name_filter, limit, entries)


func _read_file(params: Dictionary) -> Variant:
	var file_path := String(params.get("path", ""))
	if not FileAccess.file_exists(file_path):
		return WingmanError.new("FILE_NOT_FOUND", "No file at '%s'." % file_path)
	if not TEXT_FILE_EXTENSIONS.has(file_path.get_extension().to_lower()):
		return WingmanError.new("NOT_TEXT", "'%s' is not a text file." % file_path, "Images and other binary files cannot be read as text. Use get_resource_properties for resources.")
	return {"path": file_path, "content": FileAccess.get_file_as_string(file_path)}


func _write_file(params: Dictionary) -> Variant:
	var file_path := String(params.get("path", ""))
	if not file_path.begins_with("res://"):
		return WingmanError.new("INVALID_PATH", "Paths must start with res://.")
	if file_path.get_extension() in ["gd", "cs"]:
		return WingmanError.new("USE_SCRIPT_TOOLS", "Use create_script or edit_script for scripts; they also check for errors.")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(file_path.get_base_dir()))
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		return WingmanError.new("WRITE_FAILED", "Could not write '%s': %s." % [file_path, error_string(FileAccess.get_open_error())])
	file.store_string(String(params.get("content", "")))
	file.close()
	await _make_files_known(PackedStringArray([file_path]))
	return {"written": file_path}


## Searches the text of project files. `query` is plain text unless `regex` is true.
func _search_project(params: Dictionary) -> Variant:
	var query := String(params.get("query", ""))
	if query == "":
		return WingmanError.new("EMPTY_QUERY", "query is empty.")
	var pattern: RegEx = null
	if bool(params.get("regex", false)):
		pattern = RegEx.create_from_string(query)
		if pattern == null or not pattern.is_valid():
			return WingmanError.new("INVALID_REGEX", "'%s' is not a valid regular expression." % query)
	var file_filter := String(params.get("file_filter", "*"))
	var limit := int(params.get("limit", DEFAULT_SEARCH_LIMIT))
	var lowercase_query := query.to_lower()

	var matches: Array[String] = []
	for file_path in _list_text_files("res://", file_filter):
		var lines := FileAccess.get_file_as_string(file_path).split("\n")
		for line_index in lines.size():
			var line := lines[line_index]
			var is_match := pattern.search(line) != null if pattern != null else line.to_lower().contains(lowercase_query)
			if is_match:
				matches.append("%s:%d: %s" % [file_path, line_index + 1, line.strip_edges().left(200)])
				if matches.size() >= limit:
					return {"matches": matches, "note": "Stopped at %d matches." % limit}
	return {"matches": matches}


func _list_text_files(folder_path: String, file_filter: String) -> Array[String]:
	var files: Array[String] = []
	var folder := DirAccess.open(folder_path)
	if folder == null:
		return files
	for file_name in folder.get_files():
		if TEXT_FILE_EXTENSIONS.has(file_name.get_extension().to_lower()) and file_name.matchn(file_filter) and file_name.get_extension() != "import":
			files.append(folder_path.path_join(file_name))
	for subfolder_name in folder.get_directories():
		if subfolder_name.begins_with("."):
			continue
		files.append_array(_list_text_files(folder_path.path_join(subfolder_name), file_filter))
	return files

#endregion


#region Moving and deleting

func _move_file(params: Dictionary) -> Variant:
	var old_path := String(params.get("from", ""))
	var new_path := String(params.get("to", ""))
	if not FileAccess.file_exists(old_path) and not DirAccess.dir_exists_absolute(old_path):
		return WingmanError.new("FILE_NOT_FOUND", "Nothing at '%s'." % old_path)
	if FileAccess.file_exists(new_path) or DirAccess.dir_exists_absolute(new_path):
		return WingmanError.new("ALREADY_EXISTS", "'%s' already exists." % new_path)
	if not new_path.begins_with("res://"):
		return WingmanError.new("INVALID_PATH", "The new path must start with res://.")

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(new_path.get_base_dir()))
	var move_error := DirAccess.rename_absolute(old_path, new_path)
	if move_error != OK:
		return WingmanError.new("MOVE_FAILED", "Could not move '%s': %s." % [old_path, error_string(move_error)])
	for companion_suffix in COMPANION_SUFFIXES:
		if FileAccess.file_exists(old_path + companion_suffix):
			DirAccess.rename_absolute(old_path + companion_suffix, new_path + companion_suffix)

	var updated_files := _replace_references(old_path, new_path)
	EditorInterface.get_resource_filesystem().scan()
	return {"moved": old_path, "to": new_path, "references_updated_in": updated_files}


## Replaces "res://old" with "res://new" in every text file that mentions it.
func _replace_references(old_path: String, new_path: String) -> Array[String]:
	var updated_files: Array[String] = []
	for file_path in _list_text_files("res://", "*"):
		var content := FileAccess.get_file_as_string(file_path)
		if not content.contains(old_path):
			continue
		var file := FileAccess.open(file_path, FileAccess.WRITE)
		if file == null:
			continue
		file.store_string(content.replace(old_path, new_path))
		file.close()
		updated_files.append(file_path)
	return updated_files


func _delete_file(params: Dictionary) -> Variant:
	var file_path := String(params.get("path", ""))
	if not FileAccess.file_exists(file_path) and not DirAccess.dir_exists_absolute(file_path):
		return WingmanError.new("FILE_NOT_FOUND", "Nothing at '%s'." % file_path)
	if file_path in ["res://", "res://project.godot"] or file_path.begins_with(_context.addon_directory):
		return WingmanError.new("PROTECTED", "'%s' cannot be deleted with this tool." % file_path)

	var users := _find_files_referencing(file_path)
	if not users.is_empty() and not bool(params.get("force", false)):
		return WingmanError.new("STILL_USED", "'%s' is still used by: %s" % [file_path, ", ".join(users)], "Remove those references first, or pass force: true.")

	var trash_error := OS.move_to_trash(ProjectSettings.globalize_path(file_path))
	if trash_error != OK:
		return WingmanError.new("DELETE_FAILED", "Could not move '%s' to the trash: %s." % [file_path, error_string(trash_error)])
	for companion_suffix in COMPANION_SUFFIXES:
		if FileAccess.file_exists(file_path + companion_suffix):
			OS.move_to_trash(ProjectSettings.globalize_path(file_path + companion_suffix))
	EditorInterface.get_resource_filesystem().scan()
	return {"moved_to_trash": file_path, "note": "The file can be restored from the operating system's trash."}


func _find_files_referencing(file_path: String) -> Array[String]:
	var users: Array[String] = []
	for candidate_path in _list_text_files("res://", "*"):
		if candidate_path != file_path and FileAccess.get_file_as_string(candidate_path).contains(file_path):
			users.append(candidate_path)
	return users


func _create_folder(params: Dictionary) -> Variant:
	var folder_path := String(params.get("path", ""))
	if not folder_path.begins_with("res://"):
		return WingmanError.new("INVALID_PATH", "Paths must start with res://.")
	var create_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder_path))
	if create_error != OK:
		return WingmanError.new("CREATE_FAILED", "Could not create '%s': %s." % [folder_path, error_string(create_error)])
	EditorInterface.get_resource_filesystem().scan()
	return {"created": folder_path}

#endregion


func _get_dependencies(params: Dictionary) -> Variant:
	var file_path := String(params.get("path", ""))
	if not ResourceLoader.exists(file_path):
		return WingmanError.new("FILE_NOT_FOUND", "No resource at '%s'." % file_path)
	var dependencies: Array[String] = []
	for dependency in ResourceLoader.get_dependencies(file_path):
		# Entries look like "uid://...::Type::res://path"; the path is the last part.
		dependencies.append(dependency.get_slice("::", dependency.get_slice_count("::") - 1))
	return {"path": file_path, "uses": dependencies, "used_by": _find_files_referencing(file_path)}


func _reimport_files(params: Dictionary) -> Variant:
	var file_paths := PackedStringArray(params.get("paths", []))
	if file_paths.is_empty():
		return WingmanError.new("NO_FILES", "paths is empty.")
	for file_path in file_paths:
		if not FileAccess.file_exists(file_path):
			return WingmanError.new("FILE_NOT_FOUND", "No file at '%s'." % file_path)
	var file_system := EditorInterface.get_resource_filesystem()
	var newly_found := await _make_files_known(file_paths)
	var known_files := PackedStringArray()
	for file_path in file_paths:
		if not newly_found.has(file_path):
			known_files.append(file_path)
	if not known_files.is_empty():
		file_system.reimport_files(known_files)
	var types := {}
	for file_path in file_paths:
		var file_type := file_system.get_file_type(file_path)
		types[file_path] = file_type if file_type != "" else "not a resource (not importable)"
	return {"imported": types}


## Tells the editor about new or changed files. Files in folders it has not scanned yet
## (for example a folder just created by a script) need a full scan, which also imports
## new assets. Returns the files that were found by that scan.
func _make_files_known(file_paths: PackedStringArray) -> PackedStringArray:
	var file_system := EditorInterface.get_resource_filesystem()
	var unknown_files := PackedStringArray()
	for file_path in file_paths:
		if file_system.get_filesystem_path(file_path.get_base_dir()) == null or file_system.get_file_type(file_path) == "":
			unknown_files.append(file_path)
	for file_path in file_paths:
		if not unknown_files.has(file_path):
			file_system.update_file(file_path)
	if unknown_files.is_empty():
		return unknown_files
	var scene_tree: SceneTree = _context.get_scene_tree()
	file_system.scan()
	var waited_seconds := 0.0
	await scene_tree.process_frame
	while (file_system.is_scanning() or file_system.get_file_type(unknown_files[0]) == "") and waited_seconds < MAXIMUM_SCAN_WAIT_SECONDS:
		await scene_tree.create_timer(SCAN_POLL_SECONDS).timeout
		waited_seconds += SCAN_POLL_SECONDS
	return unknown_files
