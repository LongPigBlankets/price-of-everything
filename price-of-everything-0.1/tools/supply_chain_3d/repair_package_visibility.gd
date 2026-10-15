extends Node
## Repair only visibility metadata from the package's exact three terrain LODs.
const Package := preload("res://tools/supply_chain_3d/bake_package.gd")
func _ready() -> void:
	var directory := Package.Cache.BUNDLED
	var before := await Package.validate(directory,self)
	for error in before.errors:
		if not str(error).begins_with("Terrain outside visibility bounds:"):
			push_error("Refusing unrelated package repair: "+str(error));get_tree().quit(1);return
	var path := directory.path_join("manifest.json")
	var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	var root := Package.persisted_data(directory.path_join(manifest.continent_key+".res"),manifest.continent_key)
	var changed: Array=[]
	for tid in manifest.tiles:
		var initial: PackedVector3Array=root.metadata.visibility.hulls[tid]
		var hull := initial
		for name in ["base","medium","near"]:
			var key: String=manifest.tiles[tid][name]
			var data := Package.persisted_data(directory.path_join(key+".res"),key)
			hull=Package.enclose_terrain(hull,data)
		if hull!=initial:changed.append(tid);root.metadata.visibility.hulls[tid]=hull
	var writer := Package.Cache.new();writer.enabled=true;writer.directory=directory;writer.defer_trim=true
	if not changed.is_empty():
		writer.write(manifest.continent_key,root)
		manifest.resources[manifest.continent_key]=Package.file_record(directory,manifest.continent_key)
		FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(manifest,"\t")+"\n")
	# Validation must reload the rewritten root rather than retain its old hull.
	ResourceLoader.load(directory.path_join(manifest.continent_key+".res"),"",ResourceLoader.CACHE_MODE_REPLACE)
	var report := await Package.validate(directory,self)
	report.repaired_visibility_tiles=changed
	if report.ok and "--prune" in OS.get_cmdline_user_args():
		for file in DirAccess.get_files_at(directory):
			if file.ends_with(".res") and not manifest.resources.has(file.get_basename()):DirAccess.remove_absolute(directory.path_join(file))
	FileAccess.open("/private/tmp/continent_visibility_repair.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("[VISIBILITY REPAIR] ",JSON.stringify(report))
	get_tree().quit(0 if report.ok else 1)
