/**
 * The "resources" toolset (materials, shapes, themes...), the "filesystem" toolset
 * (project files) and the "viewport" toolset (editor screens and rendered views).
 */
import { z } from "zod";
import { defineEditorTool, defineTool, imageResult } from "../../mcp/tool-definition.ts";
import { nodePathField, propertyValuesField, resourcePathField } from "../shared-schemas.ts";

const resourceLocationShape = {
  path: resourcePathField.optional().describe("A resource file (.tres, .res)."),
  node_path: nodePathField.optional().describe("Or: the node holding the resource..."),
  property: z.string().optional().describe('...and its property, e.g. "material" or "shape".'),
};

export const createResourceTool = defineEditorTool({
  name: "create_resource",
  title: "Create resource",
  description:
    'Creates a resource such as StandardMaterial3D, CircleShape2D, Gradient, Theme or LabelSettings, sets its properties, and saves it to a .tres file and/or assigns it to a node property. Example: {"type": "StandardMaterial3D", "properties": {"albedo_color": "#3a7d44"}, "assign_to": {"node_path": "Ground", "property": "material_override"}}.',
  inputShape: {
    type: z.string(),
    properties: propertyValuesField.optional(),
    path: resourcePathField.optional().describe("Save as a file to reuse it in several places."),
    assign_to: z.object({ node_path: nodePathField, property: z.string() }).optional(),
  },
  access: "write",
  editorMethod: "create_resource",
});

export const getResourcePropertiesTool = defineEditorTool({
  name: "get_resource_properties",
  title: "Get resource properties",
  description:
    "Lists the properties of a resource file, or of a resource inside a node property. Only changed properties unless include_defaults.",
  inputShape: { ...resourceLocationShape, include_defaults: z.boolean().optional() },
  access: "read",
  editorMethod: "get_resource_properties",
});

export const setResourcePropertiesTool = defineEditorTool({
  name: "set_resource_properties",
  title: "Set resource properties",
  description:
    "Changes properties of a resource file (saved right away) or of a resource inside a node property (saved with the scene). Undoable.",
  inputShape: { ...resourceLocationShape, properties: propertyValuesField },
  access: "write",
  editorMethod: "set_resource_properties",
});

export const RESOURCE_TOOLS = [createResourceTool, getResourcePropertiesTool, setResourcePropertiesTool];

export const listFilesTool = defineEditorTool({
  name: "list_files",
  title: "List project files",
  description:
    'Lists project files with their resource type, like the FileSystem dock. filter is a wildcard pattern such as "*.tscn" or "player*".',
  inputShape: {
    path: resourcePathField.optional().describe('Folder. Default: "res://".'),
    filter: z.string().optional(),
    recursive: z.boolean().optional().describe("Include subfolders. Default: true."),
    limit: z.number().int().min(1).max(5000).optional(),
  },
  access: "read",
  editorMethod: "list_files",
});

export const readFileTool = defineEditorTool({
  name: "read_file",
  title: "Read text file",
  description:
    "Reads a text file of the project (.tscn, .tres, .json, .cfg, .gdshader...). For scripts read_script adds line numbers.",
  inputShape: { path: resourcePathField },
  access: "read",
  editorMethod: "read_file",
});

export const writeFileTool = defineEditorTool({
  name: "write_file",
  title: "Write text file",
  description:
    "Writes a text file in the project (data like .json or .cfg, shaders, docs) and tells the editor about it. Use create_script / edit_script for scripts. Prefer the scene tools over writing .tscn text by hand.",
  inputShape: { path: resourcePathField, content: z.string() },
  access: "write",
  editorMethod: "write_file",
});

export const searchProjectTool = defineEditorTool({
  name: "search_project",
  title: "Search project files",
  description:
    'Searches the text of scripts, scenes and other text files. Returns "path:line: text". Set regex for regular expressions; file_filter limits files, e.g. "*.gd".',
  inputShape: {
    query: z.string(),
    regex: z.boolean().optional(),
    file_filter: z.string().optional(),
    limit: z.number().int().min(1).max(1000).optional(),
  },
  access: "read",
  editorMethod: "search_project",
});

export const moveFileTool = defineEditorTool({
  name: "move_file",
  title: "Move or rename file",
  description:
    "Moves or renames a file or folder and updates every reference to it in scenes, resources and scripts.",
  inputShape: { from: resourcePathField, to: resourcePathField },
  access: "write",
  editorMethod: "move_file",
});

export const deleteFileTool = defineEditorTool({
  name: "delete_file",
  title: "Delete file",
  description:
    "Moves a file or folder to the operating system's trash (it can be restored from there). Refuses when other files still use it, unless force is true.",
  inputShape: { path: resourcePathField, force: z.boolean().optional() },
  access: "write",
  destructive: true,
  editorMethod: "delete_file",
});

export const createFolderTool = defineEditorTool({
  name: "create_folder",
  title: "Create folder",
  description: "Creates a folder in the project (and missing parent folders).",
  inputShape: { path: resourcePathField },
  access: "write",
  editorMethod: "create_folder",
});

export const getDependenciesTool = defineEditorTool({
  name: "get_dependencies",
  title: "Get file dependencies",
  description:
    "Shows which files a resource uses, and which files use it. Check this before deleting or replacing a file.",
  inputShape: { path: resourcePathField },
  access: "read",
  editorMethod: "get_dependencies",
});

export const reimportFilesTool = defineEditorTool({
  name: "reimport_files",
  title: "Reimport files",
  description:
    "Imports new asset files (images, sounds, 3D models), also in folders the editor has not scanned yet, and re-imports changed ones. Returns the resource type of each file.",
  inputShape: { paths: z.array(resourcePathField).min(1) },
  access: "write",
  editorMethod: "reimport_files",
});

export const FILESYSTEM_TOOLS = [
  listFilesTool,
  readFileTool,
  writeFileTool,
  searchProjectTool,
  moveFileTool,
  deleteFileTool,
  createFolderTool,
  getDependenciesTool,
  reimportFilesTool,
];

export const setMainScreenTool = defineEditorTool({
  name: "set_main_screen",
  title: "Switch editor screen",
  description: "Switches the editor's main screen (the tabs at the top): 2D, 3D, Script, Game or AssetLib.",
  inputShape: { screen: z.enum(["2D", "3D", "Script", "Game", "AssetLib"]) },
  access: "read",
  editorMethod: "set_main_screen",
});

export const renderViewTool = defineTool({
  name: "render_view",
  title: "Render scene from any angle",
  description:
    'Renders the open scene, framed around a node, from any angle, without moving the person\'s editor camera. 3D: view "front", "back", "left", "right", "top", "bottom" or "perspective", or exact yaw_degrees / pitch_degrees; zoom > 1 moves closer. 2D: frames the node and its children. Use it to check how something looks.',
  inputShape: {
    node_path: nodePathField.optional().describe("Node to frame. Default: the whole scene."),
    view: z.enum(["front", "back", "left", "right", "top", "bottom", "perspective"]).optional(),
    yaw_degrees: z.number().optional(),
    pitch_degrees: z.number().min(-89).max(89).optional(),
    zoom: z.number().min(0.05).max(20).optional(),
    width: z.number().int().min(64).max(2048).optional(),
    height: z.number().int().min(64).max(2048).optional(),
    format: z.enum(["jpeg", "png", "webp"]).optional(),
  },
  access: "read",
  async run(input, context) {
    const render = await context.editors.request<{ mime_type: string; data_base64: string; mode: string }>(
      "render_view",
      input,
    );
    return imageResult(
      render.data_base64,
      render.mime_type,
      `${render.mode} render of ${input.node_path ?? "the scene"}`,
    );
  },
});

export const VIEWPORT_TOOLS = [setMainScreenTool, renderViewTool];
