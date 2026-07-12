extends PanelContainer
## Top Bar v2 — implemented from the owner's React prototype "Top Bar (offline).html".
## Modules left→right:
##   Treasury (cash + net/turn + runway) · Power net · Victory (5 track meters + score)
##   · [flex] · Briefing (merged bell: decisions + updates) · [flex]
##   · Council (seated portraits w/ loyalty rings) · Encyclopedia · | · Turn/date · Menu.
## Treasury / Victory / Council open quick-glance FLYOUTS anchored under the bar whose
## buttons deep-link into the full panels (Money / Victory / People); the Briefing
## module expands the Turn Briefing hub directly.
##
## External contracts kept: the MoneyWidget Button's node path (e2e drives it),
## %EncyclopediaButton + %TurnCounter unique names (world_map + tutorial spotlights),
## the three *_clicked signals (bottom_menu routing), the bankruptcy strip and the
## CFO intro popup.

@onready var money_widget: Button = $MarginContainer/HBoxContainer/MoneyWidget

signal money_widget_clicked
## Treasury mini-panel action requests a specific tab in the full Money panel.
signal money_panel_tab_requested(tab_name: String)
## The victory flyout's "Full breakdown" was clicked (opens the Victory panel).
signal victory_widget_clicked
## A council flyout row was clicked (opens the People panel).
signal council_widget_clicked

const FLASH_RED := Color(0.9, 0.2, 0.2)
# Show the "Bankruptcy imminent" strip when total runway — cash plus remaining
# borrowing room — drops below this.
const BANKRUPTCY_IMMINENT_RUNWAY := 100.0

# ── Prototype palette (top-bar local; the DS navy family, tuned per the design) ──
const BAR_H := 69.0
const MOD_H := 48.0
# Briefing notch: taller than the bar, hangs below it as a two-row centre notch.
const NOTCH_H := 102.0
const NOTCH_MIN_W := 300.0
const NOTCH_RADIUS := 16.0
# Research microscope object — the exact art the bottom menu's (alt-mode) Research
# button uses. Composited onto a teal disc + light ring in the briefing notch on
# research-unlock turns, mirroring bottom_menu.ALT_COLORS["TechButton"].
const RESEARCH_ICON: Texture2D = preload("res://assets/icons/ui_icons/alt/research.png")
const RESEARCH_DISC := Color("#1e5e63")   # teal disc  (ALT_COLORS["TechButton"][0])
const RESEARCH_RING := Color("#ddefec")   # light ring (ALT_COLORS["TechButton"][1])
# Metallic bottom bezel (the end-turn dock's machined-silver family), lit from the left.
const EDGE_H := 7.0
const SILVER_LT := Color("#b3bcc6")
const SILVER_MD := Color("#8b95a1")
const SILVER_DK := Color("#5b636e")
const EDGE_SEAM := Color("#3a4048")
const C_BAR_BG := Color("#0c1c2e")
const C_BAR_EDGE := Color("#1c3149")
const C_MOD_BG := Color(0.055, 0.125, 0.204, 0.85)     # rgba(14,32,52,.85)
const C_MOD_BORDER := Color("#22384f")
const C_ACTIVE_BG := Color("#15304a")
const C_ACTIVE_BORDER := Color("#2f5578")
const C_WARN_BORDER := Color(0.886, 0.376, 0.29, 0.55) # rgba(226,96,74,.55)
const C_MUTED := Color("#62788f")
const C_TEXT := Color("#cdd9e6")
const C_BRIGHT := Color("#f3f8fd")
const C_GOOD := Color("#7ec98a")
const C_BAD := Color("#e6917f")
const C_RED := Color("#e2604a")
const C_AMBER := Color("#e6b34a")
const C_CREAM := Color("#f2e6c8")
const C_TRACK_BG := Color("#0a1623")
const C_TRACK_EDGE := Color("#1c3149")

const _COUNCIL_GOOD := Color("#5FBF6B")
const _COUNCIL_WARN := Color("#E6B34A")
const _COUNCIL_BAD := Color("#E2604A")
const DISLOYAL_BELOW := -3.4   # loyalty (−10..+10) under this = disloyal

const CFOIntroPopup := preload("res://scripts/cfo_intro_popup.gd")
const CFO_INTRO_BODY := "I saw we weren't being tax efficient so now I've filed for a tax credit based on our losses. I can only make it work for 5 turns at a time but it should mean we can reduce our tax bill based on recent losses. See, and you worried about keeping me around…"

var _flashing := false
var _bankruptcy_strip: PanelContainer

# Treasury module labels (inside the MoneyWidget Button)
var _cash_label: Label
var _net_label: Label
var _runway_label: Label
var _money_inner: HBoxContainer

# Power module
var _power_btn: Control
var _power_glyph: Label
var _power_head: Label
var _power_sub: Label

# Victory module
var _victory_btn: Control
var _victory_meters: HBoxContainer
var _victory_score: Label
var _victory_target: Label   # "/ N" — the rising win threshold for the current turn

# Briefing notch (top_level: centred on the viewport, hangs below the bar)
var _briefing_btn: Control
var _briefing_glyph: Control   # _BellIcon (vector — the font has no bell glyph)
var _research_badge: Panel  # teal microscope badge — visible only on turns research unlocks
var _research_pill: Panel  # count pill on the badge — shown when >1 research unlocks in a turn
var _research_pill_label: Label
var _research_seen := false  # UI-only: briefing opened while research showing; reset each turn
var _briefing_head: Label
var _briefing_sub: Label
var _briefing_dot: Panel

# Council module
var _council_btn: Control
var _council_status: Label
var _council_stack: HBoxContainer

# Turn/date
var _date_label: Label

# Flyout layer
var _fly_layer: CanvasLayer
var _fly_scrim: Control
var _fly_panel: PanelContainer
var _fly_open_id := ""

# Coalesced refresh (notification-bell doctrine): sim signals mark dirty; ONE
# deferred refresh per frame updates every module label.
var _refresh_queued := false


func _ready() -> void:
	_style_bar()
	_build_treasury()
	_build_power()
	_build_victory()
	_build_briefing()
	_build_council()
	_adopt_encyclopedia_and_turn()
	_build_menu()
	_build_fly_layer()
	_add_bankruptcy_warning()

	MatchState.money_changed.connect(_on_money_changed)
	MatchState.build_rejected_no_funds.connect(_on_build_rejected_no_funds)
	MatchState.cfo_tax_credit_filed.connect(_on_cfo_tax_credit_filed)
	MatchState.advisors_changed.connect(_queue_refresh)
	MatchState.advisor_loyalty_changed.connect(func(_id: String, _v: float) -> void: _queue_refresh())
	Production.turn_processed.connect(func(_s: Dictionary) -> void: _queue_refresh())
	# A new turn brings a fresh research digest, so the microscope should show again.
	TurnManager.turn_advanced.connect(func(_t: int) -> void:
		_research_seen = false
		_queue_refresh())
	LoanState.loans_updated.connect(_queue_refresh)
	VictoryState.score_changed.connect(func(_t: int, _b: Dictionary) -> void: _queue_refresh())
	TurnBriefing.items_changed.connect(_queue_refresh)
	# Opening the briefing marks research as seen — hide the microscope until next turn.
	TurnBriefing.expanded_changed.connect(func(e: bool) -> void:
		if e:
			_research_seen = true
		_queue_refresh())
	# The v2 briefing notch replaces the collapsed strip.
	TurnBriefing.strip_enabled = false
	get_viewport().size_changed.connect(_recenter_notch)
	resized.connect(queue_redraw)   # the metallic edge spans the live width
	_queue_refresh()


# ── Bar chrome ────────────────────────────────────────────────────────────────

func _style_bar() -> void:
	custom_minimum_size = Vector2(0, BAR_H)
	offset_bottom = BAR_H
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_BAR_BG
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 6   # trimmed padding — remove unused space, don't shrink modules
	sb.content_margin_bottom = 6 + EDGE_H   # keep modules off the metallic rim
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 8
	sb.shadow_offset = Vector2(0, 4)
	add_theme_stylebox_override("panel", sb)
	# The scene's MarginContainer reserves 276px on the right for the OLD
	# encyclopedia overlay — kill it so the module row spans the full bar.
	var margin := money_widget.get_parent().get_parent() as MarginContainer
	margin.add_theme_constant_override("margin_right", 0)
	var hbox := money_widget.get_parent() as HBoxContainer
	hbox.add_theme_constant_override("separation", 10)

## Sample the bar's left→right metal lighting at canvas x (0 = lit, right = shadowed).
func _silver_at(canvas_x: float) -> Color:
	var vw := maxf(1.0, get_viewport_rect().size.x)
	return SILVER_LT.lerp(SILVER_DK, clampf(canvas_x / vw, 0.0, 1.0))

func _draw() -> void:
	var w := size.x
	var y1 := size.y
	var y0 := y1 - EDGE_H
	# Ambient light sweeping LEFT → RIGHT across the whole bar (owner 2026-07-11:
	# the bar read top-lit; this gives it a horizontal light instead). Brightest at
	# the left, fading to nothing by mid-bar; a matching shade deepens the right end.
	draw_polygon(
		PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, y0), Vector2(0, y0)]),
		PackedColorArray([Color(1, 1, 1, 0.055), Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.05)]))
	draw_polygon(
		PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, y0), Vector2(0, y0)]),
		PackedColorArray([Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.10), Color(0, 0, 0, 0.09), Color(0, 0, 0, 0.0)]))
	# Machined metallic BEZEL along the bar's bottom (end-turn dock silver):
	# lit left → right along its length, and bevelled through its depth — dark
	# seam against the navy, bright top lip, mid body, shadowed lower return.
	draw_line(Vector2(0, y0 - 0.5), Vector2(w, y0 - 0.5), EDGE_SEAM, 1.0)
	draw_polygon(
		PackedVector2Array([Vector2(0, y0), Vector2(w, y0), Vector2(w, y1), Vector2(0, y1)]),
		PackedColorArray([SILVER_LT, SILVER_DK, SILVER_DK, SILVER_LT]))
	# Top lip highlight, fading down (the raised face of the bezel).
	draw_polygon(
		PackedVector2Array([Vector2(0, y0), Vector2(w, y0), Vector2(w, y0 + 2.8), Vector2(0, y0 + 2.8)]),
		PackedColorArray([Color(1, 1, 1, 0.55), Color(1, 1, 1, 0.16), Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.0)]))
	# Lower return falling into shadow + crisp dark base line.
	draw_polygon(
		PackedVector2Array([Vector2(0, y1 - 3.0), Vector2(w, y1 - 3.0), Vector2(w, y1), Vector2(0, y1)]),
		PackedColorArray([Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.45), Color(0, 0, 0, 0.38)]))
	draw_line(Vector2(0, y1 - 0.5), Vector2(w, y1 - 0.5), Color(0.05, 0.07, 0.10, 0.9), 1.0)

func _module_box(active: bool, warn: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_ACTIVE_BG if active else C_MOD_BG
	sb.border_color = C_ACTIVE_BORDER if active else (C_WARN_BORDER if warn else C_MOD_BORDER)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	return sb

## Small uppercase module tag ("COUNCIL").
func _tag(text: String) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_size_override("font_size", 10)
	l.add_theme_color_override("font_color", C_MUTED)
	return l

func _mini(text: String, color: Color, size: int = 10) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

## Clickable bar module: PanelContainer (sizes to children, unlike Button) that
## emits "pressed" and swaps active/warn chrome. Buttons can't hold containers.
class _ModuleBtn extends PanelContainer:
	signal pressed
	var warn := false:
		set(v):
			warn = v
			_restyle()
	var active := false:
		set(v):
			active = v
			_restyle()
	var _hover := false
	var _bar: Node
	func _init(bar: Node) -> void:
		_bar = bar
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_restyle()
		mouse_entered.connect(func() -> void: _hover = true; _restyle())
		mouse_exited.connect(func() -> void: _hover = false; _restyle())
	func _restyle() -> void:
		var sb: StyleBoxFlat = _bar._module_box(active or _hover, warn)
		add_theme_stylebox_override("panel", sb)
		queue_redraw()
	func _draw() -> void:
		# Left → right light sheen over the module (drawn on top of the panel
		# stylebox), so modules read as lit from the left rather than top-down.
		var r := Rect2(Vector2.ZERO, size).grow(-2.0)
		draw_polygon(
			PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
			PackedColorArray([Color(1, 1, 1, 0.07), Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.055)]))
	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			pressed.emit()

## Full-rect left→right light sheen, mounted on the Button-based modules (Treasury,
## Encyclopedia) that can't override _draw the way _ModuleBtn does — keeps the
## whole bar's lighting horizontal and consistent.
class _Sheen extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)
		resized.connect(queue_redraw)
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size).grow(-2.0)
		draw_polygon(
			PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
			PackedColorArray([Color(1, 1, 1, 0.07), Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.055)]))

func _module_row(mod: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 9)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mod.add_child(row)
	return row

func _divider() -> Control:
	var d := Panel.new()
	d.custom_minimum_size = Vector2(1, MOD_H - 10)
	d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_TRACK_EDGE
	d.add_theme_stylebox_override("panel", sb)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return d

func _flex() -> Control:
	var s := Control.new()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s

func _hbox() -> HBoxContainer:
	return money_widget.get_parent() as HBoxContainer


# ── 1 · Treasury (the MoneyWidget Button, restyled — node path is an e2e contract) ──

func _build_treasury() -> void:
	money_widget.text = ""
	money_widget.tooltip_text = "Treasury — money & loans"
	money_widget.focus_mode = Control.FOCUS_NONE
	money_widget.custom_minimum_size = Vector2(0, MOD_H)
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		money_widget.add_theme_stylebox_override(state, _module_box(state != "normal", false))
	# Buttons don't size to child containers: full-rect inner row + manual min width.
	_money_inner = HBoxContainer.new()
	_money_inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_money_inner.offset_left = 12
	_money_inner.offset_right = -12
	_money_inner.alignment = BoxContainer.ALIGNMENT_CENTER
	_money_inner.add_theme_constant_override("separation", 10)
	_money_inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	money_widget.add_child(_money_inner)
	var coin := _mini("£", C_AMBER, 21)
	_money_inner.add_child(coin)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 1)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_money_inner.add_child(col)
	_cash_label = Label.new()
	_cash_label.theme_type_variation = "Numeric"
	_cash_label.add_theme_font_size_override("font_size", 20)
	_cash_label.add_theme_color_override("font_color", C_BRIGHT)
	col.add_child(_cash_label)
	var sub := HBoxContainer.new()
	sub.add_theme_constant_override("separation", 6)
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(sub)
	_net_label = _mini("", C_GOOD, 13)
	sub.add_child(_net_label)
	_runway_label = _mini("", C_RED, 11)
	sub.add_child(_runway_label)
	money_widget.add_child(_Sheen.new())   # left→right light, matching the modules
	money_widget.pressed.connect(func() -> void: _toggle_fly("treasury"))

func _money_text(n: float) -> String:
	# £ with thousands separators, no decimals in the bar (the flyout has exact rows).
	var v := int(round(absf(n)))
	var s := str(v)
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return ("−£" if n < 0 else "£") + out


# ── 2 · Power: status-first (green self-sufficient / amber grid / red unpowered) ──

func _build_power() -> void:
	var mod := _ModuleBtn.new(self)
	mod.name = "PowerModule"
	mod.custom_minimum_size = Vector2(0, MOD_H)
	var row := _module_row(mod)
	_power_glyph = _mini("⚡", C_GOOD, 19)
	row.add_child(_power_glyph)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	_power_head = _mini("Powered", C_GOOD, 15)
	col.add_child(_power_head)
	_power_sub = _mini("self-sufficient", C_MUTED, 12)
	col.add_child(_power_sub)
	_hbox().add_child(mod)
	_power_btn = mod
	mod.pressed.connect(_on_power_pressed)

func _on_power_pressed() -> void:
	# Toggle the Power (power-balance) map overlay directly on the MapMode autoload —
	# the same call the Mapmodes panel's Power row makes. set_sentinel_mode is itself a
	# toggle, and the overlay is driven by MapMode signals (map_overlay.gd), so the
	# Mapmodes panel need not be open for the overlay to appear.
	MapMode.set_sentinel_mode(MapMode.Mode.POWER_BALANCE, MapMode.POWER_SENTINEL)

func _power_stats() -> Dictionary:
	var s: Dictionary = Production.last_turn_summary
	var unpowered := 0
	for iid in Production.missing_by_building:
		var b: Dictionary = MatchState.buildings.get(iid, {})
		if b.is_empty() or not MatchState.is_player_owned(b):
			continue
		var recipe := Catalog.get_recipe(str(b.get("recipe_id", "")))
		if str(recipe.get("output_name", "")) == "power":
			continue   # a producer's "power" entry is the cable-cap marker, not starvation
		for m in (Production.missing_by_building[iid] as Array):
			if str(m.get("good_id", "")) == "power":
				unpowered += 1
				break
	return {
		"self_gen": int(s.get("power_supply", 0)),
		"grid_draw": int(s.get("grid_bought", 0)),
		"unpowered": unpowered,
	}


# ── 3 · Victory: five mini track meters + score ─────────────────────────────────

func _build_victory() -> void:
	var mod := _ModuleBtn.new(self)
	mod.name = "VictoryModule"
	mod.tooltip_text = "Victory tracks"
	mod.custom_minimum_size = Vector2(0, MOD_H)
	var row := _module_row(mod)
	row.add_child(_mini("★", C_CREAM.darkened(0.15), 16))
	_victory_meters = HBoxContainer.new()
	_victory_meters.add_theme_constant_override("separation", 6)
	_victory_meters.alignment = BoxContainer.ALIGNMENT_END
	_victory_meters.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_victory_meters)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	_victory_score = Label.new()
	_victory_score.theme_type_variation = "Numeric"
	_victory_score.add_theme_font_size_override("font_size", 18)
	_victory_score.add_theme_color_override("font_color", C_CREAM)
	col.add_child(_victory_score)
	_victory_target = _mini("/ 4,000", C_MUTED, 11)   # updated to the rising threshold each refresh
	_victory_target.tooltip_text = "Points needed to win rise over the game — 1 track from turn 105 up to 4 tracks by turn 300."
	col.add_child(_victory_target)
	mod.pressed.connect(func() -> void: _toggle_fly("victory"))
	_hbox().add_child(mod)
	_victory_btn = mod

func _track_color(entry: Dictionary) -> Color:
	return DS.PALETTE.get(str(entry.get("color_key", "")), C_CREAM)

func _refresh_victory() -> void:
	var bd: Dictionary = VictoryState.get_breakdown()
	for c in _victory_meters.get_children():
		c.queue_free()
	for t in (bd.get("tracks", []) as Array):
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 2)
		cell.alignment = BoxContainer.ALIGNMENT_END
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.tooltip_text = "%s — %d%%" % [str(t.get("name", "")), int(round(float(t.get("progress", 0.0)) * 100.0))]
		var meter := Panel.new()
		meter.custom_minimum_size = Vector2(15, 30)
		var msb := StyleBoxFlat.new()
		msb.bg_color = C_TRACK_BG
		msb.border_color = C_TRACK_EDGE
		msb.set_border_width_all(1)
		msb.set_corner_radius_all(3)
		meter.add_theme_stylebox_override("panel", msb)
		var fill := Panel.new()
		var fsb := StyleBoxFlat.new()
		fsb.bg_color = _track_color(t)
		fsb.set_corner_radius_all(2)
		fill.add_theme_stylebox_override("panel", fsb)
		fill.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		var frac: float = clampf(float(t.get("progress", 0.0)), 0.0, 1.0)
		fill.offset_top = -28.0 * frac
		fill.offset_bottom = -1
		fill.offset_left = 1
		fill.offset_right = -1
		meter.add_child(fill)
		cell.add_child(meter)
		var letter := _mini(str(t.get("name", "?")).substr(0, 1), C_MUTED, 9)
		letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		letter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_child(letter)
		_victory_meters.add_child(cell)
	_victory_score.text = _thousands(int(bd.get("total", 0)))
	if _victory_target != null:
		_victory_target.text = "/ %s" % _thousands(int(bd.get("win_threshold", 4000)))

func _thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if n < 0 else "") + out


# ── 4 · Briefing NOTCH: a two-row centre notch taller than the bar itself ──────
# top_level (containers skip it — same trick as the bankruptcy strip), centred on
# the viewport, hanging NOTCH_H − BAR_H below the bar. Click toggles the hub.

## Vector bell (dome, flared skirt, clapper, crown loop — notification_bell's
## fallback shape; the bundled font renders the bell codepoint as tofu).
class _BellIcon extends Control:
	var color := Color("#cdd9e6")
	func _init() -> void:
		custom_minimum_size = Vector2(24, 26)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func set_color(c: Color) -> void:
		color = c
		queue_redraw()
	func _draw() -> void:
		var centre := size * 0.5
		var w := size.x * 0.78
		var h := size.y * 0.78
		var cx := centre.x
		var top := centre.y - h * 0.5
		var bot := centre.y + h * 0.36
		var body := PackedVector2Array([
			Vector2(cx - w * 0.20, top), Vector2(cx + w * 0.20, top),
			Vector2(cx + w * 0.42, top + h * 0.45), Vector2(cx + w * 0.55, bot),
			Vector2(cx - w * 0.55, bot), Vector2(cx - w * 0.42, top + h * 0.45),
		])
		draw_colored_polygon(body, color)
		draw_rect(Rect2(Vector2(cx - w * 0.55, bot), Vector2(w * 1.10, 1.8)), color)
		draw_circle(Vector2(cx, bot + 3.6), 2.1, color)
		draw_arc(Vector2(cx, top - 1.8), 2.0, 0.0, TAU, 12, color, 1.6, true)

class _NotchBtn extends PanelContainer:
	signal pressed
	var warn := false:
		set(v):
			warn = v
			_restyle()
	var active := false:
		set(v):
			active = v
			_restyle()
	var _hover := false
	var _bar: Node
	func _init(bar: Node) -> void:
		_bar = bar
		top_level = true
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func() -> void: _hover = true; _restyle())
		mouse_exited.connect(func() -> void: _hover = false; _restyle())
		resized.connect(queue_redraw)
		_restyle()
	func _restyle() -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = _bar.C_ACTIVE_BG if (active or _hover) else _bar.C_BAR_BG
		if warn:
			sb.bg_color = (sb.bg_color as Color).lerp(Color(0.32, 0.07, 0.05), 0.30)
		sb.corner_radius_bottom_left = int(_bar.NOTCH_RADIUS)
		sb.corner_radius_bottom_right = int(_bar.NOTCH_RADIUS)
		sb.content_margin_left = 26
		sb.content_margin_right = 26
		sb.content_margin_top = 12
		sb.content_margin_bottom = 14
		sb.shadow_color = Color(0, 0, 0, 0.35)
		sb.shadow_size = 8
		sb.shadow_offset = Vector2(0, 4)
		add_theme_stylebox_override("panel", sb)
		queue_redraw()
	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			pressed.emit()
	func _draw() -> void:
		# Metallic rim wrapping the notch's left/bottom/right — continues the bar's
		# silver bottom edge, sampling the same left→right lighting at each point.
		var r: float = _bar.NOTCH_RADIUS
		var w := size.x
		var h := size.y - 1.0
		var pts := PackedVector2Array()
		pts.append(Vector2(1.0, 0.0))
		pts.append(Vector2(1.0, h - r))
		for i in range(1, 7):
			var a := PI - (PI * 0.5) * float(i) / 6.0    # left → bottom
			pts.append(Vector2(r, h - r) + Vector2(cos(a), sin(a)) * (r - 1.0))
		pts.append(Vector2(w - r, h))
		for i in range(1, 7):
			var a := PI * 0.5 - (PI * 0.5) * float(i) / 6.0   # bottom → right
			pts.append(Vector2(w - r, h - r) + Vector2(cos(a), sin(a)) * (r - 1.0))
		pts.append(Vector2(w - 1.0, 0.0))
		var cols := PackedColorArray()
		var warn_tint := Color("#b0574a")
		for p in pts:
			var c: Color = _bar._silver_at(global_position.x + p.x)
			cols.append(c.lerp(warn_tint, 0.55) if warn else c)
		draw_polyline_colors(pts, cols, 2.5, true)

func _build_briefing() -> void:
	var notch := _NotchBtn.new(self)
	notch.name = "BriefingModule"
	notch.tooltip_text = "Turn briefing"
	notch.custom_minimum_size = Vector2(NOTCH_MIN_W, NOTCH_H)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notch.add_child(row)
	# Research badge (leads the row) — the bottom menu's teal microscope, built to
	# match its alt-mode style: research.png object on a teal disc + light ring.
	# Shown only on turns a research unlock lands.
	_research_badge = Panel.new()
	_research_badge.custom_minimum_size = Vector2(60, 60)
	var rbsb := StyleBoxFlat.new()
	rbsb.bg_color = RESEARCH_DISC
	rbsb.set_corner_radius_all(30)          # circular on the 60px disc
	rbsb.border_color = RESEARCH_RING
	rbsb.set_border_width_all(4)
	_research_badge.add_theme_stylebox_override("panel", rbsb)
	_research_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_research_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_research_badge.tooltip_text = "Research unlocked this turn"
	_research_badge.visible = false
	var micro := TextureRect.new()
	micro.texture = RESEARCH_ICON
	micro.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	micro.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	micro.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	micro.offset_left = 6.0
	micro.offset_top = 6.0
	micro.offset_right = -6.0
	micro.offset_bottom = -6.0
	micro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_research_badge.add_child(micro)
	# Count pill on the badge's bottom-right corner — only when >1 research this turn.
	_research_pill = Panel.new()
	_research_pill.custom_minimum_size = Vector2(24, 18)
	_research_pill.position = Vector2(40, 48)
	_research_pill.z_index = 1
	_research_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rpsb := StyleBoxFlat.new()
	rpsb.bg_color = C_RED
	rpsb.set_corner_radius_all(9)           # stadium/pill shape
	rpsb.border_color = C_BRIGHT
	rpsb.set_border_width_all(2)
	_research_pill.add_theme_stylebox_override("panel", rpsb)
	_research_pill.visible = false
	_research_pill_label = _mini("2", C_BRIGHT, 12)
	_research_pill_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_research_pill_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_research_pill_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_research_pill_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_research_pill.add_child(_research_pill_label)
	_research_badge.add_child(_research_pill)
	row.add_child(_research_badge)
	var glyph_holder := Control.new()
	glyph_holder.custom_minimum_size = Vector2(28, 28)
	glyph_holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	glyph_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_briefing_glyph = _BellIcon.new()
	_briefing_glyph.position = Vector2(1, 1)
	_briefing_glyph.size = Vector2(24, 26)
	glyph_holder.add_child(_briefing_glyph)
	_briefing_dot = Panel.new()
	_briefing_dot.custom_minimum_size = Vector2(9, 9)
	_briefing_dot.position = Vector2(21, 0)
	var dsb := StyleBoxFlat.new()
	dsb.bg_color = C_RED
	dsb.set_corner_radius_all(5)
	_briefing_dot.add_theme_stylebox_override("panel", dsb)
	_briefing_dot.visible = false
	glyph_holder.add_child(_briefing_dot)
	row.add_child(glyph_holder)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 3)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	_briefing_head = _mini("Briefing", C_BRIGHT, 18)
	col.add_child(_briefing_head)
	_briefing_sub = _mini("0 updates", C_MUTED, 14)
	col.add_child(_briefing_sub)
	notch.pressed.connect(func() -> void:
		_close_fly()
		if TurnBriefing.expanded:
			TurnBriefing.collapse()
		else:
			TurnBriefing.expand())
	add_child(notch)
	_briefing_btn = notch

func _recenter_notch() -> void:
	if _briefing_btn == null or not is_instance_valid(_briefing_btn):
		return
	var vw := get_viewport_rect().size.x
	var min_size := _briefing_btn.get_combined_minimum_size()
	_briefing_btn.size = Vector2(maxf(min_size.x, NOTCH_MIN_W), NOTCH_H)
	_briefing_btn.position = Vector2(roundf((vw - _briefing_btn.size.x) * 0.5), 0.0)
	queue_redraw()

func _refresh_briefing() -> void:
	var decisions := 0
	var updates := 0
	var research_count := 0
	for it in TurnBriefing.items():
		if str(it.get("kind", "")) == "decision":
			decisions += 1
		else:
			updates += 1
		if str(it.get("event_kind", "")) == "research_unlocked":
			research_count += int(it.get("magnitude", 1))   # aggregated item carries the count
	if _research_badge != null:
		_research_badge.visible = research_count > 0 and not _research_seen
	if _research_pill != null:
		_research_pill.visible = research_count > 1 and not _research_seen
		_research_pill_label.text = "%d" % research_count
	var hot := decisions > 0
	(_briefing_btn as _NotchBtn).warn = hot
	(_briefing_btn as _NotchBtn).active = TurnBriefing.expanded
	(_briefing_glyph as _BellIcon).set_color(C_RED if hot else C_TEXT)
	_briefing_head.text = ("%d decision%s to make" % [decisions, "" if decisions == 1 else "s"]) if hot else "Briefing"
	_briefing_head.add_theme_color_override("font_color", Color("#f0a496") if hot else C_BRIGHT)
	_briefing_sub.text = "%d update%s" % [updates, "" if updates == 1 else "s"]
	_briefing_sub.add_theme_color_override("font_color", C_TEXT if updates > 0 else C_MUTED)
	_briefing_dot.visible = decisions + updates > 0
	var dsb := _briefing_dot.get_theme_stylebox("panel") as StyleBoxFlat
	if dsb != null:
		dsb.bg_color = C_RED if hot else C_AMBER
	call_deferred("_recenter_notch")


# ── 5 · Council: seated portraits with loyalty rings + number chips ─────────────

func _build_council() -> void:
	# Everything from Council rightwards is anchored to the far right edge (the
	# briefing notch is out of the flow, so this is the row's only expander).
	_hbox().add_child(_flex())
	var mod := _ModuleBtn.new(self)
	mod.name = "CouncilModule"
	mod.tooltip_text = "Council — advisor loyalty"
	mod.custom_minimum_size = Vector2(0, MOD_H)
	var row := _module_row(mod)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 3)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	col.add_child(_tag("Council"))
	_council_status = _mini("", C_MUTED, 12)
	col.add_child(_council_status)
	_council_stack = HBoxContainer.new()
	_council_stack.add_theme_constant_override("separation", 6)
	_council_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_council_stack)
	mod.pressed.connect(func() -> void: _toggle_fly("council"))
	_hbox().add_child(mod)
	_council_btn = mod

func _loyalty_tone(v: float) -> Color:
	if v >= 3.4:
		return _COUNCIL_GOOD
	if v > DISLOYAL_BELOW:
		return _COUNCIL_WARN
	return _COUNCIL_BAD

func _refresh_council() -> void:
	var seated: Array = MatchState.advisor_seats.values()
	var disloyal := 0
	for aid in seated:
		if MatchState.advisor_loyalty_value(str(aid)) <= DISLOYAL_BELOW:
			disloyal += 1
	(_council_btn as _ModuleBtn).warn = disloyal > 0
	if seated.is_empty():
		_council_status.text = "no seats filled"
		_council_status.add_theme_color_override("font_color", C_MUTED)
	elif disloyal > 0:
		_council_status.text = "%d DISLOYAL" % disloyal
		_council_status.add_theme_color_override("font_color", C_RED)
	else:
		_council_status.text = "%d seated" % seated.size()
		_council_status.add_theme_color_override("font_color", C_MUTED)
	for c in _council_stack.get_children():
		c.queue_free()
	for aid in seated:
		_council_stack.add_child(_portrait_chip(str(aid), 36))

## Portrait in a loyalty-toned ring with a number chip bottom-right.
func _portrait_chip(aid: String, size: float) -> Control:
	var v := MatchState.advisor_loyalty_value(aid)
	var tone := _loyalty_tone(v)
	var adv: Dictionary = MatchState.get_advisor(aid)
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(size + 4, size + 4)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.tooltip_text = "%s — %+.1f loyalty" % [str(adv.get("name", aid)), v]
	var ring := PanelContainer.new()
	ring.custom_minimum_size = Vector2(size, size)
	ring.size = Vector2(size, size)
	ring.clip_contents = true
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_TRACK_BG
	sb.border_color = tone
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(int(size / 2.0))
	ring.add_theme_stylebox_override("panel", sb)
	var path := str(adv.get("portrait_path", ""))
	if path != "" and ResourceLoader.exists(path):
		var img := TextureRect.new()
		img.texture = load(path) as Texture2D
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ring.add_child(img)
	else:
		var initials := Label.new()
		initials.text = str(adv.get("initials", "?"))
		initials.add_theme_font_size_override("font_size", int(size * 0.38))
		initials.add_theme_color_override("font_color", adv.get("portrait_color", C_TEXT))
		initials.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		initials.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		ring.add_child(initials)
	holder.add_child(ring)
	var chip := Label.new()
	chip.text = "%+d" % int(round(v))
	chip.add_theme_font_size_override("font_size", 9)
	chip.add_theme_color_override("font_color", tone)
	var csb := StyleBoxFlat.new()
	csb.bg_color = Color("#0a1521")
	csb.border_color = tone
	csb.set_border_width_all(1)
	csb.set_corner_radius_all(6)
	csb.content_margin_left = 3
	csb.content_margin_right = 3
	var chip_holder := PanelContainer.new()
	chip_holder.add_theme_stylebox_override("panel", csb)
	chip_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip_holder.add_child(chip)
	chip_holder.position = Vector2(size - 12, size - 8)
	holder.add_child(chip_holder)
	return holder


# ── 6/7/8 · Encyclopedia (adopted) · Turn/date · Menu ───────────────────────────

## Small open-book vector icon (drawn — the bundled font has no book glyph).
class _BookIcon extends Control:
	var color := Color("#8ea3ba")
	func _init(c: Color) -> void:
		color = c
		custom_minimum_size = Vector2(19, 16)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func set_color(c: Color) -> void:
		color = c
		queue_redraw()
	func _draw() -> void:
		var w := size.x
		var h := size.y
		var cx := w * 0.5
		# Two open pages meeting at a spine, covers dipping at the outer edges.
		var left := PackedVector2Array([
			Vector2(1, 2.5), Vector2(cx - 1, 4.5), Vector2(cx - 1, h - 1.5), Vector2(1, h - 3.5)])
		var right := PackedVector2Array([
			Vector2(w - 1, 2.5), Vector2(cx + 1, 4.5), Vector2(cx + 1, h - 1.5), Vector2(w - 1, h - 3.5)])
		draw_colored_polygon(left, Color(color, 0.20))
		draw_colored_polygon(right, Color(color, 0.20))
		for page: PackedVector2Array in [left, right]:
			var outline: PackedVector2Array = page.duplicate()
			outline.append(page[0])
			draw_polyline(outline, color, 1.2, true)
		draw_line(Vector2(cx, 4.5), Vector2(cx, h - 1.0), color, 1.2, true)
		# A text line on each page.
		draw_line(Vector2(3.5, h * 0.42), Vector2(cx - 3.5, h * 0.5), Color(color, 0.7), 1.0, true)
		draw_line(Vector2(cx + 3.5, h * 0.5), Vector2(w - 3.5, h * 0.42), Color(color, 0.7), 1.0, true)

var _enc_inner: HBoxContainer
var _enc_button: Button

func _adopt_encyclopedia_and_turn() -> void:
	# The scene-authored EncyclopediaButton + TurnCounter live in a right-anchored
	# overlay; adopt them into the module row (scene-unique %names survive reparent,
	# which world_map's @onready refs and the tutorial spotlights rely on).
	var hitbox := get_node_or_null("EncyclopediaHitBox")
	var enc := get_node_or_null("EncyclopediaHitBox/EncyclopediaButton") as Button
	var turn := get_node_or_null("EncyclopediaHitBox/TurnCounter") as Label
	if enc != null:
		enc.reparent(_hbox())
		enc.custom_minimum_size = Vector2(0, MOD_H)
		enc.focus_mode = Control.FOCUS_NONE
		enc.tooltip_text = "Encyclopedia (X)"
		for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
			enc.add_theme_stylebox_override(state, _module_box(state != "normal", false))
		# Book icon + label inside the button (Buttons don't size to child
		# containers — min width is synced in _refresh_treasury's sibling below).
		enc.text = ""
		_enc_inner = HBoxContainer.new()
		_enc_inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_enc_inner.alignment = BoxContainer.ALIGNMENT_CENTER
		_enc_inner.add_theme_constant_override("separation", 8)
		_enc_inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		enc.add_child(_enc_inner)
		var book := _BookIcon.new(Color("#8ea3ba"))
		_enc_inner.add_child(book)
		var lbl := _mini("ENCYCLOPEDIA", Color("#8ea3ba"), 13)
		lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_enc_inner.add_child(lbl)
		enc.mouse_entered.connect(func() -> void:
			book.set_color(C_BRIGHT)
			lbl.add_theme_color_override("font_color", C_BRIGHT))
		enc.mouse_exited.connect(func() -> void:
			book.set_color(Color("#8ea3ba"))
			lbl.add_theme_color_override("font_color", Color("#8ea3ba")))
		enc.add_child(_Sheen.new())   # left→right light, matching the modules
		_enc_button = enc
	_hbox().add_child(_divider())
	if turn != null:
		var col := VBoxContainer.new()
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.add_theme_constant_override("separation", 2)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hbox().add_child(col)
		turn.reparent(col)
		turn.custom_minimum_size = Vector2(0, 0)
		turn.theme_type_variation = "Numeric"
		turn.add_theme_font_size_override("font_size", 16)
		turn.add_theme_color_override("font_color", C_TEXT)
		turn.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_date_label = _mini("", C_MUTED, 12)
		_date_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_date_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(_date_label)
	if hitbox != null:
		hitbox.visible = false

## Turn → month + year (owner 2026-07-10: months not seasons, campaign starts
## January 2015; one month per turn — 300 turns run 2015 → 2039).
const _MONTHS: Array[String] = ["January", "February", "March", "April", "May", "June",
	"July", "August", "September", "October", "November", "December"]

func _turn_date(turn: int) -> String:
	return "%s %d" % [_MONTHS[(turn - 1) % 12], 2015 + (turn - 1) / 12]

func _build_menu() -> void:
	var mod := _ModuleBtn.new(self)
	mod.name = "MenuModule"
	mod.tooltip_text = "Main menu — save, settings, quit"
	mod.custom_minimum_size = Vector2(0, MOD_H)
	var row := _module_row(mod)
	row.add_child(_mini("☰", Color("#8ea3ba"), 19))
	mod.pressed.connect(func() -> void:
		_close_fly()
		PauseMenu.open(get_parent()))
	_hbox().add_child(mod)


# ── Flyouts (Treasury · Council · Victory), anchored under their modules ────────

func _build_fly_layer() -> void:
	_fly_layer = CanvasLayer.new()
	_fly_layer.layer = 110   # under the Turn Briefing hub (120)
	add_child(_fly_layer)
	_fly_scrim = Control.new()
	_fly_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fly_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_fly_scrim.visible = false
	_fly_scrim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			_fly_scrim.accept_event()
			_close_fly())
	_fly_layer.add_child(_fly_scrim)

func _toggle_fly(id: String) -> void:
	if _fly_open_id == id:
		_close_fly()
	else:
		_open_fly(id)

func _close_fly() -> void:
	_fly_open_id = ""
	_fly_scrim.visible = false
	if _fly_panel != null and is_instance_valid(_fly_panel):
		_fly_panel.queue_free()
	_fly_panel = null
	if _victory_btn != null:
		(_victory_btn as _ModuleBtn).active = false
	if _council_btn != null:
		(_council_btn as _ModuleBtn).active = false

func _open_fly(id: String) -> void:
	_close_fly()
	if TurnBriefing.expanded:
		TurnBriefing.collapse()
	_fly_open_id = id
	# Size the scrim to the viewport (Controls under a CanvasLayer get nothing free).
	var vp := get_viewport()
	if vp != null:
		_fly_scrim.size = vp.get_visible_rect().size
		_fly_scrim.position = Vector2.ZERO
	_fly_scrim.visible = true
	_fly_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#0d1e31")
	sb.border_color = C_ACTIVE_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(12)
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = 18
	_fly_panel.add_theme_stylebox_override("panel", sb)
	_fly_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 0)
	_fly_panel.add_child(vb)
	var anchor: Control = money_widget
	match id:
		"treasury":
			# This is the compact money mini-panel. Keep it distinct from the
			# full Money panel, which the buttons below open.
			_fly_panel.custom_minimum_size = Vector2(510, 0)
			vb.add_child(_fly_head("Treasury"))
			_fly_treasury(vb)
			anchor = money_widget
		"victory":
			_fly_panel.custom_minimum_size = Vector2(330, 0)
			vb.add_child(_fly_head("Victory"))
			_fly_victory(vb)
			anchor = _victory_btn
			(_victory_btn as _ModuleBtn).active = true
		"council":
			_fly_panel.custom_minimum_size = Vector2(352, 0)
			vb.add_child(_fly_head("Council"))
			_fly_council(vb)
			anchor = _council_btn
			(_council_btn as _ModuleBtn).active = true
	_fly_layer.add_child(_fly_panel)
	# Position after layout: left-align to the module, clamped to the viewport.
	var place := func() -> void:
		if _fly_panel == null or not is_instance_valid(_fly_panel):
			return
		# CanvasLayer children do not participate in a parent Container layout.
		# Give the mini-panel its measured content height explicitly, otherwise it
		# retains the viewport height and leaves an empty panel below its actions.
		_fly_panel.size = _fly_panel.get_combined_minimum_size()
		var vw := get_viewport().get_visible_rect().size.x
		var x := anchor.global_position.x
		x = clampf(x, 8.0, vw - _fly_panel.size.x - 8.0)
		_fly_panel.global_position = Vector2(x, BAR_H + 8.0)
	place.call_deferred()

func _fly_head(title: String) -> Control:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 14)
	pad.add_theme_constant_override("margin_right", 10)
	pad.add_theme_constant_override("margin_top", 10)
	pad.add_theme_constant_override("margin_bottom", 8)
	var t := Label.new()
	t.theme_type_variation = "Section"
	t.text = title
	head.add_child(t)
	head.add_child(_flex())
	var x := Button.new()
	x.text = "✕"
	x.focus_mode = Control.FOCUS_NONE
	x.add_theme_font_size_override("font_size", 11)
	x.pressed.connect(_close_fly)
	head.add_child(x)
	pad.add_child(head)
	var wrap := VBoxContainer.new()
	wrap.add_child(pad)
	var line := Panel.new()
	line.custom_minimum_size = Vector2(0, 1)
	var lsb := StyleBoxFlat.new()
	lsb.bg_color = C_TRACK_EDGE
	line.add_theme_stylebox_override("panel", lsb)
	wrap.add_child(line)
	return wrap

func _fly_pad(vb: VBoxContainer, sep: int = 7) -> VBoxContainer:
	var pad := MarginContainer.new()
	for m in ["margin_left", "margin_right"]:
		pad.add_theme_constant_override(m, 14)
	pad.add_theme_constant_override("margin_top", 12)
	pad.add_theme_constant_override("margin_bottom", 12)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", sep)
	pad.add_child(inner)
	vb.add_child(pad)
	return inner

func _fly_row(label: String, value: String, tone: Color = C_TEXT, label_tone: Color = Color("#8ea3ba")) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var l := _mini(label, label_tone, 12)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var v := Label.new()
	v.theme_type_variation = "Numeric"
	v.text = value
	v.add_theme_font_size_override("font_size", 12)
	v.add_theme_color_override("font_color", tone)
	row.add_child(v)
	return row

func _fly_sep() -> Control:
	var line := Panel.new()
	line.custom_minimum_size = Vector2(0, 1)
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_TRACK_EDGE
	line.add_theme_stylebox_override("panel", sb)
	return line

func _fly_btn(text: String, primary: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 30)
	# CanvasLayer children do not inherit the viewport theme reliably, so apply
	# the DS theme directly to keep the flyout CTAs in the metal-button family.
	b.theme = DS.theme
	if primary:
		b.theme_type_variation = "Primary"
	return b

# Treasury mini-panel: cash / net / runway, last-turn two-column breakdown,
# loans + capacity, then deep-links into the full Money panel.
func _fly_treasury(vb: VBoxContainer) -> void:
	var inner := _fly_pad(vb)
	var s: Dictionary = Production.last_turn_summary
	var net := float(s.get("money_in", 0.0)) - float(s.get("money_out", 0.0))
	inner.add_child(_fly_row("Cash on hand", _money_text(MatchState.money), C_BRIGHT, C_BRIGHT))
	inner.add_child(_fly_row("Net last turn", _fly_signed_money(net), C_BRIGHT, C_BRIGHT))
	var runway := _runway_turns()
	if runway > 0:
		inner.add_child(_fly_row("Runway at current burn", "≈ %d turns" % runway, C_BRIGHT, C_BRIGHT))
	inner.add_child(_fly_sep())

	# Mirror the expanded turn summary: revenue and outgoings read side by side,
	# using its precise monetary values rather than the top bar's rounded format.
	var revenue := [
		["Goods sold", float(s.get("goods_sales_revenue", 0.0))],
		["Power sold", float(s.get("power_sales_revenue", 0.0))],
		["Green subsidy", float(s.get("green_subsidy_received", 0.0))],
	]
	var operating_costs := float(s.get("maintenance_paid", 0.0)) + float(s.get("labour_paid", 0.0)) + float(s.get("advisor_paid", 0.0))
	var taxes_and_dividends := float(s.get("taxes_paid", 0.0)) + float(s.get("dividends_paid", 0.0))
	var costs := [
		["Operating costs", operating_costs],
		["Power bought", float(s.get("power_purchase_cost", 0.0))],
		["Transport costs", float(s.get("transport_paid", 0.0))],
		["Goods purchased", float(s.get("goods_purchased_cost", 0.0))],
		["Warehousing", float(s.get("warehousing_paid", 0.0))],
		["Interest", float(s.get("interest_paid", 0.0))],
		["Taxes & dividends", taxes_and_dividends],
		["Carbon tax", float(s.get("carbon_tax_paid", 0.0))],
		["Profit sharing", float(s.get("profit_sharing_paid", 0.0))],
	]
	inner.add_child(_fly_money_breakdown(revenue, costs))
	vb.add_child(_fly_sep())
	var loans := _fly_pad(vb, 8)
	var loans_pad := loans.get_parent() as MarginContainer
	loans_pad.add_theme_constant_override("margin_bottom", 20)
	var tag := _fly_money_column_header("Loans")
	loans.add_child(tag)
	for l in LoanState.loans:
		var card := PanelContainer.new()
		var csb := StyleBoxFlat.new()
		csb.bg_color = Color(0.902, 0.702, 0.29, 0.07)
		csb.border_color = Color(0.902, 0.702, 0.29, 0.3)
		csb.set_border_width_all(1)
		csb.set_corner_radius_all(8)
		csb.content_margin_left = 10
		csb.content_margin_right = 10
		csb.content_margin_top = 6
		csb.content_margin_bottom = 6
		card.add_theme_stylebox_override("panel", csb)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var nm := _mini("Loan #%d" % int(l.get("id", 0)), C_BRIGHT, 12)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(nm)
		row.add_child(_mini("%s @ %.0f%%" % [_money_text(float(l.get("principal_remaining", 0.0))), float(l.get("interest_rate", 0.0)) * 100.0], C_BRIGHT, 12))
		card.add_child(row)
		loans.add_child(card)
	if LoanState.loans.is_empty():
		loans.add_child(_mini("No loans outstanding.", C_BRIGHT, 11))
	loans.add_child(_fly_row("Borrowing capacity left", _money_text(LoanState.available_capacity()), C_BRIGHT, C_BRIGHT))
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	var take := _fly_btn("Take loan", true)
	take.name = "FlyTakeLoanButton"   # stable target: the e2e loan flow presses this
	take.pressed.connect(func() -> void:
		_open_money_panel_tab("Loans"))
	actions.add_child(take)
	var balance := _fly_btn("Balance", false)
	balance.name = "FlyBalanceButton"
	balance.pressed.connect(func() -> void:
		_open_money_panel_tab("Balance"))
	actions.add_child(balance)
	var charts := _fly_btn("Charts", false)
	charts.name = "FlyChartsButton"
	charts.pressed.connect(func() -> void:
		_open_money_panel_tab("Charts"))
	actions.add_child(charts)
	loans.add_child(actions)

func _open_money_panel_tab(tab_name: String) -> void:
	_close_fly()
	money_panel_tab_requested.emit(tab_name)

func _fly_money_breakdown(revenue: Array, costs: Array) -> Control:
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 12)
	columns.add_child(_fly_money_column("Revenue", revenue, true))
	var divider := Panel.new()
	divider.custom_minimum_size = Vector2(1, 0)
	var divider_box := StyleBoxFlat.new()
	divider_box.bg_color = C_TRACK_EDGE
	divider.add_theme_stylebox_override("panel", divider_box)
	columns.add_child(divider)
	columns.add_child(_fly_money_column("Costs", costs, false))
	return columns

func _fly_money_column(title: String, entries: Array, is_revenue: bool) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.name = "%sColumn" % title
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 5)
	column.add_child(_fly_money_column_header(title))
	var has_entries := false
	for entry in entries:
		var amount := float(entry[1])
		if amount <= 0.005:
			continue
		has_entries = true
		column.add_child(_fly_money_row(str(entry[0]), amount, is_revenue))
	if not has_entries:
		column.add_child(_mini("None last turn", C_BRIGHT, 11))
	return column

func _fly_money_column_header(text: String) -> Label:
	var header := Label.new()
	header.text = text.to_upper()
	header.theme_type_variation = "Numeric"
	header.add_theme_font_size_override("font_size", 12)
	header.add_theme_color_override("font_color", C_BRIGHT)
	return header

func _fly_money_row(label: String, amount: float, is_revenue: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var name := _mini(label, C_BRIGHT, 11)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(name)
	var value := Label.new()
	value.theme_type_variation = "Numeric"
	value.text = _fly_signed_money(amount if is_revenue else -amount)
	value.add_theme_font_size_override("font_size", 11)
	value.add_theme_color_override("font_color", C_GOOD if is_revenue else C_BAD)
	row.add_child(value)
	return row

func _fly_signed_money(amount: float) -> String:
	return "%s£%.2f" % ["+" if amount >= 0.0 else "−", absf(amount)]

func _runway_turns() -> int:
	var s: Dictionary = Production.last_turn_summary
	var net := float(s.get("money_in", 0.0)) - float(s.get("money_out", 0.0))
	if net >= 0.0 or s.is_empty():
		return 0
	var turns := int(floor((MatchState.money + LoanState.available_capacity()) / -net))
	return turns if turns <= 12 else 0   # only surface when it's actually alarming

# Victory: five labelled progress bars + total, deep-link to the full panel.
func _fly_victory(vb: VBoxContainer) -> void:
	var inner := _fly_pad(vb, 10)
	var bd: Dictionary = VictoryState.get_breakdown()
	for t in (bd.get("tracks", []) as Array):
		var block := VBoxContainer.new()
		block.add_theme_constant_override("separation", 4)
		var head := HBoxContainer.new()
		var nm := _mini(str(t.get("name", "")), C_TEXT, 12)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(nm)
		head.add_child(_mini("%d / %d" % [int(t.get("contribution", 0)), int(t.get("max_score", 1000))], _track_color(t), 11))
		block.add_child(head)
		var meter := Panel.new()
		meter.custom_minimum_size = Vector2(0, 8)
		var msb := StyleBoxFlat.new()
		msb.bg_color = C_TRACK_BG
		msb.border_color = Color("#16273a")
		msb.set_border_width_all(1)
		msb.set_corner_radius_all(4)
		meter.add_theme_stylebox_override("panel", msb)
		var fill := Panel.new()
		var fsb := StyleBoxFlat.new()
		fsb.bg_color = _track_color(t)
		fsb.set_corner_radius_all(3)
		fill.add_theme_stylebox_override("panel", fsb)
		fill.set_anchors_preset(Control.PRESET_LEFT_WIDE)
		fill.offset_top = 1
		fill.offset_bottom = -1
		fill.offset_left = 1
		meter.add_child(fill)
		meter.resized.connect(func() -> void:
			fill.offset_right = -1.0 - (1.0 - clampf(float(t.get("progress", 0.0)), 0.0, 1.0)) * (meter.size.x - 2.0))
		block.add_child(meter)
		inner.add_child(block)
	vb.add_child(_fly_sep())
	var foot := _fly_pad(vb)
	var frow := HBoxContainer.new()
	frow.add_theme_constant_override("separation", 8)
	var total := _mini("Total %s / %s to win" % [_thousands(int(bd.get("total", 0))), _thousands(int(bd.get("win_threshold", 4000)))], C_MUTED, 11)
	total.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frow.add_child(total)
	var full := _fly_btn("Full breakdown", true)
	full.size_flags_horizontal = Control.SIZE_SHRINK_END
	full.pressed.connect(func() -> void:
		_close_fly()
		victory_widget_clicked.emit())
	frow.add_child(full)
	foot.add_child(frow)

# Council: one row per seated advisor (portrait · name/seat · loyalty bar · value).
func _fly_council(vb: VBoxContainer) -> void:
	var inner := _fly_pad(vb, 3)
	var seats: Dictionary = MatchState.advisor_seats
	if seats.is_empty():
		inner.add_child(_mini("No advisors seated — open People to hire.", C_MUTED, 11))
	for seat_id in seats:
		var aid := str(seats[seat_id])
		var v := MatchState.advisor_loyalty_value(aid)
		var tone := _loyalty_tone(v)
		var adv: Dictionary = MatchState.get_advisor(aid)
		var row_btn := _ModuleBtn.new(self)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row_btn.add_child(row)
		row.add_child(_portrait_chip(aid, 30))
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(col)
		col.add_child(_mini(str(adv.get("name", aid)), Color("#eef4fb"), 12))
		col.add_child(_mini(MatchState._seat_display_name(str(seat_id)), C_MUTED, 10))
		var meter := Panel.new()
		meter.custom_minimum_size = Vector2(58, 5)
		meter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var msb := StyleBoxFlat.new()
		msb.bg_color = C_TRACK_BG
		msb.border_color = Color("#16273a")
		msb.set_border_width_all(1)
		msb.set_corner_radius_all(3)
		meter.add_theme_stylebox_override("panel", msb)
		var fill := Panel.new()
		var fsb := StyleBoxFlat.new()
		fsb.bg_color = tone
		fill.add_theme_stylebox_override("panel", fsb)
		fill.set_anchors_preset(Control.PRESET_LEFT_WIDE)
		var frac := clampf((v + 10.0) / 20.0, 0.0, 1.0)
		fill.offset_left = 1
		fill.offset_top = 1
		fill.offset_bottom = -1
		fill.offset_right = -57.0 + 56.0 * frac
		meter.add_child(fill)
		row.add_child(meter)
		var val := _mini("%+.1f" % v, tone, 11)
		row.add_child(val)
		row_btn.pressed.connect(func() -> void:
			_close_fly()
			council_widget_clicked.emit())
		inner.add_child(row_btn)


# ── Coalesced refresh ─────────────────────────────────────────────────────────

func _queue_refresh(_a: Variant = null) -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	call_deferred("_apply_refresh")

func _apply_refresh() -> void:
	_refresh_queued = false
	if not is_inside_tree():
		return
	_refresh_treasury()
	_refresh_power()
	_refresh_victory()
	_refresh_briefing()
	_refresh_council()
	if _date_label != null:
		_date_label.text = _turn_date(int(TurnManager.current_turn))
	if _enc_button != null and _enc_inner != null:
		_enc_button.custom_minimum_size = Vector2(_enc_inner.get_combined_minimum_size().x + 28.0, MOD_H)
	_refresh_bankruptcy_warning()

func _refresh_treasury() -> void:
	_cash_label.text = _money_text(MatchState.money)
	if not _flashing:
		_cash_label.add_theme_color_override("font_color", _base_money_color())
	var s: Dictionary = Production.last_turn_summary
	var net := float(s.get("money_in", 0.0)) - float(s.get("money_out", 0.0))
	_net_label.text = ("+" if net >= 0.0 else "−") + _money_text(absf(net)) + " / turn"
	_net_label.add_theme_color_override("font_color", C_GOOD if net >= 0.0 else C_BAD)
	var runway := _runway_turns()
	_runway_label.visible = runway > 0
	if runway > 0:
		_runway_label.text = "≈%d TURNS" % runway
	# Buttons don't size to non-container children: min width = inner row + padding.
	money_widget.custom_minimum_size = Vector2(_money_inner.get_combined_minimum_size().x + 26.0, MOD_H)

func _refresh_power() -> void:
	var p := _power_stats()
	var starved: bool = int(p.unpowered) > 0
	var gridding: bool = not starved and int(p.grid_draw) > 0
	var c := C_RED if starved else (C_AMBER if gridding else C_GOOD)
	(_power_btn as _ModuleBtn).warn = starved
	_power_glyph.add_theme_color_override("font_color", c)
	_power_head.add_theme_color_override("font_color", c)
	_power_head.text = ("%d unpowered" % int(p.unpowered)) if starved else (("Grid −%d" % int(p.grid_draw)) if gridding else "Powered")
	_power_sub.text = "buildings lack power" if starved else ("all buildings powered" if gridding else "self-sufficient")
	_power_btn.tooltip_text = "Power — %d self-generated%s%s" % [int(p.self_gen),
		(" · %d drawn from grid" % int(p.grid_draw)) if int(p.grid_draw) > 0 else "",
		(" · %d buildings unpowered" % int(p.unpowered)) if starved else ""]


# ── Shared bits kept from v1 (CFO popup · bankruptcy strip · money flash) ───────

func _on_cfo_tax_credit_filed(_amount: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var cfo_id: String = MatchState.get_advisor_in_seat("cfo")
	var cfo: Dictionary = MatchState.get_advisor(cfo_id) if cfo_id != "" else {}
	var popup := CFOIntroPopup.new()
	add_child(popup)
	popup.show_for(cfo, CFO_INTRO_BODY)

# A red "Bankruptcy imminent" strip directly beneath the money widget, matching its
# width. A top_level overlay (NOT a re-parent): the e2e harness drives the loan UI
# through the MoneyWidget's node path, so the top-bar hierarchy must stay put.
func _add_bankruptcy_warning() -> void:
	_bankruptcy_strip = PanelContainer.new()
	_bankruptcy_strip.visible = false
	_bankruptcy_strip.top_level = true
	_bankruptcy_strip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_bankruptcy_strip.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_bankruptcy_strip.accept_event()
			TurnBriefing.expand("alert:bankruptcy"))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.62, 0.16, 0.14, 0.95)
	sb.set_corner_radius_all(4)
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	_bankruptcy_strip.add_theme_stylebox_override("panel", sb)
	var lbl := Label.new()
	lbl.text = "Bankruptcy imminent"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.clip_text = true
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(1, 1, 1))
	_bankruptcy_strip.add_child(lbl)
	add_child(_bankruptcy_strip)
	money_widget.item_rect_changed.connect(_refresh_bankruptcy_warning)

func _refresh_bankruptcy_warning(_ignored: Variant = null) -> void:
	if not is_instance_valid(_bankruptcy_strip):
		return
	var runway: float = MatchState.money + LoanState.available_capacity()
	_bankruptcy_strip.visible = not TurnManager.game_ended and runway < BANKRUPTCY_IMMINENT_RUNWAY
	if _bankruptcy_strip.visible:
		_bankruptcy_strip.global_position = money_widget.global_position + Vector2(0, money_widget.size.y + 2)
		_bankruptcy_strip.custom_minimum_size = Vector2(money_widget.size.x, 0)
		_bankruptcy_strip.size = Vector2(money_widget.size.x, _bankruptcy_strip.get_combined_minimum_size().y)

func _on_money_changed(_new_amount: float) -> void:
	_queue_refresh()

func _on_build_rejected_no_funds(_message: String) -> void:
	flash_red()

func _base_money_color() -> Color:
	var amount: float = MatchState.money
	if amount < 0:
		return FLASH_RED
	elif amount < 10:
		return Color(1.0, 0.6, 0.2)
	return C_BRIGHT

func _set_money_color(c: Color) -> void:
	_cash_label.add_theme_color_override("font_color", c)

func flash_red() -> void:
	if _flashing:
		return
	_flashing = true
	var base := _base_money_color()
	var tween := create_tween()
	tween.tween_method(_set_money_color, base, FLASH_RED, 0.2)
	tween.tween_method(_set_money_color, FLASH_RED, base, 0.2)
	tween.tween_method(_set_money_color, base, FLASH_RED, 0.2)
	tween.tween_method(_set_money_color, FLASH_RED, base, 0.2)
	tween.tween_callback(func() -> void:
		_flashing = false
		_set_money_color(_base_money_color())
	)
