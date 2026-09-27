extends Control
## One window of the turn briefing's annunciator (docs/briefing-ds2-plan.md §5): dark glass in the LED screens'
## gunmetal bezel (brief_window_<tone>.png, a 9-slice), lit amber or red from behind with its legend and count in
## navy black when its alert is live, green for information, dark with its legend in white when clear. A window
## the player picked is latched: a light ring round it and a notch under it pointing at the readout below.
## Presentation only: TurnBriefing.alert_windows() says what each window shows.

signal pressed(kind: String)

const Parts := preload("res://scripts/briefing_ds2/parts.gd")
const Plate := preload("res://scripts/bdp_v3_plate.gd")

const HEIGHT := 46.0
## Legends at 15 px, two lines when one will not fit; the count at 20 px at the window's right.
const LEGEND_PX := 15
const COUNT_PX := 20
const LIT_INK := Color("#1e0f02")
const DARK_INK := Color("#E8EEF7")
const RING := Color(0.91, 0.93, 0.97, 0.95)
const TONE_LAYER := {"bad": "brief_window_red", "warn": "brief_window_amber", "ok": "brief_window_green"}

var kind := ""
var legend := ""
var tone := "":
	set(v):
		tone = v
		queue_redraw()
var count := 0
var latched := false:
	set(v):
		latched = v
		queue_redraw()


func _init(window_kind: String = "", window_legend: String = "") -> void:
	kind = window_kind
	legend = window_legend
	name = "Window_%s" % window_kind
	custom_minimum_size = Vector2(0, HEIGHT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_filter = Control.MOUSE_FILTER_STOP


## Lit windows can be picked; a dark one says only that nothing is wrong.
func is_lit() -> bool:
	return tone != ""


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and is_lit():
		accept_event()
		pressed.emit(kind)


func _draw() -> void:
	var layer: String = TONE_LAYER.get(tone, "brief_window_dark")
	Parts.draw_nine(self, Parts.tex(layer), Rect2(Vector2.ZERO, size), Parts.WINDOW_MARGIN,
		Parts.WINDOW_RIM + Parts.WINDOW_RADIUS + 2.0)
	var ink := LIT_INK if is_lit() else DARK_INK
	var font: Font = Plate.FONT_BOLD
	var inset := Parts.WINDOW_RIM / Parts.LAYOUT + 4.0
	var room := Rect2(inset, 0.0, size.x - 2.0 * inset, size.y)
	var count_text := str(count) if is_lit() and count > 0 else ""
	if count_text != "":
		var cw := font.get_string_size(count_text, HORIZONTAL_ALIGNMENT_LEFT, -1, COUNT_PX).x
		var base := size.y * 0.5 + (font.get_ascent(COUNT_PX) - font.get_descent(COUNT_PX)) * 0.5
		draw_string(font, Vector2(room.end.x - cw - 2.0, base), count_text, HORIZONTAL_ALIGNMENT_LEFT, -1, COUNT_PX, ink)
		room.size.x -= cw + 6.0
	var lines := _legend_lines(font, room.size.x)
	var px := LEGEND_PX
	var line_h := font.get_ascent(px) - font.get_descent(px) + 1.0
	var first := size.y * 0.5 - line_h * (lines.size() - 1) * 0.5 + (font.get_ascent(px) - font.get_descent(px)) * 0.5
	for i in lines.size():
		var w := font.get_string_size(lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		draw_string(font, Vector2(room.position.x + (room.size.x - w) * 0.5, first + i * line_h), lines[i],
			HORIZONTAL_ALIGNMENT_LEFT, -1, px, ink)
	if latched:
		var ring := Rect2(Vector2.ZERO, size).grow(3.0)
		var sb := StyleBoxFlat.new()
		sb.draw_center = false
		sb.border_color = RING
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(6)
		draw_style_box(sb, ring)
		var mid := size.x * 0.5
		draw_colored_polygon(PackedVector2Array([Vector2(mid - 6, size.y + 4), Vector2(mid + 6, size.y + 4), Vector2(mid, size.y + 10)]), RING)


## The legend on one line, or its words split over two when one line is too wide.
func _legend_lines(font: Font, width: float) -> PackedStringArray:
	if font.get_string_size(legend, HORIZONTAL_ALIGNMENT_LEFT, -1, LEGEND_PX).x <= width or not legend.contains(" "):
		return PackedStringArray([legend])
	var words := legend.split(" ")
	var half := ceili(words.size() / 2.0)
	return PackedStringArray([" ".join(words.slice(0, half)), " ".join(words.slice(half))])
