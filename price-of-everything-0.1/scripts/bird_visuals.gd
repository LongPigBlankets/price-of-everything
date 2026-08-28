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

## Latitudes as fractions of the world's height. Chosen over the landmass -- the southern
## fifth of the map is open sea and a skein there would be crossing water, not country.
const LATITUDES: Array[float] = [0.12, 0.26, 0.40, 0.54, 0.68]

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
		var lead := Vector2(
			lerpf(_lo.x - SPAN * 4.0, _lo.x - SPAN * 4.0 + RUN, u),
			lerpf(_lo.y, _hi.y, LATITUDES[s]))
		# Fade in and out at the ends of the run, so the wrap is a skein flying out of sight
		# rather than one blinking off.
		var fade := clampf(minf(u, 1.0 - u) / 0.08, 0.0, 1.0)
		if fade <= 0.01:
			continue
		var col := Color(INK.r, INK.g, INK.b, fade)
		for b in FLOCK:
			# Rank 0 leads; the rest fall back alternately to either side.
			var rank := int((b + 1) / 2)
			var side := 1.0 if b % 2 == 1 else -1.0
			var at := lead + Vector2(-float(rank) * SPAN * RANK_BACK,
				side * float(rank) * SPAN * RANK_OUT)
			if not view.has_point(at):
				continue
			# Each bird beats slightly out of step with the one ahead.
			var flap := sin((_clock + float(b) * 0.11 + float(s) * 0.37) * TAU * FLAP_RATE)
			draw_polyline(_bird(at, flap), col, LINE_W, true)


## One bird: left tip, up over the body, out to the right tip. `flap` in [-1, 1] is the
## stroke -- at the extremes the wings arch hard, at zero they are straight out.
func _bird(at: Vector2, flap: float) -> PackedVector2Array:
	var half := SPAN * 0.5
	var bow := half * ARCH * flap
	var out := PackedVector2Array()
	# Left wing, tip inward to the body.
	for i in 5:
		out.append(_arc(at + Vector2(-half, 0.0), at, bow, float(i) / 4.0))
	# Right wing, body outward to the tip. Skips u=0, which is the body point just added.
	for i in range(1, 5):
		out.append(_arc(at, at + Vector2(half, 0.0), bow, float(i) / 4.0))
	return out


## Quadratic from `a` to `b`, bowed perpendicular by `bow` at its middle. That single control
## point is the whole wing: positive bows the arch up, negative down, zero draws it straight.
func _arc(a: Vector2, b: Vector2, bow: float, u: float) -> Vector2:
	var mid := (a + b) * 0.5 + Vector2(0.0, -bow)
	return a.lerp(mid, u).lerp(mid.lerp(b, u), u)
