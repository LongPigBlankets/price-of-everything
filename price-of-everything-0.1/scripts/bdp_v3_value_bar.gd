extends Control
## Building Detail v3: a building's revenue and its costs as two bars on the same scale, each on a mini
## screen (res://assets/ui/bdp_v3/mini_screen.png and its glass, 9-slices), so the gap between their ends
## is what it adds. The revenue bar (if sold, when the output stays in stock) has a slice for each good it
## sells in shades of green, the good's icon above it on a small rounded tile; the cost bar has inputs,
## labour, upkeep and transport in shades of red, each with its raised icon above it (econ_icon_<key>.png
## and its shadow, rendered by tools/button_mockup/cluster.html?export). Where narrow slices crowd their icons together, the icons
## spread apart and a short line joins each to its slice; a faint mark on the cost bar shows where the
## revenue ends. The slices carry their own light, like the LED figures, so the lamp over the panel doesn't
## dim them. Hovering a slice or its icon names it, with its £ and its share of the revenue.

const Nine := preload("res://scripts/bdp_v3_nine.gd")
const Light := preload("res://scripts/bdp_v3_light.gd")
const Plate := preload("res://scripts/bdp_v3_plate.gd")
const GoodIcons := preload("res://scripts/good_icons.gd")
const UIHelpers := preload("res://scripts/ui_helpers.gd")
const SCREEN: Texture2D = preload("res://assets/ui/bdp_v3/mini_screen.png")
const GLASS: Texture2D = preload("res://assets/ui/bdp_v3/mini_screen_glass.png")
const CAPTURE_SCALE := 1.875
## From layout.json (mini_screen), in layout pixels: the screen's shadow room, bezel and pane radius.
const SCREEN_MARGIN := 8.0
const SCREEN_RIM := 7.0
const SCREEN_RADIUS := 5.0
## Drawn sizes, in logical pixels: the label column, an icon, the room between the icons and their bar
## (the leader lines run through it), a bar's height inside its bezel, the room between the two bars, and
## the room between icons that crowd.
const LABEL_W := 70.0
const ICON_PX := 32.0
const ICON_GAP := 12.0
const BAR_H := 14.0
const ROW_GAP := 14.0
const ICON_SPACING := 2.0
const LABEL_SIZE := 13
const REVENUE_GREENS: Array[Color] = [Color("#3fb265"), Color("#2e8f4f"), Color("#5fcf85"), Color("#23713d")]
## The cost slices, in the order they run: key (for its icon), name, and colour.
const COSTS := [
	{"key": "inputs", "name": "Inputs", "colour": Color("#6b1914")},
	{"key": "labour", "name": "Labour", "colour": Color("#8e231b")},
	{"key": "upkeep", "name": "Upkeep", "colour": Color("#b03026")},
	{"key": "transport", "name": "Transport", "colour": Color("#d64a3a")},
]

## Two rows, revenue then costs: {label, slices: [{key, name, colour, value, from, to, icon, shadow}]},
## from and to as shares of the common scale.
var _rows: Array = []
var _revenue := 0.0
var _revenue_end := 0.0
var _layer: Control
var _tile := StyleBoxFlat.new()


func _init() -> void:
	name = "BdpV3ValueBar"
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(0.0, 2.0 * _row_h() + ROW_GAP)
	mouse_filter = Control.MOUSE_FILTER_PASS
	_tile.bg_color = UIHelpers.PILL_PAPER
	_tile.set_corner_radius_all(6)
	_tile.shadow_color = Color(0, 0, 0, 0.45)
	_tile.shadow_size = 3
	_tile.shadow_offset = Vector2(1.5, 1.5)
	_layer = Control.new()
	_layer.name = "Slices"
	_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layer.material = Light.emissive_material()
	_layer.draw.connect(_draw_slices)
	add_child(_layer)
	var glass := Control.new()
	glass.name = "Glass"
	glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glass.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	glass.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glass.draw.connect(func() -> void:
		for i in _rows.size():
			Nine.paint(glass, GLASS, _bar_rect(i).grow(SCREEN_MARGIN / CAPTURE_SCALE), _corner()))
	add_child(glass)


## The two bars for an economics reading (BuildingEconomics.per_turn), on one scale: the revenue or the
## costs, whichever is larger. Each is {label, slices: [{key, name, colour, value, from, to}]}.
static func rows_for(econ: Dictionary) -> Array:
	var outputs: Array = econ.get("outputs", [])
	var revenue := 0.0
	for o: Dictionary in outputs:
		revenue += maxf(0.0, float(o.get("value", 0.0)))
	var values := {"inputs": float(econ.get("input_value", 0.0)), "labour": float(econ.get("labour", 0.0)),
		"upkeep": float(econ.get("upkeep", 0.0)), "transport": float(econ.get("transport", 0.0))}
	var costs := 0.0
	for k in values:
		costs += maxf(0.0, float(values[k]))
	var span := maxf(revenue, costs)
	var income: Array = []
	var at := 0.0
	for i in outputs.size():
		var o: Dictionary = outputs[i]
		var v := maxf(0.0, float(o.get("value", 0.0)))
		if v <= 0.0 or span <= 0.0:
			continue
		var gid := str(o.get("good_id", ""))
		income.append({"key": gid, "name": "Power" if gid == "power" else Catalog.get_display_name(gid),
			"colour": REVENUE_GREENS[i % REVENUE_GREENS.size()], "value": v, "from": at / span, "to": (at + v) / span})
		at += v
	var spend: Array = []
	at = 0.0
	for c: Dictionary in COSTS:
		var v := maxf(0.0, float(values[c.key]))
		if v <= 0.0 or span <= 0.0:
			continue
		spend.append({"key": c.key, "name": c.name, "colour": c.colour, "value": v, "from": at / span, "to": (at + v) / span})
		at += v
	return [
		{"label": "Revenue" if bool(econ.get("sold", true)) else "Revenue if sold", "slices": income},
		{"label": "Costs", "slices": spend},
	]


func set_values(econ: Dictionary) -> void:
	_rows = rows_for(econ)
	_revenue = 0.0
	_revenue_end = 0.0
	for s: Dictionary in _rows[0].slices:
		_revenue += float(s.value)
		_revenue_end = maxf(_revenue_end, float(s.to))
	for row: Dictionary in _rows:
		for s: Dictionary in row.slices:
			var icon := _icon_for(str(s.key))
			s.icon = icon[0]
			s.shadow = icon[1]
	queue_redraw()
	_layer.queue_redraw()


func row_keys(row: int) -> Array:
	return (_rows[row].slices as Array).map(func(s: Dictionary) -> String: return str(s.key)) if row < _rows.size() else []


func row_label(row: int) -> String:
	return str(_rows[row].label) if row < _rows.size() else ""


## A slice's icon: the raised economics icon for a cost, the good's own icon for an output, the coins for
## power. [face, shadow or null].
static func _icon_for(key: String) -> Array:
	var path := "res://assets/ui/bdp_v3/econ_icon_%s.png"
	if key in ["inputs", "labour", "upkeep", "transport"]:
		return [load(path % key), load((path % key).replace(".png", "_shadow.png"))]
	if key == "power":
		return [load(path % "value"), load((path % "value").replace(".png", "_shadow.png"))]
	return [GoodIcons.texture_for_size(key, str(Catalog.get_good(key).get("internal_name", "")), float(ICON_PX)), null]


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
		_layer.queue_redraw()


func _bar_frame_h() -> float:
	return BAR_H + 2.0 * (SCREEN_RIM / CAPTURE_SCALE + 2.0)


func _row_h() -> float:
	return ICON_PX + ICON_GAP + _bar_frame_h()


## A row's bezel, right of its label and under its icons.
func _bar_rect(row: int) -> Rect2:
	var top := row * (_row_h() + ROW_GAP) + ICON_PX + ICON_GAP
	return Rect2(LABEL_W, top, size.x - LABEL_W, _bar_frame_h())


## The pane a row's slices fill, inside its bezel.
func _pane(row: int) -> Rect2:
	return _bar_rect(row).grow(-(SCREEN_RIM / CAPTURE_SCALE + 2.0))


func _corner() -> float:
	return (SCREEN_MARGIN + SCREEN_RIM + SCREEN_RADIUS + 2.0) * 2.0 / CAPTURE_SCALE


## A row's icon centres, spread so no two overlap, kept over its bar.
func icon_centres(row: int) -> Array:
	var pane := _pane(row)
	var xs: Array = []
	for s: Dictionary in _rows[row].slices:
		xs.append(pane.position.x + pane.size.x * (float(s.from) + float(s.to)) * 0.5)
	var step := ICON_PX + ICON_SPACING
	var lo := LABEL_W + ICON_PX * 0.5
	var hi := size.x - ICON_PX * 0.5
	for _pass in 8:
		for i in range(1, xs.size()):
			xs[i] = maxf(float(xs[i]), float(xs[i - 1]) + step)
		if not xs.is_empty():
			xs[-1] = minf(float(xs[-1]), hi)
		for i in range(xs.size() - 2, -1, -1):
			xs[i] = minf(float(xs[i]), float(xs[i + 1]) - step)
		if not xs.is_empty():
			xs[0] = maxf(float(xs[0]), lo)
	return xs


func _draw() -> void:
	var font: Font = Plate.FONT_SEMI
	for r in _rows.size():
		var bar := _bar_rect(r)
		Nine.paint(self, SCREEN, bar.grow(SCREEN_MARGIN / CAPTURE_SCALE), _corner())
		# The row's name, printed on the steel beside its bar, in capitals: one word a line.
		var words := str(_rows[r].label).to_upper().split(" ")
		var lines: Array = [words[0]] if words.size() == 1 else [words[0], " ".join(words.slice(1))]
		var line_h := font.get_height(LABEL_SIZE)
		var y := bar.get_center().y - line_h * lines.size() * 0.5 + font.get_ascent(LABEL_SIZE)
		for ln: String in lines:
			draw_string(font, Vector2(1.0, y + 1.0), ln, HORIZONTAL_ALIGNMENT_LEFT, LABEL_W - 6.0, LABEL_SIZE, Color(0, 0, 0, 0.8))
			draw_string(font, Vector2(0.0, y), ln, HORIZONTAL_ALIGNMENT_LEFT, LABEL_W - 6.0, LABEL_SIZE, DS.PALETTE["TEXT"])
			y += line_h
		var pane := _pane(r)
		var centres := icon_centres(r)
		var top := r * (_row_h() + ROW_GAP)
		for i in _rows[r].slices.size():
			var s: Dictionary = _rows[r].slices[i]
			var cx: float = centres[i]
			var slice_x := pane.position.x + pane.size.x * (float(s.from) + float(s.to)) * 0.5
			draw_line(Vector2(cx, top + ICON_PX + 1.0), Vector2(slice_x, pane.position.y - 2.0), Color(1, 1, 1, 0.4), 1.0, true)
			var rect := Rect2(cx - ICON_PX * 0.5, top, ICON_PX, ICON_PX)
			if s.get("shadow") != null:
				draw_texture_rect(s.shadow, rect, false)
			else:
				# A good's own icon sits on a small rounded tile, as good icons do elsewhere.
				_tile.draw(get_canvas_item(), rect.grow(-1.0))
			if s.get("icon") != null:
				draw_texture_rect(s.icon, rect.grow(-4.0) if s.get("shadow") == null else rect, false)


func _draw_slices() -> void:
	for r in _rows.size():
		var pane := _pane(r)
		for s: Dictionary in _rows[r].slices:
			var x0 := pane.position.x + pane.size.x * float(s.from)
			var x1 := pane.position.x + pane.size.x * float(s.to)
			var rect := Rect2(x0, pane.position.y, maxf(x1 - x0, 1.0), pane.size.y)
			_layer.draw_rect(rect, s.colour)
			# A little light along the top of each slice and shade along its foot, so it reads as lit.
			_layer.draw_rect(Rect2(rect.position, Vector2(rect.size.x, rect.size.y * 0.35)), Color(1, 1, 1, 0.12))
			_layer.draw_rect(Rect2(rect.position + Vector2(0.0, rect.size.y * 0.75), Vector2(rect.size.x, rect.size.y * 0.25)), Color(0, 0, 0, 0.18))
			if x0 > pane.position.x + 0.5:
				_layer.draw_line(Vector2(x0, rect.position.y), Vector2(x0, rect.end.y), Color(0, 0, 0, 0.55), 1.0)
	if _rows.size() > 1 and _revenue_end > 0.0:
		# Where the revenue ends, marked faintly across the cost bar.
		var pane := _pane(1)
		var mx := pane.position.x + pane.size.x * _revenue_end
		var y := pane.position.y - 3.0
		while y < pane.end.y + 3.0:
			_layer.draw_line(Vector2(mx, y), Vector2(mx, minf(y + 2.5, pane.end.y + 3.0)), Color(1, 1, 1, 0.55), 1.0)
			y += 4.5


func _get_tooltip(at_position: Vector2) -> String:
	for r in _rows.size():
		var pane := _pane(r)
		var centres := icon_centres(r)
		var top := r * (_row_h() + ROW_GAP)
		for i in _rows[r].slices.size():
			var s: Dictionary = _rows[r].slices[i]
			var icon := Rect2(float(centres[i]) - ICON_PX * 0.5, top, ICON_PX, ICON_PX)
			var bar := Rect2(pane.position.x + pane.size.x * float(s.from), pane.position.y,
				pane.size.x * (float(s.to) - float(s.from)), pane.size.y)
			if icon.has_point(at_position) or bar.has_point(at_position):
				var share := float(s.value) / _revenue * 100.0 if _revenue > 0.0 else 0.0
				return "%s: £%.2f (%d%% of the revenue)" % [s.name, float(s.value), roundi(share)]
	return ""
