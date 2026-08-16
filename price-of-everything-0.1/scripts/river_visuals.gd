extends Node2D

const RIVER_PROPERTIES_PATH := "res://data/river_properties.csv"
## River blue lives in MapStyle (river_color — same hue as lakes/shelf so all
## water reads as one; the 'toggle ink' cheat swaps it).
const RIVER_WIDTH := 15.0
const RIVER_MOUTH_WIDTH := 25.0
const CURVE_STEPS := 16
const TILE_CENTER := Vector2(270, 240)
const POINT_TENSIONS: Array[float] = [0.34, 0.22, 0.39, 0.27, 0.46]
const MOUTH_EXIT_EXTENSION := 18.0
const DEFAULT_LAKE_WIDTH := 200.0
const DEFAULT_LAKE_HEIGHT := 150.0
const LAKE_SHAPE_STEPS := 32

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

@onready var terrain_layer: HexMap = %TerrainLayer

var river_properties := {}
## Which draw pass is running: 1 = water (always); 0 = ink bank casing, drawn
## first across the WHOLE map in ink mode — casing must finish everywhere
## before any blue goes down, or tile-seam joints blotch dark over the
## neighbouring path's water.
var _pass := 1

func _ready() -> void:
	river_properties = _load_river_properties()
	MapStyle.style_changed.connect(queue_redraw)
	queue_redraw()

func _draw() -> void:
	if terrain_layer == null:
		return

	var passes: Array = [0, 1] if MapStyle.uses_ink_linework() else [1]
	for p in passes:
		_pass = p
		for coord in terrain_layer.tiles:
			var tile_data: Dictionary = terrain_layer.tiles[coord]
			if not tile_data.get("has_river", false):
				continue
			var river_type: String = str(tile_data.get("river_type", ""))
			if river_type == "" or not river_properties.has(river_type):
				continue
			var river_data: Dictionary = river_properties[river_type]
			_draw_tile_river(coord, river_data)

## Returns every river path as a world-space, sampled polyline along the exact
## same routes the river is drawn on (one entry per path; tiles with joints/merges
## yield several). Each entry is {coord: Vector2i, points: PackedVector2Array}.
## Used by the Survey overlay to redraw rivers as hand-drawn cartographer lines.
func get_river_polylines() -> Array:
	var out: Array = []
	if terrain_layer == null:
		return out
	for coord in terrain_layer.tiles:
		var tile_data: Dictionary = terrain_layer.tiles[coord]
		if not tile_data.get("has_river", false):
			continue
		var river_type: String = str(tile_data.get("river_type", ""))
		if river_type == "" or not river_properties.has(river_type):
			continue
		var river_data: Dictionary = river_properties[river_type]
		var center: Vector2 = terrain_layer.map_to_local(terrain_layer.map_coord_for_tile_coord(coord))
		for record_value in _river_path_records_for_tile(coord, center, river_data):
			var record: Dictionary = record_value
			out.append({
				"coord": coord,
				"points": (record.points as PackedVector2Array).duplicate(),
				"start_width": float(record.start_width),
				"end_width": float(record.end_width),
			})
	return out

## Continuous draw-only water mask for SettlementPlan. It is built from the
## exact sampled paths and renderer widths above, not NavGrid cells. Round
## joins/caps are unioned across every path whose buffered geometry intersects
## the authored settlement extent, so adjacent non-urban river tiles and
## branches cannot leave cracks at their shared endpoints.
func get_water_exclusion_geometry(extent_polygons: Array,
		building_bank_clearance: float = 4.0) -> Dictionary:
	var raw_polys: Array = []
	var selected_paths: Array = []
	var selected_lakes: Array = []
	var casing_extra := MapStyle.river_casing_extra()
	for path_value in get_river_polylines():
		var path: Dictionary = path_value
		var points: PackedVector2Array = path.points
		if points.size() < 2:
			continue
		var rendered_width := maxf(float(path.start_width), float(path.end_width))
		var half_width := (rendered_width + casing_extra) * 0.5 + building_bank_clearance
		var buffered := Geometry2D.offset_polyline(points, half_width,
			Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND)
		var intersects := false
		for poly_value in buffered:
			var poly: PackedVector2Array = poly_value
			if _water_poly_intersects_extents(poly, extent_polygons):
				intersects = true
				raw_polys.append(poly)
		if intersects:
			selected_paths.append({
				"coord": path.coord,
				"points": points.duplicate(),
				"rendered_width": rendered_width,
				"exclusion_half_width": half_width,
			})

	# Source lakes are procedurally drawn by this renderer; use the same bean
	# vertices and add shore/clearance outside their visible edge.
	if terrain_layer != null:
		for coord in terrain_layer.tiles:
			var tile_data: Dictionary = terrain_layer.tiles[coord]
			if not tile_data.get("has_river", false):
				continue
			var river_type := str(tile_data.get("river_type", ""))
			if not river_properties.has(river_type):
				continue
			var river_data: Dictionary = river_properties[river_type]
			if str(river_data.get("kind", "")) != "source":
				continue
			var center: Vector2 = terrain_layer.map_to_local(
				terrain_layer.map_coord_for_tile_coord(coord))
			var lake_center := _river_point(center, str(river_data.get("lake_point", "C0")))
			var lake_width := _float_or_default(str(river_data.get("lake_width", "")),
				DEFAULT_LAKE_WIDTH)
			var lake_height := _float_or_default(str(river_data.get("lake_height", "")),
				DEFAULT_LAKE_HEIGHT)
			var lake := _bean_lake_points(lake_center, lake_width, lake_height, river_type)
			_append_plan_lake(lake, "river-source|%s" % river_type,
				building_bank_clearance, extent_polygons, raw_polys, selected_lakes)

	# Baked inland lakes share HillVisuals' exact visible polygons. They are
	# independent of river-tile ownership and therefore catch water entering an
	# authored plan from a non-urban source.
	var baked_lakes: Array = HillBaked.lakes()
	for i in baked_lakes.size():
		_append_plan_lake(baked_lakes[i] as PackedVector2Array,
			"baked-lake|%d" % i, building_bank_clearance,
			extent_polygons, raw_polys, selected_lakes)

	var merged := _merge_water_polys(raw_polys)
	var exclusions: Array = []
	for i in merged.size():
		var poly: PackedVector2Array = merged[i]
		exclusions.append({"key": "water-exclusion|%d" % i,
			"poly": poly, "bb": _water_bbox(poly)})
	var uncovered_joins := _uncovered_river_joins(selected_paths, exclusions)
	return {
		"polygons": exclusions,
		"paths": selected_paths,
		"lakes": selected_lakes,
		"building_bank_clearance": building_bank_clearance,
		"river_casing_extra": casing_extra,
		"uncovered_river_join_count": uncovered_joins,
	}

func _append_plan_lake(lake: PackedVector2Array, key: String, clearance: float,
		extents: Array, raw_polys: Array, selected_lakes: Array) -> void:
	if lake.size() < 3:
		return
	var ccw := lake.duplicate()
	if Geometry2D.is_polygon_clockwise(ccw):
		ccw.reverse()
	var expanded := Geometry2D.offset_polygon(ccw,
		MapStyle.lake_shore_width() * 0.5 + clearance, Geometry2D.JOIN_ROUND)
	for poly_value in expanded:
		var poly: PackedVector2Array = poly_value
		if not _water_poly_intersects_extents(poly, extents):
			continue
		raw_polys.append(poly)
		selected_lakes.append({"key": key, "poly": lake.duplicate(),
			"exclusion_poly": poly.duplicate()})

func _water_poly_intersects_extents(poly: PackedVector2Array, extents: Array) -> bool:
	var bb := _water_bbox(poly)
	for extent_value in extents:
		var extent: PackedVector2Array = extent_value
		if extent.size() < 3 or not bb.intersects(_water_bbox(extent)):
			continue
		if not Geometry2D.intersect_polygons(poly, extent).is_empty():
			return true
		if Geometry2D.is_point_in_polygon(poly[0], extent):
			return true
		if Geometry2D.is_point_in_polygon(extent[0], poly):
			return true
	return false

func _merge_water_polys(polys: Array) -> Array:
	var merged: Array = []
	for poly_value in polys:
		var pending: PackedVector2Array = poly_value
		var i := 0
		while i < merged.size():
			var unions := Geometry2D.merge_polygons(merged[i], pending)
			if unions.size() == 1:
				pending = unions[0]
				merged.remove_at(i)
				i = 0
			else:
				i += 1
		merged.append(pending)
	return merged

func _uncovered_river_joins(paths: Array, exclusions: Array) -> int:
	var joins: Array = []
	for path_value in paths:
		var points: PackedVector2Array = (path_value as Dictionary).points
		if points.size() >= 2:
			joins.append(points[0])
			joins.append(points[points.size() - 1])
	var uncovered := 0
	for i in joins.size():
		var shared := false
		for j in joins.size():
			if i != j and (joins[i] as Vector2).distance_to(joins[j]) <= 0.25:
				shared = true
				break
		if shared and not _point_in_water_exclusions(joins[i], exclusions):
			uncovered += 1
	return uncovered

func _point_in_water_exclusions(point: Vector2, exclusions: Array) -> bool:
	for exclusion_value in exclusions:
		var exclusion: Dictionary = exclusion_value
		if exclusion.bb.has_point(point) and Geometry2D.is_point_in_polygon(point,
				exclusion.poly):
			return true
	return false

func _water_bbox(poly: PackedVector2Array) -> Rect2:
	var lo := poly[0]
	var hi := poly[0]
	for point in poly:
		lo = lo.min(point)
		hi = hi.max(point)
	return Rect2(lo, hi - lo)

# The list of point-id sequences (with mouth flags) the river follows on a tile,
# mirroring the _draw_* dispatch, returned as sampled world-space polylines.
func _river_paths_for_tile(tile_coord: Vector2i, center: Vector2, river_data: Dictionary) -> Array:
	var paths: Array = []
	for record_value in _river_path_records_for_tile(tile_coord, center, river_data):
		paths.append((record_value as Dictionary).points)
	return paths

func _river_path_records_for_tile(tile_coord: Vector2i, center: Vector2,
		river_data: Dictionary) -> Array:
	var paths: Array = []
	var kind: String = str(river_data.get("kind", "single"))
	match kind:
		"joint":
			paths.append(_sampled_record(center, [str(river_data["entry_hsm"]), str(river_data["entry_square_point"]), str(river_data["center_point"])], false))
			paths.append(_sampled_record(center, [str(river_data["center_point"]), str(river_data["exit_square_point"]), str(river_data["exit_hsm"])], _exit_meets_sea(tile_coord, str(river_data["exit_hsm"]))))
			var jx2: String = str(river_data.get("exit_hsm_2", ""))
			if jx2 != "":
				paths.append(_sampled_record(center, [str(river_data["center_point"]), str(river_data["exit_square_point_2"]), jx2], _exit_meets_sea(tile_coord, jx2)))
		"source":
			var lake_id: String = str(river_data.get("lake_point", "C0"))
			paths.append(_sampled_record(center, [lake_id, str(river_data["exit_square_point"]), str(river_data["exit_hsm"])], _exit_meets_sea(tile_coord, str(river_data["exit_hsm"]))))
			var sx2: String = str(river_data.get("exit_hsm_2", ""))
			if sx2 != "":
				paths.append(_sampled_record(center, [lake_id, str(river_data["exit_square_point_2"]), sx2], _exit_meets_sea(tile_coord, sx2)))
		"merge":
			paths.append(_sampled_record(center, [str(river_data["entry_hsm"]), str(river_data["entry_square_point"]), str(river_data["center_point"])], false))
			var mx2: String = str(river_data.get("exit_hsm_2", ""))
			if mx2 != "":
				paths.append(_sampled_record(center, [mx2, str(river_data["exit_square_point_2"]), str(river_data["center_point"])], false))
		_:
			paths.append(_sampled_record(center, [str(river_data["entry_hsm"]), str(river_data["entry_square_point"]), str(river_data["center_point"]), str(river_data["exit_square_point"]), str(river_data["exit_hsm"])], _exit_meets_sea(tile_coord, str(river_data["exit_hsm"]))))
	return paths

func _sampled_record(center: Vector2, point_ids: Array,
		has_river_mouth: bool) -> Dictionary:
	return {
		"points": _sampled_ids(center, point_ids, has_river_mouth),
		"start_width": RIVER_WIDTH,
		"end_width": RIVER_MOUTH_WIDTH if has_river_mouth else RIVER_WIDTH,
	}

func _sampled_ids(center: Vector2, point_ids: Array, has_river_mouth: bool) -> PackedVector2Array:
	var ids: Array[String] = []
	var points := PackedVector2Array()
	for pid in point_ids:
		ids.append(str(pid))
		points.append(_river_point(center, str(pid)))
	var draw_points := PackedVector2Array(points)
	if has_river_mouth:
		var li := draw_points.size() - 1
		draw_points[li] = draw_points[li] + _hsm_outward_direction(ids[li]) * MOUTH_EXIT_EXTENSION
	var tangents: Array[Vector2] = _path_tangents(draw_points, ids)
	var out := PackedVector2Array()
	for i in range(draw_points.size() - 1):
		var seg_len: float = draw_points[i].distance_to(draw_points[i + 1])
		var ca: Vector2 = draw_points[i] + tangents[i] * seg_len * POINT_TENSIONS[i]
		var cb: Vector2 = draw_points[i + 1] - tangents[i + 1] * seg_len * POINT_TENSIONS[i + 1]
		var first_step := 0 if i == 0 else 1
		for step in range(first_step, CURVE_STEPS + 1):
			out.append(_cubic_bezier(draw_points[i], ca, cb, draw_points[i + 1], float(step) / float(CURVE_STEPS)))
	return out

func _draw_tile_river(tile_coord: Vector2i, river_data: Dictionary) -> void:
	var center: Vector2 = terrain_layer.map_to_local(terrain_layer.map_coord_for_tile_coord(tile_coord))
	var kind: String = str(river_data.get("kind", "single"))
	match kind:
		"joint":
			_draw_joint_river(tile_coord, center, river_data)
		"source":
			_draw_source_river(tile_coord, center, river_data)
		"merge":
			_draw_merge_river(center, river_data)
		_:
			_draw_single_river(tile_coord, center, river_data)

func _draw_single_river(tile_coord: Vector2i, center: Vector2, river_data: Dictionary) -> void:
	var point_ids: Array[String] = [
		str(river_data["entry_hsm"]),
		str(river_data["entry_square_point"]),
		str(river_data["center_point"]),
		str(river_data["exit_square_point"]),
		str(river_data["exit_hsm"]),
	]
	var points := PackedVector2Array([
		_river_point(center, point_ids[0]),
		_river_point(center, point_ids[1]),
		_river_point(center, point_ids[2]),
		_river_point(center, point_ids[3]),
		_river_point(center, point_ids[4]),
	])
	var exit_hsm: String = str(river_data["exit_hsm"])
	var has_river_mouth: bool = _exit_meets_sea(tile_coord, exit_hsm)
	_draw_curved_river_path(points, point_ids, has_river_mouth)

func _draw_joint_river(tile_coord: Vector2i, center: Vector2, river_data: Dictionary) -> void:
	var entry_point_ids: Array[String] = [
		str(river_data["entry_hsm"]),
		str(river_data["entry_square_point"]),
		str(river_data["center_point"]),
	]
	_draw_path_for_ids(center, entry_point_ids, false)

	var exit_point_ids: Array[String] = [
		str(river_data["center_point"]),
		str(river_data["exit_square_point"]),
		str(river_data["exit_hsm"]),
	]
	_draw_path_for_ids(center, exit_point_ids, _exit_meets_sea(tile_coord, exit_point_ids[2]))

	var second_exit_hsm: String = str(river_data.get("exit_hsm_2", ""))
	if second_exit_hsm != "":
		var second_exit_point_ids: Array[String] = [
			str(river_data["center_point"]),
			str(river_data["exit_square_point_2"]),
			second_exit_hsm,
		]
		_draw_path_for_ids(center, second_exit_point_ids, _exit_meets_sea(tile_coord, second_exit_hsm))

func _draw_source_river(tile_coord: Vector2i, center: Vector2, river_data: Dictionary) -> void:
	var lake_point_id: String = str(river_data.get("lake_point", "C0"))
	var lake_center: Vector2 = _river_point(center, lake_point_id)
	var lake_width: float = _float_or_default(str(river_data.get("lake_width", "")), DEFAULT_LAKE_WIDTH)
	var lake_height: float = _float_or_default(str(river_data.get("lake_height", "")), DEFAULT_LAKE_HEIGHT)
	_draw_bean_lake(lake_center, lake_width, lake_height, str(river_data["river_type"]))

	var exit_hsm: String = str(river_data["exit_hsm"])
	var exit_point_ids: Array[String] = [
		lake_point_id,
		str(river_data["exit_square_point"]),
		exit_hsm,
	]
	_draw_path_for_ids(center, exit_point_ids, _exit_meets_sea(tile_coord, exit_hsm))

	var second_exit_hsm: String = str(river_data.get("exit_hsm_2", ""))
	if second_exit_hsm != "":
		var second_exit_point_ids: Array[String] = [
			lake_point_id,
			str(river_data["exit_square_point_2"]),
			second_exit_hsm,
		]
		_draw_path_for_ids(center, second_exit_point_ids, _exit_meets_sea(tile_coord, second_exit_hsm))

func _draw_merge_river(center: Vector2, river_data: Dictionary) -> void:
	var entry_point_ids: Array[String] = [
		str(river_data["entry_hsm"]),
		str(river_data["entry_square_point"]),
		str(river_data["center_point"]),
	]
	_draw_path_for_ids(center, entry_point_ids, false)

	var second_entry_hsm: String = str(river_data.get("exit_hsm_2", ""))
	if second_entry_hsm != "":
		var second_entry_point_ids: Array[String] = [
			second_entry_hsm,
			str(river_data["exit_square_point_2"]),
			str(river_data["center_point"]),
		]
		_draw_path_for_ids(center, second_entry_point_ids, false)

func _draw_path_for_ids(center: Vector2, point_ids: Array[String], has_river_mouth: bool) -> void:
	var points := PackedVector2Array()
	for point_id in point_ids:
		points.append(_river_point(center, point_id))
	_draw_curved_river_path(points, point_ids, has_river_mouth)

func _river_point(tile_center: Vector2, point_id: String) -> Vector2:
	var local_point: Vector2 = RIVER_POINTS[point_id]
	return tile_center + local_point - TILE_CENTER

func _draw_curved_river_path(points: PackedVector2Array, point_ids: Array[String], has_river_mouth: bool) -> void:
	var draw_points: PackedVector2Array = PackedVector2Array(points)
	if has_river_mouth:
		var last_index := draw_points.size() - 1
		draw_points[last_index] = draw_points[last_index] + _hsm_outward_direction(point_ids[point_ids.size() - 1]) * MOUTH_EXIT_EXTENSION

	var tangents: Array[Vector2] = _path_tangents(draw_points, point_ids)
	for i in range(draw_points.size() - 1):
		var start_width: float = RIVER_WIDTH
		var end_width: float = RIVER_MOUTH_WIDTH if has_river_mouth and i == draw_points.size() - 2 else RIVER_WIDTH
		_draw_cubic_segment(
			draw_points[i],
			draw_points[i + 1],
			tangents[i],
			tangents[i + 1],
			POINT_TENSIONS[i],
			POINT_TENSIONS[i + 1],
			start_width,
			end_width
		)

func _path_tangents(points: PackedVector2Array, point_ids: Array[String]) -> Array[Vector2]:
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

func _draw_bean_lake(center: Vector2, width: float, height: float, seed_text: String) -> void:
	if _pass == 0:
		return   # lakes draw fill + shore in the water pass (no casing needed)
	var points := _bean_lake_points(center, width, height, seed_text)
	draw_colored_polygon(points, MapStyle.river_color())
	if MapStyle.uses_ink_linework():
		var shore := points.duplicate()
		shore.append(shore[0])
		draw_polyline(shore, MapStyle.lake_shore_color(MapStyle.river_color()), MapStyle.lake_shore_width(), true)

func _bean_lake_points(center: Vector2, width: float, height: float,
		seed_text: String) -> PackedVector2Array:
	var points := PackedVector2Array()
	var phase: float = float(abs(hash(seed_text)) % 628) / 100.0
	for step in range(LAKE_SHAPE_STEPS):
		var angle: float = TAU * float(step) / float(LAKE_SHAPE_STEPS)
		var radius_x: float = width * 0.5 * (1.0 + 0.08 * sin(angle * 3.0 + phase))
		var radius_y: float = height * 0.5 * (1.0 + 0.10 * cos(angle * 2.0 + phase))
		points.append(center + Vector2(cos(angle) * radius_x, sin(angle) * radius_y))
	return points

func _draw_cubic_segment(
	start: Vector2,
	end: Vector2,
	start_tangent: Vector2,
	end_tangent: Vector2,
	start_tension: float,
	end_tension: float,
	start_width: float,
	end_width: float
) -> void:
	var segment_length: float = start.distance_to(end)
	var control_a: Vector2 = start + start_tangent * segment_length * start_tension
	var control_b: Vector2 = end - end_tangent * segment_length * end_tension
	var previous: Vector2 = start

	for step in range(1, CURVE_STEPS + 1):
		var t: float = float(step) / float(CURVE_STEPS)
		var point: Vector2 = _cubic_bezier(start, control_a, control_b, end, t)
		var width: float = lerpf(start_width, end_width, t)
		if _pass == 0:
			draw_line(previous, point, MapStyle.river_casing(), width + MapStyle.river_casing_extra(), true)
		else:
			draw_line(previous, point, MapStyle.river_color(), width, true)
			if MapStyle.uses_ink_linework() and step == CURVE_STEPS / 2:
				_draw_flow_squiggle(previous, point, width)
		previous = point

## One short darker-blue dash along the flow direction, seeded per location —
## the mockup's "water is moving" mark. Skips ~1/3 of candidates for rhythm.
func _draw_flow_squiggle(a: Vector2, b: Vector2, width: float) -> void:
	var mid := (a + b) * 0.5
	var seed := "rsq|%d|%d" % [roundi(mid.x), roundi(mid.y)]
	if RoadHash.pick(seed, 3) == 0:
		return
	var dir := (b - a).normalized()
	if dir == Vector2.ZERO:
		return
	var perp := Vector2(-dir.y, dir.x)
	var slide := (float(RoadHash.pick(seed + "|s", 100)) / 100.0 - 0.5) * width * 0.5
	var dash_len := width * (0.8 + float(RoadHash.pick(seed + "|l", 100)) / 100.0 * 0.8)
	var c := mid + perp * slide
	draw_line(c - dir * dash_len * 0.5, c + dir * dash_len * 0.5, MapStyle.river_squiggle(), 2.0, true)

func _hsm_outward_direction(hsm: String) -> Vector2:
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

func _is_hsm(point_id: String) -> bool:
	return point_id.begins_with("HSM")

func _float_or_default(value: String, fallback: float) -> float:
	if value == "":
		return fallback
	return float(value)

func _cubic_bezier(a: Vector2, b: Vector2, c: Vector2, d: Vector2, t: float) -> Vector2:
	var inverse_t: float = 1.0 - t
	return (
		a * inverse_t * inverse_t * inverse_t
		+ b * 3.0 * inverse_t * inverse_t * t
		+ c * 3.0 * inverse_t * t * t
		+ d * t * t * t
	)

func _exit_meets_sea(tile_coord: Vector2i, exit_hsm: String) -> bool:
	var neighbor_coord: Vector2i = tile_coord + _neighbor_offset_for_hsm(tile_coord, exit_hsm)
	if not terrain_layer.tiles.has(neighbor_coord):
		return false
	var neighbor: Dictionary = terrain_layer.tiles[neighbor_coord]
	if neighbor.get("has_river", false):
		return false
	var neighbor_type: String = str(neighbor.get("type", ""))
	return neighbor_type == "sea" or neighbor_type == "deep_sea"

func _neighbor_offset_for_hsm(tile_coord: Vector2i, hsm: String) -> Vector2i:
	var is_odd_column: bool = tile_coord.x % 2 == 1
	match hsm:
		"HSM1":
			return Vector2i(0, -1)
		"HSM2":
			return Vector2i(1, 0) if is_odd_column else Vector2i(1, -1)
		"HSM3":
			return Vector2i(1, 1) if is_odd_column else Vector2i(1, 0)
		"HSM4":
			return Vector2i(0, 1)
		"HSM5":
			return Vector2i(-1, 1) if is_odd_column else Vector2i(-1, 0)
		"HSM6":
			return Vector2i(-1, 0) if is_odd_column else Vector2i(-1, -1)
		_:
			return Vector2i.ZERO

func _load_river_properties() -> Dictionary:
	var result := {}
	if not FileAccess.file_exists(RIVER_PROPERTIES_PATH):
		push_warning("River properties CSV not found at %s." % RIVER_PROPERTIES_PATH)
		return result

	var file := FileAccess.open(RIVER_PROPERTIES_PATH, FileAccess.READ)
	if file == null:
		push_warning("Could not open %s." % RIVER_PROPERTIES_PATH)
		return result

	var header := file.get_csv_line()
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() == 0 or (row.size() == 1 and row[0] == ""):
			continue
		if row.size() != header.size():
			continue

		var river_data := {}
		for i in range(header.size()):
			river_data[header[i]] = row[i]
		result[river_data["river_type"]] = river_data

	file.close()
	return result
