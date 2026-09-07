extends Range
## Brushed metal, the way the panels do it (owner 2026-08-24): a solid body under a
## top-left light, a fine horizontal grain, a machined rim and a bevel just inside the
## top edge. Square ends with a small corner radius -- the old pill's h/2 radius put a
## circle on both ends of every bar.
const RAD := 4.0
var frac: float:
	get: return clampf((value - min_value) / maxf(0.0001, max_value - min_value), 0.0, 1.0)
	set(v): value = lerpf(min_value, max_value, clampf(v, 0.0, 1.0))
var rank: int = 1
var col: Color = Color("#6FA7C1"):
	set(v): col = v; queue_redraw()
var show_percentage: bool = false

func _init() -> void:
	step = 0.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	value_changed.connect(func(_v: float) -> void: queue_redraw())
	changed.connect(queue_redraw)
func _draw() -> void:
	var w := size.x
	var h := size.y
	_round_rect( Rect2(Vector2.ZERO, Vector2(w, h)), RAD, Color("#08131F"))
	draw_polyline(_ring(Rect2(Vector2(0.5, 0.5), Vector2(w - 1.0, h - 1.0))),
		Color(1, 1, 1, 0.06), 1.0, true)
	var bw := clampf(frac * w, 0.0, w)
	if bw <= 0.0 or h < 2.0:
		return
	if bw < 5.0:
		draw_rect(Rect2(0, 0, bw, h), col)
		return
	var body: Color = Color("#C9A75C") if rank == 0 else col
	_round_rect( Rect2(Vector2.ZERO, Vector2(bw, h)), RAD, body.darkened(0.32))
	# Light from the top-left, shade to the bottom-right -- on a 4-vertex quad, never a
	# per-vertex ramp around the rounded outline (that fans into artifacts in GL compat).
	var q := PackedVector2Array([Vector2(1.5, 1.5), Vector2(bw - 1.5, 1.5),
		Vector2(bw - 1.5, h - 1.5), Vector2(1.5, h - 1.5)])
	var lt := body.lightened(0.34)
	draw_polygon(q, PackedColorArray([Color(lt, 0.95), Color(lt, 0.45),
		Color(lt, 0.05), Color(lt, 0.45)]))
	draw_polygon(q, PackedColorArray([Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.10),
		Color(0, 0, 0, 0.34), Color(0, 0, 0, 0.10)]))
	# Brushed grain: fine horizontal streaks at a deterministic alpha.
	var y := 3.0
	var i := 0
	while y < h - 2.0:
		draw_line(Vector2(2.5, y), Vector2(bw - 2.5, y),
			Color(1, 1, 1, 0.025 + 0.022 * absf(sin(float(i) * 12.9898))), 1.0)
		y += 3.0
		i += 1
	# Machined rim, and the bevel just inside the top edge.
	draw_polyline(_ring(Rect2(Vector2(0.75, 0.75), Vector2(bw - 1.5, h - 1.5))),
		Color(body.lightened(0.55), 0.75), 1.4, true)
	draw_line(Vector2(RAD + 1.0, 2.2), Vector2(bw - RAD - 1.0, 2.2),
		Color(1, 1, 1, 0.28), 1.2, true)

func _ring(r: Rect2) -> PackedVector2Array:
	var rad: float = minf(RAD, minf(r.size.x, r.size.y) * 0.5)
	var pts := PackedVector2Array()
	var centres: Array[Vector2] = [
		Vector2(r.position.x + rad, r.position.y + rad),
		Vector2(r.end.x - rad, r.position.y + rad),
		Vector2(r.end.x - rad, r.end.y - rad),
		Vector2(r.position.x + rad, r.end.y - rad)]
	var starts: Array[float] = [PI, PI * 1.5, 0.0, PI * 0.5]
	for c in 4:
		for j in 5:
			var a: float = starts[c] + (PI * 0.5) * float(j) / 4.0
			pts.append(centres[c] + Vector2(cos(a), sin(a)) * rad)
	pts.append(pts[0])
	return pts

func _round_rect(rect: Rect2, radius: float, color: Color) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(int(minf(radius, minf(rect.size.x, rect.size.y) * 0.5)))
	draw_style_box(style, rect)
