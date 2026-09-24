extends Control
## Building Detail v3: a wide key for a row that opens, a worn off-white keycap like Inputs' and Outputs'
## (res://assets/ui/bdp_v3/key_modifiers.png and _pressed, rendered blank by
## tools/button_mockup/cluster.html?export and drawn as a horizontal three-slice), with its text printed
## on its top in navy, as Inputs' key prints its route, and a chevron at its right end. It latches down
## while what it opens is open. The Modifiers key prints the output modifier (or None); the economics'
## rows print their names.

signal toggled(open: bool)

const Plate := preload("res://scripts/bdp_v3_plate.gd")
const NORMAL: Texture2D = preload("res://assets/ui/bdp_v3/key_modifiers.png")
const PRESSED: Texture2D = preload("res://assets/ui/bdp_v3/key_modifiers_pressed.png")
const CAPTURE_SCALE := 1.875
const TEXELS_PER_PIXEL := 2.0
## From layout.json (key_modifiers), in layout pixels: the render's height, the ends kept at their size,
## how far the render reaches beyond the keycap, and how far in from the keycap's edge its flat top is.
const HEIGHT := 120.0
const CAP := 64.0
const KEY_INSET := 16.0
const FACE_INSET := 15.6
const PRESS_TINT := Color(0.93, 0.93, 0.93)
const NAVY := Color("#0b2340")

var open := false
## The text printed on the key, and its ink.
var summary := ""
var summary_ink := NAVY
var _held := false


func _init() -> void:
	name = "BdpV3ModKey"
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(0.0, (HEIGHT - 2.0 * KEY_INSET) / CAPTURE_SCALE)


func set_open(value: bool) -> void:
	open = value
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	accept_event()
	if mb.pressed:
		_held = true
		queue_redraw()
	elif _held:
		_held = false
		if Rect2(Vector2.ZERO, size).has_point(mb.position):
			open = not open
			toggled.emit(open)
		queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_MOUSE_EXIT:
		if what == NOTIFICATION_MOUSE_EXIT and _held:
			_held = false
		queue_redraw()


func _draw() -> void:
	var down := open or _held
	var tex := PRESSED if down else NORMAL
	# The render reaches KEY_INSET beyond the keycap on every side (its bezel's shadow).
	var out := KEY_INSET / CAPTURE_SCALE
	var dest := Rect2(-out, -out, size.x + 2.0 * out, size.y + 2.0 * out)
	var cap_px := CAP / CAPTURE_SCALE
	var cap_tx := CAP * TEXELS_PER_PIXEL / CAPTURE_SCALE
	var tw := float(tex.get_width())
	var th := float(tex.get_height())
	var tint := PRESS_TINT if down else Color.WHITE
	draw_texture_rect_region(tex, Rect2(dest.position, Vector2(cap_px, dest.size.y)), Rect2(0, 0, cap_tx, th), tint)
	draw_texture_rect_region(tex, Rect2(dest.position.x + cap_px, dest.position.y, dest.size.x - 2.0 * cap_px, dest.size.y),
		Rect2(cap_tx, 0, tw - 2.0 * cap_tx, th), tint)
	draw_texture_rect_region(tex, Rect2(dest.end.x - cap_px, dest.position.y, cap_px, dest.size.y), Rect2(tw - cap_tx, 0, cap_tx, th), tint)
	# The print on the flat top: the summary from its left, the chevron at its right end, pointing down
	# while open.
	var face := Rect2(Vector2.ZERO, size).grow(-FACE_INSET / CAPTURE_SCALE)
	var mid := face.get_center().y
	var bold: Font = Plate.FONT_BOLD
	if summary != "":
		var fs := Plate._fit(bold, summary, 22, face.size.x - 34.0)
		draw_string(bold, Vector2(face.position.x + 6.0, _baseline(bold, fs, mid)), summary, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, summary_ink)
	var cx := face.end.x - 12.0
	var c := 5.0
	var pts := PackedVector2Array([Vector2(cx - c, mid - c * 0.5), Vector2(cx, mid + c * 0.5), Vector2(cx + c, mid - c * 0.5)]) if open \
		else PackedVector2Array([Vector2(cx - c * 0.5, mid - c), Vector2(cx + c * 0.5, mid), Vector2(cx - c * 0.5, mid + c)])
	draw_polyline(pts, NAVY, 2.4, true)


static func _baseline(font: Font, font_size: int, mid: float) -> float:
	return mid + (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
