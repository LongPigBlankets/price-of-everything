class_name SettlementPlanBuilder
extends RefCounted
## Deterministic authored prototypes for SettlementPlan.
##
## The fixed world may provide exact local guidance. These points describe the
## visual history of a settlement; they do not create RoadNetwork edges or
## reserve any gameplay land.

const SILKSTOWN_IDS := ["tile_9_8", "tile_9_9"]
const CAPITAL_IDS := [
	"tile_23_8", "tile_24_7", "tile_24_8", "tile_24_9",
	"tile_25_9", "tile_26_8", "tile_27_9",
]
static var HEX_VERTS := PackedVector2Array([
	Vector2(-135.0, -240.0), Vector2(135.0, -240.0), Vector2(270.0, 0.0),
	Vector2(135.0, 240.0), Vector2(-135.0, 240.0), Vector2(-270.0, 0.0),
])
const FACE_MIN_AREA := 520.0
const ZONE_PARCEL_TARGET_AREA := 14500.0
const ZONE_PARCEL_MIN_AREA := 720.0
const RELIEF_MIN_AREA_RETENTION := 0.72
const RELIEF_MIN_PARCEL_RETENTION := 0.60
const AUTHORITATIVE_ROAD_MARGIN := 5.2
const DECORATIVE_STREET_HALF_WIDTH := 3.0
const BUILDING_BANK_CLEARANCE := 4.0

static func build_silkstown(terrain: TileMapLayer, river_visuals: Node,
		hill_visuals: Node,
		authoritative_roads: Array, footprints: Array, gameplay_sites: Array,
		industry_sites: Array) -> SettlementPlan:
	var plan := SettlementPlan.new("silkstown")
	plan.tile_ids.assign(SILKSTOWN_IDS)
	plan.authoritative_roads = authoritative_roads.duplicate(true)

	# Authored land-side control points. Endpoints are exact points on built
	# approaches; the interpolated middle follows the historic bank alignment.
	var north_west := _catmull_path(PackedVector2Array([
		Vector2(4276.0, 4348.0), Vector2(4245.0, 4372.0),
		Vector2(4180.0, 4428.0), Vector2(4172.0, 4465.0),
		Vector2(4205.0, 4498.0), Vector2(4255.0, 4525.0),
		Vector2(4295.2001953125, 4559.5),
	]), 6)
	var south_east := _catmull_path(PackedVector2Array([
		Vector2(4356.5, 4566.47998046875), Vector2(4340.0, 4600.0),
		Vector2(4310.0, 4640.0), Vector2(4242.0, 4680.0),
		Vector2(4296.0, 4725.0), Vector2(4348.0, 4765.0),
		Vector2(4360.0, 4800.0), Vector2(4336.0, 4848.0),
		Vector2(4268.0, 4888.0), Vector2(4242.0, 4920.0),
		Vector2(4292.0, 4965.0), Vector2(4342.0, 5000.0),
		Vector2(4360.0, 5040.0), Vector2(4346.0, 5085.0),
		Vector2(4336.0, 5113.0),
	]), 5)
	plan.decorative_streets = [
		{"key": "old-bank-north-west", "points": north_west,
			"role": "embankment", "half_width": DECORATIVE_STREET_HALF_WIDTH},
		{"key": "old-bank-south-east", "points": south_east,
			"role": "embankment", "half_width": DECORATIVE_STREET_HALF_WIDTH},
	]

	# The extents use the authored riverfront streets as settlement boundaries
	# and open toward established inland roads. Tile hexes do not appear here.
	plan.extent_polygons = [
		_extent_from_street(north_west, PackedVector2Array([
			Vector2(4160.0, 4620.0), Vector2(4020.0, 4605.0),
			Vector2(3925.0, 4535.0), Vector2(3920.0, 4435.0),
			Vector2(3985.0, 4350.0), Vector2(4120.0, 4300.0),
		])),
		_extent_from_street(south_east, PackedVector2Array([
			Vector2(4515.0, 5175.0), Vector2(4650.0, 5105.0),
			Vector2(4740.0, 4970.0), Vector2(4730.0, 4780.0),
			Vector2(4660.0, 4650.0), Vector2(4525.0, 4575.0),
		])),
	]
	_apply_water_geometry(plan, river_visuals)
	_apply_relief_geometry(plan, hill_visuals)
	plan.district_guides = [
		{"key": "west-frontage", "role": "ordinary-town", "point": Vector2(4105.0, 4500.0)},
		{"key": "south-river-green", "role": "park", "point": Vector2(4415.0, 4860.0)},
		{"key": "docks-works", "role": "works", "point": Vector2(4450.0, 5070.0)},
	]
	_apply_industry_compounds(plan, industry_sites, gameplay_sites,
		authoritative_roads, 16.0, "silkstown-industry")
	for i in footprints.size():
		var rect: Rect2 = (footprints[i] as Rect2).grow(8.0)
		plan.open_lots.append({"key": "gameplay-footprint|%d" % i,
			"poly": _rect_poly(rect), "bb": rect, "role": "gameplay-exclusion"})

	var corridors := _road_corridors(authoritative_roads)
	for street_value in plan.decorative_streets:
		var street: Dictionary = street_value
		corridors.append_array(_polyline_corridors(street.points,
			float(street.half_width)))
	var exclusions: Array = []
	exclusions.append_array(corridors)
	exclusions.append_array(plan.water_exclusions)
	exclusions.append_array(plan.industrial_reservations)
	exclusions.append_array(plan.open_lots)
	var face_polys := _clip_polys(plan.extent_polygons, exclusions, FACE_MIN_AREA)
	face_polys.sort_custom(func(a: PackedVector2Array, b: PackedVector2Array) -> bool:
		var ca := _poly_center(a)
		var cb := _poly_center(b)
		return ca.y < cb.y if not is_equal_approx(ca.y, cb.y) else ca.x < cb.x
	)
	for i in face_polys.size():
		plan.faces.append({"key": "silkstown-face|%d" % i,
			"poly": face_polys[i], "role": "unassigned"})

	_assign_silkstown_roles(plan)
	_split_plan_parcels_by_relief(plan)
	var water_diagnostics := plan.diagnostics.duplicate(true)
	plan.diagnostics = _silkstown_diagnostics(plan)
	plan.diagnostics.merge(water_diagnostics, true)
	return plan

static func build_capital(terrain: TileMapLayer, river_visuals: Node,
		hill_visuals: Node,
		authoritative_roads: Array, footprints: Array, gameplay_sites: Array,
		industry_sites: Array, specs: Array) -> SettlementPlan:
	var plan := SettlementPlan.new("capital-port")
	plan.tile_ids.assign(CAPITAL_IDS)
	plan.authoritative_roads = authoritative_roads.duplicate(true)

	# One authored component outline follows the inland fringe and the harbor
	# shore. It is deliberately unrelated to the seven source hex silhouettes.
	plan.extent_polygons = [PackedVector2Array([
		Vector2(9650.0, 4320.0), Vector2(9850.0, 4160.0),
		Vector2(10220.0, 4070.0), Vector2(10470.0, 4160.0),
		Vector2(10535.0, 4350.0), Vector2(10520.0, 4540.0),
		Vector2(10580.0, 4700.0), Vector2(10720.0, 4810.0),
		Vector2(11000.0, 4860.0), Vector2(11300.0, 4800.0),
		Vector2(11610.0, 4780.0), Vector2(11880.0, 4920.0),
		Vector2(11930.0, 5170.0), Vector2(11720.0, 5390.0),
		Vector2(11360.0, 5460.0), Vector2(11000.0, 5360.0),
		Vector2(10690.0, 5500.0), Vector2(10300.0, 5500.0),
		Vector2(9960.0, 5350.0), Vector2(9740.0, 5100.0),
		Vector2(9650.0, 4800.0),
	])]
	_apply_water_geometry(plan, river_visuals)
	_apply_relief_geometry(plan, hill_visuals)
	plan.district_guides = [
		{"key": "market-row", "role": "core", "point": Vector2(9950.0, 4570.0)},
		{"key": "old-quarter", "role": "core", "point": Vector2(10370.0, 5160.0)},
		{"key": "docks", "role": "works", "point": Vector2(10600.0, 4820.0)},
		{"key": "industrial-zone", "role": "works", "point": Vector2(11200.0, 5050.0)},
		{"key": "foundry", "role": "works", "point": Vector2(11600.0, 5110.0)},
		{"key": "harbor-green", "role": "park", "point": Vector2(10820.0, 4970.0)},
	]
	_apply_industry_compounds(plan, industry_sites, gameplay_sites,
		authoritative_roads, 18.0, "capital-industry")
	for i in footprints.size():
		var rect: Rect2 = (footprints[i] as Rect2).grow(9.0)
		plan.open_lots.append({"key": "gameplay-footprint|%d" % i,
			"poly": _rect_poly(rect), "bb": rect, "role": "gameplay-exclusion"})

	var exclusions: Array = []
	exclusions.append_array(_road_corridors(authoritative_roads))
	exclusions.append_array(plan.water_exclusions)
	exclusions.append_array(plan.industrial_reservations)
	exclusions.append_array(plan.open_lots)
	var face_polys := _clip_polys(plan.extent_polygons, exclusions, 900.0)
	face_polys.sort_custom(func(a: PackedVector2Array, b: PackedVector2Array) -> bool:
		var ca := _poly_center(a)
		var cb := _poly_center(b)
		return ca.y < cb.y if not is_equal_approx(ca.y, cb.y) else ca.x < cb.x
	)
	for i in face_polys.size():
		if SettlementPlan.polygon_self_intersects(face_polys[i]):
			continue
		plan.faces.append({"key": "capital-face|%d" % i,
			"poly": face_polys[i], "role": "unassigned"})
	_assign_capital_roles(plan)
	_split_plan_parcels_by_relief(plan)
	var water_diagnostics := plan.diagnostics.duplicate(true)
	plan.diagnostics = _capital_diagnostics(plan, specs, terrain)
	plan.diagnostics.merge(water_diagnostics, true)
	return plan

static func _apply_industry_compounds(plan: SettlementPlan,
		industry_sites: Array, gameplay_sites: Array, roads: Array,
		clearance: float, key_prefix: String) -> void:
	var result := MidcenturyIndustryCompound.plan(industry_sites, gameplay_sites,
		roads, plan.water_exclusions, plan.relief_shoulders, clearance, key_prefix)
	plan.industrial_reservations = result.reservations
	plan.diagnostics.merge(result.diagnostics, true)

static func _apply_water_geometry(plan: SettlementPlan, river_visuals: Node) -> void:
	if river_visuals == null or not river_visuals.has_method("get_water_exclusion_geometry"):
		return
	var water: Dictionary = river_visuals.call("get_water_exclusion_geometry",
		plan.extent_polygons, BUILDING_BANK_CLEARANCE)
	plan.water_exclusions = (water.get("polygons", []) as Array).duplicate(true)
	plan.water_paths = (water.get("paths", []) as Array).duplicate(true)
	plan.water_lakes = (water.get("lakes", []) as Array).duplicate(true)
	plan.boundary_splines = []
	for path_value in plan.water_paths:
		var path: Dictionary = path_value
		plan.boundary_splines.append({
			"kind": "river_centerline",
			"tile_coord": path.get("coord", Vector2i(-1, -1)),
			"points": (path.points as PackedVector2Array).duplicate(),
			"rendered_width": float(path.get("rendered_width", 15.0)),
			"exclusion_half_width": float(path.get("exclusion_half_width", 0.0)),
		})
	plan.diagnostics["uncovered_river_join_count"] = int(
		water.get("uncovered_river_join_count", 0))
	plan.diagnostics["building_bank_clearance"] = float(
		water.get("building_bank_clearance", BUILDING_BANK_CLEARANCE))
	plan.diagnostics["river_casing_extra"] = float(
		water.get("river_casing_extra", MapStyle.river_casing_extra()))

static func _apply_relief_geometry(plan: SettlementPlan,
		hill_visuals: Node) -> void:
	if hill_visuals == null or not hill_visuals.has_method(
			"get_land_relief_geometry"):
		return
	var relief: Dictionary = hill_visuals.call("get_land_relief_geometry",
		plan.extent_polygons)
	plan.relief_shoulders = (relief.get("shoulders", []) as Array).duplicate(true)
	plan.relief_plateaus = (relief.get("plateaus", []) as Array).duplicate(true)
	plan.material_relief_bands = (relief.get("material_bands", []) as Array).duplicate()
	plan.diagnostics["material_land_band_count"] = int(
		relief.get("material_band_count", 0))
	plan.diagnostics["relief_shoulders_active"] = bool(relief.get("active", false))

static func _split_plan_parcels_by_relief(plan: SettlementPlan) -> void:
	if plan.relief_shoulders.is_empty():
		return
	var original_parcels: Array = plan.parcels.duplicate(true)
	var original_area := 0.0
	for parcel_value in original_parcels:
		original_area += SettlementPlan.polygon_area(
			(parcel_value as Dictionary).poly as PackedVector2Array)
	var split: Array = []
	for parcel_value in plan.parcels:
		var parcel: Dictionary = parcel_value
		var pieces: Array = [parcel.poly as PackedVector2Array]
		for shoulder_value in plan.relief_shoulders:
			var shoulder: Dictionary = shoulder_value
			var next: Array = []
			for piece_value in pieces:
				var piece: PackedVector2Array = piece_value
				if not _bbox(piece).intersects(shoulder.bb):
					next.append(piece)
					continue
				for clipped_value in Geometry2D.clip_polygons(piece, shoulder.poly):
					var clipped: PackedVector2Array = clipped_value
					if clipped.size() >= 3 and SettlementPlan.polygon_area(clipped) >= \
							ZONE_PARCEL_MIN_AREA:
						next.append(clipped)
			pieces = next
			if pieces.is_empty():
				break
		for i in pieces.size():
			var record := parcel.duplicate(true)
			record.key = "%s|plateau|%d" % [str(parcel.key), i]
			record.poly = pieces[i]
			split.append(record)
	var retained_area := 0.0
	for parcel_value in split:
		retained_area += SettlementPlan.polygon_area(
			(parcel_value as Dictionary).poly as PackedVector2Array)
	var area_retention := retained_area / maxf(1.0, original_area)
	var parcel_retention := float(split.size()) / maxf(1.0,
		float(original_parcels.size()))
	plan.diagnostics["relief_parcel_area_retention"] = area_retention
	plan.diagnostics["relief_parcel_count_retention"] = parcel_retention
	# Sequential contour subtraction is allowed to separate a block, never to
	# erase the settlement. Defer relief massing for this plan when the operation
	# would discard a substantial share of the already water-safe zoning.
	if split.is_empty() or area_retention < RELIEF_MIN_AREA_RETENTION or \
			parcel_retention < RELIEF_MIN_PARCEL_RETENTION:
		plan.parcels = original_parcels
		plan.diagnostics["relief_retention_fallback"] = true
		plan.diagnostics["relief_shoulders_deferred_count"] = \
			plan.relief_shoulders.size()
		plan.diagnostics["relief_shoulders_active"] = false
		plan.relief_shoulders = []
		return
	plan.diagnostics["relief_retention_fallback"] = false
	plan.parcels = split

static func _assign_capital_roles(plan: SettlementPlan) -> void:
	var parcels: Array = []
	for face_value in plan.faces:
		var face: Dictionary = face_value
		for piece_value in _subdivide_zone_face(face.poly, str(face.key), 0):
			var piece: PackedVector2Array = piece_value
			var center := _poly_center(piece)
			var core_distance := minf(center.distance_to(Vector2(9950.0, 4570.0)),
				center.distance_to(Vector2(10370.0, 5160.0)))
			var works_distance := minf(center.distance_to(Vector2(10600.0, 4820.0)),
				minf(center.distance_to(Vector2(11200.0, 5050.0)),
					center.distance_to(Vector2(11600.0, 5110.0))))
			var boundary_distance := _point_polygon_boundary_distance(center,
				plan.extent_polygons[0])
			var context := "ordinary"
			if core_distance < 260.0:
				context = "core"
			elif works_distance < 255.0:
				context = "works"
			elif boundary_distance < 95.0:
				context = "peripheral"
			parcels.append({
				"key": "%s|zone|%d" % [str(face.key), parcels.size()],
				"face_key": str(face.key), "poly": piece,
				"role": "built", "context": context,
				"core_distance": core_distance,
				"works_distance": works_distance,
				"boundary_distance": boundary_distance,
			})
	var total_area := 0.0
	for parcel_value in parcels:
		total_area += SettlementPlan.polygon_area((parcel_value as Dictionary).poly)
	var yard_candidates := parcels.duplicate()
	yard_candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var da := _capital_parcel_industry_score(a, plan)
		var db := _capital_parcel_industry_score(b, plan)
		return da < db if not is_equal_approx(da, db) else str(a.key) < str(b.key)
	)
	_assign_role_to_target(yard_candidates, "yard", total_area * 0.15, {})
	var park_candidates: Array = parcels.filter(func(parcel: Dictionary) -> bool:
		return str(parcel.role) == "built")
	var park_guide := Vector2(10820.0, 4970.0)
	park_candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var da := _poly_center(a.poly).distance_squared_to(park_guide)
		var db := _poly_center(b.poly).distance_squared_to(park_guide)
		return da < db if not is_equal_approx(da, db) else str(a.key) < str(b.key)
	)
	_assign_role_to_target(park_candidates, "park", total_area * 0.095, {})
	var open_candidates: Array = parcels.filter(func(parcel: Dictionary) -> bool:
		return str(parcel.role) == "built")
	open_candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var da := float(a.boundary_distance)
		var db := float(b.boundary_distance)
		return da < db if not is_equal_approx(da, db) else str(a.key) < str(b.key)
	)
	_assign_role_to_target(open_candidates, "open", total_area * 0.10, {})
	plan.parcels = parcels
	for face_value in plan.faces:
		var face: Dictionary = face_value
		var roles: Dictionary = {}
		for parcel_value in parcels:
			var parcel: Dictionary = parcel_value
			if str(parcel.face_key) == str(face.key):
				roles[str(parcel.role)] = true
		face.role = roles.keys()[0] if roles.size() == 1 else "mixed"

static func _capital_parcel_industry_score(parcel: Dictionary,
		plan: SettlementPlan) -> float:
	var center := _poly_center(parcel.poly)
	var best := float(parcel.works_distance)
	for reservation_value in plan.industrial_reservations:
		var reservation: Dictionary = reservation_value
		best = minf(best, center.distance_to((reservation.bb as Rect2).get_center()))
	return best

static func _point_polygon_boundary_distance(point: Vector2,
		poly: PackedVector2Array) -> float:
	var best := INF
	for i in poly.size():
		best = minf(best, _point_segment_distance(point, poly[i],
			poly[(i + 1) % poly.size()]))
	return best

static func _capital_diagnostics(plan: SettlementPlan, specs: Array,
		terrain: TileMapLayer) -> Dictionary:
	var spec_by_coord: Dictionary = {}
	for spec_value in specs:
		var spec: Dictionary = spec_value
		spec_by_coord[spec.coord] = spec
	var internal_edges: Array = []
	var external_edges: Array = []
	var seen_internal: Dictionary = {}
	for spec_value in specs:
		var spec: Dictionary = spec_value
		var neighbors: Array[Vector2i] = terrain.call("neighbor_coords", spec.coord)
		for edge_index in HEX_VERTS.size():
			var a: Vector2 = spec.center + HEX_VERTS[edge_index]
			var b: Vector2 = spec.center + HEX_VERTS[(edge_index + 1) % HEX_VERTS.size()]
			var neighbor: Vector2i = neighbors[edge_index]
			if spec_by_coord.has(neighbor):
				var pair := [str(spec.id), str((spec_by_coord[neighbor] as Dictionary).id)]
				pair.sort()
				var key := "%s|%s" % pair
				if not seen_internal.has(key):
					seen_internal[key] = true
					internal_edges.append({"key": key, "a": a, "b": b})
			else:
				external_edges.append({"key": "%s|%d" % [str(spec.id), edge_index],
					"a": a, "b": b})
	var internal_records := _edge_band_records(internal_edges, plan)
	var external_records := _edge_band_records(external_edges, plan)
	var invalid_faces: Array = []
	for face_value in plan.faces:
		var face: Dictionary = face_value
		if not SettlementPlan.polygon_self_intersects(face.poly):
			continue
		var points: Array = []
		for point in face.poly:
			points.append([point.x, point.y])
		invalid_faces.append({"key": str(face.key), "points": points})
	var role_area := {"built": 0.0, "park": 0.0, "yard": 0.0, "open": 0.0}
	var context_counts: Dictionary = {}
	for parcel_value in plan.parcels:
		var parcel: Dictionary = parcel_value
		var role := str(parcel.role)
		role_area[role] = float(role_area.get(role, 0.0)) + SettlementPlan.polygon_area(parcel.poly)
		var context := str(parcel.context)
		context_counts[context] = int(context_counts.get(context, 0)) + 1
	return {
		"internal_edge_count": internal_edges.size(),
		"internal_edge_bands": internal_records,
		"external_edge_bands": external_records,
		"internal_band_coverage": _average_edge_coverage(internal_records),
		"external_band_coverage": _average_edge_coverage(external_records),
		"longest_internal_empty_strip": _longest_edge_empty(internal_records),
		"face_self_intersections": plan.faces.filter(func(face: Dictionary) -> bool:
			return SettlementPlan.polygon_self_intersects(face.poly)).size(),
		"invalid_faces": invalid_faces,
		"role_area": role_area,
		"context_counts": context_counts,
		"geometry_errors": Array(plan.validate_geometry()),
	}

static func _edge_band_records(edges: Array, plan: SettlementPlan) -> Array:
	var records: Array = []
	for edge_value in edges:
		var edge: Dictionary = edge_value
		var a: Vector2 = edge.a
		var b: Vector2 = edge.b
		var samples := maxi(2, ceili(a.distance_to(b) / 12.0))
		var covered := 0
		var longest_empty := 0.0
		var current_empty := 0.0
		var step_length := a.distance_to(b) / float(samples)
		var tangent := (b - a).normalized()
		var normal := Vector2(-tangent.y, tangent.x)
		for i in range(samples + 1):
			var point := a.lerp(b, float(i) / float(samples))
			var occupied := _point_in_any_poly(point + normal * 18.0, plan.faces)
			occupied = occupied or _point_in_any_poly(point - normal * 18.0, plan.faces)
			if occupied:
				covered += 1
				current_empty = 0.0
			else:
				current_empty += step_length
				longest_empty = maxf(longest_empty, current_empty)
		records.append({"key": str(edge.key),
			"coverage": float(covered) / float(samples + 1),
			"longest_empty_strip": longest_empty})
	return records

static func _point_in_any_poly(point: Vector2, records: Array) -> bool:
	for record_value in records:
		var record: Dictionary = record_value
		if Geometry2D.is_point_in_polygon(point, record.poly):
			return true
	return false

static func _average_edge_coverage(records: Array) -> float:
	var total := 0.0
	for record_value in records:
		total += float((record_value as Dictionary).coverage)
	return total / maxf(1.0, float(records.size()))

static func _longest_edge_empty(records: Array) -> float:
	var longest := 0.0
	for record_value in records:
		longest = maxf(longest, float((record_value as Dictionary).longest_empty_strip))
	return longest

static func _assign_silkstown_roles(plan: SettlementPlan) -> void:
	var parcels: Array = []
	for i in plan.faces.size():
		var face: Dictionary = plan.faces[i]
		var pieces := _subdivide_zone_face(face.poly, str(face.key), 0)
		for piece_value in pieces:
			var piece: PackedVector2Array = piece_value
			parcels.append({
				"key": "%s|zone|%d" % [str(face.key), parcels.size()],
				"face_key": str(face.key), "poly": piece, "role": "built",
			})
	face_roles_from_context(plan, parcels)
	plan.parcels = parcels
	for face_value in plan.faces:
		var face: Dictionary = face_value
		var roles: Dictionary = {}
		for parcel_value in parcels:
			var parcel: Dictionary = parcel_value
			if str(parcel.face_key) == str(face.key):
				roles[str(parcel.role)] = true
		face.role = roles.keys()[0] if roles.size() == 1 else "mixed"

static func face_roles_from_context(plan: SettlementPlan, parcels: Array) -> void:
	var total_area := 0.0
	for parcel_value in parcels:
		total_area += SettlementPlan.polygon_area((parcel_value as Dictionary).poly)
	var yard_candidates := parcels.duplicate()
	yard_candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var da := _parcel_industry_score(a, plan)
		var db := _parcel_industry_score(b, plan)
		return da < db if not is_equal_approx(da, db) else str(a.key) < str(b.key)
	)
	_assign_role_to_target(yard_candidates, "yard", total_area * 0.17, {})

	var park_candidates: Array = parcels.filter(func(parcel: Dictionary) -> bool:
		return str(parcel.role) == "built")
	var park_guide := Vector2(4415.0, 4860.0)
	park_candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var da := _poly_center(a.poly).distance_squared_to(park_guide)
		var db := _poly_center(b.poly).distance_squared_to(park_guide)
		return da < db if not is_equal_approx(da, db) else str(a.key) < str(b.key)
	)
	_assign_role_to_target(park_candidates, "park", total_area * 0.10, {})

	var open_candidates: Array = parcels.filter(func(parcel: Dictionary) -> bool:
		return str(parcel.role) == "built")
	var settlement_focus := Vector2(4320.0, 4760.0)
	open_candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var da := _poly_center(a.poly).distance_squared_to(settlement_focus)
		var db := _poly_center(b.poly).distance_squared_to(settlement_focus)
		return da > db if not is_equal_approx(da, db) else str(a.key) < str(b.key)
	)
	_assign_role_to_target(open_candidates, "open", total_area * 0.075, {})

static func _assign_role_to_target(candidates: Array, role: String,
		target_area: float, _unused_options: Dictionary) -> void:
	var assigned_area := 0.0
	for candidate_value in candidates:
		if assigned_area >= target_area:
			break
		var candidate: Dictionary = candidate_value
		if str(candidate.role) != "built":
			continue
		candidate.role = role
		assigned_area += SettlementPlan.polygon_area(candidate.poly)

static func _parcel_industry_score(parcel: Dictionary, plan: SettlementPlan) -> float:
	var center := _poly_center(parcel.poly)
	var best := center.distance_to(Vector2(4450.0, 5070.0))
	for reservation_value in plan.industrial_reservations:
		var reservation: Dictionary = reservation_value
		best = minf(best, center.distance_to((reservation.bb as Rect2).get_center()))
	return best

static func _subdivide_zone_face(poly: PackedVector2Array, key: String,
		depth: int) -> Array:
	var area := SettlementPlan.polygon_area(poly)
	var target := ZONE_PARCEL_TARGET_AREA * lerpf(0.86, 1.16,
		float(RoadHash.pick("%s|zone-target" % key, 1001)) / 1000.0)
	if area <= target or depth >= 4:
		return [poly]
	var bb := _bbox(poly)
	var cut_point := bb.get_center()
	var cut_tangent := Vector2.DOWN if bb.size.x >= bb.size.y else Vector2.RIGHT
	var along := Vector2(-cut_tangent.y, cut_tangent.x)
	cut_point += along * lerpf(-0.09, 0.09,
		float(RoadHash.pick("%s|zone-shift" % key, 1001)) / 1000.0) * maxf(bb.size.x, bb.size.y)
	var angle := lerpf(-0.13, 0.13,
		float(RoadHash.pick("%s|zone-angle" % key, 1001)) / 1000.0)
	cut_tangent = cut_tangent.rotated(angle)
	var pieces := _split_poly_by_line(poly, cut_point, cut_tangent)
	if pieces.size() < 2:
		return [poly]
	var out: Array = []
	for i in pieces.size():
		out.append_array(_subdivide_zone_face(pieces[i], "%s|%d" % [key, i], depth + 1))
	return out

static func _split_poly_by_line(poly: PackedVector2Array, point: Vector2,
		tangent: Vector2) -> Array:
	var span := _bbox(poly).size.length() * 4.0 + 120.0
	var direction := tangent.normalized()
	var normal := Vector2(-direction.y, direction.x)
	var a := point - direction * span
	var b := point + direction * span
	var half_a := PackedVector2Array([a, b, b + normal * span, a + normal * span])
	var half_b := PackedVector2Array([b, a, a - normal * span, b - normal * span])
	var out: Array = []
	for half in [half_a, half_b]:
		for piece_value in Geometry2D.intersect_polygons(poly, half):
			var piece: PackedVector2Array = piece_value
			if piece.size() >= 3 and SettlementPlan.polygon_area(piece) >= ZONE_PARCEL_MIN_AREA:
				out.append(piece)
	return out

static func _silkstown_diagnostics(plan: SettlementPlan) -> Dictionary:
	var nav := NavGrid.instance()
	var endpoint_distances: Array = []
	var water_samples := 0
	var water_points: Array = []
	var water_samples_by_street: Dictionary = {}
	var street_samples := 0
	var min_segment := INF
	for street_value in plan.decorative_streets:
		var street: Dictionary = street_value
		var points: PackedVector2Array = street.points
		var street_water_samples := 0
		for endpoint in [points[0], points[points.size() - 1]]:
			endpoint_distances.append(_nearest_road_distance(endpoint,
				plan.authoritative_roads))
		for i in range(points.size() - 1):
			var a := points[i]
			var b := points[i + 1]
			min_segment = minf(min_segment, a.distance_to(b))
			var count := maxi(1, ceili(a.distance_to(b) / 4.0))
			for sample in range(count + 1):
				var point := a.lerp(b, float(sample) / float(count))
				street_samples += 1
				if nav.is_ready():
					var cell := nav.cell_of(point)
					if nav.water(cell.x, cell.y) != NavGrid.WATER_LAND:
						water_samples += 1
						street_water_samples += 1
						if water_points.size() < 96:
							water_points.append([point.x, point.y])
		water_samples_by_street[str(street.get("key", "street"))] = street_water_samples
	var face_self_intersections := 0
	var face_records: Array = []
	var role_area := {"built": 0.0, "park": 0.0, "yard": 0.0, "open": 0.0}
	for face_value in plan.faces:
		var face: Dictionary = face_value
		if SettlementPlan.polygon_self_intersects(face.poly):
			face_self_intersections += 1
		var area := SettlementPlan.polygon_area(face.poly)
		var role := str(face.role)
		var center := _poly_center(face.poly)
		face_records.append({"key": str(face.key), "role": role,
			"area": area, "center": [center.x, center.y]})
	var parcel_records: Array = []
	for parcel_value in plan.parcels:
		var parcel: Dictionary = parcel_value
		var area := SettlementPlan.polygon_area(parcel.poly)
		var role := str(parcel.role)
		role_area[role] = float(role_area.get(role, 0.0)) + area
		var center := _poly_center(parcel.poly)
		parcel_records.append({"key": str(parcel.key), "face_key": str(parcel.face_key),
			"role": role, "area": area, "center": [center.x, center.y]})
	var enclosed_guides := 0
	for guide_value in plan.district_guides:
		var guide: Dictionary = guide_value
		for face_value in plan.faces:
			if Geometry2D.is_point_in_polygon(guide.point,
					(face_value as Dictionary).poly):
				enclosed_guides += 1
				break
	return {
		"endpoint_distances_to_real_roads": endpoint_distances,
		"max_endpoint_distance": endpoint_distances.max() if not endpoint_distances.is_empty() else INF,
		"street_samples": street_samples,
		"water_samples": water_samples,
		"water_samples_by_street": water_samples_by_street,
		"water_points": water_points,
		"minimum_street_segment": min_segment,
		"face_self_intersections": face_self_intersections,
		"face_records": face_records,
		"parcel_records": parcel_records,
		"role_area": role_area,
		"enclosed_district_guides": enclosed_guides,
		"required_enclosed_district_guides": 2,
		"geometry_errors": Array(plan.validate_geometry()),
	}

static func _catmull_path(control: PackedVector2Array, steps: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	if control.size() < 2:
		return control
	for i in range(control.size() - 1):
		var p0 := control[maxi(0, i - 1)]
		var p1 := control[i]
		var p2 := control[i + 1]
		var p3 := control[mini(control.size() - 1, i + 2)]
		for step in range(0 if i == 0 else 1, steps + 1):
			var t := float(step) / float(steps)
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t
				+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
				+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	return out

static func _extent_from_street(street: PackedVector2Array,
		outer: PackedVector2Array) -> PackedVector2Array:
	var poly := street.duplicate()
	for point in outer:
		poly.append(point)
	return poly

static func _road_corridors(roads: Array) -> Array:
	var raw: Array = []
	for road_value in roads:
		var road: Dictionary = road_value
		var half_width := MapStyle.road_width(bool(road.get("trunk", false))) * 0.5 + AUTHORITATIVE_ROAD_MARGIN
		raw.append({"poly": _segment_quad(road.a, road.b, half_width),
			"bb": _bbox(_segment_quad(road.a, road.b, half_width))})
	return _merge_exclusions(raw)

static func _polyline_corridors(points: PackedVector2Array, half_width: float) -> Array:
	var raw: Array = []
	for i in range(points.size() - 1):
		var tangent := (points[i + 1] - points[i]).normalized()
		if tangent == Vector2.ZERO:
			continue
		var poly := _segment_quad(points[i] - tangent * half_width,
			points[i + 1] + tangent * half_width, half_width)
		raw.append({"poly": poly, "bb": _bbox(poly)})
	return _merge_exclusions(raw)

static func _merge_exclusions(exclusions: Array) -> Array:
	var polys: Array = []
	for exclusion_value in exclusions:
		polys.append((exclusion_value as Dictionary).poly)
	var merged := _merge_polys(polys)
	var out: Array = []
	for poly_value in merged:
		var poly: PackedVector2Array = poly_value
		out.append({"poly": poly, "bb": _bbox(poly)})
	return out

static func _merge_polys(polys: Array) -> Array:
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

static func _clip_polys(polys: Array, exclusions: Array, min_area: float) -> Array:
	var pieces: Array = polys.duplicate()
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

static func _nearest_road_distance(point: Vector2, roads: Array) -> float:
	var best := INF
	for road_value in roads:
		var road: Dictionary = road_value
		best = minf(best, _point_segment_distance(point, road.a, road.b))
	return best

static func _point_segment_distance(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	if ab.length_squared() <= 0.0001:
		return point.distance_to(a)
	var t := clampf((point - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return point.distance_to(a + ab * t)

static func _segment_quad(a: Vector2, b: Vector2, half_width: float) -> PackedVector2Array:
	var tangent := (b - a).normalized()
	var normal := Vector2(-tangent.y, tangent.x) * half_width
	return PackedVector2Array([a - normal, b - normal, b + normal, a + normal])

static func _rect_poly(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y),
		rect.end, Vector2(rect.position.x, rect.end.y)])

static func _bbox(poly: PackedVector2Array) -> Rect2:
	var lo := poly[0]
	var hi := poly[0]
	for point in poly:
		lo = lo.min(point)
		hi = hi.max(point)
	return Rect2(lo, hi - lo)

static func _poly_center(poly: PackedVector2Array) -> Vector2:
	var center := Vector2.ZERO
	for point in poly:
		center += point
	return center / maxf(1.0, float(poly.size()))
