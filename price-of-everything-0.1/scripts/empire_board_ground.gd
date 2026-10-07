extends RefCounted
## Supply chain board — the ground: one height at every point of the map.
##
## TILE HEIGHTS. A tile stands at its tile height (empire_board_relief.gd plates): the average
## band level of its land, snapped to the nearest band, settled so that no river climbs and no two
## neighbours differ by more than the cap.
##
## STEPS. Where two neighbours stand at different heights the step between them does not follow
## their shared hex edge. It follows an organic line near it, the map's own contour between the two
## heights where one runs near the edge, eased back to the edge at its corners so the steps of a
## corner's three tiles meet there. A tile's REGION is its hex bounded by those lines instead of its
## edges. Two neighbours of one height share a straight edge and no step at all.
##
## RISES. Where the map's bands stand well above the tile height they rise from the tile along
## their own contours, rounded and with slivers dropped: one rise for each rung of RISE_LEVELS.
##
## SLOPES. The lower side of every step, every rise, every shore and every valley wall is a slope
## SLOPE_W wide, down from the higher level. Where the slopes of two steps overlap their falls add.
##
## WATER. Open water stands at SEA_LEVEL, a lake at its own level, a river at its own level, all
## below the land. A river runs in a valley VALLEY_DEPTH below the ground it crosses, level for
## BANK either side of it, then sloping up to the land. Followed downstream a river never rises:
## where its ground steps down it falls with it, and where its ground rises beside it it does not.
##
## THE LATTICE. The ground is worked out exactly at the nodes of one lattice over the whole map,
## NODE apart, and smoothed between them by a cubic B-spline (cell()), so no slope shows the
## lattice's squares. The drawn ground and everything standing on it read it the same way, so all
## agree, on both sides of every tile edge.
##
## Pure data: nothing here reads the sim.

const Relief := preload("res://scripts/empire_board_relief.gd")

const NODE := 12.0
const SLOPE_W := 22.0
const SEA_LEVEL := Relief.SEA_LEVEL
const VALLEY_DEPTH := 9.0
## The level floor beside a river, beyond its own half-width, before its valley wall.
const BANK := 8.0
## The heights rises stand at, and how far above the tile height a rung must be to rise.
const RISE_LEVELS: Array[float] = [50.0, 66.0, 88.0, 110.0, 132.0]
const RISE_MIN := 10.0
## Rises are rounded off by this much, and those left smaller than this are dropped.
const RISE_ROUND := 16.0
const RISE_MIN_AREA := 3000.0
## A step strays at most this far from its hex edge, and is drawn back to it over this share of the
## edge at either end. The line is looked for in steps of STEP_SCAN, at STEP_SAMPLES points.
const STEP_REACH := 50.0
const STEP_TAPER := 0.35
const STEP_SCAN := 4.0
const STEP_SAMPLES := 24
## A step that follows no contour sways this much either side, so it never runs ruler-straight.
const STEP_SWAY := 7.0
## A river's end this close to a tile edge crosses into the neighbour there.
const EDGE_REACH := 2.0
## A river's level is followed every this much of its length.
const RIVER_SAMPLE := 12.0
## A rise's outline keeps no two points closer than this.
const RISE_SPACING := 5.0
const HEX_HALF := Vector2(270.0, 240.0)
## Lines are filed by where they lie: in buckets one slope wide, a river's in buckets one valley wide.
const _BUCKET := 34.0
const _RIVER_BUCKET := 64.0
## The farthest a river's valley reaches from its middle: its widest half-width, its bank, its wall.
const _RIVER_REACH := 20.0 + BANK + SLOPE_W
## Ground rising less than this per map unit counts as level.
const LEVEL_SLOPE := 0.005
## The spline's weights at a cell's near and far side.
static var _corner_weights: Array[PackedFloat32Array] = [PackedFloat32Array([1.0 / 6.0, 4.0 / 6.0, 1.0 / 6.0, 0.0]),
	PackedFloat32Array([0.0, 1.0 / 6.0, 4.0 / 6.0, 1.0 / 6.0])]
## Lattice nodes are looked at in blocks this many a side, and a block with nothing near it that
## changes the ground is all one level.
const _BLOCK := 4

## The map: tile_id -> {center, height, water}. Filled by for_map (or by a test), then setup().
var tiles: Dictionary = {}
## The map's bands as [{b, p}] polygons in map space, in paint order: what rises are cut from.
var bands: Array = []
## Lakes as polygons in map space.
var lakes: Array = []
## Every river: tile_id -> [{points, start_width, end_width}] as RiverVisuals gives them.
var rivers: Dictionary = {}
## Which way rivers flow from tile to tile: [[upstream, downstream]].
var flows: Array = []
## The map's own level at a point (Relief.band_level of its band): what steps follow.
var level_at: Callable
## A tile's relief clipped to its hex, {sea, land, lakes}: what the board draws.
var relief: Callable
## Might the hex centred at a point hold open water at all: a quick test, true when unsure.
var may_be_wet: Callable = func(_center: Vector2) -> bool: return true

var _by_center: Dictionary = {}       # Vector2i(rounded centre) -> tile_id
var _cols: Dictionary = {}            # Vector2i(column, row) bucket -> [tile_id]
var _flow_down: Dictionary = {}       # tile -> {downstream tile: true}
var _flow_up: Dictionary = {}         # tile -> {upstream tile: true}
var _edges: Dictionary = {}           # "a|b" -> {from, to, n, offs} for a < b, n from a into b; {} when level
var _regions: Dictionary = {}         # tile -> its region, PackedVector2Array
var _hills: Dictionary = {}           # tile -> [{v, ring, box}]
var _lake_level: Dictionary = {}      # lake index -> level
var _lake_box: Array = []
var _river_runs: Dictionary = {}      # tile -> [{pts, levels, half}] densified, with levels
var _exits: Dictionary = {}           # tile -> [[point, level]] where its rivers leave it
var _solving: Dictionary = {}
var _steps_done: Dictionary = {}       # tile, or "a|b" edge -> its steps and shores are filed
var _hills_done: Dictionary = {}       # tile -> its rises and river valleys are filed
var _step_segs: Dictionary = {}       # bucket -> [[a, b, v]]
var _hill_segs: Dictionary = {}       # bucket -> [[a, b, v]]
var _shore_segs: Dictionary = {}      # bucket -> [[a, b, water level]]
var _river_segs: Dictionary = {}      # river bucket -> [[a, b, level a, level b, half]]
var _wet_tiles: Dictionary = {}       # tile -> its relief holds open water
var _wet_cells: Dictionary = {}       # Vector3i(bucket, tile) -> is that bucket of the tile open water
var _oriented: Dictionary = {}        # tile -> its steps, oriented for it
var _nodes: Dictionary = {}           # Vector2i -> height
var _cells: Dictionary = {}           # Vector2i -> cell()
var _blocks: Dictionary = {}          # Vector2i -> _block_level()

static var _shared: RefCounted = null
static var _shared_for := 0


## The ground of the live map, built once per map. `river_recs` is tile_id -> [river record],
## `plates` the settled tile heights (Relief.plates), `relief_of` the board's relief per tile.
static func for_map(terrain: Object, river_recs: Dictionary, plates: Dictionary, relief_of: Callable) -> RefCounted:
	if _shared != null and _shared_for == terrain.get_instance_id():
		return _shared
	var g: RefCounted = load("res://scripts/empire_board_ground.gd").new()
	var centers: Dictionary = {}
	var lines: Dictionary = {}
	for tid in Catalog.all_tile_ids():
		var coord: Vector2i = terrain.id_to_coord(str(tid))
		if coord.x < 0:
			continue
		var c: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(coord))
		centers[str(tid)] = c
		var kind := str(Catalog.tile_type(str(tid)))
		g.tiles[str(tid)] = {"center": c, "height": float(plates.get(str(tid), Relief.band_level(2))),
			"water": Relief.WATER_TILES.has(kind)}
	for tid in river_recs:
		var pts: Array = []
		for rec in river_recs[tid]:
			pts.append(rec["points"])
		lines[tid] = pts
	g.bands = HillBaked.polys()
	g.lakes = HillBaked.lakes()
	g.rivers = river_recs
	g.flows = Relief.river_flows(lines, centers)
	g.level_at = func(p: Vector2) -> float: return Relief.map_level(p)
	g.relief = relief_of
	g.may_be_wet = func(center: Vector2) -> bool: return Relief.hex_has_water(center)
	g.setup()
	_shared = g
	_shared_for = terrain.get_instance_id()
	return g


func setup() -> void:
	for tid in tiles:
		var c: Vector2 = tiles[tid]["center"]
		_by_center[Vector2i(c.round())] = str(tid)
		(_cols.get_or_add(_col_key(c), []) as Array).append(str(tid))
	for f in flows:
		(_flow_down.get_or_add(str(f[0]), {}) as Dictionary)[str(f[1])] = true
		(_flow_up.get_or_add(str(f[1]), {}) as Dictionary)[str(f[0])] = true
	for i in range(lakes.size()):
		_lake_box.append(_box_of(lakes[i]))
	var boxed: Array = []
	for e in bands:
		boxed.append({"b": int(e["b"]), "p": e["p"], "box": _box_of(e["p"])})
	bands = boxed


# ------------------------------------------------------------------ reading the ground

## The ground at a map point.
func height(p: Vector2) -> float:
	var f := p / NODE
	var i := floori(f.x)
	var j := floori(f.y)
	return cell_height(cell(i, j), f.x - float(i), f.y - float(j))


## Which way and how steeply the ground rises at a map point: height per map unit.
func gradient(p: Vector2) -> Vector2:
	var f := p / NODE
	var i := floori(f.x)
	var j := floori(f.y)
	return cell_gradient(cell(i, j), f.x - float(i), f.y - float(j))


## Is the lattice cell (i, j) level all over. Returns that height, or NAN where it is not.
func cell_level(i: int, j: int) -> float:
	return float(cell(i, j)[0])


## The lattice cell (i, j), worked out once: [its level or NAN, the heights of the sixteen nodes
## round it row by row from (i - 1, j - 1), and the ground at its four corners (i, j), (i + 1, j),
## (i, j + 1), (i + 1, j + 1)].
##
## The ground is the cubic B-spline of the nodes: smooth, its slope running on smoothly from cell to
## cell, never above or below the nodes round it, and level wherever they are. Its height is read
## off the spline at each cell's corners and blended between them, which is all the eye can tell
## apart; its slope, which the shading shows, is read off the spline itself wherever it is wanted.
func cell(i: int, j: int) -> Array:
	var key := Vector2i(i, j)
	var got: Variant = _cells.get(key)
	if got != null:
		return got
	var nodes := PackedFloat32Array()
	var level := node(i, j)
	for dy in range(-1, 3):
		for dx in range(-1, 3):
			var h := node(i + dx, j + dy)
			nodes.append(h)
			if absf(h - level) > 0.001:
				level = NAN
	var corners := PackedFloat32Array([level, level, level, level])
	if is_nan(level):
		for k in range(4):
			corners[k] = _spline_at(nodes, _corner_weights[k % 2], _corner_weights[k / 2])
	var out: Array = [level, nodes, corners]
	_cells[key] = out
	return out


## The ground at (u, v) across a cell (cell()), each from 0 to 1.
static func cell_height(cd: Array, u: float, v: float) -> float:
	if not is_nan(float(cd[0])):
		return float(cd[0])
	var c: PackedFloat32Array = cd[2]
	return lerpf(lerpf(c[0], c[1], u), lerpf(c[2], c[3], u), v)


## The rise of the ground at (u, v) across a cell, per map unit, off the spline.
static func cell_gradient(cd: Array, u: float, v: float) -> Vector2:
	if not is_nan(float(cd[0])):
		return Vector2.ZERO
	var nodes: PackedFloat32Array = cd[1]
	return Vector2(_spline_at(nodes, _spline_slope(u), _spline(v)), _spline_at(nodes, _spline(u), _spline_slope(v))) / NODE


## The spline over sixteen nodes with weights `wu` across and `wv` down.
static func _spline_at(nodes: PackedFloat32Array, wu: PackedFloat32Array, wv: PackedFloat32Array) -> float:
	var h := 0.0
	for y in range(4):
		h += (nodes[y * 4] * wu[0] + nodes[y * 4 + 1] * wu[1] + nodes[y * 4 + 2] * wu[2] + nodes[y * 4 + 3] * wu[3]) * wv[y]
	return h


## The cubic B-spline's weights for the four nodes along one way, at `t` from 0 to 1 between the
## middle two.
static func _spline(t: float) -> PackedFloat32Array:
	var t2 := t * t
	var t3 := t2 * t
	var r := 1.0 - t
	return PackedFloat32Array([r * r * r / 6.0, (3.0 * t3 - 6.0 * t2 + 4.0) / 6.0,
		(-3.0 * t3 + 3.0 * t2 + 3.0 * t + 1.0) / 6.0, t3 / 6.0])


## The same weights' rate of change along the way.
static func _spline_slope(t: float) -> PackedFloat32Array:
	var r := 1.0 - t
	return PackedFloat32Array([-r * r * 0.5, (3.0 * t * t - 4.0 * t) * 0.5, (-3.0 * t * t + 2.0 * t + 1.0) * 0.5, t * t * 0.5])


## The height at lattice node (i, j), worked out once.
func node(i: int, j: int) -> float:
	var key := Vector2i(i, j)
	var h: Variant = _nodes.get(key)
	if h != null:
		return float(h)
	var value := _block_level(Vector2i(floori(float(i) / float(_BLOCK)), floori(float(j) / float(_BLOCK))))
	if is_nan(value):
		value = _ground(Vector2(float(i), float(j)) * NODE, true)
	_nodes[key] = value
	return value


## The level of a block of _BLOCK by _BLOCK lattice nodes where nothing changes the ground: no step,
## rise, shore or river within reach of it. NAN where something does, and each node is worked out.
func _block_level(b: Vector2i) -> float:
	var got: Variant = _blocks.get(b)
	if got != null:
		return float(got)
	var lo := Vector2(b * _BLOCK) * NODE
	var hi := lo + Vector2.ONE * NODE * float(_BLOCK)
	var level := NAN
	var mapped := _prepare_near(lo, hi, true)
	if mapped and not _filed_near(_step_segs, lo, hi, SLOPE_W, _BUCKET) and not _filed_near(_hill_segs, lo, hi, SLOPE_W, _BUCKET) \
			and not _filed_near(_shore_segs, lo, hi, SLOPE_W, _BUCKET) \
			and not _filed_near(_river_segs, lo, hi, _RIVER_REACH, _RIVER_BUCKET):
		level = _ground(lo, true)
	_blocks[b] = level
	return level


## Is anything filed in `buckets` (of `size`) within `reach` of the box from `lo` to `hi`.
static func _filed_near(buckets: Dictionary, lo: Vector2, hi: Vector2, reach: float, size: float) -> bool:
	for x in range(floori((lo.x - reach) / size), floori((hi.x + reach) / size) + 1):
		for y in range(floori((lo.y - reach) / size), floori((hi.y + reach) / size) + 1):
			if buckets.has(Vector2i(x, y)):
				return true
	return false


## A tile's region: its hex, bounded by the steps to its neighbours instead of its edges.
func region(tile: String) -> PackedVector2Array:
	if _regions.has(tile):
		return _regions[tile]
	var hexp := hex_points(tiles[tile]["center"])
	var out := PackedVector2Array()
	for i in range(6):
		var e: Dictionary = _edge_of(tile, i)
		if e.is_empty():
			out.append(hexp[i])
			continue
		var offs: PackedFloat32Array = e["offs"]
		for k in range(STEP_SAMPLES):
			out.append((e["from"] as Vector2).lerp(e["to"], float(k) / float(STEP_SAMPLES)) + (e["n"] as Vector2) * offs[k])
	_regions[tile] = out
	return out


## The tile whose region a point lies in.
func region_at(p: Vector2) -> String:
	return _region_in(tile_at(p), p)


## The tile whose region a point of tile `t`'s hex lies in: `t`, or the neighbour a step has given it to.
func _region_in(t: String, p: Vector2) -> String:
	if t == "":
		return t
	for e in _steps_of(t):
		var from: Vector2 = e["from"]
		var run: Vector2 = e["run"]
		var s := clampf((p - from).dot(run) / run.length_squared(), 0.0, 1.0)
		if (p - from).dot(e["n"]) > _offset_at(e["offs"], s):
			return str(e["nb"])
	return t


## A tile's edges that are steps, oriented for the tile (_edge_of, with `run` from end to end).
func _steps_of(t: String) -> Array:
	var got: Variant = _oriented.get(t)
	if got != null:
		return got
	var out: Array = []
	for i in range(6):
		var e: Dictionary = _edge_of(t, i)
		if not e.is_empty():
			e["run"] = (e["to"] as Vector2) - (e["from"] as Vector2)
			out.append(e)
	_oriented[t] = out
	return out


## The tile whose hex a point lies in, or "" off the map.
func tile_at(p: Vector2) -> String:
	var k := _col_key(p)
	for dx in range(-1, 2):
		for dy in range(-2, 3):
			for tid in _cols.get(k + Vector2i(dx, dy), []):
				var d: Vector2 = p - (tiles[tid]["center"] as Vector2)
				if absf(d.y) <= HEX_HALF.y + 0.001 and absf(d.x) <= HEX_HALF.x - absf(d.y) * 0.5625 + 0.001:
					return str(tid)
	return ""


## The level a river runs at, at a point along it: [level at each point] for each of a tile's
## rivers, in RiverVisuals' order, with the points densified ({pts, levels, half}).
func river_runs(tile: String) -> Array:
	_solve_river(tile)
	return _river_runs.get(tile, [])


## Is a point of a tile open water, as the ground draws it: in a lake, or in the sea where no land
## lies over it. The sea's sheets run on under the land, which is painted over them.
static func is_water(rel: Dictionary, p: Vector2) -> bool:
	for w in rel.get("lakes", []):
		if Geometry2D.is_point_in_polygon(p, w):
			return true
	var in_sea := false
	for e in rel.get("sea", []):
		in_sea = in_sea or Geometry2D.is_point_in_polygon(p, e["p"])
	if not in_sea:
		return false
	for e in rel.get("land", []):
		if Geometry2D.is_point_in_polygon(p, e["p"]):
			return false
	return true


static func hex_points(center: Vector2) -> PackedVector2Array:
	var hh := HEX_HALF
	return PackedVector2Array([
		center + Vector2(hh.x, 0.0), center + Vector2(hh.x * 0.5, hh.y),
		center + Vector2(-hh.x * 0.5, hh.y), center + Vector2(-hh.x, 0.0),
		center + Vector2(-hh.x * 0.5, -hh.y), center + Vector2(hh.x * 0.5, -hh.y),
	])


# ------------------------------------------------------------------ the ground at a point

## The ground at a map point: `full` with its rises, shores and river valleys, otherwise the base a
## river takes its level from, the tiles and their steps only. What lies near the point must have
## been prepared (_prepare_near, _prepare_tile).
func _ground(p: Vector2, full: bool) -> float:
	var t := tile_at(p)
	if t == "":
		return Relief.band_level(2)
	var r := _region_in(t, p)
	var f := float(tiles[r]["height"])
	if full:
		for piece in _hills.get(r, []):
			if (piece["box"] as Rect2).has_point(p) and Geometry2D.is_point_in_polygon(p, piece["ring"]):
				f = maxf(f, float(piece["v"]))
	# Up the slopes of whatever stands higher within reach.
	var best: Dictionary = {}               # level -> nearest distance to ground at that level or above
	var k := Vector2i(floori(p.x / _BUCKET), floori(p.y / _BUCKET))
	var shore_near := false
	for x in range(k.x - 1, k.x + 2):
		for y in range(k.y - 1, k.y + 2):
			var key := Vector2i(x, y)
			_nearest_higher(_step_segs.get(key), p, f, best)
			if full:
				_nearest_higher(_hill_segs.get(key), p, f, best)
			shore_near = shore_near or _shore_segs.has(key)
	var h := _climb(f, best)
	if not full:
		return h
	# Down to open water.
	if _wet(t):
		var wet := false
		if shore_near:
			wet = is_water(relief.call(t, tiles[t]["center"]), p)
		else:
			# No shore within reach: the water or the land here runs on round the point unbroken.
			var cell := Vector3i(k.x, k.y, hash(t))
			if not _wet_cells.has(cell):
				_wet_cells[cell] = is_water(relief.call(t, tiles[t]["center"]), p)
			wet = bool(_wet_cells[cell])
		if wet:
			return _water_level(p)
	if shore_near:
		for x in range(k.x - 1, k.x + 2):
			for y in range(k.y - 1, k.y + 2):
				var got: Variant = _shore_segs.get(Vector2i(x, y))
				if got == null:
					continue
				for seg in got:
					var d := Geometry2D.get_closest_point_to_segment(p, seg[0], seg[1]).distance_to(p)
					if d < SLOPE_W:
						h = minf(h, lerpf(float(seg[2]), h, d / SLOPE_W))
	# Down into a river's valley.
	var rk := Vector2i(floori(p.x / _RIVER_BUCKET), floori(p.y / _RIVER_BUCKET))
	for x in range(rk.x - 1, rk.x + 2):
		for y in range(rk.y - 1, rk.y + 2):
			var got: Variant = _river_segs.get(Vector2i(x, y))
			if got == null:
				continue
			for seg in got:
				var a: Vector2 = seg[0]
				var b: Vector2 = seg[1]
				var q := Geometry2D.get_closest_point_to_segment(p, a, b)
				var d := q.distance_to(p)
				var floor_w := float(seg[4]) + BANK
				if d >= floor_w + SLOPE_W:
					continue
				var run := a.distance_to(b)
				var level := lerpf(float(seg[2]), float(seg[3]), q.distance_to(a) / run if run > 0.001 else 0.0)
				h = minf(h, lerpf(level, h, clampf((d - floor_w) / SLOPE_W, 0.0, 1.0)))
	return h


## The ground at `f` raised by the slopes of the higher ground near it: `best` is level -> the
## distance to the nearest ground at that level or above. Each rung between them adds its share,
## by how far up its slope the point stands.
static func _climb(f: float, best: Dictionary) -> float:
	if best.is_empty():
		return f
	var levels: Array = best.keys()
	levels.sort()
	var reach := INF
	var near: Array = []
	near.resize(levels.size())
	for k in range(levels.size() - 1, -1, -1):
		reach = minf(reach, float(best[levels[k]]))
		near[k] = reach
	var h := f
	var below := f
	for k in range(levels.size()):
		h += (float(levels[k]) - below) * (1.0 - float(near[k]) / SLOPE_W)
		below = float(levels[k])
	return h


## The nearest of `segs` ([[a, b, level]], or null) standing higher than `f`, kept in `best` by level.
static func _nearest_higher(segs: Variant, p: Vector2, f: float, best: Dictionary) -> void:
	if segs == null:
		return
	for seg in segs:
		var v := float(seg[2])
		if v <= f + 0.01:
			continue
		var d := Geometry2D.get_closest_point_to_segment(p, seg[0], seg[1]).distance_to(p)
		if d < SLOPE_W and d < float(best.get(v, INF)):
			best[v] = d


## The level of the open water at a point: a lake's own, else the sea's.
func _water_level(p: Vector2) -> float:
	for i in range(lakes.size()):
		if (_lake_box[i] as Rect2).has_point(p) and Geometry2D.is_point_in_polygon(p, lakes[i]):
			return _lake_level_of(i)
	return SEA_LEVEL


## A lake stands VALLEY_DEPTH below the lowest ground round it, and never below the sea.
func _lake_level_of(i: int) -> float:
	if _lake_level.has(i):
		return _lake_level[i]
	var ring: PackedVector2Array = lakes[i]
	var low := INF
	var stride := maxi(1, ring.size() / 16)
	for k in range(0, ring.size(), stride):
		var t := tile_at(ring[k])
		if t == "":
			continue
		for near in _around(t):
			_prepare_tile(str(near), false)
		var r := region_at(ring[k])
		var best: Dictionary = {}
		var kb := Vector2i(floori(ring[k].x / _BUCKET), floori(ring[k].y / _BUCKET))
		for x in range(kb.x - 1, kb.x + 2):
			for y in range(kb.y - 1, kb.y + 2):
				_nearest_higher(_step_segs.get(Vector2i(x, y)), ring[k], float(tiles[r]["height"]), best)
		low = minf(low, _climb(float(tiles[r]["height"]), best))
	var level := maxf(SEA_LEVEL, (low if low < INF else Relief.band_level(2)) - VALLEY_DEPTH)
	_lake_level[i] = level
	return level


## Does a tile's relief hold open water at all.
func _wet(tile: String) -> bool:
	if not _wet_tiles.has(tile):
		var wet := false
		if bool(may_be_wet.call(tiles[tile]["center"])):
			var rel: Dictionary = relief.call(tile, tiles[tile]["center"])
			wet = not (rel.get("sea", []) as Array).is_empty() or not (rel.get("lakes", []) as Array).is_empty()
		_wet_tiles[tile] = wet
	return bool(_wet_tiles[tile])


# ------------------------------------------------------------------ steps between tiles

## A tile's edge `i` as a step, oriented for the tile: {from, to, n (outward), offs (along n), nb},
## or {} where the edge is level or has no tile beyond it.
func _edge_of(tile: String, i: int) -> Dictionary:
	var c: Vector2 = tiles[tile]["center"]
	var hexp := hex_points(c)
	var a := hexp[i]
	var b := hexp[(i + 1) % 6]
	var nb: Variant = _by_center.get(Vector2i((c + ((a + b) * 0.5 - c) * 2.0).round()))
	if nb == null:
		return {}
	var lo := tile if tile < str(nb) else str(nb)
	var hi := str(nb) if tile < str(nb) else tile
	var key := lo + "|" + hi
	if not _edges.has(key):
		_edges[key] = _make_step(lo, hi)
	var e: Dictionary = _edges[key]
	if e.is_empty():
		return e
	if lo == tile:
		return {"from": e["from"], "to": e["to"], "n": e["n"], "offs": e["offs"], "nb": hi}
	# The same line seen from the other side: from its far end, offsets the other way.
	var offs := PackedFloat32Array()
	var src: PackedFloat32Array = e["offs"]
	for k in range(src.size() - 1, -1, -1):
		offs.append(-src[k])
	return {"from": e["to"], "to": e["from"], "n": -(e["n"] as Vector2), "offs": offs, "nb": lo}


## The step between tiles `a` and `b` (a < b) along their shared edge, or {} where they stand level.
## At each of STEP_SAMPLES + 1 points along the edge the map is read square across it, and the line
## laid where its level rises through the middle of the two heights nearest the edge; with no such
## crossing, well into the side the map there does not belong to. The line is then smoothed, given a
## little sway, and eased back to the edge toward its corners.
func _make_step(a: String, b: String) -> Dictionary:
	var ha := float(tiles[a]["height"])
	var hb := float(tiles[b]["height"])
	if absf(ha - hb) < 0.5:
		return {}
	var c: Vector2 = tiles[a]["center"]
	var nb_c: Vector2 = tiles[b]["center"]
	var hexp := hex_points(c)
	var from := Vector2.ZERO
	var to := Vector2.ZERO
	for i in range(6):
		var mid := (hexp[i] + hexp[(i + 1) % 6]) * 0.5
		if (c + (mid - c) * 2.0).distance_to(nb_c) < 2.0:
			from = hexp[i]
			to = hexp[(i + 1) % 6]
	var n := (to - from).orthogonal().normalized()
	if n.dot((from + to) * 0.5 - c) < 0.0:
		n = -n
	var up := 1.0 if hb > ha else -1.0        # along n, toward the higher tile
	var mid_level := (ha + hb) * 0.5
	var raw := PackedFloat32Array()
	for k in range(STEP_SAMPLES + 1):
		var q := from.lerp(to, float(k) / float(STEP_SAMPLES))
		var best := INF
		var prev := float(level_at.call(q - n * up * STEP_REACH))
		var t := -STEP_REACH + STEP_SCAN
		while t <= STEP_REACH + 0.001:
			var lv := float(level_at.call(q + n * up * t))
			if prev < mid_level and lv >= mid_level and absf(t - STEP_SCAN * 0.5) < absf(best):
				best = t - STEP_SCAN * 0.5
			prev = lv
			t += STEP_SCAN
		if best == INF:
			best = -STEP_REACH if float(level_at.call(q)) >= mid_level else STEP_REACH
		raw.append(best)
	for _pass in range(4):
		var smooth := raw.duplicate()
		for k in range(1, raw.size() - 1):
			smooth[k] = (raw[k - 1] + raw[k] * 2.0 + raw[k + 1]) * 0.25
		raw = smooth
	var phase := float(hash(a + "|" + b) % 1000) / 1000.0 * TAU
	var offs := PackedFloat32Array()
	for k in range(raw.size()):
		var s := float(k) / float(STEP_SAMPLES)
		var ease := smoothstep(0.0, STEP_TAPER, s) * smoothstep(0.0, STEP_TAPER, 1.0 - s)
		var sway := STEP_SWAY * sin(TAU * s * 2.0 + phase)
		offs.append(clampf((raw[k] + sway) * ease, -STEP_REACH, STEP_REACH) * up)
	return {"from": from, "to": to, "n": n, "offs": offs}


static func _offset_at(offs: PackedFloat32Array, s: float) -> float:
	var f := s * float(offs.size() - 1)
	var k := mini(floori(f), offs.size() - 2)
	return lerpf(offs[k], offs[k + 1], f - float(k))


## Everything that shapes the ground near a box of the map, filed for reading: the steps, and with
## `full` the shores, rises and river valleys, of every tile within reach of it. False where the
## box runs off the map.
func _prepare_near(lo: Vector2, hi: Vector2, full: bool) -> bool:
	var reach := STEP_REACH + SLOPE_W + NODE
	var mapped := true
	for x in range(5):
		for y in range(5):
			var p := Vector2(lerpf(lo.x - reach, hi.x + reach, float(x) / 4.0), lerpf(lo.y - reach, hi.y + reach, float(y) / 4.0))
			var t := tile_at(p)
			if t == "":
				mapped = mapped and (x == 0 or x == 4 or y == 0 or y == 4)
				continue
			_prepare_tile(t, full)
	return mapped and tile_at(lo) != "" and tile_at(hi) != ""


## What shapes one tile's ground, filed for reading: its steps, and with `full` its shores, rises and
## river valleys.
func _prepare_tile(t: String, full: bool) -> void:
	if not _steps_done.has(t):
		_steps_done[t] = true
		_file_steps(t)
	if full and not _hills_done.has(t):
		_hills_done[t] = true
		_file_shore(t)
		_file_rises(t)
		_file_rivers(t)


## A tile's steps to its neighbours, each filed once.
func _file_steps(t: String) -> void:
	for i in range(6):
		var e: Dictionary = _edge_of(t, i)
		if e.is_empty():
			continue
		var key := t + "|" + str(e["nb"]) if t < str(e["nb"]) else str(e["nb"]) + "|" + t
		if _steps_done.has(key):
			continue
		_steps_done[key] = true
		var v := maxf(float(tiles[t]["height"]), float(tiles[str(e["nb"])]["height"]))
		var offs: PackedFloat32Array = e["offs"]
		var prev := Vector2.INF
		for k in range(STEP_SAMPLES + 1):
			var q := (e["from"] as Vector2).lerp(e["to"], float(k) / float(STEP_SAMPLES)) + (e["n"] as Vector2) * offs[k]
			if prev != Vector2.INF:
				_file(_step_segs, prev, q, [prev, q, v])
			prev = q


# ------------------------------------------------------------------ rises

## A tile's rises, filed for reading.
func _file_rises(t: String) -> void:
	var pieces: Array = _rises(t)
	_hills[t] = pieces
	for piece in pieces:
		var ring: PackedVector2Array = piece["ring"]
		for k in range(ring.size()):
			var a := ring[k]
			var b := ring[(k + 1) % ring.size()]
			_file(_hill_segs, a, b, [a, b, float(piece["v"])])


## A tile's rises: for each rung of RISE_LEVELS well above its height, where the map's bands stand
## at or above that rung, rounded off, holes filled, slivers dropped, and kept to the tile's region.
func _rises(tile: String) -> Array:
	var out: Array = []
	if bool(tiles[tile]["water"]):
		return out
	var h := float(tiles[tile]["height"])
	var reg := region(tile)
	var box := _box_of(reg).grow(RISE_ROUND * 3.0)
	var window := PackedVector2Array([box.position, Vector2(box.end.x, box.position.y), box.end, Vector2(box.position.x, box.end.y)])
	# The map's bands above the tile, cut to round its region once: [[level, piece]].
	var near: Array = []
	for e in bands:
		var level := Relief.band_level(int(e["b"]))
		if level < h + RISE_MIN or not (e["box"] as Rect2).intersects(box):
			continue
		for piece in Geometry2D.intersect_polygons(e["p"], window):
			if not Geometry2D.is_polygon_clockwise(piece):
				near.append([level, piece])
	for rung in RISE_LEVELS:
		if rung < h + RISE_MIN:
			continue
		var merged: Array = []
		for e in near:
			if float(e[0]) >= rung:
				merged = _merge_in(merged, e[1])
		var rounded: Array = []
		for poly in merged:
			for opened in _offset(_offset([poly], -RISE_ROUND), RISE_ROUND):
				rounded = _merge_in(rounded, opened)
		var closed: Array = _offset(_offset(rounded, RISE_ROUND), -RISE_ROUND)
		for poly in closed:
			for piece in Geometry2D.intersect_polygons(poly, reg):
				if Geometry2D.is_polygon_clockwise(piece) or _area(piece) < RISE_MIN_AREA:
					continue
				var ring := _thinned(piece)
				if ring.size() >= 3:
					out.append({"v": rung, "ring": ring, "box": _box_of(ring)})
	return out


## An outline with points closer than RISE_SPACING to the last one kept left out: rounding leaves
## many, and each is read for every point of ground near it.
static func _thinned(ring: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in ring:
		if out.is_empty() or out[out.size() - 1].distance_to(p) >= RISE_SPACING:
			out.append(p)
	if out.size() > 3 and out[out.size() - 1].distance_to(out[0]) < RISE_SPACING:
		out.remove_at(out.size() - 1)
	return out


## Polygons grown (or shrunk, by a negative `by`) with rounded corners; holes are dropped.
static func _offset(polys: Array, by: float) -> Array:
	var out: Array = []
	for poly in polys:
		for grown in Geometry2D.offset_polygon(poly, by, Geometry2D.JOIN_ROUND):
			if not Geometry2D.is_polygon_clockwise(grown) and (grown as PackedVector2Array).size() >= 3:
				out = _merge_in(out, grown)
	return out


## A set of disjoint outlines with one more merged in; any holes the merge makes are filled.
static func _merge_in(polys: Array, poly: PackedVector2Array) -> Array:
	var cur := poly
	var out: Array = []
	for other in polys:
		var joined := Geometry2D.merge_polygons(cur, other)
		var outers: Array = []
		for j in joined:
			if not Geometry2D.is_polygon_clockwise(j):
				outers.append(j)
		if outers.size() == 1:
			cur = outers[0]
		else:
			out.append(other)
	out.append(cur)
	return out


# ------------------------------------------------------------------ shores

## A tile's shores, filed for reading: every edge of its relief with open water on one side and land
## on the other, with that water's level.
func _file_shore(t: String) -> void:
	if not _wet(t):
		return
	var c: Vector2 = tiles[t]["center"]
	var rel: Dictionary = relief.call(t, c)
	var hexp := hex_points(c)
	# The open sea: the sea's sheets with the land cut out of them, holes and all.
	var open: Array = []
	for e in rel.get("sea", []):
		open.append(e["p"])
	for e in rel.get("land", []):
		var cut: Array = []
		for w in open:
			cut.append_array(Geometry2D.clip_polygons(w, e["p"]))
		open = cut
	var rings: Array = []
	for w in open:
		rings.append([w, SEA_LEVEL])
	for lake in rel.get("lakes", []):
		var ring: PackedVector2Array = lake
		if ring.size() >= 3:
			rings.append([ring, _water_level(_inside(ring))])
	for entry in rings:
		var pts: PackedVector2Array = entry[0]
		for k in range(pts.size()):
			var a := pts[k]
			var b := pts[(k + 1) % pts.size()]
			if a.distance_squared_to(b) < 0.01 or _on_border((a + b) * 0.5, hexp):
				continue
			_file(_shore_segs, a, b, [a, b, float(entry[1])])


## A point inside a polygon: the middle of its first triangle.
static func _inside(ring: PackedVector2Array) -> Vector2:
	var tris := Geometry2D.triangulate_polygon(ring)
	if tris.size() < 3:
		return ring[0]
	return (ring[tris[0]] + ring[tris[1]] + ring[tris[2]]) / 3.0


# ------------------------------------------------------------------ rivers

## A tile's river valleys, filed for reading.
func _file_rivers(t: String) -> void:
	for run in river_runs(t):
		var pts: PackedVector2Array = run["pts"]
		var levels: PackedFloat32Array = run["levels"]
		for k in range(pts.size() - 1):
			_file(_river_segs, pts[k], pts[k + 1], [pts[k], pts[k + 1], levels[k], levels[k + 1], float(run["half"])],
				_RIVER_BUCKET)


## The levels of a tile's rivers, once those of every tile upstream of it are known: each river is
## followed downstream from where it comes in, and at every point it runs at no more than
## VALLEY_DEPTH below its ground there, nor above where it was, nor below the sea.
func _solve_river(tile: String) -> void:
	if _river_runs.has(tile) or _solving.has(tile):
		return
	_solving[tile] = true
	for up in _flow_up.get(tile, {}):
		_solve_river(str(up))
	if tiles.has(tile):
		for near in _around(tile):
			_prepare_tile(str(near), false)
	var runs: Array = []
	var exits: Array = []
	var c: Vector2 = tiles[tile]["center"] if tiles.has(tile) else Vector2.ZERO
	for rec in rivers.get(tile, []):
		var line: PackedVector2Array = rec["points"]
		var half := (float(rec.get("start_width", 0.0)) + float(rec.get("end_width", 0.0))) * 0.25
		if line.size() < 2 or not tiles.has(tile):
			continue
		var pts := _densify(line)
		var flipped := not _upstream_first(tile, c, pts)
		if flipped:
			pts.reverse()
		var level := _entry_level(tile, c, pts[0])
		var levels := PackedFloat32Array()
		for p in pts:
			level = maxf(minf(level, _ground(p, false) - VALLEY_DEPTH), SEA_LEVEL)
			levels.append(level)
		exits.append([pts[pts.size() - 1], level])
		if flipped:
			pts.reverse()
			levels.reverse()
		runs.append({"pts": pts, "levels": levels, "half": half})
	_river_runs[tile] = runs
	_exits[tile] = exits
	_solving.erase(tile)


## Does a tile's river run from its first point to its last? Its end toward the tile it flows into,
## or out to sea, is the lower; with nothing to tell, the end on the lower ground.
func _upstream_first(tile: String, c: Vector2, pts: PackedVector2Array) -> bool:
	var s0 := _end_score(tile, c, pts[0])
	var s1 := _end_score(tile, c, pts[pts.size() - 1])
	if s0 != s1:
		return s0 > s1
	return _ground(pts[0], false) >= _ground(pts[pts.size() - 1], false)


## +1 for a river's end coming in from upstream, -1 for one leaving downstream or into the sea, 0 when
## it cannot be told.
func _end_score(tile: String, c: Vector2, p: Vector2) -> int:
	var hexp := hex_points(c)
	var nb := ""
	for i in range(6):
		if Geometry2D.get_closest_point_to_segment(p, hexp[i], hexp[(i + 1) % 6]).distance_to(p) < EDGE_REACH:
			var mid := (hexp[i] + hexp[(i + 1) % 6]) * 0.5
			nb = str(_by_center.get(Vector2i((c + (mid - c) * 2.0).round()), ""))
	if nb != "":
		if (_flow_down.get(tile, {}) as Dictionary).has(nb) or bool(tiles[nb]["water"]):
			return -1
		if (_flow_up.get(tile, {}) as Dictionary).has(nb):
			return 1
		return 0
	if not Geometry2D.is_point_in_polygon(p, hexp):
		return -1
	return 0


## The level a river comes into a tile at: where a river upstream leaves its tile at that point.
func _entry_level(tile: String, c: Vector2, p: Vector2) -> float:
	var level := INF
	for up in _flow_up.get(tile, {}):
		for ex in _exits.get(str(up), []):
			if (ex[0] as Vector2).distance_to(p) < EDGE_REACH * 2.0:
				level = minf(level, float(ex[1]))
	return level


static func _densify(line: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array([line[0]])
	for i in range(1, line.size()):
		var a := line[i - 1]
		var b := line[i]
		var n := maxi(1, ceili(a.distance_to(b) / RIVER_SAMPLE))
		for k in range(1, n + 1):
			out.append(a.lerp(b, float(k) / float(n)))
	return out


# ------------------------------------------------------------------ helpers

## A tile and its neighbours.
func _around(tile: String) -> Array:
	var out: Array = [tile]
	var c: Vector2 = tiles[tile]["center"]
	var hexp := hex_points(c)
	for i in range(6):
		var nb: Variant = _by_center.get(Vector2i((c + ((hexp[i] + hexp[(i + 1) % 6]) * 0.5 - c) * 2.0).round()))
		if nb != null:
			out.append(str(nb))
	return out


static func _col_key(p: Vector2) -> Vector2i:
	return Vector2i(roundi(p.x / 405.0), roundi(p.y / 240.0))


static func _file(buckets: Dictionary, a: Vector2, b: Vector2, entry: Array, size: float = _BUCKET) -> void:
	var lo := Vector2i(floori(minf(a.x, b.x) / size), floori(minf(a.y, b.y) / size))
	var hi := Vector2i(floori(maxf(a.x, b.x) / size), floori(maxf(a.y, b.y) / size))
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			(buckets.get_or_add(Vector2i(x, y), []) as Array).append(entry)


static func _on_border(p: Vector2, hexp: PackedVector2Array) -> bool:
	for i in range(6):
		if Geometry2D.get_closest_point_to_segment(p, hexp[i], hexp[(i + 1) % 6]).distance_squared_to(p) < 1.0:
			return true
	return false


static func _box_of(pts: PackedVector2Array) -> Rect2:
	if pts.is_empty():
		return Rect2()
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	return r


static func _area(pts: PackedVector2Array) -> float:
	var a := 0.0
	for i in range(pts.size()):
		a += pts[i].x * pts[(i + 1) % pts.size()].y - pts[(i + 1) % pts.size()].x * pts[i].y
	return absf(a) * 0.5
