extends Control
## A real, isolated 3D world for the supply-chain overview. The regular map still owns
## its Camera2D, rendering and input. Rebuilding never changes this camera's orbit.
signal building_picked(iid: String)
signal suppliers_picked
signal tile_picked(tile_id: String)
const GoodIcons := preload("res://scripts/good_icons.gd")
const Builder := preload("res://scripts/supply_chain_3d/world_builder.gd")
const Rig := preload("res://scripts/supply_chain_3d/orbit_camera.gd")
const Model := preload("res://scripts/empire_board_model.gd")
const Legacy := preload("res://scripts/empire_board.gd")
const Relief := preload("res://scripts/empire_board_relief.gd")
const Ground := preload("res://scripts/empire_board_ground.gd")
const Geo := preload("res://scripts/supply_chain_3d/geometry.gd")
var animate_goods := true
var _viewport: SubViewport
var _camera: Camera3D
var _rig := Rig.new()
var _world: Node3D
var _content: Node3D
var _builder: RefCounted
var _model: Dictionary = {}
var _terrain_cache: Dictionary = {}
var _selection: MeshInstance3D
var _selected_tile := ""
var _generation := 0
var _building := false
var _fitted := false
var _drag_button := 0
var _press := Vector2.ZERO
var _dragged := false
var _time := 0.0
var _goods: Array = []
var _last_graph: Dictionary = {}
var _last_terrain: Node
var _last_show: Dictionary = {}
var _effects: Array = []
var _labels: Control

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var container := SubViewportContainer.new()
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.handle_input_locally = false
	_viewport.gui_disable_input = true
	_viewport.msaa_3d = Viewport.MSAA_2X
	container.add_child(_viewport)
	_world = Node3D.new()
	_viewport.add_child(_world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("2b3757")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("d3e1f2")
	environment.environment.ambient_light_energy = 0.45
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_world.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.light_color = Color("fff0d0")
	sun.light_energy = 0.85
	# The approved sprite rig disables cast shadows; the printed shading belongs on faces.
	sun.shadow_enabled = false
	sun.directional_shadow_max_distance = 20000.0
	_world.add_child(sun)
	_camera = Camera3D.new()
	_world.add_child(_camera)
	_camera.current = true
	_rig.apply(_camera)
	visibility_changed.connect(_visibility)
	_visibility()
	_labels = Control.new()
	_labels.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_labels.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_labels.draw.connect(_draw_labels)
	add_child(_labels)
	var visibility := preload("res://scripts/empire_board_visibility.gd").new()
	add_child(visibility)
	visibility.setup(Legacy.show)
	visibility.changed.connect(func(_key: String, _on: bool) -> void:
		if is_instance_valid(_last_terrain): set_graph(_last_graph, _last_terrain))
	var keys := HBoxContainer.new()
	keys.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	keys.offset_left = -306
	keys.offset_top = -102
	keys.offset_right = -24
	keys.offset_bottom = -58
	add_child(keys)
	for label in ["↶", "Reset view", "↷"]:
		var button := Button.new()
		button.text = label
		button.focus_mode = Control.FOCUS_NONE
		button.theme_type_variation = &"Outlined"
		button.custom_minimum_size = Vector2(54, 42)
		button.pressed.connect(func() -> void:
			if label == "Reset view": reset_view()
			else:
				_rig.yaw += PI / 4.0 * (1.0 if label == "↷" else -1.0)
				_rig.apply(_camera))
		keys.add_child(button)

func _visibility() -> void:
	_drag_button = 0
	if _viewport != null:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if is_visible_in_tree() else SubViewport.UPDATE_DISABLED
	if _world != null: _world.process_mode = Node.PROCESS_MODE_INHERIT if is_visible_in_tree() else Node.PROCESS_MODE_DISABLED
	set_process(is_visible_in_tree())
	set_process_unhandled_key_input(is_visible_in_tree())

func has_content() -> bool:
	return not _model.get("tiles", {}).is_empty()

func is_ready() -> bool:
	return not _building

func _hold_until_baked() -> void:
	pass # Geometry is retained; there are no angle-dependent image bakes.

func set_graph(graph: Dictionary, terrain: Node) -> void:
	_build(graph, terrain, false)

func build_async(graph: Dictionary, terrain: Node) -> void:
	await _build(graph, terrain, true)

func _build(graph: Dictionary, terrain: Node, paced: bool) -> void:
	_last_graph = graph
	_last_terrain = terrain
	_generation += 1
	var generation := _generation
	_building = true
	var next := Node3D.new()
	next.name = "Company"
	var builder := Builder.new()
	builder.terrain_cache = _terrain_cache
	var rivers := _rivers_by_tile(terrain)
	var river_lines: Dictionary = {}
	for tid in rivers:
		river_lines[tid] = []
		for rec in rivers[tid]: river_lines[tid].append(rec.points)
	var model := Model.build(terrain, graph, _true_positions(graph, terrain), river_lines, Legacy.plate_town and Legacy.show.decor,
		Legacy._water_test(terrain), Legacy._shore_test(terrain))
	if model == _model and Legacy.show == _last_show:
		_building = false
		next.free()
		return
	builder.tiles = model.get("tiles", {})
	builder.rivers = rivers
	builder.ground = Ground.for_map(terrain, rivers, Relief.plates(terrain, river_lines), Callable(Legacy, "_relief_of"))
	# Stable origin: expanding the company does not move existing terrain under the camera.
	builder.origin = Vector2.ZERO
	var first := true
	for tid in builder.tiles:
		next.add_child(builder.tile_node(str(tid)))
		for p in Model.hex_points(builder.tiles[tid].center):
			var v: Vector3 = builder.point(p)
			if first: builder.bounds = AABB(v, Vector3.ONE); first = false
			else: builder.bounds = builder.bounds.expand(v)
		if paced:
			await get_tree().process_frame
			if generation != _generation: next.free(); return
	next.add_child(builder.infrastructure(model, Legacy.show))
	for s in model.get("standing", []): next.add_child(builder.standing_node(s))
	if Legacy.show.trees:
		for tid in builder.tiles: next.add_child(builder.trees_node(str(tid), model.get("standing", [])))
	builder.prepare_flows(model)
	var goods: Array = []
	if Legacy.show.goods:
		for flow in builder.flows:
			if not flow.icon is Texture2D: continue
			var sprite := Sprite3D.new()
			sprite.texture = flow.icon
			sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			sprite.no_depth_test = false
			sprite.shaded = false
			sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			next.add_child(sprite)
			goods.append({"sprite": sprite, "flow": flow})
		# When paused, show each output above its producer (the existing motion key's meaning).
		for item in builder.pickables:
			var output: Array = model.get("made", {}).get(str(item.iid), [])
			for i in output.size():
				var sprite := Sprite3D.new()
				var good := str(output[i])
				sprite.texture = GoodIcons.texture_for(good, str(Catalog.get_good(good).get("internal_name", "")))
				if sprite.texture == null: sprite.free(); continue
				sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				sprite.position = item.top + Vector3((i - (output.size() - 1) * 0.5) * 22.0, 8.0, 0)
				next.add_child(sprite)
				goods.append({"sprite": sprite, "stationary": true})
	var effects := _build_effects(builder, next)
	if _content != null:
		_world.remove_child(_content)
		_content.queue_free()
	_selection = null
	_content = next
	_world.add_child(_content)
	_builder = builder
	_model = model
	_last_show = Legacy.show.duplicate()
	_goods = goods
	_effects = effects
	_building = false
	if not _fitted and has_content(): fit_view()
	_select_tile(_selected_tile)
	_update_goods()
	_update_cars()
	if _labels != null: _labels.queue_redraw()

func _rivers_by_tile(terrain: Node) -> Dictionary:
	var rivers: Dictionary = {}
	var rv: Node = terrain.get_parent().get_node_or_null("RiverVisuals") if terrain.get_parent() != null else null
	if rv == null: rv = get_tree().get_first_node_in_group("river_visuals")
	if rv != null and rv.has_method("get_river_polylines"):
		for rec in rv.call("get_river_polylines"):
			var c: Vector2i = rec.coord
			var tid := "tile_%d_%d" % [c.x + 1, c.y + 1]
			(rivers.get_or_add(tid, []) as Array).append(rec)
	return rivers

func _true_positions(graph: Dictionary, terrain: Node) -> Dictionary:
	var positions: Dictionary = {}
	var bv := get_tree().get_first_node_in_group("building_footprints")
	if bv != null and bv.has_method("footprint_center_for"):
		for node in graph.get("nodes", []):
			var tile := str(node.get("tile_id", ""))
			if tile != "": positions[str(node.iid)] = bv.call("footprint_center_for", str(node.iid), terrain.id_to_coord(tile))
	return positions

func fit_view() -> void:
	if _builder == null or not has_content(): return
	_rig.yaw = Rig.HOME_YAW
	_rig.pitch = Rig.HOME_PITCH
	_rig.target = _builder.bounds.get_center()
	_rig.apply(_camera)
	var extent := Vector2.ZERO
	var inverse := _camera.global_basis.inverse()
	for i in 8:
		var p: Vector3 = inverse * (_builder.bounds.get_endpoint(i) - _rig.target)
		extent = extent.max(Vector2(absf(p.x), absf(p.y)))
	var home_span := clampf(maxf(extent.y * 2.0 + 220.0, (extent.x * 2.0 + 180.0) / maxf(0.5, size.x / maxf(1, size.y))) * 1.2, Rig.MIN_SIZE, Rig.MAX_SIZE)
	_rig.span = home_span
	_rig.apply(_camera)
	_fitted = true

func reset_view() -> void:
	fit_view()

func capture_camera() -> Dictionary:
	return _rig.capture()

func restore_camera(state: Dictionary) -> void:
	_rig.restore(state)
	_rig.apply(_camera)

func pick_at(screen: Vector2, tiles_only: bool = false) -> Dictionary:
	if not has_content(): return {}
	var space := _viewport.find_world_3d().direct_space_state
	# A long orthographic ray exactly on a shared triangle edge can miss in Jolt.
	# Subpixel retries cover numerical cracks without expanding selection by a visible pixel.
	for offset in [Vector2.ZERO, Vector2(0.25, 0.25), Vector2(-0.25, -0.25)]:
		var from := _camera.project_ray_origin(screen + offset)
		var ray := PhysicsRayQueryParameters3D.create(from, from + _camera.project_ray_normal(screen + offset) * _camera.far, 1 if tiles_only else 3)
		ray.hit_back_faces = true
		var hit := space.intersect_ray(ray)
		if not hit.is_empty(): return hit
	return {}

func _activate_at(screen: Vector2, tiles_only: bool = false) -> void:
	var hit := pick_at(screen, tiles_only)
	if hit.is_empty(): return
	var body: Node = hit.collider
	var standing: Dictionary = body.get_meta("standing", {})
	if not tiles_only and str(standing.get("kind", "")) in ["building", "site"]:
		building_picked.emit(str(standing.iid))
	elif not tiles_only and str(standing.get("kind", "")) == "suppliers":
		suppliers_picked.emit()
	else:
		var tile := str(body.get_meta("tile_id", ""))
		_select_tile(tile)
		tile_picked.emit(tile)

func _select_tile(tile: String) -> void:
	_selected_tile = tile
	if _selection != null: _selection.queue_free(); _selection = null
	if _builder == null or not _builder.tiles.has(tile): return
	var batch := Geo.Batch.new()
	var points := Model.hex_points(_builder.tiles[tile].center)
	points.append(points[0])
	_builder.ribbon(batch, points, 4.0, Color("ffe6a4"), 4.0)
	_selection = Geo.instance(batch.mesh(), _builder.line_mat)
	_content.add_child(_selection)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
			var before := pick_at(event.position, true)
			_rig.span = clampf(_rig.span * (0.88 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 0.88), Rig.MIN_SIZE, Rig.MAX_SIZE)
			_rig.apply(_camera)
			if not before.is_empty():
				var plane := Plane(Vector3.UP, (before.position as Vector3).y)
				var after = plane.intersects_ray(_camera.project_ray_origin(event.position), _camera.project_ray_normal(event.position))
				if after is Vector3: _rig.target += before.position - after
				_rig.apply(_camera)
		elif event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			if event.pressed:
				_drag_button = event.button_index
				_press = event.position
				_dragged = false
			elif event.button_index == _drag_button:
				_drag_button = 0
				if event.button_index == MOUSE_BUTTON_LEFT and not _dragged:
					var terrain := get_tree().get_first_node_in_group("hex_map")
					var tile_action := terrain != null and bool(terrain.get("_stockpile_destination_selection_active"))
					_activate_at(event.position, event.shift_pressed or tile_action or BuildMode.is_active)
		accept_event()
	elif event is InputEventMouseMotion and _drag_button != 0:
		if event.position.distance_to(_press) > 5.0: _dragged = true
		if _dragged:
			if _drag_button == MOUSE_BUTTON_LEFT: _rig.pan(event.relative, size.y)
			else: _rig.orbit(event.relative)
			_rig.apply(_camera)
		accept_event()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode == KEY_HOME: reset_view()
	elif event.keycode in [KEY_Q, KEY_E]:
		_rig.yaw += PI / 12.0 * (1.0 if event.keycode == KEY_E else -1.0)
		_rig.apply(_camera)
	else: return
	get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if animate_goods: _time += delta
	_update_goods()
	_update_cars()
	if _labels != null: _labels.queue_redraw()

func _update_goods() -> void:
	for item in _goods:
		var stationary := bool(item.get("stationary", false))
		item.sprite.visible = not animate_goods if stationary else animate_goods
		item.sprite.pixel_size = clampf(_rig.span / maxf(1.0, size.y), 0.3, 2.0) * 22.0 / maxf(1, item.sprite.texture.get_width())
		if stationary: continue
		var flow: Dictionary = item.flow
		var at := fposmod(_time * 38.0, float(flow.length)) if animate_goods else 0.0
		var distances: PackedFloat32Array = flow.distances
		var idx := clampi(distances.bsearch(at), 1, distances.size() - 1)
		var t := inverse_lerp(distances[idx - 1], distances[idx], at)
		item.sprite.position = (flow.points[idx - 1] as Vector3).lerp(flow.points[idx], t)

func _draw_labels() -> void:
	if _builder == null or not Legacy.show.names: return
	var font := ThemeDB.fallback_font
	for label in _builder.labels:
		var p: Vector3 = label.point + Vector3(0, 0, 140)
		if _camera.is_position_behind(p): continue
		var screen := _camera.unproject_position(p)
		if not Rect2(Vector2.ZERO, size).has_point(screen): continue
		var title := str(label.text)
		var width := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		var start := screen - Vector2(width * 0.5, 0)
		_labels.draw_string_outline(font, start, title, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 4, Color("23304d"))
		_labels.draw_string(font, start, title, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("fff1cf"))

func standing_screen_rects() -> Array:
	var out: Array = []
	if _builder == null: return out
	for item in _builder.pickables:
		var p := _camera.unproject_position(item.point)
		out.append({"iid": item.iid, "kind": item.kind, "rect": Rect2(p - Vector2(12, 12), Vector2(24, 24))})
	return out


func _build_effects(builder: RefCounted, parent: Node3D) -> Array:
	var cars: Array = []
	var car := Geo.Batch.new()
	car.box(Vector3(0, 2, 0), Vector3(4, 3, 9), Color("dbb963"))
	car.box(Vector3(0, 4, 0), Vector3(3.5, 2, 4), Color("41556a"))
	var car_mesh := car.mesh()
	for road in builder.cars:
		var path := PackedVector3Array()
		for i in 17:
			var p: Vector2 = (road.a as Vector2).lerp(road.b, float(i) / 16.0)
			path.append(builder.at_height(p, builder.road_height(p) + 2.0))
		var node := Geo.instance(car_mesh, builder.mat)
		parent.add_child(node)
		cars.append({"node": node, "points": path, "phase": road.phase})
	if Legacy.show.pollution:
		var puff := SphereMesh.new()
		puff.radial_segments = 8
		puff.rings = 4
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(0.62, 0.66, 0.7, 0.4)
		material.roughness = 1.0
		puff.material = material
		for stack in builder.smoke:
			var particles := CPUParticles3D.new()
			particles.mesh = puff
			particles.position = stack.point
			particles.amount = 14
			particles.lifetime = 4.5
			particles.preprocess = 2.0
			particles.direction = Vector3.UP
			particles.spread = 12.0
			particles.initial_velocity_min = 8.0
			particles.initial_velocity_max = 12.0
			particles.gravity = Vector3(3, 0, 0)
			particles.scale_amount_min = 6.0
			particles.scale_amount_max = 12.0
			var fade := Gradient.new()
			fade.colors = PackedColorArray([Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)])
			particles.color_ramp = fade
			parent.add_child(particles)
	return cars

func _update_cars() -> void:
	for car in _effects:
		var at := fposmod(_time * 0.06 + float(car.phase), 1.0) * 16.0
		var index := mini(15, int(at))
		var a: Vector3 = car.points[index]
		var b: Vector3 = car.points[index + 1]
		car.node.position = a.lerp(b, at - index)
		if a.distance_squared_to(b) > 0.01: car.node.look_at(car.node.position + b - a, Vector3.UP)
