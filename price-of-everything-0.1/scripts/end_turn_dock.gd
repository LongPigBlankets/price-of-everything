extends Control
## End Turn Dock — the bottom-right turn control.
##
## The end of the DS2 control desk in the bottom-right corner, with the phase roller to the button's right
## sharing its centre-line. The per-turn financial breakdown lives in the top bar's Treasury mini-panel, so
## this dock is purely the end-turn control.
##
## The plate is the desk plate's left end (desk_plate.png, the same navy steel and screw as the bottom bar's),
## the button a stylised silver push button drawn here: a flat face, four shaded bevel facets, the shadow it
## casts into its black frame and an arrow pointing right. END TURN is engraved under it, and the phase is on
## the roller in a black frame beside it, a gear on each end of the roller seen edge on, its teeth turning with
## the roller as the phase rolls over.
##
## UI is read-only against the sim (CLAUDE.md rule #5): it observes
## TurnManager.phase_started and only reads state.

# ── Geometry (local px; computed rects derive from these in _update_layout) ───
const ROLLER_W := 96.0    # phase roller width (sits to the right of the button)
const ROLLER_H := 30.0    # phase roller height
const ROW_GAP := 12.0     # gap between the button and the roller
const PAD := 10.0         # inset round the button and roller on the plate
const BASE_BLEED := 20.0  # base bottom/right edges extend this far off-screen

# ── The desk ─────────────────────────────────────────────────────────────────
const DESK_PLATE: Texture2D = preload("res://assets/ui/bdp_v3/desk_plate.png")
const F_ENGRAVE: Font = preload("res://assets/fonts/BarlowCondensed-SemiBold.ttf")
## The button's black frame in px, the label's height under it, the desk's foot under the label and the plate's
## height over it all.
const DESK_BTN := Vector2(74.0, 36.0)
const DESK_LABEL := 15.0
const DESK_FOOT := 5.0
const DESK_PLATE_TOP := 68.0
## The button: the frame's rim, the bevel's width at rest and held, and its colours, lit from the upper left.
const BTN_RIM := 4.0
const BEVEL := 6.0
const BEVEL_HELD := 4.0
const FRAME_BLACK := Color("#121316")
const WELL_BLACK := Color("#050608")
const FACET_TOP := Color("#eef1f5")
const FACET_LEFT := Color("#cfd5dc")
const FACET_RIGHT := Color("#7c848e")
const FACET_BOTTOM := Color("#5f6670")
const FACE_TOP := Color("#cdd3da")
const FACE_BOTTOM := Color("#b0b7c0")
const ARROW_INK := Color("#22262d")
## A resolving turn dims the button to this.
const DIMMED := Color(0.6, 0.6, 0.62)
## The roller's gears, one on each end, seen edge on: the rim's thickness, how far it stands above and below the
## roller, its gap from the roller's frame, its teeth all round, and the teeth it turns as the phase rolls over.
const GEAR_W := 10.0
const GEAR_OVER := 5.0
const GEAR_GAP := 2.0
const GEAR_TEETH := 26
const TEETH_PER_PHASE := 3
const GEAR_STEEL := Color("#b9c1cb")
const GEAR_GROOVE := Color("#4a525c")

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
## Phase changes so far: the gears stand this many steps round, less the step the roller is still rolling.
var _gear_steps := 0


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
	_gear_steps += 1


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


# ─── Note ────────────────────────────────────────────────────────────────────
## How long a note above the button stays, and how long it takes to fade.
const NOTE_SEC := 2.6
const NOTE_FADE_SEC := 0.3
var _note: PanelContainer


## A small note just above the End Turn button, saying why a press did nothing. It fades by itself.
func show_note(text: String) -> void:
	if _note != null and is_instance_valid(_note):
		_note.queue_free()
	_note = PanelContainer.new()
	_note.name = "EndTurnNote"
	_note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	box.bg_color = Color(DS.PALETTE.BG_PANEL, 0.96)
	box.border_color = DS.PALETTE.ACCENT
	box.set_border_width_all(1)
	box.set_corner_radius_all(6)
	box.content_margin_left = 12.0
	box.content_margin_right = 12.0
	box.content_margin_top = 7.0
	box.content_margin_bottom = 7.0
	_note.add_theme_stylebox_override("panel", box)
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", DS.PALETTE.TEXT)
	label.add_theme_font_size_override("font_size", 14)
	_note.add_child(label)
	add_child(_note)
	var ns := _note.get_combined_minimum_size()
	var r := Rect2(_end_turn_button.position, _end_turn_button.size)
	_note.position = Vector2(clampf(r.get_center().x - ns.x * 0.5, 8.0, maxf(8.0, size.x - ns.x - 8.0)), r.position.y - ns.y - 48.0)
	var note := _note
	var fade := create_tween()
	fade.tween_interval(NOTE_SEC)
	fade.tween_property(note, "modulate:a", 0.0, NOTE_FADE_SEC)
	fade.tween_callback(note.queue_free)


# ─── Layout ──────────────────────────────────────────────────────────────────
## The button over its engraved label on the desk's foot, the roller beside the button, the plate over them all
## from DESK_PLATE_TOP, bleeding off the bottom and right.
func _update_layout() -> void:
	var w := size.x
	var h := size.y
	var gear := 3.0 + GEAR_GAP + GEAR_W
	var left := maxf(w - (PAD * 2.0 + DESK_BTN.x + ROW_GAP + gear * 2.0 + ROLLER_W + 18.0), _menu_right_local() + 12.0)
	_r_base = Rect2(left, h - DESK_PLATE_TOP, (w + BASE_BLEED) - left, DESK_PLATE_TOP + BASE_BLEED)
	_r_button = Rect2(left + PAD + 6.0, h - DESK_FOOT - DESK_LABEL - DESK_BTN.y, DESK_BTN.x, DESK_BTN.y)
	_end_turn_button.position = _r_button.position
	_end_turn_button.size = _r_button.size
	_roller.position = Vector2(_r_button.end.x + ROW_GAP + gear, _r_button.get_center().y - ROLLER_H * 0.5)
	_roller.size = Vector2(ROLLER_W, ROLLER_H)
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
	if _roller.rolling():
		queue_redraw()


# ─── Drawing ─────────────────────────────────────────────────────────────────
## The desk plate's left end over the dock, the button (at rest, sunk while held, dimmed while a turn
## resolves), the roller's gearing and frame, and END TURN engraved under the button.
func _draw() -> void:
	var plate := DESK_PLATE.get_size()
	var shown := Vector2(minf(_r_base.size.x, plate.x / 2.0), plate.y / 2.0)
	draw_texture_rect_region(DESK_PLATE, Rect2(_r_base.position, shown), Rect2(Vector2.ZERO, shown * 2.0))
	if _r_base.size.x > shown.x:
		# Past the plate's render, the plate runs on off the screen: its middle, without the far end's screw.
		var rest := Rect2(_r_base.position + Vector2(shown.x, 0.0), Vector2(_r_base.size.x - shown.x, shown.y))
		draw_texture_rect_region(DESK_PLATE, rest, Rect2(Vector2(plate.x * 0.5, 0.0), Vector2(rest.size.x * 2.0, plate.y)))
	_draw_desk_button(_r_button, _end_turn_button.disabled, _btn_down, _btn_hover)
	_draw_gearing()
	# The roller's black frame.
	draw_rect(Rect2(_roller.position, _roller.size).grow(3.0), Color("#121316"))
	# END TURN engraved under the button: off-white capitals over a dark cut shadow.
	var tw := F_ENGRAVE.get_string_size("END TURN", HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	var at := Vector2(_r_button.get_center().x - tw * 0.5, _r_button.end.y + 13.0)
	draw_string(F_ENGRAVE, at + Vector2(1, 1), "END TURN", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0, 0, 0, 0.85))
	draw_string(F_ENGRAVE, at, "END TURN", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, DS.PALETTE.TEXT)


## The stylised silver button in its black frame: the frame and its well, the shadow the button casts into the
## well, four bevel facets lit from the upper left round a flat face, and the arrow, its edge catching the light.
func _draw_desk_button(r: Rect2, dimmed: bool, held: bool, hover: bool) -> void:
	var dim := DIMMED if dimmed else Color.WHITE
	var frame := StyleBoxFlat.new()
	frame.bg_color = FRAME_BLACK
	frame.set_corner_radius_all(6)
	frame.shadow_color = Color(0, 0, 0, 0.45)
	frame.shadow_size = 3
	frame.shadow_offset = Vector2(1.5, 2.5)
	draw_style_box(frame, r)
	var well := r.grow(-BTN_RIM)
	draw_rect(well, WELL_BLACK)
	var body := well.grow(-1.0)
	if held:
		body.position += Vector2(0.5, 1.0)
	else:
		draw_rect(Rect2(body.position + Vector2(2.0, 2.0), body.size).intersection(well), Color(0, 0, 0, 0.7))
	var bev := BEVEL_HELD if held else BEVEL
	var face := body.grow(-bev)
	var o := [body.position, Vector2(body.end.x, body.position.y), body.end, Vector2(body.position.x, body.end.y)]
	var f := [face.position, Vector2(face.end.x, face.position.y), face.end, Vector2(face.position.x, face.end.y)]
	var lift := 0.88 if held else 1.0
	draw_colored_polygon(PackedVector2Array([o[0], o[1], f[1], f[0]]), FACET_TOP * dim * Color(lift, lift, lift))
	draw_colored_polygon(PackedVector2Array([o[0], f[0], f[3], o[3]]), FACET_LEFT * dim * Color(lift, lift, lift))
	draw_colored_polygon(PackedVector2Array([o[1], o[2], f[2], f[1]]), FACET_RIGHT * dim)
	draw_colored_polygon(PackedVector2Array([o[3], f[3], f[2], o[2]]), FACET_BOTTOM * dim)
	var glow := 1.06 if hover and not held and not dimmed else (0.94 if held else 1.0)
	var top := FACE_TOP * dim * Color(glow, glow, glow)
	var bottom := FACE_BOTTOM * dim * Color(glow, glow, glow)
	draw_polygon(PackedVector2Array(f), PackedColorArray([top, top, bottom, bottom]))
	draw_polyline(PackedVector2Array(f + [f[0]]), Color(0, 0, 0, 0.18), 1.0)
	# The arrow, pointing right: a shaft and a head, its lower edge lit as if pressed into the face.
	var c := face.get_center()
	var aw := face.size.y * 1.15
	var ah := face.size.y * 0.78
	var shaft := ah * 0.4
	var head := aw * 0.45
	var arrow := PackedVector2Array([
		c + Vector2(-aw * 0.5, -shaft * 0.5), c + Vector2(aw * 0.5 - head, -shaft * 0.5), c + Vector2(aw * 0.5 - head, -ah * 0.5),
		c + Vector2(aw * 0.5, 0.0), c + Vector2(aw * 0.5 - head, ah * 0.5), c + Vector2(aw * 0.5 - head, shaft * 0.5),
		c + Vector2(-aw * 0.5, shaft * 0.5)])
	var lit := PackedVector2Array()
	for pt in arrow:
		lit.append(pt + Vector2(0.0, 1.0))
	draw_colored_polygon(lit, Color(1, 1, 1, 0.45 if not dimmed else 0.2))
	draw_colored_polygon(arrow, Color(ARROW_INK, 0.55 if dimmed else 1.0))


## A gear on each end of the roller, seen edge on beside its frame.
func _draw_gearing() -> void:
	var frame := Rect2(_roller.position, _roller.size).grow(3.0)
	var turn := -(float(_gear_steps - 1) + _roller.progress()) * TAU / GEAR_TEETH * TEETH_PER_PHASE
	for x: float in [frame.position.x - GEAR_GAP - GEAR_W, frame.end.x + GEAR_GAP]:
		_draw_gear_edge(Rect2(x, frame.get_center().y - frame.size.y * 0.5 - GEAR_OVER, GEAR_W, frame.size.y + GEAR_OVER * 2.0), turn)


## A steel gear seen edge on, its axle across the view, turned to `turn`: its shadow on the desk, the dark
## grooves between its teeth, and the teeth on the near half as bands foreshortened toward its top and foot,
## shaded by how squarely each faces the viewer and lit from above.
func _draw_gear_edge(r: Rect2, turn: float) -> void:
	var c := r.get_center().y
	var radius := r.size.y * 0.5
	draw_rect(Rect2(r.position + Vector2(1.5, 2.0), r.size), Color(0, 0, 0, 0.45))
	# The body under the teeth: the grooves' steel, shaded as a cylinder turning away at its top and foot.
	var bands := 24
	for b in bands:
		var a0 := -PI * 0.5 + PI * b / bands
		var a1 := a0 + PI / bands
		var shade := clampf(0.3 + 0.7 * cos((a0 + a1) * 0.5) - 0.15 * sin((a0 + a1) * 0.5), 0.12, 1.0)
		draw_rect(Rect2(r.position.x + 1.0, c + radius * sin(a0), r.size.x - 2.0, radius * (sin(a1) - sin(a0)) + 0.5), Color(GEAR_GROOVE * shade, 1.0))
	# The teeth: full width, standing proud of the grooves, foreshortened and shaded the same way.
	var w := TAU / GEAR_TEETH
	for i in GEAR_TEETH:
		var a := wrapf(turn + i * w, -PI, PI)
		var a0 := maxf(a - 0.26 * w, -PI * 0.5)
		var a1 := minf(a + 0.26 * w, PI * 0.5)
		if a1 <= a0:
			continue
		var y0 := c + radius * sin(a0)
		var y1 := c + radius * sin(a1)
		var lit := clampf(0.25 + 0.8 * cos(a) - 0.2 * sin(a), 0.12, 1.08)
		draw_rect(Rect2(r.position.x, y0, r.size.x, maxf(y1 - y0, 0.5)), Color(GEAR_STEEL * lit, 1.0))
		# Each tooth's upper edge catches the light.
		if a < 0.2 and y1 - y0 > 1.2:
			draw_line(Vector2(r.position.x, y0 + 0.5), Vector2(r.end.x, y0 + 0.5), Color(1, 1, 1, 0.3 * cos(a)), 1.0)
	# The rim's edges: lit down its left side, dark down its right.
	draw_line(Vector2(r.position.x + 0.5, r.position.y + 3.0), Vector2(r.position.x + 0.5, r.end.y - 3.0), Color(1, 1, 1, 0.18), 1.0)
	draw_line(Vector2(r.end.x - 0.5, r.position.y + 3.0), Vector2(r.end.x - 0.5, r.end.y - 3.0), Color(0, 0, 0, 0.4), 1.0)


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

	## How far the current roll has gone, eased (1 once it has settled).
	func progress() -> float:
		return 1.0 - pow(1.0 - _t, 3.0)

	func rolling() -> bool:
		return _t < 1.0

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
