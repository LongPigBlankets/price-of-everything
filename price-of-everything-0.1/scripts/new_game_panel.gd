extends Control
## New Game settings screen. Slides in over the main menu's goods board when the
## player clicks New Game and lets them pick a START (a single row of 7 cards — a
## tier-coloured good-on-hex icon, title and difficulty badge), a DIFFICULTY, a SPEED
## (game length / era pacing) and whether the TUTORIAL is on, then launches through
## the same loading pipeline New Game has always used.
##
## Pure UI: captures the choices and emits `start_requested(start_path, overrides)` /
## `back_requested`; the main menu owns the scene transition. Built from the shared DS
## theme plus a rounded metallic icon frame + BevelEdge rim (the market panel's framed
## goods-icon light) over the research panel's metallic navy plate (diagonal light +
## rivets). Referenced from main_menu via a preload const (no class_name) for headless.

signal start_requested(start_path: String, overrides: Dictionary)
signal back_requested

const STARTS_INDEX := "res://data/starts/index.json"
const DEFAULT_START := "res://data/starts/default.json"

# Demo build: only Coal Baron, Normal difficulty and the 300-turn length are
# playable; everything else is greyed with a "Locked in the Demo" tooltip. Flip
# DEMO_LOCK to false to restore the full menu after the demo.
const DEMO_LOCK := true
const DEMO_START_IDS: Array = ["metal_magnate", "glass_merchant"]   # the starts playable in the demo
const DEMO_DIFFICULTY_ID := "normal"
## The length a demo build is pinned to. Now the Itch.io demo itself: 100 turns with its
## own policy timeline, rather than a 300-turn campaign the player could never finish.
const DEMO_SPEED_ID := "demo_itch"
const DEMO_LOCK_TIP := "Locked in the Demo"

const ICON := 120.0                                  # start-card icon size
const CARD_PAD := 12                                 # fixed card content margin (constant across states)
const DESC_INSET := 200                              # description inset from each container edge
const BevelEdge := preload("res://scripts/bevel_edge.gd")
const GoodIcons := preload("res://scripts/good_icons.gd")
const UIHelpers := preload("res://scripts/ui_helpers.gd")
const MenuChrome := preload("res://scripts/menu_chrome.gd")
const BEBAS := preload("res://assets/fonts/BebasNeue-Regular.ttf")
const BuildingIcon := preload("res://scripts/building_icon.gd")   # navy-keyed metallic building icons
const DebugTerminal := preload("res://scripts/debug_terminal.gd")   # for the `unlock demo` cheat flag
const GOLD := Color(0.90, 0.72, 0.36, 1.0)
const CREAM := Color(0.995234, 0.930806, 0.763265)   # recipe-card parchment, for the goods tiles
# "2 sizes larger" body text in the start detail (DS Body 14 / Numeric 16 baselines).
const DETAIL_BODY_FS := 18
const DETAIL_NUM_FS := 20
const START_NAME_FS := 22
# Reserved detail geometry so switching starts never nudges the buildings/financials around:
# a fixed description height (top-aligned) pins their vertical origin, and a fixed
# "Buildings owned" column width pins the centred group's horizontal position.
const DESC_MIN_H := 84
const BCOL_W := 600

# Tier -> hex fill colour + difficulty badge.
const TIERS := {
	"green": {"fill": Color(0.18, 0.46, 0.30), "badge": "Beginner-friendly"},
	"amber": {"fill": Color(0.74, 0.52, 0.20), "badge": "Intermediate"},
	"red":   {"fill": Color(0.62, 0.24, 0.22), "badge": "Challenging"},
}

const DIFFICULTIES: Array = [
	{"id": "easy", "label": "Easy",
		"desc": "All resource deposits present on the map and infinite. The whole map is surveyed."},
	{"id": "normal", "label": "Normal",
		"desc": "All resource deposits on the map, but some are finite. Some tiles are surveyed."},
	{"id": "hard", "label": "Hard",
		"desc": "A single finite rare-earth deposit on the map. Other deposits are reduced. Some tiles are surveyed."},
	{"id": "very_hard", "label": "Very Hard", "locked": true,
		"desc": "No rare-earth deposits. A single alloy-metal deposit on the map. Other deposits reduced. Only your starting tiles are surveyed."},
	{"id": "god", "label": "God of Industry", "locked": true,
		"desc": "No rare-earth, alloy-metal or crude-oil deposits. Other deposits reduced. Only your starting tiles are surveyed."},
]
const DIFFICULTY_DEFAULT := 1

## A length carries its policy timeline and its victory set with it, because a 100-turn
## match cannot use the campaign's decarbonisation beats (the subsidy lands after it ends)
## or the campaign's victory tracks (they are written for 300 turns of compounding).
const SPEEDS: Array = [
	{"id": "200", "turns": 200, "label": "200 turns"},
	{"id": "300", "turns": 300, "label": "300 turns"},
	{"id": "400", "turns": 400, "label": "400 turns"},
	{"id": DEMO_SPEED_ID, "turns": 100, "label": "Demo - Itch.io",
		"policy_timeline": "demo_itch", "victory_set": "demo_itch"},
]
const SPEED_DEFAULT := 1
## Which row a demo build starts on — the only one it leaves enabled.
const SPEED_DEFAULT_DEMO := 3

# Advanced Settings tickboxes (the "Tutorial" column was replaced by these). Only
# the first is wired today; 2 & 3 are placeholders for future toggles.
const ADVANCED_SETTINGS: Array = [
	{"id": "survey_all", "label": "All tiles surveyed at game start"},
	{"id": "setting_2", "label": "Setting 2"},
	{"id": "setting_3", "label": "Setting 3"},
]

var _starts: Array = []
var _start_id := ""
var _start_path := DEFAULT_START
var _difficulty_id := "normal"
var _speed_turns := 300
var _policy_timeline := ""   # only the demo length sets one
var _victory_set := ""       # ditto: the demo's five tracks, or the campaign's
# New Game never launches the tutorial coach (that's what the Tutorial menu is for).
var _tutorial_on := false
var _survey_all := true
var _advanced: Dictionary = {}   # setting id -> bool
var _send_metrics := true        # telemetry opt-out checkbox (default on; remembered)

var _card_buttons: Array = []
var _detail_desc: Label
var _start_detail_box: HBoxContainer   # "Buildings owned" | "Financials"; hidden when the accordion opens
var _difficulty_caption: Label

static var _vig_tex: Texture2D = null


func _ready() -> void:
	_build()


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		back_requested.emit()
		get_viewport().set_input_as_handled()


# ── Layout ──────────────────────────────────────────────────────────────────────

func _build() -> void:
	_starts = _load_starts()

	var bg := MetalBg.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.clip_contents = true   # keep content from spilling past the panel edges
	for s in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + s, DS.SP["XL"])
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", DS.SP["MD"])
	margin.add_child(col)

	# Header.
	var header := HBoxContainer.new()
	col.add_child(header)
	var title := Label.new()
	title.text = "New Game"
	title.theme_type_variation = &"Title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(func() -> void: back_requested.emit())
	header.add_child(back)

	# Start cards — a single centred, spaced-out row.
	_build_cards(col)

	# Selected-start detail: expanded description (inset from each edge) + a fact line.
	var detail_margin := MarginContainer.new()
	detail_margin.add_theme_constant_override("margin_left", DESC_INSET)
	detail_margin.add_theme_constant_override("margin_right", DESC_INSET)
	col.add_child(detail_margin)
	var detail_col := VBoxContainer.new()
	detail_col.add_theme_constant_override("separation", DS.SP["MD"])
	detail_margin.add_child(detail_col)
	_detail_desc = Label.new()
	_detail_desc.theme_type_variation = &"Body"
	_detail_desc.add_theme_font_size_override("font_size", DETAIL_BODY_FS)
	_detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Reserve a fixed height (top-aligned) so a longer/shorter description never shifts the
	# buildings/financials detail below it up or down when you switch starts.
	_detail_desc.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_detail_desc.custom_minimum_size = Vector2(0, DESC_MIN_H)
	detail_col.add_child(_detail_desc)
	# Expanded explanation — "Buildings owned" | "Financials". Shown while the accordion is
	# closed; the accordion's toggle hides it when opened, freeing the space for the settings.
	_start_detail_box = HBoxContainer.new()
	_start_detail_box.add_theme_constant_override("separation", DS.SP["XL"] * 3)
	_start_detail_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_start_detail_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	detail_col.add_child(_start_detail_box)

	_build_settings_columns(col)

	col.add_child(_expand_spacer())
	var start_wrap := HBoxContainer.new()
	start_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(start_wrap)
	start_wrap.add_child(_flex_spacer(0.15))
	var start_btn := Button.new()
	start_btn.text = "Start New Game"
	start_btn.theme_type_variation = &"Primary"
	start_btn.custom_minimum_size = Vector2(0, 54)
	start_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start_btn.size_flags_stretch_ratio = 0.70
	start_btn.pressed.connect(_on_start_pressed)
	start_wrap.add_child(start_btn)
	start_wrap.add_child(_flex_spacer(0.15))

	_select_default_start()


func _build_cards(parent: Node) -> void:
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(center)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", DS.SP["LG"])
	center.add_child(row)
	var group := ButtonGroup.new()
	for start in _starts:
		row.add_child(_start_card(start, group))


# A start card: a container holding the framed good-on-hex icon, the title and the
# difficulty badge, with a transparent radio button on top. Selection only changes the
# card's colours (same border width + content margin -> no size shift).
func _start_card(start: Dictionary, group: ButtonGroup) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _card_box(false))

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", DS.SP["SM"])
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(vb)

	var icon := _make_icon(start, ICON)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(icon)

	var title := Label.new()
	title.text = String(start.get("title", ""))
	title.theme_type_variation = &"BuildingName"
	title.add_theme_font_size_override("font_size", START_NAME_FS)   # larger start-name text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size = Vector2(ICON + 20.0, 0)
	vb.add_child(title)

	# Push the difficulty badge to the bottom of the card so every badge lines up on one row,
	# no matter how many lines the title wraps to. Cards are stretched to equal height by their
	# HBox row, so this expanding spacer soaks up the surplus above the badge.
	var badge_spacer := Control.new()
	badge_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	badge_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(badge_spacer)

	var badge_row := CenterContainer.new()
	badge_row.add_child(_make_badge(start))
	vb.add_child(badge_row)

	var btn := Button.new()
	btn.toggle_mode = true
	btn.button_group = group
	btn.tooltip_text = String(start.get("title", ""))
	for s in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(s, StyleBoxEmpty.new())
	card.add_child(btn)
	# Demo lock: every start except Coal Baron is greyed + unclickable.
	if _demo_locked() and not DEMO_START_IDS.has(String(start.get("id", ""))):
		btn.disabled = true
		btn.tooltip_text = DEMO_LOCK_TIP
		card.modulate = Color(1, 1, 1, 0.35)
		_card_buttons.append(btn)
		return card
	var st := start
	btn.toggled.connect(func(on: bool) -> void:
		card.add_theme_stylebox_override("panel", _card_box(on))
		if on:
			_select_start(st))
	_card_buttons.append(btn)
	return card


# Selected vs unselected card differ ONLY in colour — identical border width, corner
# radius and content margin, so toggling never resizes the card.
func _card_box(selected: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = DS.PALETTE["BG_HIGHLIGHT"] if selected else DS.PALETTE["BG_INSET"]
	sb.border_color = DS.PALETTE["ACCENT"] if selected else DS.PALETTE["BORDER_SOFT"]
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = CARD_PAD
	sb.content_margin_right = CARD_PAD
	sb.content_margin_top = CARD_PAD
	sb.content_margin_bottom = CARD_PAD
	return sb


# Rounded metallic framed icon: rounded navy plate (cream border) → tier hex + good +
# vignette → raised bevel rim (top-left light). Rounded corners; nothing square.
func _make_icon(start: Dictionary, px: float) -> Control:
	var root := Control.new()
	root.custom_minimum_size = Vector2(px, px)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Flat tier-coloured rounded plate (was a navy plate + tier hexagon; simplified to one colour).
	var frame := RoundFrame.new()
	frame.fill = _tier_fill(start)
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(frame)

	var inner := Control.new()
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	var pad := px * 0.10
	inner.offset_left = pad
	inner.offset_top = pad
	inner.offset_right = -pad
	inner.offset_bottom = -pad
	inner.clip_contents = true
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(inner)

	var icon := TextureRect.new()
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	var ins := px * 0.085   # ~25% larger good icon
	icon.offset_left = ins
	icon.offset_top = ins
	icon.offset_right = -ins
	icon.offset_bottom = -ins
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tex: Texture2D = GoodIcons.texture_for(String(start.get("good_id", "")), String(start.get("good_internal", "")))
	if tex != null:
		icon.texture = tex
	inner.add_child(icon)

	# Brass beveled edge (the main-menu frame, same ~6px thickness) around the image container.
	MenuChrome.add_frame(root)
	return root


func _make_badge(start: Dictionary) -> Control:
	var info: Dictionary = TIERS.get(String(start.get("tier", "amber")), TIERS["amber"])
	var pill := PanelContainer.new()
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = info["fill"]
	sb.set_corner_radius_all(9)
	sb.content_margin_left = 9
	sb.content_margin_right = 9
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	pill.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = String(info["badge"])
	l.theme_type_variation = &"Caption"
	l.add_theme_color_override("font_color", Color(0.04, 0.09, 0.14))
	pill.add_child(l)
	return pill


# Difficulty, Speed and Tutorial as three side-by-side columns (buttons stacked
# within each), grouped in one section. The selected difficulty's description shows
# beneath the section.
func _build_settings_columns(parent: Node) -> void:
	# Collapsible "Advanced Settings" accordion (closed by default). Difficulty / Speed / the
	# option tickboxes all live inside it; the telemetry consent row is added to `parent`
	# afterwards, so it stays OUTSIDE the accordion.
	var accordion := VBoxContainer.new()
	accordion.add_theme_constant_override("separation", DS.SP["SM"])
	parent.add_child(accordion)

	var header := _accordion_header("Advanced Settings")
	if _demo_locked():
		header.tooltip_text = DEMO_LOCK_TIP
	accordion.add_child(header)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", DS.SP["SM"])
	body.visible = false   # closed by default
	accordion.add_child(body)
	header.toggled.connect(func(on: bool) -> void:
		if on and _demo_locked():
			header.set_pressed_no_signal(false)   # blocked in the demo (until `unlock demo`)
			return
		body.visible = on
		header.text = ("▾   " if on else "▸   ") + "Advanced Settings"
		if _start_detail_box != null:
			_start_detail_box.visible = not on)   # the buildings/financials detail fills this space when closed

	var section := PanelContainer.new()
	section.theme_type_variation = &"Inset"
	body.add_child(section)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", DS.SP["XL"])
	section.add_child(cols)

	# Difficulty column (with the God-of-Industry lock).
	var dcol := _settings_column(cols, "Difficulty")
	_difficulty_caption = Label.new()
	_difficulty_caption.theme_type_variation = &"Caption"
	_difficulty_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var dgroup := ButtonGroup.new()
	var unlocked := PlayerProfile.has_completed_game()
	for opt in DIFFICULTIES:
		var oid := String(opt["id"])
		var odesc := String(opt["desc"])
		var olabel := String(opt["label"])
		var b := _stacked_button(dcol, olabel, dgroup)
		# Demo lock: only Normal is playable. (Otherwise the finish-a-game lock on
		# Very Hard / God of Industry still applies.)
		if _demo_locked() and oid != DEMO_DIFFICULTY_ID:
			b.disabled = true
			b.tooltip_text = DEMO_LOCK_TIP
			continue
		if bool(opt.get("locked", false)) and not unlocked:
			b.disabled = true
			b.tooltip_text = "This difficulty is unlocked once you finish one game"
			continue
		b.toggled.connect(func(on: bool) -> void:
			if on:
				_difficulty_id = oid
				_difficulty_caption.text = odesc)
	_press_in_group(dcol, DIFFICULTY_DEFAULT)

	# Speed column.
	var scol := _settings_column(cols, "Speed")
	var sgroup := ButtonGroup.new()
	for opt in SPEEDS:
		var turns := int(opt["turns"])
		var timeline := String(opt.get("policy_timeline", ""))
		var victory_set := String(opt.get("victory_set", ""))
		var b := _stacked_button(scol, String(opt["label"]), sgroup)
		# Demo lock: only the 300-turn length is playable.
		if _demo_locked() and String(opt["id"]) != DEMO_SPEED_ID:
			b.disabled = true
			b.tooltip_text = DEMO_LOCK_TIP
			continue
		b.toggled.connect(func(on: bool) -> void:
			if on:
				_speed_turns = turns
				_policy_timeline = timeline
			_victory_set = victory_set)
	var note := Label.new()
	note.text = "This also changes the Era pacing."
	note.theme_type_variation = &"Caption"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scol.add_child(note)
	_press_in_group(scol, SPEED_DEFAULT_DEMO if _demo_locked() else SPEED_DEFAULT)

	# Options column: three tickboxes (the accordion itself now carries the "Advanced Settings"
	# title). The DS theme doesn't style CheckBox, so use UIHelpers' drawn box icons for a
	# legible tick against the navy plate.
	var acol := _settings_column(cols, "Options")
	for opt in ADVANCED_SETTINGS:
		var sid := String(opt["id"])
		var locked_value := sid == "survey_all"
		_advanced[sid] = locked_value
		var cb := CheckBox.new()
		cb.text = "  " + String(opt["label"])
		cb.size_flags_horizontal = Control.SIZE_FILL
		cb.custom_minimum_size = Vector2(0, 34)
		cb.add_theme_icon_override("unchecked", UIHelpers.checkbox_icon(false))
		cb.add_theme_icon_override("checked", UIHelpers.checkbox_icon(true))
		cb.add_theme_icon_override("unchecked_disabled", UIHelpers.checkbox_icon(false))
		cb.add_theme_icon_override("checked_disabled", UIHelpers.checkbox_icon(true))
		cb.add_theme_color_override("font_color", DS.PALETTE["TEXT"])
		cb.button_pressed = locked_value
		cb.disabled = true
		acol.add_child(cb)

	body.add_child(_difficulty_caption)

	# Telemetry consent (opt-out, docs/telemetry-spec.md §2): defaults to the player's
	# remembered choice; consumed by main_menu on Start. OUTSIDE the accordion (always visible).
	_send_metrics = not PlayerProfile.telemetry_opt_out
	var consent := UIHelpers.make_telemetry_consent_row(_send_metrics)
	(consent["checkbox"] as CheckBox).toggled.connect(
			func(on: bool) -> void: _send_metrics = on)
	parent.add_child(consent["row"])


## Accordion header: a flat, left-aligned toggle in large Bebas Neue cream (the DS Title font),
## with a ▸/▾ affordance. Clicking it shows/hides the accordion body.
func _accordion_header(label: String) -> Button:
	var h := Button.new()
	h.toggle_mode = true
	h.button_pressed = false
	h.text = "▸   " + label
	h.add_theme_font_override("font", BEBAS)
	h.add_theme_font_size_override("font_size", 30)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		h.add_theme_color_override(c, DS.PALETTE["ACCENT"])
	h.alignment = HORIZONTAL_ALIGNMENT_LEFT
	h.focus_mode = Control.FOCUS_NONE
	h.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for st in ["normal", "hover", "pressed", "focus"]:
		h.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	return h


func _settings_column(parent: Node, heading: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_FILL
	v.add_theme_constant_override("separation", DS.SP["SM"])
	parent.add_child(v)
	var h := Label.new()
	h.text = heading
	h.theme_type_variation = &"Section"
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER   # centred over its column
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(h)
	return v


func _stacked_button(col: Node, label: String, group: ButtonGroup) -> Button:
	# Wrapped so the button spans 70% of the column (30% narrower), centred and resolution-proof.
	var wrap := HBoxContainer.new()
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(wrap)
	wrap.add_child(_flex_spacer(0.15))
	var b := Button.new()
	b.text = label
	b.toggle_mode = true
	b.button_group = group
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_stretch_ratio = 0.70
	b.custom_minimum_size = Vector2(0, 36)
	wrap.add_child(b)
	wrap.add_child(_flex_spacer(0.15))
	return b


func _flex_spacer(ratio: float) -> Control:
	var s := Control.new()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_stretch_ratio = ratio
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s


# ── Selection + data ────────────────────────────────────────────────────────────

func _select_start(start: Dictionary) -> void:
	_start_id = String(start.get("id", ""))
	_start_path = String(start.get("file", DEFAULT_START))
	_detail_desc.text = String(start.get("description", start.get("blurb", "")))
	_populate_start_detail(start)


## Rebuild the "Buildings owned" | "Financials" explanation for the selected start.
func _populate_start_detail(start: Dictionary) -> void:
	for c in _start_detail_box.get_children():
		c.queue_free()
	var cfg := _read_config(String(start.get("file", "")))

	# Column 1 — Buildings owned: one row per building, its metallic icon paired with the
	# recipe's main output good (mirrors the tile view's building cards).
	var bcol := VBoxContainer.new()
	bcol.add_theme_constant_override("separation", DS.SP["SM"])
	# Fixed width so a start with fewer buildings (a 1-column grid) doesn't collapse the
	# column and slide the whole centred group sideways. Financials is already fixed at 300.
	bcol.custom_minimum_size = Vector2(BCOL_W, 0)
	_start_detail_box.add_child(bcol)
	bcol.add_child(_detail_heading("Buildings owned"))
	var buildings := cfg.get("buildings", []) as Array
	if buildings.is_empty():
		bcol.add_child(_muted_label("None"))
	else:
		# Pairs (building + good) laid out two-wide.
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", DS.SP["XL"])
		grid.add_theme_constant_override("v_separation", DS.SP["MD"])
		bcol.add_child(grid)
		for entry in buildings:
			grid.add_child(_building_row(entry as Dictionary))

	# Column 2 — Financials: cash, debt, and the estimated per-turn profit.
	var fcol := VBoxContainer.new()
	fcol.add_theme_constant_override("separation", DS.SP["XS"])
	fcol.custom_minimum_size = Vector2(300, 0)
	_start_detail_box.add_child(fcol)
	fcol.add_child(_detail_heading("Financials"))
	var cash := float(cfg.get("money", EconomyConfig.STARTING_MONEY))
	var debt := 0.0
	for l in (cfg.get("loans", []) as Array):
		debt += float((l as Dictionary).get("principal", 0.0))
	fcol.add_child(_fin_row("Cash", "£%s" % _fmt_money(cash)))
	fcol.add_child(_fin_row("Debt", "—" if debt <= 0.0 else "£%s" % _fmt_money(debt)))
	# Prefer the measured steady-state profit (config "steady_profit_per_turn" — matches what you
	# see ~6 turns into a do-nothing game); fall back to a rough base-price estimate otherwise.
	var profit := float(cfg.get("steady_profit_per_turn", _profit_estimate(cfg)))
	var loss := profit < 0.0
	var profit_txt := ("−£%s" % _fmt_money(absf(profit))) if loss else ("+£%s" % _fmt_money(profit))
	fcol.add_child(_fin_row("Avg. profit / turn", profit_txt, Color(0.85, 0.36, 0.32) if loss else null))


func _detail_heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", BEBAS)
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", DS.PALETTE["ACCENT"])
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER   # centred over its column
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _muted_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"Caption"
	return l


## A building row: the metallic building icon + its recipe's main output good (icon + name).
func _building_row(entry: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", DS.SP["SM"])
	var bid := String(entry.get("building_id", ""))
	var binternal := String(Catalog.get_building(bid).get("internal_name", ""))
	row.add_child(_building_icon(bid, binternal, 76))
	var recipe := Catalog.get_recipe(String(entry.get("recipe_id", "")))
	var gid := String(recipe.get("output_good_id", ""))
	if gid != "":
		# Good icon on a cream, rounded-corner tile (the recipe-card treatment).
		var g_tile := PanelContainer.new()
		g_tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var sb := StyleBoxFlat.new()
		sb.bg_color = CREAM
		sb.set_corner_radius_all(10)
		sb.set_content_margin_all(5)
		g_tile.add_theme_stylebox_override("panel", sb)
		var g := TextureRect.new()
		g.texture = GoodIcons.texture_for(gid, Catalog.get_internal_name(gid))
		g.custom_minimum_size = Vector2(52, 52)
		g.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		g.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		g_tile.add_child(g)
		row.add_child(g_tile)
		var name := Label.new()
		name.text = Catalog.get_display_name(gid)
		name.theme_type_variation = &"Body"
		name.add_theme_font_size_override("font_size", DETAIL_BODY_FS)
		name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(name)
	return row


## Metallic building icon (top-left-lit emboss) like the ledger/tile cards, sized to `px`.
func _building_icon(bid: String, binternal: String, px: float) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(px, px)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tex: Texture2D = BuildingIcon.clean_texture(bid, binternal)
	if tex == null:
		return holder
	for layer in [[Vector2(2.5, 2.5), Color(0, 0, 0, 0.6)], [Vector2(-1, -1), Color(1, 1, 1, 0.4)], [Vector2.ZERO, Color(0.93, 0.96, 1.0)]]:
		var t := TextureRect.new()
		t.set_anchors_preset(Control.PRESET_FULL_RECT)
		t.offset_left = (layer[0] as Vector2).x
		t.offset_top = (layer[0] as Vector2).y
		t.offset_right = (layer[0] as Vector2).x
		t.offset_bottom = (layer[0] as Vector2).y
		t.texture = tex
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.modulate = layer[1]
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(t)
	return holder


func _fin_row(label_text: String, value: String, value_color: Variant = null) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", DS.SP["SM"])
	var l := Label.new()
	l.text = label_text
	l.theme_type_variation = &"Body"
	l.add_theme_font_size_override("font_size", DETAIL_BODY_FS)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var v := Label.new()
	v.text = value
	v.theme_type_variation = &"Numeric"
	v.add_theme_font_size_override("font_size", DETAIL_NUM_FS)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if value_color != null:
		v.add_theme_color_override("font_color", value_color as Color)
	row.add_child(v)
	return row


## Rough per-turn profit at base prices: outputs sold − inputs bought − maintenance, summed over
## the starting buildings (intermediate goods cancel out, leaving the operation's gross margin).
## Ignores labour / power / transport, so it's only a directional estimate (fallback when a
## start has no measured steady_profit_per_turn).
func _profit_estimate(cfg: Dictionary) -> float:
	var net := 0.0
	for entry in (cfg.get("buildings", []) as Array):
		var e := entry as Dictionary
		var recipe := Catalog.get_recipe(String(e.get("recipe_id", "")))
		for o in recipe.get("outputs", []):
			net += Catalog.get_base_price(String((o as Dictionary).get("good_id", ""))) * float((o as Dictionary).get("qty", 0))
		for i in recipe.get("inputs", []):
			net -= Catalog.get_base_price(String((i as Dictionary).get("good_id", ""))) * float((i as Dictionary).get("qty", 0))
		var maint: Variant = Catalog.get_building(String(e.get("building_id", ""))).get("maintenance_cost", null)
		if maint != null:
			net -= float(maint)
	return net


func _select_default_start() -> void:
	# Under the demo lock only DEMO_START_IDS are playable (default to the first of them in row
	# order); otherwise the recommended card.
	var idx := -1
	for i in _starts.size():
		var st := _starts[i] as Dictionary
		if _demo_locked():
			if DEMO_START_IDS.has(String(st.get("id", ""))):
				idx = i
				break
		elif bool(st.get("recommended", false)):
			idx = i
			break
	# Fall back to the first ENABLED card if the preferred one is missing or locked
	# (e.g. the start data was edited to drop Coal Baron): never leave New Game with
	# no start selected — pressing a disabled card would silently keep DEFAULT_START.
	if idx < 0 or idx >= _card_buttons.size() or (_card_buttons[idx] as Button).disabled:
		idx = -1
		for i in _card_buttons.size():
			if not (_card_buttons[i] as Button).disabled:
				idx = i
				break
	if idx >= 0 and idx < _card_buttons.size():
		(_card_buttons[idx] as Button).button_pressed = true


func _tier_fill(start: Dictionary) -> Color:
	var info: Dictionary = TIERS.get(String(start.get("tier", "amber")), TIERS["amber"])
	return info["fill"]


func _load_starts() -> Array:
	var out: Array = []
	if FileAccess.file_exists(STARTS_INDEX):
		var f := FileAccess.open(STARTS_INDEX, FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			f.close()
			if parsed is Dictionary and (parsed as Dictionary).has("starts"):
				for e in (parsed as Dictionary)["starts"]:
					if e is Dictionary:
						out.append(e)
	if out.is_empty():
		out.append({"id": "default", "file": DEFAULT_START, "title": "New Game",
			"tier": "green", "description": "", "recommended": true})
	return out


func _facts_for(start: Dictionary) -> Array:
	var cfg := _read_config(String(start.get("file", "")))
	var cash := float(cfg.get("money", EconomyConfig.STARTING_MONEY))
	var n_buildings := (cfg.get("buildings", []) as Array).size()
	var loan_total := 0.0
	for l in (cfg.get("loans", []) as Array):
		loan_total += float((l as Dictionary).get("principal", 0.0))
	var facts: Array = []
	facts.append("Cash £%s" % _fmt_money(cash))
	facts.append("no buildings" if n_buildings == 0 else "%d buildings" % n_buildings)
	facts.append("no loans" if loan_total <= 0.0 else "£%s debt" % _fmt_money(loan_total))
	return facts


func _read_config(path: String) -> Dictionary:
	if path == "" or not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return (parsed as Dictionary) if parsed is Dictionary else {}


func _fmt_money(v: float) -> String:
	var n := int(round(v))
	var s := str(absi(n))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if n < 0 else "") + out


# ── Small UI helpers ────────────────────────────────────────────────────────────

func _section(parent: Node, heading: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", DS.SP["XS"])
	parent.add_child(v)
	var h := Label.new()
	h.text = heading
	h.theme_type_variation = &"Section"
	v.add_child(h)
	return v


func _spacer(h: int) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, h)
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s


func _expand_spacer() -> Control:
	var s := Control.new()
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s


func _press_in_group(row: Node, i: int) -> void:
	var btns: Array = []
	_collect_buttons(row, btns)   # recursive: the buttons are wrapped for 30% narrowing
	if i >= 0 and i < btns.size():
		(btns[i] as Button).button_pressed = true


func _collect_buttons(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is Button:
			out.append(c)
		else:
			_collect_buttons(c, out)


## True while the demo restrictions apply — the `unlock demo` terminal cheat clears them.
func _demo_locked() -> bool:
	return DEMO_LOCK and not DebugTerminal.demo_is_unlocked()


func _on_start_pressed() -> void:
	var overrides := {
		# Consumed (and erased) by main_menu before prepare_new_game.
		"telemetry_opt_in": _send_metrics,
		"ruleset": {
			"start_id": _start_id,
			"difficulty": _difficulty_id,
			"speed_turns": _speed_turns,
			# Set by the length row. Empty for a campaign length, which is what every reader
			# falls back to, so only the demo has to say anything.
			"policy_timeline": _policy_timeline,
			"victory_set": _victory_set,
			"tutorial_enabled": _tutorial_on,
			# Advanced Settings: force every land tile surveyed at game start (this
			# overrides whatever the difficulty's survey config would otherwise do).
			"survey_all_tiles": _survey_all,
		},
	}
	start_requested.emit(_start_path, overrides)


# Radial vignette texture (transparent centre darkening to the edges), built once.
static func _vignette_tex() -> Texture2D:
	if _vig_tex != null:
		return _vig_tex
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var cc := (n - 1) * 0.5
	for y in range(n):
		for x in range(n):
			var dx := (float(x) - cc) / cc
			var dy := (float(y) - cc) / cc
			var d := sqrt(dx * dx + dy * dy) / 1.41421356
			var a := clampf((d - 0.5) / 0.5, 0.0, 1.0)
			img.set_pixel(x, y, Color(0.0, 0.0, 0.0, a * a * 0.6))
	_vig_tex = ImageTexture.create_from_image(img)
	return _vig_tex


# ── Nested draw classes ─────────────────────────────────────────────────────────

## Metallic navy plate: diagonal gradient (light top-left → dark bottom-right), corner
## rivets and a cream rounded outline — the research/market-panel treatment.
class MetalBg extends Control:
	const TL := Color(0.06, 0.21, 0.35, 1.0)
	const TR := Color(0.02, 0.13, 0.25, 1.0)
	const BL := Color(0.01, 0.10, 0.20, 1.0)
	const BR := Color(0.0, 0.05, 0.10, 1.0)
	const BORDER := Color(0.995234, 0.930806, 0.763265, 1.0)
	const INSET := 5.0
	const RADIUS := 14

	func _ready() -> void:
		resized.connect(queue_redraw)

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var b := r.grow(-INSET)
		if b.size.x <= 0.0 or b.size.y <= 0.0:
			return
		draw_polygon(
			PackedVector2Array([b.position, Vector2(b.end.x, b.position.y), b.end, Vector2(b.position.x, b.end.y)]),
			PackedColorArray([TL, TR, BR, BL]))
		var m := 18.0
		for cc in [b.position + Vector2(m, m), Vector2(b.end.x - m, b.position.y + m),
				Vector2(b.position.x + m, b.end.y - m), b.end - Vector2(m, m)]:
			_rivet(cc, 5.0)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color.TRANSPARENT
		sb.border_color = BORDER
		sb.set_border_width_all(4)
		sb.set_corner_radius_all(RADIUS)
		draw_style_box(sb, r)

	func _rivet(c: Vector2, rad: float) -> void:
		draw_circle(c, rad, Color("#586673"))
		draw_circle(c - Vector2(rad * 0.3, rad * 0.3), rad * 0.5, Color("#cdd8e2"))
		draw_arc(c, rad, 0, TAU, 16, Color(0, 0, 0, 0.5), 1.0)


## Rounded navy plate for the icon — the brass MenuChrome frame is overlaid on top (no cream
## border of its own). RADIUS matches the brass frame's inner radius so it wraps cleanly.
class RoundFrame extends Control:
	const NAVY := Color(0.02, 0.085, 0.155, 1.0)
	# Match the overlaid brass frame's OUTER silhouette (inset ~3px, radius 28): the fill then
	# sits under the whole gold border and shows through its hole with no gap and no overflow.
	const INSET := 3.0
	const RADIUS := 28
	var fill: Color = NAVY

	func _ready() -> void:
		resized.connect(queue_redraw)

	func _draw() -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = fill
		sb.set_corner_radius_all(RADIUS)
		draw_style_box(sb, Rect2(Vector2.ZERO, size).grow(-INSET))


## A tier-coloured hexagon with a gold outline (drawn over the frame's navy field).
class HexBg extends Control:
	const GOLD := Color(0.90, 0.72, 0.36, 1.0)
	var fill := Color(0.3, 0.3, 0.3)

	func _ready() -> void:
		resized.connect(queue_redraw)

	func _draw() -> void:
		var c := size * 0.5
		var rad := minf(size.x, size.y) * 0.5
		var pts := PackedVector2Array()
		for i in range(6):
			var ang := float(i) * PI / 3.0   # flat-top hexagon
			pts.append(c + Vector2(cos(ang), sin(ang)) * rad)
		draw_colored_polygon(pts, fill)
		var closed := pts.duplicate()
		closed.append(pts[0])
		draw_polyline(closed, GOLD, 3.0, true)
