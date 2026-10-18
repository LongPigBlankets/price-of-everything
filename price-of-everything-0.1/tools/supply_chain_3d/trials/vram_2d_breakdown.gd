extends Node
## What the 2D map holds in video memory, and what releasing it while the 3D view
## covers the map would save. New Metal Magnate game through the real menu.
## AGENT_GODOT_WINDOW=1 godot --path . res://tools/supply_chain_3d/trials/vram_2d_breakdown.tscn -- \
##   --no-telemetry --bake-cache-directory=<new dir> --trial-output=<dir>
## Every texture reachable from the scene tree (properties, script variables,
## shader parameters, tile sets) and from the static texture caches is sized
## from its real GPU format. Release experiments measure the actual delta.
const Harness := preload("res://tools/shot_harness.gd")
const AuthoredBake := preload("res://scripts/authored_bake.gd")
## Static caches that hold textures for the 2D map, the HUD and the 3D view.
const STATIC_CACHES := [
	["res://scripts/authored_bake.gd", "_textures"], ["res://scripts/hill_texture_baked.gd", "_cache"],
	["res://scripts/hill_baked.gd", "_cache"], ["res://scripts/empire_board.gd", "_ground_textures"],
	["res://scripts/empire_board.gd", "_window_tex"], ["res://scripts/empire_board.gd", "_tree_tex"],
	["res://scripts/empire_board.gd", "_mine_tex"], ["res://scripts/good_icons.gd", "_texture_cache"],
	["res://scripts/building_sprites.gd", "_cache"], ["res://scripts/building_sprites.gd", "_content_cache"],
	["res://scripts/building_sprites.gd", "_npc_cache"], ["res://scripts/building_icon.gd", "_cache"],
	["res://scripts/keyed_building_icon.gd", "_cache"], ["res://scripts/empire_fx.gd", "_arm_frames"],
	["res://scripts/bdp_v3_plate.gd", "_textures"], ["res://scripts/effect_emblem.gd", "_cache"],
	["res://scripts/start_layout_baked.gd", "_cache"],
]
var output := ""
var report := {"stages": []}
var _seen := {}
var _rows := {}
var _visited := {}
var _weak: Array = []

func _rd() -> RenderingDevice: return RenderingServer.get_rendering_device()

func _mib(bytes: float) -> float: return snappedf(bytes / 1048576.0, 0.1)

func _stage(name: String) -> void:
	for i in 5: RenderingServer.force_draw(false); await get_tree().process_frame
	var row := {"stage": name, "total_MiB": _mib(_rd().get_memory_usage(RenderingDevice.MEMORY_TOTAL)),
		"textures_MiB": _mib(_rd().get_memory_usage(RenderingDevice.MEMORY_TEXTURES)),
		"buffers_MiB": _mib(_rd().get_memory_usage(RenderingDevice.MEMORY_BUFFERS)),
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"rs_texture_MiB": _mib(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)),
		"authored_alive": _weak.filter(func(w: WeakRef) -> bool: return w.get_ref() != null).size()}
	report.stages.append(row)
	print("[VRAM 2D] ", JSON.stringify(row))

## Bytes per pixel, or per block for block-compressed formats ([bytes, block]).
func _format_cost(format: int) -> Array:
	var names := {}
	for name in ClassDB.class_get_integer_constant_list("RenderingDevice"):
		if name.begins_with("DATA_FORMAT_"): names[ClassDB.class_get_integer_constant("RenderingDevice", name)] = name
	var label := str(names.get(format, "UNKNOWN"))
	if label.contains("ASTC_4x4") or label.contains("BC7") or label.contains("BC3") or label.contains("BC5") or label.contains("ETC2_R8G8B8A8") or label.contains("EAC_R11G11"): return [16, 4, label]
	if label.contains("BC1") or label.contains("BC4") or label.contains("ETC2_R8G8B8_") or label.contains("EAC_R11_"): return [8, 4, label]
	if label.contains("ASTC_8x8"): return [16, 8, label]
	if label.contains("R32G32B32A32"): return [16, 1, label]
	if label.contains("R16G16B16A16"): return [8, 1, label]
	if label.contains("R8G8B8A8") or label.contains("B8G8R8A8") or label.contains("A2B10G10R10") or label.contains("B10G11R11") or label.contains("D32") or label.contains("D24") or label.contains("R32_") or label.contains("R16G16_"): return [4, 1, label]
	if label.contains("R8G8_") or label.contains("R16_") or label.contains("D16"): return [2, 1, label]
	if label.contains("R8_"): return [1, 1, label]
	return [4, 1, label]

func _texture_bytes(texture: Texture2D) -> Dictionary:
	var rd_rid := RenderingServer.texture_get_rd_texture(texture.get_rid())
	if not rd_rid.is_valid(): return {}
	var format: RDTextureFormat = _rd().texture_get_format(rd_rid)
	var cost := _format_cost(format.format)
	var bytes := 0.0
	var w := format.width; var h := format.height
	for level in maxi(1, format.mipmaps):
		bytes += ceilf(float(w) / cost[1]) * ceilf(float(h) / cost[1]) * cost[0]
		w = maxi(1, w >> 1); h = maxi(1, h >> 1)
	bytes *= maxi(1, format.array_layers) * maxi(1, format.depth) * (1 << format.samples)
	return {"bytes": bytes, "format": cost[2], "size": [format.width, format.height], "mipmaps": format.mipmaps}

func _category(texture: Texture2D, who: String) -> String:
	var path := texture.resource_path
	if path.begins_with("res://"):
		var parts := path.trim_prefix("res://").split("/")
		return "/".join(parts.slice(0, mini(parts.size() - 1, 4)))
	return "%s <%s>" % [who, texture.get_class()]

func _add(texture: Texture2D, who: String) -> void:
	if texture == null: return
	var rid := texture.get_rid()
	if not rid.is_valid() or _seen.has(rid): return
	_seen[rid] = true
	var size := _texture_bytes(texture)
	if size.is_empty(): return
	var key := _category(texture, who)
	var row: Dictionary = _rows.get_or_add(key, {"count": 0, "bytes": 0.0, "formats": {}, "owner": who})
	row.count += 1
	row.bytes += size.bytes
	row.formats[size.format] = int(row.formats.get(size.format, 0)) + 1

func _walk(value: Variant, who: String, depth: int) -> void:
	if depth > 5: return
	if value is Texture2D: _add(value, who)
	elif value is Material:
		if _visited.has(value): return
		_visited[value] = true
		if value is ShaderMaterial and value.shader != null:
			for param in value.shader.get_shader_uniform_list():
				_walk(value.get_shader_parameter(param.name), who, depth + 1)
		for prop in value.get_property_list():
			if prop.type == TYPE_OBJECT: _walk(value.get(prop.name), who, depth + 1)
	elif value is Dictionary:
		for item in value.values(): _walk(item, who, depth + 1)
	elif value is Array:
		for item in value: _walk(item, who, depth + 1)
	elif value is TileSet:
		for i in value.get_source_count():
			var source: TileSetSource = value.get_source(value.get_source_id(i))
			if source is TileSetAtlasSource: _walk(source.texture, who, depth + 1)
	elif value is MultiMesh or value is Mesh or value is StyleBoxTexture or value is AtlasTexture:
		if _visited.has(value): return
		_visited[value] = true
		for prop in value.get_property_list():
			if prop.type == TYPE_OBJECT: _walk(value.get(prop.name), who, depth + 1)

func _owner_of(node: Node) -> String:
	var root := get_tree().current_scene
	var path := str(root.get_path_to(node)) if root != null and root.is_ancestor_of(node) else str(node.get_path())
	var parts := path.split("/")
	return "/".join(parts.slice(0, mini(parts.size(), 2)))

func _inventory(label: String) -> void:
	_seen.clear(); _rows.clear(); _visited.clear()
	for node in get_tree().root.find_children("*", "", true, false):
		if not is_instance_valid(node): continue
		var who := _owner_of(node)
		for prop in node.get_property_list():
			if prop.type in [TYPE_OBJECT, TYPE_DICTIONARY, TYPE_ARRAY] and prop.name not in ["script", "owner"]:
				var value: Variant = node.get(prop.name)
				if value is Node: continue
				_walk(value, who, 0)
		if node is Viewport:
			_add(node.get_texture(), "viewport " + who)
	for entry in STATIC_CACHES:
		var script: Script = load(entry[0])
		_walk(script.get(entry[1]), "static " + str(entry[0]).get_file() + ":" + str(entry[1]), 0)
	var rows: Array = []
	var total := 0.0
	for key in _rows:
		var row: Dictionary = _rows[key]
		total += row.bytes
		rows.append({"category": key, "MiB": _mib(row.bytes), "count": row.count, "formats": row.formats, "owner": row.owner})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.MiB > b.MiB)
	report[label] = {"textures_MiB": _mib(total), "rows": rows}
	print("[VRAM 2D] inventory ", label, " ", _mib(total), " MiB in ", _seen.size(), " textures")
	for row in rows.slice(0, 12): print("   ", JSON.stringify(row))

func _shot(main: Node, name: String) -> void:
	if output == "": return
	DirAccess.make_dir_recursive_absolute(output)
	RenderingServer.force_draw(false)
	get_viewport().get_texture().get_image().save_png(output.path_join(name + ".png"))

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--trial-output="): output = arg.trim_prefix("--trial-output=")
	Harness.prepare_window(get_window(), Vector2i(1920, 1080))
	Harness.arm_watchdog(self, 900.0)
	TelemetryState.enabled = false
	SaveLoad.autosave_enabled = false
	AudioServer.set_bus_mute(0, true)
	var menu: Control = load("res://scenes/main_menu.tscn").instantiate()
	get_tree().root.add_child.call_deferred(menu)
	await get_tree().process_frame
	get_tree().current_scene = menu
	for i in 30: await get_tree().process_frame
	await _stage("main_menu")
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
	MatchState.ruleset["opener_done"] = true
	Tutorial._on_overlay_skipped()
	DecisionState.enabled = false
	for layer in get_tree().root.find_children("*", "CanvasLayer", true, false):
		var script := layer.get_script() as Script
		if script != null and script.resource_path.ends_with("_intro.gd"):
			if layer.has_method("_on_begin"): layer.call("_on_begin")
			else: layer.queue_free()
	# Past the hidden 3D view's release delay.
	var settle := Time.get_ticks_msec()
	while Time.get_ticks_msec() - settle < 14000: await get_tree().process_frame
	await _stage("2d_map_settled")
	var camera: Camera2D = main.get_node("Camera2D")
	report.start_zoom = camera.zoom.x
	report.authored_resident_start = AuthoredBake._textures.size()
	_inventory("inventory_2d")
	# A typical playing zoom on the company, then back out to the opening view.
	var start_zoom := camera.zoom
	_weak = AuthoredBake._textures.values().map(func(t: Texture2D) -> WeakRef: return weakref(t))
	camera.set("_target_zoom", Vector2.ONE * 1.2); camera.zoom = Vector2.ONE * 1.2
	settle = Time.get_ticks_msec()
	while Time.get_ticks_msec() - settle < 5000: await get_tree().process_frame
	report.authored_resident_company_zoom = AuthoredBake._textures.size()
	await _stage("2d_company_zoom")
	_inventory("inventory_2d_company_zoom")
	camera.set("_target_zoom", start_zoom); camera.zoom = start_zoom
	settle = Time.get_ticks_msec()
	while Time.get_ticks_msec() - settle < 5000: await get_tree().process_frame
	await _stage("2d_back_to_start_zoom")
	var view: Control = main.find_child("EmpireView", true, false)
	var board: Control = view.find_child("Board", true, false)
	var fabric: Node = main.get_node("AuthoredFabricVisuals")
	report.repaints = {"near": fabric.get("_repainted").size(), "far": fabric.get("_repainted_far").size()}
	_shot(main, "2d_before")
	# A quick look at the 3D view: closed again inside the warm window, nothing is let go.
	view.call("toggle")
	settle = Time.get_ticks_msec()
	while Time.get_ticks_msec() - settle < 2000: await get_tree().process_frame
	view.call("toggle")
	await _stage("2d_after_quick_look")
	report.quick_look_kept = AuthoredBake._textures.size()
	# A longer stay: still warm at 1 s, released after the warm window.
	view.call("toggle")
	settle = Time.get_ticks_msec()
	while Time.get_ticks_msec() - settle < 1000: await get_tree().process_frame
	await _stage("3d_open_1s_warm")
	while Time.get_ticks_msec() - settle < 6500 or not bool(board.call("detail_ready")):
		await get_tree().process_frame
		if Time.get_ticks_msec() - settle > 60000: break
	await _stage("3d_open_after_release")
	report.released_state = {"authored_resident": AuthoredBake._textures.size(), "near_repaints": fabric.get("_repainted").size(),
		"far_repaints": fabric.get("_repainted_far").size(), "hill_released": main.get_node("HillVisuals").get("_texture_released")}
	_inventory("inventory_3d_released")
	# Back to the map: how long until the opening view is whole again.
	var back := Time.get_ticks_msec()
	view.call("toggle")
	var worst := 0.0
	var slow := 0
	var last := Time.get_ticks_usec()
	var hills: Node = main.get_node("HillVisuals")
	while (AuthoredBake._textures.size() < int(report.authored_resident_start) or bool(hills.get("_texture_released"))) and Time.get_ticks_msec() - back < 30000:
		await get_tree().process_frame
		var now := Time.get_ticks_usec(); var frame := (now - last) / 1000.0; last = now
		worst = maxf(worst, frame)
		if frame > 50.0: slow += 1
	report.restore_2d = {"ms": Time.get_ticks_msec() - back, "worst_frame_ms": snappedf(worst, 0.1), "frames_over_50ms": slow,
		"resident": AuthoredBake._textures.size(), "hill_texture_back": not bool(hills.get("_texture_released"))}
	print("[VRAM 2D] restore ", JSON.stringify(report.restore_2d))
	await _stage("2d_restored")
	for i in 30: await get_tree().process_frame
	_shot(main, "2d_after")
	# Zoomed in to the near tier: the full-size repaints come back.
	camera.set("_target_zoom", Vector2.ONE * 2.4); camera.zoom = Vector2.ONE * 2.4
	settle = Time.get_ticks_msec()
	while Time.get_ticks_msec() - settle < 4000: await get_tree().process_frame
	report.near_repaints_after_zoom = fabric.get("_repainted").size()
	print("[VRAM 2D] near repaints after zoom-in ", report.near_repaints_after_zoom, " of ", report.repaints.near)
	if output != "":
		DirAccess.make_dir_recursive_absolute(output)
		FileAccess.open(output.path_join("vram_2d_breakdown.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	get_tree().quit()
