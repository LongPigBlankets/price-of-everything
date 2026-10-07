extends Node
## Times the supply chain view across a load. See supply_board_load_probe.gd.

const ShotHarness := preload("res://tools/shot_harness.gd")
const PREPARE_LIMIT := 30.0      # seconds to wait for the view to be built in the background

var screen: Node = null

var _t0 := 0
var _last := 0


func _ready() -> void:
	_t0 = Time.get_ticks_msec()
	_last = _t0
	get_tree().create_timer(240.0).timeout.connect(func() -> void:
		print("[load_probe] watchdog: giving up")
		get_tree().quit(124))
	_run()


func _now() -> float:
	return float(Time.get_ticks_msec() - _t0) / 1000.0


func _world() -> Node:
	var scene := get_tree().current_scene
	return scene if scene != null and scene.get("build_complete") != null else null


func _run() -> void:
	while _world() == null or not bool(_world().get("build_complete")):
		await get_tree().process_frame
	var built := _now()
	print("[load_probe] world built at %.2f s" % built)
	var view: Node = _world().find_child("EmpireView", true, false)
	# The worst gap between frames while the view is built and baked in the background.
	var worst := 0
	var frames := 0
	var prepared := -1.0
	_last = Time.get_ticks_msec()
	while _now() - built < PREPARE_LIMIT:
		# A covered window draws no frames of its own, and a bake waits on a drawn frame.
		RenderingServer.force_draw(false)
		await get_tree().process_frame
		var now := Time.get_ticks_msec()
		worst = maxi(worst, now - _last)
		_last = now
		frames += 1
		if view.has_method("is_prepared") and bool(view.call("is_prepared")):
			prepared = _now()
			break
		if not view.has_method("is_prepared") and frames > 30:
			break
	if prepared >= 0.0:
		print("[load_probe] view prepared at %.2f s, %.2f s after the world, %d frames, worst frame %d ms"
			% [prepared, prepared - built, frames, worst])
	else:
		print("[load_probe] view not prepared in the background (%d frames, worst frame %d ms)" % [frames, worst])
	# Begin, as soon as it is offered.
	while is_instance_valid(screen) and not bool((screen.get("_begin") as Control).visible):
		RenderingServer.force_draw(false)
		await get_tree().process_frame
	print("[load_probe] Begin offered at %.2f s" % _now())
	if is_instance_valid(screen):
		screen.call("_on_begin_pressed")
	while is_instance_valid(screen):
		await get_tree().process_frame
	for _i in range(30):
		await get_tree().process_frame
	# The first Tab.
	var board: Control = view.find_child("Board", true, false)
	var bakes_before := (board.get("_bakes") as Dictionary).size()
	var t := Time.get_ticks_usec()
	view.call("toggle")
	var opened := float(Time.get_ticks_usec() - t) / 1000.0
	var first_frame_from := Time.get_ticks_usec()
	await get_tree().process_frame
	var first_frame := float(Time.get_ticks_usec() - first_frame_from) / 1000.0
	print("[load_probe] first open: %.1f ms to open, %.1f ms to its first frame, %d bakes ready, %s"
		% [opened, first_frame, bakes_before, "ready" if str(board.call("_next_bake")) == "" else "still baking"])
	var out := OS.get_environment("SB_SHOT_DIR")
	if out != "":
		await get_tree().create_timer(1.0).timeout
		RenderingServer.force_draw(false)
		get_viewport().get_texture().get_image().save_png(out.path_join("load_probe_first_open.png"))
	# Closed again, a change in the sim: the view rebuilds in the background while the map plays.
	view.call("toggle")
	for _i in range(30):
		await get_tree().process_frame
	if view.has_method("sim_changed") and view.has_method("is_prepared"):
		var sigs: Dictionary = (board.get("_tile_sig") as Dictionary).duplicate()
		view.call("sim_changed")
		var from := Time.get_ticks_msec()
		var gap_worst := 0
		_last = from
		while Time.get_ticks_msec() - from < 20000:
			RenderingServer.force_draw(false)
			await get_tree().process_frame
			var now := Time.get_ticks_msec()
			gap_worst = maxi(gap_worst, now - _last)
			_last = now
			if bool(view.call("is_prepared")):
				break
		var again := 0
		for unit in board.get("_tile_sig"):
			again += 1 if int(sigs.get(unit, 0)) != int((board.get("_tile_sig") as Dictionary)[unit]) else 0
		print("[load_probe] background rebuild while playing: %.2f s, worst frame %d ms, %d layers to bake again"
			% [float(Time.get_ticks_msec() - from) / 1000.0, gap_worst, again])
	get_tree().quit()
