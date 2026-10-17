extends RefCounted
## Trial only. Keep at most two forthcoming tiles' native resources in flight.
## Drain every request, including after camera changes; never generate a bake.
const VERSION := 3
var pending := {}
var held := {}
var requested := 0
var peak_requests := 0
var peak_disk_bytes := 0
var errors := []
const MAX_BYTES := 16 * 1024 * 1024

func poll() -> void:
	for path in pending.keys():
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS: continue
		if status == ResourceLoader.THREAD_LOAD_LOADED: held[path] = ResourceLoader.load_threaded_get(path)
		else: errors.append(path)
		pending.erase(path)

func enqueue(builder: RefCounted, wanted: Array, fine: Dictionary, index: int) -> void:
	poll()
	var bytes := 0
	for cost in pending.values(): bytes += int(cost)
	# Current tile plus two ahead. Only native terrain resources; artwork uses
	# the existing bounded loader and remains shared across tiles.
	for item in wanted.slice(index, mini(wanted.size(), index + 3)):
		var tid := str(item.tile)
		var paths: Dictionary = builder.progressive_manifest.get(tid, {})
		if paths.is_empty(): continue
		var tier := int(fine.get(tid, 0))
		if builder.backdrop_pending: tier = maxi(tier, 1)
		# The runtime retains decoded dictionaries rather than the outer Resource.
		# ResourceLoader.has_cached alone would reread already-resident terrain.
		var retained: Dictionary = builder.resource_cache.entries.get(tid,{})
		var data: Dictionary = builder.terrain_cache.get(builder.terrain_key(tid),retained.get("data",{}))
		var chunk: Dictionary = builder._chunk_data.get(tid,retained.get("chunk",{}))
		var keys: Array = []
		if chunk.is_empty(): keys.append(paths.base)
		for level in range(1,tier+1):
			if data.is_empty() or data.meshes[level] == null: keys.append(paths.medium if level==1 else paths.near)
		for key in keys:
			var path: String = builder.bake_cache.bundled_directory.path_join(str(key) + ".res")
			if pending.has(path) or held.has(path) or ResourceLoader.has_cached(path): continue
			var file := FileAccess.open(path, FileAccess.READ)
			if file == null: continue
			var cost := file.get_length(); file.close()
			if pending.size() >= 9 or bytes + cost > MAX_BYTES: continue
			if ResourceLoader.load_threaded_request(path, "", false, ResourceLoader.CACHE_MODE_REUSE) == OK:
				pending[path] = cost; bytes += cost; requested += 1
	peak_requests = maxi(peak_requests, pending.size())
	peak_disk_bytes = maxi(peak_disk_bytes, bytes)

func ready_current(tree: SceneTree, builder: RefCounted, tid: String) -> void:
	var paths: Dictionary = builder.progressive_manifest.get(tid, {})
	while true:
		poll()
		var waiting := false
		for key in paths.values():
			if pending.has(builder.bake_cache.bundled_directory.path_join(str(key) + ".res")): waiting = true
		if not waiting: return
		await tree.process_frame

func release_current(builder: RefCounted, tid: String) -> void:
	for key in builder.progressive_manifest.get(tid, {}).values():
		held.erase(builder.bake_cache.bundled_directory.path_join(str(key) + ".res"))

func finish(tree: SceneTree) -> void:
	while not pending.is_empty():
		poll()
		if not pending.is_empty(): await tree.process_frame
	held.clear()
