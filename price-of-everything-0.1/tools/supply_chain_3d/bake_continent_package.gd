extends "res://tools/supply_chain_3d/capture.gd"
## Resumable production bake set for the authored Metal Magnate starting world.
## AGENT_GODOT_WINDOW=1 godot --path . res://tools/supply_chain_3d/bake_continent_package.tscn -- --continent-review --no-telemetry
const Package := preload("res://tools/supply_chain_3d/bake_package.gd")
var layout_reuse := preload("res://tools/supply_chain_3d/reuse_terrain_bakes.gd").new()

func _ready() -> void:
	if not preload("res://scripts/supply_chain_3d/stoneshore_trial.gd").preview_enabled() and "--approved-continent-bake" not in OS.get_cmdline_user_args():
		push_error("Use --stoneshore-review, or --approved-continent-bake after explicit user approval.")
		get_tree().quit(1)
		return
	var reuse_source := ""; var previous_alignment := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--reuse-terrain-package="):reuse_source=arg.trim_prefix("--reuse-terrain-package=")
		if arg.begins_with("--previous-road-alignment="):previous_alignment=arg.trim_prefix("--previous-road-alignment=")
	if not reuse_source.is_empty() and previous_alignment.is_empty():
		push_error("Terrain reuse requires --previous-road-alignment to verify the only changed generator")
		get_tree().quit(1);return
	if not previous_alignment.is_empty():
		if "--no-background-continent" not in OS.get_cmdline_user_args() or reuse_source.is_empty():
			push_error("Alignment reuse requires --no-background-continent and --reuse-terrain-package")
			get_tree().quit(1);return
		layout_reuse.enable_layout_reuse(reuse_source,previous_alignment)
		if not preload("res://scripts/supply_chain_3d/board.gd").offline_layout_reuse.is_valid():
			get_tree().quit(1);return
	PlayerProfile.supply_chain_all_tiles = true # scoped disposable harness; do not save preferences
	await super._ready()
	preload("res://scripts/supply_chain_3d/board.gd").offline_layout_reuse=Callable()

func _continent_review(board: Control, _home: Dictionary) -> void:
	await board.set_all_tiles(true, false)
	board.set_process(false)
	while not board.detail_ready():
		RenderingServer.force_draw(false)
		await get_tree().process_frame
	var builder: RefCounted = board._builder
	var source: RefCounted = builder.bake_cache
	var terrain_reuse := layout_reuse
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--reuse-terrain-package="):
			terrain_reuse.configure(arg.trim_prefix("--reuse-terrain-package="),builder,board._model)
			if not terrain_reuse.configured:
				get_tree().quit(1);return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--reuse-scenery-package="):
			terrain_reuse=preload("res://tools/supply_chain_3d/reuse_scenery_terrain_bakes.gd").new()
			terrain_reuse.configure(arg.trim_prefix("--reuse-scenery-package="),builder,board._model)
			if not terrain_reuse.configured: get_tree().quit(1);return
	var writer := Package.Cache.new()
	writer.enabled = true
	writer.directory = preload("res://scripts/supply_chain_3d/stoneshore_trial.gd").PACKAGE if preload("res://scripts/supply_chain_3d/stoneshore_trial.gd").preview_enabled() else Package.Cache.BUNDLED
	writer.defer_trim = true # release assets are not the bounded runtime disk cache
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--package-output="): writer.directory = arg.trim_prefix("--package-output=")
	if preload("res://scripts/supply_chain_3d/stoneshore_trial.gd").preview_enabled():
		assert(writer.directory != Package.Cache.BUNDLED, "A Stoneshore trial must not overwrite the continent package")
		assert(builder.tiles.size() == 5, "Expected only the five Stoneshore review tiles")
	writer.bundled_directory = writer.directory
	assert(DirAccess.make_dir_recursive_absolute(writer.directory) == OK)
	var previous_manifest: Dictionary = {}
	var previous_path := writer.directory.path_join("manifest.json")
	if FileAccess.file_exists(previous_path):
		var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(previous_path))
		if saved is Dictionary: previous_manifest = saved
	var unchanged_base := 0
	var manifest := {"schema": Package.MANIFEST_SCHEMA, "complete": false, "start": "res://data/starts/metal_magnate.json",
		"engine": Engine.get_version_info().string, "binary_values_version": Package.Cache.Data.Values.VERSION, "tile_count": builder.tiles.size(), "storage": "zstd" if writer.compress else "raw",
		"continent_key": builder._continent_key, "scenery_key": builder._scenery_key,
		"map_key": builder._map_key, "tiles": {}, "resources": {}}
	if board._layout_queries != null:
		# Begin/first draw may populate an adjacent relief query after the board
		# snapshot. Ship that warmed query too, avoiding a first-launch cache write.
		var geography: Dictionary = board._model.get("rail_network",{}).get("tiles",{})
		for tid in builder.tiles:
			for neighbour in geography.get(tid,{}).get("neighbours",[]):
				var center: Vector2 = preload("res://scripts/empire_board_model.gd").tile_center(board._last_terrain,neighbour)
				preload("res://scripts/empire_board.gd")._relief_of(neighbour,center)
		board._layout_queries.data.relief = preload("res://scripts/empire_board.gd")._relief_cache.duplicate(true)
		manifest.layout_key = board._layout_queries.key
		writer.write(manifest.layout_key, board._layout_queries.data)
		manifest.resources[manifest.layout_key] = Package.file_record(writer.directory, manifest.layout_key)
	manifest.rail_layout_keys = []
	for key in preload("res://scripts/supply_chain_3d/rail_network.gd").prepared_keys:
		var prepared: Dictionary = preload("res://scripts/supply_chain_3d/rail_network.gd").prepared_keys[key]
		assert(not prepared.is_empty(), "Missing prepared rail network: " + key)
		writer.write(key,prepared)
		manifest.rail_layout_keys.append(key)
		manifest.resources[key]=Package.file_record(writer.directory,key)
	manifest.transport_key = builder.transport_key
	# Sidewalk rendering annotates the live road dictionaries after cache keys
	# have been calculated. Preserve the transport snapshot saved before that
	# work, rather than baking those later annotations into the next load's key.
	# Ignore ResourceLoader's live instance, which may share the same dictionaries.
	var transport_path: String=source.directory.path_join(builder.transport_key+".res")
	if not FileAccess.file_exists(transport_path):
		transport_path=source.bundled_directory.path_join(builder.transport_key+".res")
	var transport := Package.persisted_data(transport_path,builder.transport_key)
	assert(not transport.is_empty(),"Missing persisted transport snapshot")
	writer.write(builder.transport_key, transport)
	manifest.resources[builder.transport_key] = Package.file_record(writer.directory, builder.transport_key)
	builder.bake_cache = writer
	builder.release_local_tiles({})
	var started := Time.get_ticks_msec()
	var copied := {"medium": 0, "near": 0}
	var generated := {"medium": 0, "near": 0}
	var reused := {"medium": 0, "near": 0}
	var prepared := 0
	for tid in builder.tiles:
		var base_key: String = builder.tile_chunks[tid]
		var base := writer.read(base_key)
		if base.is_empty():
			base = source.read(base_key)
			if base.is_empty():
				await board._build_local_tile(builder, board._content, board._model, tid, board._generation)
				base = builder.base_chunk(tid)
				writer.write(base_key, base)
			else:
				writer.write(base_key, base)
		var needs_base: bool = (Package.Cache.storage_format(writer.directory.path_join(base_key + ".res")) != manifest.storage
			or base.get("detail_source", "") != Package.Cache.source_key("detail") or not base.get("pick_shape") is ConcavePolygonShape3D)
		builder._chunk_data[tid] = base
		builder.prepare_local_detail(tid, board._model.get("standing", []))
		builder.prepare_picking(base)
		var previous_key := str(previous_manifest.get("tiles", {}).get(tid, {}).get("base", ""))
		if previous_key != "" and previous_key != base_key:
			var previous := writer.read(previous_key)
			if not previous.is_empty() and Package.same_payload(base, previous):
				base_key = previous_key
				builder.tile_chunks[tid] = base_key
				unchanged_base += 1
				needs_base = false
		if needs_base:
			writer.write(base_key, base)
			prepared += 1
		manifest.tiles[tid] = {"base": base_key}
		manifest.resources[base_key] = Package.file_record(writer.directory, base_key)
		builder.view_hulls[tid]=Package.enclose_terrain(builder.view_hulls[tid],base)
		for name in Package.TILE_TIERS:
			var tier: int = Package.TILE_TIERS[name]
			var key: String = builder.tile_bake_key(tid, tier)
			var data := writer.read(key)
			if data.is_empty():
				data = source.read(key)
				if data.is_empty():
					data = terrain_reuse.read_tile(tid,name)
					if not data.is_empty():
						writer.write(key,data)
						reused[name] += 1
					else:
						data = await builder._tile_bake(self, tid, tier)
						generated[name] += 1
				else:
					writer.write(key, data)
					copied[name] += 1
			else:
				reused[name] += 1
			if Package.Cache.storage_format(writer.directory.path_join(key + ".res")) != manifest.storage or not data.get("pick_shape") is ConcavePolygonShape3D:
				builder.prepare_picking(data)
				writer.write(key, data)
			manifest.tiles[tid][name] = key
			manifest.resources[key] = Package.file_record(writer.directory, key)
			builder.view_hulls[tid]=Package.enclose_terrain(builder.view_hulls[tid],data)
		builder.release_local_tiles({})
		builder._chunk_data.clear()
		if manifest.tiles.size() % 20 == 0:
			print("[PACKAGE] ", manifest.tiles.size(), "/", builder.tiles.size(), " copied=", copied, " generated=", generated, " reused=", reused,
				" elapsed_ms=", Time.get_ticks_msec() - started)
			await get_tree().process_frame
	builder.road_surface.finish_build()
	var root: Dictionary = builder.continent.duplicate()
	root.tile_chunks = builder.tile_chunks.duplicate()
	root.metadata = root.metadata.duplicate()
	root.metadata.visibility = builder.visibility_bake()
	writer.write(builder._continent_key, root)
	writer.write(builder._scenery_key, builder.scenery_data())
	for key in [builder._continent_key, builder._scenery_key]: manifest.resources[key] = Package.file_record(writer.directory, key)
	FileAccess.open(writer.directory.path_join("source_fingerprints.json"), FileAccess.WRITE).store_string(JSON.stringify(Package.Cache.source_fingerprints(), "\t") + "\n")
	manifest.complete = true
	var path := writer.directory.path_join("manifest.json")
	FileAccess.open(path, FileAccess.WRITE).store_string(JSON.stringify(manifest, "\t") + "\n")
	await preload("res://tools/supply_chain_3d/compact_render_bakes.gd").migrate(writer.directory,self)
	var report := await Package.validate(writer.directory, self)
	if report.ok and "--prune" in OS.get_cmdline_user_args():
		for file in DirAccess.get_files_at(writer.directory):
			if file.ends_with(".res") and not manifest.resources.has(file.get_basename()):
				DirAccess.remove_absolute(writer.directory.path_join(file))
	report.prepared_base_tiles = prepared
	report.unchanged_base_tiles = unchanged_base
	report.generated = generated
	report.copied = copied
	report.reused = reused
	report.reused_unchanged_terrain = terrain_reuse.reused
	report.civic = {}
	for standing in board._model.get("standing", []):
		if standing.has("decor_family"):
			var family := str(standing.decor_family)
			report.civic[family] = int(report.civic.get(family, 0)) + 1
	report.elapsed_ms = Time.get_ticks_msec() - started
	FileAccess.open("/private/tmp/continent_package_report.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("[PACKAGE COMPLETE] ", JSON.stringify(report))
	for i in 4:
		RenderingServer.force_draw(false)
		await get_tree().process_frame
	if not report.ok:
		push_error("Packaged continent did not pass validation")
		get_tree().quit(1)
