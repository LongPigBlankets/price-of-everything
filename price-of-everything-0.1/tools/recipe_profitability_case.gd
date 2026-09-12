extends Node
## One recipe per engine process: no shared match, price history, saves or modifiers.
## No main scene or panels. The actual UI build handler is called without entering
## the scene tree; the map uses the actual HexMap CSV loader without visual layers.
const Paths := preload("res://scripts/app_paths.gd")
const Economics := preload("res://scripts/economics_snapshot.gd")
const World := preload("res://scripts/world_map.gd")
const SITE := "tile_5_10"
const SAMPLE_TURNS := 10
const MAX_START_TURNS := 60
const INITIAL_EQUITY := 1000000.0
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
	result.merge({"schema_version": 1, "site": SITE, "sample_turns": SAMPLE_TURNS,
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
	var tile: Dictionary = _map.tiles[_map.id_to_coord(SITE)]
	result["tile"] = tile.duplicate(true)
	if _is_mining(recipe):
		result["status"] = "excluded_mining"
		_write(result)
		return
	var bid := str(recipe.get("building_id", ""))
	var blocked := ""
	if not Catalog.is_building_allowed_on_tile_type(bid, str(tile.get("type", ""))):
		blocked = "Building terrain requirement is not met at Stoneshore Docks"
	elif _world._recipe_requirement_block(tile, recipe, SITE) != "":
		blocked = "Recipe site requirements are not met at Stoneshore Docks"
	if blocked != "":
		result.merge({"status": "unbuildable_at_site", "reason": blocked})
		_write(result)
		return
	BuildMode.build_attempted.connect(_world._on_build_attempted)
	BuildMode._last_attempt_ms = -10000
	BuildMode.attempt_direct_build(bid, recipe_id, SITE, true)
	if Construction.construction_projects.size() != 1:
		result.merge({"status": "build_rejected", "reason": "UI build handler did not create a construction project"})
		_write(result)
		return
	var iid := str(Construction.construction_projects.keys()[0])
	result["construction_project"] = Construction.construction_projects[iid].duplicate(true)
	result["initial_build_cash_spent"] = INITIAL_EQUITY - MatchState.money
	var first_running := -1
	var sample_count := 0
	for index in range(MAX_START_TURNS + SAMPLE_TURNS):
		var cash_before := MatchState.money
		var turn := TurnManager.current_turn
		TurnManager.commit_turn()
		await TurnManager.turn_resolution_completed
		var row := Economics.capture(cash_before, iid)
		row["turn"] = turn
		row["ran"] = bool(Production.last_turn_run.get(iid, false))
		row["blocked_reason"] = Production.blocked_reason_by_building.get(iid, {}).duplicate(true)
		row["missing_inputs"] = Production.missing_by_building.get(iid, []).duplicate(true)
		if first_running < 0 and bool(row.ran):
			first_running = turn
			result["cash_spent_before_first_run"] = INITIAL_EQUITY - cash_before
		row["in_sample"] = first_running >= 0
		_rows.append(row)
		assert(ResearchState.unlocked_titles.is_empty() and AdvisorState.advisor_seats.is_empty())
		assert(BuildingState.buildings.size() <= 1 and MatchState.building_tabs.is_empty())
		if first_running >= 0:
			sample_count += 1
			if sample_count == SAMPLE_TURNS:
				break
		elif turn >= MAX_START_TURNS:
			break
	result["first_running_turn"] = first_running
	result["status"] = "completed" if sample_count == SAMPLE_TURNS else "never_ran"
	result["sample_count"] = sample_count
	result["transactions"] = MatchState.transaction_log.duplicate(true)
	result["final_modifiers"] = Modifiers.export_state()
	result["final_loans"] = LoanState.export_state()
	result["final_missions"] = {"completed": MiniQuest.done.duplicate(), "granted": MiniQuest.granted.duplicate()}
	_write(result)

func _write(data: Dictionary) -> void:
	var file := FileAccess.open(_out_path, FileAccess.WRITE)
	assert(file != null, "Could not open case output")
	file.store_string(JSON.stringify(data, "\t") + "\n")
	print("[recipe profitability] %s: %s" % [data.get("recipe_id", "catalogue"), data.get("status", "listed")])
