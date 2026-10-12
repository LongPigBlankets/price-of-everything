extends "res://tools/railway_assets/network_capture.gd"
func _continent_review(board: Control, home: Dictionary) -> void:
	await super._continent_review(board,home)
	var builder: RefCounted = board.get("_builder")
	print("[TRANSPORT CAPTURE] depots=",builder.depots," bridges=",builder.road_grade.bridges.size()," busy roads=",builder.rail_urban.busy.size())
	var captures: Array = []
	for depot in builder.depots: captures.append({"name":"depot_"+str(depot.city).to_snake_case(),"p":depot.pos,"span":440.0})
	if not builder.road_grade.bridges.is_empty(): captures.append({"name":"road_over_rail","p":builder.road_grade.bridges[0].p,"span":550.0})
	for entry in captures:
		var state: Dictionary = board.call("capture_camera")
		state.target=builder.point(entry.p); state.span=entry.span
		board.call("restore_camera",state)
		while not board.call("detail_ready"): await get_tree().process_frame
		await board.call("_stream_visible")
		for i in 20: await get_tree().process_frame
		await _shot(entry.name)
