extends RefCounted
class_name SubtileGrid

const COLUMNS := 27
const ROWS := 24
const SUBTILE_SIZE := 20
const RIVER_WIDTH := 15.0
const RIVER_BUILD_BUFFER := 3.0
const RIVER_BLOCK_RADIUS := (RIVER_WIDTH * 0.5) + RIVER_BUILD_BUFFER
const DEFAULT_LAKE_WIDTH := 200.0
const DEFAULT_LAKE_HEIGHT := 150.0
const ROAD_BUILD_BUFFER := 3.0
const CURVE_STEPS := 16
const TILE_CENTER := Vector2(270, 240)
const POINT_TENSIONS: Array[float] = [0.34, 0.22, 0.39, 0.27, 0.46]

const RIVER_POINTS := {
	"C0": Vector2(270, 240),
	"S1": Vector2(390, 120),
	"S2": Vector2(390, 360),
	"S3": Vector2(150, 360),
	"S4": Vector2(150, 120),
	"HSM1": Vector2(270, 0),
	"HSM2": Vector2(472.5, 120),
	"HSM3": Vector2(472.5, 360),
	"HSM4": Vector2(270, 480),
	"HSM5": Vector2(67.5, 360),
	"HSM6": Vector2(67.5, 120),
}

static var _report_cache: Dictionary = {}

static func total_subtile_count() -> int:
	return COLUMNS * ROWS

static func subtile_id(col: int, row: int) -> String:
	return "subtile_%d_%d" % [col, row]

static func subtile_center(col: int, row: int) -> Vector2:
	return Vector2((float(col) - 0.5) * SUBTILE_SIZE, (float(row) - 0.5) * SUBTILE_SIZE)

static func hex_polygon() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(270, 0),
		Vector2(540, 120),
		Vector2(540, 360),
		Vector2(270, 480),
		Vector2(0, 360),
		Vector2(0, 120),
	])

static func is_subtile_buildable(col: int, row: int, river_data: Dictionary = {}, road_segments: Array[Dictionary] = []) -> bool:
	if not _point_is_inside_polygon(subtile_center(col, row), hex_polygon()):
		return false
	if not river_data.is_empty() and _river_intersects_subtile(col, row, river_data):
		return false
	if not road_segments.is_empty() and _road_intersects_subtile(col, row, road_segments):
		return false
	return true

static func subtile_cells(river_data: Dictionary = {}, road_segments: Array[Dictionary] = []) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for row in range(1, ROWS + 1):
		for col in range(1, COLUMNS + 1):
			result.append({
				"id": subtile_id(col, row),
				"coord": Vector2i(col, row),
				"center": subtile_center(col, row),
				"buildable": is_subtile_buildable(col, row, river_data, road_segments),
			})
	return result

static func unbuildable_subtiles(river_data: Dictionary = {}, road_segments: Array[Dictionary] = []) -> Array[String]:
	var result: Array[String] = []
	for cell in subtile_cells(river_data, road_segments):
		if not cell["buildable"]:
			result.append(str(cell["id"]))
	return result

static func unbuildable_summary(river_data: Dictionary = {}, road_segments: Array[Dictionary] = []) -> Dictionary:
	var report: Dictionary = unbuildable_report(river_data, road_segments)
	return {
		"total_subtiles": report["total_subtiles"],
		"unbuildable_count": report["unbuildable_count"],
		"unbuildable_percent": report["unbuildable_percent"],
		"unbuildable_subtiles": report["unbuildable_subtiles"],
	}

static func format_unbuildable_by_row(river_data: Dictionary = {}, road_segments: Array[Dictionary] = []) -> String:
	var report: Dictionary = unbuildable_report(river_data, road_segments)
	return str(report["formatted_unbuildable_by_row"])

static func unbuildable_report(river_data: Dictionary = {}, road_segments: Array[Dictionary] = []) -> Dictionary:
	var cache_key: String = _cache_key_for_layout(river_data, road_segments)
	if _report_cache.has(cache_key):
		return _report_cache[cache_key]

	var unbuildable: Array[String] = []
	var row_parts: Array[String] = []
	for row in range(1, ROWS + 1):
		var ids: Array[String] = []
		for col in range(1, COLUMNS + 1):
			if not is_subtile_buildable(col, row, river_data, road_segments):
				var id: String = subtile_id(col, row)
				ids.append(id)
				unbuildable.append(id)
		if not ids.is_empty():
			row_parts.append("row_%d=[%s]" % [row, _join_strings(ids, ", ")])

	var total: int = total_subtile_count()
	var report: Dictionary = {
		"total_subtiles": total,
		"unbuildable_count": unbuildable.size(),
		"unbuildable_percent": (float(unbuildable.size()) / float(total)) * 100.0,
		"unbuildable_subtiles": unbuildable,
		"formatted_unbuildable_by_row": _join_strings(row_parts, "; "),
	}
	_report_cache[cache_key] = report
	return report

static func _cache_key_for_layout(river_data: Dictionary, road_segments: Array[Dictionary]) -> String:
	var road_key: String = ""
	for segment in road_segments:
		road_key += str(segment) + ";"
	if river_data.is_empty():
		return "base|" + road_key
	return str(river_data.get("river_type", "")) + "|" + str(river_data) + "|" + road_key

static func _river_intersects_subtile(col: int, row: int, river_data: Dictionary) -> bool:
	var rect: Rect2 = Rect2(
		Vector2(float(col - 1) * SUBTILE_SIZE, float(row - 1) * SUBTILE_SIZE),
		Vector2(SUBTILE_SIZE, SUBTILE_SIZE)
	)
	if str(river_data.get("kind", "single")) == "source" and _source_lake_intersects_rect(rect, river_data):
		return true
	var paths: Array[PackedVector2Array] = _river_paths_points(river_data)
	for path in paths:
		for i in range(path.size() - 1):
			if _segment_rect_distance(path[i], path[i + 1], rect) <= RIVER_BLOCK_RADIUS:
				return true
	return false

static func _road_intersects_subtile(col: int, row: int, road_segments: Array[Dictionary]) -> bool:
	var rect: Rect2 = Rect2(
		Vector2(float(col - 1) * SUBTILE_SIZE, float(row - 1) * SUBTILE_SIZE),
		Vector2(SUBTILE_SIZE, SUBTILE_SIZE)
	)
	for segment in road_segments:
		var start: Vector2 = segment["start"]
		var end: Vector2 = segment["end"]
		var width: float = float(segment.get("width", 6.0))
		var radius: float = (width * 0.5) + ROAD_BUILD_BUFFER
		if _segment_rect_distance(start, end, rect) <= radius:
			return true
	return false

static func _river_paths_points(river_data: Dictionary) -> Array[PackedVector2Array]:
	var kind: String = str(river_data.get("kind", "single"))
	match kind:
		"joint":
			var result: Array[PackedVector2Array] = [
				_river_path_points_for_ids([
					str(river_data["entry_hsm"]),
					str(river_data["entry_square_point"]),
					str(river_data["center_point"]),
				]),
				_river_path_points_for_ids([
					str(river_data["center_point"]),
					str(river_data["exit_square_point"]),
					str(river_data["exit_hsm"]),
				]),
			]
			var second_exit_hsm: String = str(river_data.get("exit_hsm_2", ""))
			if second_exit_hsm != "":
				result.append(_river_path_points_for_ids([
					str(river_data["center_point"]),
					str(river_data["exit_square_point_2"]),
					second_exit_hsm,
				]))
			return result
		"source":
			var lake_point_id: String = str(river_data.get("lake_point", "C0"))
			var result: Array[PackedVector2Array] = [
				_river_path_points_for_ids([
					lake_point_id,
					str(river_data["exit_square_point"]),
					str(river_data["exit_hsm"]),
				]),
			]
			var second_exit_hsm: String = str(river_data.get("exit_hsm_2", ""))
			if second_exit_hsm != "":
				result.append(_river_path_points_for_ids([
					lake_point_id,
					str(river_data["exit_square_point_2"]),
					second_exit_hsm,
				]))
			return result
		"merge":
			var result: Array[PackedVector2Array] = [
				_river_path_points_for_ids([
					str(river_data["entry_hsm"]),
					str(river_data["entry_square_point"]),
					str(river_data["center_point"]),
				]),
			]
			var second_entry_hsm: String = str(river_data.get("exit_hsm_2", ""))
			if second_entry_hsm != "":
				result.append(_river_path_points_for_ids([
					second_entry_hsm,
					str(river_data["exit_square_point_2"]),
					str(river_data["center_point"]),
				]))
			return result
		_:
			return [
				_river_path_points_for_ids([
					str(river_data["entry_hsm"]),
					str(river_data["entry_square_point"]),
					str(river_data["center_point"]),
					str(river_data["exit_square_point"]),
					str(river_data["exit_hsm"]),
				]),
			]

static func _river_path_points_for_ids(point_ids: Array[String]) -> PackedVector2Array:
	var anchors: PackedVector2Array = PackedVector2Array()
	for point_id in point_ids:
		anchors.append(_river_point(point_id))
	var tangents: Array[Vector2] = _path_tangents(anchors, point_ids)
	var path: PackedVector2Array = PackedVector2Array()
	path.append(anchors[0])
	for i in range(anchors.size() - 1):
		var segment_length: float = anchors[i].distance_to(anchors[i + 1])
		var control_a: Vector2 = anchors[i] + tangents[i] * segment_length * POINT_TENSIONS[i]
		var control_b: Vector2 = anchors[i + 1] - tangents[i + 1] * segment_length * POINT_TENSIONS[i + 1]
		for step in range(1, CURVE_STEPS + 1):
			var t: float = float(step) / float(CURVE_STEPS)
			path.append(_cubic_bezier(anchors[i], control_a, control_b, anchors[i + 1], t))
	return path

static func _source_lake_intersects_rect(rect: Rect2, river_data: Dictionary) -> bool:
	var lake_center: Vector2 = _river_point(str(river_data.get("lake_point", "C0")))
	var lake_width: float = _float_or_default(str(river_data.get("lake_width", "")), DEFAULT_LAKE_WIDTH)
	var lake_height: float = _float_or_default(str(river_data.get("lake_height", "")), DEFAULT_LAKE_HEIGHT)
	var inflated_rect: Rect2 = rect.grow(RIVER_BUILD_BUFFER)
	if inflated_rect.has_point(lake_center):
		return true
	for corner in _rect_corners(inflated_rect):
		if _point_inside_ellipse(corner, lake_center, lake_width * 0.5, lake_height * 0.5):
			return true
	return _point_inside_ellipse(inflated_rect.get_center(), lake_center, lake_width * 0.5, lake_height * 0.5)

static func _point_inside_ellipse(point: Vector2, center: Vector2, radius_x: float, radius_y: float) -> bool:
	if is_zero_approx(radius_x) or is_zero_approx(radius_y):
		return false
	var local: Vector2 = point - center
	return ((local.x * local.x) / (radius_x * radius_x)) + ((local.y * local.y) / (radius_y * radius_y)) <= 1.0

static func _float_or_default(value: String, fallback: float) -> float:
	if value == "":
		return fallback
	return float(value)

static func _river_point(point_id: String) -> Vector2:
	var local_point: Vector2 = RIVER_POINTS[point_id]
	return local_point

static func _path_tangents(points: PackedVector2Array, point_ids: Array[String]) -> Array[Vector2]:
	var tangents: Array[Vector2] = []
	for i in range(points.size()):
		if i == 0:
			if _is_hsm(point_ids[i]):
				tangents.append(-_hsm_outward_direction(point_ids[i]))
			else:
				tangents.append((points[i + 1] - points[i]).normalized())
		elif i == points.size() - 1:
			if _is_hsm(point_ids[i]):
				tangents.append(_hsm_outward_direction(point_ids[i]))
			else:
				tangents.append((points[i] - points[i - 1]).normalized())
		else:
			var tangent: Vector2 = points[i + 1] - points[i - 1]
			if tangent.is_zero_approx():
				tangent = points[i + 1] - points[i]
			tangents.append(tangent.normalized())
	return tangents

static func _is_hsm(point_id: String) -> bool:
	return point_id.begins_with("HSM")

static func _hsm_outward_direction(hsm: String) -> Vector2:
	match hsm:
		"HSM1":
			return Vector2(0, -1)
		"HSM2":
			return Vector2(240, -135).normalized()
		"HSM3":
			return Vector2(240, 135).normalized()
		"HSM4":
			return Vector2(0, 1)
		"HSM5":
			return Vector2(-240, 135).normalized()
		"HSM6":
			return Vector2(-240, -135).normalized()
		_:
			return Vector2.ZERO

static func _cubic_bezier(a: Vector2, b: Vector2, c: Vector2, d: Vector2, t: float) -> Vector2:
	var inverse_t: float = 1.0 - t
	return (
		a * inverse_t * inverse_t * inverse_t
		+ b * 3.0 * inverse_t * inverse_t * t
		+ c * 3.0 * inverse_t * t * t
		+ d * t * t * t
	)

static func _segment_rect_distance(start: Vector2, end: Vector2, rect: Rect2) -> float:
	if rect.has_point(start) or rect.has_point(end) or _segment_intersects_rect(start, end, rect):
		return 0.0
	var distance: float = minf(_point_rect_distance(start, rect), _point_rect_distance(end, rect))
	for corner in _rect_corners(rect):
		distance = minf(distance, _point_segment_distance(corner, start, end))
	return distance

static func _segment_intersects_rect(start: Vector2, end: Vector2, rect: Rect2) -> bool:
	var corners: Array[Vector2] = _rect_corners(rect)
	for i in range(corners.size()):
		var next_index: int = (i + 1) % corners.size()
		if _segments_intersect(start, end, corners[i], corners[next_index]):
			return true
	return false

static func _rect_corners(rect: Rect2) -> Array[Vector2]:
	return [
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y),
	]

static func _point_rect_distance(point: Vector2, rect: Rect2) -> float:
	var closest_x: float = clampf(point.x, rect.position.x, rect.end.x)
	var closest_y: float = clampf(point.y, rect.position.y, rect.end.y)
	return point.distance_to(Vector2(closest_x, closest_y))

static func _point_segment_distance(point: Vector2, start: Vector2, end: Vector2) -> float:
	var segment: Vector2 = end - start
	var length_squared: float = segment.length_squared()
	if is_zero_approx(length_squared):
		return point.distance_to(start)
	var t: float = clampf((point - start).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(start + segment * t)

static func _segments_intersect(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	var direction_1: float = _orientation(a, b, c)
	var direction_2: float = _orientation(a, b, d)
	var direction_3: float = _orientation(c, d, a)
	var direction_4: float = _orientation(c, d, b)
	if direction_1 * direction_2 < 0.0 and direction_3 * direction_4 < 0.0:
		return true
	return (
		_is_point_on_segment(c, a, b)
		or _is_point_on_segment(d, a, b)
		or _is_point_on_segment(a, c, d)
		or _is_point_on_segment(b, c, d)
	)

static func _orientation(a: Vector2, b: Vector2, c: Vector2) -> float:
	return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)

static func _is_point_on_segment(point: Vector2, start: Vector2, end: Vector2) -> bool:
	if not is_zero_approx(_orientation(start, end, point)):
		return false
	return (
		point.x >= minf(start.x, end.x)
		and point.x <= maxf(start.x, end.x)
		and point.y >= minf(start.y, end.y)
		and point.y <= maxf(start.y, end.y)
	)

static func _join_strings(values: Array[String], separator: String) -> String:
	var result := ""
	for i in range(values.size()):
		if i > 0:
			result += separator
		result += values[i]
	return result

static func _point_is_inside_polygon(point: Vector2, polygon: PackedVector2Array) -> bool:
	var inside := false
	var previous := polygon.size() - 1
	for current in range(polygon.size()):
		var current_point := polygon[current]
		var previous_point := polygon[previous]
		if _point_is_on_segment(point, previous_point, current_point):
			return true
		if (current_point.y > point.y) != (previous_point.y > point.y):
			var crossing_x := (previous_point.x - current_point.x) * (point.y - current_point.y) / (previous_point.y - current_point.y) + current_point.x
			if point.x < crossing_x:
				inside = not inside
		previous = current
	return inside

static func _point_is_on_segment(point: Vector2, start: Vector2, end: Vector2) -> bool:
	var cross := (point.y - start.y) * (end.x - start.x) - (point.x - start.x) * (end.y - start.y)
	if not is_zero_approx(cross):
		return false
	var dot := (point.x - start.x) * (end.x - start.x) + (point.y - start.y) * (end.y - start.y)
	if dot < 0.0:
		return false
	var length_squared := start.distance_squared_to(end)
	return dot <= length_squared
