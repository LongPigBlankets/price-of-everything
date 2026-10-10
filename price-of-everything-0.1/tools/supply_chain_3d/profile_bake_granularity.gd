extends Node
## Equal-payload loading comparison. Temporary packs are deleted after measurement.
const Cache := preload("res://scripts/supply_chain_3d/bake_cache.gd")
const Data := preload("res://scripts/supply_chain_3d/bake_data.gd")
const Assets := preload("res://scripts/supply_chain_3d/assets.gd")
const OUTPUT := "res://../outputs/supply-chain-3d/fast-prepared-bakes/"
var scratch := ""
var report := {"terrain": [], "buildings": [], "warm_os_cache": true,
	"notes": "Resource loading only, with fresh embedded resources. Building tests hold identical model geometry; terrain always remains separate from building assets."}

func _region(tid: String) -> String:
	var x := int(tid.get_slice("_", 1)) - 1
	var y := int(tid.get_slice("_", 2)) - 1
	return "%d_%d" % [x / 3, y / 3]

func _save(name: String, payload: Dictionary) -> String:
	var data := Data.new()
	data.schema = Cache.SCHEMA
	data.key = name
	data.data = payload
	var path := scratch.path_join(name + ".res")
	assert(ResourceSaver.save(data, path, 0) == OK)
	return path

func _measure(paths: Array) -> Dictionary:
	var held := []
	var bytes := 0
	var elapsed := 0.0
	var largest := 0.0
	for path in paths:
		bytes += FileAccess.open(path, FileAccess.READ).get_length()
		var start := Time.get_ticks_usec()
		var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as Data
		var ms := (Time.get_ticks_usec() - start) / 1000.0
		assert(loaded != null)
		held.append(loaded)
		elapsed += ms
		largest = maxf(largest, ms)
	RenderingServer.force_draw(false)
	return {"files": paths.size(), "bytes": bytes, "resource_load_ms": elapsed, "longest_load_ms": largest}

func _ready() -> void:
	TelemetryState.enabled = false
	SaveLoad.autosave_enabled = false
	get_tree().create_timer(300.0).timeout.connect(func() -> void: get_tree().quit(2))
	scratch = "/private/tmp/bake-granularity-%d" % Time.get_ticks_usec()
	assert(DirAccess.make_dir_recursive_absolute(scratch) == OK)
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	await get_tree().process_frame
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Cache.BUNDLED.path_join("manifest.json")))
	var tiles := []
	for tid in manifest.tiles:
		if _region(tid) == _region("tile_10_10"): tiles.append(tid)
	tiles.sort()
	assert(tiles.size() == 9)
	for tier in ["medium", "near"]:
		var combined := {}
		var paths := []
		for tid in tiles:
			var path: String = Cache.BUNDLED.path_join(str(manifest.tiles[tid][tier]) + ".res")
			combined[tid] = (ResourceLoader.load(path) as Data).data
			paths.append(path)
		var region_path := _save("terrain-region-" + tier, combined)
		var tile_bytes := 0
		for path in paths: tile_bytes += FileAccess.open(path, FileAccess.READ).get_length()
		assert(FileAccess.open(region_path, FileAccess.READ).get_length() > tile_bytes * 0.8, "Region comparison must embed the same payloads")
		combined.clear()
		for round_index in 3:
			for count in [1, 3, 9]:
				for mode in (["tile", "region"] if round_index % 2 == 0 else ["region", "tile"]):
					var result := _measure(paths.slice(0, count) if mode == "tile" else [region_path])
					result.merge({"tier": tier, "round": round_index, "mode": mode, "requested_tiles": count,
						"loaded_tiles": count if mode == "tile" else 9})
					report.terrain.append(result)
					await get_tree().process_frame
		DirAccess.remove_absolute(region_path)
		print("[GRANULARITY] terrain ", tier, " complete")
	# Compare spatial layouts on the real 61-tile initial / 9-tile adjacent trace.
	var trace: Array = JSON.parse_string(FileAccess.get_file_as_string("res://../outputs/supply-chain-3d/closest-cache-profile/profile.json"))
	var loaded_regions := {}
	var spatial := []
	for view in trace.slice(0, 2):
		var requested: Array = view.added_visible + view.added_offscreen
		var incoming := {}
		for tid in requested:
			if not loaded_regions.has(_region(tid)): incoming[_region(tid)] = true
		var loaded := 0
		for tid in manifest.tiles:
			if incoming.has(_region(tid)): loaded += 1
		spatial.append({"view": view.view, "tile_payloads": requested.size(), "region_files": incoming.size(), "region_tile_payloads": loaded})
		loaded_regions.merge(incoming)
	report.spatial_trace = spatial
	# Pick the region containing the most real building instances.
	var root: Dictionary = (ResourceLoader.load(Cache.BUNDLED.path_join(manifest.continent_key + ".res")) as Data).data
	var scenery: Dictionary = (ResourceLoader.load(Cache.BUNDLED.path_join(manifest.scenery_key + ".res")) as Data).data
	var regions := {}
	for iid in scenery.standing:
		var frame: Dictionary = scenery.standing[iid]
		if str(frame.key).is_empty(): continue
		var nearest := ""
		var distance := INF
		for tid in root.metadata.visibility.hulls:
			var at: Vector3 = root.metadata.visibility.hulls[tid][0]
			var delta := Vector2(at.x - frame.position.x, at.z - frame.position.z).length_squared()
			if delta < distance: distance = delta; nearest = tid
		(regions.get_or_add(_region(nearest), []) as Array).append({"iid": iid, "tile": nearest, "key": str(frame.key)})
	var instances := []
	for members in regions.values():
		if members.size() > instances.size(): instances = members
	assert(not instances.is_empty())
	var models := {}
	for instance in instances:
		var key: String = instance.key
		if models.has(key): continue
		var mesh := Assets.mesh_for(key)
		var outline := Assets.contour_for(key)
		var shape := Assets.picking_shape(key)
		models[key] = {"mesh": mesh.duplicate() if mesh != null else null,
			"outline": outline.duplicate() if outline != null else null,
			"picking": shape.duplicate() if shape != null else null}
	var modes := {}
	for mode in ["building", "tile", "region", "archetype"]:
		var groups := {}
		for instance in instances:
			var group: String = {"building": str(instance.iid), "tile": str(instance.tile), "region": "all", "archetype": str(instance.key)}[mode]
			var entry: Dictionary = groups.get_or_add(group, {"models": {}, "instances": []})
			entry.models[instance.key] = models[instance.key]
			entry.instances.append(instance)
		var index := 0
		for group in groups.values():
			group.path = _save("buildings-%s-%d" % [mode, index], {"models": group.models})
			index += 1
		modes[mode] = groups.values()
	var selected_tile: String = instances[0].tile
	for round_index in 3:
		for selection in ["one_building", "one_tile", "whole_region"]:
			var wanted := {}
			for instance in instances:
				if selection == "one_building" and instance.iid != instances[0].iid: continue
				if selection == "one_tile" and instance.tile != selected_tile: continue
				wanted[instance.iid] = true
			for mode in (modes.keys() if round_index % 2 == 0 else ["archetype", "region", "tile", "building"]):
				var paths := []
				var payloads := 0
				for group in modes[mode]:
					if not group.instances.any(func(item: Dictionary) -> bool: return wanted.has(item.iid)): continue
					paths.append(group.path)
					payloads += group.models.size()
				var result := _measure(paths)
				result.merge({"mode": mode, "selection": selection, "round": round_index,
					"requested_buildings": wanted.size(), "model_payloads": payloads})
				report.buildings.append(result)
				await get_tree().process_frame
	report.building_sample = {"instances": instances.size(), "archetypes": models.size(), "tiles": modes.tile.size()}
	FileAccess.open(OUTPUT.path_join("granularity.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	for file in DirAccess.get_files_at(scratch): DirAccess.remove_absolute(scratch.path_join(file))
	DirAccess.remove_absolute(scratch)
	print("[GRANULARITY] complete ", JSON.stringify(report.building_sample))
	get_tree().quit()
