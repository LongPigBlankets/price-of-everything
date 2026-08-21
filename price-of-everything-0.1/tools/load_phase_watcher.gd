extends Node
## Measurement-only companion to load_freeze_check: survives the scene change and
## logs, once per second, how far the new-game build has progressed (buildings
## placed, road edges up, frames elapsed) so wall-clock time can be attributed to
## phases. Prints avg frame ms per window — a high number during the placement
## stretch means the per-frame redraw is the cost, not the placement itself.
var _t0 := 0
var _last_report := 0
var _frames := 0
var _frames_at_report := 0
var _done := false
func _ready() -> void:
	_t0 = Time.get_ticks_msec()
	_last_report = _t0
func _process(_d: float) -> void:
	_frames += 1
	var now := Time.get_ticks_msec()
	if now - _last_report >= 1000:
		var window_frames := _frames - _frames_at_report
		var avg_ms := float(now - _last_report) / maxf(1.0, float(window_frames))
		var n_buildings := MatchState.buildings.size()
		var n_edges := RoadNetwork.instance().edges.size()
		print("PHASE t+%6d ms  frames=%5d  (win %3d f, avg %5.1f ms/f)  buildings=%4d  road_edges=%4d" %
			[now - _t0, _frames, window_frames, avg_ms, n_buildings, n_edges])
		_last_report = now
		_frames_at_report = _frames
	var cur := get_tree().current_scene
	if not _done and cur != null and cur.get("build_complete") != null and bool(cur.get("build_complete")):
		_done = true
		print("PHASE LOAD done at t+%d ms (%d frames)" % [now - _t0, _frames])
		# OPEN_GRAPH=1: simulate the user opening the Goods Graph right after the load and
		# measure the open cost the way they'd feel it — the layout build, the icon-cache
		# populate, and the wall time of the first few rendered frames (GPU upload lands here).
		if OS.get_environment("OPEN_GRAPH") != "":
			await _measure_graph_open(cur)
		# LAYOUT_DUMP=<path>: write every placement's geometry (sorted by instance id)
		# so two runs can be diffed byte-for-byte — the "layout identical" proof for
		# any placement-path refactor. LAYOUT_SHOT=<path>: hide the loading screen,
		# let the world present, and save a PNG of the revealed map.
		var dump_path := OS.get_environment("LAYOUT_DUMP")
		if dump_path != "":
			_dump_layout(cur, dump_path)
		var shot_path := OS.get_environment("LAYOUT_SHOT")
		if shot_path != "":
			for c in get_tree().root.get_children():
				if c is LoadingScreen:
					c.visible = false
			# LAYOUT_SHOT_FRAMES raises the settle time before the grab. The default is
			# enough for a finished world; raise it when comparing against a path that is
			# still catching up on paced background work (e.g. the fabric's evicted-tile
			# repair, one tile a frame).
			var settle := 6
			if OS.get_environment("LAYOUT_SHOT_FRAMES") != "":
				settle = int(OS.get_environment("LAYOUT_SHOT_FRAMES"))
			for _i in settle:
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(shot_path)
			print("PHASE layout shot -> %s" % shot_path)
		# Attribute the post-placement tail: how many sim buildings never got a drawn
		# footprint (forests are by design; the rest are failed/crowded placements that
		# _place_pending_start_buildings re-attempts one per frame, every load).
		var bv: Node = cur.get("building_visuals")
		if bv != null and bv.has_method("has_placement"):
			var missing_by_bid: Dictionary = {}
			var missing := 0
			for iid in MatchState.buildings:
				if not bv.has_placement(str(iid)):
					missing += 1
					var bid := str(MatchState.buildings[iid].get("building_id", ""))
					missing_by_bid[bid] = int(missing_by_bid.get(bid, 0)) + 1
			print("PHASE placements missing for %d/%d buildings, by id: %s" %
				[missing, MatchState.buildings.size(), missing_by_bid])
		get_tree().quit(0)

const _GoodsFlowGraph := preload("res://scripts/goods_flow_graph.gd")
const _GoodIcons := preload("res://scripts/good_icons.gd")
func _measure_graph_open(cur: Node) -> void:
	var t_layout := Time.get_ticks_usec()
	_GoodsFlowGraph.build()
	print("OPEN graph layout build(): %.1f ms (cached=fast)" % [float(Time.get_ticks_usec() - t_layout) / 1000.0])
	var t_icons := Time.get_ticks_usec()
	_GoodIcons.warm(Catalog.all_goods())
	print("OPEN medium-icon populate: %.1f ms (warmed=fast)" % [float(Time.get_ticks_usec() - t_icons) / 1000.0])
	# Actually open the view and time the first rendered frames (GPU upload cost lands here).
	var view: Node = cur.get("goods_graph_view")
	if view == null:
		print("OPEN no goods_graph_view found"); return
	view.set("visible", true)
	var per_frame := ""
	for i in 8:
		var f0 := Time.get_ticks_msec()
		await get_tree().process_frame
		per_frame += "%d " % (Time.get_ticks_msec() - f0)
	print("OPEN frames after show: [ %s] ms (per-frame; first = GPU first-present)" % per_frame)

func _dump_layout(cur: Node, path: String) -> void:
	var bv: Node = cur.get("building_visuals")
	if bv == null:
		return
	var rows: Array = []
	for p in (bv.get("_placements") as Array):
		var d: Dictionary = p
		var verts: Array = []
		for v in (d.verts as PackedVector2Array):
			verts.append([(v as Vector2).x, (v as Vector2).y])
		rows.append({"iid": str(d.instance_id), "bid": str(d.building_id),
			"tile": str(d.tile_id), "verts": verts})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.iid) < str(b.iid))
	var subs: Array = []
	for sc in (bv.get("_subcomponents") as Array):
		var sd: Dictionary = sc
		var sverts: Array = []
		for v in (sd.get("verts", PackedVector2Array()) as PackedVector2Array):
			sverts.append([(v as Vector2).x, (v as Vector2).y])
		subs.append({"kind": str(sd.get("kind", "")), "tile": str(sd.get("tile_id", "")), "verts": sverts})
	subs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.tile) + str(a.kind) + str(a.verts) < str(b.tile) + str(b.kind) + str(b.verts))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"placements": rows, "subcomponents": subs}, "", true))
		f.close()
		print("PHASE layout dump: %d placements, %d subcomponents -> %s" % [rows.size(), subs.size(), path])
