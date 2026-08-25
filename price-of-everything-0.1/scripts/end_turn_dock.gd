extends Control
## End Turn Dock — the bottom-right turn control.
##
## A single industrial navy-steel plate in the bottom-right corner. The emissive
## END TURN button is inset 40px from the plate's top + left and the screen's
## bottom edge, with the phase roller to its right sharing the button's centre-line. The
## per-turn financial breakdown that used to live here (the "Turn Summary" plate
## and its slide-up ledger) now lives in the top bar's Treasury mini-panel, so
## this dock is purely the end-turn control.
##
## Drawn in the game's industrial language: a brushed-silver base, a beveled
## navy plate with a gold rim + rivet, and an emissive gold END TURN face.
##
## UI is read-only against the sim (CLAUDE.md rule #5): it observes
## TurnManager.phase_started and only reads state.

# ── Fonts (reuse the project's loaded faces) ─────────────────────────────────
const F_HEAD := preload("res://assets/fonts/BebasNeue-Regular.ttf")   # END TURN

# ── Palette (mirrors the imported design; aligned with DS where they overlap) ─
const ACCENT := Color("#e6b34a")          # gold
# Diagonal navy gradient — light at the top-left, dark at the bottom-right.
const NAVY_TL := Color(0.025, 0.18, 0.34)
const NAVY_TR := Color(0.0, 0.12156863, 0.24313726)
const NAVY_BL := Color(0.0, 0.105, 0.215)
const NAVY_BR := Color(0.0, 0.067, 0.145)
# Brighter navy for the END TURN button (heavy top-left light, research-tech style).
const ETN_TL := Color(0.07, 0.30, 0.50)
const ETN_TR := Color(0.0, 0.14, 0.27)
const ETN_BL := Color(0.0, 0.11, 0.22)
const ETN_BR := Color(0.0, 0.045, 0.10)
const RIM := Color("#f4e6c0")              # cream metallic rim

# Silver under-plate (the squarish layer beneath the navy plate).
const SILVER_LT := Color("#b3bcc6")
const SILVER_MD := Color("#8b95a1")
const SILVER_DK := Color("#5b636e")

# ── Geometry (local px; computed rects derive from these in _update_layout) ───
const PLATE_W := 290.0    # visible width of the navy plate (grows off the right edge)
const BTN_W := 150.0
const BTN_H := 56.0
const ROLLER_W := 96.0    # phase roller width (sits to the right of the button)
const ROLLER_H := 30.0    # phase roller height
const ROW_GAP := 12.0     # gap between the button and the roller
## Inset from the metal rim, and from the screen bottom, all at once (owner 2026-08-25:
## 10px, was 40). The dock was carrying a third of its own height in padding; the plate is
## chrome around a button, not a room for it. PLATE_W came down with it so the rim sits the
## same 10px to the right of the roller.
const PAD := 10.0         # button inset from the plate top + left and the screen bottom
const RIVET_EDGE := 5.0   # rivet centre inset from a plate edge
const BASE_BLEED := 20.0  # base bottom/right edges extend this far off-screen
const BASE_RADIUS := 14.0 # squarish-rounded corner radius on the silver under-plate
const BASE_INSET := 6.0   # navy plate inset inside the silver plate

# ── State ────────────────────────────────────────────────────────────────────
var _menu: Control
var _roller: PhaseRoller
var _base_block: Control

# Cached layout rects (local space).
var _r_button := Rect2()
var _r_base := Rect2()

# Interactive child controls (created in code / the scene; the dock draws faces).
@onready var _end_turn_button: Button = %EndTurnButton
@onready var _phase_label: Label = %PhaseLabel

var _btn_hover := false
var _btn_down := false
var _last_disabled := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_end_turn_button()
	_build_interactive_children()

	# Phase roller (replaces the plain caption) — a navy-on-offwhite cylinder that
	# rolls when the turn phase changes.
	_roller = PhaseRoller.new()
	_roller.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_roller)
	TurnManager.phase_started.connect(_on_phase_started)
	_roller.set_phase(TurnManager.get_phase_name(TurnManager.current_phase), false)

	resized.connect(_update_layout)

	# Track the bottom menu so the navy base never overlaps it.
	_menu = get_node_or_null("%BottomMenu")
	if _menu != null and _menu.has_signal("sort_children"):
		_menu.sort_children.connect(_update_layout)

	# The old %PhaseLabel is replaced by the roller; keep it hidden for world_map.
	_phase_label.visible = false

	# Keep the End Turn button above the base blocker so it stays clickable.
	move_child(_end_turn_button, get_child_count() - 1)

	_update_layout()


func _on_phase_started(phase: int) -> void:
	_roller.set_phase(TurnManager.get_phase_name(phase), true)


# ─── Setup ───────────────────────────────────────────────────────────────────
func _style_end_turn_button() -> void:
	# The dock paints the button face; the real Button stays transparent and only
	# catches input + disabled state. World map keeps wiring it via %EndTurnButton.
	_end_turn_button.text = ""
	_end_turn_button.flat = true
	_end_turn_button.focus_mode = Control.FOCUS_NONE
	var empty := StyleBoxEmpty.new()
	for s in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		_end_turn_button.add_theme_stylebox_override(s, empty)
	_end_turn_button.mouse_entered.connect(func() -> void: _btn_hover = true; queue_redraw())
	_end_turn_button.mouse_exited.connect(func() -> void: _btn_hover = false; queue_redraw())
	_end_turn_button.button_down.connect(func() -> void: _btn_down = true; queue_redraw())
	_end_turn_button.button_up.connect(func() -> void: _btn_down = false; queue_redraw())


func _build_interactive_children() -> void:
	# Base blocker: absorbs map clicks over the whole navy plate. At a low relative
	# z so the End Turn button stays clickable above it.
	_base_block = Control.new()
	_base_block.mouse_filter = Control.MOUSE_FILTER_STOP
	_base_block.z_index = -1
	add_child(_base_block)


# ─── Layout ──────────────────────────────────────────────────────────────────
func _update_layout() -> void:
	var w := size.x
	var h := size.y

	# Navy plate anchored bottom-right, bleeding off the bottom + right edges and
	# never overlapping the bottom menu.
	var base_left := w - PLATE_W
	base_left = maxf(base_left, _menu_right_local() + 12.0)
	var navy_left := base_left + BASE_INSET

	# The END TURN button is inset PAD from the plate's top + left and from the
	# screen's bottom edge; the phase roller sits to its right on the same centre-line.
	var button_bottom := h - PAD
	var button_top := button_bottom - BTN_H
	var navy_top := button_top - PAD
	_r_base = Rect2(base_left, navy_top, (w + BASE_BLEED) - base_left, (h + BASE_BLEED) - navy_top)

	_r_button = Rect2(navy_left + PAD, button_top, BTN_W, BTN_H)
	_end_turn_button.position = _r_button.position
	_end_turn_button.size = _r_button.size

	_roller.position = Vector2(_r_button.end.x + ROW_GAP, _r_button.get_center().y - ROLLER_H * 0.5)
	_roller.size = Vector2(ROLLER_W, ROLLER_H)

	# Base blocker covers the visible navy panel — absorbs map clicks behind it.
	_base_block.position = _r_base.position
	_base_block.size = Vector2(minf(_r_base.size.x, w - _r_base.position.x), h - _r_base.position.y)

	queue_redraw()


func _menu_right_local() -> float:
	# Right edge of the bottom menu's visible buttons, in this control's space.
	if _menu == null:
		_menu = get_node_or_null("%BottomMenu")
	if _menu == null:
		return size.x * 0.5
	var max_r := -INF
	for c in _menu.get_children():
		if c is Control and (c as Control).visible:
			max_r = maxf(max_r, (c as Control).global_position.x + (c as Control).size.x)
	if max_r == -INF:
		max_r = _menu.global_position.x + _menu.size.x
	return max_r - global_position.x


func _process(_dt: float) -> void:
	# World map toggles end_turn_button.disabled during resolution; reflect it.
	if _end_turn_button.disabled != _last_disabled:
		_last_disabled = _end_turn_button.disabled
		queue_redraw()


# ─── Drawing ─────────────────────────────────────────────────────────────────
func _draw() -> void:
	_draw_base(_r_base)
	_draw_end_turn(_r_button)


func _draw_base(r: Rect2) -> void:
	# Two metal layers: a squarish SILVER plate underneath and a NAVY plate on top
	# (inset), so the silver reads as a frame. Each layer is a single polygon with
	# one gradient, so it shades consistently.
	# Bottom layer — silver.
	var sp := _plate_points(r, BASE_RADIUS)
	draw_polygon(sp, _octa_colors(sp, r, SILVER_LT, SILVER_MD, SILVER_DK, SILVER_MD))
	var so := sp.duplicate()
	so.append(sp[0])
	draw_polyline(so, Color("#3a4048"), 1.5, true)
	# Top layer — navy, inset.
	var nr := r.grow(-BASE_INSET)
	var np := _plate_points(nr, BASE_RADIUS - BASE_INSET)
	draw_polygon(np, _octa_colors(np, nr, NAVY_TL, NAVY_TR, NAVY_BR, NAVY_BL))
	draw_polygon(np, _octa_colors(np, nr, Color(1, 1, 1, 0.10), Color(1, 1, 1, 0.03), Color(0, 0, 0, 0.0), Color(1, 1, 1, 0.02)))
	var no := np.duplicate()
	no.append(np[0])
	draw_polyline(no, Color(RIM, 0.6), 1.5, true)
	# Bevel highlight along the visible top edge.
	var d := Vector2(0.0, 1.5)
	draw_line(np[4] + d, np[5] + d, Color(1, 1, 1, 0.16), 1.5)
	# Rivet on the silver frame's visible top-left corner.
	_rivet(Vector2(r.position.x + RIVET_EDGE + 3.0, r.position.y + RIVET_EDGE + 3.0), 3.5)


# Plate outline: rounded top-left corner, straight top edge, then the off-screen
# right + bottom edges (they bleed past the viewport).
func _plate_points(r: Rect2, radius: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var rr := minf(radius, minf(r.size.x, r.size.y) * 0.5)
	var cen := Vector2(r.position.x + rr, r.position.y + rr)
	for i in 5:
		var a := lerpf(PI, PI * 1.5, float(i) / 4.0)
		pts.append(cen + Vector2(cos(a), sin(a)) * rr)
	pts.append(Vector2(r.end.x, r.position.y))     # [5] top-right (off-screen R)
	pts.append(Vector2(r.end.x, r.end.y))          # [6] bottom-right (off-screen)
	pts.append(Vector2(r.position.x, r.end.y))     # [7] bottom-left (off-screen)
	return pts


func _draw_end_turn(r: Rect2) -> void:
	# Octagonal navy container in the research-panel tech style: heavy diagonal
	# lighting, metallic sheen, machined bevel, cream rim.
	var disabled := _end_turn_button.disabled
	var cut := 9.0
	var pts := _octagon_points(r, cut)

	# Drop shadow under the octagon.
	var shadow := _octagon_points(Rect2(r.position + Vector2(2, 3), r.size), cut)
	draw_polygon(shadow, _solid(shadow.size(), Color(0, 0, 0, 0.30)))

	# Navy fill with heavy top-left light.
	draw_polygon(pts, _octa_colors(pts, r, ETN_TL, ETN_TR, ETN_BR, ETN_BL))
	# Metallic sheen — faint white wash, brightest top-left.
	draw_polygon(pts, _octa_colors(pts, r, Color(1, 1, 1, 0.16), Color(1, 1, 1, 0.04), Color(0, 0, 0, 0.0), Color(1, 1, 1, 0.02)))

	# Machined bevel along the octagon edges (light top/left, dark bottom/right).
	var ip := _octagon_points(r.grow(-2.5), cut)
	draw_line(ip[0], ip[1], Color(1, 1, 1, 0.22), 1.5)   # top
	draw_line(ip[7], ip[0], Color(1, 1, 1, 0.18), 1.5)   # top-left cut
	draw_line(ip[6], ip[7], Color(1, 1, 1, 0.16), 1.5)   # left
	draw_line(ip[2], ip[3], Color(0, 0, 0, 0.32), 1.5)   # right
	draw_line(ip[3], ip[4], Color(0, 0, 0, 0.30), 1.5)   # bottom-right cut
	draw_line(ip[4], ip[5], Color(0, 0, 0, 0.34), 1.5)   # bottom

	# Cream rim outline.
	var outline := pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, Color(RIM, 0.85), 1.5, true)

	# Hover/press accent glow ring.
	if not disabled and (_btn_hover or _btn_down):
		var go := pts.duplicate()
		go.append(pts[0])
		draw_polyline(go, Color(ACCENT, 0.30 if _btn_down else 0.20), 2.5, true)

	# Label — gold, with shadow + top highlight (research title treatment).
	var col := ACCENT if not disabled else Color(ACCENT, 0.4)
	var tw := _measure(F_HEAD, "END TURN", 18)
	var tx := r.position.x + (r.size.x - tw) * 0.5
	var ty := r.position.y + (r.size.y - 18.0) * 0.5
	_text(F_HEAD, Vector2(tx + 1, ty + 1), "END TURN", 18, Color(0, 0, 0, 0.5))
	if not disabled:
		_text(F_HEAD, Vector2(tx, ty), "END TURN", 18, Color(ACCENT, 0.25))  # bloom
	_text(F_HEAD, Vector2(tx, ty), "END TURN", 18, col)


# ─── Draw helpers ────────────────────────────────────────────────────────────
func _octagon_points(r: Rect2, cut: float) -> PackedVector2Array:
	var x0 := r.position.x
	var y0 := r.position.y
	var x1 := r.end.x
	var y1 := r.end.y
	return PackedVector2Array([
		Vector2(x0 + cut, y0), Vector2(x1 - cut, y0),
		Vector2(x1, y0 + cut), Vector2(x1, y1 - cut),
		Vector2(x1 - cut, y1), Vector2(x0 + cut, y1),
		Vector2(x0, y1 - cut), Vector2(x0, y0 + cut),
	])


func _octa_colors(pts: PackedVector2Array, r: Rect2, tl: Color, tr: Color, br: Color, bl: Color) -> PackedColorArray:
	var cols := PackedColorArray()
	for p in pts:
		var u := (p.x - r.position.x) / maxf(1.0, r.size.x)
		var v := (p.y - r.position.y) / maxf(1.0, r.size.y)
		cols.append(tl.lerp(tr, u).lerp(bl.lerp(br, u), v))
	return cols


func _solid(n: int, col: Color) -> PackedColorArray:
	var cols := PackedColorArray()
	for _i in n:
		cols.append(col)
	return cols


func _rivet(c: Vector2, rad: float) -> void:
	draw_circle(c, rad, Color("#5a636e"))
	draw_circle(c - Vector2(rad * 0.3, rad * 0.3), rad * 0.55, Color("#c9d4df"))
	draw_arc(c, rad, 0, TAU, 16, Color(0, 0, 0, 0.5), 1.0)


func _text(font: Font, top_left: Vector2, s: String, fs: int, col: Color, width := -1.0) -> void:
	# width > 0 clips the line (and ellipsizes) so it can't run under the frame.
	draw_string(font, Vector2(top_left.x, top_left.y + font.get_ascent(fs)), s,
		HORIZONTAL_ALIGNMENT_LEFT, width, fs, col, TextServer.JUSTIFICATION_NONE,
		TextServer.DIRECTION_AUTO, TextServer.ORIENTATION_HORIZONTAL)


func _measure(font: Font, s: String, fs: int) -> float:
	return font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x


# ─── Phase roller ────────────────────────────────────────────────────────────
# An offwhite cylinder showing the current phase in navy. When the phase changes
# the name rolls over (0.1s): the old name slides up and out, the new one rolls
# in from below. clip_contents keeps the rolling text inside the cylinder.
class PhaseRoller extends Control:
	const _FONT: Font = preload("res://assets/fonts/IBMPlexSans-SemiBold.ttf")
	const _FS := 13
	const _ROLL := 0.1                          # transition duration (s)
	const _NAVY := Color(0.02, 0.10, 0.20)      # navy ink
	# Cylinder shading: apex (brightest) at the middle line, top lighter than the
	# evenly-darker bottom.
	const _TOP := Color(0.86, 0.86, 0.81)
	const _MID := Color(0.99, 0.99, 0.95)
	const _BOT := Color(0.60, 0.60, 0.55)

	var _cur := ""
	var _prev := ""
	var _t := 1.0                                # 1 = settled

	func _ready() -> void:
		clip_contents = true

	func set_phase(text: String, animate: bool) -> void:
		if text == _cur:
			return
		_prev = _cur
		_cur = text
		_t = 0.0 if animate else 1.0
		queue_redraw()

	func _process(delta: float) -> void:
		if _t < 1.0:
			_t = minf(1.0, _t + delta / _ROLL)
			queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		# Cylinder body — flat-sided, vertical gradient (apex brightest at middle).
		for i in int(h):
			var f := float(i) / maxf(1.0, h - 1.0)
			var col := _TOP.lerp(_MID, f / 0.5) if f < 0.5 else _MID.lerp(_BOT, (f - 0.5) / 0.5)
			draw_line(Vector2(0, i), Vector2(w, i), col, 1.0)
		# Rolling text (navy).
		var ease := 1.0 - pow(1.0 - _t, 3.0)        # ease-out
		_blit(_cur, (1.0 - ease) * h)               # new rolls up from below
		if _t < 1.0:
			_blit(_prev, -ease * h)                  # old slides up and out
		# Flat rim.
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.42, 0.42, 0.39, 0.7), false, 1.0)

	func _blit(text: String, dy: float) -> void:
		if text == "":
			return
		var tw := _FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, _FS).x
		var x := (size.x - tw) * 0.5
		var y := (size.y - _FS) * 0.5 + _FONT.get_ascent(_FS) + dy
		draw_string(_FONT, Vector2(x, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, _FS, _NAVY)
