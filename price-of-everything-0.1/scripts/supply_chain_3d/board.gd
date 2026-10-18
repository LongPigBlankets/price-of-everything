extends Control
## A real, isolated 3D world for the supply-chain overview. The regular map still owns
## its Camera2D, rendering and input. Rebuilding never changes this camera's orbit.
signal building_picked(iid: String)
signal suppliers_picked
signal tile_picked(tile_id: String)
const StreamReadAhead = preload("res://scripts/supply_chain_3d/stream_read_ahead.gd")
var stream_read_ahead_stats := {}
const TileOverlay := preload("res://scripts/supply_chain_3d/tile_overlay.gd")
const WorldSnapshot := preload("res://scripts/supply_chain_3d/world_snapshot.gd")
static var _shipped_key := ""
static var _shipped_model := {}
static var _shipped_index := {}
var _ground: RefCounted = null
var _ground_key: Array = []
var _asset_drain := false
var _cars_source: Array = []
var _cars_by_tile: Dictionary = {}
var _cars_shown_tiles: Dictionary = {}
var _label_source: Array = []
var _label_selection := ""
var _label_count := -1
var _label_order: Array = []
var _warm_camera: Dictionary = {}
const HIDDEN_RELEASE_MSEC := 10000
var _hidden_since := 0
var _released_while_hidden := false

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
const LayoutQueries := preload("res://scripts/supply_chain_3d/layout_queries.gd")
const BackgroundLoad := preload("res://scripts/supply_chain_3d/background_load.gd")
const BackgroundWorld := preload("res://scripts/supply_chain_3d/background_world.gd")
const PaperMap := preload("res://scripts/supply_chain_3d/paper_map.gd")
const ProgressiveTile := preload("res://scripts/supply_chain_3d/progressive_tile.gd")
## Offline packaging may prove that an upstream layout memo is still valid.
## Empty in normal play; this does not alter source fingerprints or cache reads.
static var offline_layout_reuse := Callable()
var _loading_ink := {}
var _paper: Node3D
var _paper_owner: Node3D
var _owned_center := Vector2.ZERO
var _reveal_started := 0
var reveal_profile := {"tiles":[]}
## Soot around a smoking stack: how far it reaches over the ground, and how much one stack adds.
const SOOT_REACH := 450.0
const SOOT_PER_STACK := 0.8
const SMOG_COLOUR := Color(0.31, 0.28, 0.25, 0.17)
const SMOG_SPREAD := 300.0
const SMOG_SIZE := 280.0
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
var _last_evening := false
var _effects: Array = []
var _labels: Control
var _detail := -1
var _tokens := Tokens.new()
var show_all_tiles := false
var _last_all_tiles := false
var _coverage: OptionButton
## Session switch: evening lights every town, daylight lights only polluted tiles.
static var evening := false
var _light: OptionButton
var _environment: Environment
var _progress: Label
var _fit_after_build := false
var _medium_after_build := false
var _opened := false
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
## Timings separate layout work, disk reads and scene setup from GPU/streaming.
var load_profile: Dictionary = {}
var _layout_queries: RefCounted
var _coverage_states := {}
var _warming: RefCounted
var _requested_all_tiles := false
var background_profile := {}
var background_status := "idle"
const SCENE_BUDGET_USEC := 4000
const RENDER_BUDGET_PIXELS := 2560 * 1440
static var render_budget_pixels := RENDER_BUDGET_PIXELS
## Tools only: simulate a high-density screen on an ordinary capture window.
static var density_override := 0.0

func _discard_background() -> void:
	_release_paper_owner()
	_requested_all_tiles = show_all_tiles
	if _warming != null: _warming.cancelled = true
	_warming = null
	for packet in _coverage_states.values():
		if packet.content != _content and is_instance_valid(packet.content):
			packet.builder.handover.clear()
			packet.builder.road_surface.finish_build()
			packet.content.free()
	_coverage_states.clear()
	background_status = "idle"
	if is_instance_valid(_paper): _paper.queue_free()
	_paper = null
	_loading_ink = {}

func background_ready() -> bool:
	return _coverage_states.has(true)

func background_active() -> bool:
	return _warming != null and not _warming.done

func _show_paper() -> void:
	if not is_instance_valid(_paper) and is_instance_valid(_last_terrain):
		var centres := {}
		for coord in _last_terrain.get("tiles"):
			var tid := "tile_%d_%d" % [coord.x+1,coord.y+1]
			centres[tid] = Model.tile_center(_last_terrain, tid)
		_paper = PaperMap.new()
		_paper.configure(centres)
		_world.add_child(_paper)
	_sync_paper()

func _sync_paper() -> void:
	if not is_instance_valid(_paper): return
	_paper.visible = _requested_all_tiles and (_builder == null or not _builder.streamed or _builder.backdrop_pending or (_builder.loading_reveal != null and _builder.loading_reveal.active))
	if _paper.visible and _builder != null:
		var covered: Dictionary = _builder.ready_tiles.duplicate() if _builder.streamed else _builder.tiles.duplicate()
		if _builder.loading_reveal != null and _builder.loading_reveal.active: covered = _builder.loading_reveal.complete.duplicate()
		covered.merge(_builder.paper_owned_tiles)
		_paper.cover(covered)

func _visible_paper_tiles() -> Dictionary:
	var result := {}
	if not is_instance_valid(_paper): return result
	var view := Rect2(Vector2.ZERO,size).grow(60.0)
	for tid in _paper.tiles:
		var at: Vector2 = _paper.tiles[tid]
		if _camera.is_position_behind(Vector3(at.x,PaperMap.HEIGHT,at.y)): continue
		var bounds := Rect2(screen_point(Vector3(at.x,PaperMap.HEIGHT,at.y)),Vector2.ZERO)
		for p in Model.hex_points(at): bounds = bounds.expand(screen_point(Vector3(p.x,PaperMap.HEIGHT,p.y)))
		if _builder != null and _builder.streamed and _builder.tiles.has(tid):
			for p in _builder.tile_view_hull(tid): bounds=bounds.expand(screen_point(p))
		if bounds.intersects(view): result[tid]=true
	return result

func _start_tile_reveal(builder: RefCounted, tid: String) -> void:
	# Infrastructure arrives with the backdrop; local terrain alone is not ready.
	# Colour also waits for budgeted building cards/models to finish appearing.
	if builder.backdrop_pending or builder.asset_tier_pending or (not builder._overview and not builder.tile_ready(tid)): return
	if builder.loading_reveal == null or not builder.loading_reveal.start(tid): return
	if is_instance_valid(_paper) and _loading_ink.has(tid): _paper.draw_tile(tid,_loading_ink[tid])

func _start_backdrop_reveals(builder: RefCounted) -> void:
	if builder.loading_reveal == null or not builder.loading_reveal.active: return
	var now := Time.get_ticks_msec()
	if now<builder.loading_reveal.next_backdrop_msec: return
	var visible_tiles := _visible_paper_tiles()
	# A high mountain's paper footprint may be on screen while its actual hull
	# is outside it. Only wait for detail that the streaming planner requests.
	if not builder._overview:
		var requested := {}
		for item in _wanted_detail_tiles(): requested[item.tile]=true
		for tid in visible_tiles.keys():
			if not requested.has(tid): visible_tiles.erase(tid)
	var ordered: Array = []
	for tid in builder.tiles:
		if builder.loading_reveal.complete.has(tid) or builder.loading_reveal.elapsed.has(tid): continue
		if visible_tiles.has(tid):
			if builder._overview or builder.tile_ready(tid): ordered.append(tid)
		else: builder.loading_reveal.skip(tid)
	var focus := Vector2(_rig.target.x,_rig.target.z)
	ordered.sort_custom(func(a,b): return (builder.tiles[a].center as Vector2).distance_squared_to(focus)<(builder.tiles[b].center as Vector2).distance_squared_to(focus))
	# The far resource arrives as one object, but should not replace every paper
	# tile in the same frame. Spread it outward, following the current camera.
	# Scale the batch at very wide zoom so a whole continent does not take minutes.
	var budget := maxi(2,ceili(visible_tiles.size()/20.0))
	for tid in builder.loading_reveal.backdrop_batch(ordered,now,budget):
		if is_instance_valid(_paper) and _loading_ink.has(tid): _paper.draw_tile(tid,_loading_ink[tid])

func _tile_is_paper(tid: String) -> bool:
	return _builder != null and _builder.loading_reveal != null and _builder.loading_reveal.active and not _builder.loading_reveal.complete.has(tid)

func _advance_tile_reveals(delta: float) -> void:
	if _builder == null or _builder.loading_reveal == null or not _requested_all_tiles: return
	var reveal: RefCounted = _builder.loading_reveal
	if reveal.active and not _builder.backdrop_pending: _start_backdrop_reveals(_builder)
	if reveal.active: reveal.advance(delta,true)
	if is_instance_valid(_paper):
		for tid in reveal.elapsed: _paper.set_time(tid,reveal.elapsed[tid])
	if not reveal.active and not _builder.backdrop_pending:
		if not _builder.handover.active: reveal.restore()
		_loading_ink = {}
		if is_instance_valid(_paper): _paper.clear_drawings()

func _release_paper_owner() -> void:
	if is_instance_valid(_paper_owner) and _paper_owner.get_parent()==_world:
		_world.remove_child(_paper_owner)
	_paper_owner = null
	if _builder != null: _builder.paper_owned_tiles.clear()

func _release_ready_paper_owner(builder: RefCounted) -> void:
	if builder != _builder or builder.backdrop_pending or not is_instance_valid(_paper_owner): return
	if not builder._overview:
		for request in _wanted_detail_tiles():
			if builder.paper_owned_tiles.has(request.tile) and not builder.tile_ready(request.tile): return
	_release_paper_owner()
	builder._apply_view_visibility()

func _publish_background(packet: Dictionary, job: RefCounted) -> void:
	if job.cancelled or _warming != job: return
	_coverage_states[true] = packet
	background_status = "tiles_ready"
	if _requested_all_tiles:
		show_all_tiles = true
		_activate(packet)

func _backdrop_ready(builder: RefCounted) -> void:
	if builder != _builder: return
	_start_backdrop_reveals(builder)
	_release_ready_paper_owner(builder)
	if _reveal_started>0: reveal_profile.backdrop_ms = Time.get_ticks_msec()-_reveal_started
	builder.set_overview_scale(size.y/_rig.span, true)
	_stream_generation = -1
	_sync_paper()

func _start_background() -> void:
	if show_all_tiles or _building or _builder == null or background_active() or background_ready(): return
	if DisplayServer.get_name() == "headless" or "--no-background-continent" in OS.get_cmdline_user_args(): return
	var job := BackgroundLoad.new()
	_warming = job
	background_status = "loading"
	if _coverage != null: _coverage.set_item_text(1, "Show all tiles (preparing…)")
	# Yield before any work; owned coverage is already usable and the loading
	# screen never waits for the continent's readiness.
	await get_tree().process_frame
	if job.cancelled: job.done = true; return
	var packet := await BackgroundWorld.prepare(self, job, _generation)
	job.done = true
	if job.cancelled or _warming != job: return
	background_profile = job.profile
	if not packet.is_empty():
		_coverage_states[true] = packet
		background_status = "ready"
	else:
		# A changed world must use its normal rebuild path, never stale scenery.
		background_status = "unavailable"
		job.resources.clear()
		if _requested_all_tiles: set_all_tiles.call_deferred(true, false)
	if _coverage != null: _coverage.set_item_text(1, "Show all tiles")
	print("[CONTINENT BACKGROUND] ", background_status, " ", JSON.stringify(background_profile))

func _exit_tree() -> void:
	_generation += 1
	_discard_background()
	# Release large cached resources while the scene/rendering services still
	# exist, rather than retaining them until the scripting runtime shuts down.
	if _builder != null:
		_builder.handover.clear()
		_builder.road_surface.finish_build()
	_builder = null
	_terrain_cache.clear()
	_goods.clear()
	_effects.clear()

func _ready() -> void:
	RenderingServer.frame_post_draw.connect(_on_rendered_frame)
	# Coverage is session-local: every new board opens on the company.
	show_all_tiles = false
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
	_environment = environment.environment
	_apply_light()
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
	_light = OptionButton.new()
	_light.name = "Light"
	_light.add_item("Daylight")
	_light.add_item("Evening")
	_light.selected = 1 if evening else 0
	_light.focus_mode = Control.FOCUS_NONE
	_light.item_selected.connect(func(index: int) -> void: set_evening(index == 1))
	controls.add_child(_light)
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
	var reset := Button.new()
	reset.text = "Reset view"
	reset.tooltip_text = "Frame the current map and restore the default angle (Home)"
	reset.focus_mode = Control.FOCUS_NONE
	reset.theme_type_variation = &"Outlined"
	reset.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	reset.offset_left = -164
	reset.offset_top = -102
	reset.offset_right = -24
	reset.offset_bottom = -58
	reset.pressed.connect(reset_view)
	add_child(reset)

func _visibility() -> void:
	_drag_button = 0
	_collision_sample.clear()
	if not is_visible_in_tree() and _builder != null and _builder.cursor_picking: _builder.set_collision_tiles({})
	if _viewport != null:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if is_visible_in_tree() else SubViewport.UPDATE_DISABLED
	if _world != null: _world.process_mode = Node.PROCESS_MODE_INHERIT if is_visible_in_tree() else Node.PROCESS_MODE_DISABLED
	set_process(is_visible_in_tree())
	set_process_unhandled_key_input(is_visible_in_tree())
	if _viewport == null: return
	if is_visible_in_tree():
		_hidden_since = 0
		_resize_viewport()
		if _released_while_hidden:
			_released_while_hidden = false
			_stream_camera = {} # rebuild the visible tiles released while away
	else:
		# The multisampled render targets stay allocated while hidden unless shrunk.
		_viewport.size = Vector2i(2, 2)
		_hidden_since = Time.get_ticks_msec()
		_release_when_hidden(_hidden_since)

func _release_when_hidden(stamp: int) -> void:
	# Away from the 3D view for HIDDEN_RELEASE_MSEC: treat every continent tile as
	# offscreen so its video memory is released, except the company's own tiles.
	await get_tree().create_timer(HIDDEN_RELEASE_MSEC / 1000.0).timeout
	if _hidden_since != stamp or is_visible_in_tree() or _builder == null or not _builder.streamed or _building or _streaming: return
	var now := Time.get_ticks_msec()
	_builder.release_local_tiles({}, true, true)
	_builder.resource_cache.owned = _company_tiles()
	_builder.resource_cache.age(now, {}, {})
	_builder.resource_cache.trim(now, {}, {})
	_released_while_hidden = true
	_drain_asset_tier()

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

func set_evening(value: bool) -> void:
	if evening == value: return
	evening = value
	if _light != null: _light.selected = 1 if value else 0
	_apply_light()
	# The continent is the shipped daylight package, so there only the grade changes.
	# The company scene relights now, or when the map returns to it.
	if show_all_tiles or not is_instance_valid(_last_terrain): return
	await _build(_last_graph, _last_terrain, true)

## Evening is a per-channel curve after the tonemap: mid tones drop and cool, while the
## brightest values (lit windows, lamp glows) keep their warmth.
func _apply_light() -> void:
	if _environment == null: return
	_environment.adjustment_enabled = evening
	if not evening:
		_environment.adjustment_color_correction = null
		return
	var curve := Gradient.new()
	curve.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
	curve.colors = PackedColorArray([Color(0.03, 0.035, 0.10), Color(0.14, 0.15, 0.25),
		Color(0.34, 0.35, 0.45), Color(0.63, 0.61, 0.68), Color(1.0, 0.96, 0.92)])
	var lut := GradientTexture1D.new()
	lut.gradient = curve
	lut.width = 256
	_environment.adjustment_color_correction = lut

func set_all_tiles(value: bool, _persist: bool = true) -> void:
	_requested_all_tiles = value
	if value:
		_reveal_started = Time.get_ticks_msec()
		reveal_profile = {"tiles":[]}
		_show_paper()
	else: _sync_paper()
	if not value and not show_all_tiles:
		if _coverage != null: _coverage.selected = 0
		if _progress != null and not _building: _progress.hide()
		return
	if value and not show_all_tiles and background_active() and not background_ready():
		if _coverage != null: _coverage.selected = 1
		_medium_view()
		if _progress != null:
			_progress.text = "Unfolding the map…"
			_progress.show()
		return
	if show_all_tiles == value: return
	show_all_tiles = value
	if _coverage != null: _coverage.selected = 1 if value else 0
	_fit_after_build = not value
	_medium_after_build = value
	# A company scene built in the other light is rebuilt rather than reused.
	if _coverage_states.has(value) and (value or _coverage_states[value].builder.evening == evening):
		_activate(_coverage_states[value])
	elif is_instance_valid(_last_terrain):
		await _build(_last_graph, _last_terrain, true)

func _build(graph: Dictionary, terrain: Node, paced: bool) -> void:
	var started := Time.get_ticks_usec()
	var stage := started
	var timings := {}
	_last_graph = graph
	_last_terrain = terrain
	_generation += 1
	_discard_background()
	var generation := _generation
	_building = true
	var next := Node3D.new()
	next.name = "Company"
	var builder := Builder.new()
	builder.streamed = show_all_tiles
	builder.evening = evening
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
	# The terrain sampler only depends on the map. Reuse it, with its filled
	# caches, for every company rebuild of the same map.
	var ground_key := [terrain.get_instance_id(), river_lines.size(), Legacy.plate_town]
	if _ground_key != ground_key or _ground == null:
		_ground = preload("res://scripts/supply_chain_3d/coast.gd").ground_for(terrain, rivers, Relief.plates(terrain, river_lines), true)
		_ground_key = ground_key
	builder.ground = _ground
	if preload("res://scripts/supply_chain_3d/stoneshore_trial.gd").preview_enabled():
		extra_tiles = preload("res://scripts/supply_chain_3d/stoneshore_trial.gd").TILES.duplicate()
	var water := Legacy._water_test(terrain)
	# Layout passes share static memo tables between prepare() and finish().
	await _lock_layout("build:%d" % generation)
	if generation != _generation: _unlock_layout("build:%d" % generation); next.free(); return
	var queries := LayoutQueries.new()
	var geography: Array = []
	for coord in terrain.get("tiles"):
		var tid := "tile_%d_%d" % [coord.x + 1, coord.y + 1]
		geography.append([tid, Model.tile_center(terrain, tid), Catalog.tile_type(tid)])
	queries.prepare(builder.bake_cache, [geography, builder.ground.get("bands"), builder.ground.get("lakes"),
		builder.ground.get("rivers"), HillBaked.sea()], water)
	var true_positions := _true_positions(graph, terrain)
	timings.layout_inputs_ms = (Time.get_ticks_usec() - stage) / 1000.0
	var solve_started := Time.get_ticks_usec()
	var model := {}
	var shipped := {} if show_all_tiles else _shipped_world(builder.bake_cache)
	timings.shipped_ms = (Time.get_ticks_usec() - solve_started) / 1000.0
	if not shipped.is_empty():
		# The company is the shipped world's tiles, with only the tiles whose
		# contents changed laid out again.
		var company := {}
		for tid in extra_tiles: company[str(tid)] = true
		for n in graph.get("nodes", []):
			if str(n.get("tile_id", "")) != "": company[str(n.tile_id)] = true
		await get_tree().process_frame
		if generation != _generation: next.free(); return
		var overlay: Dictionary = await TileOverlay.prepare(self, shipped, builder.ground, builder.bake_cache, company.keys(), queries, func() -> bool: return generation == _generation)
		if generation != _generation: next.free(); return
		if not overlay.is_empty():
			var restrict_started := Time.get_ticks_usec()
			if _shipped_index.is_empty(): _shipped_index = TileOverlay.index(shipped, builder.ground)
			model = TileOverlay.restrict(overlay.model, overlay.probe, overlay.tiles, builder.ground, _shipped_index)
			preload("res://scripts/supply_chain_3d/authored_region.gd").reroute_flows(model, model.authored_region.tiles, model.roads)
			timings.overlay = overlay.profile
			timings.restrict_ms = (Time.get_ticks_usec() - restrict_started) / 1000.0
	if model.is_empty():
		model = Model.build(terrain, graph, true_positions, river_lines, Legacy.plate_town and Legacy.show.decor,
			water, Legacy._shore_test(terrain), extra_tiles)
		if preload("res://scripts/supply_chain_3d/stoneshore_trial.gd").preview_enabled():
			preload("res://scripts/supply_chain_3d/stoneshore_trial.gd").restrict_model(model)
		_solve_layout(model, terrain, rivers, queries, builder, water, timings)
	timings.layout_solve_ms = (Time.get_ticks_usec() - solve_started) / 1000.0
	if not show_all_tiles:
		await get_tree().process_frame
		if generation != _generation: next.free(); return
	queries.finish(builder.bake_cache)
	_unlock_layout("build:%d" % generation)
	_layout_queries = queries
	timings.model_ms = (Time.get_ticks_usec() - stage) / 1000.0
	stage = Time.get_ticks_usec()
	if show_all_tiles: print("[CONTINENT BUILD] model ready ", Time.get_ticks_msec())
	if model == _model and Legacy.show == _last_show and show_all_tiles == _last_all_tiles and evening == _last_evening:
		_building = false
		if _progress != null: _progress.hide()
		next.free()
		_coverage_states[show_all_tiles] = {"content": _content, "builder": _builder, "model": _model,
			"goods": _goods, "effects": _effects, "profile": load_profile}
		if not show_all_tiles: _start_background.call_deferred()
		return
	builder.tiles = model.get("tiles", {})
	builder.rivers = rivers
	# Stable origin: expanding the company does not move existing terrain under the camera.
	builder.origin = Vector2.ZERO
	builder.configure_pits(model.get("standing", []))
	if not show_all_tiles:
		await get_tree().process_frame
		if generation != _generation: next.free(); return
		await builder.presolve_alignment(self, model, func() -> bool: return generation == _generation)
		if generation != _generation: next.free(); return
	builder.prepare_transport(model)
	timings.transport = builder.transport_profile.duplicate()
	builder.configure_bakes(model)
	timings.keys_ms = (Time.get_ticks_usec() - stage) / 1000.0
	if not show_all_tiles:
		await get_tree().process_frame
		if generation != _generation: next.free(); return
	stage = Time.get_ticks_usec()
	if _progress != null: _progress.text = "Loading landscape layout…"
	await builder.prepare_scenery(self, model)
	if not is_instance_valid(self): next.free(); return
	timings.scenery_ms = (Time.get_ticks_usec() - stage) / 1000.0
	if not show_all_tiles:
		await get_tree().process_frame
		if generation != _generation: next.free(); return
	stage = Time.get_ticks_usec()
	if generation != _generation: next.free(); return
	builder.configure_grade()
	if show_all_tiles:
		if _progress != null: _progress.text = "Loading continent bake…"
		await builder.prepare_continent(self)
		if generation != _generation: next.free(); return
	timings.continent_ms = (Time.get_ticks_usec() - stage) / 1000.0
	stage = Time.get_ticks_usec()
	next.free()
	var packet := await _assemble(builder, model, generation, paced or not show_all_tiles, timings)
	if packet.is_empty(): return
	timings.total_ms = (Time.get_ticks_usec() - started) / 1000.0
	packet.profile = timings
	_activate(packet)

## One layout at a time: the passes swap static memo tables in and out, so a
## company rebuild and the background continent must not interleave. An owner
## abandoned by a newer build releases the lock.
var _layout_owner := ""
func _lock_layout(owner: String) -> void:
	while _layout_owner != "" and _layout_owner != owner and _layout_owner_alive():
		await get_tree().process_frame
	_layout_owner = owner

func _unlock_layout(owner: String) -> void:
	if _layout_owner == owner: _layout_owner = ""

func _layout_owner_alive() -> bool:
	if _layout_owner.begins_with("build:"): return int(_layout_owner.trim_prefix("build:")) == _generation and _building
	if _layout_owner.begins_with("background:"): return _warming != null and str(_warming.get_instance_id()) == _layout_owner.trim_prefix("background:") and not _warming.cancelled
	return false

## The shipped world snapshot's model, decoded once per session. Never mutated.
func _shipped_world(cache: RefCounted) -> Dictionary:
	if preload("res://scripts/supply_chain_3d/stoneshore_trial.gd").preview_enabled(): return {}
	var manifest_path: String = cache.bundled_directory.path_join("manifest.json")
	if not FileAccess.file_exists(manifest_path): return {}
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not manifest is Dictionary or not manifest.get("complete", false): return {}
	var key := str(manifest.get("world_snapshot_key", ""))
	if key.is_empty(): return {}
	if _shipped_key != key:
		var data: Dictionary = cache.read(key)
		if data.is_empty() or not WorldSnapshot.usable_base(data, manifest): return {}
		_shipped_model = data.model
		_shipped_index = {}
		_shipped_key = key
	return _shipped_model

## The presentation layout passes, in order, for whatever tiles the model holds:
## the company, the whole continent, or only the tiles that differ from the
## shipped base (tile_overlay.gd).
func _solve_layout(model: Dictionary, terrain: Node, rivers: Dictionary, queries: RefCounted, builder: RefCounted, water: Callable, timings: Dictionary, fit_roads: Array = []) -> void:
	var road_started := Time.get_ticks_usec()
	preload("res://scripts/supply_chain_3d/authored_region.gd").apply(model, terrain, get_tree().get_first_node_in_group("building_footprints"), queries.data, builder.surface_height)
	preload("res://scripts/supply_chain_3d/riverside_fields.gd").apply(model, rivers, queries.data)
	timings.road_import_ms = (Time.get_ticks_usec() - road_started) / 1000.0
	road_started = Time.get_ticks_usec()
	preload("res://scripts/supply_chain_3d/harbour.gd").apply(model)
	preload("res://scripts/supply_chain_3d/rail_network.gd").apply(model, terrain, water, builder.surface_height)
	preload("res://scripts/supply_chain_3d/rail_station.gd").apply(model,builder.surface_height)
	preload("res://scripts/supply_chain_3d/depot_roads.gd").apply(model,queries.data)
	preload("res://scripts/supply_chain_3d/port_approach.gd").apply(model,builder.surface_height,queries.data)
	preload("res://scripts/supply_chain_3d/district_blocks.gd").new().apply(model, builder.surface_height, builder.open_water, queries.data)
	print("[LAYOUT] districts ready ",Time.get_ticks_msec())
	preload("res://scripts/supply_chain_3d/street_curves.gd").apply(model,builder.surface_height,builder.open_water,Builder.standing_key,queries.data)
	print("[LAYOUT] curves ready ",Time.get_ticks_msec())
	if Legacy.plate_town and Legacy.show.decor: preload("res://scripts/supply_chain_3d/stoneshore_trial.gd").populate(model, terrain)
	print("[LAYOUT] seeds ready ",Time.get_ticks_msec())
	if offline_layout_reuse.is_valid(): offline_layout_reuse.call(model,queries.data,rivers,Builder.standing_key)
	# A tile overlay keeps the shipped road network; its buildings fit those roads.
	if not fit_roads.is_empty(): model.roads = fit_roads.duplicate()
	preload("res://scripts/supply_chain_3d/road_placement.gd").new().fit(model, builder.surface_height, builder.open_water, Builder.standing_key, rivers, queries.data)
	timings.road_frontage_ms = (Time.get_ticks_usec() - road_started) / 1000.0
	road_started = Time.get_ticks_usec()
	preload("res://scripts/supply_chain_3d/authored_region.gd").reroute_flows(model, model.authored_region.tiles, model.roads)
	preload("res://scripts/supply_chain_3d/rail_network.gd").apply(model, terrain, water, builder.surface_height)
	timings.road_routing_ms = (Time.get_ticks_usec() - road_started) / 1000.0

func _assemble(builder: RefCounted, model: Dictionary, generation: int, paced: bool, timings: Dictionary) -> Dictionary:
	var stage := Time.get_ticks_usec()
	var next := Node3D.new()
	next.name = "Continent" if builder.streamed else "Company"
	if paced and not builder.streamed:
		await builder.prebake_roads(self, model, Legacy.show, func() -> bool: return generation == _generation)
		if generation != _generation: next.free(); return {}
		stage = Time.get_ticks_usec()
	var infrastructure: Node3D = builder.infrastructure(model, Legacy.show, not builder.streamed)
	next.add_child(infrastructure)
	if builder.backdrop_pending:
		infrastructure.hide()
		builder.pending_infrastructure.append(infrastructure)
	timings.infrastructure_ms = (Time.get_ticks_usec() - stage) / 1000.0
	if paced:
		await get_tree().process_frame
		if generation != _generation: next.free(); return {}
	var standing_started := Time.get_ticks_usec()
	# A far-only world may never request detail. Do not retain the bound height
	# callback (builder -> road surface -> builder) while waiting for a zoom-in.
	if not builder.base_ready: builder.road_surface.finish_build()
	var slice_start := Time.get_ticks_usec()
	var max_slice := 0
	for s in model.get("standing", []):
		if not builder.streamed or str(s.kind) != "house": next.add_child(builder.standing_node(s))
		if paced and Time.get_ticks_usec() - slice_start >= SCENE_BUDGET_USEC:
			max_slice = maxi(max_slice, Time.get_ticks_usec() - slice_start)
			await get_tree().process_frame
			if generation != _generation: next.free(); return {}
			slice_start = Time.get_ticks_usec()
	timings.max_standing_slice_ms = max_slice / 1000.0
	timings.standing_ms = (Time.get_ticks_usec() - standing_started) / 1000.0
	if builder.base_ready:
		if not await _build_base_tiles(builder, next, model, generation, paced):
			builder.road_surface.finish_build()
			next.free()
			return {}
	for node in [builder.mine_rims_node(), builder.shadows_node()]:
		next.add_child(node)
		if builder.backdrop_pending:
			node.hide()
			builder.pending_infrastructure.append(node)
	if builder.streamed:
		if builder.backdrop_pending: builder.attach_continent_pick(next)
		else: builder.finish_continent(next)
		# Cold baking may visit every tile, but its temporary detail is not the
		# runtime working set. Warm and cold openings both start with one backdrop.
		builder.release_local_tiles({})
		builder.local_streaming = true
		builder.base_ready = true
		builder.handover_enabled = true
	else:
		builder.prepare_company_pick_surface(next)
	if builder.streamed: print("[CONTINENT BUILD] trees ready ", Time.get_ticks_msec())
	timings.static_scene_ms = (Time.get_ticks_usec() - stage) / 1000.0
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
	var effects_parent := Node3D.new()
	next.add_child(effects_parent)
	if builder.backdrop_pending:
		effects_parent.hide()
		builder.pending_infrastructure.append(effects_parent)
	_paint_soot(builder)
	var effects := _build_effects(builder, effects_parent)
	timings.scene_ms = (Time.get_ticks_usec() - stage) / 1000.0
	return {"content": next, "builder": builder, "model": model, "goods": goods, "effects": effects, "profile": timings}

func _activate(packet: Dictionary) -> void:
	var measured := Time.get_ticks_usec()
	var activation := {}
	_generation += 1 # Any pending streamer still belongs to the previous world.
	var builder: RefCounted = packet.builder
	var model: Dictionary = packet.model
	var timings: Dictionary = packet.profile
	_release_paper_owner()
	if _content != null:
		if _builder != null and _builder.cursor_picking: _builder.set_collision_tiles({})
		if builder.backdrop_pending and _builder != null and not _builder.streamed:
			# Keep already usable company tiles until the far map can replace them.
			_paper_owner = _content
			builder.paper_owned_tiles = _builder.tiles.duplicate()
		else: _world.remove_child(_content)
		if not _coverage_states.has(_last_all_tiles): _content.queue_free()
		elif _last_all_tiles: _expire_inactive_detail(_coverage_states[true])
	if is_instance_valid(_selection): _selection.queue_free()
	_selection = null
	_content = packet.content
	packet.inactive_since = 0
	_coverage_states[builder.streamed] = packet
	_world.add_child(_content)
	activation.attach_ms = (Time.get_ticks_usec()-measured)/1000.0
	measured = Time.get_ticks_usec()
	_builder = builder
	if builder.loading_reveal != null and not builder.loading_reveal.begun:
		var owned: Dictionary = _coverage_states[false].builder.tiles if _coverage_states.has(false) else {}
		builder.loading_reveal.begin(owned)
	if not builder.streamed:
		_owned_center = Vector2.ZERO
		for tile in builder.tiles.values(): _owned_center += tile.center
		_owned_center /= maxf(1,builder.tiles.size())
	else:
		builder.progressive_tiles = true
	# Spread continent model creation over frames; the company view is small.
	builder.asset_budget_usec = Builder.ASSET_BUDGET_USEC if builder.streamed else 0
	builder.configure_grade()
	activation.grade_ms = (Time.get_ticks_usec()-measured)/1000.0
	measured = Time.get_ticks_usec()
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
	_last_evening = packet.builder.evening
	_last_all_tiles = show_all_tiles
	_goods = packet.goods
	_effects = packet.effects
	_building = false
	if _progress != null: _progress.hide()
	if has_content():
		if show_all_tiles and not _fitted:
			_focus_map_camera()
		elif _medium_after_build:
			_medium_view()
		elif not _fitted or _fit_after_build:
			fit_view()
	_fit_after_build = false
	_medium_after_build = false
	_select_tile(_selected_tile)
	activation.state_ms = (Time.get_ticks_usec()-measured)/1000.0
	measured = Time.get_ticks_usec()
	_update_detail()
	activation.detail_ms = (Time.get_ticks_usec()-measured)/1000.0
	measured = Time.get_ticks_usec()
	_update_goods()
	_update_cars()
	if builder.loading_reveal != null and not builder.backdrop_pending: _start_backdrop_reveals(builder)
	_sync_paper()
	activation.effects_ms = (Time.get_ticks_usec()-measured)/1000.0
	timings.activation = activation
	if _labels != null: _labels.queue_redraw()
	timings.cache_hits = builder.bake_cache.hits
	timings.bundled_hits = builder.bake_cache.bundled_hits
	timings.cache_misses = builder.bake_cache.misses
	timings.cache_writes = builder.bake_cache.writes
	load_profile = timings
	if show_all_tiles: print("[CONTINENT LOAD] ", JSON.stringify(timings))
	elif not background_ready(): _start_background.call_deferred()

func _expire_inactive_detail(packet: Dictionary) -> void:
	# Keep a quick return cheap, then retire inactive detail through the same
	# ten-second grace period and resource target used by normal panning.
	var stamp := Time.get_ticks_msec()
	packet.inactive_since = stamp
	var timer := Timer.new()
	timer.wait_time = 10.0; timer.one_shot = true
	add_child(timer)
	timer.timeout.connect(func() -> void:
		if packet.get("inactive_since", 0) == stamp: _retire_inactive_detail(packet)
		timer.queue_free())
	timer.start()

func _retire_inactive_detail(packet: Dictionary) -> void:
	if not is_instance_valid(packet.content) or packet.content == _content: return
	var builder: RefCounted = packet.builder
	builder.handover.reset(0.0)
	builder.release_local_tiles({}, true)
	builder.resource_cache.owned = _company_tiles()
	builder.resource_cache.age(Time.get_ticks_msec(), {}, {})
	builder.resource_cache.trim(Time.get_ticks_msec(), {}, {})

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
		"tree_sprite_nodes", "building_visuals", "decor_nodes", "detail_nodes", "farm_nodes", "sprite_pairs", "pickables", "glows", "smoke"]
	var offsets := {}
	for field in fields: offsets[field] = (builder.get(field) as Array).size()
	var root := Node3D.new()
	root.name = "Detail_" + tid
	root.visible = false
	parent.add_child(root)
	root.add_child(builder.tile_node(tid))
	if Legacy.show.roads: builder.append_road(root, tid)
	var slice := Time.get_ticks_usec()
	for standing in builder._visibility_standing.get(tid, model.get("standing", [])):
		if str(standing.kind) == "house" and str(standing.tile) == tid:
			root.add_child(builder.standing_node(standing))
		if builder.progressive_tiles and Time.get_ticks_usec()-slice >= SCENE_BUDGET_USEC:
			await get_tree().process_frame
			if generation != _generation:
				for field in fields: builder.get(field).resize(offsets[field])
				if is_instance_valid(root): root.free()
				return false
			slice = Time.get_ticks_usec()
	if Legacy.show.trees: root.add_child(builder.trees_node(tid, model.get("standing", [])))
	_build_glows(builder, root, offsets.glows)
	var records := {}
	for field in fields: records[field] = (builder.get(field) as Array).slice(offsets[field])
	builder.local_tiles[tid] = {"root": root, "records": records}
	root.visible = not builder.progressive_tiles and not builder._overview and (not builder.handover_enabled or builder.handover.blend > 0.0)
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

func _medium_view() -> void:
	# Logical pixels match Detail.choose(), including scaled/Retina windows.
	_rig.span = clampf(size.y / 1.1, Rig.MIN_SIZE, Rig.MAX_SIZE)
	_rig.apply(_camera)
	_fitted = true

func _focus_map_camera() -> void:
	var camera := get_tree().get_first_node_in_group("camera") as Camera2D
	if camera != null and is_instance_valid(_last_terrain) and _builder != null:
		var at: Vector2 = _last_terrain.to_local(camera.get_screen_center_position())
		_rig.target = _builder.point(at)
	elif _builder != null:
		_rig.target = _builder.bounds.get_center()
	_medium_view()

func open_at_map_camera() -> void:
	if _opened: return
	_opened = true
	if show_all_tiles and has_content():
		_focus_map_camera()
		_update_detail()

func capture_camera() -> Dictionary:
	return _rig.capture()

func restore_camera(state: Dictionary) -> void:
	_rig.restore(state)
	_rig.apply(_camera)
	_update_detail()

func _resize_viewport() -> void:
	if _viewport == null: return
	var density := get_viewport().get_final_transform().get_scale().abs()
	if density_override > 0.0: density = Vector2.ONE * density_override
	var pixels := Vector2i((size * density).ceil()).max(Vector2i(1, 1))
	if _viewport.size != pixels: _viewport.size = pixels
	# The 3D scene renders natively up to render_budget_pixels (2560x1440) with
	# 4x MSAA. Denser screens render that many pixels with 2x MSAA and upscale;
	# labels and UI stay at the screen's full density.
	var scale := minf(1.0, sqrt(float(render_budget_pixels) / float(pixels.x * pixels.y)))
	var reduced := scale < 0.999
	var upscaler := Viewport.SCALING_3D_MODE_BILINEAR
	if reduced and RenderingServer.get_current_rendering_method() != "gl_compatibility": upscaler = Viewport.SCALING_3D_MODE_FSR
	if not is_equal_approx(_viewport.scaling_3d_scale, scale): _viewport.scaling_3d_scale = scale
	if _viewport.scaling_3d_mode != upscaler: _viewport.scaling_3d_mode = upscaler
	var msaa := Viewport.MSAA_2X if reduced else Viewport.MSAA_4X
	if _viewport.msaa_3d != msaa: _viewport.msaa_3d = msaa

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
	_drain_asset_tier()

func _warm_ground_slice(delta: float) -> void:
	# One tile per frame, nearest the camera first, only while the view is still
	# and the last frame had headroom: a pan never pays for this. On the owned
	# view this prepares the continent around the company before its first open.
	var camera := capture_camera()
	var still := camera == _warm_camera
	_warm_camera = camera
	if not still or delta > 1.0 / 50.0 or _building or _streaming or _builder == null: return
	# The company view first solves its road chains into the alignment memo, so
	# a building on a new tile re-solves only the chains near that tile.
	if not _builder.streamed and not _builder.alignment_seeded():
		_builder.seed_alignment_step(4000)
		return
	var builder: RefCounted = _builder
	var focus := Vector2(_rig.target.x, _rig.target.z)
	if not builder.streamed:
		if not background_ready() or background_active(): return
		builder = _coverage_states[true].builder
		focus = _owned_center
	elif builder._overview or not detail_ready(): return
	if builder.ground_warmed.size() >= builder.tiles.size(): return
	var best := ""
	var best_distance := INF
	for tid in builder.tiles:
		if builder.ground_warmed.has(tid): continue
		var distance := (builder.tiles[tid].center as Vector2).distance_squared_to(focus)
		if distance < best_distance: best = str(tid); best_distance = distance
	if best != "": builder.warm_ground(best)

func _drain_asset_tier() -> void:
	# Finish budgeted model creation and released-tile freeing a slice per frame,
	# independent of _process.
	if _asset_drain or _builder == null or not (_builder.asset_tier_pending or not _builder.retiring_roots.is_empty()): return
	_asset_drain = true
	var builder: RefCounted = _builder
	while is_inside_tree() and builder == _builder and (builder.asset_tier_pending or not builder.retiring_roots.is_empty()):
		await get_tree().process_frame
		if builder != _builder: break
		if builder.asset_tier_pending: builder._update_asset_tier()
		builder.free_retired()
	_asset_drain = false

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
				if _tile_is_paper(hit.tile_id) or (_builder.backdrop_pending and not _builder.tile_ready(hit.tile_id) and not _builder.paper_owned_tiles.has(hit.tile_id)):
					return _paper_hit(screen)
				return _as_tile_hit(hit)
			if _tile_is_paper(str(hit.collider.get_meta("tile_id",""))): return _paper_hit(screen)
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
	return _paper_hit(screen)

func _paper_hit(pixel: Vector2) -> Dictionary:
	if not is_instance_valid(_paper) or not _paper.visible: return {}
	return _paper.pick(_camera.project_ray_origin(pixel), _camera.project_ray_normal(pixel))

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
		var delta: Vector2 = -event.delta * 12.0
		# Poll the held key so releasing it over UI cannot leave orbit mode stuck.
		# Physical 0 also supports layouts where typing the digit requires Shift.
		if Input.is_physical_key_pressed(KEY_0) or Input.is_key_pressed(KEY_0) or Input.is_key_pressed(KEY_KP_0):
			_rig.orbit(delta)
		else:
			_rig.pan(delta, size.y)
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
	if _builder != null: _builder.free_retired()
	if not _building: _update_cursor_collision(get_local_mouse_position())
	_update_goods()
	_update_cars()
	if _builder != null and not _building: _builder.update_harbour_traffic(_time)
	_advance_tile_reveals(delta)
	_sync_paper()
	_stream_clock += delta
	_warm_ground_slice(delta)
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
	if _tile_is_paper(tid) or (_builder.backdrop_pending and not _builder.tile_ready(tid)):
		_builder.set_collision_tiles({})
		return
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
	var view := Rect2(Vector2.ZERO, size).grow(60.0)
	var buffered := Rect2(-size * 0.20, size * 1.40)
	var nearby := buffered.grow(540.0 * size.y / _rig.span)
	var direction: Vector3 = _rig.target - (_stream_camera.get("target", _rig.target) as Vector3)
	var focus := _camera_focus_tile() if _detail == 2 else ""
	var centre := Vector2(_rig.target.x,_rig.target.z)
	# Start at the owned composition; camera movement naturally reprioritises
	# visible tiles around the player's new focus.
	if centre.distance_to(_owned_center) < 100.0: centre = _owned_center
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
		if not behind and bounds.intersects(view):
			wanted.append({"tile": str(tid), "visible": not behind and bounds.intersects(view), "near": near,
				"ring":_hex_tile_distance(centre,_builder.tiles[tid].center), "distance": _tile_distances[tid]})
		elif not behind and bounds.intersects(buffered):
			_prefetch_tiles.append({"tile": str(tid), "distance": _tile_distances[tid],
				"ahead": direction.length_squared() > 1.0 and direction.dot(at - _rig.target) > 0.0})
	wanted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.visible != b.visible: return a.visible
		if _builder.paper_owned_tiles.has(a.tile) != _builder.paper_owned_tiles.has(b.tile): return not _builder.paper_owned_tiles.has(a.tile)
		if a.near != b.near: return a.near
		if a.ring != b.ring: return a.ring < b.ring
		return a.distance < b.distance)
	_prefetch_tiles.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.ahead != b.ahead: return a.ahead
		return a.distance < b.distance)
	if _prefetch_tiles.size() > PREFETCH_TILES: _prefetch_tiles.resize(PREFETCH_TILES)
	return wanted

func _fine_detail_plan(wanted: Array) -> Dictionary:
	var plan := {}
	if _detail <= 0: return plan
	for item in wanted:
		# Visible tiles within four rings use closest detail. Offscreen neighbours
		# retain resources, without constructing invisible scene nodes.
		if _detail == 2 and item.get("near", false): plan[item.tile] = 2
		elif item.visible: plan[item.tile] = 1
	return plan

func _maintain_resource_cache() -> void:
	var now := Time.get_ticks_msec()
	if not _builder._overview:
		for tid in _builder.local_tiles: _builder.resource_cache.touch(tid, now)
	var nearby: Dictionary = _nearby_tiles if not _builder._overview else {}
	_builder.resource_cache.owned = _company_tiles()
	_builder.resource_cache.age(now, _builder.local_tiles, nearby)
	_builder.resource_cache.trim(now, _builder.local_tiles, nearby, _tile_distances)

func _company_tiles() -> Dictionary:
	# Tiles holding the player's buildings: the owned view's world.
	return _coverage_states[false].builder.tiles if _coverage_states.has(false) else {}

func _prefetch_resources(builder: RefCounted, generation: int, camera_state: Dictionary) -> void:
	if builder._overview or builder.backdrop_pending: return
	var attempted := 0
	for item in _prefetch_tiles:
		var tid := str(item.tile)
		if _prefetch_checked.has(tid) or builder.local_tiles.has(tid): continue
		# Only packaged tiles have resources to read ahead; a world built at runtime
		# has nothing to prefetch, and an empty entry would poison the tile cache.
		if builder.progressive_manifest.get(tid, {}).is_empty(): continue
		if not builder.resource_cache.can_prefetch(): break
		_prefetch_checked[tid] = true
		# Work on private containers so rejected speculative upgrades cannot
		# silently change the cache's retained-byte accounting.
		var key: String = builder.terrain_key(tid)
		var retained: Dictionary = builder.resource_cache.restore(tid)
		if not retained.is_empty(): builder.terrain_cache[key] = retained.data.duplicate(true)
		var prepared: bool = await ProgressiveTile.prepare(self,builder,tid,maxi(1,_detail),generation)
		if prepared and generation == _generation and builder == _builder:
			var data: Dictionary = builder.terrain_cache.get(key,{})
			var chunk: Dictionary = builder._chunk_data.get(tid,{})
			var cost := Builder.TileCache.estimate(data,chunk)
			if data.has("meshes") and builder.resource_cache.can_prefetch(maxi(0,cost-int(retained.get("bytes",0)))):
				builder.resource_cache.put(tid,data,chunk,Time.get_ticks_msec())
		builder.terrain_cache.erase(key);builder._chunk_data.erase(tid)
		builder.tile_load_resources.clear()
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
	builder.release_local_tiles(keep, true, true)
	_drain_asset_tier()
	if far_expired: _far_detail_expires_msec = 0
	var fine := _fine_detail_plan(wanted)
	if not hold_far_detail: builder.release_detail(fine, true)
	var terrain_by_tile := {}
	for item in builder.terrain_lods: terrain_by_tile[item.tile] = item
	var slice_start := Time.get_ticks_usec()
	var completed := true
	var read_ahead := StreamReadAhead.new()
	var request_index := 0
	for request in wanted:
		var tile_started := Time.get_ticks_usec()
		var tile_timings := {}
		var tid := str(request.tile)
		var tier := int(fine.get(tid, 0))
		if builder.backdrop_pending: tier = maxi(1,tier)
		builder.free_retired(1000)
		read_ahead.enqueue(builder,wanted,fine,request_index)
		await read_ahead.ready_current(get_tree(),builder,tid)
		if generation != _generation or camera_state != capture_camera():
			completed = false
			break
		request_index += 1
		if not builder.local_tiles.has(tid) or (tier>0 and terrain_by_tile[tid].data.meshes[tier]==null):
			if not await ProgressiveTile.prepare(self,builder,tid,tier,generation):
				completed = false
				break
			if generation != _generation: break
		read_ahead.release_current(builder,tid)
		tile_timings.prepare_ms = (Time.get_ticks_usec()-tile_started)/1000.0
		var node_started := Time.get_ticks_usec()
		if not builder.local_tiles.has(tid):
			if not await _build_local_tile(builder,_content,_model,tid,generation):
				completed = false
				break
			terrain_by_tile[tid] = builder.terrain_lods[-1]
		if tier>0: await builder.refine_tile(self,terrain_by_tile[tid],tier)
		else: builder.apply_tile_detail(terrain_by_tile[tid],0)
		if generation != _generation: break
		tile_timings.node_ms = (Time.get_ticks_usec()-node_started)/1000.0
		var reveal_started := Time.get_ticks_usec()
		if not builder.ready_tiles.has(tid):
			builder.reveal_tile(tid)
			_release_ready_paper_owner(builder)
			if builder.loading_reveal != null:
				builder.loading_reveal.bind(builder.local_tiles[tid].root)
				if request.visible: _start_tile_reveal(builder,tid)
				else: builder.loading_reveal.skip(tid)
			if _reveal_started>0:
				reveal_profile.tiles.append({"tile":tid,"ring":request.ring,"visible":request.visible,
					"ms":Time.get_ticks_msec()-_reveal_started,"before_far":builder.backdrop_pending,"stages":tile_timings})
			_sync_paper()
		else: builder._apply_view_visibility()
		_drain_asset_tier()
		tile_timings.reveal_ms = (Time.get_ticks_usec()-reveal_started)/1000.0
		builder.cache_local_tile(tid)
		builder.tile_load_resources.clear()
		# A complete tile is published before yielding; the next frame can display
		# it while the next tile's resources load. Never wait for a whole layer.
		if Time.get_ticks_usec()-slice_start >= SCENE_BUDGET_USEC:
			await get_tree().process_frame
			slice_start = Time.get_ticks_usec()
		if camera_state != capture_camera() or generation != _generation: break
	await read_ahead.finish(get_tree())
	stream_read_ahead_stats = {"requests":read_ahead.requested,"peak_requests":read_ahead.peak_requests,"peak_disk_bytes":read_ahead.peak_disk_bytes,"errors":read_ahead.errors}
	builder.road_surface.finish_build()
	builder._road_height_cache.clear()
	if completed and generation == _generation and camera_state == capture_camera():
		for tid in builder.local_tiles: builder.cache_local_tile(str(tid))
		_stream_camera = camera_state
		_stream_generation = generation
		_stream_tier = _detail
		_maintain_resource_cache()
		builder.complete_detail_request()
		if not background_active() and _coverage_states.has(true): _coverage_states[true].get("resources", {}).clear()
	_streaming = false

func detail_ready() -> bool:
	if _building or _streaming: return false
	if _builder == null: return true
	if _builder.asset_tier_pending: return false
	if _builder.handover.active: return false
	var reveal: RefCounted = _builder.loading_reveal
	# A loaded backdrop can still have queued reveals between batches.
	return reveal == null or not reveal.active or (_builder.backdrop_pending and reveal.elapsed.is_empty())

func _update_goods() -> void:
	for item in _goods:
		var stationary := bool(item.get("stationary", false))
		item.sprite.visible = not animate_goods if stationary else animate_goods
		var units_per_pixel := _rig.span / maxf(1.0, size.y)
		var token_pixels := clampf(44.0 / units_per_pixel + 10.0, 16.0, 40.0)
		item.sprite.pixel_size = units_per_pixel * token_pixels / maxf(1, item.sprite.texture.get_width())
		if not stationary:
			var flow: Dictionary = item.flow
			var at := fposmod(_time * 38.0, float(flow.length)) if animate_goods else 0.0
			var distances: PackedFloat32Array = flow.distances
			var idx := clampi(distances.bsearch(at), 1, distances.size() - 1)
			var t := inverse_lerp(distances[idx - 1], distances[idx], at)
			item.sprite.position = (flow.points[idx - 1] as Vector3).lerp(flow.points[idx], t)
		if _tile_is_paper(_builder.tile_at(item.sprite.position)) or (_builder.backdrop_pending and not _builder.tile_ready(_builder.tile_at(item.sprite.position))):
			item.sprite.hide()

func _draw_labels() -> void:
	if _builder == null or not Legacy.show.names: return
	var font := ThemeDB.fallback_font
	var distant := show_all_tiles and size.y / _rig.span < 0.30
	var label_limit := 8 if size.y / _rig.span < 0.15 else 14
	var occupied: Array[Rect2] = []
	# Labels redraw every frame; sort only when the set or the selection changes.
	if not is_same(_label_source, _builder.labels) or _label_selection != _selected_tile or _label_count != _builder.labels.size():
		_label_source = _builder.labels
		_label_selection = _selected_tile
		_label_count = _builder.labels.size()
		_label_order = _builder.labels.duplicate()
		_label_order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if (str(a.tile) == _selected_tile) != (str(b.tile) == _selected_tile): return str(a.tile) == _selected_tile
			return str(a.tile) < str(b.tile))
	for label in _label_order:
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

## A plan-space soot map from every smoking stack, read by the ground shader.
func _paint_soot(builder: RefCounted) -> void:
	var stacks: Array = builder.smoke if Legacy.show.pollution else []
	RenderingServer.global_shader_parameter_set("sc3d_soot_on", 0.0 if stacks.is_empty() else 1.0)
	if stacks.is_empty(): return
	var box: AABB = builder.bounds
	var cell := maxf(box.size.x, box.size.z) / 512.0
	var size := Vector2i(maxi(1, ceili(box.size.x / cell)), maxi(1, ceili(box.size.z / cell)))
	var field := PackedFloat32Array()
	field.resize(size.x * size.y)
	var reach := SOOT_REACH / cell
	for stack in stacks:
		var at := Vector2((stack.point.x - box.position.x) / cell, (stack.point.z - box.position.z) / cell)
		for y in range(maxi(0, floori(at.y - reach)), mini(size.y, ceili(at.y + reach))):
			for x in range(maxi(0, floori(at.x - reach)), mini(size.x, ceili(at.x + reach))):
				var d := Vector2(x + 0.5, y + 0.5).distance_to(at) / reach
				if d < 1.0: field[y * size.x + x] += SOOT_PER_STACK * (1.0 - d * d) * (1.0 - d * d)
	var bytes := PackedByteArray()
	bytes.resize(field.size())
	for i in field.size(): bytes[i] = mini(255, int(field[i] * 255.0))
	var image := Image.create_from_data(size.x, size.y, false, Image.FORMAT_L8, bytes)
	RenderingServer.global_shader_parameter_set("sc3d_soot_map", ImageTexture.create_from_image(image))
	RenderingServer.global_shader_parameter_set("sc3d_soot_rect", Vector4(box.position.x, box.position.z, size.x * cell, size.y * cell))

func _build_effects(builder: RefCounted, parent: Node3D) -> Array:
	_build_glows(builder, parent)
	var cars: Array = []
	var car := Geo.Batch.new()
	car.box(Vector3(0, 2, 0), Vector3(4, 3, 9), Color("dbb963"))
	car.box(Vector3(0, 4, 0), Vector3(3.5, 2, 4), Color("41556a"))
	var car_mesh := car.mesh()
	for road in builder.cars:
		# Whole-continent traffic used to sample every road's height before opening,
		# even when only a handful of tiles (or no cars at far zoom) could be seen.
		cars.append({"node": null, "mesh": car_mesh, "parent": parent, "road": road, "phase": road.phase})
	if Legacy.show.pollution:
		var puff := SphereMesh.new()
		puff.radial_segments = 8
		puff.rings = 4
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(0.40, 0.38, 0.36, 0.55)
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
			particles.scale_amount_min = 8.0
			particles.scale_amount_max = 17.0
			var fade := Gradient.new()
			fade.colors = PackedColorArray([Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)])
			particles.color_ramp = fade
			parent.add_child(particles)
		_build_smog(builder, parent)
	return cars

## A low brown pall hangs over every polluted tile, thicker with more polluters. Billboards
## like the lamp glows: no realtime light, one shared material.
func _build_smog(builder: RefCounted, parent: Node3D) -> void:
	var haze := GradientTexture2D.new()
	haze.width = 64
	haze.height = 64
	haze.fill = GradientTexture2D.FILL_RADIAL
	haze.fill_from = Vector2(0.5, 0.5)
	haze.fill_to = Vector2(1.0, 0.5)
	haze.gradient = Gradient.new()
	haze.gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.albedo_texture = haze
	material.albedo_color = SMOG_COLOUR
	for tid in builder.tiles:
		var polluters := int(builder.tiles[tid].get("polluters", 0))
		if polluters <= 0: continue
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(str(tid))
		var centre: Vector2 = builder.tiles[tid].center
		for i in 4 + 2 * mini(polluters, 6):
			var at := centre + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, SMOG_SPREAD)
			var quad := QuadMesh.new()
			var side := rng.randf_range(0.75, 1.25) * SMOG_SIZE
			quad.size = Vector2(side, side * 0.6)
			var node := Geo.instance(quad, material)
			node.position = builder.point(at) + Vector3.UP * rng.randf_range(60.0, 100.0)
			parent.add_child(node)

func _update_cars() -> void:
	if _builder == null: return
	# Continent traffic has thousands of cars; touch only those on detail tiles.
	if not is_same(_cars_source, _effects):
		_cars_source = _effects
		_cars_by_tile.clear()
		_cars_shown_tiles.clear()
		for car in _effects: (_cars_by_tile.get_or_add(str(car.road.tile), []) as Array).append(car)
	var shown_tiles := {}
	if not show_all_tiles or size.y / _rig.span >= 0.30:
		for tid in (_builder.local_tiles if show_all_tiles else _cars_by_tile):
			if _cars_by_tile.has(tid) and not _tile_is_paper(str(tid)): shown_tiles[tid] = true
	for tid in _cars_shown_tiles:
		if shown_tiles.has(tid): continue
		for car in _cars_by_tile[tid]:
			if car.node != null: car.node.visible = false
	_cars_shown_tiles = shown_tiles
	var started := Time.get_ticks_usec()
	for tid in shown_tiles:
		for car in _cars_by_tile[tid]:
			if car.node == null:
				# Each new car samples its road 17 times; spread creation over frames.
				if Time.get_ticks_usec() - started > 2000: continue
				var path := PackedVector3Array()
				for i in 17:
					var p: Vector2 = (car.road.a as Vector2).lerp(car.road.b, float(i) / 16.0)
					path.append(_builder.at_height(p, _builder.road_height(p) + 2.0))
				car.points = path
				car.node = Geo.instance(car.mesh, _builder.mat)
				car.parent.add_child(car.node)
			car.node.visible = true
			var at := fposmod(_time * 0.06 + float(car.phase), 1.0) * 16.0
			var index := mini(15, int(at))
			var a: Vector3 = car.points[index]
			var b: Vector3 = car.points[index + 1]
			car.node.position = a.lerp(b, at - index)
			if a.distance_squared_to(b) > 0.01: car.node.look_at(car.node.position + b - a, Vector3.UP)
