extends Node
## Convert canonical metadata in place, verify identical values, then remove only
## the explicitly indexed duplicate startup files. No landscape generation.
const Package := preload("res://tools/supply_chain_3d/bake_package.gd")

func _ready() -> void:
	get_tree().create_timer(180.0).timeout.connect(func(): get_tree().quit(2))
	await get_tree().process_frame
	var directory: String = Package.Cache.BUNDLED
	var manifest_path := directory.path_join("manifest.json")
	var original_manifest := FileAccess.get_file_as_string(manifest_path)
	var manifest: Dictionary = JSON.parse_string(original_manifest)
	var scratch := "/private/tmp/bake-values-migration-%d" % Time.get_ticks_usec()
	var previous := scratch.path_join("previous")
	DirAccess.make_dir_recursive_absolute(previous)
	FileAccess.open(previous.path_join("manifest.json"),FileAccess.WRITE).store_string(original_manifest)
	var writer := Package.Cache.new()
	writer.enabled=true; writer.defer_trim=true; writer.directory=scratch
	writer.compress=manifest.storage=="zstd"
	var converted: Array = []
	var duplicates: Array = manifest.get("startup_keys",[]).duplicate()
	var old_index := str(manifest.get("world_startup_key",""))
	if not old_index.is_empty() and not duplicates.has(old_index): duplicates.append(old_index)
	for key in duplicates:
		if not str(key).begins_with("startup-") and not str(key).begins_with("world-startup-"):
			_fail("Unexpected duplicate key: "+str(key)); return
	for key in manifest.resources:
		if not Package.Cache.binary_values_for(key): continue
		var source: String = directory.path_join(key+".res")
		var before := Package.file_record(directory,key)
		if before.sha256!=manifest.resources[key].sha256:
			_fail("Source bake changed: "+key); return
		var values := Package.persisted_data(source,key)
		if values.is_empty(): _fail("Cannot read source bake: "+key); return
		writer.write(key,values)
		var staged := scratch.path_join(key+".res")
		var reloaded := Package.persisted_data(staged,key)
		if not Package.same_payload(values,reloaded):
			_fail("Converted values differ: "+key); return
		if DirAccess.copy_absolute(source,previous.path_join(key+".res"))!=OK:
			_fail("Cannot preserve source bake: "+key); return
		converted.append({"key":key,"before_bytes":before.bytes,"after":Package.file_record(scratch,key),"payload_equal":true})
		print("[VALUE MIGRATION] verified ",key)
		await get_tree().process_frame
	# All replacements have passed round-trip checks before touching the package.
	for item in converted:
		if DirAccess.copy_absolute(scratch.path_join(item.key+".res"),directory.path_join(item.key+".res"))!=OK:
			_rollback(directory,previous,converted,original_manifest)
			_fail("Cannot install converted bake: "+item.key); return
		manifest.resources[item.key]=item.after
	for key in duplicates:
		manifest.resources.erase(key)
		manifest.auxiliary_keys.erase(key)
	manifest.erase("startup_keys"); manifest.erase("world_startup_key")
	manifest.binary_values_version=Package.Cache.Data.Values.VERSION
	FileAccess.open(manifest_path,FileAccess.WRITE).store_string(JSON.stringify(manifest,"\t")+"\n")
	var report := await Package.validate(directory,self)
	if not report.ok:
		_rollback(directory,previous,converted,original_manifest)
		_fail("Package validation failed: "+JSON.stringify(report)); return
	var removed_bytes := 0
	for key in duplicates:
		var path: String=directory.path_join(key+".res")
		if not FileAccess.file_exists(path): continue
		removed_bytes+=FileAccess.open(path,FileAccess.READ).get_length()
		if DirAccess.remove_absolute(path)!=OK: _fail("Cannot remove duplicate: "+key); return
	report.converted=converted; report.removed=duplicates; report.removed_bytes=removed_bytes
	var output := "res://../outputs/supply-chain-3d/unified-bake-values"
	DirAccess.make_dir_recursive_absolute(output)
	FileAccess.open(output.path_join("migration.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("[VALUE MIGRATION COMPLETE] ",JSON.stringify(report))
	get_tree().quit()

func _rollback(directory: String, previous: String, converted: Array, manifest: String) -> void:
	for item in converted:
		DirAccess.copy_absolute(previous.path_join(item.key+".res"),directory.path_join(item.key+".res"))
	FileAccess.open(directory.path_join("manifest.json"),FileAccess.WRITE).store_string(manifest)

func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
