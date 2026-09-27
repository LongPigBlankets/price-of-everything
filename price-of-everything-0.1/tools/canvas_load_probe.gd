extends Node
## Dev probe: how many 2D canvas objects does the map submit per frame, anywhere the camera can go?
##
## The GL Compatibility renderer batches canvas items through an instance buffer of
## rendering/gl_compatibility/item_buffer_size entries (16384 by default). A frame that submits
## more grows the buffer mid-pass, and that growth path in Godot 4.6 can index a buffer that
## does not exist yet when the GPU is behind: a hard crash that playing by hand only hits
## sometimes. This probe makes it measurable instead. It boots a demo start without the loading
## screen, then sweeps the camera over the whole map at three zooms (full map, region, tile).
## At every stop it forces a real draw and reads the frame's canvas objects and draw calls, then
## hides each WorldMap layer named in LAYERS and reads them again, so each layer's share is known.
##
##   <godot> --path . res://tools/canvas_load_probe.tscn -- --style=midcentury --out=/tmp/x.json
##
## --style: midcentury (default), ink, plate or classic. --out: JSON report path (optional).
## Exits 1 when any stop reaches the buffer size, so it can gate a change.

const BUFFER_SIZE := 16384
const LAYERS := ["RiverVisuals"]
const ZOOM_FRACTIONS := {"full": 0.0, "region": 0.25, "tile": 1.0}
const MAX_STOPS_PER_ZOOM := 160

func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var opt := _options()
	SaveLoad.prepare_new_game("res://data/starts/metal_magnate.json", {"ruleset": {
		"start_id": "metal_magnate", "difficulty": "normal", "speed_turns": 100,
		"policy_timeline": "demo_itch", "victory_set": "demo_itch",
		"tutorial_enabled": false, "survey_all_tiles": true, "company_colour": "diesel_red",
	}})
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(120)
	var fabric: Node = get_tree().get_first_node_in_group("authored_fabric")
	if fabric != null and fabric.has_method("has_pending_repairs"):
		var guard := 0
		while bool(fabric.call("has_pending_repairs")) and guard < 4000:
			guard += 1
			await get_tree().process_frame
	_apply_style(str(opt.get("style", "midcentury")))
	var cam: Camera2D = get_viewport().get_camera_2d()
	if cam == null:
		push_error("[CANVAS] no camera"); get_tree().quit(1); return
	if "edge_pan_enabled" in cam:
		cam.set("edge_pan_enabled", false)
	var world: Node = game if game.name == "WorldMap" else game.find_child("WorldMap", true, false)
	if world == null:
		world = game
	var map_min: Vector2 = cam.get("map_min")
	var map_max: Vector2 = cam.get("map_max")
	var z_min: float = cam.call("_effective_zoom_min")
	var z_max: float = cam.get("zoom_max")
	await _settle(30)
	print("[CANVAS] window=%s adapter=%s style=%s map=%s..%s zoom %.3f..%.3f" % [
		str(DisplayServer.window_get_size()), RenderingServer.get_video_adapter_name(),
		str(opt.get("style", "midcentury")), str(map_min), str(map_max), z_min, z_max])

	var report := {"style": str(opt.get("style", "midcentury")), "buffer_size": BUFFER_SIZE,
		"zooms": {}}
	var worst := 0
	for label in ZOOM_FRACTIONS:
		var z := lerpf(z_min, z_max, float(ZOOM_FRACTIONS[label]))
		cam.call("_apply_intro_zoom", z)
		var view := Vector2(get_viewport().get_visible_rect().size) / z
		var stops := _stops(map_min, map_max, view)
		var rows: Array = []
		var peak := {"objects": 0}
		var totals := {"objects": 0, "draw_calls": 0, "ms": 0.0}
		var layer_peak := {}
		for layer in LAYERS:
			layer_peak[layer] = 0
		for stop in stops:
			cam.position = stop
			await _settle(3)
			var m := _sample()
			var row := {"pos": [roundi(stop.x), roundi(stop.y)], "objects": m.objects,
				"draw_calls": m.draw_calls, "ms": m.ms, "layers": {}}
			for layer in LAYERS:
				var node := world.get_node_or_null(NodePath(layer)) as CanvasItem
				if node == null or not node.visible:
					continue
				node.visible = false
				var without := _sample()
				node.visible = true
				var share := int(m.objects) - int(without.objects)
				row.layers[layer] = share
				layer_peak[layer] = maxi(int(layer_peak[layer]), share)
			rows.append(row)
			totals.objects += int(m.objects)
			totals.draw_calls += int(m.draw_calls)
			totals.ms += float(m.ms)
			if int(m.objects) > int(peak.objects):
				peak = row
		var n := maxi(stops.size(), 1)
		worst = maxi(worst, int(peak.objects))
		report.zooms[label] = {"zoom": z, "stops": stops.size(), "peak": peak,
			"mean_objects": float(totals.objects) / n, "mean_draw_calls": float(totals.draw_calls) / n,
			"mean_draw_ms": float(totals.ms) / n, "layer_peak": layer_peak, "rows": rows}
		print("[CANVAS] %-6s zoom=%.3f stops=%3d  objects peak=%6d mean=%8.0f  draw calls mean=%5.0f  draw ms mean=%6.2f  %s" % [
			label, z, stops.size(), int(peak.objects), float(totals.objects) / n,
			float(totals.draw_calls) / n, float(totals.ms) / n,
			"  ".join(PackedStringArray(layer_peak.keys().map(
				func(k: String) -> String: return "%s peak=%d" % [k, int(layer_peak[k])])))])
	report["worst_objects"] = worst
	report["video_mem_mb"] = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	var verdict := "UNDER" if worst < BUFFER_SIZE else "OVER"
	print("[CANVAS] worst frame %d objects: %s the %d item buffer  video mem %.1f MB" % [
		worst, verdict, BUFFER_SIZE, float(report.video_mem_mb)])
	var out := str(opt.get("out", ""))
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(report, "  "))
			f.close()
	get_tree().quit(0 if worst < BUFFER_SIZE else 1)

## A grid of camera centres covering the map, one view apart, capped for the tile zoom.
func _stops(lo: Vector2, hi: Vector2, view: Vector2) -> Array:
	var out: Array = []
	var size := hi - lo
	var nx := maxi(1, ceili(size.x / view.x))
	var ny := maxi(1, ceili(size.y / view.y))
	var stride := 1
	while ceili(float(nx) / stride) * ceili(float(ny) / stride) > MAX_STOPS_PER_ZOOM:
		stride += 1
	for iy in range(0, ny, stride):
		for ix in range(0, nx, stride):
			out.append(lo + Vector2((ix + 0.5) * size.x / nx, (iy + 0.5) * size.y / ny))
	return out

## Draws one frame now and reads what it cost. The window may be hidden (macOS stops drawing
## it), so the stats are only fresh after an explicit draw.
func _sample() -> Dictionary:
	var vp := get_viewport()
	var t0 := Time.get_ticks_usec()
	RenderingServer.force_draw(false)
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	return {"objects": vp.get_render_info(Viewport.RENDER_INFO_TYPE_CANVAS,
			Viewport.RENDER_INFO_OBJECTS_IN_FRAME),
		"draw_calls": vp.get_render_info(Viewport.RENDER_INFO_TYPE_CANVAS,
			Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
		"ms": ms}

func _apply_style(style: String) -> void:
	match style:
		"ink":
			MapStyle.set_midcentury(false)
			MapStyle.set_ink(true)
		"plate":
			MapStyle.set_midcentury(false)
			MapStyle.set_plate(true)
		"classic":
			MapStyle.set_midcentury(false)
			MapStyle.set_ink(false)
		_:
			MapStyle.set_midcentury(true)

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

func _settle(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
