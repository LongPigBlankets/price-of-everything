extends Node2D
## Dev tool: render the Ownership mapmode's chunk gauge. A real game reaches these holdings over
## dozens of turns, so this buys land and places buildings directly through the real MatchState
## API on four neighbouring tiles: untouched, part-owned, part-owned-and-built, and fully owned.
## The hover count is driven by warping the mouse onto the built tile.
##   "$GODOT_BIN" --path . res://tools/ownership_mapmode_shot.tscn --quit-after 900
var _wm

func _ready() -> void:
	get_window().size = Vector2i(1920, 1080)
	_wm = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_wm)
	for _i in range(160):
		await get_tree().process_frame

	var terrain = _wm.find_child("TerrainLayer", true, false)
	if terrain == null:
		print("[OWN_MM] no terrain layer"); get_tree().quit(1); return
	var build_id := ""
	for b in Catalog.all_buildings():
		var bd: Dictionary = b
		if str(bd.get("category", "")).to_lower() != "infrastructure":
			build_id = str(bd.get("id", bd.get("building_id", "")))
			if build_id != "":
				break

	# Tiles near the MIDDLE of the map: the camera clamps to the map bounds, so a tile on the
	# top row can never be centred and the shot ends up with the subject in the margin.
	var land: Array = []
	var sum := Vector2.ZERO
	for coord in terrain.tiles:
		var td: Dictionary = terrain.tiles[coord]
		var ttype := str(td.get("type", ""))
		if ttype == "sea" or ttype == "deep_sea":
			continue
		var tid := str(td.get("id", ""))
		if tid == "":
			continue
		var pos: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(coord))
		land.append({"id": tid, "coord": coord, "pos": pos})
		sum += pos
	var map_centre: Vector2 = sum / float(maxi(1, land.size()))
	land.sort_custom(func(a, b): return a.pos.distance_to(map_centre) < b.pos.distance_to(map_centre))
	var picks: Array = land.slice(0, 4)
	var centre := Vector2.ZERO
	for p0 in picks:
		centre += p0.pos
	centre /= float(maxi(1, picks.size()))
	if picks.size() < 4:
		print("[OWN_MM] not enough land tiles"); get_tree().quit(1); return

	MatchState.money = 100000.0
	# Tile 0: untouched. 1: a quarter owned. 2: half owned with buildings on it.
	# 3: the whole tile owned.
	MatchState.purchase_tile_land(str(picks[1].id), 5)     # 5 patches = 50 of 200 units
	MatchState.purchase_tile_land(str(picks[2].id), 10)
	MatchState.purchase_tile_land(str(picks[3].id), 20)
	if build_id != "":
		for _n in range(3):
			MatchState.add_building(build_id, "", str(picks[2].id))
		# Tile 3 is fully owned and built out to 150 of its 200 units: enough estate to fill the
		# left column and spill halfway up the right, which is what the half-width split exists
		# for. (add_building here bypasses the land gate a real build goes through, so keep the
		# figure under the tile's owned land or the display clamps to full.)
		for _n in range(5):
			MatchState.add_building(build_id, "", str(picks[3].id))
	for p in picks:
		var tid: String = str(p.id)
		print("[OWN_MM] %s owned=%d/%d built=%.0f" % [
			tid, MatchState.get_tile_land_owned(tid), MatchState.MAX_TILE_LAND,
			MatchState.get_tile_player_space_used(tid)])

	# Placing buildings pops "Built Mine" toasts that sit over the legend. They are the game
	# reacting correctly to the setup; just clear them.
	for _i in range(6):
		await get_tree().process_frame
	for node in _wm.find_children("*", "Control", true, false):
		if node.get_script() != null \
				and str(node.get_script().resource_path).ends_with("toast_manager.gd"):
			for t in (node as Node).get_children():
				t.queue_free()

	var cam := get_viewport().get_camera_2d()
	if cam != null:
		cam.set("edge_pan_enabled", false)
		# The controller smooths `zoom` toward `_target_zoom` every frame, so assigning `zoom`
		# alone is overwritten on the next tick.
		var z: float = float(cam.get("zoom_max"))
		cam.set("_target_zoom", Vector2(z, z))
		cam.zoom = Vector2(z, z)
		if cam.has_method("pan_to_world"):
			cam.pan_to_world(centre, 0.01)
		else:
			cam.position = centre
	for _i in range(60):
		await get_tree().process_frame

	MapMode.set_sentinel_mode(MapMode.Mode.OWNERSHIP, MapMode.OWNERSHIP_SENTINEL)
	for _i in range(12):
		await get_tree().process_frame

	var overlay = _wm.find_child("OwnershipOverlay", true, false)
	if overlay == null:
		print("[OWN_MM] overlay not found"); get_tree().quit(1); return
	print("[OWN_MM] mode=%d tiles=%d bands_per_tile=%d" % [
		MapMode.current_mode, overlay._tiles.size(), overlay._band_polys.size()])
	for p in picks:
		var tid: String = str(p.id)
		if overlay._by_tile_id.has(tid):
			var e: Dictionary = overlay._tiles[overlay._by_tile_id[tid]]
			print("[OWN_MM]   %s bands_owned=%d halves_built=%d (left %d, right %d)" % [
				tid, e.bands_owned, e.halves_built, mini(e.halves_built, e.bands_owned),
				clampi(e.halves_built - e.bands_owned, 0, e.bands_owned)])

	# Hover the built tile so the white building count is in the frame.
	var built_centre: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(picks[2].coord))
	var xform := get_viewport().get_canvas_transform()
	Input.warp_mouse(xform * built_centre)
	for _i in range(10):
		await get_tree().process_frame
	print("[OWN_MM] hovered='%s'" % overlay._hovered_id)
	for r in overlay._hover_rows:
		print("[OWN_MM]   plate | %-22s %s" % [str(r[0]), str(r[1])])
	# Warping the cursor can leave a bottom-menu panel showing over the map. Close them so the
	# shot is of the mapmode, not of whatever the pointer brushed on the way.
	var hud2 = _wm.get_node_or_null("UILayer/HUD")
	if hud2 != null and hud2.has_method("_hide_all_panels"):
		hud2.call("_hide_all_panels")
	for _i in range(6):
		await get_tree().process_frame

	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://ownership_mapmode_shot.png")
	print("SAVED ownership_mapmode_shot.png")
	get_tree().quit()
