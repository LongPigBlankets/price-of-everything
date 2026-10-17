extends Node
const Hub := preload("res://scripts/rail_hub.gd")
const Depot := preload("res://scripts/supply_chain_3d/rail_depot.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok: failures += 1; push_error(message)
func _ready() -> void:
	TelemetryState.enabled=false; SaveLoad.autosave_enabled=false
	preload("res://tools/shot_harness.gd").arm_watchdog(self,180.0)
	SaveLoad.prepare_new_game("res://data/starts/metal_magnate.json")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	while not bool(main.get("build_complete")): await get_tree().process_frame
	check(Hub.sites().size()==5,"All five Rail Hubs seed in a real new game")
	var footprints: Node = get_tree().get_first_node_in_group("building_footprints")
	var lots: Array = footprints.get("_placements")
	for site in Hub.sites():
		check(Hub.CITIES.values().has(site.tile),"Hub is on a hub city tile")
		check(lots.any(func(p): return str(p.instance_id)==str(site.instance_id)),"Hub has an authoritative map footprint")
		var conflicts: Array = []
		for lot in lots:
			if lot.tile_id != site.tile or lot.instance_id == site.instance_id: continue
			if not Geometry2D.intersect_polygons(lot.verts,Depot.yard_polygon(site)).is_empty(): conflicts.append(lot.instance_id)
		check(conflicts.is_empty(),"Hub parcel clears all real buildings: %s %s" % [site.city,conflicts])
	var model := {"tiles":{},"lines":[],"standing":[]}
	for tid in Hub.CITIES.values(): model.tiles[tid] = {}
	preload("res://scripts/supply_chain_3d/rail_network.gd").apply(model, main.get("terrain_layer"))
	check(model.depots.size()==5, "Game renderer includes exactly the five seeded city depots")
	var trunk := preload("res://scripts/supply_chain_3d/railway.gd").network(model.lines.filter(func(line): return line.get("kind", "") != "depot"))
	for depot in model.depots:
		var blocked := false
		for path in trunk.paths:
			for p in path.points:
				if Geometry2D.is_point_in_polygon(p,Depot.polygon(depot)): blocked=true
		check(not blocked,"Runtime trunk rails clear the saved depot: "+str(depot.city))
	var removed: String = str(Hub.sites()[0].instance_id)
	BuildingState.remove_building(removed)
	preload("res://scripts/supply_chain_3d/rail_network.gd").apply(model, main.get("terrain_layer"))
	check(model.depots.size()==4, "Removing a hub removes its depot and sidings from the renderer")
	print("[hub-world] sites=",Hub.sites().size()," failures=",failures)
	get_tree().quit(1 if failures else 0)
