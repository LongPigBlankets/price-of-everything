extends Control
# Stacked line/area chart of the last N turns of money, split by colour-coded series.
# Toggles between "revenue" and "costs". Axes are kept thin and skinny to match the
# tile-view panel (the same light-blue BORDER_COLOR treatment).

const AXIS_COLOR := Color(0.7, 0.85, 1.0, 0.65)
const GRID_COLOR := Color(0.7, 0.85, 1.0, 0.14)
const LABEL_COLOR := Color(0.7, 0.85, 1.0, 0.85)
const TOP_LINE_COLOR := Color(1.0, 1.0, 1.0, 0.35)
const NAVY := Color(0.02, 0.06, 0.18)

const MARGIN_LEFT := 58.0
const MARGIN_TOP := 14.0
const MARGIN_BOTTOM := 26.0
const MARGIN_RIGHT := 12.0
const LEGEND_WIDTH := 232.0      # the legend is checkboxes now, not drawn text
const LEGEND_SWATCH := 16.0
const AXIS_FONT_SIZE := 14

# Series are stacked bottom -> top in array order. `key` indexes into the per-turn
# breakdown dict the money panel records; `hatch` (optional) overlays a navy crosshatch.
const REVENUE_SERIES := [
	{"key": "finished",     "label": "Finished goods",     "color": Color(0.60, 0.90, 0.60)},   # light green
	{"key": "intermediate", "label": "Intermediate goods", "color": Color(0.10, 0.45, 0.16)},   # dark green
	{"key": "raw",          "label": "Raw goods",          "color": Color(0.55, 0.95, 0.78)},   # mint green
	{"key": "construction", "label": "Construction goods", "color": Color(0.95, 0.88, 0.25)},   # yellow
	{"key": "power",        "label": "Power sold",         "color": Color(0.55, 0.80, 0.95)},   # light blue
	{"key": "green_subsidy","label": "Green subsidy",      "color": Color(0.35, 0.75, 0.40)},   # subsidy green
]
const COST_SERIES := [
	{"key": "raw",          "label": "Raw goods bought",   "color": Color(0.55, 0.08, 0.08)},   # dark red
	{"key": "intermediate", "label": "Intermediate bought","color": Color(0.95, 0.45, 0.45)},   # light red
	{"key": "construction", "label": "Construction bought","color": Color(0.50, 0.33, 0.15)},   # brown
	{"key": "power",        "label": "Power bought",       "color": Color(0.95, 0.60, 0.15)},   # orange
	{"key": "transport",    "label": "Transport",          "color": Color(0.20, 0.62, 0.60)},   # teal
	{"key": "warehousing",  "label": "Warehousing",        "color": Color(0.42, 0.55, 0.35)},   # olive
	{"key": "maintenance",  "label": "Maintenance",        "color": Color(0.60, 0.30, 0.72)},   # purple
	{"key": "labour",       "label": "Labour",             "color": Color(0.96, 0.55, 0.78)},   # pink
	{"key": "advisor",      "label": "Advisor salaries",   "color": Color(0.80, 0.42, 0.62)},   # mauve
	{"key": "carbon_tax",   "label": "Carbon tax",         "color": Color(0.25, 0.25, 0.28), "hatch": NAVY},  # soot, hatched
	{"key": "taxes",        "label": "Taxes",              "color": Color(0.78, 0.78, 0.78)},   # light grey
	{"key": "dividends",    "label": "Dividends",          "color": Color(0.36, 0.36, 0.38)},   # dark grey
	{"key": "profit_sharing","label": "Profit sharing",     "color": Color(0.62, 0.72, 0.95)},   # slate blue
	{"key": "interest",     "label": "Interest",           "color": Color(0.92, 0.85, 0.20), "hatch": NAVY},  # yellow hatched navy
]

var _history: Array = []   # Array of { "revenue": {...}, "costs": {...}, "turn": int }
var _mode: String = "revenue"
## Series the player has unticked, keyed "<mode>|<key>" so revenue and costs each keep
## their own selection. A hidden series leaves the stack AND the y-axis, so unticking the
## big ones is how you read the small ones — which is the whole point of the tickboxes.
var _hidden: Dictionary = {}
var _legend_box: VBoxContainer = null
var _legend_rows: VBoxContainer = null
var _legend_mode: String = ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # the plot; the legend's children are hit-tested
	# Tall enough for the LONGEST legend (costs runs to fourteen series) plus its two
	# buttons — the tickboxes are real Controls now, and a column of them that outgrows the
	# chart hangs off the panel and draws over the map.
	custom_minimum_size = Vector2(0, 480)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_legend_shell()

func set_data(history: Array, mode: String) -> void:
	_history = history
	if mode != _mode:
		_mode = mode
		_rebuild_legend()
	queue_redraw()

func _series_specs() -> Array:
	return COST_SERIES if _mode == "costs" else REVENUE_SERIES

## The series actually drawn: everything the player has left ticked.
func _visible_specs() -> Array:
	var out: Array = []
	for s in _series_specs():
		if not bool(_hidden.get("%s|%s" % [_mode, str(s.key)], false)):
			out.append(s)
	return out

# ── Legend: one tickbox per series, and the two bulk actions under them ───────────────
## The legend column runs the FULL height of the chart, with the tickboxes in a scroll and
## the two bulk actions pinned under them. Anchored rather than laid out so it cannot push
## the plot around, and scrolled rather than free-growing because a fourteen-series column
## outgrows any panel height that also fits on a 1080p screen — it used to hang off the
## bottom of the panel and draw over the map.
func _build_legend_shell() -> void:
	_legend_box = VBoxContainer.new()
	_legend_box.anchor_left = 1.0
	_legend_box.anchor_right = 1.0
	_legend_box.anchor_top = 0.0
	_legend_box.anchor_bottom = 1.0
	_legend_box.offset_left = -LEGEND_WIDTH + 6.0
	_legend_box.offset_right = -6.0
	_legend_box.offset_top = MARGIN_TOP
	_legend_box.offset_bottom = -MARGIN_BOTTOM
	_legend_box.add_theme_constant_override("separation", 6)
	_legend_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_legend_box)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_legend_box.add_child(scroll)
	_legend_rows = VBoxContainer.new()
	_legend_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_legend_rows.add_theme_constant_override("separation", 2)
	_legend_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(_legend_rows)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_legend_box.add_child(actions)
	actions.add_child(_action_button("Select all", true))
	actions.add_child(_action_button("Clear all", false))
	_rebuild_legend()

func _action_button(text: String, select: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", AXIS_FONT_SIZE)
	b.pressed.connect(_set_all.bind(select))
	return b

func _set_all(select: bool) -> void:
	for s in _series_specs():
		_hidden["%s|%s" % [_mode, str(s.key)]] = not select
	_rebuild_legend()
	queue_redraw()

func _rebuild_legend() -> void:
	if _legend_rows == null:
		return
	_legend_mode = _mode
	for c in _legend_rows.get_children():
		c.queue_free()
	for s in _series_specs():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var swatch := ColorRect.new()
		swatch.color = s.color
		swatch.custom_minimum_size = Vector2(LEGEND_SWATCH, LEGEND_SWATCH)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(swatch)
		var box := CheckBox.new()
		# The label only — the latest turn's figure used to trail every row, which is what
		# pushed the legend into the plot and off the panel (owner 2026-08-24). The numbers
		# are on the Balance sheet, itemised, where they can be read properly.
		box.text = str(s.label)
		box.focus_mode = Control.FOCUS_NONE
		box.button_pressed = not bool(_hidden.get("%s|%s" % [_mode, str(s.key)], false))
		box.add_theme_font_size_override("font_size", AXIS_FONT_SIZE)
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.toggled.connect(_on_series_toggled.bind(str(s.key)))
		row.add_child(box)
		_legend_rows.add_child(row)

func _on_series_toggled(pressed: bool, key: String) -> void:
	_hidden["%s|%s" % [_mode, key]] = not pressed
	queue_redraw()

func _draw() -> void:
	var specs := _visible_specs()
	if _legend_mode != _mode:
		_rebuild_legend()
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

	if n == 0:
		_draw_centered_note(plot, "No turns recorded yet")
		return
	if specs.is_empty():
		_draw_centered_note(plot, "Nothing selected")
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

func _draw_centered_note(plot: Rect2, note: String) -> void:
	var font := get_theme_default_font()
	draw_string(font, Vector2(plot.position.x + 12.0, plot.position.y + plot.size.y * 0.5),
		note, HORIZONTAL_ALIGNMENT_LEFT, plot.size.x, AXIS_FONT_SIZE, LABEL_COLOR)

func _format_money(v: float) -> String:
	if v >= 1000.0:
		return "£%.1fk" % (v / 1000.0)
	return "£%.0f" % v
