extends Node2D
## Skeins of birds crossing the map: five sets, five birds apiece in a V, on five latitudes
## over the landmass.
##
## Same discipline as the smoke, the cranes and the ships: nothing is animated and nothing is
## stored between frames. A bird is `position = f(clock)` -- its set's along-track distance
## plus a fixed formation offset -- and its wings are a function of the same clock. The whole
## layer is 25 polylines and no state.
##
## A bird is TWO ARCHES (owner, 2026-08-27) that straighten and re-bow as they beat: each wing
## is a quadratic from the body out to the tip, and the flap moves only the control point. At
## the top and bottom of the stroke the arch is deepest; halfway through, the wing is straight.

const NOTE_TILE_H := 480.0

## Birds per set, laid out in a V (owner). NB the brief also said "three birds"; five is what
## the formation line asked for and is what this draws.
const FLOCK := 5
const SETS := 5
## One crossing every 30 s (owner).
const PERIOD := 30.0
## How far a set travels in a period, world units. Set so a skein crosses a comfortable
## stretch of map rather than teleporting across the whole continent.
const RUN := 5200.0
## Wingspan. "No larger than the puffs of smoke" -- a big puff runs ~90 u across, so this is
## comfortably under it while still being visible at working zoom.
const SPAN := 26.0
## Spacing behind and out to the side, per rank of the V, in wingspans.
const RANK_BACK := 0.95
const RANK_OUT := 0.62
## Wingbeats per second.
const FLAP_RATE := 2.6
## How deep the arch bows at the extremes, as a fraction of the half-span.
const ARCH := 0.42


const INK := Color(0.06, 0.06, 0.07, 1.0)
const LINE_W := 1.7
## Below this many pixels of wingspan a bird is a speck; the layer stands down.
const MIN_SPAN_PX := 5.0
const CULL_MARGIN := 200.0

## One entry per set: (start x, start y) as fractions of the world, then the HEADING in
## radians. Both the formation and the bird glyph are built in a forward-facing frame and
## rotated by that heading, so a set flies, points and forms up along its own course.
##
## Screen y runs DOWN, so south is +y: south-east is PI/4 and due south is PI/2.
## Three skeins run NORTH-WEST to SOUTH-EAST across the continent; two come down the eastern
## side from the NORTH-EAST (owner, 2026-08-27).
##
## The courses are aimed to CROSS THE PORT TILES (owner, 2026-08-27: that is where players
## spend their time, so that is where the sky should have something in it). The three harbours
## sit at (0.36, 0.86), (0.75, 0.80) and (0.81, 0.36) of the world box, and each of the first,
## second and fourth starts is the harbour MINUS half a run along its own heading, so the skein
## is overhead partway through its crossing rather than at the end of it. Checked, not assumed,
## by tools/bird_course_probe -- eyeballed starts put every skein thousands of units wide.
const COURSES: Array[Vector3] = [
	Vector3(0.183, 0.639, PI * 0.25),  # NW -> SE, over the south-western harbour at u~0.55
	Vector3(0.562, 0.566, PI * 0.25),  # NW -> SE, over the south-eastern harbour at u~0.60
	Vector3(0.220, 0.030, PI * 0.25),  # NW -> SE, inland
	Vector3(0.815, 0.079, PI * 0.50),  # NE -> SE, straight down over the Capital Port at u~0.5
	Vector3(0.880, 0.020, PI * 0.50),  # NE -> SE, further out
]

var _clock := 0.0
var _lo := Vector2.ZERO
var _hi := Vector2.ZERO
var _ready_bounds := false


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	_clock += delta
	if _clock > 86400.0:
		_clock = 0.0
	_ensure_bounds()
	if _ready_bounds:
		queue_redraw()


## World extent from the tiles, measured once. Same source the shipping lanes use, so the
## latitudes here and the sea lanes there are in the same frame.
func _ensure_bounds() -> void:
	if _ready_bounds:
		return
	var terrain := get_parent().find_child("TerrainLayer", true, false) as TileMapLayer
	if terrain == null:
		return
	var tiles: Variant = terrain.get("tiles")
	if not (tiles is Dictionary) or (tiles as Dictionary).is_empty():
		return
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for coord in (tiles as Dictionary):
		var world: Vector2 = terrain.map_to_local(
			terrain.map_coord_for_tile_coord(coord as Vector2i))
		lo = lo.min(world)
		hi = hi.max(world)
	_lo = lo
	_hi = hi
	_ready_bounds = true


func _draw() -> void:
	if not _ready_bounds:
		return
	var vp := get_viewport()
	if vp == null:
		return
	var ppu := vp.get_canvas_transform().get_scale().x
	if SPAN * ppu < MIN_SPAN_PX:
		return
	var view := (vp.get_canvas_transform().affine_inverse()
		* Rect2(Vector2.ZERO, vp.get_visible_rect().size)).grow(CULL_MARGIN)

	for s in SETS:
		# Each set starts a fifth of a period apart, so the sky is never empty and never has
		# all five skeins abreast.
		var u := fposmod(_clock / PERIOD + float(s) / float(SETS), 1.0)
		var lead := lead_of(s, u)
		# Fade in and out at the ends of the run, so the wrap is a skein flying out of sight
		# rather than one blinking off.
		var fade := clampf(minf(u, 1.0 - u) / 0.08, 0.0, 1.0)
		if fade <= 0.01:
			continue
		var col := Color(INK.r, INK.g, INK.b, fade)
		# The V is laid out in the flight frame: ranks fall BACK along the course and OUT to
		# either side of it, so the tip of the V leads in the direction of travel.
		var forward := Vector2.RIGHT.rotated(COURSES[s].z)
		var beam := Vector2(-forward.y, forward.x)
		for b in FLOCK:
			# Rank 0 leads; the rest fall back alternately to either side.
			var rank := int((b + 1) / 2)
			var side := 1.0 if b % 2 == 1 else -1.0
			var at := lead - forward * float(rank) * SPAN * RANK_BACK \
				+ beam * side * float(rank) * SPAN * RANK_OUT
			if not view.has_point(at):
				continue
			# Each bird beats slightly out of step with the one ahead.
			var flap := sin((_clock + float(b) * 0.11 + float(s) * 0.37) * TAU * FLAP_RATE)
			draw_polyline(_bird(at, flap, forward, beam), col, LINE_W, true)


## Where set `s` leads at fraction `u` of its run. Public so a shot tool can aim at a real
## skein instead of re-deriving this and getting it wrong -- which is exactly what happened
## the first time birds were photographed.
func lead_of(s: int, u: float) -> Vector2:
	var course: Vector3 = COURSES[s]
	var start := Vector2(lerpf(_lo.x, _hi.x, course.x), lerpf(_lo.y, _hi.y, course.y))
	return start + Vector2.RIGHT.rotated(course.z) * RUN * u


## One bird: one wingtip, in over the body, out to the other. `flap` in [-1, 1] is the stroke
## -- at the extremes the wings arch hard, at zero they are straight out.
##
## Built in the FLIGHT FRAME, not in screen axes: the wings span `beam`, across the course, and
## the arch bows along `forward`. Drawn on the screen axes instead, a bird flying east would
## have its wings spread east-west and be travelling wingtip-first.
func _bird(at: Vector2, flap: float, forward: Vector2, beam: Vector2) -> PackedVector2Array:
	var half := SPAN * 0.5
	var bow := half * ARCH * flap
	var left := at - beam * half
	var right := at + beam * half
	var out := PackedVector2Array()
	# One wing, tip inward to the body.
	for i in 5:
		out.append(_arc(left, at, bow, float(i) / 4.0, forward))
	# The other, body outward to the tip. Skips u=0, which is the body point just added.
	for i in range(1, 5):
		out.append(_arc(at, right, bow, float(i) / 4.0, forward))
	return out


## Quadratic from `a` to `b`, bowed along `bow_axis` by `bow` at its middle. That single
## control point is the whole wing: positive bows the arch one way, negative the other, zero
## draws it straight.
func _arc(a: Vector2, b: Vector2, bow: float, u: float, bow_axis: Vector2) -> Vector2:
	var mid := (a + b) * 0.5 + bow_axis * bow
	return a.lerp(mid, u).lerp(mid.lerp(b, u), u)
