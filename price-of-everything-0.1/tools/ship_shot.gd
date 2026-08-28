extends Node2D
## Dev tool: photograph harbour ships through one 12.5 s berthing cycle, so the drift,
## the growth and the fade can be checked as a sequence rather than guessed at from a single
## frame. Needs a window (NOT --headless):
##   <godot> --path . res://tools/ship_shot.tscn --quit-after 14000 -- \
##       --tile=tile_5_10 --zoom=2.0 --out=artifacts/smoke
##
## The clock is DRIVEN, not waited on: `SmokeVisuals._clock` is assigned directly and the
## layer repainted, so every frame lands at an exact phase and two runs produce identical
## images. Waiting on real time would make the sequence depend on frame pacing.
##
## Prints a census of every stack-carrying building first, which is how you find a refinery
## (3 stacks) or a chem plant (2) to point `--tile` at.

const ShotHarness := preload("res://tools/shot_harness.gd")

var _wm: Node
var _terrain: TileMapLayer
var _cam: Camera2D


func _ready() -> void:
	# SAFETY FIRST, before main.tscn exists: the project boots FULLSCREEN, and a tool
	# that grabs the whole screen for a 30 s world build reads as a frozen machine.
	ShotHarness.prepare_window(get_window())
	ShotHarness.arm_watchdog(self)
	var opt := _options()
	var tile_id := str(opt.get("tile", "tile_5_10"))
	var zoom := float(opt.get("zoom", 2.0))
	var out_prefix := str(opt.get("out", "artifacts/smoke"))
	var size := Vector2i(900, 700)
	var offset := _parse_vec(str(opt.get("offset", "")))

	SaveLoad.prepare_new_game(str(opt.get("start", "res://data/starts/metal_magnate.json")), {})
	get_viewport().set_disable_input(true)
	_wm = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_wm)
	for _i in 150:
		await get_tree().process_frame
	_terrain = _wm.get_node("%TerrainLayer")
	var grid := _wm.find_child("HexGridOverlay", true, false) as CanvasItem
	if grid != null:
		grid.visible = false
	var ui := _wm.get_node_or_null("UILayer") as CanvasLayer
	if ui != null:
		ui.visible = false
	_cam = get_viewport().get_camera_2d()
	if _cam == null:
		push_error("smoke_shot: no game camera")
		get_tree().quit(1)
		return
	_cam.set_process(false)
	_cam.set_physics_process(false)
	if "edge_pan_enabled" in _cam:
		_cam.set("edge_pan_enabled", false)

	var smoke := _wm.find_child("PortShipVisuals", true, false)
	if smoke == null:
		push_error("ship_shot: no PortShipVisuals node")
		get_tree().quit(1)
		return
	var visuals := _wm.find_child("BuildingVisuals", true, false)
	_census(visuals)

	var stacks: Array = smoke.call("smoke_stacks") if smoke.has_method("smoke_stacks") \
		else (visuals.call("smoke_stacks") as Array)
	var grey := 0
	for st_value in stacks:
		if bool((st_value as Dictionary).get("carbon", true)):
			grey += 1
	print("[SMOKE] %d chimney(s) on the map — %d grey (carbon), %d steam"
		% [stacks.size(), grey, stacks.size() - grey])
	# Which tiles actually show a STEAM plume, so a demo shot can be aimed at one.
	var steam_tiles: Dictionary = {}
	var placements: Variant = visuals.get("_placements")
	if placements is Array:
		for p_value in (placements as Array):
			var pl: Dictionary = p_value
			var pn := str(pl.get("iname", ""))
			if not (visuals.get("SMOKE_STACKS") as Dictionary).has(pn):
				continue
			if bool(visuals.call("_recipe_emits_carbon", str(pl.instance_id))):
				continue
			steam_tiles["%s (%s)" % [str(pl.get("tile_id", "")), pn]] = true
	var listed := 0
	for k in steam_tiles:
		print("[SMOKE]   steam at %s" % str(k))
		listed += 1
		if listed >= 10:
			print("[SMOKE]   ... more not listed")
			break

	var pos := _tile_pos(tile_id)
	if pos == Vector2.INF:
		push_error("smoke_shot: unknown tile %s" % tile_id)
		get_tree().quit(3)
		return
	# Aim at a real BERTH, not the tile centre: a harbour sits out on the coastline and the
	# tile's middle is usually inland, which is how the first run photographed empty grass.
	var berths_value: Variant = smoke.get("_berths")
	if berths_value is Array and not (berths_value as Array).is_empty():
		var first: Dictionary = (berths_value as Array)[0]
		pos = first["berth"]
		print("[SHIP] %d berth(s); aiming at %s (ship length %.1f)"
			% [(berths_value as Array).size(), str(pos), float(first["length"])])
	else:
		print("[SHIP] NO BERTHS — falling back to the tile centre")
	# CALLER CHECK: prove the port-call routes exist and actually reach the berth, which a
	# screenshot of open water cannot show.
	var routes: Variant = smoke.get("_callers")
	if routes is Array:
		print("[SHIP] %d caller route(s)" % (routes as Array).size())
		for ri in (routes as Array).size():
			var route: Dictionary = (routes as Array)[ri]
			var berth_pos: Vector2 = (route["berth"] as Dictionary)["berth"]
			var period: float = route["period"]
			var nearest := INF
			var at_berth := -1.0
			for k in 400:
				var u := period * float(k) / 400.0
				var place: Array = smoke.call("_caller_at", route, u)
				var gap: float = (place[0] as Vector2).distance_to(berth_pos)
				if gap < nearest:
					nearest = gap
					at_berth = u
			print("[SHIP]   route %d: period %.0fs, closest approach to berth %.1f u at t=%.0fs"
				% [ri, period, nearest, at_berth])
	_cam.position = pos + offset
	_cam.zoom = Vector2(zoom, zoom)
	if "_target_zoom" in _cam:
		_cam.set("_target_zoom", _cam.zoom)
	for _i in 12:
		await get_tree().process_frame

	# One full period, sampled six ways. 1.99 rather than 2.0 so the last frame is the puff
	# about to die, not the next one already born — the loop seam is the thing to inspect.
	for t in [0.0, 1.5, 2.5, 5.0, 8.0, 11.0]:
		smoke.set("_clock", float(t))
		(smoke as CanvasItem).queue_redraw()
		await get_tree().process_frame
		RenderingServer.force_draw()
		var image := get_viewport().get_texture().get_image()
		var crop := Vector2i(mini(size.x, image.get_width()), mini(size.y, image.get_height()))
		var origin := Vector2i((image.get_width() - crop.x) / 2, (image.get_height() - crop.y) / 2)
		var path := "%s_t%03d.png" % [out_prefix, int(float(t) * 100.0)]
		image.get_region(Rect2i(origin, crop)).save_png(path)
		print("[SMOKE] %s" % path)
	print("[SMOKE] done")
	get_tree().quit(0)


## Which buildings on this map carry stacks, and where — so a tile with a 3-stack refinery
## can be found without reading the start config by hand.
func _census(visuals: Node) -> void:
	if visuals == null:
		return
	var placements: Variant = visuals.get("_placements")
	if not (placements is Array):
		return
	var spec: Dictionary = visuals.get("SMOKE_STACKS")
	var per_tile: Dictionary = {}
	var totals: Dictionary = {}
	for p_value in (placements as Array):
		var p: Dictionary = p_value
		var iname := str(p.get("iname", ""))
		if not spec.has(iname):
			continue
		totals[iname] = int(totals.get(iname, 0)) + 1
		var key := "%s|%s" % [str(p.get("tile_id", "")), iname]
		per_tile[key] = int(per_tile.get(key, 0)) + 1
	print("[SMOKE] stack-carrying buildings by type: ", totals)
	var shown := 0
	for key in per_tile:
		var bits := str(key).split("|")
		print("[SMOKE]   %s has %d x %s (%d stack(s) each)"
			% [bits[0], int(per_tile[key]), bits[1], int((spec[bits[1]] as Dictionary)["count"])])
		shown += 1
		if shown >= 14:
			print("[SMOKE]   ... more not listed")
			break


func _tile_pos(tile_id: String) -> Vector2:
	if not _terrain.has_method("id_to_coord"):
		return Vector2.INF
	var coord: Vector2i = _terrain.id_to_coord(tile_id)
	if coord == Vector2i(-1, -1):
		return Vector2.INF
	return _terrain.map_to_local(_terrain.map_coord_for_tile_coord(coord))


func _options() -> Dictionary:
	var out := {}
	for arg in OS.get_cmdline_user_args():
		var a := str(arg)
		if not a.begins_with("--") or not a.contains("="):
			continue
		var bits := a.substr(2).split("=", true, 1)
		if bits.size() == 2:
			out[str(bits[0])] = str(bits[1])
	return out


func _parse_vec(raw: String) -> Vector2:
	var bits := raw.split(",")
	if bits.size() == 2 and str(bits[0]).is_valid_float() and str(bits[1]).is_valid_float():
		return Vector2(float(bits[0]), float(bits[1]))
	return Vector2.ZERO
