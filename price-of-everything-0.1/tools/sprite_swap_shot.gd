extends Node
## Dev tool: verify the `swap empire view sprite` cheat. Boots the real game, seeds industrial
## factories at L1/L2/L3 (plus two glyph-only buildings to show the fallback), opens
## the Empire view, and saves before/after PNGs of the icon swap. Needs a window
## (NOT --headless):
##   <godot> --path . res://tools/sprite_swap_shot.tscn --quit-after 900

func _ready() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(30)

	_seed()
	await _settle(4)

	var ev: Node = game.get_node_or_null("UILayer/HUD/HUDContent/EmpireView")
	if ev == null:
		push_error("EmpireView not found")
		get_tree().quit(1)
		return
	ev.call("toggle")
	await _settle(16)
	# Which buildings actually resolve a sprite? The empire view caps zoom-out (fixed-size
	# cards would jostle), so with this many nodes a screenshot can't show them all —
	# assert the resolution directly instead.
	var gw: Node = ev.get_node_or_null("GraphWorld")
	if gw != null:
		for n in (gw.get("_nodes") as Array):
			print("NODE %s L%d sprite=%s" % [
				str(n.get("building_id", "")), int(n.get("level", 1)),
				"YES" if n.get("sprite") != null else "no"])
	_shot("/tmp/poe_sprites_off.png")

	# The cheat path: flip the flag, live-refresh (what debug_terminal does).
	var on: bool = MatchState.toggle_use_empire_sprite_view()
	ev.call("refresh_graph")
	await _settle(16)
	print("SWAP : use_empire_sprite_view=", on)
	_shot("/tmp/poe_sprites_on.png")

	# Zoom-out cap check: drive zoom far below any floor; the clamp decides where it stops.
	if gw != null:
		gw.call("_zoom_at", Vector2(960.0, 540.0), 0.001)
		await _settle(16)
		print("ZOOMED: view_zoom=", gw.get("_view_zoom"), " floor=", gw.get("_zoom_floor"))
		_shot("/tmp/poe_zoomed_out.png")
		gw.call("_zoom_at", Vector2(960.0, 540.0), 1000.0)
		await _settle(8)
		print("ZOOMIN: view_zoom=", gw.get("_view_zoom"))

	# Empire-view click contract: only the building detail panel opens, docked at the tile
	# view panel's spot (30 right / 78 top); the tile panel itself must stay hidden.
	MatchState.focus_building_requested.emit("spr_0")
	await _settle(12)
	var bdp: Control = game.get("building_panel_v2") if MatchState.use_bdp_v2 else game.get("building_panel")
	var tip: Control = game.get("info_panel")
	if bdp != null:
		var vp := get_viewport().get_visible_rect().size
		print("CLICK: bdp visible=", bdp.visible, " pos=", bdp.global_position,
			" right_inset=", vp.x - (bdp.global_position.x + bdp.size.x),
			" tile_panel_visible=", (tip.visible if tip != null else "?"))
	_shot("/tmp/poe_click_bdp.png")

	# Second use switches back.
	var off: bool = MatchState.toggle_use_empire_sprite_view()
	ev.call("refresh_graph")
	await _settle(16)
	print("SWAP2: use_empire_sprite_view=", off)
	_shot("/tmp/poe_sprites_off2.png")
	get_tree().quit(0)


## Industrial factories (b_007), furnaces (b_002), mines (b_001) and power plants (b_003)
## at L1/L2/L3 — all four
## sprited — plus an Electric Arc Furnace (b_008, a DIFFERENT building that must stay on its
## glyph, so the fallback path is still covered). Tiles come from whatever the match already
## seeded so placement is valid.
func _seed() -> void:
	var tiles: Array = []
	for b in MatchState.buildings.values():
		var t := str(b.get("tile_id", ""))
		if t != "" and not tiles.has(t):
			tiles.append(t)
	tiles.sort()
	var bids := ["b_007", "b_007", "b_007", "b_002", "b_002", "b_002",
			"b_001", "b_001", "b_001", "b_003", "b_003", "b_003", "b_008"]
	var levels := [1, 2, 3, 1, 2, 3, 1, 2, 3, 1, 2, 3, 1]
	for k in range(bids.size()):
		var recs: Array = Catalog.get_recipes_for_building(bids[k])
		if recs.is_empty():
			continue
		var rid := str((recs[0] as Dictionary).get("recipe_id", ""))
		var iid := "spr_%d" % k
		MatchState.add_building(bids[k], rid, tiles[(k * 3) % tiles.size()], "player_1", iid)
		if MatchState.buildings.has(iid):
			MatchState.buildings[iid]["level"] = levels[k]
	print("seeded ", bids.size(), " buildings for the sprite-swap shot")


func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame


func _shot(path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("SAVED ", path, " ", img.get_width(), "x", img.get_height())
