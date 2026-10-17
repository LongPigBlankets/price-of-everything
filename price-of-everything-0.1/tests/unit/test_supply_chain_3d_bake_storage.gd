extends "res://tests/test_base.gd"
const FEATURE := "supply_chain_3d"
const Storage := preload("res://tools/supply_chain_3d/repack_bake_storage.gd")
const Data := preload("res://scripts/supply_chain_3d/bake_data.gd")

func _test_bake_storage_boundaries_and_corruption() -> void:
	for size in [1,4095,4096,4097,262144,262145,1048576]:
		var raw := PackedByteArray();raw.resize(size)
		for i in size: raw[i]=(i*37+i/1024)%256
		for block in [4096,262144,1048576]:
			var packed := Storage.encode(raw,block)
			_check(Storage.decode(packed)==raw,"Lossless storage at size %d / block %d" % [size,block])
	var packed := Storage.encode("resource payload".to_utf8_buffer(),4096)
	_check(Storage.decode(packed.slice(0,18)).is_empty(),"Reject truncated block table")
	packed.encode_u32(16,0xffffffff)
	_check(Storage.decode(packed).is_empty(),"Reject block size past end of file")
	packed=Storage.encode("resource payload".to_utf8_buffer(),4096);packed.encode_u32(8,0)
	_check(Storage.decode(packed).is_empty(),"Reject zero block length")

func _test_bake_storage_native_resource_and_threaded_load() -> void:
	var resource := Data.new();resource.key="fixture";resource.schema=2
	var mesh := BoxMesh.new();mesh.size=Vector3(30,50,80)
	resource.data={"mesh":mesh,"pick_shape":mesh.create_trimesh_shape(),"positions":PackedVector3Array([Vector3(1,2,3)])}
	var path := "/private/tmp/bake-storage-%d.res" % Time.get_ticks_usec()
	_check(ResourceSaver.save(resource,path,ResourceSaver.FLAG_COMPRESS)==OK,"Save native source")
	var raw := Storage.decode(FileAccess.get_file_as_bytes(path))
	var rewritten := Storage.encode(raw,1048576)
	var file := FileAccess.open(path,FileAccess.WRITE);file.store_buffer(rewritten);file.close()
	var loaded := ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP) as Data
	_check(loaded!=null and loaded.data.mesh.size==mesh.size and loaded.data.positions==resource.data.positions,"Native reader retains values and mesh")
	_check(loaded.data.pick_shape.get_faces()==resource.data.pick_shape.get_faces(),"Native reader retains exact collision triangles")
	_check(ResourceLoader.load_threaded_request(path,"",false,ResourceLoader.CACHE_MODE_IGNORE_DEEP)==OK,"Threaded native loading accepts repacked resource")
	while ResourceLoader.load_threaded_get_status(path)==ResourceLoader.THREAD_LOAD_IN_PROGRESS: await get_tree().process_frame
	var threaded := ResourceLoader.load_threaded_get(path) as Data
	_check(threaded!=null and threaded.data.mesh.size==mesh.size,"Threaded reader retains mesh")
	DirAccess.remove_absolute(path)

func _test_bake_storage_manifest_idempotence_and_source_guard() -> void:
	var directory := "/private/tmp/bake-storage-package-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(directory)
	var path := directory.path_join("fixture.res")
	var resource := Data.new();resource.key="fixture"
	var bytes := PackedByteArray();bytes.resize(300000);bytes.fill(27)
	resource.data={"bytes":bytes}
	ResourceSaver.save(resource,path,ResourceSaver.FLAG_COMPRESS)
	var manifest := {"storage":"zstd","resources":{"fixture":{"bytes":FileAccess.get_file_as_bytes(path).size(),"sha256":FileAccess.get_sha256(path)}}}
	var manifest_path := directory.path_join("manifest.json")
	Storage.save_json(manifest_path,manifest)
	var first := await Storage.migrate(directory,self)
	_check(first.ok and first.changed==1 and first.verified_payloads==1,"Migration verifies payload and updates manifest")
	var second := await Storage.migrate(directory,self)
	_check(second.ok and second.changed==0 and second.verified_payloads==0,"Unchanged package skips recompression")
	var installed: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	_check(installed.resources.fixture.sha256==FileAccess.get_sha256(path),"Manifest checksum matches installed bytes")
	var damaged := FileAccess.get_file_as_bytes(path);damaged[0]=0
	var file := FileAccess.open(path,FileAccess.WRITE);file.store_buffer(damaged);file.close()
	var refused := await Storage.migrate(directory,self)
	_check(not refused.ok and refused.changed==0 and FileAccess.get_file_as_bytes(path)==damaged,"Reject changed input without overwriting it")
	manifest.storage="raw";Storage.save_json(manifest_path,manifest)
	var raw := await Storage.migrate(directory,self)
	_check(raw.ok and raw.has("skipped"),"Keep deliberately raw profiling packages unchanged")
	for name in DirAccess.get_files_at(directory): DirAccess.remove_absolute(directory.path_join(name))
	DirAccess.remove_absolute(directory)
