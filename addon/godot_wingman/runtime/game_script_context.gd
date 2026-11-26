extends RefCounted
## Base class of code sent with the execute_game_script tool. The code runs inside the
## running game as the body of `run()`, with these helpers:
##
##   tree        - the game's SceneTree
##   root        - the root Window (autoloads are its children, e.g. root.get_node("GameState"))
##   scene       - the current scene (tree.current_scene)
##   node(path)  - a node by path, relative to the current scene ("/root/..." for absolute)
##   output(x)   - adds a line to the result (print() works too)

var tree: SceneTree
var root: Window
var scene: Node

var _output_lines: PackedStringArray = []


func output(value: Variant) -> void:
	_output_lines.append(str(value))


func node(node_path: String) -> Node:
	if node_path.begins_with("/"):
		return root.get_node_or_null(NodePath(node_path))
	if scene == null:
		return null
	if node_path == "" or node_path == ".":
		return scene
	return scene.get_node_or_null(NodePath(node_path))


func get_output_lines() -> PackedStringArray:
	return _output_lines
