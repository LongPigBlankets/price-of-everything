extends Node2D
## Logistics map overlay. When the Logistics mapmode is active it dims the map and
## draws every origin->destination route as a thick coloured line (soft white glow)
## running tile-centre to tile-centre, with a triangle at the origin and a 60x60 box
## at the destination. Each IN-TRANSIT SHIPMENT gets a 120x60 pentagon (rectangle +
## triangle pointing at the destination) in the route colour, with the turns-to-go
## in bold white; hover it for the full goods breakdown. Parallel routes sharing
## tiles spread 50px apart and cross when they diverge.
##
## NOTE: sizes are world-units (Node2D space), tuned by eye — expect in-engine tweaks.

@onready var terrain_layer: HexMap = %TerrainLayer

const LINE_WIDTH := 20.0
const DEST_BOX := 60.0
const TAG_LEN := 120.0   # along the line (incl. the pointed tip)
const TAG_WID := 60.0    # across the line
const TAG_TIP := 30.0    # length of the pointed tip
const PARALLEL_GAP := 50.0
const TRIANGLE_LEN := 30.0
const TRIANGLE_HALF := 18.0
const PANEL := Vector2(120, 120)
const DIM_COLOUR := Color(0, 0, 0, 0.55)
const PALETTE: Array = [
	Color(0.13, 0.55, 0.13), Color(0.95, 0.83, 0.18), Color(0.47, 0.78, 1.0),
	Color(0.55, 0.35, 0.88), Color(0.22, 0.22, 0.22), Color(0.95, 0.48, 0.14),
	Color(0.48, 0.90, 0.72), Color(0.25, 0.41, 0.88),
]

var _routes: Array = []
var _tag_hits: Array = []      # [{centre, dir, turns, goods, color}] one per in-transit shipment
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
		var sg := _shipment_goods(s)
		for g in sg.keys():
			entry.goods[g] = int(entry.goods.get(g, 0)) + int(sg[g])
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
		_draw_tag(t, false)
	var mouse := to_local(get_global_mouse_position())
	_hover_tag = -1
	for i in _tag_hits.size():
		if _point_in_tag(mouse, _tag_hits[i]):
			_hover_tag = i
			break
	if _hover_tag >= 0:
		_draw_tag(_tag_hits[_hover_tag], true)
		_draw_hover_panel(_tag_hits[_hover_tag])

func _offset_point(p: Vector2, seg_dir: Vector2, amount: float) -> Vector2:
	return p + Vector2(-seg_dir.y, seg_dir.x) * amount

func _draw_glow(pa: Vector2, pb: Vector2) -> void:
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
	_tag_hits.clear()
	var tsz: float = terrain_layer.tile_set.tile_size.x
	for s in MatchState.get_pending_transport_shipments():
		var src := str(s.get("source_tile", ""))
		var dst := str(s.get("destination_tile", ""))
		var path: Array = s.get("path", [])
		if src == "" or dst == "" or path.is_empty():
			continue
		var total := int(s.get("transport_turns", path.size() - 1))
		var rem := int(s.get("turns_remaining", 0))
		var idx: int = clampi(total - rem, 0, path.size() - 1)
		var cur := _tile_pos(str(path[idx]))
		if cur == Vector2.INF:
			continue
		var incoming := Vector2.ZERO
		if idx > 0:
			var prev := _tile_pos(str(path[idx - 1]))
			if prev != Vector2.INF and (cur - prev).length() > 0.5:
				incoming = (cur - prev).normalized()
		var outgoing := Vector2.ZERO
		if idx < path.size() - 1:
			var nxt := _tile_pos(str(path[idx + 1]))
			if nxt != Vector2.INF and (nxt - cur).length() > 0.5:
				outgoing = (nxt - cur).normalized()
		var dir := outgoing if outgoing != Vector2.ZERO else incoming
		if dir == Vector2.ZERO:
			dir = Vector2.RIGHT
		var pos := cur
		# On a bend, slide the tag onto the outward (departing) leg and along its normal.
		if incoming != Vector2.ZERO and outgoing != Vector2.ZERO and incoming.dot(outgoing) < 0.95:
			var perp := Vector2(-outgoing.y, outgoing.x)
			pos = cur + outgoing * (tsz * 0.28) + perp * (tsz * 0.10)
			dir = outgoing
		_tag_hits.append({
			"centre": pos, "dir": dir, "turns": rem,
			"goods": _shipment_goods(s),
			"color": route_colors.get(src + "->" + dst, Color.WHITE),
		})

func _draw_tag(tag: Dictionary, hovered: bool) -> void:
	var c: Vector2 = tag.centre
	var along: Vector2 = tag.dir
	var perp := Vector2(-along.y, along.x)
	var half_len := TAG_LEN / 2.0
	var half_wid := TAG_WID / 2.0
	var rect_front := half_len - TAG_TIP
	# Pentagon: rectangle body + triangle tip pointing toward the destination.
	var poly := PackedVector2Array([
		c - along * half_len + perp * half_wid,
		c - along * half_len - perp * half_wid,
		c + along * rect_front - perp * half_wid,
		c + along * half_len,                       # tip toward destination
		c + along * rect_front + perp * half_wid,
	])
	var col: Color = tag.color
	if hovered:
		col = col.lightened(0.35)
	draw_colored_polygon(poly, col)
	draw_polyline(PackedVector2Array([poly[0], poly[1], poly[2], poly[3], poly[4], poly[0]]),
		Color(1, 1, 1, 0.85), 2.0)
	# Turns-to-go, bold white, centred (rotated with the tag).
	var label := str(int(tag.turns))
	draw_set_transform(c, along.angle(), Vector2.ONE)
	for off in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:  # fake-bold
		draw_string(ThemeDB.fallback_font, Vector2(-half_len, 9.0) + off, label,
			HORIZONTAL_ALIGNMENT_CENTER, TAG_LEN, 26, Color.WHITE)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _point_in_tag(p: Vector2, tag: Dictionary) -> bool:
	var local: Vector2 = p - tag.centre
	var dir: Vector2 = tag.dir
	return abs(local.dot(dir)) <= TAG_LEN / 2.0 and abs(local.dot(Vector2(-dir.y, dir.x))) <= TAG_WID / 2.0

func _draw_hover_panel(tag: Dictionary) -> void:
	var origin: Vector2 = tag.centre + Vector2(TAG_LEN / 2.0 + 6.0, -PANEL.y - 6.0)
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
