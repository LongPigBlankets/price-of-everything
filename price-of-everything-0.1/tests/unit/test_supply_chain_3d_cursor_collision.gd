extends "res://tests/test_base.gd"
const FEATURE := "supply_chain_3d"
const Board := preload("res://scripts/supply_chain_3d/board.gd")
const Builder := preload("res://scripts/supply_chain_3d/world_builder.gd")

class FlatGround extends RefCounted:
	func height(_p: Vector2) -> float: return 30.0
	func gradient(_p: Vector2) -> Vector2: return Vector2.ZERO

func _fixture() -> Control:
	var board := Board.new()
	board.size = Vector2(1280, 720)
	add_child(board)
	board.set_process(false)
	var builder := Builder.new()
	builder.cursor_picking = true
	builder.streamed = true
	builder.lazy_assets = true
	builder.ground = FlatGround.new()
	builder.tiles = {"a": {"center": Vector2.ZERO, "type": "rural", "label": "A"},
		"b": {"center": Vector2(405, 240), "type": "rural", "label": "B"}}
	builder.configure_grade()
	var texture := ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGBA8))
	for tid in builder.tiles:
		var meshes := [builder._surface(tid, 120.0), builder._surface(tid, 60.0), builder._surface(tid, 30.0)]
		builder.terrain_cache[builder.terrain_key(tid)] = {"meshes": meshes, "textures": [texture, texture, texture]}
		board._world.add_child(builder.tile_node(tid))
	builder.prepare_company_pick_surface(board._world)
	board._builder = builder
	board._model = {"tiles": builder.tiles}
	board.restore_camera({"target": builder.point(Vector2.ZERO), "span": 700.0, "pitch": 0.8, "yaw": PI / 4.0})
	return board

func _active_tiles(builder: RefCounted) -> Array:
	var result := []
	for item in builder.terrain_lods:
		if item.has("collider") and item.collider.shape != null: result.append(str(item.tile))
	return result

func _building(board: Control, tile: String, position: Vector3, dimensions: Vector3) -> Dictionary:
	var root := Node3D.new()
	root.position = position
	board._world.add_child(root)
	var pair := {"key": "", "tile": tile, "root": root, "dimension": dimensions, "lit": false,
		"standing": {"iid": "test_building", "kind": "building", "tile": tile, "side": 80.0},
		"near": [], "medium": null, "far": null, "medium_allowed": false}
	board._builder.sprite_pairs.append(pair)
	board._builder.collision_revision += 1
	return pair

func _test_cursor_collision_residency_and_camera_independence() -> void:
	_check(Board.cursor_collision_rings() == 0 and Board.cursor_collision_rings(950.0) == 2,
		"3D cursor collision: 300 world units rounds down to the cursor tile, not a neighbouring ring")
	var board := _fixture()
	var builder: RefCounted = board._builder
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(_active_tiles(builder).is_empty(), "3D cursor collision: prepared terrain starts with no detailed physics")
	var screen: Vector2 = board.screen_point(builder.point(Vector2.ZERO))
	var hit: Dictionary = board.pick_at(screen, true)
	_check(not hit.is_empty() and hit.collider.get_meta("tile_id", "") == "a" and _active_tiles(builder) == ["a"],
		"3D cursor collision: first click immediately attaches and hits only the cursor tile")
	var item: Dictionary = builder.terrain_lods[0]
	var shape: Shape3D = item.collider.shape
	var mesh: Mesh = item.node.mesh
	var camera: Dictionary = board.capture_camera()
	camera.target = builder.point(builder.tiles.b.center)
	board.restore_camera(camera)
	var focus: String = board._camera_focus_tile()
	_check(focus == "b" and _active_tiles(builder) == ["a"],
		"3D cursor collision: the camera-centre preload query does not move physics residency")
	hit = board.pick_at(screen, true)
	_check(not hit.is_empty() and hit.collider.get_meta("tile_id", "") == "b" and _active_tiles(builder) == ["b"],
		"3D cursor collision: panning beneath a stationary cursor activates the new tile and detaches the old")
	_check(item.node.mesh == mesh and item.data.shapes[1] == shape,
		"3D cursor collision: detaching physics retains prepared meshes and collision resources")
	camera.target = builder.point(Vector2.ZERO)
	board.restore_camera(camera)
	board.pick_at(screen, true)
	_check(item.collider.shape == shape and _active_tiles(builder) == ["a"],
		"3D cursor collision: returning reuses the same prepared shape")
	hit = board.pick_at(board.screen_point(builder.point(Vector2(202.5, 120))), true)
	_check(not hit.is_empty() and _active_tiles(builder).size() == 1,
		"3D cursor collision: a click on the shared tile boundary still resolves with only one active tile")
	board._update_cursor_collision(Vector2(-1, -1))
	_check(_active_tiles(builder).is_empty() and builder.terrain_lods.size() == 2,
		"3D cursor collision: leaving the viewport detaches physics without evicting terrain")
	board.queue_free()
	await get_tree().process_frame

func _test_cursor_collision_mine_without_coarse_ground_hit() -> void:
	var board := _fixture()
	var builder: RefCounted = board._builder
	var rim := PackedVector2Array([Vector2(-50, -50), Vector2(50, -50), Vector2(50, 50), Vector2(-50, 50)])
	builder.pits.test_building = {"rim": rim, "area": Rect2(-50, -50, 100, 100), "pos": Vector2.ZERO,
		"side": 80.0, "height": 30.0, "sink": 80.0, "step": 8.0}
	var meshes: Array = []
	for item in builder.terrain_lods:
		for tier in 3: item.data.meshes[tier] = builder._surface(item.tile, [120.0, 60.0, 30.0][tier])
		meshes.append(item.data.meshes[0])
		builder.apply_tile_detail(item, 2)
	builder.continent_body.get_child(0).shape = builder.Geo.joined(meshes).create_trimesh_shape()
	var pair := _building(board, "a", Vector3(0, -50, 0), Vector3(80, 100, 80))
	board.restore_camera({"target": Vector3(0, 20, 0), "span": 240.0, "pitch": 1.35, "yaw": PI / 4.0})
	await get_tree().physics_frame
	await get_tree().physics_frame
	var screen: Vector2 = board.size * 0.5
	_check(board._cursor_surface_hit(screen).is_empty(), "3D cursor collision: mine fixture has an opening in the coarse terrain")
	var hit: Dictionary = board.pick_at(screen)
	_check(not hit.is_empty() and hit.collider.get_meta("standing", {}).get("iid", "") == "test_building"
		and _active_tiles(builder) == ["a"],
		"3D cursor collision: the mine remains selectable without a coarse ground hit")
	var tile_hit: Dictionary = board.pick_at(screen, true)
	_check(not tile_hit.is_empty() and tile_hit.collider.get_meta("tile_id", "") == "a",
		"3D cursor collision: a tile-only click through the mine still targets its tile")
	builder.continent_body.get_child(0).shape = builder._coarse_pick_shape(builder.Geo.joined(meshes))
	var far: Dictionary = board.capture_camera()
	far.span = board.Rig.MAX_SIZE
	board.restore_camera(far)
	hit = board.pick_at(board.screen_point(Vector3(0, 30, 0)))
	_check(not hit.is_empty() and hit.collider == builder.continent_body and _active_tiles(builder).is_empty()
		and pair.body.get_child(0).shape == null,
		"3D cursor collision: the shared locator covers a far-zoom mine with no active mine collider")
	board.queue_free()
	await get_tree().process_frame

func _test_cursor_collision_coarse_and_fine_boundary_disagree() -> void:
	var board := _fixture()
	var builder: RefCounted = board._builder
	# Deliberately exaggerated relief discrepancy moves the fine ray across a hex
	# edge while the shared locator still returns a. The visible mesh must win.
	for item in builder.terrain_lods:
		var arrays: Array = item.data.meshes[1].surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i in vertices.size(): vertices[i] += Vector3.UP * 400.0
		arrays[Mesh.ARRAY_VERTEX] = vertices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		item.data.meshes[1] = mesh
		builder.apply_tile_detail(item, 1)
	board.restore_camera({"target": builder.point(Vector2.ZERO), "span": 700.0, "pitch": 0.8, "yaw": atan2(405.0, 240.0)})
	await get_tree().physics_frame
	await get_tree().physics_frame
	var screen: Vector2 = board.size * 0.5
	var coarse: Dictionary = board._cursor_surface_hit(screen)
	_check(not coarse.is_empty() and builder.tile_at(coarse.position) == "a", "3D cursor collision: relief fixture seeds the coarse tile")
	var hit: Dictionary = board.pick_at(screen, true)
	_check(not hit.is_empty() and hit.collider.get_meta("tile_id", "") == "b" and _active_tiles(builder) == ["b"],
		"3D cursor collision: fine relief corrects the cursor tile without retaining neighbouring colliders")
	board.queue_free()
	await get_tree().process_frame

func _test_cursor_collision_overhanging_building_and_far_zoom() -> void:
	var board := _fixture()
	var builder: RefCounted = board._builder
	# Looking away from tile b projects this tall building's roof across the boundary.
	var pair := _building(board, "b", builder.point(builder.tiles.b.center), Vector3(80, 300, 80))
	var roof: Vector3 = pair.root.position + Vector3.UP * 250.0
	board.restore_camera({"target": roof, "span": 700.0, "pitch": 0.8, "yaw": atan2(405.0, 240.0)})
	await get_tree().physics_frame
	await get_tree().physics_frame
	var screen: Vector2 = board.screen_point(roof)
	var coarse: Dictionary = board._cursor_surface_hit(screen)
	_check(not coarse.is_empty() and builder.tile_at(coarse.position) == "a",
		"3D cursor collision: roof fixture projects over the neighbouring ground tile")
	var hit: Dictionary = board.pick_at(screen)
	_check(not hit.is_empty() and hit.collider.get_meta("standing", {}).get("iid", "") == "test_building"
		and _active_tiles(builder) == ["b"],
		"3D cursor collision: an overhanging roof selects its exact building and retains only that tile")
	board._update_cursor_collision(Vector2(-1, -1))
	_check(pair.body.get_child(0).shape == null, "3D cursor collision: building physics detaches with its tile")
	var camera: Dictionary = board.capture_camera()
	camera.target = builder.point(builder.tiles.b.center)
	camera.span = board.Rig.MAX_SIZE
	board.restore_camera(camera)
	hit = board.pick_at(board.screen_point(camera.target))
	_check(not hit.is_empty() and not hit.collider.has_meta("standing") and _active_tiles(builder).is_empty()
		and pair.body.get_child(0).shape == null,
		"3D cursor collision: far zoom keeps only the shared surface and tile selection")
	board.queue_free()
	await get_tree().process_frame
