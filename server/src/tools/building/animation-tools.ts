/**
 * The "animation" toolset: animations of AnimationPlayer nodes (tracks and keys) and
 * state machines of AnimationTree nodes. Every change is one undo step in the editor.
 */
import { z } from "zod";
import { defineEditorTool } from "../../mcp/tool-definition.ts";
import { nodePathField } from "../shared-schemas.ts";

const animationPlayerField = nodePathField.describe("Path of the AnimationPlayer node.");
const animationNameField = z
  .string()
  .describe('Animation name, e.g. "walk". Animations in a named library are "library/walk".');

const keyShape = z.object({
  time: z.number().min(0).describe("Seconds from the start."),
  value: z
    .unknown()
    .optional()
    .describe(
      'Value tracks: a value of the property ([x, y], "#ff0000", 1.5...). position_3d/scale_3d: [x, y, z]. rotation_3d: [x, y, z] in degrees. method: {"method": "queue_free", "args": []}. audio: "res://sound.ogg". animation: an animation name.',
    ),
  transition: z
    .number()
    .optional()
    .describe("Easing to the next key: 1 linear, <1 ease out, >1 ease in, negative in-out."),
});

const trackShape = z.object({
  path: z
    .string()
    .describe(
      'Relative to the AnimationPlayer\'s root node (its parent by default). Value and bezier tracks: "NodePath:property", e.g. "Sprite2D:modulate", ".:position", "Body:scale:y". Other types: the node path only, e.g. "Body".',
    ),
  type: z
    .enum([
      "value",
      "position_3d",
      "rotation_3d",
      "scale_3d",
      "blend_shape",
      "method",
      "bezier",
      "audio",
      "animation",
    ])
    .optional()
    .describe("Default: value (animates any property)."),
  interpolation: z.enum(["nearest", "linear", "cubic", "linear_angle", "cubic_angle"]).optional(),
  update_mode: z
    .enum(["continuous", "discrete", "capture"])
    .optional()
    .describe("Value tracks: discrete for frame numbers, textures, booleans."),
  replace_keys: z.boolean().optional().describe("Remove the track's existing keys first."),
  keys: z.array(keyShape).optional(),
});

const animationEditShape = {
  length: z.number().positive().optional().describe("Seconds."),
  loop_mode: z.enum(["none", "linear", "pingpong"]).optional(),
  step: z.number().min(0).optional().describe("Snap step for keys in the editor, in seconds."),
  tracks: z
    .array(trackShape)
    .optional()
    .describe("Tracks to add or extend. Keys at an existing time replace that key."),
};

export const listAnimationsTool = defineEditorTool({
  name: "list_animations",
  title: "List animations",
  description:
    "Lists the AnimationPlayer nodes of the open scene with their animations (length, loop, track count), and the AnimationTree nodes.",
  inputShape: { node_path: animationPlayerField.optional().describe("Only this AnimationPlayer.") },
  access: "read",
  editorMethod: "list_animations",
});

export const getAnimationTool = defineEditorTool({
  name: "get_animation",
  title: "Get animation",
  description: "Shows an animation's tracks and keys (time: value), its length and loop mode.",
  inputShape: { node_path: animationPlayerField, animation: animationNameField },
  access: "read",
  editorMethod: "get_animation",
});

export const createAnimationTool = defineEditorTool({
  name: "create_animation",
  title: "Create animation",
  description:
    'Creates an animation in an AnimationPlayer, with its tracks and keys in the same call. Example (a 2D sprite that blinks red and moves): {"node_path": "AnimationPlayer", "animation": "hit", "length": 0.4, "tracks": [{"path": "Sprite2D:modulate", "keys": [{"time": 0, "value": "white"}, {"time": 0.2, "value": "red"}, {"time": 0.4, "value": "white"}]}, {"path": "Sprite2D:position", "keys": [{"time": 0, "value": [0, 0]}, {"time": 0.2, "value": [4, 0]}]}]}. For sprite sheets animate "Sprite2D:frame" with update_mode discrete.',
  inputShape: {
    node_path: animationPlayerField,
    animation: animationNameField,
    ...animationEditShape,
    autoplay: z.boolean().optional().describe("Play this animation when the scene starts."),
    overwrite: z.boolean().optional().describe("Replace an animation with the same name."),
  },
  access: "write",
  editorMethod: "create_animation",
});

export const editAnimationTool = defineEditorTool({
  name: "edit_animation",
  title: "Edit animation",
  description:
    "Changes an animation: length, loop mode, adds or extends tracks (keys at an existing time are replaced), removes tracks or single keys. One undo step.",
  inputShape: {
    node_path: animationPlayerField,
    animation: animationNameField,
    ...animationEditShape,
    remove_tracks: z.array(z.string()).optional().describe("Paths of tracks to remove."),
    remove_keys: z
      .array(z.object({ path: z.string(), type: z.string().optional(), time: z.number() }))
      .optional(),
  },
  access: "write",
  editorMethod: "edit_animation",
});

export const deleteAnimationTool = defineEditorTool({
  name: "delete_animation",
  title: "Delete animation",
  description: "Deletes an animation from its AnimationPlayer (undoable).",
  inputShape: { node_path: animationPlayerField, animation: animationNameField },
  access: "write",
  destructive: true,
  editorMethod: "delete_animation",
});

export const previewAnimationTool = defineEditorTool({
  name: "preview_animation",
  title: "Preview animation pose",
  description:
    "Shows the pose of an animation at a given time in the editor, like dragging the Animation panel's time cursor, and returns the animated values at that moment. Follow with render_view to see it. The pose really changes the scene: preview RESET at 0 before saving when the project has a RESET animation.",
  inputShape: {
    node_path: animationPlayerField,
    animation: animationNameField,
    time: z.number().min(0).optional().describe("Seconds. Default: 0."),
  },
  access: "read",
  editorMethod: "preview_animation",
});

export const setupAnimationStateMachineTool = defineEditorTool({
  name: "setup_animation_state_machine",
  title: "Set up animation state machine",
  description:
    'Builds the state machine of an AnimationTree: states that play animations and transitions between them. Example: {"node_path": "AnimationTree", "animation_player": "AnimationPlayer", "states": [{"name": "Idle", "animation": "idle"}, {"name": "Run", "animation": "run"}, {"name": "Jump", "animation": "jump"}], "start_state": "Idle", "transitions": [{"from": "Idle", "to": "Run", "condition": "moving", "xfade_time": 0.1}, {"from": "Run", "to": "Idle", "condition": "stopped"}, {"from": "Jump", "to": "Idle", "switch_mode": "at_end"}]}. Transitions with a condition or expression advance by themselves; others are reached with travel().',
  inputShape: {
    node_path: nodePathField.describe("Path of the AnimationTree node (add one with add_node first)."),
    animation_player: nodePathField
      .optional()
      .describe("The AnimationPlayer whose animations the states play."),
    states: z
      .array(
        z.object({
          name: z.string(),
          animation: z.string().optional().describe("Default: the state name."),
          position: z.array(z.number()).length(2).optional().describe("Position in the graph."),
        }),
      )
      .optional(),
    transitions: z
      .array(
        z.object({
          from: z.string().describe('A state, or "Start".'),
          to: z.string().describe('A state, or "End".'),
          switch_mode: z.enum(["immediate", "sync", "at_end"]).optional(),
          advance_mode: z.enum(["disabled", "enabled", "auto"]).optional(),
          condition: z.string().optional().describe("Name of a boolean in parameters/conditions/."),
          expression: z.string().optional().describe('GDScript expression, e.g. "velocity.x != 0".'),
          xfade_time: z.number().min(0).optional().describe("Cross-fade seconds."),
        }),
      )
      .optional(),
    start_state: z.string().optional().describe("State played first (adds Start -> state)."),
    keep_existing: z
      .boolean()
      .optional()
      .describe("Add to the current state machine instead of replacing it."),
  },
  access: "write",
  editorMethod: "setup_animation_state_machine",
});

export const getAnimationTreeTool = defineEditorTool({
  name: "get_animation_tree",
  title: "Get animation tree",
  description:
    "Describes an AnimationTree: its states and transitions (state machine) or nodes (blend tree), and every parameter with its value (conditions, blend positions...).",
  inputShape: { node_path: nodePathField.describe("Path of the AnimationTree node.") },
  access: "read",
  editorMethod: "get_animation_tree",
});

export const ANIMATION_TOOLS = [
  listAnimationsTool,
  getAnimationTool,
  createAnimationTool,
  editAnimationTool,
  deleteAnimationTool,
  previewAnimationTool,
  setupAnimationStateMachineTool,
  getAnimationTreeTool,
];
