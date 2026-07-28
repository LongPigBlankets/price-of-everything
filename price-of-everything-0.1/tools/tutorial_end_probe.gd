extends Node
## Ground-truth P&L probe for the state a player is left in AFTER finishing the tutorial.
## Seeds the tutorial's end board (window factory + the integration building, co-located on
## tile_5_9, sell-surplus on) and runs turns printing the REAL per-turn money delta plus the
## full turn-summary money breakdown, so a -£X/turn steady state can be attributed to a line.
##
##   <godot> --headless --path . res://tools/tutorial_end_probe.tscn --quit-after 9000 ++ glass54
## variants: glass54 (optimal glass path) | glass53 | alu | buyall | rich

const MAIN_SCENE := "res://scenes/main.tscn"
const BuildingReadout := preload("res://scripts/building_readout.gd")
const TILE := "tile_5_9"
const EXTRA_SELL_TILES := ["tile_5_10"]
const TURNS := 300

var _main: Node = null
var _started := false
var _frames := 0
var _variant := "glass54"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if str(a).strip_edges() != "":
			_variant = str(a).strip_edges()
	SaveLoad.prepare_new_game("res://data/starts/_tut_end_%s.json" % _variant)
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	add_child(_main)


func _process(_dt: float) -> void:
	if _started:
		return
	_frames += 1
	if _main != null and _main.get("build_complete") == true:
		_started = true
		_run()
	elif _frames > 6000:
		printerr("world never built")
		get_tree().quit(1)


func _run() -> void:
	TurnManager.fast_mode = true
	TurnManager.phase_pause_duration = 0.0
	MatchState.enable_sell_surplus(TILE)
	for t in EXTRA_SELL_TILES:
		MatchState.enable_sell_surplus(str(t))
	print("=== TUTORIAL-END PROBE  variant=%s  tile=%s  sell-surplus ON  start money=%.0f ===" % [
		_variant, TILE, MatchState.money])
	for iid in MatchState.buildings:
		var inst: Dictionary = MatchState.buildings[iid]
		if MatchState.is_player_owned(inst):
			print("  seeded: %s / %s on %s" % [inst.get("building_id"), inst.get("recipe_id"), inst.get("tile_id")])
	var prev: float = MatchState.money
	for t in range(1, TURNS + 1):
		TurnManager.commit_turn()
		await TurnManager.turn_resolution_completed
		var m: float = MatchState.money
		var s: Dictionary = Production.last_turn_summary
		var real: float = m - prev
		print("t%-3d REAL=%+8.2f cash=%9.1f | sales=%7.2f pwrSell=%5.2f || inputs=%7.2f pwr=%6.2f labour=%6.2f maint=%5.2f trans=%5.2f whse=%5.2f tax=%5.2f div=%5.2f int=%5.2f co2=%5.2f | econ(fac/oth)=%+6.1f/%+6.1f" % [
			t, real, m,
			_f(s, "goods_sales_revenue"), _f(s, "power_sales_revenue"),
			_f(s, "goods_purchased_cost"), _f(s, "power_purchase_cost"),
			_f(s, "labour_paid"), _f(s, "maintenance_paid"), _f(s, "transport_paid"),
			_f(s, "warehousing_paid"), _f(s, "taxes_paid"), _f(s, "dividends_paid"),
			_f(s, "interest_paid"), _f(s, "carbon_tax_paid"),
			_becon("r_056"), _becon_other()])
		var dro: Array = s.get("deposits_running_out", [])
		if not dro.is_empty():
			var d0: Dictionary = dro[0]
			print("     ^ DEPOSIT WARNING: %s on %s — %d turns left (%d units @ %d/turn)" % [
				str(d0.get("token","")), str(d0.get("tile_id","")), int(d0.get("turns_left",0)),
				int(d0.get("remaining",0)), int(d0.get("per_turn",0))])
		if t == TURNS or t == 20:
			_deep_report(t, s)
		prev = m
	print("=== steady state = the last ~10 REAL values ===")
	get_tree().quit(0)


func _f(s: Dictionary, k: String) -> float:
	return float(s.get(k, 0.0))


func _deep_report(t: int, s: Dictionary) -> void:
	print("  -- deep report turn %d --" % t)
	print("     produced=%s" % [s.get("produced", {})])
	print("     consumed=%s" % [s.get("consumed", {})])
	print("     sold=%s" % [s.get("sold", {})])
	print("     purchased=%s" % [s.get("purchased", {})])
	print("     purchased_cost=%s" % [s.get("purchased_cost", {})])
	print("     starved=%s" % [s.get("starved", [])])
	print("     input_orders_short=%s" % [s.get("input_orders_short", [])])
	print("     input_orders_capped=%s" % [s.get("input_orders_capped", [])])
	print("     input_splices=%s" % [s.get("input_splices", [])])
	print("     labour_by_type=%s" % [s.get("labour_by_type", {})])
	print("     power supply=%d demand=%d bought=%d sold=%d" % [
		int(s.get("power_supply", 0)), int(s.get("power_demand", 0)),
		int(s.get("grid_bought", 0)), int(s.get("grid_sold", 0))])
	print("     tile stock=%s" % [Stockpile.get_tile_totals(TILE)])
	for gid in ["g_038", "g_039", "g_029"]:
		print("     price %s (%s) = %.3f (base %.3f)" % [
			gid, Catalog.get_internal_name(gid), MarketState.get_price(gid),
			float(Catalog.get_good(gid).get("base_price", 0.0))])
	for iid in MatchState.buildings:
		var inst: Dictionary = MatchState.buildings[iid]
		if not MatchState.is_player_owned(inst):
			continue
		var rid := str(inst.get("recipe_id", ""))
		var rec: Dictionary = Catalog.get_recipe(rid)
		var bd: Dictionary = Catalog.get_building(str(inst.get("building_id", "")))
		var e: Dictionary = BuildingReadout.economics(inst, rec, bd)
		print("     [%s/%s] state=%s econ=%s" % [
			inst.get("building_id"), rid, BuildingReadout.run_state(inst, rec, false), e])
		print("        missing=%s blocked=%s" % [
			Production.missing_by_building.get(str(inst.get("instance_id", "")), {}),
			Production.blocked_reason_by_building.get(str(inst.get("instance_id", "")), "")])


func _becon(rid: String) -> float:
	for iid in MatchState.buildings:
		var inst: Dictionary = MatchState.buildings[iid]
		if str(inst.get("recipe_id", "")) == rid and MatchState.is_player_owned(inst):
			var rec: Dictionary = Catalog.get_recipe(rid)
			var bd: Dictionary = Catalog.get_building(str(inst.get("building_id", "")))
			return float(BuildingReadout.economics(inst, rec, bd).get("net", 0.0))
	return 0.0


func _becon_other() -> float:
	for iid in MatchState.buildings:
		var inst: Dictionary = MatchState.buildings[iid]
		if str(inst.get("recipe_id", "")) != "r_056" and MatchState.is_player_owned(inst):
			var rec: Dictionary = Catalog.get_recipe(str(inst.get("recipe_id", "")))
			var bd: Dictionary = Catalog.get_building(str(inst.get("building_id", "")))
			return float(BuildingReadout.economics(inst, rec, bd).get("net", 0.0))
	return 0.0
