extends Node
## Render all stills, a slide and Begin; CAROUSEL_PLAY=1 instead measures a real New Game.
## AGENT_GODOT_WINDOW=1 godot --path . res://tools/loading_carousel_probe.tscn

const Screen := preload("res://scripts/loading_screen.gd")
var build_complete := false
var _out := "/private/tmp/cnc-loading-preview"
var _capture_size := Vector2i(1280, 720)
var _profile_started := 0
var _profile_last := 0
var _profile_frames: Array[Dictionary] = []
var _draw_started := 0
var _last_draw_ms := 0.0
var _capture_failed := false
var _capture_retries := 0


func _ready() -> void:
	TelemetryState.enabled = false
	RenderingServer.frame_pre_draw.connect(func() -> void: _draw_started = Time.get_ticks_usec())
	RenderingServer.frame_post_draw.connect(func() -> void: _last_draw_ms = (Time.get_ticks_usec()-_draw_started)/1000.0)
	get_window().mode = Window.MODE_WINDOWED
	# Let a saved macOS fullscreen mode finish leaving its Space before sizing/capturing.
	await get_tree().create_timer(0.8, true, false, true).timeout
	get_window().size = Vector2i(1280, 720)
	if OS.get_environment("CAROUSEL_OUTPUT") != "":
		_out = OS.get_environment("CAROUSEL_OUTPUT")
	DirAccess.make_dir_recursive_absolute(_out)
	await get_tree().process_frame
	var screen := Screen.show_global(get_tree())
	if OS.get_environment("CAROUSEL_IDLE_PROFILE") != "":
		await get_tree().create_timer(3.0, true, false, true).timeout
		_profile_started = Time.get_ticks_usec()
		_profile_last = _profile_started
		await get_tree().create_timer(10.0, true, false, true).timeout
		_write_profile()
		if OS.get_environment("CAROUSEL_RECORD") != "":
			await _record(screen)
	elif OS.get_environment("CAROUSEL_PLAY") != "" or OS.get_environment("CAROUSEL_PROFILE") != "":
		await _real_load(screen)
	elif OS.get_environment("CAROUSEL_RECORD") != "":
		await _record(screen)
	else:
		await _stills(screen)
	if is_instance_valid(screen):
		screen.queue_free()
	await get_tree().process_frame
	Audio.silence_for_quit()
	get_tree().quit(1 if _capture_failed else 0)


func _stills(screen: Node) -> void:
	var carousel: Control = screen.get("_carousel")
	carousel.set_process(false)
	for i in 6:
		for night in [false, true]:
			carousel.call("seek", i*5.0 + (3.9 if night else 0.5))
			await _shot("%02d-%s" % [i+1, "night" if night else "day"])
	carousel.call("seek", 4.65)
	await _shot("slide")
	carousel.call("seek", 3.9)
	build_complete = true
	screen.set("_scene_changed", true)
	await get_tree().create_timer(1.1, true, false, true).timeout
	await _shot("begin")
	print("CAROUSEL stills, slide and Begin rendered")
	# A portrait viewport checks that the full hex remains visible.
	_capture_size = Vector2i(720, 1000)
	await _shot("portrait")


func _real_load(screen: Node) -> void:
	if OS.get_environment("CAROUSEL_LOW") != "":
		PlayerProfile.graphics_quality = PlayerProfile.QUALITY_LOW  # this probe only; never saved
	# Use the shipped New Game panel's selected start and rules, rather than a legacy start.
	var panel: Control = preload("res://scripts/new_game_panel.gd").new()
	add_child(panel)
	var selection: Dictionary = {}
	panel.start_requested.connect(func(path: String, overrides: Dictionary) -> void:
		selection.path = path
		selection.overrides = overrides.duplicate(true))
	panel.call("_on_start_pressed")
	panel.queue_free()
	var start: String = OS.get_environment("CAROUSEL_START")
	if start.is_empty():
		start = selection.path
	var overrides: Dictionary = selection.overrides
	overrides.erase("telemetry_opt_in")
	if start != selection.path:
		overrides.ruleset.start_id = start.get_file().get_basename()
	SaveLoad.prepare_new_game(start, overrides)
	print("CAROUSEL setup ", JSON.stringify({"start": start, "overrides": overrides,
		"quality": PlayerProfile.graphics_quality, "window": [get_window().size.x,get_window().size.y]}))
	# Retain this probe across the scene change, just as the loading layer is retained.
	get_tree().current_scene = null
	var started := Time.get_ticks_msec()
	if OS.get_environment("CAROUSEL_PROFILE") != "":
		_profile_started = Time.get_ticks_usec()
		_profile_last = _profile_started
		print("CAROUSEL profile start_abs_ms=", started)
	screen.begin_load(SaveLoad.MAIN_SCENE)
	if _profile_started == 0:
		await _shot("real-first-frame")
	while is_instance_valid(screen) and not bool(screen.get("_morphed")):
		if Time.get_ticks_msec()-started > 120000:
			push_error("Loading carousel probe timed out before Begin")
			get_tree().quit(1)
			return
		await get_tree().process_frame
	print("CAROUSEL real New Game ready_ms=", Time.get_ticks_msec()-started)
	if _profile_started != 0:
		_write_profile()
	await get_tree().create_timer(1.1).timeout
	await _shot("real-ready")
	if OS.get_environment("CAROUSEL_PROFILE") == "":
		screen.call("_on_begin_pressed")
		await get_tree().create_timer(1.2).timeout
		await _shot("real-play")
		print("CAROUSEL released=", not is_instance_valid(screen))
	# Run scene cleanup while rendering services still exist, including 3D worker cancellation.
	var world := get_tree().current_scene
	get_tree().current_scene = null
	if is_instance_valid(world):
		world.queue_free()
	for _frame in 8:
		await get_tree().process_frame


func _process(_delta: float) -> void:
	if _profile_started == 0:
		return
	var now := Time.get_ticks_usec()
	var gap := float(now-_profile_last)/1000.0
	var record := {"wall_ms": float(now-_profile_started)/1000.0, "frame_ms": gap,
		"abs_ms": now/1000.0, "last_draw_ms": _last_draw_ms, "window": [get_window().size.x,get_window().size.y]}
	_profile_frames.append(record)
	_profile_last = now
	if gap > 100.0:
		print("CAROUSEL STALL ", JSON.stringify(record))


func _write_profile() -> void:
	var frames := _profile_frames.duplicate()
	frames.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.frame_ms < b.frame_ms)
	var slow := _profile_frames.filter(func(f: Dictionary) -> bool: return f.frame_ms > 100.0)
	var summary := {"ready_ms": (Time.get_ticks_usec()-_profile_started)/1000.0,
		"frames": frames.size(), "over_100ms": slow.size(), "worst_ms": frames[-1].frame_ms,
		"p95_ms": frames[floori((frames.size()-1)*0.95)].frame_ms}
	FileAccess.open(_out+"/profile.json", FileAccess.WRITE).store_string(JSON.stringify({"summary": summary, "stalls": slow, "frames": _profile_frames}, "\t"))
	print("CAROUSEL PROFILE ", JSON.stringify(summary))
	_profile_started = 0


func _record(screen: Node) -> void:
	var carousel: Control = screen.get("_carousel")
	carousel.set_process(false)
	screen.set_process(false)
	for frame in 900:
		carousel.call("seek", frame/30.0)
		screen.call("_process", 1.0/30.0)
		var image := await _capture_frame()
		if image == null:
			return
		image.save_jpg(_out+"/frame_%04d.jpg" % frame, 0.92)
	FileAccess.open(_out+"/record.json", FileAccess.WRITE).store_string(JSON.stringify({
		"frames": 900, "fps": 30, "width": _capture_size.x, "height": _capture_size.y,
		"capture_retries": _capture_retries}, "\t"))
	print("CAROUSEL loop: 900 frames at 30 fps")


func _shot(name: String) -> void:
	get_window().size = _capture_size
	for _frame in 4:
		await get_tree().process_frame
	var image := await _capture_frame()
	if image != null:
		image.save_png(_out+"/"+name+".png")


func _capture_frame() -> Image:
	# macOS can finish restoring a saved fullscreen size a frame after our request.
	# Never feed that wrong-aspect frame to the encoder; hold the review timeline
	# until both the window and the rendered image match the requested dimensions.
	for attempt in 30:
		get_window().size = _capture_size
		await get_tree().process_frame
		RenderingServer.force_draw(false)  # occluded macOS windows may not present
		var image := get_viewport().get_texture().get_image()
		if image.get_size() == _capture_size and get_window().size == _capture_size:
			return image
		_capture_retries += 1
		print("CAROUSEL capture retry ", attempt, ": wanted ", _capture_size, ", got ", image.get_size())
	_capture_failed = true
	push_error("Loading carousel capture could not settle at the requested size")
	return null
