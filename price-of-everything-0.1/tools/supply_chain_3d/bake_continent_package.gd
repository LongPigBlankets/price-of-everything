extends "res://tools/supply_chain_3d/capture.gd"
## Resumable production bake set for the authored Metal Magnate starting world.
## AGENT_GODOT_WINDOW=1 godot --path . res://tools/supply_chain_3d/bake_continent_package.tscn -- --continent-review --no-telemetry
const Package := preload("res://tools/supply_chain_3d/bake_package.gd")

func _continent_review(board: Control, _home: Dictionary) -> void:
	await board.set_all_tiles(true, false)
	board.set_process(false)
	while not board.detail_ready():
		RenderingServer.force_draw(false)
		await get_tree().process_frame
	var builder: RefCounted = board._builder
	var source: RefCounted = builder.bake_cache
	var writer := Package.Cache.new()
	writer.enabled = true
	writer.directory = Package.Cache.BUNDLED
	writer.defer_trim = true # release assets are not the bounded runtime disk cache
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--package-output="): writer.directory = arg.trim_prefix("--package-output=")
	writer.bundled_directory = writer.directory
	assert(DirAccess.make_dir_recursive_absolute(writer.directory) == OK)
	var manifest := {"schema": Package.MANIFEST_SCHEMA, "complete": false, "start": "res://data/starts/metal_magnate.json",
		"engine": Engine.get_version_info().string, "tile_count": builder.tiles.size(), "storage": "zstd" if writer.compress else "raw",
		"continent_key": builder._continent_key, "scenery_key": builder._scenery_key,
		"map_key": builder._map_key, "tiles": {}, "resources": {}}
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
		if needs_base:
			writer.write(base_key, base)
			prepared += 1
		manifest.tiles[tid] = {"base": base_key}
		manifest.resources[base_key] = Package.file_record(writer.directory, base_key)
		for name in Package.TILE_TIERS:
			var tier: int = Package.TILE_TIERS[name]
			var key: String = builder.tile_bake_key(tid, tier)
			var data := writer.read(key)
			if data.is_empty():
				data = source.read(key)
				if data.is_empty():
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
		builder.release_local_tiles({})
		builder._chunk_data.clear()
		if manifest.tiles.size() % 20 == 0:
			print("[PACKAGE] ", manifest.tiles.size(), "/", builder.tiles.size(), " copied=", copied, " generated=", generated, " reused=", reused,
				" elapsed_ms=", Time.get_ticks_msec() - started)
			await get_tree().process_frame
	builder.road_surface.finish_build()
	var root: Dictionary = builder.continent.duplicate()
	root.metadata = root.metadata.duplicate()
	root.metadata.visibility = builder.visibility_bake()
	writer.write(builder._continent_key, root)
	writer.write(builder._scenery_key, {"trees": builder.tree_placements, "shadows": builder.static_shadows,
		"standing": builder.standing_frames, "grade": builder.grade_range})
	for key in [builder._continent_key, builder._scenery_key]: manifest.resources[key] = Package.file_record(writer.directory, key)
	FileAccess.open(writer.directory.path_join("source_fingerprints.json"), FileAccess.WRITE).store_string(JSON.stringify(Package.Cache.source_fingerprints(), "\t") + "\n")
	if "--prune" in OS.get_cmdline_user_args():
		for file in DirAccess.get_files_at(writer.directory):
			if file.ends_with(".res") and not manifest.resources.has(file.get_basename()):
				DirAccess.remove_absolute(writer.directory.path_join(file))
	manifest.complete = true
	var path := writer.directory.path_join("manifest.json")
	FileAccess.open(path, FileAccess.WRITE).store_string(JSON.stringify(manifest, "\t") + "\n")
	var report := await Package.validate(writer.directory, self)
	report.prepared_base_tiles = prepared
	report.generated = generated
	report.copied = copied
	report.reused = reused
	report.elapsed_ms = Time.get_ticks_msec() - started
	FileAccess.open("/private/tmp/continent_package_report.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("[PACKAGE COMPLETE] ", JSON.stringify(report))
	for i in 4:
		RenderingServer.force_draw(false)
		await get_tree().process_frame
	if not report.ok:
		push_error("Packaged continent did not pass validation")
		get_tree().quit(1)
