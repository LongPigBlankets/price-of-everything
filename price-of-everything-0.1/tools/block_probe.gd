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
	# Service lanes: how many tiles earned one, and how long it came out.
	var lanes: Dictionary = bv.get("_service_segs") as Dictionary
	var laid := 0
	for k in lanes:
		var segs2: Array = lanes[k]
		if segs2.is_empty():
			continue
		laid += 1
		var run := 0.0
		for s in segs2:
			run += (s[0] as Vector2).distance_to(s[1] as Vector2)
		print("  lane %s: %d chords, %.0fu long" % [k, segs2.size(), run])
	print("service lanes: %d laid / %d tiles considered" % [laid, lanes.size()])
	var mine: Array = lanes.get(tid, [])
	if not mine.is_empty():
		var pts := PackedStringArray()
		pts.append("(%.0f,%.0f)" % [(mine[0][0] as Vector2).x, (mine[0][0] as Vector2).y])
		for s in mine:
			pts.append("(%.0f,%.0f)" % [(s[1] as Vector2).x, (s[1] as Vector2).y])
		print("%s lane (rel to tile centre): %s" % [tid, " -> ".join(pts)])
	# Nothing may sit ON a lane: report every footprint closer than SERVICE_CLEAR.
	var breaches := 0
	for k in lanes:
		var lsegs: Array = lanes[k]
		if lsegs.is_empty():
			continue
		for p in (bv.get("_placements") as Array):
			if str(p.get("tile_id", "")) != str(k):
				continue
			var origin: Vector2 = bv.call("_tile_center_world_pos", p.get("coord", Vector2i.ZERO))
			var vs: PackedVector2Array = p.get("verts", PackedVector2Array())
			var near := 1.0e9
			for v in vs:
				for s in lsegs:
					near = minf(near, bv.call("_pt_seg_dist", v - origin, s[0], s[1]))
			if near < 4.0:
				breaches += 1
				if breaches <= 6:
					print("  BREACH %s %s: %.1fu from its lane" % [k, str(p.get("building_id", "?")), near])
	print("lane breaches (footprint within SERVICE_CLEAR): %d" % breaches)
	MapStyle.set_ink(true)
	# Frame the tile and save a PNG (windowed runs only). Camera controller is
	# suspended, or its zoom smoothing + bounds clamp snap the view back.
	var cam := get_viewport().get_camera_2d()
	if cam != null and DisplayServer.get_name() != "headless":
		cam.set_process(false)
		cam.set_physics_process(false)
		var grid: Node = game.find_child("HexGridOverlay", true, false)
		if grid != null:
			(grid as CanvasItem).visible = false
		# Frame a tile that actually got a lane, so the shot shows the feature.
		var shot_coord := coord
		for k in lanes:
			if not (lanes[k] as Array).is_empty():
				shot_coord = terrain.id_to_coord(str(k))
				print("[SHOT] framing %s" % str(k))
				break
		cam.position = terrain.map_to_local(terrain.map_coord_for_tile_coord(shot_coord))
		cam.zoom = Vector2(2.4, 2.4)
		for _j in 20:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/poe_block_probe.png")
		print("[SHOT] /tmp/poe_block_probe.png")
	get_tree().quit(0)
