extends Control
## Loading-screen hex intro (reuses the empire-view hex aesthetic). A navy field
## tiled with a regular flat-top hex lattice whose lines rest light grey and light to
## gold. The sequence, driven by `_t` (seconds since shown):
##   0–10 s   the grey lattice DRAWS IN — a soft diagonal wipe from top-left to
##            bottom-right, so the field is empty navy at first and fully drawn by 10 s.
##   10 s on  a GOLD wavefront sweeps the lattice: a very wavy (sine-modulated) band
##            travelling a corner path bottom-right → top-left → top-right → bottom-right,
##            looping every SWEEP_SECS until the load finishes.
##
## Per the empire-view bg, each hex edge is subdivided to ~SEG_LEN and every sample is
## coloured individually, so the gold reads as a moving band along the geometry, not a
## per-hex flat fill. Animates in `_process`; if the main thread blocks during the heavy
## world build the clock simply pauses and resumes (the timed-yield fix is a later step).

const SQRT3 := 1.7320508
const HEX_HW := 92.0             # cell half-width (regular hex: half-height = HW * 2/sqrt3)
const ROW_GAP_FRAC := 0.20       # gap between offset rows, as a fraction of cell height
const LINE_W := 1.5
const SEG_LEN := 18.0            # px between coloured samples along each edge

const NAVY := Color(0.015, 0.058, 0.105, 1.0)
const GREY := Color(0.62, 0.64, 0.67, 0.40)   # resting line colour
const GOLD := Color(0.93, 0.69, 0.33, 0.95)   # lit wavefront

const DRAW_IN_SECS := 10.0       # grey lattice wipes in over this
const DRAW_IN_EDGE := 0.18       # softness of the wipe front (fraction of the diagonal)
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
			_draw_hex(center, hw, ht, sh, rsz)


func _draw_hex(center: Vector2, hw: float, ht: float, sh: float, rsz: Vector2) -> void:
	var verts := PackedVector2Array([
		center + Vector2(0.0, -ht), center + Vector2(hw, -sh), center + Vector2(hw, sh),
		center + Vector2(0.0, ht), center + Vector2(-hw, sh), center + Vector2(-hw, -sh),
		center + Vector2(0.0, -ht),
	])
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	for i in range(6):
		var a: Vector2 = verts[i]
		var b: Vector2 = verts[i + 1]
		var segs := maxi(1, int(a.distance_to(b) / SEG_LEN))
		for s in range(segs):
			var p := a.lerp(b, float(s) / float(segs))
			pts.append(p)
			cols.append(_color_at(p, rsz))
	pts.append(verts[6])
	cols.append(_color_at(verts[6], rsz))
	draw_polyline_colors(pts, cols, LINE_W, true)


func _color_at(p: Vector2, rsz: Vector2) -> Color:
	# Draw-in: a soft diagonal wipe (top-left → bottom-right) over DRAW_IN_SECS.
	var diag := (p.x / rsz.x + p.y / rsz.y) * 0.5     # 0 at top-left, 1 at bottom-right
	var wipe := clampf(_t / DRAW_IN_SECS, 0.0, 1.0)
	var appear := smoothstep(diag - DRAW_IN_EDGE, diag, wipe)
	if appear <= 0.001:
		return Color(GREY.r, GREY.g, GREY.b, 0.0)
	var col := Color(GREY.r, GREY.g, GREY.b, GREY.a * appear)
	if _t > DRAW_IN_SECS:
		var g := _gold_at(p, rsz)
		col = col.lerp(Color(GOLD.r, GOLD.g, GOLD.b, GOLD.a * appear), g)
	return col


# Gold wavefront brightness at p (0..1): a wavy gaussian band travelling the corner
# path BR → TL → TR → BR, looping. The band is displaced by a sine of the coordinate
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
