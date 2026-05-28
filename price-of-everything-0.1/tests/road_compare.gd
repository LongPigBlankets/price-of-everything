extends Node2D

const FIXTURE_DIR := "res://tests/fixtures/road_maps"
const SNAPSHOT_DIR := "res://tests/snapshots"
const SNAPSHOT_SUFFIX := "phase1_region"
const FIXTURES := [
	"fixture_rural_strip",
	"fixture_dense_city",
	"fixture_split_river_region",
	"fixture_mixed_density",
	"fixture_dense_city_no_apron",
	"fixture_coastal_city_branches",
]

@onready var terrain_layer: HexMap = %TerrainLayer
@onready var river_visuals: Node2D = %RiverVisuals
@onready var road_visuals: Node2D = %RoadVisuals
@onready var camera: Camera2D = %Camera2D

var _fixture_index := 0
var _current_fixture_id := ""


func _ready() -> void:
	road_visuals.set_process_unhandled_input(false)
	var requested_index := _requested_fixture_index()
	if requested_index >= 0:
		_fixture_index = requested_index
	_apply_fixture(_fixture_index)
	if OS.get_cmdline_user_args().has("--dump-plan"):
		call_deferred("_quit_after_dump")


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return

	match event.keycode:
		KEY_0:
			_apply_fixture((_fixture_index + 1) % FIXTURES.size())
			get_viewport().set_input_as_handled()
		KEY_9:
			_apply_fixture((_fixture_index - 1 + FIXTURES.size()) % FIXTURES.size())
			get_viewport().set_input_as_handled()
		KEY_F9:
			_capture_snapshot()
			get_viewport().set_input_as_handled()


func _apply_fixture(index: int) -> void:
	_fixture_index = index
	var fixture_id: String = FIXTURES[_fixture_index]
	var fixture: Dictionary = _load_fixture(fixture_id)
	if fixture.is_empty():
		return

	_current_fixture_id = fixture_id
	terrain_layer.tiles = _build_fixture_tiles(fixture)
	terrain_layer.cities = fixture.get("cities", {})
	terrain_layer._build_prototype_map()
	_center_camera_on_fixture()

	river_visuals.queue_redraw()
	road_visuals.queue_redraw()
	print("[RoadCompare] Loaded %s (%d/%d)" % [_current_fixture_id, _fixture_index + 1, FIXTURES.size()])


func _load_fixture(fixture_id: String) -> Dictionary:
	var path := "%s/%s.json" % [FIXTURE_DIR, fixture_id]
	if not FileAccess.file_exists(path):
		push_error("Missing road fixture: %s" % path)
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Could not open road fixture: %s" % path)
		return {}

	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Road fixture did not parse to a Dictionary: %s" % path)
		return {}
	return parsed


func _requested_fixture_index() -> int:
	for arg in OS.get_cmdline_user_args():
		var text := str(arg)
		if not text.begins_with("--road-fixture="):
			continue
		var fixture_id := text.trim_prefix("--road-fixture=")
		return FIXTURES.find(fixture_id)
	return -1


func _quit_after_dump() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit()


func _build_fixture_tiles(fixture: Dictionary) -> Dictionary:
	var tiles := {}
	for r in range(HexMap.MAP_H):
		for q in range(HexMap.MAP_W):
			var coord := Vector2i(q, r)
			tiles[coord] = terrain_layer._make_default_tile(q, r)
			tiles[coord]["type"] = "sea"

	var fixture_tiles: Array = fixture.get("tiles", [])
	var authored_coords: Array[Vector2i] = []
	for row_data in fixture_tiles:
		var row: Dictionary = row_data
		var tile_id: String = str(row.get("id", ""))
		var coord: Vector2i = terrain_layer.id_to_coord(tile_id)
		if coord == Vector2i(-1, -1):
			push_warning("Fixture %s has invalid tile id '%s'." % [_current_fixture_id, tile_id])
			continue

		var tile: Dictionary = terrain_layer._make_default_tile(coord.x, coord.y)
		tile["type"] = str(row.get("type", "rural"))
		tile["infrastructure_present"] = Array(row.get("infrastructure_present", []))
		tile["has_river"] = bool(row.get("has_river", false))
		tile["river_type"] = str(row.get("river_type", ""))
		tile["road_type"] = str(row.get("road_type", ""))
		tile["road_hsms"] = Array(row.get("road_hsms", []))
		tile["road_density"] = str(row.get("road_density", ""))
		tile["city_id"] = str(row.get("city_id", ""))
		tile["city_name"] = str(row.get("city_name", ""))
		tile["tile_role"] = str(row.get("tile_role", ""))
		tile["road_seed"] = int(row.get("road_seed", tile["road_seed"]))
		tiles[coord] = tile
		authored_coords.append(coord)
	if bool(fixture.get("add_land_apron", true)):
		_add_land_apron(tiles, authored_coords)
	return tiles


func _add_land_apron(tiles: Dictionary, authored_coords: Array[Vector2i]) -> void:
	for coord in authored_coords:
		for offset in _neighbor_offsets_for_coord(coord):
			var neighbor := coord + offset
			if not _coord_in_bounds(neighbor):
				continue
			var tile: Dictionary = tiles[neighbor]
			if tile.get("type", "") != "sea":
				continue
			tile["type"] = "rural"
			tiles[neighbor] = tile


func _coord_in_bounds(coord: Vector2i) -> bool:
	return coord.x >= 0 and coord.x < HexMap.MAP_W and coord.y >= 0 and coord.y < HexMap.MAP_H


func _neighbor_offsets_for_coord(coord: Vector2i) -> Array[Vector2i]:
	var is_odd_column := coord.x % 2 == 1
	if is_odd_column:
		return [
			Vector2i(0, -1),
			Vector2i(1, 0),
			Vector2i(1, 1),
			Vector2i(0, 1),
			Vector2i(-1, 1),
			Vector2i(-1, 0),
		]
	return [
		Vector2i(0, -1),
		Vector2i(1, -1),
		Vector2i(1, 0),
		Vector2i(0, 1),
		Vector2i(-1, 0),
		Vector2i(-1, -1),
	]


func _center_camera_on_fixture() -> void:
	var centers: Array[Vector2] = []
	for coord in terrain_layer.tiles:
		var tile: Dictionary = terrain_layer.tiles[coord]
		var infrastructure: Array = tile.get("infrastructure_present", [])
		if infrastructure.has("roads") or tile.get("has_river", false):
			centers.append(terrain_layer.map_to_local(terrain_layer.map_coord_for_tile_coord(coord)))

	if centers.is_empty():
		camera.position = terrain_layer.map_center_world()
		return

	var sum := Vector2.ZERO
	for point in centers:
		sum += point
	camera.position = sum / float(centers.size())
	camera.zoom = Vector2(0.42, 0.42)


func _capture_snapshot() -> void:
	call_deferred("_capture_snapshot_deferred")


func _capture_snapshot_deferred() -> void:
	await RenderingServer.frame_post_draw
	_save_snapshot_image()


func _save_snapshot_image() -> void:
	var snapshot_dir := ProjectSettings.globalize_path(SNAPSHOT_DIR)
	DirAccess.make_dir_recursive_absolute(snapshot_dir)
	var path := "%s/%s_%s.png" % [snapshot_dir, _current_fixture_id, SNAPSHOT_SUFFIX]
	var texture := get_viewport().get_texture()
	if texture == null:
		push_error("Could not save road snapshot; viewport texture is unavailable.")
		return
	var image := texture.get_image()
	if image == null:
		push_error("Could not save road snapshot; viewport image is unavailable.")
		return
	var error := image.save_png(path)
	if error != OK:
		push_error("Could not save road snapshot to %s (error %d)." % [path, error])
		return
	print("[RoadCompare] Snapshot saved: %s" % path)
