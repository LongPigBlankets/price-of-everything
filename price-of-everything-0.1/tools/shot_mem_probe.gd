extends Node2D
## Diagnostic: where does a screenshot tool's memory actually go? Prints a memory line while
## the world builds, while it idles, and around each framebuffer capture, so the growth can
## be attributed instead of guessed at.
##
##   <godot> --windowed --resolution 640x480 --path . res://tools/shot_mem_probe.tscn \
##       --quit-after 2500 -- --captures=8
##
## ALWAYS run this (and every shot tool) WINDOWED and SMALL: project.godot sets
## window/size/mode=3, so a default run takes the whole screen while it works.

const ShotHarness := preload("res://tools/shot_harness.gd")

var _wm: Node


func _ready() -> void:
	# SAFETY FIRST, before main.tscn exists: the project boots FULLSCREEN, and a tool
	# that grabs the whole screen for a 30 s world build reads as a frozen machine.
	ShotHarness.prepare_window(get_window())
	ShotHarness.arm_watchdog(self)
	var captures := 8
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--captures="):
			captures = int(str(a).split("=")[1])
	_say("boot")
	# The real shot tools arm a start first. This is one of only two things they do that the
	# flat-memory probe above did not.
	SaveLoad.prepare_new_game("res://data/starts/metal_magnate.json", {})
	_say("start armed")
	_wm = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_wm)
	for i in 180:
		await get_tree().process_frame
		if i % 60 == 0:
			_say("building world f%d" % i)
	_say("world built")

	# IDLE: no captures at all. If memory climbs here, the leak is the running game (or the
	# per-frame animated layers), not the readback.
	for i in 300:
		await get_tree().process_frame
		if i % 100 == 0:
			_say("idle f%d" % i)
	_say("idle done")

	# CAMERA MOVES: the other thing the real tools do. Zooming out widens the visible rect,
	# which is what makes AuthoredBake stream tile textures in.
	var terrain: TileMapLayer = _wm.get_node("%TerrainLayer")
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		cam.set_process(false)
		for step in [["tile_5_10", 2.2], ["tile_5_10", 0.45], ["tile_23_8", 1.15],
				["tile_9_8", 0.30], ["tile_18_18", 2.0]]:
			var c: Vector2i = terrain.id_to_coord(str(step[0]))
			if c == Vector2i(-1, -1):
				continue
			cam.position = terrain.map_to_local(terrain.map_coord_for_tile_coord(c))
			cam.zoom = Vector2(float(step[1]), float(step[1]))
			if "_target_zoom" in cam:
				cam.set("_target_zoom", cam.zoom)
			for _i in 25:
				await get_tree().process_frame
			RenderingServer.force_draw()
			var shot := get_viewport().get_texture().get_image()
			shot = null
			_say("cam %s z%.2f" % [str(step[0]), float(step[1])])
	_say("camera sweep done")

	# CAPTURES: the thing every shot tool does in a loop.
	for i in captures:
		RenderingServer.force_draw()
		var img := get_viewport().get_texture().get_image()
		# save_png too — the last thing the real tools do that this probe did not.
		img.save_png("artifacts/_memprobe.png")
		_say("capture %d (img %dx%d)" % [i, img.get_width(), img.get_height()])
		img = null
		await get_tree().process_frame
	_say("captures done")
	get_tree().quit(0)


func _say(tag: String) -> void:
	var stat := OS.get_static_memory_usage()
	print("[MEM] %-24s static=%7.1f MB  objects=%6d  orphans=%4d  nodes=%5d" % [
		tag, float(stat) / 1048576.0,
		int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
	])
