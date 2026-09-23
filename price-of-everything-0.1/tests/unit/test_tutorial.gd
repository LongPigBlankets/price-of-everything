extends "res://tests/test_base.gd"
## Tutorial engine, steps and detectors.

const FEATURE := "tutorial"
## Tests that also belong to other features (run under any of their tags).
const TAGS := {
	"_test_tutorial_rescue": ["finance", "tutorial"],
	"_test_tutorial_engine": ["construction", "finance", "production", "stockpile", "transport", "tutorial", "victory"],
}

# Tutorial "Coach" engine (Wave 1). The engine itself is signal-driven and confined to
# a live scene, so here we cover the two pure surfaces: the authored step list and the
# state-verified detectors (the only logic that decides step completion).
func _tutorial_copy_has_dash(value: Variant) -> bool:
	if value is String:
		for mark: String in ["-", "–", "—", "‑", "‐"]:
			if value.contains(mark):
				return true
	elif value is Array:
		for item: Variant in value:
			if _tutorial_copy_has_dash(item):
				return true
	elif value is Dictionary:
		for item: Variant in value.values():
			if _tutorial_copy_has_dash(item):
				return true
	return false


func _test_tutorial_rescue() -> void:
	# Tutorial matches top a negative balance back up to £2500, three times, then stop.
	# See docs/early-game-onboarding-spec.md §3.
	MatchState.reset()
	MatchState.ruleset = {"name": "tutorial", "tutorial_enabled": true}
	SolvencyState.reset()

	MatchState.money = -50.0
	SolvencyState._on_turn_resolution_completed()
	_check(is_equal_approx(MatchState.money, SolvencyState.TUTORIAL_RESCUE_CASH)
		and SolvencyState.tutorial_rescues() == 1,
		"first tutorial rescue tops the balance back up to £%.0f" % SolvencyState.TUTORIAL_RESCUE_CASH)

	for _i in range(SolvencyState.TUTORIAL_RESCUE_LIMIT - 1):
		MatchState.money = -50.0
		SolvencyState._on_turn_resolution_completed()
	_check(SolvencyState.tutorial_rescues() == SolvencyState.TUTORIAL_RESCUE_LIMIT
		and is_equal_approx(MatchState.money, SolvencyState.TUTORIAL_RESCUE_CASH),
		"the tutorial rescues %d times in total" % SolvencyState.TUTORIAL_RESCUE_LIMIT)

	# Past the limit the kindness stops and the balance is allowed to stand red.
	MatchState.money = -50.0
	SolvencyState._on_turn_resolution_completed()
	_check(is_equal_approx(MatchState.money, -50.0)
		and SolvencyState.tutorial_rescues() == SolvencyState.TUTORIAL_RESCUE_LIMIT,
		"after the last rescue a negative tutorial balance stands")

	# The rescue counter rides the save so reloading cannot refill the allowance.
	var saved: Dictionary = SolvencyState.export_state()
	SolvencyState.reset()
	SolvencyState.import_state(saved)
	_check(SolvencyState.tutorial_rescues() == SolvencyState.TUTORIAL_RESCUE_LIMIT,
		"the tutorial rescue count survives save/load")

	# A normal match is never rescued, whatever the balance.
	MatchState.reset()
	MatchState.money = -50.0
	SolvencyState._on_turn_resolution_completed()
	_check(is_equal_approx(MatchState.money, -50.0) and SolvencyState.tutorial_rescues() == 0,
		"non-tutorial matches are never rescued")

func _test_demo_tutorial_diagnostic_lights() -> void:
	var readout = load("res://scripts/building_readout.gd")
	_check(readout.diagnostic_led_tone([{"tone": "ok"}, {"tone": "warn"}]) == "ok", "tile LED: green tolerates one amber alongside green")
	_check(readout.diagnostic_led_tone([{"tone": "ok"}, {"tone": "warn"}, {"tone": "warn"}]) == "warn", "tile LED: multiple amber diagnostics need attention")
	_check(readout.diagnostic_led_tone([{"tone": "warn"}]) == "warn", "tile LED: all amber stays amber")
	_check(readout.diagnostic_led_tone([{"tone": "ok"}, {"tone": "warn"}, {"tone": "bad"}]) == "bad", "tile LED: any red diagnostic wins")
	var steps: Array = load("res://scripts/tutorial/tutorial_steps.gd").steps()
	var ids: Array = steps.map(func(step: Dictionary) -> String: return str(step.id))
	_check(ids.find("tile_basics_select") == ids.find("ui_primer") + 1 and ids.find("recipe_inputs_intro") == ids.find("tile_basics_features") + 1, "tutorial: tile lessons lead back into the existing recipe flow")

func _test_tutorial_engine() -> void:
	var steps: Array = TutorialSteps.steps()
	for step: Dictionary in steps:
		_check(not _tutorial_copy_has_dash(step), "tutorial copy has no hyphens or dashes: " + str(step.id))
	_check(not steps.is_empty(), "tutorial: steps() returns content")
	_check(str((steps[0] as Dictionary).get("id", "")) == "welcome", "tutorial: first step is the welcome panel")
	_check(str((steps[0] as Dictionary).get("mode", "")) == "welcome", "tutorial: first step uses welcome render mode")
	_check(TutorialSteps.BOARD_TILES.has(TutorialSteps.WINDOW_TILE), "tutorial: board includes the factory tile")
	_check(TutorialSteps.BOARD_TILES.has(TutorialSteps.STUB_TILE), "tutorial: board includes the coal stub")
	_check(TutorialSteps.BOARD_TILES.has(TutorialSteps.GLASS_TILE), "tutorial: board includes the glass furnace tile (port-adjacent)")

	# The New Game "have you done the tutorial?" gate reads PlayerProfile.has_done_tutorial(),
	# which reflects the flag marked only by the terminal End tutorial action.
	var tut_saved: bool = PlayerProfile.tutorial_completed
	PlayerProfile.tutorial_completed = false
	_check(not PlayerProfile.has_done_tutorial(), "profile: has_done_tutorial false before finishing")
	PlayerProfile.tutorial_completed = true
	_check(PlayerProfile.has_done_tutorial(), "profile: has_done_tutorial true once the flag is set")
	PlayerProfile.tutorial_completed = tut_saved

	# Settings → Graphics resolution persists through PlayerProfile (apply is a headless no-op).
	var ws_saved: Vector2i = PlayerProfile.window_size
	PlayerProfile.set_window_size(Vector2i(3440, 1440))
	_check(PlayerProfile.window_size == Vector2i(3440, 1440), "profile: set_window_size stores the chosen resolution")

	# Fullscreen, target monitor, and audio volumes are settings that persist across sessions.
	# Verify the setters store them and that they survive the profile's JSON encode/decode.
	# (The real fixes: fullscreen fills the chosen screen; the monitor pick + windowed clamp
	# keep the window from overflowing a smaller external display.)
	var fs_saved: bool = PlayerProfile.fullscreen
	var sc_saved: int = PlayerProfile.screen_index
	var al_saved: Dictionary = PlayerProfile.audio_levels.duplicate()
	PlayerProfile.set_display(false, Vector2i(1920, 1080), 0)
	_check(PlayerProfile.fullscreen == false and PlayerProfile.window_size == Vector2i(1920, 1080) and PlayerProfile.screen_index == 0, "profile: set_display stores mode + windowed size + monitor")
	PlayerProfile.set_audio_levels({"Master": 100.0, "Music": 55.0, "SFX": 30.0})
	_check(int(PlayerProfile.audio_levels.get("Music", 0)) == 55, "profile: set_audio_levels stores volumes")
	var round_trip: Variant = JSON.parse_string(JSON.stringify({"fullscreen": PlayerProfile.fullscreen, "screen_index": PlayerProfile.screen_index, "audio_levels": PlayerProfile.audio_levels}))
	_check(round_trip is Dictionary and (round_trip as Dictionary).get("fullscreen") == false \
		and int((round_trip as Dictionary).get("screen_index", -99)) == 0 \
		and int(((round_trip as Dictionary).get("audio_levels", {}) as Dictionary).get("Music", 0)) == 55, \
		"profile: display + audio prefs survive a JSON round-trip")

	PlayerProfile.fullscreen = fs_saved
	PlayerProfile.set_audio_levels(al_saved)              # restore + re-persist the originals
	PlayerProfile.set_display(fs_saved, ws_saved, sc_saved)
	_check(PlayerProfile.window_size == ws_saved and PlayerProfile.screen_index == sc_saved, "profile: window_size + monitor restored after test")

	var terminal_present := false
	var terminal_step: Dictionary = {}
	for s in steps:
		if str((s as Dictionary).get("id", "")) == "integration_done":
			terminal_present = true
			terminal_step = s as Dictionary
	_check(terminal_present, "tutorial: terminal integration_done step exists (the completion hook target)")
	_check(str(terminal_step.get("title", "")) == "Tutorial complete"
		and str(terminal_step.get("body", "")).begins_with("This tutorial has give you all the basic tools")
		and str(terminal_step.get("next_label", "")) == "End tutorial"
		and bool(terminal_step.get("hide_skip", false)),
		"tutorial: finale has one explicit End tutorial action and the requested closing copy")

	# building_owned_on_tile detector: player-owned building on the tile -> true;
	# NPC-owned -> false; unknown predicate kind -> false. Save/restore live buildings.
	var saved: Dictionary = BuildingState.buildings
	BuildingState.buildings = {
		"inst_test": {
			"instance_id": "inst_test", "building_id": "b_007",
			"tile_id": TutorialSteps.WINDOW_TILE, "owner": MatchState.LOCAL_PLAYER,
		}
	}
	var decide := {"kind": "building_owned_on_tile", "tile": TutorialSteps.WINDOW_TILE, "building_id": "b_007"}
	_check(TutorialDetectors.poll(decide) == true, "tutorial: detector true when player owns the factory")
	# building_or_project_on_tile also matches the built (player-owned) building.
	_check(TutorialDetectors.poll({"kind": "building_or_project_on_tile", "tile": TutorialSteps.WINDOW_TILE, "building_id": "b_007"}) == true,
		"tutorial: building_or_project detector matches a built building")
	BuildingState.buildings["inst_test"]["owner"] = "Vandel Glassworks"
	_check(TutorialDetectors.poll(decide) == false, "tutorial: detector false while NPC-owned")
	_check(TutorialDetectors.poll({"kind": "unknown_predicate"}) == false, "tutorial: unknown predicate never advances")
	BuildingState.buildings = saved
	# infra detectors read Catalog state; with no cables built they must be false.
	_check(TutorialDetectors.poll({"kind": "board_has_infra", "infra": "cables"}) == false,
		"tutorial: board_has_infra false before any cable is laid")
	_check(TutorialDetectors.poll({"kind": "tile_has_infra", "tile": TutorialSteps.WINDOW_TILE, "infra": "cables"}) == false,
		"tutorial: tile_has_infra false before any cable is laid")
	# The core + Integration sequence is authored end-to-end.
	var ids: Array = []
	var by_id: Dictionary = {}
	for s in steps:
		var sid := str((s as Dictionary).get("id", ""))
		ids.append(sid)
		by_id[sid] = s
	for expected in ["welcome", "ui_primer", "recipe_inputs_intro", "recipe_outputs_intro", "capital_motor_open", "capital_motor_watch", "capital_money_transport", "capital_road_install", "capital_road_watch", "capital_rail_build", "capital_rail_watch", "capital_fluids", "capital_port_open", "capital_port_costs", "goto_tile", "build_open", "build_pick_recipe", "build_cost", "build_close_buy", "buy_factory", "diagnose_factory", "lay_cable_factory", "run_until_running", "analyse_supply", "explore_encyclopedia", "close_encyclopedia", "revenue_settle", "choose_integration", "build_glass_open", "build_glass_recipe", "build_glass_confirm", "glass_sell", "glass_wait_built", "glass_diagnose_pipe", "glass_lay_pipe", "glass_run", "glass_profit", "glass_research", "glass_upgrade", "build_alu_open", "alu_run_base", "alu_output_check", "alu_base_settle", "alu_research", "alu_research_search", "alu_research_condition", "alu_research_unlock", "alu_upgrade", "alu_diagnose_pipe", "alu_lay_pipe", "alu_final_run", "alu_profit", "integration_done"]:
		_check(expected in ids, "tutorial: step '%s' present" % expected)
	for removed in ["open_mapmodes", "select_logistics", "view_shipment", "transport_ports"]:
		_check(not (removed in ids), "tutorial: redundant old transport step '%s' removed" % removed)
	# The two production diagrams and seven counted Capital beats appear before the
	# existing window-factory tutorial. Output routing and the first shipment now
	# receive their own displayed Step 6 and Step 7.
	var opening_beats := 0
	for i in range(ids.find("ui_primer") + 1, ids.find("goto_tile")):
		if bool((steps[i] as Dictionary).get("count_step", true)):
			opening_beats += 1
	_check(opening_beats == 12, "tutorial: three tile lessons, two recipe diagrams and seven counted Capital beats precede the factory lesson")
	var output_route_step: Dictionary = by_id.get("capital_motor_route", {})
	_check(ids.find("capital_motor_route") == ids.find("capital_motor_open") + 1
		and ids.find("capital_motor_watch") == ids.find("capital_motor_route") + 1
		and bool(output_route_step.get("count_step", true))
		and bool((by_id.get("capital_motor_watch", {}) as Dictionary).get("count_step", true)),
		"tutorial: output destinations and first shipment are separate counted Steps 6 and 7")
	_check(not bool(output_route_step.get("spotlight_passthrough", true)),
		"tutorial: Step 6 highlights Output destination without allowing an accidental click")
	var shipment_camera: Dictionary = (by_id.get("capital_motor_watch", {}) as Dictionary).get("camera", {})
	var shipment_camera_tiles: Array = shipment_camera.get("tiles", [])
	_check(shipment_camera_tiles.has(TutorialSteps.CAPITAL_PORT_NORTH_TILE)
		and float(shipment_camera.get("grow", 0.0)) >= 300.0,
		"tutorial: Step 7 zooms out far enough to include the tile north of Capital Port")
	var transport_bill_step: Dictionary = by_id.get("capital_money_transport", {})
	_check(str(transport_bill_step.get("title", "")) == "Transporting without roads is slow and inefficient"
		and str(transport_bill_step.get("body", "")).begins_with("Transporting offroad/using unpaved roads"),
		"tutorial: Step 8 plainly explains the cost of travelling without roads")
	var coach_overlay = load("res://scripts/tutorial/coach_overlay.gd").new()
	add_child(coach_overlay)
	coach_overlay._hole = Rect2(10, 10, 100, 100)
	coach_overlay._spotlight_passthrough = false
	_check(coach_overlay._has_point(Vector2(20, 20)),
		"tutorial: read-only spotlight swallows a click inside its highlighted control")
	coach_overlay._spotlight_passthrough = true
	_check(not coach_overlay._has_point(Vector2(20, 20)),
		"tutorial: interactive spotlight still passes a click through its highlighted control")
	var coach_footer := coach_overlay.find_child("CoachFooter", true, false) as HBoxContainer
	var coach_skip := coach_overlay.find_child("CoachSkipButton", true, false) as LinkButton
	var coach_next := coach_overlay.find_child("CoachNextButton", true, false) as Button
	_check(coach_footer != null and coach_footer.get_index() > coach_overlay._body.get_index(),
		"tutorial: navigation sits in a footer below the coach-card text")
	_check(coach_skip != null and coach_next != null
		and coach_footer.get_child(0) == coach_skip
		and coach_footer.get_child(coach_footer.get_child_count() - 1) == coach_next
		and coach_footer.get_child(1).size_flags_horizontal == Control.SIZE_EXPAND_FILL,
		"tutorial: Skip anchors left and Next anchors right with an expanding gap")
	var fake_money_panel := Control.new()
	fake_money_panel.name = "MoneyPanel"
	fake_money_panel.position = Vector2(0, 90)
	fake_money_panel.size = Vector2(620, 900)
	add_child(fake_money_panel)
	coach_overlay.size = Vector2(1920, 1080)
	coach_overlay.show_step({
		"chapter": "Moving Goods", "title": "Transport costs", "body": "Breakdown copy.",
		"spotlight": {"kind": "none", "ref": ""}, "advance": "next",
	}, 7, 59)
	coach_overlay._reposition_card()
	_check(absf(coach_overlay._card.get_rect().get_center().x - coach_overlay.size.x * 0.5) < 1.0
		and is_equal_approx(coach_overlay._card.position.y, 110.0),
		"tutorial: a Balance-panel collision moves the coach card to centre-top below the top bar")
	fake_money_panel.free()
	var pick_recipe_step: Dictionary = by_id.get("build_pick_recipe", {})
	coach_overlay.show_step(pick_recipe_step, 13, 59)
	coach_overlay._reposition_card()
	_check(absf(coach_overlay._card.get_rect().get_center().x - coach_overlay.size.x * 0.5) < 1.0
		and is_equal_approx(coach_overlay._card.position.y, 110.0),
		"tutorial: Step 14 renders centre-top below the top bar, clear of the Construct panel")
	coach_overlay.show_step(terminal_step, 58, 59)
	_check(coach_next.text == "End tutorial" and coach_next.visible and not coach_skip.visible,
		"tutorial: terminal coach card replaces Next with End tutorial and removes the ordinary Skip link")
	coach_overlay.free()
	var fluids_body := str((by_id.get("capital_fluids", {}) as Dictionary).get("body", ""))
	_check(fluids_body.contains("as well as by road or rail")
		and fluids_body.contains("Hydrogen") and fluids_body.contains("Reinforced Pipework")
		and not fluids_body.contains("Encyclopedia entry") and not fluids_body.contains("Goods Graph"),
		"tutorial: Step 11 explains hydrogen's reinforced-pipe option alongside road and rail")
	var find_factory_step: Dictionary = by_id.get("goto_tile", {})
	var find_factory_setup: Array = find_factory_step.get("setup", [])
	var factory_camera_tiles: Array = ((find_factory_step.get("camera", {}) as Dictionary).get("tiles", []) as Array)
	var furthest_factory_camera_tile := 0
	for factory_camera_tile in factory_camera_tiles:
		furthest_factory_camera_tile = maxi(furthest_factory_camera_tile,
			Catalog.tile_hex_distance(TutorialSteps.WINDOW_TILE, str(factory_camera_tile)))
	_check(factory_camera_tiles.size() > 37 and furthest_factory_camera_tile == 5
		and factory_camera_tiles.has(TutorialSteps.PORT_TILE)
		and (find_factory_step.get("board_tiles", []) as Array) == TutorialSteps.BOARD_TILES,
		"tutorial: Step 12 pans across a radius-five factory view without widening build access")
	_check(not find_factory_setup.is_empty()
		and str((find_factory_setup[0] as Dictionary).get("action", "")) == "handoff_from_capital_lesson",
		"tutorial: Step 12 begins by retiring the Capital demonstration")

	# The handoff must remove every future Capital-demo payday without touching unrelated
	# freight, then present the west-coast lesson with a clean £99,999 balance.
	var handoff_buildings_saved: Dictionary = BuildingState.buildings
	var handoff_tile_buildings_saved: Dictionary = BuildingState.tile_buildings
	var handoff_shipments_saved: Array = TransportState.pending_transport_shipments
	var handoff_stock_saved: Dictionary = Stockpile.export_state()
	var handoff_money_saved := MatchState.money
	var handoff_fake_money_saved := MatchState.fake_money_this_turn
	var handoff_summary_saved: Dictionary = Production.last_turn_summary.duplicate(true)
	var handoff_queued_sales_saved: Dictionary = MatchState.queued_stockpile_market_sales
	var handoff_sell_surplus_saved: Dictionary = MatchState.sell_surplus_tiles
	var handoff_auto_sell_saved: Dictionary = MatchState.auto_sell_goods
	var handoff_auto_keep_saved: Dictionary = MatchState.auto_sell_keep
	var handoff_auto_impact_saved: Dictionary = MatchState.auto_sell_impact
	var handoff_sales_by_tile_saved: Dictionary = MatchState.sales_by_tile
	BuildingState.buildings = {
		"tutorial_motor": {"instance_id": "tutorial_motor", "building_id": "b_007",
			"recipe_id": "r_009", "tile_id": TutorialSteps.MOTOR_TILE, "owner": MatchState.LOCAL_PLAYER},
		"tutorial_steel": {"instance_id": "tutorial_steel", "building_id": "b_008",
			"recipe_id": "r_076", "tile_id": TutorialSteps.STEEL_TILE, "owner": MatchState.LOCAL_PLAYER},
		"tutorial_rail": {"instance_id": "tutorial_rail", "building_id": "b_019",
			"recipe_id": "", "tile_id": TutorialSteps.CAPITAL_RAIL_BUILD_TILES[0], "owner": MatchState.LOCAL_PLAYER},
		"tutorial_road": {"instance_id": "tutorial_road", "building_id": "b_005",
			"recipe_id": "", "tile_id": TutorialSteps.CAPITAL_RAIL_BUILD_TILES[1], "owner": MatchState.LOCAL_PLAYER},
		"unrelated_rail": {"instance_id": "unrelated_rail", "building_id": "b_019",
			"recipe_id": "", "tile_id": TutorialSteps.WINDOW_TILE, "owner": MatchState.LOCAL_PLAYER},
	}
	BuildingState.tile_buildings = {
		TutorialSteps.MOTOR_TILE: ["tutorial_motor", "tutorial_rail"],
		TutorialSteps.STEEL_TILE: ["tutorial_steel"],
		TutorialSteps.CAPITAL_RAIL_BUILD_TILES[1]: ["tutorial_road"],
		TutorialSteps.WINDOW_TILE: ["unrelated_rail"],
	}
	TransportState.pending_transport_shipments = [
		{"is_sale": true, "source_tile": TutorialSteps.MOTOR_TILE},
		{"is_sale": true, "source_tile": TutorialSteps.STEEL_TILE},
		{"is_sale": true, "source_tile": TutorialSteps.WINDOW_TILE},
		{"is_sale": false, "source_tile": TutorialSteps.MOTOR_TILE},
	]
	Stockpile.clear_all()
	Stockpile.add(TutorialSteps.MOTOR_TILE, "g_006", 32)
	Stockpile.add(TutorialSteps.STEEL_TILE, "g_030", 16)
	MatchState.queued_stockpile_market_sales = {TutorialSteps.MOTOR_TILE: true}
	MatchState.sell_surplus_tiles = {TutorialSteps.MOTOR_TILE: true}
	MatchState.auto_sell_goods = {TutorialSteps.STEEL_TILE: {"g_030": true}}
	MatchState.auto_sell_keep = {TutorialSteps.STEEL_TILE: {"g_030": 1}}
	MatchState.auto_sell_impact = {TutorialSteps.STEEL_TILE: {"g_030": 1}}
	MatchState.sales_by_tile = {TutorialSteps.MOTOR_TILE: {"units": 28, "revenue": 100.0}}
	MatchState.money = 123.0
	MatchState.fake_money_this_turn = 50.0
	Production.last_turn_summary = {"money_in": 100.0, "sold": {"g_025": {"qty": 28}}}
	Tutorial._handoff_from_capital_lesson()
	var handoff_remaining_sales := 0
	for handoff_shipment in TransportState.pending_transport_shipments:
		if bool((handoff_shipment as Dictionary).get("is_sale", false)):
			handoff_remaining_sales += 1
	_check(str((BuildingState.buildings["tutorial_motor"] as Dictionary).get("owner", "")) == BuildingState.SOLD_TO_OWNER
		and str((BuildingState.buildings["tutorial_steel"] as Dictionary).get("owner", "")) == BuildingState.SOLD_TO_OWNER,
		"tutorial: Capital motor and steel demonstrations transfer to an NPC at the handoff")
	_check(str((BuildingState.buildings["tutorial_rail"] as Dictionary).get("owner", "")) == "tile_data"
		and str((BuildingState.buildings["tutorial_road"] as Dictionary).get("owner", "")) == "tile_data"
		and BuildingState.is_player_owned(BuildingState.buildings["unrelated_rail"]),
		"tutorial: Capital roads and rails become general infrastructure without transferring unrelated assets")
	_check(handoff_remaining_sales == 1 and TransportState.pending_transport_shipments.size() == 2,
		"tutorial: handoff cancels only Capital-demo sales and preserves unrelated freight")
	_check(Stockpile.get_used_capacity(TutorialSteps.MOTOR_TILE) == 0
		and Stockpile.get_used_capacity(TutorialSteps.STEEL_TILE) == 0
		and not MatchState.is_stockpile_market_sale_queued(TutorialSteps.MOTOR_TILE)
		and not MatchState.is_sell_surplus_enabled(TutorialSteps.MOTOR_TILE)
		and not MatchState.is_auto_sell_good(TutorialSteps.STEEL_TILE, "g_030"),
		"tutorial: handoff transfers demo inventory and disarms tile-level sale orders")
	_check(is_equal_approx(MatchState.money, float(TutorialSteps.WEST_COAST_HANDOFF_CASH))
		and is_zero_approx(MatchState.fake_money_this_turn)
		and Production.last_turn_summary.is_empty(),
		"tutorial: west-coast lesson starts from clean £99,999 cash and no motor-era summary")
	BuildingState.buildings = handoff_buildings_saved
	BuildingState.tile_buildings = handoff_tile_buildings_saved
	TransportState.pending_transport_shipments = handoff_shipments_saved
	Stockpile.import_state(handoff_stock_saved)
	MatchState.money = handoff_money_saved
	MatchState.fake_money_this_turn = handoff_fake_money_saved
	Production.last_turn_summary = handoff_summary_saved
	MatchState.queued_stockpile_market_sales = handoff_queued_sales_saved
	MatchState.sell_surplus_tiles = handoff_sell_surplus_saved
	MatchState.auto_sell_goods = handoff_auto_sell_saved
	MatchState.auto_sell_keep = handoff_auto_keep_saved
	MatchState.auto_sell_impact = handoff_auto_impact_saved
	MatchState.sales_by_tile = handoff_sales_by_tile_saved
	_check(str(pick_recipe_step.get("card_side", "")) == "center_top",
		"tutorial: Step 14 pins its coach card centre-top above the Construct panel")
	_check(str((by_id.get("build_glass_recipe", {}) as Dictionary).get("card_side", "")) == "center_top"
		and str((by_id.get("build_alu_recipe", {}) as Dictionary).get("card_side", "")) == "center_top",
		"tutorial: Step 39 pins both integration recipe cards centre-top above the Construct panel")
	var build_cost_body := str((by_id.get("build_cost", {}) as Dictionary).get("body", ""))
	_check(build_cost_body.begins_with("Constructing the factory costs more because")
		and build_cost_body.contains("steel, concrete and frames"),
		"tutorial: Step 15 explains imported construction materials and cheaper integration")
	var buy_instead_step: Dictionary = by_id.get("build_close_buy", {})
	_check(str(buy_instead_step.get("title", "")) == "Let's buy it instead"
		and str(buy_instead_step.get("body", "")).begins_with("Now open this tile's Buildings"),
		"tutorial: Step 16 goes straight from the buy header to opening Buildings for sale")
	var buy_factory_step: Dictionary = by_id.get("buy_factory", {})
	_check(str(buy_factory_step.get("body", "")).begins_with("The £")
		and str(buy_factory_step.get("body", "")).contains("first 2 turns of supplies")
		and str(buy_factory_step.get("body", "")).ends_with("(assuming power)."),
		"tutorial: Step 17 explains that the higher purchase price includes two turns of inputs")
	var recipe_intro_step: Dictionary = by_id.get("recipes_intro", {})
	var recipe_intro_setup: Array = recipe_intro_step.get("setup", [])
	_check(str(recipe_intro_step.get("title", "")) == "This factory runs a window making recipe"
		and str(recipe_intro_step.get("body", "")).begins_with("Window factories consume aluminium")
		and str(recipe_intro_step.get("body", "")).ends_with("Click next to begin fixing it."),
		"tutorial: Step 18 introduces the window recipe and its two diagnostic faults")
	_check(not recipe_intro_setup.is_empty()
		and str((recipe_intro_setup[0] as Dictionary).get("action", "")) == "close_market_panel",
		"tutorial: Step 18 closes Buildings for sale before opening the factory detail")
	_check(str((by_id.get("diagnose_factory", {}) as Dictionary).get("body", ""))
		== "The red Power row is the blocker: the factory has no electricity, so it's switched off.",
		"tutorial: Step 19 keeps only the power diagnosis")
	_check(not str((by_id.get("lay_cable_source", {}) as Dictionary).get("body", "")).contains("—"),
		"tutorial: Step 21 stops after ordering the cable materials")
	_check(str((by_id.get("run_until_running", {}) as Dictionary).get("body", ""))
		== "It takes 2 turns for the construction materials to arrive and a 3rd turn to complete. And then the building will make windows. Click 'End turn' a few times until the building runs.",
		"tutorial: Step 22 gives the authored two-turn delivery plus one-turn build timing")
	var redirect_pick_step: Dictionary = by_id.get("transport_redirect_pick", {})
	var redirect_decide: Dictionary = (redirect_pick_step.get("done", {}) as Dictionary).get("decide", {})
	var redirect_setup: Array = redirect_pick_step.get("setup", [])
	var redirect_camera_tiles: Array = ((redirect_pick_step.get("camera", {}) as Dictionary).get("tiles", []) as Array)
	var furthest_redirect_camera_tile := 0
	for redirect_camera_tile in redirect_camera_tiles:
		furthest_redirect_camera_tile = maxi(furthest_redirect_camera_tile,
			Catalog.tile_hex_distance(TutorialSteps.WINDOW_TILE, str(redirect_camera_tile)))
	var redirect_flash: Dictionary = {}
	for redirect_action in redirect_setup:
		if str((redirect_action as Dictionary).get("action", "")) == "flash_tiles":
			redirect_flash = redirect_action as Dictionary
			break
	_check(str(redirect_decide.get("kind", "")) == "output_routed_to_tile"
		and str(redirect_decide.get("destination", "")) == TutorialSteps.WINDOW_REDIRECT_TILE
		and (redirect_pick_step.get("board_tiles", []) as Array).has(TutorialSteps.WINDOW_REDIRECT_TILE),
		"tutorial: Step 24 requires the coastal tile immediately east of the factory")
	_check((redirect_flash.get("tiles", []) as Array) == [TutorialSteps.WINDOW_REDIRECT_TILE],
		"tutorial: Step 24 flashes its exact coastal destination")
	_check(str(redirect_flash.get("color", "")) == "white"
		and int(redirect_flash.get("pulse_count", 0)) == 10
		and is_equal_approx(float(redirect_flash.get("pulse_seconds", 0.0)), 0.7),
		"tutorial: Step 24 flashes Stoneshore Coast white ten times for 0.7 seconds each")
	_check(redirect_camera_tiles.size() > 37 and furthest_redirect_camera_tile == 5
		and redirect_camera_tiles.has(TutorialSteps.PORT_TILE),
		"tutorial: Step 24 restores the radius-five camera clamp for the remaining west-coast lessons")
	var redirect_arrival_step: Dictionary = by_id.get("transport_pentagon_revert", {})
	var redirect_arrival_decide: Dictionary = (redirect_arrival_step.get("done", {}) as Dictionary).get("decide", {})
	_check(str(redirect_arrival_decide.get("kind", "")) == "stockpile_good_at_least"
		and str(redirect_arrival_decide.get("tile", "")) == TutorialSteps.WINDOW_REDIRECT_TILE
		and str(redirect_arrival_decide.get("good", "")) == "windows",
		"tutorial: Step 25 advances only after windows arrive on the eastern coastal tile")
	var margin_setup_actions: Array = (by_id.get("margin_motivation", {}) as Dictionary).get("setup", [])
	var margin_action_names: Array = []
	for margin_action in margin_setup_actions:
		margin_action_names.append(str((margin_action as Dictionary).get("action", "")))
	_check("route_building_outputs_to_market" not in margin_action_names,
		"tutorial: integration lesson leaves the output route for the player to change")
	var port_tile_ids: Array = []
	for tutorial_port in Catalog.all_ports():
		port_tile_ids.append(str((tutorial_port as Dictionary).get("tile_id", "")))
	_check(Catalog.tile_hex_distance(TutorialSteps.WINDOW_TILE, TutorialSteps.WINDOW_REDIRECT_TILE) == 1
		and not port_tile_ids.has(TutorialSteps.WINDOW_REDIRECT_TILE),
		"tutorial: the Step 24 destination is adjacent to the factory and is not a port")
	_check(TutorialSteps.CAPITAL_ROUTE_TILES.size() == 6
		and TutorialSteps.CAPITAL_ROUTE_TILES.front() == TutorialSteps.MOTOR_TILE
		and TutorialSteps.CAPITAL_ROUTE_TILES.back() == TutorialSteps.CAPITAL_PORT_TILE,
		"tutorial: Capital route is the authored five-hop factory-to-port path")
	_check(TutorialSteps.CAPITAL_RAIL_BUILD_TILES.size() == 5
		and TutorialSteps.CAPITAL_RAIL_BUILD_TILES.front() == TutorialSteps.MOTOR_TILE
		and TutorialSteps.CAPITAL_RAIL_BUILD_TILES.back() == TutorialSteps.CAPITAL_ROUTE_TILES[TutorialSteps.CAPITAL_ROUTE_TILES.size() - 2]
		and TutorialSteps.CAPITAL_RAIL_BUILD_TILES.has(TutorialSteps.MOTOR_TILE)
		and not TutorialSteps.CAPITAL_RAIL_BUILD_TILES.has(TutorialSteps.CAPITAL_PORT_TILE),
		"tutorial: rail targets include the factory tile and four tiles leading to the port")
	var rail_setup: Array = (by_id.get("capital_rail_build", {}) as Dictionary).get("setup", [])
	var rail_setup_actions: Array = []
	for rail_action in rail_setup:
		rail_setup_actions.append(str((rail_action as Dictionary).get("action", "")))
	_check(rail_setup_actions.has("close_tile_panel")
		and rail_setup_actions.find("close_tile_panel") < rail_setup_actions.find("enter_infra"),
		"tutorial: rail lesson closes the lingering Capital Port tile panel before rail mode")
	_check(rail_setup_actions.has("install_tutorial_rail_port_terminal")
		and not rail_setup_actions.has("install_tutorial_rail_terminals"),
		"tutorial: rail lesson supplies only the port terminal, leaving the factory tile to the player")
	_check(rail_setup_actions.has("hold_capital_rail_tiles")
		and not rail_setup_actions.has("flash_capital_rail_tiles"),
		"tutorial: rail targets use a persistent amber guide rather than a timed flash")
	var road_install_setup: Array = (by_id.get("capital_road_install", {}) as Dictionary).get("setup", [])
	var road_install_actions: Array = []
	for road_install_action in road_install_setup:
		road_install_actions.append(str((road_install_action as Dictionary).get("action", "")))
	_check(road_install_actions.has("clear_capital_motor_shipments")
		and road_install_actions.find("clear_capital_motor_shipments")
			< road_install_actions.find("seed_motor_shipment"),
		"tutorial: the road lesson retires the off-road motor pipeline before seeding its 28-unit shipment")
	_check(TutorialSteps.CAPITAL_ROUTE_TILES.has(TutorialSteps.MOTOR_TILE),
		"tutorial: the automatically installed road route includes the motor-factory tile")
	var rail_watch_setup: Array = (by_id.get("capital_rail_watch", {}) as Dictionary).get("setup", [])
	var rail_watch_actions: Array = []
	for rail_watch_action in rail_watch_setup:
		rail_watch_actions.append(str((rail_watch_action as Dictionary).get("action", "")))
	_check(rail_watch_actions.has("transfer_capital_transport_infrastructure")
		and rail_watch_actions.has("clear_capital_motor_shipments")
		and not rail_watch_actions.has("seed_motor_shipment"),
		"tutorial: the rail lesson clears the road pipeline and uses the factory's real 28-unit rail shipment")
	var rail_highlight = load("res://scripts/tutorial/tutorial_route_highlight.gd").new()
	add_child(rail_highlight)
	rail_highlight.flash([], 0.7, 10, Color.WHITE)
	_check(is_equal_approx(float(rail_highlight._pulse_seconds), 0.7)
		and int(rail_highlight._pulse_count) == 10
		and Color(rail_highlight._flash_color).is_equal_approx(Color.WHITE),
		"tutorial: route highlighter accepts the authored white ten-pulse cue")
	rail_highlight._holding = true
	rail_highlight._tile_centres = {
		TutorialSteps.CAPITAL_RAIL_BUILD_TILES[0]: Vector2.ZERO,
		TutorialSteps.CAPITAL_RAIL_BUILD_TILES[1]: Vector2.ONE,
	}
	rail_highlight.dismiss(TutorialSteps.CAPITAL_RAIL_BUILD_TILES[0])
	_check(rail_highlight._holding
		and not rail_highlight._tile_centres.has(TutorialSteps.CAPITAL_RAIL_BUILD_TILES[0])
		and rail_highlight._tile_centres.has(TutorialSteps.CAPITAL_RAIL_BUILD_TILES[1]),
		"tutorial: clicking one rail target dismisses only that tile's amber guide")
	rail_highlight.dismiss(TutorialSteps.CAPITAL_RAIL_BUILD_TILES[1])
	_check(not rail_highlight._holding and rail_highlight._tile_centres.is_empty(),
		"tutorial: the amber rail guide ends after every target tile has been clicked")
	rail_highlight.queue_free()
	# Regression lock for the lesson's 5 → 3 → 2 pacing, using the same live
	# Catalog router used by production shipments.
	var saved_catalog_infra: Dictionary = Catalog._tile_infra.duplicate(true)
	Catalog.reset_runtime_infrastructure()
	var motor_id := str(Catalog.get_good_by_internal_name("motor").get("id", ""))
	var no_infra_turns := int(TransportService.route(TutorialSteps.MOTOR_TILE, TutorialSteps.CAPITAL_PORT_TILE, motor_id).get("turns", -1))
	for tile_id in TutorialSteps.CAPITAL_ROUTE_TILES:
		Catalog.add_tile_infrastructure(str(tile_id), "roads")
	var road_turns := int(TransportService.route(TutorialSteps.MOTOR_TILE, TutorialSteps.CAPITAL_PORT_TILE, motor_id).get("turns", -1))
	for tile_id in TutorialSteps.CAPITAL_ROUTE_TILES:
		Catalog.add_tile_infrastructure(str(tile_id), "rails")
	var rail_turns := int(TransportService.route(TutorialSteps.MOTOR_TILE, TutorialSteps.CAPITAL_PORT_TILE, motor_id).get("turns", -1))
	_check([no_infra_turns, road_turns, rail_turns] == [5, 3, 2],
		"tutorial: live route timing is exactly 5 turns fallback, 3 road, 2 rail")
	Catalog._tile_infra = saved_catalog_infra
	Catalog._route_cache.clear()
	# The stage transition removes only old motor SALES from the Capital factory.
	# This is what prevents the truthful Sales ledger from showing two 28-unit batches
	# as 56 when the faster pipeline catches the slower one.
	var pipeline_saved: Array = TransportState.pending_transport_shipments
	var motor_good_id := str(Catalog.get_good_by_internal_name("motor").get("id", ""))
	var steel_good_id := str(Catalog.get_good_by_internal_name("steel").get("id", ""))
	TransportState.pending_transport_shipments = [
		{"id": 701, "is_sale": true, "source_tile": TutorialSteps.MOTOR_TILE,
			"sale_record": {"items": [{"good_id": motor_good_id, "qty": 28}]}},
		{"id": 702, "is_sale": true, "source_tile": TutorialSteps.MOTOR_TILE,
			"sale_record": {"items": [{"good_id": steel_good_id, "qty": 28}]}},
		{"id": 703, "is_sale": false, "source_tile": TutorialSteps.MOTOR_TILE,
			"good_id": motor_good_id, "qty": 28},
		{"id": 704, "is_sale": true, "source_tile": TutorialSteps.WINDOW_TILE,
			"sale_record": {"items": [{"good_id": motor_good_id, "qty": 28}]}},
	]
	Tutorial._clear_capital_motor_sale_shipments()
	var kept_pipeline_ids: Array = []
	for kept_shipment in TransportState.pending_transport_shipments:
		kept_pipeline_ids.append(int((kept_shipment as Dictionary).get("id", 0)))
	_check(kept_pipeline_ids == [702, 703, 704],
		"tutorial: pipeline reset removes only Capital motor sales and preserves other goods, moves and tiles")
	TransportState.pending_transport_shipments = pipeline_saved
	var welcome: Dictionary = by_id.get("welcome", {})
	var welcome_paragraphs: Array = welcome.get("paragraphs", [])
	_check(welcome_paragraphs.size() == 2 and str(welcome_paragraphs[0]).begins_with("Carbon and Capital is an industrial simulator"),
		"tutorial: welcome uses the concise Taralia introduction")
	var primer_step: Dictionary = by_id.get("ui_primer", {})
	var primer_refs: Array = []
	for target in primer_step.get("targets", []):
		primer_refs.append(str((target as Dictionary).get("ref", "")))
	_check(str(primer_step.get("card_side", "")) == "left"
		and "GoodsGraphModule" in primer_refs and "EncyclopediaButton" in primer_refs
		and "MapmodesButton" in primer_refs and "EmpireButton" in primer_refs
		and (primer_step.get("hints", []) as Array).is_empty(),
		"tutorial: Step 2 uses top-bar G/X callouts, keeps map modes, and has no left-edge hints")
	var rubber_recipe: Dictionary = Catalog.get_recipe("r_028")
	var rubber_input_ids: Array = []
	for input in rubber_recipe.get("inputs", []):
		rubber_input_ids.append(str((input as Dictionary).get("good_id", "")))
	var rubber_output_ids: Array = []
	for output in rubber_recipe.get("outputs", []):
		rubber_output_ids.append(str((output as Dictionary).get("good_id", "")))
	_check("g_024" in rubber_input_ids and "g_011" in rubber_input_ids
		and "g_028" in rubber_output_ids and int(rubber_recipe.get("energy_req", 0)) > 0,
		"tutorial: production diagram matches the live ethylene + oxygen + power to rubber recipe")
	_check("advisors_hire" in ids, "tutorial: advisor flow has a seat-agnostic assignment step")
	var advisor_inspect: Dictionary = by_id.get("advisors_inspect", {})
	var advisor_inspect_done: Dictionary = advisor_inspect.get("done", {})
	var advisor_inspect_decide: Dictionary = advisor_inspect_done.get("decide", {})
	_check(advisor_inspect_decide.is_empty() and bool(advisor_inspect.get("no_dim", false))
		and str(advisor_inspect.get("spotlight", {}).get("kind", "")) == "none",
		"tutorial: advisor comparison stays open and undimmed until explicit candidate choice")
	_check(Tutorial.is_active_step("not_a_real_step") == false,
		"tutorial: inactive step guard is false outside an active tutorial")
	var tutorial_active_saved := Tutorial.active
	Tutorial.active = true
	_check(Tutorial.port_purchase_disabled("b_004")
		and not Tutorial.port_purchase_disabled("b_007"),
		"tutorial: purchase guard disables Capital Port only")
	_check(Tutorial.PORT_PURCHASE_DISABLED_TOOLTIP == "This option is disabled during the tutorial",
		"tutorial: disabled port purchase uses the authored hover text")
	Tutorial.active = false
	_check(not Tutorial.port_purchase_disabled("b_004"),
		"tutorial: Capital Port purchase is restored outside the tutorial")
	Tutorial.active = tutorial_active_saved
	_check(TutorialDetectors.poll({"kind": "node_hidden", "ref": "NoSuchNode_xyz"}) == true,
		"tutorial: node_hidden true for a missing node")
	# New detectors are wired and default false in a fresh scene.
	_check(TutorialDetectors.poll({"kind": "building_running_on_tile", "tile": TutorialSteps.WINDOW_TILE, "building_id": "b_007"}) == false,
		"tutorial: building_running_on_tile false before the factory runs")
	_check(TutorialDetectors.poll({"kind": "tile_cabled_or_ordered", "tile": TutorialSteps.WINDOW_TILE}) == false,
		"tutorial: tile_cabled_or_ordered false before any cable")
	_check(TutorialDetectors.poll({"kind": "tile_infra_or_ordered", "tile": TutorialSteps.GLASS_TILE, "infra": "reinf_pipes", "building_id": "b_018"}) == false,
		"tutorial: tile_infra_or_ordered false before any reinforced pipe is laid")
	_check(TutorialDetectors.poll({"kind": "tile_panel_open", "tile": TutorialSteps.WINDOW_TILE}) == false,
		"tutorial: tile_panel_open false before the tile panel is opened")
	# The UI-primer step annotates HUD nodes with labels + leader lines.
	var primer: Dictionary = by_id.get("ui_primer", {})
	_check(str(primer.get("mode", "")) == "annotate" and (primer.get("targets", []) as Array).size() >= 8,
		"tutorial: ui_primer annotates the bottom-menu buttons and HUD")
	_check(TutorialDetectors.poll({"kind": "in_mapmode", "mode": "logistics"}) == false,
		"tutorial: in_mapmode false when not in logistics")
	_check(TutorialDetectors.poll({"kind": "node_visible", "ref": "NoSuchNode_xyz"}) == false,
		"tutorial: node_visible false for a missing node")
	# The port is framed AND buildable now — the aluminium plant is built on the docks so its
	# hazard-liquid build material (industrial_acids) can land at the seeded reinf-pipe terminal.
	# Co-location: the port is framed but view-only again; the producers build on the factory tile.
	_check(TutorialSteps.PORT_TILE in TutorialSteps.CAMERA_TILES and not (TutorialSteps.PORT_TILE in TutorialSteps.BOARD_TILES),
		"tutorial: port tile is framed but not buildable (co-location moved producers off the docks)")
	_check(TutorialSteps.GLASS_TILE == TutorialSteps.WINDOW_TILE and TutorialSteps.ALU_TILE == TutorialSteps.WINDOW_TILE,
		"tutorial: glass + aluminium producers are co-located on the window factory tile")
	# Branching: the choice offers glass (margin) vs aluminium (overflow revenue).
	var choices: Array = (by_id.get("choose_integration", {}) as Dictionary).get("choices", [])
	_check(choices.size() == 2, "tutorial: choose_integration offers two branches")
	var gotos: Array = []
	for c in choices:
		gotos.append(str((c as Dictionary).get("goto", "")))
	_check("build_glass_open" in gotos and "build_alu_open" in gotos, "tutorial: choice gotos target the two build flows")
	# Glass branch now runs its own reinforced-pipe lesson (build furnace off-port -> diagnose the
	# expensive road delivery -> lay a cheaper reinf pipe -> run) before reconverging.
	_check(str((by_id.get("build_glass_confirm", {}) as Dictionary).get("goto", "")) == "",
		"tutorial: glass branch does not reconverge early (runs the pipe lesson)")
	var glass_inputs: Dictionary = by_id.get("glass_diagnose_pipe", {})
	var glass_inputs_decide: Dictionary = (glass_inputs.get("done", {}) as Dictionary).get("decide", {})
	_check(str(glass_inputs.get("title", "")) == "Inputs are on their way"
		and str(glass_inputs.get("body", "")).contains("The inputs are on their way from the port")
		and str((glass_inputs.get("spotlight", {}) as Dictionary).get("ref", "")) == "EndTurnButton"
		and str(glass_inputs_decide.get("kind", "")) == "turns_advanced"
		and int(glass_inputs_decide.get("count", 0)) == 2
		and str(glass_inputs.get("advance", "")) == "auto",
		"tutorial: Step 44 explains the red input state and waits two turns for port deliveries")
	# Glass branch now ends with a research sub-flow (unlock High Strength Glassmaking -> retool to r_054).
	_check(str((by_id.get("glass_run", {}) as Dictionary).get("goto", "")) == "",
		"tutorial: glass_run flows into the research steps (no early reconverge)")
	var glass_settle: Dictionary = by_id.get("glass_run", {})
	var glass_settle_decide: Dictionary = (glass_settle.get("done", {}) as Dictionary).get("decide", {})
	var glass_settle_actions: Array = glass_settle.get("setup", [])
	var glass_settle_action_names: Array = []
	for glass_settle_action in glass_settle_actions:
		glass_settle_action_names.append(str((glass_settle_action as Dictionary).get("action", "")))
	_check(bool(glass_settle.get("count_step", true))
		and str(glass_settle_decide.get("kind", "")) == "turns_advanced"
		and int(glass_settle_decide.get("count", 0)) == 3
		and "route_building_outputs_to_tile" in glass_settle_action_names,
		"tutorial: Step 46 locally routes glass and waits exactly three turns for profit to settle")
	var profit_step: Dictionary = by_id.get("glass_profit", {})
	var summary_before_profit_copy: Dictionary = Production.last_turn_summary.duplicate(true)
	Production.last_turn_summary = {"money_in": 73.5, "money_out": 28.25}
	var displayed_profit_step: Dictionary = Tutorial._display_step(profit_step)
	_check(not bool(profit_step.get("count_step", true))
		and str(profit_step.get("body_dynamic", "")) == "last_turn_profit"
		and str(profit_step.get("spotlight", {}).get("ref", "")) == "MoneyWidget"
		and str(displayed_profit_step.get("title", "")).contains("£45.25 profit")
		and str(displayed_profit_step.get("body", "")).contains("we can do better"),
		"tutorial: Step 46's result phase shows live settled profit without consuming Step 47")
	_check(bool((by_id.get("glass_research", {}) as Dictionary).get("count_step", true)),
		"tutorial: the High Strength Glassmaking research instruction is the counted Step 47")
	Production.last_turn_summary = summary_before_profit_copy
	# Reconverges at the ADVISORS chapter, not the finale: jumping straight to
	# integration_done skipped the whole advisor arc for anyone on the glass path.
	_check(str((by_id.get("glass_upgrade", {}) as Dictionary).get("goto", "")) == "advisors_intro",
		"tutorial: glass branch reconverges to the advisor arc after the recipe upgrade")
	var alu_research: Dictionary = by_id.get("alu_research", {})
	var alu_research_decide: Dictionary = (alu_research.get("done", {}) as Dictionary).get("decide", {})
	_check(float((by_id.get("transport_pentagon_revert", {}) as Dictionary).get("completion_delay", 0.0)) == 1.0,
		"tutorial: coastal arrival holds its animation for one second")
	var alu_review: Dictionary = by_id.get("alu_base_profit", {})
	_check(str(alu_review.get("advance", "")) == "next" and str(alu_review.get("body_dynamic", "")) == "last_turn_profit",
		"tutorial: aluminium shows settled profit and waits for acknowledgement before research")
	_check(not str((by_id.get("alu_research_condition", {}) as Dictionary).get("body", "")).contains("400 Aluminium"),
		"tutorial: aluminium research condition reflects the current chlorine gate")
	var alu_base_settle: Dictionary = by_id.get("alu_base_settle", {})
	var alu_base_settle_decide: Dictionary = (alu_base_settle.get("done", {}) as Dictionary).get("decide", {})
	var alu_search: Dictionary = by_id.get("alu_research_search", {})
	var alu_search_decide: Dictionary = (alu_search.get("done", {}) as Dictionary).get("decide", {})
	var alu_unlock: Dictionary = by_id.get("alu_research_unlock", {})
	var alu_unlock_decide: Dictionary = (alu_unlock.get("done", {}) as Dictionary).get("decide", {})
	var alu_upgrade: Dictionary = by_id.get("alu_upgrade", {})
	var alu_upgrade_decide: Dictionary = (alu_upgrade.get("done", {}) as Dictionary).get("decide", {})
	_check(str(alu_research_decide.get("kind", "")) == "node_visible"
		and str(alu_search_decide.get("kind", "")) == "research_visible"
		and bool(alu_search.get("no_dim", false))
		and str((alu_unlock.get("spotlight", {}) as Dictionary).get("kind", "")) == "research_unlock"
		and str(alu_unlock_decide.get("title", "")) == "Bauxite Carbochlorination"
		and str(((by_id.get("build_alu_recipe", {}) as Dictionary).get("spotlight", {}) as Dictionary).get("ref", "")) == "RecipeRow_r_050",
		"tutorial: aluminium branch searches and free-unlocks Carbochlorination after building the base smelter")
	_check(not bool(alu_base_settle.get("count_step", true))
		and str(alu_base_settle_decide.get("kind", "")) == "turns_advanced"
		and int(alu_base_settle_decide.get("count", 0)) == 3
		and str((alu_base_settle.get("spotlight", {}) as Dictionary).get("ref", "")) == "EndTurnButton",
		"tutorial: aluminium waits three full turns after local routing before the profit review")
	_check(str(alu_upgrade_decide.get("recipe_id", "")) == "r_232",
		"tutorial: aluminium branch waits until the existing smelter has finished retooling to Carbochlorination")
	var alu_pipe_intro: Dictionary = by_id.get("alu_diagnose_pipe", {})
	var alu_pipe_intro_decide: Dictionary = (alu_pipe_intro.get("done", {}) as Dictionary).get("decide", {})
	_check(str(alu_pipe_intro_decide.get("kind", "")) == "turns_advanced"
		and int(alu_pipe_intro_decide.get("count", 0)) == 2
		and str((alu_pipe_intro.get("spotlight", {}) as Dictionary).get("ref", "")) == "EndTurnButton"
		and not bool(alu_pipe_intro.get("lock_panel", false))
		and str(alu_pipe_intro.get("body", "")).contains("The retool is complete")
		and str(alu_pipe_intro.get("body", "")).contains("twice more"),
		"tutorial: Step 50 waits for the retool, then Step 51 requires two additional settling turns")
	var alu_settle: Dictionary = by_id.get("alu_final_run", {})
	var alu_settle_decide: Dictionary = (alu_settle.get("done", {}) as Dictionary).get("decide", {})
	var alu_profit: Dictionary = by_id.get("alu_profit", {})
	var alu_profit_targets: Array = alu_profit.get("targets", [])
	var alu_profit_setup: Array = alu_profit.get("setup", [])
	var alu_profit_actions: Array = []
	for alu_profit_action in alu_profit_setup:
		alu_profit_actions.append(str((alu_profit_action as Dictionary).get("action", "")))
	_check(not bool(alu_settle.get("count_step", true))
		and str(alu_settle_decide.get("kind", "")) == "turns_advanced"
		and int(alu_settle_decide.get("count", 0)) == 3,
		"tutorial: after Step 52 the aluminium recipe gets exactly three unnumbered settling turns")
	_check(str(alu_profit.get("body_dynamic", "")) == "last_turn_profit"
		and str(alu_profit.get("mode", "")) == "annotate"
		and not alu_profit_targets.is_empty()
		and str((alu_profit_targets[0] as Dictionary).get("ref", "")) == "FlyRowNet"
		and "open_money_panel" in alu_profit_actions,
		"tutorial: aluminium Step 53 opens the treasury and calls out live net profit")
	_check(str((advisor_inspect.get("spotlight", {}) as Dictionary).get("kind", "")) == "none",
		"tutorial: candidate comparison does not restrict clicks to Add new advisor")
	var gr_done: Dictionary = (by_id.get("glass_research", {}) as Dictionary).get("done", {})
	var gr_decide: Dictionary = gr_done.get("decide", {})
	_check(str(gr_decide.get("kind", "")) == "research_unlocked",
		"tutorial: glass_research gates on unlocking High Strength Glassmaking")
	_check(TutorialDetectors.poll({"kind": "research_unlocked", "title": "High Strength Glassmaking"}) == false,
		"tutorial: research_unlocked false before the node is unlocked")
	_check(TutorialDetectors.poll({"kind": "building_recipe_on_tile", "tile": TutorialSteps.GLASS_TILE, "recipe_id": "r_054"}) == false,
		"tutorial: building_recipe_on_tile false before the furnace is retooled")
	var glass_lay: Dictionary = by_id.get("glass_lay_pipe", {})
	# The whole CELL, not the bare "+" dial: the cell is the VBox holding the dial AND its
	# name label, so the highlight encloses the infrastructure's name too.
	_check(str((glass_lay.get("spotlight", {}) as Dictionary).get("ref", "")) == "InfraCell_reinf_pipes",
		"tutorial: glass_lay_pipe spotlights the reinforced-pipe cell (dial + name)")
	_check(TutorialDetectors.poll({"kind": "sell_surplus_on_tile", "tile": TutorialSteps.WINDOW_TILE}) == false,
		"tutorial: sell_surplus_on_tile false before enabling it")
	# Deeper-integration content (own power, survey/mine) authored + deferred.
	var integ_ids: Array = []
	for s in TutorialSteps._integration_steps():
		integ_ids.append(str((s as Dictionary).get("id", "")))
	_check("survey_stub" in integ_ids and "build_coal_mine" in integ_ids,
		"tutorial: deeper-integration survey/mine steps authored + deferred")
	_check("build_own_power" in integ_ids, "tutorial: own-power step deferred to deeper integration")

	# Buy Land lesson: tiles start unowned, the tutorial seeds only the factory plot,
	# and the buy_land step gates the furnace build on the COMPUTED land target
	# (footprints of everything the tutorial puts on the tile, in whole patches).
	for expected2 in ["buy_land", "transport_redirect_open", "transport_redirect_pick", "transport_pentagon_revert"]:
		_check(expected2 in ids, "tutorial: step '%s' present" % expected2)
	_check(ids.find("buy_land") < ids.find("choose_integration"),
		"tutorial: buy_land runs before the integration branch (both builds need the land)")
	var land_target: int = TutorialSteps._land_lesson_target()
	var bl_decide: Dictionary = ((by_id.get("buy_land", {}) as Dictionary).get("done", {}) as Dictionary).get("decide", {})
	_check(str(bl_decide.get("kind", "")) == "tile_land_at_least" and int(bl_decide.get("amount", 0)) == land_target,
		"tutorial: buy_land gates on the computed land target (%d)" % land_target)
	_check(land_target % BuildingState.LAND_PATCH_SIZE == 0 and land_target > 0,
		"tutorial: land target is a whole number of patches")
	# The seeded plot must cover pricing up the factory (step 5) but NOT the furnace:
	# the wall has to appear exactly at the buy_land step.
	var seed_land: int = TutorialSteps.TUTORIAL_SEED_LAND
	var start_cfg: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/starts/tutorial.json"))
	_check(start_cfg is Dictionary and int(((start_cfg as Dictionary).get("land", {}) as Dictionary).get(TutorialSteps.WINDOW_TILE, -1)) == seed_land,
		"tutorial: TUTORIAL_SEED_LAND matches the start config's factory-tile seed")
	_check(start_cfg is Dictionary and int((start_cfg as Dictionary).get("money", 0)) == 99999,
		"tutorial: player starts the Capital lesson with £99,999")
	var capital_stock: Dictionary = (((start_cfg as Dictionary).get("stockpile", {}) as Dictionary).get(TutorialSteps.MOTOR_TILE, {}) as Dictionary)
	_check(int(capital_stock.get("g_006", 0)) == 160 and int(capital_stock.get("g_007", 0)) == 160,
		"tutorial: motor factory starts with exactly five batches of steel and copper wiring")
	var fp_factory := int(round(float(Catalog.get_building("b_007").get("tile_size_used", 1.0))))
	var fp_cable := int(round(float(Catalog.get_building("b_006").get("tile_size_used", 1.0))))
	var fp_furnace := int(round(float(Catalog.get_building("b_002").get("tile_size_used", 1.0))))
	_check(fp_factory <= seed_land, "tutorial: the seeded plot covers pricing up the factory (step 5)")
	_check(fp_factory + fp_cable + fp_furnace > seed_land + fp_factory,
		"tutorial: the furnace does NOT fit before buy_land (the lesson's wall exists)")
	var land_saved: Dictionary = BuildingState.tile_land_owned.duplicate(true)
	BuildingState.tile_land_owned.clear()
	_check(TutorialDetectors.poll({"kind": "tile_land_at_least", "tile": TutorialSteps.WINDOW_TILE, "amount": land_target}) == false,
		"tutorial: tile_land_at_least false with no land owned")
	BuildingState.tile_land_owned[TutorialSteps.WINDOW_TILE] = land_target
	_check(TutorialDetectors.poll({"kind": "tile_land_at_least", "tile": TutorialSteps.WINDOW_TILE, "amount": land_target}) == true,
		"tutorial: tile_land_at_least true at exactly the target amount")
	BuildingState.tile_land_owned = land_saved
	# The helper behind construction-cost references must agree with the Build panel's
	# own formula even though Step 15 now explains the cost without quoting a live figure.
	var kit_cost: int = TutorialSteps._build_confirm_cost("b_007")
	var panel_cost := int(round(
		maxf(0.0, float(Catalog.get_building("b_007").get("base_price", 0.0)))
		+ Construction.market_purchase_value("b_007")))
	_check(kit_cost == panel_cost,
		"tutorial: build_cost matches the Build confirm panel figure (£%d vs £%d)" % [kit_cost, panel_cost])
	_check(kit_cost > 0, "tutorial: live factory build cost remains available to tutorial references")
	_check(str((by_id.get("margin_motivation", {}) as Dictionary).get("body", "")).contains("The solution is vertical integration."),
		"tutorial: margin lesson explains integration without a precise price claim")
	var glass_qty: int = TutorialSteps._recipe_input_qty("r_056", "glass")
	_check(glass_qty > 0 and str((by_id.get("choose_integration", {}) as Dictionary).get("body", "")).begins_with("Your choice. GLASS or ALUMINIUM."),
		"tutorial: integration choice presents both specialisations")
	var alu_out: int = TutorialSteps._recipe_output_qty("r_232")
	_check(alu_out > 0 and str((by_id.get("build_alu_open", {}) as Dictionary).get("body", "")).contains("%d aluminium" % alu_out),
		"tutorial: build_alu_open quotes the live smelter output (%d)" % alu_out)
	var direct_bauxite: Dictionary = Catalog.get_recipe("r_232")
	var direct_inputs: Array = direct_bauxite.get("inputs", [])
	var direct_needs_chlorine := false
	for direct_input in direct_inputs:
		if str((direct_input as Dictionary).get("internal_name", "")) == "chlorine":
			direct_needs_chlorine = true
			break
	_check(str(direct_bauxite.get("building_id", "")) == "b_002"
		and int(direct_bauxite.get("energy_req", 0)) < int(Catalog.get_recipe("r_050").get("energy_req", 0))
		and direct_needs_chlorine
		and TutorialSteps._recipe_input_qty("r_232", "chlorine") == 20
		and str(direct_bauxite.get("tech_unlock_req", "")) == "research_metal_012",
		"tutorial: Bauxite Carbochlorination is the lower-energy gated furnace route with chlorine")
	var carbo_unlock: Dictionary = ResearchState.get_unlock_def("Bauxite Carbochlorination")
	# Chlorine is the real reagent dependency; the old "and 400 aluminium" was circular
	# (make aluminium to unlock an aluminium recipe) and was dropped (owner 2026-09-06).
	_check(str(carbo_unlock.get("action", "")) == "Produce"
		and str(carbo_unlock.get("object", "")) == "chlorine"
		and int(carbo_unlock.get("qty", 0)) == 300,
		"research: Bauxite Carbochlorination requires 300 Chlorine (chlorine is the reagent; no circular aluminium gate)")
	# Reward text names the recipe only — output quantities were dropped from every card
	# (owner 2026-09-06) because they went stale against recipes_all.csv.
	_check(str(carbo_unlock.get("description", "")) == "Unlocks new recipe: Bauxite Carbochlorination.",
		"research: Bauxite Carbochlorination description describes its recipe, not its condition")
	_check(TutorialSteps._recipe_input_qty("r_050", "alumina") == 20
		and int(Catalog.get_recipe("r_050").get("labour_unskilled_required", 0)) == 505
		and int(Catalog.get_recipe("r_050").get("labour_skilled_required", 0)) == 189
		and int(Catalog.get_recipe("r_050").get("labour_h_skilled_required", 0)) == 30,
		"tutorial: Hall-Heroult's extra alumina is offset by its labour requirement")
	var alu_lay: Dictionary = by_id.get("alu_lay_pipe", {})
	_check(str((alu_lay.get("spotlight", {}) as Dictionary).get("ref", "")) == "InfraCell_reinf_pipes",
		"tutorial: alu_lay_pipe spotlights the reinforced-pipe cell")
	var settle_done: Dictionary = ((by_id.get("revenue_settle", {}) as Dictionary).get("done", {}) as Dictionary)
	var settle_decide: Dictionary = settle_done.get("decide", {})
	_check(str(settle_decide.get("kind", "")) == "filtered_market_sale_since_entry" and str(settle_decide.get("good", "")) == "windows" and str(settle_decide.get("tile", "")) == TutorialSteps.WINDOW_TILE,
		"tutorial: money lesson waits for a shipment to reach market, not a hard-coded turn")
	_check(bool((by_id.get("revenue_settle", {}) as Dictionary).get("no_dim", false)),
		"tutorial: shipment wait keeps the map unobstructed")
	var loan_step: Dictionary = by_id.get("money_take_loan", {})
	_check(str((loan_step.get("spotlight", {}) as Dictionary).get("kind", "")) == "none",
		"tutorial: loan confirmation remains interactive after opening the Loans tab")
	_check(not bool((by_id.get("money_primer", {}) as Dictionary).get("lock_panel", false)),
		"tutorial: money primer does not rebuild the flyout beneath its Next click")
	_check(not bool((by_id.get("money_loan_terms", {}) as Dictionary).get("lock_panel", false)),
		"tutorial: loan terms does not rebuild the flyout beneath its Next click")
	var loan_terms_step: Dictionary = by_id.get("money_loan_terms", {})
	_check(str(loan_terms_step.get("title", "")) == "The terms of the loan"
		and str(loan_terms_step.get("body", "")).begins_with("Nothing is due"),
		"tutorial: Step 35 introduces the loan terms without the redundant Borrowed lead-in")

	var previous_loans := LoanState.loans.duplicate(true)
	var loan_decide: Dictionary = by_id["money_take_loan"]["done"]["decide"]
	LoanState.loans = [{"principal_initial": 200.0}]
	_check(not TutorialDetectors.poll(loan_decide), "tutorial: a loan of exactly 200 does not satisfy over 200")
	LoanState.loans = [{"principal_initial": 200.5}]
	_check(TutorialDetectors.poll(loan_decide), "tutorial: any loan above 200 satisfies the expansion lesson")
	LoanState.loans = previous_loans
	# Transport arc: output-route detectors read the explicit per-good destinations.
	var saved2: Dictionary = BuildingState.buildings
	var saved_routes: Dictionary = MatchState.output_stockpile_destinations.duplicate(true)
	BuildingState.buildings = {
		"inst_route": {
			"instance_id": "inst_route", "building_id": "b_007",
			"recipe_id": "r_056", "tile_id": TutorialSteps.WINDOW_TILE, "owner": MatchState.LOCAL_PLAYER,
		}
	}
	MatchState.output_stockpile_destinations.clear()
	_check(TutorialDetectors.poll({"kind": "output_routed_offtile", "tile": TutorialSteps.WINDOW_TILE, "building_id": "b_007"}) == false,
		"tutorial: output_routed_offtile false with no explicit route")
	_check(TutorialDetectors.poll({"kind": "output_routed_market", "tile": TutorialSteps.WINDOW_TILE, "building_id": "b_007"}) == false,
		"tutorial: output_routed_market false with no explicit route (sell_mode fallback is not a route)")
	MatchState.output_stockpile_destinations["inst_route"] = {"g_test": TutorialSteps.INPUT_TILE}
	_check(TutorialDetectors.poll({"kind": "output_routed_offtile", "tile": TutorialSteps.WINDOW_TILE, "building_id": "b_007"}) == true,
		"tutorial: output_routed_offtile true once routed to another tile")
	_check(TutorialDetectors.poll({"kind": "output_routed_to_tile", "tile": TutorialSteps.WINDOW_TILE,
		"building_id": "b_007", "destination": TutorialSteps.WINDOW_REDIRECT_TILE}) == false,
		"tutorial: Step 24 does not accept an arbitrary off-tile route")
	MatchState.output_stockpile_destinations["inst_route"] = {"g_test": TutorialSteps.WINDOW_REDIRECT_TILE}
	_check(TutorialDetectors.poll({"kind": "output_routed_to_tile", "tile": TutorialSteps.WINDOW_TILE,
		"building_id": "b_007", "destination": TutorialSteps.WINDOW_REDIRECT_TILE}) == true,
		"tutorial: Step 24 accepts the exact eastern coastal destination")
	MatchState.output_stockpile_destinations["inst_route"] = {"g_test": TutorialSteps.WINDOW_TILE}
	_check(TutorialDetectors.poll({"kind": "output_routed_offtile", "tile": TutorialSteps.WINDOW_TILE, "building_id": "b_007"}) == false,
		"tutorial: output_routed_offtile false for a same-tile stockpile route")
	MatchState.output_stockpile_destinations.clear()
	Tutorial._route_building_outputs_to_market(TutorialSteps.WINDOW_TILE, "b_007")
	_check(TutorialDetectors.poll({"kind": "output_routed_market", "tile": TutorialSteps.WINDOW_TILE, "building_id": "b_007"}) == true,
		"tutorial: Step 26 automatically routes the window output back to market")
	Tutorial._route_building_outputs_to_tile(TutorialSteps.WINDOW_TILE, "b_007", TutorialSteps.WINDOW_TILE)
	_check(TutorialDetectors.poll({"kind": "output_routed_same_tile", "tile": TutorialSteps.WINDOW_TILE,
		"building_id": "b_007"}) == true,
		"tutorial: the Step 45 handoff routes recipe output into the local tile stockpile")
	var redirect_stock_saved: Dictionary = Stockpile.export_state()
	var windows_good_id := str(Catalog.get_good_by_internal_name("windows").get("id", ""))
	Stockpile.consume(TutorialSteps.WINDOW_REDIRECT_TILE, windows_good_id,
		Stockpile.get_at_tile(TutorialSteps.WINDOW_REDIRECT_TILE, windows_good_id))
	var arrival_decide := {"kind": "stockpile_good_at_least", "tile": TutorialSteps.WINDOW_REDIRECT_TILE,
		"good": "windows", "amount": 1}
	_check(not TutorialDetectors.poll(arrival_decide),
		"tutorial: Step 25 waits while no windows have reached the target stockpile")
	Stockpile.add(TutorialSteps.WINDOW_REDIRECT_TILE, windows_good_id, 1)
	_check(TutorialDetectors.poll(arrival_decide),
		"tutorial: Step 25 advances as soon as windows arrive at the target stockpile")
	Stockpile.import_state(redirect_stock_saved)
	MatchState.output_stockpile_destinations = saved_routes
	BuildingState.buildings = saved2

	# Ordinary Skip only dismisses the coach. The terminal action alone changes the
	# match into a normal campaign, establishes the £200 balance and clears tutorial score.
	var completion_rules_saved: Dictionary = MatchState.ruleset.duplicate(true)
	var completion_money_saved: float = MatchState.money
	var completion_fake_saved: float = MatchState.fake_money_this_turn
	var completion_victory_saved: Dictionary = VictoryState.export_state()
	var completion_steps_saved: Array = Tutorial._steps
	var completion_index_saved: int = Tutorial._index
	var completion_active_saved: bool = Tutorial.active
	MatchState.ruleset = {"name": "tutorial", "tutorial_enabled": true}
	MatchState.money = 99999.0
	Tutorial._on_overlay_skipped()
	_check(bool(MatchState.ruleset.get("tutorial_enabled", false)) and is_equal_approx(MatchState.money, 99999.0),
		"tutorial: an early Skip leaves tutorial rules and cash untouched")
	VictoryState.track_best["richest"] = 1.0
	MatchState.fake_money_this_turn = 123.0
	Tutorial._steps = [terminal_step]
	Tutorial._index = 0
	Tutorial.active = true
	Tutorial._on_overlay_advanced()
	_check(not bool(MatchState.ruleset.get("tutorial_enabled", true))
		and is_equal_approx(MatchState.money, 200.0)
		and is_equal_approx(MatchState.fake_money_this_turn, 0.0)
		and VictoryState.total_for_turn() == 0,
		"tutorial: End tutorial alone enables victory, resets cash to £200 and clears tutorial score")
	MatchState.ruleset = completion_rules_saved
	MatchState.money = completion_money_saved
	MatchState.fake_money_this_turn = completion_fake_saved
	VictoryState.import_state(completion_victory_saved)
	Tutorial._steps = completion_steps_saved
	Tutorial._index = completion_index_saved
	Tutorial.active = completion_active_saved
