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
# A tile counts as "full" for the transport readout at this share of its capacity —
# 95%% is close enough that the next shipment is the one that gets refused.
const NEAR_FULL_FRACTION := 0.95

# ── Prototype palette (top-bar local; the DS navy family, tuned per the design) ──
# v3 (docs/top-bar-v3-spec.md §1.1): the bar lost its per-module boxes, so the
# padding those boxes needed went with them — 4 top + 38 module + 4 bottom + the
# 7px bezel. Module chrome is flat now; see _module_box.
# v3.1 (owner, 27 Aug): +12px overall, same 4/4/7 budget so MOD_H absorbs all of it —
# content_margin_top/bottom in _style_bar reference BAR_H's own EDGE_H term, not a
# literal number, so nothing else needed to change for the bar to grow around this.
const BAR_H := 65.0
const MOD_H := 50.0
# Briefing notch: taller than the bar, hanging below it as a two-row centre notch.
# Derived from BAR_H rather than fixed — it was authored to drop NOTCH_DROP px past a
# 69px bar, and v3's shorter bar would otherwise leave a notch nearly as deep as the
# bar is tall. NOTCH_DROP also clears the 60px research badge plus its margins.
const NOTCH_DROP := 33.0
const NOTCH_H := BAR_H + NOTCH_DROP
const NOTCH_MIN_W := 300.0
const NOTCH_RADIUS := 16.0
# Research microscope object — the exact art the bottom menu's (alt-mode) Research
# button uses. Composited onto a teal disc + light ring in the briefing notch on
# research-unlock turns, mirroring bottom_menu.ALT_COLORS["TechButton"].
const RESEARCH_ICON: Texture2D = preload("res://assets/icons/ui_icons/alt/research.png")
const RESEARCH_DISC := Color("#1e5e63")   # teal disc  (ALT_COLORS["TechButton"][0])
const RESEARCH_RING := Color("#ddefec")   # light ring (ALT_COLORS["TechButton"][1])
# v3.1 (cheat: `swap topbar v3.1`) — Goods Graph / Encyclopedia / Mission / Power /
# Victory / Rankings swap their text/vector-glyph faces for these baked standalone
# icons: the bottom-menu button treatment (cream emboss + bevel + drop shadow) minus
# the round disc and outer ring, since these sit flat on the bar rather than in a
# socket. Unlike _freight_cell's cleaned building icons, these are NOT modulated at
# display time — they are already coloured to the building-icon off-white and
# re-tinting would pull them off that match.
const ICON_GOODS_GRAPH: Texture2D = preload("res://assets/icons/ui_icons/standalone/sankey.png")
const ICON_ENCYCLOPEDIA: Texture2D = preload("res://assets/icons/ui_icons/standalone/open-book.png")
const ICON_QUEST: Texture2D = preload("res://assets/icons/ui_icons/standalone/target.png")
const ICON_POWER: Texture2D = preload("res://assets/icons/ui_icons/standalone/power_icon.png")
const ICON_VICTORY: Texture2D = preload("res://assets/icons/ui_icons/standalone/trophy.png")
const ICON_RANKINGS: Texture2D = preload("res://assets/icons/ui_icons/standalone/podium.png")
const ICON_BRIEFING_BELL: Texture2D = preload("res://assets/icons/ui_icons/standalone/bell.png")
const ICON_COUNCIL: Texture2D = preload("res://assets/icons/ui_icons/standalone/board-of-directors.png")
const ICON_COIN: Texture2D = preload("res://assets/icons/ui_icons/standalone/coin.png")
const SPECULAR_TEX: Texture2D = preload("res://assets/icons/ui_icons/alt/_specular.png")
# A soft radial burst (bright centre, fades to nothing) — the same "glow behind the
# object" idea as bottom_menu.gd's per-button _glow_<key>.png, just one shared
# generic gradient rather than a shape cut to each icon, since these icons don't
# sit on a disc for a cutout glow to read against.
const GLOW_TEX: Texture2D = preload("res://assets/icons/ui_icons/standalone/_glow.png")
const GLOW_SCALE := 2.0   # glow diameter relative to the icon's own px size
const GLOW_TINT := Color(1.0, 0.92, 0.75, 0.6)
# v3.1 (owner, 27 Aug): grown with MOD_H (38->50px), bottom-aligned in their row
# instead of centred — see _v31_icon — with a fixed gap off the row's bottom edge.
const V31_ICON_PX := 44.0
const V31_ICON_BOTTOM_PAD := 8.0
# The two Briefing bells: 28px original -> +50% (27 Aug) -> +25% again on TOP of
# that (28*1.5*1.25=52.5), per the owner.
const BELL_PX := 52.5
# v3.1: the notch hugs just the bells instead of the classic text's much wider
# NOTCH_MIN_W floor — see _recenter_notch.
const NOTCH_V31_SIDE_PAD := 24.0
# v3.1 notice pills (Briefing): shaped like UIHelpers.make_quantity_pill but with their
# own colour pair per pill — that helper's fixed navy/cream doesn't cover this split.
const PILL_RED_BG := Color("#F2A99C")   # light red — decisions (critical/unskippable)
const PILL_WHITE_BG := Color("#FFFFFF")  # updates (research unlocks etc.)
# Metallic bottom bezel (the end-turn dock's machined-silver family), lit from the left.
const EDGE_H := 7.0
# Pixels the bar's ground is painted ABOVE its top edge, burying the sub-pixel seam
# that non-integer window stretching leaves on the top row (see _style_bar).
const TOP_BLEED := 8.0
const SILVER_LT := Color("#b3bcc6")
const SILVER_MD := Color("#8b95a1")
const SILVER_DK := Color("#5b636e")
const EDGE_SEAM := Color("#3a4048")
const C_BAR_BG := Color("#0c1c2e")
const C_BAR_EDGE := Color("#1c3149")
# Bar ground = the END TURN dock's container navy (BarNavy.TL/TR/BL/BR), stretched
# across the bar's full span instead of the dock's small face (spec §1.4). Both
# surfaces read the same four constants so they can never drift apart.
const BarNavy := preload("res://scripts/bar_navy.gd")
const C_MOD_BG := Color(0.055, 0.125, 0.204, 0.85)     # rgba(14,32,52,.85)
const C_MOD_BORDER := Color("#22384f")
const C_ACTIVE_BG := Color("#15304a")
const C_ACTIVE_BORDER := Color("#2f5578")
const C_WARN_BORDER := Color(0.886, 0.376, 0.29, 0.55) # rgba(226,96,74,.55)
# v3 (spec §1.5): the bar's body text is the SAME off-white the panels use. The old
# #cdd9e6 and the module labels' #8ea3ba both read as grey on this navy — the owner's
# standing rule (ds.gd:50) is that grey never goes on a dark ground. Colour that carries
# MEANING is untouched: good/bad green and red, amber warnings, the cream victory score.
const C_TEXT := Color("#E8EEF7")        # = DS.PALETTE.TEXT
# Resting colour for the icon-and-label modules (Encyclopedia, Goods Graph, Menu).
# They brighten to C_BRIGHT on hover, so the affordance survives the contrast fix.
const C_LABEL := Color("#E8EEF7")
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
var _money_glyph: Label      # the classic "£"
var _money_coin_icon: Control   # v3.1

# Status LEDs (spec §1.3): Treasury / Power / Transport only. Rankings,
# Encyclopedia and the Goods Graph carry none by owner ruling, and Victory /
# Council / Briefing have no defined red condition — a lamp that can never light
# is noise, so those modules simply have none.
var _treasury_led: Control
var _power_led: Control
# v3.1 only — Victory/Rankings have no lamp in the classic bar (no red condition was
# ever defined for either), so these exist only once the icon face is built.
var _victory_led: Control
var _rankings_led: Control

# Power module
var _power_btn: Control
var _power_glyph: Label
var _power_icon: Control   # v3.1
var _power_head: Label
var _power_sub: Label

# Victory module
var _victory_btn: Control
var _victory_glyph: Label
var _victory_icon: Control   # v3.1
var _victory_meters: HBoxContainer
var _quest_btn: Control
var _quest_title: Label
var _quest_sub: Label
var _quest_text_col: VBoxContainer
var _quest_icon: Control   # v3.1
var _quest_shown_before := false    # v3.1 — has the module ever appeared this session
var _quest_v31_wide := false        # v3.1 — currently showing full text (intro / post-completion reveal)
var _quest_v31_animating := false   # v3.1 — a width tween owns _quest_btn.size right now
var _quest_width_anim: Tween
var _victory_score: Label
var _victory_target: Label   # "/ N" — the rising win threshold for the current turn
var _victory_ratio: Label    # v3.1 — replaces the meters + two-line score/target

# Transport module (v3)
var _transport_btn: Control
var _store_led: Control      # tiles refusing goods
var _road_led: Control       # links over capacity
var _port_led: Control       # freight riding to market

# Company rankings module
var _rankings_btn: Control
var _rankings_head: Label
var _rankings_sub: Label
var _rankings_icon: Control   # v3.1

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
var _briefing_icon_v31: HBoxContainer   # v3.1 — the two bells, replaces the head/sub text
var _briefing_decision_pill_slot: Control   # v3.1 — full-rect over the decisions bell
var _briefing_update_pill_slot: Control     # v3.1 — full-rect over the updates bell

# Council module
var _council_btn: Control
var _council_tag: Label
var _council_status: Label
var _council_stack: HBoxContainer
var _council_icon: Control   # v3.1
var _council_led: Control        # v3.1 only — no lamp in the classic bar

# Turn/date
var _date_label: Label

# Flyout layer
var _fly_layer: CanvasLayer
var _fly_scrim: Control
var _fly_panel: PanelContainer
var _fly_open_id := ""
var _rankings_tab := "revenue"

# Coalesced refresh (notification-bell doctrine): sim signals mark dirty; ONE
# deferred refresh per frame updates every module label.
var _refresh_queued := false

# v3.1 (cheat: `swap topbar v3.1`): [classic_node, icon_node] pairs for modules with
# no refresh cycle of their own (Goods Graph, Encyclopedia) — toggled on build and
# again whenever the flag flips. Power/Victory/Rankings/Quest instead toggle inline
# in their own _refresh_* since they already run one every _apply_refresh.
var _v31_pairs: Array[Array] = []


func _ready() -> void:
	# Deferred so the flyout is rebuilt after the turn's numbers have settled, not mid-resolution.
	TurnManager.turn_resolution_completed.connect(func() -> void: _refresh_open_fly.call_deferred())
	_style_bar()
	_build_treasury()
	_build_power()
	_build_victory()
	_build_transport()
	_build_rankings()
	_build_briefing()
	_build_quest()
	_build_council()
	_build_goods_graph()
	_adopt_encyclopedia_and_turn()
	_build_menu()
	_build_fly_layer()
	_add_bankruptcy_warning()

	MatchState.money_changed.connect(_on_money_changed)
	MatchState.build_rejected_no_funds.connect(_on_build_rejected_no_funds)
	MatchState.cfo_tax_credit_filed.connect(_on_cfo_tax_credit_filed)
	MatchState.topbar_v3_1_changed.connect(_on_topbar_v3_1_changed)
	MatchState.advisors_changed.connect(_queue_refresh)
	MatchState.advisor_loyalty_changed.connect(func(_id: String, _v: float) -> void: _queue_refresh())
	Production.turn_processed.connect(func(_s: Dictionary) -> void: _queue_refresh())
	CompanyRankings.rankings_updated.connect(_queue_refresh)
	# A new turn brings a fresh research digest, so the microscope should show again.
	TurnManager.turn_advanced.connect(func(_t: int) -> void:
		_research_seen = false
		_queue_refresh())
	LoanState.loans_updated.connect(_queue_refresh)
	LoanState.loan_taken.connect(_on_loan_taken)
	TurnManager.turn_resolution_completed.connect(_on_turn_resolved_anomalies)
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
	# v3: the ground is PAINTED in _draw (the dock's 4-corner navy, stretched across the
	# bar), so the stylebox carries padding and shadow only — a fill here would sit on top
	# of the gradient and flatten it straight back out.
	#
	# The old opaque fill also bled TOP_BLEED px above y=0 to bury a shimmering 1–3px seam
	# along the very top row (the window is stretched by a non-integer factor — canvas_items
	# + expand, monitor px / 1920×1080 — with pixel-snap off, so the camera nudged that edge
	# sub-pixel every frame). _draw paints the gradient over the same bleed, keeping the fix.
	sb.bg_color = Color(0, 0, 0, 0)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 4   # v3: modules lost their boxes, so they need less room
	sb.content_margin_bottom = 4 + EDGE_H   # keep modules off the metallic rim
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

## The bar's ground colour at canvas x, along its BOTTOM edge — what anything docked
## under the bar must paint itself to continue the gradient rather than interrupt it.
func bar_ground_at(canvas_x: float) -> Color:
	var vw := maxf(1.0, get_viewport_rect().size.x)
	return BarNavy.BL.lerp(BarNavy.BR, clampf(canvas_x / vw, 0.0, 1.0))

## Sample the bar's left→right metal lighting at canvas x (0 = lit, right = shadowed).
func _silver_at(canvas_x: float) -> Color:
	var vw := maxf(1.0, get_viewport_rect().size.x)
	return SILVER_LT.lerp(SILVER_DK, clampf(canvas_x / vw, 0.0, 1.0))

func _draw() -> void:
	var w := size.x
	var y1 := size.y
	var y0 := y1 - EDGE_H
	# GROUND: the END TURN dock's container navy, spread over the bar's full span — the
	# gradient that covers the dock's small face now travels the whole width, so the two
	# surfaces read as one material (spec §1.4). Replaces both the old flat stylebox fill
	# and the ambient left→right sweeps that used to fake its light.
	#
	# Drawn from -TOP_BLEED, not 0: _draw is unclipped (clip_contents is false), so the
	# gradient covers the same few pixels above the bar that the old opaque fill's
	# expand_margin_top did — that bleed is what buries the sub-pixel seam on the top row.
	draw_polygon(
		PackedVector2Array([Vector2(0, -TOP_BLEED), Vector2(w, -TOP_BLEED), Vector2(w, y0), Vector2(0, y0)]),
		BarNavy.corner_colors())
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

## v3: modules are flat text on the bar — no outline, no shading (spec §1.2).
## `active` (an open flyout) keeps a fill so the player can see which module the
## panel belongs to; hover gets a fainter one. The old `warn` red border is gone —
## a module in trouble lights its LED instead (StatusLed, §1.3) — so the argument is
## accepted and ignored, which keeps every existing call site valid.
func _module_box(active: bool, _warn: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_ACTIVE_BG if active else Color(0, 0, 0, 0)
	sb.set_border_width_all(0)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	return sb

## Small uppercase module tag ("COUNCIL").
func _tag(text: String) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_size_override("font_size", 10)
	l.add_theme_color_override("font_color", C_TEXT)
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
	## Optional thin border, re-applied by _restyle so hover cannot wipe it. Transparent (the
	## default) leaves a module exactly as it was.
	var rim := Color(0, 0, 0, 0):
		set(v):
			rim = v
			_restyle()
	## Completion glow, 0–1. Washes the fill brass and lifts a brass shadow — the mission-done
	## flash the owner wants to happen HERE, on the bar, rather than down in the flyout.
	var glow := 0.0:
		set(v):
			glow = v
			_restyle()
	## A checkmark drawn straight onto the module over 0–1, so completion is marked where the
	## player is already looking. It draws only while the label has faded away (see
	## _celebrate_mission), so it has the module to itself rather than sitting over the text.
	var tick_progress := 0.0:
		set(v):
			tick_progress = clampf(v, 0.0, 1.0)
			queue_redraw()
	## The tick is NEGATIVE SPACE: it is drawn in the navy of the bar directly behind the module,
	## so it reads as a checkmark cut out of the brass plate rather than a mark laid on top. The
	## bar sets this to a sample of its own gradient at the module's position.
	var tick_color := Color(0, 0, 0, 0):
		set(v):
			tick_color = v
			queue_redraw()
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
		# Hover on a flat module is a faint wash, not a box: _module_box paints the
		# active fill, and hover borrows it at low opacity.
		var sb: StyleBoxFlat = _bar._module_box(active, warn)
		if _hover and not active:
			sb.bg_color = Color(1, 1, 1, 0.05)
		if rim.a > 0.0:
			sb.border_color = rim
			sb.set_border_width_all(1)
			sb.set_corner_radius_all(8)
		if glow > 0.0:
			var brass: Color = DS.PALETTE.BRASS
			# Near-opaque, so the navy tick punched through it reads as a hole rather than a
			# tint. Alpha climbs fast and caps, so even the trough between flashes stays solid
			# enough for the negative space to hold.
			sb.bg_color = Color(brass.r, brass.g, brass.b, minf(1.0, glow * 1.7))
			sb.shadow_color = Color(brass.r, brass.g, brass.b, 0.6 * glow)
			sb.shadow_size = int(round(16.0 * glow))
			sb.set_corner_radius_all(8)
		add_theme_stylebox_override("panel", sb)
	## The tick, drawn OVER the panel. A PanelContainer paints its stylebox from a C++
	## notification and then still calls this script _draw, so the checkmark lands on top of
	## the brass fill. Drawn in the bar's own navy (tick_color), it reads as a hole cut through
	## the plate to the bar behind — negative space, not a mark laid on.
	##
	## It is a single FILLED outline, not two strokes. Two draw_line segments met at the bottom
	## vertex with square end-caps that left a notch — "two lines that don't quite meet" — so the
	## shape is built as one polygon whose bottom is a short flat edge (owner, 26 Aug). It reveals
	## left to right: x rises monotonically along the stroke, so a vertical wipe reads as drawing.
	func _draw() -> void:
		if tick_progress <= 0.0 or tick_color.a <= 0.0:
			return
		var s: float = minf(size.x, size.y) * 0.72
		var ox: float = (size.x - s) * 0.5
		var oy: float = (size.y - s) * 0.5
		var x0: float = ox + 0.06 * s
		var x1: float = ox + 0.98 * s
		var cut: float = x0 + (x1 - x0) * tick_progress
		var clip := PackedVector2Array([
			Vector2(x0 - s, oy - s), Vector2(cut, oy - s),
			Vector2(cut, oy + 2.0 * s), Vector2(x0 - s, oy + 2.0 * s)])
		# Each piece is convex, so clipping keeps it convex and draw_colored_polygon fills it
		# correctly. The area guard drops the near-zero slivers the wipe front throws off — even
		# draw_colored_polygon triangulates internally and errors on a degenerate one.
		for piece: PackedVector2Array in _tick_pieces(s, ox, oy):
			for shown: PackedVector2Array in Geometry2D.intersect_polygons(piece, clip):
				if shown.size() >= 3 and absf(_poly_area(shown)) >= 0.5:
					draw_colored_polygon(shown, tick_color)

	## The checkmark as three CONVEX pieces that tile it exactly — the two arms and the wedge
	## between them — with a FLAT bottom (bl → br). Two draw_line strokes met at a point whose
	## square end-caps left a notch ("two lines that don't quite meet"); this closes it and the
	## bottom is a short horizontal edge instead of a vanishing point. Centreline a → b → c.
	func _tick_pieces(s: float, ox: float, oy: float) -> Array:
		var a := Vector2(ox + 0.16 * s, oy + 0.52 * s)
		var b := Vector2(ox + 0.44 * s, oy + 0.80 * s)
		var c := Vector2(ox + 0.90 * s, oy + 0.16 * s)
		var half: float = maxf(1.5, s * 0.17) * 0.5
		var d1 := (b - a).normalized()
		var d2 := (c - b).normalized()
		var n1 := Vector2(d1.y, -d1.x)   # up-normal (points to −y)
		var n2 := Vector2(d2.y, -d2.x)
		var a_top := a + n1 * half
		var a_bot := a - n1 * half
		var c_top := c + n2 * half
		var c_bot := c - n2 * half
		var top_v = Geometry2D.line_intersects_line(a_top, d1, c_top, d2)   # inner concave notch
		var bot_v = Geometry2D.line_intersects_line(a_bot, d1, c_bot, d2)   # would-be sharp point
		if not (top_v is Vector2) or not (bot_v is Vector2):
			return []
		# The flat, cut a little above the sharp point, where it crosses each bottom edge.
		var y_flat: float = (bot_v as Vector2).y - half * 0.9
		var bl := a_bot + d1 * ((y_flat - a_bot.y) / d1.y)
		var br := c_bot + d2 * ((y_flat - c_bot.y) / d2.y)
		return [
			PackedVector2Array([a_top, top_v, bl, a_bot]),    # short arm
			PackedVector2Array([top_v, c_top, c_bot, br]),    # long arm
			PackedVector2Array([bl, top_v, br]),              # the wedge, closing the flat bottom
		]

	func _poly_area(poly: PackedVector2Array) -> float:
		var acc := 0.0
		for i in poly.size():
			var p := poly[i]
			var q := poly[(i + 1) % poly.size()]
			acc += p.x * q.y - q.x * p.y
		return acc * 0.5
	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			pressed.emit()

## LED status lamp — a 5px-radius dot with a soft glow, in one of two states only:
## RED (a problem the player should act on) or UNLIT grey. Never a third colour, and
## never amber: the bar's old per-module warn BORDER was removed with the boxes, so
## this lamp is now the whole of a module's alarm vocabulary (spec §1.3).
##
## Drawn rather than textured: concentric alpha circles give a cheap bloom that reads
## as a lit bulb at any DPI, with no shader and no art dependency.
## The lamp lives in scripts/status_led.gd now — the tile-view tabs wanted the same one in
## green and amber, and one implementation cannot drift from itself. The bar's lamps are red,
## which is StatusLed's default.

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


# ── v3.1 (cheat: `swap topbar v3.1`) — shared icon-face helpers ─────────────────

## A compact module-face icon. The baked standalone PNGs already carry their own
## cream fill + bevel + drop shadow, so unlike _freight_cell this does NOT modulate
## them — that would pull them off the building-icon off-white they were colour-
## matched to.
## A v3.1 module-face icon. Bottom-aligned within its row with a fixed gap off the
## row's bottom edge (owner, 27 Aug) rather than vertically centred: the texture is
## pinned to a fixed-height TOP slice of a slightly taller wrapper, and the WRAPPER
## is what bottom-aligns (SIZE_SHRINK_END) — so the icon's own bottom edge ends up
## V31_ICON_BOTTOM_PAD above the row's. .modulate/.visible on the returned Control
## reach the texture underneath (modulate cascades to children), so every existing
## fade/tint/toggle call site keeps working unchanged even though this now returns
## the wrapper, not the TextureRect itself.
## `hover_source` — pass the module button (or whatever Control raises the relevant
## mouse_entered/exited) to get a soft diagonal sheen over the icon on hover: the
## SAME _specular.png the bottom-menu buttons flash while lifted (owner, 27 Aug:
## "more like the bottom bar buttons"). Omit it for icons with no natural hover
## owner to wire against.
func _v31_icon(tex: Texture2D, hover_source: Control = null, px: float = V31_ICON_PX) -> Control:
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(px, px + V31_ICON_BOTTOM_PAD)
	wrap.size_flags_vertical = Control.SIZE_SHRINK_END
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Glow goes in BEHIND the icon (added first — Godot draws children in add
	# order), centred on the icon's own centre (px/2, not the padded wrap's), sized
	# larger so it radiates past the icon's edges instead of being cropped to it.
	var glow: TextureRect = null
	if hover_source != null:
		glow = _v31_glow(px)
		wrap.add_child(glow)
	var icon := TextureRect.new()
	icon.texture = tex
	icon.anchor_left = 0.0
	icon.anchor_right = 1.0
	icon.anchor_top = 0.0
	icon.anchor_bottom = 0.0
	icon.offset_left = 0.0
	icon.offset_right = 0.0
	icon.offset_top = 0.0
	icon.offset_bottom = px
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(icon)
	if hover_source != null:
		var spec := TextureRect.new()
		spec.texture = SPECULAR_TEX
		spec.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		spec.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		spec.stretch_mode = TextureRect.STRETCH_SCALE
		spec.mouse_filter = Control.MOUSE_FILTER_IGNORE
		spec.visible = false
		icon.add_child(spec)
		hover_source.mouse_entered.connect(func() -> void: spec.visible = true; glow.visible = true)
		hover_source.mouse_exited.connect(func() -> void: spec.visible = false; glow.visible = false)
	return wrap

## A radial glow (GLOW_TEX) centred on a px-tall icon slot, sized GLOW_SCALE larger
## than it so it radiates past the icon's own edges — the ADD-blend "glow behind
## the object" bottom_menu.gd's per-button glow does, generalised to a shared
## texture since these icons don't sit on a disc for a shape-cut glow to read
## against. Hidden by default; the caller wires .visible to hover.
func _v31_glow(px: float) -> TextureRect:
	var glow := TextureRect.new()
	glow.texture = GLOW_TEX
	glow.modulate = GLOW_TINT
	var gs := px * GLOW_SCALE
	glow.anchor_left = 0.5
	glow.anchor_right = 0.5
	glow.anchor_top = 0.0
	glow.anchor_bottom = 0.0
	glow.offset_left = -gs / 2.0
	glow.offset_right = gs / 2.0
	glow.offset_top = px / 2.0 - gs / 2.0
	glow.offset_bottom = px / 2.0 + gs / 2.0
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = mat
	glow.visible = false
	return glow

## A small clipped bell (see the single-bell v3.1 comment this superseded — a bare
## TextureRect.size under a non-Container parent kept reverting to the bell's native
## crop) PLUS a full-rect sibling "pill_slot" a caller can anchor a corner badge to —
## same corner-badge shape as _research_pill on _research_badge, just generalised so
## _refresh_briefing can rebuild the badge without touching the bell underneath it.
## `hover_source` — see _v31_icon's own doc — usually the notch, so both bells catch
## the light together on hover.
func _bell_unit(hover_source: Control = null) -> Dictionary:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(BELL_PX, BELL_PX)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Glow is a sibling of `clip`, NOT inside it — clip_contents would crop the
	# glow to the bell's own square instead of letting it radiate past it. Added
	# first so it still draws behind the bell.
	var glow: TextureRect = null
	if hover_source != null:
		glow = _v31_glow(BELL_PX)
		holder.add_child(glow)
	var clip := Control.new()
	clip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(clip)
	var tex := TextureRect.new()
	tex.texture = ICON_BRIEFING_BELL
	tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(tex)
	if hover_source != null:
		var spec := TextureRect.new()
		spec.texture = SPECULAR_TEX
		spec.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		spec.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		spec.stretch_mode = TextureRect.STRETCH_SCALE
		spec.mouse_filter = Control.MOUSE_FILTER_IGNORE
		spec.visible = false
		clip.add_child(spec)
		hover_source.mouse_entered.connect(func() -> void: spec.visible = true; glow.visible = true)
		hover_source.mouse_exited.connect(func() -> void: spec.visible = false; glow.visible = false)
	var pill_slot := Control.new()
	pill_slot.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pill_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(pill_slot)
	return {"root": holder, "pill_slot": pill_slot}

## Anchors `pill` to `host`'s bottom-right corner, overhanging by (pill size − inset) —
## same technique as UIHelpers.make_overlaid_quantity_pill, just for a pill built with
## our own colours (_notice_pill) instead of that helper's fixed navy/cream.
func _overhang_bottom_right(pill: Control, host: Control, inset: float = 4.0) -> void:
	pill.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	var w: float = pill.custom_minimum_size.x
	var h: float = pill.custom_minimum_size.y
	pill.offset_left = -w + inset
	pill.offset_top = -h + inset
	pill.offset_right = inset
	pill.offset_bottom = inset
	host.add_child(pill)

## A small count pill, shaped like UIHelpers.make_quantity_pill (rounded oval capsule,
## sized to its text, centred label) but with its own colour pair — Briefing's decisions/
## updates split needs colours outside that helper's fixed navy-bg/cream-text. Sized to
## match _research_pill (the same corner-badge role, on the research badge) rather than
## make_quantity_pill's own default — that read too tall for a badge this small.
func _notice_pill(text: String, bg: Color, fg: Color) -> PanelContainer:
	var height := 16
	var width: int = maxi(20, text.length() * 8 + 12)
	var pill := PanelContainer.new()
	pill.custom_minimum_size = Vector2(width, height)
	# IGNORE still shows tooltip_text (see _freight_cell's identical pair.tooltip_text
	# + MOUSE_FILTER_IGNORE) while leaving clicks to fall through to the notch button.
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(int(height / 2.0))
	pill.add_theme_stylebox_override("panel", sb)
	var lbl := _mini(text, fg, 13)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(lbl)
	return pill

## Registers a [classic, v3.1] face pair for a module with no refresh cycle of its own
## (Goods Graph, Encyclopedia) and applies the current look immediately.
func _register_v31_pair(classic: Control, v31: Control) -> void:
	_v31_pairs.append([classic, v31])
	_apply_v31_pair(classic, v31)

func _apply_v31_pair(classic: Control, v31: Control) -> void:
	var on: bool = MatchState.use_topbar_v3_1
	classic.visible = not on
	v31.visible = on

## `swap topbar v3.1` flipped. Static modules swap their face pair directly; Quest
## has its own refresh already; everything else re-reads the flag inside the
## coalesced _apply_refresh pass.
func _on_topbar_v3_1_changed(_enabled: bool) -> void:
	for pair: Array in _v31_pairs:
		_apply_v31_pair(pair[0], pair[1])
	_refresh_quest()
	_queue_refresh()


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
	_treasury_led = StatusLed.new()
	_money_inner.add_child(_treasury_led)
	_money_glyph = _mini("£", C_AMBER, 21)
	_money_inner.add_child(_money_glyph)
	_money_coin_icon = _v31_icon(ICON_COIN, money_widget)
	_money_coin_icon.visible = false
	_money_inner.add_child(_money_coin_icon)
	# v3.1: brighten the coin on hover — Treasury never had icon-level hover feedback
	# of its own (only the Button's native stylebox swap), unlike Goods Graph/
	# Encyclopedia's icon+label brighten-on-hover (owner, 27 Aug: "add a hover state").
	money_widget.mouse_entered.connect(func() -> void:
		_money_coin_icon.modulate = Color(1.18, 1.18, 1.05))
	money_widget.mouse_exited.connect(func() -> void:
		_money_coin_icon.modulate = Color.WHITE)
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
	_power_led = StatusLed.new()
	row.add_child(_power_led)
	_power_glyph = _mini("⚡", C_GOOD, 19)
	row.add_child(_power_glyph)
	_power_icon = _v31_icon(ICON_POWER, mod)
	row.add_child(_power_icon)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	_power_head = _mini("Powered", C_GOOD, 15)
	col.add_child(_power_head)
	_power_sub = _mini("self-sufficient", C_TEXT, 12)
	col.add_child(_power_sub)
	_hbox().add_child(mod)
	_power_btn = mod
	# v3.1 (owner, 28 Aug): opens the new Supply Priority flyout instead of
	# jumping straight to the map overlay — matches every other module now
	# (Treasury/Victory/Rankings/Council all open a flyout on click). The old
	# direct behaviour survives as a button inside the flyout, see _fly_power.
	mod.pressed.connect(func() -> void: _toggle_fly("power"))

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
	_victory_led = StatusLed.new()
	row.add_child(_victory_led)
	_victory_led.visible = false   # v3.1 only — see the var's own comment
	_victory_glyph = _mini("★", C_CREAM.darkened(0.15), 16)
	row.add_child(_victory_glyph)
	_victory_icon = _v31_icon(ICON_VICTORY, mod)
	_victory_icon.visible = false
	row.add_child(_victory_icon)
	# v3.1: replaces the meters + two-line score/target with a single "X/Y".
	_victory_ratio = _mini("", C_CREAM, 15)
	_victory_ratio.visible = false
	row.add_child(_victory_ratio)
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
	_victory_score.add_theme_font_size_override("font_size", 15)
	_victory_score.add_theme_color_override("font_color", C_CREAM)
	col.add_child(_victory_score)
	# Second line: the points needed to win. Just the threshold — see below for why there is
	# no turn estimate here.
	_victory_target = _mini("", C_TEXT, 11)
	# Text set on refresh (_victory_bar_tip) — at build time the ruleset has not landed yet,
	# so the bar's shape is not yet known.
	col.add_child(_victory_target)
	mod.pressed.connect(func() -> void: _toggle_fly("victory"))
	_hbox().add_child(mod)
	_victory_btn = mod

func _track_color(entry: Dictionary) -> Color:
	return DS.PALETTE.get(str(entry.get("color_key", "")), C_CREAM)

## v3.1's Victory light: green when MOST tracks have risen against their own recent
## trend (last sample vs ~3 turns back). VictoryState has no "on track to win"
## concept to read instead — the spec's own explicit ruling was "no red condition
## defined" for this module — so this is a momentum read, not a distance-to-bar one
## (owner direction, 26 Aug). No red/amber state: unlit simply means "no clear trend
## yet", not "losing".
func _victory_trending_up(bd: Dictionary) -> bool:
	var tracks: Array = bd.get("tracks", [])
	if tracks.is_empty():
		return false
	var improving := 0
	for t in tracks:
		var trend: Array = (t as Dictionary).get("trend", [])
		if trend.size() < 2:
			continue
		var i_now := trend.size() - 1
		var i_then := maxi(0, i_now - 3)
		if float(trend[i_now]) > float(trend[i_then]):
			improving += 1
	return improving * 2 > tracks.size()


# ── 3b · Transport: what is moving, and what is choking (v3) ──────────────

## The three things that can go wrong with logistics, each with its own lamp: storage
## (tiles refusing goods), infrastructure (links over capacity) and freight (shipments
## stuck with nowhere to unload). Splitting them is the point — the single count this
## replaced read '0 units → market' in any game shipping tile-to-tile, which is most of
## them, so the module spent the early game reporting nothing at all.
##
## The art is the game's OWN icons, run through the same cleaner the Construct menu uses:
## the navy is keyed out, the artwork trimmed and centred, so they sit on the bar as
## off-white shapes on nothing. Roads and the port are building icons; the warehouse has
## no building behind it, so its cleaned PNG is checked in beside the other UI icons.
const BuildingIcon := preload("res://scripts/building_icon.gd")
const WAREHOUSE_ICON: Texture2D = preload("res://assets/icons/ui_icons/warehouse.png")
const FREIGHT_ICON_PX := 38
## Gap between an icon and its own lamp, and between one pair and the next. The pair gap
## is the wider of the two on purpose: it is what makes three icon-and-lamp units read as
## three separate readouts rather than one row of six things.
const FREIGHT_LED_GAP := 4
const FREIGHT_PAIR_GAP := 16

## The cleaned icon for an infrastructure type, by its internal name.
func _infra_texture(internal_name: String) -> Texture2D:
	var building: Dictionary = Catalog.get_building_by_internal_name(internal_name)
	return BuildingIcon.clean_texture(str(building.get("id", "")), internal_name)


## One freight icon with its lamp BESIDE it, as a single pair.
func _freight_cell(texture: Texture2D, tip: String) -> Dictionary:
	var pair := HBoxContainer.new()
	pair.add_theme_constant_override("separation", FREIGHT_LED_GAP)
	pair.alignment = BoxContainer.ALIGNMENT_CENTER
	pair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pair.tooltip_text = tip
	# LED before the icon (owner, 27 Aug) — every other module (Power, Victory,
	# Rankings, Council) leads with its lamp; these three were the one place that
	# read icon-then-LED.
	var led := StatusLed.new()
	pair.add_child(led)
	var icon := TextureRect.new()
	icon.texture = texture
	icon.custom_minimum_size = Vector2(FREIGHT_ICON_PX, FREIGHT_ICON_PX)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The art is cream; the bar's other labels are the off-white, so match them.
	icon.modulate = C_LABEL
	pair.add_child(icon)
	return {"root": pair, "led": led}


func _build_transport() -> void:
	var mod := _ModuleBtn.new(self)
	mod.name = "TransportModule"
	mod.custom_minimum_size = Vector2(0, MOD_H)
	var row := _module_row(mod)
	row.add_theme_constant_override("separation", FREIGHT_PAIR_GAP)
	var store := _freight_cell(WAREHOUSE_ICON, "Storage")
	var road := _freight_cell(_infra_texture("roads"), "Infrastructure")
	var port := _freight_cell(_infra_texture("port"), "Freight to market")
	for cell: Dictionary in [store, road, port]:
		row.add_child(cell.root)
	_store_led = store.led
	_road_led = road.led
	_port_led = port.led
	mod.pressed.connect(func() -> void:
		_close_fly()
		MatchState.transport_panel_requested.emit())
	_hbox().add_child(mod)
	_transport_btn = mod


## Freight headline: units of goods currently riding to MARKET (sale shipments), the
## count of tile-links running over capacity, and tiles at/near their storage cap.
## Every figure is derived from state the sim already keeps — nothing new is simulated.
func _transport_stats() -> Dictionary:
	var to_market := 0
	for s in MatchState.pending_transport_shipments:
		var ship: Dictionary = s
		if not bool(ship.get("is_sale", false)):
			continue
		for it in (ship.get("sale_record", {}) as Dictionary).get("items", []):
			to_market += int((it as Dictionary).get("qty", 0))
	var over := MatchState.congested_links().size()
	var full := 0
	var rejecting := 0
	for tile_key in Stockpile.tiles_with_stock():
		var cap := float(Stockpile.get_capacity(tile_key))
		if cap <= 0.0:
			continue
		if float(Stockpile.get_used_capacity(tile_key)) / cap >= NEAR_FULL_FRACTION:
			full += 1
		if Stockpile.get_refused(tile_key) > 0:
			rejecting += 1
	return {"to_market": to_market, "over": over, "full": full, "rejecting": rejecting}

func _refresh_transport() -> void:
	if _transport_btn == null:
		return
	var t := _transport_stats()
	# Each lamp owns one failure. Splitting them is the point: the single count this
	# replaced read '0 units → market' in any game shipping tile-to-tile, which is most of
	# them, so the module spent the early game reporting nothing at all.
	(_store_led as StatusLed).lit = int(t.rejecting) > 0 or int(t.full) > 1
	(_road_led as StatusLed).lit = int(t.over) > 3
	# Freight that arrived somewhere with no room and is stuck waiting for space. It is the
	# one thing that can go wrong with a shipment AFTER it set off, so it is what the port
	# lamp watches rather than the healthy count of goods in motion.
	(_port_led as StatusLed).lit = MatchState.overflow_shipments.size() > 0
	_transport_btn.tooltip_text = "Transport — %d tile%s at 95%%+ storage (%d refusing), %d link%s over capacity, %s unit%s riding to market" % [
		int(t.full), "" if int(t.full) == 1 else "s", int(t.rejecting),
		int(t.over), "" if int(t.over) == 1 else "s",
		_thousands(int(t.to_market)), "" if int(t.to_market) == 1 else "s"]
	if MatchState.overflow_shipments.size() > 0:
		_transport_btn.tooltip_text += "
%d shipment(s) stuck with nowhere to unload" % MatchState.overflow_shipments.size()


# ── 4 · Rankings: player position in the cosmetic company league ────────────

func _build_rankings() -> void:
	var mod := _ModuleBtn.new(self)
	mod.name = "RankingsModule"
	mod.tooltip_text = "Company rankings — league position and the goods you lead"
	mod.custom_minimum_size = Vector2(0, MOD_H)
	var row := _module_row(mod)
	# Classic: no leading glyph — the head line carries its own movement arrow, and a
	# second static triangle beside it read as a claim about the goods line
	# underneath. v3.1 trades the text-only face for the podium icon, so that
	# objection no longer applies: the icon reads as "rankings", not as a second
	# movement claim.
	_rankings_led = StatusLed.new()
	_rankings_led.visible = false   # v3.1 only — no lamp in the classic bar
	row.add_child(_rankings_led)
	_rankings_icon = _v31_icon(ICON_RANKINGS, mod)
	_rankings_icon.visible = false
	row.add_child(_rankings_icon)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	# Two lines only (v3): the "RANKINGS" tag row went with the module boxes.
	_rankings_head = _mini("10TH OF 10", C_BRIGHT, 14)
	col.add_child(_rankings_head)
	_rankings_sub = _mini("", DS.PALETTE.TEXT, 11)
	col.add_child(_rankings_sub)
	mod.pressed.connect(func() -> void: _toggle_fly("rankings"))
	_hbox().add_child(mod)
	_rankings_btn = mod

func _refresh_rankings() -> void:
	if _rankings_head == null:
		return
	var rows: Array[Dictionary] = CompanyRankings.standings()
	for row: Dictionary in rows:
		if not bool(row.get("is_player", false)):
			continue
		var movement: int = int(row.get("rank_change", 0))
		var rank: int = int(row.get("rank", 10))
		var v31: bool = MatchState.use_topbar_v3_1
		if v31:
			# v3.1: position only — no movement arrow (nothing else on the face carries
			# a movement claim any more) and no "OF N".
			_rankings_head.text = _ordinal(rank)
			_rankings_head.add_theme_color_override("font_color", C_BRIGHT)
		else:
			_rankings_head.text = "%s %s OF %d" % [_ranking_arrow(movement), _ordinal(rank), rows.size()]
			_rankings_head.add_theme_color_override("font_color", C_GOOD if movement > 0 else (C_BAD if movement < 0 else C_BRIGHT))
		# The sub-line answers "am I winning at anything?", which a revenue total never
		# did — it counts the goods where the player outproduces all nine rivals.
		var led := _goods_led_count()
		_rankings_sub.text = "%d good%s you lead in" % [led, "" if led == 1 else "s"]
		_rankings_sub.visible = not v31
		_rankings_icon.visible = v31
		if _rankings_led != null:
			# v3.1: green only outright leading the league — 2nd of 10 is not "bad", so
			# unlit rather than amber/red for anything short of #1.
			_rankings_led.visible = v31
			(_rankings_led as StatusLed).lit = rank == 1
		return

## Goods where the player outproduces every rival. goods_standings() returns one row
## per GOOD, each carrying a nested `producers` league — the player is one entry in it.
##
## Zero output never counts as leading. Apex goods have no rivals generated at all, so
## the player is trivially rank 1 on every one of them; without the quantity test the
## bar would boast about goods the player has never made a single unit of.
func _goods_led_count() -> int:
	var led := 0
	for good: Dictionary in CompanyRankings.goods_standings():
		for producer: Dictionary in (good.get("producers", []) as Array):
			if not bool(producer.get("is_player", false)):
				continue
			if int(producer.get("rank", 0)) == 1 and int(producer.get("quantity", 0)) > 0:
				led += 1
			break
	return led

func _ranking_arrow(change: int) -> String:
	if change > 0:
		return "▲"
	if change < 0:
		return "▼"
	return "—"

func _ordinal(value: int) -> String:
	var suffix := "th"
	if value % 100 < 11 or value % 100 > 13:
		match value % 10:
			1: suffix = "st"
			2: suffix = "nd"
			3: suffix = "rd"
	return "%d%s" % [value, suffix]

## queue_free() is DEFERRED: the old children live until the end of the frame while the new ones
## are added immediately, so for one frame the container holds BOTH sets and the HBox lays out
## double the widgets — which is the flicker. remove_child() first takes them out of the layout
## in the same frame. (Same pattern advisor_council_tab._rebuild already uses.)
func _clear_now(container: Node) -> void:
	for c in container.get_children():
		container.remove_child(c)
		c.queue_free()


func _refresh_victory() -> void:
	var bd: Dictionary = VictoryState.get_breakdown()
	_clear_now(_victory_meters)
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
		var letter := _mini(str(t.get("name", "?")).substr(0, 1), C_TEXT, 9)
		letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		letter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_child(letter)
		_victory_meters.add_child(cell)
	var total := int(bd.get("total", 0))
	_victory_score.text = "%s Victory Point%s" % [_thousands(total), "" if total == 1 else "s"]
	if _victory_target != null:
		_victory_target.text = "of %s to win" % _thousands(int(bd.get("win_threshold", 4000)))
		_victory_target.tooltip_text = _victory_bar_tip(bd)
	var v31: bool = MatchState.use_topbar_v3_1
	_victory_glyph.visible = not v31
	_victory_icon.visible = v31
	_victory_meters.visible = not v31
	(_victory_score.get_parent() as Control).visible = not v31
	_victory_ratio.visible = v31
	if v31:
		_victory_ratio.text = "%s/%s" % [_thousands(total), _thousands(int(bd.get("win_threshold", 4000)))]
		_victory_ratio.tooltip_text = _victory_bar_tip(bd)
	if _victory_led != null:
		_victory_led.visible = v31
		(_victory_led as StatusLed).lit = _victory_trending_up(bd)

## What the win bar does, in one line. A campaign bar climbs with the turn; the demo's is
## flat, and a demo player told to hold out for turn 300 has been told something false.
func _victory_bar_tip(bd: Dictionary) -> String:
	var max_turns := int(bd.get("max_turns", 300))
	if VictoryState.win_threshold_for_turn(1) == VictoryState.win_threshold_for_turn(max_turns):
		return "%s points wins, on any turn — the bar does not rise." % _thousands(
			int(bd.get("win_threshold", 0)))
	return "Points needed to win rise over the game — 1 track from turn %d up to 4 tracks by turn %d." % [
		VictoryState.WIN_START_TURN, max_turns]

## NO TURN FORECAST HERE, DELIBERATELY (owner, 25 Aug). The module used to extrapolate a
## points-per-turn rate from the last six resolved turns and print "N turns until victory".
## Victory has no rate of its own — the tracks report where they ARE, not how fast they are
## moving — so the estimate was a straight-line guess over a curve, and the win threshold
## itself RISES with the turn (see _victory_bar_tip), which the extrapolation never modelled.
## It read as a promise and was routinely wrong. The second line now states the threshold and
## nothing else; the score above it is the progress. Do not reintroduce an ETA without a real
## model of the tracks.


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
		# Match the bar's ground where the notch meets it: the bar is a gradient now, so a
		# flat fill read as a darker slab bolted on. Sampled at the notch's own centre, the
		# notch simply looks like the bar bulging downward.
		sb.bg_color = _bar.C_ACTIVE_BG if (active or _hover) else _bar.bar_ground_at(
			global_position.x + size.x * 0.5)
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
	_briefing_sub = _mini("0 updates", C_TEXT, 14)
	col.add_child(_briefing_sub)
	# v3.1: TWO bells — one for decisions, one for updates — each with its own count
	# pill overhanging its bottom-right corner (same corner-badge technique as
	# _research_pill on _research_badge above, and UIHelpers.make_overlaid_quantity_pill
	# elsewhere). Replaces the head/sub text entirely; each pill is rebuilt on refresh,
	# same idiom as _victory_meters/_council_stack.
	_briefing_icon_v31 = HBoxContainer.new()
	_briefing_icon_v31.add_theme_constant_override("separation", 10)
	_briefing_icon_v31.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_briefing_icon_v31.visible = false
	# top_level + manually centred on the notch's own midline, in _place_briefing_bells
	# (owner, 27 Aug): as an ordinary `row` child it centred as a GROUP together with
	# the research badge, so the bells visibly shifted right whenever the badge
	# showed. Independent placement keeps them on the notch's axis regardless.
	_briefing_icon_v31.top_level = true
	var decision_bell := _bell_unit(notch)
	_briefing_icon_v31.add_child(decision_bell.root)
	_briefing_decision_pill_slot = decision_bell.pill_slot
	var update_bell := _bell_unit(notch)
	_briefing_icon_v31.add_child(update_bell.root)
	_briefing_update_pill_slot = update_bell.pill_slot
	notch.add_child(_briefing_icon_v31)
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
	# v3.1: nothing left in `row` to show but the (optional) research badge — the
	# bells are top_level now, so they don't feed row's content width — so the
	# classic text's much wider NOTCH_MIN_W floor would leave the bells looking
	# lost in a wide box. Hug the bells instead.
	#
	# custom_minimum_size was set ONCE at build time to NOTCH_MIN_W (_build_briefing),
	# and get_combined_minimum_size() always returns at least custom_minimum_size —
	# so reading it BEFORE overriding that here always floored min_size.x at the
	# classic 300, silently no-opping any narrower v3.1 floor_w below. Override
	# custom_minimum_size.x first so the read afterwards actually reflects it.
	var floor_w := NOTCH_MIN_W
	if MatchState.use_topbar_v3_1 and _briefing_icon_v31 != null and is_instance_valid(_briefing_icon_v31):
		floor_w = _briefing_icon_v31.get_combined_minimum_size().x + NOTCH_V31_SIDE_PAD * 2.0
	_briefing_btn.custom_minimum_size.x = floor_w
	# maxf against the (now correctly floored) min_size still lets real content —
	# the research badge, or classic text — widen the notch past floor_w when shown.
	var min_size := _briefing_btn.get_combined_minimum_size()
	_briefing_btn.size = Vector2(maxf(min_size.x, floor_w), NOTCH_H)
	_briefing_btn.position = Vector2(roundf((vw - _briefing_btn.size.x) * 0.5), 0.0)
	_place_quest()
	_place_briefing_bells()
	queue_redraw()

## v3.1: keeps the two bells centred on the notch's own midline regardless of
## whether the research badge is showing beside them — see the top_level comment
## where _briefing_icon_v31 is built.
func _place_briefing_bells() -> void:
	if _briefing_icon_v31 == null or not is_instance_valid(_briefing_icon_v31):
		return
	if _briefing_btn == null or not is_instance_valid(_briefing_btn):
		return
	var want := _briefing_icon_v31.get_combined_minimum_size()
	_briefing_icon_v31.size = want
	_briefing_icon_v31.position = Vector2(
		_briefing_btn.position.x + (_briefing_btn.size.x - want.x) * 0.5,
		_briefing_btn.position.y + (_briefing_btn.size.y - want.y) * 0.5)

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
	_briefing_sub.add_theme_color_override("font_color", C_TEXT)
	var v31: bool = MatchState.use_topbar_v3_1
	_briefing_dot.visible = decisions + updates > 0 and not v31
	var dsb := _briefing_dot.get_theme_stylebox("panel") as StyleBoxFlat
	if dsb != null:
		dsb.bg_color = C_RED if hot else C_AMBER
	_briefing_glyph.visible = not v31
	_briefing_icon_v31.visible = v31
	(_briefing_head.get_parent() as Control).visible = not v31
	if v31:
		# v3.1: no "Briefing"/"update" words — two bells instead, each carrying its own
		# count badge: light-red/black for decisions (critical/unskippable — the same
		# count the classic head goes red for), white/black for updates (tech unlocks
		# etc.). Rebuilt each refresh like _victory_meters/_council_stack — clearing
		# just the pill_slot, never the bell itself.
		_clear_now(_briefing_decision_pill_slot)
		var decision_pill := _notice_pill(str(decisions), PILL_RED_BG, Color.BLACK)
		decision_pill.tooltip_text = "Decisions to make"
		_overhang_bottom_right(decision_pill, _briefing_decision_pill_slot)
		_clear_now(_briefing_update_pill_slot)
		var update_pill := _notice_pill(str(updates), PILL_WHITE_BG, Color.BLACK)
		update_pill.tooltip_text = "Updates"
		_overhang_bottom_right(update_pill, _briefing_update_pill_slot)
	call_deferred("_recenter_notch")


# ── 5 · Council: seated portraits with loyalty rings + number chips ─────────────

## The post-tutorial mini quest (scripts/mini_quest.gd). Sits immediately right of the updates
## notch: the hbox separation is 10, which is the offset asked for, so it needs no spacer.
## Hidden until MiniQuest says there is a quest — that wants a finished tutorial AND a chain the
## player has actually gone into.
func _build_quest() -> void:
	var mod := _ModuleBtn.new(self)
	mod.name = "QuestModule"
	mod.tooltip_text = "Mini quest"
	# The thin gold rim is what marks this out from its neighbours: every other module on the
	# bar is bare or silver-edged, so the rim does the work a badge would.
	mod.rim = _quest_rim()
	# v3.1: the collapse-to-icon animation shrinks mod.size.x with the full-width text
	# still visible underneath (see _quest_v31_collapse_to_icon) — clip so the text
	# is cropped by the shrinking edge instead of overflowing it.
	mod.clip_contents = true
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 12)
	pad.add_theme_constant_override("margin_right", 12)
	pad.add_theme_constant_override("margin_top", 6)
	pad.add_theme_constant_override("margin_bottom", 6)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mod.add_child(pad)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(col)
	_quest_title = _mini("", C_CREAM, 13)
	col.add_child(_quest_title)
	_quest_sub = _mini("", C_TEXT, 11)
	col.add_child(_quest_sub)
	# The whole text block, kept so the completion flash can fade it away and the tick can take
	# the module to itself. Fading modulate (not visibility) leaves the layout — and so the
	# module's width — untouched while the label is gone.
	_quest_text_col = col
	# v3.1: icon-only face, a sibling of the text column inside the same pad — hiding
	# one and showing the other is what gives the module its "narrower" v3.1 shape
	# (MarginContainer excludes invisible children from its own minimum size), and
	# the tick/glow celebration keeps working unchanged since it is drawn on the
	# _ModuleBtn itself, not on whichever content sits inside it.
	_quest_icon = _v31_icon(ICON_QUEST, mod)
	_quest_icon.visible = false
	pad.add_child(_quest_icon)
	mod.pressed.connect(func() -> void: _toggle_fly("quest"))
	# TOP-LEVEL, like the briefing notch and the bankruptcy strip. The bar is a PanelContainer:
	# an ordinary child is both stretched to fill it AND counted in its minimum size, and measured
	# that took the bar from 64 px tall to 67. Containers skip a top_level child, which fixes the
	# growth and removes any need to re-place it after every sort.
	mod.top_level = true
	add_child(mod)
	_quest_btn = mod
	mod.visible = false
	MiniQuest.quest_changed.connect(_refresh_quest)
	MiniQuest.mission_completed.connect(_on_quest_mission_completed)
	# Refresh when the match snapshot lands: that is the first moment the ruleset (and its
	# start_id) exists, and is_available() resolves a start-derived chain from it. Connecting
	# HERE — on the bar, not only in MiniQuest — sidesteps a boot race: match_loaded fires during
	# world build, after this bar's _ready, whereas MiniQuest is a deferred autoload that on a
	# fast boot can still be wiring up. Without it the module first appeared on turn 2, because
	# TurnManager emits turn 1's DECIDE before the ruleset is even loaded, so that nudge is lost.
	SaveLoad.match_loaded.connect(_refresh_quest)
	get_viewport().size_changed.connect(_place_quest)
	_refresh_quest()


## The module's resting rim. Not a const: Color.darkened() is a method call, so it cannot be
## folded at parse time.
func _quest_rim() -> Color:
	return C_CREAM.darkened(0.15)


## A mission landed. The toast MiniQuest raises says WHAT happened; the module — flashing up on
## the bar — says where. See _celebrate_mission for the sequence itself.
func _on_quest_mission_completed(kind: String, _mission_title: String, _reward: String) -> void:
	_refresh_quest()   # the module may only now be earning its place on the bar
	if _quest_btn == null or not is_instance_valid(_quest_btn) or not _quest_btn.visible:
		return
	_celebrate_mission(kind)


## Ten pixels off the notch's right edge, vertically centred in the bar proper (the notch hangs
## below it; the quest does not). Re-run whenever the notch moves or the label changes, since
## both change the rect this is measured against.
const QUEST_GAP := 10.0

## Both this and the notch are top_level, so their positions live in the same space and the
## container will not touch either. Centred in what the bar actually DRAWS — its live height
## less the metallic bezel along the bottom — rather than in BAR_H, which is the offset the bar
## is anchored by and is smaller than the height its styleboxes give it (53 vs a measured 64).
func _place_quest() -> void:
	if _quest_btn == null or not is_instance_valid(_quest_btn) or not _quest_btn.visible:
		return
	if _briefing_btn == null or not is_instance_valid(_briefing_btn):
		return
	if _quest_v31_animating:
		return   # a width tween owns .size right now (see _quest_v31_collapse_to_icon)
	var want_size := _quest_btn.get_combined_minimum_size()
	_quest_btn.size = want_size
	_quest_btn.position = Vector2(
		_briefing_btn.position.x + _briefing_btn.size.x + QUEST_GAP,
		maxf(0.0, roundf((size.y - EDGE_H - want_size.y) * 0.5)))


## Text and visibility both come from MiniQuest; the bar never decides either for itself.
func _refresh_quest() -> void:
	if _quest_btn == null or not is_instance_valid(_quest_btn):
		return
	var on: bool = MiniQuest.is_available()
	# v3.1: the FIRST turn the module has anything to show at all — game start, or the
	# tutorial finishing and handing off to a real mission — gets the intro reveal
	# (owner, 27 Aug). Latched once per session; never replayed for a later cheat toggle.
	var just_appeared := on and not _quest_shown_before
	_quest_shown_before = _quest_shown_before or on
	_quest_btn.visible = on
	if not on:
		if _fly_open_id == "quest":
			_close_fly()
		return
	# Recover the label's opacity outside a celebration: if one was interrupted (a state reset
	# mid-flash) the fade could otherwise leave the module reading blank.
	if not _quest_celebrating and _quest_text_col != null and is_instance_valid(_quest_text_col):
		_quest_text_col.modulate.a = 1.0
	# MiniQuest decides which of its missions is showing; the bar just renders it — EXCEPT
	# during the completion sequence, which holds the module on the mission that just finished
	# (reading "Complete — <reward>") until the flash is over and it hands over deliberately.
	var kind: String = _quest_celebrating_kind if _quest_celebrating else MiniQuest.active_mission()
	_quest_title.text = MiniQuest.title(kind)
	_quest_sub.text = MiniQuest.subtitle(kind)
	var v31: bool = MatchState.use_topbar_v3_1
	# The tooltip carries the mission text once the label itself is hidden (mirrors
	# the Transport module's icon+LED-with-tooltip pattern).
	_quest_btn.tooltip_text = ("%s — %s" % [_quest_title.text, _quest_sub.text]) if v31 else "Mini quest"
	if not v31:
		_quest_text_col.visible = true
		if _quest_icon != null:
			_quest_icon.visible = false
	elif not _quest_celebrating and not _quest_v31_animating:
		# Steady v3.1 state: an active animation (intro / celebration handoff) owns the
		# text/icon visibility itself and must not be stomped by an unrelated refresh
		# landing mid-sequence (money changing, a turn advancing, etc).
		if just_appeared:
			_quest_v31_reveal_then_collapse()
		elif not _quest_v31_wide:
			_quest_text_col.visible = false
			if _quest_icon != null:
				_quest_icon.visible = true
	if not _quest_v31_animating:
		_place_quest.call_deferred()   # the new label/icon decides the width
	if _fly_open_id == "quest" and not _quest_celebrating:
		_refresh_open_fly()


## v3.1: show the full mission text immediately (no reveal animation of its own —
## there's nothing to reveal FROM the first time, and after a celebration the gold
## icon already carried that beat), hold it, then collapse to the icon. Used both
## for the mission's first appearance and for the mission a completion hands off to.
func _quest_v31_reveal_then_collapse() -> void:
	if _quest_btn == null or not is_instance_valid(_quest_btn):
		return
	var mod := _quest_btn as _ModuleBtn
	_quest_icon.visible = false
	_quest_icon.modulate = Color.WHITE
	_quest_text_col.visible = true
	_quest_text_col.modulate.a = 1.0
	_quest_v31_wide = true
	_quest_v31_animating = false
	var want: float = _quest_text_col.get_combined_minimum_size().x + 24.0   # pad's L/R margins
	mod.size.x = want
	_place_quest.call_deferred()
	# Only collapse if we're still resting on the mission this was raised for — a real
	# completion landing mid-hold replaces this with its own sequence instead.
	var expected_kind := (_quest_celebrating_kind if _quest_celebrating else MiniQuest.active_mission())
	get_tree().create_timer(QUEST_V31_HOLD_SEC).timeout.connect(func() -> void:
		if MatchState.use_topbar_v3_1 and not _quest_celebrating \
				and MiniQuest.active_mission() == expected_kind:
			_quest_v31_collapse_to_icon())


## v3.1: animate the module's width down from the full text to the icon's, text
## clipped by the shrinking edge (mod.clip_contents, set in _build_quest), then swap
## to the icon once the tween lands — swapping earlier would show the icon stretched
## to fill the still-wide rect for the last stretch of the shrink.
func _quest_v31_collapse_to_icon() -> void:
	if _quest_btn == null or not is_instance_valid(_quest_btn):
		return
	var mod := _quest_btn as _ModuleBtn
	var icon_w: float = _quest_icon.get_combined_minimum_size().x + 24.0
	if _quest_width_anim != null and _quest_width_anim.is_valid():
		_quest_width_anim.kill()
	_quest_v31_animating = true
	_quest_width_anim = create_tween()
	_quest_width_anim.tween_property(mod, "size:x", icon_w, QUEST_V31_COLLAPSE_SEC)
	_quest_width_anim.tween_callback(func() -> void:
		_quest_text_col.visible = false
		_quest_icon.visible = true
		_quest_icon.modulate = Color.WHITE
		_quest_v31_wide = false
		_quest_v31_animating = false
		_place_quest.call_deferred())


func _build_council() -> void:
	# Everything from Council rightwards is anchored to the far right edge (the
	# briefing notch is out of the flow, so this is the row's only expander).
	_hbox().add_child(_flex())
	var mod := _ModuleBtn.new(self)
	mod.name = "CouncilModule"
	mod.tooltip_text = "Council — advisor loyalty"
	mod.custom_minimum_size = Vector2(0, MOD_H)
	var row := _module_row(mod)
	_council_led = StatusLed.new()
	_council_led.visible = false   # v3.1 only — no lamp in the classic bar
	row.add_child(_council_led)
	_council_icon = _v31_icon(ICON_COUNCIL, mod)
	_council_icon.visible = false
	row.add_child(_council_icon)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 3)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	_council_tag = _tag("Council")
	col.add_child(_council_tag)
	_council_status = _mini("", C_TEXT, 12)
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
	var min_loyalty := 999.0
	for aid in seated:
		var lv: float = MatchState.advisor_loyalty_value(str(aid))
		if lv <= DISLOYAL_BELOW:
			disloyal += 1
		min_loyalty = minf(min_loyalty, lv)
	(_council_btn as _ModuleBtn).warn = disloyal > 0
	if seated.is_empty():
		_council_status.text = "no seats filled"
		_council_status.add_theme_color_override("font_color", C_TEXT)
	elif disloyal > 0:
		_council_status.text = "%d DISLOYAL" % disloyal
		_council_status.add_theme_color_override("font_color", C_RED)
	else:
		_council_status.text = "%d seated" % seated.size()
		_council_status.add_theme_color_override("font_color", C_TEXT)
	_clear_now(_council_stack)
	for aid in seated:
		_council_stack.add_child(_portrait_chip(str(aid), 36))
	var v31: bool = MatchState.use_topbar_v3_1
	# v3.1: icon + light only — the tag/status text and the portrait stack both go,
	# with the status line folded into the tooltip instead.
	(_council_tag.get_parent() as Control).visible = not v31
	_council_stack.visible = not v31
	_council_icon.visible = v31
	_council_btn.tooltip_text = ("Council — %s" % _council_status.text) if v31 else "Council — advisor loyalty"
	if _council_led != null:
		_council_led.visible = v31
		var led := _council_led as StatusLed
		led.blink = false
		led.lit = true
		# v3.1's own thresholds — separate from the classic DISLOYAL_BELOW (-3.4) the
		# status text/warn tint use above. An empty seat list leaves min_loyalty at
		# its sentinel, which clears both checks below and reads green — no seats
		# filled is not a problem.
		if min_loyalty < -5.0:
			led.color = C_RED
		elif min_loyalty < 0.0:
			led.color = C_AMBER
		else:
			led.color = C_GOOD

## A portrait clipped to an ACTUAL circle, in a loyalty-toned ring, with a number chip
## bottom-right. clip_contents only ever clips to the RECT, so the round ring used to hold
## a square portrait — the mask has to BE the drawing, which is what the UV'd circle below
## is: one polygon, the portrait mapped across it, no shader and no render target.
class _PortraitCircle extends Control:
	const SEGMENTS := 48
	var texture: Texture2D = null
	var ring := Color.WHITE
	func _init(px: float) -> void:
		custom_minimum_size = Vector2(px, px)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var r: float = minf(size.x, size.y) * 0.5
		var c: Vector2 = size * 0.5
		if texture != null:
			var pts := PackedVector2Array()
			var uvs := PackedVector2Array()
			for i in SEGMENTS:
				var a := TAU * float(i) / float(SEGMENTS)
				var dir := Vector2(cos(a), sin(a))
				pts.append(c + dir * (r - 1.0))
				# The art is square, so the circle samples the middle of it.
				uvs.append(Vector2(0.5, 0.5) + dir * 0.5)
			draw_colored_polygon(pts, Color.WHITE, uvs, texture)
		else:
			draw_circle(c, r - 1.0, Color("#0a1623"))
		draw_arc(c, r - 1.0, 0.0, TAU, SEGMENTS, ring, 2.0, true)

func _portrait_chip(aid: String, size: float) -> Control:
	var v := MatchState.advisor_loyalty_value(aid)
	var tone := _loyalty_tone(v)
	var adv: Dictionary = MatchState.get_advisor(aid)
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(size + 4, size + 4)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.tooltip_text = "%s — %+.1f loyalty" % [str(adv.get("name", aid)), v]
	var circle := _PortraitCircle.new(size)
	circle.ring = tone
	var path := str(adv.get("portrait_path", ""))
	if path != "" and ResourceLoader.exists(path):
		circle.texture = load(path) as Texture2D
	circle.size = Vector2(size, size)
	holder.add_child(circle)
	if circle.texture == null:
		var initials := Label.new()
		initials.text = str(adv.get("initials", "?"))
		initials.add_theme_font_size_override("font_size", int(size * 0.38))
		initials.add_theme_color_override("font_color", adv.get("portrait_color", C_TEXT))
		initials.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		initials.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		initials.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		initials.mouse_filter = Control.MOUSE_FILTER_IGNORE
		circle.add_child(initials)
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


# ── 5b · Goods Graph ─────────────────────────────────────────────────────────────

## Small goods-web vector icon: tiered flow nodes joined by edges (drawn — no
## suitable glyph in the bundled font). Mirrors the _BookIcon pattern.
class _WebIcon extends Control:
	var color := Color("#E8EEF7")   # C_LABEL; inner classes can't read outer consts
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
		# Left source node -> two mid nodes -> right sink node (a mini flow chart).
		var src := Vector2(2.5, h * 0.5)
		var mid_a := Vector2(w * 0.5, 3.0)
		var mid_b := Vector2(w * 0.5, h - 3.0)
		var sink := Vector2(w - 2.5, h * 0.5)
		for pair: Array in [[src, mid_a], [src, mid_b], [mid_a, sink], [mid_b, sink]]:
			draw_line(pair[0], pair[1], Color(color, 0.7), 1.2, true)
		for p: Vector2 in [src, mid_a, mid_b, sink]:
			draw_circle(p, 2.4, Color(color, 0.25))
			draw_arc(p, 2.4, 0.0, TAU, 10, color, 1.2, true)

func _build_goods_graph() -> void:
	var mod := _ModuleBtn.new(self)
	mod.name = "GoodsGraphModule"
	mod.tooltip_text = "Goods Graph (G) — how every good is made and what it feeds"
	mod.custom_minimum_size = Vector2(0, MOD_H)
	var row := _module_row(mod)
	var classic_row := HBoxContainer.new()
	classic_row.add_theme_constant_override("separation", 9)
	classic_row.alignment = BoxContainer.ALIGNMENT_CENTER
	classic_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(classic_row)
	var icon := _WebIcon.new(C_LABEL)
	classic_row.add_child(icon)
	var lbl := _mini("GOODS GRAPH", C_LABEL, 13)
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	classic_row.add_child(lbl)
	mod.mouse_entered.connect(func() -> void:
		icon.set_color(C_BRIGHT)
		lbl.add_theme_color_override("font_color", C_BRIGHT))
	mod.mouse_exited.connect(func() -> void:
		icon.set_color(C_LABEL)
		lbl.add_theme_color_override("font_color", C_LABEL))
	var v31_icon := _v31_icon(ICON_GOODS_GRAPH, mod)
	row.add_child(v31_icon)
	_register_v31_pair(classic_row, v31_icon)
	mod.pressed.connect(func() -> void:
		_close_fly()
		MatchState.goods_graph_requested.emit())
	_hbox().add_child(mod)


# ── 6/7/8 · Encyclopedia (adopted) · Turn/date · Menu ───────────────────────────

## Small open-book vector icon (drawn — the bundled font has no book glyph).
class _BookIcon extends Control:
	var color := Color("#E8EEF7")   # C_LABEL; inner classes can't read outer consts
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
var _enc_v31_inner: HBoxContainer   # v3.1

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
		var book := _BookIcon.new(C_LABEL)
		_enc_inner.add_child(book)
		var lbl := _mini("ENCYCLOPEDIA", C_LABEL, 13)
		lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_enc_inner.add_child(lbl)
		enc.mouse_entered.connect(func() -> void:
			book.set_color(C_BRIGHT)
			lbl.add_theme_color_override("font_color", C_BRIGHT))
		enc.mouse_exited.connect(func() -> void:
			book.set_color(C_LABEL)
			lbl.add_theme_color_override("font_color", C_LABEL))
		_enc_button = enc
		# v3.1: a second full-rect inner row, built the same way as _enc_inner so it
		# centres identically, holding just the icon. Only one of the two is ever
		# visible — see _register_v31_pair.
		_enc_v31_inner = HBoxContainer.new()
		_enc_v31_inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_enc_v31_inner.alignment = BoxContainer.ALIGNMENT_CENTER
		_enc_v31_inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		enc.add_child(_enc_v31_inner)
		_enc_v31_inner.add_child(_v31_icon(ICON_ENCYCLOPEDIA, enc))
		_register_v31_pair(_enc_inner, _enc_v31_inner)
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
		_date_label = _mini("", C_TEXT, 12)
		_date_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_date_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(_date_label)
	if hitbox != null:
		hitbox.visible = false

## Turn → month + year. One month per turn, but the year is the COMPANY'S year, not a
## calendar one (owner 2026-08-24): "January Year 1" through "December Year 25" over a
## 300-turn campaign, and into Year 9 by the demo's turn 100. A real calendar year kept
## implying a period the sim does not simulate.
const _MONTHS: Array[String] = ["January", "February", "March", "April", "May", "June",
	"July", "August", "September", "October", "November", "December"]

func _turn_date(turn: int) -> String:
	return "%s Year %d" % [_MONTHS[(turn - 1) % 12], 1 + (turn - 1) / 12]

func _build_menu() -> void:
	var mod := _ModuleBtn.new(self)
	mod.name = "MenuModule"
	mod.tooltip_text = "Main menu — save, settings, quit"
	mod.custom_minimum_size = Vector2(0, MOD_H)
	var row := _module_row(mod)
	row.add_child(_mini("☰", C_LABEL, 19))
	mod.pressed.connect(func() -> void:
		_close_fly()
		PauseMenu.open(get_parent()))
	_hbox().add_child(mod)


# ── Flyouts (Treasury · Council · Victory), anchored under their modules ────────

## The quest panel: the four steps with their ticks, the reward, and where to look if lost.
## No heading — at 120 px a title would spend a third of the panel repeating the module the
## player just clicked.
## ── The mission flyout ───────────────────────────────────────────────────────
##
## An ACCORDION of every mission in the chain, not just the live one. One section open at a
## time; opening one closes the rest.
##
## WIDTH IS THE MODULE'S, not the text's. This measured its own longest line for a while and
## the result was correct in isolation and visibly misaligned in place — the panel hangs off
## the module and the two have to read as one object (owner, 26 Aug). Steps wrap to fit;
## the module is the ruler.
const QUEST_FLY_FALLBACK_W := 320   # only if the module has not been laid out yet
const QUEST_FLY_PAD := 20           # this panel's left+right margins, which the text cannot use
## The flyout stylebox's 1 px border, both sides. A PanelContainer's minimum is its content plus
## its stylebox, so without subtracting this the panel lands 2 px wider than the module and the
## two edges visibly disagree.
const QUEST_FLY_BORDER := 2
const QUEST_STEP_PT := 13
const QUEST_HINT_PT := 12
const QUEST_BOX := 12.0             # the per-step tickbox, per spec

## Completion sequence, in seconds: the label fades away, the module flashes brass twice with a
## navy tick cut through it, then the next mission pops open and collapses itself again.
const QUEST_FLASH_SEC := 0.6
const QUEST_FLASHES := 2
const QUEST_CELEBRATE_SEC := 1.5
const QUEST_NEXT_OPEN_SEC := 3.0
## How long the label takes to fade out at the start (and the next one to fade in at the end).
## The tick waits this out before it starts drawing, so it never shares the module with text.
const QUEST_TEXT_FADE := 0.18
## The brass never drops below this through the flash, so the navy negative-space tick always
## has a plate to sit in — a flash that returned to zero would blink the tick out with it.
const QUEST_GLOW_FLOOR := 0.55

## v3.1 (cheat: `swap topbar v3.1`): the module's own expand/collapse, independent of the
## flyout — first appearance and each post-celebration handoff hold the full mission text
## for QUEST_V31_HOLD_SEC, then animate down to the icon over QUEST_V31_COLLAPSE_SEC.
const QUEST_V31_HOLD_SEC := 3.0
const QUEST_V31_COLLAPSE_SEC := 1.0
## How long the icon holds gold after the tick, before handing off to the next mission's
## text reveal — long enough to register as its own beat, not a flicker.
const QUEST_GOLD_HOLD_SEC := 0.6

## Which section is open, by mission kind; "" is all-collapsed. It lives on the bar rather than
## on the built nodes because _refresh_open_fly throws the whole flyout away and rebuilds it.
var _quest_open := ""
var _quest_sections: Dictionary = {}
var _quest_anim: Tween = null
var _quest_tick_anim: Tween = null
var _quest_text_anim: Tween = null
## Did the completion sequence open this flyout by itself? If so it closes it again afterwards,
## rather than leaving a panel over the map that the player never asked for.
var _quest_auto_opened := false
## While true, the module holds the finished mission's text and nothing rebuilds the flyout.
var _quest_celebrating := false
var _quest_celebrating_kind := ""


func _quest_fly_width() -> int:
	if _quest_btn != null and is_instance_valid(_quest_btn) and _quest_btn.size.x > 1.0:
		return int(_quest_btn.size.x)
	return QUEST_FLY_FALLBACK_W


func _fly_quest(vb: VBoxContainer) -> void:
	var width := _quest_fly_width()
	if _fly_panel != null and is_instance_valid(_fly_panel):
		_fly_panel.custom_minimum_size = Vector2(width - QUEST_FLY_BORDER, 0)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 10)
	pad.add_theme_constant_override("margin_right", 10)
	pad.add_theme_constant_override("margin_top", 10)
	pad.add_theme_constant_override("margin_bottom", 10)
	vb.add_child(pad)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	pad.add_child(col)
	_quest_sections = {}
	var list: Array = MiniQuest.missions()
	if _quest_open == "" and not list.is_empty():
		_quest_open = MiniQuest.active_mission()
	var inner: int = width - QUEST_FLY_PAD - QUEST_FLY_BORDER
	for kind_variant: Variant in list:
		var kind := str(kind_variant)
		var section := _quest_section(kind, inner)
		_quest_sections[kind] = section
		col.add_child(section)


## One accordion section: its header always, its steps and reward only while it is the open one.
func _quest_section(kind: String, inner: int) -> Control:
	var done: bool = MiniQuest.is_mission_complete(kind)
	var open: bool = _quest_open == kind
	var section := _QuestSection.new()
	section.custom_minimum_size = Vector2(inner, 0)
	section.pressed.connect(_toggle_quest_section.bind(kind))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	section.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(_quest_label("▾" if open else "▸", C_TEXT, QUEST_STEP_PT, false))
	# A finished mission's title goes brass, because a COLLAPSED section shows nothing else —
	# neither its filled boxes nor its ticked reward — and "which of these have I done" is the
	# question an accordion has to answer while shut.
	var title := _quest_label(MiniQuest.title(kind),
		DS.PALETTE.BRASS if done else C_TEXT, QUEST_STEP_PT, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	col.add_child(head)
	if not open:
		return section

	var steps: Array = MiniQuest.steps(kind)
	for i in steps.size():
		col.add_child(_quest_step_row(str(steps[i]), MiniQuest.step_done(i, kind)))

	var reward_row := HBoxContainer.new()
	reward_row.add_theme_constant_override("separation", 6)
	reward_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tick := _TickMark.new()
	tick.custom_minimum_size = Vector2(QUEST_BOX + 2.0, QUEST_BOX + 2.0)
	tick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tick.progress = 1.0 if done else 0.0
	reward_row.add_child(tick)
	section.tick = tick
	var reward := Label.new()
	reward.theme_type_variation = "Reward"   # brass + semibold, from DS
	reward.text = "Reward: %s" % MiniQuest.reward_text(kind)
	reward.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reward.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reward.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reward_row.add_child(reward)
	col.add_child(reward_row)

	var hint: String = MiniQuest.hint(kind)
	if hint != "":
		col.add_child(_quest_label(hint, C_TEXT, QUEST_HINT_PT, true))
	return section


## A step: the 12 px tickbox the spec asks for, then the text. The box is empty until the step
## is met and fills brass when it is; the text stays off-white either way, because dimming a
## completed step would be the grey-on-navy the house rule forbids.
func _quest_step_row(text: String, done: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The box hangs off the FIRST line of a wrapped step, not the middle of the block.
	var box_pad := MarginContainer.new()
	box_pad.add_theme_constant_override("margin_top", 3)
	box_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box_pad.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var box := Panel.new()
	box.custom_minimum_size = Vector2(QUEST_BOX, QUEST_BOX)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(3)
	sb.bg_color = DS.PALETTE.BRASS if done else Color(0, 0, 0, 0)
	sb.border_color = DS.PALETTE.BRASS if done else Color(C_TEXT.r, C_TEXT.g, C_TEXT.b, 0.55)
	sb.set_border_width_all(1)
	box.add_theme_stylebox_override("panel", sb)
	box_pad.add_child(box)
	row.add_child(box_pad)
	var label := _quest_label(text, C_TEXT, QUEST_STEP_PT, true)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	return row


## Off-white by default and never anything quieter (CLAUDE.md); IGNORE so every click inside a
## section reaches the section itself, which is the whole hit target.
func _quest_label(text: String, color: Color, pt: int, wrap: bool) -> Label:
	var l := _mini(text, color, pt)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _toggle_quest_section(kind: String) -> void:
	_quest_open = "" if _quest_open == kind else kind
	_quest_auto_opened = false   # they are driving now; do not close it out from under them
	if _fly_open_id == "quest":
		_refresh_open_fly()


## The completion sequence, 1.5 s of it, and it happens ON THE BAR (owner, 26 Aug). The module
## itself flashes brass twice while a tick draws across it; the flyout stays SHUT through all of
## that. Only when the flash is done does the module switch to the next mission and the flyout
## pop open for three seconds to reveal it, then fold away.
##
## Driving the module rather than a flyout section is also what makes the timing trustworthy:
## the module is a permanent node, so nothing the turn-resolution does can free the tween's
## target mid-flight — which is exactly what used to collapse the whole 1.5 s into an instant.
func _celebrate_mission(kind: String) -> void:
	if _quest_btn == null or not is_instance_valid(_quest_btn) or not _quest_btn.visible:
		return
	_quest_celebrating = true
	_quest_celebrating_kind = kind
	# The flash is on the bar, so the flyout has no part in it — close it if a prior celebration
	# left it open, and do NOT open it now.
	if _fly_open_id == "quest" and _quest_auto_opened:
		_close_fly()
	_refresh_quest()   # the module holds on the finished mission ("Complete — <reward>")
	var mod := _quest_btn as _ModuleBtn
	mod.tick_progress = 0.0
	# The tick is the navy of the bar directly behind the module, so it reads as a hole in the
	# brass. Sampled once — the module does not move during the flash.
	mod.tick_color = _bar_navy_at(mod.position + mod.size * 0.5)
	_kill_quest_anim()
	# The label (or v3.1 icon) fades away first, so the tick has the module to itself
	# (owner, 26 Aug). Both are tweened — whichever is currently hidden just no-ops.
	_quest_text_anim = create_tween()
	if _quest_text_col != null and is_instance_valid(_quest_text_col):
		_quest_text_anim.tween_property(_quest_text_col, "modulate:a", 0.0, QUEST_TEXT_FADE)
	if _quest_icon != null and is_instance_valid(_quest_icon):
		_quest_text_anim.parallel().tween_property(_quest_icon, "modulate:a", 0.0, QUEST_TEXT_FADE)
	# Two flashes, but between them the glow only dips to the floor rather than to zero, so the
	# brass plate — and the navy tick cut into it — stays lit the whole way through.
	_quest_anim = create_tween()
	for _i in QUEST_FLASHES:
		_quest_anim.tween_method(_set_quest_celebrate, QUEST_GLOW_FLOOR, 1.0, QUEST_FLASH_SEC * 0.5)
		_quest_anim.tween_method(_set_quest_celebrate, 1.0, QUEST_GLOW_FLOOR, QUEST_FLASH_SEC * 0.5)
	_quest_anim.tween_interval(maxf(0.0, QUEST_CELEBRATE_SEC - QUEST_FLASH_SEC * QUEST_FLASHES))
	_quest_anim.tween_callback(_finish_celebration.bind(kind))
	# The tick waits for the label to clear, then draws across the two flashes.
	_quest_tick_anim = create_tween()
	_quest_tick_anim.tween_interval(QUEST_TEXT_FADE)
	_quest_tick_anim.tween_property(mod, "tick_progress", 1.0,
		QUEST_FLASH_SEC * QUEST_FLASHES - QUEST_TEXT_FADE)


## One flash of the module: rim to brass and the fill glow, together on the same eased value.
func _set_quest_celebrate(t: float) -> void:
	if _quest_btn == null or not is_instance_valid(_quest_btn):
		return
	var mod := _quest_btn as _ModuleBtn
	mod.rim = _quest_rim().lerp(DS.PALETTE.BRASS, t)
	mod.glow = t


## The bar's own ground gradient, sampled at a canvas point — bilinear across the four BarNavy
## corners, the same fill _draw lays down. Used to colour the negative-space completion tick so
## it matches the bar exactly rather than approximating it.
func _bar_navy_at(pos: Vector2) -> Color:
	var w: float = maxf(1.0, size.x)
	var y0: float = size.y - EDGE_H
	var u: float = clampf(pos.x / w, 0.0, 1.0)
	var v: float = clampf((pos.y + TOP_BLEED) / maxf(1.0, y0 + TOP_BLEED), 0.0, 1.0)
	return BarNavy.TL.lerp(BarNavy.TR, u).lerp(BarNavy.BL.lerp(BarNavy.BR, u), v)


func _kill_quest_anim() -> void:
	for t: Tween in [_quest_anim, _quest_tick_anim, _quest_text_anim]:
		if t != null and t.is_valid():
			t.kill()
	_quest_anim = null
	_quest_tick_anim = null
	_quest_text_anim = null


## 1.5 s in: the flash is over. Clear the module back to its resting look, switch it to the next
## mission, and THEN — not before — pop the flyout open on that mission for three seconds.
func _finish_celebration(finished_kind: String) -> void:
	if _quest_btn != null and is_instance_valid(_quest_btn):
		var mod := _quest_btn as _ModuleBtn
		mod.glow = 0.0
		mod.tick_progress = 0.0
		mod.rim = _quest_rim()
	_quest_celebrating = false
	_quest_celebrating_kind = ""
	var list: Array = MiniQuest.missions()
	var idx: int = list.find(finished_kind)
	var next := str(list[idx + 1]) if idx >= 0 and idx + 1 < list.size() else ""
	_quest_open = next
	var v31: bool = MatchState.use_topbar_v3_1
	if v31:
		_quest_v31_animating = true   # hold _refresh_quest's steady-state branch off below
	_refresh_quest()   # the module now reads the next mission (or hides, if the chain is done)
	if v31:
		_finish_celebration_v31(next)
		return
	# Fade the (new) label back in — it was faded to nothing for the tick. If the chain is done
	# the module is hidden anyway, but restore the alpha so a fresh match starts opaque.
	if _quest_text_col != null and is_instance_valid(_quest_text_col):
		if next == "":
			_quest_text_col.modulate.a = 1.0
		else:
			_quest_text_anim = create_tween()
			_quest_text_anim.tween_property(_quest_text_col, "modulate:a", 1.0, QUEST_TEXT_FADE)
	if next == "":
		return
	# The reveal: the next mission pops open, and folds itself away after three seconds.
	if _fly_open_id != "quest":
		_quest_auto_opened = true
		_open_fly("quest")
	else:
		_refresh_open_fly()
	get_tree().create_timer(QUEST_NEXT_OPEN_SEC).timeout.connect(
		_collapse_quest_accordion.bind(next))


## v3.1's half of _finish_celebration (classic instead pops the flyout open, above —
## the module itself now carries the reveal, so v3.1 skips that entirely, avoiding
## showing the same "here's the new mission" information twice at once).
##
## The icon reveals already turning gold (fading in on a gold modulate, not to white
## then re-tinting — one motion, not two), holds long enough to read as its own beat,
## then hands off to the reveal-then-collapse sequence for the mission this completion
## advanced to. With no next mission, it just rests on the icon in white.
func _finish_celebration_v31(next: String) -> void:
	if _quest_icon == null or not is_instance_valid(_quest_icon):
		_quest_v31_animating = false
		return
	_quest_text_col.visible = false
	_quest_icon.visible = true
	if next == "":
		_quest_icon.modulate = Color.WHITE
		_quest_v31_wide = false
		_quest_v31_animating = false
		_place_quest.call_deferred()
		return
	var brass: Color = DS.PALETTE.BRASS
	_quest_icon.modulate = Color(brass.r, brass.g, brass.b, 0.0)
	_place_quest.call_deferred()
	var gold_anim := create_tween()
	gold_anim.tween_property(_quest_icon, "modulate", brass, QUEST_TEXT_FADE)
	gold_anim.tween_interval(QUEST_GOLD_HOLD_SEC)
	gold_anim.tween_callback(func() -> void:
		_quest_v31_animating = false
		_quest_v31_reveal_then_collapse())


## Fold the accordion shut — but only if the player has not since opened something else, and
## only close the flyout itself if the celebration is what opened it.
func _collapse_quest_accordion(expected: String) -> void:
	if _quest_open != expected:
		return
	_quest_open = ""
	if _fly_open_id != "quest":
		return
	if _quest_auto_opened:
		_quest_auto_opened = false
		_close_fly()
	else:
		_refresh_open_fly()


## One accordion section: the whole block is the click target that toggles it. It still holds a
## `tick` for the reward line's static checkmark, but the completion FLASH is no longer here —
## that plays on the module up on the bar (see _celebrate_mission), where the eye already is.
class _QuestSection extends PanelContainer:
	signal pressed
	var tick: Control = null
	var _hover := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func() -> void: _hover = true; _restyle())
		mouse_exited.connect(func() -> void: _hover = false; _restyle())
		_restyle()

	func _restyle() -> void:
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(8)
		sb.content_margin_left = 9
		sb.content_margin_right = 9
		sb.content_margin_top = 7
		sb.content_margin_bottom = 7
		sb.bg_color = Color(1, 1, 1, 0.09 if _hover else 0.035)
		sb.set_border_width_all(1)
		sb.border_color = Color(1, 1, 1, 0.13)
		add_theme_stylebox_override("panel", sb)

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			pressed.emit()


## A checkmark that DRAWS itself over `progress` 0→1, so the completion sequence has a tick
## being drawn rather than a glyph that blinks into existence. Two strokes: the short one takes
## the first third, the long one the rest.
class _TickMark extends Control:
	const SHORT_STROKE := 0.35
	var progress := 0.0:
		set(v):
			progress = clampf(v, 0.0, 1.0)
			queue_redraw()

	func _draw() -> void:
		if progress <= 0.0:
			return
		var s: float = minf(size.x, size.y)
		var a := Vector2(0.16, 0.52) * s
		var b := Vector2(0.40, 0.80) * s
		var c := Vector2(0.88, 0.18) * s
		var w: float = maxf(1.5, s * 0.15)
		var col: Color = DS.PALETTE.BRASS
		draw_line(a, a.lerp(b, minf(progress / SHORT_STROKE, 1.0)), col, w, true)
		if progress > SHORT_STROKE:
			draw_line(b, b.lerp(c, (progress - SHORT_STROKE) / (1.0 - SHORT_STROKE)), col, w, true)


func _build_fly_layer() -> void:
	_fly_layer = CanvasLayer.new()
	_fly_layer.layer = 110   # under the Turn Briefing hub (120)
	add_child(_fly_layer)
	_fly_scrim = _FlyScrim.new()
	_fly_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fly_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_fly_scrim.visible = false
	_fly_scrim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			_fly_scrim.accept_event()
			_close_fly())
	_fly_layer.add_child(_fly_scrim)

## Full-screen catcher that closes an open flyout on any outside click. It deliberately
## does NOT cover the End Turn button: a STOP-filter Control consumes the event whether or
## not it calls accept_event, so the only way to let that one click through is to be
## un-hittable there. Ending a turn with the treasury mini-panel open now works, and the
## panel stays up so the player sees the new numbers land.
class _FlyScrim extends Control:
	var _end_turn: Control = null

	func _has_point(point: Vector2) -> bool:
		var btn := _end_turn_button()
		if btn != null and btn.is_visible_in_tree() \
				and btn.get_global_rect().has_point(point + global_position):
			return false
		return true

	func _end_turn_button() -> Control:
		if _end_turn != null and is_instance_valid(_end_turn):
			return _end_turn
		var scene := get_tree().current_scene if is_inside_tree() else null
		if scene == null:
			return null
		var n := scene.find_child("EndTurnButton", true, false)
		_end_turn = n as Control
		return _end_turn


func _toggle_fly(id: String) -> void:
	if _fly_open_id == id:
		_close_fly()
	else:
		_open_fly(id)

## A resolved turn changes every number in the treasury mini-panel. It was built once on open,
## so a player who left it up read last turn's figures — rebuild it in place instead.
func _refresh_open_fly() -> void:
	if _fly_open_id == "" or _fly_panel == null or not is_instance_valid(_fly_panel):
		return
	var id := _fly_open_id
	_close_fly()
	_open_fly(id)


func _close_fly() -> void:
	_fly_open_id = ""
	_fly_scrim.visible = false
	if _fly_panel != null and is_instance_valid(_fly_panel):
		if _fly_panel.get_parent() != null:
			_fly_panel.get_parent().remove_child(_fly_panel)
		_fly_panel.queue_free()
	_fly_panel = null
	_fly_open_id = ""
	if _victory_btn != null:
		(_victory_btn as _ModuleBtn).active = false
	if _rankings_btn != null:
		(_rankings_btn as _ModuleBtn).active = false
	if _council_btn != null:
		(_council_btn as _ModuleBtn).active = false
	if _quest_btn != null and is_instance_valid(_quest_btn):
		(_quest_btn as _ModuleBtn).active = false
	if _power_btn != null and is_instance_valid(_power_btn):
		(_power_btn as _ModuleBtn).active = false

func _open_fly(id: String) -> void:
	_close_fly()
	_fly_scroll = null
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
	_fly_panel.name = "Flyout_%s" % id   # stable target (tutorial spotlight / e2e)
	if id == "rankings":
		# CanvasLayer children do not consistently inherit the viewport's theme.
		# Assign it here so this expanded panel genuinely uses DS Card/Outlined styles.
		_fly_panel.theme = DS.theme
		_fly_panel.theme_type_variation = "Card"
	else:
		# The quest panel needs the DS theme for the same reason the rankings one does: a
		# CanvasLayer child does not reliably inherit the viewport's, so its Labels fall back to
		# the ENGINE default font. Off-brand, and it made this panel unmeasurable — the width was
		# computed in the DS face and rendered in a wider one, so steps kept wrapping at what was
		# supposedly a generous width. Setting it took the panel from 228 px tall to 165.
		#
		# The OTHER flyouts here (treasury, council, victory) have the same gap and are left
		# alone deliberately: none of them was in scope, and each would want its own look at.
		if id == "quest":
			_fly_panel.theme = DS.theme
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
		"power":
			_fly_panel.custom_minimum_size = Vector2(300, 0)
			vb.add_child(_fly_head("Power"))
			_fly_power(vb)
			anchor = _power_btn
			(_power_btn as _ModuleBtn).active = true
		"victory":
			_fly_panel.custom_minimum_size = Vector2(330, 0)
			vb.add_child(_fly_head("Victory"))
			_fly_victory(vb)
			anchor = _victory_btn
			(_victory_btn as _ModuleBtn).active = true
		"rankings":
			_fly_panel.custom_minimum_size = Vector2(560, 0)
			vb.add_child(_fly_head("Company rankings"))
			_fly_rankings(vb)
			anchor = _rankings_btn
			(_rankings_btn as _ModuleBtn).active = true
		"council":
			_fly_panel.custom_minimum_size = Vector2(352, 0)
			vb.add_child(_fly_head("Council"))
			_fly_council(vb)
			anchor = _council_btn
			(_council_btn as _ModuleBtn).active = true
		"quest":
			# 120 tall as specced, and wide enough that the longest step sits on one line.
			_fly_quest(vb)   # measures its own text and sets the panel width
			anchor = _quest_btn
			(_quest_btn as _ModuleBtn).active = true
	_fly_layer.add_child(_fly_panel)
	# Position after layout: left-align to the module, clamped to the viewport.
	var place := func() -> void:
		if _fly_panel == null or not is_instance_valid(_fly_panel):
			return
		# CanvasLayer children do not participate in a parent Container layout.
		# Give the mini-panel its measured content height explicitly, otherwise it
		# retains the viewport height and leaves an empty panel below its actions.
		_fly_panel.size = _fly_panel.get_combined_minimum_size()
		# Now that there IS a real rect, hand any overshoot back to the scroller: the panel ends
		# above the screen edge and the rows that no longer fit scroll inside it, rather than
		# sitting below the bottom of the display where nothing can reach them.
		var vh: float = get_viewport().get_visible_rect().size.y
		var max_h: float = vh - (BAR_H + 8.0) - FLY_BOTTOM_MARGIN
		if _fly_panel.size.y > max_h and _fly_scroll != null and is_instance_valid(_fly_scroll):
			var overflow: float = _fly_panel.size.y - max_h
			_fly_scroll.custom_minimum_size.y = maxf(
				FLY_LIST_MIN_H, _fly_scroll.custom_minimum_size.y - overflow)
			_fly_panel.size.y = minf(_fly_panel.size.y, max_h)
		var vw := get_viewport().get_visible_rect().size.x
		var x := 12.0 if id == "rankings" else anchor.global_position.x
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

func _fly_row(label: String, value: String, tone: Color = C_TEXT, label_tone: Color = DS.PALETTE.TEXT_DIM, row_name: String = "") -> Control:
	var row := HBoxContainer.new()
	if row_name != "":
		row.name = row_name   # stable target for the tutorial's money primer
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

func _fly_rankings(vb: VBoxContainer) -> void:
	vb.add_child(_rankings_tabs())
	if _rankings_tab == "goods":
		_fly_goods_rankings(vb)
	else:
		_fly_revenue_rankings(vb)

func _rankings_tabs() -> Control:
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 14)
	pad.add_theme_constant_override("margin_right", 14)
	pad.add_theme_constant_override("margin_top", 10)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	pad.add_child(row)
	for tab: String in ["revenue", "goods"]:
		var button := Button.new()
		button.theme = DS.theme
		button.text = "Revenue" if tab == "revenue" else "Goods"
		# Keep both tabs clickable; the primary treatment, rather than a disabled
		# button, marks the tab currently being shown.
		button.theme_type_variation = "Primary" if tab == _rankings_tab else ""
		button.custom_minimum_size = Vector2(110, 30)
		button.pressed.connect(func() -> void: _set_rankings_tab(tab))
		row.add_child(button)
	return pad

func _set_rankings_tab(tab: String) -> void:
	if tab == _rankings_tab:
		return
	_rankings_tab = tab
	_close_fly()
	_open_fly("rankings")

## How tall a rankings list may be before it scrolls: everything between the bar and the bottom
## of the screen, less this panel's own chrome (title, tabs, column headings) and a margin.
##
## A CONSTANT will not do here. At nine rivals the revenue table fitted on any screen; at
## nineteen it is twenty rows deep and ran off the bottom of a 1440 px display with ranks 13–20
## unreachable — and a constant chosen to fit 1080p would waste half of a taller one.
const FLY_LIST_CHROME := 260.0
const FLY_LIST_MIN_H := 360.0
## Clearance kept between the bottom of a flyout and the bottom of the screen.
const FLY_BOTTOM_MARGIN := 16.0

func _fly_list_height() -> float:
	var vp := get_viewport()
	var vh: float = vp.get_visible_rect().size.y if vp != null else 1080.0
	return maxf(FLY_LIST_MIN_H, vh - FLY_LIST_CHROME)


## The scroller of whichever flyout is open, so _open_fly's deferred placement can hand back
## any height the panel overshot the screen by. Null for the flyouts that hold no list.
var _fly_scroll: ScrollContainer = null

## A scroller sized by _fly_list_height, with the list inside it. Both rankings tabs use it: the
## goods tab has always been longer than the screen, and the revenue tab now is too.
##
## _fly_list_height is only an OPENING BID — it subtracts an ESTIMATE of this panel's chrome,
## and an estimate is what left the revenue table hanging off the bottom of a 1440 px screen
## with its last rows unreachable. The correction is measured in _open_fly's placement, once
## the panel has a real rect.
func _fly_list_scroll(vb: VBoxContainer, separation: int) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, _fly_list_height())
	_fly_scroll = scroll
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", separation)
	scroll.add_child(list)
	vb.add_child(scroll)
	return list


func _fly_revenue_rankings(vb: VBoxContainer) -> void:
	var inner := _fly_pad(vb, 5)
	var hint := Label.new()
	hint.theme_type_variation = "Caption"
	hint.text = "TOTAL REVENUE · LAST 5-TURN AVERAGE"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	inner.add_child(hint)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	var rank_head := _mini("RANK", DS.PALETTE.TEXT_DIM, 10)
	rank_head.custom_minimum_size = Vector2(68, 0)
	header.add_child(rank_head)
	var company_head := _mini("COMPANY", DS.PALETTE.TEXT_DIM, 10)
	company_head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(company_head)
	var revenue_head := _mini("REVENUE", DS.PALETTE.TEXT_DIM, 10)
	revenue_head.custom_minimum_size = Vector2(112, 0)
	revenue_head.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(revenue_head)
	var average_head := _mini("5T AVG", DS.PALETTE.TEXT_DIM, 10)
	average_head.custom_minimum_size = Vector2(112, 0)
	average_head.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(average_head)
	inner.add_child(header)
	inner.add_child(_fly_sep())
	# The rows go in a scroller, not in `inner`: twenty of them are taller than the screen.
	var rows := _fly_list_scroll(vb, 5)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 14)
	pad.add_theme_constant_override("margin_right", 14)
	pad.add_theme_constant_override("margin_bottom", 12)
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 5)
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_child(stack)
	rows.add_child(pad)
	for entry: Dictionary in CompanyRankings.standings():
		stack.add_child(_ranking_row(entry))

func _fly_goods_rankings(vb: VBoxContainer) -> void:
	var hint_pad := MarginContainer.new()
	hint_pad.add_theme_constant_override("margin_left", 14)
	hint_pad.add_theme_constant_override("margin_right", 14)
	hint_pad.add_theme_constant_override("margin_top", 4)
	hint_pad.add_theme_constant_override("margin_bottom", 8)
	var hint := Label.new()
	hint.theme_type_variation = "Caption"
	hint.text = "TOP 3 PRODUCERS + YOUR LAST-TURN OUTPUT · APEX GOODS ARE PLAYER-ONLY"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_pad.add_child(hint)
	vb.add_child(hint_pad)
	var list := _fly_list_scroll(vb, 8)
	for good: Dictionary in CompanyRankings.goods_standings():
		list.add_child(_goods_ranking_card(good))

## One good: its icon, its name, and the podium with the player under it.
##
## The card has NO fixed height. It carries three rows when the player is on the podium and four
## when they are not, and it is meant to grow by exactly that one row — a fixed height would
## either clip the fourth or leave a hole under the third. What IS pinned is the floor: the
## 60 px icon, so a three-row card cannot shrink below its own artwork.
const GOOD_CARD_ICON := 60
const GOOD_RANK_W := 42.0

func _goods_ranking_card(good: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.theme_type_variation = "Card"
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	card.add_child(body)
	# Unframed: the plate-and-bevel treatment is the market shelf's, and a scrolling column of it
	# read as chrome (owner, 26 Aug). Same art, same cream, rounded corners, no rim.
	body.add_child(DS.good_icon_plain(
		str(good.get("good_id", "")), str(good.get("internal_name", "")), GOOD_CARD_ICON))
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 4)
	body.add_child(details)
	var name := Label.new()
	name.theme_type_variation = "BuildingName"
	name.text = str(good.get("display_name", ""))
	details.add_child(name)
	for producer: Dictionary in (good.get("producers", []) as Array):
		var mine: bool = bool(producer.get("is_player", false))
		var producer_row := HBoxContainer.new()
		# The player's own rank is the one number on the card worth finding at a glance, so it is
		# cream where the rivals' are quiet. Rank is measured against the WHOLE field, which is
		# why it can read 7th on a card that lists four rows.
		var rank := _mini(_ordinal(int(producer.get("rank", 0))),
			C_CREAM if mine else DS.PALETTE.TEXT_DIM, 12)
		rank.custom_minimum_size = Vector2(GOOD_RANK_W, 0)
		producer_row.add_child(rank)
		var producer_name := Label.new()
		producer_name.theme_type_variation = "Body"
		producer_name.text = str(producer.get("name", ""))
		producer_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if mine:
			producer_name.add_theme_color_override("font_color", C_CREAM)
		producer_row.add_child(producer_name)
		var quantity := Label.new()
		quantity.theme_type_variation = "Numeric"
		quantity.text = "(%d)" % int(producer.get("quantity", 0))
		if mine:
			quantity.add_theme_color_override("font_color", C_CREAM)
		producer_row.add_child(quantity)
		details.add_child(producer_row)
	return card

func _ranking_row(entry: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.theme_type_variation = "Outlined" if bool(entry.get("is_player", false)) else "Card"
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	var rank := Label.new()
	rank.theme_type_variation = "Numeric"
	rank.text = "%s %s" % [_ranking_arrow(int(entry.get("rank_change", 0))), _ordinal(int(entry.get("rank", 0)))]
	rank.custom_minimum_size = Vector2(68, 0)
	row.add_child(rank)
	var company := Label.new()
	company.theme_type_variation = "Body"
	company.text = str(entry.get("name", ""))
	company.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(company)
	var revenue := Label.new()
	revenue.theme_type_variation = "Numeric"
	revenue.text = "%s / turn" % _money_text(float(entry.get("revenue", 0.0)))
	revenue.custom_minimum_size = Vector2(112, 0)
	revenue.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(revenue)
	var average := Label.new()
	average.theme_type_variation = "Numeric"
	average.text = "%s / turn" % _money_text(float(entry.get("trend_average", 0.0)))
	average.custom_minimum_size = Vector2(112, 0)
	average.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(average)
	return card

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
	inner.add_child(_fly_row("Cash on hand", _money_text(MatchState.money), C_BRIGHT, C_BRIGHT, "FlyRowCash"))
	inner.add_child(_fly_row("Net last turn", _fly_signed_money(net), C_BRIGHT, C_BRIGHT, "FlyRowNet"))
	var runway := _runway_turns()
	if runway > 0:
		inner.add_child(_fly_row("Runway at current burn", "≈ %d turns" % runway, C_BRIGHT, C_BRIGHT, "FlyRowRunway"))
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
	var total := _mini("Total %s / %s to win" % [_thousands(int(bd.get("total", 0))),
	_thousands(int(bd.get("win_threshold", 4000)))], C_TEXT, 11)
	total.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frow.add_child(total)
	var full := _fly_btn("Full breakdown", true)
	full.size_flags_horizontal = Control.SIZE_SHRINK_END
	full.pressed.connect(func() -> void:
		_close_fly()
		victory_widget_clicked.emit())
	frow.add_child(full)
	foot.add_child(frow)

# Power: two Supply Priority toggles (owner, 28 Aug), then the old direct map-
# overlay shortcut as a CTA button, so that behaviour survives the module moving
# to a flyout like every other one.
func _fly_power(vb: VBoxContainer) -> void:
	var inner := _fly_pad(vb, 14)
	_fly_priority_row(inner, "Supply Priority — Coal & Gas",
		"Runs your coal/gas plants first; only buys from the grid if they can't cover demand.",
		"Sells your coal/gas output to the grid; demand is met by grid purchase instead.",
		MatchState.power_priority_coal_gas,
		func(v: String) -> void: MatchState.set_power_priority("coal_gas", v))
	_fly_priority_row(inner, "Supply Priority — Wind & Solar",
		"Runs your wind/solar first — exposes buildings to derating when it's not generating.",
		"Sells your wind/solar output to the grid; buildings draw firm grid power instead (default — avoids intermittency).",
		MatchState.power_priority_wind_solar,
		func(v: String) -> void: MatchState.set_power_priority("wind_solar", v))
	vb.add_child(_fly_sep())
	var foot := _fly_pad(vb)
	var map_btn := _fly_btn("View power balance map", true)
	map_btn.pressed.connect(func() -> void:
		_close_fly()
		_on_power_pressed())
	foot.add_child(map_btn)

## One "Grid" / "Your buildings" toggle row: label, then two ButtonGroup-linked
## pill buttons — same two-way-choice idiom construct_panel_v2.gd's
## _settings_choice_button uses for its own material/destination settings,
## restyled to this bar's flyout look (that helper isn't reachable from here).
func _fly_priority_row(vb: VBoxContainer, title: String, self_tip: String, grid_tip: String,
		current: String, on_pick: Callable) -> void:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	vb.add_child(row)
	row.add_child(_mini(title, C_TEXT, 12))
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	row.add_child(btn_row)
	var group := ButtonGroup.new()
	for opt: Array in [["grid", "Grid", grid_tip], ["self", "Your buildings", self_tip]]:
		var key: String = opt[0]
		var selected := current == key
		var btn := Button.new()
		btn.text = str(opt[1])
		btn.tooltip_text = str(opt[2])
		btn.toggle_mode = true
		btn.button_group = group
		btn.button_pressed = selected
		btn.focus_mode = Control.FOCUS_NONE
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 12)
		var sb := StyleBoxFlat.new()
		sb.bg_color = C_ACTIVE_BG if selected else Color(1, 1, 1, 0.05)
		sb.border_color = C_BRIGHT if selected else C_MOD_BORDER
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(6)
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
		for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
			btn.add_theme_stylebox_override(state, sb)
		btn.add_theme_color_override("font_color", C_BRIGHT if selected else C_TEXT)
		for state in ["font_hover_color", "font_pressed_color", "font_focus_color"]:
			btn.add_theme_color_override(state, C_BRIGHT if selected else C_TEXT)
		btn.pressed.connect(func() -> void:
			on_pick.call(key)
			_refresh_open_fly())
		btn_row.add_child(btn)

# Council: one row per seated advisor (portrait · name/seat · loyalty bar · value).
func _fly_council(vb: VBoxContainer) -> void:
	var inner := _fly_pad(vb, 3)
	var seats: Dictionary = MatchState.advisor_seats
	if seats.is_empty():
		inner.add_child(_mini("No advisors seated — open People to hire.", DS.PALETTE.TEXT_DIM, 11))
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
		col.add_child(_mini(MatchState._seat_display_name(str(seat_id)), DS.PALETTE.TEXT_DIM, 10))
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
	_refresh_transport()
	_refresh_rankings()
	_refresh_briefing()
	_refresh_council()
	if _date_label != null:
		_date_label.text = _turn_date(int(TurnManager.current_turn))
	if _enc_button != null and _enc_inner != null:
		var enc_face: Control = _enc_v31_inner if (MatchState.use_topbar_v3_1 and _enc_v31_inner != null) else _enc_inner
		_enc_button.custom_minimum_size = Vector2(enc_face.get_combined_minimum_size().x + 28.0, MOD_H)
	_refresh_bankruptcy_warning()

func _refresh_treasury() -> void:
	_cash_label.text = _money_text(MatchState.money)
	if not _flashing:
		_cash_label.add_theme_color_override("font_color", _base_money_color())
	var s: Dictionary = Production.last_turn_summary
	var net := float(s.get("money_in", 0.0)) - float(s.get("money_out", 0.0))
	_net_label.text = ("+" if net >= 0.0 else "−") + _money_text(absf(net)) + " / turn"
	_net_label.add_theme_color_override("font_color", C_GOOD if net >= 0.0 else C_BAD)
	# LED: overdrawn AND still losing money. Either alone is survivable — a negative
	# balance with a profitable turn is climbing out, and a loss with cash in hand is
	# affordable. Together they are the shape that ends runs (spec §1.3).
	(_treasury_led as StatusLed).lit = MatchState.money < 0.0 and net < 0.0
	var v31: bool = MatchState.use_topbar_v3_1
	_money_glyph.visible = not v31
	_money_coin_icon.visible = v31
	var runway := _runway_turns()
	_runway_label.visible = runway > 0
	if runway > 0:
		_runway_label.text = "≈%d TURNS" % runway
	# Buttons don't size to non-container children: min width = inner row + padding.
	money_widget.custom_minimum_size = Vector2(_money_inner.get_combined_minimum_size().x + 26.0, MOD_H)

func _refresh_power() -> void:
	var p := _power_stats()
	var s: Dictionary = Production.last_turn_summary
	var starved: bool = int(p.unpowered) > 0
	var gridding: bool = not starved and int(p.grid_draw) > 0
	var derated: bool = Production.intermittency_derated_count() > 0
	var c := C_RED if starved else (C_AMBER if gridding else C_GOOD)
	(_power_btn as _ModuleBtn).warn = starved
	var v31: bool = MatchState.use_topbar_v3_1
	_power_glyph.visible = not v31
	_power_icon.visible = v31
	var led := _power_led as StatusLed
	if v31:
		# v3.1: green when everything is good, amber for drawing from the grid, that
		# same amber BLINKS once a second when a building is actually being derated
		# by intermittency (independent of whether the empire is also grid-buying),
		# red when a building has no power at all. Red beats blink beats steady beats
		# green — this supersedes the classic LED's own narrower (grid-draw AND
		# losing money) condition below.
		led.blink = false
		if starved:
			led.color = C_RED
			led.lit = true
		elif derated:
			led.color = C_AMBER
			led.lit = true
			led.blink = true
		elif gridding:
			led.color = C_AMBER
			led.lit = true
		else:
			led.lit = false
	else:
		# Classic: buildings actually derated by intermittency, or the player buying
		# grid power while losing money. The second is the case the owner singled
		# out — the lamp lights HERE and not on the treasury, because power is the
		# thing to go and fix.
		var net: float = float(s.get("money_in", 0.0)) - float(s.get("money_out", 0.0))
		led.color = C_RED
		led.blink = false
		led.lit = (derated or (int(p.grid_draw) > 0 and net < 0.0))
	_power_glyph.add_theme_color_override("font_color", c)
	_power_head.add_theme_color_override("font_color", c)
	_power_head.text = ("%d unpowered" % int(p.unpowered)) if starved else (("Grid −%d" % int(p.grid_draw)) if gridding else "Powered")
	_power_sub.text = "buildings lack power" if starved else ("all buildings powered" if gridding else "self-sufficient")
	# v3.1: icon + light only — the "Powered / self-sufficient" text goes to the
	# tooltip below instead (same head is still colour-coded for the classic bar).
	(_power_head.get_parent() as Control).visible = not v31
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


# ── Anomaly popups (spec §4) ───────────────────────────────────────────────────
#
# A playtester finished a 118-turn run without ever understanding why her balance
# swung, and read a +£2,500 turn as arbitrary. It was not: a batch of sale shipments
# landed at once, on top of an auto-bridge loan she never noticed being taken, with
# tax and dividends skimmed in the same turn. Every figure was already on screen
# somewhere — none of it was ever ATTRIBUTED. These cards attribute it, in one
# sentence, under the module the money actually moved through.
#
# Thresholds are ratios against the previous THREE resolved turns, so a steadily
# growing empire never trips them — only a turn that breaks its own recent pattern.

## Turns of history the baselines average over.
const ANOMALY_BASELINE_TURNS := 3
## Revenue / running-cost spike: this multiple of the baseline.
const ANOMALY_SPIKE_RATIO := 1.5
## Transport is touchier — freight creeping up is the thing players miss.
const ANOMALY_TRANSPORT_RATIO := 1.25
## Power: a fifth of generation lost, or a fifth more demand than usual.
const ANOMALY_POWER_RATIO := 0.8
const ANOMALY_DEMAND_RATIO := 1.2
## Turns before the same trigger may fire again, so a long plateau does not nag.
const ANOMALY_COOLDOWN := 5
## At most two money cards at once (owner ruling), this far apart.
const ANOMALY_MAX_STACK := 2
const ANOMALY_STACK_GAP := 15.0
## Priority when more than ANOMALY_MAX_STACK money triggers fire in one turn.
const ANOMALY_MONEY_ORDER: Array[String] = ["loan", "spend", "transport", "payment"]
## Running-cost lines the spend trigger watches, each against its OWN baseline, mapped
## to the summary breakdown that says which buildings ran it up.
const ANOMALY_COST_LINES := {
	"goods_purchased_cost": "goods_purchased_by_type",
	"labour_paid": "labour_by_type",
	"maintenance_paid": "maintenance_by_type",
	"power_purchase_cost": "power_purchase_by_type",
}

const AnomalyPopup := preload("res://scripts/anomaly_popup.gd")

# Rolling history of the figures the triggers compare against: one entry per resolved
# turn, newest last, at most ANOMALY_BASELINE_TURNS long.
var _anomaly_history: Array[Dictionary] = []
var _anomaly_cooldown := {}          # trigger id -> turn it last fired
var _anomaly_cards: Array = []       # live popups, money and power together
var _anomaly_scrim: Control = null
var _loan_taken_this_turn := 0.0
## Latched once per run: the intermittency lesson is taught the first time the player
## actually generates intermittent green power, and never again.
var _intermittency_taught := false


func _on_loan_taken(loan: Dictionary) -> void:
	# Every path lands here — the silent auto-bridge as much as a deliberate draw, and
	# spread financing too (owner: 48 turns = 12 grace + 36 repaying IS a loan at
	# standard interest). Cleared once the turn's popups have been evaluated.
	_loan_taken_this_turn += float(loan.get("amount", 0.0))


## Judge the resolved turn, then fold it into the baseline for the next one.
func _on_turn_resolved_anomalies() -> void:
	var s: Dictionary = Production.last_turn_summary
	if s.is_empty():
		return
	var current := _anomaly_snapshot(s)
	_evaluate_anomalies(current, s)
	_anomaly_history.append(current)
	if _anomaly_history.size() > ANOMALY_BASELINE_TURNS:
		_anomaly_history = _anomaly_history.slice(_anomaly_history.size() - ANOMALY_BASELINE_TURNS)
	_loan_taken_this_turn = 0.0


func _anomaly_snapshot(s: Dictionary) -> Dictionary:
	var snap := {
		"revenue": float(s.get("goods_sales_revenue", 0.0)) + float(s.get("power_sales_revenue", 0.0)),
		"transport": float(s.get("transport_paid", 0.0)),
		"power_supply": float(s.get("power_supply", 0)),
		"power_demand": float(s.get("power_demand", 0)),
	}
	for line in ANOMALY_COST_LINES:
		snap[line] = float(s.get(line, 0.0))
	return snap


## Mean of `key` across the recorded history. Returns -1.0 until a FULL baseline exists:
## with fewer than three turns behind it every ratio is noise, and the opening turns of
## a run would otherwise fire on nothing but the empire starting up.
func _anomaly_baseline(key: String) -> float:
	if _anomaly_history.size() < ANOMALY_BASELINE_TURNS:
		return -1.0
	var total := 0.0
	for entry: Dictionary in _anomaly_history:
		total += float(entry.get(key, 0.0))
	return total / float(_anomaly_history.size())


func _anomaly_ready(id: String) -> bool:
	return int(TurnManager.current_turn) - int(_anomaly_cooldown.get(id, -9999)) >= ANOMALY_COOLDOWN


func _evaluate_anomalies(current: Dictionary, s: Dictionary) -> void:
	_clear_anomaly_cards()
	var money := _money_anomalies(current, s)
	# Priority order first, then the owner's cap of two.
	var chosen: Array = []
	for id: String in ANOMALY_MONEY_ORDER:
		for hit: Dictionary in money:
			if str(hit.id) == id and chosen.size() < ANOMALY_MAX_STACK:
				chosen.append(hit)
	for hit: Dictionary in chosen:
		_anomaly_cooldown[str(hit.id)] = int(TurnManager.current_turn)
	_show_anomaly_stack(chosen, money_widget)

	var power := _power_anomalies(current)
	if not power.is_empty():
		_anomaly_cooldown[str(power[0].id)] = int(TurnManager.current_turn)
		_show_anomaly_stack([power[0]], _power_btn)


## Money triggers that fired this turn, unordered. Each is {id, text}.
func _money_anomalies(current: Dictionary, s: Dictionary) -> Array:
	var hits: Array = []

	if _loan_taken_this_turn > 0.0 and _anomaly_ready("loan"):
		hits.append({"id": "loan", "word": "loan", "tone": "bad",
			"text": "We've taken a %s loan to cover this turn's bills." % _money_text(_loan_taken_this_turn)})

	var revenue_base := _anomaly_baseline("revenue")
	if revenue_base > 0.0 and float(current.revenue) >= revenue_base * ANOMALY_SPIKE_RATIO and _anomaly_ready("payment"):
		var pay := _big_payment_text(s)
		hits.append({"id": "payment", "tone": "good",
			"text": str(pay.get("text", "")), "word": str(pay.get("word", ""))})

	# Each running-cost line is judged against its OWN baseline, so a labour jump is not
	# hidden by a quiet turn for inputs. One generic sentence covers them all (owner).
	for line: String in ANOMALY_COST_LINES:
		var base := _anomaly_baseline(line)
		if base <= 0.0 or float(current.get(line, 0.0)) < base * ANOMALY_SPIKE_RATIO:
			continue
		if not _anomaly_ready("spend"):
			break
		hits.append({"id": "spend", "word": "spending", "tone": "bad",
			"text": "We're spending abnormal amounts of money: %s due to running costs for %s." % [
				_money_text(float(current.get(line, 0.0))),
				_cost_culprit(s, str(ANOMALY_COST_LINES[line]))]})
		break

	# Freight up sharply AND not paid for by extra revenue. The second half is the point:
	# a bigger empire shipping more is fine — freight outrunning what it earns is not.
	var transport_base := _anomaly_baseline("transport")
	if transport_base > 0.0 and _anomaly_ready("transport"):
		var transport_delta := float(current.transport) - transport_base
		var revenue_delta := float(current.revenue) - maxf(0.0, revenue_base)
		if transport_delta > transport_base * (ANOMALY_TRANSPORT_RATIO - 1.0) and revenue_delta < transport_delta:
			hits.append({"id": "transport", "word": "Transport", "tone": "bad",
				"text": "Transport costs are through the roof. Check if we're shipping by the most efficient transport."})
	return hits


## Name what ran a cost line up. `by_type_key` is the summary's building_id ->
## {count, amount} breakdown that the money panel's tooltips already read.
func _cost_culprit(s: Dictionary, by_type_key: String) -> String:
	var by_type: Dictionary = s.get(by_type_key, {})
	if by_type.is_empty():
		return "our buildings"
	var top_id := ""
	var top_amount := 0.0
	var total := 0.0
	var count := 0
	for bid in by_type:
		var entry: Dictionary = by_type[bid]
		var amount := float(entry.get("amount", 0.0))
		total += amount
		count += int(entry.get("count", 0))
		if amount > top_amount:
			top_amount = amount
			top_id = str(bid)
	# A single building is named only when it really is the story. Otherwise the honest
	# answer is a count — picking the top of a flat distribution would blame the innocent.
	if top_id != "" and total > 0.0 and top_amount / total >= 0.5:
		return Catalog.get_building_display_name(top_id)
	return "%d buildings" % count if count > 0 else "our buildings"


## The sale that made the turn, as {text, word}. Names the good when one dominates the
## payout, because "you sold 40 units of steel for £900" is actionable where "revenue was
## up" is not. `word` is the span the card colours: the MONEY, which is what the player is
## looking for, rather than the verb that got it there (owner 2026-08-24).
func _big_payment_text(s: Dictionary) -> Dictionary:
	var sold: Dictionary = s.get("sold", {})
	var top_id := ""
	var top_revenue := 0.0
	var top_qty := 0
	var total_revenue := 0.0
	var total_qty := 0
	for gid in sold:
		var entry: Dictionary = sold[gid]
		var rev := float(entry.get("revenue", 0.0))
		total_revenue += rev
		total_qty += int(entry.get("qty", 0))
		if rev > top_revenue:
			top_revenue = rev
			top_id = str(gid)
			top_qty = int(entry.get("qty", 0))
	if top_id != "" and total_revenue > 0.0 and top_revenue / total_revenue >= 0.5:
		var earned := "earned you %s" % _money_text(top_revenue)
		return {"word": earned,
			"text": "You sold %d units of %s to the global market, which %s." % [
				top_qty, Catalog.get_display_name(top_id), earned]}
	var span := "%d units" % total_qty
	return {"word": span,
		"text": "You sold an unusually high %s of %d goods." % [span, sold.size()]}


## Power triggers, highest-priority first.
func _power_anomalies(current: Dictionary) -> Array:
	var hits: Array = []
	var previous: Dictionary = _anomaly_history[-1] if not _anomaly_history.is_empty() else {}

	var last_supply := float(previous.get("power_supply", 0.0))
	if last_supply > 0.0 and float(current.power_supply) <= last_supply * ANOMALY_POWER_RATIO and _anomaly_ready("dark"):
		hits.append({"id": "dark", "word": "power", "tone": "bad",
			"text": "Our power plants are going dark!"})

	# Taught once, the first turn intermittent green is actually GENERATED — when the
	# player has just built the wind or solar, not when it first bites (owner ruling:
	# that is the teachable moment, ahead of the first derate).
	if not _intermittency_taught:
		var quality: Dictionary = Production.last_turn_summary.get("power_supply_by_quality", {})
		if float(quality.get("green_intermittent", 0)) > 0.0:
			_intermittency_taught = true
			hits.append({"id": "intermittency", "word": "Renewable", "tone": "good",
				"text": "Renewable power's great, but what do we do when the sun doesn't shine or the wind doesn't blow?"})

	var demand_base := _anomaly_baseline("power_demand")
	var flipped: bool = (not previous.is_empty()
			and float(previous.get("power_supply", 0.0)) >= float(previous.get("power_demand", 0.0))
			and float(current.power_supply) < float(current.power_demand))
	var jumped: bool = demand_base > 0.0 and float(current.power_demand) >= demand_base * ANOMALY_DEMAND_RATIO
	if (flipped or jumped) and _anomaly_ready("grid"):
		hits.append({"id": "grid", "word": "grid", "tone": "bad",
			"text": "We're drawing power from the grid for now, but this is becoming expensive."})
	return hits


# ── Anomaly presentation ──────────────────────────────────────────────────────

func _show_anomaly_stack(hits: Array, anchor: Control) -> void:
	if hits.is_empty() or anchor == null or DisplayServer.get_name() == "headless":
		return
	_ensure_anomaly_scrim()
	var offset := 0.0
	for hit: Dictionary in hits:
		var card := AnomalyPopup.new()
		_fly_layer.add_child(card)
		# Width first: the stack offset below is measured off the card's wrapped height,
		# which is only correct once the width its text wraps at is settled.
		card.set_width(anchor.size.x)
		card.set_message(str(hit.text), str(hit.get("word", "")), str(hit.get("tone", "warn")))
		_anomaly_cards.append(card)
		# Placed after layout: the card has no height until its wrapped label is measured.
		card.call_deferred("place_under", anchor, offset)
		offset += card.get_combined_minimum_size().y + ANOMALY_STACK_GAP
	_anomaly_scrim.visible = true


## Full-screen catcher: a click anywhere outside the cards dismisses them all. The cards
## sit ABOVE it and stop their own clicks, so reading one can never dismiss it.
func _ensure_anomaly_scrim() -> void:
	if _anomaly_scrim != null and is_instance_valid(_anomaly_scrim):
		return
	_anomaly_scrim = _FlyScrim.new()
	_anomaly_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_anomaly_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_anomaly_scrim.visible = false
	_anomaly_scrim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			_anomaly_scrim.accept_event()
			_clear_anomaly_cards())
	_fly_layer.add_child(_anomaly_scrim)
	_fly_layer.move_child(_anomaly_scrim, 0)


func _clear_anomaly_cards() -> void:
	for card in _anomaly_cards:
		if is_instance_valid(card):
			card.queue_free()
	_anomaly_cards.clear()
	if _anomaly_scrim != null and is_instance_valid(_anomaly_scrim):
		_anomaly_scrim.visible = false
