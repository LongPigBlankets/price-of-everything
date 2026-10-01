extends "res://tests/unit/test_middleman_service.gd"
const Locations := preload("res://scripts/middleman_locations.gd")

func _test_global_location_coefficients() -> void:
	_check(Locations.classify("urban", 7, true, false) == 1.05, "large connected port city")
	_check(Locations.classify("urban", 7, false, false) == 1.25, "large inland city uses ordinary city coefficient")
	_check(Locations.classify("urban", 4, false, false) == 1.25, "four non-port urban tiles are medium")
	_check(Locations.classify("urban", 3, true, false) == 1.05, "even a small urban port area receives 1.05")
	_check(Locations.classify("rural", 0, false, true) == 1.75 and Locations.classify("hill", 0, false, true) == 1.75, "adjacent rural and hill tiles")
	_check(Locations.classify("rural", 0, false, false) == 2.0, "remote countryside")
	_check(Locations.classify("mountain", 0, true, true) == 2.5, "mountains always cost 2.5")
	_check(Locations.coefficient("tile_5_4") == 1.5 and Locations.coefficient("tile_6_4") == 1.75, "Pepper benchmark factors unchanged")
	_check(Locations.factors().size() > 400, "full authored map classified")

func _test_new_tariffs_and_power_exclusion() -> void:
	setup()
	var snapshot := Service.prices()
	for item in [["solid_light", "cpu", 0.025], ["safe_liquid", "pure_water", 0.08], ["hazard_liquid", "chlorine", 0.15], ["gas", "oxygen", 0.2]]:
		var gid := str(Catalog.get_good_by_internal_name(str(item[1])).id)
		var quote := Service.Contract.quote("buy", [{"good":gid,"quantity":10}], snapshot, 1.5, Service.goods())
		_check(quote.ok and absf(float(quote.fee)-10*(Service.Contract.AD_VALOREM*float(snapshot[gid].reference)+float(item[2])*1.5)) < 0.000001, "new cargo tariff: "+str(item[0]))
	var electricity := str(Catalog.get_good_by_internal_name("power").id)
	_check(not Service.goods().has(electricity), "grid electricity excluded from material price basket")
	var waste := str(Catalog.get_good_by_internal_name("waste_water").id)
	_check(not Service.material_tradeable(waste, "input") and not Service.material_tradeable(waste, "output"), "wastewater cannot become a market trade")
	cleanup()

func _test_multi_output_factory_settles_every_product_once() -> void:
	setup()
	var iid := BuildingState.add_building("b_010", "r_012", "tile_5_4", MatchState.LOCAL_PLAYER)
	# Resolve building type from the catalogue rather than assume a factory ID.
	var recipe := Catalog.get_recipe("r_012")
	BuildingState.buildings[iid].building_id = str(recipe.building_id)
	_check(Service.enable(iid).ok, "chemical factory now eligible")
	var before := MatchState.money
	Production._process_production()
	var report := Production.last_turn_summary
	for product: Dictionary in recipe.outputs:
		_check(int(report.sold.get(str(product.good_id), {}).get("qty", 0)) == int(product.qty), "all coproducts sold: "+str(product.internal_name))
	_check(absf(MatchState.money-before-Production.cash_change_of(report)) < 0.0001, "expanded material and fee accounting reconciles")
	var settled := MatchState.money
	Service.settle(BuildingState.buildings.values(), report)
	_check(MatchState.money == settled, "coproduct settlement remains exactly once")
	cleanup()

func _test_no_input_source_and_power_plant() -> void:
	setup()
	var recipe := Catalog.get_recipe("r_087")
	var source := BuildingState.add_building(str(recipe.building_id), "r_087", "tile_5_4", MatchState.LOCAL_PLAYER)
	_check(Service.enable(source).ok and not Service.uses_inputs(source), "no-input source has output-only service")
	_check(Service.fully_managed(source), "no-input source has no owned warehouse obligation")
	# Drive the same actual output hook independently of research availability.
	var report := summary()
	Service.prepare(BuildingState.buildings.values(), report)
	var nitrogen := str(Catalog.get_good_by_internal_name("nitrogen").id)
	Service.produce(source, nitrogen, 50)
	Service.settle(BuildingState.buildings.values(), report)
	_check(int(report.sold.get(nitrogen, {}).get("qty", 0)) == 50, "no-input source can sell without a fabricated consumed receipt")
	var plant := BuildingState.add_building("b_003", "r_004", "tile_5_4", MatchState.LOCAL_PLAYER)
	_check(Service.enable(plant).ok and Service.uses_inputs(plant) and not Service.uses_outputs(plant), "power plant buys fuel and water but retains grid output")
	var quote := Service.preview_building(BuildingState.get_building(plant))
	_check(quote.ok and quote.sale.items.is_empty(), "power sales incur no middleman fee")
	cleanup()

func _test_all_recipe_locations_and_new_construction_defaults() -> void:
	setup()
	MatchState.ruleset.middleman_new_buildings = true
	var checked := 0
	for recipe: Dictionary in Catalog.all_recipes():
		if not Service.recipe_side(recipe, "input") and not Service.recipe_side(recipe, "output"): continue
		var b := {"instance_id":"prospective", "building_id":str(recipe.building_id), "recipe_id":str(recipe.recipe_id), "tile_id":"tile_14_2", "owner":MatchState.LOCAL_PLAYER, "level":1}
		_check(Service.default_for(str(recipe.recipe_id), "tile_14_2"), "new construction supports recipe "+str(recipe.recipe_id))
		var quote := Service.preview_building(b)
		_check(quote.ok, "material quote supports recipe "+str(recipe.recipe_id))
		checked += 1
	_check(checked > 80, "rollout covers the full production catalogue")
	MatchState.ruleset.middleman_new_buildings = false
	_check(not Service.default_for("r_012", "tile_14_2"), "other-start enrollment defaults unchanged")
	cleanup()

func _test_completed_port_changes_urban_coefficient() -> void:
	setup()
	_check(Locations.coefficient("tile_5_4") == 1.5, "small inland town initially costs 1.5")
	var port := BuildingState.add_building("b_004", "", "tile_5_4", MatchState.LOCAL_PLAYER)
	_check(Locations.coefficient("tile_5_4") == 1.05, "completed port changes the whole urban area immediately")
	BuildingState.buildings.erase(port)
	_check(Locations.coefficient("tile_5_4") == 1.5, "removing runtime port invalidates location cache")
	var rural_port := BuildingState.add_building("b_004", "", "tile_6_4", MatchState.LOCAL_PLAYER)
	_check(Locations.coefficient("tile_5_4") == 1.5, "adjacent non-urban port does not grant urban port rate")
	BuildingState.buildings.erase(rural_port)
	cleanup()

func _test_live_mine_grid_and_nontradeable_coproduct() -> void:
	setup()
	MatchState.recycling_unlocked = true
	var mine := BuildingState.add_building("b_001", "r_001", "tile_5_4", MatchState.LOCAL_PLAYER)
	var plant := BuildingState.add_building("b_003", "r_004", "tile_5_4", MatchState.LOCAL_PLAYER)
	var farm_recipe := Catalog.get_recipe("r_208")
	var farm := BuildingState.add_building(str(farm_recipe.building_id), "r_208", "tile_5_4", MatchState.LOCAL_PLAYER)
	for iid: String in [mine, plant, farm]: _check(Service.enable(iid).ok, "material service enabled for "+iid)
	var before := MatchState.money
	Production._process_production()
	var report := Production.last_turn_summary
	_check(int(report.sold.get("g_001", {}).get("qty", 0)) == 60, "live no-input mine sells a complete batch")
	_check(int(report.power_supply) > 0 and int(report.grid_sold) > 0, "fuelled generator feeds ordinary grid settlement")
	var power_id := str(Catalog.get_good_by_internal_name("power").id)
	_check(not report.sold.has(power_id) and not Service.entry(plant).receipts.has("sale"), "generator electricity never enters middleman sales")
	var waste_id := str(Catalog.get_good_by_internal_name("waste_water").id)
	_check(not report.sold.has(waste_id) and Stockpile.get_at_tile("tile_5_4", waste_id) == 5, "unsaleable farm coproduct stays in owned storage")
	_check(absf(MatchState.money-before-Production.cash_change_of(report)) < 0.0001, "mine, farm and grid mixed economy reconciles cash")
	var snap := SaveLoad.export_snapshot()
	SaveLoad.import_snapshot(JSON.parse_string(JSON.stringify(snap)))
	_check(Service.enabled(farm), "expanded goods and building modes reload")
	_check(Service.uses_inputs(plant) and not Service.uses_outputs(plant), "grid exclusion survives reload")
	cleanup()

## Each demo start opens with its own free batches (data/starts/*.json "opening_batches", and a building entry's
## own "opening_batches" for that building): none, and turn 1 buys the inputs; N, one batch held and N-1 more in
## reserve. Metal Magnate has none (owner, 28 September). Glass Merchant stocks only its windows factory for one
## turn, the rest buy on turn 1: the factory's batch is the dear one, and without it £300 cannot fund turn 1.
func _test_demo_starts_open_with_their_batches() -> void:
	var want := {"metal_magnate": {}, "glass_merchant": {"b_007": 1}}
	for start: String in want:
		var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/starts/%s.json" % start))
		_check(int(cfg.get("opening_batches", -1)) == 0, "%s opens with no free batches by default" % start)
		var snap := SaveLoad.expand_start_config(cfg)
		var match_state: Dictionary = snap.get("match", {})
		_check(str((match_state.get("ruleset", {}) as Dictionary).get("logistics_model", "")) == "middleman_v1", "%s is an intermediary game" % start)
		var services: Dictionary = (match_state.get("middleman_service", {}) as Dictionary).get("buildings", {})
		_check(services.size() == (cfg.get("buildings", []) as Array).size(), "%s enrols every starting building" % start)
		var exact := true
		for iid in services:
			var building_id := str(services[iid].get("building_id", str(iid).get_slice("_", 1) + "_" + str(iid).get_slice("_", 2)))
			var batches := int((want[start] as Dictionary).get(building_id, 0))
			var recipe := Catalog.get_recipe(str(services[iid].recipe_id))
			var held: Dictionary = services[iid].get("inputs", {})
			var reserve: Dictionary = services[iid].get("opening_inputs", {})
			for input: Dictionary in recipe.get("inputs", []):
				if not Service.material_tradeable(str(input.good_id), "input"):
					continue
				var one := int(input.qty) if batches > 0 else 0
				if int(held.get(str(input.good_id), 0)) != one or int(reserve.get(str(input.good_id), 0)) != int(input.qty) * maxi(0, batches - 1):
					exact = false
			if (recipe.get("inputs", []) as Array).is_empty() and not (held.is_empty() and reserve.is_empty()):
				exact = false
		_check(exact, "%s holds the free batches it names and nothing else (%s)" % [start, str(want[start])])
		_check((cfg.get("stockpile", {}) as Dictionary).is_empty(), "%s has no tile stockpile to strand" % start)
	# A building entry's own opening_batches overrides the start's.
	var cfg2 := {"start": true, "ruleset": {"logistics_model": "middleman_v1", "middleman_new_buildings": true},
		"opening_batches": 2, "money": 100, "buildings": [
			{"building_id": "b_002", "recipe_id": "r_053", "tile_id": "tile_18_16"},
			{"building_id": "b_002", "recipe_id": "r_053", "tile_id": "tile_18_16", "opening_batches": 0}]}
	var services2: Dictionary = ((SaveLoad.expand_start_config(cfg2).get("match", {}) as Dictionary).get("middleman_service", {}) as Dictionary).get("buildings", {})
	var stocked := 0
	for iid in services2:
		if not (services2[iid].get("inputs", {}) as Dictionary).is_empty(): stocked += 1
	_check(services2.size() == 2 and stocked == 1, "a building's own opening_batches overrides the start's (%d of %d stocked)" % [stocked, services2.size()])

func _test_opening_reserve_runs_two_turns_then_buys() -> void:
	var iid := str(setup()[0])
	var e := Service.entry(iid)
	e.inputs = {"g_006": 32, "g_007": 32}
	e["opening_inputs"] = {"g_006": 32, "g_007": 32}
	Production._process_production()
	var s := Production.last_turn_summary
	_check(s.purchased.is_empty() and int(s.sold.get("g_008", {}).get("qty", 0)) == 33, "turn one runs on the held batch without buying")
	_check(int(Service.entry(iid).get("inputs", {}).get("g_006", 0)) == 0 and Service.has_assets(iid), "the reserve is still owned after turn one")
	TurnManager.current_turn += 1
	Production._process_production()
	s = Production.last_turn_summary
	_check(s.purchased.is_empty() and int(s.sold.get("g_008", {}).get("qty", 0)) == 33, "turn two draws the reserve instead of buying")
	_check(not Service.entry(iid).has("opening_inputs"), "the reserve is used up after two batches")
	TurnManager.current_turn += 1
	Production._process_production()
	s = Production.last_turn_summary
	_check(int(s.purchased.get("g_006", 0)) == 32 and int(s.purchased.get("g_007", 0)) == 32, "turn three buys its batch as usual")
	cleanup()

func _test_opening_reserve_is_released_with_the_inputs() -> void:
	var iid := str(setup()[0])
	var e := Service.entry(iid)
	e.inputs = {"g_006": 32, "g_007": 32}
	e["opening_inputs"] = {"g_006": 32, "g_007": 32}
	_check(Service.set_mode(iid, "input", "managed").ok, "take inputs in-house with a reserve on hand")
	_check(Stockpile.get_at_tile("tile_5_4", "g_006") == 64 and Stockpile.get_at_tile("tile_5_4", "g_007") == 64, "held and reserved inputs both move to the tile stockpile")
	cleanup()

## Batches are funded all or nothing, so on a tight turn the most profitable batch goes first: with cash for
## one batch and no credit, the better earner runs and the other waits, whatever order they were built in.
func _test_intermediary_funds_the_most_profitable_batch_first() -> void:
	var ids := setup(2)
	var first := str(ids[0])
	var better := str(ids[1])
	Modifiers.add({"id": "test_better_output", "domain": "recipe_output", "target": "*",
		"target_match": {"instance_id": better}, "pct": 50.0, "label": "test", "source": "test"})
	var snapshot := Service.prices()
	var m_first := Service.batch_margin(BuildingState.get_building(first), snapshot)
	var m_better := Service.batch_margin(BuildingState.get_building(better), snapshot)
	_check(m_better > m_first, "the boosted building's batch earns more (£%.1f against £%.1f)" % [m_better, m_first])
	# No credit to borrow against, and cash for exactly one batch after the turn's bills.
	LoanState.loans.append({"id": 99, "principal_initial": LoanState.capacity_total() + 10000.0,
		"principal_remaining": 0.0, "payment_per_turn": 0.0, "turns_remaining": 0, "interest_paid": 0.0})
	var p: Dictionary = Service.preview_building(BuildingState.get_building(better))
	MatchState.money = float(p.upfront) + float(p.protected_commitments) + 1.0
	Service.prepare(BuildingState.buildings.values(), summary())
	_check(str(Service.entry(better).state) == "supplied" and str(Service.entry(first).state) == "rejected_before_supply",
		"with cash for one batch the better earner is supplied and the first built waits (%s, %s)" % [
			str(Service.entry(better).state), str(Service.entry(first).state)])
	Modifiers.remove("test_better_output")
	cleanup()

## A start's one-off charge is paid once, in its turn, as a cost before tax; a later turn does not repeat it.
func _test_start_one_off_charge_is_paid_once() -> void:
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/starts/glass_merchant.json"))
	var charges: Array = (SaveLoad.expand_start_config(cfg).get("match", {}) as Dictionary).get("one_off_charges", [])
	_check(charges.size() == 1 and int(charges[0].turn) == 1 and is_equal_approx(float(charges[0].amount), 100.0)
		and str(charges[0].label) == "Opening costs", "Glass Merchant books £100 of opening costs on turn 1")
	_check(float(cfg.get("money", 0)) == 400.0 and float((cfg.get("loans", [{}]) as Array)[0].get("principal", 0)) == 1000.0,
		"Glass Merchant opens with £400 and a £1,000 loan")
	setup(1)
	MatchState.one_off_charges = [{"turn": 1, "amount": 100.0, "label": "Opening costs"}]
	var cash := MatchState.money
	Production._process_production()
	var s: Dictionary = Production.last_turn_summary
	_check(is_equal_approx(float(s.get("one_off_paid", 0.0)), 100.0) and (s.get("one_off_lines", []) as Array).size() == 1,
		"turn 1 pays the opening costs")
	_check(absf(MatchState.money - cash - Production.cash_change_of(s)) < 0.0001, "the charge is in the turn's cash")
	_check(absf(preload("res://scripts/money_panel.gd").net_cash_of(s) - Production.cash_change_of(s)) < 0.0001,
		"the money panel counts it among the costs")
	_check(MatchState.one_off_charges.is_empty(), "once paid, it is gone")
	TurnManager.current_turn += 1
	Production._process_production()
	_check(float(Production.last_turn_summary.get("one_off_paid", 0.0)) == 0.0, "turn 2 does not charge it again")
	cleanup()
