/**
 * The "project" toolset (settings, input map, autoloads, plugins) and the "signals"
 * toolset (connecting nodes to each other).
 */
import { z } from "zod";
import { defineEditorTool } from "../../mcp/tool-definition.ts";
import { nodePathField, resourcePathField } from "../shared-schemas.ts";

const inputEventListField = z
  .array(z.string())
  .describe(
    'Input events: "key:Space", "key:Ctrl+S", "mouse:left", "joy_button:a", "joy_axis:left_x-". Key names are like A, Space, Enter, Escape, Up, F1.',
  );

export const getProjectSettingsTool = defineEditorTool({
  name: "get_project_settings",
  title: "Get project settings",
  description:
    'Reads project settings. Without arguments: only settings changed from the defaults. With prefix (e.g. "display/window", "physics/2d", "rendering"): every setting in that section. names reads specific settings.',
  inputShape: {
    prefix: z.string().optional(),
    names: z.array(z.string()).optional(),
  },
  access: "read",
  editorMethod: "get_project_settings",
});

export const setProjectSettingsTool = defineEditorTool({
  name: "set_project_settings",
  title: "Set project settings",
  description:
    'Changes project settings and saves project.godot. Example: {"settings": {"display/window/size/viewport_width": 1280, "application/run/main_scene": "res://main.tscn"}}. Not undoable with Ctrl+Z; read the old values first if you may need them.',
  inputShape: { settings: z.record(z.string(), z.unknown()) },
  access: "write",
  editorMethod: "set_project_settings",
});

export const getInputMapTool = defineEditorTool({
  name: "get_input_map",
  title: "Get input map",
  description:
    "Lists the input actions of the project (Project Settings > Input Map) with their keys and buttons.",
  inputShape: { include_builtin: z.boolean().optional().describe("Also list the built-in ui_* actions.") },
  access: "read",
  editorMethod: "get_input_map",
});

export const setInputActionTool = defineEditorTool({
  name: "set_input_action",
  title: "Create or change input action",
  description:
    'Creates an input action or replaces its events. Scripts read it with Input.is_action_pressed("jump"). Example: {"name": "jump", "events": ["key:Space", "joy_button:a"]}.',
  inputShape: {
    name: z.string(),
    events: inputEventListField,
    deadzone: z.number().min(0).max(1).optional().describe("For joystick axes. Default: 0.2."),
  },
  access: "write",
  editorMethod: "set_input_action",
});

export const removeInputActionTool = defineEditorTool({
  name: "remove_input_action",
  title: "Remove input action",
  description: "Removes an input action from the project.",
  inputShape: { name: z.string() },
  access: "write",
  destructive: true,
  editorMethod: "remove_input_action",
});

export const listAutoloadsTool = defineEditorTool({
  name: "list_autoloads",
  title: "List autoloads",
  description:
    "Lists autoloads: scripts or scenes loaded at game start and reachable from everywhere by name (global singletons like GameState).",
  inputShape: {},
  access: "read",
  editorMethod: "list_autoloads",
});

export const addAutoloadTool = defineEditorTool({
  name: "add_autoload",
  title: "Add autoload",
  description:
    "Registers a script or scene as an autoload (global singleton), for example GameState for score and lives.",
  inputShape: { name: z.string().describe("Global name, e.g. GameState."), path: resourcePathField },
  access: "write",
  editorMethod: "add_autoload",
});

export const removeAutoloadTool = defineEditorTool({
  name: "remove_autoload",
  title: "Remove autoload",
  description: "Removes an autoload. The script or scene file stays.",
  inputShape: { name: z.string() },
  access: "write",
  editorMethod: "remove_autoload",
});

export const listPluginsTool = defineEditorTool({
  name: "list_plugins",
  title: "List editor plugins",
  description: "Lists the editor plugins in res://addons and whether they are enabled.",
  inputShape: {},
  access: "read",
  editorMethod: "list_plugins",
});

export const setPluginEnabledTool = defineEditorTool({
  name: "set_plugin_enabled",
  title: "Enable or disable a plugin",
  description:
    "Turns an editor plugin on or off (Project Settings > Plugins). folder is the plugin's folder name in res://addons.",
  inputShape: { folder: z.string(), enabled: z.boolean() },
  access: "write",
  editorMethod: "set_plugin_enabled",
});

export const PROJECT_TOOLS = [
  getProjectSettingsTool,
  setProjectSettingsTool,
  getInputMapTool,
  setInputActionTool,
  removeInputActionTool,
  listAutoloadsTool,
  addAutoloadTool,
  removeAutoloadTool,
  listPluginsTool,
  setPluginEnabledTool,
];

export const listSignalsTool = defineEditorTool({
  name: "list_signals",
  title: "List signals",
  description:
    "Lists the signals of a node with their arguments, and where each one is connected (Node dock > Signals).",
  inputShape: {
    node_path: nodePathField,
    only_connected: z.boolean().optional().describe("Only signals that have connections."),
  },
  access: "read",
  editorMethod: "list_signals",
});

export const connectSignalTool = defineEditorTool({
  name: "connect_signal",
  title: "Connect signal",
  description:
    'Connects a signal of one node to a method of another, saved with the scene (undoable). If the method does not exist it is added to the target\'s GDScript with the right arguments, like the editor does. Example: {"from_node": "StartButton", "signal": "pressed", "to_node": ".", "method": "_on_start_pressed"}.',
  inputShape: {
    from_node: nodePathField,
    signal: z.string(),
    to_node: nodePathField,
    method: z.string().optional().describe("Default: _on_<node>_<signal>."),
    create_method: z
      .boolean()
      .optional()
      .describe("Add the method to the script when missing. Default: true."),
    binds: z.array(z.unknown()).optional().describe("Extra arguments passed after the signal's own."),
    deferred: z.boolean().optional(),
    one_shot: z.boolean().optional(),
  },
  access: "write",
  editorMethod: "connect_signal",
});

export const disconnectSignalTool = defineEditorTool({
  name: "disconnect_signal",
  title: "Disconnect signal",
  description: "Removes a signal connection (undoable). The method stays in the script.",
  inputShape: { from_node: nodePathField, signal: z.string(), method: z.string() },
  access: "write",
  editorMethod: "disconnect_signal",
});

export const SIGNAL_TOOLS = [listSignalsTool, connectSignalTool, disconnectSignalTool];
