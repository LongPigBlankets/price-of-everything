extends Node
const Paths := preload("res://scripts/app_paths.gd")
func _enter_tree() -> void:
	Paths._base = "/tmp/pepper-infrastructure/runtime"
	RunMetrics.enabled = false
func set_infra(tile: String, mode: String, level: int) -> void:
	Catalog.add_tile_infrastructure(tile, mode)
	Catalog.set_tile_infra_level(tile, mode, level)
	var hm = get_tree().get_first_node_in_group("hex_map")
	var coord = hm.id_to_coord(tile)
	var data: Dictionary = hm.tiles[coord]
	var slot := "rails" if mode == "rail" else mode
	var present: Array = data.get("infrastructure_present", [])
	if not present.has(slot): present.append(slot)
	data["infrastructure_present"] = present
	var levels: Dictionary = data.get("infrastructure_levels", {})
	levels[slot] = level
	data["infrastructure_levels"] = levels
func corridor(source: String, destination: String) -> Array:
	var queue: Array = [source]
	var previous := {source:""}
	var index := 0
	while index < queue.size():
		var current := str(queue[index])
		index += 1
		if current == destination: break
		for neighbour in Catalog.tile_neighbours(current):
			var next := str(neighbour)
			if previous.has(next) or not bool(Catalog._tile_land.get(next, false)): continue
			previous[next] = current
			queue.append(next)
	assert(previous.has(destination))
	var path := []
	var cursor := destination
	while cursor != "":
		path.push_front(cursor)
		cursor = str(previous[cursor])
	return path
func _ready() -> void:
	SaveLoad.autosave_enabled = false
	SaveLoad.prepare_new_game("res://data/starts/pepper_valley_motors.json", {"ruleset":{"logistics_model":"middleman_v1"}})
	add_child(load("res://scenes/main.tscn").instantiate())
	for frame in 160: await get_tree().process_frame
	var all_work: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("/tmp/pepper-consolidation/workloads.json"))
	var original: Array = all_work.ten_factories
	var result := {}
	for variant in ["roads_l2", "rail_l1"]:
		var installed := {}
		if variant == "roads_l2":
			for stream in original:
				for tile in stream.route.tiles:
					set_infra(str(tile),"roads",2)
					installed[str(tile)] = true
		else:
			for pair in [["tile_5_4","tile_5_10"],["tile_6_4","tile_5_10"],["tile_6_4","tile_5_4"]]:
				for tile in corridor(pair[0],pair[1]):
					set_infra(str(tile),"rail",1)
					installed[str(tile)] = true
		TransportState._last_link_flow = {}
		var streams := []
		for old in original:
			var s: Dictionary = old.duplicate(true)
			s.route = TransportService.route(str(old.route.tiles[0]),str(old.route.tiles[-1]),str(old.good))
			assert(TransportService.route_is_reachable(s.route))
			streams.append(s)
		TransportState.pending_transport_shipments.clear()
		for stream in streams:
			var duration := maxi(1,int(stream.route.turns))
			for remaining in range(1,duration+1):
				TransportState.pending_transport_shipments.append({"qty":int(stream.quantity),"tiles":stream.route.tiles,"legs":stream.route.legs,"transport_turns":duration,"turns_remaining":remaining})
		var flow: Dictionary = TransportState.transport_link_flow()
		var quotes := []
		for s in streams:
			TransportState._last_link_flow = {}
			var base := TransportService.transport_cost_for_route(str(s.good),int(s.quantity),s.route)
			TransportState._last_link_flow = flow
			quotes.append({"stream":s,"base":base,"charged":TransportService.transport_cost_for_route(str(s.good),int(s.quantity),s.route),"binding":TransportState.route_congestion(s.route)})
		var upkeep := {"maintenance":0.0,"labour":0.0}
		if variant == "rail_l1":
			for tile in ["tile_5_4","tile_5_5","tile_5_6"]:
				assert(installed.has(tile))
				var b := {"building_id":"b_019","recipe_id":"","level":1,"tile_id":tile}
				upkeep.maintenance += Production._calculate_maintenance_cost(b)
				for turn in range(40,50):
					TurnManager.current_turn = turn
					upkeep.labour += Production._calculate_labour_cost(b)/10.0
		result[variant] = {"installed_tiles":installed.keys(),"flow":flow,"quotes":quotes,"upkeep":upkeep}
	DirAccess.make_dir_recursive_absolute("/tmp/pepper-infrastructure")
	var f := FileAccess.open("/tmp/pepper-infrastructure/quotes.json",FileAccess.WRITE)
	f.store_string(JSON.stringify(result,"\t"))
	get_tree().quit()
