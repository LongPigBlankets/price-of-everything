extends Node
## Add one wood and loose connecting clumps to northern non-urban tiles that currently
## contain only one or two authored woods. The generated forest id makes this migration
## idempotent; compact tree_points keep the extra planting cheap to load and edit.
##
## Dry run (default):
##   <godot> --path . res://tools/map_editor/add_northern_forest_links.tscn --quit-after 60000
## Apply:
##   POE_NORTH_FOREST_APPLY=1 <godot> --path . \
##     res://tools/map_editor/add_northern_forest_links.tscn --quit-after 60000

const AuthoredMap := preload("res://scripts/authored_map.gd")

const DOCUMENT_NAME := "stoneshore-procedural"
const NORTH_MAX_ROW := 6
const FOREST_RADIUS := 78.0
const FOREST_DENSITY := 4.0
const FOREST_VARIANT := "current"
const CLUMP_RADIUS := 26.0
const MIN_FOREST_GAP := 124.0
const DESIRED_FOREST_GAP := 170.0
const ROAD_FOREST_CLEARANCE := 88.0
const ROAD_CLUMP_CLEARANCE := 32.0
const BUILDING_FOREST_CLEARANCE := 82.0
const BUILDING_CLUMP_CLEARANCE := 28.0
const TREE_DUPLICATE_CLEARANCE := 42.0
const GENERATED_ID_MARKER := ":north-link:"

var _terrain: Node
var _tile_centres: Dictionary = {}
var _roads: Array = []
var _building_polygons: Array = []
var _building_discs: Array = []
var _occupied_trees: Array[Vector2] = []


func _ready() -> void:
	AuthoredMap.set_override(DOCUMENT_NAME)
	var loaded := AuthoredMap.data()
	if loaded.is_empty():
		push_error("[NORTH-FORESTS] '%s' did not load" % DOCUMENT_NAME)
		get_tree().quit(1)
		return
	var doc: Dictionary = loaded.duplicate(true)
	if not _prepare_terrain():
		get_tree().quit(1)
		return
	var result := _apply(doc)
	print("[NORTH-FORESTS] targets=%d forests=%d clumps=%d skipped=%d" % [
		int(result.targets), int(result.forests), int(result.clumps), int(result.skipped)])
	print("[NORTH-FORESTS] tiles: %s" % ", ".join(result.tiles as Array))
	for note_value in (result.notes as Array):
		print("[NORTH-FORESTS] %s" % str(note_value))
	if OS.get_environment("POE_NORTH_FOREST_APPLY") != "1":
		print("[NORTH-FORESTS] dry run — set POE_NORTH_FOREST_APPLY=1 to save")
		get_tree().quit(0)
		return
	if int(result.forests) == 0:
		print("[NORTH-FORESTS] no changes needed")
		get_tree().quit(0)
		return
	var path := ProjectSettings.globalize_path(AuthoredMap.path_for(DOCUMENT_NAME))
	var problem := AuthoredMap.save_to(doc, path)
	if problem != "":
		push_error("[NORTH-FORESTS] %s" % problem)
		get_tree().quit(1)
		return
	print("[NORTH-FORESTS] saved %s" % path)
	get_tree().quit(0)


func _prepare_terrain() -> bool:
	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		push_error("[NORTH-FORESTS] could not load main scene")
		return false
	var scene := packed.instantiate()
	_terrain = scene.get_node_or_null(NodePath("TerrainLayer"))
	if _terrain == null:
		push_error("[NORTH-FORESTS] main scene has no TerrainLayer")
		scene.free()
		return false
	# Keep the unparented scene alive for coordinate calls until this one-shot tool exits.
	for tile_value in Catalog.all_tile_ids():
		var tile_id := str(tile_value)
		var coord: Vector2i = _terrain.call("id_to_coord", tile_id)
		if coord == Vector2i(-1, -1):
			continue
		var map_coord: Vector2i = _terrain.call("map_coord_for_tile_coord", coord)
		_tile_centres[tile_id] = _terrain.call("map_to_local", map_coord)
	return true


func _apply(doc: Dictionary) -> Dictionary:
	var settlements_value: Variant = doc.get("settlements", {})
	if typeof(settlements_value) != TYPE_DICTIONARY:
		return {"targets": 0, "forests": 0, "clumps": 0, "skipped": 0,
			"tiles": [], "notes": ["document has no settlements dictionary"]}
	var settlements: Dictionary = settlements_value
	var forest_by_tile: Dictionary = {}
	var all_forests: Array = []
	var generated_tiles: Dictionary = {}
	_index_obstacles_and_forests(settlements, forest_by_tile, all_forests, generated_tiles)

	var targets: Array[String] = []
	for tile_value in forest_by_tile.keys():
		var tile_id := str(tile_value)
		var count := (forest_by_tile[tile_id] as Array).size()
		if count < 1 or count > 2 or generated_tiles.has(tile_id):
			continue
		if not _is_northern_nonurban(tile_id):
			continue
		targets.append(tile_id)
	targets.sort_custom(_tile_less)

	var added_forests := 0
	var added_clumps := 0
	var skipped := 0
	var changed_tiles: Array[String] = []
	var notes: Array[String] = []
	for tile_id in targets:
		var existing: Array = forest_by_tile[tile_id]
		var centre := _choose_forest_centre(tile_id, existing, all_forests)
		if is_inf(centre.x):
			skipped += 1
			notes.append("%s skipped: no clear non-urban site" % tile_id)
			continue
		var owner := str((existing[0] as Dictionary).owner)
		if not settlements.has(owner):
			skipped += 1
			notes.append("%s skipped: source settlement disappeared" % tile_id)
			continue
		var settlement: Dictionary = settlements[owner]
		var record := {
			"id": "fo:%s:north-link:%s" % [owner, tile_id],
			"outline": _forest_outline(centre, tile_id),
			"density": FOREST_DENSITY,
			"variant": FOREST_VARIANT,
			"tiles": [tile_id],
		}
		var forests_value: Variant = settlement.get("forests", [])
		var forests: Array = forests_value if typeof(forests_value) == TYPE_ARRAY else []
		forests.append(record)
		settlement["forests"] = forests
		var new_info := {"centre": centre, "owner": owner, "tile": tile_id, "record": record}
		all_forests.append(new_info)
		var links := _link_targets(centre, existing, all_forests, tile_id)
		var tile_clumps := _add_link_clumps(settlement, centre, links)
		added_clumps += tile_clumps
		added_forests += 1
		changed_tiles.append(tile_id)
		notes.append("%s: %d -> %d woods, +%d linking clumps (%s)" % [
			tile_id, existing.size(), existing.size() + 1, tile_clumps, owner])
	return {"targets": targets.size(), "forests": added_forests, "clumps": added_clumps,
		"skipped": skipped, "tiles": changed_tiles, "notes": notes}


func _index_obstacles_and_forests(settlements: Dictionary, forest_by_tile: Dictionary,
		all_forests: Array, generated_tiles: Dictionary) -> void:
	var keys := settlements.keys()
	keys.sort()
	for key_value in keys:
		var owner := str(key_value)
		var settlement_value: Variant = settlements[key_value]
		if typeof(settlement_value) != TYPE_DICTIONARY:
			continue
		var settlement: Dictionary = settlement_value
		_roads.append_array(settlement.get("roads", []) as Array)
		for field in ["specials", "plazas"]:
			for record_value in (settlement.get(field, []) as Array):
				if typeof(record_value) == TYPE_DICTIONARY:
					var polygon := _outline((record_value as Dictionary).get("outline", []))
					if polygon.size() >= 3:
						_building_polygons.append(polygon)
		for decor_value in (settlement.get("decor", []) as Array):
			if typeof(decor_value) != TYPE_DICTIONARY:
				continue
			var decor: Dictionary = decor_value
			var pos := _point(decor.get("pos", null))
			var size := _point(decor.get("size", null))
			if not is_inf(pos.x):
				_building_discs.append({"centre": pos, "radius": 0.5 * size.length()})
		for tree_value in AuthoredMap.tree_records(settlement, owner):
			var tree_pos := _point((tree_value as Dictionary).get("position", null))
			if not is_inf(tree_pos.x):
				_occupied_trees.append(tree_pos)
		for forest_value in (settlement.get("forests", []) as Array):
			if typeof(forest_value) != TYPE_DICTIONARY:
				continue
			var forest: Dictionary = forest_value
			var centre := _centroid(forest.get("outline", []) as Array)
			if is_inf(centre.x):
				continue
			var tile_id := _tile_of(centre)
			if tile_id == "":
				continue
			var info := {"centre": centre, "owner": owner, "tile": tile_id, "record": forest}
			if not forest_by_tile.has(tile_id):
				forest_by_tile[tile_id] = []
			(forest_by_tile[tile_id] as Array).append(info)
			all_forests.append(info)
			if str(forest.get("id", "")).contains(GENERATED_ID_MARKER):
				generated_tiles[tile_id] = true


func _choose_forest_centre(tile_id: String, existing: Array, all_forests: Array) -> Vector2:
	var tile_centre: Vector2 = _tile_centres.get(tile_id, Vector2(INF, INF))
	if is_inf(tile_centre.x):
		return tile_centre
	var preferred := tile_centre
	if existing.size() == 1:
		var start: Vector2 = (existing[0] as Dictionary).centre
		var neighbour := _nearest_other_forest(start, existing, all_forests)
		var direction := (neighbour - start).normalized() if not is_inf(neighbour.x) \
			else (tile_centre - start).normalized()
		if direction == Vector2.ZERO:
			direction = Vector2.RIGHT.rotated(float(_stable_seed(tile_id) % 360) * PI / 180.0)
		preferred = start + direction * DESIRED_FOREST_GAP
	else:
		var a: Vector2 = (existing[0] as Dictionary).centre
		var b: Vector2 = (existing[1] as Dictionary).centre
		preferred = (a + b) * 0.5

	var best := Vector2(INF, INF)
	var best_score := INF
	var phase := float(_stable_seed(tile_id) % 360) * PI / 180.0
	var radii := [0.0, 42.0, 78.0, 112.0, 142.0]
	for radius_value in radii:
		var radius := float(radius_value)
		var samples := 1 if radius == 0.0 else 24
		for i in samples:
			var angle := phase + TAU * float(i) / float(samples)
			var candidate := tile_centre + Vector2(cos(angle), sin(angle)) * radius
			if not _forest_site_clear(candidate, tile_id, all_forests):
				continue
			var score := candidate.distance_to(preferred) + 0.12 * candidate.distance_to(tile_centre)
			for info_value in existing:
				var distance := candidate.distance_to((info_value as Dictionary).centre as Vector2)
				score += 0.7 * absf(distance - DESIRED_FOREST_GAP)
			if score < best_score:
				best_score = score
				best = candidate
	return best


func _forest_site_clear(point: Vector2, tile_id: String, all_forests: Array) -> bool:
	if _tile_of(point) != tile_id:
		return false
	var outline := _forest_outline(point, tile_id)
	for vertex_value in outline:
		var vertex := _point(vertex_value)
		var vertex_tile := _tile_of(vertex)
		if vertex_tile != "" and Catalog.tile_type(vertex_tile) == "urban":
			return false
	for info_value in all_forests:
		if point.distance_to((info_value as Dictionary).centre as Vector2) < MIN_FOREST_GAP:
			return false
	if _near_roads(point, ROAD_FOREST_CLEARANCE):
		return false
	if _near_buildings(point, BUILDING_FOREST_CLEARANCE):
		return false
	return true


func _link_targets(new_centre: Vector2, existing: Array, all_forests: Array,
		tile_id: String) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for info_value in existing:
		out.append((info_value as Dictionary).centre as Vector2)
	if existing.size() == 1:
		var external := _nearest_other_forest(new_centre, existing, all_forests)
		if not is_inf(external.x) and new_centre.distance_to(external) <= 650.0 \
				and _link_stays_clear_of_urban(new_centre, external):
			out.append(external)
	# Long links are visual noise; the local wood is always linked first.
	var filtered: Array[Vector2] = []
	for target in out:
		if new_centre.distance_to(target) <= 650.0 and target != new_centre:
			filtered.append(target)
	return filtered


func _add_link_clumps(settlement: Dictionary, start: Vector2, links: Array[Vector2]) -> int:
	var added := 0
	for link_index in links.size():
		var finish := links[link_index]
		var direction := (finish - start).normalized()
		if direction == Vector2.ZERO:
			continue
		var normal := Vector2(-direction.y, direction.x)
		for sample_index in 3:
			var t := 0.28 + 0.22 * float(sample_index)
			var side := -1.0 if (sample_index + link_index) % 2 == 0 else 1.0
			var candidate := start.lerp(finish, t) + normal * side * (12.0 + 5.0 * sample_index)
			if not _clump_site_clear(candidate):
				continue
			if AuthoredMap.append_tree(settlement, "mixed", candidate, CLUMP_RADIUS):
				_occupied_trees.append(candidate)
				added += 1
	return added


func _clump_site_clear(point: Vector2) -> bool:
	var tile_id := _tile_of(point)
	if not _is_northern_nonurban(tile_id):
		return false
	if _near_roads(point, ROAD_CLUMP_CLEARANCE) or _near_buildings(point, BUILDING_CLUMP_CLEARANCE):
		return false
	for old in _occupied_trees:
		if point.distance_to(old) < TREE_DUPLICATE_CLEARANCE:
			return false
	return true


func _near_roads(point: Vector2, clearance: float) -> bool:
	for road_value in _roads:
		if typeof(road_value) != TYPE_DICTIONARY:
			continue
		var line := _polyline((road_value as Dictionary).get("points", []))
		for i in range(line.size() - 1):
			if point.distance_to(Geometry2D.get_closest_point_to_segment(
					point, line[i], line[i + 1])) < clearance:
				return true
	return false


func _near_buildings(point: Vector2, clearance: float) -> bool:
	for polygon_value in _building_polygons:
		var polygon: PackedVector2Array = polygon_value
		if Geometry2D.is_point_in_polygon(point, polygon):
			return true
		for i in polygon.size():
			if point.distance_to(Geometry2D.get_closest_point_to_segment(
					point, polygon[i], polygon[(i + 1) % polygon.size()])) < clearance:
				return true
	for disc_value in _building_discs:
		var disc: Dictionary = disc_value
		if point.distance_to(disc.centre as Vector2) < float(disc.radius) + clearance:
			return true
	return false


func _nearest_other_forest(point: Vector2, excluded: Array, all_forests: Array) -> Vector2:
	var excluded_centres: Array[Vector2] = []
	for info_value in excluded:
		excluded_centres.append((info_value as Dictionary).centre as Vector2)
	var best := Vector2(INF, INF)
	var best_distance := INF
	for info_value in all_forests:
		var candidate: Vector2 = (info_value as Dictionary).centre
		if excluded_centres.has(candidate):
			continue
		var tile_id := str((info_value as Dictionary).tile)
		if not _is_northern_nonurban(tile_id):
			continue
		var distance := point.distance_to(candidate)
		if distance < best_distance:
			best_distance = distance
			best = candidate
	return best


func _link_stays_clear_of_urban(start: Vector2, finish: Vector2) -> bool:
	for i in 9:
		var tile_id := _tile_of(start.lerp(finish, float(i) / 8.0))
		if tile_id != "" and Catalog.tile_type(tile_id) == "urban":
			return false
	return true


func _forest_outline(centre: Vector2, token: String) -> Array:
	var out: Array = []
	var salt := _stable_seed(token)
	for i in 8:
		var angle := TAU * float(i) / 8.0
		var wobble := 0.82 + 0.28 * absf(sin(float(i) * 2.3 + float(salt % 17) * 0.4))
		var point := centre + Vector2(cos(angle), sin(angle)) * FOREST_RADIUS * wobble
		out.append([snappedf(point.x, 0.01), snappedf(point.y, 0.01)])
	return out


func _tile_of(point: Vector2) -> String:
	var map_coord: Vector2i = _terrain.call("local_to_map", point)
	var coord: Vector2i = _terrain.call("tile_coord_for_map_coord", map_coord)
	var tile_id := "tile_%d_%d" % [coord.x + 1, coord.y + 1]
	return tile_id if _tile_centres.has(tile_id) else ""


func _is_northern_nonurban(tile_id: String) -> bool:
	if tile_id == "" or not _tile_centres.has(tile_id):
		return false
	var coord: Vector2i = _terrain.call("id_to_coord", tile_id)
	if coord.y < 0 or coord.y + 1 > NORTH_MAX_ROW:
		return false
	var tile_type := Catalog.tile_type(tile_id)
	return tile_type != "urban" and tile_type != "sea" and tile_type != "deep_sea"


func _tile_less(a: String, b: String) -> bool:
	var ca: Vector2i = _terrain.call("id_to_coord", a)
	var cb: Vector2i = _terrain.call("id_to_coord", b)
	return ca.y < cb.y or (ca.y == cb.y and ca.x < cb.x)


func _centroid(points: Array) -> Vector2:
	if points.is_empty():
		return Vector2(INF, INF)
	var total := Vector2.ZERO
	var count := 0
	for point_value in points:
		var point := _point(point_value)
		if is_inf(point.x):
			continue
		total += point
		count += 1
	return total / float(count) if count > 0 else Vector2(INF, INF)


func _outline(value: Variant) -> PackedVector2Array:
	var out := PackedVector2Array()
	if typeof(value) != TYPE_ARRAY:
		return out
	for point_value in (value as Array):
		var point := _point(point_value)
		if not is_inf(point.x):
			out.append(point)
	return out


func _polyline(value: Variant) -> PackedVector2Array:
	return _outline(value)


func _point(value: Variant) -> Vector2:
	if typeof(value) == TYPE_VECTOR2:
		return value
	if typeof(value) == TYPE_ARRAY and (value as Array).size() >= 2:
		return Vector2(float((value as Array)[0]), float((value as Array)[1]))
	return Vector2(INF, INF)


func _stable_seed(value: String) -> int:
	var result := 17
	for byte in value.to_utf8_buffer():
		result = int((result * 131 + int(byte)) % 2147483647)
	return result
