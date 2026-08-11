class_name RoadRegions
extends RefCounted
## Lazy loader for hand-authored road regions and their routing style contract.
## The file is designer-owned; validation reports likely cleanup items without
## re-inferring identity from scratch.

const REGIONS_PATH := "res://data/road_regions.json"
const TILE_PROPS_PATH := "res://data/tile_properties.csv"

const DEFAULT_REGION_ID := "__unassigned_sparse_rural"
const DEFAULT_IDENTITY := "sparse_rural"

const ID_DENSE_CITY := "dense_city"
const ID_SPARSE_CITY := "sparse_city"
const ID_DENSE_RURAL := "dense_rural"
const ID_SPARSE_RURAL := "sparse_rural"
const ID_MOUNTAIN_RANGE := "mountain_range"

const PATTERN_BELTWAY_MINIHUBS := "beltway_minihubs"
const PATTERN_MINIHUB_NETWORK := "minihub_network"
const PATTERN_HUB_SPOKES := "hub_spokes"
const PATTERN_THROUGH_FARM_LINKS := "through_farm_links"
const PATTERN_MOUNTAIN_PASS := "mountain_pass"
const WATER_POLICY := "water_impassable_coast_follow_or_inland"

const VALID_IDENTITIES := [
	ID_DENSE_CITY,
	ID_SPARSE_CITY,
	ID_DENSE_RURAL,
	ID_SPARSE_RURAL,
	ID_MOUNTAIN_RANGE,
]

const STYLE := {
	ID_DENSE_CITY: {
		"wiggle_jitter": 0.02,
		"network_pattern": PATTERN_BELTWAY_MINIHUBS,
		"water_policy": WATER_POLICY,
		"job_generation": "full_beltway_minihubs_spokes",
		"local_density": "high",
		"interconnection": "adjacent_member_pairs_1_5_tiles",
		"orbital": true,
		"orbital_ports_min": 8,
		"orbital_ports_max": 12,
		"hub_strategy": "urban_subcenters",
		"trunk_turn_penalty_mult": 1.0,
		"max_segments": -1,
	},
	ID_SPARSE_CITY: {
		"wiggle_jitter": 0.04,
		"network_pattern": PATTERN_MINIHUB_NETWORK,
		"water_policy": WATER_POLICY,
		"job_generation": "urban_minihubs_to_gateways_and_nearby_members",
		"local_density": "medium",
		"interconnection": "gateway_spokes_plus_nearby_members",
		"orbital": false,
		"optional_partial_bypass": true,
		"full_orbital_allowed": false,
		"hub_strategy": "one_or_two_urban_minihubs",
		"trunk_turn_penalty_mult": 1.0,
		"max_segments": -1,
	},
	ID_DENSE_RURAL: {
		"wiggle_jitter": 0.05,
		"network_pattern": PATTERN_HUB_SPOKES,
		"water_policy": WATER_POLICY,
		"job_generation": "cohesive_hub_spokes_plus_few_cross_links",
		"local_density": "medium",
		"interconnection": "spokes_plus_one_redundant_link_per_four_tiles",
		"orbital": false,
		"hub_strategy": "urban_if_present_else_central_lowest_rural",
		"trunk_turn_penalty_mult": 1.2,
		"max_segments": -1,
	},
	ID_SPARSE_RURAL: {
		"wiggle_jitter": 0.07,
		"network_pattern": PATTERN_THROUGH_FARM_LINKS,
		"water_policy": WATER_POLICY,
		"job_generation": "through_route_first_connect_farms_along_way",
		"local_density": "low",
		"interconnection": "through_route_plus_optional_farm_spurs",
		"orbital": false,
		"rural_anchor_building_ids": ["b_014"],
		"hub_strategy": "none",
		"trunk_turn_penalty_mult": 1.3,
		"max_segments": -1,
	},
	ID_MOUNTAIN_RANGE: {
		"wiggle_jitter": 0.08,
		"network_pattern": PATTERN_MOUNTAIN_PASS,
		"water_policy": WATER_POLICY,
		"job_generation": "cheapest_far_side_crossing",
		"local_density": "minimal",
		"interconnection": "none",
		"orbital": false,
		"hub_strategy": "pass_gateways",
		"trunk_turn_penalty_mult": 1.5,
		"max_segments": 3,
		"switchback_gate": {
			"terrain": ["hill", "mountain"],
			"min_level_gain": 2,
			"window_u": 20.0,
		},
	},
}

static var _loaded := false
static var _regions: Dictionary = {}
static var _tile_to_region: Dictionary = {}
static var _tile_types: Dictionary = {}
static var _validation: Dictionary = {}

static func reset_for_tests() -> void:
	_loaded = false
	_regions.clear()
	_tile_to_region.clear()
	_tile_types.clear()
	_validation.clear()

static func region_ids() -> Array:
	_ensure_loaded()
	return _regions.keys()

static func all_regions() -> Dictionary:
	_ensure_loaded()
	return _regions.duplicate(true)

static func get_region(region_id: String) -> Dictionary:
	_ensure_loaded()
	if region_id == DEFAULT_REGION_ID:
		return {
			"name": "Unassigned sparse rural",
			"identity": DEFAULT_IDENTITY,
			"identity_source": "default",
			"tiles": [],
		}
	if not _regions.has(region_id):
		return {}
	var region: Dictionary = _regions[region_id]
	return region.duplicate(true)

static func region_of(tile_id: String) -> String:
	_ensure_loaded()
	return str(_tile_to_region.get(tile_id, DEFAULT_REGION_ID))

static func identity(region_id: String) -> String:
	_ensure_loaded()
	if region_id == DEFAULT_REGION_ID:
		return DEFAULT_IDENTITY
	var region: Dictionary = _regions.get(region_id, {})
	var id := str(region.get("identity", DEFAULT_IDENTITY))
	return id if id in VALID_IDENTITIES else DEFAULT_IDENTITY

static func identity_for_tile(tile_id: String) -> String:
	return identity(region_of(tile_id))

static func style(region_id_or_identity: String) -> Dictionary:
	var id := region_id_or_identity if region_id_or_identity in VALID_IDENTITIES else identity(region_id_or_identity)
	var style_doc: Dictionary = STYLE.get(id, STYLE[DEFAULT_IDENTITY])
	return style_doc.duplicate(true)

static func style_for_identity(identity_id: String) -> Dictionary:
	var id := identity_id if identity_id in VALID_IDENTITIES else DEFAULT_IDENTITY
	var style_doc: Dictionary = STYLE.get(id, STYLE[DEFAULT_IDENTITY])
	return style_doc.duplicate(true)

static func style_for_tile(tile_id: String) -> Dictionary:
	return style(region_of(tile_id))

static func tiles(region_id: String) -> Array:
	_ensure_loaded()
	var region: Dictionary = _regions.get(region_id, {})
	var member_tiles: Array = region.get("tiles", [])
	return member_tiles.duplicate()

static func validation_report() -> Dictionary:
	_ensure_loaded()
	return _validation.duplicate(true)

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_tile_types = _load_tile_types()
	_regions = _load_regions()
	_build_tile_index_and_validation()
	_warn_validation()

static func _load_regions() -> Dictionary:
	var out: Dictionary = {}
	if not FileAccess.file_exists(REGIONS_PATH):
		push_warning("RoadRegions: %s missing." % REGIONS_PATH)
		return out
	var file := FileAccess.open(REGIONS_PATH, FileAccess.READ)
	if file == null:
		push_warning("RoadRegions: could not open %s." % REGIONS_PATH)
		return out
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("RoadRegions: %s did not parse." % REGIONS_PATH)
		return out
	var doc: Dictionary = parsed
	var regions_value: Variant = doc.get("regions", {})
	if typeof(regions_value) != TYPE_DICTIONARY:
		push_warning("RoadRegions: %s has no regions dictionary." % REGIONS_PATH)
		return out
	var parsed_regions: Dictionary = regions_value
	for region_id in parsed_regions.keys():
		var region_value: Variant = parsed_regions[region_id]
		if typeof(region_value) != TYPE_DICTIONARY:
			continue
		var region: Dictionary = region_value
		var clean_tiles: Array = []
		for tile_value in region.get("tiles", []):
			clean_tiles.append(str(tile_value))
		out[str(region_id)] = {
			"name": str(region.get("name", str(region_id))),
			"identity": str(region.get("identity", DEFAULT_IDENTITY)),
			"identity_source": str(region.get("identity_source", "unknown")),
			"tiles": clean_tiles,
		}
	return out

static func _load_tile_types() -> Dictionary:
	var out: Dictionary = {}
	if not FileAccess.file_exists(TILE_PROPS_PATH):
		push_warning("RoadRegions: %s missing." % TILE_PROPS_PATH)
		return out
	var file := FileAccess.open(TILE_PROPS_PATH, FileAccess.READ)
	if file == null:
		push_warning("RoadRegions: could not open %s." % TILE_PROPS_PATH)
		return out
	var headers := file.get_csv_line()
	var id_idx := _header_index(headers, "id")
	var type_idx := _header_index(headers, "type")
	if id_idx < 0 or type_idx < 0:
		file.close()
		push_warning("RoadRegions: %s is missing id/type columns." % TILE_PROPS_PATH)
		return out
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.is_empty() or row.size() <= max(id_idx, type_idx):
			continue
		var tile_id := str(row[id_idx]).strip_edges()
		if tile_id == "":
			continue
		out[tile_id] = str(row[type_idx]).strip_edges()
	file.close()
	return out

static func _header_index(headers: PackedStringArray, key: String) -> int:
	for i in range(headers.size()):
		if str(headers[i]).strip_edges() == key:
			return i
	return -1

static func _build_tile_index_and_validation() -> void:
	_tile_to_region.clear()
	var unknown_tiles: Array = []
	var overlaps: Array = []
	var lake_tiles: Array = []
	var water_tiles: Array = []
	var invalid_identities: Array = []
	var mountain_rule_mismatches: Array = []
	var duplicate_member_tiles: Array = []

	for region_id in _regions.keys():
		var region: Dictionary = _regions[region_id]
		var id := str(region.get("identity", DEFAULT_IDENTITY))
		if not id in VALID_IDENTITIES:
			invalid_identities.append({"region_id": region_id, "identity": id})
		var seen_in_region: Dictionary = {}
		var mountain_count := 0
		for tile_id_value in region.get("tiles", []):
			var tile_id := str(tile_id_value)
			if seen_in_region.has(tile_id):
				duplicate_member_tiles.append({"region_id": region_id, "tile_id": tile_id})
				continue
			seen_in_region[tile_id] = true
			if not _tile_types.has(tile_id):
				unknown_tiles.append({"region_id": region_id, "tile_id": tile_id})
				continue
			var tile_type := str(_tile_types[tile_id])
			if tile_type == "mountain":
				mountain_count += 1
			if tile_id in HillField.LAKE_TILES:
				lake_tiles.append({"region_id": region_id, "tile_id": tile_id})
			if tile_type in HillField.SEA_TYPES:
				water_tiles.append({"region_id": region_id, "tile_id": tile_id, "type": tile_type})
			if _tile_to_region.has(tile_id):
				overlaps.append({
					"tile_id": tile_id,
					"first_region": str(_tile_to_region[tile_id]),
					"duplicate_region": region_id,
				})
			else:
				_tile_to_region[tile_id] = region_id
		if mountain_count > 1 and id != ID_MOUNTAIN_RANGE:
			mountain_rule_mismatches.append({
				"region_id": region_id,
				"identity": id,
				"mountain_tiles": mountain_count,
			})

	_validation = {
		"unknown_tiles": unknown_tiles,
		"overlaps": overlaps,
		"lake_tiles": lake_tiles,
		"water_tiles": water_tiles,
		"invalid_identities": invalid_identities,
		"mountain_rule_mismatches": mountain_rule_mismatches,
		"duplicate_member_tiles": duplicate_member_tiles,
	}

static func _warn_validation() -> void:
	for key in [
		"unknown_tiles",
		"overlaps",
		"lake_tiles",
		"water_tiles",
		"invalid_identities",
		"mountain_rule_mismatches",
		"duplicate_member_tiles",
	]:
		var entries: Array = _validation.get(key, [])
		if not entries.is_empty():
			push_warning("RoadRegions: %s -> %d" % [key, entries.size()])
