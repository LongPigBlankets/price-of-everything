extends Control
## Building Detail v3: a figure on a mini screen in LED segments, as on a digital clock. A gunmetal bezel
## round a recessed pane of dark glass (res://assets/ui/bdp_v3/mini_screen.png, a 9-slice), the digits'
## seven segments lit in `colour` over the unlit ones, faint, and the glass over them (mini_screen_glass.png):
## the bezel's shadow and a faint glare. Rendered by tools/button_mockup/cluster.html?export. The segments
## carry their own light, so the lamp over the panel doesn't dim them (bdp_v3_light.gd's emissive material).
## Digits, "-", "." and spaces are shown.
##
## Every screen follows the owner's rule (docs/ds2-owner-decisions.md, Digital displays): the point takes a cell
## of its own, a figure is at most five cells with the point counted, and never more than two decimals. A number
## handed to set_figure (or measured by cells_for) is fitted to it here (fit): 9.99, 99.99, 999.1, 9999, then
## 15.6K, 1.01M with the letter printed after the screen; decimals are dropped, never added, and a minus takes a
## cell. Leading spaces (a group's padding to one width) are kept.
const Nine := preload("res://scripts/bdp_v3_nine.gd")
const MoneyFigure := preload("res://scripts/ds2/money_figure.gd")
const SUFFIX_FONT: FontFile = preload("res://assets/fonts/BarlowCondensed-SemiBold.ttf")
const SUFFIX_PX := 18
const SUFFIX_GAP := 4.0
const Light := preload("res://scripts/bdp_v3_light.gd")
const SCREEN: Texture2D = preload("res://assets/ui/bdp_v3/mini_screen.png")
const GLASS: Texture2D = preload("res://assets/ui/bdp_v3/mini_screen_glass.png")
const CAPTURE_SCALE := 1.875
## From layout.json (mini_screen), in layout pixels: the render's shadow room, the bezel's width and the
## pane's corner radius.
const MARGIN := 8.0
const RIM := 7.0
const RADIUS := 5.0
## A digit's cell, the gap between cells, the extra room after a digit with its point lit, a segment's
## thickness and the italic slant, in logical pixels; the room between the pane's edge and the digits.
const CELL := Vector2(12.0, 21.0)
const GAP := 3.0
const POINT_ROOM := 4.0
const STROKE := 2.6
const SLANT := 0.1
const PAD := Vector2(5.0, 4.0)
const UNLIT_ALPHA := 0.1

## Which segments each character lights: a top, b upper right, c lower right, d bottom, e lower left,
## f upper left, g middle.
const SEGMENTS := {
	"0": "abcdef", "1": "bc", "2": "abged", "3": "abgcd", "4": "fgbc", "5": "afgcd",
	"6": "afgedc", "7": "abc", "8": "abcdefg", "9": "abcdfg", "-": "g", " ": "",
}

var colour := Color.WHITE
## The point in a cell of its own, as wide as a digit's (the owner's rule, the default). Off only lights the point
## beside the digit before it, the old way; set it before set_figure.
var point_cell := true
## A screen for a tight column (a boardroom place): the cells closer together and less glass round them. Off by
## default; set it before set_figure.
var compact := false
const COMPACT_GAP := 1.0
const COMPACT_PAD := Vector2(3.0, 4.0)
## [character, point after it] per cell.
var _cells: Array = []
## K, M or B printed after the screen when the figure was scaled to fit.
var _suffix := ""
var _segments: Control
var _glass: Control


func _init() -> void:
	name = "BdpV3Led"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_segments = Control.new()
	_segments.name = "Segments"
	_segments.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_segments.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_segments.material = Light.emissive_material()
	_segments.draw.connect(_draw_segments)
	add_child(_segments)
	_glass = Control.new()
	_glass.name = "Glass"
	_glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glass.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_glass.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_glass.draw.connect(func() -> void: Nine.paint(_glass, GLASS, _screen_rect(), _corner()))
	add_child(_glass)


## A figure fitted to the rule: its leading spaces kept, a number (with at most two decimals kept) re-cut to five
## cells counting the point, scaled with K, M or B from 10,000. Returns {figure, suffix}; text that is not a
## number (a dash for no figure) is returned as it is.
static func fit(figure: String) -> Dictionary:
	var body := figure.lstrip(" ")
	var pad := figure.length() - body.length()
	var t := body.strip_edges()
	if t == "" or not t.is_valid_float():
		return {"figure": figure, "suffix": ""}
	var decimals := t.length() - t.find(".") - 1 if t.contains(".") else 0
	var parts := MoneyFigure.screen(t.to_float(), mini(decimals, 2))
	return {"figure": " ".repeat(pad) + str(parts.figure), "suffix": str(parts.suffix)}


## The cells a figure takes once fitted: each digit, "-", "." or space its own (the point its own cell). With
## `points_apart` false, a "." lights the point of the cell before it, the old way.
static func cells_for(figure: String, points_apart := true) -> Array:
	var fitted := str(fit(figure).figure)
	var out: Array = []
	for ch in fitted:
		if ch == "." and not points_apart and not out.is_empty():
			out[-1][1] = true
		elif ch == "." or SEGMENTS.has(ch):
			out.append([ch, false])
	return out


## A screen's width for `cells` cells (the point one of them), bezel and all, without any suffix: for sizing a
## group of screens to one width without building one.
static func width_for_cells(cells: int, tight := false) -> float:
	var n := maxi(1, cells)
	return n * CELL.x + (n - 1) * (COMPACT_GAP if tight else GAP) + 2.0 * (COMPACT_PAD.x if tight else PAD.x) + 2.0 * RIM / CAPTURE_SCALE


## The same cells, the point always its own (kept for callers of the first People build).
static func cells_with_points(figure: String) -> Array:
	return cells_for(figure, true)


func set_figure(figure: String, lit: Color) -> void:
	_cells = cells_for(figure, point_cell)
	_suffix = str(fit(figure).suffix)
	colour = lit
	custom_minimum_size = _pane_size() + Vector2(_suffix_width(), 0.0)
	queue_redraw()
	_segments.queue_redraw()
	_glass.queue_redraw()


## The screen's own size, bezel and all, without the suffix printed after it.
func _pane_size() -> Vector2:
	var pane := Vector2(_digits_width(), CELL.y) + 2.0 * (COMPACT_PAD if compact else PAD)
	return pane + Vector2.ONE * 2.0 * RIM / CAPTURE_SCALE


func _suffix_width() -> float:
	if _suffix == "":
		return 0.0
	return SUFFIX_GAP + SUFFIX_FONT.get_string_size(_suffix, HORIZONTAL_ALIGNMENT_LEFT, -1, SUFFIX_PX).x


## The K, M or B printed after the screen ("" when the figure needed none).
func suffix() -> String:
	return _suffix


func figure() -> String:
	var s := ""
	for c: Array in _cells:
		s += str(c[0]) + ("." if bool(c[1]) else "")
	return s


## The digits' run across: the cells, the gaps between them, and room for each lit point.
func _digits_width() -> float:
	var n := _cells.size()
	var w := n * CELL.x + maxi(n - 1, 0) * _gap()
	for c: Array in _cells:
		w += POINT_ROOM if bool(c[1]) else 0.0
	return w


func _gap() -> float:
	return COMPACT_GAP if compact else GAP


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _screen_rect() -> Rect2:
	return Rect2(Vector2.ZERO, Vector2(size.x - _suffix_width(), size.y)).grow(MARGIN / CAPTURE_SCALE)


func _corner() -> float:
	return (MARGIN + RIM + RADIUS + 2.0) * 2.0 / CAPTURE_SCALE


func _draw() -> void:
	Nine.paint(self, SCREEN, _screen_rect(), _corner())
	if _suffix != "":
		# Printed on the surface after the screen, as a £ is printed before it: white standing off the metal.
		var x := size.x - _suffix_width() + SUFFIX_GAP
		var base := size.y * 0.5 + (SUFFIX_FONT.get_ascent(SUFFIX_PX) - SUFFIX_FONT.get_descent(SUFFIX_PX)) * 0.5
		draw_string(SUFFIX_FONT, Vector2(x + 1, base + 1), _suffix, HORIZONTAL_ALIGNMENT_LEFT, -1, SUFFIX_PX, Color(0, 0, 0, 0.9))
		draw_string(SUFFIX_FONT, Vector2(x, base), _suffix, HORIZONTAL_ALIGNMENT_LEFT, -1, SUFFIX_PX, DS.PALETTE["TEXT"])


func _draw_segments() -> void:
	var n := _cells.size()
	var origin := (Vector2(size.x - _suffix_width(), size.y) - Vector2(_digits_width(), CELL.y)) * 0.5
	var unlit := Color(colour, UNLIT_ALPHA)
	var glow := Color(colour, 0.28)
	var x := 0.0
	for i in n:
		var at := origin + Vector2(x, 0.0)
		var point := bool(_cells[i][1])
		x += CELL.x + _gap() + (POINT_ROOM if point else 0.0)
		if str(_cells[i][0]) == ".":
			# A point in a cell of its own: the dot at the foot of the cell, no segments.
			var spot := at + Vector2(CELL.x * 0.5 - (CELL.y - STROKE * 0.5 - CELL.y) * SLANT, CELL.y - STROKE * 0.5)
			_segments.draw_circle(spot, STROKE * 1.0, glow)
			_segments.draw_circle(spot, STROKE * 0.7, colour)
			continue
		var on := str(SEGMENTS.get(str(_cells[i][0]), ""))
		for seg in "abcdefg":
			var poly := _segment(seg, at)
			if on.contains(seg):
				_segments.draw_colored_polygon(_grown(poly, 0.9), glow)
				_segments.draw_colored_polygon(poly, colour)
			else:
				_segments.draw_colored_polygon(poly, unlit)
		if point:
			var dot := at + Vector2(CELL.x + (GAP + POINT_ROOM) * 0.5, CELL.y - STROKE * 0.5)
			_segments.draw_circle(dot, STROKE * 1.0, glow)
			_segments.draw_circle(dot, STROKE * 0.7, colour)


## One segment's outline, a long hexagon with pointed ends, slanted like a clock's digits.
func _segment(seg: String, at: Vector2) -> PackedVector2Array:
	var w := CELL.x
	var h := CELL.y
	var t := STROKE
	var g := 0.5
	var pts := PackedVector2Array()
	match seg:
		"a", "g", "d":
			var y := {"a": t * 0.5, "g": h * 0.5, "d": h - t * 0.5}[seg] as float
			var x0 := t * 0.5 + g
			var x1 := w - t * 0.5 - g
			pts = PackedVector2Array([Vector2(x0, y), Vector2(x0 + t * 0.5, y - t * 0.5), Vector2(x1 - t * 0.5, y - t * 0.5),
				Vector2(x1, y), Vector2(x1 - t * 0.5, y + t * 0.5), Vector2(x0 + t * 0.5, y + t * 0.5)])
		_:
			var x := t * 0.5 if seg in ["e", "f"] else w - t * 0.5
			var y0 := t * 0.5 + g if seg in ["b", "f"] else h * 0.5 + g
			var y1 := h * 0.5 - g if seg in ["b", "f"] else h - t * 0.5 - g
			pts = PackedVector2Array([Vector2(x, y0), Vector2(x + t * 0.5, y0 + t * 0.5), Vector2(x + t * 0.5, y1 - t * 0.5),
				Vector2(x, y1), Vector2(x - t * 0.5, y1 - t * 0.5), Vector2(x - t * 0.5, y0 + t * 0.5)])
	for i in pts.size():
		pts[i] = at + pts[i] + Vector2((h - pts[i].y) * SLANT, 0.0)
	return pts


static func _grown(poly: PackedVector2Array, by: float) -> PackedVector2Array:
	var grown := Geometry2D.offset_polygon(poly, by)
	return grown[0] if not grown.is_empty() else poly
