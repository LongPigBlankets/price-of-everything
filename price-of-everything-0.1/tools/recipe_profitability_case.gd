extends Node
## One recipe per engine process: no shared match, price history, saves or modifiers.
## No main scene or panels. The actual UI build handler is called without entering
## the scene tree; the map uses the actual HexMap CSV loader without visual layers.
const Paths := preload("res://scripts/app_paths.gd")
const Economics := preload("res://scripts/economics_snapshot.gd")
const World := preload("res://scripts/world_map.gd")
const Middleman := preload("res://scripts/middleman_service.gd")
const Readout := preload("res://scripts/building_readout.gd")
const BuildingEconomics := preload("res://scripts/building_economics.gd")
var site := "tile_5_10"
var logistics_mode := "market"
var route_mode := ""
var rail_owned_limit := 0
var infra_level := 1
## --panel: also record, before each turn, what the Building Detail panel's Economics section says the
## building will make that turn (BuildingReadout.economics, and v3's BuildingEconomics.per_turn under
## value_added_v3), to compare with the cash that moves.
var record_panel := false
const SAMPLE_TURNS := 10
const MAX_START_TURNS := 60
const INITIAL_EQUITY := 1000000.0
const PEPPER_STEADY_WARMUP_TURNS := 35
var _out_path: String
var _world: Node2D
var _map: HexMap
var _rows: Array[Dictionary] = []

class DataMap extends HexMap:
	func _ready() -> void:
		_generate_tile_data()
		_load_tile_overrides()
		river_properties = _load_river_properties()
		cities = _load_cities()
		set_process(false)
		set_process_input(false)
		set_process_unhandled_input(false)

func _enter_tree() -> void:
	var args := OS.get_cmdline_user_args()
	assert(args.size() >= 2, "Expected recipe_id (or --list) and output.json")
	_out_path = args[1]
	for arg: String in args:
		if arg.begins_with("--site="):
			site = arg.trim_prefix("--site=")
		elif arg.begins_with("--mode="):
			logistics_mode = arg.trim_prefix("--mode=")
		elif arg.begins_with("--route="):
			route_mode = arg.trim_prefix("--route=")
		elif arg.begins_with("--rail-owned="):
			rail_owned_limit = maxi(0, int(arg.trim_prefix("--rail-owned=")))
		elif arg.begins_with("--infra-level="):
			infra_level = clampi(int(arg.trim_prefix("--infra-level=")), 1, 3)
		elif arg == "--panel":
			record_panel = true
	if rail_owned_limit == 0 and site == "tile_5_4" and route_mode == "rail":
		rail_owned_limit = 3
	Paths._base = _out_path.get_base_dir().path_join("runtime")
	RunMetrics.enabled = false

func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var recipe_id := OS.get_cmdline_user_args()[0]
	if recipe_id == "--list":
		var entries: Array[Dictionary] = []
		for recipe: Dictionary in Catalog.all_recipes():
			var entry := _description(recipe)
			entry["mining"] = _is_mining(recipe)
			entries.append(entry)
		_write({"recipes": entries})
		get_tree().quit()
		return
	await _run(recipe_id)
	if _world != null:
		_world.free()
	get_tree().quit()

func _description(recipe: Dictionary) -> Dictionary:
	var bid := str(recipe.get("building_id", ""))
	return {"recipe_id": str(recipe.get("recipe_id", "")), "building_id": bid,
		"building_name": str(Catalog.get_building(bid).get("display_name", bid)),
		"recipe_name": str(recipe.get("display_name", "")),
		"recipe_type": str(recipe.get("recipe_type", "")),
		"research_requirement": str(recipe.get("tech_unlock_req", "")),
		"requirements": recipe.get("requirements", []).duplicate(true)}

func _is_mining(recipe: Dictionary) -> bool:
	if str(recipe.get("recipe_type", "")) in ["Mineral Mining", "Oil Extraction"]:
		return true
	for req: Dictionary in recipe.get("requirements", []):
		if str(req.get("type", "")) == "deposit" and str(req.get("value", "")) != "water":
			return true
	return false

func _run(recipe_id: String) -> void:
	var recipe := Catalog.get_recipe(recipe_id)
	assert(not recipe.is_empty(), "Unknown recipe")
	var result := _description(recipe)
	result.merge({"schema_version": 2, "site": site, "logistics_mode": logistics_mode,
		"route_mode": route_mode, "infra_level": infra_level, "sample_turns": SAMPLE_TURNS,
		"initial_equity": INITIAL_EQUITY, "research_eligibility_bypassed": true,
		"profit_basis": "actual retained cash change, after tax and dividends, excluding pre-operation construction",
		"recipe": recipe.duplicate(true), "turns": _rows})
	MatchState.reset()
	TurnManager.reset_for_test()
	TurnManager.fast_mode = true
	UiPrefs.debug_turn_logs_enabled = false
	MarketState.import_state({})
	Stockpile.import_state({})
	Production.import_state({})
	Modifiers.import_state({})
	DecisionState.enabled = false
	# Prevent unlock-by-doing from adding bonuses while measuring a fixed baseline.
	# This fixture-only change never modifies the catalogue or gameplay code.
	ResearchState._unlock_defs.clear()
	MatchState.money = INITIAL_EQUITY
	MatchState.ruleset = {"name": "standard", "logistics_model": "middleman_v1" if logistics_mode == "middleman" else "standard",
		"middleman_new_buildings": logistics_mode == "middleman", "tutorial_enabled": false}
	MatchState.construct_material_source = "market"
	MatchState.construct_output_destination = "market"
	MatchState.set_construct_credit_default("none")
	MatchState.power_priority_coal_gas = "grid"
	MatchState.power_priority_wind_solar = "grid"
	TransportState.seaport_auto_subscribe = false
	_map = DataMap.new()
	add_child(_map)
	MatchState.seed_surveyed_ports()
	MatchState.seed_deposits(_map)
	_world = World.new()
	_world.terrain_layer = _map
	var tile: Dictionary = _map.tiles[_map.id_to_coord(site)]
	result["tile"] = tile.duplicate(true)
	if _is_mining(recipe):
		result["status"] = "excluded_mining"
		_write(result)
		return
	var bid := str(recipe.get("building_id", ""))
	var blocked := ""
	if not Catalog.is_building_allowed_on_tile_type(bid, str(tile.get("type", ""))):
		blocked = "Building terrain requirement is not met at %s" % site
	elif _world._recipe_requirement_block(tile, recipe, site) != "":
		blocked = "Recipe site requirements are not met at %s" % site
	if blocked != "":
		result.merge({"status": "unbuildable_at_site", "reason": blocked})
		_write(result)
		return
	BuildMode.build_attempted.connect(_world._on_build_attempted)
	BuildMode._last_attempt_ms = -10000
	if route_mode in ["roads", "rail"]:
		print("[pepper fixture] installing %s route from %s to %s" % [route_mode, site, TransportService.nearest_port_tile(site)])
		_install_route(site, TransportService.nearest_port_tile(site), route_mode)
		print("[pepper fixture] route installed")
	BuildMode.attempt_direct_build(bid, recipe_id, site, true)
	if Construction.construction_projects.size() != 1:
		result.merge({"status": "build_rejected", "reason": "UI build handler did not create a construction project"})
		_write(result)
		return
	var iid := str(Construction.construction_projects.keys()[0])
	result["construction_project"] = Construction.construction_projects[iid].duplicate(true)
	result["initial_build_cash_spent"] = INITIAL_EQUITY - MatchState.money
	var first_running := -1
	var sample_count := 0
	var steady_warmup := PEPPER_STEADY_WARMUP_TURNS if site == "tile_5_4" else 0
	for index in range(MAX_START_TURNS + SAMPLE_TURNS):
		# Construction creates the building only when its project completes.  Enable
		# the service at the first DECIDE phase after that point, so the measured
		# middleman case uses the same live provider as normal gameplay.
		if logistics_mode == "middleman" and not Middleman.enabled(iid) and BuildingState.buildings.has(iid):
			var enabled := Middleman.enable(iid)
			assert(bool(enabled.get("ok", false)), "middleman enable: %s" % enabled)
			for output: Dictionary in recipe.get("outputs", []):
				MatchState.route_output_to_market(iid, str(output.get("good_id", "")))
		var cash_before := MatchState.money
		var turn := TurnManager.current_turn
		var panel: Dictionary = {}
		if record_panel and BuildingState.buildings.has(iid):
			var b: Dictionary = BuildingState.get_building(iid)
			var r: Dictionary = Catalog.get_recipe(str(b.get("recipe_id", "")))
			panel = Readout.economics(b, r, Catalog.get_building(str(b.get("building_id", ""))))
			panel["value_added_v3"] = BuildingEconomics.per_turn(b)
		TurnManager.commit_turn()
		await TurnManager.turn_resolution_completed
		var row := Economics.capture(cash_before, iid)
		if record_panel:
			row["panel_economics"] = panel
		row["turn"] = turn
		row["ran"] = bool(Production.last_turn_run.get(iid, false))
		row["blocked_reason"] = Production.blocked_reason_by_building.get(iid, {}).duplicate(true)
		row["missing_inputs"] = Production.missing_by_building.get(iid, []).duplicate(true)
		if first_running < 0 and bool(row.ran):
			first_running = turn
			result["cash_spent_before_first_run"] = INITIAL_EQUITY - cash_before
		row["in_sample"] = first_running >= 0 and turn >= first_running + steady_warmup
		_rows.append(row)
		assert(ResearchState.unlocked_titles.is_empty() and AdvisorState.advisor_seats.is_empty())
		assert(BuildingState.buildings.size() <= 1 + rail_owned_limit and MatchState.building_tabs.is_empty())
		if row["in_sample"]:
			sample_count += 1
			if sample_count == SAMPLE_TURNS:
				break
		elif first_running < 0 and turn >= MAX_START_TURNS:
			break
	result["first_running_turn"] = first_running
	result["steady_state"] = _steady_summary()
	result["status"] = "completed" if sample_count == SAMPLE_TURNS else "never_ran"
	result["sample_count"] = sample_count
	result["transactions"] = MatchState.transaction_log.duplicate(true)
	result["final_modifiers"] = Modifiers.export_state()
	result["final_loans"] = LoanState.export_state()
	result["final_missions"] = {"completed": MiniQuest.done.duplicate(), "granted": MiniQuest.granted.duplicate()}
	_write(result)

func _steady_summary() -> Dictionary:
	var rows := _rows.filter(func(row: Dictionary) -> bool: return bool(row.get("in_sample", false)))
	if rows.is_empty():
		return {}
	var keys := ["cash_delta", "sales", "reported_net", "middleman_fee", "transport_paid", "warehousing_paid",
		"goods_sales_revenue", "goods_purchased_cost", "labour_paid", "maintenance_paid", "power_purchase_cost",
		"port_inbound", "port_outbound", "port_insurance"]
	var result := {"turns": rows.size()}
	for key: String in keys:
		var total := 0.0
		for row: Dictionary in rows:
			var empire: Dictionary = row.get("empire", {})
			if key == "cash_delta": total += float(row.get("cash_delta", 0.0))
			elif key == "sales": total += float(row.get("sales", 0.0))
			elif key == "reported_net": total += float(row.get("reported_net", 0.0))
			elif key in ["port_inbound", "port_outbound", "port_insurance"]:
				var breakdown: Dictionary = empire.get("transport_breakdown", {})
				total += float(breakdown.get(key, 0.0))
			else: total += float(empire.get(key, 0.0))
		result[key] = total / float(rows.size())
	return result

func _install_route(source: String, destination: String, mode: String) -> void:
	var queue: Array = [source]
	var previous := {source: ""}
	var index := 0
	while index < queue.size():
		var current := str(queue[index])
		index += 1
		if current == destination:
			break
		for neighbour in Catalog.tile_neighbours(current):
			var next := str(neighbour)
			if previous.has(next) or not bool(Catalog._tile_land.get(next, false)):
				continue
			previous[next] = current
			queue.append(next)
	assert(previous.has(destination), "No land corridor from %s to %s" % [source, destination])
	if not previous.has(destination):
		return
	var path: Array = []
	var cursor := destination
	while cursor != "":
		path.push_front(cursor)
		cursor = str(previous[cursor])
	var terrain = get_tree().get_first_node_in_group("hex_map")
	var owned_rail_count := 0
	for tile_id: String in path:
		Catalog.add_tile_infrastructure(tile_id, mode)
		Catalog.set_tile_infra_level(tile_id, mode, infra_level)
		var coord = terrain.id_to_coord(tile_id)
		if not terrain.tiles.has(coord):
			continue
		var data: Dictionary = terrain.tiles[coord]
		var slot := "rails" if mode == "rail" else mode
		var present: Array = data.get("infrastructure_present", [])
		if not present.has(slot):
			present.append(slot)
		data["infrastructure_present"] = present
		var levels: Dictionary = data.get("infrastructure_levels", {})
		levels[slot] = infra_level
		data["infrastructure_levels"] = levels
		terrain.tiles[coord] = data
		if mode == "rail" and owned_rail_count < rail_owned_limit:
			BuildingState.add_building("b_019", "", tile_id, MatchState.LOCAL_PLAYER)
			owned_rail_count += 1

func _write(data: Dictionary) -> void:
	var file := FileAccess.open(_out_path, FileAccess.WRITE)
	assert(file != null, "Could not open case output")
	file.store_string(JSON.stringify(data, "\t") + "\n")
	print("[recipe profitability] %s: %s" % [data.get("recipe_id", "catalogue"), data.get("status", "listed")])
