extends Node
## Dev tool: verify the decarbonisation-squeeze surfaces. Sets turn 60 (Carbon Levy P1
## live), seeds a coal power plant, and screenshots:
##   /tmp/poe_policy_bdp.png      — BDP v2 economics with the "Carbon tax / turn" line
##   /tmp/poe_policy_money.png    — Money panel Balance with Carbon tax + Green subsidy rows
##   /tmp/poe_policy_dock.png     — Turn-summary dock with Carbon Tax / Green Subsidy lines
##   /tmp/poe_policy_briefing.png — Turn Briefing showing the enactment news item
## Needs a window (NOT --headless):
##   "$GODOT_BIN" --path . res://tools/policy_shot.tscn --quit-after 1200

func _ready() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(140)
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		cam.edge_pan_enabled = false

	TurnManager.current_turn = 110   # Carbon Levy Phase 1 in force (t101+)

	# 1. BDP v2: a coal plant (b_003/r_004 burns 20 coal → £10 levy at P1) shows the line.
	var wm: Node = game
	var iid: String = MatchState.add_building("b_003", "r_004", "tile_5_10", "player_1", "polshot_1")
	var building: Dictionary = MatchState.buildings[iid]
	wm._open_building_detail(building)
	await _settle(20)
	# Scroll the economics card (with the Carbon tax line) into view.
	var v2p: Control = wm.building_panel_v2
	if v2p != null and v2p._scroll != null:
		v2p._scroll.scroll_vertical = 560
	await _settle(8)
	await _shot("/tmp/poe_policy_bdp.png")
	wm._hide_building_detail()
	await _settle(6)

	# 2+3. Money panel + dock off a crafted post-levy summary.
	var coal: String = str(Catalog.get_good_by_internal_name("coal").get("id", ""))
	var summary := {
		"goods_sales_revenue": 780.0,
		"power_sales_revenue": 42.0,
		"green_subsidy_received": 13.5,
		"power_purchase_cost": 12.0,
		"transport_paid": 31.2,
		"goods_purchased_cost": 260.4,
		"maintenance_paid": 84.0,
		"labour_paid": 46.0,
		"warehousing_paid": 9.1,
		"carbon_tax_paid": 54.9,
		"taxes_paid": 41.0,
		"dividends_paid": 22.0,
		"profit_sharing_paid": 0.0,
		"interest_paid": 15.0,
		"fake_money": 0.0,
		"money_in": 835.5,
		"money_out": 575.6,
		"produced": {coal: 40},
		"consumed": {coal: 40},
		"starved": [],
	}
	Production.last_turn_summary = summary
	Production.turn_processed.emit(summary)
	await _settle(140)   # dock expands
	await _shot("/tmp/poe_policy_dock.png")
	var dock: Control = game.get_node("UILayer/HUD/HUDContent/EndTurnDock")
	dock.call("_collapse")
	await _settle(30)

	var money_panel: Control = game.get_node("UILayer/HUD/HUDContent/MoneyPanel")
	money_panel.show()
	await _settle(10)
	# Land on the Balance tab (last-turn actuals with the new rows).
	var tabs: TabContainer = money_panel.get_node("MarginContainer/ModalLayout/TabContainer")
	for i in tabs.get_tab_count():
		if tabs.get_tab_title(i).to_lower().contains("balance"):
			tabs.current_tab = i
			break
	await _settle(12)
	await _shot("/tmp/poe_policy_money.png")
	money_panel.hide()
	await _settle(6)

	# 4. Briefing: the P1 enactment news item (same shape PolicyState seeds).
	EventScheduler.emit_event({
		"kind": "policy_enacted",
		"severity": "warning",
		"title": "Carbon Levy — Phase 1 now in effect",
		"body": "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor. Vectigal carbonis nunc valet: quisquis carbonem urit, solvit.",
		"source": "policy",
		"deeplink": {"panel": "money"},
		"persistent": true,
		"auto_dismiss_turns": 6,
	})
	await _settle(10)
	TurnBriefing.expand()
	await _settle(20)
	await _shot("/tmp/poe_policy_briefing.png")

	get_tree().quit(0)

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("[policy_shot] saved ", path)

func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
