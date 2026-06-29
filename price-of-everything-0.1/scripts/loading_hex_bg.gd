extends Control
## Loading-screen hex intro (reuses the empire-view hex field — regular outer hexes in
## an offset lattice, each holding 3 nested inner hexes built as an anchored inward
## offset). Driven by `_t` (seconds shown):
##   0–10 s   the grey lattice DRAWS IN — a soft diagonal wipe from top-left to
##            bottom-right, with a bright "pen" glow at the leading edge so it reads as
##            the hexes being drawn. Outer AND inner hexes draw in together.
##   10–30 s  once the grey is in place, the hexes FILL GOLD one by one along a corner
##            path — bottom-left → top-left → top-right → bottom-right — over GOLD_FILL_SECS.
##            Each hex (outer or inner) ramps grey→gold over GOLD_FILL_PER_HEX. Ahead of
##            the lit region the light SPILLS over the edges as a smooth gradient that
##            falls off over ~half a hex, so the front reads as a soft luminous band.
##
## Each hex edge is subdivided to ~SEG_LEN. The per-hex fill comes from the hex centroid's
## position along the path; the spill gradient is evaluated PER POINT (so it's smooth), but
## only for hexes near the front (`near`) to keep the per-point path projection cheap.
## Animates in `_process`; if the main thread blocks during the world build the clock pauses.

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
const GOLD := Color(0.93, 0.69, 0.33, 0.95)   # filled hex

const DRAW_IN_SECS := 10.0       # grey lattice wipes in over this
const DRAW_IN_EDGE := 0.18       # softness of the wipe front (fraction of the diagonal coord)
const PEN_TRAIL := 0.06          # how far behind the front the pen glow lingers (diag coord)
const GOLD_FILL_SECS := 20.0     # the gold front travels the whole corner path in this time
const GOLD_FILL_PER_HEX := 0.5   # each hex ramps grey→gold over this
const SPILL_MAX := 0.55          # gold a point catches from lit neighbours, right at the front
const SPILL_FALLOFF := HEX_HW    # the spill glow fades to 0 over this distance ahead (~half a hex)
const SPILL_GATE := HEX_HW * 2.0 # only evaluate per-point spill for hexes within this of the front

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


# Draw the regular outer hex, then INNER nested hexes (anchored inward offset). Each loop's
# fill comes from its centroid's path position; the grey draw-in and the spill are per point.
func _draw_cell(center: Vector2, hw: float, ht: float, sh: float, variant: int, rsz: Vector2) -> void:
	var verts := _hex_verts(center, hw, ht, sh)
	var outer := PackedVector2Array(verts)
	outer.append(verts[0])
	_glow_loop(outer, rsz, _path_s(center, rsz))

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
		var sum := Vector2.ZERO
		for j in range(6):
			var i0 := (j + 5) % 6
			var i1 := j
			var b0: float = base[i0] + (0.0 if (i0 == ea0 or i0 == ea1) else float(k) * gap)
			var b1: float = base[i1] + (0.0 if (i1 == ea0 or i1 == ea1) else float(k) * gap)
			var v := _intersect_lines(nrm[i0], b0, nrm[i1], b1)
			pts.append(v)
			sum += v
		var ic := sum / 6.0
		pts.append(pts[0])
		_glow_loop(pts, rsz, _path_s(ic, rsz))


# Subdivide a closed loop to ~SEG_LEN and colour each sample. `s_hex` is the hex centroid's
# path position. `own` (per-hex fill) is uniform; the spill is evaluated per point but only
# when the hex is near the front (so most hexes skip the per-point path projection).
func _glow_loop(corners: PackedVector2Array, rsz: Vector2, s_hex: float) -> void:
	if corners.size() < 2:
		return
	var own := _own_fill(s_hex)
	var near := _near_front(s_hex, own, rsz)
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
			cols.append(_color_at(p, rsz, own, near))
	pts.append(corners[n])
	cols.append(_color_at(corners[n], rsz, own, near))
	draw_polyline_colors(pts, cols, LINE_W, true)


func _color_at(p: Vector2, rsz: Vector2, own: float, near: bool) -> Color:
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
	var gold := own
	# Spill: light bleeding over the edges from the lit region into this point, a smooth
	# gradient that falls to 0 over SPILL_FALLOFF (~half a hex) ahead of the fill front.
	if near and own < 1.0:
		var t_gold := _t - DRAW_IN_SECS
		var s_front := t_gold / (GOLD_FILL_SECS - GOLD_FILL_PER_HEX)
		var ahead := (_path_s(p, rsz) - s_front) * (2.0 * rsz.y + rsz.x)
		gold = maxf(gold, SPILL_MAX * (1.0 - smoothstep(0.0, SPILL_FALLOFF, maxf(ahead, 0.0))))
	if gold > 0.0:
		col = col.lerp(Color(GOLD.r, GOLD.g, GOLD.b, GOLD.a * appear), gold)
	return col


# Per-hex fill (0..1): a hex begins filling when the front (travelling BL→TL→TR→BR over
# GOLD_FILL_SECS) reaches its path position `s`, then ramps over GOLD_FILL_PER_HEX.
func _own_fill(s: float) -> float:
	if _t <= DRAW_IN_SECS:
		return 0.0
	var started := s * (GOLD_FILL_SECS - GOLD_FILL_PER_HEX)
	return clampf((_t - DRAW_IN_SECS - started) / GOLD_FILL_PER_HEX, 0.0, 1.0)


# A hex is "near the front" (so its points evaluate the per-point spill) if it's mid-fill,
# or unfilled but within SPILL_GATE arc-distance ahead of the fill front.
func _near_front(s_hex: float, own: float, rsz: Vector2) -> bool:
	if _t <= DRAW_IN_SECS or own >= 1.0:
		return false
	if own > 0.0:
		return true
	var s_front := (_t - DRAW_IN_SECS) / (GOLD_FILL_SECS - GOLD_FILL_PER_HEX)
	return (s_hex - s_front) * (2.0 * rsz.y + rsz.x) < SPILL_GATE


# Normalised arc-length (0..1) of p's nearest point on the path BL → TL → TR → BR (the
# left, top and right edges). 0 at bottom-left, 1 at bottom-right.
func _path_s(p: Vector2, rsz: Vector2) -> float:
	var total := 2.0 * rsz.y + rsz.x
	if total < 1.0:
		return 0.0
	var legs := [
		[Vector2(0.0, rsz.y), Vector2(0.0, 0.0), rsz.y],     # BL → TL
		[Vector2(0.0, 0.0), Vector2(rsz.x, 0.0), rsz.x],     # TL → TR
		[Vector2(rsz.x, 0.0), Vector2(rsz.x, rsz.y), rsz.y], # TR → BR
	]
	var best_d := INF
	var best_arc := 0.0
	var cum := 0.0
	for leg in legs:
		var a: Vector2 = leg[0]
		var b: Vector2 = leg[1]
		var leg_len: float = leg[2]
		var ab := b - a
		var l2 := ab.length_squared()
		var tt := clampf((p - a).dot(ab) / l2, 0.0, 1.0) if l2 > 0.0 else 0.0
		var cp := a + ab * tt
		var d := p.distance_squared_to(cp)
		if d < best_d:
			best_d = d
			best_arc = cum + tt * leg_len
		cum += leg_len
	return best_arc / total


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
