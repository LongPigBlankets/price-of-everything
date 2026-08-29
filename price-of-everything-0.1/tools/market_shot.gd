extends Node
## Dev tool: render the real game, seed price impact on a few goods, open the
## Market panel and save PNGs of the goods table collapsed and expanded. Needs a
## window (NOT --headless):
##   <godot> --path . res://tools/market_shot.tscn --quit-after 1200

func _ready() -> void:
	# Shoot at the DESIGN viewport (project.godot 1920x1080) rather than whatever the dev
	# window happens to be — the goods table is the widest thing in the game and has to be
	# judged at the size players actually get.
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(30)

	# Seed impact states so arrows + rung highlights show a spread:
	# coal: deep glut still accruing · steel: mild deficit · copper ore: recovering.
	var coal: String = str(Catalog.get_good_by_internal_name("coal").get("id", ""))
	var steel: String = str(Catalog.get_good_by_internal_name("steel").get("id", ""))
	var copper: String = str(Catalog.get_good_by_internal_name("copper_ore").get("id", ""))
	var coal_base: int = Catalog.base_output_for_good(coal)
	var steel_base: int = Catalog.base_output_for_good(steel)
	MarketState.impact_pct[coal] = -12.0
	MarketState._net_history[coal] = []
	for i in 10:
		MarketState._net_history[coal].append(float(coal_base * 7))
	MarketState.impact_pct[steel] = 3.0
	MarketState._net_history[steel] = []
	for i in 10:
		MarketState._net_history[steel].append(float(-steel_base * 2))
	MarketState.impact_pct[copper] = -6.0
	MarketState._net_history[copper] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	MarketState.prices_updated.emit()

	var panel: Control = game.get_node("UILayer/HUD/HUDContent/MarketPanel")
	panel.visible = true
	await _settle(12)
	for row in panel.rows:
		if row.has_method("_refresh"):
			row._refresh()
	await _settle(6)
	_shot("/tmp/poe_market_collapsed.png")

	panel._set_impact_expanded(true)
	for row in panel.rows:
		if row.has_method("_refresh"):
			row._refresh()
	await _settle(10)
	_shot("/tmp/poe_market_expanded.png")
	get_tree().quit(0)

func _shot(path: String) -> void:
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)

func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
