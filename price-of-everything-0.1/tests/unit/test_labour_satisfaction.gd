extends "res://tests/test_base.gd"
## Phase 1 of docs/pacing-labour-mining-licensing-spec.md: throughput as a bonus type, the labour
## knobs, labour satisfaction, the union tiers with the Comprehensive halving, step-downs and
## renege. Each test names the acceptance criteria (AC…) it checks.

const FEATURE := "labour"
const TAGS := {
	"_test_throughput_scales_inputs_outputs_and_power": ["labour", "production"],
	"_test_recipe_input_modifier_scales_inputs": ["labour", "production"],
	"_test_previews_match_production": ["labour", "production"],
	"_test_save_round_trip_and_migration": ["labour", "save"],
}

const FURNACE := "b_002"     # hazardous
const FACTORY := "b_007"     # not hazardous
const MINE := "b_001"
const SaveValidationScript := preload("res://scripts/save_validation.gd")
const HAZARDOUS := ["b_001", "b_002", "b_003", "b_008", "b_011", "b_012", "b_013", "b_032", "b_033", "b_034"]


func _fresh() -> void:
	Modifiers.reset()
	MatchState.reset()
	LabourState.policy_throughput_enabled = true
	TurnManager.current_turn = 1


func _furnace() -> Dictionary:
	BuildingState.tile_land_owned["tile_9_9"] = 200
	var iid := BuildingState.add_building(FURNACE, "r_005", "tile_9_9", MatchState.LOCAL_PLAYER, "")
	return BuildingState.buildings[iid]


func _part(id: String) -> float:
	for p in LabourState.satisfaction_contributions():
		if str(p.id) == id:
			return float(p.value)
	return 0.0


func _labour_delta(building: Dictionary) -> float:
	return LabourState.labour_cost_factor_for(building) - 1.0


## AC1.1, AC1.2: throughput scales every input, every output and the power draw by the same factor;
## labour and maintenance stay put. run_multiplier is the one scale.
func _test_throughput_scales_inputs_outputs_and_power() -> void:
	_fresh()
	LabourState.policy_throughput_enabled = false
	var b := _furnace()
	var recipe: Dictionary = Catalog.get_recipe("r_005")
	var in0: Array = []
	for input in recipe.get("inputs", []):
		in0.append(Production._scaled_input_qty(input, b))
	var out0 := BuildingStatus.effective_output_qty(b, recipe)
	var power0 := Production._effective_energy_req(b, recipe)
	var labour0 := Production._calculate_labour_cost(b, recipe)
	var maint0 := Production._calculate_maintenance_cost(b)
	Modifiers.add({"id": "test_tp", "domain": "throughput", "target": "*", "target_match": {"building_id": FURNACE}, "pct": 20.0})
	_check(is_equal_approx(MatchState.run_multiplier(b), 1.2), "AC1.2 run multiplier carries a +20% throughput modifier")
	var ok_in := true
	var i := 0
	for input in recipe.get("inputs", []):
		ok_in = ok_in and Production._scaled_input_qty(input, b) == int(round(float(in0[i]) * 1.2))
		i += 1
	_check(ok_in, "AC1.1 throughput scales every input")
	_check(BuildingStatus.effective_output_qty(b, recipe) == int(round(float(out0) * 1.2)), "AC1.1 throughput scales outputs")
	_check(Production._effective_energy_req(b, recipe) == int(round(float(power0) * 1.2)), "AC1.1 throughput scales the power draw")
	_check(is_equal_approx(Production._calculate_labour_cost(b, recipe), labour0)
		and is_equal_approx(Production._calculate_maintenance_cost(b), maint0), "AC1.1 throughput leaves labour and maintenance alone")
	Modifiers.remove("test_tp")
	_fresh()


## AC1.3: a recipe_input modifier scales that recipe's input quantities.
func _test_recipe_input_modifier_scales_inputs() -> void:
	_fresh()
	LabourState.policy_throughput_enabled = false
	var b := _furnace()
	var recipe: Dictionary = Catalog.get_recipe("r_005")
	var coal: Dictionary = {}
	var ore: Dictionary = {}
	for input in recipe.get("inputs", []):
		if str(Catalog.get_good(str(input.good_id)).get("internal_name", "")) == "coal":
			coal = input
		else:
			ore = input
	var coal0 := Production._scaled_input_qty(coal, b)
	var ore0 := Production._scaled_input_qty(ore, b)
	Modifiers.add({"id": "test_saving", "domain": "recipe_input", "target": "r_005", "target_match": {"good_internal": "coal"}, "pct": -15.0})
	_check(Production._scaled_input_qty(coal, b) == int(round(float(coal0) * 0.85)) and Production._scaled_input_qty(ore, b) == ore0,
		"AC1.3 a recipe_input modifier cuts only the coal it targets (%d -> %d)" % [coal0, Production._scaled_input_qty(coal, b)])
	var stats: Dictionary = Production.stats_at_level(str(b.instance_id), 1)
	var preview_coal := 0
	for row in stats.get("inputs", []):
		if str(row.good_id) == str(coal.good_id):
			preview_coal = int(row.qty)
	_check(preview_coal == Production._scaled_input_qty(coal, b), "AC1.3 the level preview shows the saved coal too")
	Modifiers.remove("test_saving")
	_fresh()


## AC1.5: previews agree with production for the same building and turn.
func _test_previews_match_production() -> void:
	_fresh()
	var b := _furnace()
	LabourState.set_labour_multiplier(1.2)
	var recipe: Dictionary = Catalog.get_recipe("r_005")
	var stats: Dictionary = Production.stats_at_level(str(b.instance_id), 1)
	var status_out := BuildingStatus.effective_output_qty(b, recipe)
	var stats_out := 0
	for row in stats.get("outputs", []):
		stats_out += int(row.qty)
	var ok_in := true
	for row in stats.get("inputs", []):
		for input in recipe.get("inputs", []):
			if str(input.good_id) == str(row.good_id):
				ok_in = ok_in and int(row.qty) == Production._scaled_input_qty(input, b)
	_check(status_out == stats_out and ok_in and is_equal_approx(MatchState.run_multiplier(b), 1.0 + (15.0 + 12.0) / 100.0),
		"AC1.5 status, level preview and production agree under Overtime and the 45 hour week (%d, %d)" % [status_out, stats_out])
	_fresh()


## AC1.4, AC2.9: no policy makes output from nothing; only satisfaction of +90 or more adds output.
func _test_no_free_output_and_the_prize() -> void:
	_fresh()
	var b := _furnace()
	var recipe: Dictionary = Catalog.get_recipe("r_005")
	var free := false
	var policies := [LabourState.WORKFORCE_POLICY_LAX_SAFETY, LabourState.WORKFORCE_POLICY_STRICT_SAFETY,
		LabourState.WORKFORCE_POLICY_GENEROUS_PENSIONS, LabourState.WORKFORCE_POLICY_PENSIONS_MINIMUM,
		LabourState.WORKFORCE_POLICY_ANNUAL_BONUS, LabourState.WORKFORCE_POLICY_SMALL_BONUS,
		LabourState.WORKFORCE_POLICY_ANNUAL_PROFIT_SHARE, LabourState.WORKFORCE_POLICY_PROFIT_SHARE_10,
		LabourState.WORKFORCE_POLICY_PUSH_AUTOMATION, LabourState.WORKFORCE_POLICY_EXTENDED_ANNUAL_LEAVE,
		LabourState.WORKFORCE_POLICY_GENEROUS_PARENTAL_LEAVE, LabourState.WORKFORCE_POLICY_UNION_PARTIAL,
		LabourState.WORKFORCE_POLICY_UNION_COMPREHENSIVE]
	for pid in policies:
		LabourState.set_workforce_policy_enabled(str(pid), true)
		free = free or not is_equal_approx(LabourState.workforce_output_multiplier(), 1.0)
		LabourState.set_workforce_policy_enabled(str(pid), false)
	_check(not free, "AC1.4 no labour policy multiplies output on its own")
	var out_before := BuildingStatus.effective_output_qty(b, recipe)
	var coal_in := Production._scaled_input_qty((recipe.get("inputs", []) as Array)[0], b)
	LabourState.satisfaction = 90.0
	_check(is_equal_approx(LabourState.workforce_output_multiplier(), 1.05)
		and absi(BuildingStatus.effective_output_qty(b, recipe) - int(round(float(out_before) * 1.05))) <= 1
		and Production._scaled_input_qty((recipe.get("inputs", []) as Array)[0], b) == coal_in,
		"AC2.9 at +90 outputs are +5% and inputs are not")
	LabourState.satisfaction = 89.9
	_check(is_equal_approx(LabourState.workforce_output_multiplier(), 1.0), "AC2.9 below +90 the prize is gone")
	_fresh()


## AC2.1, AC2.2: every knob option's throughput, labour and satisfaction match the spec table.
func _test_knob_table() -> void:
	_fresh()
	var haz := {"building_id": FURNACE, "level": 1}
	var plain := {"building_id": FACTORY, "level": 1}
	var level2 := {"building_id": FACTORY, "level": 2}
	# Defaults: Standard effort, 100% idle pay (+5), the 45 hour week (+12%, −15 with no union).
	_check(is_equal_approx(LabourState.throughput_pct_for(FACTORY), 12.0) and is_equal_approx(_part("idle_pay"), 5.0)
		and is_equal_approx(_part("work_week"), -15.0) and is_equal_approx(_labour_delta(plain), 0.0),
		"AC2.1 defaults: 45 hour week +12% throughput, −15 satisfaction, idle pay +5, no labour change")
	# Work effort.
	LabourState.set_labour_multiplier(0.8)
	_check(is_equal_approx(LabourState.throughput_pct_for(FACTORY), 2.0) and is_equal_approx(_labour_delta(plain), -0.20)
		and is_equal_approx(_part("effort"), -20.0), "AC2.1 Lean: throughput −10%, salary −20%, satisfaction −20")
	LabourState.set_labour_multiplier(1.2)
	_check(is_equal_approx(LabourState.throughput_pct_for(FACTORY), 27.0) and is_equal_approx(_labour_delta(plain), 0.25)
		and is_equal_approx(_part("effort"), -30.0), "AC2.1 Overtime: throughput +15%, salary +25%, satisfaction −30")
	LabourState.set_labour_multiplier(1.0)
	# Pay while idle.
	var idle_ok := true
	for pair in [[0.5, -15.0], [0.75, -5.0], [1.0, 5.0]]:
		LabourState.set_idle_labour_pay_share(float(pair[0]))
		idle_ok = idle_ok and is_equal_approx(_part("idle_pay"), float(pair[1]))
	_check(idle_ok, "AC2.1 pay while idle: −15, −5, +5")
	# Safety (AC2.2: hazardous only for the throughput and High safety's labour).
	LabourState.set_workforce_policy_enabled(LabourState.WORKFORCE_POLICY_LAX_SAFETY, true)
	var haz_ok := true
	for bid in HAZARDOUS:
		haz_ok = haz_ok and is_equal_approx(LabourState.throughput_pct_for(str(bid)), 22.0)
	_check(haz_ok and is_equal_approx(LabourState.throughput_pct_for(FACTORY), 12.0)
		and is_equal_approx(_labour_delta(plain), -0.05) and is_equal_approx(_part(LabourState.WORKFORCE_POLICY_LAX_SAFETY), -25.0),
		"AC2.1 AC2.2 Minimal safety: +10% at every hazardous site only, labour −5%, satisfaction −25")
	LabourState.set_workforce_policy_enabled(LabourState.WORKFORCE_POLICY_STRICT_SAFETY, true)
	_check(is_equal_approx(_labour_delta(haz), 0.05) and is_equal_approx(_labour_delta(plain), 0.0)
		and is_equal_approx(_part(LabourState.WORKFORCE_POLICY_STRICT_SAFETY), 10.0),
		"AC2.1 AC2.2 High safety: labour +5% at hazardous sites only, satisfaction +10")
	LabourState.set_workforce_policy_enabled(LabourState.WORKFORCE_POLICY_STRICT_SAFETY, false)
	# Pensions.
	LabourState.set_workforce_policy_enabled(LabourState.WORKFORCE_POLICY_PENSIONS_MINIMUM, true)
	_check(is_equal_approx(_labour_delta(plain), -0.05) and is_equal_approx(_part(LabourState.WORKFORCE_POLICY_PENSIONS_MINIMUM), -15.0),
		"AC2.1 Minimum legal pensions: labour −5%, satisfaction −15")
	LabourState.set_workforce_policy_enabled(LabourState.WORKFORCE_POLICY_GENEROUS_PENSIONS, true)
	var young := _part(LabourState.WORKFORCE_POLICY_GENEROUS_PENSIONS)
	for _t in 30:
		LabourState.tick_workforce_policies()
	_check(is_equal_approx(young, 10.0) and is_equal_approx(_part(LabourState.WORKFORCE_POLICY_GENEROUS_PENSIONS), 20.0)
		and _labour_delta(plain) > 0.0, "AC2.1 Generous pensions: +10, then +20 after 30 turns, with a rising labour cost")
	LabourState.set_workforce_policy_enabled(LabourState.WORKFORCE_POLICY_GENEROUS_PENSIONS, false)
	# Bonus.
	LabourState.set_workforce_policy_enabled(LabourState.WORKFORCE_POLICY_SMALL_BONUS, true)
	var small_ok := is_equal_approx(_labour_delta(plain), 0.025) and is_equal_approx(_part(LabourState.WORKFORCE_POLICY_SMALL_BONUS), 8.0)
	LabourState.set_workforce_policy_enabled(LabourState.WORKFORCE_POLICY_ANNUAL_BONUS, true)
	_check(small_ok and is_equal_approx(_labour_delta(plain), 0.05) and is_equal_approx(_part(LabourState.WORKFORCE_POLICY_ANNUAL_BONUS), 15.0),
		"AC2.1 annual bonus: small +2.5% and +8, generous +5% and +15")
	LabourState.set_workforce_policy_enabled(LabourState.WORKFORCE_POLICY_ANNUAL_BONUS, false)
	# Profit share: satisfaction only (AC2.3 covers its cost in test_finance).
	LabourState.set_workforce_policy_enabled(LabourState.WORKFORCE_POLICY_ANNUAL_PROFIT_SHARE, true)
	var five := _part(LabourState.WORKFORCE_POLICY_ANNUAL_PROFIT_SHARE)
	LabourState.set_workforce_policy_enabled(LabourState.WORKFORCE_POLICY_PROFIT_SHARE_10, true)
	_check(is_equal_approx(five, 10.0) and is_equal_approx(_part(LabourState.WORKFORCE_POLICY_PROFIT_SHARE_10), 20.0)
		and is_equal_approx(LabourState.throughput_pct_for(FACTORY), 12.0) and is_equal_approx(_labour_delta(plain), 0.0),
		"AC2.1 AC2.3 profit share: +10 and +20 satisfaction, no throughput, no labour change")
	LabourState.set_workforce_policy_enabled(LabourState.WORKFORCE_POLICY_PROFIT_SHARE_10, false)
	# Automation (AC2.6): level 2+ only.
	LabourState.set_workforce_policy_enabled(LabourState.WORKFORCE_POLICY_PUSH_AUTOMATION, true)
	_check(is_equal_approx(_labour_delta(level2), -0.15) and is_equal_approx(_labour_delta(plain), 0.0)
		and is_equal_approx(LabourState.workforce_power_multiplier(level2), 1.10) and is_equal_approx(LabourState.workforce_maintenance_multiplier(level2), 1.10)
		and is_equal_approx(LabourState.workforce_power_multiplier(plain), 1.0)
		and is_equal_approx(_part(LabourState.WORKFORCE_POLICY_PUSH_AUTOMATION), -10.0),
		"AC2.6 Automation on level 2+: labour −15%, power and maintenance +10%, satisfaction −10")
	var layoff := false
	for s in LabourState.target_shifts:
		layoff = layoff or (is_equal_approx(float(s.value), -10.0) and int(s.turns_left) == 10)
	_check(layoff, "AC2.6 switching Automation on adds a −10 target shift for 10 turns")
	LabourState.set_workforce_policy_enabled(LabourState.WORKFORCE_POLICY_PUSH_AUTOMATION, false)
	# Lockers.
	LabourState.set_workforce_policy_enabled(LabourState.WORKFORCE_POLICY_EXTENDED_ANNUAL_LEAVE, true)
	LabourState.set_workforce_policy_enabled(LabourState.WORKFORCE_POLICY_GENEROUS_PARENTAL_LEAVE, true)
	_check(is_equal_approx(LabourState.throughput_pct_for(FACTORY), 8.0)
		and is_equal_approx(_part(LabourState.WORKFORCE_POLICY_EXTENDED_ANNUAL_LEAVE), 8.0)
		and is_equal_approx(_part(LabourState.WORKFORCE_POLICY_GENEROUS_PARENTAL_LEAVE), 8.0),
		"AC2.1 leave policies: −2% throughput and +8 satisfaction each")
	LabourState.workforce_policies[LabourState.WORKFORCE_POLICY_LONG_TENURE] = true
	LabourState.workforce_policies[LabourState.WORKFORCE_POLICY_STOCK_OPTIONS] = true
	_check(is_equal_approx(_part(LabourState.WORKFORCE_POLICY_LONG_TENURE), 5.0) and is_equal_approx(_part(LabourState.WORKFORCE_POLICY_STOCK_OPTIONS), 10.0),
		"AC2.1 Long Tenure Awards +5, Stock Options +10")
	_fresh()


## AC2.4: the work week's throughput, and its cost by union.
func _test_work_week() -> void:
	_fresh()
	var plain := {"building_id": FACTORY, "level": 1}
	_check(LabourState.work_week_hours == 45, "AC2.4 new games start on the 45 hour week")
	var ok := true
	for row in [[35, 5.0, -5.0, 0.10], [40, 9.0, -10.0, 0.20], [45, 12.0, -15.0, 0.30], [50, 14.5, -20.0, 0.40]]:
		LabourState.set_work_week(int(row[0]))
		ok = ok and is_equal_approx(LabourState.throughput_pct_for(FACTORY), float(row[1]))
		ok = ok and is_equal_approx(_part("work_week"), float(row[2])) and is_equal_approx(_labour_delta(plain), 0.0)
		LabourState.set_union_tier(LabourState.UNION_PARTIAL)
		ok = ok and is_equal_approx(_part("work_week"), 0.0)
		ok = ok and is_equal_approx(_labour_delta(plain), 0.10 + float(row[3]))
		LabourState.union_halving_active = false
		LabourState.workforce_policies.erase(LabourState.WORKFORCE_POLICY_UNION_PARTIAL)
		LabourState.union_active_turns = 0
	_check(ok, "AC2.4 35/40/45/50 hours: +5/+9/+12/+14.5% throughput; −5 a level with no union, +10% labour a level under one")
	LabourState.set_work_week(42)
	_check(LabourState.work_week_hours == 50, "AC2.4 an off-menu week is refused")
	_fresh()


## AC2.5: union tiers, their satisfaction, their exclusivity and the pay-round ramp.
func _test_union_tiers_and_ramp() -> void:
	_fresh()
	LabourState.set_union_tier(LabourState.UNION_PARTIAL)
	var partial := _part(LabourState.WORKFORCE_POLICY_UNION_PARTIAL)
	LabourState.set_workforce_policy_enabled(LabourState.WORKFORCE_POLICY_UNION_COMPREHENSIVE, true)
	_check(is_equal_approx(partial, 15.0) and is_equal_approx(_part(LabourState.WORKFORCE_POLICY_UNION_COMPREHENSIVE), 30.0)
		and not LabourState.is_workforce_policy_enabled(LabourState.WORKFORCE_POLICY_UNION_PARTIAL),
		"AC2.5 Partial +15, Comprehensive +30, and they are exclusive")
	var ramp_ok := is_equal_approx(LabourState.union_labour_delta(), 0.10)
	for _t in 10:
		LabourState.tick_satisfaction()
	ramp_ok = ramp_ok and is_equal_approx(LabourState.union_labour_delta(), 0.11)
	ramp_ok = ramp_ok and is_equal_approx(LabourState.union_labour_delta(150), 0.25) and is_equal_approx(LabourState.union_labour_delta(500), 0.25)
	_check(ramp_ok, "AC2.5 union labour +10%, +1% each 10 turns, capped at +25%")
	_fresh()


## AC2.7: output pressure is retired.
func _test_output_pressure_retired() -> void:
	_fresh()
	var fields := LabourState.export_fields()
	LabourState.import_fields({"labour_output_pressure_pct": 10.0, "labour_multiplier": 1.2})
	_check(not fields.has("labour_output_pressure_pct") and LabourState.get("labour_output_pressure_pct") == null
		and is_equal_approx(LabourState.labour_multiplier, 1.2), "AC2.7 output pressure is gone and an old save carrying it still loads")
	_fresh()


## AC2.8: the target, the movement rule and the projection.
func _test_satisfaction_movement() -> void:
	_fresh()
	_check(is_equal_approx(LabourState.step_toward(40.0, -55.0), 30.5) and is_equal_approx(LabourState.step_toward(-55.0, 40.0), -45.5),
		"AC2.8 one turn moves 10% of the gap, the same both ways")
	_check(is_equal_approx(LabourState.step_toward(0.0, 15.0), 2.0) and is_equal_approx(LabourState.step_toward(0.0, 1.5), 1.5)
		and is_equal_approx(LabourState.step_toward(-4.0, -6.0), -6.0), "AC2.8 at least 2 a turn, landing on the target within 2")
	LabourState.set_labour_multiplier(1.2)
	LabourState.add_target_shift("test_shift", "test", -20.0)
	_check(is_equal_approx(LabourState.target_satisfaction(), -30.0 + 5.0 - 15.0 - 20.0), "AC2.8 target = contributions + shifts")
	for _i in 12:
		LabourState.add_target_shift("test_pile_%d" % _i, "test", -20.0)
	_check(is_equal_approx(LabourState.target_satisfaction(), -100.0), "AC2.8 the target clamps at −100")
	LabourState.target_shifts.clear()
	LabourState.add_target_shift("test_shift", "test", -20.0)
	var projected := LabourState.projected_satisfaction(10)
	for _t in 10:
		LabourState.tick_satisfaction()
	_check(is_equal_approx(projected, LabourState.satisfaction), "AC2.8 the 10 turn projection equals 10 real turns (%.2f)" % projected)
	_fresh()


## AC2.10: workforce size and the HR Director.
func _test_company_contributions() -> void:
	_fresh()
	for i in 2:
		BuildingState.tile_land_owned["tile_6_8"] = 200
		BuildingState.add_building(MINE, "r_001", "tile_6_8", MatchState.LOCAL_PLAYER, "")
	_furnace()
	_check(LabourState.workforce_headcount() > 5000 and LabourState.workforce_headcount() < 25000
		and is_equal_approx(_part("workforce_5000"), 5.0) and is_equal_approx(_part("workforce_25000"), 0.0),
		"AC2.10 over 5,000 workers +5 (%d workers)" % LabourState.workforce_headcount())
	for i in 10:
		BuildingState.add_building(MINE, "r_001", "tile_6_8", MatchState.LOCAL_PLAYER, "")
	_check(LabourState.workforce_headcount() > 25000 and is_equal_approx(_part("workforce_5000") + _part("workforce_25000"), 10.0),
		"AC2.10 over 25,000 workers +10 in total")
	var saved_seats: Dictionary = AdvisorState.advisor_seats.duplicate(true)
	var tier_ok := is_equal_approx(_part("hr_director"), 0.0)
	for pair in [["eleanor", 5.0], ["marcus", 0.0], ["idris", -5.0]]:
		AdvisorState.advisor_seats["hr_director"] = str(pair[0])
		tier_ok = tier_ok and is_equal_approx(_part("hr_director"), float(pair[1]))
	_check(tier_ok, "AC2.10 HR Director 3 stars +5, 2 stars 0, 1 star −5, none 0")
	AdvisorState.advisor_seats = saved_seats
	_fresh()


## AC2.11: events shift the target for 10 turns; satisfaction never jumps for them.
func _test_events_shift_the_target() -> void:
	_fresh()
	var target0 := LabourState.target_satisfaction()
	LabourState.satisfaction = 20.0
	LabourState.on_building_demolished("x")
	LabourState.on_building_sold("y")
	_check(is_equal_approx(LabourState.satisfaction, 20.0) and is_equal_approx(LabourState.target_satisfaction(), target0 - 20.0),
		"AC2.11 demolition −15 and a sale −5 move the target, not satisfaction")
	for _t in 10:
		LabourState.tick_satisfaction()
	_check(LabourState.target_shifts.is_empty() and is_equal_approx(LabourState.target_satisfaction(), target0),
		"AC2.11 the shifts are gone after 10 turns")
	_fresh()


## AC2.12: start values and the Metal Magnate trajectory (−5 crossed on turn 8).
func _test_start_values_and_magnate_trajectory() -> void:
	_fresh()
	var mm: Dictionary = SaveLoad.expand_start_config(JSON.parse_string(FileAccess.get_file_as_string("res://data/starts/metal_magnate.json")))
	var gm: Dictionary = SaveLoad.expand_start_config(JSON.parse_string(FileAccess.get_file_as_string("res://data/starts/glass_merchant.json")))
	_check(is_equal_approx(float(mm.match.labour_satisfaction), 40.0) and is_equal_approx(float(gm.match.labour_satisfaction), 20.0),
		"AC2.12 starts: Magnate +40, Glass Merchant +20")
	# Magnate's presets and workforce.
	for spec in [[MINE, "r_001", "tile_6_8"], [MINE, "r_002", "tile_7_10"], [FURNACE, "r_005", "tile_9_9"], ["b_003", "r_004", "tile_9_9"]]:
		BuildingState.tile_land_owned[str(spec[2])] = 200
		BuildingState.add_building(str(spec[0]), str(spec[1]), str(spec[2]), MatchState.LOCAL_PLAYER, "")
	LabourState.set_labour_multiplier(1.2)
	LabourState.set_idle_labour_pay_share(0.5)
	LabourState.satisfaction = 40.0
	_check(is_equal_approx(LabourState.target_satisfaction(), -55.0), "AC2.12 Magnate's target is −55 (%.1f)" % LabourState.target_satisfaction())
	var crossed := 0
	for turn in range(2, 30):
		LabourState.tick_satisfaction()
		if crossed == 0 and LabourState.satisfaction < -5.0:
			crossed = turn
	_check(crossed == 8, "AC2.12 Magnate's default satisfaction crosses −5 on turn 8 (turn %d)" % crossed)
	_fresh()


## AC2.14 to AC2.17: the Comprehensive halving.
func _test_comprehensive_halving() -> void:
	_fresh()
	var b := {"building_id": FURNACE, "level": 1, "instance_id": ""}
	Modifiers.add({"id": "test_cut_before", "domain": "labour_headcount", "target": "*", "pct": -10.0})
	LabourState.set_labour_multiplier(0.8)
	LabourState.set_union_tier(LabourState.UNION_COMPREHENSIVE)
	_check(LabourState.union_halving_active and LabourState.union_grandfathered_ids.has("test_cut_before")
		and LabourState.union_grandfathered_ids.has("effort_lean"), "AC2.14 signing records the cuts then in force")
	Modifiers.add({"id": "test_cut_after", "domain": "labour_headcount", "target": "*", "pct": -10.0})
	# Lean −0.20 and the old cut −0.10 in full; the new cut −0.05; union +0.10; 45 hours under a union +0.30.
	_check(is_equal_approx(_labour_delta(b), -0.20 - 0.10 - 0.05 + 0.10 + 0.30),
		"AC2.14 old cuts stay full, new cuts count at half (%.3f)" % _labour_delta(b))
	LabourState.set_labour_multiplier(1.0)
	LabourState.set_labour_multiplier(0.8)
	_check(not LabourState.union_grandfathered_ids.has("effort_lean") and is_equal_approx(_labour_delta(b), -0.10 - 0.10 - 0.05 + 0.10 + 0.30),
		"AC2.15 a cut switched off and on again counts as new")
	LabourState.set_workforce_policy_enabled(LabourState.WORKFORCE_POLICY_STRICT_SAFETY, true)
	_check(is_equal_approx(_labour_delta(b), -0.10 - 0.10 - 0.05 + 0.10 + 0.30 + 0.05), "AC2.16 increases are never halved")
	Modifiers.add({"id": "test_cut_huge", "domain": "labour_headcount", "target": "*", "pct": -200.0})
	_check(is_equal_approx(LabourState.labour_cost_factor_for(b), EconomyConfig.LABOUR_FACTOR_MIN), "AC2.16 the floor applies after the halving")
	Modifiers.remove("test_cut_huge")
	LabourState.set_union_tier(LabourState.UNION_NONE)
	_check(LabourState.union_halving_active and LabourState.halving_weight("test_cut_after", -0.1) == 0.5,
		"AC2.17 the halving survives dropping the union")
	LabourState.set_union_tier(LabourState.UNION_COMPREHENSIVE)
	_check(not LabourState.union_grandfathered_ids.has("test_cut_after"), "AC2.17 re-signing keeps the existing record")
	# An advisor re-seated (its modifier gone for a turn, then back) counts as new.
	Modifiers.remove("test_cut_before")
	LabourState.tick_satisfaction()
	Modifiers.add({"id": "test_cut_before", "domain": "labour_headcount", "target": "*", "pct": -10.0})
	_check(LabourState.halving_weight("test_cut_before", -0.1) == 0.5, "AC2.15 a cut that ended and came back counts as new")
	_fresh()


## AC2.18: stepping down a tier.
func _test_union_step_downs() -> void:
	_fresh()
	var saved_rev: Array = LoanState._revenue_history.duplicate()
	LoanState._revenue_history = [100.0, 100.0, 100.0, 100.0, 100.0]
	MatchState.one_off_charges.clear()
	LabourState.set_union_tier(LabourState.UNION_COMPREHENSIVE)
	_check(MatchState.one_off_charges.is_empty(), "AC2.18 moving up costs nothing")
	LabourState.set_union_tier(LabourState.UNION_PARTIAL)
	var one: Dictionary = MatchState.one_off_charges[0] if not MatchState.one_off_charges.is_empty() else {}
	_check(MatchState.one_off_charges.size() == 1 and is_equal_approx(float(one.get("amount", 0.0)), 5.0) and str(one.get("label", "")) == "Union settlement"
		and LabourState.target_shifts.size() == 1 and is_equal_approx(float(LabourState.target_shifts[0].value), -15.0),
		"AC2.18 Comprehensive to Partial: 5% of average revenue and a −15 shift")
	MatchState.one_off_charges.clear()
	LabourState.target_shifts.clear()
	LabourState.set_union_tier(LabourState.UNION_COMPREHENSIVE)
	LabourState.set_union_tier(LabourState.UNION_NONE)
	var total := 0.0
	for c in MatchState.one_off_charges:
		total += float(c.amount)
	_check(is_equal_approx(total, 10.0) and LabourState.target_shifts.size() == 2, "AC2.18 Comprehensive to none is both steps (10%, two shifts)")
	for _t in 29:
		LabourState.tick_satisfaction()
	var left_29 := LabourState.target_shifts.size()
	LabourState.tick_satisfaction()
	_check(left_29 == 2 and LabourState.target_shifts.is_empty(), "AC2.18 a −15 shift decays 0.5 a turn and is gone after 30 turns")
	MatchState.one_off_charges.clear()
	LoanState._revenue_history = saved_rev
	_fresh()


## AC2.19: renege.
func _test_renege() -> void:
	_fresh()
	_check(not LabourState.can_renege(), "AC2.19 no renege without a halving")
	LabourState.set_union_tier(LabourState.UNION_COMPREHENSIVE)
	_check(not LabourState.can_renege(), "AC2.19 no renege while a union stands")
	MatchState.one_off_charges.clear()
	LabourState.set_union_tier(LabourState.UNION_NONE)
	LabourState.satisfaction = 12.0
	_check(LabourState.can_renege() and LabourState.renege_union_agreements(), "AC2.19 renege is offered once the union is gone")
	_check(not LabourState.union_halving_active and LabourState.union_grandfathered_ids.is_empty()
		and is_equal_approx(LabourState.satisfaction, -38.0), "AC2.19 renege ends the halving and drops satisfaction by exactly 50")
	LabourState.set_union_tier(LabourState.UNION_COMPREHENSIVE)
	LabourState.set_union_tier(LabourState.UNION_NONE)
	LabourState.satisfaction = -80.0
	LabourState.renege_union_agreements()
	_check(is_equal_approx(LabourState.satisfaction, -100.0), "AC2.19 renege clamps at −100")
	MatchState.one_off_charges.clear()
	_fresh()


## AC2.13, AC3.1: a save mid-run continues identically; v17 saves migrate; validation.
func _test_save_round_trip_and_migration() -> void:
	_fresh()
	LabourState.set_labour_multiplier(1.2)
	LabourState.set_union_tier(LabourState.UNION_COMPREHENSIVE)
	LabourState.set_work_week(50)
	LabourState.add_target_shift("test_event", "test", -15.0)
	LabourState.satisfaction = 33.0
	for _t in 5:
		LabourState.tick_satisfaction()
	var mid := LabourState.export_fields()
	for _t in 5:
		LabourState.tick_satisfaction()
	var straight := LabourState.satisfaction
	var straight_fields := LabourState.export_fields()
	LabourState.reset()
	LabourState.import_fields(mid)
	for _t in 5:
		LabourState.tick_satisfaction()
	_check(is_equal_approx(LabourState.satisfaction, straight) and str(LabourState.export_fields()) == str(straight_fields),
		"AC2.13 AC3.1 a mid-run save and load continues identically")
	var old := {"save_version": 17, "match": {"scenario_name": "metal_magnate", "labour_output_pressure_pct": 10.0, "labour_multiplier": 1.2}}
	var migrated: Dictionary = SaveLoad._migrate(old)
	_check(int(migrated.save_version) == 18 and is_equal_approx(float(migrated.match.labour_satisfaction), 40.0)
		and int(migrated.match.work_week_hours) == 45 and not (migrated.match as Dictionary).has("labour_output_pressure_pct"),
		"AC3.1 a v17 save migrates: its start's satisfaction, 45 hours, no output pressure")
	var unknown: Dictionary = SaveLoad._migrate({"save_version": 17, "match": {}})
	_check(is_equal_approx(float(unknown.match.labour_satisfaction), 0.0), "AC3.1 a save with no known start migrates to satisfaction 0")
	var validator = SaveValidationScript.new()
	var good := {"save_version": 18, "match": LabourState.export_fields(), "turn": {"current_turn": 3}}
	var bad_sat := {"save_version": 18, "match": {"labour_satisfaction": 150.0}, "turn": {"current_turn": 3}}
	var bad_week := {"save_version": 18, "match": {"work_week_hours": 42}, "turn": {"current_turn": 3}}
	_check(validator.validate(good, 18, false) == "" and validator.validate(bad_sat, 18, false) != ""
		and validator.validate(bad_week, 18, false) != "", "AC3.1 validation accepts the new fields and rejects out-of-range values")
	_fresh()
