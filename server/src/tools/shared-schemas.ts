/**
 * Input fields used by many tools, described once so every tool explains them the same way.
 */
import { z } from "zod";

export const nodePathField = z
  .string()
  .describe(
    'Path of a node in the open scene, relative to the scene root: "." for the root, "Player/Sprite2D" for a child.',
  );

export const optionalNodePathField = nodePathField.optional();

export const resourcePathField = z
  .string()
  .describe('Project path starting with res://, for example "res://scenes/player.tscn".');

/**
 * Property values as JSON. The addon converts them to the property's type, so natural
 * forms work: [100, 50] or "Vector2(100, 50)" for vectors, "#ff8800" or "red" for colors,
 * "res://icon.svg" for textures, a class name like "CircleShape2D" for a new resource.
 */
export const propertyValuesField = z
  .record(z.string(), z.unknown())
  .describe(
    'Property names and new values, for example {"position": [100, 50], "modulate": "#ff8800", "texture": "res://icon.svg", "shape": "CircleShape2D", "shape:radius": 24}. Sub-properties use ":" (position:x, material:albedo_color). Any value can also be a Godot literal like "Vector2(1, 2)".',
  );
