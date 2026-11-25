/**
 * The "scene" toolset: the scene tree and its nodes, like the Scene dock.
 */
import { z } from "zod";
import { defineEditorTool } from "../../mcp/tool-definition.ts";
import {
  nodePathField,
  optionalNodePathField,
  propertyValuesField,
  resourcePathField,
} from "../shared-schemas.ts";

export const getSceneTreeTool = defineEditorTool({
  name: "get_scene_tree",
  title: "Get scene tree",
  description:
    'Shows the node tree of the open scene, one node per line, indented by depth: "Name (Class) script=... instance=... groups=[...]". A node\'s path is the names from the root joined with "/", without the root\'s name. Instanced scenes are shown as one line; open them to see inside.',
  inputShape: {
    node_path: optionalNodePathField.describe("Show only this branch. Default: the whole scene."),
    max_depth: z.number().int().min(1).max(50).optional().describe("How deep to go. Default: 8."),
  },
  access: "read",
  editorMethod: "get_scene_tree",
});

export const openSceneTool = defineEditorTool({
  name: "open_scene",
  title: "Open scene",
  description: "Opens a scene file in the editor and makes it the edited scene.",
  inputShape: { path: resourcePathField },
  access: "read",
  editorMethod: "open_scene",
});

export const saveSceneTool = defineEditorTool({
  name: "save_scene",
  title: "Save scene",
  description: "Saves the open scene (Ctrl+S). Pass path to save it under a new name (Save As).",
  inputShape: { path: resourcePathField.optional() },
  access: "write",
  editorMethod: "save_scene",
});

export const createSceneTool = defineEditorTool({
  name: "create_scene",
  title: "Create scene",
  description:
    'Creates a new scene file with one root node and opens it. Common roots: "Node2D" (2D levels), "Node3D" (3D levels), "CharacterBody2D" (a player), "Control" (UI), "Area2D" (pickups).',
  inputShape: {
    path: resourcePathField.describe('Where to save, for example "res://scenes/enemy.tscn".'),
    root_type: z.string().optional().describe('Class of the root node. Default: "Node2D".'),
    root_name: z.string().optional().describe("Name of the root node. Default: from the file name."),
    overwrite: z.boolean().optional().describe("Replace an existing file. Default: false."),
  },
  access: "write",
  editorMethod: "create_scene",
});

export const closeSceneTool = defineEditorTool({
  name: "close_scene",
  title: "Close scene",
  description:
    "Closes the open scene tab. Refuses when there are unsaved changes, unless discard_changes is true.",
  inputShape: { discard_changes: z.boolean().optional() },
  access: "write",
  editorMethod: "close_scene",
});

export const addNodeTool = defineEditorTool({
  name: "add_node",
  title: "Add node",
  description:
    'Adds a node to the open scene (undoable). type is a class ("Sprite2D", "CollisionShape2D"), a script class_name, or a scene file ("res://enemy.tscn") to add an instance of it. Properties can be set at once. Example: {"parent_path": "Player", "type": "CollisionShape2D", "properties": {"shape": "CapsuleShape2D", "shape:height": 40}}.',
  inputShape: {
    type: z.string().describe("Node class, script class name, or scene path to instance."),
    parent_path: optionalNodePathField.describe('Parent node. Default: the scene root (".").'),
    name: z.string().optional().describe("Node name. Default: the type name."),
    properties: propertyValuesField.optional(),
    index: z.number().int().optional().describe("Position among the parent's children. Default: last."),
  },
  access: "write",
  editorMethod: "add_node",
});

export const deleteNodesTool = defineEditorTool({
  name: "delete_nodes",
  title: "Delete nodes",
  description: "Deletes nodes and everything under them from the open scene (undoable with Ctrl+Z).",
  inputShape: { node_paths: z.array(nodePathField).min(1) },
  access: "write",
  destructive: true,
  editorMethod: "delete_nodes",
});

export const duplicateNodeTool = defineEditorTool({
  name: "duplicate_node",
  title: "Duplicate node",
  description:
    "Duplicates a node with its children, scripts, groups and signal connections (Ctrl+D). The copy is placed right after the original.",
  inputShape: { node_path: nodePathField, new_name: z.string().optional() },
  access: "write",
  editorMethod: "duplicate_node",
});

export const moveNodeTool = defineEditorTool({
  name: "move_node",
  title: "Move or reorder node",
  description:
    "Moves a node under another parent and/or to another position among its siblings (drag and drop in the Scene dock). Keeps the global position by default. Child order matters: later children draw on top in 2D.",
  inputShape: {
    node_path: nodePathField,
    new_parent_path: optionalNodePathField.describe("New parent. Default: keep the parent."),
    index: z.number().int().optional().describe("New position among siblings (0 = first)."),
    keep_global_transform: z.boolean().optional().describe("Keep the position in the world. Default: true."),
  },
  access: "write",
  editorMethod: "move_node",
});

export const renameNodeTool = defineEditorTool({
  name: "rename_node",
  title: "Rename node",
  description: "Renames a node. Scripts that use the old path ($OldName) must be updated too.",
  inputShape: { node_path: nodePathField, new_name: z.string() },
  access: "write",
  editorMethod: "rename_node",
});

export const selectNodesTool = defineEditorTool({
  name: "select_nodes",
  title: "Select nodes",
  description:
    "Selects nodes in the editor and shows the last one in the Inspector, so the person sees what you are working on.",
  inputShape: { node_paths: z.array(nodePathField) },
  access: "read",
  editorMethod: "select_nodes",
});

export const batchEditTool = defineEditorTool({
  name: "batch_edit",
  title: "Several scene edits at once",
  description:
    'Runs several scene operations in one call, in order, to save round trips. Each operation has "action" plus the same fields as the matching tool: add_node, delete_nodes, duplicate_node, move_node, rename_node, set_properties (node_path + properties). Stops at the first error unless stop_on_error is false. Example: {"operations": [{"action": "add_node", "type": "Sprite2D", "name": "Coin"}, {"action": "set_properties", "node_path": "Coin", "properties": {"position": [64, 32]}}]}',
  inputShape: {
    operations: z.array(z.record(z.string(), z.unknown())).min(1),
    stop_on_error: z.boolean().optional(),
  },
  access: "write",
  editorMethod: "batch_edit",
});

export const SCENE_TOOLS = [
  getSceneTreeTool,
  openSceneTool,
  saveSceneTool,
  createSceneTool,
  closeSceneTool,
  addNodeTool,
  deleteNodesTool,
  duplicateNodeTool,
  moveNodeTool,
  renameNodeTool,
  selectNodesTool,
  batchEditTool,
];
