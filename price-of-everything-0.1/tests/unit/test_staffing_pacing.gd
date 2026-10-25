extends "res://tests/test_base.gd"
## Phase 2 of docs/pacing-labour-mining-licensing-spec.md: staffing, construction and upgrade pacing, the
## purchase closing and Andrew Keeler as Expansion Director. Each test names the acceptance criteria (AC…)
## it checks.

const FEATURE := "staffing"
const TAGS := {
	"_test_fill_starts_when_construction_begins": ["staffing", "construction"],
	"_test_fill_ticks_and_carries_to_the_building": ["staffing", "construction"],
	"_test_pending_purchases_save": ["staffing", "save"],
	"_test_diagnostics_staffing_row": ["staffing", "ui"],
}

const MINE := "b_001"
const FURNACE := "b_002"
const FACTORY := "b_007"
const TILE := "tile_9_9"
const Staffing := preload("res://scripts/staffing.gd")
const BuildingMarketTab := preload("res://scripts/building_market_panel.gd")
## Satisfaction for each hiring band: fast (+50 and up), normal, slow (under −5).
const BAND_SATISFACTION := {"fast": 60.0, "normal": 0.0, "slow": -30.0}


func _fresh(satisfaction: float = 0.0) -> void:
	Modifiers.reset()
	MatchState.reset()
	Stockpile.clear_all()
	TurnManager.current_turn = 1
	LabourState.satisfaction = satisfaction


func _building(building_id: String, recipe_id: String, owner: String = MatchState.LOCAL_PLAYER) -> Dictionary:
	BuildingState.tile_land_owned[TILE] = 400
	var iid := BuildingState.add_building(building_id, recipe_id, TILE, owner, "")
	return BuildingState.buildings[iid]


func _stock_kit(building_id: String) -> void:
	var reqs: Dictionary = Construction.requirements_for(building_id)
	for gid in reqs:
		Stockpile.add(TILE, str(gid), int(reqs[gid]))


func _seat_expansion_director() -> bool:
	return AdvisorState.seat_founder(AdvisorState.EXPANSION_DIRECTOR_SEAT)


## AC6.1: hiring starts when construction begins, at 0 (half with the Expansion Director); a project still
## waiting for its kit does not hire.
func _test_fill_starts_when_construction_begins() -> void:
	_fresh()
	_stock_kit(FURNACE)
	var iid := Construction.start_on_tile(FURNACE, "r_005", TILE)
	var project: Dictionary = Construction.construction_projects.get(iid, {})
	_check(project.has("staff_fill") and is_zero_approx(float(project.staff_fill)),
		"AC6.1 a build placed with its kit on the tile starts hiring at 0")

	var gid := str(Construction.requirements_for(FURNACE).keys()[0])
	Construction.construction_projects["test_awaiting"] = {
		"instance_id": "test_awaiting", "building_id": FURNACE, "recipe_id": "r_005", "tile_id": TILE,
		"status": Construction.STATUS_AWAITING_MATERIALS, "required_materials": {gid: 1},
		"missing_materials": {gid: 1}, "turns_remaining": 5, "construction_duration": 5, "level": 1,
	}
	Construction.claim_materials()
	_check(not (Construction.construction_projects["test_awaiting"] as Dictionary).has("staff_fill"),
		"AC6.1 a project still waiting for materials does not hire")
	Stockpile.add(TILE, gid, 1)
	Construction.claim_materials()
	var claimed: Dictionary = Construction.construction_projects["test_awaiting"]
	_check(str(claimed.status) == Construction.STATUS_UNDER_CONSTRUCTION and is_zero_approx(float(claimed.get("staff_fill", -1.0))),
		"AC6.1 the materials claim starts construction and hiring at 0")

	_fresh()
	_check(_seat_expansion_director(), "AC6.1 Andrew takes the Expansion Director seat")
	_stock_kit(FURNACE)
	var fast_iid := Construction.start_on_tile(FURNACE, "r_005", TILE)
	_check(is_equal_approx(float((Construction.construction_projects[fast_iid] as Dictionary).get("staff_fill", 0.0)), 0.5),
		"AC6.1 with the Expansion Director a new site starts half staffed")
	_fresh()


## AC6.2: fill rises 1/fill turns per tick with the construction countdown, comes with the building and keeps
## rising; a building without the key is fully staffed.
func _test_fill_ticks_and_carries_to_the_building() -> void:
	_fresh(BAND_SATISFACTION.normal)
	_stock_kit(FURNACE)
	var iid := Construction.start_on_tile(FURNACE, "r_005", TILE)
	Construction.tick_turn()
	_check(is_equal_approx(float((Construction.construction_projects[iid] as Dictionary).staff_fill), 0.125),
		"AC6.2 one construction tick hires 1/8 at normal satisfaction")
	for _i in 4:
		Production.tick_staffing()
		Construction.tick_turn()
	var b: Dictionary = BuildingState.buildings.get(iid, {})
	_check(not b.is_empty() and is_equal_approx(Staffing.fill(b), 0.625),
		"AC6.2 the finished furnace brings its 5 turns of hiring (62.5%)")
	Production.tick_staffing()
	_check(is_equal_approx(Staffing.fill(b), 0.75), "AC6.2 hiring goes on after completion")
	Production.tick_staffing()
	Production.tick_staffing()
	_check(not b.has("staff_fill"), "AC6.2 a fully staffed building drops the key")
	var starting := _building(MINE, "r_001")
	_check(is_equal_approx(Staffing.run_fraction(starting), 1.0) and is_equal_approx(Staffing.hired_share(starting), 1.0),
		"AC6.2 a building without the key (starting, old save) is fully staffed")
	LabourState.satisfaction = BAND_SATISFACTION.fast
	starting["staff_fill"] = 0.0
	Production.tick_staffing()
	_check(is_equal_approx(Staffing.fill(starting), 0.2), "AC6.2 content staff hire in 5 turns")
	LabourState.satisfaction = BAND_SATISFACTION.slow
	starting["staff_fill"] = 0.0
	Production.tick_staffing()
	_check(is_equal_approx(Staffing.fill(starting), 1.0 / 12.0), "AC6.2 unhappy staff hire in 12 turns")
	_fresh()


## AC6.3, AC6.4: below 70% the building does not run and carries the staffing reason; from 70% it runs at its
## fill; labour is paid on the hired share, at the idle share while it waits.
func _test_run_fraction_wages_and_gate() -> void:
	_fresh()
	LabourState.policy_throughput_enabled = false
	var mine := _building(MINE, "r_001")
	var recipe: Dictionary = Catalog.get_recipe("r_001")
	var full_out := BuildingStatus.effective_output_qty(mine, recipe)
	var full_labour := Production._calculate_labour_cost(mine, recipe)
	mine["staff_fill"] = 0.75
	_check(is_equal_approx(MatchState.startup_capacity_multiplier(mine), 0.75) and is_equal_approx(MatchState.run_multiplier(mine), 0.75),
		"AC6.3 at 75% staffed the run fraction and run multiplier are 0.75")
	_check(BuildingStatus.effective_output_qty(mine, recipe, true) == int(round(float(full_out) * 0.75))
		and BuildingStatus.effective_output_qty(mine, recipe) == full_out,
		"AC6.3 this turn's output scales with the run fraction; the standing rate does not")
	_check(is_equal_approx(Production._calculate_labour_cost(mine, recipe), full_labour * 0.75),
		"AC6.4 labour is paid on the hired share")
	mine["staff_fill"] = 0.5
	_check(is_zero_approx(MatchState.startup_capacity_multiplier(mine)), "AC6.3 below 70% the run fraction is 0")
	LabourState.set_idle_labour_pay_share(0.5)
	_check(is_equal_approx(Production.labour_charge(mine, false, recipe), full_labour * 0.5 * 0.5),
		"AC6.4 an idle, half staffed building pays the idle share of its hired share")
	Production._process_production()
	var reason: Dictionary = Production.blocked_reason_by_building.get(str(mine.instance_id), {})
	_check(str(reason.get("code", "")) == "staffing" and not Production.last_turn_run.has(str(mine.instance_id)),
		"AC6.3 a building below 70% does not run and says it is short of staff")
	LabourState.policy_throughput_enabled = false
	_fresh()


## AC6.5, AC6.6: an upgrade rebases the hires onto the bigger headcount and the old output never falls; cancelling
## restores them; a recipe switch keeps them.
func _test_upgrade_rebases_staff() -> void:
	_fresh()
	var b := _building(FURNACE, "r_005")
	Staffing.begin_upgrade(b, 2)
	_check(is_equal_approx(Staffing.fill(b), 1.0 / 1.5) and int(b.staff_level) == 2,
		"AC6.5 works start: the level 1 crew is two thirds of level 2's headcount")
	_check(is_equal_approx(Staffing.run_fraction(b), 1.0) and is_equal_approx(Staffing.hired_share(b), 1.0),
		"AC6.5 during the works it runs and pays exactly as before")
	Staffing.cancel_upgrade(b)
	_check(not b.has("staff_fill") and not b.has("staff_level"), "AC6.5 cancelling restores the full level 1 crew")
	Staffing.begin_upgrade(b, 2)
	b["level"] = 2
	Staffing.finish_upgrade(b)
	_check(is_equal_approx(Staffing.run_fraction(b), BuildingLevels.mult("output", 1) / BuildingLevels.mult("output", 2)),
		"AC6.5 finished but short of new staff, it still makes the level 1 output")
	Staffing.tick(b)
	_check(Staffing.run_fraction(b) >= 0.79, "AC6.5 past 70% of the new headcount it runs at its fill")
	var before := Staffing.fill(b)
	BuildingWorks.pending_retrofits.append({"instance_id": str(b.instance_id), "from_recipe": "r_005", "to_recipe": "r_005",
		"turns_remaining": 1, "labour_fraction": 0.5})
	BuildingWorks.tick_retrofits()
	_check(is_equal_approx(Staffing.fill(b), before), "AC6.6 a recipe switch keeps the staff")
	_fresh()


## AC6.7: a deposit is charged its base draw times the staffing run fraction.
func _test_deposit_charged_by_staffing() -> void:
	_fresh()
	var tile := "tile_6_8"  # has a coal deposit
	var inst: String = BuildingState.add_building(MINE, "r_001", tile)
	MatchState.reveal_deposit(tile, "coal")
	MatchState.deposit_remaining[tile] = {"coal": 999}
	var mine: Dictionary = BuildingState.get_building(inst)
	Production._produce_outputs(mine, Catalog.get_recipe("r_001"), _fresh_production_summary())
	Production._flush_output_buffer()
	var full_draw := 999 - MatchState.deposit_remaining_for(tile, "coal")
	MatchState.deposit_remaining[tile] = {"coal": 999}
	mine["staff_fill"] = 0.75
	Production._produce_outputs(mine, Catalog.get_recipe("r_001"), _fresh_production_summary())
	Production._flush_output_buffer()
	var staffed_draw := 999 - MatchState.deposit_remaining_for(tile, "coal")
	_check(full_draw > 0 and staffed_draw == int(round(float(full_draw) * 0.75)),
		"AC6.7 a 75%% staffed mine draws 75%% of its base from the deposit (%d of %d)" % [staffed_draw, full_draw])
	_fresh()


## AC6.8: the half capacity start is retired.
func _test_half_capacity_start_retired() -> void:
	_fresh()
	_check(not ("construct_start_half_capacity" in MatchState) and not MatchState.has_method("set_construct_start_half_capacity"),
		"AC6.8 the half capacity setting is gone")
	var snap: Dictionary = MatchState.export_state()
	_check(not snap.has("construct_start_half_capacity"), "AC6.8 the flag is no longer saved")
	snap["construct_start_half_capacity"] = true
	MatchState.import_state(snap)
	_check(not MatchState.export_state().has("construct_start_half_capacity"), "AC6.8 a save that carries the flag still loads")
	var b := _building(MINE, "r_001")
	b["startup_half_capacity"] = true
	_check(is_equal_approx(MatchState.startup_capacity_multiplier(b), 1.0), "AC6.8 an old building's half capacity flag is ignored")
	_fresh()


## AC6.9: the §7.7 time to first output table, reproduced turn by turn from the real durations, hiring and
## closing. Ticks: hiring on buildings, then construction (which hires on its projects and promotes), then the
## building runs if staffed, then closing at the end of the turn.
func _test_time_to_first_output_table() -> void:
	var expected := {
		MINE: {"fast": 4, "normal": 6, "slow": 9},
		FURNACE: {"fast": 5, "normal": 6, "slow": 9},
		FACTORY: {"fast": 6, "normal": 6, "slow": 9},
	}
	var recipes := {MINE: "r_001", FURNACE: "r_005", FACTORY: "r_056"}
	var lines: PackedStringArray = ["build      fast normal slow"]
	for andrew: bool in [false, true]:
		for bid: String in [MINE, FURNACE, FACTORY]:
			var row := "%s%s" % [Catalog.get_building_display_name(bid), " + Andrew" if andrew else ""]
			for band: String in ["fast", "normal", "slow"]:
				var got := _first_output_turn(bid, str(recipes[bid]), float(BAND_SATISFACTION[band]), andrew)
				var want: int = int((expected[bid] as Dictionary)[band])
				if andrew:
					want = {"fast": 3 if bid == FACTORY else 2, "normal": 3 if bid == FACTORY else 2, "slow": 3}[band]
				_check(got == want, "AC6.9 %s, %s hiring: first output on turn %d (got %d)" % [row, band, want, got])
				row += "  %d" % got
			lines.append(row)
	var bought_row := "Bought building"
	for band: String in ["fast", "normal", "slow"]:
		var got := _first_output_after_offer(float(BAND_SATISFACTION[band]))
		var want: int = {"fast": 3, "normal": 3, "slow": 5}[band]
		_check(got == want, "AC6.9 bought building, %s hiring: first output on turn %d (got %d)" % [band, want, got])
		bought_row += "  %d" % got
	lines.append(bought_row)
	print("[AC6.9] time to first output\n" + "\n".join(lines))
	_fresh()


func _first_output_turn(building_id: String, recipe_id: String, satisfaction: float, andrew: bool) -> int:
	_fresh(satisfaction)
	if andrew:
		_seat_expansion_director()
	_stock_kit(building_id)
	var iid := Construction.start_on_tile(building_id, recipe_id, TILE)
	for turn in range(1, 20):
		Production.tick_staffing()
		Construction.tick_turn()
		var b: Dictionary = BuildingState.buildings.get(iid, {})
		if not b.is_empty() and Staffing.run_fraction(b) > 0.0:
			return turn
	return -1


func _first_output_after_offer(satisfaction: float) -> int:
	_fresh(satisfaction)
	MatchState.money = 1000000.0
	var npc := _building(FACTORY, "r_056", "npc_test")
	var iid := str(npc.instance_id)
	if not bool(MatchState.offer_for_building(iid).get("ok", false)):
		return -2
	for turn in range(1, 20):
		Production.tick_staffing()
		var b: Dictionary = BuildingState.buildings[iid]
		if BuildingState.is_player_owned(b) and Staffing.run_fraction(b) > 0.0:
			return turn
		MatchState.tick_purchases()
	return -1


## AC7.1, AC7.2: construction totals 4 / 5 / 6, infrastructure 2; the construction_time domain with floor 2;
## Gerald's turn off; a project keeps the duration it started with.
func _test_construction_durations() -> void:
	_fresh()
	var totals := {
		4: ["mine", "water_pump", "oil_well", "fracking_oil_well", "solar_farm", "onshore_wind_farm", "farm", "new_forest", "old_forest", "landfill"],
		5: ["furnace", "power_plant", "eaf", "petro_refinery", "chem_plant", "poly_plant", "electrolyser", "desal", "hydro_power_plant", "battery", "heat_battery", "water_recycling", "recycling_plant"],
		6: ["industrial_factory", "assembly_plant", "high_tech_manufactory", "consumer_factory", "offshore_oil_platform", "offshore_wind_farm", "airport"],
		2: ["roads", "cables", "pipes", "reinf_pipes", "rails"],
	}
	var wrong: PackedStringArray = []
	for total: int in totals:
		for internal: String in totals[total]:
			var bid := str(Catalog.get_building_by_internal_name(internal).get("id", ""))
			if MatchState.effective_build_duration(bid) != total:
				wrong.append("%s %d" % [internal, MatchState.effective_build_duration(bid)])
	_check(wrong.is_empty(), "AC7.1 construction takes 4, 5 or 6 turns by class, infrastructure 2 (%s)" % ", ".join(wrong))
	AdvisorState.advisor_seats["coo"] = AdvisorState.MASTER_BUILDER_ID
	_check(MatchState.effective_build_duration(FACTORY) == 5, "AC7.2 Gerald still takes a turn off")
	AdvisorState.advisor_seats.erase("coo")
	Modifiers.add({"id": "test_ct_add", "domain": "construction_time", "add": -3.0})
	_check(MatchState.effective_build_duration(MINE) == 2 and MatchState.effective_build_duration(FACTORY) == 3,
		"AC7.2 a −3 turn speed up never takes a build below 2")
	Modifiers.remove("test_ct_add")
	Modifiers.add({"id": "test_ct_pct", "domain": "construction_time", "pct": -50.0})
	_check(MatchState.effective_build_duration(FACTORY) == 3, "AC7.2 a −50% speed up halves a 6 turn build")
	Modifiers.remove("test_ct_pct")
	_stock_kit(FACTORY)
	var iid := Construction.start_on_tile(FACTORY, "r_056", TILE)
	Modifiers.add({"id": "test_ct_late", "domain": "construction_time", "add": -3.0})
	_check(int((Construction.construction_projects[iid] as Dictionary).construction_duration) == 6,
		"AC7.2 a project keeps the duration it started with")
	_fresh()


## AC7.3, AC7.4: upgrades take 5 turns; retrofits 3, 2, 3, 4 with fees and labour unchanged.
func _test_upgrade_and_retrofit_durations() -> void:
	_check(BuildingLevels.UPGRADE_DURATION == 5, "AC7.3 upgrades take 5 turns")
	var tiers: Dictionary = EconomyConfig.RETROFIT_TIERS
	_check(int(tiers.base.turns) == 3 and int(tiers.ops3.turns) == 2 and int(tiers.ops2.turns) == 3 and int(tiers.ops1.turns) == 4,
		"AC7.4 retrofit turns: base 3, Ops 3 2, Ops 2 3, Ops 1 4")
	_check(is_equal_approx(float(tiers.base.fee), 25.0) and is_equal_approx(float(tiers.ops3.fee), 15.0)
		and is_equal_approx(float(tiers.ops1.labour), 0.75), "AC7.4 retrofit fees and labour fractions are unchanged")


## AC8.1–AC8.3: the offer pays now, takes the building off the market and closes after 2 turns with 80% (50%
## when unhappy) of its staff; no second offer.
func _test_offer_and_closing() -> void:
	_fresh(BAND_SATISFACTION.normal)
	MatchState.money = 100000.0
	var npc := _building(FACTORY, "r_056", "npc_test")
	var iid := str(npc.instance_id)
	var price := MatchState.building_purchase_price(npc)
	var lots_before := BuildingMarketTab.lots().size()
	var offer := MatchState.offer_for_building(iid)
	_check(bool(offer.ok) and int(offer.turns) == 2 and is_equal_approx(MatchState.money, 100000.0 - float(price)),
		"AC8.1 the offer charges the full price now")
	_check(MatchState.is_under_offer(iid) and not BuildingState.is_player_owned(npc) and BuildingMarketTab.lots().size() == lots_before - 1,
		"AC8.2 under offer it stays NPC owned and leaves the market lots")
	_check(not bool(MatchState.offer_for_building(iid).ok), "AC8.2 a building under offer cannot be offered for twice")
	_check(BuildingMarketTab.offer_words(iid) == "Under offer. Yours in 2 turns.", "AC8.2 panels say when it is yours")
	MatchState.tick_purchases()
	_check(not BuildingState.is_player_owned(npc) and MatchState.offer_turns_remaining(iid) == 1, "AC8.3 one turn in, still closing")
	MatchState.tick_purchases()
	_check(BuildingState.is_player_owned(npc) and not MatchState.is_under_offer(iid) and is_equal_approx(Staffing.fill(npc), 0.8)
		and bool(npc.get("land_exempt", false)), "AC8.3 at closing it is yours, 80% staffed, with its land")

	_fresh(BAND_SATISFACTION.slow)
	MatchState.money = 100000.0
	var unhappy := _building(FACTORY, "r_056", "npc_test")
	MatchState.offer_for_building(str(unhappy.instance_id))
	MatchState.tick_purchases()
	MatchState.tick_purchases()
	_check(is_equal_approx(Staffing.fill(unhappy), 0.5), "AC8.3 below −5 satisfaction it arrives 50% staffed")
	_fresh()


## AC8.4: pending purchases are saved, validated and cleared on reset; older saves load with none.
func _test_pending_purchases_save() -> void:
	_fresh()
	MatchState.money = 100000.0
	var npc := _building(FACTORY, "r_056", "npc_test")
	var iid := str(npc.instance_id)
	MatchState.offer_for_building(iid)
	var snap: Dictionary = MatchState.export_state()
	_check((snap.get("pending_purchases", {}) as Dictionary).has(iid), "AC8.4 pending purchases are saved")
	_check(_validator_lists("pending_purchases"), "AC8.4 the validator knows pending purchases")
	MatchState.reset()
	_check(MatchState.pending_purchases.is_empty(), "AC8.4 reset clears pending purchases")
	MatchState.import_state(snap)
	_check(MatchState.offer_turns_remaining(iid) == 2, "AC8.4 a loaded save keeps the offer and its closing")
	var legacy := snap.duplicate(true)
	legacy.erase("pending_purchases")
	MatchState.import_state(legacy)
	_check(MatchState.pending_purchases.is_empty(), "AC8.4 an older save loads with none")
	_fresh()


func _validator_lists(field: String) -> bool:
	return FileAccess.get_file_as_string("res://scripts/save_validation.gd").contains("\"%s\"" % field)


## AC9.1, AC9.2: the Expansion Director seat is Andrew's alone, exists while he holds it, and his package lasts
## his tenure: builds 3 turns shorter (floor 2), sites half staffed, closing in 1 turn, no purchase discount.
func _test_expansion_director() -> void:
	_fresh()
	var seat := AdvisorState.EXPANSION_DIRECTOR_SEAT
	var choice_ids: Array = []
	for c: Dictionary in (DecisionState.DECISION_DEFINITIONS.family_friend as Dictionary).choices:
		choice_ids.append(str(c.id))
	_check(choice_ids == ["cfo", "coo", "expansion"], "AC9.1 Andrew's offer has a third choice")
	_check(DecisionState.choice_words("family_friend", "expansion", {}).has("The Expansion Director's chair for 30 turns, unpaid."),
		"AC9.1 the choice names the seat")
	_check(not AdvisorState.is_seat_available(seat), "AC9.1 the seat does not exist before he takes it")
	AdvisorState.permanent_advisor_ids.append(AdvisorState.MASTER_BUILDER_ID)
	_check(not AdvisorState.assign_advisor_to_seat(seat, AdvisorState.MASTER_BUILDER_ID), "AC9.1 nobody else can take it")
	var npc := _building(FACTORY, "r_056", "npc_test")
	var price_before := MatchState.building_purchase_price(npc)
	_check(_seat_expansion_director() and AdvisorState.expansion_director_active(), "AC9.1 Andrew takes the seat")
	_check(MatchState.effective_build_duration(MINE) == 2 and MatchState.effective_build_duration(FURNACE) == 2
		and MatchState.effective_build_duration(FACTORY) == 3, "AC9.2 builds take 3 turns less, never under 2")
	_check(is_equal_approx(Staffing.start_fill(), 0.5) and MatchState.purchase_closing_turns() == 1,
		"AC9.2 sites start half staffed and purchases close in 1 turn")
	_check(MatchState.building_purchase_price(npc) == price_before, "AC9.2 no purchase discount")
	TurnManager.current_turn = AdvisorState.founder_leaves_turn
	_check(not AdvisorState.expansion_director_active() and MatchState.purchase_closing_turns() == 2
		and is_zero_approx(Staffing.start_fill()), "AC9.2 the package ends with his tenure")
	AdvisorState.release_founder()
	_check(MatchState.effective_build_duration(MINE) == 4 and not AdvisorState.is_seat_available(seat),
		"AC9.2 once he leaves, the seat and its speed up are gone")
	_fresh()


## AC10.1: the diagnostics name the staffing.
func _test_diagnostics_staffing_row() -> void:
	_fresh()
	LabourState.policy_throughput_enabled = false
	var b := _building(MINE, "r_001")
	var recipe: Dictionary = Catalog.get_recipe("r_001")
	var bdata: Dictionary = Catalog.get_building(MINE)
	b["staff_fill"] = 0.5
	var rows: Array = BuildingReadout.diagnostics(b, recipe, bdata, false)
	_check(str((rows[0] as Dictionary).get("label", "")) == "Hiring staff"
		and str((rows[0] as Dictionary).get("detail", "")).begins_with("Staffed 50%. Starts at 70%."),
		"AC10.1 below 70% the first row says it is hiring and when it starts")
	b["staff_fill"] = 0.85
	var found := false
	for r: Dictionary in BuildingReadout.diagnostics(b, recipe, bdata, false):
		found = found or str(r.get("detail", "")).begins_with("Staffed 85%. Runs at 85%.")
	_check(found, "AC10.1 from 70% a row says what share it runs at")
	_fresh()
