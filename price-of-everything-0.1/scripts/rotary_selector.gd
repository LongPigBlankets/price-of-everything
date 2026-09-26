extends Control
## Rotary knob drawn from the pre-rendered frames in res://assets/ui/knob/ (frame 0 points at 9 o'clock,
## frame 6 at 3 o'clock). By default it has seven positions with the numbers 1–7 on an arc above it.
## Given `options` (two to seven), it has one position per option instead: each option is an icon on the
## arc that is a real button (clicking it turns the knob there; its name is its tooltip), spread over the
## frames symmetrically, with `label` printed below the knob as the only text. Click, drag the knob, or use
## the scroll wheel / arrow keys while it has focus. Presentation only: it reports `value_changed` and holds
## no state beyond its own position.

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
## Options mode: the icons' size and their arc as a multiple of the ring radius; the label's size.
const OPTION_ICON := 30.0
const OPTION_ARC := 1.78
const OPTION_LABEL_SIZE := 15
## Which frames n options use, spread symmetrically about 12 o'clock.
const OPTION_FRAMES := {2: [2, 4], 3: [1, 3, 5], 4: [0, 2, 4, 6], 5: [1, 2, 3, 4, 5], 6: [0, 1, 2, 4, 5, 6], 7: [0, 1, 2, 3, 4, 5, 6]}

## [{id, icon: Texture2D, name, enabled (default true)}]; empty for the numbered knob.
var options: Array = []: set = set_options
## Options mode: the knob's name, printed under it, and its ink (navy on a light plate, white on a dark one).
var label := "":
	set(v):
		label = v
		queue_redraw()
var label_colour: Color = Color("#0b2340")
## Options mode: the option icons' ink (white art tinted; navy on a light plate).
var option_ink: Color = Color.WHITE:
	set(v):
		option_ink = v
		_style_options()
## The option buttons, in option order (callers may rename them, e.g. for a tutorial spotlight).
var option_buttons: Array[Button] = []

var value: int = 1:
	set(v):
		var clamped := clampi(v, 1, _positions())
		if clamped == value:
			return
		value = clamped
		queue_redraw()
		_style_options()
		value_changed.emit(value)

var _dragging := false


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_fit()


## Wide enough for the 9 and 3 o'clock numbers (or icons), tall enough for the 12 o'clock one above, the
## frame's baked drop shadow below, and in options mode the label under that.
func _fit() -> void:
	var s := _scale()
	var arc := _arc_top()
	var below := (FRAME_SIZE - FRAME_CENTRE.y) * s
	if not options.is_empty():
		below += OPTION_LABEL_SIZE + 4.0
	custom_minimum_size = Vector2(maxf(knob_size, 2.0 * arc), arc + below)
	_place_options()


## Replaces the options; one button per option on the arc. The value keeps its position if it still fits.
func set_options(list: Array) -> void:
	for b: Button in option_buttons:
		b.queue_free()
	option_buttons.clear()
	options = list
	for i in options.size():
		var o: Dictionary = options[i]
		var b := Button.new()
		b.name = "KnobOption_%s" % str(o.get("id", i))
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.icon = o.get("icon", null)
		b.expand_icon = true
		b.tooltip_text = str(o.get("name", ""))
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.custom_minimum_size = Vector2(OPTION_ICON, OPTION_ICON)
		b.size = b.custom_minimum_size
		b.disabled = not bool(o.get("enabled", true))
		# No frame and no padding: a themed button's content margins would leave the icon no room.
		var bare := StyleBoxEmpty.new()
		for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
			b.add_theme_stylebox_override(state, bare)
		b.add_theme_constant_override("icon_max_width", int(OPTION_ICON))
		var at := i + 1
		b.pressed.connect(func() -> void:
			grab_focus()
			value = at)
		add_child(b)
		option_buttons.append(b)
	value = clampi(value, 1, _positions())
	_fit()
	_style_options()
	queue_redraw()


## The chosen option's icon at full strength, the others quieter, a disabled one faint.
func _style_options() -> void:
	for i in option_buttons.size():
		var b := option_buttons[i]
		b.modulate = Color(option_ink, 1.0 if i + 1 == value else (0.3 if b.disabled else 0.62))


## Sets the position without emitting `value_changed` (for initialising from saved state).
func set_value_no_signal(v: int) -> void:
	set_block_signals(true)
	value = v
	set_block_signals(false)


func _draw() -> void:
	var s := _scale()
	var centre := _centre()
	var origin := centre - FRAME_CENTRE * s
	draw_texture_rect(FRAMES[_frame(value - 1)], Rect2(origin, Vector2(FRAME_SIZE, FRAME_SIZE) * s), false)
	if not options.is_empty():
		# A tick from the ring to each option, and the knob's name under it.
		for i in options.size():
			var dir := Vector2(cos(_angle(i)), -sin(_angle(i)))
			var r0 := FRAME_RADIUS * s * 1.06
			draw_line(centre + dir * r0, centre + dir * (r0 + 6.0), label_colour, 2.0, true)
		if label != "":
			var lf := get_theme_font(&"font", &"Body")
			var ext := lf.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, OPTION_LABEL_SIZE)
			var y := centre.y + (FRAME_SIZE - FRAME_CENTRE.y) * s + lf.get_ascent(OPTION_LABEL_SIZE)
			draw_string(lf, Vector2(centre.x - ext.x * 0.5, y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, OPTION_LABEL_SIZE, label_colour)
		if has_focus():
			draw_arc(centre, FRAME_RADIUS * s + 6.0, 0.0, TAU, 64, Color(DS.PALETTE.ACCENT, 0.5), 1.5, true)
		return

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
			value = _step(1)
			accept_event()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			value = _step(-1)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				grab_focus()
				var hit := _label_at(mb.position)
				if hit >= 0:
					value = hit + 1
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
		value = _step(1)
		accept_event()
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_down"):
		value = _step(-1)
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_FOCUS_ENTER or what == NOTIFICATION_FOCUS_EXIT or what == NOTIFICATION_RESIZED:
		queue_redraw()
		if what == NOTIFICATION_RESIZED:
			_place_options()


## The next position in `dir` that can be chosen (a disabled option is passed over); the same one at the end.
func _step(dir: int) -> int:
	var v := value + dir
	while v >= 1 and v <= _positions():
		if options.is_empty() or option_buttons.size() < v or not option_buttons[v - 1].disabled:
			return v
		v += dir
	return value


func _scale() -> float:
	return knob_size / FRAME_SIZE


## How far above the knob's centre the numbers (or icons) reach.
func _arc_top() -> float:
	if options.is_empty():
		return FRAME_RADIUS * _scale() * LABEL_ARC + LABEL_SIZE_ACTIVE
	return FRAME_RADIUS * _scale() * OPTION_ARC + OPTION_ICON * 0.5 + 2.0


## Knob centre in local coordinates: horizontally centred, with room above for the arc.
func _centre() -> Vector2:
	return Vector2(size.x * 0.5, _arc_top())


func _positions() -> int:
	return POSITIONS if options.is_empty() else options.size()


## The frame (0 = 9 o'clock … 6 = 3 o'clock) position `i` shows.
func _frame(i: int) -> int:
	if options.is_empty():
		return i
	var frames: Array = OPTION_FRAMES.get(options.size(), OPTION_FRAMES[7])
	return int(frames[clampi(i, 0, frames.size() - 1)])


## Screen angle of position `i`'s pointer, measured anticlockwise from 3 o'clock.
func _angle(i: int) -> float:
	return PI * (1.0 - float(_frame(i)) / float(POSITIONS - 1))


func _place_options() -> void:
	var r := FRAME_RADIUS * _scale() * OPTION_ARC
	for i in option_buttons.size():
		var at := _centre() + Vector2(cos(_angle(i)), -sin(_angle(i))) * r
		option_buttons[i].position = (at - Vector2(OPTION_ICON, OPTION_ICON) * 0.5).round()


func _label_position(i: int) -> Vector2:
	var r := FRAME_RADIUS * _scale() * LABEL_ARC
	return _centre() + Vector2(cos(_angle(i)), -sin(_angle(i))) * r


func _label_at(p: Vector2) -> int:
	if not options.is_empty():
		return -1   # the option icons are buttons of their own
	for i in POSITIONS:
		if p.distance_to(_label_position(i)) <= LABEL_SIZE:
			return i
	return -1


## The position whose pointer direction is closest to the direction from the centre to `p`.
## Points below the centre snap to whichever end is on their side. A disabled option is skipped.
func _position_towards(p: Vector2) -> int:
	var d := p - _centre()
	var angle := atan2(-d.y, d.x)
	if angle < 0.0:
		angle = 0.0 if d.x >= 0.0 else PI
	if options.is_empty():
		return clampi(roundi((1.0 - angle / PI) * float(POSITIONS - 1)), 0, POSITIONS - 1) + 1
	var best := value
	var best_gap := INF
	for i in options.size():
		if option_buttons.size() > i and option_buttons[i].disabled:
			continue
		var gap := absf(_angle(i) - angle)
		if gap < best_gap:
			best_gap = gap
			best = i + 1
	return best
