extends Node
## Read-only production audit and isolated collision-sharing experiment.
## Run with --trial-output=/private/tmp/... [--audit-geometry]. Nothing installed.
const Data = preload("res://scripts/supply_chain_3d/bake_data.gd")
const Storage = preload("res://tools/supply_chain_3d/repack_bake_storage.gd")
const Exact = preload("res://tools/supply_chain_3d/trials/shared_mesh_collision.gd")
const Direct = preload("res://tools/supply_chain_3d/trials/direct_mesh_collision.gd")
const Package = preload("res://tools/supply_chain_3d/bake_package.gd")
const DIRECTORY = "res://assets/supply_chain_3d/bakes"
const TILES = ["tile_4_9", "tile_10_10", "tile_11_5", "tile_11_6", "tile_15_16"]

func _ready() -> void: call_deferred("run")

func run() -> void:
	var output := ""
	var audit := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--trial-output="): output = arg.trim_prefix("--trial-output=")
		if arg == "--audit-geometry": audit = true
	if not output.begins_with("/private/tmp/") or ".." in output:
		push_error("Trial output must be a new directory inside /private/tmp/"); get_tree().quit(1); return
	if DirAccess.dir_exists_absolute(output):
		push_error("Trial output already exists; choose a new directory"); get_tree().quit(1); return
	DirAccess.make_dir_recursive_absolute(output)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIRECTORY + "/manifest.json"))
	var report := {"records": [], "errors": [], "engine": Engine.get_version_info().string,
		"renderer": RenderingServer.get_current_rendering_method(), "sample_before": 0,
		"sample_after": {}, "production_manifest_sha256": FileAccess.get_sha256(DIRECTORY + "/manifest.json")}
	for tid in TILES:
		for tier in ["base", "medium", "near"]:
			var key: String = manifest.tiles[tid][tier]
			var path := DIRECTORY + "/" + key + ".res"
			var original := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as Data
			var old_shape: ConcavePolygonShape3D = original.data.pick_shape
			report.sample_before += int(manifest.resources[key].bytes)
			for mode in ["exact", "direct"]:
				var candidate := Data.new()
				candidate.schema = original.schema; candidate.key = original.key
				candidate.data = original.data.duplicate()
				var shape: ConcavePolygonShape3D = Exact.new() if mode == "exact" else Direct.new()
				shape.source_mesh = original.data.mesh
				shape.backface_collision = old_shape.backface_collision
				shape.margin = old_shape.margin; shape.custom_solver_bias = old_shape.custom_solver_bias
				candidate.data.pick_shape = shape
				var destination := output.path_join(key + "-" + mode + ".res")
				if ResourceSaver.save(candidate, destination, ResourceSaver.FLAG_COMPRESS) != OK:
					report.errors.append("Save failed: " + key); continue
				var best := FileAccess.get_file_as_bytes(destination)
				var raw := Storage.decode(best)
				for block in Storage.BLOCKS:
					var packed := Storage.encode(raw, block)
					if packed.size() < best.size(): best = packed
				var file := FileAccess.open(destination, FileAccess.WRITE)
				file.store_buffer(best); file.close()
				var loaded := ResourceLoader.load(destination, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as Data
				var new_shape: ConcavePolygonShape3D = loaded.data.pick_shape
				var faces_equal := new_shape.get_faces() == old_shape.get_faces()
				if mode == "exact" and not faces_equal: report.errors.append("Exact faces changed: " + key)
				if new_shape.source_mesh != loaded.data.mesh: report.errors.append("Mesh not shared: " + key)
				if new_shape.backface_collision != old_shape.backface_collision or new_shape.margin != old_shape.margin or new_shape.custom_solver_bias != old_shape.custom_solver_bias:
					report.errors.append("Shape properties changed: " + key)
				var compared := loaded.data.duplicate(); compared.pick_shape = old_shape
				if not Package.same_payload(original.data, compared): report.errors.append("Noncollision payload changed: " + key)
				var worst := 0.0
				var old_faces := old_shape.get_faces(); var new_faces := new_shape.get_faces()
				if old_faces.size() != new_faces.size(): report.errors.append("Triangle count changed: " + key)
				else:
					for i in old_faces.size(): worst = maxf(worst, old_faces[i].distance_to(new_faces[i]))
				# Interleave both orders; no retained-resource cache, but OS cache is warm.
				var times := {"old": [], "new": []}
				for iteration in 8:
					for label in (["old", "new"] if iteration % 2 == 0 else ["new", "old"]):
						var time := load_time(path if label == "old" else destination)
						if iteration > 0: times[label].append(time)
				for label in times: times[label].sort()
				# Also confirm the real threaded ResourceLoader handles the custom setter.
				if ResourceLoader.load_threaded_request(destination, "", false, ResourceLoader.CACHE_MODE_IGNORE_DEEP) != OK:
					report.errors.append("Threaded request failed: " + key)
				else:
					while ResourceLoader.load_threaded_get_status(destination) == ResourceLoader.THREAD_LOAD_IN_PROGRESS: await get_tree().process_frame
					var threaded := ResourceLoader.load_threaded_get(destination) as Data
					if threaded == null or threaded.data.pick_shape.source_mesh != threaded.data.mesh or threaded.data.pick_shape.get_faces() != new_faces:
						report.errors.append("Threaded sharing/face check failed: " + key)
				report.sample_after[mode] = report.sample_after.get(mode, 0) + best.size()
				report.records.append({"tile": tid, "tier": tier, "mode": mode, "before": manifest.resources[key].bytes,
					"after": best.size(), "exact_collision": faces_equal, "max_position_error": worst,
					"old_load_us": times.old[3], "new_load_us": times.new[3]})
				if FileAccess.get_sha256(path) != manifest.resources[key].sha256: report.errors.append("Source checksum changed: " + key)
			await get_tree().process_frame
	if audit: report.geometry_audit = await audit_geometry(manifest)
	report.ok = report.errors.is_empty()
	Storage.save_json(output.path_join("report.json"), report)
	print("[SHARED GEOMETRY] ", JSON.stringify(report))
	get_tree().quit(0 if report.ok else 1)

func load_time(path: String) -> int:
	var start := Time.get_ticks_usec()
	var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	var elapsed := Time.get_ticks_usec() - start
	assert(resource != null)
	return elapsed

func audit_geometry(manifest: Dictionary) -> Dictionary:
	var groups := {}; var resources := 0
	for key in manifest.resources:
		if not (key.begins_with("tile-") or key.begins_with("base-tile-")): continue
		var resource := ResourceLoader.load(DIRECTORY + "/" + key + ".res", "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as Data
		for field in ["mesh", "pick_shape", "rim_mesh", "lip_mesh"]:
			var item: Resource = resource.data.get(field)
			if item == null: continue
			var values := []
			if item is Mesh:
				for surface in item.get_surface_count(): values.append([item.surface_get_primitive_type(surface), item.surface_get_arrays(surface)])
			elif item is ConcavePolygonShape3D: values = [item.get_faces(), item.backface_collision, item.margin, item.custom_solver_bias]
			else: continue
			var bytes := var_to_bytes(values)
			var hash := HashingContext.new(); hash.start(HashingContext.HASH_SHA256); hash.update(bytes)
			var id := hash.finish().hex_encode()
			if not groups.has(id): groups[id] = {"count": 0, "empty": values.is_empty()}
			groups[id].count += 1
		resources += 1
		if resources % 100 == 0: await get_tree().process_frame
	var duplicates := 0; var empty_duplicates := 0
	for item in groups.values():
		if item.count > 1:
			if item.empty: empty_duplicates += item.count - 1
			else: duplicates += item.count - 1
	return {"resources": resources, "unique_geometry_payloads": groups.size(), "nonempty_duplicate_instances": duplicates,
		"empty_duplicate_instances": empty_duplicates, "fields": ["mesh", "pick_shape", "rim_mesh", "lip_mesh"]}
