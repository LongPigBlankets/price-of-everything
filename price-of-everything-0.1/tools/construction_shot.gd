extends Node2D
## Dev tool: queue real construction projects on one tile and photograph them through a full
## 4 s crane cycle. Needs a window (NOT --headless):
##   <godot> --path . res://tools/construction_shot.tscn --quit-after 16000 -- \
##       --tile=tile_5_10 --zoom=2.2 --out=artifacts/site
##
## The builds are started through `Construction.start_on_tile`, the same call the Construct
## panel makes, so the sites are genuine projects rather than a mock — which is the only way
## to prove `_is_under_construction` actually drives the beige, and that a site turns into a
## finished building when the project promotes.
##
## Three projects on ONE tile, because the 1 s per-site offset is the thing worth seeing.
## The clock is DRIVEN (`ConstructionVisuals._clock` assigned directly), never waited on, so
## the frames land on exact phases and two runs match.

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
	var zoom := float(opt.get("zoom", 2.2))
	var out_prefix := str(opt.get("out", "artifacts/site"))
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
		push_error("construction_shot: no game camera")
		get_tree().quit(1)
		return
	_cam.set_process(false)
	_cam.set_physics_process(false)
	if "edge_pan_enabled" in _cam:
		_cam.set("edge_pan_enabled", false)

	var cranes := _wm.find_child("ConstructionVisuals", true, false)
	var visuals := _wm.find_child("BuildingVisuals", true, false)
	if cranes == null or visuals == null:
		push_error("construction_shot: ConstructionVisuals / BuildingVisuals missing")
		get_tree().quit(1)
		return

	# Stock the tile so the builds are not refused for want of materials, then queue three.
	var coord: Vector2i = _terrain.id_to_coord(tile_id)
	for build_id in ["b_002", "b_007", "b_003"]:
		for good_id in Construction.requirements_for(build_id):
			Stockpile.add(tile_id, str(good_id), int(Construction.requirements_for(build_id)[good_id]) + 50)
	var started: Array = []
	for build_id in ["b_002", "b_007", "b_003"]:
		var iid := Construction.start_on_tile(build_id, "", tile_id, 0.0)
		if iid == "":
			print("[SITE] refused: %s" % build_id)
			continue
		started.append(iid)
		if _wm.has_signal("building_placed"):
			_wm.emit_signal("building_placed", tile_id, build_id, "", iid, coord)
	print("[SITE] started %d project(s): %s" % [started.size(), str(started)])
	print("[SITE] Construction.construction_projects = %d" % Construction.construction_projects.size())
	await get_tree().process_frame
	(visuals as CanvasItem).queue_redraw()
	for _i in 6:
		await get_tree().process_frame

	var sites: Array = visuals.call("construction_sites")
	print("[SITE] BuildingVisuals reports %d site(s)" % sites.size())
	for s_value in sites:
		var s: Dictionary = s_value
		print("[SITE]   index=%d reach=%.1f" % [int(s["index"]), float(s["reach"])])

	var pos := _tile_pos(tile_id)
	if pos == Vector2.INF:
		push_error("construction_shot: unknown tile %s" % tile_id)
		get_tree().quit(3)
		return
	_cam.position = pos + offset
	_cam.zoom = Vector2(zoom, zoom)
	if "_target_zoom" in _cam:
		_cam.set("_target_zoom", _cam.zoom)
	for _i in 12:
		await get_tree().process_frame

	# A full 4 s cycle: out over the first two seconds, back over the second two.
	for t in [0.0, 0.5, 1.0, 1.5, 2.0, 3.0]:
		cranes.set("_clock", float(t))
		(cranes as CanvasItem).queue_redraw()
		await get_tree().process_frame
		RenderingServer.force_draw()
		var image := get_viewport().get_texture().get_image()
		var crop := Vector2i(mini(size.x, image.get_width()), mini(size.y, image.get_height()))
		var origin := Vector2i((image.get_width() - crop.x) / 2, (image.get_height() - crop.y) / 2)
		var path := "%s_t%03d.png" % [out_prefix, int(float(t) * 100.0)]
		image.get_region(Rect2i(origin, crop)).save_png(path)
		print("[SITE] %s" % path)

	# And prove a site stops being a site: promote everything, then shoot once more.
	for iid in started:
		Construction.construction_projects.erase(iid)
		MatchState.add_building("b_002", "", tile_id, MatchState.LOCAL_PLAYER, str(iid))
	Construction.construction_completed.emit(str(started[0]) if not started.is_empty() else "", tile_id)
	(visuals as CanvasItem).queue_redraw()
	(cranes as CanvasItem).queue_redraw()
	for _i in 8:
		await get_tree().process_frame
	RenderingServer.force_draw()
	var done := get_viewport().get_texture().get_image()
	var dcrop := Vector2i(mini(size.x, done.get_width()), mini(size.y, done.get_height()))
	var dorigin := Vector2i((done.get_width() - dcrop.x) / 2, (done.get_height() - dcrop.y) / 2)
	done.get_region(Rect2i(dorigin, dcrop)).save_png("%s_done.png" % out_prefix)
	print("[SITE] %s_done.png  (projects left: %d)" % [out_prefix, Construction.construction_projects.size()])
	print("[SITE] done")
	get_tree().quit(0)


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
