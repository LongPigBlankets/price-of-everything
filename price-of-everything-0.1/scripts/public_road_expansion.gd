extends RefCounted
## Public roads grow outward from the ports without charging the player. Existing
## infrastructure and player construction projects are skipped rather than overwritten.
const FIRST_TURN := 20
const INTERVAL := 5
const LAND_TYPES := ["urban", "rural", "hill"]

static func batch_size(turn: int) -> int:
	if turn < FIRST_TURN or (turn - FIRST_TURN) % INTERVAL != 0:
		return 0
	return 3 + ((turn - FIRST_TURN) / INTERVAL) % 2


static func next_tiles(tiles: Array, turn: int) -> Array[String]:
	var count := batch_size(turn)
	var result: Array[String] = []
	if count == 0:
		return result
	var ports := Catalog.all_ports()
	if ports.is_empty():
		return result
	var pending: Dictionary = {}
	var road_id := str(Catalog.get_building_by_internal_name("roads").get("id", ""))
	for project in Construction.construction_projects.values():
		if str(project.get("building_id", "")) == road_id:
			pending[str(project.get("tile_id", ""))] = true
	var ranked: Array = []
	for tile in tiles:
		var id := str(tile.get("id", ""))
		if id == "" or not LAND_TYPES.has(Catalog.tile_type(id)):
			continue
		if (tile.get("infrastructure_present", []) as Array).has("roads") or Catalog.tile_has_infrastructure(id, "roads") or pending.has(id):
			continue
		var distance := 1 << 30
		for port in ports:
			distance = mini(distance, Catalog.tile_hex_distance(id, str(port.tile_id)))
		ranked.append({"id": id, "distance": distance})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.distance < b.distance if a.distance != b.distance else str(a.id) < str(b.id))
	for i in mini(count, ranked.size()):
		result.append(str(ranked[i].id))
	return result
