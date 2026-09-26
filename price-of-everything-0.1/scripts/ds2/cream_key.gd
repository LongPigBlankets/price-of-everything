extends Button
## DS2 (the tile view's Transport tab): a real Button (named, pressable by tests and the tutorial) drawn as one of the
## cabinet's own cream keys (res://assets/ui/bdp_v3/tile_key.png with its _pressed and _latched renders, a
## horizontal three-slice drawn as scripts/ds2/latch_key.gd draws the five tab keys). Its print is navy:
## the action in one word, Build or Upgrade; what the action costs and brings is on its hover card
## (scripts/ds2/dot_card.gd, kept in `tip`), which opens inside the tile view's body. A key that
## opens something can have a chevron at its right end. A second, smaller line under the action is still possible, as Building Detail's Upgrade key
## prints one.
##
## While its job runs the key is latched as the cabinet's tab keys latch: the cap sunk to its bezel with the
## dark well showing round it, a shade darker, its print in the amber ink for light surfaces and a pilot
## lamp lit amber in its left end, so it plainly can't be pressed again. A key whose press would be refused
## or can't be paid for prints in the red ink for light surfaces (`title_ink`), its card saying why.
##
## A key with nothing left to do (a link at its top level) is greyed as the cabinet greys a key it can't
## press (latch_key.gd's DISABLED_TINT, its print faded), and keeps its place in the key column.

const TileKey := preload("res://scripts/ds2/latch_key.gd")
const Plate := preload("res://scripts/bdp_v3_plate.gd")
const Lamp := preload("res://scripts/bdp_v3_lamp.gd")

const NAVY := Color("#0b2340")
const AMBER_INK := Color("#7a4a00")
const RED_INK := Color("#8f1f19")
## The print's sizes: one line, or the action over what it brings (never under 12 px), and the two lines'
## cap height (Barlow's capitals stand 0.7 of the size) and the gap between them.
const ONE_LINE_PX := 18
const TITLE_PX := 15
const DETAIL_PX := 13
const MIN_PX := 12
const CAP_HEIGHT := 0.7
const LINE_GAP := 5.0
## The latched key's lamp, as a share of the status lamp; a latched cap sits this much lower.
const LAMP_SCALE := 0.5
const SUNK := 1.0

var title := ""
var detail := ""
var detail_ink := NAVY
var title_ink := NAVY
## The hover card (dot_card.gd), shown in place of a plain tooltip when set.
var tip: Dictionary = {}
var chevron := false
var busy := false
var spent := false
var key_scale := 1.0
var _lamp: Control


## A key `width` wide printing `title_text` (and `detail_text` under it); `node_name` names the Button.
static func make(node_name: String, title_text: String, detail_text: String, width: float, opens := false, latched := false,
		k := 1.0) -> Button:
	var b: Button = load("res://scripts/ds2/cream_key.gd").new()
	b.name = node_name
	b.title = title_text
	b.detail = detail_text
	b.chevron = opens
	b.key_scale = k
	b.custom_minimum_size = Vector2(width, height_for(k))
	b.set_busy(latched)
	return b


## The key's height at scale `k`: the keycap's, without the render's shadow room.
static func height_for(k := 1.0) -> float:
	return (TileKey.HEIGHT - 2.0 * TileKey.KEY_INSET) / TileKey.CAPTURE_SCALE * k


## The width a key needs to print `title_text` (and `detail_text`) at its full size.
static func width_for(title_text: String, detail_text: String, opens: bool, latched: bool, k := 1.0) -> float:
	var one := detail_text == ""
	var w := Plate.FONT_BOLD.get_string_size(title_text, HORIZONTAL_ALIGNMENT_LEFT, -1, ONE_LINE_PX if one else TITLE_PX).x
	if not one:
		w = maxf(w, Plate.FONT_SEMI.get_string_size(detail_text, HORIZONTAL_ALIGNMENT_LEFT, -1, DETAIL_PX).x)
	return ceilf(w + _room(opens, latched, k))


## The room a key's face keeps round its print: the face's inset each side, a margin, the chevron's
## room and the latched lamp's.
static func _room(opens: bool, latched: bool, k: float) -> float:
	var inset := TileKey.FACE_INSET / TileKey.CAPTURE_SCALE * k
	var room := 2.0 * inset + 12.0 * k
	if opens:
		room += 22.0 * k
	if latched:
		room += _lamp_side() + 5.0
	return room


static func _lamp_side() -> float:
	return roundf(Lamp.BEZEL / Lamp.CAPTURE_SCALE * LAMP_SCALE)


func _init() -> void:
	flat = true
	focus_mode = Control.FOCUS_NONE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	size_flags_horizontal = Control.SIZE_SHRINK_END
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for state in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)
	mouse_entered.connect(func() -> void:
		if not disabled:
			Audio.hover())
	resized.connect(_place_lamp)


## Latches the key down while its job runs (it can't be pressed), or frees it.
func set_busy(value: bool) -> void:
	busy = value
	disabled = value
	mouse_default_cursor_shape = Control.CURSOR_ARROW if value else Control.CURSOR_POINTING_HAND
	if value and _lamp == null:
		_lamp = Lamp.new()
		_lamp.name = "BusyLamp"
		_lamp.lamp_scale = LAMP_SCALE
		_lamp.set_tone("warn")
		add_child(_lamp)
	if _lamp != null:
		_lamp.visible = value
	_place_lamp()
	queue_redraw()


## Greys the key out for good: there is nothing for it to do (its tooltip says why).
func set_spent(value: bool) -> void:
	spent = value
	disabled = value or busy
	mouse_default_cursor_shape = Control.CURSOR_ARROW if disabled else Control.CURSOR_POINTING_HAND
	queue_redraw()


func _face() -> Rect2:
	var face := Rect2(Vector2.ZERO, size).grow(-TileKey.FACE_INSET / TileKey.CAPTURE_SCALE * key_scale)
	if busy:
		face.position.y += SUNK
	return face


func _place_lamp() -> void:
	if _lamp == null:
		return
	var s := _lamp_side()
	var face := _face()
	_lamp.size = Vector2(s, s)
	# Sunk with the key: the lamp sits on the face's left end.
	_lamp.position = Vector2(face.position.x + 5.0 * key_scale, face.get_center().y - s * 0.5)


func _draw() -> void:
	var held := get_draw_mode() == DRAW_PRESSED or get_draw_mode() == DRAW_HOVER_PRESSED
	var tex: Texture2D = TileKey.LATCHED if busy else (TileKey.PRESSED if held else TileKey.NORMAL)
	var tint := TileKey.LATCH_TINT if busy else (TileKey.PRESS_TINT if held else Color.WHITE)
	if spent and not busy:
		tex = TileKey.NORMAL
		tint = TileKey.DISABLED_TINT
	var k := key_scale
	var out := TileKey.KEY_INSET / TileKey.CAPTURE_SCALE * k
	var dest := Rect2(-out, -out, size.x + 2.0 * out, size.y + 2.0 * out)
	var cap_px := TileKey.CAP / TileKey.CAPTURE_SCALE * k
	var cap_tx := TileKey.CAP * TileKey.TEXELS_PER_PIXEL / TileKey.CAPTURE_SCALE
	var tw := float(tex.get_width())
	var th := float(tex.get_height())
	draw_texture_rect_region(tex, Rect2(dest.position, Vector2(cap_px, dest.size.y)), Rect2(0, 0, cap_tx, th), tint)
	draw_texture_rect_region(tex, Rect2(dest.position.x + cap_px, dest.position.y, dest.size.x - 2.0 * cap_px, dest.size.y),
		Rect2(cap_tx, 0, tw - 2.0 * cap_tx, th), tint)
	draw_texture_rect_region(tex, Rect2(dest.end.x - cap_px, dest.position.y, cap_px, dest.size.y), Rect2(tw - cap_tx, 0, cap_tx, th), tint)

	var face := _face()
	var ink := AMBER_INK if busy else (Color(NAVY, 0.5) if spent else title_ink)
	var left := face.position.x + 6.0 * k
	if busy:
		left += _lamp_side() + 5.0
	var right := face.end.x - (6.0 + (22.0 if chevron else 0.0)) * k
	var room := Rect2(left, face.position.y, maxf(right - left, 1.0), face.size.y)
	var bold: Font = Plate.FONT_BOLD
	var semi: Font = Plate.FONT_SEMI
	if detail == "":
		# One line, centred on the face as Building Detail's wide keys centre theirs.
		var fs := maxi(MIN_PX, Plate._fit(bold, title, ONE_LINE_PX, room.size.x))
		_print(bold, title, fs, room, room.get_center().y + (bold.get_ascent(fs) - bold.get_descent(fs)) * 0.5, ink)
	else:
		# Two lines, the pair of capitals centred on the face with LINE_GAP between them.
		var ts := maxi(MIN_PX, Plate._fit(bold, title, TITLE_PX, room.size.x))
		var ds := maxi(MIN_PX, Plate._fit(semi, detail, DETAIL_PX, room.size.x))
		var stack := CAP_HEIGHT * ts + LINE_GAP * key_scale + CAP_HEIGHT * ds
		var first := face.get_center().y - stack * 0.5 + CAP_HEIGHT * ts
		_print(bold, title, ts, room, first, ink)
		_print(semi, detail, ds, room, first + LINE_GAP * key_scale + CAP_HEIGHT * ds, ink if busy or spent else detail_ink)
	if chevron:
		var cx := face.end.x - 12.0 * k
		var mid := face.get_center().y
		var c := 5.0 * k
		draw_polyline(PackedVector2Array([Vector2(cx - c * 0.5, mid - c), Vector2(cx + c * 0.5, mid), Vector2(cx - c * 0.5, mid + c)]),
			ink, 2.4 * k, true)


func _make_custom_tooltip(_for_text: String) -> Object:
	return load("res://scripts/ds2/dot_card.gd").make(tip, self) if not tip.is_empty() else null


## A line printed on `baseline`, centred across `room` (from its left on a key that opens something).
func _print(font: Font, text: String, font_size: int, room: Rect2, baseline: float, ink: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var x := room.position.x + (room.size.x - w) * 0.5 if not chevron else room.position.x
	draw_string(font, Vector2(x, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ink)
