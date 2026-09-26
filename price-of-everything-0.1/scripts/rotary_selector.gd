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
## Options mode: each option on a square of black plastic (no screws), always shown, its icon embossed in
## `option_ink` and greyed when the option can't be chosen; and the icons' size against OPTION_ICON. Set both
## before `options`.
var option_plates := false
var option_scale := 1.0
## Options mode: where the label stands, this far below the knob's ring; at its default (-1) it stands under
## the frame's drop shadow as before.
var label_gap := -1.0
const PLATE_PAD := 6.0
const PLATE_FILL := Color("#1d1f23")
const PLATE_EDGE := Color("#3b3f45")
const PLATE_LIT := Color(1, 1, 1, 0.10)
const PLATE_RADIUS := 6
## An option's icon: chosen, free to choose, and greyed.
const ICON_ALPHA := {"chosen": 1.0, "open": 0.72}
const ICON_GREY := Color(0.45, 0.45, 0.47, 0.8)
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
		below = _label_top() - _centre_y_offset() + OPTION_LABEL_SIZE + 4.0 if label_gap >= 0.0 else below + OPTION_LABEL_SIZE + 4.0
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
		b.icon = null if option_plates else o.get("icon", null)
		b.expand_icon = true
		if option_plates:
			var face := OptionFace.new()
			face.icon = o.get("icon", null)
			face.pad = PLATE_PAD
			face.selector = self
			face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			b.add_child(face)
		b.tooltip_text = str(o.get("name", ""))
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.custom_minimum_size = Vector2(_option_side(), _option_side())
		b.size = b.custom_minimum_size
		b.disabled = not bool(o.get("enabled", true))
		# No frame and no padding: a themed button's content margins would leave the icon no room.
		var bare := StyleBoxEmpty.new()
		for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
			b.add_theme_stylebox_override(state, bare)
		b.add_theme_constant_override("icon_max_width", int(_option_side()))
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
		var alpha := 1.0 if i + 1 == value else (0.3 if b.disabled else 0.62)
		# On plates the plate always shows and the face inks and greys its own icon.
		b.modulate = Color.WHITE if option_plates else Color(option_ink, alpha)
		if option_plates and b.get_child_count() > 0:
			(b.get_child(0) as Control).queue_redraw()


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
			var y := (centre.y - _centre_y_offset() + _label_top() if label_gap >= 0.0 else centre.y + (FRAME_SIZE - FRAME_CENTRE.y) * s) \
				+ lf.get_ascent(OPTION_LABEL_SIZE)
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
	return FRAME_RADIUS * _scale() * OPTION_ARC + _option_side() * 0.5 + 2.0


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
		option_buttons[i].position = (at - Vector2(_option_side(), _option_side()) * 0.5).round()


## The label's top below the knob's centre when `label_gap` places it: the ring's radius and the gap.
func _label_top() -> float:
	return _centre_y_offset() + FRAME_RADIUS * _scale() + label_gap


## The knob's centre below the control's top (what _centre gives, taken as an offset).
func _centre_y_offset() -> float:
	return _arc_top()


## An option's square: its icon at `option_scale`, and round it the plastic plate's padding when it has one.
func _option_side() -> float:
	return OPTION_ICON * option_scale + (2.0 * PLATE_PAD if option_plates else 0.0)


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


## An option on its black plastic square: the plate (a moulded edge lit along its top), then the icon embossed,
## a dark copy down and to the right under it, in the selector's ink, fainter when not chosen and grey when the
## option can't be chosen.
class OptionFace extends Control:
	var icon: Texture2D
	var pad := 6.0
	var selector: Control

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

	func _draw() -> void:
		var box := Rect2(Vector2.ZERO, size)
		var c: Dictionary = (selector.get_script() as Script).get_script_constant_map()
		var plate := StyleBoxFlat.new()
		plate.bg_color = c["PLATE_FILL"]
		plate.border_color = c["PLATE_EDGE"]
		plate.set_border_width_all(1)
		plate.set_corner_radius_all(int(c["PLATE_RADIUS"]))
		draw_style_box(plate, box)
		draw_line(Vector2(4.0, 1.5), Vector2(size.x - 4.0, 1.5), c["PLATE_LIT"], 1.0)
		if icon == null:
			return
		var button := get_parent() as Button
		var buttons: Array = selector.get("option_buttons")
		var chosen: bool = button != null and buttons.find(button) + 1 == int(selector.get("value"))
		var ink: Color = selector.get("option_ink")
		if button != null and button.disabled:
			ink = c["ICON_GREY"]
		elif not chosen:
			ink = Color(ink, float(c["ICON_ALPHA"]["open"]))
		var art := box.grow(-pad)
		var k := minf(art.size.x / icon.get_width(), art.size.y / icon.get_height())
		var dest := Rect2(art.position + (art.size - icon.get_size() * k) * 0.5, icon.get_size() * k)
		draw_texture_rect(icon, Rect2(dest.position + Vector2(1.5, 1.5), dest.size), false, Color(0, 0, 0, 0.85 * ink.a))
		draw_texture_rect(icon, Rect2(dest.position + Vector2(-0.5, -0.5), dest.size), false, Color(1, 1, 1, 0.18 * ink.a))
		draw_texture_rect(icon, dest, false, ink)
