extends Node2D
## Logistics map overlay. When the Logistics mapmode is active it dims the map and
## draws every in-transit shipment as a thick coloured line running tile-centre to
## tile-centre along the shipment's path: a triangle at the origin, a 60x60 box at
## the destination, and a 40x20 tag (good + qty) at each turn boundary that you can
## hover for the full goods breakdown. One colour per origin->destination route.
##
## Parallel routes that share tiles are spread 30px apart, offset equally from the
## line they share, and cross freely once their paths diverge.
##
## NOTE: written without a visual pass (headless) — sizes/feathering/panel are a
## first cut and will likely want tuning in-engine.

@onready var terrain_layer: HexMap = %TerrainLayer

const LINE_WIDTH := 20.0
const FEATHER := 5.0
const DEST_BOX := 60.0
const TAG_W := 40.0
const TAG_H := 20.0
const PARALLEL_GAP := 30.0      # edge-to-edge spacing between parallel routes
const TRIANGLE_LEN := 30.0
const TRIANGLE_HALF := 18.0
const PANEL := Vector2(120, 120)
const DIM_COLOUR := Color(0, 0, 0, 0.55)
const FEATHER_COLOUR := Color(1, 1, 1, 0.85)
# Reuses the stockpile colour scheme (capped at 10; the scheme currently has 8).
const PALETTE: Array = [
	Color(0.13, 0.55, 0.13), Color(0.95, 0.83, 0.18), Color(0.47, 0.78, 1.0),
	Color(0.55, 0.35, 0.88), Color(0.22, 0.22, 0.22), Color(0.95, 0.48, 0.14),
	Color(0.48, 0.90, 0.72), Color(0.25, 0.41, 0.88),
]

var _routes: Array = []        # [{source, dest, tiles, path, goods, color, index}]
var _tag_hits: Array = []      # [{centre, dir, goods, route_idx}] rebuilt each _draw
var _hover_tag := -1

func _ready() -> void:
	add_to_group("logistics_overlay")
	visible = false
	set_process(false)
	MapMode.selections_changed.connect(_on_mode_changed)
	MapMode.mode_cleared.connect(_on_mode_cleared)

func _on_mode_changed(mode: int, _sel: Array) -> void:
	var active := mode == MapMode.Mode.LOGISTICS
	visible = active
	set_process(active)
	queue_redraw()

func _on_mode_cleared() -> void:
	visible = false
	set_process(false)
	_hover_tag = -1
	queue_redraw()

func _process(_delta: float) -> void:
	queue_redraw()

# --- public: legend reads this ---
func get_routes() -> Array:
	_rebuild_routes()
	return _routes

func _rebuild_routes() -> void:
	_routes.clear()
	var by_route: Dictionary = {}
	for s in MatchState.get_pending_transport_shipments():
		var src := str(s.get("source_tile", ""))
		var dst := str(s.get("destination_tile", ""))
		if src == "" or dst == "":
			continue
		var key := src + "->" + dst
		if not by_route.has(key):
			by_route[key] = {
				"source": src, "dest": dst,
				"tiles": s.get("tiles", []).duplicate(),
				"path": s.get("path", []).duplicate(),
				"goods": {},
			}
		var entry: Dictionary = by_route[key]
		if entry.tiles.is_empty() and not s.get("tiles", []).is_empty():
			entry.tiles = s.get("tiles", []).duplicate()
		if entry.path.is_empty() and not s.get("path", []).is_empty():
			entry.path = s.get("path", []).duplicate()
		if bool(s.get("is_sale", false)):
			for item in s.get("sale_record", {}).get("items", []):
				var g := str(item.get("good_id", ""))
				entry.goods[g] = int(entry.goods.get(g, 0)) + int(item.get("qty", 0))
		else:
			var g := str(s.get("good_id", ""))
			if g != "":
				entry.goods[g] = int(entry.goods.get(g, 0)) + int(s.get("qty", 0))
	var keys: Array = by_route.keys()
	keys.sort()  # deterministic → colours match the legend
	var idx := 0
	for k in keys:
		var r: Dictionary = by_route[k]
		r.color = PALETTE[idx % PALETTE.size()]
		r.index = idx
		_routes.append(r)
		idx += 1

func _tile_pos(tile_id: String) -> Vector2:
	var coord := terrain_layer.id_to_coord(tile_id)
	if coord == Vector2i(-1, -1):
		return Vector2.INF
	return terrain_layer.map_to_local(terrain_layer.map_coord_for_tile_coord(coord))

# --- parallel-offset bookkeeping ---
func _seg_key(a: String, b: String) -> String:
	return (a + "~" + b) if a < b else (b + "~" + a)

func _build_segment_offsets() -> Dictionary:
	# segment key -> {route_idx -> offset_amount}
	var users: Dictionary = {}  # segkey -> [route_idx...]
	for r in _routes:
		var t: Array = r.tiles
		for i in range(t.size() - 1):
			var k := _seg_key(str(t[i]), str(t[i + 1]))
			if not users.has(k):
				users[k] = []
			if not users[k].has(r.index):
				users[k].append(r.index)
	var offsets: Dictionary = {}
	for k in users.keys():
		var list: Array = users[k]
		list.sort()
		var n := list.size()
		var per: Dictionary = {}
		for rank in range(n):
			per[list[rank]] = (float(rank) - float(n - 1) / 2.0) * PARALLEL_GAP
		offsets[k] = per
	return offsets

func _draw() -> void:
	if MapMode.current_mode != MapMode.Mode.LOGISTICS:
		return
	# Dim the whole map.
	draw_rect(Rect2(-100000, -100000, 200000, 200000), DIM_COLOUR)
	_rebuild_routes()
	if _routes.is_empty():
		return
	var seg_offsets := _build_segment_offsets()
	_tag_hits.clear()
	var mouse := to_local(get_global_mouse_position())

	# First pass: figure out which tag (if any) is hovered.
	_hover_tag = -1
	# (tags are registered during the draw below; hover is resolved next frame)
	for r in _routes:
		_draw_route(r, seg_offsets)
	# Resolve hover against the tags we just registered, then draw the panel.
	for i in _tag_hits.size():
		if _point_in_tag(mouse, _tag_hits[i]):
			_hover_tag = i
			break
	if _hover_tag >= 0:
		_draw_hover_panel(_tag_hits[_hover_tag])

func _offset_point(p: Vector2, seg_dir: Vector2, amount: float) -> Vector2:
	var perp := Vector2(-seg_dir.y, seg_dir.x)
	return p + perp * amount

func _draw_route(r: Dictionary, seg_offsets: Dictionary) -> void:
	var t: Array = r.tiles
	if t.size() < 2:
		return
	var col: Color = r.color
	# Draw each segment with its parallel offset.
	for i in range(t.size() - 1):
		var a := _tile_pos(str(t[i]))
		var b := _tile_pos(str(t[i + 1]))
		if a == Vector2.INF or b == Vector2.INF:
			continue
		var dir := (b - a)
		if dir.length() < 0.5:
			continue
		dir = dir.normalized()
		var k := _seg_key(str(t[i]), str(t[i + 1]))
		var amount: float = float(seg_offsets.get(k, {}).get(r.index, 0.0))
		var pa := _offset_point(a, dir, amount)
		var pb := _offset_point(b, dir, amount)
		draw_line(pa, pb, FEATHER_COLOUR, LINE_WIDTH + 2.0 * FEATHER)  # white feather
		draw_line(pa, pb, col, LINE_WIDTH)
	# Start triangle at the origin, pointing along the first segment.
	var p0 := _tile_pos(str(t[0]))
	var p1 := _tile_pos(str(t[1]))
	if p0 != Vector2.INF and p1 != Vector2.INF:
		var d0 := (p1 - p0).normalized()
		var perp := Vector2(-d0.y, d0.x)
		var tip := p0 + d0 * TRIANGLE_LEN
		draw_colored_polygon(PackedVector2Array([
			tip, p0 + perp * TRIANGLE_HALF, p0 - perp * TRIANGLE_HALF
		]), col)
	# Destination box.
	var pd := _tile_pos(str(t[t.size() - 1]))
	if pd != Vector2.INF:
		draw_rect(Rect2(pd - Vector2(DEST_BOX, DEST_BOX) / 2.0, Vector2(DEST_BOX, DEST_BOX)), col)
	# Per-turn tags at each turn boundary (path = turn-move endpoints, skip origin).
	var boundaries: Array = r.path
	for i in range(1, boundaries.size()):
		var bt := str(boundaries[i])
		var bpos := _tile_pos(bt)
		if bpos == Vector2.INF:
			continue
		# direction along the path at this tile
		var prev_pos := _tile_pos(str(boundaries[i - 1]))
		var tdir := Vector2.RIGHT
		if prev_pos != Vector2.INF and (bpos - prev_pos).length() > 0.5:
			tdir = (bpos - prev_pos).normalized()
		_tag_hits.append({"centre": bpos, "dir": tdir, "goods": r.goods, "color": col})
		_draw_tag(bpos, tdir, r, _tag_hits.size() - 1)

func _draw_tag(centre: Vector2, dir: Vector2, r: Dictionary, tag_index: int) -> void:
	# 40x20 rect with its LONG edge along the line direction.
	var along := dir
	var perp := Vector2(-dir.y, dir.x)
	var hw := TAG_W / 2.0
	var hh := TAG_H / 2.0
	var corners := PackedVector2Array([
		centre + along * hw + perp * hh,
		centre + along * hw - perp * hh,
		centre - along * hw - perp * hh,
		centre - along * hw + perp * hh,
	])
	var hovered := tag_index == _hover_tag
	var bg := Color(0.04, 0.06, 0.10, 0.95)
	if hovered:
		bg = Color(0.22, 0.28, 0.36, 0.98)
	draw_colored_polygon(corners, bg)
	draw_polyline(PackedVector2Array([corners[0], corners[1], corners[2], corners[3], corners[0]]), r.color, 2.0)
	# Primary good + qty (full breakdown is in the hover panel).
	var label := _tag_label(r.goods)
	if label != "":
		draw_set_transform(centre, along.angle(), Vector2.ONE)
		draw_string(ThemeDB.fallback_font, Vector2(-hw + 3.0, 5.0), label,
			HORIZONTAL_ALIGNMENT_LEFT, TAG_W - 6.0, 12, Color.WHITE)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _tag_label(goods: Dictionary) -> String:
	if goods.is_empty():
		return ""
	var first = goods.keys()[0]
	var txt := "%s x%d" % [Catalog.get_display_name(str(first)), int(goods[first])]
	if goods.size() > 1:
		txt = "+%d  %s" % [goods.size() - 1, txt]
	return txt

func _point_in_tag(p: Vector2, tag: Dictionary) -> bool:
	var c: Vector2 = tag.centre
	var dir: Vector2 = tag.dir
	var perp := Vector2(-dir.y, dir.x)
	var local := p - c
	return abs(local.dot(dir)) <= TAG_W / 2.0 and abs(local.dot(perp)) <= TAG_H / 2.0

func _draw_hover_panel(tag: Dictionary) -> void:
	var origin: Vector2 = tag.centre + Vector2(TAG_W, -PANEL.y - 6.0)
	draw_rect(Rect2(origin, PANEL), Color(0.03, 0.05, 0.09, 0.96))
	draw_rect(Rect2(origin, PANEL), Color(0.7, 0.85, 1.0, 0.5), false, 2.0)
	var y := 16.0
	for g in tag.goods.keys():
		draw_string(ThemeDB.fallback_font, origin + Vector2(8.0, y),
			"%s  x%d" % [Catalog.get_display_name(str(g)), int(tag.goods[g])],
			HORIZONTAL_ALIGNMENT_LEFT, PANEL.x - 16.0, 12, Color.WHITE)
		y += 18.0
		if y > PANEL.y - 6.0:
			break
