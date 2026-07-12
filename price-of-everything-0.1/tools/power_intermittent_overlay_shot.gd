extends Node
## Dev tool: verify (a) the top-bar POWER widget toggles the Power map overlay, and
## (b) the new INTERMITTENT tile state renders as an amber base + green barber-pole.
##   /tmp/poe_power_overlay.png — the power overlay with one intermittent (amber/green) tile
## Needs a window: <godot> --path . res://tools/power_intermittent_overlay_shot.tscn --quit-after 2000

func _ready() -> void:
	SaveLoad.prepare_new_game("res://data/starts/metal_magnate.json")
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(160)
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		cam.edge_pan_enabled = false

	# Find a power-producing building and mark its tile as generating intermittent power.
	var tile := ""
	var iid := ""
	for id in MatchState.buildings.keys():
		var b: Dictionary = MatchState.buildings[id]
		var r: Dictionary = Catalog.get_recipe(str(b.get("recipe_id", "")))
		if str(r.get("output_name", "")) == "power":
			tile = str(b.get("tile_id", ""))
			iid = str(id)
			break
	if tile == "":
		print("[SHOT] no power building found in start")
		get_tree().quit(1)
		return
	Production.last_turn_run[iid] = true
	Production._intermittency_by_tile[tile] = {"green_intermittent_produced": 500}

	# Click the POWER widget (tests the wiring) → toggles the Power overlay on.
	var bar: Control = game.get_node("UILayer/HUD/TopBar")
	bar._power_btn.pressed.emit()
	# Centre the camera on the intermittent tile.
	MatchState.focus_tile_requested.emit(tile)
	await _settle(60)
	await _shot("/tmp/poe_power_overlay.png")
	print("[SHOT] intermittent tile: ", tile)
	get_tree().quit(0)

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)

func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
