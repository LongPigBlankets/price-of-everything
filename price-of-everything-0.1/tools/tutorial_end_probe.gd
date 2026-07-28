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
# `levels` arg — same schedule as the e2e harness: L2 at t100, L3 at t150, set directly so
# the per-turn figures are the steady state of a levelled cluster, not the transition.
var _level_schedule := false
var _levels_applied := {}
# `expand`: when a tracked deposit falls to 25% of what it started at, open a replacement mine
# on the NEAREST tile whose deposit of the same ore is infinite. A finite deposit is a clock,
# and the interesting question is whether a cluster can outrun it rather than whether it dies.
const EXPAND_AT_FRACTION := 0.25
var _expand_deposits := false
var _deposit_start := {}          # "tile|token" -> yield at turn 1
var _expanded := {}               # "tile|token" -> true once replaced
var _expand_log: Array[String] = []


## Nearest tile (hex distance) whose deposit of `token` is INFINITE, i.e. untracked.
## seed_deposits skips any deposit with no quantity, so "not in deposit_remaining but present
## on the tile" is exactly what infinite means.
func _nearest_infinite(from_tile: String, token: String) -> String:
	var hm = get_tree().get_first_node_in_group("hex_map")
	if hm == null:
		return ""
	var best := ""
	var best_d := 1 << 30
	for coord in (hm.get("tiles") as Dictionary).keys():
		var td: Dictionary = (hm.get("tiles") as Dictionary)[coord]
		var tid := str(td.get("id", ""))
		if tid == "" or tid == from_tile:
			continue
		var has := false
		for dep in td.get("deposits", []):
			if str(dep).begins_with(token) and not str(dep).contains("("):
				has = true
		if not has:
			continue
		if MatchState.deposit_remaining_for(tid, token) >= 0:
			continue                       # tracked => finite, not what we are looking for
		var d := Catalog.tile_hex_distance(from_tile, tid)
		if d < best_d:
			best_d = d
			best = tid
	return best


func _expand_depleting_deposits(turn: int) -> void:
	if not _expand_deposits:
		return
	for iid in MatchState.buildings.keys():
		var inst: Dictionary = MatchState.buildings[iid]
		if not MatchState.is_player_owned(inst):
			continue
		var tid := str(inst.get("tile_id", ""))
		var recipe: Dictionary = Catalog.get_recipe(str(inst.get("recipe_id", "")))
		for outp in recipe.get("outputs", []):
			var token := str(outp.get("internal_name", ""))
			var rem := MatchState.deposit_remaining_for(tid, token)
			if rem < 0:
				continue                   # already infinite, nothing to outrun
			var key := "%s|%s" % [tid, token]
			if not _deposit_start.has(key):
				_deposit_start[key] = maxi(rem, 1)
			if _expanded.has(key):
				continue
			if float(rem) / float(_deposit_start[key]) > EXPAND_AT_FRACTION:
				continue
			var target := _nearest_infinite(tid, token)
			if target == "":
				_expand_log.append("t%d %s at %d%% — NO infinite %s deposit reachable"
					% [turn, token, int(100.0 * rem / float(_deposit_start[key])), token])
				_expanded[key] = true
				continue
			MatchState.purchase_tile_land(target, 1)
			var new_id := MatchState.add_building(str(inst.get("building_id", "")),
				str(inst.get("recipe_id", "")), target, "player_1")
			# Route the replacement to wherever the original was shipping, per output good,
			# or it mines into a warehouse nobody draws from.
			var dest := str(inst.get("output_to", ""))
			if dest != "" and dest != "market":
				for o2 in recipe.get("outputs", []):
					MatchState.set_output_stockpile_destination(str(new_id), dest, str(o2.get("good_id", "")))
			_expanded[key] = true
			_expand_log.append("t%d %s hit %d%% on %s -> opened %s on %s (infinite, %d tiles away)"
				% [turn, token, int(100.0 * rem / float(_deposit_start[key])), tid,
					str(inst.get("recipe_id", "")), target,
					Catalog.tile_hex_distance(tid, target)])


func _apply_level_schedule(turn: int) -> void:
	if not _level_schedule:
		return
	var target := 0
	if turn >= 150:
		target = 3
	elif turn >= 100:
		target = 2
	if target == 0 or _levels_applied.has(target):
		return
	_levels_applied[target] = true
	var n := 0
	for iid in MatchState.buildings.keys():
		var inst: Dictionary = MatchState.buildings[iid]
		if str(inst.get("owner", "")) != "player_1":
			continue
		if int(inst.get("level", 1)) < target:
			inst["level"] = target
			n += 1
	print("[levels] t%d: %d buildings -> L%d" % [turn, n, target])


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var arg := str(a).strip_edges()
		if arg.to_lower() == "levels":
			_level_schedule = true
		elif arg.to_lower() == "expand":
			_expand_deposits = true
		elif arg != "":
			_variant = arg
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
		_apply_level_schedule(t)
		_expand_depleting_deposits(t)
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

	_report_expansion()

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


func _report_expansion() -> void:
	if not _expand_deposits:
		return
	if true:
		print("---- deposit expansion ----")
		if _expand_log.is_empty():
			print("  nothing fell to %d%% — no expansion was needed" % int(EXPAND_AT_FRACTION * 100.0))
		for line in _expand_log:
			print("  " + line)
		for iid in MatchState.buildings.keys():
			var inst2: Dictionary = MatchState.buildings[iid]
			if not MatchState.is_player_owned(inst2):
				continue
			var t2 := str(inst2.get("tile_id", ""))
			for tok2 in ["coal", "iron_ore", "copper_ore"]:
				var r2 := MatchState.deposit_remaining_for(t2, tok2)
				if r2 >= 0:
					print("  %s %s: %d left" % [t2, tok2, r2])


func _becon_other() -> float:
	for iid in MatchState.buildings:
		var inst: Dictionary = MatchState.buildings[iid]
		if str(inst.get("recipe_id", "")) != "r_056" and MatchState.is_player_owned(inst):
			var rec: Dictionary = Catalog.get_recipe(str(inst.get("recipe_id", "")))
			var bd: Dictionary = Catalog.get_building(str(inst.get("building_id", "")))
			return float(BuildingReadout.economics(inst, rec, bd).get("net", 0.0))
	return 0.0
