extends "res://tests/test_base.gd"
const FEATURE := "supply_chain_3d"
const Cache := preload("res://scripts/supply_chain_3d/bake_cache.gd")
const Load := preload("res://scripts/supply_chain_3d/background_load.gd")
const Package := preload("res://tools/supply_chain_3d/bake_package.gd")

func _test_bake_values_sync_async_and_private_worlds() -> void:
	var directory := "user://bake-values-%d" % Time.get_ticks_usec()
	var cache := Cache.new(); cache.enabled=true; cache.directory=directory; cache.bundled_directory=directory
	var batch := preload("res://scripts/supply_chain_3d/geometry.gd").Batch.new()
	batch.box(Vector3.ZERO,Vector3.ONE*10.0,Color.WHITE)
	var mesh := batch.mesh()
	var picture := Image.create(4,4,false,Image.FORMAT_RGBA8); picture.fill(Color.BLUE)
	var original := {"roads":[{"height":2.5}],"mesh":mesh,"shape":mesh.create_trimesh_shape(),"texture":ImageTexture.create_from_image(picture)}
	var key := "transport-fixture"
	cache.write(key,original)
	var path := directory.path_join(key+".res")
	var resource := ResourceLoader.load(path) as Cache.Data
	_check(resource.data.is_empty() and not resource.encoded_values.is_empty(), "Metadata writes store one binary representation without a duplicate native dictionary")
	var shared := cache.read(key)
	_check(Package.same_payload(shared,original), "The synchronous reader preserves geometry, collision, pixels and layout values")
	shared.roads[0].height=7.0
	var job := Load.new()
	var warmed := await job.bake(get_tree(),cache,key)
	_check(warmed.roads[0].height==7.0 and warmed.mesh==shared.mesh, "Async and synchronous readers reuse the same decoded resource when sharing is requested")
	var detached := await job.bake(get_tree(),cache,key,true)
	_check(detached.roads[0].height==2.5 and detached.mesh==shared.mesh, "A new background world decodes original values even when the live cached dictionary has renderer annotations")
	detached.roads[0].height=99.0
	_check(shared.roads[0].height==7.0, "Private background containers cannot mutate the active world")
	_check(job.resources.is_empty(), "Private loads release their encoded file buffers after decoding")
	_check(Package.persisted_data(path,key).roads[0].height==2.5, "Offline repackaging reads the persisted values, never live renderer annotations")
	_check(cache.writes==1 and cache.misses==0 and cache.bundled_hits==3, "All reader variants reuse a single installed bake without regeneration")
	DirAccess.remove_absolute(path); DirAccess.remove_absolute(directory)

func _test_bake_values_legacy_and_invalid_bundle_fallback() -> void:
	var directory := "user://bake-values-fallback-%d" % Time.get_ticks_usec()
	var bundled := directory.path_join("bundle")
	DirAccess.make_dir_recursive_absolute(bundled)
	var cache := Cache.new(); cache.enabled=true; cache.directory=directory; cache.bundled_directory=bundled
	var key := "scenery-fixture"
	var legacy := Cache.Data.new(); legacy.schema=Cache.SCHEMA; legacy.key=key
	legacy.data={"trees":{"a":[Vector2(2,3)]}}
	var path := directory.path_join(key+".res")
	ResourceSaver.save(legacy,path)
	var invalid := Cache.Data.new(); invalid.schema=Cache.SCHEMA; invalid.key=key
	invalid.encoded_values={"version":-1}
	var bad_path := bundled.path_join(key+".res")
	ResourceSaver.save(invalid,bad_path)
	_check(cache.read(key)==legacy.data and cache.bundled_hits==0, "An unsupported bundled encoding falls back to an existing native user cache")
	var job := Load.new()
	var loaded := await job.bake(get_tree(),cache,key,true)
	_check(loaded==legacy.data and cache.bundled_hits==0, "The background reader also accepts old native caches without rewriting them")
	loaded.trees.a.append(Vector2.ZERO)
	_check(legacy.data.trees.a.size()==1, "Private reads detach old-format containers too")
	job.cancelled=true
	_check((await job.bake(get_tree(),cache,key,true)).is_empty(), "Cancelled background loads cannot publish legacy or binary data")
	_check(cache.writes==0 and cache.misses==0, "Fallback reads neither regenerate nor rewrite existing user caches")
	DirAccess.remove_absolute(bad_path); DirAccess.remove_absolute(bundled)
	DirAccess.remove_absolute(path); DirAccess.remove_absolute(directory)
