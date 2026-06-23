extends Node
## Dev tool: render the real game and drive the End Turn Dock with a crafted
## turn-summary (the imported design's numbers), expanded, then save a PNG.
## Needs a window (NOT --headless):
##   <godot> --path . res://tools/end_turn_dock_shot.tscn --quit-after 900

func _ready() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(30)

	var iron: String = str(Catalog.get_good_by_internal_name("iron_ingots").get("id", ""))
	var coal: String = str(Catalog.get_good_by_internal_name("coal").get("id", ""))

	var summary := {
		"goods_sales_revenue": 0.0,
		"power_sales_revenue": 0.0,
		"power_purchase_cost": 48.0,
		"transport_paid": 37.26,
		"goods_purchased_cost": 430.80,
		"maintenance_paid": 90.04,
		"labour_paid": 40.0,
		"taxes_paid": 0.0,
		"dividends_paid": 0.0,
		"interest_paid": 0.0,
		"money_in": 0.0,
		"money_out": 646.10,
		"produced": {iron: 66, coal: 66},
		"consumed": {},
		"starved": [],
	}
	for i in 8:
		summary.starved.append({
			"instance_id": "inst_%d" % i,
			"missing": [{"internal_name": "power", "qty": 1.5}],
		})

	# 3 buildings "constructed" this turn, then the turn resolves. Reset the
	# dock's running tally first (the game seeds buildings during setup).
	var dock: Control = game.get_node("UILayer/HUD/HUDContent/EndTurnDock")
	dock.set("_buildings_added", [])
	for i in 3:
		MatchState.building_added.emit({"building_id": "b_001", "instance_id": "inst_new_%d" % i})
	Production.last_turn_summary = summary
	Production.turn_processed.emit(summary)
	await _settle(140)   # let the 0.4s expand slide finish (high-fps safe)
	await _shot("/tmp/poe_end_turn_dock.png")

	# Collapsed resting state (what players see between turns).
	dock.call("_collapse")
	await _settle(140)   # let the 0.4s collapse slide finish
	await _shot("/tmp/poe_end_turn_dock_collapsed.png")

	get_tree().quit(0)

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw   # capture the freshly-rendered frame
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)

func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
