extends "res://tools/supply_chain_3d/review_near_radius.gd"
## Disposable measurement run. Does not change bakes, art or streaming behaviour.
const ProfileBuilder := preload("res://tools/supply_chain_3d/closest_profile_builder.gd")
const ProfileBoard := preload("res://tools/supply_chain_3d/pan_profile_board.gd")
const ProfileCache := preload("res://tools/supply_chain_3d/pan_profile_cache.gd")
var profiles: Array = []
var frames: Array = []
var sampling := false
var last_tick := 0

func _rebind(object: Object, script: Script) -> void:
	var state := {}
	for property in object.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			state[str(property.name)] = object.get(str(property.name))
	object.set_script(script)
	for key in state: object.set(key, state[key])

func _frame() -> void:
	if not sampling: return
	var now := Time.get_ticks_usec()
	frames.append((now - last_tick) / 1000.0)
	last_tick = now

func _stats(samples: Array) -> Dictionary:
	if samples.is_empty(): return {"count": 0, "total_ms": 0.0, "max_ms": 0.0}
	var sorted := samples.duplicate()
	sorted.sort()
	var total := 0.0
	for value in samples: total += float(value)
	return {"count": samples.size(), "total_ms": total, "max_ms": sorted[-1],
		"p95_ms": sorted[mini(sorted.size() - 1, floori(sorted.size() * 0.95))]}

func _stage_stats(stages: Dictionary) -> Dictionary:
	var result := {}
	for key in stages: result[key] = _stats(stages[key])
	return result

func _continent_review(board: Control, home: Dictionary) -> void:
	await board.set_all_tiles(true, false)
	while not board.detail_ready():
		RenderingServer.force_draw(false)
		await get_tree().process_frame
	board.set_process(false)
	_rebind(board._builder, ProfileBuilder)
	_rebind(board._builder.bake_cache, ProfileCache)
	_rebind(board, ProfileBoard)
	board.set_process(false)
	get_tree().process_frame.connect(_frame)
	await super._continent_review(board, home)

func _view(board: Control, state: Dictionary, name: String) -> void:
	var builder: RefCounted = board._builder
	builder.probe.clear()
	builder.bake_cache.probe.clear()
	builder.bake_cache.compressed_bytes = 0
	board.probe.clear()
	var before: Dictionary = builder.local_tiles.duplicate()
	frames.clear()
	last_tick = Time.get_ticks_usec()
	sampling = true
	await super._view(board, state, name)
	sampling = false
	var added_visible := []
	var added_offscreen := []
	for item in board._wanted_detail_tiles():
		if not before.has(item.tile):
			if item.visible: added_visible.append(item.tile)
			else: added_offscreen.append(item.tile)
	var record := {"view": name, "builder": _stage_stats(builder.probe),
		"board": _stage_stats(board.probe), "load": _stage_stats(builder.bake_cache.probe),
		"read_MiB": builder.bake_cache.compressed_bytes / 1048576.0,
		"streaming_frames": _stats(frames), "added_visible": added_visible,
		"added_offscreen": added_offscreen, "can_prefetch": builder.resource_cache.can_prefetch(),
		"prefetch_candidates": board._prefetch_tiles.size()}
	profiles.append(record)
	FileAccess.open(output.path_join("profile.json"), FileAccess.WRITE).store_string(JSON.stringify(profiles, "\t"))
	print("[CLOSEST PROFILE] ", name, " ", JSON.stringify(record))

func _draw_view(board: Control, name: String) -> void:
	if sampling: frames.append((Time.get_ticks_usec() - last_tick) / 1000.0)
	sampling = false
	await super._draw_view(board, name)
