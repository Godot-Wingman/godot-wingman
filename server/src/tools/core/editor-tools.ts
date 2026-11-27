/**
 * Core tools that work inside the running editor: its state, running GDScript,
 * reading the Output panel, taking screenshots, messages to other AIs, and the chat
 * with the person in the Godot Wingman panel.
 */
import { z } from "zod";
import { defineTool, forwardToEditor, imageResult, textResult } from "../../mcp/tool-definition.ts";

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

export const tellOtherAisTool = defineTool({
  name: "tell_other_ais",
  title: "Tell the other AIs",
  description: [
    "Sends a short message to the other AIs connected to this Godot editor (for example Claude Code and Cursor working on the same game), so you do not change the same things at the same time or undo each other's work.",
    "They get it at the end of their next tool result. An AI that connects later gets the recent messages too. The person sees the messages in the Godot Wingman panel.",
    "Use it before larger changes when other AIs are connected (you are told when they are), and when you finish: what you change, which files or nodes, and what the others should leave alone.",
    'Example: "I am rewriting res://player/player.gd and the Player scene. Please do not edit them until I say I am done."',
  ].join("\n"),
  inputShape: {
    message: z
      .string()
      .min(1)
      .max(1000)
      .describe("What you are about to change or have changed, in one or two sentences."),
  },
  access: "read",
  run: async (input, context) => {
    const answer = await context.editors.request<{ delivered_to: string[] }>("post_message_to_other_ais", {
      message: input.message,
    });
    const receivers = answer.delivered_to;
    return textResult(
      receivers.length > 0
        ? `Sent to ${receivers.join(", ")}. They read it with their next tool result.`
        : "No other AI is connected right now. The message is kept, and an AI that connects in the next 30 minutes gets it.",
    );
  },
});

export const replyToPersonTool = defineTool({
  name: "reply_to_person",
  title: "Reply in the Godot chat",
  description: [
    "Writes to the person in the chat of the Godot Wingman panel in the editor. Use it to answer messages the person wrote there (they reach you as news, or from wait_for_person_message): the person may not be looking at your own app.",
    "Markdown is shown formatted: headings, bold, lists, `code` and code blocks with a Copy button. res:// paths become links that open the file in Godot.",
    "Keep it as short as a chat message: what you did or found, and a question if you need a decision.",
  ].join("\n"),
  inputShape: {
    message: z.string().min(1).max(20_000).describe("The answer, in Markdown."),
    files: z
      .array(z.string())
      .max(20)
      .optional()
      .describe(
        "Project files you changed or want the person to look at, as res:// paths. Shown as buttons that open them.",
      ),
  },
  access: "read",
  run: async (input, context) => {
    await context.editors.request("reply_to_person", { message: input.message, files: input.files ?? [] });
    return textResult("Shown in the Godot Wingman chat.");
  },
});

/** Longest wait per call. Codex is set up with a 300 second tool timeout. */
const MAXIMUM_LISTEN_SECONDS = 280;

export const waitForPersonMessageTool = defineTool({
  name: "wait_for_person_message",
  title: "Wait for the person in the Godot chat",
  description: [
    "Waits until the person writes to you in the chat of the Godot Wingman panel, and returns their message (with attached pictures, files and nodes).",
    'Use it when the person asks you to listen to them in Godot, the Godot Wingman chat or the panel (for example "Listen to me in the Godot Wingman chat."). Then work in a loop: call this tool, do what the message asks, answer with reply_to_person, and call this tool again.',
    'If it returns "No message yet", call it again right away to keep listening. Stop listening when the person tells you to, or writes to you in your own app.',
  ].join("\n"),
  inputShape: {
    timeout_seconds: z
      .number()
      .int()
      .min(5)
      .max(MAXIMUM_LISTEN_SECONDS)
      .optional()
      .describe(`How long to wait in this call. Default: ${MAXIMUM_LISTEN_SECONDS}.`),
  },
  access: "read",
  run: async (input, context) => {
    const timeoutSeconds = input.timeout_seconds ?? MAXIMUM_LISTEN_SECONDS;
    const answer = await context.editors.request<{ message_arrived: boolean }>(
      "wait_for_person_message",
      { timeout_seconds: timeoutSeconds },
      (timeoutSeconds + 30) * 1000,
    );
    // The message itself comes as news at the end of this result.
    return textResult(
      answer.message_arrived
        ? "The person wrote to you in the Godot Wingman chat (below). Do what it asks, answer with reply_to_person, then call wait_for_person_message again."
        : "No message yet. Call wait_for_person_message again to keep listening.",
    );
  },
});
