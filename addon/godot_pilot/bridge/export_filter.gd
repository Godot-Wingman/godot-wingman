@tool
extends EditorExportPlugin
## Keeps the addon out of exported games. The addon is an editor tool: it has no use in
## a released game, and leaving it out also means the addon's license never applies to
## the games people make.
##
## The main guard is the empty ".gdignore" file in the addon folder: Godot's file system
## skips the folder, so exports never list its files. (Godot's own GDScript export step
## handles scripts before other export plugins see them, so this filter alone could not
## keep compiled scripts out.) The filter below is a second guard for anything else.

var _addon_directory: String


func _init(addon_directory: String) -> void:
	_addon_directory = addon_directory


func _get_name() -> String:
	return "GodotPilotExportFilter"


func _export_file(path: String, _type: String, _features: PackedStringArray) -> void:
	if path.begins_with(_addon_directory + "/"):
		skip()
