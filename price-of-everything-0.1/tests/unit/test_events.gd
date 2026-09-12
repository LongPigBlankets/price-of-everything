extends "res://tests/test_base.gd"
## Event scheduler, notifications and the turn briefing.

const FEATURE := "events"
## Tests that also belong to other features (run under any of their tags).
const TAGS := {
	"_test_modifiers_event_payload": ["events", "research"],
	"_test_briefing_items_and_dismissal": ["decisions", "events", "finance", "production"],
}

# Drive a synthetic turn: bump current_turn and emit phase_started(NARRATIVE)
# so EventScheduler ticks. Avoids running the full TurnManager resolution which
# would have side-effects on every other system.
func _tick_event_scheduler_to(new_turn: int) -> void:
	TurnManager.current_turn = new_turn
	TurnManager.phase_started.emit(TurnManager.Phase.NARRATIVE)
	await get_tree().process_frame

func _count_panels(node: Node) -> int:
	var n := 0
	for c in node.get_children():
		n += _count_panels(c)
		if c is PanelContainer:
			n += 1
	return n

func _collect_links(node: Node, out: Array) -> void:
	if node is LinkButton:
		out.append(node)
	for child in node.get_children():
		_collect_links(child, out)

func _test_event_scheduler_emit() -> void:
	EventScheduler.reset()
	TurnManager.current_turn = 1
	var fired: Array = []
	var cb := func(ev): fired.append(ev)
	EventScheduler.event_fired.connect(cb)
	var ev := EventScheduler.emit_event({"title": "Hi", "severity": EventScheduler.SEVERITY_INFO})
	_check(fired.size() == 1 and str(fired[0].id) == str(ev.id),
		"emit_event puts an event in the bell + fires event_fired")
	_check(EventScheduler.active_count() == 1, "active_count reflects the new event")
	_check(int(ev.turn_fired) == 1, "event records the turn it fired on")
	_check(EventScheduler.dismiss(str(ev.id)) and EventScheduler.active_count() == 0,
		"dismiss removes from active list")
	if EventScheduler.event_fired.is_connected(cb):
		EventScheduler.event_fired.disconnect(cb)
	EventScheduler.reset()

func _test_event_scheduler_schedule() -> void:
	EventScheduler.reset()
	TurnManager.current_turn = 5
	EventScheduler.schedule(8, {"id": "scheduled_test", "title": "Fires on 8",
		"severity": EventScheduler.SEVERITY_WARNING})
	# Turn 6, 7: scheduled event should NOT have fired yet.
	await _tick_event_scheduler_to(6)
	_check(not EventScheduler._active.has("scheduled_test"), "scheduled event waits past turn 6")
	await _tick_event_scheduler_to(7)
	_check(not EventScheduler._active.has("scheduled_test"), "scheduled event waits past turn 7")
	# Turn 8: fires.
	await _tick_event_scheduler_to(8)
	_check(EventScheduler._active.has("scheduled_test"), "scheduled event fires on its turn")
	EventScheduler.reset()

func _test_event_scheduler_forewarn() -> void:
	EventScheduler.reset()
	TurnManager.current_turn = 10
	EventScheduler.schedule(20, {"id": "carbon_tax", "title": "Carbon Tax Applied",
		"severity": EventScheduler.SEVERITY_CRITICAL, "forewarn_turns": 5,
		"forewarn_body": "Tax begins in 5 turns."})
	# Turn 14: still no forewarning.
	await _tick_event_scheduler_to(14)
	_check(not EventScheduler._active.has("carbon_tax:forewarn"), "forewarn not yet armed")
	# Turn 15: forewarning fires (20 - 5).
	await _tick_event_scheduler_to(15)
	_check(EventScheduler._active.has("carbon_tax:forewarn"),
		"forewarning fires N turns before the scheduled event")
	_check(not EventScheduler._active.has("carbon_tax"),
		"main event has not fired yet at forewarn turn")
	# Turn 20: main event fires.
	await _tick_event_scheduler_to(20)
	_check(EventScheduler._active.has("carbon_tax"),
		"main scheduled event fires on its target turn")
	EventScheduler.reset()

func _test_event_scheduler_watch_oneshot() -> void:
	EventScheduler.reset()
	TurnManager.current_turn = 1
	EventScheduler.watch({"type": "turn_reached", "value": 3},
		{"id": "turn3", "title": "Hit turn 3", "severity": EventScheduler.SEVERITY_INFO},
		true)
	await _tick_event_scheduler_to(2)
	_check(not EventScheduler._active.has("turn3"), "watch doesn't fire before predicate is true")
	await _tick_event_scheduler_to(3)
	_check(EventScheduler._active.has("turn3"), "watch fires the turn its predicate becomes true")
	# Dismiss and tick again — one-shot must not re-fire.
	EventScheduler.dismiss("turn3")
	await _tick_event_scheduler_to(4)
	_check(not EventScheduler._active.has("turn3"), "one-shot watch does not re-fire")
	EventScheduler.reset()

func _test_event_scheduler_starvation_ramp() -> void:
	EventScheduler.reset()
	TurnManager.current_turn = 1
	var record := {"instance_id": "inst_test", "building_id": "b_001", "tile_id": "tile_12_4", "missing": []}
	EventScheduler._on_building_starved(record)
	var ev: Dictionary = EventScheduler._active.get("starvation:inst_test", {})
	_check(str(ev.get("severity", "")) == EventScheduler.SEVERITY_WARNING,
		"starvation turn 1 = amber")
	# Turn 2: still amber.
	TurnManager.current_turn = 2
	EventScheduler._on_building_starved(record)
	_check(str(EventScheduler._active["starvation:inst_test"].severity) == EventScheduler.SEVERITY_WARNING,
		"starvation turn 2 = amber")
	# Turn 3: ramps to critical (STARVATION_RAMP_TURNS = 3).
	TurnManager.current_turn = 3
	EventScheduler._on_building_starved(record)
	_check(str(EventScheduler._active["starvation:inst_test"].severity) == EventScheduler.SEVERITY_CRITICAL,
		"starvation turn 3 ramps to critical (red)")
	# Skip turn 4 — building runs (no starvation signal); turn 5 NARRATIVE clears it.
	await _tick_event_scheduler_to(5)
	_check(not EventScheduler._active.has("starvation:inst_test"),
		"auto-clear removes starvation when the building runs again")
	EventScheduler.reset()

func _test_event_scheduler_aggregator() -> void:
	EventScheduler.reset()
	TurnManager.current_turn = 10
	var template := {"title_template": "{count} sales — £{value}",
		"body_template": "rolled up", "severity": EventScheduler.SEVERITY_INFO}
	for i in range(12):
		EventScheduler.aggregate("test_agg", template, 1, 350.0)
	# Aggregator stays open during the turn — no event in bell yet.
	_check(EventScheduler.active_count() == 0, "aggregator does not fire mid-turn")
	# NARRATIVE flushes: one rolled-up event.
	await _tick_event_scheduler_to(10)
	_check(EventScheduler.active_count() == 1,
		"flush_aggregators emits one event per bucket (got %d)" % EventScheduler.active_count())
	var rows: Array = EventScheduler.active_events()
	_check(str(rows[0].title).begins_with("12 sales"),
		"aggregated title interpolates {count} (got '%s')" % str(rows[0].title))
	EventScheduler.reset()

func _test_event_scheduler_max_severity() -> void:
	EventScheduler.reset()
	TurnManager.current_turn = 1
	EventScheduler.emit_event({"id": "i", "title": "i", "severity": EventScheduler.SEVERITY_INFO})
	_check(EventScheduler.max_severity() == EventScheduler.SEVERITY_INFO, "1 info → info")
	EventScheduler.emit_event({"id": "w", "title": "w", "severity": EventScheduler.SEVERITY_WARNING})
	_check(EventScheduler.max_severity() == EventScheduler.SEVERITY_WARNING, "info+warning → warning")
	EventScheduler.emit_event({"id": "c", "title": "c", "severity": EventScheduler.SEVERITY_CRITICAL})
	_check(EventScheduler.max_severity() == EventScheduler.SEVERITY_CRITICAL, "info+warning+critical → critical")
	EventScheduler.dismiss("c")
	_check(EventScheduler.max_severity() == EventScheduler.SEVERITY_WARNING,
		"dismissing the critical drops bell back to warning")
	EventScheduler.reset()

func _test_event_scheduler_roundtrip() -> void:
	EventScheduler.reset()
	TurnManager.current_turn = 50
	EventScheduler.emit_event({"id": "active_a", "title": "A",
		"severity": EventScheduler.SEVERITY_WARNING})
	EventScheduler.schedule(80, {"id": "future_a", "title": "future",
		"severity": EventScheduler.SEVERITY_CRITICAL, "forewarn_turns": 5})
	EventScheduler.watch({"type": "turn_reached", "value": 100},
		{"id": "watch_a", "title": "watched", "severity": EventScheduler.SEVERITY_INFO}, true)
	var snap := EventScheduler.export_state()
	# Wipe and reimport.
	EventScheduler.reset()
	_check(EventScheduler.active_count() == 0 and EventScheduler._scheduled.is_empty()
		and EventScheduler._watches.is_empty(), "reset clears all state")
	EventScheduler.import_state(snap)
	_check(EventScheduler._active.has("active_a"), "round-trip restores active events")
	_check(EventScheduler._scheduled.size() == 1
		and str(EventScheduler._scheduled[0].event.id) == "future_a",
		"round-trip restores scheduled events")
	_check(EventScheduler._watches.size() == 1
		and str(EventScheduler._watches[0].id) == "watch_a",
		"round-trip restores watches")
	EventScheduler.reset()

func _test_modifiers_event_payload() -> void:
	Modifiers.reset()
	EventScheduler.reset()
	TurnManager.current_turn = 1
	# An EventScheduler event with a modifiers payload should auto-add them.
	EventScheduler.emit_event({
		"id": "carbon_tax_apply",
		"title": "Carbon Tax applied",
		"severity": EventScheduler.SEVERITY_CRITICAL,
		"modifiers": [{
			"id": "carbon_tax_transport",
			"domain": "transport_cost", "target": "*",
			"mult": 1.30, "duration_turns": 20,
		}],
	})
	_check(Modifiers.has("carbon_tax_transport"),
		"event with `modifiers` payload auto-registers the modifier on fire")
	_check(absf(Modifiers.apply("transport_cost", "g_001", 10.0) - 13.0) < 0.001,
		"the auto-registered modifier is live for apply (10 * 1.30 = 13)")
	Modifiers.reset()
	EventScheduler.reset()

func _test_event_grouping() -> void:
	EventScheduler.reset()
	TurnManager.current_turn = 1
	for i in range(3):
		EventScheduler._on_building_starved({"instance_id": "p_%d" % i, "building_id": "b_001",
			"tile_id": "tile_6_8", "missing": [{"internal_name": "power", "need": 4, "have": 0}]})
	for i in range(2):
		EventScheduler._on_building_starved({"instance_id": "in_%d" % i, "building_id": "b_002",
			"tile_id": "tile_7_10", "missing": [{"internal_name": "coal", "need": 10, "have": 0}]})
	var power_group := {}
	var input_group := {}
	for g in EventScheduler.grouped_active():
		if str(g.group_key) == "starved_power":
			power_group = g
		elif str(g.group_key) == "starved_inputs":
			input_group = g
	_check(not power_group.is_empty() and (power_group.members as Array).size() == 3,
		"3 power starvations fold into one group")
	_check(str(power_group.get("title", "")) == "Buildings Starved of Power",
		"power group carries the plural title")
	_check(not input_group.is_empty() and (input_group.members as Array).size() == 2,
		"2 input starvations fold into a separate group")
	# dismiss_group clears only that group.
	EventScheduler.dismiss_group("starved_power")
	_check(EventScheduler._active.size() == 2,
		"dismiss_group removes only its own members (got %d left)" % EventScheduler._active.size())
	var remaining := EventScheduler.grouped_active()
	_check(remaining.size() == 1 and str(remaining[0].group_key) == "starved_inputs",
		"only the input group remains after dismissing the power group")
	EventScheduler.reset()

# Clicking a group header expands its members inline (indented) in the same
# dropdown; a member's "Go to" routes a starved building to the building panel.
func _test_notification_group_inline_expand() -> void:
	EventScheduler.reset()
	MatchState.reset()
	TurnManager.current_turn = 1
	for i in range(3):
		EventScheduler._on_building_starved({"instance_id": "ex_%d" % i, "building_id": "b_001",
			"tile_id": "tile_6_8", "missing": [{"internal_name": "power"}]})
	var bell: Node = load("res://scripts/notification_bell.gd").new()
	add_child(bell)
	await get_tree().process_frame
	bell.call("toggle_dropdown")  # opens + builds rows (one collapsed group header)
	await get_tree().process_frame
	var list: VBoxContainer = bell.get("_dropdown_list")
	_check(_count_panels(list) == 1, "collapsed: one group header row (got %d)" % _count_panels(list))
	# Expand the group: header + 3 indented members.
	bell.set("_expanded_group_key", "starved_power")
	bell.call("_rebuild_dropdown_rows")
	await get_tree().process_frame
	_check(_count_panels(list) >= 4, "expanded: header + 3 member rows (got %d)" % _count_panels(list))
	# A member "Go to" routes to the building panel.
	var focused_buildings: Array = []
	var cb := func(b): focused_buildings.append(b)
	MatchState.focus_building_requested.connect(cb)
	var links: Array = []
	_collect_links(bell, links)
	_check(links.size() >= 3, "each expanded member has a Go-to link (got %d)" % links.size())
	if not links.is_empty():
		(links[0] as LinkButton).pressed.emit()
	_check(focused_buildings.size() == 1 and str(focused_buildings[0]).begins_with("ex_"),
		"member Go-to fires focus_building_requested for the building instance")
	MatchState.focus_building_requested.disconnect(cb)
	bell.queue_free()
	await get_tree().process_frame
	EventScheduler.reset()
	MatchState.reset()

# The header bells filter the list by severity ("" = show all).
func _test_notification_header_filter() -> void:
	EventScheduler.reset()
	TurnManager.current_turn = 1
	# Two groups: a critical one and a warning one (2 members each so they group).
	for id in ["c1", "c2"]:
		EventScheduler.emit_event({"id": id, "group_key": "g_crit", "group_title": "Crit",
			"severity": EventScheduler.SEVERITY_CRITICAL})
	for id in ["w1", "w2"]:
		EventScheduler.emit_event({"id": id, "group_key": "g_warn", "group_title": "Warn",
			"severity": EventScheduler.SEVERITY_WARNING})
	var bell: Node = load("res://scripts/notification_bell.gd").new()
	add_child(bell)
	await get_tree().process_frame
	bell.call("toggle_dropdown")
	await get_tree().process_frame
	var list: VBoxContainer = bell.get("_dropdown_list")
	_check(_count_panels(list) == 2, "no filter: both groups show (got %d)" % _count_panels(list))
	# Filter to critical → only the critical group.
	bell.set("_filter_severity", "critical")
	bell.call("_rebuild_dropdown_rows")
	await get_tree().process_frame
	_check(_count_panels(list) == 1, "critical filter: one group (got %d)" % _count_panels(list))
	# Four header filter bells were built.
	_check((bell.get("_filter_bells") as Array).size() == 4, "four header filter bells built")
	# Clearing (navy) shows all again.
	bell.set("_filter_severity", "")
	bell.call("_rebuild_dropdown_rows")
	await get_tree().process_frame
	_check(_count_panels(list) == 2, "cleared filter: both groups show again (got %d)" % _count_panels(list))
	bell.queue_free()
	await get_tree().process_frame
	EventScheduler.reset()

# UI smoke: the navy bell builds, the badge follows the active count (shown at
# >=1), the dropdown opens with one row per event, and dismiss_all clears it.
func _test_notification_bell_smoke() -> void:
	EventScheduler.reset()
	TurnManager.current_turn = 1
	var bell: Node = load("res://scripts/notification_bell.gd").new()
	add_child(bell)
	await get_tree().process_frame
	_check(bell.get("_dropdown") != null, "bell builds its dropdown")
	_check(not (bell.get("_badge") as Label).visible, "badge hidden when no events")
	# One event → badge shows "1" (the navy trigger keeps the unread count).
	# Refreshes coalesce via call_deferred, so settle two frames before reading.
	EventScheduler.emit_event({"id": "u1", "title": "Test warn",
		"severity": EventScheduler.SEVERITY_WARNING})
	await get_tree().process_frame
	await get_tree().process_frame
	_check((bell.get("_badge") as Label).visible and (bell.get("_badge") as Label).text == "1",
		"badge shows 1 with one event (got '%s')" % (bell.get("_badge") as Label).text)
	EventScheduler.emit_event({"id": "u2", "title": "Test crit",
		"severity": EventScheduler.SEVERITY_CRITICAL})
	await get_tree().process_frame
	await get_tree().process_frame
	_check((bell.get("_badge") as Label).text == "2",
		"badge shows the unread count (got '%s')" % (bell.get("_badge") as Label).text)
	# Open dropdown, expect one row per (ungrouped) event.
	bell.call("toggle_dropdown")
	await get_tree().process_frame
	_check((bell.get("_dropdown") as PanelContainer).visible, "dropdown opens on click")
	var list: VBoxContainer = bell.get("_dropdown_list")
	var row_count := 0
	for c in list.get_children():
		if c is PanelContainer:
			row_count += 1
	_check(row_count == 2, "dropdown shows one row per active event (got %d)" % row_count)
	EventScheduler.dismiss("u2")
	await get_tree().process_frame
	await get_tree().process_frame
	_check((bell.get("_badge") as Label).text == "1", "badge drops to 1 after a dismiss")
	EventScheduler.dismiss_all()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not (bell.get("_badge") as Label).visible, "badge hidden after dismiss_all")
	bell.queue_free()
	await get_tree().process_frame
	EventScheduler.reset()

func _test_briefing_items_and_dismissal() -> void:
	# The Briefing assembles decisions + live alerts, decisions are never dismissible,
	# alerts dismiss quietly and re-surface only when the condition worsens.
	var snap := _decision_board_snapshot()
	var loans_before: Array = LoanState.loans.duplicate(true)
	var profit_before: Array = LoanState._profit_history.duplicate()
	var missing_before: Dictionary = Production.missing_by_building.duplicate(true)
	DecisionState.reset()
	TurnBriefing.reset()
	TurnManager.current_turn = 40
	# One pending decision + a bankruptcy-grade runway + one starved building.
	DecisionState.pending_queue = [{"uid": "b1", "def_id": "brokers_offer",
		"target": {"scope": "company", "good_id": "g_001", "name": "Coal"}, "turn_drawn": 40}]
	LoanState.loans = []
	LoanState._profit_history = [-10.0]
	BuildingState.buildings["tb_starved"] = {"instance_id": "tb_starved", "building_id": "b_001",
		"recipe_id": "", "tile_id": "tile_1_1", "owner": MatchState.LOCAL_PLAYER}
	# Whatever collateral the shared test env carries, park cash so runway < £100. Measured
	# AFTER the building is added: a building is collateral, so reading the capacity first
	# left the company solvent again the moment build costs rose.
	MatchState.money = -(LoanState.available_capacity() + 50.0)
	Production.missing_by_building = {"tb_starved": [{"internal_name": "coal"}]}
	TurnBriefing._rebuild_items()
	var ids: Array = TurnBriefing.items().map(func(it) -> String: return str(it.id))
	_check(ids.has("dec:b1"), "briefing: the pending decision becomes a decision item")
	_check(ids.has("alert:bankruptcy"), "briefing: low runway raises the bankruptcy alert")
	_check(ids.has("alert:starved"), "briefing: a starved building raises the starved alert")
	_check(ids[0] == "dec:b1", "briefing: decisions sort first")
	# Decisions are never dismissible; alerts are.
	TurnBriefing.dismiss("dec:b1")
	TurnBriefing._rebuild_items()
	_check(TurnBriefing.items().any(func(it) -> bool: return str(it.id) == "dec:b1"),
		"briefing: dismiss on a decision is a no-op (resolve-only)")
	TurnBriefing.dismiss("alert:starved")
	TurnBriefing._rebuild_items()
	_check(not TurnBriefing.items().any(func(it) -> bool: return str(it.id) == "alert:starved"),
		"briefing: a dismissed alert leaves the list")
	# Same magnitude → stays quiet; worsened (another building starves) → re-surfaces.
	BuildingState.buildings["tb_starved2"] = {"instance_id": "tb_starved2", "building_id": "b_001",
		"recipe_id": "", "tile_id": "tile_1_2", "owner": MatchState.LOCAL_PLAYER}
	Production.missing_by_building["tb_starved2"] = [{"internal_name": "power"}]
	TurnBriefing._rebuild_items()
	_check(TurnBriefing.items().any(func(it) -> bool: return str(it.id) == "alert:starved"),
		"briefing: the starved alert re-surfaces when the count worsens")
	BuildingState.buildings.erase("tb_starved")
	BuildingState.buildings.erase("tb_starved2")
	Production.missing_by_building = missing_before
	LoanState.loans = loans_before
	LoanState._profit_history = profit_before
	TurnBriefing.reset()
	_decision_board_restore(snap)

func _test_briefing_event_mapping() -> void:
	# Bell events map into sections: research → info, unknown kinds → news; dismissing
	# in the Briefing dismisses in the bell (one source of truth).
	var snap := _decision_board_snapshot()
	EventScheduler.reset()
	TurnBriefing.reset()
	EventScheduler.emit_event({"id": "tb_ev_res", "kind": "research_unlocked",
		"title": "Unlocked: Test", "body": "x", "persistent": false,
		"research_name": "Test", "research_reward": "Reward X", "research_condition": "Produce coal 5 units"})
	EventScheduler.emit_event({"id": "tb_ev_news", "kind": "carbon_announcement",
		"title": "Carbon tax announced", "body": "x", "severity": "warning", "persistent": true})
	TurnBriefing._rebuild_items()
	var by_id := {}
	for it in TurnBriefing.items():
		by_id[str(it.id)] = it
	# Research unlocks aggregate into a single "info" update that carries each entry.
	var agg: Dictionary = by_id.get("research_unlocked_agg", {})
	_check(not agg.is_empty() and str(agg.get("section", "")) == "info" \
			and str((agg.get("research", [{}])[0] as Dictionary).get("reward", "")) == "Reward X",
		"briefing: research events land in the info section")
	_check(by_id.has("ev:tb_ev_news") and str(by_id["ev:tb_ev_news"].section) == "news",
		"briefing: unknown announcement kinds land in the news section")
	TurnBriefing.dismiss("ev:tb_ev_news")
	_check(not EventScheduler._active.has("tb_ev_news"),
		"briefing: dismissing an event item dismisses it in the bell too")
	EventScheduler.reset()
	TurnBriefing.reset()
	_decision_board_restore(snap)
