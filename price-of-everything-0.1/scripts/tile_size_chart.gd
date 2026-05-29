extends Control

signal segment_clicked(building: Dictionary)

const TILE_SIZE_CAPACITY := 200
const SOFT_CAPACITY := 100.0
const SCALE_WIDTH := 36.0
const CHART_WIDTH := 180.0
const CHART_RIGHT_INSET := 10.0
const LAND_LABEL_WIDTH := 120.0
const MIN_CHART_WIDTH_RATIO := 0.75
const LAND_LABEL_GAP := 8.0
const CONTROL_WIDTH := SCALE_WIDTH + CHART_WIDTH + LAND_LABEL_WIDTH
const MAX_CHART_HEIGHT := 500.0
const SCALE_TICK_WIDTH := 6.0
const PERCENT_LABEL_HEIGHT := 30.0
const PERCENT_FONT_SIZE := 13
const PERCENT_TOOLTIP := "Building and infrastructure tile-size use, and land owned on this tile. Exceeding 100 tile size increases building costs."
const COMPACT_VISIBLE_CAPACITY := 110.0
const COMPACT_GAP_HEIGHT := 30.0
const COMPACT_HATCH_PREVIEW_HEIGHT := 40.0
const COMPACT_ELLIPSES_FONT_SIZE := 28
const ICON_MAX_SIZE := 80.0
const ICON_PADDING := 8.0
const ICON_MIN_SEGMENT_HEIGHT := 24.0
const INFRASTRUCTURE_ROW_CAPACITY := 3
const INFRASTRUCTURE_SEGMENT_SIZE := 5.0

const FURNACE_COLOR := Color(0.78, 0.12, 0.08)
const MINE_COLOR := Color(0.08, 0.09, 0.10)
const FACTORY_COLOR := Color(0.12, 0.38, 0.70)
const POWER_COLOR := Color(1.0, 0.8, 0.0)
const INFRASTRUCTURE_COLOR := Color(0.92, 0.90, 0.82)
const DEFAULT_COLOR := Color(0.18, 0.18, 0.18)
const NAVY_TEXT_COLOR := Color(0.015, 0.06, 0.105)
const BORDER_COLOR := Color(0.7, 0.85, 1.0, 0.65)
const HOVER_BORDER_COLOR := Color(1.0, 1.0, 1.0, 0.95)
const HOVER_SHADE_COLOR := Color(1.0, 1.0, 1.0, 0.12)
const OVERFLOW_COLOR := Color(0.95, 0.1, 0.1, 0.24)
const OVERFLOW_LINE_COLOR := Color(1.0, 0.16, 0.16, 0.9)
const OVER_CAPACITY_HATCH_FILL := Color(0.95, 0.1, 0.1, 0.05)
const OVER_CAPACITY_HATCH_LINE := Color(1.0, 0.16, 0.16, 0.28)
const LAND_LINE_COLOR := Color(0.92, 0.90, 0.82, 0.95)
const LAND_LINE_SHADOW := Color(0.02, 0.025, 0.03, 0.65)
const LAND_DASH_LENGTH := 7.0
const LAND_DASH_GAP := 5.0

var _buildings: Array = []
var _segments: Array = []
var _hovered_segment_index := -1
var _pressed_segment_index := -1
var _tile_size_capacity: int = TILE_SIZE_CAPACITY
var _land_owned: int = MatchState.DEFAULT_TILE_LAND_OWNED
var _icon_cache: Dictionary = {}
var total_size_taken: float = 0.0

func _ready() -> void:
	custom_minimum_size = Vector2(CONTROL_WIDTH, MAX_CHART_HEIGHT)
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = PERCENT_TOOLTIP
	mouse_exited.connect(_on_mouse_exited)

func set_buildings(buildings: Array, tile_size_capacity: int = TILE_SIZE_CAPACITY, land_owned: int = -1) -> void:
	_buildings = buildings.duplicate()
	_tile_size_capacity = maxi(1, tile_size_capacity)
	if land_owned >= 0:
		_land_owned = maxi(0, land_owned)
	total_size_taken = 0.0
	for building in _buildings:
		total_size_taken += _building_size(building)
	queue_redraw()

func set_land_owned(land_owned: int) -> void:
	_land_owned = maxi(0, land_owned)
	queue_redraw()

func _draw() -> void:
	_segments.clear()
	var chart_rect := _chart_rect()
	var segment_rect := _segment_rect(chart_rect)
	_draw_percent_label()
	_draw_scale(chart_rect)
	_draw_over_capacity_hatching(chart_rect)
	_draw_compressed_gap(chart_rect)
	
	if size.y <= 0.0:
		return
	
	var unit_height := segment_rect.size.y / _segment_capacity()
	var current_bottom := segment_rect.end.y
	var infrastructure_buildings := _infrastructure_buildings()
	var regular_buildings := _regular_buildings()
	
	for building in regular_buildings:
		var segment_height := unit_height * _building_size(building)
		var segment_top := current_bottom - segment_height
		var visible_top := maxf(segment_rect.position.y, segment_top)
		var visible_height := current_bottom - visible_top
		
		if visible_height > 0.0:
			var rect := Rect2(Vector2(segment_rect.position.x, visible_top), Vector2(segment_rect.size.x, visible_height))
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

	for row in _infrastructure_rows(infrastructure_buildings):
		var row_size := _infrastructure_row_size(row)
		var row_height := unit_height * row_size
		var row_top := current_bottom - row_height
		var visible_top := maxf(segment_rect.position.y, row_top)
		var visible_height := current_bottom - visible_top
		if visible_height > 0.0:
			_draw_infrastructure_row(row, Rect2(
				Vector2(segment_rect.position.x, visible_top),
				Vector2(segment_rect.size.x, visible_height)
			))
		current_bottom = row_top

	_draw_land_owned_line(chart_rect)
	_draw_chart_border(chart_rect)

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

func _regular_buildings() -> Array:
	var buildings: Array = []
	for building in _buildings:
		if not _is_infrastructure_building(building):
			buildings.append(building)
	return buildings

func _infrastructure_buildings() -> Array:
	var by_internal_name := {}
	for building in _buildings:
		if not _is_infrastructure_building(building):
			continue
		var internal_name := _infrastructure_internal_name(building)
		if internal_name == "":
			continue
		by_internal_name[internal_name] = building

	var ordered: Array = []
	for group in _infrastructure_groups():
		for internal_name in group:
			if by_internal_name.has(internal_name):
				ordered.append(by_internal_name[internal_name])
	return ordered

func _infrastructure_rows(infrastructure_buildings: Array) -> Array:
	var rows: Array = []
	for group in _infrastructure_groups():
		var row: Array = []
		for internal_name in group:
			for building in infrastructure_buildings:
				if _infrastructure_internal_name(building) == internal_name:
					row.append(building)
					break
		if not row.is_empty():
			rows.append(row)
	return rows

func _infrastructure_groups() -> Array:
	return [
		["cables", "roads", "pipes"],
		["hvdc", "rails", "reinf_pipes"],
	]

func _draw_infrastructure_row(row: Array, row_rect: Rect2) -> void:
	var visible_count := mini(row.size(), INFRASTRUCTURE_ROW_CAPACITY)
	if visible_count <= 0:
		return
	var group := _infrastructure_group_for_row(row)
	var cell_width := row_rect.size.x / float(INFRASTRUCTURE_ROW_CAPACITY)
	for building in row:
		var internal_name := _infrastructure_internal_name(building)
		var slot_index := group.find(internal_name)
		if slot_index < 0:
			continue
		var rect := Rect2(
			Vector2(row_rect.position.x + (cell_width * float(slot_index)), row_rect.position.y),
			Vector2(cell_width, row_rect.size.y)
		)
		var segment_index := _segments.size()
		draw_rect(rect, INFRASTRUCTURE_COLOR, true)
		draw_rect(rect, BORDER_COLOR, false, 1.0)
		_draw_building_icon(building, rect)
		if segment_index == _hovered_segment_index and segment_index != _pressed_segment_index:
			draw_rect(rect, HOVER_SHADE_COLOR, true)
			draw_rect(rect, HOVER_BORDER_COLOR, false, 3.0)
		_segments.append({
			"rect": rect,
			"building": building,
		})

func _infrastructure_row_size(_row: Array) -> float:
	return float(INFRASTRUCTURE_ROW_CAPACITY) * INFRASTRUCTURE_SEGMENT_SIZE

func _infrastructure_group_for_row(row: Array) -> Array:
	for group in _infrastructure_groups():
		for building in row:
			if group.has(_infrastructure_internal_name(building)):
				return group
	return _infrastructure_groups()[0]

func _chart_rect() -> Rect2:
	var top_reserved := PERCENT_LABEL_HEIGHT
	var chart_height := maxf(1.0, minf(size.y, MAX_CHART_HEIGHT) - top_reserved)
	var chart_y := top_reserved
	var available_width := maxf(1.0, size.x - SCALE_WIDTH)
	var min_chart_width := available_width * MIN_CHART_WIDTH_RATIO
	var chart_width := clampf(maxf(CHART_WIDTH, min_chart_width), 1.0, available_width)
	chart_width = maxf(1.0, chart_width - CHART_RIGHT_INSET)
	return Rect2(Vector2(SCALE_WIDTH, chart_y), Vector2(chart_width, chart_height))

func _uses_compact_upper_range() -> bool:
	return _tile_size_capacity > int(COMPACT_VISIBLE_CAPACITY) and total_size_taken <= SOFT_CAPACITY and _land_owned <= int(SOFT_CAPACITY)

func _segment_rect(chart_rect: Rect2) -> Rect2:
	if not _uses_compact_upper_range():
		return chart_rect
	var segment_height := maxf(1.0, chart_rect.size.y - COMPACT_HATCH_PREVIEW_HEIGHT - COMPACT_GAP_HEIGHT)
	return Rect2(
		Vector2(chart_rect.position.x, chart_rect.position.y + COMPACT_HATCH_PREVIEW_HEIGHT + COMPACT_GAP_HEIGHT),
		Vector2(chart_rect.size.x, segment_height)
	)

func _compact_hatch_rect(chart_rect: Rect2) -> Rect2:
	return Rect2(chart_rect.position, Vector2(chart_rect.size.x, COMPACT_HATCH_PREVIEW_HEIGHT))

func _compact_gap_rect(chart_rect: Rect2) -> Rect2:
	return Rect2(
		Vector2(chart_rect.position.x, chart_rect.position.y + COMPACT_HATCH_PREVIEW_HEIGHT),
		Vector2(chart_rect.size.x, COMPACT_GAP_HEIGHT)
	)

func _segment_capacity() -> float:
	return COMPACT_VISIBLE_CAPACITY if _uses_compact_upper_range() else float(_tile_size_capacity)

func _value_to_y(value: float, chart_rect: Rect2) -> float:
	var segment_rect := _segment_rect(chart_rect)
	var ratio := clampf(value / _segment_capacity(), 0.0, 1.0)
	return segment_rect.end.y - (segment_rect.size.y * ratio)

func _draw_chart_border(chart_rect: Rect2) -> void:
	if _uses_compact_upper_range():
		draw_rect(_compact_hatch_rect(chart_rect), BORDER_COLOR, false, 1.0)
		draw_rect(_segment_rect(chart_rect), BORDER_COLOR, false, 1.0)
	else:
		draw_rect(chart_rect, BORDER_COLOR, false, 1.0)

func _draw_percent_label() -> void:
	var font := get_theme_default_font()
	var label := "%s building space | %s infra space | %d land owned" % [
		_format_size_value(_tile_size_used_by_regular_buildings()),
		_format_size_value(_tile_size_used_by_infrastructure()),
		_land_owned,
	]
	var label_pos := Vector2(0.0, PERCENT_FONT_SIZE + 2.0)
	draw_string(font, label_pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, PERCENT_FONT_SIZE, BORDER_COLOR)
	if _is_over_capacity():
		var label_width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, PERCENT_FONT_SIZE).x
		draw_string(font, Vector2(label_width + 5.0, label_pos.y), "!", HORIZONTAL_ALIGNMENT_LEFT, -1.0, PERCENT_FONT_SIZE, OVERFLOW_LINE_COLOR)

func _draw_over_capacity_hatching(chart_rect: Rect2) -> void:
	if _uses_compact_upper_range():
		_draw_hatching(_compact_hatch_rect(chart_rect))
		return
	if _tile_size_capacity <= int(SOFT_CAPACITY):
		return
	var threshold_ratio := SOFT_CAPACITY / float(_tile_size_capacity)
	var threshold_y := chart_rect.end.y - (chart_rect.size.y * threshold_ratio)
	var hatch_rect := Rect2(
		Vector2(chart_rect.position.x, chart_rect.position.y),
		Vector2(chart_rect.size.x, threshold_y - chart_rect.position.y)
	)
	_draw_hatching(hatch_rect)

func _draw_hatching(hatch_rect: Rect2) -> void:
	if hatch_rect.size.x <= 0.0 or hatch_rect.size.y <= 0.0:
		return
	draw_rect(hatch_rect, OVER_CAPACITY_HATCH_FILL, true)
	for offset in range(-int(hatch_rect.size.y), int(hatch_rect.size.x), 10):
		var start_x: float = hatch_rect.position.x + float(max(offset, 0))
		var start_y: float = hatch_rect.end.y - float(max(-offset, 0))
		var end_x: float = hatch_rect.position.x + float(min(offset + int(hatch_rect.size.y), int(hatch_rect.size.x)))
		var end_y: float = hatch_rect.position.y + float(max(offset + int(hatch_rect.size.y) - int(hatch_rect.size.x), 0))
		draw_line(Vector2(start_x, start_y), Vector2(end_x, end_y), OVER_CAPACITY_HATCH_LINE, 1.0)

func _draw_compressed_gap(chart_rect: Rect2) -> void:
	if not _uses_compact_upper_range():
		return
	var gap_rect := _compact_gap_rect(chart_rect)
	var font := get_theme_default_font()
	if font == null:
		return
	var label := "..."
	var baseline_y := gap_rect.position.y + (gap_rect.size.y * 0.5) + 3.0
	var label_pos := Vector2(
		gap_rect.position.x,
		baseline_y
	)
	draw_string(font, label_pos, label, HORIZONTAL_ALIGNMENT_CENTER, gap_rect.size.x, COMPACT_ELLIPSES_FONT_SIZE, BORDER_COLOR)

func _draw_land_owned_line(chart_rect: Rect2) -> void:
	if _tile_size_capacity <= 0:
		return
	var segment_rect := _segment_rect(chart_rect)
	var y := _value_to_y(float(_land_owned), chart_rect)
	_draw_dashed_line(Vector2(segment_rect.position.x, y), Vector2(segment_rect.end.x, y), LAND_LINE_COLOR, 2.0)
	var font := get_theme_default_font()
	var font_size := maxi(10, get_theme_default_font_size() - 1)
	var label_x := segment_rect.end.x + LAND_LABEL_GAP
	var label_width := maxf(24.0, size.x - label_x)
	var line_height := float(font_size + 2)
	var label_y := clampf(
		y - (line_height * 0.5),
		segment_rect.position.y + float(font_size),
		segment_rect.end.y - line_height
	)
	var labels: Array[String] = ["Your land", "capacity"]
	for i in labels.size():
		var line_pos := Vector2(label_x, label_y + (line_height * float(i)))
		draw_string(font, line_pos + Vector2(1.0, 1.0), labels[i], HORIZONTAL_ALIGNMENT_LEFT, label_width, font_size, LAND_LINE_SHADOW)
		draw_string(font, line_pos, labels[i], HORIZONTAL_ALIGNMENT_LEFT, label_width, font_size, LAND_LINE_COLOR)

func _draw_dashed_line(start: Vector2, end: Vector2, color: Color, width: float) -> void:
	var distance := start.distance_to(end)
	if distance <= 0.0:
		return
	var direction := (end - start).normalized()
	var cursor := 0.0
	while cursor < distance:
		var dash_end := minf(cursor + LAND_DASH_LENGTH, distance)
		draw_line(start + direction * cursor, start + direction * dash_end, color, width)
		cursor += LAND_DASH_LENGTH + LAND_DASH_GAP

func _draw_scale(chart_rect: Rect2) -> void:
	var scale_x := SCALE_WIDTH - SCALE_TICK_WIDTH
	if _uses_compact_upper_range():
		var preview_rect := _compact_hatch_rect(chart_rect)
		var segment_rect := _segment_rect(chart_rect)
		draw_line(Vector2(scale_x, preview_rect.position.y), Vector2(scale_x, preview_rect.end.y), BORDER_COLOR, 1.0)
		draw_line(Vector2(scale_x, segment_rect.position.y), Vector2(scale_x, segment_rect.end.y), BORDER_COLOR, 1.0)
		var compact_tick_step := _scale_tick_step(int(COMPACT_VISIBLE_CAPACITY))
		for value in range(0, int(SOFT_CAPACITY) + 1, compact_tick_step):
			_draw_scale_tick(value, segment_rect, scale_x, int(COMPACT_VISIBLE_CAPACITY))
		var preview_tick_step := _scale_tick_step(_tile_size_capacity)
		if _tile_size_capacity % preview_tick_step == 0:
			_draw_scale_tick(_tile_size_capacity, preview_rect, scale_x, _tile_size_capacity)
		return

	draw_line(Vector2(scale_x, chart_rect.position.y), Vector2(scale_x, chart_rect.end.y), BORDER_COLOR, 1.0)
	var tick_step := _scale_tick_step(_tile_size_capacity)
	for value in range(0, _tile_size_capacity + 1, tick_step):
		_draw_scale_tick(value, chart_rect, scale_x, _tile_size_capacity)

func _scale_tick_step(max_value: int) -> int:
	return 25 if max_value % 25 == 0 else 20

func _draw_scale_tick(value: int, chart_rect: Rect2, scale_x: float, max_value: int) -> void:
	var value_ratio := float(value) / float(maxi(1, max_value))
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
	if _is_infrastructure_building(building):
		return _infrastructure_size(building)
	var building_id: String = building.get("building_id", "")
	var building_data: Dictionary = Catalog.get_building(building_id)
	return maxf(0.0, float(building_data.get("tile_size_used", 1)))

func _tile_size_used_by_regular_buildings() -> float:
	var used := 0.0
	for building in _buildings:
		if not _is_infrastructure_building(building):
			used += _building_size(building)
	return used

func _tile_size_used_by_infrastructure() -> float:
	var used := 0.0
	for building in _buildings:
		if _is_infrastructure_building(building):
			used += _building_size(building)
	return used

func _format_size_value(value: float) -> String:
	var rounded := roundf(value)
	if is_equal_approx(value, rounded):
		return str(int(rounded))
	return "%.1f" % value

func _infrastructure_size(_building: Dictionary) -> float:
	return INFRASTRUCTURE_SEGMENT_SIZE

func _draw_building_icon(building: Dictionary, rect: Rect2) -> void:
	if rect.size.y < ICON_MIN_SEGMENT_HEIGHT:
		_draw_building_name_fallback(building, rect)
		return
	var texture := _building_icon(building)
	if texture == null:
		_draw_building_name_fallback(building, rect)
		return
	var icon_size := minf(ICON_MAX_SIZE, minf(rect.size.y - ICON_PADDING, rect.size.x - (ICON_PADDING * 2.0)))
	if icon_size <= 0.0:
		_draw_building_name_fallback(building, rect)
		return
	var icon_rect := Rect2(
		Vector2(
			rect.position.x + ((rect.size.x - icon_size) * 0.5),
			rect.position.y + ((rect.size.y - icon_size) * 0.5)
		),
		Vector2(icon_size, icon_size)
	)
	draw_texture_rect(texture, icon_rect, false)

func _draw_building_name_fallback(building: Dictionary, rect: Rect2) -> void:
	if rect.size.y < 9.0 or rect.size.x < 18.0:
		return
	var font := get_theme_default_font()
	if font == null:
		return
	var font_size := clampi(int(rect.size.y * 0.35), 8, 13)
	var label := _building_name(building).to_upper()
	var max_chars := maxi(3, int(rect.size.x / maxf(5.0, float(font_size) * 0.58)))
	if label.length() > max_chars:
		label = "%s..." % label.substr(0, maxi(1, max_chars - 3))
	var text_y := rect.position.y + ((rect.size.y + float(font_size)) * 0.5) - 2.0
	var text_pos := Vector2(rect.position.x, text_y)
	var text_color := NAVY_TEXT_COLOR if _is_infrastructure_building(building) else Color.WHITE
	var shadow_color := Color(1, 1, 1, 0.55) if _is_infrastructure_building(building) else Color(0, 0, 0, 0.78)
	draw_string(font, text_pos + Vector2(1.0, 1.0), label, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, font_size, shadow_color)
	draw_string(font, text_pos, label, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, font_size, text_color)

func _building_name(building: Dictionary) -> String:
	var building_data: Dictionary = Catalog.get_building(building.get("building_id", ""))
	return str(building_data.get("display_name", building.get("building_id", "")))

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
	return total_size_taken > SOFT_CAPACITY

func _color_for_building(building: Dictionary) -> Color:
	var building_id: String = building.get("building_id", "")
	var building_data: Dictionary = Catalog.get_building(building_id)
	var internal_name: String = building_data.get("internal_name", "")
	var category: String = building_data.get("category", "")

	if _is_power_building(building, building_data):
		return POWER_COLOR

	match internal_name:
		"furnace":
			return FURNACE_COLOR
		"mine":
			return MINE_COLOR
	if internal_name.contains("factory") or internal_name.contains("manufactory"):
		return FACTORY_COLOR
	if str(building_data.get("display_name", "")).to_lower().contains("factory"):
		return FACTORY_COLOR

	match internal_name:
		"cables", "roads", "pipes", "pipework", "rails", "reinf_pipes", "hvdc":
			return INFRASTRUCTURE_COLOR
	
	if category == "infrastructure":
		return INFRASTRUCTURE_COLOR
	
	return DEFAULT_COLOR

func _is_power_building(building: Dictionary, building_data: Dictionary) -> bool:
	if str(building_data.get("category", "")) == "power":
		return true
	var recipe: Dictionary = Catalog.get_recipe(building.get("recipe_id", ""))
	if str(recipe.get("output_name", "")) == "power":
		return true
	for output in recipe.get("outputs", []):
		if str(output.get("internal_name", "")) == "power" or str(output.get("good_id", "")) == "g_010":
			return true
	return false

func _is_infrastructure_building(building: Dictionary) -> bool:
	var internal_name := _infrastructure_internal_name(building)
	for group in _infrastructure_groups():
		if group.has(internal_name):
			return true
	return false

func _infrastructure_internal_name(building: Dictionary) -> String:
	var building_data: Dictionary = Catalog.get_building(building.get("building_id", ""))
	match str(building_data.get("internal_name", "")).strip_edges().to_lower():
		"railway", "railways":
			return "rails"
		"pipework", "pipeworks", "pipes":
			return "pipes"
		"reinforced_pipes", "reinforced_pipework", "reinforced_pipeworks":
			return "reinf_pipes"
		"hvdc":
			return "hvdc"
		_:
			return str(building_data.get("internal_name", "")).strip_edges().to_lower()
