/**
 * Every toolset of Godot Pilot. To add a tool, define it in its toolset's folder and
 * add it to the list below.
 */
import type { Toolset } from "../mcp/toolset-controller.ts";
import {
  executeEditorScriptTool,
  getEditorStateTool,
  getLogsTool,
  takeEditorScreenshotTool,
} from "./core/editor-tools.ts";
import { getClassDocsTool, getGuideTool, searchDocsTool } from "./core/knowledge-tools.ts";
import {
  getStatusTool,
  installAddonTool,
  launchEditorTool,
  listToolsetsTool,
  selectEditorTool,
  toggleToolsetsTool,
} from "./core/setup-tools.ts";
import { INSPECTOR_TOOLS, SCRIPT_TOOLS } from "./editing/inspector-and-script-tools.ts";
import { PROJECT_TOOLS, SIGNAL_TOOLS } from "./editing/project-and-signal-tools.ts";
import { FILESYSTEM_TOOLS, RESOURCE_TOOLS, VIEWPORT_TOOLS } from "./editing/resource-file-viewport-tools.ts";
import { SCENE_TOOLS } from "./editing/scene-tools.ts";
import { DEBUG_TOOLS, GAME_INSPECT_TOOLS, INPUT_TOOLS, PLAY_TOOLS } from "./playtesting/playtesting-tools.ts";

export const ALL_TOOLSETS: Toolset[] = [
  {
    name: "core",
    title: "Core",
    description:
      "Status, opening projects, toolset switching, running GDScript in the editor, logs and errors, editor screenshots, Godot documentation and guides. Always enabled.",
    alwaysEnabled: true,
    tools: [
      getStatusTool,
      launchEditorTool,
      installAddonTool,
      selectEditorTool,
      listToolsetsTool,
      toggleToolsetsTool,
      getEditorStateTool,
      executeEditorScriptTool,
      getLogsTool,
      takeEditorScreenshotTool,
      getClassDocsTool,
      searchDocsTool,
      getGuideTool,
    ],
  },
  {
    name: "scene",
    title: "Scene",
    description:
      "The scene tree: open, create and save scenes; add, delete, duplicate, move, rename and select nodes; batch edits.",
    tools: SCENE_TOOLS,
  },
  {
    name: "inspector",
    title: "Inspector",
    description:
      "Read and change node properties (position, texture, collision shape...) and groups, with undo.",
    tools: INSPECTOR_TOOLS,
  },
  {
    name: "script",
    title: "Scripts",
    description:
      "Create, read, edit, check and attach GDScript and C# scripts. Every change is checked by Godot's parser.",
    tools: SCRIPT_TOOLS,
  },
  {
    name: "project",
    title: "Project settings",
    description:
      "Project settings, input map (keys and buttons for actions), autoloads (global singletons) and editor plugins.",
    tools: PROJECT_TOOLS,
  },
  {
    name: "signals",
    title: "Signals",
    description:
      "List, connect and disconnect signals between nodes (button pressed, body entered, timer timeout...).",
    tools: SIGNAL_TOOLS,
  },
  {
    name: "resources",
    title: "Resources",
    description:
      "Create and edit resources: materials, collision shapes, gradients, themes, label settings and .tres files.",
    tools: RESOURCE_TOOLS,
  },
  {
    name: "filesystem",
    title: "File system",
    description:
      "List, read, write, search, move (with reference updates) and delete project files; dependencies; reimport.",
    tools: FILESYSTEM_TOOLS,
  },
  {
    name: "viewport",
    title: "Viewport",
    description: "Switch the editor between 2D, 3D and Script, and render the scene from any angle.",
    tools: VIEWPORT_TOOLS,
  },
  {
    name: "play",
    title: "Play",
    description:
      "Run and stop the game, pause it, step frame by frame, change its speed, and wait until something happens.",
    tools: PLAY_TOOLS,
  },
  {
    name: "input",
    title: "Input",
    description:
      "Play the game like a person: press and hold keys, actions and gamepad buttons, click, drag, type, timed sequences.",
    tools: INPUT_TOOLS,
  },
  {
    name: "game_inspect",
    title: "Game inspection",
    description:
      "Look inside the running game: screenshots, frame series, live node tree, live values, method calls, GDScript, UI controls.",
    tools: GAME_INSPECT_TOOLS,
  },
  {
    name: "debug",
    title: "Debug",
    description: "The running game's printed output and errors with stack traces, and performance numbers.",
    tools: DEBUG_TOOLS,
  },
];
