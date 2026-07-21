extends Node
## Verifies the consent gate headlessly: an opted-out run spools nothing; an
## opted-in tutorial run gets a "-T" run id, a real per-install player id, and
## an envelope. Run:
##   TELEMETRY_DEBUG=1 <godot> --headless --path . res://tools/telemetry/consent_sim.tscn

const AppPaths := preload("res://scripts/app_paths.gd")


func _ready() -> void:
	await get_tree().process_frame
	var fails := 0
	var before := _outbox_count()

	# 1. Opted-out run: finalize spools nothing.
	TelemetryState.set_next_run_consent(false, false)
	TelemetryState._on_run_started()
	TelemetryState._finalize_run("quit_to_menu")
	fails += _check(_outbox_count() == before, "opt-out run spooled nothing")

	# 2. Opted-in tutorial run: "-T" id + envelope with a real player id.
	TelemetryState.set_next_run_consent(true, true)
	TelemetryState._on_run_started()
	var rid: String = TelemetryState._run_id
	fails += _check(rid.ends_with("-T"), "tutorial run id ends with -T (%s)" % rid)
	TelemetryState._finalize_run("quit_to_menu")
	fails += _check(_outbox_count() == before + 1, "opted-in run spooled an envelope")
	var dir := AppPaths.telemetry_outbox_dir()
	for fname in DirAccess.get_files_at(dir):
		if fname.begins_with(rid.substr(0, 12)):
			var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(fname)))
			fails += _check(str(d.get("run_id", "")).ends_with("-T"), "envelope run_id keeps -T")
			var pid := str(d.get("player_id", ""))
			fails += _check(pid.length() == 32, "player id is a 32-hex uuid (%s)" % pid)
			fails += _check(bool(d.get("end", {}).get("run_complete", true)) == false,
					"quit_to_menu is not run_complete")
			DirAccess.remove_absolute(dir.path_join(fname))  # test junk — never upload

	print("CONSENT SIM %s" % ("PASS" if fails == 0 else "FAIL (%d checks)" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func _check(ok: bool, what: String) -> int:
	print("  %s %s" % ["PASS" if ok else "FAIL", what])
	return 0 if ok else 1


func _outbox_count() -> int:
	var n := 0
	for f in DirAccess.get_files_at(AppPaths.telemetry_outbox_dir()):
		if f.ends_with(".json") and not f.begins_with("ck_"):
			n += 1
	return n
