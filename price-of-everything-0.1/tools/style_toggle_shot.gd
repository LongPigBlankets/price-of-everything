extends Node2D
## Dev tool: what do the `toggle ink` / `toggle plate` / `toggle midcentury` cheats actually
## change? Photographs ONE framing -- Stoneshore Docks by default -- in every style the debug
## terminal can put the map into, so the four can be compared side by side rather than
## described. Needs a window (NOT --headless):
##   <godot> --path . res://tools/style_toggle_shot.tscn --quit-after 120000 -- \
##       --tile=tile_5_10 --zoom=0.9 --out=artifacts/style
##
## The shipped default is ink ON, plate off, midcentury off (see scripts/map_style.gd), so
## "default" and "ink" are the same picture; both are captured anyway, because a difference
## between them would mean something had latched a mode at boot.

const ShotHarness := preload("res://tools/shot_harness.gd")

var _wm: Node
var _terrain: TileMapLayer
var _cam: Camera2D
var _out := "artifacts/style"


func _ready() -> void:
	ShotHarness.prepare_window(get_window())
	ShotHarness.arm_watchdog(self, 300.0)
	var opt := _options()
	var tile_id := str(opt.get("tile", "tile_5_10"))
	var zoom := float(opt.get("zoom", 0.9))
	_out = str(opt.get("out", "artifacts/style"))

	get_viewport().set_disable_input(true)
	_wm = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_wm)
	for _i in 180:
		await get_tree().process_frame
	_terrain = _wm.get_node("%TerrainLayer")
	var grid := _wm.find_child("HexGridOverlay", true, false) as CanvasItem
	if grid != null:
		grid.visible = false
	var ui := _wm.get_node_or_null("UILayer") as CanvasLayer
	if ui != null:
		ui.visible = false
	_cam = get_viewport().get_camera_2d()
	_cam.set_process(false)
	_cam.set_physics_process(false)
	if "edge_pan_enabled" in _cam:
		_cam.set("edge_pan_enabled", false)
	var coord: Vector2i = _terrain.id_to_coord(tile_id)
	_cam.position = _terrain.map_to_local(_terrain.map_coord_for_tile_coord(coord))
	_cam.zoom = Vector2(zoom, zoom)
	if "_target_zoom" in _cam:
		_cam.set("_target_zoom", _cam.zoom)

	print("[STYLE] shipped default: ink=%s plate=%s midcentury=%s"
		% [MapStyle.ink, MapStyle.plate, MapStyle.is_midcentury()])
	await _shot("default")
	MapStyle.set_midcentury(false)
	MapStyle.set_plate(false)
	MapStyle.set_ink(false)
	await _shot("classic")            # what `toggle ink` leaves you in, from the default
	MapStyle.set_ink(true)
	await _shot("ink")
	MapStyle.set_plate(true)
	await _shot("plate")
	MapStyle.set_plate(false)
	MapStyle.set_midcentury(true)
	await _shot("midcentury")
	MapStyle.set_midcentury(false)
	print("[STYLE] done")
	get_tree().quit(0)


func _shot(mode: String) -> void:
	for _i in 40:
		await get_tree().process_frame
	# The relief LOD re-bakes asynchronously on every style change; capturing a fixed number
	# of frames later photographs its vector fallback for one mode and the finished texture
	# for the next, which reads as a style difference that is not one.
	var hills := _wm.find_child("HillVisuals", true, false)
	if hills != null and hills.has_method("is_capture_ready_for_current_view"):
		var started := Time.get_ticks_msec()
		while not bool(hills.is_capture_ready_for_current_view()) \
				and Time.get_ticks_msec() - started < 45000:
			RenderingServer.force_draw()
			await get_tree().process_frame
	RenderingServer.force_draw()
	var path := "%s_%s.png" % [_out, mode]
	get_viewport().get_texture().get_image().save_png(path)
	print("[STYLE] %s  (ink=%s plate=%s midcentury=%s)"
		% [path, MapStyle.ink, MapStyle.plate, MapStyle.is_midcentury()])


func _options() -> Dictionary:
	var out: Dictionary = {}
	for arg in OS.get_cmdline_user_args():
		var text := str(arg)
		if text.begins_with("--") and text.contains("="):
			out[text.substr(2).get_slice("=", 0)] = text.get_slice("=", 1)
	return out
