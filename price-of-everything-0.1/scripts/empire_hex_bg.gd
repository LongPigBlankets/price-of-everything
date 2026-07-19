extends Control
## Empire view — animated amber hex-concentric field background (Milestone 7).
##
## A navy backdrop tiled with REGULAR hexagons (120deg corners, 30deg chevrons) in an OFFSET (brick)
## layout, rows pulled apart by ROW_GAP_FRAC so the gap reads as a zig-zag separator. Inside each cell sit
## INNER hexes built as an ANCHORED INWARD OFFSET of the outer hex (equal gaps, preserved angles), nested
## toward one of three bottom vertices (lean-left / straight-up / lean-right, cycling along the row).
##
## ANIMATION: every line rests LIGHT GREY and lights to bright GOLD where the animation's wavefront is.
## Brightness is sampled PER POINT (each hex edge is subdivided to SEG_LEN and coloured by the brightness
## at that point via draw_polyline_colors), so the gold is a moving BAND along the geometry with a gradient
## that falls off over ~half a hex (BAND), not a whole-cell flat fill. `_process` advances the clock and
## redraws; cheat `anim` cycles the mode. Modes (cheat var `empire_view_animation`, 1..4):
##   1 building-origin pulses — expanding gaussian rings out of each of the player's buildings
##   2 wave gradient          — gaussian crest bands roll diagonally across the field
##   3 flowing glow           — an organic noise cloud of brightness drifts over the field
##   4 hex explosions         — 1 random hex erupts in an expanding ring band; after it fades 2 erupt and
##                              clash; then back to 1, alternating 1-2-1-2 forever

const SQRT3 := 1.7320508

const NAVY := Color(0.015, 0.058, 0.105, 1.0)
const GREY := Color(0.62, 0.64, 0.67, 0.40)        # resting light-grey line
const GOLD := Color(0.93, 0.69, 0.33, 0.95)        # lit bright brassy peak

# Geometry knobs (tuned visually against the reference).
const HEX_HW := 92.0            # cell half-width (outer hex is regular: half-height = HW * 2/sqrt3)
const ROW_GAP_FRAC := 0.20      # gap between rows = this fraction of the cell height
const INNER := 3                # number of inner hexes per cell
const GAP_FRAC := 0.26          # constant inward gap between nested hexes, as a fraction of the apothem (hw)
const LINE_W := 1.5
# Overridable per host view: the goods graph runs a thinner lattice so its dense
# flow lines stay the loudest layer; the empire view keeps the default.
var line_width: float = LINE_W

# Animation rendering.
const BAND := 0.46 * HEX_HW     # gaussian half-width of the lit band (~half a hex) — gradient falloff
const SEG_LEN := 18.0           # px between sampled points along each edge (smaller = smoother gradient)
# Anim 1 ripples out of at most this many building origins. The brightness field
# is sampled ~18k times per frame, and every sample scans all origins — with an
# uncapped late-game empire that's millions of distance checks per frame for a
# background. Past the cap, an even subsample of buildings reads identically.
const A1_MAX_ORIGINS := 24

# Animation 1 — building-origin pulses (expanding gaussian rings).
const A1_SPEED := 0.5           # rings move outward at A1_SPEED * A1_WAVELEN px/sec
const A1_WAVELEN := 230.0       # px between consecutive rings
const A1_RANGE := 950.0         # px past which an origin's rings fade out
# Animation 2 — wave gradient (gaussian crest bands). A2_DIR is unit length already.
const A2_DIR := Vector2(0.80, 0.60)
const A2_WAVELEN := 300.0       # px between crests
const A2_SPEED := 0.5           # crests/sec
# Animation 3 — flowing glow (noise).
const A3_SCALE := 0.0016        # noise frequency (1/px) -> blob size
const A3_DRIFTX := 24.0         # px/sec drift through the noise field
const A3_DRIFTY := 8.0
const A3_LO := 0.42             # contrast window mapped to grey..gold
const A3_HI := 0.74
# Animation 4 — hex explosions (expanding gaussian ring, half-hex band width = BAND).
const A4_SPEED := 520.0         # ring expansion px/sec
const A4_LIFE := 2.6            # seconds an explosion lives (fades in then out)

# Cheat: which animation plays. Cycle 1->2->3->4->1 via `cycle_animation()` (debug terminal `anim`).
var empire_view_animation: int = 1

var _t: float = 0.0                                 # animation clock (seconds)
var _origins: PackedVector2Array = PackedVector2Array()   # building screen centres (anim 1)
var _explosions: Array = []                         # anim 4: [{origin: Vector2, t0: float}]
var _next_count: int = 1                            # anim 4: 1,2,1,2,... explosions per batch
var _noise: FastNoiseLite                           # anim 3
var _rng := RandomNumberGenerator.new()             # deterministic (seeded), NOT global randf
var _gw: Node = null                                # empire_graph_world, queried for building positions

# Static geometry cache. The hex lattice is fixed for a given control size —
# only the per-point COLOURS animate — yet the old _draw rebuilt every vertex,
# inward offset, and edge subdivision for ~600 loops each frame. The subdivided
# loops are now built once (and on resize); per frame only colours are computed.
var _loops: Array[PackedVector2Array] = []
var _geom_size := Vector2.ZERO


func _ready() -> void:
	add_to_group("empire_hex_bg")
	_rng.seed = 20260626
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.seed = 1337
	_noise.frequency = A3_SCALE


## empire_view hands us the node-graph layer so anim 1 can ripple out of the live building positions.
func set_graph_world(gw: Node) -> void:
	_gw = gw


## Override the ripple origins directly (used by the screenshot tool, which has no graph).
func set_origins(pts: PackedVector2Array) -> void:
	_origins = pts


## Cheat entry point: advance to the next animation (1->2->3->4->1) and return its label.
func cycle_animation() -> String:
	empire_view_animation = posmod(empire_view_animation, 4) + 1
	_explosions.clear()
	_next_count = 1
	return _anim_name()


func set_animation(n: int) -> String:
	empire_view_animation = clampi(n, 1, 4)
	_explosions.clear()
	_next_count = 1
	return _anim_name()


func _anim_name() -> String:
	match empire_view_animation:
		1: return "1 · building-origin pulses"
		2: return "2 · wave gradient"
		3: return "3 · flowing glow"
		4: return "4 · hex explosions"
	return str(empire_view_animation)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	if empire_view_animation == 1 and _gw != null and _gw.has_method("building_screen_points"):
		var pts: PackedVector2Array = _gw.call("building_screen_points")
		if pts.size() > A1_MAX_ORIGINS:
			# Even subsample so the ripple field stays spread across the empire.
			var sampled := PackedVector2Array()
			var step := float(pts.size()) / float(A1_MAX_ORIGINS)
			for i in range(A1_MAX_ORIGINS):
				sampled.append(pts[int(float(i) * step)])
			pts = sampled
		if pts.size() > 0:
			_origins = pts
	if empire_view_animation == 4:
		_update_explosions()
	queue_redraw()


func _draw() -> void:
	var rsz := size
	if rsz.x <= 1.0 or rsz.y <= 1.0:
		rsz = Vector2(1920, 1080)
	draw_rect(Rect2(Vector2.ZERO, rsz), NAVY, true)
	if _geom_size != rsz:
		_rebuild_geometry(rsz)
	# Per frame: colours only. Each loop's points are pre-subdivided; the lit
	# region is a band along the line because brightness is sampled PER POINT.
	for pts in _loops:
		var cols := PackedColorArray()
		cols.resize(pts.size())
		for i in range(pts.size()):
			cols[i] = GREY.lerp(GOLD, _brightness(pts[i], rsz))
		draw_polyline_colors(pts, cols, line_width, true)


## Build the static lattice: every cell's outer + nested loops, each subdivided
## to ~SEG_LEN sample points, stored closed (last point == first).
func _rebuild_geometry(rsz: Vector2) -> void:
	_geom_size = rsz
	_loops.clear()
	var hw := HEX_HW
	var ht := HEX_HW * 2.0 / SQRT3      # regular hexagon: all six sides equal
	var sh := 0.5 * ht                  # side vertices at +/- 0.5*ht (regular)
	var col_sp := 2.0 * hw
	var row_sp := ht + sh + ROW_GAP_FRAC * 2.0 * ht   # offset rows meet at (cy + sh); add the gap
	var cols := int(rsz.x / col_sp) + 4
	var rows := int(rsz.y / row_sp) + 4
	for rr in range(-1, rows):
		for c in range(-1, cols):
			var center := Vector2(float(c) * col_sp + float(posmod(rr, 2)) * hw, float(rr) * row_sp)
			# Cycle the nested-hex lean along the row: lean-left, straight-up, lean-right, ...
			var variant := posmod(c, 3)
			_collect_cell(center, hw, ht, sh, variant)


## Subdivide one closed hex loop to ~SEG_LEN spacing and store it for per-frame colouring.
func _collect_loop(corners: PackedVector2Array) -> void:
	if corners.size() < 2:
		return
	var pts := PackedVector2Array()
	var n := corners.size() - 1
	for i in range(n):
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[i + 1]
		var segs := maxi(1, int(a.distance_to(b) / SEG_LEN))
		for s in range(segs):
			pts.append(a.lerp(b, float(s) / float(segs)))
	pts.append(corners[n])
	_loops.append(pts)


# ---------------------------------------------------------------------------------------------------
# Brightness field — sampled per point, in [0,1]. The grey->gold lerp uses this.
# ---------------------------------------------------------------------------------------------------

func _brightness(p: Vector2, rsz: Vector2) -> float:
	match empire_view_animation:
		1: return _b_building(p, rsz)
		2: return _b_wave(p)
		3: return _b_glow(p)
		4: return _b_explode(p)
	return 0.0


## 1 — expanding rings out of each building (or the screen centre as a fallback). Each ring is a gaussian
## band of half-width BAND; rings move outward as the clock advances and fade past A1_RANGE. Max-combined.
func _b_building(p: Vector2, rsz: Vector2) -> float:
	var origins := _origins
	if origins.is_empty():
		origins = PackedVector2Array([rsz * 0.5])
	var b := 0.0
	var rng2 := A1_RANGE * A1_RANGE
	for o in origins:
		var d2 := p.distance_squared_to(o)        # cheap early-out before the sqrt
		if d2 > rng2:
			continue
		var d := sqrt(d2)
		var u := d / A1_WAVELEN - _t * A1_SPEED
		var x := (absf(u - round(u)) * A1_WAVELEN) / BAND   # px distance to nearest ring / band width
		b = maxf(b, exp(-x * x) * (1.0 - d / A1_RANGE))
	return b


## 2 — gaussian crest bands rolling along A2_DIR.
func _b_wave(p: Vector2) -> float:
	var u := p.dot(A2_DIR) / A2_WAVELEN - _t * A2_SPEED
	var x := (absf(u - round(u)) * A2_WAVELEN) / BAND
	return exp(-x * x)


## 3 — organic noise cloud drifting over the field.
func _b_glow(p: Vector2) -> float:
	if _noise == null:
		return 0.0
	var n := _noise.get_noise_2d(p.x + _t * A3_DRIFTX, p.y + _t * A3_DRIFTY)
	return smoothstep(A3_LO, A3_HI, n * 0.5 + 0.5)


## 4 — additive (so they "clash and merge") expanding gaussian ring bands from the active explosions.
func _b_explode(p: Vector2) -> float:
	var b := 0.0
	for ex in _explosions:
		var t0: float = ex["t0"]
		var age := _t - t0
		if age < 0.0 or age > A4_LIFE:
			continue
		var d := p.distance_to(ex["origin"] as Vector2)
		var x := (d - age * A4_SPEED) / BAND
		b += exp(-x * x) * sin(PI * (age / A4_LIFE))   # gaussian ring * fade-in/out envelope
	return minf(b, 1.0)


## Anim 4 state machine: when the current batch has fully faded, spawn the next — 1 hex, then 2, then 1…
func _update_explosions() -> void:
	var alive: Array = []
	for ex in _explosions:
		if _t - (ex["t0"] as float) <= A4_LIFE:
			alive.append(ex)
	_explosions = alive
	if _explosions.is_empty():
		for _i in range(_next_count):
			_explosions.append({"origin": _random_cell_center(), "t0": _t})
		_next_count = 2 if _next_count == 1 else 1


## A random hex cell centre on screen (deterministic via the seeded RNG, never global randf).
func _random_cell_center() -> Vector2:
	var rsz := size
	if rsz.x <= 1.0 or rsz.y <= 1.0:
		rsz = Vector2(1920, 1080)
	var hw := HEX_HW
	var ht := HEX_HW * 2.0 / SQRT3
	var sh := 0.5 * ht
	var col_sp := 2.0 * hw
	var row_sp := ht + sh + ROW_GAP_FRAC * 2.0 * ht
	var c := _rng.randi_range(0, maxi(int(rsz.x / col_sp), 1))
	var rr := _rng.randi_range(0, maxi(int(rsz.y / row_sp), 1))
	return Vector2(float(c) * col_sp + float(posmod(rr, 2)) * hw, float(rr) * row_sp)


# ---------------------------------------------------------------------------------------------------
# Geometry (static) — see the anchored-inward-offset note on _collect_cell.
# ---------------------------------------------------------------------------------------------------

## Collect a cell: the regular outer hex, then INNER hexes built as an ANCHORED INWARD OFFSET — the two
## anchored edges stay put (gap 0, overlapping the outer sides), every other edge is pushed inward by a
## constant k*gap (equal spacing), staying parallel to the outer edge (angles preserved). Three variants
## cycle along the row (edges numbered clockwise from the top peak): 0 lean-left anchors sides 4 & 5,
## 1 straight-up anchors sides 3 & 4, 2 lean-right anchors sides 2 & 3. Every loop is drawn glow-banded.
func _collect_cell(center: Vector2, hw: float, ht: float, sh: float, variant: int) -> void:
	var verts := _hex_verts(center, hw, ht, sh)
	var outer := PackedVector2Array(verts)
	outer.append(verts[0])
	_collect_loop(outer)

	# The two consecutive edges (edge i runs verts[i] -> verts[(i+1)%6]) the inner hexes stay flush to.
	var ea0 := 2                                  # straight-up: anchor = bottom peak, sides 3 & 4
	var ea1 := 3
	if variant == 0:                              # lean-left: anchor = bottom-left shoulder, sides 4 & 5
		ea0 = 3
		ea1 = 4
	elif variant == 2:                            # lean-right: anchor = bottom-right shoulder, sides 2 & 3
		ea0 = 1
		ea1 = 2

	# Inward unit normal + (normal . vertex) per edge — constant across the nests; only the offset scales.
	var nrm: Array[Vector2] = []
	var base: Array[float] = []
	for i in range(6):
		var a: Vector2 = verts[i]
		var b: Vector2 = verts[(i + 1) % 6]
		var mid := (a + b) * 0.5
		var nn := Vector2(-(b.y - a.y), b.x - a.x)
		if nn.dot(center - mid) < 0.0:            # flip to point INTO the cell
			nn = -nn
		nn = nn.normalized()
		nrm.append(nn)
		base.append(nn.dot(a))

	var gap := GAP_FRAC * hw
	for k in range(1, INNER + 1):
		if float(k) * gap >= hw * 0.95:           # safety: stop before the offset collapses the hex
			break
		var pts := PackedVector2Array()
		for j in range(6):
			var i0 := (j + 5) % 6                 # edge ending at vertex j
			var i1 := j                           # edge starting at vertex j
			var b0: float = base[i0] + (0.0 if (i0 == ea0 or i0 == ea1) else float(k) * gap)
			var b1: float = base[i1] + (0.0 if (i1 == ea0 or i1 == ea1) else float(k) * gap)
			pts.append(_intersect_lines(nrm[i0], b0, nrm[i1], b1))
		pts.append(pts[0])
		_collect_loop(pts)


## Intersection of the two lines n0.p = b0 and n1.p = b1. Adjacent hex edges are never parallel, so the
## determinant is non-zero in practice; ZERO is returned only as a degenerate guard.
func _intersect_lines(n0: Vector2, b0: float, n1: Vector2, b1: float) -> Vector2:
	var det := n0.x * n1.y - n0.y * n1.x
	if absf(det) < 0.000001:
		return Vector2.ZERO
	return Vector2((b0 * n1.y - b1 * n0.y) / det, (n0.x * b1 - n1.x * b0) / det)


## Regular pointy-top hexagon vertices (no closing point). hw = half-width, ht = half-height (centre to
## peak), sh = |y| of the side vertices.
func _hex_verts(c: Vector2, hw: float, ht: float, sh: float) -> PackedVector2Array:
	return PackedVector2Array([
		c + Vector2(0.0, -ht),     # top peak
		c + Vector2(hw, -sh),      # top-right shoulder
		c + Vector2(hw, sh),       # bottom-right shoulder
		c + Vector2(0.0, ht),      # bottom peak
		c + Vector2(-hw, sh),      # bottom-left shoulder
		c + Vector2(-hw, -sh),     # top-left shoulder
	])
