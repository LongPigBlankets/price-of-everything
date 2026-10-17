extends "res://tools/supply_chain_3d/capture.gd"
func _open_supply_view(view: Control) -> void:
	await view.call("prepare")
	var board: Control = view.find_child("Board",true,false)
	while board.get("_building") or not board.get("_model").has("tiles"): await get_tree().process_frame
	Harness.prepare_window(get_window(),Vector2i(1920,1080))
	view.call("toggle")
	while board.get("_building"): await get_tree().process_frame
	board.call("fit_view")
	for i in 10: await get_tree().process_frame
func _continent_review(board: Control, _home: Dictionary) -> void:
	await board.call("set_all_tiles",true,false)
	while board.get("_building"): await get_tree().process_frame
	var model: Dictionary = board.get("_model")
	var report: Dictionary = model.rail_network
	print("[RAIL CAPTURE] tiles=",report.tiles.size()," edges=",report.global_edges," drops=",report.drops.size())
	var home: Dictionary = board.call("capture_camera")
	await _shot("rail_network_overview")
	var builder: RefCounted = board.get("_builder")
	for kind in ["urban","hill"]:
		var chosen := ""; var best := -INF
		for tid in report.tiles:
			var tile: Dictionary = report.tiles[tid]
			if tile.type != kind: continue
			var score: float = float(tile.buildings) if kind == "urban" else -tile.center.distance_to(Vector2(6500,5000))
			if score > best: chosen = tid; best = score
		var state := home.duplicate()
		state.target = builder.point(report.anchors[chosen]); state.span = 1000.0
		board.call("restore_camera",state)
		while not board.call("detail_ready"): await get_tree().process_frame
		await board.call("_stream_visible")
		for i in 20: await get_tree().process_frame
		print("[RAIL CAPTURE] ",kind," ",chosen)
		await _shot("rail_network_"+kind)
