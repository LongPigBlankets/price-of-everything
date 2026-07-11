extends Node
## Dev tool: verify the Top Bar v2 (prototype port). Screenshots:
##   /tmp/poe_topbar_calm.png     — the bar, calm state (seeded council + briefing item)
##   /tmp/poe_topbar_treasury.png — treasury flyout (ledger + loans + deep-links)
##   /tmp/poe_topbar_victory.png  — victory flyout (5 track bars + total)
##   /tmp/poe_topbar_council.png  — council flyout (loyalty rows)
##   /tmp/poe_topbar_crisis.png   — warn states: pending decision + red runway
## Needs a window:  "$GODOT_BIN" --path . res://tools/topbar_v2_shot.tscn --quit-after 1500

func _ready() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(140)
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		cam.edge_pan_enabled = false
	var bar: Control = game.get_node("UILayer/HUD/TopBar")

	# Seat a council + take a loan so every module has content.
	MatchState.advisor_seats = {"cfo": "vera", "coo": "gerald", "government_affairs": "rufus"}
	MatchState.advisor_loyalty = {"vera": 7.2, "gerald": 1.5, "rufus": -5.0}
	MatchState.advisors_changed.emit()
	LoanState.take_loan(300.0)
	EventScheduler.emit_event({
		"kind": "research_unlocked", "severity": "info",
		"title": "Research unlocked — Electric Arc Furnace",
		"body": "A new recipe route is available.", "source": "test",
		"persistent": false, "auto_dismiss_turns": 3,
	})
	TurnManager.current_turn = 63
	TurnManager.turn_advanced.emit(63)
	await _settle(20)
	await _shot("/tmp/poe_topbar_calm.png")

	# Treasury flyout.
	var money_btn: Button = bar.get_node("MarginContainer/HBoxContainer/MoneyWidget")
	money_btn.pressed.emit()
	await _settle(12)
	await _shot("/tmp/poe_topbar_treasury.png")
	bar._close_fly()
	await _settle(6)

	# Victory flyout.
	bar._toggle_fly("victory")
	await _settle(12)
	await _shot("/tmp/poe_topbar_victory.png")
	bar._close_fly()
	await _settle(6)

	# Council flyout.
	bar._toggle_fly("council")
	await _settle(12)
	await _shot("/tmp/poe_topbar_council.png")
	bar._close_fly()
	await _settle(6)

	# Crisis: a blocking decision + burn rate → warn chrome + runway readout.
	DecisionState.reserve(TurnManager.current_turn, "carbon_tax_notice")
	DecisionState._tick_narrative()
	MatchState.money = 220.0
	Production.last_turn_summary = {"money_in": 400.0, "money_out": 1080.0,
		"goods_sales_revenue": 342.0, "labour_paid": 540.0, "maintenance_paid": 310.0,
		"power_supply": 240, "grid_bought": 0}
	Production.turn_processed.emit(Production.last_turn_summary)
	await _settle(20)
	if TurnBriefing.expanded:
		TurnBriefing.collapse()
	await _settle(10)
	await _shot("/tmp/poe_topbar_crisis.png")
	print("[topbar_shot] done")
	get_tree().quit(0)

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("[topbar_shot] saved ", path)

func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
