extends Control
## DS2 (the tile view's Buildings tab): a drum counter at rest, Building Detail's (bdp_v3_counter.gd: the gunmetal
## housing, black drums and the glass over them, counter_housing.png and counter_glass.png), drawn to a
## height of the tab's choosing so it stands as tall as the LED screens beside it. The housing's ends and
## drums scale together; the digits are printed live at the matching size, so they stay sharp. Every drum
## shows its digit, leading ones as 0, as a real counter's do.

const Counter := preload("res://scripts/bdp_v3_counter.gd")
const Plate := preload("res://scripts/bdp_v3_plate.gd")
const Led := preload("res://scripts/bdp_v3_led.gd")

var drums := 1
var value := 0
## Logical px per layout px of the counter's render.
var _s := 1.0 / Counter.CAPTURE_SCALE


## The LED screens' height (bdp_v3_led.gd: a digit's cell, its padding and the bezel), which the tab's
## drums are drawn to.
static func led_height() -> float:
	return Led.CELL.y + 2.0 * Led.PAD.y + 2.0 * Led.RIM / Led.CAPTURE_SCALE


## A counter's width for `drum_count` drums at `height`.
static func width_for(drum_count: int, height: float) -> float:
	return (2.0 * Counter.CAP + maxi(1, drum_count) * Counter.CELL) * height / Counter.HEIGHT


func _init(height: float, drum_count: int, v: int) -> void:
	name = "Drum"
	drums = maxi(1, drum_count)
	value = maxi(0, v)
	_s = height / Counter.HEIGHT
	custom_minimum_size = Vector2(width_for(drums, height), height)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func _draw() -> void:
	var origin := (size - custom_minimum_size) * 0.5
	_slices(Counter.HOUSING, origin)
	var font: Font = Plate.FONT_SEMI
	var px := roundi(Counter.DIGIT_SIZE * _s * Counter.CAPTURE_SCALE)
	var top := origin.y + Counter.WINDOW.x * _s
	var win_h := (Counter.WINDOW.y - Counter.WINDOW.x) * _s
	var baseline := top + win_h * 0.5 + (font.get_ascent(px) - font.get_descent(px)) * 0.5
	var digits := Counter.digits_for(float(value), drums, 0)
	for i in drums:
		var d := str(digits[i])
		var cell_x := origin.x + (Counter.CAP + i * Counter.CELL) * _s
		var w := font.get_string_size(d, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		draw_string(font, Vector2(cell_x + (Counter.CELL * _s - w) * 0.5, baseline), d, HORIZONTAL_ALIGNMENT_LEFT,
			-1, px, Counter.DIGIT_INK)
	_slices(Counter.GLASS, origin)


## The render's three slices: an end, one drum's cell per drum, the other end.
func _slices(tex: Texture2D, origin: Vector2) -> void:
	var k := Counter.TEXELS_PER_PIXEL / Counter.CAPTURE_SCALE
	var h := Counter.HEIGHT * _s
	var th := float(tex.get_height())
	var cap := Counter.CAP * _s
	var cell := Counter.CELL * _s
	draw_texture_rect_region(tex, Rect2(origin, Vector2(cap, h)), Rect2(0, 0, Counter.CAP * k, th))
	for i in drums:
		draw_texture_rect_region(tex, Rect2(origin + Vector2(cap + i * cell, 0), Vector2(cell, h)),
			Rect2(Counter.REPEAT_FROM * k, 0, Counter.CELL * k, th))
	draw_texture_rect_region(tex, Rect2(origin + Vector2(cap + drums * cell, 0), Vector2(cap, h)),
		Rect2(tex.get_width() - Counter.CAP * k, 0, Counter.CAP * k, th))
