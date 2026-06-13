extends Node2D
## Hover-following hex grid over the heightmap + brassy selection outline.
##
## The dark-grey grid only appears around the hovered tile, fading out within
## HOVER_RANGE hex edges. The fade uses GRAPH distance on the hex grid (cube
## distance), evaluated per hex corner, so it travels along the grid edges
## rather than as a euclidean circle. Works at any zoom (line width is
## compensated against the camera).
##
## The selected tile's outline glows brassy-metallic: light catches the
## top-left of the hex and falls off to a dark bottom-right.

const HOVER_RANGE := 5
const GRID_COLOR := Color(0.15, 0.16, 0.17)
const BRASS_LIGHT := Color("f9e7ab")
const BRASS_MID := Color("c9a93f")
const BRASS_DARK := Color("6e5212")
const TILE_CENTER := Vector2(270, 240)
const HEX_VERTS := [Vector2(135, 0), Vector2(405, 0), Vector2(540, 240), Vector2(405, 480), Vector2(135, 480), Vector2(0, 240)]

@onready var terrain: HexMap = get_node_or_null("%TerrainLayer")

var _hover := Vector2i(-999, -999)
var _selected := Vector2i(-999, -999)
var _panel: Control = null

func _process(_delta: float) -> void:
	if terrain == null:
		return
	var coord := _mouse_tile()
	if coord != _hover:
		_hover = coord
		queue_redraw()
	_sync_selection()

## The brass outline mirrors the tile view panel: it appears on the tile the
## panel is showing, follows it when the panel switches tiles (any path —
## click, deep-link), and clears the moment the panel closes.
func _sync_selection() -> void:
	if _panel == null or not is_instance_valid(_panel):
		var panels := get_tree().get_nodes_in_group("tile_view_panel")
		_panel = panels[0] if not panels.is_empty() else null
	var coord := Vector2i(-999, -999)
	if _panel != null and _panel.visible:
		var tid := str(_panel.get("_current_tile_id"))
		if tid != "":
			var c: Vector2i = terrain.id_to_coord(tid)
			if terrain.tiles.has(c):
				coord = c
	if coord != _selected:
		_selected = coord
		queue_redraw()

func _mouse_tile() -> Vector2i:
	var c: Vector2i = terrain.tile_coord_for_map_coord(terrain.local_to_map(terrain.to_local(terrain.get_global_mouse_position())))
	return c if terrain.tiles.has(c) else Vector2i(-999, -999)

## odd-q offset (odd columns shifted down) -> cube coords, for hex graph distance.
static func _cube(c: Vector2i) -> Vector3i:
	var x := c.x
	var z := c.y - (c.x - (c.x & 1)) / 2
	return Vector3i(x, -x - z, z)

static func _hex_dist(a: Vector2i, b: Vector2i) -> int:
	var d := _cube(a) - _cube(b)
	return (absi(d.x) + absi(d.y) + absi(d.z)) / 2

func _neighbor_offsets(coord: Vector2i) -> Array:
	# HSM order — matches the HEX_VERTS edge order (edge i borders offset i)
	var odd := coord.x % 2 != 0
	if odd:
		return [Vector2i(0, -1), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0)]
	return [Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(-1, -1)]

func _tile_center(coord: Vector2i) -> Vector2:
	return terrain.map_to_local(terrain.map_coord_for_tile_coord(coord))

func _grid_width() -> float:
	var cam := get_viewport().get_camera_2d()
	var zoom := cam.zoom.x if cam != null else 1.0
	return clampf(5.0 / maxf(zoom, 0.01), 1.5, 6.0)

func _draw() -> void:
	if terrain == null:
		return
	var width := _grid_width()
	if terrain.tiles.has(_hover):
		_draw_hover_grid(width)
	if terrain.tiles.has(_selected):
		_draw_brass_outline(_selected, width)

func _draw_hover_grid(width: float) -> void:
	# Collect every (deduped) hex edge as a disjoint segment, then submit the whole
	# grid in ONE draw_multiline_colors — this redraws on every mouse move, so the
	# old per-edge draw_polyline_colors (≈900 draw calls) showed up badly when panning.
	var drawn := {}
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	for dq in range(-HOVER_RANGE, HOVER_RANGE + 1):
		for dr in range(-HOVER_RANGE - 3, HOVER_RANGE + 4):
			var coord := _hover + Vector2i(dq, dr)
			if not terrain.tiles.has(coord):
				continue
			if _hex_dist(coord, _hover) > HOVER_RANGE:
				continue
			var center := _tile_center(coord)
			var offs := _neighbor_offsets(coord)
			for i in 6:
				var nb: Vector2i = coord + offs[i]
				# draw each shared edge once
				if terrain.tiles.has(nb) and _hex_dist(nb, _hover) <= HOVER_RANGE and (nb < coord):
					continue
				var c1: Vector2 = center + HEX_VERTS[i] - TILE_CENTER
				var c2: Vector2 = center + HEX_VERTS[(i + 1) % 6] - TILE_CENTER
				var key := Vector2i(int((c1.x + c2.x) * 0.5), int((c1.y + c2.y) * 0.5))
				if drawn.has(key):
					continue
				drawn[key] = true
				var a1 := _corner_alpha(coord, i)
				var a2 := _corner_alpha(coord, (i + 1) % 6)
				if a1 <= 0.0 and a2 <= 0.0:
					continue
				pts.append(c1)
				pts.append(c2)
				cols.append(Color(GRID_COLOR.r, GRID_COLOR.g, GRID_COLOR.b, a1))
				cols.append(Color(GRID_COLOR.r, GRID_COLOR.g, GRID_COLOR.b, a2))
	if not pts.is_empty():
		draw_multiline_colors(pts, cols, width)

## Corner i of a tile is shared with the neighbours across edges i-1 and i;
## its fade value is the closest graph distance among the touching tiles.
func _corner_alpha(coord: Vector2i, i: int) -> float:
	var offs := _neighbor_offsets(coord)
	var d := _hex_dist(coord, _hover)
	for j in [i, (i + 5) % 6]:
		var nb: Vector2i = coord + offs[j]
		if terrain.tiles.has(nb):
			d = mini(d, _hex_dist(nb, _hover))
	var t := 1.0 - float(d) / float(HOVER_RANGE + 1)
	return pow(clampf(t, 0.0, 1.0), 1.4) * 0.85

func _draw_brass_outline(coord: Vector2i, width: float) -> void:
	var center := _tile_center(coord)
	var light_dir := Vector2(1, 1).normalized()   # light from the top-left
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var glow_cols := PackedColorArray()
	for i in 7:
		var v: Vector2 = HEX_VERTS[i % 6] - TILE_CENTER
		pts.append(center + v)
		var t := (v.normalized().dot(light_dir) + 1.0) * 0.5
		var c := BRASS_LIGHT.lerp(BRASS_MID, t * 2.0) if t < 0.5 else BRASS_MID.lerp(BRASS_DARK, (t - 0.5) * 2.0)
		cols.append(c)
		glow_cols.append(Color(c.r, c.g, c.b, 0.32))
	draw_polyline_colors(pts, glow_cols, width * 2.6, true)
	draw_polyline_colors(pts, cols, width * 1.15, true)
