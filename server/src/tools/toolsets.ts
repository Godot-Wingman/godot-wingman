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
];
