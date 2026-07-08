extends Control
## End Turn Dock — the bottom-right turn cluster.
##
## A single industrial dock that unifies what used to be three separate nodes
## (the plain End Turn button, the phase caption, and the floating Turn Summary
## panel). Layout, top → bottom:
##   • An expandable LEDGER slideout that grows UP above the summary (2-column
##     financial mini-ledger + ops lines + dismiss row). Shown on turn-end.
##   • A compact SUMMARY plate (net cash + starved + built) with a chevron, and
##     the emissive END TURN button to its right, both sitting on a silver base.
##   • A "Phase: …" caption beneath the button.
##
## Faithful to the imported "End Turn Dock" design, drawn in the game's own
## industrial language: beveled navy-steel plates, gold pinstripe, rivets, a
## brushed-silver base, and an emissive gold END TURN face.
##
## UI is read-only against the sim (CLAUDE.md rule #5): it observes
## Production.turn_processed / MatchState.building_added and only reads state.

const RUNWAY_THRESHOLD_TURNS := 5
const AUTO_COLLAPSE_DELAY := 6.0

# ── Fonts (reuse the project's loaded faces) ─────────────────────────────────
const F_HEAD := preload("res://assets/fonts/BebasNeue-Regular.ttf")   # titles / END TURN
const F_BODY := preload("res://assets/fonts/IBMPlexSans-Regular.ttf")
const F_MED := preload("res://assets/fonts/IBMPlexSans-Medium.ttf")
const F_SEMI := preload("res://assets/fonts/IBMPlexSans-SemiBold.ttf") # numeric

# ── Shared art (the research reference panel's brass pipe frame, 9-sliced) ──
const BRASS_FRAME: Texture2D = preload("res://assets/ui/brass_pipe_frame_transparent.png")
const BRASS_SRC_SLICE := 168.0            # corner slice in the brass source texture

# ── Palette (mirrors the imported design; aligned with DS where they overlap) ─
const ACCENT := Color("#e6b34a")          # gold
# Diagonal navy gradient — light at the top-left, dark at the bottom-right
# (the research panel's lighting; reused on the expanded ledger).
const NAVY_TL := Color(0.025, 0.18, 0.34)
const NAVY_TR := Color(0.0, 0.12156863, 0.24313726)
const NAVY_BL := Color(0.0, 0.105, 0.215)
const NAVY_BR := Color(0.0, 0.067, 0.145)
# Brighter navy for the END TURN container (heavy top-left light, research-tech style).
const ETN_TL := Color(0.07, 0.30, 0.50)
const ETN_TR := Color(0.0, 0.14, 0.27)
const ETN_BL := Color(0.0, 0.11, 0.22)
const ETN_BR := Color(0.0, 0.045, 0.10)
const BRASS_LIT := Color("#f2d490")        # brass notch — lit (left)
const BRASS_DIM := Color("#9c7a32")        # brass notch — shadowed (right)
const RIM := Color("#f4e6c0")              # cream metallic rim
const C_TITLE := Color("#dce7f2")
const C_BODY := Color("#aebccd")
const C_MUTED := Color("#8298ac")
const C_DIVIDER := Color("#22384f")
const C_LOSS := Color("#e6917f")
const C_GAIN := Color("#7fc98a")
const C_ZERO := Color("#9fb0c4")
const C_NET_LOSS := Color("#f0584a")
const C_WARN := Color("#e6b34a")
const C_BUILT := Color("#5fbf6b")
const C_CAPTION := Color("#3a4048")        # phase caption sits on the light silver base

# ── Geometry (local px; computed rects derive from these in _update_layout) ───
const RP := 18.0          # right padding to screen edge
const SUMMARY_W := 300.0  # compact summary plate (fixed)
const SUMMARY_H := 66.0   # collapsed summary height (anchored to the brass pipe, grows down)
const SUMMARY_PAD := 20.0 # internal padding (text inset from the edges)
const BTN_W := 120.0
const BTN_H := 52.0
const GAP := 12.0
const RIVET_EDGE := 5.0   # rivet centre inset from a plate edge
const BASE_H := 130.0     # navy base panel height
const BASE_BLEED := 20.0  # base bottom/right edges extend this far off-screen
const BASE_RADIUS := 14.0 # squarish-rounded corner radius on the silver under-plate
const BASE_INSET := 6.0   # navy octagon inset inside the silver plate
const BASE_CUT := 14.0    # navy octagon corner cut
const TAB_RAISE := 22.0   # height the panel edge rises over the End Turn button
const TAB_CHAMFER := 18.0 # diagonal length of that raised-section transition
const SLIDE_PAD := 16.0   # ledger content inset (clears the pipe frame)
const SLIDE_SECS := 0.4   # expand / collapse slide duration

# Silver under-plate (the squarish layer beneath the navy octagon).
const SILVER_LT := Color("#b3bcc6")
const SILVER_MD := Color("#8b95a1")
const SILVER_DK := Color("#5b636e")

# ── State ────────────────────────────────────────────────────────────────────
var _expanded := false
var _suppress_expand := false
var _have_summary := false
var _collapse_timer: SceneTreeTimer = null
var _slide_t := 0.0           # 0 = collapsed, 1 = expanded (animated)
var _slide_target := 0.0
var _hud_sibling_index := -1  # our HUDContent child index, saved while raised to the front

var _net := 0.0
var _starved := 0
var _built := 0
var _fin: Array = []          # [{k, v}] ledger lines
var _produced_text := ""
var _power_out := 0.0
var _buildings_added: Array = []

# Cached layout rects (local space).
var _r_summary := Rect2()
var _r_button := Rect2()
var _r_slide := Rect2()
var _r_base := Rect2()

# Interactive child controls (created in code; the dock draws their faces).
@onready var _end_turn_button: Button = %EndTurnButton
@onready var _phase_label: Label = %PhaseLabel
var _menu: Control
var _roller: PhaseRoller
var _base_block: Control
var _header_hit: Button
var _slide_block: Control
var _suppress_chk: Button
var _go_btn: Button
var _summary_marker: Control   # invisible, findable Control over the collapsed TURN SUMMARY plate (tutorial coach target)

var _btn_hover := false
var _btn_down := false
var _last_disabled := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_end_turn_button()
	_build_interactive_children()

	# Phase roller (replaces the plain caption) — a navy-on-offwhite cylinder
	# that rolls when the turn phase changes.
	_roller = PhaseRoller.new()
	_roller.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_roller)
	TurnManager.phase_started.connect(_on_phase_started)
	_roller.set_phase(TurnManager.get_phase_name(TurnManager.current_phase), false)

	resized.connect(_update_layout)
	Production.turn_processed.connect(_on_turn_processed)
	MatchState.building_added.connect(_on_building_added)

	# Track the bottom menu so the navy base never overlaps it.
	_menu = get_node_or_null("%BottomMenu")
	if _menu != null and _menu.has_signal("sort_children"):
		_menu.sort_children.connect(_update_layout)

	# The old %PhaseLabel is replaced by the roller; keep it hidden for world_map.
	_phase_label.visible = false

	# Keep the End Turn button above the base blocker so it stays clickable.
	move_child(_end_turn_button, get_child_count() - 1)

	_render_empty()
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
	# Base blocker: absorbs map clicks over the whole navy panel. At a low relative
	# z so the interactive buttons (End Turn, header, checkbox) stay clickable.
	_base_block = Control.new()
	_base_block.mouse_filter = Control.MOUSE_FILTER_STOP
	_base_block.z_index = -1
	add_child(_base_block)

	# Block created next so the interactive buttons below sit ON TOP of it (else
	# it would swallow clicks meant for the header caret / checkbox).
	_slide_block = Control.new()                   # eats clicks over the open ledger
	_slide_block.mouse_filter = Control.MOUSE_FILTER_STOP
	_slide_block.visible = false
	add_child(_slide_block)

	_header_hit = _make_hit()                      # toggles the ledger (caret closes it)
	_header_hit.pressed.connect(_toggle)
	_header_hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	_suppress_chk = _make_hit()
	_suppress_chk.toggle_mode = true
	_suppress_chk.toggled.connect(func(on: bool) -> void: _suppress_expand = on; queue_redraw())
	_suppress_chk.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_suppress_chk.visible = false

	_go_btn = _make_hit()
	_go_btn.pressed.connect(_on_go_pressed)
	_go_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_go_btn.visible = false

	# Named, findable Control sized to the collapsed TURN SUMMARY plate — a spotlight/annotation
	# target for the tutorial coach. Draws nothing (no children) and ignores the mouse so it never
	# steals the header/chevron clicks beneath it. Kept in sync by _update_layout().
	_summary_marker = Control.new()
	_summary_marker.name = "TurnSummaryMarker"
	_summary_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_summary_marker)


func _make_hit() -> Button:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	var empty := StyleBoxEmpty.new()
	for s in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		b.add_theme_stylebox_override(s, empty)
	add_child(b)
	return b


# ─── Layout ──────────────────────────────────────────────────────────────────
func _update_layout() -> void:
	var w := size.x
	var h := size.y
	var rx := w - RP                                # cluster right edge (= button right)
	var navy_top := h - (BASE_H - BASE_BLEED)       # visible top of the navy panel

	# Cluster row sits at the TOP of the (shorter) navy panel. Roller below button.
	var row_top := navy_top + 2.0
	_r_button = Rect2(rx - BTN_W + 10.0, row_top + (SUMMARY_H - BTN_H) * 0.5 - 5.0, BTN_W, BTN_H)
	var sum_right := _r_button.position.x - GAP
	_r_summary = Rect2(sum_right - SUMMARY_W, row_top, SUMMARY_W, SUMMARY_H)
	if _summary_marker != null:
		_summary_marker.position = _r_summary.position
		_summary_marker.size = _r_summary.size

	# Navy base: shorter, squarish-rounded, bleeds off bottom + right; right of menu.
	var base_left := _r_summary.position.x - 24.0
	base_left = maxf(base_left, _menu_right_local() + 8.0)
	_r_base = Rect2(base_left, navy_top, (w + BASE_BLEED) - base_left, BASE_H)

	# Expanded ledger: same width as the summary, aligned with it, emerging from
	# the navy panel's top edge and growing up. It carries the summary content in
	# its top header.
	var slide_h := 348.0   # +2 rows for the split labour/maintenance/tax/fake-money ledger
	_r_slide = Rect2(_r_summary.position.x, navy_top - slide_h, SUMMARY_W, slide_h)

	# Input layers.
	_end_turn_button.position = _r_button.position
	_end_turn_button.size = _r_button.size
	# Phase roller below the button — 70% of the button width.
	var roller_w := BTN_W * 0.7
	_roller.position = Vector2(_r_button.get_center().x - roller_w * 0.5, _r_button.end.y + 2.0)
	_roller.size = Vector2(roller_w, 30.0)

	# Header hit: the summary plate when collapsed; the ledger's top header (which
	# now holds the summary content) when expanded — its caret closes the panel.
	if _expanded:
		_header_hit.position = Vector2(_r_slide.position.x, _r_slide.position.y + 10.0)
		_header_hit.size = Vector2(SUMMARY_W, SUMMARY_H)
	else:
		_header_hit.position = _r_summary.position
		_header_hit.size = _r_summary.size

	_slide_block.position = _r_slide.position
	_slide_block.size = _r_slide.size

	# Base blocker covers the whole navy panel (clamped to the visible viewport so
	# it doesn't reach left of the panel) — absorbs map clicks behind the dock.
	_base_block.position = _r_base.position
	_base_block.size = Vector2(minf(_r_base.size.x, w - _r_base.position.x), h - _r_base.position.y)

	# Ledger-only hit zones. Tickbox row sits at the bottom (short); the "Go →"
	# link on the starved line.
	var inner_x := _r_slide.position.x + SLIDE_PAD
	var inner_r := _r_slide.end.x - SLIDE_PAD
	_suppress_chk.position = Vector2(inner_x, _r_slide.end.y - 31.0)
	_suppress_chk.size = Vector2(inner_r - inner_x, 20.0)
	_go_btn.position = Vector2(inner_x + 66.0, _r_slide.end.y - 64.0)
	_go_btn.size = Vector2(44.0, 16.0)

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


func _process(dt: float) -> void:
	# World map toggles end_turn_button.disabled during resolution; reflect it.
	if _end_turn_button.disabled != _last_disabled:
		_last_disabled = _end_turn_button.disabled
		queue_redraw()
	# Expand / collapse slide.
	if _slide_t != _slide_target:
		var step := dt / SLIDE_SECS
		_slide_t = move_toward(_slide_t, _slide_target, step)
		if is_equal_approx(_slide_t, 0.0):
			_slide_block.visible = false
		queue_redraw()


# ─── Data ────────────────────────────────────────────────────────────────────
func _on_building_added(instance: Dictionary) -> void:
	_buildings_added.append(instance)


func _on_turn_processed(summary: Dictionary) -> void:
	_render_summary(summary)
	_have_summary = true
	if not _suppress_expand:
		_expand()
		_start_collapse_timer()
	_buildings_added.clear()


func _render_empty() -> void:
	_net = 0.0
	_starved = 0
	_built = 0
	_power_out = 0.0
	_produced_text = ""
	_fin = [
		{"k": "Sold", "v": 0.0}, {"k": "Fake Money", "v": 0.0},
		{"k": "Labour", "v": 0.0}, {"k": "Maintenance", "v": 0.0},
		{"k": "Tax & Div", "v": 0.0}, {"k": "Power", "v": 0.0},
		{"k": "Transport", "v": 0.0}, {"k": "Bought", "v": 0.0},
		{"k": "Interest", "v": 0.0}, {"k": "Profit Sharing", "v": 0.0},
	]
	queue_redraw()


func _render_summary(s: Dictionary) -> void:
	var sold: float = float(s.get("goods_sales_revenue", 0.0)) + float(s.get("power_sales_revenue", 0.0))
	var fake: float = float(s.get("fake_money", 0.0))
	var labour: float = float(s.get("labour_paid", 0.0)) + float(s.get("advisor_paid", 0.0))
	var maint: float = float(s.get("maintenance_paid", 0.0))
	var tax_div: float = float(s.get("taxes_paid", 0.0)) + float(s.get("dividends_paid", 0.0))
	var power: float = float(s.get("power_purchase_cost", 0.0))
	var transport: float = float(s.get("transport_paid", 0.0))
	var bought: float = float(s.get("goods_purchased_cost", 0.0))
	var interest: float = float(s.get("interest_paid", 0.0))
	var profit_sharing: float = float(s.get("profit_sharing_paid", 0.0))
	_fin = [
		{"k": "Sold", "v": sold},
		{"k": "Fake Money", "v": fake},
		{"k": "Labour", "v": -labour},
		{"k": "Maintenance", "v": -maint},
		{"k": "Tax & Div", "v": -tax_div},
		{"k": "Power", "v": -power},
		{"k": "Transport", "v": -transport},
		{"k": "Bought", "v": -bought},
		{"k": "Interest", "v": -interest},
		{"k": "Profit Sharing", "v": -profit_sharing},
	]
	# Fake money counts toward the reported total but not the sim's money_in.
	_net = float(s.get("money_in", 0.0)) - float(s.get("money_out", 0.0)) + fake

	var starved: Array = s.get("starved", [])
	_starved = starved.size()
	_built = _buildings_added.size()
	_produced_text = _format_produced(s.get("produced", {}))
	_power_out = _missing_power(starved)
	queue_redraw()


func _format_produced(produced: Dictionary) -> String:
	if produced.is_empty():
		return ""
	var pairs: Array = []
	for gid in produced.keys():
		pairs.append({"id": gid, "qty": int(produced[gid])})
	pairs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.qty > b.qty)
	var parts: Array = []
	for i in mini(pairs.size(), 2):
		parts.append("%d %s" % [pairs[i].qty, Catalog.get_display_name(pairs[i].id)])
	return ", ".join(parts)


func _missing_power(starved: Array) -> float:
	# Sum of "power" shortfalls reported in the starvation records, if any.
	var total := 0.0
	for rec in starved:
		for m in rec.get("missing", []):
			if str(m.get("internal_name", m.get("good_id", ""))).to_lower() == "power":
				total += float(m.get("qty", 0))
	return total


# ─── Expand / collapse ───────────────────────────────────────────────────────
func _toggle() -> void:
	if _expanded:
		_collapse()
	else:
		_expand()


func _expand() -> void:
	_expanded = true
	_slide_target = 1.0
	_slide_block.visible = true
	_suppress_chk.visible = true
	_go_btn.visible = _starved > 0
	z_index = 10                # rise above sibling panels while open
	_raise_for_input()          # …and win mouse input over them (see below)
	_cancel_collapse_timer()
	_update_layout()            # move the header hit up into the ledger
	set_process(true)


func _collapse() -> void:
	_expanded = false
	_slide_target = 0.0
	_suppress_chk.visible = false
	_go_btn.visible = false
	z_index = 0                 # back under the bottom menu at rest
	_restore_input_order()
	_cancel_collapse_timer()
	_update_layout()            # move the header hit back to the summary plate
	set_process(true)


# z_index lifts the DRAW order, but Control mouse-picking follows TREE order — so on
# its own the open ledger draws over the tech/research panel yet lets clicks fall
# THROUGH to it (you couldn't close the summary with that panel open). Moving to the
# front of our siblings while open makes the ledger consume those clicks; we restore
# the original order on collapse so the dock sits back under the other panels at rest.
func _raise_for_input() -> void:
	var parent := get_parent()
	if parent == null:
		return
	if _hud_sibling_index < 0:
		_hud_sibling_index = get_index()
	parent.move_child(self, parent.get_child_count() - 1)


func _restore_input_order() -> void:
	var parent := get_parent()
	if parent != null and _hud_sibling_index >= 0:
		parent.move_child(self, clampi(_hud_sibling_index, 0, parent.get_child_count() - 1))
	_hud_sibling_index = -1


func _start_collapse_timer() -> void:
	var timer := get_tree().create_timer(AUTO_COLLAPSE_DELAY)
	_collapse_timer = timer
	await timer.timeout
	if _collapse_timer == timer:
		_collapse()


func _cancel_collapse_timer() -> void:
	_collapse_timer = null


func _on_go_pressed() -> void:
	# Jump to the first starved building if the sim exposes one; otherwise no-op.
	if MatchState.has_signal("focus_building_requested") and not _buildings_added.is_empty():
		pass
	var summary: Dictionary = Production.last_turn_summary
	var starved: Array = summary.get("starved", [])
	if starved.is_empty():
		return
	var inst_id: String = str(starved[0].get("instance_id", ""))
	if inst_id != "" and MatchState.has_signal("focus_building_requested"):
		MatchState.focus_building_requested.emit(inst_id)
	_collapse()


# ─── Drawing ─────────────────────────────────────────────────────────────────
func _draw() -> void:
	# The ledger slides up out of the navy panel. We draw it (translated by the
	# remaining offset), then paint the navy base OVER everything below the panel
	# top — masking the still-hidden part so it appears to emerge from the panel.
	var eased := _slide_t * _slide_t * (3.0 - 2.0 * _slide_t)   # smoothstep
	if _slide_t > 0.001:
		var offset := (1.0 - eased) * _r_slide.size.y
		draw_set_transform(Vector2(0.0, offset))
		_draw_slideout(_r_slide)
		draw_set_transform(Vector2.ZERO)
	_draw_base(_r_base)
	if _slide_t < 0.5:
		_draw_summary(_r_summary)
	_draw_end_turn(_r_button)
	# Brass notch — always in the foreground, at the navy panel top; the ledger
	# slides out from behind it.
	_draw_brass_notch(_r_slide)


func _draw_base(r: Rect2) -> void:
	# Two metal layers: a squarish SILVER plate underneath and a NAVY plate on top
	# (inset), so the silver reads as a frame. The panel's top edge rises into a
	# raised octagon-style section over the End Turn button (bleeding off the right
	# edge). Each layer is a single polygon with one gradient, so the raised
	# section shades consistently with the rest of the panel.
	var tab_x0 := _r_button.position.x - 14.0          # where the raise begins
	# Bottom layer — silver.
	var sp := _container_points(r, BASE_RADIUS, tab_x0, TAB_RAISE, TAB_CHAMFER)
	var s_rect := Rect2(r.position.x, r.position.y - TAB_RAISE, r.size.x, r.size.y + TAB_RAISE)
	draw_polygon(sp, _octa_colors(sp, s_rect, SILVER_LT, SILVER_MD, SILVER_DK, SILVER_MD))
	var so := sp.duplicate()
	so.append(sp[0])
	draw_polyline(so, Color("#3a4048"), 1.5, true)
	# Top layer — navy, inset.
	var nr := r.grow(-BASE_INSET)
	var np := _container_points(nr, BASE_RADIUS - BASE_INSET, tab_x0 + BASE_INSET, TAB_RAISE, TAB_CHAMFER)
	var n_rect := Rect2(nr.position.x, nr.position.y - TAB_RAISE, nr.size.x, nr.size.y + TAB_RAISE)
	draw_polygon(np, _octa_colors(np, n_rect, NAVY_TL, NAVY_TR, NAVY_BR, NAVY_BL))
	draw_polygon(np, _octa_colors(np, n_rect, Color(1, 1, 1, 0.10), Color(1, 1, 1, 0.03), Color(0, 0, 0, 0.0), Color(1, 1, 1, 0.02)))
	var no := np.duplicate()
	no.append(np[0])
	draw_polyline(no, Color(RIM, 0.6), 1.5, true)
	# Bevel highlight along the visible top run: top edge → chamfer → raised top.
	var d := Vector2(0.0, 1.5)
	draw_line(np[4] + d, np[5] + d, Color(1, 1, 1, 0.16), 1.5)   # top edge
	draw_line(np[5] + d, np[6] + d, Color(1, 1, 1, 0.18), 1.5)   # raise chamfer
	draw_line(np[6] + d, np[7] + d, Color(1, 1, 1, 0.16), 1.5)   # raised top
	# Rivet on the silver frame's visible top-left corner.
	_rivet(Vector2(r.position.x + RIVET_EDGE + 3.0, r.position.y + RIVET_EDGE + 3.0), 3.5)


# Panel outline: rounded top-left corner, straight top edge, a raised octagon-
# style section from tab_x0 to the right (which bleeds off-screen), then the
# off-screen right + bottom edges.
func _container_points(r: Rect2, radius: float, tab_x0: float, raise: float, cut: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var rr := minf(radius, minf(r.size.x, r.size.y) * 0.5)
	var cen := Vector2(r.position.x + rr, r.position.y + rr)
	for i in 5:
		var a := lerpf(PI, PI * 1.5, float(i) / 4.0)
		pts.append(cen + Vector2(cos(a), sin(a)) * rr)
	pts.append(Vector2(tab_x0, r.position.y))               # [5] top edge end
	pts.append(Vector2(tab_x0 + cut, r.position.y - raise)) # [6] chamfer up
	pts.append(Vector2(r.end.x, r.position.y - raise))      # [7] raised top (off-screen R)
	pts.append(Vector2(r.end.x, r.end.y))                   # [8] bottom-right (off-screen)
	pts.append(Vector2(r.position.x, r.end.y))              # [9] bottom-left (off-screen)
	return pts


func _draw_summary(r: Rect2) -> void:
	# Rounded navy-steel plate with a machined metallic bevel + gold rim.
	_metal_plate(r, Color("#13243a"), Color(ACCENT, 0.5), 9.0)
	_rivets(r)
	_draw_summary_content(r)


# The collapsed bar's content (title / net / stacked stats / chevron). Drawn on
# the summary plate when collapsed, and at the top of the ledger when expanded —
# as if the summary slid up and carried this header with it.
func _draw_summary_content(r: Rect2) -> void:
	var x0 := r.position.x + SUMMARY_PAD
	var x1 := r.end.x - SUMMARY_PAD
	var r1 := r.position.y + 16.0   # top text row
	var r2 := r.position.y + 42.0   # bottom text row
	_text(F_HEAD, Vector2(x0, r1 - 1.0), "TURN SUMMARY", 18, C_TITLE)
	var net_col := C_NET_LOSS if _net < -0.005 else (C_GAIN if _net > 0.005 else C_ZERO)
	_text(F_SEMI, Vector2(x0, r2), _money(_net), 17, net_col)
	# expand/collapse chevron: centred vertically at the far right. Points UP when
	# collapsed (slides up to expand), DOWN when expanded.
	var ch_h := 40.0
	var ch_w := 28.0
	_draw_chevron_box(Rect2(x1 - ch_w, r.position.y + (SUMMARY_H - ch_h) * 0.5, ch_w, ch_h), not _expanded)
	# stats column (right, left of the chevron): starved on top, built below.
	var col_r := x1 - ch_w - 16.0
	var snum := str(_starved)
	var snw := _measure(F_SEMI, snum, 16)
	_text(F_SEMI, Vector2(col_r - snw, r1), snum, 16, C_WARN)
	_draw_warn(Vector2(col_r - snw - 19.0, r1 + 1.0), 14.0, C_WARN)
	var bnum := str(_built)
	var bnw := _measure(F_SEMI, bnum, 16)
	_text(F_SEMI, Vector2(col_r - bnw, r2), bnum, 16, C_BUILT)
	_draw_hammer(Vector2(col_r - bnw - 19.0, r2 + 1.0), C_BUILT)


func _draw_end_turn(r: Rect2) -> void:
	# Octagonal navy container in the research-panel tech style: heavy diagonal
	# lighting, metallic sheen, machined bevel, cream rim, 4 corner rivets.
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


func _draw_slideout(r: Rect2) -> void:
	# Diagonal navy fill (light top-left → dark bottom-right). The brass notch is
	# drawn separately in the foreground. 3-sided pipe frame (top, left, right).
	_diag_fill(r.grow(-3.0), NAVY_TL, NAVY_TR, NAVY_BR, NAVY_BL)
	_draw_pipe_frame(r, 26.0, true)
	var x0 := r.position.x + SLIDE_PAD
	var x1 := r.end.x - SLIDE_PAD

	# Header: the collapsed summary content, carried up into the ledger top.
	_draw_summary_content(Rect2(r.position.x, r.position.y + 10.0, r.size.x, SUMMARY_H))
	var hdr_y := r.position.y + 10.0 + SUMMARY_H + 8.0
	draw_line(Vector2(x0, hdr_y), Vector2(x1, hdr_y), C_DIVIDER, 1.0)

	var colw := (x1 - x0 - 16.0) * 0.5
	# 2-column ledger — reduced padding above Sold (gives it to the tickbox row)
	var y := hdr_y + 19.0
	for i in _fin.size():
		var f: Dictionary = _fin[i]
		var cx := x0 if i % 2 == 0 else x0 + colw + 16.0
		_fin_line(cx, cx + colw, y, str(f.k), float(f.v), 13)
		if i % 2 == 1:
			y += 27.0
	if _fin.size() % 2 == 1:
		y += 27.0
	# divider — reduced padding below Bought (gives it to the tickbox row)
	y += 3.0
	draw_line(Vector2(x0, y), Vector2(x1, y), C_DIVIDER, 1.0)
	y += 16.0
	# ops: constructed, then produced on its own full-width line
	_text(F_BODY, Vector2(x0, y), "Constructed: %d" % _built, 13, C_BODY, x1 - x0)
	y += 22.0
	if _produced_text != "":
		_text(F_BODY, Vector2(x0, y), "Produced: " + _produced_text, 13, C_BODY, x1 - x0)
		y += 22.0
	# ops line: starved + power
	if _starved > 0:
		_draw_warn(Vector2(x0, y + 1.0), 12.0, C_WARN)
		_text(F_BODY, Vector2(x0 + 17.0, y), "%d starved" % _starved, 13, C_WARN)
		_text(F_BODY, Vector2(x0 + 17.0 + _measure(F_BODY, "%d starved" % _starved, 13) + 7.0, y), "Go →", 13, Color("#5fa8e0"))
	if _power_out > 0.005:
		var px := x1 - _measure(F_BODY, "Power out %.1fT" % _power_out, 13) - 17.0
		_draw_warn(Vector2(px - 17.0, y + 1.0), 12.0, C_WARN)
		_text(F_BODY, Vector2(px, y), "Power out %.1fT" % _power_out, 13, C_WARN)
	# short tickbox row at the bottom (aligned with its hit zone)
	var ry := _suppress_chk.position.y
	_draw_checkbox(Vector2(x0, ry + 2.0), _suppress_expand)
	_text(F_BODY, Vector2(x0 + 20.0, ry + 1.0), "Don't auto-expand", 12, C_MUTED)


# ─── Draw helpers ────────────────────────────────────────────────────────────
func _diag_fill(r: Rect2, tl: Color, tr: Color, br: Color, bl: Color) -> void:
	# Four-corner gradient — light at top-left, dark at bottom-right.
	draw_polygon(
		PackedVector2Array([
			r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y),
		]),
		PackedColorArray([tl, tr, br, bl]))


func _draw_pipe_frame(r: Rect2, c: float, skip_bottom := false) -> void:
	# Thin brassy pipe as a manual 9-slice: corners scaled, edges stretched.
	# skip_bottom → 3-sided frame (top, left, right); sides run to the bottom.
	var ts := BRASS_FRAME.get_size()
	var s := minf(BRASS_SRC_SLICE, minf(ts.x, ts.y) * 0.5)
	var sr := ts.x - s
	var sb := ts.y - s
	_brass(Rect2(0, 0, s, s), Rect2(r.position.x, r.position.y, c, c))                       # TL
	_brass(Rect2(sr, 0, s, s), Rect2(r.end.x - c, r.position.y, c, c))                       # TR
	var side_h := (r.size.y - c) if skip_bottom else (r.size.y - 2.0 * c)
	if not skip_bottom:
		_brass(Rect2(0, sb, s, s), Rect2(r.position.x, r.end.y - c, c, c))                   # BL
		_brass(Rect2(sr, sb, s, s), Rect2(r.end.x - c, r.end.y - c, c, c))                   # BR
	var mw := r.size.x - 2.0 * c
	if mw > 0.0:
		_brass(Rect2(s, 0, ts.x - 2.0 * s, s), Rect2(r.position.x + c, r.position.y, mw, c)) # top
		if not skip_bottom:
			_brass(Rect2(s, sb, ts.x - 2.0 * s, s), Rect2(r.position.x + c, r.end.y - c, mw, c))
	if side_h > 0.0:
		_brass(Rect2(0, s, s, ts.y - 2.0 * s), Rect2(r.position.x, r.position.y + c, c, side_h))
		_brass(Rect2(sr, s, s, ts.y - 2.0 * s), Rect2(r.end.x - c, r.position.y + c, c, side_h))


func _brass(src: Rect2, dst: Rect2) -> void:
	draw_texture_rect_region(BRASS_FRAME, dst, src)


func _draw_brass_notch(r: Rect2) -> void:
	# Brass flange at the bottom of the ledger, where it emerges from the top of
	# the navy panel. Same brass as the pipe, lit on the left, darker on the right.
	var nx0 := r.position.x + 3.0
	var nx1 := r.end.x - 3.0
	var ny0 := r.end.y - 7.0
	var ny1 := r.end.y + 7.0
	var nr := Rect2(nx0, ny0, nx1 - nx0, ny1 - ny0)
	_diag_fill(nr, BRASS_LIT, ACCENT, BRASS_DIM, Color("#c79a40"))
	draw_line(nr.position, Vector2(nr.end.x, nr.position.y), Color(1, 1, 1, 0.45), 1.0)        # top sheen
	draw_line(Vector2(nr.position.x, nr.end.y), nr.end, Color(0, 0, 0, 0.35), 1.0)             # bottom shade
	_rivet(Vector2(nx0 + 7.0, nr.get_center().y), 3.0)
	_rivet(Vector2(nx1 - 7.0, nr.get_center().y), 3.0)


func _metal_plate(r: Rect2, base: Color, border: Color, radius: float) -> void:
	# Rounded metallic plate: solid rounded fill + machined bevel + diagonal sheen.
	var sb := StyleBoxFlat.new()
	sb.bg_color = base
	sb.set_corner_radius_all(int(radius))
	sb.border_color = border
	sb.set_border_width_all(1)
	draw_style_box(sb, r)
	_machined_bevel(r, 5.0)
	_diag_fill(r.grow(-5.0), Color(1, 1, 1, 0.10), Color(1, 1, 1, 0.03), Color(0, 0, 0, 0.12), Color(1, 1, 1, 0.02))


func _machined_bevel(r: Rect2, bevel: float) -> void:
	# Four bevel facets — light top/left, dark bottom/right (research-panel style).
	var inner := r.grow(-bevel)
	var tl := Color(1, 1, 1, 0.18)
	var ll := Color(1, 1, 1, 0.12)
	var rs := Color(0, 0, 0, 0.22)
	var bs := Color(0, 0, 0, 0.30)
	var mid := Color(0.55, 0.58, 0.60, 0.10)
	draw_polygon(PackedVector2Array([r.position + Vector2(bevel, 0), Vector2(r.end.x - bevel, r.position.y), Vector2(inner.end.x, inner.position.y), inner.position]), PackedColorArray([tl, tl, mid, mid]))
	draw_polygon(PackedVector2Array([r.position + Vector2(0, bevel), inner.position, Vector2(inner.position.x, inner.end.y), Vector2(r.position.x, r.end.y - bevel)]), PackedColorArray([ll, mid, mid, ll]))
	draw_polygon(PackedVector2Array([Vector2(r.end.x, r.position.y + bevel), Vector2(r.end.x, r.end.y - bevel), inner.end, Vector2(inner.end.x, inner.position.y)]), PackedColorArray([rs, rs, mid, mid]))
	draw_polygon(PackedVector2Array([Vector2(r.position.x + bevel, r.end.y), Vector2(inner.position.x, inner.end.y), inner.end, Vector2(r.end.x - bevel, r.end.y)]), PackedColorArray([bs, mid, mid, bs]))


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


func _rounded_rect_points(r: Rect2, radius: float) -> PackedVector2Array:
	var rr := minf(radius, minf(r.size.x, r.size.y) * 0.5)
	var seg := 4
	var pts := PackedVector2Array()
	# corner centres + arc ranges: TL, TR, BR, BL (clockwise)
	var corners := [
		[Vector2(r.position.x + rr, r.position.y + rr), PI, PI * 1.5],
		[Vector2(r.end.x - rr, r.position.y + rr), PI * 1.5, TAU],
		[Vector2(r.end.x - rr, r.end.y - rr), 0.0, PI * 0.5],
		[Vector2(r.position.x + rr, r.end.y - rr), PI * 0.5, PI],
	]
	for cdef in corners:
		var cen: Vector2 = cdef[0]
		for i in seg + 1:
			var a: float = lerpf(cdef[1], cdef[2], float(i) / seg)
			pts.append(cen + Vector2(cos(a), sin(a)) * rr)
	return pts


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


func _fin_line(x0: float, x1: float, y: float, k: String, v: float, fs := 12) -> void:
	_text(F_BODY, Vector2(x0, y), k, fs, C_MUTED)
	var col := C_ZERO if absf(v) < 0.005 else (C_LOSS if v < 0 else C_GAIN)
	var s := _money(v)
	_text(F_SEMI, Vector2(x1 - _measure(F_SEMI, s, fs), y), s, fs, col)


func _rivets(r: Rect2) -> void:
	var e := RIVET_EDGE + 3.0
	for c in [Vector2(e, e), Vector2(r.size.x - e, e), Vector2(e, r.size.y - e), Vector2(r.size.x - e, r.size.y - e)]:
		_rivet(r.position + c, 3.5)


func _rivet(c: Vector2, rad: float) -> void:
	draw_circle(c, rad, Color("#5a636e"))
	draw_circle(c - Vector2(rad * 0.3, rad * 0.3), rad * 0.55, Color("#c9d4df"))
	draw_arc(c, rad, 0, TAU, 16, Color(0, 0, 0, 0.5), 1.0)


func _vgrad(r: Rect2, stops: Array) -> void:
	# Vertical gradient as 1px horizontal strips between colour stops.
	var n := int(r.size.y)
	for i in n:
		var t := float(i) / maxf(1.0, r.size.y - 1.0)
		var col := _grad_at(stops, t)
		var yy := r.position.y + float(i)
		draw_line(Vector2(r.position.x, yy), Vector2(r.end.x, yy), col, 1.0)


func _grad_at(stops: Array, t: float) -> Color:
	for i in range(1, stops.size()):
		if t <= stops[i][0]:
			var a: Array = stops[i - 1]
			var b: Array = stops[i]
			var span: float = maxf(0.0001, b[0] - a[0])
			return (a[1] as Color).lerp(b[1] as Color, (t - a[0]) / span)
	return stops[stops.size() - 1][1]


func _text(font: Font, top_left: Vector2, s: String, fs: int, col: Color, width := -1.0) -> void:
	# width > 0 clips the line (and ellipsizes) so it can't run under the frame.
	draw_string(font, Vector2(top_left.x, top_left.y + font.get_ascent(fs)), s,
		HORIZONTAL_ALIGNMENT_LEFT, width, fs, col, TextServer.JUSTIFICATION_NONE,
		TextServer.DIRECTION_AUTO, TextServer.ORIENTATION_HORIZONTAL)


func _measure(font: Font, s: String, fs: int) -> float:
	return font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x


func _draw_minibtn(r: Rect2, label: String) -> void:
	_vgrad(r, [[0.0, Color("#3a4654")], [1.0, Color("#28323d")]])
	draw_rect(r, Color("#18222d"), false, 1.0)
	draw_line(r.position, Vector2(r.end.x, r.position.y), Color(0.7, 0.8, 0.9, 0.3), 1.0)
	var tw := _measure(F_MED, label, 12)
	_text(F_MED, Vector2(r.position.x + (r.size.x - tw) * 0.5, r.position.y + (r.size.y - 12.0) * 0.5 - 1.0), label, 12, C_TITLE)


func _draw_checkbox(c: Vector2, on: bool) -> void:
	var box := Rect2(c, Vector2(14, 14))
	draw_rect(box, Color("#0c1a29"))
	draw_rect(box, Color("#3a566f"), false, 1.5)
	if on:
		var pts := PackedVector2Array([c + Vector2(3, 7), c + Vector2(6, 10), c + Vector2(11, 4)])
		draw_polyline(pts, ACCENT, 2.0, true)


# ─── Icon glyphs (minimal vector forms matching the design kit) ──────────────
func _draw_chevron_box(box: Rect2, up: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#0c1a29")
	sb.set_corner_radius_all(4)
	sb.border_color = Color(ACCENT, 0.45)
	sb.set_border_width_all(1)
	draw_style_box(sb, box)
	var m := box.get_center()
	var pts: PackedVector2Array
	if up:
		pts = PackedVector2Array([m + Vector2(-5, 3), m + Vector2(0, -3), m + Vector2(5, 3)])
	else:
		pts = PackedVector2Array([m + Vector2(-5, -3), m + Vector2(0, 3), m + Vector2(5, -3)])
	draw_polyline(pts, ACCENT, 2.0, true)


func _draw_warn(top_left: Vector2, s: float, col: Color) -> void:
	var a := top_left + Vector2(s * 0.5, 0)
	var b := top_left + Vector2(0, s)
	var c := top_left + Vector2(s, s)
	draw_polyline(PackedVector2Array([a, b, c, a]), col, 1.6, true)
	draw_line(top_left + Vector2(s * 0.5, s * 0.4), top_left + Vector2(s * 0.5, s * 0.7), col, 1.6)
	draw_circle(top_left + Vector2(s * 0.5, s * 0.85), 0.9, col)


func _draw_hammer(top_left: Vector2, col: Color) -> void:
	# Simplified hammer: head bar (top-right) + handle (down-left).
	var s := 13.0
	draw_line(top_left + Vector2(s * 0.15, s * 0.85), top_left + Vector2(s * 0.6, s * 0.4), col, 2.0)
	var head := PackedVector2Array([
		top_left + Vector2(s * 0.5, s * 0.3), top_left + Vector2(s * 0.95, s * 0.65),
	])
	draw_line(head[0], head[1], col, 3.0)


func _money(v: float, dp: int = 2) -> String:
	var sign_s := "-" if v < -0.005 else "+"
	var a := absf(v)
	var whole := int(a)
	var frac := int(round((a - float(whole)) * pow(10, dp)))
	var ws := str(whole)
	# thousands separators
	var out := ""
	var cnt := 0
	for i in range(ws.length() - 1, -1, -1):
		out = ws[i] + out
		cnt += 1
		if cnt % 3 == 0 and i > 0:
			out = "," + out
	var fs := str(frac).pad_zeros(dp)
	return "%s£%s.%s" % [sign_s, out, fs]


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
