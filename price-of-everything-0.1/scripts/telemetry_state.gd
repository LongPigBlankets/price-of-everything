extends Node
## Telemetry — phase A: anonymous run envelopes, uploaded at close time and
## crash-resilient via periodic checkpoints. No per-turn metrics and no consent
## gate yet; both arrive in later phases (docs/telemetry-spec.md §9).
## Phase-A builds must not ship to players — consent lands first.
##
## Lifecycle: arms when a run starts (MatchState.state_reset, with the first
## resolved turn as a fallback for harness-style runs) and finalizes ONCE per
## run. Delivery, by exit path:
##  - Game end (victory / turn_cap / bankruptcy signals): finalize with the
##    real reason, run_complete true, upload immediately (end screen is up).
##  - Window X / request_app_quit() (main-menu Quit, pause-menu Exit to
##    Desktop): we own the close handshake (auto_accept_quit false) — spool to
##    disk FIRST, hide the window, upload with a bounded wait
##    (QUIT_UPLOAD_WINDOW_MSEC) and quit regardless; the outbox catches
##    timeouts.
##  - Raw quit() teardown (any path not routed through request_app_quit):
##    disk only via EXIT_TREE, uploads next boot.
##  - Crash / force-kill: a checkpoint envelope (reason "crash") is rewritten
##    every CHECKPOINT_EVERY turns; a clean close deletes it, so one surviving
##    on boot means the process died — it uploads with the retry.
##  - New run re-arming while armed = quit to menu: spool + upload (app alive).

const AppPaths := preload("res://scripts/app_paths.gd")

const ENDPOINT_URL := "https://script.google.com/macros/s/AKfycbx9fgcEBw5asUWCOxU_IgauBhCnXduRH2oOncHQbZi2Jg95mNK97G_ykSQqSDHu9e1A/exec"
const TOKEN := "d299f45324f48cce4b9257789dfc493e172d5ac657ba1641"
const SCHEMA_VERSION := 1
const QUIT_UPLOAD_WINDOW_MSEC := 6000  # Apps Script round trips run 1.5-4 s
const CHECKPOINT_EVERY := 10
const COMPLETE_REASONS: Array[String] = ["victory", "turn_cap", "bankruptcy"]

var enabled := false
var _armed := false
var _finalized := false
var _closing := false
var _session_id := ""
var _run_id := ""
var _run_started_unix := 0
var _run_started_msec := 0
var _uploading := {}  # path -> true while a request for that outbox file is in flight


func _ready() -> void:
	# Headless (unit suite / e2e harness) is inert unless TELEMETRY_DEBUG=1
	# forces it on — that override is how the phase-A verification runs work.
	enabled = DisplayServer.get_name() != "headless" \
			or OS.get_environment("TELEMETRY_DEBUG") == "1"
	if not enabled:
		return
	# We own the window-close handshake: _handle_window_close() must call
	# get_tree().quit() on every path or the app can no longer be closed.
	get_tree().set_auto_accept_quit(false)
	_session_id = _uuid()
	MatchState.state_reset.connect(_on_run_started)
	TurnManager.turn_resolution_completed.connect(_on_turn_completed)
	VictoryState.victory_achieved.connect(_on_victory)
	TurnManager.game_ended_signal.connect(_on_game_ended)
	SolvencyState.bankruptcy_declared.connect(_on_bankruptcy)
	print("[Telemetry] ready (phase A, session %s)" % _session_id.substr(0, 8))
	_retry_outbox()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_handle_window_close()
	elif what == NOTIFICATION_EXIT_TREE:
		# quit() skips WM_CLOSE but tears the tree down; _finalized keeps the
		# window-X path (which fires both) from spooling twice.
		_finalize_run("quit_to_desktop")


func _on_run_started() -> void:
	if not enabled:
		return
	if _armed and not _finalized:
		_finalize_run("quit_to_menu")
	_armed = true
	_finalized = false
	_run_id = _uuid()
	_run_started_unix = int(Time.get_unix_time_from_system())
	_run_started_msec = Time.get_ticks_msec()
	_retry_outbox()


func _on_turn_completed() -> void:
	if not enabled:
		return
	if not _armed:
		_on_run_started()
	var done_turn := TurnManager.current_turn - 1
	if done_turn > 0 and done_turn % CHECKPOINT_EVERY == 0:
		_write_json(_checkpoint_path(), _build_envelope("crash"))


## The run ended on-screen (victory / turn cap / bankruptcy): finalize with the
## real reason and upload immediately — the app stays alive on the end screen.
func _on_victory(_total: int, _turn: int) -> void:
	_finalize_run("victory")
	_retry_outbox()


func _on_game_ended(reason: String) -> void:
	_finalize_run("turn_cap" if reason == "turn_cap_reached" else reason)
	_retry_outbox()


func _on_bankruptcy() -> void:
	_finalize_run("bankruptcy")
	_retry_outbox()


## App-wide quit entry point (main-menu Quit, pause-menu Exit to Desktop):
## same spool → hide window → bounded upload drain → quit as the window X.
## Safe to call whether or not telemetry is enabled.
func request_app_quit() -> void:
	_handle_window_close("quit_to_desktop")


func _handle_window_close(reason: String = "window_close") -> void:
	if _closing:
		return
	_closing = true
	# Disk before network: even if the upload stalls, the envelope is spooled.
	_finalize_run(reason)
	if not enabled:
		get_tree().quit()
		return
	# Hide the window so the close feels instant while uploads drain unseen.
	if DisplayServer.get_name() != "headless":
		get_window().hide()
	_retry_outbox()
	_quit_when_drained()


func _quit_when_drained() -> void:
	var deadline := Time.get_ticks_msec() + QUIT_UPLOAD_WINDOW_MSEC
	while Time.get_ticks_msec() < deadline and not _uploading.is_empty():
		await get_tree().process_frame
	get_tree().quit()


func _finalize_run(reason: String) -> void:
	if not enabled or not _armed or _finalized:
		return
	_finalized = true
	# The clean envelope supersedes the crash checkpoint.
	DirAccess.remove_absolute(_checkpoint_path())
	var envelope := _build_envelope(reason)
	var path := AppPaths.telemetry_outbox_dir().path_join(
			"%s_%d.json" % [_run_id.substr(0, 12), envelope["sent_at"]])
	_write_json(path, envelope)
	print("[Telemetry] spooled %s (%s, turn %d)"
			% [path.get_file(), reason, envelope["end"]["turn"]])


func _build_envelope(reason: String) -> Dictionary:
	var now := int(Time.get_unix_time_from_system())
	return {
		"token": TOKEN,
		"schema": SCHEMA_VERSION,
		"player_id": "phase-a",  # per-install id arrives with the consent phase
		"run_id": _run_id,
		"session_id": _session_id,
		"sent_at": now,
		"client": {
			"version": str(ProjectSettings.get_setting("application/config/version", "dev")),
			"os": OS.get_name(),
		},
		"run": {"started_at": _run_started_unix},
		"end": {
			"reason": reason,
			"run_complete": reason in COMPLETE_REASONS,
			"turn": TurnManager.current_turn,
			"ended_at": now,
			"playtime_s": (Time.get_ticks_msec() - _run_started_msec) / 1000,
		},
		"turns": [],
	}


func _checkpoint_path() -> String:
	return AppPaths.telemetry_outbox_dir().path_join("ck_%s.json" % _run_id.substr(0, 12))


func _write_json(path: String, data: Dictionary) -> void:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("[Telemetry] cannot write: " + tmp)
		return
	f.store_string(JSON.stringify(data))
	f.close()
	DirAccess.rename_absolute(tmp, path)


func _retry_outbox() -> void:
	var dir := AppPaths.telemetry_outbox_dir()
	var live_checkpoint := "ck_%s.json" % _run_id.substr(0, 12) if _armed and not _finalized else ""
	for fname in DirAccess.get_files_at(dir):
		if fname.ends_with(".json") and fname != live_checkpoint:
			_upload_file(dir.path_join(fname))


func _upload_file(path: String) -> void:
	if _uploading.has(path):
		return
	var body := FileAccess.get_file_as_string(path)
	if body == "":
		return
	_uploading[path] = true
	var http := HTTPRequest.new()
	http.use_threads = true
	http.timeout = 15.0
	http.max_redirects = 0  # Apps Script answers 302; the redirect IS success
	add_child(http)
	http.request_completed.connect(_on_upload_done.bind(http, path))
	var err := http.request(ENDPOINT_URL, ["Content-Type: application/json"],
			HTTPClient.METHOD_POST, body)
	if err != OK:
		_uploading.erase(path)
		http.queue_free()


func _on_upload_done(result: int, code: int, _headers: PackedStringArray,
		_body: PackedByteArray, http: HTTPRequest, path: String) -> void:
	_uploading.erase(path)
	http.queue_free()
	# With max_redirects = 0 the 302 arrives as RESULT_REDIRECT_LIMIT_REACHED,
	# not RESULT_SUCCESS — the response code is the success signal.
	if code == 302 or (result == HTTPRequest.RESULT_SUCCESS and code == 200):
		DirAccess.remove_absolute(path)
		print("[Telemetry] uploaded %s (http %d)" % [path.get_file(), code])
	else:
		print("[Telemetry] upload failed for %s (result %d, http %d) — kept for next boot"
				% [path.get_file(), result, code])


func _uuid() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()
