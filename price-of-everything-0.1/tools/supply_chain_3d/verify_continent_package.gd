extends Node
## godot --headless --path . res://tools/supply_chain_3d/verify_continent_package.tscn -- --no-telemetry
func _ready() -> void:
	var package := preload("res://tools/supply_chain_3d/bake_package.gd")
	var directory: String = package.Cache.BUNDLED
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--package-output="): directory = arg.trim_prefix("--package-output=")
	await get_tree().process_frame
	var report := await package.validate(directory, self)
	print("[PACKAGE VALIDATION] ", JSON.stringify(report))
	get_tree().quit(0 if report.ok else 1)
