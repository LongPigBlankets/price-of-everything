extends Node
## Headless verification of the tutorial glass-pipe lesson MECHANIC (not the coach UI).
## Boots the tutorial start with the real main scene, then asserts the facts the redesigned
## glass branch depends on: the port pipe terminal seeds in from data/starts/tutorial.json,
## the furnace tile (tile_5_9) is port-adjacent buildable land, and sodium_hydroxide (a
## hazard_liquid) only routes to the furnace once the player lays a reinforced pipe joining
## that tile to the pre-piped port. A failed seed or bad adjacency would soft-lock glass_run,
## so this guards the whole lesson. Run:
##   <godot> --headless --path . res://tools/tutorial_pipe_verify.tscn --quit-after 900

const BuildingReadout := preload("res://scripts/building_readout.gd")
const TutorialDetectors := preload("res://scripts/tutorial/tutorial_detectors.gd")
const TutorialSteps := preload("res://scripts/tutorial/tutorial_steps.gd")

const MAIN_SCENE := "res://scenes/main.tscn"
const TUTORIAL_START := "res://data/starts/tutorial.json"
const WINDOW_TILE := "tile_5_9"    # NPC window factory + co-located producers (== GLASS_TILE)
const GLASS_TILE := "tile_5_9"     # furnace tile (must match TutorialSteps.GLASS_TILE)
const PORT_TILE := "tile_5_10"     # Stoneshore Docks (pre-seeded reinf_pipes terminal, hex-adjacent south)
const NAOH := "g_013"              # sodium_hydroxide

var _passed := 0
var _failed := 0
var _main: Node = null


func _ready() -> void:
	print("\n==== tutorial glass-pipe verification ====")
	await _run()
	print("==== tutorial-pipe %d passed, %d failed ====\n" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _run() -> void:
	SaveLoad.prepare_new_game(TUTORIAL_START)
	var packed := load(MAIN_SCENE) as PackedScene
	_check(packed != null, "main scene loads")
	if packed == null:
		return
	_main = packed.instantiate()
	add_child(_main)
	await _await_build_complete()

	# The good under test (resolve id -> name so a CSV re-number is caught).
	_check(Catalog.get_internal_name(NAOH) == "sodium_hydroxide",
		"g_013 is sodium_hydroxide")
	_check(Catalog.get_transport_class(NAOH) == "hazard_liquid",
		"sodium_hydroxide is a hazard_liquid (pipe-only)")

	# Start-config seeding applied.
	_check(int(MatchState.money) == 2500,
		"tutorial start grants 2500 money (got %d)" % int(MatchState.money))
	_check(Catalog.tile_has_infrastructure(PORT_TILE, "reinf_pipes"),
		"port tile pre-seeded with a reinforced-pipe terminal")
	_check(not Catalog.tile_has_infrastructure(GLASS_TILE, "reinf_pipes"),
		"furnace tile has NO reinforced pipe yet (player builds it)")

	# Geometry: furnace tile is port-adjacent buildable land; the port is its nearest port.
	_check(Catalog.tile_neighbours(GLASS_TILE).has(PORT_TILE),
		"furnace tile is hex-adjacent to the port (single-hop pipe)")
	_check(Catalog.is_land_tile(GLASS_TILE),
		"furnace tile is buildable land")
	_check(TransportService.nearest_port_tile(GLASS_TILE) == PORT_TILE,
		"the port is the furnace tile's nearest port (fluid lands there)")

	# The lesson's crux: NaOH cannot reach the furnace until the player pipes ITS tile,
	# even though the port terminal is already piped (both endpoints must carry reinf_pipes).
	var before := TransportService.route(PORT_TILE, GLASS_TILE, NAOH)
	_check(not TransportService.route_is_reachable(before),
		"sodium_hydroxide is UNREACHABLE before the furnace tile is piped (diagnosis fires)")
	# The real production delivery path (quote_market_buy) is also blocked pre-pipe — note the
	# PORT terminal is already piped, so it's the furnace tile's missing pipe that blocks it.
	_check(TransportService.quote_market_buy(GLASS_TILE, NAOH, 3, false).is_empty(),
		"market-buy of sodium_hydroxide is blocked before the furnace tile is piped")

	Catalog.add_tile_infrastructure(GLASS_TILE, "reinf_pipes")
	var after := TransportService.route(PORT_TILE, GLASS_TILE, NAOH)
	_check(TransportService.route_is_reachable(after),
		"sodium_hydroxide becomes REACHABLE once the furnace tile is piped to the port")
	var legs: Array = after.get("legs", [])
	var mode := "" if legs.is_empty() else str((legs[0] as Dictionary).get("mode", ""))
	_check(mode == "reinf_pipes",
		"the fluid route runs over reinf_pipes (got '%s')" % mode)
	_check(not TransportService.quote_market_buy(GLASS_TILE, NAOH, 3, false).is_empty(),
		"market-buy of sodium_hydroxide succeeds once the furnace tile is piped")

	# --- Co-location layout: NPC window factory on the port-adjacent tile, producers co-locate here,
	#     the tile is un-cabled so the "lay a cable for power" lesson still lands.
	_check(_npc_building_on(WINDOW_TILE, "b_007"),
		"NPC window factory (b_007) seeds on the co-location tile %s" % WINDOW_TILE)
	_check(not Catalog.tile_has_infrastructure(WINDOW_TILE, "cables"),
		"factory tile has NO cables (the power lesson still needs the player to lay one)")

	# --- Research sub-flow: the better glass recipe r_054 is gated behind High Strength Glassmaking.
	# Gates store research_node_ids since the id migration — resolve the title to its id.
	_check(str(Catalog.get_recipe("r_054").get("tech_unlock_req", ""))
			== MatchState.research_node_id_for_title("High Strength Glassmaking"),
		"r_054 (better glass) is gated behind the High Strength Glassmaking research node")
	_check(not MatchState.is_unlocked("High Strength Glassmaking"),
		"High Strength Glassmaking starts locked (player unlocks it via a free unlock)")
	_check(not TutorialDetectors.poll({"kind": "research_unlocked", "title": "High Strength Glassmaking"}),
		"research_unlocked detector false before the node is unlocked")
	_check(not TutorialDetectors.poll({"kind": "building_recipe_on_tile", "tile": GLASS_TILE, "recipe_id": "r_054"}),
		"building_recipe_on_tile r_054 false before the furnace is retooled")

	# --- goto_tile step: the tile_panel_open detector flips true once the player opens a tile.
	_check(not TutorialDetectors.poll({"kind": "tile_panel_open", "tile": WINDOW_TILE}),
		"tile_panel_open is false before the window tile is opened")
	MatchState.focus_tile_requested.emit(WINDOW_TILE)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(TutorialDetectors.poll({"kind": "tile_panel_open", "tile": WINDOW_TILE}),
		"tile_panel_open flips true once the window tile panel is open")

	# --- Bottom-menu buttons TOGGLE their panel (open on first press, close on the second).
	var cbtn := _main.find_child("ConstructButton", true, false) as BaseButton
	var cpanel := _main.find_child("ConstructPanel", true, false) as Control
	if cbtn != null and cpanel != null:
		if cpanel.visible:
			cbtn.pressed.emit()
			await get_tree().process_frame
		cbtn.pressed.emit()
		await get_tree().process_frame
		_check(cpanel.visible, "Construct button opens the construct panel")
		cbtn.pressed.emit()
		await get_tree().process_frame
		_check(not cpanel.visible, "Construct button pressed again toggles the panel closed")

	# --- Step-5 breakdown: the window factory (r_056) must be buildable on the co-location
	#     tile so its recipe row renders, and the buy/sourcing spotlight nodes must exist.
	var wf_recipe: Dictionary = Catalog.get_recipe("r_056")
	var wf_bid := str(wf_recipe.get("building_id", ""))
	_check(wf_bid != "" and not Catalog.get_building(wf_bid).is_empty(),
		"r_056 (Window Manufacturing) maps to a real buildable building (got '%s')" % wf_bid)
	_check(str(wf_recipe.get("tech_unlock_req", "")) == "",
		"r_056 is not research-gated (its build row always shows)")
	# The tile panel exposes the named "Buy Buildings" button (build_close_buy spotlight).
	MatchState.focus_tile_requested.emit(WINDOW_TILE)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_main.find_child("BLBuyBuildingsButton", true, false) != null,
		"tile panel exposes the named 'Buy Buildings' button (BLBuyBuildingsButton)")
	# Opening Build on the factory tile lists the window recipe row (build_pick_recipe spotlight).
	var bbtn := _main.find_child("BLBuildButton", true, false) as BaseButton
	if bbtn != null:
		bbtn.pressed.emit()
		await get_tree().process_frame
		await get_tree().process_frame
		_check(_main.find_child("RecipeRow_r_056", true, false) != null,
			"opening Build on the factory tile lists the window recipe row (RecipeRow_r_056)")
	# The sourcing dialog carries the named cost card + buy button the tutorial spotlights.
	var dlg: Control = load("res://scripts/construction_missing_dialog.gd").new()
	add_child(dlg)
	await get_tree().process_frame
	_check(dlg.find_child("SourcingMarketCost", true, false) != null,
		"sourcing dialog has the named market-cost card (SourcingMarketCost)")
	_check(dlg.find_child("SourcingBuyButton", true, false) != null,
		"sourcing dialog has the named buy button (SourcingBuyButton)")
	dlg.queue_free()

	# --- Buy Land lesson: the tutorial seeds ONLY the factory plot; the furnace build
	#     hits the owned-land wall until the player buys the shortfall. All figures are
	#     COMPUTED from the catalog + TutorialSteps so rebalances keep this green.
	var seed: int = TutorialSteps.TUTORIAL_SEED_LAND
	var target: int = TutorialSteps._land_lesson_target()
	var fp_factory: int = TutorialSteps._footprint("b_007")
	var fp_cable: int = TutorialSteps._footprint("b_006")
	var fp_furnace: int = TutorialSteps._footprint("b_002")
	var fp_pipe: int = TutorialSteps._footprint("b_018")
	_check(MatchState.get_tile_land_owned(WINDOW_TILE) == seed,
		"tutorial start seeds %d land on the factory tile (got %d)" % [seed, MatchState.get_tile_land_owned(WINDOW_TILE)])
	_check(MatchState.get_tile_land_owned("tile_6_6") == 0,
		"other board tiles start with no land owned")
	# The step-5 costing click (window factory footprint) fits the seeded plot.
	_check(MatchState.get_tile_player_space_used(WINDOW_TILE) + float(fp_factory) <= float(seed),
		"pricing up the window factory fits the seeded plot (the sourcing dialog can open)")
	# Buy the NPC factory as the buy_factory step does: its footprint lands as owned land.
	var fac_iid := ""
	for iid in MatchState.tile_buildings.get(WINDOW_TILE, []):
		if str(MatchState.get_building(str(iid)).get("building_id", "")) == "b_007":
			fac_iid = str(iid)
	_check(fac_iid != "", "window factory instance resolves on the co-location tile")
	MatchState.set_building_owner(fac_iid, MatchState.LOCAL_PLAYER)
	var owned_after_buy := seed + fp_factory
	_check(MatchState.get_tile_land_owned(WINDOW_TILE) == owned_after_buy,
		"buying the factory grants its footprint (owned %d)" % owned_after_buy)
	# The cable fits; WITH the cable laid (the power lesson precedes integration)
	# the furnace does not — that's the buy_land step's wall.
	var used := MatchState.get_tile_player_space_used(WINDOW_TILE)
	_check(used + float(fp_cable) <= float(owned_after_buy), "the power-lesson cable fits the granted land")
	MatchState.add_building("b_006", "", WINDOW_TILE)   # the cable the power lesson lays
	used = MatchState.get_tile_player_space_used(WINDOW_TILE)
	_check(used + float(fp_furnace) > float(owned_after_buy),
		"the furnace does NOT fit before the buy_land step (%d + %d > %d)" % [int(used), fp_furnace, owned_after_buy])
	_check(not TutorialDetectors.poll({"kind": "tile_land_at_least", "tile": WINDOW_TILE, "amount": target}),
		"tile_land_at_least(%d) false before the purchase" % target)
	var patches := ceili(float(target - owned_after_buy) / float(MatchState.LAND_PATCH_SIZE))
	_check(MatchState.purchase_tile_land(WINDOW_TILE, patches),
		"buying %d land patch(es) on the factory tile succeeds" % patches)
	_check(TutorialDetectors.poll({"kind": "tile_land_at_least", "tile": WINDOW_TILE, "amount": target}),
		"tile_land_at_least(%d) true after the purchase — buy_land advances" % target)
	_check(MatchState.get_tile_player_space_used(WINDOW_TILE) + float(fp_furnace + fp_pipe) <= float(target),
		"furnace + reinforced pipe fit the purchased land (both branches unblocked)")

	# --- Transport lesson: the building panel's output card opens the routing sheet,
	#     and the route detectors track the redirect → revert loop.
	MatchState.focus_building_requested.emit(fac_iid)
	await get_tree().process_frame
	await get_tree().process_frame
	var out_card := _main.find_child("OutputDestCard", true, false) as Control
	_check(out_card != null and out_card.is_visible_in_tree(),
		"building panel exposes the output-destination card (OutputDestCard)")
	if out_card != null:
		var ev := InputEventMouseButton.new()
		ev.pressed = true
		ev.button_index = MOUSE_BUTTON_LEFT
		out_card.gui_input.emit(ev)
		await get_tree().process_frame
		_check(TutorialDetectors.poll({"kind": "node_visible", "ref": "ActionSheet"}),
			"clicking the card opens the routing sheet (ActionSheet) — redirect step advances")
	var wf_good := str(Catalog.get_recipe("r_056").get("output_good_id", ""))
	_check(wf_good != "", "window recipe has an output good for routing")
	_check(not TutorialDetectors.poll({"kind": "output_routed_offtile", "tile": WINDOW_TILE, "building_id": "b_007"}),
		"output_routed_offtile false before the redirect")
	MatchState.set_output_stockpile_destination(fac_iid, "tile_5_7", wf_good)
	_check(TutorialDetectors.poll({"kind": "output_routed_offtile", "tile": WINDOW_TILE, "building_id": "b_007"}),
		"output_routed_offtile true once shipped to the sand tile")
	MatchState.route_output_to_market(fac_iid, wf_good)
	_check(TutorialDetectors.poll({"kind": "output_routed_market", "tile": WINDOW_TILE, "building_id": "b_007"}),
		"output_routed_market true once set back to Global market")
	_check(_main.find_child("EmpireView", true, false) != null,
		"empire view exists for the Tab lesson (transport_ports)")


## Wait for the async terrain build, then a couple more frames so world_map._ready's
## SaveLoad.apply_pending() (which applies the infrastructure seed) has run.
func _await_build_complete() -> void:
	var frames := 0
	while frames < 1800:
		if _main != null and _main.get("build_complete") == true:
			await get_tree().process_frame
			await get_tree().process_frame
			return
		await get_tree().process_frame
		frames += 1


func _npc_building_on(tile: String, bid: String) -> bool:
	for iid in MatchState.buildings:
		var inst: Dictionary = MatchState.buildings[iid]
		if str(inst.get("tile_id", "")) == tile and str(inst.get("building_id", "")) == bid:
			return true
	return false


func _check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  PASS  %s" % label)
	else:
		_failed += 1
		print("  FAIL  %s" % label)
