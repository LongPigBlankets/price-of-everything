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
var _stream_camera: Dictionary = {}
var _stream_generation := -1
var _stream_tier := -1
var _nearby_tiles: Dictionary = {}
var _tile_distances: Dictionary = {}
var _prefetch_tiles: Array = []
var _prefetch_checked: Dictionary = {}
const PREFETCH_TILES := 8
const NEAR_TILE_RADIUS := 4
const CURSOR_COLLISION_UNITS := 300.0
const FAR_DETAIL_HOLD_MSEC := 10000
var _far_detail_expires_msec := 0
var _collision_sample: Array = []

func _exit_tree() -> void:
	_generation += 1
	# Release large cached resources while the scene/rendering services still
	# exist, rather than retaining them until the scripting runtime shuts down.
	if _builder != null: _builder.handover.clear()
	_builder = null
	_terrain_cache.clear()
	_goods.clear()
	_effects.clear()

func _ready() -> void:
	RenderingServer.frame_post_draw.connect(_on_rendered_frame)
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
	_collision_sample.clear()
	if not is_visible_in_tree() and _builder != null and _builder.cursor_picking: _builder.set_collision_tiles({})
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
	builder.cursor_picking = true
	builder.lazy_assets = true
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
	builder.configure_pits(model.get("standing", []))
	builder.configure_bakes(model)
	if _progress != null: _progress.text = "Loading landscape layout…"
	await builder.prepare_scenery(self, model)
	if generation != _generation: next.free(); return
	builder.configure_grade()
	if show_all_tiles:
		if _progress != null: _progress.text = "Loading continent bake…"
		await builder.prepare_continent(self)
		if generation != _generation: next.free(); return
	var infrastructure := builder.infrastructure(model, Legacy.show, not show_all_tiles)
	next.add_child(infrastructure)
	# A far-only world may never request detail. Do not retain the bound height
	# callback (builder -> road surface -> builder) while waiting for a zoom-in.
	if not builder.base_ready: builder.road_surface.finish_build()
	for s in model.get("standing", []):
		if not show_all_tiles or str(s.kind) != "house": next.add_child(builder.standing_node(s))
	if builder.base_ready:
		if not await _build_base_tiles(builder, next, model, generation, paced):
			builder.road_surface.finish_build()
			next.free()
			return
	next.add_child(builder.mine_rims_node())
	next.add_child(builder.shadows_node())
	if show_all_tiles:
		builder.finish_continent(next)
		# Cold baking may visit every tile, but its temporary detail is not the
		# runtime working set. Warm and cold openings both start with one backdrop.
		builder.release_local_tiles({})
		builder.local_streaming = true
		builder.base_ready = true
		builder.handover_enabled = true
	else:
		builder.prepare_company_pick_surface(next)
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
	_far_detail_expires_msec = 0
	_nearby_tiles.clear()
	_tile_distances.clear()
	_prefetch_tiles.clear()
	_prefetch_checked.clear()
	# The far resource is independently reusable now. Obsolete per-tile meshes
	# must not stay resident through an owned -> continent coverage switch.
	var keep: Dictionary = {}
	for tid in builder.tiles: keep[builder.terrain_key(str(tid))] = true
	for key in _terrain_cache.keys():
		if keep.has(key) and builder.base_ready: continue
		_terrain_cache.erase(key)
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

func _build_base_tiles(builder: RefCounted, parent: Node3D, model: Dictionary, generation: int, paced: bool) -> bool:
	if builder.streamed:
		var first := true
		for tid in builder.tiles:
			if not await _build_local_tile(builder, parent, model, str(tid), generation): return false
			for p in Model.hex_points(builder.tiles[tid].center):
				var v: Vector3 = builder.point(p)
				if first: builder.bounds = AABB(v, Vector3.ONE); first = false
				else: builder.bounds = builder.bounds.expand(v)
			if paced and builder.local_tiles.size() % 8 == 0:
				await get_tree().process_frame
				if generation != _generation: return false
		builder.road_surface.finish_build()
		builder._road_height_cache.clear()
		parent.add_child(builder.distant_towns(model.get("standing", [])))
		return true
	var first := true
	var built := 0
	var detail_parent := Node3D.new()
	detail_parent.name = "TileDetails"
	detail_parent.visible = not builder.base_loading
	parent.add_child(detail_parent)
	builder.labels.clear()
	for tid in builder.tiles:
		await builder.prepare_tile(self, str(tid))
		if generation != _generation: return false
		detail_parent.add_child(builder.tile_node(str(tid)))
		for p in Model.hex_points(builder.tiles[tid].center):
			var v: Vector3 = builder.point(p)
			if first: builder.bounds = AABB(v, Vector3.ONE); first = false
			else: builder.bounds = builder.bounds.expand(v)
		built += 1
		if paced and built % 8 == 0:
			if _progress != null: _progress.text = "Preparing map detail · %d / %d tiles" % [built, builder.tiles.size()]
			await get_tree().process_frame
			if generation != _generation: return false
	builder.road_surface.finish_build()
	builder._road_height_cache.clear()
	if Legacy.show.trees:
		var groves := 0
		for tid in builder.tiles:
			detail_parent.add_child(builder.trees_node(str(tid), model.get("standing", [])))
			groves += 1
			if paced and groves % 8 == 0:
				await get_tree().process_frame
				if generation != _generation: return false
	detail_parent.visible = true
	builder.base_ready = true
	builder.active_lod = -1
	return true

func _build_local_tile(builder: RefCounted, parent: Node3D, model: Dictionary, tid: String, generation: int) -> bool:
	await builder.prepare_tile(self, tid)
	if generation != _generation: return false
	var fields := ["terrain_lods", "frame_nodes", "road_nodes", "glint_nodes", "tree_nodes",
		"tree_sprite_nodes", "building_visuals", "decor_nodes", "detail_nodes", "sprite_pairs", "pickables", "glows", "smoke"]
	var offsets := {}
	for field in fields: offsets[field] = (builder.get(field) as Array).size()
	var root := Node3D.new()
	root.name = "Detail_" + tid
	parent.add_child(root)
	root.add_child(builder.tile_node(tid))
	if Legacy.show.roads: builder.append_road(root, tid)
	for standing in model.get("standing", []):
		if str(standing.kind) == "house" and str(standing.tile) == tid:
			root.add_child(builder.standing_node(standing))
	if Legacy.show.trees: root.add_child(builder.trees_node(tid, model.get("standing", [])))
	_build_glows(builder, root, offsets.glows)
	var records := {}
	for field in fields: records[field] = (builder.get(field) as Array).slice(offsets[field])
	builder.local_tiles[tid] = {"root": root, "records": records}
	root.visible = not builder._overview and (not builder.handover_enabled or builder.handover.blend > 0.0)
	builder.cache_local_tile(tid)
	return true

func _ensure_continent_detail() -> void:
	if not _streaming: await _stream_visible()

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
	var previous_overview: bool = _builder._overview
	var previous_detail := _detail
	_detail = Detail.choose(size.y / _rig.span, _detail)
	# Apply both decisions before creating assets: a far or near arrival must
	# not briefly allocate medium sprites using the previous overview state.
	_builder.set_detail(_detail, false)
	_builder.set_overview_scale(size.y / _rig.span)
	if previous_overview != _builder._overview or previous_detail != _detail: _stream_clock = 0.25

func _on_rendered_frame() -> void:
	if DisplayServer.get_name() == "headless" or not is_visible_in_tree(): return
	_advance_handover()

func _advance_handover() -> void:
	if _builder == null or not _builder.handover.active: return
	_builder.advance_handover()
	if not _builder.handover.active:
		_stream_clock = 0.25
		# Avoid freeing textures the GPU has just sampled. A quick zoom back also
		# reuses the existing medium view instead of loading it again.
		_far_detail_expires_msec = Time.get_ticks_msec() + FAR_DETAIL_HOLD_MSEC if _builder._overview and not _builder.local_tiles.is_empty() else 0

func pick_at(screen: Vector2, tiles_only: bool = false) -> Dictionary:
	_update_cursor_collision(screen)
	screen = _render_point(screen)
	if not has_content(): return {}
	var space := _viewport.find_world_3d().direct_space_state
	tiles_only = tiles_only or (_builder != null and _builder._overview)
	if _builder != null and _builder.handover_enabled and _builder.handover.blend < 1.0: tiles_only = true
	# A long orthographic ray exactly on a shared triangle edge can miss in Jolt.
	# Subpixel retries cover numerical cracks without expanding selection by a visible pixel.
	for offset in [Vector2.ZERO, Vector2(0.25, 0.25), Vector2(-0.25, -0.25)]:
		var from := _camera.project_ray_origin(screen + offset)
		var ray := PhysicsRayQueryParameters3D.create(from, from + _camera.project_ray_normal(screen + offset) * _camera.far, 1 if tiles_only else 3)
		ray.hit_back_faces = true
		var hit := _surface_ray(space, ray)
		if not hit.is_empty():
			if hit.collider.has_meta("continent_pick"):
				hit["tile_id"] = _builder.tile_at(hit.position)
				return _as_tile_hit(hit)
			if tiles_only: return hit
			if hit.collider.has_meta("standing"):
				if _building_large_enough(hit.collider): return hit
				# An undersized building must not occlude the tile below it. The
				# mine's layer-1 collider also covers its excavated terrain opening.
				var tile_ray := PhysicsRayQueryParameters3D.create(from, from + _camera.project_ray_normal(screen + offset) * _camera.far, 1)
				tile_ray.hit_back_faces = true
				var tile_hit := _surface_ray(space, tile_ray)
				if tile_hit.is_empty(): return {}
				return _as_tile_hit(tile_hit)
			# A two-world-unit halo helps hit fine building edges without swallowing
			# the yard in a tall rectangular box. Terrain, trees and roads select tiles.
			var halo := 2.0 * float(_viewport.size.y) / _rig.span
			for direction in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
				var pixel: Vector2 = screen + direction * halo
				var start := _camera.project_ray_origin(pixel)
				var near_ray := PhysicsRayQueryParameters3D.create(start, start + _camera.project_ray_normal(pixel) * _camera.far, 3)
				near_ray.hit_back_faces = true
				var neighbour := _surface_ray(space, near_ray)
				if not neighbour.is_empty() and neighbour.collider.has_meta("standing") and _building_large_enough(neighbour.collider) and neighbour.collider.get_meta("tile_id", "") == hit.collider.get_meta("tile_id", ""):
					return neighbour
			return hit
	return {}

func _surface_ray(space: PhysicsDirectSpaceState3D, ray: PhysicsRayQueryParameters3D) -> Dictionary:
	if _builder.cursor_picking: ray.collision_mask |= 4
	if _builder.handover_enabled and (_builder._overview or _builder.handover.blend == 0.0):
		# Staged/hidden local surfaces must not intercept the visible far terrain.
		var excluded: Array[RID] = ray.exclude
		for item in _builder.terrain_lods:
			if item.has("collider"): excluded.append(item.collider.get_parent().get_rid())
		ray.exclude = excluded
	var hit := space.intersect_ray(ray)
	if hit.is_empty() or not hit.collider.has_meta("continent_pick") or _builder._overview or (_builder.handover_enabled and _builder.handover.blend == 0.0): return hit
	var tid: String = _builder.tile_at(hit.position)
	if not (_builder.collision_tiles.has(tid) if _builder.cursor_picking else _builder.local_tiles.has(tid)): return hit
	# The far terrain is masked out on this tile. Its coarse surface must not
	# intercept a fine river bank or a building; outside residency it still occludes.
	ray.exclude = [_builder.continent_body.get_rid()]
	var local := space.intersect_ray(ray)
	return local if not local.is_empty() else hit

func _building_large_enough(body: Node3D) -> bool:
	if not body.has_meta("pick_bounds"): return false
	var bounds: AABB = body.get_meta("pick_bounds")
	return _pick_bounds_large_enough(body.global_transform * bounds)

func _pick_bounds_large_enough(bounds: AABB) -> bool:
	var rect := Rect2(screen_point(bounds.position), Vector2.ZERO)
	for i in 8: rect = rect.expand(screen_point(bounds.get_endpoint(i)))
	return rect.size.x > 20.0 and rect.size.y > 20.0

func _as_tile_hit(hit: Dictionary) -> Dictionary:
	# The collider may still be a mine. Activation must treat the pick as terrain.
	if hit.collider.has_meta("continent_pick"): hit["tile_id"] = _builder.tile_at(hit.position)
	hit["tiles_only"] = true
	return hit

func _activate_at(screen: Vector2, tiles_only: bool = false) -> void:
	var hit := pick_at(screen, tiles_only)
	if hit.is_empty(): return
	var body: Node = hit.collider
	var standing: Dictionary = body.get_meta("standing", {})
	tiles_only = tiles_only or bool(hit.get("tiles_only", false)) or (_builder != null and _builder._overview)
	if not tiles_only and str(standing.get("kind", "")) in ["building", "site"]:
		building_picked.emit(str(standing.iid))
	elif not tiles_only and str(standing.get("kind", "")) == "suppliers":
		suppliers_picked.emit()
	else:
		var tile := str(hit.get("tile_id", body.get_meta("tile_id", "")))
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
	# The dummy renderer has no drawn frames; permit headless scene tests to settle.
	if DisplayServer.get_name() == "headless": _advance_handover()
	_resize_viewport()
	if animate_goods: _time += delta
	_update_detail()
	if not _building: _update_cursor_collision(get_local_mouse_position())
	_update_goods()
	_update_cars()
	_stream_clock += delta
	# React to travel promptly; idle retention/prefetch still uses the slower tick.
	var stream_interval := 0.05 if capture_camera() != _stream_camera else 0.25
	if show_all_tiles and not _building and not _streaming and _stream_clock >= stream_interval:
		_stream_clock = 0.0
		_stream_visible()
	if _labels != null: _labels.queue_redraw()

func _camera_focus_tile() -> String:
	# The orbit pivot may be above the ground, especially after panning/orbiting
	# mountains. Centre the preload ring on the terrain under the screen centre.
	# Camera residency must never move detailed collision away from the cursor.
	var hit := _cursor_surface_hit(size * 0.5, false) if _builder.cursor_picking else pick_at(size * 0.5, true)
	return _builder.tile_at(hit.get("position", _rig.target))

static func cursor_collision_rings(units: float = CURSOR_COLLISION_UNITS) -> int:
	var neighbour_step := minf(Model.HEX_HALF.y * 2.0, Vector2(Model.HEX_HALF.x * 1.5, Model.HEX_HALF.y).length())
	return maxi(0, floori(units / neighbour_step))

func _cursor_collision_tiles(tid: String) -> Dictionary:
	if tid.is_empty() or not _builder.tiles.has(tid): return {}
	var wanted := {tid: true}
	var rings := cursor_collision_rings()
	if rings == 0: return wanted
	for other in _builder.tiles:
		if _hex_tile_distance(_builder.tiles[tid].center, _builder.tiles[other].center) <= rings: wanted[other] = true
	return wanted

func _cursor_surface_hit(screen: Vector2, coarse_only: bool = true) -> Dictionary:
	if _builder == null or _builder.continent_body == null: return {}
	var space := _viewport.find_world_3d().direct_space_state
	var pixel := _render_point(screen)
	for offset in [Vector2.ZERO, Vector2(0.25, 0.25), Vector2(-0.25, -0.25)]:
		var start := _camera.project_ray_origin(pixel + offset)
		var ray := PhysicsRayQueryParameters3D.create(start, start + _camera.project_ray_normal(pixel + offset) * _camera.far, 4 if coarse_only else 1)
		ray.hit_back_faces = true
		var hit := space.intersect_ray(ray) if coarse_only else _surface_ray(space, ray)
		if not hit.is_empty(): return hit
	return {}

func _update_cursor_collision(screen: Vector2) -> void:
	if _builder == null or not _builder.cursor_picking: return
	var sample := [screen, capture_camera(), size, _viewport.size, _generation, _builder.get_instance_id(),
		_builder.collision_revision, _builder.collision_detail_visible()]
	if sample == _collision_sample: return
	_collision_sample = sample
	if not Rect2(Vector2.ZERO, size).has_point(screen) or not _builder.collision_detail_visible():
		_builder.set_collision_tiles({})
		return
	var hit := _cursor_surface_hit(screen)
	var pixel := _render_point(screen)
	var start := _camera.project_ray_origin(pixel)
	var direction := _camera.project_ray_normal(pixel)
	var tid: String = _builder.tile_at(hit.position) if not hit.is_empty() else ""
	_builder.set_collision_tiles(_cursor_collision_tiles(tid))
	var ray := PhysicsRayQueryParameters3D.create(start, start + direction * _camera.far, 3)
	ray.hit_back_faces = true
	var space := _viewport.find_world_3d().direct_space_state
	var local := space.intersect_ray(ray)
	if local.is_empty() and not tid.is_empty():
		# Coarse/fine relief can put a boundary ray in different hexes. Test only
		# resident adjacent surfaces whose bounds cross this ray, one tile at a time.
		var ground_distance := INF
		for item in _builder.terrain_lods:
			if item.tile == tid or _hex_tile_distance(_builder.tiles[tid].center, _builder.tiles[item.tile].center) != 1: continue
			var bounds: AABB = item.node.global_transform * item.node.get_aabb()
			if not bounds.grow(0.1).intersects_ray(start, direction) is Vector3: continue
			_builder.set_collision_tiles(_cursor_collision_tiles(item.tile))
			var neighbour := space.intersect_ray(ray)
			if not neighbour.is_empty() and start.distance_squared_to(neighbour.position) < ground_distance:
				ground_distance = start.distance_squared_to(neighbour.position)
				local = neighbour
		if not local.is_empty(): tid = str(local.collider.get_meta("tile_id", tid))
		_builder.set_collision_tiles(_cursor_collision_tiles(tid))
	if not local.is_empty(): hit = local
	var distance := start.distance_squared_to(hit.position) if not hit.is_empty() else INF
	# A roof can project over another tile, and a mine can leave a hole in the
	# coarse surface. Cheap bounds nominate candidate tiles; exact silhouettes
	# decide the hit. Only one tile's detailed collision is attached at a time.
	var candidates: Array = []
	for pair in _builder.sprite_pairs:
		if not pair.get("standing") is Dictionary or str(pair.standing.kind) not in ["building", "site", "warehouse", "suppliers"]: continue
		if str(pair.tile) == tid: continue
		var dimension: Vector3 = pair.dimension
		var bounds: AABB = pair.root.global_transform * AABB(Vector3(-dimension.x * 0.5, 0, -dimension.z * 0.5), dimension)
		var crossing: Variant = bounds.grow(2.0).intersects_ray(start, direction)
		if crossing is Vector3 and start.distance_squared_to(crossing) < distance and _pick_bounds_large_enough(bounds):
			candidates.append({"tile": str(pair.tile), "distance": start.distance_squared_to(crossing)})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.distance < b.distance)
	var checked := {tid: true}
	for candidate in candidates:
		if candidate.distance >= distance: break
		if checked.has(candidate.tile): continue
		checked[candidate.tile] = true
		_builder.set_collision_tiles(_cursor_collision_tiles(candidate.tile))
		local = space.intersect_ray(ray)
		if local.is_empty() or not local.collider.has_meta("standing") or not _building_large_enough(local.collider): continue
		var local_distance := start.distance_squared_to(local.position)
		if local_distance < distance:
			distance = local_distance
			tid = candidate.tile
	_builder.set_collision_tiles(_cursor_collision_tiles(tid))

static func _hex_tile_distance(a: Vector2, b: Vector2) -> int:
	# Flat-top hex centres use 405 x 480 spacing. Axial coordinates handle
	# staggered columns, negative positions and arbitrary map origins alike.
	var delta := b - a
	var q := roundi(delta.x / (Model.HEX_HALF.x * 1.5))
	var r := roundi(delta.y / (Model.HEX_HALF.y * 2.0) - q * 0.5)
	return maxi(absi(q), maxi(absi(r), absi(q + r)))

func _wanted_detail_tiles() -> Array:
	var wanted: Array = []
	_nearby_tiles.clear()
	_tile_distances.clear()
	_prefetch_tiles.clear()
	if _builder == null or _builder._overview: return wanted
	var view := Rect2(Vector2.ZERO, size)
	var buffered := view.grow(120.0)
	var nearby := buffered.grow(540.0 * size.y / _rig.span)
	var direction: Vector3 = _rig.target - (_stream_camera.get("target", _rig.target) as Vector3)
	var focus := _camera_focus_tile() if _detail == 2 else ""
	for tid in _builder.tiles:
		var near := focus != "" and _hex_tile_distance(_builder.tiles[focus].center, _builder.tiles[tid].center) <= NEAR_TILE_RADIUS
		var points: PackedVector3Array = _builder.tile_view_hull(str(tid))
		var at := points[0]
		_tile_distances[tid] = at.distance_squared_to(_rig.target)
		var behind := _camera.is_position_behind(at)
		if behind and not near: continue
		var bounds := Rect2(screen_point(at), Vector2.ZERO)
		for p in points: bounds = bounds.expand(screen_point(p))
		bounds = bounds.grow(40.0)
		if near or bounds.intersects(nearby): _nearby_tiles[tid] = true
		if near or bounds.intersects(buffered):
			wanted.append({"tile": str(tid), "visible": not behind and bounds.intersects(view), "near": near, "distance": _tile_distances[tid]})
		elif bounds.intersects(nearby):
			_prefetch_tiles.append({"tile": str(tid), "distance": _tile_distances[tid],
				"ahead": direction.length_squared() > 1.0 and direction.dot(at - _rig.target) > 0.0})
	wanted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.visible != b.visible: return a.visible
		if a.near != b.near: return a.near
		return a.distance < b.distance)
	_prefetch_tiles.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.ahead != b.ahead: return a.ahead
		return a.distance < b.distance)
	# The node allowance limits extra buffering, never visible/radius coverage.
	# Shallow angles can expose more than 96 tiles at the widest local zoom.
	var required_count := wanted.filter(func(item: Dictionary) -> bool: return item.visible or item.near).size()
	if wanted.size() > maxi(Builder.BASE_RESIDENT_TILES, required_count): wanted.resize(maxi(Builder.BASE_RESIDENT_TILES, required_count))
	if _prefetch_tiles.size() > PREFETCH_TILES: _prefetch_tiles.resize(PREFETCH_TILES)
	return wanted

func _fine_detail_plan(wanted: Array) -> Dictionary:
	var plan := {}
	if _detail <= 0: return plan
	for item in wanted:
		# The complete four-ring neighbourhood stays ready, including offscreen
		# tiles. Visible terrain beyond that radius still receives medium detail.
		if _detail == 2 and item.get("near", false): plan[item.tile] = 2
		elif item.visible: plan[item.tile] = 1
	return plan

func _maintain_resource_cache() -> void:
	var now := Time.get_ticks_msec()
	if not _builder._overview:
		for tid in _builder.local_tiles: _builder.resource_cache.touch(tid, now)
	_builder.resource_cache.trim(now, _builder.local_tiles, _nearby_tiles if not _builder._overview else {}, _tile_distances)

func _prefetch_resources(builder: RefCounted, generation: int, camera_state: Dictionary) -> void:
	if builder._overview: return
	var attempted := 0
	for item in _prefetch_tiles:
		if _prefetch_checked.has(item.tile): continue
		if not builder.resource_cache.can_prefetch(): break
		_prefetch_checked[item.tile] = true
		builder.prefetch_medium(item.tile)
		attempted += 1
		await get_tree().process_frame
		if generation != _generation or camera_state != capture_camera() or attempted >= 2: break

func _stream_visible() -> void:
	if _builder == null or not _builder.streamed or _streaming or _building: return
	if _builder.handover.active: return
	var camera_state := capture_camera()
	var far_expired: bool = _builder._overview and _far_detail_expires_msec > 0 and Time.get_ticks_msec() >= _far_detail_expires_msec
	var changed := _stream_generation != _generation or _stream_camera != camera_state or _stream_tier != _detail
	_streaming = true
	var generation := _generation
	var builder: RefCounted = _builder
	if not changed and not far_expired:
		_maintain_resource_cache()
		await _prefetch_resources(builder, generation, camera_state)
		_streaming = false
		return
	_prefetch_checked.clear()
	var wanted := _wanted_detail_tiles()
	var keep := {}
	for item in wanted: keep[item.tile] = true
	var hold_far_detail: bool = builder._overview and Time.get_ticks_msec() < _far_detail_expires_msec
	if hold_far_detail:
		for tid in builder.local_tiles: keep[tid] = true
	if not builder._overview:
		# Start the existing unused-resource grace period at departure, even if
		# the previous streaming pass took longer than the normal idle tick.
		var now := Time.get_ticks_msec()
		for tid in builder.local_tiles: builder.resource_cache.touch(tid, now)
	builder.release_local_tiles(keep, true)
	if far_expired: _far_detail_expires_msec = 0
	var slice_start := Time.get_ticks_usec()
	for item in wanted:
		if builder.local_tiles.has(item.tile): continue
		if not await _build_local_tile(builder, _content, _model, item.tile, generation): break
		builder.apply_tile_detail(builder.terrain_lods[-1], _detail)
		# Cached tiles share a small frame budget instead of paying a whole frame
		# apiece. Newly built roots remain hidden behind the far fallback until ready.
		if Time.get_ticks_usec() - slice_start >= 4000:
			builder._apply_view_visibility()
			await get_tree().process_frame
			slice_start = Time.get_ticks_usec()
			if generation != _generation or camera_state != capture_camera(): break
	builder.road_surface.finish_build()
	builder._road_height_cache.clear()
	if generation == _generation and camera_state == capture_camera() and not hold_far_detail:
		builder._apply_view_visibility()
		var fine := _fine_detail_plan(wanted)
		builder.release_detail(fine, true)
		var terrain_by_tile := {}
		for item in builder.terrain_lods: terrain_by_tile[item.tile] = item
		slice_start = Time.get_ticks_usec()
		# Follow current viewport priority even when old offscreen tiles were
		# inserted into terrain_lods before newly visible tiles after a pan.
		for request in wanted:
			if not fine.has(request.tile): continue
			var item: Dictionary = terrain_by_tile[request.tile]
			await builder.refine_tile(self, item, int(fine[item.tile]))
			if generation != _generation or camera_state != capture_camera(): break
			if Time.get_ticks_usec() - slice_start >= 4000:
				await get_tree().process_frame
				slice_start = Time.get_ticks_usec()
				if generation != _generation or camera_state != capture_camera(): break
	if generation == _generation and camera_state == capture_camera():
		for tid in builder.local_tiles: builder.cache_local_tile(str(tid))
		_stream_camera = camera_state
		_stream_generation = generation
		_stream_tier = _detail
		_maintain_resource_cache()
		builder.complete_detail_request()
	_streaming = false

func detail_ready() -> bool:
	return not _building and not _streaming and (_builder == null or not _builder.handover.active)

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


func _build_glows(builder: RefCounted, parent: Node3D, from_index: int = 0) -> void:
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
	for item in builder.glows.slice(from_index):
		var quad := QuadMesh.new()
		quad.size = item.size
		var node := Geo.instance(quad, glow_material)
		node.position = item.point
		parent.add_child(node)
		builder.detail_nodes.append({"node": node, "minimum": 1})

func _build_effects(builder: RefCounted, parent: Node3D) -> Array:
	_build_glows(builder, parent)
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
