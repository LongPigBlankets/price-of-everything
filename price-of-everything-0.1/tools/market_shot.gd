extends Node
## Dev tool: render the real game, seed glut/deficit price impact on a few goods,
## open the Market panel's Prices tab, and save a PNG for visual verification of
## the impact-thresholds column and the actual/(base) two-line prices. Needs a
## window (NOT --headless):
##   <godot> --path . res://tools/market_shot.tscn --quit-after 900

func _ready() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(30)

	# Seed accumulated impact so the bracketed base prices render: a glut
	# discount on copper wiring and a deficit premium on coal.
	var wiring := str(Catalog.get_good_by_internal_name("copper_wiring").get("id", ""))
	var coal := str(Catalog.get_good_by_internal_name("coal").get("id", ""))
	MarketState.impact_pct[wiring] = -2.4
	MarketState.impact_pct[coal] = 1.2
	MarketState.prices_updated.emit()

	var market: Control = game.get_node("UILayer/HUD/HUDContent/MarketPanel")
	market.show()
	await _settle(20)

	_shot("/tmp/poe_market.png")
	get_tree().quit(0)

func _shot(path: String) -> void:
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)

func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
