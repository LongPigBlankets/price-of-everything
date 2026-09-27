extends RefCounted
## The turn briefing's DS2 parts (docs/briefing-ds2-plan.md §5): the render layers (assets/ui/bdp_v3/brief_*.png, from
## tools/button_mockup/cluster.html?export&only=briefback,briefclip,briefwin) and the kit's parts it reuses, how they
## are drawn, and the print on them. Presentation only.

const PeopleParts := preload("res://scripts/people_ds2/parts.gd")
const Kit := preload("res://scripts/tvp_v3/buildings_parts.gd")
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
