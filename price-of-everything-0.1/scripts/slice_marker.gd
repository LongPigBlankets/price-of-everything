extends Node2D

@export var radius: float = 20
@export var arc_segments: int = 24
@export var colors: Array[Color] = [Color.RED]:
	set(value):
		colors = value.slice(0, 4)  # cap at 4
		if is_inside_tree():
			queue_redraw()

func set_colors(new_colors: Array[Color]) -> void:
	colors = new_colors

func _draw() -> void:
	match colors.size():
		0: return
		1: draw_circle(Vector2.ZERO, radius, colors[0])
		2:
			_draw_stripe(-radius, 0, colors[0])
			_draw_stripe(0, radius, colors[1])
		3:
			var t = radius * 2.0 / 3.0
			_draw_stripe(-radius, -radius + t, colors[0])
			_draw_stripe(-radius + t, radius - t, colors[1])
			_draw_stripe(radius - t, radius, colors[2])
		4:
			_draw_quadrant(0, colors[0])  # TL (reading order: TL, TR, BL, BR)
			_draw_quadrant(1, colors[1])  # TR
			_draw_quadrant(2, colors[2])  # BL
			_draw_quadrant(3, colors[3])  # BR

func _circle_point(alpha: float) -> Vector2:
	# alpha=0 at top, increases clockwise (Godot's +y is down)
	return Vector2(sin(alpha) * radius, -cos(alpha) * radius)

func _draw_stripe(y_top: float, y_bot: float, color: Color) -> void:
	var poly = PackedVector2Array()
	var a_tr = acos(-y_top / radius)
	var a_br = acos(-y_bot / radius)
	# Right arc: top-right down to bottom-right
	for i in range(arc_segments + 1):
		poly.append(_circle_point(lerp(a_tr, a_br, float(i) / arc_segments)))
	# Left arc: bottom-left up to top-left (TAU - a gives the mirrored angle)
	for i in range(arc_segments + 1):
		poly.append(_circle_point(lerp(TAU - a_br, TAU - a_tr, float(i) / arc_segments)))
	draw_colored_polygon(poly, color)

func _draw_quadrant(quad: int, color: Color) -> void:
	var poly = PackedVector2Array()
	poly.append(Vector2.ZERO)
	var corner: Vector2
	var a_start: float
	var a_end: float
	match quad:
		0:  # TL
			corner = Vector2(0, -radius); a_start = TAU; a_end = 3.0 * PI / 2.0
		1:  # TR
			corner = Vector2(radius, 0); a_start = PI / 2.0; a_end = 0
		2:  # BL
			corner = Vector2(-radius, 0); a_start = 3.0 * PI / 2.0; a_end = PI
		3:  # BR
			corner = Vector2(0, radius); a_start = PI; a_end = PI / 2.0
	poly.append(corner)
	for i in range(arc_segments + 1):
		poly.append(_circle_point(lerp(a_start, a_end, float(i) / arc_segments)))
	draw_colored_polygon(poly, color)
