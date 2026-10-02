extends Control
## Supply chain board — the view.
##
## Draws the model (empire_board_model.gd) as an isometric plate over dark space: only the
## tiles the company stands on, stores in or routes through, each at the map's own tile size
## and place. A tile shows its rivers, its water and a rough terrace of its relief; hills and
## mountains stand taller. On the tiles stand the company's buildings, each tile's warehouse
## and any port it trades through. The lines between them are the transport routes, drawn as
## the road, rail, pipe or cable that carries them, with goods travelling along.
##
## BOARD SPACE. Everything static is built once in board space, the isometric projection of
## the map at zoom 1 (see iso()). The projection is linear, so pan and zoom are one canvas
## transform and nothing is rebuilt while the player moves the view.
##
## Presentation only: it reads the sim and never changes it.

signal building_picked(iid: String)

const Model := preload("res://scripts/empire_board_model.gd")
const GoodHover := preload("res://scripts/good_icon_hover.gd")

const ISO_X := 0.70710678
const ISO_Y := 0.40824829          # 0.7071 * tan(30 deg): a true isometric squash
const ISO_RISE := 0.81649658

## Rough relief: each band above the tile's own level steps up by this much, three steps at most.
const TERRACE_STEP := 9.0
const TERRACE_MAX := 3
## The band a tile counts as its own level covers at least this share of it.
const BASE_BAND_SHARE := 0.55
const HEX_AREA := 194400.0

## How much of its frame's width a level 3 sprite fills (sprite_export pads 6 px a side).
const SPRITE_FILL := 0.985

const _NAVY := Color(0.015, 0.058, 0.105)
const _CREAM := Color(0.995, 0.931, 0.763)
const _WALL := Color("5d4a37")
const _WALL_SEA := Color("0f2a5c")
const _PAD := Color("cdc4aa")
const _PAD_EDGE := Color("8c8470")
const _BOX_ROOF := Color("efe6ce")
const _BOX_SOUTH := Color("b9ae93")
const _BOX_EAST := Color("d6ccb1")
const _ASPHALT := Color("5c5c59")
const _KERB := Color("b9b4a6")
const _DASH := Color("f4f1e6")
const _BALLAST := Color("756a5c")
const _TIE := Color("3d2f22")
const _RAIL := Color("c9ccd0")
const _PIPE := Color("b5763e")
const _PIPE_REINF := Color("8f979e")
const _PIPE_EDGE := Color("3a2a1c")
const _TRACK := Color("7a6444")
const _CABLE := Color("e8c66a")

const _ZOOM_STEP := 1.12
const _FIT_PAD := 90.0
const _TOKEN_SPEED := 80.0          # board units per second
const _TOKEN_SPACING := 1100.0      # between tokens of one flow
const _DRAG_SLOP := 5.0

## Sun in the south-east: the faces toward the camera are lit, east most.
const _SUN := Vector2(0.8, 0.6)

static var _hill_polys: Array = []           # [{b, p, box}] parsed once
static var _sea_polys: Array = []
static var _lake_polys: Array = []
static var _relief_cache: Dictionary = {}    # tile_id -> {base, sea: [], land: [], lakes: []}

var _model: Dictionary = {}
var _ground: ArrayMesh = null                # every drawn tile, back to front, in board space
var _standing: Array = []                    # model standing + {at: Vector2 board, h, rect}
var _links: Array = []                       # [{mode, pts: PackedVector2Array board}]
var _flows: Array = []                       # [{pts, cum, total, icon, power, phase}]
var _labels: Array = []                      # [{at: Vector2 board, text}]
var _bounds := Rect2()
var _zoom := 1.0
var _offset := Vector2.ZERO
var _fitted := false
var _clock := 0.0
var _press_pos := Vector2.INF
var _dragging := false
var _hover: Dictionary = {}
var _tokens: Control


static func iso(p: Vector2, h: float = 0.0) -> Vector2:
	return Vector2((p.x - p.y) * ISO_X, (p.x + p.y) * ISO_Y - h * ISO_RISE)


class TokenLayer extends Control:
	var board: Control
	func _draw() -> void:
		board.call("_draw_tokens", self)


func _ready() -> void:
	clip_contents = true
	_tokens = TokenLayer.new()
	_tokens.set("board", self)
	_tokens.name = "Tokens"
	_tokens.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tokens.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_tokens)
	resized.connect(func() -> void:
		if not _fitted:
			fit_view())


## Rebuild the board from the live sim. `graph` is empire_graph.build(); `terrain` the HexMap.
func set_graph(graph: Dictionary, terrain: Node) -> void:
	_model = {}
	_ground = null
	_standing.clear()
	_links.clear()
	_flows.clear()
	_labels.clear()
	_hover = {}
	if terrain == null or not terrain.has_method("id_to_coord"):
		queue_redraw()
		return
	var rivers: Dictionary = _rivers_by_tile(terrain)
	_model = Model.build(terrain, graph, _river_lines(rivers), _true_positions(graph, terrain))
	_build_ground(rivers)
	_build_standing()
	_build_lines()
	if not _fitted:
		fit_view()
	queue_redraw()


func has_content() -> bool:
	return not (_model.get("tiles", {}) as Dictionary).is_empty()


func capture_camera() -> Dictionary:
	return {"offset": _offset, "zoom": _zoom}


## The standing things with their screen rects, for tools and tests.
func standing_screen_rects() -> Array:
	var out: Array = []
	for s in _standing:
		var r: Rect2 = s["rect"]
		out.append({"iid": s["iid"], "kind": s["kind"],
			"rect": Rect2(r.position * _zoom + _offset, r.size * _zoom)})
	return out


func fit_view() -> void:
	if _bounds.size.x <= 0.0 or size.x <= 0.0:
		return
	var avail := size - Vector2(_FIT_PAD, _FIT_PAD) * 2.0
	_zoom = clampf(minf(avail.x / _bounds.size.x, avail.y / _bounds.size.y), 0.08, 1.6)
	_offset = size * 0.5 - _bounds.get_center() * _zoom
	_fitted = true
	queue_redraw()


# ------------------------------------------------------------------ source data

func _rivers_by_tile(terrain: Node) -> Dictionary:
	var out: Dictionary = {}
	var rv: Node = terrain.get_parent().get_node_or_null("RiverVisuals") if terrain.get_parent() != null else null
	if rv == null:
		rv = get_tree().get_first_node_in_group("river_visuals")
	if rv == null or not rv.has_method("get_river_polylines"):
		return out
	for rec in rv.call("get_river_polylines"):
		var c: Vector2i = rec["coord"]
		var tid := "tile_%d_%d" % [c.x + 1, c.y + 1]
		(out.get_or_add(tid, []) as Array).append(rec)
	return out


func _river_lines(rivers: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for tid in rivers:
		var lines: Array = []
		for rec in rivers[tid]:
			lines.append(rec["points"])
		out[tid] = lines
	return out


func _true_positions(graph: Dictionary, terrain: Node) -> Dictionary:
	var out: Dictionary = {}
	var bv: Node = get_tree().get_first_node_in_group("building_footprints")
	if bv == null or not bv.has_method("footprint_center_for"):
		return out
	for n in graph.get("nodes", []):
		var tile := str((n as Dictionary).get("tile_id", ""))
		if tile == "":
			continue
		out[str(n["iid"])] = bv.call("footprint_center_for", str(n["iid"]), terrain.id_to_coord(tile))
	return out


static func _load_relief() -> void:
	if not _hill_polys.is_empty():
		return
	for e in HillBaked.polys():
		_hill_polys.append({"b": int(e["b"]), "p": e["p"], "box": _box_of(e["p"])})
	for e in HillBaked.sea():
		if int(e["b"]) < 5:
			_sea_polys.append({"b": int(e["b"]), "p": e["p"], "box": _box_of(e["p"])})
	for p in HillBaked.lakes():
		_lake_polys.append({"p": p, "box": _box_of(p)})


static func _box_of(pts: PackedVector2Array) -> Rect2:
	if pts.is_empty():
		return Rect2()
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	return r


## The tile's rough relief: its water and its land bands clipped to the hex, each land band
## with the step it stands on. Cached for good; the relief never changes in a game.
static func _relief_of(tile_id: String, center: Vector2) -> Dictionary:
	if _relief_cache.has(tile_id):
		return _relief_cache[tile_id]
	_load_relief()
	var hexp := Model.hex_points(center)
	var box := _box_of(hexp)
	var sea: Array = []
	for e in _sea_polys:
		if (e["box"] as Rect2).intersects(box):
			for piece in _clip(e["p"], hexp):
				sea.append({"b": int(e["b"]), "p": piece})
	var land_raw: Array = []
	var area: Dictionary = {}
	for e in _hill_polys:
		if not (e["box"] as Rect2).intersects(box):
			continue
		for piece in _clip(e["p"], hexp):
			land_raw.append({"b": int(e["b"]), "p": piece})
			area[int(e["b"])] = float(area.get(int(e["b"]), 0.0)) + _area(piece)
	var base := 1
	for b in area:
		if int(b) > base and float(area[b]) >= HEX_AREA * BASE_BAND_SHARE:
			base = int(b)
	var land: Array = []
	for e in land_raw:
		land.append({"b": int(e["b"]), "p": e["p"],
			"lift": float(clampi(int(e["b"]) - base, 0, TERRACE_MAX)) * TERRACE_STEP})
	var lakes: Array = []
	for e in _lake_polys:
		if (e["box"] as Rect2).intersects(box):
			lakes.append_array(_clip(e["p"], hexp))
	var rel := {"base": base, "sea": sea, "land": land, "lakes": lakes}
	_relief_cache[tile_id] = rel
	return rel


static func _clip(poly: PackedVector2Array, hexp: PackedVector2Array) -> Array:
	var out: Array = []
	if poly.size() < 3:
		return out
	for piece in Geometry2D.intersect_polygons(poly, hexp):
		var pts: PackedVector2Array = piece
		if pts.size() >= 3 and not Geometry2D.is_polygon_clockwise(pts):
			out.append(pts)
	return out


static func _area(pts: PackedVector2Array) -> float:
	var a := 0.0
	for i in range(pts.size()):
		var p := pts[i]
		var q := pts[(i + 1) % pts.size()]
		a += p.x * q.y - q.x * p.y
	return absf(a) * 0.5


## How far the terraces lift the ground at a point of a tile.
func _lift_at(tile_id: String, p: Vector2) -> float:
	var rel: Dictionary = _relief_cache.get(tile_id, {})
	var lift := 0.0
	for e in rel.get("land", []):
		if Geometry2D.is_point_in_polygon(p, e["p"]):
			lift = float(e["lift"])
	return lift


func _height_at(tile_id: String, p: Vector2) -> float:
	var t: Dictionary = (_model["tiles"] as Dictionary).get(tile_id, {})
	return float(t.get("height", 0.0)) + _lift_at(tile_id, p)


# ------------------------------------------------------------------ building the picture

func _build_ground(rivers: Dictionary) -> void:
	var tiles: Dictionary = _model.get("tiles", {})
	_bounds = Rect2()
	if tiles.is_empty():
		return
	var order: Array = tiles.keys()
	order.sort_custom(func(a, b) -> bool:
		var ca: Vector2 = tiles[a]["center"]
		var cb: Vector2 = tiles[b]["center"]
		if absf((ca.x + ca.y) - (cb.x + cb.y)) > 0.5:
			return ca.x + ca.y < cb.x + cb.y
		return ca.x < cb.x)
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var band_cols: Array[Color] = MapStyle.band_colors()
	var sea_cols: Array[Color] = MapStyle.sea_colors()
	var water: Color = sea_cols[4]
	var first := true
	for tid in order:
		var t: Dictionary = tiles[tid]
		var c: Vector2 = t["center"]
		var h := float(t["height"])
		var hexp := Model.hex_points(c)
		var is_sea := str(t["type"]) == "sea" or str(t["type"]) == "deep_sea"
		var rel: Dictionary = _relief_of(str(tid), c)
		for i in range(6):
			var a := hexp[i]
			var b := hexp[(i + 1) % 6]
			var n := ((a + b) * 0.5 - c).normalized()
			if n.x + n.y <= 0.01:
				continue
			var wall: Color = (_WALL_SEA if is_sea else _WALL).lightened(0.22 * maxf(0.0, n.dot(_SUN)))
			_quad(verts, cols, idx, iso(a, h), iso(b, h), iso(b, 0.0), iso(a, 0.0), wall)
		var top: Color = sea_cols[0 if str(t["type"]) == "deep_sea" else 2] if is_sea else sea_cols[5]
		_poly(verts, cols, idx, hexp, h, top)
		for e in rel["sea"]:
			_poly(verts, cols, idx, e["p"], h, sea_cols[int(e["b"])])
		if not is_sea:
			for e in rel["land"]:
				var col: Color = band_cols[clampi(int(e["b"]), 0, band_cols.size() - 1)]
				var lift := float(e["lift"])
				if lift > 0.0:
					_risers(verts, cols, idx, e["p"], hexp, h + lift, col.darkened(0.3))
				_poly(verts, cols, idx, e["p"], h + lift, col)
		for p in rel["lakes"]:
			_poly(verts, cols, idx, p, h, water)
		for rec in rivers.get(tid, []):
			var w := (float(rec["start_width"]) + float(rec["end_width"])) * 0.5
			for part in Geometry2D.intersect_polyline_with_polygon(rec["points"], hexp):
				_stroke(verts, cols, idx, part, w, h, water)
		for p in hexp:
			for hh in [h + TERRACE_STEP * TERRACE_MAX, 0.0]:
				var q := iso(p, hh)
				if first:
					_bounds = Rect2(q, Vector2.ZERO)
					first = false
				else:
					_bounds = _bounds.expand(q)
		_labels.append({"at": iso(c + Vector2(135.0, 240.0) * 0.72, h), "text": str(t["label"])})
	if idx.is_empty():
		return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	_ground = ArrayMesh.new()
	_ground.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


static func _quad(verts: PackedVector3Array, cols: PackedColorArray, idx: PackedInt32Array,
		a: Vector2, b: Vector2, c: Vector2, d: Vector2, col: Color) -> void:
	var base := verts.size()
	for p in [a, b, c, d]:
		verts.append(Vector3(p.x, p.y, 0.0))
		cols.append(col)
	for i in [0, 1, 2, 0, 2, 3]:
		idx.append(base + i)


static func _poly(verts: PackedVector3Array, cols: PackedColorArray, idx: PackedInt32Array,
		pts: PackedVector2Array, h: float, col: Color) -> void:
	var tris := Geometry2D.triangulate_polygon(pts)
	if tris.is_empty():
		return
	var base := verts.size()
	for p in pts:
		var q := iso(p, h)
		verts.append(Vector3(q.x, q.y, 0.0))
		cols.append(col)
	for i in tris:
		idx.append(base + i)


## The camera-facing step faces of a terrace. Edges lying on the tile's own border are left
## out: the band carries on into the next tile there, so a face would draw a seam.
static func _risers(verts: PackedVector3Array, cols: PackedColorArray, idx: PackedInt32Array,
		pts: PackedVector2Array, hexp: PackedVector2Array, h: float, col: Color) -> void:
	var signed := 0.0
	for i in range(pts.size()):
		signed += pts[i].x * pts[(i + 1) % pts.size()].y - pts[(i + 1) % pts.size()].x * pts[i].y
	var flip := 1.0 if signed >= 0.0 else -1.0
	for i in range(pts.size()):
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		var n := (b - a).orthogonal() * flip
		if n.x + n.y <= 0.0 or _on_border((a + b) * 0.5, hexp):
			continue
		_quad(verts, cols, idx, iso(a, h), iso(b, h), iso(b, h - TERRACE_STEP), iso(a, h - TERRACE_STEP), col)


static func _on_border(p: Vector2, hexp: PackedVector2Array) -> bool:
	for i in range(6):
		if Geometry2D.get_closest_point_to_segment(p, hexp[i], hexp[(i + 1) % 6]).distance_squared_to(p) < 1.0:
			return true
	return false


static func _stroke(verts: PackedVector3Array, cols: PackedColorArray, idx: PackedInt32Array,
		pts: PackedVector2Array, width: float, h: float, col: Color) -> void:
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		if a.distance_squared_to(b) < 0.01:
			continue
		var along := (b - a).normalized() * width * 0.5
		var side := along.orthogonal()
		_quad(verts, cols, idx, iso(a - along + side, h), iso(b + along + side, h),
			iso(b + along - side, h), iso(a - along - side, h), col)


func _build_standing() -> void:
	for s in _model.get("standing", []):
		var d: Dictionary = (s as Dictionary).duplicate()
		var pos: Vector2 = d["pos"]
		var h := _height_at(str(d["tile"]), pos)
		var side := float(d["side"])
		d["h"] = h
		d["at"] = iso(pos, h)
		d["depth"] = pos.x + pos.y
		var tex: Texture2D = d.get("sprite")
		if tex != null:
			# The sprite's content is as wide as its footprint's diamond, and its lowest point is
			# the diamond's front corner.
			var used: Rect2 = Model.BuildingSprites.content_rect(tex)
			# The frame, not the content, is what the slot's footprint scales: a level set shares
			# one scale, so the lower levels sit smaller inside the same frame.
			var k := side * 2.0 * ISO_X / (float(tex.get_width()) * SPRITE_FILL)
			side = used.size.x * k / (2.0 * ISO_X)
			d["side"] = side
			var front: Vector2 = (d["at"] as Vector2) + Vector2(0.0, side * ISO_Y)
			var origin := Vector2(front.x - (used.position.x + used.size.x * 0.5) * k,
				front.y - used.end.y * k)
			d["tex_rect"] = Rect2(origin, Vector2(tex.get_width(), tex.get_height()) * k)
			d["rect"] = Rect2(origin + used.position * k, used.size * k)
		else:
			var top := iso(pos, h + side * 0.6)
			d["rect"] = Rect2(top.x - side * ISO_X, top.y - side * ISO_Y,
				side * 2.0 * ISO_X, side * 2.0 * ISO_Y + side * 0.6 * ISO_RISE)
		_standing.append(d)
	_standing.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["depth"]) < float(b["depth"]))


func _build_lines() -> void:
	var tiles: Dictionary = _model.get("tiles", {})
	# A short drive from each standing thing to its tile's warehouse.
	for s in _standing:
		var t: Dictionary = tiles.get(s["tile"], {})
		if str(s["kind"]) == "warehouse" or not bool(t.get("store", false)):
			continue
		var hub: Vector2 = t["hub"]
		_links.append({"mode": Model.MODE_DRIVE, "pts": PackedVector2Array([
			iso(s["pos"], float(s["h"])), iso(hub, _height_at(str(s["tile"]), hub))])})
	for l in _model.get("links", []):
		var ta: Dictionary = tiles.get(l["a"], {})
		var tb: Dictionary = tiles.get(l["b"], {})
		if ta.is_empty() or tb.is_empty():
			continue
		var mid := Model.crossing(ta["center"], tb["center"], float(l["lane"]), true)
		var ha: Vector2 = ta["hub"]
		var hb: Vector2 = tb["hub"]
		_links.append({"mode": str(l["mode"]), "pts": PackedVector2Array([
			iso(ha, _height_at(str(l["a"]), ha)), iso(mid, float(ta["height"])),
			iso(mid, float(tb["height"])), iso(hb, _height_at(str(l["b"]), hb))])})
	# Roads last and drives first would bury the drives; draw order is by weight instead.
	var weight := {Model.MODE_DRIVE: 0, "nothing": 1, Model.MODE_CABLE: 2, "pipes": 3,
		"reinf_pipes": 4, "roads": 5, "rail": 6}
	_links.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(weight.get(a["mode"], 1)) < int(weight.get(b["mode"], 1)))
	var n := 0
	for f in _model.get("flows", []):
		var pts := PackedVector2Array()
		var path: Array = f["path"]
		for i in range(path.size()):
			var node: Dictionary = path[i]
			var tile := str(node["tile"])
			# A crossing sits on the tile's edge at the tile's own height; everything else is a
			# standing position and rides its terrace.
			var is_crossing := str(node["mode"]) != Model.MODE_DRIVE and i > 0 and i < path.size() - 1 \
				and (node["p"] as Vector2) != (tiles[tile]["hub"] as Vector2)
			var h := float(tiles[tile]["height"]) if is_crossing else _height_at(tile, node["p"])
			pts.append(iso(node["p"], h))
		var cum := PackedFloat32Array([0.0])
		for i in range(1, pts.size()):
			cum.append(cum[i - 1] + pts[i].distance_to(pts[i - 1]))
		var total := cum[cum.size() - 1]
		if total < 1.0:
			continue
		_flows.append({"pts": pts, "cum": cum, "total": total, "icon": f["icon"],
			"good": f["good"], "power": Model._is_power(str(f["good"])),
			"phase": fmod(float(n) * 0.618034, 1.0) * _TOKEN_SPACING})
		n += 1


# ------------------------------------------------------------------ drawing

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_clock += delta
	if not _flows.is_empty():
		_tokens.queue_redraw()


func _draw() -> void:
	if not has_content():
		var font := get_theme_default_font()
		var msg := "Nothing built yet"
		var w := font.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		draw_string(font, size * 0.5 - Vector2(w * 0.5, 0.0), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, DS.PALETTE.TEXT)
		return
	draw_set_transform(_offset, 0.0, Vector2(_zoom, _zoom))
	if _ground != null:
		draw_mesh(_ground, null)
	for l in _links:
		_draw_link(l)
	for s in _standing:
		_draw_standing(s)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_labels()
	_draw_hover()


func _draw_standing(s: Dictionary) -> void:
	var pos: Vector2 = s["pos"]
	var h := float(s["h"])
	var side := float(s["side"])
	var half := side * 0.56
	var pad := PackedVector2Array([
		iso(pos + Vector2(-half, -half), h), iso(pos + Vector2(half, -half), h),
		iso(pos + Vector2(half, half), h), iso(pos + Vector2(-half, half), h)])
	draw_colored_polygon(pad, _PAD)
	pad.append(pad[0])
	draw_polyline(pad, _PAD_EDGE, 1.2)
	var tex: Texture2D = s.get("sprite")
	if tex != null:
		draw_texture_rect(tex, s["tex_rect"], false)
		return
	# No sprite yet: a plain block of the footprint, with the building's icon on its roof.
	var hs := side * 0.5
	var top := h + side * 0.6
	var a := pos + Vector2(-hs, -hs)
	var b := pos + Vector2(hs, -hs)
	var c := pos + Vector2(hs, hs)
	var d := pos + Vector2(-hs, hs)
	draw_colored_polygon(PackedVector2Array([iso(d, top), iso(c, top), iso(c, h), iso(d, h)]), _BOX_SOUTH)
	draw_colored_polygon(PackedVector2Array([iso(c, top), iso(b, top), iso(b, h), iso(c, h)]), _BOX_EAST)
	draw_colored_polygon(PackedVector2Array([iso(a, top), iso(b, top), iso(c, top), iso(d, top)]), _BOX_ROOF)
	var icon: Texture2D = s.get("icon")
	if icon != null:
		var isz := side * 0.8
		draw_texture_rect(icon, Rect2(iso(pos, top) - Vector2(isz, isz) * 0.5, Vector2(isz, isz)), false,
			Color(0.0, 0.12, 0.24))


func _draw_link(l: Dictionary) -> void:
	var pts: PackedVector2Array = l["pts"]
	match str(l["mode"]):
		"roads":
			_thick(pts, _KERB, 21.0)
			_thick(pts, _ASPHALT, 16.0)
			_draw_dashes(pts, 12.0, 12.0, _DASH, 1.8)
		Model.MODE_DRIVE:
			_thick(pts, _KERB, 10.0)
			_thick(pts, _ASPHALT, 7.0)
		"rail":
			_thick(pts, _BALLAST, 15.0)
			_draw_ties(pts, 10.0, 13.0, _TIE, 2.6)
			_draw_offset_line(pts, 4.0, _RAIL, 1.5)
			_draw_offset_line(pts, -4.0, _RAIL, 1.5)
		"pipes":
			_thick(pts, _PIPE_EDGE, 9.0)
			_thick(pts, _PIPE, 6.0)
			_draw_offset_line(pts, -1.4, _PIPE.lightened(0.45), 1.2)
		"reinf_pipes":
			_thick(pts, _PIPE_EDGE, 12.0)
			_thick(pts, _PIPE_REINF, 9.0)
			_draw_ties(pts, 26.0, 12.0, _PIPE_EDGE, 2.4)
			_draw_offset_line(pts, -2.2, _PIPE_REINF.lightened(0.5), 1.4)
		Model.MODE_CABLE:
			_thick(pts, _PIPE_EDGE, 4.5)
			_thick(pts, _CABLE, 2.4)
		_:
			# Bare ground: a cart track, no built way.
			_draw_dashes(pts, 13.0, 9.0, _TRACK, 6.0)


## A wide line drawn segment by segment with round joints. draw_polyline miters its joints,
## and a route that steps up a tile's wall turns back on itself there, which throws a spike.
func _thick(pts: PackedVector2Array, col: Color, width: float) -> void:
	for i in range(pts.size() - 1):
		draw_line(pts[i], pts[i + 1], col, width)
		if i > 0:
			draw_circle(pts[i], width * 0.5, col)


## Walk a polyline calling `emit(point, direction)` every `step` units.
func _walk(pts: PackedVector2Array, step: float, start: float, emit: Callable) -> void:
	var want := start
	var done := 0.0
	for i in range(pts.size() - 1):
		var seg := pts[i].distance_to(pts[i + 1])
		if seg < 0.001:
			continue
		var dir := (pts[i + 1] - pts[i]) / seg
		while want <= done + seg:
			emit.call(pts[i] + dir * (want - done), dir)
			want += step
		done += seg


func _draw_dashes(pts: PackedVector2Array, dash: float, gap: float, col: Color, width: float) -> void:
	_walk(pts, dash + gap, gap * 0.5, func(p: Vector2, dir: Vector2) -> void:
		draw_line(p, p + dir * dash, col, width))


func _draw_ties(pts: PackedVector2Array, step: float, length: float, col: Color, width: float) -> void:
	_walk(pts, step, step * 0.5, func(p: Vector2, dir: Vector2) -> void:
		var n := dir.orthogonal() * length * 0.5
		draw_line(p - n, p + n, col, width))


func _draw_offset_line(pts: PackedVector2Array, off: float, col: Color, width: float) -> void:
	for i in range(pts.size() - 1):
		if pts[i].distance_squared_to(pts[i + 1]) < 0.001:
			continue
		var n := (pts[i + 1] - pts[i]).normalized().orthogonal() * off
		draw_line(pts[i] + n, pts[i + 1] + n, col, width)


func _draw_labels() -> void:
	var font := get_theme_default_font()
	var fs := 13
	for l in _labels:
		var at: Vector2 = (l["at"] as Vector2) * _zoom + _offset
		var text := str(l["text"])
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var box := Rect2(at - Vector2(w * 0.5 + 8.0, 11.0), Vector2(w + 16.0, 22.0))
		draw_rect(box, Color(_NAVY.r, _NAVY.g, _NAVY.b, 0.86))
		draw_string(font, Vector2(box.position.x + 8.0, box.position.y + 16.0), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, DS.PALETTE.TEXT)


func _draw_hover() -> void:
	if _hover.is_empty():
		return
	var r: Rect2 = _hover["rect"]
	var sr := Rect2(r.position * _zoom + _offset, r.size * _zoom)
	var font := get_theme_default_font()
	var lines: Array = [str(_hover["name"])]
	if str(_hover["kind"]) == "warehouse":
		var tid := str(_hover["tile"])
		lines.append("Level %d   %d of %d stored" % [int(_hover["level"]),
			Stockpile.get_used_capacity(tid), Stockpile.get_capacity(tid)])
		for row in Stockpile.get_top_goods(tid, 3):
			lines.append("%s  %d" % [str(Catalog.get_display_name(str(row["good_id"]))), int(row["qty"])])
	elif str(_hover["kind"]) == "site":
		lines.append("Under construction")
	var fs := 14
	var w := 0.0
	for line in lines:
		w = maxf(w, font.get_string_size(str(line), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	var box := Rect2(Vector2(sr.get_center().x - w * 0.5 - 10.0, sr.position.y - 14.0 - 20.0 * lines.size()),
		Vector2(w + 20.0, 20.0 * lines.size() + 10.0))
	box.position.x = clampf(box.position.x, 4.0, maxf(4.0, size.x - box.size.x - 4.0))
	box.position.y = maxf(4.0, box.position.y)
	draw_rect(box, Color(_NAVY.r, _NAVY.g, _NAVY.b, 0.95))
	draw_rect(box, _CREAM, false, 1.0)
	for i in range(lines.size()):
		draw_string(font, box.position + Vector2(10.0, 20.0 + 20.0 * float(i)), str(lines[i]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, DS.PALETTE.TEXT)


## Goods on the move: each flow's icon travels its path, building to warehouse to route to
## warehouse to building. Power is a pulse on the cable, not a crate.
func _draw_tokens(layer: Control) -> void:
	var box := clampf(44.0 * _zoom + 10.0, 16.0, 40.0)
	var view := Rect2(Vector2.ZERO, size).grow(box)
	for f in _flows:
		var total := float(f["total"])
		var pts: PackedVector2Array = f["pts"]
		var cum: PackedFloat32Array = f["cum"]
		var d := fmod(_clock * _TOKEN_SPEED + float(f["phase"]), _TOKEN_SPACING)
		var seg := 0
		while d < total:
			while seg < cum.size() - 2 and cum[seg + 1] < d:
				seg += 1
			var span := maxf(0.001, cum[seg + 1] - cum[seg])
			var p := pts[seg].lerp(pts[seg + 1], (d - cum[seg]) / span) * _zoom + _offset
			if view.has_point(p):
				if bool(f["power"]):
					layer.draw_circle(p, box * 0.2, _CABLE)
				else:
					layer.draw_circle(p, box * 0.5 + 1.5, _NAVY)
					layer.draw_circle(p, box * 0.5, _CREAM)
					var icon: Texture2D = f["icon"]
					if icon != null:
						var isz := box * 0.74
						layer.draw_texture_rect(icon, Rect2(p - Vector2(isz, isz) * 0.5, Vector2(isz, isz)), false)
			d += _TOKEN_SPACING


# ------------------------------------------------------------------ input

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_at(mb.position, _ZOOM_STEP)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at(mb.position, 1.0 / _ZOOM_STEP)
		elif mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			if mb.pressed:
				_press_pos = mb.position
				_dragging = false
			else:
				if not _dragging and mb.button_index == MOUSE_BUTTON_LEFT:
					_click(mb.position)
				_press_pos = Vector2.INF
				_dragging = false
		accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _press_pos != Vector2.INF:
			if not _dragging and mm.position.distance_to(_press_pos) > _DRAG_SLOP:
				_dragging = true
			if _dragging:
				_offset += mm.relative
				queue_redraw()
		else:
			_set_hover(_pick(mm.position))
	elif event is InputEventMagnifyGesture:
		_zoom_at((event as InputEventMagnifyGesture).position, (event as InputEventMagnifyGesture).factor)
		accept_event()
	elif event is InputEventPanGesture:
		_offset -= (event as InputEventPanGesture).delta * 12.0
		queue_redraw()
		accept_event()


func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var z := clampf(_zoom * factor, 0.06, 4.0)
	var board := (screen_pos - _offset) / _zoom
	_zoom = z
	_offset = screen_pos - board * _zoom
	queue_redraw()


## The standing thing under a screen point, nearest the camera first.
func _pick(screen_pos: Vector2) -> Dictionary:
	var board := (screen_pos - _offset) / _zoom
	for i in range(_standing.size() - 1, -1, -1):
		if (_standing[i]["rect"] as Rect2).has_point(board):
			return _standing[i]
	return {}


func _set_hover(s: Dictionary) -> void:
	if str(s.get("iid", "")) == str(_hover.get("iid", "")):
		return
	_hover = s
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if str(s.get("kind", "")) in ["building", "site"] \
		else Control.CURSOR_ARROW
	queue_redraw()


func _click(screen_pos: Vector2) -> void:
	var s := _pick(screen_pos)
	if str(s.get("kind", "")) in ["building", "site"]:
		building_picked.emit(str(s["iid"]))
