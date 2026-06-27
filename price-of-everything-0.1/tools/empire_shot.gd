extends Node
## Dev tool: render the real game, open the Empire view (Milestone 1 shell), and save a
## PNG so the navy command screen can be eyeballed and the toggle path confirmed to work.
## Loading the full main.tscn also parse-checks world_map.gd / camera_controller.gd /
## empire_view.gd together. Needs a window (NOT --headless):
##   <godot> --path . res://tools/empire_shot.tscn --quit-after 900

func _ready() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(30)

	_seed_empire()
	await _settle(4)

	# world_map.gd creates the view in _ready() at this path.
	var ev: Node = game.get_node_or_null("UILayer/HUD/HUDContent/EmpireView")
	if ev == null:
		push_error("EmpireView not found — milestone 1 wiring failed")
		get_tree().quit(1)
		return

	# Confirm the camera gate exists and toggle the view open.
	var cam: Node = game.get_node_or_null("Camera2D")
	ev.call("toggle")
	await _settle(16)

	var blocked := cam != null and bool(cam.get("input_blocked"))
	var gw: Node = ev.get_node_or_null("GraphWorld")
	if gw != null:
		var sell: Array = gw.get("_sell_edges")
		var per_port: Dictionary = {}
		for e in sell:
			per_port[str(e["to"])] = int(per_port.get(str(e["to"]), 0)) + 1
		print("GRAPH: nodes=", (gw.get("_nodes") as Array).size(),
			"  edges=", (gw.get("_edges") as Array).size(),
			"  ports=", (gw.get("_ports") as Array).size(),
			"  sell=", sell.size(), "  per_port=", per_port)
	print("OPEN : EmpireView visible=", ev.visible, "  camera input_blocked=", blocked)
	_shot("/tmp/poe_empire.png")

	# Click-through: push a left click on a building panel and confirm the detail panel opens.
	var detail0: Node = game.get_node_or_null("UILayer/HUD/HUDContent/BuildingDetailPanel")
	if gw != null and detail0 != null:
		var panels: Array = gw.get("_panels")
		if panels.size() > 0:
			var pctrl: Control = panels[0]["ctrl"]
			var c := pctrl.get_global_rect().get_center()
			var click := InputEventMouseButton.new()
			click.button_index = MOUSE_BUTTON_LEFT
			click.pressed = true
			click.position = c
			click.global_position = c
			get_viewport().push_input(click)
			await _settle(8)
			print("CLICK: clicked panel iid=", pctrl.get("instance_id"), "  detail opened=", detail0.visible)
			# Close the detail again so the zoom/close shots stay clean.
			if detail0.visible:
				PanelStack.close_top()
				await _settle(4)

	# Diagnose the real input routing: push a wheel event and a pinch event through the viewport
	# (as a user device would) and confirm each actually reaches the graph and changes zoom.
	if gw != null:
		var z0 := float(gw.get("_view_zoom"))
		var wheel := InputEventMouseButton.new()
		wheel.button_index = MOUSE_BUTTON_WHEEL_UP
		wheel.pressed = true
		wheel.position = Vector2(1180.0, 664.0)
		wheel.global_position = Vector2(1180.0, 664.0)
		get_viewport().push_input(wheel)
		await _settle(2)
		var z1 := float(gw.get("_view_zoom"))
		var pinch := InputEventMagnifyGesture.new()
		pinch.factor = 1.3
		pinch.position = Vector2(1180.0, 664.0)
		get_viewport().push_input(pinch)
		await _settle(2)
		var z2 := float(gw.get("_view_zoom"))
		print("ZOOM-DIAG: start=", z0, "  after_wheel=", z1, "  after_pinch=", z2)
		# Zoom in further for the visual (toward the centre) and pan.
		gw.call("_zoom_at", Vector2(1180.0, 664.0), 1.6)
		gw.set("_view_offset", (gw.get("_view_offset") as Vector2) + Vector2(60.0, 0.0))
		gw.call("queue_redraw")
		await _settle(6)
		print("ZOOM : view_zoom=", gw.get("_view_zoom"))
		_shot("/tmp/poe_empire_zoom.png")

	# Close path: toggle again and confirm the map/camera are fully restored.
	var terrain: Node = game.get_node_or_null("TerrainLayer")
	ev.call("toggle")
	await _settle(16)
	var blocked2 := cam != null and bool(cam.get("input_blocked"))
	var terrain_visible := terrain != null and bool(terrain.get("visible"))
	print("CLOSE: EmpireView visible=", ev.visible, "  camera input_blocked=", blocked2,
		"  terrain restored=", terrain_visible)
	_shot("/tmp/poe_empire_closed.png")

	# Verify the refactored building detail panel still renders its 6 RAG indicators (now sharing
	# building_status.gd with the Empire view).
	var detail: Node = game.get_node_or_null("UILayer/HUD/HUDContent/BuildingDetailPanel")
	var b: Dictionary = MatchState.get_building("emp_0")
	if detail != null and not b.is_empty():
		detail.call("show_building", b)
		await _settle(10)
		print("DETAIL: panel visible=", detail.visible)
		_shot("/tmp/poe_detail.png")

	get_tree().quit(0)


## Place a handful of player-owned buildings across real tiles (with valid recipes, so edges form
## and outputs read), at mixed levels to show L2/L3 sizing. Tiles are pulled from whatever the
## match already seeded so they are guaranteed valid.
func _seed_empire() -> void:
	var tiles: Array = []
	for b in MatchState.buildings.values():
		var t := str(b.get("tile_id", ""))
		if t != "" and not tiles.has(t):
			tiles.append(t)
	tiles.sort()
	for fb in ["tile_9_10", "tile_7_9", "tile_10_11", "tile_8_9"]:
		if not tiles.has(fb):
			tiles.append(fb)

	var bids := ["b_001", "b_002", "b_003", "b_007", "b_008", "b_009", "b_010", "b_011",
		"b_012", "b_013", "b_014", "b_020", "b_021", "b_036"]
	var levels := [1, 1, 2, 1, 3, 1, 2, 1, 1, 2, 1, 1, 3, 1]
	var placed := 0
	for k in range(bids.size()):
		var bid: String = bids[k]
		var recs: Array = Catalog.get_recipes_for_building(bid)
		if recs.is_empty():
			continue
		var rid := str((recs[0] as Dictionary).get("recipe_id", ""))
		var tid: String = tiles[(k * 3) % tiles.size()]
		var iid := "emp_%d" % k
		MatchState.add_building(bid, rid, tid, "player_1", iid)
		if MatchState.buildings.has(iid):
			MatchState.buildings[iid]["level"] = levels[k]
		placed += 1
	print("seeded ", placed, " player buildings across ", tiles.size(), " candidate tiles")


func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame


func _shot(path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("SAVED ", path, " ", img.get_width(), "x", img.get_height())
