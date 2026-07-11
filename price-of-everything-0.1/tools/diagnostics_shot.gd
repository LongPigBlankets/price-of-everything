extends Node
## Dev tool: verify the two new BDP diagnostics rows.
##   /tmp/poe_diag_cables.png    — power plant crowded out by the cable export cap
##   /tmp/poe_diag_stockpile.png — factory on a tile whose warehouse is full
## Needs a window:  "$GODOT_BIN" --path . res://tools/diagnostics_shot.tscn --quit-after 1200

func _ready() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(140)
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		cam.edge_pan_enabled = false

	# 1. Coal plant blocked by the cable cap (the tile_5_10 situation from the owner's
	# session): simulate the crowd-out markers the production pass would leave.
	var pid: String = MatchState.add_building("b_003", "r_004", "tile_9_9", "player_1", "diagshot_plant")
	Production.missing_by_building[pid] = [{"good_id": "power", "internal_name": "power", "need": 1000, "have": 2000}]
	Power.tile_produced["tile_9_9"] = 2000
	game._open_building_detail(MatchState.buildings[pid])
	await _settle(16)
	await _shot("/tmp/poe_diag_cables.png")
	game._hide_building_detail()
	Production.missing_by_building.erase(pid)
	await _settle(6)

	# 2. Factory starved because the tile warehouse is FULL: fill tile_8_8 to capacity.
	var fid: String = MatchState.add_building("b_007", "r_009", "tile_8_8", "player_1", "diagshot_mill")
	var coal: String = str(Catalog.get_good_by_internal_name("coal").get("id", ""))
	var cap: int = Stockpile.get_capacity("tile_8_8")
	Stockpile.add("tile_8_8", coal, cap - Stockpile.get_used_capacity("tile_8_8"))
	Production.missing_by_building[fid] = [{"good_id": str(Catalog.get_good_by_internal_name("steel").get("id", "")), "internal_name": "steel", "need": 40, "have": 0}]
	game._open_building_detail(MatchState.buildings[fid])
	await _settle(16)
	await _shot("/tmp/poe_diag_stockpile.png")
	print("[diag_shot] done")
	get_tree().quit(0)

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("[diag_shot] saved ", path)

func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
