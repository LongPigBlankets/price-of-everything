extends Control
## Building Detail v3: the diagnostics' readout. A dark glass screen in a gunmetal bezel (the LED
## screens' render: res://assets/ui/bdp_v3/mini_screen.png and mini_screen_glass.png) at the foot of the
## visual view. It names the check under the pointer and says what it found, with the check's lamp lit
## beside it; the panel shows the worst check here when the pointer is on none.

const Nine := preload("res://scripts/bdp_v3_nine.gd")
const Lamp := preload("res://scripts/bdp_v3_lamp.gd")
const Plate := preload("res://scripts/bdp_v3_plate.gd")
const SCREEN: Texture2D = preload("res://assets/ui/bdp_v3/mini_screen.png")
const GLASS: Texture2D = preload("res://assets/ui/bdp_v3/mini_screen_glass.png")
const CAPTURE_SCALE := 1.875
## From layout.json (mini_screen), in layout pixels: the screen's shadow room, bezel and pane radius.
const MARGIN := 8.0
const RIM := 7.0
const RADIUS := 5.0
## Room for the name and two lines of detail.
const HEIGHT := 72.0
const DETAIL_FONT_SIZE := 14
## The text's inset from the bezel's inside edge.
const PAD := Vector2(8.0, 3.0)
const LAMP_SCALE := 0.55

var _lamp: Control
var _name: Label
var _detail: Label
var _glass: Control


func _init() -> void:
	name = "BdpV3Readout"
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	# PASS: over the icons it floats above, it keeps the pointer off them, and the wheel still scrolls.
	mouse_filter = Control.MOUSE_FILTER_PASS
	custom_minimum_size = Vector2(0.0, HEIGHT)
	var inset := RIM / CAPTURE_SCALE
	var row := HBoxContainer.new()
	row.name = "ReadoutRow"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = inset + PAD.x
	row.offset_right = -(inset + PAD.x)
	row.offset_top = inset + PAD.y
	row.offset_bottom = -(inset + PAD.y)
	add_child(row)
	_lamp = Lamp.new()
	_lamp.lamp_scale = LAMP_SCALE
	row.add_child(_lamp)
	var lines := VBoxContainer.new()
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lines.alignment = BoxContainer.ALIGNMENT_CENTER
	lines.add_theme_constant_override("separation", -1)
	row.add_child(lines)
	_name = Label.new()
	_name.name = "ReadoutName"
	_name.add_theme_font_override("font", Plate.FONT_SEMI)
	_name.add_theme_font_size_override("font_size", 15)
	_name.add_theme_color_override("font_color", DS.PALETTE["TEXT"])
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name.clip_text = true
	lines.add_child(_name)
	_detail = Label.new()
	_detail.name = "ReadoutDetail"
	_detail.theme_type_variation = "Caption"
	_detail.add_theme_color_override("font_color", DS.PALETTE["TEXT"])
	_detail.add_theme_font_size_override("font_size", DETAIL_FONT_SIZE)
	_detail.add_theme_constant_override("line_spacing", 0)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Two lines at most, and no clip_text: with autowrap, clip_text leaves the label asking for no height.
	_detail.max_lines_visible = 2
	_detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	lines.add_child(_detail)
	_glass = Control.new()
	_glass.name = "Glass"
	_glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glass.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_glass.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_glass.draw.connect(func() -> void: Nine.paint(_glass, GLASS, _screen_rect(), _corner()))
	add_child(_glass)


## Shows one check: its stage and name on the first line ("Outputs: Reach"), what it found below.
func show_check(stage: String, check_name: String, detail: String, tone: String) -> void:
	_name.text = check_name if stage == "" else "%s: %s" % [stage, check_name]
	_detail.text = detail
	_lamp.set_tone(tone)


func shown_name() -> String:
	return _name.text


func shown_detail() -> String:
	return _detail.text


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
		_glass.queue_redraw()


func _screen_rect() -> Rect2:
	return Rect2(Vector2.ZERO, size).grow(MARGIN / CAPTURE_SCALE)


func _corner() -> float:
	return (MARGIN + RIM + RADIUS + 2.0) * 2.0 / CAPTURE_SCALE


func _draw() -> void:
	Nine.paint(self, SCREEN, _screen_rect(), _corner())
