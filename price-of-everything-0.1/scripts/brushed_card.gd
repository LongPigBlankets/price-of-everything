extends PanelContainer
## The brushed navy card the tile view uses for a building: a rounded navy plate with a
## top-left light, a fine horizontal grain, a machined silver rim and a hover lift.
##
## Extracted from tile_info_panel_v2, where it began as an inner class, so the transport
## panel can wear the SAME card rather than an imitation of it. Two implementations of one
## look drift apart the first time either is touched; one cannot.

const NAVY_TL := Color(0.05, 0.205, 0.365)
const NAVY_BR := Color(0.0, 0.075, 0.155)
const SILVER_LT := Color("#b3bcc6")
const SILVER_DK := Color("#5b636e")
const SILVER_HOVER := Color("#dbe2ea")
var radius := 9.0
var hovered := false:
	set(v):
		hovered = v
		queue_redraw()
func _init(margin_h: int = 12, margin_v: int = 8, r: float = 9.0) -> void:
	radius = r
	var sb := StyleBoxEmpty.new()
	sb.content_margin_left = margin_h
	sb.content_margin_right = margin_h
	sb.content_margin_top = margin_v
	sb.content_margin_bottom = margin_v
	add_theme_stylebox_override("panel", sb)
	resized.connect(queue_redraw)
static func _rounded_points(r: Rect2, rad: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var centres: Array[Vector2] = [
		Vector2(r.position.x + rad, r.position.y + rad),
		Vector2(r.end.x - rad, r.position.y + rad),
		Vector2(r.end.x - rad, r.end.y - rad),
		Vector2(r.position.x + rad, r.end.y - rad),
	]
	var starts: Array[float] = [PI, PI * 1.5, 0.0, PI * 0.5]
	for c in 4:
		for i in 7:
			var a: float = starts[c] + (PI * 0.5) * float(i) / 6.0
			pts.append(centres[c] + Vector2(cos(a), sin(a)) * rad)
	return pts
func _draw() -> void:
	draw_on(self, Rect2(Vector2.ZERO, size), radius, hovered)

static func draw_on(canvas: CanvasItem, area: Rect2, radius: float = 9.0, hovered: bool = false) -> void:
	if area.size.x < 4.0 or area.size.y < 4.0:
		return
	var r := area.grow(-1.0)
	var pts := _rounded_points(r, radius)
	var diag := maxf(1.0, area.size.x + area.size.y)
	# Navy plate: solid mid fill, then 4-vertex gradient quads for the
	# top-left light and bottom-right shade. (Per-vertex colours on the
	# 28-point rounded polygon interpolate as fan artifacts — the left
	# edge rendered nearly black — so gradients go on simple quads.)
	var mid := NAVY_TL.lerp(NAVY_BR, 0.45)
	canvas.draw_colored_polygon(pts, mid.lightened(0.08) if hovered else mid)
	var q := PackedVector2Array([
		r.position + Vector2(1.5, 1.5), Vector2(r.end.x - 1.5, r.position.y + 1.5),
		r.end - Vector2(1.5, 1.5), Vector2(r.position.x + 1.5, r.end.y - 1.5)])
	var lt := NAVY_TL.lightened(0.16)
	canvas.draw_polygon(q, PackedColorArray([
		Color(lt, 0.9), Color(lt, 0.15), Color(lt, 0.0), Color(lt, 0.35)]))
	canvas.draw_polygon(q, PackedColorArray([
		Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.12), Color(0, 0, 0, 0.30), Color(0, 0, 0, 0.08)]))
	# Brushed streaks — fine horizontal grain, deterministic alpha pattern.
	var y := r.position.y + 4.0
	var i := 0
	while y < r.end.y - 3.0:
		var a := 0.022 + 0.02 * absf(sin(float(i) * 12.9898))
		canvas.draw_line(Vector2(r.position.x + 3.0, y), Vector2(r.end.x - 3.0, y), Color(1, 1, 1, a), 1.0)
		y += 3.0
		i += 1
	# Machined silver rim (closed), lighter where the light lands.
	var rim := PackedColorArray()
	for p in pts:
		var t := clampf((p.x - area.position.x + p.y - area.position.y) / diag, 0.0, 1.0)
		rim.append((SILVER_HOVER if hovered else SILVER_LT).lerp(SILVER_DK, t))
	var closed := pts.duplicate()
	closed.append(pts[0])
	rim.append(rim[0])
	canvas.draw_polyline_colors(closed, rim, 1.5, true)
	# Bevel highlight just inside the top edge.
	canvas.draw_line(Vector2(r.position.x + radius, r.position.y + 2.2),
		Vector2(r.end.x - radius, r.position.y + 2.2), Color(1, 1, 1, 0.10), 1.0)
