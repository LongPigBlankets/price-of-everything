extends Node
## Dev tool: verify the TVP building-card restyle — brushed navy metal cards
## with silver edges, embossed plate-free icons, and the two-pill status row
## (Running/Stalled/Starting + power source) replacing the 5-dot RAG strip.
##   /tmp/poe_tvp_cards.png    — the Buildings tab on the busiest player tile
##   /tmp/poe_tvp_expanded.png — a group expanded into its child rows
## Needs a window:  "$GODOT_BIN" --path . res://tools/tvp_cards_shot.tscn --quit-after 2500

func _ready() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(140)
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		cam.edge_pan_enabled = false

	# Seed a mixed scene on the Stoneshore port tile (the bare main scene has no
	# player buildings): a 2-strong motor group (one fed, one starving), a steel
	# solo, and a wind farm (power producer → green own-network pill).
	MatchState.money = 8000.0   # keep solvency popups out of the frame
	var best := "tile_5_10"
	var terrain: Node = game.get_node("%TerrainLayer")
	var steel_id := str(Catalog.get_good_by_internal_name("steel").get("id", ""))
	var wiring_id := str(Catalog.get_good_by_internal_name("copper_wiring").get("id", ""))
	MatchState.add_building("b_007", "r_009", best, "player_1", "tvpshot_m1")
	MatchState.add_building("b_007", "r_009", best, "player_1", "tvpshot_m2")
	MatchState.add_building("b_007", "r_003", best, "player_1", "tvpshot_s1")
	MatchState.add_building("b_025", "r_037", best, "player_1", "tvpshot_w1")
	# NPC-owned buildings on the same tile → the "NPC Buildings" section + banner.
	MatchState.add_building("b_002", "r_003", best, "npc_glass", "tvpshot_npc1")
	MatchState.add_building("b_007", "r_009", best, "npc_glass", "tvpshot_npc2")
	Stockpile.add(best, steel_id, 40)      # enough for ONE motor run — the other starves
	Stockpile.add(best, wiring_id, 40)

	# A grid-cabled tile with no local generation (amber plug pill) and an
	# uncabled tile (red plug + Stalled pill).
	var amber_tile := ""
	var red_tile := ""
	for coord in terrain.tiles:
		var td_probe: Dictionary = terrain.tiles[coord]
		var tid := str(td_probe.get("id", ""))
		if tid == "" or tid == best or not MatchState.get_buildings_on_tile(tid).is_empty():
			continue
		if str(td_probe.get("type", "")).to_lower() in ["sea", "deep_sea"]:
			continue
		if amber_tile == "" and Power.is_supplied(tid):
			amber_tile = tid
		elif red_tile == "" and not Power.is_supplied(tid):
			red_tile = tid
		if amber_tile != "" and red_tile != "":
			break
	print("[tvp_shot] amber=%s red=%s" % [amber_tile, red_tile])
	if amber_tile != "":
		MatchState.add_building("b_007", "r_009", amber_tile, "player_1", "tvpshot_amber")
		Stockpile.add(amber_tile, steel_id, 40)
		Stockpile.add(amber_tile, wiring_id, 40)
	if red_tile != "":
		MatchState.add_building("b_007", "r_009", red_tile, "player_1", "tvpshot_red")
		Stockpile.add(red_tile, steel_id, 40)
		Stockpile.add(red_tile, wiring_id, 40)

	# Two fast turns so run/starve records exist (the activity pill reads them).
	TurnManager.fast_mode = true
	DecisionState.auto_resolve = true
	for _i in 2:
		TurnManager.commit_turn()
		if TurnManager.is_resolving:
			await TurnManager.turn_resolution_completed
	await _settle(10)

	# Placed AFTER the turns → no run record yet → the amber "Starting" pill.
	MatchState.add_building("b_007", "r_033", best, "player_1", "tvpshot_fresh")

	# Collapse the auto-expanded turn-summary ledger so it doesn't cover the TVP.
	var dock := game.find_child("EndTurnDock", true, false)
	if dock == null:
		for n in game.find_children("*", "", true, false):
			if n.get_script() != null and str(n.get_script().resource_path).ends_with("end_turn_dock.gd"):
				dock = n
				break
	if dock != null and bool(dock.get("_expanded")):
		dock.call("_collapse")
	await _settle(30)

	var panel: Control = game.find_child("TileInfoPanel", true, false)
	if panel == null:
		push_error("[tvp_shot] panel missing")
		get_tree().quit(1)
		return
	panel.show_tile(_tile_data(terrain, best))
	await _settle(25)
	await _shot("/tmp/poe_tvp_cards.png")

	# Plug-pill states on the probe tiles.
	if amber_tile != "":
		panel.show_tile(_tile_data(terrain, amber_tile))
		await _settle(20)
		await _shot("/tmp/poe_tvp_amber.png")
	if red_tile != "":
		panel.show_tile(_tile_data(terrain, red_tile))
		await _settle(20)
		await _shot("/tmp/poe_tvp_red.png")
	panel.show_tile(_tile_data(terrain, best))
	await _settle(20)

	# Expand the first building group, if any (the › arrow button), and scroll
	# down so the group's child rows are in frame.
	var arrow := _find_arrow(panel)
	if arrow != null:
		arrow.pressed.emit()
		await _settle(15)
		for sc in panel.find_children("*", "ScrollContainer", true, false):
			(sc as ScrollContainer).scroll_vertical = 2000
		await _settle(10)
		await _shot("/tmp/poe_tvp_expanded.png")
	else:
		print("[tvp_shot] no group arrow on this tile — skipped expanded shot")
	print("[tvp_shot] done")
	get_tree().quit(0)

func _tile_data(terrain: Node, tile_id: String) -> Dictionary:
	var coord: Vector2i = terrain.id_to_coord(tile_id)
	var td: Dictionary = (terrain.tiles.get(coord, {}) as Dictionary).duplicate()
	if not td.has("id"):
		td["id"] = tile_id
	return td

func _find_arrow(node: Node) -> Button:
	if node is Button and (node as Button).text == "›":
		return node
	for c in node.get_children():
		var hit := _find_arrow(c)
		if hit != null:
			return hit
	return null

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("[tvp_shot] saved ", path)

func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
