extends Node2D
## Draws a simple tile highlight when a building is selected.
## Should be a child of the root world Node2D, at the same tree level as TerrainLayer.

@onready var terrain_layer: HexMap = %TerrainLayer

# ---- appearance ----
const HIGHLIGHT_COLOR := Color(0.94, 0.91, 0.82, 0.44)

# ---- state ----
var _origin_tile_id: String = ""

# ---- hex geometry cache ----
var _hex_verts: PackedVector2Array = PackedVector2Array()  # hex polygon in tile-local space

func _ready() -> void:
	visible = false
	set_process(false)

func on_building_connections_changed(
		origin_tile_id: String,
		_input_tile_ids: Array,
		_output_tile_ids: Array,
		_has_market_output: bool) -> void:
	_origin_tile_id = origin_tile_id

	var active := origin_tile_id != ""
	visible = active
	set_process(false)
	if not active:
		queue_redraw()
		return
	_ensure_hex_verts()
	queue_redraw()

func _draw() -> void:
	if _origin_tile_id == "":
		return

	var origin_pos := _tile_world_pos_by_id(_origin_tile_id)
	if origin_pos == Vector2.INF:
		return

	# Highlight origin tile
	if not _hex_verts.is_empty():
		var shifted := PackedVector2Array()
		for v in _hex_verts:
			shifted.append(origin_pos + v)
		draw_colored_polygon(shifted, HIGHLIGHT_COLOR)

# ---- hex vertex cache ----

func _ensure_hex_verts() -> void:
	if not _hex_verts.is_empty():
		return
	# Flat-top hex (tile_offset_axis = VERTICAL, tile_size = Vector2(540, 480)).
	# Vertices: right (W/2, 0), top-right (W/4, -H/2), top-left (-W/4, -H/2),
	#           left (-W/2, 0), bottom-left (-W/4, H/2), bottom-right (W/4, H/2).
	# The HSM points in hex_map.gd are side midpoints of these same vertices.
	var ts: Vector2 = terrain_layer.tile_set.tile_size
	var hw := ts.x * 0.5   # half-width  (270 at default tile size)
	var hh := ts.y * 0.5   # half-height (240 at default tile size)
	const INSET := 0.88
	_hex_verts = PackedVector2Array([
		Vector2( hw,       0.0) * INSET,
		Vector2( hw * 0.5, -hh) * INSET,
		Vector2(-hw * 0.5, -hh) * INSET,
		Vector2(-hw,       0.0) * INSET,
		Vector2(-hw * 0.5,  hh) * INSET,
		Vector2( hw * 0.5,  hh) * INSET,
	])

# ---- tile world position helpers ----

func _tile_world_pos_by_id(tile_id: String) -> Vector2:
	var coord := terrain_layer.id_to_coord(tile_id)
	if coord == Vector2i(-1, -1):
		return Vector2.INF
	return terrain_layer.map_to_local(terrain_layer.map_coord_for_tile_coord(coord))
