extends Node
## Disposable lossless codec / GPU texture comparison. Shipped bakes are read-only.
const Cache := preload("res://scripts/supply_chain_3d/bake_cache.gd")
const Data := preload("res://scripts/supply_chain_3d/bake_data.gd")
const OUTPUT := "res://../outputs/supply-chain-3d/compact-bakes/"

static func fastlz_copy(source: String, target: String) -> void:
	# ResourceSaver writes RSCC containers using Zstd. FileAccess exposes the same
	# container with GCPF magic. Repack its unchanged logical bytes using FastLZ;
	# embedded resource offsets remain unchanged (unlike compressing a raw RSRC).
	var temporary := target + ".container"
	var bytes := FileAccess.get_file_as_bytes(source)
	assert(bytes.slice(0, 4).get_string_from_ascii() == "RSCC")
	for i in 4: bytes[i] = "GCPF".to_ascii_buffer()[i]
	FileAccess.open(temporary, FileAccess.WRITE).store_buffer(bytes)
	var reader := FileAccess.open_compressed(temporary, FileAccess.READ)
	assert(reader != null)
	var data := reader.get_buffer(reader.get_length())
	reader.close()
	var writer := FileAccess.open_compressed(target, FileAccess.WRITE, FileAccess.COMPRESSION_FASTLZ)
	writer.store_buffer(data)
	writer.close()
	var header := FileAccess.open(target, FileAccess.READ_WRITE)
	header.store_buffer("RSCC".to_ascii_buffer())
	header.seek_end(-4)
	header.store_buffer("RSCC".to_ascii_buffer())
	header.close()
	DirAccess.remove_absolute(temporary)

func _ready() -> void:
	TelemetryState.enabled = false
	SaveLoad.autosave_enabled = false
	get_tree().create_timer(240.0).timeout.connect(func() -> void: get_tree().quit(2))
	await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Cache.BUNDLED.path_join("manifest.json")))
	var directory := "/private/tmp/compact-bake-profile-%d" % Time.get_ticks_usec()
	assert(DirAccess.make_dir_recursive_absolute(directory) == OK)
	var tids := ["tile_6_9", "tile_7_10", "tile_10_10", "tile_11_10", "tile_15_10", "tile_20_10", "tile_25_10", "tile_1_1", "tile_30_20"]
	var gpu_name := "s3tc" if "--s3tc" in OS.get_cmdline_user_args() else "bptc"
	var samples := []
	for tid in tids:
		var source: String = Cache.BUNDLED.path_join(str(manifest.tiles[tid].near) + ".res")
		var original := ResourceLoader.load(source, "", ResourceLoader.CACHE_MODE_IGNORE) as Data
		assert(original != null)
		var paths := {"raw": directory.path_join(tid + "_raw.res")}
		var copy := Data.new()
		copy.key = original.key
		copy.data = original.data
		assert(ResourceSaver.save(copy, paths.raw, 0) == OK)
		paths.zstd = directory.path_join(tid + "_zstd.res")
		assert(ResourceSaver.save(copy, paths.zstd, ResourceSaver.FLAG_COMPRESS) == OK)
		paths.fastlz = directory.path_join(tid + "_fastlz.res")
		fastlz_copy(paths.zstd, paths.fastlz)
		var verified := ResourceLoader.load(paths.fastlz, "", ResourceLoader.CACHE_MODE_IGNORE) as Data
		assert(verified != null and verified.key == original.key)
		assert(verified.data.texture.get_image().get_data() == original.data.texture.get_image().get_data())
		assert(verified.data.pick_shape.get_faces() == original.data.pick_shape.get_faces())
		var image: Image = original.data.texture.get_image()
		var gpu := image.duplicate() as Image
		var error := gpu.compress(Image.COMPRESS_S3TC if gpu_name == "s3tc" else Image.COMPRESS_BPTC)
		var quality := {}
		if error == OK:
			var decoded := gpu.duplicate() as Image
			assert(decoded.decompress() == OK)
			quality = image.compute_image_metrics(decoded, false)
			copy = Data.new()
			copy.key = original.key
			copy.data = original.data.duplicate()
			copy.data.texture = ImageTexture.create_from_image(gpu)
			paths[gpu_name + "_raw"] = directory.path_join(tid + "_" + gpu_name + "_raw.res")
			paths[gpu_name + "_zstd"] = directory.path_join(tid + "_" + gpu_name + "_zstd.res")
			assert(ResourceSaver.save(copy, paths[gpu_name + "_raw"], 0) == OK)
			assert(ResourceSaver.save(copy, paths[gpu_name + "_zstd"], ResourceSaver.FLAG_COMPRESS) == OK)
			if tid == "tile_6_9":
				image.save_png(OUTPUT.path_join("terrain-original.png"))
				decoded.save_png(OUTPUT.path_join("terrain-" + gpu_name + ".png"))
		var sizes := {}
		for format in paths: sizes[format] = FileAccess.open(paths[format], FileAccess.READ).get_length()
		samples.append({"tile": tid, "paths": paths, "bytes": sizes, "gpu_format": gpu_name, "gpu_error": error,
			"rgba_bytes": image.get_data_size(), "gpu_bytes": gpu.get_data_size(), "quality": quality})
		print("[COMPACT PREPARED] ", tid, " ", JSON.stringify(sizes))
		RenderingServer.force_draw(false)
		await get_tree().process_frame
	var timings := []
	for round_index in 3:
		for sample in samples:
			var formats: Array = sample.paths.keys()
			if round_index % 2: formats.reverse()
			for format in formats:
				var start := Time.get_ticks_usec()
				var loaded := ResourceLoader.load(sample.paths[format], "", ResourceLoader.CACHE_MODE_IGNORE) as Data
				var load_ms := (Time.get_ticks_usec() - start) / 1000.0
				assert(loaded != null and loaded.data.texture.get_width() == 2048)
				RenderingServer.force_draw(false)
				var draw_ms := (Time.get_ticks_usec() - start) / 1000.0
				timings.append({"round": round_index, "tile": sample.tile, "format": format, "load_ms": load_ms, "load_and_draw_ms": draw_ms})
				loaded = null
				await get_tree().process_frame
	var report := {"samples": samples, "timings": timings, "warm_os_cache": true,
		"notes": "Same prepared mesh and collision data; lossless raw/Zstd/FastLZ; GPU formats change only texture encoding. CACHE_MODE_IGNORE reloads embedded resources. Conversion excluded. GPU completion not isolated."}
	FileAccess.open(OUTPUT.path_join(gpu_name + "-profile.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	for sample in samples:
		for format in sample.paths:
			DirAccess.remove_absolute(sample.paths[format])
	DirAccess.remove_absolute(directory)
	print("[COMPACT COMPLETE] ", timings.size(), " loads")
	get_tree().quit()
