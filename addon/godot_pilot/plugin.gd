@tool
extends EditorPlugin
## Entry point of the Godot Pilot addon.
##
## When the editor loads the plugin, it:
## 1. starts capturing the editor's output (Godot 4.5+),
## 2. starts a WebSocket server on 127.0.0.1 with a random secret token,
## 3. writes a registry file so the MCP server can find this editor.
## Everything is undone when the plugin is disabled or the editor closes.
##
## The addon only lives in the editor: nothing from it runs in exported games.

const RequestDispatcher := preload("bridge/request_dispatcher.gd")
const BridgeServer := preload("bridge/bridge_server.gd")
const EditorRegistryFile := preload("bridge/editor_registry_file.gd")
const EditorContext := preload("editor_context.gd")

## Every group of request handlers. A group is a script with `register_methods(dispatcher)`.
const HANDLER_GROUP_SCRIPTS: Array[Script] = [
	preload("handlers/core_handlers.gd"),
	preload("handlers/scene_handlers.gd"),
	preload("handlers/inspector_handlers.gd"),
	preload("handlers/script_handlers.gd"),
	preload("handlers/project_handlers.gd"),
	preload("handlers/signal_handlers.gd"),
	preload("handlers/resource_handlers.gd"),
	preload("handlers/filesystem_handlers.gd"),
	preload("handlers/viewport_handlers.gd"),
]

const TOKEN_BYTE_COUNT := 24

var _log_capture: Object
var _handler_groups: Array[RefCounted] = []
var _bridge_server: BridgeServer
var _registry_file: EditorRegistryFile


func _enter_tree() -> void:
	var addon_directory: String = get_script().resource_path.get_base_dir()
	_log_capture = _start_log_capture(addon_directory)

	var context := EditorContext.new(self, _log_capture, _read_addon_version(addon_directory), addon_directory)
	var dispatcher := RequestDispatcher.new()
	for handler_group_script in HANDLER_GROUP_SCRIPTS:
		var handler_group: RefCounted = handler_group_script.new(context)
		handler_group.register_methods(dispatcher)
		# A Callable does not keep its object alive, so we must hold the reference.
		_handler_groups.append(handler_group)

	var token := Crypto.new().generate_random_bytes(TOKEN_BYTE_COUNT).hex_encode()
	var editor_information := _collect_editor_information(context.addon_version)

	_bridge_server = BridgeServer.new(dispatcher, token, editor_information)
	if _bridge_server.start_listening() != OK:
		push_error("Godot Pilot: could not find a free port between %d and %d." % [BridgeServer.FIRST_PORT, BridgeServer.LAST_PORT])
		_bridge_server = null
		return
	add_child(_bridge_server)
	_bridge_server.client_count_changed.connect(_on_client_count_changed)

	var registry_information := editor_information.duplicate()
	registry_information["port"] = _bridge_server.port
	registry_information["token"] = token
	_registry_file = EditorRegistryFile.new()
	var registry_error := _registry_file.write(registry_information)
	if registry_error != OK:
		push_error("Godot Pilot: could not write the registry file (%s)." % error_string(registry_error))

	print("Godot Pilot %s: ready for AI connections on port %d." % [context.addon_version, _bridge_server.port])


func _exit_tree() -> void:
	if _registry_file != null:
		_registry_file.remove()
		_registry_file = null
	if _bridge_server != null:
		_bridge_server.queue_free()
		_bridge_server = null
	_handler_groups.clear()
	if _log_capture != null and OS.has_method("remove_logger"):
		OS.call("remove_logger", _log_capture)
	_log_capture = null


## The Logger class only exists since Godot 4.5. The capture script extends it, so we
## load that script only when the class exists; older versions simply have no logs.
func _start_log_capture(addon_directory: String) -> Object:
	if not ClassDB.class_exists("Logger") or not OS.has_method("add_logger"):
		return null
	var log_capture_script: Script = load(addon_directory.path_join("logging/log_capture.gd"))
	var log_capture: Object = log_capture_script.new()
	OS.call("add_logger", log_capture)
	return log_capture


func _read_addon_version(addon_directory: String) -> String:
	var plugin_config := ConfigFile.new()
	if plugin_config.load(addon_directory.path_join("plugin.cfg")) != OK:
		return "unknown"
	return String(plugin_config.get_value("plugin", "version", "unknown"))


func _collect_editor_information(addon_version: String) -> Dictionary:
	return {
		"process_id": OS.get_process_id(),
		"project_path": ProjectSettings.globalize_path("res://"),
		"project_name": String(ProjectSettings.get_setting("application/config/name", "")),
		"godot_version": Engine.get_version_info().string,
		"godot_executable": OS.get_executable_path(),
		"addon_version": addon_version,
		"headless": DisplayServer.get_name() == "headless",
		"started_at_unix": int(Time.get_unix_time_from_system()),
	}


func _on_client_count_changed(authenticated_client_count: int) -> void:
	if authenticated_client_count > 0:
		print("Godot Pilot: %d AI connection(s) active." % authenticated_client_count)
	else:
		print("Godot Pilot: no AI connected.")
