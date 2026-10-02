extends Control
## Supply chain board — the view.
##
## Draws the model (empire_board_model.gd) as an isometric plate over dark space: only the
## tiles the company stands on, stores in or routes through, each at the map's own tile size
## and place. A lowland tile shows its rivers, its water and a rough terrace of its relief;
## hills and mountains are flat plates that stand taller, in a higher band's colour. On the tiles stand the company's buildings, each tile's warehouse
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
const Pipes := preload("res://scripts/empire_board_pipes.gd")
const Atlas := preload("res://scripts/empire_board_atlas.gd")

const ISO_X := 0.70710678
const ISO_Y := 0.40824829          # 0.7071 * tan(30 deg): a true isometric squash
const ISO_RISE := 0.81649658

## Rough relief: each band above the tile's own level steps up by this much, three steps at most.
const TERRACE_STEP := 9.0
const TERRACE_MAX := 3
## The band a tile counts as its own level covers at least this share of it.
const BASE_BAND_SHARE := 0.55
const HEX_AREA := 194400.0
## Hill and mountain tiles carry no relief: a taller plate in the colour of a higher band.
const HIGH_BAND := {"hill": 7, "mountain": 9}

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
const _CABLE_DARK := Color("1b2030")
const _CABLE_STRIPE := Color("d9c27a")

const _CONCRETE := Color("a7a294")
const _ROAD_HALF := 8.0
const _DRIVE_HALF := 4.0
const _JUNCTION_GROW := 1.12         # a junction patch against the widest road into it
const _ROAD_OVERLAP := 6.0           # a straight runs this far under a junction piece
const _UNPAVED := Color(0.86, 0.74, 0.56)    # a way over bare ground: the same pieces, in earth
const _PIPE_SLOT_GAP := 11.0         # between pipes that end side by side
const _SIGN_OFFSET := 15.0
const _SIGN_POST := 15.0
const _SIGN_PLATE := 13.0
const _SIGN_MIN_PX := 15.0
const _CABLE_SAG := 0.06
const _CABLE_STEPS := 10
const _LIVE_CREEP_SECS := 4.0

const _ZOOM_STEP := 1.12
const _FIT_PAD := 90.0
const _TOKEN_SPEED := 80.0          # board units per second
const _TOKEN_SPACING := 1100.0      # between tokens of one flow
const _PULSE_SPACING := 120.0       # between slugs in a pipe and pulses on a cable
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
var _links: Array = []                       # road-like ways: [{mode, pts: PackedVector2Array board}]
var _road_plan: Array = []                   # [{a, b, half}] road segments in plan, for pipes to cross
var _junctions: Array = []                   # [{at, arms, width}] where roads and drives meet
var _rivers: Dictionary = {}                  # tile_id -> [PackedVector2Array] in plan
var _road_fits: Array = []                   # [{name, at, tint}] junction pieces
var _road_polys: Array = []                  # [{points, uvs, tint}] the straights, tile by tile
var _ramp_fills: Array = []                  # [PackedVector2Array] the banks under ramps
var _pipes: Array = []                       # plain lines, drawn only when the pieces are not baked
var _pipe_items: Array = []                  # baked pieces and run tiles, far to near
var _pipe_lines: Array = []                  # [{pts, cum, total}] centrelines, in the flow's direction
var _signs: Array = []                       # [{foot, top, icon, depth}] sorted far to near
var _cables: Array = []                      # [PackedVector2Array board]
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
	_road_plan.clear()
	_junctions.clear()
	_pipes.clear()
	_road_fits.clear()
	_road_polys.clear()
	_ramp_fills.clear()
	_pipe_items.clear()
	_pipe_lines.clear()
	_signs.clear()
	_cables.clear()
	_flows.clear()
	_labels.clear()
	_hover = {}
	if terrain == null or not terrain.has_method("id_to_coord"):
		queue_redraw()
		return
	var rivers: Dictionary = _rivers_by_tile(terrain)
	_rivers = _river_lines(rivers)
	_model = Model.build(terrain, graph, _true_positions(graph, terrain), _rivers)
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
static func _relief_of(tile_id: String, center: Vector2, flat: bool = false) -> Dictionary:
	if _relief_cache.has(tile_id):
		return _relief_cache[tile_id]
	if flat:
		# High ground is one flat plate: its height and its colour say what it is.
		_relief_cache[tile_id] = {"base": 1, "sea": [], "land": [], "lakes": []}
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
	# A tile with a warehouse is built on: its streets and slots need level ground.
	if bool(((_model.get("tiles", {}) as Dictionary).get(tile_id, {}) as Dictionary).get("store", false)):
		return 0.0
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
		var high := HIGH_BAND.has(str(t["type"]))
		var rel: Dictionary = _relief_of(str(tid), c, high)
		for i in range(6):
			var a := hexp[i]
			var b := hexp[(i + 1) % 6]
			var n := ((a + b) * 0.5 - c).normalized()
			if n.x + n.y <= 0.01:
				continue
			var wall: Color = (_WALL_SEA if is_sea else _WALL).lightened(0.22 * maxf(0.0, n.dot(_SUN)))
			_quad(verts, cols, idx, iso(a, h), iso(b, h), iso(b, 0.0), iso(a, 0.0), wall)
		var top: Color = sea_cols[0 if str(t["type"]) == "deep_sea" else 2] if is_sea else sea_cols[5]
		if high:
			top = band_cols[clampi(int(HIGH_BAND[str(t["type"])]), 0, band_cols.size() - 1)]
		_poly(verts, cols, idx, hexp, h, top)
		for e in rel["sea"]:
			_poly(verts, cols, idx, e["p"], h, sea_cols[int(e["b"])])
		if not is_sea:
			for e in rel["land"]:
				var col: Color = band_cols[clampi(int(e["b"]), 0, band_cols.size() - 1)]
				var lift := 0.0 if bool(t["store"]) else float(e["lift"])
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
			if str(d["kind"]) == "pylon":
				# A pylon stands on its feet, which are far narrower than its arms.
				front = (d["at"] as Vector2) + Vector2(0.0, side * 0.12)
			var origin := Vector2(front.x - (used.position.x + used.size.x * 0.5) * k,
				front.y - used.end.y * k)
			d["tex_rect"] = Rect2(origin, Vector2(tex.get_width(), tex.get_height()) * k)
			d["rect"] = Rect2(origin + used.position * k, used.size * k)
		else:
			var rise := side * (1.6 if str(d["kind"]) == "pylon" else 0.6)
			var top := iso(pos, h + rise)
			d["rect"] = Rect2(top.x - side * ISO_X, top.y - side * ISO_Y,
				side * 2.0 * ISO_X, side * 2.0 * ISO_Y + rise * ISO_RISE)
			if str(d["kind"]) == "pylon":
				d["rect"] = Rect2(top.x - side * 0.3, top.y, side * 0.6, rise * ISO_RISE)
		_standing.append(d)
	_standing.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["depth"]) < float(b["depth"]))


func _build_lines() -> void:
	var tiles: Dictionary = _model.get("tiles", {})
	var by_iid: Dictionary = {}
	for s in _standing:
		by_iid[str(s["iid"])] = s
	_build_roads(tiles)
	# Any way that cannot follow the streets (two tiles that do not touch) is a plain line.
	for l in _model.get("lines", []):
		var mode := str(l["mode"])
		if mode == Model.MODE_CABLE or Model.PIPE_MODES.has(mode):
			continue
		var pts := PackedVector2Array()
		for node in l["pts"]:
			pts.append(iso(node["p"], _ground_h(node)))
		_links.append({"mode": mode, "pts": pts})

	# Pipes, laid from baked pieces on a grid of directions; each end goes into the ground.
	var kit: bool = Pipes.ready()
	var slots: Dictionary = {}
	for l in _model.get("lines", []):
		var mode := str(l["mode"])
		if not Model.PIPE_MODES.has(mode):
			continue
		var path: Array = l["pts"]
		var sign_a: Vector2 = path[0]["p"]
		var sign_b: Vector2 = path[1]["p"]
		if kit:
			var legs: Array = Pipes.plan(_pipe_waypoints(path, slots))
			if legs.is_empty():
				continue
			var laid: Dictionary = Pipes.lay(legs, _road_plan, "s" if mode == "reinf_pipes" else "c")
			for item in laid["items"]:
				if str(item["kind"]) == "fit":
					_pipe_items.append(item)
					continue
				# A run is drawn tile by tile, so each tile takes its own place in depth.
				for poly in Pipes.kit().run_polys(item):
					poly["kind"] = "run"
					_pipe_items.append(poly)
			_pipe_lines.append({"pts": laid["line"], "reverse": bool(l.get("reverse", false))})
			sign_a = legs[0]["a"]
			sign_b = legs[0]["b"]
		else:
			var plain := PackedVector2Array()
			for node in path:
				plain.append(iso(node["p"], float(tiles[str(node["tile"])]["height"]) + 4.0))
			_pipes.append({"mode": mode, "pts": plain})
			_pipe_lines.append({"pts": plain, "reverse": bool(l.get("reverse", false))})
		var good := str(l.get("good", ""))
		if good != "":
			var at: Vector2 = sign_a.lerp(sign_b, clampf(22.0 / maxf(1.0, sign_a.distance_to(sign_b)), 0.0, 0.5))
			var side := (sign_b - sign_a).normalized().orthogonal()
			if side.x + side.y < 0.0:
				side = -side
			var foot: Vector2 = at + side * _SIGN_OFFSET
			var gh := float(tiles[str(path[0]["tile"])]["height"])
			_signs.append({"foot": iso(foot, gh), "top": iso(foot, gh + _SIGN_POST),
				"icon": Model.GoodIcons.texture_for(good, Model._internal_name(good)),
				"depth": foot.x + foot.y})
	for pl in _pipe_lines:
		var pts2: PackedVector2Array = pl["pts"]
		if bool(pl["reverse"]):
			pts2.reverse()
		var cum2 := PackedFloat32Array([0.0])
		for i in range(1, pts2.size()):
			cum2.append(cum2[i - 1] + pts2[i].distance_to(pts2[i - 1]))
		pl["pts"] = pts2
		pl["cum"] = cum2
		pl["total"] = cum2[cum2.size() - 1]

	# Cables hang from a building to its tile's pylon and from pylon to pylon.
	for l in _model.get("lines", []):
		if str(l["mode"]) != Model.MODE_CABLE:
			continue
		var pts := _cable_between(by_iid, l["ids"])
		if pts.size() >= 2:
			_cables.append(pts)

	_signs.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x["depth"]) < float(y["depth"]))
	_pipe_items.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x["depth"]) < float(y["depth"]))

	var n := 0
	for f in _model.get("flows", []):
		var mode := str(f["mode"])
		var pts := PackedVector2Array()
		if mode == Model.MODE_CABLE:
			pts = _cable_between(by_iid, f["ids"])
			if bool(f.get("reverse", false)):
				pts.reverse()
		elif Model.PIPE_MODES.has(mode):
			# What is in a pipe is shown on the pipe itself, not as crates along the way.
			continue
		else:
			pts = _street_line(f["pts"])
		if pts.size() < 2:
			continue
		var cum := PackedFloat32Array([0.0])
		for i in range(1, pts.size()):
			cum.append(cum[i - 1] + pts[i].distance_to(pts[i - 1]))
		var total := cum[cum.size() - 1]
		if total < 1.0:
			continue
		_flows.append({"pts": pts, "cum": cum, "total": total, "icon": f["icon"],
			"good": f["good"], "kind": str(f["kind"]), "live": f.get("live", []),
			"style": "power" if mode == Model.MODE_CABLE else "goods",
			"phase": fmod(float(n) * 0.618034, 1.0) * _TOKEN_SPACING})
		n += 1


## The streets in use, as baked pieces: a junction piece wherever roads meet, turn or change
## width, straights between them, and a truss bridge where a street crosses a river.
func _build_roads(tiles: Dictionary) -> void:
	_road_plan.clear()
	var roads: Atlas = _road_kit()
	var segs: Array = _model.get("roads", [])
	var nodes: Dictionary = {}                # rounded plan point -> {p, arms: {k: {level, h, paved}}}
	for s in segs:
		var h := float(tiles[str(s["tile"])]["height"])
		var level := int(s["level"])
		var ends: Array = [s["a"], s["b"]]
		for e in range(2):
			var here: Vector2 = ends[e]
			var there: Vector2 = ends[1 - e]
			var nd: Dictionary = nodes.get_or_add(Vector2i(here.round()), {"p": here, "arms": {}})
			var k: int = Pipes.k_of(there - here)
			var arms: Dictionary = nd["arms"]
			if not arms.has(k) or int(arms[k]["level"]) < level:
				arms[k] = {"level": level, "h": h, "paved": bool(s["paved"])}
		_road_plan.append({"a": s["a"], "b": s["b"],
			"half": roads.dim("half_%d" % level) + roads.dim("walk_%d" % level) if roads.ok() else _ROAD_HALF})
	if not roads.ok():
		# The pieces are not baked: plain lines instead.
		for s in segs:
			var h2 := float(tiles[str(s["tile"])]["height"])
			_links.append({"mode": "roads" if str(s["kind"]) != "spur" else Model.MODE_DRIVE,
				"pts": PackedVector2Array([iso(s["a"], h2), iso(s["b"], h2)])})
		return
	var arm := roads.dim("arm")
	var pieced: Dictionary = {}               # node key -> true: a junction piece stands there
	var climbs: Dictionary = {}               # node key -> the height the road there has to reach
	for key in nodes:
		var nd: Dictionary = nodes[key]
		var arms: Dictionary = nd["arms"]
		var ks: Array = arms.keys()
		ks.sort()
		if ks.size() < 2:
			continue
		var h0 := float(arms[ks[0]]["h"])
		var level_ground := true
		var paved := true
		for k in ks:
			level_ground = level_ground and is_equal_approx(float(arms[k]["h"]), h0)
			paved = paved and bool(arms[k]["paved"])
		if not level_ground:
			# Two tiles of different heights meet here: the lower one's road ramps up to the edge.
			var hi := h0
			for k in ks:
				hi = maxf(hi, float(arms[k]["h"]))
			climbs[key] = hi
			continue
		if ks.size() == 2 and posmod(int(ks[0]) + 6, 12) == int(ks[1]) \
				and int(arms[ks[0]]["level"]) == int(arms[ks[1]]["level"]):
			continue                              # straight on at one width: no piece
		var parts: Array = []
		for k in ks:
			parts.append("%d.%d" % [int(k), int(arms[k]["level"])])
		var name := "r_j_" + "_".join(parts)
		if not roads.has(name):
			continue
		pieced[key] = true
		_road_fits.append({"name": name, "at": iso(nd["p"], h0), "tint": Color.WHITE if paved else _UNPAVED})
	for s in segs:
		var tile := str(s["tile"])
		var h := float(tiles[tile]["height"])
		var a: Vector2 = s["a"]
		var b: Vector2 = s["b"]
		var length := a.distance_to(b)
		var dir := (b - a) / maxf(length, 0.001)
		# A straight runs a little way under each junction piece, so the piece's cut ends are hidden.
		var from := (arm - _ROAD_OVERLAP) if pieced.has(Vector2i(a.round())) else 0.0
		var to := length - ((arm - _ROAD_OVERLAP) if pieced.has(Vector2i(b.round())) else 0.0)
		if bool(s["rail"]):
			_links.append({"mode": "rail", "pts": PackedVector2Array([iso(a, h), iso(b, h)])})
		if to - from < 0.5:
			continue
		var k6 := posmod(Pipes.k_of(dir), 6)
		var level := int(s["level"])
		var tint: Color = Color.WHITE if bool(s["paved"]) else _UNPAVED
		var piece := "r_straight_%d_%d" % [k6, level]
		var step := iso(Pipes.dir_of(k6) * roads.dim("tile"))
		# Where this tile is the lower of two, the last stretch before the edge is a ramp. A
		# ramp is the flat road sheared upward along its length, which is exactly how a slope
		# projects, so the same piece draws it.
		var flat_from := from
		var flat_to := to
		for e in range(2):
			var end: Vector2 = b if e == 1 else a
			var key := Vector2i(end.round())
			if not climbs.has(key) or float(climbs[key]) <= h + 0.5:
				continue
			var rise := float(climbs[key]) - h
			var run := ramp_length(length)
			var r0 := (length - run) if e == 1 else run        # where the ramp meets the flat
			var edge := length if e == 1 else 0.0
			var foot := iso(a + dir * r0, h)
			var top := iso(a + dir * edge, h)
			var along := (top - foot).normalized()
			var board_run := foot.distance_to(top)
			var lift := Vector2(0.0, -rise * ISO_RISE)
			for poly in roads.run_polys({"name": piece, "a": iso(a + dir * minf(r0, edge), h),
					"b": iso(a + dir * maxf(r0, edge), h), "step": step}):
				var pts: PackedVector2Array = poly["points"]
				for i in range(pts.size()):
					pts[i] += lift * clampf((pts[i] - foot).dot(along) / board_run, -0.2, 1.2)
				poly["points"] = pts
				poly["tint"] = tint
				_road_polys.append(poly)
			# The bank the ramp stands on, seen from the side that faces the camera.
			var half := roads.dim("half_%d" % level) + roads.dim("walk_%d" % level)
			var side := iso(dir.orthogonal() * half)
			if side.y < 0.0:
				side = -side
			_ramp_fills.append(PackedVector2Array([foot + side, top + side, top + lift + side]))
			_ramp_fills.append(PackedVector2Array([top - side, top + side, top + lift + side, top + lift - side]))
			if e == 1:
				flat_to = minf(flat_to, r0)
			else:
				flat_from = maxf(flat_from, r0)
		if flat_to - flat_from < 0.5:
			continue
		for poly in roads.run_polys({"name": piece, "a": iso(a + dir * flat_from, h),
				"b": iso(a + dir * flat_to, h), "step": step}):
			poly["tint"] = tint
			_road_polys.append(poly)
		# A truss bridge where this stretch crosses a river. A bridge needs a clear straight its
		# own length, so it slides along the stretch to find one; where the long bridge has no
		# room the short one is tried, and with no room for that the road simply runs across.
		var hits: Array = []
		for line in _rivers.get(tile, []):
			var river: PackedVector2Array = line
			for i in range(river.size() - 1):
				var hit: Variant = Geometry2D.segment_intersects_segment(a, b, river[i], river[i + 1])
				if hit != null:
					hits.append((hit as Vector2).distance_to(a))
		hits.sort()
		var last := -INF
		for along_hit in hits:
			for kind in ["bridge", "bridge_short"]:
				var span := roads.dim(kind) * 0.5 + 2.0
				if flat_to - flat_from < span * 2.0:
					continue
				var at := clampf(float(along_hit), flat_from + span, flat_to - span)
				# The river has to stay under the bridge, and one bridge serves a river that
				# doubles back under the road.
				if absf(at - float(along_hit)) > span * 0.6 or at - last < span * 2.0:
					continue
				last = at
				var p := a + dir * at
				_pipe_items.append({"kind": "fit", "atlas": roads, "at": iso(p, h), "depth": p.x + p.y,
					"name": "r_bridge_%s%d_%d" % ["s_" if kind == "bridge_short" else "", k6, level]})
				break


## How much of a stretch of road of this length is ramp where it climbs to a higher tile.
static func ramp_length(length: float) -> float:
	return minf(60.0, length * 0.7)


static var _roads_atlas: Atlas = null
static func _road_kit() -> Atlas:
	if _roads_atlas == null:
		_roads_atlas = Atlas.new("roads")
	return _roads_atlas


## A path along the streets as board points. Where it crosses to a tile of another height it
## takes the ramp on the lower side, as the road does.
func _street_line(path: Array) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(path.size()):
		var node: Dictionary = path[i]
		var h := _ground_h(node)
		if not bool(node["edge"]):
			pts.append(iso(node["p"], h))
			continue
		# The edge is given once per tile. Both stand at the higher tile's level, and the
		# lower side reaches it over a ramp.
		var other := h
		for j in [i - 1, i + 1]:
			if j >= 0 and j < path.size() and bool(path[j]["edge"]) \
					and (path[j]["p"] as Vector2).is_equal_approx(node["p"]):
				other = _ground_h(path[j])
		var top := maxf(h, other)
		if h < top - 0.5:
			var before: bool = i > 0 and not bool(path[i - 1]["edge"])
			var inner: Dictionary = path[i - 1] if before else (path[i + 1] if i + 1 < path.size() else node)
			var back: Vector2 = (inner["p"] as Vector2) - (node["p"] as Vector2)
			var foot: Vector2 = (node["p"] as Vector2) + back.normalized() * ramp_length(back.length())
			if before:
				pts.append(iso(foot, h))
				pts.append(iso(node["p"], top))
			else:
				pts.append(iso(node["p"], top))
				pts.append(iso(foot, h))
		else:
			pts.append(iso(node["p"], top))
	return pts


## The ground under a path point: a crossing sits on the tile's edge at the tile's own height,
## anything else rides its terrace.
func _ground_h(node: Dictionary) -> float:
	var tile := str(node["tile"])
	if bool(node["edge"]):
		return float((_model["tiles"] as Dictionary)[tile]["height"])
	return _height_at(tile, node["p"])


## A pipe line's route as the waypoints the pipe planner takes. Pipes keep to their tile's own
## level, ignoring its terraces. Several pipes that end at one point are set side by side.
func _pipe_waypoints(path: Array, slots: Dictionary) -> Array:
	var tiles: Dictionary = _model["tiles"]
	var out: Array = []
	for i in range(path.size()):
		var node: Dictionary = path[i]
		var p: Vector2 = node["p"]
		var wp := {"p": p, "base": float(tiles[str(node["tile"])]["height"]), "edge": bool(node["edge"])}
		if bool(node["edge"]):
			var twin: Dictionary = path[i + 1] if i + 1 < path.size() and bool(path[i + 1]["edge"]) \
				and (path[i + 1]["p"] as Vector2).is_equal_approx(p) else path[i - 1]
			var here: Vector2 = tiles[str(node["tile"])]["center"]
			var there: Vector2 = tiles[str(twin["tile"])]["center"]
			wp["normal"] = (there - here).normalized()
		elif i == 0 or i == path.size() - 1:
			var key := Vector2i(p.round())
			var n := int(slots.get(key, 0))
			slots[key] = n + 1
			wp["p"] = p + Vector2(ISO_X, -ISO_X) * _PIPE_SLOT_GAP * float(n)
		out.append(wp)
	return out


## A cable between two standing things: from high on one to high on the other, with a sag.
func _cable_between(by_iid: Dictionary, ids: Array) -> PackedVector2Array:
	var pts := PackedVector2Array()
	if not by_iid.has(str(ids[0])) or not by_iid.has(str(ids[1])):
		return pts
	var ends: Array = []
	for id in ids:
		var s: Dictionary = by_iid[str(id)]
		var r: Rect2 = s["rect"]
		var share := 0.2 if str(s["kind"]) == "pylon" else 0.42
		ends.append(Vector2(r.get_center().x, r.position.y + r.size.y * share))
	var a: Vector2 = ends[0]
	var b: Vector2 = ends[1]
	var sag := a.distance_to(b) * _CABLE_SAG
	for k in range(_CABLE_STEPS + 1):
		var t := float(k) / float(_CABLE_STEPS)
		pts.append(a.lerp(b, t) + Vector2(0.0, sag * 4.0 * t * (1.0 - t)))
	return pts


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
	var road_tex: Texture2D = _road_kit().texture()
	if road_tex != null:
		for fit in _road_fits:
			var rr: Array = _road_kit().fit_rects(str(fit["name"]), fit["at"])
			draw_texture_rect_region(road_tex, rr[0], rr[1], fit["tint"])
		for fill in _ramp_fills:
			draw_colored_polygon(fill, _WALL.darkened(0.12))
		for poly in _road_polys:
			var tints := PackedColorArray()
			tints.resize((poly["points"] as PackedVector2Array).size())
			tints.fill(poly["tint"])
			draw_polygon(poly["points"], tints, poly["uvs"], road_tex)
	_draw_roads()
	for p in _pipes:
		_thick(p["pts"], _PIPE_EDGE, 9.0)
		_thick(p["pts"], _PIPE_REINF if str(p["mode"]) == "reinf_pipes" else _PIPE, 6.0)
	# Pipe pieces and signs stand among the buildings, so all three are drawn in one order of
	# depth, far to near.
	var atlas: Texture2D = Pipes.kit().texture()
	var pi := 0
	var si := 0
	for s in _standing:
		var depth := float(s["depth"])
		while pi < _pipe_items.size() and float(_pipe_items[pi]["depth"]) <= depth:
			_draw_pipe_item(_pipe_items[pi], atlas)
			pi += 1
		while si < _signs.size() and float(_signs[si]["depth"]) <= depth:
			_draw_sign(_signs[si])
			si += 1
		_draw_standing(s)
	while pi < _pipe_items.size():
		_draw_pipe_item(_pipe_items[pi], atlas)
		pi += 1
	while si < _signs.size():
		_draw_sign(_signs[si])
		si += 1
	for c in _cables:
		draw_polyline(c, _CABLE_DARK, 2.0)
		draw_polyline(c, _CABLE_STRIPE, 0.55)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_labels()
	_draw_hover()


func _draw_standing(s: Dictionary) -> void:
	var pos: Vector2 = s["pos"]
	var h := float(s["h"])
	var side := float(s["side"])
	var half := float(s.get("pad", side * 1.12)) * 0.5
	if str(s["kind"]) == "pylon":
		if s.get("sprite") != null:
			draw_texture_rect(s["sprite"], s["tex_rect"], false)
		else:
			var foot: Vector2 = s["at"]
			var r: Rect2 = s["rect"]
			draw_line(foot, Vector2(foot.x, r.position.y), _PIPE_EDGE, 3.0)
			for arm in [0.18, 0.36]:
				var y: float = r.position.y + r.size.y * float(arm)
				draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), _PIPE_EDGE, 2.2)
		return
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


## Every road-like way, in passes: all the kerbs, then all the asphalt, then the markings. Two
## roads that meet therefore merge into one surface, and a junction is a plain patch of asphalt
## with the centre lines stopping short of it.
func _draw_roads() -> void:
	for l in _links:
		if str(l["mode"]) == "nothing":
			# Bare ground: a cart track, no built way.
			_draw_dashes(l["pts"], 13.0, 9.0, _TRACK, 6.0, [])
	for l in _links:
		match str(l["mode"]):
			"roads":
				_thick(l["pts"], _KERB, _ROAD_HALF * 2.0 + 5.0)
			Model.MODE_DRIVE:
				_thick(l["pts"], _KERB, _DRIVE_HALF * 2.0 + 3.5)
	for j in _junctions:
		draw_circle(j["at"], float(j["width"]) * 0.5 * _JUNCTION_GROW + 2.5, _KERB)
	for l in _links:
		match str(l["mode"]):
			"roads":
				_thick(l["pts"], _ASPHALT, _ROAD_HALF * 2.0)
			Model.MODE_DRIVE:
				_thick(l["pts"], _ASPHALT, _DRIVE_HALF * 2.0)
	var guards: Array = []
	for j in _junctions:
		draw_circle(j["at"], float(j["width"]) * 0.5 * _JUNCTION_GROW, _ASPHALT)
		if int(j["arms"]) >= 2:
			guards.append([j["at"], float(j["width"]) * 0.5 * _JUNCTION_GROW + 6.0])
	for l in _links:
		if str(l["mode"]) == "roads":
			_draw_dashes(l["pts"], 12.0, 12.0, _DASH, 1.8, guards)
	# A give-way line across each arm where it meets the junction.
	for j in _junctions:
		if int(j["arms"]) < 3:
			continue
		for l in _links:
			if str(l["mode"]) != Model.MODE_DRIVE:
				continue
			var pts: PackedVector2Array = l["pts"]
			for e in [[pts[0], pts[1]], [pts[pts.size() - 1], pts[pts.size() - 2]]]:
				if (e[0] as Vector2).distance_to(j["at"]) > 1.0:
					continue
				var dir := ((e[1] as Vector2) - (e[0] as Vector2)).normalized()
				var at: Vector2 = (j["at"] as Vector2) + dir * (float(j["width"]) * 0.5 * _JUNCTION_GROW + 1.0)
				var across := dir.orthogonal() * _DRIVE_HALF * 0.8
				draw_line(at - across, at + across, _DASH, 1.4)
	for l in _links:
		if str(l["mode"]) == "rail":
			_thick(l["pts"], _BALLAST, 15.0)
			_draw_ties(l["pts"], 10.0, 13.0, _TIE, 2.6)
			_draw_offset_line(l["pts"], 4.0, _RAIL, 1.5)
			_draw_offset_line(l["pts"], -4.0, _RAIL, 1.5)


func _draw_pipe_item(item: Dictionary, atlas: Texture2D) -> void:
	var kit: Atlas = item.get("atlas", Pipes.kit())
	var tex: Texture2D = kit.texture() if item.has("atlas") else atlas
	if tex == null:
		return
	if str(item["kind"]) == "run":
		draw_colored_polygon(item["points"], Color.WHITE, item["uvs"], tex)
		return
	var rects: Array = kit.fit_rects(str(item["name"]), item["at"])
	draw_texture_rect_region(tex, rects[0], rects[1])


## A small sign on a post in front of a pipe, showing what it carries.
func _draw_sign(s: Dictionary) -> void:
	var foot: Vector2 = s["foot"]
	var top: Vector2 = s["top"]
	var plate := maxf(_SIGN_PLATE, _SIGN_MIN_PX / maxf(_zoom, 0.001))
	draw_line(foot, top, _PIPE_EDGE, maxf(1.6, plate * 0.1))
	var box := Rect2(top - Vector2(plate * 0.5, plate * 0.9), Vector2(plate, plate))
	draw_rect(box.grow(plate * 0.09), _PIPE_EDGE)
	draw_rect(box, _CREAM)
	var icon: Texture2D = s["icon"]
	if icon != null:
		draw_texture_rect(icon, box.grow(-plate * 0.08), false)


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


## Dashes along a line, leaving out any that start inside a guard circle ([centre, radius]).
func _draw_dashes(pts: PackedVector2Array, dash: float, gap: float, col: Color, width: float, guards: Array) -> void:
	_walk(pts, dash + gap, gap * 0.5, func(p: Vector2, dir: Vector2) -> void:
		for g in guards:
			if p.distance_to(g[0]) < float(g[1]) or (p + dir * dash).distance_to(g[0]) < float(g[1]):
				return
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


## Goods on the move. A shipment really in transit is one token with its quantity, sitting
## where its turns put it along the route and creeping through the turn ahead. A way with
## nothing in transit right now, and every run between a building and its warehouse, shows a
## steady trickle. Fluid in a pipe is a bright slug in the tube; power is a pulse on the cable.
func _draw_tokens(layer: Control) -> void:
	var box := clampf(44.0 * _zoom + 10.0, 16.0, 40.0)
	var view := Rect2(Vector2.ZERO, size).grow(box)
	var font := get_theme_default_font()
	_draw_pipe_flow(layer)
	# Power is shown on the pylons, not as something travelling.
	var tiles: Dictionary = _model.get("tiles", {})
	for s in _standing:
		if str(s["kind"]) != "pylon":
			continue
		var icon: Texture2D = (tiles.get(s["tile"], {}) as Dictionary).get("power_icon")
		var r: Rect2 = s["rect"]
		var at := Vector2(r.get_center().x, r.position.y + r.size.y * 0.52) * _zoom + _offset
		if icon != null and view.has_point(at):
			_token(layer, at, box * 0.9, icon)
	for f in _flows:
		var total := float(f["total"])
		var style := str(f["style"])
		var live: Array = f["live"]
		if not live.is_empty() and style == "goods":
			for sh in live:
				var duration := float(sh["duration"])
				var done := duration - float(sh["remaining"])
				var creep := 0.0 if bool(sh["waiting"]) else smoothstep(0.0, 1.0, fmod(_clock / _LIVE_CREEP_SECS, 1.0))
				var at := _along(f, clampf((done + creep) / duration, 0.0, 1.0) * total) * _zoom + _offset
				if view.has_point(at):
					_token(layer, at, box * 1.12, f["icon"])
					var text := str(int(sh["qty"]))
					var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
					var pill := Rect2(at + Vector2(-w * 0.5 - 5.0, box * 0.5), Vector2(w + 10.0, 16.0))
					layer.draw_rect(pill, _NAVY)
					layer.draw_string(font, pill.position + Vector2(5.0, 12.0), text,
						HORIZONTAL_ALIGNMENT_LEFT, -1, 12, DS.PALETTE.TEXT)
			continue
		var d := fmod(_clock * _TOKEN_SPEED + float(f["phase"]), _TOKEN_SPACING)
		if style != "goods":
			d = fmod(_clock * _TOKEN_SPEED * 1.6 + float(f["phase"]), _PULSE_SPACING)
		while d < total:
			var p := _along(f, d) * _zoom + _offset
			if view.has_point(p):
				match style:
					"power":
						layer.draw_circle(p, clampf(4.0 * _zoom + 1.5, 2.0, 5.0), _CABLE.lightened(0.4))
					_:
						_token(layer, p, box, f["icon"])
			d += _TOKEN_SPACING if style == "goods" else _PULSE_SPACING


## What a pipe carries, as bright slugs running along the tube the way the fluid goes.
func _draw_pipe_flow(layer: Control) -> void:
	var view := Rect2(Vector2.ZERO, size).grow(8.0)
	var width := clampf(3.2 * _zoom, 1.4, 4.0)
	for pl in _pipe_lines:
		var total := float(pl["total"])
		var d := fmod(_clock * _TOKEN_SPEED * 1.3, _PULSE_SPACING)
		while d < total:
			var p := _along(pl, d) * _zoom + _offset
			if view.has_point(p):
				layer.draw_line(p, _along(pl, minf(total, d + 8.0)) * _zoom + _offset,
					Color(1.0, 1.0, 1.0, 0.8), width)
			d += _PULSE_SPACING


func _along(f: Dictionary, d: float) -> Vector2:
	var pts: PackedVector2Array = f["pts"]
	var cum: PackedFloat32Array = f["cum"]
	var seg := 0
	while seg < cum.size() - 2 and cum[seg + 1] < d:
		seg += 1
	var span := maxf(0.001, cum[seg + 1] - cum[seg])
	return pts[seg].lerp(pts[seg + 1], clampf((d - cum[seg]) / span, 0.0, 1.0))


func _token(layer: Control, p: Vector2, box: float, icon: Texture2D) -> void:
	layer.draw_circle(p, box * 0.5 + 1.5, _NAVY)
	layer.draw_circle(p, box * 0.5, _CREAM)
	if icon != null:
		var isz := box * 0.74
		layer.draw_texture_rect(icon, Rect2(p - Vector2(isz, isz) * 0.5, Vector2(isz, isz)), false)


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
