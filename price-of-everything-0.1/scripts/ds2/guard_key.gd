extends Control
## DS2 (the tile view's Buildings tab): a guarded button for spending (docs/tile-view-ds2-plan.md §9, Spending),
## Building Detail's footer key on its own: the amber cap with its coins under a hinged clear cover, drawn
## from its region of the footer's render (guard_sell, _pressed, _cover, _cover_open), with a warm glow
## round it. The first click lifts the cover, which stands up over the cap; the second presses the cap and
## emits `pressed`. A lifted cover left alone drops after OPEN_SECONDS, as the footer's does. While
## `disabled` the cover stays down, the cap is dimmed and unlit, and clicks do nothing.
## `cover_changed` says when the cover lifts or drops, so the figure the key spends can say so.
## The lifted cover stands `overhang(side)` above the cap: whatever holds the key leaves that much room over
## it, so the cover never reaches past its module. Its hover is the tab's readout (buildings_tip.gd), in `tip`.

signal pressed
signal cover_changed(open: bool)

const Plate := preload("res://scripts/bdp_v3_plate.gd")
const Light := preload("res://scripts/bdp_v3_light.gd")
const Tip := preload("res://scripts/tvp_v3/buildings_tip.gd")
## In the footer's texture pixels (guard_sell*.png, 921 × 228): the cap, and the region drawn round it,
## from the lifted cover's top to the closed cover's foot.
const CAP := Rect2(65, 85, 126, 126)
const REGION := Rect2(58, 12, 176, 216)
## The glow: a pilot lamp's amber glow, this many times the cap's side, behind it.
const GLOW_SPAN := 2.3
const OPEN_SECONDS := 4.0
const PRESS_TINT := Color(0.93, 0.93, 0.93)
const DIM := Color(0.62, 0.62, 0.62)

var disabled := false:
	set(v):
		disabled = v
		mouse_default_cursor_shape = Control.CURSOR_ARROW if v else Control.CURSOR_POINTING_HAND
		_redraw()
## The hover readout: {stage, name, detail, tone}.
var tip: Dictionary = {}
var _open_left := 0.0
var _held := false
var _glow: Control


func _init(px: float) -> void:
	name = "GuardKey"
	custom_minimum_size = Vector2(px, px)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# PASS: left clicks are taken here; the wheel still reaches the body's scroll.
	mouse_filter = Control.MOUSE_FILTER_PASS
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_glow = Control.new()
	_glow.name = "Glow"
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow.show_behind_parent = true
	_glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_glow.material = Light.glow_material()
	_glow.draw.connect(_draw_glow)
	add_child(_glow)
	set_process(false)


## How far the lifted cover stands above a cap `side` px square.
static func overhang(side: float) -> float:
	return (CAP.position.y - REGION.position.y) * side / CAP.size.x


func _make_custom_tooltip(_for_text: String) -> Object:
	return Tip.make(tip) if not tip.is_empty() else null


func is_open() -> bool:
	return _open_left > 0.0


func lift() -> void:
	if disabled:
		return
	var was := is_open()
	_open_left = OPEN_SECONDS
	set_process(true)
	_redraw()
	if not was:
		cover_changed.emit(true)


func drop() -> void:
	var was := is_open()
	_open_left = 0.0
	_held = false
	set_process(false)
	_redraw()
	if was:
		cover_changed.emit(false)


func _process(delta: float) -> void:
	_open_left -= delta
	if _open_left <= 0.0 and not _held:
		drop()


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	accept_event()
	if disabled:
		return
	if mb.pressed:
		if is_open():
			_held = true
			_redraw()
		return
	if _held:
		_held = false
		drop()
		if Rect2(Vector2.ZERO, size).has_point(mb.position):
			pressed.emit()
	else:
		lift()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_redraw()
	elif what == NOTIFICATION_MOUSE_EXIT and _held:
		_held = false
		_redraw()


func _redraw() -> void:
	queue_redraw()
	if _glow != null:
		_glow.queue_redraw()


## Where the region of the footer's frame lands, the cap filling this control.
func _region_rect() -> Rect2:
	var k := size.x / CAP.size.x
	return Rect2((REGION.position - CAP.position) * k, REGION.size * k)


func _draw() -> void:
	var down := _held and is_open()
	var tint := DIM if disabled else (PRESS_TINT if down else Color.WHITE)
	draw_texture_rect_region(Plate.tex("guard_sell_pressed" if down else "guard_sell"), _region_rect(), REGION, tint)
	draw_texture_rect_region(Plate.tex("guard_sell_cover_open" if is_open() else "guard_sell_cover"), _region_rect(), REGION)


func _draw_glow() -> void:
	if disabled:
		return
	var side := size.x * GLOW_SPAN
	_glow.draw_texture_rect(Plate.tex("lamp_glow_amber"), Rect2(size * 0.5 - Vector2(side, side) * 0.5, Vector2(side, side)), false,
		Color(1, 1, 1, 0.85 if is_open() else 0.6))
