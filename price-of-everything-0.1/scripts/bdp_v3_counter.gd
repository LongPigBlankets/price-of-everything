extends Control
## Building Detail v3: a mechanical drum counter. A gunmetal housing with black drums in its window
## (res://assets/ui/bdp_v3/counter_housing.png), the digits printed on the drums live so they can roll,
## and counter_glass.png over them: the drums' curve shading away top and bottom, the window lip's
## shadow and a faint glare. Both renders are horizontal three-slices whose middle cell repeats once
## per drum. Rendered by tools/button_mockup/cluster.html?export.
##
## When the value changes (set_value with a `from`), the drums roll to it like an odometer's: each
## drum turns only while the one below it passes from 9 to 0.

const Plate := preload("res://scripts/bdp_v3_plate.gd")
const HOUSING: Texture2D = preload("res://assets/ui/bdp_v3/counter_housing.png")
const GLASS: Texture2D = preload("res://assets/ui/bdp_v3/counter_glass.png")
const CAPTURE_SCALE := 1.875
const TEXELS_PER_PIXEL := 2.0
## From layout.json (counter), in layout pixels: the ends kept at their size, a drum's cell, the
## render's height, the window's rows, and the cell the repeat is taken from.
const CAP := 18.0
const CELL := 30.0
const HEIGHT := 52.0
const WINDOW := Vector2(9.0, 43.0)
const REPEAT_FROM := 78.0
const DIGIT_INK := Color("#efede6")
const DIGIT_SIZE := 17
const ROLL_SECONDS := 0.5

var drums := 4
var decimals := 0
var value := 0.0
var _from := 0.0
var _t := 1.0
var _digits: Control
var _glass: Control


## The digits the counter reads at rest, most significant first (a value too large shows nines).
static func digits_for(v: float, drum_count: int, decimal_count: int) -> PackedInt32Array:
	var u := roundi(maxf(v, 0.0) * pow(10.0, decimal_count))
	u = mini(u, roundi(pow(10.0, drum_count)) - 1)
	var out := PackedInt32Array()
	for i in drum_count:
		out.append(int(u / roundi(pow(10.0, drum_count - 1 - i))) % 10)
	return out


## The drum count a value needs, at least `at_least`.
static func drums_for(v: float, decimal_count: int, at_least: int) -> int:
	return maxi(at_least, str(roundi(maxf(v, 0.0) * pow(10.0, decimal_count))).length())


func _init() -> void:
	name = "BdpV3Counter"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_digits = Control.new()
	_digits.name = "Digits"
	_digits.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_digits.clip_contents = true
	_digits.draw.connect(_draw_digits)
	add_child(_digits)
	_glass = Control.new()
	_glass.name = "Glass"
	_glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glass.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_glass.draw.connect(_draw_glass)
	add_child(_glass)
	set_process(false)
	configure(drums, decimals)


func configure(drum_count: int, decimal_count: int) -> void:
	drums = maxi(1, drum_count)
	decimals = clampi(decimal_count, 0, drums - 1)
	custom_minimum_size = Vector2((2.0 * CAP + drums * CELL) / CAPTURE_SCALE, HEIGHT / CAPTURE_SCALE)
	_digits.position = Vector2(CAP, WINDOW.x) / CAPTURE_SCALE
	_digits.size = Vector2(drums * CELL, WINDOW.y - WINDOW.x) / CAPTURE_SCALE
	_redraw()


## Shows `v`, rolling the drums to it from `from` when that is given and differs.
func set_value(v: float, from: float = NAN) -> void:
	value = maxf(v, 0.0)
	if is_nan(from) or is_equal_approx(from, value):
		_t = 1.0
		set_process(false)
	else:
		_from = maxf(from, 0.0)
		_t = 0.0
		set_process(true)
	_redraw()


func _process(delta: float) -> void:
	_t = minf(1.0, _t + delta / ROLL_SECONDS)
	if _t >= 1.0:
		set_process(false)
	_redraw()


func _redraw() -> void:
	queue_redraw()
	_digits.queue_redraw()
	_glass.queue_redraw()


func _shown() -> float:
	return lerpf(_from, value, ease(_t, -2.0))


func _cells(tex: Texture2D) -> Array:
	var k := TEXELS_PER_PIXEL / CAPTURE_SCALE
	var cap_px := CAP / CAPTURE_SCALE
	var cell_px := CELL / CAPTURE_SCALE
	var h := HEIGHT / CAPTURE_SCALE
	var out: Array = [[Rect2(0, 0, cap_px, h), Rect2(0, 0, CAP * k, tex.get_height())]]
	for i in drums:
		out.append([Rect2(cap_px + i * cell_px, 0, cell_px, h), Rect2(REPEAT_FROM * k, 0, CELL * k, tex.get_height())])
	out.append([Rect2(cap_px + drums * cell_px, 0, cap_px, h), Rect2(tex.get_width() - CAP * k, 0, CAP * k, tex.get_height())])
	return out


func _draw() -> void:
	for c: Array in _cells(HOUSING):
		draw_texture_rect_region(HOUSING, c[0], c[1])


func _draw_digits() -> void:
	var font: Font = Plate.FONT_SEMI
	var cell_px := CELL / CAPTURE_SCALE
	var win_h := (WINDOW.y - WINDOW.x) / CAPTURE_SCALE
	var ascent := font.get_ascent(DIGIT_SIZE)
	var baseline := win_h * 0.5 + (ascent - font.get_descent(DIGIT_SIZE)) * 0.5
	var u := _shown() * pow(10.0, decimals)
	if _t >= 1.0:
		u = roundf(u)   # at rest the drums read exactly (54.17 x 100 is 5416.999...)
	for i in drums:
		var place := drums - 1 - i   # 0 is the last drum
		var p := pow(10.0, place)
		var digit := int(floor(u / p)) % 10
		# The last drum turns with the value; each one before it only while the one below it
		# passes from 9 to 0.
		var turn := u - floorf(u) if place == 0 else clampf(fmod(u, p) - (p - 1.0), 0.0, 1.0)
		for step in 2:
			var d := (digit + step) % 10
			var y := baseline + (float(step) - turn) * win_h
			var w := font.get_string_size(str(d), HORIZONTAL_ALIGNMENT_LEFT, -1, DIGIT_SIZE).x
			_digits.draw_string(font, Vector2(i * cell_px + (cell_px - w) * 0.5, y), str(d), HORIZONTAL_ALIGNMENT_LEFT, -1, DIGIT_SIZE, DIGIT_INK)


func _draw_glass() -> void:
	for c: Array in _cells(GLASS):
		_glass.draw_texture_rect_region(GLASS, c[0], c[1])
	if decimals > 0:
		# The decimal point, printed on the housing between the whole drums and the fractional ones.
		var x := (CAP + (drums - decimals) * CELL) / CAPTURE_SCALE
		_glass.draw_circle(Vector2(x, (WINDOW.y - 5.0) / CAPTURE_SCALE), 1.4, DIGIT_INK)
