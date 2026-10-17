extends "res://tools/supply_chain_3d/capture.gd"
## Real-game load breakdown and a fixed-angle pan over Capital City.
var output := "/private/tmp/supply3d-startup"
var first_open := {}
var first_open_started := 0

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--startup-output="): output = arg.trim_prefix("--startup-output=")
	DirAccess.make_dir_recursive_absolute(output)
	PlayerProfile.supply_chain_all_tiles = false # disposable process; never save preferences
	await super._ready()

func _open_supply_view(view: Control) -> void:
	if "--combined-open" not in OS.get_cmdline_user_args():
		await super._open_supply_view(view)
		return
	var board: Control = view.find_child("Board", true, false)
	first_open = {"prepared_before_open": view.is_prepared(),
		"preparing_before_open": view._preparing,
		"background_load": board.load_profile.duplicate()}
	first_open_started = Time.get_ticks_usec()
	view.toggle()
	await _settle(board)
	first_open.ready_ms = (Time.get_ticks_usec() - first_open_started) / 1000.0
	first_open.load = board.load_profile.duplicate()
	first_open.tiles = board._model.tiles.size()
	print("[FIRST OPEN] ", JSON.stringify(first_open))

func _settle(board: Control) -> void:
	await board._stream_visible()
	while not board.detail_ready():
		RenderingServer.force_draw(false)
		await get_tree().process_frame
	RenderingServer.force_draw(false)

func _continent_review(board: Control, home: Dictionary) -> void:
	if "--profile-layout" in OS.get_cmdline_user_args():
		_profile_layout(board)
		return
	var started := Time.get_ticks_usec()
	await board.set_all_tiles(true, false)
	await _settle(board)
	var report := {"engine": Engine.get_version_info().string,
		"load": board.load_profile.duplicate(), "ready_ms": (Time.get_ticks_usec() - started) / 1000.0,
		"opening_camera": board.capture_camera(), "previous_camera": home,
		"opening_lod": board._detail, "local_tiles": board._builder.local_tiles.size(),
		"cache_hits_after_stream": board._builder.bake_cache.hits,
		"bundled_hits_after_stream": board._builder.bake_cache.bundled_hits,
		"cache_writes_after_stream": board._builder.bake_cache.writes,
		"continent_key": board._builder._continent_key, "scenery_key": board._builder._scenery_key}
	if not first_open.is_empty():
		report.first_open = first_open
		report.combined_ready_ms = (Time.get_ticks_usec() - first_open_started) / 1000.0
		FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
		print("[STARTUP PROBE] ", JSON.stringify(report))
		return
	var capital := ""
	for tid in board._builder.tiles:
		if "capital" in str(board._builder.tiles[tid].label).to_lower(): capital = tid; break
	report.capital = capital
	var state := home.duplicate()
	state.span = board.size.y
	if capital != "": state.target = board._builder.point(board._builder.tiles[capital].center)
	board.restore_camera(state)
	await _settle(board)
	board.set_process(false)
	board._labels.hide()
	board._viewport.get_texture().get_image().save_png(output.path_join("capital-medium.png"))
	var cases := []
	for yaw in [board.Rig.HOME_YAW, PI / 16.0, PI * 3.0 / 16.0]:
		state.yaw = yaw
		board.restore_camera(state)
		var reference: Basis = board._camera.basis
		var frames := {}
		var bases := {}
		for i in 300:
			board._rig.pan(Vector2(3, 1), board.size.y)
			board._rig.apply(board._camera)
			var direction: Vector3 = board._camera.basis.z.normalized()
			var frame := posmod(floori(fposmod(atan2(direction.x, direction.z), TAU) / TAU * 16.0 + 0.5), 16)
			frames[frame] = int(frames.get(frame, 0)) + 1
			bases[board._camera.basis] = true
		cases.append({"yaw": yaw, "frames": frames, "unique_bases": bases.size(), "basis_unchanged": reference == board._camera.basis})
	report.pan_cases = cases
	# Actual pointer gestures in the game viewport must preserve the same frame.
	state.yaw = PI / 16.0
	board.restore_camera(state)
	for i in 8:
		var gesture := InputEventPanGesture.new()
		gesture.delta = Vector2(-20.0 / 12.0, 0)
		gesture.position = board.size * 0.5
		board._gui_input(gesture)
		await _settle(board)
		board._viewport.get_texture().get_image().save_png(output.path_join("capital-pan-%02d.png" % i))
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("[STARTUP PROBE] ", JSON.stringify(report))

func _profile_layout(board: Control) -> void:
	# Instrument an in-memory copy; editing the model file would invalidate the
	# resources under measurement through the source-fingerprint guard.
	var source := FileAccess.get_file_as_string("res://scripts/empire_board_model.gd")
	source = source.replace("\t_shores = shores", "\tvar profile_tick := Time.get_ticks_usec()\n\t_shores = shores")
	for marker in ["# Optional coverage", "# What each tile's rivers", "# Stand everything", "var route := func", "# The crossroads", "# Neighbouring tiles", "# Cables run", "return {\"tiles\""]:
		var line: String = "\t" + marker
		var checkpoint := "\tprint(\"[LAYOUT SECTION] %s \", (Time.get_ticks_usec() - profile_tick) / 1000.0)\n\tprofile_tick = Time.get_ticks_usec()\n" % marker.replace("\"", "'")
		source = source.replace(line, checkpoint + line)
	var instrumented := GDScript.new()
	instrumented.source_code = source
	assert(instrumented.reload() == OK)
	var water: Callable = board.Legacy._water_test(board._last_terrain)
	var costs := {}
	for query in board._layout_queries.data.costs: costs[query + "|" + str(water.hash())] = board._layout_queries.data.costs[query]
	instrumented._street_costs = costs
	var shores := {}
	for query in board._layout_queries.data.shores: shores[query + ", " + str(water.hash()) + "]"] = board._layout_queries.data.shores[query]
	instrumented._shore_streets = shores
	board.Model.Streets._paths = board._layout_queries.data.paths.duplicate(true)
	var rivers := {}
	for tid in board._builder.rivers:
		rivers[tid] = []
		for rec in board._builder.rivers[tid]: rivers[tid].append(rec.points)
	var tiles := []
	for coord in board._last_terrain.get("tiles"): tiles.append("tile_%d_%d" % [coord.x + 1, coord.y + 1])
	var model: Dictionary = instrumented.build(board._last_terrain, board._last_graph, board._true_positions(board._last_graph, board._last_terrain),
		rivers, true, water, board.Legacy._shore_test(board._last_terrain), tiles)
	print("[LAYOUT SECTION] result ", model.tiles.size(), " tiles, ", model.standing.size(), " standing")
