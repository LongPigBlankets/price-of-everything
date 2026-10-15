extends RefCounted
const Load := preload("res://scripts/supply_chain_3d/background_load.gd")
const Sprites := preload("res://scripts/supply_chain_3d/far_sprites.gd")
const Assets := preload("res://scripts/supply_chain_3d/assets.gd")

static func prepare(board: Control, builder: RefCounted, tid: String, tier: int, generation: int) -> bool:
	var tree := board.get_tree()
	var loader := Load.new()
	var key: String = builder.terrain_key(tid)
	var retained: Dictionary = builder.resource_cache.restore(tid)
	var data: Dictionary = builder.terrain_cache.get(key, retained.get("data", {}))
	var chunk: Dictionary = builder._chunk_data.get(tid, retained.get("chunk", {}))
	var paths: Dictionary = builder.progressive_manifest.get(tid, {})
	if paths.is_empty(): return true # Nonpackaged worlds retain their normal repair path.
	var wanted := maxi(1, tier) if builder.backdrop_pending else tier
	var native_paths: Array = []
	var cache: RefCounted = builder.bake_cache
	if chunk.is_empty(): native_paths.append(cache.bundled_directory.path_join(str(paths.base)+".res"))
	for level in range(1,wanted+1):
		if data.is_empty() or data.meshes[level]==null:
			native_paths.append(cache.bundled_directory.path_join(str(paths["medium" if level==1 else "near"])+".res"))
	await loader.batch(tree,native_paths)
	if generation != board._generation: return false
	if chunk.is_empty(): chunk = await loader.bake(tree, builder.bake_cache, paths.base)
	if generation != board._generation or chunk.is_empty(): return false
	if data.is_empty():
		data = {"textures":[null,null,null], "meshes":[chunk.mesh,null,null],
			"shapes":[chunk.get("pick_shape"),null,null], "streamed":true,"ground_id":builder.ground.get_instance_id()}
	for level in range(1, wanted+1):
		if data.meshes[level] != null: continue
		var fine: Dictionary = await loader.bake(tree, builder.bake_cache, paths["medium" if level==1 else "near"])
		if generation != board._generation or fine.is_empty(): return false
		data.textures[level] = fine.texture; data.meshes[level] = fine.mesh
		data.shapes[level] = fine.get("pick_shape")
	if builder.backdrop_pending:
		data.textures[0] = data.textures[1]; data.meshes[0] = data.meshes[1]; data.shapes[0] = data.shapes[1]
	else:
		data.textures[0] = builder.continent.texture; data.meshes[0] = chunk.mesh
		data.shapes[0] = chunk.get("pick_shape")
	var art := {}
	var art_paths: Array = []
	for standing in builder._visibility_standing.get(tid, []): art[builder.standing_key(standing)] = true
	for level in range(1,4): art[Assets.key_for("tree",level)] = true
	for asset in art:
		for detail in range(0, 2 if wanted>0 else 1):
			if Sprites.entry(asset, detail).is_empty(): continue
			var directory: String = Sprites.DIRECTORY if detail==0 else Sprites.MEDIUM_DIRECTORY
			for suffix in [".png","_depth.png"]:
				art_paths.append(directory+asset+suffix)
			var lit_texture := str(Sprites.entry(asset,detail).get("lit_texture", ""))
			if not lit_texture.is_empty():
				art_paths.append(directory+lit_texture)
		if wanted==2 or asset.begins_with("pylon_") or asset.begins_with("port_"):
			art_paths.append(Assets.DIRECTORY+asset+".glb")
	if not chunk.get("local_detail", {}).get("farms", {}).is_empty():
		art_paths.append(Assets.DIRECTORY+Assets.key_for("farm_crop_cell",1)+".glb")
	await loader.batch(tree,art_paths)
	if generation != board._generation: return false
	builder._chunk_data[tid] = chunk
	builder.terrain_cache[key] = data
	# Keep texture handles alive until standing nodes bind them later this frame.
	builder.tile_load_resources = loader.resources
	return true
