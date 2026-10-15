extends RefCounted
const Snapshot := preload("res://scripts/supply_chain_3d/world_snapshot.gd")
const Builder := preload("res://scripts/supply_chain_3d/world_builder.gd")
const Sprites := preload("res://scripts/supply_chain_3d/far_sprites.gd")

static func prepare(board: Control, job: RefCounted, generation: int) -> Dictionary:
	var started := Time.get_ticks_usec()
	var tree := board.get_tree()
	var owner: RefCounted = board._builder
	var cache: RefCounted = owner.bake_cache
	var manifest_path: String = cache.bundled_directory.path_join("manifest.json")
	if not FileAccess.file_exists(manifest_path): return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not parsed is Dictionary: return {}
	var manifest: Dictionary = parsed
	var key := str(manifest.get("world_snapshot_key", ""))
	if key.is_empty() or not manifest.get("complete", false): return {}
	var copied := Time.get_ticks_usec()
	var context := Snapshot.inputs(board)
	job.profile.input_copy_ms = (Time.get_ticks_usec() - copied) / 1000.0
	var input_key: String = await job.digest(tree, context)
	if job.cancelled: return {}
	var data: Dictionary = await job.bake(tree, cache, key)
	if job.cancelled or not Snapshot.matches(data, input_key, manifest): return {}
	board._loading_ink = data.ink
	board._sync_paper()
	var setup_started := Time.get_ticks_usec()
	var builder := Builder.new()
	builder.streamed = true; builder.cursor_picking = true; builder.lazy_assets = true
	builder.backdrop_pending = true; builder.progressive_tiles = true
	builder.progressive_manifest = manifest.tiles
	builder.ground = owner.ground
	builder.terrain_cache = board._terrain_cache
	job.stage = "copy prepared model"
	var model: Dictionary = await job.copy_model(tree, data.model)
	if job.cancelled or model.is_empty(): return {}
	builder.tiles = model.tiles
	builder.rivers = data.rivers
	builder.prepared_foundations = data.foundations
	builder.prepared_continent_pick = data.pick_shape
	builder.prepared_mine_rims = data.mine_rims
	builder.prepared_authored_profile = data.authored_profile
	builder.bounds = data.overview.bounds
	builder.labels = data.overview.labels.duplicate(true)
	builder.tile_chunks = data.overview.tile_chunks
	if not builder._restore_visibility(data.overview.visibility): return {}
	builder.base_ready = false
	for field in Snapshot.KEY_FIELDS: builder.set(field, data.keys[field])
	job.profile.model_setup_ms = (Time.get_ticks_usec()-setup_started)/1000.0
	# Load immutable resources away from the game thread. Holding their Resource
	# handles makes the existing native cache lookups below immediate.
	for dependency in [builder.transport_key, builder._scenery_key]:
		if (await job.bake(tree, builder.bake_cache, dependency)).is_empty() or job.cancelled: return {}
	setup_started = Time.get_ticks_usec()
	job.stage = "restore layout"
	builder.pits = data.pits
	job.profile.pits_ms = (Time.get_ticks_usec()-setup_started)/1000.0
	var measured := Time.get_ticks_usec()
	builder.lines = model.get("lines", []); builder.depots = model.get("depots", [])
	builder.stations = model.get("stations", []); builder.neighbourhood = model.get("neighbourhood", {})
	builder._index_rivers()
	job.profile.river_index_ms = (Time.get_ticks_usec()-measured)/1000.0
	measured = Time.get_ticks_usec()
	var transport: Dictionary = builder.bake_cache.read(builder.transport_key)
	if transport.get("version", -1) != Builder.TransportBake.VERSION: return {}
	# The snapshot carries the final authored spatial indexes. The ordinary
	# restore rebuilds those indexes twice even when all geometry came from disk.
	for item in [[builder.road_alignment, Builder.TransportBake.ALIGNMENT, "alignment"],
		[builder.road_grade, Builder.TransportBake.GRADE, "grade"],
		[builder.rail_urban, Builder.TransportBake.URBAN, "urban"]]:
		for field in item[1]:
			if not transport.get(item[2], {}).has(field): return {}
			item[0].set(field, transport[item[2]][field])
	builder.roads = transport.roads
	builder.rail_plan = transport.rail_plan
	builder.transport_ready = true
	model.roads = builder.roads
	job.profile.transport_restore_ms = (Time.get_ticks_usec()-measured)/1000.0
	measured = Time.get_ticks_usec()
	await builder.prepare_scenery(board, model)
	job.profile.scenery_restore_ms = (Time.get_ticks_usec()-measured)/1000.0
	measured = Time.get_ticks_usec()
	if job.cancelled: return {}
	builder.configure_grade(false)
	job.profile.grade_ms = (Time.get_ticks_usec()-measured)/1000.0
	job.profile.restore_layout_ms = (Time.get_ticks_usec()-setup_started)/1000.0
	var artwork := {}
	for s in model.standing:
		if str(s.kind) != "house": artwork[builder.standing_key(s)] = true
		if s.has("harbour"):
			var frame: Dictionary = builder.standing_frame(s)
			await job.resource(tree, Builder.Assets.DIRECTORY + str(frame.harbour_asset) + ".glb")
			if job.cancelled: return {}
	var art_paths: Array = []
	for asset in artwork:
		if Sprites.entry(asset).is_empty(): continue
		for suffix in [".png", "_depth.png"]:
			art_paths.append(Sprites.DIRECTORY + asset + suffix)
	await job.batch(tree,art_paths)
	if job.cancelled: return {}
	job.profile.resources_ms = (Time.get_ticks_usec() - started) / 1000.0
	job.stage = "assemble scene"
	var packet: Dictionary = await board._assemble(builder, model, generation, true, job.profile)
	if job.cancelled:
		if not packet.is_empty(): packet.content.free()
		return {}
	packet.profile = job.profile
	packet.resources = job.resources
	job.profile.layout_ready_ms = (Time.get_ticks_usec()-started)/1000.0
	board._publish_background(packet, job)
	# Local medium tiles can now appear over paper. The single far bake loads
	# independently and fills distant areas when it is ready.
	var far: Dictionary = await job.bake(tree, builder.bake_cache, builder._continent_key)
	if job.cancelled: return {}
	if far.is_empty(): return packet
	art_paths.clear()
	for groups in [far.get("tree_sprites", {}), far.get("decor_sprites", {})]:
		for asset in groups:
			for suffix in [".png", "_depth.png"]:
				art_paths.append(Sprites.DIRECTORY+asset+suffix)
	await job.batch(tree,art_paths)
	if job.cancelled: return {}
	builder.continent = far
	builder.install_backdrop(packet.content)
	board._backdrop_ready(builder)
	job.profile.total_ms = (Time.get_ticks_usec() - started) / 1000.0
	return packet
