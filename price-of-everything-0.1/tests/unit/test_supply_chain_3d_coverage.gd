extends "res://tests/test_base.gd"
const FEATURE := "supply_chain_3d"
const Board := preload("res://scripts/supply_chain_3d/board.gd")
const Builder := preload("res://scripts/supply_chain_3d/world_builder.gd")
const Relief := preload("res://scripts/supply_chain_3d/relief.gd")

class FlatGround extends RefCounted:
	func height(_p: Vector2) -> float: return 30.0
	func gradient(_p: Vector2) -> Vector2: return Vector2.ZERO

class InteriorSummit extends FlatGround:
	func node(i: int, j: int) -> float: return 132.0 if i == 12 and j == 8 else 30.0

class CentredTerrainBoard extends "res://scripts/supply_chain_3d/board.gd":
	var centre_hit := Vector3.ZERO
	func pick_at(_screen: Vector2, _tiles_only: bool = false) -> Dictionary:
		return {"position": centre_hit}

func _test_medium_covers_every_visible_tile() -> void:
	var board := Board.new()
	var wanted := []
	for i in 45: wanted.append({"tile": str(i), "visible": i < 37})
	board._detail = 1
	var plan: Dictionary = board._fine_detail_plan(wanted)
	_check(plan.size() == 37 and plan.values().all(func(tier: int) -> bool: return tier == 1),
		"3D medium coverage: all 37 visible tiles use medium instead of only the first 24")
	_check(not plan.has("37"), "3D medium coverage: offscreen buffer does not eagerly acquire fine terrain")
	board._detail = 2
	for item in wanted: item.near = int(item.tile) >= 10
	plan = board._fine_detail_plan(wanted)
	_check(plan.size() == 45 and plan.values().count(2) == 35 and plan.values().count(1) == 10,
		"3D near coverage: the full radius gets near detail, including offscreen tiles; visible tiles outside use medium")
	board._detail = 0
	_check(board._fine_detail_plan(wanted).is_empty(), "3D widest local coverage: every tile uses the same continent terrain tier")
	board.free()

func _catalog_radius(center: String) -> Dictionary:
	# Independent of renderer coordinates: walk the gameplay neighbour graph.
	var ring := {center: true}
	var front := [center]
	for step in 4:
		var next := []
		for tid in front:
			for neighbour in Catalog.tile_neighbours(tid):
				if ring.has(neighbour): continue
				ring[neighbour] = true
				next.append(neighbour)
		front = next
	return ring

func _test_near_camera_radius_tracks_hexes_and_map_edges() -> void:
	var board := CentredTerrainBoard.new()
	board.size = Vector2(1920, 1080)
	add_child(board)
	board.set_process(false)
	var builder := Builder.new()
	builder.streamed = true
	builder.ground = FlatGround.new()
	builder.origin = Vector2(125, -80)
	for q in 30:
		for r in 20:
			builder.tiles["tile_%d_%d" % [q + 1, r + 1]] = {"center": Vector2(q * 405, (r + posmod(q, 2) * 0.5) * 480), "type": "rural"}
	board._builder = builder
	for tid in ["tile_10_10", "tile_11_10", "tile_1_1"]:
		board.centre_hit = builder.point(builder.tiles[tid].center)
		# Deliberately different pivot: the centre ray's terrain hit is authoritative.
		board.restore_camera({"target": board.centre_hit + Vector3(500, 100, 0), "span": 240.0, "pitch": 0.5, "yaw": PI * 0.75})
		var wanted: Array = board._wanted_detail_tiles()
		var near := wanted.filter(func(item: Dictionary) -> bool: return item.near)
		var expected := _catalog_radius(tid)
		var plan: Dictionary = board._fine_detail_plan(wanted)
		_check(board._camera_focus_tile() == tid and near.size() == expected.size()
			and near.all(func(item: Dictionary) -> bool: return expected.has(item.tile) and plan[item.tile] == 2),
			"3D near radius: centre hit %s loads its exact four hex rings across staggered columns/map edges" % tid)
		_check(near.any(func(item: Dictionary) -> bool: return not item.visible)
			and near.all(func(item: Dictionary) -> bool: return board._nearby_tiles.has(item.tile)),
			"3D near radius: offscreen ring tiles remain loaded and protected from pressure eviction")
		var first_offscreen := false
		var prioritised := true
		for item in wanted:
			if not item.visible: first_offscreen = true
			elif first_offscreen: prioritised = false
		_check(prioritised, "3D near radius: visible requests precede offscreen ring loading")
	_check(_catalog_radius("tile_10_10").size() == 61, "3D near radius: interior working set is the centre plus 60 neighbours")
	board.restore_camera({"target": board.centre_hit, "span": 1080.0, "pitch": 0.7, "yaw": PI / 4.0})
	var medium: Array = board._wanted_detail_tiles()
	_check(not medium.any(func(item: Dictionary) -> bool: return item.near), "3D near radius: medium zoom retains viewport-based loading")
	board.queue_free()
	await get_tree().process_frame

func _test_bounds_include_interior_summits_and_scenery() -> void:
	var builder := Builder.new()
	builder.ground = InteriorSummit.new()
	builder.tiles = {"tile": {"center": Vector2.ZERO, "type": "rural"}}
	var hull := builder.tile_view_hull("tile")
	var bounds := AABB(hull[1], Vector3.ZERO)
	for p in hull: bounds = bounds.expand(p)
	_check(hull.size() == 9 and bounds.has_point(Vector3(144, Relief.height(132), 96)),
		"3D visibility bounds: lattice extrema include an interior summit absent from centre/corners")
	_check(bounds.position.y <= -150.0, "3D visibility bounds: continent cutaway edges remain inside the saved hull")
	builder.view_hulls.clear()
	builder._visibility_standing.tile = [{"iid": "tower", "tile": "tile", "kind": "house", "side": 100.0}]
	builder.standing_frames.tower = {"key": "", "position": Vector3(0, 30, 0), "dimension": Vector3(60, 600, 60)}
	hull = builder.tile_view_hull("tile")
	bounds = AABB(hull[1], Vector3.ZERO)
	for p in hull: bounds = bounds.expand(p)
	_check(bounds.has_point(Vector3(0, 630, 0)), "3D visibility bounds: tall buildings expand the tile's saved vertical extent")
	var saved := builder.visibility_bake().duplicate(true)
	saved.version = 1
	_check(not builder._restore_visibility(saved), "3D visibility bounds: centre/corner-only metadata is upgraded without changing terrain keys")

func _test_shallow_view_does_not_drop_visible_tiles_at_node_limit() -> void:
	var board := Board.new()
	board.size = Vector2(1920, 1080)
	add_child(board)
	board.set_process(false)
	var builder := Builder.new()
	builder.streamed = true
	builder.ground = FlatGround.new()
	for q in 30:
		for r in 20:
			builder.tiles["%d_%d" % [q, r]] = {"center": Vector2(q * 405, (r + posmod(q, 2) * 0.5) * 480), "type": "rural"}
	board._builder = builder
	board.restore_camera({"target": Vector3(6000, 30, 4500), "span": 1080.0 / 0.34, "pitch": 0.30, "yaw": PI / 4.0})
	var wanted: Array = board._wanted_detail_tiles()
	var visible := wanted.filter(func(item: Dictionary) -> bool: return item.visible).size()
	_check(visible > Builder.BASE_RESIDENT_TILES and wanted.size() == visible,
		"3D visibility coverage: shallow wide view retains every visible tile and drops only offscreen buffer")
	board.queue_free()
	await get_tree().process_frame

func _test_tower_roof_visible_beyond_ground_footprint() -> void:
	var board := Board.new()
	board.size = Vector2(1280, 720)
	add_child(board)
	board.set_process(false)
	var builder := Builder.new()
	builder.ground = FlatGround.new()
	builder.tiles = {"tower_tile": {"center": Vector2.ZERO, "type": "urban"}}
	builder._visibility_standing.tower_tile = [{"iid": "tower", "tile": "tower_tile", "kind": "house", "side": 100.0}]
	builder.standing_frames.tower = {"key": "", "position": Vector3(0, 30, 0), "dimension": Vector3(60, 600, 60)}
	board._builder = builder
	var roof := Vector3(0, 630, 0)
	var target := roof - Vector3(0, 0, 1) * (360.0 - 8.0) / sin(0.30)
	board.restore_camera({"target": target, "span": 720.0, "pitch": 0.30, "yaw": 0.0})
	var wanted: Array = board._wanted_detail_tiles()
	_check(board.screen_point(Vector3(0, 30, 0)).y > board.size.y and board.screen_point(roof).y < board.size.y
		and wanted.any(func(item: Dictionary) -> bool: return item.tile == "tower_tile" and item.visible),
		"3D visibility coverage: a roof at the bottom edge loads its tile even when its foot is offscreen")
	board.queue_free()
	await get_tree().process_frame

func _test_bounds_include_sprite_angle_displacement() -> void:
	var dimension := Vector3(40, 600, 40)
	var bounds := Builder._sprite_view_bounds(Vector3.ZERO, dimension)
	var corner := dimension * 0.5
	var tilted := Basis(Vector3.UP, PI / 16.0) * Basis(Vector3.RIGHT, (1.35 - 0.30) / 8.0) * corner
	_check(bounds.has_point(tilted), "3D visibility bounds: angle-snapped tall sprites remain enclosed between baked views")
