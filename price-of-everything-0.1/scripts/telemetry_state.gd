extends Node
## Telemetry — phases A+B+C: anonymous run envelopes with one row of economic
## data per turn (money, revenue, profit, loans, buildings, power, per-good
## production, victory tracks, playtime), uploaded at close time and
## crash-resilient via periodic checkpoints that carry the rows.
##
## Consent (docs/telemetry-spec.md §2): opt-out checkbox on the New Game and
## Tutorial screens, staged via set_next_run_consent() and fixed for the run's
## lifetime — it rides the save ("collect"), so a resumed opted-out run stays
## off. When off, nothing is captured, cached, or sent for that run. Tutorial
## runs carry a "-T" run-id suffix. player_id is an anonymous per-install uuid
## from PlayerProfile.
##
## Rows are a pure observer of Production.last_turn_summary and sim autoload
## state — no sim writes, no sim RNG, nothing in _process. The crash
## checkpoint doubles as the on-disk row cache: it is a complete envelope
## rewritten (deferred, atomically) every CHECKPOINT_EVERY turns, so a crash
## loses at most CHECKPOINT_EVERY turns of rows.
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

const ENDPOINT_URL := "https://script.google.com/macros/s/AKfycbw8dUX-A_dSKmI2GB4_2AbRXbGnOKTbP8mpEa17t6wBBAg4Y0LcCnS_xJNH3EeNRwdr/exec"
const TOKEN := "d299f45324f48cce4b9257789dfc493e172d5ac657ba1641"
const SCHEMA_VERSION := 3  # v3: + run.start, rescues, cheats_used, per-building arrays, cost breakdown
const QUIT_UPLOAD_WINDOW_MSEC := 6000  # Apps Script round trips run 1.5-4 s
const CHECKPOINT_EVERY := 10
const COMPLETE_REASONS: Array[String] = ["victory", "turn_cap", "bankruptcy"]
# Order of the per-row tier rollup. The goods CSV's goods_graph_tier column is
# read tolerantly: it only exists once the goods-graph branch lands, so until
# then rows omit "tiers" (per-good `produced` carries the full information).
const TIER_BANDS: Array[String] = ["raw", "processed", "intermediate", "finished", "apex"]
# Per-turn cost breakdown: summary key -> short label in the `costs` cell. Diagnosis only —
# every entry is a component of money_out, so the breakdown SUMS INTO money_out and must
# never be subtracted from profit on top of it (see _build_row's note).
const COST_LINES := {
	"goods_purchased_cost": "inputs",
	"transport_paid": "transport",
	"labour_paid": "labour",
	"maintenance_paid": "maintenance",
	"power_purchase_cost": "power",
	"warehousing_paid": "storage",
	"interest_paid": "interest",
	"advisor_paid": "advisors",
	"taxes_paid": "tax",
	"dividends_paid": "dividends",
	"profit_sharing_paid": "profit_share",
	"carbon_tax_paid": "carbon",
}
# Per-turn freight split, FIXED ORDER, summing to the `transport` line in COST_LINES.
# Added after a tutorial run had to have its freight decomposed by inference — the engine
# always knew the split, the sheet just never carried it. Imports/exports carry the WHOLE port
# charge by direction: splitting fee-from-ad-valorem left both reading zero once the flat fee
# was retired. See docs/early-game-onboarding-spec.md §4.2b.
const TRANSPORT_LINES: Array[String] = [
	"port_inbound", "port_outbound", "roads", "rail", "pipes", "reinf_pipes",
]

var enabled := false
var _armed := false
var _finalized := false
var _closing := false
var _session_id := ""
var _run_id := ""
var _run_started_unix := 0
var _run_started_msec := 0
var _playtime_carried_s := 0  # playtime from earlier sessions of a loaded run
var _session_ordinal := 1     # 1 = first sitting of the run, +1 per load
var _collect := true          # this run's consent (the opt-out checkbox at start)
var _next_collect := true     # staged by the New Game / Tutorial screens
var _next_tutorial := false   # staged: suffix the next run id with "-T"
var _rows: Array = []         # one Dictionary per completed turn, this session
var _uploading := {}  # path -> that file's delivery watermark while its request is in flight
# Highest turn the server has ACCEPTED for this run. Every envelope used to carry the whole
# run history, so a checkpoint upload followed by the final envelope wrote turn 1 to the sheet
# two or three times over (owner 2026-08-01) — visible there as nested prefixes: 1-10, 1-20,
# 1-27 for one run. Rows at or below the watermark are already in the sheet and are not resent.
var _delivered_through := 0
var _goods_indexed := false
var _tier_available := false
var _tier_index := {}         # good_id -> index into TIER_BANDS
var _good_names := {}         # good_id -> internal_name ("coal"), for readable rows
var _building_names := {}     # building_id -> internal_name ("mine"), for the roster
# Run-level facts captured DURING the run rather than read at envelope time. The envelope
# for a quit-to-menu run is built from inside MatchState.state_reset, by which point the
# match has already been torn down — anything read there is the reset default, which is
# how `ruleset` came to report "standard" for tutorial runs in the delivered sheet.
var _run_start_id := ""
var _run_cheats := false
var _run_rescues := 0
var _capture_max_usec := 0    # worst per-turn capture cost, for the perf gate


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


## Staged by the New Game / Tutorial screens just before a run starts; consumed
## by the next arm (loads then override consent from the save in import_state).
func set_next_run_consent(collect: bool, tutorial: bool) -> void:
	_next_collect = collect
	_next_tutorial = tutorial


func _on_run_started() -> void:
	if not enabled:
		return
	if _armed and not _finalized:
		_finalize_run("quit_to_menu")
	_armed = true
	_finalized = false
	_collect = _next_collect
	_run_id = _uuid() + ("-T" if _next_tutorial else "")
	_next_collect = true
	_next_tutorial = false
	_run_started_unix = int(Time.get_unix_time_from_system())
	_run_started_msec = Time.get_ticks_msec()
	_playtime_carried_s = 0
	_session_ordinal = 1
	_rows = []
	_delivered_through = 0
	_run_start_id = ""
	_run_cheats = false
	_run_rescues = 0
	_ensure_tier_index()
	_retry_outbox()


func _on_turn_completed() -> void:
	if not enabled:
		return
	if not _armed:
		_on_run_started()
	if _finalized or not _collect:
		return
	var t0 := Time.get_ticks_usec()
	var summary: Dictionary = Production.last_turn_summary
	if not summary.is_empty():
		_rows.append(_build_row(summary))
	_capture_max_usec = maxi(_capture_max_usec, int(Time.get_ticks_usec() - t0))
	var done_turn := TurnManager.current_turn - 1
	if done_turn > 0 and done_turn % CHECKPOINT_EVERY == 0:
		# Deferred: the (growing) checkpoint rewrite lands on the frame after
		# turn resolution, off the end-turn critical path.
		_write_checkpoint.call_deferred()


func _write_checkpoint() -> void:
	if not enabled or not _armed or _finalized:
		return
	_write_json(_checkpoint_path(), _build_envelope("crash"))


## One row per completed turn, lifted from the already-computed summary.
## Budget (spec §3.2): < 0.5 ms — dict reads + one pass over buildings
## (player_building_count) + one pass over summary.produced.
func _build_row(summary: Dictionary) -> Dictionary:
	var revenue := float(summary.get("goods_sales_revenue", 0.0)) \
			+ float(summary.get("power_sales_revenue", 0.0))
	# By summary emission, money_out ALREADY contains taxes/dividends/profit
	# sharing (_apply_tax_and_dividends adds them as it charges), so in − out IS
	# the retained post-tax net — the same number the game's turn readout shows.
	# Subtracting taxes_paid etc. again here double-counts them (SolvencyState's
	# _post_tax_profit backs them out of money_out first for the same reason).
	var profit := float(summary.get("money_in", 0.0)) - float(summary.get("money_out", 0.0))
	var produced := {}
	var tiers := [0, 0, 0, 0, 0]
	var summary_produced: Dictionary = summary.get("produced", {})
	for good_id in summary_produced:
		if good_id == "power":
			continue
		var qty := int(summary_produced[good_id])
		produced[_good_names.get(good_id, good_id)] = qty
		if _tier_available:
			tiers[_tier_index.get(good_id, 2)] += qty
	# Every line here is a component of money_out, so the breakdown explains `profit`
	# rather than adjusting it. Zero lines are dropped — the server densifies.
	var costs := {}
	for key in COST_LINES:
		var amount := float(summary.get(key, 0.0))
		if amount > 0.0:
			costs[COST_LINES[key]] = snappedf(amount, 0.01)
	var empire := _empire_snapshot()
	# Run-level facts, latched while the match is still alive (see _run_start_id).
	if _run_start_id == "":
		_run_start_id = str(MatchState.scenario_name)
	_run_cheats = _run_cheats or bool(MatchState.cheats_used)
	_run_rescues = maxi(_run_rescues, SolvencyState.tutorial_rescues())
	var row := {
		"turn": TurnManager.current_turn - 1,
		"money": snappedf(MatchState.money, 0.01),
		"revenue": snappedf(revenue, 0.01),
		"profit": snappedf(profit, 0.01),
		"loans": snappedf(LoanState.total_outstanding(), 0.01),
		"buildings": empire.count,
		"power_gen": int(summary.get("power_supply", 0)),
		"power_use": int(summary.get("power_demand", 0)),
		"victory": _victory_array(),
		"playtime_s": _playtime_s(),
		"session": _session_ordinal,
		"produced": produced,
		"costs": costs,
		"transport": _transport_split(summary),
		"buildings_list": empire.list,
		"building_states": empire.states,
	}
	if _tier_available:
		row["tiers"] = tiers
	return row


func _victory_array() -> Array:
	var arr := []
	for key in VictoryState.TRACK_ORDER:
		arr.append(int(round(float(VictoryState.track_best.get(key, 0.0)) * 1000.0)))
	return arr


func _playtime_s() -> int:
	return _playtime_carried_s + int((Time.get_ticks_msec() - _run_started_msec) / 1000)


## This turn's freight in TRANSPORT_LINES order, always seven values so the sheet column is
## positional and safe to chart. Any freight the engine could not attribute to a mode (an
## in-flight shipment restored from an old save carries no breakdown) lands in roads, which is
## where production.gd's tolerant reader puts it — the seven therefore sum to `transport`.
func _transport_split(summary: Dictionary) -> Array:
	var breakdown: Dictionary = summary.get("transport_breakdown", {})
	var out: Array = []
	for key in TRANSPORT_LINES:
		out.append(snappedf(float(breakdown.get(key, 0.0)), 0.01))
	return out


## One pass over the player's buildings for the count, the "mine(l2)" roster, and each
## building's index-aligned run state. Single loop with cached names: this runs every turn
## inside the <0.5 ms capture budget (measured 234 us at 562 buildings before the arrays).
func _empire_snapshot() -> Dictionary:
	_ensure_tier_index()   # guarded; keeps the roster readable even if a row precedes arming
	var names: Array = []
	var states: Array = []
	var ran: Dictionary = Production.last_turn_run
	var missing: Dictionary = Production.missing_by_building
	var blocked: Dictionary = Production.blocked_reason_by_building
	for b in MatchState.buildings.values():
		if not (b is Dictionary) or not MatchState.is_player_owned(b):
			continue
		var bid := str(b.get("building_id", ""))
		names.append("%s(l%d)" % [_building_names.get(bid, bid), int(b.get("level", 1))])
		states.append(_building_state(str(b.get("instance_id", "")), ran, missing, blocked))
	return {"count": names.size(), "list": names, "states": states}


## Why a building did or didn't run this turn. "running" plus the engine's own blocked
## codes, so the sheet can separate "starving" from "starving BECAUSE it ran out of cash".
func _building_state(iid: String, ran: Dictionary, missing: Dictionary, blocked: Dictionary) -> String:
	if bool(ran.get(iid, false)):
		return "running"
	var code := str((blocked.get(iid, {}) as Dictionary).get("code", ""))
	if code == "just_constructed":
		return "starting"
	if code != "":
		return code
	var missing_list: Array = missing.get(iid, [])
	if missing_list.is_empty():
		return "idle"
	for m in missing_list:
		if m is Dictionary and str((m as Dictionary).get("good_id", "")) == "power":
			return "no_power"
	return "missing_inputs"


func _ensure_tier_index() -> void:
	if _goods_indexed:
		return
	_goods_indexed = true
	for b in Catalog.all_buildings():
		var bid := str(b.get("id", ""))
		var bname := str(b.get("internal_name", "")).strip_edges()
		if bid != "" and bname != "":
			_building_names[bid] = bname
	for g in Catalog.all_goods():
		var gid := str(g.get("id", ""))
		var iname := str(g.get("internal_name", "")).strip_edges()
		if iname != "":
			_good_names[gid] = iname
		var band := str(g.get("goods_graph_tier", "")).strip_edges().to_lower()
		var idx := TIER_BANDS.find(band)
		if idx >= 0:
			_tier_index[gid] = idx
			_tier_available = true


## Save integration (additive "telemetry" key, tolerant reader).
func export_state() -> Dictionary:
	if not enabled or not _armed:
		return {}
	return {
		"run_id": _run_id,
		"started_at": _run_started_unix,
		"playtime_s": _playtime_s(),
		"session": _session_ordinal,
		"collect": _collect,
	}


## Runs AFTER state_reset has re-armed with a fresh identity; a saved run_id
## overrides it so the resumed run keeps its identity across sessions.
func import_state(d: Dictionary) -> void:
	if not enabled or str(d.get("run_id", "")) == "":
		return
	_run_id = str(d["run_id"])
	_run_started_unix = int(d.get("started_at", _run_started_unix))
	_playtime_carried_s = int(d.get("playtime_s", 0))
	_session_ordinal = int(d.get("session", 1)) + 1
	# Consent was fixed when the run started; a resumed opted-out run stays off.
	_collect = bool(d.get("collect", true))
	_run_started_msec = Time.get_ticks_msec()
	_rows = []
	_delivered_through = _load_watermark()


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
	if not _collect:
		print("[Telemetry] run %s ended (%s) — metrics off, nothing sent"
				% [_run_id.substr(0, 8), reason])
		return
	var envelope := _build_envelope(reason)
	var path := AppPaths.telemetry_outbox_dir().path_join(
			"%s_%d.json" % [_run_id.substr(0, 12), envelope["sent_at"]])
	_write_json(path, envelope)
	print("[Telemetry] spooled %s (%s, turn %d, %d rows)"
			% [path.get_file(), reason, envelope["end"]["turn"], _rows.size()])
	if OS.get_environment("TELEMETRY_DEBUG") == "1":
		print("[Telemetry] capture max %d us over %d rows" % [_capture_max_usec, _rows.size()])


func _build_envelope(reason: String) -> Dictionary:
	var now := int(Time.get_unix_time_from_system())
	return {
		"token": TOKEN,
		"schema": SCHEMA_VERSION,
		"player_id": PlayerProfile.get_telemetry_player_id(),
		"run_id": _run_id,
		"session_id": _session_id,
		"sent_at": now,
		"client": {
			"version": str(ProjectSettings.get_setting("application/config/version", "dev")),
			"os": OS.get_name(),
		},
		"run": {
			"started_at": _run_started_unix,
			"ruleset": str(MatchState.ruleset.get("name", "standard")),
			# Latched during the run, not read here: on a quit-to-menu finalize the match
			# has already been reset, which is exactly why `ruleset` above is unreliable
			# on that path (a tutorial run reports "standard").
			"start": _run_start_id,
			"cheats_used": _run_cheats or bool(MatchState.cheats_used),
		},
		"end": {
			"reason": reason,
			"run_complete": reason in COMPLETE_REASONS,
			"turn": TurnManager.current_turn,
			"ended_at": now,
			"playtime_s": _playtime_s(),
			"victory": _victory_array(),
			"rescues": maxi(_run_rescues, SolvencyState.tutorial_rescues()),
		},
		"turns": _undelivered_rows(),
	}


## Rows the server has not confirmed yet. A failed upload leaves its file in the outbox and the
## watermark unmoved, so nothing is dropped by filtering here — it is retried on the next boot.
func _undelivered_rows() -> Array:
	if _delivered_through <= 0:
		return _rows
	var out: Array = []
	for r in _rows:
		if int((r as Dictionary).get("turn", 0)) > _delivered_through:
			out.append(r)
	return out


## The watermark lives beside the outbox, NOT inside it — _retry_outbox uploads every .json it
## finds in the outbox, so a watermark file in there would be POSTed as if it were an envelope.
func _watermark_path() -> String:
	return AppPaths.telemetry_outbox_dir().get_base_dir().path_join("sent_%s.json" % _run_id.substr(0, 12))


func _load_watermark() -> int:
	var f := FileAccess.open(_watermark_path(), FileAccess.READ)
	if f == null:
		return 0
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return int((parsed as Dictionary).get("through", 0)) if parsed is Dictionary else 0


## Highest turn in `body`, or -1 when the envelope belongs to a different run (an older
## crashed run draining from the outbox must not move THIS run's watermark).
func _watermark_of(body: String) -> int:
	var parsed: Variant = JSON.parse_string(body)
	if not (parsed is Dictionary) or str((parsed as Dictionary).get("run_id", "")) != _run_id:
		return -1
	var top := 0
	for r in ((parsed as Dictionary).get("turns", []) as Array):
		top = maxi(top, int((r as Dictionary).get("turn", 0)))
	return top


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
	_uploading[path] = _watermark_of(body)
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
	var delivered := int(_uploading.get(path, -1))
	_uploading.erase(path)
	http.queue_free()
	# With max_redirects = 0 the 302 arrives as RESULT_REDIRECT_LIMIT_REACHED,
	# not RESULT_SUCCESS — the response code is the success signal.
	if code == 302 or (result == HTTPRequest.RESULT_SUCCESS and code == 200):
		DirAccess.remove_absolute(path)
		if delivered > _delivered_through:
			_delivered_through = delivered
			_write_json(_watermark_path(), {"run_id": _run_id, "through": _delivered_through})
		# The run is over and its last envelope landed — the watermark has nothing left to guard.
		if _finalized and delivered >= 0:
			DirAccess.remove_absolute(_watermark_path())
		print("[Telemetry] uploaded %s (http %d, delivered through turn %d)"
				% [path.get_file(), code, _delivered_through])
	else:
		print("[Telemetry] upload failed for %s (result %d, http %d) — kept for next boot"
				% [path.get_file(), result, code])


func _uuid() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()
