extends "res://tests/test_base.gd"
const FEATURE := "supply_chain_3d"
const Traffic := preload("res://scripts/supply_chain_3d/harbour_traffic.gd")
const Assets := preload("res://scripts/supply_chain_3d/assets.gd")
const Harbour := preload("res://scripts/supply_chain_3d/harbour.gd")
const Builder := preload("res://scripts/supply_chain_3d/world_builder.gd")

func _test_harbour_ships_mesh_partition_and_lods() -> void:
	var key := Assets.key_for("port", 1)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Assets.DIRECTORY + "manifest.json"))
	var ships: Array = Assets.harbour_for(key).ships
	var triangles := int(manifest[key].triangles)
	var medium_triangles := 0
	var near_triangles := 0
	var matched := true
	for ship in ships:
		near_triangles += int(manifest[ship.near].triangles)
		medium_triangles += int(manifest[ship.medium].triangles)
		matched = matched and is_equal_approx(float(Assets.component_for(ship.near).waterline), float(Assets.component_for(ship.medium).waterline))
		var near_bounds := Assets.mesh_for(ship.near).get_aabb()
		var medium_bounds := Assets.mesh_for(ship.medium).get_aabb()
		matched = matched and is_equal_approx(near_bounds.size.x, medium_bounds.size.x) and is_equal_approx(near_bounds.size.z, medium_bounds.size.z)
	_check(ships.size() == 3 and triangles + near_triangles == 6652, "Harbour ships: dock and three detailed ships exactly partition the original asset")
	_check(medium_triangles < near_triangles * 0.3, "Harbour ships: medium cuts vessel triangles by over 70 percent")
	_check(matched, "Harbour ships: medium and near share hull dimensions and waterline")
	# The former hull centre is empty in the static port, including its collider.
	var berth: Vector3 = Harbour.vector3(ships[0].berth)
	var faces := Assets.mesh_for(key).get_faces()
	var ghost := false
	for i in range(0, faces.size(), 3):
		if Geometry3D.segment_intersects_triangle(berth + Vector3.UP * 0.03, berth - Vector3.UP * 0.03, faces[i], faces[i + 1], faces[i + 2]) != null: ghost = true
	_check(not ghost, "Harbour ships: static harbour leaves no ghost ship geometry or hitbox")

func _test_harbour_ships_cycle_and_turn_clearance() -> void:
	var route := Traffic.plan_route(Vector2.ZERO, Vector2.RIGHT, 84.0, 18.0, 95.0, Vector2.ZERO, func(_p: Vector2) -> float: return 25.0)
	_check(route.mobile and route.turning, "Harbour ships: open water supports departures and bow-first arrival turns")
	_check(Traffic.sample(route, 0, 0).phase == "berthed" and Traffic.sample(route, 16, 0).phase == "departing", "Harbour ships: docked vessels depart on their own schedule")
	_check(Traffic.sample(route, 42, 0).opacity == 0.0 and Traffic.sample(route, 60, 0).phase == "arriving", "Harbour ships: departed set leaves before replacement arrivals")
	_check(Traffic.sample(route, 84, 0).position == Vector2.ZERO, "Harbour ships: arriving vessel finishes at its exact original berth")
	var earliest_turn := INF
	for step in 101:
		var state := Traffic.arrival(route, 9.0 + 13.0 * step / 100.0)
		earliest_turn = minf(earliest_turn, state.position.x - 42.0)
	_check(earliest_turn > 95.0, "Harbour ships: turning hull stays beyond the quay mouth")
	var continuous := true
	for boundary in [9.0, 22.0, 38.0]:
		var before := Traffic.arrival(route, boundary - 0.001)
		var after := Traffic.arrival(route, boundary + 0.001)
		continuous = continuous and before.position.distance_to(after.position) < 0.1 and before.heading.dot(after.heading) > 0.999
	_check(continuous, "Harbour ships: cruise, turn and reverse docking meet continuously")
	_check(Traffic.sample(route, Traffic.CYCLE - 0.001, 0).position.distance_to(Traffic.sample(route, 0.001, 0).position) < 0.01, "Harbour ships: cycle wraps at the berth without teleporting")

func _test_harbour_ships_coast_and_far_visibility() -> void:
	var shore := func(p: Vector2) -> float: return 34.0 if p.x > 285.0 else 25.0
	var route := Traffic.plan_route(Vector2.ZERO, Vector2.RIGHT, 84.0, 18.0, 95.0, Vector2.ZERO, shore)
	_check(route.mobile and route.distance < 255.0, "Harbour ships: routes stop before the opposite shore including hull clearance")
	var safe := true
	for second in range(0, int(Traffic.CYCLE)):
		var state := Traffic.sample(route, second, 0)
		if state.opacity > 0.0: safe = safe and Traffic.water_safe(route, state.position, state.heading, Vector2.ZERO, shore)
	_check(safe, "Harbour ships: complete visible cycle stays over water")
	var frame := {"harbour_asset": Assets.key_for("port", 1), "harbour_transform": Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 220), Vector3(0, 20.66, 0))}
	var parent := Node3D.new()
	add_child(parent)
	var traffic := Traffic.create(parent, frame, Vector2.ZERO, func(_p: Vector2) -> float: return 25.0)
	Traffic.update(traffic, 15.0, 1)
	var before: Transform3D = traffic.ships[0].node.transform
	_check(traffic.ships[0].medium.visible and traffic.ships[0].near == null, "Harbour ships: medium loads only the simplified model")
	Traffic.update(traffic, 15.0, 2)
	_check(traffic.ships[0].near.visible and not traffic.ships[0].medium.visible and traffic.ships[0].node.transform == before, "Harbour ships: near switch preserves animation position and heading")
	Traffic.update(traffic, 25.0, 0)
	_check(not traffic.root.visible and traffic.ships[0].node.transform == before, "Harbour ships: far hides ships and skips transform updates")
	Traffic.update(traffic, 25.0, 2)
	var fading: Dictionary = traffic.ships[0]
	var coverage: bool = fading.last.opacity > 0.0 and fading.last.opacity < 1.0
	for visual in fading.visuals:
		coverage = coverage and visual.transparency == 0.0 and is_equal_approx(float(visual.material_override.get_shader_parameter("lod_blend")), fading.last.opacity)
	_check(coverage, "Harbour ships: hull and contour fade with matching opaque coverage, without alpha sorting")
	_check(parent.find_children("*", "CollisionObject3D", true, false).is_empty(), "Harbour ships: animated vessels allocate no physics bodies")
	parent.free()
