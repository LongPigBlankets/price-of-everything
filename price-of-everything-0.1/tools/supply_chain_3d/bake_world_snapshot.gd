extends "res://tools/supply_chain_3d/capture.gd"
## Refresh only prepared board metadata; retain every existing terrain/art bake.
const Package := preload("res://tools/supply_chain_3d/bake_package.gd")
const Snapshot := preload("res://scripts/supply_chain_3d/world_snapshot.gd")

func _continent_review(board: Control, _home: Dictionary) -> void:
	assert(not board.show_all_tiles)
	assert("--no-background-continent" in OS.get_cmdline_user_args())
	var inputs := Snapshot.inputs(board)
	var input_key := Package.Cache.digest(inputs)
	await board.set_all_tiles(true, false)
	board.set_process(false)
	while not board.detail_ready():
		RenderingServer.force_draw(false)
		await get_tree().process_frame
	var directory: String = board._builder.bake_cache.bundled_directory
	var path := directory.path_join("manifest.json")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var data := Snapshot.packed(board, input_key)
	assert(Snapshot.matches(data, input_key, manifest), "Snapshot must reference the existing validated art package")
	var key := "world-snapshot-" + Package.Cache.digest([Snapshot.VERSION, input_key, data.keys])
	var writer := Package.Cache.new()
	writer.enabled = true; writer.defer_trim = true; writer.directory = directory
	writer.write(key, data)
	var previous := str(manifest.get("world_snapshot_key", ""))
	var auxiliary: Array = manifest.get("auxiliary_keys", [])
	if previous != "" and previous != key:
		auxiliary.erase(previous); manifest.resources.erase(previous)
	if not auxiliary.has(key): auxiliary.append(key)
	manifest.world_snapshot_key = key
	manifest.resources[key] = Package.file_record(directory, key)
	manifest.auxiliary_keys = auxiliary
	preload("res://tools/supply_chain_3d/bake_startup_bundle.gd").install(directory,manifest)
	var report := await Package.validate(directory, self)
	report.world_snapshot_key = key
	report.snapshot_bytes = manifest.resources[key].bytes
	FileAccess.open("/private/tmp/world_snapshot_package.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("[WORLD SNAPSHOT PACKAGE] ", JSON.stringify(report))
	if not report.ok: get_tree().quit(1)
