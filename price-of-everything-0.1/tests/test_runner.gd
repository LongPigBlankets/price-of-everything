extends Node
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

func _ready() -> void:
	print("\n==== price-of-everything tests ====")
	_test_scripts_parse()
	_test_widgets_instantiate()
	_test_recipe_row_instantiates()
	await _test_stockpile_legend_label_visible()
	_test_scene_loads()
	await _test_main_scene_instantiates()
	_test_catalog_loaded()
	_test_recipe_requirements()
	_test_menu_icons()
	_test_ports()
	await _test_building_ledger()
	await _test_debug_terminal()
	_test_queue_move()
	_test_move_extras()
	_test_storage_boost()
	_test_queue_sell()
	_test_npc_ports()
	_test_bulk_sell()
	_test_output_market_route()
	_test_transaction_ledger()
	_test_market_buy()
	_test_purchases()
	_test_recipes_producing()
	_test_transfer_helpers()
	_test_output_conservation()
	_test_market_sale_credits()
	_test_owner_costs()
	_test_recurring_sell_multitile()
	_test_auto_sell_goods()
	_test_price_impact()
	_test_buy_price()
	_test_limestone_concrete()
	_test_construction()
	_test_construction_awaiting()
	_test_construction_sourcing()
	_test_construction_cancel()
	await _test_construction_detail_panel()
	print("==== %d passed, %d failed ====\n" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)

func _check(ok: bool, name: String) -> void:
	if ok:
		_passed += 1
		print("  PASS  ", name)
	else:
		_failed += 1
		printerr("  FAIL  ", name)

func _test_storage_boost() -> void:
	MatchState.add_building("b_004", "", "tile_3_3", "Three Diamonds Shipping Corporation")
	_check(Stockpile.get_capacity("tile_3_3") == Stockpile.TILE_CAPACITY + 500,
		"storage_boost raises tile capacity (port = +500)")

func _test_market_sale_credits() -> void:
	# Output routed to market should be sold and its revenue credited on arrival,
	# not silently lost. (Reproduces the "produced but never stockpiled/consumed/sold".)
	MatchState.reset()
	Stockpile.clear_all()
	MatchState.money = 0.0
	var summary := {"transport_paid": 0.0, "money_out": 0.0, "money_in": 0.0,
		"goods_sales_revenue": 0.0, "sold": {}}
	Production._sell_output_to_market("tile_3_8", Catalog.get_good("g_001"), 20, summary)
	# Drive arrivals for a few turns; a deferred sale should eventually credit.
	for _i in range(25):
		Production._process_transport_arrivals(summary)
		if MatchState.money > 0.0:
			break
	_check(MatchState.money > 0.0, "a market-routed output sale credits revenue (money=%.2f)" % MatchState.money)
	_check(summary.goods_sales_revenue > 0.0, "the sale appears in goods_sales_revenue")

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
	_check(MatchState.money < money_before, "queue_buy pays for goods + transport")
	_check(MatchState.get_pending_transport_shipments().size() > ship_before, "queue_buy queues an inbound shipment")
	var rows: Array = MatchState.get_oneoff_transaction_rows()
	_check(rows.size() == t_before + 1 and str(rows[rows.size() - 1].get("type", "")) == "Buy",
		"a buy is logged with type Buy")
	# Best-effort: a big order with little cash buys a partial amount, not nothing.
	MatchState.money = 50.0
	var partial: Dictionary = MatchState.queue_buy("tile_3_8", "g_002", 1000)
	_check(not partial.is_empty() and int(partial.get("qty", 0)) > 0 and int(partial.get("qty", 0)) < 1000,
		"queue_buy buys a partial amount when cash is short")

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
	var duration: int = int(Catalog.get_building(bid).get("build_duration", 0))
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
			_check(panel.get("status_icon_column").visible and panel.get("close_button").visible,
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
	var duration: int = int(Catalog.get_building(bid).get("build_duration", 0))
	for _i in range(duration):
		Construction.tick_turn()
	_check(MatchState.buildings.has(iid) and not Construction.construction_projects.has(iid),
		"awaiting project promotes after securing materials + countdown")
	MatchState.remove_building(iid)

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

func _test_owner_costs() -> void:
	_check(MatchState.is_player_owned({"owner": "player_1"}), "player_1 building is player-owned")
	_check(MatchState.is_player_owned({}), "building with no owner defaults to player-owned")
	_check(not MatchState.is_player_owned({"owner": "Three Diamonds Shipping Corporation"}),
		"NPC-owned building is not player-owned (not charged maintenance)")

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
	MatchState.route_output_to_market("inst_test_market", "g_001")
	_check(MatchState.is_output_market("inst_test_market", "g_001"),
		"route_output_to_market marks the building for market")
	_check(MatchState.get_output_stockpile_destination("inst_test_market", "g_001") == "",
		"a market route reads as no stockpile tile")
	_check(MatchState.sell_mode == mode_before,
		"per-building market route leaves the global sell mode unchanged")

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
	_check(Stockpile.get_capacity("tile_5_10") >= Stockpile.TILE_CAPACITY + 500,
		"port tile capacity raised by the port's storage_boost")

func _test_queue_sell() -> void:
	Stockpile.add("tile_3_8", "g_001", 8)
	var before: int = MatchState.get_pending_transport_shipments().size()
	var summary: Dictionary = MatchState.queue_sell("tile_3_8", {"g_001": 8})
	_check(not summary.is_empty(), "queue_sell returns a summary")
	_check(Stockpile.get_at_tile("tile_3_8", "g_001") == 0, "queue_sell consumes from source")
	_check(str(summary.get("port", "")) != "" and MatchState.get_pending_transport_shipments().size() > before,
		"queue_sell ships to a port")

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
	var before: float = MatchState.money
	var result: String = term._run_command("cash 250")
	_check(absf(MatchState.money - (before + 250.0)) < 0.001, "terminal: cash adds the amount")
	_check("250" in result, "terminal: cash reports the amount")
	_check(term._run_command("bogus").begins_with("unknown"), "terminal: unknown command handled")
	term.queue_free()

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
	_check(int(Catalog.route("tile_12_2", "tile_12_2").turns) == 0, "route same-tile = 0 turns")
	_check(int(Catalog.route("tile_12_2", "tile_13_2").turns) == 1, "route to adjacent tile = 1 turn")

# Smoke: every script we touch must still parse. load() returns null on a parse
# error — this is the check that catches the bug class we couldn't verify by hand.
func _test_scripts_parse() -> void:
	for path in [
		"res://scripts/stockpile_view.gd",
		"res://scripts/infra_grid.gd",
		"res://scripts/tile_info_panel.gd",
		"res://scripts/building_detail_panel.gd",
		"res://scripts/world_map.gd",
		"res://scripts/map_overlay.gd",
		"res://scripts/ds.gd",
		"res://scripts/search_overlay.gd",
		"res://scripts/good_icons.gd",
		"res://scripts/catalog.gd",
		"res://scripts/construct_panel.gd",
		"res://scripts/building_row.gd",
		"res://scripts/recipe_row.gd",
		"res://scripts/logistics_overlay.gd",
		"res://scripts/mapmodes_panel.gd",
		"res://scripts/overlay_legend.gd",
		"res://scripts/debug_terminal.gd",
		"res://scripts/sale_effects.gd",
		"res://scripts/ui_helpers.gd",
		"res://scripts/market_panel.gd",
		"res://scripts/turn_summary.gd",
		"res://scripts/construction.gd",
		"res://scripts/construction_missing_dialog.gd",
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
	var tl = panel.get("title_label") if panel != null else null
	# Guards the theme-cascade fix: DS variations must actually resolve on panels.
	_check(tl != null and tl.get_theme_font_size("font_size") == DS.FS["H1"],
		"DS theme reaches the tile panel (title uses the DS Title font)")
	var ok: bool = panel != null \
		and panel.get("tile_size_chart") != null \
		and panel.get("title_label") != null \
		and panel.get("infrastructure_table") != null \
		and panel.get("close_button") != null \
		and panel.get("tile_image_banner") != null \
		and panel.get("_banner_summary_content") != null \
		and panel.get("_right_scroll_content") != null
	_check(ok, "main.tscn instantiates; TileInfoPanel @onready nodes resolve")
	inst.queue_free()
	await get_tree().process_frame

# Logic: the data CSVs load into the Catalog as expected.
func _test_catalog_loaded() -> void:
	_check(Catalog.all_goods().size() == 40, "Catalog has 40 goods")
	var _all_classed := true
	for g in Catalog.all_goods():
		if str(g.get("transport_class", "")) == "":
			_all_classed = false
	_check(_all_classed, "every loaded good has a transport_class")
	_check(Catalog.all_recipes().size() >= 18, "Catalog promotes a healthy recipe set (>=18)")
	_check(Catalog.all_buildings().size() == 37, "Catalog has 37 buildings")

# Logic: recipe requirements parse correctly (guards the build-mode path that
# silently broke earlier in the merge).
func _test_recipe_requirements() -> void:
	var recipe: Dictionary = Catalog.get_recipe("r_001")
	var reqs: Array = recipe.get("requirements", [])
	var ok: bool = reqs.size() == 1 \
		and reqs[0].get("type", "") == "deposit" \
		and reqs[0].get("value", "") == "coal"
	_check(ok, "r_001 (Coal Mining) requires deposit:coal")
	_check(recipe.get("recipe_type", "") == "extraction", "r_001 recipe_type is extraction")
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

# Logic: the regenerated bottom-menu icons import and load as textures.
func _test_menu_icons() -> void:
	var all_ok := true
	for key in ["resources", "buildings", "map_overlays", "markets", "politics", "construct", "tech"]:
		var path := "res://assets/icons/ui_icons/200/%s.png" % key
		if not (ResourceLoader.exists(path) and load(path) is Texture2D):
			all_ok = false
	_check(all_ok, "bottom-menu icons (200px tier) import and load")
