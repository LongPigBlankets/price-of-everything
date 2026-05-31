extends Node2D
## Logistics map overlay. When the Logistics mapmode is active it dims the map and
## draws every origin->destination route as a thick coloured line (with a soft white
## glow) running tile-centre to tile-centre: a triangle at the origin and a 60x60 box
## at the destination. Each IN-TRANSIT SHIPMENT gets a 60x40 tag at its current
## position along the route showing that shipment's good + qty; hover it for the full
## breakdown. Parallel routes sharing tiles spread 30px apart and cross when they diverge.
##
## NOTE: sizes are world-units (Node2D space), tuned by eye — expect in-engine tweaks.

@onready var terrain_layer: HexMap = %TerrainLayer

const LINE_WIDTH := 20.0
const DEST_BOX := 60.0
const TAG_W := 60.0   # long edge (along the line)
const TAG_H := 40.0   # short edge
const PARALLEL_GAP := 30.0
const TRIANGLE_LEN := 30.0
const TRIANGLE_HALF := 18.0
const PANEL := Vector2(120, 120)
const DIM_COLOUR := Color(0, 0, 0, 0.55)
const PALETTE: Array = [
	Color(0.13, 0.55, 0.13), Color(0.95, 0.83, 0.18), Color(0.47, 0.78, 1.0),
	Color(0.55, 0.35, 0.88), Color(0.22, 0.22, 0.22), Color(0.95, 0.48, 0.14),
	Color(0.48, 0.90, 0.72), Color(0.25, 0.41, 0.88),
]

var _routes: Array = []        # [{source, dest, tiles, path, goods, color, index}]
var _tag_hits: Array = []      # [{centre, dir, goods, color}] one per in-transit shipment
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

# --- legend reads this ---
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
			by_route[key] = {"source": src, "dest": dst, "tiles": [], "path": [], "goods": {}}
		var entry: Dictionary = by_route[key]
		if entry.tiles.is_empty() and not s.get("tiles", []).is_empty():
			entry.tiles = s.get("tiles", []).duplicate()
		if entry.path.is_empty() and not s.get("path", []).is_empty():
			entry.path = s.get("path", []).duplicate()
		for g in _shipment_goods(s).keys():
			entry.goods[g] = int(entry.goods.get(g, 0)) + int(_shipment_goods(s)[g])
	var keys: Array = by_route.keys()
	keys.sort()
	var idx := 0
	for k in keys:
		var r: Dictionary = by_route[k]
		r.color = PALETTE[idx % PALETTE.size()]
		r.index = idx
		_routes.append(r)
		idx += 1

func _shipment_goods(s: Dictionary) -> Dictionary:
	var g: Dictionary = {}
	if bool(s.get("is_sale", false)):
		for item in s.get("sale_record", {}).get("items", []):
			g[str(item.get("good_id", ""))] = int(item.get("qty", 0))
	else:
		var gid := str(s.get("good_id", ""))
		if gid != "":
			g[gid] = int(s.get("qty", 0))
	return g

func _tile_pos(tile_id: String) -> Vector2:
	var coord := terrain_layer.id_to_coord(tile_id)
	if coord == Vector2i(-1, -1):
		return Vector2.INF
	return terrain_layer.map_to_local(terrain_layer.map_coord_for_tile_coord(coord))

func _seg_key(a: String, b: String) -> String:
	return (a + "~" + b) if a < b else (b + "~" + a)

func _build_segment_offsets() -> Dictionary:
	var users: Dictionary = {}
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
	draw_rect(Rect2(-100000, -100000, 200000, 200000), DIM_COLOUR)
	_rebuild_routes()
	if _routes.is_empty():
		return
	var seg_offsets := _build_segment_offsets()
	var route_colors: Dictionary = {}
	for r in _routes:
		route_colors[str(r.source) + "->" + str(r.dest)] = r.color
	for r in _routes:
		_draw_route_line(r, seg_offsets)
	_build_shipment_tags(route_colors)
	for t in _tag_hits:
		_draw_tag(t.centre, t.dir, t.color, t.goods, false)
	# hover resolution
	var mouse := to_local(get_global_mouse_position())
	_hover_tag = -1
	for i in _tag_hits.size():
		if _point_in_tag(mouse, _tag_hits[i]):
			_hover_tag = i
			break
	if _hover_tag >= 0:
		var ht: Dictionary = _tag_hits[_hover_tag]
		_draw_tag(ht.centre, ht.dir, ht.color, ht.goods, true)
		_draw_hover_panel(ht)

func _offset_point(p: Vector2, seg_dir: Vector2, amount: float) -> Vector2:
	return p + Vector2(-seg_dir.y, seg_dir.x) * amount

func _draw_glow(pa: Vector2, pb: Vector2) -> void:
	# Soft white halo (layered translucent strokes, widest+faintest outward).
	draw_line(pa, pb, Color(1, 1, 1, 0.07), LINE_WIDTH + 18.0)
	draw_line(pa, pb, Color(1, 1, 1, 0.12), LINE_WIDTH + 11.0)
	draw_line(pa, pb, Color(1, 1, 1, 0.22), LINE_WIDTH + 5.0)

func _draw_route_line(r: Dictionary, seg_offsets: Dictionary) -> void:
	var t: Array = r.tiles
	if t.size() < 2:
		return
	var col: Color = r.color
	for i in range(t.size() - 1):
		var a := _tile_pos(str(t[i]))
		var b := _tile_pos(str(t[i + 1]))
		if a == Vector2.INF or b == Vector2.INF:
			continue
		var dir := b - a
		if dir.length() < 0.5:
			continue
		dir = dir.normalized()
		var amount: float = float(seg_offsets.get(_seg_key(str(t[i]), str(t[i + 1])), {}).get(r.index, 0.0))
		var pa := _offset_point(a, dir, amount)
		var pb := _offset_point(b, dir, amount)
		_draw_glow(pa, pb)
		draw_line(pa, pb, col, LINE_WIDTH)
	var p0 := _tile_pos(str(t[0]))
	var p1 := _tile_pos(str(t[1]))
	if p0 != Vector2.INF and p1 != Vector2.INF:
		var d0 := (p1 - p0).normalized()
		var perp := Vector2(-d0.y, d0.x)
		draw_colored_polygon(PackedVector2Array([
			p0 + d0 * TRIANGLE_LEN, p0 + perp * TRIANGLE_HALF, p0 - perp * TRIANGLE_HALF
		]), col)
	var pd := _tile_pos(str(t[t.size() - 1]))
	if pd != Vector2.INF:
		draw_rect(Rect2(pd - Vector2(DEST_BOX, DEST_BOX) / 2.0, Vector2(DEST_BOX, DEST_BOX)), col)

func _build_shipment_tags(route_colors: Dictionary) -> void:
	# One tag per in-transit shipment, at its current position along its route.
	_tag_hits.clear()
	for s in MatchState.get_pending_transport_shipments():
		var src := str(s.get("source_tile", ""))
		var dst := str(s.get("destination_tile", ""))
		var path: Array = s.get("path", [])
		if src == "" or dst == "" or path.is_empty():
			continue
		var total := int(s.get("transport_turns", path.size() - 1))
		var rem := int(s.get("turns_remaining", 0))
		var idx: int = clampi(total - rem, 0, path.size() - 1)
		var pos := _tile_pos(str(path[idx]))
		if pos == Vector2.INF:
			continue
		var dir := Vector2.RIGHT
		if idx > 0:
			var prev := _tile_pos(str(path[idx - 1]))
			if prev != Vector2.INF and (pos - prev).length() > 0.5:
				dir = (pos - prev).normalized()
		elif path.size() > 1:
			var nxt := _tile_pos(str(path[1]))
			if nxt != Vector2.INF and (nxt - pos).length() > 0.5:
				dir = (nxt - pos).normalized()
		_tag_hits.append({
			"centre": pos, "dir": dir,
			"goods": _shipment_goods(s),
			"color": route_colors.get(src + "->" + dst, Color.WHITE),
		})

func _draw_tag(centre: Vector2, dir: Vector2, col: Color, goods: Dictionary, hovered: bool) -> void:
	var along := dir
	var perp := Vector2(-dir.y, dir.x)
	var hw := TAG_W / 2.0
	var hh := TAG_H / 2.0
	var corners := PackedVector2Array([
		centre + along * hw + perp * hh, centre + along * hw - perp * hh,
		centre - along * hw - perp * hh, centre - along * hw + perp * hh,
	])
	var bg := Color(0.22, 0.28, 0.36, 0.99) if hovered else Color(0.04, 0.06, 0.10, 0.96)
	draw_colored_polygon(corners, bg)
	draw_polyline(PackedVector2Array([corners[0], corners[1], corners[2], corners[3], corners[0]]), col, 2.0)
	var label := _tag_label(goods)
	if label != "":
		draw_set_transform(centre, along.angle(), Vector2.ONE)
		draw_string(ThemeDB.fallback_font, Vector2(-hw + 4.0, 5.0), label,
			HORIZONTAL_ALIGNMENT_LEFT, TAG_W - 8.0, 14, Color.WHITE)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _tag_label(goods: Dictionary) -> String:
	if goods.is_empty():
		return ""
	var first = goods.keys()[0]
	var txt := "%s x%d" % [Catalog.get_display_name(str(first)), int(goods[first])]
	if goods.size() > 1:
		txt += " +%d" % (goods.size() - 1)
	return txt

func _point_in_tag(p: Vector2, tag: Dictionary) -> bool:
	var local: Vector2 = p - tag.centre
	var dir: Vector2 = tag.dir
	return abs(local.dot(dir)) <= TAG_W / 2.0 and abs(local.dot(Vector2(-dir.y, dir.x))) <= TAG_H / 2.0

func _draw_hover_panel(tag: Dictionary) -> void:
	var origin: Vector2 = tag.centre + Vector2(TAG_W / 2.0 + 6.0, -PANEL.y - 6.0)
	draw_rect(Rect2(origin, PANEL), Color(0.03, 0.05, 0.09, 0.97))
	draw_rect(Rect2(origin, PANEL), Color(0.7, 0.85, 1.0, 0.5), false, 2.0)
	var y := 18.0
	for g in tag.goods.keys():
		draw_string(ThemeDB.fallback_font, origin + Vector2(8.0, y),
			"%s  x%d" % [Catalog.get_display_name(str(g)), int(tag.goods[g])],
			HORIZONTAL_ALIGNMENT_LEFT, PANEL.x - 16.0, 13, Color.WHITE)
		y += 20.0
		if y > PANEL.y - 6.0:
			break
