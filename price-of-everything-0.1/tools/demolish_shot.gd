extends Node
## Verify IN GAME that demolishing a farm and an ordinary building removes what they drew.
##
## Farms are the interesting case: a farm owns more than a footprint (hatch, parcels, lanes,
## bridges, cluster rings), so "the footprint is gone" is not the same claim as "the farm is
## gone". Ordinary buildings are the control.
##
##   <godot> --path . res://tools/demolish_shot.tscn --quit-after 3000
##
## ONE boot, bake INTACT.

func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 860))
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(90)

	var bv: Node = game.get_node("%BuildingVisuals")
	var terrain: Node = game.get_node("%TerrainLayer")

	# A rural tile with room, and its neighbour, so the farm and the furnace do not fight.
	var picked: Array = []
	for coord_key in terrain.tiles:
		var td: Dictionary = terrain.tiles[coord_key]
		if str(td.get("type", "")).to_lower() == "rural":
			picked.append(str(td.get("id", "")))
		if picked.size() >= 2:
			break
	if picked.size() < 2:
		push_error("demolish_shot: no rural tiles")
		get_tree().quit(1)
		return

	var made: Array = []
	for spec in [[str(picked[0]), "b_014", "r_090"], [str(picked[1]), "b_002", "r_005"]]:
		var tid := str(spec[0])
		var coord: Vector2i = terrain.call("id_to_coord", tid)
		var iid: String = MatchState.add_building(str(spec[1]), str(spec[2]), tid, MatchState.LOCAL_PLAYER, "")
		game.call("emit_signal", "building_placed", tid, str(spec[1]), str(spec[2]), iid, coord)
		made.append({"iid": iid, "tile": tid, "bid": str(spec[1]), "coord": coord})
	await _settle(30)

	var cam: Camera2D = game.get_node_or_null("Camera2D") as Camera2D
	if cam != null:
		cam.set_process(false)
		cam.set_physics_process(false)
		cam.set("edge_pan_enabled", false)
		var cell = terrain.call("map_coord_for_tile_coord", (made[0] as Dictionary)["coord"])
		cam.position = terrain.call("to_global", terrain.call("map_to_local", cell))
		cam.zoom = Vector2(1.5, 1.5)
		cam.set("_target_zoom", Vector2(1.5, 1.5))
	var ui: Node = game.get_node_or_null("UILayer")
	if ui != null:
		(ui as CanvasLayer).visible = false
	await _settle(20)
	for m in made:
		print("[DEM] before %s on %s drawn=%s" % [(m as Dictionary)["bid"], (m as Dictionary)["tile"],
			str(bv.call("has_placement", str((m as Dictionary)["iid"])))])
	_shot("/tmp/poe_dem_before.png")

	# Demolish through the player's own route: queue, then let the job finish.
	for m in made:
		MatchState.start_demolish(str((m as Dictionary)["iid"]))
	for _t in MatchState.DEMOLISH_TURNS:
		MatchState.tick_demolish()
	await _settle(30)
	for m in made:
		print("[DEM] after  %s drawn=%s exists=%s" % [(m as Dictionary)["bid"],
			str(bv.call("has_placement", str((m as Dictionary)["iid"]))),
			str(MatchState.buildings.has(str((m as Dictionary)["iid"])))])
	_shot("/tmp/poe_dem_after.png")
	get_tree().quit(0)


func _shot(path: String) -> void:
	get_viewport().get_texture().get_image().save_png(path)
	print("[DEM] saved ", path)

func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
