extends "res://tools/supply_chain_3d/review_medium_range.gd"
## Matched production captures; no forced LODs or artwork changes.

func _continent_review(board: Control, home: Dictionary) -> void:
	output = "res://../outputs/supply-chain-3d/medium-near-examples/"
	DirAccess.make_dir_recursive_absolute(output)
	await board.set_all_tiles(true, false)
	while not board.detail_ready():
		RenderingServer.force_draw(false)
		await get_tree().process_frame
	board.set_process(false)
	board._labels.hide()
	board.animate_goods = false
	var builder: RefCounted = board._builder
	var coast: Vector3 = home.target
	for tile in builder.tiles.values():
		if "Stoneshore Coast" in str(tile.label):
			coast = builder.point(tile.center)
			break
	var town := {}
	var distance := INF
	for standing in board._model.standing:
		if str(standing.kind) != "house" or not bool(standing.get("tall", false)): continue
		var frame: Dictionary = builder.standing_frame(standing)
		var d: float = frame.position.distance_squared_to(coast)
		if d < distance:
			distance = d
			town = {"position": frame.position + Vector3.UP * float(frame.dimension.y) * 0.35, "key": frame.key, "tile": standing.tile}
	assert(not town.is_empty(), "Town capture needs a decorative tower")
	var industry := {}
	for standing in board._model.standing:
		var frame: Dictionary = builder.standing_frame(standing)
		if str(standing.tile) == "tile_9_9" and str(standing.kind) == "building":
			industry = {"position": frame.position + Vector3.UP * float(frame.dimension.y) * 0.30, "key": frame.key, "tile": standing.tile}
			break
	assert(not industry.is_empty(), "Industrial capture needs a starting production building")
	for example in [{"name": "town", "focus": town}, {"name": "industry", "focus": industry}]:
		if "--industry-only" in OS.get_cmdline_user_args() and example.name != "industry": continue
		print("[NEAR EXAMPLE] ", example)
		# Start wide, then move inward so the close-medium sample uses normal
		# zoom-in hysteresis, rather than inheriting the previous near tier.
		board.fit_view()
		var state: Dictionary = board.capture_camera()
		state.target = example.focus.position
		state.yaw = PI * 1.25 if example.name == "industry" else PI / 4.0
		state.pitch = 0.6154797
		for sample in [{"name": "medium", "ppu": 1.25}, {"name": "medium_close", "ppu": 1.70}, {"name": "near", "ppu": 2.60}, {"name": "near_max", "ppu": board.size.y / board.Rig.MIN_SIZE}]:
			state.span = board.size.y / float(sample.ppu)
			await _view(board, state, str(example.name) + "_" + str(sample.name))
	_save_report()
