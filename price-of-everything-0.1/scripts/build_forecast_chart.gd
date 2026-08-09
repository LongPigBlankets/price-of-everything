extends Control
## Draws BuildForecast.project() as a per-turn cash trajectory: grey while the site is
## under construction, red while the building costs more than it earns, green once it
## pays. Each segment carries a translucent fill down to the zero axis, so the dip a
## player is about to buy has visible area, not just a line.
##
## See docs/early-game-onboarding-spec.md §5.1.

const LINE_W := 5.0            # owner-specified stroke weight
const FILL_ALPHA := 0.22
const PAD_L := 44.0            # room for the £ axis labels
const PAD_R := 10.0
const PAD_T := 12.0
const PAD_B := 20.0            # room for the turn labels

var _data: Dictionary = {}
var _font: Font = null


func _init() -> void:
	custom_minimum_size = Vector2(0, 132)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_forecast(data: Dictionary) -> void:
	_data = data
	queue_redraw()


func _draw() -> void:
	var points: Array = _data.get("points", [])
	if points.size() < 2:
		return
	if _font == null:
		_font = get_theme_default_font()

	var plot := Rect2(PAD_L, PAD_T, size.x - PAD_L - PAD_R, size.y - PAD_T - PAD_B)
	if plot.size.x <= 0.0 or plot.size.y <= 0.0:
		return

	# Symmetric-ish scale that always includes zero, so the axis means what it looks like.
	var lo: float = 0.0
	var hi: float = 0.0
	for p in points:
		lo = minf(lo, float(p))
		hi = maxf(hi, float(p))
	if is_equal_approx(lo, hi):
		hi = lo + 1.0
	var span: float = hi - lo
	lo -= span * 0.12
	hi += span * 0.12

	var zero_y: float = _value_to_y(0.0, lo, hi, plot)
	var muted: Color = DS.PALETTE.get("TEXT_MUTED", Color(0.75, 0.75, 0.72))
	var soft: Color = DS.PALETTE.get("BORDER_SOFT", Color(0.55, 0.53, 0.48))

	# Zero axis — the line the whole chart is read against.
	draw_line(Vector2(plot.position.x, zero_y), Vector2(plot.end.x, zero_y), soft, 1.0)
	draw_string(_font, Vector2(4, zero_y + 4), "£0",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, muted)

	var build_turns: int = int(_data.get("build_turns", 0))
	var step: float = plot.size.x / float(points.size() - 1)

	# Construction band: a quiet plate behind the turns where nothing is earned or owed.
	if build_turns > 0:
		var band_w: float = step * float(mini(build_turns, points.size() - 1))
		draw_rect(Rect2(plot.position.x, plot.position.y, band_w, plot.size.y),
			Color(soft.r, soft.g, soft.b, 0.10), true)
		_draw_hammers(plot, step, build_turns, muted)

	# One coloured segment per turn-to-turn step, each with its own fill to the axis. A step
	# that crosses zero is split at the crossing, so the losing half draws red and the earning
	# half green — and so the fill never becomes a self-intersecting bow-tie.
	for i in range(points.size() - 1):
		var va := float(points[i])
		var vb := float(points[i + 1])
		var a := Vector2(plot.position.x + step * float(i), _value_to_y(va, lo, hi, plot))
		var b := Vector2(plot.position.x + step * float(i + 1), _value_to_y(vb, lo, hi, plot))
		if i < build_turns:
			_draw_span(a, b, zero_y, DS.PALETTE.get("TEXT_MUTED", Color(0.72, 0.70, 0.66)))
			continue
		if (va < 0.0) != (vb < 0.0) and not is_equal_approx(va, vb):
			var t: float = absf(va) / maxf(0.0001, absf(va) + absf(vb))
			var crossing := Vector2(a.x + (b.x - a.x) * t, zero_y)
			_draw_span(a, crossing, zero_y, _sign_colour(va))
			_draw_span(crossing, b, zero_y, _sign_colour(vb))
		else:
			_draw_span(a, b, zero_y, _sign_colour(va if not is_zero_approx(va) else vb))

	# The turn the building starts paying for itself.
	var first_profit: int = int(_data.get("first_profit", -1))
	if first_profit > 0 and first_profit < points.size():
		var x: float = plot.position.x + step * float(first_profit)
		draw_dashed_line(Vector2(x, plot.position.y), Vector2(x, plot.end.y),
			DS.PALETTE.get("OK", Color(0.35, 0.72, 0.45)), 1.0, 4.0)

	# Turn ruler: first, the turn it comes online, and last.
	_draw_turn_label(plot, step, 0, muted)
	if build_turns > 0 and build_turns < points.size():
		_draw_turn_label(plot, step, build_turns, muted)
	_draw_turn_label(plot, step, points.size() - 1, muted)

	# Peak and trough, so the reader gets the magnitude without a full axis.
	draw_string(_font, Vector2(2, _value_to_y(hi, lo, hi, plot) + 10),
		_money(hi), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, muted)
	draw_string(_font, Vector2(2, _value_to_y(lo, lo, hi, plot) - 2),
		_money(lo), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, muted)


func _sign_colour(value: float) -> Color:
	if value < 0.0:
		return DS.PALETTE.get("DANGER", Color(0.80, 0.32, 0.28))
	return DS.PALETTE.get("OK", Color(0.35, 0.72, 0.45))


## One stroke plus its fill down to the axis. Foot points are only added when the endpoint
## is off the axis, so a span that starts or ends on zero stays a clean triangle instead of a
## polygon with a repeated vertex (which fails triangulation).
func _draw_span(a: Vector2, b: Vector2, zero_y: float, colour: Color) -> void:
	var poly := PackedVector2Array([a, b])
	if absf(b.y - zero_y) > 0.5:
		poly.append(Vector2(b.x, zero_y))
	if absf(a.y - zero_y) > 0.5:
		poly.append(Vector2(a.x, zero_y))
	if poly.size() >= 3:
		draw_colored_polygon(poly, Color(colour.r, colour.g, colour.b, FILL_ALPHA))
	draw_line(a, b, colour, LINE_W)


func _draw_hammers(plot: Rect2, step: float, build_turns: int, colour: Color) -> void:
	# A small hammer per construction turn: haft and head, drawn rather than textured so it
	# scales with the plate and needs no asset.
	for i in range(mini(build_turns, 6)):
		var cx: float = plot.position.x + step * (float(i) + 0.5)
		var cy: float = plot.position.y + 12.0
		draw_line(Vector2(cx - 3, cy + 6), Vector2(cx + 2, cy - 3), colour, 1.5)
		draw_line(Vector2(cx - 1, cy - 5), Vector2(cx + 6, cy - 1), colour, 3.0)


func _draw_turn_label(plot: Rect2, step: float, index: int, colour: Color) -> void:
	var x: float = plot.position.x + step * float(index)
	draw_string(_font, Vector2(x - 8, plot.end.y + 14), "t%d" % (index + 1),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, colour)


func _value_to_y(value: float, lo: float, hi: float, plot: Rect2) -> float:
	var t: float = (value - lo) / maxf(0.0001, hi - lo)
	return plot.end.y - t * plot.size.y


func _money(v: float) -> String:
	return "£%s%d" % ["-" if v < 0.0 else "", int(round(absf(v)))]
