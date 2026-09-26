extends RefCounted
## Tile view v3, Buildings tab: the parts its body is made of, all Building Detail v3's (docs/ds2-theme.md
## §5): the black plastic case and its silver screws, the raised modules (and a one-line module for a
## group's member), a good set in its well with the quantity pill inside (unlit while its building is
## stalled; a smaller well and pill on a member's line), Cost to produce as a £ and an LED screen (the
## seven-segment screen is for money only), turns on drum counters as tall as those screens
## (drum_figure.gd), raised headings, metal labels, cream keys, emblems in polished metal, and the
## column the body's parts stand in, clear of the scroll rail. Modules, keys and figures carry Building
## Detail's readout as their hover (buildings_tip.gd). Presentation only: the tab (buildings_tab.gd) says
## what goes where.

const Metrics := preload("res://scripts/ds2/metrics.gd")
const Section := preload("res://scripts/bdp_v3_section.gd")
const Lamp := preload("res://scripts/bdp_v3_lamp.gd")
const ModKey := preload("res://scripts/bdp_v3_mod_key.gd")
const Heading := preload("res://scripts/bdp_v3_heading.gd")
const Led := preload("res://scripts/bdp_v3_led.gd")
const Nine := preload("res://scripts/bdp_v3_nine.gd")
const Indicator := preload("res://scripts/bdp_v3_indicator.gd")
const Plate := preload("res://scripts/bdp_v3_plate.gd")
const UIHelpers := preload("res://scripts/ui_helpers.gd")
const KeyedBuildingIcon := preload("res://scripts/keyed_building_icon.gd")
const Drum := preload("res://scripts/ds2/drum_figure.gd")
const Tip := preload("res://scripts/tvp_v3/buildings_tip.gd")

## Building Detail's raised module (layout.json diag_module): its shadow room and 9-slice corner.
const MODULE: Texture2D = preload("res://assets/ui/bdp_v3/diag_module.png")
const MODULE_MARGIN := 10.0 / 1.875
const MODULE_CORNER := 26.0 * 2.0 / 1.875
## Building Detail's icon well (layout.json icon_well): its reach beyond the icon, 9-slice corner and radius.
const WELL: Texture2D = preload("res://assets/ui/bdp_v3/icon_well.png")
const WELL_REACH := (12.0 + 7.0) / 1.875
const WELL_CORNER := (12.0 + 7.0 + 16.0) * 2.0 / 1.875
const WELL_RADIUS := 10.0 / 1.875
const FONT_TITLE: FontFile = preload("res://assets/fonts/IBMPlexSans-SemiBold.ttf")
const FONT_BODY: FontFile = preload("res://assets/fonts/IBMPlexSans-Medium.ttf")
const EMBLEM := "res://assets/ui/bdp_v3/bld_emblem_%s.png"
const RAISED := "res://assets/ui/bdp_v3/%s.png"

## A module's inside margins and the gap between its parts; the emblem's side (sized by its art) and the
## well's; the lamps' size as a share of the status lamp's (the diagnostics rows'), and the gap between a
## lamp and its words; the text sizes (the owner's standard: body 14, captions 15, the printed £ 18).
const PAD := Vector2(10.0, Metrics.CARD_PAD_Y)
const GAP := 10
const EMBLEM_PX := 58.0
const WELL_PX := Metrics.GOOD_ICON
const LAMP_SCALE := 0.72
const LAMP_GAP := 7
const BODY_PX := 14
const CAPTION_PX := 15
const POUND_PX := 18
const MODULE_GAP := 8
## A compact module's (a group member's) inside margin, top and bottom, and the smaller well its output
## stands in, with the quantity pill scaled to it: its height, type size and inset from the icon's corner.
const COMPACT_PAD_Y := Metrics.CARD_PAD_Y
const MEMBER_WELL_PX := Metrics.GOOD_ICON
const SMALL_PILL_H := 17
const SMALL_PILL_PX := 12
const SMALL_PILL_INSET := 3
## How far under a member's line its own words start: past the reach of the well's frame below its tile.
const WORDS_DROP := 4
## The body's parts one under another this far apart: more than their renders reach past them between
## two parts (the plastic case's shadow 7.5 px below and 3 px above, the steel frame's 6.6 px below), so
## one case's edge or shadow never lies over the next.
const CASE_GAP := 14
## The case's screws sit this far in from its edges, clear of modules DS2's plate padding in.
const CASE_SCREW_INSET := 7.0
## Room kept between the cases and the body's scroll rail while the rail shows, past the cases' shadow room.
const GUTTER := 10
## A module under the pointer is drawn this much brighter.
const HOT := Color(1.22, 1.22, 1.22)
## A good in the well of a stalled building: the cream tile left unlit.
const UNLIT := Color(0.42, 0.42, 0.44)
## About how far apart a case's screws sit, across and down (Building Detail's diagnostics case).
const SCREW_PITCH := Vector2(170.0, 130.0)
const SHORT_CASE := 110.0
## A drawer's front: its case's inside margin above and below the key while it is shut.
const DRAWER_MARGIN := 12


# --- surfaces ------------------------------------------------------------------------------

## The case's inside margin: the kit's sections' rim and padding.
static func case_margin() -> float:
	return float(Metrics.PLATE_PAD)


## Building Detail's black plastic case (its diagnostics' diag_plastic render and silver screws), its
## content inset as the kit's sections are. The screws are spaced along each edge by its length, about as
## far apart as on Building Detail's case, so a short case isn't crowded with them. A drawer's case
## (`front`) keeps its top edge to its two corner screws, clear of the key its front holds nearer that
## edge. Rows go in child 0.
static func plastic_case(case_name: String, front := false) -> MarginContainer:
	var case := MarginContainer.new()
	case.name = case_name
	case.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	case.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	case.mouse_filter = Control.MOUSE_FILTER_IGNORE
	case.set_meta("front", front)
	var m := roundi(case_margin())
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		case.add_theme_constant_override(side, m)
	var rows := VBoxContainer.new()
	rows.name = "Rows"
	rows.add_theme_constant_override("separation", MODULE_GAP)
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	case.add_child(rows)
	case.draw.connect(func() -> void:
		Nine.paint(case, Section.PLASTIC, Rect2(Vector2.ZERO, case.size).grow(Section.PLASTIC_MARGIN), Section.PLASTIC_CORNER_TEXELS)
		var s: Vector2 = Section.SCREW.get_size() / 2.0
		for p in screw_points(case.size, front):
			case.draw_texture_rect(Section.SCREW, Rect2(p - s * 0.5, s), false))
	case.resized.connect(case.queue_redraw)
	return case


## Where a case's screws go: one in each corner, then evenly along each edge about SCREW_PITCH apart. A case
## shorter than SHORT_CASE (a drawer's front, an empty case) keeps its four corner screws only, clear of
## what it holds; so does the top edge of a drawer's case (`front`).
static func screw_points(plate: Vector2, front := false) -> PackedVector2Array:
	var lo := Vector2(CASE_SCREW_INSET, CASE_SCREW_INSET)
	var hi := plate - lo
	var across := maxi(2, roundi((hi.x - lo.x) / SCREW_PITCH.x) + 1) if plate.y >= SHORT_CASE else 2
	var down := maxi(2, roundi((hi.y - lo.y) / SCREW_PITCH.y) + 1)
	var pts := PackedVector2Array()
	for i in across:
		var x := lerpf(lo.x, hi.x, float(i) / (across - 1))
		if not front or i == 0 or i == across - 1:
			pts.append(Vector2(x, lo.y))
		pts.append(Vector2(x, hi.y))
	for i in range(1, down - 1):
		var y := lerpf(lo.y, hi.y, float(i) / (down - 1))
		pts.append(Vector2(lo.x, y))
		pts.append(Vector2(hi.x, y))
	return pts


## Building Detail's raised module, as its diagnostics' rows are, with room inside. Its parts go in one row
## (child 0 of the module), at least a well tall; a compact module (a group member on its cable) is one
## line, as tall as a member's smaller well. Its hover is a readout (`Tip.attach`).
static func module(module_name: String, compact := false) -> PanelContainer:
	var m: PanelContainer = Tip.TipPanel.new()
	m.name = module_name
	var pad := StyleBoxEmpty.new()
	pad.content_margin_left = PAD.x
	pad.content_margin_right = PAD.x
	pad.content_margin_top = COMPACT_PAD_Y if compact else PAD.y
	pad.content_margin_bottom = COMPACT_PAD_Y if compact else PAD.y
	m.add_theme_stylebox_override("panel", pad)
	m.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	# PASS: the wheel still reaches the body's scroll over a module.
	m.mouse_filter = Control.MOUSE_FILTER_PASS
	m.draw.connect(func() -> void:
		Nine.paint(m, MODULE, Rect2(Vector2.ZERO, m.size).grow(MODULE_MARGIN), MODULE_CORNER))
	# Under the pointer the module's plastic catches a little more light, as Building Detail's icons do.
	m.mouse_entered.connect(func() -> void: m.self_modulate = HOT)
	m.mouse_exited.connect(func() -> void: m.self_modulate = Color.WHITE)
	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", GAP)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.custom_minimum_size = Vector2(0, float(MEMBER_WELL_PX if compact else WELL_PX))
	m.add_child(row)
	return m


static func row_of(m: PanelContainer) -> HBoxContainer:
	return m.get_child(0) as HBoxContainer


## A left click on `ctrl` runs `fn`; the pointer shows it can be pressed.
static func on_click(ctrl: Control, fn: Callable) -> void:
	ctrl.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	ctrl.gui_input.connect(func(e: InputEvent) -> void:
		var mb := e as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			ctrl.accept_event()
			fn.call())


# --- a module's parts ----------------------------------------------------------------------

## The name (semibold) over the lamp and its words (chosen by buildings_readings to fit about two lines).
## An empty tone leaves the lamp out; empty words leave the line out. `chevron` puts a group's fold mark
## after the name: meta "open" on the returned box's "Chevron" child says which way it points. A name with
## its fold mark that is wider than `room` wraps, the mark at the line's end, so a long name never widens
## the body.
static func info(title: String, tone: String, words: String, chevron := false, room := 0.0) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "Info"
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_theme_constant_override("separation", 3)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name := body(title)
	name.name = "Title"
	name.add_theme_font_override("font", FONT_TITLE)
	if chevron:
		var line := HBoxContainer.new()
		line.name = "TitleLine"
		line.add_theme_constant_override("separation", 8)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if room <= 0.0 or title_width(title) + 8.0 + 12.0 <= room:
			name.autowrap_mode = TextServer.AUTOWRAP_OFF
			name.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			name.custom_minimum_size.x = 0
		line.add_child(name)
		line.add_child(chevron_mark())
		box.add_child(line)
	else:
		box.add_child(name)
	if words == "" and tone == "":
		return box
	var status := HBoxContainer.new()
	status.name = "Status"
	status.add_theme_constant_override("separation", LAMP_GAP)
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(status)
	if tone != "":
		var lamp: Control = Lamp.new()
		lamp.name = "BuildingLamp"
		lamp.lamp_scale = LAMP_SCALE
		lamp.call("set_tone", tone)
		lamp.set_meta("tone", tone)
		status.add_child(lamp)
	var said := body(words)
	said.name = "Words"
	status.add_child(said)
	return box


## A row as a diagnostics row reads: the lamp, then the name (semibold) and, under it, the words when there
## are any.
static func line_info(title: String, tone: String, words: String) -> HBoxContainer:
	var line := HBoxContainer.new()
	line.name = "Info"
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_theme_constant_override("separation", LAMP_GAP)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if tone != "":
		var lamp: Control = Lamp.new()
		lamp.name = "BuildingLamp"
		lamp.lamp_scale = LAMP_SCALE
		lamp.call("set_tone", tone)
		lamp.set_meta("tone", tone)
		line.add_child(lamp)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.add_theme_constant_override("separation", 1)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(text)
	var name := body(title)
	name.name = "Title"
	name.add_theme_font_override("font", FONT_TITLE)
	text.add_child(name)
	if words != "":
		var said := body(words)
		said.name = "Words"
		text.add_child(said)
	return line


## Puts `words` under a module's row, across the module, `indent` in from its left (under the row's title,
## past its lamp): the row keeps its line and its figures, and the words have the module's width.
static func words_under(m: PanelContainer, words: String, indent: float) -> void:
	var row := row_of(m)
	m.remove_child(row)
	var col := VBoxContainer.new()
	col.name = "Lines"
	# The row is a member's well tall and its title sits in the middle of it. The well's frame reaches about
	# 5 px below the good's tile: the words start WORDS_DROP under the row, so their letters stand clear of
	# the frame where the words run under the well.
	col.add_theme_constant_override("separation", WORDS_DROP)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(col)
	col.add_child(row)
	var inset := MarginContainer.new()
	inset.name = "WordsLine"
	inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inset.add_theme_constant_override("margin_left", roundi(indent))
	inset.add_theme_constant_override("margin_bottom", 3)
	var said := body(words)
	said.name = "Words"
	inset.add_child(said)
	col.add_child(inset)


## A project's turns on a drum counter as tall as the LED screens beside it (never a good's quantity,
## which is the pill on its icon).
static func drum(value: int, drums: int) -> Control:
	return Drum.new(Drum.led_height(), drums, value)


## The width a lamp and its gap take before the words.
static func lamp_room() -> float:
	return roundf(Lamp.BEZEL / Lamp.CAPTURE_SCALE * LAMP_SCALE) + LAMP_GAP


## How wide `text` sets as a row's title (semibold).
static func title_width(text: String) -> float:
	return FONT_TITLE.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, BODY_PX).x


## How wide `text` sets in body type.
static func body_width(text: String) -> float:
	return FONT_BODY.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, BODY_PX).x


## A group head's fold mark, right while folded and down while open (meta "open").
static func chevron_mark() -> Control:
	var h := Control.new()
	h.name = "Chevron"
	h.custom_minimum_size = Vector2(12, 12)
	h.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.set_meta("open", true)
	h.draw.connect(func() -> void:
		var mid := h.size * 0.5
		var c := 4.5
		var pts := PackedVector2Array([mid + Vector2(-c, -c * 0.5), mid + Vector2(0, c * 0.5), mid + Vector2(c, -c * 0.5)]) \
			if bool(h.get_meta("open", true)) else \
			PackedVector2Array([mid + Vector2(-c * 0.5, -c), mid + Vector2(c * 0.5, 0), mid + Vector2(-c * 0.5, c)])
		var shade := pts.duplicate()
		for i in shade.size():
			shade[i] += Vector2(1, 1)
		h.draw_polyline(shade, Color(0, 0, 0, 0.85), 2.4, true)
		h.draw_polyline(pts, DS.PALETTE["TEXT"], 2.2, true))
	return h


## The outputs, each a good set in a well with its quantity on a pill inside the icon's corner (a quantity
## below zero shows the good alone), centred in the case's figure column (`width`), so the column holds its
## place and every figure in the case stands on one centre line. Unlit (`lit` false: the building is
## stalled and makes nothing), the good sits dark in its well over a 0. A well's hover is the game's good
## hover (its name, what the building makes of it this turn, and the encyclopedia link a click follows).
static func wells(outputs: Array, with_qty: bool, lit: bool, width: float) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.name = "Outputs"
	hb.add_theme_constant_override("separation", 8)
	hb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.custom_minimum_size = Vector2(maxf(width, WELL_PX), WELL_PX)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	for o: Dictionary in outputs.slice(0, 3):
		var gid := str(o.get("good_id", ""))
		var qty := int(o.get("qty", -1)) if with_qty else -1
		hb.add_child(good_in_well(gid, qty, output_tip(gid, qty, lit), lit))
	return hb


## What the building makes of a good this turn, under the good's name in its hover ("140 this turn"), or ""
## for a well that only names the good.
static func output_tip(gid: String, qty: int, lit := true) -> String:
	if qty < 0:
		return ""
	if not lit:
		return "Stalled, none this turn"
	return "%d MW this turn" % qty if Catalog.get_internal_name(gid) == "power" else "%d this turn" % qty


## A good in its well, `px` square: a member's line takes the smaller well (MEMBER_WELL_PX) and pill.
static func good_in_well(gid: String, qty: int, tip: String, lit := true, px: int = WELL_PX) -> Control:
	var icon := UIHelpers.make_plain_good_icon(gid, Catalog.get_internal_name(gid), px)
	if tip != "":
		icon.set("detail_lines", PackedStringArray([tip]))
	icon.mouse_filter = Control.MOUSE_FILTER_PASS
	var tile := icon.get_child(0) as PanelContainer
	if tile != null and tile.get_theme_stylebox("panel") is StyleBoxFlat:
		var st := (tile.get_theme_stylebox("panel") as StyleBoxFlat).duplicate() as StyleBoxFlat
		st.set_corner_radius_all(roundi(WELL_RADIUS))
		tile.add_theme_stylebox_override("panel", st)
	if tile != null and not lit:
		tile.modulate = UNLIT
	var well := Control.new()
	well.name = "IconWell"
	well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	well.set_anchors_preset(Control.PRESET_FULL_RECT)
	well.draw.connect(func() -> void:
		Nine.paint(well, WELL, Rect2(Vector2.ZERO, well.size).grow(WELL_REACH), WELL_CORNER))
	well.resized.connect(well.queue_redraw)
	icon.add_child(well)
	if qty >= 0:
		icon.add_child(pill(qty, px < WELL_PX))
	return icon


## Building Detail's navy quantity pill, kept inside the icon's corner; `small` for a member's smaller well:
## the same pill, shorter, its figure at 12 px, so it covers no more of the good than on the full well.
static func pill(qty: int, small := false) -> Control:
	var text := str(qty)
	var h := SMALL_PILL_H if small else 22
	var inset := SMALL_PILL_INSET if small else 5
	var w := maxi(h, ceili(FONT_TITLE.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL_PILL_PX).x) + 10) \
		if small else maxi(h, text.length() * 9 + 14)
	var p := PanelContainer.new()
	p.name = "Qty"
	p.custom_minimum_size = Vector2(w, h)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	p.offset_left = -w - inset
	p.offset_top = -h - inset
	p.offset_right = -inset
	p.offset_bottom = -inset
	var st := StyleBoxFlat.new()
	st.bg_color = DS.PALETTE["BG_PANEL"]
	st.set_corner_radius_all(int(h / 2.0))
	st.set_border_width_all(1 if small else 2)
	st.border_color = DS.PALETTE["BORDER_STRONG"]
	if small:
		st.content_margin_top = 0
		st.content_margin_bottom = 0
	p.add_theme_stylebox_override("panel", st)
	var l := Label.new()
	l.theme_type_variation = "Numeric"
	if small:
		l.add_theme_font_override("font", FONT_TITLE)
		l.add_theme_font_size_override("font_size", SMALL_PILL_PX)
	l.text = text
	l.add_theme_color_override("font_color", DS.PALETTE["ACCENT"])
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	return p


## A money figure as Building Detail prints one: the £ at 18 px, then an LED screen lit in `colour`, padded
## with blank leading digits to `digits` so every screen in a group is one width, and `suffix` (K, M) printed
## after it as the top bar prints its cash's.
static func money(amount_text: String, colour: Color, digits: int, suffix := "") -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.name = "Money"
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 4)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(caption("£", POUND_PX, HORIZONTAL_ALIGNMENT_RIGHT))
	var led: Control = Led.new()
	led.name = "Led"
	led.call("set_figure", " ".repeat(maxi(0, digits - Led.cells_for(amount_text).size())) + amount_text, colour)
	hb.add_child(led)
	if suffix != "":
		var s := caption(suffix, POUND_PX)
		s.name = "Suffix"
		hb.add_child(s)
	return hb


## How wide `money` is for a figure of `digits` cells.
static func money_width(digits: int) -> float:
	var led: Control = Led.new()
	led.call("set_figure", "8".repeat(maxi(1, digits)), Color.WHITE)
	var w: float = led.custom_minimum_size.x
	led.free()
	return Plate.FONT_SEMI.get_string_size("£", HORIZONTAL_ALIGNMENT_LEFT, -1, POUND_PX).x + 4.0 + w


## What a unit costs to make, lit in the cost's colour against the market (green below, amber about even,
## red above), and, with `market`, the market price under it: Building Detail's Cost to produce, row for
## row. `width` keeps the column one width down the case, empty or not, so the screens line up. `tip` is
## its hover readout.
static func cost_column(cost: Dictionary, digits: int, width: float, market: bool, tip: Dictionary) -> VBoxContainer:
	var col: VBoxContainer = Tip.TipVBox.new()
	col.name = "Cost"
	col.custom_minimum_size = Vector2(width, 0)
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if cost.is_empty():
		return col
	col.add_child(money("%.2f" % float(cost.unit_cost), cost.get("color", DS.PALETTE["TEXT"]), digits))
	if market:
		var m := body(market_text(cost))
		m.name = "Market"
		m.autowrap_mode = TextServer.AUTOWRAP_OFF
		m.custom_minimum_size.x = 0
		m.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(m)
	if not tip.is_empty():
		col.mouse_filter = Control.MOUSE_FILTER_PASS
		Tip.attach(col, tip)
	return col


static func market_text(cost: Dictionary) -> String:
	return "Market £%.2f" % float(cost.get("market_price", 0.0))


## A building's emblem in polished metal, Building Detail's (its render trimmed to its art, centred in a box
## `px` square), or the v2 glyph for a building with no emblem.
static func emblem(building_id: String, px: float) -> Control:
	var path := EMBLEM % building_id
	if building_id != "" and ResourceLoader.exists(path):
		return Raised.new(load(path), load(path.replace(".png", "_shadow.png")), px)
	var tex := KeyedBuildingIcon.keyed(Catalog.get_building(building_id))
	return Raised.new(tex, null, px)


## One of Building Detail's raised cream icons by layer name, with its shadow.
static func raised(layer: String, px: float) -> Control:
	return Raised.new(load(RAISED % layer), load(RAISED % (layer + "_shadow")), px)


## A real Button (named, pressable by the tutorial and tests) with Building Detail's wide cream key drawn in
## it, its words printed centred in navy, pressing while held. Its hover is a readout (`Tip.attach`).
static func key_button(text: String, button_name: String, key_scale: float) -> Button:
	var b: Button = Tip.TipButton.new()
	b.name = button_name
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# STOP: a press on a key is the key's alone, never the module's round it (Cancel must not also open the
	# project). The wheel still reaches the body's scroll (mouse_force_pass_scroll_events).
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	var key: Control = ModKey.new()
	key.set("openable", false)
	key.set("summary", text)
	key.set("centred", true)
	key.set("key_scale", key_scale)
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	key.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.add_child(key)
	b.custom_minimum_size = Vector2(0, key.custom_minimum_size.y)
	b.button_down.connect(func() -> void: key.call("set_open", true))
	b.button_up.connect(func() -> void: key.call("set_open", false))
	return b


# --- lettering -----------------------------------------------------------------------------

## A section's heading in Building Detail's raised white letters.
static func heading(text: String) -> Control:
	var hb := HBoxContainer.new()
	hb.name = "Heading"
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if Heading.can_show(text):
		var r: Control = Heading.new()
		r.set("text", text)
		hb.add_child(r)
	else:
		hb.add_child(caption(text))
	return hb


## How wide `text` sets as a metal label.
static func caption_width(text: String, px: int = CAPTION_PX) -> float:
	return Plate.FONT_SEMI.get_string_size(text.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, px).x


## A metal label: Barlow Condensed SemiBold capitals in white, standing off the surface.
static func caption(text: String, px: int = CAPTION_PX, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.uppercase = true
	l.add_theme_font_override("font", Plate.FONT_SEMI)
	l.add_theme_font_size_override("font_size", px)
	l.horizontal_alignment = align
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	emboss(l)
	return l


## A metal label centred under a figure in a column `width` wide. A label wider than the column stands out
## past it evenly on both sides (into the gaps beside the column), so the figure's column keeps its width.
static func caption_under(text: String, width: float) -> Control:
	var box := Control.new()
	box.name = "CaptionBox"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := ceilf(Plate.FONT_SEMI.get_height(CAPTION_PX))
	box.custom_minimum_size = Vector2(width, h)
	var l := caption(text, CAPTION_PX, HORIZONTAL_ALIGNMENT_CENTER)
	l.name = "Caption"
	var w := ceilf(caption_width(text)) + 2.0
	l.anchor_left = 0.5
	l.anchor_right = 0.5
	l.offset_left = -w * 0.5
	l.offset_right = w * 0.5
	l.offset_top = 0.0
	l.offset_bottom = h
	box.add_child(l)
	return box


## Body text, 14 px IBM Plex Sans Medium in white, wrapping.
static func body(text: String) -> Label:
	var l := Label.new()
	l.theme_type_variation = "Body"
	l.text = text
	l.add_theme_font_size_override("font_size", BODY_PX)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(60, 0)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	emboss(l)
	return l


static func emboss(l: Label) -> void:
	l.add_theme_color_override("font_color", DS.PALETTE["TEXT"])
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)


static func spacer(w: float, h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## The column the tab's parts stand in, CASE_GAP apart (in `rows`). While the body's scroll rail shows, it
## keeps GUTTER clear of the rail, so no case's edge or shadow runs under it; with the rail hidden the
## cases take the body's width, as far from the sheet's rim on the right as on the left.
class Column extends MarginContainer:
	var rows: VBoxContainer
	## Keep the scroll rail's room even while it hides, so the parts don't reflow when it shows (a tile
	## with other companies' buildings, whose fold opening usually brings the rail).
	var reserve := false:
		set(v):
			reserve = v
			_fit()
	var _bar: ScrollBar

	func _init(gap: int) -> void:
		name = "BuildingsBody"
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		rows = VBoxContainer.new()
		rows.name = "Parts"
		rows.add_theme_constant_override("separation", gap)
		rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(rows)

	func _enter_tree() -> void:
		var up := get_parent()
		while up != null and not up is ScrollContainer:
			up = up.get_parent()
		_bar = (up as ScrollContainer).get_v_scroll_bar() if up != null else null
		if _bar != null and not _bar.visibility_changed.is_connected(_fit):
			_bar.visibility_changed.connect(_fit)
		_fit()

	func _exit_tree() -> void:
		if _bar != null and is_instance_valid(_bar) and _bar.visibility_changed.is_connected(_fit):
			_bar.visibility_changed.disconnect(_fit)
		_bar = null

	func _fit() -> void:
		if _bar != null and _bar.visible:
			add_theme_constant_override("margin_right", GUTTER)
		elif reserve and _bar != null:
			add_theme_constant_override("margin_right", GUTTER + roundi(_bar.get_combined_minimum_size().x))
		else:
			add_theme_constant_override("margin_right", 0)


## A raised render drawn so its art, not its frame, fills a `side`-pixel box, centred on the box's midline;
## its shadow is drawn to the same rect, so it falls where it was rendered.
class Raised extends Control:
	var face: Texture2D
	var shadow: Texture2D
	var side := 40.0

	func _init(f: Texture2D, s: Texture2D, px: float) -> void:
		name = "Raised"
		face = f
		shadow = s
		side = px
		custom_minimum_size = Vector2(px, px)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

	func _draw() -> void:
		if face == null:
			return
		var art := Indicator.art_rect(face)
		var k := side / maxf(art.size.x, art.size.y)
		var art_size := art.size * k
		var at := (size - art_size) * 0.5
		var rect := Rect2(at - art.position * k, face.get_size() * k)
		if shadow != null:
			draw_texture_rect(shadow, rect, false)
		draw_texture_rect(face, rect, false)
