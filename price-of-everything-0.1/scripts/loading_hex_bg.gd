extends Control
## Loading-screen hex intro (reuses the empire-view hex field — regular outer hexes in
## an offset lattice, each holding 3 nested inner hexes built as an anchored inward
## offset). The lines rest light grey and light to gold. Driven by `_t` (seconds shown):
##   0–10 s   the grey lattice DRAWS IN — a soft diagonal wipe from top-left to
##            bottom-right, with a bright "pen" glow at the leading edge so it reads as
##            the hexes being drawn. Outer AND inner hexes draw in together.
##   10 s on  a GOLD wavefront sweeps the whole lattice (outer + inner): a very wavy
##            (sine-modulated) band travelling a corner path bottom-right → top-left →
##            top-right → bottom-right, looping every SWEEP_SECS until the load finishes.
##
## Each hex edge is subdivided to ~SEG_LEN and every sample is coloured individually
## (the draw-in + gold are evaluated per point), so the gold reads as a moving band along
## the geometry, not a per-hex flat fill. Animates in `_process`; if the main thread blocks
## during the heavy world build the clock pauses and resumes (the frame-yield fix is later).

const SQRT3 := 1.7320508
const HEX_HW := 92.0             # cell half-width (regular hex: half-height = HW * 2/sqrt3)
const ROW_GAP_FRAC := 0.20       # gap between offset rows, as a fraction of cell height
const INNER := 3                 # nested inner hexes per cell
const GAP_FRAC := 0.26           # inward gap between nested hexes, as a fraction of the apothem
const LINE_W := 1.5
const SEG_LEN := 18.0            # px between coloured samples along each edge

const NAVY := Color(0.015, 0.058, 0.105, 1.0)
const GREY := Color(0.62, 0.64, 0.67, 0.40)   # resting line colour
const PEN := Color(0.86, 0.90, 0.96, 0.90)    # bright leading edge while drawing in
const GOLD := Color(0.93, 0.69, 0.33, 0.95)   # lit wavefront

const DRAW_IN_SECS := 10.0       # grey lattice wipes in over this
const DRAW_IN_EDGE := 0.18       # softness of the wipe front (fraction of the diagonal coord)
const PEN_TRAIL := 0.06          # how far behind the front the pen glow lingers (diag coord)
const SWEEP_SECS := 20.0         # one full corner-path gold sweep (then loops)
const BAND := 0.12               # gold band half-width as a fraction of the screen diagonal
const WAVE_AMP := 0.08           # sine waviness of the wavefront (fraction of the diagonal)
const WAVE_FREQ := 6.0           # sine humps across the perpendicular extent
const WAVE_SPEED := 1.1          # how fast the waviness ripples

var _t := 0.0


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	queue_redraw()


## Jump the clock (used by the screenshot tool to grab specific frames).
func seek(t: float) -> void:
	_t = t
	queue_redraw()


func _draw() -> void:
	var rsz := size
	if rsz.x <= 1.0 or rsz.y <= 1.0:
		rsz = Vector2(1920, 1080)
	draw_rect(Rect2(Vector2.ZERO, rsz), NAVY)

	var hw := HEX_HW
	var ht := HEX_HW * 2.0 / SQRT3
	var sh := 0.5 * ht
	var col_sp := 2.0 * hw
	var row_sp := ht + sh + ROW_GAP_FRAC * 2.0 * ht
	var cols := int(rsz.x / col_sp) + 4
	var rows := int(rsz.y / row_sp) + 4
	for rr in range(-1, rows):
		for c in range(-1, cols):
			var center := Vector2(float(c) * col_sp + float(posmod(rr, 2)) * hw, float(rr) * row_sp)
			_draw_cell(center, hw, ht, sh, posmod(c, 3), rsz)


# Draw the regular outer hex, then INNER nested hexes built as an anchored inward offset
# (two anchored edges stay flush; every other edge is pushed inward by k*gap, angles
# preserved). Three variants cycle along the row. Every loop is drawn grey→gold per point.
func _draw_cell(center: Vector2, hw: float, ht: float, sh: float, variant: int, rsz: Vector2) -> void:
	var verts := _hex_verts(center, hw, ht, sh)
	var outer := PackedVector2Array(verts)
	outer.append(verts[0])
	_glow_loop(outer, rsz)

	# The two consecutive edges (edge i runs verts[i]→verts[(i+1)%6]) the inner hexes hug.
	var ea0 := 2     # straight-up: anchor = bottom peak, sides 3 & 4
	var ea1 := 3
	if variant == 0:     # lean-left: bottom-left shoulder, sides 4 & 5
		ea0 = 3
		ea1 = 4
	elif variant == 2:   # lean-right: bottom-right shoulder, sides 2 & 3
		ea0 = 1
		ea1 = 2

	var nrm: Array[Vector2] = []
	var base: Array[float] = []
	for i in range(6):
		var a: Vector2 = verts[i]
		var b: Vector2 = verts[(i + 1) % 6]
		var mid := (a + b) * 0.5
		var nn := Vector2(-(b.y - a.y), b.x - a.x)
		if nn.dot(center - mid) < 0.0:
			nn = -nn
		nn = nn.normalized()
		nrm.append(nn)
		base.append(nn.dot(a))

	var gap := GAP_FRAC * hw
	for k in range(1, INNER + 1):
		if float(k) * gap >= hw * 0.95:
			break
		var pts := PackedVector2Array()
		for j in range(6):
			var i0 := (j + 5) % 6
			var i1 := j
			var b0: float = base[i0] + (0.0 if (i0 == ea0 or i0 == ea1) else float(k) * gap)
			var b1: float = base[i1] + (0.0 if (i1 == ea0 or i1 == ea1) else float(k) * gap)
			pts.append(_intersect_lines(nrm[i0], b0, nrm[i1], b1))
		pts.append(pts[0])
		_glow_loop(pts, rsz)


# Subdivide a closed loop to ~SEG_LEN and colour each sample via _color_at.
func _glow_loop(corners: PackedVector2Array, rsz: Vector2) -> void:
	if corners.size() < 2:
		return
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var n := corners.size() - 1
	for i in range(n):
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[i + 1]
		var segs := maxi(1, int(a.distance_to(b) / SEG_LEN))
		for s in range(segs):
			var p := a.lerp(b, float(s) / float(segs))
			pts.append(p)
			cols.append(_color_at(p, rsz))
	pts.append(corners[n])
	cols.append(_color_at(corners[n], rsz))
	draw_polyline_colors(pts, cols, LINE_W, true)


func _color_at(p: Vector2, rsz: Vector2) -> Color:
	# Draw-in: a soft diagonal wipe (top-left → bottom-right) over DRAW_IN_SECS.
	var diag := (p.x / rsz.x + p.y / rsz.y) * 0.5     # 0 at top-left, 1 at bottom-right
	var wipe := clampf(_t / DRAW_IN_SECS, 0.0, 1.0)
	var appear := smoothstep(diag - DRAW_IN_EDGE, diag, wipe)
	if appear <= 0.001:
		return Color(GREY.r, GREY.g, GREY.b, 0.0)
	var col := GREY
	if _t < DRAW_IN_SECS:
		# Leading-edge pen glow: brightest where the line was just drawn, fading behind.
		var since := maxf(wipe - diag, 0.0)
		var pen := exp(-pow(since / PEN_TRAIL, 2.0))
		col = GREY.lerp(PEN, pen)
	col.a *= appear
	# Gold wavefront sweeps the drawn lattice after the draw-in.
	if _t > DRAW_IN_SECS:
		var g := _gold_at(p, rsz)
		col = col.lerp(Color(GOLD.r, GOLD.g, GOLD.b, GOLD.a * appear), g)
	return col


# Gold wavefront brightness at p (0..1): a wavy gaussian band travelling the corner path
# BR → TL → TR → BR, looping. The band is displaced by a sine of the coordinate
# perpendicular to its travel, so the front is "very wavy".
func _gold_at(p: Vector2, rsz: Vector2) -> float:
	var phase := _t - DRAW_IN_SECS
	if phase < 0.0:
		return 0.0
	var cycle := fmod(phase, SWEEP_SECS)
	var leg_dur := SWEEP_SECS / 3.0
	var leg := int(cycle / leg_dur)
	var lp := (cycle - float(leg) * leg_dur) / leg_dur   # 0..1 within the leg
	var start := Vector2(rsz.x, rsz.y)   # leg 0: BR → TL
	var goal := Vector2(0.0, 0.0)
	if leg == 1:                          # TL → TR
		start = Vector2(0.0, 0.0)
		goal = Vector2(rsz.x, 0.0)
	elif leg >= 2:                        # TR → BR
		start = Vector2(rsz.x, 0.0)
		goal = Vector2(rsz.x, rsz.y)
	var seg := goal - start
	var seg_len := seg.length()
	if seg_len < 1.0:
		return 0.0
	var dir := seg / seg_len
	var perp := Vector2(-dir.y, dir.x)
	var diag := rsz.length()
	var along := (p - start).dot(dir)
	var perpc := (p - start).dot(perp)
	var front := lp * seg_len
	var wavy := front + WAVE_AMP * diag * sin(perpc / diag * WAVE_FREQ * TAU + phase * WAVE_SPEED)
	var dd := (along - wavy) / (BAND * diag)
	return exp(-dd * dd)


func _intersect_lines(n0: Vector2, b0: float, n1: Vector2, b1: float) -> Vector2:
	var det := n0.x * n1.y - n0.y * n1.x
	if absf(det) < 0.000001:
		return Vector2.ZERO
	return Vector2((b0 * n1.y - b1 * n0.y) / det, (n0.x * b1 - n1.x * b0) / det)


# Regular pointy-top hexagon vertices (no closing point). hw = half-width, ht = half-height
# (centre→peak), sh = |y| of the side vertices.
func _hex_verts(c: Vector2, hw: float, ht: float, sh: float) -> PackedVector2Array:
	return PackedVector2Array([
		c + Vector2(0.0, -ht), c + Vector2(hw, -sh), c + Vector2(hw, sh),
		c + Vector2(0.0, ht), c + Vector2(-hw, sh), c + Vector2(-hw, -sh),
	])
