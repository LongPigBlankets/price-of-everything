extends SceneTree
## Run with --main-pack GAME.pck --script /absolute/path/to/this/file.gd.
## Load the release gate externally: developer tools are excluded from the PCK.
func _initialize() -> void:
	call_deferred("verify")

func verify() -> void:
	var gate = load(get_script().resource_path.get_base_dir().path_join("bake_package.gd"))
	var report: Dictionary = await gate.validate("res://assets/supply_chain_3d/bakes",root)
	var output := "/private/tmp/export-bake-validation.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--validation-output="):output=arg.trim_prefix("--validation-output=")
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("[EXPORTED BAKE VALIDATION] ",JSON.stringify(report))
	quit(0 if report.ok else 1)
