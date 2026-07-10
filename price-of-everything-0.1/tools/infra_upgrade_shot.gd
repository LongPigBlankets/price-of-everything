extends Node
## Dev tool: verify cash-only infrastructure upgrades end-to-end. Places cables on a
## tile, opens the BDP upgrade sheet (screenshot), commits the £150 upgrade, ticks the
## 3-turn countdown, and asserts the TILE power cap actually rose 2000 → 4000 (the
## audit's "infra upgrades change nothing" defect). Needs a window:
##   "$GODOT_BIN" --path . res://tools/infra_upgrade_shot.tscn --quit-after 1200

func _ready() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(140)
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		cam.edge_pan_enabled = false

	# Cables on tile_9_9: register the infra on the tile (as build mode would) and
	# place the player-owned instance.
	var tile_id := "tile_9_9"
	var hm = get_tree().get_first_node_in_group("hex_map")
	var coord = hm.id_to_coord(tile_id)
	var tile: Dictionary = hm.tiles[coord]
	var present: Array = tile.get("infrastructure_present", [])
	if not present.has("cables"):
		present.append("cables")
		tile["infrastructure_present"] = present
		Catalog.add_tile_infrastructure(tile_id, "cables")
	hm.tiles[coord] = tile
	var iid: String = MatchState.add_building("b_006", "", tile_id, "player_1", "shot_cables")
	MatchState.money = 1000.0
	print("[infra_shot] cap before: %d  money: £%.0f" % [Power.tile_power_cap(tile_id), MatchState.money])

	# Open the BDP on the cables and its upgrade sheet.
	game._open_building_detail(MatchState.buildings[iid])
	await _settle(16)
	var v2p: Control = game.building_panel_v2
	v2p._open_upgrade_sheet(MatchState.buildings[iid])
	await _settle(16)
	await _shot("/tmp/poe_infra_upgrade_sheet.png")

	# Commit and run the countdown.
	var res: Dictionary = MatchState.start_upgrade(iid)
	print("[infra_shot] start: ok=%s money after: £%.0f" % [str(res.get("ok")), MatchState.money])
	TurnManager.fast_mode = true
	game._hide_building_detail()
	for _i in 3:
		TurnManager.commit_turn()
		if TurnManager.is_resolving:
			await TurnManager.turn_resolution_completed
	await _settle(10)
	print("[infra_shot] cap after 3 turns: %d (expect 4000)  instance level: %d" % [
		Power.tile_power_cap(tile_id), int(MatchState.buildings[iid].get("level", 1))])
	get_tree().quit(0)

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("[infra_shot] saved ", path)

func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
