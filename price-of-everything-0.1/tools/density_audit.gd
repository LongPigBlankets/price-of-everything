extends Node
## Per-tile decorative-density compliance audit.
##   <godot> --headless --path . res://tools/density_audit.tscn --quit-after 4000
##
## Implements section 6 of docs/map-density-and-port-addendum.md: for EVERY land
## tile it emits tile id, nickname, class (urban/sparse/mountain/remote), small
## and large decorative-building counts, green-space count and area, dry
## buildable area, and pass/fail against the section-2 table.
##
## It measures the geometry the mid-century style ACTUALLY RENDERS — the
## sanitised block and park layers, read through
## `UrbanFabricVisuals.density_audit_snapshot()`. Gameplay buildings are frozen
## and are never counted. The audit changes nothing; it only reads.
##
## Exit codes
##   0  every audited tile complies
##   1  the audit could not run (missing node, missing profile data)
##   2  the audit ran and the map does not comply — the intended baseline result
##
## Outputs
##   /tmp/poe_density_audit.json   full per-tile record
##   /tmp/poe_density_audit.txt    human-readable table and failure list

const PROFILE_PATH := "res://data/visual_settlement_profiles.json"
const JSON_PATH := "/tmp/poe_density_audit.json"
const TEXT_PATH := "/tmp/poe_density_audit.txt"
## Tile centres are 405u apart in x and 480u in y; anything further than this
## cannot share area with the mass being assigned.
const NEIGHBOUR_RADIUS := 640.0

var _terrain: TileMapLayer = null
var _fabric: Node = null


func _ready() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	for _i in 240:
		await get_tree().process_frame
	_terrain = game.get_node_or_null("%TerrainLayer") as TileMapLayer
	_fabric = game.find_child("UrbanFabricVisuals", true, false)
	if _terrain == null or _fabric == null:
		push_error("density_audit: TerrainLayer or UrbanFabricVisuals missing")
		get_tree().quit(1)
		return
	MapStyle.set_midcentury(true)
	for _i in 60:
		await get_tree().process_frame
	if not _fabric.has_method("density_audit_snapshot"):
		push_error("density_audit: fabric has no density_audit_snapshot() seam")
		get_tree().quit(1)
		return
	var report := _audit()
	MapStyle.set_midcentury(false)
	_write(JSON_PATH, JSON.stringify(report, "  "))
	_write(TEXT_PATH, _render_text(report))
	_print_summary(report)
	var summary: Dictionary = report.summary
	get_tree().quit(0 if int(summary.gate_failure_tiles) == 0 else 2)


func _audit() -> Dictionary:
	var profiles := _load_profiles()
	if profiles.is_empty():
		push_error("density_audit: no urban profiles at %s" % PROFILE_PATH)
		get_tree().quit(1)
		return {}
	var snapshot: Dictionary = _fabric.call("density_audit_snapshot")
	var fabric_metrics: Dictionary = _fabric.call("metrics")

	# --- tile table -------------------------------------------------------
	var tile_records: Array = []
	var coords: Array = _terrain.tiles.keys()
	coords.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x < b.x or (a.x == b.x and a.y < b.y))
	for coord_value in coords:
		var coord: Vector2i = coord_value
		var tile_data: Dictionary = _terrain.tiles[coord]
		var tile_id := str(tile_data.get("id", "%d_%d" % [coord.x, coord.y]))
		var terrain_type := str(tile_data.get("type", ""))
		var center: Vector2 = _terrain.map_to_local(
			_terrain.map_coord_for_tile_coord(coord))
		var hex := PackedVector2Array()
		for vertex in UrbanFabricVisuals.HEX_VERTS:
			hex.append(center + vertex)
		var built_edges := _built_road_edge_count(coord)
		var tile_class := DensityAudit.classify(terrain_type,
			profiles.has(tile_id), built_edges)
		tile_records.append({
			"tile_id": tile_id,
			"nickname": str(tile_data.get("nickname", "")),
			"coord": [coord.x, coord.y],
			"terrain_type": terrain_type,
			"class": tile_class,
			"urban_profile": str(profiles.get(tile_id, "")),
			"built_road_edge_count": built_edges,
			"center": center,
			"hex": hex,
			"bb": _bbox(hex),
			"small_count": 0, "large_count": 0,
			"small_area": 0.0, "large_area": 0.0,
			"courtyard_count": 0, "courtyard_area": 0.0,
			"mass_kind_counts": {},
			"green_entries": [],
			"pieces": [],
			"bare_parcels": [],
		})

	# --- profile / classification consistency ----------------------------
	var profiled_not_urban: Array = []
	var urban_not_profiled: Array = []
	for record_value in tile_records:
		var record: Dictionary = record_value
		var profiled: bool = profiles.has(str(record.tile_id))
		var typed_urban: bool = str(record.terrain_type) == "urban"
		if profiled and not typed_urban:
			profiled_not_urban.append(str(record.tile_id))
		elif typed_urban and not profiled:
			urban_not_profiled.append(str(record.tile_id))

	# --- assign every rendered mass and green to one tile ----------------
	var areas: Array[float] = []
	var unassigned_masses := 0
	var unassigned_greens := 0
	var uncounted_masses := 0
	var counted_masses: Array = []
	for mass_value in snapshot.get("masses", []):
		var mass: Dictionary = mass_value
		var area := float(mass.area)
		areas.append(area)
		var kind := str(mass.kind)
		if not DensityAudit.counts_as_building(kind, area):
			uncounted_masses += 1
			continue
		counted_masses.append({"poly": mass.poly, "area": area, "kind": kind})
		var owner_index := _owning_tile(tile_records, mass.poly, mass.center)
		if owner_index < 0:
			unassigned_masses += 1
			continue
		var record: Dictionary = tile_records[owner_index]
		(record.mass_kind_counts as Dictionary)[kind] = int(
			(record.mass_kind_counts as Dictionary).get(kind, 0)) + 1
		if DensityAudit.is_large(area):
			record.large_count = int(record.large_count) + 1
			record.large_area = float(record.large_area) + area
		else:
			record.small_count = int(record.small_count) + 1
			record.small_area = float(record.small_area) + area
	for green_value in snapshot.get("greens", []):
		var green: Dictionary = green_value
		var kind := str(green.kind)
		var area := float(green.area)
		var owner_index := _owning_tile(tile_records, green.poly, green.center)
		if owner_index < 0:
			unassigned_greens += 1
			continue
		var record: Dictionary = tile_records[owner_index]
		if kind == "courtyard":
			record.courtyard_count = int(record.courtyard_count) + 1
			record.courtyard_area = float(record.courtyard_area) + area
			continue
		if not DensityAudit.counts_as_green(kind, area):
			continue
		(record.green_entries as Array).append({"poly": green.poly,
			"role": str(green.get("role", "")), "area": area})

	# --- INSTRUMENT 1: visible pieces, map-wide, then assigned to tiles ---
	# The clustering is done ONCE over the whole map so a silhouette that
	# straddles a hex side stays one piece; the piece is then charged to the
	# tile its silhouette shares the most area with, the same rule G1.02 fixed
	# for masses.
	var pieces: Array = DensityAudit.visible_pieces(counted_masses)
	var unassigned_pieces := 0
	for piece_value in pieces:
		var piece: Dictionary = piece_value
		var owner_index := _owning_tile(tile_records, piece.silhouette,
			piece.silhouette_center)
		if owner_index < 0:
			unassigned_pieces += 1
			continue
		((tile_records[owner_index] as Dictionary).pieces as Array).append(piece)

	# --- INSTRUMENT 2: bare built-role parcels ---------------------------
	# Everything the fabric actually inked in, as a coverage field. A parcel the
	# plan assigned a BUILT role that this field barely touches is an undrawn
	# hole with an outline round it.
	var cover_polys: Array = []
	for mass_value in snapshot.get("masses", []):
		cover_polys.append((mass_value as Dictionary).poly)
	for green_value in snapshot.get("greens", []):
		cover_polys.append((green_value as Dictionary).poly)
	var cover_grid := _build_poly_grid(cover_polys)
	var ink_grid: Dictionary = DensityAudit.build_ink_grid(
		snapshot.get("ink_segments", PackedVector2Array()))
	var unassigned_bare := 0
	var judged_parcels := 0
	for parcel_value in snapshot.get("parcels", []):
		var parcel: Dictionary = parcel_value
		var role := str(parcel.get("role", ""))
		var area := float(parcel.area)
		if not DensityAudit.is_built_parcel_role(role):
			continue
		if area < DensityAudit.MIN_COUNTED_PARCEL_AREA:
			continue
		judged_parcels += 1
		var covered := _covered_fraction(parcel.poly, area, cover_polys,
			cover_grid)
		if not DensityAudit.parcel_is_bare(role, area, covered):
			continue
		var owner_index := _owning_tile(tile_records, parcel.poly,
			parcel.center)
		if owner_index < 0:
			unassigned_bare += 1
			continue
		((tile_records[owner_index] as Dictionary).bare_parcels as Array).append({
			"role": role, "area": area, "covered_fraction": covered})

	# --- evaluate ---------------------------------------------------------
	var shortfall_records: Dictionary = fabric_metrics.get(
		"density_shortfalls", {})
	var rural_tiles: Dictionary = (fabric_metrics.get("rural_growth", {}) as \
		Dictionary).get("tiles", {})
	var accommodation_tiles: Dictionary = (fabric_metrics.get(
		"accommodation", {}) as Dictionary).get("tiles", {})
	var land_coords: Array = []
	for record_value in tile_records:
		var record: Dictionary = record_value
		if str(record["class"]) == DensityAudit.CLASS_WATER:
			continue
		land_coords.append(Vector2i(int(record.coord[0]), int(record.coord[1])))
	var geometry_by_coord: Dictionary = _fabric.call(
		"tile_dry_buildable_areas", land_coords)
	var class_counts: Dictionary = {}
	var class_compliant: Dictionary = {}
	var class_constrained: Dictionary = {}
	var failures: Array = []
	var audited := 0
	var gate_failure_tiles := 0
	var out_tiles: Array = []
	for record_value in tile_records:
		var record: Dictionary = record_value
		var tile_class := str(record["class"])
		var tile_id := str(record.tile_id)
		var green_spaces := _merge_green_spaces(record.green_entries)
		var green_area := 0.0
		var deliberate_count := 0
		var deliberate_area := 0.0
		var hole_count := 0
		var hole_area := 0.0
		var hole_reasons: Dictionary = {}
		for space_value in green_spaces:
			var space: Dictionary = space_value
			var space_area := absf(_poly_area(space.poly))
			green_area += space_area
			var role_share := float(space.role_area) / maxf(1.0,
				float(space.area))
			var enclosure := DensityAudit.enclosure_fraction(space.poly,
				ink_grid)
			var verdict: Dictionary = DensityAudit.green_verdict(role_share,
				enclosure)
			if bool(verdict.deliberate):
				deliberate_count += 1
				deliberate_area += space_area
			else:
				hole_count += 1
				hole_area += space_area
				var reason := str(verdict.reason)
				hole_reasons[reason] = int(hole_reasons.get(reason, 0)) + 1
		var bare_area := 0.0
		for bare_value in record.bare_parcels:
			bare_area += float((bare_value as Dictionary).area)
		var articulation: Dictionary = DensityAudit.articulation_summary(
			record.pieces)
		var geometry: Dictionary = {}
		var evaluation: Dictionary = {}
		if tile_class != DensityAudit.CLASS_WATER:
			geometry = geometry_by_coord.get(Vector2i(int(record.coord[0]),
				int(record.coord[1])), {})
			# THE CORRECTION: only DELIBERATE parks satisfy the >= 2 urban
			# floor. An undrawn hole is bare ground, not a civic green.
			evaluation = DensityAudit.evaluate(tile_class,
				int(record.small_count), int(record.large_count),
				deliberate_count,
				float(geometry.get("dry_buildable_area", 0.0)),
				shortfall_records.has(tile_id))
			audited += 1
			class_counts[tile_class] = int(class_counts.get(tile_class, 0)) + 1
			if bool(evaluation.passes):
				class_compliant[tile_class] = int(
					class_compliant.get(tile_class, 0)) + 1
			if bool(evaluation.physically_constrained):
				class_constrained[tile_class] = int(
					class_constrained.get(tile_class, 0)) + 1
		var rejected: Dictionary = {}
		if rural_tiles.has(tile_id):
			rejected["rural_growth"] = (rural_tiles[tile_id] as Dictionary).get(
				"rejected", {})
		if accommodation_tiles.has(tile_id):
			rejected["accommodation"] = (accommodation_tiles[tile_id] as \
				Dictionary).get("rejected", {})
		var out := {
			"tile_id": tile_id,
			"nickname": str(record.nickname),
			"coord": record.coord,
			"terrain_type": str(record.terrain_type),
			"class": tile_class,
			"urban_profile": str(record.urban_profile),
			"built_road_edge_count": int(record.built_road_edge_count),
			"small_count": int(record.small_count),
			"large_count": int(record.large_count),
			"small_area": float(record.small_area),
			"large_area": float(record.large_area),
			"park_count": green_spaces.size(),
			"park_area": green_area,
			# --- INSTRUMENT 2 ---
			"deliberate_park_count": deliberate_count,
			"deliberate_park_area": deliberate_area,
			"park_hole_count": hole_count,
			"park_hole_area": hole_area,
			"park_hole_reasons": hole_reasons,
			"bare_parcel_count": (record.bare_parcels as Array).size(),
			"bare_parcel_area": bare_area,
			"bare_parcels": record.bare_parcels,
			# --- INSTRUMENT 1 ---
			"visible_piece_count": int(articulation.visible_piece_count),
			"piece_mass_count": int(articulation.mass_count),
			"masses_per_visible_piece": float(
				articulation.masses_per_visible_piece),
			"fused_piece_count": int(articulation.fused_piece_count),
			"fused_mass_share_pct": float(articulation.fused_mass_share_pct),
			"largest_piece_mass_count": int(
				articulation.largest_piece_mass_count),
			"mean_visible_piece_area": float(
				articulation.mean_visible_piece_area),
			"median_visible_piece_area": float(
				articulation.median_visible_piece_area),
			"silhouette_perimeter_ratio": float(
				articulation.silhouette_perimeter_ratio),
			"courtyard_count": int(record.courtyard_count),
			"courtyard_area": float(record.courtyard_area),
			"mass_kind_counts": record.mass_kind_counts,
			"hex_area": float(geometry.get("hex_area", 0.0)),
			"dry_land_area": float(geometry.get("dry_land_area", 0.0)),
			"open_land_area": float(geometry.get("open_land_area", 0.0)),
			"relief_retention_fallback": bool(geometry.get(
				"relief_retention_fallback", false)),
			"dry_buildable_area": float(geometry.get("dry_buildable_area", 0.0)),
			"water_margin_area": float(geometry.get("water_margin_area", 0.0)),
			"forest_disc_count": int(geometry.get("forest_disc_count", 0)),
			"gameplay_footprint_count": int(geometry.get(
				"gameplay_footprint_count", 0)),
			"relief_shoulder_count": int(geometry.get("relief_shoulder_count", 0)),
			"rejected_candidates": rejected,
		}
		out.merge(evaluation)
		out_tiles.append(out)
		if tile_class != DensityAudit.CLASS_WATER and not bool(out.get("passes", true)):
			failures.append(out)
		if bool(out.get("gate_failure", false)):
			gate_failure_tiles += 1

	# --- per-settlement-component roll-up ---------------------------------
	# `tile_to_settlement` is the fabric's own component key per tile, covering
	# the morphology components, the two settlement plans and the Arin hero.
	# Tiles outside any component are grouped under "(unclustered)" so nothing
	# is silently dropped.
	var tile_to_component: Dictionary = fabric_metrics.get(
		"tile_to_settlement", {})
	var component_tiles: Dictionary = {}
	for tile_value in out_tiles:
		var tile: Dictionary = tile_value
		if str(tile["class"]) == DensityAudit.CLASS_WATER:
			continue
		var component := str(tile_to_component.get(str(tile.tile_id),
			"(unclustered)"))
		if not component_tiles.has(component):
			component_tiles[component] = []
		(component_tiles[component] as Array).append(tile)
	var component_records: Array = []
	var component_keys: Array = component_tiles.keys()
	component_keys.sort()
	for key_value in component_keys:
		var key := str(key_value)
		var members: Array = component_tiles[key]
		var member_pieces: Array = []
		var ids: Array = []
		var small := 0
		var large := 0
		var deliberate := 0
		var holes := 0
		var bare := 0
		var built_area := 0.0
		for tile_value in members:
			var tile: Dictionary = tile_value
			ids.append(str(tile.tile_id))
			small += int(tile.small_count)
			large += int(tile.large_count)
			deliberate += int(tile.deliberate_park_count)
			holes += int(tile.park_hole_count)
			bare += int(tile.bare_parcel_count)
			built_area += float(tile.small_area) + float(tile.large_area)
		for record_value in tile_records:
			var record: Dictionary = record_value
			if ids.has(str(record.tile_id)):
				member_pieces.append_array(record.pieces)
		var component_articulation: Dictionary = 			DensityAudit.articulation_summary(member_pieces)
		var out_component := {
			"component": key,
			"tile_count": members.size(),
			"tiles": ids,
			"small_count": small,
			"large_count": large,
			"built_area": built_area,
			"deliberate_park_count": deliberate,
			"park_hole_count": holes,
			"bare_parcel_count": bare,
		}
		out_component.merge(component_articulation)
		component_records.append(out_component)

	var map_articulation: Dictionary = DensityAudit.articulation_summary(pieces)
	var park_totals := {"deliberate_park_count": 0, "deliberate_park_area": 0.0,
		"park_hole_count": 0, "park_hole_area": 0.0, "bare_parcel_count": 0,
		"bare_parcel_area": 0.0, "hole_reasons": {},
		"urban_tiles_meeting_park_floor": 0,
		"urban_tiles_meeting_park_floor_uncorrected": 0}
	for tile_value in out_tiles:
		var tile: Dictionary = tile_value
		if str(tile["class"]) == DensityAudit.CLASS_WATER:
			continue
		park_totals.deliberate_park_count = int(
			park_totals.deliberate_park_count) + int(tile.deliberate_park_count)
		park_totals.deliberate_park_area = float(
			park_totals.deliberate_park_area) + float(tile.deliberate_park_area)
		park_totals.park_hole_count = int(park_totals.park_hole_count) + 			int(tile.park_hole_count)
		park_totals.park_hole_area = float(park_totals.park_hole_area) + 			float(tile.park_hole_area)
		park_totals.bare_parcel_count = int(park_totals.bare_parcel_count) + 			int(tile.bare_parcel_count)
		park_totals.bare_parcel_area = float(park_totals.bare_parcel_area) + 			float(tile.bare_parcel_area)
		for reason_value in (tile.park_hole_reasons as Dictionary):
			var reason := str(reason_value)
			(park_totals.hole_reasons as Dictionary)[reason] = int(
				(park_totals.hole_reasons as Dictionary).get(reason, 0)) + int(
				(tile.park_hole_reasons as Dictionary)[reason])
		if str(tile["class"]) != DensityAudit.CLASS_URBAN:
			continue
		if int(tile.deliberate_park_count) >= 2:
			park_totals.urban_tiles_meeting_park_floor = int(
				park_totals.urban_tiles_meeting_park_floor) + 1
		if int(tile.park_count) >= 2:
			park_totals.urban_tiles_meeting_park_floor_uncorrected = int(
				park_totals.urban_tiles_meeting_park_floor_uncorrected) + 1

	areas.sort()
	failures.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if str(a["class"]) != str(b["class"]):
			return str(a["class"]) < str(b["class"])
		return str(a.tile_id) < str(b.tile_id))
	return {
		"threshold": {
			"large_mass_area": DensityAudit.LARGE_MASS_AREA,
			"min_counted_mass_area": DensityAudit.MIN_COUNTED_MASS_AREA,
			"min_counted_green_area": DensityAudit.MIN_COUNTED_GREEN_AREA,
			"measured_distribution": {
				"rendered_mass_count": areas.size(),
				"p25": _percentile(areas, 0.25),
				"median": _percentile(areas, 0.50),
				"p75": _percentile(areas, 0.75),
				"p90": _percentile(areas, 0.90),
				"large_share_pct": 100.0 * float(_count_at_or_above(areas,
					DensityAudit.LARGE_MASS_AREA)) / maxf(1.0, float(areas.size())),
			},
		},
		"classification": {
			"profiled_urban_tiles": profiles.size(),
			"profiled_but_not_urban_terrain": profiled_not_urban,
			"urban_terrain_but_not_profiled": urban_not_profiled,
		},
		"summary": {
			"audited_tiles": audited,
			"class_counts": class_counts,
			"class_compliant": class_compliant,
			"class_physically_constrained": class_constrained,
			"failing_tiles": failures.size(),
			"gate_failure_tiles": gate_failure_tiles,
			"documented_shortfall_tiles": shortfall_records.size(),
			"unassigned_masses": unassigned_masses,
			"unassigned_greens": unassigned_greens,
			"uncounted_mass_fragments": uncounted_masses,
			"rendered_masses": int(snapshot.get("masses", []).size()),
			"rendered_greens": int(snapshot.get("greens", []).size()),
		},
		"articulation": {
			"definition": "a visible piece is a connected component of the "
				+ "drawn masses under 'outlines dilated by %.1fu overlap'; "
				% DensityAudit.FUSION_DILATION
				+ "the dilation is half UrbanFabricVisuals."
				+ "HERO_ALLEY_HALF_WIDTH, so any gap narrower than an accepted "
				+ "3.8u alley reads as one silhouette",
			"fusion_dilation": DensityAudit.FUSION_DILATION,
			"map": map_articulation,
			"unassigned_pieces": unassigned_pieces,
		},
		"parks": {
			"definition": "a DELIBERATE park carries a plan role record AND "
				+ "has at least %.0f%% of its outline inked; anything else is "
				% (100.0 * DensityAudit.PARK_ENCLOSURE_MIN)
				+ "an UNDRAWN HOLE and does not satisfy the urban park floor",
			"enclosure_min": DensityAudit.PARK_ENCLOSURE_MIN,
			"bare_parcel_max_cover": DensityAudit.BARE_PARCEL_MAX_COVER,
			"totals": park_totals,
			"judged_built_parcels": judged_parcels,
			"unassigned_bare_parcels": unassigned_bare,
		},
		"components": component_records,
		"tiles": out_tiles,
		"failures": failures,
	}


func _load_profiles() -> Dictionary:
	var file := FileAccess.open(PROFILE_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


func _built_road_edge_count(coord: Vector2i) -> int:
	var network := RoadNetwork.instance()
	var count := 0
	for edge_id_value in network.edges_on_tile(coord):
		var edge: Dictionary = network.edges.get(str(edge_id_value), {})
		if str(edge.get("state", "")) == RoadNetwork.STATE_BUILT:
			count += 1
	return count


## The tile that owns a polygon is the tile it shares the MOST area with, not
## the tile its centroid lands in — settlement geometry deliberately spills
## across hex sides, and G1.02 established intersection over centroid as the
## honest assignment. Ties break on tile id, so the result is deterministic.
func _owning_tile(records: Array, poly: PackedVector2Array,
		center: Vector2) -> int:
	var best_index := -1
	var best_area := 0.0
	var best_id := ""
	var poly_bb := _bbox(poly)
	for i in records.size():
		var record: Dictionary = records[i]
		var tile_center: Vector2 = record.center
		if absf(tile_center.x - center.x) > NEIGHBOUR_RADIUS or \
				absf(tile_center.y - center.y) > NEIGHBOUR_RADIUS:
			continue
		if not (record.bb as Rect2).intersects(poly_bb):
			continue
		var overlap := 0.0
		for piece_value in Geometry2D.intersect_polygons(poly, record.hex):
			overlap += absf(_poly_area(piece_value))
		if overlap <= 0.0:
			continue
		var tile_id := str(record.tile_id)
		if overlap > best_area or (is_equal_approx(overlap, best_area) and \
				tile_id < best_id):
			best_area = overlap
			best_index = i
			best_id = tile_id
	return best_index


## Two green polygons that merge into one outline are ONE green space. Fragments
## under the counting floor are dropped, so a park sliced by a footprint does not
## inflate the count into two spaces unless the halves really are separate.
##
## Each entry carries the PLAN ROLE that produced it, and the merged space keeps
## the area contributed by park-role entries (`role_area`) alongside its total,
## so instrument 2 can ask what share of a merged green the plan actually meant
## to be green. Merging a genuine park with an adjacent residual pocket must not
## launder the pocket into a park, and a role share below one half will not.
func _merge_green_spaces(entries: Array) -> Array:
	var merged: Array = []
	for entry_value in entries:
		var entry: Dictionary = entry_value
		var pending: PackedVector2Array = entry.poly
		var role_area := float(entry.area) if DensityAudit.is_park_role(
			str(entry.role)) else 0.0
		var total_area := float(entry.area)
		var i := 0
		while i < merged.size():
			var candidate: Dictionary = merged[i]
			var unions := Geometry2D.merge_polygons(candidate.poly, pending)
			if unions.size() == 1:
				pending = unions[0]
				role_area += float(candidate.role_area)
				total_area += float(candidate.area)
				merged.remove_at(i)
				i = 0
			else:
				i += 1
		merged.append({"poly": pending, "role_area": role_area,
			"area": total_area})
	var out: Array = []
	for merged_value in merged:
		var space: Dictionary = merged_value
		var poly: PackedVector2Array = space.poly
		if poly.size() >= 3 and absf(_poly_area(poly)) >= \
				DensityAudit.MIN_COUNTED_GREEN_AREA:
			out.append(space)
	return out


## Uniform bucket grid over a polygon array, for the parcel-coverage test.
func _build_poly_grid(polys: Array, cell: float = 128.0) -> Dictionary:
	var grid: Dictionary = {}
	for i in polys.size():
		var box := _bbox(polys[i])
		var x0 := floori(box.position.x / cell)
		var x1 := floori((box.position.x + box.size.x) / cell)
		var y0 := floori(box.position.y / cell)
		var y1 := floori((box.position.y + box.size.y) / cell)
		for cx in range(x0, x1 + 1):
			for cy in range(y0, y1 + 1):
				var key := Vector2i(cx, cy)
				if not grid.has(key):
					grid[key] = PackedInt32Array()
				var bucket: PackedInt32Array = grid[key]
				bucket.append(i)
				grid[key] = bucket
	return {"grid": grid, "cell": cell}


## Fraction of a parcel covered by anything the fabric actually inked in.
## Overlaps between two covering polygons are counted twice and the result is
## clamped to 1.0; that can only ever make a parcel look MORE covered, so it
## cannot manufacture a bare parcel that is not bare.
func _covered_fraction(poly: PackedVector2Array, area: float, polys: Array,
		grid_data: Dictionary) -> float:
	if area <= 0.0:
		return 1.0
	var grid: Dictionary = grid_data.grid
	var cell := float(grid_data.cell)
	var box := _bbox(poly)
	var seen: Dictionary = {}
	var covered := 0.0
	var x0 := floori(box.position.x / cell)
	var x1 := floori((box.position.x + box.size.x) / cell)
	var y0 := floori(box.position.y / cell)
	var y1 := floori((box.position.y + box.size.y) / cell)
	for cx in range(x0, x1 + 1):
		for cy in range(y0, y1 + 1):
			var bucket_value: Variant = grid.get(Vector2i(cx, cy))
			if bucket_value == null:
				continue
			var bucket: PackedInt32Array = bucket_value
			for index in bucket:
				if seen.has(index):
					continue
				seen[index] = true
				var other: PackedVector2Array = polys[index]
				if not _bbox(other).intersects(box):
					continue
				for piece_value in Geometry2D.intersect_polygons(poly, other):
					covered += absf(_poly_area(piece_value))
				if covered >= area:
					return 1.0
	return minf(1.0, covered / area)


func _percentile(sorted_values: Array[float], percentile: float) -> float:
	if sorted_values.is_empty():
		return 0.0
	var index := clampi(roundi(percentile * float(sorted_values.size() - 1)),
		0, sorted_values.size() - 1)
	return sorted_values[index]


func _count_at_or_above(sorted_values: Array[float], threshold: float) -> int:
	var count := 0
	for value in sorted_values:
		if value >= threshold:
			count += 1
	return count


func _poly_area(poly: PackedVector2Array) -> float:
	var total := 0.0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		total += a.x * b.y - b.x * a.y
	return absf(total) * 0.5


func _bbox(poly: PackedVector2Array) -> Rect2:
	if poly.is_empty():
		return Rect2()
	var mn := poly[0]
	var mx := poly[0]
	for point in poly:
		mn = mn.min(point)
		mx = mx.max(point)
	return Rect2(mn, mx - mn)


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("density_audit: cannot write '%s'" % path)
		return
	file.store_string(text)
	print("[DENSITY AUDIT] %s" % path)


func _render_text(report: Dictionary) -> String:
	var lines: Array[String] = []
	var threshold: Dictionary = report.threshold
	var distribution: Dictionary = threshold.measured_distribution
	var summary: Dictionary = report.summary
	lines.append("=== PER-TILE DECORATIVE DENSITY AUDIT ===")
	lines.append("addendum section 2 table, measured on the rendered mid-century fabric")
	lines.append("")
	lines.append("SMALL/LARGE THRESHOLD (frozen, absolute, map-wide)")
	lines.append("  large_mass_area          %.1f u^2" % float(threshold.large_mass_area))
	lines.append("  counted mass floor       %.1f u^2" % float(threshold.min_counted_mass_area))
	lines.append("  counted green floor      %.1f u^2" % float(threshold.min_counted_green_area))
	lines.append("  measured this run: n=%d  p25=%.0f  median=%.0f  p75=%.0f  p90=%.0f" % [
		int(distribution.rendered_mass_count), float(distribution.p25),
		float(distribution.median), float(distribution.p75), float(distribution.p90)])
	lines.append("  masses at or above the threshold: %.1f%%" % float(
		distribution.large_share_pct))
	lines.append("")
	lines.append("CLASSIFICATION")
	var classification: Dictionary = report.classification
	lines.append("  profiled urban tiles     %d" % int(classification.profiled_urban_tiles))
	lines.append("  profiled but not urban   %s" % str(classification.profiled_but_not_urban_terrain))
	lines.append("  urban but not profiled   %s" % str(classification.urban_terrain_but_not_profiled))
	lines.append("")
	lines.append("COMPLIANCE BY CLASS")
	lines.append("  %-10s %7s %10s %9s %12s" % ["class", "tiles", "compliant", "failing", "constrained"])
	var class_counts: Dictionary = summary.class_counts
	var class_keys: Array = class_counts.keys()
	class_keys.sort()
	for key_value in class_keys:
		var key := str(key_value)
		var total := int(class_counts[key])
		var ok := int((summary.class_compliant as Dictionary).get(key, 0))
		lines.append("  %-10s %7d %10d %9d %12d" % [key, total, ok, total - ok,
			int((summary.class_physically_constrained as Dictionary).get(key, 0))])
	lines.append("")
	lines.append("  audited tiles                %d" % int(summary.audited_tiles))
	lines.append("  failing tiles                %d" % int(summary.failing_tiles))
	lines.append("  UNDOCUMENTED misses (gate)   %d" % int(summary.gate_failure_tiles))
	lines.append("  documented shortfalls        %d" % int(summary.documented_shortfall_tiles))
	lines.append("  rendered masses / greens     %d / %d" % [
		int(summary.rendered_masses), int(summary.rendered_greens)])
	lines.append("  mass fragments below floor   %d" % int(summary.uncounted_mass_fragments))
	lines.append("  masses/greens off every tile %d / %d" % [
		int(summary.unassigned_masses), int(summary.unassigned_greens)])
	lines.append("")
	lines.append("ARTICULATION (instrument 1) - VISIBLE PIECES, NOT POLYGONS")
	var articulation: Dictionary = report.articulation
	var map_articulation: Dictionary = articulation.map
	lines.append("  %s" % str(articulation.definition))
	lines.append("  drawn masses counted        %d" % int(map_articulation.mass_count))
	lines.append("  VISIBLE PIECES              %d" % int(map_articulation.visible_piece_count))
	lines.append("  masses per visible piece    %.3f   (1.000 = nothing fuses)" % float(
		map_articulation.masses_per_visible_piece))
	lines.append("  fused pieces (>=2 masses)   %d" % int(map_articulation.fused_piece_count))
	lines.append("  masses inside a fused piece %.1f%%" % float(map_articulation.fused_mass_share_pct))
	lines.append("  largest single silhouette   %d masses" % int(
		map_articulation.largest_piece_mass_count))
	lines.append("  mean visible piece area     %.0f u^2" % float(
		map_articulation.mean_visible_piece_area))
	lines.append("  median visible piece area   %.0f u^2" % float(
		map_articulation.median_visible_piece_area))
	lines.append("  silhouette perimeter ratio  %.3f   (1.000 = no shared boundary)" % float(
		map_articulation.silhouette_perimeter_ratio))
	lines.append("  pieces off every tile       %d" % int(articulation.unassigned_pieces))
	lines.append("")
	lines.append("PARKS vs HOLES (instrument 2)")
	var parks: Dictionary = report.parks
	var park_totals: Dictionary = parks.totals
	lines.append("  %s" % str(parks.definition))
	lines.append("  DELIBERATE parks            %d  (%.0f u^2)" % [
		int(park_totals.deliberate_park_count), float(park_totals.deliberate_park_area)])
	lines.append("  UNDRAWN holes (greens)      %d  (%.0f u^2)  %s" % [
		int(park_totals.park_hole_count), float(park_totals.park_hole_area),
		str(park_totals.hole_reasons)])
	lines.append("  BARE built-role parcels     %d  (%.0f u^2) of %d judged" % [
		int(park_totals.bare_parcel_count), float(park_totals.bare_parcel_area),
		int(parks.judged_built_parcels)])
	lines.append("  urban tiles >= 2 parks      %d corrected / %d uncorrected" % [
		int(park_totals.urban_tiles_meeting_park_floor),
		int(park_totals.urban_tiles_meeting_park_floor_uncorrected)])
	lines.append("  bare parcels off every tile %d" % int(parks.unassigned_bare_parcels))
	lines.append("")
	lines.append("PER SETTLEMENT COMPONENT")
	lines.append("  %-34s %5s %6s %6s %7s %7s %9s %6s %6s" % [
		"component", "tiles", "masses", "pieces", "m/piece", "med_area",
		"perim_rat", "dpark", "hole"])
	for component_value in report.components:
		var component: Dictionary = component_value
		lines.append("  %-34s %5d %6d %6d %7.3f %7.0f %9.3f %6d %6d" % [
			str(component.component).substr(0, 34), int(component.tile_count),
			int(component.mass_count), int(component.visible_piece_count),
			float(component.masses_per_visible_piece),
			float(component.median_visible_piece_area),
			float(component.silhouette_perimeter_ratio),
			int(component.deliberate_park_count), int(component.park_hole_count)])
	lines.append("")
	lines.append("FULL TILE TABLE")
	lines.append("  dpark = deliberate parks (the number the section-2 floor is judged on)")
	lines.append("  hole  = greens that are undrawn holes; bare = built-role parcels with nothing on them")
	lines.append("  %-12s %-26s %-9s %5s %5s %5s %5s %5s %6s %7s %10s  %s" % [
		"tile", "nickname", "class", "small", "large", "dpark",
		"hole", "bare", "pieces", "m/piece", "dry_area", "verdict"])
	for tile_value in report.tiles:
		var tile: Dictionary = tile_value
		if str(tile["class"]) == DensityAudit.CLASS_WATER:
			continue
		var verdict := "PASS"
		if not bool(tile.get("passes", true)):
			verdict = "FAIL %s" % str(tile.failures)
			if bool(tile.get("physically_constrained", false)):
				verdict += " [physically constrained]"
		lines.append("  %-12s %-26s %-9s %5d %5d %5d %5d %5d %6d %7.3f %10.0f  %s" % [
			str(tile.tile_id), str(tile.nickname).substr(0, 26), str(tile["class"]),
			int(tile.small_count), int(tile.large_count),
			int(tile.deliberate_park_count), int(tile.park_hole_count),
			int(tile.bare_parcel_count), int(tile.visible_piece_count),
			float(tile.masses_per_visible_piece),
			float(tile.dry_buildable_area), verdict])
	lines.append("")
	lines.append("FAILURES (%d)" % int(summary.failing_tiles))
	for tile_value in report.failures:
		var tile: Dictionary = tile_value
		var req: Dictionary = tile.requirements
		lines.append("  %-12s %-9s %-24s small=%d (min %d, max %d)  large=%d (min %d, max %d)  park=%d (min %d)  dry=%.0f/%.0f  %s%s" % [
			str(tile.tile_id), str(tile["class"]), str(tile.nickname).substr(0, 24),
			int(tile.small_count), int(req.small_min), int(req.small_max),
			int(tile.large_count), int(req.large_min), int(req.large_max),
			int(tile.deliberate_park_count), int(req.park_min),
			float(tile.dry_buildable_area), float(tile.required_dry_area),
			str(tile.failures),
			" [physically constrained]" if bool(tile.physically_constrained) else ""])
	lines.append("")
	return "\n".join(lines)


func _print_summary(report: Dictionary) -> void:
	var summary: Dictionary = report.summary
	print("\n=== DENSITY AUDIT ===")
	print("large-mass threshold: %.0f u^2 (frozen)" % DensityAudit.LARGE_MASS_AREA)
	print("audited tiles:     %d" % int(summary.audited_tiles))
	print("class counts:      %s" % str(summary.class_counts))
	print("class compliant:   %s" % str(summary.class_compliant))
	print("failing tiles:     %d" % int(summary.failing_tiles))
	print("undocumented:      %d" % int(summary.gate_failure_tiles))
	var map_articulation: Dictionary = (report.articulation as Dictionary).map
	print("visible pieces:    %d from %d masses (%.3f masses/piece)" % [
		int(map_articulation.visible_piece_count),
		int(map_articulation.mass_count),
		float(map_articulation.masses_per_visible_piece)])
	print("median piece area: %.0f u^2   perimeter ratio %.3f" % [
		float(map_articulation.median_visible_piece_area),
		float(map_articulation.silhouette_perimeter_ratio)])
	var park_totals: Dictionary = (report.parks as Dictionary).totals
	print("parks:             %d deliberate / %d holes / %d bare parcels" % [
		int(park_totals.deliberate_park_count), int(park_totals.park_hole_count),
		int(park_totals.bare_parcel_count)])
