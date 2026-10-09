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
const Detail := preload("res://scripts/supply_chain_3d/detail.gd")
const Tokens := preload("res://scripts/supply_chain_3d/tokens.gd")
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
var _detail := -1
var _tokens := Tokens.new()
var show_all_tiles := false
var _last_all_tiles := false
var _coverage: OptionButton
var _progress: Label
var _fit_after_build := false
var _streaming := false
var _stream_clock := 0.0

func _ready() -> void:
	show_all_tiles = PlayerProfile.supply_chain_all_tiles
	mouse_filter = Control.MOUSE_FILTER_STOP
	var container := TextureRect.new()
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.handle_input_locally = false
	_viewport.gui_disable_input = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	container.add_child(_viewport)
	container.texture = _viewport.get_texture()
	resized.connect(_resize_viewport)
	_resize_viewport()
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
	# Illustrated face lighting and feathered terrain shadows follow the legacy board.
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
	var controls: VBoxContainer = visibility.panel.get("content")
	controls.add_child(HSeparator.new())
	_coverage = OptionButton.new()
	_coverage.name = "TileCoverage"
	_coverage.add_item("Show player owned tiles only")
	_coverage.add_item("Show all tiles")
	_coverage.selected = 1 if show_all_tiles else 0
	_coverage.focus_mode = Control.FOCUS_NONE
	_coverage.item_selected.connect(func(index: int) -> void: set_all_tiles(index == 1))
	controls.add_child(_coverage)
	_progress = Label.new()
	_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_progress.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_progress.offset_top = 92
	_progress.offset_left = -160
	_progress.offset_right = 160
	_progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_progress.visible = false
	add_child(_progress)
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

func set_all_tiles(value: bool, persist: bool = true) -> void:
	if show_all_tiles == value: return
	show_all_tiles = value
	if persist: PlayerProfile.set_supply_chain_all_tiles(value)
	if _coverage != null: _coverage.selected = 1 if value else 0
	_fit_after_build = true
	if is_instance_valid(_last_terrain): await _build(_last_graph, _last_terrain, true)

func _build(graph: Dictionary, terrain: Node, paced: bool) -> void:
	_last_graph = graph
	_last_terrain = terrain
	_generation += 1
	var generation := _generation
	_building = true
	var next := Node3D.new()
	next.name = "Company"
	var builder := Builder.new()
	builder.streamed = show_all_tiles
	builder.terrain_cache = _terrain_cache
	var rivers := _rivers_by_tile(terrain)
	var river_lines: Dictionary = {}
	for tid in rivers:
		river_lines[tid] = []
		for rec in rivers[tid]: river_lines[tid].append(rec.points)
	var extra_tiles: Array = []
	if show_all_tiles:
		for coord in terrain.get("tiles"):
			extra_tiles.append("tile_%d_%d" % [coord.x + 1, coord.y + 1])
	else:
		for tid in BuildingState.tile_land_owned:
			if BuildingState.get_tile_land_owned(str(tid)) > 0: extra_tiles.append(str(tid))
	if _progress != null:
		_progress.text = "Preparing continent…" if show_all_tiles else "Preparing company tiles…"
		_progress.show()
		await get_tree().process_frame
		if generation != _generation: next.free(); return
	var model := Model.build(terrain, graph, _true_positions(graph, terrain), river_lines, Legacy.plate_town and Legacy.show.decor,
		Legacy._water_test(terrain), Legacy._shore_test(terrain), extra_tiles)
	if show_all_tiles: print("[CONTINENT BUILD] model ready ", Time.get_ticks_msec())
	if model == _model and Legacy.show == _last_show and show_all_tiles == _last_all_tiles:
		_building = false
		if _progress != null: _progress.hide()
		next.free()
		return
	builder.tiles = model.get("tiles", {})
	builder.rivers = rivers
	builder.ground = Ground.for_map(terrain, rivers, Relief.plates(terrain, river_lines), Callable(Legacy, "_relief_of"))
	# Stable origin: expanding the company does not move existing terrain under the camera.
	builder.origin = Vector2.ZERO
	builder.configure_grade()
	builder.configure_pits(model.get("standing", []))
	var first := true
	var built := 0
	for tid in builder.tiles:
		await builder.prepare_tile(self, str(tid))
		if generation != _generation: next.free(); return
		next.add_child(builder.tile_node(str(tid)))
		built += 1
		if _progress != null: _progress.text = "Preparing map · %d / %d tiles" % [built, builder.tiles.size()]
		for p in Model.hex_points(builder.tiles[tid].center):
			var v: Vector3 = builder.point(p)
			if first: builder.bounds = AABB(v, Vector3.ONE); first = false
			else: builder.bounds = builder.bounds.expand(v)
		if paced and built % 8 == 0:
			await get_tree().process_frame
			if generation != _generation: next.free(); return
	next.add_child(builder.mine_rims_node())
	if show_all_tiles: print("[CONTINENT BUILD] terrain ready ", Time.get_ticks_msec())
	var infrastructure := builder.infrastructure(model, Legacy.show, not show_all_tiles)
	next.add_child(infrastructure)
	if show_all_tiles and Legacy.show.roads:
		var roads_built := 0
		for tid in builder.tiles:
			builder.append_road(infrastructure, str(tid))
			roads_built += 1
			if roads_built % 8 == 0:
				_progress.text = "Preparing roads · %d / %d tiles" % [roads_built, builder.tiles.size()]
				await get_tree().process_frame
				if generation != _generation:
					builder.road_surface.finish_build()
					next.free()
					return
		builder.road_surface.finish_build()
		builder._road_height_cache.clear()
	if show_all_tiles: print("[CONTINENT BUILD] roads ready ", Time.get_ticks_msec())
	for s in model.get("standing", []): next.add_child(builder.standing_node(s))
	if show_all_tiles: next.add_child(builder.distant_towns(model.get("standing", [])))
	if Legacy.show.trees:
		var groves := 0
		for tid in builder.tiles:
			next.add_child(builder.trees_node(str(tid), model.get("standing", [])))
			groves += 1
			if paced and groves % 8 == 0:
				await get_tree().process_frame
				if generation != _generation: next.free(); return
	next.add_child(builder.shadows_node())
	if show_all_tiles: print("[CONTINENT BUILD] trees ready ", Time.get_ticks_msec())
	builder.prepare_flows(model)
	var goods: Array = []
	if Legacy.show.goods:
		for flow in builder.flows:
			if not flow.icon is Texture2D: continue
			var sprite := Sprite3D.new()
			sprite.texture = _tokens.texture_for(flow.icon)
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
				sprite.texture = _tokens.texture_for(GoodIcons.texture_for(good, str(Catalog.get_good(good).get("internal_name", ""))))
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
	# Retain only this company's current terrain. Released tiles/old height fields
	# cannot accumulate their three texture tiers across rebuilds.
	var keep: Dictionary = {}
	for tid in builder.tiles: keep[builder.terrain_key(str(tid))] = true
	for key in _terrain_cache.keys():
		if keep.has(key): continue
		var cached: Dictionary = _terrain_cache[key]
		if not show_all_tiles and cached.get("streamed", false) and cached.get("ground_id", 0) == builder.ground.get_instance_id():
			# Keep just the small base continent across coverage switches. Fine
			# tiers are released; a new map/height field clears the old base too.
			for tier in [1, 2]:
				cached.meshes[tier] = null
				cached.textures[tier] = null
		else: _terrain_cache.erase(key)
	_detail = -1
	_model = model
	_last_show = Legacy.show.duplicate()
	_last_all_tiles = show_all_tiles
	_goods = goods
	_effects = effects
	_building = false
	if _progress != null: _progress.hide()
	if (not _fitted or _fit_after_build) and has_content(): fit_view()
	_fit_after_build = false
	_select_tile(_selected_tile)
	_update_detail()
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
	var margin := 1.15 if show_all_tiles else 1.2
	var home_span := clampf(maxf(extent.y * 2.0 + 220.0, (extent.x * 2.0 + 180.0) / maxf(0.5, size.x / maxf(1, size.y))) * margin, Rig.MIN_SIZE, Rig.MAX_SIZE)
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
	_update_detail()

func _resize_viewport() -> void:
	if _viewport == null: return
	var density := get_viewport().get_final_transform().get_scale().abs()
	var pixels := Vector2i((size * density).ceil()).max(Vector2i(1, 1))
	if _viewport.size != pixels: _viewport.size = pixels

func screen_point(world: Vector3) -> Vector2:
	return _camera.unproject_position(world) * size / Vector2(_viewport.size)

func _render_point(screen: Vector2) -> Vector2:
	return screen * Vector2(_viewport.size) / size.max(Vector2.ONE)

func _update_detail() -> void:
	if _builder == null: return
	_detail = Detail.choose(size.y / _rig.span, _detail)
	_builder.set_detail(_detail)
	_builder.set_overview_scale(size.y / _rig.span)

func pick_at(screen: Vector2, tiles_only: bool = false) -> Dictionary:
	screen = _render_point(screen)
	if not has_content(): return {}
	var space := _viewport.find_world_3d().direct_space_state
	# A long orthographic ray exactly on a shared triangle edge can miss in Jolt.
	# Subpixel retries cover numerical cracks without expanding selection by a visible pixel.
	for offset in [Vector2.ZERO, Vector2(0.25, 0.25), Vector2(-0.25, -0.25)]:
		var from := _camera.project_ray_origin(screen + offset)
		var ray := PhysicsRayQueryParameters3D.create(from, from + _camera.project_ray_normal(screen + offset) * _camera.far, 1 if tiles_only else 3)
		ray.hit_back_faces = true
		var hit := space.intersect_ray(ray)
		if not hit.is_empty():
			if tiles_only or hit.collider.has_meta("standing"): return hit
			# A two-world-unit halo helps hit fine building edges without swallowing
			# the yard in a tall rectangular box. Terrain, trees and roads select tiles.
			var halo := 2.0 * float(_viewport.size.y) / _rig.span
			for direction in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
				var pixel: Vector2 = screen + direction * halo
				var start := _camera.project_ray_origin(pixel)
				var near_ray := PhysicsRayQueryParameters3D.create(start, start + _camera.project_ray_normal(pixel) * _camera.far, 3)
				near_ray.hit_back_faces = true
				var neighbour := space.intersect_ray(near_ray)
				if not neighbour.is_empty() and neighbour.collider.has_meta("standing") and neighbour.collider.get_meta("tile_id", "") == hit.collider.get_meta("tile_id", ""):
					return neighbour
			return hit
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
			_zoom_at(event.position, 1.0 / 0.88 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 0.88)
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

	elif event is InputEventMagnifyGesture:
		_zoom_at(event.position, event.factor)
		accept_event()
	elif event is InputEventPanGesture:
		_rig.pan(-event.delta * 12.0, size.y)
		_rig.apply(_camera)
		accept_event()

func _zoom_at(screen: Vector2, factor: float) -> void:
	if factor <= 0.0 or not is_finite(factor): return
	var before := pick_at(screen, true)
	_rig.span = clampf(_rig.span / factor, Rig.MIN_SIZE, Rig.MAX_SIZE)
	_rig.apply(_camera)
	if not before.is_empty():
		var plane := Plane(Vector3.UP, (before.position as Vector3).y)
		var pixel := _render_point(screen)
		var after = plane.intersects_ray(_camera.project_ray_origin(pixel), _camera.project_ray_normal(pixel))
		if after is Vector3: _rig.target += before.position - after
		_rig.apply(_camera)
	_update_detail()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode == KEY_HOME: reset_view()
	elif event.keycode in [KEY_Q, KEY_E]:
		_rig.yaw += PI / 12.0 * (1.0 if event.keycode == KEY_E else -1.0)
		_rig.apply(_camera)
	else: return
	get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	_resize_viewport()
	if animate_goods: _time += delta
	_update_detail()
	_update_goods()
	_update_cars()
	_stream_clock += delta
	if show_all_tiles and not _building and not _streaming and _stream_clock >= 0.25:
		_stream_clock = 0.0
		_stream_visible()
	if _labels != null: _labels.queue_redraw()

func _stream_visible() -> void:
	if _builder == null or not _builder.streamed: return
	_streaming = true
	var generation := _generation
	var builder: RefCounted = _builder
	var tier := _detail
	var wanted: Array = []
	if tier > 0:
		var view := Rect2(Vector2.ZERO, size).grow(120.0)
		for item in builder.terrain_lods:
			var at: Vector3 = builder.point(builder.tiles[item.tile].center)
			if _camera.is_position_behind(at): continue
			var bounds := Rect2(screen_point(at), Vector2.ZERO)
			for p in Model.hex_points(builder.tiles[item.tile].center): bounds = bounds.expand(screen_point(builder.point(p)))
			if bounds.intersects(view): wanted.append(item)
		wanted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return (builder.point(builder.tiles[a.tile].center) - _rig.target).length_squared() < (builder.point(builder.tiles[b.tile].center) - _rig.target).length_squared())
		if wanted.size() > Builder.RESIDENT_TILES: wanted.resize(Builder.RESIDENT_TILES)
	var keep := {}
	for item in wanted: keep[str(item.tile)] = true
	builder.release_detail(keep)
	var camera_state := capture_camera()
	for item in wanted:
		await builder.refine_tile(self, item, tier)
		if generation != _generation or camera_state != capture_camera(): break
	_streaming = false

func detail_ready() -> bool:
	return not _building and not _streaming

func _update_goods() -> void:
	for item in _goods:
		var stationary := bool(item.get("stationary", false))
		item.sprite.visible = not animate_goods if stationary else animate_goods
		var units_per_pixel := _rig.span / maxf(1.0, size.y)
		var token_pixels := clampf(44.0 / units_per_pixel + 10.0, 16.0, 40.0)
		item.sprite.pixel_size = units_per_pixel * token_pixels / maxf(1, item.sprite.texture.get_width())
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
	var distant := show_all_tiles and size.y / _rig.span < 0.30
	var label_limit := 8 if size.y / _rig.span < 0.15 else 14
	var occupied: Array[Rect2] = []
	var candidates: Array = _builder.labels.duplicate()
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if (str(a.tile) == _selected_tile) != (str(b.tile) == _selected_tile): return str(a.tile) == _selected_tile
		return str(a.tile) < str(b.tile))
	for label in candidates:
		if distant and occupied.size() >= label_limit: break
		var selected := str(label.tile) == _selected_tile
		var tile: Dictionary = _builder.tiles[label.tile]
		# At continent scale only cities and the selected tile need labels.
		if show_all_tiles and size.y / _rig.span < 0.3 and not selected and str(tile.type) != "urban": continue
		var p: Vector3 = label.point
		if _camera.is_position_behind(p): continue
		var screen := screen_point(p)
		if not Rect2(Vector2.ZERO, size).has_point(screen): continue
		var title := str(label.text)
		if title.begins_with("(") and not selected: continue
		if distant: title = title.get_slice(" - (", 0)
		var width := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		var box := Rect2(screen - Vector2(width * 0.5 + 8, 11), Vector2(width + 16, 22))
		var crowded := false
		for previous in occupied: crowded = crowded or box.grow(80.0 if distant else 8.0).intersects(previous)
		if crowded: continue
		occupied.append(box)
		if distant:
			_labels.draw_circle(screen + Vector2(0, -9), 3.5, Color("e6d9b4"))
			_labels.draw_circle(screen + Vector2(0, -9), 1.6, Color("6f6253"))
			_labels.draw_string_outline(font, box.position + Vector2(8, 16), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color("293852"))
		else: _labels.draw_rect(box, Color(0.015, 0.058, 0.105, 0.86))
		_labels.draw_string(font, box.position + Vector2(8, 16), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, DS.PALETTE.TEXT)

func standing_screen_rects() -> Array:
	var out: Array = []
	if _builder == null: return out
	for item in _builder.pickables:
		var p := screen_point(item.point)
		out.append({"iid": item.iid, "kind": item.kind, "rect": Rect2(p - Vector2(12, 12), Vector2(24, 24))})
	return out


func _build_effects(builder: RefCounted, parent: Node3D) -> Array:
	# The old view lights windows and yards in polluted districts. Shared additive
	# cards reproduce its soft bloom without allocating a realtime light per lamp.
	var glow := GradientTexture2D.new()
	glow.width = 64
	glow.height = 64
	glow.fill = GradientTexture2D.FILL_RADIAL
	glow.fill_from = Vector2(0.5, 0.5)
	glow.fill_to = Vector2(1.0, 0.5)
	glow.gradient = Gradient.new()
	glow.gradient.colors = PackedColorArray([Color(1, 1, 1, 0.35), Color(1, 1, 1, 0)])
	var glow_material := StandardMaterial3D.new()
	glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	glow_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	glow_material.albedo_texture = glow
	glow_material.albedo_color = Color(1.0, 0.70, 0.34, 0.6)
	for item in builder.glows:
		var quad := QuadMesh.new()
		quad.size = item.size
		var node := Geo.instance(quad, glow_material)
		node.position = item.point
		parent.add_child(node)
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
		car.node.visible = not show_all_tiles or size.y / _rig.span >= 0.30
		if not car.node.visible: continue
		var at := fposmod(_time * 0.06 + float(car.phase), 1.0) * 16.0
		var index := mini(15, int(at))
		var a: Vector3 = car.points[index]
		var b: Vector3 = car.points[index + 1]
		car.node.position = a.lerp(b, at - index)
		if a.distance_squared_to(b) > 0.01: car.node.look_at(car.node.position + b - a, Vector3.UP)
