extends Control
## Building Detail v3: where each £ of a building's output goes, as one bar on a mini screen
## (res://assets/ui/bdp_v3/mini_screen.png and its glass, 9-slices): its costs in shades of red (inputs,
## labour, upkeep, transport) and its net value added in green, each slice as wide as its share. Each
## slice has its raised icon above it (econ_icon_<key>.png and its shadow, rendered by
## tools/button_mockup/cluster.html?export); where narrow slices crowd their icons together, the icons
## spread apart and a short line joins each to its slice. A loss runs the costs past a white mark at the
## output's value. The slices carry their own light, like the LED figures, so the lamp over the panel
## doesn't dim them. Hovering a slice or its icon names it, with its £ and share.

const Nine := preload("res://scripts/bdp_v3_nine.gd")
const Light := preload("res://scripts/bdp_v3_light.gd")
const SCREEN: Texture2D = preload("res://assets/ui/bdp_v3/mini_screen.png")
const GLASS: Texture2D = preload("res://assets/ui/bdp_v3/mini_screen_glass.png")
const CAPTURE_SCALE := 1.875
## From layout.json (mini_screen), in layout pixels: the screen's shadow room, bezel and pane radius.
const SCREEN_MARGIN := 8.0
const SCREEN_RIM := 7.0
const SCREEN_RADIUS := 5.0
## Drawn sizes, in logical pixels: an icon's frame, the gap under the icons, the bar's height inside
## the bezel, and the room between icons that crowd.
const ICON_PX := 36.0
const ICON_GAP := 4.0
const BAR_H := 16.0
const ICON_SPACING := 2.0
## The slices, in the order they run: key (for its icon), name, and colour.
const SLICES := [
	{"key": "inputs", "name": "Inputs", "colour": Color("#6b1914")},
	{"key": "labour", "name": "Labour", "colour": Color("#8e231b")},
	{"key": "upkeep", "name": "Upkeep", "colour": Color("#b03026")},
	{"key": "transport", "name": "Transport", "colour": Color("#d64a3a")},
	{"key": "value", "name": "Net value added", "colour": Color("#3fb265")},
]

## [{key, name, colour, value, from, to}] per slice drawn, from and to as shares of the bar.
var _slices: Array = []
var _output_mark := -1.0
var _icons := {}
var _layer: Control


func _init() -> void:
	name = "BdpV3ValueBar"
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(0.0, ICON_PX + ICON_GAP + _bar_frame_h())
	mouse_filter = Control.MOUSE_FILTER_PASS
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
	glass.draw.connect(func() -> void: Nine.paint(glass, GLASS, _bar_rect().grow(SCREEN_MARGIN / CAPTURE_SCALE), _corner()))
	add_child(glass)
	for s: Dictionary in SLICES:
		var key := str(s.key)
		_icons[key] = [load("res://assets/ui/bdp_v3/econ_icon_%s.png" % key), load("res://assets/ui/bdp_v3/econ_icon_%s_shadow.png" % key)]


## The slices for an economics reading (BuildingEconomics.per_turn): the costs, then the net value
## added if there is any. The bar spans the output's value or, at a loss, the costs.
static func slices_for(econ: Dictionary) -> Array:
	var values := {
		"inputs": float(econ.get("input_value", 0.0)), "labour": float(econ.get("labour", 0.0)),
		"upkeep": float(econ.get("upkeep", 0.0)), "transport": float(econ.get("transport", 0.0)),
		"value": maxf(0.0, float(econ.get("net_value_added", 0.0))),
	}
	var costs := 0.0
	for k in ["inputs", "labour", "upkeep", "transport"]:
		costs += maxf(0.0, float(values[k]))
	var span := maxf(float(econ.get("output_value", 0.0)), costs)
	var out: Array = []
	var at := 0.0
	for s: Dictionary in SLICES:
		var v := maxf(0.0, float(values[s.key]))
		if v <= 0.0 or span <= 0.0:
			continue
		out.append({"key": s.key, "name": s.name, "colour": s.colour, "value": v, "from": at / span, "to": (at + v) / span})
		at += v
	return out


func set_values(econ: Dictionary) -> void:
	_slices = slices_for(econ)
	var costs := 0.0
	for s: Dictionary in _slices:
		if s.key != "value":
			costs += float(s.value)
	var output_value := float(econ.get("output_value", 0.0))
	_output_mark = output_value / costs if costs > output_value and costs > 0.0 else -1.0
	queue_redraw()
	_layer.queue_redraw()


func slice_keys() -> Array:
	return _slices.map(func(s: Dictionary) -> String: return str(s.key))


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
		_layer.queue_redraw()


func _bar_frame_h() -> float:
	return BAR_H + 2.0 * (SCREEN_RIM / CAPTURE_SCALE + 2.0)


## The bezel's rect, under the icons.
func _bar_rect() -> Rect2:
	return Rect2(0.0, ICON_PX + ICON_GAP, size.x, _bar_frame_h())


## The pane the slices fill, inside the bezel.
func _pane() -> Rect2:
	return _bar_rect().grow(-(SCREEN_RIM / CAPTURE_SCALE + 2.0))


func _corner() -> float:
	return (SCREEN_MARGIN + SCREEN_RIM + SCREEN_RADIUS + 2.0) * 2.0 / CAPTURE_SCALE


## Each slice's icon centre, spread so no two overlap, kept over the bar.
func icon_centres() -> Array:
	var pane := _pane()
	var xs: Array = []
	for s: Dictionary in _slices:
		xs.append(pane.position.x + pane.size.x * (float(s.from) + float(s.to)) * 0.5)
	var step := ICON_PX + ICON_SPACING
	var lo := ICON_PX * 0.5
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
	Nine.paint(self, SCREEN, _bar_rect().grow(SCREEN_MARGIN / CAPTURE_SCALE), _corner())
	var pane := _pane()
	var centres := icon_centres()
	for i in _slices.size():
		var s: Dictionary = _slices[i]
		var cx: float = centres[i]
		var slice_x := pane.position.x + pane.size.x * (float(s.from) + float(s.to)) * 0.5
		if absf(cx - slice_x) > 2.0:
			draw_line(Vector2(cx, ICON_PX - 2.0), Vector2(slice_x, pane.position.y - 1.0), Color(1, 1, 1, 0.45), 1.0, true)
		var rect := Rect2(cx - ICON_PX * 0.5, 0.0, ICON_PX, ICON_PX)
		var tex: Array = _icons[str(s.key)]
		draw_texture_rect(tex[1], rect, false)
		draw_texture_rect(tex[0], rect, false)


func _draw_slices() -> void:
	var pane := _pane()
	for s: Dictionary in _slices:
		var x0 := pane.position.x + pane.size.x * float(s.from)
		var x1 := pane.position.x + pane.size.x * float(s.to)
		var r := Rect2(x0, pane.position.y, maxf(x1 - x0, 1.0), pane.size.y)
		var c: Color = s.colour
		_layer.draw_rect(r, c)
		# A little light along the top of each slice and shade along its foot, so it reads as lit.
		_layer.draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.35)), Color(1, 1, 1, 0.12))
		_layer.draw_rect(Rect2(r.position + Vector2(0.0, r.size.y * 0.75), Vector2(r.size.x, r.size.y * 0.25)), Color(0, 0, 0, 0.18))
		if x0 > pane.position.x + 0.5:
			_layer.draw_line(Vector2(x0, r.position.y), Vector2(x0, r.end.y), Color(0, 0, 0, 0.55), 1.0)
	if _output_mark > 0.0:
		var mx := pane.position.x + pane.size.x * _output_mark
		_layer.draw_line(Vector2(mx, pane.position.y - 2.0), Vector2(mx, pane.end.y + 2.0), Color.WHITE, 2.0)


func _get_tooltip(at_position: Vector2) -> String:
	var pane := _pane()
	var centres := icon_centres()
	for i in _slices.size():
		var s: Dictionary = _slices[i]
		var icon := Rect2(float(centres[i]) - ICON_PX * 0.5, 0.0, ICON_PX, ICON_PX)
		var bar := Rect2(pane.position.x + pane.size.x * float(s.from), pane.position.y,
			pane.size.x * (float(s.to) - float(s.from)), pane.size.y)
		if icon.has_point(at_position) or bar.has_point(at_position):
			return "%s: £%.2f (%d%%)" % [s.name, float(s.value), roundi((float(s.to) - float(s.from)) * 100.0)]
	return ""
