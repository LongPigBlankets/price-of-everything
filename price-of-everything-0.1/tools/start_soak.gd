extends Node
## Plays a start for N real turns and reports whether it runs as a business: every starting
## building producing, cash reconciling each turn, solvency, fees and the steady profit that
## the New Game card quotes. Research, events and random decisions are off so runs repeat.
##
## Usage (headless):
##   <godot> --headless --path . res://tools/start_soak.tscn -- --start=res://data/starts/metal_magnate.json [--turns=50]
## Writes /tmp/start-soak/<start name>.json and prints START_SOAK <json>.
const Paths := preload("res://scripts/app_paths.gd")
const Service := preload("res://scripts/middleman_service.gd")
const OUT := "/tmp/start-soak"

var failures: Array = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)

func _arg(name: String, fallback: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--" + name + "="):
			return arg.trim_prefix("--" + name + "=")
	return fallback

func _enter_tree() -> void:
	Paths._base = OUT + "/runtime"
	RunMetrics.enabled = false
	TelemetryState.enabled = false

func _ready() -> void:
	var start_path := _arg("start", "res://data/starts/metal_magnate.json")
	var turns := int(_arg("turns", "50"))
	preload("res://tools/shot_harness.gd").arm_watchdog(self, 600.0)
	AudioServer.set_bus_mute(0, true)
	SaveLoad.autosave_enabled = false
	SaveLoad.prepare_new_game(start_path, {"ruleset": {"tutorial_enabled": false}})
	var world: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(world)
	await get_tree().process_frame
	get_tree().current_scene = world
	for frame in 180: await get_tree().process_frame
	TurnManager.fast_mode = true
	for system in [ResearchState, EventScheduler, DecisionState]:
		var hook := Callable(system, "_on_phase_started")
		if TurnManager.phase_started.is_connected(hook): TurnManager.phase_started.disconnect(hook)
	DecisionState.enabled = false
	DecisionState.auto_resolve = true

	var starting: Array = BuildingState.buildings.values().filter(func(b: Dictionary) -> bool: return BuildingState.is_player_owned(b))
	var ids: Array = starting.map(func(b: Dictionary) -> String: return str(b.instance_id))
	var service_ids: Array = ids.filter(func(iid: String) -> bool: return Service.enabled(iid))
	var coefficients := {}
	for b: Dictionary in starting:
		coefficients[str(b.tile_id)] = preload("res://scripts/middleman_locations.gd").coefficient(str(b.tile_id))
	var rows: Array = []
	var idle_turns := {}
	for turn in range(1, turns + 1):
		var before := MatchState.money
		TurnManager.commit_turn()
		await TurnManager.turn_resolution_completed
		for frame in 2: await get_tree().process_frame
		var s: Dictionary = Production.last_turn_summary.duplicate(true)
		check(absf(MatchState.money - before - Production.cash_change_of(s)) < 0.0001, "cash reconciles turn %d" % turn)
		check(MatchState.money >= 0.0, "solvent turn %d" % turn)
		var idle: Array = []
		for iid: String in ids:
			if Production.blocked_reason_by_building.has(iid) or Production.missing_by_building.has(iid):
				idle.append(iid)
				idle_turns[iid] = int(idle_turns.get(iid, 0)) + 1
		var debt := 0.0
		for loan: Dictionary in LoanState.loans:
			debt += float(loan.get("principal_remaining", 0.0))
		rows.append({
			"turn": turn, "cash": MatchState.money, "cash_change": MatchState.money - before,
			"pre_tax_profit": float(s.get("pre_tax_profit", 0.0)),
			"revenue": float(s.get("goods_sales_revenue", 0.0)),
			"purchases": float(s.get("goods_purchased_cost", 0.0)),
			"middleman_fee": float(s.get("middleman_fee", 0.0)),
			"labour": float(s.get("labour_paid", 0.0)), "maintenance": float(s.get("maintenance_paid", 0.0)),
			"power": float(s.get("power_purchase_cost", 0.0)), "warehousing": float(s.get("warehousing_paid", 0.0)),
			"produced": s.get("produced", {}), "idle": idle, "debt": debt,
			"stock": Stockpile.get_all_totals(),
		})
	check(service_ids.size() == ids.size(), "every starting building joined the intermediary")
	# A mine whose finite deposit runs out stops by design; report it, do not fail on it.
	var depleted := {}
	for b: Dictionary in starting:
		var token: String = Production._recipe_deposit_token(Catalog.get_recipe(str(b.recipe_id)))
		if token != "" and MatchState.deposit_depleted(str(b.tile_id), token):
			depleted[str(b.instance_id)] = token
	for iid: String in ids:
		if not depleted.has(iid):
			check(int(idle_turns.get(iid, 0)) <= 1, "%s produced on all but at most one turn" % iid)

	var mean := func(key: String, first: int, last: int) -> float:
		var picked := rows.filter(func(r: Dictionary) -> bool: return int(r.turn) >= first and int(r.turn) <= last)
		var total := 0.0
		for r: Dictionary in picked: total += float(r[key])
		return total / maxf(1.0, float(picked.size()))
	var reasons := {}
	for iid: String in ids:
		reasons[iid] = str(Production.blocked_reason_by_building.get(iid, ""))
	var report := {
		"status": "passed" if failures.is_empty() else "failed", "failures": failures,
		"start": start_path, "turns": turns, "starting_cash": float(rows[0].cash) - float(rows[0].cash_change),
		"buildings": ids.size(), "service_buildings": service_ids.size(), "coefficients": coefficients,
		"idle_turns": idle_turns, "depleted": depleted, "last_blocked_reasons": reasons,
		"steady_profit_turns_6_15": mean.call("pre_tax_profit", 6, 15),
		"cash_change_turns_6_15": mean.call("cash_change", 6, 15),
		"cash_change_turns_40_49": mean.call("cash_change", 40, 49),
		"fee_turns_6_15": mean.call("middleman_fee", 6, 15),
		"min_cash": rows.map(func(r: Dictionary) -> float: return float(r.cash)).min(),
		"final_cash": float(rows[-1].cash), "final_debt": float(rows[-1].debt),
		"rows": rows,
	}
	var name := start_path.get_file().get_basename()
	DirAccess.make_dir_recursive_absolute(OUT)
	var file := FileAccess.open(OUT + "/" + name + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	var brief := report.duplicate()
	brief.erase("rows")
	print("START_SOAK ", JSON.stringify(brief))
	get_tree().quit(0 if failures.is_empty() else 1)
