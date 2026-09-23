extends "res://tools/pepper_infrastructure_quote_probe.gd"
func _ready() -> void:
	SaveLoad.autosave_enabled = false
	SaveLoad.prepare_new_game("res://data/starts/pepper_valley_motors.json", {"ruleset":{"logistics_model":"middleman_v1"}})
	add_child(load("res://scenes/main.tscn").instantiate())
	for frame in 160: await get_tree().process_frame
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("/tmp/pepper-seven-tiles/spec.json"))
	var installed := {}
	for stream in spec.streams:
		for tile in corridor(str(stream.source),str(stream.destination)):
			set_infra(str(tile),"rail",2)
			installed[str(tile)] = true
	TransportState._last_link_flow = {}
	var streams := []
	# Upgrade any existing rail connector the router selects as well, so every
	# traversed rail tile actually meets the requested L2 standard.
	var stable := false
	for attempt in 20:
		streams.clear()
		var expanded := false
		for old in spec.streams:
			var s: Dictionary = old.duplicate(true)
			s.route = TransportService.route(str(s.source),str(s.destination),str(s.good))
			assert(TransportService.route_is_reachable(s.route))
			for tile in s.route.tiles:
				if not installed.has(str(tile)):
					set_infra(str(tile), "rail", 2)
					installed[str(tile)] = true
					expanded = true
			streams.append(s)
		if not expanded:
			stable = true
			break
	assert(stable)
	for s in streams:
		for tile in s.route.tiles:
			assert(TransportState._tile_infra_level(str(tile), "rail") == 2)
	TransportState.pending_transport_shipments.clear()
	for s in streams:
		var duration := maxi(1,int(s.route.turns))
		for remaining in range(1,duration+1):
			TransportState.pending_transport_shipments.append({"qty":int(s.quantity),"tiles":s.route.tiles,"legs":s.route.legs,"transport_turns":duration,"turns_remaining":remaining})
	var flow := TransportState.transport_link_flow()
	var quotes := []
	for s in streams:
		TransportState._last_link_flow = {}
		var base := TransportService.transport_cost_for_route(str(s.good),int(s.quantity),s.route)
		TransportState._last_link_flow = flow
		quotes.append({"stream":s,"base":base,"charged":TransportService.transport_cost_for_route(str(s.good),int(s.quantity),s.route),"binding":TransportState.route_congestion(s.route)})
	var costs := []
	for site in spec.layout:
		var b := {"building_id":"b_007" if site.recipe in ["r_009","r_008"] else "b_002","recipe_id":site.recipe,"level":1,"tile_id":site.tile}
		var labour := 0.0
		for turn in range(40,50):
			TurnManager.current_turn = turn
			labour += Production._calculate_labour_cost(b)/10.0
		costs.append({"tile":site.tile,"recipe":site.recipe,"labour":labour,"maintenance":Production._calculate_maintenance_cost(b),"power":Production._effective_energy_req(b,Catalog.get_recipe(site.recipe))*EconomyConfig.GRID_BUY_PRICE})
	var rail_cost := {"maintenance":0.0,"labour":0.0}
	for tile in spec.owned_rail_tiles:
		assert(installed.has(tile))
		var b := {"building_id":"b_019","recipe_id":"","level":2,"tile_id":tile}
		rail_cost.maintenance += Production._calculate_maintenance_cost(b)
		for turn in range(40,50):
			TurnManager.current_turn = turn
			rail_cost.labour += Production._calculate_labour_cost(b)/10.0
	var f := FileAccess.open("/tmp/pepper-seven-tiles/quotes.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"quotes":quotes,"flow":flow,"factory_costs":costs,"rail_upkeep":rail_cost,"installed_tiles":installed.keys()},"\t"))
	get_tree().quit()
