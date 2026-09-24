extends Control
## Building Detail v3: a two-way slide switch moulded into the diagnostics' plastic case, an off-white
## ridged thumb in a slot (res://assets/ui/bdp_v3/toggle_slot.png and toggle_knob.png, rendered by
## tools/button_mockup/cluster.html?export). A click throws it to the other side; the thumb slides there.

signal toggled(right: bool)

const SLOT: Texture2D = preload("res://assets/ui/bdp_v3/toggle_slot.png")
const KNOB: Texture2D = preload("res://assets/ui/bdp_v3/toggle_knob.png")
const CAPTURE_SCALE := 1.875
const TEXELS_PER_PIXEL := 2.0
## From layout.json (toggle), in layout pixels: the slot's inside and the thumb's width, which set how
## far the thumb travels either side of the middle.
const SLOT_INSIDE := Vector2(62.0, 18.0)
const THUMB_W := 26.0
const SLIDE_SECONDS := 0.14

var right := true
var _at := 1.0
var _tween: Tween


func _init() -> void:
	name = "BdpV3Toggle"
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	custom_minimum_size = SLOT.get_size() / TEXELS_PER_PIXEL


## Sets the side without sliding or signalling.
func set_right(value: bool) -> void:
	right = value
	_at = 1.0 if right else 0.0
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		right = not right
		if _tween != null:
			_tween.kill()
		_tween = create_tween()
		_tween.tween_method(func(v: float) -> void:
			_at = v
			queue_redraw(), _at, 1.0 if right else 0.0, SLIDE_SECONDS).set_trans(Tween.TRANS_SINE)
		toggled.emit(right)


func _draw() -> void:
	var slot := SLOT.get_size() / TEXELS_PER_PIXEL
	var origin := (size - slot) * 0.5
	draw_texture_rect(SLOT, Rect2(origin, slot), false)
	var travel := (SLOT_INSIDE.x - THUMB_W) * 0.5 - 2.0
	var knob := KNOB.get_size() / TEXELS_PER_PIXEL
	var centre := origin + slot * 0.5 + Vector2(lerpf(-travel, travel, _at) / CAPTURE_SCALE, 0.0)
	draw_texture_rect(KNOB, Rect2(centre - knob * 0.5, knob), false)
