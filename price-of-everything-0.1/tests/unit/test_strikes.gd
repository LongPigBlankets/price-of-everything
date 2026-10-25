extends "res://tests/test_base.gd"
## Phase 3 of docs/pacing-labour-mining-licensing-spec.md: strikes, pay rises and accidents
## (scripts/labour_unrest.gd). Each test names the acceptance criteria (AC…) it checks.

const FEATURE := "strikes"
const TAGS := {
	"_test_strike_telemetry": ["strikes", "telemetry"],
	"_test_strike_save_round_trip": ["strikes", "save"],
	"_test_strikes_tab_and_diagnostics": ["strikes", "ui", "people"],
}

const MINE := "b_001"
const FURNACE := "b_002"
const POWER := "b_003"
const FACTORY := "b_007"
const LabourUnrest := preload("res://scripts/labour_unrest.gd")
const PeopleDs2 := preload("res://scripts/people_ds2/people_ds2.gd")


func _fresh(satisfaction: float = 0.0) -> void:
	Modifiers.reset()
	MatchState.reset()
	Stockpile.clear_all()
	TurnManager.current_turn = 1
	LabourState.satisfaction = satisfaction


func _u() -> LabourUnrest:
	return LabourState.unrest


## A company of `count` buildings, alternating hazardous furnaces and plain factories, on one tile.
func _company(count: int) -> Array:
	var out: Array = []
	BuildingState.tile_land_owned["tile_9_9"] = 2000
	for i in count:
		var bid := FURNACE if i % 2 == 0 else FACTORY
		out.append(BuildingState.add_building(bid, "r_005" if bid == FURNACE else "r_056", "tile_9_9", MatchState.LOCAL_PLAYER, ""))
	return out


## Runs the unrest tick for `turn` as the turn does (TurnManager on that turn, so timed modifiers expire right).
func _tick(turn: int) -> void:
	TurnManager.current_turn = turn
	_u().tick(turn)


func _shift(id_prefix: String) -> float:
	var total := 0.0
	for s: Dictionary in LabourState.target_shifts:
		if str(s.get("id", "")).begins_with(id_prefix):
			total += float(s.get("value", 0.0))
	return total


## AC12.1: the warning is drawn in the resolution of T−3 below −70, a quarter of N (half below −90); N counts the
## company's production and power buildings only.
func _test_strike_warning_and_size() -> void:
	var sizes_ok := true
	for n in range(1, 21):
		sizes_ok = sizes_ok and _u().strike_size(n, false) == ceili(n * 0.25) and _u().strike_size(n, true) == ceili(n * 0.5)
	_check(sizes_ok, "AC12.1 strike size is ceil(25% of N), ceil(50% below −90), for N 1 to 20")
	_fresh(-80.0)
	var iids := _company(6)
	BuildingState.add_building(FURNACE, "r_005", "tile_9_9", "npc_test", "")
	BuildingState.add_building("b_028", "r_040", "tile_9_9", MatchState.LOCAL_PLAYER, "")
	BuildingWorks.set_building_paused(str(iids[5]), true)
	_check(_u().eligible_buildings().size() == 5, "AC12.1 N leaves out NPC, battery and paused buildings (N=%d)" % _u().eligible_buildings().size())
	_tick(6)
	_check(_u().warning.is_empty(), "AC12.1 no warning outside the T−3 resolution")
	_tick(7)
	_check(int(_u().warning.get("turn", 0)) == 10 and (_u().warning.buildings as Array).size() == 2
		and not bool(_u().warning.heavy), "AC12.1 below −70 the turn 7 resolution names ceil(25% of 5) = 2 for turn 10")
	_fresh(-95.0)
	_company(6)
	_tick(17)
	_check((_u().warning.buildings as Array).size() == 3 and bool(_u().warning.heavy), "AC12.1 below −90 half the company is named")
	_fresh(-60.0)
	_company(6)
	_tick(27)
	_check(_u().warning.is_empty(), "AC12.1 at −70 or above nobody is named")
	_fresh()


## AC12.2: a weighted, seeded draw: the same seed gives the same names; hazardous ×2 under Minimal safety,
## an accident in the last 10 turns ×2; a building under a pay rise is never named.
func _test_strike_draw_is_weighted_and_seeded() -> void:
	_fresh(-80.0)
	var iids := _company(8)
	MatchState.match_rng_seed = 4242
	_u().reset()
	var first := _u().draw(_u().eligible_buildings(), 3, 10)
	_u().reset()
	var again := _u().draw(_u().eligible_buildings(), 3, 10)
	_check(first == again and first.size() == 3, "AC12.2 the same seed draws the same buildings (%s)" % str(first))
	var furnace := str(iids[0])
	var factory := str(iids[1])
	_check(is_equal_approx(_u().strike_weight(furnace, 10), 1.0) and is_equal_approx(_u().strike_weight(factory, 10), 1.0),
		"AC12.2 every building weighs 1 under standard safety")
	LabourState.set_workforce_policy_enabled(LabourState.WORKFORCE_POLICY_LAX_SAFETY, true)
	_u().accident_turns[furnace] = 5
	_u().accident_turns[factory] = 5
	_check(is_equal_approx(_u().strike_weight(furnace, 10), 4.0) and is_equal_approx(_u().strike_weight(factory, 10), 2.0)
		and is_equal_approx(_u().strike_weight(factory, 16), 1.0), "AC12.2 hazardous ×2 under Minimal safety, a recent accident ×2")
	_u().pay_raises[furnace] = 5
	LabourState.satisfaction = -95.0
	_tick(7)
	_check(not (_u().warning.get("buildings", []) as Array).has(furnace), "AC12.2 a building under a pay rise is never named")
	_fresh()


## AC12.3–AC12.5: at T the named buildings strike below −70, or only the first quarter when a −90 warning eased to
## −70…−90, or it is called off at −70 and above. A strike halves output (power too) for T, T+1 and T+2, consumes
## full inputs, charges a deposit in full and halves labour; one that runs out lifts the target 5.
func _test_strike_effect_and_end() -> void:
	_fresh(-80.0)
	LabourState.policy_throughput_enabled = false
	var iids := _company(4)
	_tick(7)
	var named: Array = _u().warning.buildings
	var iid := str(named[0])
	var b := BuildingState.get_building(iid)
	var recipe := Catalog.get_recipe(str(b.recipe_id))
	var out0 := BuildingStatus.effective_output_qty(b, recipe)
	var in0 := Production._scaled_input_qty(recipe.inputs[0], b)
	_tick(10)
	_check(_u().is_on_strike(iid) and _u().warning.is_empty() and str((_u().record.back() as Dictionary).outcome) == "struck",
		"AC12.3 below −70 at T the named buildings strike")
	_check(BuildingStatus.effective_output_qty(b, recipe) == int(round(float(out0) * 0.5))
		and Production._scaled_input_qty(recipe.inputs[0], b) == in0, "AC12.4 a strike halves output and keeps inputs in full")
	var unstruck := Production._base_labour_cost(b, recipe) * Production.labour_cost_factor(b)
	_check(is_equal_approx(Production._calculate_labour_cost(b, recipe), unstruck * 0.5), "AC12.4 struck labour costs half")
	var expires := -1
	for m: Dictionary in Modifiers.active():
		if str(m.get("id", "")) == "strike_%s" % iid:
			expires = int(m.get("expires_turn", 0))
	_check(expires == 12, "AC12.4 the strike's output modifier lasts turns 10, 11 and 12 (expires %d)" % expires)
	_tick(11)
	_tick(12)
	_check(_u().is_on_strike(iid) and is_zero_approx(_shift("strike_over")), "AC12.5 still on strike through turn 12")
	_tick(13)
	_check(not _u().is_on_strike(iid) and is_equal_approx(_shift("strike_over"), 5.0), "AC12.5 a strike that runs out lifts the target 5")
	# Power plants are halved too.
	_fresh()
	var plant_iid := BuildingState.add_building(POWER, "r_004", "tile_9_9", MatchState.LOCAL_PLAYER, "")
	var plant := BuildingState.get_building(plant_iid)
	var power0 := Production._effective_power_output(plant, Catalog.get_recipe("r_004"))
	_u().active[plant_iid] = 3
	Modifiers.add({"id": "strike_%s" % plant_iid, "domain": "recipe_output", "target": "*", "target_match": {"instance_id": plant_iid},
		"mult": 0.5, "duration_turns": 3, "source": "strike"})
	_check(Production._effective_power_output(plant, Catalog.get_recipe("r_004")) == int(round(float(power0) * 0.5)),
		"AC12.4 a struck power plant makes half its power")
	# A struck mine still charges its deposit in full.
	_fresh()
	var tile := "tile_6_8"
	var mine_iid: String = BuildingState.add_building(MINE, "r_001", tile)
	MatchState.reveal_deposit(tile, "coal")
	MatchState.deposit_remaining[tile] = {"coal": 999}
	var mine := BuildingState.get_building(mine_iid)
	Production._produce_outputs(mine, Catalog.get_recipe("r_001"), _fresh_production_summary())
	Production._flush_output_buffer()
	var draw0 := 999 - MatchState.deposit_remaining_for(tile, "coal")
	MatchState.deposit_remaining[tile] = {"coal": 999}
	Modifiers.add({"id": "strike_%s" % mine_iid, "domain": "recipe_output", "target": "*", "target_match": {"instance_id": mine_iid},
		"mult": 0.5, "duration_turns": 3, "source": "strike"})
	Production._produce_outputs(mine, Catalog.get_recipe("r_001"), _fresh_production_summary())
	Production._flush_output_buffer()
	_check(999 - MatchState.deposit_remaining_for(tile, "coal") == draw0, "AC12.4 a struck mine charges its deposit in full")
	# Called off, and the eased heavy warning.
	_fresh(-80.0)
	_company(4)
	_tick(7)
	LabourState.satisfaction = -60.0
	_tick(10)
	_check(_u().active.is_empty() and str((_u().record.back() as Dictionary).outcome) == "called off",
		"AC12.3 at −70 or above at T the strike is called off")
	_fresh(-95.0)
	_company(8)
	_tick(7)
	_check((_u().warning.buildings as Array).size() == 4, "AC12.3 the −90 warning names half")
	LabourState.satisfaction = -80.0
	_tick(10)
	_check(_u().active.size() == 2, "AC12.3 eased to −80 by T, only the first quarter strike (%d)" % _u().active.size())
	LabourState.policy_throughput_enabled = false
	_fresh()


## AC12.6: no warning under a union agreement, and a standing warning is called off at T.
func _test_union_blocks_strikes() -> void:
	_fresh(-80.0)
	_company(4)
	LabourState.set_union_tier(LabourState.UNION_PARTIAL)
	LabourState.satisfaction = -80.0
	_tick(7)
	_check(_u().warning.is_empty(), "AC12.6 a union agreement means no warning")
	LabourState.set_union_tier(LabourState.UNION_NONE)
	LabourState.target_shifts.clear()
	LabourState.satisfaction = -80.0
	_tick(17)
	_check(not _u().warning.is_empty(), "AC12.6 without it the warning is drawn")
	LabourState.set_union_tier(LabourState.UNION_COMPREHENSIVE)
	LabourState.satisfaction = -80.0
	_tick(20)
	_check(_u().active.is_empty() and str((_u().record.back() as Dictionary).outcome) == "called off",
		"AC12.6 signing a union before T calls the strike off")
	_fresh()


## AC13.1–AC13.3: raising pay at one building takes it out of the warning or ends its strike, +20% labour there for
## 10 turns; raising it for all ends every strike and keeps strikes away for 15 turns; neither moves satisfaction.
func _test_pay_rises() -> void:
	_fresh(-80.0)
	_company(8)
	_tick(7)
	var named: Array = (_u().warning.buildings as Array).duplicate()
	var first := str(named[0])
	var b := BuildingState.get_building(first)
	var factor0 := LabourState.labour_cost_factor_for(b)
	var target0 := LabourState.target_satisfaction()
	_check(_u().raise_pay(first) and not _u().is_named(first) and int(_u().pay_raises[first]) == 10,
		"AC13.1 a pay rise takes the building out of the warning for 10 turns")
	_check(is_equal_approx(LabourState.labour_cost_factor_for(b) - factor0, 0.20), "AC13.1 its labour is 20% higher")
	_check(is_equal_approx(LabourState.target_satisfaction(), target0) and is_equal_approx(LabourState.satisfaction, -80.0),
		"AC13.3 a pay rise moves neither satisfaction nor its target")
	_tick(10)
	var striking := str(_u().active.keys()[0])
	_check(not _u().is_on_strike(first), "AC13.1 the raised building does not strike")
	_check(_u().raise_pay(striking) and not _u().is_on_strike(striking) and is_zero_approx(_shift("strike_over")),
		"AC13.1 raising pay ends a strike at once, with no +5")
	var mod_left := false
	for m: Dictionary in Modifiers.active():
		mod_left = mod_left or str(m.get("id", "")) == "strike_%s" % striking
	_check(not mod_left, "AC13.1 its output is whole again")
	_fresh(-80.0)
	_company(8)
	_tick(7)
	_tick(10)
	_check(not _u().active.is_empty(), "AC13.2 setup: strikes on")
	_check(_u().raise_pay_all(10) and _u().active.is_empty() and _u().warning.is_empty() and _u().strike_free_until == 25,
		"AC13.2 raising pay for all ends every strike and protects to turn 25")
	_tick(17)
	_check(_u().warning.is_empty(), "AC13.2 no warning while protected")
	_check(is_zero_approx(_shift("strike_over")), "AC13.3 strikes ended by pay rises give no +5")
	_fresh()


## AC14.1, AC14.2: accidents under Minimal safety only, at hazardous buildings: 2% rising 0.25 points a turn to 6%,
## reset when safety changes; an accident stops the building 2 turns, shifts the target −10 and charges 2 turns of
## wages.
func _test_accidents() -> void:
	_fresh()
	var iids := _company(4)
	_check(is_zero_approx(_u().accident_chance()), "AC14.1 no accidents without Minimal safety")
	LabourState.set_workforce_policy_enabled(LabourState.WORKFORCE_POLICY_LAX_SAFETY, true)
	_check(is_equal_approx(_u().accident_chance(), 0.02), "AC14.1 2% when Minimal safety starts")
	_u().minimal_safety_turns = 8
	_check(is_equal_approx(_u().accident_chance(), 0.04), "AC14.1 4% after 8 turns of it")
	_u().minimal_safety_turns = 40
	_check(is_equal_approx(_u().accident_chance(), 0.06), "AC14.1 capped at 6%")
	LabourState.set_workforce_policy_enabled(LabourState.WORKFORCE_POLICY_LAX_SAFETY, false)
	_tick(2)
	_check(_u().minimal_safety_turns == 0, "AC14.1 the ramp resets when safety changes")
	LabourState.set_workforce_policy_enabled(LabourState.WORKFORCE_POLICY_LAX_SAFETY, true)
	# A long run: accidents land, and only at the hazardous furnaces.
	MatchState.match_rng_seed = 99
	_u().reset()
	var hit: Dictionary = {}
	for turn in range(3, 80):
		_tick(turn)
		for iid in _u().accident_down:
			hit[iid] = true
	var only_hazardous := true
	for iid in hit:
		only_hazardous = only_hazardous and str(BuildingState.get_building(str(iid)).building_id) == FURNACE
	_check(not hit.is_empty() and only_hazardous, "AC14.1 accidents happen, and only at hazardous buildings (%d hit)" % hit.size())
	# One accident, checked whole.
	_fresh()
	LabourState.set_workforce_policy_enabled(LabourState.WORKFORCE_POLICY_LAX_SAFETY, true)
	var furnace := str(_company(2)[0])
	var b := BuildingState.get_building(furnace)
	MatchState.one_off_charges.clear()
	TurnManager.current_turn = 30
	var wages := Production._calculate_labour_cost(b)
	_u()._accident(furnace, b, 30)
	_check(_u().is_down(furnace) and is_equal_approx(_shift("accident_"), -10.0), "AC14.2 an accident stops the building and shifts the target −10")
	_check(MatchState.one_off_charges.size() == 1 and is_equal_approx(float(MatchState.one_off_charges[0].amount), wages * 2.0),
		"AC14.2 compensation is 2 turns of its wages")
	Production._process_production()
	_check(str((Production.blocked_reason_by_building.get(furnace, {}) as Dictionary).get("code", "")) == "accident"
		and not Production.last_turn_run.has(furnace), "AC14.2 it does not run while down")
	_u()._age(_u().accident_down)
	_check(_u().is_down(furnace), "AC14.2 still down the next turn")
	_u()._age(_u().accident_down)
	_check(not _u().is_down(furnace), "AC14.2 back after 2 turns")
	_fresh()


## AC15.1: the unrest state round-trips a save; an older save loads quiet.
func _test_strike_save_round_trip() -> void:
	_fresh(-80.0)
	_company(4)
	_tick(7)
	_tick(10)
	var striking := str(_u().active.keys()[0])
	_u().pay_raises["x"] = 4
	_u().accident_down["y"] = 1
	_u().accident_turns["y"] = 9
	_u().minimal_safety_turns = 6
	var snap: Dictionary = MatchState.export_state()
	for key in ["strike_warning", "strike_active", "strike_record", "strike_pay_raises", "strike_free_until",
			"accident_down", "accident_turns", "accident_minimal_turns", "labour_rng_seed", "labour_rng_state"]:
		_check(snap.has(key), "AC15.1 the save carries %s" % key)
	var state := _u().export_fields()
	var pool := _u().eligible_buildings()
	var next := _u().draw(pool, 2, 20)
	MatchState.reset()
	_check(_u().active.is_empty() and _u().record.is_empty(), "AC15.1 reset clears the unrest")
	_u().import_fields(state)
	_check(_u().is_on_strike(striking) and int(_u().pay_raises.x) == 4 and _u().is_down("y") and _u().minimal_safety_turns == 6,
		"AC15.1 a load restores strikes, raises and accidents")
	_check(_u().draw(pool, 2, 20) == next, "AC15.1 the labour RNG continues where it was")
	var legacy := {}
	_u().import_fields(legacy)
	_check(_u().active.is_empty() and _u().warning.is_empty() and _u().strike_free_until == 0, "AC15.1 an older save loads quiet")
	_check(FileAccess.get_file_as_string("res://scripts/save_validation.gd").contains("\"strike_active\""), "AC15.1 the validator knows the fields")
	_fresh()


## AC15.2: telemetry schema 7 carries the buildings on strike in each turn row and transmits them.
func _test_strike_telemetry() -> void:
	_fresh()
	_u().active = {"a": 2, "b": 1}
	var summary := {
		"money_in": 0.0, "money_out": 0.0,
		"goods_sales_revenue": 0.0, "power_sales_revenue": 0.0,
		"goods_purchased_cost": 0.0, "labour_paid": 0.0, "maintenance_paid": 0.0,
		"taxes_paid": 0.0, "produced": {}, "power_supply": 0, "power_demand": 0,
	}
	var row: Dictionary = TelemetryState._build_row(summary)
	_check(int(row.get("strikes", -1)) == 2, "AC15.2 the turn row counts buildings on strike")
	_check(int(TelemetryState.balancing_payload({"run_id": "s7", "turns": [row]}).turns[0].strikes) == 2,
		"AC15.2 the transmitted report keeps it")
	_check(TelemetryState.SCHEMA_VERSION == 7, "AC15.2 schema 7")
	_fresh()


## AC16.1–AC16.3: the Strikes tab, its key lamp and the diagnostics rows.
func _test_strikes_tab_and_diagnostics() -> void:
	_fresh(-80.0)
	var iids := _company(4)
	_tick(7)
	var shell: Control = PeopleDs2.new()
	add_child(shell)
	await get_tree().process_frame
	_check(PeopleDs2.TABS == ["Advisors", "Labour", "Strikes"], "AC16.1 People has a Strikes tab")
	shell.call("show_tab", 2)
	await get_tree().process_frame
	var tab: Control = shell.call("body", 2)
	tab.call("_rebuild")
	_check(tab.find_child("WarningBoard", true, false) != null and tab.find_child("RaisePayAll", true, false) != null,
		"AC16.1 a warning shows its board and the key to raise pay for all")
	var named := str((_u().warning.buildings as Array)[0])
	_check(tab.find_child("RaisePay_%s" % named, true, false) != null, "AC16.1 each named building has its own key")
	shell.call("_refresh_key_lamps")
	var keys: Array = shell.get("_keys")
	_check((keys[2].get("lamp") as Color).a > 0.0, "AC16.2 the Strikes key's lamp lights during a warning")
	var rows: Array = BuildingReadout.diagnostics(BuildingState.get_building(named), Catalog.get_recipe("r_005"), Catalog.get_building(FURNACE), false)
	var warned := false
	for r: Dictionary in rows:
		warned = warned or str(r.get("label", "")) == "Strike warning"
	_check(warned, "AC16.3 the diagnostics say the building is named to strike")
	_tick(10)
	tab.call("_rebuild")
	_check(tab.find_child("OnStrike", true, false) != null and tab.find_child("StrikeRecord", true, false) != null,
		"AC16.1 strikes on show the buildings on strike and the record")
	var striking := str(_u().active.keys()[0])
	var on := false
	for r: Dictionary in BuildingReadout.diagnostics(BuildingState.get_building(striking), Catalog.get_recipe(str(BuildingState.get_building(striking).recipe_id)), Catalog.get_building(str(BuildingState.get_building(striking).building_id)), false):
		on = on or str(r.get("label", "")) == "On strike"
	_check(on, "AC16.3 the diagnostics say the building is on strike")
	shell.queue_free()
	_fresh()
