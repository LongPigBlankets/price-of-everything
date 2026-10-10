extends "res://tests/test_base.gd"
const FEATURE := "supply_chain_3d"
const Rig := preload("res://scripts/supply_chain_3d/orbit_camera.gd")
const Detail := preload("res://scripts/supply_chain_3d/detail.gd")
const Assets := preload("res://scripts/supply_chain_3d/assets.gd")
const Builder := preload("res://scripts/supply_chain_3d/world_builder.gd")
const RoadSurface := preload("res://scripts/supply_chain_3d/road_surface.gd")
const Legacy := preload("res://scripts/empire_board.gd")
const WaterArt := preload("res://scripts/supply_chain_3d/water_art.gd")

class SlopedGround extends RefCounted:
	func height(p: Vector2) -> float: return 30.0 + p.x * 0.08 + p.y * 0.03
	func gradient(_p: Vector2) -> Vector2: return Vector2(0.08, 0.03)

func _test_orbit_limits_and_pan() -> void:
	var rig := Rig.new()
	rig.orbit(Vector2(100000, 100000))
	_check(rig.pitch == Rig.MAX_PITCH and absf(rig.yaw) <= PI, "3D orbit: yaw wraps and pitch cannot flip under terrain")
	rig.orbit(Vector2(0, -100000))
	_check(rig.pitch == Rig.MIN_PITCH, "3D orbit: low angle remains above the ground")
	rig.yaw = PI / 2
	rig.pan(Vector2(100, 0), 1000)
	_check(absf(rig.target.x) < 0.01 and rig.target.z > 0, "3D pan follows the rotated camera's horizontal axis")
	var state := rig.capture()
	var copy := Rig.new()
	copy.restore(state)
	_check(copy.capture() == state, "3D camera state survives a round trip")

func _test_exported_3d_meshes() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Assets.DIRECTORY + "manifest.json"))
	var all_valid := true
	for key in manifest:
		var mesh := Assets.mesh_for(str(key))
		all_valid = all_valid and mesh != null and mesh.get_surface_count() == 1
		if mesh != null:
			var box := mesh.get_aabb()
			all_valid = all_valid and box.size.y > 0 and absf(box.position.y) < 0.01
	_check(manifest.size() >= 50 and all_valid, "3D assets: all exported levels load as one grounded solid mesh")
	var factory := Assets.mesh_for("industrial_factory_lvl3")
	var arrays := factory.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var edge_bits: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	var print_data_valid := uv.size() == vertices.size() and edge_bits.size() == vertices.size()
	var suppressed_diagonal := false
	for i in uv.size():
		var bary := Vector3(uv[i].x, 1.0 - uv[i].y, uv[i].y - uv[i].x)
		print_data_valid = print_data_valid and bary.x >= -0.001 and bary.y >= -0.001 and bary.z >= -0.001
		if i < edge_bits.size():
			var bits := edge_bits[i].x
			print_data_valid = print_data_valid and bits >= -0.001 and bits <= 7.001 and absf(bits - roundf(bits)) < 0.001
			suppressed_diagonal = suppressed_diagonal or bits < 7
	_check(print_data_valid and suppressed_diagonal, "3D print: imported barycentrics and edge masks preserve creases without inking mesh diagonals")
	_check(factory.surface_get_material(0) is ShaderMaterial,
		"3D print: building uses its illustrated material")
	_check(Assets.key_for("mine", 3) == "mine_flush_lvl3", "3D mine uses its surface geometry")

func _test_3d_overview_interaction() -> void:
	SaveLoad.prepare_new_game("res://data/starts/metal_magnate.json")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	while not bool(main.get("build_complete")): await get_tree().process_frame
	Tutorial._on_overlay_skipped()
	var view: Control = main.find_child("EmpireView", true, false)
	await view.call("prepare")
	var board: Control = view.find_child("Board", true, false)
	var viewport: SubViewport = board.get("_viewport")
	var camera: Camera3D = board.get("_camera")
	var map_camera: Camera2D = get_tree().get_first_node_in_group("camera")
	var map_state := [map_camera.position, map_camera.zoom, map_camera.rotation]
	_check(viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "3D overview does not render while closed")
	view.show()
	await get_tree().physics_frame
	await get_tree().process_frame
	_check(bool(map_camera.get("input_blocked")), "3D overview owns input while visible")
	_check(viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "3D viewport wakes when opened")
	var builder: RefCounted = board.get("_builder")
	var model: Dictionary = board.get("_model")
	_check_source_tree_layout(builder, model)
	var terrain_node: Node = board.get("_last_terrain")
	var background := ""
	for coord in terrain_node.get("tiles"):
		var candidate := "tile_%d_%d" % [coord.x + 1, coord.y + 1]
		if not model.tiles.has(candidate): background = candidate; break
	var expanded: Dictionary = preload("res://scripts/empire_board_model.gd").build(terrain_node, board.get("_last_graph"), {}, {}, false, Callable(), Callable(), [background])
	_check(expanded.tiles.has(background) and not expanded.tiles[background].store,
		"3D coverage: background tile renders without creating a company stockpile")
	var invented := false
	for item in expanded.standing:
		if str(item.tile) == background and str(item.kind) in ["building", "warehouse"]: invented = true
	_check(not invented, "3D coverage: adding map context does not invent player buildings")
	var tid := str(model.tiles.keys()[0])
	var center: Vector2 = model.tiles[tid].center
	var target: Vector3 = builder.point(center)
	var state: Dictionary = board.call("capture_camera")
	state.target = target
	state.span = 800.0
	var hits := 0
	for i in 4:
		state.yaw = i * PI * 0.5
		board.call("restore_camera", state)
		var hit: Dictionary = board.call("pick_at", board.call("screen_point", target), true)
		if not hit.is_empty() and str(hit.collider.get_meta("tile_id")) == tid: hits += 1
	_check(hits == 4, "3D picking: same terrain tile is selected from all four orbit directions")
	var original_pixels := viewport.size
	viewport.size = original_pixels * 2
	var retina_point: Vector2 = board.call("screen_point", target)
	var retina_hit: Dictionary = board.call("pick_at", retina_point, true)
	_check(not retina_hit.is_empty() and str(retina_hit.collider.get_meta("tile_id")) == tid,
		"3D high-DPI: canvas coordinates still pick the same tile in a double-resolution viewport")
	viewport.size = original_pixels
	var house_meshes: Dictionary = {}
	for visual in builder.building_visuals:
		if str(visual.get_parent().name).begins_with("house"):
			house_meshes[visual.mesh.get_instance_id()] = true
	_check(house_meshes.size() >= 3, "3D housing: the company's three source house varieties remain distinct")
	var selected: Array = []
	board.connect("tile_picked", func(id: String) -> void: selected.append(id))
	var p: Vector2 = board.call("screen_point", target)
	board.call("_activate_at", p, true)
	var panel: Control = main.get("info_panel")
	_check(selected == [tid] and panel.visible and view.visible, "3D terrain click opens the existing tile panel above the overview")
	panel.hide()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = p
	board.call("_gui_input", press)
	var motion := InputEventMouseMotion.new()
	motion.position = p + Vector2(50, 0)
	motion.relative = Vector2(50, 0)
	board.call("_gui_input", motion)
	press.pressed = false
	press.position = motion.position
	board.call("_gui_input", press)
	_check(selected.size() == 1, "3D drag release never selects a tile")
	var before_pinch: Dictionary = board.call("capture_camera")
	var pinch := InputEventMagnifyGesture.new()
	pinch.position = p
	pinch.factor = 1.4
	board.call("_gui_input", pinch)
	var zoomed: Dictionary = board.call("capture_camera")
	_check(is_equal_approx(zoomed.span, before_pinch.span / 1.4), "3D trackpad: pinch zooms continuously")
	pinch.factor = 1.0 / 1.4
	board.call("_gui_input", pinch)
	_check(is_equal_approx(board.call("capture_camera").span, before_pinch.span), "3D trackpad: reciprocal pinch restores zoom")
	var gesture := InputEventPanGesture.new()
	gesture.delta = Vector2(2, 1)
	board.call("_gui_input", gesture)
	_check(board.call("capture_camera").target != zoomed.target, "3D trackpad: two-finger pan moves the camera")
	var terrain: Dictionary = builder.terrain_lods[0]
	var counts: Array = []
	for mesh in terrain.data.meshes: counts.append(mesh.surface_get_array_len(0))
	_check(counts[0] < counts[1] and counts[1] < counts[2], "3D terrain: each of three LODs increases geometric detail")
	for tier in 3:
		builder.set_detail(tier)
		_check(terrain.node.mesh == terrain.data.meshes[tier], "3D terrain: tier %d swaps cached mesh without rebuilding" % tier)
	var after_pan: Dictionary = board.call("capture_camera")
	var content: Node = board.get("_content")
	board.call("set_graph", board.get("_last_graph"), board.get("_last_terrain"))
	_check(board.get("_content") == content and board.call("capture_camera") == after_pan, "3D unchanged rebuild keeps geometry and camera")
	var building_hits := 0
	for item in builder.pickables:
		if str(item.kind) != "building": continue
		state.target = item.point
		state.pitch = 1.2
		board.call("restore_camera", state)
		await get_tree().physics_frame
		var hit: Dictionary = board.call("pick_at", board.call("screen_point", item.point))
		if not hit.is_empty() and str(hit.collider.get_meta("standing", {}).get("iid", "")) == str(item.iid):
			building_hits += 1
			board.call("_activate_at", board.call("screen_point", item.point))
			break
	var chart: Control = view.find_child("GraphWorld", true, false)
	_check(building_hits > 0 and chart.visible and not board.visible, "3D building click still opens its supply-chain network")
	chart.call("clear_focus")
	view.hide()
	await get_tree().process_frame
	_check(not bool(map_camera.get("input_blocked")) and [map_camera.position, map_camera.zoom, map_camera.rotation] == map_state,
		"3D overview leaves the regular map camera unchanged and restores input")
	_check(viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "3D viewport sleeps again on close")
	main.queue_free()
	await get_tree().process_frame

func _test_detail_hysteresis() -> void:
	_check([Detail.choose(0.4), Detail.choose(1.0), Detail.choose(2.0)] == [0, 1, 2], "3D LOD: far, medium and near use distinct screen-space tiers")
	_check(Detail.choose(0.78, 0) == 0 and Detail.choose(0.72, 1) == 1 and Detail.choose(1.50, 2) == 2,
		"3D LOD: hysteresis prevents flicker near zoom boundaries")
	_check(Detail.choose(2.5, 0) == 2 and Detail.choose(0.2, 2) == 0, "3D LOD: large pinch jumps reach the correct tier")

func _test_3d_artwork_ink_exclusions() -> void:
	for key in ["house_lvl1", "house_lvl2", "house_lvl3", "towers_lvl1", "towers_lvl2"]:
		var arrays := Assets.mesh_for(key).surface_get_arrays(0)
		var ink: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
		var unoutlined := 0
		var source_widths := true
		for i in ink.size():
			if int(roundf(ink[i].x)) == 0: unoutlined += 1
			var width := 1.0 - ink[i].y
			source_widths = source_widths and width > 0.0001 and width < 0.03
		_check(unoutlined > 30 and source_widths,
			"3D source ink: %s retains painted faces without outlines and scales the source stroke widths" % key)

func _test_3d_artwork_joined_roads() -> void:
	for spacing in [3.0, 6.0]: _check_joined_roads(spacing)

func _check_joined_roads(spacing: float) -> void:
	var road := RoadSurface.new()
	road.cell_size = spacing
	var ground := SlopedGround.new()
	road.configure([
		{"tile": "left", "a": Vector2(-60, 0), "b": Vector2.ZERO, "level": 2, "paved": true},
		{"tile": "right", "a": Vector2.ZERO, "b": Vector2(45, 45), "level": 2, "paved": true},
		{"tile": "right", "a": Vector2.ZERO, "b": Vector2(0, -60), "level": 2, "paved": true}], ground.height)
	var meshes := [road.mesh_for("left"), road.mesh_for("right")]
	var joined := true
	# Probe the centre, inner corner and outer turn where strip ends used to leave
	# gaps or draw a kerb through the crossing. Test two independently culled tiles.
	for p in [Vector2(0.2, 0.4), Vector2(3, -2), Vector2(-3, 3), Vector2(3, 3)]:
		var top := _road_top_at(meshes, p)
		joined = joined and not top.is_empty() and (top.colour as Color).is_equal_approx(Legacy._ROAD_ASPHALT)
	_check(joined, "3D roads at %du: asphalt joins across angled, sloped and cross-tile junctions with no internal kerb" % spacing)
	var first: Dictionary = road.nodes[Vector2i.ZERO]
	_check(float(first.reach) > 0.0 and road.ways[0].clear[1] > first.reach,
		"3D roads: centre markings stop outside the whole junction")
	road.finish_build()

func _road_top_at(meshes: Array, p: Vector2) -> Dictionary:
	var out := {}
	for mesh in meshes:
		var arrays: Array = mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		for i in range(0, vertices.size(), 3):
			var a := Vector2(vertices[i].x, vertices[i].z)
			var b := Vector2(vertices[i + 1].x, vertices[i + 1].z)
			var c := Vector2(vertices[i + 2].x, vertices[i + 2].z)
			if not Geometry2D.is_point_in_polygon(p, PackedVector2Array([a, b, c])): continue
			var det := (b - a).cross(c - a)
			if absf(det) < 0.000001: continue
			var u := (p - a).cross(c - a) / det
			var v := (b - a).cross(p - a) / det
			var h := vertices[i].y * (1.0 - u - v) + vertices[i + 1].y * u + vertices[i + 2].y * v
			if out.is_empty() or h > float(out.height): out = {"height": h, "colour": colours[i]}
	return out

func _test_3d_artwork_submerged_mines() -> void:
	Assets._manifest = {}
	_check(not Assets.pit_for(1).is_empty(), "3D mines: first metadata lookup after a cold start includes the opening")
	for level in [1, 2, 3]:
		var builder := Builder.new()
		builder.ground = SlopedGround.new()
		builder.tiles = {"mine": {"center": Vector2.ZERO}}
		var mine := {"iid": "pit", "kind": "building", "internal_name": "mine", "level": level,
			"side": 120.0, "tile": "mine", "pos": Vector2.ZERO}
		builder.configure_pits([mine])
		var pit: Dictionary = builder.pits.pit
		var rim_level := true
		for p in pit.rim: rim_level = rim_level and is_equal_approx(builder.surface_height(p), float(pit.height))
		_check(rim_level, "3D mine L%d: steep ground is graded to the rim datum, never through the upper benches" % level)
		var cut := true
		for cell in Detail.CELLS:
			var mesh: ArrayMesh = builder._surface("mine", cell)
			var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			for i in range(0, vertices.size(), 3):
				var p := (vertices[i] + vertices[i + 1] + vertices[i + 2]) / 3.0
				if Geometry2D.is_point_in_polygon(Vector2(p.x, p.z), pit.rim): cut = false
		_check(cut, "3D mine L%d: all three terrain LODs leave the excavated pit open" % level)
		var standing := builder.standing_node(mine)
		_check(is_equal_approx(standing.position.y + float(pit.sink), float(pit.height)),
			"3D mine L%d: source ground datum meets the terrain, with workings below it" % level)
		var body := standing.find_children("*", "StaticBody3D", true, false)[0] as StaticBody3D
		_check(body.collision_layer == 3, "3D mine L%d: excavated ground supports both building and tile picking" % level)
		standing.free()

func _test_3d_artwork_builder_lifetime() -> void:
	var builder := Builder.new()
	builder.ground = SlopedGround.new()
	var alive: WeakRef = weakref(builder)
	var infrastructure := builder.infrastructure({"roads": [], "lines": []}, {"roads": true})
	infrastructure.free()
	builder = null
	_check(alive.get_ref() == null, "3D roads: finished infrastructure does not retain its builder through the height callback")

func _check_source_tree_layout(builder: RefCounted, model: Dictionary) -> void:
	# Compare the actual source renderer's accepted placements, not a second copy
	# of the candidate/clearance algorithm. Tree sprites encode their foot at 96%.
	var original := Legacy.new()
	original._model = model
	original._ground = builder.ground
	for tid in builder.rivers:
		original._rivers[tid] = []
		for rec in builder.rivers[tid]: original._rivers[tid].append(rec.points)
	for road in model.roads:
		original._road_plan.append({"a": road.a, "b": road.b, "half": Legacy._road_widths(int(road.level))[0]})
	original._build_standing()
	original._build_trees()
	var expected: Array[Vector2] = []
	var expected_kinds: Array[String] = []
	for tree in original._pipe_items:
		if tree.kind != "tree": continue
		var r: Rect2 = tree.rect
		expected.append(Vector2(r.get_center().x, r.end.y - r.size.y * 0.04))
		expected_kinds.append((tree.tex as Texture2D).resource_path.get_file().get_basename().trim_prefix("tree_"))
	var actual: Array[Vector2] = []
	var actual_kinds: Array[String] = []
	for placement in builder.tree_placements.values():
		for tree in placement:
			actual.append(Legacy.iso(tree.pos, builder.ground.height(tree.pos)))
			actual_kinds.append(str(tree.kind))
	var matches := actual.size() == expected.size()
	for i in actual.size():
		var found := false
		for j in expected.size(): found = found or (actual[i].distance_to(expected[j]) < 0.01 and actual_kinds[i] == expected_kinds[j])
		matches = matches and found
	_check(matches and actual.size() > 30, "3D trees: species layout and roadside clearance keep all %d original tree positions (%d actual)" % [expected.size(), actual.size()])
	original.free()

func _test_3d_artwork_river_mouth() -> void:
	var hex := Legacy.Model.hex_points(Vector2.ZERO)
	var dry := Geometry2D.intersect_polygons(hex, PackedVector2Array([Vector2(-1000, -1000), Vector2(0, -1000), Vector2(0, 1000), Vector2(-1000, 1000)]))[0]
	var wet := Geometry2D.intersect_polygons(hex, PackedVector2Array([Vector2(0, -1000), Vector2(1000, -1000), Vector2(1000, 1000), Vector2(0, 1000)]))[0]
	var relief := {"land": [{"p": dry, "b": 0}], "sea": [{"p": wet, "b": 4}], "lakes": []}
	var painter := WaterArt.new()
	var mesh := painter.artwork({"center": Vector2.ZERO, "type": "plain"}, relief,
		[{"points": PackedVector2Array([Vector2(-100, 0), Vector2(-10, 0), Vector2(80, 0)]), "start_width": 12.0, "end_width": 12.0}], func(_p: Vector2) -> float: return 0.0)
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var banks_stop := true
	var has_fade := false
	var mouth_span := 0.0
	for i in vertices.size():
		var p := vertices[i]
		if colors[i].is_equal_approx(Legacy._BANK) and p.x > 0.01: banks_stop = false
		if p.x > 5.0 and colors[i].a > 0.0 and colors[i].a < 0.95: has_fade = true
		if p.x > 1.0 and p.x < 23.0 and colors[i].a < 1.0: mouth_span = maxf(mouth_span, absf(p.y) * 2.0)
	_check(banks_stop, "3D river mouth: riverbank ink/earth stops on the shoreline")
	_check(has_fade and mouth_span > 30.0, "3D river mouth: estuary flares beyond the river width and fades into open water")
	painter.free()
	var foam_verts := PackedVector3Array()
	var foam_cols := PackedColorArray()
	var foam_idx := PackedInt32Array()
	var fall := PackedVector2Array([Vector2(-60, 0), Vector2(-30, 0), Vector2.ZERO])
	WaterArt._plan_white_water(foam_verts, foam_cols, foam_idx, fall, PackedFloat32Array([9, 5, 0]), 12.0)
	_check(foam_verts.is_empty(), "3D river: shallow gradients do not become rapids")
	WaterArt._plan_white_water(foam_verts, foam_cols, foam_idx, fall, PackedFloat32Array([25, 12, 0]), 12.0)
	_check(foam_verts.size() > 20 and foam_cols.has(Legacy._FOAM), "3D river: steep falls carry the original broken foam and foot splash")

func _test_3d_artwork_contour_meshes() -> void:
	var valid := true
	for key in [Assets.key_for("house", 1), Assets.key_for("towers", 2), Assets.key_for("pylon", 1), Assets.key_for("tree", 3)]:
		var mesh := Assets.contour_for(key)
		if mesh == null: valid = false; continue
		var arrays := mesh.surface_get_arrays(0)
		for width in arrays[Mesh.ARRAY_TEX_UV]: valid = valid and width.x > 0.0 and width.x < 0.1
		for normal in arrays[Mesh.ARRAY_NORMAL]: valid = valid and absf((normal as Vector3).length() - 1.0) < 0.001
	_check(valid, "3D contours: buildings and source trees carry normalized shell normals and scale-dependent source line widths")
	for level in [1, 2, 3]:
		var key := Assets.key_for("tree", level)
		_check(Assets.mesh_for(key) != null and Assets.projected_height(key) > 0.0, "3D trees: original species %d has real rotatable geometry and sprite-height framing" % level)

func _test_3d_continent_residency() -> void:
	var builder := Builder.new()
	builder.streamed = true
	builder.ground = SlopedGround.new()
	builder.tiles = {"sample": {"center": Vector2.ZERO, "type": "rural", "label": "Sample"}}
	await builder.prepare_tile(self, "sample")
	var node := builder.tile_node("sample")
	add_child(node)
	var item: Dictionary = builder.terrain_lods[0]
	_check(item.data.meshes[0] != null and item.data.meshes[1] == null and item.data.meshes[2] == null,
		"3D continent: distant tiles allocate only their base terrain")
	await builder.refine_tile(self, item, 2)
	_check(item.data.meshes[2] != null and item.node.mesh == item.data.meshes[2],
		"3D continent: near tile gains real fine geometry on demand")
	builder.release_detail({})
	_check(item.node.mesh == item.data.meshes[0] and item.data.meshes[2] == null and item.data.textures[2] == null,
		"3D continent: leaving the camera releases fine meshes and textures")
	_check(Rig.MAX_SIZE >= 24000.0 and Builder.RESIDENT_TILES <= 24,
		"3D continent: wide zoom and explicit fine-terrain budget")
	node.queue_free()
	await get_tree().process_frame

func _test_3d_building_silhouette_picking() -> void:
	var board := preload("res://scripts/supply_chain_3d/board.gd").new()
	board.size = Vector2(1280, 720)
	add_child(board)
	board.set_process(false)
	var builder := Builder.new()
	builder.ground = SlopedGround.new()
	builder.tiles = {"pick": {"center": Vector2.ZERO, "type": "rural", "label": "Picking"}}
	await builder.prepare_tile(self, "pick")
	board._world.add_child(builder.tile_node("pick"))
	var standing := builder.standing_node({"kind": "building", "iid": "factory", "tile": "pick", "pos": Vector2.ZERO,
		"internal_name": "industrial_factory", "level": 3, "side": 80.0})
	board._world.add_child(standing)
	board._builder = builder
	board._model = {"tiles": builder.tiles}
	board.restore_camera({"yaw": PI / 4.0, "pitch": 0.7, "span": 240.0, "target": builder.point(Vector2.ZERO) + Vector3.UP * 20.0})
	var box := BoxShape3D.new()
	box.size = builder.pickables[0].size
	var old_bounds := StaticBody3D.new()
	old_bounds.collision_layer = 4
	old_bounds.position = standing.position + Vector3.UP * box.size.y * 0.5
	var collision := CollisionShape3D.new()
	collision.shape = box
	old_bounds.add_child(collision)
	board._world.add_child(old_bounds)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var building_hits := 0
	var freed_ground_hits := 0
	var space := board._viewport.find_world_3d().direct_space_state
	for y in range(220, 490, 8):
		for x in range(450, 830, 8):
			var screen := Vector2(x, y)
			var pixel := board._render_point(screen)
			var start := board._camera.project_ray_origin(pixel)
			var old_ray := PhysicsRayQueryParameters3D.create(start, start + board._camera.project_ray_normal(pixel) * board._camera.far, 4)
			if space.intersect_ray(old_ray).is_empty(): continue
			var hit := board.pick_at(screen)
			if hit.is_empty(): continue
			if hit.collider.has_meta("standing"): building_hits += 1
			elif hit.collider.get_meta("tile_id", "") == "pick": freed_ground_hits += 1
	_check(building_hits > 10, "3D picking: visible building remains easy to select")
	_check(freed_ground_hits > 5, "3D picking: empty space inside the old oversized box now selects the tile")
	var body: StaticBody3D = standing.find_children("*", "StaticBody3D", true, false)[0]
	_check(board._building_large_enough(body), "3D picking: large projected building has a clickbox")
	builder._overview = true
	var overview_hit := board.pick_at(board.screen_point(builder.pickables[0].point))
	_check(not overview_hit.is_empty() and not overview_hit.collider.has_meta("standing"),
		"3D picking: continent overview forces even a large building to select terrain")
	builder._overview = false
	var far := board.capture_camera()
	far.span = Rig.MAX_SIZE
	board.restore_camera(far)
	await get_tree().physics_frame
	var tiny := board.pick_at(board.screen_point(builder.pickables[0].point))
	_check(not board._building_large_enough(body) and not tiny.is_empty() and not tiny.collider.has_meta("standing"),
		"3D picking: sub-20px buildings let clicks reach their terrain at far zoom")
	var pixels := board._viewport.size
	board._viewport.size = pixels * 2
	_check(not board._building_large_enough(body), "3D picking: Retina density does not change the 20 logical pixel threshold")
	board._viewport.size = pixels
	# Both dimensions matter: a tall, very narrow silhouette remains a tile target.
	body.set_meta("pick_bounds", AABB(Vector3.ZERO, Vector3(1, 1000, 1)))
	far.span = 1000.0
	board.restore_camera(far)
	_check(not board._building_large_enough(body), "3D picking: tall but narrower-than-20px buildings still select the tile")
	board.queue_free()
	await get_tree().process_frame

func _test_3d_persistent_bakes() -> void:
	var Cache := preload("res://scripts/supply_chain_3d/bake_cache.gd")
	var first := Builder.new()
	first.ground = SlopedGround.new()
	first.tiles = {"cache_test": {"center": Vector2.ZERO, "type": "rural", "label": "Fixture"}}
	first._map_key = "isolated-flat-fixture"
	first.bake_cache.enabled = true
	first.bake_cache.directory = "user://supply-chain-bake-test-%d" % Time.get_ticks_usec()
	var key := first.tile_bake_key("cache_test", 1)
	var original := await first._tile_bake(self, "cache_test", 1)
	_check(first.bake_cache.writes == 1, "3D bake cache: tile is persisted on first generation")
	var fresh := Builder.new()
	fresh.ground = SlopedGround.new()
	fresh.tiles = first.tiles.duplicate(true)
	fresh._map_key = first._map_key
	fresh.bake_cache.enabled = true
	fresh.bake_cache.directory = first.bake_cache.directory
	var loaded := await fresh._tile_bake(self, "cache_test", 1)
	_check(fresh.bake_cache.hits == 1 and fresh.bake_cache.writes == 0 and loaded.mesh.surface_get_array_len(0) == original.mesh.surface_get_array_len(0),
		"3D bake cache: a fresh builder reuses disk geometry and texture without generation")
	_check(key == fresh.tile_bake_key("cache_test", 1) and key != fresh.tile_bake_key("cache_test", 2),
		"3D bake cache: stable across instances, separate for medium and near tiles")
	fresh.tiles.cache_test.type = "urban"
	_check(key != fresh.tile_bake_key("cache_test", 1), "3D bake cache: changed tile geography invalidates a bake")
	_check(Cache.digest({"b": 2, "a": 1}) == Cache.digest({"a": 1, "b": 2}), "3D bake cache: dictionary insertion order does not invalidate content")
	first.pits["adjacent"] = {"pos": Vector2(330, 0), "side": 100.0, "area": Rect2(310, -20, 40, 40)}
	_check(key != first.tile_bake_key("cache_test", 1),
		"3D bake cache: an adjacent mine's graded shoulder invalidates the tile even when its pit is outside")
	DirAccess.remove_absolute(first.bake_cache.directory.path_join(key + ".res"))
	DirAccess.remove_absolute(first.bake_cache.directory)

func _test_3d_continent_bake_sharing() -> void:
	var builder := Builder.new()
	builder.ground = SlopedGround.new()
	builder.tiles = {"west": {"center": Vector2.ZERO, "type": "rural", "label": "West"},
		"east": {"center": Vector2(540, 0), "type": "rural", "label": "East"}}
	builder.streamed = true
	builder.configure_grade()
	await builder.prepare_continent(self)
	var root := Node3D.new()
	add_child(root)
	for tid in builder.tiles:
		await builder.prepare_tile(self, tid)
		root.add_child(builder.tile_node(tid))
	var west: Dictionary = builder.terrain_lods[0]
	var east: Dictionary = builder.terrain_lods[1]
	_check(west.data.textures[0] == east.data.textures[0] and west.data.textures[0] == builder.continent.texture,
		"3D continent bake: every coarse tile references one shared atlas")
	builder.finish_continent(root)
	builder.set_overview_scale(0.1)
	_check(builder.continent_node.visible and not west.node.visible and not east.node.visible,
		"3D continent bake: outermost zoom renders the joined continent instead of per-tile surfaces")
	builder.set_overview_scale(1.0)
	_check(not builder.continent_node.visible and west.node.visible and east.node.visible,
		"3D continent bake: closer zoom restores independently detailed tile surfaces")
	root.queue_free()
	await get_tree().process_frame
