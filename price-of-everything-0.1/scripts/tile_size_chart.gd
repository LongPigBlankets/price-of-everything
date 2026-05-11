extends Control

signal segment_clicked(building: Dictionary)

const TILE_SIZE_CAPACITY := 10
const BUILDING_SIZE := 1
const CHART_WIDTH := 120.0

const FURNACE_COLOR := Color(0.78, 0.12, 0.08)
const MINE_COLOR := Color(0.08, 0.09, 0.10)
const INFRASTRUCTURE_COLOR := Color(0.92, 0.90, 0.82)
const DEFAULT_COLOR := Color(0, 0, 0, 0)
const BORDER_COLOR := Color(0.7, 0.85, 1.0, 0.65)
const HOVER_BORDER_COLOR := Color(1.0, 1.0, 1.0, 0.95)
const HOVER_SHADE_COLOR := Color(1.0, 1.0, 1.0, 0.12)

var _buildings: Array = []
var _segments: Array = []
var _hovered_segment_index := -1
var _pressed_segment_index := -1
var total_size_taken: int = 0

func _ready() -> void:
	custom_minimum_size = Vector2(CHART_WIDTH, custom_minimum_size.y)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_exited.connect(_on_mouse_exited)

func set_buildings(buildings: Array) -> void:
	_buildings = buildings.duplicate()
	total_size_taken = _buildings.size() * BUILDING_SIZE
	queue_redraw()

func _draw() -> void:
	_segments.clear()
	var chart_rect := Rect2(Vector2.ZERO, Vector2(CHART_WIDTH, size.y))
	draw_rect(chart_rect, BORDER_COLOR, false, 1.0)
	
	if size.y <= 0.0:
		return
	
	var unit_height := size.y / float(TILE_SIZE_CAPACITY)
	var current_bottom := size.y
	
	for building in _buildings:
		var segment_height := unit_height * BUILDING_SIZE
		var segment_top := current_bottom - segment_height
		var visible_top := maxf(0.0, segment_top)
		var visible_height := current_bottom - visible_top
		
		if visible_height > 0.0:
			var rect := Rect2(Vector2(0.0, visible_top), Vector2(CHART_WIDTH, visible_height))
			var color := _color_for_building(building)
			var segment_index := _segments.size()
			if color.a > 0.0:
				draw_rect(rect, color, true)
				draw_rect(rect, BORDER_COLOR, false, 1.0)
			if segment_index == _hovered_segment_index and segment_index != _pressed_segment_index:
				draw_rect(rect, HOVER_SHADE_COLOR, true)
				draw_rect(rect, HOVER_BORDER_COLOR, false, 3.0)
			_segments.append({
				"rect": rect,
				"building": building,
			})
		
		current_bottom = segment_top

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_set_hovered_segment(_segment_index_at(event.position))
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var segment_index := _segment_index_at(event.position)
			if segment_index == -1:
				return
			_pressed_segment_index = segment_index
			queue_redraw()
			var segment: Dictionary = _segments[segment_index]
			segment_clicked.emit(segment.building)
			accept_event()
		else:
			_pressed_segment_index = -1
			_set_hovered_segment(_segment_index_at(event.position))
			accept_event()

func _segment_index_at(position: Vector2) -> int:
	for i in range(_segments.size() - 1, -1, -1):
		var segment: Dictionary = _segments[i]
		var rect: Rect2 = segment.rect
		if rect.has_point(position):
			return i
	return -1

func _set_hovered_segment(segment_index: int) -> void:
	if _hovered_segment_index == segment_index:
		return
	_hovered_segment_index = segment_index
	queue_redraw()

func _on_mouse_exited() -> void:
	_hovered_segment_index = -1
	_pressed_segment_index = -1
	queue_redraw()

func _color_for_building(building: Dictionary) -> Color:
	var building_id: String = building.get("building_id", "")
	var building_data: Dictionary = Catalog.get_building(building_id)
	var internal_name: String = building_data.get("internal_name", "")
	var category: String = building_data.get("category", "")
	
	match internal_name:
		"furnace":
			return FURNACE_COLOR
		"mine":
			return MINE_COLOR
		"cables", "roads", "pipework":
			return INFRASTRUCTURE_COLOR
	
	if category == "infrastructure":
		return INFRASTRUCTURE_COLOR
	
	return DEFAULT_COLOR
