extends Node
## Representation-only migration: preserve layouts and terrain pixels, replace
## redundant surface geometry and layered road paint. Run against a staged copy.
const Cache=preload("res://scripts/supply_chain_3d/bake_cache.gd")
const Package=preload("res://tools/supply_chain_3d/bake_package.gd")
const Compact=preload("res://scripts/supply_chain_3d/surface_compact.gd")
const Roads=preload("res://scripts/supply_chain_3d/road_drawing.gd")
func _ready() -> void:
	var directory:="";var only:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--package-output="):directory=arg.trim_prefix("--package-output=")
		if arg.begins_with("--only-tile="):only=arg.trim_prefix("--only-tile=")
	assert(not directory.is_empty(),"Specify a staged --package-output directory")
	var report:Dictionary=await migrate(directory,self,only)
	print("[COMPACT BAKE] ",JSON.stringify(report))
	get_tree().quit()

static func migrate(directory: String, host: Node, only: String="") -> Dictionary:
	var path:=directory.path_join("manifest.json")
	var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	var writer:=Cache.new();writer.enabled=true;writer.directory=directory;writer.bundled_directory=directory;writer.defer_trim=true
	var selected:Dictionary=manifest.resources if only.is_empty() else {}
	if not only.is_empty():
		for key in manifest.tiles[only].values():selected[key]=true
	var total_before:=0;var total_after:=0;var changed:=0;var started:=Time.get_ticks_msec()
	for key in selected:
		if not (key.begins_with("tile-") or key.begins_with("base-tile-") or key.begins_with("continent-") or key.begins_with("road-")):continue
		var data:=Package.persisted_data(directory.path_join(key+".res"),key)
		assert(not data.is_empty())
		if data.get("compact_surface_version",0)==Compact.VERSION:
			manifest.resources[key]=Package.file_record(directory,key)
			continue
		var before:Dictionary=Package.file_record(directory,key)
		assert(before.sha256==manifest.resources[key].sha256,"Source changed before compaction")
		if data.get("compact_surface_version",0)==1:
			if not key.begins_with("road-"):
				data.mesh=Compact.without_slivers(data.mesh)
				if data.has("pick_shape") and data.mesh.get_surface_count()>0:data.pick_shape=data.mesh.create_trimesh_shape()
			if data.has("road_drawing"):data.road_drawing.mesh=Compact.without_slivers(data.road_drawing.mesh)
		elif key.begins_with("road-"):
			data.road_drawing=await Roads.bake(host,data.mesh,3.0)
			data.mesh=data.road_drawing.extras;data.road_drawing.erase("extras")
		else:
			data.mesh=Compact.build(data.mesh)
			if data.has("pick_shape") and data.mesh.get_surface_count()>0:data.pick_shape=data.mesh.create_trimesh_shape()
			for field in ["rim_mesh","lip_mesh"]:
				if data.has(field):data[field]=Compact.build(data[field],false)
			if data.has("roads_mesh"):
				data.road_drawing=await Roads.bake(host,data.roads_mesh,6.0,6144 if key.begins_with("continent-") else 4096)
				data.roads_mesh=data.road_drawing.extras;data.road_drawing.erase("extras")
		data.compact_surface_version=Compact.VERSION
		writer.write(key,data)
		var after:=Package.file_record(directory,key)
		assert(after.sha256!=before.sha256)
		manifest.resources[key]=after
		total_before+=int(before.bytes);total_after+=int(after.bytes);changed+=1
		if changed%20==0 or not only.is_empty():print("[COMPACT] ",changed," before=",total_before," after=",total_after," elapsed_ms=",Time.get_ticks_msec()-started)
		# Checkpoint through atomic rename; the stage may use hard links to originals.
		if changed%20==0:save_json(path,manifest)
		await host.get_tree().process_frame
	if only.is_empty():
		manifest.compact_surface_version=Compact.VERSION
		manifest.render_fingerprint=render_fingerprint()
	save_json(path,manifest)
	var textures := await preload("res://tools/supply_chain_3d/compact_terrain_textures.gd").migrate(directory,host,PackedStringArray([only]) if not only.is_empty() else PackedStringArray())
	return {"changed":changed,"before":total_before,"after":total_after,"elapsed_ms":Time.get_ticks_msec()-started,"terrain_textures":textures}

static func save_json(path: String, value: Dictionary) -> void:
	FileAccess.open(path+".tmp",FileAccess.WRITE).store_string(JSON.stringify(value,"\t")+"\n")
	assert(DirAccess.rename_absolute(path+".tmp",path)==OK)

static func render_fingerprint() -> String:
	var files:=[]
	for name in ["surface_compact.gd","road_drawing.gd","road_drawing.gdshader"]:
		files.append(FileAccess.get_sha256("res://scripts/supply_chain_3d/"+name))
	return Cache.digest([Compact.VERSION,Roads.VERSION,files])
