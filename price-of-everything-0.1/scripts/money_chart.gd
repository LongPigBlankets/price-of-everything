extends Control
# Stacked line/area chart of the last N turns of money, split by colour-coded series.
# Toggles between "revenue" and "costs". Axes are kept thin and skinny to match the
# tile-view panel (tile_size_chart.gd uses the same light-blue BORDER_COLOR treatment).

const AXIS_COLOR := Color(0.7, 0.85, 1.0, 0.65)
const GRID_COLOR := Color(0.7, 0.85, 1.0, 0.14)
const LABEL_COLOR := Color(0.7, 0.85, 1.0, 0.85)
const TOP_LINE_COLOR := Color(1.0, 1.0, 1.0, 0.35)
const NAVY := Color(0.02, 0.06, 0.18)

const MARGIN_LEFT := 58.0
const MARGIN_TOP := 14.0
const MARGIN_BOTTOM := 26.0
const MARGIN_RIGHT := 12.0
const LEGEND_WIDTH := 150.0
const LEGEND_SWATCH := 14.0
const LEGEND_ROW_H := 22.0
const AXIS_FONT_SIZE := 12

# Series are stacked bottom -> top in array order. `key` indexes into the per-turn
# breakdown dict the money panel records; `hatch` (optional) overlays a navy crosshatch.
const REVENUE_SERIES := [
	{"key": "finished",     "label": "Finished goods",     "color": Color(0.60, 0.90, 0.60)},   # light green
	{"key": "intermediate", "label": "Intermediate goods", "color": Color(0.10, 0.45, 0.16)},   # dark green
	{"key": "raw",          "label": "Raw goods",          "color": Color(0.55, 0.95, 0.78)},   # mint green
	{"key": "construction", "label": "Construction goods", "color": Color(0.95, 0.88, 0.25)},   # yellow
	{"key": "power",        "label": "Power sold",         "color": Color(0.55, 0.80, 0.95)},   # light blue
]
const COST_SERIES := [
	{"key": "raw",          "label": "Raw goods bought",   "color": Color(0.55, 0.08, 0.08)},   # dark red
	{"key": "intermediate", "label": "Intermediate bought","color": Color(0.95, 0.45, 0.45)},   # light red
	{"key": "construction", "label": "Construction bought","color": Color(0.50, 0.33, 0.15)},   # brown
	{"key": "power",        "label": "Power bought",       "color": Color(0.95, 0.60, 0.15)},   # orange
	{"key": "maintenance",  "label": "Maintenance",        "color": Color(0.60, 0.30, 0.72)},   # purple
	{"key": "labour",       "label": "Labour",             "color": Color(0.96, 0.55, 0.78)},   # pink
	{"key": "taxes",        "label": "Taxes",              "color": Color(0.78, 0.78, 0.78)},   # light grey
	{"key": "dividends",    "label": "Dividends",          "color": Color(0.36, 0.36, 0.38)},   # dark grey
	{"key": "interest",     "label": "Interest",           "color": Color(0.92, 0.85, 0.20), "hatch": NAVY},  # yellow hatched navy
]

var _history: Array = []   # Array of { "revenue": {...}, "costs": {...}, "turn": int }
var _mode: String = "revenue"

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0, 320)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

func set_data(history: Array, mode: String) -> void:
	_history = history
	_mode = mode
	queue_redraw()

func _series_specs() -> Array:
	return COST_SERIES if _mode == "costs" else REVENUE_SERIES

func _draw() -> void:
	var specs := _series_specs()
	var plot := Rect2(
		Vector2(MARGIN_LEFT, MARGIN_TOP),
		Vector2(
			maxf(1.0, size.x - MARGIN_LEFT - MARGIN_RIGHT - LEGEND_WIDTH),
			maxf(1.0, size.y - MARGIN_TOP - MARGIN_BOTTOM)
		)
	)
	var n := _history.size()

	# Per-turn totals to scale the Y axis.
	var totals: Array = []
	var max_total := 0.0
	for entry in _history:
		var sub: Dictionary = entry.get(_mode, {})
		var t := 0.0
		for s in specs:
			t += float(sub.get(s.key, 0.0))
		totals.append(t)
		max_total = maxf(max_total, t)
	# Hug the tallest stack exactly — no headroom above the highest peak.
	var y_max: float = max_total if max_total > 0.0 else 1.0

	_draw_grid_and_axes(plot, y_max)
	_draw_legend(specs)

	if n == 0:
		_draw_centered_note(plot, "No turns recorded yet")
		return

	# X positions for each turn sample.
	var xs: Array = []
	for i in n:
		if n == 1:
			xs.append(plot.position.x + plot.size.x * 0.5)
		else:
			xs.append(plot.position.x + plot.size.x * (float(i) / float(n - 1)))

	# Stack series bottom -> top, drawing convex per-segment quads (reliable fill).
	var cum: Array = []
	cum.resize(n)
	cum.fill(0.0)
	for s in specs:
		var tops: Array = []
		tops.resize(n)
		for i in n:
			var sub: Dictionary = _history[i].get(_mode, {})
			tops[i] = cum[i] + float(sub.get(s.key, 0.0))

		var band_poly := _band_polygon(xs, cum, tops, plot, y_max)
		_fill_band(xs, cum, tops, plot, y_max, s.color)
		if s.has("hatch"):
			_draw_hatch(band_poly, s.hatch)

		# Thin top edge so adjacent same-family colours stay legible.
		if n >= 2:
			var line_pts := PackedVector2Array()
			for i in n:
				line_pts.append(Vector2(xs[i], _value_to_y(tops[i], plot, y_max)))
			draw_polyline(line_pts, TOP_LINE_COLOR, 1.0, true)

		cum = tops

	_draw_x_labels(plot, xs)

func _fill_band(xs: Array, bottoms: Array, tops: Array, plot: Rect2, y_max: float, color: Color) -> void:
	var n := xs.size()
	if n == 1:
		var bw := 18.0
		var x: float = xs[0]
		var rect := Rect2(
			Vector2(x - bw * 0.5, _value_to_y(tops[0], plot, y_max)),
			Vector2(bw, _value_to_y(bottoms[0], plot, y_max) - _value_to_y(tops[0], plot, y_max))
		)
		if rect.size.y > 0.0:
			draw_rect(rect, color, true)
		return
	for i in range(n - 1):
		var quad := PackedVector2Array([
			Vector2(xs[i],     _value_to_y(bottoms[i], plot, y_max)),
			Vector2(xs[i + 1], _value_to_y(bottoms[i + 1], plot, y_max)),
			Vector2(xs[i + 1], _value_to_y(tops[i + 1], plot, y_max)),
			Vector2(xs[i],     _value_to_y(tops[i], plot, y_max)),
		])
		draw_colored_polygon(quad, color)

func _band_polygon(xs: Array, bottoms: Array, tops: Array, plot: Rect2, y_max: float) -> PackedVector2Array:
	var poly := PackedVector2Array()
	var n := xs.size()
	if n == 1:
		var bw := 18.0
		var x: float = xs[0]
		poly.append(Vector2(x - bw * 0.5, _value_to_y(bottoms[0], plot, y_max)))
		poly.append(Vector2(x + bw * 0.5, _value_to_y(bottoms[0], plot, y_max)))
		poly.append(Vector2(x + bw * 0.5, _value_to_y(tops[0], plot, y_max)))
		poly.append(Vector2(x - bw * 0.5, _value_to_y(tops[0], plot, y_max)))
		return poly
	for i in n:
		poly.append(Vector2(xs[i], _value_to_y(bottoms[i], plot, y_max)))
	for i in range(n - 1, -1, -1):
		poly.append(Vector2(xs[i], _value_to_y(tops[i], plot, y_max)))
	return poly

func _draw_hatch(poly: PackedVector2Array, color: Color) -> void:
	if poly.size() < 3:
		return
	var bounds := _poly_bounds(poly)
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return
	var spacing := 7.0
	var off := -bounds.size.y
	while off < bounds.size.x:
		var p1 := Vector2(bounds.position.x + off, bounds.position.y)
		var p2 := Vector2(bounds.position.x + off + bounds.size.y, bounds.position.y + bounds.size.y)
		var line := PackedVector2Array([p1, p2])
		for seg in Geometry2D.intersect_polyline_with_polygon(line, poly):
			if seg.size() >= 2:
				draw_polyline(seg, color, 1.0)
		off += spacing

func _poly_bounds(poly: PackedVector2Array) -> Rect2:
	var mn := poly[0]
	var mx := poly[0]
	for p in poly:
		mn.x = minf(mn.x, p.x)
		mn.y = minf(mn.y, p.y)
		mx.x = maxf(mx.x, p.x)
		mx.y = maxf(mx.y, p.y)
	return Rect2(mn, mx - mn)

func _value_to_y(value: float, plot: Rect2, y_max: float) -> float:
	var ratio := clampf(value / y_max, 0.0, 1.0) if y_max > 0.0 else 0.0
	return plot.end.y - plot.size.y * ratio

func _draw_grid_and_axes(plot: Rect2, y_max: float) -> void:
	var font := get_theme_default_font()
	# Horizontal gridlines + Y labels at the quarter marks (top label is the exact peak).
	for frac in [0.25, 0.5, 0.75, 1.0]:
		var v: float = y_max * float(frac)
		var y := _value_to_y(v, plot, y_max)
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), GRID_COLOR, 1.0)
		var label := _format_money(v)
		var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, AXIS_FONT_SIZE).x
		draw_string(font, Vector2(plot.position.x - tw - 6.0, y + AXIS_FONT_SIZE * 0.35),
			label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, AXIS_FONT_SIZE, LABEL_COLOR)
	# Thin axes.
	draw_line(Vector2(plot.position.x, plot.position.y), Vector2(plot.position.x, plot.end.y), AXIS_COLOR, 1.0)
	draw_line(Vector2(plot.position.x, plot.end.y), Vector2(plot.end.x, plot.end.y), AXIS_COLOR, 1.0)

func _draw_x_labels(plot: Rect2, xs: Array) -> void:
	var font := get_theme_default_font()
	for i in xs.size():
		var turn_no := int(_history[i].get("turn", i + 1))
		var label := str(turn_no)
		var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, AXIS_FONT_SIZE).x
		draw_string(font, Vector2(float(xs[i]) - tw * 0.5, plot.end.y + AXIS_FONT_SIZE + 4.0),
			label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, AXIS_FONT_SIZE, LABEL_COLOR)
	# Axis caption.
	draw_string(font, Vector2(plot.position.x, plot.end.y + AXIS_FONT_SIZE * 2.0 + 6.0),
		"Turn", HORIZONTAL_ALIGNMENT_LEFT, -1.0, AXIS_FONT_SIZE, LABEL_COLOR)

func _draw_legend(specs: Array) -> void:
	var font := get_theme_default_font()
	var x := size.x - LEGEND_WIDTH + 6.0
	var y := MARGIN_TOP
	# Latest-turn values give the legend live numbers.
	var latest: Dictionary = {}
	if not _history.is_empty():
		latest = _history[_history.size() - 1].get(_mode, {})
	for s in specs:
		var swatch := Rect2(Vector2(x, y), Vector2(LEGEND_SWATCH, LEGEND_SWATCH))
		draw_rect(swatch, s.color, true)
		if s.has("hatch"):
			for d in range(0, int(LEGEND_SWATCH) + int(LEGEND_SWATCH), 4):
				var a := Vector2(x + float(d) - LEGEND_SWATCH, y + LEGEND_SWATCH)
				var b := Vector2(x + float(d), y)
				draw_line(a.clamp(swatch.position, swatch.end), b.clamp(swatch.position, swatch.end), s.hatch, 1.0)
		draw_rect(swatch, AXIS_COLOR, false, 1.0)
		var val := float(latest.get(s.key, 0.0))
		var text: String = s.label
		if val > 0.005:
			text = "%s  %s" % [s.label, _format_money(val)]
		draw_string(font, Vector2(x + LEGEND_SWATCH + 6.0, y + LEGEND_SWATCH - 2.0),
			text, HORIZONTAL_ALIGNMENT_LEFT, LEGEND_WIDTH - LEGEND_SWATCH - 12.0, AXIS_FONT_SIZE, LABEL_COLOR)
		y += LEGEND_ROW_H

func _draw_centered_note(plot: Rect2, note: String) -> void:
	var font := get_theme_default_font()
	draw_string(font, Vector2(plot.position.x + 12.0, plot.position.y + plot.size.y * 0.5),
		note, HORIZONTAL_ALIGNMENT_LEFT, plot.size.x, AXIS_FONT_SIZE, LABEL_COLOR)

func _format_money(v: float) -> String:
	if v >= 1000.0:
		return "£%.1fk" % (v / 1000.0)
	return "£%.0f" % v
