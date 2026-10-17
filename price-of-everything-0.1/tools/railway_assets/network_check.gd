extends Node
const Network := preload("res://scripts/supply_chain_3d/rail_network.gd")
const Rail := preload("res://scripts/supply_chain_3d/railway.gd")
const Index := preload("res://scripts/supply_chain_3d/road_index.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok: failures += 1; push_error(message)
func _ready() -> void:
	TelemetryState.enabled = false; SaveLoad.autosave_enabled = false
	check(is_equal_approx(Rail.TRACK_SPACING + Rail.HALF*2, preload("res://scripts/authored_road_style.gd").bed_width("mid")), "Paired railway has the authored two-lane carriageway width")
	var tiles := {}
	for id in ["a","b","c","d","e"]:
		tiles[id] = {"type":"rural","buildings":0,"neighbours":["a","b","c","d","e"]}
	tiles.b.type = "mountain"; tiles.c.type = "hill"; tiles.d.buildings = 3; tiles.e.type = "urban"
	for seed in 25:
		var plan := Network.topology(tiles,seed)
		check(plan == Network.topology(tiles,seed), "Stable seed reproduces exact network")
		var reversed := {}; var keys := tiles.keys(); keys.reverse()
		for id in keys: reversed[id] = tiles[id]
		check(plan.edges == Network.topology(reversed,seed).edges, "Input order cannot reshuffle connections")
		var first: Dictionary = plan.drops[0]
		check(first.neighbour == ("c" if first.tile == "b" else "b"), "First dropout chooses undeveloped mountain, then hill")
		check(plan.components.size() == 1, "Dropouts preserve connectivity")
		for id in plan.adjacency:
			for nb in plan.adjacency[id]: check(plan.adjacency[nb].has(id), "Connections are mutual")
	var shapes := {"sample":{"decor":[{"id":"house","pos":[0,0]}, {"id":"house","pos":[0,0]}, {"id":"terrace","pos":[60,0],"form":"row"}],"slots":[{"pos":[0,0]}],"trees":[[0,0]],"specials":[{"id":"quay","port_role":"quay"}]}}
	check(Network.authored_buildings({"a":Vector2.ZERO},shapes).counts.a == 2,"Count buildings once, excluding slots, trees and quays")
	var outcomes := {}
	var equal_tiles := tiles.duplicate(true)
	for tile in equal_tiles.values(): tile.type = "rural"; tile.buildings = 0
	for seed in 12: outcomes[str(Network.topology(equal_tiles,seed).edges)] = true
	check(outcomes.size() > 1, "Seed changes random tie outcomes")
	var chain := {"a":{"type":"rural","neighbours":["b"]},"b":{"type":"mountain","neighbours":["a","c"]},"c":{"type":"urban","neighbours":["b"]},"island":{"type":"rural","neighbours":[]}}
	check(Network.topology(chain,4).edges.size() == 2, "Sole connection across narrow land remains")
	check(Network.topology(chain,4).components.size() == 2, "Separate islands remain separate")
	var terrain := preload("res://scripts/hex_map.gd").new()
	terrain.tile_set = load("res://assets/main_tileset.tres")
	terrain._generate_tile_data(); terrain._load_tile_overrides()
	var model := {"tiles":{},"lines":[]}
	for id in Catalog.all_tile_ids(): model.tiles[id] = {}
	var started := Time.get_ticks_msec()
	var builder := preload("res://scripts/supply_chain_3d/world_builder.gd").new()
	builder.ground = builder.Coast.ground_for(terrain,{},preload("res://scripts/empire_board_relief.gd").plates(terrain,{}))
	Network.apply(model,terrain,preload("res://scripts/empire_board.gd")._water_test(terrain),builder.surface_height, true)
	check(model.depots.size()==5,"One depot is placed on each of the five hub city tiles")
	for depot in model.depots:
		check(depot.tile==depot.city_tile and depot.tracks==6 and depot.siding_tracks==2,"Depot sits on its city tile with six tracks and two loading sidings")
		check(model.lines.any(func(line): return line.get("kind","")=="depot" and line.a==depot.tile),"Depot tracks are connected to the visible network")
	print("[rail-network] depots=",model.depots)
	var report: Dictionary = model.rail_network
	check(report.tiles.size() > 100, "Real map land covered")
	for id in report.tiles:
		check(not Catalog.tile_type(id) in ["sea","deep_sea"], "No ocean tile receives rail")
		if Catalog.tile_neighbours(id).any(func(nb): return report.tiles.has(nb)):
			check(report.edges.any(func(e): return e.a==id or e.b==id), "Every land tile with a land neighbour is connected")
	print("[rail-network] component sizes=",report.components.map(func(c): return c.size()))
	var original := {}
	for id in report.tiles:
		original[id] = {}
		for nb in report.tiles[id].neighbours:
			if report.tiles.has(nb): original[id][nb] = true
	check(Network.components(original) == report.components, "All original landmasses retained exactly")
	var developed := 0
	for tile in report.tiles.values(): developed += tile.buildings
	check(developed > 100, "Development counts read real authored buildings")
	print("[rail-network] land=",report.tiles.size()," edges=",report.edges.size()," drops=",report.drops.size()," landmasses=",report.components.size()," buildings=",developed," planning_ms=",Time.get_ticks_msec()-started)
	started = Time.get_ticks_msec()
	var trunk := Rail.network(model.lines.filter(func(line): return line.get("kind","")!="depot"))
	for depot in model.depots:
		var blocked := 0
		for path in trunk.paths:
			for p in path.points:
				var q: Vector2 = (p-depot.pos).rotated(-depot.yaw)
				if Rect2(38,-32,80,64).has_point(q): blocked+=1
		check(blocked==0,"Main railway clears the depot shed: "+depot.city)
		print("[rail-network] depot trunk conflicts ",depot.city,": ",blocked)
	var net := Rail.network(model.lines)
	print("[rail-network] geometry paths=",net.paths.size()," topology_ms=",Time.get_ticks_msec()-started)
	var centers := {}
	for tid in report.tiles: centers[tid] = report.tiles[tid].center
	var land_index := Index.tiles(centers)
	var sea_samples := 0
	for path in net.paths:
		for point in path.points:
			if Index.tile_at(land_index,centers,point) == "": sea_samples += 1
	check(sea_samples == 0, "Rail curves stay within land tiles")
	print("[rail-network] sea_samples=",sea_samples)
	var chosen: String = report.tiles.keys()[0]
	var local_model := {"tiles":{chosen:{}},"lines":[{"mode":"pipes","pts":[]}]}
	Network.apply(local_model,terrain,Callable(),Callable(),true)
	check(local_model.rail_network.edges == report.edges,"Company and continent share global dropout choices")
	check(local_model.lines[0].mode == "pipes","Other infrastructure is preserved")
	for line in local_model.lines:
		if not Rail.is_rail(line.mode): continue
		for point in line.pts: check(Index.contains(report.tiles[chosen].center,point.p),"Company rail ends at visible tile boundary")
	terrain.free()
	var file := FileAccess.open("res://../outputs/railway-assets/network-validation.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"land_tiles":report.tiles.size(),"edges":report.edges.size(),"dropped_edges":report.drops.size(),"landmasses":report.components.size(),"authored_buildings":developed,"paired_width":Rail.CORRIDOR_WIDTH,"depots":model.depots,"failures":failures},"\t"))
	print("[rail-network] failures=",failures)
	get_tree().quit(1 if failures else 0)
