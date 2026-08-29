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
		covered: Dictionary, tile_of: Callable, centres: Dictionary) -> Dictionary:
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
	if not port_decor.is_empty():
		out["port_decor"] = port_decor
	return out


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
