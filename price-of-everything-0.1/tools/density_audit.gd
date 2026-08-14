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
			"green_polys": [],
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
	for mass_value in snapshot.get("masses", []):
		var mass: Dictionary = mass_value
		var area := float(mass.area)
		areas.append(area)
		var kind := str(mass.kind)
		if not DensityAudit.counts_as_building(kind, area):
			uncounted_masses += 1
			continue
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
		(record.green_polys as Array).append(green.poly)

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
		var green_spaces := _merge_green_spaces(record.green_polys)
		var green_area := 0.0
		for green_value in green_spaces:
			green_area += abs(_poly_area(green_value))
		var geometry: Dictionary = {}
		var evaluation: Dictionary = {}
		if tile_class != DensityAudit.CLASS_WATER:
			geometry = geometry_by_coord.get(Vector2i(int(record.coord[0]),
				int(record.coord[1])), {})
			evaluation = DensityAudit.evaluate(tile_class,
				int(record.small_count), int(record.large_count),
				green_spaces.size(),
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
func _merge_green_spaces(polys: Array) -> Array:
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
	var out: Array = []
	for poly_value in merged:
		var poly: PackedVector2Array = poly_value
		if poly.size() >= 3 and absf(_poly_area(poly)) >= \
				DensityAudit.MIN_COUNTED_GREEN_AREA:
			out.append(poly)
	return out


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
	lines.append("FULL TILE TABLE")
	lines.append("  %-12s %-26s %-9s %5s %5s %5s %10s %10s  %s" % [
		"tile", "nickname", "class", "small", "large", "park",
		"park_area", "dry_area", "verdict"])
	for tile_value in report.tiles:
		var tile: Dictionary = tile_value
		if str(tile["class"]) == DensityAudit.CLASS_WATER:
			continue
		var verdict := "PASS"
		if not bool(tile.get("passes", true)):
			verdict = "FAIL %s" % str(tile.failures)
			if bool(tile.get("physically_constrained", false)):
				verdict += " [physically constrained]"
		lines.append("  %-12s %-26s %-9s %5d %5d %5d %10.0f %10.0f  %s" % [
			str(tile.tile_id), str(tile.nickname).substr(0, 26), str(tile["class"]),
			int(tile.small_count), int(tile.large_count), int(tile.park_count),
			float(tile.park_area), float(tile.dry_buildable_area), verdict])
	lines.append("")
	lines.append("FAILURES (%d)" % int(summary.failing_tiles))
	for tile_value in report.failures:
		var tile: Dictionary = tile_value
		var req: Dictionary = tile.requirements
		lines.append("  %-12s %-9s %-24s small=%d (min %d, max %d)  large=%d (min %d, max %d)  park=%d (min %d)  dry=%.0f/%.0f  %s%s" % [
			str(tile.tile_id), str(tile["class"]), str(tile.nickname).substr(0, 24),
			int(tile.small_count), int(req.small_min), int(req.small_max),
			int(tile.large_count), int(req.large_min), int(req.large_max),
			int(tile.park_count), int(req.park_min),
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
