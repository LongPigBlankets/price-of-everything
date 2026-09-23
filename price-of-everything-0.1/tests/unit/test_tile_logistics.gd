extends "res://tests/unit/test_middleman_service.gd"
const Routes := preload("res://scripts/logistics_routes_view.gd")
const Readout := preload("res://scripts/building_readout.gd")
const TileViewData := preload("res://scripts/tile_view_data.gd")

func _test_intermediary_output_is_not_rendered_as_tile_stockpile() -> void:
	var iid := str(setup()[0])
	var building := BuildingState.get_building(iid)
	var recipe := Catalog.get_recipe(str(building.get("recipe_id", "")))
	var label := TileViewData._output_route_label(iid, str(building.get("tile_id", "")), recipe, false)
	var destination := TileViewData._destination_text(building, "g_008")
	_check("logistics intermediary" in label and destination == "logistics intermediary",
		"active intermediary output stays private in tile route labels")
	cleanup()

func _test_input_source_list_contains_endpoints_not_transit_tiles() -> void:
	setup()
	var consumer := BuildingState.add_building("b_007", "r_009", "tile_6_4", MatchState.LOCAL_PLAYER)
	Stockpile.add("tile_8_8", "g_007", 32)
	TransportState.pending_transport_shipments = [{
		"good_id": "g_007", "qty": 32, "source_tile": "tile_1_1",
		"destination_tile": "tile_9_9", "path_tiles": ["tile_5_5", "tile_7_7"],
		"turns_remaining": 2,
	}]
	var sources := Readout.stockpile_source_tiles(BuildingState.get_building(consumer), "g_007")
	_check(sources.has("tile_8_8") and sources.has("tile_9_9"), "source list includes stored and arriving endpoints")
	_check(not sources.has("tile_1_1") and not sources.has("tile_5_5") and not sources.has("tile_7_7"), "source list excludes shipment origin and transit path tiles")
	cleanup()

func _test_tile_surplus_destination_round_trips() -> void:
	setup()
	MatchState.set_sell_surplus_destination("tile_5_4", "middleman")
	_check(MatchState.get_sell_surplus_destination("tile_5_4") == "middleman", "tile surplus can be sold to the local intermediary")
	_check(MatchState.is_sell_surplus_enabled("tile_5_4"), "local intermediary surplus destination enables the standing order")
	var snapshot := SaveLoad.export_snapshot()
	SaveLoad.import_snapshot(JSON.parse_string(JSON.stringify(snapshot)))
	_check(MatchState.get_sell_surplus_destination("tile_5_4") == "middleman", "surplus destination survives save/load")
	MatchState.set_sell_surplus_destination("tile_5_4", "none")
	_check(not MatchState.is_sell_surplus_enabled("tile_5_4") and MatchState.get_sell_surplus_destination("tile_5_4") == "none", "disabling surplus clears the standing order")
	cleanup()

func _test_tile_switch_is_atomic_and_sides_independent() -> void:
	var ids := setup(2)
	for iid: String in ids: Service.entry(iid).inputs = {"g_006":20}
	Stockpile.add("tile_5_4", "g_001", Stockpile.get_capacity("tile_5_4")-30)
	_check(not Service.set_tile_mode("tile_5_4", "input", "managed").ok, "combined releases must fit, not just each building")
	_check(Service.uses_inputs(ids[0]) and Service.uses_inputs(ids[1]), "failed tile switch changes neither building")
	Stockpile.consume("tile_5_4", "g_001", 10)
	_check(Service.set_tile_mode("tile_5_4", "input", "managed").ok, "combined release fits exactly")
	_check(Stockpile.get_at_tile("tile_5_4", "g_006")==40, "all paid inputs released once")
	var state := Service.tile_sides("tile_5_4")
	_check(not state.all_input and state.all_output and state.physical, "mixed tile keeps stockpile and independent output tick")
	_check(Service.set_tile_mode("tile_5_4", "input", "middleman").ok, "tile can return to intermediary")
	_check(not Service.tile_sides("tile_5_4").physical, "all intermediary hides regular stockpile")
	_check(Stockpile.get_at_tile("tile_5_4", "g_006")==40, "hiding stockpile preserves owned stock")
	cleanup()

func _test_tile_switch_credit_and_ownership_guards() -> void:
	var ids := setup(2)
	Service.set_tile_mode("tile_5_4", "input", "managed")
	MatchState.building_tabs[ids[1]] = {"amount":10.0}
	_check(not Service.set_tile_mode("tile_5_4", "input", "middleman").ok, "one credit tab rejects whole operation")
	_check(not Service.uses_inputs(ids[0]), "earlier eligible building not partially switched")
	MatchState.building_tabs.clear()
	var npc := BuildingState.add_building("b_007", "r_009", "tile_5_4", "npc")
	_check(Service.tile_sides("tile_5_4").input.size()==2, "NPC excluded from tile controls")
	Service.set_tile_mode("tile_5_4", "input", "middleman")
	_check(not Service.enabled(npc), "tile switch never opts NPC in")
	cleanup()

func _test_ledger_routes_track_each_side_and_split_destinations() -> void:
	var iid := str(setup()[0])
	var b := BuildingState.get_building(iid)
	_check(Routes.endpoints(b, "input")==[{"icon":"middleman", "label":"Logistics Intermediary"}], "private input icons deduplicated")
	Service.set_mode(iid, "output", "managed")
	_check(Routes.endpoints(b, "output")[0].label=="Tile (5, 4) Stockpile", "managed output shows actual retained stockpile")
	MatchState.route_output_to_market(iid, "g_008")
	_check(Routes.endpoints(b, "output")[0].label=="Global Market", "market output has port endpoint")
	Service.set_mode(iid, "input", "managed")
	Service.set_input_source(iid, "g_006", "tile_5_4")
	var routes := Routes.endpoints(b, "input")
	_check(routes.any(func(r: Dictionary)->bool: return r.icon=="stockpile") and routes.any(func(r: Dictionary)->bool: return r.icon=="port"), "mixed managed inputs show stockpile and global market")
	cleanup()

func _test_grid_and_recipe_less_buildings_do_not_force_stockpile() -> void:
	setup()
	var plant := BuildingState.add_building("b_001", "r_004", "tile_5_4", MatchState.LOCAL_PLAYER)
	_check(Service.enable(plant).ok, "enable material fuel supply for power plant")
	BuildingState.add_building("b_004", "", "tile_5_4", MatchState.LOCAL_PLAYER)
	_check(not Service.tile_sides("tile_5_4").physical, "grid output and recipe-less port do not count as physical freight")
	_check(Routes.endpoints(BuildingState.get_building(plant), "output")[0].label=="Electricity grid", "power ledger retains grid endpoint")
	cleanup()

func _test_ledger_split_and_producer_endpoints() -> void:
	var iid := str(setup()[0])
	Service.set_mode(iid, "input", "managed")
	Service.set_mode(iid, "output", "managed")
	var furnace := BuildingState.add_building("b_002", "r_003", "tile_5_4", MatchState.LOCAL_PLAYER)
	MatchState.set_output_stockpile_destination(furnace, "tile_5_4", "g_006")
	var routes := Routes.endpoints(BuildingState.get_building(iid), "input")
	_check(routes.any(func(r: Dictionary)->bool: return r.icon=="b_002" and "(5, 4)" in str(r.label)), "local supplier uses furnace icon and tile tooltip")
	MatchState.add_output_split_destination(iid, "g_008", "tile_6_4")
	MatchState.add_output_split_destination(iid, "g_008", "tile_7_4")
	routes = Routes.endpoints(BuildingState.get_building(iid), "output")
	_check(routes.size()==2 and routes[0].label=="Tile (6, 4) Stockpile" and routes[1].label=="Tile (7, 4) Stockpile", "split destinations each have a stockpile endpoint")
	cleanup()

func _test_global_switch_counts_and_checks_every_tile_before_changing() -> void:
	var ids := setup(2)
	var remote := BuildingState.add_building("b_007", "r_009", "tile_6_4", MatchState.LOCAL_PLAYER)
	Service.set_mode(remote, "input", "middleman")
	Service.set_mode(remote, "output", "middleman")
	Service.set_mode(ids[0], "input", "managed")
	var state := Service.global_side("input")
	var changes := Service.changed_ids(state.ids, "input", "managed")
	_check(state.intermediary==2 and state.managed==1 and changes.size()==2, "global count excludes already-selected mode")
	Service.entry(remote).inputs={"g_006":1}
	Stockpile.add("tile_6_4", "g_001", Stockpile.get_capacity("tile_6_4"))
	_check(not Service.set_modes(changes, "input", "managed").ok, "full remote tile rejects global switch")
	_check(Service.uses_inputs(ids[1]) and Service.uses_inputs(remote), "no earlier tile partially switched")
	Stockpile.consume("tile_6_4", "g_001", 1)
	_check(Service.set_modes(changes, "input", "managed").changed==2, "global switch changes exactly displayed selection")
	_check(Service.uses_outputs(ids[1]) and Service.uses_outputs(remote), "global input choice leaves output unchanged")
	_check(Service.set_modes(changes, "input", "managed").changed==0, "reapplying selection is idempotent")
	cleanup()
