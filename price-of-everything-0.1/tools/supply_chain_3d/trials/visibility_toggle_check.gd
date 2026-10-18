extends "res://tools/supply_chain_3d/capture.gd"
## A visibility tickbox in the supply chain view, flipped the way the player flips it: how long
## the view takes to settle, its slowest frame, and a capture before and after.
## AGENT_GODOT_WINDOW=1 godot --path . res://tools/supply_chain_3d/trials/visibility_toggle_check.tscn -- \
##   --continent-review --no-telemetry --quality=low|high [--all-tiles] [--toggle=names] --trial-output=<dir> --bake-cache-directory=<new dir>
const Legacy := preload("res://scripts/empire_board.gd")
var output := ""
var toggle := "names"
var all_tiles := false
var report := {}

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--trial-output="): output = arg.trim_prefix("--trial-output=")
		if arg.begins_with("--toggle="): toggle = arg.trim_prefix("--toggle=")
		if arg == "--all-tiles": all_tiles = true
		# This run only; the saved profile is not touched.
		if arg.begins_with("--quality="): PlayerProfile.graphics_quality = arg.trim_prefix("--quality=")
	DirAccess.make_dir_recursive_absolute(output)
	report.quality = PlayerProfile.graphics_quality
	report.toggle = toggle
	await super._ready()

func _mib() -> float:
	return snappedf(RenderingServer.get_rendering_device().get_memory_usage(RenderingDevice.MEMORY_TOTAL) / 1048576.0, 1)

func _settle(board: Control, limit_ms: int) -> Dictionary:
	var started := Time.get_ticks_msec()
	var last := Time.get_ticks_usec()
	var worst := 0.0
	var frames := 0
	while (board._building or board._streaming or not bool(board.call("detail_ready")) or board.background_active()) and Time.get_ticks_msec() - started < limit_ms:
		await get_tree().process_frame
		var now := Time.get_ticks_usec(); worst = maxf(worst, (now - last) / 1000.0); last = now; frames += 1
	for i in 30: await get_tree().process_frame
	return {"ms": Time.get_ticks_msec() - started, "worst_frame_ms": snappedf(worst, 0.1), "frames": frames}

func _state(board: Control) -> Dictionary:
	var builder: RefCounted = board._builder
	return {"show_all_tiles": board.show_all_tiles, "flat": board.call("built_flat"), "streamed": builder.streamed,
		"terrain_tiles": builder.terrain_lods.size(), "local_tiles": builder.local_tiles.size(), "overview": builder._overview,
		"base_ready": builder.base_ready, "backdrop_pending": builder.backdrop_pending, "gpu_MiB": _mib()}

func _continent_review(board: Control, _home: Dictionary) -> void:
	report.opened = await _settle(board, 60000)
	if all_tiles:
		await board.set_all_tiles(true, false)
		report.all_tiles = await _settle(board, 180000)
	report.before = _state(board)
	board._viewport.get_texture().get_image().save_png(output.path_join("%s_before.png" % report.quality))
	var visibility: Node = null
	for node in board.get_children():
		if node.has_signal("changed") and node.get_script() != null and str(node.get_script().resource_path).ends_with("empire_board_visibility.gd"): visibility = node
	# What the tickbox does: flip the shared switch, then say so.
	Legacy.show[toggle] = not bool(Legacy.show[toggle])
	var profile_before: Dictionary = board.load_profile
	var started := Time.get_ticks_msec()
	visibility.changed.emit(toggle, Legacy.show[toggle])
	report.call_ms = Time.get_ticks_msec() - started
	report.toggled = await _settle(board, 600000)
	report.after = _state(board)
	report.rebuilt = board.load_profile != profile_before
	report.locked = bool(visibility.get("_boxes").get(toggle).disabled) if visibility.get("_boxes").has(toggle) else false
	board._viewport.get_texture().get_image().save_png(output.path_join("%s_after.png" % report.quality))
	print("[VISIBILITY TOGGLE] ", JSON.stringify(report))
	FileAccess.open(output.path_join("toggle_%s.json" % report.quality), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
