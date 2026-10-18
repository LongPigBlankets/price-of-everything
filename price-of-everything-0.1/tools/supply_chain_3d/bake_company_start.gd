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
	# An unchanged owned-tile resource can be a bundled hit after the continent
	# manifest was replaced. Index those hits too, not only this run's writes.
	var required:Array=[board._builder._scenery_key,board._builder.transport_key]
	for tid in board._builder.tiles:
		for tier in 3: required.append(board._builder.tile_bake_key(tid,tier))
		required.append(board._builder.road_mesh_key(tid))
	for key in required:
		assert(FileAccess.file_exists(writer.directory.path_join(key+".res")),"Missing company resource: "+key)
		if not manifest.resources.has(key): auxiliary.append(key)
		manifest.resources[key]=Package.file_record(writer.directory,key)
	# The shared layout resource contains BOTH coverage variants. Explicitly use
	# the finished memo, not a ResourceLoader reference from before this run.
	var layout_key: String=board._layout_queries.key
	writer.write(layout_key,board._layout_queries.data)
	manifest.resources[layout_key]=Package.file_record(writer.directory,layout_key)
	# Every road chain of the default company, so its first session never solves one while
	# the player looks at the view (road_alignment_memo.gd).
	var builder: RefCounted=board._builder
	while not builder.seed_alignment_step(1 << 30): pass
	var alignment_key: String=builder.alignment_memo_key()
	writer.write(alignment_key,{"chains":builder.AlignmentMemo.entries()})
	if not manifest.resources.has(alignment_key): auxiliary.append(alignment_key)
	manifest.resources[alignment_key]=Package.file_record(writer.directory,alignment_key)
	manifest.auxiliary_keys=auxiliary
	manifest.company_start={"tiles":board._model.tiles.keys(),"resource_count":auxiliary.size()}
	FileAccess.open(manifest_path,FileAccess.WRITE).store_string(JSON.stringify(manifest,"\t")+"\n")
	await preload("res://tools/supply_chain_3d/compact_render_bakes.gd").migrate(writer.directory,self)
	var report := await Package.validate(writer.directory,self)
	report.company_start=manifest.company_start
	# The layout memo this run writes back can move roads on the next build. A
	# run that baked nothing new is the settled one; until then, run it again.
	var baked := Array(DirAccess.get_files_at(cache_directory) if DirAccess.dir_exists_absolute(cache_directory) else PackedStringArray()).filter(func(f: String) -> bool: return f.ends_with(".res") and not f.begins_with("layout-") and not f.begins_with("alignment-"))
	report.settled=baked.is_empty()
	FileAccess.open("/private/tmp/company_package_report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("[COMPANY PACKAGE] ",JSON.stringify(report))
	if not report.ok:get_tree().quit(1)
