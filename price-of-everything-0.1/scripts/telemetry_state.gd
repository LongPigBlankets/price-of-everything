extends Node
## Telemetry — phase A: anonymous run envelopes spooled to disk on every close
## path, uploaded from the outbox on the next boot. No per-turn metrics and no
## consent gate yet; both arrive in later phases (docs/telemetry-spec.md §9).
## Phase-A builds must not ship to players — consent lands first.
##
## Lifecycle: arms when a run starts (MatchState.state_reset, with the first
## resolved turn as a fallback for harness-style runs), finalizes ONCE per run
## on the first close path that fires — window X, quit() teardown, or a new run
## re-arming (= quit to menu). Close paths only touch disk; the network happens
## on the next boot's outbox retry, so quitting never blocks on a request.

const AppPaths := preload("res://scripts/app_paths.gd")

const ENDPOINT_URL := "https://script.google.com/macros/s/AKfycbx9fgcEBw5asUWCOxU_IgauBhCnXduRH2oOncHQbZi2Jg95mNK97G_ykSQqSDHu9e1A/exec"
const TOKEN := "d299f45324f48cce4b9257789dfc493e172d5ac657ba1641"
const SCHEMA_VERSION := 1

var enabled := false
var _armed := false
var _finalized := false
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
	_session_id = _uuid()
	MatchState.state_reset.connect(_on_run_started)
	TurnManager.turn_resolution_completed.connect(_on_turn_completed)
	print("[Telemetry] ready (phase A, session %s)" % _session_id.substr(0, 8))
	_retry_outbox()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_finalize_run("window_close")
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
	if enabled and not _armed:
		_on_run_started()


func _finalize_run(reason: String) -> void:
	if not enabled or not _armed or _finalized:
		return
	_finalized = true
	_spool(_build_envelope(reason))


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
			"run_complete": false,
			"turn": TurnManager.current_turn,
			"ended_at": now,
			"playtime_s": (Time.get_ticks_msec() - _run_started_msec) / 1000,
		},
		"turns": [],
	}


func _spool(envelope: Dictionary) -> void:
	var dir := AppPaths.telemetry_outbox_dir()
	var path := dir.path_join("%s_%d.json" % [_run_id.substr(0, 12), envelope["sent_at"]])
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("[Telemetry] cannot write outbox file: " + tmp)
		return
	f.store_string(JSON.stringify(envelope))
	f.close()
	DirAccess.rename_absolute(tmp, path)
	print("[Telemetry] spooled %s (%s, turn %d)"
			% [path.get_file(), envelope["end"]["reason"], envelope["end"]["turn"]])


func _retry_outbox() -> void:
	var dir := AppPaths.telemetry_outbox_dir()
	for fname in DirAccess.get_files_at(dir):
		if fname.ends_with(".json"):
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
