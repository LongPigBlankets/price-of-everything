extends Node
## Would a 90-degree-rotated sprite variant pack more buildings onto a tile?
##
## The question behind it: gameplay sprites have varied aspect ratios (industrial factory
## 53.8 x 31.2, offshore wind 38.1 x 80.0), and placement currently uses ONE orientation —
## chosen by the street the building fronts, not by the space that is free. A transposed
## variant could fit a gap the upright one cannot.
##
## This measures the HEADROOM before anything is built: how many buildings fail to place at
## all today, and how many of those failures a transposed footprint would have solved. A
## feature that fixes nothing is not worth its complexity.
##
##   <godot> --headless --path . res://tools/map_editor/sprite_pack_probe.tscn --quit-after 3000

const AuthoredMap := preload("res://scripts/authored_map.gd")

func _ready() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	for _i in 240:
		await get_tree().process_frame
	var bv: Node = get_tree().get_first_node_in_group("building_footprints")
	if bv == null:
		push_error("sprite_pack_probe: BuildingVisuals not found")
		get_tree().quit(1)
		return

	# What actually got drawn, against what the sim thinks exists.
	var placed: Array = bv.get("_placements")
	var drawn: Dictionary = {}
	for p in placed:
		drawn[str((p as Dictionary).get("instance_id", ""))] = true
	var total := 0
	var undrawn: Array = []
	for instance in MatchState.buildings.values():
		var iid := str((instance as Dictionary).get("instance_id", ""))
		var bid := str((instance as Dictionary).get("building_id", ""))
		if bid == "b_005" or bid == "b_015" or bid == "b_016":
			continue   # networks and forests are drawn elsewhere by design
		total += 1
		if not drawn.has(iid):
			undrawn.append({"iid": iid, "bid": bid,
				"tile": str((instance as Dictionary).get("tile_id", ""))})
	print("[PACK] %d buildings on the map, %d NOT drawn (%.1f%%)"
		% [total, undrawn.size(), 100.0 * float(undrawn.size()) / maxf(1.0, float(total))])

	# Aspect ratios: a transposed variant only helps a building that is not square.
	var visuals := preload("res://scenes/building_visuals.gd")
	var ink := preload("res://scripts/ink_building_gen.gd")
	var squarish := 0
	var oblong := 0
	print("[PACK] sprite aspect ratios (long side / short side):")
	var rows: Array = []
	for building_value in Catalog.all_buildings():
		var building: Dictionary = building_value
		var internal := str(building.get("internal_name", ""))
		var art_key := str(visuals.INK_ART_KEY.get(internal, internal))
		var frame: Vector2 = ink.level_frame(art_key, 3)
		if frame.x <= 0.0 or frame.y <= 0.0:
			continue
		var aspect := maxf(frame.x, frame.y) / maxf(0.001, minf(frame.x, frame.y))
		rows.append([aspect, internal])
		if aspect < 1.25:
			squarish += 1
		else:
			oblong += 1
	rows.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
	for i in mini(6, rows.size()):
		print("[PACK]    %-24s %.2f" % [rows[i][1], rows[i][0]])
	print("[PACK] %d oblong (aspect >= 1.25, a transpose changes their box), %d near-square"
		% [oblong, squarish])

	if not undrawn.is_empty():
		var by_tile: Dictionary = {}
		for entry in undrawn:
			var t := str((entry as Dictionary)["tile"])
			by_tile[t] = int(by_tile.get(t, 0)) + 1
		print("[PACK] undrawn by tile:")
		for t in by_tile.keys():
			print("[PACK]    %-14s %d" % [t, int(by_tile[t])])
	get_tree().quit(0)
