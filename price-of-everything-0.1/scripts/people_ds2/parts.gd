extends RefCounted
## The People panel's DS2 parts shared by its shell and both tabs (docs/people-ds2-plan.md): the render layers
## (assets/ui/bdp_v3/people_*.png, from tools/button_mockup/cluster.html?export&only=peoplecab,…), how they are
## drawn, the print on them and the money screens. Presentation only.

const Kit := preload("res://scripts/tvp_v3/buildings_parts.gd")
const Led := preload("res://scripts/bdp_v3_led.gd")
const Nine := preload("res://scripts/bdp_v3_nine.gd")
const Money := preload("res://scripts/ds2/money_figure.gd")
const Plate := preload("res://scripts/bdp_v3_plate.gd")
const UIFonts := preload("res://scripts/ui_fonts.gd")

const LAYOUT := 1.875
const TEXELS := 2.0 / 1.875
const NAVY := Color("#0b2340")
## Print on a light surface (brass, paper, white plastic): navy with a faint light shadow; DS2's darker inks for
## figures that judge.
const INK_LIGHT_SHADOW := Color(1, 1, 1, 0.45)
const INK := {"ok": Color("#1d6b3a"), "warn": Color("#7a4a00"), "bad": Color("#8f1f19")}
## LED colours: results green (red below zero), costs red.
const GREEN := Color("#5BD180")
const RED := Color("#E66060")
## Every money screen on the panel takes five cells, the point counted (the owner's screen rule).
const CELLS := 5
const BODY_PX := Kit.BODY_PX
const CAPTION_PX := Kit.CAPTION_PX


## The layers, held once loaded: a texture drawn from a fresh load() and dropped when the draw call returns is
## freed before the frame renders, and draws blank.
static var _held := {}

static func tex(layer: String) -> Texture2D:
	if not _held.has(layer):
		_held[layer] = load("res://assets/ui/bdp_v3/%s.png" % layer) as Texture2D
	return _held[layer]


## A layer `margin` layout px of shadow room round its part, drawn over `rect` (the part itself), cropped from its
## top down and its last `foot` layout px (with the margin under them) drawn whole at the foot, so nothing on it
## stretches. Where the rect is taller than the render the middle is stretched to fit. The width fits the rect.
static func crop_v(ci: CanvasItem, t: Texture2D, rect: Rect2, margin: float, foot: float) -> void:
	if t == null or rect.size.y <= 0.0:
		return
	var dest := rect.grow(margin / LAYOUT)
	var tw := float(t.get_width())
	var th := float(t.get_height())
	var k := tw / dest.size.x
	var foot_tx := (foot + margin) * TEXELS
	var foot_px := minf(foot_tx / k, dest.size.y * 0.5)
	var top_px := dest.size.y - foot_px
	var top_tx := minf(top_px * k, th - foot_px * k)
	ci.draw_texture_rect_region(t, Rect2(dest.position, Vector2(dest.size.x, top_px)), Rect2(0, 0, tw, top_tx))
	ci.draw_texture_rect_region(t, Rect2(dest.position + Vector2(0, top_px), Vector2(dest.size.x, foot_px)),
		Rect2(0, th - foot_px * k, tw, foot_px * k))


## A fixed render drawn at 2 texels a pixel with its part's top left at `at` (its margin reaching out round it).
static func draw_fixed(ci: CanvasItem, t: Texture2D, at: Vector2, margin: float, scale := 1.0) -> Rect2:
	var m := margin / LAYOUT * scale
	var r := Rect2(at - Vector2(m, m), t.get_size() / 2.0 * scale)
	ci.draw_texture_rect(t, r, false)
	return r


## A horizontal three-slice: the ends `cap` layout px kept, the middle stretched; the render's margin round it.
static func draw_h3(ci: CanvasItem, t: Texture2D, rect: Rect2, margin: float, cap: float) -> void:
	var dest := rect.grow(margin / LAYOUT)
	var cap_px := (cap + margin) / LAYOUT
	var cap_tx := (cap + margin) * TEXELS
	var tw := float(t.get_width())
	var th := float(t.get_height())
	ci.draw_texture_rect_region(t, Rect2(dest.position, Vector2(cap_px, dest.size.y)), Rect2(0, 0, cap_tx, th))
	ci.draw_texture_rect_region(t, Rect2(dest.position.x + cap_px, dest.position.y, dest.size.x - 2.0 * cap_px, dest.size.y),
		Rect2(cap_tx, 0, tw - 2.0 * cap_tx, th))
	ci.draw_texture_rect_region(t, Rect2(dest.end.x - cap_px, dest.position.y, cap_px, dest.size.y), Rect2(tw - cap_tx, 0, cap_tx, th))


## A 9-slice render (`corner` layout px, the margin inside it) over `rect`, its margin reaching out.
static func draw_nine(ci: CanvasItem, t: Texture2D, rect: Rect2, margin: float, corner: float) -> void:
	Nine.paint(ci, t, rect.grow(margin / LAYOUT), (corner + margin) * TEXELS)


# --- print ------------------------------------------------------------------------------------

static func body(text: String) -> Label:
	return Kit.body(text)


## A row's own title: body text, semibold.
static func title(text: String) -> Label:
	var l := Kit.body(text)
	l.add_theme_font_override("font", Kit.FONT_TITLE)
	return l


static func caption(text: String, px: int = CAPTION_PX, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	return Kit.caption(text, px, align)


static func heading(text: String) -> Control:
	return Kit.heading(text)


## Navy print on a light surface, with a faint light shadow.
static func ink(l: Label, colour: Color = NAVY) -> Label:
	l.add_theme_color_override("font_color", colour)
	l.add_theme_color_override("font_shadow_color", INK_LIGHT_SHADOW)
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	return l


## A money figure: the printed £, an LED screen of CELLS cells (the point its own cell) lit in `colour`, the K,
## M or B after it and then `unit` ("/turn").
static func money(value: float, colour: Color, unit := "", pound_px: int = Kit.POUND_PX) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.name = "Money"
	hb.add_theme_constant_override("separation", 4)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(caption("£", pound_px, HORIZONTAL_ALIGNMENT_RIGHT))
	var parts := Money.screen(value)
	var fig: String = parts.figure
	var led: Control = Led.new()
	led.name = "Led"
	led.set("point_cell", true)
	led.call("set_figure", " ".repeat(maxi(0, CELLS - fig.length())) + fig, colour)
	hb.add_child(led)
	var after := str(parts.suffix) + unit
	if after != "":
		var s := caption(after, Kit.POUND_PX if str(parts.suffix) != "" else CAPTION_PX)
		s.uppercase = false
		s.name = "Unit"
		hb.add_child(s)
	return hb


## The figure a money screen shows for `value`, as it reads on the screen ("20.72", "-10.4", "15.6K").
static func money_text(value: float) -> String:
	var parts := Money.screen(value)
	return str(parts.figure) + str(parts.suffix)


static func spacer(w: float, h: float) -> Control:
	return Kit.spacer(w, h)
