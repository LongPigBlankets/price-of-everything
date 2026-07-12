extends Node2D
## Phase-1 verification for the redesigned Building Detail v2 panel + the `swap bdp` toggle.
## Loads the real main scene, places a factory running a real recipe (r_009 Motor Manufacture),
## seeds inputs + a synthetic CostSolver result (so the emphasised cost-to-produce block shows
## real, RAG-coloured numbers for two outputs without committing a turn — which would pop the
## turn-summary/victory/capacity dialogs). Screenshots the classic panel and the v2 panel.
##   Godot --path . res://tools/bdp_v2_shot.tscn --quit-after 1200
## Writes /tmp/poe_bdp_v1.png and /tmp/poe_bdp_v2.png.

var _wm

func _ready() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	_wm = packed.instantiate()
	add_child(_wm)
	await _settle(140)
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		cam.edge_pan_enabled = false

	var building := _pick_building()
	if building.is_empty():
		print("[BDP_V2_SHOT] no player building found — aborting")
		get_tree().quit(1)
		return
	# Open the tile view panel too, so the detail panel can match its height.
	var coord: Vector2i = _wm.terrain_layer.id_to_coord("tile_5_10")
	var tile_data: Dictionary = _wm.terrain_layer.tiles.get(coord, {})
	if _wm.info_panel != null and not tile_data.is_empty():
		_wm.info_panel.show_tile(tile_data)
	await _settle(10)

	# Phase 3: with no `swap bdp`, opening a building should route to v2 by default.
	_wm._open_building_detail(building)
	await _settle(8)
	print("[BDP_V2_SHOT] default: use_bdp_v2=%s  v2.visible=%s  v1.visible=%s" % [
		str(MatchState.use_bdp_v2), str(_wm.building_panel_v2.visible), str(_wm.building_panel.visible)])
	_wm._hide_building_detail()

	# v1 (classic) — reachable via the fallback toggle
	MatchState.set_use_bdp_v2(false)
	_wm._open_building_detail(building)
	await _settle(12)
	get_viewport().get_texture().get_image().save_png("/tmp/poe_bdp_v1.png")
	print("[BDP_V2_SHOT] saved /tmp/poe_bdp_v1.png")

	# Seed two output modifiers so the output pill shows the struck base + effective qty
	# (green outline, net positive) and the diagnostics "See all modifiers" accordion has rows.
	Modifiers.add({"domain": "recipe_output", "target": "*", "pct": 15.0, "label": "Assembly-line optimisation"})
	Modifiers.add({"domain": "recipe_output", "target": "*", "pct": -6.0, "label": "Ageing machinery"})

	# v2 (redesign) — flip the flag exactly as `swap bdp` does
	MatchState.set_use_bdp_v2(true)
	_wm._open_building_detail(building)
	await _settle(20)
	get_viewport().get_texture().get_image().save_png("/tmp/poe_bdp_v2.png")
	print("[BDP_V2_SHOT] saved /tmp/poe_bdp_v2.png")

	var v2p = _wm.building_panel_v2
	# scroll to the diagnostics band and expand the modifier accordion
	if v2p != null and v2p._scroll != null:
		v2p._scroll.scroll_vertical = 560
		await _settle(6)
		for b in _all_buttons(v2p):
			if str(b.text).findn("See all modifiers") >= 0:
				b.emit_signal("pressed")
				break
		await _settle(6)
		get_viewport().get_texture().get_image().save_png("/tmp/poe_bdp_v2_diagnostics.png")
		print("[BDP_V2_SHOT] saved /tmp/poe_bdp_v2_diagnostics.png")
		v2p._scroll.scroll_vertical = 0

	# scroll the v2 body to the bottom to reveal Routing (interactive) + Labour
	if v2p != null and v2p._scroll != null:
		v2p._scroll.scroll_vertical = 4000
		await _settle(8)
		get_viewport().get_texture().get_image().save_png("/tmp/poe_bdp_v2_routing.png")
		print("[BDP_V2_SHOT] saved /tmp/poe_bdp_v2_routing.png")
		v2p._scroll.scroll_vertical = 0

	# Route the output to MARKET and re-capture the economics — this exercises the SELLING path
	# (Sale value / turn + Output transport / turn + Net including the sale), vs the held path above.
	var motor_gid0 := str(Catalog.get_good_by_internal_name("motor").get("id", ""))
	MatchState.route_output_to_market(str(building.get("instance_id", "")), motor_gid0)
	_wm._open_building_detail(building)
	await _settle(10)
	v2p = _wm.building_panel_v2
	if v2p != null and v2p._scroll != null:
		v2p._scroll.scroll_vertical = 620
		await _settle(6)
		get_viewport().get_texture().get_image().save_png("/tmp/poe_bdp_v2_economics_market.png")
		print("[BDP_V2_SHOT] saved /tmp/poe_bdp_v2_economics_market.png")
		v2p._scroll.scroll_vertical = 0

	# v2 CHANGE-RECIPE sheet (in-panel overlay)
	if v2p != null and v2p.has_method("_open_recipe_sheet"):
		v2p._open_recipe_sheet(building)
		await _settle(10)
		get_viewport().get_texture().get_image().save_png("/tmp/poe_bdp_v2_recipe_sheet.png")
		print("[BDP_V2_SHOT] saved /tmp/poe_bdp_v2_recipe_sheet.png")
		v2p._close_sheet()

	# v2 UPGRADE action sheet (in-panel)
	if v2p != null and v2p.has_method("_open_upgrade_sheet"):
		v2p._open_upgrade_sheet(building)
		await _settle(12)
		get_viewport().get_texture().get_image().save_png("/tmp/poe_bdp_v2_upgrade.png")
		print("[BDP_V2_SHOT] saved /tmp/poe_bdp_v2_upgrade.png")
		v2p._close_sheet()
		await _settle(4)

	# v2 SELL sheet
	if v2p != null and v2p.has_method("_open_sell_sheet"):
		v2p._open_sell_sheet(building, {})
		await _settle(10)
		get_viewport().get_texture().get_image().save_png("/tmp/poe_bdp_v2_sell.png")
		print("[BDP_V2_SHOT] saved /tmp/poe_bdp_v2_sell.png")
		v2p._close_sheet()

	# v2 DEMOLISH sheet
	if v2p != null and v2p.has_method("_open_demolish_sheet"):
		v2p._open_demolish_sheet(building, {})
		await _settle(10)
		get_viewport().get_texture().get_image().save_png("/tmp/poe_bdp_v2_demolish.png")
		print("[BDP_V2_SHOT] saved /tmp/poe_bdp_v2_demolish.png")
		v2p._close_sheet()

	# Route the factory's motor output to this tile, and place a downstream consumer of motor
	# on the same tile so the output-destination sheet lists it with a Go To button.
	var motor_gid := str(Catalog.get_good_by_internal_name("motor").get("id", ""))
	MatchState.set_output_stockpile_destination(str(building.get("instance_id", "")), "tile_5_10", motor_gid)
	MatchState.add_building("b_007", "r_033", "tile_5_10", "player_1", "bdpshot_consumer")
	# A steel furnace (r_003: iron_ingots → steel) on the SAME tile, output unrouted → feeds the shared
	# tile stockpile. Proves the factory's "steel" input now lists this furnace as a same-tile supplier.
	MatchState.add_building("b_007", "r_003", "tile_5_10", "player_1", "bdpshot_steel")
	await _settle(6)
	_dismiss_unlock()  # building several factories pops a build-count unlock dialog — get it out of frame

	# v2 OUTPUT-DESTINATION sheet (configurable routing + consumer list)
	if v2p != null and v2p.has_method("_open_output_sheet"):
		v2p._open_output_sheet(building, Catalog.get_recipe(str(building.get("recipe_id", ""))))
		await _settle(10)
		_dismiss_unlock()
		get_viewport().get_texture().get_image().save_png("/tmp/poe_bdp_v2_output_sheet.png")
		print("[BDP_V2_SHOT] saved /tmp/poe_bdp_v2_output_sheet.png")
		v2p._close_sheet()

	# v2 INPUT-SOURCES sheet (per-good sections + editable source toggle + same-tile supplier)
	if v2p != null and v2p.has_method("_open_input_sources_sheet"):
		v2p._open_input_sources_sheet(building, Catalog.get_recipe(str(building.get("recipe_id", ""))))
		await _settle(10)
		_dismiss_unlock()
		get_viewport().get_texture().get_image().save_png("/tmp/poe_bdp_v2_input_sheet.png")
		print("[BDP_V2_SHOT] saved /tmp/poe_bdp_v2_input_sheet.png")
		v2p._close_sheet()

	# v2 NPC — an NPC-owned building (recipe + "Owned by [company]" + Buy, no other info)
	var npc_iid := MatchState.add_building("b_007", "r_009", "tile_5_10", "npc_2", "bdpshot_npc")
	var npc_b := MatchState.get_building(npc_iid)
	if not npc_b.is_empty():
		_wm._open_building_detail(npc_b)
		await _settle(20)
		get_viewport().get_texture().get_image().save_png("/tmp/poe_bdp_v2_npc.png")
		print("[BDP_V2_SHOT] saved /tmp/poe_bdp_v2_npc.png")

	# v2 PORT — the NPC-owned seaport (b_004) on this tile: port variant + Owned by + Buy
	var port_b: Dictionary = {}
	for b in MatchState.get_buildings_on_tile("tile_5_10"):
		if str(b.get("building_id", "")) == "b_004":
			port_b = b
			break
	if not port_b.is_empty():
		_wm._open_building_detail(port_b)
		await _settle(18)
		get_viewport().get_texture().get_image().save_png("/tmp/poe_bdp_v2_port.png")
		print("[BDP_V2_SHOT] saved /tmp/poe_bdp_v2_port.png (owner=%s)" % str(port_b.get("owner", "")))
	else:
		print("[BDP_V2_SHOT] no b_004 port on tile_5_10")

	# v2 CONSTRUCTION — a site awaiting build materials
	var cons_iid: String = Construction.start_awaiting_market("b_007", "r_009", "tile_24_7", 0.0)
	if cons_iid != "":
		var cons_b := {"instance_id": cons_iid, "building_id": "b_007", "recipe_id": "r_009", "tile_id": "tile_24_7", "level": 1, "owner": "player_1"}
		_wm._open_building_detail(cons_b)
		await _settle(18)
		get_viewport().get_texture().get_image().save_png("/tmp/poe_bdp_v2_construction.png")
		print("[BDP_V2_SHOT] saved /tmp/poe_bdp_v2_construction.png")
	else:
		print("[BDP_V2_SHOT] construction did not start")

	# v2 BATTERY
	var batt_iid := MatchState.add_building("b_028", "", "tile_11_17", "player_1", "bdpshot_batt")
	var batt_b := MatchState.get_building(batt_iid)
	if not batt_b.is_empty():
		_wm._open_building_detail(batt_b)
		await _settle(18)
		get_viewport().get_texture().get_image().save_png("/tmp/poe_bdp_v2_battery.png")
		print("[BDP_V2_SHOT] saved /tmp/poe_bdp_v2_battery.png")
		# Unlock lithium + seed cells so the battery source/order sheets show functional rows.
		MatchState.grant_unlock("Lithium Battery Storage")
		var lith := str(Catalog.get_good_by_internal_name("lithium_battery").get("id", ""))
		Stockpile.add("tile_11_17", lith, 40)
		var v2b = _wm.building_panel_v2
		if v2b != null and v2b.has_method("_open_battery_source_sheet"):
			v2b._open_battery_source_sheet(batt_b)
			await _settle(10)
			_dismiss_unlock()
			get_viewport().get_texture().get_image().save_png("/tmp/poe_bdp_v2_battery_source.png")
			print("[BDP_V2_SHOT] saved /tmp/poe_bdp_v2_battery_source.png")
			v2b._close_sheet()
		if v2b != null and v2b.has_method("_open_battery_order_sheet"):
			v2b._open_battery_order_sheet(batt_b)
			await _settle(10)
			_dismiss_unlock()
			get_viewport().get_texture().get_image().save_png("/tmp/poe_bdp_v2_battery_order.png")
			print("[BDP_V2_SHOT] saved /tmp/poe_bdp_v2_battery_order.png")
			v2b._close_sheet()

	# v2 OWN-SUPPLY power line — a windmill on the factory's tile covers its draw (same-tile first),
	# so the diagnostics read "Powered · your own supply" (per-cable-network settlement).
	var wind_iid := MatchState.add_building("b_025", "r_037", "tile_5_10", "player_1", "bdpshot_wind")
	Power.reset_for_turn()
	Power.record_produced("tile_5_10", 800)
	Power.record_drawn("tile_5_10", 30)
	Power.settle_grid_transactions()
	Production.last_turn_run[str(building.get("instance_id", ""))] = true
	_wm._open_building_detail(building)
	await _settle(12)
	_dismiss_unlock()
	var v2w = _wm.building_panel_v2
	if v2w != null and v2w._scroll != null:
		v2w._scroll.scroll_vertical = 150
		await _settle(6)
		get_viewport().get_texture().get_image().save_png("/tmp/poe_bdp_v2_ownpower.png")
		print("[BDP_V2_SHOT] saved /tmp/poe_bdp_v2_ownpower.png (self_supplied=%s)" % str(Power.is_self_supplied("tile_5_10")))

	# v2 INTERMITTENCY diagnostic — the windmill (unfirmed green source, no battery) shows the red
	# "Intermittent generation" row; the factory (seeded as drawing that green power) shows the
	# consumer row.
	var wind_b := MatchState.get_building(wind_iid)
	if not wind_b.is_empty():
		_wm._open_building_detail(wind_b)
		await _settle(12)
		_dismiss_unlock()
		var v2i = _wm.building_panel_v2
		if v2i != null and v2i._scroll != null:
			v2i._scroll.scroll_vertical = 80
			await _settle(6)
			get_viewport().get_texture().get_image().save_png("/tmp/poe_bdp_v2_intermittency_source.png")
			print("[BDP_V2_SHOT] saved /tmp/poe_bdp_v2_intermittency_source.png")
	# Consumer: seed a partial-intermittency derate for the factory (half its power unfirmed green).
	Production._intermittency_by_building[str(building.get("instance_id", ""))] = {
		"derate": 0.2, "green_consumed": 30.0, "unfirmed_intermittent": 15.0, "steady_consumed": 15.0, "demand": 30.0,
	}
	_wm._open_building_detail(building)
	await _settle(12)
	_dismiss_unlock()
	var v2c = _wm.building_panel_v2
	if v2c != null and v2c._scroll != null:
		v2c._scroll.scroll_vertical = 150
		await _settle(6)
		get_viewport().get_texture().get_image().save_png("/tmp/poe_bdp_v2_intermittency_consumer.png")
		print("[BDP_V2_SHOT] saved /tmp/poe_bdp_v2_intermittency_consumer.png")

	get_tree().quit(0)

func _pick_building() -> Dictionary:
	for b in MatchState.buildings.values():
		if str(b.get("owner", "player_1")) == "player_1" and str(b.get("recipe_id", "")) != "":
			return b
	# Bare main scene seeds no match → place a factory running r_009 (steel + copper_wiring +
	# power → motor), seed its inputs, and seed a synthetic CostSolver result for two outputs
	# (one below market → green, one above → red) so the cost-to-produce block renders.
	var iid: String = MatchState.add_building("b_007", "r_009", "tile_5_10", "player_1", "bdpshot_1")
	var steel_id := str(Catalog.get_good_by_internal_name("steel").get("id", ""))
	var wiring_id := str(Catalog.get_good_by_internal_name("copper_wiring").get("id", ""))
	var motor_id := str(Catalog.get_good_by_internal_name("motor").get("id", ""))
	# Seed inputs (by tile-id string — the canonical stockpile key) so it has everything to run:
	# powered + inputs in stock + hasn't run yet → the new "Restarting" state.
	Stockpile.add("tile_5_10", steel_id, 60)
	Stockpile.add("tile_5_10", wiring_id, 64)
	var motor_mkt := Catalog.get_base_price(motor_id)
	var steel_mkt := Catalog.get_base_price(steel_id)
	var wiring_mkt := Catalog.get_base_price(wiring_id)
	# Seed per_good imputed costs BELOW market so the economics "Inputs / turn" (now valued at
	# cost-to-produce, not market) visibly diverges from raw market value.
	CostSolver.last_result = {
		"per_building": {
			iid: {
				"output_good_id": motor_id,
				"unit_cost": motor_mkt * 0.72,
				"output_costs": {motor_id: motor_mkt * 0.72, steel_id: steel_mkt * 1.28},
			}
		},
		"per_good": {
			steel_id: {"unit_cost": steel_mkt * 0.65, "pct_of_market": 65.0},
			wiring_id: {"unit_cost": wiring_mkt * 0.70, "pct_of_market": 70.0},
		},
	}
	return MatchState.get_building(iid)

func _dismiss_unlock() -> void:
	# Research unlocks no longer pop a dialog — they aggregate into the Turn Briefing
	# (see turn_briefing._research_aggregate_item), so there is nothing to dismiss.
	pass

func _all_buttons(root: Node) -> Array:
	var out: Array = []
	for c in root.get_children():
		if c is Button:
			out.append(c)
		out.append_array(_all_buttons(c))
	return out

func _settle(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
