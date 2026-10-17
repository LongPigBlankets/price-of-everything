extends "res://tests/test_base.gd"
## The tile quick menu (right click on a tile): its actions (scripts/tile_quick_actions.gd), the favourites they
## build from, buildings placed straight at a favourite's level, and the menu that draws them.

const FEATURE := "tile_menu"
const Actions := preload("res://scripts/tile_quick_actions.gd")
const LandPrice := preload("res://scripts/land_price.gd")
const TAGS := {
	"_test_quick_land": ["tile_menu", "land"],
	"_test_levelled_build_on_the_map": ["tile_menu", "construction"],
	"_test_levelled_kit_and_quote": ["tile_menu", "construction"],
	"_test_quick_local_sale_in_turn": ["tile_menu", "market"],
}

const TILE := "tile_5_10"


func _fresh() -> void:
	MatchState.reset()
	Stockpile.clear_all()
	BuildingState.land_economy_level = 0
	MatchState.money = 100000.0


func _gid(internal: String) -> String:
	return str(Catalog.get_good_by_internal_name(internal).get("id", ""))


func _test_quick_sell_market() -> void:
	_fresh()
	var saved: Dictionary = MatchState.ruleset.duplicate(true)
	MatchState.ruleset["logistics_model"] = ""
	var steel := _gid("steel")
	Stockpile.add(TILE, steel, 30)
	_check(str(Actions.sale_route(TILE).route) == "market", "quick menu: outside a Local Suppliers game sales go to the market")
	var opt := Actions.surplus_option(TILE)
	_check(bool(opt.ok) and int((opt.goods as Dictionary).get(steel, 0)) == 30,
		"quick menu: with no buildings on the tile all its stock is surplus")
	var done := Actions.sell(TILE, opt.goods)
	_check(bool(done.ok) and Stockpile.get_at_tile(TILE, steel) == 0, "quick menu: selling the surplus ships it to the market")
	var rows := Actions.goods_options(TILE)
	_check(rows.is_empty() and not bool(Actions.goods_entry(TILE).ok), "quick menu: an empty tile has no goods to sell")
	MatchState.ruleset = saved
	_fresh()


func _test_quick_surplus_keeps_the_reserve() -> void:
	_fresh()
	var iid := BuildingState.add_building("b_002", "r_005", TILE, MatchState.LOCAL_PLAYER, "quick_furnace", false)
	var reserve: Dictionary = Production.compute_sell_reserve_for_tile(TILE)
	var gid := str(reserve.keys()[0]) if not reserve.is_empty() else ""
	if gid == "":
		_check(false, "quick menu: the furnace reserves an input")
		return
	Stockpile.add(TILE, gid, int(reserve[gid]) + 7)
	_check(int(Actions.surplus(TILE).get(gid, 0)) == 7, "quick menu: surplus leaves the tile's buildings their working stock")
	BuildingState.remove_building(iid)
	_fresh()


func _test_quick_local_sale_in_turn() -> void:
	_fresh()
	var saved: Dictionary = MatchState.ruleset.duplicate(true)
	MatchState.ruleset["logistics_model"] = "middleman_v1"
	var steel := _gid("steel")
	Stockpile.add(TILE, steel, 20)
	var route := Actions.sale_route(TILE)
	if ResearchState.global_trade_license_available():
		_check(true, "quick menu: the licence is held, so the market route is open")
	else:
		_check(str(route.route) == "local", "quick menu: before the licence, sales go to Local Suppliers")
		var done := Actions.sell(TILE, {steel: 20})
		_check(bool(done.ok) and MatchState.queued_local_units(TILE, steel) == 20 and Stockpile.get_at_tile(TILE, steel) == 20,
			"quick menu: a Local Suppliers sale is queued for the turn, the stock still here")
		_check(Actions._sellable(TILE, {steel: 20}, "local").is_empty(), "quick menu: queued units are not offered twice")
		var saved_state := MatchState.export_state()
		_check((saved_state.get("queued_local_sales", {}) as Dictionary).has(TILE), "quick menu: a queued sale is saved")
		TurnManager.commit_turn()
		await _await_turn_settled()
		_check(Stockpile.get_at_tile(TILE, steel) < 20 and MatchState.queued_local_sales.is_empty(),
			"quick menu: the turn's sell phase sells the queued units to Local Suppliers")
	MatchState.ruleset = saved
	_fresh()


func _test_quick_land() -> void:
	_fresh()
	var buy := Actions.buy_land_option(TILE)
	var s := LandPrice.starting_price(TILE)
	_check(bool(buy.ok) and absf(float(buy.cost) - float(int(buy.patches)) * s * 2.0) < 0.01,
		"quick menu: buying all the land is a stand-alone purchase at double the price")
	_check(Actions.buy_land_confirm(TILE).contains(LandPrice.pounds(float(buy.cost))), "quick menu: the confirm states the price")
	_check(Actions.buy_all_land(TILE) and BuildingState.get_tile_land_units_available(TILE) == 0
		and BuildingState.tile_land_standalone.has(TILE), "quick menu: it buys every patch left, on its own")
	_check(not bool(Actions.buy_land_option(TILE).ok), "quick menu: nothing is left to buy afterwards")
	# Spare bought land sells at the starting price plus the economy's rise, never the rises the player made.
	BuildingState.add_building("b_002", "r_005", TILE, MatchState.LOCAL_PLAYER, "quick_land_b", false)
	BuildingState.land_economy_level = 1
	var spare := BuildingState.spare_land_patches(TILE)
	var expect := float(spare) * s * (1.0 + (0.25 if LandPrice.band(TILE) in LandPrice.URBAN_BANDS else 0.0))
	var opt := Actions.sell_land_option(TILE)
	_check(bool(opt.ok) and absf(float(opt.paid) - expect) < 0.01, "quick menu: spare land sells at the starting price and the economy's rise")
	var cash := MatchState.money
	var used := ceili(BuildingState.get_tile_player_space_used(TILE))
	BuildingState.sell_spare_land(TILE)
	_check(absf(MatchState.money - cash - expect) < 0.01 and BuildingState.get_tile_land_owned(TILE) >= used,
		"quick menu: selling keeps the land the buildings stand on")
	# Granted land (a start's, or a bought building's) does not sell.
	_fresh()
	BuildingState.tile_land_owned[TILE] = 60
	_check(BuildingState.spare_land_patches(TILE) == 0 and str(Actions.sell_land_option(TILE).words).begins_with("Only land you bought"),
		"quick menu: land you were granted cannot be sold")
	_fresh()


func _test_favourites() -> void:
	_fresh()
	_check(not bool(Actions.favourite_entry(TILE).ok), "favourites: with none starred the entry says how to add one")
	_check(MatchState.toggle_favourite_build("b_002", "r_005", 2) and MatchState.favourite_index("b_002", "r_005", 2) == 0,
		"favourites: a star adds the building type, recipe and level")
	_check(MatchState.favourite_index("b_002", "r_005", 1) == -1, "favourites: the level is part of the favourite")
	var saved := MatchState.export_state()
	MatchState.favourite_builds.clear()
	MatchState.import_state(JSON.parse_string(JSON.stringify(saved)))
	_check(MatchState.favourite_builds.size() == 1 and int(MatchState.favourite_builds[0].level) == 2, "favourites: saved with the match")
	_check(Actions.favourite_title(MatchState.favourite_builds[0]).ends_with("level 2"), "favourites: the list names the level")
	_check(not MatchState.toggle_favourite_build("b_002", "r_005", 2) and MatchState.favourite_builds.is_empty(),
		"favourites: a second press removes it")
	_fresh()


func _test_levelled_kit_and_quote() -> void:
	_fresh()
	var base: Dictionary = Construction.requirements_for("b_002", 1)
	var l3: Dictionary = Construction.requirements_for("b_002", 3)
	var ups: Dictionary = {}
	for target in [2, 3]:
		for internal: String in BuildingLevels.upgrade_materials("furnace", target):
			var g := _gid(internal)
			ups[g] = int(ups.get(g, 0)) + int(BuildingLevels.upgrade_materials("furnace", target)[internal])
	var sums := true
	for g in ups:
		sums = sums and int(l3.get(g, 0)) == int(base.get(g, 0)) + int(ups[g])
	_check(not ups.is_empty() and sums, "levelled build: the kit is the level 1 kit plus each upgrade's materials")
	_check(Construction.requirements_for("b_002") == base, "levelled build: outside an attempt the kit is level 1's")
	var rules := preload("res://scripts/construction_rules.gd")
	BuildingState.tile_land_owned[TILE] = 200
	var q1: Dictionary = rules.quote("b_002", "r_005", TILE, {}, {})
	var q2: Dictionary = rules.quote("b_002", "r_005", TILE, {}, {"level": 2})
	_check(int(q2.build_turns) == int(q1.build_turns) + Construction.LEVELLED_BUILD_EXTRA_TURNS,
		"levelled build: it takes two turns longer")
	_check(float((q2.land_plan as Dictionary).needed) > float((q1.land_plan as Dictionary).needed),
		"levelled build: it needs the larger footprint")
	var gate := BuildingLevels.research_gate("furnace", 2)
	var blocked := (q2.blocks as Array).any(func(b: Dictionary) -> bool: return str(b.key) == "level_research")
	_check(gate == "" or ResearchState.is_unlocked(gate) or blocked, "levelled build: the level's research is required")
	_check(Construction.placing_level == 1, "levelled build: a quote leaves the placing level at 1")
	_fresh()


func _test_levelled_build_on_the_map() -> void:
	_fresh()
	var inst: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(inst)
	await get_tree().process_frame
	MatchState.money = 100000.0
	var gate := BuildingLevels.research_gate("furnace", 2)
	if gate != "":
		ResearchState.grant_unlock(gate)
	BuildingState.tile_land_owned[TILE] = 200
	var kit: Dictionary = Construction.requirements_for("b_002", 2)
	for g in kit:
		Stockpile.add(TILE, str(g), int(kit[g]))
	BuildMode._last_attempt_ms = 0
	var placed := BuildMode.attempt_direct_build("b_002", "r_005", TILE, true, 2)
	var project: Dictionary = {}
	for p: Dictionary in Construction.projects_on_tile(TILE):
		if str(p.building_id) == "b_002":
			project = p
	_check(placed and int(project.get("level", 0)) == 2, "levelled build: the map places the building at the favourite's level")
	_check(int(project.get("construction_duration", 0)) == MatchState.effective_build_duration("b_002") + Construction.LEVELLED_BUILD_EXTRA_TURNS
		and absf(float(project.get("reserved_space", 0.0)) - float(Catalog.get_building("b_002").tile_size_used) * BuildingLevels.mult("size", 2)) < 0.01,
		"levelled build: two turns longer, on the level's footprint")
	_check(Construction.placing_level == 1 and BuildMode.attempt_level == 1, "levelled build: the level is one attempt only")
	var iid := str(project.get("instance_id", ""))
	if iid != "":
		Construction._promote(iid)
	_check(int(BuildingState.get_building(iid).get("level", 0)) == 2, "levelled build: it finishes at that level")
	inst.queue_free()
	await get_tree().process_frame
	_fresh()


func _test_quick_menu_draws() -> void:
	_fresh()
	var steel := _gid("steel")
	Stockpile.add(TILE, steel, 12)
	var menu: PopupPanel = load("res://scripts/tile_quick_menu.gd").new()
	add_child(menu)
	menu.open_for({"id": TILE}, Vector2(100, 100))
	await get_tree().process_frame
	var names: Array = []
	for n in ["SellSurplus", "SellGood", "BuyLand", "SellLand", "BuildFavourite"]:
		if menu.find_child("QuickAction_" + n, true, false) != null:
			names.append(n)
	_check(names.size() == 5, "quick menu: the five actions are listed")
	var title: Label = menu.find_child("QuickMenuTitle", true, false)
	_check(title != null and title.text == Actions.place(TILE) and not title.text.contains("("), "quick menu: the tile's name heads it, without coordinates")
	_check(bool(menu.find_child("QuickAction_BuildFavourite", true, false).get_meta("disabled", false)),
		"quick menu: with no favourites, Build a favourite cannot run and says why")
	menu.show_page("goods")
	_check(menu.find_child("QuickAction_Good_" + steel, true, false) != null and menu.find_child("QuickAction_Back", true, false) != null,
		"quick menu: the goods page lists the tile's goods under Back")
	menu.show_page("buy_land")
	_check(menu.find_child("QuickKey_BuyLandConfirm", true, false) != null, "quick menu: buying all the land asks first")
	menu.queue_free()
	await get_tree().process_frame
	_fresh()
