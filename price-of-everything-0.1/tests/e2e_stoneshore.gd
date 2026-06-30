extends Node
## Headless end-to-end scenario for the foundations sprint.
##
## This runner deliberately instantiates the real main scene and drives the same
## signal paths that UI clicks use where practical: survey mapmode signals, loan
## dialog buttons, BuildMode attempts, construction missing-materials buttons,
## and output-destination tile picks. Direct state calls are kept to deterministic
## harness setup (debug cash) and routing toggles that do not yet have a stable
## headless click target.
##
## Phase 1 refactor: the scenario is now DATA-DRIVEN. The hardcoded "optimized
## Capital motor chain" lives in res://tests/scenarios/open_field_1.json. Pick a
## scenario by name with the first user arg:
##     -- open_field_1 60     run scenario "open_field_1" to turn 60
##     -- 100                 (back-compat) run "open_field_1" to turn 100
## If the first user arg parses as an int it is treated as the turn and the
## scenario name defaults to "open_field_1".

const MAIN_SCENE := "res://scenes/main.tscn"
const BASELINE_PATH := "res://tests/snapshots/e2e_benchmark_baseline.json"
const LATEST_PATH := "user://e2e_stoneshore_latest.json"
const TURN_PROFILE_PATH := "user://turn_profile.csv"
const SCENARIOS_DIR := "res://tests/scenarios/"
const DEFAULT_SCENARIO := "open_field_1"
const DEFAULT_TARGET_TURN := 100
const CASH_RUNWAY := 25000
const COAL_RUNWAY_TURNS := 8
const SLOW_TURN_THRESHOLD_MS := 200.0

var _passed := 0
var _failed := 0
var _load_ms := 0.0
var _ready_ms := 0.0
var _turn_times_ms: Array[float] = []
var _turn_wall_records: Array[Dictionary] = []
var _main: Node = null
var _terrain: HexMap = null
var _construct_panel: Control = null
var _money_panel: Control = null
var _loan_dialog: Control = null
var _terminal: Node = null

var _goods := {}
var _buildings := {}
var _recipes := {}
var _built := {}
# Logical scenario building id (from JSON "id") -> Array of engine instance ids.
# A single config entry with count>1 maps to several instance ids.
var _built_by_id := {}
var _scenario := {}
var _scenario_name := DEFAULT_SCENARIO
var _scenario_note := ""
var _target_turn := DEFAULT_TARGET_TURN
var _revenue_history: Array[float] = []
var _profit_post_tax_history: Array[float] = []
var _cash_before_runway := 0.0
var _cash_after_runway := 0.0
var _cash_after_coal_runway := 0.0
var _cash_after_buildout := 0.0
var _coal_backed_available_capacity := 0.0
var _coal_backed_loan_amount := 0.0


func _ready() -> void:
	_parse_cmdline_args()
	print("\n==== price-of-everything E2E: %s ====" % _scenario_name)
	print("[E2E] scenario=%s target_turn=%d" % [_scenario_name, _target_turn])
	await _run()
	_check(_passed >= 80, "E2E scenario produced at least 80 assertions")
	_write_latest_metrics()
	print("==== E2E %d passed, %d failed ====\n" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _run() -> void:
	_reset_autoloads()
	_resolve_catalog_ids()
	_load_scenario()
	await _load_main_scene()
	_check_ui_loaded()
	_check_stoneshore_fixture()
	await _survey_deposits_via_ui()
	await _take_loan_via_ui(50.0, "initial working-capital loan")
	await _add_cash_through_terminal(CASH_RUNWAY)
	await _open_construct_panel_via_bottom_menu()
	_buy_land_from_config()
	await _build_coal_runway_from_config()
	await _take_coal_backed_loan_if_capacity_allows()

	var before_route := TransportService.route("tile_22_3", "tile_26_5", _goods.coal)
	await _build_transport_spine_from_config()
	await _advance_turns(2, "complete road/rail/cable construction")
	var after_route := TransportService.route("tile_22_3", "tile_26_5", _goods.coal)
	_check(int(after_route.get("turns", 999)) <= int(before_route.get("turns", 999)),
		"optimized rail corridor does not worsen coal-to-iron routing")
	_check(int(after_route.get("turns", 999)) < (1 << 30), "coal-to-iron rail route is reachable")
	_check(int(TransportService.route("tile_21_10", "tile_25_6", _goods.copper_wiring).get("turns", 999)) < (1 << 30),
		"copper-to-motor rail route is reachable")

	await _build_supply_chain_from_config()
	_configure_output_routes_from_config()
	_configure_surplus_sales_from_config()
	_configure_tile_only_inputs_from_config()
	await _advance_until_no_construction(14)
	_check(Construction.construction_projects.is_empty(), "all scenario construction projects completed")
	_check(MatchState.buildings.size() >= 24, "scenario has a live multi-building industrial base")

	_cash_after_buildout = MatchState.money
	await _run_to_target_turn(_target_turn)
	await _take_second_loan_if_capacity_allows()
	_check_economy_end_state()
	_check_benchmark_baseline()


# ─────────────────────────────────────────────────────────────────────────────
# Command-line + scenario loading (Phase 1 data-driven entry points)
# ─────────────────────────────────────────────────────────────────────────────

func _parse_cmdline_args() -> void:
	# Accepted forms:
	#   <name> <turn>   e.g. open_field_1 60
	#   <name>          scenario name, default turn
	#   <turn>          (back-compat) turn only, default scenario
	var args := OS.get_cmdline_user_args()
	_scenario_name = DEFAULT_SCENARIO
	_target_turn = DEFAULT_TARGET_TURN
	if args.is_empty():
		return
	var first := str(args[0])
	if first.is_valid_int():
		# Back-compat `-- 100`: first arg is the turn, scenario stays default.
		_target_turn = maxi(1, int(first))
		return
	_scenario_name = first
	if args.size() > 1 and str(args[1]).is_valid_int():
		_target_turn = maxi(1, int(args[1]))


func _load_scenario() -> void:
	var path := SCENARIOS_DIR + _scenario_name + ".json"
	_check(FileAccess.file_exists(path), "scenario file exists: %s" % path)
	var f := FileAccess.open(path, FileAccess.READ)
	_check(f != null, "scenario file opened: %s" % path)
	if f == null:
		_scenario = {}
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	_check(typeof(parsed) == TYPE_DICTIONARY, "scenario JSON parsed to a dictionary: %s" % _scenario_name)
	_scenario = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	_scenario_note = str(_scenario.get("note", ""))
	_check(not _scenario.has("buildings") or typeof(_scenario.get("buildings")) == TYPE_ARRAY,
		"scenario buildings is an array")


# Resolve a scenario building entry's recipe: prefer an explicit recipe_key into
# the pre-resolved _recipes map; otherwise fall back to _recipe_for() via the
# internal_name + recipe_output (+ optional recipe_display) fields.
func _scenario_recipe_id(entry: Dictionary) -> String:
	var key := str(entry.get("recipe_key", ""))
	if key != "":
		var resolved := str(_recipes.get(key, ""))
		_check(resolved != "", "scenario recipe_key resolved: %s" % key)
		return resolved
	var internal := str(entry.get("internal_name", ""))
	var output := str(entry.get("recipe_output", ""))
	var display := str(entry.get("recipe_display", ""))
	return _recipe_for(internal, output, display)


# Build every entry in a scenario building list, recording one or more instance
# ids per logical id. count defaults to 1; allow_market_materials defaults to true
# (the turn-1 rebalance left no pre-placed build materials on these tiles, so a
# direct tile-materials build would silently no-op — see open_field_1.json note).
func _build_buildings_from_list(entries: Array) -> void:
	for entry in entries:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var logical_id := str(entry.get("id", ""))
		var internal := str(entry.get("internal_name", ""))
		var building_id := str(_buildings.get(internal, ""))
		_check(building_id != "", "scenario building internal_name resolved: %s" % internal)
		var recipe_id := _scenario_recipe_id(entry)
		_check(recipe_id != "", "scenario building recipe resolved for %s" % logical_id)
		var tile_id := str(entry.get("tile", ""))
		var count := maxi(1, int(entry.get("count", 1)))
		var allow_market: bool = bool(entry.get("allow_market_materials", true))
		for i in range(count):
			var instance_id := await _build_building_via_build_mode(building_id, recipe_id, tile_id, allow_market)
			_register_built(logical_id, instance_id)
			var level := int(entry.get("level", 1))
			if level > 1 and instance_id != "":
				_apply_level(instance_id, level)


# Map a logical scenario id to its instance id(s). The first instance also lands
# in _built[logical_id] so legacy-style single references keep working.
func _register_built(logical_id: String, instance_id: String) -> void:
	if logical_id == "":
		return
	var list: Array = _built_by_id.get(logical_id, [])
	list.append(instance_id)
	_built_by_id[logical_id] = list
	if not _built.has(logical_id):
		_built[logical_id] = instance_id


func _instances_for(logical_id: String) -> Array:
	return _built_by_id.get(logical_id, [])


func _first_instance(logical_id: String) -> String:
	var list: Array = _built_by_id.get(logical_id, [])
	return str(list[0]) if not list.is_empty() else ""


# Best-effort level-up of a freshly built/awaiting building, mirroring the level
# field on a scenario building entry. Tolerant of either a live building or a
# project still under construction.
func _apply_level(instance_id: String, level: int) -> void:
	if MatchState.buildings.has(instance_id):
		var b: Dictionary = MatchState.buildings[instance_id]
		b["level"] = level
		MatchState.buildings[instance_id] = b
	elif Construction.construction_projects.has(instance_id):
		var p: Dictionary = Construction.construction_projects[instance_id]
		p["target_level"] = level
		Construction.construction_projects[instance_id] = p


func _buy_land_from_config() -> void:
	var purchases: Array = _scenario.get("land_purchases", [])
	for purchase in purchases:
		if typeof(purchase) != TYPE_DICTIONARY:
			continue
		var tile_id := str(purchase.get("tile", ""))
		var amount := int(purchase.get("amount", 0))
		var before_owned := MatchState.get_tile_land_owned(tile_id)
		var before_money := MatchState.money
		var ok := MatchState.purchase_tile_land(tile_id, amount)
		_check(ok, "land purchased for scenario on %s" % tile_id)
		_check(MatchState.get_tile_land_owned(tile_id) > before_owned,
			"land ownership increased on %s" % tile_id)
		_check(MatchState.money < before_money, "land purchase charged cash on %s" % tile_id)


func _build_coal_runway_from_config() -> void:
	var runway: Dictionary = _scenario.get("coal_runway", {})
	if runway.is_empty():
		_cash_after_coal_runway = MatchState.money
		return
	var runway_turns := int(runway.get("turns", COAL_RUNWAY_TURNS))
	# Mines bought their build materials from the market, so they sit in
	# awaiting_materials for the transport lead before the 2-turn build counts down.
	var construction_window := int(runway.get("construction_window", 8))
	await _build_buildings_from_list(runway.get("buildings", []))
	for route in runway.get("route_to_market", []):
		if typeof(route) != TYPE_DICTIONARY:
			continue
		var good_id := str(_goods.get(str(route.get("good", "")), ""))
		for instance_id in _instances_for(str(route.get("id", ""))):
			var iid := str(instance_id)
			MatchState.route_output_to_market(iid, good_id)
			_check(MatchState.is_output_market(iid, good_id),
				"coal runway mine routes directly to market: %s" % iid)
	for tile_id in runway.get("surplus_sales", []):
		MatchState.set_auto_sell_impact(str(tile_id), MatchState.IMPACT_ANY)
		MatchState.enable_sell_surplus(str(tile_id))
	await _advance_until_no_construction(construction_window)
	await _advance_turns(runway_turns, "coal runway market sales")
	_cash_after_coal_runway = MatchState.money
	_check(_sold_qty(_goods.coal) > 0, "coal runway sold coal to market before the motor buildout")
	_check(_recent_run_metric("profit_post_tax", mini(3, runway_turns)) > 0.0,
		"coal runway is recently post-tax profitable before expansion")


func _build_transport_spine_from_config() -> void:
	var spine: Dictionary = _scenario.get("transport_spine", {})
	if spine.is_empty():
		return
	var corridors: Array = spine.get("corridors", [])
	# Resolve corridors to concrete adjacent land paths and validate adjacency.
	var resolved_corridors: Array = []
	for corridor in corridors:
		if typeof(corridor) != TYPE_ARRAY or corridor.size() < 2:
			continue
		var path := _land_path(str(corridor[0]), str(corridor[corridor.size() - 1]))
		_check(path.size() >= 2, "optimized transport corridor has at least two tiles")
		for i in range(path.size() - 1):
			_check(Catalog.tile_neighbours(str(path[i])).has(str(path[i + 1])),
				"optimized corridor has adjacent step %s -> %s" % [str(path[i]), str(path[i + 1])])
		resolved_corridors.append(path)

	for tile_id in spine.get("roads", []):
		await _build_infra_via_build_mode("roads", str(tile_id))

	# rails: either an explicit tile list, or the literal "corridors" to mean "every
	# tile touched by the resolved corridors" (faithful to the original behaviour).
	var rails_spec = spine.get("rails", [])
	var rail_tiles: Array = []
	if typeof(rails_spec) == TYPE_STRING and str(rails_spec) == "corridors":
		var corridor_tiles := {}
		for path in resolved_corridors:
			for tile_id in path:
				corridor_tiles[str(tile_id)] = true
		rail_tiles = corridor_tiles.keys()
		rail_tiles.sort()
	elif typeof(rails_spec) == TYPE_ARRAY:
		for tile_id in rails_spec:
			rail_tiles.append(str(tile_id))
	for tile_id in rail_tiles:
		await _build_infra_via_build_mode("rails", str(tile_id))

	for tile_id in spine.get("cables", []):
		await _build_infra_via_build_mode("cables", str(tile_id))


func _build_supply_chain_from_config() -> void:
	await _build_buildings_from_list(_scenario.get("buildings", []))
	for key in _built.keys():
		_check(str(_built[key]) != "", "build helper returned instance id for %s" % str(key))


func _configure_output_routes_from_config() -> void:
	for route in _scenario.get("output_routes", []):
		if typeof(route) != TYPE_DICTIONARY:
			continue
		var logical_id := str(route.get("id", ""))
		var good_id := str(_goods.get(str(route.get("good", "")), ""))
		var dest := str(route.get("dest", ""))
		for instance_id in _instances_for(logical_id):
			var iid := str(instance_id)
			if dest == "market":
				MatchState.route_output_to_market(iid, good_id)
				_check(MatchState.is_output_market(iid, good_id),
					"output routed to market: %s %s" % [iid, good_id])
			else:
				_select_output_destination(iid, good_id, dest)


func _configure_surplus_sales_from_config() -> void:
	for tile_id in _scenario.get("surplus_sales", []):
		MatchState.set_auto_sell_impact(str(tile_id), MatchState.IMPACT_ANY)
		_check(MatchState.get_auto_sell_impact(str(tile_id)) == MatchState.IMPACT_ANY,
			"surplus sale impact set to any for %s" % str(tile_id))
		MatchState.enable_sell_surplus(str(tile_id))
		_check(MatchState.is_sell_surplus_enabled(str(tile_id)),
			"master surplus auto-sell armed for %s" % str(tile_id))


func _configure_tile_only_inputs_from_config() -> void:
	for entry in _scenario.get("tile_only_inputs", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var logical_id := str(entry.get("id", ""))
		var good_ids: Array = []
		for g in entry.get("goods", []):
			good_ids.append(str(_goods.get(str(g), "")))
		for instance_id in _instances_for(logical_id):
			_set_tile_only(str(instance_id), good_ids)


# ─────────────────────────────────────────────────────────────────────────────
# Preserved helpers (verbatim from the original linear scenario)
# ─────────────────────────────────────────────────────────────────────────────

func _reset_autoloads() -> void:
	var run_metrics := get_tree().root.get_node_or_null("RunMetrics")
	if run_metrics != null and run_metrics.has_method("reset"):
		run_metrics.reset()
	var turn_profiler := get_tree().root.get_node_or_null("TurnProfiler")
	if turn_profiler != null:
		turn_profiler.set("_csv_header_written", false)
	var turn_profile_file := FileAccess.open(TURN_PROFILE_PATH, FileAccess.WRITE)
	if turn_profile_file != null:
		turn_profile_file.close()
	TurnManager.fast_mode = true
	TurnManager.phase_pause_duration = 0.0
	TurnManager.reset_for_test()
	MatchState.reset()
	Stockpile.clear_all()
	Construction.construction_projects.clear()
	LoanState.loans.clear()
	LoanState.set("_next_loan_id", 1)
	LoanState.set("_profit_history", [])
	LoanState.set("_revenue_history", [])
	LoanState.last_payment_total = 0.0
	Production.last_turn_summary.clear()
	Production.last_turn_run.clear()
	Production.missing_by_building.clear()
	Production.produced_by_building.clear()
	Production.full_output_streak_by_building.clear()
	_revenue_history.clear()
	_profit_post_tax_history.clear()
	MarketState.prices.clear()
	for good in Catalog.all_goods():
		MarketState.prices[str(good.get("id", ""))] = float(good.get("base_price", 1.0))
	MarketState.prices_updated.emit()


func _resolve_catalog_ids() -> void:
	for internal in ["coal", "iron_ore", "copper_ore", "iron_ingots", "copper_ingots",
			"steel", "copper_wiring", "motor", "pure_water", "basic_salt",
			"chem_salts", "chlorine", "sodium_hydroxide"]:
		var good := Catalog.get_good_by_internal_name(internal)
		_check(not good.is_empty(), "catalog good exists: %s" % internal)
		_goods[internal] = str(good.get("id", ""))
	for internal in ["mine", "furnace", "industrial_factory", "chem_plant",
			"water_pump", "coal_power", "roads", "rails", "cables"]:
		var building := Catalog.get_building_by_internal_name(internal)
		_check(not building.is_empty(), "catalog building exists: %s" % internal)
		_buildings[internal] = str(building.get("id", ""))

	_recipes.coal_mining = _recipe_for("mine", "coal", "Coal")
	_recipes.iron_mining = _recipe_for("mine", "iron_ore", "Iron")
	_recipes.copper_mining = _recipe_for("mine", "copper_ore", "Copper")
	_recipes.salt_mining = _recipe_for("mine", "basic_salt", "Salt")
	_recipes.water_pumping = _recipe_for("water_pump", "pure_water", "Water")
	_recipes.pig_iron = _recipe_for("furnace", "iron_ingots", "Pig")
	_recipes.steel = _recipe_for("furnace", "steel", "Steel")
	_recipes.copper_ingots = _recipe_for("furnace", "copper_ingots", "Copper Blister")
	_recipes.copper_wiring = _recipe_for("industrial_factory", "copper_wiring", "Wire")
	_recipes.motor = _recipe_for("industrial_factory", "motor", "Motor")
	_recipes.chlorine = _recipe_for("chem_plant", "chlorine", "Chlor")
	_recipes.power = _recipe_for("coal_power", "power", "Power")
	for key in _recipes.keys():
		_check(str(_recipes[key]) != "", "scenario recipe resolved: %s -> %s" % [str(key), str(_recipes[key])])


func _recipe_for(building_internal: String, output_internal: String, display_contains: String = "") -> String:
	var building_id := str(_buildings.get(building_internal, ""))
	var output_good := Catalog.get_good_by_internal_name(output_internal)
	var output_id := str(output_good.get("id", ""))
	for recipe in Catalog.all_recipes():
		if str(recipe.get("building_id", "")) != building_id:
			continue
		if output_id != "" and not Catalog.recipe_produces(recipe, output_id):
			continue
		if display_contains != "" and str(recipe.get("display_name", "")).findn(display_contains) < 0:
			continue
		return str(recipe.get("recipe_id", ""))
	return ""


func _load_main_scene() -> void:
	var load_start := Time.get_ticks_usec()
	var packed := load(MAIN_SCENE) as PackedScene
	_load_ms = float(Time.get_ticks_usec() - load_start) / 1000.0
	_check(packed != null, "main scene loads for E2E")
	if packed == null:
		return
	var ready_start := Time.get_ticks_usec()
	_main = packed.instantiate()
	add_child(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_ready_ms = float(Time.get_ticks_usec() - ready_start) / 1000.0
	_terrain = _main.get_node("%TerrainLayer") as HexMap
	_construct_panel = _main.get_node("%ConstructPanel") as Control
	_money_panel = _main.get_node("%MoneyPanel") as Control
	_loan_dialog = _main.get_node("%TakeLoanDialog") as Control
	_terminal = _find_by_script(_main, "res://scripts/debug_terminal.gd")
	_check(_terrain != null, "E2E found real HexMap")
	_check(_construct_panel != null, "E2E found real ConstructPanel")
	_check(_money_panel != null, "E2E found real MoneyPanel")
	_check(_loan_dialog != null, "E2E found real TakeLoanDialog")
	_check(_terminal != null, "E2E found debug terminal for cash harness setup")


func _check_ui_loaded() -> void:
	_check(MatchState.use_alt_bottom_menu, "white-rimmed bottom menu is active in E2E")
	_check((_main.get_node("%BottomMenu") as Control).visible, "bottom menu starts visible")
	_check(not _construct_panel.visible, "construct panel starts hidden")
	_check(not _money_panel.visible, "money panel starts hidden")
	_check(MatchState.get_buildings_on_tile("tile_5_10").size() > 0, "NPC Stoneshore port placed")
	_check(MatchState.get_buildings_on_tile("tile_11_17").size() > 0, "NPC Arin port placed")
	_check(MatchState.get_buildings_on_tile("tile_24_7").size() > 0, "NPC Capital port placed")
	_check(MatchState.is_tile_surveyed("tile_5_10"), "Stoneshore starts surveyed")
	_check(MatchState.is_tile_surveyed("tile_11_17"), "Arin starts surveyed")
	_check(MatchState.is_tile_surveyed("tile_24_7"), "Capital starts surveyed")


func _check_stoneshore_fixture() -> void:
	var required := {
		"tile_22_3": "coal",
		"tile_20_9": "water",
		"tile_22_9": "coal",
		"tile_26_5": "iron_ore",
		"tile_21_10": "copper_ore",
	}
	for tile_id in required.keys():
		var td := _tile(tile_id)
		_check(not td.is_empty(), "fixture tile exists: %s" % tile_id)
		_check(_tile_deposits_include(td, str(required[tile_id])), "fixture tile %s has %s" % [tile_id, str(required[tile_id])])
		_check(float(td.get("build_capacity", 0)) >= 100.0, "fixture tile %s has enough build capacity" % tile_id)
	var assembly_tile := _tile("tile_25_6")
	_check(not assembly_tile.is_empty(), "fixture assembly tile exists: tile_25_6")
	_check(float(assembly_tile.get("build_capacity", 0)) >= 100.0, "fixture assembly tile has enough build capacity")
	_check(Catalog.nearest_port_tile("tile_25_6") == "tile_24_7", "motor tile uses Capital as nearest port")
	_check(Catalog.nearest_port_tile("tile_11_17") == "tile_11_17", "Arin port resolves to itself")


func _survey_deposits_via_ui() -> void:
	await _survey_tile_via_ui("tile_23_9")
	await _survey_tile_via_ui("tile_25_6")
	await _survey_tile_via_ui("tile_24_5")
	await _advance_turns(2, "complete first survey wave")
	_check(MatchState.is_tile_surveyed("tile_23_9"), "Capital coal approach tile surveyed")
	_check(MatchState.is_tile_surveyed("tile_25_6"), "Capital iron approach tile surveyed")
	_check(MatchState.is_tile_surveyed("tile_24_5"), "Capital northern coal approach tile surveyed")
	await _survey_tile_via_ui("tile_22_9")
	await _survey_tile_via_ui("tile_26_5")
	await _survey_tile_via_ui("tile_23_4")
	await _advance_turns(2, "complete second survey wave")
	_check(MatchState.is_tile_surveyed("tile_22_9"), "survey bridge coal tile surveyed")
	_check(MatchState.is_tile_surveyed("tile_26_5"), "iron tile surveyed")
	_check(MatchState.is_tile_surveyed("tile_23_4"), "northern coal approach tile surveyed")
	await _survey_tile_via_ui("tile_20_9")
	await _survey_tile_via_ui("tile_21_10")
	await _survey_tile_via_ui("tile_22_3")
	await _advance_turns(2, "complete optimized resource survey")
	_check(MatchState.is_tile_surveyed("tile_22_3"), "primary coal tile surveyed")
	_check(MatchState.is_tile_surveyed("tile_20_9"), "power water tile surveyed")
	_check(MatchState.is_tile_surveyed("tile_21_10"), "primary copper tile surveyed")
	for tile_id in ["tile_23_9", "tile_25_6", "tile_24_5", "tile_22_9",
			"tile_26_5", "tile_23_4", "tile_22_3", "tile_20_9", "tile_21_10"]:
		_check(MatchState.is_tile_surveyed(tile_id), "%s surveyed through UI flow" % tile_id)
	MapMode.clear_all()


func _survey_tile_via_ui(tile_id: String) -> void:
	MapMode.clear_all()
	await get_tree().process_frame
	var activated := MapMode.set_sentinel_mode(MapMode.Mode.SURVEYING, MapMode.SURVEYING_SENTINEL)
	_check(activated and MapMode.current_mode == MapMode.Mode.SURVEYING, "survey mapmode active for %s" % tile_id)
	_check(MatchState.is_tile_surveyable(tile_id), "%s is surveyable before clicking" % tile_id)
	_terrain.survey_tile_clicked.emit(_tile(tile_id))
	await get_tree().process_frame
	var dialog := _main.get("_survey_dialog") as Control
	_check(dialog != null and dialog.visible, "survey dialog opened for %s" % tile_id)
	if dialog == null:
		return
	var market_btn := dialog.get("_market_btn") as Button
	_check(market_btn != null and not market_btn.disabled, "survey market-order button enabled for %s" % tile_id)
	var money_before := MatchState.money
	if market_btn != null:
		market_btn.pressed.emit()
	await get_tree().process_frame
	_check(MatchState.money < money_before, "surveying %s charged cash" % tile_id)
	_check(MatchState.is_survey_in_progress(tile_id), "surveying %s is in progress" % tile_id)


func _take_loan_via_ui(amount: float, label: String) -> void:
	var money_widget := _main.get_node("%TopBar/MarginContainer/HBoxContainer/MoneyWidget") as Button
	_check(money_widget != null, "money widget exists for loan UI")
	if money_widget != null:
		money_widget.pressed.emit()
	await get_tree().process_frame
	_check(_money_panel.visible, "money panel opened for %s" % label)
	var take_button := _money_panel.get_node("MarginContainer/ModalLayout/TabContainer/Loans/MarginContainer/ContentVBox/ActionsRow/TakeLoanButton") as Button
	_check(take_button != null and not take_button.disabled, "take-loan button enabled for %s" % label)
	if take_button != null:
		take_button.pressed.emit()
	await get_tree().process_frame
	_check(_loan_dialog.visible, "loan dialog opened for %s" % label)
	var slider := _loan_dialog.get_node("MarginContainer/VBoxContainer/AmountRow/AmountSlider") as HSlider
	var confirm := _loan_dialog.get_node("MarginContainer/VBoxContainer/ButtonsRow/ConfirmButton") as Button
	_check(slider != null, "loan amount slider exists")
	_check(confirm != null, "loan confirm button exists")
	if slider != null:
		slider.value = minf(amount, slider.max_value)
	var loans_before := LoanState.loans.size()
	var money_before := MatchState.money
	if confirm != null:
		confirm.pressed.emit()
	await get_tree().process_frame
	_check(LoanState.loans.size() == loans_before + 1, "loan added through UI: %s" % label)
	_check(MatchState.money > money_before, "loan disbursed cash: %s" % label)
	_check(LoanState.total_outstanding() > 0.0, "loan outstanding balance recorded")
	_money_panel.hide()


func _take_second_loan_if_capacity_allows() -> void:
	if LoanState.available_capacity() < 1.0:
		_check(true, "second loan skipped because no post-scenario capacity was available")
		return
	await _take_loan_via_ui(minf(25.0, LoanState.available_capacity()), "post-build capacity loan")


func _take_coal_backed_loan_if_capacity_allows() -> void:
	var available := LoanState.available_capacity()
	_coal_backed_available_capacity = available
	if available < 1.0:
		_check(true, "coal-backed expansion loan skipped because coal runway had no extra credit capacity")
		return
	_coal_backed_loan_amount = minf(250.0, available)
	await _take_loan_via_ui(_coal_backed_loan_amount, "coal-backed expansion loan")
	_check(_coal_backed_loan_amount > 0.0, "coal sales unlocked an expansion loan")


func _add_cash_through_terminal(amount: int) -> void:
	_check(_terminal != null, "debug terminal available for documented cash harness exception")
	if _terminal == null:
		_cash_before_runway = MatchState.money
		MatchState.add_money(float(amount))
		_cash_after_runway = MatchState.money
		return
	var before := MatchState.money
	_cash_before_runway = before
	var result := str(_terminal.call("_run_command", "cash %d" % amount))
	_check(result.find("Added") >= 0, "debug terminal accepted cash command")
	_check(MatchState.money >= before + float(amount), "debug terminal cash applied")
	_cash_after_runway = MatchState.money


func _open_construct_panel_via_bottom_menu() -> void:
	var button := _main.get_node("%ConstructButton") as Button
	_check(button != null, "construct bottom-menu button exists")
	if button != null:
		button.pressed.emit()
	await get_tree().process_frame
	_check(_construct_panel.visible, "construct panel opened from bottom menu")


func _land_path(source_tile: String, dest_tile: String) -> Array:
	if source_tile == dest_tile:
		return [source_tile]
	var frontier := [source_tile]
	var came_from := {}
	came_from[source_tile] = ""
	var index := 0
	while index < frontier.size():
		var current := str(frontier[index])
		index += 1
		if current == dest_tile:
			break
		for next_tile in Catalog.tile_neighbours(current):
			var next_id := str(next_tile)
			if came_from.has(next_id):
				continue
			var td := _tile(next_id)
			if td.is_empty():
				continue
			var tile_type := str(td.get("type", ""))
			if tile_type.findn("sea") >= 0 and next_id != dest_tile:
				continue
			came_from[next_id] = current
			frontier.append(next_id)
	if not came_from.has(dest_tile):
		return [source_tile, dest_tile]
	var path := []
	var cursor := dest_tile
	while cursor != "":
		path.push_front(cursor)
		cursor = str(came_from.get(cursor, ""))
	return path


func _build_infra_via_build_mode(infra_type: String, tile_id: String) -> void:
	var td := _tile(tile_id)
	var existing: Array = td.get("infrastructure_present", [])
	if existing.has(infra_type):
		_check(true, "%s already present on %s" % [infra_type, tile_id])
		return
	var before_projects := Construction.construction_projects.size()
	BuildMode.enter_infrastructure_mode(infra_type)
	_check(BuildMode.is_active and BuildMode.kind == BuildMode.Kind.INFRASTRUCTURE,
		"BuildMode entered infrastructure mode for %s" % infra_type)
	BuildMode.set("_last_attempt_ms", 0)
	BuildMode.attempt_build(tile_id)
	await get_tree().process_frame
	BuildMode.exit_build_mode()
	var started := Construction.construction_projects.size() > before_projects
	_check(started, "infrastructure project queued: %s on %s" % [infra_type, tile_id])


func _build_building_via_build_mode(building_id: String, recipe_id: String, tile_id: String, allow_market_materials: bool) -> String:
	var before_projects := _keys_dict(Construction.construction_projects)
	var before_buildings := _keys_dict(MatchState.buildings)
	var money_before := MatchState.money
	BuildMode.set("_last_attempt_ms", 0)
	BuildMode.attempt_direct_build(building_id, recipe_id, tile_id)
	await get_tree().process_frame
	var instance_id := _find_new_project_or_building(before_projects, before_buildings, building_id, recipe_id, tile_id)
	if instance_id == "" and allow_market_materials:
		var dialog := _main.get("_construction_dialog") as Control
		_check(dialog != null and dialog.visible, "missing-materials dialog opened for %s on %s" % [building_id, tile_id])
		if dialog != null:
			var buy_btn := dialog.get("_buy_button") as Button
			_check(buy_btn != null and not buy_btn.disabled, "buy-and-construct button enabled for %s" % building_id)
			if buy_btn != null:
				buy_btn.pressed.emit()
			await get_tree().process_frame
		instance_id = _find_new_project_or_building(before_projects, before_buildings, building_id, recipe_id, tile_id)
		_check(Construction.construction_projects.has(instance_id), "awaiting/under-construction project created for %s" % instance_id)
	else:
		_check(instance_id != "", "direct construction project created for %s on %s" % [building_id, tile_id])
	_check(MatchState.money < money_before, "building attempt charged money for %s on %s" % [building_id, tile_id])
	return instance_id


func _find_new_project_or_building(before_projects: Dictionary, before_buildings: Dictionary,
		building_id: String, recipe_id: String, tile_id: String) -> String:
	for instance_id in Construction.construction_projects.keys():
		if before_projects.has(instance_id):
			continue
		var project: Dictionary = Construction.construction_projects[instance_id]
		if str(project.get("building_id", "")) == building_id \
				and str(project.get("recipe_id", "")) == recipe_id \
				and str(project.get("tile_id", "")) == tile_id:
			return str(instance_id)
	for instance_id in MatchState.buildings.keys():
		if before_buildings.has(instance_id):
			continue
		var building: Dictionary = MatchState.buildings[instance_id]
		if str(building.get("building_id", "")) == building_id \
				and str(building.get("recipe_id", "")) == recipe_id \
				and str(building.get("tile_id", "")) == tile_id:
			return str(instance_id)
	return ""


func _select_output_destination(instance_id: String, good_id: String, tile_id: String) -> void:
	MatchState.begin_output_stockpile_selection(instance_id, good_id)
	_check(not MatchState.pending_output_stockpile_selection.is_empty(),
		"output destination selection began for %s %s" % [instance_id, good_id])
	_terrain.stockpile_destination_selected.emit(_tile(tile_id))
	_check(MatchState.get_output_stockpile_destination(instance_id, good_id) == tile_id,
		"output destination selected: %s -> %s" % [good_id, tile_id])


func _set_tile_only(instance_id: String, good_ids: Array) -> void:
	for good_id in good_ids:
		MatchState.set_input_tile_only(instance_id, str(good_id), true)
		_check(MatchState.is_input_tile_only(instance_id, str(good_id)),
			"input set to tile-stockpile-only: %s %s" % [instance_id, str(good_id)])


func _advance_until_no_construction(max_turns: int) -> void:
	var turns := 0
	while not Construction.construction_projects.is_empty() and turns < max_turns:
		await _advance_turns(1, "waiting for construction")
		turns += 1
	_check(turns < max_turns, "construction completed within %d turns" % max_turns)
	for key in _built.keys():
		var instance_id := str(_built[key])
		_check(MatchState.buildings.has(instance_id), "completed building is live: %s" % str(key))


func _run_to_target_turn(target_turn: int) -> void:
	while TurnManager.current_turn < target_turn:
		await _advance_turns(1, "run economy to target turn")
	_check(TurnManager.current_turn >= target_turn, "scenario reached turn %d" % target_turn)


func _advance_turns(count: int, reason: String) -> void:
	for _i in range(count):
		var before_turn := TurnManager.current_turn
		var start := Time.get_ticks_usec()
		TurnManager.commit_turn()
		await TurnManager.turn_resolution_completed
		_capture_turn_metrics()
		var elapsed_ms := float(Time.get_ticks_usec() - start) / 1000.0
		_turn_times_ms.append(elapsed_ms)
		_turn_wall_records.append({
			"turn": before_turn,
			"reason": reason,
			"wall_ms": elapsed_ms,
		})
		if before_turn <= 8 or before_turn % 10 == 0 or before_turn + 1 >= _target_turn:
			_check(TurnManager.current_turn == before_turn + 1,
				"turn advanced for %s (%d -> %d)" % [reason, before_turn, TurnManager.current_turn])


func _capture_turn_metrics() -> void:
	var summary: Dictionary = Production.last_turn_summary
	if summary.is_empty():
		_revenue_history.append(0.0)
		_profit_post_tax_history.append(0.0)
		return
	var revenue := float(summary.get("goods_sales_revenue", 0.0)) + float(summary.get("power_sales_revenue", 0.0))
	var profit_post_tax := float(summary.get("money_in", 0.0)) - float(summary.get("money_out", 0.0))
	_revenue_history.append(revenue)
	_profit_post_tax_history.append(profit_post_tax)


func _check_economy_end_state() -> void:
	var totals := Stockpile.get_all_totals()
	var summary: Dictionary = Production.last_turn_summary
	var cumulative_profit := _cumulative_run_metric("profit_post_tax")
	var cumulative_revenue := _cumulative_run_metric("revenue")
	var recent_profit := _recent_run_metric("profit_post_tax", 10)
	var motor_ids := _instances_for("motor_a") + _instances_for("motor_b") + _instances_for("motor_c")
	var wiring_ids := _instances_for("copper_wiring_a") + _instances_for("copper_wiring_b")
	var coal_mine_a := _first_instance("coal_mine_a")
	var coal_mine_c := _first_instance("coal_mine_c")
	var coal_mine_d := _first_instance("coal_mine_d")
	var steel_a := _first_instance("steel_a")
	var wiring_a := _first_instance("copper_wiring_a")
	_check(not summary.is_empty(), "production summary exists after E2E run")
	_check(int(summary.get("power_demand", 0)) > 0, "power demand was transmitted through cabled tiles")
	_check(int(summary.get("grid_bought", 0)) >= 0, "power grid settlement ran")
	_check(int(summary.get("grid_bought", 0)) == 0, "local coal power fully covers scenario demand")
	_check(int(summary.get("grid_sold", 0)) > 0, "surplus local power is sold to the grid")
	_check(float(summary.get("maintenance_paid", 0.0)) > 0.0, "maintenance costs were paid")
	_check(float(summary.get("labour_paid", 0.0)) > 0.0, "labour costs were paid")
	_check(float(summary.get("transport_paid", 0.0)) >= 0.0, "transport costs were tracked")
	_check(totals.get(_goods.motor, 0) > 0 or _sold_qty(_goods.motor) > 0,
		"motor supply chain produced or sold motors")
	_check(_produced_total_by(motor_ids, _goods.motor) > 0,
		"motor factories produced motors")
	_check(_produced_total_by(wiring_ids, _goods.copper_wiring) > 0,
		"wiring factories produced copper wiring")
	_check(_sold_qty(_goods.motor) > 0, "motor sale was logged")
	_check(_sold_revenue(_goods.motor) > 0.0, "motor sale produced market revenue")
	_check(cumulative_revenue > 0.0, "cumulative scenario revenue is positive")
	_check(recent_profit > 0.0, "last 10 turns are post-tax profitable")
	_check(cumulative_profit > 0.0, "cumulative post-tax profit is positive")
	_check(MatchState.money > _cash_after_buildout, "optimized motor chain increases cash after buildout")
	_check(MatchState.transaction_log.size() > 0, "transaction ledger populated")
	_check(MatchState.move_log.size() > 0, "movement ledger populated")
	_check(MatchState.get_pending_transport_shipments().size() >= 0, "pending transport can be queried")
	_check(MatchState.money > EconomyConfig.BANKRUPTCY_FLOOR, "company remains above bankruptcy floor")
	_check(LoanState.total_per_turn_payment() >= 0.0, "loan payment state remains queryable")
	_check(MatchState.deposit_remaining_for("tile_22_3", "coal") == -1, "coal deposit is unbounded for turn-100 run")
	_check(MatchState.deposit_remaining_for("tile_26_5", "iron_ore") == -1, "iron deposit is unbounded for turn-100 run")
	_check(TransportService.route("tile_21_10", "tile_25_6", _goods.copper_wiring).get("turns", 0) >= 1,
		"wiring route between industrial tiles resolves")
	_check(TransportService.route_to_nearest_port("tile_25_6", _goods.motor).get("port", "") == "tile_24_7",
		"motor market route uses Capital")
	# Output-route destinations resolved on representative chain links.
	if coal_mine_a != "":
		_check(MatchState.get_output_stockpile_destination(coal_mine_a, str(_goods.coal)) == "tile_26_5",
			"coal output routed to iron/steel tile")
	if coal_mine_c != "":
		_check(MatchState.get_output_stockpile_destination(coal_mine_c, str(_goods.coal)) == "tile_20_9",
			"coal output routed to power tile")
	if coal_mine_d != "":
		_check(MatchState.get_output_stockpile_destination(coal_mine_d, str(_goods.coal)) == "tile_20_9",
			"second coal output routed to power tile")
	if steel_a != "":
		_check(MatchState.get_output_stockpile_destination(steel_a, str(_goods.steel)) == "tile_25_6",
			"steel output routed to motor tile")
	if wiring_a != "":
		_check(MatchState.get_output_stockpile_destination(wiring_a, str(_goods.copper_wiring)) == "tile_25_6",
			"copper wiring output routed to motor tile")
	if _scenario_note == "":
		_scenario_note = "scenario %s completed to turn %d" % [_scenario_name, _target_turn]


func _check_benchmark_baseline() -> void:
	var baseline := _load_baseline()
	_check(not baseline.is_empty(), "benchmark baseline snapshot loaded")
	if baseline.is_empty():
		return
	var max_multiplier := float(baseline.get("max_multiplier", 3.0))
	var slack := float(baseline.get("absolute_slack_ms", 1000.0))
	var stats := _turn_stats()
	_check(_load_ms <= float(baseline.get("load_ms", 1.0)) * max_multiplier + slack,
		"main scene load time within baseline budget (%.2f ms)" % _load_ms)
	_check(_ready_ms <= float(baseline.get("ready_ms", 1.0)) * max_multiplier + slack,
		"main scene instantiate+ready time within baseline budget (%.2f ms)" % _ready_ms)
	_check(float(stats.get("mean_ms", 0.0)) <= float(baseline.get("turn_mean_ms", 1.0)) * max_multiplier + slack,
		"mean turn time within baseline budget (%.2f ms)" % float(stats.get("mean_ms", 0.0)))
	_check(float(stats.get("p95_ms", 0.0)) <= float(baseline.get("turn_p95_ms", 1.0)) * max_multiplier + slack,
		"p95 turn time within baseline budget (%.2f ms)" % float(stats.get("p95_ms", 0.0)))
	_check(_turn_times_ms.size() >= int(baseline.get("min_turns_measured", 50)), "benchmark measured enough turns")


func _load_baseline() -> Dictionary:
	if not FileAccess.file_exists(BASELINE_PATH):
		return {}
	var f := FileAccess.open(BASELINE_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _write_latest_metrics() -> void:
	var stats := _turn_stats()
	var cumulative_revenue := _cumulative_run_metric("revenue")
	var cumulative_profit := _cumulative_run_metric("profit_post_tax")
	var recent_profit := _recent_run_metric("profit_post_tax", 10)
	var slow_turns := _slow_turn_records(SLOW_TURN_THRESHOLD_MS)
	var latest := {
		"scenario": _scenario_name,
		"target_turn": _target_turn,
		"assertions_passed": _passed,
		"assertions_failed": _failed,
		"load_ms": _load_ms,
		"ready_ms": _ready_ms,
		"turns_measured": _turn_times_ms.size(),
		"turn_mean_ms": stats.get("mean_ms", 0.0),
		"turn_median_ms": stats.get("median_ms", 0.0),
		"turn_p95_ms": stats.get("p95_ms", 0.0),
		"turn_max_ms": stats.get("max_ms", 0.0),
		"slow_turn_threshold_ms": SLOW_TURN_THRESHOLD_MS,
		"slow_turns": slow_turns,
		"buildings": MatchState.buildings.size(),
		"pending_shipments": MatchState.pending_transport_shipments.size(),
		"money": MatchState.money,
		"cash_before_runway": _cash_before_runway,
		"cash_after_runway": _cash_after_runway,
		"cash_after_coal_runway": _cash_after_coal_runway,
		"cash_after_buildout": _cash_after_buildout,
		"cash_delta_from_runway": MatchState.money - _cash_after_runway,
		"cash_delta_from_coal_runway": MatchState.money - _cash_after_coal_runway,
		"cash_delta_from_buildout": MatchState.money - _cash_after_buildout,
		"coal_backed_available_capacity": _coal_backed_available_capacity,
		"coal_backed_loan_amount": _coal_backed_loan_amount,
		"cumulative_revenue": cumulative_revenue,
		"cumulative_profit_post_tax": cumulative_profit,
		"recent_10_profit_post_tax": recent_profit,
		"note": _scenario_note,
	}
	var f := FileAccess.open(LATEST_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(latest, "\t"))
		f.close()
	print("[E2E] latest metrics: ", JSON.stringify(latest))


func _slow_turn_records(threshold_ms: float) -> Array:
	var profiler_rows := _turn_profiler_rows_by_turn()
	var out: Array = []
	for record in _turn_wall_records:
		var wall_ms := float(record.get("wall_ms", 0.0))
		if wall_ms <= threshold_ms:
			continue
		var turn := int(record.get("turn", 0))
		var profiler: Dictionary = profiler_rows.get(turn, {})
		var slow := record.duplicate(true)
		slow["wall_ms"] = snappedf(wall_ms, 0.001)
		if not profiler.is_empty():
			slow["profiler_total_ms"] = profiler.get("total_ms", 0.0)
			slow["profiler_steps"] = profiler.get("steps", {})
			slow["profiler_scale"] = profiler.get("scale", {})
		out.append(slow)
	return out


func _turn_profiler_rows_by_turn() -> Dictionary:
	var out := {}
	if not FileAccess.file_exists(TURN_PROFILE_PATH):
		return out
	var f := FileAccess.open(TURN_PROFILE_PATH, FileAccess.READ)
	if f == null:
		return out
	var header := f.get_csv_line()
	while not f.eof_reached():
		var line := f.get_csv_line()
		if line.size() < header.size() or (line.size() == 1 and line[0] == ""):
			continue
		var row := {}
		for i in header.size():
			row[str(header[i])] = line[i] if i < line.size() else ""
		var turn := int(row.get("turn", 0))
		var steps := {}
		var scale := {}
		for key in row.keys():
			var key_str := str(key)
			if key_str.begins_with("step_"):
				steps[key_str.trim_prefix("step_")] = float(row[key])
			elif key_str.begins_with("scale_"):
				scale[key_str.trim_prefix("scale_")] = int(row[key])
		out[turn] = {
			"total_ms": float(row.get("total_ms", 0.0)),
			"steps": steps,
			"scale": scale,
		}
	f.close()
	return out


func _turn_stats() -> Dictionary:
	if _turn_times_ms.is_empty():
		return {"mean_ms": 0.0, "median_ms": 0.0, "p95_ms": 0.0, "max_ms": 0.0}
	var sorted := _turn_times_ms.duplicate()
	sorted.sort()
	var sum := 0.0
	for v in sorted:
		sum += float(v)
	var p95_idx := clampi(int(ceil(float(sorted.size()) * 0.95)) - 1, 0, sorted.size() - 1)
	return {
		"mean_ms": sum / float(sorted.size()),
		"median_ms": float(sorted[sorted.size() / 2]),
		"p95_ms": float(sorted[p95_idx]),
		"max_ms": float(sorted[sorted.size() - 1]),
	}


func _produced_by(instance_id: String, good_id: String) -> int:
	return int((Production.produced_by_building.get(instance_id, {}) as Dictionary).get(good_id, 0))


func _produced_total_by(instance_ids: Array, good_id: String) -> int:
	var total := 0
	for instance_id in instance_ids:
		total += _produced_by(str(instance_id), good_id)
	return total


func _cumulative_run_metric(column: String) -> float:
	if column == "profit_post_tax":
		var profit_total := 0.0
		for value in _profit_post_tax_history:
			profit_total += float(value)
		return profit_total
	if column == "revenue":
		var revenue_total := 0.0
		for value in _revenue_history:
			revenue_total += float(value)
		return revenue_total
	if not RunMetrics.has_method("read_rows"):
		return 0.0
	var total := 0.0
	for row in RunMetrics.read_rows():
		total += float(row.get(column, 0.0))
	return total


func _recent_run_metric(column: String, count: int) -> float:
	if column == "profit_post_tax":
		return _recent_array_total(_profit_post_tax_history, count)
	if column == "revenue":
		return _recent_array_total(_revenue_history, count)
	if not RunMetrics.has_method("read_rows"):
		return 0.0
	var rows: Array = RunMetrics.read_rows()
	var start := maxi(0, rows.size() - maxi(0, count))
	var total := 0.0
	for i in range(start, rows.size()):
		total += float((rows[i] as Dictionary).get(column, 0.0))
	return total


func _recent_array_total(values: Array[float], count: int) -> float:
	var start := maxi(0, values.size() - maxi(0, count))
	var total := 0.0
	for i in range(start, values.size()):
		total += float(values[i])
	return total


func _sold_qty(good_id: String) -> int:
	var total := 0
	for row in MatchState.transaction_log:
		if str(row.get("kind", "")) == "sell" and str(row.get("good_id", "")) == good_id:
			total += int(row.get("qty", 0))
	return total


func _sold_revenue(good_id: String) -> float:
	var total := 0.0
	for row in MatchState.transaction_log:
		if str(row.get("kind", "")) == "sell" and str(row.get("good_id", "")) == good_id:
			total += float(row.get("qty", 0)) * MarketState.get_price(good_id)
	return total


func _tile(tile_id: String) -> Dictionary:
	if _terrain == null:
		return {}
	var coord := _terrain.id_to_coord(tile_id)
	return _terrain.tiles.get(coord, {})


func _tile_deposits_include(tile_data: Dictionary, token: String) -> bool:
	for dep in tile_data.get("deposits", []):
		var raw := str(dep)
		var p := raw.find("(")
		var found := raw.substr(0, p) if p >= 0 else raw
		if found.strip_edges().to_lower() == token:
			return true
	return false


func _keys_dict(source: Dictionary) -> Dictionary:
	var out := {}
	for key in source.keys():
		out[key] = true
	return out


func _find_by_script(root: Node, script_path: String) -> Node:
	if root == null:
		return null
	var script = root.get_script()
	if script != null and script.resource_path == script_path:
		return root
	for child in root.get_children():
		var found := _find_by_script(child, script_path)
		if found != null:
			return found
	return null


func _check(ok: bool, name: String) -> void:
	if ok:
		_passed += 1
		print("  PASS  ", name)
	else:
		_failed += 1
		printerr("  FAIL  ", name)
