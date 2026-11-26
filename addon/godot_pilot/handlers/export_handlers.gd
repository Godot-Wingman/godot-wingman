@tool
extends RefCounted
## Handlers of the "export" toolset that need the editor: reading and adding export
## presets (export_presets.cfg) and checking that export templates are installed.
## The export itself runs in a separate Godot process started by the MCP server.

const PilotError := preload("../utils/pilot_error.gd")

const EXPORT_PRESETS_PATH := "res://export_presets.cfg"
## Platform names exactly as Godot writes them in export_presets.cfg, with the usual
## file extension of their export.
const PLATFORM_EXTENSIONS := {
	"Windows Desktop": "exe",
	"Linux": "x86_64",
	"macOS": "zip",
	"Web": "html",
	"Android": "apk",
	"iOS": "ipa",
}

var _context: RefCounted


func _init(context: RefCounted) -> void:
	_context = context


func register_methods(dispatcher: RefCounted) -> void:
	dispatcher.register_method("list_export_presets", _list_export_presets)
	dispatcher.register_method("add_export_preset", _add_export_preset)
	dispatcher.register_method("save_all_scenes", _save_all_scenes)


func _list_export_presets(_params: Dictionary) -> Variant:
	var presets: Array[Dictionary] = []
	var config := ConfigFile.new()
	if config.load(EXPORT_PRESETS_PATH) == OK:
		for section in _preset_sections(config):
			presets.append({
				"name": String(config.get_value(section, "name", "")),
				"platform": String(config.get_value(section, "platform", "")),
				"export_path": String(config.get_value(section, "export_path", "")),
				"runnable": bool(config.get_value(section, "runnable", false)),
			})
	var templates := _describe_export_templates()
	var result := {"presets": presets, "export_templates": templates}
	if presets.is_empty():
		result["hint"] = "No export presets yet. Add one with add_export_preset (or in Project > Export)."
	if not templates["installed"]:
		result["templates_hint"] = "Exporting needs the export templates for this exact Godot version. Install them in the editor: Editor > Manage Export Templates > Download and Install."
	return result


func _add_export_preset(params: Dictionary) -> Variant:
	var platform := String(params.get("platform", ""))
	if not PLATFORM_EXTENSIONS.has(platform):
		return PilotError.new("INVALID_PLATFORM", "Unknown platform '%s'." % platform, "Use one of: %s." % ", ".join(PLATFORM_EXTENSIONS.keys()))
	var preset_name := String(params.get("name", platform))
	var config := ConfigFile.new()
	config.load(EXPORT_PRESETS_PATH)
	var sections := _preset_sections(config)
	for section in sections:
		if String(config.get_value(section, "name", "")) == preset_name:
			return PilotError.new("ALREADY_EXISTS", "There already is an export preset named '%s'." % preset_name)
	var export_path := String(params.get("export_path", "build/%s/%s.%s" % [platform.to_snake_case(), _safe_file_name(), PLATFORM_EXTENSIONS[platform]]))
	if export_path.begins_with("res://"):
		return PilotError.new("INVALID_PATH", "export_path is relative to the project folder, for example \"build/windows/game.exe\"; do not use res://.")

	var section := "preset.%d" % sections.size()
	config.set_value(section, "name", preset_name)
	config.set_value(section, "platform", platform)
	config.set_value(section, "runnable", bool(params.get("runnable", true)))
	config.set_value(section, "dedicated_server", false)
	config.set_value(section, "custom_features", "")
	config.set_value(section, "export_filter", "all_resources")
	config.set_value(section, "include_filter", "")
	config.set_value(section, "exclude_filter", "")
	config.set_value(section, "export_path", export_path)
	# No ".options" section: the platform uses its default value for every option.
	var save_error := config.save(ProjectSettings.globalize_path(EXPORT_PRESETS_PATH))
	if save_error != OK:
		return PilotError.new("SAVE_FAILED", "Could not write export_presets.cfg: %s." % error_string(save_error))
	return {
		"added": preset_name,
		"platform": platform,
		"export_path": export_path,
		"note": "The editor's Export window shows the new preset after the editor restarts; export_project can use it now.",
	}


func _preset_sections(config: ConfigFile) -> Array[String]:
	var sections: Array[String] = []
	for section in config.get_sections():
		if section.begins_with("preset.") and not section.ends_with(".options"):
			sections.append(section)
	return sections


## Templates live in the editor's data folder, in a folder named after the exact version
## ("4.7.2.stable", or "4.7.stable" when there is no patch number; ".mono" for .NET).
func _describe_export_templates() -> Dictionary:
	var version := Engine.get_version_info()
	var version_folder := "%d.%d" % [version["major"], version["minor"]]
	if int(version["patch"]) > 0:
		version_folder += ".%d" % version["patch"]
	version_folder += ".%s" % version["status"]
	if ClassDB.class_exists("CSharpScript"):
		version_folder += ".mono"
	var templates_folder := EditorInterface.get_editor_paths().get_data_dir().path_join("export_templates").path_join(version_folder)
	var installed := DirAccess.dir_exists_absolute(templates_folder)
	var description := {"installed": installed, "folder": templates_folder}
	if installed:
		description["files"] = Array(DirAccess.get_files_at(templates_folder))
	return description


func _safe_file_name() -> String:
	var project_name := String(ProjectSettings.get_setting("application/config/name", "game")).to_snake_case()
	var safe_name := ""
	for character in project_name:
		safe_name += character if character.is_valid_identifier() or character.is_valid_int() else "_"
	return safe_name if safe_name != "" else "game"


## Exports read the files on disk, so unsaved changes in the editor must be saved first.
func _save_all_scenes(_params: Dictionary) -> Variant:
	EditorInterface.save_all_scenes()
	return {"saved": true}
