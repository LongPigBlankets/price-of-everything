extends Control
## DS2 (the tile view's Transport tab): a load against its capacity as a bar of LED cells on a mini screen, the
## way a level meter on a control desk reads. The screen is Building Detail's (res://assets/ui/bdp_v3/
## mini_screen.png and its glass, both 9-slices, as the LED figures use).
##
## The scale runs past the capacity, as a level meter's runs into its red: capacity sits at CAP_AT of the
## scale, marked on the glass. A load beyond the scale stretches it, so the mark moves left and the run past
## it grows with how far over the link is. The unlit cells print the scale's zones faintly: green up to the
## near share of capacity, amber to the mark, red past it. The lit run shows in one colour, the load's tone
## (green with room, amber near capacity, red over it), the rule the link's lamp and its words use, so the
## meter, the lamp and the sentence always read the same state however the cells round. The lit cells carry
## their own light, as the LED figures' segments do.

const Nine := preload("res://scripts/bdp_v3_nine.gd")
const Light := preload("res://scripts/bdp_v3_light.gd")
const SCREEN: Texture2D = preload("res://assets/ui/bdp_v3/mini_screen.png")
const GLASS: Texture2D = preload("res://assets/ui/bdp_v3/mini_screen_glass.png")
const CAPTURE_SCALE := 1.875
## From layout.json (mini_screen), in layout pixels: the render's shadow room, the bezel and the pane's radius.
const MARGIN := 8.0
const RIM := 7.0
const RADIUS := 5.0
## A cell's width and the gap between cells, the room between the pane's edge and the cells, the height.
const CELL_W := 4.0
const CELL_GAP := 2.0
const PAD := Vector2(4.0, 3.0)
const HEIGHT := 22.0
const UNLIT_ALPHA := 0.13
## Where capacity sits on the scale, and how full the scale may be before it stretches.
const CAP_AT := 0.8
const FULL_AT := 0.96
## The capacity mark: printed on the glass in the cream of the keycaps.
const MARK := Color(0.96, 0.93, 0.84, 0.95)

## The load, the capacity, the share of capacity at which a link counts as near it, and the load's tone
## (ok, warn or bad), which colours the lit run.
var used := 0.0
var cap := 1.0
var near := 0.9
var tone := "ok"
var _cells: Control
var _glass: Control


func _init() -> void:
	name = "TransportMeter"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	custom_minimum_size = Vector2(80.0, HEIGHT)
	_cells = Control.new()
	_cells.name = "Cells"
	_cells.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cells.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cells.material = Light.emissive_material()
	_cells.draw.connect(_draw_cells)
	add_child(_cells)
	_glass = Control.new()
	_glass.name = "Glass"
	_glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glass.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_glass.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_glass.draw.connect(_draw_glass)
	add_child(_glass)


## The load against `capacity`, and its tone as the tab judges it (link_tone); judged here by the same
## rule when not given.
func set_load(load_now: float, capacity: float, near_share: float, load_tone := "") -> void:
	used = maxf(load_now, 0.0)
	cap = maxf(capacity, 1.0)
	near = clampf(near_share, 0.05, 1.0)
	tone = load_tone if load_tone != "" else tone_for(used, cap, near)
	queue_redraw()
	_cells.queue_redraw()
	_glass.queue_redraw()


## A load's tone against its capacity: red over it, amber from the near share, green below.
static func tone_for(load_now: float, capacity: float, near_share: float) -> String:
	var share := load_now / maxf(capacity, 1.0)
	if share > 1.0:
		return "bad"
	return "warn" if share >= near_share else "ok"


## The scale's full reading: capacity at CAP_AT of it, stretched when the load runs past FULL_AT.
static func scale_for(load_now: float, capacity: float) -> float:
	return maxf(capacity / CAP_AT, load_now / FULL_AT)


## How many cells the meter holds, and how many are lit for a reading `value` of the scale (at least one
## while anything moves).
static func cells_for(width: float) -> int:
	return maxi(1, int(floor((width + CELL_GAP) / (CELL_W + CELL_GAP))))


static func lit_for(value: float, count: int) -> int:
	if value <= 0.0:
		return 0
	return clampi(maxi(1, roundi(value * count)), 1, count)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
		_cells.queue_redraw()
		_glass.queue_redraw()


func _screen_rect() -> Rect2:
	return Rect2(Vector2.ZERO, size).grow(MARGIN / CAPTURE_SCALE)


func _corner() -> float:
	return (MARGIN + RIM + RADIUS + 2.0) * 2.0 / CAPTURE_SCALE


func _pane() -> Rect2:
	return Rect2(Vector2.ZERO, size).grow(-RIM / CAPTURE_SCALE).grow_individual(-PAD.x, -PAD.y, -PAD.x, -PAD.y)


## The run of cells across the pane: its left, and its length.
func _run() -> Vector2:
	var pane := _pane()
	var count := cells_for(pane.size.x)
	var run := count * CELL_W + (count - 1) * CELL_GAP
	return Vector2(pane.position.x + (pane.size.x - run) * 0.5, run)


func _draw() -> void:
	Nine.paint(self, SCREEN, _screen_rect(), _corner())


func _draw_cells() -> void:
	var pane := _pane()
	var count := cells_for(pane.size.x)
	var run := _run()
	var full := scale_for(used, cap)
	var lit := lit_for(used / full, count)
	var green: Color = DS.PALETTE["OK"]
	var amber: Color = DS.PALETTE["WARN"]
	var red: Color = DS.PALETTE["DANGER"]
	var lamp: Color = red if tone == "bad" else (amber if tone == "warn" else green)
	for i in count:
		var at := (float(i) + 0.5) / float(count) * full
		var zone := red if at > cap else (amber if at >= near * cap else green)
		var cell := Rect2(run.x + i * (CELL_W + CELL_GAP), pane.position.y, CELL_W, pane.size.y)
		if i < lit:
			_cells.draw_rect(cell.grow(0.8), Color(lamp, 0.28))
			_cells.draw_rect(cell, lamp)
		else:
			_cells.draw_rect(cell, Color(zone, UNLIT_ALPHA))


func _draw_glass() -> void:
	Nine.paint(_glass, GLASS, _screen_rect(), _corner())
	# Capacity, marked on the glass between the last cell within it and the first past it, from the pane's
	# top to its foot and a little onto the bezel.
	var pane := _pane()
	var count := cells_for(pane.size.x)
	var run := _run()
	var full := scale_for(used, cap)
	var within := clampi(int(floor(cap / full * count + 0.5)), 1, count)
	var x := run.x + within * (CELL_W + CELL_GAP) - CELL_GAP * 0.5
	_glass.draw_line(Vector2(x, pane.position.y - 2.5), Vector2(x, pane.end.y + 2.5), MARK, 1.5, true)
