extends RefCounted
## The `enable procedural <region>` cheats: cut one city's share of the imported live map
## out of `data/map_authored/procedural.json` and merge it into the editor's working
## document as an editable settlement.
##
## EDITOR-ONLY (see the header of `map_editor.gd`). The debug terminal reaches the editor
## by group + `call()`, never by preloading this file.
##
## WHY REGIONS. The land the authored look has not touched yet is too big to import as one
## piece (the whole-map import runs to ~2300 shapes), so it is split FOUR WAYS by which city
## each tile is closest to: Port Lightning in the north, Arin City, Vandel Port and Capital
## Port. Every untouched land tile belongs to exactly one region, so enabling all four shows
## the whole remaining map and enabling one shows a piece small enough to edit.
##
## THE SOURCE IS A FILE, NOT THE LIVE WORLD. `UrbanFabricVisuals` stands the whole
## procedural fabric down while any authored document is active (its `_draws_here()`), so
## inside the editor there are no live records to read — and rebuilding fabric under an
## authored map is the exact rebuild-storm `_draws_here` exists to prevent. The
## `import_live_map` tool boots a blind world and writes everything to `procedural.json`;
## this module only selects, renumbers and merges. Regenerate the file after fabric changes:
##
##     <godot> --path . res://tools/map_editor/import_live_map.tscn --quit-after 30000 \
##         -- --name=procedural
##
## OWNERSHIP RULES (what stops a record importing twice):
## - A record with an area (mass, park, plaza) belongs to the region of the tile under its
##   centroid. One tile, one region, so one owner.
## - A ROAD belongs to the region nearest its polyline's centroid — a road that crosses a
##   region boundary is imported whole by one region rather than cut or doubled.
## - A road touching ANY tile the document already authors is skipped entirely: the
##   Stoneshore imports took every edge touching their tiles, so such an edge is already in
##   the document (or was deliberately deleted from it, which this must respect).
## - Forests are never imported here: `import_forests` already wrote every wood on the map
##   into the active document as `forests` areas, and the authored painter draws them as
##   individual trees. Importing them again would draw every wood twice.

const AuthoredMap := preload("res://scripts/authored_map.gd")

## Cheat-facing region names, in tie-break order: a tile equidistant from two anchors goes
## to the earlier entry, so the partition is deterministic.
const REGIONS := ["north", "arin", "vandel", "capital"]

## The tile whose centre anchors each region — the city the region is "near".
## north = Port Lightning (the northern settlement, tile row 2).
const REGION_ANCHORS := {
	"north": "tile_14_2",      # Port Lightning
	"arin": "tile_11_17",      # Arin City
	"vandel": "tile_22_16",    # Vandel Port
	"capital": "tile_25_9",    # Capital Port
}

## Working-document settlement key per region. The prefix marks these as regenerable
## imports, and [method covered_tiles] uses it to keep them OUT of the "already authored"
## set — the partition must not shrink because a sibling region is currently shown.
const SETTLEMENT_PREFIX := "procedural-"

const SOURCE_PATH := "res://data/map_authored/procedural.json"

## Stoneshore's planted-tree layer is the reference for the four imported city regions.
## It is deliberately a TEMPLATE, not another generated forest: the source is a loose
## eleven-hex fringe of individual specimens and small mixed stands woven between streets.
## Copying that visual grammar into every tile would both look tiled and recreate the editor
## performance failure that prompted compact tree storage, so one transformed footprint is
## fitted around each region anchor and clipped against the imported fabric.
const TREE_PATTERN_SOURCE_ANCHOR := "tile_5_10"
const TREE_PATTERN_SOURCE_RADIUS := 1500.0
const TREE_ROAD_CLEARANCE := 8.0
const TREE_MASS_CLEARANCE := 5.0
const TREE_DUPLICATE_CLEARANCE := 4.0

## North and Stoneshore use a second planting grammar beside the loose fringe: irregular
## runs of individual trees tucked against the road edge. These measured defaults retain
## deliberate gaps, so the result reads as incidental planting rather than a rigid avenue.
const ROADSIDE_TREE_SPACING := 90.0
const ROADSIDE_TREE_MIN_SEGMENT := 50.0
const ROADSIDE_TREE_CHANCE := 22
const ROADSIDE_TREE_MIN_OFFSET := 10.0
const ROADSIDE_TREE_OFFSET_STEPS := 8
const ROADSIDE_TREE_ROAD_CLEARANCE := 7.5
const ROADSIDE_TREE_DUPLICATE_CLEARANCE := 3.0

## Focused, removable review layer for Copperstown. The live procedural source already has
## the desired polygon vocabulary; the active authored document simply predates this fabric.
const CENTRAL_BUILDINGS_KEY := "procedural-central-buildings"
const CENTRAL_BUILDING_FOCUS_TILE := "tile_13_9"
const CENTRAL_BUILDING_TILES := ["tile_12_8", "tile_12_9", "tile_13_9", "tile_14_9"]

## Tie-break order when several symmetries fit equally well. The best fit still wins (coasts
## and city fabric decide that); different first choices keep the four cities from looking
## like literal copies when their rejection masks happen to be similar.
const TREE_TRANSFORM_ORDER := {
	"north": [4, 5, 6, 7, 0, 1, 2, 3],
	"arin": [2, 3, 0, 1, 6, 7, 4, 5],
	"vandel": [1, 0, 3, 2, 5, 4, 7, 6],
	"capital": [7, 6, 5, 4, 3, 2, 1, 0],
}


static func is_region(value: String) -> bool:
	return REGIONS.has(value)


static func settlement_key(region: String) -> String:
	return SETTLEMENT_PREFIX + region


## Every tile the document already authors, EXCLUDING the regenerable region imports
## themselves (unless asked for). This is the "touched by the authored look" set the owner's
## split is defined against.
static func covered_tiles(doc: Dictionary, include_regions: bool = false) -> Dictionary:
	var out: Dictionary = {}
	var settlements_value: Variant = doc.get("settlements", {})
	if typeof(settlements_value) != TYPE_DICTIONARY:
		return out
	var settlements: Dictionary = settlements_value
	for key_value in settlements.keys():
		var key := str(key_value)
		if not include_regions and key.begins_with(SETTLEMENT_PREFIX):
			continue
		var settlement_value: Variant = settlements[key_value]
		if typeof(settlement_value) != TYPE_DICTIONARY:
			continue
		for tile_value in ((settlement_value as Dictionary).get("tiles", []) as Array):
			out[str(tile_value)] = true
	return out


## The region a world point belongs to: nearest anchor, ties to the earlier region.
## `centres` is {tile_id: Vector2} and must contain every anchor tile.
static func region_of_point(point: Vector2, centres: Dictionary) -> String:
	var best := ""
	var best_distance := INF
	for region in REGIONS:
		var anchor_value: Variant = centres.get(str(REGION_ANCHORS[region]), null)
		if typeof(anchor_value) != TYPE_VECTOR2:
			continue
		var distance := point.distance_squared_to(anchor_value)
		if distance < best_distance:
			best_distance = distance
			best = str(region)
	return best


## Split the untouched land into the four regions: {tile_id: region} for every tile in
## `centres` (land tiles only — the caller filters sea) that is not in `covered`.
static func partition(centres: Dictionary, covered: Dictionary) -> Dictionary:
	for region in REGIONS:
		if typeof(centres.get(str(REGION_ANCHORS[region]), null)) != TYPE_VECTOR2:
			return {}   # anchor missing from the terrain — nothing sane to compute
	var out: Dictionary = {}
	for tile_value in centres.keys():
		var tile_id := str(tile_value)
		if covered.has(tile_id):
			continue
		out[tile_id] = region_of_point(centres[tile_value], centres)
	return out


## The tiles of one region, as the {tile_id: true} set the record filters use.
static func region_tiles(partitioned: Dictionary, region: String) -> Dictionary:
	var out: Dictionary = {}
	for tile_value in partitioned.keys():
		if str(partitioned[tile_value]) == region:
			out[str(tile_value)] = true
	return out


## The whole-map import, freshly parsed (so nothing aliases the editor's document).
## Returns {"doc": Dictionary} or {"problem": String}.
static func load_source() -> Dictionary:
	if not FileAccess.file_exists(SOURCE_PATH):
		return {"problem": "no %s — regenerate it: <godot> --path . res://tools/map_editor/import_live_map.tscn --quit-after 30000 -- --name=procedural" % SOURCE_PATH.get_file()}
	var file := FileAccess.open(SOURCE_PATH, FileAccess.READ)
	if file == null:
		return {"problem": "%s exists but could not be opened" % SOURCE_PATH.get_file()}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"problem": "%s did not parse" % SOURCE_PATH.get_file()}
	var doc: Dictionary = parsed
	var errors := AuthoredMap.validate(doc)
	if not errors.is_empty():
		return {"problem": "%s failed validation — regenerate it (%s)"
			% [SOURCE_PATH.get_file(), errors[0]]}
	return {"doc": doc}


## One region's settlement, cut from the source document. Empty when the region holds
## nothing. `tile_of` maps a world Vector2 to a tile id (the editor binds the terrain).
##
## The settlement claims EVERY tile of the region, not just the tiles records landed on:
## the region is the unit the owner toggles, and claiming it whole means the procedural
## systems stand down for exactly the ground the import replaces once the document is saved.
static func build_settlement(source: Dictionary, region: String, tiles_of_region: Dictionary,
		covered: Dictionary, tile_of: Callable, centres: Dictionary,
		tree_template: Dictionary = {}, tree_blockers: Array = []) -> Dictionary:
	if tiles_of_region.is_empty():
		return {}
	var roads: Array = []
	var specials: Array = []
	var parks: Array = []
	var plazas: Array = []
	var port_decor: Array = []
	var slots: Dictionary = {}

	var settlements_value: Variant = source.get("settlements", {})
	var settlements: Dictionary = settlements_value if typeof(settlements_value) == TYPE_DICTIONARY else {}
	var keys := settlements.keys()
	keys.sort()   # deterministic ids whatever the parse order
	for key in keys:
		var settlement_value: Variant = settlements[key]
		if typeof(settlement_value) != TYPE_DICTIONARY:
			continue
		var settlement: Dictionary = settlement_value

		for road_value in (settlement.get("roads", []) as Array):
			var road: Dictionary = road_value
			if _touches(road.get("tiles", []) as Array, covered):
				continue   # already authored (or deliberately deleted) by a real settlement
			if region_of_point(_centroid(road.get("points", []) as Array), centres) != region:
				continue
			var copy: Dictionary = road.duplicate(true)
			copy["id"] = "r:%s:%d" % [region, roads.size()]
			roads.append(copy)

		for special_value in (settlement.get("specials", []) as Array):
			var special: Dictionary = special_value
			var anchor := str(special.get("port", ""))
			if anchor == "":
				anchor = str(tile_of.call(_centroid(special.get("outline", []) as Array)))
			if not tiles_of_region.has(anchor):
				continue
			var copy: Dictionary = special.duplicate(true)
			copy["id"] = "s:%s:%d" % [region, specials.size()]
			specials.append(copy)

		for park_value in (settlement.get("parks", []) as Array):
			var park: Dictionary = park_value
			if not tiles_of_region.has(str(tile_of.call(_centroid(park.get("outline", []) as Array)))):
				continue
			var copy: Dictionary = park.duplicate(true)
			copy["id"] = "p:%s:%d" % [region, parks.size()]
			parks.append(copy)

		for plaza_value in (settlement.get("plazas", []) as Array):
			var plaza: Dictionary = plaza_value
			if not tiles_of_region.has(str(tile_of.call(_centroid(plaza.get("outline", []) as Array)))):
				continue
			var copy: Dictionary = plaza.duplicate(true)
			copy["id"] = "pz:%s:%d" % [region, plazas.size()]
			plazas.append(copy)

		for decor_value in (settlement.get("port_decor", []) as Array):
			var decor: Dictionary = decor_value
			if tiles_of_region.has(str(decor.get("tile", ""))):
				port_decor.append(decor.duplicate(true))

		var slots_value: Variant = settlement.get("slots", {})
		if typeof(slots_value) == TYPE_DICTIONARY:
			for tile_value in (slots_value as Dictionary).keys():
				if tiles_of_region.has(str(tile_value)):
					slots[str(tile_value)] = ((slots_value as Dictionary)[tile_value] as Dictionary).duplicate(true)

	var tile_list := tiles_of_region.keys()
	tile_list.sort()
	var out := {
		"tiles": tile_list,
		"next_id": roads.size() + specials.size() + parks.size() + plazas.size() + 1,
		"roads": roads,
		"specials": specials,
		"parks": parks,
		"plazas": plazas,
		"slots": slots,
	}
	var tree_points := patterned_tree_points(tree_template, region, tiles_of_region, tile_of,
		centres, roads, specials, plazas, tree_blockers)
	var patterned_records := AuthoredMap.tree_records(
		{AuthoredMap.TREE_POINTS_FIELD: tree_points}, "pattern-%s" % region)
	var roadside := roadside_tree_points(tiles_of_region, tile_of, roads,
		specials + plazas, patterned_records, tree_blockers, region)
	_merge_tree_groups(tree_points, roadside)
	if not tree_points.is_empty():
		out[AuthoredMap.TREE_POINTS_FIELD] = tree_points
	if not port_decor.is_empty():
		out["port_decor"] = port_decor
	return out


## Copy only Copperstown's decorative building polygons into a removable review layer.
## Roads stay in the active settlement; this command is intentionally scoped to buildings.
static func build_central_buildings(source: Dictionary, tile_of: Callable) -> Dictionary:
	var wanted: Dictionary = {}
	for tile_id in CENTRAL_BUILDING_TILES:
		wanted[str(tile_id)] = true
	var specials: Array = []
	var settlements_value: Variant = source.get("settlements", {})
	if typeof(settlements_value) != TYPE_DICTIONARY:
		return {}
	var settlements: Dictionary = settlements_value
	var keys := settlements.keys()
	keys.sort()
	for key_value in keys:
		var settlement_value: Variant = settlements[key_value]
		if typeof(settlement_value) != TYPE_DICTIONARY:
			continue
		for special_value in ((settlement_value as Dictionary).get("specials", []) as Array):
			var special: Dictionary = special_value
			var tile_id := str(special.get("port", ""))
			if tile_id == "":
				tile_id = str(tile_of.call(_centroid(special.get("outline", []) as Array)))
			if not wanted.has(tile_id):
				continue
			var copy := special.duplicate(true)
			copy["id"] = "s:central:%d" % specials.size()
			specials.append(copy)
	if specials.is_empty():
		return {}
	return {
		"tiles": CENTRAL_BUILDING_TILES.duplicate(),
		"next_id": specials.size() + 1,
		"roads": [],
		"specials": specials,
		"parks": [],
		"plazas": [],
		"slots": {},
	}


## Capture Stoneshore's current standalone planting as offsets from its city anchor. Only
## points in the local fringe are used, so unrelated trees added elsewhere later cannot
## silently change every procedural city on the next import.
static func stoneshore_tree_template(doc: Dictionary, centres: Dictionary) -> Dictionary:
	var anchor_value: Variant = centres.get(TREE_PATTERN_SOURCE_ANCHOR, null)
	if typeof(anchor_value) != TYPE_VECTOR2:
		return {}
	var anchor: Vector2 = anchor_value
	var points: Array = []
	var settlements_value: Variant = doc.get("settlements", {})
	if typeof(settlements_value) != TYPE_DICTIONARY:
		return {}
	var settlements: Dictionary = settlements_value
	var keys := settlements.keys()
	keys.sort()
	for key_value in keys:
		var key := str(key_value)
		# A re-import must never learn from its own earlier output.
		if key.begins_with(SETTLEMENT_PREFIX):
			continue
		var settlement_value: Variant = settlements[key_value]
		if typeof(settlement_value) != TYPE_DICTIONARY:
			continue
		for record_value in AuthoredMap.tree_records(settlement_value as Dictionary, key):
			var record: Dictionary = record_value
			var pos := _point(record.get("position", null))
			if pos.distance_to(anchor) > TREE_PATTERN_SOURCE_RADIUS:
				continue
			var item := {
				"kind": str(record.get("kind", "small")),
				"offset": pos - anchor,
			}
			if str(item.kind) == "mixed":
				item["radius"] = float(record.get("radius", 0.0))
			points.append(item)
	return {"points": points} if not points.is_empty() else {}


## Fit the Stoneshore footprint to one generated region. Eight rotations/reflections are
## tried and the version retaining the most clear, on-land points wins. Output is already in
## the compact on-disk representation used by AuthoredMap, grouped by visible kind.
static func patterned_tree_points(tree_template: Dictionary, region: String,
		tiles_of_region: Dictionary, tile_of: Callable, centres: Dictionary, roads: Array,
		specials: Array, plazas: Array, tree_blockers: Array = []) -> Dictionary:
	if tree_template.is_empty() or not REGION_ANCHORS.has(region):
		return {}
	var points_value: Variant = tree_template.get("points", [])
	if typeof(points_value) != TYPE_ARRAY or (points_value as Array).is_empty():
		return {}
	var anchor_value: Variant = centres.get(str(REGION_ANCHORS[region]), null)
	if typeof(anchor_value) != TYPE_VECTOR2:
		return {}
	var anchor: Vector2 = anchor_value
	var polygon_blockers: Array = []
	for record_value in specials + plazas:
		var outline := _outline((record_value as Dictionary).get("outline", []))
		if outline.size() >= 3:
			polygon_blockers.append(outline)
	for blocker_value in tree_blockers:
		var blocker := _outline(blocker_value)
		if blocker.size() >= 3:
			polygon_blockers.append(blocker)

	var best: Array = []
	var order: Array = TREE_TRANSFORM_ORDER.get(region, [0, 1, 2, 3, 4, 5, 6, 7])
	for transform_value in order:
		var transform_index := int(transform_value)
		var accepted: Array = []
		for point_value in (points_value as Array):
			if typeof(point_value) != TYPE_DICTIONARY:
				continue
			var source: Dictionary = point_value
			var kind := str(source.get("kind", "small"))
			if not AuthoredMap.TREE_KINDS.has(kind):
				continue
			var candidate := anchor + _tree_transform(
				(source.get("offset", Vector2.ZERO) as Vector2), transform_index)
			var radius := float(source.get("radius", 0.0))
			var reach := _tree_reach(kind, radius)
			if not _tree_clear(candidate, reach, tiles_of_region, tile_of, roads,
					polygon_blockers, accepted):
				continue
			accepted.append({"kind": kind, "position": candidate, "radius": radius})
		if accepted.size() > best.size():
			best = accepted

	var groups: Dictionary = {}
	for record_value in best:
		var record: Dictionary = record_value
		var kind := str(record.kind)
		if not groups.has(kind):
			groups[kind] = []
		var pos: Vector2 = record.position
		var compact: Array = [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01)]
		if kind == "mixed":
			compact.append(snappedf(float(record.radius), 0.01))
		(groups[kind] as Array).append(compact)
	return groups


## Generate sparse, deterministic road-edge planting. Existing trees are blockers, which
## makes this safe to run over hand-planted areas and makes a second pass a true no-op.
static func roadside_tree_points(allowed_tiles: Dictionary, tile_of: Callable, roads: Array,
		polygon_records: Array, occupied_records: Array = [], tree_blockers: Array = [],
		salt: String = "roadside", keepout_centres: Array = []) -> Dictionary:
	var polygon_blockers: Array = []
	for record_value in polygon_records:
		if typeof(record_value) != TYPE_DICTIONARY:
			continue
		var outline := _outline((record_value as Dictionary).get("outline", []))
		if outline.size() >= 3:
			polygon_blockers.append(outline)
	for blocker_value in tree_blockers:
		var blocker := _outline(blocker_value)
		if blocker.size() >= 3:
			polygon_blockers.append(blocker)

	var occupied: Array = []
	for record_value in occupied_records:
		if typeof(record_value) != TYPE_DICTIONARY:
			continue
		var record: Dictionary = record_value
		occupied.append({
			"kind": str(record.get("kind", "small")),
			"position": _point(record.get("position", null)),
			"radius": float(record.get("radius", 0.0)),
		})

	var accepted: Array = []
	for road_index in roads.size():
		var road_value: Variant = roads[road_index]
		if typeof(road_value) != TYPE_DICTIONARY:
			continue
		var road: Dictionary = road_value
		var line := _polyline(road.get("points", []))
		for segment_index in range(line.size() - 1):
			var start := line[segment_index]
			var finish := line[segment_index + 1]
			var length := start.distance_to(finish)
			if length < ROADSIDE_TREE_MIN_SEGMENT:
				continue
			var direction := (finish - start) / length
			var normal := Vector2(-direction.y, direction.x)
			var sample_count := maxi(1, int(floor(length / ROADSIDE_TREE_SPACING)))
			for sample_index in sample_count:
				var token := "%s:%s:%d:%d:%d" % [salt,
					str(road.get("id", road_index)), segment_index, sample_index, sample_count]
				var seed := _stable_tree_seed(token)
				if seed % 100 >= ROADSIDE_TREE_CHANCE:
					continue
				var along := (float(sample_index) + 0.5) * length / float(sample_count)
				along += float((seed / 101) % 17 - 8)
				along = clampf(along, 0.2 * length, 0.8 * length)
				var primary_side := -1.0 if (seed / 211) % 2 == 0 else 1.0
				var sides := [primary_side]
				if (seed / 307) % 11 == 0:
					sides.append(-primary_side)
				for side_value in sides:
					var side := float(side_value)
					var variant_seed := _stable_tree_seed("%s:%d" % [token, int(side)])
					var kind := "small" if variant_seed % 5 < 3 else "large"
					var offset := ROADSIDE_TREE_MIN_OFFSET \
						+ float((variant_seed / 17) % ROADSIDE_TREE_OFFSET_STEPS)
					var candidate := start + direction * along + normal * side * offset
					if _roadside_tree_clear(candidate, kind, allowed_tiles, tile_of, roads,
							polygon_blockers, occupied, accepted, keepout_centres):
						accepted.append({"kind": kind, "position": candidate, "radius": 0.0})

	var groups: Dictionary = {}
	for record_value in accepted:
		var record: Dictionary = record_value
		var kind := str(record.kind)
		if not groups.has(kind):
			groups[kind] = []
		var pos: Vector2 = record.position
		(groups[kind] as Array).append([snappedf(pos.x, 0.01), snappedf(pos.y, 0.01)])
	return groups


static func _roadside_tree_clear(point: Vector2, kind: String, allowed_tiles: Dictionary,
		tile_of: Callable, roads: Array, polygon_blockers: Array, occupied: Array,
		accepted: Array, keepout_centres: Array) -> bool:
	var tile_id := str(tile_of.call(point))
	if tile_id == "" or not allowed_tiles.has(tile_id):
		return false
	for centre_value in keepout_centres:
		if typeof(centre_value) == TYPE_VECTOR2 \
				and point.distance_to(centre_value as Vector2) <= TREE_PATTERN_SOURCE_RADIUS:
			return false
	for road_value in roads:
		var line := _polyline((road_value as Dictionary).get("points", []))
		for i in range(line.size() - 1):
			if point.distance_to(Geometry2D.get_closest_point_to_segment(
					point, line[i], line[i + 1])) < ROADSIDE_TREE_ROAD_CLEARANCE:
				return false
	var reach := _tree_reach(kind, 0.0)
	for polygon_value in polygon_blockers:
		var polygon: PackedVector2Array = polygon_value
		if Geometry2D.is_point_in_polygon(point, polygon):
			return false
		for i in polygon.size():
			if point.distance_to(Geometry2D.get_closest_point_to_segment(
					point, polygon[i], polygon[(i + 1) % polygon.size()])) < reach:
				return false
	for prior_value in occupied + accepted:
		var prior: Dictionary = prior_value
		var prior_reach := _tree_reach(str(prior.kind), float(prior.radius))
		if point.distance_to(prior.position as Vector2) \
				< minf(reach, prior_reach) + ROADSIDE_TREE_DUPLICATE_CLEARANCE:
			return false
	return true


static func _stable_tree_seed(value: String) -> int:
	var result := 17
	for byte in value.to_utf8_buffer():
		result = int((result * 131 + int(byte)) % 2147483647)
	return result


static func _merge_tree_groups(target: Dictionary, source: Dictionary) -> void:
	for kind_value in source:
		var kind := str(kind_value)
		if not target.has(kind):
			target[kind] = []
		(target[kind] as Array).append_array(source[kind_value] as Array)


## One-time/backfill path for generated areas that were already merged before patterned
## planting existed. Points are routed into whichever settlement owns the land beneath them;
## exact-coordinate de-duplication makes the operation idempotent without storing hidden ids
## beside every compact point. Future `enable procedural` imports use build_settlement above.
static func apply_pattern_to_existing(doc: Dictionary, regions: Array, centres: Dictionary,
		tile_of: Callable) -> Dictionary:
	var tree_template := stoneshore_tree_template(doc, centres)
	if tree_template.is_empty():
		return {"total": 0, "regions": {}}
	var settlements_value: Variant = doc.get("settlements", {})
	if typeof(settlements_value) != TYPE_DICTIONARY:
		return {"total": 0, "regions": {}}
	var settlements: Dictionary = settlements_value
	var owner_of: Dictionary = {}
	var roads: Array = []
	var specials: Array = []
	var plazas: Array = []
	var forest_blockers: Array = []
	var occupied: Array[Vector2] = []
	var keys := settlements.keys()
	keys.sort()
	for key_value in keys:
		var settlement_value: Variant = settlements[key_value]
		if typeof(settlement_value) != TYPE_DICTIONARY:
			continue
		var settlement: Dictionary = settlement_value
		for tile_value in (settlement.get("tiles", []) as Array):
			owner_of[str(tile_value)] = str(key_value)
		roads.append_array(settlement.get("roads", []) as Array)
		specials.append_array(settlement.get("specials", []) as Array)
		plazas.append_array(settlement.get("plazas", []) as Array)
		for forest_value in (settlement.get("forests", []) as Array):
			if typeof(forest_value) == TYPE_DICTIONARY:
				forest_blockers.append((forest_value as Dictionary).get("outline", []))
		for tree_value in AuthoredMap.tree_records(settlement, str(key_value)):
			occupied.append(_point((tree_value as Dictionary).get("position", null)))

	var allowed: Dictionary = {}
	for tile_id in owner_of:
		allowed[str(tile_id)] = true
	var per_region: Dictionary = {}
	var total := 0
	for region_value in regions:
		var region := str(region_value)
		if not is_region(region):
			continue
		var generated := patterned_tree_points(tree_template, region, allowed, tile_of, centres,
			roads, specials, plazas, forest_blockers)
		var added := 0
		var generated_settlement := {AuthoredMap.TREE_POINTS_FIELD: generated}
		for record_value in AuthoredMap.tree_records(generated_settlement, "backfill-%s" % region):
			var record: Dictionary = record_value
			var pos := _point(record.get("position", null))
			var duplicate := false
			for old in occupied:
				if pos.distance_to(old) <= 0.02:
					duplicate = true
					break
			if duplicate:
				continue
			var owner := str(owner_of.get(str(tile_of.call(pos)), ""))
			if owner == "" or not settlements.has(owner):
				continue
			if AuthoredMap.append_tree(settlements[owner] as Dictionary,
					str(record.get("kind", "small")), pos, float(record.get("radius", 0.0))):
				occupied.append(pos)
				added += 1
		per_region[region] = added
		total += added
	return {"total": total, "regions": per_region}


## Fill road-edge gaps across the authored document while leaving the two reference areas
## untouched. Points are routed to the settlement owning the tile beneath them, and compact
## coordinate proximity makes the migration idempotent without adding persistent ids.
static func apply_roadside_to_existing(doc: Dictionary, centres: Dictionary,
		tile_of: Callable) -> Dictionary:
	var settlements_value: Variant = doc.get("settlements", {})
	if typeof(settlements_value) != TYPE_DICTIONARY:
		return {"total": 0, "settlements": {}}
	var settlements: Dictionary = settlements_value
	var owner_of: Dictionary = {}
	var roads: Array = []
	var polygons: Array = []
	var forest_blockers: Array = []
	var occupied_records: Array = []
	var keys := settlements.keys()
	keys.sort()
	for key_value in keys:
		var key := str(key_value)
		var settlement_value: Variant = settlements[key_value]
		if typeof(settlement_value) != TYPE_DICTIONARY:
			continue
		var settlement: Dictionary = settlement_value
		for tile_value in (settlement.get("tiles", []) as Array):
			owner_of[str(tile_value)] = key
		roads.append_array(settlement.get("roads", []) as Array)
		polygons.append_array(settlement.get("specials", []) as Array)
		polygons.append_array(settlement.get("plazas", []) as Array)
		for forest_value in (settlement.get("forests", []) as Array):
			if typeof(forest_value) == TYPE_DICTIONARY:
				forest_blockers.append((forest_value as Dictionary).get("outline", []))
		occupied_records.append_array(AuthoredMap.tree_records(settlement, key))

	var allowed: Dictionary = {}
	for tile_id in owner_of:
		allowed[str(tile_id)] = true
	var keepouts: Array = []
	for anchor_id in [TREE_PATTERN_SOURCE_ANCHOR, str(REGION_ANCHORS.north)]:
		var centre_value: Variant = centres.get(anchor_id, null)
		if typeof(centre_value) == TYPE_VECTOR2:
			keepouts.append(centre_value)
	var generated := roadside_tree_points(allowed, tile_of, roads, polygons,
		occupied_records, forest_blockers, "authored-roadside", keepouts)
	var per_settlement: Dictionary = {}
	var total := 0
	var wrapper := {AuthoredMap.TREE_POINTS_FIELD: generated}
	for record_value in AuthoredMap.tree_records(wrapper, "roadside-backfill"):
		var record: Dictionary = record_value
		var pos := _point(record.get("position", null))
		var owner := str(owner_of.get(str(tile_of.call(pos)), ""))
		if owner == "" or not settlements.has(owner):
			continue
		if AuthoredMap.append_tree(settlements[owner] as Dictionary,
				str(record.get("kind", "small")), pos, float(record.get("radius", 0.0))):
			per_settlement[owner] = int(per_settlement.get(owner, 0)) + 1
			total += 1
	return {"total": total, "settlements": per_settlement}


static func _tree_transform(offset: Vector2, index: int) -> Vector2:
	var transformed := Vector2(-offset.x, offset.y) if index >= 4 else offset
	return transformed.rotated(float(index % 4) * PI * 0.5)


static func _tree_reach(kind: String, radius: float) -> float:
	match kind:
		"large":
			return 6.0 + TREE_MASS_CLEARANCE
		"mixed":
			return maxf(radius, 1.0) + 6.0 + TREE_MASS_CLEARANCE
		_:
			return 2.6 + TREE_MASS_CLEARANCE


static func _tree_clear(point: Vector2, reach: float, tiles_of_region: Dictionary,
		tile_of: Callable, roads: Array, polygon_blockers: Array, accepted: Array) -> bool:
	var tile_id := str(tile_of.call(point))
	if tile_id == "" or not tiles_of_region.has(tile_id):
		return false
	for road_value in roads:
		var road: Dictionary = road_value
		var line := _polyline(road.get("points", []))
		for i in range(line.size() - 1):
			if point.distance_to(Geometry2D.get_closest_point_to_segment(
					point, line[i], line[i + 1])) < reach + TREE_ROAD_CLEARANCE:
				return false
	for polygon_value in polygon_blockers:
		var polygon: PackedVector2Array = polygon_value
		if Geometry2D.is_point_in_polygon(point, polygon):
			return false
		for i in polygon.size():
			if point.distance_to(Geometry2D.get_closest_point_to_segment(
					point, polygon[i], polygon[(i + 1) % polygon.size()])) < reach:
				return false
	for accepted_value in accepted:
		var prior: Dictionary = accepted_value
		var prior_reach := _tree_reach(str(prior.kind), float(prior.radius))
		if point.distance_to(prior.position as Vector2) < minf(reach, prior_reach) \
				+ TREE_DUPLICATE_CLEARANCE:
			return false
	return true


static func _outline(value: Variant) -> PackedVector2Array:
	var out := PackedVector2Array()
	if typeof(value) == TYPE_PACKED_VECTOR2_ARRAY:
		return value as PackedVector2Array
	if typeof(value) != TYPE_ARRAY:
		return out
	for point_value in (value as Array):
		var point := _point(point_value)
		out.append(point)
	return out


static func _polyline(value: Variant) -> PackedVector2Array:
	return _outline(value)


static func _point(value: Variant) -> Vector2:
	if typeof(value) == TYPE_VECTOR2:
		return value as Vector2
	if typeof(value) == TYPE_ARRAY and (value as Array).size() >= 2:
		return Vector2(float((value as Array)[0]), float((value as Array)[1]))
	return Vector2.ZERO


static func _touches(tiles: Array, covered: Dictionary) -> bool:
	for tile_value in tiles:
		if covered.has(str(tile_value)):
			return true
	return false


static func _centroid(points: Array) -> Vector2:
	var total := Vector2.ZERO
	var count := 0
	for entry in points:
		var values: Array = entry as Array
		if values == null or values.size() < 2:
			continue
		total += Vector2(float(values[0]), float(values[1]))
		count += 1
	return total / float(count) if count > 0 else Vector2.ZERO
