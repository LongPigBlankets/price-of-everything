extends Control
## The tutorial card's face: dark metal with only a faint brushed grain, inside a polished silver frame with
## a bevel catching the light from the top left. Drawn, not a texture, so it carries none of the kit plates'
## scratches and rust. Sits behind the card's content and fills it.

const FRAME := 6.0
const CORNER := 12
const SILVER := Color("#b4bbc3")
const SILVER_LIT := Color("#eef1f4")
const SILVER_SHADE := Color("#68707a")
const EDGE := Color("#1d2127")
const FACE_TOP := Color("#262a31")
const FACE_FOOT := Color("#16191d")
## The brushed grain: one faint line every GRAIN_STEP px.
const GRAIN_STEP := 3.0
const GRAIN_ALPHA := 0.035


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	# The silver frame, its bevel lit on the top and left, shaded on the bottom and right.
	draw_style_box(_box(SILVER, CORNER, EDGE, 1), r)
	var bevel := StyleBoxFlat.new()
	bevel.draw_center = false
	bevel.set_corner_radius_all(CORNER)
	bevel.border_width_top = 2
	bevel.border_width_left = 2
	bevel.border_color = Color(SILVER_LIT, 0.85)
	draw_style_box(bevel, r.grow(-1.0))
	var shade := StyleBoxFlat.new()
	shade.draw_center = false
	shade.set_corner_radius_all(CORNER)
	shade.border_width_bottom = 2
	shade.border_width_right = 2
	shade.border_color = Color(SILVER_SHADE, 0.9)
	draw_style_box(shade, r.grow(-1.0))
	# The face: dark metal, a shade lighter at the top, set into the frame.
	var face := r.grow(-FRAME)
	draw_style_box(_box(FACE_FOOT, CORNER - 4, EDGE, 1), face)
	# A smooth fade from top to foot, a line a pixel, each line shortened at the corners to keep their round.
	var radius := float(CORNER - 4)
	var inner := face.grow(-1.0)
	var row := inner.position.y
	while row < inner.end.y:
		var t := (row - inner.position.y) / maxf(inner.size.y, 1.0)
		var from_edge := minf(row - inner.position.y, inner.end.y - row)
		var inset := 0.0
		if from_edge < radius:
			inset = radius - sqrt(maxf(radius * radius - (radius - from_edge) * (radius - from_edge), 0.0))
		draw_line(Vector2(inner.position.x + inset, row + 0.5), Vector2(inner.end.x - inset, row + 0.5),
			FACE_TOP.lerp(FACE_FOOT, smoothstep(0.0, 1.0, t)), 1.0)
		row += 1.0
	# The grain: faint and even, no scuffs.
	var y := face.position.y + 4.0
	var i := 0
	while y < face.end.y - 4.0:
		var a := GRAIN_ALPHA * (0.6 + 0.4 * float((i * 7) % 5) / 4.0)
		draw_line(Vector2(face.position.x + 6.0, y), Vector2(face.end.x - 6.0, y), Color(1, 1, 1, a), 1.0)
		y += GRAIN_STEP
		i += 1
	# The face's own edge: a dark cut on the top and left where the frame overhangs it.
	draw_line(face.position + Vector2(CORNER - 4, 1), Vector2(face.end.x - CORNER + 4, face.position.y + 1), Color(0, 0, 0, 0.5), 1.0)
	draw_line(face.position + Vector2(1, CORNER - 4), Vector2(face.position.x + 1, face.end.y - CORNER + 4), Color(0, 0, 0, 0.5), 1.0)


static func _box(fill: Color, corner: int, edge: Color, edge_w: int) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = fill
	b.set_corner_radius_all(corner)
	b.border_color = edge
	b.set_border_width_all(edge_w)
	b.anti_aliasing = true
	return b
