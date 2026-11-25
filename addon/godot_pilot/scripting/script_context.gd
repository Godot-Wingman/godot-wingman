@tool
extends RefCounted
## Base class of code sent with the execute_editor_script tool.
##
## The AI's code becomes the body of `run()` in a script that extends this class,
## so these helpers are available in that code without any setup:
##
##   editor      - EditorInterface (open scenes, selection, file system...)
##   scene_root  - root node of the scene open in the editor (may be null)
##   undo_redo   - EditorUndoRedoManager, so changes can be undone with Ctrl+Z
##   tree        - the editor's SceneTree, for example `await tree.process_frame`
##   output(x)   - adds a line to the result shown to the AI (print() works too)
##   node(path)  - finds a node in the edited scene by its path, or null

var editor: EditorInterface
var scene_root: Node
var undo_redo: EditorUndoRedoManager
var tree: SceneTree

var _output_lines: PackedStringArray = []


func output(value: Variant) -> void:
	_output_lines.append(str(value))


func node(node_path: String) -> Node:
	if scene_root == null:
		return null
	if node_path == "" or node_path == ".":
		return scene_root
	return scene_root.get_node_or_null(NodePath(node_path))


func get_output_lines() -> PackedStringArray:
	return _output_lines
