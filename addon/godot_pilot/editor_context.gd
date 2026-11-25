@tool
extends RefCounted
## Shared objects and helpers that every request handler needs.
##
## One instance is created by the plugin and passed to each handler group, so the
## handlers do not need to know how the plugin is put together.

const PilotError := preload("utils/pilot_error.gd")
const ValueCodec := preload("utils/value_codec.gd")

var plugin: EditorPlugin
## Collects editor output. Null on Godot versions older than 4.5 (no Logger class).
var log_capture: Object
var addon_version: String
## Folder of the addon, for example "res://addons/godot_pilot".
var addon_directory: String


func _init(owning_plugin: EditorPlugin, captured_logs: Object, version: String, directory: String) -> void:
	plugin = owning_plugin
	log_capture = captured_logs
	addon_version = version
	addon_directory = directory


func get_edited_scene_root() -> Node:
	return EditorInterface.get_edited_scene_root()


func get_undo_redo() -> EditorUndoRedoManager:
	return EditorInterface.get_editor_undo_redo()


func get_scene_tree() -> SceneTree:
	return plugin.get_tree()


## Finds a node in the edited scene. `node_path` is relative to the scene root;
## "." or "" means the root itself. Returns a PilotError when the node is missing.
func find_node_in_edited_scene(node_path: String) -> Variant:
	var scene_root := get_edited_scene_root()
	if scene_root == null:
		return PilotError.new("NO_OPEN_SCENE", "No scene is open in the editor.", "Open a scene first.")
	if node_path == "" or node_path == "." or node_path == scene_root.name:
		return scene_root
	var found_node := scene_root.get_node_or_null(NodePath(node_path.trim_prefix("./")))
	if found_node == null:
		return PilotError.new(
			"NODE_NOT_FOUND",
			"No node at '%s' in the scene '%s'." % [node_path, scene_root.scene_file_path],
			"Paths are relative to the scene root, for example \"Player/Sprite2D\". Use get_scene_tree to see the paths."
		)
	return found_node


## Calls an EditorInterface method that may not exist in older Godot versions.
## Calling it directly would stop the whole addon from compiling there.
func call_editor_interface(method_name: String, arguments: Array = [], fallback: Variant = null) -> Variant:
	if EditorInterface.has_method(method_name):
		return EditorInterface.callv(method_name, arguments)
	return fallback


func describe_node_path(node: Node) -> String:
	return ValueCodec.describe_node_path(node, get_edited_scene_root())


## Id of the next log entry, or 0 when logs are not captured.
func get_next_log_id() -> int:
	if log_capture == null:
		return 0
	return log_capture.get_next_entry_id()


## Entries logged since `from_id`, filtered by level. Empty when logs are not captured.
func get_logs_since(from_id: int, levels: Array = []) -> Array:
	if log_capture == null:
		return []
	return log_capture.get_entries(from_id, levels, "", 0)
