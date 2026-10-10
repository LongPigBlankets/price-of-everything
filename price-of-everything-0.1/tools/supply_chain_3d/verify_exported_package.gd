extends SceneTree
## Run from an empty working directory to prevent loose-project fallback:
## godot --headless --main-pack /tmp/game.pck --script /absolute/path/to/this.gd -- --no-telemetry --validator=/absolute/path/to/bake_package.gd
func _initialize() -> void:
	call_deferred("_verify")

func _verify() -> void:
	var validator := ""
	var report_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--validator="): validator = arg.trim_prefix("--validator=")
		if arg.begins_with("--report="): report_path = arg.trim_prefix("--report=")
	if validator.is_empty(): push_error("Pass an external --validator path"); quit(1); return
	var gate: Script = load(validator)
	var cache: Script = load("res://scripts/supply_chain_3d/bake_cache.gd")
	var report: Dictionary = await gate.validate(cache.BUNDLED, root)
	report.compiled_scripts_only = not FileAccess.file_exists("res://scripts/supply_chain_3d/terrain_paint.gd")
	report.export_fingerprints = cache.source_fingerprints()
	report.ok = report.ok and report.compiled_scripts_only
	if not report_path.is_empty(): FileAccess.open(report_path, FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("[EXPORTED PACKAGE] ", JSON.stringify(report))
	quit(0 if report.ok else 1)
