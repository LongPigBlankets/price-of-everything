extends Node
## How expensive is a zone mask, really?
##
## The question it answers: does checking decorative overlap at run time (the CLEAR /
## SACRIFICIAL_OK / ANY tiers) cost enough to prefer pre-designated reserve zones over one
## zone plus a fallback. Measured rather than argued.
##
##   <godot> --headless --path . res://tools/map_editor/zone_mask_bench.tscn --quit-after 900

const AuthoredMap := preload("res://scripts/authored_map.gd")

func _ready() -> void:
	var terrain := TileMapLayer.new()
	terrain.tile_set = load("res://assets/main_tileset.tres")
	terrain.set_script(load("res://scripts/hex_map.gd"))
	add_child(terrain)
	await get_tree().process_frame
	var bv := preload("res://scenes/building_visuals.gd").new()
	add_child(bv)
	await get_tree().process_frame
	bv.terrain_layer = terrain

	var tile_id := "tile_9_10"
	var coord: Vector2i = terrain.id_to_coord(tile_id)
	var centre: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(coord))

	# A zone covering most of a tile is the worst case: every land cell is inside it, so
	# every cell also gets tested against the fabric.
	var zone: Array = []
	for offset in [Vector2(-230, -200), Vector2(230, -200), Vector2(230, 200), Vector2(-230, 200)]:
		zone.append([centre.x + offset.x, centre.y + offset.y])

	print("[BENCH] decor  cells  CLEAR(ms)  SACRIF(ms)  ANY(ms)   3 tiers  1 tier")
	for decor_count in [0, 5, 15, 40]:
		var decor: Array = []
		for i in decor_count:
			var at := centre + Vector2(-180.0 + 60.0 * float(i % 7), -150.0 + 70.0 * float(i / 7))
			decor.append({"id": "m%d" % i, "form": "rect", "pos": [at.x, at.y],
				"rot": 0.0, "size": [55, 40], "sacrificial": i % 2 == 0})
		AuthoredMap.set_document_for_tests({"version": AuthoredMap.SCHEMA_VERSION,
			"settlements": {"s": {"tiles": [tile_id], "decor": decor,
				"zones": [{"id": "z1", "kind": "industrial", "tiles": [tile_id],
					"outline": zone}]}}})
		bv._tile_land.erase(tile_id)
		bv._drop_zone_masks(tile_id)
		bv.ensure_block_template_for(tile_id, coord)

		var times: Array = []
		var cells := 0
		for tier in [bv.ZoneTier.CLEAR, bv.ZoneTier.SACRIFICIAL_OK, bv.ZoneTier.ANY]:
			bv._drop_zone_masks(tile_id)
			var t0 := Time.get_ticks_usec()
			var mask: PackedByteArray = bv._zone_mask(tile_id, coord, "industrial", tier)
			times.append(float(Time.get_ticks_usec() - t0) / 1000.0)
			cells = mask.size()
		print("[BENCH] %5d  %5d  %9.2f  %10.2f  %7.2f   %7.2f  %6.2f"
			% [decor_count, cells, times[0], times[1], times[2],
				times[0] + times[1] + times[2], times[2]])

	AuthoredMap.set_document_for_tests({})
	AuthoredMap.reset_for_tests()
	print("[BENCH] note: masks are built ONCE per tile+kind+tier and cached for the run.")
	get_tree().quit(0)
