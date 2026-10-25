extends "res://tests/test_base.gd"
const FEATURE := "rail_hub"
const Hub := preload("res://scripts/rail_hub.gd")
const Tab := preload("res://scripts/tvp_v3/buildings_tab.gd")

func _test_rail_hub_purchase_capacity_costs_save() -> void:
	MatchState.reset(); Modifiers.reset(); TurnManager.current_turn = 1
	var fake := Node.new()
	var src := GDScript.new()
	src.source_code = "extends Node\nvar tiles := {}\nfunc id_to_coord(t):\n var p=t.split('_')\n return Vector2i(int(p[1])-1,int(p[2])-1)\n"
	src.reload(); fake.set_script(src); fake.add_to_group("hex_map")
	var tile := "tile_5_10"; var coord := Vector2i(4,9)
	fake.set("tiles", {coord: {"id":tile,"infrastructure_present":["cables","rails"],"infrastructure_levels":{"cables":1,"rails":1}}})
	get_tree().root.add_child(fake)
	var site := {"city":"Stoneshore","city_tile":tile,"tile":tile,"pos":Vector2(2790,5550),"yaw":2.094395,"height":33.1,"tracks":6,"siding_tracks":2}
	var ids := Hub.seed_sites([site]); var iid: String = ids[0]
	var hub := BuildingState.get_building(iid)
	_check(Hub.seed_sites([site]).is_empty(), "Rail Hub seeding is idempotent")
	_check(not MatchState.is_building_available(Hub.ID), "Rail Hub cannot be constructed")
	_check(MatchState.building_purchase_price(hub)==5000, "Rail Hub price is exactly £5000")
	_check(BuildingState.space_used(hub)==30, "Rail Hub occupies 30 land")
	_check(TransportState.tile_mode_capacity("rail",1,tile)==600, "NPC hub gives no capacity bonus")
	Production._process_production()
	_check(float(Production.last_turn_summary.maintenance_paid)==0 and float(Production.last_turn_summary.labour_paid)==0 and int(Production.last_turn_summary.power_demand)==0, "NPC pays its own running costs")
	var panel := preload("res://scripts/tile_info_panel_v2.gd").new()
	get_tree().root.add_child(panel)
	MatchState.money = 4999
	panel.set("_pending_port_buy", {"iid":iid,"price":5000})
	panel.call("_on_port_buy_confirmed", false)
	_check(not BuildingState.is_player_owned(hub) and MatchState.money==4999, "Insufficient funds cannot buy a hub")
	MatchState.money = 6000
	panel.call("_on_port_buy_confirmed", false)
	_check(MatchState.is_under_offer(iid) and not BuildingState.is_player_owned(hub) and MatchState.money==1000,
		"Tile-panel purchase charges £5000 and the hub goes under offer")
	panel.call("_on_port_buy_confirmed", false)
	_check(MatchState.money==1000, "Repeated confirmation cannot charge twice")
	# The 2-turn closing (docs/pacing-labour-mining-licensing-spec.md §7.5).
	MatchState.tick_purchases()
	MatchState.tick_purchases()
	_check(BuildingState.is_player_owned(hub) and MatchState.money==1000, "Tile-panel purchase transfers ownership at closing")
	_check(BuildingState.get_tile_land_owned(tile)==30, "Buying includes the hub's land")
	_check(TransportState.tile_mode_capacity("rail",1,tile)==1200, "Purchased hub doubles local rail capacity")
	var route := {"tiles":[tile,"tile_5_11"],"legs":[{"mode":"rail","from":tile,"to":"tile_5_11"}]}
	TransportState._last_link_flow = {tile+"|rail":900}
	_check(TransportState.route_congestion_tier(route)==0, "900 rail units remain uncongested with the hub")
	BuildingWorks.set_building_paused(iid,true)
	_check(TransportState.route_congestion_tier(route)==1, "Same 900 units incur congestion when the hub pauses")
	BuildingWorks.set_building_paused(iid,false)
	TransportState._last_link_flow.clear()
	for distance in [3,4]:
		var target := "tile_5_%d" % (10+distance)
		_check(TransportState.tile_mode_capacity("rail",1,target)==(1200 if distance==3 else 600), "Radius boundary at %d tiles" % distance)
	_check(TransportState.tile_mode_capacity("roads",1,tile)==300 and TransportState.tile_mode_capacity("pipes",1,tile)==250, "Roads and pipes receive no bonus")
	var other := BuildingState.add_building(Hub.ID,Hub.RECIPE,tile)
	_check(TransportState.tile_mode_capacity("rail",1,tile)==1200, "Overlapping hubs do not stack")
	BuildingState.remove_building(other)
	_check(not BuildingWorks.start_upgrade(iid).ok and BuildingWorks.preview_upgrade(iid).at_max, "Rail Hub has no upgrades")
	var recipe := Catalog.get_recipe(Hub.RECIPE)
	_check(not recipe.is_empty() and Production._effective_energy_req(hub,recipe)==80, "Rail Hub operating recipe draws 80 power")
	_check(is_equal_approx(Production._base_labour_cost(hub,recipe),6.0), "Base wages are £6 per turn")
	Production._process_production()
	_check(is_equal_approx(float(Production.last_turn_summary.maintenance_paid),10.0), "Turn charges £10 maintenance")
	_check(is_equal_approx(float(Production.last_turn_summary.labour_paid),6.0), "Turn charges £6 labour")
	_check(int(Production.last_turn_summary.power_demand)==80 and int(Power.tile_drawn.get(tile,0))==80, "Turn books 80 power to the grid")
	BuildingWorks.set_building_paused(iid,true)
	_check(Hub.capacity_multiplier(tile)==1.0, "Paused hub gives no bonus")
	BuildingWorks.set_building_paused(iid,false)
	fake.tiles[coord].infrastructure_present = ["rails"]
	_check(Hub.capacity_multiplier(tile)==1.0, "Disconnected power removes the bonus")
	fake.tiles[coord].infrastructure_present = ["rails","cables"]
	var before: Dictionary = Hub.sites()[0]
	BuildingState.rail_hubs_seeded = true
	var save := JSON.parse_string(JSON.stringify(MatchState.export_state())) as Dictionary
	MatchState.reset(); MatchState.import_state(save)
	_check(BuildingState.rail_hubs_seeded and BuildingState.is_player_owned(BuildingState.get_building(iid)), "Hub ownership and seeding survive JSON save/load")
	_check(Hub.sites()[0].pos==before.pos and is_equal_approx(Hub.sites()[0].yaw,before.yaw), "Depot location survives JSON save/load")
	_check(TransportState.tile_mode_capacity("rail",1,tile)==1200, "Capacity bonus survives save/load")
	var state := Tab._site(tile)
	_check(not state.rail_hub.is_empty() and state.mine.is_empty() and state.others.is_empty(), "Rail Hub has a dedicated tile section")
	var pane := VBoxContainer.new(); panel.add_child(pane)
	Tab._add_rail_hub(panel,pane,state)
	_check(pane.find_child("RailHubBuildingCard",true,false)!=null, "Dedicated hub card builds")
	panel.free(); fake.free(); MatchState.reset(); Modifiers.reset()
