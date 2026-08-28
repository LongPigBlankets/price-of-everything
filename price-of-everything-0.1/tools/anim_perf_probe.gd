extends Node2D
## What do the chimneys, the smoke and the cranes actually COST?
##
## Measures frame time and draw calls with each of the three switched on and off, at a camera
## position where plenty of them are visible. Needs a window (NOT --headless) — the whole
## point is the renderer:
##   <godot> --path . res://tools/anim_perf_probe.tscn --quit-after 9000 -- --tile=tile_9_16
##
## VSYNC IS DISABLED. With it on every configuration reads 16.6 ms and the measurement says
## nothing at all.

const ShotHarness := preload("res://tools/shot_harness.gd")

const WARMUP := 30
const SAMPLE := 150

var _wm: Node
var _terrain: TileMapLayer
var _cam: Camera2D
var _smoke: CanvasItem
var _cranes: CanvasItem
var _visuals: Node
var _ships: CanvasItem


func _ready() -> void:
	ShotHarness.prepare_window(get_window())
	ShotHarness.arm_watchdog(self, 300.0)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	var opt := _options()
	var tile_id := str(opt.get("tile", "tile_9_16"))
	var zoom := float(opt.get("zoom", 1.0))

	SaveLoad.prepare_new_game("res://data/starts/metal_magnate.json", {})
	get_viewport().set_disable_input(true)
	_wm = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_wm)
	for _i in 170:
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
	_smoke = _wm.find_child("SmokeVisuals", true, false) as CanvasItem
	_cranes = _wm.find_child("ConstructionVisuals", true, false) as CanvasItem
	_visuals = _wm.find_child("BuildingVisuals", true, false)
	_ships = _wm.find_child("PortShipVisuals", true, false) as CanvasItem

	# Cranes need sites, so queue real builds on the tile we are about to look at.
	var coord: Vector2i = _terrain.id_to_coord(tile_id)
	for build_id in ["b_002", "b_007", "b_003"]:
		for good_id in Construction.requirements_for(build_id):
			Stockpile.add(tile_id, str(good_id),
				int(Construction.requirements_for(build_id)[good_id]) + 50)
	var sites := 0
	for build_id in ["b_002", "b_007", "b_003"]:
		var iid := Construction.start_on_tile(build_id, "", tile_id, 0.0)
		if iid != "":
			sites += 1
			if _wm.has_signal("building_placed"):
				_wm.emit_signal("building_placed", tile_id, build_id, "", iid, coord)

	_cam.position = _terrain.map_to_local(_terrain.map_coord_for_tile_coord(coord))
	_cam.zoom = Vector2(zoom, zoom)
	if "_target_zoom" in _cam:
		_cam.set("_target_zoom", _cam.zoom)
	for _i in 20:
		await get_tree().process_frame

	var stacks: int = (_visuals.call("smoke_stacks") as Array).size()
	print("[PERF] tile=%s zoom=%.2f  chimneys(map)=%d  sites=%d  vsync=OFF"
		% [tile_id, zoom, stacks, sites])
	print("[PERF] %-34s %9s %9s %11s" % ["configuration", "ms/frame", "max ms", "draw calls"])

	# Baseline last as a repeat, to show drift between the first and last measurement — a
	# number that moved between two identical runs is a number not to trust.
	await _measure("none (baseline)", false, false, false, false)
	await _measure("chimneys only", true, false, false, false)
	await _measure("chimneys + smoke", true, true, false, false)
	await _measure("chimneys + smoke + cranes", true, true, true, false)
	await _measure("+ ships", true, true, true, true)
	await _measure("ships only", false, false, false, true)
	await _measure("none (repeat, drift check)", false, false, false, false)
	print("[PERF] done")
	get_tree().quit(0)


func _measure(label: String, chimneys: bool, smoke: bool, cranes: bool,
		ships: bool) -> void:
	var visuals_script := preload("res://scenes/building_visuals.gd")
	visuals_script.DRAW_CHIMNEYS = chimneys
	if _smoke != null:
		_smoke.visible = smoke
		(_smoke as Node).set_process(smoke)
	if _cranes != null:
		_cranes.visible = cranes
		(_cranes as Node).set_process(cranes)
	if _ships != null:
		_ships.visible = ships
		(_ships as Node).set_process(ships)
	# The building canvas only repaints on settle, so a chimney toggle needs saying out loud.
	if _visuals != null:
		(_visuals as CanvasItem).queue_redraw()
	for _i in WARMUP:
		await get_tree().process_frame
	var total := 0.0
	var worst := 0.0
	var calls := 0.0
	for _i in SAMPLE:
		var t0 := Time.get_ticks_usec()
		await get_tree().process_frame
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0
		total += ms
		worst = maxf(worst, ms)
		calls += float(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	print("[PERF] %-34s %9.3f %9.3f %11.0f"
		% [label, total / float(SAMPLE), worst, calls / float(SAMPLE)])


func _options() -> Dictionary:
	var out := {}
	for arg in OS.get_cmdline_user_args():
		var a := str(arg)
		if a.begins_with("--") and a.contains("="):
			var bits := a.substr(2).split("=", true, 1)
			out[str(bits[0])] = str(bits[1])
	return out
