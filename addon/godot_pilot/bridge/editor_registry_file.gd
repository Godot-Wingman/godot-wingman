@tool
extends RefCounted
## Writes a small JSON file that tells the MCP server this editor is running.
##
## The file contains the port and the secret token of the bridge, so only programs
## run by the same operating-system user can find and connect to this editor.
## The file is deleted when the editor closes. Files left behind by a crashed editor
## are cleaned up by the MCP server, which checks whether the process still exists.

const PRODUCT_FOLDER_NAME := "godot-pilot"
## Lets tests and advanced users move the folder somewhere else.
const HOME_OVERRIDE_ENVIRONMENT_VARIABLE := "GODOT_PILOT_HOME"

var _registry_file_path: String = ""


static func get_product_home_directory() -> String:
	var override_directory := OS.get_environment(HOME_OVERRIDE_ENVIRONMENT_VARIABLE)
	if override_directory != "":
		return override_directory
	return OS.get_data_dir().path_join(PRODUCT_FOLDER_NAME)


static func get_registry_directory() -> String:
	return get_product_home_directory().path_join("editors")


func write(editor_information: Dictionary) -> Error:
	var registry_directory := get_registry_directory()
	var directory_error := DirAccess.make_dir_recursive_absolute(registry_directory)
	if directory_error != OK:
		return directory_error

	_registry_file_path = registry_directory.path_join("%d.json" % OS.get_process_id())
	var registry_file := FileAccess.open(_registry_file_path, FileAccess.WRITE)
	if registry_file == null:
		return FileAccess.get_open_error()
	registry_file.store_string(JSON.stringify(editor_information, "  "))
	registry_file.close()
	return OK


func remove() -> void:
	if _registry_file_path != "" and FileAccess.file_exists(_registry_file_path):
		DirAccess.remove_absolute(_registry_file_path)
	_registry_file_path = ""
