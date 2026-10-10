extends RefCounted
## Offline release gate. The runtime uses content-addressed resources directly.
const Cache := preload("res://scripts/supply_chain_3d/bake_cache.gd")
const Detail := preload("res://scripts/supply_chain_3d/detail.gd")
const Paint := preload("res://scripts/supply_chain_3d/terrain_paint.gd")
const VISIBILITY_VERSION := 4
const MANIFEST_SCHEMA := 4
const TILE_TIERS := {"medium": 1, "near": 2}

static func file_record(directory: String, key: String) -> Dictionary:
	var path := directory.path_join(key + ".res")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {}
	return {"bytes": file.get_length(), "sha256": FileAccess.get_sha256(path)}

static func validate_header(manifest: Dictionary) -> bool:
	return manifest.get("schema", -1) == MANIFEST_SCHEMA and manifest.get("complete", false) and manifest.get("storage") in ["raw", "zstd"] \
		and manifest.get("tiles", {}).size() == int(manifest.get("tile_count", -1)) \
		and int(manifest.get("tile_count", 0)) > 0

static func validate(directory: String, host: Node) -> Dictionary:
	var manifest_path := directory.path_join("manifest.json")
	var result := {"ok": false, "errors": [], "resources": 0, "tiles": 0, "bytes": 0,
		"medium_decoded_bytes": 0, "near_decoded_bytes": 0, "near_disk_bytes": 0}
	if not FileAccess.file_exists(manifest_path): result.errors.append("Missing package manifest"); return result
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not parsed is Dictionary or not validate_header(parsed): result.errors.append("Incomplete/invalid package manifest"); return result
	var manifest: Dictionary = parsed
	var fingerprints_path := directory.path_join("source_fingerprints.json")
	var fingerprints: Variant = JSON.parse_string(FileAccess.get_file_as_string(fingerprints_path)) if FileAccess.file_exists(fingerprints_path) else null
	if not fingerprints is Dictionary or not Cache.fingerprints_match(fingerprints, Cache.source_fingerprints()):
		result.errors.append("Missing/stale export source fingerprints")
	var required := {str(manifest.get("continent_key", "")): true, str(manifest.get("scenery_key", "")): true}
	for entry in manifest.tiles.values():
		required[str(entry.get("base", ""))] = true
		for name in TILE_TIERS: required[str(entry.get(name, ""))] = true
	if required.has("") or required.size() != manifest.resources.size(): result.errors.append("Incomplete resource index")
	for key in required:
		if not manifest.resources.has(key): result.errors.append("Unindexed resource: " + key)
	var cache := Cache.new()
	cache.enabled = true
	cache.bundled_directory = directory
	cache.directory = "res://__no_user_cache_for_package_validation__"
	for key in manifest.resources:
		if Cache.storage_format(directory.path_join(key + ".res")) != manifest.storage: result.errors.append("Wrong resource storage format: " + key)
		var record := file_record(directory, key)
		var expected: Dictionary = manifest.resources[key]
		if int(record.get("bytes", -1)) != int(expected.get("bytes", -2)) or record.get("sha256") != expected.get("sha256"):
			result.errors.append("Missing or changed resource: " + key)
		for dependency in ResourceLoader.get_dependencies(directory.path_join(key + ".res")):
			var path: String = dependency.get_slice("::", dependency.get_slice_count("::") - 1)
			if not path.begins_with("res://") or not ResourceLoader.exists(path):
				result.errors.append("Nonportable/missing dependency: " + path)
		result.bytes += int(record.get("bytes", 0))
		result.resources += 1
	var root := cache.read(manifest.continent_key)
	var scenery := cache.read(manifest.scenery_key)
	if root.is_empty() or scenery.is_empty(): result.errors.append("Missing continent/scenery data"); return result
	var visibility: Dictionary = root.get("metadata", {}).get("visibility", {})
	if visibility.get("version", -1) != VISIBILITY_VERSION or visibility.get("hulls", {}).size() != manifest.tiles.size():
		result.errors.append("Incomplete visibility bounds"); return result
	for tid in manifest.tiles:
		var entry: Dictionary = manifest.tiles[tid]
		if root.get("tile_chunks", {}).get(tid) != entry.base: result.errors.append("Wrong base reference: " + tid)
		var base := cache.read(entry.base)
		if base.is_empty(): result.errors.append("Missing tile data: " + tid); continue
		if base.get("detail_source", "") != Cache.source_key("detail"): result.errors.append("Stale local detail: " + tid)
		var detail: Dictionary = base.get("local_detail", {})
		if not detail.get("clutter_mesh") is ArrayMesh or not detail.get("glint_mesh") is ArrayMesh or not detail.get("tree_cards") is Dictionary:
			result.errors.append("Missing prepared local detail: " + tid)
		if not base.get("pick_shape") is ConcavePolygonShape3D: result.errors.append("Missing base picking shape: " + tid)
		for field in ["mesh", "rim_mesh", "lip_mesh", "roads_mesh"]:
			if not base.get(field) is ArrayMesh: result.errors.append("Invalid base " + field + ": " + tid)
		var hull: PackedVector3Array = visibility.hulls.get(tid, PackedVector3Array())
		if hull.size() != 9: result.errors.append("Invalid visibility hull: " + tid); continue
		var bounds := AABB(hull[1], Vector3.ZERO)
		for p in hull: bounds = bounds.expand(p)
		for mesh in [base.mesh, base.rim_mesh, base.lip_mesh]:
			if mesh.get_surface_count() > 0 and not bounds.encloses(mesh.get_aabb()): result.errors.append("Terrain outside visibility bounds: " + tid)
		for name in TILE_TIERS:
			var key: String = str(entry.get(name, ""))
			var payload := cache.read(key)
			if not payload.get("mesh") is ArrayMesh or not payload.get("texture") is Texture2D:
				result.errors.append("Invalid " + name + " payload: " + tid); continue
			if not payload.get("pick_shape") is ConcavePolygonShape3D: result.errors.append("Missing " + name + " picking shape: " + tid)
			var texture: Texture2D = payload.texture
			var image := texture.get_image()
			var width: int = Detail.TEXTURES[TILE_TIERS[name]]
			if texture.get_width() != width or texture.get_height() != roundi(width * Paint.EXTENT.y / Paint.EXTENT.x) or image == null or not image.has_mipmaps():
				result.errors.append("Wrong " + name + " resolution/mipmaps: " + tid)
			else: result[name + "_decoded_bytes"] += image.get_data_size()
			if name == "near": result.near_disk_bytes += int(manifest.resources.get(key, {}).get("bytes", 0))
			if payload.mesh.get_surface_count() > 0 and not bounds.encloses(payload.mesh.get_aabb()):
				result.errors.append("Terrain outside visibility bounds: " + tid + ":" + name)
		result.tiles += 1
		if result.tiles % 30 == 0: await host.get_tree().process_frame
	result.ok = result.errors.is_empty() and result.tiles == manifest.tile_count
	return result
