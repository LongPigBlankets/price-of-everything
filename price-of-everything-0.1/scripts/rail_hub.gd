extends RefCounted
## Purchasable city infrastructure. Physical sites live on the instances so saves,
## tile accounting and the 3D board all refer to the same depot.
const ID := "b_038"
const RECIPE := "r_rail_hub"
const PRICE := 5000
const RADIUS := 3
const OWNER := "National Rail Corporation"
const CITIES := {"Stoneshore":"tile_5_10", "Arin":"tile_11_17", "Capital Port":"tile_24_7", "Vandel’s Skip":"tile_22_16", "Port Lightning":"tile_14_2"}

static func active(b: Dictionary) -> bool:
	return BuildingState.is_player_owned(b) and not BuildingWorks.is_building_paused(str(b.get("instance_id", ""))) \
		and Power.is_supplied(str(b.get("tile_id", "")), 80)

static func capacity_multiplier(tile_id: String) -> float:
	if tile_id == "": return 1.0
	for source: String in CITIES.values():
		if Catalog.tile_hex_distance(source, tile_id) > RADIUS: continue
		for b: Dictionary in BuildingState.get_buildings_on_tile(source):
			if str(b.get("building_id", "")) == ID and active(b): return 2.0
	return 1.0

static func sites() -> Array:
	var out: Array = []
	for b: Dictionary in BuildingState.buildings.values():
		if str(b.get("building_id", "")) != ID or not b.has("rail_hub_site"): continue
		var rec: Dictionary = b.rail_hub_site.duplicate(true)
		var p: Array = rec.pos
		rec.pos = Vector2(float(p[0]), float(p[1]))
		rec.instance_id = str(b.instance_id)
		out.append(rec)
	return out

static func seed_sites(planned: Array) -> Array[String]:
	var added: Array[String] = []
	for rec: Dictionary in planned:
		if not CITIES.values().has(str(rec.tile)): continue
		var existing := BuildingState.get_buildings_on_tile(str(rec.tile)).filter(func(b): return str(b.get("building_id", "")) == ID)
		var iid := str(existing[0].instance_id) if not existing.is_empty() else BuildingState.add_building(ID, RECIPE, str(rec.tile), OWNER, "rail_hub:" + str(rec.tile))
		var saved := rec.duplicate(true)
		saved.pos = [rec.pos.x, rec.pos.y]
		BuildingState.buildings[iid].rail_hub_site = saved
		if existing.is_empty(): added.append(iid)
	BuildingState.rail_hubs_seeded = planned.size() == CITIES.size()
	return added

static func seed_world(terrain: Node) -> Array[String]:
	if BuildingState.rail_hubs_seeded: return []
	var builder = load("res://scripts/supply_chain_3d/world_builder.gd").new()
	builder.ground = builder.Coast.ground_for(terrain, {}, load("res://scripts/empire_board_relief.gd").plates(terrain, {}))
	var model := {"tiles": {}, "lines": []}
	for tid in Catalog.all_tile_ids(): model.tiles[tid] = {}
	load("res://scripts/supply_chain_3d/rail_network.gd").apply(model, terrain, load("res://scripts/empire_board.gd")._water_test(terrain), builder.surface_height, true)
	return seed_sites(model.depots)
