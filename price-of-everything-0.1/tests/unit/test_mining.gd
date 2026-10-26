extends "res://tests/test_base.gd"
## Phase 4 of docs/pacing-labour-mining-licensing-spec.md: seams with working limits, deposit sizes, land and the
## seam card (scripts/mining_sites.gd, scripts/seam_cards.gd). Each test names the acceptance criteria (AC…) it
## checks.

const FEATURE := "mining"
const TAGS := {
	"_test_seam_save_round_trip": ["mining", "save"],
	"_test_land_units": ["mining", "construction"],
}

const MINE := "b_001"
const FURNACE := "b_002"
const FACTORY := "b_007"
const PUMP := "b_037"
## tile_7_4 has an endless coal seam, tile_6_8 a finite one (2,000 in the CSV), tile_8_4 coal and water.
const ENDLESS_TILE := "tile_7_4"
const FINITE_TILE := "tile_6_8"
const WATER_TILE := "tile_8_4"
const MiningSites := preload("res://scripts/mining_sites.gd")
const SeamCards := preload("res://scripts/seam_cards.gd")
const Staffing := preload("res://scripts/staffing.gd")


func _fresh() -> void:
	Modifiers.reset()
	MatchState.reset()
	Stockpile.clear_all()
	TurnManager.current_turn = 1
	LabourState.satisfaction = 0.0
	DecisionState.pending_queue.clear()


## A player's working on `tile`, fully staffed, at `level`.
func _mine(tile: String, level: int = 1, recipe: String = "r_001") -> String:
	BuildingState.tile_land_owned[tile] = 2000
	var iid: String = BuildingState.add_building(MINE, recipe, tile, MatchState.LOCAL_PLAYER, "")
	var b := BuildingState.get_building(iid)
	b.erase("staff_fill")
	b["level"] = level
	return iid


func _summary() -> Dictionary:
	var s := _fresh_production_summary()
	s["deposits_running_out"] = []
	return s


func _dig(iid: String) -> void:
	var b := BuildingState.get_building(iid)
	Production._produce_outputs(b, Catalog.get_recipe(str(b.recipe_id)), _summary())
	Production._flush_output_buffer()


## AC18.1, AC18.2: draw is level × throughput × staffing, nothing while down; caps by seam kind; NPCs and strikes
## don't count.
func _test_site_draw_and_caps() -> void:
	_fresh()
	var a := _mine(ENDLESS_TILE)
	var s := MiningSites.site(ENDLESS_TILE, "coal")
	_check(str(s.kind) == "endless" and is_equal_approx(float(s.free), 2.0) and is_equal_approx(float(s.max), 4.0)
		and is_equal_approx(float(s.draw), 1.0), "AC18.2 an endless seam is free to 2 and ends at 4; one L1 draws 1")
	var b := _mine(ENDLESS_TILE, 2)
	_check(is_equal_approx(float(MiningSites.site(ENDLESS_TILE, "coal").draw), 3.0), "AC18.1 a level 2 working draws 2")
	BuildingState.get_building(b)["level"] = 3
	_check(is_equal_approx(float(MiningSites.site(ENDLESS_TILE, "coal").draw), 4.5), "AC18.1 a level 3 working draws 3.5")
	BuildingState.get_building(b)["level"] = 1
	Modifiers.add({"id": "t_thru", "domain": "throughput", "target": "*", "pct": 20.0})
	_check(is_equal_approx(float(MiningSites.site(ENDLESS_TILE, "coal").draw), 2.4), "AC18.1 throughput +20% draws 1.2 a working")
	Modifiers.remove("t_thru")
	BuildingState.get_building(b)["staff_fill"] = 0.8
	_check(absf(float(MiningSites.site(ENDLESS_TILE, "coal").draw) - (1.0 + Staffing.run_fraction(BuildingState.get_building(b)))) < 0.001
		and Staffing.run_fraction(BuildingState.get_building(b)) < 1.0, "AC18.1 a working short of staff draws its run fraction")
	BuildingState.get_building(b).erase("staff_fill")
	LabourState.unrest.accident_down[b] = 2
	_check(is_equal_approx(float(MiningSites.site(ENDLESS_TILE, "coal").draw), 1.0), "AC18.1 a working down after an accident draws nothing")
	LabourState.unrest.accident_down.erase(b)
	LabourState.unrest.active[a] = 2
	_check(is_equal_approx(float(MiningSites.site(ENDLESS_TILE, "coal").draw), 2.0), "AC18.1 a strike does not lower draw")
	LabourState.unrest.active.clear()
	var npc: String = BuildingState.add_building(MINE, "r_001", ENDLESS_TILE, "npc_test", "")
	_check(is_equal_approx(float(MiningSites.site(ENDLESS_TILE, "coal").draw), 2.0) and MiningSites.m_for(BuildingState.get_building(npc)) == 1.0,
		"AC18.1 an NPC working never draws and pays no M")
	var f := MiningSites.site(FINITE_TILE, "coal")
	_check(str(f.kind) == "finite" and is_equal_approx(float(f.free), 3.0) and is_equal_approx(float(f.max), 6.0),
		"AC18.2 a finite seam is free to 3 and ends at 6")
	_check(str(MiningSites.kind(WATER_TILE, "water")) == "endless", "AC18.2 water counts as an endless seam")
	_fresh()


## AC18.3, AC18.4: M = 1 + c × over, continuous, on labour after the floor and on maintenance; c from
## extraction_cap_cost modifiers.
func _test_over_cap_cost() -> void:
	_fresh()
	var a := _mine(ENDLESS_TILE)
	var solo_labour := Production._calculate_labour_cost(BuildingState.get_building(a))
	var solo_maint := Production._calculate_maintenance_cost(BuildingState.get_building(a))
	_mine(ENDLESS_TILE)
	_check(is_equal_approx(MiningSites.m_for(BuildingState.get_building(a)), 1.0), "AC18.3 at the free cap M is 1")
	Modifiers.add({"id": "t_thru", "domain": "throughput", "target": "*", "pct": 10.0})
	var m := MiningSites.m_for(BuildingState.get_building(a))
	_check(absf(m - 1.2) < 0.0001, "AC18.3 M is continuous: 0.2 over the cap costs ×1.2 (M %.3f)" % m)
	Modifiers.remove("t_thru")
	_mine(ENDLESS_TILE, 2)
	var b := BuildingState.get_building(a)
	_check(is_equal_approx(MiningSites.m_for(b), 3.0), "AC18.3 two over the free cap is ×3")
	_check(absf(Production._calculate_labour_cost(b) - solo_labour * 3.0) < 0.001
		and absf(Production._calculate_maintenance_cost(b) - solo_maint * 3.0) < 0.001,
		"AC18.3 M multiplies the labour and maintenance of every working on the site")
	Modifiers.add({"id": "t_cap", "domain": "extraction_cap_cost", "target": "*", "pct": -25.0})
	_check(is_equal_approx(MiningSites.m_for(b), 2.5), "AC18.3 extraction_cap_cost −25% makes each working over +75%")
	Modifiers.remove("t_cap")
	# Labour cut 60% to the floor, then M 4: labour ×1.6 of base, not ×3.4.
	_fresh()
	var f1 := _mine(FINITE_TILE, 2)
	_mine(FINITE_TILE, 2)
	_mine(FINITE_TILE, 2)
	var fb := BuildingState.get_building(f1)
	Modifiers.add({"id": "t_lab", "domain": "labour_headcount", "target": "*", "pct": -60.0})
	var base := Production._base_labour_cost(fb)
	_check(is_equal_approx(MiningSites.m_for(fb), 4.0) and is_equal_approx(Production.labour_cost_factor(fb), EconomyConfig.LABOUR_FACTOR_MIN),
		"AC18.4 setup: three L2 on a finite seam, M 4, labour at its floor")
	_check(absf(Production._calculate_labour_cost(fb) - base * 1.6) < 0.001, "AC18.4 M applies after the labour floor: ×1.6, not ×3.4")
	_fresh()


## AC18.5: past the max every working runs at max / draw: outputs, power and the charge scale together.
func _test_past_max_scales() -> void:
	_fresh()
	var a := _mine(ENDLESS_TILE, 2)
	var solo_run := MatchState.run_multiplier(BuildingState.get_building(a))
	var solo_power := Production._effective_energy_req_f(BuildingState.get_building(a), Catalog.get_recipe("r_001"))
	_mine(ENDLESS_TILE, 2)
	_mine(ENDLESS_TILE, 2)
	var b := BuildingState.get_building(a)
	var s := MiningSites.site(ENDLESS_TILE, "coal")
	_check(is_equal_approx(float(s.draw), 6.0) and is_equal_approx(float(s.scale), 4.0 / 6.0) and is_equal_approx(float(s.m), 3.0),
		"AC18.5 three L2 on an endless seam draw 6: scale 4/6, M 3 (at the max)")
	_check(is_equal_approx(MatchState.run_multiplier(b), solo_run * 4.0 / 6.0), "AC18.5 the run multiplier carries the scale")
	_check(absf(Production._effective_energy_req_f(b, Catalog.get_recipe("r_001")) - solo_power * 4.0 / 6.0) < 0.01, "AC18.5 power scales with it")
	_fresh()


## AC18.6: a finite seam is charged what is dug (level, throughput, staffing); yield never charges it.
func _test_finite_charge() -> void:
	_fresh()
	Modifiers.remove("deposit_penalty_coal")
	var a := _mine(FINITE_TILE)
	MatchState.deposit_remaining[FINITE_TILE] = {"coal": 9999}
	_dig(a)
	var l1 := 9999 - MatchState.deposit_remaining_for(FINITE_TILE, "coal")
	MatchState.deposit_remaining[FINITE_TILE] = {"coal": 9999}
	BuildingState.get_building(a)["level"] = 2
	_dig(a)
	var l2 := 9999 - MatchState.deposit_remaining_for(FINITE_TILE, "coal")
	_check(l1 == 60 and l2 == 120, "AC18.6 level 2 digs and is charged twice level 1 (%d, %d)" % [l1, l2])
	BuildingState.get_building(a)["level"] = 1
	MatchState.deposit_remaining[FINITE_TILE] = {"coal": 9999}
	Modifiers.add({"id": "t_thru", "domain": "throughput", "target": "*", "pct": 20.0})
	_dig(a)
	_check(9999 - MatchState.deposit_remaining_for(FINITE_TILE, "coal") == 72, "AC18.6 throughput +20% is charged")
	Modifiers.remove("t_thru")
	MatchState.deposit_remaining[FINITE_TILE] = {"coal": 9999}
	Modifiers.add({"id": "t_yield", "domain": "recipe_output", "target": "*", "pct": 50.0})
	Modifiers.add({"id": "deposit_penalty_coal", "domain": "recipe_output", "target": "*", "target_match": {"good_internal": "coal"}, "pct": -30.0})
	_dig(a)
	_check(9999 - MatchState.deposit_remaining_for(FINITE_TILE, "coal") == 60, "AC18.6 yield (research, the −30% penalty) never charges")
	_fresh()


## AC18.7: the coal table of §8.3, from the site's M and the spec's mine upkeep basis (labour £9.50, maintenance
## £4, power £3.30 a turn at level 1; level 2 ×1.5 / ×1.8, level 3 ×2 / ×2.5) and coal at 60 × 0.7 a level.
func _test_coal_table() -> void:
	var rows := [
		[ENDLESS_TILE, [2], 0.33, -1.0], [ENDLESS_TILE, [3], 0.55, -1.0], [ENDLESS_TILE, [2, 2], 0.84, 0.43],
		[FINITE_TILE, [1, 1, 1], 0.40, -1.0], [FINITE_TILE, [3], 0.35, -1.0], [FINITE_TILE, [3, 2], 0.83, 0.42],
		[FINITE_TILE, [2, 2, 2], 1.09, 0.55],
	]
	var all_ok := true
	var said := PackedStringArray()
	for row: Array in rows:
		_fresh()
		var tile: String = row[0]
		for level: int in row[1]:
			_mine(tile, level)
		var m := MiningSites.m_for(BuildingState.get_building(MiningSites.site(tile, "coal").workings[0]))
		for discounted in [false, true]:
			var want: float = float(row[3]) if discounted else float(row[2])
			if want < 0.0:
				continue
			var labour := 0.0
			var upkeep := 0.0
			var coal := 0.0
			for level: int in row[1]:
				labour += 9.5 * BuildingLevels.mult("labour", level)
				upkeep += 4.0 * BuildingLevels.mult("maint", level)
				coal += 60.0 * 0.7 * BuildingLevels.mult("output", level)
			var power := 0.0
			for level: int in row[1]:
				power += 3.3 * BuildingLevels.mult("energy", level)
			var lab_f := 0.4 if discounted else 1.0
			var main_f := 0.6 if discounted else 1.0
			var per_coal := (labour * lab_f * m + upkeep * main_f * m + power) / coal
			all_ok = all_ok and absf(per_coal - want) <= 0.02
			said.append("%.2f" % per_coal)
	_check(all_ok, "AC18.7 the coal table of §8.3 is reproduced within £0.02 (%s)" % ", ".join(said))
	_fresh()


## AC19.1, AC19.2: finite seams ×3 after normalisation; endless stays endless; the demo's Magnate coal is 2,000.
func _test_deposit_sizes() -> void:
	var saved_rem: Dictionary = MatchState.deposit_remaining.duplicate(true)
	var saved_init: Dictionary = MatchState.deposit_initial.duplicate(true)
	var saved_terrain = MatchState._deposit_terrain
	var saved_rules: Dictionary = MatchState.ruleset.duplicate(true)
	var terrain := {"tiles": {Vector2i(0, 0): {"id": "t_seams", "deposits": ["coal(2000)", "iron_ore(4000)", "copper_ore(5000)", "water"]},
		Vector2i(1, 0): {"id": "t_big", "deposits": ["coal(5000)", "sand(1000)"]}}}
	MatchState.seed_deposits(terrain)
	_check(MatchState.deposit_remaining_for("t_seams", "coal") == 6000 and MatchState.deposit_remaining_for("t_seams", "iron_ore") == 12000
		and MatchState.deposit_remaining_for("t_seams", "copper_ore") == 15000 and MatchState.deposit_remaining_for("t_big", "sand") == 3000,
		"AC19.1 finite seams are tripled after normalisation")
	_check(MatchState.deposit_remaining_for("t_big", "coal") == -1, "AC19.1 a coal seam above 4,000 in the CSV stays endless")
	_check(MatchState.deposit_initial_for("t_seams", "coal") == 6000, "AC19.1 the starting size is kept for the seam card")
	MatchState.ruleset["victory_set"] = "standard"
	MatchState._apply_demo_deposit_overrides({"t_seams": {"coal": 2000}})
	_check(MatchState.deposit_remaining_for("t_seams", "coal") == 6000, "AC19.2 outside the demo the override does nothing")
	MatchState.ruleset["victory_set"] = "demo_itch"
	MatchState._apply_demo_deposit_overrides({"t_seams": {"coal": 2000}})
	_check(MatchState.deposit_remaining_for("t_seams", "coal") == 2000 and MatchState.deposit_initial_for("t_seams", "coal") == 2000,
		"AC19.2 under the demo rules the start's override sets the seam and its start")
	var start: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/starts/metal_magnate.json"))
	_check(int(((start.get("demo_deposit_overrides", {}) as Dictionary).get("tile_6_8", {}) as Dictionary).get("coal", 0)) == 2000,
		"AC19.2 Metal Magnate's start keeps its coal at 2,000 in the demo")
	MatchState.deposit_remaining = saved_rem
	MatchState.deposit_initial = saved_init
	MatchState._deposit_terrain = saved_terrain
	MatchState.ruleset = saved_rules


## AC20.1, AC20.2: land_units, mines 32 and the five factory kinds 20; the simulation reads it, art does not.
func _test_land_units() -> void:
	_fresh()
	var mine_def := Catalog.get_building(MINE)
	_check(Catalog.land_units(mine_def) == 32.0 and int(mine_def.tile_size_used) == 25, "AC20.1 a mine takes 32 land, drawn at 25")
	var factories_ok := true
	for bid in ["b_007", "b_008", "b_009", "b_010", "b_030"]:
		factories_ok = factories_ok and Catalog.land_units(Catalog.get_building(bid)) == 20.0
	_check(factories_ok, "AC20.1 the five factory kinds take 20")
	_check(Catalog.land_units(Catalog.get_building(FURNACE)) == float(Catalog.get_building(FURNACE).tile_size_used),
		"AC20.1 a blank land_units falls back to the drawn size")
	var iid := _mine(ENDLESS_TILE)
	_check(is_equal_approx(BuildingState.space_used(BuildingState.get_building(iid)), 32.0), "AC20.2 a mine uses 32 of its tile")
	_check(is_equal_approx(Construction.placing_size(MINE), 32.0), "AC20.2 a new mine reserves 32")
	var src := FileAccess.get_file_as_string("res://scripts/authored_slot_sizes.gd")
	_check(src.contains("tile_size_used") and not src.contains("land_units"), "AC20.2 the art keeps reading tile_size_used")
	_fresh()


## AC21.1: the card once a finite seam is at a quarter of its start, for that site.
func _test_seam_card_offered_once() -> void:
	_fresh()
	var was_enabled := DecisionState.enabled
	DecisionState.enabled = true
	DecisionState.auto_resolve = false
	var a := _mine(FINITE_TILE)
	MatchState.deposit_initial[FINITE_TILE] = {"coal": 1000}
	MatchState.deposit_remaining[FINITE_TILE] = {"coal": 400}
	_dig(a)
	_check(DecisionState.pending_queue.is_empty(), "AC21.1 no card above a quarter")
	MatchState.deposit_remaining[FINITE_TILE] = {"coal": 260}
	_dig(a)
	var card: Dictionary = DecisionState.pending_queue[0] if not DecisionState.pending_queue.is_empty() else {}
	_check(str(card.get("def_id", "")) == "seam_running_out" and str((card.get("target", {}) as Dictionary).get("tile_id", "")) == FINITE_TILE
		and str((card.get("target", {}) as Dictionary).get("token", "")) == "coal", "AC21.1 at a quarter the card comes for that site")
	var view := DecisionState.pending_view(str(card.get("uid", "")))
	var ids := PackedStringArray()
	for c: Dictionary in view.get("choices", []):
		ids.append(str(c.id))
	_check(ids == PackedStringArray(["deeper_shaft", "rob_pillars", "heavy_blasting", "sell_reserves", "carry_on"]),
		"AC21.1 it offers the five choices (%s)" % ", ".join(ids))
	DecisionState.pending_queue.clear()
	_dig(a)
	_check(DecisionState.pending_queue.is_empty(), "AC21.1 it comes once per site")
	DecisionState.enabled = was_enabled
	_fresh()


## AC21.2: a deeper shaft: its cost, 2 turns offline, +40%, then labour ×1.4 and power ×1.5.
func _test_deeper_shaft() -> void:
	_fresh()
	var a := _mine(FINITE_TILE)
	var b := BuildingState.get_building(a)
	MatchState.deposit_remaining[FINITE_TILE] = {"coal": 500}
	var labour0 := Production._calculate_labour_cost(b)
	var power0 := Production._effective_energy_req_f(b, Catalog.get_recipe("r_001"))
	var target := MatchState.seams.target_for(FINITE_TILE, "coal")
	var cost := MatchState.seams.shaft_cost(FINITE_TILE, "coal")
	_check(cost > Production._base_labour_cost(b) * Production.labour_cost_factor(b) * 2.0, "AC21.2 it costs two turns of wages plus a kit")
	MatchState.money = 100000.0
	DecisionState._execute_effects(DecisionState._find_choice(DecisionState.DECISION_DEFINITIONS["seam_running_out"], "deeper_shaft").effects, target)
	_check(absf(MatchState.money - (100000.0 - cost)) < 0.01, "AC21.2 the shaft is paid for")
	_check(MatchState.deposit_remaining_for(FINITE_TILE, "coal") == 700, "AC21.2 the seam gains 40%")
	_check(MatchState.seams.is_offline(FINITE_TILE, "coal") and is_equal_approx(float(MiningSites.site(FINITE_TILE, "coal").draw), 0.0),
		"AC21.2 the site goes offline")
	MatchState.seams.age()
	_check(MatchState.seams.is_offline(FINITE_TILE, "coal"), "AC21.2 still offline the next turn")
	MatchState.seams.age()
	_check(not MatchState.seams.is_offline(FINITE_TILE, "coal"), "AC21.2 back after 2 turns")
	_check(absf(Production._calculate_labour_cost(b) - labour0 * 1.4) < 0.001
		and absf(Production._effective_energy_req_f(b, Catalog.get_recipe("r_001")) - power0 * 1.5) < 0.01,
		"AC21.2 labour ×1.4 and power ×1.5 until the seam ends")
	MatchState.deplete_deposit(FINITE_TILE, "coal", 700)
	_check(MatchState.seams.mode_of(FINITE_TILE, "coal") == "" and absf(Production._calculate_labour_cost(b) - labour0) < 0.001,
		"AC21.2 and no longer once it has")
	_fresh()


## AC21.3: robbing the pillars: +25%, labour ×1.5, the accident chance by safety, and the collapse at the end.
func _test_rob_the_pillars() -> void:
	_fresh()
	var a := _mine(FINITE_TILE)
	var b := BuildingState.get_building(a)
	MatchState.deposit_remaining[FINITE_TILE] = {"coal": 400}
	var labour0 := Production._calculate_labour_cost(b)
	MatchState.seams.apply("rob_pillars", FINITE_TILE, "coal")
	_check(MatchState.deposit_remaining_for(FINITE_TILE, "coal") == 500 and absf(Production._calculate_labour_cost(b) - labour0 * 1.5) < 0.001,
		"AC21.3 robbing adds 25% and labour ×1.5")
	_check(is_equal_approx(SeamCards._safety_factor(), 1.0), "AC21.3 standard safety keeps 3%")
	LabourState.set_workforce_policy_enabled(LabourState.WORKFORCE_POLICY_LAX_SAFETY, true)
	_check(is_equal_approx(SeamCards._safety_factor(), 2.0), "AC21.3 Minimal safety doubles it")
	LabourState.set_workforce_policy_enabled(LabourState.WORKFORCE_POLICY_LAX_SAFETY, false)
	LabourState.set_workforce_policy_enabled(LabourState.WORKFORCE_POLICY_STRICT_SAFETY, true)
	_check(is_equal_approx(SeamCards._safety_factor(), 0.5), "AC21.3 High safety halves it")
	LabourState.set_workforce_policy_enabled(LabourState.WORKFORCE_POLICY_STRICT_SAFETY, false)
	var accidents := 0
	for t in range(2, 202):
		LabourState.unrest.accident_down.clear()
		MatchState.seams.tick(t)
		if LabourState.unrest.is_down(a):
			accidents += 1
	_check(accidents >= 1 and accidents <= 15, "AC21.3 about 3%% of turns bring an accident (%d in 200)" % accidents)
	LabourState.unrest.accident_down.clear()
	MatchState.deplete_deposit(FINITE_TILE, "coal", 500)
	_check(not BuildingState.buildings.has(a), "AC21.3 when the seam ends the robbed workings collapse")
	_fresh()


## AC21.4, AC21.6: heavy blasting's seeded rolls: double digs, roof falls and a lost seam, the same for the same seed.
func _test_heavy_blasting() -> void:
	_fresh()
	var a := _mine(FINITE_TILE)
	var runs: Array = []
	for attempt in 2:
		MatchState.seams.reset()
		MatchState.deposit_remaining[FINITE_TILE] = {"coal": 99999}
		MatchState.seams.apply("heavy_blasting", FINITE_TILE, "coal")
		var seq := PackedStringArray()
		for t in range(1, 301):
			MatchState.seams.age()
			MatchState.seams.tick(t)
			if MatchState.deposit_remaining_for(FINITE_TILE, "coal") == 0:
				seq.append("L")
				MatchState.deposit_remaining[FINITE_TILE] = {"coal": 99999}
				MatchState.seams.apply("heavy_blasting", FINITE_TILE, "coal")
				continue
			seq.append("D" if MatchState.seams.dig_mult(BuildingState.get_building(a)) == 2.0 else ("R" if MatchState.seams.is_offline(FINITE_TILE, "coal") else "."))
		runs.append("".join(seq))
	var first: String = runs[0]
	_check(runs[0] == runs[1], "AC21.6 the same seed gives the same blasting")
	var d := first.count("D")
	var r := first.count("R")
	var l := first.count("L")
	_check(d > 30 and r > 5 and l >= 1, "AC21.4 blasting brings double digs, roof falls and lost seams (%d, %d, %d in 300)" % [d, r, l])
	MatchState.deposit_remaining[FINITE_TILE] = {"coal": 9999}
	MatchState.seams.double_dig[SeamCards.key(FINITE_TILE, "coal")] = true
	Modifiers.remove("deposit_penalty_coal")
	_dig(a)
	_check(9999 - MatchState.deposit_remaining_for(FINITE_TILE, "coal") == 120, "AC21.4 a double dig is charged double")
	_fresh()


## AC21.5: selling with the reserves: the workings go to another company, paid once at their price plus half the seam.
func _test_sell_with_reserves() -> void:
	_fresh()
	var a := _mine(FINITE_TILE)
	MatchState.deposit_remaining[FINITE_TILE] = {"coal": 1000}
	var value := MatchState.seams.sale_value(FINITE_TILE, "coal")
	var expected := float(preload("res://scripts/building_price.gd").sale_price(BuildingState.get_building(a))) \
		+ 1000.0 * MarketState.get_price("g_001") * 0.5
	_check(absf(value - expected) < 0.01, "AC21.5 the sale is the building's price plus the seam at half market")
	var money0 := MatchState.money
	var target := MatchState.seams.target_for(FINITE_TILE, "coal")
	DecisionState._execute_effects(DecisionState._find_choice(DecisionState.DECISION_DEFINITIONS["seam_running_out"], "sell_reserves").effects, target)
	_check(not BuildingState.is_player_owned(BuildingState.get_building(a)) and absf(MatchState.money - money0 - value) < 0.01,
		"AC21.5 the working changes hands and is paid for once")
	_fresh()


## AC21.6, AC23.1: the card's state and RNG saved; draw and M never saved; old saves load with none.
func _test_seam_save_round_trip() -> void:
	_fresh()
	MatchState.seams.offered["tile_6_8|coal"] = true
	MatchState.seams.modes["tile_6_8|coal"] = "blasting"
	MatchState.seams.offline["tile_6_8|coal"] = 1
	MatchState.seams.tick(5)
	var snap: Dictionary = MatchState.export_state()
	for key in ["seam_offered", "seam_modes", "seam_offline", "seam_rng_seed", "seam_rng_state", "deposit_initial"]:
		_check(snap.has(key), "AC21.6 the save carries %s" % key)
	_check(not snap.has("seam_draw") and not snap.has("site_m"), "AC23.1 draw and M are not saved")
	var fields := MatchState.seams.export_fields()
	var next_roll := MatchState.seams._rng.randf()
	MatchState.seams.reset()
	MatchState.seams.import_fields(fields)
	_check(str(MatchState.seams.mode_of("tile_6_8", "coal")) == "blasting" and MatchState.seams.is_offline("tile_6_8", "coal")
		and is_equal_approx(MatchState.seams._rng.randf(), next_roll), "AC21.6 a load restores the card's state and its RNG")
	MatchState.seams.import_fields({})
	_check(MatchState.seams.offered.is_empty() and MatchState.seams.modes.is_empty(), "AC23.1 an older save loads with no card state")
	_check(FileAccess.get_file_as_string("res://scripts/save_validation.gd").contains("\"seam_modes\""), "AC21.6 the validator knows the fields")
	_fresh()


## AC23.2: telemetry schema 8 carries the sites over their free cap and the highest M, and transmits them.
func _test_seam_telemetry() -> void:
	_fresh()
	_mine(ENDLESS_TILE, 2)
	_mine(ENDLESS_TILE, 2)
	_mine(FINITE_TILE)
	var summary := {
		"money_in": 0.0, "money_out": 0.0,
		"goods_sales_revenue": 0.0, "power_sales_revenue": 0.0,
		"goods_purchased_cost": 0.0, "labour_paid": 0.0, "maintenance_paid": 0.0,
		"taxes_paid": 0.0, "produced": {}, "power_supply": 0, "power_demand": 0,
	}
	var row: Dictionary = TelemetryState._build_row(summary)
	_check(int(row.get("over_cap_sites", -1)) == 1 and is_equal_approx(float(row.get("max_site_m", 0.0)), 3.0),
		"AC23.2 the turn row counts sites over their free cap and the highest M")
	var sent: Dictionary = TelemetryState.balancing_payload({"run_id": "m8", "turns": [row]}).turns[0]
	_check(int(sent.over_cap_sites) == 1 and is_equal_approx(float(sent.max_site_m), 3.0) and TelemetryState.SCHEMA_VERSION == 8,
		"AC23.2 schema 8 transmits them")
	_check(FileAccess.get_file_as_string("res://tools/telemetry/Code.gs").contains('FIXED.push("over_cap_sites", "max_site_m")'),
		"AC23.2 the receiver appends their columns")
	_fresh()


## AC22.1: the tile view's seam line.
func _test_seam_words() -> void:
	_fresh()
	_mine(FINITE_TILE)
	BuildingState.get_building(_mine(FINITE_TILE))["staff_fill"] = 0.0
	var b := BuildingState.get_building(_mine(FINITE_TILE))
	b["level"] = 1
	Modifiers.add({"id": "t_thru", "domain": "throughput", "target": "*", "pct": 25.0})
	MatchState.deposit_remaining[FINITE_TILE] = {"coal": 4120}
	var words := MiningSites.seam_words(FINITE_TILE, "coal")
	_check(words == "Coal seam. Drawing 2.5 of 3 free. Limit 6. 4,120 left.", "AC22.1 the seam line reads %s" % words)
	_check(MiningSites.seam_words(ENDLESS_TILE, "coal").ends_with("Limit 4. Never runs out."), "AC22.1 an endless seam never runs out")
	_fresh()


## AC22.2: the construct and upgrade dialogs show the seam after the action and refuse one that adds nothing.
func _test_construct_and_upgrade_seam() -> void:
	_fresh()
	MatchState.money = 100000.0
	var a := _mine(ENDLESS_TILE, 2)
	var after := MiningSites.site_after(MINE, "r_001", ENDLESS_TILE, 2)
	_check(MiningSites.after_words(after) == "Takes the seam to 4 of 2 free. Labour and upkeep here ×3.", "AC22.2 a build reads %s" % MiningSites.after_words(after))
	var q: Dictionary = preload("res://scripts/construction_rules.gd").quote(MINE, "r_001", ENDLESS_TILE, {}, {})
	var seam_said := false
	for w: Dictionary in q.get("warnings", []):
		seam_said = seam_said or str(w.get("key", "")) == "seam"
	_check(seam_said, "AC22.2 the construct quote carries the seam line")
	_mine(ENDLESS_TILE, 2)
	_check(preload("res://scripts/construction_rules.gd").seam_block("r_001", ENDLESS_TILE) != "", "AC22.2 a seam at its limit refuses another build")
	q = preload("res://scripts/construction_rules.gd").quote(MINE, "r_001", ENDLESS_TILE, {}, {})
	var blocked := false
	for blk: Dictionary in q.get("blocks", []):
		blocked = blocked or str(blk.get("key", "")) == "seam_full"
	_check(blocked and not bool(q.get("ok", true)), "AC22.2 and the construct quote says so")
	var pv: Dictionary = BuildingWorks.preview_upgrade(a)
	_check(str(pv.get("seam_reason", "")) != "", "AC22.2 the upgrade preview refuses a working on a full seam")
	var gate := BuildingLevels.research_gate("mine", 3)
	if gate != "":
		ResearchState.grant_unlock(gate)
	var started: Dictionary = BuildingWorks.start_upgrade(a, "tile")
	_check(not bool(started.get("ok", true)) and str(started.get("reason", "")).contains("limit"), "AC22.2 and the upgrade itself is refused (%s)" % str(started.get("reason", "")))
	_fresh()
	var c := _mine(FINITE_TILE)
	var pv2: Dictionary = BuildingWorks.preview_upgrade(c)
	_check(str(pv2.get("seam_reason", "")) == "" and is_equal_approx(float((pv2.get("seam", {}) as Dictionary).get("draw", 0.0)), 2.0),
		"AC22.2 the upgrade preview shows the seam at level 2")
	_fresh()


## AC22.3: building detail's Seam check: green within the free cap, amber over it, red at the limit.
func _test_seam_check() -> void:
	_fresh()
	var a := _mine(ENDLESS_TILE)
	_check(str(BuildingReadout.seam_check(BuildingState.get_building(a)).tone) == "ok", "AC22.3 within the free cap the Seam check is green")
	_mine(ENDLESS_TILE, 2)
	var mid := BuildingReadout.seam_check(BuildingState.get_building(a))
	_check(str(mid.tone) == "warn" and str(mid.detail).contains("×2"), "AC22.3 over it amber, with M")
	_mine(ENDLESS_TILE)
	_check(str(BuildingReadout.seam_check(BuildingState.get_building(a)).tone) == "bad", "AC22.3 at the limit red")
	var furnace: String = BuildingState.add_building(FURNACE, "r_005", "tile_9_9", MatchState.LOCAL_PLAYER, "")
	_check(str(BuildingReadout.seam_check(BuildingState.get_building(furnace)).tone) == "off", "AC22.3 off for a building that mines nothing")
	var plant := BuildingReadout.plant_checks(BuildingState.get_building(a), Catalog.get_recipe("r_001"), false)
	_check(plant.any(func(c: Dictionary) -> bool: return str(c.key) == "seam" and str(c.get("icon", "")) == "deposit"), "AC22.3 it stands in the Plant stage")
	_fresh()


## AC22.4: the build forecast includes M and the limit for the mine it would add.
func _test_forecast_includes_m() -> void:
	_fresh()
	var alone: Dictionary = BuildForecast.project(MINE, "r_001", ENDLESS_TILE)
	_mine(ENDLESS_TILE, 2)
	var crowded: Dictionary = BuildForecast.project(MINE, "r_001", ENDLESS_TILE)
	var lab_alone := float((alone.get("breakdown", {}) as Dictionary).get("labour", 0.0))
	var lab_crowded := float((crowded.get("breakdown", {}) as Dictionary).get("labour", 0.0))
	_check(lab_alone > 0.0 and absf(lab_crowded - lab_alone * 2.0) < 0.01, "AC22.4 a third working on an endless seam is forecast at ×2 labour (%.2f, %.2f)" % [lab_alone, lab_crowded])
	_fresh()

