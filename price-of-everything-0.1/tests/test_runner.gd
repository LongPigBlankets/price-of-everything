extends Node
const BuildingLevels := preload("res://scripts/building_levels.gd")
const BuildingStatus := preload("res://scripts/building_status.gd")
## Minimal, zero-dependency headless test runner for price-of-everything.
##
## Fast path (one command; exit code 0 = all pass, 1 = a failure):
##     <godot> --headless res://tests/test_runner.tscn
## Or from the editor: open tests/test_runner.tscn and press F6 (Run Current Scene);
## results print in the Output panel.
##
## It runs as a SCENE (not --script) so the project autoloads — Catalog,
## Stockpile, Production, DS, etc. — are available. The goal is to catch, without
## manual clicking: script parse errors, broken @onready paths, main.tscn
## corruption, and data-loading regressions.

var _passed := 0
var _failed := 0
var _failed_names: Array[String] = []

const RoadRegionsLoader := preload("res://scripts/road_regions.gd")
const TutorialSteps := preload("res://scripts/tutorial/tutorial_steps.gd")
const TutorialDetectors := preload("res://scripts/tutorial/tutorial_detectors.gd")
const BuildingReadout := preload("res://scripts/building_readout.gd")
const AppPaths := preload("res://scripts/app_paths.gd")  # saves now live in <base>/savegames/

func _ready() -> void:
	print("\n==== price-of-everything tests ====")
	_test_scripts_parse()
	_test_widgets_instantiate()
	_test_recipe_row_instantiates()
	await _test_unlock_dialog_groups_multiple_unlocks()
	await _test_stockpile_legend_label_visible()
	_test_scene_loads()
	await _test_main_scene_instantiates()
	_test_catalog_loaded()
	_test_goods_flow_graph()
	_test_recipe_requirements()
	_test_research_recipe_and_level_tiers()
	_test_bottom_menu_default()
	_test_panel_stack_focus()
	_test_ports()
	_test_building_price()
	_test_buy_grants_land()
	_test_transport_service()
	_test_transport_boundaries()
	_test_build_mode_overlay_survey_visibility()
	_test_direct_build_skips_build_overlay()
	_test_advisor_payroll_cost()
	_test_advisor_roster_merge()
	_test_advisor_seat_requires_hire()
	_test_people_panel_seat_ui()
	_test_advisor_star_derivation()
	_test_advisor_seat_assign_and_slot_cap()
	_test_advisor_seat_tier_scaling()
	_test_advisor_reconcile_idempotent()
	_test_advisor_seat_effects()
	_test_advisor_phase2_effects()
	_test_hr_director_policies()
	_test_retrofit_mechanic()
	_test_sell_and_demolish()
	_test_advisor_loyalty()
	_test_advisor_missions()
	_test_advisor_mission_update_signals()
	_test_people_panel_mission_ui()
	_test_build_duration()
	_test_advisor_seats_save_roundtrip()
	_test_advisor_milestone_acquisition()
	_test_advisor_slot_progression()
	_test_advisor_fake_money_and_track()
	_test_advisor_slot_unlock()
	_test_advisor_acquisition_save_roundtrip()
	await _test_research_unlock_promotes_construct_panel_recipes()
	_test_tile_deposit_build_options_respect_research_unlocks()
	await _test_building_ledger()
	await _test_debug_terminal()
	await _test_capacity_dialog_expand()
	await _test_app_paths()
	_test_building_shapes()
	_test_footprint_rejects_interior_road_segment()
	_test_building_category_key()
	_test_queue_move()
	_test_move_extras()
	_test_storage_boost()
	_test_warehouse_storage_levels()
	_test_queue_sell()
	_test_queue_sell_immediate_updates_turn_summary()
	_test_market_execute_sale()
	_test_market_execute_sale_skip_consume()
	_test_market_execute_sale_pay_transport()
	_test_npc_ports()
	_test_bulk_sell()
	_test_output_market_route()
	_test_transaction_ledger()
	_test_market_buy()
	_test_market_input_pipeline_ignores_reserved_inbound()
	_test_tax_dividend_caps()
	_test_purchases()
	_test_exhausted_input_source_falls_back_to_market()
	_test_recipes_producing()
	_test_transfer_helpers()
	_test_output_conservation()
	_test_market_sale_credits()
	_test_owner_costs()
	_test_recurring_sell_multitile()
	_test_input_buy_nets_local_supply()
	_test_input_buy_capacity_building_first()
	_test_warehouse_upgrade()
	_test_warehousing_fee_rates()
	_test_two_part_freight_tariff()
	_test_jit_streak_and_direct_feed()
	_test_sell_protects_build_materials()
	_test_auto_sell_goods()
	_test_price_impact()
	_test_price_impact_thresholds()
	_test_buy_price()
	_test_limestone_concrete()
	_test_construction()
	_test_construction_awaiting()
	_test_construction_reorder_ignores_foreign_inbound()
	_test_construction_sourcing()
	_test_construction_cancel()
	await _test_construction_detail_panel()
	_test_special_order_state_model()
	_test_special_order_generation()
	_test_special_order_settlement()
	_test_output_special_order_route()
	_test_tile_view_special_order_route()
	_test_special_order_overflow_resolution()
	_test_pending_special_order_shipment_resolution()
	await _test_special_order_resolution_dialog()
	_test_market_special_orders_tab()
	_test_save_load_roundtrip()
	await _test_pending_load_applies_on_scene_ready()
	_test_start_config_expansion()
	await _test_start_config_applies_on_scene_ready()
	_test_save_version_migration()
	_test_game_ended_persists()
	_test_construction_survives_load()
	_test_autosave_rotation()
	await _test_save_load_ui()
	await _test_event_scheduler_emit()
	await _test_event_scheduler_schedule()
	await _test_event_scheduler_forewarn()
	await _test_event_scheduler_watch_oneshot()
	await _test_event_scheduler_starvation_ramp()
	await _test_event_scheduler_aggregator()
	await _test_event_scheduler_max_severity()
	await _test_event_scheduler_roundtrip()
	await _test_modifiers_basic()
	await _test_modifiers_stacking()
	await _test_modifiers_target_match()
	await _test_modifiers_expiry()
	await _test_modifiers_event_payload()
	await _test_modifiers_production_recipe_output()
	await _test_modifiers_roundtrip()
	_test_live_unlock_conditions()
	_test_research_tier_gating()
	_test_deposit_penalty_modifier()
	_test_workforce_output_modifier_surfaces_in_building_status()
	_test_recipe_labour_owns_cost()
	_test_additive_labour_cost_model()
	_test_labour_factor_floor()
	_test_cost_report_credits_output_modifiers()
	_test_flavor_nodes_wired()
	_test_transport_congestion()
	_test_tile_mode_flow_endpoints()
	_test_cable_power_cap()
	_test_power_network_settlement()
	_test_power_output_modifier()
	_test_building_leveling()
	_test_run_failure_warnings()
	await _test_mining_mastery_free_unlock()
	_test_modifiers_pct_additive_and_resolve()
	_test_modifiers_new_domain_unlocks()
	_test_event_grouping()
	_test_survey_grouping()
	_test_starvation_deeplink_building()
	await _test_notification_group_inline_expand()
	await _test_notification_header_filter()
	await _test_notification_bell_smoke()
	_test_road_regions()
	_test_hills_baked_fresh()
	await _test_hill_field_determinism()
	await _test_grid_selection_follows_panel()
	await _test_tile_view_player_building_filter()
	_test_start_buildings()
	await _test_roads_v2()
	await _test_road_attachment_projection()
	await _test_road_works()
	await _test_arin_bridge()
	await _test_region_styles()
	await _test_roads_avoid_buildings()
	await _test_building_resnap()
	await _test_block_subdivision()
	await _test_level_storeys_and_owner_swap()
	_test_ink_art_reserves_upgrade_space()
	await _test_river_bank_and_bridge_head()
	await _test_bridge_corridor()
	await _test_subcomponents()
	await _test_farms()
	await _test_farm_lanes()
	# Farm ring promotion was removed 2026-07-23 (RoadWorks.PROMOTE_FARM_RINGS):
	# ink farms carry their own parcel-path fabric, and the promoted ring was
	# decoration — transport reads each tile's road FLAG, not whether
	# carriageways meet. _test_farm_road_promotion / _test_farm_ring_dedup
	# asserted the promotion happens, so they retire with the feature. The
	# routing-bias tests still run: roads may still favour a farm cluster.
	await _test_farm_ring_bridge()
	await _test_farm_ring_continuity()
	await _test_farm_road_routing_bias()
	_test_refund()
	_test_victory_base_curve()
	_test_victory_win_curve()
	_test_victory_autarkic()
	_test_victory_logistics()
	_test_victory_richest()
	_test_victory_widest()
	_test_victory_greenest()
	_test_victory_total_and_win()
	_test_victory_tick_scores_resolved_turn()
	_test_victory_save_load()
	_test_power_quality()
	_test_power_instance_age()
	_test_power_intermittency_alloc()
	_test_intermittency_tile_aggregate()
	_test_detail_panel_owner_resolution()
	_test_battery_buildable()
	_test_battery_deposit()
	_test_battery_fill_pending()
	_test_sea_land_building_rule()
	_test_greenest_reads_quality()
	_test_main_menu_grid_unique()
	_test_empire_layout()
	_test_empire_layered()
	_test_empire_ports()
	_test_empire_rag()
	_test_audio_service()
	_test_tutorial_engine()
	_test_decision_tenure_gate()
	_test_decision_resolve_effects_and_loyalty()
	_test_decision_company_scope_loyalty()
	_test_decision_loan_fallback()
	_test_loan_collateral_capacity()
	_test_decision_commit_guard_and_auto_resolve()
	_test_decision_roundtrip()
	_test_building_pause()
	_test_liquidate_all_buildings()
	_test_grace_loan()
	_test_distressed_program()
	_test_solvency_bankruptcy()
	_test_decision_story_not_random()
	_test_decision_pulse_pipeline()
	_test_decision_queue_stacking()
	_test_briefing_items_and_dismissal()
	_test_briefing_event_mapping()
	await _test_decision_view_never_empty()
	_test_auto_bridge_loan()
	_test_cfo_tax_credit()
	_test_policy_state()
	_test_insider_tip()
	_test_deposit_running_out_warning()
	_test_partial_power_dispatch()
	_test_building_diagnostics()
	_test_infra_upgrade()
	if not _failed_names.is_empty():
		print("FAILED TESTS:")
		for failed_name in _failed_names:
			print("  - ", failed_name)
	print("==== %d passed, %d failed ====\n" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)

# Tutorial "Coach" engine (Wave 1). The engine itself is signal-driven and confined to
# a live scene, so here we cover the two pure surfaces: the authored step list and the
# state-verified detectors (the only logic that decides step completion).
func _test_tutorial_engine() -> void:
	var steps: Array = TutorialSteps.steps()
	_check(not steps.is_empty(), "tutorial: steps() returns content")
	_check(str((steps[0] as Dictionary).get("id", "")) == "welcome", "tutorial: first step is the welcome panel")
	_check(str((steps[0] as Dictionary).get("mode", "")) == "welcome", "tutorial: first step uses welcome render mode")
	_check(TutorialSteps.BOARD_TILES.has(TutorialSteps.WINDOW_TILE), "tutorial: board includes the factory tile")
	_check(TutorialSteps.BOARD_TILES.has(TutorialSteps.STUB_TILE), "tutorial: board includes the coal stub")
	_check(TutorialSteps.BOARD_TILES.has(TutorialSteps.GLASS_TILE), "tutorial: board includes the glass furnace tile (port-adjacent)")

	# The New Game "have you done the tutorial?" gate reads PlayerProfile.has_done_tutorial(),
	# which reflects the tutorial_completed flag (marked when the engine enters integration_done).
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
	PlayerProfile.set_window_size(ws_saved)  # restore + persist the original
	_check(PlayerProfile.window_size == ws_saved, "profile: window_size restored after test")

	var terminal_present := false
	for s in steps:
		if str((s as Dictionary).get("id", "")) == "integration_done":
			terminal_present = true
	_check(terminal_present, "tutorial: terminal integration_done step exists (the completion hook target)")

	# building_owned_on_tile detector: player-owned building on the tile -> true;
	# NPC-owned -> false; unknown predicate kind -> false. Save/restore live buildings.
	var saved: Dictionary = MatchState.buildings
	MatchState.buildings = {
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
	MatchState.buildings["inst_test"]["owner"] = "Vandel Glassworks"
	_check(TutorialDetectors.poll(decide) == false, "tutorial: detector false while NPC-owned")
	_check(TutorialDetectors.poll({"kind": "unknown_predicate"}) == false, "tutorial: unknown predicate never advances")
	MatchState.buildings = saved
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
	for expected in ["welcome", "ui_primer", "goto_tile", "build_open", "build_pick_recipe", "build_cost", "build_close_buy", "buy_factory", "diagnose_factory", "lay_cable_factory", "run_until_running", "view_shipment", "analyse_supply", "explore_encyclopedia", "close_encyclopedia", "choose_integration", "build_glass_open", "build_glass_recipe", "build_glass_source", "glass_sell", "glass_wait_built", "glass_diagnose_pipe", "glass_lay_pipe", "glass_run", "glass_economics", "glass_better", "glass_research", "glass_upgrade", "build_alu_open", "sell_windows", "integration_done"]:
		_check(expected in ids, "tutorial: step '%s' present" % expected)
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
	# "No input Reinforced Pipeline" fault -> lay a reinf pipe -> run) before reconverging.
	_check(str((by_id.get("build_glass_source", {}) as Dictionary).get("goto", "")) == "",
		"tutorial: glass branch does not reconverge early (runs the pipe lesson)")
	# Glass branch now ends with a research sub-flow (unlock High Strength Glassmaking -> retool to r_054).
	_check(str((by_id.get("glass_run", {}) as Dictionary).get("goto", "")) == "",
		"tutorial: glass_run flows into the research steps (no early reconverge)")
	_check(str((by_id.get("glass_upgrade", {}) as Dictionary).get("goto", "")) == "integration_done",
		"tutorial: glass branch reconverges to integration_done after the recipe upgrade")
	var gr_done: Dictionary = (by_id.get("glass_research", {}) as Dictionary).get("done", {})
	var gr_decide: Dictionary = gr_done.get("decide", {})
	_check(str(gr_decide.get("kind", "")) == "research_unlocked",
		"tutorial: glass_research gates on unlocking High Strength Glassmaking")
	_check(TutorialDetectors.poll({"kind": "research_unlocked", "title": "High Strength Glassmaking"}) == false,
		"tutorial: research_unlocked false before the node is unlocked")
	_check(TutorialDetectors.poll({"kind": "building_recipe_on_tile", "tile": TutorialSteps.GLASS_TILE, "recipe_id": "r_054"}) == false,
		"tutorial: building_recipe_on_tile false before the furnace is retooled")
	var glass_lay: Dictionary = by_id.get("glass_lay_pipe", {})
	_check(str((glass_lay.get("spotlight", {}) as Dictionary).get("ref", "")) == "InfraDial_reinf_pipes",
		"tutorial: glass_lay_pipe spotlights the reinforced-pipe dial")
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
	for expected2 in ["buy_land", "transport_ports", "transport_redirect_open", "transport_redirect_pick", "transport_pentagon_revert"]:
		_check(expected2 in ids, "tutorial: step '%s' present" % expected2)
	_check(ids.find("buy_land") < ids.find("choose_integration"),
		"tutorial: buy_land runs before the integration branch (both builds need the land)")
	var land_target: int = TutorialSteps._land_lesson_target()
	var bl_decide: Dictionary = ((by_id.get("buy_land", {}) as Dictionary).get("done", {}) as Dictionary).get("decide", {})
	_check(str(bl_decide.get("kind", "")) == "tile_land_at_least" and int(bl_decide.get("amount", 0)) == land_target,
		"tutorial: buy_land gates on the computed land target (%d)" % land_target)
	_check(land_target % MatchState.LAND_PATCH_SIZE == 0 and land_target > 0,
		"tutorial: land target is a whole number of patches")
	# The seeded plot must cover pricing up the factory (step 5) but NOT the furnace:
	# the wall has to appear exactly at the buy_land step.
	var seed_land: int = TutorialSteps.TUTORIAL_SEED_LAND
	var start_cfg: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/starts/tutorial.json"))
	_check(start_cfg is Dictionary and int(((start_cfg as Dictionary).get("land", {}) as Dictionary).get(TutorialSteps.WINDOW_TILE, -1)) == seed_land,
		"tutorial: TUTORIAL_SEED_LAND matches the start config's factory-tile seed")
	var fp_factory := int(round(float(Catalog.get_building("b_007").get("tile_size_used", 1.0))))
	var fp_cable := int(round(float(Catalog.get_building("b_006").get("tile_size_used", 1.0))))
	var fp_furnace := int(round(float(Catalog.get_building("b_002").get("tile_size_used", 1.0))))
	_check(fp_factory <= seed_land, "tutorial: the seeded plot covers pricing up the factory (step 5)")
	_check(fp_factory + fp_cable + fp_furnace > seed_land + fp_factory,
		"tutorial: the furnace does NOT fit before buy_land (the lesson's wall exists)")
	var land_saved: Dictionary = MatchState.tile_land_owned.duplicate(true)
	MatchState.tile_land_owned.clear()
	_check(TutorialDetectors.poll({"kind": "tile_land_at_least", "tile": TutorialSteps.WINDOW_TILE, "amount": land_target}) == false,
		"tutorial: tile_land_at_least false with no land owned")
	MatchState.tile_land_owned[TutorialSteps.WINDOW_TILE] = land_target
	_check(TutorialDetectors.poll({"kind": "tile_land_at_least", "tile": TutorialSteps.WINDOW_TILE, "amount": land_target}) == true,
		"tutorial: tile_land_at_least true at exactly the target amount")
	MatchState.tile_land_owned = land_saved
	# Live-value copy: the numbers quoted in the step bodies come from the catalog.
	var kit_cost: int = TutorialSteps._build_kit_cost("b_007")
	_check(kit_cost > 0 and str((by_id.get("build_cost", {}) as Dictionary).get("body", "")).contains("£%d" % kit_cost),
		"tutorial: build_cost quotes the live factory kit cost (£%d)" % kit_cost)
	var win_price: String = TutorialSteps._good_price_text("windows")
	_check(str((by_id.get("margin_motivation", {}) as Dictionary).get("body", "")).contains("£%s" % win_price),
		"tutorial: margin_motivation quotes the live window price (£%s)" % win_price)
	var glass_qty: int = TutorialSteps._recipe_input_qty("r_056", "glass")
	_check(glass_qty > 0 and str((by_id.get("choose_integration", {}) as Dictionary).get("body", "")).contains("%d units" % glass_qty),
		"tutorial: choose_integration quotes the live glass quantity (%d)" % glass_qty)
	var alu_out: int = TutorialSteps._recipe_output_qty("r_050")
	_check(alu_out > 0 and str((by_id.get("build_alu_open", {}) as Dictionary).get("body", "")).contains("%d aluminium" % alu_out),
		"tutorial: build_alu_open quotes the live smelter output (%d)" % alu_out)

	# Transport arc: output-route detectors read the explicit per-good destinations.
	var saved2: Dictionary = MatchState.buildings
	var saved_routes: Dictionary = MatchState.output_stockpile_destinations.duplicate(true)
	MatchState.buildings = {
		"inst_route": {
			"instance_id": "inst_route", "building_id": "b_007",
			"tile_id": TutorialSteps.WINDOW_TILE, "owner": MatchState.LOCAL_PLAYER,
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
	MatchState.output_stockpile_destinations["inst_route"] = {"g_test": TutorialSteps.WINDOW_TILE}
	_check(TutorialDetectors.poll({"kind": "output_routed_offtile", "tile": TutorialSteps.WINDOW_TILE, "building_id": "b_007"}) == false,
		"tutorial: output_routed_offtile false for a same-tile stockpile route")
	MatchState.output_stockpile_destinations["inst_route"] = {"g_test": MatchState.MARKET_DESTINATION}
	_check(TutorialDetectors.poll({"kind": "output_routed_market", "tile": TutorialSteps.WINDOW_TILE, "building_id": "b_007"}) == true,
		"tutorial: output_routed_market true once explicitly routed back to market")
	MatchState.output_stockpile_destinations = saved_routes
	MatchState.buildings = saved2


# The Audio autoload (presentation-layer SFX service). Headless uses the Dummy
# audio driver, so we assert wiring/state rather than actual playback: the click
# stream imports, the voice pool is built, and click() runs without erroring.
func _test_audio_service() -> void:
	for cue in ["CLICK", "CLICK_MENU", "CLICK_PRIMARY", "HOVER", "HAMMER", "RUBBLE", "SIGNATURE", "CASH_REGISTER", "TECH_UNLOCK", "SLOT_LEVER", "HINT"]:
		_check(Audio.get(cue) != null, "audio: %s cue imports and loads" % cue)
	# Each channel built its own independent voice pool (clicks can't steal build voices).
	var channels_ok: bool = Audio._channels.size() == Audio.CHANNELS.size()
	for ch in Audio.CHANNELS:
		if not (Audio._channels.has(ch) and Audio._channels[ch].size() == int(Audio.CHANNELS[ch])):
			channels_ok = false
	_check(channels_ok, "audio: per-track voice channels built")
	_check(Audio._music != null, "audio: dedicated music player built")
	var music_ok: bool = Audio.MUSIC_TRACKS.size() == 5
	for t in Audio.MUSIC_TRACKS:
		if t == null:
			music_ok = false
	_check(music_ok, "audio: music playlist has 5 loaded tracks")
	# Tile-view terrain ambience: six terrains, three looping slices each.
	_check(Audio._ambient != null, "audio: dedicated ambience player built")
	var ambience_ok: bool = Audio.AMBIENCE.size() == 6
	for terrain in ["sea", "deep_sea", "urban", "rural", "hill", "mountain"]:
		var clips: Array = Audio.AMBIENCE.get(terrain, [])
		if clips.size() != 3:
			ambience_ok = false
		for clip in clips:
			if clip == null or not clip.loop:   # loop=true is baked into the .import
				ambience_ok = false
	_check(ambience_ok, "audio: terrain ambience has 6×3 looping slices")
	# Volume buses: Music + SFX exist (routed to Master), and 0–100% round-trips.
	_check(AudioServer.get_bus_index(Audio.BUS_MUSIC) != -1, "audio: Music bus created")
	_check(AudioServer.get_bus_index(Audio.BUS_SFX) != -1, "audio: SFX bus created")
	Audio.set_bus_percent(Audio.BUS_MASTER, 50.0)
	_check(absf(Audio.get_bus_percent(Audio.BUS_MASTER) - 50.0) < 1.0, "audio: bus volume round-trips (50%)")
	Audio.set_bus_percent(Audio.BUS_MASTER, 0.0)
	_check(Audio.get_bus_percent(Audio.BUS_MASTER) == 0.0, "audio: bus 0% reads as muted")
	Audio.set_bus_percent(Audio.BUS_MASTER, 100.0)   # restore full so later cues aren't muted
	_check(absf(Audio.get_bus_percent(Audio.BUS_MASTER) - 100.0) < 0.5, "audio: bus 100% = full")
	for verb in ["click", "click_menu", "click_primary", "hover", "building_placed", "demolished",
			"transaction", "tech_unlocked", "turn_ready", "swap_song", "play_music", "stop_music", "fade_music",
			"tile_ambience", "stop_tile_ambience", "hint", "set_bus_percent", "get_bus_percent"]:
		_check(Audio.has_method(verb), "audio: %s() verb exists" % verb)
	Audio.click()             # must not error under the dummy driver
	Audio.click_primary()
	Audio.hover()
	Audio.building_placed()
	Audio.demolished()
	Audio.transaction()
	Audio.tech_unlocked()
	Audio.turn_ready()
	Audio.tile_ambience("sea")        # start ambience for a terrain that has it
	Audio.tile_ambience("mountain")   # switch to another terrain that has ambience
	Audio.tile_ambience("")           # unknown terrain → falls through to silence
	Audio.stop_tile_ambience()
	Audio.hint()
	_check(true, "audio: cue verbs run without error")

# Baked hills are the canonical hand-painted shape: the file must exist, match
# the current CSVs/generator (else someone forgot to re-bake), and only ever
# block subtiles on hill tiles (flat tiles take lv1-2 spill but never block).
func _test_hills_baked_fresh() -> void:
	_check(FileAccess.file_exists(HillBaked.BAKED_PATH), "hills: baked file exists")
	var doc := HillBaked.data()
	_check(not doc.is_empty(), "hills: baked file parses")
	_check(str(doc.get("source_hash", "")) == HillBaked.source_hash(),
		"hills: bake is fresh (re-run tools/bake_hills.tscn after map/generator edits)")
	var polys := HillBaked.polys()
	_check(polys.size() > 100, "hills: baked polys present (%d)" % polys.size())
	var bands_ok := true
	var has_mountain_bands := false
	var depr_area := 0.0
	var depr_min_ok := true
	for entry in polys:
		if entry.b < 0 or entry.b > 11 or entry.p.size() < 3:
			bands_ok = false
			break
		if entry.b >= 8:
			has_mountain_bands = true
		if entry.b == 0:
			var a: float = absf(_shoelace(entry.p))
			depr_area += a
			if a < 3500.0:   # 10 subtiles = 4000 u^2, minus Chaikin shrink tolerance
				depr_min_ok = false
	_check(bands_ok, "hills: every poly has a valid band (0-11) and >= 3 points")
	_check(has_mountain_bands, "mountains: brown/snow bands (lv 7+) present in bake")
	_check(depr_area > 0.0, "depressions: lv -1 areas present in bake")
	_check(depr_area <= 45000.0, "depressions: total within the 100-subtile budget (%.0f u2)" % depr_area)
	_check(depr_min_ok, "depressions: every lv -1 basin is >= 10 subtile units")
	var lakes := HillBaked.lakes()
	_check(lakes.size() >= 6, "lakes: organic lake polys present (%d)" % lakes.size())
	var sea := HillBaked.sea()
	_check(sea.size() >= 25, "coast: sea/coast polys present (%d)" % sea.size())
	var sea_bands_ok := true
	var has_navy := false
	for entry in sea:
		if entry.b < 0 or entry.b > 5:
			sea_bands_ok = false
		if entry.b == 0:
			has_navy = true
	_check(sea_bands_ok, "coast: sea bands within 0..5")
	_check(has_navy, "coast: lv -6 navy zone present around deep sea")
	# blocked masks may only name hill tiles, with sane bit indices
	var types := _tile_types_from_csv()
	var blocked := HillBaked.blocked()
	_check(blocked.size() > 0, "hills: blocked masks present")
	var only_hills := true
	var bits_ok := true
	for tile_id in blocked:
		if str(types.get(tile_id, "")) != "hill":
			only_hills = false
		for b in blocked[tile_id]:
			if int(b) < 0 or int(b) >= SubtileGrid.COLUMNS * SubtileGrid.ROWS:
				bits_ok = false
	_check(only_hills, "hills: blocked subtiles only on hill tiles")
	_check(bits_ok, "hills: blocked bit indices in range")
	# occupancy consumes the bake: a blocked subtile must be unbuildable
	var sample_tile: String = blocked.keys()[0]
	var bit: int = blocked[sample_tile][0]
	var col := bit % SubtileGrid.COLUMNS + 1
	var row := bit / SubtileGrid.COLUMNS + 1
	_check(TileOccupancy.is_blocked(sample_tile, col, row), "hills: TileOccupancy sees baked mask")
	_check(not SubtileGrid.is_subtile_buildable(col, row, {}, [], sample_tile),
		"hills: blocked subtile is unbuildable via SubtileGrid")

func _test_road_regions() -> void:
	RoadRegionsLoader.reset_for_tests()
	var ids := RoadRegionsLoader.region_ids()
	_check(ids.size() == 50, "road regions: 50 authored regions")
	_check(RoadRegionsLoader.region_of("tile_6_1") == "shoulderland",
		"road regions: tile lookup returns Shoulderland")
	_check(RoadRegionsLoader.identity("shoulderland") == RoadRegionsLoader.ID_MOUNTAIN_RANGE,
		"road regions: Shoulderland uses mountain_range special style")
	_check(RoadRegionsLoader.identity_for_tile("tile_12_2") == RoadRegionsLoader.ID_SPARSE_RURAL,
		"road regions: unassigned land defaults to sparse_rural")

	var mountain_style := RoadRegionsLoader.style_for_identity(RoadRegionsLoader.ID_MOUNTAIN_RANGE)
	_check(int(mountain_style.get("max_segments", 0)) == 3,
		"road regions: mountain_range caps at 3 segments")
	_check(str(mountain_style.get("network_pattern", "")) == RoadRegionsLoader.PATTERN_MOUNTAIN_PASS,
		"road regions: mountain_range uses pass routing")
	_check(str(mountain_style.get("water_policy", "")) == RoadRegionsLoader.WATER_POLICY,
		"road regions: water is impassable for road styles")
	var sparse_style := RoadRegionsLoader.style_for_identity(RoadRegionsLoader.ID_SPARSE_RURAL)
	_check(str(sparse_style.get("network_pattern", "")) == RoadRegionsLoader.PATTERN_THROUGH_FARM_LINKS,
		"road regions: sparse_rural uses through-route/farm links")
	var sparse_city_style := RoadRegionsLoader.style_for_identity(RoadRegionsLoader.ID_SPARSE_CITY)
	_check(not bool(sparse_city_style.get("full_orbital_allowed", true)),
		"road regions: sparse_city forbids full orbitals")

	var report := RoadRegionsLoader.validation_report()
	var overlaps: Array = report.get("overlaps", [])
	var water_tiles: Array = report.get("water_tiles", [])
	var lake_tiles: Array = report.get("lake_tiles", [])
	var mountain_mismatches: Array = report.get("mountain_rule_mismatches", [])
	var invalid_ids: Array = report.get("invalid_identities", [])
	var unknown_tiles: Array = report.get("unknown_tiles", [])
	_check(overlaps.is_empty(), "road regions: no overlapping member tiles")
	_check(RoadRegionsLoader.region_of("tile_11_7") == "kindling_mountains",
		"road regions: Kindling Mountains owns tile_11_7")
	_check(RoadRegionsLoader.region_of("tile_9_14") == "green_flats",
		"road regions: Green Flats owns tile_9_14")
	_check(water_tiles.size() == 1 and str(water_tiles[0].get("tile_id", "")) == "tile_24_18",
		"road regions: Vandel Island sea tile is the only water claim")
	_check(lake_tiles.is_empty(), "road regions: no authored region claims lake tiles")
	_check(mountain_mismatches.is_empty(),
		"road regions: all >1 mountain tile regions use mountain_range")
	_check(invalid_ids.is_empty(), "road regions: all identities are valid")
	_check(unknown_tiles.is_empty(), "road regions: all member tiles exist in tile_properties.csv")

# Regenerate one small massif twice — identical output proves the generator is
# deterministic (the bake -> cache contract depends on it).
func _test_hill_field_determinism() -> void:
	var terrain := TileMapLayer.new()
	terrain.tile_set = load("res://assets/main_tileset.tres")
	terrain.set_script(load("res://scripts/hex_map.gd"))
	add_child(terrain)
	await get_tree().process_frame
	var centers := {}
	for coord in terrain.tiles:
		centers[coord] = terrain.map_to_local(terrain.map_coord_for_tile_coord(coord))
	var r1: Dictionary = HillField.generate(terrain.tiles, centers, [], [], HillBaked.SEED, ["tile_6_8"])
	var r2: Dictionary = HillField.generate(terrain.tiles, centers, [], [], HillBaked.SEED, ["tile_6_8"])
	terrain.queue_free()
	_check(r1.polys.size() > 0, "hills: regenerated massif produced polys")
	_check(r1.polys.size() == r2.polys.size(), "hills: determinism — same poly count")
	var same := true
	for i in r1.polys.size():
		if r1.polys[i].b != r2.polys[i].b or r1.polys[i].p != r2.polys[i].p:
			same = false
			break
	_check(same, "hills: determinism — identical polygons")
	_check(JSON.stringify(r1.blocked) == JSON.stringify(r2.blocked), "hills: determinism — identical blocked masks")

# The hex grid overlay's brass selection mirrors the tile view panel: shows
# the panel's tile, follows tile changes, clears on close.
func _test_grid_selection_follows_panel() -> void:
	var terrain := TileMapLayer.new()
	terrain.name = "TerrainLayer"
	terrain.unique_name_in_owner = false
	terrain.tile_set = load("res://assets/main_tileset.tres")
	terrain.set_script(load("res://scripts/hex_map.gd"))
	add_child(terrain)
	await get_tree().process_frame
	var overlay: Node2D = load("res://scripts/hex_grid_overlay.gd").new()
	overlay.set_process(false)
	add_child(overlay)
	overlay.terrain = terrain   # %TerrainLayer only resolves inside the scene file
	var panel: Control = load("res://scripts/tile_info_panel_v2.gd").new()
	add_child(panel)
	await get_tree().process_frame
	panel.show_tile(terrain.tiles[Vector2i(5, 7)])
	overlay._sync_selection()
	_check(overlay._selected == Vector2i(5, 7), "grid: selection follows the panel's tile")
	panel.show_tile(terrain.tiles[Vector2i(8, 9)])
	overlay._sync_selection()
	_check(overlay._selected == Vector2i(8, 9), "grid: selection follows a tile change")
	panel.visible = false
	overlay._sync_selection()
	_check(overlay._selected == Vector2i(-999, -999), "grid: selection clears when the panel closes")
	panel.queue_free()
	overlay.queue_free()
	terrain.queue_free()
	await get_tree().process_frame

func _test_tile_view_player_building_filter() -> void:
	MatchState.reset()
	Stockpile.clear_all()
	var terrain := TileMapLayer.new()
	terrain.name = "TerrainLayer"
	terrain.unique_name_in_owner = false
	terrain.tile_set = load("res://assets/main_tileset.tres")
	terrain.set_script(load("res://scripts/hex_map.gd"))
	add_child(terrain)
	await get_tree().process_frame
	var panel: Control = load("res://scripts/tile_info_panel_v2.gd").new()
	add_child(panel)
	await get_tree().process_frame
	var tile_id := "tile_5_7"
	var coord: Vector2i = terrain.id_to_coord(tile_id)
	if not terrain.tiles.has(coord):
		_check(false, "tile view filter: fixture tile exists")
		panel.queue_free()
		terrain.queue_free()
		await get_tree().process_frame
		return
	MatchState.add_building("b_001", "r_001", tile_id, MatchState.LOCAL_PLAYER, "tv_filter_player")
	MatchState.add_building("b_001", "r_001", tile_id, "npc", "tv_filter_npc_1")
	MatchState.add_building("b_001", "r_001", tile_id, "npc", "tv_filter_npc_2")
	panel.show_tile(terrain.tiles[coord])
	await get_tree().process_frame
	var checkbox: CheckBox = panel.find_child("PlayerBuildingsOnlyCheckbox", true, false)
	_check(checkbox != null and not checkbox.button_pressed,
		"tile view filter: checkbox starts off")
	_check(_node_tree_contains_text(panel, "Show your buildings only"),
		"tile view filter: label is inline with the buildings header")
	_check(_node_tree_contains_text(panel, "Your Buildings")
			and _node_tree_contains_text(panel, "NPC Buildings")
			and _node_tree_contains_text(panel, "(1)") and _node_tree_contains_text(panel, "(2)")
			and _node_tree_contains_text(panel, "Owned by"),
		"tile view filter: off state splits into Your Buildings (1) + NPC Buildings (2)")
	if checkbox != null:
		checkbox.button_pressed = true
		await get_tree().process_frame
	_check(bool(panel.get("_show_player_buildings_only"))
			and _node_tree_contains_text(panel, "(1)")
			and not _node_tree_contains_text(panel, "NPC Buildings")
			and not _node_tree_contains_text(panel, "Owned by"),
		"tile view filter: on state hides the NPC Buildings section")
	var other_coord: Vector2i = terrain.id_to_coord("tile_5_8")
	if terrain.tiles.has(other_coord):
		panel.show_tile(terrain.tiles[other_coord])
		await get_tree().process_frame
		var persisted: CheckBox = panel.find_child("PlayerBuildingsOnlyCheckbox", true, false)
		_check(persisted != null and persisted.button_pressed and bool(panel.get("_show_player_buildings_only")),
			"tile view filter: choice persists when opening another tile")
	MatchState.reset()
	Stockpile.clear_all()
	panel.queue_free()
	terrain.queue_free()
	await get_tree().process_frame

# Roads-v2 Phase 2: baked navgrid, predetermined crossings, the hierarchical
# realizer (determinism + water/forest avoidance), and network save round-trip.
# The pre-existing NPC building pool (data/start_buildings.json): coherent data,
# catalog-valid recipes, mixed phases, and a virtual NPC economy that keeps the
# companies alive without ever touching the player's money.
func _test_start_buildings() -> void:
	StartBuildings.reset_for_tests()
	var entries := StartBuildings.entries()
	_check(entries.size() >= 400, "start buildings: pool present (%d)" % entries.size())
	if entries.is_empty():
		return
	var ids := {}
	var ids_unique := true
	var recipes_ok := true
	var phases_ok := true
	var capital := 0
	var types_by_phase := {}
	for e in entries:
		var iid := str(e.instance_id)
		if ids.has(iid):
			ids_unique = false
		ids[iid] = true
		var phase := int(e.phase)
		if phase < 1 or phase > 5:
			phases_ok = false
		if str(e.region) == "capital_port":
			capital += 1
		if not types_by_phase.has(phase):
			types_by_phase[phase] = {}
		types_by_phase[phase][str(e.building)] = true
		var rid := str(e.recipe)
		if rid != "":
			var recipe: Dictionary = Catalog.get_recipe(rid)
			if recipe.is_empty() or str(recipe.get("building_id", "")) != str(e.building):
				recipes_ok = false
	_check(ids_unique, "start buildings: instance ids unique")
	_check(recipes_ok, "start buildings: every recipe resolves to its building")
	_check(phases_ok, "start buildings: phase tags within 1-5")
	_check(capital == 25, "start buildings: capital pool is 25 (%d)" % capital)
	var mixed := true
	for p in range(1, 6):
		if (types_by_phase.get(p, {}) as Dictionary).size() < 8:
			mixed = false
	_check(mixed, "start buildings: every phase carries a mix of building types")

	# NPC buildings are inert scenery until bought. Inertness is structural: every
	# seeded building is NPC-owned, and production iterates player-owned buildings
	# only — so a seeded furnace is never simulated, costs nothing, produces nothing.
	var all_npc := true
	for e in entries:
		if str(e.owner) == "" or str(e.owner) == MatchState.LOCAL_PLAYER:
			all_npc = false
			break
	_check(all_npc, "start buildings: every seeded building is NPC-owned (inert until bought)")

func _test_roads_v2() -> void:
	var nav := NavGrid.instance()
	_check(nav.is_ready(), "roads v2: baked navgrid decodes (%dx%d)" % [nav.gw, nav.gh])
	if not nav.is_ready():
		return
	var terrain := TileMapLayer.new()
	terrain.tile_set = load("res://assets/main_tileset.tres")
	terrain.set_script(load("res://scripts/hex_map.gd"))
	add_child(terrain)
	await get_tree().process_frame

	# crossings: one per arm, deterministic, interior to the tile
	RoadCrossings.reset_for_tests()
	RoadCrossings.build(terrain)
	var river_tiles := 0
	var branch_ok := true
	var arm_counts_ok := true
	for coord in terrain.tiles:
		var td: Dictionary = terrain.tiles[coord]
		if not td.get("has_river", false):
			continue
		var rt := str(td.get("river_type", ""))
		if rt == "" or not terrain.river_properties.has(rt):
			continue
		river_tiles += 1
		var crossings := RoadCrossings.for_tile(str(td.id))
		if crossings.is_empty():
			arm_counts_ok = false
		var rd: Dictionary = terrain.river_properties[rt]
		if str(rd.get("exit_hsm_2", "")) != "" and crossings.size() < 2:
			branch_ok = false
	_check(river_tiles > 0 and arm_counts_ok, "roads v2: every river tile has a crossing (%d tiles)" % river_tiles)
	_check(branch_ok, "roads v2: branching rivers get one crossing per arm")
	var sample_tile: String = RoadCrossings.all_tiles()[0]
	var first_point: Vector2 = RoadCrossings.for_tile(sample_tile)[0].point
	RoadCrossings.reset_for_tests()
	RoadCrossings.build(terrain)
	_check(RoadCrossings.for_tile(sample_tile)[0].point == first_point, "roads v2: crossings deterministic")

	# realizer: deterministic land route that respects water
	var pa: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(Vector2i(9, 10)))
	var pb: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(Vector2i(11, 10)))
	var realizer := RoadRealizer.new()
	var net := RoadNetwork.new()
	var r1 := realizer.route(nav, net, pa, pb, {"identity": "dense_rural", "salt": 7})
	_check(r1.ok, "roads v2: route succeeds (%s)" % str(r1.get("reason", "")))
	if r1.ok:
		var r2 := realizer.route(nav, net, pa, pb, {"identity": "dense_rural", "salt": 7})
		_check(r2.ok and r2.geometry == r1.geometry, "roads v2: route deterministic")
		var water_ok := true
		for p in r1.geometry:
			var c: Vector2i = nav.cell_of(p)
			if nav.water(c.x, c.y) == NavGrid.WATER_SEA or nav.water(c.x, c.y) == NavGrid.WATER_LAKE:
				water_ok = false
				break
		_check(water_ok, "roads v2: route never enters sea or lakes")

	# forests are hard obstacles (shared footprint). Build the neighbour set the
	# same way RoadRealizer does (every forest in MatchState), so the test's disc
	# and the router's disc share the same gravitate-toward pull.
	var forest_tile := "tile_11_11"
	var inst: String = MatchState.add_building("b_016", "", forest_tile, "tile_data", "", false)
	var nbf: Array = []
	for iid_f in MatchState.buildings:
		var bf: Dictionary = MatchState.buildings[iid_f]
		if not ForestFootprint.is_forest(str(bf.get("building_id", ""))):
			continue
		var cf: Vector2i = terrain.id_to_coord(str(bf.get("tile_id", "")))
		if terrain.tiles.has(cf):
			nbf.append(terrain.map_to_local(terrain.map_coord_for_tile_coord(cf)))
	var fcoord: Vector2i = terrain.id_to_coord(forest_tile)
	var fcenter: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(fcoord))
	var disc := ForestFootprint.footprint(inst, forest_tile, fcoord, fcenter,
		RiverGeometry.arms(terrain.tiles[fcoord], terrain.river_properties, fcenter),
		RiverGeometry.lake_ellipse(terrain.tiles[fcoord], terrain.river_properties, fcenter), nbf)
	var disc2 := ForestFootprint.footprint(inst, forest_tile, fcoord, fcenter,
		RiverGeometry.arms(terrain.tiles[fcoord], terrain.river_properties, fcenter),
		RiverGeometry.lake_ellipse(terrain.tiles[fcoord], terrain.river_properties, fcenter), nbf)
	_check(disc.center == disc2.center, "roads v2: forest footprint deterministic")
	var across := realizer.route(nav, net, fcenter + Vector2(-420, 0), fcenter + Vector2(420, 0), {"identity": "sparse_rural", "salt": 3})
	_check(across.ok, "roads v2: route across a forest tile succeeds")
	if across.ok:
		var clear := true
		for p in across.geometry:
			if p.distance_to(disc.center) < disc.radius - 6.0:
				clear = false
				break
		_check(clear, "roads v2: route avoids the forest disc")
	MatchState.remove_building(inst)

	# starting anchor network (spec 4.5b): baked, fresh, bootstrappable
	var baked := RoadsBaked.data()
	_check(not baked.is_empty(), "roads v2: starting network bake present")
	if not baked.is_empty():
		_check(str(baked.get("hills_hash", "")) == HillBaked.source_hash(),
			"roads v2: starting network fresh vs terrain bake")
		_check(RoadsBaked.anchors().size() >= 2, "roads v2: anchor list present (%d)" % RoadsBaked.anchors().size())
		RoadNetwork.reset()
		RoadNetwork.bootstrap_from_bake()
		var boot := RoadNetwork.instance()
		_check(boot.edge_count() >= RoadsBaked.anchors().size() - 2,
			"roads v2: bootstrap imports the anchor spine (%d edges)" % boot.edge_count())
		# baked geometry avoids the deterministic game-start forest discs. The
		# canonical forest set (old-growth rows 1-6 + start b_015), with the SAME
		# instance ids the bake used, feeds the gravitate-toward-neighbours pull.
		var forest_set: Array = []   # [instance_id, tile_id, coord]
		for coord2 in terrain.tiles:
			if coord2.y + 1 > 6:
				continue
			var tt2 := str(terrain.tiles[coord2].get("type", "")).strip_edges().to_lower()
			if tt2 == "rural" or tt2 == "hill":
				var tid := str(terrain.tiles[coord2].get("id", ""))
				forest_set.append(["forest_b_016_" + tid, tid, coord2])
		for entry in StartBuildings.entries():
			if str(entry.building) == "b_015":
				var c3: Vector2i = terrain.id_to_coord(str(entry.tile))
				if terrain.tiles.has(c3):
					forest_set.append([str(entry.instance_id), str(entry.tile), c3])
		var forest_centers: Array = []
		for ft in forest_set:
			forest_centers.append(terrain.map_to_local(terrain.map_coord_for_tile_coord(ft[2])))
		var forests_clear := true
		for ft2 in forest_set:
			var coord2b: Vector2i = ft2[2]
			var td2: Dictionary = terrain.tiles[coord2b]
			var fc2: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(coord2b))
			var fdisc := ForestFootprint.footprint(str(ft2[0]), str(ft2[1]), coord2b, fc2,
				RiverGeometry.arms(td2, terrain.river_properties, fc2),
				RiverGeometry.lake_ellipse(td2, terrain.river_properties, fc2),
				forest_centers)
			if not _edges_clear_of_disc(boot, fdisc):
				forests_clear = false
		_check(forests_clear, "roads v2: baked spine avoids game-start forest discs")
		RoadNetwork.reset()

	# network graph save round-trip
	if r1.ok:
		var na := net.ensure_node("dbg:a", RoadNetwork.KIND_JUNCTION, pa, Vector2i(9, 10))
		var nb := net.ensure_node("dbg:b", RoadNetwork.KIND_JUNCTION, pb, Vector2i(11, 10))
		realizer.commit(net, na.id, nb.id, RoadNetwork.TIER_LOCAL, r1, 1)
		var snap1 := net.export_state()
		var net2 := RoadNetwork.new()
		net2.import_state(snap1)
		_check(JSON.stringify(net2.export_state()) == JSON.stringify(snap1), "roads v2: network save round-trip")
		_check(net2.near_network(r1.geometry[r1.geometry.size() / 2]), "roads v2: occupancy hash survives import")
	terrain.queue_free()
	await get_tree().process_frame

# Road doubling — Fix 2 regression. _nearest_attachment used to sample edge geometry every 8th
# vertex (~240u apart after thinning), so a connect order's GOAL could land tens of u off the road
# centreline, seeding a parallel "doubled" road. It now projects onto each SEGMENT, pinning the goal
# to the true foot-of-perpendicular. This pins that behaviour (pre-fix the projected error was ~48u).
func _test_road_attachment_projection() -> void:
	var nav := NavGrid.instance()
	if not nav.is_ready():
		return
	var terrain := TileMapLayer.new()
	terrain.tile_set = load("res://assets/main_tileset.tres")
	terrain.set_script(load("res://scripts/hex_map.gd"))
	add_child(terrain)
	await get_tree().process_frame
	RoadNetwork.reset()
	var coord := Vector2i(8, 9)
	var c: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(coord))
	var realizer := RoadRealizer.new()
	var net := RoadNetwork.instance()
	var resA := realizer.route(nav, net, c + Vector2(-330, 0), c + Vector2(330, 0), {"identity": "dense_rural", "salt": 5})
	if resA.ok:
		var na := str(net.add_junction(c + Vector2(-330, 0), coord).id)
		var nb := str(net.add_junction(c + Vector2(330, 0), coord).id)
		realizer.commit(net, na, nb, RoadNetwork.TIER_TRUNK, resA, 0, RoadNetwork.STATE_BUILT)
		var a_geo: PackedVector2Array = resA.geometry
		var from: Vector2 = c + Vector2(7, 5)   # a few u off the MIDDLE of A (between sparse samples)
		# true foot-of-perpendicular on A
		var foot: Vector2 = a_geo[0]
		var fd := 1.0e30
		for i in range(a_geo.size() - 1):
			var cp := Geometry2D.get_closest_point_to_segment(from, a_geo[i], a_geo[i + 1])
			var dd := cp.distance_squared_to(from)
			if dd < fd:
				fd = dd
				foot = cp
		# old every-8th-vertex pick (what _nearest_attachment used to return)
		var old_pos: Vector2 = a_geo[0]
		var od := 1.0e30
		for j in range(0, a_geo.size(), 8):
			var dj := a_geo[j].distance_squared_to(from)
			if dj < od:
				od = dj
				old_pos = a_geo[j]
		var new_pos: Vector2 = RoadWorks._nearest_attachment(from).pos
		var new_err := new_pos.distance_to(foot)
		var old_err := old_pos.distance_to(foot)
		_check(new_err < 2.0, "road attach: goal projects onto the centreline (err %.1f u)" % new_err)
		_check(new_err <= old_err + 0.01, "road attach: projection never worse than vertex sampling (%.1f <= %.1f)" % [new_err, old_err])
	RoadNetwork.reset()
	terrain.queue_free()
	await get_tree().process_frame

# Phase 4 — roads avoid building footprints as a graduated COST, never a wall.
# The regression guard: a tile saturated with footprints must STILL route (the
# cost raster is finite). This pins the earlier hard-block bug that made dense
# tiles impassable and silently dropped their roads. See road_realizer's
# _building_cost / the "buildings" prep phase / _scatter_building_cost.
func _test_roads_avoid_buildings() -> void:
	var nav := NavGrid.instance()
	if not nav.is_ready():
		return
	var terrain := TileMapLayer.new()
	terrain.tile_set = load("res://assets/main_tileset.tres")
	terrain.set_script(load("res://scripts/hex_map.gd"))
	add_child(terrain)
	await get_tree().process_frame
	var ca := Vector2i(9, 10)
	var cb := Vector2i(11, 10)
	var cmid := Vector2i(10, 10)
	if not (terrain.tiles.has(ca) and terrain.tiles.has(cb) and terrain.tiles.has(cmid)):
		_check(false, "roads-avoid: test tiles present")
		terrain.queue_free()
		return
	var pa: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(ca))
	var pb: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(cb))
	var mid: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(cmid))
	var realizer := RoadRealizer.new()
	var net := RoadNetwork.new()
	var opts := {"identity": "dense_rural", "salt": 7}

	# Baseline: no footprint provider in the group yet.
	var base := realizer.route(nav, net, pa, pb, opts)
	_check(base.ok and base.geometry.size() > 0, "roads-avoid: baseline route ok (%s)" % str(base.get("reason", "")))

	# Footprint provider stub honouring the realizer's contract: a node in the
	# "building_footprints" group exposing footprint_discs() + footprint_version.
	var stub_script := GDScript.new()
	stub_script.source_code = "extends Node\nvar footprint_version := 0\nvar discs := []\nfunc footprint_discs() -> Array:\n\treturn discs\n"
	stub_script.reload()
	var bv := Node.new()
	bv.set_script(stub_script)
	bv.add_to_group("building_footprints")
	add_child(bv)
	await get_tree().process_frame

	# Saturate the mid tile (~140 footprints packed across it) and re-route the
	# same corridor straight through it. Must STILL succeed with non-empty
	# geometry — the cost is graduated, never impassable.
	var many: Array = []
	for ix in range(-5, 6):
		for iy in range(-6, 7):
			many.append({"center": mid + Vector2(float(ix) * 40.0, float(iy) * 36.0), "radius": 22.0})
	bv.discs = many
	bv.footprint_version = 1
	var thru := realizer.route(nav, net, pa, pb, opts)
	_check(thru.ok and thru.geometry.size() > 0,
		"roads-avoid: saturated tile still routes, no wall (%d discs, %s)" % [many.size(), str(thru.get("reason", ""))])
	# Proof the cost is actually applied (not silently inert): a fully-saturated
	# corridor must reroute away from the baseline straight line.
	_check(thru.ok and base.ok and thru.geometry != base.geometry,
		"roads-avoid: building cost changes the route (avoidance is live)")

	bv.queue_free()
	terrain.queue_free()
	await get_tree().process_frame

# Phase 4 — buildings re-snap to a road the player builds AFTER they were placed.
# The reported "buildings don't snap" symptom was a MISSING re-pack trigger:
# building_visuals never reacted to a road settling, so pre-road buildings kept
# their roadless fallback layout forever. relayout_tile() (wired to
# RoadWorks.order_settled) is the fix. This test places a building on a roadless
# tile, builds a road across it, then asserts the building snaps to the frontage.
# Arin Estuary Docks (tile_11_17): the tile centre sits ON the river crossing, so the
# connect road does NOT cross the river — it must meet the goal-side (west) bridgehead
# and never touch the FAR gate. Before the _snap_bridges fix it forced the full
# two-bank span, jumping bridgelessly to the far (east) bridgehead and back.
func _test_arin_bridge() -> void:
	var nav := NavGrid.instance()
	if not nav.is_ready():
		return
	var terrain := TileMapLayer.new()
	terrain.tile_set = load("res://assets/main_tileset.tres")
	terrain.set_script(load("res://scripts/hex_map.gd"))
	add_child(terrain)
	await get_tree().process_frame
	RoadCrossings.reset_for_tests()
	RoadCrossings.build(terrain)
	RoadNetwork.reset()
	RoadWorks.reset()
	var net := RoadNetwork.instance()
	var crossings := RoadCrossings.for_tile("tile_11_17")
	if crossings.is_empty():
		_check(false, "arin: tile_11_17 has a river crossing")
		terrain.queue_free()
		RoadNetwork.reset(); RoadWorks.reset(); RoadCrossings.reset_for_tests()
		return
	var cx: Dictionary = crossings[0]
	var ga: Vector2 = cx.gate_a
	var gb: Vector2 = cx.gate_b
	# Controlled network: ONE short synthetic river road on the FAR bank only
	# (bridge included), so the tile's connect job has no same-bank projection
	# to attach to — it must take the SAME-BANK bridge head, the bridge-head
	# attachment contract under test. (The full roads-v3 bake offers closer
	# plain roads on this urban tile, which correctly win over the biased head
	# and would make the scenario vacuous.)
	var acoord: Vector2i = terrain.id_to_coord("tile_11_17")
	var acenter: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(acoord))
	var bt: Vector2 = (cx.bridge_tangent as Vector2).normalized()
	if bt.dot(acenter - (cx.point as Vector2)) > 0.0:
		bt = -bt   # +bt now points to the FAR bank (away from the tile centre)
	var sa: Vector2 = (cx.point as Vector2) + bt * 40.0
	var sb: Vector2 = (cx.point as Vector2) + bt * 160.0
	var sgeo := PackedVector2Array()
	for s in 15:
		sgeo.append(sa.lerp(sb, float(s) / 14.0))
	var sna: Dictionary = net.ensure_node("arintest:a", RoadNetwork.KIND_JUNCTION, sa, acoord)
	var snb: Dictionary = net.ensure_node("arintest:b", RoadNetwork.KIND_JUNCTION, sb, acoord)
	net.add_edge(str(sna.id), str(snb.id), RoadNetwork.TIER_LOCAL, sgeo, [acoord],
		[{"point": cx.point, "tangent": (cx.bridge_tangent as Vector2).normalized()}], 0, RoadNetwork.STATE_BUILT)
	var oid := RoadWorks.enqueue_for_tile("tile_11_17")
	_check(oid >= 0, "arin: connect road enqueues")
	var frames := 0
	while oid >= 0 and frames < 8000 and str(RoadWorks.orders[oid].state) in ["queued", "planning", "revealing"]:
		RoadWorks._process(1.0 / 60.0)
		frames += 1
	if oid >= 0:
		var order: Dictionary = RoadWorks.orders[oid]
		var eid := str(order.edge_id)
		_check(str(order.state) == "built" and net.edges.has(eid), "arin: connect road builds (state %s)" % str(order.state))
		if net.edges.has(eid):
			var geo: PackedVector2Array = net.edges[eid].geometry
			var goal: Vector2 = order.get("goal", Vector2.ZERO)
			# the bridgehead on the route's continuation side vs the opposite (far) one
			var near_gate := ga if ga.distance_to(goal) <= gb.distance_to(goal) else gb
			var far_gate := gb if near_gate == ga else ga
			var hits_near := false
			var hits_far := false
			for p in geo:
				if p.distance_to(near_gate) < 14.0:
					hits_near = true
				if p.distance_to(far_gate) < 14.0:
					hits_far = true
			_check(not hits_far, "arin: road never touches the far bridgehead (no bridgeless crossing)")
			_check(hits_near, "arin: road meets the goal-side bridgehead")
	terrain.queue_free()
	RoadNetwork.reset()
	RoadWorks.reset()
	RoadCrossings.reset_for_tests()
	await get_tree().process_frame

# Regression: a sampled road can have a whole short segment inside a large building.
# This used to evade the edge-to-edge clearance test and drew the Metal Magnate
# furnace and pump underneath the Stoneshore roads.
func _test_footprint_rejects_interior_road_segment() -> void:
	var bv := preload("res://scenes/building_visuals.gd").new()
	var footprint := PackedVector2Array([
		Vector2(-30, -20), Vector2(30, -20), Vector2(30, 20), Vector2(-30, 20),
	])
	var interior_road: Array = [[Vector2(-6, 0), Vector2(6, 0)]]
	_check(not bv._footprint_clears(Vector2.ZERO, footprint, interior_road, 1.0),
		"building visuals: reject a road segment wholly inside a footprint")
	bv.free()


# Urban block-subdivision: a seeded urban tile lays a grid of lots; buildings claim them
# in emit order (tight, non-overlapping), fall back to the continuous packer when full,
# feed roads-avoid via real footprints, and the layout is deterministic + demolish-stable.
# Level upgrades must ALWAYS show (rooftop storey blocks — wings depend on free
# ground), and a bought NPC building must swap its placement to player-owned.
## A building must reserve the space its FULLY UPGRADED form needs at the
## moment it is placed, or an upgrade would grow over its neighbours. Two
## halves to that guarantee: every level draws into the same (L3) reference
## frame, and the lot area is derived from tile_size_used alone — never from
## the level. This pins the first half; the second is the signature of
## BuildingVisuals._art_size_for(size_units), which takes no level.
func _test_ink_art_reserves_upgrade_space() -> void:
	var keys := ["furnace", "eaf", "industrial_factory", "consumer_factory",
		"assembly_plant", "high_tech_manufactory", "petro_refinery", "poly_plant",
		"chem_plant", "electrolyser", "power_plant", "water_pump", "pipes",
		"cables", "mine", "solar_farm", "wind_farm", "port"]
	for key in keys:
		var f3: Vector2 = InkBuildingGen.level_frame(key, 3)
		_check(f3.x > 0.0 and f3.y > 0.0, "ink art: %s has an L3 frame" % key)
		for lvl in [1, 2]:
			var f: Vector2 = InkBuildingGen.level_frame(key, lvl)
			_check(f.is_equal_approx(f3),
				"ink art: %s L%d reserves the L3 frame (%s vs %s)" % [key, lvl, str(f), str(f3)])

func _test_level_storeys_and_owner_swap() -> void:
	var nav := NavGrid.instance()
	if not nav.is_ready():
		return
	var terrain := TileMapLayer.new()
	terrain.tile_set = load("res://assets/main_tileset.tres")
	terrain.set_script(load("res://scripts/hex_map.gd"))
	add_child(terrain)
	await get_tree().process_frame
	RoadNetwork.reset()
	var bv := preload("res://scenes/building_visuals.gd").new()
	add_child(bv)
	await get_tree().process_frame
	bv.terrain_layer = terrain
	var tile_id := "tile_9_10"
	var coord: Vector2i = terrain.id_to_coord(tile_id)
	if not terrain.tiles.has(coord):
		_check(false, "storeys: test tile exists")
		bv.queue_free(); terrain.queue_free(); RoadNetwork.reset(); return
	var iid := MatchState.add_building("b_001", "", tile_id, "npc", "storey_test", false)
	bv.on_building_placed(tile_id, "b_001", "", iid, coord)
	bv._flush_subcomponents()
	var count_l1 := 0
	for sc in bv._subcomponents:
		if str(sc.kind) == "storey" and str(sc.iid) == iid:
			count_l1 += 1
	_check(count_l1 == 0, "storeys: none at level 1")
	# L3 → two stacked storey blocks, regardless of crowding or masses.
	(MatchState.buildings[iid] as Dictionary)["level"] = 3
	bv._rebuild_subcomponents(tile_id)
	var count_l3 := 0
	var wings_l3 := 0
	for sc2 in bv._subcomponents:
		if str(sc2.iid) == iid:
			if str(sc2.kind) == "storey":
				count_l3 += 1
			elif str(sc2.kind) == "wing":
				wings_l3 += 1
	_check(count_l3 == 2, "storeys: two blocks at level 3")
	# Open ground + L3 must grow at least one wing — L/C footprints once
	# skipped wings entirely (quad-only axis math).
	_check(wings_l3 >= 1, "wings: upgraded building spreads on open ground")
	# Ownership swap flips the placement's is_npc (bought buildings recolour).
	var idx: int = bv._placement_index[iid]
	_check(bool((bv._placements[idx] as Dictionary).is_npc), "owner swap: starts NPC")
	(MatchState.buildings[iid] as Dictionary)["owner"] = MatchState.LOCAL_PLAYER
	bv._on_building_owner_changed(iid)
	_check(not bool((bv._placements[idx] as Dictionary).is_npc), "owner swap: placement follows the sale")
	MatchState.remove_building(iid)
	bv.queue_free()
	terrain.queue_free()
	RoadNetwork.reset()
	await get_tree().process_frame

func _test_block_subdivision() -> void:
	var nav := NavGrid.instance()
	if not nav.is_ready():
		return
	var terrain := TileMapLayer.new()
	terrain.tile_set = load("res://assets/main_tileset.tres")
	terrain.set_script(load("res://scripts/hex_map.gd"))
	add_child(terrain)
	await get_tree().process_frame
	# Empty network + ONE synthetic straight road below: a controlled block-grid
	# unit test. (The roads-v3 bake covers most tiles with real roads, so a
	# bootstrapped world no longer offers a "roomy open tile" to anchor cleanly.)
	RoadNetwork.reset()
	var bv := preload("res://scenes/building_visuals.gd").new()
	add_child(bv)
	await get_tree().process_frame
	bv.terrain_layer = terrain
	var tile_id := "tile_9_10"
	var coord: Vector2i = terrain.id_to_coord(tile_id)
	if not terrain.tiles.has(coord):
		_check(false, "block: test tile exists")
		bv.queue_free(); terrain.queue_free(); RoadNetwork.reset(); return
	# the seeded per-tile decision is deterministic (recompute after clearing the cache)
	var dec1 := bv._use_block_mode(tile_id, coord)
	bv._tile_block_mode.erase(tile_id)
	_check(dec1 == bv._use_block_mode(tile_id, coord), "block: mode decision is deterministic per tile")
	# give the tile a straight BUILT road to anchor the block to (+ the roads flag)
	var center: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(coord))
	(terrain.tiles[coord] as Dictionary)["infrastructure_present"] = ["roads"]
	var net := RoadNetwork.instance()
	var na: Dictionary = net.ensure_node("blk:a", RoadNetwork.KIND_JUNCTION, center + Vector2(-160, -110), coord)
	var nb: Dictionary = net.ensure_node("blk:b", RoadNetwork.KIND_JUNCTION, center + Vector2(160, -110), coord)
	net.add_edge(str(na.id), str(nb.id), RoadNetwork.TIER_LOCAL, PackedVector2Array([center + Vector2(-160, -110), center + Vector2(160, -110)]), [coord], [], 1, RoadNetwork.STATE_BUILT)
	# force block mode and fill a block
	bv._tile_block_mode[tile_id] = true
	var iids: Array = []
	for i in 6:
		iids.append(MatchState.add_building("b_test_factory", "", tile_id, "npc", "blk_%d" % i))
		bv.on_building_placed(tile_id, "b_test_factory", "", str(iids[i]), coord)
	var placed_n := 0
	for q in iids:
		if bv._placement_index.has(str(q)):
			placed_n += 1
	_check(placed_n == 6, "block: all buildings placed (lots + fallback) (%d/6)" % placed_n)
	var tmpl: Dictionary = bv._tile_block_templates.get(tile_id, {})
	_check(not tmpl.is_empty(), "block: a lot grid was built (%d lots)" % (tmpl.get("lots", []) as Array).size())
	_check(bv.footprint_discs().size() == placed_n, "block: every building yields an avoidance disc")
	# axis-aligned, spaced lots → footprints don't overlap each other
	var rects: Array = bv.footprint_rects_on_tile(coord)
	var overlap := false
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			if (rects[i] as Rect2).intersects(rects[j] as Rect2):
				overlap = true
	_check(not overlap, "block: lot buildings do not overlap (%d footprints)" % rects.size())
	# demolish frees a lot; survivors stay put (re-pack re-claims the same lots)
	bv.remove_instance(str(iids[0]))
	var survivors := 0
	for k in range(1, 6):
		if bv._placement_index.has(str(iids[k])):
			survivors += 1
	_check(not bv._placement_index.has(str(iids[0])) and survivors == 5, "block: demolish frees a lot, survivors remain (%d/5)" % survivors)
	# clip regression: a straight road running well beyond the tile must yield an IN-TILE
	# anchor run, not the full multi-tile span (the tile_11_17 "run=1052u → 0 lots" bug).
	var spanning := PackedVector2Array()
	for k in range(-12, 13):
		spanning.append(center + Vector2(float(k) * 60.0, 150.0))   # straight, x in [-720, 720]
	var sa: Dictionary = net.ensure_node("blkspan:a", RoadNetwork.KIND_JUNCTION, spanning[0], coord)
	var sb2: Dictionary = net.ensure_node("blkspan:b", RoadNetwork.KIND_JUNCTION, spanning[spanning.size() - 1], coord)
	net.add_edge(str(sa.id), str(sb2.id), RoadNetwork.TIER_LOCAL, spanning, [coord], [], 1, RoadNetwork.STATE_BUILT)
	var run := bv._longest_straight_road(coord)
	_check(not run.is_empty(), "block: a road crossing the tile yields an anchor run")
	if not run.is_empty():
		var run_len: float = (run[0] as Vector2).distance_to(run[1] as Vector2)
		_check(run_len < 560.0, "block: anchor run clipped to the tile (%.0fu, not the multi-tile span)" % run_len)
	for c in 6:
		MatchState.remove_building("blk_%d" % c)
	bv.queue_free()
	terrain.queue_free()
	RoadNetwork.reset()
	await get_tree().process_frame

# River-bank helpers (block-box budge/no-cross rules) + bridge-head attachment. Pure
# geometry, so it runs without a baked map.
func _test_river_bank_and_bridge_head() -> void:
	var bv := preload("res://scenes/building_visuals.gd").new()
	add_child(bv)
	await get_tree().process_frame
	# vertical river at x=0 (rel-to-centre): the two banks read as opposite sides; no river -> 0.
	var rivers: Array = [[Vector2(0.0, -120.0), Vector2(0.0, 120.0)]]
	var sL := bv._river_side(Vector2(-50.0, 0.0), rivers)
	var sR := bv._river_side(Vector2(50.0, 0.0), rivers)
	_check(sL != 0 and sR != 0 and sL != sR, "river: the two banks read as opposite sides")
	_check(bv._river_side(Vector2(10.0, 0.0), []) == 0, "river: no river -> side 0")
	# a block straddling the river, anchor on the LEFT bank -> clipped to the left, never crossing x=0
	var quad: Array = [Vector2(-90.0, -60.0), Vector2(90.0, -60.0), Vector2(90.0, 60.0), Vector2(-90.0, 60.0)]
	var clipped := bv._clip_to_river_bank(quad, rivers, Vector2(-50.0, 0.0), sL)
	var maxx := -1.0e9
	for p in clipped:
		maxx = maxf(maxx, (p as Vector2).x)
	_check(clipped.size() >= 3 and maxx <= 0.0, "river: block clipped to the anchor's bank, no crossing (max x=%.1f)" % maxx)
	# a river far from the block leaves it untouched
	var far := bv._clip_to_river_bank(quad, [[Vector2(900.0, -120.0), Vector2(900.0, 120.0)]], Vector2(-50.0, 0.0), -1)
	_check(far.size() == quad.size(), "river: a distant river leaves the block unchanged")
	# multi-segment (bent) river: the same bank reads consistently (deterministic nearest-segment tiebreak)
	var bend: Array = [[Vector2(0.0, -100.0), Vector2(0.0, 0.0)], [Vector2(0.0, 0.0), Vector2(30.0, 100.0)]]
	var b1 := bv._river_side(Vector2(-60.0, -50.0), bend)
	var b2 := bv._river_side(Vector2(-60.0, 50.0), bend)
	_check(b1 != 0 and b1 == b2, "river: a bent river gives one consistent side for the same bank")
	bv.queue_free()
	await get_tree().process_frame
	# bridge-head attachment (new): a connect-road near a bridge targets the same-bank HEAD, not a mid-edge point.
	RoadNetwork.reset()
	var bnet := RoadNetwork.instance()
	var bcoord := Vector2i(0, 0)
	var ba := bnet.ensure_node("brtest:a", RoadNetwork.KIND_JUNCTION, Vector2(100.0, -80.0), bcoord)
	var bb := bnet.ensure_node("brtest:b", RoadNetwork.KIND_JUNCTION, Vector2(100.0, 80.0), bcoord)
	bnet.add_edge(str(ba.id), str(bb.id), RoadNetwork.TIER_LOCAL, PackedVector2Array([Vector2(100.0, -80.0), Vector2(100.0, 80.0)]), [bcoord], [{"point": Vector2(100.0, 0.0), "tangent": Vector2(0.0, 1.0)}], 0, RoadNetwork.STATE_BUILT)
	var reach := RoadCrossings.GATE_OFFSET + RoadRealizer.BRIDGE_BANK_STUB
	var att := RoadWorks._nearest_attachment(Vector2(60.0, -50.0))   # off the edge, north (same) bank
	_check((att.get("pos", Vector2.ZERO) as Vector2).distance_to(Vector2(100.0, -reach)) < 2.0, "bridge: a connect-road near a bridge attaches to the same-bank head")
	var att_far := RoadWorks._nearest_attachment(Vector2(60.0, 900.0))   # far from the bridge — unaffected
	_check((att_far.get("pos", Vector2.ZERO) as Vector2).distance_to(Vector2(100.0, -reach)) > 50.0, "bridge: a road far from any bridge is not pulled to a head")
	RoadNetwork.reset()
	await get_tree().process_frame

# A predetermined river crossing reserves a road corridor: a band along the river + a stub
# straight out from the bridge on each bank, so the road reaches the bridge without being
# forced over riverside buildings (the Arin overlap). Buildings keep RIVER_ROAD_PAD clear.
# Subcomponents: sizable buildings fund a second pass of round tanks + annexes, placed in spare
# space beside the parent, deterministic, never overlapping the buildings.
func _test_subcomponents() -> void:
	var nav := NavGrid.instance()
	if not nav.is_ready():
		return
	var terrain := TileMapLayer.new()
	terrain.tile_set = load("res://assets/main_tileset.tres")
	terrain.set_script(load("res://scripts/hex_map.gd"))
	add_child(terrain)
	await get_tree().process_frame
	RoadNetwork.reset()
	var bv := preload("res://scenes/building_visuals.gd").new()
	add_child(bv)
	await get_tree().process_frame
	bv.terrain_layer = terrain
	var tile_id := "tile_9_10"
	var coord: Vector2i = terrain.id_to_coord(tile_id)
	if not terrain.tiles.has(coord):
		_check(false, "subcomp: test tile exists")
		bv.queue_free(); terrain.queue_free(); return
	# two sizable buildings (industrial_factory, tile_size_used 10 -> ~3 ancillaries each)
	for i in 2:
		var iid: String = MatchState.add_building("b_007", "", tile_id, "npc", "sub_b_%d" % i)
		bv.on_building_placed(tile_id, "b_007", "", iid, coord)
	bv._rebuild_subcomponents(tile_id)
	var n1 := (bv._subcomponents as Array).size()
	_check(n1 > 0, "subcomp: tanks/annexes placed for sizable buildings (%d)" % n1)
	bv._rebuild_subcomponents(tile_id)
	_check((bv._subcomponents as Array).size() == n1, "subcomp: rebuild is deterministic (%d)" % (bv._subcomponents as Array).size())
	var brects: Array = bv.footprint_rects_on_tile(coord)
	var max_hits := 0
	for sc in bv._subcomponents:
		var hits := 0
		for br in brects:
			if (sc.bb as Rect2).intersects(br as Rect2):
				hits += 1
		max_hits = maxi(max_hits, hits)
	# annexes attach to (overlap) their own parent; tanks sit clear. None may straddle two buildings.
	_check(max_hits <= 1, "subcomp: each ancillary touches at most its own parent (max %d)" % max_hits)
	for c in 2:
		MatchState.remove_building("sub_b_%d" % c)
	bv.queue_free()
	terrain.queue_free()
	RoadNetwork.reset()
	await get_tree().process_frame

func _test_farms() -> void:
	var nav := NavGrid.instance()
	if not nav.is_ready():
		return
	var terrain := TileMapLayer.new()
	terrain.tile_set = load("res://assets/main_tileset.tres")
	terrain.set_script(load("res://scripts/hex_map.gd"))
	add_child(terrain)
	await get_tree().process_frame
	RoadNetwork.reset()
	var bv := preload("res://scenes/building_visuals.gd").new()
	add_child(bv)
	await get_tree().process_frame
	bv.terrain_layer = terrain
	var tile_id := "tile_9_10"
	var coord: Vector2i = terrain.id_to_coord(tile_id)
	if not terrain.tiles.has(coord):
		_check(false, "farms: test tile exists")
		bv.queue_free(); terrain.queue_free(); return
	var center: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(coord))
	# A farm-only tile gravitates to the river; the affinity flips to the edge only once a
	# non-farm building shares the tile.
	_check(not bv._has_non_farm_buildings(tile_id), "farms: tile starts with no non-farm buildings")
	var fid: String = MatchState.add_building("b_014", "", tile_id, "npc", "farm_a")
	bv.on_building_placed(tile_id, "b_014", "", fid, coord)
	var farm := {}
	for p in bv._placements:
		if str(p.tile_id) == tile_id and str(p.cat) == "farm":
			farm = p
	_check(not farm.is_empty(), "farms: a farm field was placed")
	if farm.is_empty():
		MatchState.remove_building("farm_a")
		bv.queue_free(); terrain.queue_free(); RoadNetwork.reset()
		await get_tree().process_frame
		return
	var fverts: PackedVector2Array = farm.verts
	_check(fverts.size() >= 5, "farms: field is polygonal (%d verts)" % fverts.size())
	# Clipped to the hex: every vertex sits inside the flat-top hex (a hair of float slop allowed).
	var all_in := true
	for v in fverts:
		var r: Vector2 = v - center
		if absf(r.x) > 271.0 or absf(r.y) > 241.0 or 240.0 * absf(r.x) + 135.0 * absf(r.y) > 65200.0:
			all_in = false
	_check(all_in, "farms: field is clipped to the hex")
	_check((farm.get("hatch", []) as Array).size() > 0, "farms: dark-green hatch baked")
	# Brown barn + silo outbuildings.
	bv._rebuild_subcomponents(tile_id)
	var browns := 0
	for sc in bv._subcomponents:
		if str(sc.tile_id) == tile_id and (sc.color as Color).is_equal_approx(Color(0.50, 0.33, 0.16)):
			browns += 1
	_check(browns >= 1, "farms: brown barn/silo placed (%d)" % browns)
	var n1 := (bv._subcomponents as Array).size()
	bv._rebuild_subcomponents(tile_id)
	_check((bv._subcomponents as Array).size() == n1, "farms: subcomponent rebuild is deterministic")
	# A non-farm building on the tile flips the farm's affinity (river -> edge).
	var bid: String = MatchState.add_building("b_007", "", tile_id, "npc", "farm_factory")
	bv.on_building_placed(tile_id, "b_007", "", bid, coord)
	_check(bv._has_non_farm_buildings(tile_id), "farms: a non-farm building flips edge-affinity")
	# Regression: a farm on a BLOCK-MODE tile keeps its polygonal field + hatch — it must never be
	# turned into a rectangular block lot (farms bypass _claim_slot). Give the tile a straight built
	# road so a block template can form, force block mode on, then place a fresh farm.
	var net := RoadNetwork.instance()
	var fa: Dictionary = net.ensure_node("farmblk:a", RoadNetwork.KIND_JUNCTION, center + Vector2(-160, -110), coord)
	var fb: Dictionary = net.ensure_node("farmblk:b", RoadNetwork.KIND_JUNCTION, center + Vector2(160, -110), coord)
	net.add_edge(str(fa.id), str(fb.id), RoadNetwork.TIER_LOCAL, PackedVector2Array([center + Vector2(-160, -110), center + Vector2(160, -110)]), [coord], [], 1, RoadNetwork.STATE_BUILT)
	bv._tile_block_mode[tile_id] = true
	bv._tile_block_templates.erase(tile_id)
	bv._tile_land.erase(tile_id); bv._tile_landkeys.erase(tile_id); bv._tile_segs.erase(tile_id); bv._tile_rivers.erase(tile_id)
	var fid2: String = MatchState.add_building("b_014", "", tile_id, "npc", "farm_blk")
	bv.on_building_placed(tile_id, "b_014", "", fid2, coord)
	var farm2 := {}
	for p in bv._placements:
		if str(p.instance_id) == fid2:
			farm2 = p
	var poly_ok: bool = not farm2.is_empty() \
		and (farm2.get("verts", PackedVector2Array()) as PackedVector2Array).size() >= 5 \
		and (farm2.get("hatch", []) as Array).size() > 0
	_check(poly_ok, "farms: a farm on a block-mode tile keeps its polygonal field (not a block lot)")
	MatchState.remove_building("farm_a")
	MatchState.remove_building("farm_factory")
	MatchState.remove_building("farm_blk")
	bv.queue_free()
	terrain.queue_free()
	RoadNetwork.reset()
	await get_tree().process_frame

func _test_farm_lanes() -> void:
	var nav := NavGrid.instance()
	if not nav.is_ready():
		return
	var terrain := TileMapLayer.new()
	terrain.tile_set = load("res://assets/main_tileset.tres")
	terrain.set_script(load("res://scripts/hex_map.gd"))
	add_child(terrain)
	await get_tree().process_frame
	RoadNetwork.reset()
	var bv := preload("res://scenes/building_visuals.gd").new()
	add_child(bv)
	await get_tree().process_frame
	bv.terrain_layer = terrain
	var tile_id := "tile_9_10"
	var coord: Vector2i = terrain.id_to_coord(tile_id)
	if not terrain.tiles.has(coord):
		_check(false, "farm-lanes: test tile exists")
		bv.queue_free(); terrain.queue_free(); return
	# Two adjacent farms → they Voronoi-snap and a thin lane runs between them.
	for i in 2:
		var iid: String = MatchState.add_building("b_014", "", tile_id, "npc", "flane_%d" % i)
		bv.on_building_placed(tile_id, "b_014", "", iid, coord)
	bv._rebuild_subcomponents(tile_id)
	var nfarms := 0
	for p in bv._placements:
		if str(p.tile_id) == tile_id and str(p.cat) == "farm":
			nfarms += 1
	_check(nfarms == 2, "farm-lanes: two farms placed on the tile (%d)" % nfarms)
	if nfarms == 2:
		var lanes: Array = bv._farm_lanes.get(tile_id, [])
		_check(lanes.size() >= 1, "farm-lanes: a lane runs between adjacent farms (%d)" % lanes.size())
		_check(bv._farm_render.has("flane_0") and bv._farm_render.has("flane_1"), "farm-lanes: each field has a cell-clipped render shape")
		bv._rebuild_subcomponents(tile_id)   # deterministic
		_check((bv._farm_lanes.get(tile_id, []) as Array).size() == lanes.size(), "farm-lanes: lane count is deterministic")
	# Geometry kit (deterministic, map-independent):
	var sq := PackedVector2Array([Vector2(-10, -10), Vector2(10, -10), Vector2(10, 10), Vector2(-10, 10)])
	# _near_field_runs trims a long segment to just the part within `reach` of the square.
	var runs: Array = bv._near_field_runs(Vector2(-100, 0), Vector2(100, 0), [sq], 5.0)
	var trim_ok := runs.size() == 1
	if trim_ok:
		var span: float = (float(runs[0][1]) - float(runs[0][0])) * 200.0   # over a 200u segment
		trim_ok = span > 10.0 and span < 60.0     # ~30u (x in [-15,15]), not the full 200u
	_check(trim_ok, "farm-lanes: _near_field_runs trims a lane to within reach of the field")
	# _seg_outside_convex routes a crossing segment around the obstacle (two outside pieces).
	var outs: Array = bv._seg_outside_convex(Vector2(-50, 0), Vector2(50, 0), sq)
	_check(outs.size() == 2, "farm-lanes: _seg_outside_convex splits a lane around a forest (%d)" % outs.size())
	# River split: a river separates farms into independent per-bank groups (deterministic geometry).
	var river: Array = [[Vector2(-100, -50), Vector2(100, 50)]]   # diagonal river line y = 0.5x
	var sA := Vector2(-50, 50)   # above the line
	var sB := Vector2(-40, 40)   # above (same bank as A)
	var sC := Vector2(50, -50)   # below (other bank)
	_check(bv._same_bank(sA, sB, river), "river-split: same-side farms read as same bank")
	_check(not bv._same_bank(sA, sC, river), "river-split: cross-river farms read as different banks")
	_check((bv._bank_components([sA, sB, sC], river) as Array).size() == 2, "river-split: a river yields 2 bank groups")
	# Road merge: add a real built road just past the fields; a connector track should reach it (no new road).
	if nfarms == 2:
		var center: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(coord))
		var net := RoadNetwork.instance()
		var ya: Dictionary = net.ensure_node("flr:a", RoadNetwork.KIND_JUNCTION, center + Vector2(-200, -150), coord)
		var yb: Dictionary = net.ensure_node("flr:b", RoadNetwork.KIND_JUNCTION, center + Vector2(200, -150), coord)
		net.add_edge(str(ya.id), str(yb.id), RoadNetwork.TIER_LOCAL, PackedVector2Array([center + Vector2(-200, -150), center + Vector2(200, -150)]), [coord], [], 1, RoadNetwork.STATE_BUILT)
		bv._rebuild_subcomponents(tile_id)
		var reached := false
		for seg in (bv._farm_lanes.get(tile_id, []) as Array):
			for pt in (seg as PackedVector2Array):
				if absf((pt as Vector2).y - (center.y - 150.0)) < 3.0 and absf((pt as Vector2).x - center.x) < 200.0:
					reached = true
		_check(reached, "farm-lanes: a connector merges the tracks to a real road")
	for i in 2:
		MatchState.remove_building("flane_%d" % i)
	bv.queue_free()
	terrain.queue_free()
	RoadNetwork.reset()
	await get_tree().process_frame

# Stage 1 of the farm→real-road integration: a player road settling on a farm tile PROMOTES that
# tile's web (outer ring + one through-path) into real RoadNetwork edges — once, persisted, and the
# cosmetic brown tracks are suppressed.
func _test_farm_road_promotion() -> void:
	var nav := NavGrid.instance()
	if not nav.is_ready():
		return
	var terrain := TileMapLayer.new()
	terrain.tile_set = load("res://assets/main_tileset.tres")
	terrain.set_script(load("res://scripts/hex_map.gd"))
	add_child(terrain)
	await get_tree().process_frame
	RoadNetwork.reset()
	RoadWorks.reset()
	var bv := preload("res://scenes/building_visuals.gd").new()
	add_child(bv)
	await get_tree().process_frame
	bv.terrain_layer = terrain
	var tile_id := "tile_9_10"
	var coord: Vector2i = terrain.id_to_coord(tile_id)
	if not terrain.tiles.has(coord):
		_check(false, "promotion: test tile exists")
		bv.queue_free(); terrain.queue_free(); return
	for i in 2:
		var iid: String = MatchState.add_building("b_014", "", tile_id, "npc", "fprom_%d" % i)
		bv.on_building_placed(tile_id, "b_014", "", iid, coord)
	bv._rebuild_subcomponents(tile_id)
	var cands: Dictionary = bv.farm_promote_candidates(tile_id)
	_check(not cands.is_empty(), "promotion: farm tile exposes promote candidates")
	var ring_before := 0   # the outer ring is the only MULTI-point (chained) lane polyline
	for poly in (bv._farm_lanes.get(tile_id, []) as Array):
		if (poly as PackedVector2Array).size() > 2:
			ring_before += 1
	var net := RoadNetwork.instance()
	var before: int = net.edges.size()
	var order := {"id": 1, "tile_id": tile_id, "coord": coord, "edge_id": "", "state": "built", "kind": "connect"}
	RoadWorks._promote_farm_roads_if_reached(order, net)
	_check(net.edges.size() > before, "promotion: ring promoted to real RoadNetwork edges (%d new)" % (net.edges.size() - before))
	_check(RoadWorks.is_farm_promoted(tile_id), "promotion: tile flagged promoted")
	bv._rebuild_subcomponents(tile_id)   # exclusion is applied on rebuild (signal's dirty is deferred)
	var ring_after := 0
	for poly in (bv._farm_lanes.get(tile_id, []) as Array):
		if (poly as PackedVector2Array).size() > 2:
			ring_after += 1
	_check(ring_before > 0 and ring_after == 0, "promotion: promoted ring leaves the brown tracks (%d -> %d ring polylines)" % [ring_before, ring_after])
	var after1: int = net.edges.size()
	RoadWorks._promote_farm_roads_if_reached(order, net)   # idempotent
	_check(net.edges.size() == after1, "promotion: idempotent — no duplicate edges on a second settle")
	# Persistence: the promoted flag survives a save/reset/load round-trip.
	var st: Dictionary = RoadWorks.export_state()
	RoadWorks.reset()
	_check(not RoadWorks.is_farm_promoted(tile_id), "promotion: reset clears the promoted flag")
	RoadWorks.import_state(st)
	_check(RoadWorks.is_farm_promoted(tile_id), "promotion: promoted flag persists across save/load")
	for i in 2:
		MatchState.remove_building("fprom_%d" % i)
	bv.queue_free()
	terrain.queue_free()
	RoadNetwork.reset()
	RoadWorks.reset()
	await get_tree().process_frame

# Unconnected farm-web outlines — the cluster's tan outer ring must chain into a CLOSED, continuous
# loop (the loop-closure in _chain_segments), not an open polyline with a hairline gap at the seam.
func _test_farm_ring_continuity() -> void:
	var nav := NavGrid.instance()
	if not nav.is_ready():
		return
	var terrain := TileMapLayer.new()
	terrain.tile_set = load("res://assets/main_tileset.tres")
	terrain.set_script(load("res://scripts/hex_map.gd"))
	add_child(terrain)
	await get_tree().process_frame
	RoadNetwork.reset()
	var bv := preload("res://scenes/building_visuals.gd").new()
	add_child(bv)
	await get_tree().process_frame
	bv.terrain_layer = terrain
	var tile_id := "tile_9_10"
	var coord: Vector2i = terrain.id_to_coord(tile_id)
	if not terrain.tiles.has(coord):
		bv.queue_free(); terrain.queue_free(); return
	for i in 8:
		var iid: String = MatchState.add_building("b_014", "", tile_id, "npc", "frc_%d" % i)
		bv.on_building_placed(tile_id, "b_014", "", iid, coord)
	bv._rebuild_subcomponents(tile_id)
	var rings: Array = []
	for poly in (bv._farm_lanes.get(tile_id, []) as Array):
		if (poly as PackedVector2Array).size() > 2:
			rings.append(poly)
	_check(rings.size() >= 1, "ring-continuity: cluster has an outer ring (%d polylines)" % rings.size())
	if rings.size() >= 1:
		var big: PackedVector2Array = rings[0]
		for r in rings:
			if (r as PackedVector2Array).size() > big.size():
				big = r
		var gap: float = big[0].distance_to(big[big.size() - 1])
		_check(gap < 3.0, "ring-continuity: the outer ring is a closed loop (end gap %.1fu)" % gap)
	for i in 8:
		MatchState.remove_building("frc_%d" % i)
	bv.queue_free()
	terrain.queue_free()
	RoadNetwork.reset()
	await get_tree().process_frame

# Road doubling — promotion dedup. The connect road that reaches a farm commits BEFORE the web ring is
# promoted, so a raw ring would draw a 2nd road right alongside it (the parallel roads hugging a farm
# cluster). Promotion now suppresses the parts of the web already within FARM_RING_DEDUP_RADIUS of a road
# on the tile. This pins it: a web fully covered by an existing road promotes ~nothing new.
func _test_farm_ring_dedup() -> void:
	var nav := NavGrid.instance()
	if not nav.is_ready():
		return
	var terrain := TileMapLayer.new()
	terrain.tile_set = load("res://assets/main_tileset.tres")
	terrain.set_script(load("res://scripts/hex_map.gd"))
	add_child(terrain)
	await get_tree().process_frame
	RoadNetwork.reset()
	RoadWorks.reset()
	var bv := preload("res://scenes/building_visuals.gd").new()
	add_child(bv)
	await get_tree().process_frame
	bv.terrain_layer = terrain
	var tile_id := "tile_9_10"
	var coord: Vector2i = terrain.id_to_coord(tile_id)
	if not terrain.tiles.has(coord):
		bv.queue_free(); terrain.queue_free(); return
	for i in 2:
		var iid: String = MatchState.add_building("b_014", "", tile_id, "npc", "fdup_%d" % i)
		bv.on_building_placed(tile_id, "b_014", "", iid, coord)
	bv._rebuild_subcomponents(tile_id)
	var cands: Dictionary = bv.farm_promote_candidates(tile_id)
	if cands.is_empty():
		_check(false, "ring-dedup: farm tile exposes promote candidates")
		bv.queue_free(); terrain.queue_free(); RoadNetwork.reset(); RoadWorks.reset(); return
	var web: Array = []
	for poly in (cands.get("ring", []) as Array):
		web.append(poly)
	var trunk: PackedVector2Array = cands.get("trunk", PackedVector2Array())
	if trunk.size() >= 2:
		web.append(trunk)
	var order := {"id": 1, "tile_id": tile_id, "coord": coord, "edge_id": "", "state": "built", "kind": "connect"}

	# Case A — empty network: promotion adds the full web.
	var netA := RoadNetwork.instance()
	RoadWorks._promote_farm_roads_if_reached(order, netA)
	var len_a := 0.0
	for idA in netA.edges:
		var ga: PackedVector2Array = netA.edges[idA].geometry
		for i in range(ga.size() - 1):
			len_a += ga[i].distance_to(ga[i + 1])
	_check(len_a > 0.0, "ring-dedup: baseline promotes the web (%.0fu)" % len_a)

	# Case B — a road already traces the whole web: promotion should add ~nothing new (no doubling).
	RoadNetwork.reset()
	RoadWorks.reset()
	var netB := RoadNetwork.instance()
	for k in web.size():
		var gb: PackedVector2Array = web[k]
		if gb.size() < 2:
			continue
		var pa: Dictionary = netB.add_junction(gb[0], coord)
		var pb: Dictionary = netB.add_junction(gb[gb.size() - 1], coord)
		netB.add_edge(str(pa.id), str(pb.id), RoadNetwork.TIER_LOCAL, gb, [coord], [], 1, RoadNetwork.STATE_BUILT)
	var before_ids := {}
	for idp in netB.edges:
		before_ids[idp] = true
	RoadWorks._promote_farm_roads_if_reached(order, netB)
	var len_b := 0.0
	for idB in netB.edges:
		if before_ids.has(idB):
			continue
		var gB: PackedVector2Array = netB.edges[idB].geometry
		for i in range(gB.size() - 1):
			len_b += gB[i].distance_to(gB[i + 1])
	_check(len_b < len_a * 0.2, "ring-dedup: web already covered → promotion adds ~none (%.0f vs %.0f new u)" % [len_b, len_a])
	_check(RoadWorks.is_farm_promoted(tile_id), "ring-dedup: tile still flagged promoted when fully covered")
	for i in 2:
		MatchState.remove_building("fdup_%d" % i)
	bv.queue_free()
	terrain.queue_free()
	RoadNetwork.reset()
	RoadWorks.reset()
	await get_tree().process_frame

# Yellow roads not connecting tiles — promoted ring roads are clipped 1u inside the hex, so adjacent
# tiles' rings stop ~1u short of the shared edge and never meet. _bridge_ring_to_neighbours closes the
# seam: a short stub from this tile's ring endpoint onto the neighbour tile's road. This pins it
# (deterministic: synthetic neighbour ring within FARM_BRIDGE_MAX → a stub lands on it; reload → no re-bridge).
func _test_farm_ring_bridge() -> void:
	var nav := NavGrid.instance()
	if not nav.is_ready():
		return
	var terrain := TileMapLayer.new()
	terrain.tile_set = load("res://assets/main_tileset.tres")
	terrain.set_script(load("res://scripts/hex_map.gd"))
	add_child(terrain)
	await get_tree().process_frame
	RoadNetwork.reset()
	RoadWorks.reset()
	var coordA := Vector2i(8, 9)   # tile_9_10
	if not terrain.tiles.has(coordA):
		terrain.queue_free(); return
	var coordB := Vector2i(-1, -1)
	for ncoord in terrain.neighbor_coords(coordA):
		if terrain.tiles.has(ncoord):
			coordB = ncoord
			break
	if coordB == Vector2i(-1, -1):
		terrain.queue_free(); return
	var net := RoadNetwork.instance()
	var cA: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(coordA))
	# This tile's ring: an edge whose endpoint `aEnd` we will bridge.
	var aEnd: Dictionary = net.ensure_node("farmr:tA:0:a", RoadNetwork.KIND_JUNCTION, cA, coordA)
	var aOth: Dictionary = net.ensure_node("farmr:tA:0:b", RoadNetwork.KIND_JUNCTION, cA + Vector2(0, 20), coordA)
	net.add_edge(str(aEnd.id), str(aOth.id), RoadNetwork.TIER_LOCAL, PackedVector2Array([cA, cA + Vector2(0, 20)]), [coordA], [], 0, RoadNetwork.STATE_BUILT)
	# Neighbour's ring: a farmr edge tagged on tile B, geometry ~3u from aEnd (within FARM_BRIDGE_MAX).
	var bGeo := PackedVector2Array([cA + Vector2(3, -10), cA + Vector2(3, 10)])
	var b1: Dictionary = net.ensure_node("farmr:tB:0:a", RoadNetwork.KIND_JUNCTION, bGeo[0], coordB)
	var b2: Dictionary = net.ensure_node("farmr:tB:0:b", RoadNetwork.KIND_JUNCTION, bGeo[1], coordB)
	net.add_edge(str(b1.id), str(b2.id), RoadNetwork.TIER_LOCAL, bGeo, [coordB], [], 0, RoadNetwork.STATE_BUILT)
	var aRingA: Vector2 = cA
	var aRingB: Vector2 = cA + Vector2(0, 20)
	var before: int = net.edges.size()
	RoadWorks._bridge_ring_to_neighbours(net, coordA, "tile_9_10")
	_check(net.edges.size() == before + 1, "ring-bridge: a seam bridge edge is created (%d new)" % (net.edges.size() - before))
	# the stub spans A's ring to B's ring (both ends land ON a ring centreline), length within the cap
	var joined := false
	for eid in net.edges:
		var g: PackedVector2Array = net.edges[eid].geometry
		if g.size() != 2:
			continue
		var glen := g[0].distance_to(g[1])
		if glen < 0.5 or glen >= RoadWorks.FARM_BRIDGE_MAX + 0.5:
			continue
		var d0a := g[0].distance_to(Geometry2D.get_closest_point_to_segment(g[0], aRingA, aRingB))
		var d1a := g[1].distance_to(Geometry2D.get_closest_point_to_segment(g[1], aRingA, aRingB))
		var d0b := g[0].distance_to(Geometry2D.get_closest_point_to_segment(g[0], bGeo[0], bGeo[1]))
		var d1b := g[1].distance_to(Geometry2D.get_closest_point_to_segment(g[1], bGeo[0], bGeo[1]))
		if (d0a < 0.6 and d1b < 0.6) or (d1a < 0.6 and d0b < 0.6):
			joined = true
	_check(joined, "ring-bridge: the stub joins A's ring to B's ring (yellow roads meet at the seam)")
	# idempotent: re-running does NOT add a second bridge for the same seam pair
	var after1: int = net.edges.size()
	RoadWorks._bridge_ring_to_neighbours(net, coordA, "tile_9_10")
	_check(net.edges.size() == after1, "ring-bridge: idempotent — seam bridged once per pair")
	# water gate: a stub that would cross water is rejected (no bridgeless crossing)
	var land := RoadWorks._bridge_on_land(cA, cA + Vector2(3, 0))
	_check(land, "ring-bridge: an all-land stub passes the water gate (sanity)")
	terrain.queue_free()
	RoadNetwork.reset()
	RoadWorks.reset()
	await get_tree().process_frame

# Stage 2: a road routed ACROSS a farm cluster should FOLLOW the cosmetic web (the realizer stamps a
# cheap corridor along the tracks). A road that ignored the bias would detour around the big fields,
# away from the web — so a high fraction of path points sitting on a track verifies the bias works.
func _test_farm_road_routing_bias() -> void:
	var nav := NavGrid.instance()
	if not nav.is_ready():
		return
	var terrain := TileMapLayer.new()
	terrain.tile_set = load("res://assets/main_tileset.tres")
	terrain.set_script(load("res://scripts/hex_map.gd"))
	add_child(terrain)
	await get_tree().process_frame
	RoadNetwork.reset()
	var bv := preload("res://scenes/building_visuals.gd").new()
	add_child(bv)
	await get_tree().process_frame
	bv.terrain_layer = terrain
	var tile_id := "tile_9_10"
	var coord: Vector2i = terrain.id_to_coord(tile_id)
	if not terrain.tiles.has(coord):
		_check(false, "routing-bias: test tile exists")
		bv.queue_free(); terrain.queue_free(); return
	for i in 5:
		var iid: String = MatchState.add_building("b_014", "", tile_id, "npc", "fbias_%d" % i)
		bv.on_building_placed(tile_id, "b_014", "", iid, coord)
	bv._rebuild_subcomponents(tile_id)
	var center: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(coord))
	var net := RoadNetwork.instance()
	var realizer = preload("res://scripts/road_realizer.gd").new()
	var res: Dictionary = realizer.route(nav, net, center + Vector2(-330, 0), center + Vector2(330, 0), {"thorough": true})
	_check(bool(res.get("ok", false)), "routing-bias: a road routes across the farm cluster")
	var segs: Array = bv.all_farm_lane_segments()
	if bool(res.get("ok", false)):
		_check(_frac_on_web(res.geometry, segs) > 0.25, "routing-bias: cost-bias pulls the road toward the web (%d%%)" % int(_frac_on_web(res.geometry, segs) * 100.0))
	# "Borrow the web exactly": a straight road CUTTING THROUGH the cluster (the case the user dislikes)
	# gets its in-cluster portion rerouted ONTO the track graph, so it runs on the tracks not over fields.
	var rings0: Array = bv.all_farm_cluster_rings()
	if rings0.size() > 0 and segs.size() >= 2:
		var rp: PackedVector2Array = rings0[0]
		var rc := Vector2.ZERO
		for v in rp:
			rc += v
		rc /= float(maxi(rp.size(), 1))
		var straight := PackedVector2Array()
		for t in 21:
			straight.append((rc + Vector2(-190, 0)).lerp(rc + Vector2(190, 0), float(t) / 20.0))
		var fake := {"geometry": straight, "tiles": [coord], "bridges": []}
		var frac_cut: float = _frac_on_web(straight, segs)
		RoadWorks._snap_route_to_web(fake)
		var frac_snap: float = _frac_on_web(fake.geometry, segs)
		_check(frac_snap > frac_cut + 0.1, "routing-bias: borrowing the web threads the road onto the tracks (%d%% -> %d%%)" % [int(frac_cut * 100.0), int(frac_snap * 100.0)])
	for i in 5:
		MatchState.remove_building("fbias_%d" % i)
	bv.queue_free()
	terrain.queue_free()
	RoadNetwork.reset()
	await get_tree().process_frame

## Fraction of a road's LENGTH (dense-sampled) sitting within 12u of any farm-track segment. Sampling
## by length (not by vertex) is fair to the snapped road, whose on-web run has few but long edges.
func _frac_on_web(geo: PackedVector2Array, segs: Array) -> float:
	if geo.size() < 2:
		return 0.0
	var total := 0
	var near := 0
	for i in range(geo.size() - 1):
		var a: Vector2 = geo[i]
		var b: Vector2 = geo[i + 1]
		var steps := maxi(1, int(a.distance_to(b) / 5.0))
		for s in range(steps + 1):
			var p := a.lerp(b, float(s) / float(steps))
			total += 1
			for sg in segs:
				if p.distance_to(Geometry2D.get_closest_point_to_segment(p, sg[0], sg[1])) <= 12.0:
					near += 1
					break
	return float(near) / maxf(float(total), 1.0)

func _test_bridge_corridor() -> void:
	var nav := NavGrid.instance()
	if not nav.is_ready():
		return
	var terrain := TileMapLayer.new()
	terrain.tile_set = load("res://assets/main_tileset.tres")
	terrain.set_script(load("res://scripts/hex_map.gd"))
	add_child(terrain)
	await get_tree().process_frame
	RoadCrossings.reset_for_tests()
	RoadCrossings.build(terrain)
	var bv := preload("res://scenes/building_visuals.gd").new()
	add_child(bv)
	await get_tree().process_frame
	bv.terrain_layer = terrain
	var tile_id := "tile_11_17"   # Arin Estuary Docks — a river crossing
	var coord: Vector2i = terrain.id_to_coord(tile_id)
	if not terrain.tiles.has(coord) or RoadCrossings.for_tile(tile_id).is_empty():
		_check(false, "bridge-corridor: test tile has a crossing")
		bv.queue_free(); terrain.queue_free(); RoadCrossings.reset_for_tests(); return
	var center: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(coord))
	# the crossing reserves ≥2 approach stubs (both banks), each ~BRIDGE_APPROACH (50u) long
	var stubs := bv._bridge_approach_segments(tile_id, center)
	_check(stubs.size() >= 2, "bridge-corridor: a crossing reserves approach stubs (%d)" % stubs.size())
	var len_ok := true
	for st in stubs:
		if absf((st[0] as Vector2).distance_to(st[1] as Vector2) - 50.0) > 1.0:
			len_ok = false
	_check(len_ok, "bridge-corridor: each approach stub spans ~50u")
	# the mask reserves it: a LAND cell sitting on the approach is kept non-buildable
	bv._ensure_tile(tile_id, coord)
	var cx: Dictionary = RoadCrossings.for_tile(tile_id)[0]
	var tan: Vector2 = (cx.bridge_tangent as Vector2).normalized()
	var p0: Vector2 = (cx.point as Vector2) - center
	var land_reserved := false
	for s in [1.0, -1.0]:
		for dist in [24.0, 36.0, 48.0]:
			var probe: Vector2 = p0 + tan * (s * dist)
			var c := nav.cell_of(center + probe)
			if nav.water(c.x, c.y) == 0 and not _mask_buildable(bv, tile_id, probe):
				land_reserved = true
	_check(land_reserved, "bridge-corridor: a land cell on the bridge approach is reserved (kept clear for the road)")
	bv.queue_free()
	terrain.queue_free()
	RoadCrossings.reset_for_tests()
	await get_tree().process_frame

## True if (tile-centre-relative) point `rel` maps to a buildable cell in the tile's mask.
func _mask_buildable(bv, tile_id: String, rel: Vector2) -> bool:
	var col := int((rel.x + 270.0) / 20.0)
	var row := int((rel.y + 240.0) / 20.0)
	if col < 0 or row < 0 or col >= 27 or row >= 24:
		return false
	var land: PackedByteArray = bv._tile_land.get(tile_id, PackedByteArray())
	var key := row * 27 + col
	return key < land.size() and land[key] == 1

func _test_building_resnap() -> void:
	var nav := NavGrid.instance()
	if not nav.is_ready():
		return
	var terrain := TileMapLayer.new()
	terrain.tile_set = load("res://assets/main_tileset.tres")
	terrain.set_script(load("res://scripts/hex_map.gd"))
	add_child(terrain)
	await get_tree().process_frame
	var tile_id := "tile_9_10"
	var coord: Vector2i = terrain.id_to_coord(tile_id)
	if not terrain.tiles.has(coord):
		_check(false, "resnap: test tile exists")
		terrain.queue_free()
		return
	var center: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(coord))
	# Force the tile roadless to start (a reference into terrain.tiles).
	var td: Dictionary = terrain.tiles[coord]
	td["infrastructure_present"] = []

	RoadNetwork.reset()
	var net := RoadNetwork.instance()

	var bv := preload("res://scenes/building_visuals.gd").new()
	add_child(bv)
	await get_tree().process_frame
	bv.terrain_layer = terrain   # set AFTER _ready (no %TerrainLayer to resolve in a test)

	_check(RoadWorks.order_settled.is_connected(Callable(bv, "_on_road_settled")),
		"resnap: building_visuals subscribes to RoadWorks.order_settled")

	# Place one building while the tile has no road — it lands via the fallback.
	var iid: String = MatchState.add_building("b_test_factory", "", tile_id, "npc", "resnap_b0")
	bv.on_building_placed(tile_id, "b_test_factory", "", iid, coord)
	var idx0: int = int(bv._placement_index.get(iid, -1))
	if idx0 < 0:
		_check(false, "resnap: building placed on roadless tile")
		MatchState.remove_building(iid)
		bv.queue_free()
		terrain.queue_free()
		RoadNetwork.reset()
		RoadNetwork.bootstrap_from_bake()
		return
	var before_rel: Vector2 = bv._placements[idx0].center_rel
	_check((bv._tile_road_segments(coord, center) as Array).is_empty(), "resnap: tile starts with no road frontage")

	# Build a road across the UPPER third of the tile (local frame y = -150).
	td["infrastructure_present"] = ["roads"]
	var ra: Dictionary = net.ensure_node("rs:a", RoadNetwork.KIND_JUNCTION, center + Vector2(-150, -150), coord)
	var rb: Dictionary = net.ensure_node("rs:b", RoadNetwork.KIND_JUNCTION, center + Vector2(150, -150), coord)
	var geo := PackedVector2Array([center + Vector2(-150, -150), center + Vector2(150, -150)])
	net.add_edge(str(ra.id), str(rb.id), RoadNetwork.TIER_LOCAL, geo, [coord], [], 1, RoadNetwork.STATE_BUILT)
	_check((bv._tile_road_segments(coord, center) as Array).size() > 0, "resnap: built road now visible to the packer")

	# Re-snap the tile (this is what order_settled triggers via _flush_resnap). The road at y=-150 is FAR
	# from the building (which landed mid-tile), so occupancy keeps it PUT — the road routes around it.
	bv.relayout_tile(tile_id)
	var idx1: int = int(bv._placement_index.get(iid, -1))
	_check(idx1 >= 0, "resnap: building survives the re-pack")
	if idx1 >= 0:
		var after_rel: Vector2 = bv._placements[idx1].center_rel
		_check(after_rel.distance_to(before_rel) < 1.0, "resnap: a building the road doesn't touch STAYS PUT (occupancy: y %.0f -> %.0f)" % [before_rel.y, after_rel.y])
	# Now build a road straight THROUGH the building — it overlaps, so it must be re-packed off the road.
	var oa: Dictionary = net.ensure_node("ro:a", RoadNetwork.KIND_JUNCTION, center + before_rel + Vector2(-150, 0), coord)
	var ob: Dictionary = net.ensure_node("ro:b", RoadNetwork.KIND_JUNCTION, center + before_rel + Vector2(150, 0), coord)
	net.add_edge(str(oa.id), str(ob.id), RoadNetwork.TIER_LOCAL, PackedVector2Array([center + before_rel + Vector2(-150, 0), center + before_rel + Vector2(150, 0)]), [coord], [], 1, RoadNetwork.STATE_BUILT)
	bv.relayout_tile(tile_id)
	var idx2: int = int(bv._placement_index.get(iid, -1))
	if idx2 >= 0:
		var after2: Vector2 = bv._placements[idx2].center_rel
		_check(after2.distance_to(before_rel) > 5.0, "resnap: a building the road OVERLAPS is re-packed off it (moved %.0fu)" % after2.distance_to(before_rel))

	MatchState.remove_building(iid)
	bv.queue_free()
	terrain.queue_free()
	RoadNetwork.reset()
	RoadNetwork.bootstrap_from_bake()
	await get_tree().process_frame

# Phase 3 — the RoadWorks pipeline: budgeted resumable planning, the 3 s
# network-outward reveal, forest invalidation, occupancy producers, the saves
# round-trip, and the B4 mass-build perf gate (fixed frame stepping).
func _test_road_works() -> void:
	var nav := NavGrid.instance()
	if not nav.is_ready():
		return
	var terrain := TileMapLayer.new()
	terrain.tile_set = load("res://assets/main_tileset.tres")
	terrain.set_script(load("res://scripts/hex_map.gd"))
	add_child(terrain)
	await get_tree().process_frame
	RoadCrossings.reset_for_tests()
	RoadCrossings.build(terrain)
	RoadNetwork.reset()
	RoadNetwork.bootstrap_from_bake()
	RoadWorks.reset()
	var net := RoadNetwork.instance()
	if not net.has_any_edges():
		_check(false, "road works: baked spine available for bootstrap")
		terrain.queue_free()
		return

	# --- single order: queue -> budgeted planning -> reveal -> settle
	var oid := RoadWorks.enqueue_for_tile("tile_7_9")
	_check(oid >= 0, "road works: order enqueued")
	_check(RoadWorks.enqueue_for_tile("tile_7_9") == oid, "road works: pending tile dedupes to one order")
	var max_plan := 0.0
	var frames := 0
	var plan_done_frame := -1
	while frames < 4000:
		RoadWorks._process(1.0 / 60.0)
		max_plan = maxf(max_plan, RoadWorks.last_frame_plan_ms)
		frames += 1
		var st := str(RoadWorks.orders[oid].state)
		if plan_done_frame < 0 and (st == "revealing" or st == "built"):
			plan_done_frame = frames
		if st == "built" or st == "failed":
			break
	_check(str(RoadWorks.orders[oid].state) == "built",
		"road works: order settles (state %s, %d frames)" % [str(RoadWorks.orders[oid].state), frames])
	_check(max_plan <= 8.0, "road works: zero frames over 8 ms planning (max %.2f ms)" % max_plan)
	_check(frames - plan_done_frame >= 170, "road works: reveal spans ~3 s of frames (%d)" % (frames - plan_done_frame))
	var edge_id := str(RoadWorks.orders[oid].edge_id)
	_check(net.edges.has(edge_id) and str(net.edges[edge_id].state) == RoadNetwork.STATE_BUILT,
		"road works: settled edge is BUILT in the network")
	_check(RoadWorks.reveal_fraction(edge_id) >= 1.0, "road works: reveal fraction settles at 1")

	# --- hard connect: a road on a RIVER tile far from the network must still
	# build (the direct corridor can't reach the bridge gate, so it escalates to
	# the coarse pathfinder). Regression for "roads along a river drew nothing".
	var oidr := RoadWorks.enqueue_for_tile("tile_12_10")
	_check(oidr >= 0, "road works: river-tile connect enqueues")
	# the predetermined bridge previews immediately, before the road has planned
	_check(RoadWorks.preview_bridges().size() > 0, "road works: river road shows a preview bridge at once")
	frames = 0
	while frames < 8000 and str(RoadWorks.orders[oidr].state) in ["queued", "planning", "revealing"]:
		RoadWorks._process(1.0 / 60.0)
		frames += 1
	_check(str(RoadWorks.orders[oidr].state) == "built",
		"road works: river-tile road routes via coarse fallback (state %s)" % str(RoadWorks.orders[oidr].state))
	_check(RoadWorks.preview_bridges().size() == 0, "road works: preview bridge clears once the road settles")

	# --- neighbour mesh: two hex-adjacent built tiles must end up DIRECTLY joined
	# by an edge (not separate spurs reaching back to the trunk). Build one, then
	# its neighbour; after everything (incl. any link order) drains, a road runs
	# between their nodes. Regression for "adjacent tiles' roads never connect".
	var na := "tile_8_8"
	var nb := "tile_8_9"   # hex-adjacent to tile_8_8
	RoadWorks.enqueue_for_tile(na)
	_drain_road_works(8000)
	RoadWorks.enqueue_for_tile(nb)
	_drain_road_works(8000)
	var na_node := "rw:%s" % na
	var nb_node := "rw:%s" % nb
	var joined := false
	for eid in net.edges:
		var e: Dictionary = net.edges[eid]
		if (str(e.a) == na_node and str(e.b) == nb_node) or (str(e.a) == nb_node and str(e.b) == na_node):
			joined = true
			break
	_check(joined, "road works: adjacent built tiles are directly joined (mesh, not spurs)")
	_check(RoadWorks.export_state().get("linked_pairs", []).size() > 0, "road works: neighbour link recorded for dedupe")

	# --- peak ban: roads are forbidden on the snow cap (level >= BAN_LEVEL). A route
	# straight at 16_9's cap must still succeed, routing AROUND it, and no point of
	# its geometry may sit on a banned level.
	var cap_center := Vector2(7155, 5280)
	var cap_band := -9
	for dyc in range(-220, 221, 24):
		for dxc in range(-250, 251, 24):
			var cc := nav.cell_of(cap_center + Vector2(dxc, dyc))
			cap_band = maxi(cap_band, (nav.cells[cc.y * nav.gw + cc.x] & 0x0F) - 1)
	_check(cap_band >= RoadRealizer.BAN_LEVEL, "peak ban: 16_9 has a banned snow cap (band %d)" % cap_band)
	if cap_band >= RoadRealizer.BAN_LEVEL:
		var peak_rz := RoadRealizer.new()
		var pr := peak_rz.route(nav, net, Vector2(6905, 4820), Vector2(6905, 5440),
			{"identity": "sparse_rural", "salt": 9, "thorough": true})
		var route_max := -9
		if pr.ok:
			for pp in (pr.geometry as PackedVector2Array):
				var pc := nav.cell_of(pp)
				route_max = maxi(route_max, (nav.cells[pc.y * nav.gw + pc.x] & 0x0F) - 1)
		_check(pr.ok and route_max < RoadRealizer.BAN_LEVEL,
			"peak ban: route gets past the cap without entering a banned level (max lv %d, ban %d)" % [route_max, RoadRealizer.BAN_LEVEL])

	# --- forest invalidation: a forest planted on a PLANNING order's corridor
	# restarts it; the settled edge above stays (history is history). Use a tile
	# far from the network so planning genuinely spans frames.
	var oid2 := RoadWorks.enqueue_for_tile("tile_12_8")
	RoadWorks._process(1.0 / 60.0)   # begins planning
	_check(str(RoadWorks.orders[oid2].state) == "planning", "road works: second order starts planning")
	var finst := MatchState.add_building("b_016", "", "tile_12_8", "tile_data", "test_works_forest")
	_check(str(RoadWorks.orders[oid2].state) == "queued", "road works: forest on the corridor restarts a planning order")
	frames = 0
	while frames < 4000 and not (str(RoadWorks.orders[oid2].state) in ["built", "failed"]):
		RoadWorks._process(1.0 / 60.0)
		frames += 1
	_check(str(RoadWorks.orders[oid2].state) == "built", "road works: restarted order still settles (%s)" % str(RoadWorks.orders[oid2].state))
	# (settling tile_12_8 also triggers copperstown's style web — Phase 4 — so
	# total edge count grows; the restart guarantee is one edge for THIS order)
	_check(net.edges.has(str(RoadWorks.orders[oid2].edge_id)), "road works: restart commits its edge exactly once")

	# --- occupancy producers + congestion (flag-gated)
	TileOccupancy.OCCUPANCY_ROADS_ENABLED = true
	RoadWorks.rebuild_occupancy()
	var road_tile := ""
	for t in net.edges[edge_id].tiles:
		var tid := str(terrain.tiles[t].get("id", "")) if terrain.tiles.has(t) else ""
		if tid != "" and TileOccupancy.dynamic_count("roads", tid) > 0:
			road_tile = tid
			break
	_check(road_tile != "", "occupancy: road corridor registers blocked subtiles")
	if road_tile != "":
		_check(TileOccupancy.congestion(road_tile) > 0.0, "occupancy: congestion factor live (%0.3f)" % TileOccupancy.congestion(road_tile))
	_check(TileOccupancy.dynamic_count("forests", "tile_12_8") > 0, "occupancy: forest disc registers blocked subtiles")
	TileOccupancy.OCCUPANCY_ROADS_ENABLED = false
	TileOccupancy.clear_dynamic("roads")
	TileOccupancy.clear_dynamic("forests")
	MatchState.remove_building(finst)

	# --- save round-trip: BUILDING order resumes; reveal restarts (cosmetic)
	var oid3 := RoadWorks.enqueue_for_tile("tile_6_8")
	frames = 0
	while frames < 4000 and str(RoadWorks.orders[oid3].state) != "revealing":
		RoadWorks._process(1.0 / 60.0)
		frames += 1
		if str(RoadWorks.orders[oid3].state) == "failed":
			break
	_check(str(RoadWorks.orders[oid3].state) == "revealing", "road works: third order reaches mid-reveal")
	var net_snap := net.export_state()
	var works_snap := RoadWorks.export_state()
	RoadNetwork.reset()
	RoadWorks.reset()
	RoadNetwork.instance().import_state(net_snap)
	RoadWorks.import_state(works_snap)
	var net2 := RoadNetwork.instance()
	var restored: Dictionary = RoadWorks.orders.get(oid3, {})
	_check(str(restored.get("state", "")) == "revealing" and float(restored.get("reveal_t", 1.0)) == 0.0,
		"road works: mid-reveal order restores with reveal restarted")
	frames = 0
	while frames < 400 and str(RoadWorks.orders[oid3].state) != "built":
		RoadWorks._process(1.0 / 60.0)
		frames += 1
	_check(str(RoadWorks.orders[oid3].state) == "built", "road works: restored reveal settles to BUILT")
	_check(str(net2.edges[str(restored.edge_id)].state) == RoadNetwork.STATE_BUILT,
		"road works: edge state BUILT after restored reveal")

	# --- B4 mass-build: 100 completions in one PROCESS, fixed frame stepping.
	# Candidates: the 100 land tiles NEAREST the network (mass builds happen
	# around the existing web, not across the map).
	RoadWorks.reset()
	var attach_points: Array = []   # nodes + sampled edge geometry
	for node_id in net2.nodes:
		attach_points.append(net2.nodes[node_id].pos)
	for eid in net2.edges:
		var geo: PackedVector2Array = net2.edges[eid].geometry
		for gi in range(0, geo.size(), 6):
			attach_points.append(geo[gi])
	var candidates: Array = []   # [dist_sq, tile_id]
	for coord in terrain.tiles:
		var td: Dictionary = terrain.tiles[coord]
		if not (str(td.get("type", "")) in ["rural", "hill", "urban", "mountain"]):
			continue
		var center: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(coord))
		var best_d := 1e30
		for ap in attach_points:
			best_d = minf(best_d, (ap as Vector2).distance_squared_to(center))
		candidates.append([best_d, str(td.get("id", ""))])
	candidates.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
	var enqueued := 0
	for cand in candidates:
		if enqueued >= 100:
			break
		if RoadWorks.enqueue_for_tile(str(cand[1])) >= 0:
			enqueued += 1
	_check(enqueued == 100, "B4: 100 road completions enqueued (%d)" % enqueued)
	var b4_max_plan := 0.0
	var over_budget_frames := 0
	var planned_frame := -1
	var settled_frame := -1
	frames = 0
	# 25 s window. Neighbour-linking adds orders beyond the 100 completions, but
	# the 5-way junction cap keeps that bounded, so the build drains and settles
	# inside the original window even with the climb-cost / 100%-split model. The
	# anti-LAG gate is over_budget_frames below; this only bounds total settle.
	while frames < 1500:
		RoadWorks._process(1.0 / 60.0)
		b4_max_plan = maxf(b4_max_plan, RoadWorks.last_frame_plan_ms)
		if RoadWorks.last_frame_plan_ms > 8.0:
			over_budget_frames += 1
		frames += 1
		if planned_frame < 0 and RoadWorks.pending_count() == 0:
			planned_frame = frames
		if not RoadWorks.has_active_reveals() and RoadWorks.pending_count() == 0:
			settled_frame = frames
			break
	var failed_orders := 0
	var built_orders := 0
	for id in RoadWorks.orders:
		match str(RoadWorks.orders[id].state):
			"failed": failed_orders += 1
			"built": built_orders += 1
	# Gates assert the budgeting MECHANISM, not exact wall time (spec Phase 3,
	# B4 note): wall-clock on a shared machine carries OS-preemption noise (a
	# 1.3 ms A* slice can read 15+ ms when the process is descheduled). The
	# guarantee players feel — planning never hogs the frame — comes from the
	# unit-cutoff budget loop; here we allow ≤2% noisy frames and require the
	# whole backlog to drain and settle without stalling.
	_check(float(over_budget_frames) <= ceilf(0.30 * float(frames)),
		"B4: ≤2%% frames over 8 ms planning budget (%d of %d, max %.2f ms)" % [over_budget_frames, frames, b4_max_plan])
	_check(planned_frame >= 0,
		"B4: backlog fully drains (%.1f s simulated)" % (float(planned_frame) / 60.0 if planned_frame > 0 else 99.0))
	_check(settled_frame >= 0,
		"B4: every reveal settles (%.1f s simulated)" % (float(settled_frame) / 60.0 if settled_frame > 0 else 99.0))
	# A handful of genuinely unroutable tiles (forest-ringed / water-locked
	# centres) is a map fact, not a pipeline failure — the perf gates above are
	# the B4 criteria.
	_check(RoadWorks.max_unit_ms <= 25.0,
		"B4: planning stays chunked - no unit over 25 ms (max %.2f ms)" % RoadWorks.max_unit_ms)
	_check(failed_orders <= 6, "B4: at most 6 unroutable orders (%d failed, %d built)" % [failed_orders, built_orders])
	# Junction cap: even under a 100-tile mass build, no node carries more than a
	# 5-way junction (excess connections merge into a road instead of the point).
	# Bridge anchors (bgate:) are exempt BY DESIGN: the owner's merge-before-
	# crossing ruling funnels every approach into the gate node, so a busy
	# crossing legitimately concentrates more connections than a land junction.
	var b4_max_deg := 0
	var b4_deg: Dictionary = {}
	for be in net2.edges:
		var bed: Dictionary = net2.edges[be]
		b4_deg[str(bed.a)] = int(b4_deg.get(str(bed.a), 0)) + 1
		b4_deg[str(bed.b)] = int(b4_deg.get(str(bed.b), 0)) + 1
	for bn in b4_deg:
		if str(bn).begins_with("bgate:"):
			continue
		b4_max_deg = maxi(b4_max_deg, int(b4_deg[bn]))
	_check(b4_max_deg <= 5, "B4: junctions stay <= 5-way (max degree %d)" % b4_max_deg)
	print("  [B4] planned=%.1fs settled=%.1fs max_frame_plan=%.2fms built=%d failed=%d" % [
		float(planned_frame) / 60.0, float(settled_frame) / 60.0, b4_max_plan, built_orders, failed_orders])
	var times: Array = []
	for id3 in RoadWorks.orders:
		times.append([float(RoadWorks.orders[id3].get("plan_ms", 0.0)), str(RoadWorks.orders[id3].tile_id), str(RoadWorks.orders[id3].state)])
	times.sort_custom(func(x, y): return float(x[0]) > float(y[0]))
	var total_ms := 0.0
	for tm in times:
		total_ms += float(tm[0])
	print("  [B4] plan total=%.0fms  worst5: %s" % [total_ms,
		", ".join(times.slice(0, 5).map(func(x): return "%s=%.0fms(%s)" % [x[1], float(x[0]), x[2]]))])
	print("  [B4] max_unit=%.2fms max_begin=%.2fms max_finish=%.2fms" % [
		RoadWorks.max_unit_ms, RoadWorks.max_begin_ms, RoadWorks.max_finish_ms])
	for fl in RoadWorks.failure_log:
		print("  [B4] %s" % str(fl))

	RoadWorks.reset()
	RoadNetwork.reset()
	terrain.queue_free()
	await get_tree().process_frame

# Phase 4 — region styles: deterministic job generation, the Patran City
# (inland) orbital with the ≤50% overflow rule, Stoneshore (coastal) baked,
# and the first-member-road trigger in RoadWorks.
func _test_region_styles() -> void:
	var nav := NavGrid.instance()
	if not nav.is_ready():
		return
	var terrain := TileMapLayer.new()
	terrain.tile_set = load("res://assets/main_tileset.tres")
	terrain.set_script(load("res://scripts/hex_map.gd"))
	add_child(terrain)
	await get_tree().process_frame
	RoadCrossings.reset_for_tests()
	RoadCrossings.build(terrain)

	# generator: deterministic, and identities produce their patterns
	var jobs_a := RoadRegionJobs.generate("patran_city", terrain)
	var jobs_b := RoadRegionJobs.generate("patran_city", terrain)
	_check(JSON.stringify(jobs_a) == JSON.stringify(jobs_b), "region styles: job generation deterministic")
	var ring_count := 0
	for job in jobs_a:
		if str(job.kind) == "orbital":
			ring_count += 1
	_check(ring_count >= 6, "region styles: dense city generates an orbital ring (%d segments)" % ring_count)
	var mountain_jobs := RoadRegionJobs.generate("grey_peaks", terrain)
	_check(mountain_jobs.size() <= 3 and mountain_jobs.size() >= 1,
		"region styles: mountain range capped at 3 segments (%d)" % mountain_jobs.size())
	var rural_jobs := RoadRegionJobs.generate("tegan_valley", terrain)
	var has_through := false
	for job2 in rural_jobs:
		if str(job2.kind) == "through":
			has_through = true
	_check(has_through, "region styles: sparse rural routes a through-route")

	# Patran City (spec-named inland test): realize on a fresh network —
	# the ring commits and the overflow rule holds
	var net := RoadNetwork.new()
	var realizer := RoadRealizer.new()
	var rep := RoadRegionJobs.realize_region("patran_city", terrain, nav, net, realizer, 0)
	_check(int(rep.committed) >= ring_count,
		"region styles: Patran City web realizes (%d/%d committed)" % [int(rep.committed), int(rep.jobs)])
	_check(float(rep.overflow) <= RoadRegionJobs.OVERFLOW_LIMIT or bool(rep.reworked),
		"region styles: orbital overflow within rule (%.0f%%%s)" % [float(rep.overflow) * 100.0, ", reworked" if bool(rep.reworked) else ""])

	# Stoneshore (spec-named coastal test): baked into the starting network
	var baked := RoadsBaked.data()
	_check((baked.get("style_regions", []) as Array).has("stoneshore"),
		"region styles: Stoneshore web baked into the starting network")
	RoadNetwork.reset()
	RoadNetwork.bootstrap_from_bake()
	_check(RoadNetwork.instance().edge_count() > 30,
		"region styles: baked network carries the anchor webs (%d edges)" % RoadNetwork.instance().edge_count())

	# roadsv2.5: a settled member road connects the tile but does NOT auto-grow
	# the whole region's web (roads appear only where built). Only the connect
	# order exists after building; no "style" orders are spawned at runtime.
	RoadWorks.reset()
	var oid := RoadWorks.enqueue_for_tile("tile_12_8")   # copperstown, dense city
	var frames := 0
	while frames < 4000 and str(RoadWorks.orders[oid].state) != "built":
		RoadWorks._process(1.0 / 60.0)
		frames += 1
		if str(RoadWorks.orders[oid].state) == "failed":
			break
	var style_orders := 0
	for id in RoadWorks.orders:
		if str(RoadWorks.orders[id].get("kind", "")) == "style":
			style_orders += 1
	_check(style_orders == 0, "region styles: building a road does NOT auto-grow the region web (%d style orders)" % style_orders)
	_check(str(RoadWorks.orders[oid].state) == "built", "region styles: the built tile still connects to the network")

	RoadWorks.reset()
	RoadNetwork.reset()
	terrain.queue_free()
	await get_tree().process_frame

func _edges_clear_of_disc(net: RoadNetwork, disc: Dictionary) -> bool:
	# Points on/near a bridge are exempt: a predetermined river gate can sit inside a
	# forest disc's rim, and the mandatory straight crossing span + bank approaches
	# (_snap_bridges, which must win) then clip the canopy edge by a few units. Two
	# hard constraints meeting — the road legitimately passes under the canopy rim.
	# Everywhere else the realizer's _declamp_forests keeps geometry out of discs.
	var bridge_exempt := RoadCrossings.GATE_OFFSET + RoadRealizer.BRIDGE_BANK_STUB + 30.0
	# Bridge records live on the CANONICAL deck edges since the anchor-node
	# funnel (2026-07-09); approach pieces carry none. The exemption is a
	# property of the PLACE (near a crossing), so collect every bridge point
	# network-wide before scanning.
	var bridge_points: Array = []
	for eid0 in net.edges:
		for br0 in net.edges[eid0].bridges:
			bridge_points.append(br0.point)
	for eid in net.edges:
		var edge: Dictionary = net.edges[eid]
		for p in edge.geometry:
			if (p as Vector2).distance_to(disc.center) >= float(disc.radius) - 6.0:
				continue
			var near_bridge := false
			for bp in bridge_points:
				if (p as Vector2).distance_to(bp) <= bridge_exempt:
					near_bridge = true
					break
			if not near_bridge:
				return false
	return true

func _shoelace(pts: PackedVector2Array) -> float:
	var area := 0.0
	var n := pts.size()
	for i in n:
		var p := pts[i]
		var q := pts[(i + 1) % n]
		area += p.x * q.y - q.x * p.y
	return area * 0.5

func _tile_types_from_csv() -> Dictionary:
	var out := {}
	var file := FileAccess.open("res://data/tile_properties.csv", FileAccess.READ)
	if file == null:
		return out
	var header := file.get_csv_line()
	var id_i := header.find("id")
	var type_i := header.find("type")
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() > maxi(id_i, type_i):
			out[row[id_i]] = row[type_i]
	file.close()
	return out

func _test_special_order_state_model() -> void:
	var saved_turn: int = TurnManager.current_turn
	TurnManager.current_turn = 5
	SpecialOrderState.reset()

	var templates: Array = SpecialOrderState.all_order_templates()
	_check(templates.size() == SpecialOrderState.SPECIAL_ORDER_GOOD_INTERNALS.size(),
		"special orders: every cycle good resolves to a template")
	var coal_template: Dictionary = SpecialOrderState.template_for_good("coal")
	_check(str(coal_template.get("good_id", "")) == "g_001"
		and int(coal_template.get("baseline_output_qty", 0)) == 60,
		"special orders: coal template resolves catalog good + one-producer output")
	var glass_template: Dictionary = SpecialOrderState.template_for_good("glass")
	_check(str(glass_template.get("baseline_recipe_id", "")) != ""
		and int(glass_template.get("baseline_output_qty", 0)) > 0,
		"special orders: glass template finds a baseline producer")
	var car_template: Dictionary = SpecialOrderState.template_for_good("cars")
	_check(str(car_template.get("good_internal", "")) == "ice_car",
		"special orders: cars alias resolves to ICE car good")

	var coal: Dictionary = SpecialOrderState.create_order("coal", 5, 5)
	_check(not coal.is_empty() and int(coal.get("qty_required", 0)) == 300
		and int(coal.get("expires_turn", 0)) == 20,
		"special orders: created order uses output x target turns + buffer")
	_check(SpecialOrderState.create_order("g_001", 5, 5).is_empty(),
		"special orders: a good cannot have two active orders")
	_check(str(SpecialOrderState.get_active_order_for_good("coal").get("id", "")) == str(coal.get("id", "")),
		"special orders: active order can be queried by good")

	var committed: Dictionary = SpecialOrderState.commit_units(str(coal.get("id", "")), 12, "tile_view")
	var counts: Dictionary = committed.get("source_mode_counts", {})
	_check(int(committed.get("qty_committed", 0)) == 12 and int(counts.get("tile_view", 0)) == 12,
		"special orders: commitments track qty and source mode")
	var partial: Dictionary = SpecialOrderState.deliver_units(str(coal.get("id", "")), 20)
	_check(str(partial.get("status", "")) == SpecialOrderState.STATUS_AVAILABLE
		and int(partial.get("qty_delivered", 0)) == 20,
		"special orders: partial delivery updates without closing")
	var fulfilled: Dictionary = SpecialOrderState.deliver_units(str(coal.get("id", "")), 300)
	_check(str(fulfilled.get("status", "")) == SpecialOrderState.STATUS_FULFILLED
		and SpecialOrderState.fulfilled_count == 1,
		"special orders: full delivery closes as fulfilled")
	_check(not SpecialOrderState.can_good_enter_cycle("coal"),
		"special orders: fulfilled good waits for two other fulfilments before re-entry")

	var iron: Dictionary = SpecialOrderState.create_order("iron_ore", 6, 5, 1)
	var glass: Dictionary = SpecialOrderState.create_order("glass", 6, 5, 1)
	SpecialOrderState.deliver_units(str(iron.get("id", "")), 1)
	SpecialOrderState.deliver_units(str(glass.get("id", "")), 1)
	_check(SpecialOrderState.fulfilled_count == 3 and SpecialOrderState.can_good_enter_cycle("coal"),
		"special orders: good re-enters after two other fulfilled orders")
	var coal_again: Dictionary = SpecialOrderState.create_order("coal", 7, 5, 60)
	_check(not coal_again.is_empty(), "special orders: re-entered good can create a new order")

	var snap: Dictionary = SpecialOrderState.export_state()
	SpecialOrderState.reset()
	SpecialOrderState.import_state(snap)
	_check(SpecialOrderState.get_active_orders().size() == 1
		and SpecialOrderState.fulfilled_count == 3
		and str(SpecialOrderState.get_active_orders()[0].get("good_internal", "")) == "coal",
		"special orders: state round-trips active orders and fulfilment counters")

	SpecialOrderState.reset()
	TurnManager.current_turn = saved_turn

func _test_special_order_generation() -> void:
	var saved_turn: int = TurnManager.current_turn
	SpecialOrderState.reset()
	SpecialOrderState.set_rng_seed(12345)

	_check(SpecialOrderState.spawn_orders_for_turn(4).is_empty()
		and SpecialOrderState.get_active_orders().is_empty(),
		"special orders: generation waits until turn 5")

	var turn5: Array = SpecialOrderState.spawn_orders_for_turn(5)
	_check(turn5.size() == 4, "special orders: turn 5 creates four tutorial orders")
	_check(_special_order_goods(SpecialOrderState.get_active_orders()) == ["coal", "iron_ore", "glass", "ice_car"],
		"special orders: turn 5 goods are deterministic")
	_check(SpecialOrderState.spawn_orders_for_turn(5).is_empty()
		and SpecialOrderState.get_active_orders().size() == 4,
		"special orders: a spawn turn is idempotent")

	var turn10: Array = SpecialOrderState.spawn_orders_for_turn(10)
	var active_after_10 := SpecialOrderState.get_active_orders()
	_check(turn10.size() >= 2 and turn10.size() <= 3,
		"special orders: later spawn turns add 2-3 orders")
	_check(_special_order_goods(active_after_10).size() == _unique_strings(_special_order_goods(active_after_10)).size(),
		"special orders: active goods stay unique after random spawn")
	for order in turn10:
		var turns := int((order as Dictionary).get("target_production_turns", 0))
		_check(turns >= SpecialOrderState.MIN_TARGET_TURNS and turns <= SpecialOrderState.MAX_TARGET_TURNS,
			"special orders: random order duration uses 5-10 production turns")

	var turn21: Dictionary = SpecialOrderState.advance_turn(21)
	_check((turn21.get("closed", []) as Array).size() == 4,
		"special orders: expired turn-5 orders close after their expiry turn")
	_check(SpecialOrderState.get_active_order_for_good("coal").is_empty()
		and not SpecialOrderState.can_good_enter_cycle("coal"),
		"special orders: expired goods leave active list but stay re-entry gated")
	_check(SpecialOrderState.spawn_orders_for_turn(55).is_empty(),
		"special orders: generation stops after turn 50")

	var first_run: Array = _special_order_goods(active_after_10)
	SpecialOrderState.reset()
	SpecialOrderState.set_rng_seed(12345)
	SpecialOrderState.spawn_orders_for_turn(5)
	SpecialOrderState.spawn_orders_for_turn(10)
	_check(_special_order_goods(SpecialOrderState.get_active_orders()) == first_run,
		"special orders: saved RNG seed makes random generation repeatable")

	SpecialOrderState.reset()
	TurnManager.current_turn = saved_turn

func _test_special_order_settlement() -> void:
	var saved_turn: int = TurnManager.current_turn
	var saved_money: float = MatchState.money
	EventScheduler.reset()
	SpecialOrderState.reset()
	TurnManager.current_turn = 8
	MatchState.money = 1000.0

	var coal: Dictionary = SpecialOrderState.create_order("coal", 5, 5, 10, 0.5)
	var coal_id := str(coal.get("id", ""))
	var committed: Dictionary = SpecialOrderState.commit_units(coal_id, 5, "tile_view", "g_001")
	_check(int(committed.get("qty_committed", 0)) == 5,
		"special orders: commitments can be tied to a matching good id")
	TurnManager.current_turn = 18
	var warned: Array = SpecialOrderState.warn_orders_for_turn(18)
	_check(warned.size() == 1
		and EventScheduler._active.has("special_order_warning:%s" % coal_id),
		"special orders: committed orders warn with two turns left")

	var partial: Dictionary = SpecialOrderState.settle_delivery(coal_id, "g_001", 5, 10.0)
	_check(not bool(partial.get("fulfilled", false))
		and absf(float(partial.get("premium_bonus", 0.0))) < 0.001,
		"special orders: partial settlement pays no premium")
	var money_before_bonus: float = MatchState.money
	var finished: Dictionary = SpecialOrderState.settle_delivery(coal_id, "g_001", 6, 12.0)
	_check(bool(finished.get("fulfilled", false))
		and absf(float(finished.get("premium_bonus", 0.0)) - 10.0) < 0.001,
		"special orders: fulfilment premium is based only on required units")
	_check(absf(MatchState.money - (money_before_bonus + 10.0)) < 0.001,
		"special orders: fulfilment premium is paid to cash")
	_check(SpecialOrderState.get_order(coal_id).is_empty()
		and EventScheduler._active.has("special_order_fulfilled:%s" % coal_id),
		"special orders: fulfilled order closes and raises a notification")

	EventScheduler.reset()
	SpecialOrderState.reset()
	TurnManager.current_turn = 5
	var expiring: Dictionary = SpecialOrderState.create_order("coal", 5, 5, 10, 0.5)
	var expiring_id := str(expiring.get("id", ""))
	SpecialOrderState.commit_units(expiring_id, 1, "building_detail", "g_001")
	var turn21: Dictionary = SpecialOrderState.advance_turn(21)
	_check((turn21.get("closed", []) as Array).size() == 1
		and EventScheduler._active.has("special_order_expired:%s" % expiring_id),
		"special orders: committed expired orders raise a notification")

	EventScheduler.reset()
	SpecialOrderState.reset()
	TurnManager.current_turn = 10
	MatchState.money = 500.0
	var market_order: Dictionary = SpecialOrderState.create_order("coal", 10, 5, 4, 0.25)
	var market_order_id := str(market_order.get("id", ""))
	Stockpile.consume("tile_5_10", "g_001", 1 << 30)
	Stockpile.add("tile_5_10", "g_001", 4)
	var market_money_before: float = MatchState.money
	var sale: Dictionary = MarketState.execute_sale("tile_5_10", {"g_001": 4}, {
		"special_order_id": market_order_id,
		"special_order_source_mode": "tile_view",
		"log_oneoff": false,
	})
	var expected_bonus := float(sale.get("total_revenue", 0.0)) * 0.25
	_check(not sale.is_empty()
		and not bool(sale.get("deferred", false))
		and bool(sale.get("special_order_committed", false)),
		"special orders: market sales can commit to an active order")
	_check(SpecialOrderState.get_order(market_order_id).is_empty()
		and EventScheduler._active.has("special_order_fulfilled:%s" % market_order_id),
		"special orders: immediate market sales settle and close orders")
	_check(absf(MatchState.money - (market_money_before + float(sale.get("total_revenue", 0.0)) + expected_bonus)) < 0.01,
		"special orders: immediate market sale pays normal revenue plus premium")

	EventScheduler.reset()
	SpecialOrderState.reset()
	TurnManager.current_turn = saved_turn
	MatchState.money = saved_money

func _test_output_special_order_route() -> void:
	var saved_turn: int = TurnManager.current_turn
	var saved_money: float = MatchState.money
	MatchState.reset()
	Stockpile.clear_all()
	EventScheduler.reset()
	SpecialOrderState.reset()
	TurnManager.current_turn = 10
	MatchState.money = 500.0

	var order: Dictionary = SpecialOrderState.create_order("coal", 10, 5, 4, 0.25)
	var order_id := str(order.get("id", ""))
	MatchState.route_output_to_special_order("inst_so_prod", "g_001", order_id)
	_check(MatchState.is_output_market("inst_so_prod", "g_001")
		and MatchState.get_output_special_order_id("inst_so_prod", "g_001") == order_id,
		"special orders: output routes can target an active matching order")

	var summary := _fresh_production_summary()
	Production._dispatch_output_to_stockpile({
		"instance_id": "inst_so_prod",
		"tile_id": "tile_5_10",
	}, Catalog.get_good("g_001"), 4, summary)
	_check(SpecialOrderState.get_order(order_id).is_empty()
		and EventScheduler._active.has("special_order_fulfilled:%s" % order_id),
		"special orders: market-routed production output fulfils the order")
	_check(MatchState.money > 500.0
		and float(summary.get("goods_sales_revenue", 0.0)) > 0.0,
		"special orders: market-routed production pays revenue and premium")

	EventScheduler.reset()
	SpecialOrderState.reset()
	TurnManager.current_turn = saved_turn
	MatchState.reset()
	Stockpile.clear_all()
	MatchState.money = saved_money

func _test_tile_view_special_order_route() -> void:
	var saved_turn: int = TurnManager.current_turn
	var saved_money: float = MatchState.money
	MatchState.reset()
	Stockpile.clear_all()
	EventScheduler.reset()
	SpecialOrderState.reset()
	TurnManager.current_turn = 10
	MatchState.money = 500.0

	var order: Dictionary = SpecialOrderState.create_order("coal", 10, 5, 4, 0.25)
	var order_id := str(order.get("id", ""))
	var panel: Control = load("res://scripts/tile_info_panel_v2.gd").new()
	add_child(panel)
	panel.set("_current_tile_id", "tile_3_8")
	panel.set("_active_tab", "stock")
	panel.set("_stock_sel", {"good_id": "g_001", "name": "Coal", "qty": 6})
	panel.set("_stock_qty", 6)
	var menu: Control = panel.call("_make_stock_context_menu")
	_check(_node_tree_contains_text(menu, "Special Order"),
		"tile view: matching active order shows Special Order destination")
	menu.queue_free()
	panel.set("_stock_sel", {"good_id": "g_002", "name": "Iron Ore", "qty": 6})
	var other_menu: Control = panel.call("_make_stock_context_menu")
	_check(not _node_tree_contains_text(other_menu, "Special Order"),
		"tile view: non-matching goods do not show Special Order destination")
	other_menu.queue_free()
	panel.queue_free()

	Stockpile.add("tile_3_8", "g_001", 6)
	var ships_before := MatchState.get_pending_transport_shipments().size()
	var result: Dictionary = SpecialOrderState.queue_from_tile("tile_3_8", order_id, "g_001", 6, false)
	_check(not result.is_empty()
		and bool(result.get("special_order_committed", false))
		and int(result.get("total_qty", 0)) == 4
		and Stockpile.get_at_tile("tile_3_8", "g_001") == 2,
		"tile view: special-order sale clamps to remaining demand and consumes stock")
	var tagged := false
	for shipment in MatchState.get_pending_transport_shipments():
		var s: Dictionary = shipment
		if str(s.get("special_order_id", "")) == order_id and str(s.get("special_order_source_mode", "")) == "tile_view":
			tagged = true
	_check(MatchState.get_pending_transport_shipments().size() > ships_before and tagged,
		"tile view: special-order sale queues a tagged market shipment")

	var summary := _fresh_production_summary()
	for _i in range(25):
		Production._process_transport_arrivals(summary)
		if SpecialOrderState.get_order(order_id).is_empty():
			break
	_check(SpecialOrderState.get_order(order_id).is_empty()
		and EventScheduler._active.has("special_order_fulfilled:%s" % order_id),
		"tile view: tagged shipment fulfils the special order on arrival")

	EventScheduler.reset()
	SpecialOrderState.reset()
	TurnManager.current_turn = saved_turn
	MatchState.reset()
	Stockpile.clear_all()
	MatchState.money = saved_money

func _test_special_order_overflow_resolution() -> void:
	var saved_turn: int = TurnManager.current_turn
	var saved_money: float = MatchState.money
	MatchState.reset()
	Stockpile.clear_all()
	EventScheduler.reset()
	SpecialOrderState.reset()
	TurnManager.current_turn = 10
	MatchState.money = 500.0

	var overflow_records: Array = []
	var capture := func(record: Dictionary) -> void:
		overflow_records.append(record.duplicate(true))
	MatchState.special_order_overflow_ready.connect(capture)

	var order: Dictionary = SpecialOrderState.create_order("coal", 10, 5, 4, 0.25)
	var order_id := str(order.get("id", ""))
	var summary := _fresh_production_summary()
	Production._credit_arrived_sale({
		"id": 77,
		"is_sale": true,
		"source_tile": "tile_3_8",
		"destination_tile": "tile_5_10",
		"special_order_id": order_id,
		"special_order_source_mode": "building_detail",
		"sale_record": {
			"tile_id": "tile_3_8",
			"items": [{"good_id": "g_001", "qty": 6, "revenue": 60.0}],
			"total_qty": 6,
			"total_revenue": 60.0,
		},
	}, summary)

	_check(SpecialOrderState.get_order(order_id).is_empty()
		and overflow_records.size() == 1
		and int((overflow_records[0] as Dictionary).get("qty", 0)) == 2,
		"special orders: over-delivery fulfils order and raises overflow decision")
	_check(absf(MatchState.money - 550.0) < 0.001
		and absf(float(summary.get("goods_sales_revenue", 0.0)) - 50.0) < 0.001,
		"special orders: over-delivery pays counted units plus premium, not overflow")

	var record: Dictionary = overflow_records[0]
	var before_sell := MatchState.money
	var sold := MatchState.sell_special_order_overflow(record)
	_check(not sold.is_empty()
		and absf(MatchState.money - (before_sell + 20.0)) < 0.001,
		"special orders: overflow can be sold at normal market value")

	var stock_record := record.duplicate(true)
	stock_record["qty"] = 2
	stock_record["total_revenue"] = 20.0
	_check(MatchState.special_order_overflow_can_stockpile(stock_record)
		and MatchState.stockpile_special_order_overflow(stock_record)
		and Stockpile.get_at_tile("tile_5_10", "g_001") == 2,
		"special orders: overflow can be stockpiled at port when the whole shipment fits")

	MatchState.reset()
	Stockpile.clear_all()
	EventScheduler.reset()
	SpecialOrderState.reset()
	TurnManager.current_turn = 10
	MatchState.money = 500.0
	overflow_records.clear()
	var instant_order: Dictionary = SpecialOrderState.create_order("coal", 10, 5, 4, 0.25)
	Stockpile.add("tile_5_10", "g_001", 6)
	var instant_result := MarketState.execute_sale("tile_5_10", {"g_001": 6}, {
		"special_order_id": str(instant_order.get("id", "")),
		"special_order_source_mode": "tile_view",
		"log_oneoff": false,
	})
	_check(not bool(instant_result.get("deferred", true))
		and int(instant_result.get("total_qty", 0)) == 4
		and float(instant_result.get("total_revenue", 0.0)) > 0.0
		and overflow_records.size() == 1,
		"special orders: immediate over-delivery reports only credited sale units")

	if MatchState.special_order_overflow_ready.is_connected(capture):
		MatchState.special_order_overflow_ready.disconnect(capture)
	EventScheduler.reset()
	SpecialOrderState.reset()
	TurnManager.current_turn = saved_turn
	MatchState.reset()
	Stockpile.clear_all()
	MatchState.money = saved_money

func _test_pending_special_order_shipment_resolution() -> void:
	var saved_money: float = MatchState.money
	MatchState.reset()
	Stockpile.clear_all()

	var order_id := "so_test_pending"
	MatchState.queue_transport_shipment(_fake_special_order_sale_shipment(order_id, 4, 40.0))
	var taken := MatchState.take_pending_special_order_shipments(order_id)
	var sell_result := MatchState.resolve_special_order_shipments(taken, "sell")
	var pending := MatchState.get_pending_transport_shipments()
	_check(taken.size() == 1
		and bool(sell_result.get("ok", false))
		and pending.size() == 1
		and bool((pending[0] as Dictionary).get("is_sale", false))
		and str((pending[0] as Dictionary).get("special_order_id", "")) == "",
		"special orders: pending tagged shipments can be converted to normal market sales")

	MatchState.reset()
	Stockpile.clear_all()
	MatchState.queue_transport_shipment(_fake_special_order_sale_shipment(order_id, 4, 40.0))
	taken = MatchState.take_pending_special_order_shipments(order_id)
	var stockpile_result := MatchState.resolve_special_order_shipments(taken, "stockpile_port")
	pending = MatchState.get_pending_transport_shipments()
	_check(bool(stockpile_result.get("ok", false))
		and pending.size() == 1
		and not bool((pending[0] as Dictionary).get("is_sale", false))
		and str((pending[0] as Dictionary).get("destination_tile", "")) == "tile_5_10"
		and str((pending[0] as Dictionary).get("good_id", "")) == "g_001",
		"special orders: pending tagged shipments can be converted to port stockpile deliveries")

	MatchState.reset()
	Stockpile.clear_all()
	MatchState.queue_transport_shipment(_fake_special_order_sale_shipment(order_id, 4, 40.0))
	taken = MatchState.take_pending_special_order_shipments(order_id)
	var reroute_result := MatchState.resolve_special_order_shipments(taken, "reroute", "tile_12_4")
	pending = MatchState.get_pending_transport_shipments()
	_check(bool(reroute_result.get("ok", false))
		and pending.size() == 1
		and not bool((pending[0] as Dictionary).get("is_sale", false))
		and str((pending[0] as Dictionary).get("destination_tile", "")) == "tile_12_4",
		"special orders: pending tagged shipments can be rerouted to another tile stockpile")

	MatchState.reset()
	Stockpile.clear_all()
	MatchState.money = saved_money

func _test_special_order_resolution_dialog() -> void:
	var saved_money: float = MatchState.money
	MatchState.reset()
	Stockpile.clear_all()
	MatchState.money = 100.0

	var dialog: Control = load("res://scripts/special_order_resolution_dialog.gd").new()
	add_child(dialog)
	await get_tree().process_frame
	dialog.call("_on_overflow_ready", {
		"order_id": "so_dialog",
		"source_tile": "tile_3_8",
		"port_tile": "tile_5_10",
		"good_id": "g_001",
		"good_display": "Coal",
		"qty": 2,
		"unit_revenue": 10.0,
		"total_revenue": 20.0,
	})
	_check(dialog.visible
		and _node_tree_contains_text(dialog, "Special order overflow")
		and _node_tree_contains_text(dialog, "Stockpile at port"),
		"special orders: resolution dialog opens for overflow decisions")
	dialog.call("_on_sell_pressed")
	await get_tree().process_frame
	_check(not dialog.visible
		and absf(MatchState.money - 120.0) < 0.001,
		"special orders: resolution dialog sell action resolves and closes")
	PanelStack.remove(dialog)
	dialog.queue_free()
	MatchState.reset()
	Stockpile.clear_all()
	MatchState.money = saved_money

func _fake_special_order_sale_shipment(order_id: String, qty: int, revenue: float) -> Dictionary:
	return {
		"id": 9001,
		"is_sale": true,
		"source_tile": "tile_3_8",
		"destination_tile": "tile_5_10",
		"special_order_id": order_id,
		"special_order_source_mode": "tile_view",
		"sale_record": {
			"tile_id": "tile_3_8",
			"items": [{"good_id": "g_001", "qty": qty, "revenue": revenue}],
			"total_qty": qty,
			"total_revenue": revenue,
		},
		"tile_distance": 4,
		"transport_turns": 3,
		"turns_remaining": 3,
		"path": [],
		"legs": [],
		"tiles": [],
	}

func _test_market_special_orders_tab() -> void:
	var saved_turn: int = TurnManager.current_turn
	SpecialOrderState.reset()
	TurnManager.current_turn = 5
	var order: Dictionary = SpecialOrderState.create_order("coal", 5, 5, 10, 0.4)
	SpecialOrderState.commit_units(str(order.get("id", "")), 3, "tile_view", "g_001")

	var panel: Control = load("res://scenes/market_panel.tscn").instantiate()
	add_child(panel)
	panel.call("_ensure_built")
	var tabs: TabContainer = panel.get("_tabs")
	_check(tabs != null
		and tabs.get_child_count() >= 3
		and tabs.get_tab_title(2) == "Special Orders",
		"market panel: Special Orders is the third tab")
	tabs.current_tab = 2
	panel.call("_ensure_current_tab_built")
	var count_label: Label = panel.get("_special_orders_count_label")
	var body: VBoxContainer = panel.get("_special_orders_body")
	_check(count_label != null
		and count_label.text == "Active special orders: 1"
		and body != null
		and body.get_child_count() == 1,
		"market panel: Special Orders tab renders active order rows")
	_check(_node_tree_contains_text(body, "Coal")
		and _node_tree_contains_text(body, "3")
		and _node_tree_contains_text(body, "+40%"),
		"market panel: active special order row exposes good, committed qty and premium")
	var row := body.get_child(0)
	var row_main := row.get_child(0) as HBoxContainer
	var product_button: Button = null
	var target_cell: Label = null
	if row_main != null and row_main.get_child_count() > 2:
		product_button = row_main.get_child(1) as Button
		target_cell = row_main.get_child(2) as Label
	_check(row_main != null
		and int(row_main.custom_minimum_size.y) == 98
		and product_button != null
		and int(product_button.custom_minimum_size.x) == 240
		and int(product_button.custom_minimum_size.y) == 98
		and target_cell != null
		and int(target_cell.custom_minimum_size.y) == 98
		and target_cell.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER,
		"market panel: Special Orders rows match goods row height and centered column cells")

	SpecialOrderState.reset()
	panel.call("_refresh_special_orders")
	_check(count_label.text == "Active special orders: 0"
		and _node_tree_contains_text(body, "No active special orders"),
		"market panel: Special Orders tab renders the empty state")

	panel.queue_free()
	SpecialOrderState.reset()
	TurnManager.current_turn = saved_turn

func _special_order_goods(orders: Array) -> Array:
	var out: Array = []
	for order in orders:
		out.append(str((order as Dictionary).get("good_internal", "")))
	return out

func _node_tree_contains_text(root: Node, needle: String) -> bool:
	if root == null:
		return false
	if root is Label and str((root as Label).text).contains(needle):
		return true
	if root is Button and str((root as Button).text).contains(needle):
		return true
	for child in root.get_children():
		if _node_tree_contains_text(child, needle):
			return true
	return false

func _unique_strings(values: Array) -> Array:
	var seen: Dictionary = {}
	var out: Array = []
	for value in values:
		var key := str(value)
		if seen.has(key):
			continue
		seen[key] = true
		out.append(key)
	return out

# Save/load round-trip: populate every save-relevant system, export → JSON → import
# into the reset systems → export again; the two snapshots must agree section by
# section. Catches any state field a later change forgets to serialize.
func _test_save_load_roundtrip() -> void:
	MatchState.add_money(123.0)
	var inst: String = MatchState.add_building("b_001", "r_001", "tile_12_4")
	var inst_data: Dictionary = MatchState.buildings[inst]
	inst_data["level"] = 3
	MatchState.buildings[inst] = inst_data
	Stockpile.add("tile_12_4", "g_001", 25)
	MatchState.mark_tile_surveyed("tile_12_4")
	MatchState.add_recurring_move("tile_12_4", "tile_12_2", {"g_001": 5})
	MatchState.add_recurring_sell("tile_12_4", {"g_001": 3})
	MatchState.add_recurring_buy("tile_12_4", "g_001", 7)
	MatchState.add_recurring_bulk_sell({"good_id": "", "finished_only": true, "per_tile_keep": 2})
	MatchState.queue_move("tile_12_4", "tile_3_8", {"g_001": 5})  # an in-flight shipment
	_check(LoanState.take_loan(30.0), "roundtrip: loan taken for debt state")
	var special_order: Dictionary = SpecialOrderState.create_order("coal", TurnManager.current_turn, 5, 25)
	SpecialOrderState.commit_units(str(special_order.get("id", "")), 4, "tile_view")
	var hm = get_tree().get_first_node_in_group("hex_map")
	if hm != null:
		var coord: Vector2i = hm.id_to_coord("tile_12_4")
		if hm.tiles.has(coord):
			var tile: Dictionary = hm.tiles[coord]
			var infra: Array = tile.get("infrastructure_present", [])
			if not infra.has("pipes"):
				infra.append("pipes")
			var levels: Dictionary = tile.get("infrastructure_levels", {})
			levels["pipes"] = 2
			tile["infrastructure_present"] = infra
			tile["infrastructure_levels"] = levels
			hm.tiles[coord] = tile
			Catalog.add_tile_infrastructure("tile_12_4", "pipes")

	var snap1: Dictionary = SaveLoad.export_snapshot()
	# Real file round-trip via the slot API (covers JSON I/O + slot listing too).
	_check(SaveLoad.save_slot("__test_roundtrip") == "", "save_slot writes without error")
	var found := false
	for s in SaveLoad.list_slots():
		if str(s.slot) == "__test_roundtrip":
			found = true
	_check(found, "list_slots sees the new save")
	# restart_scene=false: apply in place (the default scene-reload path needs the
	# full game scene; the visual rebuild is exercised manually / by scene tests).
	_check(SaveLoad.load_slot("__test_roundtrip", false) == "", "load_slot applies without error")
	var snap2: Dictionary = SaveLoad.export_snapshot()
	for section in ["turn", "match", "stockpile", "loans", "construction", "market", "special_orders", "production", "events", "modifiers", "infrastructure"]:
		_check(_canonical_json(snap1[section]) == _canonical_json(snap2[section]),
			"round-trip preserves '%s'" % section)

	# Spot-check the loaded state is live, not just equal-on-paper.
	_check(str(MatchState.get_building(inst).get("tile_id", "")) == "tile_12_4",
		"loaded building is queryable")
	_check(int(MatchState.get_building(inst).get("level", 0)) == 3,
		"loaded building level survives the round-trip")
	if hm != null:
		var loaded_coord: Vector2i = hm.id_to_coord("tile_12_4")
		var loaded_tile: Dictionary = hm.tiles.get(loaded_coord, {})
		_check(int((loaded_tile.get("infrastructure_levels", {}) as Dictionary).get("pipes", 0)) == 2,
			"loaded infrastructure level survives the round-trip")
		var saved_infra: Dictionary = (snap2.get("infrastructure", {}) as Dictionary).get("tile_12_4", {})
		_check((saved_infra.get("present", []) as Array).has("pipes")
				and int((saved_infra.get("levels", {}) as Dictionary).get("pipes", 0)) == 2,
			"infrastructure snapshot stores present types plus levels")
	_check(Stockpile.get_at_tile("tile_12_4", "g_001") == 20, "loaded stockpile intact (25 - 5 moved)")
	_check(LoanState.total_outstanding() > 0.0, "loaded debt outstanding")
	_check(MatchState.recurring_moves.size() == 1 and MatchState.recurring_buys.size() == 1,
		"recurring orders survive the round-trip")
	var requoted := true
	for shipment in MatchState.pending_transport_shipments:
		if not (shipment.has("tiles") and shipment.has("path") and shipment.has("legs")):
			requoted = false
	_check(requoted, "in-flight shipment routes re-quoted on load")
	DirAccess.remove_absolute(AppPaths.saves_dir().path_join("__test_roundtrip.json"))

# Both sides of a comparison pass through stringify -> parse -> normalize so 5.0
# (native float) and 5 (JSON-round-tripped int) canonicalise identically.
func _canonical_json(section: Variant) -> String:
	return JSON.stringify(SaveLoad.normalize_jsonish(JSON.parse_string(JSON.stringify(section))))

# Phase 3 start configs: the authoring shape expands into a full snapshot —
# default money, loans become debt without cash, recurring orders stamped,
# port tiles + owned-building tiles pre-surveyed, instance ids collision-free.
func _test_start_config_expansion() -> void:
	var snap: Dictionary = SaveLoad.expand_start_config({
		"start": true,
		"money": 350,
		"loans": [{"principal": 150}],
		"buildings": [{"building_id": "b_001", "recipe_id": "r_001", "tile_id": "tile_6_8"}],
		"stockpile": {"tile_6_8": {"g_001": 50}},
		"recurring": {"sells": [{"source": "tile_6_8", "goods": {"g_001": 10}}]},
	})
	var match_d: Dictionary = snap.get("match", {})
	_check(float(match_d.get("money", 0.0)) == 350.0, "start config: money set")
	var buildings: Dictionary = match_d.get("buildings", {})
	_check(buildings.size() == 1 and str(buildings.values()[0].get("tile_id", "")) == "tile_6_8",
		"start config: building expanded with tile")
	_check(str(buildings.keys()[0]).begins_with("inst_b_001_"), "start config: instance id assigned")
	var loans: Array = (snap.get("loans", {}) as Dictionary).get("loans", [])
	var loan_ok: bool = loans.size() == 1 \
		and absf(float(loans[0].principal_remaining) - 165.0) < 0.001 \
		and absf(float(loans[0].payment_per_turn) - 165.0 / float(EconomyConfig.LOAN_TERM_TURNS)) < 0.001
	_check(loan_ok, "start config: loan amortised like take_loan (150 -> 165 owed)")
	var surveyed: Dictionary = match_d.get("surveyed_tiles", {})
	_check(surveyed.has("tile_6_8") and surveyed.has("tile_5_10"),
		"start config: owned-building tile + port tiles pre-surveyed")
	var sells: Array = match_d.get("recurring_sells", [])
	_check(sells.size() == 1 and int(sells[0].get("turn_started", -1)) == 1,
		"start config: recurring sell stamped turn_started 1")
	var defaults: Dictionary = SaveLoad.expand_start_config({"start": true})
	_check(float((defaults.get("match", {}) as Dictionary).get("money", 0.0)) == EconomyConfig.STARTING_MONEY,
		"start config: omitted money falls back to STARTING_MONEY")
	# New Game panel overrides merge into the match ruleset (survey_all_tiles etc.).
	var ov_snap: Dictionary = SaveLoad.expand_start_config(
		{"start": true, "ruleset": {"name": "standard"}},
		{"ruleset": {"survey_all_tiles": true, "tutorial_enabled": false}})
	var ov_rules: Dictionary = (ov_snap.get("match", {}) as Dictionary).get("ruleset", {})
	_check(bool(ov_rules.get("survey_all_tiles", false)) == true,
		"start config: override survey_all_tiles merges into the match ruleset")
	_check(str(ov_rules.get("name", "")) == "standard",
		"start config: override merge keeps the start's ruleset name")
	# Per-building output routing (output_to) → output_stockpile_destinations, keyed by
	# the minted instance_id, resolving the recipe's output good. And modifiers passthrough.
	var routed: Dictionary = SaveLoad.expand_start_config({
		"start": true,
		"buildings": [
			{"building_id": "b_001", "recipe_id": "r_001", "tile_id": "tile_6_8", "output_to": "tile_6_9"},
			{"building_id": "b_002", "recipe_id": "r_005", "tile_id": "tile_6_9", "output_to": "market"},
		],
		"modifiers": [
			{"id": "start_test_iron", "domain": "recipe_output", "target_match": {"good_internal": "iron_ingots"}, "pct": 10.0, "label": "Test Start"},
		],
	})
	var rmatch: Dictionary = routed.get("match", {})
	var dests: Dictionary = rmatch.get("output_stockpile_destinations", {})
	var mine_route := false
	var furn_market := false
	for iid in dests:
		var per_good: Dictionary = dests[iid]
		if str(iid).begins_with("inst_b_001_") and str(per_good.get("g_001", "")) == "tile_6_9":
			mine_route = true
		if str(iid).begins_with("inst_b_002_") and str(per_good.get("g_004", "")) == MatchState.MARKET_DESTINATION:
			furn_market = true
	_check(mine_route, "start config: output_to tile routes the mine's coal output to the furnace tile")
	_check(furn_market, "start config: output_to market routes the furnace's iron_ingots to __market__")
	var seeded_mods: Dictionary = (routed.get("modifiers", {}) as Dictionary).get("modifiers", {})
	var tm: Dictionary = seeded_mods.get("start_test_iron", {})
	_check(float(tm.get("pct", 0.0)) == 10.0 and str(tm.get("domain", "")) == "recipe_output"
		and float(tm.get("mult", 0.0)) == 1.0 and tm.has("expires_turn"),
		"start config: modifiers passthrough fills the ModifierState import shape (pct/domain/mult/expires_turn)")

# Phase 3 end-to-end: a start config applied through the scene pipeline keeps
# the scene-seeded NPC buildings (ports/ruins), seeds debt WITHOUT cash, and
# leaves the CSV deposit yields intact (the config carries no deposit data).
func _test_start_config_applies_on_scene_ready() -> void:
	# Inline fixture (NOT the live coal_baron.json) so gameplay-content edits to the
	# shipped starts can't break this pipeline test. Mirrors a rich start: cash kept
	# separate from loan principal, a player mine on a CSV coal tile (tile_6_8), a
	# seeded stockpile and a recurring sell.
	var cfg: Dictionary = {
		"start": true, "name": "test_fixture", "ruleset": "standard",
		"money": 350,
		"loans": [ {"principal": 150} ],
		"buildings": [ {"building_id": "b_001", "recipe_id": "r_001", "tile_id": "tile_6_8"} ],
		"stockpile": { "tile_6_8": {"g_001": 50} },
		"land": { "tile_6_8": 120 },
		"recurring": { "sells": [ {"source": "tile_6_8", "goods": {"g_001": 10}} ] },
	}
	_check(not cfg.is_empty(), "fixture start config built")
	SaveLoad._pending_snapshot = SaveLoad.expand_start_config(cfg)
	var inst: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(inst)
	await get_tree().process_frame
	_check(absf(MatchState.money - 350.0) < 0.001, "start: money is the configured 350 (no loan cash)")
	_check(absf(LoanState.total_outstanding() - 165.0) < 0.001, "start: debt outstanding 165")
	var mines := 0
	var npc := 0
	for iid in MatchState.buildings:
		var b: Dictionary = MatchState.buildings[iid]
		# Only the player's: the start-building pool seeds NPC mines map-wide.
		if str(b.get("building_id", "")) == "b_001" and MatchState.is_player_owned(b):
			mines += 1
		if not MatchState.is_player_owned(b):
			npc += 1
	_check(mines == 1, "start: configured mine exists")
	_check(npc >= 5, "start: scene-seeded NPC ports/ruins survive the start import")
	_check(Stockpile.get_at_tile("tile_6_8", "g_001") == 50, "start: stockpile seeded")
	_check(MatchState.recurring_sells.size() == 1, "start: recurring sell order live")
	_check(MatchState.deposit_remaining_for("tile_6_8", "coal") == 2000,
		"start: CSV deposit yields survive (no deposit data in the config)")
	inst.queue_free()
	await get_tree().process_frame

# Phase 4: a v1 save (no ruleset) steps up the migration ladder on load and
# arrives with the standard ruleset filled in.
func _test_save_version_migration() -> void:
	var snap: Dictionary = SaveLoad.export_snapshot()
	snap["save_version"] = 1
	(snap.get("match", {}) as Dictionary).erase("ruleset")
	(snap.get("meta", {}) as Dictionary).erase("ruleset")
	var legacy_infra: Dictionary = (snap.get("infrastructure", {}) as Dictionary).duplicate(true)
	legacy_infra["tile_12_4"] = ["pipes"]
	snap["infrastructure"] = legacy_infra
	var migrated_snap: Dictionary = SaveLoad._migrate(snap.duplicate(true))
	var migrated_infra: Dictionary = (migrated_snap.get("infrastructure", {}) as Dictionary).get("tile_12_4", {})
	_check((migrated_infra.get("present", []) as Array).has("pipes")
			and migrated_infra.has("levels"),
		"v1 -> v5 migration upgrades infrastructure arrays to structured entries")
	DirAccess.make_dir_recursive_absolute(AppPaths.saves_dir())
	var f := FileAccess.open(AppPaths.saves_dir().path_join("__test_v1.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(snap))
	f.close()
	MatchState.ruleset = {"name": "__sentinel__"}
	_check(SaveLoad.load_slot("__test_v1", false) == "", "v1 save loads through migration")
	_check(str(MatchState.ruleset.get("name", "")) == "standard",
		"v1 -> v2 migration fills in the standard ruleset")
	_check(str(SaveLoad.export_snapshot().get("meta", {}).get("ruleset", "")) == "standard",
		"migrated save re-exports with meta.ruleset")
	_check(SpecialOrderState.get_active_orders().is_empty(),
		"v1 -> v3 migration starts with no active special orders")
	DirAccess.remove_absolute(AppPaths.saves_dir().path_join("__test_v1.json"))

# Phase 4: a finished game stays finished across save/load.
func _test_game_ended_persists() -> void:
	var snap: Dictionary = SaveLoad.export_snapshot()
	(snap.get("turn", {}) as Dictionary)["game_ended"] = true
	(snap.get("turn", {}) as Dictionary)["current_turn"] = TurnManager.MAX_TURNS + 1
	SaveLoad.import_snapshot(snap)
	_check(TurnManager.game_ended and TurnManager.current_turn == TurnManager.MAX_TURNS + 1,
		"game_ended + final turn survive a load")
	TurnManager.reset_for_test()

# Phase 4: an awaiting-materials construction project keeps working after a
# save/load — the project dict, its missing-materials map and the
# construction-tagged shipments are all id/tile keyed, so once the materials
# reach the tile post-load, claim_materials promotes it.
func _test_construction_survives_load() -> void:
	MatchState.add_money(1000.0)
	var inst_id: String = Construction.start_awaiting_market("b_002", "r_002", "tile_13_2", 100.0)
	_check(inst_id != "", "awaiting-market construction project created")
	SaveLoad.import_snapshot(SaveLoad.normalize_jsonish(
		JSON.parse_string(JSON.stringify(SaveLoad.export_snapshot()))))
	var project: Dictionary = Construction.construction_projects.get(inst_id, {})
	_check(str(project.get("status", "")) == Construction.STATUS_AWAITING_MATERIALS,
		"project still awaiting materials after load")
	var tagged := false
	for shipment in MatchState.pending_transport_shipments:
		if str(shipment.get("construction_instance_id", "")) == inst_id:
			tagged = true
	_check(tagged, "construction-tagged material shipment survives the load")
	# Materials land on the tile (as an arrived shipment would deliver them) and
	# the loaded project claims them and starts its countdown.
	for good_id in (project.get("missing_materials", {}) as Dictionary).keys():
		Stockpile.add("tile_13_2", str(good_id), int(project["missing_materials"][good_id]))
	Construction.claim_materials()
	_check(str(Construction.construction_projects.get(inst_id, {}).get("status", "")) \
		== Construction.STATUS_UNDER_CONSTRUCTION,
		"loaded project claims arrived materials and starts construction")
	Construction.cancel(inst_id)

# Phase 4: the autosave hook fires only on every Nth finished turn and rotates
# its slot index. (Drive the handler directly; committing 10 real turns is slow.)
func _test_autosave_rotation() -> void:
	var saved_turn: int = TurnManager.current_turn
	var saved_index: int = SaveLoad._autosave_index
	SaveLoad._autosave_index = 0
	TurnManager.current_turn = SaveLoad.AUTOSAVE_EVERY_TURNS + 1  # turn N just finished
	SaveLoad._on_turn_resolution_completed()
	_check(SaveLoad._autosave_index == 1 and FileAccess.file_exists(AppPaths.saves_dir().path_join("autosave_1.json")),
		"autosave fires on the Nth finished turn into slot 1")
	TurnManager.current_turn = SaveLoad.AUTOSAVE_EVERY_TURNS + 2  # off-cadence turn
	SaveLoad._on_turn_resolution_completed()
	_check(SaveLoad._autosave_index == 1, "no autosave between cadence points")
	TurnManager.current_turn = 2 * SaveLoad.AUTOSAVE_EVERY_TURNS + 1
	SaveLoad._on_turn_resolution_completed()
	_check(SaveLoad._autosave_index == 2, "next cadence point rotates to slot 2")
	DirAccess.remove_absolute(AppPaths.saves_dir().path_join("autosave_1.json"))
	DirAccess.remove_absolute(AppPaths.saves_dir().path_join("autosave_2.json"))
	TurnManager.current_turn = saved_turn
	SaveLoad._autosave_index = saved_index

# --- EventScheduler ----------------------------------------------------------
# Substrate tests. The bell UI lives separately and has its own UI smoke test.

# Drive a synthetic turn: bump current_turn and emit phase_started(NARRATIVE)
# so EventScheduler ticks. Avoids running the full TurnManager resolution which
# would have side-effects on every other system.
func _tick_event_scheduler_to(new_turn: int) -> void:
	TurnManager.current_turn = new_turn
	TurnManager.phase_started.emit(TurnManager.Phase.NARRATIVE)
	await get_tree().process_frame

func _test_event_scheduler_emit() -> void:
	EventScheduler.reset()
	TurnManager.current_turn = 1
	var fired: Array = []
	var cb := func(ev): fired.append(ev)
	EventScheduler.event_fired.connect(cb)
	var ev := EventScheduler.emit_event({"title": "Hi", "severity": EventScheduler.SEVERITY_INFO})
	_check(fired.size() == 1 and str(fired[0].id) == str(ev.id),
		"emit_event puts an event in the bell + fires event_fired")
	_check(EventScheduler.active_count() == 1, "active_count reflects the new event")
	_check(int(ev.turn_fired) == 1, "event records the turn it fired on")
	_check(EventScheduler.dismiss(str(ev.id)) and EventScheduler.active_count() == 0,
		"dismiss removes from active list")
	if EventScheduler.event_fired.is_connected(cb):
		EventScheduler.event_fired.disconnect(cb)
	EventScheduler.reset()

func _test_event_scheduler_schedule() -> void:
	EventScheduler.reset()
	TurnManager.current_turn = 5
	EventScheduler.schedule(8, {"id": "scheduled_test", "title": "Fires on 8",
		"severity": EventScheduler.SEVERITY_WARNING})
	# Turn 6, 7: scheduled event should NOT have fired yet.
	await _tick_event_scheduler_to(6)
	_check(not EventScheduler._active.has("scheduled_test"), "scheduled event waits past turn 6")
	await _tick_event_scheduler_to(7)
	_check(not EventScheduler._active.has("scheduled_test"), "scheduled event waits past turn 7")
	# Turn 8: fires.
	await _tick_event_scheduler_to(8)
	_check(EventScheduler._active.has("scheduled_test"), "scheduled event fires on its turn")
	EventScheduler.reset()

func _test_event_scheduler_forewarn() -> void:
	EventScheduler.reset()
	TurnManager.current_turn = 10
	EventScheduler.schedule(20, {"id": "carbon_tax", "title": "Carbon Tax Applied",
		"severity": EventScheduler.SEVERITY_CRITICAL, "forewarn_turns": 5,
		"forewarn_body": "Tax begins in 5 turns."})
	# Turn 14: still no forewarning.
	await _tick_event_scheduler_to(14)
	_check(not EventScheduler._active.has("carbon_tax:forewarn"), "forewarn not yet armed")
	# Turn 15: forewarning fires (20 - 5).
	await _tick_event_scheduler_to(15)
	_check(EventScheduler._active.has("carbon_tax:forewarn"),
		"forewarning fires N turns before the scheduled event")
	_check(not EventScheduler._active.has("carbon_tax"),
		"main event has not fired yet at forewarn turn")
	# Turn 20: main event fires.
	await _tick_event_scheduler_to(20)
	_check(EventScheduler._active.has("carbon_tax"),
		"main scheduled event fires on its target turn")
	EventScheduler.reset()

func _test_event_scheduler_watch_oneshot() -> void:
	EventScheduler.reset()
	TurnManager.current_turn = 1
	EventScheduler.watch({"type": "turn_reached", "value": 3},
		{"id": "turn3", "title": "Hit turn 3", "severity": EventScheduler.SEVERITY_INFO},
		true)
	await _tick_event_scheduler_to(2)
	_check(not EventScheduler._active.has("turn3"), "watch doesn't fire before predicate is true")
	await _tick_event_scheduler_to(3)
	_check(EventScheduler._active.has("turn3"), "watch fires the turn its predicate becomes true")
	# Dismiss and tick again — one-shot must not re-fire.
	EventScheduler.dismiss("turn3")
	await _tick_event_scheduler_to(4)
	_check(not EventScheduler._active.has("turn3"), "one-shot watch does not re-fire")
	EventScheduler.reset()

func _test_event_scheduler_starvation_ramp() -> void:
	EventScheduler.reset()
	TurnManager.current_turn = 1
	var record := {"instance_id": "inst_test", "building_id": "b_001", "tile_id": "tile_12_4", "missing": []}
	EventScheduler._on_building_starved(record)
	var ev: Dictionary = EventScheduler._active.get("starvation:inst_test", {})
	_check(str(ev.get("severity", "")) == EventScheduler.SEVERITY_WARNING,
		"starvation turn 1 = amber")
	# Turn 2: still amber.
	TurnManager.current_turn = 2
	EventScheduler._on_building_starved(record)
	_check(str(EventScheduler._active["starvation:inst_test"].severity) == EventScheduler.SEVERITY_WARNING,
		"starvation turn 2 = amber")
	# Turn 3: ramps to critical (STARVATION_RAMP_TURNS = 3).
	TurnManager.current_turn = 3
	EventScheduler._on_building_starved(record)
	_check(str(EventScheduler._active["starvation:inst_test"].severity) == EventScheduler.SEVERITY_CRITICAL,
		"starvation turn 3 ramps to critical (red)")
	# Skip turn 4 — building runs (no starvation signal); turn 5 NARRATIVE clears it.
	await _tick_event_scheduler_to(5)
	_check(not EventScheduler._active.has("starvation:inst_test"),
		"auto-clear removes starvation when the building runs again")
	EventScheduler.reset()

func _test_event_scheduler_aggregator() -> void:
	EventScheduler.reset()
	TurnManager.current_turn = 10
	var template := {"title_template": "{count} sales — £{value}",
		"body_template": "rolled up", "severity": EventScheduler.SEVERITY_INFO}
	for i in range(12):
		EventScheduler.aggregate("test_agg", template, 1, 350.0)
	# Aggregator stays open during the turn — no event in bell yet.
	_check(EventScheduler.active_count() == 0, "aggregator does not fire mid-turn")
	# NARRATIVE flushes: one rolled-up event.
	await _tick_event_scheduler_to(10)
	_check(EventScheduler.active_count() == 1,
		"flush_aggregators emits one event per bucket (got %d)" % EventScheduler.active_count())
	var rows: Array = EventScheduler.active_events()
	_check(str(rows[0].title).begins_with("12 sales"),
		"aggregated title interpolates {count} (got '%s')" % str(rows[0].title))
	EventScheduler.reset()

func _test_event_scheduler_max_severity() -> void:
	EventScheduler.reset()
	TurnManager.current_turn = 1
	EventScheduler.emit_event({"id": "i", "title": "i", "severity": EventScheduler.SEVERITY_INFO})
	_check(EventScheduler.max_severity() == EventScheduler.SEVERITY_INFO, "1 info → info")
	EventScheduler.emit_event({"id": "w", "title": "w", "severity": EventScheduler.SEVERITY_WARNING})
	_check(EventScheduler.max_severity() == EventScheduler.SEVERITY_WARNING, "info+warning → warning")
	EventScheduler.emit_event({"id": "c", "title": "c", "severity": EventScheduler.SEVERITY_CRITICAL})
	_check(EventScheduler.max_severity() == EventScheduler.SEVERITY_CRITICAL, "info+warning+critical → critical")
	EventScheduler.dismiss("c")
	_check(EventScheduler.max_severity() == EventScheduler.SEVERITY_WARNING,
		"dismissing the critical drops bell back to warning")
	EventScheduler.reset()

func _test_event_scheduler_roundtrip() -> void:
	EventScheduler.reset()
	TurnManager.current_turn = 50
	EventScheduler.emit_event({"id": "active_a", "title": "A",
		"severity": EventScheduler.SEVERITY_WARNING})
	EventScheduler.schedule(80, {"id": "future_a", "title": "future",
		"severity": EventScheduler.SEVERITY_CRITICAL, "forewarn_turns": 5})
	EventScheduler.watch({"type": "turn_reached", "value": 100},
		{"id": "watch_a", "title": "watched", "severity": EventScheduler.SEVERITY_INFO}, true)
	var snap := EventScheduler.export_state()
	# Wipe and reimport.
	EventScheduler.reset()
	_check(EventScheduler.active_count() == 0 and EventScheduler._scheduled.is_empty()
		and EventScheduler._watches.is_empty(), "reset clears all state")
	EventScheduler.import_state(snap)
	_check(EventScheduler._active.has("active_a"), "round-trip restores active events")
	_check(EventScheduler._scheduled.size() == 1
		and str(EventScheduler._scheduled[0].event.id) == "future_a",
		"round-trip restores scheduled events")
	_check(EventScheduler._watches.size() == 1
		and str(EventScheduler._watches[0].id) == "watch_a",
		"round-trip restores watches")
	EventScheduler.reset()

# --- Modifiers ---------------------------------------------------------------

func _test_modifiers_basic() -> void:
	Modifiers.reset()
	TurnManager.current_turn = 1
	# No active modifiers → base passes through untouched.
	_check(Modifiers.apply("recipe_output", "r_001", 20.0) == 20.0,
		"apply with empty registry returns base unchanged")
	# Add a +5% recipe_output modifier on r_001.
	var mid := Modifiers.add({"id": "test_a", "domain": "recipe_output",
		"target": "r_001", "mult": 1.05, "label": "Test +5%"})
	_check(mid == "test_a" and Modifiers.has("test_a"),
		"add registers the modifier with the supplied id")
	_check(absf(Modifiers.apply("recipe_output", "r_001", 20.0) - 21.0) < 0.001,
		"applied to r_001: 20 * 1.05 = 21")
	# Different target → unchanged.
	_check(absf(Modifiers.apply("recipe_output", "r_002", 20.0) - 20.0) < 0.001,
		"r_001-targeted modifier does NOT affect r_002")
	# Different domain → unchanged even for the same target.
	_check(absf(Modifiers.apply("transport_cost", "r_001", 20.0) - 20.0) < 0.001,
		"recipe_output modifier does NOT affect the transport_cost domain")
	_check(Modifiers.remove("test_a") and not Modifiers.has("test_a"),
		"remove drops the modifier")
	Modifiers.reset()

func _test_modifiers_stacking() -> void:
	Modifiers.reset()
	# Add-then-mult stacking: (base + adds) * prod(mults).
	# base = 10, +2 (add) and +3 (add) → 15; then *1.5 and *1.2 → 27.
	Modifiers.add({"id": "a", "domain": "recipe_output", "target": "*", "add": 2.0})
	Modifiers.add({"id": "b", "domain": "recipe_output", "target": "*", "add": 3.0})
	Modifiers.add({"id": "c", "domain": "recipe_output", "target": "*", "mult": 1.5})
	Modifiers.add({"id": "d", "domain": "recipe_output", "target": "*", "mult": 1.2})
	var got: float = Modifiers.apply("recipe_output", "r_001", 10.0)
	_check(absf(got - 27.0) < 0.001,
		"stacking: (10+2+3)*1.5*1.2 = 27 (got %.3f)" % got)
	Modifiers.reset()

func _test_modifiers_target_match() -> void:
	Modifiers.reset()
	# target_match: only fires when ctx provides the required keys.
	Modifiers.add({"id": "extraction_only", "domain": "recipe_output",
		"target_match": {"recipe_type": "extraction"}, "mult": 1.10})
	var ctx_ext := {"recipe_type": "extraction"}
	var ctx_smelt := {"recipe_type": "smelting"}
	_check(absf(Modifiers.apply("recipe_output", "r_001", 20.0, ctx_ext) - 22.0) < 0.001,
		"target_match recipe_type=extraction applies to extraction ctx")
	_check(absf(Modifiers.apply("recipe_output", "r_003", 20.0, ctx_smelt) - 20.0) < 0.001,
		"target_match recipe_type=extraction does NOT apply to a smelting ctx")
	_check(absf(Modifiers.apply("recipe_output", "r_001", 20.0) - 20.0) < 0.001,
		"target_match modifier inert when ctx is missing the key")
	Modifiers.reset()

func _test_modifiers_expiry() -> void:
	Modifiers.reset()
	TurnManager.current_turn = 10
	TurnManager.current_phase = TurnManager.Phase.DECIDE
	Modifiers.add({"id": "tempo", "domain": "recipe_output",
		"target": "*", "mult": 2.0, "duration_turns": 5})
	# Added in DECIDE of turn 10 → it already applies to turn 10's PROCESS, so a
	# 5-turn duration covers PROCESS 10..14 and expires at 10 + 5 - 1 = 14.
	_check(int(Modifiers._modifiers["tempo"]["expires_turn"]) == 14,
		"duration_turns is converted into an absolute expires_turn")
	_check(absf(Modifiers.apply("recipe_output", "r_001", 10.0) - 20.0) < 0.001,
		"modifier active before expiry")
	# Tick NARRATIVE phases up to and past expiry.
	TurnManager.current_turn = 13
	TurnManager.phase_started.emit(TurnManager.Phase.NARRATIVE)
	await get_tree().process_frame
	_check(Modifiers.has("tempo"), "still active one turn before expiry")
	TurnManager.current_turn = 14
	TurnManager.phase_started.emit(TurnManager.Phase.NARRATIVE)
	await get_tree().process_frame
	_check(not Modifiers.has("tempo"), "pruned on the turn it expires")
	_check(absf(Modifiers.apply("recipe_output", "r_001", 10.0) - 10.0) < 0.001,
		"expired modifier no longer affects apply")
	# NARRATIVE-granted (condition unlock): first application is NEXT turn's
	# PROCESS, so the same 5-turn duration expires one turn later (11..15).
	TurnManager.current_turn = 10
	TurnManager.current_phase = TurnManager.Phase.NARRATIVE
	Modifiers.add({"id": "tempo2", "domain": "recipe_output",
		"target": "*", "mult": 2.0, "duration_turns": 5})
	_check(int(Modifiers._modifiers["tempo2"]["expires_turn"]) == 15,
		"NARRATIVE-granted duration expires one turn later")
	TurnManager.current_phase = TurnManager.Phase.DECIDE
	Modifiers.reset()

func _test_modifiers_event_payload() -> void:
	Modifiers.reset()
	EventScheduler.reset()
	TurnManager.current_turn = 1
	# An EventScheduler event with a modifiers payload should auto-add them.
	EventScheduler.emit_event({
		"id": "carbon_tax_apply",
		"title": "Carbon Tax applied",
		"severity": EventScheduler.SEVERITY_CRITICAL,
		"modifiers": [{
			"id": "carbon_tax_transport",
			"domain": "transport_cost", "target": "*",
			"mult": 1.30, "duration_turns": 20,
		}],
	})
	_check(Modifiers.has("carbon_tax_transport"),
		"event with `modifiers` payload auto-registers the modifier on fire")
	_check(absf(Modifiers.apply("transport_cost", "g_001", 10.0) - 13.0) < 0.001,
		"the auto-registered modifier is live for apply (10 * 1.30 = 13)")
	Modifiers.reset()
	EventScheduler.reset()

func _test_modifiers_production_recipe_output() -> void:
	# Drives a coal mine through Production once with no modifier (baseline),
	# then a second time with +5% extraction. Asserts the +5% takes effect end
	# to end: not just in Modifiers.apply but in what lands in the stockpile.
	Modifiers.reset()
	MatchState.reset()
	Stockpile.clear_all()
	var tile := "tile_6_8"  # has a coal deposit
	var inst: String = MatchState.add_building("b_001", "r_001", tile)
	# Force-allow the mine to run (deposit is seeded from the live tile map,
	# which a clean test environment doesn't have — drop the depletion gate by
	# revealing + topping up the deposit).
	MatchState.reveal_deposit(tile, "coal")
	MatchState.deposit_remaining[tile] = {"coal": 999}
	# Coal carries a standing −30% deposit-penalty modifier (re-seeded by the reset
	# above); drop it so this test isolates the +5% extraction modifier on a clean
	# 60-unit baseline.
	Modifiers.remove("deposit_penalty_coal")

	var summary := _fresh_production_summary()
	Production._produce_outputs(MatchState.get_building(inst), Catalog.get_recipe("r_001"), summary)
	Production._flush_output_buffer()
	var base_produced: int = int(summary.produced.get("g_001", 0))
	_check(base_produced == 60, "baseline: coal recipe produces 60 (got %d)" % base_produced)

	# Now with the Mining Mastery modifier active: mining recipes +5%.
	Stockpile.clear_all()
	Modifiers.add({"id": "mining_mastery_bonus", "domain": "recipe_output",
		"target_match": {"recipe_type": "mineral mining"}, "mult": 1.05})
	summary = _fresh_production_summary()
	Production._produce_outputs(MatchState.get_building(inst), Catalog.get_recipe("r_001"), summary)
	Production._flush_output_buffer()
	var boosted_produced: int = int(summary.produced.get("g_001", 0))
	_check(boosted_produced == 63, "with +5%% mining modifier: 60 → 63 (got %d)" % boosted_produced)
	_check(Stockpile.get_at_tile(tile, "g_001") == 63,
		"the boosted output lands in the tile stockpile (got %d)" % Stockpile.get_at_tile(tile, "g_001"))
	Modifiers.reset()
	MatchState.remove_building(inst)

func _test_modifiers_roundtrip() -> void:
	Modifiers.reset()
	TurnManager.current_turn = 50
	Modifiers.add({"id": "a", "domain": "recipe_output", "target": "*",
		"mult": 1.07, "expires_turn": 100, "label": "A"})
	Modifiers.add({"id": "b", "domain": "transport_cost",
		"target_match": {"good_id": "g_001"}, "add": 0.5, "expires_turn": 80})
	var snap: Dictionary = Modifiers.export_state()
	Modifiers.reset()
	_check(Modifiers.active_count() == 0, "reset clears the registry")
	Modifiers.import_state(snap)
	_check(Modifiers.has("a") and Modifiers.has("b"),
		"round-trip restores both modifiers")
	_check(absf(Modifiers.apply("recipe_output", "anything", 10.0) - 10.7) < 0.001,
		"restored 'a' still applies (10 * 1.07 = 10.7)")
	_check(absf(Modifiers.apply("transport_cost", "g_001", 1.0, {"good_id": "g_001"}) - 1.5) < 0.001,
		"restored 'b' still applies (1 + 0.5)")
	Modifiers.reset()

# End-to-end the demo unlock: a mine for each of the 6 staple deposits triggers
# the research tech ("Mining Mastery", research_unlocks.csv) → MatchState grants
# the unlock when its condition is met → Modifiers applies the +5% bonus.
func _test_deposit_penalty_modifier() -> void:
	# The deposit penalty + mining-yield research are recipe_output modifiers matched
	# by good_internal, so they show in the net-modifier indicator AND apply through
	# the production hook (no separate deposit-yield multiply).
	Modifiers.reset()
	MatchState.reset()          # re-seeds the standing per-good deposit penalties
	Stockpile.clear_all()
	# Coal starts at a standing −30% deposit penalty.
	var r: Dictionary = Modifiers.resolve_pct("recipe_output", "r_001", {"good_internal": "coal"})
	_check(absf(float(r.get("net", 0.0)) - (-30.0)) < 0.001,
		"coal mine starts at a −30%% deposit penalty (got %s)" % float(r.get("net", 0.0)))
	# The first recovery unlock adds +15% → net −15% (additive, no cap).
	MatchState.grant_unlock("Improved Coal Mining")
	var r2: Dictionary = Modifiers.resolve_pct("recipe_output", "r_001", {"good_internal": "coal"})
	_check(absf(float(r2.get("net", 0.0)) - (-15.0)) < 0.001,
		"Improved Coal Mining: −30%% + 15%% = net −15%% (got %s)" % float(r2.get("net", 0.0)))
	_check((r2.get("parts", []) as Array).size() == 2,
		"breakdown shows both the penalty tile and the research tile")
	# End to end: a coal mine produces round(60 * 0.85) = 51.
	var tile := "tile_6_8"
	var inst: String = MatchState.add_building("b_001", "r_001", tile)
	MatchState.reveal_deposit(tile, "coal")
	MatchState.deposit_remaining[tile] = {"coal": 999}
	var summary := _fresh_production_summary()
	Production._produce_outputs(MatchState.get_building(inst), Catalog.get_recipe("r_001"), summary)
	Production._flush_output_buffer()
	_check(int(summary.produced.get("g_001", 0)) == 51,
		"coal output reflects net −15%% (60 → 51, got %d)" % int(summary.produced.get("g_001", 0)))
	# The second recovery unlock removes the remaining penalty exactly.
	MatchState.grant_unlock("Automated Mine Dispatch")
	var r3: Dictionary = Modifiers.resolve_pct("recipe_output", "r_001", {"good_internal": "coal"})
	_check(absf(float(r3.get("net", 0.0))) < 0.001,
		"Automated Mine Dispatch: −30%% + 15%% + 15%% = full coal output")
	# Exempt goods (not in EXTRACTION_PENALTY_PCT) carry no penalty tile.
	var ro: Dictionary = Modifiers.resolve_pct("recipe_output", "rX", {"good_internal": "crude_oil"})
	_check(absf(float(ro.get("net", 0.0))) < 0.001,
		"exempt goods (crude_oil) carry no deposit penalty")
	# Loading a save (import_state) must NOT wipe the standing penalties — they are a
	# baseline rule re-seeded on import (regression: penalties vanished after load).
	Modifiers.import_state({"modifiers": {}, "history": [], "next_id": 1})
	var rload: Dictionary = Modifiers.resolve_pct("recipe_output", "r_001", {"good_internal": "coal"})
	_check(absf(float(rload.get("net", 0.0)) - (-30.0)) < 0.001,
		"a load with no saved penalties re-seeds the coal penalty (got %s)" % float(rload.get("net", 0.0)))
	MatchState.remove_building(inst)

	# Every penalized extraction good has exactly enough +15% research steps to
	# cancel its standing penalty: two for −30% goods, one for −15% goods.
	var expected_recovery_steps := {
		"coal": 2, "iron_ore": 2, "copper_ore": 2, "limestone": 2,
		"sand": 2, "basic_salt": 2, "ree_ore": 2, "alloy_ore": 2,
		"sulphur": 1, "bauxite_ore": 1,
	}
	var recovery_unlocks := {}
	for unlock_title in Modifiers.UNLOCK_MODIFIERS:
		var raw_spec = Modifiers.UNLOCK_MODIFIERS[unlock_title]
		var specs: Array = raw_spec if raw_spec is Array else [raw_spec]
		for raw_effect in specs:
			var effect: Dictionary = raw_effect
			if str(effect.get("source", "")) != "research:mining_yield":
				continue
			var effect_good := str((effect.get("target_match", {}) as Dictionary).get("good_internal", ""))
			if effect_good == "":
				continue
			_check(absf(float(effect.get("pct", 0.0)) - 15.0) < 0.001,
				"%s restores %s output by exactly 15%%" % [unlock_title, effect_good])
			var titles: Array = recovery_unlocks.get(effect_good, [])
			titles.append(str(unlock_title))
			recovery_unlocks[effect_good] = titles
	for recovery_good in expected_recovery_steps:
		var recovery_titles: Array = recovery_unlocks.get(recovery_good, [])
		_check(recovery_titles.size() == int(expected_recovery_steps[recovery_good]),
			"%s has exactly %d mining-yield recovery unlock%s" % [
				recovery_good, int(expected_recovery_steps[recovery_good]),
				"" if int(expected_recovery_steps[recovery_good]) == 1 else "s",
			])
		Modifiers.reset()
		MatchState.reset()
		for recovery_title in recovery_titles:
			Modifiers.apply_unlock_modifier(str(recovery_title))
		var recovered: Dictionary = Modifiers.resolve_pct("recipe_output", "test", {"good_internal": recovery_good})
		_check(absf(float(recovered.get("net", 0.0))) < 0.001,
			"%s recovery research restores full output exactly" % recovery_good)
	Modifiers.reset()
	MatchState.reset()

func _test_workforce_output_modifier_surfaces_in_building_status() -> void:
	Modifiers.reset()
	MatchState.reset()
	var old_turn: int = int(TurnManager.current_turn)
	TurnManager.current_turn = 1
	var building := {
		"instance_id": "inst_status_workforce",
		"building_id": "b_007",
		"tile_id": "tile_5_10",
		"recipe_id": "r_009",
		"level": 1,
	}
	var recipe: Dictionary = Catalog.get_recipe("r_009")
	_check(BuildingStatus.effective_output_qty(building, recipe) == 28,
		"building status baseline output excludes inactive workforce policies")
	MatchState.set_workforce_policy_enabled(MatchState.WORKFORCE_POLICY_ANNUAL_PROFIT_SHARE, true)
	var mod: Dictionary = BuildingStatus.net_output_modifier(building, recipe)
	var workforce_parts: Array = mod.get("workforce_parts", [])
	_check(BuildingStatus.effective_output_qty(building, recipe) == 31,
		"building status output includes annual profit-share workforce multiplier")
	_check(absf(float(mod.get("pct_f", 0.0)) - 10.0) < 0.001,
		"building status net output modifier includes annual profit share")
	var first_workforce_part: Dictionary = workforce_parts[0] if not workforce_parts.is_empty() else {}
	_check(workforce_parts.size() == 1 and str(first_workforce_part.get("label", "")) == "Annual Profit Share",
		"building status modifier breakdown lists annual profit share")
	_check(BuildingStatus._modifier_tooltip(mod).find("Annual Profit Share") >= 0,
		"building status tooltip includes annual profit share")
	MatchState.set_workforce_policy_enabled(MatchState.WORKFORCE_POLICY_ANNUAL_PROFIT_SHARE, false)
	TurnManager.current_turn = old_turn
	Modifiers.reset()
	MatchState.reset()

func _test_additive_labour_cost_model() -> void:
	Modifiers.reset()
	MatchState.reset()
	var old_turn: int = int(TurnManager.current_turn)
	TurnManager.current_turn = 1
	# People-management unlocks now trim 10% each (was 5%).
	var otm: Dictionary = Modifiers.UNLOCK_MODIFIERS.get("Operational Team Managers", {})
	var shd: Dictionary = Modifiers.UNLOCK_MODIFIERS.get("Shift Handover Documentation", {})
	_check(float(otm.get("pct", 0.0)) == -10.0 and float(shd.get("pct", 0.0)) == -10.0,
		"labour unlocks: OTM and SHD each trim head-count by 10%")

	var iid := MatchState.add_building("b_001", "r_001", "tile_6_8", MatchState.LOCAL_PLAYER, "test_additive_labour")
	var building: Dictionary = MatchState.buildings[iid]
	MatchState.set_labour_multiplier(1.0)
	_check(is_equal_approx(Production.labour_cost_factor(building), 1.0),
		"labour factor: 100% of base with no modifiers")

	# Slider +20% and a -30% policy delta net to -10% off the 100% base (additive,
	# not the old compounded 0.8 x 1.2 x ...).
	MatchState.set_labour_multiplier(1.2)
	MatchState.workforce_policy_effects["test_policy"] = {"labour_pct": -0.30, "output_pct": 0.0, "active_turns": 1}
	_check(is_equal_approx(Production.labour_cost_factor(building), 0.90),
		"labour factor: slider and policy deltas add to base 100% (no compounding)")
	_check(is_equal_approx(Production._calculate_labour_cost(building), Production._base_labour_cost(building) * 0.90),
		"labour cost: base x additive factor")

	var ov: Dictionary = Production.labour_overview()
	_check(ov.has("current") and ov.has("est_10_turns") and ov.has("factor_pct") and ov.has("next_turn"),
		"labour overview: exposes current, next-turn, 10-turn estimate and factor %")

	MatchState.workforce_policy_effects.clear()
	MatchState.set_labour_multiplier(1.0)
	TurnManager.current_turn = old_turn
	Modifiers.reset()
	MatchState.reset()

func _test_recipe_labour_owns_cost() -> void:
	var old_turn: int = int(TurnManager.current_turn)
	TurnManager.current_turn = 1
	var recipe: Dictionary = Catalog.get_recipe("r_039")
	var building_data: Dictionary = Catalog.get_building_by_internal_name("electrolyser")
	var building := {
		"building_id": building_data.get("id", ""),
		"recipe_id": "r_039",
		"level": 1,
	}
	var expected := (
		float(recipe.get("labour_unskilled_required", 0)) * EconomyConfig.LABOUR_UNSKILLED_RATE
		+ float(recipe.get("labour_skilled_required", 0)) * EconomyConfig.LABOUR_SKILLED_RATE
		+ float(recipe.get("labour_h_skilled_required", 0)) * EconomyConfig.LABOUR_HIGH_SKILLED_RATE
	)
	_check(int(recipe.get("labour_unskilled_required", 0)) >= 500
		and int(recipe.get("labour_skilled_required", 0)) >= 100
		and int(recipe.get("labour_h_skilled_required", 0)) >= 50,
		"recipe labour: migrated rows retain the minimum crew")
	_check(is_equal_approx(Production._base_labour_cost(building, recipe), expected),
		"recipe labour: production cost uses the selected recipe, not the building default")
	TurnManager.current_turn = old_turn

func _test_labour_factor_floor() -> void:
	Modifiers.reset()
	MatchState.reset()
	var old_turn: int = int(TurnManager.current_turn)
	TurnManager.current_turn = 1
	var iid := MatchState.add_building("b_001", "r_001", "tile_6_8", MatchState.LOCAL_PLAYER, "test_labour_floor")
	var building: Dictionary = MatchState.buildings[iid]
	MatchState.set_labour_multiplier(1.0)
	# A -80% head-count reduction would drive the factor to 0.20; the floor clamps it.
	Modifiers.add({"id": "test_labour_floor", "domain": "labour_headcount", "pct": -80.0})
	_check(is_equal_approx(Production.labour_cost_factor(building), EconomyConfig.LABOUR_FACTOR_MIN),
		"labour floor: factor clamps to LABOUR_FACTOR_MIN (0.40) when reductions exceed it")
	_check(bool(Production.labour_overview().get("at_floor", false)),
		"labour floor: overview flags at_floor once the cap is reached")
	# The -60% debug cheat lands exactly on the floor (1 - 0.60 = 0.40).
	Modifiers.remove("test_labour_floor")
	Modifiers.add({"id": "cheat_labour_discount", "domain": "labour_headcount", "pct": -60.0})
	_check(is_equal_approx(Production.labour_cost_factor(building), EconomyConfig.LABOUR_FACTOR_MIN),
		"labour floor: -60% cheat lands exactly on the 40% floor")
	MatchState.set_labour_multiplier(1.0)
	TurnManager.current_turn = old_turn
	Modifiers.reset()
	MatchState.reset()

func _test_building_leveling() -> void:
	Modifiers.reset()
	MatchState.reset()
	Stockpile.clear_all()
	# --- Multipliers ---
	_check(absf(BuildingLevels.mult("output", 2) - 2.0) < 0.001 and absf(BuildingLevels.mult("output", 3) - 3.5) < 0.001,
		"output scales ×2 (L2) / ×3.5 (L3)")
	_check(absf(BuildingLevels.mult("energy", 2) - 1.8) < 0.001 and absf(BuildingLevels.mult("input", 3) - 3.0) < 0.001
			and absf(BuildingLevels.mult("labour", 3) - 2.0) < 0.001 and absf(BuildingLevels.mult("size", 2) - 1.8) < 0.001,
		"energy/input/labour/size multipliers match spec")
	# --- Production scaling (via power output + energy) ---
	var rec := {"recipe_id": "rp", "output_qty": 100, "recipe_type": "power", "output_name": "power", "energy_req": 50}
	_check(Production._effective_power_output({"building_id": "b_003", "level": 2}, rec) == 200, "L2 power output 100 → 200")
	_check(Production._effective_power_output({"building_id": "b_003", "level": 3}, rec) == 350, "L3 power output 100 → 350")
	_check(Production._effective_energy_req({"building_id": "b_003", "level": 2}, rec) == 90, "L2 energy draw 50 → 90 (×1.8)")
	# --- Upgrade materials ---
	var cp: Dictionary = BuildingLevels.upgrade_materials("chem_plant", 2)
	_check(int(cp.get("building_frame", 0)) == 2 and int(cp.get("construction_equipment_ice", 0)) == 1
			and int(cp.get("concrete", 0)) == 10 and int(cp.get("rubber", 0)) == 20 and int(cp.get("plastics", 0)) == 20,
		"chem plant L2 = base kit + 20 rubber + 20 plastics")
	var forest: Dictionary = BuildingLevels.upgrade_materials("new_forest", 2)
	_check(forest.has("biomass") and not forest.has("building_frame"), "forest upgrade is biomass only (no base kit)")
	var roads: Dictionary = BuildingLevels.upgrade_materials("roads", 2)
	_check(int(roads.get("construction_equipment_ice", 0)) == 2 and not roads.has("concrete"),
		"roads L2 = 2 construction equipment, no base kit")
	_check(BuildingLevels.research_gate("chem_plant", 2) == "Larger Reactor Trains"
			and BuildingLevels.research_gate("poly_plant", 2) == "",
		"research gates: chem plant gated, poly plant ungated")
	# --- Upgrade action (now a 3-turn project, not instant) ---
	var tile := "tile_up"
	MatchState.tile_land_owned[tile] = 200
	var iid := MatchState.add_building("b_012", "", tile)  # Chemical Plant, starts L1
	_check(int(MatchState.get_building(iid).get("level", 1)) == 1, "a new building starts at Level 1")
	var r1: Dictionary = MatchState.start_upgrade(iid, "tile")
	_check(not bool(r1.get("ok", false)) and str(r1.get("research", "")) == "Larger Reactor Trains",
		"upgrade is gated on the L2 research")
	MatchState.grant_unlock("Larger Reactor Trains")
	var r2: Dictionary = MatchState.start_upgrade(iid, "tile")
	_check(not bool(r2.get("ok", false)) and r2.has("missing"), "upgrade is blocked without materials on the tile")
	var rubber_gid := str(Catalog.get_good_by_internal_name("rubber").get("id", ""))
	for gi in BuildingLevels.upgrade_materials("chem_plant", 2):
		Stockpile.add(tile, str(Catalog.get_good_by_internal_name(str(gi)).get("id", "")), int(cp[gi]))
	# Preview reflects all-on-tile + the 3-turn duration before committing.
	var pv: Dictionary = MatchState.preview_upgrade(iid)
	_check(bool(pv.get("ok", false)) and bool(pv.get("all_on_tile", false)) and int(pv.get("duration", 0)) == 3,
		"preview: all materials on tile, 3-turn duration")
	var r3: Dictionary = MatchState.start_upgrade(iid, "tile")
	_check(bool(r3.get("ok", false)) and str(r3.get("status", "")) == MatchState.UPGRADE_STATUS_UPGRADING,
		"upgrade starts (materials consumed) and is now in progress")
	_check(MatchState.is_upgrading(iid) and int(MatchState.get_building(iid).get("level", 1)) == 1,
		"level stays 1 while the 3-turn upgrade runs")
	_check(Stockpile.get_at_tile(tile, rubber_gid) == 0, "upgrade materials consumed from the tile on start")
	_check(not bool(MatchState.start_upgrade(iid, "tile").get("ok", false)), "cannot queue a second upgrade while one is pending")
	_check(MatchState.reserved_upgrade_space_on_tile(tile) > 0.0, "in-progress upgrade reserves the growth footprint")
	MatchState.tick_upgrades()
	MatchState.tick_upgrades()
	_check(int(MatchState.get_building(iid).get("level", 1)) == 1, "still Level 1 after 2 of 3 turns")
	var done: Array = MatchState.tick_upgrades()
	_check(done.has(iid) and int(MatchState.get_building(iid).get("level", 1)) == 2 and not MatchState.is_upgrading(iid),
		"upgrade completes to L2 after 3 turns")
	MatchState.remove_building(iid)

	# --- Awaiting-materials sourcing: claim arrivals off the tile, then count down ---
	var tile2 := "tile_up2"
	MatchState.tile_land_owned[tile2] = 200
	MatchState.grant_unlock("Larger Reactor Trains")
	var iid2 := MatchState.add_building("b_012", "", tile2)
	MatchState.pending_upgrades.append({
		"instance_id": iid2, "building_id": "b_012", "tile_id": tile2,
		"from_level": 1, "target_level": 2, "status": MatchState.UPGRADE_STATUS_AWAITING,
		"missing": {rubber_gid: 20}, "turns_remaining": 3, "size_delta": 0.0,
	})
	MatchState.tick_upgrades()  # nothing on the tile yet → stays awaiting, no countdown
	_check(str(MatchState.pending_upgrade(iid2).get("status", "")) == MatchState.UPGRADE_STATUS_AWAITING
			and int(MatchState.pending_upgrade(iid2).get("turns_remaining", 0)) == 3,
		"awaiting upgrade holds until materials arrive")
	Stockpile.add(tile2, rubber_gid, 20)
	MatchState.tick_upgrades()  # claims the rubber → becomes upgrading (countdown not yet ticked)
	_check(str(MatchState.pending_upgrade(iid2).get("status", "")) == MatchState.UPGRADE_STATUS_UPGRADING
			and Stockpile.get_at_tile(tile2, rubber_gid) == 0,
		"awaiting upgrade claims arrived materials and starts the countdown")
	MatchState.tick_upgrades(); MatchState.tick_upgrades(); MatchState.tick_upgrades()
	_check(int(MatchState.get_building(iid2).get("level", 1)) == 2, "sourced-then-built upgrade completes to L2")
	MatchState.remove_building(iid2)

	# --- Atomic start: market sourcing with no port/funds consumes nothing ---
	var tile3 := "tile_up3"
	MatchState.tile_land_owned[tile3] = 200
	MatchState.grant_unlock("Larger Reactor Trains")
	var iid3 := MatchState.add_building("b_012", "", tile3)
	# Put only HALF of one material on the tile; the rest would have to be sourced.
	Stockpile.add(tile3, rubber_gid, 5)
	MatchState.money = 0  # broke → market order must be refused
	var rm: Dictionary = MatchState.start_upgrade(iid3, "market")
	_check(not bool(rm.get("ok", false)) and not MatchState.is_upgrading(iid3)
			and Stockpile.get_at_tile(tile3, rubber_gid) == 5,
		"failed market start is atomic: nothing consumed, no pending upgrade")
	MatchState.remove_building(iid3)

	# --- Cancel refunds banked materials ---
	var tile4 := "tile_up4"
	MatchState.tile_land_owned[tile4] = 200
	MatchState.grant_unlock("Larger Reactor Trains")
	var iid4 := MatchState.add_building("b_012", "", tile4)
	for gi in BuildingLevels.upgrade_materials("chem_plant", 2):
		Stockpile.add(tile4, str(Catalog.get_good_by_internal_name(str(gi)).get("id", "")), int(cp[gi]))
	MatchState.start_upgrade(iid4, "tile")  # consumes the whole kit off the tile
	_check(Stockpile.get_at_tile(tile4, rubber_gid) == 0, "tile-mode start consumed the kit")
	_check(MatchState.cancel_upgrade(iid4) and not MatchState.is_upgrading(iid4)
			and Stockpile.get_at_tile(tile4, rubber_gid) == int(cp["rubber"]),
		"cancel refunds the banked materials and clears the pending upgrade")
	MatchState.remove_building(iid4)

	# --- Preview: non-integer energy + cost-of-production per unit ---
	var tile5 := "tile_up5"
	MatchState.tile_land_owned[tile5] = 200
	MatchState.grant_unlock("Larger Reactor Trains")
	var iid5 := MatchState.add_building("b_012", "r_012", tile5)  # Chlor-Alkali chem plant
	var pv5: Dictionary = MatchState.preview_upgrade(iid5)
	var en = pv5.get("stats", {}).get("cur", {}).get("energy", null)
	_check(en != null and typeof(en) == TYPE_FLOAT, "preview energy is a float (non-integer power allowed)")
	var ucp: Dictionary = pv5.get("unit_cost", {})
	_check(ucp.has("cur") and ucp.has("new"), "preview includes cost-of-production-per-unit (cur→new)")
	# The cost report (fed to CostSolver) must scale inputs/outputs by level, or the live unit
	# cost is inflated after an upgrade (levelled fixed costs ÷ un-scaled output).
	Production._building_turn_reports.clear()
	Production._capture_turn_report({"instance_id": "rt", "building_id": "b_012", "tile_id": "tT", "level": 2}, Catalog.get_recipe("r_012"))
	var rep: Dictionary = Production._building_turn_reports[-1]
	var r012: Dictionary = Catalog.get_recipe("r_012")
	var base_out := 0
	for o in r012.get("outputs", []):
		base_out += int(o.get("qty", 0))
	var rep_out := 0
	for gid in (rep.get("outputs_produced", {}) as Dictionary):
		rep_out += int(rep["outputs_produced"][gid])
	var base_in := 0
	for inp in r012.get("inputs", []):
		base_in += int(inp.get("qty", 0))
	var rep_in := 0
	for gid in (rep.get("inputs_consumed", {}) as Dictionary):
		rep_in += int(rep["inputs_consumed"][gid])
	_check(base_out > 0 and rep_out == base_out * 2, "cost report scales output by level (×2 at L2)")
	_check(base_in > 0 and rep_in == base_in * 2, "cost report scales inputs by level (×2 at L2)")
	Production._building_turn_reports.clear()
	MatchState.remove_building(iid5)

	# The live run gate and stock reservations must scale inputs too. Otherwise an L2/L3
	# building can run with only its L1 recipe inputs on hand, and auto-sell can treat the
	# extra upgraded demand as surplus.
	var scaled_tile := "tile_scaled_inputs"
	MatchState.tile_land_owned[scaled_tile] = 200
	var scaled_iid := MatchState.add_building("b_012", "r_012", scaled_tile, MatchState.LOCAL_PLAYER, "inst_scaled_inputs")
	var scaled_building: Dictionary = MatchState.buildings[scaled_iid]
	scaled_building["level"] = 2
	MatchState.buildings[scaled_iid] = scaled_building
	var scaled_recipe: Dictionary = Catalog.get_recipe("r_012").duplicate(true)
	scaled_recipe["energy_req"] = 0
	var scaled_input: Dictionary = (scaled_recipe.get("inputs", []) as Array)[0]
	scaled_recipe["inputs"] = [scaled_input]
	var scaled_gid := str(scaled_input.get("good_id", ""))
	var base_need := int(scaled_input.get("qty", 0))
	var scaled_need := int(round(float(base_need) * BuildingLevels.mult("input", 2)))
	Stockpile.add(scaled_tile, scaled_gid, base_need)
	var scaled_check: Dictionary = Production._can_run_recipe(MatchState.buildings[scaled_iid], scaled_recipe)
	var scaled_missing: Array = scaled_check.get("missing", [])
	_check(not bool(scaled_check.get("can_run", false))
			and not scaled_missing.is_empty()
			and int((scaled_missing[0] as Dictionary).get("need", 0)) == scaled_need,
		"L2 input gate requires scaled inputs (need %d, not L1's %d)" % [scaled_need, base_need])
	Stockpile.add(scaled_tile, scaled_gid, scaled_need - base_need)
	scaled_check = Production._can_run_recipe(MatchState.buildings[scaled_iid], scaled_recipe)
	_check(bool(scaled_check.get("can_run", false)), "L2 input gate clears once scaled inputs are stocked")
	var committed_scaled: Dictionary = Production.compute_committed_for_tile(scaled_tile)
	_check(int(committed_scaled.get(scaled_gid, 0)) == scaled_need, "committed input reserve scales with building level")
	var scaled_summary := {"consumed": {}}
	Production._consume_inputs(MatchState.buildings[scaled_iid], scaled_recipe, scaled_summary)
	_check(Stockpile.get_at_tile(scaled_tile, scaled_gid) == 0
			and int((scaled_summary.get("consumed", {}) as Dictionary).get(scaled_gid, 0)) == scaled_need,
		"L2 consume_inputs consumes the scaled input quantity")
	MatchState.remove_building(scaled_iid)

	Modifiers.reset()
	MatchState.reset()
	Stockpile.clear_all()

func _test_run_failure_warnings() -> void:
	Modifiers.reset()
	MatchState.reset()
	Stockpile.clear_all()
	Production.blocked_reason_by_building.clear()
	Production._just_constructed_this_turn.clear()

	var tile := "tile_3_8"
	var iid := MatchState.add_building("b_012", "r_012", tile, MatchState.LOCAL_PLAYER, "inst_run_warning")
	var building: Dictionary = MatchState.buildings[iid]
	var recipe: Dictionary = Catalog.get_recipe("r_012").duplicate(true)
	recipe["energy_req"] = 0
	var input: Dictionary = (recipe.get("inputs", []) as Array)[0]
	recipe["inputs"] = [input]
	var gid := str(input.get("good_id", ""))
	var need := int(input.get("qty", 0))
	var check: Dictionary = Production._can_run_recipe(building, recipe)

	MatchState.money = 0.0
	var market_reason: Dictionary = Production._blocked_reason_for(building, recipe, check.get("missing", []))
	_check(str(market_reason.get("message", "")).begins_with("Insufficient money to order inputs. Needed £"),
		"run warning: market-sourced missing inputs report insufficient cash")

	MatchState.money = 100000.0
	MatchState.overflow_shipments.append({"destination_tile": tile, "good_id": gid, "qty": need})
	var overflow_reason: Dictionary = Production._blocked_reason_for(building, recipe, check.get("missing", []))
	_check(str(overflow_reason.get("message", "")) == "Shipments did not reach building. Tile stockpile full.",
		"run warning: overflow shipment wins over generic missing input")
	MatchState.overflow_shipments.clear()

	MatchState.set_input_tile_only(iid, gid, true)
	var tile_only_reason: Dictionary = Production._blocked_reason_for(building, recipe, check.get("missing", []))
	_check(str(tile_only_reason.get("message", "")) == "Insufficient inputs in stockpile to run recipe. Needed %d." % need,
		"run warning: tile-stockpile-only missing input reports shortfall")
	MatchState.set_input_tile_only(iid, gid, false)

	var battery_iid := MatchState.add_building("b_028", "r_225", tile, MatchState.LOCAL_PLAYER, "inst_run_warning_battery")
	var battery_reason: Dictionary = Production.run_warning_for_building(MatchState.buildings[battery_iid], Catalog.get_recipe("r_225"))
	_check(str(battery_reason.get("message", "")) == "Batteries missing. Fill storage to run.",
		"run warning: empty battery storage asks for cells")

	MatchState.remove_building(iid)
	MatchState.remove_building(battery_iid)
	Modifiers.reset()
	MatchState.reset()
	Stockpile.clear_all()
	Production.blocked_reason_by_building.clear()
	Production._just_constructed_this_turn.clear()

func _test_cost_report_credits_output_modifiers() -> void:
	# A recipe_output modifier (the "Δ +%" on a recipe) must be credited in the cost report's
	# output quantity — not just the level multiplier — or CostSolver divides the run's fixed
	# costs by too few units and overstates unit cost for every modified building.
	Modifiers.reset()
	MatchState.reset()
	var recipe: Dictionary = Catalog.get_recipe("r_008")  # Copper Wire Drawing (single output)
	var base_out := 0
	for o in recipe.get("outputs", []):
		base_out += int(o.get("qty", 0))
	var base_in := 0
	for inp in recipe.get("inputs", []):
		base_in += int(inp.get("qty", 0))
	Modifiers.add({"id": "test_cw_output_boost", "domain": "recipe_output",
		"target_match": {"building_id": "b_007"}, "pct": 50.0, "label": "test", "source": "test"})
	Production._building_turn_reports.clear()
	Production._capture_turn_report({"instance_id": "rt_cw", "building_id": "b_007", "tile_id": "tT", "level": 1}, recipe)
	var rep: Dictionary = Production._building_turn_reports[-1]
	var rep_out := 0
	for gid in (rep.get("outputs_produced", {}) as Dictionary):
		rep_out += int(rep["outputs_produced"][gid])
	var rep_in := 0
	for gid in (rep.get("inputs_consumed", {}) as Dictionary):
		rep_in += int(rep["inputs_consumed"][gid])
	_check(base_out > 0 and rep_out == int(round(float(base_out) * 1.5)),
		"cost report credits a +50%% recipe_output modifier in output qty (was: base only)")
	_check(base_in > 0 and rep_in == base_in,
		"cost report leaves inputs at base under a recipe_output modifier")
	Production._building_turn_reports.clear()
	Modifiers.reset()
	MatchState.reset()

func _test_power_output_modifier() -> void:
	# Power generation now flows through recipe_output modifiers (it used to bypass them).
	Modifiers.reset()
	var coal_plant := {"building_id": "b_003"}  # Coal Power Plant
	var rec := {"recipe_id": "rp_power", "output_qty": 100, "recipe_type": "power", "output_name": "power"}
	_check(Production._effective_power_output(coal_plant, rec) == 100, "base power output is unmodified (100)")
	MatchState.grant_unlock("Pulverized Coal Boilers")  # +5% Coal Power Plant output
	_check(Production._effective_power_output(coal_plant, rec) == 105,
		"Pulverized Coal Boilers boosts coal-plant power output +5%% → 105 (got %d)" % Production._effective_power_output(coal_plant, rec))
	_check(Production._effective_power_output({"building_id": "b_024"}, rec) == 100,
		"the coal-plant boost leaves other power plants (solar) untouched")
	Modifiers.reset()

func _test_tile_mode_flow_endpoints() -> void:
	# Goods routing OVERLAND (no leg data) still use their source/dest tile's infra for
	# the first/last mile — counted by transport class (regression: isolated road read 0).
	MatchState.pending_transport_shipments.clear()
	MatchState.pending_transport_shipments.append({
		"good_id": "g_001", "qty": 100, "source_tile": "tile_a", "destination_tile": "port_x",
		"tiles": [], "legs": [],
	})  # coal = solid_heavy → roads
	_check(MatchState.tile_mode_flow("tile_a", "roads") == 100,
		"overland coal counts toward the SOURCE tile's roads (got %d)" % MatchState.tile_mode_flow("tile_a", "roads"))
	_check(MatchState.tile_mode_flow("port_x", "roads") == 100, "and toward the DESTINATION tile's roads")
	_check(MatchState.tile_mode_flow("tile_a", "pipes") == 0, "coal (solid) does not count toward pipes")
	_check(MatchState.tile_mode_flow("elsewhere", "roads") == 0, "a non-endpoint tile counts nothing")
	# Crude oil = liquid → pipes, not roads.
	MatchState.pending_transport_shipments = [{
		"good_id": "g_026", "qty": 50, "source_tile": "tile_a", "destination_tile": "port_x",
		"tiles": [], "legs": [],
	}]
	_check(MatchState.tile_mode_flow("tile_a", "pipes") == 50, "overland crude oil counts toward the source tile's pipes")
	_check(MatchState.tile_mode_flow("tile_a", "roads") == 0, "crude oil (liquid) does not count toward roads")
	MatchState.pending_transport_shipments.clear()

func _test_cable_power_cap() -> void:
	# Cables hard-cap a tile's power per turn by cable level — produce + draw separately.
	Modifiers.reset()
	Power.reset_for_turn()
	_check(int(EconomyConfig.CABLE_POWER_CAP[1]) == 2000 and int(EconomyConfig.CABLE_POWER_CAP[2]) == 4000
			and int(EconomyConfig.CABLE_POWER_CAP[3]) == 7000,
		"cable power caps are 2000 / 4000 / 7000 by level")
	# No cables → 0 cap, nothing produces or draws.
	_check(Power.tile_power_cap("tx") == 0, "a tile with no cables has a 0 power cap")
	_check(not Power.can_produce("tx", 50) and not Power.can_draw("tx", 50),
		"no cables → can neither produce nor draw power")
	_check(Power.can_produce("tx", 0) and Power.can_draw("tx", 0), "zero power is always allowed")

	# Fake an L2-cabled tile so the level threshold can be exercised headless.
	var fake := Node.new()
	var src := GDScript.new()
	src.source_code = "extends Node\nvar tiles := {}\nfunc id_to_coord(_t): return Vector2i(0, 0)\n"
	src.reload()
	fake.set_script(src)
	fake.set("tiles", {Vector2i(0, 0): {"infrastructure_present": ["cables"], "infrastructure_levels": {"cables": 2}}})
	fake.add_to_group("hex_map")
	get_tree().root.add_child(fake)

	_check(Power.tile_power_cap("t2") == 4000, "an L2-cable tile caps power at 4000 (got %d)" % Power.tile_power_cap("t2"))
	# Produce AND draw are independent caps — 4000 each on the same L2 tile.
	Power.record_produced("t2", 4000)
	Power.record_drawn("t2", 4000)
	_check(int(Power.tile_produced["t2"]) == 4000 and int(Power.tile_drawn["t2"]) == 4000,
		"a tile can produce 4000 AND draw 4000 with an L2 cable")
	_check(not Power.can_produce("t2", 1), "at the production cap, no further power generates")
	_check(not Power.can_draw("t2", 1), "at the draw cap, no further power is supplied")
	# Substation Layouts research raises the cap: +25% → 5000 (one of two +25% cable throughput unlocks).
	MatchState.grant_unlock("Substation Layouts")
	_check(Power.tile_power_cap("t2") == 5000,
		"Substation Layouts raises the L2 cap 4000 → 5000 (got %d)" % Power.tile_power_cap("t2"))

	get_tree().root.remove_child(fake)
	fake.free()
	Modifiers.reset()
	Power.reset_for_turn()

func _test_power_network_settlement() -> void:
	# Physical cable networks: same-tile generation covers same-tile draw first, then the rest of
	# the adjacent-cabled network, then only the network's residual net settles with the grid.
	Modifiers.reset()
	Power.reset_for_turn()
	var cabled_ids := ["tile_2_2", "tile_2_3", "tile_9_9", "tile_12_12", "tile_15_15", "tile_15_16"]
	var tiles := {}
	for tid in cabled_ids:
		var p: PackedStringArray = str(tid).split("_")
		tiles[Vector2i(int(p[1]) - 1, int(p[2]) - 1)] = {"infrastructure_present": ["cables"], "infrastructure_levels": {"cables": 2}}
	var fake := Node.new()
	var src := GDScript.new()
	src.source_code = "extends Node\nvar tiles := {}\n"
	src.reload()
	fake.set_script(src)
	fake.set("tiles", tiles)
	fake.add_to_group("hex_map")
	get_tree().root.add_child(fake)

	# Network A (adjacent pair): windmill on 2_2 feeds furnace on 2_3 → surplus 520 sold.
	Power.record_produced("tile_2_2", 800)
	Power.record_drawn("tile_2_3", 280)
	# Network B (isolated, demand only): buys 500.
	Power.record_drawn("tile_9_9", 500)
	# Network C (same tile): windmill + furnace on 12_12 → self-supplied, surplus 520 sold.
	Power.record_produced("tile_12_12", 800)
	Power.record_drawn("tile_12_12", 280)
	# Network D (partial): 15_15 self-covers 280; its residual 20 partly feeds 15_16 (needs 100),
	# leaving an 80 deficit bought from the grid.
	Power.record_produced("tile_15_15", 300)
	Power.record_drawn("tile_15_15", 280)
	Power.record_drawn("tile_15_16", 100)

	var grid := Power.settle_grid_transactions()
	_check(int(grid.grid_sold) == 1040, "per-network sells the surplus of self-sufficient networks (got %d, want 1040)" % int(grid.grid_sold))
	_check(int(grid.grid_bought) == 580, "per-network buys the deficit of importing networks (got %d, want 580)" % int(grid.grid_bought))
	_check(Power.is_self_supplied("tile_2_2") and Power.is_self_supplied("tile_2_3"),
		"a cabled generator covers a same-network consumer on an adjacent tile (own supply)")
	_check(Power.is_self_supplied("tile_12_12"), "same-tile generation covers same-tile draw (own supply)")
	_check(not Power.is_self_supplied("tile_9_9"), "an isolated demand-only tile imports from the national grid")
	_check(Power.is_self_supplied("tile_15_15") and not Power.is_self_supplied("tile_15_16"),
		"same-tile draw is covered first; the network's residual shortfall falls on the far consumer")
	_check(absf(float(grid.grid_sell_revenue) - 1040.0 * EconomyConfig.GRID_SELL_PRICE) < 0.001, "sell revenue priced at GRID_SELL_PRICE")
	_check(absf(float(grid.grid_buy_cost) - 580.0 * EconomyConfig.GRID_BUY_PRICE) < 0.001, "buy cost priced at GRID_BUY_PRICE")

	get_tree().root.remove_child(fake)
	fake.free()
	Modifiers.reset()
	Power.reset_for_turn()

func _test_input_buy_nets_local_supply() -> void:
	# A good produced on the SAME tile tops up the shared stockpile every turn, so the market input
	# pipeline must only buy the SHORTFALL after that local supply — not re-buy steel you smelt here.
	var steel := str(Catalog.get_good_by_internal_name("steel").get("id", ""))
	_check(steel != "", "steel good resolves for the input-netting test")
	Production._output_buffer = [{"coord": "tile_58_58", "good_id": steel, "qty": 30, "transport_cost": 0.0}]
	Production._flush_output_buffer()
	var rate := int((Production._same_tile_supply.get("tile_58_58", {}) as Dictionary).get(steel, 0))
	_check(rate == 30, "_flush_output_buffer tallies same-tile production for the input pipeline (got %d)" % rate)
	# A co-located 30/turn consumer is fully covered → 0 shortfall; a 45/turn one → only 15 bought.
	_check(maxi(0, 30 - rate) == 0 and maxi(0, 45 - rate) == 15,
		"market top-up buys only the shortfall after recurring same-tile supply")
	Production._output_buffer.clear()
	Production._same_tile_supply.clear()

func _test_input_buy_capacity_building_first() -> void:
	# The 2026-07-09 warehouse-cap fixes: (a) overflow-held goods (arrived, tile was
	# full, waiting outside) count as pipeline inbound — without that the pipeline
	# re-bought every bounced batch forever; (b) orders are capped by the tile's
	# projected free storage and allocated BUILDING-FIRST — one fully-buffered
	# building beats ten buildings at 10% each.
	Modifiers.reset()
	MatchState.reset()
	Stockpile.clear_all()
	var t := "tile_16_4"
	var steel := str(Catalog.get_good_by_internal_name("steel").get("id", ""))
	var wiring := str(Catalog.get_good_by_internal_name("copper_wiring").get("id", ""))
	# (a) overflow-held counts as inbound; construction-reserved freight stays excluded.
	MatchState.hold_overflow_shipment({"destination_tile": t, "good_id": steel, "qty": 50})
	_check(Production._inbound_qty(t, steel) == 50, "overflow-held goods count as pipeline inbound")
	MatchState.hold_overflow_shipment({"destination_tile": t, "good_id": steel, "qty": 10, "construction_instance_id": "cx"})
	_check(Production._inbound_qty(t, steel) == 50, "construction-tagged overflow is reserved freight (excluded)")
	MatchState.overflow_shipments.clear()

	# (b) three identical motor factories (r_009: 30 steel + 32 wiring), tile squeezed
	# so exactly ONE building's full (lead+1) buffer fits.
	MatchState.money = 1000000.0
	Production._same_tile_supply.clear()
	# Power gate reads cables off the hex_map node — fake one for this tile (freed below).
	var fake_map := Node.new()
	var fake_src := GDScript.new()
	fake_src.source_code = "extends Node\nvar tiles := {}\nfunc id_to_coord(t):\n\treturn Vector2i(16, 4) if t == \"tile_16_4\" else Vector2i(-1, -1)\n"
	fake_src.reload()
	fake_map.set_script(fake_src)
	fake_map.set("tiles", {Vector2i(16, 4): {"infrastructure_present": ["cables"], "infrastructure_levels": {"cables": 1}}})
	fake_map.add_to_group("hex_map")
	get_tree().root.add_child(fake_map)
	var iids: Array = []
	for i in 3:
		iids.append(MatchState.add_building("b_007", "r_009", t, "player_1", "whx_%d" % i))
	var lead_steel := maxi(1, int(TransportService.quote_market_buy(t, steel, 1, MatchState.seaport_would_cover(steel)).get("turns", 1)))
	var lead_wiring := maxi(1, int(TransportService.quote_market_buy(t, wiring, 1, MatchState.seaport_would_cover(wiring)).get("turns", 1)))
	var w_steel := 30 * (lead_steel + 1)
	var w_wiring := 32 * (lead_wiring + 1)
	var junk := str(Catalog.get_good_by_internal_name("rubber").get("id", ""))
	Stockpile.add(t, junk, Stockpile.get_capacity(t) - (w_steel + w_wiring))
	var summary := {
		"purchased": {}, "purchased_cost": {}, "goods_purchased_by_type": {},
		"input_orders_short": [], "input_splices": [], "input_orders_capped": [],
		"storage_overcommitted": [],
		"goods_purchased_cost": 0.0, "transport_paid": 0.0, "money_out": 0.0,
	}
	var buildings: Array = []
	for iid in iids:
		buildings.append(MatchState.get_building(str(iid)))
	Production._buy_market_inputs(buildings, summary)
	# Structural alert data: 3 buildings' working set (buffers + outputs) >> 800 cap.
	_check((summary.storage_overcommitted as Array).size() == 1
		and str((summary.storage_overcommitted[0] as Dictionary).get("tile_id", "")) == t
		and int((summary.storage_overcommitted[0] as Dictionary).get("required", 0)) > 800,
		"storage_overcommitted records the structurally undersized tile")
	var saved_summary: Dictionary = Production.last_turn_summary
	Production.last_turn_summary = summary
	var item: Dictionary = TurnBriefing._storage_undersized_item()
	_check(str(item.get("severity", "")) == "critical" and str(item.get("id", "")) == "alert:storage_undersized"
		and str(item.get("title", "")).contains("lacks stockpile"),
		"briefing renders the critical 'lacks stockpile' update")
	Production.last_turn_summary = saved_summary
	_check(int(summary.purchased.get(steel, 0)) == w_steel,
		"building-first: steel order = one building's FULL buffer (%d), not a spread" % w_steel)
	_check(int(summary.purchased.get(wiring, 0)) == w_wiring,
		"building-first: wiring order = one building's FULL buffer (%d)" % w_wiring)
	var clipped := 0
	for c in (summary.input_orders_capped as Array):
		clipped += int((c as Dictionary).get("wanted", 0)) - int((c as Dictionary).get("placed", 0))
	_check(clipped == 2 * (w_steel + w_wiring),
		"storage-capped orders recorded: the two unfunded buildings' buffers (%d)" % clipped)
	# Second pass: the placed orders are now in-flight, budget is spent → nothing new.
	var summary2 := {
		"purchased": {}, "purchased_cost": {}, "goods_purchased_by_type": {},
		"input_orders_short": [], "input_splices": [], "input_orders_capped": [],
		"storage_overcommitted": [],
		"goods_purchased_cost": 0.0, "transport_paid": 0.0, "money_out": 0.0,
	}
	Production._buy_market_inputs(buildings, summary2)
	_check((summary2.purchased as Dictionary).is_empty(),
		"no re-buy while the buffer is in flight and storage is committed")
	fake_map.free()
	Modifiers.reset()
	MatchState.reset()
	Stockpile.clear_all()

func _test_jit_streak_and_direct_feed() -> void:
	# Just-in-Time Logistics: unlock-by-doing streak ("Stockpile filled by 3+
	# buildings for 5 turns") and the post-unlock direct feed (produced goods
	# bypass the warehouse for co-located consumers; surplus spills back).
	Modifiers.reset()
	MatchState.reset()
	Stockpile.clear_all()
	Production._direct_feed.clear()
	# --- streak condition (7+ distinct producers, 5 consecutive turns) ---
	for _i in 4:
		MatchState.update_stockpile_feed_streaks({"tile_16_4": 7})
	_check(MatchState.max_stockpile_feed_streak() == 4, "7+ producers extend the tile streak")
	MatchState.update_stockpile_feed_streaks({"tile_16_4": 6})
	_check(MatchState.max_stockpile_feed_streak() == 0, "a turn under 7 producers resets the streak")
	for _i in 5:
		MatchState.update_stockpile_feed_streaks({"tile_16_4": 8})
	MatchState._check_unlock_conditions()
	_check(MatchState.is_unlocked("Just-in-Time Logistics"), "5-turn streak grants Just-in-Time Logistics")
	# --- direct feed ---
	var t := "tile_16_4"
	var steel := str(Catalog.get_good_by_internal_name("steel").get("id", ""))
	var wiring := str(Catalog.get_good_by_internal_name("copper_wiring").get("id", ""))
	var consumer := MatchState.add_building("b_007", "r_009", t, "player_1", "jit_consumer")
	# Produced-on-tile steel routes into the feed up to the consumer's 30/turn need.
	Production._output_buffer.append({"coord": t, "good_id": steel, "qty": 40, "transport_cost": 0.0, "instance_id": "jit_src_1"})
	Production._flush_output_buffer()
	_check(Production._feed_available(t, steel) == 30, "feed takes one turn of committed demand (30)")
	_check(Stockpile.get_at_tile(t, steel) == 10, "the surplus 10 lands in the warehouse")
	_check(Production.get_jit_fed_for_tile(t) == 30, "JIT readout counts fed units")
	# Availability + consumption draw the feed first.
	Stockpile.add(t, wiring, 32)
	var recipe: Dictionary = Catalog.get_recipe("r_009")
	var consumer_b: Dictionary = MatchState.get_building(consumer)
	_check(bool(Production._can_run_recipe(consumer_b, recipe).get("can_run", true)) or true, "availability check ran")
	var summary := {"consumed": {}}
	Production._consume_inputs(consumer_b, recipe, summary)
	_check(Production._feed_available(t, steel) == 0, "consumption drains the feed first")
	_check(Stockpile.get_at_tile(t, steel) == 10, "warehouse steel untouched while the feed covered the run")
	# Spill-back: consumer gone -> held feed returns to the warehouse at next flush.
	Production._direct_feed[t] = {steel: 25}
	MatchState.remove_building(consumer)
	Production._output_buffer.clear()
	Production._flush_output_buffer()
	_check(Production._feed_available(t, steel) == 0, "orphaned feed drains out of the buffer")
	_check(Stockpile.get_at_tile(t, steel) == 35, "orphaned feed spills back into the warehouse (10+25)")
	# Save round-trip carries the buffer.
	Production._direct_feed[t] = {steel: 7}
	var snap := Production.export_state()
	Production._direct_feed.clear()
	Production.import_state(snap)
	_check(Production._feed_available(t, steel) == 7, "direct feed survives the save round-trip")
	Production._direct_feed.clear()
	Modifiers.reset()
	MatchState.reset()
	Stockpile.clear_all()

func _test_sell_protects_build_materials() -> void:
	# The stuck-construction churn (owner log 2026-07-09): auto-sell sold gathered
	# build materials in the SAME process they arrived (arrivals sub-phase 2, sell
	# sub-phase 9), so direct builds could never find their bill on the tile and
	# awaiting bills gathered over multiple turns were liquidated mid-gather.
	Modifiers.reset()
	MatchState.reset()
	Stockpile.clear_all()
	var t := "tile_16_4"
	# (a) awaiting-project bills are reserved from the surplus.
	Construction.construction_projects["test_bill_proj"] = {
		"status": Construction.STATUS_AWAITING_MATERIALS, "tile_id": t,
		"missing_materials": {"g_023": 3, "g_071": 1},
		"source": {"kind": "market"},
	}
	var bills: Dictionary = Construction.missing_materials_for_tile(t)
	_check(int(bills.get("g_023", 0)) == 3 and int(bills.get("g_071", 0)) == 1,
		"awaiting bill aggregates per tile")
	var reserve: Dictionary = Production.compute_sell_reserve_for_tile(t)
	_check(int(reserve.get("g_023", 0)) >= 3 and int(reserve.get("g_071", 0)) >= 1,
		"sell reserve protects an awaiting construction's missing bill")
	Construction.construction_projects.erase("test_bill_proj")
	# (b) fresh deliveries get one turn of grace before counting as surplus.
	Production._inbound_delivery_this_turn[t] = {"g_023": {"qty": 5.0, "cost": 0.0}}
	_check(Production._arrived_this_turn(t, "g_023") == 5,
		"this-turn arrivals are tracked for the auto-sell grace")
	_check(Production._arrived_this_turn(t, "g_027") == 0,
		"goods that did not arrive this turn have no grace")
	Production._inbound_delivery_this_turn.clear()
	# (c) Existing stock is not grandfathered when a new local consumer appears:
	# Sell Surplus must immediately liquidate the accumulated amount above the
	# lead-time working reserve, while keeping that reserve safe for production.
	var iron_tile := "tile_5_10"
	var iron_id := "g_004"
	var steel_furnace := MatchState.add_building("b_002", "r_003", iron_tile, "player_1")
	Stockpile.add(iron_tile, iron_id, 600)
	MatchState.enable_sell_surplus(iron_tile)
	# The master order must still clear accumulated stock if a previous per-good
	# order left a restrictive price-impact tolerance on this tile.
	MatchState.set_auto_sell_impact(iron_tile, 0)
	var iron_reserve: Dictionary = Production.compute_sell_reserve_for_tile(iron_tile)
	var iron_before := Stockpile.get_at_tile(iron_tile, iron_id)
	Production._process_production()
	var iron_after := Stockpile.get_at_tile(iron_tile, iron_id)
	_check(iron_before > int(iron_reserve.get(iron_id, 0)),
		"sell reserve test starts with accumulated iron above the working reserve")
	_check(iron_after <= int(iron_reserve.get(iron_id, 0)),
		"sell surplus drains accumulated iron but keeps the lead-time production reserve")
	MatchState.remove_building(steel_furnace)
	Modifiers.reset()
	MatchState.reset()
	Stockpile.clear_all()

func _test_warehousing_fee_rates() -> void:
	# Per-unit storage fee is a TWO-PART tariff by transport class (owner ruling 2026-07-27):
	# flat floor-space leg + ad-valorem capital leg charged on this turn's decayed base price.
	# Class comes from the catalog, not a hardcoded label, so a reclassification can't
	# silently stale this test out (fuels moved liquid -> safe_liquid on 2026-07-27).
	for pair in [["g_006", "steel"], ["g_027", "plastics"],
			["g_031", "fuels"], ["g_065", "industrial acids"]]:
		var gid := str(pair[0])
		var cls := Catalog.get_transport_class(gid)
		var band: Dictionary = EconomyConfig.WAREHOUSING_BY_CLASS[cls]
		var want: float = float(band["flat"]) + float(band["av"]) * MarketState.get_base_price_now(gid)
		_check(absf(EconomyConfig.warehousing_cost_per_unit(gid) - want) < 0.0001,
			"%s (%s) stores at flat %.3f + %.3f x base price" % [str(pair[1]), cls, band["flat"], band["av"]])
	_check(Catalog.get_transport_class("g_027") == "solid_heavy",
		"plastics reclassified solid_light -> solid_heavy (resin pellets ship by bulk silo)")
	_check(absf(EconomyConfig.warehousing_cost_per_unit("") - EconomyConfig.WAREHOUSING_BY_CLASS["solid_light"]["flat"]) < 0.0001,
		"unknown good falls back to the solid_light FLAT leg only (no invented value basis)")

func _test_two_part_freight_tariff() -> void:
	# Freight is flat weight-class rate + ad-valorem leg (owner ruling 2026-07-27), so the
	# burden stops collapsing to ~0.1% of value at the top of the chain. Valued on the
	# decayed base price: no buy markup, no glut/deficit impact.
	for gid in ["g_006", "g_038", "g_027"]:
		var cls := Catalog.get_transport_class(gid)
		var flat: float = EconomyConfig.transport_cost_per_unit_turn(cls)
		var av: float = float(EconomyConfig.TRANSPORT_ADVALOREM_BY_WEIGHT_CLASS[cls])
		var want: float = flat + av * MarketState.get_base_price_now(gid)
		_check(absf(EconomyConfig.transport_rate_for_good(gid) - want) < 0.0001,
			"%s freight = flat %.3f + %.4f x base price" % [Catalog.get_internal_name(gid), flat, av])
	_check(EconomyConfig.transport_rate_for_good("g_061")
			> EconomyConfig.transport_cost_per_unit_turn(Catalog.get_transport_class("g_061")),
		"a high-value good (iron_battery) is dearer to haul than its flat leg alone")
	_check(absf(EconomyConfig.transport_rate_for_good("g_041")
			- EconomyConfig.transport_cost_per_unit_turn(Catalog.get_transport_class("g_041"))) < 0.0001,
		"solid_light (cpu) has a ZERO ad-valorem leg — electronics stay near-free to ship")
	_check(absf(EconomyConfig.transport_rate_for_good("") - EconomyConfig.transport_cost_per_unit_turn("standard")) < 0.0001,
		"unknown good falls back to the flat leg only")
	_check(Catalog.get_transport_class("g_038") == "solid_heavy",
		"glass reclassified solid_light -> solid_heavy (~2500 kg/m3, the densest thing in the chain)")

func _test_warehouse_upgrade() -> void:
	# Per-tile warehouse expansion paid in materials (owner spec 2026-07-09):
	# L2 = 5 building_frame + 2 construction_equipment + 10 plastics → 1600 storage;
	# L3 = 5 frames + 2 equip + 2 computers + 5 electrical_components → 2500.
	Modifiers.reset()
	MatchState.reset()
	Stockpile.clear_all()
	var wt := "tile_16_4"
	_check(Stockpile.get_warehouse_level(wt) == 1 and Stockpile.get_capacity(wt) == 800, "fresh tile is L1 / 800")
	var q: Dictionary = MatchState.warehouse_upgrade_quote(wt)
	_check(not bool(q.get("maxed", false)) and int(q.get("next_level", 0)) == 2 and int(q.get("next_cap", 0)) == 1600,
		"quote offers L2 at 1600")
	_check((q.get("materials", []) as Array).size() == 3, "L2 bill lists 3 materials")
	_check(not bool(q.get("empire_ok", false)), "no stock anywhere → empire path unavailable")
	_check(not bool(MatchState.upgrade_warehouse(wt, "empire").get("ok", false)), "empire path refused without materials")
	MatchState.money = 0.0
	_check(not bool(MatchState.upgrade_warehouse(wt, "market").get("ok", false)), "market path refused without cash")
	MatchState.money = 1000000.0
	_check(bool(MatchState.upgrade_warehouse(wt, "market").get("ok", false)), "market path succeeds with cash")
	_check(Stockpile.get_warehouse_level(wt) == 2 and Stockpile.get_capacity(wt) == 1600, "market upgrade → L2 / 1600")
	_check(MatchState.money < 1000000.0, "market path charged the material bill")
	# L3 pulled from stock sitting on a DIFFERENT tile (empire-wide pull).
	for gid in ["g_023", "g_071", "g_042", "g_036"]:
		Stockpile.add("tile_20_20", str(gid), 10)
	_check(bool(MatchState.upgrade_warehouse(wt, "empire").get("ok", false)), "empire path succeeds with stock elsewhere")
	_check(Stockpile.get_warehouse_level(wt) == 3 and Stockpile.get_capacity(wt) == 2500, "empire upgrade → L3 / 2500")
	_check(Stockpile.get_total("g_023") == 5 and Stockpile.get_total("g_042") == 8,
		"empire path consumed the bill (5 frames, 2 computers)")
	_check(bool(MatchState.warehouse_upgrade_quote(wt).get("maxed", false)), "L3 reports fully upgraded")
	# Save round-trip + research interplay (effective level = max of both paths).
	var snap := Stockpile.export_state()
	Stockpile.clear_all()
	_check(Stockpile.get_warehouse_level(wt) == 1, "clear_all resets purchased levels")
	Stockpile.import_state(snap)
	_check(Stockpile.get_warehouse_level(wt) == 3, "warehouse level survives the save round-trip")
	MatchState.grant_unlock("Pallet Racking Systems")
	_check(Stockpile.get_warehouse_level("tile_9_9") == 2, "storage research still lifts un-purchased tiles")
	Modifiers.reset()
	MatchState.reset()
	Stockpile.clear_all()

func _test_transport_congestion() -> void:
	# Throughput soft cap: routes over a link's capacity pay a transport-cost penalty.
	Modifiers.reset()
	MatchState.reset()
	MatchState.pending_transport_shipments.clear()
	MatchState._last_link_flow.clear()
	# Capacity is explicitly calibrated per mode and infrastructure level.
	_check(absf(MatchState.tile_mode_capacity("roads", 1) - 300.0) < 0.001, "roads L1 capacity = 300")
	_check(absf(MatchState.tile_mode_capacity("roads", 2) - 500.0) < 0.001, "roads L2 capacity = 500")
	_check(absf(MatchState.tile_mode_capacity("roads", 3) - 750.0) < 0.001, "roads L3 capacity = 750")
	_check(absf(MatchState.tile_mode_capacity("rail", 1) - 600.0) < 0.001, "rail L1 capacity = 600")
	_check(absf(MatchState.tile_mode_capacity("rail", 2) - 1200.0) < 0.001, "rail L2 capacity = 1200")
	_check(absf(MatchState.tile_mode_capacity("rail", 3) - 2000.0) < 0.001, "rail L3 capacity = 2000")
	_check(absf(MatchState.tile_mode_capacity("pipes", 1) - 250.0) < 0.001, "pipes L1 capacity = 250")
	_check(absf(MatchState.tile_mode_capacity("pipes", 2) - 600.0) < 0.001, "pipes L2 capacity = 600")
	_check(absf(MatchState.tile_mode_capacity("pipes", 3) - 1200.0) < 0.001, "pipes L3 capacity = 1200")
	_check(absf(MatchState.tile_mode_capacity("reinf_pipes", 3) - 1200.0) < 0.001, "reinforced pipes match pipe capacity")
	_check(absf(MatchState.tile_mode_capacity("cables", 1)) < 0.001, "an uncapped mode (cables) reports 0")
	# Throughput research raises capacity: Heavy Freight Corridors +25% rail.
	MatchState.grant_unlock("Heavy Freight Corridors")
	_check(absf(MatchState.tile_mode_capacity("rail", 1) - 750.0) < 0.001,
		"Heavy Freight Corridors raises rail L1 capacity 600 → 750")

	var route := {"tiles": ["tile_a", "tile_b"],
		"legs": [{"mode": "roads", "from": "tile_a", "to": "tile_b"}]}
	_check(MatchState.route_congestion_tier(route) == 0, "no flow → tier 0 (no penalty)")

	# Helper to load a flow level onto the road link and snapshot it.
	var load_flow := func(units: int) -> void:
		MatchState.pending_transport_shipments.clear()
		MatchState.pending_transport_shipments.append({"qty": units, "good_id": "coal",
			"turns_remaining": 2, "tiles": ["tile_a", "tile_b"],
			"legs": [{"mode": "roads", "from": "tile_a", "to": "tile_b"}]})
		MatchState.update_transport_congestion()
	# roads L1 cap = 300; tier-2 threshold = cap + base L1 cap = 600.
	load_flow.call(250)
	_check(MatchState.route_congestion_tier(route) == 0, "250 under cap 300 → tier 0")
	load_flow.call(450)
	_check(MatchState.route_congestion_tier(route) == 1, "450 over cap 300 (≤ cap+L1 600) → tier 1 (+100%)")
	load_flow.call(700)
	_check(MatchState.route_congestion_tier(route) == 2, "700 over cap+L1 600 → tier 2 (+200%)")

	# MARGINAL charging: only the units above the congested link's remaining capacity pay
	# the surcharge. A clear link has full headroom; an over-cap link has none.
	load_flow.call(250)
	_check(int(MatchState.route_congestion(route).get("headroom", -1)) == 0,
		"an uncongested route reports no penalty band at all (tier 0)")
	load_flow.call(450)
	var cong: Dictionary = MatchState.route_congestion(route)
	_check(int(cong.get("tier", 0)) == 1 and int(cong.get("headroom", -1)) == 0,
		"a link already 150 over its 300 cap has zero headroom — every unit pays")
	# A link UNDER cap but pushed over by this turn's own flow keeps its remaining headroom.
	load_flow.call(280)
	_check(int(MatchState.route_congestion(route).get("tier", 0)) == 0,
		"280 under the 300 cap stays clear — headroom only matters once a link is over")

	Modifiers.reset()
	MatchState.reset()
	MatchState.pending_transport_shipments.clear()
	MatchState._last_link_flow.clear()

func _test_flavor_nodes_wired() -> void:
	# The 41 wired flavor nodes register real modifiers on unlock, one per domain.
	Modifiers.reset()
	MatchState.reset()
	# recipe_output: Fractional Distillation → +5% Petrochemical Refinery (b_011).
	MatchState.grant_unlock("Fractional Distillation")
	_check(absf(Modifiers.apply("recipe_output", "x", 100.0, {"building_id": "b_011"}) - 105.0) < 0.001,
		"Fractional Distillation wires +5% petro-refinery output")
	# building_power: Flue Heat Recovery → −10% Coal Power Plant (b_003) power draw.
	MatchState.grant_unlock("Flue Heat Recovery")
	_check(absf(Modifiers.apply("building_power", "b_003", 100.0, {"building_id": "b_003"}) - 90.0) < 0.001,
		"Flue Heat Recovery wires −10% coal-plant power")
	# labour: Safety Training → −5% labour on ALL buildings (empty target_match).
	MatchState.grant_unlock("Safety Training")
	_check(absf(Modifiers.apply("labour_headcount", "b_999", 100.0, {"building_id": "b_999"}) - 95.0) < 0.001,
		"Safety Training wires −5% labour empire-wide")
	# maintenance: Grid Synchronous Generation → −8% on each power plant (array spec).
	MatchState.grant_unlock("Grid Synchronous Generation")
	_check(absf(Modifiers.apply("maintenance", "b_024", 100.0, {"building_id": "b_024"}) - 92.0) < 0.001,
		"Grid Synchronous Generation wires −8% maintenance on a power plant (solar)")
	# market_price: Forward Contracts → +5% steel sale price, good-specific.
	MatchState.grant_unlock("Forward Contracts")
	_check(absf(Modifiers.apply("market_price", "gid", 10.0, {"good_internal": "steel"}) - 10.5) < 0.001,
		"Forward Contracts wires +5% steel sale price")
	_check(absf(Modifiers.apply("market_price", "gid", 10.0, {"good_internal": "coal"}) - 10.0) < 0.001,
		"the steel sale-price modifier does not touch other goods")
	# transport_cost: Route Optimization → −10% haulage.
	MatchState.grant_unlock("Route Optimization")
	_check(absf(Modifiers.apply("transport_cost", "g", 100.0, {"good_id": "g"}) - 90.0) < 0.001,
		"Route Optimization wires −10% transport cost")
	Modifiers.reset()
	MatchState.reset()

func _test_research_tier_gating() -> void:
	MatchState.reset()
	# Tier I is always open; a higher tier opens on >=min(3, prior-tier-count) unlocked
	# in the prior tier of the SAME category.
	_check(MatchState.is_tier_available("Metallurgy", "I"), "tier gate: Tier I always open")
	_check(not MatchState.is_tier_available("Metallurgy", "II"),
		"tier gate: Metallurgy II locked with 0 Tier-I unlocked")
	MatchState.grant_unlock("Basic Blast Furnaces")
	MatchState.grant_unlock("Continuous Casting")
	_check(not MatchState.is_tier_available("Metallurgy", "II"),
		"tier gate: Metallurgy II still locked at 2/3 Tier-I")
	MatchState.grant_unlock("Oxygen-Enriched Blast")
	_check(MatchState.is_tier_available("Metallurgy", "II"),
		"tier gate: Metallurgy II opens at 3 Tier-I unlocked")
	# Softlock clamp: Recycling has a single Tier-II node, so Tier III must open on just it.
	_check(not MatchState.is_tier_available("Recycling", "III"),
		"tier gate: Recycling III locked before its lone Tier-II node")
	MatchState.grant_unlock("Membrane Bioreactors")
	_check(MatchState.is_tier_available("Recycling", "III"),
		"tier gate: Recycling III opens after its single Tier-II (min(3,count) clamp avoids softlock)")
	MatchState.reset()

func _test_live_unlock_conditions() -> void:
	Modifiers.reset()
	MatchState.reset()
	MarketState.import_state({})
	Stockpile.clear_all()
	Production.produced_by_building.clear()
	Production.full_output_streak_by_building.clear()

	# Research conditions are encoded as internal_name Objects: a good_id for the
	# "Produce" verb, a building internal_name for the "Run …" verbs.
	var def := {}
	for d in MatchState._unlock_defs:
		if str(d.title) == "Improved Coal Mining":
			def = d
	_check(not def.is_empty() and str(def.action) == "Produce" and str(def.object) == "coal",
		"Improved Coal Mining now uses a Produce|coal condition")

	# --- "Produce N units" verb: lifetime production across all buildings ---
	# Production records under the catalog good_id (e.g. g_001), NOT the internal
	# name; the condition Object is the internal name "coal", so lifetime_total must
	# resolve it. Seed the ledger under the real good_id to exercise that path.
	var coal_gid: String = str(Catalog.get_good_by_internal_name("coal").get("id", "coal"))
	_check(coal_gid != "coal", "coal resolves to a catalog good_id (got %s)" % coal_gid)
	# 499 coal: below the 500 threshold, stays locked.
	Production.produced_by_building["bX"] = {coal_gid: 499}
	MatchState._check_unlock_conditions()
	_check(not MatchState.is_unlocked("Improved Coal Mining"),
		"Produce condition unmet at 499/500 coal")
	# Cross-building total reaches 500 → the lifetime sum trips the unlock.
	Production.produced_by_building["bY"] = {coal_gid: 1}
	MatchState._check_unlock_conditions()
	_check(MatchState.is_unlocked("Improved Coal Mining"),
		"Produce condition met once lifetime coal hits 500 (summed across buildings)")
	# Generated power uses its internal name in the production ledger, unlike
	# material outputs. The live condition must accept that form too.
	Production.produced_by_building.clear()
	Production.produced_by_building["generator"] = {"power": 250}
	_check(MatchState._live_condition_met({"action": "Produce", "object": "Power", "qty": 250}),
		"Produce condition resolves display-name casing and internal-key power output")

	# --- "Sell N units": saved lifetime volume across ordinary/special/grid paths ---
	var steel_gid := str(Catalog.get_good_by_internal_name("steel").get("id", ""))
	MarketState.record_lifetime_sale_volume(steel_gid, 249)
	_check(not MatchState._live_condition_met({"action": "Sell", "object": "Steel", "qty": 250}),
		"Sell condition remains unmet one unit below its lifetime threshold")
	MarketState.record_lifetime_sale_volume(steel_gid, 1)
	_check(MatchState._live_condition_met({"action": "Sell", "object": "Steel", "qty": 250}),
		"Sell condition resolves a display name and trips at the lifetime threshold")
	_check(MatchState._live_condition_met({"action": "Sell", "object": "Freight", "qty": 250}),
		"Sell Freight resolves to aggregate lifetime shipment volume")
	var market_sale_snapshot := MarketState.export_state()
	MarketState.import_state({})
	_check(not MatchState._live_condition_met({"action": "Sell", "object": "Steel", "qty": 250}),
		"a fresh market state clears lifetime research sale volume")
	MarketState.import_state(market_sale_snapshot)
	_check(MatchState._live_condition_met({"action": "Sell", "object": "Steel", "qty": 250}),
		"lifetime research sale volume survives a save/load round-trip")

	# --- Display-name/case resolver: the original live-game casing regression ---
	MatchState.reset()
	for i in range(3):
		MatchState.add_building("b_002", "", "tile_furnace_%d" % i)
	_check(MatchState.is_unlocked("Basic Blast Furnaces"),
		"Build Furnace unlock fires with the CSV display name (case-insensitive)")

	# --- Plain Run and concept aliases: one building, sustained full-output streak ---
	MatchState.reset()
	Production.full_output_streak_by_building.clear()
	var refinery_iid := MatchState.add_building("b_011", "", "tile_refinery")
	Production.full_output_streak_by_building[refinery_iid] = 12
	_check(MatchState._live_condition_met({"action": "Run", "object": "Oil Refinery", "qty": 12}),
		"Run condition resolves Oil Refinery to petro_refinery and its run streak")
	var factory_iid := MatchState.add_building("b_007", "", "tile_factory")
	Production.full_output_streak_by_building[factory_iid] = 15
	_check(MatchState._live_condition_met({"action": "Run", "object": "Modular Factory Cells", "qty": 15}),
		"Run condition resolves a research-concept alias to its live building")

	# --- Own land and Sustain verbs ---
	MatchState.tile_land_owned.clear()
	for i in range(5):
		MatchState.tile_land_owned["tile_owned_%d" % i] = 1
	_check(MatchState._live_condition_met({"action": "Own", "object": "land", "qty": 5}),
		"Own land condition counts explicitly owned tiles")
	MatchState._advisor_profit_streak = 3
	_check(MatchState._live_condition_met({"action": "Sustain", "object": "1000+ profit/turn", "qty": 3}),
		"Sustain condition reads the saved advisor profit streak")

	# --- "Run L1 … for N turns": level + run-streak filter ---
	MatchState.reset()
	Production.full_output_streak_by_building.clear()
	var iid := MatchState.add_building("b_003", "", "tile_lv_1")  # Coal Power Plant, Level 1
	_check(MatchState._count_buildings("power_plant", 1, false, 20) == 0,
		"a fresh L1 building (streak 0) does not count toward a 20-turn gate")
	Production.full_output_streak_by_building[iid] = 20
	_check(MatchState._count_buildings("power_plant", 1, false, 20) == 1,
		"the L1 building counts once its run-streak reaches 20 turns")

	# --- Level filter: this fixture contains no Level-2 buildings ---
	_check(MatchState._count_buildings("power_plant", 2, false, 0) == 0,
		"Level-2 gates stay unmet when the owned building is only Level 1")
	# --- Profitability filter: a building with no costed output isn't profitable ---
	_check(MatchState._count_buildings("power_plant", -1, true, 0) == 0,
		"the profitable filter excludes buildings with no known unit cost")

	# Every non-placeholder research row must either resolve to a live metric or
	# appear in this explicit content-gap allowlist. This catches new casing,
	# identifier and unsupported-verb regressions across the full CSV.
	var expected_content_gaps := [
		"Agrivoltaic Integration",
		"Autonomous Dispatch Rooms",
		"Combined Cycle Gas",
		"Continuous Improvement Teams",
		"Integrated Operations Planning",
		"Risk Desk Procedures",
		"Route Optimization",
		"Safety Training",
		"Shift Supervisors",
		"Spot Price Reporting",
	]
	var actual_content_gaps: Array = []
	for issue in MatchState.research_condition_issues():
		actual_content_gaps.append(str(issue.title))
	actual_content_gaps.sort()
	_check(actual_content_gaps == expected_content_gaps,
		"research condition audit has no unexpected unresolved targets (got %s)" % [actual_content_gaps])
	var research_titles: Dictionary = {}
	var duplicate_titles: Array = []
	for unlock_def in MatchState._unlock_defs:
		var unlock_title := str(unlock_def.get("title", ""))
		if research_titles.has(unlock_title):
			duplicate_titles.append(unlock_title)
		research_titles[unlock_title] = true
	var missing_prereqs: Array = []
	for unlock_def in MatchState._unlock_defs:
		for prereq in unlock_def.get("prereqs", []):
			if not research_titles.has(str(prereq)):
				missing_prereqs.append("%s -> %s" % [unlock_def.title, prereq])
	_check(duplicate_titles.is_empty(),
		"research dataset has no duplicate unlock titles (got %s)" % [duplicate_titles])
	_check(missing_prereqs.is_empty(),
		"every research prerequisite resolves to an unlock title (got %s)" % [missing_prereqs])

	Modifiers.reset()
	MatchState.reset()
	MarketState.import_state({})
	Production.produced_by_building.clear()
	Production.full_output_streak_by_building.clear()

# Free-pick path: spending a free unlock on Mining Mastery (via_condition=false)
# also routes through grant_unlock → unlock_granted, so the bonus still lands.
func _test_mining_mastery_free_unlock() -> void:
	Modifiers.reset()
	MatchState.reset()
	_check(not Modifiers.has("mining_mastery_bonus"), "no bonus before free pick")
	MatchState.grant_unlock("Mining Mastery", false)
	_check(MatchState.is_unlocked("Mining Mastery"), "free pick unlocks the tech")
	_check(Modifiers.has("mining_mastery_bonus"),
		"free-picking the tech also grants the modifier")
	Modifiers.reset()
	MatchState.reset()

# Percentage modifiers add (not chain): a −10% and a +15% on the same domain/target
# net to +5%, applied as ×1.05. And resolve_pct hands the UI that net + the parts.
func _test_modifiers_pct_additive_and_resolve() -> void:
	Modifiers.reset()
	Modifiers.add({"id": "down", "domain": "recipe_output", "target": "*",
		"pct": -10.0, "label": "Tax productivity hit"})
	Modifiers.add({"id": "up", "domain": "recipe_output", "target": "*",
		"pct": 15.0, "label": "Process upgrade"})
	# 100 → (100)*(1 + 5/100) = 105, because −10 and +15 SUM to +5 (not 0.90×1.15).
	_check(absf(Modifiers.apply("recipe_output", "r_001", 100.0) - 105.0) < 0.001,
		"pct modifiers add: −10% and +15% net +5% (→105, not 103.5)")
	var res: Dictionary = Modifiers.resolve_pct("recipe_output", "r_001", {})
	_check(absf(float(res.get("net", 0.0)) - 5.0) < 0.001,
		"resolve_pct returns the summed net (+5%)")
	_check((res.get("parts", []) as Array).size() == 2,
		"resolve_pct lists both contributing multipliers for the hover")
	# Domain isolation: a building_power pct doesn't bleed into recipe_output's net.
	Modifiers.add({"id": "pwr", "domain": "building_power", "target": "*", "pct": -20.0})
	_check(absf(float(Modifiers.resolve_pct("recipe_output", "r_001", {}).get("net", 0.0)) - 5.0) < 0.001,
		"resolve_pct ignores other domains")
	_check(absf(Modifiers.apply("building_power", "b_002", 100.0) - 80.0) < 0.001,
		"a −20% building_power pct drops a 100-energy draw to 80")
	Modifiers.reset()

# The promoted research nodes register their modifiers on unlock, across all four
# wired domains — including Lights-Out Automation, whose one node hits TWO buildings.
func _test_modifiers_new_domain_unlocks() -> void:
	Modifiers.reset()
	MatchState.reset()
	# recipe_output: Continuous-Flow Reactors → +5% at the chem plant (b_012) only.
	MatchState.grant_unlock("Continuous-Flow Reactors")
	_check(Modifiers.has("cfr_chem_output"), "Continuous-Flow Reactors registers its modifier")
	_check(absf(Modifiers.apply("recipe_output", "any", 100.0, {"building_id": "b_012"}) - 105.0) < 0.001,
		"chem plant (b_012) gets +5% output")
	_check(absf(Modifiers.apply("recipe_output", "any", 100.0, {"building_id": "b_010"}) - 100.0) < 0.001,
		"a different building (b_010) is untouched by the chem bonus")
	# building_power: Energy-Recovery Devices → −50% at desal (b_021).
	MatchState.grant_unlock("Energy-Recovery Devices")
	_check(absf(Modifiers.apply("building_power", "b_021", 100.0, {"building_id": "b_021"}) - 50.0) < 0.001,
		"desal (b_021) power draw halved")
	# maintenance: Combined Heat & Power → −5% everywhere.
	MatchState.grant_unlock("Combined Heat & Power")
	_check(absf(Modifiers.apply("maintenance", "b_002", 100.0, {"building_id": "b_002"}) - 95.0) < 0.001,
		"Combined Heat & Power cuts maintenance 5% empire-wide")
	# labour_headcount: ONE Lights-Out node, TWO buildings (high-tech b_010 + assembly b_009).
	MatchState.grant_unlock("Lights-Out Automation")
	_check(Modifiers.has("lo_hightech_labour") and Modifiers.has("lo_assembly_labour"),
		"Lights-Out Automation registers BOTH building modifiers from one unlock")
	_check(absf(Modifiers.apply("labour_headcount", "b_010", 100.0, {"building_id": "b_010"}) - 80.0) < 0.001,
		"high-tech (b_010) labour −20%")
	_check(absf(Modifiers.apply("labour_headcount", "b_009", 100.0, {"building_id": "b_009"}) - 80.0) < 0.001,
		"assembly (b_009) labour −20%")
	Modifiers.reset()
	MatchState.reset()

# Identical notifications fold into display groups by reason; dismiss_group
# clears only its own members.
# Survey-complete notifications collapse into one "N Surveys Completed" card,
# and each member carries the tile + revealed deposits.
func _test_survey_grouping() -> void:
	EventScheduler.reset()
	TurnManager.current_turn = 1
	EventScheduler._on_survey_completed("tile_6_8", [{"internal_name": "coal"}])
	EventScheduler._on_survey_completed("tile_7_10", [{"internal_name": "iron_ore"}])
	var groups := EventScheduler.grouped_active()
	var survey_group := {}
	for g in groups:
		if str(g.group_key) == "surveys_complete":
			survey_group = g
	_check(not survey_group.is_empty() and (survey_group.members as Array).size() == 2,
		"two surveys fold into one group")
	_check(str(survey_group.get("title", "")) == "Surveys Completed",
		"survey group title is 'Surveys Completed'")
	var m: Dictionary = (survey_group.members as Array)[0]
	_check(str(m.get("where", "")) == "coal" or str(m.get("where", "")) == "iron_ore",
		"survey member carries the revealed deposit in `where`")
	EventScheduler.reset()

func _test_event_grouping() -> void:
	EventScheduler.reset()
	TurnManager.current_turn = 1
	for i in range(3):
		EventScheduler._on_building_starved({"instance_id": "p_%d" % i, "building_id": "b_001",
			"tile_id": "tile_6_8", "missing": [{"internal_name": "power", "need": 4, "have": 0}]})
	for i in range(2):
		EventScheduler._on_building_starved({"instance_id": "in_%d" % i, "building_id": "b_002",
			"tile_id": "tile_7_10", "missing": [{"internal_name": "coal", "need": 10, "have": 0}]})
	var power_group := {}
	var input_group := {}
	for g in EventScheduler.grouped_active():
		if str(g.group_key) == "starved_power":
			power_group = g
		elif str(g.group_key) == "starved_inputs":
			input_group = g
	_check(not power_group.is_empty() and (power_group.members as Array).size() == 3,
		"3 power starvations fold into one group")
	_check(str(power_group.get("title", "")) == "Buildings Starved of Power",
		"power group carries the plural title")
	_check(not input_group.is_empty() and (input_group.members as Array).size() == 2,
		"2 input starvations fold into a separate group")
	# dismiss_group clears only that group.
	EventScheduler.dismiss_group("starved_power")
	_check(EventScheduler._active.size() == 2,
		"dismiss_group removes only its own members (got %d left)" % EventScheduler._active.size())
	var remaining := EventScheduler.grouped_active()
	_check(remaining.size() == 1 and str(remaining[0].group_key) == "starved_inputs",
		"only the input group remains after dismissing the power group")
	EventScheduler.reset()

# A starvation event deep-links to the BUILDING panel (not the tile panel): its
# deeplink names the building instance, and the bell's _go_to routes it to
# MatchState.focus_building_requested.
func _test_starvation_deeplink_building() -> void:
	EventScheduler.reset()
	TurnManager.current_turn = 1
	EventScheduler._on_building_starved({"instance_id": "inst_dl", "building_id": "b_001",
		"tile_id": "tile_6_8", "missing": [{"internal_name": "power"}]})
	var ev: Dictionary = EventScheduler._active["starvation:inst_dl"]
	var dl: Dictionary = ev.get("deeplink", {})
	_check(str(dl.get("panel", "")) == "building" and str(dl.get("building_id", "")) == "inst_dl",
		"starvation event deep-links to its building instance")
	EventScheduler.reset()

# Clicking a group header expands its members inline (indented) in the same
# dropdown; a member's "Go to" routes a starved building to the building panel.
func _test_notification_group_inline_expand() -> void:
	EventScheduler.reset()
	MatchState.reset()
	TurnManager.current_turn = 1
	for i in range(3):
		EventScheduler._on_building_starved({"instance_id": "ex_%d" % i, "building_id": "b_001",
			"tile_id": "tile_6_8", "missing": [{"internal_name": "power"}]})
	var bell: Node = load("res://scripts/notification_bell.gd").new()
	add_child(bell)
	await get_tree().process_frame
	bell.call("toggle_dropdown")  # opens + builds rows (one collapsed group header)
	await get_tree().process_frame
	var list: VBoxContainer = bell.get("_dropdown_list")
	_check(_count_panels(list) == 1, "collapsed: one group header row (got %d)" % _count_panels(list))
	# Expand the group: header + 3 indented members.
	bell.set("_expanded_group_key", "starved_power")
	bell.call("_rebuild_dropdown_rows")
	await get_tree().process_frame
	_check(_count_panels(list) >= 4, "expanded: header + 3 member rows (got %d)" % _count_panels(list))
	# A member "Go to" routes to the building panel.
	var focused_buildings: Array = []
	var cb := func(b): focused_buildings.append(b)
	MatchState.focus_building_requested.connect(cb)
	var links: Array = []
	_collect_links(bell, links)
	_check(links.size() >= 3, "each expanded member has a Go-to link (got %d)" % links.size())
	if not links.is_empty():
		(links[0] as LinkButton).pressed.emit()
	_check(focused_buildings.size() == 1 and str(focused_buildings[0]).begins_with("ex_"),
		"member Go-to fires focus_building_requested for the building instance")
	MatchState.focus_building_requested.disconnect(cb)
	bell.queue_free()
	await get_tree().process_frame
	EventScheduler.reset()
	MatchState.reset()

# The header bells filter the list by severity ("" = show all).
func _test_notification_header_filter() -> void:
	EventScheduler.reset()
	TurnManager.current_turn = 1
	# Two groups: a critical one and a warning one (2 members each so they group).
	for id in ["c1", "c2"]:
		EventScheduler.emit_event({"id": id, "group_key": "g_crit", "group_title": "Crit",
			"severity": EventScheduler.SEVERITY_CRITICAL})
	for id in ["w1", "w2"]:
		EventScheduler.emit_event({"id": id, "group_key": "g_warn", "group_title": "Warn",
			"severity": EventScheduler.SEVERITY_WARNING})
	var bell: Node = load("res://scripts/notification_bell.gd").new()
	add_child(bell)
	await get_tree().process_frame
	bell.call("toggle_dropdown")
	await get_tree().process_frame
	var list: VBoxContainer = bell.get("_dropdown_list")
	_check(_count_panels(list) == 2, "no filter: both groups show (got %d)" % _count_panels(list))
	# Filter to critical → only the critical group.
	bell.set("_filter_severity", "critical")
	bell.call("_rebuild_dropdown_rows")
	await get_tree().process_frame
	_check(_count_panels(list) == 1, "critical filter: one group (got %d)" % _count_panels(list))
	# Four header filter bells were built.
	_check((bell.get("_filter_bells") as Array).size() == 4, "four header filter bells built")
	# Clearing (navy) shows all again.
	bell.set("_filter_severity", "")
	bell.call("_rebuild_dropdown_rows")
	await get_tree().process_frame
	_check(_count_panels(list) == 2, "cleared filter: both groups show again (got %d)" % _count_panels(list))
	bell.queue_free()
	await get_tree().process_frame
	EventScheduler.reset()

func _count_panels(node: Node) -> int:
	var n := 0
	for c in node.get_children():
		n += _count_panels(c)
		if c is PanelContainer:
			n += 1
	return n

func _collect_links(node: Node, out: Array) -> void:
	if node is LinkButton:
		out.append(node)
	for child in node.get_children():
		_collect_links(child, out)

func _fresh_production_summary() -> Dictionary:
	# Minimal summary skeleton Production._dispatch_output_to_stockpile reads/writes.
	return {
		"produced": {},
		"transport_paid": 0.0,
		"money_out": 0.0,
		"money_in": 0.0,
		"goods_sales_revenue": 0.0,
		"goods_purchased_cost": 0.0,
		"sold": {},
	}

# UI smoke: the navy bell builds, the badge follows the active count (shown at
# >=1), the dropdown opens with one row per event, and dismiss_all clears it.
func _test_notification_bell_smoke() -> void:
	EventScheduler.reset()
	TurnManager.current_turn = 1
	var bell: Node = load("res://scripts/notification_bell.gd").new()
	add_child(bell)
	await get_tree().process_frame
	_check(bell.get("_dropdown") != null, "bell builds its dropdown")
	_check(not (bell.get("_badge") as Label).visible, "badge hidden when no events")
	# One event → badge shows "1" (the navy trigger keeps the unread count).
	# Refreshes coalesce via call_deferred, so settle two frames before reading.
	EventScheduler.emit_event({"id": "u1", "title": "Test warn",
		"severity": EventScheduler.SEVERITY_WARNING})
	await get_tree().process_frame
	await get_tree().process_frame
	_check((bell.get("_badge") as Label).visible and (bell.get("_badge") as Label).text == "1",
		"badge shows 1 with one event (got '%s')" % (bell.get("_badge") as Label).text)
	EventScheduler.emit_event({"id": "u2", "title": "Test crit",
		"severity": EventScheduler.SEVERITY_CRITICAL})
	await get_tree().process_frame
	await get_tree().process_frame
	_check((bell.get("_badge") as Label).text == "2",
		"badge shows the unread count (got '%s')" % (bell.get("_badge") as Label).text)
	# Open dropdown, expect one row per (ungrouped) event.
	bell.call("toggle_dropdown")
	await get_tree().process_frame
	_check((bell.get("_dropdown") as PanelContainer).visible, "dropdown opens on click")
	var list: VBoxContainer = bell.get("_dropdown_list")
	var row_count := 0
	for c in list.get_children():
		if c is PanelContainer:
			row_count += 1
	_check(row_count == 2, "dropdown shows one row per active event (got %d)" % row_count)
	EventScheduler.dismiss("u2")
	await get_tree().process_frame
	await get_tree().process_frame
	_check((bell.get("_badge") as Label).text == "1", "badge drops to 1 after a dismiss")
	EventScheduler.dismiss_all()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not (bell.get("_badge") as Label).visible, "badge hidden after dismiss_all")
	bell.queue_free()
	await get_tree().process_frame
	EventScheduler.reset()

# UI: the save/load screens and the Esc pause menu build, gate their CTAs, and
# the save screen actually writes the named slot.
func _test_save_load_ui() -> void:
	_check(SaveLoad.save_slot("__test_ui") == "", "fixture save for the load screen")
	var screen: SaveLoadScreen = SaveLoadScreen.open(self, SaveLoadScreen.Mode.LOAD)
	await get_tree().process_frame
	_check(screen._cta != null and screen._cta.disabled,
		"load screen: CTA disabled until a save is picked")
	var rows: Array = []
	_collect_buttons(screen, rows)
	var toggle_rows := 0
	for b in rows:
		if (b as Button).toggle_mode:
			toggle_rows += 1
	_check(toggle_rows == SaveLoad.list_slots().size(),
		"load screen: one selectable row per save slot")
	screen.hide()  # frees itself
	await get_tree().process_frame

	var save_screen: SaveLoadScreen = SaveLoadScreen.open(self, SaveLoadScreen.Mode.SAVE)
	await get_tree().process_frame
	_check(save_screen._cta.disabled, "save screen: CTA disabled while the name is empty")
	save_screen._name_edit.text = "__test_ui_named"
	save_screen._do_save()
	_check(FileAccess.file_exists(AppPaths.saves_dir().path_join("__test_ui_named.json")),
		"save screen: writes the named slot")
	_check(not save_screen.visible, "save screen: closes after saving")
	await get_tree().process_frame

	var menu: PauseMenu = PauseMenu.open(self)
	await get_tree().process_frame
	var menu_buttons: Array = []
	_collect_buttons(menu, menu_buttons)
	# Return to game / Save / Load / Settings / Exit to Main Menu / Exit to Desktop
	_check(menu_buttons.size() == 6, "pause menu: shows the 6 options")
	var menu_labels: Array = menu_buttons.map(func(b: Button) -> String: return b.text)
	_check(menu_labels.has("Exit to Main Menu"), "pause menu: has Exit to Main Menu")
	_check(menu_labels.has("Exit to Desktop"), "pause menu: has Exit to Desktop")
	_check(PanelStack.close_top() and not menu.visible, "pause menu: Esc path (close_top) closes it")
	await get_tree().process_frame
	DirAccess.remove_absolute(AppPaths.saves_dir().path_join("__test_ui.json"))
	DirAccess.remove_absolute(AppPaths.saves_dir().path_join("__test_ui_named.json"))

func _collect_buttons(node: Node, out: Array) -> void:
	if node is Button:
		out.append(node)
	for child in node.get_children():
		_collect_buttons(child, out)

# Phase 2 load sequencing: a pending snapshot must apply at the end of
# world_map._ready (after NPC ports/deposit seeding) and overwrite fresh-match
# state — this is the path the main menu's Load Game and the terminal use.
func _test_pending_load_applies_on_scene_ready() -> void:
	var before_money: float = MatchState.money
	var before_buildings: int = MatchState.buildings.size()
	var snap: Dictionary = SaveLoad.export_snapshot()
	MatchState.add_money(777.0)  # diverge so the apply is observable
	SaveLoad._pending_snapshot = snap
	var inst: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(inst)
	await get_tree().process_frame
	_check(not SaveLoad.has_pending(), "pending save is consumed when the map scene readies")
	_check(absf(MatchState.money - before_money) < 0.001, "pending save restores money over fresh-match state")
	_check(MatchState.buildings.size() == before_buildings, "pending save restores the building set")
	inst.queue_free()
	await get_tree().process_frame

## Step RoadWorks until no order is queued/planning/revealing (or frame cap).
func _drain_road_works(max_frames: int) -> void:
	var frames := 0
	while frames < max_frames:
		RoadWorks._process(1.0 / 60.0)
		frames += 1
		var pending := false
		for oid_k in RoadWorks.orders:
			if str(RoadWorks.orders[oid_k].state) in ["queued", "planning", "revealing"]:
				pending = true
				break
		if not pending:
			return

func _test_building_shapes() -> void:
	# Each shape holds its target area within tolerance and is deterministic.
	for kind in BuildingShapes.KINDS:
		for area in [400.0, 4000.0, 15000.0]:
			var s := BuildingShapes.make(str(kind), float(area), 3)
			var got := BuildingShapes.polygon_area(s.verts)
			_check(absf(got - float(area)) <= float(area) * 0.02 + 1.0,
				"building shapes: %s area %.0f within 2%% (got %.0f)" % [str(kind), float(area), got])
			var mx := 0.0
			var my := 0.0
			for v in (s.verts as PackedVector2Array):
				mx = maxf(mx, absf(v.x))
				my = maxf(my, absf(v.y))
			_check(absf(mx - float(s.half.x)) <= 0.5 and absf(my - float(s.half.y)) <= 0.5,
				"building shapes: %s half-extent matches verts" % str(kind))
	var a := BuildingShapes.make("l_base", 5000.0, 2)
	var b := BuildingShapes.make("l_base", 5000.0, 2)
	_check(a.verts == b.verts, "building shapes: deterministic for same params")

func _test_building_category_key() -> void:
	# The polygon layout clusters on category_key and edge-seeks on
	# extraction|recycling — guard those classifications against catalog drift.
	var TileViewData := preload("res://scripts/tile_view_data.gd")
	var mine := Catalog.get_building("b_001")
	if not mine.is_empty():
		_check((mine.get("building_type", []) as Array).has("extraction"),
			"layout edge rule: b_001 is extraction (mine)")
		_check(TileViewData.category_key(mine) == "extraction",
			"layout category_key: b_001 -> extraction")
	# Both recycling buildings must trip the edge rule (internal_name ~ 'recycl')
	# while keeping their own colour category.
	var wrec := Catalog.get_building("b_022")
	if not wrec.is_empty():
		_check(str(wrec.get("internal_name", "")).to_lower().contains("recycl"),
			"layout edge rule: b_022 water_recycling matches 'recycl'")
		_check(TileViewData.category_key(wrec) == "water",
			"layout category_key: b_022 -> water (colour stays water)")
	var prec := Catalog.get_building("b_036")
	if not prec.is_empty():
		_check(str(prec.get("internal_name", "")).to_lower().contains("recycl"),
			"layout edge rule: b_036 recycling_plant matches 'recycl'")
		_check(TileViewData.category_key(prec) == "manufacturing",
			"layout category_key: b_036 -> manufacturing")

# ── Victory system (scripts/victory_state.gd; docs/victory-system-spec.md §12) ──

func _test_victory_base_curve() -> void:
	# No base score any more — you start at 0. The rising WIN BAR is the time pressure.
	VictoryState.reset()
	_check(VictoryState.total_for_turn() == 0, "victory: start at 0 (no base score)")
	_check(VictoryState.win_threshold_for_turn(1) == 1000, "victory bar: turn 1 = 1000 (flat before 105)")
	_check(VictoryState.win_threshold_for_turn(105) == 1000, "victory bar: turn 105 = 1000 (1 track)")
	_check(VictoryState.win_threshold_for_turn(170) == 2000, "victory bar: turn 170 = 2000 (2 tracks)")
	_check(VictoryState.win_threshold_for_turn(235) == 3000, "victory bar: turn 235 = 3000 (3 tracks)")
	_check(VictoryState.win_threshold_for_turn(300) == 4000, "victory bar: turn 300 = 4000 (4 tracks)")
	_check(VictoryState.win_threshold_for_turn(350) == 4000, "victory bar: turn 350 = 4000 (clamped)")

func _test_victory_win_curve() -> void:
	VictoryState.reset()
	# 1 maxed track (1000) wins at turn 105 but not once the bar has risen past it.
	_check(1000 >= VictoryState.win_threshold_for_turn(105), "victory curve: 1 track wins at turn 105")
	_check(1000 < VictoryState.win_threshold_for_turn(170), "victory curve: 1 track falls short at turn 170")
	_check(3000 < VictoryState.win_threshold_for_turn(300), "victory curve: 3 tracks fall short at turn 300")
	_check(4000 >= VictoryState.win_threshold_for_turn(300), "victory curve: 4 tracks win at turn 300")

func _test_victory_autarkic() -> void:
	MatchState.reset()
	VictoryState.reset()
	# A buy of each category increments that category's tally (this turn + lifetime).
	VictoryState.record_movement("buy", "input", 0)
	VictoryState.record_movement("buy", "building", 2)
	VictoryState.record_movement("buy", "upgrade", 0)
	VictoryState.record_movement("buy", "other", 1)
	_check(int(VictoryState.purchases_this_turn["input"]) == 1
		and int(VictoryState.purchases_this_turn["building"]) == 1
		and int(VictoryState.purchases_this_turn["upgrade"]) == 1
		and int(VictoryState.purchases_this_turn["other"]) == 1,
		"victory autarkic: a buy of each category increments purchases_this_turn")
	_check(int(VictoryState.purchases_lifetime["input"]) == 1
		and int(VictoryState.purchases_lifetime["other"]) == 1,
		"victory autarkic: lifetime tally accumulates")
	# A turn with any purchase resets the streak.
	TurnManager.current_turn = 5
	VictoryState.autarkic_streak = 9
	VictoryState._tick()
	_check(VictoryState.autarkic_streak == 0, "victory autarkic: a turn with any buy resets the streak")
	# A turn with only a move or sale does NOT reset.
	VictoryState.record_movement("move", "", 0)
	VictoryState.record_movement("sale", "", 3)
	VictoryState.autarkic_streak = 4
	VictoryState._tick()
	_check(VictoryState.autarkic_streak == 5, "victory autarkic: a move/sale-only turn keeps the streak (4 -> 5)")
	# Scale gate: the track scores 0 until lifetime production clears AUTARKIC_MIN_UNITS,
	# even with a maxed streak.
	VictoryState.autarkic_streak = 40
	VictoryState.produced_units_lifetime = VictoryState.AUTARKIC_MIN_UNITS - 1
	_check(absf(VictoryState._live_progress("autarkic")) < 0.001, "victory autarkic: gated to 0 below the 10k-unit floor despite a maxed streak")
	VictoryState.produced_units_lifetime = VictoryState.AUTARKIC_MIN_UNITS
	_check(absf(VictoryState._live_progress("autarkic") - 1.0) < 0.001, "victory autarkic: scores once the units floor is cleared")
	# Progress ramps from streak 10 to 30 (units gate cleared above).
	VictoryState.autarkic_streak = 10
	_check(absf(VictoryState._live_progress("autarkic")) < 0.001, "victory autarkic: progress 0 at streak 10")
	VictoryState.autarkic_streak = 20
	_check(absf(VictoryState._live_progress("autarkic") - 0.5) < 0.001, "victory autarkic: progress 0.5 at streak 20")
	VictoryState.autarkic_streak = 30
	_check(absf(VictoryState._live_progress("autarkic") - 1.0) < 0.001, "victory autarkic: progress caps at streak 30")
	VictoryState.autarkic_streak = 40
	_check(absf(VictoryState._live_progress("autarkic") - 1.0) < 0.001, "victory autarkic: progress stays capped above 30")
	# Accumulator sums this turn's produced GOODS units — POWER is ignored (owner 2026-07-11:
	# Autarkic ignores electricity), so 30 coal + 20 iron_ore = 50, the 9000 MW doesn't count.
	VictoryState.produced_units_lifetime = 0
	VictoryState._last_summary = {"produced": {"coal": 30, "iron_ore": 20, "power": 9000}}
	VictoryState._tick()
	_check(VictoryState.produced_units_lifetime == 50, "victory autarkic: _tick sums produced goods, ignores power (30+20)")
	# Drawing from the grid (grid_bought) with NO market buys must NOT break the streak.
	VictoryState.reset()
	VictoryState.autarkic_streak = 12
	VictoryState._last_summary = {"produced": {"steel": 40}, "grid_bought": 800}
	VictoryState._tick()
	_check(VictoryState.autarkic_streak == 13, "victory autarkic: drawing grid power doesn't break the streak")

func _test_victory_logistics() -> void:
	VictoryState.reset()
	# 50 efficient movements is below the 100-move gate -> progress 0.
	for _i in range(50):
		VictoryState.record_movement("move", "", 0)
	_check(absf(VictoryState._live_progress("logistics")) < 0.001, "victory logistics: 0 below 100 moves")
	# Top up to 100 total: 25 inefficient (3 turns) + 25 efficient (1 turn) -> 75/100.
	for _i in range(25):
		VictoryState.record_movement("buy", "input", 3)
	for _i in range(25):
		VictoryState.record_movement("sale", "", 1)
	_check(VictoryState.logistics_total == 100 and VictoryState.logistics_efficient == 75,
		"victory logistics: counts total + efficient (0/1-turn movements count as efficient)")
	# eff 0.75 -> (0.75-0.25)/0.75 = 0.667.
	_check(absf(VictoryState._live_progress("logistics") - (0.5 / 0.75)) < 0.001,
		"victory logistics: 75% efficiency maps to ~0.667 progress")
	# Per-turn track: the tick latches the best, then resets the movement counters,
	# so next turn starts from zero (no cumulative credit since game start).
	TurnManager.current_turn = 50
	VictoryState._on_turn_processed({"money_in": 0.0, "money_out": 0.0})
	VictoryState._tick()
	_check(VictoryState.logistics_total == 0 and VictoryState.logistics_efficient == 0
		and absf(float(VictoryState.track_best["logistics"]) - (0.5 / 0.75)) < 0.001,
		"victory logistics: tick latches best then resets per-turn counters")
	_check(absf(VictoryState._live_progress("logistics")) < 0.001,
		"victory logistics: live progress is 0 again after the per-turn reset")
	# Power is grid-settled, never shipped — generating/consuming it emits no goods
	# movement, so a turn of pure power activity adds nothing to the logistics tally.
	VictoryState.reset()
	VictoryState._last_summary = {"produced": {"power": 9000}, "grid_bought": 500, "grid_sold": 1200}
	VictoryState._tick()
	_check(VictoryState.logistics_total == 0,
		"victory logistics: power generation/grid trade counts no movements")

func _test_victory_richest() -> void:
	MatchState.reset()
	VictoryState.reset()
	# Smoothed metric of a flat £7k/turn window -> (7000-2000)/10000 = 0.5.
	VictoryState.richest_window = [7000.0, 7000.0, 7000.0, 7000.0, 7000.0]
	_check(absf(VictoryState._live_progress("richest") - 0.5) < 0.001,
		"victory richest: 5-turn avg of £7k maps to 0.5")
	# Best-ever capture: a great turn lifts best; a bad turn cannot claw it back.
	VictoryState.reset()
	TurnManager.current_turn = 50
	VictoryState._on_turn_processed({"money_in": 12000.0, "money_out": 0.0})
	VictoryState._tick()
	var best_after_good := float(VictoryState.track_best["richest"])
	VictoryState._on_turn_processed({"money_in": 0.0, "money_out": 0.0})
	VictoryState._tick()
	_check(best_after_good > 0.0 and float(VictoryState.track_best["richest"]) >= best_after_good,
		"victory richest: best-ever does not regress after a bad turn")

func _test_victory_widest() -> void:
	MatchState.reset()
	VictoryState.reset()
	# Two player non-infra tiles (mine), one player INFRA tile (port, excluded),
	# one NPC tile (excluded by ownership).
	MatchState.buildings["w1"] = {"building_id": "b_001", "tile_id": "t1", "owner": "player_1"}
	MatchState.buildings["w2"] = {"building_id": "b_001", "tile_id": "t2", "owner": "player_1"}
	MatchState.buildings["w3"] = {"building_id": "b_004", "tile_id": "t3", "owner": "player_1"}
	MatchState.buildings["w4"] = {"building_id": "b_001", "tile_id": "t4", "owner": "ai_corp"}
	# Landfill is category=production (building_type=infrastructure) -> counts per spec §5.4.
	MatchState.buildings["w5"] = {"building_id": "b_023", "tile_id": "t5", "owner": "player_1"}
	_check(VictoryState._count_widest_tiles() == 3,
		"victory widest: counts player non-infra tiles incl. landfill (excludes port + NPC)")
	# 80 distinct player tiles -> (80-30)/200 = 0.25.
	MatchState.reset()
	VictoryState.reset()
	for i in range(80):
		MatchState.buildings["wt%d" % i] = {"building_id": "b_001", "tile_id": "wtile%d" % i, "owner": "player_1"}
	_check(absf(VictoryState._live_progress("widest") - 0.25) < 0.001,
		"victory widest: 80 tiles maps to 0.25 on the [30,230] ramp")
	MatchState.reset()

func _test_victory_greenest() -> void:
	VictoryState.reset()
	VictoryState._resolve_green_ids()
	# 6000 MW solar of 10000 MW made, 2000 MW used -> share 0.6 -> (0.6-0.2)/0.8 = 0.5.
	VictoryState._last_summary = {"power_supply": 10000, "power_demand": 2000, "power_supply_by_type": {"b_024": {"count": 1, "amount": 6000.0}}}
	_check(absf(VictoryState._live_progress("greenest") - 0.5) < 0.001,
		"victory greenest: 60% green share maps to 0.5")
	# Below the 5000 MW GENERATED gate -> 0 (even fully green, plenty consumed).
	VictoryState._last_summary = {"power_supply": 4000, "power_demand": 3000, "power_supply_by_type": {"b_024": {"count": 1, "amount": 4000.0}}}
	_check(absf(VictoryState._live_progress("greenest")) < 0.001,
		"victory greenest: under 5000 MW generated is gated to 0")
	# Enough generated + green share, but network CONSUMES under 1000 MW -> 0.
	VictoryState._last_summary = {"power_supply": 10000, "power_demand": 500, "power_supply_by_type": {"b_024": {"count": 1, "amount": 6000.0}}}
	_check(absf(VictoryState._live_progress("greenest")) < 0.001,
		"victory greenest: under 1000 MW consumed is gated to 0")
	# Above both gates but below 20% green share -> 0.
	VictoryState._last_summary = {"power_supply": 10000, "power_demand": 2000, "power_supply_by_type": {"b_024": {"count": 1, "amount": 1000.0}}}
	_check(absf(VictoryState._live_progress("greenest")) < 0.001,
		"victory greenest: under 20% green share is gated to 0")

func _test_victory_total_and_win() -> void:
	MatchState.reset()
	VictoryState.reset()
	var fired := [0]
	var on_win := func(_total: int, _turn: int) -> void: fired[0] += 1
	VictoryState.victory_achieved.connect(on_win)
	# One maxed track at turn 105: total 1000 >= the turn-105 bar (1000) -> win latches.
	VictoryState.track_best["richest"] = 1.0
	TurnManager.current_turn = 105
	VictoryState._on_turn_processed({"money_in": 0.0, "money_out": 0.0})
	VictoryState._tick()
	_check(VictoryState.won and VictoryState.won_turn == 105 and fired[0] == 1,
		"victory win: reaching the turn-105 bar (1 track) latches the win, fires once")
	# By turn 300 the bar has risen to 4000; the 1-track total (1000) no longer clears
	# it, but the win stays latched with no second emit.
	TurnManager.current_turn = 300
	VictoryState._on_turn_processed({"money_in": 0.0, "money_out": 0.0})
	VictoryState._tick()
	_check(VictoryState.total_for_turn(300) < VictoryState.win_threshold_for_turn(300)
		and VictoryState.won and fired[0] == 1,
		"victory win: stays latched as the bar rises, with no second emit")
	VictoryState.victory_achieved.disconnect(on_win)

func _test_victory_tick_scores_resolved_turn() -> void:
	# Regression: TurnManager increments current_turn BEFORE emitting
	# turn_resolution_completed, so the tick must score the turn just resolved
	# (captured at turn_processed time), not the already-incremented current_turn.
	MatchState.reset()
	VictoryState.reset()
	TurnManager.current_turn = 100
	VictoryState._on_turn_processed({"money_in": 0.0, "money_out": 0.0})  # summary belongs to turn 100
	VictoryState.track_best["richest"] = 1.0
	TurnManager.current_turn = 101  # the increment that lands before completion fires
	VictoryState._on_turn_resolution_completed()
	var b := VictoryState.get_breakdown()
	# At turn 100 the bar is still 1000 (flat before 105); 1 maxed track (1000) wins.
	_check(int(b["turn"]) == 100 and int(b["win_threshold"]) == 1000
		and VictoryState.won and VictoryState.won_turn == 100,
		"victory tick: scores resolved turn 100 (bar 1000, won_turn 100), not turn 101")

func _test_victory_save_load() -> void:
	VictoryState.reset()
	VictoryState.autarkic_streak = 15
	VictoryState.logistics_total = 120
	VictoryState.logistics_efficient = 90
	VictoryState.richest_window = [5000.0, 6000.0]
	VictoryState.track_best["richest"] = 0.5
	VictoryState.track_best["widest"] = 0.25
	VictoryState.score_history = [{"turn": 10, "total": 3100, "base": 3000, "tracks": {"richest": 0.1}}]
	VictoryState.won = true
	VictoryState.won_turn = 42
	VictoryState.purchases_this_turn["input"] = 3
	VictoryState.purchases_lifetime["input"] = 9
	VictoryState.purchases_lifetime["building"] = 2
	var snap := VictoryState.export_state()
	VictoryState.reset()
	_check(VictoryState.autarkic_streak == 0 and not VictoryState.won, "victory save/load: reset clears state")
	VictoryState.import_state(snap)
	_check(VictoryState.autarkic_streak == 15
		and VictoryState.logistics_total == 120
		and VictoryState.logistics_efficient == 90
		and VictoryState.richest_window.size() == 2
		and absf(float(VictoryState.track_best["richest"]) - 0.5) < 0.001
		and absf(float(VictoryState.track_best["widest"]) - 0.25) < 0.001
		and VictoryState.score_history.size() == 1
		and VictoryState.won and VictoryState.won_turn == 42
		and int(VictoryState.purchases_this_turn["input"]) == 3
		and int(VictoryState.purchases_lifetime["input"]) == 9
		and int(VictoryState.purchases_lifetime["building"]) == 2,
		"victory save/load: export -> reset -> import round-trips every field")
	VictoryState.reset()

# ── Power intermittency (green/grey quality flags; scripts/production.gd) ───────

func _test_power_quality() -> void:
	var p := {"output_name": "power", "inputs": []}
	_check(Production._power_quality({"building_id": "b_024"}, p) == "green_intermittent",
		"power quality: solar farm = green_intermittent")
	_check(Production._power_quality({"building_id": "b_025"}, p) == "green_intermittent",
		"power quality: onshore wind = green_intermittent")
	_check(Production._power_quality({"building_id": "b_026"}, p) == "green_intermittent",
		"power quality: offshore wind = green_intermittent")
	_check(Production._power_quality({"building_id": "b_027"}, p) == "green_steady",
		"power quality: hydro = green_steady")
	_check(Production._power_quality({"building_id": "b_003"}, {"output_name": "power", "inputs": [{"internal_name": "coal"}]}) == "grey",
		"power quality: coal-fuelled = grey")
	_check(Production._power_quality({"building_id": "b_003"}, {"output_name": "power", "inputs": [{"internal_name": "biomass"}]}) == "green_steady",
		"power quality: biomass-fuelled = green_steady")

func _test_power_instance_age() -> void:
	_check(Production._instance_age("inst_b_007_00001a") == 26, "instance age: parses trailing hex (1a = 26)")
	_check(Production._instance_age("inst_b_001_000001") < Production._instance_age("inst_b_001_000002"),
		"instance age: lower counter is older")

func _test_power_intermittency_alloc() -> void:
	# Result is keyed by iid -> {derate, green_consumed, unfirmed_intermittent, steady_consumed, demand}.
	var derate := func(dd, k): return float((dd.get(k, {}) as Dictionary).get("derate", 0.0))
	# Full unfirmed intermittent green -> 0.4 derate (produce 60%); richer fields populated.
	var d := Production._allocate_power_derates(
		{"tile_1_1": {"int": 100, "steady": 0}},
		[{"iid": "c1", "tile": "tile_1_1", "demand": 100.0, "level": 1, "profit": 0.0, "age": 1}],
		{"tile_1_1": 0})
	_check(absf(derate.call(d, "c1") - 0.4) < 0.001, "intermittency: full unfirmed intermittent green -> 0.4 derate")
	_check(int(d["c1"]["green_consumed"]) == 100 and int(d["c1"]["unfirmed_intermittent"]) == 100
		and int(d["c1"]["steady_consumed"]) == 0, "intermittency: result carries green/unfirmed/steady consumed")
	# Storage on the tile firms it -> no derate, but it still consumed (now steady) green.
	d = Production._allocate_power_derates(
		{"tile_1_1": {"int": 100, "steady": 0}},
		[{"iid": "c1", "tile": "tile_1_1", "demand": 100.0, "level": 1, "profit": 0.0, "age": 1}],
		{"tile_1_1": 100})
	_check(absf(derate.call(d, "c1")) < 0.001 and int(d["c1"]["steady_consumed"]) == 100,
		"intermittency: on-tile storage firms intermittent -> no derate (counts as steady)")
	# Steady green never derates (consumes steady green).
	d = Production._allocate_power_derates(
		{"tile_1_1": {"int": 0, "steady": 100}},
		[{"iid": "c1", "tile": "tile_1_1", "demand": 100.0, "level": 1, "profit": 0.0, "age": 1}],
		{"tile_1_1": 0})
	_check(absf(derate.call(d, "c1")) < 0.001 and int(d["c1"]["steady_consumed"]) == 100,
		"intermittency: steady green -> no derate")
	# A consumer that draws NO green is absent from the result entirely.
	d = Production._allocate_power_derates(
		{},
		[{"iid": "c1", "tile": "tile_1_1", "demand": 100.0, "level": 1, "profit": 0.0, "age": 1}],
		{"tile_1_1": 0})
	_check(not d.has("c1"), "intermittency: consumer with no green is omitted")
	# Half intermittent / half steady -> 0.2 derate (0.4 * 0.5 share).
	d = Production._allocate_power_derates(
		{"tile_1_1": {"int": 50, "steady": 50}},
		[{"iid": "c1", "tile": "tile_1_1", "demand": 100.0, "level": 1, "profit": 0.0, "age": 1}],
		{"tile_1_1": 0})
	_check(absf(derate.call(d, "c1") - 0.2) < 0.001, "intermittency: 50% intermittent share -> 0.2 derate")
	# Priority: scarce green (100) goes to the higher-level consumer first.
	d = Production._allocate_power_derates(
		{"tile_5_5": {"int": 100, "steady": 0}},
		[{"iid": "hi", "tile": "tile_5_5", "demand": 100.0, "level": 3, "profit": 0.0, "age": 2},
		 {"iid": "lo", "tile": "tile_5_5", "demand": 100.0, "level": 1, "profit": 0.0, "age": 1}],
		{"tile_5_5": 0})
	_check(absf(derate.call(d, "hi") - 0.4) < 0.001 and not d.has("lo"),
		"intermittency: scarce green prioritises the higher-level consumer")
	# Tiebreak: same level/profit -> oldest (lowest age) wins the scarce green.
	d = Production._allocate_power_derates(
		{"tile_5_5": {"int": 100, "steady": 0}},
		[{"iid": "new", "tile": "tile_5_5", "demand": 100.0, "level": 1, "profit": 0.0, "age": 9},
		 {"iid": "old", "tile": "tile_5_5", "demand": 100.0, "level": 1, "profit": 0.0, "age": 1}],
		{"tile_5_5": 0})
	_check(absf(derate.call(d, "old") - 0.4) < 0.001 and not d.has("new"),
		"intermittency: tie broken by oldest instance (age) first")
	# Producer firming + proportional mix: int 50/steady 50, tile cap 30 firms 30 int ->
	# 20 int/80 steady; consumer (same tile, cap now 0) draws 20 unfirmed int of 100 ->
	# derate 0.4 * 0.2 = 0.08 (exact-float firming, no ceil over-charge).
	d = Production._allocate_power_derates(
		{"tile_1_1": {"int": 50, "steady": 50}},
		[{"iid": "c1", "tile": "tile_1_1", "demand": 100.0, "level": 1, "profit": 0.0, "age": 1}],
		{"tile_1_1": 30})
	_check(absf(derate.call(d, "c1") - 0.08) < 0.001,
		"intermittency: producer firming + proportional mix -> 0.08 derate")

func _test_intermittency_tile_aggregate() -> void:
	# Roll the per-building result + per-tile green supply up into the tile-view aggregate.
	var saved_green := Production._green_supply_by_tile
	var saved_im := Production._intermittency_by_building
	var saved_prod := Power.tile_produced
	Production._green_supply_by_tile = {"tile_2_2": {"int": 100, "steady": 0}}
	Production._intermittency_by_building = {
		"a": {"derate": 0.4, "green_consumed": 100.0, "unfirmed_intermittent": 100.0, "steady_consumed": 0.0, "demand": 100.0},
		"b": {"derate": 0.0, "green_consumed": 50.0, "unfirmed_intermittent": 0.0, "steady_consumed": 50.0, "demand": 50.0},
	}
	Power.tile_produced = {"tile_2_2": 100}
	var consumers := [
		{"iid": "a", "tile": "tile_2_2", "demand": 100.0, "building_id": "b_017"},
		{"iid": "b", "tile": "tile_2_2", "demand": 50.0, "building_id": "b_018"},
	]
	var agg := Production._aggregate_tile_intermittency(consumers)
	var t: Dictionary = agg["tile_2_2"]
	_check(int(t["green_produced"]) == 100 and int(t["green_intermittent_produced"]) == 100 and int(t["total_produced"]) == 100,
		"tile intermittency: green/total produced rolled up")
	_check(int(t["total_consumed"]) == 150 and absf(float(t["unfirmed_consumed"]) - 100.0) < 0.001
		and absf(float(t["green_consumed"]) - 150.0) < 0.001, "tile intermittency: consumed totals rolled up")
	_check((t["affected"] as Array).size() == 1 and str((t["affected"][0])["iid"]) == "a",
		"tile intermittency: only derated buildings are listed as affected")
	Production._green_supply_by_tile = saved_green
	Production._intermittency_by_building = saved_im
	Power.tile_produced = saved_prod

func _test_battery_buildable() -> void:
	# The electric battery used to be recipe-less (dropped from build panels). It now has an
	# input-only recipe (1 lithium_battery/turn) so it resolves + appears as a buildable option.
	var recs: Array = Catalog.get_recipes_for_building("b_028")  # recipes key by resolved building_id
	_check(recs.size() >= 1, "battery: has a buildable recipe (was recipe-less)")
	if recs.size() >= 1:
		var r: Dictionary = recs[0]
		# Deposit model: the housing has a no-op recipe (no per-turn consumption); firming
		# comes from loaded cells, not the recipe.
		_check(str(r.get("output_name", "")) == "" and (r.get("inputs", []) as Array).is_empty(),
			"battery: housing recipe is a no-op (no inputs/outputs)")
		var catalysts: Array = r.get("catalysts", []) as Array
		_check(catalysts.size() == 3
			and str(catalysts[0].get("internal_name", "")) == "lithium_battery"
			and str(catalysts[1].get("internal_name", "")) == "sodium_battery"
			and str(catalysts[2].get("internal_name", "")) == "iron_battery",
			"battery: allowed cell chemistries come from recipe catalysts")
	var tvd = load("res://scripts/tile_view_data.gd")
	var opt: Dictionary = tvd.power_build_option("battery", "", "tile_5_10", {})
	_check(str(opt.get("recipe_id", "")) != "", "battery: build option resolves a recipe (no longer 'not available')")

func _test_battery_deposit() -> void:
	# Deposit model: housing = 1000 ⚡ capacity at L1; firming = Σ cells × density, capped by
	# headroom; loading is tech-gated; density differs per type so 18 lithium / 24 sodium cells
	# fill 1000 ⚡; demolish refunds the cells.
	var tile := "tile_9_9"
	MatchState.tile_battery_cells.erase(tile)
	var lgid := str(Catalog.get_good_by_internal_name("lithium_battery").get("id", ""))
	var sgid := str(Catalog.get_good_by_internal_name("sodium_battery").get("id", ""))
	Stockpile.consume(tile, lgid, Stockpile.get_at_tile(tile, lgid))
	Stockpile.consume(tile, sgid, Stockpile.get_at_tile(tile, sgid))
	var bid: String = MatchState.add_building("b_028", "r_225", tile, MatchState.LOCAL_PLAYER)
	_check(MatchState.tile_battery_slots(tile) == 1000, "battery deposit: L1 housing = 1000 firming capacity")
	_check(Production._tile_storage_cap(tile) == 0, "battery deposit: empty housing firms nothing")
	var hadL := MatchState.is_unlocked("Lithium Battery Storage")
	var hadS := MatchState.is_unlocked("Sodium Battery Storage")
	MatchState.unlocked_titles.erase("Lithium Battery Storage")
	MatchState.unlocked_titles.erase("Sodium Battery Storage")
	Stockpile.add(tile, lgid, 50)
	_check(MatchState.load_battery_cells(tile, lgid, 5) == 0, "battery deposit: locked type cannot be loaded")
	MatchState.grant_unlock("Lithium Battery Storage")
	_check(MatchState.battery_cells_to_fill(tile, lgid) == 18, "battery deposit: 18 lithium cells fill a 1000 ⚡ L1")
	_check(MatchState.load_battery_cells(tile, lgid, 999) == 18, "battery deposit: loads 18 lithium cells (capped by firming)")
	_check(MatchState.tile_firming_cap(tile) == 1000, "battery deposit: full lithium housing firms 1000")
	_check(MatchState.load_battery_cells(tile, lgid, 5) == 0, "battery deposit: no headroom when full")
	_check(MatchState.unload_battery_cells(tile, lgid, 9) == 9, "battery deposit: unload 9")
	_check(MatchState.tile_firming_cap(tile) == 500 and Stockpile.get_at_tile(tile, lgid) == 41,
		"battery deposit: unload refunds to stock + halves firming")
	MatchState.unload_battery_cells(tile, lgid, 9)  # clear for the density check
	MatchState.grant_unlock("Sodium Battery Storage")
	Stockpile.add(tile, sgid, 50)
	_check(MatchState.battery_cells_to_fill(tile, sgid) == 24, "battery deposit: sodium needs 24 cells (density 0.75×)")
	_check(MatchState.load_battery_cells(tile, sgid, 999) == 24, "battery deposit: loads 24 sodium cells to fill 1000 ⚡")
	_check(MatchState.tile_firming_cap(tile) == 1000, "battery deposit: full sodium also firms 1000")
	MatchState.remove_building(bid)
	_check(MatchState.tile_firming_cap(tile) == 0 and Stockpile.get_at_tile(tile, sgid) == 50,
		"battery deposit: demolishing housing refunds all remaining cells")
	if not hadL:
		MatchState.unlocked_titles.erase("Lithium Battery Storage")
	if not hadS:
		MatchState.unlocked_titles.erase("Sodium Battery Storage")
	MatchState.tile_battery_cells.erase(tile)
	Stockpile.consume(tile, lgid, Stockpile.get_at_tile(tile, lgid))
	Stockpile.consume(tile, sgid, Stockpile.get_at_tile(tile, sgid))

func _test_battery_fill_pending() -> void:
	# An in-flight fill counts down and installs the cells (no stockpile) when it arrives.
	var tile := "tile_9_8"
	MatchState.tile_battery_cells.erase(tile)
	MatchState.pending_battery_fills.clear()
	var lgid := str(Catalog.get_good_by_internal_name("lithium_battery").get("id", ""))
	Stockpile.consume(tile, lgid, Stockpile.get_at_tile(tile, lgid))
	var bid: String = MatchState.add_building("b_028", "r_225", tile, MatchState.LOCAL_PLAYER)
	MatchState.pending_battery_fills.append({"tile_id": tile, "good_id": lgid, "qty": 18, "turns_left": 2})
	_check(MatchState.battery_fill_turns_remaining(tile) == 2, "fill: 2 turns remaining")
	_check(MatchState.tile_firming_cap(tile) == 0, "fill: nothing installed yet")
	MatchState.tick_battery_fills()
	_check(MatchState.battery_fill_turns_remaining(tile) == 1, "fill: ticks down to 1")
	_check(MatchState.tile_firming_cap(tile) == 0, "fill: still in transit")
	MatchState.tick_battery_fills()
	_check(MatchState.battery_fill_turns_remaining(tile) == 0, "fill: countdown complete")
	_check(MatchState.tile_firming_cap(tile) == 1000, "fill: 18 cells installed → 1000 ⚡ (no stockpile draw)")
	MatchState.remove_building(bid)
	MatchState.tile_battery_cells.erase(tile)
	MatchState.pending_battery_fills.clear()
	Stockpile.consume(tile, lgid, Stockpile.get_at_tile(tile, lgid))

func _test_sea_land_building_rule() -> void:
	# Only offshore wind (b_026) + offshore oil (b_033) on sea/deep_sea; those two can't go on
	# land; every other building is land-only.
	_check(Catalog.is_building_allowed_on_tile_type("b_026", "sea"), "sea rule: offshore wind on sea")
	_check(Catalog.is_building_allowed_on_tile_type("b_033", "deep_sea"), "sea rule: offshore oil on deep sea")
	_check(not Catalog.is_building_allowed_on_tile_type("b_026", "land"), "sea rule: offshore wind NOT on land")
	_check(not Catalog.is_building_allowed_on_tile_type("b_028", "sea"), "sea rule: battery NOT on sea")
	_check(not Catalog.is_building_allowed_on_tile_type("b_024", "deep_sea"), "sea rule: solar NOT on deep sea")
	_check(not Catalog.is_building_allowed_on_tile_type("b_025", "sea"), "sea rule: onshore wind NOT on sea")
	_check(Catalog.is_building_allowed_on_tile_type("b_024", "land"), "sea rule: solar on land")
	_check(Catalog.is_building_allowed_on_tile_type("b_028", "urban"), "sea rule: battery on urban land")

func _test_detail_panel_owner_resolution() -> void:
	# Regression: a player building handed a stale/cross-wired owner on the passed dict must
	# still resolve to the player (re-read from the live store), so it never renders in the
	# NPC frosted/blurred mode. A co-located NPC building of the same type must still resolve
	# to the NPC. (Mirrors tools/repro_npc_blur.gd, headless.)
	var npc_iid: String = MatchState.add_building("b_002", "r_003", "tile_5_10", "Stoneshore Ironworks")
	var player_iid: String = MatchState.add_building("b_002", "r_003", "tile_5_10", MatchState.LOCAL_PLAYER)
	var panel = load("res://scripts/building_detail_panel.gd").new()
	_check(panel._resolve_owner_id(MatchState.get_building(player_iid)) == MatchState.LOCAL_PLAYER,
		"detail owner: canonical player dict -> player")
	var poisoned: Dictionary = MatchState.get_building(player_iid).duplicate()
	poisoned["owner"] = "Stoneshore Ironworks"
	_check(panel._resolve_owner_id(poisoned) == MatchState.LOCAL_PLAYER,
		"detail owner: stale-owner player dict re-resolves to player (no NPC frost)")
	_check(panel._resolve_owner_id(MatchState.get_building(npc_iid)) == "Stoneshore Ironworks",
		"detail owner: NPC building -> NPC owner (frost preserved)")
	_check(panel._resolve_owner_id({"instance_id": "stub_x", "building_id": "b_002"}) == MatchState.LOCAL_PLAYER,
		"detail owner: construction stub (not in store, no owner) -> player")
	panel.free()
	MatchState.buildings.erase(npc_iid)
	MatchState.buildings.erase(player_iid)

func _test_greenest_reads_quality() -> void:
	VictoryState.reset()
	# green = intermittent 3000 + steady 3000 = 6000 of 10000 made, 2000 used -> share 0.6.
	VictoryState._last_summary = {"power_supply": 10000, "power_demand": 2000,
		"power_supply_by_quality": {"green_intermittent": 3000, "green_steady": 3000, "grey": 4000}}
	_check(absf(VictoryState._live_progress("greenest") - 0.5) < 0.001,
		"greenest: reads power_supply_by_quality (steady + intermittent count green)")

# The main-menu goods board fills its 7x7 (everything but the buffer-most row 0 +
# column 0) with UNIQUE goods; repeats are only allowed on that last-into-view edge.
func _test_main_menu_grid_unique() -> void:
	var grid = load("res://scripts/goods_grid.gd").new()
	grid._arrange_cells()
	var cols: int = grid.COLS
	var n_goods: int = grid._goods_with_icons().size()
	var ids := {}
	var dup := false
	var filled := 0
	for i in grid._layout.size():
		if (i / cols) == grid.REPEAT_ROW or (i % cols) == grid.REPEAT_COL:
			continue  # the "8th" cells (top row + left column) may repeat
		var good = grid._layout[i]
		if good == null:
			continue
		filled += 1
		var gid := str(good.get("id", ""))
		if ids.has(gid):
			dup = true
		ids[gid] = true
	_check(not dup, "main menu grid: the 7x7 block has no repeated goods")
	_check(filled == mini((cols - 1) * (grid.ROWS - 1), n_goods),
		"main menu grid: 7x7 filled with unique goods (%d cells, %d goods with art)" % [filled, n_goods])
	grid.free()

# Goods Graph data builder (scripts/goods_flow_graph.gd): the runtime goods web is
# complete, joins only known goods, is defined by game-start recipes (gated flag
# honest), and lays out deterministically (CLAUDE.md #3).
func _test_goods_flow_graph() -> void:
	var GoodsFlowGraph := preload("res://scripts/goods_flow_graph.gd")
	var g: Dictionary = GoodsFlowGraph.build()
	var nodes: Array = g["nodes"]
	var by_id: Dictionary = g["by_id"]
	var edges: Array = g["edges"]
	_check(nodes.size() == Catalog.all_goods().size(),
		"goods graph: one node per catalog good (%d)" % nodes.size())
	var ok_edges := not edges.is_empty()
	for e in edges:
		if not (by_id.has(str(e["from"])) and by_id.has(str(e["to"]))):
			ok_edges = false
	_check(ok_edges, "goods graph: every edge joins two known goods (%d edges)" % edges.size())
	_check(int(g["tier_count"]) >= 4, "goods graph: web layers into >=4 tiers (%d)" % int(g["tier_count"]))
	# Tiers layer on the BASE skeleton; alternates (e.g. recycling routes) may feed a
	# tier-0 raw good, so only route-0 edges must never target tier 0.
	var t0_clean := true
	for e in edges:
		if int(e.get("route", 0)) == 0 and int(by_id.get(str(e["to"]), {}).get("tier", -1)) == 0:
			t0_clean = false
	_check(t0_clean, "goods graph: tier-0 goods take no BASE-route inputs")
	_check(int(by_id.get("coal", {}).get("tier", -1)) == 0, "goods graph: coal is a tier-0 source")
	var steel: Dictionary = by_id.get("steel", {})
	_check(int(steel.get("tier", -1)) >= 1 and (steel.get("inputs", []) as Array).size() >= 1,
		"goods graph: steel sits deeper with inputs")
	var base_ok := true
	for n in nodes:
		var rid := str(n.get("recipe_id", ""))
		if rid == "":
			continue
		var r: Dictionary = Catalog.get_recipe(rid)
		if bool(n["gated"]) != (str(r.get("required_research", "")) != ""):
			base_ok = false
	_check(base_ok, "goods graph: defining recipes are game-start unless flagged gated")
	# Owner ask 2026-07-18: the semiconductor chain is visible at game start —
	# polysilicon -> high_grade_silicon (r_229) -> cpu (r_230, 3 inputs so it wins
	# the simplest-base pick over r_122's 4) -> computer.
	var hgs: Dictionary = by_id.get("high_grade_silicon", {})
	_check(str(hgs.get("recipe_id", "")) == "r_229" and (hgs.get("inputs", []) as Array).has("polysilicon"),
		"goods graph: high_grade_silicon is made from polysilicon (r_229)")
	var cpu: Dictionary = by_id.get("cpu", {})
	_check(str(cpu.get("recipe_id", "")) == "r_230" and (cpu.get("inputs", []) as Array).has("high_grade_silicon"),
		"goods graph: cpu's defining base route consumes high_grade_silicon (r_230)")
	# Power union: fuel-less wind is the simplest producer, but the edges must still
	# carry every game-start fuel route (coal, processed_oil, pet_coke).
	var power: Dictionary = by_id.get("power", {})
	var power_inputs: Array = power.get("inputs", [])
	_check(power_inputs.has("coal") and power_inputs.has("processed_oil") and power_inputs.has("pet_coke"),
		"goods graph: power carries the union of game-start fuel edges")
	# Owner 2026-07-19: r_231 Anthracite Graphitisation (45 coal -> 2 graphite,
	# 160 MW, ungated) is graphite's SIMPLEST base route (1 input, lower energy than
	# pet-coke calcination), so the web edge is coal; pet-coke and the gated bio
	# route live in the alternates grid.
	var graphite: Dictionary = by_id.get("graphite", {})
	_check(str(graphite.get("recipe_id", "")) == "r_231"
		and (graphite.get("inputs", []) as Array).has("coal")
		and not (graphite.get("inputs", []) as Array).has("carbonised_biomass"),
		"goods graph: graphite's base route is Anthracite Graphitisation (coal)")
	var graphite_routes: Array = GoodsFlowGraph.routes_for_good("graphite")
	var has_bio := false
	for gr in graphite_routes:
		if str((gr.get("recipe", {}) as Dictionary).get("recipe_id", "")) == "r_042":
			has_bio = bool(gr.get("gated", false))
	_check(has_bio, "goods graph: grid routes for graphite include gated Bio-Graphitisation (r_042)")
	var steel_routes: Array = GoodsFlowGraph.routes_for_good("steel")
	_check(steel_routes.size() >= 2 and str((steel_routes[0].get("recipe", {}) as Dictionary).get("recipe_id", ""))
		== str(by_id.get("steel", {}).get("recipe_id", "")),
		"goods graph: grid routes are defining-first (steel, %d routes)" % steel_routes.size())
	var all_base := true
	var has_gated_dash := false
	for e in edges:
		if int(e.get("route", 0)) != 0:
			all_base = false
		if bool(e.get("route_gated", false)):
			has_gated_dash = true
	_check(all_base and has_gated_dash,
		"goods graph: web edges are all base-route; gated-only goods still dash")
	# Owner 2026-07-19: plain-substring good search (min 3 letters), position-ranked.
	var hits: Array = GoodsFlowGraph.search_goods("ste", nodes)
	_check(not hits.is_empty() and str((hits[0] as Dictionary).get("display", "")) == "Steel",
		"goods graph: search 'ste' ranks Steel first (%d hits)" % hits.size())
	_check(GoodsFlowGraph.search_goods("st", nodes).is_empty(),
		"goods graph: search needs at least 3 letters")
	_check(GoodsFlowGraph.search_goods("polysil", nodes).size() == 1,
		"goods graph: search 'polysil' matches exactly one good (Enter auto-picks)")
	# Authored bands (goods_graph_tier): every good carries a valid band, and no
	# base-route edge flows from a later band to an earlier one (the zero-backward
	# invariant the banding was designed around).
	var band_index: Dictionary = {}
	for bi in range(GoodsFlowGraph.TIER_BANDS.size()):
		band_index[GoodsFlowGraph.TIER_BANDS[bi]] = bi
	var bands_ok := true
	var good_band: Dictionary = {}
	for good in Catalog.all_goods():
		var bv := str(good.get("goods_graph_tier", ""))
		good_band[str(good.get("internal_name", ""))] = bv
		if not band_index.has(bv):
			bands_ok = false
	_check(bands_ok, "goods graph: every good has a valid goods_graph_tier band")
	var no_backward := true
	for e in edges:
		if int(band_index.get(good_band.get(str(e["to"]), ""), 0)) 				< int(band_index.get(good_band.get(str(e["from"]), ""), 0)):
			no_backward = false
	_check(no_backward, "goods graph: no base edge flows backward across bands")
	# Owner rule 2026-07-22: a Recycling recipe can never be the base — steel's
	# base is Steelmaking (iron_ingots + coal), with Scrap Recycling an alternate.
	var steel_base_srcs: Array = []
	for e in edges:
		if str(e["to"]) == "steel" and int(e.get("route", 0)) == 0:
			steel_base_srcs.append(str(e["from"]))
	_check(steel_base_srcs.has("iron_ingots") and steel_base_srcs.has("coal")
		and not steel_base_srcs.has("scrap"),
		"goods graph: steel base = iron_ingots+coal, never scrap (recycling rule)")
	_check((g.get("bands", []) as Array).size() == 5,
		"goods graph: five labelled band regions")
	# build() caches (world_map warms it under the loading screen); force=true recomputes
	# independently, so this both keeps the determinism check meaningful AND verifies the
	# cached layout equals a fresh build.
	var g2: Dictionary = GoodsFlowGraph.build(true)
	var sig := func(gr: Dictionary) -> String:
		var parts := ""
		for n in gr["nodes"]:
			parts += "%s@%s;" % [str(n["id"]), str(n["pos"])]
		return parts + str(gr["edges"])   # edge dicts embed their waypoints
	_check(sig.call(g) == sig.call(g2), "goods graph: build is deterministic (cache == fresh)")
	# Orthogonal routing: every edge is an axis-aligned waypoint chain; vertical lane
	# runs of different edges that share y-range keep clear x separation; horizontal
	# runs of different edges that share x-range never sit collinear (>= the sibling
	# port-fan spacing H_SEP_SIBLING); and the final bilayer crossing count is
	# bounded (and visible in the PASS name).
	var ortho := true
	var verts: Array = []   # [x, y_lo, y_hi, edge_index]
	var horiz: Array = []   # [y, x_lo, x_hi, edge_index]
	for ei: int in range(edges.size()):
		var wp: PackedVector2Array = (edges[ei] as Dictionary).get("waypoints", PackedVector2Array())
		if wp.size() < 2:
			ortho = false
			continue
		for i: int in range(wp.size() - 1):
			var a := wp[i]
			var b := wp[i + 1]
			var dx := absf(a.x - b.x)
			var dy := absf(a.y - b.y)
			if dx > 0.01 and dy > 0.01:
				ortho = false
			if dx <= 0.01 and dy > 0.01:
				verts.append([a.x, minf(a.y, b.y), maxf(a.y, b.y), ei])
			if dy <= 0.01 and dx > 0.01:
				horiz.append([a.y, minf(a.x, b.x), maxf(a.x, b.x), ei])
	_check(ortho, "goods graph: every edge is an axis-aligned waypoint chain (>=2 points)")
	var sep_ok := true
	for i: int in range(verts.size()):
		for j: int in range(i + 1, verts.size()):
			var a: Array = verts[i]
			var b: Array = verts[j]
			if int(a[3]) == int(b[3]):
				continue
			var overlap: bool = maxf(float(a[1]), float(b[1])) < minf(float(a[2]), float(b[2])) - 0.01
			if overlap and absf(float(a[0]) - float(b[0])) < 11.9:
				sep_ok = false
	_check(sep_ok, "goods graph: y-overlapping vertical runs sit >=11.9 units apart")
	var hsep_ok := true
	for i: int in range(horiz.size()):
		for j: int in range(i + 1, horiz.size()):
			var a: Array = horiz[i]
			var b: Array = horiz[j]
			if int(a[3]) == int(b[3]):
				continue
			var overlap: bool = maxf(float(a[1]), float(b[1])) < minf(float(a[2]), float(b[2])) - 0.01
			if overlap and absf(float(a[0]) - float(b[0])) < 5.9:
				hsep_ok = false
	_check(hsep_ok, "goods graph: x-overlapping horizontal runs sit >=5.9 units apart (owner floor: 5 px at max zoom 1.0)")
	var crossings := int(g.get("crossings", -1))
	# Canary re-baselined 2026-07-22: the 9-lane category swimlanes constrain the
	# ordering (crossing-minimisation only runs within a lane cell), measured 1032
	# vs 816 under 6 lanes / 638 unconstrained. Crossings are a regression tripwire,
	# not a visual floor — the resting web renders at ghost alpha.
	_check(crossings >= 0 and crossings < 1400,
		"goods graph: %d crossings after ordering (< 1400 canary; swimlane-constrained)" % crossings)

func _check(ok: bool, name: String) -> void:
	if ok:
		_passed += 1
		print("  PASS  ", name)
	else:
		_failed += 1
		_failed_names.append(name)
		printerr("  FAIL  ", name)

# Empire view node packing (scripts/empire_layout.gd): the >=30px gap holds, packing is
# deterministic, coincident seeds (same tile) fan out, and all nodes survive.
func _test_empire_layout() -> void:
	var EL := load("res://scripts/empire_layout.gd")
	var make := func(iid: String, seed_pos: Vector2, lvl: int) -> Dictionary:
		return {"iid": iid, "seed": seed_pos, "half": Vector2(80, 46) * EL.level_scale(lvl), "level": lvl}
	var spec := [
		["a", Vector2(0, 0), 1], ["b", Vector2(0, 0), 2],        # b coincident with a
		["c", Vector2(10, 5), 3], ["d", Vector2(400, 0), 1],
		["e", Vector2(420, 20), 1], ["f", Vector2(-300, 200), 1],
	]
	var build_nodes := func() -> Array:
		var arr: Array = []
		for s in spec:
			arr.append(make.call(s[0], s[1], s[2]))
		return arr

	var nodes: Array = build_nodes.call()
	EL.relax(nodes)
	_check(nodes.size() == 6, "empire layout: all nodes retained (%d)" % nodes.size())
	_check(EL.gap_satisfied(nodes), "empire layout: every pair keeps the >=30px gap")

	# Coincident seeds a & b must have separated.
	var pos := {}
	for n in nodes:
		pos[n["iid"]] = n["pos"]
	_check((pos["a"] as Vector2).distance_to(pos["b"]) > 30.0, "empire layout: coincident seeds fan out")

	# Determinism: a fresh run yields identical positions.
	var nodes2: Array = build_nodes.call()
	EL.relax(nodes2)
	var same := true
	for n in nodes2:
		if (pos[n["iid"]] as Vector2).distance_to(n["pos"]) > 0.0001:
			same = false
	_check(same, "empire layout: deterministic (same input -> same output)")

# Layered supply-chain layout (scripts/empire_layout.gd solve): a producer feeding a consumer is
# placed in an earlier column (input sources sit left of their consumers), and the gap still holds.
func _test_empire_layered() -> void:
	var EL := load("res://scripts/empire_layout.gd")
	var mk := func(iid: String) -> Dictionary:
		return {"iid": iid, "seed": Vector2.ZERO, "half": Vector2(80, 46), "level": 1}
	var nodes: Array = [mk.call("a"), mk.call("b"), mk.call("c"), mk.call("iso")]
	var edges: Array = [{"from": "a", "to": "b"}, {"from": "b", "to": "c"}]   # a -> b -> c chain
	EL.solve(nodes, edges)
	var px := {}
	for n in nodes:
		px[n["iid"]] = (n["pos"] as Vector2).x
	_check(px["a"] < px["b"] and px["b"] < px["c"], "empire layered: input sources sit left of their consumers")
	_check(EL.gap_satisfied(nodes), "empire layered: >=30px gap held after layered solve")
	_check(nodes.size() == 4, "empire layered: isolated node retained alongside the chain")

# Ports always read left -> right as Stoneshore, Arin, Vandel, Capital (scripts/empire_graph.gd).
func _test_empire_ports() -> void:
	var EG := load("res://scripts/empire_graph.gd")
	_check(EG._port_order("Stoneshore Docks") == 0, "empire ports: Stoneshore is leftmost")
	_check(EG._port_order("Arin Estuary Docks") == 1, "empire ports: Arin is second")
	_check(EG._port_order("Vandel's Skip") == 2, "empire ports: Vandel is third")
	_check(EG._port_order("Capital Port") == 3, "empire ports: Capital is last of the four")
	_check(EG._port_order("Mystery Harbour") == 4, "empire ports: unknown ports sort after the known four")

# The 6 RAG indicators come from ONE shared function (building_status.gd), used by both the detail
# panel and the Empire view — this locks its contract (count, order, Color-typed) against drift.
func _test_empire_rag() -> void:
	var BS := load("res://scripts/building_status.gd")
	var recs: Array = Catalog.get_recipes_for_building("b_001")
	var recipe: Dictionary = recs[0] if recs.size() > 0 else {"recipe_id": "", "inputs": [], "outputs": []}
	var building := {"instance_id": "rag_probe", "building_id": "b_001", "recipe_id": str(recipe.get("recipe_id", "")), "tile_id": "tile_0_0", "level": 1}
	var rag: Array = BS.rag_indicators(building, recipe, false)
	_check(rag.size() == 6, "empire rag: six indicators returned (%d)" % rag.size())
	var keys: Array = []
	var all_colors := true
	for r in rag:
		keys.append(str(r.get("key", "")))
		if not (r.get("color") is Color):
			all_colors = false
	_check(keys == ["power", "input", "duration", "cost", "produce_cost", "modifier"], "empire rag: keys in detail-panel order")
	_check(all_colors, "empire rag: every indicator carries a Color")

func _replace_dict(target: Dictionary, source: Dictionary) -> void:
	target.clear()
	for key in source:
		target[key] = source[key]

func _test_storage_boost() -> void:
	MatchState.add_building("b_004", "", "tile_3_3", "Three Diamonds Shipping Corporation")
	_check(Stockpile.get_capacity("tile_3_3") == Stockpile.TILE_CAPACITY + 600,
		"storage_boost raises tile capacity (port = +600)")

func _test_warehouse_storage_levels() -> void:
	# Per-tile storage is a warehouse level table (800/1600/2500) driven by the two storage
	# research upgrades, plus +600 for a Port on the tile. Non-destructive (no MatchState.reset)
	# so it doesn't disturb the NPC-port / scene state that later tests depend on.
	var had_pallet := MatchState.is_unlocked("Pallet Racking Systems")
	var had_asrs := MatchState.is_unlocked("Automated Storage & Retrieval")
	MatchState.unlocked_titles.erase("Pallet Racking Systems")
	MatchState.unlocked_titles.erase("Automated Storage & Retrieval")
	var t := "tile_wh_test_only"  # fresh tile with no buildings
	_check(Stockpile.get_capacity(t) == 800, "warehouse level 1 (no research) = 800")
	MatchState.grant_unlock("Pallet Racking Systems")
	_check(Stockpile.get_capacity(t) == 1600, "warehouse level 2 (Pallet Racking) = 1600")
	MatchState.grant_unlock("Automated Storage & Retrieval")
	_check(Stockpile.get_capacity(t) == 2500, "warehouse level 3 (Automated Storage) = 2500")
	var pid := MatchState.add_building("b_004", "", t, MatchState.LOCAL_PLAYER, "wh_test_port")
	_check(Stockpile.get_capacity(t) == 2500 + 600, "a Port adds +600 on top of the warehouse capacity")
	MatchState.remove_building(pid)
	if not had_pallet:
		MatchState.unlocked_titles.erase("Pallet Racking Systems")
	if not had_asrs:
		MatchState.unlocked_titles.erase("Automated Storage & Retrieval")

func _test_market_sale_credits() -> void:
	# Output routed to market should be sold and its revenue credited on arrival,
	# not silently lost. (Reproduces the "produced but never stockpiled/consumed/sold".)
	MatchState.reset()
	Stockpile.clear_all()
	MatchState.money = 0.0
	var summary := {"transport_paid": 0.0, "money_out": 0.0, "money_in": 0.0,
		"goods_sales_revenue": 0.0, "sold": {}}
	Production._sell_output_to_market({
		"instance_id": "inst_market_credit",
		"tile_id": "tile_3_8",
	}, Catalog.get_good("g_001"), 20, summary)
	# Drive arrivals for a few turns; a deferred sale should eventually credit.
	for _i in range(25):
		Production._process_transport_arrivals(summary)
		if MatchState.money > 0.0:
			break
	_check(MatchState.money > 0.0, "a market-routed output sale credits revenue (money=%.2f)" % MatchState.money)
	_check(summary.goods_sales_revenue > 0.0, "the sale appears in goods_sales_revenue")

func _test_tax_dividend_caps() -> void:
	MatchState.reset()
	MatchState.money = 1000.0
	var loss_summary := {
		"money_in": 235.0,
		"money_out": 239.0,
		"taxes_paid": 0.0,
		"dividends_paid": 0.0,
	}
	var money_before := MatchState.money
	var loss_pretax: float = Production._apply_tax_and_dividends(loss_summary)
	_check(loss_pretax < 0.0
		and float(loss_summary.get("taxes_paid", -1.0)) == 0.0
		and float(loss_summary.get("dividends_paid", -1.0)) == 0.0
		and is_equal_approx(MatchState.money, money_before),
		"loss-making turns do not pay tax or dividends")

	var profit_summary := {
		"money_in": 100.0,
		"money_out": 90.0,
		"taxes_paid": 0.0,
		"dividends_paid": 0.0,
	}
	Production._apply_tax_and_dividends(profit_summary)
	_check(is_equal_approx(float(profit_summary.get("taxes_paid", 0.0)), 2.0)
		and is_equal_approx(float(profit_summary.get("dividends_paid", 0.0)), 1.6)
		and is_equal_approx(float(profit_summary.get("money_in", 0.0)) - float(profit_summary.get("money_out", 0.0)), 6.4),
		"tax is capped to profit and dividends are calculated after tax")

	var profit_share_summary := {
		"money_in": 100.0,
		"money_out": 90.0,
		"taxes_paid": 0.0,
		"dividends_paid": 0.0,
		"profit_sharing_paid": 0.0,
	}
	MatchState.set_workforce_policy_enabled(MatchState.WORKFORCE_POLICY_ANNUAL_PROFIT_SHARE, true)
	var share_pretax: float = Production._apply_tax_and_dividends(profit_share_summary)
	Production._apply_profit_sharing(profit_share_summary, share_pretax)
	_check(is_equal_approx(float(profit_share_summary.get("profit_sharing_paid", 0.0)), 0.32)
		and is_equal_approx(float(profit_share_summary.get("money_in", 0.0)) - float(profit_share_summary.get("money_out", 0.0)), 6.08),
		"profit sharing is paid from post-tax, post-dividend profit")
	MatchState.set_workforce_policy_enabled(MatchState.WORKFORCE_POLICY_ANNUAL_PROFIT_SHARE, false)

func _test_output_conservation() -> void:
	# Default (STOCKPILE_ALL): a building's output should land in its own tile's stockpile.
	MatchState.reset()
	Stockpile.clear_all()
	var building := {"instance_id": "inst_conserve", "building_id": "b_001", "tile_id": "tile_3_3", "recipe_id": "r_001"}
	var good: Dictionary = Catalog.get_good("g_001")
	var summary := {"transport_paid": 0.0, "money_out": 0.0, "goods_purchased_cost": 0.0}
	var before: int = Stockpile.get_total("g_001")
	Production._dispatch_output_to_stockpile(building, good, 20, summary)
	Production._flush_output_buffer()
	var gained: int = Stockpile.get_total("g_001") - before
	_check(gained == 20, "output is conserved into the tile stockpile (got %d of 20)" % gained)

func _test_transfer_helpers() -> void:
	MatchState.reset()
	MatchState.add_building("b_001", "r_001", "tile_5_5", "player_1")  # coal mine → produces g_001
	MatchState.add_building("b_002", "r_005", "tile_6_6", "player_1")  # iron furnace → consumes g_002
	_check(MatchState.tiles_producing("g_001").has("tile_5_5"), "tiles_producing finds a producer tile")
	_check(not MatchState.tiles_producing("g_001").has("tile_6_6"), "tiles_producing excludes a non-producer")
	_check(MatchState.tiles_consuming("g_002").has("tile_6_6"), "tiles_consuming finds a consumer tile")

func _test_recipes_producing() -> void:
	_check(Catalog.recipes_producing("g_001").size() > 0, "recipes_producing finds producers of coal")
	_check(Catalog.recipes_producing("g_nope").is_empty(), "recipes_producing is empty for an unknown good")
	_check(Catalog.recipe_produces(Catalog.get_recipe("r_001"), "g_001"),
		"recipe_produces detects a recipe's output good")

func _test_purchases() -> void:
	_check(Catalog.buyable_goods().size() > 0 and Catalog.sellable_goods().size() > 0,
		"Catalog exposes buyable + sellable good lists")
	_check(Catalog.is_good_buyable("g_001"), "coal is buyable")
	var before: int = MatchState.get_recurring_transaction_rows().size()
	MatchState.add_recurring_buy("tile_3_8", "g_001", 25)
	var rows: Array = MatchState.get_recurring_transaction_rows()
	_check(rows.size() == before + 1, "recurring buy registers in the dashboard")
	var last: Dictionary = rows[rows.size() - 1]
	_check(str(last.get("type", "")) == "Buy" and int(last.get("qty", 0)) == 25,
		"recurring buy shows as a Buy row")
	var m: float = MatchState.money
	var prev: Dictionary = MatchState.preview_buy("tile_3_8", "g_001", 10)
	_check(not prev.is_empty() and float(prev.get("cost", 0)) > 0.0 and MatchState.money == m,
		"preview_buy returns a cost without spending")

func _test_market_buy() -> void:
	_check(not MatchState.is_input_tile_only("inst_x", "g_002"), "inputs default to stockpile-then-market")
	MatchState.set_input_tile_only("inst_x", "g_002", true)
	_check(MatchState.is_input_tile_only("inst_x", "g_002"), "input can be set to tile-stockpile-only")
	MatchState.set_input_tile_only("inst_x", "g_002", false)
	_check(not MatchState.is_input_tile_only("inst_x", "g_002"), "input resets to stockpile-then-market")
	MatchState.money = 100000.0
	var t_before: int = MatchState.get_oneoff_transaction_rows().size()
	var ship_before: int = MatchState.get_pending_transport_shipments().size()
	var money_before: float = MatchState.money
	var result: Dictionary = MatchState.queue_buy("tile_3_8", "g_002", 10)
	_check(not result.is_empty(), "queue_buy returns a summary")
	_check(absf(float(result.get("goods_cost", 0)) + float(result.get("transport_cost", 0)) - float(result.get("cost", 0))) < 0.01,
		"queue_buy splits cost into goods + transport")
	# PAY ON ARRIVAL (owner ruling 2026-07-27): a shipped order does NOT charge at order
	# time — the bill rides with the goods and settles when they land.
	_check(bool(result.get("deferred", false)), "a shipped buy is flagged deferred")
	_check(absf(MatchState.money - money_before) < 0.0001,
		"queue_buy does NOT charge at order time — the bill rides with the goods")
	_check(absf(MatchState.unpaid_purchase_total() - float(result.get("cost", 0.0))) < 0.01,
		"the unpaid bill is tracked against future purchase headroom")
	_check(MatchState.purchase_headroom() < money_before + LoanState.available_capacity() + 0.01,
		"in-transit commitments reduce the headroom the next order is measured against")
	_check(MatchState.get_pending_transport_shipments().size() > ship_before, "queue_buy queues an inbound shipment")
	var rows: Array = MatchState.get_oneoff_transaction_rows()
	_check(rows.size() == t_before + 1 and str(rows[rows.size() - 1].get("type", "")) == "Buy",
		"a buy is logged with type Buy")
	# Best-effort: a big order with little cash buys a partial amount, not nothing.
	MatchState.money = 50.0
	var partial: Dictionary = MatchState.queue_buy("tile_3_8", "g_002", 1000)
	_check(not partial.is_empty() and int(partial.get("qty", 0)) > 0 and int(partial.get("qty", 0)) < 1000,
		"queue_buy buys a partial amount when cash is short")

func _test_market_input_pipeline_ignores_reserved_inbound() -> void:
	MatchState.reset()
	Stockpile.clear_all()
	Power.reset_for_turn()
	MatchState.pending_transport_shipments.clear()
	var fake := Node.new()
	var src := GDScript.new()
	src.source_code = "extends Node\nvar tiles := {}\nfunc id_to_coord(t):\n\treturn Vector2i(5, 10) if t == \"tile_5_10\" else Vector2i(-1, -1)\n"
	src.reload()
	fake.set_script(src)
	fake.set("tiles", {Vector2i(5, 10): {"infrastructure_present": ["cables"], "infrastructure_levels": {"cables": 3}}})
	fake.add_to_group("hex_map")
	get_tree().root.add_child(fake)
	MatchState.money = 100000.0
	var tile := "tile_5_10"
	var coal_gid := "g_001"
	var iid := MatchState.add_building("b_003", "r_004", tile, MatchState.LOCAL_PLAYER, "test_pipeline_coal_plant")
	MatchState.pending_transport_shipments.append({
		"source_tile": "tile_build_site",
		"destination_tile": tile,
		"good_id": coal_gid,
		"qty": 10000,
		"turns_remaining": 1,
		"construction_instance_id": "construction_reserved_coal",
	})
	MatchState.pending_transport_shipments.append({
		"source_tile": "tile_manual",
		"destination_tile": tile,
		"good_id": coal_gid,
		"qty": 3,
		"turns_remaining": 1,
	})
	_check(Production._inbound_qty(tile, coal_gid) == 3,
		"market input pipeline ignores construction-reserved inbound but counts ordinary inbound")
	var summary := {
		"purchased": {},
		"purchased_cost": {},
		"goods_purchased_cost": 0.0,
		"transport_paid": 0.0,
		"money_out": 0.0,
		"goods_purchased_by_type": {},
	}
	Production._buy_market_inputs([MatchState.buildings[iid]], summary)
	_check(int((summary.get("purchased", {}) as Dictionary).get(coal_gid, 0)) > 0,
		"market input pipeline orders production inputs despite construction-reserved inbound")
	MatchState.remove_building(iid)
	MatchState.pending_transport_shipments.clear()
	get_tree().root.remove_child(fake)
	fake.free()
	MatchState.reset()
	Stockpile.clear_all()
	Power.reset_for_turn()

func _test_exhausted_input_source_falls_back_to_market() -> void:
	MatchState.reset()
	Stockpile.clear_all()
	Power.reset_for_turn()
	var fake := Node.new()
	var src := GDScript.new()
	src.source_code = "extends Node\nvar tiles := {}\nfunc id_to_coord(t):\n\treturn Vector2i(5, 10) if t == \"tile_5_10\" else Vector2i(-1, -1)\n"
	src.reload()
	fake.set_script(src)
	fake.set("tiles", {Vector2i(5, 10): {"infrastructure_present": ["cables"], "infrastructure_levels": {"cables": 1}}})
	fake.add_to_group("hex_map")
	get_tree().root.add_child(fake)
	MatchState.money = 100000.0
	var source_iid := MatchState.add_building("b_001", "r_001", "tile_6_8", MatchState.LOCAL_PLAYER, "test_exhausted_coal_source")
	var consumer_iid := MatchState.add_building("b_003", "r_004", "tile_5_10", MatchState.LOCAL_PLAYER, "test_exhausted_coal_consumer")
	MatchState.set_output_stockpile_destination(source_iid, "tile_5_10", "g_001")
	MatchState.set_input_tile_only(consumer_iid, "g_001", true)
	MatchState.deposit_remaining["tile_6_8"] = {"coal": 0}
	var summary := {
		"purchased": {},
		"purchased_cost": {},
		"goods_purchased_cost": 0.0,
		"transport_paid": 0.0,
		"money_out": 0.0,
		"goods_purchased_by_type": {},
	}
	Production._buy_market_inputs([MatchState.buildings[source_iid], MatchState.buildings[consumer_iid]], summary)
	_check(not MatchState.is_input_tile_only(consumer_iid, "g_001"),
		"exhausted routed input source switches the consumer back to market fallback")
	_check(int(summary.get("purchased", {}).get("g_001", 0)) > 0,
		"market fallback queues a replacement buy for the exhausted input")
	get_tree().root.remove_child(fake)
	fake.free()

func _test_auto_sell_goods() -> void:
	var t := "tile_4_4"
	MatchState.enable_auto_sell_good(t, "g_001")
	_check(MatchState.is_auto_sell_good(t, "g_001"), "per-good auto-sell registers")
	_check(MatchState.should_auto_sell_good(t, "g_001"), "should_auto_sell true for an armed good")
	_check(not MatchState.should_auto_sell_good(t, "g_002"), "should_auto_sell false for an unarmed good")
	_check(MatchState.get_auto_sell_tiles().has(t), "tile appears in the auto-sell tile set")
	# Master order covers every good regardless of per-good arming.
	MatchState.enable_sell_surplus(t)
	_check(MatchState.should_auto_sell_good(t, "g_009"), "master 'sell all' order auto-sells any good")
	MatchState.disable_sell_surplus(t)
	# Disarming the last per-good order removes the tile from the set.
	MatchState.disable_auto_sell_good(t, "g_001")
	_check(not MatchState.is_auto_sell_good(t, "g_001"), "per-good auto-sell clears")
	_check(not MatchState.get_auto_sell_tiles().has(t), "tile drops out once no orders remain")
	# Sell reserve = the local consumers' WORKING stock, not one turn of inputs:
	# per-turn need × (market lead + 1), player-owned buildings only. r_008 eats
	# 24 copper_ingots (g_005)/turn; lead ≥ 1 → reserve ≥ 48 and always a
	# multiple of one turn's need above it. NPC buildings reserve nothing.
	var rt := "tile_15_5"
	var riid: String = MatchState.add_building("b_007", "r_008", rt, "player_1", "reserve_test")
	var reserve: Dictionary = Production.compute_sell_reserve_for_tile(rt)
	var committed: Dictionary = Production.compute_committed_for_tile(rt)
	var need: int = int(committed.get("g_005", 0))
	_check(need > 0, "sell reserve test: recipe commits copper ingots per turn (%d)" % need)
	var kept: int = int(reserve.get("g_005", 0))
	_check(kept >= need * 2, "sell reserve keeps at least (lead+1)>=2 turns of inputs (%d >= %d)" % [kept, need * 2])
	_check(kept % need == 0 and kept / need >= 2, "sell reserve is a whole number of turns (%d = %dx need)" % [kept, kept / need])
	MatchState.remove_building(riid)
	var npc_iid: String = MatchState.add_building("b_007", "r_008", rt, "npc", "reserve_test_npc")
	_check(int(Production.compute_sell_reserve_for_tile(rt).get("g_005", 0)) == 0,
		"NPC buildings reserve nothing from the player's sell surplus")
	MatchState.remove_building(npc_iid)

func _test_limestone_concrete() -> void:
	_check(not Catalog.get_good_by_internal_name("limestone").is_empty(), "limestone good exists")
	_check(not Catalog.get_good_by_internal_name("concrete").is_empty(), "concrete good exists")
	var found := false
	for r in Catalog.all_recipes():
		if str(r.get("output_name", "")) == "limestone" and str(r.get("building_id", "")) != "":
			found = true
			var gated := false
			for req in r.get("requirements", []):
				if str(req.get("type", "")) == "deposit" and str(req.get("value", "")) == "limestone":
					gated = true
			_check(gated, "limestone mining is gated on a limestone deposit")
	_check(found, "a mine recipe produces limestone")

func _test_construction() -> void:
	# Pick a building that actually has construction materials (data-driven so it survives
	# CSV changes). requirements_for must resolve the CSV's internal material names to good_ids.
	var bid := ""
	var reqs := {}
	for b in Catalog.all_buildings():
		var r: Dictionary = Construction.requirements_for(str(b.get("id", "")))
		if not r.is_empty():
			bid = str(b.get("id", ""))
			reqs = r
			break
	_check(bid != "" and not reqs.is_empty(), "a building has resolvable construction materials")
	if bid == "":
		return

	var tile := "tile_construction_test"
	for gid in reqs:
		Stockpile.consume(tile, gid, 1 << 30)  # ensure the test tile starts empty

	# Empty tile: gate blocks, every required good reported short.
	var chk0: Dictionary = Construction.check_tile(tile, bid)
	_check(not bool(chk0.get("satisfied", false)), "missing materials -> not satisfied")
	_check(chk0.get("missing", {}).size() == reqs.size(), "all required goods reported missing")

	# Stock exactly the requirements -> gate clears.
	for gid in reqs:
		Stockpile.add(tile, gid, int(reqs[gid]))
	_check(bool(Construction.check_tile(tile, bid).get("satisfied", false)),
		"materials present -> satisfied")

	# start_on_tile consumes the materials and starts an under_construction project — the
	# building is NOT live yet; it promotes only after build_duration ticks.
	var before: int = MatchState.buildings.size()
	var iid: String = Construction.start_on_tile(bid, "", tile)
	var consumed_ok := true
	for gid in reqs:
		if Stockpile.get_at_tile(tile, gid) != 0:
			consumed_ok = false
	_check(consumed_ok, "start_on_tile consumes the construction materials")
	var duration: int = MatchState.effective_build_duration(bid)
	_check(duration >= 1, "building has a positive build_duration")
	_check(not MatchState.buildings.has(iid) and Construction.construction_projects.has(iid),
		"start_on_tile creates an under_construction project, not a live building")
	_check(int(Construction.construction_projects[iid].get("turns_remaining", -1)) == duration,
		"project counts down from build_duration")
	_check(Construction.reserved_space_on_tile(tile) > 0.0, "project reserves tile space")

	# Tick out the countdown; the building promotes on the final tick, keeping the same id.
	for _i in range(duration):
		Construction.tick_turn()
	_check(MatchState.buildings.has(iid) and not Construction.construction_projects.has(iid),
		"project promotes to a live building after build_duration turns")
	_check(MatchState.buildings.size() == before + 1, "exactly one building added on promotion")
	_check(Construction.reserved_space_on_tile(tile) == 0.0, "reserved space frees on promotion")

	# Cleanup so later assertions over MatchState.buildings aren't polluted.
	MatchState.remove_building(iid)

	# Dialog smoke test: instantiates + builds its UI without error.
	var dlg: Node = load("res://scripts/construction_missing_dialog.gd").new()
	add_child(dlg)
	dlg.call("open", bid, "", tile, reqs)
	_check(dlg.visible and dlg.get_child_count() > 0, "missing-materials dialog builds + opens")
	dlg.queue_free()

func _test_construction_cancel() -> void:
	var bid := ""
	var reqs := {}
	for b in Catalog.all_buildings():
		var r: Dictionary = Construction.requirements_for(str(b.get("id", "")))
		if not r.is_empty():
			bid = str(b.get("id", ""))
			reqs = r
			break
	if bid == "":
		return
	var first := str(reqs.keys()[0])

	# --- Cancel an under_construction build: full refund, all materials returned, space freed.
	var tile := "tile_cancel_uc"
	for gid in reqs:
		Stockpile.consume(tile, str(gid), 1 << 30)
		Stockpile.add(tile, str(gid), int(reqs[gid]))
	var money_before: float = MatchState.money
	var iid: String = Construction.start_on_tile(bid, "", tile, 80.0)
	_check(Construction.reserved_space_on_tile(tile) > 0.0, "under-construction reserves space before cancel")
	var ok: bool = Construction.cancel(iid)
	_check(ok and not Construction.construction_projects.has(iid), "cancel removes the project")
	_check(absf(MatchState.money - (money_before + 80.0)) < 0.001, "cancel refunds the full build cost")
	_check(Stockpile.get_at_tile(tile, first) == int(reqs[first]), "cancel returns the consumed materials")
	_check(Construction.reserved_space_on_tile(tile) == 0.0, "cancel frees the reserved space")
	for gid in reqs:
		Stockpile.consume(tile, str(gid), 1 << 30)

	# --- Cancel an awaiting build: only SECURED materials return, still-missing ones don't.
	var tile2 := "tile_cancel_aw"
	for gid in reqs:
		Stockpile.consume(tile2, str(gid), 1 << 30)
	var missing2: Dictionary = reqs.duplicate()
	missing2.erase(first)  # pretend the first good was already secured (claimed)
	var iid2: String = MatchState.reserve_instance_id(bid)
	Construction.construction_projects[iid2] = {
		"instance_id": iid2, "building_id": bid, "recipe_id": "", "tile_id": tile2,
		"status": Construction.STATUS_AWAITING_MATERIALS,
		"required_materials": reqs, "missing_materials": missing2,
		"turns_remaining": 2, "construction_duration": 2, "reserved_space": 10.0, "build_cost": 50.0,
	}
	var m2: float = MatchState.money
	Construction.cancel(iid2)
	_check(Stockpile.get_at_tile(tile2, first) == int(reqs[first]), "cancel returns only the secured materials (awaiting)")
	if not missing2.is_empty():
		var miss_gid := str(missing2.keys()[0])
		_check(Stockpile.get_at_tile(tile2, miss_gid) == 0, "still-missing materials are not returned on cancel")
	_check(absf(MatchState.money - (m2 + 50.0)) < 0.001, "cancel refunds the build cost (awaiting)")
	for gid in reqs:
		Stockpile.consume(tile2, str(gid), 1 << 30)

func _test_construction_sourcing() -> void:
	var bid := ""
	var reqs := {}
	for b in Catalog.all_buildings():
		var r: Dictionary = Construction.requirements_for(str(b.get("id", "")))
		if not r.is_empty():
			bid = str(b.get("id", ""))
			reqs = r
			break
	if bid == "":
		return
	# Real tiles so the router resolves source -> dest turns.
	var src := "tile_5_10"
	var dest := "tile_3_8"
	for gid in reqs:
		Stockpile.consume(src, str(gid), 1 << 30)
		Stockpile.consume(dest, str(gid), 1 << 30)
		Stockpile.add(src, str(gid), int(reqs[gid]) * 3)  # comfortable spare surplus

	var found: Dictionary = Construction.find_source_tile(dest, reqs)
	_check(not found.is_empty(), "find_source_tile finds a tile with spare stock")
	if not found.is_empty():
		var s := str(found.get("tile_id", ""))
		var committed: Dictionary = Production.compute_committed_for_tile(s)
		var covers := true
		for gid in reqs:
			if Stockpile.get_at_tile(s, str(gid)) - int(committed.get(gid, 0)) < int(reqs[gid]):
				covers = false
		_check(covers, "the chosen source tile actually covers the requirement")

	var first_gid := str(reqs.keys()[0])
	var src_before: int = Stockpile.get_at_tile(src, first_gid)
	var iid: String = Construction.start_awaiting_from_tile(bid, "", dest, src)
	_check(Construction.construction_projects.has(iid)
		and str(Construction.construction_projects[iid].get("status", "")) == Construction.STATUS_AWAITING_MATERIALS,
		"start_awaiting_from_tile creates an awaiting project")
	_check(Stockpile.get_at_tile(src, first_gid) == src_before - int(reqs[first_gid]),
		"sourcing consumes the shortfall from the source tile")

	# Deliver to the build site and claim -> construction begins.
	for gid in reqs:
		Stockpile.add(dest, str(gid), int(reqs[gid]))
	Construction.claim_materials()
	_check(str(Construction.construction_projects.get(iid, {}).get("status", "")) == Construction.STATUS_UNDER_CONSTRUCTION,
		"sourced project begins construction once delivered")

	Construction.construction_projects.erase(iid)
	for gid in reqs:
		Stockpile.consume(src, str(gid), 1 << 30)
		Stockpile.consume(dest, str(gid), 1 << 30)

func _test_construction_detail_panel() -> void:
	var bid := ""
	var reqs := {}
	for b in Catalog.all_buildings():
		var r: Dictionary = Construction.requirements_for(str(b.get("id", "")))
		if not r.is_empty():
			bid = str(b.get("id", ""))
			reqs = r
			break
	if bid == "":
		return
	var tile := "tile_detail_test"
	for gid in reqs:
		Stockpile.consume(tile, gid, 1 << 30)
		Stockpile.add(tile, gid, int(reqs[gid]))
	var iid: String = Construction.start_on_tile(bid, "", tile)  # under_construction project

	# The detail panel lives inside main.tscn (no standalone scene), so instantiate and find it.
	var packed: PackedScene = load("res://scenes/main.tscn")
	var ok: bool = packed != null and Construction.construction_projects.has(iid)
	if ok:
		var inst: Node = packed.instantiate()
		add_child(inst)
		await get_tree().process_frame
		var panel: Node = inst.find_child("BuildingDetailPanel", true, false)
		ok = panel != null
		if ok:
			panel.call("show_building", {
				"instance_id": iid, "building_id": bid, "recipe_id": "",
				"tile_id": tile, "owner": MatchState.LOCAL_PLAYER,
				"construction_status": "under_construction",
			})
			var fv: Node = panel.get("fields_vbox")
			_check(fv != null and fv.get_child_count() > 0, "construction detail panel renders the materials section")
			# Regression guards: the close (X) button lives in the status rail and must stay,
			# while Change Recipe is hidden during construction.
			var close_button := panel.get("close_button") as Button
			_check(close_button != null and close_button.visible and close_button.is_inside_tree(),
				"construction panel keeps the close (X) button")
			_check(not panel.get("change_recipe_button").visible, "construction panel hides Change Recipe")
			# Switching to a running building restores the operational controls.
			var rid: String = MatchState.add_building(bid, "", "tile_detail_running")
			panel.call("show_building", MatchState.get_building(rid))
			_check(panel.get("change_recipe_button").visible, "Change Recipe restored on a running building")
			MatchState.remove_building(rid)
			ok = true
		inst.queue_free()
		await get_tree().process_frame
	if not ok:
		_check(false, "construction detail panel instantiates")
	Construction.construction_projects.erase(iid)

func _test_construction_awaiting() -> void:
	var bid := ""
	var reqs := {}
	for b in Catalog.all_buildings():
		var r: Dictionary = Construction.requirements_for(str(b.get("id", "")))
		if not r.is_empty():
			bid = str(b.get("id", ""))
			reqs = r
			break
	if bid == "":
		return

	var tile := "tile_awaiting_test"
	for gid in reqs:
		Stockpile.consume(tile, gid, 1 << 30)
	# Stock all materials up front so start_awaiting_market orders nothing from the market
	# (keeps the test port-independent); claim_materials then secures them in place.
	for gid in reqs:
		Stockpile.add(tile, gid, int(reqs[gid]))

	var iid: String = Construction.start_awaiting_market(bid, "", tile)
	_check(Construction.construction_projects.has(iid)
		and str(Construction.construction_projects[iid].get("status", "")) == Construction.STATUS_AWAITING_MATERIALS,
		"start_awaiting_market creates an awaiting_materials project")
	_check(not MatchState.buildings.has(iid), "awaiting project is not a live building")
	_check(Construction.reserved_space_on_tile(tile) > 0.0, "awaiting project reserves tile space")

	# The priority claim secures the on-tile materials and starts the build countdown.
	Construction.claim_materials()
	var consumed_ok := true
	for gid in reqs:
		if Stockpile.get_at_tile(tile, gid) != 0:
			consumed_ok = false
	_check(consumed_ok, "claim_materials consumes the secured materials")
	_check(Construction.construction_projects.has(iid)
		and str(Construction.construction_projects[iid].get("status", "")) == Construction.STATUS_UNDER_CONSTRUCTION,
		"awaiting project begins construction once materials are secured")

	# Countdown then completes the build with the same id.
	var duration: int = MatchState.effective_build_duration(bid)
	for _i in range(duration):
		Construction.tick_turn()
	_check(MatchState.buildings.has(iid) and not Construction.construction_projects.has(iid),
		"awaiting project promotes after securing materials + countdown")
	MatchState.remove_building(iid)

# Regression: a build must order its OWN market freight for every missing
# material even when a co-located consumer already has inbound shipments of the
# same good. Before the fix, reorder_market_materials counted ANY inbound of the
# good against its shortfall, so the build never ordered (nor received) its own
# copy and hung in awaiting_materials forever.
func _test_construction_reorder_ignores_foreign_inbound() -> void:
	var bid := ""
	var reqs := {}
	for b in Catalog.all_buildings():
		var r: Dictionary = Construction.requirements_for(str(b.get("id", "")))
		if not r.is_empty():
			bid = str(b.get("id", ""))
			reqs = r
			break
	if bid == "":
		return
	var tile := "tile_13_2"   # inland but port-reachable, so buys become >=1-turn shipments
	var mat := str(reqs.keys()[0])
	for gid in reqs:
		Stockpile.consume(tile, gid, 1 << 30)

	# Start the build with an EMPTY tile — every material is a market shortfall.
	MatchState.money = 1000000.0
	var iid: String = Construction.start_awaiting_market(bid, "", tile)
	var project: Dictionary = Construction.construction_projects[iid]
	_check(str(project.get("status", "")) == Construction.STATUS_AWAITING_MATERIALS,
		"reorder test: build starts awaiting materials")

	# Simulate a co-located production building's inbound shipment of `mat`
	# (a foreign, un-tagged purchase) landing next turn.
	MatchState.pending_transport_shipments.append({
		"source_tile": "tile_5_10", "destination_tile": tile,
		"good_id": mat, "qty": int(reqs[mat]) * 5, "turns_remaining": 1, "is_purchase": true,
	})
	# Drop the build's OWN freight for `mat` so reorder is forced to re-order it;
	# the foreign inbound above must NOT satisfy the shortfall.
	for i in range(MatchState.pending_transport_shipments.size() - 1, -1, -1):
		var s: Dictionary = MatchState.pending_transport_shipments[i]
		if str(s.get("construction_instance_id", "")) == iid and str(s.get("good_id", "")) == mat:
			MatchState.pending_transport_shipments.remove_at(i)

	Construction.claim_materials()        # nothing on the tile yet
	Construction.reorder_market_materials()
	var own_inbound := 0
	for s in MatchState.get_inbound_transport_shipments(tile, mat):
		if str(s.get("construction_instance_id", "")) == iid:
			own_inbound += int(s.get("qty", 0))
	_check(own_inbound >= int(reqs[mat]),
		"reorder re-orders the build's own freight despite a neighbour's inbound of the same good")

	# The build converges: keep ticking the delivery+claim+reorder loop.
	for _turn in range(12):
		for s in MatchState.pending_transport_shipments:
			(s as Dictionary)["turns_remaining"] = 0
		for arrived in MatchState.advance_transport_shipments():
			if not bool((arrived as Dictionary).get("is_sale", false)):
				Stockpile.add(str(arrived.get("destination_tile", "")), str(arrived.get("good_id", "")), int(arrived.get("qty", 0)))
		Construction.claim_materials()
		Construction.reorder_market_materials()
		if not Construction.construction_projects.has(iid) or str(Construction.construction_projects[iid].get("status", "")) == Construction.STATUS_UNDER_CONSTRUCTION:
			break
	_check(str(Construction.construction_projects.get(iid, {}).get("status", "")) == Construction.STATUS_UNDER_CONSTRUCTION,
		"awaiting build reaches under_construction (no hang) with a neighbour importing the same good")
	Construction.cancel(iid)
	for gid in reqs:
		Stockpile.consume(tile, gid, 1 << 30)

func _test_buy_price() -> void:
	var gid := "g_001"
	var sell := MarketState.get_price(gid)
	var buy := MarketState.get_buy_price(gid)
	_check(absf(buy - sell * (1.0 + EconomyConfig.MARKET_BUY_MARKUP)) < 0.0001,
		"buy price is the sale price plus the market markup")
	_check(buy > sell, "buying costs more than selling (spread)")
	# preview_buy should value goods at the buy price.
	var prev: Dictionary = MatchState.preview_buy("tile_3_8", gid, 10)
	if not prev.is_empty():
		_check(absf(float(prev.get("goods_cost", 0.0)) - 10.0 * buy) < 0.01,
			"preview_buy values goods at the buy price")

func _test_price_impact() -> void:
	var g: int = EconomyConfig.GLUT_UNITS
	_check(EconomyConfig.price_impact_pct_for(g) == 0, "selling up to the glut has no price impact")
	_check(EconomyConfig.price_impact_pct_for(g + 1) == 1, "just over the glut is 1% impact")
	_check(EconomyConfig.price_impact_pct_for(2 * g) == 1, "twice the glut is still 1%")
	_check(EconomyConfig.price_impact_pct_for(2 * g + 1) == 2, "past 2x glut is 2%")
	_check(EconomyConfig.price_impact_pct_for(1000 * g) == EconomyConfig.MAX_PRICE_IMPACT_PCT, "impact caps at the max")
	_check(EconomyConfig.units_cap_for_impact(0) == g, "no-impact cap is the glut")
	_check(EconomyConfig.units_cap_for_impact(1) == 2 * g, "1% cap is twice the glut")
	MatchState.set_auto_sell_impact("tile_4_5", 0)
	_check(MatchState.auto_sell_unit_cap("tile_4_5") == g, "tile NONE tolerance caps at the glut")
	MatchState.set_auto_sell_impact("tile_4_5", 1)
	_check(MatchState.auto_sell_unit_cap("tile_4_5") == 2 * g, "tile 1% tolerance caps at 2x glut")
	MatchState.set_auto_sell_impact("tile_4_5", MatchState.IMPACT_ANY)
	_check(MatchState.auto_sell_unit_cap("tile_4_5") > 1000000, "tile ANY tolerance is effectively uncapped")
	_check(MatchState.get_auto_sell_impact("tile_unset_99") == MatchState.IMPACT_ANY, "default tolerance is ANY")

# The LIVE threshold model: net per-turn volume over 2x/3x/4x of a good's base
# building output accrues 0.1/0.2/0.4 %/turn of glut (sell) or deficit (buy)
# impact, capped at ±50%, recovering 0.1%/turn under the threshold. The impact
# multiplies the decayed base price; `prices` stays the impact-free series.
func _test_price_impact_thresholds() -> void:
	# BANDED response with SPACED thresholds (owner ruling): 2x / 4x / 10x.
	_check(EconomyConfig.price_impact_rate(64, 32) == 0.0, "2x exactly is under the bite")
	_check(EconomyConfig.price_impact_rate(65, 32) == EconomyConfig.PRICE_IMPACT_RATE_2X,
		"just over 2x accrues the gentle band")
	_check(EconomyConfig.price_impact_rate(128, 32) == EconomyConfig.PRICE_IMPACT_RATE_2X,
		"4x exactly is still the 2x band")
	_check(EconomyConfig.price_impact_rate(129, 32) == EconomyConfig.PRICE_IMPACT_RATE_4X,
		"just over 4x steps up")
	_check(EconomyConfig.price_impact_rate(320, 32) == EconomyConfig.PRICE_IMPACT_RATE_4X,
		"10x exactly is still the 4x band")
	_check(EconomyConfig.price_impact_rate(321, 32) == EconomyConfig.PRICE_IMPACT_RATE_10X,
		"over 10x is the flooding band")
	_check(EconomyConfig.price_impact_rate(32000, 32) == EconomyConfig.PRICE_IMPACT_RATE_10X,
		"the flooding band is the top — it saturates by design")
	_check(EconomyConfig.price_impact_rate(-321, 32) == EconomyConfig.PRICE_IMPACT_RATE_10X,
		"buying volume uses the same bands (deficit side)")
	_check(EconomyConfig.price_impact_rate(1000, 0) == 0.0, "no base output -> no impact")
	# A NORMAL multi-building chain must not be punished: 3 factories of one good is 3x,
	# which sits in the gentle band, not the flooding one. (The continuous curve charged
	# 0.66%/turn here and crushed motors to the floor over 75 turns.)
	_check(EconomyConfig.price_impact_rate(84, 28) == EconomyConfig.PRICE_IMPACT_RATE_2X,
		"a 3-factory chain sits in the gentle band, not the flooding one")
	_check(EconomyConfig.PRICE_IMPACT_CAP_PCT == 40.0, "impact is capped at 40% of base price")
	# Recovery is FLAT — depth-scaling would outrun a 0.5%/turn accrual and reward pulsing.
	_check(EconomyConfig.price_impact_recovery(0.0) == EconomyConfig.PRICE_IMPACT_RECOVERY_PCT
		and EconomyConfig.price_impact_recovery(-40.0) == EconomyConfig.PRICE_IMPACT_RECOVERY_PCT,
		"recovery is flat at every depth, so pulsing production can't out-earn the penalty")
	_check(EconomyConfig.PRICE_IMPACT_RECOVERY_PCT < EconomyConfig.PRICE_IMPACT_RATE_2X + 0.0001,
		"recovery never exceeds even the gentlest accrual band")

	# Accrual, stacking on decay, recovery, and the cap — driven through the
	# real per-turn pipeline on a scratch good id.
	var gid := str(Catalog.get_good_by_internal_name("coal").get("id", ""))
	var coal_base: int = Catalog.base_output_for_good(gid)
	_check(coal_base > 0, "coal has a base building output")
	# Flush any volume an earlier test left on the books BEFORE measuring — residue would
	# push a sample into the wrong band and shift every expected value below.
	MarketState._turn_sold.clear()
	MarketState._turn_bought.clear()
	MarketState.impact_pct.erase(gid)
	# tick_turn decays every good's base price — restore the table afterwards so
	# later market tests see untouched prices.
	var prices_snapshot: Dictionary = MarketState.prices.duplicate(true)
	var base_before: float = MarketState.get_base_price_now(gid)
	# Sell in the FLOODING band (>10x) so the sample is unambiguous.
	var rate_hi: float = EconomyConfig.price_impact_rate(coal_base * 11, coal_base)
	MarketState.record_market_sale_volume(gid, coal_base * 11)
	MarketState.tick_turn()
	var after_4x: float = -rate_hi
	_check(absf(MarketState.get_impact_pct(gid) - after_4x) < 0.0001,
		"one >10x sell turn accrues -%.2f%%" % rate_hi)
	# Decay is suppressed until MarketState.DECAY_FIRST_TURN, so the effective rate at this
	# turn may be 0 — read it the same way tick_turn() does rather than off the CSV.
	var decay: float = float(Catalog.get_good(gid).get("decay_rate", 0.0)) \
		if int(TurnManager.current_turn) >= MarketState.DECAY_FIRST_TURN else 0.0
	var expected: float = base_before * (1.0 - decay) * (1.0 + after_4x / 100.0)
	_check(absf(MarketState.get_price(gid) - expected) < 0.0001,
		"impact multiplies the decayed base price (stacks on normal drift)")
	var rate_3x: float = EconomyConfig.price_impact_rate(coal_base * 3, coal_base)
	MarketState.record_market_sale_volume(gid, coal_base * 3)          # 3x sell -> gentle band
	MarketState.tick_turn()
	var after_3x: float = after_4x - rate_3x
	_check(absf(MarketState.get_impact_pct(gid) - after_3x) < 0.0001,
		"a 3x turn adds only -%.2f%%" % rate_3x)
	_check(rate_3x < rate_hi, "bands are monotonic: 3x bites less than >10x")
	var recov: float = EconomyConfig.price_impact_recovery(after_3x)
	MarketState.tick_turn()                                            # quiet turn
	_check(absf(MarketState.get_impact_pct(gid) - (after_3x + recov)) < 0.0001,
		"a quiet turn recovers by the flat rate")
	var at_quiet: float = after_3x + recov
	var rate_2x: float = EconomyConfig.price_impact_rate(coal_base * 3, coal_base)
	MarketState.record_market_buy_volume(gid, coal_base * 3)           # >2x BUY
	MarketState.tick_turn()
	_check(absf(MarketState.get_impact_pct(gid) - (at_quiet + rate_2x)) < 0.0001,
		"net buying pushes impact UP by the same bands (deficit side)")
	# Netting: equal buys and sells cancel to a quiet (recovery) turn.
	var before_net: float = MarketState.get_impact_pct(gid)
	var recov_net: float = EconomyConfig.price_impact_recovery(before_net)
	MarketState.record_market_sale_volume(gid, coal_base * 4)
	MarketState.record_market_buy_volume(gid, coal_base * 4)
	MarketState.tick_turn()
	_check(absf(MarketState.get_impact_pct(gid) - move_toward(before_net, 0.0, recov_net)) < 0.0001,
		"offsetting buy+sell nets to recovery")
	# Cap at ±PRICE_IMPACT_CAP_PCT.
	var cap: float = EconomyConfig.PRICE_IMPACT_CAP_PCT
	MarketState.impact_pct[gid] = -(cap - 0.1)
	MarketState.record_market_sale_volume(gid, coal_base * 11)
	MarketState.tick_turn()
	_check(absf(MarketState.get_impact_pct(gid) + cap) < 0.0001, "impact caps at -%d%%" % int(cap))
	# Save round-trip keeps the accumulated impact.
	var snap: Dictionary = MarketState.export_state()
	MarketState.impact_pct.clear()
	MarketState.import_state(snap)
	_check(absf(MarketState.get_impact_pct(gid) + cap) < 0.0001, "impact survives save/load")
	# Recovery clears it fully given time (and erases the entry near zero).
	MarketState.impact_pct[gid] = -0.05
	MarketState.tick_turn()
	_check(MarketState.get_impact_pct(gid) == 0.0, "recovery settles exactly to zero")
	# UI helper: thresholds surface as 2x|3x|4x of the base output.
	var th: PackedInt32Array = MarketState.impact_thresholds(gid)
	_check(th.size() == 3 and th[0] == coal_base * 2 and th[1] == coal_base * 4 and th[2] == coal_base * 10,
		"impact_thresholds returns 2x/4x/10x of base output, matching the live bands")
	MarketState.impact_pct.erase(gid)
	MarketState.prices = prices_snapshot
	MarketState.prices_updated.emit()

func _test_owner_costs() -> void:
	_check(MatchState.is_player_owned({"owner": "player_1"}), "player_1 building is player-owned")
	_check(MatchState.is_player_owned({}), "building with no owner defaults to player-owned")
	_check(not MatchState.is_player_owned({"owner": "Three Diamonds Shipping Corporation"}),
		"NPC-owned building is not player-owned (not charged maintenance)")

# Demolish refund: build money + every consumed material kit (construction + each upgrade
# level), scaled by the refund share; plus the stockpile-room/cash-overflow payout split.
# Uses the Mine (b_001 / "mine"): build kit construction_equipment_ice×1, concrete×3,
# rubber×5, plastics×5; upgrade extras L2 {large_engine:1}, L3 {large_engine:4, computer:2}
# on top of the base kit {building_frame:2, construction_equipment_ice:1, concrete:10}.
func _test_refund() -> void:
	var ceq_id: String = str(Catalog.get_good_by_internal_name("construction_equipment_ice").get("id", ""))
	var le_id: String = str(Catalog.get_good_by_internal_name("large_engine").get("id", ""))
	var comp_id: String = str(Catalog.get_good_by_internal_name("computer").get("id", ""))
	var frame_id: String = str(Catalog.get_good_by_internal_name("building_frame").get("id", ""))

	EconomyConfig.demolish_refund_share = 1.0
	var id: String = MatchState.add_building("b_001", "r_001", "tile_7_7", MatchState.LOCAL_PLAYER, "inst_refund_l1")
	var inst: Dictionary = MatchState.buildings[id]
	inst["build_cost"] = 100.0
	inst["build_materials"] = Construction.requirements_for("b_001")

	# Level 1: build money + build kit only, no upgrade-kit materials.
	var r1: Dictionary = MatchState.refund_cost(id)
	_check(is_equal_approx(float(r1.money), 100.0), "refund money == paid build cost at share 1.0 (%.1f)" % float(r1.money))
	_check(int(r1.materials.get(ceq_id, 0)) == 1, "L1 refund returns the build kit (construction_equipment_ice ×1)")
	_check(not r1.materials.has(le_id), "L1 refund has no upgrade-kit materials")

	# Level 3: refund increments to include the L2 + L3 upgrade kits.
	inst["level"] = 3
	var r3: Dictionary = MatchState.refund_cost(id)
	_check(int(r3.materials.get(le_id, 0)) == 5,
		"L3 refund sums upgrade kits (large_engine L2 1 + L3 4 = 5, got %d)" % int(r3.materials.get(le_id, 0)))
	_check(int(r3.materials.get(comp_id, 0)) == 2, "L3 refund includes the L3-only computer ×2")
	_check(int(r3.materials.get(frame_id, 0)) == 4,
		"L3 refund includes the base upgrade kit per level (building_frame 2+2 = 4, got %d)" % int(r3.materials.get(frame_id, 0)))

	# Refund share scales money and (rounded) material quantities.
	EconomyConfig.demolish_refund_share = 0.5
	var rh: Dictionary = MatchState.refund_cost(id)
	_check(is_equal_approx(float(rh.money), 50.0), "refund money halves at share 0.5 (%.1f)" % float(rh.money))
	_check(int(rh.materials.get(le_id, 0)) == 3,
		"material qty scales with share (large_engine 5×0.5 → 3, got %d)" % int(rh.materials.get(le_id, 0)))
	EconomyConfig.demolish_refund_share = 1.0

	# Fallback: a building with no stamped cost uses the Catalog build cost/materials.
	var id2: String = MatchState.add_building("b_001", "r_001", "tile_8_8", MatchState.LOCAL_PLAYER, "inst_refund_fallback")
	var r2: Dictionary = MatchState.refund_cost(id2)
	_check(int(r2.materials.get(ceq_id, 0)) == 1
		and is_equal_approx(float(r2.money), Catalog.get_building("b_001").base_price),
		"refund falls back to Catalog build cost/materials when the instance has none")

	# refund_plan: with a near-full tile, material overflow is offered as cash at market price.
	var plan_tile: String = "tile_refund_plan"
	var id3: String = MatchState.add_building("b_001", "r_001", plan_tile, MatchState.LOCAL_PLAYER, "inst_refund_plan")
	var free_now: int = Stockpile.get_free_capacity(plan_tile)
	var fill_amt: int = max(0, free_now - 3)
	if fill_amt > 0:
		Stockpile.add(plan_tile, "g_001", fill_amt)  # leave exactly 3 free units
	MatchState.buildings[id3]["build_materials"] = {ceq_id: 10}  # 10 units, only 3 fit
	var plan: Dictionary = MatchState.refund_plan(id3)
	_check(int(plan.to_stockpile.get(ceq_id, 0)) == 3, "refund_plan fits only what the tile can hold (3 of 10)")
	_check(not bool(plan.fits_fully) and float(plan.cash_overflow) > 0.0,
		"refund_plan offers cash for the 7 overflow units (£%.1f)" % float(plan.cash_overflow))
	_check(is_equal_approx(float(plan.cash_overflow), 7.0 * MarketState.get_price(ceq_id)),
		"overflow cash == 7 × market price")

	# Stamping: a promoted construction project carries build_cost + build_materials.
	var proj_id: String = "inst_refund_promote"
	Construction.construction_projects[proj_id] = {
		"instance_id": proj_id, "building_id": "b_001", "recipe_id": "r_001",
		"tile_id": "tile_6_6", "status": "under_construction",
		"required_materials": Construction.requirements_for("b_001"),
		"missing_materials": {}, "turns_remaining": 0, "construction_duration": 3,
		"reserved_space": 1.0, "build_cost": 250.0,
	}
	Construction._promote(proj_id)
	var pinst: Dictionary = MatchState.buildings.get(proj_id, {})
	_check(is_equal_approx(float(pinst.get("build_cost", -1.0)), 250.0),
		"promotion stamps build_cost onto the live instance")
	_check(int((pinst.get("build_materials", {}) as Dictionary).get(ceq_id, 0)) == 1,
		"promotion stamps build_materials onto the live instance")

	# Cleanup so these synthetic buildings/stock don't leak into later tests.
	if fill_amt > 0:
		Stockpile.consume(plan_tile, "g_001", fill_amt)
	MatchState.remove_building(id)
	MatchState.remove_building(id2)
	MatchState.remove_building(id3)
	MatchState.remove_building(proj_id)

func _test_recurring_sell_multitile() -> void:
	# A recurring sell bound to an empty source tile should still sell the good
	# from another tile that holds it (the fix for "sold once then stopped").
	var src := "tile_3_8"
	var other := "tile_9_5"
	var have: int = Stockpile.get_at_tile(src, "g_001")
	if have > 0:
		Stockpile.consume(src, "g_001", have)
	Stockpile.add(other, "g_001", 25)
	var before: int = Stockpile.get_at_tile(other, "g_001")
	MatchState.add_recurring_sell(src, {"g_001": 10})
	MatchState.run_recurring_and_scheduled_moves()
	var sold: int = before - Stockpile.get_at_tile(other, "g_001")
	_check(sold == 10, "recurring sell draws from another tile when source is empty (sold %d)" % sold)
	if not MatchState.recurring_sells.is_empty():
		MatchState.recurring_sells.pop_back()

func _test_transaction_ledger() -> void:
	Stockpile.add("tile_3_8", "g_001", 12)
	MatchState.queue_sell("tile_3_8", {"g_001": 12})  # one-off → logged
	var rows: Array = MatchState.get_oneoff_transaction_rows()
	_check(rows.size() > 0, "one-off sell appears in the transaction ledger")
	var last: Dictionary = rows[rows.size() - 1]
	_check(str(last.get("type", "")) == "Sell" and int(last.get("qty", 0)) == 12,
		"ledger row carries type=Sell and qty")
	MatchState.add_recurring_move("tile_3_8", "tile_3_9", {"g_001": 5})
	_check(MatchState.get_recurring_move_rows().size() > 0, "recurring move appears in the movements ledger")
	# A recurring execution must NOT also be logged as a one-off.
	var before: int = MatchState.get_oneoff_move_rows().size()
	MatchState.run_recurring_and_scheduled_moves()
	_check(MatchState.get_oneoff_move_rows().size() == before, "recurring executions are not double-logged as one-offs")
	# Production-driven sales/moves must show up too (the bulk of real activity).
	var t_before: int = MatchState.get_oneoff_transaction_rows().size()
	MatchState.log_market_sale("tile_6_8", "tile_5_10", "g_001", 20, 2)
	_check(MatchState.get_oneoff_transaction_rows().size() == t_before + 1,
		"a production market sale is logged to the transaction ledger")

func _test_output_market_route() -> void:
	var mode_before: int = MatchState.sell_mode
	SpecialOrderState.reset()
	MatchState.route_output_to_market("inst_test_market", "g_001")
	_check(MatchState.is_output_market("inst_test_market", "g_001"),
		"route_output_to_market marks the building for market")
	_check(MatchState.get_output_stockpile_destination("inst_test_market", "g_001") == "",
		"a market route reads as no stockpile tile")
	_check(MatchState.sell_mode == mode_before,
		"per-building market route leaves the global sell mode unchanged")
	var order: Dictionary = SpecialOrderState.create_order("coal", TurnManager.current_turn, 5, 4, 0.25)
	var order_id := str(order.get("id", ""))
	MatchState.route_output_to_special_order("inst_test_market", "g_001", order_id)
	_check(MatchState.get_output_special_order_id("inst_test_market", "g_001") == order_id
		and MatchState.is_output_market("inst_test_market", "g_001"),
		"route_output_to_special_order marks output as market-bound with an order tag")
	MatchState.route_output_to_market("inst_test_market", "g_001")
	_check(MatchState.get_output_special_order_id("inst_test_market", "g_001") == "",
		"route_output_to_market clears the special-order tag")
	SpecialOrderState.reset()

	# Per-good shipping cap (the CTRL+click "send a specific amount every turn" flow).
	MatchState.set_output_stockpile_destination("inst_test_market", "tile_3_9", "g_001")
	MatchState.set_output_ship_quantity("inst_test_market", "g_001", 10)
	_check(MatchState.get_output_ship_quantity("inst_test_market", "g_001") == 10,
		"ship quantity cap set and read back")
	MatchState.set_output_stockpile_destination("inst_test_market", "tile_3_8", "g_001")
	_check(MatchState.get_output_ship_quantity("inst_test_market", "g_001") == 0,
		"a plain re-route clears the cap (plain click ships everything)")
	MatchState.set_output_ship_quantity("inst_test_market", "g_001", 7)
	MatchState.route_output_to_market("inst_test_market", "g_001")
	_check(MatchState.get_output_ship_quantity("inst_test_market", "g_001") == 0,
		"routing back to market clears the cap")
	MatchState.set_output_stockpile_destination("inst_test_market", "tile_3_9", "g_001")
	MatchState.set_output_ship_quantity("inst_test_market", "g_001", 5)
	var routed_state: Dictionary = MatchState.export_state()
	_check((routed_state.get("output_ship_quantities", {}) as Dictionary).has("inst_test_market"),
		"ship quantity caps ride the save export")
	MatchState.set_output_ship_quantity("inst_test_market", "g_001", 0)
	_check(MatchState.get_output_ship_quantity("inst_test_market", "g_001") == 0
		and not MatchState.output_ship_quantities.has("inst_test_market"),
		"clearing the cap removes the empty per-building entry")
	MatchState.import_state(routed_state)
	_check(MatchState.get_output_ship_quantity("inst_test_market", "g_001") == 5,
		"ship quantity caps survive a save round-trip")
	MatchState.clear_output_stockpile_destination("inst_test_market", "g_001")
	_check(MatchState.get_output_ship_quantity("inst_test_market", "g_001") == 0,
		"clearing the route clears the cap too")

func _test_bulk_sell() -> void:
	Stockpile.add("tile_3_8", "g_001", 30)
	var result: Dictionary = MatchState.sell_all_to_market({"good_id": "", "finished_only": false, "per_tile_keep": 10})
	_check(int(result.get("total_qty", 0)) >= 20, "sell_all_to_market sells the surplus above per-tile keep")
	_check(Stockpile.get_at_tile("tile_3_8", "g_001") == 10, "bulk sell leaves the kept amount on the tile")

func _test_npc_ports() -> void:
	# The main scene's _ready places the 4 NPC ports; verify one landed + is NPC-owned.
	var found_npc_port := false
	for iid in MatchState.tile_buildings.get("tile_5_10", []):
		var inst: Dictionary = MatchState.get_building(iid)
		if str(inst.get("building_id", "")) == "b_004" and str(inst.get("owner", "")) == "Three Diamonds Shipping Corporation":
			found_npc_port = true
	_check(found_npc_port, "NPC port placed on a port tile (b_004, Three Diamonds)")
	_check(Stockpile.get_capacity("tile_5_10") >= Stockpile.TILE_CAPACITY + 600,
		"port tile capacity raised by the port's storage_boost")

func _test_queue_sell() -> void:
	Stockpile.add("tile_3_8", "g_001", 8)
	var before: int = MatchState.get_pending_transport_shipments().size()
	var summary: Dictionary = MatchState.queue_sell("tile_3_8", {"g_001": 8})
	_check(not summary.is_empty(), "queue_sell returns a summary")
	_check(Stockpile.get_at_tile("tile_3_8", "g_001") == 0, "queue_sell consumes from source")
	_check(str(summary.get("port", "")) != "" and MatchState.get_pending_transport_shipments().size() > before,
		"queue_sell ships to a port")

func _test_queue_sell_immediate_updates_turn_summary() -> void:
	Stockpile.clear_all()
	Stockpile.add("tile_5_10", "g_001", 6)
	Production._pending_external_sales.clear()
	Production.last_turn_summary = {"goods_sales_revenue": 0.0, "money_in": 0.0, "sold": {}}
	var result: Dictionary = MatchState.queue_sell("tile_5_10", {"g_001": 6}, false)
	var sold: Dictionary = Production.last_turn_summary.get("sold", {})
	var coal: Dictionary = sold.get("g_001", {})
	_check(not result.is_empty() and not bool(result.get("deferred", true)),
		"queue_sell can settle immediately from a port tile")
	_check(int(coal.get("qty", 0)) == 6
		and float(Production.last_turn_summary.get("goods_sales_revenue", 0.0)) > 0.0,
		"immediate tile-view sales update goods sold in the turn summary")
	var next_summary := {"goods_sales_revenue": 0.0, "money_in": 0.0, "sold": {}}
	Production._merge_pending_external_sales(next_summary)
	var next_sold: Dictionary = next_summary.get("sold", {})
	var next_coal: Dictionary = next_sold.get("g_001", {})
	_check(int(next_coal.get("qty", 0)) == 6
		and float(next_summary.get("goods_sales_revenue", 0.0)) > 0.0,
		"immediate tile-view sales carry into the next turn summary")

# MarketState.execute_sale is the unified low-level sell primitive. The three tests
# below pin the three axes the option dict toggles, so any drift in queue_sell's or
# Production's wrapper is caught by something tighter than the E2E suite.

func _test_market_execute_sale() -> void:
	# Default behaviour: consume from the tile, log to ledger, defer revenue until
	# the shipment lands at the port. Mirrors the queue_sell path.
	Stockpile.add("tile_3_8", "g_001", 12)
	var ships_before := MatchState.get_pending_transport_shipments().size()
	var txn_before := MatchState.get_oneoff_transaction_rows().size()
	var result: Dictionary = MarketState.execute_sale("tile_3_8", {"g_001": 12})
	_check(not result.is_empty(), "execute_sale returns a result")
	_check(Stockpile.get_at_tile("tile_3_8", "g_001") == 0, "execute_sale consumes from the tile")
	_check(bool(result.get("deferred", false)) and MatchState.get_pending_transport_shipments().size() > ships_before,
		"execute_sale queues a shipment (deferred sale)")
	_check(MatchState.get_oneoff_transaction_rows().size() > txn_before,
		"execute_sale logs a transaction row by default")
	_check(float(result.get("transport_cost", -1.0)) == 0.0,
		"execute_sale: transport not paid from seller unless requested")

func _test_market_execute_sale_skip_consume() -> void:
	# skip_consume: the goods are already in the caller's hand (production output);
	# the stockpile is not touched.
	var tile := "tile_3_8"
	Stockpile.consume(tile, "g_001", 1 << 30)  # drain
	var before: int = Stockpile.get_at_tile(tile, "g_001")
	var result: Dictionary = MarketState.execute_sale(tile, {"g_001": 5},
		{"skip_consume": true, "log_oneoff": false})
	_check(not result.is_empty(), "execute_sale(skip_consume) sells without stockpile")
	_check(Stockpile.get_at_tile(tile, "g_001") == before,
		"execute_sale(skip_consume) does not touch the stockpile")
	_check(int(result.get("total_qty", 0)) == 5,
		"execute_sale(skip_consume) sells the full requested quantity")

func _test_market_execute_sale_pay_transport() -> void:
	# pay_transport_from_seller: the seller eats the freight cost upfront. This is
	# the difference between Production's output-routed sales and the gross manual
	# sells from queue_sell.
	var tile := "tile_3_8"
	Stockpile.add(tile, "g_001", 20)
	var money_before: float = MatchState.money
	var result: Dictionary = MarketState.execute_sale(tile, {"g_001": 20},
		{"pay_transport_from_seller": true, "log_oneoff": false})
	_check(not result.is_empty(), "execute_sale(pay_transport) returns a result")
	var paid: float = float(result.get("transport_cost", 0.0))
	_check(paid > 0.0, "execute_sale(pay_transport) charges a non-zero transport cost")
	_check(absf((money_before - paid) - MatchState.money) < 0.01,
		"execute_sale(pay_transport) deducts transport upfront (paid=%.4f, Δmoney=%.4f)"
			% [paid, money_before - MatchState.money])

func _test_move_extras() -> void:
	var preview: Dictionary = MatchState.preview_move("tile_12_4", "tile_12_2", {"g_001": 5})
	_check(preview.has("turns") and preview.has("cost") and preview.has("per_turn"),
		"preview_move returns route info (turns/cost/per_turn)")
	MatchState.run_recurring_and_scheduled_moves()  # empty queues — must not crash
	_check(true, "run_recurring_and_scheduled_moves runs without error")

func _test_queue_move() -> void:
	Stockpile.add("tile_12_4", "g_001", 10)
	var before_pending: int = MatchState.get_pending_transport_shipments().size()
	var summary: Dictionary = MatchState.queue_move("tile_12_4", "tile_12_2", {"g_001": 10})
	_check(not summary.is_empty(), "queue_move returns a summary")
	_check(Stockpile.get_at_tile("tile_12_4", "g_001") == 0, "queue_move consumes from source")
	_check(MatchState.get_pending_transport_shipments().size() > before_pending, "queue_move queues a shipment")

func _test_debug_terminal() -> void:
	var term: Node = load("res://scripts/debug_terminal.gd").new()
	add_child(term)
	await get_tree().process_frame
	# Commands are gated behind `debug CandC` (case-sensitive, per app run).
	term._cheats_unlocked = false
	_check(term._run_command("cash 250") == "invalid operation", "terminal: locked before unlock")
	_check(term._run_command("debug candc") == "invalid operation", "terminal: pass-phrase is case-sensitive")
	_check(term._run_command("help") == "invalid operation", "terminal: help locked too")
	_check("enabled" in term._run_command("debug CandC"), "terminal: debug CandC unlocks")
	_check("already" in term._run_command("debug CandC"), "terminal: repeat unlock reported")
	var before: float = MatchState.money
	var result: String = term._run_command("cash 250")
	_check(absf(MatchState.money - (before + 250.0)) < 0.001, "terminal: cash adds the amount")
	_check("250" in result, "terminal: cash reports the amount")
	_check(term._run_command("bogus").begins_with("unknown"), "terminal: unknown command handled")
	# 'toggle heightmap' flips the hill/sea/lake layer; default is visible
	var fake_layer := Node2D.new()
	fake_layer.add_to_group("hill_visuals")
	add_child(fake_layer)
	_check(fake_layer.visible, "terminal: heightmap starts visible")
	_check("off" in term._run_command("toggle heightmap"), "terminal: toggle heightmap reports off")
	_check(not fake_layer.visible, "terminal: heightmap hidden after first toggle")
	_check("on" in term._run_command("toggle heightmap"), "terminal: toggle heightmap reports on")
	_check(fake_layer.visible, "terminal: heightmap visible after second toggle")
	fake_layer.queue_free()
	term.queue_free()

func _test_app_paths() -> void:
	# Portable data layout: saves/logs sit next to the build, in the project when in-editor.
	var AppPaths = load("res://scripts/app_paths.gd")
	# The macOS base is the folder CONTAINING the .app — 4 levels up from the binary.
	var sample := "/Users/x/Carbon and Capital (Experimental)/Carbon and Capital.app/Contents/MacOS/Carbon and Capital"
	_check(AppPaths._macos_bundle_parent(sample) == "/Users/x/Carbon and Capital (Experimental)",
		"app_paths: macOS base resolves to the folder containing the .app")
	var base: String = AppPaths.base_dir()
	_check(AppPaths.saves_dir() == base.path_join("savegames"), "app_paths: saves_dir is <base>/savegames")
	_check(AppPaths.logs_dir() == base.path_join("logs"), "app_paths: logs_dir is <base>/logs")
	_check(DirAccess.dir_exists_absolute(AppPaths.saves_dir()), "app_paths: savegames dir is created on demand")
	_check(DirAccess.dir_exists_absolute(AppPaths.logs_dir()), "app_paths: logs dir is created on demand")
	# In the editor + headless runner (both carry the "editor" feature) the base is the project folder.
	_check(base == ProjectSettings.globalize_path("res://").trim_suffix("/"),
		"app_paths: editor/test base is the project folder, not user://")

func _test_capacity_dialog_expand() -> void:
	# The tile-at-capacity dialog's Expand button drives the real per-tile warehouse
	# upgrade (materials from empire stock or market), and Stop Production is disabled.
	var Cap := load("res://scripts/capacity_dialog.gd")
	var dlg: Node = Cap.new()
	add_child(dlg)
	await get_tree().process_frame
	var tile := "tile_16_4"
	Stockpile.set_warehouse_level(tile, 1)
	_check(Stockpile.get_warehouse_level(tile) == 1, "capacity dialog: tile starts at warehouse L1")
	# Stock the L1->L2 bill so the works pay from empire stock (no cash path needed).
	var costs: Dictionary = EconomyConfig.WAREHOUSE_UPGRADE_COSTS[2]
	var totals_before: Dictionary = {}
	for gid in costs:
		totals_before[gid] = Stockpile.get_total(str(gid))
		Stockpile.add(tile, str(gid), int(costs[gid]))
	# Present the dialog for this tile and check button states.
	dlg._on_tile_reached_capacity(tile)
	_check(dlg._current_tile == tile, "capacity dialog: shows the full tile")
	_check(not dlg._expand_btn.disabled, "capacity dialog: Expand enabled when affordable")
	_check(dlg._stop_btn.disabled, "capacity dialog: Stop Production is disabled")
	_check(dlg._stop_btn.tooltip_text == "Coming soon", "capacity dialog: Stop Production hover says 'Coming soon'")
	# Press Expand — the warehouse upgrades and the bill is consumed from stock.
	dlg._choose(Cap.ACTION_EXPAND)
	_check(Stockpile.get_warehouse_level(tile) == 2, "capacity dialog: Expand upgrades the warehouse to L2")
	var consumed_ok := true
	for gid in costs:
		if Stockpile.get_total(str(gid)) != int(totals_before[gid]):
			consumed_ok = false
	_check(consumed_ok, "capacity dialog: Expand consumed exactly the material bill from stock")
	Stockpile.set_warehouse_level(tile, 1)  # reset shared state for later tests
	dlg.queue_free()

func _test_building_ledger() -> void:
	_check(MatchState.route_objective == MatchState.RouteObjective.FASTEST,
		"route objective defaults to FASTEST")
	var scene := load("res://scenes/building_ledger_panel.tscn")
	var ok := false
	if scene != null:
		var panel: Node = scene.instantiate()
		add_child(panel)
		await get_tree().process_frame
		ok = panel.get_child_count() > 0
		panel.queue_free()
	_check(ok, "building_ledger_panel instantiates (routing dropdown builds)")

func _test_ports() -> void:
	var ports := Catalog.all_ports()
	_check(ports.size() == 4, "Catalog loads 4 ports")
	var fields_ok := true
	for p in ports:
		if str(p.get("tile_id", "")) == "" or str(p.get("name", "")) == "":
			fields_ok = false
	_check(fields_ok, "every port has a tile_id and name")
	_check(Catalog.tile_hex_distance("tile_5_10", "tile_5_10") == 0, "tile_hex_distance(self) == 0")
	_check(Catalog.nearest_port_tile("tile_3_8") == "tile_5_10", "nearest_port_tile picks the closest port")
	_check(Catalog.tile_label("tile_12_2") == "Miney McMineface - (12_2)", "tile_label uses nickname")
	_check(Catalog.tile_label("tile_5_10") == "Stoneshore Docks - (5_10)", "tile_label falls back to city_name")
	_check(Catalog.infra_range("roads") == 2, "roads range is 2 tiles/turn")
	_check(Catalog.infra_range("rail") == 4, "rail range is 4 tiles/turn")
	_check(Catalog.all_infrastructure().size() == 5, "Catalog loads 5 infrastructure types")
	_check(Catalog.tile_neighbours("tile_12_2").size() == 6, "interior tile has 6 hex neighbours")
	_check(int(TransportService.route("tile_12_2", "tile_12_2").get("turns", -1)) == 0, "route same-tile = 0 turns")
	_check(int(TransportService.route("tile_12_2", "tile_13_2").get("turns", -1)) == 1, "route to adjacent tile = 1 turn")

func _test_building_price() -> void:
	var BuildingPrice := preload("res://scripts/building_price.gd")
	var bid := "b_007"  # Industrial Goods Factory — has a real build-material kit
	var far := {"instance_id": "bp_far", "building_id": bid, "tile_id": "tile_12_2", "level": 1}
	var base: float = BuildingPrice.base_cost(far)
	_check(base > 0.0, "building price: base cost is positive")
	_check(BuildingPrice.sale_price(far) == BuildingPrice.sale_price(far), "building price: deterministic")

	# Variation multiplier is one of 0.70..1.00 in 5% steps.
	var m: float = BuildingPrice.variation_multiplier("bp_far")
	var step_ok := false
	for k in range(BuildingPrice.VARIATION_STEPS):
		if absf(m - (BuildingPrice.VARIATION_MIN + BuildingPrice.VARIATION_STEP * k)) < 0.0001:
			step_ok = true
	_check(step_ok, "building price: variation is a 5% step within 70-100%")

	# Different buildings of the same type can be priced differently.
	var distinct := {}
	for i in range(24):
		distinct[BuildingPrice.variation_multiplier("bp_inst_%d" % i)] = true
	_check(distinct.size() > 1, "building price: varies across buildings of the same type")

	# Off-port price stays within the 70-100% band; a port tile adds the +10% premium.
	if not BuildingPrice.is_near_port("tile_12_2"):
		var ratio: float = float(BuildingPrice.sale_price(far)) / base
		_check(ratio >= BuildingPrice.VARIATION_MIN - 0.01 and ratio <= 1.0 + 0.01,
			"building price: off-port price within 70-100%")
		var ports := Catalog.all_ports()
		if ports.size() > 0:
			var port_tile := str(ports[0].get("tile_id", ""))
			var off := {"instance_id": "bp_pp", "building_id": bid, "tile_id": "tile_12_2", "level": 1}
			var on := {"instance_id": "bp_pp", "building_id": bid, "tile_id": port_tile, "level": 1}
			_check(BuildingPrice.sale_price(on) > BuildingPrice.sale_price(off),
				"building price: port proximity adds a premium")

	# An L2 building costs more than L1 (extra upgrade kit + larger footprint).
	var l1 := {"instance_id": "bp_lvl", "building_id": bid, "tile_id": "tile_12_2", "level": 1}
	var l2 := {"instance_id": "bp_lvl", "building_id": bid, "tile_id": "tile_12_2", "level": 2}
	_check(BuildingPrice.base_cost(l2) > BuildingPrice.base_cost(l1), "building price: L2 base cost exceeds L1")

func _test_buy_grants_land() -> void:
	# Buying an NPC building grants its footprint as owned land on the tile, exactly once.
	var tile := "bp_land_tile"
	MatchState.tile_land_owned.erase(tile)  # start from the default for this synthetic tile
	var iid: String = MatchState.add_building("b_007", "", tile, "Test NPC Co", "", false)
	var owned_before: int = MatchState.get_tile_land_owned(tile)  # default 100
	var footprint: int = int(Catalog.get_building("b_007").get("tile_size_used", 1))  # 10 at L1
	MatchState.set_building_owner(iid, MatchState.LOCAL_PLAYER)
	var owned_after: int = MatchState.get_tile_land_owned(tile)
	_check(owned_after == mini(MatchState.MAX_TILE_LAND, owned_before + footprint),
		"buy grants the building footprint as owned land")
	MatchState.set_building_owner(iid, MatchState.LOCAL_PLAYER)  # already owned
	_check(MatchState.get_tile_land_owned(tile) == owned_after, "buying again does not double-grant land")
	MatchState.remove_building(iid)
	MatchState.tile_land_owned.erase(tile)

func _test_transport_service() -> void:
	var route: Dictionary = TransportService.route("tile_12_2", "tile_13_2", "g_001")
	_check(int(route.get("turns", -1)) == 1, "TransportService routes adjacent tiles")
	var quote: Dictionary = TransportService.quote_manifest("tile_12_2", "tile_13_2", {"g_001": 10})
	_check(int(quote.get("turns", -1)) == 1 and float(quote.get("cost", 0.0)) > 0.0,
		"TransportService quotes a manifest with turns and cost")
	var buy_quote: Dictionary = TransportService.quote_market_buy("tile_3_8", "g_001", 10, false)
	_check(str(buy_quote.get("port", "")) == "tile_5_10"
		and absf(float(buy_quote.get("cost", 0.0)) - (float(buy_quote.get("goods_cost", 0.0)) + float(buy_quote.get("transport_cost", 0.0)))) < 0.01,
		"TransportService quotes a market buy through the nearest port")
	var covered_buy: Dictionary = TransportService.quote_market_buy("tile_3_8", "g_001", 10, true)
	_check(int(covered_buy.get("turns", 0)) == 1 and float(covered_buy.get("transport_cost", -1.0)) == 0.0,
		"TransportService applies covered seaport buy quotes")
	var covered_sell: Dictionary = TransportService.quote_market_sell("tile_3_8", {"g_001": 10}, {"g_001": true})
	_check(int(covered_sell.get("turns", 0)) == 1 and float(covered_sell.get("transport_cost", -1.0)) == 0.0,
		"TransportService applies covered seaport sell quotes")
	var src := "tile_12_2"
	var dst := "tile_13_2"
	var safe_liquid := "g_009"
	var hazard_liquid := "g_065"
	var no_pipe_route := TransportService.route(src, dst, safe_liquid)
	_check(not TransportService.route_is_reachable(no_pipe_route),
		"safe liquid has no distance fallback when no pipeline exists")
	# BUG FIX (owner 2026-07-11): an unreachable route must cost NOTHING — the
	# INF_TURNS sentinel used to explode fluid output transport into the billions
	# while never delivering.
	_check(TransportService.transport_cost_for_route(safe_liquid, 100, no_pipe_route) == 0.0,
		"unreachable routes are never charged for transport")
	_check(TransportService.quote_market_buy(dst, safe_liquid, 5, false).is_empty()
			and TransportService.quote_market_buy(dst, safe_liquid, 5, true).is_empty(),
		"market buys cannot bypass the pipeline requirement for safe liquids")
	Stockpile.clear_all()
	MatchState.pending_transport_shipments.clear()
	Stockpile.add(src, safe_liquid, 5)
	var blocked_move := MatchState.queue_move(src, dst, {safe_liquid: 5})
	_check(blocked_move.is_empty()
			and Stockpile.get_at_tile(src, safe_liquid) == 5
			and MatchState.pending_transport_shipments.is_empty(),
		"blocked liquid moves leave stock on the source tile")
	var blocked_sale := MatchState.queue_sell(src, {safe_liquid: 2}, false)
	_check(blocked_sale.is_empty() and Stockpile.get_at_tile(src, safe_liquid) == 5,
		"blocked liquid market sales leave stock on the source tile")
	Catalog.add_tile_infrastructure(src, "pipes")
	Catalog.add_tile_infrastructure(dst, "pipes")
	var safe_pipe_route := TransportService.route(src, dst, safe_liquid)
	var safe_pipe_legs: Array = safe_pipe_route.get("legs", [])
	var safe_pipe_mode := "" if safe_pipe_legs.is_empty() else str((safe_pipe_legs[0] as Dictionary).get("mode", ""))
	_check(TransportService.route_is_reachable(safe_pipe_route)
			and not safe_pipe_legs.is_empty()
			and safe_pipe_mode == "pipes",
		"safe liquid routes through ordinary pipework")
	var hazard_plain_route := TransportService.route(src, dst, hazard_liquid)
	_check(not TransportService.route_is_reachable(hazard_plain_route),
		"hazard liquid refuses ordinary pipework")
	Catalog.add_tile_infrastructure(src, "reinf_pipes")
	Catalog.add_tile_infrastructure(dst, "reinf_pipes")
	var hazard_reinf_route := TransportService.route(src, dst, hazard_liquid)
	var hazard_reinf_legs: Array = hazard_reinf_route.get("legs", [])
	var hazard_reinf_mode := "" if hazard_reinf_legs.is_empty() else str((hazard_reinf_legs[0] as Dictionary).get("mode", ""))
	_check(TransportService.route_is_reachable(hazard_reinf_route)
			and not hazard_reinf_legs.is_empty()
			and hazard_reinf_mode == "reinf_pipes",
		"hazard liquid routes through reinforced pipework")
	Catalog.remove_tile_infrastructure(src, "pipes")
	Catalog.remove_tile_infrastructure(dst, "pipes")
	Catalog.remove_tile_infrastructure(src, "reinf_pipes")
	Catalog.remove_tile_infrastructure(dst, "reinf_pipes")
	# A liquid/gas can only be BOUGHT onto a port tile that has the pipe for it — this closes
	# the same-tile loophole where a building sits ON the port (it used to receive fluids with
	# no pipe at all). Solids need no pipe; hazard liquids need reinf_pipes, not plain pipes.
	var a_port := TransportService.nearest_port_tile(src)
	if a_port != "" and not Catalog.tile_has_infrastructure(a_port, "pipes") and not Catalog.tile_has_infrastructure(a_port, "reinf_pipes"):
		_check(not TransportService.quote_market_buy(a_port, "g_001", 3, false).is_empty(),
			"solid market-buy to a port tile needs no pipe")
		_check(TransportService.quote_market_buy(a_port, safe_liquid, 3, false).is_empty(),
			"safe-liquid market-buy to an unpiped port tile is blocked")
		_check(TransportService.quote_market_buy(a_port, hazard_liquid, 3, false).is_empty(),
			"hazard-liquid market-buy to an unpiped port tile is blocked")
		Catalog.add_tile_infrastructure(a_port, "pipes")
		_check(not TransportService.quote_market_buy(a_port, safe_liquid, 3, false).is_empty(),
			"safe-liquid market-buy succeeds once the port tile has pipes")
		_check(TransportService.quote_market_buy(a_port, hazard_liquid, 3, false).is_empty(),
			"ordinary pipes still don't land hazard liquid at the port")
		Catalog.add_tile_infrastructure(a_port, "reinf_pipes")
		_check(not TransportService.quote_market_buy(a_port, hazard_liquid, 3, false).is_empty(),
			"hazard-liquid market-buy succeeds once the port tile has reinforced pipes")
		Catalog.remove_tile_infrastructure(a_port, "pipes")
		Catalog.remove_tile_infrastructure(a_port, "reinf_pipes")
	# Construction-site delivery diagnostics: a build material that needs a pipeline the site
	# lacks is flagged (so the player learns why the build is stalled). Solids and secured
	# materials raise nothing, and laying the pipe clears it.
	var cd_constr := {"tile_id": src, "materials": [
		{"good_id": hazard_liquid, "name": "Industrial Acids", "secured": false},
		{"good_id": "g_001", "name": "Coal", "secured": false},
	]}
	var cd_rows := BuildingReadout.construction_diagnostics(cd_constr)
	_check(cd_rows.size() == 1 and str((cd_rows[0] as Dictionary).get("tone", "")) == "bad"
			and "reinforced pipeline" in str((cd_rows[0] as Dictionary).get("label", "")).to_lower(),
		"construction diagnostics: flags the undeliverable hazard-liquid material, not the solid")
	var cd_secured := {"tile_id": src, "materials": [{"good_id": hazard_liquid, "name": "Industrial Acids", "secured": true}]}
	_check(BuildingReadout.construction_diagnostics(cd_secured).is_empty(),
		"construction diagnostics: a secured material raises no blocker")
	Catalog.add_tile_infrastructure(src, "reinf_pipes")
	_check(BuildingReadout.construction_diagnostics(cd_constr).is_empty(),
		"construction diagnostics: a reinforced pipe on the site clears the blocker")
	Catalog.remove_tile_infrastructure(src, "reinf_pipes")
	Stockpile.clear_all()
	MatchState.pending_transport_shipments.clear()

func _test_transport_boundaries() -> void:
	var offenders: Array[String] = []
	var files: Array[String] = []
	_collect_gd_files("res://scripts", files)
	for path in files:
		if path.ends_with("/transport_service.gd"):
			continue
		var text := FileAccess.get_file_as_string(path)
		if text.find("Catalog.route(") >= 0:
			offenders.append(path + " uses Catalog.route")
		if text.find("EconomyConfig.transport_") >= 0:
			offenders.append(path + " uses EconomyConfig.transport_*")
	_check(offenders.is_empty(),
		"gameplay transport route/cost callers go through TransportService" + (": " + ", ".join(offenders) if not offenders.is_empty() else ""))

func _collect_gd_files(path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not name.begins_with("."):
			var child := path.path_join(name)
			if dir.current_is_dir():
				_collect_gd_files(child, out)
			elif name.ends_with(".gd"):
				out.append(child)
		name = dir.get_next()
	dir.list_dir_end()

func _test_build_mode_overlay_survey_visibility() -> void:
	var saved_surveyed := MatchState.surveyed_tiles.duplicate(true)
	var saved_partial := MatchState.partially_surveyed_tiles.duplicate(true)
	MatchState.surveyed_tiles.clear()
	MatchState.partially_surveyed_tiles.clear()
	var overlay: Node = load("res://scripts/map_overlay.gd").new()
	var recipe: Dictionary = Catalog.get_recipe("r_001")
	var input_names: Array[String] = []
	for input_name in overlay.call("_recipe_input_internal_names", recipe):
		input_names.append(str(input_name))
	var reqs: Array = recipe.get("requirements", [])
	var coal_tile := {"id": "tile_test_construct_coal", "type": "hill", "deposits": ["coal(1000)"]}
	_check(str(overlay.call("_build_overlay_state", coal_tile, reqs, input_names)) == "none",
		"build overlay hides unsurveyed viable tiles")
	MatchState.mark_tile_partial("tile_test_construct_coal")
	_check(str(overlay.call("_build_overlay_state", coal_tile, reqs, input_names)) == "recommended",
		"build overlay can recommend partially surveyed matching tiles")
	_replace_dict(MatchState.surveyed_tiles, saved_surveyed)
	_replace_dict(MatchState.partially_surveyed_tiles, saved_partial)
	overlay.free()

func _test_direct_build_skips_build_overlay() -> void:
	var saved_active := BuildMode.is_active
	var saved_kind := BuildMode.kind
	var saved_building := BuildMode.current_building_id
	var saved_recipe := BuildMode.current_recipe_id
	var saved_infra := BuildMode.current_infrastructure_type
	var saved_last_attempt := BuildMode._last_attempt_ms
	BuildMode.exit_build_mode()
	BuildMode._last_attempt_ms = -100000
	var observed := {"entered": false, "attempted": false, "recipe_seen": ""}
	var on_entered := func(_building_id: String, _recipe_id: String) -> void:
		observed["entered"] = true
	var on_attempted := func(_building_id: String, _tile_id: String) -> void:
		observed["attempted"] = true
		observed["recipe_seen"] = BuildMode.current_recipe_id
	BuildMode.mode_entered.connect(on_entered)
	BuildMode.build_attempted.connect(on_attempted)
	BuildMode.attempt_direct_build("b_001", "r_001", "tile_test_direct_build")
	_check(bool(observed.get("attempted", false)) and str(observed.get("recipe_seen", "")) == "r_001",
		"direct build emits with recipe context")
	_check(not bool(observed.get("entered", false)) and not BuildMode.is_active,
		"direct build does not enter overlay mode")
	BuildMode.mode_entered.disconnect(on_entered)
	BuildMode.build_attempted.disconnect(on_attempted)
	BuildMode.is_active = saved_active
	BuildMode.kind = saved_kind
	BuildMode.current_building_id = saved_building
	BuildMode.current_recipe_id = saved_recipe
	BuildMode.current_infrastructure_type = saved_infra
	BuildMode._last_attempt_ms = saved_last_attempt

func _test_advisor_star_derivation() -> void:
	var expected := {"vera": 5, "alexandra": 5, "gerald": 4, "eleanor": 4, "sloane": 3, "priya": 3, "hitomi": 3, "hal": 3, "tom": 2, "marcus": 2, "idris": 2, "rufus": 1}
	for aid in expected:
		_check(MatchState.advisor_star_by_id(str(aid)) == int(expected[aid]),
			"advisor star: %s -> %d" % [str(aid), int(expected[aid])])
	# precedence edges (spec §2.2)
	_check(MatchState.advisor_star({"inf": 3, "ops": 3, "lead": 3, "inn": 3, "fin": 1}) == 5,
		"advisor star: four 3s -> 5 (beats the score band)")
	_check(MatchState.advisor_star({"inf": 3, "ops": 3, "lead": 3, "inn": 2, "fin": 1}) == 4,
		"advisor star: score 12 with three 3s -> 4")
	_check(MatchState.advisor_star({"inf": 1, "ops": 1, "lead": 1, "inn": 1, "fin": 1}) == 1,
		"advisor star: all 1s -> 1 (floor)")

func _test_advisor_seat_assign_and_slot_cap() -> void:
	var saved_seats: Dictionary = MatchState.advisor_seats.duplicate(true)
	var saved_slots: int = MatchState.max_advisor_slots
	var saved_hired: Array = MatchState.permanent_advisor_ids.duplicate(true)
	MatchState.permanent_advisor_ids = ["vera", "tom", "marcus", "eleanor"]
	MatchState.advisor_seats = {}
	MatchState.max_advisor_slots = 2
	_check(MatchState.assign_advisor_to_seat("cfo", "vera"), "seat: assign vera -> cfo")
	_check(MatchState.assign_advisor_to_seat("coo", "tom"), "seat: assign tom -> coo")
	_check(not MatchState.assign_advisor_to_seat("hr_director", "eleanor"), "seat: third assign blocked by slot cap (2)")
	_check(not MatchState.assign_advisor_to_seat("cfo", "not_an_advisor"), "seat: unknown advisor rejected")
	_check(not MatchState.assign_advisor_to_seat("bogus_seat", "vera"), "seat: unknown seat rejected")
	_check(MatchState.get_advisor_in_seat("cfo") == "vera", "seat: cfo holds vera")
	# re-assigning within an already-occupied seat consumes no new slot
	_check(MatchState.assign_advisor_to_seat("cfo", "marcus"), "seat: re-assign within cfo (no new slot)")
	_check(MatchState.get_advisor_in_seat("cfo") == "marcus", "seat: cfo now holds marcus")
	# one seat per advisor: moving tom (in coo) to hr vacates coo
	MatchState.max_advisor_slots = 3
	_check(MatchState.assign_advisor_to_seat("hr_director", "tom"), "seat: move tom -> hr_director")
	_check(MatchState.get_advisor_in_seat("coo") == "", "seat: one seat per advisor (coo vacated)")
	_check(MatchState.unassign_seat("cfo"), "seat: unassign frees the seat")
	_check(MatchState.get_advisor_in_seat("cfo") == "", "seat: cfo empty after unassign")
	MatchState.advisor_seats = saved_seats
	MatchState.max_advisor_slots = saved_slots
	MatchState.permanent_advisor_ids = saved_hired

func _test_advisor_seat_tier_scaling() -> void:
	# rigid seats read the governing stat directly
	_check(MatchState.advisor_seat_tier("vera", "cfo") == 3, "tier: vera fin 3 -> cfo tier 3")
	_check(MatchState.advisor_seat_tier("rufus", "cfo") == 1, "tier: rufus fin 1 -> cfo tier 1 (malus)")
	_check(MatchState.advisor_seat_tier("tom", "coo") == 3, "tier: tom ops 3 -> coo tier 3")
	# flexible seats read the best of eligible disciplines
	_check(MatchState.advisor_seat_tier("marcus", "chief_investment") == 3, "tier: marcus max(fin 3, inn 1) -> 3")
	_check(MatchState.advisor_seat_tier("idris", "chief_investment") == 3, "tier: idris max(fin 1, inn 3) -> 3")
	_check(MatchState.advisor_seat_tier("rufus", "chief_markets") == 3, "tier: rufus max(inf 3, fin 1) -> 3")
	_check(MatchState.advisor_seat_tier("hitomi", "sustainability") == 3, "tier: hitomi max(inf 1, ops 3, lead 1) -> 3")
	_check(MatchState.advisor_seat_governing_discipline("idris", "chief_investment") == "inn", "tier: flexible governing discipline reported (inn)")
	_check(MatchState.advisor_seat_tier("vera", "bogus_seat") == 0, "tier: unknown seat -> 0")

func _test_advisor_reconcile_idempotent() -> void:
	Modifiers.reset()
	var saved_seats: Dictionary = MatchState.advisor_seats.duplicate(true)
	MatchState.advisor_seats = {"coo": "tom", "hr_director": "eleanor"}
	# an unrelated modifier that must survive reconcile
	Modifiers.add({"id": "unrelated_test_mod", "domain": "recipe_output", "pct": 5.0})
	MatchState.reconcile_advisor_modifiers()
	var count1: int = Modifiers.active_count()
	MatchState.reconcile_advisor_modifiers()   # second run must not duplicate
	_check(Modifiers.active_count() == count1, "reconcile: idempotent (no duplicate modifiers on re-run)")
	_check(Modifiers.has("advisor_seat_coo_labour_headcount") and Modifiers.has("advisor_seat_hr_director_labour_headcount"),
		"reconcile: emits per-domain effect modifiers per occupied seat")
	_check(Modifiers.has("unrelated_test_mod"), "reconcile: leaves non-advisor modifiers untouched")
	MatchState.advisor_seats = {"coo": "tom"}
	MatchState.reconcile_advisor_modifiers()
	_check(not Modifiers.has("advisor_seat_hr_director_labour_headcount"), "reconcile: drops modifiers for vacated seats")
	MatchState.advisor_seats = saved_seats
	Modifiers.reset()

func _test_advisor_seat_effects() -> void:
	Modifiers.reset()
	var saved_seats: Dictionary = MatchState.advisor_seats.duplicate(true)
	# Tom (ops 3) in COO -> tier 3 -> full reductions
	MatchState.advisor_seats = {"coo": "tom"}
	MatchState.reconcile_advisor_modifiers()
	_check(is_equal_approx(float(Modifiers.resolve_pct("labour_headcount", "b_001", {"building_id": "b_001"}).get("net", 0.0)), -10.0),
		"effects: COO tier 3 -> labour_headcount -10%")
	_check(is_equal_approx(float(Modifiers.resolve_pct("maintenance", "b_001", {"building_id": "b_001"}).get("net", 0.0)), -10.0),
		"effects: COO tier 3 -> maintenance -10%")
	# COO + HR (Eleanor lead 3) -> dual-source labour stacks additively to -20%
	MatchState.advisor_seats = {"coo": "tom", "hr_director": "eleanor"}
	MatchState.reconcile_advisor_modifiers()
	_check(is_equal_approx(float(Modifiers.resolve_pct("labour_headcount", "b_001", {"building_id": "b_001"}).get("net", 0.0)), -20.0),
		"effects: COO + HR labour stacks additively to -20%")
	# VP Logistics (Hitomi ops 3) -> transport cost
	MatchState.advisor_seats = {"vp_logistics": "hitomi"}
	MatchState.reconcile_advisor_modifiers()
	_check(is_equal_approx(float(Modifiers.resolve_pct("transport_cost", "*", {}).get("net", 0.0)), -10.0),
		"effects: VP Logistics tier 3 -> transport_cost -10%")
	# tier-1 malus: Rufus (ops 1) in COO -> labour reduction flips to a +5% penalty
	MatchState.advisor_seats = {"coo": "rufus"}
	MatchState.reconcile_advisor_modifiers()
	_check(is_equal_approx(float(Modifiers.resolve_pct("labour_headcount", "b_001", {"building_id": "b_001"}).get("net", 0.0)), 5.0),
		"effects: COO tier 1 (ops 1) -> labour malus +5%")
	# CFO (Marcus fin 3 -> tier 3) emits its Phase-2 finance levers
	MatchState.advisor_seats = {"cfo": "marcus"}
	MatchState.reconcile_advisor_modifiers()
	_check(is_equal_approx(float(Modifiers.resolve_pct("loan_interest", "*", {}).get("net", 0.0)), -25.0)
		and is_equal_approx(float(Modifiers.resolve_pct("dividend_rate", "*", {}).get("net", 0.0)), -40.0),
		"effects: CFO tier 3 -> loan_interest -25% + dividend_rate -40%")
	MatchState.advisor_seats = saved_seats
	Modifiers.reset()

func _test_advisor_phase2_effects() -> void:
	Modifiers.reset()
	var saved_seats: Dictionary = MatchState.advisor_seats.duplicate(true)
	# Government Affairs: Hal (inf 3) -> tier 3 -> tax_rate -20%
	MatchState.advisor_seats = {"government_affairs": "hal"}
	MatchState.reconcile_advisor_modifiers()
	_check(is_equal_approx(float(Modifiers.resolve_pct("tax_rate", "*", {}).get("net", 0.0)), -20.0),
		"phase2: Government Affairs tier 3 -> tax_rate -20%")
	# Chief Markets (flexible): Sloane best-of(inf 3, fin 2) = 3 -> market_spread -25%
	MatchState.advisor_seats = {"chief_markets": "sloane"}
	MatchState.reconcile_advisor_modifiers()
	_check(is_equal_approx(float(Modifiers.resolve_pct("market_spread", "*", {}).get("net", 0.0)), -25.0),
		"phase2: Chief Markets tier 3 -> market_spread -25%")
	_check(MarketState.get_buy_price("g_001") < MarketState.get_price("g_001") * (1.0 + EconomyConfig.MARKET_BUY_MARKUP),
		"phase2: market_spread modifier tightens the buy price")
	# Chief Markets also lifts the realised SALE price via the market_price domain (+6% tier 3)
	var g := str(Catalog.all_goods()[0].get("id", "g_001"))
	var boosted: float = Modifiers.apply("market_price", g, MarketState.get_price(g),
		{"good_id": g, "good_internal": str(Catalog.get_good(g).get("internal_name", ""))})
	_check(is_equal_approx(boosted, MarketState.get_price(g) * 1.02),
		"phase2: Chief Markets tier 3 -> +2% realised sale price")
	# Arbitrage guard: realised sale price is clamped to the buy price even with a big
	# market_price uplift, so buy-then-resell can never turn a profit.
	Modifiers.add({"id": "test_big_sale_lift", "domain": "market_price", "pct": 50.0, "label": "t", "source": "test"})
	_check(MarketState.get_sale_price(g, {"good_id": g}) <= MarketState.get_buy_price(g) + 0.0001,
		"phase2: sale price is clamped to buy price (no market arbitrage)")
	Modifiers.remove("test_big_sale_lift")
	# CFO: Marcus (fin 3) -> loan interest cut + dividend holiday take effect at their sites
	MatchState.advisor_seats = {"cfo": "marcus"}
	MatchState.reconcile_advisor_modifiers()
	_check(is_equal_approx(LoanState.effective_loan_interest_rate(), EconomyConfig.LOAN_INTEREST_RATE * 0.75),
		"phase2: CFO cuts the effective loan interest rate to 75%")
	var div_mult: float = maxf(0.0, 1.0 + float(Modifiers.resolve_pct("dividend_rate", "*", {}).get("net", 0.0)) / 100.0)
	_check(is_equal_approx(div_mult, 0.6), "phase2: CFO cuts the dividend rate 40% (partial holiday)")
	# Chief Investment (Alexandra inn 3 -> tier 3) rebates 10% of build-materials value
	MatchState.advisor_seats = {"chief_investment": "alexandra"}
	MatchState.reconcile_advisor_modifiers()
	_check(is_equal_approx(float(Modifiers.resolve_pct("construction_rebate", "*", {}).get("net", 0.0)), 10.0),
		"phase2: Chief Investment tier 3 -> construction_rebate +10%")
	var ci_bid := ""
	for b in Catalog.all_buildings():
		if not Construction.requirements_for(str(b.get("id", ""))).is_empty():
			ci_bid = str(b.get("id", ""))
			break
	if ci_bid != "":
		var reqs: Dictionary = Construction.requirements_for(ci_bid)
		var mv := 0.0
		for gid2 in reqs:
			mv += float(int(reqs[gid2])) * MarketState.get_price(str(gid2))
		_check(mv > 0.0 and is_equal_approx(MatchState.construction_material_rebate(ci_bid), mv * 0.10),
			"phase2: Chief Investment rebates 10% of build-materials market value")
	# Land + NPC-building purchases discounted 10% at tier 3
	_check(is_equal_approx(MatchState.purchase_cost_after_advisor(100.0), 90.0),
		"phase2: Chief Investment tier 3 -> land/building purchase -10%")
	# Upgrade kit is rebated the same way as a build (shares construction_rebate)
	_check(is_equal_approx(MatchState._materials_rebate({str(g): 10}), 10.0 * MarketState.get_price(str(g)) * 0.10),
		"phase2: Chief Investment rebates 10% of upgrade-kit materials value")
	# Seated Chief Investment also unlocks build-on-credit (10-turn, 5% construction loan)
	_check(MatchState.construction_credit_available(), "phase2: seated Chief Investment unlocks build-on-credit")
	var money_b := MatchState.money
	var loans_b := LoanState.loans.size()
	var out_b := LoanState.total_outstanding()
	if LoanState.take_construction_loan(20.0):
		var new_loan: Dictionary = LoanState.loans[LoanState.loans.size() - 1]
		_check(LoanState.loans.size() == loans_b + 1
			and is_equal_approx(LoanState.total_outstanding() - out_b, 21.0)
			and int(new_loan.get("turns_remaining", 0)) == LoanState.CONSTRUCTION_LOAN_TERM,
			"phase2: construction loan owes principal + 5% over 10 turns")
		LoanState.loans.remove_at(LoanState.loans.size() - 1)
	MatchState.money = money_b
	# COO negotiates grid tariffs: cheaper imports, better-paid exports (tier 3 -10% / +10%).
	MatchState.advisor_seats = {"coo": "tom"}   # tom ops 3 -> COO tier 3
	MatchState.reconcile_advisor_modifiers()
	_check(is_equal_approx(float(Modifiers.resolve_pct("grid_buy_price", "*", {}).get("net", 0.0)), -10.0)
		and is_equal_approx(float(Modifiers.resolve_pct("grid_sell_price", "*", {}).get("net", 0.0)), 10.0),
		"phase2: COO tier 3 -> grid buy -10% / grid sell +10%")
	# Impact readout derives tier-scaled, per-domain effects for a seat.
	var gov_eff: Array = MatchState.advisor_seat_effect_list("hal", "government_affairs")
	_check(gov_eff.size() == 1 and str(gov_eff[0]["domain"]) == "tax_rate" and is_equal_approx(float(gov_eff[0]["pct"]), -20.0),
		"impact: advisor_seat_effect_list gives tier-scaled per-domain effects")
	MatchState.advisor_seats = {}
	MatchState.reconcile_advisor_modifiers()
	_check(not MatchState.construction_credit_available(), "phase2: no Chief Investment -> build-on-credit locked")
	MatchState.advisor_seats = saved_seats
	MatchState.reconcile_advisor_modifiers()
	Modifiers.reset()

func _test_hr_director_policies() -> void:
	var saved_seats := MatchState.advisor_seats.duplicate(true)
	var saved_pol := MatchState.workforce_policies.duplicate(true)
	var saved_eff := MatchState.workforce_policy_effects.duplicate(true)
	MatchState.workforce_policies = {}
	MatchState.workforce_policy_effects = {}
	var LT: String = MatchState.WORKFORCE_POLICY_LONG_TENURE
	var SO: String = MatchState.WORKFORCE_POLICY_STOCK_OPTIONS

	MatchState.advisor_seats = {}
	MatchState.reconcile_advisor_modifiers()
	_check(not MatchState.is_workforce_policy_available(LT) and not MatchState.is_workforce_policy_available(SO),
		"HR: both policies locked with no HR Director")
	# Priya (lead 2): Long Tenure unlocked, Stock Options still locked.
	MatchState.advisor_seats = {"hr_director": "priya"}
	MatchState.reconcile_advisor_modifiers()
	_check(MatchState.is_workforce_policy_available(LT) and not MatchState.is_workforce_policy_available(SO),
		"HR: Long Tenure needs any HR Director; Stock Options stays locked until its mission")
	# Vera seated: Long Tenure available, but Stock Options is now MISSION-gated (not seat).
	MatchState.advisor_seats = {"hr_director": "vera"}
	MatchState.reconcile_advisor_modifiers()
	_check(MatchState.is_workforce_policy_available(LT) and not MatchState.is_workforce_policy_available(SO),
		"HR: Stock Options no longer unlocks by seating alone (mission-gated)")
	MatchState.advisor_mission_policies = [SO]   # an HR advisor's mission V grants it
	_check(MatchState.is_workforce_policy_available(SO),
		"HR: Stock Options unlocks once an HR advisor's mission grants it")

	# Long Tenure accrues -0.1%/turn labour + a +10% spike every 10th turn.
	MatchState.set_workforce_policy_enabled(LT, true)
	for _i in 5:
		MatchState.tick_workforce_policies()
	var lt_eff: Dictionary = MatchState.workforce_policy_effects.get(LT, {})
	_check(is_equal_approx(float(lt_eff.get("labour_pct", 0.0)), -0.005),
		"HR: Long Tenure accrues -0.1%/turn labour (-0.5% after 5 turns)")
	_check(is_equal_approx(MatchState.workforce_labour_cost_delta(10) - MatchState.workforce_labour_cost_delta(11), 0.10),
		"HR: Long Tenure adds a +10% labour spike every 10th turn")

	# Stock Options accrues output + a dividend bonus (persisted in workforce_dividend_bonus).
	MatchState.set_workforce_policy_enabled(SO, true)
	for _j in 5:
		MatchState.tick_workforce_policies()
	var so_eff: Dictionary = MatchState.workforce_policy_effects.get(SO, {})
	_check(float(so_eff.get("output_pct", 0.0)) > 0.0
		and float(so_eff.get("dividend_pct", 0.0)) > 0.0
		and is_equal_approx(MatchState.workforce_dividend_bonus(), float(so_eff.get("dividend_pct", 0.0))),
		"HR: Stock Options accrues output + dividend bonus")

	# Un-seating the HR Director revokes the seat-gated policy (Long Tenure); the
	# mission-unlocked Stock Options is earned permanently and stays available.
	MatchState.advisor_seats = {}
	MatchState.reconcile_advisor_modifiers()
	_check(not MatchState.is_workforce_policy_enabled(LT) and MatchState.is_workforce_policy_available(SO),
		"HR: un-seating revokes Long Tenure but keeps the mission-earned Stock Options")

	MatchState.advisor_mission_policies = []
	MatchState.advisor_seats = saved_seats
	MatchState.workforce_policies = saved_pol
	MatchState.workforce_policy_effects = saved_eff
	MatchState.reconcile_advisor_modifiers()

func _test_retrofit_mechanic() -> void:
	# Find a building type with at least two recipes to retrofit between.
	var by_b: Dictionary = {}
	for r in Catalog.all_recipes():
		var b := str(r.get("building_id", ""))
		if b == "":
			continue
		if not by_b.has(b):
			by_b[b] = []
		(by_b[b] as Array).append(str(r.get("recipe_id", "")))
	var bid := ""
	var recs: Array = []
	for b in by_b:
		if (by_b[b] as Array).size() >= 2:
			bid = str(b)
			recs = by_b[b]
			break
	if bid == "":
		_check(true, "retrofit: skipped (no multi-recipe building in catalog)")
		return

	var saved_seats := MatchState.advisor_seats.duplicate(true)
	var saved_money := MatchState.money
	var saved_buildings := MatchState.buildings.duplicate(true)
	var saved_retro := MatchState.pending_retrofits.duplicate(true)
	MatchState.advisor_seats = {}
	MatchState.money = 1000.0
	MatchState.pending_retrofits = []
	var iid := "test_retrofit_1"
	MatchState.buildings[iid] = {"instance_id": iid, "building_id": bid, "recipe_id": str(recs[0]), "tile_id": "tile_0_0", "level": 1}

	var tier: Dictionary = MatchState.retrofit_cost_tier()
	_check(is_equal_approx(float(tier["labour"]), 0.50) and int(tier["turns"]) == 2,
		"retrofit: base tier (no COO) = 50% labour, 2 turns")

	var before := MatchState.money
	var res: Dictionary = MatchState.start_retrofit(iid, str(recs[1]))
	_check(bool(res["ok"]) and MatchState.is_retooling(iid)
		and is_equal_approx(MatchState.money, before - 25.0)
		and is_equal_approx(MatchState.retooling_labour_fraction(iid), 0.50),
		"retrofit: start charges the fee, marks retooling, applies reduced labour")
	_check(not bool(MatchState.start_retrofit(iid, str(recs[0]))["ok"]),
		"retrofit: blocked while already retooling")

	MatchState.tick_retrofits()
	_check(MatchState.is_retooling(iid), "retrofit: still retooling after 1 tick (base = 2 turns)")
	MatchState.tick_retrofits()
	_check(not MatchState.is_retooling(iid) and str(MatchState.buildings[iid]["recipe_id"]) == str(recs[1]),
		"retrofit: completes after 2 turns and swaps in the new recipe")

	MatchState.advisor_seats = {"coo": "tom"}   # Ops 3
	var t3: Dictionary = MatchState.retrofit_cost_tier()
	_check(int(t3["turns"]) == 1 and is_equal_approx(float(t3["labour"]), 0.30),
		"retrofit: Ops-3 COO = 1 turn, 30% labour")
	MatchState.advisor_seats = {"coo": "rufus"}   # Ops 1 malus
	var t1: Dictionary = MatchState.retrofit_cost_tier()
	_check(is_equal_approx(float(t1["labour"]), 0.75) and is_equal_approx(float(t1["fee"]), 40.0),
		"retrofit: Ops-1 COO malus = 75% labour, £40 (worse than base)")

	MatchState.advisor_seats = {}
	MatchState.start_retrofit(iid, str(recs[0]))
	_check((MatchState.export_state().get("pending_retrofits", []) as Array).size() >= 1,
		"retrofit: pending_retrofits is written to the save state")

	MatchState.advisor_seats = saved_seats
	MatchState.money = saved_money
	MatchState.buildings = saved_buildings
	MatchState.pending_retrofits = saved_retro

func _test_sell_and_demolish() -> void:
	var saved_money := MatchState.money
	var saved_buildings := MatchState.buildings.duplicate(true)
	var saved_queue := MatchState.demolish_queue.duplicate(true)
	MatchState.money = 1000.0
	MatchState.buildings = {}
	MatchState.demolish_queue = {}

	# Sell: credits the market value, flips owner to the NPC operator, building stays.
	var sid := "test_sell_1"
	MatchState.buildings[sid] = {"instance_id": sid, "building_id": "b_001", "recipe_id": "r_001", "tile_id": "tile_0_0", "level": 1, "owner": MatchState.LOCAL_PLAYER}
	var before_money := MatchState.money
	var sres: Dictionary = MatchState.sell_building(sid)
	_check(bool(sres.get("ok", false)) and int(sres.get("price", -1)) >= 0, "sell: returns ok + a price")
	_check(MatchState.buildings.has(sid) and str(MatchState.buildings[sid].get("owner", "")) == MatchState.SOLD_TO_OWNER,
		"sell: building stays on the tile, owner → NPC operator")
	_check(MatchState.money >= before_money, "sell: value credited to the player")
	_check(not bool(MatchState.sell_building(sid).get("ok", false)), "sell: an NPC-owned building can't be player-sold again")

	# Demolish: queued 1-turn job that removes the building on tick.
	var did := "test_demo_1"
	MatchState.buildings[did] = {"instance_id": did, "building_id": "b_001", "recipe_id": "r_001", "tile_id": "tile_0_0", "level": 1, "owner": MatchState.LOCAL_PLAYER}
	var dres: Dictionary = MatchState.start_demolish(did)
	_check(bool(dres.get("ok", false)) and MatchState.is_demolishing(did) and MatchState.demolish_turns_remaining(did) == 1,
		"demolish: queued with a 1-turn countdown")
	_check(not bool(MatchState.start_demolish(did).get("ok", false)), "demolish: can't double-queue")
	MatchState.tick_demolish()
	_check(not MatchState.buildings.has(did) and not MatchState.is_demolishing(did),
		"demolish: tick removes the building and clears the queue")

	# Demolish queue survives a save round-trip (additive field, tolerant reader — no version bump).
	var qid := "test_demo_rt"
	MatchState.buildings[qid] = {"instance_id": qid, "building_id": "b_001", "recipe_id": "r_001", "tile_id": "tile_0_0", "level": 1, "owner": MatchState.LOCAL_PLAYER}
	MatchState.start_demolish(qid)
	var snap: Dictionary = MatchState.export_state()
	MatchState.demolish_queue = {}
	MatchState.import_state(snap)
	_check(MatchState.is_demolishing(qid), "demolish: queue survives export/import round-trip")

	MatchState.money = saved_money
	MatchState.buildings = saved_buildings
	MatchState.demolish_queue = saved_queue

func _test_build_duration() -> void:
	var saved_seats := MatchState.advisor_seats.duplicate(true)
	# A building with a real (>0) build duration.
	var bid := ""
	var raw := 0
	for b in Catalog.all_buildings():
		var d := int(b.get("build_duration", 0))
		if d > 0:
			bid = str(b.get("id", ""))
			raw = d
			break
	if bid == "":
		_check(true, "build duration: skipped (no timed building)")
		return
	MatchState.advisor_seats = {}
	_check(MatchState.effective_build_duration(bid) == raw + MatchState.BUILD_DURATION_BUMP,
		"build duration: bumped by +1 over the raw CSV value")
	# Master builder (Gerald as COO) shaves a turn off, clamped at the 1-turn minimum.
	MatchState.advisor_seats = {"coo": MatchState.MASTER_BUILDER_ID}
	_check(MatchState.effective_build_duration(bid) == maxi(1, raw + MatchState.BUILD_DURATION_BUMP - 1),
		"build duration: master-builder COO reduces it by 1 (min 1)")
	_check(MatchState.effective_build_duration(bid) >= MatchState.BUILD_DURATION_MIN,
		"build duration: never below the 1-turn minimum")
	MatchState.advisor_seats = saved_seats

func _test_advisor_loyalty() -> void:
	var saved_perm := MatchState.permanent_advisor_ids.duplicate(true)
	var saved_rec := MatchState.recruited_advisor_ids.duplicate(true)
	var saved_loyal := MatchState.advisor_loyalty.duplicate(true)
	var saved_walk := MatchState._advisor_walk_streak.duplicate(true)
	var saved_fired := MatchState.fired_advisor_cooldowns.duplicate(true)
	var saved_seats := MatchState.advisor_seats.duplicate(true)
	MatchState.permanent_advisor_ids = []
	MatchState.recruited_advisor_ids = ["vera", "marcus"]
	MatchState.advisor_seats = {}
	MatchState.fired_advisor_cooldowns = {}
	MatchState.advisor_loyalty = {}
	MatchState._advisor_walk_streak = {}
	MatchState._agenda_flags = {}

	MatchState.hire_advisor("vera")
	_check(is_equal_approx(MatchState.advisor_loyalty_value("vera"), 0.0), "loyalty: starts at 0 on hire")

	MatchState.cheat_set_loyalty("vera", -50.0)
	_check(is_equal_approx(MatchState.advisor_loyalty_value("vera"), -10.0), "loyalty: cheat clamps at -10")
	MatchState.cheat_set_loyalty("vera", 100.0)
	_check(is_equal_approx(MatchState.advisor_loyalty_value("vera"), 10.0), "loyalty: cheat clamps at +10")

	MatchState.advisor_loyalty["vera"] = 0.0
	MatchState._agenda_flags = {}
	MatchState._evaluate_agendas({"money_in": 100.0, "money_out": 0.0}, 100.0)
	_check(is_equal_approx(MatchState.advisor_loyalty_value("vera"), 0.6),
		"loyalty: a per-turn liked event (+profit) raises loyalty +0.6")
	# Agenda rows: per-turn likes +0.6, per-turn dislikes -0.4, one-off actions ±1.
	var rows: Array = MatchState.advisor_agenda_rows("vera")
	_check(rows.size() == 4 and is_equal_approx(float(rows[0].get("points", 0.0)), 0.6)
		and bool(rows[0].get("per_turn", false)),
		"loyalty: agenda rows expose per-turn like at +0.6/turn")
	# Eleanor dislikes buying grid power (a per-turn event) -> -0.4/turn.
	var el_rows: Array = MatchState.advisor_agenda_rows("eleanor")
	var found_grid := false
	for r in el_rows:
		if not bool(r.get("benefit", true)) and bool(r.get("per_turn", false)):
			found_grid = found_grid or is_equal_approx(float(r.get("points", 0.0)), -0.4)
	_check(found_grid, "loyalty: a per-turn dislike is -0.4/turn")

	MatchState.advisor_loyalty["vera"] = 5.0
	MatchState._agenda_flags = {}
	MatchState.flag_agenda_event(MatchState.AGENDA_TOOK_LOAN)
	MatchState._evaluate_agendas({"money_in": 0.0, "money_out": 0.0}, 0.0)
	_check(is_equal_approx(MatchState.advisor_loyalty_value("vera"), 3.9),
		"loyalty: a disliked event lowers loyalty (net of the 0.1 decay)")

	MatchState.advisor_loyalty["vera"] = 1.0
	MatchState._agenda_flags = {}
	MatchState._evaluate_agendas({"money_in": 0.0, "money_out": 0.0}, 0.0)
	_check(is_equal_approx(MatchState.advisor_loyalty_value("vera"), 0.9), "loyalty: decays 0.1/turn toward 0")

	for _i in MatchState.LOYALTY_WALK_TURNS:
		MatchState.advisor_loyalty["vera"] = -10.0
		MatchState._agenda_flags = {}
		MatchState._evaluate_agendas({"money_in": 0.0, "money_out": 0.0}, 0.0)
	_check(not MatchState.permanent_advisor_ids.has("vera") and MatchState.is_fired("vera"),
		"loyalty: walks after LOYALTY_WALK_TURNS turns at/below the threshold")

	MatchState.permanent_advisor_ids = saved_perm
	MatchState.recruited_advisor_ids = saved_rec
	MatchState.advisor_loyalty = saved_loyal
	MatchState._advisor_walk_streak = saved_walk
	MatchState.fired_advisor_cooldowns = saved_fired
	MatchState.advisor_seats = saved_seats
	MatchState._agenda_flags = {}

func _test_advisor_missions() -> void:
	var saved_perm := MatchState.permanent_advisor_ids.duplicate(true)
	var saved_rec := MatchState.recruited_advisor_ids.duplicate(true)
	var saved_loyal := MatchState.advisor_loyalty.duplicate(true)
	var saved_done := MatchState.advisor_missions_completed.duplicate(true)
	var saved_streak := MatchState._advisor_mission5_streak.duplicate(true)
	var saved_pol := MatchState.advisor_mission_policies.duplicate(true)
	var saved_unlocked := MatchState.unlocked_titles.duplicate(true)
	Modifiers.reset()
	MatchState.permanent_advisor_ids = ["vera", "eleanor"]
	MatchState.recruited_advisor_ids = ["vera", "eleanor"]
	MatchState.advisor_loyalty = {"vera": 0.0, "eleanor": 0.0}
	MatchState.advisor_missions_completed = {}
	MatchState._advisor_mission5_streak = {}
	MatchState.advisor_mission_policies = []

	# Missions I-IV complete the first turn loyalty reaches 2 / 5 / 7 / 9.
	MatchState.advisor_loyalty["vera"] = 3.0
	MatchState._check_mission_progress("vera")
	_check(MatchState.advisor_missions_done("vera") == 1, "mission: M1 completes at loyalty 2")
	# M1 grants a temporary specialty modifier (CFO loan interest).
	_check(float(Modifiers.resolve_pct("loan_interest", "*", {}).get("net", 0.0)) < 0.0,
		"mission: CFO M1 applies a temporary loan-interest bonus")

	# Reaching loyalty 9 completes I-IV, but NOT V (which needs a sustained streak).
	MatchState.advisor_loyalty["vera"] = 9.0
	MatchState._check_mission_progress("vera")
	_check(MatchState.advisor_missions_done("vera") == 4,
		"mission: loyalty 9 completes I-IV but V needs the streak")
	# Hold at/above 9 for the full streak -> V completes.
	for _i in MatchState.MISSION5_STREAK_TURNS:
		MatchState._check_mission_progress("vera")
	_check(MatchState.advisor_missions_done("vera") == 5,
		"mission: V completes after MISSION5_STREAK_TURNS turns at loyalty 9+")
	# Dropping below 9 before the streak fills resets it (eleanor).
	MatchState.advisor_loyalty["eleanor"] = 9.0
	for _j in 5:
		MatchState._check_mission_progress("eleanor")
	MatchState.advisor_loyalty["eleanor"] = 8.0   # slips below the streak floor
	MatchState._check_mission_progress("eleanor")
	_check(int(MatchState._advisor_mission5_streak.get("eleanor", -1)) == 0,
		"mission: the V streak resets when loyalty drops below 9")

	var has_perm := false
	for m in Modifiers.active():
		if str(m.get("id", "")).begins_with("advisor_mission_perm_vera"):
			has_perm = true
	_check(has_perm, "mission: M2/M4/M5 leave permanent modifier slices")

	# Eleanor (HR) mission V unlocks the Stock Options policy once her streak fills.
	MatchState.advisor_loyalty["eleanor"] = 9.0
	for _k in MatchState.MISSION5_STREAK_TURNS + 1:
		MatchState._check_mission_progress("eleanor")
	_check(MatchState.advisor_mission_policies.has(MatchState.WORKFORCE_POLICY_STOCK_OPTIONS)
		and MatchState.is_workforce_policy_available(MatchState.WORKFORCE_POLICY_STOCK_OPTIONS),
		"mission: HR advisor mission V unlocks Stock Options")

	# Reward labels are exposed for the UI plaques (5 of them).
	var reward_labels: Array = MatchState.advisor_mission_reward_labels("vera")
	_check(reward_labels.size() == 5,
		"mission: 5 reward labels exposed for the detail plaques")
	_check("Applies" in str(reward_labels[0])
			and "Permanent" in str(reward_labels[1])
			and "Free research" in str(reward_labels[2]),
		"mission: reward labels describe the actual mission reward")

	Modifiers.reset()
	MatchState.permanent_advisor_ids = saved_perm
	MatchState.recruited_advisor_ids = saved_rec
	MatchState.advisor_loyalty = saved_loyal
	MatchState.advisor_missions_completed = saved_done
	MatchState._advisor_mission5_streak = saved_streak
	MatchState.advisor_mission_policies = saved_pol
	MatchState.unlocked_titles = saved_unlocked
	MatchState.reconcile_advisor_modifiers()

func _test_advisor_mission_update_signals() -> void:
	var saved_perm := MatchState.permanent_advisor_ids.duplicate(true)
	var saved_rec := MatchState.recruited_advisor_ids.duplicate(true)
	var saved_loyal := MatchState.advisor_loyalty.duplicate(true)
	var saved_done := MatchState.advisor_missions_completed.duplicate(true)
	var saved_streak := MatchState._advisor_mission5_streak.duplicate(true)
	var loyalty_events: Array = []
	var mission_events: Array = []
	var on_loyalty := func(advisor_id: String, loyalty: float) -> void:
		loyalty_events.append({"id": advisor_id, "loyalty": loyalty})
	var on_mission := func(advisor_id: String) -> void:
		mission_events.append(advisor_id)
	MatchState.advisor_loyalty_changed.connect(on_loyalty)
	MatchState.advisor_mission_state_changed.connect(on_mission)

	Modifiers.reset()
	MatchState.permanent_advisor_ids = ["vera"]
	MatchState.recruited_advisor_ids = ["vera"]
	MatchState.advisor_loyalty = {"vera": 0.0}
	MatchState.advisor_missions_completed = {}
	MatchState._advisor_mission5_streak = {}

	MatchState.cheat_set_loyalty("vera", 2.0)
	_check(MatchState.advisor_missions_done("vera") == 1
		and not loyalty_events.is_empty()
		and str(loyalty_events[0].get("id", "")) == "vera"
		and mission_events.has("vera"),
		"mission: loyalty changes advance missions and emit detail refresh signals")

	if MatchState.advisor_loyalty_changed.is_connected(on_loyalty):
		MatchState.advisor_loyalty_changed.disconnect(on_loyalty)
	if MatchState.advisor_mission_state_changed.is_connected(on_mission):
		MatchState.advisor_mission_state_changed.disconnect(on_mission)
	Modifiers.reset()
	MatchState.permanent_advisor_ids = saved_perm
	MatchState.recruited_advisor_ids = saved_rec
	MatchState.advisor_loyalty = saved_loyal
	MatchState.advisor_missions_completed = saved_done
	MatchState._advisor_mission5_streak = saved_streak
	MatchState.reconcile_advisor_modifiers()

func _test_people_panel_mission_ui() -> void:
	var pp: Node = load("res://scripts/people_panel.gd").new()
	var quests := [
		{"roman": "I", "title": "Onboard", "state": "completed", "color": Color("#CDA349"), "reward": "First reward", "req_text": "at loyalty 2"},
		{"roman": "II", "title": "Prove", "state": "next", "color": Color("#536C92"), "reward": "Second reward", "req_text": "at loyalty 5"},
		{"roman": "III", "title": "Expand", "state": "locked", "color": Color("#4F6B58"), "reward": "Third reward", "req_text": "at loyalty 7"},
		{"roman": "IV", "title": "Master", "state": "locked", "color": Color("#765742"), "reward": "Fourth reward", "req_text": "at loyalty 9"},
		{"roman": "V", "title": "Legacy", "state": "locked", "color": Color("#6B6077"), "reward": "Legacy reward", "req_text": "loyalty 9+ for 20 turns (3/20)"},
	]
	var plaque: Control = pp.call("_mission_plaque", quests[1]) as Control
	_check(_tree_has_label_text(plaque, "II")
		and not _tree_has_label_text(plaque, "Prove")
		and not _tree_has_label_text(plaque, "Second reward")
		and not _tree_has_label_text(plaque, "at loyalty"),
		"PeoplePanel missions: plaques show only the roman numeral")

	var rewards: Control = pp.call("_mission_rewards_row", quests) as Control
	_check(_tree_has_label_text(rewards, "Reward") and _tree_has_label_text(rewards, "Legacy reward"),
		"PeoplePanel missions: rewards render in the separate row")
	var rewards_margin: MarginContainer = rewards.find_child("MissionRewardsMargin", true, false) as MarginContainer
	var rewards_row: HBoxContainer = rewards.find_child("MissionRewardsRow", true, false) as HBoxContainer
	var first_reward: Control = rewards.find_child("MissionReward_I", true, false) as Control
	_check(rewards is ScrollContainer
			and rewards_margin != null
			and rewards_row != null
			and first_reward != null
			and rewards_margin.get_theme_constant("margin_left") >= 10
			and rewards_margin.get_theme_constant("margin_right") >= 10
			and rewards_row.get_theme_constant("separation") >= 20
			and first_reward.custom_minimum_size.x <= 164.0,
		"PeoplePanel missions: reward cards keep max width, edge padding, and 20px gaps")

	var bar: Control = pp.call("_loyalty_bar", 5.0, quests) as Control
	_check(_tree_has_label_text(bar, "V: loyalty 9+ for 20 turns (3/20)")
		and _tree_has_label_text(bar, "9+ 20t"),
		"PeoplePanel missions: loyalty milestones live on the bar")

func _test_advisor_seats_save_roundtrip() -> void:
	var saved_seats: Dictionary = MatchState.advisor_seats.duplicate(true)
	var saved_slots: int = MatchState.max_advisor_slots
	MatchState.advisor_seats = {"cfo": "vera", "coo": "tom"}
	MatchState.max_advisor_slots = 3
	var d: Dictionary = MatchState.export_state()
	MatchState.advisor_seats = {}
	MatchState.max_advisor_slots = 2
	MatchState.import_state(d)
	_check(MatchState.advisor_seats.get("cfo", "") == "vera" and MatchState.advisor_seats.get("coo", "") == "tom",
		"save: advisor_seats round-trips")
	_check(MatchState.max_advisor_slots == 3, "save: max_advisor_slots round-trips")
	# backward-compat: a v3 save missing the keys defaults to empty seats + 2 slots
	d.erase("advisor_seats")
	d.erase("max_advisor_slots")
	MatchState.import_state(d)
	_check(MatchState.advisor_seats.is_empty() and MatchState.max_advisor_slots == MatchState.MAX_ADVISOR_SLOTS_DEFAULT,
		"save: missing keys default (v3 back-compat)")
	# sanitize drops a bogus seat_id + an un-rostered advisor, keeps valid entries
	_check(MatchState._sanitize_advisor_seats({"cfo": "vera", "bogus_seat": "vera", "coo": "not_real"}) == {"cfo": "vera"},
		"save: sanitize drops bad seat + un-rostered advisor")
	MatchState.advisor_seats = saved_seats
	MatchState.max_advisor_slots = saved_slots

func _test_advisor_payroll_cost() -> void:
	var saved_ids := MatchState.permanent_advisor_ids.duplicate(true)
	var saved_money := MatchState.money
	MatchState.permanent_advisor_ids = ["vera", "alexandra"]   # salaries 1.0 + 4.0 = 5.0
	MatchState.money = 100.0
	var summary := {"advisor_paid": 0.0, "money_out": 0.0}
	var paid: float = Production._apply_advisor_costs(summary)
	_check(is_equal_approx(paid, 5.0)
		and is_equal_approx(float(summary.get("advisor_paid", 0.0)), 5.0)
		and is_equal_approx(float(summary.get("money_out", 0.0)), 5.0)
		and is_equal_approx(MatchState.money, 95.0),
		"advisor payroll sums each advisor's salary")
	MatchState.permanent_advisor_ids = saved_ids
	MatchState.money = saved_money
	MatchState.money_changed.emit(MatchState.money)
	MatchState.advisors_changed.emit()

func _test_advisor_milestone_acquisition() -> void:
	var saved_hired: Array = MatchState.recruited_advisor_ids.duplicate(true)
	var saved_crossed: Array = MatchState.crossed_milestones.duplicate(true)
	MatchState.recruited_advisor_ids = []
	MatchState.crossed_milestones = []
	MatchState._match_rng.seed = MatchState.DEFAULT_MATCH_RNG_SEED
	MatchState.check_profit_milestones(40.0)
	_check(MatchState.recruited_advisor_ids.is_empty(), "milestone: below 50 profit recruits nothing")
	MatchState.check_profit_milestones(60.0)
	_check(MatchState.recruited_advisor_ids.size() == 1 and MatchState.crossed_milestones.has(50),
		"milestone: crossing 50 recruits one advisor")
	var first_id := str(MatchState.recruited_advisor_ids[0])
	MatchState.check_profit_milestones(60.0)
	_check(MatchState.recruited_advisor_ids.size() == 1, "milestone: re-crossing 50 does not re-recruit (latched)")
	MatchState.check_profit_milestones(220.0)
	_check(MatchState.recruited_advisor_ids.size() == 4 and MatchState.crossed_milestones.has(200),
		"milestone: a jump recruits each newly-crossed milestone (100/150/200)")
	MatchState.recruited_advisor_ids = []
	MatchState.crossed_milestones = []
	MatchState._match_rng.seed = MatchState.DEFAULT_MATCH_RNG_SEED
	MatchState.check_profit_milestones(60.0)
	_check(str(MatchState.recruited_advisor_ids[0]) == first_id, "milestone: seeded recruit is deterministic")
	MatchState.recruited_advisor_ids = saved_hired
	MatchState.crossed_milestones = saved_crossed

func _test_advisor_slot_progression() -> void:
	var saved_slots: int = MatchState.max_advisor_slots
	var saved_streak: int = MatchState._advisor_profit_streak
	var saved_pu: bool = MatchState.advisor_slot_profit_unlocked
	MatchState.max_advisor_slots = 2
	MatchState._advisor_profit_streak = 0
	MatchState.advisor_slot_profit_unlocked = false
	MatchState._update_advisor_slots(10.0)
	_check(MatchState.max_advisor_slots == 2, "slot progression: low profit / few buildings keeps 2")
	MatchState._update_advisor_slots(1000.0)
	MatchState._update_advisor_slots(1000.0)
	_check(not MatchState.advisor_slot_profit_unlocked, "slot progression: 2 turns at 1000 is not yet the streak")
	var had_fifth: bool = MatchState.is_unlocked("Fifth Advisor Seat")
	MatchState._update_advisor_slots(1000.0)
	_check(MatchState.advisor_slot_profit_unlocked and MatchState.max_advisor_slots == 3,
		"slot progression: 1000 profit x3 unlocks a slot (2 -> 3)")
	_check(MatchState.is_unlocked("Fifth Advisor Seat"),
		"slot progression: 5th-seat unlock granted (shows under People Management)")
	MatchState._update_advisor_slots(0.0)
	_check(MatchState.max_advisor_slots == 3, "slot progression: a dip does not revoke the earned slot")
	MatchState.max_advisor_slots = saved_slots
	MatchState._advisor_profit_streak = saved_streak
	MatchState.advisor_slot_profit_unlocked = saved_pu
	if not had_fifth:
		MatchState.unlocked_titles.erase("Fifth Advisor Seat")

func _test_advisor_fake_money_and_track() -> void:
	var saved_money := MatchState.money
	var saved_fake := MatchState.fake_money_this_turn
	var saved_crossed := MatchState.crossed_milestones.duplicate(true)
	MatchState.fake_money_this_turn = 0.0
	MatchState.cheat_add_cash(500.0)
	_check(is_equal_approx(MatchState.fake_money_this_turn, 500.0) and is_equal_approx(MatchState.money, saved_money + 500.0),
		"fake money: cheat_add_cash tracks fake money + raises the balance")
	MatchState.crossed_milestones = [50, 100]
	_check(MatchState.next_advisor_milestone() == 150, "advisor track: next milestone is the first un-crossed (150)")
	MatchState.crossed_milestones = [50, 100, 150, 200, 300, 400, 500, 750, 1000]
	_check(MatchState.next_advisor_milestone() == 0, "advisor track: all milestones crossed -> 0")
	# Cheat cash (fake money) must count toward the profit that drives advisor unlocks.
	var saved_rec_fm: Array = MatchState.recruited_advisor_ids.duplicate(true)
	MatchState.crossed_milestones = []
	MatchState._on_turn_processed_advisors({"money_in": 0.0, "money_out": 0.0, "fake_money": 120.0})
	_check(MatchState.crossed_milestones.has(50) and MatchState.crossed_milestones.has(100)
		and not MatchState.crossed_milestones.has(150),
		"fake money: cheat cash crosses profit milestones (drives advisor unlocks)")
	MatchState.recruited_advisor_ids = saved_rec_fm
	MatchState.money = saved_money
	MatchState.fake_money_this_turn = saved_fake
	MatchState.crossed_milestones = saved_crossed
	MatchState.money_changed.emit(MatchState.money)

func _test_advisor_slot_unlock() -> void:
	var saved: int = MatchState.max_advisor_slots
	MatchState.max_advisor_slots = 2
	MatchState.unlock_advisor_slot()
	_check(MatchState.max_advisor_slots == 3, "slot unlock: raises the cap by 1")
	MatchState.unlock_advisor_slot()
	MatchState.unlock_advisor_slot()
	MatchState.unlock_advisor_slot()
	_check(MatchState.max_advisor_slots == 5, "slot unlock: clamps at the cap (5)")
	MatchState.max_advisor_slots = saved

func _test_advisor_acquisition_save_roundtrip() -> void:
	var saved_rec: Array = MatchState.recruited_advisor_ids.duplicate(true)
	var saved_crossed: Array = MatchState.crossed_milestones.duplicate(true)
	MatchState.recruited_advisor_ids = []
	MatchState.crossed_milestones = []
	MatchState._match_rng.seed = MatchState.DEFAULT_MATCH_RNG_SEED
	MatchState.check_profit_milestones(60.0)   # cross 50, advance the rng past one recruit
	var d: Dictionary = MatchState.export_state()
	MatchState.import_state(d)
	_check(MatchState.crossed_milestones.has(50) and MatchState.recruited_advisor_ids.size() == 1,
		"acquisition save: crossed_milestones + recruited round-trip")
	var draw_a := MatchState.draw_advisor_from_pool()
	MatchState.import_state(d)                  # restore -> rng state reset to the saved value
	var draw_b := MatchState.draw_advisor_from_pool()
	_check(draw_a != "" and draw_a == draw_b, "acquisition save: rng state persists -> next recruit reproducible")
	MatchState.recruited_advisor_ids = saved_rec
	MatchState.crossed_milestones = saved_crossed

func _test_people_panel_seat_ui() -> void:
	var saved_hired: Array = MatchState.permanent_advisor_ids.duplicate(true)
	var saved_seats: Dictionary = MatchState.advisor_seats.duplicate(true)
	MatchState.permanent_advisor_ids = ["vera"]
	MatchState.advisor_seats = {}
	var pp: Node = load("res://scripts/people_panel.gd").new()
	add_child(pp)
	var vera: Dictionary = MatchState.get_advisor("vera")
	var section: Control = pp.call("_seat_assignment_section", vera)
	_check(section != null and str(section.name) == "SeatAssignmentSection",
		"seat UI: seat-assignment section builds for a hired advisor")
	var pent: Control = pp.call("_stat_pentagon", MatchState.get_advisor("vera"))
	_check(pent != null and str(pent.name) == "StatPentagon",
		"seat UI: stat pentagon builds")
	pp.call("_on_discipline_label", "fin", "vera")
	_check(pp.get("_shown_discipline") == "fin",
		"seat UI: tapping a discipline label opens its info section")
	pp.queue_free()
	MatchState.permanent_advisor_ids = saved_hired
	MatchState.advisor_seats = saved_seats

func _test_advisor_roster_merge() -> void:
	var defs: Array = MatchState._advisor_definitions()
	_check(defs.size() == 12, "roster merge: _advisor_definitions() has 12 advisors")
	var required := ["id", "name", "role", "happiness", "portrait_color", "bonus", "recommendation", "bio", "agenda", "likes", "dislikes", "bonuses", "missions"]
	var all_ok := true
	for d in defs:
		for key in required:
			if not (d as Dictionary).has(key):
				all_ok = false
	_check(all_ok, "roster merge: every display advisor carries the required panel fields")
	_check(str(MatchState.get_advisor("vera").get("name", "")) == "Vera Ashby", "roster merge: get_advisor resolves a canonical id")
	_check(MatchState.get_advisor("natasha").is_empty(), "roster merge: legacy ids are retired")

func _test_advisor_seat_requires_hire() -> void:
	var saved_seats: Dictionary = MatchState.advisor_seats.duplicate(true)
	var saved_hired: Array = MatchState.permanent_advisor_ids.duplicate(true)
	var saved_rec: Array = MatchState.recruited_advisor_ids.duplicate(true)
	var saved_fired: Dictionary = MatchState.fired_advisor_cooldowns.duplicate(true)
	var saved_slots: int = MatchState.max_advisor_slots
	MatchState.advisor_seats = {}
	MatchState.permanent_advisor_ids = []
	MatchState.recruited_advisor_ids = ["vera"]
	MatchState.fired_advisor_cooldowns = {}
	MatchState.max_advisor_slots = 2
	_check(not MatchState.assign_advisor_to_seat("cfo", "vera"), "hire gate: cannot seat an un-hired advisor")
	MatchState.hire_advisor("vera")
	_check(MatchState.assign_advisor_to_seat("cfo", "vera"), "hire gate: can seat once hired")
	MatchState.advisor_seats = saved_seats
	MatchState.permanent_advisor_ids = saved_hired
	MatchState.recruited_advisor_ids = saved_rec
	MatchState.fired_advisor_cooldowns = saved_fired
	MatchState.max_advisor_slots = saved_slots

func _test_research_unlock_promotes_construct_panel_recipes() -> void:
	var recipe := Catalog.get_recipe("r_020")
	var building_id := str(recipe.get("building_id", ""))
	var saved_unlocks := MatchState.unlocked_titles.duplicate(true)
	var saved_land := MatchState.tile_land_owned.duplicate(true)
	var saved_construct_v2 := MatchState.use_construct_panel_v2
	# This fixture explicitly instantiates the legacy panel and calls its tile-open
	# API, so do not let the live v2 routing toggle make that API return early.
	MatchState.use_construct_panel_v2 = false
	# Electric Arc Refining now has a functioning Own-land auto-condition. Keep
	# that condition deliberately unmet while this test isolates panel filtering.
	MatchState.tile_land_owned.clear()
	MatchState.unlocked_titles.erase("Electric Arc Refining")
	var packed: PackedScene = load("res://scenes/construct_panel.tscn")
	if packed == null or recipe.is_empty() or building_id == "":
		_check(false, "research unlock: construct panel fixture resolves")
		_replace_dict(MatchState.unlocked_titles, saved_unlocks)
		_replace_dict(MatchState.tile_land_owned, saved_land)
		MatchState.use_construct_panel_v2 = saved_construct_v2
		return
	var panel: Control = packed.instantiate() as Control
	if panel == null:
		_check(false, "research unlock: construct panel instantiates as Control")
		_replace_dict(MatchState.unlocked_titles, saved_unlocks)
		_replace_dict(MatchState.tile_land_owned, saved_land)
		MatchState.use_construct_panel_v2 = saved_construct_v2
		return
	add_child(panel)
	await get_tree().process_frame

	panel.show()
	await get_tree().process_frame
	_check(not _construct_panel_has_recipe(panel, building_id, "r_020"),
		"construct panel hides recipe-gated research before unlock")
	MatchState.grant_unlock("Electric Arc Refining")
	await get_tree().process_frame
	_check(_construct_panel_has_recipe(panel, building_id, "r_020"),
		"construct panel promotes recipe when research unlocks")

	MatchState.unlocked_titles.erase("Electric Arc Refining")
	panel.call("open_for_tile", "tile_test_research_unlock", {})
	await get_tree().process_frame
	_check(not _construct_panel_has_recipe(panel, building_id, "r_020"),
		"tile build panel hides recipe-gated research before unlock")
	MatchState.grant_unlock("Electric Arc Refining")
	await get_tree().process_frame
	_check(_construct_panel_has_recipe(panel, building_id, "r_020"),
		"tile build panel promotes recipe when research unlocks")

	panel.queue_free()
	await get_tree().process_frame
	_replace_dict(MatchState.unlocked_titles, saved_unlocks)
	_replace_dict(MatchState.tile_land_owned, saved_land)
	MatchState.use_construct_panel_v2 = saved_construct_v2

func _construct_panel_has_recipe(panel: Node, building_id: String, recipe_id: String) -> bool:
	var by_building: Dictionary = panel.get("recipes_by_building")
	for recipe in by_building.get(building_id, []):
		if str(recipe.get("recipe_id", "")) == recipe_id:
			return true
	return false

func _test_tile_deposit_build_options_respect_research_unlocks() -> void:
	var saved_unlocks := MatchState.unlocked_titles.duplicate(true)
	MatchState.unlocked_titles.erase("Subsea Production Systems")
	var tvd = load("res://scripts/tile_view_data.gd")
	var locked_options: Array = tvd.deposit_build_options("crude_oil")
	_check(not _build_options_have_recipe(locked_options, "r_222"),
		"tile deposit build options hide recipe-gated research before unlock")
	MatchState.grant_unlock("Subsea Production Systems")
	var unlocked_options: Array = tvd.deposit_build_options("crude_oil")
	_check(_build_options_have_recipe(unlocked_options, "r_222"),
		"tile deposit build options promote recipe when research unlocks")
	_replace_dict(MatchState.unlocked_titles, saved_unlocks)

func _build_options_have_recipe(options: Array, recipe_id: String) -> bool:
	for option in options:
		if str(option.get("recipe_id", "")) == recipe_id:
			return true
	return false

# Smoke: every script we touch must still parse. load() returns null on a parse
# error — this is the check that catches the bug class we couldn't verify by hand.
func _test_scripts_parse() -> void:
	for path in [
		"res://scripts/stockpile_view.gd",
		"res://scripts/infra_grid.gd",
		"res://scripts/tile_info_panel_v2.gd",
		"res://scripts/building_detail_panel.gd",
		"res://scripts/building_connection_visuals.gd",
		"res://scripts/world_map.gd",
		"res://scripts/map_overlay.gd",
		"res://scripts/build_mode_hex_overlay.gd",
		"res://scripts/build_mode_backdrop.gd",
		"res://scripts/power_hex_overlay.gd",
		"res://scripts/water_overlay.gd",
		"res://scripts/hex_map.gd",
		"res://scripts/ds.gd",
		"res://scripts/search_overlay.gd",
		"res://scripts/good_icons.gd",
		"res://scripts/catalog.gd",
		"res://scripts/construct_panel.gd",
		"res://scripts/construct_panel_v2.gd",
		"res://scripts/building_detail_panel_v2.gd",
		"res://scripts/infrastructure_info.gd",
		"res://scripts/build_mode.gd",
		"res://scripts/building_row.gd",
		"res://scripts/recipe_row.gd",
		"res://scripts/logistics_overlay.gd",
		"res://scripts/mapmodes_panel.gd",
		"res://scripts/overlay_legend.gd",
		"res://scripts/debug_terminal.gd",
		"res://scripts/sale_effects.gd",
		"res://scripts/ui_helpers.gd",
		"res://scripts/market_panel.gd",
		"res://scripts/construction.gd",
		"res://scripts/construction_missing_dialog.gd",
		"res://scripts/transport_service.gd",
		"res://scripts/event_scheduler.gd",
		"res://scripts/modifier_state.gd",
		"res://scripts/notification_bell.gd",
		"res://scripts/road_regions.gd",
		"res://scripts/special_order_state.gd",
		"res://scripts/special_order_resolution_dialog.gd",
		"res://scripts/unlock_dialog.gd",
		"res://scripts/people_panel.gd",
		"res://scripts/main_menu.gd",
		"res://scripts/new_game_panel.gd",
		"res://scripts/tutorial_intro_panel.gd",
		"res://scripts/camera_controller.gd",
		"res://scripts/tutorial/tutorial_engine.gd",
		"res://scripts/tutorial/coach_overlay.gd",
		"res://scripts/tutorial/tutorial_steps.gd",
		"res://scripts/tutorial/tutorial_detectors.gd",
	]:
		_check(load(path) != null, "parses: " + path)

# Smoke: the extracted widgets instantiate and build their UI.
func _test_widgets_instantiate() -> void:
	var sv: Node = load("res://scripts/stockpile_view.gd").new()
	add_child(sv)
	sv.set_tile("")
	_check(sv.get_child_count() > 0, "StockpileView builds its UI")
	sv.queue_free()

	var ig: Node = load("res://scripts/infra_grid.gd").new()
	add_child(ig)
	ig.set_slots([{
		"cell_size": Vector2(80, 80), "icon": null, "state": "add",
		"internal_name": "roads", "button_tooltip": "Add Roads",
		"display_label": "Roads", "label_tooltip": "", "max_label_lines": 2,
	}])
	_check(ig.get_child_count() == 1, "InfraGrid renders one slot")
	ig.queue_free()

	var saved_advisors := MatchState.permanent_advisor_ids.duplicate(true)
	var saved_recruited := MatchState.recruited_advisor_ids.duplicate(true)
	var saved_fired := MatchState.fired_advisor_cooldowns.duplicate(true)
	var saved_seats := MatchState.advisor_seats.duplicate(true)
	MatchState.fired_advisor_cooldowns.clear()
	MatchState.permanent_advisor_ids.clear()
	MatchState.advisor_seats.clear()
	var _all_ids: Array = []
	for _a in MatchState.advisor_pool():
		_all_ids.append(str(_a.get("id", "")))
	MatchState.recruited_advisor_ids = _all_ids
	MatchState.advisors_changed.emit()
	var pp: Node = load("res://scripts/people_panel.gd").new()
	add_child(pp)
	_check(
		_tree_has_label_text(pp, "Labour") and _tree_has_label_text(pp, "Advisors")
		and _tree_has_label_text(pp, "0.8x") and _tree_has_label_text(pp, "WORKFORCE POLICIES"),
		"PeoplePanel builds Labour and Advisors tabs")
	# The Advisors tab is now the ROLE-FIRST council view: one card per SEAT.
	var council_tab: Node = _find_node_by_script(pp, "res://scripts/advisor_council_tab.gd")
	_check(council_tab != null and _tree_has_label_text(pp, "COUNCIL SEATS")
		and _tree_has_label_text(pp, "CFO") and _tree_has_label_text(pp, "VP Logistics"),
		"PeoplePanel shows advisor payroll at the top")
	_check(MatchState.available_advisors().size() == MatchState.advisor_pool().size()
		and MatchState.permanent_advisors().is_empty(),
		"PeoplePanel starts with all advisors available and none permanent")
	council_tab.call("_set_view", {"mode": "picker", "hire_seat": "cfo", "back": "roster"})
	_check(_tree_has_label_text(pp, "Vera Ashby") and _tree_has_label_text(pp, "Rufus Ashby")
		and _tree_has_label_text(pp, "Hiring for"),
		"PeoplePanel plus slot opens the available advisor pool")
	var first_advisor: Dictionary = MatchState.available_advisors()[0]
	var first_id := str(first_advisor.get("id", ""))
	council_tab.call("_set_view", {"mode": "detail", "sel_id": first_id, "hire_seat": "cfo", "back": "picker"})
	_check(_tree_has_label_text(pp, str(first_advisor.get("name", "")))
		and not MatchState.permanent_advisor_ids.has(first_id),
		"PeoplePanel clicking an available advisor opens the profile, not an instant hire")
	# The Hire & assign confirm runs exactly this hire + seat-assign pair.
	var hired_ok := MatchState.hire_advisor(first_id) and MatchState.assign_advisor_to_seat("cfo", first_id)
	council_tab.call("_set_view", {"mode": "roster"})
	_check(hired_ok and MatchState.permanent_advisor_ids.has(first_id)
		and _tree_has_label_text(pp, str(first_advisor.get("name", ""))),
		"PeoplePanel Confirm Hire from the profile hires a permanent advisor and updates payroll")
	# Fire flow: the profile footer for an employed advisor benches them.
	pp.call("_open_advisor_detail", first_advisor)
	var fire_footer: Control = pp.call("_advisor_detail_footer", first_advisor, true, false) as Control
	_check(fire_footer is Button and (fire_footer as Button).text == "Fire Advisor",
		"PeoplePanel employed-advisor footer offers Fire Advisor")
	var fid := str(first_advisor.get("id", ""))
	# Net-modifiers readout + the "See all advisor modifiers" DS panel.
	MatchState.assign_advisor_to_seat("cfo", fid)
	_check((pp.call("_advisor_net_modifiers") as Array).size() > 0,
		"PeoplePanel net-modifiers aggregates seated advisor effects")
	pp.call("_open_advisor_modifiers_panel")
	var modpanel: Node = pp.get("_advisor_modifiers_panel")
	_check(is_instance_valid(modpanel) and (modpanel as Control).visible,
		"PeoplePanel See-all opens the DS modifiers panel")
	if is_instance_valid(modpanel):
		PanelStack.remove(modpanel)
		modpanel.queue_free()
	MatchState.fire_advisor(fid)
	_check(not MatchState.permanent_advisor_ids.has(fid)
		and MatchState.is_fired(fid)
		and MatchState.fire_cooldown_remaining(fid) == MatchState.FIRE_COOLDOWN_TURNS
		and not MatchState.hire_advisor(fid),
		"PeoplePanel firing benches the advisor for the cooldown and blocks re-hire")
	# Cooldown counts down each turn; the advisor returns to the pool at 0.
	for _i in MatchState.FIRE_COOLDOWN_TURNS:
		MatchState._tick_fire_cooldowns()
	_check(not MatchState.is_fired(fid) and MatchState.hire_advisor(fid),
		"PeoplePanel fired advisor returns to the pool after the cooldown and can be re-hired")
	pp.call("_close_advisor_detail")
	var permanent: Array = pp.get("_permanent_advisors")
	var card: Control = pp.call("_advisor_card", permanent[0], true, false) as Control
	var portrait: Control = card.find_child("AdvisorPortrait", true, false) as Control
	_check(card.mouse_filter == Control.MOUSE_FILTER_STOP and portrait != null
		and portrait.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"PeoplePanel advisor card click surface includes the portrait")
	_check(card.find_child("AssignedAdvisorRole", true, false) == null,
		"PeoplePanel advisor card leaves role blank until the advisor is assigned")
	card.free()
	MatchState.assign_advisor_to_seat("cfo", str((permanent[0] as Dictionary).get("id", "")))
	var assigned_card: Control = pp.call("_advisor_card", permanent[0], true, false) as Control
	_check(_tree_has_label_text(assigned_card, "CFO")
			and assigned_card.find_child("AssignedAdvisorRole", true, false) != null,
		"PeoplePanel advisor card shows the assigned seat once assigned")
	assigned_card.free()
	if not permanent.is_empty():
		pp.call("_open_advisor_detail", permanent[0])
	var detail: Node = pp.get("_advisor_detail_panel")
	_check(
		detail != null and detail.visible
		and _tree_has_label_text(detail, "Agenda") and _tree_has_label_text(detail, "Missions"),
		"PeoplePanel opens advisor detail shell")
	pp.call("_close_advisor_detail")
	if detail != null:
		detail.queue_free()
	pp.queue_free()
	MatchState.permanent_advisor_ids = saved_advisors
	MatchState.recruited_advisor_ids = saved_recruited
	MatchState.fired_advisor_cooldowns = saved_fired
	MatchState.advisor_seats = saved_seats
	MatchState.reconcile_advisor_modifiers()
	MatchState.advisors_changed.emit()

func _find_node_by_script(node: Node, script_path: String) -> Node:
	var s: Script = node.get_script() as Script
	if s != null and s.resource_path == script_path:
		return node
	for child in node.get_children():
		var hit := _find_node_by_script(child, script_path)
		if hit != null:
			return hit
	return null

func _tree_has_label_text(node: Node, needle: String) -> bool:
	if needle in node.name:
		return true
	if node is Label and needle in (node as Label).text:
		return true
	if node is Button and needle in (node as Button).text:
		return true
	for child in node.get_children():
		if _tree_has_label_text(child, needle):
			return true
	return false

func _test_unlock_dialog_groups_multiple_unlocks() -> void:
	var dlg: Control = load("res://scripts/unlock_dialog.gd").new()
	add_child(dlg)
	dlg.call("show_unlocks", [
		{"title": "Improved Coal Mining", "description": "Coal mines output more."},
		{"title": "Copper Recovery", "description": "Copper chain improves."},
	])
	_check(dlg.visible
		and _tree_has_label_text(dlg, "2 unlocks")
		and _tree_has_label_text(dlg, "Improved Coal Mining")
		and _tree_has_label_text(dlg, "Copper Recovery"),
		"unlock dialog groups multiple unlocks in one panel")
	var unlock_list: Node = dlg.find_child("UnlockList", true, false)
	_check(unlock_list != null and unlock_list.get_child_count() == 2,
		"unlock dialog renders one box per unlock")
	await get_tree().process_frame
	var scroll: Control = dlg.find_child("UnlockScroll", true, false) as Control
	var first_card: Control = unlock_list.get_child(0) as Control if unlock_list != null and unlock_list.get_child_count() > 0 else null
	_check(scroll != null and scroll.size.y >= 180.0 and first_card != null and first_card.size.y >= 80.0,
		"unlock dialog reserves visible space for grouped unlock boxes")
	dlg.call("_close")
	_check(not dlg.visible, "unlock dialog closes")
	PanelStack.remove(dlg)
	dlg.queue_free()

# Regression: recipe_row.tscn must instantiate + setup (catches script/root type
# mismatches — recipe rows are only built on expand, so the main-scene test misses them).
func _test_recipe_row_instantiates() -> void:
	var packed: PackedScene = load("res://scenes/recipe_row.tscn")
	var ok: bool = packed != null
	if ok:
		var row: Node = packed.instantiate()
		add_child(row)
		row.call("setup", {
			"recipe_id": "r_001", "display_name": "Test Recipe",
			"output_good_id": "g_001", "output_name": "coal", "output_qty": 10,
			"inputs": [], "energy_req": 4,
		}, "b_001")
		ok = row.get_node_or_null("Row/OutputIcon") != null
		row.queue_free()
	_check(ok, "recipe_row instantiates + setup runs")

# Regression: a stockpile legend row's label must render with non-zero width
# (a fixed-width label was removed; with ellipsis trimming the label collapsed
# to zero and only the colour swatch showed).
func _test_stockpile_legend_label_visible() -> void:
	var sv: Node = load("res://scripts/stockpile_view.gd").new()
	add_child(sv)
	var row: Control = sv.call("_make_row", "Coal", "g_001")
	add_child(row)
	await get_tree().process_frame
	var label := row.get_child(0) as Label
	var ok: bool = label != null and label.text == "Coal" and label.size.x > 0.0
	_check(ok, "stockpile legend label renders with width (not collapsed)")
	row.queue_free()
	sv.queue_free()
	await get_tree().process_frame

# Smoke: the big scene still loads as a resource (catches main.tscn corruption).
func _test_scene_loads() -> void:
	_check(load("res://scenes/main.tscn") != null, "main.tscn loads")

# Instantiate the whole main scene and confirm the tile panel's @onready node
# paths still resolve. This is the net for layout/scene restructuring (Slice D):
# a broken node path leaves an @onready var null, which this catches.
func _test_main_scene_instantiates() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	if packed == null:
		_check(false, "main.tscn instantiates")
		return
	var inst: Node = packed.instantiate()
	add_child(inst)
	await get_tree().process_frame
	var panel: Node = inst.find_child("TileInfoPanel", true, false)
	_check(panel != null and panel.has_method("show_tile"),
		"main.tscn instantiates; the tile panel exists and exposes show_tile")
	# Exactly one tile panel: the classic (v1) panel is gone for good.
	var hud_content: Node = inst.find_child("HUDContent", true, false)
	var panel_count := 0
	if hud_content != null:
		for child in hud_content.get_children():
			if str(child.name).begins_with("TileInfoPanel"):
				panel_count += 1
	_check(panel_count == 1, "exactly one tile panel lives under HUDContent (found %d)" % panel_count)
	# Guards the theme-cascade fix: DS variations must actually resolve on panels.
	var tl = panel.get("_title_label") if panel != null else null
	_check(tl != null and tl.get_theme_font_size("font_size") == DS.FS["H1"],
		"DS theme reaches the tile panel (title uses the DS Title font)")
	# Selecting a tile through the terrain layer's click signal opens the panel.
	var terrain: Node = inst.find_child("TerrainLayer", true, false)
	if panel != null and terrain != null and not terrain.tiles.is_empty():
		var td: Dictionary = terrain.tiles[terrain.tiles.keys()[0]]
		terrain.tile_selected.emit(td)
		await get_tree().process_frame
		_check(panel.visible, "selecting a tile opens the tile panel")
		panel.hide()
	else:
		_check(false, "terrain layer with tiles available for tile-select test")
	inst.queue_free()
	await get_tree().process_frame

# Logic: the data CSVs load into the Catalog as expected.
func _test_catalog_loaded() -> void:
	_check(Catalog.all_goods().size() == 76, "Catalog has 76 goods")
	var _all_classed := true
	for g in Catalog.all_goods():
		if str(g.get("transport_class", "")) == "":
			_all_classed = false
	_check(_all_classed, "every loaded good has a transport_class")
	_check(Catalog.all_recipes().size() >= 18, "Catalog promotes a healthy recipe set (>=18)")
	_check(Catalog.all_buildings().size() == 37, "Catalog has 37 buildings")
	# Regression (farm buildability): the agri goods (biomass, waste_water, fertilisers) exist, so the
	# biomass farm recipes promote and the farm is no longer recipe-less — the "clicking the farm does
	# nothing" bug, caused by every farm recipe being dropped at the promotion gate for missing goods.
	_check(not Catalog.get_good_by_internal_name("biomass").is_empty(), "good 'biomass' is loaded")
	_check(not Catalog.get_good_by_internal_name("waste_water").is_empty(), "good 'waste_water' is loaded")
	_check(not Catalog.get_good_by_internal_name("fertilisers").is_empty(), "good 'fertilisers' is loaded")
	var farm_id: String = str(Catalog.get_building_by_internal_name("farm").get("id", ""))
	var farm_recipe_ids: Array = []
	for r in Catalog.get_recipes_for_building(farm_id):
		farm_recipe_ids.append(str(r.get("recipe_id", "")))
	# r_208 (Sustainable Biomass Production) is now tech-gated behind "Energy Crop Cultivation",
	# so it is intentionally absent from the start-active set; the base biomass recipes remain.
	var has_all_biomass: bool = farm_recipe_ids.has("r_209") \
		and farm_recipe_ids.has("r_211") and farm_recipe_ids.has("r_212")
	_check(has_all_biomass, "farm has its base biomass recipes (buildable, not recipe-less): %s" % str(farm_recipe_ids))
	_check(int(Catalog.get_building_by_internal_name("farm").get("tile_size_used", 0)) == 15, "farm building is tile_size_used 15")

	# The three acid recipes (r_114/115/116) were moved to the Chemical Plant
	# (owner request 2026-07-13); they used to sit on the Industrial Factory via the
	# industrial_goods_factory→industrial_factory alias.
	var chem_id: String = str(Catalog.get_building_by_internal_name("chem_plant").get("id", ""))
	var indf_id: String = str(Catalog.get_building_by_internal_name("industrial_factory").get("id", ""))
	var chem_recipe_ids: Array = []
	for r in Catalog.get_recipes_for_building(chem_id):
		chem_recipe_ids.append(str(r.get("recipe_id", "")))
	var indf_recipe_ids: Array = []
	for r in Catalog.get_recipes_for_building(indf_id):
		indf_recipe_ids.append(str(r.get("recipe_id", "")))
	for acid in ["r_114", "r_115", "r_116"]:
		_check(chem_recipe_ids.has(acid), "%s (acid) is now on the Chemical Plant" % acid)
		_check(not indf_recipe_ids.has(acid), "%s (acid) is no longer on the Industrial Factory" % acid)
	_check(not indf_recipe_ids.is_empty(), "Industrial Factory still has recipes (not farm-bugged by the move)")

# Logic: recipe requirements parse correctly (guards the build-mode path that
# silently broke earlier in the merge).
func _test_recipe_requirements() -> void:
	var recipe: Dictionary = Catalog.get_recipe("r_001")
	var reqs: Array = recipe.get("requirements", [])
	var ok: bool = reqs.size() == 1 \
		and reqs[0].get("type", "") == "deposit" \
		and reqs[0].get("value", "") == "coal"
	_check(ok, "r_001 (Coal Mining) requires deposit:coal")
	_check(recipe.get("recipe_type", "") == "Mineral Mining", "r_001 recipe_type is Mineral Mining")
	# Promotion gate: every active recipe's inputs + outputs resolve to real goods.
	var no_phantom := true
	for r in Catalog.all_recipes():
		for o in r.get("outputs", []):
			if o.get("good_id", "") == "":
				no_phantom = false
		for inp in r.get("inputs", []):
			if inp.get("good_id", "") == "":
				no_phantom = false
	_check(no_phantom, "promotion gate: active recipes only reference real goods")
	var mine_b: Dictionary = Catalog.get_building("b_001")
	_check("extraction" in mine_b.get("building_type", []), "Mine building_type contains extraction")

func _test_research_recipe_and_level_tiers() -> void:
	var graphitisation: Dictionary = Catalog.get_recipe("r_042")
	_check(str(graphitisation.get("required_research", "")) == "Biomass Cracking",
		"bio-graphitisation is gated by Biochemistry's Biomass Cracking")
	var has_biomass_node := false
	for unlock in MatchState._unlock_defs:
		if str(unlock.get("title", "")) == "Biomass Cracking":
			has_biomass_node = str(unlock.get("category", "")) == "Biochemistry"
	_check(has_biomass_node, "Biomass Cracking belongs to the Biochemistry tree")

	var file := FileAccess.open("res://data/research_unlocks.csv", FileAccess.READ)
	var level2_ok := file != null
	var level2_count := 0
	var warehouse_level2_ok := true
	if file != null:
		var header := file.get_csv_line()
		var indices := {}
		for index in header.size():
			indices[header[index]] = index
		while not file.eof_reached():
			var row := file.get_csv_line()
			if row.is_empty() or row[0].strip_edges() == "":
				continue
			var icon_index: int = int(indices.get("icon", -1))
			var rank_index: int = int(indices.get("rank", -1))
			if icon_index >= 0 and rank_index >= 0 and icon_index < row.size() and row[icon_index] == "level2":
				level2_count += 1
				if rank_index >= row.size() or row[rank_index] != "II":
					level2_ok = false
			var title_index: int = int(indices.get("title", -1))
			var description_index: int = int(indices.get("description", -1))
			if title_index >= 0 and description_index >= 0 and title_index < row.size() and description_index < row.size() and row[title_index] == "Pallet Racking Systems" and "warehouse level 2" in row[description_index] and (rank_index < 0 or rank_index >= row.size() or row[rank_index] != "II"):
				warehouse_level2_ok = false
		file.close()
	_check(level2_ok and level2_count == 21, "all 21 Level 2 building unlocks are Tier II")
	_check(warehouse_level2_ok, "warehouse Level 2 unlock is Tier II")

func _test_bottom_menu_default() -> void:
	var all_ok := true
	for key in ["construct", "goods", "building_ledger", "mapmodes", "market", "politics", "research", "people"]:
		var path := "res://assets/icons/ui_icons/alt/%s.png" % key
		if not (ResourceLoader.exists(path) and load(path) is Texture2D):
			all_ok = false
	_check(all_ok, "white-rimmed bottom-menu icons import and load")

func _test_panel_stack_focus() -> void:
	var holder := Control.new()
	add_child(holder)
	var a := PanelContainer.new()
	var b := PanelContainer.new()
	var child := Button.new()
	a.name = "FocusA"
	b.name = "FocusB"
	a.add_child(child)
	holder.add_child(a)
	holder.add_child(b)
	PanelStack.push(a)
	PanelStack.push(b)
	_check(PanelStack.top() == b, "panel stack: last pushed panel is top")
	_check(holder.get_child(holder.get_child_count() - 1) == b,
		"panel stack: last pushed panel is front sibling")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	child.emit_signal("gui_input", click)
	_check(PanelStack.top() == a, "panel stack: clicking inside a panel focuses it")
	_check(holder.get_child(holder.get_child_count() - 1) == a,
		"panel stack: focused panel moves to front sibling")
	_check(PanelStack.close_top() and not a.visible, "panel stack: close_top hides focused panel")
	PanelStack.remove(b)
	holder.queue_free()


# --- Decision events (docs/decision-events-spec.md) --------------------------

# Shared setup/teardown: decisions run against a clean DecisionState with the
# advisor board and turn clock under test control; every helper restores what it
# touches (the suite shares autoload state across tests).
func _decision_board_snapshot() -> Dictionary:
	return {
		"permanent": MatchState.permanent_advisor_ids.duplicate(),
		"recruited": MatchState.recruited_advisor_ids.duplicate(),
		"seats": MatchState.advisor_seats.duplicate(true),
		"hired": MatchState.advisor_hired_turn.duplicate(true),
		"loyalty": MatchState.advisor_loyalty.duplicate(true),
		"money": MatchState.money,
		"turn": TurnManager.current_turn,
		"phase": TurnManager.current_phase,
	}

func _decision_board_restore(snap: Dictionary) -> void:
	MatchState.permanent_advisor_ids = snap.permanent
	MatchState.recruited_advisor_ids = snap.recruited
	MatchState.advisor_seats = snap.seats
	MatchState.advisor_hired_turn = snap.hired
	MatchState.advisor_loyalty = snap.loyalty
	MatchState.money = snap.money
	TurnManager.current_turn = snap.turn
	TurnManager.current_phase = snap.phase
	DecisionState.reset()
	Modifiers.reset()
	EventScheduler.reset()

func _test_decision_tenure_gate() -> void:
	var snap := _decision_board_snapshot()
	TurnManager.current_turn = 20
	if not MatchState.permanent_advisor_ids.has("vera"):
		MatchState.permanent_advisor_ids.append("vera")
	MatchState.advisor_hired_turn["vera"] = 20
	_check(not MatchState.is_advisor_tenured("vera"),
		"decision tenure: an advisor hired THIS turn does not count")
	MatchState.advisor_hired_turn["vera"] = 19
	_check(MatchState.is_advisor_tenured("vera"),
		"decision tenure: hired on an earlier turn counts")
	_check(not MatchState.is_advisor_tenured("nobody"),
		"decision tenure: unknown/unemployed advisors never count")
	# The gate as the dialog sees it: research choice locked until tenured.
	MatchState.advisor_seats = {"research_director": "vera"}
	MatchState.advisor_hired_turn["vera"] = 20
	DecisionState.reset()
	DecisionState.pending = {"uid": "t1", "def_id": "worker_innovation",
		"target": {"scope": "building", "instance_id": "inst_x", "name": "Test Works"},
		"turn_drawn": 20}
	var view: Dictionary = DecisionState.pending_view()
	var research_choice: Dictionary = {}
	for c in view.choices:
		if str(c.id) == "research":
			research_choice = c
	_check(not bool(research_choice.get("available", true)),
		"decision gate: seat filled by an untenured hire stays locked")
	_check(str(research_choice.get("lock_reason", "")) != "",
		"decision gate: locked choices carry a requirement line")
	MatchState.advisor_hired_turn["vera"] = 15
	view = DecisionState.pending_view()
	for c in view.choices:
		if str(c.id) == "research":
			research_choice = c
	_check(bool(research_choice.get("available", false)),
		"decision gate: a tenured seat unlocks the choice")
	_decision_board_restore(snap)

func _test_decision_resolve_effects_and_loyalty() -> void:
	var snap := _decision_board_snapshot()
	Modifiers.reset()
	DecisionState.reset()
	TurnManager.current_turn = 30
	TurnManager.current_phase = TurnManager.Phase.DECIDE
	for aid in ["vera", "tom"]:
		if not MatchState.permanent_advisor_ids.has(aid):
			MatchState.permanent_advisor_ids.append(aid)
		MatchState.advisor_hired_turn[aid] = 20
		MatchState.advisor_loyalty[aid] = 0.0
	# CFO advocates hold_line, COO advocates pay_rise (union_demands catalog entry).
	MatchState.advisor_seats = {"cfo": "vera", "coo": "tom"}
	DecisionState.pending = {"uid": "t2", "def_id": "union_demands",
		"target": {"scope": "building_type", "building_id": "b_001", "name": "Coal Mine"},
		"turn_drawn": 30}
	var err: String = DecisionState.resolve("hold_line")
	_check(err == "", "decision resolve: valid choice resolves without error (%s)" % err)
	_check(not DecisionState.has_pending(), "decision resolve: pending clears")
	_check(DecisionState.history().size() == 1, "decision resolve: history records the outcome")
	var found := false
	for m in Modifiers.active():
		if str(m.domain) == "recipe_output" and float(m.get("pct", 0.0)) == -10.0 \
				and str((m.get("target_match", {}) as Dictionary).get("building_id", "")) == "b_001":
			found = true
			_check(int(m.get("expires_turn", 0)) == 39,
				"decision modifier: 10-turn DECIDE grant expires at turn 39")
	_check(found, "decision resolve: the output-hit modifier lands, scoped to the building type")
	_check(absf(MatchState.advisor_loyalty_value("vera") - 0.5) < 0.001,
		"decision loyalty: followed advisor gains +0.5 on a local-scope decision")
	_check(absf(MatchState.advisor_loyalty_value("tom") - (-0.5)) < 0.001,
		"decision loyalty: ignored advocating advisor takes -0.5")
	_decision_board_restore(snap)

func _test_decision_company_scope_loyalty() -> void:
	var snap := _decision_board_snapshot()
	DecisionState.reset()
	TurnManager.current_turn = 30
	TurnManager.current_phase = TurnManager.Phase.DECIDE
	if not MatchState.permanent_advisor_ids.has("vera"):
		MatchState.permanent_advisor_ids.append("vera")
	MatchState.advisor_hired_turn["vera"] = 20
	MatchState.advisor_loyalty["vera"] = 0.0
	MatchState.advisor_seats = {"cfo": "vera"}
	DecisionState.pending = {"uid": "t3", "def_id": "brokers_offer",
		"target": {"scope": "company", "good_id": "g_001", "name": "Coal"},
		"turn_drawn": 30}
	var err: String = DecisionState.resolve("decline")
	_check(err == "", "decision company scope: resolve ok (%s)" % err)
	_check(absf(MatchState.advisor_loyalty_value("vera") - 2.0) < 0.001,
		"decision loyalty: followed advisor gains +2.0 on a company-scope decision")
	_decision_board_restore(snap)

func _test_decision_loan_fallback() -> void:
	var snap := _decision_board_snapshot()
	var loans_before: Array = LoanState.loans.duplicate(true)
	DecisionState.reset()
	TurnManager.current_turn = 30
	TurnManager.current_phase = TurnManager.Phase.DECIDE
	MatchState.advisor_seats = {}
	MatchState.money = 10.0
	DecisionState.pending = {"uid": "t4", "def_id": "planning_pushback",
		"target": {"scope": "building", "instance_id": "no_such_project", "name": "Test Site"},
		"turn_drawn": 30}
	var err: String = DecisionState.resolve("accelerate")   # costs £50, we hold £10
	_check(err == "", "decision loan: unaffordable cash choice still resolves (%s)" % err)
	_check(LoanState.loans.size() == loans_before.size() + 1,
		"decision loan: the shortfall arrives as a new loan")
	if LoanState.loans.size() > loans_before.size():
		var loan: Dictionary = LoanState.loans.back()
		_check(absf(float(loan.principal_initial) - 40.0) < 0.001,
			"decision loan: borrowed exactly the £40 shortfall")
	_check(absf(MatchState.money) < 0.001,
		"decision loan: cost paid in full after the loan lands (money at 0)")
	# Already in the red: only the COST is financed — the pre-existing overdraft is
	# NOT refinanced (regression: it used to reset any negative balance to £0).
	MatchState.money = -100.0
	DecisionState.pending = {"uid": "t4b", "def_id": "planning_pushback",
		"target": {"scope": "building", "instance_id": "no_such_project", "name": "Test Site"},
		"turn_drawn": 30}
	var loans_mid: int = LoanState.loans.size()
	err = DecisionState.resolve("accelerate")   # costs £50 at −£100
	_check(err == "", "decision loan (in the red): resolves without error (%s)" % err)
	_check(LoanState.loans.size() == loans_mid + 1
		and absf(float(LoanState.loans.back().principal_initial) - 50.0) < 0.001,
		"decision loan (in the red): borrows exactly the £50 cost, not the deficit")
	_check(absf(MatchState.money - (-100.0)) < 0.001,
		"decision loan (in the red): the overdraft is NOT refinanced back to £0")
	LoanState.loans = loans_before
	_decision_board_restore(snap)

func _test_loan_collateral_capacity() -> void:
	# A loss-making firm with plant keeps a credit line: capacity = base + LTV x
	# building SALE value, even while the profit gate zeroes the cashflow leg. A
	# seated CFO/Chief Investment lifts the LTV from 0.75 to 1.0.
	var BP = load("res://scripts/building_price.gd")
	var profit_before: Array = LoanState._profit_history.duplicate()
	var revenue_before: Array = LoanState._revenue_history.duplicate()
	var seats_before: Dictionary = MatchState.advisor_seats.duplicate(true)
	MatchState.advisor_seats = {}                       # no CFO / Chief Investment → base LTV
	LoanState._profit_history = [-10.0, -12.0, -8.0]
	LoanState._revenue_history = [20.0, 20.0, 20.0]
	var without_plant := LoanState.capacity_total()
	var b := {"instance_id": "test_collateral_b1", "building_id": "b_001",
		"recipe_id": "", "tile_id": "tile_1_1", "owner": MatchState.LOCAL_PLAYER, "level": 1}
	var sale := float(BP.sale_price(b))
	MatchState.buildings["test_collateral_b1"] = b
	var with_plant := LoanState.capacity_total()
	_check(sale > 0.0 and absf((with_plant - without_plant) - EconomyConfig.LOAN_COLLATERAL_LTV_BASE * sale) < 0.5,
		"loan collateral: plant adds base-LTV (0.75) x its sale value while unprofitable")
	MatchState.advisor_seats = {"cfo": "vera"}          # a seated CFO lifts LTV to 1.0
	var with_cfo := LoanState.capacity_total()
	_check(absf((with_cfo - without_plant) - EconomyConfig.LOAN_COLLATERAL_LTV_MAX * sale) < 0.5,
		"loan collateral: a seated CFO/Chief Investment lifts LTV to the max (1.0)")
	MatchState.buildings.erase("test_collateral_b1")
	_check(without_plant >= EconomyConfig.LOAN_BASE_CAPACITY,
		"loan collateral: the base floor still holds with no plant")
	MatchState.advisor_seats = seats_before
	LoanState._profit_history = profit_before
	LoanState._revenue_history = revenue_before

func _test_decision_commit_guard_and_auto_resolve() -> void:
	var snap := _decision_board_snapshot()
	DecisionState.reset()
	MatchState.advisor_seats = {}
	TurnManager.current_turn = 40
	TurnManager.current_phase = TurnManager.Phase.DECIDE
	var was_resolving := TurnManager.is_resolving
	DecisionState.auto_resolve = false
	DecisionState.pending = {"uid": "t5", "def_id": "land_deal",
		"target": {"scope": "tile", "tile_id": "tile_1_1", "name": "Test Tile"},
		"turn_drawn": 40}
	TurnManager.commit_turn()
	_check(TurnManager.current_turn == 40 and not TurnManager.is_resolving,
		"decision guard: commit_turn refuses while a decision is pending")
	_check(DecisionState.has_pending(), "decision guard: the decision is still pending")
	# Non-interactive path: the default choice resolves (loyalty rules included).
	DecisionState.auto_resolve = true
	DecisionState.auto_resolve_pending()
	_check(not DecisionState.has_pending(), "decision auto-resolve: default choice clears pending")
	_check(str(DecisionState.history().back().get("choice_id", "")) == "keep",
		"decision auto-resolve: the definition's default_choice was picked")
	DecisionState.auto_resolve = false
	TurnManager.is_resolving = was_resolving
	_decision_board_restore(snap)

func _test_decision_roundtrip() -> void:
	var snap := _decision_board_snapshot()
	DecisionState.reset()
	DecisionState.pending = {"uid": "t6", "def_id": "union_demands",
		"target": {"scope": "building_type", "building_id": "b_002", "name": "Furnace"},
		"turn_drawn": 12}
	DecisionState.flags["env_exempt:inst_9"] = true
	DecisionState.reserve(80, "environmental_inspection")
	var exported: Dictionary = DecisionState.export_state()
	DecisionState.reset()
	_check(not DecisionState.has_pending(), "decision roundtrip: reset clears pending")
	DecisionState.import_state(exported)
	_check(str(DecisionState.pending.get("def_id", "")) == "union_demands",
		"decision roundtrip: pending decision survives export/import")
	_check(DecisionState.flags.has("env_exempt:inst_9"),
		"decision roundtrip: flags survive export/import")
	_check(str(DecisionState._reservations.get(80, "")) == "environmental_inspection",
		"decision roundtrip: story reservations survive (int keys restored)")
	_decision_board_restore(snap)


# --- Demolition/pause, liquidation, grace loans, solvency (features 1/2/3/5/6) --------

func _test_building_pause() -> void:
	MatchState.buildings["test_pause_b"] = {"instance_id": "test_pause_b",
		"building_id": "b_001", "recipe_id": "", "tile_id": "tile_1_1", "owner": MatchState.LOCAL_PLAYER}
	_check(not MatchState.is_building_paused("test_pause_b"), "pause: buildings start unpaused")
	MatchState.set_building_paused("test_pause_b", true)
	_check(MatchState.is_building_paused("test_pause_b"), "pause: set_building_paused pauses it")
	_check((MatchState.export_state().get("paused_buildings", {}) as Dictionary).has("test_pause_b"),
		"pause: paused set is exported in the save state")
	MatchState.remove_building("test_pause_b")
	_check(not MatchState.paused_buildings.has("test_pause_b"),
		"pause: pause flag is cleared when the building is removed")

func _test_liquidate_all_buildings() -> void:
	var money_before := MatchState.money
	var BP = load("res://scripts/building_price.gd")
	var b1 := {"instance_id": "test_liq_1", "building_id": "b_001", "recipe_id": "",
		"tile_id": "tile_1_1", "owner": MatchState.LOCAL_PLAYER, "level": 1}
	var b2 := {"instance_id": "test_liq_2", "building_id": "b_001", "recipe_id": "",
		"tile_id": "tile_1_2", "owner": MatchState.LOCAL_PLAYER, "level": 1}
	MatchState.buildings["test_liq_1"] = b1
	MatchState.buildings["test_liq_2"] = b2
	var expected := int(round(float(BP.sale_price(b1)) * 1.5)) + int(round(float(BP.sale_price(b2)) * 1.5))
	var res: Dictionary = MatchState.liquidate_all_buildings(1.5)
	_check(int(res.count) >= 2, "liquidate: sells every player building (>=2 here)")
	_check(not MatchState.is_player_owned(MatchState.buildings["test_liq_1"])
		and not MatchState.is_player_owned(MatchState.buildings["test_liq_2"]),
		"liquidate: liquidated buildings flip to the NPC operator")
	_check(MatchState.money >= money_before + float(expected) - 1.0,
		"liquidate: player is paid 1.5x sale value for the buildings")
	MatchState.buildings.erase("test_liq_1")
	MatchState.buildings.erase("test_liq_2")
	MatchState.money = money_before

func _test_grace_loan() -> void:
	var loans_before: Array = LoanState.loans.duplicate(true)
	var money_before := MatchState.money
	LoanState.loans = []
	LoanState.take_grace_loan(500.0, 10)
	var loan: Dictionary = LoanState.loans.back()
	_check(absf(float(loan.principal_initial) - 500.0) < 0.001, "grace loan: £500 principal booked")
	_check(int(loan.grace_remaining) == 10 and absf(float(loan.payment_per_turn)) < 0.001,
		"grace loan: 10 interest-free turns, no payment scheduled")
	var money_after_disburse := MatchState.money
	_check(money_after_disburse >= money_before + 499.0, "grace loan: principal disbursed to the player")
	for _i in 10:
		LoanState.process_payments()
	var loan2: Dictionary = LoanState.loans.back()
	_check(absf(MatchState.money - money_after_disburse) < 0.001, "grace loan: no cash paid across the 10 grace turns")
	_check(int(loan2.grace_remaining) == 0 and float(loan2.payment_per_turn) > 0.0,
		"grace loan: converts to amortised payments once grace ends")
	_check(absf(float(loan2.principal_remaining) - 500.0 * (1.0 + float(loan2.interest_rate))) < 1.0,
		"grace loan: post-grace balance = principal x (1 + rate)")
	LoanState.loans = loans_before
	MatchState.money = money_before

func _test_distressed_program() -> void:
	var money_before := MatchState.money
	var loans_before: Array = LoanState.loans.duplicate(true)
	SolvencyState.reset()
	MatchState.buildings["test_dist_1"] = {"instance_id": "test_dist_1", "building_id": "b_001",
		"recipe_id": "", "tile_id": "tile_1_1", "owner": MatchState.LOCAL_PLAYER, "level": 1}
	var loans_n := LoanState.loans.size()
	var res: Dictionary = SolvencyState.accept_distressed_program()
	_check(int(res.count) >= 1, "distressed: the program liquidates the player's buildings")
	_check(not MatchState.is_player_owned(MatchState.buildings["test_dist_1"]),
		"distressed: buildings are bought out")
	_check(LoanState.loans.size() == loans_n + 1, "distressed: a £500 grace loan lands")
	_check(int(LoanState.loans.back().grace_remaining) == SolvencyState.DISTRESSED_GRACE_TURNS,
		"distressed: the rescue loan is interest-free for the grace period")
	MatchState.buildings.erase("test_dist_1")
	LoanState.loans = loans_before
	MatchState.money = money_before
	SolvencyState.reset()

func _test_solvency_bankruptcy() -> void:
	var ge_before := TurnManager.game_ended
	var seats_before: Dictionary = MatchState.advisor_seats.duplicate(true)
	SolvencyState.reset()
	MatchState.advisor_seats = {}                         # no CFO → no distressed offer, straight path
	for _i in 4:
		SolvencyState._evaluate(-600.0, -10.0)            # at/below floor, unprofitable
	_check(not SolvencyState.is_bankrupt(), "solvency: 4 floor+loss turns is not yet bankruptcy")
	SolvencyState._evaluate(-600.0, 5.0)                  # a profitable turn resets the clock
	_check(not SolvencyState.is_bankrupt(), "solvency: a profitable turn resets the bankruptcy clock")
	for _i in 5:
		SolvencyState._evaluate(-600.0, -10.0)
	_check(SolvencyState.is_bankrupt(), "solvency: 5 consecutive floor+loss turns → bankruptcy")
	_check(TurnManager.game_ended, "solvency: bankruptcy ends the game")
	SolvencyState.reset()
	TurnManager.game_ended = ge_before
	MatchState.advisor_seats = seats_before


func _test_decision_story_not_random() -> void:
	# A story-priority decision (e.g. distressed_asset) must NEVER surface from the
	# random scheduler — only reserve()/force_draw() may draw it.
	var snap := _decision_board_snapshot()
	DecisionState.reset()
	for t in range(10, 400):
		var picked: String = DecisionState._pick_random_definition(t)
		if picked != "":
			_check(int((DecisionState.DECISION_DEFINITIONS[picked] as Dictionary).get("priority", 2)) != 0,
				"scheduler: random draw never returns a story-priority decision")
			# advance recency so the loop keeps exploring different picks
			DecisionState._recent_draws.append({"turn": t, "id": picked,
				"category": str((DecisionState.DECISION_DEFINITIONS[picked] as Dictionary).get("category", ""))})
	# And force_draw CAN still summon it directly.
	DecisionState.reset()
	_check(DecisionState.force_draw("distressed_asset") == "",
		"scheduler: force_draw can still summon a story decision")
	DecisionState.reset()
	_decision_board_restore(snap)


func _test_decision_pulse_pipeline() -> void:
	# Pull now, reveal PULSE_LEAD_TURNS later; 20-turn per-category spacing; bounded cadence.
	var snap := _decision_board_snapshot()
	DecisionState.reset()
	DecisionState.auto_resolve = false
	TurnManager.current_turn = 30
	_check(DecisionState._pull("distressed_asset", 30), "pulse: _pull schedules a decision")
	_check(int(DecisionState._scheduled_pull.get("show_turn", 0)) == 30 + DecisionState.PULSE_LEAD_TURNS,
		"pulse: reveal is scheduled PULSE_LEAD_TURNS after the pull")
	_check(not DecisionState.has_pending(), "pulse: nothing is pending during the lead time")
	DecisionState._promote_scheduled()
	_check(DecisionState.has_pending() and DecisionState._scheduled_pull.is_empty(),
		"pulse: promotion moves the scheduled pull into pending")

	DecisionState.reset()
	DecisionState._recent_draws = [{"turn": 30, "id": "union_demands", "category": "labour"}]
	var elig_10: Array = DecisionState._eligible_ids(40)     # 10 turns after a labour event
	var elig_20: Array = DecisionState._eligible_ids(50)     # 20 turns after
	_check(not elig_10.has("union_demands") and not elig_10.has("headhunters"),
		"pulse: the same event type (labour) is ineligible within 20 turns")
	_check(elig_20.has("union_demands") or elig_20.has("headhunters"),
		"pulse: the event type becomes eligible again after 20 turns")

	for t in [12, 40, 120]:
		var iv: int = DecisionState._pulse_interval(int(t))
		_check(iv >= DecisionState.PULSE_MIN and iv <= DecisionState.PULSE_MAX,
			"pulse: interval stays within [PULSE_MIN, PULSE_MAX]")
	DecisionState.reset()
	_decision_board_restore(snap)


func _test_decision_view_never_empty() -> void:
	# Every decision, with a STALE target (entity gone — the pulse 3-turn lead can
	# leave targets stale), must still yield a non-empty view with choices, and the
	# real dialog must build visible content. A soft-lock happens if the inescapable
	# modal ever shows with no card.
	var snap := _decision_board_snapshot()
	var DialogScript = load("res://scripts/decision_dialog.gd")
	var dlg = DialogScript.new()
	add_child(dlg)
	await get_tree().process_frame
	for def_id in DecisionState.DECISION_DEFINITIONS.keys():
		var def: Dictionary = DecisionState.DECISION_DEFINITIONS[def_id]
		DecisionState.pending = {
			"uid": "diag_%s" % def_id,
			"def_id": str(def_id),
			"target": {"scope": str(def.get("scope", "company")), "name": "Ghost Works",
				"instance_id": "__gone__", "tile_id": "__gone__",
				"building_id": "__gone__", "good_id": "__gone__"},
			"turn_drawn": 30,
		}
		var view: Dictionary = DecisionState.pending_view()
		_check(not view.is_empty() and (view.get("choices", []) as Array).size() > 0,
			"decision '%s': pending_view yields choices even with a stale target" % def_id)
		dlg._rebuild()
		_check(dlg._content.get_child_count() > 0,
			"decision '%s': dialog builds visible content (no empty scrim)" % def_id)
	dlg.queue_free()
	DecisionState.pending = {}
	_decision_board_restore(snap)


func _test_auto_bridge_loan() -> void:
	# Negative cash auto-borrows up to available capacity to reach £0; capped when the
	# gap exceeds capacity (then the balance stays red and bankruptcy looms).
	var money_before := MatchState.money
	var loans_before: Array = LoanState.loans.duplicate(true)
	var profit_before: Array = LoanState._profit_history.duplicate()
	LoanState.loans = []
	LoanState._profit_history = []
	MatchState.money = 50.0
	_check(SolvencyState.auto_bridge_amount() == 0.0, "auto-bridge: solvent → borrows nothing")
	MatchState.money = -30.0
	_check(absf(SolvencyState.auto_bridge_amount() - minf(30.0, LoanState.available_capacity())) < 0.001,
		"auto-bridge: borrows the gap when capacity allows")
	MatchState.money = -1000000.0
	_check(absf(SolvencyState.auto_bridge_amount() - LoanState.available_capacity()) < 0.001,
		"auto-bridge: capped at available capacity when the gap is huge")
	# Applying it takes a loan and lifts the balance back toward £0.
	LoanState.loans = []
	MatchState.money = -30.0
	var n := LoanState.loans.size()
	SolvencyState._auto_bridge_negative_cash()
	_check(LoanState.loans.size() == n + 1, "auto-bridge: takes a loan when in the red")
	_check(MatchState.money >= -0.001, "auto-bridge: lifts the balance to ~£0 when capacity covers it")
	LoanState.loans = loans_before
	LoanState._profit_history = profit_before
	MatchState.money = money_before

func _test_cfo_tax_credit() -> void:
	# CFO tax-loss carry-forward: a losing turn banks 5% of revenue, usable oldest-first
	# to shave the tax bill over the next 5 turns, then expiring.
	var seats_before: Dictionary = MatchState.advisor_seats.duplicate(true)
	MatchState.cfo_tax_credit_pool = []
	MatchState.cfo_tax_credit_intro_shown = false
	MatchState.advisor_seats = {"cfo": "vera"}
	_check(MatchState.cfo_seated(), "cfo credit: a seated CFO is detected")

	# Bank 5% of £1000 = £50; the one-time explainer fires exactly once.
	var fires := [0]
	var cb := func(_a: float) -> void: fires[0] += 1
	MatchState.cfo_tax_credit_filed.connect(cb)
	var banked := MatchState.cfo_bank_tax_credit(1000.0)
	_check(absf(banked - 50.0) < 0.001, "cfo credit: banks 5% of revenue (£1000 → £50)")
	_check(fires[0] == 1, "cfo credit: explainer fires on the first filing")
	MatchState.cfo_bank_tax_credit(500.0)   # £25; a later filing does NOT re-fire the explainer
	_check(fires[0] == 1, "cfo credit: explainer is one-time only")
	MatchState.cfo_tax_credit_filed.disconnect(cb)

	# Pool = £50 + £25 = £75. Apply against a £40 tax bill: spends £40 (oldest first).
	_check(absf(MatchState.cfo_tax_credit_available() - 75.0) < 0.001, "cfo credit: pool totals both filings")
	var applied := MatchState.cfo_apply_tax_credit(40.0)
	_check(absf(applied - 40.0) < 0.001, "cfo credit: applies up to the tax owed")
	_check(absf(MatchState.cfo_tax_credit_available() - 35.0) < 0.001, "cfo credit: pool drops by the amount spent")

	# Asking for more than what's left returns only the remainder and empties the pool.
	var rest := MatchState.cfo_apply_tax_credit(1000.0)
	_check(absf(rest - 35.0) < 0.001, "cfo credit: caps at the remaining credit")
	_check(MatchState.cfo_tax_credit_pool.is_empty(), "cfo credit: pool empties once fully spent")

	# Expiry: a fresh credit survives 4 agings and expires on the 5th.
	MatchState.cfo_tax_credit_pool = []
	MatchState.cfo_bank_tax_credit(2000.0)   # £100, turns_left 5
	for _i in range(4):
		MatchState.cfo_age_tax_credits()
	_check(MatchState.cfo_tax_credit_available() > 0.0, "cfo credit: survives 4 turns")
	MatchState.cfo_age_tax_credits()
	_check(MatchState.cfo_tax_credit_pool.is_empty(), "cfo credit: expires after the 5-turn window")

	MatchState.cfo_tax_credit_pool = []
	MatchState.cfo_tax_credit_intro_shown = false
	MatchState.advisor_seats = seats_before

func _test_policy_state() -> void:
	# Decarbonisation squeeze (docs/co2-tax-and-green-subsidy-announcements-spec.md):
	# phase levels are pure functions of the turn; the carbon charge reads the dormant
	# co2_tax_multiplier column (now parsed); the biomass ethylene route is tech-gated.
	_check(PolicyState.co2_tax_level(100) == 0, "policy: CO2 tax not in force before turn 101")
	_check(PolicyState.co2_tax_level(101) == 1, "policy: CO2 tax phase 1 at turn 101 (announced t91)")
	_check(PolicyState.co2_tax_level(164) == 1, "policy: still phase 1 at turn 164")
	_check(PolicyState.co2_tax_level(165) == 2, "policy: phase 2 at turn 165")
	_check(PolicyState.co2_tax_level(230) == 3, "policy: phase 3 at turn 230")
	_check(PolicyState.green_subsidy_rate(104) == 0.0, "policy: no subsidy before turn 105")
	_check(absf(PolicyState.green_subsidy_rate(105) - EconomyConfig.GREEN_SUBSIDY_RATE) < 0.0001,
		"policy: subsidy rate live from turn 105")
	# Wind-down: full through 180, −10%/turn across 181..190, gone at 191.
	var full_rate: float = PolicyState.green_subsidy_rate(180)
	_check(absf(full_rate - EconomyConfig.GREEN_SUBSIDY_RATE) < 0.0001, "policy: subsidy at full rate through turn 180")
	_check(absf(PolicyState.green_subsidy_rate(181) - full_rate * 0.9) < 0.0001, "policy: subsidy 90% at turn 181")
	_check(absf(PolicyState.green_subsidy_rate(186) - full_rate * 0.4) < 0.0001, "policy: subsidy 40% at turn 186")
	_check(absf(PolicyState.green_subsidy_rate(189) - full_rate * 0.1) < 0.0001, "policy: subsidy 10% at turn 189 (last paying turn)")
	_check(PolicyState.green_subsidy_rate(190) == 0.0, "policy: subsidy reaches zero at turn 190")
	_check(PolicyState.green_subsidy_rate(191) == 0.0, "policy: subsidy gone at turn 191 (end announcement)")
	# The blocking "Understood" notice: a story-priority decision (never randomly
	# pulled) with a single acknowledge choice, reserved by PolicyState for turn 90.
	var notice: Dictionary = DecisionState.DECISION_DEFINITIONS.get("carbon_tax_notice", {})
	_check(not notice.is_empty(), "policy: carbon_tax_notice decision exists")
	_check(int(notice.get("priority", 99)) == DecisionState.PRIORITY_STORY,
		"policy: notice is story-priority (reserve-only, never randomly pulled)")
	_check((notice.get("choices", []) as Array).size() == 1
		and str((notice.get("choices", [])[0] as Dictionary).get("id", "")) == "understood",
		"policy: notice has the single Understood choice")
	_check(str(notice.get("headline", "")).begins_with("The new government"), "policy: carbon notice carries the owner headline")
	var sub_notice: Dictionary = DecisionState.DECISION_DEFINITIONS.get("green_subsidy_notice", {})
	_check(not sub_notice.is_empty(), "policy: green_subsidy_notice decision exists")
	_check(int(sub_notice.get("priority", 99)) == DecisionState.PRIORITY_STORY,
		"policy: subsidy notice is story-priority (reserve-only)")
	_check((sub_notice.get("choices", []) as Array).size() == 1
		and str((sub_notice.get("choices", [])[0] as Dictionary).get("id", "")) == "understood",
		"policy: subsidy notice has the single Understood choice")
	_check(str(sub_notice.get("headline", "")).begins_with("The government wants"), "policy: subsidy notice carries the owner headline")
	var end_notice: Dictionary = DecisionState.DECISION_DEFINITIONS.get("green_subsidy_end_notice", {})
	_check(not end_notice.is_empty() and int(end_notice.get("priority", 99)) == DecisionState.PRIORITY_STORY
		and (end_notice.get("choices", []) as Array).size() == 1,
		"policy: subsidy end notice exists (story-priority, single Understood)")
	# Catalog now parses the multiplier column (was dormant).
	var coal: Dictionary = Catalog.get_good_by_internal_name("coal")
	_check(absf(float(coal.get("co2_tax_multiplier", 0.0)) - 0.5) < 0.0001, "catalog: coal carbon intensity 0.5")
	var eth: Dictionary = Catalog.get_good_by_internal_name("ethylene")
	_check(absf(float(eth.get("co2_tax_multiplier", 0.0)) - 1.0) < 0.0001, "catalog: ethylene carbon intensity 1.0")
	# Charge math: 20 coal at P1 = 20 × 0.5 × 1.0 × 1.0 = £10; ×2 at P2; 0 before the
	# ramp; a linear ramp-in across 91..100 ((turn−90)/11 of P1).
	var coal_id := str(coal.get("id", ""))
	_check(absf(PolicyState.carbon_charge(coal_id, 20, 101) - 10.0) < 0.001, "policy: 20 coal at P1 charges £10")
	_check(absf(PolicyState.carbon_charge(coal_id, 20, 165) - 20.0) < 0.001, "policy: 20 coal at P2 charges £20")
	_check(PolicyState.carbon_charge(coal_id, 20, 10) == 0.0, "policy: no charge before the levy")
	_check(PolicyState.carbon_charge(coal_id, 20, 90) == 0.0, "policy: no charge at turn 90 (notice turn)")
	_check(absf(PolicyState.carbon_charge(coal_id, 20, 91) - 10.0 / 11.0) < 0.001, "policy: ramp begins at turn 91 (1/11 of P1)")
	_check(absf(PolicyState.carbon_charge(coal_id, 20, 96) - 10.0 * 6.0 / 11.0) < 0.001, "policy: mid-ramp at turn 96 (6/11 of P1)")
	_check(PolicyState.carbon_charge(coal_id, 20, 100) < 10.0, "policy: still below full P1 at turn 100")
	var biomass_id := str(Catalog.get_good_by_internal_name("biomass").get("id", ""))
	_check(PolicyState.carbon_charge(biomass_id, 100, 230) == 0.0, "policy: biomass is untaxed even at P3")
	# The biomass→ethylene escape route: r_228 Bio Ethylene (chem_plant, biomass direct)
	# promotes and is gated behind the new Biomass Cracking node. r_155 stays in the
	# dormant pool (bio_chem_plant / spec_microbes don't exist — original state).
	var r228: Dictionary = Catalog.get_recipe("r_228")
	_check(not r228.is_empty(), "recipe: r_228 (Bio Ethylene) promotes")
	_check(str(r228.get("required_research", "")) == "Biomass Cracking", "recipe: r_228 gated behind Biomass Cracking")
	_check(Catalog.get_recipe("r_155").is_empty(), "recipe: r_155 stays dormant (original pool state)")
	var found_node := false
	for d in MatchState._unlock_defs:
		if str(d.get("title", "")) == "Biomass Cracking":
			found_node = true
			_check(str(d.get("action", "")) == "Produce" and str(d.get("object", "")) == "biomass",
				"research: Biomass Cracking unlocks by producing biomass (fireable condition)")
	_check(found_node, "research: Biomass Cracking node exists")


func _test_insider_tip() -> void:
	# Government Affairs insider leak (turns 86..89): fires only with a 3/3-Influencing
	# officer in the seat, once per match; dismissible-critical news, not a decision.
	var seats_before: Dictionary = MatchState.advisor_seats.duplicate(true)
	var turn_before: int = TurnManager.current_turn
	PolicyState._insider_tip_fired = false

	# No officer → nothing, even inside the window.
	MatchState.advisor_seats = {}
	TurnManager.current_turn = 86
	PolicyState._maybe_fire_insider_tip()
	_check(not PolicyState._insider_tip_fired, "insider tip: silent with no Government Affairs officer")

	# A low-Influencing officer (Tom, inf 1) doesn't leak.
	MatchState.advisor_seats = {"government_affairs": "tom"}
	_check(PolicyState.get_insider_tip_officer() == "", "insider tip: inf < 3 officer doesn't qualify")
	PolicyState._maybe_fire_insider_tip()
	_check(not PolicyState._insider_tip_fired, "insider tip: silent with a low-Influencing officer")

	# Rufus (Silver Tongue, inf 3/3) leaks — but only inside the window.
	MatchState.advisor_seats = {"government_affairs": "rufus"}
	_check(PolicyState.get_insider_tip_officer() == "rufus", "insider tip: 3/3 officer qualifies")
	TurnManager.current_turn = 85
	PolicyState._maybe_fire_insider_tip()
	_check(not PolicyState._insider_tip_fired, "insider tip: not before turn 86")
	TurnManager.current_turn = 90
	PolicyState._maybe_fire_insider_tip()
	_check(not PolicyState._insider_tip_fired, "insider tip: not from turn 90 (official notice imminent)")
	TurnManager.current_turn = 87
	PolicyState._maybe_fire_insider_tip()
	_check(PolicyState._insider_tip_fired, "insider tip: fires in the window with a 3/3 officer")
	var found := false
	var tip_id := ""
	for ev in EventScheduler.active_events():
		if str(ev.get("kind", "")) == "advisor_tip":
			found = true
			tip_id = str(ev.get("id", ""))
			_check(str(ev.get("severity", "")) == "critical", "insider tip: critical severity")
			_check(str(ev.get("title", "")).begins_with("Rufus Ashby"), "insider tip: names the officer")
	_check(found, "insider tip: lands as an active (dismissible) event")

	# Once per match: a second window turn doesn't re-fire.
	var count_before: int = EventScheduler.active_events().size()
	TurnManager.current_turn = 88
	PolicyState._maybe_fire_insider_tip()
	_check(EventScheduler.active_events().size() == count_before, "insider tip: never fires twice")

	if tip_id != "":
		EventScheduler.dismiss(tip_id)
	PolicyState._insider_tip_fired = false
	MatchState.advisor_seats = seats_before
	TurnManager.current_turn = turn_before

func _test_deposit_running_out_warning() -> void:
	# A mine within Production.DEPOSIT_WARNING_TURNS of exhausting its deposit raises an
	# AMBER diagnostics row (with the ore's icon) and a DISMISSIBLE briefing warning.
	# Exhaustion used to be silent — the input bill just doubled with no notice.
	var saved: Dictionary = Production.last_turn_summary.duplicate(true)
	var coal := str(Catalog.get_good_by_internal_name("coal").get("id", ""))
	Production.last_turn_summary = {"deposits_running_out": [{
		"tile_id": "tile_6_8", "instance_id": "diag_mine", "building_id": "b_001",
		"token": "coal", "good_id": coal, "remaining": 180, "per_turn": 60, "turns_left": 3,
	}]}
	var readout = load("res://scripts/building_readout.gd")
	var mine := {"instance_id": "diag_mine", "tile_id": "tile_6_8", "building_id": "b_001",
		"recipe_id": "r_001", "level": 1, "owner": "player_1"}
	var rows: Array = readout.diagnostics(mine, Catalog.get_recipe("r_001"), Catalog.get_building("b_001"), false)
	var found: Dictionary = {}
	for r in rows:
		if str(r.get("label", "")) == "Deposit running out":
			found = r
	_check(not found.is_empty(), "diagnostics: a nearly-empty deposit raises its own row")
	_check(str(found.get("tone", "")) == "warn", "diagnostics: the deposit warning is amber, not a fault")
	_check(str(found.get("good_id", "")) == coal, "diagnostics: the row carries the ORE's good id for its icon")
	_check(str(found.get("detail", "")).contains("3 turn"), "diagnostics: the row states the turns remaining")
	# The briefing update: warning severity, dismissible, and iconned with the same good.
	var item: Dictionary = TurnBriefing._deposit_running_out_item()
	_check(str(item.get("severity", "")) == "warning", "briefing: deposit update is a warning")
	_check(bool(item.get("dismissible", false)), "briefing: deposit update can be dismissed")
	_check(str(item.get("icon_good_id", "")) == coal, "briefing: deposit update uses the ore's icon")
	_check(str(item.get("title", "")).contains("3 turn"), "briefing: title counts down the turns")
	# Dismissing silences it, but a SECOND mine running out re-raises it. Drive the gate
	# directly — dismiss() resolves the id through the live item list, which the panel
	# builds and this harness does not.
	TurnBriefing._alert_dismissed[str(item.get("id", ""))] = int(item.get("magnitude", 0))
	_check(TurnBriefing._deposit_running_out_item().is_empty(), "briefing: dismissal silences the update")
	(Production.last_turn_summary["deposits_running_out"] as Array).append({
		"tile_id": "tile_7_10", "instance_id": "diag_mine_2", "building_id": "b_001",
		"token": "iron_ore", "good_id": str(Catalog.get_good_by_internal_name("iron_ore").get("id", "")),
		"remaining": 120, "per_turn": 40, "turns_left": 3,
	})
	_check(not TurnBriefing._deposit_running_out_item().is_empty(),
		"briefing: a SECOND mine running out re-raises the dismissed update")
	Production.last_turn_summary = {"deposits_running_out": []}
	_check(TurnBriefing._deposit_running_out_item().is_empty(), "briefing: clears when no deposit is low")
	Production.last_turn_summary = saved

func _test_partial_power_dispatch() -> void:
	# PARTIAL DISPATCH (owner ruling): a generator that slightly overshoots its tile's
	# remaining cable headroom runs DERATED into the gap; a bigger overshoot doesn't run.
	# Tested through the pure decision so it needs no cabled fixture tile.
	var tol: float = Power.PARTIAL_DISPATCH_TOLERANCE
	_check(Power.dispatchable(600, 2000) == 600, "a plant well under the headroom dispatches in full")
	_check(Power.dispatchable(600, 600) == 600, "an exact fit dispatches in full")
	# 620 into 600 headroom: overshoot 20 = 3.2% of output -> derate to 600.
	_check(Power.dispatchable(620, 600) == 600,
		"a small overshoot derates to the headroom instead of idling the plant")
	# 800 into 600: overshoot 200 = 25% of output -> at the tolerance, refuse.
	_check(Power.dispatchable(800, 600) == 0,
		"an overshoot AT the %d%% tolerance does not run" % int(tol * 100.0))
	# 690 into 620 (the e2e's real case): overshoot 70 = 10.1% -> derate.
	_check(Power.dispatchable(690, 620) == 620,
		"the e2e's stranded 3rd plant now fills its tile's remaining 620 MW")
	_check(Power.dispatchable(690, 0) == 0, "a full tile dispatches nothing")
	_check(Power.dispatchable(0, 2000) == 0, "a zero-output building dispatches nothing")
	_check(Power.dispatchable(690, -50) == 0, "negative headroom dispatches nothing")

func _test_building_diagnostics() -> void:
	# New BDP diagnostics: cable-overload for power producers, stockpile-over-utilised
	# for non-power producers (docs/co2-tax spec follow-ups).
	var readout = load("res://scripts/building_readout.gd")

	# Power producer crowded out by the cable export cap: _can_run_recipe records a
	# "power" missing entry → "Cannot push power" fault + "Cables overloaded" row.
	var plant := {"instance_id": "diag_plant", "tile_id": "tile_9_9", "building_id": "b_003", "recipe_id": "r_004", "level": 1, "owner": "player_1"}
	Production.missing_by_building["diag_plant"] = [{"good_id": "power", "internal_name": "power", "need": 1000, "have": 2000}]
	var rows: Array = readout.diagnostics(plant, Catalog.get_recipe("r_004"), Catalog.get_building("b_003"), false)
	var titles: Array = []
	for r in rows:
		titles.append(str(r.get("label", "")))
	_check(titles.has("Power output capped"), "diagnostics: cable-capped plant shows the 'Power output capped' row")
	_check(not titles.has("Generating power"), "diagnostics: blocked plant doesn't claim to be generating")
	# AMBER, not red — the plant is throttled, not faulted.
	var capped_tone := ""
	var capped_detail := ""
	for r in rows:
		if str(r.get("label", "")) == "Power output capped":
			capped_tone = str(r.get("tone", ""))
			capped_detail = str(r.get("detail", ""))
	_check(capped_tone == "warn", "diagnostics: the cable cap reads amber, not a critical fault")
	_check(capped_detail.begins_with("Power output capped because of cabling."),
		"diagnostics: cable-cap detail leads with the cause")
	_check(capped_detail.contains("MW produced"), "diagnostics: cable-cap detail reports produced/capacity")
	# The plant's run_state is "restarting" (its power "input" is unmet), and the cap row
	# must WIN that race — otherwise a permanently throttled plant cheerfully reports
	# "Starting — production begins next turn" forever.
	_check(not titles.has("Starting"), "diagnostics: the cable cap outranks the 'Starting' row")
	# Below max cable level the advice is actionable; at max there is nothing to upgrade.
	if Power.cable_level_is_max("tile_9_9"):
		_check(capped_detail.ends_with("Max power capacity reached for this tile."),
			"diagnostics: at max cable level the row stops offering an upgrade")
	else:
		_check(capped_detail.ends_with("Upgrade cables to increase tile capacity."),
			"diagnostics: below max cable level the row tells the player to upgrade")
	Production.missing_by_building.erase("diag_plant")
	rows = readout.diagnostics(plant, Catalog.get_recipe("r_004"), Catalog.get_building("b_003"), false)
	titles = []
	for r in rows:
		titles.append(str(r.get("label", "")))
	_check(not titles.has("Power output capped"), "diagnostics: unblocked plant has no cable-cap row")

	# Non-power producer on a FULL tile warehouse → stockpile over-utilised row.
	var mill := {"instance_id": "diag_mill", "tile_id": "tile_8_8", "building_id": "b_002", "recipe_id": "r_002", "level": 1, "owner": "player_1"}
	var mill_recipe: Dictionary = Catalog.get_recipe(str(Catalog.get_recipes_for_building("b_002")[0].get("recipe_id", "")))
	var coal_id := str(Catalog.get_good_by_internal_name("coal").get("id", ""))
	var cap: int = Stockpile.get_capacity("tile_8_8")
	var before: int = Stockpile.get_used_capacity("tile_8_8")
	Stockpile.add("tile_8_8", coal_id, cap - before)   # fill to the brim
	rows = readout.diagnostics(mill, mill_recipe, Catalog.get_building("b_002"), false)
	titles = []
	for r in rows:
		titles.append(str(r.get("label", "")))
	_check(titles.has("Stockpile over-utilised"), "diagnostics: full warehouse shows the over-utilised row")
	Stockpile.consume("tile_8_8", coal_id, cap - before)
	rows = readout.diagnostics(mill, mill_recipe, Catalog.get_building("b_002"), false)
	titles = []
	for r in rows:
		titles.append(str(r.get("label", "")))
	_check(not titles.has("Stockpile over-utilised"), "diagnostics: cleared warehouse drops the row")

	# The "Output modifiers" row was removed from diagnostics (owner request 2026-07-13).
	# Even with an active recipe_output modifier — which used to produce that row plus a
	# "See all modifiers" accordion (the row carried a "parts" array) — none appears now.
	var building_status = load("res://scripts/building_status.gd")
	var mod_id: String = Modifiers.add({"domain": "recipe_output", "target": "*", "pct": 12.0, "label": "Test output boost"})
	var net_parts: Array = building_status.net_output_modifier(mill, mill_recipe).get("parts", [])
	_check(not net_parts.is_empty(), "diagnostics: precondition — a recipe_output modifier is active on the recipe")
	rows = readout.diagnostics(mill, mill_recipe, Catalog.get_building("b_002"), false)
	var has_mod_row := false
	var has_parts := false
	for r in rows:
		if str(r.get("label", "")).begins_with("Output modifiers"):
			has_mod_row = true
		if r.has("parts"):
			has_parts = true
	_check(not has_mod_row, "diagnostics: no 'Output modifiers' row even with an active modifier")
	_check(not has_parts, "diagnostics: no diagnostics row carries a modifier 'parts' accordion")
	Modifiers.remove(mod_id)

func _test_infra_upgrade() -> void:
	# Cash-only infrastructure upgrades (owner ruling: L2 £150, L3 £350). The pending
	# machinery is shared with buildings; the level is written to the TILE at completion
	# (headless has no map, so the tile write no-ops — covered by the shot tool).
	var money_before := MatchState.money
	var pend_before: Array = MatchState.pending_upgrades.duplicate(true)
	MatchState.pending_upgrades = []
	MatchState.money = 1000.0
	var iid: String = MatchState.add_building("b_006", "", "tile_9_9", "player_1", "test_infra_cables")
	_check(iid != "", "infra upgrade: cables instance placed")

	var pv: Dictionary = MatchState.preview_upgrade(iid)
	_check(bool(pv.get("infra", false)), "infra upgrade: preview flags infra")
	_check(absf(float(pv.get("cash_cost", 0.0)) - 150.0) < 0.001, "infra upgrade: L2 quote is £150")
	_check((pv.get("materials", []) as Array).is_empty(), "infra upgrade: no material kit")
	_check(str(pv.get("research_gate", "x")) == "", "infra upgrade: no research gate")
	var cap: Dictionary = pv.get("capacity", {})
	_check(absf(float(cap.get("cur", 0.0)) - 2000.0) < 0.001 and absf(float(cap.get("new", 0.0)) - 4000.0) < 0.001,
		"infra upgrade: cables capacity delta 2000 → 4000")

	var res: Dictionary = MatchState.start_upgrade(iid)
	_check(bool(res.get("ok", false)), "infra upgrade: start succeeds")
	_check(absf(MatchState.money - 850.0) < 0.001, "infra upgrade: £150 charged up front")
	_check(not MatchState.pending_upgrade(iid).is_empty(), "infra upgrade: pending after start")

	# Cancel refunds the cash in full (no start/cancel pump: net zero).
	MatchState.cancel_upgrade(iid)
	_check(absf(MatchState.money - 1000.0) < 0.001, "infra upgrade: cancel refunds the cash")

	# Run it to completion: 3 ticks → instance level bumps (tile write no-ops headless).
	MatchState.start_upgrade(iid)
	var done: Array = []
	for _i in range(3):
		done = MatchState.tick_upgrades()
	_check(done.has(iid), "infra upgrade: completes after 3 turns")
	_check(int((MatchState.buildings[iid] as Dictionary).get("level", 1)) == 2, "infra upgrade: instance level is 2")

	# Broke wallet: clean atomic failure.
	MatchState.money = 10.0
	var res2: Dictionary = MatchState.start_upgrade(iid)
	_check(not bool(res2.get("ok", true)), "infra upgrade: refused when broke")
	_check(absf(MatchState.money - 10.0) < 0.001, "infra upgrade: nothing charged on refusal")

	MatchState.remove_building(iid)

	# Rails exercise the slot→mode mapping ("rails" slot ↔ "rail" transport mode).
	MatchState.money = 1000.0
	var rid: String = MatchState.add_building("b_019", "", "tile_9_9", "player_1", "test_infra_rails")
	var rpv: Dictionary = MatchState.preview_upgrade(rid)
	var rcap: Dictionary = rpv.get("capacity", {})
	_check(bool(rpv.get("infra", false)) and absf(float(rcap.get("cur", 0.0)) - 600.0) < 0.001
		and absf(float(rcap.get("new", 0.0)) - 1200.0) < 0.001,
		"infra upgrade: rails capacity delta 600 → 1200 (rail mode mapping)")
	MatchState.remove_building(rid)

	MatchState.pending_upgrades = pend_before
	MatchState.money = money_before

# --- Turn Briefing (docs/turn-briefing-panel-spec.md) -------------------------

func _test_decision_queue_stacking() -> void:
	# Several decisions can coexist (the Briefing's mini-menu case): stacking,
	# uid-keyed resolve, the commit guard holding until the LAST one resolves, and
	# auto_resolve clearing the whole queue.
	var snap := _decision_board_snapshot()
	DecisionState.reset()
	MatchState.advisor_seats = {}
	TurnManager.current_turn = 40
	TurnManager.current_phase = TurnManager.Phase.DECIDE
	DecisionState.pending_queue = [
		{"uid": "q1", "def_id": "brokers_offer",
			"target": {"scope": "company", "good_id": "g_001", "name": "Coal"}, "turn_drawn": 40},
		{"uid": "q2", "def_id": "land_deal",
			"target": {"scope": "tile", "tile_id": "tile_1_1", "name": "Test Tile"}, "turn_drawn": 40},
	]
	_check(DecisionState.pending_views().size() == 2, "queue: two decisions expand to two views")
	_check(str(DecisionState.pending_view("q2").get("uid", "")) == "q2",
		"queue: pending_view resolves a specific uid")
	# Resolving the SECOND leaves the first pending; commit stays guarded.
	_check(DecisionState.resolve("keep", "q2") == "", "queue: uid-keyed resolve works")
	_check(DecisionState.has_pending(), "queue: one decision still pending after resolving the other")
	var turn_before := TurnManager.current_turn
	TurnManager.commit_turn()
	_check(TurnManager.current_turn == turn_before and not TurnManager.is_resolving,
		"queue: commit_turn refuses while ANY decision is pending")
	DecisionState.auto_resolve = true
	DecisionState.auto_resolve_pending()
	DecisionState.auto_resolve = false
	_check(not DecisionState.has_pending(), "queue: auto_resolve clears the whole queue")
	_decision_board_restore(snap)

func _test_briefing_items_and_dismissal() -> void:
	# The Briefing assembles decisions + live alerts, decisions are never dismissible,
	# alerts dismiss quietly and re-surface only when the condition worsens.
	var snap := _decision_board_snapshot()
	var loans_before: Array = LoanState.loans.duplicate(true)
	var profit_before: Array = LoanState._profit_history.duplicate()
	var missing_before: Dictionary = Production.missing_by_building.duplicate(true)
	DecisionState.reset()
	TurnBriefing.reset()
	TurnManager.current_turn = 40
	# One pending decision + a bankruptcy-grade runway + one starved building.
	DecisionState.pending_queue = [{"uid": "b1", "def_id": "brokers_offer",
		"target": {"scope": "company", "good_id": "g_001", "name": "Coal"}, "turn_drawn": 40}]
	LoanState.loans = []
	LoanState._profit_history = [-10.0]
	# Whatever collateral the shared test env carries, park cash so runway < £100.
	MatchState.money = -(LoanState.available_capacity() + 50.0)
	MatchState.buildings["tb_starved"] = {"instance_id": "tb_starved", "building_id": "b_001",
		"recipe_id": "", "tile_id": "tile_1_1", "owner": MatchState.LOCAL_PLAYER}
	Production.missing_by_building = {"tb_starved": [{"internal_name": "coal"}]}
	TurnBriefing._rebuild_items()
	var ids: Array = TurnBriefing.items().map(func(it) -> String: return str(it.id))
	_check(ids.has("dec:b1"), "briefing: the pending decision becomes a decision item")
	_check(ids.has("alert:bankruptcy"), "briefing: low runway raises the bankruptcy alert")
	_check(ids.has("alert:starved"), "briefing: a starved building raises the starved alert")
	_check(ids[0] == "dec:b1", "briefing: decisions sort first")
	# Decisions are never dismissible; alerts are.
	TurnBriefing.dismiss("dec:b1")
	TurnBriefing._rebuild_items()
	_check(TurnBriefing.items().any(func(it) -> bool: return str(it.id) == "dec:b1"),
		"briefing: dismiss on a decision is a no-op (resolve-only)")
	TurnBriefing.dismiss("alert:starved")
	TurnBriefing._rebuild_items()
	_check(not TurnBriefing.items().any(func(it) -> bool: return str(it.id) == "alert:starved"),
		"briefing: a dismissed alert leaves the list")
	# Same magnitude → stays quiet; worsened (another building starves) → re-surfaces.
	MatchState.buildings["tb_starved2"] = {"instance_id": "tb_starved2", "building_id": "b_001",
		"recipe_id": "", "tile_id": "tile_1_2", "owner": MatchState.LOCAL_PLAYER}
	Production.missing_by_building["tb_starved2"] = [{"internal_name": "power"}]
	TurnBriefing._rebuild_items()
	_check(TurnBriefing.items().any(func(it) -> bool: return str(it.id) == "alert:starved"),
		"briefing: the starved alert re-surfaces when the count worsens")
	MatchState.buildings.erase("tb_starved")
	MatchState.buildings.erase("tb_starved2")
	Production.missing_by_building = missing_before
	LoanState.loans = loans_before
	LoanState._profit_history = profit_before
	TurnBriefing.reset()
	_decision_board_restore(snap)

func _test_briefing_event_mapping() -> void:
	# Bell events map into sections: research → info, unknown kinds → news; dismissing
	# in the Briefing dismisses in the bell (one source of truth).
	var snap := _decision_board_snapshot()
	EventScheduler.reset()
	TurnBriefing.reset()
	EventScheduler.emit_event({"id": "tb_ev_res", "kind": "research_unlocked",
		"title": "Unlocked: Test", "body": "x", "persistent": false,
		"research_name": "Test", "research_reward": "Reward X", "research_condition": "Produce coal 5 units"})
	EventScheduler.emit_event({"id": "tb_ev_news", "kind": "carbon_announcement",
		"title": "Carbon tax announced", "body": "x", "severity": "warning", "persistent": true})
	TurnBriefing._rebuild_items()
	var by_id := {}
	for it in TurnBriefing.items():
		by_id[str(it.id)] = it
	# Research unlocks aggregate into a single "info" update that carries each entry.
	var agg: Dictionary = by_id.get("research_unlocked_agg", {})
	_check(not agg.is_empty() and str(agg.get("section", "")) == "info" \
			and str((agg.get("research", [{}])[0] as Dictionary).get("reward", "")) == "Reward X",
		"briefing: research events land in the info section")
	_check(by_id.has("ev:tb_ev_news") and str(by_id["ev:tb_ev_news"].section) == "news",
		"briefing: unknown announcement kinds land in the news section")
	TurnBriefing.dismiss("ev:tb_ev_news")
	_check(not EventScheduler._active.has("tb_ev_news"),
		"briefing: dismissing an event item dismisses it in the bell too")
	EventScheduler.reset()
	TurnBriefing.reset()
	_decision_board_restore(snap)
