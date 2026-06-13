extends TileMapLayer
class_name HexMap


const MAP_W := 30
const MAP_H := 20
const MAP_PADDING := 2
const RENDERED_MAP_W := MAP_W + (MAP_PADDING * 2)
const RENDERED_MAP_H := MAP_H + (MAP_PADDING * 2)
const TILE_DATA_PATH := "res://data/tile_properties.csv"
const RIVER_PROPERTIES_PATH := "res://data/river_properties.csv"
const CITY_REGISTRY_PATH := "res://data/cities.json"

const SOURCE_RURAL := 0
const SOURCE_HILL := 2
const SOURCE_MOUNTAIN := 4
const SOURCE_SEA := 5
const SOURCE_URBAN := 6
const SOURCE_DEEP_SEA := 53
const ROAD_WIDTH := 5.0
const ARTERIAL_WIDTH := 5.0
const ROAD_GRID_WIDTH := 5.0
const ROAD_GRID_SIZE := Vector2(60, 40)
const TILE_CENTER := Vector2(270, 240)

const HSM_POINTS := {
	"HSM1": Vector2(270, 0),
	"HSM2": Vector2(472.5, 120),
	"HSM3": Vector2(472.5, 360),
	"HSM4": Vector2(270, 480),
	"HSM5": Vector2(67.5, 360),
	"HSM6": Vector2(67.5, 120),
}
const HSM_ORDER := ["HSM1", "HSM2", "HSM3", "HSM4", "HSM5", "HSM6"]

signal tile_selected(tile_data)
signal stockpile_destination_selected(tile_data)
signal survey_tile_clicked(tile_data)

var tiles := {}  # Vector2i(q, r) -> Dictionary
var river_properties := {}
var cities := {}
var _stockpile_destination_selection_active := false
var _hovered_destination_coord := Vector2i(-1, -1)
var _selection_paint := true  # false = capture clicks only, no terrain category/hover overlays
var _hover_overlay: TileMapLayer = null
var _overlay_consumer: TileMapLayer = null   # light green — tiles that consume the stockpile good
var _overlay_viable: TileMapLayer = null     # dark green — tiles with buildings but not consuming
var _overlay_neutral: TileMapLayer = null    # dark grey — all other tiles
const TILE_HIGHLIGHT_ALPHA := 0.5

func _enter_tree() -> void:
	add_to_group("hex_map")

func _ready() -> void:
	_generate_tile_data()
	_load_tile_overrides()
	river_properties = _load_river_properties()
	cities = _load_cities()
	_sync_tile_types_from_existing_map()
	_build_prototype_map()
	_build_hover_overlay()
	_build_category_overlays()

func begin_stockpile_destination_selection(good_id: String = "", paint: bool = true) -> void:
	_stockpile_destination_selection_active = true
	_selection_paint = paint
	if paint:
		_paint_stockpile_categories(good_id)
		_update_destination_hover()
	else:
		_clear_category_overlays()
		_clear_destination_hover()

func end_stockpile_destination_selection() -> void:
	_stockpile_destination_selection_active = false
	_clear_destination_hover()
	_clear_category_overlays()

func _build_hover_overlay() -> void:
	_hover_overlay = TileMapLayer.new()
	_hover_overlay.name = "StockpileDestinationHover"
	_hover_overlay.tile_set = tile_set
	_hover_overlay.modulate = Color(1.55, 1.55, 1.35, TILE_HIGHLIGHT_ALPHA)
	_hover_overlay.z_index = 22
	_hover_overlay.enabled = true
	add_child(_hover_overlay)

func _build_category_overlays() -> void:
	_overlay_consumer = _make_tinted_overlay("StockpileConsumer", Color(0.35, 1.0, 0.35, TILE_HIGHLIGHT_ALPHA), 10)
	_overlay_viable   = _make_tinted_overlay("StockpileViable",   Color(0.1,  0.45, 0.1,  TILE_HIGHLIGHT_ALPHA), 10)
	_overlay_neutral  = _make_tinted_overlay("StockpileNeutral",  Color(0.25, 0.25, 0.25, TILE_HIGHLIGHT_ALPHA), 10)

func _make_tinted_overlay(overlay_name: String, color: Color, z: int) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = overlay_name
	layer.tile_set = tile_set
	layer.modulate = color
	layer.z_index = z
	layer.enabled = true
	layer.visible = false
	add_child(layer)
	return layer

func _paint_stockpile_categories(good_id: String) -> void:
	_overlay_consumer.clear()
	_overlay_viable.clear()
	_overlay_neutral.clear()
	_overlay_consumer.visible = true
	_overlay_viable.visible = true
	_overlay_neutral.visible = true

	for coord in tiles:
		var tile_data: Dictionary = tiles[coord]
		var tile_id: String = tile_data.get("id", "")
		var map_coord := map_coord_for_tile_coord(coord)
		var src := _source_for_tile_type(tile_data.get("type", ""))

		if good_id != "" and _tile_consumes_good(tile_id, good_id):
			_overlay_consumer.set_cell(map_coord, src, Vector2i.ZERO)
		elif _tile_has_buildings(tile_id):
			_overlay_viable.set_cell(map_coord, src, Vector2i.ZERO)
		else:
			_overlay_neutral.set_cell(map_coord, src, Vector2i.ZERO)

func _clear_category_overlays() -> void:
	for layer in [_overlay_consumer, _overlay_viable, _overlay_neutral]:
		if layer != null:
			layer.clear()
			layer.visible = false

func _tile_consumes_good(tile_id: String, good_id: String) -> bool:
	var instance_ids: Array = MatchState.tile_buildings.get(tile_id, [])
	for instance_id in instance_ids:
		var building: Dictionary = MatchState.buildings.get(instance_id, {})
		var recipe: Dictionary = Catalog.get_recipe(building.get("recipe_id", ""))
		var inputs: Array = recipe.get("inputs", [])
		for inp in inputs:
			if inp.get("good_id", "") == good_id:
				return true
	return false

func _tile_has_buildings(tile_id: String) -> bool:
	return MatchState.tile_buildings.get(tile_id, []).size() > 0

func _process(_delta: float) -> void:
	# Track the hovered tile whenever a selection is active (so the logistics
	# overlay's hover info can read it). Only PAINT the terrain hover when painting.
	if _stockpile_destination_selection_active:
		_update_destination_hover()

func _update_destination_hover() -> void:
	var coord := _tile_coord_under_mouse()
	if not tiles.has(coord):
		coord = Vector2i(-1, -1)
	if coord == _hovered_destination_coord:
		return
	_hovered_destination_coord = coord
	if not _selection_paint:
		return  # tracking only — no terrain hover overlay (transfer / buy / sell flows)
	if _hover_overlay != null:
		_hover_overlay.clear()
	if coord != Vector2i(-1, -1):
		var tile_data: Dictionary = tiles[coord]
		_hover_overlay.set_cell(map_coord_for_tile_coord(coord), _source_for_tile_type(tile_data.get("type", "")), Vector2i.ZERO)

func _clear_destination_hover() -> void:
	if _hover_overlay != null:
		_hover_overlay.clear()
	_hovered_destination_coord = Vector2i(-1, -1)

func map_coord_for_tile_coord(coord: Vector2i) -> Vector2i:
	return coord + Vector2i(MAP_PADDING, MAP_PADDING)

func tile_coord_for_map_coord(map_coord: Vector2i) -> Vector2i:
	return map_coord - Vector2i(MAP_PADDING, MAP_PADDING)

func get_hovered_destination_tile_id() -> String:
	# The tile currently under the mouse while a destination selection is active ("" otherwise).
	if not _stockpile_destination_selection_active or _hovered_destination_coord == Vector2i(-1, -1):
		return ""
	return "tile_%d_%d" % [_hovered_destination_coord.x + 1, _hovered_destination_coord.y + 1]

func map_center_world() -> Vector2:
	return map_world_rect().get_center()

func map_world_rect() -> Rect2:
	return _world_rect_for_cells(get_used_cells())

func playable_world_rect() -> Rect2:
	var playable_cells: Array[Vector2i] = []
	for y in MAP_H:
		for x in MAP_W:
			playable_cells.append(map_coord_for_tile_coord(Vector2i(x, y)))
	return _world_rect_for_cells(playable_cells)

func _world_rect_for_cells(cells: Array[Vector2i]) -> Rect2:
	if cells.is_empty():
		return Rect2(Vector2.ZERO, Vector2.ZERO)
	var tile_size := Vector2(tile_set.tile_size) if tile_set != null else Vector2(540, 480)
	var first: Vector2 = map_to_local(cells[0])
	var min_pos := first
	var max_pos := first
	for cell in cells:
		var pos := map_to_local(cell)
		min_pos.x = minf(min_pos.x, pos.x)
		min_pos.y = minf(min_pos.y, pos.y)
		max_pos.x = maxf(max_pos.x, pos.x)
		max_pos.y = maxf(max_pos.y, pos.y)
	min_pos -= tile_size * 0.5
	max_pos += tile_size * 0.5
	return Rect2(min_pos, max_pos - min_pos)

func _build_prototype_map() -> void:
	clear()
	for y in RENDERED_MAP_H:
		for x in RENDERED_MAP_W:
			set_cell(Vector2i(x, y), SOURCE_SEA, Vector2i.ZERO)
	for coord in tiles:
		var tile_data: Dictionary = tiles[coord]
		set_cell(map_coord_for_tile_coord(coord), _source_for_tile_type(tile_data.get("type", "")), Vector2i.ZERO)
	_paint_north_decoration()
	_paint_sea_frame()

# Land columns of the top-row decoration (cols 5..28); hills are sprinkled on top.
const NORTH_LAND_FROM := 5
const NORTH_LAND_TO := 28
# Hills bounded to cols 5..21: three on the top row's left coast, a few more on
# the row below.
const NORTH_TOP_HILLS := [5, 6, 7]
const NORTH_LOW_HILLS := [7, 10]
# Mountains and a small sea inlet on the north edge. Outer row = "2 tiles north"
# (y=0), inner row = "1 tile north" (y=1).
const NORTH_TOP_MTN := [11, 18]                # 2 tiles north of 11_1; mountains north of 18_1
const NORTH_LOW_MTN := [11, 12, 13, 18]        # 1 mountain north of 11_1/12_1/13_1; and 18_1
const NORTH_SEA := [14, 15]                     # sea north of 14_1 and 15_1

# Hand-painted scenery on the unclickable border rows above the playable map.
# The north edge is a rural coast (col C sits at cell x = C+1); the far west/east
# stay sea and step out to the deep-sea frame painted by _paint_sea_frame().
func _paint_north_decoration() -> void:
	# Coastal shallow sea west of col 5 and east of col 28.
	for col in range(1, NORTH_LAND_FROM):
		_set_north_cell(col, 0, SOURCE_SEA)
		_set_north_cell(col, 1, SOURCE_SEA)
	for col in range(NORTH_LAND_TO + 1, MAP_W + 1):
		_set_north_cell(col, 0, SOURCE_SEA)
		_set_north_cell(col, 1, SOURCE_SEA)
	# Rural land across both border rows.
	for col in range(NORTH_LAND_FROM, NORTH_LAND_TO + 1):
		_set_north_cell(col, 0, SOURCE_RURAL)
		_set_north_cell(col, 1, SOURCE_RURAL)
	# Hills (bounded to cols 5..21).
	for col in NORTH_TOP_HILLS:
		_set_north_cell(col, 0, SOURCE_HILL)
	for col in NORTH_LOW_HILLS:
		_set_north_cell(col, 1, SOURCE_HILL)
	# Mountains and the sea inlet (override the rural base).
	for col in NORTH_TOP_MTN:
		_set_north_cell(col, 0, SOURCE_MOUNTAIN)
	for col in NORTH_LOW_MTN:
		_set_north_cell(col, 1, SOURCE_MOUNTAIN)
	for col in NORTH_SEA:
		_set_north_cell(col, 0, SOURCE_SEA)
		_set_north_cell(col, 1, SOURCE_SEA)

func _set_north_cell(col: int, row: int, src: int) -> void:
	set_cell(Vector2i(col + 1, row), src, Vector2i.ZERO)

# The two left + two right decorative columns are deep sea, except a ~10-tile
# shallow-sea inlet at the bottom of the east columns that joins the shallow sea
# at tiles 30_16 / 30_17 (the east edge; "bottom-left" in the request reads as
# the corner next to those tiles).
func _paint_sea_frame() -> void:
	var left_a := 0
	var left_b := 1
	var right_a := RENDERED_MAP_W - 2   # x = 32
	var right_b := RENDERED_MAP_W - 1   # x = 33
	for y in RENDERED_MAP_H:
		set_cell(Vector2i(left_a, y), SOURCE_DEEP_SEA, Vector2i.ZERO)
		set_cell(Vector2i(left_b, y), SOURCE_DEEP_SEA, Vector2i.ZERO)
		set_cell(Vector2i(right_a, y), SOURCE_DEEP_SEA, Vector2i.ZERO)
		set_cell(Vector2i(right_b, y), SOURCE_DEEP_SEA, Vector2i.ZERO)
	# The bottom two decorative rows are deep sea.
	for x in RENDERED_MAP_W:
		set_cell(Vector2i(x, RENDERED_MAP_H - 2), SOURCE_DEEP_SEA, Vector2i.ZERO)
		set_cell(Vector2i(x, RENDERED_MAP_H - 1), SOURCE_DEEP_SEA, Vector2i.ZERO)
	# Shallow inlet: east columns, rows abreast of 30_16 (cell y=17) and 30_17 (y=18).
	for y in range(16, 21):
		set_cell(Vector2i(right_a, y), SOURCE_SEA, Vector2i.ZERO)
		set_cell(Vector2i(right_b, y), SOURCE_SEA, Vector2i.ZERO)

func _source_for_tile_type(tile_type: String) -> int:
	match tile_type:
		"rural", "grass":
			return SOURCE_RURAL
		"hill":
			return SOURCE_HILL
		"mountain":
			return SOURCE_MOUNTAIN
		"deep_sea":
			return SOURCE_DEEP_SEA
		"urban":
			return SOURCE_URBAN
		"sea", _:
			return SOURCE_SEA

func _tile_type_for_source(source_id: int) -> String:
	match source_id:
		SOURCE_RURAL:
			return "rural"
		SOURCE_HILL:
			return "hill"
		SOURCE_MOUNTAIN:
			return "mountain"
		SOURCE_DEEP_SEA:
			return "deep_sea"
		SOURCE_URBAN:
			return "urban"
		SOURCE_SEA:
			return "sea"
		_:
			return ""

func _sync_tile_types_from_existing_map() -> void:
	var used_cells := get_used_cells()
	if used_cells.is_empty():
		return

	var uses_padded_layout := _existing_map_uses_padded_layout(used_cells)
	for coord in tiles:
		var source_coord: Vector2i = map_coord_for_tile_coord(coord) if uses_padded_layout else coord
		var source_id := get_cell_source_id(source_coord)
		var tile_type := _tile_type_for_source(source_id)
		if tile_type != "":
			tiles[coord].type = tile_type

func _existing_map_uses_padded_layout(used_cells: Array[Vector2i]) -> bool:
	var used := {}
	for cell in used_cells:
		used[cell] = true

	for y in RENDERED_MAP_H:
		for x in RENDERED_MAP_W:
			if not used.has(Vector2i(x, y)):
				return false
	return true

func _generate_tile_data() -> void:
	for r in MAP_H:
		for q in MAP_W:
			var coord := Vector2i(q, r)
			tiles[coord] = _make_default_tile(q, r)

func _make_default_tile(q: int, r: int) -> Dictionary:
	var col := q + 1
	var row := r + 1
	return {
		"id": "tile_%d_%d" % [col, row],
		"nickname": "",
		"coord": Vector2i(q, r),
		"type": "",
		"deposits": [],
		"solar_potential": 0,
		"wind_potential": 0,
		"build_capacity": 0,
		"buildings_present": [],
		"tile_price": 0,
		"infrastructure_present": [],
		"has_river": false,
		"river_type": "",
		"road_type": "",
		"road_hsms": [],
		"road_density": "",
		"city_id": "",
		"city_name": "",
		"tile_role": "",
		"road_seed": _default_road_seed(q, r),
	}

func _load_tile_overrides() -> void:
	if not FileAccess.file_exists(TILE_DATA_PATH):
		push_warning("CSV not found at %s — using placeholder data for all tiles." % TILE_DATA_PATH)
		return

	var file := FileAccess.open(TILE_DATA_PATH, FileAccess.READ)
	if file == null:
		push_warning("Could not open %s — using placeholder data." % TILE_DATA_PATH)
		return

	var header := file.get_csv_line()
	if header.size() == 0:
		push_warning("CSV is empty — using placeholder data.")
		return

	var rows_loaded := 0
	var rows_failed := 0
	var line_num := 1  # header is line 1

	while not file.eof_reached():
		line_num += 1
		var row: PackedStringArray = file.get_csv_line()
		if row.size() == 0 or (row.size() == 1 and row[0] == ""):
			continue

		var parsed := _parse_csv_row(header, row, line_num)
		if parsed.is_empty():
			rows_failed += 1
			continue

		var coord := id_to_coord(parsed.id)
		if coord == Vector2i(-1, -1):
			push_warning("Line %d: bad id '%s' — skipping." % [line_num, parsed.id])
			rows_failed += 1
			continue

		parsed.coord = coord
		if int(parsed.get("road_seed", 0)) == 0:
			parsed.road_seed = _default_road_seed(coord.x, coord.y)
		tiles[coord] = parsed
		rows_loaded += 1

	file.close()
	print("Loaded %d tile overrides from CSV (%d failed)." % [rows_loaded, rows_failed])

func _load_river_properties() -> Dictionary:
	var result: Dictionary = {}
	if not FileAccess.file_exists(RIVER_PROPERTIES_PATH):
		push_warning("River properties CSV not found at %s." % RIVER_PROPERTIES_PATH)
		return result

	var file := FileAccess.open(RIVER_PROPERTIES_PATH, FileAccess.READ)
	if file == null:
		push_warning("Could not open %s." % RIVER_PROPERTIES_PATH)
		return result

	var header: PackedStringArray = file.get_csv_line()
	while not file.eof_reached():
		var row: PackedStringArray = file.get_csv_line()
		if row.size() == 0 or (row.size() == 1 and row[0] == ""):
			continue
		if row.size() != header.size():
			continue

		var river_data: Dictionary = {}
		for i in range(header.size()):
			river_data[header[i]] = row[i]
		result[river_data["river_type"]] = river_data

	file.close()
	return result

func _load_cities() -> Dictionary:
	var result: Dictionary = {}
	if not FileAccess.file_exists(CITY_REGISTRY_PATH):
		return result

	var file := FileAccess.open(CITY_REGISTRY_PATH, FileAccess.READ)
	if file == null:
		push_warning("Could not open %s." % CITY_REGISTRY_PATH)
		return result

	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("City registry JSON did not parse to a dictionary.")
		return result

	var parsed_dictionary: Dictionary = parsed
	return parsed_dictionary

func _parse_csv_row(header: PackedStringArray, row: PackedStringArray, line_num: int) -> Dictionary:
	if row.size() != header.size():
		push_warning("Line %d: column count mismatch (got %d, expected %d) — skipping." % [line_num, row.size(), header.size()])
		return {}

	var result := {}
	for i in header.size():
		var key := header[i].strip_edges()
		var value := row[i].strip_edges()

		match key:
			"id", "nickname", "type", "road_type", "road_density", "city_id", "city_name", "tile_role":
				result[key] = value
			"has_river":
				result[key] = value.to_lower() == "true" or value == "1"
			"river_type":
				result[key] = value
			"deposits", "buildings_present", "infrastructure_present", "road_hsms":
				result[key] = [] if value == "" else Array(value.split("|"))
			"solar_potential", "wind_potential", "build_capacity", "tile_price", "road_seed":
				result[key] = 0 if value == "" else int(value)
			_:
				push_warning("Line %d: unknown column '%s' — ignoring." % [line_num, key])

	return result

func _default_road_seed(q: int, r: int) -> int:
	return abs((q + 1) * 73856093 ^ (r + 1) * 19349663)

func id_to_coord(id: String) -> Vector2i:
	var parts := id.split("_")
	if parts.size() != 3 or parts[0] != "tile":
		return Vector2i(-1, -1)
	if not parts[1].is_valid_int() or not parts[2].is_valid_int():
		return Vector2i(-1, -1)
	return Vector2i(int(parts[1]) - 1, int(parts[2]) - 1)

func _tile_coord_under_mouse() -> Vector2i:
	var world_pos := get_global_mouse_position()
	return tile_coord_for_map_coord(local_to_map(to_local(world_pos)))

func tile_id_under_mouse() -> String:
	# "tile_X_Y" for the tile under the cursor, or "" if the cursor isn't over a tile.
	var coord := _tile_coord_under_mouse()
	if not tiles.has(coord):
		return ""
	return "tile_%d_%d" % [coord.x + 1, coord.y + 1]

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return

	if event.button_index == MOUSE_BUTTON_RIGHT:
		var handled := false
		if _stockpile_destination_selection_active:
			MatchState.cancel_output_stockpile_selection()
			end_stockpile_destination_selection()
			handled = true
		if BuildMode.is_active:
			BuildMode.exit_build_mode()
			handled = true
		if MapMode.is_active():
			MapMode.exit_mode()
			handled = true
		if handled:
			get_viewport().set_input_as_handled()
		return

	# Left-click logic unchanged
	if event.button_index == MOUSE_BUTTON_LEFT:
		var map_pos := _tile_coord_under_mouse()

		if not tiles.has(map_pos):
			return

		var tile_data: Dictionary = tiles[map_pos]

		if _stockpile_destination_selection_active:
			stockpile_destination_selected.emit(tile_data)
			end_stockpile_destination_selection()
			get_viewport().set_input_as_handled()
		elif MapMode.current_mode == MapMode.Mode.SURVEYING:
			survey_tile_clicked.emit(tile_data)
			get_viewport().set_input_as_handled()
		elif BuildMode.is_active:
			BuildMode.attempt_build(tile_data.id)
		else:
			tile_selected.emit(tile_data)

func _river_data_for_tile(tile_data: Dictionary) -> Dictionary:
	if not tile_data.get("has_river", false):
		return {}
	var river_type: String = str(tile_data.get("river_type", ""))
	if river_type == "" or not river_properties.has(river_type):
		return {}
	var river_data: Dictionary = river_properties[river_type]
	return river_data


func _tile_has_roads(tile_data: Dictionary) -> bool:
	var infrastructure: Array = tile_data.get("infrastructure_present", [])
	return infrastructure.has("roads")

func _road_hsms_for_tile(tile_coord: Vector2i) -> Array[String]:
	var tile_data: Dictionary = tiles[tile_coord]
	var explicit: Array = tile_data.get("road_hsms", [])
	if not explicit.is_empty():
		var explicit_result: Array[String] = []
		for hsm in explicit:
			var hsm_name: String = str(hsm)
			if HSM_ORDER.has(hsm_name) and _road_hsm_is_valid_land_connection(tile_coord, hsm_name):
				explicit_result.append(hsm_name)
		return explicit_result

	var result: Array[String] = []
	for hsm in HSM_ORDER:
		var neighbor_coord: Vector2i = tile_coord + _neighbor_offset_for_hsm(tile_coord, hsm)
		if _road_hsm_is_valid_land_connection(tile_coord, hsm) and tiles.has(neighbor_coord) and _tile_has_roads(tiles[neighbor_coord]):
			result.append(hsm)
	return result

func _road_hsm_is_valid_land_connection(tile_coord: Vector2i, hsm: String) -> bool:
	if not tiles.has(tile_coord):
		return false
	var tile_data: Dictionary = tiles[tile_coord]
	if not _tile_is_land(tile_data):
		return false
	var neighbor_coord: Vector2i = tile_coord + _neighbor_offset_for_hsm(tile_coord, hsm)
	if not tiles.has(neighbor_coord):
		return false
	var neighbor_data: Dictionary = tiles[neighbor_coord]
	return _tile_is_land(neighbor_data)

func _tile_is_land(tile_data: Dictionary) -> bool:
	var tile_type: String = str(tile_data.get("type", "")).strip_edges()
	return tile_type != "" and tile_type != "sea" and tile_type != "deep_sea"

func _road_segment(start: Vector2, end: Vector2, width: float) -> Dictionary:
	return {
		"start": start,
		"end": end,
		"width": width,
	}

func _hsm_local(hsm: String) -> Vector2:
	return HSM_POINTS[hsm]

func _adjacent_hsm_pairs(road_hsms: Array[String]) -> Array[Dictionary]:
	var pairs: Array[Dictionary] = []
	for i in range(road_hsms.size()):
		for j in range(i + 1, road_hsms.size()):
			if _hsms_are_adjacent(road_hsms[i], road_hsms[j]):
				pairs.append({
					"a": road_hsms[i],
					"b": road_hsms[j],
					"score": _hsm_adjacency_score(road_hsms[i], road_hsms[j]),
				})
	pairs.sort_custom(_sort_adjacent_pair)
	return pairs

func _hsms_are_adjacent(a: String, b: String) -> bool:
	var index_a: int = HSM_ORDER.find(a)
	var index_b: int = HSM_ORDER.find(b)
	if index_a < 0 or index_b < 0:
		return false
	var distance: int = abs(index_a - index_b)
	return distance == 1 or distance == HSM_ORDER.size() - 1

func _hsm_adjacency_score(a: String, b: String) -> int:
	var index_a: int = HSM_ORDER.find(a)
	var index_b: int = HSM_ORDER.find(b)
	return mini(abs(index_a - index_b), HSM_ORDER.size() - abs(index_a - index_b))

func _sort_adjacent_pair(a: Dictionary, b: Dictionary) -> bool:
	return int(a["score"]) < int(b["score"])

func _junction_point_for_pair(anchor_a: Vector2, anchor_b: Vector2) -> Vector2:
	var edge_midpoint: Vector2 = (anchor_a + anchor_b) * 0.5
	return edge_midpoint.lerp(TILE_CENTER, 0.34)

func _arterial_fallback_destination(pair_a: String, pair_b: String, junction: Vector2) -> Vector2:
	var local_pair_a: Vector2 = _hsm_local(pair_a)
	var local_pair_b: Vector2 = _hsm_local(pair_b)
	var average_hsm: Vector2 = (local_pair_a + local_pair_b) * 0.5
	var inward: Vector2 = (TILE_CENTER - average_hsm).normalized()
	var local_destination: Vector2 = TILE_CENTER + inward * 135.0
	return local_destination.lerp(junction, 0.15)

func _default_road_grid_rect() -> Rect2:
	return Rect2(Vector2(240, 220), ROAD_GRID_SIZE)

func _add_grid_segments(segments: Array[Dictionary], grid_rect: Rect2) -> void:
	var left: float = grid_rect.position.x
	var right: float = grid_rect.end.x
	var top: float = grid_rect.position.y
	var bottom: float = grid_rect.end.y
	var mid_y: float = grid_rect.position.y + grid_rect.size.y * 0.5
	var step_x: float = grid_rect.size.x / 3.0
	for i in range(4):
		var x: float = grid_rect.position.x + step_x * i
		segments.append(_road_segment(Vector2(x, top), Vector2(x, bottom), ROAD_GRID_WIDTH))
	for y in [top, mid_y, bottom]:
		segments.append(_road_segment(Vector2(left, y), Vector2(right, y), ROAD_GRID_WIDTH))

func _nearest_grid_point_local(grid_rect: Rect2, anchor: Vector2) -> Vector2:
	return Vector2(
		clampf(anchor.x, grid_rect.position.x, grid_rect.end.x),
		clampf(anchor.y, grid_rect.position.y, grid_rect.end.y)
	)

## The six neighbouring tile coords of a tile (HSM order). Off-map coords are
## included — callers filter against `tiles` when they need real neighbours.
func neighbor_coords(tile_coord: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for hsm in HSM_ORDER:
		result.append(tile_coord + _neighbor_offset_for_hsm(tile_coord, hsm))
	return result

func _neighbor_offset_for_hsm(tile_coord: Vector2i, hsm: String) -> Vector2i:
	var is_odd_column: bool = tile_coord.x % 2 == 1
	match hsm:
		"HSM1":
			return Vector2i(0, -1)
		"HSM2":
			return Vector2i(1, 0) if is_odd_column else Vector2i(1, -1)
		"HSM3":
			return Vector2i(1, 1) if is_odd_column else Vector2i(1, 0)
		"HSM4":
			return Vector2i(0, 1)
		"HSM5":
			return Vector2i(-1, 1) if is_odd_column else Vector2i(-1, 0)
		"HSM6":
			return Vector2i(-1, 0) if is_odd_column else Vector2i(-1, -1)
		_:
			return Vector2i.ZERO

func _sort_hsm_clockwise(a: String, b: String) -> bool:
	return HSM_ORDER.find(a) < HSM_ORDER.find(b)
