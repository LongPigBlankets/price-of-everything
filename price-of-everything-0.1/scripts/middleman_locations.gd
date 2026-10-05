extends RefCounted
## Where Local Suppliers trade from. Every land tile belongs to its nearest market hub: the ports (authored and
## completed runtime ports) and the inland hub cities below. Goods are hauled to that hub over bare ground, and
## the settlement the tile sits in sets how dear that haul is. Sea tiles have no Local Suppliers.
## Port construction/removal invalidates the cache; roads do not affect it.

## Inland cities that are market hubs without docks: Port Lightning sits on a lake and draws on a deep hinterland.
const INLAND_HUB_TILES := ["tile_14_2"]
## Settlement factor on the haul, by where the tile sits. A hub's urban area is the cheapest place to sell.
const HUB_CITY := 1.1
const CITY := 1.25
const TOWN := 1.5
const COUNTRYSIDE := 1.75
const MOUNTAIN := 2.0
## Urban tiles in one connected area that make a city rather than a town.
const CITY_MIN_TILES := 3
const UNSERVED_TERRAIN := ["sea", "deep_sea"]

static var _factors: Dictionary = {}
static var _hub_of: Dictionary = {}
static var _hub_signature := ""

## Settlement factor for a tile of `terrain` in an urban area of `urban_count` tiles; 0.0 where nobody trades.
static func classify(terrain: String, urban_count: int, hub_city: bool) -> float:
	if terrain in UNSERVED_TERRAIN: return 0.0
	if terrain == "urban":
		if hub_city: return HUB_CITY
		return CITY if urban_count >= CITY_MIN_TILES else TOWN
	if terrain in ["rural", "hill"]: return COUNTRYSIDE
	return MOUNTAIN

static func hub_tiles() -> Array:
	var hubs := {}
	for port: Dictionary in Catalog.all_ports(): hubs[str(port.tile_id)] = true
	for building: Dictionary in BuildingState.buildings.values():
		if str(building.get("building_id", "")) == "b_004": hubs[str(building.tile_id)] = true
	for tile: String in INLAND_HUB_TILES: hubs[tile] = true
	var keys := hubs.keys()
	keys.sort()
	return keys

static func factors() -> Dictionary:
	var hubs := hub_tiles()
	var signature := JSON.stringify(hubs)
	if signature == _hub_signature and not _factors.is_empty(): return _factors
	_hub_signature = signature
	_factors.clear()
	_hub_of.clear()
	var terrain := {}
	var file := FileAccess.open(Catalog.TILE_PROPS_CSV_PATH, FileAccess.READ)
	if file == null: return {}
	var header := file.get_csv_line()
	var id_col := header.find("id")
	var type_col := header.find("type")
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() > maxi(id_col, type_col): terrain[row[id_col]] = row[type_col].to_lower()
	var hub_set := {}
	for hub: String in hubs: hub_set[hub] = true
	var visited := {}
	for tile: String in terrain:
		if terrain[tile] != "urban" or visited.has(tile): continue
		var city: Array = [tile]
		visited[tile] = true
		var head := 0
		var hub_city := false
		while head < city.size():
			var current := str(city[head])
			head += 1
			if hub_set.has(current): hub_city = true
			for neighbour: String in Catalog.tile_neighbours(current):
				if terrain.get(neighbour, "") == "urban" and not visited.has(neighbour):
					visited[neighbour] = true
					city.append(neighbour)
		for member: String in city: _factors[member] = classify("urban", city.size(), hub_city)
	for tile: String in terrain:
		if not _factors.has(tile): _factors[tile] = classify(str(terrain[tile]), 0, false)
		if float(_factors[tile]) <= 0.0: continue
		var best := ""
		var best_d := 1 << 30
		for hub: String in hubs:
			var d := Catalog.tile_hex_distance(tile, hub)
			if d < best_d:
				best_d = d
				best = hub
		_hub_of[tile] = best
	return _factors

## The settlement factor on a tile's haul, or 0.0 where Local Suppliers do not trade.
static func settlement_factor(tile: String) -> float:
	return float(factors().get(tile, MOUNTAIN))

## The market hub a tile sells into: its nearest hub. Empty where Local Suppliers do not trade.
static func hub_for(tile: String) -> String:
	factors()
	return str(_hub_of.get(tile, ""))

## Turn-moves over bare ground from a tile to its hub, at least one.
static func trips(tile: String) -> int:
	var hub := hub_for(tile)
	if hub == "": return 1
	return maxi(1, ceili(float(Catalog.tile_hex_distance(tile, hub)) / float(EconomyConfig.TRANSPORT_MAX_TILES_PER_TURN)))

## The haul multiplier a Local Suppliers quote applies to a good's freight rate per leg: trips to the hub times
## the settlement factor. 0.0 where Local Suppliers do not trade, which a quote refuses.
static func coefficient(tile: String) -> float:
	var factor := settlement_factor(tile)
	if factor <= 0.0: return 0.0
	return float(trips(tile)) * factor
