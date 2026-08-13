class_name MidcenturyIndustryCompound
extends RefCounted
## Draw-only industrial-compound geometry for the optional mid-century map.
##
## Gameplay placement polygons are authoritative inputs. This helper offsets
## those exact polygons and never writes to occupancy, placement, selection or
## simulation state.

const ROAD_PRINT_CLEARANCE := 0.8
const GAMEPLAY_CLEARANCE := 1.5
const MIN_APRON_CLEARANCE := 0.1
const CLEARANCE_STEP := 0.5

static func plan(industry_sites: Array, gameplay_sites: Array, roads: Array,
		water_exclusions: Array, relief_exclusions: Array,
		preferred_clearance: float, key_prefix: String) -> Dictionary:
	var reservations: Array = []
	var diagnostics := {
		"site_count": industry_sites.size(),
		"apron_count": 0,
		"apron_missing_count": 0,
		"apron_containment_failure_count": 0,
		"apron_unrelated_gameplay_overlap_count": 0,
		"apron_water_overlap_count": 0,
		"apron_road_overlap_count": 0,
		"apron_relief_overlap_count": 0,
		"support_building_overlap_count": 0,
		"max_principal_axis_difference_degrees": 0.0,
		"principal_axis_differences_degrees": [],
	}
	var road_exclusions := _road_exclusions(roads)
	for i in industry_sites.size():
		var site: Dictionary = industry_sites[i]
		var footprint: PackedVector2Array = site.get("poly", PackedVector2Array())
		if footprint.size() < 3:
			diagnostics.apron_missing_count = int(diagnostics.apron_missing_count) + 1
			continue
		var instance_id := str(site.get("instance_id", "industry-%d" % i))
		var blocked: Array = []
		for gameplay_value in gameplay_sites:
			var gameplay: Dictionary = gameplay_value
			if str(gameplay.get("instance_id", "")) == instance_id:
				continue
			var gameplay_poly: PackedVector2Array = gameplay.get("poly", PackedVector2Array())
			if gameplay_poly.size() < 3:
				continue
			var grown := _offset_containing(gameplay_poly, GAMEPLAY_CLEARANCE)
			if grown.size() < 3:
				grown = gameplay_poly.duplicate()
			blocked.append({"poly": grown, "bb": _bbox(grown), "kind": "gameplay",
				"key": str(gameplay.get("instance_id", "gameplay"))})
		for road_value in road_exclusions:
			blocked.append((road_value as Dictionary).duplicate(true))
		for water_value in water_exclusions:
			var water: Dictionary = water_value
			blocked.append({"poly": (water.poly as PackedVector2Array).duplicate(),
				"bb": water.bb as Rect2, "kind": "water",
				"key": str(water.get("key", "water"))})
		var relief_blocked: Array = []
		for relief_value in relief_exclusions:
			var relief: Dictionary = relief_value
			relief_blocked.append({"poly": (relief.poly as PackedVector2Array).duplicate(),
				"bb": relief.bb as Rect2, "kind": "relief",
				"key": str(relief.get("key", "relief"))})

		var clearance := maxf(preferred_clearance, MIN_APRON_CLEARANCE)
		var apron := PackedVector2Array()
		while clearance >= 0.5 - 0.001:
			var candidate := _offset_containing(footprint, clearance)
			if candidate.size() >= 3 and not _poly_overlaps_any(candidate, blocked):
				apron = candidate
				break
			clearance -= CLEARANCE_STEP
		if apron.size() < 3:
			for constrained_clearance in [0.25, 0.1]:
				var candidate := _offset_containing(footprint, constrained_clearance)
				if candidate.size() >= 3 and not _poly_overlaps_any(candidate, blocked):
					apron = candidate
					clearance = constrained_clearance
					break
		if apron.size() < 3:
			diagnostics.apron_missing_count = int(diagnostics.apron_missing_count) + 1
			continue
		var draw_polys := _clip_from_exclusions(apron, relief_blocked, 4.0)
		var support_blocked := blocked.duplicate(true)
		support_blocked.append_array(relief_blocked)

		var tangent := _principal_edge_axis(footprint)
		var normal := Vector2(-tangent.y, tangent.x)
		var axis_difference := rad_to_deg(_axis_difference(
			_principal_axis(footprint), _principal_axis(apron)))
		(diagnostics.principal_axis_differences_degrees as Array).append({
			"instance_id": instance_id,
			"difference": axis_difference,
		})
		diagnostics.max_principal_axis_difference_degrees = maxf(
			float(diagnostics.max_principal_axis_difference_degrees), axis_difference)
		if not _contains_poly(apron, footprint):
			diagnostics.apron_containment_failure_count = int(
				diagnostics.apron_containment_failure_count) + 1
		for exclusion_value in blocked:
			var exclusion: Dictionary = exclusion_value
			if not _polys_overlap(apron, exclusion.poly):
				continue
			match str(exclusion.kind):
				"gameplay":
					diagnostics.apron_unrelated_gameplay_overlap_count = int(
						diagnostics.apron_unrelated_gameplay_overlap_count) + 1
				"water":
					diagnostics.apron_water_overlap_count = int(
						diagnostics.apron_water_overlap_count) + 1
				"road":
					diagnostics.apron_road_overlap_count = int(
						diagnostics.apron_road_overlap_count) + 1
		for draw_value in draw_polys:
			for relief_value in relief_blocked:
				if _polys_overlap(draw_value as PackedVector2Array,
						(relief_value as Dictionary).poly):
					diagnostics.apron_relief_overlap_count = int(
						diagnostics.apron_relief_overlap_count) + 1
		reservations.append({
			"key": "%s|%s" % [key_prefix, instance_id],
			"instance_id": instance_id,
			"poly": apron,
			"draw_polys": draw_polys,
			"bb": _bbox(apron),
			"footprint_poly": footprint.duplicate(),
			"footprint_bb": _bbox(footprint),
			"family": str(site.get("family", "orange")),
			"tangent": tangent,
			"normal": normal,
			"clearance": clearance,
			"blocked_exclusions": support_blocked,
		})
		diagnostics.apron_count = int(diagnostics.apron_count) + 1
	return {"reservations": reservations, "diagnostics": diagnostics}

static func _clip_from_exclusions(poly: PackedVector2Array,
		exclusions: Array, min_area: float) -> Array:
	var pieces: Array = [poly]
	for exclusion_value in exclusions:
		var exclusion: Dictionary = exclusion_value
		var next: Array = []
		for piece_value in pieces:
			var piece: PackedVector2Array = piece_value
			if not _bbox(piece).intersects(exclusion.bb):
				next.append(piece)
				continue
			for clipped_value in Geometry2D.clip_polygons(piece, exclusion.poly):
				var clipped: PackedVector2Array = clipped_value
				if clipped.size() >= 3 and SettlementPlan.polygon_area(clipped) >= min_area:
					next.append(clipped)
		pieces = next
		if pieces.is_empty():
			break
	return pieces

static func _road_exclusions(roads: Array) -> Array:
	var out: Array = []
	for i in roads.size():
		var road: Dictionary = roads[i]
		var a: Vector2 = road.a
		var b: Vector2 = road.b
		var tangent := (b - a).normalized()
		if tangent == Vector2.ZERO:
			continue
		var half_width := MapStyle.road_width(bool(road.get("trunk", false))) * 0.5 \
			+ ROAD_PRINT_CLEARANCE
		var poly := _segment_quad(a - tangent * half_width,
			b + tangent * half_width, half_width)
		out.append({"poly": poly, "bb": _bbox(poly), "kind": "road",
			"key": "road|%d" % i})
	return out

static func _offset_containing(poly: PackedVector2Array,
		clearance: float) -> PackedVector2Array:
	var best := PackedVector2Array()
	var best_area := 0.0
	for part_value in Geometry2D.offset_polygon(poly, clearance,
			Geometry2D.JOIN_MITER):
		var part: PackedVector2Array = part_value
		var area := SettlementPlan.polygon_area(part)
		if area > best_area and _contains_poly(part, poly):
			best = part
			best_area = area
	return best

static func _contains_poly(container: PackedVector2Array,
		contained: PackedVector2Array) -> bool:
	if container.size() < 3 or contained.size() < 3:
		return false
	var intersection_area := 0.0
	for part_value in Geometry2D.intersect_polygons(contained, container):
		intersection_area += SettlementPlan.polygon_area(part_value as PackedVector2Array)
	return intersection_area >= SettlementPlan.polygon_area(contained) - 0.05

static func _poly_overlaps_any(poly: PackedVector2Array, exclusions: Array) -> bool:
	var bb := _bbox(poly)
	for exclusion_value in exclusions:
		var exclusion: Dictionary = exclusion_value
		if bb.intersects(exclusion.bb) and _polys_overlap(poly, exclusion.poly):
			return true
	return false

static func _polys_overlap(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	for part_value in Geometry2D.intersect_polygons(a, b):
		if SettlementPlan.polygon_area(part_value as PackedVector2Array) > 0.05:
			return true
	return false

static func _principal_edge_axis(poly: PackedVector2Array) -> Vector2:
	var best := Vector2.RIGHT
	var best_length := -1.0
	for i in poly.size():
		var edge := poly[(i + 1) % poly.size()] - poly[i]
		if edge.length_squared() > best_length:
			best_length = edge.length_squared()
			best = edge.normalized()
	if best.x < -0.0001 or (absf(best.x) <= 0.0001 and best.y < 0.0):
		best = -best
	return best

static func _principal_axis(poly: PackedVector2Array) -> Vector2:
	var center := Vector2.ZERO
	for point in poly:
		center += point
	center /= maxf(1.0, float(poly.size()))
	var xx := 0.0
	var xy := 0.0
	var yy := 0.0
	for point in poly:
		var delta := point - center
		xx += delta.x * delta.x
		xy += delta.x * delta.y
		yy += delta.y * delta.y
	var angle := 0.5 * atan2(2.0 * xy, xx - yy)
	return Vector2.RIGHT.rotated(angle)

static func _axis_difference(a: Vector2, b: Vector2) -> float:
	var angle := absf(wrapf(a.angle_to(b), -PI, PI))
	return minf(angle, PI - angle)

static func _segment_quad(a: Vector2, b: Vector2,
		half_width: float) -> PackedVector2Array:
	var tangent := (b - a).normalized()
	var normal := Vector2(-tangent.y, tangent.x) * half_width
	return PackedVector2Array([a - normal, b - normal, b + normal, a + normal])

static func _bbox(poly: PackedVector2Array) -> Rect2:
	var lo := poly[0]
	var hi := poly[0]
	for point in poly:
		lo = lo.min(point)
		hi = hi.max(point)
	return Rect2(lo, hi - lo)
