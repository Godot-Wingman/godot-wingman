@tool
extends RefCounted
## Remembers the project's text files before each AI change, so they can be put back.
##
## It works like a very small git: every file content is stored once, named by its
## SHA-256 hash (blobs/<hash>), and a checkpoint is a list of "file path -> hash".
## A file is only read again when its modification time changed, so taking a
## checkpoint stays fast. Everything lives in .godot/godot_wingman/checkpoints, which
## Godot and version control ignore, and is cleared when the editor starts.
##
## Only text files are covered (scripts, scenes, resources, settings, import options).
## Images, sounds and models are not copied.

const TRACKED_EXTENSIONS: Array[String] = [
	"gd", "cs", "tscn", "tres", "gdshader", "gdshaderinc", "godot", "cfg", "json",
	"import", "gdextension", "csv", "txt", "md",
]
const MAXIMUM_FILE_SIZE_BYTES := 2 * 1024 * 1024
const MAXIMUM_CHECKPOINTS := 100
## Folders that are never part of a checkpoint: Godot's cache, version control and
## this addon itself.
const SKIPPED_FOLDER_NAMES: Array[String] = [".godot", ".git", ".import"]
## A file changed less than this long ago is always hashed again, because modification
## times only have a resolution of one second.
const RECENT_CHANGE_SECONDS := 2

var _directory: String
var _blob_directory: String
var _addon_directory: String
## File path -> {"modified": int, "hash": String} from the last time we looked.
var _known_files: Dictionary = {}
var _checkpoint_ids: Array[int] = []
var _next_checkpoint_id := 1


func _init(directory: String, addon_directory: String) -> void:
	_directory = directory
	_blob_directory = directory.path_join("blobs")
	_addon_directory = addon_directory
	_delete_folder(ProjectSettings.globalize_path(directory))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_blob_directory))


## Records the current state of every text file. Returns the checkpoint id, or -1 when
## it could not be written.
func take() -> int:
	var file_hashes := _read_current_file_hashes()
	var checkpoint_id := _next_checkpoint_id
	_next_checkpoint_id += 1
	var manifest_file := FileAccess.open(_manifest_path(checkpoint_id), FileAccess.WRITE)
	if manifest_file == null:
		return -1
	manifest_file.store_string(JSON.stringify(file_hashes))
	manifest_file.close()
	_checkpoint_ids.append(checkpoint_id)
	_forget_old_checkpoints()
	return checkpoint_id


func has_checkpoint(checkpoint_id: int) -> bool:
	return _checkpoint_ids.has(checkpoint_id)


## What restoring would change: {"changed": [...], "removed": [...]} (paths).
func preview_restore(checkpoint_id: int) -> Dictionary:
	var saved_hashes := _read_manifest(checkpoint_id)
	var current_hashes := _read_current_file_hashes()
	var changed_paths: Array[String] = []
	var removed_paths: Array[String] = []
	for file_path: String in saved_hashes:
		if current_hashes.get(file_path, "") != saved_hashes[file_path]:
			changed_paths.append(file_path)
	for file_path: String in current_hashes:
		if not saved_hashes.has(file_path):
			removed_paths.append(file_path)
	return {"changed": changed_paths, "removed": removed_paths}


## Puts every text file back as it was at the checkpoint: changed files get their old
## content, files created after it are deleted. Returns the same lists as
## preview_restore, plus "failed" for files that could not be written.
func restore(checkpoint_id: int) -> Dictionary:
	var saved_hashes := _read_manifest(checkpoint_id)
	var planned_changes := preview_restore(checkpoint_id)
	var failed_paths: Array[String] = []
	for file_path: String in planned_changes["changed"]:
		if not _write_blob_to(String(saved_hashes[file_path]), file_path):
			failed_paths.append(file_path)
	for file_path: String in planned_changes["removed"]:
		if DirAccess.remove_absolute(ProjectSettings.globalize_path(file_path)) != OK:
			failed_paths.append(file_path)
	_known_files.clear()
	planned_changes["failed"] = failed_paths
	return planned_changes


## Reads the old content of one file at a checkpoint, or null when it did not exist.
func read_saved_text(checkpoint_id: int, file_path: String) -> Variant:
	var saved_hashes := _read_manifest(checkpoint_id)
	if not saved_hashes.has(file_path):
		return null
	return FileAccess.get_file_as_string(_blob_directory.path_join(String(saved_hashes[file_path])))


func _read_current_file_hashes() -> Dictionary:
	var file_hashes := {}
	var now_unix := int(Time.get_unix_time_from_system())
	for file_path in _list_tracked_files("res://"):
		var modified_unix := int(FileAccess.get_modified_time(file_path))
		var known: Dictionary = _known_files.get(file_path, {})
		var is_recent_change := now_unix - modified_unix <= RECENT_CHANGE_SECONDS
		if not known.is_empty() and int(known["modified"]) == modified_unix and not is_recent_change:
			file_hashes[file_path] = known["hash"]
			continue
		var content_hash := _store_blob(file_path)
		if content_hash == "":
			continue
		_known_files[file_path] = {"modified": modified_unix, "hash": content_hash}
		file_hashes[file_path] = content_hash
	return file_hashes


## Copies the file into the blob folder (once per content) and returns its hash.
func _store_blob(file_path: String) -> String:
	var content := FileAccess.get_file_as_bytes(file_path)
	if content.size() > MAXIMUM_FILE_SIZE_BYTES:
		return ""
	var hashing_context := HashingContext.new()
	hashing_context.start(HashingContext.HASH_SHA256)
	hashing_context.update(content)
	var content_hash := hashing_context.finish().hex_encode()
	var blob_path := _blob_directory.path_join(content_hash)
	if not FileAccess.file_exists(blob_path):
		var blob_file := FileAccess.open(blob_path, FileAccess.WRITE)
		if blob_file == null:
			return ""
		blob_file.store_buffer(content)
		blob_file.close()
	return content_hash


func _write_blob_to(content_hash: String, file_path: String) -> bool:
	var content := FileAccess.get_file_as_bytes(_blob_directory.path_join(content_hash))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(file_path.get_base_dir()))
	var target_file := FileAccess.open(file_path, FileAccess.WRITE)
	if target_file == null:
		return false
	target_file.store_buffer(content)
	target_file.close()
	return true


func _list_tracked_files(folder_path: String) -> Array[String]:
	var file_paths: Array[String] = []
	var folder := DirAccess.open(folder_path)
	if folder == null:
		return file_paths
	folder.include_hidden = false
	for file_name in folder.get_files():
		if TRACKED_EXTENSIONS.has(file_name.get_extension().to_lower()):
			file_paths.append(folder_path.path_join(file_name))
	for subfolder_name in folder.get_directories():
		var subfolder_path := folder_path.path_join(subfolder_name)
		if SKIPPED_FOLDER_NAMES.has(subfolder_name) or subfolder_path == _addon_directory:
			continue
		file_paths.append_array(_list_tracked_files(subfolder_path))
	return file_paths


func _read_manifest(checkpoint_id: int) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_manifest_path(checkpoint_id)))
	return parsed if parsed is Dictionary else {}


func _manifest_path(checkpoint_id: int) -> String:
	return _directory.path_join("checkpoint_%d.json" % checkpoint_id)


func _forget_old_checkpoints() -> void:
	while _checkpoint_ids.size() > MAXIMUM_CHECKPOINTS:
		var oldest_id: int = _checkpoint_ids.pop_front()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_manifest_path(oldest_id)))


static func _delete_folder(absolute_path: String) -> void:
	var folder := DirAccess.open(absolute_path)
	if folder == null:
		return
	folder.include_hidden = true
	for file_name in folder.get_files():
		DirAccess.remove_absolute(absolute_path.path_join(file_name))
	for subfolder_name in folder.get_directories():
		_delete_folder(absolute_path.path_join(subfolder_name))
	DirAccess.remove_absolute(absolute_path)
