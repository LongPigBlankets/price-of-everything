extends Control
## DS2: a latching key, as the tile view's five tab keys (docs/tile-view-ds2-plan.md §9). A blank cream
## keycap in its bezel (res://assets/ui/bdp_v3/tile_key.png, _pressed and _latched, rendered by
## tools/button_mockup/cluster.html?export&only=tilekey and drawn as a horizontal three-slice), its name
## printed on its top in navy. Pressing it latches it down, where it stays while its tab is open; the
## panel unlatches the others. The latched cap sits down to its bezel, a shade darker.

signal pressed

const Plate := preload("res://scripts/bdp_v3_plate.gd")
const NORMAL: Texture2D = preload("res://assets/ui/bdp_v3/tile_key.png")
const PRESSED: Texture2D = preload("res://assets/ui/bdp_v3/tile_key_pressed.png")
const LATCHED: Texture2D = preload("res://assets/ui/bdp_v3/tile_key_latched.png")
const CAPTURE_SCALE := 1.875
const TEXELS_PER_PIXEL := 2.0
## From layout.json (tile_key), in layout pixels: the render's height, the ends kept at their size, how far
## the render reaches beyond the keycap and how far in the flat top starts. The camera looks straight
## down, so a sunk cap shows in its shadow and bezel, not by moving its top.
const HEIGHT := 116.0
const CAP := 60.0
const KEY_INSET := 16.0
const FACE_INSET := 15.6
const LATCH_TINT := Color(0.8, 0.8, 0.8)
const PRESS_TINT := Color(0.94, 0.94, 0.94)
const DISABLED_TINT := Color(0.62, 0.62, 0.62)
const NAVY := Color("#0b2340")
const LABEL_PX := 15

var text := "":
	set(v):
		text = v
		queue_redraw()
var latched := false:
	set(v):
		latched = v
		queue_redraw()
## A disabled key is greyed and doesn't press; its tooltip says why.
var disabled := false:
	set(v):
		disabled = v
		mouse_default_cursor_shape = Control.CURSOR_ARROW if v else Control.CURSOR_POINTING_HAND
		queue_redraw()
var _held := false


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(0.0, (HEIGHT - 2.0 * KEY_INSET) / CAPTURE_SCALE)


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	accept_event()
	if disabled:
		return
	if mb.pressed:
		_held = true
		queue_redraw()
	elif _held:
		_held = false
		queue_redraw()
		if Rect2(Vector2.ZERO, size).has_point(mb.position):
			pressed.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
	elif what == NOTIFICATION_MOUSE_EXIT and _held:
		_held = false
		queue_redraw()


func _draw() -> void:
	var tex := LATCHED if latched else (PRESSED if _held else NORMAL)
	var tint := LATCH_TINT if latched else (PRESS_TINT if _held else Color.WHITE)
	if disabled:
		tint = DISABLED_TINT
	var out := KEY_INSET / CAPTURE_SCALE
	var dest := Rect2(-out, -out, size.x + 2.0 * out, size.y + 2.0 * out)
	var cap_px := CAP / CAPTURE_SCALE
	var cap_tx := CAP * TEXELS_PER_PIXEL / CAPTURE_SCALE
	var tw := float(tex.get_width())
	var th := float(tex.get_height())
	draw_texture_rect_region(tex, Rect2(dest.position, Vector2(cap_px, dest.size.y)), Rect2(0, 0, cap_tx, th), tint)
	draw_texture_rect_region(tex, Rect2(dest.position.x + cap_px, dest.position.y, dest.size.x - 2.0 * cap_px, dest.size.y),
		Rect2(cap_tx, 0, tw - 2.0 * cap_tx, th), tint)
	draw_texture_rect_region(tex, Rect2(dest.end.x - cap_px, dest.position.y, cap_px, dest.size.y), Rect2(tw - cap_tx, 0, cap_tx, th), tint)
	if text == "":
		return
	var face := Rect2(Vector2.ZERO, size).grow(-FACE_INSET / CAPTURE_SCALE)
	var font: Font = Plate.FONT_SEMI
	var label := text.to_upper()
	var fs := Plate._fit(font, label, LABEL_PX, face.size.x - 6.0)
	var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var base := face.get_center().y + (font.get_ascent(fs) - font.get_descent(fs)) * 0.5
	draw_string(font, Vector2(face.get_center().x - w * 0.5, base), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(NAVY, 0.5) if disabled else (NAVY.lerp(Color.BLACK, 0.25) if latched else NAVY))
