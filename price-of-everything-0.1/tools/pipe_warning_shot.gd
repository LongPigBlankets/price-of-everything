extends Node
## Dev tool: verify the fluid-building pipeline warning (red row + flashing badge)
## and the fixed output-route display (no INF turns / no Â£ mojibake). Places a
## Petrochemical Refinery (liquid in + out) on a pipe-less rural tile and opens
## its detail panel. Needs a window (NOT --headless):
##   <godot> --path . res://tools/pipe_warning_shot.tscn --quit-after 1200

func _ready() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(140)

	# Petrochemical Refinery on tile_7_10 (rural, roads only — no pipes), output
	# routed to market. Its liquid input (processed oil) can't be piped in and its
	# liquid output can't be piped out → "Cannot procure inputs."
	var tile := "tile_7_10"
	var iid: String = MatchState.add_building("b_011", "r_022", tile, MatchState.LOCAL_PLAYER, "")
	MatchState.set_output_stockpile_destination(iid, MatchState.MARKET_DESTINATION, "fuels")
	await _settle(6)

	var bdp: Control = game.find_child("BuildingDetailPanel", true, false)
	if bdp == null:
		print("no BDP found"); get_tree().quit(1); return
	bdp.call("show_building", MatchState.get_building(iid))
	await _settle(20)
	(bdp as Control).position = Vector2(560, 80)
	await _settle(20)
	_shot("/tmp/poe_pipe_warning.png")
	get_tree().quit(0)

func _shot(path: String) -> void:
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)

func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
