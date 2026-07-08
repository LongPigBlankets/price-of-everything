extends Node
## Ground-truth balance probe for the tutorial's glass -> aluminium -> windows chain.
## Seeds all three buildings CO-LOCATED on the port (so there's no transport/oscillation noise)
## with surplus-selling on, runs turns, and logs the real per-turn money delta + each building's
## run state + the on-tile glass/aluminium/windows stock. Answers: is the integrated chain
## actually profitable, and does the 33-glass/24-produced mismatch starve the window factory?
##   <godot> --headless --path . res://tools/chain_probe.tscn --quit-after 6000

const MAIN_SCENE := "res://scenes/main.tscn"
const START := "res://data/starts/_chain_probe.json"
const BuildingReadout := preload("res://scripts/building_readout.gd")
const TILE := "tile_5_10"

var _main: Node = null
var _started := false
var _frames := 0


func _ready() -> void:
	SaveLoad.prepare_new_game(START)
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	add_child(_main)


func _process(_dt: float) -> void:
	if _started:
		return
	_frames += 1
	if _main != null and _main.get("build_complete") == true:
		_started = true
		_run()
	elif _frames > 3000:
		get_tree().quit(1)


func _run() -> void:
	TurnManager.fast_mode = true
	TurnManager.phase_pause_duration = 0.0
	MatchState.enable_sell_surplus(TILE)
	print("=== CHAIN PROBE: b_007(windows)+b_002(glass)+b_012(aluminium) co-located on %s, sell-surplus ON ===" % TILE)
	print("recipe demand: windows run = 33 glass + 10 aluminium -> 12 windows; furnace = 24 glass/turn; plant = 24 aluminium/turn")
	var prev: float = MatchState.money
	for t in range(1, 25):
		TurnManager.commit_turn()
		await TurnManager.turn_resolution_completed
		var m: float = MatchState.money
		var e_fur: float = _becon("r_054")
		var e_fac: float = _becon("r_056")
		print("turn %2d  REAL_net=%+7.1f | furnace_econ=%+7.1f factory_econ=%+7.1f  SUM_econ=%+7.1f  gap(sum-real)=%+7.1f | glass_stk=%d win_stk=%d" % [
			t, m - prev, e_fur, e_fac, e_fur + e_fac, (e_fur + e_fac) - (m - prev),
			Stockpile.get_at_tile(TILE, "g_038"), Stockpile.get_at_tile(TILE, "g_039")])
		if t == 23:
			print("  PRICES turn 23: glass market=%.3f  glass imputed_cost=%.3f  windows market=%.3f  aluminium market=%.3f" % [
				MarketState.get_price("g_038"), CostSolver.get_good_unit_cost("g_038"),
				MarketState.get_price("g_039"), MarketState.get_price("g_029")])
		prev = m
	print("=== steady-state net/turn is the last few 'net=' values (ignore the first ~5 ramp turns) ===")
	get_tree().quit(0)


func _becon(rid: String) -> float:
	for iid in MatchState.buildings:
		var inst: Dictionary = MatchState.buildings[iid]
		if str(inst.get("recipe_id", "")) == rid and MatchState.is_player_owned(inst):
			var rec: Dictionary = Catalog.get_recipe(rid)
			var bd: Dictionary = Catalog.get_building(str(inst.get("building_id", "")))
			return float(BuildingReadout.economics(inst, rec, bd).get("net", 0.0))
	return 0.0


func _bstate(rid: String) -> String:
	for iid in MatchState.buildings:
		var inst: Dictionary = MatchState.buildings[iid]
		if str(inst.get("recipe_id", "")) == rid and MatchState.is_player_owned(inst):
			var rec: Dictionary = Catalog.get_recipe(rid)
			return BuildingReadout.run_state(inst, rec, false)
	return "?"
