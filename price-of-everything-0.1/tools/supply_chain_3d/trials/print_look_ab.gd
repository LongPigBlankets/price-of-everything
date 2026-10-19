extends "res://tools/supply_chain_3d/capture.gd"
## The supply chain view's look, side by side on one company town: as painted, the ink and paper
## print, and the print with decorative scenery calmed. Daylight and evening, at three zooms, and
## the time to draw a medium frame for each look.
## AGENT_GODOT_WINDOW=1 godot --path . res://tools/supply_chain_3d/trials/print_look_ab.tscn -- \
##   --continent-review --no-telemetry --trial-output=<dir>
const Board := preload("res://scripts/supply_chain_3d/board.gd")
const LOOKS := {"painted": [false, false], "print": [true, false], "calm": [true, true]}
var output := ""
var report := {}
var _town := ""

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--trial-output="): output = arg.trim_prefix("--trial-output=")
	DirAccess.make_dir_recursive_absolute(output)
	# The first build is the look as painted, so the calming starts off.
	Board.print_look = false
	Board.calm_scenery = false
	await super._ready()

func _settle(board: Control, seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until or bool(board.get("_building")) or not bool(board.call("detail_ready")):
		RenderingServer.force_draw(false); await get_tree().process_frame
		if Time.get_ticks_msec() > until + 90000: break

## The company tile with the most homes and works on it.
func _busiest_tile(board: Control) -> String:
	var score := {}
	for pair in board._builder.sprite_pairs:
		if not pair.get("standing") is Dictionary: continue
		var kind := str(pair.standing.kind)
		var tid := str(pair.get("tile", ""))
		score[tid] = int(score.get(tid, 0)) + (1 if kind == "house" else 4 if kind == "building" else 0)
	var best := ""
	for tid in score:
		if best == "" or int(score[tid]) > int(score[best]): best = tid
	return best

func _frame(board: Control, zoom: String) -> void:
	var camera: Dictionary = board.capture_camera()
	camera.target = board._builder.point(board._builder.tiles[_town].center)
	camera.yaw = board.Rig.HOME_YAW
	camera.pitch = board.Rig.HOME_PITCH
	camera.span = {"close": board.Rig.MIN_SIZE * 1.6, "medium": 900.0, "far": 2400.0}[zoom]
	board.restore_camera(camera)

## Frames drawn back to back, each waited out on the GPU: the whole frame, CPU and GPU.
func _frame_ms() -> float:
	for i in 10: RenderingServer.force_draw(false); RenderingServer.force_sync()
	var started := Time.get_ticks_usec()
	for i in 60: RenderingServer.force_draw(false); RenderingServer.force_sync()
	return snappedf((Time.get_ticks_usec() - started) / 60000.0, 0.01)

func _shots(board: Control, light: String, look: String, zooms: Array) -> void:
	for zoom in zooms:
		# Framed twice: a build can refit the camera after the first settle.
		_frame(board, zoom)
		await _settle(board, 1.5)
		_frame(board, zoom)
		await _settle(board, 1.0)
		board._viewport.get_texture().get_image().save_png(output.path_join("%s_%s_%s.png" % [light, zoom, look]))
		if zoom == "medium" and light == "day": report["frame_ms_" + look] = _frame_ms()
	print("[PRINT AB] ", light, " ", look, " done")

func _look(board: Control, look: String) -> void:
	var setting: Array = LOOKS[look]
	await board.set_look(setting[0], setting[1])
	await _settle(board, 3.0)

func _continent_review(board: Control, _home: Dictionary) -> void:
	await _settle(board, 3.0)
	_town = _busiest_tile(board)
	report.town = _town
	report.viewport = board._viewport.size
	for look in ["painted", "print", "calm"]:
		await _look(board, look)
		await _shots(board, "day", look, ["close", "medium", "far"])
	await board.set_evening(true)
	await _settle(board, 3.0)
	for look in ["calm", "print", "painted"]:
		await _look(board, look)
		await _shots(board, "evening", look, ["close", "medium"])
	print("[PRINT AB] ", JSON.stringify(report))
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
