extends RefCounted
## Contiguous authored urban geography plus authored and completed runtime ports.
## Port construction/removal invalidates the coefficient cache; roads do not affect it.
static var _factors: Dictionary = {}
static var _port_signature := ""

static func classify(terrain: String, urban_count: int, near_port: bool, adjacent_city: bool) -> float:
	if terrain == "mountain": return 2.5
	if terrain == "urban":
		if near_port: return 1.05
		return 1.25 if urban_count >= 4 else 1.5
	return 1.75 if adjacent_city and terrain in ["rural", "hill"] else 2.0

static func factors() -> Dictionary:
	var port_tiles := {}
	for port: Dictionary in Catalog.all_ports(): port_tiles[str(port.tile_id)] = true
	for building: Dictionary in BuildingState.buildings.values():
		if str(building.get("building_id", "")) == "b_004": port_tiles[str(building.tile_id)] = true
	var keys := port_tiles.keys()
	keys.sort()
	var signature := JSON.stringify(keys)
	if signature == _port_signature and not _factors.is_empty(): return _factors
	_port_signature = signature
	_factors.clear()
	var terrain := {}
	var file := FileAccess.open(Catalog.TILE_PROPS_CSV_PATH, FileAccess.READ)
	if file == null: return {}
	var header := file.get_csv_line()
	var id_col := header.find("id")
	var type_col := header.find("type")
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() > maxi(id_col, type_col): terrain[row[id_col]] = row[type_col].to_lower()
	var visited := {}
	for tile: String in terrain:
		if terrain[tile] != "urban" or visited.has(tile): continue
		var city: Array = [tile]
		visited[tile] = true
		var head := 0
		var near_port := false
		while head < city.size():
			var current := str(city[head])
			head += 1
			if port_tiles.has(current): near_port = true
			for neighbour: String in Catalog.tile_neighbours(current):
				if terrain.get(neighbour, "") == "urban" and not visited.has(neighbour):
					visited[neighbour] = true
					city.append(neighbour)
		for member: String in city: _factors[member] = classify("urban", city.size(), near_port, false)
	for tile: String in terrain:
		if _factors.has(tile): continue
		var adjacent := false
		for neighbour: String in Catalog.tile_neighbours(tile):
			if terrain.get(neighbour, "") == "urban": adjacent = true
		_factors[tile] = classify(str(terrain[tile]), 0, false, adjacent)
	return _factors

static func coefficient(tile: String) -> float:
	return float(factors().get(tile, 2.0))
