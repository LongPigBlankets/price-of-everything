extends Node
## Dev tool: the supply-chain view in MASS mode. Boots the real game, seeds the thirteen
## buildings the sprite-swap shot uses (over the mass threshold), opens the view and shoots
## the resting grid, then opens the whole-chain chart on the first coal mine and shoots it.
## Needs a window (NOT --headless):
##   <godot> --path . res://tools/empire_mass_shot.tscn --quit-after 1500
## Writes /tmp/poe_mass_rest.png and /tmp/poe_mass_chain.png.


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
	# POE_EMPIRE_VARIANT (crossing study): base | 1 (trunks) | 2 (port order) | 3 (trunks + port buses) | all
	var variant := OS.get_environment("POE_EMPIRE_VARIANT") if OS.has_environment("POE_EMPIRE_VARIANT") else "base"
	var EL := load("res://scripts/empire_layout.gd")
	var GW := load("res://scripts/empire_graph_world.gd")
	GW.opt_trunks = variant in ["1", "3", "all", "default"]
	EL.opt_port_order = variant in ["2", "all", "default"]
	GW.opt_port_buses = variant in ["3", "all", "default"]
	EL.opt_channels = variant in ["1", "3", "all", "default"]
	# POE_EMPIRE_THRESHOLD lifts the mass threshold so the resting shot is the full FLOW view.
	if OS.has_environment("POE_EMPIRE_THRESHOLD"):
		EL.mass_threshold = int(OS.get_environment("POE_EMPIRE_THRESHOLD"))
	ev.call("toggle")
	await _settle(20)
	var gw: Node = ev.get_node_or_null("GraphWorld")
	print("MASS: ", gw.get("_mass") if gw != null else "?", " variant ", variant)
	_shot("/tmp/poe_mass_rest_%s.png" % variant)
	# Hover the first panel: the full card should appear over the compact plate.
	if gw != null:
		for pan in (gw.get("_panels") as Array):
			var ctrl: Control = pan["ctrl"]
			if ctrl.has_method("_on_hover"):
				ctrl.call("_on_hover", true)
				await _settle(4)
				_shot("/tmp/poe_mass_hover_%s.png" % variant)
				ctrl.call("_on_hover", false)
				break
	if OS.has_environment("POE_EMPIRE_THRESHOLD"):
		get_tree().quit(0)
		return
	if gw != null:
		gw.call("focus_on", "mass_6", true)
		await _settle(40)
		gw.call("_reposition_panels")
		var rep: Dictionary = gw.call("audit")
		print("CHAIN members: ", (gw.get("_focus_members") as Dictionary).size(),
			"  collisions: ", int(rep["total"]), "  crossings: ", int((rep["crossings"] as Dictionary)["total"]))
		print("CHAIN collision counts: ", JSON.stringify(rep["counts"]))
		for line in rep["named"]:
			print("CHAIN pair: ", line)
		var cr: Dictionary = (rep["crossings"] as Dictionary)["pairs"]
		for k in cr:
			print("CHAIN crossing: ", k, " x", int(cr[k]))
	_shot("/tmp/poe_mass_chain_%s.png" % variant)
	get_tree().quit(0)


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
		var iid := "mass_%d" % k
		MatchState.add_building(bids[k], rid, tiles[(k * 3) % tiles.size()], "player_1", iid)
		if MatchState.buildings.has(iid):
			MatchState.buildings[iid]["level"] = levels[k]


func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame


func _shot(path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("SAVED ", path)
