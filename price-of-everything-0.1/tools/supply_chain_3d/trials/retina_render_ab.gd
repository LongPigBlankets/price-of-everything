extends "res://tools/supply_chain_3d/capture.gd"
## Simulated 2x (Retina) screen: the current native 4x MSAA render against the
## 2560x1440 budget (FSR upscale, 2x MSAA), same frames, one process.
## AGENT_GODOT_WINDOW=1 godot --path . res://tools/supply_chain_3d/trials/retina_render_ab.tscn -- \
##   --continent-review --no-telemetry --trial-output=<dir> --bake-cache-directory=<new dir>
const Board := preload("res://scripts/supply_chain_3d/board.gd")
var output := ""
var report := {}

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--trial-output="): output = arg.trim_prefix("--trial-output=")
	DirAccess.make_dir_recursive_absolute(output)
	Board.density_override = 2.0
	await super._ready()

func _rd_mib() -> float:
	return RenderingServer.get_rendering_device().get_memory_usage(RenderingDevice.MEMORY_TOTAL) / 1048576.0

func _measure(board: Control, name: String, config: String, budget: int) -> void:
	Board.render_budget_pixels = budget
	board._resize_viewport()
	for i in 20: RenderingServer.force_draw(false); await get_tree().process_frame
	var times: Array = []
	var last := Time.get_ticks_usec()
	for i in 60:
		RenderingServer.force_draw(false); await get_tree().process_frame
		var now := Time.get_ticks_usec(); times.append((now - last) / 1000.0); last = now
	times.sort()
	var viewport: SubViewport = board._viewport
	var row := {"gpu_MiB": snappedf(_rd_mib(), 1), "frame_ms_median": snappedf(times[30], 0.01),
		"viewport": [viewport.size.x, viewport.size.y], "scale": snappedf(viewport.scaling_3d_scale, 0.001),
		"msaa": viewport.msaa_3d, "mode": viewport.scaling_3d_mode}
	report.get_or_add(name, {})[config] = row
	print("[RETINA AB] ", name, " ", config, " ", JSON.stringify(row))
	viewport.get_texture().get_image().save_png(output.path_join("%s_%s.png" % [name, config]))

func _continent_review(board: Control, _home: Dictionary) -> void:
	await board.set_all_tiles(true, false)
	var opened := Time.get_ticks_msec()
	while (board.background_active() or not board.detail_ready()) and Time.get_ticks_msec() - opened < 60000:
		RenderingServer.force_draw(false); await get_tree().process_frame
	board.animate_goods = false
	var builder: RefCounted = board._builder
	for shot in [{"name": "closest", "tile": "tile_10_10", "span": board.Rig.MIN_SIZE, "pitch": board.Rig.HOME_PITCH},
			{"name": "medium_town", "tile": "tile_10_10", "span": board.size.y * 0.8, "pitch": 0.6},
			{"name": "far", "tile": "tile_10_10", "span": 2600.0, "pitch": 0.75}]:
		var camera: Dictionary = board.capture_camera()
		camera.target = builder.point(builder.tiles[shot.tile].center)
		camera.span = shot.span; camera.pitch = shot.pitch; camera.yaw = board.Rig.HOME_YAW
		board.restore_camera(camera)
		await board._stream_visible()
		var settle := Time.get_ticks_msec()
		while (not board.detail_ready() or Time.get_ticks_msec() - settle < 3000) and Time.get_ticks_msec() - settle < 30000:
			RenderingServer.force_draw(false); await get_tree().process_frame
		await _measure(board, shot.name, "native_4x", 1 << 30)
		await _measure(board, shot.name, "budget_fsr_2x", Board.RENDER_BUDGET_PIXELS)
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
