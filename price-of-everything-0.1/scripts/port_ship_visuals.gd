extends Node2D
## Container ships working the harbours: one berths against each arm, waits, and leaves.
##
## Same split as the smoke and the cranes, for the same reason — this moves every frame, and
## the layers carrying the map's static geometry repaint only when the view settles. Mounted
## just above `PortVisuals` so a hull reads as lying ALONGSIDE the quay rather than under it.
##
## THE CYCLE (owner spec, 2026-08-27), 12.5 s end to end per ship:
##   in over 2.5 s  ->  alongside for 5 s  ->  out over 5 s
## The second arm's ship is offset by 2.5 s, so the two are never doing the same thing at the
## same moment and the harbour reads as worked rather than choreographed.

const CanvasBatch := preload("res://scripts/canvas_batch.gd")

const IN_TIME := 2.5
const HOLD_TIME := 5.0
const OUT_TIME := 5.0
const CYCLE := IN_TIME + HOLD_TIME + OUT_TIME     # 12.5 s
## How far the second berth's ship lags the first.
const ARM_OFFSET := 2.5

## Ship length as a fraction of its arm's seaward run (owner spec: a third).
const LENGTH_FRAC := 1.0 / 3.0
## Half-beam as a fraction of length. Slim, as asked.
const BEAM_FRAC := 0.19
## How far out to sea a ship starts and ends its run, in ship lengths — far enough to be clear
## of the harbour mouth before it goes, rather than winking out over the water.
const APPROACH := 2.2

const HULL := Color("222f4a")          # dark navy
const HULL_INK := Color("11182a")
const CONTAINER_RED := Color("b0483a")
const CONTAINER_YELLOW := Color("d8ab3c")
const DECK := Color("39465f")

## Below this many pixels of length a ship is a speck and its containers are noise.
const MIN_SHIP_PX := 6.0
const CULL_MARGIN := 220.0

## SEA LANES (owner, 2026-08-27). Coastal traffic crossing the south of the continent:
## one stream enters mid-west and works round to the south-east, the other runs the reverse.
##
## The centreline is given in NORMALISED map coordinates (0..1 over the world bounds), traced
## off the land/water map that `tools/sea_map_probe.tscn` prints — the west approach hugs the
## seaboard at u~0.03, and the long leg runs along the southern water below the coast. The two
## lanes are the SAME line offset perpendicular by half LANE_SEPARATION each way, so they are
## parallel by construction and can never cross.
const LANE: Array[Vector2] = [
	Vector2(0.006, 0.44), Vector2(0.006, 0.72), Vector2(0.008, 0.86),
	Vector2(0.026, 0.955), Vector2(0.10, 0.994), Vector2(0.45, 0.996),
	Vector2(0.70, 0.992), Vector2(0.88, 0.975), Vector2(0.985, 0.950),
]
## World units between the two streams. Kept NARROW on purpose: the west seaboard is only a
## ~150 u channel at mid-map (see the land/water map from `tools/sea_map_probe.tscn`), so a
## wide separation puts the inshore lane on the beach. Validated by the probe, which samples
## both lanes against NavGrid and counts anything that lands on ground.
const LANE_SEPARATION := 110.0
const LANE_SHIPS := 14
const SEA_SHIP_LENGTH := 58.0
## World units per second. A crossing should take minutes, not seconds — this is background.
const SEA_SPEED := 62.0

## Set by world_map when it builds the layer.
var ports: Node = null

var _berths: Array = []
var _lanes: Array = []      # [{points, length}] one per direction
var _known := -1
var _clock := 0.0

static var _hull_tris := PackedVector2Array()
static var _hull_shape := PackedVector2Array()


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	_clock += delta
	if _clock > 86400.0:
		_clock = 0.0
	_refresh()
	_ensure_lanes()
	if not _berths.is_empty() or not _lanes.is_empty():
		queue_redraw()


## Berths come from the harbour plans, which PortVisuals rebuilds when a footprint changes.
## Polling the plan count notices a harbour appearing or moving; the geometry itself is fixed
## once planned, so there is nothing else to watch.
func _refresh() -> void:
	if ports == null or not is_instance_valid(ports):
		return
	var plans_value: Variant = ports.get("_midcentury_plans")
	if not (plans_value is Array):
		return
	var plans: Array = plans_value
	if plans.size() == _known:
		return
	_known = plans.size()
	_berths.clear()
	for plan_value in plans:
		var plan: Dictionary = plan_value
		if not bool(plan.get("valid", false)):
			continue
		var seaward: Vector2 = plan.get("seaward", Vector2.RIGHT)
		var tangent: Vector2 = plan.get("tangent", Vector2.UP)
		var basin: PackedVector2Array = plan.get("basin_polygon", PackedVector2Array())
		if basin.size() < 3 or seaward == Vector2.ZERO:
			continue
		# The basin is a rectangle laid on (tangent, seaward). Measure it in that frame rather
		# than assuming a winding order.
		var centre := Vector2.ZERO
		for point in basin:
			centre += point
		centre /= float(basin.size())
		var half_across := 0.0
		for point in basin:
			half_across = maxf(half_across, absf((point - centre).dot(tangent)))
		for side in [1.0, -1.0]:
			var arm_key := "left_arm_polygons" if side > 0.0 else "right_arm_polygons"
			var run := _seaward_run(plan.get(arm_key, []) as Array, seaward)
			if run <= 1.0:
				continue
			var length := run * LENGTH_FRAC
			# Alongside, not down the middle: half a beam plus a fender off the basin edge.
			var inset := maxf(half_across - length * BEAM_FRAC - 3.0, 0.0)
			_berths.append({
				"berth": centre + tangent * side * inset,
				# The bow ALWAYS leads: a ship comes in facing the quay and turns about while
				# alongside, so it leaves bow-first instead of reversing out of the harbour.
				"heading_in": (-seaward).angle(),
				"seaward": seaward,
				"length": length,
				"phase": 0.0 if side > 0.0 else ARM_OFFSET,
				"seed": RoadHash.pick("ship|%s|%d" % [str(plan.get("key", "")), int(side)], 7),
			})


## Build the two lane polylines once, from the map's own extent. Deferred to the first frame
## rather than done in _ready because the tiles have to exist to measure.
func _ensure_lanes() -> void:
	if not _lanes.is_empty():
		return
	var terrain := get_parent() as TileMapLayer
	if terrain == null or terrain.get("tiles") == null:
		return
	var tiles: Dictionary = terrain.get("tiles")
	if tiles.is_empty():
		return
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for coord in tiles:
		var world: Vector2 = terrain.map_to_local(
			terrain.map_coord_for_tile_coord(coord as Vector2i))
		lo = lo.min(world)
		hi = hi.max(world)
	var centre := PackedVector2Array()
	for point in LANE:
		centre.append(Vector2(lerpf(lo.x, hi.x, point.x), lerpf(lo.y, hi.y, point.y)))
	for side in [1.0, -1.0]:
		var offset := _offset_polyline(centre, side * LANE_SEPARATION * 0.5)
		_lanes.append({
			"points": offset,
			"length": _polyline_length(offset),
			# One direction runs the line forwards, the other backwards.
			"reverse": side < 0.0,
		})


## A polyline shifted sideways by `d`, using each vertex's averaged normal so the two lanes
## stay parallel round the corners instead of pinching where the line bends.
func _offset_polyline(pts: PackedVector2Array, d: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := pts.size()
	for i in n:
		var before: Vector2 = pts[maxi(i - 1, 0)]
		var after: Vector2 = pts[mini(i + 1, n - 1)]
		var dir := (after - before)
		if dir.length() < 0.001:
			dir = Vector2.RIGHT
		dir = dir.normalized()
		out.append(pts[i] + Vector2(-dir.y, dir.x) * d)
	return out


func _polyline_length(pts: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(1, pts.size()):
		total += pts[i - 1].distance_to(pts[i])
	return total


## Position and heading at `dist` along a polyline. Wraps, so a ship that runs off the end
## reappears at the start and the stream never empties.
func _along(pts: PackedVector2Array, total: float, dist: float) -> Array:
	var d := fposmod(dist, total)
	for i in range(1, pts.size()):
		var seg := pts[i] - pts[i - 1]
		var seg_len := seg.length()
		if d <= seg_len or i == pts.size() - 1:
			var u := 0.0 if seg_len < 0.001 else clampf(d / seg_len, 0.0, 1.0)
			return [pts[i - 1] + seg * u, seg.angle()]
		d -= seg_len
	return [pts[0], 0.0]


## How far a set of arm polygons reaches along the seaward axis — the arm's own length,
## measured rather than assumed, since the two arms are jittered to different runs.
func _seaward_run(polys: Array, seaward: Vector2) -> float:
	var lo := INF
	var hi := -INF
	for poly_value in polys:
		for point in (poly_value as PackedVector2Array):
			var d: float = (point as Vector2).dot(seaward)
			lo = minf(lo, d)
			hi = maxf(hi, d)
	return 0.0 if lo == INF else hi - lo


func _draw() -> void:
	if _berths.is_empty() and _lanes.is_empty():
		return
	var ppu := _pixels_per_unit()
	if ppu <= 0.0:
		return
	if _hull_tris.is_empty():
		_hull_tris = CanvasBatch.polygon_soup(hull_shape())
		if _hull_tris.is_empty():
			return   # would not triangulate; draw nothing rather than a mess
	var view := _visible_world_rect()
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var topside: Array = []
	for berth_value in _berths:
		var berth: Dictionary = berth_value
		var length: float = berth["length"]
		if length * ppu < MIN_SHIP_PX:
			continue
		var t := fposmod(_clock + float(berth["phase"]), CYCLE)
		var along := _travel(t)
		var pos: Vector2 = (berth["berth"] as Vector2) \
			+ (berth["seaward"] as Vector2) * length * APPROACH * along
		if not view.has_point(pos):
			continue
		var basis := Transform2D(float(berth["heading_in"]) + _turn(t), pos) \
			.scaled_local(Vector2(length, length))
		var base := pts.size()
		pts.resize(base + _hull_tris.size())
		cols.resize(base + _hull_tris.size())
		for i in _hull_tris.size():
			pts[base + i] = basis * _hull_tris[i]
			cols[base + i] = HULL
		topside.append({"basis": basis, "seed": int(berth["seed"])})
	# Sea traffic, into the SAME batch as the harbour ships.
	for lane_value in _lanes:
		var lane: Dictionary = lane_value
		var points: PackedVector2Array = lane["points"]
		var total: float = lane["length"]
		if total <= 1.0 or SEA_SHIP_LENGTH * ppu < MIN_SHIP_PX:
			continue
		var backwards: bool = lane["reverse"]
		for k in LANE_SHIPS:
			# Evenly spaced along the lane, all moving at one speed, so the spacing holds.
			var d := float(k) * total / float(LANE_SHIPS) + _clock * SEA_SPEED
			var at: Array = _along(points, total, total - d if backwards else d)
			var pos: Vector2 = at[0]
			if not view.has_point(pos):
				continue
			var heading: float = float(at[1]) + (PI if backwards else 0.0)
			var basis := Transform2D(heading, pos) 				.scaled_local(Vector2(SEA_SHIP_LENGTH, SEA_SHIP_LENGTH))
			var b := pts.size()
			pts.resize(b + _hull_tris.size())
			cols.resize(b + _hull_tris.size())
			for i in _hull_tris.size():
				pts[b + i] = basis * _hull_tris[i]
				cols[b + i] = HULL
			topside.append({"basis": basis, "seed": k})
	# Every hull on screen in one command; outlines and cargo go over the top per ship, which
	# is a handful for the few harbours and lane stretches ever in view at once.
	CanvasBatch.flush(self, pts, cols)
	for entry_value in topside:
		var entry: Dictionary = entry_value
		_draw_topside(entry["basis"], int(entry["seed"]))


## Where the ship sits along its run: 0 alongside, 1 fully out to sea. Smoothstepped at both
## ends, so it slows into the berth and gathers way leaving instead of sliding at a fixed rate.
func _travel(t: float) -> float:
	if t < IN_TIME:
		var u := t / IN_TIME                        # arriving: 1 -> 0
		return 1.0 - (u * u * (3.0 - 2.0 * u))
	if t < IN_TIME + HOLD_TIME:
		return 0.0                                  # alongside
	var v := (t - IN_TIME - HOLD_TIME) / OUT_TIME   # leaving: 0 -> 1
	return v * v * (3.0 - 2.0 * v)


## The turn about while alongside, in radians added to the arrival heading. Zero on the way
## in, PI by the time it leaves, so the bow always leads and a ship never reverses out of a
## harbour. Swung over the middle 60% of the hold, so it reads as manoeuvring rather than
## pivoting on the spot the instant it stops.
func _turn(t: float) -> float:
	if t <= IN_TIME:
		return 0.0
	if t >= IN_TIME + HOLD_TIME:
		return PI
	var u := clampf(((t - IN_TIME) / HOLD_TIME - 0.2) / 0.6, 0.0, 1.0)
	return PI * u * u * (3.0 - 2.0 * u)


func _draw_topside(basis: Transform2D, seed_val: int) -> void:
	var ring := PackedVector2Array()
	for point in hull_shape():
		ring.append(basis * point)
	ring.append(ring[0])
	draw_polyline(ring, HULL_INK, 1.0, true)
	var deck := PackedVector2Array([
		basis * Vector2(0.20, -0.12), basis * Vector2(-0.40, -0.12),
		basis * Vector2(-0.40, 0.12), basis * Vector2(0.20, 0.12)])
	draw_colored_polygon(deck, DECK)
	# Two rows of boxes down the deck, red and yellow alternating; the seed shifts which
	# colour leads so neighbouring harbours are not loading identical cargo.
	var boxes := 5
	for i in boxes:
		var x := lerpf(-0.35, 0.14, float(i) / float(boxes - 1))
		for row in [-1, 1]:
			var col := CONTAINER_RED if (i + row + seed_val) % 2 == 0 else CONTAINER_YELLOW
			var y := float(row) * 0.058
			var quad := PackedVector2Array([
				basis * Vector2(x - 0.042, y - 0.048),
				basis * Vector2(x + 0.042, y - 0.048),
				basis * Vector2(x + 0.042, y + 0.048),
				basis * Vector2(x - 0.042, y + 0.048)])
			draw_colored_polygon(quad, col)


## The hull in UNIT length: a slim pentagon — bow tip, two shoulders, two quarters — with
## every corner rounded and the bow rounded most. Built once and cached.
static func hull_shape() -> PackedVector2Array:
	if not _hull_shape.is_empty():
		return _hull_shape
	var b := BEAM_FRAC
	var corners := PackedVector2Array([
		Vector2(0.50, 0.0),         # bow
		Vector2(0.16, b),           # starboard shoulder
		Vector2(-0.50, b * 0.80),   # starboard quarter
		Vector2(-0.50, -b * 0.80),  # port quarter
		Vector2(0.16, -b),          # port shoulder
	])
	var radii := PackedFloat32Array([b * 1.05, b * 0.55, b * 0.40, b * 0.40, b * 0.55])
	var out := PackedVector2Array()
	var n := corners.size()
	for i in n:
		var prev := corners[(i + n - 1) % n]
		var here := corners[i]
		var next := corners[(i + 1) % n]
		var r: float = radii[i]
		var a := here + (prev - here).normalized() * minf(r, here.distance_to(prev) * 0.45)
		var c := here + (next - here).normalized() * minf(r, here.distance_to(next) * 0.45)
		# Quadratic Bezier through the corner — enough for a rounded tip at map scale.
		for s in 5:
			var u := float(s) / 4.0
			out.append(a.lerp(here, u).lerp(here.lerp(c, u), u))
	_hull_shape = out
	return out


func _pixels_per_unit() -> float:
	var vp := get_viewport()
	return 0.0 if vp == null else vp.get_canvas_transform().get_scale().x


func _visible_world_rect() -> Rect2:
	var vp := get_viewport()
	if vp == null:
		return Rect2()
	var size := vp.get_visible_rect().size
	if size.x <= 0.0:
		return Rect2()
	return (vp.get_canvas_transform().affine_inverse() * Rect2(Vector2.ZERO, size)).grow(CULL_MARGIN)
