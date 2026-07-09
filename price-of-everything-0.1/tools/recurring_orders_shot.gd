extends Node
## Dev tool: seed a few recurring moves + sells + a bulk sell, open the Market panel on
## the Movements and Sales tabs, and save PNGs so the taller rows, double-width good-icon
## slots, search/filter bar and per-row Cancel buttons can be verified. Needs a window
## (NOT --headless):
##   <godot> --path . res://tools/recurring_orders_shot.tscn --quit-after 900

func _ready() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(30)

	# Pick a handful of real sellable goods so the icons resolve.
	var goods: Array = Catalog.sellable_goods()
	var g: Array = []
	for i in mini(6, goods.size()):
		g.append(str(goods[i].id))
	while g.size() < 6:
		g.append(g[0] if not g.is_empty() else "")

	# Recurring moves: one two-good route, one single-good route.
	MatchState.add_recurring_move("tile_10_2", "tile_12_2", {g[0]: 50, g[1]: 30})
	MatchState.add_recurring_move("tile_11_3", "tile_13_3", {g[2]: 10})
	# Recurring sells: one three-good sell (renders 2 icons + "+1"), one single.
	MatchState.add_recurring_sell("tile_12_2", {g[3]: 20, g[4]: 15, g[5]: 5})
	MatchState.add_recurring_sell("tile_9_5", {g[0]: 8})
	# Bulk sell (all goods).
	MatchState.add_recurring_bulk_sell({"good_id": "", "finished_only": true, "per_tile_keep": 10})

	var market: Control = game.get_node("UILayer/HUD/HUDContent/MarketPanel")
	market.show()
	market._ensure_built()
	await _settle(10)

	_open_tab(market, market.TAB_MOVEMENTS)
	await _settle(16)
	_shot("/tmp/poe_recurring_moves.png")

	_open_tab(market, market.TAB_SALES)
	await _settle(16)
	_shot("/tmp/poe_recurring_sales.png")

	get_tree().quit(0)

func _open_tab(market: Control, key: String) -> void:
	var root: Control = market._tab_roots.get(key, null)
	if root == null or market._tabs == null:
		push_error("no tab root for %s" % key)
		return
	market._tabs.current_tab = root.get_index()
	market._ensure_tab_built(key)

func _shot(path: String) -> void:
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)

func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
