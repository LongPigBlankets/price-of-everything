extends Node
const Builder := preload("res://scripts/supply_chain_3d/world_builder.gd")

func points(poly: PackedVector2Array) -> Array:
	var out: Array = []
	for p in poly: out.append_array([p.x, p.y])
	return out

func _ready() -> void:
	TelemetryState.enabled = false; SaveLoad.autosave_enabled = false
	var terrain := preload("res://scripts/hex_map.gd").new()
	terrain.tile_set = load("res://assets/main_tileset.tres")
	terrain._generate_tile_data(); terrain._load_tile_overrides()
	var visual := preload("res://scripts/river_visuals.gd").new()
	visual.terrain_layer = terrain; visual.river_properties = visual._load_river_properties()
	var rivers := {}; var lines := {}
	for rec in visual.get_river_polylines():
		var tid := "tile_%d_%d" % [rec.coord.x + 1, rec.coord.y + 1]
		(rivers.get_or_add(tid, []) as Array).append(rec)
		(lines.get_or_add(tid, []) as Array).append(rec.points)
	var ground := Builder.Coast.ground_for(terrain, rivers, preload("res://scripts/empire_board_relief.gd").plates(terrain, lines), true)
	var report := {"regions": [], "lakes": [], "tiles": []}
	var boxes: Array = []
	for lake in HillBaked.lakes(): boxes.append(Builder.Legacy._box_of(lake).grow(100))
	for tid in ground.tiles:
		var tile: Dictionary = ground.tiles[tid]
		report.tiles.append({"id": tid, "label": Catalog.tile_label(tid), "center": [tile.center.x, tile.center.y], "height": tile.height})
		var ring: PackedVector2Array = ground.region(tid)
		var box := Builder.Legacy._box_of(ring)
		if boxes.any(func(b): return b.intersects(box)):
			report.regions.append({"id": tid, "level": tile.height, "p": points(ring), "rises": []})
			for rise in ground._rises(tid): report.regions[-1].rises.append({"level": rise.v, "p": points(rise.ring)})
	# Always start from the authored map, including after a previous water bake.
	for lake in HillBaked.lakes(): report.lakes.append({"p": points(lake), "level": 25.0})
	FileAccess.open("/private/tmp/water-inputs.json", FileAccess.WRITE).store_string(JSON.stringify(report))
	print("[WATER INPUTS] regions=", report.regions.size(), " lakes=", report.lakes.size())
	visual.free(); terrain.free(); get_tree().quit()
