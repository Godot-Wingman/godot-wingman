/**
 * Core tools that work inside the running editor: its state, running GDScript,
 * reading the Output panel and taking screenshots.
 */
import { z } from "zod";
import { defineTool, forwardToEditor, imageResult } from "../../mcp/tool-definition.ts";

const LOG_LEVELS = ["info", "warning", "error", "script_error", "shader_error"] as const;

export const getEditorStateTool = defineTool({
  name: "get_editor_state",
  title: "Get editor state",
  description:
    "Returns what is going on in the editor: the open scene and all open scenes, unsaved scenes, selected nodes, whether the game is running, the main scene, the Godot version, and whether C# and GDExtensions are available.",
  inputShape: {},
  access: "read",
  run: (_input, context) => forwardToEditor(context, "get_editor_state"),
});

export const executeEditorScriptTool = defineTool({
  name: "execute_editor_script",
  title: "Run GDScript in the editor",
  description: [
    "Runs GDScript inside the Godot editor and returns the result. This can do anything the editor can do; use it when no specific tool fits.",
    "Your code becomes the body of `func run():` (or write `func run():` yourself, plus other functions). Indent blocks with tabs. `return` a value to get it back; `print()` output and errors are returned too.",
    'Available without setup: `editor` (EditorInterface), `scene_root` (root of the open scene), `undo_redo` (EditorUndoRedoManager), `tree` (SceneTree, e.g. `await tree.process_frame`), `node("Path/To/Node")`, `output(value)`.',
    "Prefer undo_redo for scene changes so the person can press Ctrl+Z. Nodes added to the scene need `owner = scene_root` to be saved.",
    'Example: `var label := Label.new()\\nlabel.text = "Hi"\\nundo_redo.create_action("Add label")\\nundo_redo.add_do_method(scene_root, "add_child", label)\\nundo_redo.add_do_property(label, "owner", scene_root)\\nundo_redo.add_do_reference(label)\\nundo_redo.add_undo_method(scene_root, "remove_child", label)\\nundo_redo.commit_action()\\nreturn label.get_path()`',
    "Never write endless loops: the editor freezes until the code returns.",
  ].join("\n"),
  inputShape: {
    code: z.string().describe("GDScript code to run."),
    timeout_seconds: z
      .number()
      .min(1)
      .max(600)
      .optional()
      .describe("How long to wait for the result (for code that awaits). Default: 60."),
  },
  access: "write",
  run: (input, context) =>
    forwardToEditor(context, "execute_script", { code: input.code }, (input.timeout_seconds ?? 60) * 1000),
});

export const getLogsTool = defineTool({
  name: "get_logs",
  title: "Read editor output and errors",
  description:
    'Reads the editor\'s Output panel: printed messages, warnings and errors with file, line and stack trace. Use levels ["error", "script_error"] to see only problems. Every entry has an id; pass from_id = the returned next_id later to get only new entries. Needs Godot 4.5 or newer.',
  inputShape: {
    levels: z.array(z.enum(LOG_LEVELS)).optional().describe("Only these kinds of entries. Default: all."),
    search: z.string().optional().describe("Only entries containing this text (case-insensitive)."),
    from_id: z.number().int().min(0).optional().describe("Only entries with this id or newer."),
    limit: z
      .number()
      .int()
      .min(1)
      .max(1000)
      .optional()
      .describe("Maximum number of entries, newest kept. Default: 100."),
  },
  access: "read",
  run: (input, context) => forwardToEditor(context, "get_logs", input),
});

export const takeEditorScreenshotTool = defineTool({
  name: "take_editor_screenshot",
  title: "Screenshot the editor",
  description:
    'Takes a picture of the editor so you can see what a person would see. view "editor" (default) captures the whole window, "2d" or "3d" only the scene viewport. Smaller max_size saves tokens; 1280 is readable, 768 is enough for layout checks.',
  inputShape: {
    view: z.enum(["editor", "2d", "3d"]).optional().describe('What to capture. Default: "editor".'),
    max_size: z
      .number()
      .int()
      .min(128)
      .max(4096)
      .optional()
      .describe("Longest side in pixels. Default: 1280."),
    format: z
      .enum(["jpeg", "png", "webp"])
      .optional()
      .describe("Image format. jpeg is smallest. Default: jpeg."),
  },
  access: "read",
  async run(input, context) {
    const screenshot = await context.editors.request<{
      mime_type: string;
      data_base64: string;
      width: number;
      height: number;
    }>("take_screenshot", input);
    return imageResult(
      screenshot.data_base64,
      screenshot.mime_type,
      `${input.view ?? "editor"} view, ${screenshot.width}x${screenshot.height}`,
    );
  },
});
