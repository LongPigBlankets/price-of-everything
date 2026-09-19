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
	for item in [["solid_light", "cpu", 0.02], ["safe_liquid", "pure_water", 0.05], ["hazard_liquid", "chlorine", 0.1], ["gas", "oxygen", 0.125]]:
		var gid := str(Catalog.get_good_by_internal_name(str(item[1])).id)
		var quote := Service.Contract.quote("buy", [{"good":gid,"quantity":10}], snapshot, 1.5, Service.goods())
		_check(quote.ok and absf(float(quote.fee)-10*(0.005*float(snapshot[gid].reference)+float(item[2])*1.5)) < 0.000001, "new cargo tariff: "+str(item[0]))
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
