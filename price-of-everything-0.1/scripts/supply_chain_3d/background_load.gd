extends RefCounted
## One low-priority digest worker and one resource request at a time. Scene
## construction stays on the main thread; cancellation drains pending requests.
const Cache := preload("res://scripts/supply_chain_3d/bake_cache.gd")
var cancelled := false
var done := false
var resources: Dictionary = {}
var profile := {}
var stage := "inputs"

func digest(tree: SceneTree, values: Array) -> String:
	var worker := Thread.new()
	if worker.start(Cache.digest.bind(values), Thread.PRIORITY_LOW) != OK: return ""
	while worker.is_alive(): await tree.process_frame
	return str(worker.wait_to_finish())

static func _duplicate_model(model: Dictionary) -> Dictionary:
	# Only immutable data from a loaded resource, never live game dictionaries.
	# Dictionary.duplicate(true) copies containers, retaining Resource handles.
	return model.duplicate(true)

func copy_model(tree: SceneTree, model: Dictionary) -> Dictionary:
	var worker := Thread.new()
	if worker.start(_duplicate_model.bind(model), Thread.PRIORITY_LOW) != OK: return {}
	while worker.is_alive(): await tree.process_frame
	return worker.wait_to_finish()

func resource(tree: SceneTree, path: String) -> Resource:
	stage = path.get_file()
	if cancelled or not ResourceLoader.exists(path): return null
	if resources.has(path): return resources[path]
	var started := Time.get_ticks_usec()
	if ResourceLoader.load_threaded_request(path, "", false, ResourceLoader.CACHE_MODE_REUSE) != OK: return null
	profile.max_request_ms = maxf(profile.get("max_request_ms", 0.0), (Time.get_ticks_usec()-started)/1000.0)
	while ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await tree.process_frame
	var status := ResourceLoader.load_threaded_get_status(path)
	started = Time.get_ticks_usec()
	var loaded: Resource = ResourceLoader.load_threaded_get(path) if status == ResourceLoader.THREAD_LOAD_LOADED else null
	profile.max_get_ms = maxf(profile.get("max_get_ms", 0.0), (Time.get_ticks_usec()-started)/1000.0)
	if cancelled: return null
	if loaded != null: resources[path] = loaded
	return loaded

func bake(tree: SceneTree, cache: RefCounted, key: String) -> Dictionary:
	for directory in [cache.bundled_directory, cache.directory]:
		var loaded := await resource(tree, str(directory).path_join(key + ".res")) as Cache.Data
		if loaded != null and loaded.schema == Cache.SCHEMA and loaded.key == key and not loaded.data.is_empty():
			cache.hits += 1
			if directory == cache.bundled_directory: cache.bundled_hits += 1
			return loaded.data
	return {}
