/**
 * The "tilemap" toolset (TileSets and TileMapLayer cells, terrains) and the "ui" toolset
 * (Control layouts, anchor presets, theme overrides, building UI trees).
 */
import { z } from "zod";
import { defineEditorTool } from "../../mcp/tool-definition.ts";
import { nodePathField, propertyValuesField, resourcePathField } from "../shared-schemas.ts";

const layerField = nodePathField.describe("Path of the TileMapLayer node.");
const cellField = z.array(z.number().int()).length(2).describe("Cell coordinates [x, y].");
const rectangleShape = z
  .object({ from: cellField, to: cellField })
  .describe("Both corners are included: from [0, 0] to [9, 0] is 10 cells.");
const tileChoiceShape = {
  atlas: z
    .array(z.number().int())
    .length(2)
    .optional()
    .describe("Tile coordinates in the atlas [x, y]. Default [0, 0]."),
  source_id: z.number().int().optional().describe("Default: the TileSet's first source."),
  alternative: z.number().int().optional().describe("Alternative tile (flipped, scene tile...). Default 0."),
};

export const getTilemapInfoTool = defineEditorTool({
  name: "get_tilemap_info",
  title: "Get tilemap info",
  description:
    "Describes the TileSet of a TileMapLayer (or a TileSet file): tile size, atlas sources with their tile coordinates, terrain sets and physics layers; and how many cells the layer uses.",
  inputShape: {
    node_path: layerField.optional(),
    tileset_path: resourcePathField.optional().describe("Or: a TileSet file."),
  },
  access: "read",
  editorMethod: "get_tilemap_info",
});

export const createTilesetTool = defineEditorTool({
  name: "create_tileset",
  title: "Create TileSet from tile sheet",
  description:
    "Makes a TileSet from a tile sheet image: every grid cell with visible pixels becomes a tile (atlas source 0). collision adds a full-square collision shape to every tile. Save it with path and/or put it on a TileMapLayer with assign_to.",
  inputShape: {
    texture: resourcePathField.describe("The tile sheet image."),
    tile_size: z
      .array(z.number().int().positive())
      .length(2)
      .optional()
      .describe("Pixels [width, height]. Default [16, 16]."),
    margins: z.array(z.number().int().min(0)).length(2).optional(),
    separation: z.array(z.number().int().min(0)).length(2).optional().describe("Pixels between tiles."),
    collision: z.boolean().optional(),
    skip_empty: z.boolean().optional().describe("Skip fully transparent cells. Default true."),
    path: resourcePathField.optional().describe('Save as a file, e.g. "res://tiles/world.tres".'),
    assign_to: layerField.optional(),
  },
  access: "write",
  editorMethod: "create_tileset",
});

export const setTilesTool = defineEditorTool({
  name: "set_tiles",
  title: "Place tiles",
  description:
    'Places and erases tiles on a TileMapLayer, in one undo step. Example (a floor and two blocks): {"node_path": "Ground", "rectangles": [{"from": [0, 10], "to": [29, 10], "atlas": [1, 0]}], "cells": [{"cell": [5, 9], "atlas": [2, 0]}, {"cell": [6, 9], "atlas": [2, 0]}]}. Cell [0, 0] is at the layer\'s origin; y grows downwards.',
  inputShape: {
    node_path: layerField,
    cells: z.array(z.object({ cell: cellField, ...tileChoiceShape })).optional(),
    rectangles: z
      .array(rectangleShape.extend(tileChoiceShape))
      .optional()
      .describe("Fill rectangles with one tile."),
    erase: z.array(cellField).optional().describe("Cells to empty."),
  },
  access: "write",
  editorMethod: "set_tiles",
});

export const paintTerrainTool = defineEditorTool({
  name: "paint_terrain",
  title: "Paint terrain",
  description:
    "Paints cells with a terrain of the TileSet; Godot chooses the matching edge and corner tiles, like the Terrains brush. mode path connects the cells in order (roads, rivers). Needs a TileSet with terrains (see get_tilemap_info).",
  inputShape: {
    node_path: layerField,
    cells: z.array(cellField).optional(),
    rectangle: rectangleShape.optional(),
    terrain_set: z.number().int().min(0).optional().describe("Default 0."),
    terrain: z
      .union([z.number().int().min(0), z.string()])
      .optional()
      .describe("Index or name. Default 0."),
    mode: z.enum(["connect", "path"]).optional(),
  },
  access: "write",
  editorMethod: "paint_terrain",
});

export const getTilesTool = defineEditorTool({
  name: "get_tiles",
  title: "Read tiles",
  description:
    "Shows the cells of a TileMapLayer as a text grid with a legend (one character per different tile, '.' empty), or as a list for large areas. Use it to see a level's layout.",
  inputShape: {
    node_path: layerField,
    rectangle: rectangleShape.optional().describe("Area to show. Default: every used cell."),
    as_list: z.boolean().optional(),
  },
  access: "read",
  editorMethod: "get_tiles",
});

export const TILEMAP_TOOLS = [
  getTilemapInfoTool,
  createTilesetTool,
  setTilesTool,
  paintTerrainTool,
  getTilesTool,
];

const layoutPresetField = z.enum([
  "full_rect",
  "center",
  "top_left",
  "top_right",
  "bottom_left",
  "bottom_right",
  "center_left",
  "center_top",
  "center_right",
  "center_bottom",
  "left_wide",
  "top_wide",
  "right_wide",
  "bottom_wide",
  "vcenter_wide",
  "hcenter_wide",
]);

const themeOverrideShape = {
  colors: z.record(z.string(), z.unknown()).optional().describe('e.g. {"font_color": "#ffcc00"}'),
  constants: z
    .record(z.string(), z.unknown())
    .optional()
    .describe('e.g. {"separation": 12, "margin_left": 8}'),
  font_sizes: z.record(z.string(), z.unknown()).optional().describe('e.g. {"font_size": 32}'),
  fonts: z.record(z.string(), z.unknown()).optional().describe('e.g. {"font": "res://fonts/pixel.ttf"}'),
  styles: z
    .record(z.string(), z.unknown())
    .optional()
    .describe(
      'e.g. {"panel": {"type": "StyleBoxFlat", "properties": {"bg_color": "#202030", "corner_radius_top_left": 8}}} or a .tres path.',
    ),
  icons: z.record(z.string(), z.unknown()).optional(),
};

export const getUiLayoutTool = defineEditorTool({
  name: "get_ui_layout",
  title: "Get UI layout",
  description:
    "Lists the Control nodes with their on-screen rectangle, anchors or container size flags, minimum size and text, and points out problems (zero size, off screen, text wider than its control).",
  inputShape: { node_path: nodePathField.optional().describe("Start here. Default: the scene root.") },
  access: "read",
  editorMethod: "get_ui_layout",
});

export const setLayoutPresetTool = defineEditorTool({
  name: "set_layout_preset",
  title: "Set layout preset",
  description:
    "Applies an anchor preset to Controls, like the editor's Layout menu: full_rect fills the parent, center centers, top_wide makes a top bar... Controls inside containers are placed by the container instead (use size flags).",
  inputShape: {
    node_paths: z.array(nodePathField).min(1),
    preset: layoutPresetField,
    resize_mode: z.enum(["minsize", "keep_width", "keep_height", "keep_size"]).optional(),
    margin: z.number().int().optional().describe("Pixels from the edges."),
  },
  access: "write",
  editorMethod: "set_layout_preset",
});

export const setThemeOverridesTool = defineEditorTool({
  name: "set_theme_overrides",
  title: "Set theme overrides",
  description:
    'Changes how one Control looks (font color and size, margins, panel style...) without a Theme. null removes an override. For the whole game\'s look, create a Theme with create_resource and edit items like "Button/colors/font_color" with set_resource_properties.',
  inputShape: { node_path: nodePathField, ...themeOverrideShape },
  access: "write",
  editorMethod: "set_theme_overrides",
});

/** One node of build_ui. Children have the same shape (checked by the addon). */
const uiNodeShape = z.object({
  type: z.string().describe('Node class ("Button", "VBoxContainer"...) or a scene path.'),
  name: z.string().optional(),
  properties: propertyValuesField.optional(),
  layout_preset: layoutPresetField.optional(),
  theme_overrides: z.object(themeOverrideShape).optional(),
  children: z
    .array(z.record(z.string(), z.unknown()))
    .optional()
    .describe(
      "Child nodes, each with the same fields (type, name, properties, layout_preset, theme_overrides, children).",
    ),
});

export const buildUiTool = defineEditorTool({
  name: "build_ui",
  title: "Build UI tree",
  description:
    'Creates a whole tree of nodes in one undo step: a menu, a HUD, a dialog. Works for any node types. Example: {"parent_path": "HUD", "nodes": [{"type": "MarginContainer", "name": "Menu", "layout_preset": "full_rect", "theme_overrides": {"constants": {"margin_left": 40}}, "children": [{"type": "VBoxContainer", "children": [{"type": "Label", "name": "Title", "properties": {"text": "My Game"}, "theme_overrides": {"font_sizes": {"font_size": 48}}}, {"type": "Button", "name": "Play", "properties": {"text": "Play"}}]}]}]}. Then connect_signal the buttons and check with get_ui_layout.',
  inputShape: {
    parent_path: nodePathField.optional().describe("Default: the scene root."),
    nodes: z.array(uiNodeShape).min(1),
  },
  access: "write",
  editorMethod: "build_ui",
});

export const UI_TOOLS = [getUiLayoutTool, setLayoutPresetTool, setThemeOverridesTool, buildUiTool];
