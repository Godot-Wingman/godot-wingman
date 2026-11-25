@tool
extends EditorExportPlugin
## Keeps the addon out of exported games. The addon is an editor tool: it has no use in
## a released game, and leaving it out also means the addon's license never applies to
## the games people make.

var _addon_directory: String


func _init(addon_directory: String) -> void:
	_addon_directory = addon_directory


func _get_name() -> String:
	return "GodotPilotExportFilter"


func _export_file(path: String, _type: String, _features: PackedStringArray) -> void:
	if path.begins_with(_addon_directory + "/"):
		skip()
