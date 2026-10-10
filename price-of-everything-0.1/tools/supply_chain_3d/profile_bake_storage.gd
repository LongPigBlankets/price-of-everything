extends Node
## Compare packaged Zstd resources with lossless uncompressed copies in /tmp.
## Never modifies the shipped package; all timing excludes offline conversion.
const Cache := preload("res://scripts/supply_chain_3d/bake_cache.gd")
const Data := preload("res://scripts/supply_chain_3d/bake_data.gd")
const OUTPUT := "res://../outputs/supply-chain-3d/closest-cache-profile/"

func _ready() -> void:
	TelemetryState.enabled = false
	SaveLoad.autosave_enabled = false
	get_tree().create_timer(180.0).timeout.connect(func() -> void: get_tree().quit(2))
	await get_tree().process_frame
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Cache.BUNDLED.path_join("manifest.json")))
	var profile: Array = JSON.parse_string(FileAccess.get_file_as_string(OUTPUT.path_join("profile.json")))
	var tids: Array = profile[1].added_offscreen
	var directory := "/private/tmp/closest-bake-storage-%d" % Time.get_ticks_usec()
	assert(DirAccess.make_dir_recursive_absolute(directory) == OK)
	var samples := []
	for tid in tids:
		var source: String = Cache.BUNDLED.path_join(str(manifest.tiles[tid].near) + ".res")
		var original := ResourceLoader.load(source, "", ResourceLoader.CACHE_MODE_IGNORE) as Data
		assert(original != null)
		var copy := Data.new()
		copy.key = original.key
		copy.data = original.data
		var target: String = directory.path_join(str(tid) + ".res")
		assert(ResourceSaver.save(copy, target, 0) == OK)
		samples.append({"tile": tid, "compressed": source, "raw": target,
			"compressed_bytes": FileAccess.open(source, FileAccess.READ).get_length(),
			"raw_bytes": FileAccess.open(target, FileAccess.READ).get_length()})
		RenderingServer.force_draw(false)
		await get_tree().process_frame
	var results := []
	for round_index in 3:
		for sample in samples:
			for format in (["compressed", "raw"] if round_index % 2 == 0 else ["raw", "compressed"]):
				var start := Time.get_ticks_usec()
				var bytes := FileAccess.get_file_as_bytes(sample[format])
				var read_ms := (Time.get_ticks_usec() - start) / 1000.0
				bytes.clear()
				start = Time.get_ticks_usec()
				var loaded := ResourceLoader.load(sample[format], "", ResourceLoader.CACHE_MODE_IGNORE) as Data
				var load_ms := (Time.get_ticks_usec() - start) / 1000.0
				assert(loaded != null and loaded.data.texture.get_width() == 2048)
				RenderingServer.force_draw(false)
				var settle_ms := (Time.get_ticks_usec() - start) / 1000.0
				results.append({"round": round_index, "tile": sample.tile, "format": format,
					"file_read_ms": read_ms, "resource_load_ms": load_ms, "load_and_draw_ms": settle_ms})
				loaded = null
				await get_tree().process_frame
	var report := {"samples": samples, "timings": results, "warm_os_cache": true,
		"notes": "CACHE_MODE_IGNORE reloads embedded resources; no change to art or mipmaps. GPU completion is not isolated by resource_load_ms."}
	FileAccess.open(OUTPUT.path_join("storage-profile.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	for sample in samples: DirAccess.remove_absolute(sample.raw)
	DirAccess.remove_absolute(directory)
	print("[STORAGE PROFILE] completed ", results.size(), " loads")
	get_tree().quit()
