extends "res://tests/test_base.gd"
## Phase 3 of docs/pacing-labour-mining-licensing-spec.md: strikes, pay rises and accidents
## (scripts/labour_unrest.gd). Each test names the acceptance criteria (AC…) it checks.

const FEATURE := "strikes"
const TAGS := {
	"_test_strike_telemetry": ["strikes", "telemetry"],
	"_test_strike_save_round_trip": ["strikes", "save"],
	"_test_strikes_tab_and_diagnostics": ["strikes", "ui", "people"],
	"_test_strike_planning_tab": ["strikes", "ui", "people"],
}

const MINE := "b_001"
const FURNACE := "b_002"
const POWER := "b_003"
const FACTORY := "b_007"
const LabourUnrest := preload("res://scripts/labour_unrest.gd")
const PeopleDs2 := preload("res://scripts/people_ds2/people_ds2.gd")
const SearchOverlay := preload("res://scripts/search_overlay.gd")
const Plate := preload("res://scripts/bdp_v3_plate.gd")


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


func _left_click() -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	return e


func _sum_break() -> float:
	var total := 0.0
	for iid in _u().affected_buildings():
		total += _u().break_cost(str(iid))
	return total


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
## −70…−90, or it is called off at −70 and above. A strike cuts output 60% (power too) for T, T+1 and T+2, consumes
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
	_check(BuildingStatus.effective_output_qty(b, recipe) == int(round(float(out0) * LabourUnrest.STRIKE_OUTPUT_MULT)) and LabourUnrest.STRIKE_OUTPUT_MULT == 0.4
		and Production._scaled_input_qty(recipe.inputs[0], b) == in0, "AC12.4 a strike cuts output 60% and keeps inputs in full")
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


## AC13.1–AC13.3: raising pay at one building takes it out of the warning or ends its strike, +40% labour there for
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
	_check(_u().raise_pay(first, 8) and not _u().is_named(first) and int(_u().pay_raises[first]) == 10,
		"AC13.1 a pay rise takes the building out of the warning for 10 turns")
	_check(is_equal_approx(LabourState.labour_cost_factor_for(b) - factor0, 0.40), "AC13.1 its labour is 40% higher")
	_check(is_equal_approx(LabourState.target_satisfaction(), target0) and is_equal_approx(LabourState.satisfaction, -80.0),
		"AC13.3 a pay rise moves neither satisfaction nor its target")
	_tick(10)
	var striking := str(_u().active.keys()[0])
	_check(not _u().is_on_strike(first), "AC13.1 the raised building does not strike")
	_check(_u().raise_pay(striking, 10) and not _u().is_on_strike(striking) and is_zero_approx(_shift("strike_over")),
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


## AC13.4–AC13.7: breaking strikes. One building: a turn of its base wages charged this turn ("Strike breaking"),
## its strike ends (or it leaves the warning) with no +5, and the target falls 5 for 10 turns. A whole round:
## every named and striking building, the target −20, and no protection after. Two whole rounds, or ten buildings
## one at a time, add "Routinely broke strikes", a standing −15 that only a Comprehensive Union Agreement clears.
func _test_break_strikes() -> void:
	_fresh(-80.0)
	_company(8)
	_tick(7)
	var named: Array = (_u().warning.buildings as Array).duplicate()
	var first := str(named[0])
	var cost := Production._base_labour_cost(BuildingState.get_building(first)) * LabourUnrest.BREAK_COST_TURNS
	MatchState.one_off_charges.clear()
	_check(cost > 0.0 and is_equal_approx(_u().break_cost(first), cost), "AC13.4 breaking costs a turn of base wages")
	_check(_u().break_strike(first, 8) and not _u().is_named(first), "AC13.4 a broken named building leaves the warning")
	var charge: Dictionary = MatchState.one_off_charges.back() if not MatchState.one_off_charges.is_empty() else {}
	_check(str(charge.get("label", "")) == "Strike breaking" and is_equal_approx(float(charge.get("amount", 0.0)), snappedf(cost, 0.01))
		and int(charge.get("turn", 0)) == 8, "AC13.4 it is charged this turn as Strike breaking")
	_check(is_equal_approx(_shift("strike_broken_"), LabourUnrest.BREAK_SHIFT_ONE) and LabourUnrest.BREAK_SHIFT_ONE == -5.0,
		"AC13.4 the target falls 5")
	_check(str((_u().record.back() as Dictionary).outcome) == "broken" and _u().buildings_broken == 1, "AC13.4 the record says broken")
	_tick(10)
	var striking := str(_u().active.keys()[0])
	_check(_u().break_strike(striking, 10) and not _u().is_on_strike(striking) and is_zero_approx(_shift("strike_over")),
		"AC13.4 breaking ends a strike at once, with no +5")
	_fresh(-80.0)
	_company(8)
	_tick(7)
	_tick(10)
	var total := 0.0
	for iid in _u().affected_buildings():
		total += _u().break_cost(str(iid))
	MatchState.one_off_charges.clear()
	_check(_u().break_all(10) and _u().active.is_empty() and _u().warning.is_empty() and _u().strike_free_until == 0,
		"AC13.5 breaking the round ends every strike, with no protection after")
	_check(is_equal_approx(_shift("strikes_broken_"), -20.0) and is_zero_approx(_shift("strike_broken_")),
		"AC13.5 the target falls 20 for the round, not 5 a building")
	_check(not MatchState.one_off_charges.is_empty() and is_equal_approx(float((MatchState.one_off_charges.back() as Dictionary).amount), snappedf(total, 0.01)),
		"AC13.5 every striker's turn of wages is charged")
	_check(_u().rounds_broken == 1 and not _u().routinely_broke, "AC13.6 one round broken is not yet routine")
	_tick(17)
	_tick(20)
	_check(not _u().active.is_empty() and _u().break_makes_routine("all"), "AC13.6 setup: the next round strikes, and breaking it would be routine")
	_u().break_all(20)
	var routine := false
	for part: Dictionary in LabourState.satisfaction_contributions():
		routine = routine or (str(part.id) == "routinely_broke_strikes" and is_equal_approx(float(part.value), -15.0))
	_check(_u().routinely_broke and routine, "AC13.6 a second round broken adds Routinely broke strikes, −15")
	LabourState.set_union_tier(LabourState.UNION_PARTIAL)
	_check(_u().routinely_broke, "AC13.7 a Partial Union Agreement does not clear it")
	LabourState.set_union_tier(LabourState.UNION_COMPREHENSIVE)
	_check(not _u().routinely_broke and _u().rounds_broken == 0 and _u().buildings_broken == 0,
		"AC13.7 a Comprehensive Union Agreement clears it and the counts toward it")
	LabourState.set_union_tier(LabourState.UNION_NONE)
	_check(not _u().routinely_broke, "AC13.7 it stays cleared after the union steps down")
	_fresh(-80.0)
	_u().buildings_broken = 9
	_company(8)
	_tick(7)
	var ninth := str((_u().warning.buildings as Array)[0])
	_check(_u().break_makes_routine(ninth) and not _u().break_makes_routine("all"), "AC13.6 the tenth single break would be routine")
	_u().break_strike(ninth, 8)
	_check(_u().routinely_broke, "AC13.6 ten buildings broken one at a time make it routine")
	_fresh()


## AC13.8–AC13.10: a building broken on turn t sits out every check before t + 20, one settled every check before
## t + 25. The others are drawn as usual and the strike size still counts the quiet ones.
func _test_strike_quiet() -> void:
	_fresh(-80.0)
	var only := str(_company(1)[0])
	_tick(7)
	_check(_u().is_named(only) and _u().break_strike(only, 8) and _u().warning.is_empty(), "AC13.8 setup: the only building named, then broken")
	_check(_u().is_quiet(only, 27) and not _u().is_quiet(only, 28), "AC13.8 broken on turn 8, it is quiet before turn 28 and not from it")
	for t in range(8, 18):
		_tick(t)
	_check(_u().warning.is_empty() and _u().active.is_empty(), "AC13.8 it is not named for the check on turn 20")
	for t in range(18, 28):
		_tick(t)
	_check(_u().is_named(only), "AC13.8 it can be named again for the check on turn 30")
	_fresh(-80.0)
	only = str(_company(1)[0])
	_tick(7)
	_check(_u().raise_pay(only, 8), "AC13.9 setup: the only building settled on turn 8")
	_check(_u().is_quiet(only, 32) and not _u().is_quiet(only, 33), "AC13.9 settled on turn 8, it is quiet before turn 33 and not from it")
	for t in range(8, 18):
		_tick(t)
	var quiet_at_20 := _u().warning.is_empty()
	for t in range(18, 28):
		_tick(t)
	_check(quiet_at_20 and _u().warning.is_empty() and _u().active.is_empty(), "AC13.9 it is not named for the checks on turns 20 and 30")
	for t in range(28, 38):
		_tick(t)
	_check(_u().is_named(only), "AC13.9 it can be named again for the check on turn 40")
	_fresh(-80.0)
	_company(5)
	_tick(7)
	_tick(10)
	var settled := _u().ongoing()
	_check(settled.size() == 2 and _u().raise_pay_all(10) and _u().strike_free_until == 25
		and settled.all(func(iid: String) -> bool: return int(_u().quiet_until.get(iid, 0)) == 35),
		"AC13.9 settling every strike blocks all strikes to turn 25 and each settled building to turn 35")
	for t in range(11, 28):
		_tick(t)
	var named: Array = _u().warning.get("buildings", [])
	_check(named.size() == 2 and not named.any(func(iid: String) -> bool: return settled.has(iid)),
		"AC13.9 at the check on turn 30 two of the other three are named, the size still counting all five")
	_fresh(-80.0)
	_company(5)
	_tick(7)
	_tick(10)
	var broken := _u().ongoing()
	_check(broken.size() == 2 and _u().break_all(10)
		and broken.all(func(iid: String) -> bool: return int(_u().quiet_until.get(iid, 0)) == 30),
		"AC13.8 breaking the round makes each broken building quiet to turn 30")
	for t in range(11, 18):
		_tick(t)
	named = _u().warning.get("buildings", [])
	_check(named.size() == 2 and not named.any(func(iid: String) -> bool: return broken.has(iid)),
		"AC13.8 at the check on turn 20 two of the other three are named")
	var iid := str(named[0])
	_check(str(PeopleDs2.StrikesTab.bed_words("break", iid, [iid])).contains("cannot strike again for 20 turns")
		and str(PeopleDs2.StrikesTab.bed_words("settle", iid, [iid])).contains("cannot strike again for 25 turns")
		and SearchOverlay.strikes_page().contains("A settled building cannot strike again for 25 turns")
		and SearchOverlay.strikes_page().contains("A broken building cannot strike again for 20 turns"),
		"AC13.8 AC13.9 the Strikes tab and the Mechanics page say how long each stays quiet")
	_fresh()


## AC13.11–AC13.13: a bonus costs half the Settle cost and quiets a building for 10 to 20 turns by satisfaction, 15 at 0;
## the building bonus ends its strike or warning, the company wide bonus covers every building it would lengthen, in
## one lump sum; neither moves satisfaction, and neither shortens a quiet.
func _test_one_off_bonus() -> void:
	_check(LabourUnrest.bonus_quiet_turns(-100.0) == 10 and LabourUnrest.bonus_quiet_turns(0.0) == 15
		and LabourUnrest.bonus_quiet_turns(100.0) == 20 and LabourUnrest.bonus_quiet_turns(-80.0) == 11,
		"AC13.11 a bonus quiets 10 turns at −100, 15 at 0, 20 at +100 (11 at −80)")
	_fresh(-80.0)
	_company(8)
	_tick(7)
	var first := str((_u().warning.buildings as Array)[0])
	var cost := _u().pay_raise_cost(first) * 0.5
	_check(cost > 0.0 and is_equal_approx(_u().bonus_cost(first), cost), "AC13.11 a building bonus costs half its Settle cost")
	var target0 := LabourState.target_satisfaction()
	MatchState.one_off_charges.clear()
	_check(_u().pay_bonus(first, 8) and not _u().is_named(first) and int(_u().quiet_until[first]) == 19,
		"AC13.12 a bonus on turn 8 at −80 takes the building out of the warning, quiet to turn 19")
	var charge: Dictionary = MatchState.one_off_charges.back() if not MatchState.one_off_charges.is_empty() else {}
	_check(str(charge.get("label", "")) == "One off bonus" and is_equal_approx(float(charge.get("amount", 0.0)), snappedf(cost, 0.01))
		and int(charge.get("turn", 0)) == 8, "AC13.12 it is charged this turn as One off bonus")
	_check(is_equal_approx(LabourState.target_satisfaction(), target0) and is_equal_approx(LabourState.satisfaction, -80.0)
		and _u().buildings_broken == 0 and _u().rounds_broken == 0, "AC13.12 it moves neither satisfaction nor the strike breaking counts")
	_tick(10)
	var striking := str(_u().active.keys()[0])
	_check(_u().pay_bonus(striking, 10) and not _u().is_on_strike(striking) and is_zero_approx(_shift("strike_over"))
		and int(_u().quiet_until[striking]) == 21, "AC13.12 a bonus ends a strike at once, with no +5")
	var settled := str(_u().eligible_buildings().filter(func(iid: String) -> bool: return not _u().quiet_until.has(iid))[0])
	_u().quiet_until[settled] = 35
	_check(not _u().bonus_lengthens(settled, 10) and not _u().pay_bonus(settled, 10) and int(_u().quiet_until[settled]) == 35,
		"AC13.12 AC13.11 a bonus is refused where it would not lengthen the quiet, and never shortens it")
	var covered := _u().company_bonus_buildings(10)
	var total := 0.0
	for iid in covered:
		total += _u().bonus_cost(str(iid))
	_check(covered.size() == 6 and covered.has(first) and not covered.has(striking) and not covered.has(settled)
		and is_equal_approx(_u().company_bonus_cost(10), total),
		"AC13.13 the company wide bonus covers every building it would lengthen (%d)" % covered.size())
	MatchState.one_off_charges.clear()
	_check(_u().pay_company_bonus(10) and MatchState.one_off_charges.size() == 1
		and is_equal_approx(float((MatchState.one_off_charges.back() as Dictionary).amount), snappedf(total, 0.01)),
		"AC13.13 it charges their costs as one lump sum")
	_check(covered.all(func(iid: String) -> bool: return int(_u().quiet_until[iid]) == 21) and int(_u().quiet_until[settled]) == 35,
		"AC13.13 each covered building is quiet to turn 21, the longer quiet kept")
	_check(not _u().pay_company_bonus(10), "AC13.13 it is refused when it covers none")
	_fresh()


## AC13.14: the cooldown list is the buildings quiet now; the vulnerable list the named buildings during a warning, else
## those that would not sit out the next check while its warning is still to be drawn and satisfaction is projected below
## −70 at the draw, else none.
func _test_strike_lists() -> void:
	_fresh(-80.0)
	var iids := _company(4)
	iids.sort()
	LabourState.add_target_shift("test_low", "Low", -200.0, 40)
	_check(_u().vulnerable(1) == iids, "AC13.14 before the draw, every counted building can strike")
	var quiet := str(iids[0])
	_u().quiet_until[quiet] = 15
	_check(not _u().vulnerable(1).has(quiet) and _u().vulnerable(1).size() == 3, "AC13.14 a building quiet past the check cannot")
	_check(_u().on_cooldown(1) == [quiet] and _u().quiet_turns_left(quiet, 1) == 14 and _u().on_cooldown(15).is_empty(),
		"AC13.14 the cooldown list is the buildings quiet now, with their turns left")
	_check(_u().vulnerable(8).is_empty(), "AC13.14 once the draw has passed with no warning, nobody can strike")
	_tick(7)
	_check(_u().vulnerable(8) == _u().warning.buildings, "AC13.14 during a warning, the named buildings")
	_u().warning = {}
	LabourState.set_union_tier(LabourState.UNION_PARTIAL)
	_check(_u().vulnerable(1).is_empty(), "AC13.14 none while a union agreement stands")
	LabourState.set_union_tier(LabourState.UNION_NONE)
	_u().strike_free_until = 25
	_check(_u().vulnerable(11).is_empty(), "AC13.14 none while a settlement still protects the check")
	_u().strike_free_until = 0
	LabourState.target_shifts.clear()
	LabourState.add_target_shift("test_high", "High", 200.0, 40)
	_check(_u().vulnerable(1).is_empty(), "AC13.14 none when satisfaction is projected to reach −70 by the draw")
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
	_u().quiet_until["z"] = 31
	_u().accident_down["y"] = 1
	_u().accident_turns["y"] = 9
	_u().minimal_safety_turns = 6
	_u().rounds_broken = 1
	_u().buildings_broken = 3
	_u().routinely_broke = true
	var snap: Dictionary = MatchState.export_state()
	for key in ["strike_warning", "strike_active", "strike_record", "strike_pay_raises", "strike_free_until", "strike_quiet_until",
			"accident_down", "accident_turns", "accident_minimal_turns", "labour_rng_seed", "labour_rng_state",
			"strike_rounds_broken", "strike_buildings_broken", "strike_routinely_broke"]:
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
	_check(_u().rounds_broken == 1 and _u().buildings_broken == 3 and _u().routinely_broke, "AC15.1 a load restores the strike breaking")
	_check(int(_u().quiet_until.get("z", 0)) == 31, "AC13.10 a load restores each building's quiet")
	var legacy := {}
	_u().import_fields(legacy)
	_check(_u().active.is_empty() and _u().warning.is_empty() and _u().strike_free_until == 0 and _u().quiet_until.is_empty(),
		"AC15.1 AC13.10 an older save loads quiet")
	var validator := FileAccess.get_file_as_string("res://scripts/save_validation.gd")
	_check(validator.contains("\"strike_active\"") and validator.contains("\"strike_quiet_until\""), "AC15.1 AC13.10 the validator knows the fields")
	_fresh()


## AC16.5: Strike planning's two rows and their Show keys; an open list with its suggested actions, its building rows
## and their Bonus keys, Confirm paying the bonus.
func _test_strike_planning_tab() -> void:
	_fresh(-80.0)
	_company(4)
	LabourState.add_target_shift("test_low", "Low", -200.0, 40)
	var quiet := str(_u().eligible_buildings()[0])
	_u().quiet_until[quiet] = 15
	var shell: Control = PeopleDs2.new()
	add_child(shell)
	await get_tree().process_frame
	shell.call("show_tab", 2)
	await get_tree().process_frame
	var tab: Control = shell.call("body", 2)
	tab.call("_rebuild")
	var cool: Control = tab.find_child("PlanRow_cooldown", true, false)
	var vuln: Control = tab.find_child("PlanRow_vulnerable", true, false)
	var cool_title := str((cool.find_child("Title", true, false) as Label).text) if cool != null else ""
	var vuln_title := str((vuln.find_child("Title", true, false) as Label).text) if vuln != null else ""
	_check(cool_title == "Buildings on strike cooldown (1)" and vuln_title == "Buildings vulnerable to strikes in next 10 turns (3)",
		"AC16.5 the rows read their titles with counts (%s, %s)" % [cool_title, vuln_title])
	_check(tab.find_child("Show_cooldown", true, false) != null and tab.find_child("Show_vulnerable", true, false) != null
		and tab.find_child("PlanList_vulnerable", true, false) == null, "AC16.5 each row has a Show key, the lists shut at first")
	(tab.find_child("Show_vulnerable", true, false) as Button).pressed.emit()
	var list: Control = tab.find_child("PlanList_vulnerable", true, false)
	var order := PackedStringArray()
	if list != null:
		for c in list.get_child(0).get_children():
			order.append(str(c.name))
	_check(list != null and order.size() >= 3 and order[0] == "PolicyAction" and order[1] == "BonusAction" and order[2] == "BuildingBonusAction",
		"AC16.5 Show opens the list with the three suggested actions first (%s)" % ", ".join(order.slice(0, 3)))
	var bonus_row: Control = tab.find_child("BonusAction", true, false)
	_check(bonus_row != null and is_equal_approx(float(bonus_row.get_meta("cost", -1.0)), _u().company_bonus_cost(1))
		and bonus_row.find_child("BonusActionKey", true, false) != null, "AC16.5 One off bonus has its total beside its key")
	var some := str(_u().vulnerable(1)[0])
	var member: Control = tab.find_child("Plan_%s" % some, true, false)
	_check(member != null and member.find_child("Bonus_%s" % some, true, false) != null
		and is_equal_approx(float(member.get_meta("cost", -1.0)), _u().bonus_cost(some)), "AC16.5 each building row has its bonus cost and Bonus key")
	(tab.find_child("Show_cooldown", true, false) as Button).pressed.emit()
	_check(tab.find_child("PlanList_cooldown", true, false) != null and tab.find_child("PlanList_vulnerable", true, false) == null
		and tab.find_child("Plan_%s" % quiet, true, false) != null, "AC16.5 Show on the other row opens it and shuts the first")
	var labour_shown := false
	(tab.find_child("PolicyActionKey", true, false) as Button).pressed.emit()
	await get_tree().process_frame
	labour_shown = int(shell.get("_tab")) == 1
	_check(labour_shown, "AC16.5 the policies key opens the Labour tab")
	shell.call("show_tab", 2)
	await get_tree().process_frame
	tab.set("_list_open", "vulnerable")
	tab.call("_rebuild")
	(tab.find_child("Bonus_%s" % some, true, false) as Button).pressed.emit()
	var bed: Control = tab.find_child("BonusBed", true, false)
	_check(bed != null and str(bed.get_meta("words", "")).contains("cannot strike again for 11 turns"), "AC16.5 a Bonus key opens its bed")
	(tab.find_child("ConfirmBonus", true, false) as Button).pressed.emit()
	_check(int(_u().quiet_until.get(some, 0)) == 12 and tab.find_child("BonusBed", true, false) == null, "AC16.5 Confirm pays the bonus")
	shell.queue_free()
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
	_check(TelemetryState.SCHEMA_VERSION >= 7, "AC15.2 schema 7 or later")
	_fresh()


## AC16.1–AC16.3: the Strikes tab (its sub-tabs, its table, its keys) and the diagnostics rows.
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
	tab.set("_subtab", "")
	tab.call("_rebuild")
	var n := (_u().warning.buildings as Array).size()
	var up_key: Control = tab.find_child("StrikeTab_upcoming", true, false)
	var on_key: Control = tab.find_child("StrikeTab_ongoing", true, false)
	_check(up_key != null and str(up_key.get("text")) == "Upcoming Strikes (%d)" % n and bool(up_key.get("latched"))
		and on_key != null and str(on_key.get("text")) == "Ongoing Strikes (0)",
		"AC16.2 the sub-tabs count their buildings in brackets, Upcoming open during a warning")
	_check(_u().upcoming(8).size() == n and _u().upcoming(4).is_empty(), "AC16.2 Upcoming counts only strikes due within 5 turns")
	shell.call("_refresh_key_lamps")
	var keys: Array = shell.get("_keys")
	_check((keys[2].get("lamp") as Color).a == 0.0, "AC16.2 the Strikes key carries no lamp")
	_check(tab.find_child("WarningBoard", true, false) != null and tab.find_child("SettleAll", true, false) != null,
		"AC16.1 a warning shows its table and the key to settle every strike")
	var named := str((_u().warning.buildings as Array)[0])
	var board: Control = tab.find_child("WarningBoard", true, false)
	var headings: Control = board.find_child("StrikeHeadings", true, false)
	var labels := PackedStringArray()
	if headings != null:
		for l: Label in headings.find_children("*", "Label", true, false):
			labels.append(l.text)
	_check(labels == PackedStringArray(["Location", "Output loss", "Cost to manage", "Action"]), "AC16.1 the table's columns are labelled (%s)" % ", ".join(labels))
	var head: Control = board.find_child("AllStrikes", true, false)
	var head_title: Label = head.find_child("Title", true, false) if head != null else null
	_check(head != null and head_title != null and head_title.text == "All strikes (%d building%s)" % [n, "" if n == 1 else "s"]
		and not head.find_children("*", "Label", true, false).any(func(l: Label) -> bool: return l.text.contains("Output")),
		"AC16.1 the first row is All strikes (N buildings), here %d, without the output words" % n)
	var total := 0.0
	var loss := 0.0
	for iid in _u().warning.buildings:
		total += _u().pay_raise_cost(str(iid))
		loss += _u().expected_loss(str(iid))
	_check(head != null and is_equal_approx(float(head.get_meta("total", -1.0)), total) and is_equal_approx(float(head.get_meta("loss", -1.0)), loss),
		"AC16.1 All strikes carries the total to settle and its own output loss")
	var manage: Control = head.find_child("Manage", true, false) if head != null else null
	var settle_line: Control = manage.get_child(0) if manage != null and manage.get_child_count() == 2 else null
	var break_line: Control = manage.get_child(1) if settle_line != null else null
	_check(settle_line != null and settle_line.find_child("SettleCost", true, false) != null and settle_line.find_child("SettleAll", true, false) != null
		and break_line.find_child("BreakStrikeCost", true, false) != null and break_line.find_child("BreakStrikeAll", true, false) != null,
		"AC16.1 Settle and Break strike are two lines, each cost beside its key")
	var fold: Control = tab.find_child("StrikersFold", true, false)
	var member: Control = tab.find_child("Striker_%s" % named, true, false)
	_check(tab.find_child("StrikersFoldRow", true, false) != null and fold != null and not fold.visible and member != null and member.get_parent().name == "Strikers",
		"AC16.1 the buildings start folded under their own row")
	(tab.find_child("StrikersFoldRow", true, false) as Control).gui_input.emit(_left_click())
	fold = tab.find_child("StrikersFold", true, false)
	member = tab.find_child("Striker_%s" % named, true, false)
	_check(fold != null and fold.visible and member != null, "AC16.1 a click on the fold row shows them")
	_check(member != null and member.find_child("IconWell", true, false) != null, "AC16.1 each building shows the good it makes")
	var key: Button = tab.find_child("SettleAll", true, false)
	_check(str(key.get("title")) == "Settle" and str(key.get("detail")) == "", "AC16.1 the key reads Settle, its cost beside it, not on it")
	_check(tab.find_child("SettleBed", true, false) == null, "AC16.1 Settle's words are hidden until it is pressed")
	key.pressed.emit()
	var bed: Control = tab.find_child("SettleBed", true, false)
	_check(bed != null and str(bed.get_meta("words", "")).contains("none can start for %d turns" % LabourUnrest.STRIKE_FREE_TURNS),
		"AC16.1 Settle on All strikes opens what it does, with Confirm")
	(tab.find_child("CancelSettle", true, false) as Button).pressed.emit()
	_check(tab.find_child("SettleBed", true, false) == null and not _u().warning.is_empty(), "AC16.1 Cancel shuts it and settles nothing")
	head = tab.find_child("AllStrikes", true, false)
	member = tab.find_child("Striker_%s" % named, true, false)
	_check(member != null and member.find_child("BreakStrike_%s" % named, true, false) != null and head.find_child("BreakStrikeAll", true, false) != null,
		"AC16.1 every row has Break strike beside Settle")
	_check(is_equal_approx(float(head.get_meta("break", -1.0)), _sum_break()), "AC16.1 All strikes carries the total cost of breaking")
	(tab.find_child("BreakStrikeAll", true, false) as Button).pressed.emit()
	var break_bed: Control = tab.find_child("BreakStrikeBed", true, false)
	_check(break_bed != null and str(break_bed.get_meta("words", "")).contains("−20") and str(break_bed.get_meta("words", "")).contains("remembers it for good"),
		"AC16.1 Break strike on All strikes opens what it does to satisfaction")
	(tab.find_child("CancelBreakStrike", true, false) as Button).pressed.emit()
	_check(tab.find_child("BreakStrikeBed", true, false) == null and not _u().warning.is_empty(), "AC16.1 Cancel breaks nothing")
	(tab.find_child("StrikeTab_ongoing", true, false) as Control).emit_signal("pressed")
	_check(tab.find_child("OnStrike", true, false) != null and tab.find_child("NoStrikes", true, false) != null,
		"AC16.2 Ongoing with nobody on strike says so")
	var rows: Array = BuildingReadout.diagnostics(BuildingState.get_building(named), Catalog.get_recipe("r_005"), Catalog.get_building(FURNACE), false)
	var warned := false
	for r: Dictionary in rows:
		warned = warned or str(r.get("label", "")) == "Strike warning"
	_check(warned, "AC16.3 the diagnostics say the building is named to strike")
	_tick(10)
	tab.set("_subtab", "")
	tab.call("_rebuild")
	_check(tab.find_child("OnStrike", true, false) != null and tab.find_child("StrikeRecord", true, false) != null,
		"AC16.1 strikes on show the buildings on strike and the record")
	var striking := str(_u().active.keys()[0])
	var on := false
	for r: Dictionary in BuildingReadout.diagnostics(BuildingState.get_building(striking), Catalog.get_recipe(str(BuildingState.get_building(striking).recipe_id)), Catalog.get_building(str(BuildingState.get_building(striking).building_id)), false):
		on = on or str(r.get("label", "")) == "On strike"
	_check(on, "AC16.3 the diagnostics say the building is on strike")
	var on_text := str((tab.find_child("StrikeTab_ongoing", true, false) as Control).get("text"))
	_check(on_text == "Ongoing Strikes (%d)" % _u().active.size(), "AC16.2 Ongoing counts the buildings on strike (%s)" % on_text)
	(tab.find_child("Settle_%s" % striking, true, false) as Button).pressed.emit()
	(tab.find_child("ConfirmSettle", true, false) as Button).pressed.emit()
	_check(not _u().is_on_strike(striking) and _u().pay_raises.has(striking) and tab.find_child("SettleBed", true, false) == null,
		"AC16.1 Confirm settles that building's strike and shuts the bed")
	var page := SearchOverlay.strikes_page()
	_check(SearchOverlay.MECHANIC_ENTRIES.any(func(e: Dictionary) -> bool: return str(e.id) == PeopleDs2.StrikesTab.MECHANICS_ENTRY)
		and page.contains("−70") and page.contains("−90") and not page.contains(";") and not page.contains(" - ") and not page.contains("—"),
		"AC16.1 How strikes work opens a Mechanics page in plain copy")
	var scale: Control = tab.find_child("StrikeScale", true, false)
	scale.size = Vector2(420, scale.size.y)
	var spans: Array[Rect2] = []
	var clear := true
	for m: Dictionary in scale.call("marks"):
		var w := Plate.FONT_SEMI.get_string_size(str(m.text), HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		var span := Rect2(float(m.x), 0.0, w, 1.0)
		clear = clear and not spans.any(func(r: Rect2) -> bool: return r.intersects(span))
		spans.append(span)
	_check(clear and spans.size() >= 3, "AC16.1 the strike scale's printed marks never run into each other")
	var o: Dictionary = PeopleDs2.StrikesTab.outlook(10)
	_check(str(o.tone) == "warn" and int(o.turns) == 10, "AC16.1 the risk row reads a quarter can strike, with the turns to the next check")
	shell.queue_free()
	_fresh()
