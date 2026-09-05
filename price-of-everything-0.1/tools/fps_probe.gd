extends Node
## Dev probe: where do the map's frames go? Boots a demo start (no cheats) WITHOUT the loading
## screen, so it first waits out the fabric repairs that the reveal would normally hide and
## reports how long they took; then it mirrors reveal_for_play (threaded texture streaming on,
## ring prefetched), disables vsync so frame time is the real cost, and measures frame ms at
## three zooms idle, two zooms panning, and — the one that names a hitch — each WorldMap layer
## hidden in turn WHILE PANNING at region zoom.
##   <godot> --path . res://tools/fps_probe.tscn --quit-after 120000

const AuthoredBakeScript := preload("res://scripts/authored_bake.gd")
const SAMPLE_FRAMES := 90
const PAN_FRAMES := 240
const BISECT_PAN_FRAMES := 96
const ZOOMS := {"far 0.35": 0.35, "region 0.62": 0.62, "tile 1.35": 1.35}
const STREAM_MARGIN := 600.0   # the streaming layers' own margin

func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	SaveLoad.prepare_new_game("res://data/starts/metal_magnate.json", {"ruleset": {
		"start_id": "metal_magnate", "difficulty": "normal", "speed_turns": 100,
		"policy_timeline": "demo_itch", "victory_set": "demo_itch",
		"tutorial_enabled": false, "survey_all_tiles": true, "company_colour": "diesel_red",
	}})
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(120)
	# The fabric repairs the loading screen would hide: how many masses, how many frames.
	var fabric: Node = get_tree().get_first_node_in_group("authored_fabric")
	var repair_frames := 0
	var t0 := Time.get_ticks_msec()
	if fabric != null and fabric.has_method("has_pending_repairs"):
		while bool(fabric.call("has_pending_repairs")) and repair_frames < 4000:
			repair_frames += 1
			await get_tree().process_frame
		var sacrificed: Variant = fabric.get("_sacrificed")
		print("[FPS] load repairs: %d frames, %d ms, evicted masses=%d" % [
			repair_frames, Time.get_ticks_msec() - t0,
			(sacrificed as Dictionary).size() if typeof(sacrificed) == TYPE_DICTIONARY else -1])
	var cam: Camera2D = get_viewport().get_camera_2d()
	if cam == null:
		push_error("[FPS] no camera"); get_tree().quit(1); return
	if "edge_pan_enabled" in cam:
		cam.set("edge_pan_enabled", false)
	# Mirror world_map.reveal_for_play: from here the baked map streams off worker threads.
	AuthoredBakeScript.stream_async = true
	if fabric is CanvasItem:
		AuthoredBakeScript.prefetch(AuthoredBakeScript.visible_world_rect(fabric as CanvasItem,
			STREAM_MARGIN + AuthoredBakeScript.PREFETCH_RING))
	await _settle(60)
	var home := cam.position
	print("[FPS] window=%s renderer=%s stream_async=%s" % [str(DisplayServer.window_get_size()),
		RenderingServer.get_video_adapter_name(), str(AuthoredBakeScript.stream_async)])
	for label in ZOOMS:
		cam.zoom = Vector2(ZOOMS[label], ZOOMS[label])
		cam.position = home
		await _settle(45)
		_report("idle  " + label, await _measure(SAMPLE_FRAMES, Vector2.ZERO, cam))
	for label in ["region 0.62", "tile 1.35"]:
		cam.zoom = Vector2(ZOOMS[label], ZOOMS[label])
		cam.position = home
		await _settle(45)
		var pan := await _measure(PAN_FRAMES, Vector2(8.0, 4.0) / ZOOMS[label], cam)
		_report("pan   " + label, pan)
		print("[FPS]        slowest frames: %s" % str(pan.slow))
	# PAN bisection at region zoom: hide one layer, pan, note the worst frame.
	var z: float = ZOOMS["region 0.62"]
	cam.zoom = Vector2(z, z)
	cam.position = home
	await _settle(45)
	var base := await _measure(BISECT_PAN_FRAMES, Vector2(8.0, 4.0) / z, cam)
	print("[FPS] --- pan bisection at region 0.62 (baseline max=%.0f ms, mean=%.2f ms) ---" % [base.max, base.mean])
	var world: Node = game if game.name == "WorldMap" else game.find_child("WorldMap", true, false)
	if world == null:
		world = game
	var rows: Array = []
	for child in world.get_children():
		if not (child is CanvasItem) or child is Camera2D:
			continue
		var ci := child as CanvasItem
		if not ci.visible:
			continue
		ci.visible = false
		cam.position = home
		await _settle(20)
		var m := await _measure(BISECT_PAN_FRAMES, Vector2(8.0, 4.0) / z, cam)
		ci.visible = true
		rows.append({"name": child.name, "max": m.max, "mean": m.mean})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.max) < float(b.max))
	for r in rows:
		print("[FPS] pan without %-24s -> max=%6.0f ms  mean=%6.2f ms" % [str(r.name), float(r.max), float(r.mean)])
	get_tree().quit(0)

func _report(label: String, m: Dictionary) -> void:
	print("[FPS] %-18s mean=%6.2f ms  p95=%6.2f ms  max=%7.2f ms  fps~%5.0f" % [
		label, m.mean, m.p95, m.max, 1000.0 / maxf(m.mean, 0.01)])

func _measure(frames: int, pan_per_frame: Vector2, cam: Camera2D) -> Dictionary:
	var samples: Array[float] = []
	var slow: Array = []
	var last := Time.get_ticks_usec()
	for i in frames:
		if pan_per_frame != Vector2.ZERO:
			cam.position += pan_per_frame
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var ms := float(now - last) / 1000.0
		last = now
		samples.append(ms)
		if ms > 40.0:
			slow.append("f%d=%.0fms" % [i, ms])
	var sorted := samples.duplicate()
	sorted.sort()
	var total := 0.0
	for s in samples:
		total += s
	return {"mean": total / float(frames), "max": sorted[sorted.size() - 1],
		"p95": sorted[int(floor(float(sorted.size() - 1) * 0.95))], "slow": slow.slice(0, 8)}

func _settle(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
