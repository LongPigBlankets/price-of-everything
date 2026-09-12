extends "res://tests/test_base.gd"
## Transport service, shipments, depots, ports and sea routing.

const FEATURE := "transport"
## Tests that also belong to other features (run under any of their tags).
const TAGS := {
	"_test_transport_service": ["stockpile", "transport"],
	"_test_npc_ports": ["stockpile", "transport"],
	"_test_depot_scheduling_overland_only": ["research", "transport"],
	"_test_transport_congestion": ["research", "transport"],
	"_test_transport_flow_no_double_count": ["research", "transport"],
	"_test_starvation_deeplink_building": ["events", "transport"],
}

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

## Arrival history: the empire view reports how reliably a line delivers, and nothing else
## in the sim remembers a delivery once its goods are in the stockpile. Covers the window
## query, that several shipments landing on one turn count as ONE delivering turn, and the
## save round trip (PackedInt32Array does not survive JSON, so it is rebuilt on load).
func _test_arrival_history() -> void:
	var saved: Dictionary = TransportState.arrival_turns.duplicate(true)
	TransportState.arrival_turns.clear()
	var turn: int = TurnManager.current_turn
	_check(TransportState.arrivals_in_window("tile_9_10", "coal") == 0, "arrivals: nothing recorded reads as zero")

	TransportState.call("_record_arrival", "tile_9_10", "coal")
	_check(TransportState.arrivals_in_window("tile_9_10", "coal") == 1, "arrivals: a delivery is recorded")
	TransportState.call("_record_arrival", "tile_9_10", "coal")
	_check(TransportState.arrivals_in_window("tile_9_10", "coal") == 1,
		"arrivals: two shipments on the same turn are ONE delivering turn")
	_check(TransportState.arrivals_in_window("tile_9_10", "iron_ore") == 0, "arrivals: kept per good")
	_check(TransportState.arrivals_in_window("tile_7_9", "coal") == 0, "arrivals: kept per tile")

	# Turns older than the window fall out of the count.
	TransportState.arrival_turns["tile_9_10|coal"] = PackedInt32Array([turn - 50, turn])
	_check(TransportState.arrivals_in_window("tile_9_10", "coal") == 1, "arrivals: stale turns leave the window")

	# Save round trip.
	var packed: Dictionary = TransportState.call("_arrival_turns_for_save")
	_check((packed["tile_9_10|coal"] as Array).size() == 2, "arrivals: history serialises as plain ints")
	var restored: Dictionary = TransportState.call("_arrival_turns_from_save", packed)
	_check(restored["tile_9_10|coal"] is PackedInt32Array, "arrivals: history rebuilds as PackedInt32Array")
	_check((restored["tile_9_10|coal"] as PackedInt32Array).size() == 2, "arrivals: round trip keeps every turn")
	# A pre-history save must not crash or invent data.
	_check((TransportState.call("_arrival_turns_from_save", null) as Dictionary).is_empty(),
		"arrivals: a save with no history loads empty")

	TransportState.arrival_turns = saved

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
	# Coordinates are comma-separated for the player; the underscore is an internal
	# id separator and read as part of the name on screen.
	_check(Catalog.tile_label("tile_12_2") == "Miney McMineface - (12, 2)", "tile_label uses nickname")
	_check(Catalog.tile_label("tile_5_10") == "Stoneshore Docks - (5, 10)", "tile_label falls back to city_name")
	_check(Catalog.infra_range("roads") == 2, "roads range is 2 tiles/turn")
	_check(Catalog.infra_range("rail") == 4, "rail range is 4 tiles/turn")
	_check(Catalog.all_infrastructure().size() == 5, "Catalog loads 5 infrastructure types")
	_check(Catalog.tile_neighbours("tile_12_2").size() == 6, "interior tile has 6 hex neighbours")
	_check(int(TransportService.route("tile_12_2", "tile_12_2").get("turns", -1)) == 0, "route same-tile = 0 turns")
	_check(int(TransportService.route("tile_12_2", "tile_13_2").get("turns", -1)) == 1, "route to adjacent tile = 1 turn")

func _test_transport_service() -> void:
	var route: Dictionary = TransportService.route("tile_12_2", "tile_13_2", "g_001")
	_check(int(route.get("turns", -1)) == 1, "TransportService routes adjacent tiles")
	var route_cost := TransportService.transport_cost_for_route("g_001", 10, route)
	var route_breakdown := TransportService.transport_cost_breakdown_for_route("g_001", 10, route)
	var breakdown_total := 0.0
	for amount in route_breakdown.values():
		breakdown_total += float(amount)
	_check(absf(route_cost - breakdown_total) < 0.0001,
		"TransportService route breakdown reconciles to the actual freight charge")
	var quote: Dictionary = TransportService.quote_manifest("tile_12_2", "tile_13_2", {"g_001": 10})
	_check(int(quote.get("turns", -1)) == 1 and float(quote.get("cost", 0.0)) > 0.0,
		"TransportService quotes a manifest with turns and cost")
	var buy_quote: Dictionary = TransportService.quote_market_buy("tile_3_8", "g_001", 10, false)
	_check(str(buy_quote.get("port", "")) == "tile_5_10"
		and absf(float(buy_quote.get("cost", 0.0)) - (float(buy_quote.get("goods_cost", 0.0)) + float(buy_quote.get("transport_cost", 0.0)))) < 0.01,
		"TransportService quotes a market buy through the nearest port")
	var covered_buy: Dictionary = TransportService.quote_market_buy("tile_3_8", "g_001", 10, true)
	_check(int(covered_buy.get("turns", 0)) == 1
		and absf(float(covered_buy.get("transport_cost", -1.0)) - float(covered_buy.get("sea_transport_cost", -2.0))) < 0.01,
		"TransportService applies covered seaport buy quotes while retaining the port charge")
	var covered_sell: Dictionary = TransportService.quote_market_sell("tile_3_8", {"g_001": 10}, {"g_001": true})
	_check(int(covered_sell.get("turns", 0)) == 1 and float(covered_sell.get("transport_cost", -1.0)) == 0.0,
		"TransportService applies covered seaport sell quotes")
	var src := "tile_12_2"
	var dst := "tile_13_2"
	var safe_liquid := "g_009"
	var hazard_liquid := "g_065"
	# Fluids may now travel overland by road or rail (owner ruling 2026-08-09), so "no pipeline"
	# only means "stranded" when there is no land link either. Strip both ends back to bare tiles
	# so the assertions below test the rule they claim rather than whatever the CSV baseline —
	# or an earlier test in this suite — happened to leave on these tiles.
	for _t in [src, dst]:
		for _m in ["roads", "rail", "pipes", "reinf_pipes"]:
			Catalog.remove_tile_infrastructure(str(_t), str(_m))
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
	TransportState.pending_transport_shipments.clear()
	Stockpile.add(src, safe_liquid, 5)
	var blocked_move := TransportState.queue_move(src, dst, {safe_liquid: 5})
	_check(blocked_move.is_empty()
			and Stockpile.get_at_tile(src, safe_liquid) == 5
			and TransportState.pending_transport_shipments.is_empty(),
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
	# The new escape route: no pipe anywhere, but a rail link on both ends carries the fluid —
	# at FLUID_OVERLAND_COST_MULT, which is what stops it replacing pipework outright.
	Catalog.add_tile_infrastructure(src, "rails")
	Catalog.add_tile_infrastructure(dst, "rails")
	var rail_fluid := TransportService.route(src, dst, safe_liquid)
	var rail_fluid_legs: Array = rail_fluid.get("legs", [])
	_check(TransportService.route_is_reachable(rail_fluid)
			and not rail_fluid_legs.is_empty()
			and str((rail_fluid_legs[0] as Dictionary).get("mode", "")) == "rail",
		"safe liquid takes the rail when there is no pipe")
	var hazard_rail := TransportService.route(src, dst, hazard_liquid)
	_check(TransportService.route_is_reachable(hazard_rail),
		"hazard liquid takes the rail too — the tanker is certified, the pipe is not the only way")
	Catalog.remove_tile_infrastructure(src, "rails")
	Catalog.remove_tile_infrastructure(dst, "rails")
	# A liquid/gas can only be BOUGHT onto a port tile with a compatible terminal. This closes
	# the bare-port same-tile loophole while allowing road/rail tankers as well as pipework.
	var a_port := TransportService.nearest_port_tile(src)
	# "Unpiped" now has to mean unlinked: a road or rail on the port tile is a legitimate way to
	# land a fluid since the overland ruling, so strip those too before testing the pipe rule.
	var port_had: Array = []
	if a_port != "":
		for _m in ["roads", "rail"]:
			if Catalog.tile_has_infrastructure(a_port, str(_m)):
				port_had.append(str(_m))
				Catalog.remove_tile_infrastructure(a_port, str(_m))
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
		# …and the overland route lands it without any pipe at all, which is the new rule.
		Catalog.add_tile_infrastructure(a_port, "rails")
		_check(not TransportService.quote_market_buy(a_port, safe_liquid, 3, false).is_empty()
				and not TransportService.quote_market_buy(a_port, hazard_liquid, 3, false).is_empty(),
			"either fluid can be landed at a railed port tile with no pipework")
		Catalog.remove_tile_infrastructure(a_port, "rails")
	for _m in port_had:
		Catalog.add_tile_infrastructure(a_port, str(_m))
	# Building diagnostics distinguish an expensive tanker route from no route at all.
	# Use a port tile so each terminal state is isolated to one tile (same-tile quotes have no legs).
	var diag_port := TransportService.nearest_port_tile(src)
	var diag_port_had: Array = []
	for _m in ["roads", "rail", "pipes", "reinf_pipes"]:
		if Catalog.tile_has_infrastructure(diag_port, str(_m)):
			diag_port_had.append(str(_m))
			Catalog.remove_tile_infrastructure(diag_port, str(_m))
	var fluid_building := {"instance_id": "diag_fluid_input", "tile_id": diag_port}
	var fluid_recipe := {"inputs": [{"good_id": hazard_liquid, "internal_name": "industrial_acids", "qty": 1}], "outputs": [], "energy_req": 0}
	Catalog.add_tile_infrastructure(diag_port, "roads")
	var fluid_rows: Array = BuildingReadout.diagnostics(fluid_building, fluid_recipe, {}, false)
	var found_cheaper_pipe := false
	var found_false_pipe_fault := false
	for row in fluid_rows:
		found_cheaper_pipe = found_cheaper_pipe or (str((row as Dictionary).get("tone", "")) == "warn"
				and str((row as Dictionary).get("label", "")) == "Transport could be cheaper using Reinforced Pipeline")
		found_false_pipe_fault = found_false_pipe_fault or str((row as Dictionary).get("label", "")).begins_with("No transport route")
	_check(found_cheaper_pipe and not found_false_pipe_fault,
		"building diagnostics: a valid hazardous road route is amber pipe advice, not a red blocker")
	Catalog.remove_tile_infrastructure(diag_port, "roads")
	fluid_rows = BuildingReadout.diagnostics(fluid_building, fluid_recipe, {}, false)
	var found_blocked_route := false
	for row in fluid_rows:
		found_blocked_route = found_blocked_route or (str((row as Dictionary).get("tone", "")) == "bad"
				and str((row as Dictionary).get("label", "")).begins_with("No transport route"))
	_check(found_blocked_route,
		"building diagnostics: a hazardous input with no road, rail or pipe route remains red")
	Catalog.add_tile_infrastructure(diag_port, "reinf_pipes")
	fluid_rows = BuildingReadout.diagnostics(fluid_building, fluid_recipe, {}, false)
	var found_pipe_advice := false
	for row in fluid_rows:
		found_pipe_advice = found_pipe_advice or str((row as Dictionary).get("label", "")).contains("Pipeline")
	_check(not found_pipe_advice,
		"building diagnostics: a suitable reinforced-pipe terminal clears the transport warning")

	# The same distinction applies while construction materials are being delivered.
	var cd_constr := {"tile_id": diag_port, "materials": [
		{"good_id": hazard_liquid, "name": "Industrial Acids", "secured": false},
		{"good_id": "g_001", "name": "Coal", "secured": false},
	]}
	Catalog.remove_tile_infrastructure(diag_port, "reinf_pipes")
	var cd_rows := BuildingReadout.construction_diagnostics(cd_constr)
	_check(cd_rows.size() == 1 and str((cd_rows[0] as Dictionary).get("tone", "")) == "bad"
			and "no transport route" in str((cd_rows[0] as Dictionary).get("label", "")).to_lower(),
		"construction diagnostics: flags the undeliverable hazard-liquid material, not the solid")
	var cd_secured := {"tile_id": diag_port, "materials": [{"good_id": hazard_liquid, "name": "Industrial Acids", "secured": true}]}
	_check(BuildingReadout.construction_diagnostics(cd_secured).is_empty(),
		"construction diagnostics: a secured material raises no blocker")
	Catalog.add_tile_infrastructure(diag_port, "roads")
	cd_rows = BuildingReadout.construction_diagnostics(cd_constr)
	_check(cd_rows.size() == 1 and str((cd_rows[0] as Dictionary).get("tone", "")) == "warn",
		"construction diagnostics: a road-deliverable fluid gets amber pipe advice")
	Catalog.add_tile_infrastructure(diag_port, "reinf_pipes")
	_check(BuildingReadout.construction_diagnostics(cd_constr).is_empty(),
		"construction diagnostics: a reinforced pipe on the site clears the blocker")
	for _m in ["roads", "rail", "pipes", "reinf_pipes"]:
		Catalog.remove_tile_infrastructure(diag_port, str(_m))
	for _m in diag_port_had:
		Catalog.add_tile_infrastructure(diag_port, str(_m))
	Stockpile.clear_all()
	TransportState.pending_transport_shipments.clear()

func _test_transport_breakdown_hides_unused_modes() -> void:
	var panel = load("res://scenes/money_panel.tscn").instantiate()
	add_child(panel)
	panel._set_transport_expanded(true)
	panel._render_transport_breakdown(12.0, {"rail": 12.0})
	var no_infra_row := panel.find_child("TransportCostRow_nothing", true, false) as Control
	var rail_row := panel.find_child("TransportCostRow_rail", true, false) as Control
	_check(no_infra_row != null and not no_infra_row.visible and rail_row != null and rail_row.visible,
		"balance transport: a rail-only turn hides the obsolete No infrastructure row")
	panel._render_transport_breakdown(8.0, {"nothing": 8.0})
	_check(no_infra_row.visible and not rail_row.visible,
		"balance transport: only modes actually charged this turn remain in the breakdown")
	panel.free()


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

func _npc_port_on(tile_id: String) -> bool:
	for iid in BuildingState.tile_buildings.get(tile_id, []):
		var inst: Dictionary = BuildingState.get_building(iid)
		if str(inst.get("building_id", "")) == "b_004" and str(inst.get("owner", "")) == "Three Diamonds Shipping Corporation":
			return true
	return false


func _test_npc_ports() -> void:
	# The main scene's _ready places the 4 NPC ports; verify one landed + is NPC-owned.
	# Boot the scene ourselves when an earlier test has cleared the board, so this holds
	# on its own and under any tag filter.
	if not _npc_port_on("tile_5_10"):
		await _boot_main_scene_once()
	_check(_npc_port_on("tile_5_10"), "NPC port placed on a port tile (b_004, Three Diamonds)")
	_check(Stockpile.get_capacity("tile_5_10") >= Stockpile.TILE_CAPACITY + 600,
		"port tile capacity raised by the port's storage_boost")

func _test_depot_scheduling_overland_only() -> void:
	# Depot Scheduling trims road and rail only. The plain `transport_cost` domain is applied
	# after the legs are summed and cannot tell road from pipe, so this rides its own domain
	# scaled by the overland share of the route.
	MatchState.reset()
	var road := {"reachable": true, "turns": 2, "legs": [{"mode": "roads"}, {"mode": "roads"}]}
	var pipe := {"reachable": true, "turns": 2, "legs": [{"mode": "pipes"}, {"mode": "pipes"}]}
	var road_before: float = TransportService.transport_cost_for_route("g_001", 100, road)
	var pipe_before: float = TransportService.transport_cost_for_route("g_017", 100, pipe)
	Modifiers.add({"id": "test_depot", "domain": "road_rail_transport_cost", "pct": -10.0,
		"label": "test", "source": "test"})
	var road_after: float = TransportService.transport_cost_for_route("g_001", 100, road)
	var pipe_after: float = TransportService.transport_cost_for_route("g_017", 100, pipe)
	Modifiers.remove("test_depot")
	_check(road_before > 0.0 and is_equal_approx(road_after, road_before * 0.9),
		"depot scheduling: an all-road haul is 10%% cheaper (%.3f -> %.3f)" % [road_before, road_after])
	_check(pipe_before <= 0.0 or is_equal_approx(pipe_after, pipe_before),
		"depot scheduling: a pipe haul is untouched")

func _test_logistics_shipping_line() -> void:
	# The three shipping unlocks trim the ad valorem RELATIVELY. Percentage points against a 3%
	# base would overshoot to almost nothing, which is the collapse the schedule replaced.
	MatchState.reset()
	TurnManager.current_turn = 40                       # past the step, so the base is the full rate
	var base: float = EconomyConfig.seaport_ad_valorem_rate(TurnManager.current_turn)
	var port := "tile_5_10"
	var before: float = TransportState.seaport_insurance_rate(port)
	_check(is_equal_approx(before, base),
		"shipping line: an unteched company pays the scheduled rate (%.2f%%)" % (100.0 * before))
	for title in ["Groupage Contracts", "Multimodal Containerized Freight", "Port Network Acquisition"]:
		ResearchState.grant_unlock(title)
	var after: float = TransportState.seaport_insurance_rate(port)
	_check(is_equal_approx(after, base * 0.6),
		"shipping line: all three together cut the rate 40%% (%.2f%% -> %.2f%%)"
			% [100.0 * before, 100.0 * after])
	_check(after > 0.0, "shipping line: relief never reaches zero — freight always costs something")

	# "Through EVERY port" is a reach condition: one busy port is not enough.
	MatchState.reset()
	ResearchState._port_sales_by_port = {"tile_5_10": 9999}
	var one_port := {"action": "Sell Through Every Port", "object": "ports", "qty": 500}
	_check(not ResearchState._live_condition_met(one_port),
		"shipping line: exporting through a single port does not satisfy 'every port'")
	for port_def in Catalog.all_ports():
		ResearchState._port_sales_by_port[str(port_def.get("tile_id", ""))] = 500
	_check(ResearchState._live_condition_met(one_port),
		"shipping line: reaching all %d ports satisfies it" % Catalog.all_ports().size())

	# "Own a port at level N" reads the building's real level.
	MatchState.reset()
	var lvl := {"action": "Own Port At Level", "object": "ports", "qty": 2}
	BuildingState.buildings["inst_port"] = {
		"instance_id": "inst_port", "building_id": "b_004", "recipe_id": "",
		"tile_id": "tile_5_10", "level": 1,
	}
	_check(not ResearchState._live_condition_met(lvl), "shipping line: a level-1 port does not qualify")
	BuildingState.buildings["inst_port"]["level"] = 2
	_check(ResearchState._live_condition_met(lvl), "shipping line: a level-2 port does")
	BuildingState.buildings.erase("inst_port")
	TurnManager.current_turn = 1

func _test_port_ad_valorem_schedule() -> void:
	MatchState.reset()
	# Port charging is ad valorem only, on a turn schedule: 0.5% while learning, 3% from t31.
	# The flat per-good fee is retired — it made quantity free, which is why freight collapsed
	# to 0.3% of revenue late. See docs/early-game-onboarding-spec.md §4.2b.
	_check(is_equal_approx(EconomyConfig.SEAPORT_BASE_FEE_PER_GOOD, 0.0),
		"port: the flat per-good fee is retired")
	_check(is_equal_approx(EconomyConfig.seaport_ad_valorem_rate(1), EconomyConfig.SEAPORT_AD_VALOREM_EARLY)
		and is_equal_approx(EconomyConfig.seaport_ad_valorem_rate(30), EconomyConfig.SEAPORT_AD_VALOREM_EARLY),
		"port: turns 1-30 charge the learning-window rate (%.1f%%)"
			% (100.0 * EconomyConfig.SEAPORT_AD_VALOREM_EARLY))
	_check(is_equal_approx(EconomyConfig.seaport_ad_valorem_rate(31), EconomyConfig.SEAPORT_AD_VALOREM_LATE)
		and is_equal_approx(EconomyConfig.seaport_ad_valorem_rate(200), EconomyConfig.SEAPORT_AD_VALOREM_LATE),
		"port: turn 31 onwards charges the full rate (%.1f%%)"
			% (100.0 * EconomyConfig.SEAPORT_AD_VALOREM_LATE))
	_check(EconomyConfig.SEAPORT_AD_VALOREM_LATE > EconomyConfig.SEAPORT_AD_VALOREM_EARLY,
		"port: the rate rises rather than falls at the step")

	MatchState.ruleset = {"name": "tutorial", "tutorial_enabled": true}
	TurnManager.current_turn = 31
	_check(is_equal_approx(TransportState.seaport_insurance_rate(""), EconomyConfig.SEAPORT_AD_VALOREM_EARLY),
		"tutorial port: no fee jump at turn 31")
	MatchState.ruleset["tutorial_enabled"] = false
	var saved: Dictionary = MatchState.export_state()
	MatchState.reset()
	MatchState.import_state(saved)
	TurnManager.current_turn = 300
	_check(is_equal_approx(TransportState.seaport_insurance_rate(""), EconomyConfig.SEAPORT_AD_VALOREM_EARLY),
		"tutorial port: introductory rate survives completion and save reload at turn 300")
	MatchState.reset()
	_check(is_equal_approx(TransportState.seaport_insurance_rate(""), EconomyConfig.SEAPORT_AD_VALOREM_LATE),
		"campaign port: standard late rate restored in a new game")
	TurnManager.current_turn = 1

func _test_transport_congestion() -> void:
	# Throughput soft cap: routes over a link's capacity pay a transport-cost penalty.
	Modifiers.reset()
	MatchState.reset()
	TransportState.pending_transport_shipments.clear()
	TransportState._last_link_flow.clear()
	# Capacity is explicitly calibrated per mode and infrastructure level.
	_check(absf(TransportState.tile_mode_capacity("roads", 1) - 300.0) < 0.001, "roads L1 capacity = 300")
	_check(absf(TransportState.tile_mode_capacity("roads", 2) - 500.0) < 0.001, "roads L2 capacity = 500")
	_check(absf(TransportState.tile_mode_capacity("roads", 3) - 750.0) < 0.001, "roads L3 capacity = 750")
	_check(absf(TransportState.tile_mode_capacity("rail", 1) - 600.0) < 0.001, "rail L1 capacity = 600")
	_check(absf(TransportState.tile_mode_capacity("rail", 2) - 1200.0) < 0.001, "rail L2 capacity = 1200")
	_check(absf(TransportState.tile_mode_capacity("rail", 3) - 2000.0) < 0.001, "rail L3 capacity = 2000")
	_check(absf(TransportState.tile_mode_capacity("pipes", 1) - 250.0) < 0.001, "pipes L1 capacity = 250")
	_check(absf(TransportState.tile_mode_capacity("pipes", 2) - 600.0) < 0.001, "pipes L2 capacity = 600")
	_check(absf(TransportState.tile_mode_capacity("pipes", 3) - 1200.0) < 0.001, "pipes L3 capacity = 1200")
	_check(absf(TransportState.tile_mode_capacity("reinf_pipes", 3) - 1200.0) < 0.001, "reinforced pipes match pipe capacity")
	_check(absf(TransportState.tile_mode_capacity("cables", 1)) < 0.001, "an uncapped mode (cables) reports 0")
	# Throughput research raises capacity: Heavy Freight Corridors +25% rail.
	ResearchState.grant_unlock("Heavy Freight Corridors")
	_check(absf(TransportState.tile_mode_capacity("rail", 1) - 750.0) < 0.001,
		"Heavy Freight Corridors raises rail L1 capacity 600 → 750")

	var route := {"tiles": ["tile_a", "tile_b"],
		"legs": [{"mode": "roads", "from": "tile_a", "to": "tile_b"}]}
	_check(TransportState.route_congestion_tier(route) == 0, "no flow → tier 0 (no penalty)")

	# Helper to load a flow level onto the road link and snapshot it.
	var load_flow := func(units: int) -> void:
		TransportState.pending_transport_shipments.clear()
		TransportState.pending_transport_shipments.append({"qty": units, "good_id": "coal",
			"turns_remaining": 2, "tiles": ["tile_a", "tile_b"],
			"legs": [{"mode": "roads", "from": "tile_a", "to": "tile_b"}]})
		TransportState.update_transport_congestion()
	# roads L1 cap = 300; tier-2 threshold = cap + base L1 cap = 600.
	load_flow.call(250)
	_check(TransportState.route_congestion_tier(route) == 0, "250 under cap 300 → tier 0")
	load_flow.call(450)
	_check(TransportState.route_congestion_tier(route) == 1, "450 over cap 300 (≤ cap+L1 600) → tier 1 (+100%)")
	load_flow.call(700)
	_check(TransportState.route_congestion_tier(route) == 2, "700 over cap+L1 600 → tier 2 (+200%)")

	# MARGINAL charging: only the units above the congested link's remaining capacity pay
	# the surcharge. A clear link has full headroom; an over-cap link has none.
	load_flow.call(250)
	_check(int(TransportState.route_congestion(route).get("headroom", -1)) == 0,
		"an uncongested route reports no penalty band at all (tier 0)")
	load_flow.call(450)
	var cong: Dictionary = TransportState.route_congestion(route)
	_check(int(cong.get("tier", 0)) == 1 and int(cong.get("headroom", -1)) == 0,
		"a link already 150 over its 300 cap has zero headroom — every unit pays")
	# A link UNDER cap but pushed over by this turn's own flow keeps its remaining headroom.
	load_flow.call(280)
	_check(int(TransportState.route_congestion(route).get("tier", 0)) == 0,
		"280 under the 300 cap stays clear — headroom only matters once a link is over")

	Modifiers.reset()
	MatchState.reset()
	TransportState.pending_transport_shipments.clear()
	TransportState._last_link_flow.clear()

## transport_link_flow() must count a shipment's units against a (tile, mode) link
## exactly ONCE, no matter how many consecutive legs of the SAME mode share that
## tile as a boundary. A 4-tile, 4-leg same-mode route touches its 3 internal tiles
## (pass-through: goods enter AND exit) from TWO adjacent legs each, and its two end
## tiles (origin: goods exiting; destination: goods landing) from one leg each — all
## five positions must read the same qty, not doubled at the internal ones.
func _test_transport_flow_no_double_count() -> void:
	Modifiers.reset()
	MatchState.reset()
	TransportState.pending_transport_shipments.clear()
	TransportState._last_link_flow.clear()

	var qty := 50
	var same_mode_route := func(mode: String) -> void:
		TransportState.pending_transport_shipments.clear()
		TransportState.pending_transport_shipments.append({
			"qty": qty, "good_id": "coal", "turns_remaining": 3,
			"tiles": ["t0", "t1", "t2", "t3", "t4"],
			"legs": [
				{"mode": mode, "from": "t0", "to": "t1"},
				{"mode": mode, "from": "t1", "to": "t2"},
				{"mode": mode, "from": "t2", "to": "t3"},
				{"mode": mode, "from": "t3", "to": "t4"},
			],
		})
		var flow := TransportState.transport_link_flow()
		_check(int(flow.get("t0|%s" % mode, -1)) == qty,
			"%s: origin tile (goods exiting) counts %d once" % [mode, qty])
		_check(int(flow.get("t1|%s" % mode, -1)) == qty,
			"%s: pass-through tile counts %d once, not doubled (enters + exits)" % [mode, qty])
		_check(int(flow.get("t2|%s" % mode, -1)) == qty,
			"%s: pass-through tile counts %d once, not doubled (enters + exits)" % [mode, qty])
		_check(int(flow.get("t3|%s" % mode, -1)) == qty,
			"%s: pass-through tile counts %d once, not doubled (enters + exits)" % [mode, qty])
		_check(int(flow.get("t4|%s" % mode, -1)) == qty,
			"%s: destination tile (goods landing) counts %d once" % [mode, qty])

	same_mode_route.call("roads")
	same_mode_route.call("pipes")
	same_mode_route.call("reinf_pipes")

	# A mode SWITCH mid-route (roads -> rail at t1) is NOT this bug: the transfer
	# tile legitimately draws on two separate capacity pools, so it should
	# correctly appear under BOTH keys, each at the full qty — not deduped away.
	TransportState.pending_transport_shipments.clear()
	TransportState.pending_transport_shipments.append({
		"qty": qty, "good_id": "coal", "turns_remaining": 2,
		"tiles": ["t0", "t1", "t2"],
		"legs": [
			{"mode": "roads", "from": "t0", "to": "t1"},
			{"mode": "rail", "from": "t1", "to": "t2"},
		],
	})
	var mixed_flow := TransportState.transport_link_flow()
	_check(int(mixed_flow.get("t1|roads", -1)) == qty,
		"mode switch: the transfer tile's roads leg still counts %d" % qty)
	_check(int(mixed_flow.get("t1|rail", -1)) == qty,
		"mode switch: the transfer tile's rail leg ALSO counts %d — separate capacity pool, correctly not deduped" % qty)

	Modifiers.reset()
	MatchState.reset()
	TransportState.pending_transport_shipments.clear()
	TransportState._last_link_flow.clear()

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

## The port spurs used to be Bezier curves aimed straight at the harbour, so they cut across
## headlands and callers sailed overland. They are sea paths now. Driven here on a SYNTHETIC
## grid rather than the real map, so the test says something about the router itself: given a
## wall of land between two points, does it go round, and does every step stay on water?
func _test_sea_path_goes_round_land() -> void:
	var ships := preload("res://scripts/port_ship_visuals.gd").new()
	var cols := 40
	var rows := 40
	var grid := PackedByteArray()
	grid.resize(cols * rows)
	grid.fill(1)
	# A peninsula reaching down from the top, leaving a gap along the bottom rows.
	for r in 30:
		for c in range(18, 23):
			grid[r * cols + c] = 0
	ships.set("_sea_navigable", grid)
	ships.set("_sea_cols", cols)
	ships.set("_sea_rows", rows)
	ships.set("_sea_origin", Vector2.ZERO)
	var cell: float = ships.SEA_CELL
	var from_world := Vector2(5.0 * cell, 5.0 * cell)
	var to_world := Vector2(35.0 * cell, 5.0 * cell)
	var path: PackedVector2Array = ships._sea_path(from_world, to_world)
	_check(path.size() >= 2, "sea path: a route exists round the peninsula (%d points)"
		% path.size())
	if path.size() >= 2:
		_check(path[0].distance_to(from_world) < 0.01, "sea path: starts where asked")
		_check(path[path.size() - 1].distance_to(to_world) < 0.01, "sea path: ends where asked")
		# Every sample on land is a caller drawn over a hill.
		var on_land := 0
		var deepest := 0.0
		for i in range(path.size() - 1):
			var span := path[i].distance_to(path[i + 1])
			var steps := maxi(int(span / 10.0), 1)
			for k in range(steps + 1):
				var at := path[i].lerp(path[i + 1], float(k) / float(steps))
				deepest = maxf(deepest, at.y)
				var gc := int(at.x / cell)
				var gr := int(at.y / cell)
				if gc >= 0 and gr >= 0 and gc < cols and gr < rows:
					if grid[gr * cols + gc] == 0:
						on_land += 1
		_check(on_land == 0, "sea path: no sample crosses land (%d)" % on_land)
		# It cannot have gone straight: the only water is south of the peninsula.
		_check(deepest > 29.0 * cell,
			"sea path: routes south round the headland (reached y %.0f)" % deepest)
	# A goal walled off from the start yields no route at all, so the caller draws nothing
	# rather than something wrong.
	for r in rows:
		for c in range(18, 23):
			grid[r * cols + c] = 0
	ships.set("_sea_navigable", grid)
	var blocked: PackedVector2Array = ships._sea_path(from_world, to_world)
	_check(blocked.is_empty(), "sea path: an unreachable harbour returns no route (%d)"
		% blocked.size())
	ships.free()


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

func _test_fluids_by_road_and_rail() -> void:
	var water := "g_009"      # safe_liquid — rides ordinary pipework
	var chlorine := "g_012"   # hazard_liquid — the one class normal pipes refuse
	var coal := "g_001"       # solid, for the unchanged-behaviour control

	# 1. The premium, straight off the table.
	_check(is_equal_approx(EconomyConfig.fluid_overland_mult(water, "rail"), 3.0)
		and is_equal_approx(EconomyConfig.fluid_overland_mult(water, "roads"), 6.0),
		"fluids overland: safe fluid pays 3x by rail, 6x by road")
	_check(is_equal_approx(EconomyConfig.fluid_overland_mult(chlorine, "rail"), 5.0)
		and is_equal_approx(EconomyConfig.fluid_overland_mult(chlorine, "roads"), 10.0),
		"fluids overland: hazardous fluid pays 5x by rail, 10x by road")
	_check(is_equal_approx(EconomyConfig.fluid_overland_mult(water, "pipes"), 0.0),
		"fluids overland: a pipe leg is not an overland leg (caller keeps the normal multiplier)")

	# 2. Cost: one rail leg against one pipe leg, same good, same quantity.
	var pipe_route := {"legs": [{"mode": "pipes"}]}
	var rail_route := {"legs": [{"mode": "rail"}]}
	var road_route := {"legs": [{"mode": "roads"}]}
	var piped: float = EconomyConfig.transport_cost_for_route(water, 100, pipe_route)
	_check(piped > 0.0 and is_equal_approx(
			EconomyConfig.transport_cost_for_route(water, 100, rail_route), piped * 3.0),
		"fluids overland: a rail leg costs exactly 3x the same pipe leg")
	_check(is_equal_approx(
			EconomyConfig.transport_cost_for_route(water, 100, road_route), piped * 6.0),
		"fluids overland: a road leg costs exactly 6x the same pipe leg")
	var cl_piped: float = EconomyConfig.transport_cost_for_route(chlorine, 100, pipe_route)
	_check(is_equal_approx(
			EconomyConfig.transport_cost_for_route(chlorine, 100, rail_route), cl_piped * 5.0),
		"fluids overland: hazardous by rail is 5x its reinforced-pipe leg")
	# A solid is untouched: rail stays the half-price mode it always was.
	var coal_road: float = EconomyConfig.transport_cost_for_route(coal, 100, road_route)
	_check(is_equal_approx(
			EconomyConfig.transport_cost_for_route(coal, 100, rail_route), coal_road * 0.5),
		"fluids overland: solids are unaffected — rail is still half of road")

	# 3. Routing. A straight chain of tiles: column+1 is a neighbour in both hex parities.
	var saved_infra: Dictionary = Catalog._tile_infra.duplicate(true)
	var chain: Array = []
	for col in range(5, 11):
		chain.append("tile_%d_5" % col)
	var src: String = str(chain[0])
	var dst: String = str(chain[chain.size() - 1])

	# Pipes AND rail on every tile of the chain: the fluid must still choose the pipe.
	Catalog.reset_runtime_infrastructure()
	for t in chain:
		Catalog.add_tile_infrastructure(str(t), "pipes")
		Catalog.add_tile_infrastructure(str(t), "rails")
	Catalog._route_cache.clear()
	var water_legs: Array = Catalog.route(src, dst, water).get("legs", [])
	var all_piped := not water_legs.is_empty()
	for leg in water_legs:
		if not EconomyConfig.PIPE_MODES.has(str((leg as Dictionary).get("mode", ""))):
			all_piped = false
	_check(all_piped, "fluids overland: with pipe and rail side by side, a fluid still takes the pipe")
	# Solids prefer rail over bare ground on equal-time routes, and never use pipes.
	var coal_legs: Array = Catalog.route(src, dst, coal).get("legs", [])
	var coal_off_pipe := not coal_legs.is_empty()
	for leg in coal_legs:
		if EconomyConfig.PIPE_MODES.has(str((leg as Dictionary).get("mode", ""))):
			coal_off_pipe = false
	_check(coal_off_pipe, "fluids overland: a solid over the same chain never takes the pipe")

	# Rail only: the fluid now travels where it previously could not move at all.
	Catalog.reset_runtime_infrastructure()
	for t in chain:
		Catalog.add_tile_infrastructure(str(t), "rails")
	Catalog._route_cache.clear()
	var stranded: Dictionary = Catalog.route(src, dst, water)
	var legs2: Array = stranded.get("legs", [])
	var by_rail := not legs2.is_empty()
	for leg in legs2:
		if str((leg as Dictionary).get("mode", "")) != "rail":
			by_rail = false
	_check(by_rail and int(stranded.get("turns", 1 << 30)) < (1 << 30),
		"fluids overland: with rail but no pipe, a fluid routes by rail instead of being stranded")

	Catalog._tile_infra = saved_infra
	Catalog._route_cache.clear()
