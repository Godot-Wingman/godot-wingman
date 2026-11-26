# Working in Godot with Godot Wingman

Work the way an experienced Godot developer would: look first, change in small steps, check every step.

## 1. Orient yourself

- `get_status`: which editor is connected, which toolsets are on.
- `get_editor_state`: the open scene, the selection, whether the game is running.
- `get_scene_tree` (scene toolset): the structure of the open scene.
- `take_editor_screenshot`: what the person sees. Use it after visual changes.

## 2. Know the API before you use it

Godot changes between versions. Do not guess method names.

- `search_docs` finds the right class or method ("raycast", "tween").
- `get_class_docs` shows the exact signatures of the installed version.

## 3. Change in small steps

- Prefer the specific tools (add_node, set_properties, create_script...). They use the editor's undo history, so the person can press Ctrl+Z.
- When no tool fits, use `execute_editor_script` and go through `undo_redo` for scene changes.
- Save scenes when a step is complete.

## 4. Verify every step

- After writing a script: check `get_logs` with levels ["error", "script_error"] for parse errors.
- After visual changes: take a screenshot.
- After gameplay changes: run the game and play it (play and input toolsets), then read the errors.
- Levels: `get_tiles` draws a TileMapLayer as text, cheaper than a screenshot.
- Menus and HUDs: `get_ui_layout` lists controls with zero size or off screen.
- 3D placement: `get_bounds` gives sizes in meters; `render_view` shows the result.
- Animations: `preview_animation` returns the animated values at a moment.

## Building blocks worth knowing

- One call builds a lot: `build_ui` (whole menu), `set_tiles` with rectangles (floors, walls), `create_animation` with all tracks and keys, `add_mesh` with `body` (mesh + collision), `setup_environment` (sky + sun).
- Values accept natural forms everywhere: `[x, y]`, `"#ff8800"`, `"res://..."`, a class name for a new resource, or `{"type": "StyleBoxFlat", "properties": {...}}` for a new resource with settings.
- Finished game: `list_export_presets`, `add_export_preset`, then `export_project`.

## 5. Keep the context small

- Turn on only the toolsets you need (`toggle_toolsets`), turn them off when done.
- Screenshots cost many tokens: use `max_size` 768 for layout checks.
- Ask for logs with `from_id` to get only new entries.

## Godot basics in one minute

- A game is made of **scenes** (`.tscn` files). A scene is a tree of **nodes**.
- Every node has a type (class) like `Sprite2D`, `CharacterBody2D`, `Label`, and **properties** you see in the inspector.
- Behaviour comes from **scripts** attached to nodes (GDScript `.gd`, or C# `.cs`).
- Nodes talk through **signals** (for example a Button's `pressed`).
- A scene can be used inside another scene (an **instance**), like a prefab.
- `res://` is the project folder. `user://` is the player's save folder.
