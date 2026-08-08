extends Node
## Dump the layout of the busiest block tiles as JSON, for offline plotting.
##   <godot> --headless --path . res://tools/block_dump.tscn --quit-after 3000
## Writes /tmp/poe_block_dump.json.
##
## Exists because the windowed close-up harness captures frames with the building
## layer unpainted (verified: camera correct, 7 placements inside the view rect,
## nothing drawn). The layout itself is data, so plot the data rather than fight
## the capture — this also makes the packing measurable instead of eyeballed.

const TILES := 2

func _ready() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	for _i in 240:
		await get_tree().process_frame
	var bv: Node = get_tree().get_first_node_in_group("building_footprints")
	var placements: Array = bv.get("_placements")
	var tile_segs: Dictionary = bv.get("_tile_segs")
	var terrain: Node = game.get_node("%TerrainLayer")

	# Select on the TEMPLATE, not on `via`: `via` defaults to "block" for any path
	# that does not tag itself, so filtering on it picks up farms and mislabels
	# which tiles actually laid a block.
	var tmpls: Dictionary = bv.get("_tile_block_templates")
	var count: Dictionary = {}
	for tid in tmpls:
		var t: Dictionary = tmpls[tid]
		if not bool(t.get("perimeter", false)):
			continue
		var claimed := 0
		for c in (t.get("claimed", []) as Array):
			if bool(c):
				claimed += 1
		if claimed > 0:
			count[str(tid)] = claimed
	var tiles: Array = count.keys()
	tiles.sort_custom(func(a, b) -> bool: return int(count[a]) > int(count[b]))
	print("[BLOCKDUMP] perimeter blocks with claims: %d" % tiles.size())

	var out: Dictionary = {"tiles": []}
	for i in mini(TILES, tiles.size()):
		var tid: String = tiles[i]
		var coord: Vector2i = Vector2i(-1, -1)
		var blds: Array = []
		for p in placements:
			if str(p.tile_id) != tid:
				continue
			coord = p.coord
			var vs: Array = []
			for v in (p.verts as PackedVector2Array):
				vs.append([v.x, v.y])
			blds.append({"verts": vs, "via": str(p.get("via", "")),
				"iname": str(p.get("iname", "")), "cat": str(p.cat)})
		# Road segments are stored tile-relative; lift them to world with the tile centre.
		var origin: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(coord))
		var segs: Array = []
		for s in (tile_segs.get(tid, []) as Array):
			var a: Vector2 = origin + (s[0] as Vector2)
			var b: Vector2 = origin + (s[1] as Vector2)
			segs.append([[a.x, a.y], [b.x, b.y]])
		var t: Dictionary = tmpls[tid]
		var quad: Array = []
		for v in (t.get("quad", PackedVector2Array()) as PackedVector2Array):
			quad.append([v.x, v.y])
		var lots: Array = []
		for li in (t.get("lots", []) as Array).size():
			var lc: Vector2 = (t.lots as Array)[li]
			lots.append({"c": [lc.x, lc.y], "claimed": bool((t.claimed as Array)[li]),
				"row": int((t.rows as Array)[li])})
		# Template lots and the quad are TILE-RELATIVE (_finalize takes center_rel);
		# verts are world. Ship the tile origin so the plotter can put them in one space.
		out.tiles.append({"tile_id": tid, "buildings": blds, "roads": segs,
			"block_count": int(count[tid]), "quad": quad, "lots": lots,
			"origin": [origin.x, origin.y]})
		print("[BLOCKDUMP] %s: %d buildings (%d block), %d road segs" % [
			tid, blds.size(), int(count[tid]), segs.size()])
	var f := FileAccess.open("/tmp/poe_block_dump.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()
	print("[BLOCKDUMP] wrote /tmp/poe_block_dump.json")
	get_tree().quit()
