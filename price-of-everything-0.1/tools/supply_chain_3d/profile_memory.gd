extends "res://tools/supply_chain_3d/capture.gd"
## Resource payload accounting, not an OS RSS or physical GPU allocation measurement.
const Sprites := preload("res://scripts/supply_chain_3d/far_sprites.gd")
const AssetLibrary := preload("res://scripts/supply_chain_3d/assets.gd")

func _mesh_bytes(mesh: Mesh) -> Dictionary:
	var result := {"packed_bytes": 0, "decoded_array_bytes": 0, "vertices": 0, "face_bytes": 0}
	if mesh == null: return result
	for i in mesh.get_surface_count():
		var surface := RenderingServer.mesh_get_surface(mesh.get_rid(), i)
		for key in ["vertex_data", "attribute_data", "skin_data", "index_data", "blend_shape_data"]:
			result.packed_bytes += (surface.get(key, PackedByteArray()) as PackedByteArray).size()
		for lod in surface.get("lods", []): result.packed_bytes += lod.index_data.size()
		for array in mesh.surface_get_arrays(i):
			if array != null: result.decoded_array_bytes += array.to_byte_array().size()
		result.vertices += mesh.surface_get_array_len(i)
	# Face positions only: a physics BVH and native object overhead are additional.
	result.face_bytes = mesh.get_faces().to_byte_array().size()
	return result

func _texture_bytes(texture: Texture2D) -> Dictionary:
	var image := texture.get_image()
	return {"width": image.get_width(), "height": image.get_height(), "format": image.get_format(),
		"mipmaps": image.get_mipmap_count(), "bytes": image.get_data_size()}

func _file_bytes(builder: RefCounted, key: String) -> int:
	for directory in [builder.bake_cache.BUNDLED, builder.bake_cache.directory]:
		var path: String = directory.path_join(key + ".res")
		if FileAccess.file_exists(path):
			var file := FileAccess.open(path, FileAccess.READ)
			return file.get_length()
	return 0

func _save(result: Dictionary) -> void:
	var file := FileAccess.open("/private/tmp/supply_memory_profile.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))

func _memory_counters() -> Dictionary:
	return {"godot_cpu_bytes": Performance.get_monitor(Performance.MEMORY_STATIC),
		"texture_bytes": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED),
		"buffer_bytes": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED)}

func _settle() -> void:
	for i in 4:
		RenderingServer.force_draw(false)
		await get_tree().process_frame

func _residency_probe(builder: RefCounted, samples: Array) -> Array:
	# Hold decoded resources, without constructing offscreen nodes or colliders.
	await _settle()
	var result: Array = [{"tiles": 0, "memory": _memory_counters()}]
	var retained: Array = []
	var count := 0
	for sample in samples.slice(0, 90):
		retained.append(builder.bake_cache.read(builder.tile_chunks[sample.tile]))
		retained.append(builder.bake_cache.read(builder.tile_bake_key(sample.tile, 1)))
		count += 1
		if count % 30 == 0:
			await _settle()
			result.append({"tiles": count, "memory": _memory_counters()})
	retained.clear()
	await _settle()
	result.append({"tiles": 0, "after_release": true, "memory": _memory_counters()})
	return result

func _continent_review(board: Control, home: Dictionary) -> void:
	var start := Time.get_ticks_usec()
	await board.set_all_tiles(true, false)
	while not board.detail_ready(): await get_tree().process_frame
	board.set_process(false)
	var builder: RefCounted = board._builder
	var result := {"continent_key": builder._continent_key, "tile_count": builder.tiles.size(),
		"startup_ms": (Time.get_ticks_usec() - start) / 1000.0, "initial_cache_writes": builder.bake_cache.writes,
		"baked_hulls": builder.view_hulls.size(), "hull_payload_bytes": 0,
		"visibility_file_bytes": _file_bytes(builder, builder.visibility_bake_key()),
		"far_texture": _texture_bytes(builder.continent.texture), "far_meshes": {}, "base_tiles": [], "medium_samples": [],
		"shared_sprite_textures": {}, "shared_asset_meshes": {}, "missing_medium_tiles": 0}
	for hull in builder.view_hulls.values(): result.hull_payload_bytes += hull.to_byte_array().size()
	var initial: Dictionary = board.capture_camera()
	var state := initial.duplicate()
	state.target = home.target
	state.span = 1100.0
	board.restore_camera(state)
	start = Time.get_ticks_usec()
	var wanted: Array = board._wanted_detail_tiles()
	result.first_visibility_ms = (Time.get_ticks_usec() - start) / 1000.0
	result.wanted_tiles = wanted.size()
	result.visible_tiles = wanted.filter(func(item: Dictionary) -> bool: return item.visible).size()
	board.restore_camera(initial)
	for key in ["mesh", "roads_mesh", "props_mesh", "rim_mesh", "lip_mesh"]:
		result.far_meshes[key] = _mesh_bytes(builder.continent.get(key))
	for tid in builder.tiles:
		var key: String = builder.tile_chunks[tid]
		var data: Dictionary = builder.bake_cache.read(key)
		var entry := {"tile": tid, "type": builder.tiles[tid].type, "file_bytes": _file_bytes(builder, key), "meshes": {}}
		for field in ["mesh", "roads_mesh", "rim_mesh", "lip_mesh"]: entry.meshes[field] = _mesh_bytes(data.get(field))
		result.base_tiles.append(entry)
		key = builder.tile_bake_key(str(tid), 1)
		var file_bytes := _file_bytes(builder, key)
		if file_bytes > 0:
			data = builder.bake_cache.read(key)
			result.medium_samples.append({"tile": tid, "type": builder.tiles[tid].type,
				"file_bytes": file_bytes, "mesh": _mesh_bytes(data.mesh), "texture": _texture_bytes(data.texture)})
		else: result.missing_medium_tiles += 1
		if result.base_tiles.size() % 30 == 0:
			print("[MEMORY] inventoried ", result.base_tiles.size(), " tiles; medium samples ", result.medium_samples.size())
			await get_tree().process_frame
	var keys := {}
	for frame in builder.standing_frames.values(): keys[str(frame.key)] = true
	for key in builder.continent.get("tree_sprites", {}): keys[key] = true
	for key in builder.continent.get("decor_sprites", {}): keys[key] = true
	for key in keys:
		result.shared_asset_meshes[key] = _mesh_bytes(AssetLibrary.mesh_for(key))
		for tier in [0, 1]:
			var directory: String = Sprites.DIRECTORY if tier == 0 else Sprites.MEDIUM_DIRECTORY
			for suffix in ["", "_depth"]:
				var path: String = directory + key + suffix + ".png"
				if ResourceLoader.exists(path): result.shared_sprite_textures[path] = _texture_bytes(load(path))
		await get_tree().process_frame
	result.unique_asset_types = keys.size()
	result.scenery_serialized_bytes = var_to_bytes([builder.tree_placements, builder.standing_frames, builder.static_shadows]).size()
	result.residency_probe = await _residency_probe(builder, result.medium_samples)
	_save(result)
	print("[MEMORY] complete: ", result.medium_samples.size(), " current medium bakes sampled; visibility_ms=", result.first_visibility_ms)
