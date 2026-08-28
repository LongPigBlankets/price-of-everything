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

## Set by world_map when it builds the layer.
var ports: Node = null

var _berths: Array = []
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
	if not _berths.is_empty():
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
				# Bow points landward — a ship comes in facing the quay it will work.
				"heading": (-seaward).angle(),
				"seaward": seaward,
				"length": length,
				"phase": 0.0 if side > 0.0 else ARM_OFFSET,
				"seed": RoadHash.pick("ship|%s|%d" % [str(plan.get("key", "")), int(side)], 7),
			})


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
	if _berths.is_empty():
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
		var along := _travel(fposmod(_clock + float(berth["phase"]), CYCLE))
		var pos: Vector2 = (berth["berth"] as Vector2) \
			+ (berth["seaward"] as Vector2) * length * APPROACH * along
		if not view.has_point(pos):
			continue
		var basis := Transform2D(float(berth["heading"]), pos).scaled_local(Vector2(length, length))
		var base := pts.size()
		pts.resize(base + _hull_tris.size())
		cols.resize(base + _hull_tris.size())
		for i in _hull_tris.size():
			pts[base + i] = basis * _hull_tris[i]
			cols[base + i] = HULL
		topside.append({"basis": basis, "seed": int(berth["seed"])})
	# Every hull on screen in one command; outlines and cargo go over the top per ship, which
	# is a handful of calls for the few harbours ever in view at once.
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
