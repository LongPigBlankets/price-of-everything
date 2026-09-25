extends Control
## Tile view v3: the land as a sight gauge (docs/tile-view-ds2-plan.md §4.2 and §9). One long window in the
## mini screen's gunmetal bezel (res://assets/ui/bdp_v3/mini_screen.png and its glass), the tile's land
## behind it from left to right in the one vocabulary TileViewData.land_totals uses: your buildings (a
## segment each in its category's colour, hatched while under construction), your free land, the land you
## can still buy, and other companies' land at the far end. A segment names its building on hover and
## opens it on a click.

signal segment_clicked(instance_id: String)

const Nine := preload("res://scripts/bdp_v3_nine.gd")
const SCREEN: Texture2D = preload("res://assets/ui/bdp_v3/mini_screen.png")
const GLASS: Texture2D = preload("res://assets/ui/bdp_v3/mini_screen_glass.png")
const CAPTURE_SCALE := 1.875
const TEXELS := 2.0 / 1.875
## From layout.json (mini_screen), in layout pixels: the render's shadow room, the bezel and the pane's corner.
const MARGIN := 8.0
const RIM := 7.0
const RADIUS := 5.0
const HEIGHT := 30.0
## The land's colours behind the glass. Free and buyable match the legend's swatches.
const FREE := Color("#4fae6e")
const BUYABLE := Color("#6f8196")
const OTHERS := Color("#3b4048")
const PANE := Color("#0d1014")

## [{size, colour, name, instance_id, construction}] from left to right, and the axis they fill.
var _spans: Array = []
var _axis := 1.0


func _init() -> void:
	name = "TileLandChart"
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(0, HEIGHT)


## `chart` is TileViewData.land_chart_data, `totals` TileViewData.land_totals.
func configure(chart: Dictionary, totals: Dictionary) -> void:
	_spans.clear()
	var others := 0.0
	for seg: Dictionary in chart.get("segments", []):
		if bool(seg.get("is_other", false)):
			others += float(seg.get("size", 0.0))
			continue
		_spans.append({"size": float(seg.get("size", 0.0)), "colour": seg.get("color", BUYABLE),
			"name": str(seg.get("tooltip", seg.get("name", ""))), "instance_id": str(seg.get("instance_id", "")),
			"construction": bool(seg.get("is_construction", false))})
	if int(totals.get("free", 0)) > 0:
		_spans.append({"size": float(totals.free), "colour": FREE, "name": "%d free to build on" % int(totals.free)})
	if int(totals.get("buyable", 0)) > 0:
		_spans.append({"size": float(totals.buyable), "colour": BUYABLE, "name": "%d you can buy" % int(totals.buyable)})
	if others > 0.0:
		_spans.append({"size": others, "colour": OTHERS, "name": "%d held by other companies" % int(round(others)), "others": true})
	var total := 0.0
	for s: Dictionary in _spans:
		total += float(s.size)
	# The axis is the tile's whole land; a tile built past what it owns widens it rather than overflowing.
	_axis = maxf(1.0, maxf(float(chart.get("axis_max", 1.0)), total))
	queue_redraw()


func _pane() -> Rect2:
	return Rect2(Vector2.ZERO, size).grow(-RIM / CAPTURE_SCALE)


func _draw() -> void:
	var out := MARGIN / CAPTURE_SCALE
	Nine.paint(self, SCREEN, Rect2(Vector2.ZERO, size).grow(out), (MARGIN + RIM + RADIUS + 2.0) * TEXELS)
	var pane := _pane()
	draw_rect(pane, PANE)
	var x := pane.position.x
	for s: Dictionary in _spans:
		var w := pane.size.x * float(s.size) / _axis
		var r := Rect2(x, pane.position.y, w, pane.size.y)
		draw_rect(r, Color(s.colour))
		if bool(s.get("construction", false)) or bool(s.get("others", false)):
			_hatch(r, Color(0, 0, 0, 0.35))
		if w > 3.0:
			draw_line(Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.end.y), Color(0, 0, 0, 0.45), 1.0)
		x += w
	Nine.paint(self, GLASS, Rect2(Vector2.ZERO, size).grow(out), (MARGIN + RIM + RADIUS + 2.0) * TEXELS)


func _hatch(r: Rect2, colour: Color) -> void:
	var step := 6.0
	var t := -r.size.y
	while t < r.size.x:
		var a := Vector2(r.position.x + maxf(t, 0.0), r.position.y + maxf(-t, 0.0))
		var b := Vector2(r.position.x + minf(t + r.size.y, r.size.x), r.position.y + minf(r.size.y, r.size.x - t))
		draw_line(a, b, colour, 1.5)
		t += step


## The span under a point, or {}.
func span_at(p: Vector2) -> Dictionary:
	var pane := _pane()
	var x := pane.position.x
	for s: Dictionary in _spans:
		var w := pane.size.x * float(s.size) / _axis
		if p.x >= x and p.x < x + w:
			return s
		x += w
	return {}


func _get_tooltip(at: Vector2) -> String:
	return str(span_at(at).get("name", ""))


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var iid := str(span_at(mb.position).get("instance_id", ""))
	if iid != "":
		segment_clicked.emit(iid)
		accept_event()
