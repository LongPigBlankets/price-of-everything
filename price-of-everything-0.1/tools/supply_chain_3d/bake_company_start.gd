extends "res://tools/supply_chain_3d/capture.gd"
## Supplement a validated continent package with the default owned-tiles start.
## Use a new empty --bake-cache-directory; only that run's writes are installed.
const Package := preload("res://tools/supply_chain_3d/bake_package.gd")
var cache_directory := ""

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bake-cache-directory="):cache_directory=arg.trim_prefix("--bake-cache-directory=")
	if cache_directory.is_empty() or DirAccess.dir_exists_absolute(cache_directory):
		push_error("Company package needs a new, empty --bake-cache-directory")
		get_tree().quit(1);return
	var validation := await Package.validate(Package.Cache.BUNDLED,self)
	if not validation.ok:
		push_error("Install and validate the current continent package first")
		get_tree().quit(1);return
	PlayerProfile.supply_chain_all_tiles=false
	await super._ready()

func _continent_review(board: Control, _home: Dictionary) -> void:
	assert(not board.show_all_tiles)
	board.set_process(false)
	var writer := Package.Cache.new();writer.enabled=true;writer.defer_trim=true
	writer.directory=Package.Cache.BUNDLED
	var manifest_path := writer.directory.path_join("manifest.json")
	var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	var auxiliary: Array=manifest.get("auxiliary_keys",[])
	for file in (DirAccess.get_files_at(cache_directory) if DirAccess.dir_exists_absolute(cache_directory) else PackedStringArray()):
		if not file.ends_with(".res"):continue
		var key := file.get_basename()
		var data := Package.persisted_data(cache_directory.path_join(file),key)
		assert(not data.is_empty(),"Invalid company resource: "+key)
		writer.write(key,data)
		if not manifest.resources.has(key): auxiliary.append(key)
		manifest.resources[key]=Package.file_record(writer.directory,key)
	# The shared layout resource contains BOTH coverage variants. Explicitly use
	# the finished memo, not a ResourceLoader reference from before this run.
	var layout_key: String=board._layout_queries.key
	writer.write(layout_key,board._layout_queries.data)
	manifest.resources[layout_key]=Package.file_record(writer.directory,layout_key)
	manifest.auxiliary_keys=auxiliary
	manifest.company_start={"tiles":board._model.tiles.keys(),"resource_count":auxiliary.size()}
	FileAccess.open(manifest_path,FileAccess.WRITE).store_string(JSON.stringify(manifest,"\t")+"\n")
	await preload("res://tools/supply_chain_3d/compact_render_bakes.gd").migrate(writer.directory,self)
	var report := await Package.validate(writer.directory,self)
	report.company_start=manifest.company_start
	FileAccess.open("/private/tmp/company_package_report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("[COMPANY PACKAGE] ",JSON.stringify(report))
	if not report.ok:get_tree().quit(1)
