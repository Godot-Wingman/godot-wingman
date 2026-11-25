/**
 * The "inspector" toolset (node properties and groups) and the "script" toolset
 * (creating, reading, editing, checking and attaching scripts).
 */
import { z } from "zod";
import { defineEditorTool } from "../../mcp/tool-definition.ts";
import { nodePathField, propertyValuesField, resourcePathField } from "../shared-schemas.ts";

export const getPropertiesTool = defineEditorTool({
  name: "get_properties",
  title: "Get node properties",
  description:
    'Lists the Inspector properties of a node as "name: Type = value". By default only properties that differ from the default are listed; use filter (e.g. "collision") or names to look at specific ones, or include_defaults for all. Enum properties show their options.',
  inputShape: {
    node_path: nodePathField,
    filter: z.string().optional().describe("Only properties whose name contains this text."),
    names: z.array(z.string()).optional().describe("Only these properties (shown even if default)."),
    include_defaults: z.boolean().optional().describe("Also list unchanged properties. Default: false."),
  },
  access: "read",
  editorMethod: "get_properties",
});

export const setPropertiesTool = defineEditorTool({
  name: "set_properties",
  title: "Set node properties",
  description:
    "Changes Inspector properties of a node as one undoable step. All values are checked first: if one is invalid, nothing changes and the error says why. Returns the values as Godot stored them.",
  inputShape: { node_path: nodePathField, properties: propertyValuesField },
  access: "write",
  editorMethod: "set_properties",
});

export const resetPropertiesTool = defineEditorTool({
  name: "reset_properties",
  title: "Reset node properties",
  description: "Sets properties back to their default values (the Inspector's revert arrow).",
  inputShape: { node_path: nodePathField, names: z.array(z.string()).min(1) },
  access: "write",
  editorMethod: "reset_properties",
});

export const setGroupsTool = defineEditorTool({
  name: "set_groups",
  title: "Add or remove groups",
  description:
    'Adds a node to groups or removes it. Scripts find nodes by group, for example get_tree().get_nodes_in_group("enemies"). Groups are saved with the scene.',
  inputShape: {
    node_path: nodePathField,
    add: z.array(z.string()).optional(),
    remove: z.array(z.string()).optional(),
  },
  access: "write",
  editorMethod: "set_groups",
});

export const INSPECTOR_TOOLS = [getPropertiesTool, setPropertiesTool, resetPropertiesTool, setGroupsTool];

export const createScriptTool = defineEditorTool({
  name: "create_script",
  title: "Create script",
  description:
    'Creates a GDScript (.gd) or C# (.cs) file, checks it with Godot\'s parser and can attach it to a node. Without content a template for base_type is written. GDScript uses tabs for indentation. Returns {"valid": true} or the problems with line numbers.',
  inputShape: {
    path: resourcePathField.describe('For example "res://scripts/player.gd".'),
    content: z.string().optional().describe("Full source code. Default: a template."),
    base_type: z.string().optional().describe('Class the template extends. Default: "Node".'),
    attach_to: nodePathField.optional().describe("Node to attach the script to."),
    overwrite: z.boolean().optional(),
  },
  access: "write",
  editorMethod: "create_script",
});

export const readScriptTool = defineEditorTool({
  name: "read_script",
  title: "Read script",
  description:
    "Reads a script with line numbers (number, tab, line). Long files are paged with start_line / end_line.",
  inputShape: {
    path: resourcePathField,
    start_line: z.number().int().min(1).optional(),
    end_line: z.number().int().min(1).optional(),
  },
  access: "read",
  editorMethod: "read_script",
});

export const editScriptTool = defineEditorTool({
  name: "edit_script",
  title: "Edit script",
  description:
    "Changes a script and checks it with Godot's parser. Three ways: (1) old_text + new_text replaces an exact piece of text (must be unique unless replace_all); (2) start_line + end_line + new_text replaces those lines; (3) content replaces the whole file. The open Script editor is updated too. Read the script first so old_text matches exactly, including tabs.",
  inputShape: {
    path: resourcePathField,
    old_text: z.string().optional(),
    new_text: z.string().optional(),
    replace_all: z.boolean().optional(),
    start_line: z.number().int().min(1).optional(),
    end_line: z.number().int().min(0).optional(),
    content: z.string().optional(),
  },
  access: "write",
  editorMethod: "edit_script",
});

export const validateScriptTool = defineEditorTool({
  name: "validate_script",
  title: "Check script for errors",
  description: "Checks a GDScript file with Godot's parser and returns the problems with line numbers.",
  inputShape: { path: resourcePathField },
  access: "read",
  editorMethod: "validate_script",
});

export const attachScriptTool = defineEditorTool({
  name: "attach_script",
  title: "Attach script to node",
  description:
    "Attaches a script file to a node (undoable). Pass script_path null to remove the node's script.",
  inputShape: { node_path: nodePathField, script_path: resourcePathField.nullable() },
  access: "write",
  editorMethod: "attach_script",
});

export const SCRIPT_TOOLS = [
  createScriptTool,
  readScriptTool,
  editScriptTool,
  validateScriptTool,
  attachScriptTool,
];
