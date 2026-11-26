/**
 * The playtesting toolsets: "play" (start, stop, pause, step, wait), "input" (real
 * keyboard, mouse and gamepad input), "game_inspect" (looking inside the running game)
 * and "debug" (game logs and performance).
 *
 * Except for run_game and stop_game, these tools talk to the game through the editor:
 * MCP server -> editor addon -> Godot debugger connection -> game bridge in the game.
 */
import type { CallToolResult } from "@modelcontextprotocol/sdk/types.js";
import { z } from "zod";
import {
  defineEditorTool,
  defineTool,
  jsonResult,
  type ToolContext,
  textResult,
  type WingmanTool,
} from "../../mcp/tool-definition.ts";
import { propertyValuesField } from "../shared-schemas.ts";

const gameNodePathField = z
  .string()
  .describe(
    'Node in the running game: relative to the current scene ("Player"), or absolute for autoloads ("/root/GameState").',
  );

const positionField = z
  .tuple([z.number(), z.number()])
  .describe(
    "[x, y] in game viewport pixels (screenshots report the viewport size; scale if the image was resized).",
  );

const inputDescriptionField = z
  .string()
  .describe(
    '"action:jump" (an input map action), "key:Space", "key:Left", "mouse:left", "joy_button:a" or "joy_axis:left_x-".',
  );

/** Sends a request to the running game and waits for its answer. */
async function requestFromGame<Result = unknown>(
  context: ToolContext,
  method: string,
  params: object = {},
  timeoutSeconds = 30,
): Promise<Result> {
  return context.editors.request<Result>(
    "game_request",
    { method, params, timeout_seconds: timeoutSeconds },
    (timeoutSeconds + 10) * 1000,
  );
}

function defineGameTool<Shape extends z.ZodRawShape>(definition: {
  name: string;
  title: string;
  description: string;
  inputShape: Shape;
  access: "read" | "write";
  gameMethod: string;
  timeoutSeconds?: (input: z.infer<z.ZodObject<Shape>>) => number;
}): WingmanTool {
  return defineTool({
    ...definition,
    async run(input, context) {
      const timeoutSeconds = definition.timeoutSeconds?.(input) ?? 30;
      return jsonResult(await requestFromGame(context, definition.gameMethod, input, timeoutSeconds));
    },
  });
}

interface EncodedImage {
  mime_type: string;
  data_base64: string;
  width: number;
  height: number;
  seconds?: number;
}

/* ---------------------------------- play ---------------------------------- */

export const runGameTool = defineEditorTool({
  name: "run_game",
  title: "Run the game",
  description:
    'Starts the game from the editor (like F5) and waits until the AI connection inside the game is ready. scene: "main" (default), "current" (the open scene, like F6) or a scene path. Then use the input tools to play and the game_inspect tools to look.',
  inputShape: {
    scene: z.string().optional(),
    restart: z.boolean().optional().describe("Stop a running game first. Default: false."),
    wait_seconds: z.number().min(5).max(300).optional(),
  },
  access: "write",
  editorMethod: "run_game",
  timeoutSeconds: 320,
});

export const stopGameTool = defineEditorTool({
  name: "stop_game",
  title: "Stop the game",
  description: "Stops the running game (like F8).",
  inputShape: {},
  access: "write",
  editorMethod: "stop_game",
});

export const getGameStateTool = defineGameTool({
  name: "get_game_state",
  title: "Get game state",
  description:
    "Current scene, paused or not, time scale, FPS, seconds running and viewport size of the running game.",
  inputShape: {},
  access: "read",
  gameMethod: "get_state",
});

export const pauseGameTool = defineGameTool({
  name: "pause_game",
  title: "Pause or resume the game",
  description:
    "Pauses or resumes the game (SceneTree.paused). While paused, step_frames advances it frame by frame.",
  inputShape: { paused: z.boolean() },
  access: "write",
  gameMethod: "set_paused",
});

export const stepFramesTool = defineGameTool({
  name: "step_frames",
  title: "Advance frame by frame",
  description:
    "Runs the game for exactly this many physics frames (60 per second by default), then pauses it. Use it to examine fast movement or collisions precisely.",
  inputShape: { count: z.number().int().min(1).max(600) },
  access: "write",
  gameMethod: "step_frames",
  timeoutSeconds: (input) => 10 + input.count / 10,
});

export const setTimeScaleTool = defineGameTool({
  name: "set_time_scale",
  title: "Slow down or speed up the game",
  description:
    "Changes the game speed (Engine.time_scale): 0.25 for slow motion, 2 for double speed, 1 for normal.",
  inputShape: { time_scale: z.number().min(0).max(100) },
  access: "write",
  gameMethod: "set_time_scale",
});

export const waitUntilTool = defineGameTool({
  name: "wait_until",
  title: "Wait until something happens",
  description:
    'Waits until a GDScript expression becomes true in the running game, checked every frame. Use node("Path") for nodes and scene for the current scene. Examples: node("Player").is_on_floor(), node("/root/GameState").score >= 10, scene.get_node("Door").visible == false. Returns met: false after the timeout.',
  inputShape: {
    condition: z.string(),
    timeout_seconds: z.number().min(0.1).max(300).optional().describe("Default: 10."),
  },
  access: "read",
  gameMethod: "wait_until",
  timeoutSeconds: (input) => (input.timeout_seconds ?? 10) + 5,
});

export const waitGameTool = defineGameTool({
  name: "wait_game",
  title: "Let the game run",
  description:
    "Lets the game run for some seconds or frames before the next step, for example to let an animation finish.",
  inputShape: {
    seconds: z.number().min(0).max(300).optional(),
    frames: z.number().int().min(1).max(36000).optional(),
  },
  access: "read",
  gameMethod: "wait",
  timeoutSeconds: (input) => (input.seconds ?? (input.frames ?? 60) / 30) + 5,
});

export const PLAY_TOOLS = [
  runGameTool,
  stopGameTool,
  getGameStateTool,
  pauseGameTool,
  stepFramesTool,
  setTimeScaleTool,
  waitUntilTool,
  waitGameTool,
];

/* ---------------------------------- input --------------------------------- */

/** Total seconds an input sequence will take, so the request does not time out early. */
function estimateSequenceSeconds(steps: Record<string, unknown>[]): number {
  let totalSeconds = 0;
  for (const step of steps) {
    totalSeconds +=
      Number(step.seconds ?? 0) +
      Number(step.wait_seconds ?? 0) +
      Number(step.wait_frames ?? 0) / 30 +
      (step.wait_until === undefined ? 0 : Number(step.timeout_seconds ?? 10)) +
      0.1;
    if (typeof step.type_text === "string") {
      totalSeconds += step.type_text.length / 30;
    }
  }
  return totalSeconds;
}

export const pressInputTool = defineTool({
  name: "press_input",
  title: "Press a key, button or action",
  description:
    'Presses an input like a player: a short tap, or held for hold_seconds (movement, charging a jump...). Prefer actions from the input map ("action:move_right"); get_input_map lists them. Events go through Godot\'s real input pipeline.',
  inputShape: {
    input: inputDescriptionField,
    hold_seconds: z.number().min(0).max(120).optional().describe("Hold for this long. Default: a short tap."),
  },
  access: "write",
  async run(input, context) {
    const step = input.hold_seconds
      ? { hold: input.input, seconds: input.hold_seconds }
      : { tap: input.input };
    return jsonResult(
      await requestFromGame(context, "play_input", { steps: [step] }, (input.hold_seconds ?? 0) + 15),
    );
  },
});

export const inputSequenceTool = defineTool({
  name: "input_sequence",
  title: "Play a sequence of inputs",
  description: [
    "Plays several inputs in order with exact timing inside the game, for combos and movement patterns. One key per step:",
    '{"press": "action:move_right"}, {"release": "action:move_right"}, {"tap": "action:jump"}, {"hold": "key:Right", "seconds": 1.5},',
    '{"wait_seconds": 0.5}, {"wait_frames": 10}, {"mouse_move": [x, y]}, {"mouse_click": [x, y], "button": "left", "double": false},',
    '{"mouse_drag": {"from": [x, y], "to": [x, y], "seconds": 0.3}}, {"type_text": "hello"},',
    '{"wait_until": "<GDScript expression>", "timeout_seconds": 5} (checked every physics frame; can use node("path"), scene, tree).',
    "Prefer wait_until over guessed times: physics timing varies, positions do not. Inputs still held when the sequence ends or a step fails are released.",
    'Example (run to the edge, then jump onto a platform): [{"press": "action:move_right"}, {"wait_until": "node("Player").position.x > 170"}, {"tap": "action:jump"}, {"wait_until": "node("Player").is_on_floor()"}, {"release": "action:move_right"}]',
  ].join("\n"),
  inputShape: { steps: z.array(z.record(z.string(), z.unknown())).min(1) },
  access: "write",
  async run(input, context) {
    const timeoutSeconds = estimateSequenceSeconds(input.steps) + 15;
    return jsonResult(await requestFromGame(context, "play_input", { steps: input.steps }, timeoutSeconds));
  },
});

export const mouseClickTool = defineTool({
  name: "mouse_click",
  title: "Click in the game",
  description:
    "Moves the mouse to a position in the game and clicks. For buttons and other UI, click_ui_element is more reliable.",
  inputShape: {
    position: positionField,
    button: z.enum(["left", "right", "middle"]).optional(),
    double: z.boolean().optional(),
  },
  access: "write",
  async run(input, context) {
    const step = {
      mouse_click: input.position,
      button: input.button ?? "left",
      double: input.double ?? false,
    };
    return jsonResult(await requestFromGame(context, "play_input", { steps: [step] }));
  },
});

export const mouseDragTool = defineTool({
  name: "mouse_drag",
  title: "Drag with the mouse",
  description:
    "Presses the left mouse button at from, moves smoothly to to, and releases (drag and drop, aiming, drawing).",
  inputShape: {
    from: positionField,
    to: positionField,
    seconds: z.number().min(0.05).max(30).optional().describe("Default: 0.3."),
  },
  access: "write",
  async run(input, context) {
    const step = { mouse_drag: { from: input.from, to: input.to, seconds: input.seconds ?? 0.3 } };
    return jsonResult(
      await requestFromGame(context, "play_input", { steps: [step] }, (input.seconds ?? 0.3) + 15),
    );
  },
});

export const typeTextTool = defineTool({
  name: "type_text",
  title: "Type text",
  description:
    "Types text into the focused text field of the game, one key at a time. Click the field first.",
  inputShape: { text: z.string().max(2000) },
  access: "write",
  async run(input, context) {
    return jsonResult(
      await requestFromGame(
        context,
        "play_input",
        { steps: [{ type_text: input.text }] },
        input.text.length / 30 + 15,
      ),
    );
  },
});

export const clickUiElementTool = defineGameTool({
  name: "click_ui_element",
  title: "Click a button or control",
  description:
    'Clicks a UI control in the running game by its node path or its exact visible text (case-insensitive), for example {"text": "Start Game"}. Use list_ui_elements to see the controls.',
  inputShape: {
    node_path: gameNodePathField.optional(),
    text: z.string().optional(),
  },
  access: "write",
  gameMethod: "click_ui_element",
});

export const INPUT_TOOLS = [
  pressInputTool,
  inputSequenceTool,
  mouseClickTool,
  mouseDragTool,
  typeTextTool,
  clickUiElementTool,
];

/* ------------------------------- game_inspect ------------------------------ */

export const takeGameScreenshotTool = defineTool({
  name: "take_game_screenshot",
  title: "Screenshot the game",
  description: "Takes a picture of the running game as the player sees it. Smaller max_size saves tokens.",
  inputShape: {
    max_size: z
      .number()
      .int()
      .min(128)
      .max(4096)
      .optional()
      .describe("Longest side in pixels. Default: 1280."),
    format: z.enum(["jpeg", "png", "webp"]).optional(),
  },
  access: "read",
  async run(input, context): Promise<CallToolResult> {
    const screenshot = await requestFromGame<EncodedImage & { viewport_size: string }>(
      context,
      "screenshot",
      input,
    );
    return {
      content: [
        { type: "image", data: screenshot.data_base64, mimeType: screenshot.mime_type },
        {
          type: "text",
          text: `Game view ${screenshot.width}x${screenshot.height} (viewport ${screenshot.viewport_size}; mouse positions use viewport pixels).`,
        },
      ],
    };
  },
});

export const captureFramesTool = defineTool({
  name: "capture_frames",
  title: "Capture several frames",
  description:
    "Takes several screenshots of the running game over time, to see movement and animation (2 to 12 frames). Combine with input_sequence: start the movement, then capture.",
  inputShape: {
    count: z.number().int().min(2).max(12).optional().describe("Default: 4."),
    interval_seconds: z.number().min(0).max(10).optional().describe("Time between frames. Default: 0.25."),
    max_size: z.number().int().min(128).max(2048).optional().describe("Default: 640."),
  },
  access: "read",
  async run(input, context): Promise<CallToolResult> {
    const params = { ...input, max_size: input.max_size ?? 640 };
    const timeoutSeconds = (input.count ?? 4) * (input.interval_seconds ?? 0.25) + 20;
    const capture = await requestFromGame<{ frames: EncodedImage[]; viewport_size: string }>(
      context,
      "capture_frames",
      params,
      timeoutSeconds,
    );
    const content: CallToolResult["content"] = [];
    for (const frame of capture.frames) {
      content.push({ type: "text", text: `t = ${frame.seconds ?? 0}s` });
      content.push({ type: "image", data: frame.data_base64, mimeType: frame.mime_type });
    }
    return { content };
  },
});

export const getGameTreeTool = defineGameTool({
  name: "get_game_tree",
  title: "Get live node tree",
  description:
    "Shows the nodes of the running game right now, with positions, including nodes created by scripts (bullets, enemies). Also lists autoloads.",
  inputShape: {
    node_path: gameNodePathField.optional(),
    max_depth: z.number().int().min(1).max(30).optional(),
  },
  access: "read",
  gameMethod: "get_tree",
});

export const getGamePropertiesTool = defineGameTool({
  name: "get_game_properties",
  title: "Read live values",
  description:
    "Reads property values of a node in the running game. Without names: its script variables (health, speed, state...) and common ones like position and velocity.",
  inputShape: {
    node_path: gameNodePathField,
    names: z.array(z.string()).optional(),
    filter: z.string().optional(),
  },
  access: "read",
  gameMethod: "get_properties",
});

export const setGamePropertiesTool = defineGameTool({
  name: "set_game_properties",
  title: "Change live values",
  description:
    "Changes properties of a node in the running game, for testing (teleport the player, give health, open a door). Only affects this run; the scene file is not changed.",
  inputShape: { node_path: gameNodePathField, properties: propertyValuesField },
  access: "write",
  gameMethod: "set_properties",
});

export const callGameMethodTool = defineGameTool({
  name: "call_game_method",
  title: "Call a method in the game",
  description:
    'Calls a method on a node of the running game, for example {"node_path": "Player", "method": "take_damage", "arguments": [10]}.',
  inputShape: {
    node_path: gameNodePathField,
    method: z.string(),
    arguments: z.array(z.unknown()).optional(),
  },
  access: "write",
  gameMethod: "call_method",
});

export const executeGameScriptTool = defineTool({
  name: "execute_game_script",
  title: "Run GDScript in the game",
  description:
    'Runs GDScript inside the running game; the code becomes the body of `func run():`. Helpers: tree, root, scene (current scene), node("Path") ("/root/Name" for autoloads), output(value). return a value to get it back; print() output and errors come back too. await works (for example await tree.physics_frame).',
  inputShape: { code: z.string(), timeout_seconds: z.number().min(1).max(300).optional() },
  access: "write",
  async run(input, context) {
    // A parse error inside the game would stop it in Godot's debugger (frozen until someone
    // presses Continue), so the editor compiles the code first and reports the errors.
    await context.editors.request("check_game_script", { code: input.code });
    const timeoutSeconds = input.timeout_seconds ?? 30;
    return jsonResult(await requestFromGame(context, "execute_script", input, timeoutSeconds));
  },
});

export const listUiElementsTool = defineGameTool({
  name: "list_ui_elements",
  title: "List UI controls",
  description:
    "Lists the visible UI controls of the running game with their text, screen rectangle and disabled state.",
  inputShape: { include_hidden: z.boolean().optional() },
  access: "read",
  gameMethod: "list_ui_elements",
});

export const GAME_INSPECT_TOOLS = [
  takeGameScreenshotTool,
  captureFramesTool,
  getGameTreeTool,
  getGamePropertiesTool,
  setGamePropertiesTool,
  callGameMethodTool,
  executeGameScriptTool,
  listUiElementsTool,
];

/* ---------------------------------- debug --------------------------------- */

export const getGameLogsTool = defineGameTool({
  name: "get_game_logs",
  title: "Read game output and errors",
  description:
    'Reads what the running game printed and its errors with file, line and stack trace. levels ["error", "script_error"] shows only problems; pass from_id = next_id to get only new entries.',
  inputShape: {
    levels: z.array(z.enum(["info", "warning", "error", "script_error", "shader_error"])).optional(),
    search: z.string().optional(),
    from_id: z.number().int().min(0).optional(),
    limit: z.number().int().min(1).max(1000).optional(),
  },
  access: "read",
  gameMethod: "get_logs",
});

export const getPerformanceTool = defineTool({
  name: "get_performance",
  title: "Measure game performance",
  description:
    "FPS, frame and physics time, node and object counts (orphan nodes hint at leaks), draw calls and memory of the running game.",
  inputShape: {},
  access: "read",
  async run(_input, context) {
    const monitors = await requestFromGame<Record<string, number>>(context, "get_performance");
    const lines = Object.entries(monitors).map(([monitorName, value]) => `${monitorName}: ${value}`);
    return textResult(lines.join("\n"));
  },
});

export const DEBUG_TOOLS = [getGameLogsTool, getPerformanceTool];
