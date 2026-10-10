extends RefCounted
## Cosmetic harbour traffic. One clock, no physics, and no work at far LOD.
const Assets := preload("res://scripts/supply_chain_3d/assets.gd")
const Ground := preload("res://scripts/empire_board_ground.gd")
const DEPART_DURATION := 22.0
const ARRIVE_START := 45.0
const ARRIVE_DURATION := 38.0
const CYCLE := 177.0

static func create(parent: Node3D, frame: Dictionary, center: Vector2, height_at: Callable) -> Dictionary:
	var root := Node3D.new()
	root.name = "HarbourShips"
	parent.add_child(root)
	var ships: Array = []
	var pose: Transform3D = frame.harbour_transform
	var scale := Vector3(pose.basis.x.length(), pose.basis.y.length(), pose.basis.z.length())
	for asset in Assets.harbour_for(frame.harbour_asset).ships:
		var xyz: Array = asset.berth
		var berth := pose * Vector3(xyz[0], xyz[1], xyz[2])
		var direction := Vector2(pose.basis.x.x, pose.basis.x.z).normalized()
		var route := plan_route(Vector2(berth.x, berth.z), direction,
			float(asset.length) * scale.x, float(asset.beam) * scale.x, float(asset.mouth) * scale.x,
			center, height_at)
		var ship := Node3D.new()
		ship.name = str(asset.near)
		root.add_child(ship)
		ships.append({"node": ship, "asset": asset, "route": route, "waterline": berth.y,
			"scale": scale, "near": null, "medium": null, "visuals": [], "last": {}})
	return {"root": root, "ships": ships}

static func plan_route(berth: Vector2, forward: Vector2, length: float, beam: float, mouth: float,
		center: Vector2, height_at: Callable) -> Dictionary:
	var route := {"berth": berth, "forward": forward, "cross": Vector2(-forward.y, forward.x),
		"length": length, "beam": beam, "exit": mouth + length * 0.5 + 12.0,
		"distance": 0.0, "radius": length * 0.65, "turn_sign": 1.0, "turning": false, "mobile": false}
	# Stop before the opposite bank. The vessel's whole footprint, rather than
	# just its centre, must remain wet along the outbound berth corridor.
	var desired := maxf(340.0, float(route.exit) + length * 2.5)
	for distance in range(0, ceili(desired) + 1, 8):
		if not water_safe(route, berth + forward * distance, forward, center, height_at): break
		route.distance = float(distance)
	route.mobile = float(route.distance) > maxf(length * 1.3, float(route.exit))
	if not route.mobile: return route
	# Try each side of the bay. Turns happen only after the stern clears the
	# longest pier. Arrivals are serialized so manoeuvring ships cannot collide.
	for radius_scale in [0.65, 0.55]:
		route.radius = length * radius_scale
		if route.distance < route.exit + route.radius + 24.0: continue
		for sign in [1.0, -1.0]:
			route.turn_sign = sign
			route.turning = true
			var safe := true
			for step in 97:
				var point := arrival(route, ARRIVE_DURATION * step / 96.0)
				if not water_safe(route, point.position, point.heading, center, height_at):
					safe = false
					break
			if safe: return route
	# Tight bays use the clear berth corridor for an astern approach.
	route.turning = false
	return route

static func water_safe(route: Dictionary, position: Vector2, heading: Vector2, center: Vector2, height_at: Callable) -> bool:
	var cross := Vector2(-heading.y, heading.x)
	for along in [-0.38, 0.0, 0.38]:
		for across in [-0.25, 0.25]:
			var point: Vector2 = center + position + heading * float(route.length) * along + cross * float(route.beam) * across
			if float(height_at.call(point)) > Ground.SEA_LEVEL + 0.5: return false
	return true

static func arrival(route: Dictionary, age: float) -> Dictionary:
	var offset := Vector2.ZERO
	var heading: Vector2 = route.forward
	if not route.turning:
		offset.x = float(route.distance) * (1.0 - smoothstep(0.0, ARRIVE_DURATION, age))
	elif age < 9.0:
		offset = Vector2(lerpf(route.distance, route.exit + route.radius, smoothstep(0.0, 9.0, age)), 2.0 * route.radius * route.turn_sign)
		heading = -route.forward
	elif age < 22.0:
		var angle := PI * 0.5 + PI * smoothstep(9.0, 22.0, age)
		offset = Vector2(route.exit + route.radius + route.radius * cos(angle), route.radius * route.turn_sign * (1.0 + sin(angle)))
		heading = route.forward * -sin(angle) + route.cross * cos(angle) * route.turn_sign
	else:
		offset.x = (route.exit + route.radius) * (1.0 - smoothstep(22.0, ARRIVE_DURATION, age))
	return {"position": route.berth + route.forward * offset.x + route.cross * offset.y, "heading": heading}

static func sample(route: Dictionary, time: float, index: int) -> Dictionary:
	var age := fposmod(time, CYCLE)
	var state := {"position": route.berth, "heading": route.forward, "opacity": 1.0, "phase": "berthed"}
	if not route.mobile: return state
	var depart := 5.0 + index * 6.0
	var incoming := ARRIVE_START + index * ARRIVE_DURATION
	if age < depart: return state
	if age < depart + DEPART_DURATION:
		var progress := (age - depart) / DEPART_DURATION
		state.position = route.berth + route.forward * float(route.distance) * smoothstep(0.0, 1.0, progress)
		state.opacity = 1.0 - smoothstep(0.76, 1.0, progress)
		state.phase = "departing"
	elif age < incoming:
		state.opacity = 0.0
		state.phase = "away"
	elif age < incoming + ARRIVE_DURATION:
		var point := arrival(route, age - incoming)
		state.position = point.position
		state.heading = point.heading
		state.opacity = smoothstep(0.0, 3.0, age - incoming)
		state.phase = "arriving"
	return state

static func update(traffic: Dictionary, time: float, tier: int) -> void:
	traffic.root.visible = tier > 0
	if tier <= 0: return
	var representation := "near" if tier >= 2 else "medium"
	for index in traffic.ships.size():
		var ship: Dictionary = traffic.ships[index]
		var fresh := false
		if ship[representation] == null:
			fresh = true
			var group := Node3D.new()
			group.name = representation
			ship.node.add_child(group)
			ship[representation] = group
			var key := str(ship.asset[representation])
			for mesh in [Assets.mesh_for(key), Assets.contour_for(key) if tier >= 2 else null]:
				if mesh == null: continue
				var visual := MeshInstance3D.new()
				visual.mesh = mesh
				# Reuse the opaque LOD coverage shader for fades. Alpha blending
				# sorts the contour shell over the hull and turns vessels navy.
				var material := mesh.surface_get_material(0).duplicate() as ShaderMaterial
				material.set_shader_parameter("lod_side", 1)
				material.set_shader_parameter("detail_level", tier)
				visual.material_override = material
				visual.position.y = -float(Assets.component_for(key).waterline)
				visual.lod_bias = 2.0 if tier >= 2 else 0.8
				group.add_child(visual)
				ship.visuals.append(visual)
		for name in ["near", "medium"]:
			if ship[name] != null: ship[name].visible = name == representation
		var state := sample(ship.route, time, index)
		var fade_changed := fresh or not is_equal_approx(float(ship.last.get("opacity", -1.0)), state.opacity)
		ship.last = state
		ship.node.visible = state.opacity > 0.001
		var basis := Basis(Vector3.UP, -(state.heading as Vector2).angle()).scaled_local(ship.scale)
		ship.node.transform = Transform3D(basis, Vector3(state.position.x, ship.waterline, state.position.y))
		if fade_changed:
			for visual in ship.visuals: visual.material_override.set_shader_parameter("lod_blend", state.opacity)
