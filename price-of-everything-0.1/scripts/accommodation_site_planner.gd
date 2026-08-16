class_name AccommodationSitePlanner
extends RefCounted
## Deterministic draw-only future-building accommodation sites.
##
## The planner consumes authoritative renderer/placement geometry but owns no
## land, occupancy, selection, economy or save state. The same inputs always
## produce the same oriented polygon records whether or not a map style is on.

const SITE_GAP := 5.0
const ROAD_REACH := 18.0
const FOREST_CLEAR := 4.0
const SERVICE_CLEAR := 4.0
# These are the stable placement clearances owned by BuildingVisuals, not
# renderer widths. Accommodation geometry therefore cannot move when the
# selected map style changes.
const AUTHORITATIVE_ROAD_CLEAR := 15.0

static func target_for_profile(profile: String) -> int:
	match profile:
		"metropolitan", "industrial_fringe":
			return 9
		"town", "suburban":
			return 7
		_:
			return 5

static func plan_tile(tile_id: String, center: Vector2, profile: String,
		roads: Array, service_lanes: Array, gameplay_sites: Array,
		water_exclusions: Array, relief_shoulders: Array, forests: Array,
		extra_exclusions: Array = [], allowed_polys: Array = []) -> Dictionary:
	var target := target_for_profile(profile)
	var access_segments := _segments_near_tile(roads, center, 360.0)
	var service_segments := _service_segments(service_lanes, center)
	var candidates: Array = []
	var seen: Dictionary = {}
	for access_index in access_segments.size():
		var access: Dictionary = access_segments[access_index]
		_append_access_candidates(candidates, seen, tile_id, center, profile,
			access, access_index, false)
	for access_index in service_segments.size():
		var access: Dictionary = service_segments[access_index]
		_append_access_candidates(candidates, seen, tile_id, center, profile,
			access, access_index, true)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var score_a := float(a.score)
		var score_b := float(b.score)
		return score_a < score_b if not is_equal_approx(score_a, score_b) \
			else str(a.key) < str(b.key))
	var selected: Array = []
	var used_candidates: Dictionary = {}
	var rejected := {
		"off_land": 0, "water": 0, "relief": 0, "forest": 0,
		"gameplay": 0, "road_or_lane": 0, "pair": 0, "extra": 0,
	}
	var have_large := false
	# Capacity is more useful than a row of identical tiny reservations. Select
	# deterministically by a requested size sequence, then fall back to any valid
	# class only when the preferred size cannot fit.
	var size_sequence := _size_sequence(profile, target)
	for wanted_value in size_sequence:
		var wanted := str(wanted_value)
		var accepted := false
		for candidate_value in candidates:
			var candidate: Dictionary = candidate_value
			if used_candidates.has(str(candidate.key)) or str(candidate.size_class) != wanted:
				continue
			var reason := _invalid_reason(candidate.poly, center, roads,
				service_segments, gameplay_sites, water_exclusions, relief_shoulders,
				forests, extra_exclusions, allowed_polys, selected)
			if reason != "":
				rejected[reason] = int(rejected.get(reason, 0)) + 1
				used_candidates[str(candidate.key)] = true
				continue
			_finalize_candidate(candidate, tile_id, profile, selected.size(),
				roads, service_segments)
			selected.append(candidate)
			used_candidates[str(candidate.key)] = true
			have_large = have_large or wanted == "large"
			accepted = true
			break
		if accepted:
			continue
		for candidate_value in candidates:
			var fallback: Dictionary = candidate_value
			if used_candidates.has(str(fallback.key)):
				continue
			var reason := _invalid_reason(fallback.poly, center, roads,
				service_segments, gameplay_sites, water_exclusions, relief_shoulders,
				forests, extra_exclusions, allowed_polys, selected)
			if reason != "":
				rejected[reason] = int(rejected.get(reason, 0)) + 1
				used_candidates[str(fallback.key)] = true
				continue
			_finalize_candidate(fallback, tile_id, profile, selected.size(),
				roads, service_segments)
			selected.append(fallback)
			used_candidates[str(fallback.key)] = true
			have_large = have_large or str(fallback.size_class) == "large"
			break
	# If terrain permits one valid large site, prefer it over the last smaller
	# selection; this preserves useful capacity without manufacturing geometry.
	if not have_large:
		for candidate_value in candidates:
			var candidate: Dictionary = candidate_value
			if str(candidate.size_class) != "large":
				continue
			var compare := selected.duplicate()
			if not compare.is_empty():
				compare.pop_back()
			var reason := _invalid_reason(candidate.poly, center, roads,
				service_segments, gameplay_sites, water_exclusions, relief_shoulders,
				forests, extra_exclusions, allowed_polys, compare)
			if reason == "":
				_finalize_candidate(candidate, tile_id, profile, compare.size(),
					roads, service_segments)
				selected = compare
				selected.append(candidate)
				have_large = true
				break
	var diagnostics := validate_sites(selected, gameplay_sites,
		water_exclusions, relief_shoulders, extra_exclusions)
	diagnostics.merge({
		"tile_id": tile_id,
		"profile": profile,
		"target": target,
		"valid_count": selected.size(),
		"shortfall": maxi(0, target - selected.size()),
		"constrained": selected.size() < 5,
		"candidate_count": candidates.size(),
		"rejected": rejected,
		"has_large_site": have_large,
	}, true)
	return {"sites": selected, "diagnostics": diagnostics}

static func _size_sequence(profile: String, target: int) -> Array:
	var pattern := ["large", "medium", "small", "medium", "small"]
	if profile in ["village", "rural"]:
		pattern = ["medium", "small", "small", "large", "small"]
	var out: Array = []
	for i in target:
		out.append(pattern[i % pattern.size()])
	return out

static func _finalize_candidate(candidate: Dictionary, tile_id: String,
		profile: String, index: int, roads: Array,
		service_segments: Array) -> void:
	candidate["visual_use"] = _visual_use(tile_id, profile,
		str(candidate.size_class), index)
	candidate["tile_id"] = tile_id
	candidate["profile"] = profile
	candidate["bb"] = _bbox(candidate.poly)
	candidate["reachable"] = _poly_reaches_segments(candidate.poly, roads,
		service_segments, ROAD_REACH)

static func validate_sites(sites: Array, gameplay_sites: Array,
		water_exclusions: Array, relief_shoulders: Array,
		extra_exclusions: Array = []) -> Dictionary:
	var size_distribution := {"small": 0, "medium": 0, "large": 0}
	var reach_count := 0
	var unreachable_count := 0
	var pair_overlap := 0
	var water_overlap := 0
	var contour_overlap := 0
	var footprint_overlap := 0
	var extra_overlap := 0
	for i in sites.size():
		var site: Dictionary = sites[i]
		var poly: PackedVector2Array = site.poly
		var size_class := str(site.get("size_class", "small"))
		size_distribution[size_class] = int(size_distribution.get(size_class, 0)) + 1
		if bool(site.get("reachable", false)):
			reach_count += 1
		else:
			unreachable_count += 1
		if _overlaps_any(poly, water_exclusions):
			water_overlap += 1
		if _overlaps_any(poly, relief_shoulders):
			contour_overlap += 1
		if _overlaps_site_records(poly, gameplay_sites):
			footprint_overlap += 1
		if _overlaps_any(poly, extra_exclusions):
			extra_overlap += 1
		for j in range(i + 1, sites.size()):
			if _polys_overlap(poly, (sites[j] as Dictionary).poly):
				pair_overlap += 1
	return {
		"size_distribution": size_distribution,
		"reachable_count": reach_count,
		"unreachable_count": unreachable_count,
		"pairwise_overlap_count": pair_overlap,
		"water_overlap_count": water_overlap,
		"contour_overlap_count": contour_overlap,
		"existing_footprint_overlap_count": footprint_overlap,
		"extra_exclusion_overlap_count": extra_overlap,
		"decorative_mass_overlap_count": 0,
	}

static func yield_for_hypothetical_footprints(sites: Array,
		hypothetical_footprints: Array, decorative_masses: Array = []) -> Dictionary:
	# A future building consumes a whole draw-only reservation. It never clips a
	# park/yard/lot record into remnants, and the already-clear surrounding mass
	# polygons remain untouched for the normal UrbanFabric rebuild.
	var retained: Array = []
	var removed: Array = []
	var mass_overlap_count := 0
	for site_value in sites:
		var site: Dictionary = site_value
		if _overlaps_any(site.poly, hypothetical_footprints):
			removed.append(site.duplicate(true))
		else:
			retained.append(site.duplicate(true))
	for mass_value in decorative_masses:
		var mass: Dictionary = mass_value
		var poly: PackedVector2Array = mass.get("poly", PackedVector2Array())
		if poly.size() >= 3 and _overlaps_any(poly, hypothetical_footprints):
			mass_overlap_count += 1
	var retained_overlap_count := 0
	for site_value in retained:
		if _overlaps_any((site_value as Dictionary).poly,
				hypothetical_footprints):
			retained_overlap_count += 1
	return {
		"retained_sites": retained,
		"removed_sites": removed,
		"retained_site_count": retained.size(),
		"removed_site_count": removed.size(),
		"releasable_fragment_count": 0,
		"retained_site_hypothetical_overlap_count": retained_overlap_count,
		"hypothetical_decorative_mass_overlap_count": mass_overlap_count,
		"surrounding_mass_count_before": decorative_masses.size(),
		"surrounding_mass_count_after": decorative_masses.size(),
	}

static func _append_access_candidates(out: Array, seen: Dictionary,
		tile_id: String, tile_center: Vector2, profile: String,
		access: Dictionary, access_index: int, service: bool) -> void:
	var a: Vector2 = access.a
	var b: Vector2 = access.b
	var tangent := (b - a).normalized()
	if tangent == Vector2.ZERO:
		return
	var normal := Vector2(-tangent.y, tangent.x)
	var sizes := [
		{"class": "large", "length": 46.0, "depth": 32.0},
		{"class": "medium", "length": 32.0, "depth": 22.0},
		{"class": "small", "length": 22.0, "depth": 16.0},
	]
	var offsets := [0.16, 0.30, 0.44, 0.58, 0.72, 0.86]
	for oi in offsets.size():
		var t := float(offsets[oi])
		var anchor := a.lerp(b, t)
		if anchor.distance_to(tile_center) > 370.0:
			continue
		for side in [-1.0, 1.0]:
			for size_index in sizes.size():
				var size: Dictionary = sizes[size_index]
				var depth := float(size.depth)
				var road_clear := SERVICE_CLEAR if service else \
					AUTHORITATIVE_ROAD_CLEAR
				var site_center := anchor + normal * float(side) * (
					road_clear + 0.75 + depth * 0.5)
				var key := "%s|%s|%d|%d|%d|%d" % [tile_id,
					"service" if service else "road", access_index, oi,
					int(side), size_index]
				var quantized := Vector2i(roundi(site_center.x), roundi(site_center.y))
				var dedupe := "%d|%d|%s" % [quantized.x, quantized.y, str(size.class)]
				if seen.has(dedupe):
					continue
				seen[dedupe] = true
				var poly := _site_poly(site_center, tangent, float(size.length),
					depth, key)
				var class_priority := 0.0
				if str(size.class) == "medium":
					class_priority = 0.18
				elif str(size.class) == "small":
					class_priority = 0.34
				var service_cost := 0.42 if service else 0.0
				var profile_cost := 0.0
				if profile in ["village", "rural"] and str(size.class) == "large":
					profile_cost = 0.55
				out.append({
					"key": key, "poly": poly, "center": site_center,
					"tangent": tangent, "normal": normal,
					"size_class": str(size.class),
					"access_kind": "service_lane" if service else "authoritative_road",
					"access_a": a, "access_b": b,
					"score": service_cost + class_priority + profile_cost +
						float(RoadHash.pick("accommodation-score|%s" % key, 1000)) / 10000.0,
				})

static func _invalid_reason(poly: PackedVector2Array, tile_center: Vector2,
		roads: Array, service_segments: Array, gameplay_sites: Array,
		water_exclusions: Array, relief_shoulders: Array, forests: Array,
		extra_exclusions: Array, allowed_polys: Array, selected: Array) -> String:
	if not _poly_on_usable_land(poly, tile_center):
		return "off_land"
	if not allowed_polys.is_empty() and not _inside_allowed(poly, allowed_polys):
		return "extra"
	if not _poly_reaches_segments(poly, roads, service_segments, ROAD_REACH):
		return "road_or_lane"
	if _overlaps_any(poly, water_exclusions):
		return "water"
	if _overlaps_any(poly, relief_shoulders):
		return "relief"
	if _overlaps_forests(poly, forests):
		return "forest"
	if _overlaps_site_records(poly, gameplay_sites):
		return "gameplay"
	if _poly_hits_segments(poly, roads, AUTHORITATIVE_ROAD_CLEAR) or \
			_poly_hits_segments(poly, service_segments, SERVICE_CLEAR):
		return "road_or_lane"
	if _overlaps_any(poly, extra_exclusions):
		return "extra"
	for selected_value in selected:
		var grown := _offset((selected_value as Dictionary).poly, SITE_GAP)
		if _polys_overlap(poly, grown):
			return "pair"
	return ""

static func _inside_allowed(poly: PackedVector2Array, allowed_polys: Array) -> bool:
	for allowed_value in allowed_polys:
		var allowed: PackedVector2Array = allowed_value
		if allowed.size() < 3:
			continue
		var all_inside := Geometry2D.is_point_in_polygon(_center(poly), allowed)
		for point in poly:
			if not Geometry2D.is_point_in_polygon(point, allowed):
				all_inside = false
				break
		if all_inside:
			return true
	return false

static func _access_reaches(site: Dictionary) -> bool:
	var poly: PackedVector2Array = site.poly
	var a: Vector2 = site.access_a
	var b: Vector2 = site.access_b
	var best := INF
	for point in poly:
		best = minf(best, _point_segment_distance(point, a, b))
	return best <= ROAD_REACH

static func _poly_reaches_segments(poly: PackedVector2Array, roads: Array,
		service_segments: Array, reach: float) -> bool:
	for segments in [roads, service_segments]:
		for segment_value in segments:
			var segment: Dictionary = segment_value
			for point in poly:
				if _point_segment_distance(point, segment.a, segment.b) <= reach:
					return true
	return false

static func _poly_on_usable_land(poly: PackedVector2Array,
		tile_center: Vector2) -> bool:
	var nav := NavGrid.instance()
	var probes := poly.duplicate()
	probes.append(_center(poly))
	# Corners and centre are insufficient at curved coasts: a wide polygon can
	# bridge water while all five probes remain on land. Sample every edge at
	# half-nav-cell spacing, then test nav-cell centres inside the footprint.
	var edge_step := maxf(4.0, nav.step * 0.5) if nav.is_ready() else 6.0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var samples := maxi(1, int(ceil(a.distance_to(b) / edge_step)))
		for sample in range(1, samples):
			probes.append(a.lerp(b, float(sample) / float(samples)))
	for point in probes:
		var rel := point - tile_center
		if absf(rel.x) > 270.0 or absf(rel.y) > 240.0 or \
				240.0 * absf(rel.x) + 135.0 * absf(rel.y) > 64800.0:
			return false
		if not nav.is_ready():
			continue
		var cell := nav.cell_of(point)
		if nav.water(cell.x, cell.y) != NavGrid.WATER_LAND or \
				nav.level(cell.x, cell.y) < 0:
			return false
	if nav.is_ready():
		var bb := _bbox(poly)
		var cell_min := nav.cell_of(bb.position)
		var cell_max := nav.cell_of(bb.end)
		for iy in range(cell_min.y, cell_max.y + 1):
			for ix in range(cell_min.x, cell_max.x + 1):
				var point := nav.world_of(ix, iy)
				if Geometry2D.is_point_in_polygon(point, poly) and (
						nav.water(ix, iy) != NavGrid.WATER_LAND or
						nav.level(ix, iy) < 0):
					return false
	return true

static func _segments_near_tile(segments: Array, center: Vector2,
		radius: float) -> Array:
	var out: Array = []
	for segment_value in segments:
		var segment: Dictionary = segment_value
		if _point_segment_distance(center, segment.a, segment.b) <= radius:
			out.append(segment)
	return out

static func _service_segments(lanes: Array, center: Vector2) -> Array:
	var out: Array = []
	for lane_value in lanes:
		var lane: PackedVector2Array = lane_value
		for i in range(lane.size() - 1):
			if _point_segment_distance(center, lane[i], lane[i + 1]) <= 360.0:
				out.append({"a": lane[i], "b": lane[i + 1], "trunk": false})
	return out

static func _site_poly(center: Vector2, tangent: Vector2, length: float,
		depth: float, key: String) -> PackedVector2Array:
	var t := tangent.normalized()
	var n := Vector2(-t.y, t.x)
	var front_left := -length * 0.5 + _rr("%s|fl" % key, -1.2, 1.2)
	var front_right := length * 0.5 + _rr("%s|fr" % key, -1.2, 1.2)
	var back_right := length * 0.5 + _rr("%s|br" % key, -1.8, 1.8)
	var back_left := -length * 0.5 + _rr("%s|bl" % key, -1.8, 1.8)
	return PackedVector2Array([
		center + t * front_left - n * depth * 0.5,
		center + t * front_right - n * depth * 0.5,
		center + t * back_right + n * depth * 0.5,
		center + t * back_left + n * depth * 0.5,
	])

static func _visual_use(tile_id: String, profile: String,
		size_class: String, index: int) -> String:
	if profile == "industrial_fringe" and (size_class == "large" or index % 3 == 0):
		return "industrial_growth"
	var uses := ["hard_open_lot", "releasable_park", "releasable_yard"]
	if profile in ["village", "rural"]:
		uses = ["releasable_yard", "hard_open_lot", "releasable_park"]
	return uses[RoadHash.pick("accommodation-use|%s|%d" % [tile_id, index], uses.size())]

static func _overlaps_forests(poly: PackedVector2Array, forests: Array) -> bool:
	for forest_value in forests:
		var forest: Dictionary = forest_value
		var center: Vector2 = forest.center
		var radius := float(forest.radius) + FOREST_CLEAR
		if Geometry2D.is_point_in_polygon(center, poly):
			return true
		for point in poly:
			if point.distance_to(center) < radius:
				return true
		for i in poly.size():
			if _point_segment_distance(center, poly[i],
					poly[(i + 1) % poly.size()]) < radius:
				return true
	return false

static func _poly_hits_segments(poly: PackedVector2Array, segments: Array,
		clearance: float) -> bool:
	for segment_value in segments:
		var segment: Dictionary = segment_value
		for point in poly:
			if _point_segment_distance(point, segment.a, segment.b) < clearance:
				return true
		for i in poly.size():
			if Geometry2D.segment_intersects_segment(poly[i],
					poly[(i + 1) % poly.size()], segment.a, segment.b) != null:
				return true
	return false

static func _overlaps_site_records(poly: PackedVector2Array,
		records: Array) -> bool:
	for record_value in records:
		var record: Dictionary = record_value
		var other: PackedVector2Array = record.get("poly", PackedVector2Array())
		if other.size() >= 3 and _polys_overlap(poly, other):
			return true
	return false

static func _overlaps_any(poly: PackedVector2Array, exclusions: Array) -> bool:
	var bb := _bbox(poly)
	for exclusion_value in exclusions:
		var exclusion: Dictionary = exclusion_value
		var other: PackedVector2Array = exclusion.get("poly", PackedVector2Array())
		if other.size() >= 3 and bb.intersects(exclusion.get("bb", _bbox(other))) \
				and _polys_overlap(poly, other):
			return true
	return false

static func _polys_overlap(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	for intersection_value in Geometry2D.intersect_polygons(a, b):
		if SettlementPlan.polygon_area(intersection_value as PackedVector2Array) > 0.05:
			return true
	return false

static func _offset(poly: PackedVector2Array, amount: float) -> PackedVector2Array:
	var best := poly
	var best_area := SettlementPlan.polygon_area(poly)
	for part_value in Geometry2D.offset_polygon(poly, amount, Geometry2D.JOIN_MITER):
		var part: PackedVector2Array = part_value
		var area := SettlementPlan.polygon_area(part)
		if area > best_area:
			best = part
			best_area = area
	return best

static func _center(poly: PackedVector2Array) -> Vector2:
	var center := Vector2.ZERO
	for point in poly:
		center += point
	return center / maxf(1.0, float(poly.size()))

static func _bbox(poly: PackedVector2Array) -> Rect2:
	var lo := poly[0]
	var hi := poly[0]
	for point in poly:
		lo = lo.min(point)
		hi = hi.max(point)
	return Rect2(lo, hi - lo)

static func _point_segment_distance(point: Vector2, a: Vector2,
		b: Vector2) -> float:
	var ab := b - a
	if ab.length_squared() <= 0.0001:
		return point.distance_to(a)
	var t := clampf((point - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return point.distance_to(a + ab * t)

static func _rr(key: String, low: float, high: float) -> float:
	return lerpf(low, high, float(RoadHash.pick(key, 10001)) / 10000.0)
