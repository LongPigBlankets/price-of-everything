extends Node2D
# Water mapmode. Highlights river tiles in light green and coastal land tiles
# (adjacent to a sea / deep-sea tile, where desalination plants belong) in amber.
# Unlike the deposits mapmode it draws no icons — just tinted hexes.

# Highlights are fairly opaque so the underlying terrain colours don't distract;
# every other tile (plain land + the sea) is dimmed to ~20% brightness.
const RIVER_COLOR := Color(0.45, 0.95, 0.5, 0.72)
const DESAL_COLOR := Color(0.90, 0.72, 0.36, 0.72)
const DARKEN_COLOR := Color(0.0, 0.0, 0.0, 0.8)
const SEA_TYPES := ["sea", "deep_sea"]

@onready var terrain_layer: HexMap = %TerrainLayer

var _active := false
var _markers: Array = []   # [{center: Vector2, color: Color}]

func _ready() -> void:
	MapMode.selections_changed.connect(_on_selections_changed)
	MapMode.mode_cleared.connect(_on_mode_cleared)

func _on_selections_changed(mode: int, _selections: Array) -> void:
	if mode == MapMode.Mode.WATER:
		_active = true
		_rebuild()
	else:
		_active = false
	queue_redraw()

func _on_mode_cleared() -> void:
	_active = false
	_markers.clear()
	queue_redraw()

func _rebuild() -> void:
	_markers.clear()
	if terrain_layer == null:
		return
	for coord in terrain_layer.tiles:
		var tile_data: Dictionary = terrain_layer.tiles[coord]
		var is_land := not _is_sea(str(tile_data.get("type", "")))
		var color: Color
		var highlight := true
		if is_land and bool(tile_data.get("has_river", false)):
			color = RIVER_COLOR
		elif is_land and _is_coastal(coord):
			color = DESAL_COLOR
		else:
			# Plain land and the sea are dimmed so the highlights stand out.
			color = DARKEN_COLOR
			highlight = false
		_markers.append({"center": _tile_world_pos(coord), "color": color, "highlight": highlight})

func _draw() -> void:
	if not _active:
		return
	var tile := _tile_size()
	var half_w := tile.x * 0.5
	var half_h := tile.y * 0.5
	var shoulder := tile.x * 0.25
	var shape := PackedVector2Array([
		Vector2(-shoulder, -half_h),
		Vector2(shoulder, -half_h),
		Vector2(half_w, 0),
		Vector2(shoulder, half_h),
		Vector2(-shoulder, half_h),
		Vector2(-half_w, 0),
	])
	for m in _markers:
		var center: Vector2 = m.center
		var color: Color = m.color
		var pts := PackedVector2Array()
		for p in shape:
			pts.append(p + center)
		draw_colored_polygon(pts, color)
		# Only the green/amber highlights get a brighter rim; dimmed tiles don't.
		if bool(m.highlight):
			var outline := pts.duplicate()
			outline.append(pts[0])
			draw_polyline(outline, Color(color.r, color.g, color.b, minf(1.0, color.a + 0.28)), 2.0, true)

# ── Geometry helpers ──────────────────────────────────────────────────────────

func _is_sea(tile_type: String) -> bool:
	return SEA_TYPES.has(tile_type.strip_edges())

# A land tile is coastal when at least one of its 6 hex neighbours is a sea tile.
func _is_coastal(coord: Vector2i) -> bool:
	for n in _neighbours(coord):
		if terrain_layer.tiles.has(n) and _is_sea(str(terrain_layer.tiles[n].get("type", ""))):
			return true
	return false

# Odd-q offset neighbours (matches Catalog.tile_neighbours' layout).
func _neighbours(coord: Vector2i) -> Array:
	var offs: Array
	if coord.x % 2 == 1:
		offs = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0)]
	else:
		offs = [Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(-1, -1)]
	var out: Array = []
	for o in offs:
		out.append(coord + o)
	return out

func _tile_world_pos(coord: Vector2i) -> Vector2:
	return terrain_layer.map_to_local(terrain_layer.map_coord_for_tile_coord(coord))

func _tile_size() -> Vector2:
	if terrain_layer != null and terrain_layer.tile_set != null:
		return Vector2(terrain_layer.tile_set.tile_size)
	return Vector2(540, 480)
