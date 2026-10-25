extends "res://tests/test_base.gd"
const FEATURE := "telemetry_controls"
const Telemetry := preload("res://scripts/telemetry_state.gd")
const Notice := preload("res://scripts/telemetry_notice.gd")
const Settings := preload("res://scripts/settings_panel.gd")


func _test_telemetry_controls_finalize_and_cancel_pending_reports() -> void:
	var previous_base := AppPaths._base
	var previous_opt_out := PlayerProfile.telemetry_opt_out
	var directory := ProjectSettings.globalize_path("user://telemetry-finalize-" + str(Time.get_ticks_usec()))
	AppPaths._base = directory
	PlayerProfile.telemetry_opt_out = false
	var telemetry := Telemetry.new()
	telemetry.enabled = true
	telemetry._on_run_started()
	telemetry._rows = [{"turn": 1, "profit": 10.0, "revenue": 20.0, "power_gen": 100, "buildings": 2, "produced": {"coal": 20}, "costs": {"inputs": 10}}]
	telemetry._finalize_run("quit_to_menu")
	var files := DirAccess.get_files_at(AppPaths.telemetry_outbox_dir())
	_check(files.size() == 1, "telemetry controls: enabled run spools one final envelope without network")
	if files.size() == 1:
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(AppPaths.telemetry_outbox_dir().path_join(files[0])))
		_check(data.has("sent_at") and data.has("run_id") and data.turns[0].profit == 10, "telemetry controls: restricted envelope preserves protocol fields and metrics")
		_check(data.turns[0].costs.is_empty(), "telemetry controls: spooled envelope has the same restricted scope")
	telemetry._on_preference_changed(true)
	_check(telemetry._rows.is_empty() and DirAccess.get_files_at(AppPaths.telemetry_outbox_dir()).is_empty(), "telemetry controls: disabling clears captured rows and queued run data")
	telemetry.free()
	DirAccess.remove_absolute(directory.path_join("telemetry/outbox"))
	DirAccess.remove_absolute(directory.path_join("telemetry"))
	DirAccess.remove_absolute(directory)
	AppPaths._base = previous_base
	PlayerProfile.telemetry_opt_out = previous_opt_out


func _test_telemetry_controls_saved_runs_cannot_override_preference() -> void:
	var previous := PlayerProfile.telemetry_opt_out
	var telemetry := Telemetry.new()
	telemetry.enabled = true
	telemetry._armed = true
	PlayerProfile.telemetry_opt_out = true
	telemetry.import_state({"run_id": "old-opted-in-run", "collect": true, "events": [{"action": "search_used"}]})
	_check(not telemetry._collect and telemetry._events.is_empty(), "telemetry controls: opted-in save cannot re-enable reports")
	var launch := telemetry._launch_envelope()
	_check(launch.kind == "launch" and launch.player_id != "", "telemetry controls: basic launch event remains enabled")
	_check(not launch.has("turns") and not launch.has("events"), "telemetry controls: launch event contains no gameplay report")
	PlayerProfile.telemetry_opt_out = false
	telemetry.import_state({"run_id": "old-opted-out-run", "collect": false})
	_check(telemetry._collect, "telemetry controls: current Settings choice also wins over an old opt-out")
	telemetry.free()
	PlayerProfile.telemetry_opt_out = previous


func _test_telemetry_controls_critical_payload_and_queued_data() -> void:
	var data := {"run_id": "test", "events": [{"action": "search_used"}], "run": {"start": "metal_magnate", "tutorial_step": "private-history"}, "turns": [{"turn": 3, "profit": 20.0, "revenue": 100.0, "buildings": 4, "buildings_list": ["mine(l1)"], "power_gen": 600, "produced": {"coal": 20}, "satisfaction": -12.5, "money": 2000, "costs": {"inputs": 100}, "interactions": {"search_used": 1}}]}
	var clean := Telemetry.balancing_payload(data)
	_check(clean.turns[0].profit == 20 and clean.turns[0].revenue == 100 and clean.turns[0].power_gen == 600 and is_equal_approx(float(clean.turns[0].satisfaction), -12.5), "telemetry controls: balancing report retains the advertised metrics, satisfaction included")
	_check(clean.events.is_empty() and clean.turns[0].interactions.is_empty() and clean.turns[0].costs.is_empty(), "telemetry controls: report excludes interaction history and detailed costs")
	_check(not clean.run.has("tutorial_step") and clean.turns[0].money == "", "telemetry controls: older queued envelopes are reduced to the same scope")
	_check(data.events.size() == 1 and data.turns[0].money == 2000, "telemetry controls: payload filtering does not mutate its source")
	var directory := "user://telemetry-controls-" + str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(directory)
	for name in ["run.json", "ck_run.json.tmp", "launch.json", "feedback.json"]:
		var file := FileAccess.open(directory.path_join(name), FileAccess.WRITE)
		file.store_string(JSON.stringify({"kind": name.get_basename()} if name in ["launch.json", "feedback.json"] else data))
		file.close()
	var telemetry := Telemetry.new()
	telemetry._discard_run_reports(directory)
	_check(not FileAccess.file_exists(directory.path_join("run.json")) and not FileAccess.file_exists(directory.path_join("ck_run.json.tmp")), "telemetry controls: disabling removes queued gameplay reports and checkpoints")
	_check(FileAccess.file_exists(directory.path_join("launch.json")) and FileAccess.file_exists(directory.path_join("feedback.json")), "telemetry controls: preserves launch and explicitly submitted feedback")
	var previous := PlayerProfile.telemetry_opt_out
	PlayerProfile.telemetry_opt_out = true
	var path := directory.path_join("late-report.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	telemetry._upload_file(path)
	_check(not FileAccess.file_exists(path) and telemetry._uploading.is_empty(), "telemetry controls: retry cannot send an opted-out report")
	telemetry.free()
	PlayerProfile.telemetry_opt_out = previous
	for name in DirAccess.get_files_at(directory): DirAccess.remove_absolute(directory.path_join(name))
	DirAccess.remove_absolute(directory)


func _test_telemetry_controls_settings_staging_and_notice() -> void:
	var previous := PlayerProfile.telemetry_opt_out
	var seen := PlayerProfile.telemetry_notice_seen
	PlayerProfile.telemetry_opt_out = false
	var panel := Settings.new()
	add_child(panel)
	_check(panel._telemetry_option.item_count == 2 and panel._telemetry_option.get_item_text(0) == "Send critical data for balancing", "telemetry controls: Settings provides the requested two choices")
	panel._telemetry_option.select(1)
	_check(not PlayerProfile.telemetry_opt_out, "telemetry controls: selecting a staged option does not apply it yet")
	panel._on_back_pressed()
	_check(not PlayerProfile.telemetry_opt_out, "telemetry controls: Back discards a staged telemetry change")
	await get_tree().process_frame
	panel = Settings.new()
	add_child(panel)
	panel._telemetry_option.select(1)
	panel._apply_telemetry_preference()
	_check(PlayerProfile.telemetry_opt_out, "telemetry controls: Apply changes the player preference")
	_check(panel.find_child("TelemetryUserID", true, false).text == PlayerProfile.get_telemetry_player_id(), "telemetry controls: Settings displays the report's user ID")
	panel.queue_free()
	PlayerProfile.telemetry_notice_seen = false
	_check(Notice.should_show(), "telemetry controls: first menu needs the notice")
	var notice := Notice.new()
	add_child(notice)
	_check(notice.understood_button.get_script() == preload("res://scripts/ds2/cream_key.gd"), "telemetry controls: Understood uses the DS2 cream key")
	notice.understood_button.pressed.emit()
	_check(PlayerProfile.telemetry_notice_seen and not Notice.should_show(), "telemetry controls: Understood suppresses future menu notices")
	PlayerProfile.set_telemetry_opt_out(previous)
	PlayerProfile.telemetry_notice_seen = seen
	await get_tree().process_frame
