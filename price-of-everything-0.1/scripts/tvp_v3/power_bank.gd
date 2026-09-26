extends Control
## Tile view v3, Power: the tile's battery bank and its charge. A long cell in the LED screens' gunmetal
## bezel (res://assets/ui/bdp_v3/mini_screen.png and its glass, 9-slices) with a terminal at its right end,
## its window a row of cells lit green up to how much of the housing the loaded cells fill, the rest dark
## as an LED's unlit segments are. The cells carry their own light, like the LED figures.

const Nine := preload("res://scripts/bdp_v3_nine.gd")
const Light := preload("res://scripts/bdp_v3_light.gd")
const SCREEN: Texture2D = preload("res://assets/ui/bdp_v3/mini_screen.png")
const GLASS: Texture2D = preload("res://assets/ui/bdp_v3/mini_screen_glass.png")
const CAPTURE_SCALE := 1.875
## From layout.json (mini_screen), in layout pixels.
const SCREEN_MARGIN := 8.0
const SCREEN_RIM := 7.0
const SCREEN_RADIUS := 5.0
## Drawn sizes, in logical pixels: the bank's height, the terminal at its end, the cells and the gap
## between them.
const HEIGHT := 34.0
const TERMINAL := Vector2(7.0, 14.0)
const CELLS := 12
const CELL_GAP := 3.0
const LIT := Color("#4fdc86")
const UNLIT_ALPHA := 0.1
const TERMINAL_INK := Color("#5a616b")

## How full the housing is, 0 to 1.
var charge := 0.0
var _cells: Control
var _glass: Control


func _init() -> void:
	name = "BatteryBank"
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	custom_minimum_size = Vector2(160.0, HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_PASS
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
	_glass.draw.connect(func() -> void: Nine.paint(_glass, GLASS, _case().grow(SCREEN_MARGIN / CAPTURE_SCALE), _corner()))
	add_child(_glass)


func set_charge(v: float) -> void:
	charge = clampf(v, 0.0, 1.0)
	queue_redraw()
	_cells.queue_redraw()


## The bezel: the whole control less the terminal at its right end.
func _case() -> Rect2:
	return Rect2(Vector2.ZERO, Vector2(size.x - TERMINAL.x, size.y))


func _pane() -> Rect2:
	return _case().grow(-(SCREEN_RIM / CAPTURE_SCALE + 3.0))


func _corner() -> float:
	return (SCREEN_MARGIN + SCREEN_RIM + SCREEN_RADIUS + 2.0) * 2.0 / CAPTURE_SCALE


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
		_cells.queue_redraw()
		_glass.queue_redraw()


func _draw() -> void:
	var case_rect := _case()
	# The terminal: a gunmetal stud standing off the bezel's right end, lit along its top.
	var t := Rect2(case_rect.end.x - 1.0, (size.y - TERMINAL.y) * 0.5, TERMINAL.x + 1.0, TERMINAL.y)
	draw_rect(Rect2(t.position + Vector2(1.0, 1.5), t.size), Color(0, 0, 0, 0.45))
	draw_rect(t, TERMINAL_INK)
	draw_rect(Rect2(t.position, Vector2(t.size.x, 2.0)), Color(1, 1, 1, 0.22))
	draw_rect(Rect2(t.position + Vector2(0.0, t.size.y - 2.0), Vector2(t.size.x, 2.0)), Color(0, 0, 0, 0.3))
	Nine.paint(self, SCREEN, case_rect.grow(SCREEN_MARGIN / CAPTURE_SCALE), _corner())


func _draw_cells() -> void:
	var pane := _pane()
	var w := (pane.size.x - (CELLS - 1) * CELL_GAP) / CELLS
	var lit_cells := charge * CELLS
	for i in CELLS:
		var r := Rect2(pane.position.x + i * (w + CELL_GAP), pane.position.y, w, pane.size.y)
		_cells.draw_rect(r, Color(LIT, UNLIT_ALPHA))
		var share := clampf(lit_cells - float(i), 0.0, 1.0)
		if share <= 0.0:
			continue
		var on := Rect2(r.position, Vector2(r.size.x * share, r.size.y))
		_cells.draw_rect(on.grow(0.8), Color(LIT, 0.28))
		_cells.draw_rect(on, LIT)
		_cells.draw_rect(Rect2(on.position, Vector2(on.size.x, on.size.y * 0.35)), Color(1, 1, 1, 0.14))
