class_name StartBuildings
extends RefCounted
## Loader for the pre-existing NPC building pool (data/start_buildings.json,
## authored by scripts/build_start_buildings.py). Every fresh match seeds these
## buildings; each belongs to one NPC company per region, runs its recipe via
## the NPC economy pass, and carries a market phase tag (1-5) for the later
## purchase-market rotation.
##
## entries() flattens the per-region data into one stable list with
## deterministic instance ids ("start_<building>_<tile>[_<n>]"), shared by
## world_map seeding, tools/bake_roads.tscn (forest footprints must match the
## fresh-match discs) and, later, the market tab.

const DATA_PATH := "res://data/start_buildings.json"

static var _cache: Dictionary = {}
static var _entries: Array = []
static var _loaded := false

static func data() -> Dictionary:
	if _loaded:
		return _cache
	_loaded = true
	if not FileAccess.file_exists(DATA_PATH):
		push_warning("StartBuildings: %s missing — run scripts/build_start_buildings.py." % DATA_PATH)
		return _cache
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		return _cache
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("StartBuildings: %s did not parse." % DATA_PATH)
		return _cache
	_cache = parsed
	_flatten()
	return _cache

## Flat list of {region, owner, building, recipe, tile, phase, instance_id},
## in the file's stable order.
static func entries() -> Array:
	data()
	return _entries

static func _flatten() -> void:
	_entries = []
	var seen: Dictionary = {}  # "building|tile" -> count, for unique instance ids
	var regions: Dictionary = _cache.get("regions", {})
	var keys := regions.keys()
	keys.sort()
	for region_key in keys:
		var region: Dictionary = regions[region_key]
		var owner := str(region.get("owner", "Independent Operators"))
		for b in region.get("buildings", []):
			var building := str(b.get("building", ""))
			var tile := str(b.get("tile", ""))
			if building == "" or tile == "":
				continue
			var pair := "%s|%s" % [building, tile]
			var n: int = seen.get(pair, 0)
			seen[pair] = n + 1
			var instance_id := "start_%s_%s" % [building, tile]
			if n > 0:
				instance_id += "_%d" % n
			_entries.append({
				"region": str(region_key),
				"owner": owner,
				"building": building,
				"recipe": str(b.get("recipe", "")),
				"tile": tile,
				"phase": int(b.get("phase", 1)),
				"instance_id": instance_id,
			})

static func reset_for_tests() -> void:
	_cache = {}
	_entries = []
	_loaded = false
