extends Control
## Building Detail v3: one of Labour and Wages' factory doors, for one kind of worker. A painted steel door
## in its jamb with a small wired-glass window near the top, lit warm from inside when any of these
## workers are employed, and a brushed steel kick plate at its foot with the headcount engraved on it
## (res://assets/ui/bdp_v3/labour_door.png and labour_door_lit.png, rendered by
## tools/button_mockup/cluster.html?export). The door keeps its proportions, fitted to this control.

const DARK: Texture2D = preload("res://assets/ui/bdp_v3/labour_door.png")
const LIT: Texture2D = preload("res://assets/ui/bdp_v3/labour_door_lit.png")
const Plate := preload("res://scripts/bdp_v3_plate.gd")
const CAPTURE_SCALE := 1.875
## From layout.json (labour_door), in layout pixels: the render's frame and the kick plate in it.
const FRAME := Vector2(200.0, 300.0)
const KICK_PLATE := Rect2(30.0, 216.64, 140.0, 63.36)
const HEIGHT := 150.0
const INK := Color("#0b2340")
const CUT_LIGHT := Color(1, 1, 1, 0.55)
const NUMBER_SIZE := 24

var count := 0:
	set(v):
		count = v
		queue_redraw()


func _init() -> void:
	name = "BdpV3LabourDoor"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(0.0, HEIGHT)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


## The door's frame drawn in this control: as tall as the control, or narrower to fit its width.
func frame_rect() -> Rect2:
	var s := minf(size.y / FRAME.y, size.x / FRAME.x)
	var drawn := FRAME * s
	return Rect2((size - drawn) * 0.5, drawn)


func _draw() -> void:
	var r := frame_rect()
	draw_texture_rect(LIT if count > 0 else DARK, r, false)
	# The headcount engraved on the kick plate: the cut's far edge catches the light below-right.
	var s := r.size.x / FRAME.x
	var plate := Rect2(r.position + KICK_PLATE.position * s, KICK_PLATE.size * s)
	var font: Font = Plate.FONT_BOLD
	var text := _grouped(count)
	var fs := Plate._fit(font, text, NUMBER_SIZE, plate.size.x - 12.0)
	var baseline := plate.get_center().y + (font.get_ascent(fs) - font.get_descent(fs)) * 0.5
	var at := Vector2(plate.position.x, baseline)
	draw_string(font, at + Vector2(0.8, 0.8), text, HORIZONTAL_ALIGNMENT_CENTER, plate.size.x, fs, CUT_LIGHT)
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, plate.size.x, fs, INK)


static func _grouped(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out
