extends Node
## Asks a named tile whether it can form a block, and reports what it got.
##   <godot> --headless --path . res://tools/block_probe.tscn --quit-after 6000
## Set BLOCK_DEBUG=true in building_visuals.gd to see the per-tile reason.

const TILES := ["tile_6_12", "tile_6_13", "tile_5_10", "tile_9_16"]

func _ready() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	for _i in 240:
		await get_tree().process_frame
	var bv: Node = get_tree().get_first_node_in_group("building_footprints")
	var terrain: Node = game.get_node("%TerrainLayer")
	print("\n=== BLOCK PROBE ===")
	for tid in TILES:
		var coord: Vector2i = terrain.id_to_coord(tid)
		if coord == Vector2i(-1, -1):
			print("%s: unknown tile" % tid)
			continue
		var mode: bool = bv.call("_use_block_mode", tid, coord)
		var formed: bool = bv.call("ensure_block_template_for", tid, coord)
		var tmpl: Dictionary = (bv.get("_tile_block_templates") as Dictionary).get(tid, {})
		var lots: int = (tmpl.get("lots", []) as Array).size()
		var segs: int = ((bv.get("_tile_segs") as Dictionary).get(tid, []) as Array).size()
		var placed := 0
		for p in (bv.get("_placements") as Array):
			if str(p.get("tile_id", "")) == tid:
				placed += 1
		print("%s: block_mode=%s formed=%s lots=%d road_segs=%d placed_buildings=%d"
			% [tid, str(mode), str(formed), lots, segs, placed])
	# Reproduce the owner's case: keep building on one tile and see where the
	# buildings actually land.
	var tid := "tile_6_12"
	var coord: Vector2i = terrain.id_to_coord(tid)
	var via: Dictionary = {}
	for i in 20:
		var iid := MatchState.add_building("b_007", "", tid, "player", "probe_%d" % i)
		bv.call("on_building_placed", tid, "b_007", "", str(iid), coord)
	var tmpl2: Dictionary = (bv.get("_tile_block_templates") as Dictionary).get(tid, {})
	var claimed := 0
	for c in (tmpl2.get("claimed", []) as Array):
		if bool(c):
			claimed += 1
	for p in (bv.get("_placements") as Array):
		if str(p.get("tile_id", "")) == tid:
			var v := str(p.get("via", "?"))
			via[v] = int(via.get(v, 0)) + 1
	print("\nafter +20 factories on %s: lots=%d claimed=%d rows_max=%s" % [
		tid, (tmpl2.get("lots", []) as Array).size(), claimed,
		str((tmpl2.get("rows", []) as Array).back() if not (tmpl2.get("rows", []) as Array).is_empty() else -1)])
	print("placed VIA: %s" % str(via))
	# Frame the tile and save a PNG (windowed runs only). Camera controller is
	# suspended, or its zoom smoothing + bounds clamp snap the view back.
	var cam := get_viewport().get_camera_2d()
	if cam != null and DisplayServer.get_name() != "headless":
		cam.set_process(false)
		cam.set_physics_process(false)
		var grid: Node = game.find_child("HexGridOverlay", true, false)
		if grid != null:
			(grid as CanvasItem).visible = false
		cam.position = terrain.map_to_local(terrain.map_coord_for_tile_coord(coord))
		cam.zoom = Vector2(1.5, 1.5)
		for _j in 20:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/poe_block_probe.png")
		print("[SHOT] /tmp/poe_block_probe.png")
	get_tree().quit(0)
