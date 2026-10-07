extends PanelContainer
## Top Bar — the DS2 steel strip (docs/top-bar-ds2-plan.md).
## Modules left→right:
##   Power · Transport · Mission (key and piston) · Treasury (cash on an LED screen, centred on the
##   concrete) · [flex] · Victory (drum counter) · Rankings · Council · Goods Graph · Encyclopedia
##   · | · Turn/date · Menu.
## Treasury, Power and the mission open steel sheets under the bar whose keys deep-link into the
## full panels; Victory, Council and Rankings open their own panels. Hovering a module shows its
## readout under the bar.
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
# Modules have no boxes, so the budget is 4 top + 45 module + 4 bottom + the 7px bezel.
# Module chrome is flat; see _module_box.
# content_margin_top/bottom in _style_bar reference BAR_H's own EDGE_H term, not a
# literal number, so the bar grows around MOD_H without anything else changing.
const BAR_H := 60.0
const MOD_H := 45.0
# The modules' icons: baked standalone icons in the bottom-menu button treatment (cream emboss +
# bevel + drop shadow) minus the round disc and outer ring, since these sit flat on the bar rather
# than in a socket. Each one with a raised render (DS2_BAR_ICONS) is drawn as that instead.
const ICON_GOODS_GRAPH: Texture2D = preload("res://assets/icons/ui_icons/standalone/sankey.png")
## The menu glyph, baked by tools/bake_menu_icon.py. A texture rather than the text "☰", so it
## takes the cream tint, sheen and hover glow like every other control on the bar -- those
## are applied to a texture, and a glyph is not one.
const ICON_MENU: Texture2D = preload("res://assets/icons/ui_icons/standalone/menu.png")
const ICON_ENCYCLOPEDIA: Texture2D = preload("res://assets/icons/ui_icons/standalone/open-book.png")
const ICON_QUEST: Texture2D = preload("res://assets/icons/ui_icons/standalone/target.png")
const ICON_POWER: Texture2D = preload("res://assets/icons/ui_icons/standalone/power_icon.png")
const ICON_VICTORY: Texture2D = preload("res://assets/icons/ui_icons/standalone/trophy.png")
const ICON_RANKINGS: Texture2D = preload("res://assets/icons/ui_icons/standalone/podium.png")
const ICON_COUNCIL: Texture2D = preload("res://assets/icons/ui_icons/standalone/board-of-directors.png")
const SPECULAR_TEX: Texture2D = preload("res://assets/icons/ui_icons/alt/_specular.png")
# A soft radial burst (bright centre, fades to nothing) — the same "glow behind the
# object" idea as bottom_menu.gd's per-button _glow_<key>.png, just one shared
# generic gradient rather than a shape cut to each icon, since these icons don't
# sit on a disc for a cutout glow to read against.
const GLOW_TEX: Texture2D = preload("res://assets/icons/ui_icons/standalone/_glow.png")
const GLOW_SCALE := 2.0   # glow diameter relative to the icon's own px size
const GLOW_TINT := Color(1.0, 0.92, 0.75, 0.6)
# Every icon on the bar is fitted by its drawn art, not its canvas: the art is ICON_CAP tall
# (or ICON_MAX_W wide, for a wide icon), centred on the module row's midline. See _bar_icon.
const ICON_CAP := 34.0
const ICON_MAX_W := 42.0
## Icons that read light at the cap, drawn larger by this factor. Nothing else sizes an icon.
const ICON_OPTICAL := {
	# A thin upright bolt: at the cap it is half as wide as its neighbours.
	"res://assets/icons/ui_icons/standalone/power_icon.png": 1.08,
	# All thin strokes and no solid mass: beside the council table and the book it reads small.
	"res://assets/icons/ui_icons/standalone/sankey.png": 1.12,
}
# The strip's beam along the bar's foot, which the modules keep off.
const EDGE_H := 7.0
# Pixels the strip is painted ABOVE the bar's top edge, burying the sub-pixel seam
# that non-integer window stretching leaves on the top row (see _style_bar).
const TOP_BLEED := 8.0
const C_ACTIVE_BG := Color("#15304a")
# Spec §1.5: the bar's body text is the SAME off-white the panels use — anything greyer
# reads as grey on this navy, and the standing rule (ds.gd:50) is that grey never goes
# on a dark ground. Colour that carries
# MEANING is untouched: good/bad green and red, amber warnings, the cream victory score.
const C_TEXT := Color("#E8EEF7")        # = DS.PALETTE.TEXT
# The menu icon's tint.
const C_LABEL := Color("#E8EEF7")
const C_BRIGHT := Color("#f3f8fd")
const C_GOOD := Color("#7ec98a")
const C_RED := Color("#e2604a")
const C_AMBER := Color("#e6b34a")
const C_CREAM := Color("#f2e6c8")
const C_TRACK_EDGE := Color("#1c3149")

const DISLOYAL_BELOW := -3.4   # loyalty (−10..+10) under this = disloyal

const CFOIntroPopup := preload("res://scripts/cfo_intro_popup.gd")
const CFO_INTRO_BODY := "I saw we weren't being tax efficient so now I've filed for a tax credit based on our losses. I can only make it work for 5 turns at a time but it should mean we can reduce our tax bill based on recent losses. See, and you worried about keeping me around…"

var _flashing := false
var _bankruptcy_strip: PanelContainer

# Treasury module labels (inside the MoneyWidget Button)
var _net_label: Label
var _runway_label: Label
var _money_inner: HBoxContainer

# Status lamps (spec §1.3), each shown as Building Detail's pilot lamp (_ds2_add_lamp).
# Encyclopedia, the Goods Graph and the Menu carry none.
var _treasury_led: Control
var _power_led: Control
var _victory_led: Control
var _rankings_led: Control

# Power module
var _power_btn: Control

# Mission module
var _quest_btn: Control
## The mission's title and its subtitle, from MiniQuest: the key prints the title, the readout both.
var _quest_title := ""
var _quest_sub := ""
## The missions icon, shown at the slot's left while the mission section is collapsed.
var _quest_icon: Control
## The mission as a key and a piston (scripts/ds2/mission_slot.gd).
var _mission_slot: Control
## The plate that runs down out of the bar under the slot when a mission completes.
var _mission_plate: Control
var _completed_title := ""
var _completed_reward := ""

# Victory module
var _ds2_victory: HBoxContainer   # the score's drum counter and the printed target
var _ds2_victory_counter: Control
var _ds2_victory_target: Label

# Transport module
var _transport_btn: Control
var _store_led: Control      # tiles refusing goods
var _road_led: Control       # links over capacity
var _port_led: Control       # freight riding to market

# Company rankings module
var _rankings_btn: Control
var _rankings_head: Label

## Tech names already posted to the updates dock THIS MATCH -- deliberately not this turn.
## Each is its own row there ("Unlocked: <name>"): a single "N research unlocked" line for
## several techs landing on one turn would name none of them.
##
## Two things make it a match-long gate. TurnBriefing rebuilds its items several times as
## unlocks land, so it has to be per tech rather than a count. And its window is
## [current_turn - 1, current_turn], so an unlock is in the briefing for TWO turns running:
## a gate cleared on turn change would pop every research a second time, one turn
## later. A tech unlocks once, so the set only ever
## needs emptying when a new match starts.
var _research_toasted: Dictionary = {}

# Council module
var _council_btn: Control
## The seats in a line ("2 seated", "1 DISLOYAL"), for the readout.
var _council_status := ""
var _council_led: Control

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


func _ready() -> void:
	# Empty bar space belongs to the HUD too; PASS allowed it to arm map clicks/drags.
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_force_pass_scroll_events = false
	# Deferred so the flyout is rebuilt after the turn's numbers have settled, not mid-resolution.
	TurnManager.turn_resolution_completed.connect(func() -> void: _refresh_open_fly.call_deferred())
	_style_bar()
	_build_treasury()
	_build_power()
	_build_victory()
	_build_transport()
	_build_rankings()
	_build_quest()
	_build_council()
	_build_goods_graph()
	_adopt_encyclopedia_and_turn()
	_build_menu()
	_build_fly_layer()
	_add_bankruptcy_warning()
	_ds2_setup()

	MatchState.money_changed.connect(_on_money_changed)
	MatchState.state_reset.connect(_stockpile_guidance.reset)
	SaveLoad.match_loaded.connect(_stockpile_guidance.reset)
	MatchState.state_reset.connect(_reset_upcoming_notice)
	SaveLoad.match_loaded.connect(_reset_upcoming_notice)
	for event: Signal in [Stockpile.stockpile_changed, TransportState.transport_shipments_changed,
		MatchState.recurring_orders_changed, MatchState.money_changed, LoanState.loans_updated,
		Construction.construction_started, Construction.construction_cancelled, Construction.construction_materials_updated,
		BuildingWorks.building_upgrade_started, BuildingWorks.building_upgrade_cancelled,
		BuildingWorks.building_paused_changed, MatchState.output_stockpile_destination_changed]:
		event.connect(_queue_upcoming_notice)

	MatchState.build_rejected_no_funds.connect(_on_build_rejected_no_funds)
	MatchState.cfo_tax_credit_filed.connect(_on_cfo_tax_credit_filed)
	AdvisorState.advisors_changed.connect(_queue_refresh)
	AdvisorState.advisor_loyalty_changed.connect(func(_id: String, _v: float) -> void: _queue_refresh())
	Production.turn_processed.connect(func(_s: Dictionary) -> void: _queue_refresh())
	CompanyRankings.rankings_updated.connect(_queue_refresh)
	# The research gate is NOT reset here -- see _research_toasted.
	TurnManager.turn_advanced.connect(func(_t: int) -> void: _queue_refresh())
	LoanState.loans_updated.connect(_queue_refresh)
	LoanState.loan_taken.connect(_on_loan_taken)
	TurnManager.turn_resolution_completed.connect(_on_turn_resolved_anomalies)
	VictoryState.score_changed.connect(func(_t: int, _b: Dictionary) -> void: _queue_refresh())
	TurnBriefing.items_changed.connect(_queue_refresh)
	# Decisions and updates live in the bottom-left updates dock, not in a strip.
	TurnBriefing.strip_enabled = false
	get_tree().root.child_entered_tree.connect(_on_notice_root_child_entered)
	call_deferred("_refresh_notices_after_loading")
	resized.connect(queue_redraw)   # the strip spans the live width
	_queue_refresh()


# ── Bar chrome ────────────────────────────────────────────────────────────────

func _style_bar() -> void:
	custom_minimum_size = Vector2(0, BAR_H)
	offset_bottom = BAR_H
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var sb := StyleBoxFlat.new()
	# The ground is the DS2 strip PAINTED in _draw, which carries its own shadow, so the stylebox
	# carries padding only.
	#
	# _draw also paints TOP_BLEED px above y=0 to bury a shimmering 1–3px seam
	# along the very top row (the window is stretched by a non-integer factor — canvas_items
	# + expand, monitor px / 1920×1080 — with pixel-snap off, so the camera nudges that edge
	# sub-pixel every frame).
	sb.bg_color = Color(0, 0, 0, 0)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 4   # modules have no boxes, so they need little room
	sb.content_margin_bottom = 4 + EDGE_H   # keep modules off the beam
	add_theme_stylebox_override("panel", sb)
	# The scene's MarginContainer reserves 276px on the right for the OLD
	# encyclopedia overlay — kill it so the module row spans the full bar.
	var margin := money_widget.get_parent().get_parent() as MarginContainer
	margin.add_theme_constant_override("margin_right", 0)
	var hbox := money_widget.get_parent() as HBoxContainer
	hbox.add_theme_constant_override("separation", 10)

## The strip: the backing's weathered navy steel cropped from the middle of its render, the concrete
## behind the money, and the silver pipes running beneath the bar between the two dividers.
func _draw() -> void:
	var strip: Texture2D = DS2_STRIP
	var tex := strip.get_size()
	var src_w := minf(size.x * DS2_TEXELS, tex.x)
	var src_x := (tex.x - src_w) * 0.5
	draw_texture_rect_region(strip, Rect2(0, 0, size.x, tex.y / DS2_TEXELS), Rect2(src_x, 0, src_w, tex.y))
	# The few pixels above the bar (see TOP_BLEED): the strip's top rows again.
	draw_texture_rect_region(strip, Rect2(0, -TOP_BLEED, size.x, TOP_BLEED), Rect2(src_x, 0, src_w, TOP_BLEED * DS2_TEXELS))
	# The concrete behind the money, on the money's centre line, with its top rows carried above the bar too.
	var slab := DS2_CONCRETE.get_size() / DS2_TEXELS
	var slab_x := roundf(money_widget.get_global_rect().get_center().x - global_position.x - slab.x * 0.5)
	draw_texture_rect(DS2_CONCRETE, Rect2(slab_x, 0, slab.x, slab.y), false)
	draw_texture_rect_region(DS2_CONCRETE, Rect2(slab_x, -TOP_BLEED, slab.x, TOP_BLEED),
		Rect2(0, 0, DS2_CONCRETE.get_width(), TOP_BLEED * DS2_TEXELS))
	# The silver pipes: down at one divider, along beneath the bar, back up at the other.
	var dividers := _ds2_divider_xs()
	if dividers.size() == 2:
		var left := DS2_PIPES_LEFT.get_size() / DS2_TEXELS
		var right := DS2_PIPES_RIGHT.get_size() / DS2_TEXELS
		var lx := dividers[0] - DS2_PIPES_LEFT_AXIS
		var rx := dividers[1] - DS2_PIPES_RIGHT_AXIS
		var run_from := lx + left.x
		var run_w := rx - run_from
		if run_w > 0.0:
			var run_tex := DS2_PIPES_RUN.get_size()
			var run_src_x := (run_tex.x - run_w * DS2_TEXELS) * 0.5
			draw_texture_rect_region(DS2_PIPES_RUN, Rect2(run_from, 0, run_w, run_tex.y / DS2_TEXELS), Rect2(run_src_x, 0, run_w * DS2_TEXELS, run_tex.y))
		for piece: Array in [[DS2_PIPES_LEFT, lx, left], [DS2_PIPES_RIGHT, rx, right]]:
			var tex_p: Texture2D = piece[0]
			var at: float = piece[1]
			var sz: Vector2 = piece[2]
			draw_texture_rect(tex_p, Rect2(at, 0, sz.x, sz.y), false)
			draw_texture_rect_region(tex_p, Rect2(at, -TOP_BLEED, sz.x, TOP_BLEED), Rect2(0, 0, tex_p.get_width(), TOP_BLEED * DS2_TEXELS))

## Modules are flat text on the bar — no outline, no shading (spec §1.2).
## `active` (an open flyout) keeps a fill so the player can see which module the
## panel belongs to; hover gets a fainter one. There is no `warn` red border —
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

func _mini(text: String, color: Color, size: int = 10) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

## Clickable bar module: PanelContainer (sizes to children, unlike Button) that
## emits "pressed" and swaps active chrome. Buttons can't hold containers.
class _ModuleBtn extends PanelContainer:
	signal pressed
	## The readout under the bar says what a tooltip would, so the modules show none.
	func _get_tooltip(_at: Vector2) -> String:
		return ""
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
		# Hover on a flat module is a faint wash, not a box: _module_box paints the
		# active fill, and hover borrows it at low opacity.
		var sb: StyleBoxFlat = _bar._module_box(active, warn)
		if _hover and not active:
			sb.bg_color = Color(1, 1, 1, 0.05)
		add_theme_stylebox_override("panel", sb)
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


# ── Shared icon helpers ────────────────────────────────────────────────────────

## A module-face icon, fitted by its art into a box ICON_CAP tall (or ICON_MAX_W wide, for a wide
## icon) that centres on the module row, so every icon on the bar shares one cap height and one
## midline. An icon with a raised render (DS2_BAR_ICONS) is drawn as that render and its swept
## shadow, as Building Detail's are, the face brightening on hover; one without is drawn as the baked
## PNG itself, catching the bottom menu's specular sheen on hover. Either way a soft glow lights
## behind it on hover. .modulate/.visible on the returned Control reach the art underneath.
## `hover_source`: the Control whose mouse_entered/exited light the icon.
func _bar_icon(tex: Texture2D, hover_source: Control = null) -> Control:
	var fit := _icon_fit(tex)
	var box: Vector2 = fit.box
	var wrap := Control.new()
	wrap.custom_minimum_size = box
	wrap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Glow goes in BEHIND the icon (added first: children draw in add order).
	if hover_source != null:
		var glow := _icon_glow(box)
		wrap.add_child(glow)
		hover_source.mouse_entered.connect(func() -> void: glow.visible = true)
		hover_source.mouse_exited.connect(func() -> void: glow.visible = false)
	if _add_raised_face(wrap, tex, box, hover_source):
		return wrap
	var icon := TextureRect.new()
	icon.texture = tex
	# The expand mode first: until it is set, the texture's own size is the minimum size.
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_SCALE
	var dest: Rect2 = fit.dest
	icon.position = dest.position
	icon.size = dest.size
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
		hover_source.mouse_entered.connect(func() -> void: spec.visible = true)
		hover_source.mouse_exited.connect(func() -> void: spec.visible = false)
	return wrap


## The raised face and its shadow for a bar icon, fitted by the face's own art into the icon's box. False
## when the icon has no raised render.
func _add_raised_face(wrap: Control, tex: Texture2D, box: Vector2, hover_source: Control = null) -> bool:
	var face_name: String = DS2_BAR_ICONS.get(tex.resource_path, "")
	if face_name == "":
		return false
	var face: Texture2D = load("res://assets/ui/bdp_v3/bar_icon_%s.png" % face_name)
	var shadow: Texture2D = load("res://assets/ui/bdp_v3/bar_icon_%s_shadow.png" % face_name)
	var art: Rect2 = BdpV3Indicator.art_rect(face)
	var k: float = minf(box.x / art.size.x, box.y / art.size.y)
	var at := (box - art.size * k) * 0.5 - art.position * k
	var face_rect: TextureRect = null
	for t: Texture2D in [shadow, face]:
		var r := TextureRect.new()
		r.name = "Ds2Shadow" if t == shadow else "Ds2Face"
		r.texture = t
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_SCALE
		r.position = at
		r.size = face.get_size() * k
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wrap.add_child(r)
		face_rect = r
	# Hovered, the raised face brightens, as a Building Detail indicator does.
	if hover_source != null:
		hover_source.mouse_entered.connect(func() -> void: face_rect.modulate = BdpV3Indicator.HOT_MODULATE)
		hover_source.mouse_exited.connect(func() -> void: face_rect.modulate = Color.WHITE)
	return true


## Where a bar icon's canvas is drawn so its art fills the cap: `box` is the art's size on the
## bar, `dest` the whole canvas's rect inside that box.
static func _icon_fit(tex: Texture2D) -> Dictionary:
	var art: Rect2 = BdpV3Indicator.art_rect(tex)
	var k: float = minf(ICON_CAP / art.size.y, ICON_MAX_W / art.size.x)
	k *= float(ICON_OPTICAL.get(tex.resource_path, 1.0))
	var box := (art.size * k).round()
	var at := (box - art.size * k) * 0.5
	return {"box": box, "dest": Rect2(at - art.position * k, tex.get_size() * k)}

## A radial glow (GLOW_TEX) centred on an icon's box, sized GLOW_SCALE larger
## than it so it radiates past the icon's own edges — the ADD-blend "glow behind
## the object" bottom_menu.gd's per-button glow does, generalised to a shared
## texture since these icons don't sit on a disc for a shape-cut glow to read
## against. Hidden by default; the caller wires .visible to hover.
func _icon_glow(box: Vector2) -> TextureRect:
	var glow := TextureRect.new()
	glow.texture = GLOW_TEX
	glow.modulate = GLOW_TINT
	var gs := maxf(box.x, box.y) * GLOW_SCALE
	glow.set_anchors_preset(Control.PRESET_CENTER)
	glow.offset_left = -gs / 2.0
	glow.offset_right = gs / 2.0
	glow.offset_top = -gs / 2.0
	glow.offset_bottom = gs / 2.0
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = mat
	glow.visible = false
	return glow


# ── 1 · Treasury (the MoneyWidget Button, restyled — node path is an e2e contract) ──

func _build_treasury() -> void:
	money_widget.text = ""
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
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 1)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_money_inner.add_child(col)
	# The cash on an LED screen, the £ printed before it and a K or M after it (_ds2_refresh_cash).
	_ds2_cash = HBoxContainer.new()
	_ds2_cash.name = "Ds2Cash"
	_ds2_cash.add_theme_constant_override("separation", 4)
	_ds2_cash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ds2_cash.add_child(_ds2_print("£", DS2_POUND_PX))
	_ds2_cash_holder = Control.new()
	_ds2_cash_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ds2_cash_led = Led.new()
	_ds2_cash_led.scale = Vector2.ONE * DS2_CASH_SCALE
	_ds2_cash_holder.add_child(_ds2_cash_led)
	_ds2_cash.add_child(_ds2_cash_holder)
	_ds2_cash_suffix = _ds2_print("", 18)
	_ds2_cash.add_child(_ds2_cash_suffix)
	col.add_child(_ds2_cash)
	# The profit line and the runway stand in a column to the right of the cash, printed on the concrete.
	_ds2_money_side = VBoxContainer.new()
	_ds2_money_side.name = "Ds2MoneySide"
	_ds2_money_side.alignment = BoxContainer.ALIGNMENT_CENTER
	_ds2_money_side.add_theme_constant_override("separation", 0)
	_ds2_money_side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_money_inner.add_child(_ds2_money_side)
	_net_label = _mini("", DS2_INK_GOOD, 13)
	_runway_label = _mini("", DS2_INK_BAD, DS2_BAR_MIN_PX)
	for label: Label in [_net_label, _runway_label]:
		_ds2_print_on_concrete(label)
		_ds2_money_side.add_child(label)
	money_widget.resized.connect(func() -> void: _ds2_refresh_cash())
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
	row.add_child(_bar_icon(ICON_POWER, mod))
	_hbox().add_child(mod)
	_power_btn = mod
	# Opens the Supply Priority sheet rather than jumping straight to the map overlay; the
	# direct overlay toggle survives as a key on the sheet, see _ds2_fly_power.
	mod.pressed.connect(func() -> void: _toggle_fly("power"))

func _on_power_pressed() -> void:
	# Toggle the Power (power-balance) map overlay directly on the MapMode autoload —
	# the same call the Mapmodes panel's Power row makes. set_sentinel_mode is itself a
	# toggle, and the overlay is driven by MapMode signals (map_overlay.gd), so the
	# Mapmodes panel need not be open for the overlay to appear.
	MapMode.set_sentinel_mode(MapMode.Mode.POWER_BALANCE, MapMode.POWER_SENTINEL)

func _power_stats() -> Dictionary:
	return TopBarStatus.power_stats()


# ── 3 · Victory: the score on a drum counter ────────────────────────────────────

func _build_victory() -> void:
	var mod := _ModuleBtn.new(self)
	mod.name = "VictoryModule"
	mod.custom_minimum_size = Vector2(0, MOD_H)
	var row := _module_row(mod)
	_victory_led = StatusLed.new()
	row.add_child(_victory_led)
	row.add_child(_bar_icon(ICON_VICTORY, mod))
	# The score on a drum counter, the target printed after it ("/1,000").
	_ds2_victory = HBoxContainer.new()
	_ds2_victory.name = "Ds2Victory"
	_ds2_victory.add_theme_constant_override("separation", 4)
	_ds2_victory.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ds2_victory_counter = Counter.new()
	_ds2_victory_counter.call("configure", 4, 0)
	_ds2_victory.add_child(_ds2_victory_counter)
	_ds2_victory_target = _mini("", C_TEXT, 15)
	_ds2_victory.add_child(_ds2_victory_target)
	row.add_child(_ds2_victory)
	mod.pressed.connect(func() -> void: _module_pressed("victory"))
	_hbox().add_child(mod)

## The Victory light: green when MOST tracks have risen against their own recent
## trend (last sample vs ~3 turns back). VictoryState has no "on track to win"
## concept to read instead — the spec's own explicit ruling was "no red condition
## defined" for this module — so this is a momentum read, not a distance-to-bar one
## No red/amber state: unlit simply means "no clear trend
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


# ── 3b · Transport: what is moving, and what is choking ───────────────────

## The three things that can go wrong with logistics, each with its own lamp: storage
## (tiles refusing goods), infrastructure (links over capacity) and freight (shipments
## stuck with nowhere to unload). Splitting them is the point — a single count reads
## '0 units → market' in any game shipping tile-to-tile, which is most of them, and
## would spend the early game reporting nothing at all.
##
## The art is the game's OWN icons, run through the same cleaner the Construct menu uses:
## the navy is keyed out, the artwork trimmed and centred, so they sit on the bar as
## off-white shapes on nothing. Roads and the port are building icons; the warehouse has
## no building behind it, so its cleaned PNG is checked in beside the other UI icons.
const BuildingIcon := preload("res://scripts/building_icon.gd")
## The Power and Transport modules' judgements, shared by their lamps and the hover readouts.
const TopBarStatus := preload("res://scripts/top_bar_status.gd")
## Measures an icon's drawn art (its used rect), cached per texture.
const BdpV3Indicator := preload("res://scripts/bdp_v3_indicator.gd")
const WAREHOUSE_ICON: Texture2D = preload("res://assets/icons/ui_icons/warehouse.png")
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
##
## The icon goes through `_bar_icon`, the same builder Power, Victory, Rankings and Council
## use, so it is fitted to the same cap height, centred on the same midline and lights the
## same way on hover. The lamp centres on that midline too.
func _freight_cell(texture: Texture2D, tip: String, hover_source: Control) -> Dictionary:
	var pair := HBoxContainer.new()
	pair.add_theme_constant_override("separation", FREIGHT_LED_GAP)
	pair.alignment = BoxContainer.ALIGNMENT_CENTER
	pair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pair.tooltip_text = tip
	# LED before the icon — every other module (Power, Victory,
	# Rankings, Council) leads with its lamp, so these three do too.
	var led := StatusLed.new()
	var led_slot := Control.new()
	led_slot.custom_minimum_size = led.get_combined_minimum_size()
	led_slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	led_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	led.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	led_slot.add_child(led)
	pair.add_child(led_slot)
	pair.add_child(_bar_icon(texture, hover_source))
	return {"root": pair, "led": led, "led_slot": led_slot}


func _build_transport() -> void:
	var mod := _ModuleBtn.new(self)
	mod.name = "TransportModule"
	mod.custom_minimum_size = Vector2(0, MOD_H)
	var row := _module_row(mod)
	row.add_theme_constant_override("separation", FREIGHT_PAIR_GAP)
	var store := _freight_cell(WAREHOUSE_ICON, "Storage", mod)
	var road := _freight_cell(_infra_texture("roads"), "Infrastructure", mod)
	var port := _freight_cell(_infra_texture("port"), "Freight to market", mod)
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
	return TopBarStatus.transport_stats()

func _refresh_transport() -> void:
	if _transport_btn == null:
		return
	var status := TopBarStatus.transport()
	# Each lamp owns one failure (TopBarStatus.transport). Splitting them is the point: the single
	# count this replaced read '0 units → market' in any game shipping tile-to-tile, which is most of
	# them, so the module spent the early game reporting nothing at all. The port lamp watches
	# freight stuck on arrival, the one thing that can go wrong after a shipment set off.
	for pair: Array in [[_store_led, status.storage], [_road_led, status.links], [_port_led, status.freight]]:
		var led := pair[0] as StatusLed
		led.color = C_AMBER if str((pair[1] as Dictionary).tone) == "warn" else C_RED
		led.lit = TopBarStatus.lit(pair[1])


# ── 4 · Rankings: player position in the cosmetic company league ────────────

func _build_rankings() -> void:
	var mod := _ModuleBtn.new(self)
	mod.name = "RankingsModule"
	mod.visible = CompanyRankings.available()
	mod.custom_minimum_size = Vector2(0, MOD_H)
	var row := _module_row(mod)
	_rankings_led = StatusLed.new()
	row.add_child(_rankings_led)
	row.add_child(_bar_icon(ICON_RANKINGS, mod))
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	# The player's position only: no movement arrow and no "OF N".
	_rankings_head = _mini(_ordinal(10), C_BRIGHT, 14)
	col.add_child(_rankings_head)
	mod.pressed.connect(func() -> void: _module_pressed("rankings"))
	_hbox().add_child(mod)
	_rankings_btn = mod

func _refresh_rankings() -> void:
	if _rankings_head == null:
		return
	var available := CompanyRankings.available()
	if _rankings_btn != null:
		_rankings_btn.visible = available
	if not available:
		return
	var rows: Array[Dictionary] = CompanyRankings.standings()
	for row: Dictionary in rows:
		if not bool(row.get("is_player", false)):
			continue
		var rank: int = int(row.get("rank", 10))
		_rankings_head.text = _ordinal(rank)
		# Amber warns of an imminent lost place; green marks a safe league lead.
		var at_risk := _ranking_position_at_risk(rows)
		(_rankings_led as StatusLed).color = C_AMBER if at_risk else C_GOOD
		(_rankings_led as StatusLed).lit = at_risk or rank == 1
		return

## Warn when the next rival would overtake if each company's latest revenue
## change continued for one turn. An imminent lost place is amber, not a failure.
func _ranking_position_at_risk(rows: Array[Dictionary]) -> bool:
	for i in range(rows.size() - 1):
		if not bool(rows[i].get("is_player", false)):
			continue
		var player: Dictionary = rows[i]
		var rival: Dictionary = rows[i + 1]
		var player_next := maxf(0.0, float(player.revenue) + float(player.get("revenue_change", 0.0)))
		var rival_next := maxf(0.0, float(rival.revenue) + float(rival.get("revenue_change", 0.0)))
		return rival_next > player_next
	return false

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

func _refresh_victory() -> void:
	var bd: Dictionary = VictoryState.get_breakdown()
	var total := int(bd.get("total", 0))
	var drums: int = Counter.drums_for(float(total), 0, 4)
	if int(_ds2_victory_counter.get("drums")) != drums:
		_ds2_victory_counter.call("configure", drums, 0)
	var shown: float = float(_ds2_victory_counter.get("value"))
	_ds2_victory_counter.call("set_value", float(total), shown)
	_ds2_victory_target.text = "/%s" % _thousands(int(bd.get("win_threshold", 4000)))
	# Green: more than half the tracks rising.
	(_victory_led as StatusLed).color = C_GOOD
	(_victory_led as StatusLed).lit = _victory_trending_up(bd)

## NO TURN FORECAST HERE, DELIBERATELY. Extrapolating a points-per-turn rate from recent
## turns into "N turns until victory" is wrong: Victory has no rate of its own — the tracks
## report where they ARE, not how fast they are moving — so the estimate is a straight-line
## guess over a curve, and the win threshold itself RISES with the turn, which such an
## extrapolation never models. It reads as a promise and is routinely wrong.
## The target printed after the counter is the threshold and nothing else; the counter is the progress.
## Do not introduce an ETA without a real model of the tracks.


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


## Posts each research unlock to the updates dock the first time it appears -- TurnBriefing reads
## the unlocks of the latest turn, which it keeps for two turns.
func _refresh_briefing() -> void:
	var dock := _updates_dock()
	for entry in TurnBriefing.recent_research():
		var tech := str((entry as Dictionary).get("name", ""))
		if tech != "" and not _research_toasted.has(tech):
			_research_toasted[tech] = true
			if dock != null:
				dock.push_research(tech)


# ── 4b · Mission: a key and a piston ──────────────────────────────────────────────

## The modular mission tree (scripts/mini_quest.gd), as a key and a piston (scripts/ds2/mission_slot.gd)
## in its own section between the works and the left pipes. Hidden only while the explicit tutorial coach
## owns the screen; the generic branch is available from the opening campaign turn even when its first
## unlock is still locked.
func _build_quest() -> void:
	var mod := _ModuleBtn.new(self)
	mod.name = "QuestModule"
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 12)
	pad.add_theme_constant_override("margin_right", 12)
	pad.add_theme_constant_override("margin_top", 6)
	pad.add_theme_constant_override("margin_bottom", 6)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mod.add_child(pad)
	# The missions icon at the slot's left, shown while the section is collapsed (_refresh_quest).
	_quest_icon = _bar_icon(ICON_QUEST, mod)
	_quest_icon.visible = false
	_quest_icon.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	pad.add_child(_quest_icon)
	_mission_slot = MissionSlot.new()
	pad.add_child(_mission_slot)
	_mission_slot.celebration_finished.connect(func() -> void: _place_quest.call_deferred())
	# Hovered, the slot shows its mission on the bar's readout, as the other modules do: collapsed,
	# that is the only place the text is.
	mod.mouse_entered.connect(func() -> void:
		if _ds2_readout != null:
			_ds2_hover = mod
			_ds2_show_readout())
	mod.mouse_exited.connect(func() -> void:
		if _ds2_hover == mod:
			_ds2_hover = null
			if _ds2_readout != null:
				_ds2_readout.visible = false)
	Tutorial.opener_finished.connect(_on_opener_finished)
	mod.pressed.connect(func() -> void: _toggle_fly("quest"))
	# TOP-LEVEL, like the bankruptcy strip. The bar is a PanelContainer:
	# an ordinary child is both stretched to fill it AND counted in its minimum size, and measured
	# that took the bar from 64 px tall to 67. Containers skip a top_level child, which fixes the
	# growth and removes any need to re-place it after every sort.
	mod.top_level = true
	add_child(mod)
	_quest_btn = mod
	# The mission keeps inside its own section, between the works and the left pipes, whatever its width.
	mod.resized.connect(func() -> void:
		if _ds2_quest_area.y > _ds2_quest_area.x:
			mod.position.x = roundf(_ds2_quest_area.x)
			var room := _ds2_quest_area.y - _ds2_quest_area.x
			if mod.size.x > room + 0.5:
				mod.size.x = room)
	mod.visible = false
	MiniQuest.quest_changed.connect(_refresh_quest)
	MiniQuest.mission_completed.connect(_on_quest_mission_completed)
	# Refresh when the match snapshot lands: that is the first moment the ruleset (and its
	# start_id) exists, and is_available() resolves the campaign mission surface from it. Connecting
	# HERE — on the bar, not only in MiniQuest — sidesteps a boot race: match_loaded fires during
	# world build, after this bar's _ready, whereas MiniQuest is a deferred autoload that on a
	# fast boot can still be wiring up. Without it the module first appeared on turn 2, because
	# TurnManager emits turn 1's DECIDE before the ruleset is even loaded, so that nudge is lost.
	SaveLoad.match_loaded.connect(_refresh_quest)
	# A different match is a different set of unlocks, so the match-long research gate empties
	# here -- the one place it should.
	SaveLoad.match_loaded.connect(func() -> void: _research_toasted.clear())
	get_viewport().size_changed.connect(_place_quest)
	_refresh_quest()


## A mission landed. The toast MiniQuest raises says WHAT happened; the module — the piston striking
## on the bar — says where. See _celebrate_mission for the sequence itself.
func _on_quest_mission_completed(kind: String, mission_title: String, reward: String) -> void:
	_completed_title = mission_title
	_completed_reward = reward
	_refresh_quest()   # the module may only now be earning its place on the bar
	if _quest_btn == null or not is_instance_valid(_quest_btn) or not _quest_btn.visible:
		return
	_celebrate_mission(kind)


## Sizes the mission to its slot and keeps it inside its own section, between the works and the left
## pipes; top_level, so the container will not touch it. Centred vertically in what the bar actually DRAWS —
## its live height less the beam along the bottom — rather than in BAR_H, which is the offset the bar
## is anchored by and is smaller than the height its styleboxes give it (53 vs a measured 64).
func _place_quest() -> void:
	if _quest_btn == null or not is_instance_valid(_quest_btn) or not _quest_btn.visible or _ds2_left_gap == null:
		return
	_ds2_quest_area = _ds2_quest_span()
	var want_size := _quest_btn.get_combined_minimum_size()
	# The module's own padding round the slot, measured once both are laid out (the pad's margins
	# and the button's content margins).
	var chrome := 24.0
	if _mission_slot.size.x > 1.0 and _quest_btn.size.x > _mission_slot.size.x:
		chrome = _quest_btn.size.x - _mission_slot.size.x
	want_size.x = minf(float(_mission_slot.call("ideal_width")) + chrome, _ds2_quest_area.y - _ds2_quest_area.x)
	_quest_btn.size = want_size
	_quest_btn.position = Vector2(roundf(_ds2_quest_area.x), maxf(0.0, roundf((size.y - EDGE_H - want_size.y) * 0.5)))


# ── DS2 strip (docs/top-bar-ds2-plan.md) ───────────────────────────────────────

const Ds2Light := preload("res://scripts/bdp_v3_light.gd")
## The strip: the backing's weathered navy steel, a riveted steel beam along its foot and its shadow on the map, rendered
## 3840 logical px wide (tools/button_mockup/cluster.html, set `bar`) and cropped from the middle at
## two texels a pixel, so its scratches keep their size on any screen.
const DS2_STRIP: Texture2D = preload("res://assets/ui/bdp_v3/bar_strip.png")
const DS2_TEXELS := 2.0
## The concrete behind the money (set `barconcrete`): a clean light grey slab between two pillars, its top
## off the screen, its foot on the beam, its shadow on the steel round it. Drawn centred on the money.
const DS2_CONCRETE: Texture2D = preload("res://assets/ui/bdp_v3/bar_concrete.png")
## The silver pipe pair (set `barpipes`): down off the screen at the divider after the works, over the
## beam, along beneath the bar, and back up at the divider between the money and Victory. Three pieces:
## the two risers (each lit from the top left, not mirrored) and the run, cropped to the gap between them.
## The axes are the pair's middle in each riser, from layout.json in layout px.
const DS2_PIPES_LEFT: Texture2D = preload("res://assets/ui/bdp_v3/bar_pipes_left.png")
const DS2_PIPES_RIGHT: Texture2D = preload("res://assets/ui/bdp_v3/bar_pipes_right.png")
const DS2_PIPES_RUN: Texture2D = preload("res://assets/ui/bdp_v3/bar_pipes_run.png")
const DS2_PIPES_LEFT_AXIS := 17.87 / 1.875
const DS2_PIPES_RIGHT_AXIS := 41.21 / 1.875
## Room between a divider's middle and the module beside it.
const DS2_PIPES_ROOM := 24.0
## Half the concrete slab's width, pillars included (layout.json: slab 600 layout px), and how far the pipes'
## middle stands off its side.
const DS2_SLAB_HALF := 600.0 / 1.875 * 0.5
const DS2_PIPES_OFF_SLAB := 17.0
## The bar's icons raised as Building Detail's are (set `baricon`): res://assets/ui/bdp_v3/bar_icon_<name>.png
## and its _shadow, by the art they replace.
const DS2_BAR_ICONS := {
	"res://assets/icons/ui_icons/standalone/power_icon.png": "power",
	"res://assets/icons/ui_icons/standalone/trophy.png": "trophy",
	"res://assets/icons/ui_icons/standalone/podium.png": "podium",
	"res://assets/icons/ui_icons/standalone/target.png": "target",
	"res://assets/icons/ui_icons/standalone/board-of-directors.png": "council",
	"res://assets/icons/ui_icons/standalone/sankey.png": "sankey",
	"res://assets/icons/ui_icons/standalone/open-book.png": "book",
	"res://assets/icons/ui_icons/standalone/menu.png": "menu",
	"res://assets/icons/ui_icons/warehouse.png": "warehouse",
	"res://assets/icons/buildings/cleaned/b_005.png": "roads",
	"res://assets/icons/buildings/cleaned/b_004.png": "port",
}
## The outline and shadow that keep a figure standing out on the light concrete.
const DS2_INK_OUTLINE := Color(0.03, 0.05, 0.08, 0.5)
## Cash on an LED screen: the screen's scale on the bar (a full-size screen is taller than a module with
## the net line under it), its cells (scripts/ds2/money_figure.gd), and the figure's colour.
const DS2_CASH_SCALE := 0.75
## The room between the cash's screen and the money module's top and foot.
const DS2_CASH_PAD := 5.0
const DS2_CASH_COLOUR := Color("#f4f6fa")
const DS2_CASH_RED := Color("#e66060")   # DS2 DANGER on dark: the cash below zero
## The profit line and the runway, printed on the light concrete: DS2's inks for light surfaces (the ones
## Building Detail uses on white plastic), darker than the bar's green and red so they hold their contrast.
const DS2_INK_GOOD := Color("#1d6b3a")
const DS2_INK_BAD := Color("#8f1f19")
const Led := preload("res://scripts/bdp_v3_led.gd")
const Counter := preload("res://scripts/bdp_v3_counter.gd")
const Readout := preload("res://scripts/bdp_v3_readout.gd")
const Nine := preload("res://scripts/bdp_v3_nine.gd")
const Heading := preload("res://scripts/bdp_v3_heading.gd")
const SmallKey := preload("res://scripts/bdp_v3_key.gd")
const ModKey := preload("res://scripts/bdp_v3_mod_key.gd")
const Toggle := preload("res://scripts/bdp_v3_toggle.gd")
const Section := preload("res://scripts/bdp_v3_section.gd")
const Plate := preload("res://scripts/bdp_v3_plate.gd")
## The sheet: Building Detail's action sheet shape in the bar's own weathered navy steel, no trim (set
## `barsheet`), nine-sliced. From layout.json in layout px: the render's shadow room and its corner.
const DS2_SHEET: Texture2D = preload("res://assets/ui/bdp_v3/bar_sheet.png")
const DS2_SHEET_MARGIN := 10.0
const DS2_SHEET_CORNER := 60.0
const DS2_SHEET_PAD := 16
const DS2_SHEET_DROP := 12.0
const DS2_SHEET_SECONDS := 0.2
## Figures on dark steel: DS2's OK and DANGER on dark.
const DS2_LED_GOOD := Color("#5bd180")
const DS2_LED_BAD := Color("#e66060")
## The breakdown's screens, smaller than the main figures'.
const DS2_SMALL_LED := 0.8
## The text sizes, Building Detail's: body text 14 px (IBM Plex Sans), metal-label captions 15 px (Barlow
## Condensed) and the printed £ 18 px. The bar itself keeps its compact sizes with DS2_BAR_MIN_PX as the floor.
const DS2_BODY_PX := 14
const DS2_CAPTION_PX := 15
const DS2_POUND_PX := 18
const DS2_BAR_MIN_PX := 12
const DS2_BODY_BOLD: FontFile = preload("res://assets/fonts/IBMPlexSans-SemiBold.ttf")
## The hover readout under the bar: its width and its gap below the bar.
const DS2_READOUT_W := 360.0
const DS2_READOUT_GAP := 8.0
## The bar's lamps: Building Detail's pilot lamp, at its diagnostics rows' scale.
const Ds2Lamp := preload("res://scripts/bdp_v3_lamp.gd")
const MissionSlot := preload("res://scripts/ds2/mission_slot.gd")
const MissionCompletePlate := preload("res://scripts/ds2/mission_complete_plate.gd")
const MissionsPanel := preload("res://scripts/missions_ds2/missions_panel.gd")
const DS2_LAMP_SCALE := 0.72
const MoneyFigure := preload("res://scripts/ds2/money_figure.gd")

## The lamp over the strip (a Node2D, so the bar's container doesn't lay it out); drawn last.
var _ds2_shade: Node2D
## Space before the money, sized so the money sits on the screen's centre line.
var _ds2_left_gap: Control
## The mission's section, as [left, right] screen x: from the works' end to the left pipes.
var _ds2_quest_area := Vector2.ZERO
## For tools and tests: the Transport lamp the readout reads ("storage", "links", "freight"), in place of
## the one under the pointer. Empty in play.
var ds2_readout_cell := ""
## The readout under the bar and the module it is reading.
var _ds2_readout: Control
var _ds2_hover: Control = null
## True while an open flyout is being rebuilt in place (a switch flipped), so it does not drop in again.
var _fly_refreshing := false
## The printed £, the LED screen (in a holder sized to its scale) and the printed K / M after it.
var _ds2_cash: HBoxContainer
var _ds2_cash_led: Control
var _ds2_cash_holder: Control
var _ds2_cash_suffix: Label
## The column to the cash's right that holds the profit line and the runway.
var _ds2_money_side: VBoxContainer


## Lays the bar out on the strip: the works to the left of the money, which sits on the screen's centre
## line, Victory and the office to its right; the lamps, the light across the strip and the hover readouts.
func _ds2_setup() -> void:
	var hbox := _hbox()
	var built: Array[Node] = []
	built.assign(hbox.get_children())
	var flex: Control = null
	for child: Node in built:
		if child.get_class() == "Control" and (child as Control).size_flags_horizontal & Control.SIZE_EXPAND:
			flex = child as Control
			break
	_ds2_left_gap = Control.new()
	_ds2_left_gap.name = "Ds2CentreGap"
	_ds2_left_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(_ds2_left_gap)
	var order: Array[Node] = [_hbox_child("PowerModule"), _hbox_child("TransportModule"), _ds2_left_gap,
		money_widget, flex, _hbox_child("VictoryModule"), _hbox_child("RankingsModule")]
	for child: Node in built.slice(built.find(flex) + 1):
		if not order.has(child):
			order.append(child)
	var at := 0
	for child: Node in order:
		if child != null:
			hbox.move_child(child, at)
			at += 1
	_ds2_shade = Node2D.new()
	_ds2_shade.name = "Ds2Shade"
	_ds2_shade.material = Ds2Light.across_material(Ds2Light.shade_material())
	_ds2_shade.draw.connect(func() -> void: _ds2_shade.draw_rect(Rect2(0, -TOP_BLEED, size.x, size.y + TOP_BLEED), Color.WHITE))
	add_child(_ds2_shade)
	resized.connect(func() -> void:
		(_ds2_shade.material as ShaderMaterial).set_shader_parameter("rect_size", size)
		_ds2_shade.queue_redraw())
	for node: Node in find_children("*", "Control", true, false):
		if node is StatusLed:
			_ds2_add_lamp(node as StatusLed)
	get_tree().node_added.connect(_on_ds2_node_added)
	_ds2_readout = Readout.new()
	_ds2_readout.name = "Ds2Readout"
	# On a CanvasLayer the DS theme is not inherited: without it the detail line's Caption style fell back to
	# the engine's font. With it, the readout reads as Building Detail's does (Plex, 14 px).
	_ds2_readout.theme = DS.theme
	_ds2_readout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ds2_readout.visible = false
	_fly_layer.add_child(_ds2_readout)
	for mod_name: String in DS2_READOUT_MODULES:
		var mod := _hbox_child(mod_name) as Control
		if mod == null:
			continue
		mod.mouse_entered.connect(func() -> void:
			_ds2_hover = mod
			_ds2_show_readout())
		mod.mouse_exited.connect(func() -> void:
			if _ds2_hover == mod:
				_ds2_hover = null
				_ds2_readout.visible = false)
		if mod_name == "TransportModule":
			# One readout per lamp: the cell under the pointer.
			mod.gui_input.connect(func(e: InputEvent) -> void:
				if e is InputEventMouseMotion and _ds2_hover == mod:
					_ds2_show_readout())
	var text_light: Material = Ds2Light.across_material(Ds2Light.text_material())
	for label: Node in find_children("*", "Label", true, false):
		(label as Label).material = text_light
	for node: Node in find_children("*", "CanvasItem", true, false):
		_ds2_light_across(node)
	hbox.resized.connect(_ds2_queue_centre)
	money_widget.resized.connect(_ds2_queue_centre)
	hbox.sort_children.connect(_ds2_queue_centre)
	_ds2_queue_centre()
	_place_quest.call_deferred()


## The modules that show a readout when hovered.
const DS2_READOUT_MODULES := ["MoneyWidget", "PowerModule", "TransportModule", "VictoryModule", "RankingsModule",
	"CouncilModule", "GoodsGraphModule", "EncyclopediaButton", "MenuModule"]


## Shows the hovered module's readout under the bar, centred on the module and kept on the screen.
func _ds2_show_readout() -> void:
	if _ds2_hover == null or _fly_open_id != "":
		_ds2_readout.visible = false
		return
	var r := _ds2_readout_content(_ds2_hover)
	_ds2_readout.call("show_check", str(r.stage), str(r.name), str(r.detail), str(r.tone))
	var at := _ds2_hover.get_global_rect()
	var vw := get_viewport_rect().size.x
	_ds2_readout.size = Vector2(DS2_READOUT_W, Readout.HEIGHT)
	_ds2_readout.position = Vector2(clampf(at.get_center().x - DS2_READOUT_W * 0.5, 12.0, vw - DS2_READOUT_W - 12.0),
		BAR_H + DS2_READOUT_GAP)
	_ds2_readout.visible = true


## What a module's readout says: {stage, name, detail, tone}. Power and Transport come from TopBarStatus,
## as their lamps do; Transport reads the lamp under the pointer. An empty tone shows no lamp (the modules
## that open a view rather than report a state).
func _ds2_readout_content(mod: Control) -> Dictionary:
	match str(mod.name):
		"MoneyWidget":
			var net := Production.net_of(Production.last_turn_summary)
			var borrowed := Production.borrowed_of(Production.last_turn_summary)
			var runway := _runway_turns()
			var detail := "%s%s last turn." % ["+" if net >= 0.0 else "−", _money_text(absf(net))]
			if borrowed > 0.005:
				detail += " %s borrowed." % _money_text(borrowed)
			if runway > 0:
				detail += " About %d turns before cash and borrowing run out." % runway
			else:
				detail += " Loan capacity %s." % _money_text(LoanState.available_capacity())
			var tone := "bad" if (_treasury_led as StatusLed).lit else ("warn" if net < 0.0 else "ok")
			return {"stage": "Treasury", "name": "%s cash" % _money_text(MatchState.money), "detail": detail, "tone": tone}
		"PowerModule":
			var p := TopBarStatus.power()
			return {"stage": "Power", "name": p.name, "detail": p.detail, "tone": p.tone}
		"TransportModule":
			var t := TopBarStatus.transport()
			var cell := "storage"
			var mouse := get_global_mouse_position().x
			for pair: Array in [["links", _road_led], ["freight", _port_led]]:
				var slot := (pair[1] as Control).get_parent() as Control
				if slot != null and mouse >= slot.get_global_rect().position.x - 4.0:
					cell = str(pair[0])
			if ds2_readout_cell != "":
				cell = ds2_readout_cell
			var st: Dictionary = t[cell]
			return {"stage": "Transport", "name": st.name, "detail": st.detail, "tone": st.tone}
		"VictoryModule":
			var bd: Dictionary = VictoryState.get_breakdown()
			return {"stage": "Victory", "name": "%s of %s points" % [_thousands(int(bd.get("total", 0))), _thousands(int(bd.get("win_threshold", 0)))],
				"detail": "To win, score as many points as you can across the five tracks.",
				"tone": "ok" if _victory_trending_up(bd) else "off"}
		"RankingsModule":
			return {"stage": "Rankings", "name": _rankings_head.text if _rankings_head != null else "",
				"detail": "How you rank compared to your competitors in revenue and goods production.", "tone": "off"}
		"CouncilModule":
			return {"stage": "Council", "name": _council_status if _council_status != "" else "Your advisors",
				"detail": "Your advisors, their seats and their loyalty.", "tone": "off"}
		"GoodsGraphModule":
			return {"stage": "", "name": "Goods Graph (G)", "detail": "How every good is made and what it goes into.", "tone": ""}
		"EncyclopediaButton":
			return {"stage": "", "name": "Encyclopedia (X)", "detail": "Every good, building and recipe.", "tone": ""}
		"MenuModule":
			return {"stage": "", "name": "Menu", "detail": "Save, load, settings and quit.", "tone": ""}
		"QuestModule":
			return {"stage": "Mission", "name": _quest_title, "detail": _quest_sub, "tone": ""}
	return {"stage": "", "name": str(mod.name), "detail": "", "tone": "off"}


## The mission's section, as [left, right] screen x: from the works' end to the left pipes.
func _ds2_quest_span() -> Vector2:
	var left := _ds2_left_gap.global_position.x + 8.0
	var transport := _hbox_child("TransportModule") as Control
	if transport != null and transport.visible:
		left = transport.get_global_rect().end.x + DS2_PIPES_ROOM
	var right := _ds2_divider_xs()[0] + global_position.x - DS2_PIPES_ROOM
	return Vector2(left, maxf(left, right))


## A pilot lamp inside a StatusLed, following it: lit in its colour's tone, off when it is off or blinked
## off. The StatusLed stops drawing (self_modulate) and the lamp shows; its visibility, lit state, colour
## and blink stay with the code that already sets them.
func _ds2_add_lamp(led: StatusLed) -> void:
	var lamp: Control = Ds2Lamp.new()
	lamp.name = "Ds2Lamp"
	lamp.lamp_scale = DS2_LAMP_SCALE
	led.add_child(lamp)
	var place := func() -> void:
		lamp.size = lamp.custom_minimum_size
		lamp.position = ((led.size - lamp.size) * 0.5).round()
	led.resized.connect(place)
	place.call()
	led.draw.connect(func() -> void: lamp.call("set_tone", _ds2_lamp_tone(led)))
	led.self_modulate.a = 0.0
	led.queue_redraw()


## The bar is lit from the screen's left edge, not the corner lamp's diagonal: its text, its lights and its
## glows take their share against that light (bdp_v3_light.gd across_material).
func _ds2_light_across(n: Node) -> void:
	var item := n as CanvasItem
	if item == null or not (item.material is ShaderMaterial):
		return
	for base: ShaderMaterial in [Ds2Light.text_material(), Ds2Light.emissive_material(), Ds2Light.glow_material()]:
		if item.material == base:
			item.material = Ds2Light.across_material(base)


func _on_ds2_node_added(n: Node) -> void:
	if is_ancestor_of(n):
		_ds2_light_across(n)


## A StatusLed's state as a pilot lamp's tone, by the hue of its colour.
static func _ds2_lamp_tone(led: StatusLed) -> String:
	if not led.lit or (led.blink and not bool(led.get("_blink_on"))):
		return "off"
	var h := led.color.h
	if h < 0.07 or h > 0.93:
		return "bad"
	return "warn" if h < 0.2 else "ok"


func _hbox_child(node_name: String) -> Node:
	return _hbox().get_node_or_null(node_name)


func _ds2_queue_centre() -> void:
	_ds2_centre_money.call_deferred()


## Sizes the gap before the money so the money's middle is the screen's middle.
func _ds2_centre_money() -> void:
	if _ds2_left_gap == null:
		return
	var hbox := _hbox()
	var sep := float(hbox.get_theme_constant("separation"))
	var centre := get_viewport_rect().size.x * 0.5 - hbox.global_position.x
	var want := maxf(0.0, roundf(centre - money_widget.size.x * 0.5 - sep - _ds2_left_gap.position.x))
	if absf(_ds2_left_gap.custom_minimum_size.x - want) > 0.5:
		_ds2_left_gap.custom_minimum_size.x = want
	_place_quest()
	queue_redraw()   # the concrete follows the money


## Where the silver pipes rise, in the bar's x: just off each side of the concrete, so the run beneath is
## centred on the money. The mission sits outside the left pair, Victory outside the right.
func _ds2_divider_xs() -> Array[float]:
	var c := money_widget.get_global_rect().get_center().x
	var d := DS2_SLAB_HALF + DS2_PIPES_OFF_SLAB
	return [roundf(c - d - global_position.x), roundf(c + d - global_position.x)]


## Text and visibility both come from MiniQuest; the bar never decides either for itself. The key holds
## the title and the piston the count; collapsed, the key goes and the missions icon stands at the left.
func _refresh_quest() -> void:
	if _quest_btn == null or not is_instance_valid(_quest_btn):
		return
	var on: bool = MiniQuest.is_available()
	_quest_btn.visible = on
	if not on:
		if _fly_open_id == "quest":
			_close_fly()
		return
	# MiniQuest decides which of its missions is showing; the bar just renders it — EXCEPT
	# during the completion sequence, which holds the module on the mission that just finished
	# until the piston has struck and it hands over deliberately.
	var kind: String = _quest_celebrating_kind if _quest_celebrating else MiniQuest.active_mission()
	_quest_title = MiniQuest.title(kind)
	_quest_sub = MiniQuest.subtitle(kind)
	var collapsed := PlayerProfile.mission_bar_collapsed
	_quest_icon.visible = collapsed
	_mission_slot.call("set_collapsed", collapsed, _quest_icon.get_combined_minimum_size().x)
	var progress: Vector2i = MiniQuest.progress(kind)
	if _quest_celebrating and progress.y > 1:
		progress.x = progress.y
	_mission_slot.call("set_mission", _quest_title, progress)
	_place_quest.call_deferred()
	if _fly_open_id == "quest" and not _quest_celebrating:
		_refresh_open_fly()


## The opening steps are over: the missions appear and a shine sweeps across them.
func _on_opener_finished() -> void:
	_refresh_quest()
	for i in 6:
		await get_tree().process_frame
	if _mission_slot.is_visible_in_tree():
		_mission_slot.call("shine")


# ── 5 · Council ──────────────────────────────────────────────────────────────────

func _build_council() -> void:
	# Everything from Council rightwards is anchored to the far right edge (the mission is
	# out of the flow, so this is the row's only expander).
	_hbox().add_child(_flex())
	var mod := _ModuleBtn.new(self)
	mod.name = "CouncilModule"
	mod.custom_minimum_size = Vector2(0, MOD_H)
	var row := _module_row(mod)
	_council_led = StatusLed.new()
	_council_led.visible = false   # no lamp: the readout carries the seats
	row.add_child(_council_led)
	row.add_child(_bar_icon(ICON_COUNCIL, mod))
	mod.pressed.connect(func() -> void: _module_pressed("council"))
	_hbox().add_child(mod)
	_council_btn = mod

func _refresh_council() -> void:
	var seated: Array = AdvisorState.advisor_seats.values()
	var disloyal := 0
	var min_loyalty := 999.0
	for aid in seated:
		var lv: float = AdvisorState.advisor_loyalty_value(str(aid))
		if lv <= DISLOYAL_BELOW:
			disloyal += 1
		min_loyalty = minf(min_loyalty, lv)
	if not preload("res://scripts/debug_terminal.gd").demo_is_unlocked():
		disloyal = 0
	(_council_btn as _ModuleBtn).warn = disloyal > 0
	if seated.is_empty():
		_council_status = "no seats filled"
	elif disloyal > 0:
		_council_status = "%d DISLOYAL" % disloyal
	else:
		_council_status = "%d seated" % seated.size()
	if _council_led != null:
		_council_led.visible = false
		var led := _council_led as StatusLed
		led.blink = false
		led.lit = true
		# The lamp's own thresholds — separate from DISLOYAL_BELOW (-3.4), which the status
		# line uses above. An empty seat list leaves min_loyalty at its sentinel, which clears
		# both checks below and reads green — no seats filled is not a problem.
		if min_loyalty < -5.0:
			led.color = C_RED
		elif min_loyalty < 0.0:
			led.color = C_AMBER
		else:
			led.color = C_GOOD


# ── 5b · Goods Graph ─────────────────────────────────────────────────────────────

func _build_goods_graph() -> void:
	var mod := _ModuleBtn.new(self)
	mod.name = "GoodsGraphModule"
	mod.custom_minimum_size = Vector2(0, MOD_H)
	var row := _module_row(mod)
	row.add_child(_bar_icon(ICON_GOODS_GRAPH, mod))
	mod.pressed.connect(func() -> void:
		_close_fly()
		MatchState.goods_graph_requested.emit())
	_hbox().add_child(mod)


# ── 6/7/8 · Encyclopedia (adopted) · Turn/date · Menu ───────────────────────────

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
		for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
			enc.add_theme_stylebox_override(state, _module_box(state != "normal", false))
		# The book icon inside the button, in a full-rect inner row (Buttons don't size to child
		# containers — min width is synced in _apply_refresh).
		enc.text = ""
		_enc_inner = HBoxContainer.new()
		_enc_inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_enc_inner.alignment = BoxContainer.ALIGNMENT_CENTER
		_enc_inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		enc.add_child(_enc_inner)
		_enc_inner.add_child(_bar_icon(ICON_ENCYCLOPEDIA, enc))
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
		_date_label = _mini("", C_TEXT, 12)
		_date_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_date_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(_date_label)
	if hitbox != null:
		hitbox.visible = false

## Turn → month + year. One month per turn, but the year is the COMPANY'S year, not a
## calendar one: "January Year 1" through "December Year 25" over a
## 300-turn campaign, and into Year 9 by the demo's turn 100. A real calendar year would
## imply a period the sim does not simulate.
const _MONTHS: Array[String] = ["January", "February", "March", "April", "May", "June",
	"July", "August", "September", "October", "November", "December"]

func _turn_date(turn: int) -> String:
	return "%s Year %d" % [_MONTHS[(turn - 1) % 12], 1 + (turn - 1) / 12]

func _build_menu() -> void:
	var mod := _ModuleBtn.new(self)
	mod.name = "MenuModule"
	mod.custom_minimum_size = Vector2(0, MOD_H)
	var row := _module_row(mod)
	var icon := _bar_icon(ICON_MENU, mod)
	icon.modulate = C_LABEL
	row.add_child(icon)
	mod.pressed.connect(func() -> void:
		_close_fly()
		PauseMenu.open(get_parent()))
	_hbox().add_child(mod)


# ── Flyouts (Treasury · Power · Missions), steel sheets under their modules ─────

## The modules that open a sheet under the bar. Victory, Council and Rankings open panels of their own
## (_module_pressed).
const FLYOUTS := ["treasury", "power", "quest"]

## While true, the module holds the finished mission and nothing rebuilds the missions sheet.
var _quest_celebrating := false
var _quest_celebrating_kind := ""


## The missions sheet's last row: a slide switch that collapses the bar's mission to its icon and counter.
func _mission_collapse_row(inner: int) -> Control:
	var row := HBoxContainer.new()
	row.name = "MissionCollapseRow"
	row.custom_minimum_size = Vector2(inner, 0)
	row.add_theme_constant_override("separation", 8)
	# The label stands right beside its switch, so the two read as one control.
	var label := _quest_label("Collapse mission section in the top bar", C_TEXT, 13, false)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	var toggle: Control = Toggle.new()
	toggle.name = "MissionCollapseToggle"
	toggle.call("set_right", PlayerProfile.mission_bar_collapsed)
	toggle.tooltip_text = "Show only the missions icon and the counter. The mission shows when you hover over it."
	toggle.connect("toggled", func(on: bool) -> void:
		PlayerProfile.set_mission_bar_collapsed(on)
		_refresh_quest())
	row.add_child(toggle)
	return row


## Off-white by default and never anything quieter (CLAUDE.md); IGNORE so a click reaches the row.
func _quest_label(text: String, color: Color, pt: int, wrap: bool) -> Label:
	var l := _mini(text, color, pt)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## The completion: the piston strokes across with steam, the key changes to the next mission, and the
## piston snaps back (scripts/ds2/mission_slot.gd), while a plate runs down under the slot naming the
## mission and its reward. The module itself neither fills nor ticks.
func _celebrate_mission(kind: String) -> void:
	if _quest_btn == null or not is_instance_valid(_quest_btn) or not _quest_btn.visible:
		return
	_quest_celebrating = true
	_quest_celebrating_kind = kind
	_refresh_quest()   # the piston shows the finished mission's count in full
	# The plate runs down under the slot; the piston holds at the end of its stroke until the plate goes back.
	if _mission_plate == null or not is_instance_valid(_mission_plate):
		_mission_plate = MissionCompletePlate.new()
		add_child(_mission_plate)
	var slot_rect: Rect2 = _mission_slot.get_global_rect()
	var runs: float = _mission_plate.call("play", _completed_title, _completed_reward, slot_rect.get_center().x,
		global_position.y + size.y - EDGE_H)
	_mission_slot.call("celebrate", func() -> void:
		_quest_celebrating = false
		_quest_celebrating_kind = ""
		_refresh_quest(), maxf(0.35, runs - MissionCompletePlate.RETRACT_SEC - 0.55))


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
	_fly_refreshing = true
	_close_fly()
	_open_fly(id)
	_fly_refreshing = false


## Victory and Council open their full panels, and Rankings its own panel.
func _module_pressed(id: String) -> void:
	_close_fly()
	if _ds2_readout != null:
		_ds2_readout.visible = false
	if id == "victory":
		victory_widget_clicked.emit()
	elif id == "council":
		council_widget_clicked.emit()
	elif id == "rankings":
		_toggle_rankings_panel()


func _close_fly() -> void:
	_fly_open_id = ""
	_fly_scrim.visible = false
	if _fly_panel != null and is_instance_valid(_fly_panel):
		if _fly_panel.get_parent() != null:
			_fly_panel.get_parent().remove_child(_fly_panel)
		_fly_panel.queue_free()
	_fly_panel = null
	_fly_open_id = ""
	if _rankings_btn != null:
		(_rankings_btn as _ModuleBtn).active = false
	if _quest_btn != null and is_instance_valid(_quest_btn):
		(_quest_btn as _ModuleBtn).active = false
	if _power_btn != null and is_instance_valid(_power_btn):
		(_power_btn as _ModuleBtn).active = false

func _open_fly(id: String) -> void:
	if not id in FLYOUTS:
		return
	if _ds2_readout != null:
		_ds2_readout.visible = false   # the sheet says more than the readout
	if id == "treasury" and _fly_open_id != id:
		TelemetryState.track_interaction("money_panel_opened", "treasury")
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
	_fly_panel.name = "Flyout_%s" % id   # stable target (tutorial spotlight / e2e)
	_ds2_sheet_frame(_fly_panel)
	_fly_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 0)
	_fly_panel.add_child(vb)
	var anchor: Control = money_widget
	match id:
		"treasury":
			# This is the compact money sheet. Keep it distinct from the
			# full Money panel, which the keys below open.
			_fly_panel.custom_minimum_size = Vector2(600, 0)
			vb.add_child(_ds2_sheet_head("Treasury"))
			_ds2_fly_treasury(vb)
		"power":
			_fly_panel.custom_minimum_size = Vector2(380, 0)
			vb.add_child(_ds2_sheet_head("Power"))
			_ds2_fly_power(vb)
			anchor = _power_btn
			(_power_btn as _ModuleBtn).active = true
		"quest":
			# The missions panel, one mimic board per tab.
			vb.add_child(_ds2_sheet_head("Missions"))
			vb.add_child(MissionsPanel.new())
			vb.add_child(_mission_collapse_row(int(MissionsPanel.WIDTH)))
			anchor = _quest_btn
			(_quest_btn as _ModuleBtn).active = true
	_fly_layer.add_child(_fly_panel)
	# Position after layout: centred under the module, clamped to the viewport.
	var place := func() -> void:
		if _fly_panel == null or not is_instance_valid(_fly_panel):
			return
		# CanvasLayer children do not participate in a parent Container layout.
		# Give the sheet its measured content height explicitly, otherwise it
		# retains the viewport height and leaves an empty panel below its actions.
		_fly_panel.size = _fly_panel.get_combined_minimum_size()
		var vw := get_viewport().get_visible_rect().size.x
		var x := anchor.get_global_rect().get_center().x - _fly_panel.size.x * 0.5
		x = clampf(x, 8.0, vw - _fly_panel.size.x - 8.0)
		_fly_panel.global_position = Vector2(x, BAR_H + 8.0)
		if not _fly_refreshing:
			# The sheet drops a little into place from under the bar.
			_fly_panel.position.y -= DS2_SHEET_DROP
			_fly_panel.modulate.a = 0.0
			var t := _fly_panel.create_tween().set_parallel(true)
			t.tween_property(_fly_panel, "position:y", _fly_panel.position.y + DS2_SHEET_DROP, DS2_SHEET_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			t.tween_property(_fly_panel, "modulate:a", 1.0, DS2_SHEET_SECONDS * 0.7)
	place.call_deferred()

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

## Shows a tab of the Rankings panel; with the panel shut, it opens on that tab next time.
func _set_rankings_tab(tab: String) -> void:
	if tab == _rankings_tab:
		return
	_rankings_tab = tab
	if _rankings_panel != null and is_instance_valid(_rankings_panel) and _rankings_panel.visible:
		_fill_rankings_panel()


# ── Rankings panel: the league as a panel of its own ───────────────────────────

## The Rankings panel: docked at the left under the bar, as the Market panel is, closing on Esc. It holds
## two tables (revenue and goods), in a panel sized to stop above the bottom menu.
var _rankings_panel: PanelContainer
const RANKINGS_PANEL_W := 600.0
## Room kept below the panel for the bottom menu.
const RANKINGS_PANEL_BOTTOM := 120.0


func _toggle_rankings_panel() -> void:
	if _rankings_panel != null and is_instance_valid(_rankings_panel) and _rankings_panel.visible:
		_close_rankings_panel()
	else:
		_open_rankings_panel()


func _open_rankings_panel() -> void:
	if not CompanyRankings.available():
		return
	_close_fly()
	if _rankings_panel == null or not is_instance_valid(_rankings_panel):
		_rankings_panel = PanelContainer.new()
		_rankings_panel.name = "RankingsPanel"
		_rankings_panel.theme = DS.theme
		_rankings_panel.theme_type_variation = "Card"
		_rankings_panel.mouse_filter = Control.MOUSE_FILTER_STOP
		var host: Control = get_parent().get_node_or_null("HUDContent") as Control
		(host if host != null else get_parent()).add_child(_rankings_panel)
		_rankings_panel.visibility_changed.connect(func() -> void:
			if not _rankings_panel.visible:
				PanelStack.remove(_rankings_panel)
				if _rankings_btn != null:
					(_rankings_btn as _ModuleBtn).active = false)
	_fill_rankings_panel()
	_rankings_panel.visible = true
	(_rankings_btn as _ModuleBtn).active = true
	PanelStack.push(_rankings_panel)


func _close_rankings_panel() -> void:
	if _rankings_panel != null and is_instance_valid(_rankings_panel):
		_rankings_panel.visible = false


## Builds the panel's content for the tab showing and fits it between the bar and the bottom menu.
func _fill_rankings_panel() -> void:
	for child: Node in _rankings_panel.get_children():
		_rankings_panel.remove_child(child)
		child.queue_free()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 0)
	_rankings_panel.add_child(vb)
	var head := HBoxContainer.new()
	var pad := MarginContainer.new()
	for side: String in ["left", "right"]:
		pad.add_theme_constant_override("margin_" + side, 14)
	pad.add_theme_constant_override("margin_top", 10)
	pad.add_child(head)
	var title := Label.new()
	title.theme_type_variation = "Title"
	title.text = "Company rankings"
	head.add_child(title)
	head.add_child(_flex())
	var close := Button.new()
	close.name = "RankingsCloseButton"
	close.text = "✕"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(_close_rankings_panel)
	head.add_child(close)
	vb.add_child(pad)
	_fly_scroll = null
	_fly_rankings(vb)
	var scroll := _fly_scroll
	_fly_scroll = null
	var place := func() -> void:
		if _rankings_panel == null or not is_instance_valid(_rankings_panel):
			return
		var vh: float = get_viewport().get_visible_rect().size.y
		var top: float = BAR_H + 12.0
		var room: float = vh - top - RANKINGS_PANEL_BOTTOM
		_rankings_panel.custom_minimum_size = Vector2(RANKINGS_PANEL_W, 0)
		_rankings_panel.size = _rankings_panel.get_combined_minimum_size()
		if _rankings_panel.size.y > room and scroll != null and is_instance_valid(scroll):
			scroll.custom_minimum_size.y = maxf(FLY_LIST_MIN_H * 0.5, scroll.custom_minimum_size.y - (_rankings_panel.size.y - room))
			_rankings_panel.size = _rankings_panel.get_combined_minimum_size()
		_rankings_panel.global_position = Vector2(16.0, top)
	place.call_deferred()

## How tall a rankings list may be before it scrolls: everything between the bar and the bottom
## of the screen, less this panel's own chrome (title, tabs, column headings) and a margin.
##
## A CONSTANT will not do here. At nine rivals the revenue table fitted on any screen; at
## nineteen it is twenty rows deep and ran off the bottom of a 1440 px display with ranks 13–20
## unreachable — and a constant chosen to fit 1080p would waste half of a taller one.
const FLY_LIST_CHROME := 260.0
const FLY_LIST_MIN_H := 360.0

func _fly_list_height() -> float:
	var vp := get_viewport()
	var vh: float = vp.get_visible_rect().size.y if vp != null else 1080.0
	return maxf(FLY_LIST_MIN_H, vh - FLY_LIST_CHROME)


## The scroller of the rankings list being built, so _fill_rankings_panel's deferred placement can
## hand back any height the panel overshot the screen by.
var _fly_scroll: ScrollContainer = null

## A scroller sized by _fly_list_height, with the list inside it. Both rankings tabs use it: the
## goods tab has always been longer than the screen, and the revenue tab now is too.
##
## _fly_list_height is only an OPENING BID — it subtracts an ESTIMATE of this panel's chrome,
## and an estimate is what left the revenue table hanging off the bottom of a 1440 px screen
## with its last rows unreachable. The correction is measured in _fill_rankings_panel's placement,
## once the panel has a real rect.
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
	hint.text = "REVENUE LAST TURN AND OVER THE LAST 5 TURNS"
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
	hint.text = "THE TOP 3 PRODUCERS OF EACH GOOD AND YOUR OUTPUT LAST TURN. ONLY YOU MAKE APEX GOODS."
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
	# read as chrome. Same art, same cream, rounded corners, no rim.
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

# ── The steel sheets (Treasury, Power) ──────────────────────────────────────────

## A flyout as Building Detail's steel sheet: the plate painted behind its content, the content inset
## inside the plate's trim.
func _ds2_sheet_frame(panel: PanelContainer) -> void:
	var bare := StyleBoxEmpty.new()
	bare.set_content_margin_all(DS2_SHEET_PAD)
	panel.add_theme_stylebox_override("panel", bare)
	panel.theme = DS.theme
	panel.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	panel.draw.connect(func() -> void:
		Nine.paint(panel, DS2_SHEET, Rect2(Vector2.ZERO, panel.size).grow(DS2_SHEET_MARGIN / 1.875),
			(DS2_SHEET_MARGIN + DS2_SHEET_CORNER) * 2.0 / 1.875))


## The sheet's head: its name in raised lettering and Building Detail's close key.
func _ds2_sheet_head(title: String) -> Control:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	if Heading.can_show(title.to_upper()):
		var h: Control = Heading.new()
		h.set("text", title.to_upper())
		head.add_child(h)
	else:
		head.add_child(_ds2_text(title.to_upper(), 16))
	head.add_child(_flex())
	var close: TextureButton = SmallKey.make("close", 26.0)
	close.name = "FlyCloseKey"
	close.pressed.connect(_close_fly)
	head.add_child(close)
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 8)
	wrap.add_child(head)
	return wrap


## White text on the steel with the embossed shadow (DS2 rule 3).
func _ds2_text(text: String, font_px: int = 13) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_px)
	l.add_theme_color_override("font_color", DS.PALETTE.TEXT)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## A small caption in the metal-label capitals.
func _ds2_caption(text: String) -> Label:
	var l := _ds2_text(text.to_upper(), DS2_CAPTION_PX)
	l.add_theme_font_override("font", Plate.FONT_SEMI)
	return l


## A money figure: the £ printed, the figure on an LED screen padded to `digits` cells so a column's
## screens are one width. Shown at `k` of full size.
func _ds2_money_screen(amount: float, colour: Color, digits: int, k: float = 1.0) -> Control:
	var hb := HBoxContainer.new()
	hb.name = "MoneyLed"
	hb.add_theme_constant_override("separation", 3)
	hb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var pound := _ds2_caption("£")
	pound.add_theme_font_size_override("font_size", roundi(DS2_POUND_PX * k))
	hb.add_child(pound)
	var figure := "%.2f" % amount
	var led: Control = Led.new()
	led.call("set_figure", " ".repeat(maxi(0, digits - Led.cells_for(figure).size())) + figure, colour)
	if is_equal_approx(k, 1.0):
		hb.add_child(led)
	else:
		var holder := Control.new()
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		led.scale = Vector2.ONE * k
		holder.add_child(led)
		holder.custom_minimum_size = (led.get_combined_minimum_size() * k).ceil()
		led.size = led.get_combined_minimum_size()
		hb.add_child(holder)
	return hb


## A named row on the sheet: its label at the left, its figure's screen at the right.
func _ds2_money_row(label: String, amount: float, colour: Color, digits: int, row_name: String = "", k: float = 1.0) -> HBoxContainer:
	var row := HBoxContainer.new()
	if row_name != "":
		row.name = row_name
	row.add_theme_constant_override("separation", 8)
	var l := _ds2_text(label, DS2_BODY_PX)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(l)
	row.add_child(_ds2_money_screen(amount, colour, digits, k))
	return row


## A keycap on the sheet that is a real Button (the tutorial and the e2e press these by name): Building
## Detail's wide worn key, its label printed on it, pressing down while held.
func _ds2_key_button(text: String, button_name: String) -> Button:
	var b := Button.new()
	b.name = button_name
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var key: Control = ModKey.new()
	key.set("openable", false)
	key.set("summary", text)
	key.set("centred", true)
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	key.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.add_child(key)
	b.custom_minimum_size = Vector2(0, key.custom_minimum_size.y)
	b.button_down.connect(func() -> void: key.call("set_open", true))
	b.button_up.connect(func() -> void: key.call("set_open", false))
	return b


## A darker plate on the sheet for one group of figures: Building Detail's dark metal plate on its own
## (BdpV3Section "slab": cropped, not stretched, no steel rim), with Building Detail's silver screws set in
## near its corners. Returns where its rows go.
func _ds2_sub_plate(parent: Control, plate_name: String) -> VBoxContainer:
	var plate: MarginContainer = Section.new()
	plate.name = plate_name
	plate.set("style", "slab")
	parent.add_child(plate)
	var rows: VBoxContainer = plate.get("content")
	rows.add_theme_constant_override("separation", 8)
	return rows


## The Treasury on its steel sheet: the same figures and actions as the flyout, on screens and keys, in
## three darker plates (cash, the turn's money in and out, loans) with the actions below them.
func _ds2_fly_treasury(vb: VBoxContainer) -> void:
	var s: Dictionary = Production.last_turn_summary
	var net := Production.net_of(s)
	var borrowed := Production.borrowed_of(s)
	var sheet := VBoxContainer.new()
	sheet.add_theme_constant_override("separation", 10)
	vb.add_child(sheet)
	var body := _ds2_sub_plate(sheet, "FlyPlateCash")
	var runway := _runway_turns()
	var main_figures := [MatchState.money, net, LoanState.available_capacity()]
	var digits := 0
	for f: float in main_figures:
		digits = maxi(digits, Led.cells_for("%.2f" % f).size())
	body.add_child(_ds2_money_row("Cash on hand", MatchState.money, DS2_CASH_RED if MatchState.money < 0.0 else DS2_CASH_COLOUR, digits, "FlyRowCash"))
	body.add_child(_ds2_money_row("Net last turn", net, DS2_LED_GOOD if net >= 0.0 else DS2_LED_BAD, digits, "FlyRowNet"))
	if borrowed > 0.005:
		var borrowed_row := _ds2_money_row("Borrowed last turn", borrowed, DS2_CASH_COLOUR, digits, "FlyRowBorrowed")
		borrowed_row.set_meta("cash_amount", borrowed)
		body.add_child(borrowed_row)
	if runway > 0:
		var rw := HBoxContainer.new()
		rw.name = "FlyRowRunway"
		var rl := _ds2_text("Runway at current burn", DS2_BODY_PX)
		rl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rw.add_child(rl)
		rw.add_child(_ds2_text("About %d turns" % runway, DS2_BODY_PX))
		body.add_child(rw)
	var upcoming := preload("res://scripts/cash_commitments_view.gd").make_link(func() -> void: _open_money_panel_tab("Upcoming"))
	upcoming.name = "FlyUpcomingButton"
	preload("res://scripts/cash_commitments_view.gd").update_link(upcoming, preload("res://scripts/cash_commitments.gd").snapshot())
	body.add_child(upcoming)
	# Cash in and costs, side by side, on smaller screens.
	body = _ds2_sub_plate(sheet, "FlyPlateTurn")
	var revenue := [
		["Goods sold", float(s.get("goods_sales_revenue", 0.0))],
		["Power sold", float(s.get("power_sales_revenue", 0.0))],
		["Green subsidy", float(s.get("green_subsidy_received", 0.0))],
	]
	var costs := [
		["Operating costs", float(s.get("maintenance_paid", 0.0)) + float(s.get("labour_paid", 0.0)) + float(s.get("advisor_paid", 0.0))],
		["Power bought", float(s.get("power_purchase_cost", 0.0))],
		["Transport costs", float(s.get("transport_paid", 0.0))],
		["Goods purchased", float(s.get("goods_purchased_cost", 0.0))],
		["Warehousing", float(s.get("warehousing_paid", 0.0))],
		["Opening costs", float(s.get("one_off_paid", 0.0))],
		["Loan repayments", float(s.get("interest_paid", 0.0))],
		["Taxes and dividends", float(s.get("taxes_paid", 0.0)) + float(s.get("dividends_paid", 0.0))],
		["Carbon tax", float(s.get("carbon_tax_paid", 0.0))],
		["Profit sharing", float(s.get("profit_sharing_paid", 0.0))],
	]
	var small := 0
	for entry: Array in revenue + costs:
		if float(entry[1]) > 0.005:
			small = maxi(small, Led.cells_for("%.2f" % float(entry[1])).size())
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	for spec: Array in [["Cash in & credits", revenue, DS2_LED_GOOD], ["Costs", costs, DS2_LED_BAD]]:
		var column := VBoxContainer.new()
		column.name = "%sColumn" % str(spec[0])
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation", 4)
		column.add_child(_ds2_caption(str(spec[0]).replace("&", "and")))
		var any := false
		for entry: Array in spec[1]:
			if float(entry[1]) <= 0.005:
				continue
			any = true
			var row := _ds2_money_row(str(entry[0]), float(entry[1]), spec[2], small, "", DS2_SMALL_LED)
			row.set_meta("cash_amount", float(entry[1]) if spec[2] == DS2_LED_GOOD else -float(entry[1]))
			column.add_child(row)
		if not any:
			column.add_child(_ds2_text("None last turn", DS2_BODY_PX))
		columns.add_child(column)
	body.add_child(columns)
	# Loans.
	body = _ds2_sub_plate(sheet, "FlyPlateLoans")
	body.add_child(_ds2_caption("Loans"))
	for l in LoanState.loans:
		var lrow := _ds2_money_row(LoanState.loan_label(l), LoanState.payoff_amount(l), DS2_CASH_COLOUR, digits, "", DS2_SMALL_LED)
		body.add_child(lrow)
		body.add_child(_ds2_text(LoanState.repayment_label(l), DS2_BODY_PX))
	if LoanState.loans.is_empty():
		body.add_child(_ds2_text("No loans outstanding.", DS2_BODY_PX))
	body.add_child(_ds2_money_row("Loan capacity", LoanState.available_capacity(), DS2_CASH_COLOUR, digits, "FlyRowLoanCapacity"))
	if LoanState.transit_credit_available():
		var rate_pct := LoanState.transit_credit_rate_per_turn() * 100.0
		var tcrow := _ds2_money_row("Transit credit on the road", LoanState.transit_credit_balance, DS2_CASH_COLOUR, digits, "FlyRowTransitCredit", DS2_SMALL_LED)
		body.add_child(tcrow)
		var toggle := _ds2_key_button("Advance port sales: %s" % ("On" if LoanState.transit_credit_enabled else "Off"), "FlyTransitCreditToggle")
		toggle.tooltip_text = "Port sales are paid when the goods reach the port. With this on, the bank pays you when they leave and charges %.2f%%/turn on what is still on the road. Turn it off to wait for payment and save the interest." % rate_pct
		toggle.pressed.connect(func() -> void:
			LoanState.set_transit_credit_enabled(not LoanState.transit_credit_enabled)
			_refresh_open_fly())
		body.add_child(toggle)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	for spec: Array in [["Take loan", "FlyTakeLoanButton", "Loans"], ["Balance", "FlyBalanceButton", "Balance"], ["Charts", "FlyChartsButton", "Charts"]]:
		var key := _ds2_key_button(str(spec[0]), str(spec[1]))
		var tab := str(spec[2])
		key.pressed.connect(func() -> void: _open_money_panel_tab(tab))
		actions.add_child(key)
	sheet.add_child(actions)


## Power on its steel sheet: where each kind of generation's power goes, on Building Detail's slide
## switches (Grid at the left, your buildings at the right), and a key for the power map.
func _ds2_fly_power(vb: VBoxContainer) -> void:
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	vb.add_child(body)
	for spec: Array in [
			["coal_gas", "Coal and gas", MatchState.power_priority_coal_gas,
				"Your coal and gas plants run first. The grid only covers what they cannot.",
				"Your coal and gas output is sold to the grid. Your buildings buy grid power instead."],
			["wind_solar", "Wind and solar", MatchState.power_priority_wind_solar,
				"Your wind and solar run first. Buildings can be cut short when it is not generating.",
				"Your wind and solar output is sold to the grid. Your buildings draw steady grid power instead."]]:
		var kind: String = spec[0]
		var own: bool = str(spec[2]) == "self"
		var block := VBoxContainer.new()
		block.name = "FlyPriority_%s" % kind
		block.add_theme_constant_override("separation", 4)
		var title := _ds2_text(str(spec[1]), DS2_BODY_PX)
		title.add_theme_font_override("font", DS2_BODY_BOLD)
		block.add_child(title)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.add_child(_ds2_caption("Grid"))
		var sw: Control = Toggle.new()
		sw.name = "FlyPrioritySwitch_%s" % kind
		sw.call("set_right", own)
		sw.connect("toggled", func(right: bool) -> void:
			MatchState.set_power_priority(kind, "self" if right else "grid")
			_refresh_open_fly())
		row.add_child(sw)
		row.add_child(_ds2_caption("Your buildings"))
		block.add_child(row)
		var detail := _ds2_text(str(spec[3]) if own else str(spec[4]), DS2_BODY_PX)
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail.custom_minimum_size.x = 320
		block.add_child(detail)
		body.add_child(block)
	var map_key := _ds2_key_button("Power balance map", "FlyPowerMapButton")
	map_key.pressed.connect(func() -> void:
		_close_fly()
		_on_power_pressed())
	body.add_child(map_key)


func _open_money_panel_tab(tab_name: String) -> void:
	_close_fly()
	money_panel_tab_requested.emit(tab_name)

func _runway_turns() -> int:
	var s: Dictionary = Production.last_turn_summary
	var net := Production.net_of(s)
	if net >= 0.0 or s.is_empty():
		return 0
	var turns := int(floor((MatchState.money + LoanState.available_capacity()) / -net))
	return turns if turns <= 12 else 0   # only surface when it's actually alarming

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
		_enc_button.custom_minimum_size = Vector2(_enc_inner.get_combined_minimum_size().x + 28.0, MOD_H)
	_refresh_bankruptcy_warning()
	if _upcoming_notice_dirty and not TurnManager.is_resolving and not Tutorial.active:
		_refresh_money_notices()

## A figure printed on the strip beside a screen (the £ before the cash, its K or M after): white with a
## dark shadow down and to the right, standing off the lacquer.
func _ds2_print(text: String, font_px: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_px)
	l.add_theme_color_override("font_color", DS2_CASH_COLOUR)
	_ds2_ink(l)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Dark ink printed on the light concrete: no outline, a faint light shadow below so it reads as printed
## into the surface.
func _ds2_print_on_concrete(label: Label) -> void:
	label.add_theme_color_override("font_shadow_color", Color(1, 1, 1, 0.35))
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", 1)


## A dark outline and a shadow down and to the right, so a figure stands out on the strip.
func _ds2_ink(label: Label) -> void:
	label.add_theme_color_override("font_outline_color", DS2_INK_OUTLINE)
	label.add_theme_constant_override("outline_size", 1)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	label.add_theme_constant_override("shadow_outline_size", 2)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)


## The cash on the LED screen, always five cells (blank ones unlit) so the screen never changes width. The
## screen takes the money module's height, DS2_CASH_PAD clear of its top and its foot.
func _ds2_refresh_cash(colour: Color = Color(0, 0, 0, 0)) -> void:
	if colour.a == 0.0:
		colour = DS2_CASH_RED if MatchState.money < 0.0 else DS2_CASH_COLOUR
	var parts: Dictionary = MoneyFigure.led(MatchState.money)
	var figure: String = parts.figure
	figure = " ".repeat(maxi(0, MoneyFigure.MAX_CELLS - MoneyFigure.cells(figure))) + figure
	_ds2_cash_led.call("set_figure", figure, colour)
	# Five cells, the point one of them (the owner's screen rule).
	var full := Vector2(Led.width_for_cells(MoneyFigure.MAX_CELLS), Led.CELL.y + 2.0 * Led.PAD.y + 2.0 * Led.RIM / Led.CAPTURE_SCALE)
	_ds2_cash_led.custom_minimum_size = full
	_ds2_cash_led.size = full
	var k := DS2_CASH_SCALE
	if money_widget != null and money_widget.size.y > 2.0 * DS2_CASH_PAD:
		k = (money_widget.size.y - 2.0 * DS2_CASH_PAD) / full.y
	_ds2_cash_led.scale = Vector2.ONE * k
	_ds2_cash_holder.custom_minimum_size = (full * k).round()
	_ds2_cash_suffix.text = str(parts.suffix)
	_ds2_cash_suffix.visible = str(parts.suffix) != ""
	_ds2_cash_led.tooltip_text = _money_text(MatchState.money)


func _refresh_treasury() -> void:
	_ds2_refresh_cash()
	var s: Dictionary = Production.last_turn_summary
	var net := Production.net_of(s)
	_net_label.text = ("+" if net >= 0.0 else "−") + _money_text(absf(net)) + " last turn"
	_net_label.tooltip_text = "What the last turn earned. Money borrowed is not counted."
	_net_label.add_theme_color_override("font_color", DS2_INK_GOOD if net >= 0.0 else DS2_INK_BAD)
	# LED: overdrawn AND still losing money. Either alone is survivable — a negative
	# balance with a profitable turn is climbing out, and a loss with cash in hand is
	# affordable. Together they are the shape that ends runs (spec §1.3).
	(_treasury_led as StatusLed).lit = MatchState.money < 0.0 and net < 0.0
	var runway := _runway_turns()
	_runway_label.visible = runway > 0
	if runway > 0:
		_runway_label.text = "≈%d TURNS" % runway
	# Buttons don't size to non-container children: min width = inner row + padding.
	money_widget.custom_minimum_size = Vector2(_money_inner.get_combined_minimum_size().x + 26.0, MOD_H)

## The power lamp: amber for drawing from the grid, that same amber BLINKING once a second when a
## building is actually being derated by intermittency (independent of whether the empire is also
## grid-buying), red when a building has no power at all. Red beats blink beats steady.
## TopBarStatus.power judges it, so the lamp and the hover readout say the same thing.
func _refresh_power() -> void:
	var status := TopBarStatus.power()
	(_power_btn as _ModuleBtn).warn = int(status.stats.unpowered) > 0
	var led := _power_led as StatusLed
	led.blink = bool(status.blink)
	led.color = C_RED if str(status.tone) == "bad" else C_AMBER
	led.lit = TopBarStatus.lit(status)


# ── CFO popup · bankruptcy strip · money flash ─────────────────────────────────

func _on_cfo_tax_credit_filed(_amount: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var cfo_id: String = AdvisorState.get_advisor_in_seat("cfo")
	var cfo: Dictionary = AdvisorState.get_advisor(cfo_id) if cfo_id != "" else {}
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
	lbl.add_theme_font_size_override("font_size", DS2_BAR_MIN_PX)
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
	_ds2_refresh_cash(Color(0, 0, 0, 0) if c == _base_money_color() else c)

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


# ── Notices (spec §4) ──────────────────────────────────────────────────────────
#
# A playtester finished a 118-turn run without ever understanding why her balance
# swung, and read a +£2,500 turn as arbitrary. It was not: a batch of sale shipments
# landed at once, on top of an auto-bridge loan she never noticed being taken, with
# tax and dividends skimmed in the same turn. Every figure was already on screen
# somewhere — none of it was ever ATTRIBUTED. These notices attribute it, one sentence
# each, as amber rows in the updates dock (_post_notices).
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
## At most two money notices a turn.
const ANOMALY_MAX_STACK := 2
## Priority when more than ANOMALY_MAX_STACK money triggers fire in one turn.
const ANOMALY_MONEY_ORDER: Array[String] = ["upcoming", "loan", "spend", "transport", "payment"]
## Running-cost lines the spend trigger watches, each against its OWN baseline, mapped
## to the summary breakdown that says which buildings ran it up.
const ANOMALY_COST_LINES := {
	"goods_purchased_cost": "goods_purchased_by_type",
	"labour_paid": "labour_by_type",
	"maintenance_paid": "maintenance_by_type",
	"power_purchase_cost": "power_purchase_by_type",
}

const StockpileGuidance := preload("res://scripts/stockpile_guidance.gd")
var _stockpile_guidance := StockpileGuidance.new()

# Rolling history of the figures the triggers compare against: one entry per resolved
# turn, newest last, at most ANOMALY_BASELINE_TURNS long.
var _anomaly_history: Array[Dictionary] = []
var _anomaly_cooldown := {}          # trigger id -> turn it last fired
var _loan_taken_this_turn := 0.0
var _money_notice_hits: Array = []
var _upcoming_notice_dirty := true
var _upcoming_notice_stamp := ""
## Latched once per run: the intermittency lesson is taught the first time the player
## actually generates intermittent green power, and never again.
var _intermittency_taught := false


func _on_loan_taken(loan: Dictionary) -> void:
	# A deliberate draw and spread financing (48 turns = 12 grace + 36 repaying IS a loan at
	# standard interest) land here. The auto-bridge does too, but it posts its own red row
	# with the borrowing room left, so it adds no second notice. Cleared once the turn's
	# notices have been evaluated.
	if SolvencyState.bridging:
		return
	_loan_taken_this_turn += float(loan.get("principal_initial", 0.0))


## Judge the resolved turn, then fold it into the baseline for the next one.
func _on_turn_resolved_anomalies() -> void:
	var s: Dictionary = Production.last_turn_summary
	if s.is_empty():
		return
	var current := _anomaly_snapshot(s)
	_evaluate_anomalies(current, s)
	var stock_hits := _stockpile_guidance.sample(int(TurnManager.current_turn) - 1)
	if not Tutorial.active:
		for hit: Dictionary in stock_hits:
			var tile := str(hit.tile)
			var good := str(hit.good)
			var message := "%s accumulating at %s (+%d/turn). Open stockpile to move or sell." % [Catalog.get_display_name(good), Catalog.tile_label(tile), roundi(float(hit.growth))]
			if MatchState.should_auto_sell_good(tile, good):
				message = "%s accumulating at %s despite surplus selling. Open stockpile to check sales." % [Catalog.get_display_name(good), Catalog.tile_label(tile)]
			_post_notices([{"text": message, "word": "accumulating", "tone": "warn", "stock_tile": tile, "stock_good": good}])
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
	if Tutorial.active:
		return
	_money_notice_hits = _money_anomalies(current, s)
	_refresh_money_notices(true)

	var power := _power_anomalies(current)
	if not power.is_empty():
		_anomaly_cooldown[str(power[0].id)] = int(TurnManager.current_turn)
		_post_notices([power[0]])


func _queue_upcoming_notice(_a: Variant = null, _b: Variant = null, _c: Variant = null) -> void:
	_upcoming_notice_dirty = true
	_queue_refresh()

func _reset_upcoming_notice() -> void:
	_upcoming_notice_stamp = ""
	_money_notice_hits.clear()
	_queue_upcoming_notice()


func _notice_world() -> Node:
	var node := get_parent()
	while node != null:
		if node.has_method("reveal_for_play"):
			return node
		node = node.get_parent()
	return null

func _notice_loading_active() -> bool:
	for node: Node in get_tree().root.get_children():
		if node is LoadingScreen:
			return true # Includes the fade after Begin, until the screen leaves the tree.
	return false

func _notices_can_show() -> bool:
	if TurnManager.current_turn <= 1 or Tutorial.active or TurnManager.is_resolving:
		return false
	var world := _notice_world()
	return world != null and world.get("build_complete") == true and not _notice_loading_active()

func _on_notice_root_child_entered(node: Node) -> void:
	if node is LoadingScreen:
		_upcoming_notice_stamp = ""
		node.tree_exited.connect(_queue_upcoming_notice)

func _refresh_notices_after_loading() -> void:
	var world := _notice_world()
	if world == null:
		return
	while is_instance_valid(world) and (world.get("build_complete") != true or _notice_loading_active()):
		await get_tree().process_frame
	if is_instance_valid(world):
		_queue_upcoming_notice()

func _refresh_money_notices(force: bool = false) -> void:
	if not _notices_can_show():
		return
	_upcoming_notice_dirty = false
	var forecast := preload("res://scripts/cash_commitments.gd")
	var costs := forecast.attention_costs(forecast.snapshot(), forecast.last_comparison)
	var stamp := str(TurnManager.current_turn) + "|" + JSON.stringify(costs)
	if not force and stamp == _upcoming_notice_stamp:
		return # Nothing to post again until the turn or its costs change.
	_upcoming_notice_stamp = stamp
	var hits := _money_notice_hits.duplicate()
	# Apply the notice threshold to the actual bill, before rounding its buffer.
	if float(costs.total) >= 100.0:
		var amount := "£%d" % forecast.recommended_buffer(float(costs.total))
		var bill := "Input bill"
		for row: Dictionary in (costs.payments as Array) + (costs.order_rows as Array):
			if str(row.get("source_kind", row.get("kind", ""))) in ["construction", "upgrade"]:
				bill = "Materials bill"
				break
		hits.append({"id": "upcoming", "text": "%s coming next turn.\nRecommended buffer: %s" % [bill, amount], "word": amount, "tone": "warn", "upcoming": true})

	var chosen: Array = []
	for id: String in ANOMALY_MONEY_ORDER:
		for hit: Dictionary in hits:
			if str(hit.id) == id and chosen.size() < ANOMALY_MAX_STACK:
				chosen.append(hit)
				if id != "upcoming":
					_anomaly_cooldown[id] = int(TurnManager.current_turn)
	_post_notices(chosen)
	# The upcoming bill is advice while it holds; once it doesn't, its row for this turn goes.
	if not chosen.any(func(hit: Dictionary) -> bool: return str(hit.id) == "upcoming"):
		var dock := _updates_dock()
		if dock != null:
			dock.remove_row("notice:upcoming:%d" % int(TurnManager.current_turn))


## The notice for what was borrowed this turn. When the Logistics Intermediary drew all of it to fund the
## turn's batches (one loan a turn, the summary's middleman_financing), the notice says so.
func loan_notice_text(borrowed: float, s: Dictionary) -> String:
	var financing := float(s.get("middleman_financing", 0.0))
	if financing > 0.0 and financing >= borrowed - 0.005:
		return "We've taken a %s loan to pay for Local Suppliers' batches this turn." % _money_text(borrowed)
	return "We've taken a %s loan to cover this turn's bills." % _money_text(borrowed)


## Money triggers that fired this turn, unordered. Each is {id, text}.
func _money_anomalies(current: Dictionary, s: Dictionary) -> Array:
	var hits: Array = []

	if _loan_taken_this_turn > 0.0 and _anomaly_ready("loan"):
		hits.append({"id": "loan", "word": "loan", "tone": "bad", "text": loan_notice_text(_loan_taken_this_turn, s)})

	var revenue_base := _anomaly_baseline("revenue")
	if revenue_base > 0.0 and float(current.revenue) >= revenue_base * ANOMALY_SPIKE_RATIO and _anomaly_ready("payment"):
		var pay := _big_payment_text(s)
		hits.append({"id": "payment", "tone": "good",
			"text": str(pay.get("text", "")), "word": str(pay.get("word", ""))})

	# Each running-cost line is judged against its OWN baseline, so a labour jump is not
	# hidden by a quiet turn for inputs. One generic sentence covers them all.
	# A profitable company can quite reasonably have a running-cost spike while it is
	# scaling. Use the same operating profit figure shown by the production ledger so
	# the warning only calls out abnormal spending on turns that are not clearing £5.
	var profit_per_turn := float(s.get("pre_tax_profit", float(s.get("money_in", 0.0)) - float(s.get("money_out", 0.0))))
	for line: String in ANOMALY_COST_LINES:
		var base := _anomaly_baseline(line)
		if base <= 0.0 or float(current.get(line, 0.0)) < base * ANOMALY_SPIKE_RATIO:
			continue
		if profit_per_turn >= 5.0 or not _anomaly_ready("spend"):
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
## looking for, rather than the verb that got it there.
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
	# player has just built the wind or solar, not when it first bites — that is the
	# teachable moment, ahead of the first derate.
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


# ── Notices in the updates dock ────────────────────────────────────────────────

## The bottom-left updates dock (scripts/toast_manager.gd), the bar's sibling in the HUD.
func _updates_dock() -> Control:
	var parent := get_parent()
	return parent.get_node_or_null("ToastLayer") as Control if parent != null else null


## Posts notices to the updates dock as amber rows. Each row is keyed by its notice and the
## turn, so a notice re-evaluated through a turn (the upcoming bill) keeps one row.
func _post_notices(hits: Array) -> void:
	if hits.is_empty() or DisplayServer.get_name() == "headless" or not _notices_can_show():
		return
	var dock := _updates_dock()
	if dock == null:
		return
	for hit: Dictionary in hits:
		dock.push_notice(_notice_key(hit), str(hit.text), _notice_action(hit))


func _notice_key(hit: Dictionary) -> String:
	var turn := int(TurnManager.current_turn)
	if hit.has("stock_tile"):
		return "stock:%s:%s:%d" % [str(hit.stock_tile), str(hit.stock_good), turn]
	return "%s:%d" % [str(hit.get("id", "")), turn]


## What clicking a notice's row does: the upcoming bill opens the Money panel's Upcoming tab,
## stock building up opens that tile's stockpile on the good. Other notices are not links.
func _notice_action(hit: Dictionary) -> Callable:
	if bool(hit.get("upcoming", false)):
		return func() -> void: _open_money_panel_tab("Upcoming")
	if hit.has("stock_tile"):
		var stock_tile := str(hit.stock_tile)
		var stock_good := str(hit.stock_good)
		return func() -> void:
			MatchState.tile_stockpile_requested.emit(stock_tile)
			for panel in get_tree().get_nodes_in_group("tile_view_panel"):
				if panel.has_method("select_stock_good") and str(panel.get("_current_tile_id")) == stock_tile:
					panel.call("select_stock_good", stock_good)
	return Callable()
