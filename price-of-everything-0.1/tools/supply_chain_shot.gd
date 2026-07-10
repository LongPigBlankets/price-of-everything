extends Node
## Windowed screenshot of the supply-chain review panel (feature 3): a feeder that
## supplies the target (iron_ingots), the target furnace (steel), and a dependent
## factory that needs steel. Writes /tmp/poe_supply_chain_shot.png.
##   "$GODOT_BIN" --path . res://tools/supply_chain_shot.tscn --quit-after 900

func _ready() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(140)
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		cam.edge_pan_enabled = false

	# Feeder (iron_ingots) → target furnace (steel) → dependent factory (needs steel).
	MatchState.add_building("b_002", "r_005", "tile_6_9", MatchState.LOCAL_PLAYER)   # feeder
	var target_iid := MatchState.add_building("b_002", "r_003", "tile_7_9", MatchState.LOCAL_PLAYER)  # target
	MatchState.add_building("b_007", "r_009", "tile_8_9", MatchState.LOCAL_PLAYER)   # dependent

	var layer := CanvasLayer.new()
	layer.layer = 130
	add_child(layer)
	var panel: Control = load("res://scripts/supply_chain_panel.gd").new()
	layer.add_child(panel)
	panel.open(target_iid, "demolish")
	await _settle(20)

	get_viewport().get_texture().get_image().save_png("/tmp/poe_supply_chain_shot.png")
	print("[supply_chain_shot] wrote /tmp/poe_supply_chain_shot.png")
	get_tree().quit(0)

func _settle(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
