extends "res://tools/pepper_infrastructure_quote_probe.gd"
func _enter_tree() -> void:
	Paths._base = "/tmp/pepper-district/runtime_" + "_".join(OS.get_cmdline_user_args())
	RunMetrics.enabled = false

func joined_route(a: Dictionary, b: Dictionary) -> Dictionary:
	if a.is_empty(): return b
	if b.is_empty(): return a
	assert(str(a.tiles[-1]) == str(b.tiles[0]))
	var tiles: Array = a.tiles.duplicate()
	tiles.append_array(b.tiles.slice(1))
	var legs: Array = a.legs.duplicate()
	legs.append_array(b.legs)
	return {"tiles":tiles,"legs":legs,"turns":int(a.turns)+int(b.turns),"reachable":true}

func physical_owned_rail_streams(original: Array, routed: Array, gateway: String) -> Array:
	# Keep physical journeys continuous across operator handoff. Otherwise two
	# shipment records count a same-mode gateway twice, creating false congestion.
	var physical := []
	for old in original:
		var local_route := {}
		var external_route := {}
		for s in routed:
			if str(s.good) != str(old.good) or str(s.direction) != str(old.direction): continue
			if s.operator == "carrier": external_route = s.route
			elif (old.direction == "internal" and s.source == old.source and s.destination == old.destination) or (old.direction == "import" and s.destination == old.destination) or (old.direction == "export" and s.source == old.source):
				local_route = s.route
		var route: Dictionary
		if old.direction == "internal": route = local_route
		elif old.direction == "import": route = joined_route(external_route, local_route)
		else: route = joined_route(local_route, external_route)
		assert(not route.is_empty())
		physical.append({"quantity":old.quantity,"route":route})
	return physical

func _ready() -> void:
	SaveLoad.autosave_enabled = false
	SaveLoad.prepare_new_game("res://data/starts/pepper_valley_motors.json", {"ruleset":{"logistics_model":"middleman_v1"}})
	add_child(load("res://scenes/main.tscn").instantiate())
	for frame in 160: await get_tree().process_frame
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("/tmp/pepper-district/spec.json"))
	var out := {}
	var l1_only := OS.get_cmdline_user_args().has("--rail-l1")
	var owned_rail := OS.get_cmdline_user_args().has("--owned-rail")
	for variant in (["rail_l1"] if l1_only else (["rail"] if owned_rail else ["roads", "rail"])):
		var mode: String = "rail" if variant == "rail_l1" else str(variant)
		var level := 1 if variant == "rail_l1" else (3 if mode == "roads" else 2)
		for tile in spec.area:
			set_infra(str(tile), "roads", 3)
			if owned_rail: set_infra(str(tile), "rail", level)
		for tile in spec.area:
			for t in corridor(str(tile),str(spec.port)): set_infra(str(t),mode,level)
		# Every alternative uses the same network, including any existing connector
		# selected by the router; only operator and external origin/destination change.
		for attempt in 20:
			var changed := false
			for case in spec.cases.values():
				for s in case:
					if s.operator != "carrier": continue
					var route := TransportService.route(str(s.source),str(s.destination),str(s.good))
					for tile in route.tiles:
						if TransportState._tile_infra_level(str(tile),mode) != level:
							set_infra(str(tile),mode,level)
							changed = true
			if not changed: break
		var cases := {}
		for name in spec.cases:
			TransportState._last_link_flow = {}
			var routed := []
			for old in spec.cases[name]:
				var s: Dictionary = old.duplicate(true)
				if s.operator == "carrier": s.route = TransportService.route(str(s.source),str(s.destination),str(s.good))
				elif owned_rail:
					# Prescribed shortest covered local path; every edge has rail.
					# It fits one rail leg at either level, without leaving coverage.
					assert(s.route.tiles.size()-1 <= EconomyConfig.infra_range_for_level("rail",level))
					for tile in s.route.tiles: assert(TransportState._tile_infra_level(str(tile),"rail") == level)
					s.route.legs = [{"from":s.source,"to":s.destination,"mode":"rail"}]
					s.route.turns = 1
				assert(TransportService.route_is_reachable(s.route))
				if s.operator == "carrier":
					for leg in s.route.legs: assert(str(leg.mode) == mode)
					for tile in s.route.tiles: assert(TransportState._tile_infra_level(str(tile),mode) == level)
				routed.append(s)
			TransportState.pending_transport_shipments.clear()
			var physical: Array = physical_owned_rail_streams(spec.cases.direct, routed, str(name)) if owned_rail and name != "direct" else routed
			for s in physical:
				var duration := maxi(1,int(s.route.turns))
				for remaining in range(1,duration+1):
					TransportState.pending_transport_shipments.append({"qty":int(s.quantity),"tiles":s.route.tiles,"legs":s.route.legs,"transport_turns":duration,"turns_remaining":remaining})
			var flow := TransportState.transport_link_flow()
			var quotes := []
			for s in routed:
				if s.operator != "carrier": continue
				TransportState._last_link_flow = {}
				var base := TransportService.transport_cost_for_route(str(s.good),int(s.quantity),s.route)
				TransportState._last_link_flow = flow
				quotes.append({"stream":s,"base":base,"charged":TransportService.transport_cost_for_route(str(s.good),int(s.quantity),s.route)})
			var overloads := []
			for key in flow:
				var parts: PackedStringArray = str(key).split("|")
				var cap := TransportState.tile_mode_capacity(parts[1], TransportState._tile_infra_level(parts[0],parts[1]))
				if float(flow[key]) > cap: overloads.append({"key":key,"flow":flow[key],"cap":cap})
			cases[name] = {"quotes":quotes,"streams":routed,"flow":flow,"overloads":overloads,"physical_streams":physical}
		out[variant] = cases
	var costs := []
	for site in spec.layout:
		var b := {"building_id":"b_007" if site.recipe in ["r_009","r_008"] else "b_002","recipe_id":site.recipe,"level":1,"tile_id":site.tile}
		var labour := 0.0
		for turn in range(40,50):
			TurnManager.current_turn = turn
			labour += Production._calculate_labour_cost(b)/10.0
		costs.append({"tile":site.tile,"recipe":site.recipe,"labour":labour,"maintenance":Production._calculate_maintenance_cost(b),"power":Production._effective_energy_req(b,Catalog.get_recipe(site.recipe))*EconomyConfig.GRID_BUY_PRICE})
	var upkeep := 0.0
	for tile in ["tile_5_4","tile_5_5","tile_5_6"]:
		upkeep += Production._calculate_maintenance_cost({"building_id":"b_019","level":1 if l1_only else 2,"tile_id":tile,"recipe_id":""})
	var output_path := "/tmp/pepper-district/quotes_owned_rail_l1.json" if l1_only else "/tmp/pepper-district/quotes_owned_rail_l2.json"
	if not owned_rail: output_path = "/tmp/pepper-district/quotes_l1.json" if l1_only else "/tmp/pepper-district/quotes.json"
	var f := FileAccess.open(output_path,FileAccess.WRITE)
	f.store_string(JSON.stringify({"modes":out,"factory_costs":costs,"rail_maintenance":upkeep},"\t"))
	get_tree().quit()
