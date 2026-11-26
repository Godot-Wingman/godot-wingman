/**
 * The "3d" toolset: primitive meshes with materials and collision, sky and sun,
 * collision for imported models, measuring nodes (also in 2D) and aiming 3D nodes.
 */
import { z } from "zod";
import { defineEditorTool } from "../../mcp/tool-definition.ts";
import { nodePathField } from "../shared-schemas.ts";

const vector3Field = z.array(z.number()).length(3);
const bodyField = z.enum(["none", "static", "rigid", "character", "area", "animatable"]);

export const addMeshTool = defineEditorTool({
  name: "add_mesh",
  title: "Add 3D mesh",
  description:
    'Adds a primitive 3D mesh (box, sphere, capsule, cylinder, plane, prism, torus, quad) with a color or material, optionally inside a physics body with a matching collision shape, in one undo step. Example (a floor): {"shape": "box", "name": "Floor", "size": [20, 0.5, 20], "position": [0, -0.25, 0], "color": "#4a7d3a", "body": "static"}. Sizes are meters [width, height, depth]. For model files (.glb, .gltf, .blend) use add_node with type "res://model.glb".',
  inputShape: {
    parent_path: nodePathField.optional().describe("Default: the scene root."),
    shape: z.enum(["box", "sphere", "capsule", "cylinder", "plane", "prism", "torus", "quad"]).optional(),
    name: z.string().optional(),
    size: z
      .union([vector3Field, z.number().positive()])
      .optional()
      .describe("Default [1, 1, 1]. A number makes all sides equal."),
    color: z
      .string()
      .optional()
      .describe('Creates a StandardMaterial3D, e.g. "#cc3333" or "#ffffff80" (transparent).'),
    material: z
      .unknown()
      .optional()
      .describe('A material path "res://...", or {"type": "StandardMaterial3D", "properties": {...}}.'),
    mesh_properties: z
      .record(z.string(), z.unknown())
      .optional()
      .describe('Exact mesh properties, e.g. {"radial_segments": 16}.'),
    position: vector3Field.optional(),
    rotation_degrees: vector3Field.optional(),
    scale: vector3Field.optional(),
    body: bodyField
      .optional()
      .describe("Wrap the mesh in a physics body with a collision shape. Default none."),
  },
  access: "write",
  editorMethod: "add_mesh",
});

export const setupEnvironmentTool = defineEditorTool({
  name: "setup_environment",
  title: "Set up sky and sun",
  description:
    "Gives a 3D scene a sky, ambient light, tone mapping and a sun (DirectionalLight3D with shadows) from a preset: day, sunset, night or overcast. Existing WorldEnvironment and sun nodes are updated, not duplicated. Undoable.",
  inputShape: {
    preset: z.enum(["day", "sunset", "night", "overcast"]).optional(),
    sun: z.boolean().optional().describe("Add or update a sun. Default true."),
    shadows: z.boolean().optional(),
    sun_rotation_degrees: vector3Field.optional().describe("x is the height angle (-90 = noon)."),
    fog: z.boolean().optional(),
    glow: z.boolean().optional().describe("Default true."),
    ambient_occlusion: z.boolean().optional(),
    environment_properties: z
      .record(z.string(), z.unknown())
      .optional()
      .describe('Exact Environment properties, e.g. {"fog_density": 0.02}.'),
  },
  access: "write",
  editorMethod: "setup_environment",
});

export const generateCollisionTool = defineEditorTool({
  name: "generate_collision",
  title: "Generate collision from meshes",
  description:
    "Creates collision shapes from every mesh under a node (an imported model, a level), inside a new physics body child, so players can stand on it or bump into it. trimesh follows the exact surface (static only); convex wraps each mesh (works for moving bodies).",
  inputShape: {
    node_path: nodePathField,
    shape: z.enum(["trimesh", "convex", "simplified_convex"]).optional().describe("Default trimesh."),
    body: bodyField
      .optional()
      .describe('Default static. "none" adds the shapes to node_path itself, which must be a body.'),
    name: z.string().optional().describe("Name of the new body."),
  },
  access: "write",
  editorMethod: "generate_collision",
});

export const getBoundsTool = defineEditorTool({
  name: "get_bounds",
  title: "Measure node size",
  description:
    "The space a node and its children take, in global coordinates: a box in meters for 3D (min, max, size, center, bottom_center), a rectangle in pixels for 2D (sprites, controls, collision shapes, tiles). Use it to place things on the ground, scale imported models, or check that objects fit.",
  inputShape: { node_path: nodePathField.optional().describe("Default: the scene root.") },
  access: "read",
  editorMethod: "get_bounds",
});

export const lookAtTool = defineEditorTool({
  name: "look_at",
  title: "Aim a 3D node",
  description:
    'Turns a 3D node (camera, light, character...) so its front (-Z) faces a point or another node, optionally moving it first. Example: place the camera: {"node_path": "Camera3D", "position": [0, 6, 10], "target_node": "Player"}. Undoable.',
  inputShape: {
    node_path: nodePathField,
    target: vector3Field.optional().describe("A point [x, y, z]."),
    target_node: nodePathField.optional().describe("Or: a 3D node to face."),
    position: vector3Field.optional().describe("Move the node here first (global)."),
  },
  access: "write",
  editorMethod: "look_at",
});

export const SPATIAL_TOOLS = [
  addMeshTool,
  setupEnvironmentTool,
  generateCollisionTool,
  getBoundsTool,
  lookAtTool,
];
