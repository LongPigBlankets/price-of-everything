extends Node
## Dev tool: load a fresh game and print every tile that has an NPC-owned building at
## start (ports, ruins, start companies), with that tile's current infrastructure, so
## we can ensure they all carry cables in tile_properties.csv. Headless:
##   <godot> --headless --path . res://tools/npc_tiles.tscn --quit-after 600

func _ready() -> void:
	SaveLoad.prepare_new_game("res://data/starts/default.json")
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await _settle(150)
	var hex: Node = get_tree().get_first_node_in_group("hex_map")
	var by_tile: Dictionary = {}
	for iid in MatchState.buildings:
		var b: Dictionary = MatchState.buildings[iid]
		if MatchState.is_player_owned(b):
			continue
		var t: String = str(b.get("tile_id", ""))
		if t == "":
			continue
		if not by_tile.has(t):
			by_tile[t] = []
		(by_tile[t] as Array).append(str(b.get("building_id", "")))
	var keys: Array = by_tile.keys()
	keys.sort()
	for t in keys:
		var infra: Variant = ""
		if hex != null and hex.has_method("get"):
			var tiles: Variant = hex.get("tiles")
			if tiles is Dictionary:
				for coord in (tiles as Dictionary):
					var td: Dictionary = (tiles as Dictionary)[coord]
					if str(td.get("id", "")) == t:
						infra = td.get("infrastructure_present", [])
						break
		print("NPCTILE %s buildings=%s infra=%s" % [t, str(by_tile[t]), str(infra)])
	print("NPCTILE_COUNT ", keys.size())
	get_tree().quit(0)

func _settle(frames: int) -> void:
	for _i in range(frames):
		await get_tree().process_frame
