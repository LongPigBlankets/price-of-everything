extends Node2D
## Deterministic, UI-hidden morphology gauntlet for the mid-century map.
## Writes five fixed 960x480 regional slices, one 1280x720 wide slice, and a
## JSON completion marker/metrics record under /tmp/poe_morph_*.

const TARGETS := {
	"arinold": "tile_10_16",
	"town": "tile_6_13",
	"river": "tile_9_8",
	"fringe": "tile_23_16",
	"village": "tile_29_17",
	"tegan_core": "tile_19_14",
}

var _wm: Node
var _terrain: TileMapLayer
var _cam: Camera2D

func _ready() -> void:
	get_viewport().set_disable_input(true)
	_wm = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_wm)
	for _i in 150:
		await get_tree().process_frame
	_terrain = _wm.get_node("%TerrainLayer")
	var grid := _wm.find_child("HexGridOverlay", true, false) as CanvasItem
	if grid != null:
		grid.visible = false
	var ui := _wm.get_node_or_null("UILayer") as CanvasLayer
	if ui != null:
		ui.visible = false
	_cam = get_viewport().get_camera_2d()
	if _cam == null:
		push_error("settlement_morphology_shot: no game camera")
		get_tree().quit(1)
		return
	_cam.set_process(false)
	_cam.set_physics_process(false)
	if "edge_pan_enabled" in _cam:
		_cam.set("edge_pan_enabled", false)
	MapStyle.set_midcentury(true)
	for _i in 24:
		await get_tree().process_frame
	for key in TARGETS:
		await _shot(_tile_pos(TARGETS[key]), 1.35, Vector2i(960, 480),
			"/tmp/poe_morph_%s.png" % key)
	await _shot((_tile_pos("tile_23_14") + _tile_pos("tile_23_15")) * 0.5,
		0.72, Vector2i(960, 480), "/tmp/poe_morph_rural_trunk.png")
	await _shot((_tile_pos("tile_23_14") + _tile_pos("tile_23_15") +
		_tile_pos("tile_23_16") * 1.5) / 3.5, 0.62, Vector2i(960, 480),
		"/tmp/poe_morph_suburban_transition.png")
	await _shot(_capital_continuity_pos(), 0.72, Vector2i(1280, 720),
		"/tmp/poe_morph_capital.png")
	await _wide_shot()
	var dynamic_manifest := await _capture_dynamic_diagnostics()
	_write_dynamic_manifest("/tmp/poe_morph_dynamic_manifest.json",
		dynamic_manifest)
	var field_failure := _write_metrics("/tmp/poe_morph_metrics.json",
		dynamic_manifest)
	MapStyle.set_midcentury(false)
	_wm.queue_free()
	for _i in 8:
		await get_tree().process_frame
	RenderingServer.force_draw()
	if not field_failure.is_empty():
		push_error(field_failure)
		get_tree().quit(1)
		return
	get_tree().quit(0)

func _tile_pos(tile_id: String) -> Vector2:
	var coord: Vector2i = _terrain.id_to_coord(tile_id)
	if coord == Vector2i(-1, -1) or not _terrain.tiles.has(coord):
		push_error("settlement_morphology_shot: unknown tile '%s'" % tile_id)
		return Vector2.ZERO
	return _terrain.map_to_local(_terrain.map_coord_for_tile_coord(coord))

func _capital_continuity_pos() -> Vector2:
	var tile_ids := [
		"tile_23_8", "tile_24_7", "tile_24_8", "tile_24_9",
		"tile_25_9", "tile_26_8", "tile_27_9",
	]
	var center := Vector2.ZERO
	for tile_id in tile_ids:
		center += _tile_pos(tile_id)
	return center / float(tile_ids.size())

func _shot(pos: Vector2, zoom: float, size: Vector2i, path: String) -> void:
	_cam.position = pos
	_cam.zoom = Vector2(zoom, zoom)
	if "_target_zoom" in _cam:
		_cam.set("_target_zoom", Vector2(zoom, zoom))
	for _i in 18:
		await get_tree().process_frame
	RenderingServer.force_draw()
	var image := get_viewport().get_texture().get_image()
	var crop_size := Vector2i(mini(size.x, image.get_width()), mini(size.y, image.get_height()))
	var crop_origin := Vector2i((image.get_width() - crop_size.x) / 2,
		(image.get_height() - crop_size.y) / 2)
	image.get_region(Rect2i(crop_origin, crop_size)).save_png(path)
	print("[MORPH SHOT] %s" % path)

func _wide_shot() -> void:
	var mn := Vector2(1e30, 1e30)
	var mx := Vector2(-1e30, -1e30)
	for coord in _terrain.tiles:
		var point := _terrain.map_to_local(_terrain.map_coord_for_tile_coord(coord))
		mn = mn.min(point)
		mx = mx.max(point)
	var span := mx - mn
	var viewport_size := get_viewport().get_visible_rect().size
	var zoom := minf(viewport_size.x / (span.x + 1200.0),
		viewport_size.y / (span.y + 1200.0))
	await _shot((mn + mx) * 0.5, zoom, Vector2i(1280, 720), "/tmp/poe_morph_wide.png")

func _write_metrics(path: String, dynamic_manifest: Dictionary = {}) -> String:
	var record := {"targets": {}, "fabric": {},
		"dynamic_diagnostics": dynamic_manifest}
	var fabric := _wm.find_child("UrbanFabricVisuals", true, false)
	if fabric != null and fabric.has_method("metrics"):
		record.fabric = fabric.call("metrics")
	for key in TARGETS:
		var tile_id: String = TARGETS[key]
		var coord: Vector2i = _terrain.id_to_coord(tile_id)
		var tile_data: Dictionary = _terrain.tiles.get(coord, {})
		record.targets[key] = {
			"tile_id": tile_id,
			"nickname": str(tile_data.get("nickname", "")),
			"has_river": bool(tile_data.get("has_river", false)),
			"road_edges": RoadNetwork.instance().edges_on_tile(coord).size(),
			"gameplay_buildings": MatchState.get_buildings_on_tile(tile_id).size(),
		}
	record.targets.capital = {
		"tile_id": "tile_24_8",
		"nickname": "Capital City continuity region",
		"component_tiles": [
			"tile_23_8", "tile_24_7", "tile_24_8", "tile_24_9",
			"tile_25_9", "tile_26_8", "tile_27_9",
		],
	}
	record.targets.rural_trunk = {
		"tile_id": "tile_23_15",
		"nickname": "Cross-tile authoritative trunk rural ribbon",
		"component_tiles": ["tile_23_14", "tile_23_15"],
	}
	record.targets.suburban_transition = {
		"tile_id": "tile_23_15",
		"nickname": "Vandel Port Works to Tallow River Valley fringe",
		"component_tiles": ["tile_23_14", "tile_23_15", "tile_23_16"],
	}
	# Persist the oracle before evaluating its hard gates. Failed visual
	# experiments still need complete, current metrics rather than leaving a
	# stale successful record in /tmp.
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("settlement_morphology_shot: cannot write '%s'" % path)
	else:
		file.store_string(JSON.stringify(record, "  "))
		print("[MORPH SHOT] %s (audit metrics; gates follow)" % path)
	var rural_growth: Dictionary = record.fabric.get("rural_growth", {})
	assert(float(rural_growth.get("frontage_pct", 0.0)) >= 75.0,
		"Rural growth must put at least 75% of masses within one frontage depth")
	for key in ["water_overlap_count", "relief_overlap_count",
			"forest_overlap_count", "gameplay_overlap_count", "road_overlap_count"]:
		assert(int(rural_growth.get(key, -1)) == 0,
			"Rural-growth hard gate failed: %s" % key)
	var suburban: Dictionary = record.fabric.get("suburban", {})
	assert(int(suburban.get("total_masses", 0)) >= 8,
		"Suburban district must contain one coherent detached frontage group")
	assert(int(suburban.get("cross_tile_districts", 0)) >= 1,
		"Suburban district must extend beyond its source urban component")
	assert(int(suburban.get("access_streets", 0)) >= 1 and is_equal_approx(
		float(suburban.get("street_width", 0.0)), 3.0),
		"Suburban district must have a connected subordinate 3u access street")
	for key in ["road_connection_failure_count", "floating_street_count",
			"water_overlap_count", "relief_overlap_count", "forest_overlap_count",
			"gameplay_overlap_count", "decorative_overlap_count",
			"accommodation_overlap_count", "mountain_mass_count"]:
		assert(int(suburban.get(key, -1)) == 0,
			"Suburban hard gate failed: %s" % key)
	# Coastal reach ships with its own minimum-retention gate, measured in the
	# same run: the reach extent is a superset of the core-only extent before
	# clipping, so no tile may end with less usable envelope than it had without
	# the reach cells.
	var coastal_reach: Dictionary = record.fabric.get("coastal_reach", {})
	assert(int(coastal_reach.get("bearing_count", 0)) > 0,
		"Coastal reach must find at least one wet bearing on the district field")
	assert(int(coastal_reach.get("retention_failure_count", -1)) == 0,
		"Coastal reach removed usable envelope from a tile (minimum-retention gate)")
	assert(float(coastal_reach.get("minimum_retention", 0.0)) >= 0.999,
		"Coastal reach minimum per-tile retention fell below one")
	assert(float(coastal_reach.get("reach_area_gain", 0.0)) > 0.0,
		"Coastal reach produced no additional usable envelope")
	var district_field: Dictionary = record.fabric.get("district_field", {})
	var field_failure := ""
	assert(int(district_field.get("universal_tile_count", 0)) == 92,
		"Universal district audit must include all 92 urban tiles")
	if int(district_field.get("missing_visible_core_count", -1)) != 0:
		field_failure = "Every usable urban tile must contribute a visible road-anchored core"
	elif int(district_field.get("dense_core_failure_count", -1)) != 0:
		field_failure = "Every usable urban tile must contain a genuine compact multi-building core"
	elif int(district_field.get("gradient_failure_count", -1)) != 0:
		field_failure = "Normalized road-rich coverage must exceed road-poor coverage by five points"
	elif int(district_field.get("internal_seam_failure_count", -1)) != 0:
		field_failure = "Usable internal urban edges must not retain terrain-only moats"
	elif int(district_field.get("local_hex_failure_count", -1)) != 0:
		field_failure = "Local settlement boundaries must remain below 20% hex coincidence"
	for tile_id_value in district_field.get("tiles", {}):
		var tile_id := str(tile_id_value)
		var field_tile: Dictionary = district_field.tiles[tile_id]
		for required_key in ["nickname", "profile", "dry_buildable_urban_area",
				"usable_area", "core_position", "attempted_alternative_core_positions",
				"buildable_core_zone_area", "core_built_area", "core_built_coverage",
				"distinct_core_mass_count", "total_mass_count", "built_area",
				"built_coverage", "unique_road_edge_count",
				"total_road_length_within_tile", "junction_count",
				"maximum_junction_degree", "raw_road_influence_score",
				"road_rich_usable_area", "road_intermediate_usable_area",
				"road_poor_usable_area", "road_rich_built_coverage",
				"road_intermediate_built_coverage", "road_poor_built_coverage",
				"near_road_coverage", "far_road_coverage", "spill_by_neighbor",
				"internal_edges", "internal_urban_edge_continuity",
				"local_exterior_boundary_length", "local_hex_coincident_fraction",
				"constraints"]:
			assert(field_tile.has(required_key),
				"District-field tile %s lacks diagnostic %s" % [tile_id, required_key])
	var rural_tiles: Dictionary = rural_growth.get("tiles", {})
	assert(str((rural_tiles.get("tile_23_14", {}) as Dictionary).get(
		"primary_edge_id", "")) == str((rural_tiles.get("tile_23_15", {}) as Dictionary).get(
		"primary_edge_id", "")),
		"Cross-tile rural framing must inherit one continuous authoritative route")
	var capital_found := false
	for settlement_value in record.fabric.get("settlements", {}).values():
		var settlement: Dictionary = settlement_value
		if not (settlement.get("tiles", []) as Array).has("tile_23_8"):
			continue
		capital_found = true
	assert(capital_found, "Capital continuity diagnostics must include the seven-tile component")
	var settlements: Dictionary = record.fabric.get("settlements", {})
	var capital_stats: Dictionary = settlements.get(
		"settlement-plan|capital-port", {})
	var silkstown_stats: Dictionary = settlements.get(
		"settlement-plan|silkstown", {})
	assert(float(capital_stats.get("built_pct", 0.0)) >= 30.0,
		"Capital decorative coverage regressed below the inhabited-city floor")
	assert(float(silkstown_stats.get("built_pct", 0.0)) >= 25.0,
		"Silkstown decorative coverage regressed below the inhabited-town floor")
	assert(int(record.fabric.get("urban_blocks_before_rural", 0)) >= 1000,
		"Urban relief processing erased too much decorative massing")
	var empty_settlement_count := 0
	for settlement_value in settlements.values():
		var settlement: Dictionary = settlement_value
		if float(settlement.get("built_area", 0.0)) <= 0.01:
			empty_settlement_count += 1
	assert(empty_settlement_count <= 1,
		"Too many urban settlements have no decorative building area: %d" %
		empty_settlement_count)
	var dry_land_guard: Dictionary = record.fabric.get("dry_land_guard", {})
	assert(int(dry_land_guard.get("water_overlap_count", -1)) == 0,
		"A decorative fill survived the final dry-land ownership guard")
	var capital_plan: Dictionary = record.fabric.get("settlement_plan_capital", {})
	var plan_diagnostics: Dictionary = capital_plan.get("diagnostics", {})
	assert(int(plan_diagnostics.get("internal_edge_count", 0)) == 8,
		"Capital SettlementPlan must report all eight internal component edges")
	assert(float(plan_diagnostics.get("internal_band_coverage", 0.0)) > 0.75,
		"Capital SettlementPlan internal-edge bands must remain substantially covered")
	for key in [
		"ordinary_mass_water_overlap_area",
		"industrial_support_water_overlap_area",
		"cross_bank_mass_count",
		"disconnected_mass_after_water_clip_count",
		"roof_element_water_overlap_count",
		"shadow_water_overlap_count",
		"uncovered_river_join_count",
	]:
		assert(float(plan_diagnostics.get(key, -1.0)) == 0.0,
			"Capital SettlementPlan water-safety gate failed: %s" % key)
	var relief_failures := [
		"contour_crossing_decorative_mass_count",
		"decorative_fill_relief_shoulder_overlap_area",
		"disconnected_mass_after_relief_count",
		"multi_band_decorative_building_count",
	]
	for plan_key in ["settlement_plan_capital", "settlement_plan_silkstown"]:
		var plan_record: Dictionary = record.fabric.get(plan_key, {})
		var diagnostics: Dictionary = plan_record.get("diagnostics", {})
		for failure_key in relief_failures:
			assert(float(diagnostics.get(failure_key, -1.0)) == 0.0,
				"%s relief gate failed: %s" % [plan_key, failure_key])
	for settlement_key in record.fabric.get("settlements", {}):
		var settlement: Dictionary = record.fabric.settlements[settlement_key]
		var relief: Dictionary = settlement.get("relief", {})
		if relief.is_empty():
			continue
		for failure_key in relief_failures:
			assert(float(relief.get(failure_key, -1.0)) == 0.0,
				"%s relief gate failed: %s" % [settlement_key, failure_key])
	return field_failure

func _capture_dynamic_diagnostics() -> Dictionary:
	var fabric_node := _wm.find_child("UrbanFabricVisuals", true, false)
	if fabric_node == null or not fabric_node.has_method("metrics"):
		return {"captures": []}
	var metrics: Dictionary = fabric_node.call("metrics")
	var field: Dictionary = metrics.get("district_field", {})
	var tiles: Dictionary = field.get("tiles", {})
	var weakest: Array = []
	var gradients: Array = []
	var seams: Array = []
	var hexes: Array = []
	for tile_id_value in tiles:
		var tile_id := str(tile_id_value)
		var tile: Dictionary = tiles[tile_id]
		weakest.append({"tile_id": tile_id, "tile": tile})
		if bool(tile.get("gradient_applicable", false)):
			gradients.append({"tile_id": tile_id, "tile": tile})
		if int(tile.get("internal_edge_failure_count", 0)) > 0 or float(
				tile.get("internal_urban_edge_continuity", 1.0)) < 1.0:
			seams.append({"tile_id": tile_id, "tile": tile})
		if float(tile.get("local_exterior_boundary_length", 0.0)) > 1.0:
			hexes.append({"tile_id": tile_id, "tile": tile})
	weakest.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var at: Dictionary = a.tile
		var bt: Dictionary = b.tile
		if bool(at.dense_core_ok) != bool(bt.dense_core_ok):
			return not bool(at.dense_core_ok)
		var at_count_progress := float(at.distinct_core_mass_count) / maxf(1.0,
			float(at.required_core_mass_count))
		var bt_count_progress := float(bt.distinct_core_mass_count) / maxf(1.0,
			float(bt.required_core_mass_count))
		var at_coverage_progress := at_count_progress
		var bt_coverage_progress := bt_count_progress
		if float(at.required_core_built_coverage) > 0.0:
			at_coverage_progress = float(at.core_built_coverage) / float(
				at.required_core_built_coverage)
		if float(bt.required_core_built_coverage) > 0.0:
			bt_coverage_progress = float(bt.core_built_coverage) / float(
				bt.required_core_built_coverage)
		var at_progress := minf(at_count_progress, at_coverage_progress)
		var bt_progress := minf(bt_count_progress, bt_coverage_progress)
		if not is_equal_approx(at_progress, bt_progress):
			return at_progress < bt_progress
		return str(a.tile_id) < str(b.tile_id))
	gradients.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ad := float((a.tile as Dictionary).get("gradient_delta", 0.0))
		var bd := float((b.tile as Dictionary).get("gradient_delta", 0.0))
		return ad < bd if not is_equal_approx(ad, bd) else str(a.tile_id) < str(b.tile_id))
	seams.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ac := float((a.tile as Dictionary).get(
			"internal_urban_edge_continuity", 1.0))
		var bc := float((b.tile as Dictionary).get(
			"internal_urban_edge_continuity", 1.0))
		return ac < bc if not is_equal_approx(ac, bc) else str(a.tile_id) < str(b.tile_id))
	hexes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var af := float((a.tile as Dictionary).get("local_hex_coincident_fraction", 0.0))
		var bf := float((b.tile as Dictionary).get("local_hex_coincident_fraction", 0.0))
		return af > bf if not is_equal_approx(af, bf) else str(a.tile_id) < str(b.tile_id))
	var manifest := {"captures": [], "categories": {}}
	await _capture_dynamic_category("weak_core", weakest.slice(0,
		mini(6, weakest.size())), manifest)
	await _capture_dynamic_category("road_gradient", gradients.slice(0,
		mini(3, gradients.size())), manifest)
	await _capture_dynamic_category("internal_seam", seams.slice(0,
		mini(3, seams.size())), manifest)
	await _capture_dynamic_category("hex_boundary", hexes.slice(0,
		mini(3, hexes.size())), manifest)
	return manifest

func _capture_dynamic_category(category: String, candidates: Array,
		manifest: Dictionary) -> void:
	var category_records: Array = []
	for i in candidates.size():
		var candidate: Dictionary = candidates[i]
		var tile_id := str(candidate.tile_id)
		var tile: Dictionary = candidate.tile
		var path := "/tmp/poe_morph_dynamic_%s_%02d_%s.png" % [
			category, i + 1, tile_id]
		await _shot(_tile_pos(tile_id), 1.28, Vector2i(720, 480), path)
		var record := {"category": category, "rank": i + 1,
			"path": path, "tile_id": tile_id,
			"nickname": str(tile.get("nickname", "")),
			"metrics": tile.duplicate(true)}
		(manifest.captures as Array).append(record)
		category_records.append(record)
	manifest.categories[category] = category_records

func _write_dynamic_manifest(path: String, manifest: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("settlement_morphology_shot: cannot write '%s'" % path)
		return
	file.store_string(JSON.stringify(manifest, "  "))
	print("[MORPH SHOT] %s (dynamic diagnostic manifest)" % path)
