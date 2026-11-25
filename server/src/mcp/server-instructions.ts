/**
 * Instructions sent to the AI client when it connects (the MCP "instructions" field).
 * Clients show them to the model next to the tool list, like a short manual.
 * Keep this short: it is read in every conversation. Longer guides live in
 * server/guides and are read on demand with get_guide.
 */
import { PRODUCT_DISPLAY_NAME } from "../product.ts";

export const SERVER_INSTRUCTIONS = `${PRODUCT_DISPLAY_NAME} lets you use the Godot game engine editor like a person: see it, build scenes, write scripts, run and play the game, and read errors.

Start: call get_status. If no editor is running, call launch_editor with the folder that contains project.godot. If a tool cannot reach the editor, call get_status again.

How to work well:
- Look before you change: get_editor_state, get_scene_tree, take_editor_screenshot.
- Do not guess Godot APIs, they change between versions. Use search_docs and get_class_docs; they match the installed version.
- Change in small steps and verify each one: read get_logs (levels ["error","script_error"]) after writing scripts, take a screenshot after visual changes, run and play the game after gameplay changes.
- Prefer specific tools over execute_editor_script: they record undo history so the person can press Ctrl+Z. execute_editor_script is the fallback for anything else.
- Tools come in toolsets. Only some are enabled to save context; call list_toolsets and toggle_toolsets to switch (for example enable "animation" before animating, "play" + "input" before playtesting).
- The project may use C# or GDExtension (Rust, C++) besides GDScript; see get_guide topic "csharp-and-gdextension".
- Paths: "res://" is the project folder. Node paths are relative to the open scene's root, for example "Player/Sprite2D".

For bigger tasks read get_guide topic "workflow" first.`;
