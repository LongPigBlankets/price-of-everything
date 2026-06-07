extends Control
## A square, rounded-corner "dial" that wraps an infrastructure button. The dial
## is a ~10px-thick rounded-square ring whose fill represents transit through that
## infrastructure as a fraction of its capacity:
##   • 0–70%  of the filled arc is green
##   • 70–90% is amber
##   • 90%+   is red
##   • the unfilled remainder is a dim track
## Cables (and other uncapped infra) render a full green ring ("full_green").
## Add/unavailable slots render just the dim track.
##
## The wrapped button is added as a child, inset by the ring thickness + a gap.

const THICKNESS := 8.0
const GAP := 3.0
const CORNER := 10.0
const BUTTON_SIZE := 56.0

const TRACK_COLOR := Color(1, 1, 1, 0.12)

var _mode: String = "track"   # "fill" | "full_green" | "track"
var _pct: float = 0.0
var _content_holder: MarginContainer = null

func _init() -> void:
	var dim := BUTTON_SIZE + 2.0 * (THICKNESS + GAP)
	custom_minimum_size = Vector2(dim, dim)
	_content_holder = MarginContainer.new()
	_content_holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	var inset := int(THICKNESS + GAP)
	_content_holder.add_theme_constant_override("margin_left", inset)
	_content_holder.add_theme_constant_override("margin_right", inset)
	_content_holder.add_theme_constant_override("margin_top", inset)
	_content_holder.add_theme_constant_override("margin_bottom", inset)
	add_child(_content_holder)

func set_content(node: Control) -> void:
	for child in _content_holder.get_children():
		child.queue_free()
	_content_holder.add_child(node)

## mode: "fill" (use pct), "full_green", or "track". pct in 0..1.
func configure(mode: String, pct: float = 0.0) -> void:
	_mode = mode
	_pct = clampf(pct, 0.0, 1.0)
	queue_redraw()

func _draw() -> void:
	var rect := Rect2(Vector2(THICKNESS * 0.5, THICKNESS * 0.5), size - Vector2(THICKNESS, THICKNESS))
	var pts := _ring_points(rect, CORNER)
	var lens := _cumulative_lengths(pts)
	var total: float = lens[lens.size() - 1]
	if total <= 0.0:
		return

	match _mode:
		"full_green":
			_draw_fraction(pts, lens, total, 0.0, 1.0, DS.PALETTE.OK)
		"fill":
			# dim track underneath, then coloured bands on top
			_draw_fraction(pts, lens, total, 0.0, 1.0, TRACK_COLOR)
			if _pct > 0.0:
				_draw_fraction(pts, lens, total, 0.0, minf(_pct, 0.7), DS.PALETTE.OK)
			if _pct > 0.7:
				_draw_fraction(pts, lens, total, 0.7, minf(_pct, 0.9), DS.PALETTE.WARN)
			if _pct > 0.9:
				_draw_fraction(pts, lens, total, 0.9, _pct, DS.PALETTE.DANGER)
		_:  # "track"
			_draw_fraction(pts, lens, total, 0.0, 1.0, TRACK_COLOR)

# --- Geometry ----------------------------------------------------------------
func _ring_points(rect: Rect2, rad: float) -> PackedVector2Array:
	var l := rect.position.x
	var t := rect.position.y
	var r := rect.end.x
	var b := rect.end.y
	rad = minf(rad, minf(rect.size.x, rect.size.y) * 0.5)
	var cx := (l + r) * 0.5
	var pts := PackedVector2Array()
	pts.append(Vector2(cx, t))               # start: top-centre
	pts.append(Vector2(r - rad, t))          # top edge → top-right corner
	_arc(pts, Vector2(r - rad, t + rad), rad, -PI * 0.5, 0.0)
	pts.append(Vector2(r, b - rad))          # right edge
	_arc(pts, Vector2(r - rad, b - rad), rad, 0.0, PI * 0.5)
	pts.append(Vector2(l + rad, b))          # bottom edge
	_arc(pts, Vector2(l + rad, b - rad), rad, PI * 0.5, PI)
	pts.append(Vector2(l, t + rad))          # left edge
	_arc(pts, Vector2(l + rad, t + rad), rad, PI, PI * 1.5)
	pts.append(Vector2(cx, t))               # top edge → back to start
	return pts

func _arc(pts: PackedVector2Array, center: Vector2, rad: float, a0: float, a1: float) -> void:
	var steps := 5
	for i in range(1, steps + 1):
		var a: float = a0 + (a1 - a0) * (float(i) / float(steps))
		pts.append(center + Vector2(cos(a), sin(a)) * rad)

func _cumulative_lengths(pts: PackedVector2Array) -> PackedFloat32Array:
	var lens := PackedFloat32Array()
	lens.append(0.0)
	var acc := 0.0
	for i in range(1, pts.size()):
		acc += pts[i - 1].distance_to(pts[i])
		lens.append(acc)
	return lens

func _draw_fraction(pts: PackedVector2Array, lens: PackedFloat32Array, total: float, from_f: float, to_f: float, color: Color) -> void:
	var from_len := from_f * total
	var to_len := to_f * total
	if to_len - from_len <= 0.01:
		return
	var out := PackedVector2Array()
	for i in range(pts.size()):
		var seg_start := lens[i]
		if i == 0:
			if seg_start >= from_len:
				out.append(pts[i])
			continue
		var prev := lens[i - 1]
		# Entry interpolation
		if prev < from_len and seg_start >= from_len:
			out.append(_lerp_on(pts, lens, from_len, i))
		if seg_start > from_len and seg_start < to_len:
			out.append(pts[i])
		# Exit interpolation
		if prev < to_len and seg_start >= to_len:
			out.append(_lerp_on(pts, lens, to_len, i))
			break
	if out.size() >= 2:
		draw_polyline(out, color, THICKNESS, true)

func _lerp_on(pts: PackedVector2Array, lens: PackedFloat32Array, target_len: float, i: int) -> Vector2:
	var prev := lens[i - 1]
	var seg := lens[i] - prev
	var f: float = 0.0 if seg <= 0.0 else (target_len - prev) / seg
	return pts[i - 1].lerp(pts[i], clampf(f, 0.0, 1.0))
