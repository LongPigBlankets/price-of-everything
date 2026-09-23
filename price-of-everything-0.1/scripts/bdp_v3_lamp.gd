extends Control
## Building Detail v3: the status lamp in the panel's header. A pilot lamp standing on the backing,
## lit green, amber or red for the building's status tone, or off (res://assets/ui/bdp_v3/lamp_*.png,
## rendered by tools/button_mockup/cluster.html?export). A lit lamp also draws its glow, additively,
## in its own canvas item.
##
## The render is LAMP_FRAME layout pixels square with the bezel in its middle. This control is the
## bezel's size, so it lines up with the text beside it, and the render overflows it.

const Plate := preload("res://scripts/bdp_v3_plate.gd")
const CAPTURE_SCALE := 1.875
## From layout.json (status_lamp): the render's side and the bezel's diameter, in layout pixels.
const LAMP_FRAME := 112.0
const BEZEL := 44.0
## Status tone -> lamp colour. Any other tone (e.g. "info" on an NPC-owned building) leaves it off.
const COLOURS := {"ok": "green", "good": "green", "warn": "amber", "bad": "red"}

var colour := "off"
var _glow: Control


static func colour_for(tone: String) -> String:
	return str(COLOURS.get(tone, "off"))


func _init() -> void:
	name = "BdpV3Lamp"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var side := roundf(BEZEL / CAPTURE_SCALE)
	custom_minimum_size = Vector2(side, side)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_glow = Control.new()
	_glow.name = "Glow"
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = add
	_glow.draw.connect(_draw_glow)
	add_child(_glow)


func set_tone(tone: String) -> void:
	colour = colour_for(tone)
	queue_redraw()
	_glow.queue_redraw()


func _frame_rect() -> Rect2:
	var side := LAMP_FRAME / CAPTURE_SCALE
	return Rect2((size - Vector2(side, side)) * 0.5, Vector2(side, side))


func _draw() -> void:
	draw_texture_rect(Plate.tex("lamp_" + colour), _frame_rect(), false)


func _draw_glow() -> void:
	if colour != "off":
		_glow.draw_texture_rect(Plate.tex("lamp_glow_" + colour), _frame_rect(), false)
