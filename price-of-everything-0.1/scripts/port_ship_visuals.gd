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
## Extra clearance before a ship dares turn, in ship lengths on top of its own swept radius.
## "Well clear of the docks" (owner, 2026-08-27).
const TURN_MARGIN := 0.55
## How much farther out a ship runs once it is round, in ship lengths.
const AWAY_RUN := 2.4
## The three-point legs nose AHEAD by this much of a ship length, then come back to the
## clearance line -- never inside it.
const JOG := 0.30

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
## THE CHANNEL (owner, 2026-08-27). Traffic spreads across two tiles of sea: the water
## adjacent to the land plus one tile farther out. The LANE above is the INSHORE edge of that
## band -- it was validated hugging the coast -- and the channel extends OFFSHORE from it.
##
## Offshore is the POSITIVE normal all the way round: the route runs south down a coast that
## lies to its east, then east along a coast that lies to its north, and `(-dir.y, dir.x)` is
## seaward for both. So one sign widens the band into open water the whole way.
const TILE_HEIGHT := 480.0
const CHANNEL_TILES := 2.0
const CHANNEL := TILE_HEIGHT * CHANNEL_TILES
## Each direction keeps to its own half of the channel, like traffic. Within a half every ship
## gets its OWN lateral slot, so no two paths anywhere in the channel coincide.
const HALF_CHANNEL := CHANNEL * 0.5
## Keeps ships off the exact edges of their half.
const SLOT_MARGIN := 30.0
## Ships per direction (owner: 10-20 each way).
const LANE_SHIPS := 14

const SEA_SHIP_LENGTH := 58.0
## World units per second. A crossing should take minutes, not seconds — this is background.
const SEA_SPEED := 62.0

## PORT CALLERS (owner, 2026-08-27). Five ships each way peel out of the stream, work the
## Capital Port, and merge back in.
##
## NOTHING IS ANIMATED. A caller is still `position = f(clock)`: one baked ROUTE per
## direction, shared by all five, differing only in phase. A route is a handful of segments
## -- lane run, spur in, the berth manoeuvre we already have, spur out -- each with a
## duration, so a frame costs one walk over ~4 segments and a lerp. Ten callers are ten
## lookups; the geometry is built once at load.
## The harbour is named by tile because that is what identifies it in the plan; if the map
## ever stops carrying this tile the callers simply do not spawn.
const CAPITAL_TILE := "tile_24_7"
const CALLERS_PER_DIRECTION := 5
## Points sampled along each joining curve. Enough that the merge reads as a curve.
const SPUR_SAMPLES := 22
## The outbound spur is nudged sideways so leaving does not exactly retrace arriving.
const SPUR_SPLIT := 70.0

## Set by world_map when it builds the layer.
var ports: Node = null

var _berths: Array = []
var _lanes: Array = []      # [{points, length}] one per direction
var _callers: Array = []   # one baked route per direction, shared by its ships
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
	_build_callers()
	if not _berths.is_empty() or not _lanes.is_empty() or not _callers.is_empty():
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
			# HOW FAR OUT IS CLEAR. Measured, not guessed: the seaward-most point of EITHER arm,
			# plus half the ship (its swept radius when it pivots) plus a margin. A ship turning
			# any closer sweeps its own quay, which is exactly what the owner saw.
			var arm_tip := -INF
			for both_key in ["left_arm_polygons", "right_arm_polygons"]:
				for poly_value in (plan.get(both_key, []) as Array):
					for point in (poly_value as PackedVector2Array):
						arm_tip = maxf(arm_tip, (point as Vector2).dot(seaward))
			# Alongside, not down the middle: half a beam plus a fender off the basin edge.
			var inset := maxf(half_across - length * BEAM_FRAC - 3.0, 0.0)
			var berth_pos: Vector2 = centre + tangent * side * inset
			# Everything beyond this is open water; the turn happens past it and never inside.
			var reach: float = maxf(arm_tip - berth_pos.dot(seaward), 0.0)
			var clear_out: float = reach + length * (0.5 + TURN_MARGIN)
			_berths.append({
				"tile_id": str(plan.get("tile_id", "")),
				"berth": berth_pos,
				# The bow ALWAYS leads: a ship comes in facing the quay and turns about while
				# alongside, so it leaves bow-first instead of reversing out of the harbour.
				"heading_in": (-seaward).angle(),
				"seaward": seaward,
				"length": length,
				"clear": clear_out,
				"away": clear_out + length * AWAY_RUN,
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
	# One polyline PER SHIP, each on its own lateral slot across the channel. Precomputed
	# rather than offset per frame: 28 lines of nine points is nothing to hold, and offsetting
	# a polyline every frame for every ship would not be.
	for direction in 2:
		for k in LANE_SHIPS:
			var slot := SLOT_MARGIN + (HALF_CHANNEL - SLOT_MARGIN * 2.0) 				* (float(k) + 0.5) / float(LANE_SHIPS)
			var lateral := float(direction) * HALF_CHANNEL + slot
			var line := _offset_polyline(centre, lateral)
			_lanes.append({
				"points": line,
				"length": _polyline_length(line),
				"reverse": direction == 1,
				# Staggered along the route as well as across it, so a half is not a rank of
				# ships sailing abreast.
				"start": float(k) / float(LANE_SHIPS),
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


## Build the two port-call routes once, after the berths and lanes exist. Each is a list of
## segments with durations; every caller on it is the same route at a different phase.
func _build_callers() -> void:
	if not _callers.is_empty() or _berths.is_empty() or _lanes.is_empty():
		return
	var call_berth: Dictionary = {}
	for berth_value in _berths:
		var berth: Dictionary = berth_value
		if str(berth.get("tile_id", "")) == CAPITAL_TILE:
			call_berth = berth
			break
	if call_berth.is_empty():
		return   # no Capital Port on this map; the stream simply runs past
	var seaward: Vector2 = call_berth["seaward"]
	var standoff: Vector2 = (call_berth["berth"] as Vector2) + seaward * float(call_berth["away"])
	for direction in 2:
		# Callers ride the INSHORE edge of their half — they are the ones peeling off toward
		# land, so they cross no through-traffic to get there.
		var lane_index := direction * LANE_SHIPS
		var lane: Dictionary = _lanes[lane_index]
		var pts: PackedVector2Array = lane["points"]
		var total: float = lane["length"]
		var reverse: bool = lane["reverse"]
		# Leave the lane at whatever point is nearest the harbour approach.
		var best := 0.0
		var best_d := INF
		var steps := 240
		for k in steps:
			var d := total * float(k) / float(steps)
			var probe: Array = _along(pts, total, total - d if reverse else d)
			var gap: float = (probe[0] as Vector2).distance_to(standoff)
			if gap < best_d:
				best_d = gap
				best = d
		var at: Array = _along(pts, total, total - best if reverse else best)
		var join: Vector2 = at[0]
		var course := Vector2.RIGHT.rotated(float(at[1]) + (PI if reverse else 0.0))
		var side := Vector2(-course.y, course.x) * SPUR_SPLIT
		var spur_in := _spur(join, standoff, course, Vector2.ZERO)
		var spur_out := _spur(standoff, join, -seaward, side)
		var t_lane := total / SEA_SPEED
		var t_in := _polyline_length(spur_in) / SEA_SPEED
		var t_out := _polyline_length(spur_out) / SEA_SPEED
		_callers.append({
			"points": pts, "length": total, "reverse": reverse, "join": best,
			"spur_in": spur_in, "spur_in_len": _polyline_length(spur_in),
			"spur_out": spur_out, "spur_out_len": _polyline_length(spur_out),
			"berth": call_berth,
			"t_lane": t_lane, "t_in": t_in, "t_out": t_out,
			"period": t_lane + t_in + CYCLE + t_out,
		})


## WHERE A CALLER IS AT LOCAL TIME `u`, as [position, heading]. This is the whole trick:
## four segments walked in order, with no state carried between frames and none between
## ships. Every caller on a route evaluates this same function at its own phase.
##
##   lane      round the stream, starting and ending at the divert point
##   spur in   the joining curve, off the lane and down to the harbour approach
##   berth     the EXISTING manoeuvre, unchanged: in, alongside, back out, three-point turn
##   spur out  the joining curve back, merging into the stream
func _caller_at(route: Dictionary, u: float) -> Array:
	var t_lane: float = route["t_lane"]
	var t_in: float = route["t_in"]
	var reverse: bool = route["reverse"]
	if u < t_lane:
		var pts: PackedVector2Array = route["points"]
		var total: float = route["length"]
		var d: float = float(route["join"]) + u * SEA_SPEED
		var at: Array = _along(pts, total, total - d if reverse else d)
		return [at[0], float(at[1]) + (PI if reverse else 0.0)]
	if u < t_lane + t_in:
		var spur: PackedVector2Array = route["spur_in"]
		return _along(spur, float(route["spur_in_len"]), (u - t_lane) * SEA_SPEED)
	if u < t_lane + t_in + CYCLE:
		# The berth manoeuvre, reused exactly as the harbour ships use it.
		var berth: Dictionary = route["berth"]
		var move: Array = _manoeuvre(u - t_lane - t_in, float(berth["clear"]),
				float(berth["away"]), float(berth["length"]))
		var base_pos: Vector2 = berth["berth"]
		var sea: Vector2 = berth["seaward"]
		return [base_pos + sea * float(move[0]),
				float(berth["heading_in"]) + float(move[1])]
	var out_spur: PackedVector2Array = route["spur_out"]
	return _along(out_spur, float(route["spur_out_len"]),
			(u - t_lane - t_in - CYCLE) * SEA_SPEED)


## A joining curve: quadratic Bezier from `a` to `b`, leaving along `tangent` so the ship
## eases out of (or into) the stream instead of turning a corner. `bias` shifts the far end
## sideways, which is how the outbound spur avoids exactly retracing the inbound one.
func _spur(a: Vector2, b: Vector2, tangent: Vector2, bias: Vector2) -> PackedVector2Array:
	var target := b + bias
	var control := a + tangent.normalized() * a.distance_to(target) * 0.45
	var out := PackedVector2Array()
	for i in SPUR_SAMPLES:
		var u := float(i) / float(SPUR_SAMPLES - 1)
		out.append(a.lerp(control, u).lerp(control.lerp(target, u), u))
	return out


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
		var move: Array = _manoeuvre(t, float(berth["clear"]), float(berth["away"]), length)
		var pos: Vector2 = (berth["berth"] as Vector2) \
			+ (berth["seaward"] as Vector2) * float(move[0])
		if not view.has_point(pos):
			continue
		var basis := Transform2D(float(berth["heading_in"]) + float(move[1]), pos) \
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
		var d := float(lane["start"]) * total + _clock * SEA_SPEED
		var at: Array = _along(points, total, total - d if backwards else d)
		var pos: Vector2 = at[0]
		if not view.has_point(pos):
			continue
		var heading: float = float(at[1]) + (PI if backwards else 0.0)
		var basis := Transform2D(heading, pos) 			.scaled_local(Vector2(SEA_SHIP_LENGTH, SEA_SHIP_LENGTH))
		var b := pts.size()
		pts.resize(b + _hull_tris.size())
		cols.resize(b + _hull_tris.size())
		for i in _hull_tris.size():
			pts[b + i] = basis * _hull_tris[i]
			cols[b + i] = HULL
		topside.append({"basis": basis, "seed": int(d) % 7})
	# PORT CALLERS. Five per route, the same baked route at five phases -- the whole reason
	# this costs one lookup each rather than one animation each.
	for route_value in _callers:
		var route: Dictionary = route_value
		var period: float = route["period"]
		if period <= 0.0 or SEA_SHIP_LENGTH * ppu < MIN_SHIP_PX:
			continue
		for c in CALLERS_PER_DIRECTION:
			var u := fposmod(_clock + period * float(c) / float(CALLERS_PER_DIRECTION), period)
			var place: Array = _caller_at(route, u)
			var cpos: Vector2 = place[0]
			if not view.has_point(cpos):
				continue
			var cb := Transform2D(float(place[1]), cpos) \
				.scaled_local(Vector2(SEA_SHIP_LENGTH, SEA_SHIP_LENGTH))
			var cbase := pts.size()
			pts.resize(cbase + _hull_tris.size())
			cols.resize(cbase + _hull_tris.size())
			for i2 in _hull_tris.size():
				pts[cbase + i2] = cb * _hull_tris[i2]
				cols[cbase + i2] = HULL
			topside.append({"basis": cb, "seed": c})
	# Every hull on screen in one command; outlines and cargo go over the top per ship, which
	# is a handful for the few harbours and lane stretches ever in view at once.
	CanvasBatch.flush(self, pts, cols)
	for entry_value in topside:
		var entry: Dictionary = entry_value
		_draw_topside(entry["basis"], int(entry["seed"]))


## The whole harbour manoeuvre, as [distance seaward of the berth in WORLD UNITS, heading
## offset]. Absolute rather than a fraction because the safe turning distance is a measured
## property of each harbour, not a constant.
##
##   arrive    bow-first from open water into the berth
##   hold      alongside, no turn at all
##   back out  ASTERN, still bow-landward, all the way past `clear`
##   leg 1     ahead, swinging through 70 degrees
##   leg 2     ASTERN, swinging on to 115 -- the middle point of the three
##   leg 3     ahead, straightening onto 180
##   away      out to sea, bow leading
##
## THE INVARIANT: from the moment the turn starts until the ship is gone, the returned
## distance is never less than `clear` -- which is itself the arm tip plus the swept radius
## plus a margin. That is what keeps a turning hull off the quay. The jogs nose AHEAD of the
## line and come back to it; they never cross it.
func _manoeuvre(t: float, clear: float, away: float, length: float) -> Array:
	if t < IN_TIME:
		return [away * (1.0 - _ease(t / IN_TIME)), 0.0]
	if t < IN_TIME + HOLD_TIME:
		return [0.0, 0.0]
	var v := clampf((t - IN_TIME - HOLD_TIME) / OUT_TIME, 0.0, 1.0)
	var jog := length * JOG
	if v < 0.34:
		# Astern, out of the basin and past the arm tips, before any turning begins.
		return [clear * _ease(v / 0.34), 0.0]
	if v < 0.49:
		var a1 := _ease((v - 0.34) / 0.15)
		return [clear + jog * a1, PI * 0.39 * a1]
	if v < 0.64:
		var a2 := _ease((v - 0.49) / 0.15)
		return [clear + jog * (1.0 - a2), PI * (0.39 + 0.25 * a2)]
	if v < 0.79:
		var a3 := _ease((v - 0.64) / 0.15)
		return [clear + jog * a3, PI * (0.64 + 0.36 * a3)]
	var a4 := _ease((v - 0.79) / 0.21)
	return [clear + jog + (away - clear - jog) * a4, PI]


static func _ease(x: float) -> float:
	var u := clampf(x, 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)


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
