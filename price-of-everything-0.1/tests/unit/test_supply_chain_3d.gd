extends "res://tests/test_base.gd"
const FEATURE := "supply_chain_3d"
const Rig := preload("res://scripts/supply_chain_3d/orbit_camera.gd")
const Detail := preload("res://scripts/supply_chain_3d/detail.gd")
const Assets := preload("res://scripts/supply_chain_3d/assets.gd")

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
