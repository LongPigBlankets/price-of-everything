extends Node2D
## Draws tile highlights and marching-ant paths when a building is selected.
## Should be a child of the root world Node2D, at the same tree level as TerrainLayer.

@onready var terrain_layer: HexMap = %TerrainLayer

# ---- appearance ----
# World-space sizes (tiles are ~480 world px tall at zoom 1)
const HIGHLIGHT_COLOR   := Color(0.55, 1.0,  0.55, 0.38)   # light green tile highlight
const ANT_COLOR         := Color(0.45, 1.0,  0.45, 0.95)   # triangle colour
const MARKET_TEXT_COLOR := Color(0.45, 1.0,  0.45, 1.0)
const TRIANGLE_SPACING  := 140.0   # world units between triangle tips
const TRIANGLE_HALF_W   := 20.0    # half-base of each triangle (perpendicular to path)
const TRIANGLE_LEN      := 28.0    # length of each triangle (along path direction)
const ANT_SPEED         := 200.0   # world units / second
const MARKET_DIST       := 120.0   # world units above tile top-vertex for MARKET label
const MARKET_FONT_SIZE  := 22

# ---- state ----
var _origin_tile_id: String = ""
var _input_tile_ids: Array = []    # tiles that supply this building
var _output_tile_ids: Array = []   # tiles that receive this building's output
var _has_market_output: bool = false
var _time: float = 0.0

# ---- hex geometry cache ----
var _hex_verts: PackedVector2Array = PackedVector2Array()  # hex polygon in tile-local space

func _ready() -> void:
	visible = false
	set_process(false)

func on_building_connections_changed(
		origin_tile_id: String,
		input_tile_ids: Array,
		output_tile_ids: Array,
		has_market_output: bool) -> void:
	_origin_tile_id    = origin_tile_id
	_input_tile_ids    = input_tile_ids
	_output_tile_ids   = output_tile_ids
	_has_market_output = has_market_output

	var active := origin_tile_id != ""
	visible = active
	set_process(active)
	if not active:
		queue_redraw()
		return
	_ensure_hex_verts()
	queue_redraw()

func _process(delta: float) -> void:
	_time += delta
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

	# Marching ants: inputs travel FROM source tile TO origin
	for tile_id in _input_tile_ids:
		var src_pos := _tile_world_pos_by_id(tile_id)
		if src_pos != Vector2.INF:
			_draw_ant_path(src_pos, origin_pos)

	# Marching ants: outputs travel FROM origin TO dest tile
	for tile_id in _output_tile_ids:
		var dst_pos := _tile_world_pos_by_id(tile_id)
		if dst_pos != Vector2.INF:
			_draw_ant_path(origin_pos, dst_pos)

	# Market output — sold goods sail to the nearest port. Ants run in a straight
	# line tile -> port, with the MARKET label floating just outside the port.
	if _has_market_output:
		var market_pos := _market_label_pos(origin_pos)  # fallback: above origin tile
		var port_tile := TransportService.nearest_port_tile(_origin_tile_id)
		if port_tile != "":
			var port_pos := _tile_world_pos_by_id(port_tile)
			if port_pos != Vector2.INF and port_pos.distance_to(origin_pos) > 1.0:
				var dir := (port_pos - origin_pos).normalized()
				market_pos = port_pos + dir * (terrain_layer.tile_set.tile_size.x * 0.5 + 40.0)
		_draw_ant_path(origin_pos, market_pos)
		draw_string(
			ThemeDB.fallback_font,
			market_pos + Vector2(-28.0, 6.0),
			"MARKET",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			MARKET_FONT_SIZE,
			MARKET_TEXT_COLOR
		)

# ---- drawing helpers ----

func _draw_ant_path(from: Vector2, to: Vector2) -> void:
	var segment := to - from
	var length := segment.length()
	if length < 1.0:
		return
	var dir := segment / length
	var perp := Vector2(-dir.y, dir.x)

	# Animate offset so triangles march from → to
	var offset := fmod(_time * ANT_SPEED, TRIANGLE_SPACING)

	var t := offset
	while t < length:
		var tip    := from + dir * t
		var base_c := tip - dir * TRIANGLE_LEN
		var base_l := base_c - perp * TRIANGLE_HALF_W
		var base_r := base_c + perp * TRIANGLE_HALF_W
		draw_colored_polygon(
			PackedVector2Array([tip, base_l, base_r]),
			ANT_COLOR
		)
		t += TRIANGLE_SPACING

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

func _market_label_pos(origin_pos: Vector2) -> Vector2:
	# Flat-top hex: top edge is at -H/2 from centre; place label MARKET_DIST above that.
	return origin_pos + Vector2(0.0, -(terrain_layer.tile_set.tile_size.y * 0.5 + MARKET_DIST))
