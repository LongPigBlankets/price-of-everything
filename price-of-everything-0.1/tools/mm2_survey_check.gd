extends Node
## Headless check: New Game with the "All tiles surveyed at game start" override
## reveals every tile. Boots coal_baron with the override, then samples the map.

func _ready() -> void:
	SaveLoad.prepare_new_game("res://data/starts/coal_baron.json", {"ruleset": {"survey_all_tiles": true}})
	var snap: Dictionary = SaveLoad._pending_snapshot
	var rules: Dictionary = (snap.get("match", {}) as Dictionary).get("ruleset", {})
	print("[CHK] pending ruleset.survey_all_tiles = ", rules.get("survey_all_tiles"))

	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	var frames := 0
	while frames < 4000 and main.get("build_complete") != true:
		await get_tree().process_frame
		frames += 1
	print("[CHK] build_complete=", main.get("build_complete"), " after ", frames, " frames")

	var terrain = main.get_node_or_null("%TerrainLayer")
	if terrain == null:
		print("[CHK] FAIL no terrain")
		get_tree().quit(1)
		return
	var total := 0
	var surveyed := 0
	for coord in terrain.tiles:
		var tid := str((terrain.tiles[coord] as Dictionary).get("id", ""))
		if tid == "":
			continue
		total += 1
		if MatchState.is_tile_surveyed(tid):
			surveyed += 1
	print("[CHK] surveyed %d / %d tiles (expect all)" % [surveyed, total])

	# Control: same start WITHOUT the override should leave most tiles unsurveyed.
	get_tree().quit(0 if (total > 0 and surveyed == total) else 1)
