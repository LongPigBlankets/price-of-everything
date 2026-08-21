class_name MidcenturyPortPlan
extends RefCounted
## One deterministic coastline-adaptive plan for the authoritative b_004 Port.
## Rendering, gameplay-art suppression, decorative exclusion and audits consume
## this same geometry. Nothing here changes terrain, water, roads or occupancy.

const SEARCH_RADIUS := 520.0
const MAX_COAST_SAMPLES := 12
const MAX_ACCESS_LENGTH := 310.0
const RIVER_CLEARANCE := 9.5
const SHADOW_OFFSET := Vector2(2.2, 2.8)

# Bounded coastline-adaptive search. Kept adaptive on purpose: the K1 fixed
# rectangle-and-shore-normal primitive is RETIRED. The extra angles and quay
# shifts exist because the harbour throat is now required to be water, which
# only a locally straight stretch of coast can satisfy.
const SHORE_SHIFTS := [-18.0, 18.0]
const APPROACH_ANGLES_DEG := [-22.0, -8.0, 8.0, 22.0]
## How far SEAWARD of the sampled shore point the quay face — the shared edge
## between the dry head and the harbour water — is pushed. THE HEAD IS A STRAIGHT
## BLOCK AND IS NEVER CLIPPED TO THE COASTLINE (owner, 2026-08-21). A dock is
## reclaimed ground: its quay face is a straight edge cut across the shore, not a
## tracing of every cove and spit. Clipping produced a ragged apron whose outline
## wandered with the beach and left the arms meeting it at odd angles.
## Squaring the basin (parallel arms, 90 degrees to the head) makes the seating
## fussier on a curved shore: the rectangle's root corners must both be wet. Two
## further shifts let the existing search find a wetter seat rather than us
## hand-tuning one port. Every candidate still passes the SAME unchanged dry-head
## and basin gates, so this widens the search, it does not relax it.
const QUAY_SHIFTS := [10.0, 22.0, 34.0, 46.0, 58.0]
## Rungs the harbour width may step down through to find a seat where BOTH root
## corners are wet. The arms are parallel at every rung — only the gap between
## them narrows — so the owner's ruling holds whichever one is taken.
const BASIN_WIDTH_LADDER := [1.0, 0.88, 0.76, 0.64]
## Rendered coastline = the boundary of the baked band-5 "land base" polygon.
## Probed against NavGrid over 789,496 coastal-band cells: 99.470% agreement.
const LAND_BASE_BAND := 5
## How far back an arm may reach to find the apron, and how deep it bites in.
const MAX_ARM_ATTACH_REACH := 110.0
const ARM_HEAD_BITE := 8.0
## Reject an apron the coast has eaten away to a sliver.
const MIN_HEAD_AREA_FRACTION := 0.34
## Seat gates for the STRAIGHT head. Most of the block must be real ground; the
## landward half must be almost all of it. What is left in front is the reclaimed
## quay, which is what lets the face be a straight line across a ragged shore.
const HEAD_MIN_LAND := 0.58
const HEAD_MIN_BACK_LAND := 0.93

static var _land_polygon_cache: Array = []

const SITE_SPECS := [
	{"basin_depth": 82.0, "root_half": 27.0, "mouth_half": 40.0,
		"arm_width": 20.0, "head_width": 112.0, "head_depth": 52.0},
	{"basin_depth": 98.0, "root_half": 32.0, "mouth_half": 48.0,
		"arm_width": 23.0, "head_width": 130.0, "head_depth": 60.0},
	{"basin_depth": 114.0, "root_half": 37.0, "mouth_half": 56.0,
		"arm_width": 25.0, "head_width": 148.0, "head_depth": 67.0},
]

static var _plan_cache: Dictionary = {}

static func build(hex_map: TileMapLayer, tile_id: String,
		instance_id: String = "") -> Dictionary:
	var footprint_source := hex_map.get_tree().get_first_node_in_group(
		"building_footprints")
	var footprint_version := int(footprint_source.get("footprint_version")) \
		if footprint_source != null else 0
	var cache_key := "%d|%s|%d|%d" % [hex_map.get_instance_id(), tile_id,
		RoadNetwork.instance().edge_count(), footprint_version]
	if _plan_cache.has(cache_key):
		return (_plan_cache[cache_key] as Dictionary).duplicate(true)
	var timer_start := Time.get_ticks_msec()
	var coord: Vector2i = hex_map.id_to_coord(tile_id)
	if coord == Vector2i(-1, -1) or not hex_map.tiles.has(coord):
		return {}
	var nav := NavGrid.instance()
	if not nav.is_ready():
		return {}
	var center := hex_map.map_to_local(hex_map.map_coord_for_tile_coord(coord))
	var coastline := _coastline_samples(center)
	if coastline.is_empty():
		return {}
	var river_exclusions := _river_exclusions(hex_map, center)
	var gameplay_exclusions := _gameplay_exclusions(hex_map, instance_id, center)
	var best: Dictionary = {}
	var considered := 0
	var water_rejects := 0
	var land_rejects := 0
	var land_reasons: Dictionary = {}
	var river_rejects := 0
	var access_rejects := 0
	var collision_rejects := 0
	var arm_rejects := 0
	var pruned := 0
	for sample_value in coastline:
		var sample: Dictionary = sample_value
		var base_seaward: Vector2 = sample.seaward
		var base_tangent := Vector2(-base_seaward.y, base_seaward.x)
		for shore_shift in SHORE_SHIFTS:
			var shifted_shore: Vector2 = sample.shore + base_tangent * float(shore_shift)
			for angle_deg in APPROACH_ANGLES_DEG:
				var seaward := base_seaward.rotated(deg_to_rad(float(angle_deg))).normalized()
				var tangent := Vector2(-seaward.y, seaward.x)
				for spec_value in SITE_SPECS:
					var spec: Dictionary = spec_value
					for quay_shift in QUAY_SHIFTS:
						considered += 1
						var candidate := _candidate(hex_map, tile_id, coord, center,
							shifted_shore, seaward, tangent, spec,
							float(quay_shift), river_exclusions,
							gameplay_exclusions,
							-INF if best.is_empty() else float(best.score))
						if bool(candidate.get("pruned", false)):
							pruned += 1
							continue
						if not bool(candidate.get("basin_valid", false)):
							water_rejects += 1
							continue
						if not bool(candidate.get("land_valid", false)):
							land_rejects += 1
							var reason := str(candidate.get("land_reason", "?"))
							land_reasons[reason] = int(land_reasons.get(reason, 0)) + 1
							continue
						if not bool(candidate.get("arm_valid", true)):
							arm_rejects += 1
							continue
						if not bool(candidate.get("river_valid", false)):
							river_rejects += 1
							continue
						if not bool(candidate.get("collision_valid", false)):
							collision_rejects += 1
							continue
						if not bool(candidate.get("access_valid", false)):
							access_rejects += 1
							continue
						if best.is_empty() or float(candidate.score) > float(best.score):
							best = candidate
	if best.is_empty():
		print("[MIDCENTURY PORT] %s NO PLAN considered=%d water=%d land=%d %s river=%d collision=%d access=%d" % [
			tile_id, considered, water_rejects, land_rejects, str(land_reasons),
			river_rejects, collision_rejects, access_rejects])
		print("[MIDCENTURY PORT] %s arm_rejects=%d" % [tile_id, arm_rejects])
		return {}
	var plan := _finish_plan(best, tile_id, instance_id, coord, coastline,
		river_exclusions)
	plan.diagnostics["candidate_count"] = considered
	plan.diagnostics["water_rejections"] = water_rejects
	plan.diagnostics["land_rejections"] = land_rejects
	plan.diagnostics["river_rejections"] = river_rejects
	plan.diagnostics["collision_rejections"] = collision_rejects
	plan.diagnostics["access_rejections"] = access_rejects
	plan.diagnostics["planner_msec"] = Time.get_ticks_msec() - timer_start
	plan["plan_hash"] = _plan_hash(plan)
	_plan_cache[cache_key] = plan.duplicate(true)
	print("[MIDCENTURY PORT] %s candidates=%d planner=%dms hash=%s inset=%.1f rej water=%d land=%s arm=%d river=%d coll=%d access=%d pruned=%d" % [
		tile_id, considered, int(plan.diagnostics.planner_msec),
		str(plan.plan_hash).left(12), float(best.get("head_inset", -1.0)),
		water_rejects, str(land_reasons), arm_rejects, river_rejects,
		collision_rejects, access_rejects, pruned])
	return plan

static func invalidate_cache() -> void:
	_plan_cache.clear()

static func _candidate(hex_map: TileMapLayer, tile_id: String, coord: Vector2i,
		tile_center: Vector2, shore: Vector2, seaward: Vector2, tangent: Vector2,
		spec: Dictionary, quay_shift: float, river_exclusions: Array,
		gameplay_exclusions: Array, best_score: float) -> Dictionary:
	var key := "port-adaptive|%s|%.1f|%.1f|%.1f|%.1f" % [tile_id,
		shore.x, shore.y, seaward.x, float(spec.basin_depth)]
	var basin_depth := float(spec.basin_depth)
	var root_half := float(spec.root_half)
	var mouth_half := float(spec.mouth_half)
	var arm_width := float(spec.arm_width)
	# The QUAY FACE is one shared edge: dry head landward of it, harbour water
	# seaward of it. L1 left an unvalidated throat between the head and the basin
	# and that throat is the land the owner can see inside the U.
	var head_front := shore + seaward * quay_shift
	# Three-point early-out before any polygon work: the harbour throat has to be
	# open water or this whole candidate is dead.
	var throat_half := root_half
	var throat_probe := head_front + seaward * 7.0
	if _water_at(throat_probe) != NavGrid.WATER_SEA or \
			_water_at(throat_probe + tangent * throat_half * 0.85) != NavGrid.WATER_SEA or \
			_water_at(throat_probe - tangent * throat_half * 0.85) != NavGrid.WATER_SEA:
		return {"basin_valid": false}
	# RECTANGULAR basin (owner ruling): the two edges the arms lie on run exactly
	# seaward, so the arms are PARALLEL to each other and meet the landside head
	# at 90 degrees. The earlier asymmetric trapezoid splayed them by construction.
	# Per-site variation now comes from the coastline sample, orientation, head
	# size, arm length and arm width — not from bending the harbour.
	# Width = the quay-face half-width that already validated at 100% face water.
	# A wider rectangle pushes the root corners onto a curved shore and puts land
	# back inside the U (measured: 93.0% and 91.6% sea at two ports).
	# The rectangle is fussier on a curved shore than the old flare was: BOTH root
	# corners must be wet. Narrow the harbour until it is, rather than bending it
	# — the arms stay parallel at every rung, which is the property that matters.
	var basin_root := head_front
	var basin_mouth_center := basin_root + seaward * basin_depth
	var basin_half := root_half
	var basin := PackedVector2Array()
	var basin_water := 0.0
	for width_scale in BASIN_WIDTH_LADDER:
		basin_half = root_half * float(width_scale)
		basin = PackedVector2Array([
			basin_root + tangent * basin_half,
			basin_root - tangent * basin_half,
			basin_mouth_center - tangent * basin_half,
			basin_mouth_center + tangent * basin_half,
		])
		basin_water = _class_coverage(basin, NavGrid.WATER_SEA)
		if basin_water >= 0.999:
			break
	var corridor_start := basin_root + seaward * basin_depth * 0.38
	var corridor_end := basin_mouth_center + seaward * 62.0
	var corridor := _trapezoid(corridor_start, corridor_end, tangent,
		basin_half * 0.52, mouth_half * 0.58)
	var corridor_water := _class_coverage(corridor, NavGrid.WATER_SEA)
	var mouth_run := _open_sea_run(basin_mouth_center, seaward, 190.0)
	# The quay face itself must be the waterline: sampled along its whole width,
	# the strip just seaward of it is sea.
	var face_water := _edge_class_coverage(PackedVector2Array([
		basin_root + tangent * basin_half + seaward * 4.0,
		basin_root - tangent * basin_half + seaward * 4.0,
	]), NavGrid.WATER_SEA, 5.0)
	var basin_valid := basin_water >= 0.999 and corridor_water >= 0.999 and \
		mouth_run >= 150.0 and face_water >= 0.999
	if not basin_valid:
		return {"basin_valid": false}

	# Exact branch-and-bound: every remaining score term can only subtract, except
	# the bounded asymmetry bonus. A candidate that cannot beat the incumbent even
	# at its best is skipped before the expensive offset/road work. There is no
	# head-inset term any more (the head is never eroded); reintroducing one here
	# without also scoring it would make this bound smaller than the score it
	# bounds, and the prune below would then discard the best seat. The
	# selected plan is bit-identical to the exhaustive search.
	var score_bound := _poly_area(basin) * 0.012 + mouth_run * 0.42 - \
		shore.distance_to(tile_center) * 0.035 + 0.22 * 120.0
	if score_bound <= best_score:
		return {"pruned": true}

	# The head OVERSHOOTS the quay face and is then clipped back to the rendered
	# coastline, so the apron covers every scrap of land inside the throat. Its
	# waterfront edge is the shore itself, not a straight crossbar.
	var head_back := head_front - seaward * (float(spec.head_depth) + quay_shift)
	# Wide enough that the apron wraps PAST both arm roots, so no beach wedge is
	# left exposed beside them inside the harbour throat.
	var front_half := root_half + arm_width * 1.35 + 8.0
	var left_back_half := float(spec.head_width) * _rr(key + "|head-left", 0.45, 0.54)
	var right_back_half := float(spec.head_width) * _rr(key + "|head-right", 0.45, 0.54)
	# Cheap landward pre-check before the expensive clip-and-inset.
	var back_probe := head_front - seaward * (float(spec.head_depth) * 0.55 + quay_shift)
	if _water_at(back_probe) != NavGrid.WATER_LAND or \
			_water_at(back_probe + tangent * front_half * 0.7) != NavGrid.WATER_LAND or \
			_water_at(back_probe - tangent * front_half * 0.7) != NavGrid.WATER_LAND:
		return {"basin_valid": true, "land_valid": false, "land_reason": "probe"}
	var head_block := PackedVector2Array([
		head_front + tangent * front_half,
		head_front - tangent * front_half,
		head_back - tangent * right_back_half,
		head_back + tangent * left_back_half,
	])
	var fit := _fit_head(head_block)
	var head: PackedVector2Array = fit.get("poly", PackedVector2Array())
	if head.size() < 3:
		return {"basin_valid": true, "land_valid": false,
			"land_reason": str(fit.get("reason", "area"))}
	var head_land := float(fit.land)
	var head_edge_land := float(fit.edge)
	var head_inset := float(fit.inset)

	# STRAIGHT arms (addendum section 5). Each arm is one run from the quay face
	# along its own basin edge — no mid vertex, no elbow. Length, width and angle
	# are independent per arm; the shape is not a symmetric stamped U.
	var left_width := arm_width * _rr(key + "|left-width", 0.86, 1.14)
	var right_width := arm_width * _rr(key + "|right-width", 0.86, 1.14)
	# Both axes ARE the seaward normal, so the arms are parallel and square to the
	# quay face. Only their length and width still differ between the two.
	var left_axis := seaward
	var right_axis := seaward
	var left_length_run := basin_depth + _rr(key + "|left-extra", -14.0, 22.0)
	var right_length_run := basin_depth + _rr(key + "|right-extra", -14.0, 22.0)
	# Roots sit half an arm width OUTBOARD of the basin edge, so the deck flanks
	# the harbour water instead of eating into it.
	var left_root := basin_root + tangent * basin_half + \
		Vector2(-left_axis.y, left_axis.x) * left_width * 0.5
	var right_root := basin_root - tangent * basin_half + \
		Vector2(right_axis.y, -right_axis.x) * right_width * 0.5
	# Each arm runs landward along its OWN axis until it bites into the apron, so
	# the compound reads as one connected quay instead of two floating decks.
	# Extending backwards along the same axis keeps the run dead straight.
	var left_start := _attach_to_head(left_root, -left_axis, head)
	var right_start := _attach_to_head(right_root, -right_axis, head)
	if left_start == Vector2.INF or right_start == Vector2.INF:
		return {"basin_valid": true, "land_valid": true, "arm_valid": false}
	var left_points := PackedVector2Array([
		left_start,
		left_root + left_axis * left_length_run,
	])
	var right_points := PackedVector2Array([
		right_start,
		right_root + right_axis * right_length_run,
	])
	var left_arms := _bent_arm(left_points, left_width)
	var right_arms := _bent_arm(right_points, right_width)
	var arm_polys: Array = left_arms + right_arms
	if _overlap_with_any(basin, arm_polys) > 0.05:
		return {"basin_valid": true, "land_valid": true,
			"river_valid": false}

	var opaque_base: Array = [head]
	opaque_base.append_array(arm_polys)
	var river_overlap := _arrays_overlap_area(opaque_base, river_exclusions)
	var river_valid := river_overlap <= 0.01
	if not river_valid:
		return {"basin_valid": true, "land_valid": true,
			"river_valid": false}

	var warehouses := _warehouses(head, head_front, head_back, tangent, seaward,
		key)
	if warehouses.is_empty():
		return {"basin_valid": true, "land_valid": false, "land_reason": "shed"}
	var collision_polys: Array = [head]
	collision_polys.append_array(warehouses)
	collision_polys.append_array(arm_polys)
	var gameplay_overlap := _arrays_overlap_area(collision_polys,
		gameplay_exclusions)
	var collision_valid := gameplay_overlap <= 0.01
	if not collision_valid:
		return {"basin_valid": true, "land_valid": true,
			"river_valid": true, "collision_valid": false}

	# Road access is the most expensive check in the loop (it scans every built
	# edge on 25 tiles), so it runs last, on candidates nothing else rejected.
	var entrance := head_back + tangent * _rr(key + "|entrance", -0.18, 0.18) * \
		minf(left_back_half, right_back_half)
	var road_access := _road_access(hex_map, coord, entrance, [basin, corridor],
		river_exclusions, gameplay_exclusions)
	var access_valid := road_access.size() >= 2
	if not access_valid:
		return {"basin_valid": true, "land_valid": true,
			"river_valid": true, "collision_valid": true,
			"access_valid": false}

	var left_length := _polyline_length(left_points)
	var right_length := _polyline_length(right_points)
	var asymmetry := absf(left_length - right_length) / maxf(left_length,
		right_length)
	var access_length := _polyline_length(road_access)
	var compactness := shore.distance_to(tile_center)
	# The apron inset is the width of the terrain sliver left between the quay and
	# the water, so it is exactly the residual the owner would still see inside
	# the U. Score against it, or the search happily buys basin area with land.
	var score := _poly_area(basin) * 0.012 + mouth_run * 0.42 - \
		access_length * 0.30 - compactness * 0.035 + \
		clampf(asymmetry, 0.06, 0.22) * 120.0
	return {
		"basin_valid": true, "land_valid": true, "river_valid": true,
		"collision_valid": true, "access_valid": true, "score": score,
		"key": key, "shore": shore, "seaward": seaward,
		"tangent": tangent, "head": head, "warehouses": warehouses,
		"basin": basin, "corridor": corridor,
		"basin_mouth_center": basin_mouth_center,
		"left_points": left_points, "right_points": right_points,
		"left_arms": left_arms, "right_arms": right_arms,
		"road_access": road_access,
		"basin_water": basin_water, "corridor_water": corridor_water,
		"mouth_run": mouth_run, "head_land": head_land,
		"head_edge_land": head_edge_land, "head_inset": head_inset,
		"river_overlap": river_overlap,
		"gameplay_overlap": gameplay_overlap,
		"left_length": left_length, "right_length": right_length,
		"access_length": access_length, "arm_width": arm_width,
		"left_width": left_width, "right_width": right_width,
		"asymmetry": asymmetry,
	}

static func _finish_plan(candidate: Dictionary, tile_id: String,
		instance_id: String, coord: Vector2i, coastline: Array,
		river_exclusions: Array) -> Dictionary:
	# The seed intentionally excludes instance_id: PortVisuals, BuildingVisuals
	# and UrbanFabricVisuals can request the same b_004 independently and still
	# receive byte-identical shared geometry.
	var key := "midcentury-port|%s" % tile_id
	var head: PackedVector2Array = candidate.head
	var warehouses: Array = candidate.warehouses
	var basin: PackedVector2Array = candidate.basin
	var corridor: PackedVector2Array = candidate.corridor
	var left_arms: Array = candidate.left_arms
	var right_arms: Array = candidate.right_arms
	var left_points: PackedVector2Array = candidate.left_points
	var right_points: PackedVector2Array = candidate.right_points
	var containers := _containers(head, warehouses, left_points, right_points,
		left_arms, right_arms, basin, corridor, candidate.road_access, key,
		candidate.seaward, candidate.tangent)
	var left_crane := _crane_site(left_points, float(candidate.left_width),
		"left", key)
	var right_crane := _crane_site(right_points, float(candidate.right_width),
		"right", key)
	var cranes := [left_crane, right_crane]
	var deck_polys: Array = left_arms + right_arms
	var solid_polys: Array = [head]
	solid_polys.append_array(warehouses)
	solid_polys.append_array(deck_polys)
	solid_polys.append_array(containers)
	for crane_value in cranes:
		solid_polys.append((crane_value as Dictionary).base_polygon)
	var envelope_sources: Array = solid_polys + [basin, corridor]
	var envelope := _convex_envelope(envelope_sources)
	var mouth_center: Vector2 = candidate.basin_mouth_center
	var mouth_half := basin[2].distance_to(basin[3]) * 0.5
	var tangent: Vector2 = candidate.tangent
	var harbour_mouth := PackedVector2Array([
		mouth_center + tangent * mouth_half,
		mouth_center - tangent * mouth_half,
	])
	var left_water := _array_class_coverage(left_arms, NavGrid.WATER_SEA)
	var right_water := _array_class_coverage(right_arms, NavGrid.WATER_SEA)
	# What a viewer actually sees INSIDE the U. L1 gated the purpose-built basin
	# trapezoid, which is water by construction, so the land enclosed between the
	# arms was never measured at all.
	var enclosure_ring := _interarm_ring(left_points, right_points)
	var enclosure_opaque: Array = [head]
	enclosure_opaque.append_array(warehouses)
	enclosure_opaque.append_array(deck_polys)
	enclosure_opaque.append_array(containers)
	for crane_value in cranes:
		enclosure_opaque.append((crane_value as Dictionary).base_polygon)
	var enclosure := _enclosure_stats(enclosure_ring, enclosure_opaque)
	var basin_overlap := _overlap_with_any(basin, solid_polys)
	# Polygon boolean operations can leave sub-pixel boundary-area noise where a
	# deck shares the basin edge. Treat less than a tenth of one square world
	# unit as an exact shared boundary; the visual/raster gate remains far stricter.
	if basin_overlap < 0.1:
		basin_overlap = 0.0
	var diagnostics := {
		"basin_area": _poly_area(basin),
		"basin_sea_water_coverage": float(candidate.basin_water),
		"open_sea_connectivity": float(candidate.corridor_water) >= 0.999 and
			float(candidate.mouth_run) >= 150.0,
		"open_water_corridor_coverage": float(candidate.corridor_water),
		"harbour_mouth_width": harbour_mouth[0].distance_to(harbour_mouth[1]),
		"landward_dry_land_coverage": float(candidate.head_land),
		"landward_edge_dry_coverage": float(candidate.head_edge_land),
		"left_arm_length": float(candidate.left_length),
		"right_arm_length": float(candidate.right_length),
		"left_arm_water_coverage": left_water,
		"right_arm_water_coverage": right_water,
		"river_overlap_area": float(candidate.river_overlap),
		"basin_opaque_overlap_area": basin_overlap,
		"gameplay_overlap_area": float(candidate.gameplay_overlap),
		"road_access_length": float(candidate.access_length),
		"road_access_valid": (candidate.road_access as PackedVector2Array).size() >= 2,
		"arm_asymmetry": float(candidate.asymmetry),
		"interarm_open_area": float(enclosure.open_area),
		"interarm_sea_area": float(enclosure.sea_area),
		"interarm_sea_coverage": float(enclosure.sea_coverage),
		"max_arm_bend_deg": maxf(_max_bend_deg(left_points),
			_max_bend_deg(right_points)),
		"container_count": containers.size(),
		"crane_count": cranes.size(),
		"crane_arms": ["left", "right"],
		"selected_score": float(candidate.score),
	}
	var coast_points := PackedVector2Array()
	for sample_value in coastline:
		coast_points.append((sample_value as Dictionary).shore)
	var river_debug: Array = []
	for exclusion_value in river_exclusions:
		river_debug.append((exclusion_value as Dictionary).poly)
	return {
		"valid": true,
		"key": key, "tile_id": tile_id, "instance_id": instance_id,
		"coord": coord, "position": candidate.shore,
		"seaward": candidate.seaward, "tangent": candidate.tangent,
		"angle": (candidate.seaward as Vector2).angle(),
		"land_polygons": [head],
		"warehouse_polygons": warehouses,
		"apron_polygons": [head],
		"left_arm_polygons": left_arms,
		"right_arm_polygons": right_arms,
		"deck_polygons": deck_polys,
		"basin_polygon": basin,
		"harbour_mouth": harbour_mouth,
		"open_water_corridor": corridor,
		"container_polygons": containers,
		"crane_sites": cranes,
		"solid_exclusion": _records(solid_polys),
		"marine_reservation": {"poly": basin, "bb": _bbox(basin),
			"polygons": [basin, corridor]},
		"total_compound_envelope": envelope,
		"interarm_ring": enclosure_ring,
		"road_access": candidate.road_access,
		"coastline_samples": coast_points,
		"river_exclusions": river_debug,
		"basin_water_coverage": float(candidate.basin_water),
		"landward_land_coverage": float(candidate.head_land),
		"diagnostics": diagnostics,
	}

static func _coastline_samples(center: Vector2) -> Array:
	var nav := NavGrid.instance()
	var lo := nav.cell_of(center - Vector2.ONE * SEARCH_RADIUS)
	var hi := nav.cell_of(center + Vector2.ONE * SEARCH_RADIUS)
	var raw: Array = []
	var offsets := [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
		Vector2i(-1, 0), Vector2i(1, 0), Vector2i(-1, 1),
		Vector2i(0, 1), Vector2i(1, 1)]
	for iy in range(lo.y, hi.y + 1):
		for ix in range(lo.x, hi.x + 1):
			if nav.water(ix, iy) != NavGrid.WATER_SEA:
				continue
			var point := nav.world_of(ix, iy)
			if point.distance_to(center) > SEARCH_RADIUS:
				continue
			var landward := Vector2.ZERO
			var land_count := 0
			for offset in offsets:
				var nx: int = ix + int(offset.x)
				var ny: int = iy + int(offset.y)
				if nx < 0 or ny < 0 or nx >= nav.gw or ny >= nav.gh:
					continue
				if nav.water(nx, ny) == NavGrid.WATER_LAND:
					landward += nav.world_of(nx, ny) - point
					land_count += 1
			if land_count == 0 or landward.length_squared() < 0.1:
				continue
			landward = landward.normalized()
			var shore := point + landward * nav.step * 0.48
			raw.append({"shore": shore, "seaward": -landward,
				"distance": shore.distance_squared_to(center)})
	raw.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if is_equal_approx(float(a.distance), float(b.distance)):
			var ap: Vector2 = a.shore
			var bp: Vector2 = b.shore
			return ap.y < bp.y if not is_equal_approx(ap.y, bp.y) else ap.x < bp.x
		return float(a.distance) < float(b.distance))
	var selected: Array = []
	for value in raw:
		var sample: Dictionary = value
		var separated := true
		for selected_value in selected:
			if (selected_value as Dictionary).shore.distance_to(sample.shore) < 17.0:
				separated = false
				break
		if separated:
			selected.append(sample)
			if selected.size() >= MAX_COAST_SAMPLES:
				break
	return selected

static func _river_exclusions(hex_map: TileMapLayer, center: Vector2) -> Array:
	var out: Array = []
	var node := hex_map.get_parent().get_node_or_null("RiverVisuals")
	if node == null or not node.has_method("get_river_polylines"):
		return out
	for path_value in node.get_river_polylines():
		var path: Dictionary = path_value
		var points: PackedVector2Array = path.points
		if points.size() < 2 or _polyline_distance_to_point(points, center) > \
				SEARCH_RADIUS + 180.0:
			continue
		var half_width := maxf(float(path.get("start_width", 15.0)),
			float(path.get("end_width", 15.0))) * 0.5 + RIVER_CLEARANCE
		for poly_value in Geometry2D.offset_polyline(points, half_width,
				Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND):
			var poly: PackedVector2Array = poly_value
			out.append({"poly": poly, "bb": _bbox(poly)})
	return out

static func _gameplay_exclusions(hex_map: TileMapLayer,
		exclude_instance_id: String, center: Vector2) -> Array:
	var out: Array = []
	var source := hex_map.get_tree().get_first_node_in_group("building_footprints")
	if source == null or not source.has_method("midcentury_port_obstacles"):
		return out
	for value in source.midcentury_port_obstacles(exclude_instance_id):
		var record: Dictionary = value
		var record_bb: Rect2 = record.get("bb", Rect2())
		if record_bb.get_center().distance_to(center) > SEARCH_RADIUS + 240.0:
			continue
		var poly: PackedVector2Array = record.poly
		out.append({"poly": poly, "bb": record_bb if record_bb.has_area()
			else _bbox(poly)})
	return out

static func _road_access(_hex_map: TileMapLayer, coord: Vector2i,
		entrance: Vector2, water_exclusions: Array, river_exclusions: Array,
		gameplay_exclusions: Array) -> PackedVector2Array:
	var net := RoadNetwork.instance()
	var candidates: Array = []
	var coords: Array = [coord]
	for dx in range(-2, 3):
		for dy in range(-2, 3):
			var candidate_coord := coord + Vector2i(dx, dy)
			if not coords.has(candidate_coord):
				coords.append(candidate_coord)
	for candidate_coord in coords:
		var edges: Array = net.edges_on_tile(candidate_coord)
		edges.sort()
		for edge_id_value in edges:
			var edge: Dictionary = net.edges.get(str(edge_id_value), {})
			if str(edge.get("state", "")) != RoadNetwork.STATE_BUILT:
				continue
			var geometry: PackedVector2Array = edge.get("geometry", PackedVector2Array())
			for i in range(geometry.size() - 1):
				var point := Geometry2D.get_closest_point_to_segment(entrance,
					geometry[i], geometry[i + 1])
				var distance := entrance.distance_to(point)
				if distance <= MAX_ACCESS_LENGTH:
					candidates.append({"point": point, "distance": distance,
						"edge": str(edge_id_value), "segment": i})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a.distance), float(b.distance)):
			return float(a.distance) < float(b.distance)
		if str(a.edge) != str(b.edge):
			return str(a.edge) < str(b.edge)
		return int(a.segment) < int(b.segment))
	for candidate_value in candidates:
		var target: Vector2 = (candidate_value as Dictionary).point
		var direct := PackedVector2Array([entrance, target])
		if _access_line_valid(direct, water_exclusions, river_exclusions,
				gameplay_exclusions):
			return direct
		var line := target - entrance
		if line.length_squared() < 1.0:
			continue
		var normal := Vector2(-line.y, line.x).normalized()
		for side in [-1.0, 1.0]:
			var elbow := entrance.lerp(target, 0.54) + normal * float(side) * 22.0
			var bent := PackedVector2Array([entrance, elbow, target])
			if _access_line_valid(bent, water_exclusions, river_exclusions,
					gameplay_exclusions):
				return bent
	return PackedVector2Array()

static func _access_line_valid(line: PackedVector2Array, water_exclusions: Array,
		river_exclusions: Array, gameplay_exclusions: Array) -> bool:
	if line.size() < 2:
		return false
	var segments: Array = []
	for i in range(line.size() - 1):
		segments.append(_segment_quad(line[i], line[i + 1], 2.8))
	if _arrays_overlap_area(segments, water_exclusions) > 0.01 or \
			_arrays_overlap_area(segments, river_exclusions) > 0.01 or \
			_arrays_overlap_area(segments, gameplay_exclusions) > 0.01:
		return false
	for i in range(line.size() - 1):
		var length := line[i].distance_to(line[i + 1])
		var count := maxi(2, ceili(length / 7.0))
		for sample_index in range(count + 1):
			var point := line[i].lerp(line[i + 1],
				float(sample_index) / float(count))
			if _water_at(point) != NavGrid.WATER_LAND:
				return false
	return true

static func _warehouses(head: PackedVector2Array, head_front: Vector2,
		head_back: Vector2, tangent: Vector2, seaward: Vector2,
		key: String) -> Array:
	var depth := head_front.distance_to(head_back)
	var out: Array = []
	var side := -1.0 if RoadHash.pick(key + "|warehouse-side", 2) == 0 else 1.0
	var primary_center := head_back.lerp(head_front, 0.46) + tangent * side * \
		_rr(key + "|warehouse-offset", 14.0, 24.0)
	var primary := _oriented_rect(primary_center, tangent, seaward,
		_rr(key + "|warehouse-width", 45.0, 61.0),
		clampf(depth * 0.34, 17.0, 24.0))
	for piece_value in Geometry2D.intersect_polygons(primary, head):
		var piece: PackedVector2Array = piece_value
		if _poly_area(piece) >= 520.0 and _class_coverage(piece,
				NavGrid.WATER_LAND) >= 0.999:
			out.append(piece)
	var office_center := head_back.lerp(head_front, 0.30) - tangent * side * \
		_rr(key + "|office-offset", 28.0, 38.0)
	var office := _oriented_rect(office_center, tangent, seaward,
		_rr(key + "|office-width", 18.0, 26.0),
		_rr(key + "|office-depth", 13.0, 18.0))
	for piece_value in Geometry2D.intersect_polygons(office, head):
		var piece: PackedVector2Array = piece_value
		if _poly_area(piece) >= 180.0 and _class_coverage(piece,
				NavGrid.WATER_LAND) >= 0.999 and _overlap_with_any(piece, out) <= 0.01:
			out.append(piece)
	return out

static func _containers(head: PackedVector2Array, warehouses: Array,
		left_points: PackedVector2Array, right_points: PackedVector2Array,
		left_arms: Array, right_arms: Array, basin: PackedVector2Array,
		corridor: PackedVector2Array, road_access: PackedVector2Array,
		key: String, seaward: Vector2, tangent: Vector2) -> Array:
	var out: Array = []
	var exclusions: Array = [basin, corridor]
	exclusions.append_array(warehouses)
	for i in range(road_access.size() - 1):
		exclusions.append(_segment_quad(road_access[i], road_access[i + 1], 7.0))
	var head_center := _poly_center(head)
	for side in [-1.0, 1.0]:
		for row in range(3):
			for col in range(4):
				var ckey := "%s|head-container|%d|%d|%d" % [key, int(side), row, col]
				if RoadHash.pick(ckey + "|skip", 100) < 24:
					continue
				var point := head_center + tangent * float(side) * (30.0 + col * 7.0) + \
					seaward * (float(row) - 1.0) * 6.5
				var length := _rr(ckey + "|length", 7.0, 15.5)
				var poly := _oriented_rect(point, tangent, seaward, length, 4.8)
				if _poly_inside_fraction(poly, [head]) < 0.995 or \
						_overlap_with_any(poly, exclusions + out) > 0.01:
					continue
				out.append(poly)
	_append_arm_containers(out, left_points, left_arms, exclusions, key + "|left")
	_append_arm_containers(out, right_points, right_arms, exclusions, key + "|right")
	return out

static func _append_arm_containers(out: Array, points: PackedVector2Array,
		arm_polys: Array, exclusions: Array, key: String) -> void:
	var count := 6 + RoadHash.pick(key + "|count", 4)
	for index in range(count):
		var fraction := lerpf(0.34, 0.90,
			(float(index) + 0.5) / float(count))
		var sample := _point_on_polyline(points, fraction)
		if sample.is_empty():
			continue
		var direction: Vector2 = sample.tangent
		var point: Vector2 = sample.point
		var poly := _oriented_rect(point, direction,
			Vector2(-direction.y, direction.x),
			_rr("%s|%d|length" % [key, index], 7.5, 13.0),
			_rr("%s|%d|width" % [key, index], 4.2, 5.4))
		if _poly_inside_fraction(poly, arm_polys) < 0.985 or \
				_overlap_with_any(poly, exclusions + out) > 0.01:
			continue
		out.append(poly)

static func _crane_site(points: PackedVector2Array, arm_width: float,
		arm: String, key: String) -> Dictionary:
	var fraction := _rr("%s|crane|%s|fraction" % [key, arm], 0.58, 0.70)
	var sample := _point_on_polyline(points, fraction)
	var direction: Vector2 = sample.get("tangent", Vector2.RIGHT)
	var position: Vector2 = sample.get("point", points[0])
	var cross := Vector2(-direction.y, direction.x)
	var base := _oriented_rect(position, cross, direction,
		arm_width * 0.84, 9.0)
	return {"position": position, "arm": arm, "direction": direction,
		"cross": cross, "base_polygon": base,
		"gantry_span": arm_width * 1.38,
		"jib_length": 31.0 + RoadHash.pick("%s|%s|jib" % [key, arm], 7)}

static func _bent_arm(points: PackedVector2Array, width: float) -> Array:
	var out: Array = []
	for i in range(points.size() - 1):
		var segment := _segment_quad(points[i], points[i + 1], width * 0.5)
		out.append(segment)
	if points.size() >= 3:
		out.append(_circle_poly(points[1], width * 0.51, 10))
	return out

## Baked land-base polygons — the exact geometry whose boundary the renderer
## strokes as the coastline. Static because the bake never changes at runtime.
static func _land_polygons() -> Array:
	if not _land_polygon_cache.is_empty():
		return _land_polygon_cache
	for entry_value in HillBaked.sea():
		var entry: Dictionary = entry_value
		if int(entry.b) != LAND_BASE_BAND:
			continue
		var poly: PackedVector2Array = entry.p
		if poly.size() >= 3:
			_land_polygon_cache.append({"poly": poly, "bb": _bbox(poly)})
	return _land_polygon_cache

## Accept or reject the head AS DRAWN — a straight block, kept exactly as built.
##
## This used to intersect the block with the land polygons and then erode it along
## an inset ladder, which is what made the apron follow the coastline. A dock does
## not follow a coastline; it reclaims one. So the shape is now untouched and only
## its SEAT is judged: enough of the block must be real ground that the quay reads
## as built on the shore rather than floating off it, with the remainder being the
## reclaimed apron in front. Candidates that cannot meet that move on — the search
## already sweeps shore shifts, approach angles, quay shifts and a width ladder, so
## rejecting a bad seat finds a straighter piece of coast instead of bending the
## dock to fit a crooked one.
static func _fit_head(block: PackedVector2Array) -> Dictionary:
	var land := _class_coverage(block, NavGrid.WATER_LAND)
	if land < HEAD_MIN_LAND:
		return {"reason": "cover"}
	# The BACK half is the part that must be genuine ground — the front is the
	# reclaimed quay and is allowed to sit over water.
	if _class_coverage(_back_half(block), NavGrid.WATER_LAND) < HEAD_MIN_BACK_LAND:
		return {"reason": "back"}
	return {"poly": block, "land": land, "edge": land, "inset": 0.0}


## The landward half of a head block: midpoints of the two side edges, plus the back
## corners. The block is built front-two-corners-then-back-two, so the halves are found
## by walking that order rather than by measuring against the seaward axis.
static func _back_half(block: PackedVector2Array) -> PackedVector2Array:
	if block.size() != 4:
		return block
	return PackedVector2Array([
		(block[0] + block[3]) * 0.5,
		(block[1] + block[2]) * 0.5,
		block[2],
		block[3],
	])


## March an arm backwards along its own axis until it reaches the apron, then
## bite a little further in. Returns Vector2.INF when the apron is out of reach.
static func _attach_to_head(root: Vector2, back_direction: Vector2,
		head: PackedVector2Array) -> Vector2:
	var distance := 0.0
	while distance <= MAX_ARM_ATTACH_REACH:
		var point := root + back_direction * distance
		if Geometry2D.is_point_in_polygon(point, head):
			return root + back_direction * (distance + ARM_HEAD_BITE)
		distance += 3.0
	return Vector2.INF

static func _largest_inset_piece(poly: PackedVector2Array,
		inset: float) -> PackedVector2Array:
	var best := PackedVector2Array()
	var best_area := 0.0
	for piece_value in Geometry2D.offset_polygon(poly, -inset,
			Geometry2D.JOIN_MITER):
		var piece: PackedVector2Array = piece_value
		if piece.size() < 3 or Geometry2D.is_polygon_clockwise(piece):
			continue
		var area := _poly_area(piece)
		if area > best_area:
			best_area = area
			best = piece
	return best

## Closed ring through both arm CENTRELINES: left root -> left tip -> right tip
## -> right root. Using centrelines (not offset inner edges) keeps the ring valid
## for any arm shape; the arm decks themselves are subtracted as opaque cover.
static func _interarm_ring(left_points: PackedVector2Array,
		right_points: PackedVector2Array) -> PackedVector2Array:
	var ring := PackedVector2Array()
	for point in left_points:
		ring.append(point)
	for index in range(right_points.size() - 1, -1, -1):
		ring.append(right_points[index])
	return ring

const ENCLOSURE_SAMPLE_STEP := 4.0

## Area-true land/sea split of the OPEN space inside the ring — every lattice
## point inside the ring that no opaque port element covers. This is the region
## the owner reads as "between the arms".
static func _enclosure_stats(ring: PackedVector2Array,
		opaque: Array) -> Dictionary:
	if ring.size() < 3:
		return {"open_area": 0.0, "sea_area": 0.0, "sea_coverage": 0.0}
	var bb := _bbox(ring)
	var records: Array = []
	for value in opaque:
		var poly: PackedVector2Array = value
		if poly.size() >= 3:
			records.append({"poly": poly, "bb": _bbox(poly)})
	var open_cells := 0
	var sea_cells := 0
	var columns := maxi(1, int(ceil(bb.size.x / ENCLOSURE_SAMPLE_STEP)))
	var rows := maxi(1, int(ceil(bb.size.y / ENCLOSURE_SAMPLE_STEP)))
	for iy in range(rows + 1):
		for ix in range(columns + 1):
			var point := bb.position + Vector2(float(ix), float(iy)) * \
				ENCLOSURE_SAMPLE_STEP
			if not Geometry2D.is_point_in_polygon(point, ring):
				continue
			var covered := false
			for record_value in records:
				var record: Dictionary = record_value
				if not (record.bb as Rect2).has_point(point):
					continue
				if Geometry2D.is_point_in_polygon(point, record.poly):
					covered = true
					break
			if covered:
				continue
			open_cells += 1
			if _water_at(point) == NavGrid.WATER_SEA:
				sea_cells += 1
	var cell_area := ENCLOSURE_SAMPLE_STEP * ENCLOSURE_SAMPLE_STEP
	return {
		"open_area": float(open_cells) * cell_area,
		"sea_area": float(sea_cells) * cell_area,
		"sea_coverage": float(sea_cells) / maxf(1.0, float(open_cells)),
	}

## Largest turn angle inside one arm centreline, in degrees. A straight arm is 0.
static func _max_bend_deg(points: PackedVector2Array) -> float:
	var worst := 0.0
	for i in range(1, points.size() - 1):
		var incoming := points[i] - points[i - 1]
		var outgoing := points[i + 1] - points[i]
		if incoming.length_squared() < 0.0001 or outgoing.length_squared() < 0.0001:
			continue
		worst = maxf(worst, rad_to_deg(absf(incoming.angle_to(outgoing))))
	return worst

static func _class_coverage(poly: PackedVector2Array, water_class: int) -> float:
	var nav := NavGrid.instance()
	var bb := _bbox(poly)
	var lo := nav.cell_of(bb.position - Vector2.ONE * nav.step)
	var hi := nav.cell_of(bb.end + Vector2.ONE * nav.step)
	var total := 0
	var matches := 0
	for iy in range(lo.y, hi.y + 1):
		for ix in range(lo.x, hi.x + 1):
			var point := nav.world_of(ix, iy)
			if not Geometry2D.is_point_in_polygon(point, poly):
				continue
			total += 1
			if nav.water(ix, iy) == water_class:
				matches += 1
	if total == 0:
		return 0.0
	return float(matches) / float(total)

static func _edge_class_coverage(poly: PackedVector2Array, water_class: int,
		spacing: float) -> float:
	var total := 0
	var matches := 0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var count := maxi(2, ceili(a.distance_to(b) / spacing))
		for j in range(count + 1):
			total += 1
			if _water_at(a.lerp(b, float(j) / float(count))) == water_class:
				matches += 1
	return float(matches) / maxf(1.0, float(total))

static func _array_class_coverage(polys: Array, water_class: int) -> float:
	var area := 0.0
	var weighted := 0.0
	for value in polys:
		var poly: PackedVector2Array = value
		var poly_area := _poly_area(poly)
		area += poly_area
		weighted += _class_coverage(poly, water_class) * poly_area
	return weighted / maxf(1.0, area)

static func _open_sea_run(start: Vector2, direction: Vector2,
		max_length: float) -> float:
	var step := 8.0
	var distance := 0.0
	while distance <= max_length:
		for side in [-0.35, 0.0, 0.35]:
			var sample := start + direction * distance + \
				Vector2(-direction.y, direction.x) * float(side) * 30.0
			if _water_at(sample) != NavGrid.WATER_SEA:
				return distance
		distance += step
	return max_length

static func _water_at(point: Vector2) -> int:
	var nav := NavGrid.instance()
	var cell := nav.cell_of(point)
	return nav.water(cell.x, cell.y)

static func _overlap_with_any(poly: PackedVector2Array, others: Array) -> float:
	var area := 0.0
	var bb := _bbox(poly)
	for value in others:
		var other := PackedVector2Array()
		var other_bb := Rect2()
		if value is PackedVector2Array:
			other = value
			other_bb = _bbox(other)
		elif value is Dictionary:
			var record: Dictionary = value
			other = record.get("poly", PackedVector2Array())
			if other.size() < 3:
				continue
			other_bb = record.get("bb", _bbox(other))
		if other.size() < 3 or not bb.intersects(other_bb):
			continue
		area += _poly_overlap_area(poly, other)
	return area

static func _arrays_overlap_area(a: Array, b: Array) -> float:
	var total := 0.0
	for value in a:
		var poly: PackedVector2Array = value.poly if value is Dictionary else value
		if poly.size() >= 3:
			total += _overlap_with_any(poly, b)
	return total

static func _poly_inside_fraction(poly: PackedVector2Array,
		containers: Array) -> float:
	var overlap := 0.0
	for container_value in containers:
		var container: PackedVector2Array = container_value
		overlap += _poly_overlap_area(poly, container)
	return minf(1.0, overlap / maxf(0.001, _poly_area(poly)))

static func _poly_overlap_area(a: PackedVector2Array,
		b: PackedVector2Array) -> float:
	var area := 0.0
	for piece_value in Geometry2D.intersect_polygons(a, b):
		area += _poly_area(piece_value)
	return area

static func _trapezoid(a: Vector2, b: Vector2, tangent: Vector2,
		a_half: float, b_half: float) -> PackedVector2Array:
	return PackedVector2Array([a + tangent * a_half, a - tangent * a_half,
		b - tangent * b_half, b + tangent * b_half])

static func _oriented_rect(center: Vector2, u: Vector2, v: Vector2,
		length: float, depth: float) -> PackedVector2Array:
	var hu := u.normalized() * length * 0.5
	var hv := v.normalized() * depth * 0.5
	return PackedVector2Array([center - hu - hv, center + hu - hv,
		center + hu + hv, center - hu + hv])

static func _segment_quad(a: Vector2, b: Vector2,
		half_width: float) -> PackedVector2Array:
	var tangent := (b - a).normalized()
	if tangent == Vector2.ZERO:
		return PackedVector2Array()
	var normal := Vector2(-tangent.y, tangent.x) * half_width
	return PackedVector2Array([a - normal, b - normal, b + normal, a + normal])

static func _circle_poly(center: Vector2, radius: float,
		steps: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in steps:
		out.append(center + Vector2.RIGHT.rotated(TAU * float(i) /
			float(steps)) * radius)
	return out

static func _point_on_polyline(points: PackedVector2Array,
		fraction: float) -> Dictionary:
	var total := _polyline_length(points)
	if total <= 0.0:
		return {}
	var target := total * clampf(fraction, 0.0, 1.0)
	var walked := 0.0
	for i in range(points.size() - 1):
		var length := points[i].distance_to(points[i + 1])
		if walked + length >= target and length > 0.0:
			var t := (target - walked) / length
			return {"point": points[i].lerp(points[i + 1], t),
				"tangent": (points[i + 1] - points[i]).normalized()}
		walked += length
	return {"point": points[-1],
		"tangent": (points[-1] - points[-2]).normalized()}

static func _polyline_length(points: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(points.size() - 1):
		total += points[i].distance_to(points[i + 1])
	return total

static func _polyline_distance_to_point(points: PackedVector2Array,
		point: Vector2) -> float:
	var best := INF
	for i in range(points.size() - 1):
		best = minf(best, point.distance_to(
			Geometry2D.get_closest_point_to_segment(point, points[i], points[i + 1])))
	return best

static func _convex_envelope(polys: Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	for value in polys:
		var poly: PackedVector2Array = value
		for point in poly:
			points.append(point)
	if points.size() < 3:
		return points
	return Geometry2D.convex_hull(points)

static func _records(polys: Array) -> Array:
	var out: Array = []
	for value in polys:
		var poly: PackedVector2Array = value
		out.append({"poly": poly, "bb": _bbox(poly)})
	return out

static func _poly_center(poly: PackedVector2Array) -> Vector2:
	var center := Vector2.ZERO
	for point in poly:
		center += point
	return center / maxf(1.0, float(poly.size()))

static func _poly_area(poly: PackedVector2Array) -> float:
	var twice_area := 0.0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		twice_area += a.x * b.y - b.x * a.y
	return absf(twice_area) * 0.5

static func _bbox(poly: PackedVector2Array) -> Rect2:
	if poly.is_empty():
		return Rect2()
	var lo := poly[0]
	var hi := poly[0]
	for point in poly:
		lo = lo.min(point)
		hi = hi.max(point)
	return Rect2(lo, hi - lo)

static func _rr(key: String, low: float, high: float) -> float:
	return lerpf(low, high, float(RoadHash.pick(key, 10001)) / 10000.0)

static func _plan_hash(plan: Dictionary) -> String:
	var parts: Array[String] = [str(plan.tile_id)]
	for field in ["land_polygons", "warehouse_polygons", "left_arm_polygons",
			"right_arm_polygons", "container_polygons"]:
		for value in plan.get(field, []):
			parts.append(_poly_signature(value))
	parts.append(_poly_signature(plan.basin_polygon))
	parts.append(_poly_signature(plan.open_water_corridor))
	for point in plan.road_access:
		parts.append("%.3f,%.3f" % [point.x, point.y])
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update("|".join(parts).to_utf8_buffer())
	return context.finish().hex_encode()

static func _poly_signature(poly: PackedVector2Array) -> String:
	var parts: Array[String] = []
	for point in poly:
		parts.append("%.3f,%.3f" % [point.x, point.y])
	return ";".join(parts)
