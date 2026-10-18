extends "res://tools/supply_chain_3d/capture.gd"
## Graphics quality budgets on a simulated 2x (Retina) screen: internal 3D resolution and
## MSAA, compared by video memory, frame time and captures of the same frames.
## AGENT_GODOT_WINDOW=1 godot --path . res://tools/supply_chain_3d/trials/quality_budget_ab.tscn -- \
##   --continent-review --no-telemetry --trial-output=<dir> --bake-cache-directory=<new dir>
const Board := preload("res://scripts/supply_chain_3d/board.gd")
## [name, budget pixels (0 = native), MSAA]
const CONFIGS := [
	["native_4x", 0, Viewport.MSAA_4X],
	["2560_msaa4", 2560 * 1440, Viewport.MSAA_4X],
	["2560_msaa2", 2560 * 1440, Viewport.MSAA_2X],
	["2560_off", 2560 * 1440, Viewport.MSAA_DISABLED],
	["1920_msaa2", 1920 * 1080, Viewport.MSAA_2X],
	["1920_off", 1920 * 1080, Viewport.MSAA_DISABLED],
]
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

func _measure(board: Control, view: String, config: Array) -> void:
	Board.render_budget_pixels = int(config[1]) if int(config[1]) > 0 else 1 << 30
	board._resize_viewport()
	var viewport: SubViewport = board._viewport
	viewport.msaa_3d = config[2]
	for i in 20: RenderingServer.force_draw(false); await get_tree().process_frame
	var times: Array = []
	var last := Time.get_ticks_usec()
	for i in 60:
		RenderingServer.force_draw(false); await get_tree().process_frame
		var now := Time.get_ticks_usec(); times.append((now - last) / 1000.0); last = now
	times.sort()
	var row := {"gpu_MiB": snappedf(_rd_mib(), 1), "frame_ms_median": snappedf(times[30], 0.01), "frame_ms_p90": snappedf(times[54], 0.01),
		"internal": [int(viewport.size.x * viewport.scaling_3d_scale), int(viewport.size.y * viewport.scaling_3d_scale)], "msaa": config[2]}
	report.get_or_add(view, {})[config[0]] = row
	print("[QUALITY AB] ", view, " ", config[0], " ", JSON.stringify(row))
	viewport.get_texture().get_image().save_png(output.path_join("%s_%s.png" % [view, config[0]]))

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
		for config in CONFIGS: await _measure(board, shot.name, config)
	Board.render_budget_pixels = Board.RENDER_BUDGET_PIXELS
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
