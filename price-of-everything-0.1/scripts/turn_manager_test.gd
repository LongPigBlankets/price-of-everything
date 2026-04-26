extends Node

# Test scene runner: verifies AC1-AC11 from the TurnManager spec.
# Auto-runs on scene load, prints PASS/FAIL per AC, then quits with
# exit code 0 (all pass) or 1 (any fail) so headless runs are scriptable.

var emitted: Array = []  # log of (signal_name, payload) tuples
var results: Array = []  # [{name, passed, detail}, ...]

func _ready() -> void:
	# Connect to every TurnManager signal so we can record the order they fire.
	TurnManager.turn_resolution_started.connect(func(): _log("turn_resolution_started"))
	TurnManager.turn_resolution_completed.connect(func(): _log("turn_resolution_completed"))
	TurnManager.phase_started.connect(func(p): _log("phase_started", p))
	TurnManager.phase_completed.connect(func(p): _log("phase_completed", p))
	TurnManager.turn_advanced.connect(func(t): _log("turn_advanced", t))
	TurnManager.game_ended_signal.connect(func(r): _log("game_ended_signal", r))

	await _run_all_tests()
	_print_summary()
	get_tree().quit(0 if _all_passed() else 1)

func _log(name: String, payload = null) -> void:
	emitted.append({"name": name, "payload": payload})

func _signal_str(entry: Dictionary) -> String:
	var n: String = entry.name
	var p = entry.payload
	if p == null:
		return n
	if n == "phase_started" or n == "phase_completed":
		return "%s:%s" % [n, _phase_token(p)]
	return "%s:%s" % [n, str(p)]

func _phase_token(phase: int) -> String:
	# Match the test-spec format: PROCESS, SEND, AI, NARRATIVE, RECEIVE, DECIDE
	match phase:
		TurnManager.Phase.DECIDE: return "DECIDE"
		TurnManager.Phase.PROCESS: return "PROCESS"
		TurnManager.Phase.SEND: return "SEND"
		TurnManager.Phase.AI: return "AI"
		TurnManager.Phase.NARRATIVE: return "NARRATIVE"
		TurnManager.Phase.RECEIVE: return "RECEIVE"
		_: return "UNKNOWN(%d)" % phase

func _emitted_strings() -> Array:
	var out := []
	for e in emitted:
		out.append(_signal_str(e))
	return out

func _record(name: String, passed: bool, detail: String = "") -> void:
	results.append({"name": name, "passed": passed, "detail": detail})
	if passed:
		print("PASS  %s" % name)
	else:
		print("FAIL  %s — %s" % [name, detail])

# --- TEST RUNNER ----------------------------------------------------------

func _run_all_tests() -> void:
	# AC1+AC2 must inspect the autoload's startup state, before we reset it.
	# auto_start_first_turn is true, so phase_started(DECIDE) fires after one frame.
	# Wait two frames to be safe, then check.
	await get_tree().process_frame
	await get_tree().process_frame
	_test_ac1_initial_state()
	_test_ac2_decide_emitted_on_startup()

	# Use a fast pause for most tests so the full suite finishes quickly.
	# AC7 explicitly switches to 0.5s to verify pause respect.
	TurnManager.phase_pause_duration = 0.05

	await _test_ac3_full_resolution_sequence()
	await _test_ac4_double_commit_rejected()
	await _test_ac5_turn_counter_increments()
	await _test_ac6_game_end_at_turn_300()
	await _test_ac7_phase_pause_respected()
	await _test_ac8_signal_payloads()
	_test_ac9_no_crashes_on_edge_inputs()
	await _test_ac10_phase_emission_counts()
	await _test_ac11_phase_order_deterministic()

# --- AC1 — Initial state correct ------------------------------------------

func _test_ac1_initial_state() -> void:
	var ok := (
		TurnManager.current_turn == 1
		and TurnManager.current_phase == TurnManager.Phase.DECIDE
		and TurnManager.is_resolving == false
		and TurnManager.game_ended == false
	)
	var detail := ""
	if not ok:
		detail = "turn=%d phase=%d is_resolving=%s game_ended=%s" % [
			TurnManager.current_turn, TurnManager.current_phase,
			str(TurnManager.is_resolving), str(TurnManager.game_ended)
		]
	_record("AC1 initial state", ok, detail)

# --- AC2 — DECIDE phase emits on startup ----------------------------------

func _test_ac2_decide_emitted_on_startup() -> void:
	var count := 0
	for e in emitted:
		if e.name == "phase_started" and e.payload == TurnManager.Phase.DECIDE:
			count += 1
	var ok := count == 1
	_record("AC2 DECIDE emits on startup", ok, "expected 1 phase_started(DECIDE), got %d" % count)

# --- AC3 — full resolution sequence ---------------------------------------

func _test_ac3_full_resolution_sequence() -> void:
	_reset()
	emitted.clear()

	var expected := [
		"turn_resolution_started",
		"phase_started:PROCESS",
		"phase_completed:PROCESS",
		"phase_started:SEND",
		"phase_completed:SEND",
		"phase_started:AI",
		"phase_completed:AI",
		"phase_started:NARRATIVE",
		"phase_completed:NARRATIVE",
		"phase_started:RECEIVE",
		"phase_completed:RECEIVE",
		"turn_advanced:2",
		"phase_started:DECIDE",
		"turn_resolution_completed",
	]

	TurnManager.commit_turn()
	await _await_resolution_complete(5.0)

	var actual := _emitted_strings()
	var ok := actual == expected
	var detail := ""
	if not ok:
		detail = "expected %s, got %s" % [str(expected), str(actual)]
	_record("AC3 full resolution sequence", ok, detail)

	# Post-resolution state per AC3 final clause.
	var post_ok := (
		TurnManager.current_turn == 2
		and TurnManager.current_phase == TurnManager.Phase.DECIDE
		and TurnManager.is_resolving == false
	)
	_record("AC3 post-resolution state", post_ok,
		"turn=%d phase=%d is_resolving=%s" % [
			TurnManager.current_turn, TurnManager.current_phase, str(TurnManager.is_resolving)
		])

# --- AC4 — double commit rejected -----------------------------------------

func _test_ac4_double_commit_rejected() -> void:
	_reset()
	emitted.clear()

	TurnManager.commit_turn()
	# Second call in the same frame, mid-resolution: must be a silent no-op.
	TurnManager.commit_turn()
	await _await_resolution_complete(5.0)
	# Allow any spurious extras to land.
	await get_tree().create_timer(0.1).timeout

	var started_count := 0
	for e in emitted:
		if e.name == "turn_resolution_started":
			started_count += 1

	var ok := started_count == 1 and TurnManager.current_turn == 2
	_record("AC4 double commit rejected", ok,
		"turn_resolution_started fired %d times, current_turn=%d" % [started_count, TurnManager.current_turn])

# --- AC5 — turn counter increments ----------------------------------------

func _test_ac5_turn_counter_increments() -> void:
	_reset()
	emitted.clear()

	for i in 5:
		TurnManager.commit_turn()
		await _await_resolution_complete(5.0)

	var ok := TurnManager.current_turn == 6
	_record("AC5 turn counter increments", ok, "expected 6, got %d" % TurnManager.current_turn)

# --- AC6 — game end at turn 300 -------------------------------------------

func _test_ac6_game_end_at_turn_300() -> void:
	# Player gets MAX_TURNS decision phases. Committing the final playable turn
	# (current_turn == MAX_TURNS) ticks the counter to MAX_TURNS + 1 and triggers
	# the soft end.
	_reset()
	emitted.clear()
	TurnManager.current_turn = TurnManager.MAX_TURNS

	TurnManager.commit_turn()
	await _await_resolution_complete(5.0)

	var cap_signals := 0
	for e in emitted:
		if e.name == "game_ended_signal" and e.payload == "turn_cap_reached":
			cap_signals += 1

	var ok := (
		TurnManager.current_turn == TurnManager.MAX_TURNS + 1
		and TurnManager.game_ended == true
		and cap_signals == 1
	)
	_record("AC6 game end at turn cap", ok,
		"turn=%d game_ended=%s cap_signals=%d" % [
			TurnManager.current_turn, str(TurnManager.game_ended), cap_signals
		])

	# Subsequent commits must be silent no-ops.
	emitted.clear()
	var turn_before := TurnManager.current_turn
	TurnManager.commit_turn()
	await get_tree().create_timer(0.2).timeout
	var ok2 := emitted.is_empty() and TurnManager.current_turn == turn_before
	_record("AC6 commits after game_end no-op", ok2,
		"emitted=%s turn=%d" % [str(_emitted_strings()), TurnManager.current_turn])

# --- AC7 — phase pause respected ------------------------------------------

func _test_ac7_phase_pause_respected() -> void:
	_reset()
	emitted.clear()
	TurnManager.phase_pause_duration = 0.5

	var t_started := {}  # phase -> time
	var conn := func(p):
		if not t_started.has(p):
			t_started[p] = Time.get_ticks_msec()
	TurnManager.phase_started.connect(conn)

	TurnManager.commit_turn()
	await _await_resolution_complete(10.0)
	TurnManager.phase_started.disconnect(conn)

	var phases := [
		TurnManager.Phase.PROCESS,
		TurnManager.Phase.SEND,
		TurnManager.Phase.AI,
		TurnManager.Phase.NARRATIVE,
		TurnManager.Phase.RECEIVE,
	]
	var all_ok := true
	var detail_parts: Array = []
	for i in range(phases.size() - 1):
		var a: int = t_started.get(phases[i], -1)
		var b: int = t_started.get(phases[i + 1], -1)
		if a < 0 or b < 0:
			all_ok = false
			detail_parts.append("missing time for %s or %s" % [_phase_token(phases[i]), _phase_token(phases[i + 1])])
			continue
		var dt: float = (b - a) / 1000.0
		if dt < 0.4 or dt > 0.7:
			all_ok = false
			detail_parts.append("%s->%s dt=%.3f" % [_phase_token(phases[i]), _phase_token(phases[i + 1]), dt])
	_record("AC7 phase pause respected", all_ok, ", ".join(detail_parts))

	# Restore fast pause for the remaining tests.
	TurnManager.phase_pause_duration = 0.05

# --- AC8 — signal payloads correct ----------------------------------------

func _test_ac8_signal_payloads() -> void:
	_reset()
	emitted.clear()

	TurnManager.commit_turn()
	await _await_resolution_complete(5.0)

	var ok := true
	var bad: Array = []
	for e in emitted:
		match e.name:
			"phase_started", "phase_completed":
				if not _is_valid_phase(e.payload):
					ok = false
					bad.append("%s payload=%s" % [e.name, str(e.payload)])
			"turn_advanced":
				if typeof(e.payload) != TYPE_INT:
					ok = false
					bad.append("turn_advanced payload type=%d" % typeof(e.payload))
	_record("AC8 signal payloads correct", ok, ", ".join(bad))

func _is_valid_phase(p) -> bool:
	if typeof(p) != TYPE_INT:
		return false
	return p >= 0 and p < TurnManager.Phase.size()

# --- AC9 — no crashes on edge inputs --------------------------------------

func _test_ac9_no_crashes_on_edge_inputs() -> void:
	_reset()
	TurnManager.game_ended = true
	TurnManager.commit_turn()  # must not crash

	var receive_name := TurnManager.get_phase_name(TurnManager.Phase.RECEIVE)
	var ok := receive_name == "Receive"
	_record("AC9 no crashes on edge inputs", ok, "get_phase_name(RECEIVE)=%s" % receive_name)
	TurnManager.game_ended = false

# --- AC10 — phase emission counts -----------------------------------------

func _test_ac10_phase_emission_counts() -> void:
	_reset()
	emitted.clear()

	TurnManager.commit_turn()
	await _await_resolution_complete(5.0)

	var started := 0
	var completed := 0
	for e in emitted:
		if e.name == "phase_started":
			started += 1
		elif e.name == "phase_completed":
			completed += 1
	var ok := started == 6 and completed == 5
	_record("AC10 phase emission counts", ok,
		"phase_started=%d (expected 6), phase_completed=%d (expected 5)" % [started, completed])

# --- AC11 — phase order deterministic over 10 cycles ----------------------

func _test_ac11_phase_order_deterministic() -> void:
	_reset()

	var expected_order := [
		"PROCESS", "SEND", "AI", "NARRATIVE", "RECEIVE", "DECIDE",
	]

	var all_ok := true
	var bad_cycle := -1
	var bad_actual: Array = []
	for cycle in 10:
		emitted.clear()
		TurnManager.commit_turn()
		await _await_resolution_complete(5.0)

		var order: Array = []
		for e in emitted:
			if e.name == "phase_started":
				order.append(_phase_token(e.payload))
		if order != expected_order:
			all_ok = false
			bad_cycle = cycle
			bad_actual = order
			break
	var detail := ""
	if not all_ok:
		detail = "cycle %d order=%s expected=%s" % [bad_cycle, str(bad_actual), str(expected_order)]
	_record("AC11 phase order deterministic", all_ok, detail)

# --- helpers --------------------------------------------------------------

func _reset() -> void:
	TurnManager.reset_for_test()

func _await_resolution_complete(timeout_sec: float) -> void:
	# Wait for the next turn_resolution_completed, with a hard timeout.
	var done := [false]
	var conn := func(): done[0] = true
	TurnManager.turn_resolution_completed.connect(conn, CONNECT_ONE_SHOT)

	var deadline_ms: float = Time.get_ticks_msec() + timeout_sec * 1000.0
	while not done[0]:
		if Time.get_ticks_msec() > deadline_ms:
			break
		await get_tree().process_frame
	if TurnManager.turn_resolution_completed.is_connected(conn):
		TurnManager.turn_resolution_completed.disconnect(conn)

func _all_passed() -> bool:
	for r in results:
		if not r.passed:
			return false
	return true

func _print_summary() -> void:
	var passed := 0
	var failed := 0
	for r in results:
		if r.passed:
			passed += 1
		else:
			failed += 1
	print("---------------------------------------------")
	print("TurnManager test summary: %d passed, %d failed (of %d)" % [passed, failed, results.size()])
	if failed > 0:
		print("Failures:")
		for r in results:
			if not r.passed:
				print("  - %s: %s" % [r.name, r.detail])
	print("---------------------------------------------")
