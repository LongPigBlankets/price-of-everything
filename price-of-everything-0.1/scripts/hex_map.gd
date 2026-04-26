extends TileMapLayer

const MAP_W := 30
const MAP_H := 20
const TILE_DATA_PATH := "res://data/tile_properties.csv"

signal tile_selected(tile_data)

var tiles := {}  # Vector2i(q, r) -> Dictionary

func _ready() -> void:
	_generate_tile_data()
	_load_tile_overrides()

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

		var coord := _id_to_coord(parsed.id)
		if coord == Vector2i(-1, -1):
			push_warning("Line %d: bad id '%s' — skipping." % [line_num, parsed.id])
			rows_failed += 1
			continue

		parsed.coord = coord
		tiles[coord] = parsed
		rows_loaded += 1

	file.close()
	print("Loaded %d tile overrides from CSV (%d failed)." % [rows_loaded, rows_failed])

func _parse_csv_row(header: PackedStringArray, row: PackedStringArray, line_num: int) -> Dictionary:
	if row.size() != header.size():
		push_warning("Line %d: column count mismatch (got %d, expected %d) — skipping." % [line_num, row.size(), header.size()])
		return {}

	var result := {}
	for i in header.size():
		var key := header[i].strip_edges()
		var value := row[i].strip_edges()

		match key:
			"id", "nickname", "type":
				result[key] = value
			"deposits", "buildings_present", "infrastructure_present":
				result[key] = [] if value == "" else Array(value.split("|"))
			"solar_potential", "wind_potential", "build_capacity", "tile_price":
				result[key] = 0 if value == "" else int(value)
			_:
				push_warning("Line %d: unknown column '%s' — ignoring." % [line_num, key])

	return result

func _id_to_coord(id: String) -> Vector2i:
	var parts := id.split("_")
	if parts.size() != 3 or parts[0] != "tile":
		return Vector2i(-1, -1)
	if not parts[1].is_valid_int() or not parts[2].is_valid_int():
		return Vector2i(-1, -1)
	return Vector2i(int(parts[1]) - 1, int(parts[2]) - 1)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var world_pos := get_global_mouse_position()
		var map_pos := local_to_map(to_local(world_pos))
		if tiles.has(map_pos):
			tile_selected.emit(tiles[map_pos])
