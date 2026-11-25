@tool
extends RefCounted
## Handlers of the "project" toolset: project settings, the input map, autoloads and
## editor plugins, like the Project Settings window.

const PilotError := preload("../utils/pilot_error.gd")
const ValueCodec := preload("../utils/value_codec.gd")
const InputEventText := preload("../utils/input_event_text.gd")

const INPUT_SETTING_PREFIX := "input/"
const AUTOLOAD_SETTING_PREFIX := "autoload/"
const DEFAULT_INPUT_DEADZONE := 0.2

var _context: RefCounted


func _init(context: RefCounted) -> void:
	_context = context


func register_methods(dispatcher: RefCounted) -> void:
	dispatcher.register_method("get_project_settings", _get_project_settings)
	dispatcher.register_method("set_project_settings", _set_project_settings)
	dispatcher.register_method("get_input_map", _get_input_map)
	dispatcher.register_method("set_input_action", _set_input_action)
	dispatcher.register_method("remove_input_action", _remove_input_action)
	dispatcher.register_method("list_autoloads", _list_autoloads)
	dispatcher.register_method("add_autoload", _add_autoload)
	dispatcher.register_method("remove_autoload", _remove_autoload)
	dispatcher.register_method("list_plugins", _list_plugins)
	dispatcher.register_method("set_plugin_enabled", _set_plugin_enabled)


#region Settings

## Without a prefix: only settings that differ from Godot's defaults, which is what
## makes this project special. With a prefix like "display/window": every setting there.
func _get_project_settings(params: Dictionary) -> Variant:
	var prefix := String(params.get("prefix", ""))
	var requested_names: Array = params.get("names", []) if params.get("names") is Array else []
	var settings := {}
	for property in ProjectSettings.get_property_list():
		var setting_name := String(property["name"])
		if int(property["usage"]) & PROPERTY_USAGE_CATEGORY != 0 or not setting_name.contains("/"):
			continue
		if setting_name.begins_with(INPUT_SETTING_PREFIX) and not prefix.begins_with(INPUT_SETTING_PREFIX):
			continue  # The input map has its own tool.
		var is_requested := requested_names.has(setting_name)
		if not requested_names.is_empty() and not is_requested:
			continue
		if prefix != "" and not setting_name.begins_with(prefix):
			continue
		var value: Variant = ProjectSettings.get_setting(setting_name)
		var is_changed: bool = not ProjectSettings.property_can_revert(setting_name) or ProjectSettings.property_get_revert(setting_name) != value
		if prefix == "" and requested_names.is_empty() and not is_changed:
			continue
		settings[setting_name] = ValueCodec.to_json_value(value)
	var result := {"settings": settings}
	if prefix == "" and requested_names.is_empty():
		result["note"] = "Only settings changed from the defaults. Pass a prefix such as \"display/window\" to see all settings of a section."
	return result


func _set_project_settings(params: Dictionary) -> Variant:
	var new_settings: Variant = params.get("settings", {})
	if not new_settings is Dictionary or new_settings.is_empty():
		return PilotError.new("NO_SETTINGS", "settings must be an object like {\"display/window/size/viewport_width\": 1280}.")
	var changed := {}
	for setting_name in new_settings:
		var current_value: Variant = ProjectSettings.get_setting(setting_name) if ProjectSettings.has_setting(setting_name) else null
		var conversion := ValueCodec.from_json_value(new_settings[setting_name], typeof(current_value) if current_value != null else TYPE_NIL)
		if not conversion["ok"]:
			return PilotError.new("INVALID_VALUE", "%s: %s" % [setting_name, conversion["error"]])
		ProjectSettings.set_setting(setting_name, conversion["value"])
		changed[setting_name] = ValueCodec.to_json_value(conversion["value"])
	var save_error := ProjectSettings.save()
	if save_error != OK:
		return PilotError.new("SAVE_FAILED", "Could not save project.godot: %s." % error_string(save_error))
	return {"changed": changed, "note": "Saved to project.godot. Some settings (window size, rendering) apply the next time the game starts."}

#endregion


#region Input map

func _get_input_map(params: Dictionary) -> Dictionary:
	var include_builtin := bool(params.get("include_builtin", false))
	var actions := {}
	for property in ProjectSettings.get_property_list():
		var setting_name := String(property["name"])
		if not setting_name.begins_with(INPUT_SETTING_PREFIX):
			continue
		var action_name := setting_name.trim_prefix(INPUT_SETTING_PREFIX)
		if action_name.begins_with("ui_") and not include_builtin:
			continue
		var action_setting: Dictionary = ProjectSettings.get_setting(setting_name, {})
		var event_descriptions: Array[String] = []
		for event in action_setting.get("events", []):
			event_descriptions.append(InputEventText.describe(event))
		actions[action_name] = {"events": event_descriptions, "deadzone": action_setting.get("deadzone", DEFAULT_INPUT_DEADZONE)}
	var result := {"actions": actions}
	if not include_builtin:
		result["note"] = "Built-in ui_* actions (ui_left, ui_accept...) are hidden; include_builtin: true shows them."
	return result


## Creates or replaces an action, for example "jump" with ["key:Space", "joy_button:a"].
func _set_input_action(params: Dictionary) -> Variant:
	var action_name := String(params.get("name", "")).strip_edges()
	if action_name == "":
		return PilotError.new("MISSING_NAME", "The action needs a name, for example \"jump\".")
	var events: Array[InputEvent] = []
	for description in params.get("events", []):
		var parsed: Variant = InputEventText.parse(String(description))
		if parsed is String:
			return PilotError.new("INVALID_EVENT", parsed)
		events.append(parsed)

	ProjectSettings.set_setting(INPUT_SETTING_PREFIX + action_name, {
		"deadzone": float(params.get("deadzone", DEFAULT_INPUT_DEADZONE)),
		"events": events,
	})
	var save_error := ProjectSettings.save()
	if save_error != OK:
		return PilotError.new("SAVE_FAILED", "Could not save project.godot: %s." % error_string(save_error))
	return {"action": action_name, "events": events.map(func(event: InputEvent) -> String: return InputEventText.describe(event))}


func _remove_input_action(params: Dictionary) -> Variant:
	var setting_name := INPUT_SETTING_PREFIX + String(params.get("name", ""))
	if not ProjectSettings.has_setting(setting_name):
		return PilotError.new("ACTION_NOT_FOUND", "No input action named '%s'." % params.get("name", ""))
	ProjectSettings.clear(setting_name)
	ProjectSettings.save()
	return {"removed": params.get("name")}

#endregion


#region Autoloads and plugins

func _list_autoloads(_params: Dictionary) -> Dictionary:
	var autoloads := []
	for property in ProjectSettings.get_property_list():
		var setting_name := String(property["name"])
		if not setting_name.begins_with(AUTOLOAD_SETTING_PREFIX):
			continue
		var stored_path := String(ProjectSettings.get_setting(setting_name))
		# A leading "*" means "enabled as a global singleton".
		autoloads.append({
			"name": setting_name.trim_prefix(AUTOLOAD_SETTING_PREFIX),
			"path": stored_path.trim_prefix("*"),
			"global_name": stored_path.begins_with("*"),
		})
	return {"autoloads": autoloads}


func _add_autoload(params: Dictionary) -> Variant:
	var autoload_name := String(params.get("name", ""))
	var autoload_path := String(params.get("path", ""))
	if autoload_name == "" or not autoload_name.is_valid_identifier():
		return PilotError.new("INVALID_NAME", "'%s' is not a valid autoload name. Use a name like GameState." % autoload_name)
	if not ResourceLoader.exists(autoload_path):
		return PilotError.new("FILE_NOT_FOUND", "No script or scene at '%s'." % autoload_path)
	_context.plugin.add_autoload_singleton(autoload_name, autoload_path)
	return {"added": autoload_name, "path": autoload_path, "note": "Available in every scene as %s when the game runs." % autoload_name}


func _remove_autoload(params: Dictionary) -> Variant:
	var autoload_name := String(params.get("name", ""))
	if not ProjectSettings.has_setting(AUTOLOAD_SETTING_PREFIX + autoload_name):
		return PilotError.new("AUTOLOAD_NOT_FOUND", "No autoload named '%s'." % autoload_name)
	_context.plugin.remove_autoload_singleton(autoload_name)
	return {"removed": autoload_name}


func _list_plugins(_params: Dictionary) -> Dictionary:
	var plugins := []
	var addons_directory := DirAccess.open("res://addons")
	if addons_directory == null:
		return {"plugins": plugins}
	for folder_name in addons_directory.get_directories():
		var plugin_config_path := "res://addons/%s/plugin.cfg" % folder_name
		if not FileAccess.file_exists(plugin_config_path):
			continue
		var plugin_config := ConfigFile.new()
		plugin_config.load(plugin_config_path)
		plugins.append({
			"folder": folder_name,
			"name": plugin_config.get_value("plugin", "name", folder_name),
			"version": plugin_config.get_value("plugin", "version", ""),
			"enabled": EditorInterface.is_plugin_enabled(folder_name),
		})
	return {"plugins": plugins}


func _set_plugin_enabled(params: Dictionary) -> Variant:
	var folder_name := String(params.get("folder", ""))
	if folder_name == _context.addon_directory.get_file():
		return PilotError.new("CANNOT_DISABLE_SELF", "Godot Pilot cannot turn itself off; the connection would be lost.")
	if not FileAccess.file_exists("res://addons/%s/plugin.cfg" % folder_name):
		return PilotError.new("PLUGIN_NOT_FOUND", "No plugin in res://addons/%s." % folder_name, "Use list_plugins to see the folder names.")
	EditorInterface.set_plugin_enabled(folder_name, bool(params.get("enabled", true)))
	return {"plugin": folder_name, "enabled": EditorInterface.is_plugin_enabled(folder_name)}

#endregion
