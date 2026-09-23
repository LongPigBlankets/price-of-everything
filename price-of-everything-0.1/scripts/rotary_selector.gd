extends Control
## Seven-position rotary knob drawn from the pre-rendered frames in res://assets/ui/knob/
## (frame 0 points at 9 o'clock, frame 6 at 3 o'clock), with the position numbers 1–7 on an
## arc above it. Click a number to jump to it, drag the knob to turn it, or use the scroll
## wheel / arrow keys while it has focus. Presentation only: it reports `value_changed`
## and holds no state beyond its own position.

signal value_changed(value: int)

const FRAMES: Array[Texture2D] = [
	preload("res://assets/ui/knob/knob_0.png"), preload("res://assets/ui/knob/knob_1.png"),
	preload("res://assets/ui/knob/knob_2.png"), preload("res://assets/ui/knob/knob_3.png"),
	preload("res://assets/ui/knob/knob_4.png"), preload("res://assets/ui/knob/knob_5.png"),
	preload("res://assets/ui/knob/knob_6.png"),
]
const POSITIONS := 7
## Where the knob sits inside every 512 px frame: its centre and chrome-ring radius.
const FRAME_SIZE := 512.0
const FRAME_CENTRE := Vector2(256.0, 243.0)
const FRAME_RADIUS := 166.0
## Number arc radius as a multiple of the ring radius, and the number font size.
const LABEL_ARC := 1.42
const LABEL_SIZE := 18
const LABEL_SIZE_ACTIVE := 22

## Displayed width and height of a knob frame, in pixels.
@export var knob_size: float = 240.0

var value: int = 1:
	set(v):
		var clamped := clampi(v, 1, POSITIONS)
		if clamped == value:
			return
		value = clamped
		queue_redraw()
		value_changed.emit(value)

var _dragging := false


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var s := _scale()
	var arc := FRAME_RADIUS * s * LABEL_ARC + LABEL_SIZE_ACTIVE
	# Wide enough for the 9 and 3 o'clock numbers, tall enough for the 12 o'clock number
	# above and the frame's baked drop shadow below.
	custom_minimum_size = Vector2(maxf(knob_size, 2.0 * arc), arc + (FRAME_SIZE - FRAME_CENTRE.y) * s)


## Sets the position without emitting `value_changed` (for initialising from saved state).
func set_value_no_signal(v: int) -> void:
	set_block_signals(true)
	value = v
	set_block_signals(false)


func _draw() -> void:
	var s := _scale()
	var centre := _centre()
	var origin := centre - FRAME_CENTRE * s
	draw_texture_rect(FRAMES[value - 1], Rect2(origin, Vector2(FRAME_SIZE, FRAME_SIZE) * s), false)

	var font := get_theme_font(&"font", &"Numeric")
	for i in POSITIONS:
		var active := i + 1 == value
		var size := LABEL_SIZE_ACTIVE if active else LABEL_SIZE
		var colour: Color = DS.PALETTE.ACCENT if active else DS.PALETTE.TEXT_MUTED
		var text := str(i + 1)
		var extent := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
		var at := _label_position(i) + Vector2(-extent.x * 0.5, font.get_ascent(size) - extent.y * 0.5)
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, colour)
	if has_focus():
		draw_arc(centre, FRAME_RADIUS * s + 6.0, 0.0, TAU, 64, Color(DS.PALETTE.ACCENT, 0.5), 1.5, true)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			value += 1
			accept_event()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			value -= 1
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				grab_focus()
				var label := _label_at(mb.position)
				if label >= 0:
					value = label + 1
				elif mb.position.distance_to(_centre()) <= FRAME_RADIUS * _scale():
					_dragging = true
					value = _position_towards(mb.position)
			else:
				_dragging = false
			accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _dragging:
			value = _position_towards(mm.position)
			accept_event()
		else:
			var over_knob := mm.position.distance_to(_centre()) <= FRAME_RADIUS * _scale()
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if over_knob or _label_at(mm.position) >= 0 else Control.CURSOR_ARROW
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("ui_up"):
		value += 1
		accept_event()
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_down"):
		value -= 1
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_FOCUS_ENTER or what == NOTIFICATION_FOCUS_EXIT or what == NOTIFICATION_RESIZED:
		queue_redraw()


func _scale() -> float:
	return knob_size / FRAME_SIZE


## Knob centre in local coordinates: horizontally centred, with room above for the arc.
func _centre() -> Vector2:
	var arc := FRAME_RADIUS * _scale() * LABEL_ARC + LABEL_SIZE_ACTIVE
	return Vector2(size.x * 0.5, arc)


## Screen angle of position `i` (0 = 9 o'clock … 6 = 3 o'clock), measured anticlockwise from 3 o'clock.
func _angle(i: int) -> float:
	return PI * (1.0 - float(i) / float(POSITIONS - 1))


func _label_position(i: int) -> Vector2:
	var r := FRAME_RADIUS * _scale() * LABEL_ARC
	return _centre() + Vector2(cos(_angle(i)), -sin(_angle(i))) * r


func _label_at(p: Vector2) -> int:
	for i in POSITIONS:
		if p.distance_to(_label_position(i)) <= LABEL_SIZE:
			return i
	return -1


## The position whose pointer direction is closest to the direction from the centre to `p`.
## Points below the centre snap to whichever end (1 or 7) is on their side.
func _position_towards(p: Vector2) -> int:
	var d := p - _centre()
	var angle := atan2(-d.y, d.x)
	if angle < 0.0:
		angle = 0.0 if d.x >= 0.0 else PI
	return clampi(roundi((1.0 - angle / PI) * float(POSITIONS - 1)), 0, POSITIONS - 1) + 1
