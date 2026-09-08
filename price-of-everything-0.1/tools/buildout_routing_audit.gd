extends Node
## Controlled reconstruction of the 2026-09-08 Metal Magnate log, not an action replay.
const Fixture := preload("res://tools/recipe_profitability_case.gd")
const Economics := preload("res://scripts/economics_snapshot.gd")
const STAGES := [
	["Starting company", 1], ["Steel", 7], ["Copper", 18], ["Wiring", 25],
	["Construction equipment", 32], ["Motors; coal mine exhausted", 38],
	["Automated motors", 55], ["Rail connection", 60],
	["Rare earths and electric steel; pipes", 68], ["Wind turbines", 92]]
var _map: HexMap

func _ready() -> void:
	var output: String = OS.get_cmdline_user_args()[0]
	preload("res://scripts/app_paths.gd")._base = output.get_basename() + "-runtime"
	SaveLoad.autosave_enabled = false
	TelemetryState.enabled = false
	RunMetrics.enabled = false
	await get_tree().process_frame
	var results: Array[Dictionary] = []
	for stage: Array in STAGES:
		results.append(await run_stage(str(stage[0]), int(stage[1])))
	var file := FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify(results, "\t"))
	get_tree().quit()

func install(tile: String, kind: String) -> void:
	Catalog.add_tile_infrastructure(tile, kind)
	var data: Dictionary = _map.tiles[_map.id_to_coord(tile)]
	var present: Array = data.get("infrastructure_present", [])
	if not present.has(kind):
		present.append(kind)
	data["infrastructure_present"] = present

func add_recipe(recipe: String, tile: String, destination: String = "") -> String:
	var rec := Catalog.get_recipe(recipe)
	var iid := MatchState.add_building(str(rec.building_id), recipe, tile)
	if destination != "":
		for good: Dictionary in rec.outputs:
			MatchState.set_output_stockpile_destination(iid, destination, str(good.good_id))
	return iid

func run_stage(label: String, milestone: int) -> Dictionary:
	MatchState.reset()
	TurnManager.reset_for_test()
	TurnManager.fast_mode = true
	_map = Fixture.DataMap.new()
	add_child(_map)
	_map.add_to_group("hex_map")
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/starts/metal_magnate.json"))
	SaveLoad.import_snapshot(SaveLoad.expand_start_config(config, {"speed_turns": 300, "tutorial_enabled": false, "policy_timeline": "demo_itch"}))
	MatchState.seed_deposits(_map)
	TurnManager.current_turn = milestone
	MatchState.money = 100000.0
	MatchState.debug_turn_logs_enabled = false
	MatchState._unlock_defs.clear()
	DecisionState.enabled = false
	# Keep shipped start bonuses, but no unrecorded advisor or research choices.
	MatchState.seaport_auto_subscribe = false
	for tile: String in ["tile_5_10", "tile_4_10", "tile_6_8", "tile_7_10"]:
		install(tile, "cables")
	install("tile_5_10", "pipes")
	if milestone >= 7:
		add_recipe("r_003", "tile_5_10", "tile_5_10")
	if milestone >= 18:
		add_recipe("r_007", "tile_5_10", "tile_5_10")
	if milestone >= 25:
		add_recipe("r_008", "tile_5_10", "tile_5_10")
	if milestone >= 32:
		add_recipe("r_033", "tile_5_10")
	if milestone >= 38:
		MatchState.remove_building("inst_b_001_0003e9")
		add_recipe("r_009", "tile_5_10")
	if milestone >= 55:
		add_recipe("r_203", "tile_4_10")
	if milestone >= 60:
		install("tile_4_10", "rail")
		install("tile_5_10", "rail")
	if milestone >= 68:
		install("tile_4_10", "reinf_pipes")
		install("tile_4_10", "pipes")
		install("tile_5_10", "reinf_pipes")
		add_recipe("r_041", "tile_4_10", "tile_4_10")
		add_recipe("r_076", "tile_4_10", "tile_4_10")
	if milestone >= 92:
		add_recipe("r_059", "tile_4_10")
	# Route local intermediates to tile inventory; surplus and finished goods go to market.
	for iid: String in MatchState.buildings:
		var b: Dictionary = MatchState.buildings[iid]
		if b.owner == MatchState.LOCAL_PLAYER and str(b.recipe_id) == "r_005":
			MatchState.set_output_stockpile_destination(iid, "tile_5_10", "g_004")
	MatchState.enable_sell_surplus("tile_5_10")
	MatchState.enable_sell_surplus("tile_4_10")
	var rows: Array[Dictionary] = []
	for index in 20:
		var cash: float = MatchState.money
		TurnManager.commit_turn()
		await TurnManager.turn_resolution_completed
		var row := Economics.capture(cash)
		row["turn"] = TurnManager.current_turn - 1
		row["sample"] = index >= 10
		row["running"] = Production.last_turn_run.duplicate()
		row["blocked"] = Production.blocked_reason_by_building.duplicate(true)
		if index >= 10:
			assert(MatchState.advisor_seats.is_empty(), "Controlled stages must not acquire advisors")
			for iid: String in MatchState.buildings:
				var b: Dictionary = MatchState.buildings[iid]
				assert(bool(Production.last_turn_run.get(iid, false)), "Every staged building must run in every sampled turn: " + str(b))
		rows.append(row)
	var net: float = 0.0
	for row: Dictionary in rows.slice(10):
		net += float(row.reported_net) / 10.0
	print("[buildout audit] ", label, " average=", net)
	var result: Dictionary = {"stage": label, "milestone": milestone, "net": net, "rows": rows, "buildings": MatchState.buildings.duplicate(true)}
	_map.queue_free()
	await get_tree().process_frame
	return result
