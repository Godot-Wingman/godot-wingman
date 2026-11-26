@tool
extends RefCounted
## Handlers of the "tilemap" toolset: TileSets (which tiles exist) and TileMapLayer nodes
## (which tile is in which cell), including terrain painting.
##
## Every change to the cells of a layer is one undo step: the layer's packed cell data is
## remembered before and after the change.

const WingmanError := preload("../utils/wingman_error.gd")
const ValueCodec := preload("../utils/value_codec.gd")

## Characters used to draw a layer as text; each different tile gets the next one.
const GRID_CHARACTERS := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789#@$%&*+=?!"
const MAXIMUM_GRID_CELLS := 6000
const MAXIMUM_GRID_WIDTH := 120
const MAXIMUM_LISTED_CELLS := 500
const MAXIMUM_LISTED_TILES_PER_SOURCE := 100

var _context: RefCounted


func _init(context: RefCounted) -> void:
	_context = context


func register_methods(dispatcher: RefCounted) -> void:
	dispatcher.register_method("get_tilemap_info", _get_tilemap_info)
	dispatcher.register_method("create_tileset", _create_tileset)
	dispatcher.register_method("set_tiles", _set_tiles)
	dispatcher.register_method("paint_terrain", _paint_terrain)
	dispatcher.register_method("get_tiles", _get_tiles)


func _get_tilemap_info(params: Dictionary) -> Variant:
	var tile_set: TileSet = null
	var result := {}
	if params.has("tileset_path"):
		var tileset_path := String(params["tileset_path"])
		if not ResourceLoader.exists(tileset_path):
			return WingmanError.new("FILE_NOT_FOUND", "No TileSet at '%s'." % tileset_path)
		tile_set = load(tileset_path) as TileSet
		if tile_set == null:
			return WingmanError.new("NOT_A_TILESET", "'%s' is not a TileSet." % tileset_path)
	else:
		var layer: Variant = _find_layer(String(params.get("node_path", "")))
		if layer is WingmanError:
			return layer
		tile_set = layer.tile_set
		var used_rect: Rect2i = layer.get_used_rect()
		result["node_path"] = _context.describe_node_path(layer)
		result["used_cells"] = layer.get_used_cells().size()
		result["used_rect"] = {"from": [used_rect.position.x, used_rect.position.y], "size": [used_rect.size.x, used_rect.size.y]}
		if tile_set == null:
			result["tile_set"] = null
			result["hint"] = "This layer has no TileSet. Make one from a tile sheet image with create_tileset."
			return result

	result["tile_size"] = [tile_set.tile_size.x, tile_set.tile_size.y]
	result["tile_shape"] = ["square", "isometric", "half_offset_square", "hexagon"][tile_set.tile_shape]
	result["physics_layers"] = tile_set.get_physics_layers_count()
	var terrain_sets: Array[Dictionary] = []
	for terrain_set_index in tile_set.get_terrain_sets_count():
		var terrain_names: Array[String] = []
		for terrain_index in tile_set.get_terrains_count(terrain_set_index):
			terrain_names.append("%d: %s" % [terrain_index, tile_set.get_terrain_name(terrain_set_index, terrain_index)])
		var mode_names := ["match_corners_and_sides", "match_corners", "match_sides"]
		terrain_sets.append({"terrain_set": terrain_set_index, "mode": mode_names[tile_set.get_terrain_set_mode(terrain_set_index)], "terrains": terrain_names})
	result["terrain_sets"] = terrain_sets

	var sources: Array[Dictionary] = []
	for source_index in tile_set.get_source_count():
		var source_id := tile_set.get_source_id(source_index)
		var source := tile_set.get_source(source_id)
		var source_description := {"source_id": source_id, "type": source.get_class()}
		if source is TileSetAtlasSource:
			var atlas_source: TileSetAtlasSource = source
			source_description["texture"] = atlas_source.texture.resource_path if atlas_source.texture != null else null
			source_description["grid_size"] = [atlas_source.get_atlas_grid_size().x, atlas_source.get_atlas_grid_size().y]
			source_description["tile_count"] = atlas_source.get_tiles_count()
			var tile_coordinates: Array[String] = []
			for tile_index in mini(atlas_source.get_tiles_count(), MAXIMUM_LISTED_TILES_PER_SOURCE):
				var atlas_coordinates := atlas_source.get_tile_id(tile_index)
				var tile_data := atlas_source.get_tile_data(atlas_coordinates, 0)
				var terrain_text := " terrain %d/%d" % [tile_data.terrain_set, tile_data.terrain] if tile_data != null and tile_data.terrain_set >= 0 and tile_data.terrain >= 0 else ""
				tile_coordinates.append("%d,%d%s" % [atlas_coordinates.x, atlas_coordinates.y, terrain_text])
			source_description["tiles"] = tile_coordinates
		elif source is TileSetScenesCollectionSource:
			var scene_source: TileSetScenesCollectionSource = source
			var scene_lines: Array[String] = []
			for scene_index in scene_source.get_scene_tiles_count():
				var scene_id := scene_source.get_scene_tile_id(scene_index)
				var packed_scene := scene_source.get_scene_tile_scene(scene_id)
				scene_lines.append("alternative %d: %s" % [scene_id, packed_scene.resource_path if packed_scene != null else "empty"])
			source_description["scenes"] = scene_lines
		sources.append(source_description)
	result["sources"] = sources
	return result


## Turns a tile sheet image into a TileSet: one atlas source whose tiles are the grid
## cells of the image (fully transparent cells are skipped), optionally with a square
## collision shape on every tile.
func _create_tileset(params: Dictionary) -> Variant:
	var texture_path := String(params.get("texture", ""))
	if not ResourceLoader.exists(texture_path):
		return WingmanError.new("FILE_NOT_FOUND", "No image at '%s'." % texture_path, "Use list_files with filter \"*.png\" to find tile sheets.")
	var texture := load(texture_path) as Texture2D
	if texture == null:
		return WingmanError.new("NOT_A_TEXTURE", "'%s' is not an image texture." % texture_path)
	var tile_size_conversion := ValueCodec.from_json_value(params.get("tile_size", [16, 16]), TYPE_VECTOR2I)
	if not tile_size_conversion["ok"]:
		return WingmanError.new("INVALID_TILE_SIZE", String(tile_size_conversion["error"]))
	var tile_size: Vector2i = tile_size_conversion["value"]
	if tile_size.x <= 0 or tile_size.y <= 0:
		return WingmanError.new("INVALID_TILE_SIZE", "tile_size must be positive, for example [16, 16].")
	var margins: Vector2i = ValueCodec.from_json_value(params.get("margins", [0, 0]), TYPE_VECTOR2I).get("value", Vector2i.ZERO)
	var separation: Vector2i = ValueCodec.from_json_value(params.get("separation", [0, 0]), TYPE_VECTOR2I).get("value", Vector2i.ZERO)

	var tile_set := TileSet.new()
	tile_set.tile_size = tile_size
	var atlas_source := TileSetAtlasSource.new()
	atlas_source.texture = texture
	atlas_source.texture_region_size = tile_size
	atlas_source.margins = margins
	atlas_source.separation = separation
	tile_set.add_source(atlas_source, 0)

	var with_collision := bool(params.get("collision", false))
	if with_collision:
		tile_set.add_physics_layer()
	var image := _read_texture_image(texture)
	var skip_empty_tiles := bool(params.get("skip_empty", true)) and image != null
	var grid_size := atlas_source.get_atlas_grid_size()
	var half_size := Vector2(tile_size) / 2.0
	var collision_square := PackedVector2Array([Vector2(-half_size.x, -half_size.y), Vector2(half_size.x, -half_size.y), Vector2(half_size.x, half_size.y), Vector2(-half_size.x, half_size.y)])
	var skipped_count := 0
	for row in grid_size.y:
		for column in grid_size.x:
			var atlas_coordinates := Vector2i(column, row)
			if skip_empty_tiles:
				var pixel_position := margins + atlas_coordinates * (tile_size + separation)
				if image.get_region(Rect2i(pixel_position, tile_size)).is_invisible():
					skipped_count += 1
					continue
			atlas_source.create_tile(atlas_coordinates)
			if with_collision:
				var tile_data := atlas_source.get_tile_data(atlas_coordinates, 0)
				tile_data.add_collision_polygon(0)
				tile_data.set_collision_polygon_points(0, 0, collision_square)

	var result := {"tile_size": [tile_size.x, tile_size.y], "grid_size": [grid_size.x, grid_size.y], "tiles": atlas_source.get_tiles_count(), "source_id": 0}
	if skipped_count > 0:
		result["skipped_empty_tiles"] = skipped_count
	if image == null:
		result["note"] = "The image pixels could not be read, so every grid cell became a tile."

	var save_path := String(params.get("path", ""))
	if save_path != "":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(save_path.get_base_dir()))
		var save_error := ResourceSaver.save(tile_set, save_path)
		if save_error != OK:
			return WingmanError.new("SAVE_FAILED", "Could not save '%s': %s." % [save_path, error_string(save_error)])
		tile_set.take_over_path(save_path)
		EditorInterface.get_resource_filesystem().update_file(save_path)
		result["saved"] = save_path

	if params.has("assign_to"):
		var layer: Variant = _find_layer(String(params["assign_to"]))
		if layer is WingmanError:
			return layer
		var undo_redo: EditorUndoRedoManager = _context.get_undo_redo()
		undo_redo.create_action("Assign TileSet", UndoRedo.MERGE_DISABLE, layer)
		undo_redo.add_do_property(layer, "tile_set", tile_set)
		undo_redo.add_undo_property(layer, "tile_set", layer.tile_set)
		undo_redo.commit_action()
		result["assigned_to"] = _context.describe_node_path(layer)
	return result


func _set_tiles(params: Dictionary) -> Variant:
	var layer: Variant = _find_layer_with_tileset(String(params.get("node_path", "")))
	if layer is WingmanError:
		return layer
	var tile_set: TileSet = layer.tile_set
	var default_source_id := tile_set.get_source_id(0) if tile_set.get_source_count() > 0 else -1

	# Everything is checked first, so a bad entry changes nothing.
	var placements: Array[Array] = []
	for cell_description: Variant in params.get("cells", []):
		if not cell_description is Dictionary:
			return WingmanError.new("INVALID_CELL", "Each cell looks like {\"cell\": [3, 5], \"atlas\": [0, 0]}.")
		var tile: Variant = _parse_tile(cell_description, tile_set, default_source_id)
		if tile is WingmanError:
			return tile
		var cell_conversion := ValueCodec.from_json_value(cell_description.get("cell"), TYPE_VECTOR2I)
		if not cell_conversion["ok"]:
			return WingmanError.new("INVALID_CELL", "Bad cell coordinates: %s" % cell_conversion["error"])
		placements.append([cell_conversion["value"], tile])
	for rectangle_description: Variant in params.get("rectangles", []):
		if not rectangle_description is Dictionary:
			return WingmanError.new("INVALID_RECTANGLE", "Each rectangle looks like {\"from\": [0, 10], \"to\": [19, 10], \"atlas\": [1, 0]}.")
		var tile: Variant = _parse_tile(rectangle_description, tile_set, default_source_id)
		if tile is WingmanError:
			return tile
		var rectangle: Variant = _parse_rectangle(rectangle_description)
		if rectangle is WingmanError:
			return rectangle
		for cell in _cells_in_rectangle(rectangle):
			placements.append([cell, tile])
	var erased_cells: Array[Vector2i] = []
	for erase_description: Variant in params.get("erase", []):
		var cell_conversion := ValueCodec.from_json_value(erase_description, TYPE_VECTOR2I)
		if not cell_conversion["ok"]:
			return WingmanError.new("INVALID_CELL", "Bad cell to erase: %s" % cell_conversion["error"])
		erased_cells.append(cell_conversion["value"])
	if placements.is_empty() and erased_cells.is_empty():
		return WingmanError.new("NOTHING_TO_DO", "Pass cells, rectangles or erase.")

	var data_before: PackedByteArray = layer.tile_map_data
	for cell in erased_cells:
		layer.erase_cell(cell)
	for placement in placements:
		var tile: Dictionary = placement[1]
		layer.set_cell(placement[0], tile["source_id"], tile["atlas"], tile["alternative"])
	_commit_cell_change(layer, data_before, "Set tiles")
	return {"placed": placements.size(), "erased": erased_cells.size(), "used_cells": layer.get_used_cells().size()}


## Paints cells with a terrain: Godot picks the right edge and corner tiles automatically.
func _paint_terrain(params: Dictionary) -> Variant:
	var layer: Variant = _find_layer_with_tileset(String(params.get("node_path", "")))
	if layer is WingmanError:
		return layer
	var tile_set: TileSet = layer.tile_set
	if tile_set.get_terrain_sets_count() == 0:
		return WingmanError.new("NO_TERRAINS", "The TileSet has no terrain sets.", "Terrains are set up in the TileSet editor (Terrains tab, then paint peering bits on tiles). Use set_tiles to place tiles by hand.")
	var terrain_set := int(params.get("terrain_set", 0))
	if terrain_set < 0 or terrain_set >= tile_set.get_terrain_sets_count():
		return WingmanError.new("INVALID_TERRAIN_SET", "terrain_set must be between 0 and %d." % (tile_set.get_terrain_sets_count() - 1))
	var terrain := -1
	var terrain_input: Variant = params.get("terrain", 0)
	if terrain_input is String and not String(terrain_input).is_valid_int():
		for terrain_index in tile_set.get_terrains_count(terrain_set):
			if tile_set.get_terrain_name(terrain_set, terrain_index) == terrain_input:
				terrain = terrain_index
		if terrain == -1:
			return WingmanError.new("TERRAIN_NOT_FOUND", "Terrain set %d has no terrain named '%s'." % [terrain_set, terrain_input], "Use get_tilemap_info to see the terrains.")
	else:
		terrain = int(terrain_input)

	var cells: Array[Vector2i] = []
	for cell_input: Variant in params.get("cells", []):
		var cell_conversion := ValueCodec.from_json_value(cell_input, TYPE_VECTOR2I)
		if not cell_conversion["ok"]:
			return WingmanError.new("INVALID_CELL", "Bad cell: %s" % cell_conversion["error"])
		cells.append(cell_conversion["value"])
	if params.get("rectangle") is Dictionary:
		var rectangle: Variant = _parse_rectangle(params["rectangle"])
		if rectangle is WingmanError:
			return rectangle
		cells.append_array(_cells_in_rectangle(rectangle))
	if cells.is_empty():
		return WingmanError.new("NOTHING_TO_DO", "Pass cells or a rectangle.")

	var data_before: PackedByteArray = layer.tile_map_data
	if String(params.get("mode", "connect")) == "path":
		layer.set_cells_terrain_path(cells, terrain_set, terrain)
	else:
		layer.set_cells_terrain_connect(cells, terrain_set, terrain)
	_commit_cell_change(layer, data_before, "Paint terrain")
	return {"painted": cells.size(), "terrain_set": terrain_set, "terrain": terrain, "used_cells": layer.get_used_cells().size()}


## The cells of a layer, drawn as a text grid with a legend when the area is small.
func _get_tiles(params: Dictionary) -> Variant:
	var layer: Variant = _find_layer(String(params.get("node_path", "")))
	if layer is WingmanError:
		return layer
	var area: Rect2i = layer.get_used_rect()
	if params.get("rectangle") is Dictionary:
		var rectangle: Variant = _parse_rectangle(params["rectangle"])
		if rectangle is WingmanError:
			return rectangle
		area = rectangle
	var result := {"node_path": _context.describe_node_path(layer), "area": {"from": [area.position.x, area.position.y], "to": [area.end.x - 1, area.end.y - 1]}}
	if area.size.x <= 0 or area.size.y <= 0:
		result["cells"] = 0
		return result

	var characters_by_tile := {}
	var legend := {}
	var listed_cells: Array[String] = []
	var cell_count := 0
	var draw_grid := area.size.x * area.size.y <= MAXIMUM_GRID_CELLS and area.size.x <= MAXIMUM_GRID_WIDTH and not bool(params.get("as_list", false))
	var grid_rows: Array[String] = []
	for row in range(area.position.y, area.end.y):
		var row_text := ""
		for column in range(area.position.x, area.end.x):
			var cell := Vector2i(column, row)
			var source_id: int = layer.get_cell_source_id(cell)
			if source_id == -1:
				row_text += "."
				continue
			cell_count += 1
			var atlas_coordinates: Vector2i = layer.get_cell_atlas_coords(cell)
			var alternative: int = layer.get_cell_alternative_tile(cell)
			var tile_key := "source %d atlas %d,%d%s" % [source_id, atlas_coordinates.x, atlas_coordinates.y, "" if alternative == 0 else " alternative %d" % alternative]
			if draw_grid:
				if not characters_by_tile.has(tile_key):
					var character_index := characters_by_tile.size()
					characters_by_tile[tile_key] = GRID_CHARACTERS[character_index] if character_index < GRID_CHARACTERS.length() else "~"
					legend[characters_by_tile[tile_key]] = tile_key
				row_text += characters_by_tile[tile_key]
			elif listed_cells.size() < MAXIMUM_LISTED_CELLS:
				listed_cells.append("%d,%d: %s" % [column, row, tile_key])
		if draw_grid:
			grid_rows.append(row_text)
	result["cells"] = cell_count
	if draw_grid:
		result["grid"] = "\n".join(grid_rows)
		result["grid_note"] = "Row 1 is y=%d, column 1 is x=%d. '.' is empty." % [area.position.y, area.position.x]
		result["legend"] = legend
	else:
		result["list"] = listed_cells
		if cell_count > listed_cells.size():
			result["not_listed"] = cell_count - listed_cells.size()
	return result


func _commit_cell_change(layer: TileMapLayer, data_before: PackedByteArray, action_name: String) -> void:
	var data_after: PackedByteArray = layer.tile_map_data
	var undo_redo: EditorUndoRedoManager = _context.get_undo_redo()
	undo_redo.create_action(action_name, UndoRedo.MERGE_DISABLE, layer)
	undo_redo.add_do_property(layer, "tile_map_data", data_after)
	undo_redo.add_undo_property(layer, "tile_map_data", data_before)
	undo_redo.commit_action()


## {"source_id", "atlas", "alternative"} from a cell or rectangle description.
func _parse_tile(description: Dictionary, tile_set: TileSet, default_source_id: int) -> Variant:
	var source_id := int(description.get("source_id", default_source_id))
	if not tile_set.has_source(source_id):
		return WingmanError.new("SOURCE_NOT_FOUND", "The TileSet has no source %d." % source_id, "Use get_tilemap_info to see the sources and their tiles.")
	var atlas_conversion := ValueCodec.from_json_value(description.get("atlas", [0, 0]), TYPE_VECTOR2I)
	if not atlas_conversion["ok"]:
		return WingmanError.new("INVALID_ATLAS", "Bad atlas coordinates: %s" % atlas_conversion["error"])
	var atlas_coordinates: Vector2i = atlas_conversion["value"]
	var alternative := int(description.get("alternative", 0))
	var source := tile_set.get_source(source_id)
	if source is TileSetAtlasSource and not source.has_tile(atlas_coordinates):
		return WingmanError.new("TILE_NOT_FOUND", "Source %d has no tile at atlas %d,%d." % [source_id, atlas_coordinates.x, atlas_coordinates.y], "Use get_tilemap_info to see which atlas coordinates exist.")
	return {"source_id": source_id, "atlas": atlas_coordinates, "alternative": alternative}


## {"from": [x, y], "to": [x, y]} (both corners included) as a Rect2i.
func _parse_rectangle(description: Dictionary) -> Variant:
	var from_conversion := ValueCodec.from_json_value(description.get("from"), TYPE_VECTOR2I)
	var to_conversion := ValueCodec.from_json_value(description.get("to"), TYPE_VECTOR2I)
	if not from_conversion["ok"] or not to_conversion["ok"]:
		return WingmanError.new("INVALID_RECTANGLE", "A rectangle needs from and to corners, for example {\"from\": [0, 0], \"to\": [9, 3]}.")
	var first_corner: Vector2i = from_conversion["value"]
	var second_corner: Vector2i = to_conversion["value"]
	var top_left := Vector2i(mini(first_corner.x, second_corner.x), mini(first_corner.y, second_corner.y))
	var bottom_right := Vector2i(maxi(first_corner.x, second_corner.x), maxi(first_corner.y, second_corner.y))
	return Rect2i(top_left, bottom_right - top_left + Vector2i.ONE)


func _cells_in_rectangle(rectangle: Rect2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for row in range(rectangle.position.y, rectangle.end.y):
		for column in range(rectangle.position.x, rectangle.end.x):
			cells.append(Vector2i(column, row))
	return cells


func _find_layer(node_path: String) -> Variant:
	var node: Variant = _context.find_node_in_edited_scene(node_path)
	if node is WingmanError:
		return node
	if node.get_class() == "TileMap":
		return WingmanError.new("OLD_TILEMAP_NODE", "%s is the old TileMap node." % node.name, "Select it in the editor and use the TileMap panel's \"Extract TileMap layers as individual TileMapLayer nodes\", or add a TileMapLayer node.")
	if not node is TileMapLayer:
		return WingmanError.new("NOT_A_TILEMAP_LAYER", "%s is a %s, not a TileMapLayer." % [node.name, node.get_class()], "Add one with add_node (type TileMapLayer).")
	return node


func _find_layer_with_tileset(node_path: String) -> Variant:
	var layer: Variant = _find_layer(node_path)
	if layer is WingmanError:
		return layer
	if layer.tile_set == null:
		return WingmanError.new("NO_TILESET", "%s has no TileSet." % layer.name, "Make one with create_tileset (assign_to this layer).")
	return layer


## The pixels of a texture, or null when they cannot be read (then no tile is skipped).
func _read_texture_image(texture: Texture2D) -> Image:
	var image: Image = texture.get_image()
	if (image == null or image.is_empty()) and texture.resource_path.get_extension() in ["png", "jpg", "jpeg", "webp", "svg", "bmp", "tga"]:
		image = Image.load_from_file(ProjectSettings.globalize_path(texture.resource_path))
	if image == null or image.is_empty():
		return null
	if image.is_compressed():
		image.decompress()
	return image
