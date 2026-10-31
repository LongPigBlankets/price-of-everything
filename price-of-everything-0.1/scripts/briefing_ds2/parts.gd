extends RefCounted
## The turn briefing's DS2 parts (docs/briefing-ds2-plan.md §5): the render layers (assets/ui/bdp_v3/brief_*.png, from
## tools/button_mockup/cluster.html?export&only=briefback,briefclip,briefwin) and the kit's parts it reuses, how they
## are drawn, and the print on them. Presentation only.

const PeopleParts := preload("res://scripts/people_ds2/parts.gd")
const Kit := preload("res://scripts/ds2/parts.gd")
const Nine := preload("res://scripts/bdp_v3_nine.gd")
const Lamp := preload("res://scripts/bdp_v3_lamp.gd")
const Led := preload("res://scripts/bdp_v3_led.gd")
const Plate := preload("res://scripts/bdp_v3_plate.gd")
const Drum := preload("res://scripts/ds2/drum_figure.gd")
const Money := preload("res://scripts/ds2/money_figure.gd")

const LAYOUT := 1.875
const TEXELS := 2.0 / 1.875
const NAVY := Color("#0b2340")
## Print on the cream letter: navy, with DS2's darker inks for figures that judge, and a faint light shadow.
const INK := {"ok": Color("#1d6b3a"), "warn": Color("#7a4a00"), "bad": Color("#8f1f19")}
const INK_LIGHT_SHADOW := Color(1, 1, 1, 0.45)
## LED colours: money paid to you green, a cost red, a loan white.
const GREEN := Color("#5BD180")
const RED := Color("#E66060")
const WHITE := Color("#E8EEF7")
## Every money screen on the panel takes five cells, the point counted (the owner's screen rule).
const CELLS := 5
const BODY_PX := 14
const CAPTION_PX := 15

## From layout.json, in layout px: each render's shadow room, the foot drawn whole, the 9-slice corners.
const BACKING_MARGIN := 24.0
const BACKING_FOOT := 80.0
const BOARD_MARGIN := 16.0
const BOARD_FOOT := 60.0
const CLIP_MARGIN := 20.0
const CLIP_SIZE := Vector2(360, 124)
const WINDOW_MARGIN := 8.0
const WINDOW_RIM := 7.0
const WINDOW_RADIUS := 5.0
## The letter is the keycaps' cream plastic sheet (sheet_white) as a 9-slice.
const LETTER_MARGIN := 14.0
const LETTER_CORNER := 54.0
## The LED screens' bezel and glass (mini_screen), for the gate and the readout.
const SCREEN_MARGIN := 8.0
const SCREEN_RIM := 7.0
const SCREEN_RADIUS := 5.0


## The layers, held once loaded: a texture drawn from a fresh load() and dropped when the draw call returns is
## freed before the frame renders, and draws blank.
static var _held := {}

static func tex(layer: String) -> Texture2D:
	if not _held.has(layer):
		_held[layer] = load("res://assets/ui/bdp_v3/%s.png" % layer) as Texture2D
	return _held[layer]


static func crop_v(ci: CanvasItem, t: Texture2D, rect: Rect2, margin: float, foot: float) -> void:
	PeopleParts.crop_v(ci, t, rect, margin, foot)


static func draw_nine(ci: CanvasItem, t: Texture2D, rect: Rect2, margin: float, corner: float) -> void:
	PeopleParts.draw_nine(ci, t, rect, margin, corner)


## A thin engraved line across a plate: a dark cut with a light edge under it.
static func rule() -> Control:
	var line := Control.new()
	line.name = "Rule"
	line.custom_minimum_size.y = 4.0
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.draw.connect(func() -> void:
		var y := line.size.y * 0.5
		line.draw_line(Vector2(0.0, y), Vector2(line.size.x, y), Color(0, 0, 0, 0.55), 1.0)
		line.draw_line(Vector2(0.0, y + 1.0), Vector2(line.size.x, y + 1.0), Color(1, 1, 1, 0.2), 1.0))
	return line


# --- print --------------------------------------------------------------------------------------

## White body print on a dark surface (DS.PALETTE.TEXT), wrapping.
static func body(text: String, px: int = BODY_PX) -> Label:
	var l := Kit.body(text)
	if px != Kit.BODY_PX:
		l.add_theme_font_size_override("font_size", px)
	return l


## A row's own title: body print, semibold.
static func title(text: String) -> Label:
	var l := Kit.body(text)
	l.add_theme_font_override("font", Kit.FONT_TITLE)
	return l


static func caption(text: String, px: int = CAPTION_PX, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	return Kit.caption(text, px, align)


## Navy print on the cream letter, with a faint light shadow; `font` and `px` choose the face.
static func ink(text: String, px: int, font: Font = null, colour: Color = NAVY) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if font != null:
		l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", colour)
	l.add_theme_color_override("font_shadow_color", INK_LIGHT_SHADOW)
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	return l


# --- figures ------------------------------------------------------------------------------------

## A money figure: the printed £, an LED screen of CELLS cells (the point its own cell) lit in `colour`, the K,
## M or B after it.
static func money(value: float, colour: Color) -> HBoxContainer:
	return PeopleParts.money(value, colour)


## A count on a drum counter as tall as the LED screens beside it, as many drums as its digits.
static func drum(value: int) -> Control:
	var digits := maxi(1, str(absi(value)).length())
	return Drum.new(Drum.led_height(), digits, absi(value))


## The figure a choice or an alert shows for {kind, value}: money on a screen, a count on a drum.
static func figure(f: Dictionary) -> Control:
	match str(f.get("kind", "")):
		"cash":
			return money(float(f.get("value", 0.0)), GREEN if float(f.get("value", 0.0)) >= 0.0 else RED)
		"cost":
			return money(absf(float(f.get("value", 0.0))), RED)
		"loan":
			return money(float(f.get("value", 0.0)), WHITE)
		_:
			return drum(int(f.get("value", 0)))


## A choice in brief, one line: its raised icon and a few words, amber for a risk (DecisionState.choice_brief:
## {icon, text, tone}).
static func brief_line(line: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Brief"
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := Kit.raised(str(line.get("icon", "")), BRIEF_ICON_PX)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var words := body(str(line.get("text", "")))
	words.name = "Words"
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if str(line.get("tone", "")) == "warn":
		words.add_theme_color_override("font_color", DS.PALETTE["WARN"])
	row.add_child(words)
	return row


## A choice explained in full, the plate that opens over it (DecisionState.choice_detail): its name, a few
## sentences, then each phase (Now, For the next 2 turns, Then...) with a row a figure: its icon, what it is,
## the start, an arrow and the outcome, how long it lasts beside a small clock, its chance in amber.
static func choice_plate(detail: Dictionary) -> Control:
	var host := PlateHost.new()
	var plate := slab("ChoicePlate")
	host.add_child(plate)
	var col := content_of(plate)
	col.custom_minimum_size.x = PLATE_W
	col.add_theme_constant_override("separation", 8)
	col.add_child(caption(str(detail.get("title", "")), 18))
	col.add_child(_plate_words(str(detail.get("text", ""))))
	for phase: Dictionary in detail.get("phases", []):
		col.add_child(rule())
		col.add_child(caption(str(phase.get("title", ""))))
		for r: Dictionary in phase.get("rows", []):
			col.add_child(detail_row(r))
		if str(phase.get("note", "")) != "":
			col.add_child(_plate_words(str(phase.note)))
	return host


## Wrapping print on the plate, as wide as the plate from the start: the tooltip's window takes its size from
## the first measure, and words measured with no width yet stand a word a line.
static func _plate_words(text: String) -> Label:
	var l := body(text)
	l.custom_minimum_size.x = PLATE_W
	return l


## One figure on the plate: its icon and what it is, then the start, an arrow and the outcome, the clock and how
## long, and the chance, right aligned.
static func detail_row(r: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Detail"
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := Kit.raised(str(r.get("icon", "")), DETAIL_ICON_PX)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var what := body(str(r.get("label", "")))
	what.name = "Label"
	what.autowrap_mode = TextServer.AUTOWRAP_OFF
	what.custom_minimum_size.x = 0
	what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	what.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(what)
	var from := str(r.get("from", ""))
	if from != "":
		row.add_child(_fit_label(title(from), "From"))
		row.add_child(Arrow.new())
	if str(r.get("to", "")) != "":
		row.add_child(_fit_label(title(str(r.to)), "To"))
	var span := str(r.get("span", ""))
	if span != "":
		var clock := Kit.raised("diag_icon_transit", SPAN_ICON_PX)
		clock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(clock)
		row.add_child(_fit_label(title(span), "Span"))
	var chance := str(r.get("chance", ""))
	if chance != "":
		var odds := _fit_label(title(chance), "Chance")
		odds.add_theme_color_override("font_color", DS.PALETTE["WARN"])
		row.add_child(odds)
	return row


## The words of a plate in plain text, for tooltip_text (which a tooltip needs to show at all, and which tests read).
static func plate_text(detail: Dictionary) -> String:
	var out := PackedStringArray([str(detail.get("title", "")), str(detail.get("text", ""))])
	for phase: Dictionary in detail.get("phases", []):
		out.append(str(phase.get("title", "")))
		for r: Dictionary in phase.get("rows", []):
			var fig := str(r.get("to", ""))
			if str(r.get("from", "")) != "":
				fig = "%s to %s" % [str(r.from), fig]
			var bits := PackedStringArray([str(r.get("label", "")), fig, str(r.get("span", "")), str(r.get("chance", ""))])
			out.append(" ".join(Array(bits).filter(func(b: String) -> bool: return b != "")))
		if str(phase.get("note", "")) != "":
			out.append(str(phase.note))
	return "\n".join(out)


const BRIEF_ICON_PX := 26.0
const DETAIL_ICON_PX := 28.0
const SPAN_ICON_PX := 18.0
const PLATE_W := 460.0


static func _fit_label(l: Label, label_name: String) -> Label:
	l.name = label_name
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.custom_minimum_size.x = 0
	return l


## A choice's row on the card: hovered anywhere, its key included, it opens the choice's plate.
class ChoiceRow extends HBoxContainer:
	var detail: Dictionary = {}

	func _make_custom_tooltip(_for_text: String) -> Object:
		return load("res://scripts/briefing_ds2/parts.gd").choice_plate(detail) if not detail.is_empty() else null


## Holds a plate in the tooltip's window, the window's own panel cleared so only the plate is drawn.
class PlateHost extends MarginContainer:
	func _init() -> void:
		name = "PlateHost"
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
			add_theme_constant_override(side, 8)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_PARENTED:
			var win := get_parent() as Window
			if win != null:
				win.add_theme_stylebox_override("panel", StyleBoxEmpty.new())


## A small arrow from a change's start to its outcome, white with the print's shadow.
class Arrow extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(20, 14)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		for pass_i in 2:
			var off := Vector2(1, 1) if pass_i == 0 else Vector2.ZERO
			var col: Color = Color(0, 0, 0, 0.8) if pass_i == 0 else DS.PALETTE["TEXT"]
			var y := size.y * 0.5
			draw_line(Vector2(2, y) + off, Vector2(size.x - 4, y) + off, col, 2.0, true)
			draw_colored_polygon(PackedVector2Array([Vector2(size.x - 8, y - 5) + off, Vector2(size.x - 1, y) + off,
				Vector2(size.x - 8, y + 5) + off]), col)


# --- surfaces -----------------------------------------------------------------------------------

## A dark glass screen in the LED screens' gunmetal bezel (mini_screen and its glass, both 9-slices), its lines
## printed white beside a pilot lamp lit in `tone` ("" for none). Sized by its content, unlike BdpV3Readout,
## so every line shows whole.
static func screen_box(box_name: String, tone: String) -> PanelContainer:
	var box := PanelContainer.new()
	box.name = box_name
	box.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pad := StyleBoxEmpty.new()
	var inset := SCREEN_RIM / LAYOUT
	pad.content_margin_left = inset + 12.0
	pad.content_margin_right = inset + 12.0
	pad.content_margin_top = inset + 9.0
	pad.content_margin_bottom = inset + 9.0
	box.add_theme_stylebox_override("panel", pad)
	var corner := (SCREEN_MARGIN + SCREEN_RIM + SCREEN_RADIUS + 2.0) * 2.0 / LAYOUT
	box.draw.connect(func() -> void:
		var r := Rect2(Vector2.ZERO, box.size).grow(SCREEN_MARGIN / LAYOUT)
		Nine.paint(box, tex("mini_screen"), r, corner)
		Nine.paint(box, tex("mini_screen_glass"), r, corner))
	box.resized.connect(box.queue_redraw)
	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(row)
	var lamp: Control = Lamp.new()
	lamp.name = "Lamp"
	lamp.lamp_scale = 0.62
	lamp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lamp.call("set_tone", tone)
	lamp.visible = tone != ""
	row.add_child(lamp)
	var lines := VBoxContainer.new()
	lines.name = "Lines"
	lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lines.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lines.add_theme_constant_override("separation", 2)
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lines)
	return box


## The lines column of a screen_box.
static func lines_of(box: PanelContainer) -> VBoxContainer:
	return box.get_node("Row/Lines") as VBoxContainer


## Building Detail's dark gunmetal slab with a silver screw in each corner (BdpV3Section style "slab").
static func slab(slab_name: String) -> MarginContainer:
	var s: MarginContainer = load("res://scripts/bdp_v3_section.gd").new()
	s.name = slab_name
	s.set("style", "slab")
	return s


static func content_of(s: MarginContainer) -> VBoxContainer:
	return s.get("content") as VBoxContainer
