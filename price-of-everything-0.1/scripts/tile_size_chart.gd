extends Control

signal segment_clicked(building: Dictionary)

const TILE_SIZE_CAPACITY := 10
const CHART_WIDTH := 120.0
const SCALE_WIDTH := 36.0
const CONTROL_WIDTH := 230.0
const MAX_CHART_HEIGHT := 400.0
const SCALE_TICK_WIDTH := 6.0
const PERCENT_LABEL_HEIGHT := 30.0
const OVERFLOW_HEIGHT := 20.0
const CHART_GAP := 4.0
const PERCENT_FONT_SIZE := 20
const PERCENT_TOOLTIP := "Percentage of tile space in use. Exceeding 100% increases the cost of buildings exponentially."
const ICON_MAX_SIZE := 28.0
const ICON_PADDING := 4.0
const ICON_MIN_SEGMENT_HEIGHT := 16.0

const FURNACE_COLOR := Color(0.78, 0.12, 0.08)
const MINE_COLOR := Color(0.08, 0.09, 0.10)
const INFRASTRUCTURE_COLOR := Color(0.92, 0.90, 0.82)
const DEFAULT_COLOR := Color(0, 0, 0, 0)
const BORDER_COLOR := Color(0.7, 0.85, 1.0, 0.65)
const HOVER_BORDER_COLOR := Color(1.0, 1.0, 1.0, 0.95)
const HOVER_SHADE_COLOR := Color(1.0, 1.0, 1.0, 0.12)
const OVERFLOW_COLOR := Color(0.95, 0.1, 0.1, 0.24)
const OVERFLOW_LINE_COLOR := Color(1.0, 0.16, 0.16, 0.9)

var _buildings: Array = []
var _segments: Array = []
var _hovered_segment_index := -1
var _pressed_segment_index := -1
var _tile_size_capacity: int = TILE_SIZE_CAPACITY
var _icon_cache: Dictionary = {}
var total_size_taken: float = 0.0

func _ready() -> void:
	custom_minimum_size = Vector2(CONTROL_WIDTH, MAX_CHART_HEIGHT)
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = PERCENT_TOOLTIP
	mouse_exited.connect(_on_mouse_exited)

func set_buildings(buildings: Array, tile_size_capacity: int = TILE_SIZE_CAPACITY) -> void:
	_buildings = buildings.duplicate()
	_tile_size_capacity = maxi(1, tile_size_capacity)
	total_size_taken = 0.0
	for building in _buildings:
		total_size_taken += _building_size(building)
	queue_redraw()

func _draw() -> void:
	_segments.clear()
	var chart_rect := _chart_rect()
	_draw_percent_label()
	_draw_overflow_strip()
	_draw_scale(chart_rect)
	draw_rect(chart_rect, BORDER_COLOR, false, 1.0)
	
	if size.y <= 0.0:
		return
	
	var unit_height := chart_rect.size.y / float(_tile_size_capacity)
	var current_bottom := chart_rect.end.y
	
	for building in _buildings:
		var segment_height := unit_height * _building_size(building)
		var segment_top := current_bottom - segment_height
		var visible_top := maxf(chart_rect.position.y, segment_top)
		var visible_height := current_bottom - visible_top
		
		if visible_height > 0.0:
			var rect := Rect2(Vector2(chart_rect.position.x, visible_top), Vector2(CHART_WIDTH, visible_height))
			var color := _color_for_building(building)
			var segment_index := _segments.size()
			if color.a > 0.0:
				draw_rect(rect, color, true)
				draw_rect(rect, BORDER_COLOR, false, 1.0)
			_draw_building_icon(building, rect)
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
	tooltip_text = PERCENT_TOOLTIP
	if _hovered_segment_index != -1:
		var segment: Dictionary = _segments[_hovered_segment_index]
		var building: Dictionary = segment.building
		tooltip_text = building.get("display_label", building.get("building_id", ""))
	queue_redraw()

func _on_mouse_exited() -> void:
	_hovered_segment_index = -1
	_pressed_segment_index = -1
	tooltip_text = PERCENT_TOOLTIP
	queue_redraw()

func _chart_rect() -> Rect2:
	var top_reserved := PERCENT_LABEL_HEIGHT
	if _is_over_capacity():
		top_reserved += OVERFLOW_HEIGHT + CHART_GAP
	var chart_height := maxf(1.0, minf(size.y, MAX_CHART_HEIGHT) - top_reserved)
	var chart_y := top_reserved
	return Rect2(Vector2(SCALE_WIDTH, chart_y), Vector2(CHART_WIDTH, chart_height))

func _draw_percent_label() -> void:
	var font := get_theme_default_font()
	var percent := roundi((total_size_taken / float(_tile_size_capacity)) * 100.0)
	var label := "%d%% tile space used" % percent
	var label_pos := Vector2(0.0, PERCENT_FONT_SIZE + 2.0)
	draw_string(font, label_pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, PERCENT_FONT_SIZE, BORDER_COLOR)
	if _is_over_capacity():
		var label_width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, PERCENT_FONT_SIZE).x
		draw_string(font, Vector2(label_width + 5.0, label_pos.y), "!", HORIZONTAL_ALIGNMENT_LEFT, -1.0, PERCENT_FONT_SIZE, OVERFLOW_LINE_COLOR)

func _draw_overflow_strip() -> void:
	if not _is_over_capacity():
		return
	var strip_rect := Rect2(Vector2(SCALE_WIDTH, PERCENT_LABEL_HEIGHT), Vector2(CHART_WIDTH, OVERFLOW_HEIGHT))
	draw_rect(strip_rect, OVERFLOW_COLOR, true)
	for offset in range(-int(OVERFLOW_HEIGHT), int(strip_rect.size.x), 8):
		var start_x: float = strip_rect.position.x + float(max(offset, 0))
		var start_y: float = strip_rect.end.y - float(max(-offset, 0))
		var end_x: float = strip_rect.position.x + float(min(offset + int(OVERFLOW_HEIGHT), int(strip_rect.size.x)))
		var end_y: float = strip_rect.position.y + float(max(offset + int(OVERFLOW_HEIGHT) - int(strip_rect.size.x), 0))
		draw_line(Vector2(start_x, start_y), Vector2(end_x, end_y), OVERFLOW_LINE_COLOR, 1.0)
	draw_rect(strip_rect, OVERFLOW_LINE_COLOR, false, 1.0)
	
	var font := get_theme_default_font()
	var font_size := get_theme_default_font_size()
	var label := "See All"
	var label_width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	var label_pos := Vector2(strip_rect.position.x + ((strip_rect.size.x - label_width) * 0.5), strip_rect.position.y + font_size + 2.0)
	draw_string(font, label_pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, OVERFLOW_LINE_COLOR)

func _draw_scale(chart_rect: Rect2) -> void:
	var scale_x := SCALE_WIDTH - SCALE_TICK_WIDTH
	draw_line(Vector2(scale_x, chart_rect.position.y), Vector2(scale_x, chart_rect.end.y), BORDER_COLOR, 1.0)
	
	var tick_step := maxi(1, ceili(float(_tile_size_capacity) / 10.0))
	for value in range(0, _tile_size_capacity + 1, tick_step):
		_draw_scale_tick(value, chart_rect, scale_x)
	if _tile_size_capacity % tick_step != 0:
		_draw_scale_tick(_tile_size_capacity, chart_rect, scale_x)

func _draw_scale_tick(value: int, chart_rect: Rect2, scale_x: float) -> void:
	var value_ratio := float(value) / float(_tile_size_capacity)
	var y := chart_rect.end.y - (chart_rect.size.y * value_ratio)
	draw_line(Vector2(scale_x, y), Vector2(SCALE_WIDTH, y), BORDER_COLOR, 1.0)
	
	var font := get_theme_default_font()
	var font_size := get_theme_default_font_size()
	var label := str(value)
	var label_width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	var label_y := clampf(y + (font_size * 0.35), chart_rect.position.y + font_size, chart_rect.end.y - 2.0)
	var label_pos := Vector2(maxf(0.0, scale_x - label_width - 4.0), label_y)
	draw_string(font, label_pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, BORDER_COLOR)

func _building_size(building: Dictionary) -> float:
	var building_id: String = building.get("building_id", "")
	var building_data: Dictionary = Catalog.get_building(building_id)
	return maxf(0.0, float(building_data.get("tile_size_used", 1)))

func _draw_building_icon(building: Dictionary, rect: Rect2) -> void:
	if rect.size.y < ICON_MIN_SEGMENT_HEIGHT:
		return
	var texture := _building_icon(building)
	if texture == null:
		return
	var icon_size := minf(ICON_MAX_SIZE, minf(rect.size.y - ICON_PADDING, rect.size.x - (ICON_PADDING * 2.0)))
	if icon_size <= 0.0:
		return
	var icon_rect := Rect2(
		Vector2(
			rect.position.x + ((rect.size.x - icon_size) * 0.5),
			rect.position.y + ((rect.size.y - icon_size) * 0.5)
		),
		Vector2(icon_size, icon_size)
	)
	draw_texture_rect(texture, icon_rect, false)

func _building_icon(building: Dictionary) -> Texture2D:
	var building_id: String = building.get("building_id", "")
	if building_id == "":
		return null
	if _icon_cache.has(building_id):
		return _icon_cache[building_id] as Texture2D
	var building_data: Dictionary = Catalog.get_building(building_id)
	var internal_name: String = building_data.get("internal_name", "")
	var icon_paths: Array = []
	if internal_name != "":
		icon_paths.append("res://assets/icons/buildings/%s_%s.png" % [building_id, internal_name])
		icon_paths.append("res://assets/icons/buildings/%s_%s.PNG" % [building_id, internal_name])
	icon_paths.append("res://assets/icons/buildings/%s.png" % building_id)
	icon_paths.append("res://assets/icons/buildings/%s.PNG" % building_id)
	if internal_name != "":
		icon_paths.append("res://assets/icons/buildings/%s.png" % internal_name)
		icon_paths.append("res://assets/icons/buildings/%s.PNG" % internal_name)
	for icon_path in icon_paths:
		if ResourceLoader.exists(icon_path):
			var texture := load(icon_path) as Texture2D
			_icon_cache[building_id] = texture
			return texture
	_icon_cache[building_id] = null
	return null

func _is_over_capacity() -> bool:
	return total_size_taken > float(_tile_size_capacity)

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
