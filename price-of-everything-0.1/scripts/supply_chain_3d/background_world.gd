extends RefCounted
const Snapshot := preload("res://scripts/supply_chain_3d/world_snapshot.gd")
const Builder := preload("res://scripts/supply_chain_3d/world_builder.gd")
const Sprites := preload("res://scripts/supply_chain_3d/far_sprites.gd")
const TileOverlay := preload("res://scripts/supply_chain_3d/tile_overlay.gd")

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
	job.profile.digest_ready_ms = (Time.get_ticks_usec()-started)/1000.0
	if job.cancelled: return {}
	# The canonical bake is already encoded for fast loading. Private decoding
	# detaches live layout values without a second native-format copy on disk.
	var data: Dictionary = await job.bake(tree,cache,key,true)
	job.profile.snapshot_ready_ms = (Time.get_ticks_usec()-started)/1000.0
	if job.cancelled or not Snapshot.usable_base(data, manifest): return {}
	# A live world that differs from the shipped one lays out only its changed
	# tiles. The game never lays out or bakes the whole continent.
	var changed: Array = []
	if not Snapshot.matches(data, input_key, manifest):
		job.stage = "changed tiles"
		var lock := "background:%d" % job.get_instance_id()
		await board._lock_layout(lock)
		if job.cancelled: board._unlock_layout(lock); return {}
		var overlay: Dictionary = await TileOverlay.prepare(board, data.model, owner.ground, cache, [], null, func() -> bool: return not job.cancelled)
		board._unlock_layout(lock)
		if job.cancelled or overlay.is_empty(): return {}
		data.model = overlay.model
		changed = overlay.changed
		job.profile.overlay = overlay.profile
	board._loading_ink = data.ink
	board._sync_paper()
	var setup_started := Time.get_ticks_usec()
	var builder := Builder.new()
	builder.streamed = true; builder.cursor_picking = true; builder.lazy_assets = true
	builder.backdrop_pending = true; builder.progressive_tiles = true
	builder.progressive_manifest = manifest.tiles
	builder.ground = owner.ground
	builder.terrain_cache = board._terrain_cache
	var model: Dictionary = data.model
	if job.cancelled or model.is_empty(): return {}
	builder.tiles = model.tiles
	builder.loading_reveal = preload("res://scripts/supply_chain_3d/tile_reveal.gd").new()
	builder.loading_reveal.configure(model.tiles,builder.origin)
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
	var dependency_started := Time.get_ticks_usec()
	var transport: Dictionary = await job.bake(tree,builder.bake_cache,builder.transport_key,true)
	job.profile.transport_load_ms = (Time.get_ticks_usec()-dependency_started)/1000.0
	dependency_started = Time.get_ticks_usec()
	var scenery: Dictionary = await job.bake(tree,builder.bake_cache,builder._scenery_key,true)
	job.profile.scenery_load_ms = (Time.get_ticks_usec()-dependency_started)/1000.0
	if job.cancelled or transport.is_empty() or scenery.is_empty(): return {}
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
	await builder.prepare_scenery(board,model,scenery)
	if not changed.is_empty():
		var shaded: Dictionary = await builder.refresh_scenery_tiles(board, model, changed)
		if job.cancelled: return {}
		_rebake_changed_tiles(builder, model, changed, shaded, manifest)
	job.profile.scenery_restore_ms = (Time.get_ticks_usec()-measured)/1000.0
	measured = Time.get_ticks_usec()
	if job.cancelled: return {}
	builder.configure_grade(false)
	job.profile.grade_ms = (Time.get_ticks_usec()-measured)/1000.0
	job.profile.restore_layout_ms = (Time.get_ticks_usec()-setup_started)/1000.0
	var artwork := {}
	var harbour_started := Time.get_ticks_usec()
	for s in model.standing:
		if str(s.kind) != "house": artwork[builder.standing_key(s)] = true
		if s.has("harbour"):
			var frame: Dictionary = builder.standing_frame(s)
			await job.resource(tree, Builder.Assets.DIRECTORY + str(frame.harbour_asset) + ".glb")
			if job.cancelled: return {}
	var art_paths: Array = []
	job.profile.harbour_load_ms = (Time.get_ticks_usec()-harbour_started)/1000.0
	for asset in artwork:
		if Sprites.entry(asset).is_empty(): continue
		for suffix in [".png", "_depth.png"]:
			art_paths.append(Sprites.DIRECTORY + asset + suffix)
	var art_started := Time.get_ticks_usec()
	await job.batch(tree,art_paths)
	job.profile.standing_art_ms = (Time.get_ticks_usec()-art_started)/1000.0
	if job.cancelled: return {}
	job.profile.resources_ms = (Time.get_ticks_usec() - started) / 1000.0
	job.stage = "assemble scene"
	var packet: Dictionary = await board._assemble(builder, model, generation, true, job.profile)
	if job.cancelled:
		if not packet.is_empty(): packet.content.free()
		return {}
	builder.loading_reveal.bind(packet.content)
	packet.profile = job.profile
	packet.resources = job.resources
	job.profile.layout_ready_ms = (Time.get_ticks_usec()-started)/1000.0
	board._publish_background(packet, job)
	# Give the first nearby tiles exclusive use of the loader before starting the
	# large far resource. Do not hold background preparation when owned-only is
	# still selected, or when a far camera needs the backdrop itself to proceed.
	var first_tiles_started := Time.get_ticks_usec()
	while not job.cancelled and board._builder == builder and board._requested_all_tiles and not builder._overview and builder.ready_tiles.size()<3:
		if Time.get_ticks_usec()-first_tiles_started>500000: break
		await tree.process_frame
	job.profile.first_tiles_priority_ms = (Time.get_ticks_usec()-first_tiles_started)/1000.0
	if job.cancelled: return {}
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

## Changed tiles, tiles whose mine pits moved and tiles whose shadows changed
## stop using their packaged terrain and bake it on demand, once. Tiles whose
## own contents changed also get a new base chunk, so their local detail rebuilds.
static func _rebake_changed_tiles(builder: RefCounted, model: Dictionary, changed: Array, shaded: Dictionary, manifest: Dictionary) -> void:
	var own := {}
	for tid in changed: own[tid] = true
	var base_pits: Dictionary = builder.pits.duplicate()
	builder.configure_pits(model.standing)
	for iid in base_pits.keys() + builder.pits.keys():
		if var_to_str(base_pits.get(iid)) == var_to_str(builder.pits.get(iid)): continue
		var pit: Dictionary = builder.pits.get(iid, base_pits.get(iid))
		own[str(pit.tile)] = true
		for neighbour in Catalog.tile_neighbours(str(pit.tile)): shaded[neighbour] = true
		builder.prepared_mine_rims = null
	var packaged: Dictionary = manifest.tiles.duplicate()
	for tid in own:
		var contents: Array = []
		for s in model.standing:
			if str(s.tile) == tid: contents.append([str(s.iid), str(s.kind), s.pos, float(s.get("side", 0.0)), float(s.get("yaw", 0.0))])
		builder.tile_chunks[tid] = "base-tile-" + Builder.BakeCache.digest([str(builder.tile_chunks.get(tid, "")), contents])
		packaged.erase(tid)
	for tid in shaded: packaged.erase(tid)
	builder.progressive_manifest = packaged
	print("[TILE OVERLAY] rebake tiles=", own.size(), " shadow-only=", shaded.size())
