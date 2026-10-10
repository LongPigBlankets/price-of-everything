extends Node
## Windowed visual smoke test. Uses a disposable game, never a saved game.
## AGENT_GODOT_WINDOW=1 godot --path . res://tools/supply_chain_3d/capture.tscn -- --no-telemetry
const Harness := preload("res://tools/shot_harness.gd")
func _ready() -> void:
	Harness.prepare_window(get_window(), Vector2i(1920, 1080))
	Harness.arm_watchdog(self, 900.0 if "--continent-review" in OS.get_cmdline_user_args() else 240.0)
	TelemetryState.enabled = false
	SaveLoad.autosave_enabled = false
	AudioServer.set_bus_mute(0, true)
	var menu: Control = load("res://scenes/main_menu.tscn").instantiate()
	get_tree().root.add_child.call_deferred(menu)
	await get_tree().process_frame
	get_tree().current_scene = menu
	menu.call("_on_new_game_pressed")
	SaveLoad.prepare_new_game("res://data/starts/metal_magnate.json")
	var loading := LoadingScreen.show_global(get_tree())
	loading.begin_load(SaveLoad.MAIN_SCENE)
	var main: Node
	while true:
		main = get_tree().current_scene
		if main != menu and main != null and bool(main.get("build_complete")): break
		await get_tree().process_frame
	while not bool(loading.call("_ready_to_begin")): await get_tree().process_frame
	loading.call("_on_begin_pressed")
	while is_instance_valid(loading): await get_tree().process_frame
	for i in 3: await get_tree().process_frame
	print("[3D] menu -> New Game -> Begin succeeded")
	MatchState.ruleset["opener_done"] = true
	Tutorial._on_overlay_skipped()
	DecisionState.enabled = false
	for layer in get_tree().root.find_children("*", "CanvasLayer", true, false):
		var script := layer.get_script() as Script
		if script != null and script.resource_path.ends_with("_intro.gd"):
			if layer.has_method("_on_begin"): layer.call("_on_begin")
			else: layer.queue_free()
	for i in 3: await get_tree().process_frame
	var view: Control = main.find_child("EmpireView", true, false)
	await view.call("prepare")
	Harness.prepare_window(get_window(), Vector2i(1920, 1080))
	for i in 5: await get_tree().process_frame
	view.call("toggle")
	var board: Control = view.find_child("Board", true, false)
	await get_tree().physics_frame
	board.call("fit_view")
	var home: Dictionary = board.call("capture_camera")
	if "--continent-review" in OS.get_cmdline_user_args():
		await _continent_review(board, home)
		for i in 5: await get_tree().process_frame
		await _finish_capture()
		return
	if not await _exercise_pointer(board): return
	board.call("restore_camera", home)
	print("[3D] camera ", home, " tiles ", board.get("_model").tiles.size(), " objects ", board.get("_builder").pickables.size())
	for i in 4:
		var state := home.duplicate()
		state.yaw += PI * 0.5 * i
		board.call("restore_camera", state)
		await _shot("orbit_%d" % i)
	board.call("restore_camera", home)
	var tiles: Dictionary = board.get("_model").tiles
	var first := str(tiles.keys()[0])
	var builder: RefCounted = board.get("_builder")
	var camera: Camera3D = board.get("_camera")
	await _click(board.call("screen_point", builder.point(tiles[first].center)))
	if str(board.get("_selected_tile")) != first:
		push_error("GUI Shift-click must select the projected tile")
		get_tree().quit(1)
		return
	await _shot("tile_selected")
	var panel: Control = main.get("info_panel")
	print("[3D] tile panel visible: ", panel.visible)
	if not panel.visible:
		get_tree().quit(1)
		return
	panel.hide()
	var close := home.duplicate()
	close.span *= 0.48
	board.call("restore_camera", close)
	await _shot("close")
	print("[3D] drawcalls ", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), " triangles ", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	if "--artwork-review" in OS.get_cmdline_user_args() and not await _mine_review(board):
		get_tree().quit(1)
		return
	if "--detail-review" in OS.get_cmdline_user_args(): await _detail_review(board, home)
	await _finish_capture()

func _finish_capture() -> void:
	# Background windows can stop rendering while process frames continue. Drain
	# deferred frame_post_draw captures, then release the disposable game before
	# Godot destroys its scripting runtime. Otherwise cached review runs can leave
	# an Image/coroutine alive and abort in the native Variant allocator at exit.
	for i in 8:
		RenderingServer.force_draw(false)
		await get_tree().process_frame
	var main := get_tree().current_scene
	if is_instance_valid(main) and main != self: main.queue_free()
	for i in 8:
		RenderingServer.force_draw(false)
		await get_tree().process_frame
	get_tree().quit()

func _shot(label: String) -> void:
	for i in 5: await get_tree().process_frame
	Harness.capture(self, "/private/tmp/supply3d_%s.png" % label, Vector2i(1920, 1080))

func _continent_review(board: Control, home: Dictionary) -> void:
	var tag := "continent_v1"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--review-tag="): tag = argument.trim_prefix("--review-tag=")
	var owned_count: int = board.get("_model").tiles.size()
	var start := Time.get_ticks_msec()
	await board.call("set_all_tiles", true, false)
	var measurements := {"build_ms": Time.get_ticks_msec() - start, "tiles": board.get("_model").tiles.size(), "lods": []}
	var builder: RefCounted = board.get("_builder")
	measurements.cache_directory = ProjectSettings.globalize_path(builder.bake_cache.directory)
	measurements.continent_key = builder._continent_key
	measurements.continent_cache_hits = builder.bake_cache.hits
	measurements.continent_cache_writes = builder.bake_cache.writes
	measurements.base_tiles_loaded_at_open = builder.terrain_lods.size()
	measurements.detail_chunks_loaded_at_open = builder._chunk_data.size()
	measurements.separate_tile_resources = builder.continent.get("tile_chunks", {}).size()
	measurements.decorative_sprite_variants = builder.continent.get("decor_sprites", {}).size()
	print("[BAKE] continent key=", builder._continent_key, " hits=", builder.bake_cache.hits, " writes=", builder.bake_cache.writes)
	print("[CONTINENT] build_ms=", measurements.build_ms, " tiles=", measurements.tiles)
	var all_home: Dictionary = board.call("capture_camera")
	var focus: Vector3 = home.target
	for tile in board.get("_model").tiles.values():
		if "Snare Harbour Coast" in str(tile.label): focus = board.get("_builder").point(tile.center); break
	for tier in 3:
		var state := all_home.duplicate()
		if tier > 0:
			state.target = focus
			state.span = 1100.0 if tier == 1 else 560.0
		var detail_start := Time.get_ticks_msec()
		board.call("restore_camera", state)
		for i in 20: await get_tree().process_frame
		while not board.call("detail_ready"): await get_tree().process_frame
		await board.call("_stream_visible")
		var detail_ms := Time.get_ticks_msec() - detail_start
		for i in 15: await get_tree().process_frame
		var frames: Array[float] = []
		var last := Time.get_ticks_usec()
		for i in 60:
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			frames.append(float(now - last) / 1000.0)
			last = now
		frames.sort()
		# A background window need not render process frames. Force the current
		# view, then query this 3D viewport rather than stale global/HUD counters.
		for i in 3:
			RenderingServer.force_draw(false)
			await get_tree().process_frame
		var viewport: SubViewport = board.get("_viewport")
		var draws := viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
		var triangles := viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)
		Harness.capture(self, "/private/tmp/%s_%s.png" % [tag, ["far", "medium", "near"][tier]], Vector2i(1920, 1080))
		var bytes := 0
		var resident := 0
		var textures := {}
		if builder.continent.get("texture") != null:
			var atlas: Texture2D = builder.continent.texture
			textures[atlas.get_instance_id()] = true
			bytes += int(atlas.get_width() * atlas.get_height() * 4.0 * 4.0 / 3.0)
		for item in board.get("_builder").terrain_lods:
			if item.data.meshes[1] != null or item.data.meshes[2] != null: resident += 1
			for texture in item.data.textures:
				if texture != null and not textures.has(texture.get_instance_id()):
					textures[texture.get_instance_id()] = true
					bytes += int(texture.get_width() * texture.get_height() * 4.0 * 4.0 / 3.0)
		print("[CONTINENT] tier=", tier, " span=", state.span, " resident=", resident, " terrain_MiB=", bytes / 1048576.0,
			" draws=", draws, " triangles=", triangles)
		measurements.lods.append({"tier": tier, "span": state.span, "resident_tiles": resident, "terrain_texture_MiB": bytes / 1048576.0,
			"draw_calls": draws, "triangles": triangles, "detail_ms": detail_ms,
			"base_resident_tiles": builder.local_tiles.size(), "base_chunks": builder._chunk_data.size(),
			"medium_sprite_groups": builder.sprite_pairs.filter(func(pair: Dictionary) -> bool: return pair.get("medium") != null and pair.medium.visible).size(),
			"frame_median_ms": frames[30], "frame_p95_ms": frames[57]})
	# Exercise bounded residency through pan, orbit, a return visit and far reset.
	while not board.call("detail_ready"): await get_tree().process_frame
	board.set_process(false)
	var tours: Array = []
	for shift in [Vector3(2400, 0, 900), Vector3(-2100, 0, -1300), Vector3.ZERO]:
		var state := all_home.duplicate()
		state.target = focus + shift
		state.span = 1100.0
		state.yaw += 0.5 if shift != Vector3.ZERO else 0.0
		board.call("restore_camera", state)
		var pan_start := Time.get_ticks_msec()
		await board.call("_stream_visible")
		while not board.call("detail_ready"):
			RenderingServer.force_draw(false)
			await get_tree().process_frame
		assert(builder.local_tiles.size() <= builder.BASE_RESIDENT_TILES)
		assert(builder._chunk_data.size() == builder.local_tiles.size())
		assert(builder.terrain_lods.size() == builder.local_tiles.size())
		tours.append({"base_tiles": builder.local_tiles.size(), "load_ms": Time.get_ticks_msec() - pan_start})
	measurements.pan_tours = tours
	var widest := all_home.duplicate()
	widest.span = preload("res://scripts/supply_chain_3d/orbit_camera.gd").MAX_SIZE
	board.call("restore_camera", widest)
	while not board.call("detail_ready"):
		RenderingServer.force_draw(false)
		await get_tree().process_frame
	await board.call("_stream_visible")
	measurements.far_retained_tiles = builder.local_tiles.size()
	assert(not builder.local_tiles.is_empty(), "The outgoing view remains cached during the ten-second grace period")
	board.set("_far_detail_expires_msec", Time.get_ticks_msec() - 1)
	await board.call("_stream_visible")
	assert(builder.local_tiles.is_empty() and builder._chunk_data.is_empty() and builder.terrain_lods.is_empty())
	measurements.far_reset_releases_detail_after_grace = true
	board.set_process(true)
	var visible := 0
	for tile in board.get("_model").tiles.values():
		if Rect2(Vector2.ZERO, board.size).has_point(board.call("screen_point", board.get("_builder").point(tile.center))): visible += 1
	print("[CONTINENT] max zoom visible tile centres=", visible)
	measurements.max_zoom_visible_tiles = visible
	assert(visible >= 50, "Maximum zoom must fit at least fifty tiles")
	var buildings_as_tiles := 0
	for item in builder.pickables:
		if str(item.kind) != "building": continue
		var hit: Dictionary = board.call("pick_at", board.call("screen_point", item.point))
		if not hit.is_empty() and (not hit.collider.has_meta("standing") or builder._overview): buildings_as_tiles += 1
	assert(buildings_as_tiles > 0, "Far building clicks must target tiles")
	measurements.far_buildings_pick_as_tiles = buildings_as_tiles
	board.call("restore_camera", all_home)
	var click_tile := ""
	for id in board.get("_model").tiles:
		if not bool(board.get("_model").tiles[id].store) and board.get("_model").tiles[id].type == "rural": click_tile = id; break
	if click_tile != "":
		var at: Vector3 = board.get("_builder").point(board.get("_model").tiles[click_tile].center)
		var state := all_home.duplicate()
		state.target = at
		state.span = 700.0
		board.call("restore_camera", state)
		await get_tree().physics_frame
		var hit: Dictionary = board.call("pick_at", board.call("screen_point", at))
		var picked: bool = not hit.is_empty() and str(hit.get("tile_id", hit.collider.get_meta("tile_id", ""))) == click_tile
		assert(picked, "Unowned tiles remain selectable")
		print("[CONTINENT] unowned tile picks=", picked)
	await board.call("set_all_tiles", false, false)
	assert(board.get("_model").tiles.size() == owned_count, "Coverage returns to the original company tiles")
	print("[CONTINENT] owned coverage restored=", owned_count)
	measurements.total_cache_hits = builder.bake_cache.hits
	measurements.total_cache_writes = builder.bake_cache.writes
	print("[BAKE] total hits=", builder.bake_cache.hits, " writes=", builder.bake_cache.writes)
	measurements.owned_tiles = owned_count
	var report := FileAccess.open("/private/tmp/%s_measurements.json" % tag, FileAccess.WRITE)
	report.store_string(JSON.stringify(measurements, "\t"))

func _exercise_pointer(board: Control) -> bool:
	var before: Dictionary = board.call("capture_camera")
	var event := InputEventMouseButton.new()
	event.position = board.size * 0.5
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = true
	get_viewport().push_input(event, true)
	var motion := InputEventMouseMotion.new()
	motion.position = event.position + Vector2(100, -40)
	motion.relative = Vector2(100, -40)
	motion.button_mask = MOUSE_BUTTON_MASK_RIGHT
	get_viewport().push_input(motion, true)
	event.pressed = false
	event.position = motion.position
	get_viewport().push_input(event, true)
	await get_tree().process_frame
	var after: Dictionary = board.call("capture_camera")
	if is_equal_approx(before.yaw, after.yaw) or is_equal_approx(before.pitch, after.pitch):
		push_error("GUI drag must orbit the 3D camera")
		get_tree().quit(1)
		return false
	print("[3D] GUI right drag changed yaw and pitch")
	var pinch := InputEventMagnifyGesture.new()
	pinch.position = board.size * 0.5
	pinch.factor = 1.15
	get_viewport().push_input(pinch, true)
	await get_tree().process_frame
	if not is_equal_approx(board.call("capture_camera").span, after.span / 1.15):
		push_error("GUI pinch must zoom the 3D camera")
		get_tree().quit(1)
		return false
	print("[3D] GUI trackpad pinch changed zoom")
	return true

func _click(position: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.shift_pressed = true
	event.pressed = true
	get_viewport().push_input(event, true)
	event.pressed = false
	get_viewport().push_input(event, true)
	await get_tree().process_frame

func _detail_review(board: Control, home: Dictionary) -> void:
	var focus: Vector3 = home.target
	for tile in board.get("_model").tiles.values():
		if "Snare Harbour Coast" in str(tile.label):
			focus = board.get("_builder").point(tile.center)
			break
	board.call("_select_tile", "")
	var texture_bytes := 0.0
	for item in board.get("_builder").terrain_lods:
		for texture in item.data.textures: texture_bytes += texture.get_width() * texture.get_height() * 4.0 * 4.0 / 3.0
	print("[LOD] retained terrain texture MiB=", texture_bytes / 1048576.0)
	for tier in 3:
		var state := home.duplicate()
		state.target = focus if tier > 0 else home.target
		state.span = [2200.0, 1100.0, 560.0][tier]
		board.call("restore_camera", state)
		await _shot("detail_%s" % ["far", "medium", "near"][tier])
		for warm in 60:
			RenderingServer.force_draw(false)
			await get_tree().process_frame
		var samples: Array[float] = []
		for frame in 45:
			var start := Time.get_ticks_usec()
			RenderingServer.force_draw(false)
			await get_tree().process_frame
			samples.append((Time.get_ticks_usec() - start) / 1000.0)
		samples.sort()
		print("[LOD] tier=", board.get("_detail"), " median_ms=", samples[22], " p95_ms=", samples[42],
			" draws=", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			" triangles=", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			" texture_MiB=", Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0)
	# Rotation must retain the print pattern and directional volume at near detail.
	var close: Dictionary = board.call("capture_camera")
	close.yaw += PI * 0.65
	board.call("restore_camera", close)
	await _shot("detail_near_rotated")
	board.get_parent().set_process(false)
	board.hide()
	var wrapper := Control.new()
	board.get_parent().add_child(wrapper)
	wrapper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Color("2b3757")
	wrapper.add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var original := preload("res://scripts/empire_board.gd").new()
	wrapper.add_child(original)
	original.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board.hide()
	await original.build_async(board.get("_last_graph"), board.get("_last_terrain"))
	for tier in [0, 1, 2]:
		var span: float = [2200.0, 1100.0, 560.0][tier]
		var target: Vector3 = home.target if tier == 0 else focus
		original.set("_zoom", original.size.y / span)
		original.set("_offset", original.size * 0.5 - original.iso(Vector2(target.x, target.z), target.y) * original.size.y / span)
		original.call("_view_changed")
		await Harness.await_board_baked(self, original, 20.0)
		original.modulate = Color.WHITE
		await _shot("reference_%s" % ["far", "medium", "near"][tier])
	wrapper.queue_free()
	board.get_parent().set_process(true)
	board.show()
	board.call("restore_camera", home)

func _mine_review(board: Control) -> bool:
	# Disposable three-level fixture on the same terrain and rendering path as play.
	var source: RefCounted = board.get("_builder")
	var mine := {}
	for standing in board.get("_model").standing:
		if str(standing.get("internal_name", "")) == "mine": mine = standing; break
	if mine.is_empty(): push_error("Mine review needs a company mine"); return false
	var builder := preload("res://scripts/supply_chain_3d/world_builder.gd").new()
	var tid := str(mine.tile)
	var center: Vector2 = source.tiles[tid].center
	builder.tiles = {tid: source.tiles[tid]}
	builder.ground = source.ground
	builder.rivers = source.rivers
	var standing: Array = []
	for level in [1, 2, 3]:
		var item: Dictionary = mine.duplicate()
		item.level = level
		item.iid = "review_mine_%d" % level
		item.side = 120.0
		item.pos = center + Vector2(145, -60) * (level - 2)
		standing.append(item)
	builder.configure_grade()
	builder.configure_pits(standing)
	await builder.prepare_tile(self, tid)
	var fixture := Node3D.new()
	fixture.add_child(builder.tile_node(tid))
	fixture.add_child(builder.mine_rims_node())
	for item in standing: fixture.add_child(builder.standing_node(item))
	builder.set_detail(2)
	var content: Node3D = board.get("_content")
	var layers: Dictionary = {}
	for body in content.find_children("*", "CollisionObject3D", true, false):
		layers[body] = body.collision_layer
		body.collision_layer = 0
	board.call("_select_tile", "")
	content.hide()
	board.get("_labels").hide()
	board.get("_world").add_child(fixture)
	var camera: Camera3D = board.get("_camera")
	var home: Dictionary = board.call("capture_camera")
	var state := home.duplicate()
	state.target = builder.point(center)
	state.span = 440.0
	board.call("restore_camera", state)
	await get_tree().physics_frame
	var mine_picks := 0
	for item in standing:
		var hit: Dictionary = board.call("pick_at", board.call("screen_point", builder.point(item.pos)))
		if not hit.is_empty() and str(hit.collider.get_meta("standing", {}).get("iid", "")) == item.iid: mine_picks += 1
	print("[3D] mine fixture picking ", mine_picks, "/3")
	if mine_picks != 3: push_error("All submerged mine levels must remain pickable")
	await _shot("mine_levels")
	state.yaw += PI
	board.call("restore_camera", state)
	await _shot("mine_levels_rotated")
	fixture.queue_free()
	for body in layers: body.collision_layer = layers[body]
	content.show()
	board.get("_labels").show()
	source.configure_grade()
	board.call("restore_camera", home)
	return mine_picks == 3
