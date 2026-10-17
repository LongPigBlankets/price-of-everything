extends "res://tools/supply_chain_3d/capture.gd"
## What one building change costs the open company 3D view.
## AGENT_GODOT_WINDOW=1 godot --path . res://tools/supply_chain_3d/trials/company_rebuild_profile.tscn -- \
##   --continent-review --no-background-continent --no-telemetry --bake-cache-directory=<new dir>
var map: Node

func _place(building_id: String, tid: String) -> void:
	var iid := BuildingState.add_building(building_id, "", tid)
	map.building_placed.emit(tid, building_id, "", iid, map.terrain_layer.id_to_coord(tid))

func _step(board: Control, name: String, building_id: String, tid: String) -> void:
	var before: Dictionary = board.load_profile
	var started := Time.get_ticks_msec()
	var worst := 0.0
	var slow: Array = []
	var place_started := Time.get_ticks_usec()
	_place(building_id, tid)
	slow.append(["place_call", snappedf((Time.get_ticks_usec() - place_started) / 1000.0, 0.1)])
	var last := Time.get_ticks_usec()
	while board.load_profile == before or board._building or board._streaming or not board.detail_ready():
		await get_tree().process_frame
		var now := Time.get_ticks_usec(); worst = maxf(worst, (now - last) / 1000.0)
		if (now - last) / 1000.0 > 150.0: slow.append([snappedf((now - started * 1000) / 1000.0, 1), snappedf((now - last) / 1000.0, 1)])
		last = now
		if Time.get_ticks_msec() - started > 120000: break
	var p: Dictionary = board.load_profile
	var summary := {"step": name, "tile": tid, "wall_ms": Time.get_ticks_msec() - started, "worst_frame_ms": snappedf(worst, 0.1), "slow_frames": slow}
	for key in ["model_ms", "layout_solve_ms", "road_frontage_ms", "keys_ms", "scenery_ms", "continent_ms", "infrastructure_ms", "standing_ms", "total_ms", "cache_hits", "cache_misses", "cache_writes"]:
		if p.has(key): summary[key] = p[key]
	if p.has("transport"):
		summary.transport_ms = p.transport.get("total_ms", 0.0); summary.transport_hit = p.transport.get("cache_hit", false)
		for key in ["alignment_ms", "chains_reused", "chains_solved"]:
			if p.transport.has(key): summary[key] = p.transport[key]
	summary.profile = p.duplicate(true); summary.profile.erase("transport")
	print("[COMPANY REBUILD] ", JSON.stringify(summary))

func _continent_review(board: Control, _home: Dictionary) -> void:
	for node in get_tree().root.find_children("*", "", true, false):
		var script := node.get_script() as Script
		if script != null and script.resource_path.ends_with("/world_map.gd"): map = node; break
	for i in 30: await get_tree().process_frame
	var company: Array = board._model.tiles.keys()
	company.sort()
	var fresh := ""
	for tid in company:
		for neighbour in Catalog.tile_neighbours(str(tid)):
			if not board._model.tiles.has(neighbour) and Catalog.tile_type(neighbour) in ["rural", "hill"]: fresh = neighbour; break
		if fresh != "": break
	print("[COMPANY REBUILD] company=", company, " new tile=", fresh)
	await _idle(board)
	await _step(board, "A_existing_tile", "b_002", str(company[0]))
	await _idle(board)
	await _step(board, "B_new_tile", "b_024", fresh)
	_verify_alignment(board)
	await _idle(board)
	await _step(board, "C_same_new_tile", "b_025", fresh)

## A player between builds: the view idles until the alignment memo is seeded.
func _idle(board: Control) -> void:
	var started := Time.get_ticks_msec()
	var worst := 0.0
	var last := Time.get_ticks_usec()
	while not board._builder.alignment_seeded() and Time.get_ticks_msec() - started < 60000:
		await get_tree().process_frame
		var now := Time.get_ticks_usec(); worst = maxf(worst, (now - last) / 1000.0); last = now
	print("[COMPANY REBUILD] idle seeding ", JSON.stringify({"ms": Time.get_ticks_msec() - started, "worst_frame_ms": snappedf(worst, 0.1), "seeded": board._builder.alignment_seeded()}))

## The memo must reproduce a fresh solve exactly.
func _verify_alignment(board: Control) -> void:
	var b: RefCounted = board._builder
	var input: Dictionary = b.alignment_input
	var model := {"roads": input.roads, "tiles": input.tiles, "standing": input.standing, "depots": input.depots}
	var started := Time.get_ticks_usec()
	var fresh: Array = preload("res://scripts/supply_chain_3d/road_alignment.gd").new().configure(model, b.formation_height, b.railway_level, b.open_water)
	var fresh_ms := (Time.get_ticks_usec() - started) / 1000.0
	var memo: RefCounted = preload("res://scripts/supply_chain_3d/road_alignment_memo.gd").new()
	b._prepare_alignment_memo(memo)
	started = Time.get_ticks_usec()
	var again: Array = memo.configure(model, b.formation_height, b.railway_level, b.open_water)
	print("[COMPANY REBUILD] alignment memo ", JSON.stringify({"identical": var_to_str(fresh) == var_to_str(again), "segments": fresh.size(),
		"fresh_ms": snappedf(fresh_ms, 0.1), "memo_ms": snappedf((Time.get_ticks_usec() - started) / 1000.0, 0.1), "hits": memo.memo_hits, "misses": memo.memo_misses}))
