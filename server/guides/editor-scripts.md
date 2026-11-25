# Writing code for execute_editor_script

Your code runs inside the Godot editor as the body of `func run():`.

## Ready-made helpers

| Name            | What it is                                                            |
| --------------- | --------------------------------------------------------------------- |
| `editor`        | `EditorInterface`: open/save scenes, selection, file system, settings |
| `scene_root`    | Root node of the scene open in the editor (can be null)               |
| `undo_redo`     | `EditorUndoRedoManager`: changes the person can undo with Ctrl+Z      |
| `tree`          | The editor's `SceneTree` (`await tree.process_frame` waits one frame) |
| `node("Path")`  | A node of the open scene by its path, or null                         |
| `output(value)` | Adds a line to the result                                             |

`return` a value to receive it. `print()` output and errors come back too.

## Rules

- Indent with tabs. Line numbers in errors refer to your code.
- To define helper functions or inner classes, write `func run():` yourself and put the other functions next to it.
- A node only becomes part of the saved scene when its `owner` is `scene_root`. Set it for every new node, also for children of new nodes.
- Use `undo_redo` for changes to the scene, so they can be undone:

```gdscript
var sprite := Sprite2D.new()
sprite.name = "Coin"
sprite.texture = load("res://coin.png")
undo_redo.create_action("Add coin")
undo_redo.add_do_method(scene_root, "add_child", sprite)
undo_redo.add_do_property(sprite, "owner", scene_root)
undo_redo.add_do_reference(sprite)
undo_redo.add_undo_method(scene_root, "remove_child", sprite)
undo_redo.commit_action()
```

- Changing a property with undo:

```gdscript
var player := node("Player")
undo_redo.create_action("Move player")
undo_redo.add_do_property(player, "position", Vector2(200, 300))
undo_redo.add_undo_property(player, "position", player.position)
undo_redo.commit_action()
```

- Save with `editor.save_scene()`.
- Never write loops that might not end: the editor freezes until your code returns.
- Files: after creating files with `FileAccess`, call `editor.get_resource_filesystem().scan()` so the editor sees them.
