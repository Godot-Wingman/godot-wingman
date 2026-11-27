/**
 * Instructions sent to the AI client when it connects (the MCP "instructions" field).
 * Clients show them to the model next to the tool list, like a short manual.
 * Keep this short: it is read in every conversation. Longer guides live in
 * server/guides and are read on demand with get_guide.
 */
import { PRODUCT_DISPLAY_NAME } from "../product.ts";

export const SERVER_INSTRUCTIONS = `${PRODUCT_DISPLAY_NAME} lets you use the Godot game engine editor like a person: see it, build scenes, write scripts, run and play the game, and read errors.

Start: call get_status. If no editor is running, call launch_editor with the folder that contains project.godot. For a new game without a project yet, call create_project. If a tool cannot reach the editor, call get_status again.

How to work well:
- Look before you change: get_editor_state, get_scene_tree, take_editor_screenshot.
- Do not guess Godot APIs, they change between versions. Use search_docs and get_class_docs; they match the installed version.
- Change in small steps and verify each one: read get_logs (levels ["error","script_error"]) after writing scripts, take a screenshot after visual changes, run and play the game after gameplay changes.
- Prefer specific tools over execute_editor_script: they record undo history so the person can press Ctrl+Z. execute_editor_script is the fallback for anything else.
- Tools come in toolsets. Only some are enabled to save context; call list_toolsets and toggle_toolsets to switch (for example enable "animation" before animating, "tilemap" for levels, "ui" for menus and HUDs, "3d" for 3D scenes, "play" + "input" before playtesting, "export" to build the game).
- The project may use C# or GDExtension (Rust, C++) besides GDScript; see get_guide topic "csharp-and-gdextension".
- The person sees every change you make in the Godot Wingman panel and may have to approve it. If a change is denied or blocked, do not retry it: explain what you want to do and ask.
- Tool results may end with "News from the Godot editor": the person pressed Ctrl+Z, changed things by hand, went back to an earlier step, or another AI sent a message. Take it into account: look at the current state again before you change the same things. When other AIs work in the same editor, say what you are about to change with tell_other_ais.
- The person can write to you in the chat of the Godot Wingman panel. Answer those messages with reply_to_person. When the person asks you to listen to them in Godot, keep calling wait_for_person_message.
- Paths: "res://" is the project folder. Node paths are relative to the open scene's root, for example "Player/Sprite2D".

For bigger tasks read get_guide topic "workflow" first.`;
