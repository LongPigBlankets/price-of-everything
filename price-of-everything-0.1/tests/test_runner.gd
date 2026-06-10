extends Node
## Minimal, zero-dependency headless test runner for price-of-everything.
##
## Fast path (one command; exit code 0 = all pass, 1 = a failure):
##     <godot> --headless res://tests/test_runner.tscn
## Or from the editor: open tests/test_runner.tscn and press F6 (Run Current Scene);
## results print in the Output panel.
##
## It runs as a SCENE (not --script) so the project autoloads — Catalog,
## Stockpile, Production, DS, etc. — are available. The goal is to catch, without
## manual clicking: script parse errors, broken @onready paths, main.tscn
## corruption, and data-loading regressions.

var _passed := 0
var _failed := 0

func _ready() -> void:
	print("\n==== price-of-everything tests ====")
	_test_scripts_parse()
	_test_widgets_instantiate()
	_test_recipe_row_instantiates()
	await _test_stockpile_legend_label_visible()
	_test_scene_loads()
	await _test_main_scene_instantiates()
	_test_catalog_loaded()
	_test_recipe_requirements()
	_test_menu_icons()
	_test_bottom_menu_default()
	_test_ports()
	_test_transport_service()
	_test_transport_boundaries()
	_test_build_mode_overlay_survey_visibility()
	_test_direct_build_skips_build_overlay()
	await _test_building_ledger()
	await _test_debug_terminal()
	_test_queue_move()
	_test_move_extras()
	_test_storage_boost()
	_test_queue_sell()
	_test_market_execute_sale()
	_test_market_execute_sale_skip_consume()
	_test_market_execute_sale_pay_transport()
	_test_npc_ports()
	_test_bulk_sell()
	_test_output_market_route()
	_test_transaction_ledger()
	_test_market_buy()
	_test_tax_dividend_caps()
	_test_purchases()
	_test_recipes_producing()
	_test_transfer_helpers()
	_test_output_conservation()
	_test_market_sale_credits()
	_test_owner_costs()
	_test_recurring_sell_multitile()
	_test_auto_sell_goods()
	_test_price_impact()
	_test_buy_price()
	_test_limestone_concrete()
	_test_construction()
	_test_construction_awaiting()
	_test_construction_sourcing()
	_test_construction_cancel()
	await _test_construction_detail_panel()
	_test_save_load_roundtrip()
	await _test_pending_load_applies_on_scene_ready()
	_test_start_config_expansion()
	await _test_start_config_applies_on_scene_ready()
	_test_save_version_migration()
	_test_game_ended_persists()
	_test_construction_survives_load()
	_test_autosave_rotation()
	await _test_save_load_ui()
	await _test_event_scheduler_emit()
	await _test_event_scheduler_schedule()
	await _test_event_scheduler_forewarn()
	await _test_event_scheduler_watch_oneshot()
	await _test_event_scheduler_starvation_ramp()
	await _test_event_scheduler_aggregator()
	await _test_event_scheduler_max_severity()
	await _test_event_scheduler_roundtrip()
	await _test_modifiers_basic()
	await _test_modifiers_stacking()
	await _test_modifiers_target_match()
	await _test_modifiers_expiry()
	await _test_modifiers_event_payload()
	await _test_modifiers_production_recipe_output()
	await _test_modifiers_roundtrip()
	await _test_mining_mastery_tech_unlock()
	await _test_mining_mastery_free_unlock()
	await _test_notification_bell_smoke()
	print("==== %d passed, %d failed ====\n" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)

# Save/load round-trip: populate every save-relevant system, export → JSON → import
# into the reset systems → export again; the two snapshots must agree section by
# section. Catches any state field a later change forgets to serialize.
func _test_save_load_roundtrip() -> void:
	MatchState.add_money(123.0)
	var inst: String = MatchState.add_building("b_001", "r_001", "tile_12_4")
	Stockpile.add("tile_12_4", "g_001", 25)
	MatchState.mark_tile_surveyed("tile_12_4")
	MatchState.add_recurring_move("tile_12_4", "tile_12_2", {"g_001": 5})
	MatchState.add_recurring_sell("tile_12_4", {"g_001": 3})
	MatchState.add_recurring_buy("tile_12_4", "g_001", 7)
	MatchState.add_recurring_bulk_sell({"good_id": "", "finished_only": true, "per_tile_keep": 2})
	MatchState.queue_move("tile_12_4", "tile_3_8", {"g_001": 5})  # an in-flight shipment
	_check(LoanState.take_loan(30.0), "roundtrip: loan taken for debt state")

	var snap1: Dictionary = SaveLoad.export_snapshot()
	# Real file round-trip via the slot API (covers JSON I/O + slot listing too).
	_check(SaveLoad.save_slot("__test_roundtrip") == "", "save_slot writes without error")
	var found := false
	for s in SaveLoad.list_slots():
		if str(s.slot) == "__test_roundtrip":
			found = true
	_check(found, "list_slots sees the new save")
	# restart_scene=false: apply in place (the default scene-reload path needs the
	# full game scene; the visual rebuild is exercised manually / by scene tests).
	_check(SaveLoad.load_slot("__test_roundtrip", false) == "", "load_slot applies without error")
	var snap2: Dictionary = SaveLoad.export_snapshot()
	for section in ["turn", "match", "stockpile", "loans", "construction", "market", "production", "events", "modifiers", "infrastructure"]:
		_check(_canonical_json(snap1[section]) == _canonical_json(snap2[section]),
			"round-trip preserves '%s'" % section)

	# Spot-check the loaded state is live, not just equal-on-paper.
	_check(str(MatchState.get_building(inst).get("tile_id", "")) == "tile_12_4",
		"loaded building is queryable")
	_check(Stockpile.get_at_tile("tile_12_4", "g_001") == 20, "loaded stockpile intact (25 - 5 moved)")
	_check(LoanState.total_outstanding() > 0.0, "loaded debt outstanding")
	_check(MatchState.recurring_moves.size() == 1 and MatchState.recurring_buys.size() == 1,
		"recurring orders survive the round-trip")
	var requoted := true
	for shipment in MatchState.pending_transport_shipments:
		if not (shipment.has("tiles") and shipment.has("path") and shipment.has("legs")):
			requoted = false
	_check(requoted, "in-flight shipment routes re-quoted on load")
	DirAccess.remove_absolute("user://saves/__test_roundtrip.json")

# Both sides of a comparison pass through stringify -> parse -> normalize so 5.0
# (native float) and 5 (JSON-round-tripped int) canonicalise identically.
func _canonical_json(section: Variant) -> String:
	return JSON.stringify(SaveLoad.normalize_jsonish(JSON.parse_string(JSON.stringify(section))))

# Phase 3 start configs: the authoring shape expands into a full snapshot —
# default money, loans become debt without cash, recurring orders stamped,
# port tiles + owned-building tiles pre-surveyed, instance ids collision-free.
func _test_start_config_expansion() -> void:
	var snap: Dictionary = SaveLoad.expand_start_config({
		"start": true,
		"money": 350,
		"loans": [{"principal": 150}],
		"buildings": [{"building_id": "b_001", "recipe_id": "r_001", "tile_id": "tile_6_8"}],
		"stockpile": {"tile_6_8": {"g_001": 50}},
		"recurring": {"sells": [{"source": "tile_6_8", "goods": {"g_001": 10}}]},
	})
	var match_d: Dictionary = snap.get("match", {})
	_check(float(match_d.get("money", 0.0)) == 350.0, "start config: money set")
	var buildings: Dictionary = match_d.get("buildings", {})
	_check(buildings.size() == 1 and str(buildings.values()[0].get("tile_id", "")) == "tile_6_8",
		"start config: building expanded with tile")
	_check(str(buildings.keys()[0]).begins_with("inst_b_001_"), "start config: instance id assigned")
	var loans: Array = (snap.get("loans", {}) as Dictionary).get("loans", [])
	var loan_ok: bool = loans.size() == 1 \
		and absf(float(loans[0].principal_remaining) - 165.0) < 0.001 \
		and absf(float(loans[0].payment_per_turn) - 165.0 / float(EconomyConfig.LOAN_TERM_TURNS)) < 0.001
	_check(loan_ok, "start config: loan amortised like take_loan (150 -> 165 owed)")
	var surveyed: Dictionary = match_d.get("surveyed_tiles", {})
	_check(surveyed.has("tile_6_8") and surveyed.has("tile_5_10"),
		"start config: owned-building tile + port tiles pre-surveyed")
	var sells: Array = match_d.get("recurring_sells", [])
	_check(sells.size() == 1 and int(sells[0].get("turn_started", -1)) == 1,
		"start config: recurring sell stamped turn_started 1")
	var defaults: Dictionary = SaveLoad.expand_start_config({"start": true})
	_check(float((defaults.get("match", {}) as Dictionary).get("money", 0.0)) == EconomyConfig.STARTING_MONEY,
		"start config: omitted money falls back to STARTING_MONEY")

# Phase 3 end-to-end: a start config applied through the scene pipeline keeps
# the scene-seeded NPC buildings (ports/ruins), seeds debt WITHOUT cash, and
# leaves the CSV deposit yields intact (the config carries no deposit data).
func _test_start_config_applies_on_scene_ready() -> void:
	var cfg: Dictionary = SaveLoad._read_json_file("res://data/starts/coal_baron.json")
	_check(not cfg.is_empty(), "coal_baron.json parses")
	SaveLoad._pending_snapshot = SaveLoad.expand_start_config(cfg)
	var inst: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(inst)
	await get_tree().process_frame
	_check(absf(MatchState.money - 350.0) < 0.001, "start: money is the configured 350 (no loan cash)")
	_check(absf(LoanState.total_outstanding() - 165.0) < 0.001, "start: debt outstanding 165")
	var mines := 0
	var npc := 0
	for iid in MatchState.buildings:
		var b: Dictionary = MatchState.buildings[iid]
		if str(b.get("building_id", "")) == "b_001":
			mines += 1
		if not MatchState.is_player_owned(b):
			npc += 1
	_check(mines == 1, "start: configured mine exists")
	_check(npc >= 5, "start: scene-seeded NPC ports/ruins survive the start import")
	_check(Stockpile.get_at_tile("tile_6_8", "g_001") == 50, "start: stockpile seeded")
	_check(MatchState.recurring_sells.size() == 1, "start: recurring sell order live")
	_check(MatchState.deposit_remaining_for("tile_6_8", "coal") == 1000,
		"start: CSV deposit yields survive (no deposit data in the config)")
	inst.queue_free()
	await get_tree().process_frame

# Phase 4: a v1 save (no ruleset) steps up the migration ladder on load and
# arrives with the standard ruleset filled in.
func _test_save_version_migration() -> void:
	var snap: Dictionary = SaveLoad.export_snapshot()
	snap["save_version"] = 1
	(snap.get("match", {}) as Dictionary).erase("ruleset")
	(snap.get("meta", {}) as Dictionary).erase("ruleset")
	DirAccess.make_dir_recursive_absolute("user://saves")
	var f := FileAccess.open("user://saves/__test_v1.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(snap))
	f.close()
	MatchState.ruleset = {"name": "__sentinel__"}
	_check(SaveLoad.load_slot("__test_v1", false) == "", "v1 save loads through migration")
	_check(str(MatchState.ruleset.get("name", "")) == "standard",
		"v1 -> v2 migration fills in the standard ruleset")
	_check(str(SaveLoad.export_snapshot().get("meta", {}).get("ruleset", "")) == "standard",
		"migrated save re-exports with meta.ruleset")
	DirAccess.remove_absolute("user://saves/__test_v1.json")

# Phase 4: a finished game stays finished across save/load.
func _test_game_ended_persists() -> void:
	var snap: Dictionary = SaveLoad.export_snapshot()
	(snap.get("turn", {}) as Dictionary)["game_ended"] = true
	(snap.get("turn", {}) as Dictionary)["current_turn"] = TurnManager.MAX_TURNS + 1
	SaveLoad.import_snapshot(snap)
	_check(TurnManager.game_ended and TurnManager.current_turn == TurnManager.MAX_TURNS + 1,
		"game_ended + final turn survive a load")
	TurnManager.reset_for_test()

# Phase 4: an awaiting-materials construction project keeps working after a
# save/load — the project dict, its missing-materials map and the
# construction-tagged shipments are all id/tile keyed, so once the materials
# reach the tile post-load, claim_materials promotes it.
func _test_construction_survives_load() -> void:
	MatchState.add_money(1000.0)
	var inst_id: String = Construction.start_awaiting_market("b_002", "r_002", "tile_13_2", 100.0)
	_check(inst_id != "", "awaiting-market construction project created")
	SaveLoad.import_snapshot(SaveLoad.normalize_jsonish(
		JSON.parse_string(JSON.stringify(SaveLoad.export_snapshot()))))
	var project: Dictionary = Construction.construction_projects.get(inst_id, {})
	_check(str(project.get("status", "")) == Construction.STATUS_AWAITING_MATERIALS,
		"project still awaiting materials after load")
	var tagged := false
	for shipment in MatchState.pending_transport_shipments:
		if str(shipment.get("construction_instance_id", "")) == inst_id:
			tagged = true
	_check(tagged, "construction-tagged material shipment survives the load")
	# Materials land on the tile (as an arrived shipment would deliver them) and
	# the loaded project claims them and starts its countdown.
	for good_id in (project.get("missing_materials", {}) as Dictionary).keys():
		Stockpile.add("tile_13_2", str(good_id), int(project["missing_materials"][good_id]))
	Construction.claim_materials()
	_check(str(Construction.construction_projects.get(inst_id, {}).get("status", "")) \
		== Construction.STATUS_UNDER_CONSTRUCTION,
		"loaded project claims arrived materials and starts construction")
	Construction.cancel(inst_id)

# Phase 4: the autosave hook fires only on every Nth finished turn and rotates
# its slot index. (Drive the handler directly; committing 10 real turns is slow.)
func _test_autosave_rotation() -> void:
	var saved_turn: int = TurnManager.current_turn
	var saved_index: int = SaveLoad._autosave_index
	SaveLoad._autosave_index = 0
	TurnManager.current_turn = SaveLoad.AUTOSAVE_EVERY_TURNS + 1  # turn N just finished
	SaveLoad._on_turn_resolution_completed()
	_check(SaveLoad._autosave_index == 1 and FileAccess.file_exists("user://saves/autosave_1.json"),
		"autosave fires on the Nth finished turn into slot 1")
	TurnManager.current_turn = SaveLoad.AUTOSAVE_EVERY_TURNS + 2  # off-cadence turn
	SaveLoad._on_turn_resolution_completed()
	_check(SaveLoad._autosave_index == 1, "no autosave between cadence points")
	TurnManager.current_turn = 2 * SaveLoad.AUTOSAVE_EVERY_TURNS + 1
	SaveLoad._on_turn_resolution_completed()
	_check(SaveLoad._autosave_index == 2, "next cadence point rotates to slot 2")
	DirAccess.remove_absolute("user://saves/autosave_1.json")
	DirAccess.remove_absolute("user://saves/autosave_2.json")
	TurnManager.current_turn = saved_turn
	SaveLoad._autosave_index = saved_index

# --- EventScheduler ----------------------------------------------------------
# Substrate tests. The bell UI lives separately and has its own UI smoke test.

# Drive a synthetic turn: bump current_turn and emit phase_started(NARRATIVE)
# so EventScheduler ticks. Avoids running the full TurnManager resolution which
# would have side-effects on every other system.
func _tick_event_scheduler_to(new_turn: int) -> void:
	TurnManager.current_turn = new_turn
	TurnManager.phase_started.emit(TurnManager.Phase.NARRATIVE)
	await get_tree().process_frame

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

# --- Modifiers ---------------------------------------------------------------

func _test_modifiers_basic() -> void:
	Modifiers.reset()
	TurnManager.current_turn = 1
	# No active modifiers → base passes through untouched.
	_check(Modifiers.apply("recipe_output", "r_001", 20.0) == 20.0,
		"apply with empty registry returns base unchanged")
	# Add a +5% recipe_output modifier on r_001.
	var mid := Modifiers.add({"id": "test_a", "domain": "recipe_output",
		"target": "r_001", "mult": 1.05, "label": "Test +5%"})
	_check(mid == "test_a" and Modifiers.has("test_a"),
		"add registers the modifier with the supplied id")
	_check(absf(Modifiers.apply("recipe_output", "r_001", 20.0) - 21.0) < 0.001,
		"applied to r_001: 20 * 1.05 = 21")
	# Different target → unchanged.
	_check(absf(Modifiers.apply("recipe_output", "r_002", 20.0) - 20.0) < 0.001,
		"r_001-targeted modifier does NOT affect r_002")
	# Different domain → unchanged even for the same target.
	_check(absf(Modifiers.apply("transport_cost", "r_001", 20.0) - 20.0) < 0.001,
		"recipe_output modifier does NOT affect the transport_cost domain")
	_check(Modifiers.remove("test_a") and not Modifiers.has("test_a"),
		"remove drops the modifier")
	Modifiers.reset()

func _test_modifiers_stacking() -> void:
	Modifiers.reset()
	# Add-then-mult stacking: (base + adds) * prod(mults).
	# base = 10, +2 (add) and +3 (add) → 15; then *1.5 and *1.2 → 27.
	Modifiers.add({"id": "a", "domain": "recipe_output", "target": "*", "add": 2.0})
	Modifiers.add({"id": "b", "domain": "recipe_output", "target": "*", "add": 3.0})
	Modifiers.add({"id": "c", "domain": "recipe_output", "target": "*", "mult": 1.5})
	Modifiers.add({"id": "d", "domain": "recipe_output", "target": "*", "mult": 1.2})
	var got: float = Modifiers.apply("recipe_output", "r_001", 10.0)
	_check(absf(got - 27.0) < 0.001,
		"stacking: (10+2+3)*1.5*1.2 = 27 (got %.3f)" % got)
	Modifiers.reset()

func _test_modifiers_target_match() -> void:
	Modifiers.reset()
	# target_match: only fires when ctx provides the required keys.
	Modifiers.add({"id": "extraction_only", "domain": "recipe_output",
		"target_match": {"recipe_type": "extraction"}, "mult": 1.10})
	var ctx_ext := {"recipe_type": "extraction"}
	var ctx_smelt := {"recipe_type": "smelting"}
	_check(absf(Modifiers.apply("recipe_output", "r_001", 20.0, ctx_ext) - 22.0) < 0.001,
		"target_match recipe_type=extraction applies to extraction ctx")
	_check(absf(Modifiers.apply("recipe_output", "r_003", 20.0, ctx_smelt) - 20.0) < 0.001,
		"target_match recipe_type=extraction does NOT apply to a smelting ctx")
	_check(absf(Modifiers.apply("recipe_output", "r_001", 20.0) - 20.0) < 0.001,
		"target_match modifier inert when ctx is missing the key")
	Modifiers.reset()

func _test_modifiers_expiry() -> void:
	Modifiers.reset()
	TurnManager.current_turn = 10
	Modifiers.add({"id": "tempo", "domain": "recipe_output",
		"target": "*", "mult": 2.0, "duration_turns": 5})
	_check(int(Modifiers._modifiers["tempo"]["expires_turn"]) == 15,
		"duration_turns is converted into an absolute expires_turn")
	_check(absf(Modifiers.apply("recipe_output", "r_001", 10.0) - 20.0) < 0.001,
		"modifier active before expiry")
	# Tick NARRATIVE phases up to and past expiry.
	TurnManager.current_turn = 14
	TurnManager.phase_started.emit(TurnManager.Phase.NARRATIVE)
	await get_tree().process_frame
	_check(Modifiers.has("tempo"), "still active one turn before expiry")
	TurnManager.current_turn = 15
	TurnManager.phase_started.emit(TurnManager.Phase.NARRATIVE)
	await get_tree().process_frame
	_check(not Modifiers.has("tempo"), "pruned on the turn it expires")
	_check(absf(Modifiers.apply("recipe_output", "r_001", 10.0) - 10.0) < 0.001,
		"expired modifier no longer affects apply")
	Modifiers.reset()

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

func _test_modifiers_production_recipe_output() -> void:
	# Drives a coal mine through Production once with no modifier (baseline),
	# then a second time with +5% extraction. Asserts the +5% takes effect end
	# to end: not just in Modifiers.apply but in what lands in the stockpile.
	Modifiers.reset()
	MatchState.reset()
	Stockpile.clear_all()
	var tile := "tile_6_8"  # has a coal deposit
	var inst: String = MatchState.add_building("b_001", "r_001", tile)
	# Force-allow the mine to run (deposit is seeded from the live tile map,
	# which a clean test environment doesn't have — drop the depletion gate by
	# revealing + topping up the deposit).
	MatchState.reveal_deposit(tile, "coal")
	MatchState.deposit_remaining[tile] = {"coal": 999}

	var summary := _fresh_production_summary()
	Production._produce_outputs(MatchState.get_building(inst), Catalog.get_recipe("r_001"), summary)
	Production._flush_output_buffer()
	var base_produced: int = int(summary.produced.get("g_001", 0))
	_check(base_produced == 20, "baseline: coal recipe produces 20 (got %d)" % base_produced)

	# Now with the Mining Mastery modifier active: extraction recipes +5%.
	Stockpile.clear_all()
	Modifiers.add({"id": "mining_mastery_bonus", "domain": "recipe_output",
		"target_match": {"recipe_type": "extraction"}, "mult": 1.05})
	summary = _fresh_production_summary()
	Production._produce_outputs(MatchState.get_building(inst), Catalog.get_recipe("r_001"), summary)
	Production._flush_output_buffer()
	var boosted_produced: int = int(summary.produced.get("g_001", 0))
	_check(boosted_produced == 21, "with +5% extraction modifier: 20 → 21 (got %d)" % boosted_produced)
	_check(Stockpile.get_at_tile(tile, "g_001") == 21,
		"the boosted output lands in the tile stockpile (got %d)" % Stockpile.get_at_tile(tile, "g_001"))
	Modifiers.reset()
	MatchState.remove_building(inst)

func _test_modifiers_roundtrip() -> void:
	Modifiers.reset()
	TurnManager.current_turn = 50
	Modifiers.add({"id": "a", "domain": "recipe_output", "target": "*",
		"mult": 1.07, "expires_turn": 100, "label": "A"})
	Modifiers.add({"id": "b", "domain": "transport_cost",
		"target_match": {"good_id": "g_001"}, "add": 0.5, "expires_turn": 80})
	var snap: Dictionary = Modifiers.export_state()
	Modifiers.reset()
	_check(Modifiers.active_count() == 0, "reset clears the registry")
	Modifiers.import_state(snap)
	_check(Modifiers.has("a") and Modifiers.has("b"),
		"round-trip restores both modifiers")
	_check(absf(Modifiers.apply("recipe_output", "anything", 10.0) - 10.7) < 0.001,
		"restored 'a' still applies (10 * 1.07 = 10.7)")
	_check(absf(Modifiers.apply("transport_cost", "g_001", 1.0, {"good_id": "g_001"}) - 1.5) < 0.001,
		"restored 'b' still applies (1 + 0.5)")
	Modifiers.reset()

# End-to-end the demo unlock: a mine for each of the 6 staple deposits triggers
# the research tech ("Mining Mastery", research_unlocks.csv) → MatchState grants
# the unlock when its condition is met → Modifiers applies the +5% bonus.
func _test_mining_mastery_tech_unlock() -> void:
	Modifiers.reset()
	MatchState.reset()
	Stockpile.clear_all()

	# The tech exists in the loaded research defs.
	var found_def := false
	for d in MatchState._unlock_defs:
		if str(d.title) == "Mining Mastery":
			found_def = true
	_check(found_def, "Mining Mastery exists as a research unlock def")

	# Recipes whose deposit requirement matches the six staple types — all run
	# on the b_001 (Mine) building.
	var by_deposit := {
		"coal": "r_001", "iron_ore": "r_002", "copper_ore": "r_006",
		"basic_salt": "r_010", "limestone": "r_019", "bauxite_ore": "r_015",
	}
	# Build FIVE of the six first: condition not yet met, no unlock, no modifier.
	var deps: Array = by_deposit.keys()
	for j in range(5):
		MatchState.add_building("b_001", str(by_deposit[deps[j]]), "tile_mm_%d" % j)
	_check(not MatchState.has_mine_for_each_staple_ore(),
		"condition false with only 5 of 6 staple ores")
	_check(not MatchState.is_unlocked("Mining Mastery"),
		"tech not unlocked with 5 of 6 mines")
	_check(not Modifiers.has("mining_mastery_bonus"),
		"modifier not granted before the tech unlocks")

	# Build the sixth — add_building re-checks unlock conditions, which grants
	# the tech, which (via MatchState.unlock_granted) registers the modifier.
	MatchState.add_building("b_001", str(by_deposit[deps[5]]), "tile_mm_5")
	_check(MatchState.has_mine_for_each_staple_ore(),
		"condition true once all six staple ores have mines")
	_check(MatchState.is_unlocked("Mining Mastery"),
		"the sixth mine unlocks Mining Mastery")
	_check(Modifiers.has("mining_mastery_bonus"),
		"unlocking the tech registers the +5% extraction modifier")

	# Non-extraction recipes unaffected; extraction recipes get +5%.
	_check(absf(Modifiers.apply("recipe_output", "r_003", 30.0,
			{"recipe_type": "smelting"}) - 30.0) < 0.001,
		"the bonus only applies to extraction recipes")
	_check(absf(Modifiers.apply("recipe_output", "r_001", 20.0,
			{"recipe_type": "extraction"}) - 21.0) < 0.001,
		"an extraction recipe gets 20 → 21 with the bonus")

	# The bonus is timed: 30 turns from grant. Check the expiry stamp.
	var mod: Dictionary = Modifiers._modifiers["mining_mastery_bonus"]
	_check(int(mod.get("expires_turn", 0)) == int(TurnManager.current_turn) + 30,
		"the bonus expires 30 turns after it is granted")

	# Idempotent: building a seventh mine doesn't re-grant or stack.
	MatchState.add_building("b_001", "r_001", "tile_mm_extra")
	_check(Modifiers.active_count() == 1,
		"the one-shot unlock does not re-grant the modifier on further mines")

	Modifiers.reset()
	MatchState.reset()

# Free-pick path: spending a free unlock on Mining Mastery (via_condition=false)
# also routes through grant_unlock → unlock_granted, so the bonus still lands.
func _test_mining_mastery_free_unlock() -> void:
	Modifiers.reset()
	MatchState.reset()
	_check(not Modifiers.has("mining_mastery_bonus"), "no bonus before free pick")
	MatchState.grant_unlock("Mining Mastery", false)
	_check(MatchState.is_unlocked("Mining Mastery"), "free pick unlocks the tech")
	_check(Modifiers.has("mining_mastery_bonus"),
		"free-picking the tech also grants the modifier")
	Modifiers.reset()
	MatchState.reset()

func _fresh_production_summary() -> Dictionary:
	# Minimal summary skeleton Production._dispatch_output_to_stockpile reads/writes.
	return {
		"produced": {},
		"transport_paid": 0.0,
		"money_out": 0.0,
		"money_in": 0.0,
		"goods_sales_revenue": 0.0,
		"goods_purchased_cost": 0.0,
		"sold": {},
	}

# UI smoke: the bell builds, reads EventScheduler state, the badge follows the
# active count, the bell colour follows max severity, and the dropdown opens.
func _test_notification_bell_smoke() -> void:
	EventScheduler.reset()
	TurnManager.current_turn = 1
	var bell: Node = load("res://scripts/notification_bell.gd").new()
	add_child(bell)
	await get_tree().process_frame
	_check(bell.get("_dropdown") != null, "bell builds its dropdown")
	# Empty: badge hidden, bell grey (no flash).
	_check(not (bell.get("_badge") as Label).visible,
		"badge hidden when no events")
	# Fire a warning event; badge stays hidden (n<=1), bell colour amber.
	# The bell coalesces refreshes via call_deferred, so settle two frames before
	# reading the deferred-updated colour/badge.
	EventScheduler.emit_event({"id": "u1", "title": "Test warn",
		"severity": EventScheduler.SEVERITY_WARNING})
	await get_tree().process_frame
	await get_tree().process_frame
	_check(bell._bg_target_color == DS.PALETTE.WARN,
		"single warning → bell amber")
	# Add a critical → bell red; badge shows "2".
	EventScheduler.emit_event({"id": "u2", "title": "Test crit",
		"severity": EventScheduler.SEVERITY_CRITICAL})
	await get_tree().process_frame
	await get_tree().process_frame
	_check(bell._bg_target_color == DS.PALETTE.DANGER,
		"warning + critical → bell red")
	_check((bell.get("_badge") as Label).visible
		and (bell.get("_badge") as Label).text == "2",
		"badge shows the unread count (got '%s')" % (bell.get("_badge") as Label).text)
	# Open dropdown, expect rows for both events.
	bell.call("toggle_dropdown")
	await get_tree().process_frame
	_check((bell.get("_dropdown") as PanelContainer).visible, "dropdown opens on click")
	var list: VBoxContainer = bell.get("_dropdown_list")
	# rows = list children excluding the always-present "empty" label.
	var row_count := 0
	for c in list.get_children():
		if c is PanelContainer:
			row_count += 1
	_check(row_count == 2, "dropdown shows one row per active event (got %d)" % row_count)
	# Dismiss the critical from inside the EventScheduler; bell falls back to amber.
	EventScheduler.dismiss("u2")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(bell._bg_target_color == DS.PALETTE.WARN,
		"dismissing the critical drops bell back to amber")
	# Mark all read → bell grey, badge hidden, dropdown shows the empty label.
	EventScheduler.dismiss_all()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(bell._bg_target_color == DS.PALETTE.BG_INSET,
		"dismiss_all → bell grey (BG_INSET)")
	_check(not (bell.get("_badge") as Label).visible, "badge hidden after dismiss_all")
	bell.queue_free()
	await get_tree().process_frame
	EventScheduler.reset()

# UI: the save/load screens and the Esc pause menu build, gate their CTAs, and
# the save screen actually writes the named slot.
func _test_save_load_ui() -> void:
	_check(SaveLoad.save_slot("__test_ui") == "", "fixture save for the load screen")
	var screen: SaveLoadScreen = SaveLoadScreen.open(self, SaveLoadScreen.Mode.LOAD)
	await get_tree().process_frame
	_check(screen._cta != null and screen._cta.disabled,
		"load screen: CTA disabled until a save is picked")
	var rows: Array = []
	_collect_buttons(screen, rows)
	var toggle_rows := 0
	for b in rows:
		if (b as Button).toggle_mode:
			toggle_rows += 1
	_check(toggle_rows == SaveLoad.list_slots().size(),
		"load screen: one selectable row per save slot")
	screen.hide()  # frees itself
	await get_tree().process_frame

	var save_screen: SaveLoadScreen = SaveLoadScreen.open(self, SaveLoadScreen.Mode.SAVE)
	await get_tree().process_frame
	_check(save_screen._cta.disabled, "save screen: CTA disabled while the name is empty")
	save_screen._name_edit.text = "__test_ui_named"
	save_screen._do_save()
	_check(FileAccess.file_exists("user://saves/__test_ui_named.json"),
		"save screen: writes the named slot")
	_check(not save_screen.visible, "save screen: closes after saving")
	await get_tree().process_frame

	var menu: PauseMenu = PauseMenu.open(self)
	await get_tree().process_frame
	var menu_buttons: Array = []
	_collect_buttons(menu, menu_buttons)
	_check(menu_buttons.size() == 5, "pause menu: shows the 5 options")
	_check(PanelStack.close_top() and not menu.visible, "pause menu: Esc path (close_top) closes it")
	await get_tree().process_frame
	DirAccess.remove_absolute("user://saves/__test_ui.json")
	DirAccess.remove_absolute("user://saves/__test_ui_named.json")

func _collect_buttons(node: Node, out: Array) -> void:
	if node is Button:
		out.append(node)
	for child in node.get_children():
		_collect_buttons(child, out)

# Phase 2 load sequencing: a pending snapshot must apply at the end of
# world_map._ready (after NPC ports/deposit seeding) and overwrite fresh-match
# state — this is the path the main menu's Load Game and the terminal use.
func _test_pending_load_applies_on_scene_ready() -> void:
	var before_money: float = MatchState.money
	var before_buildings: int = MatchState.buildings.size()
	var snap: Dictionary = SaveLoad.export_snapshot()
	MatchState.add_money(777.0)  # diverge so the apply is observable
	SaveLoad._pending_snapshot = snap
	var inst: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(inst)
	await get_tree().process_frame
	_check(not SaveLoad.has_pending(), "pending save is consumed when the map scene readies")
	_check(absf(MatchState.money - before_money) < 0.001, "pending save restores money over fresh-match state")
	_check(MatchState.buildings.size() == before_buildings, "pending save restores the building set")
	inst.queue_free()
	await get_tree().process_frame

func _check(ok: bool, name: String) -> void:
	if ok:
		_passed += 1
		print("  PASS  ", name)
	else:
		_failed += 1
		printerr("  FAIL  ", name)

func _replace_dict(target: Dictionary, source: Dictionary) -> void:
	target.clear()
	for key in source:
		target[key] = source[key]

func _test_storage_boost() -> void:
	MatchState.add_building("b_004", "", "tile_3_3", "Three Diamonds Shipping Corporation")
	_check(Stockpile.get_capacity("tile_3_3") == Stockpile.TILE_CAPACITY + 500,
		"storage_boost raises tile capacity (port = +500)")

func _test_market_sale_credits() -> void:
	# Output routed to market should be sold and its revenue credited on arrival,
	# not silently lost. (Reproduces the "produced but never stockpiled/consumed/sold".)
	MatchState.reset()
	Stockpile.clear_all()
	MatchState.money = 0.0
	var summary := {"transport_paid": 0.0, "money_out": 0.0, "money_in": 0.0,
		"goods_sales_revenue": 0.0, "sold": {}}
	Production._sell_output_to_market("tile_3_8", Catalog.get_good("g_001"), 20, summary)
	# Drive arrivals for a few turns; a deferred sale should eventually credit.
	for _i in range(25):
		Production._process_transport_arrivals(summary)
		if MatchState.money > 0.0:
			break
	_check(MatchState.money > 0.0, "a market-routed output sale credits revenue (money=%.2f)" % MatchState.money)
	_check(summary.goods_sales_revenue > 0.0, "the sale appears in goods_sales_revenue")

func _test_tax_dividend_caps() -> void:
	MatchState.reset()
	MatchState.money = 1000.0
	var loss_summary := {
		"money_in": 235.0,
		"money_out": 239.0,
		"taxes_paid": 0.0,
		"dividends_paid": 0.0,
	}
	var money_before := MatchState.money
	var loss_pretax: float = Production._apply_tax_and_dividends(loss_summary)
	_check(loss_pretax < 0.0
		and float(loss_summary.get("taxes_paid", -1.0)) == 0.0
		and float(loss_summary.get("dividends_paid", -1.0)) == 0.0
		and is_equal_approx(MatchState.money, money_before),
		"loss-making turns do not pay tax or dividends")

	var profit_summary := {
		"money_in": 100.0,
		"money_out": 90.0,
		"taxes_paid": 0.0,
		"dividends_paid": 0.0,
	}
	Production._apply_tax_and_dividends(profit_summary)
	_check(is_equal_approx(float(profit_summary.get("taxes_paid", 0.0)), 2.0)
		and is_equal_approx(float(profit_summary.get("dividends_paid", 0.0)), 1.6)
		and is_equal_approx(float(profit_summary.get("money_in", 0.0)) - float(profit_summary.get("money_out", 0.0)), 6.4),
		"tax is capped to profit and dividends are calculated after tax")

func _test_output_conservation() -> void:
	# Default (STOCKPILE_ALL): a building's output should land in its own tile's stockpile.
	MatchState.reset()
	Stockpile.clear_all()
	var building := {"instance_id": "inst_conserve", "building_id": "b_001", "tile_id": "tile_3_3", "recipe_id": "r_001"}
	var good: Dictionary = Catalog.get_good("g_001")
	var summary := {"transport_paid": 0.0, "money_out": 0.0, "goods_purchased_cost": 0.0}
	var before: int = Stockpile.get_total("g_001")
	Production._dispatch_output_to_stockpile(building, good, 20, summary)
	Production._flush_output_buffer()
	var gained: int = Stockpile.get_total("g_001") - before
	_check(gained == 20, "output is conserved into the tile stockpile (got %d of 20)" % gained)

func _test_transfer_helpers() -> void:
	MatchState.reset()
	MatchState.add_building("b_001", "r_001", "tile_5_5", "player_1")  # coal mine → produces g_001
	MatchState.add_building("b_002", "r_005", "tile_6_6", "player_1")  # iron furnace → consumes g_002
	_check(MatchState.tiles_producing("g_001").has("tile_5_5"), "tiles_producing finds a producer tile")
	_check(not MatchState.tiles_producing("g_001").has("tile_6_6"), "tiles_producing excludes a non-producer")
	_check(MatchState.tiles_consuming("g_002").has("tile_6_6"), "tiles_consuming finds a consumer tile")

func _test_recipes_producing() -> void:
	_check(Catalog.recipes_producing("g_001").size() > 0, "recipes_producing finds producers of coal")
	_check(Catalog.recipes_producing("g_nope").is_empty(), "recipes_producing is empty for an unknown good")
	_check(Catalog.recipe_produces(Catalog.get_recipe("r_001"), "g_001"),
		"recipe_produces detects a recipe's output good")

func _test_purchases() -> void:
	_check(Catalog.buyable_goods().size() > 0 and Catalog.sellable_goods().size() > 0,
		"Catalog exposes buyable + sellable good lists")
	_check(Catalog.is_good_buyable("g_001"), "coal is buyable")
	var before: int = MatchState.get_recurring_transaction_rows().size()
	MatchState.add_recurring_buy("tile_3_8", "g_001", 25)
	var rows: Array = MatchState.get_recurring_transaction_rows()
	_check(rows.size() == before + 1, "recurring buy registers in the dashboard")
	var last: Dictionary = rows[rows.size() - 1]
	_check(str(last.get("type", "")) == "Buy" and int(last.get("qty", 0)) == 25,
		"recurring buy shows as a Buy row")
	var m: float = MatchState.money
	var prev: Dictionary = MatchState.preview_buy("tile_3_8", "g_001", 10)
	_check(not prev.is_empty() and float(prev.get("cost", 0)) > 0.0 and MatchState.money == m,
		"preview_buy returns a cost without spending")

func _test_market_buy() -> void:
	_check(not MatchState.is_input_tile_only("inst_x", "g_002"), "inputs default to stockpile-then-market")
	MatchState.set_input_tile_only("inst_x", "g_002", true)
	_check(MatchState.is_input_tile_only("inst_x", "g_002"), "input can be set to tile-stockpile-only")
	MatchState.set_input_tile_only("inst_x", "g_002", false)
	_check(not MatchState.is_input_tile_only("inst_x", "g_002"), "input resets to stockpile-then-market")
	MatchState.money = 100000.0
	var t_before: int = MatchState.get_oneoff_transaction_rows().size()
	var ship_before: int = MatchState.get_pending_transport_shipments().size()
	var money_before: float = MatchState.money
	var result: Dictionary = MatchState.queue_buy("tile_3_8", "g_002", 10)
	_check(not result.is_empty(), "queue_buy returns a summary")
	_check(absf(float(result.get("goods_cost", 0)) + float(result.get("transport_cost", 0)) - float(result.get("cost", 0))) < 0.01,
		"queue_buy splits cost into goods + transport")
	_check(MatchState.money < money_before, "queue_buy pays for goods + transport")
	_check(MatchState.get_pending_transport_shipments().size() > ship_before, "queue_buy queues an inbound shipment")
	var rows: Array = MatchState.get_oneoff_transaction_rows()
	_check(rows.size() == t_before + 1 and str(rows[rows.size() - 1].get("type", "")) == "Buy",
		"a buy is logged with type Buy")
	# Best-effort: a big order with little cash buys a partial amount, not nothing.
	MatchState.money = 50.0
	var partial: Dictionary = MatchState.queue_buy("tile_3_8", "g_002", 1000)
	_check(not partial.is_empty() and int(partial.get("qty", 0)) > 0 and int(partial.get("qty", 0)) < 1000,
		"queue_buy buys a partial amount when cash is short")

func _test_auto_sell_goods() -> void:
	var t := "tile_4_4"
	MatchState.enable_auto_sell_good(t, "g_001")
	_check(MatchState.is_auto_sell_good(t, "g_001"), "per-good auto-sell registers")
	_check(MatchState.should_auto_sell_good(t, "g_001"), "should_auto_sell true for an armed good")
	_check(not MatchState.should_auto_sell_good(t, "g_002"), "should_auto_sell false for an unarmed good")
	_check(MatchState.get_auto_sell_tiles().has(t), "tile appears in the auto-sell tile set")
	# Master order covers every good regardless of per-good arming.
	MatchState.enable_sell_surplus(t)
	_check(MatchState.should_auto_sell_good(t, "g_009"), "master 'sell all' order auto-sells any good")
	MatchState.disable_sell_surplus(t)
	# Disarming the last per-good order removes the tile from the set.
	MatchState.disable_auto_sell_good(t, "g_001")
	_check(not MatchState.is_auto_sell_good(t, "g_001"), "per-good auto-sell clears")
	_check(not MatchState.get_auto_sell_tiles().has(t), "tile drops out once no orders remain")

func _test_limestone_concrete() -> void:
	_check(not Catalog.get_good_by_internal_name("limestone").is_empty(), "limestone good exists")
	_check(not Catalog.get_good_by_internal_name("concrete").is_empty(), "concrete good exists")
	var found := false
	for r in Catalog.all_recipes():
		if str(r.get("output_name", "")) == "limestone" and str(r.get("building_id", "")) != "":
			found = true
			var gated := false
			for req in r.get("requirements", []):
				if str(req.get("type", "")) == "deposit" and str(req.get("value", "")) == "limestone":
					gated = true
			_check(gated, "limestone mining is gated on a limestone deposit")
	_check(found, "a mine recipe produces limestone")

func _test_construction() -> void:
	# Pick a building that actually has construction materials (data-driven so it survives
	# CSV changes). requirements_for must resolve the CSV's internal material names to good_ids.
	var bid := ""
	var reqs := {}
	for b in Catalog.all_buildings():
		var r: Dictionary = Construction.requirements_for(str(b.get("id", "")))
		if not r.is_empty():
			bid = str(b.get("id", ""))
			reqs = r
			break
	_check(bid != "" and not reqs.is_empty(), "a building has resolvable construction materials")
	if bid == "":
		return

	var tile := "tile_construction_test"
	for gid in reqs:
		Stockpile.consume(tile, gid, 1 << 30)  # ensure the test tile starts empty

	# Empty tile: gate blocks, every required good reported short.
	var chk0: Dictionary = Construction.check_tile(tile, bid)
	_check(not bool(chk0.get("satisfied", false)), "missing materials -> not satisfied")
	_check(chk0.get("missing", {}).size() == reqs.size(), "all required goods reported missing")

	# Stock exactly the requirements -> gate clears.
	for gid in reqs:
		Stockpile.add(tile, gid, int(reqs[gid]))
	_check(bool(Construction.check_tile(tile, bid).get("satisfied", false)),
		"materials present -> satisfied")

	# start_on_tile consumes the materials and starts an under_construction project — the
	# building is NOT live yet; it promotes only after build_duration ticks.
	var before: int = MatchState.buildings.size()
	var iid: String = Construction.start_on_tile(bid, "", tile)
	var consumed_ok := true
	for gid in reqs:
		if Stockpile.get_at_tile(tile, gid) != 0:
			consumed_ok = false
	_check(consumed_ok, "start_on_tile consumes the construction materials")
	var duration: int = int(Catalog.get_building(bid).get("build_duration", 0))
	_check(duration >= 1, "building has a positive build_duration")
	_check(not MatchState.buildings.has(iid) and Construction.construction_projects.has(iid),
		"start_on_tile creates an under_construction project, not a live building")
	_check(int(Construction.construction_projects[iid].get("turns_remaining", -1)) == duration,
		"project counts down from build_duration")
	_check(Construction.reserved_space_on_tile(tile) > 0.0, "project reserves tile space")

	# Tick out the countdown; the building promotes on the final tick, keeping the same id.
	for _i in range(duration):
		Construction.tick_turn()
	_check(MatchState.buildings.has(iid) and not Construction.construction_projects.has(iid),
		"project promotes to a live building after build_duration turns")
	_check(MatchState.buildings.size() == before + 1, "exactly one building added on promotion")
	_check(Construction.reserved_space_on_tile(tile) == 0.0, "reserved space frees on promotion")

	# Cleanup so later assertions over MatchState.buildings aren't polluted.
	MatchState.remove_building(iid)

	# Dialog smoke test: instantiates + builds its UI without error.
	var dlg: Node = load("res://scripts/construction_missing_dialog.gd").new()
	add_child(dlg)
	dlg.call("open", bid, "", tile, reqs)
	_check(dlg.visible and dlg.get_child_count() > 0, "missing-materials dialog builds + opens")
	dlg.queue_free()

func _test_construction_cancel() -> void:
	var bid := ""
	var reqs := {}
	for b in Catalog.all_buildings():
		var r: Dictionary = Construction.requirements_for(str(b.get("id", "")))
		if not r.is_empty():
			bid = str(b.get("id", ""))
			reqs = r
			break
	if bid == "":
		return
	var first := str(reqs.keys()[0])

	# --- Cancel an under_construction build: full refund, all materials returned, space freed.
	var tile := "tile_cancel_uc"
	for gid in reqs:
		Stockpile.consume(tile, str(gid), 1 << 30)
		Stockpile.add(tile, str(gid), int(reqs[gid]))
	var money_before: float = MatchState.money
	var iid: String = Construction.start_on_tile(bid, "", tile, 80.0)
	_check(Construction.reserved_space_on_tile(tile) > 0.0, "under-construction reserves space before cancel")
	var ok: bool = Construction.cancel(iid)
	_check(ok and not Construction.construction_projects.has(iid), "cancel removes the project")
	_check(absf(MatchState.money - (money_before + 80.0)) < 0.001, "cancel refunds the full build cost")
	_check(Stockpile.get_at_tile(tile, first) == int(reqs[first]), "cancel returns the consumed materials")
	_check(Construction.reserved_space_on_tile(tile) == 0.0, "cancel frees the reserved space")
	for gid in reqs:
		Stockpile.consume(tile, str(gid), 1 << 30)

	# --- Cancel an awaiting build: only SECURED materials return, still-missing ones don't.
	var tile2 := "tile_cancel_aw"
	for gid in reqs:
		Stockpile.consume(tile2, str(gid), 1 << 30)
	var missing2: Dictionary = reqs.duplicate()
	missing2.erase(first)  # pretend the first good was already secured (claimed)
	var iid2: String = MatchState.reserve_instance_id(bid)
	Construction.construction_projects[iid2] = {
		"instance_id": iid2, "building_id": bid, "recipe_id": "", "tile_id": tile2,
		"status": Construction.STATUS_AWAITING_MATERIALS,
		"required_materials": reqs, "missing_materials": missing2,
		"turns_remaining": 2, "construction_duration": 2, "reserved_space": 10.0, "build_cost": 50.0,
	}
	var m2: float = MatchState.money
	Construction.cancel(iid2)
	_check(Stockpile.get_at_tile(tile2, first) == int(reqs[first]), "cancel returns only the secured materials (awaiting)")
	if not missing2.is_empty():
		var miss_gid := str(missing2.keys()[0])
		_check(Stockpile.get_at_tile(tile2, miss_gid) == 0, "still-missing materials are not returned on cancel")
	_check(absf(MatchState.money - (m2 + 50.0)) < 0.001, "cancel refunds the build cost (awaiting)")
	for gid in reqs:
		Stockpile.consume(tile2, str(gid), 1 << 30)

func _test_construction_sourcing() -> void:
	var bid := ""
	var reqs := {}
	for b in Catalog.all_buildings():
		var r: Dictionary = Construction.requirements_for(str(b.get("id", "")))
		if not r.is_empty():
			bid = str(b.get("id", ""))
			reqs = r
			break
	if bid == "":
		return
	# Real tiles so the router resolves source -> dest turns.
	var src := "tile_5_10"
	var dest := "tile_3_8"
	for gid in reqs:
		Stockpile.consume(src, str(gid), 1 << 30)
		Stockpile.consume(dest, str(gid), 1 << 30)
		Stockpile.add(src, str(gid), int(reqs[gid]) * 3)  # comfortable spare surplus

	var found: Dictionary = Construction.find_source_tile(dest, reqs)
	_check(not found.is_empty(), "find_source_tile finds a tile with spare stock")
	if not found.is_empty():
		var s := str(found.get("tile_id", ""))
		var committed: Dictionary = Production.compute_committed_for_tile(s)
		var covers := true
		for gid in reqs:
			if Stockpile.get_at_tile(s, str(gid)) - int(committed.get(gid, 0)) < int(reqs[gid]):
				covers = false
		_check(covers, "the chosen source tile actually covers the requirement")

	var first_gid := str(reqs.keys()[0])
	var src_before: int = Stockpile.get_at_tile(src, first_gid)
	var iid: String = Construction.start_awaiting_from_tile(bid, "", dest, src)
	_check(Construction.construction_projects.has(iid)
		and str(Construction.construction_projects[iid].get("status", "")) == Construction.STATUS_AWAITING_MATERIALS,
		"start_awaiting_from_tile creates an awaiting project")
	_check(Stockpile.get_at_tile(src, first_gid) == src_before - int(reqs[first_gid]),
		"sourcing consumes the shortfall from the source tile")

	# Deliver to the build site and claim -> construction begins.
	for gid in reqs:
		Stockpile.add(dest, str(gid), int(reqs[gid]))
	Construction.claim_materials()
	_check(str(Construction.construction_projects.get(iid, {}).get("status", "")) == Construction.STATUS_UNDER_CONSTRUCTION,
		"sourced project begins construction once delivered")

	Construction.construction_projects.erase(iid)
	for gid in reqs:
		Stockpile.consume(src, str(gid), 1 << 30)
		Stockpile.consume(dest, str(gid), 1 << 30)

func _test_construction_detail_panel() -> void:
	var bid := ""
	var reqs := {}
	for b in Catalog.all_buildings():
		var r: Dictionary = Construction.requirements_for(str(b.get("id", "")))
		if not r.is_empty():
			bid = str(b.get("id", ""))
			reqs = r
			break
	if bid == "":
		return
	var tile := "tile_detail_test"
	for gid in reqs:
		Stockpile.consume(tile, gid, 1 << 30)
		Stockpile.add(tile, gid, int(reqs[gid]))
	var iid: String = Construction.start_on_tile(bid, "", tile)  # under_construction project

	# The detail panel lives inside main.tscn (no standalone scene), so instantiate and find it.
	var packed: PackedScene = load("res://scenes/main.tscn")
	var ok: bool = packed != null and Construction.construction_projects.has(iid)
	if ok:
		var inst: Node = packed.instantiate()
		add_child(inst)
		await get_tree().process_frame
		var panel: Node = inst.find_child("BuildingDetailPanel", true, false)
		ok = panel != null
		if ok:
			panel.call("show_building", {
				"instance_id": iid, "building_id": bid, "recipe_id": "",
				"tile_id": tile, "owner": MatchState.LOCAL_PLAYER,
				"construction_status": "under_construction",
			})
			var fv: Node = panel.get("fields_vbox")
			_check(fv != null and fv.get_child_count() > 0, "construction detail panel renders the materials section")
			# Regression guards: the close (X) button lives in the status rail and must stay,
			# while Change Recipe is hidden during construction.
			var close_button := panel.get("close_button") as Button
			_check(close_button != null and close_button.visible and close_button.is_inside_tree(),
				"construction panel keeps the close (X) button")
			_check(not panel.get("change_recipe_button").visible, "construction panel hides Change Recipe")
			# Switching to a running building restores the operational controls.
			var rid: String = MatchState.add_building(bid, "", "tile_detail_running")
			panel.call("show_building", MatchState.get_building(rid))
			_check(panel.get("change_recipe_button").visible, "Change Recipe restored on a running building")
			MatchState.remove_building(rid)
			ok = true
		inst.queue_free()
		await get_tree().process_frame
	if not ok:
		_check(false, "construction detail panel instantiates")
	Construction.construction_projects.erase(iid)

func _test_construction_awaiting() -> void:
	var bid := ""
	var reqs := {}
	for b in Catalog.all_buildings():
		var r: Dictionary = Construction.requirements_for(str(b.get("id", "")))
		if not r.is_empty():
			bid = str(b.get("id", ""))
			reqs = r
			break
	if bid == "":
		return

	var tile := "tile_awaiting_test"
	for gid in reqs:
		Stockpile.consume(tile, gid, 1 << 30)
	# Stock all materials up front so start_awaiting_market orders nothing from the market
	# (keeps the test port-independent); claim_materials then secures them in place.
	for gid in reqs:
		Stockpile.add(tile, gid, int(reqs[gid]))

	var iid: String = Construction.start_awaiting_market(bid, "", tile)
	_check(Construction.construction_projects.has(iid)
		and str(Construction.construction_projects[iid].get("status", "")) == Construction.STATUS_AWAITING_MATERIALS,
		"start_awaiting_market creates an awaiting_materials project")
	_check(not MatchState.buildings.has(iid), "awaiting project is not a live building")
	_check(Construction.reserved_space_on_tile(tile) > 0.0, "awaiting project reserves tile space")

	# The priority claim secures the on-tile materials and starts the build countdown.
	Construction.claim_materials()
	var consumed_ok := true
	for gid in reqs:
		if Stockpile.get_at_tile(tile, gid) != 0:
			consumed_ok = false
	_check(consumed_ok, "claim_materials consumes the secured materials")
	_check(Construction.construction_projects.has(iid)
		and str(Construction.construction_projects[iid].get("status", "")) == Construction.STATUS_UNDER_CONSTRUCTION,
		"awaiting project begins construction once materials are secured")

	# Countdown then completes the build with the same id.
	var duration: int = int(Catalog.get_building(bid).get("build_duration", 0))
	for _i in range(duration):
		Construction.tick_turn()
	_check(MatchState.buildings.has(iid) and not Construction.construction_projects.has(iid),
		"awaiting project promotes after securing materials + countdown")
	MatchState.remove_building(iid)

func _test_buy_price() -> void:
	var gid := "g_001"
	var sell := MarketState.get_price(gid)
	var buy := MarketState.get_buy_price(gid)
	_check(absf(buy - sell * (1.0 + EconomyConfig.MARKET_BUY_MARKUP)) < 0.0001,
		"buy price is the sale price plus the market markup")
	_check(buy > sell, "buying costs more than selling (spread)")
	# preview_buy should value goods at the buy price.
	var prev: Dictionary = MatchState.preview_buy("tile_3_8", gid, 10)
	if not prev.is_empty():
		_check(absf(float(prev.get("goods_cost", 0.0)) - 10.0 * buy) < 0.01,
			"preview_buy values goods at the buy price")

func _test_price_impact() -> void:
	var g: int = EconomyConfig.GLUT_UNITS
	_check(EconomyConfig.price_impact_pct_for(g) == 0, "selling up to the glut has no price impact")
	_check(EconomyConfig.price_impact_pct_for(g + 1) == 1, "just over the glut is 1% impact")
	_check(EconomyConfig.price_impact_pct_for(2 * g) == 1, "twice the glut is still 1%")
	_check(EconomyConfig.price_impact_pct_for(2 * g + 1) == 2, "past 2x glut is 2%")
	_check(EconomyConfig.price_impact_pct_for(1000 * g) == EconomyConfig.MAX_PRICE_IMPACT_PCT, "impact caps at the max")
	_check(EconomyConfig.units_cap_for_impact(0) == g, "no-impact cap is the glut")
	_check(EconomyConfig.units_cap_for_impact(1) == 2 * g, "1% cap is twice the glut")
	MatchState.set_auto_sell_impact("tile_4_5", 0)
	_check(MatchState.auto_sell_unit_cap("tile_4_5") == g, "tile NONE tolerance caps at the glut")
	MatchState.set_auto_sell_impact("tile_4_5", 1)
	_check(MatchState.auto_sell_unit_cap("tile_4_5") == 2 * g, "tile 1% tolerance caps at 2x glut")
	MatchState.set_auto_sell_impact("tile_4_5", MatchState.IMPACT_ANY)
	_check(MatchState.auto_sell_unit_cap("tile_4_5") > 1000000, "tile ANY tolerance is effectively uncapped")
	_check(MatchState.get_auto_sell_impact("tile_unset_99") == MatchState.IMPACT_ANY, "default tolerance is ANY")

func _test_owner_costs() -> void:
	_check(MatchState.is_player_owned({"owner": "player_1"}), "player_1 building is player-owned")
	_check(MatchState.is_player_owned({}), "building with no owner defaults to player-owned")
	_check(not MatchState.is_player_owned({"owner": "Three Diamonds Shipping Corporation"}),
		"NPC-owned building is not player-owned (not charged maintenance)")

func _test_recurring_sell_multitile() -> void:
	# A recurring sell bound to an empty source tile should still sell the good
	# from another tile that holds it (the fix for "sold once then stopped").
	var src := "tile_3_8"
	var other := "tile_9_5"
	var have: int = Stockpile.get_at_tile(src, "g_001")
	if have > 0:
		Stockpile.consume(src, "g_001", have)
	Stockpile.add(other, "g_001", 25)
	var before: int = Stockpile.get_at_tile(other, "g_001")
	MatchState.add_recurring_sell(src, {"g_001": 10})
	MatchState.run_recurring_and_scheduled_moves()
	var sold: int = before - Stockpile.get_at_tile(other, "g_001")
	_check(sold == 10, "recurring sell draws from another tile when source is empty (sold %d)" % sold)
	if not MatchState.recurring_sells.is_empty():
		MatchState.recurring_sells.pop_back()

func _test_transaction_ledger() -> void:
	Stockpile.add("tile_3_8", "g_001", 12)
	MatchState.queue_sell("tile_3_8", {"g_001": 12})  # one-off → logged
	var rows: Array = MatchState.get_oneoff_transaction_rows()
	_check(rows.size() > 0, "one-off sell appears in the transaction ledger")
	var last: Dictionary = rows[rows.size() - 1]
	_check(str(last.get("type", "")) == "Sell" and int(last.get("qty", 0)) == 12,
		"ledger row carries type=Sell and qty")
	MatchState.add_recurring_move("tile_3_8", "tile_3_9", {"g_001": 5})
	_check(MatchState.get_recurring_move_rows().size() > 0, "recurring move appears in the movements ledger")
	# A recurring execution must NOT also be logged as a one-off.
	var before: int = MatchState.get_oneoff_move_rows().size()
	MatchState.run_recurring_and_scheduled_moves()
	_check(MatchState.get_oneoff_move_rows().size() == before, "recurring executions are not double-logged as one-offs")
	# Production-driven sales/moves must show up too (the bulk of real activity).
	var t_before: int = MatchState.get_oneoff_transaction_rows().size()
	MatchState.log_market_sale("tile_6_8", "tile_5_10", "g_001", 20, 2)
	_check(MatchState.get_oneoff_transaction_rows().size() == t_before + 1,
		"a production market sale is logged to the transaction ledger")

func _test_output_market_route() -> void:
	var mode_before: int = MatchState.sell_mode
	MatchState.route_output_to_market("inst_test_market", "g_001")
	_check(MatchState.is_output_market("inst_test_market", "g_001"),
		"route_output_to_market marks the building for market")
	_check(MatchState.get_output_stockpile_destination("inst_test_market", "g_001") == "",
		"a market route reads as no stockpile tile")
	_check(MatchState.sell_mode == mode_before,
		"per-building market route leaves the global sell mode unchanged")

func _test_bulk_sell() -> void:
	Stockpile.add("tile_3_8", "g_001", 30)
	var result: Dictionary = MatchState.sell_all_to_market({"good_id": "", "finished_only": false, "per_tile_keep": 10})
	_check(int(result.get("total_qty", 0)) >= 20, "sell_all_to_market sells the surplus above per-tile keep")
	_check(Stockpile.get_at_tile("tile_3_8", "g_001") == 10, "bulk sell leaves the kept amount on the tile")

func _test_npc_ports() -> void:
	# The main scene's _ready places the 4 NPC ports; verify one landed + is NPC-owned.
	var found_npc_port := false
	for iid in MatchState.tile_buildings.get("tile_5_10", []):
		var inst: Dictionary = MatchState.get_building(iid)
		if str(inst.get("building_id", "")) == "b_004" and str(inst.get("owner", "")) == "Three Diamonds Shipping Corporation":
			found_npc_port = true
	_check(found_npc_port, "NPC port placed on a port tile (b_004, Three Diamonds)")
	_check(Stockpile.get_capacity("tile_5_10") >= Stockpile.TILE_CAPACITY + 500,
		"port tile capacity raised by the port's storage_boost")

func _test_queue_sell() -> void:
	Stockpile.add("tile_3_8", "g_001", 8)
	var before: int = MatchState.get_pending_transport_shipments().size()
	var summary: Dictionary = MatchState.queue_sell("tile_3_8", {"g_001": 8})
	_check(not summary.is_empty(), "queue_sell returns a summary")
	_check(Stockpile.get_at_tile("tile_3_8", "g_001") == 0, "queue_sell consumes from source")
	_check(str(summary.get("port", "")) != "" and MatchState.get_pending_transport_shipments().size() > before,
		"queue_sell ships to a port")

# MarketState.execute_sale is the unified low-level sell primitive. The three tests
# below pin the three axes the option dict toggles, so any drift in queue_sell's or
# Production's wrapper is caught by something tighter than the E2E suite.

func _test_market_execute_sale() -> void:
	# Default behaviour: consume from the tile, log to ledger, defer revenue until
	# the shipment lands at the port. Mirrors the queue_sell path.
	Stockpile.add("tile_3_8", "g_001", 12)
	var ships_before := MatchState.get_pending_transport_shipments().size()
	var txn_before := MatchState.get_oneoff_transaction_rows().size()
	var result: Dictionary = MarketState.execute_sale("tile_3_8", {"g_001": 12})
	_check(not result.is_empty(), "execute_sale returns a result")
	_check(Stockpile.get_at_tile("tile_3_8", "g_001") == 0, "execute_sale consumes from the tile")
	_check(bool(result.get("deferred", false)) and MatchState.get_pending_transport_shipments().size() > ships_before,
		"execute_sale queues a shipment (deferred sale)")
	_check(MatchState.get_oneoff_transaction_rows().size() > txn_before,
		"execute_sale logs a transaction row by default")
	_check(float(result.get("transport_cost", -1.0)) == 0.0,
		"execute_sale: transport not paid from seller unless requested")

func _test_market_execute_sale_skip_consume() -> void:
	# skip_consume: the goods are already in the caller's hand (production output);
	# the stockpile is not touched.
	var tile := "tile_3_8"
	Stockpile.consume(tile, "g_001", 1 << 30)  # drain
	var before: int = Stockpile.get_at_tile(tile, "g_001")
	var result: Dictionary = MarketState.execute_sale(tile, {"g_001": 5},
		{"skip_consume": true, "log_oneoff": false})
	_check(not result.is_empty(), "execute_sale(skip_consume) sells without stockpile")
	_check(Stockpile.get_at_tile(tile, "g_001") == before,
		"execute_sale(skip_consume) does not touch the stockpile")
	_check(int(result.get("total_qty", 0)) == 5,
		"execute_sale(skip_consume) sells the full requested quantity")

func _test_market_execute_sale_pay_transport() -> void:
	# pay_transport_from_seller: the seller eats the freight cost upfront. This is
	# the difference between Production's output-routed sales and the gross manual
	# sells from queue_sell.
	var tile := "tile_3_8"
	Stockpile.add(tile, "g_001", 20)
	var money_before: float = MatchState.money
	var result: Dictionary = MarketState.execute_sale(tile, {"g_001": 20},
		{"pay_transport_from_seller": true, "log_oneoff": false})
	_check(not result.is_empty(), "execute_sale(pay_transport) returns a result")
	var paid: float = float(result.get("transport_cost", 0.0))
	_check(paid > 0.0, "execute_sale(pay_transport) charges a non-zero transport cost")
	_check(absf((money_before - paid) - MatchState.money) < 0.01,
		"execute_sale(pay_transport) deducts transport upfront (paid=%.4f, Δmoney=%.4f)"
			% [paid, money_before - MatchState.money])

func _test_move_extras() -> void:
	var preview: Dictionary = MatchState.preview_move("tile_12_4", "tile_12_2", {"g_001": 5})
	_check(preview.has("turns") and preview.has("cost") and preview.has("per_turn"),
		"preview_move returns route info (turns/cost/per_turn)")
	MatchState.run_recurring_and_scheduled_moves()  # empty queues — must not crash
	_check(true, "run_recurring_and_scheduled_moves runs without error")

func _test_queue_move() -> void:
	Stockpile.add("tile_12_4", "g_001", 10)
	var before_pending: int = MatchState.get_pending_transport_shipments().size()
	var summary: Dictionary = MatchState.queue_move("tile_12_4", "tile_12_2", {"g_001": 10})
	_check(not summary.is_empty(), "queue_move returns a summary")
	_check(Stockpile.get_at_tile("tile_12_4", "g_001") == 0, "queue_move consumes from source")
	_check(MatchState.get_pending_transport_shipments().size() > before_pending, "queue_move queues a shipment")

func _test_debug_terminal() -> void:
	var term: Node = load("res://scripts/debug_terminal.gd").new()
	add_child(term)
	await get_tree().process_frame
	var before: float = MatchState.money
	var result: String = term._run_command("cash 250")
	_check(absf(MatchState.money - (before + 250.0)) < 0.001, "terminal: cash adds the amount")
	_check("250" in result, "terminal: cash reports the amount")
	_check(term._run_command("bogus").begins_with("unknown"), "terminal: unknown command handled")
	term.queue_free()

func _test_building_ledger() -> void:
	_check(MatchState.route_objective == MatchState.RouteObjective.FASTEST,
		"route objective defaults to FASTEST")
	var scene := load("res://scenes/building_ledger_panel.tscn")
	var ok := false
	if scene != null:
		var panel: Node = scene.instantiate()
		add_child(panel)
		await get_tree().process_frame
		ok = panel.get_child_count() > 0
		panel.queue_free()
	_check(ok, "building_ledger_panel instantiates (routing dropdown builds)")

func _test_ports() -> void:
	var ports := Catalog.all_ports()
	_check(ports.size() == 4, "Catalog loads 4 ports")
	var fields_ok := true
	for p in ports:
		if str(p.get("tile_id", "")) == "" or str(p.get("name", "")) == "":
			fields_ok = false
	_check(fields_ok, "every port has a tile_id and name")
	_check(Catalog.tile_hex_distance("tile_5_10", "tile_5_10") == 0, "tile_hex_distance(self) == 0")
	_check(Catalog.nearest_port_tile("tile_3_8") == "tile_5_10", "nearest_port_tile picks the closest port")
	_check(Catalog.tile_label("tile_12_2") == "Miney McMineface - (12_2)", "tile_label uses nickname")
	_check(Catalog.tile_label("tile_5_10") == "Stoneshore Docks - (5_10)", "tile_label falls back to city_name")
	_check(Catalog.infra_range("roads") == 2, "roads range is 2 tiles/turn")
	_check(Catalog.infra_range("rail") == 4, "rail range is 4 tiles/turn")
	_check(Catalog.all_infrastructure().size() == 5, "Catalog loads 5 infrastructure types")
	_check(Catalog.tile_neighbours("tile_12_2").size() == 6, "interior tile has 6 hex neighbours")
	_check(int(TransportService.route("tile_12_2", "tile_12_2").get("turns", -1)) == 0, "route same-tile = 0 turns")
	_check(int(TransportService.route("tile_12_2", "tile_13_2").get("turns", -1)) == 1, "route to adjacent tile = 1 turn")

func _test_transport_service() -> void:
	var route: Dictionary = TransportService.route("tile_12_2", "tile_13_2", "g_001")
	_check(int(route.get("turns", -1)) == 1, "TransportService routes adjacent tiles")
	var quote: Dictionary = TransportService.quote_manifest("tile_12_2", "tile_13_2", {"g_001": 10})
	_check(int(quote.get("turns", -1)) == 1 and float(quote.get("cost", 0.0)) > 0.0,
		"TransportService quotes a manifest with turns and cost")
	var buy_quote: Dictionary = TransportService.quote_market_buy("tile_3_8", "g_001", 10, false)
	_check(str(buy_quote.get("port", "")) == "tile_5_10"
		and absf(float(buy_quote.get("cost", 0.0)) - (float(buy_quote.get("goods_cost", 0.0)) + float(buy_quote.get("transport_cost", 0.0)))) < 0.01,
		"TransportService quotes a market buy through the nearest port")
	var covered_buy: Dictionary = TransportService.quote_market_buy("tile_3_8", "g_001", 10, true)
	_check(int(covered_buy.get("turns", 0)) == 1 and float(covered_buy.get("transport_cost", -1.0)) == 0.0,
		"TransportService applies covered seaport buy quotes")
	var covered_sell: Dictionary = TransportService.quote_market_sell("tile_3_8", {"g_001": 10}, {"g_001": true})
	_check(int(covered_sell.get("turns", 0)) == 1 and float(covered_sell.get("transport_cost", -1.0)) == 0.0,
		"TransportService applies covered seaport sell quotes")

func _test_transport_boundaries() -> void:
	var offenders: Array[String] = []
	var files: Array[String] = []
	_collect_gd_files("res://scripts", files)
	for path in files:
		if path.ends_with("/transport_service.gd"):
			continue
		var text := FileAccess.get_file_as_string(path)
		if text.find("Catalog.route(") >= 0:
			offenders.append(path + " uses Catalog.route")
		if text.find("EconomyConfig.transport_") >= 0:
			offenders.append(path + " uses EconomyConfig.transport_*")
	_check(offenders.is_empty(),
		"gameplay transport route/cost callers go through TransportService" + (": " + ", ".join(offenders) if not offenders.is_empty() else ""))

func _collect_gd_files(path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not name.begins_with("."):
			var child := path.path_join(name)
			if dir.current_is_dir():
				_collect_gd_files(child, out)
			elif name.ends_with(".gd"):
				out.append(child)
		name = dir.get_next()
	dir.list_dir_end()

func _test_build_mode_overlay_survey_visibility() -> void:
	var saved_surveyed := MatchState.surveyed_tiles.duplicate(true)
	var saved_partial := MatchState.partially_surveyed_tiles.duplicate(true)
	MatchState.surveyed_tiles.clear()
	MatchState.partially_surveyed_tiles.clear()
	var overlay: Node = load("res://scripts/map_overlay.gd").new()
	var recipe: Dictionary = Catalog.get_recipe("r_001")
	var input_names: Array[String] = []
	for input_name in overlay.call("_recipe_input_internal_names", recipe):
		input_names.append(str(input_name))
	var reqs: Array = recipe.get("requirements", [])
	var coal_tile := {"id": "tile_test_construct_coal", "type": "hill", "deposits": ["coal(1000)"]}
	_check(str(overlay.call("_build_overlay_state", coal_tile, reqs, input_names)) == "none",
		"build overlay hides unsurveyed viable tiles")
	MatchState.mark_tile_partial("tile_test_construct_coal")
	_check(str(overlay.call("_build_overlay_state", coal_tile, reqs, input_names)) == "recommended",
		"build overlay can recommend partially surveyed matching tiles")
	_replace_dict(MatchState.surveyed_tiles, saved_surveyed)
	_replace_dict(MatchState.partially_surveyed_tiles, saved_partial)
	overlay.free()

func _test_direct_build_skips_build_overlay() -> void:
	var saved_active := BuildMode.is_active
	var saved_kind := BuildMode.kind
	var saved_building := BuildMode.current_building_id
	var saved_recipe := BuildMode.current_recipe_id
	var saved_infra := BuildMode.current_infrastructure_type
	var saved_last_attempt := BuildMode._last_attempt_ms
	BuildMode.exit_build_mode()
	BuildMode._last_attempt_ms = -100000
	var observed := {"entered": false, "attempted": false, "recipe_seen": ""}
	var on_entered := func(_building_id: String, _recipe_id: String) -> void:
		observed["entered"] = true
	var on_attempted := func(_building_id: String, _tile_id: String) -> void:
		observed["attempted"] = true
		observed["recipe_seen"] = BuildMode.current_recipe_id
	BuildMode.mode_entered.connect(on_entered)
	BuildMode.build_attempted.connect(on_attempted)
	BuildMode.attempt_direct_build("b_001", "r_001", "tile_test_direct_build")
	_check(bool(observed.get("attempted", false)) and str(observed.get("recipe_seen", "")) == "r_001",
		"direct build emits with recipe context")
	_check(not bool(observed.get("entered", false)) and not BuildMode.is_active,
		"direct build does not enter overlay mode")
	BuildMode.mode_entered.disconnect(on_entered)
	BuildMode.build_attempted.disconnect(on_attempted)
	BuildMode.is_active = saved_active
	BuildMode.kind = saved_kind
	BuildMode.current_building_id = saved_building
	BuildMode.current_recipe_id = saved_recipe
	BuildMode.current_infrastructure_type = saved_infra
	BuildMode._last_attempt_ms = saved_last_attempt

# Smoke: every script we touch must still parse. load() returns null on a parse
# error — this is the check that catches the bug class we couldn't verify by hand.
func _test_scripts_parse() -> void:
	for path in [
		"res://scripts/stockpile_view.gd",
		"res://scripts/infra_grid.gd",
		"res://scripts/tile_info_panel_v2.gd",
		"res://scripts/building_detail_panel.gd",
		"res://scripts/world_map.gd",
		"res://scripts/map_overlay.gd",
		"res://scripts/build_mode_hex_overlay.gd",
		"res://scripts/build_mode_backdrop.gd",
		"res://scripts/power_hex_overlay.gd",
		"res://scripts/water_overlay.gd",
		"res://scripts/hex_map.gd",
		"res://scripts/ds.gd",
		"res://scripts/search_overlay.gd",
		"res://scripts/good_icons.gd",
		"res://scripts/catalog.gd",
		"res://scripts/construct_panel.gd",
		"res://scripts/build_mode.gd",
		"res://scripts/building_row.gd",
		"res://scripts/recipe_row.gd",
		"res://scripts/logistics_overlay.gd",
		"res://scripts/mapmodes_panel.gd",
		"res://scripts/overlay_legend.gd",
		"res://scripts/debug_terminal.gd",
		"res://scripts/sale_effects.gd",
		"res://scripts/ui_helpers.gd",
		"res://scripts/market_panel.gd",
		"res://scripts/turn_summary.gd",
		"res://scripts/construction.gd",
		"res://scripts/construction_missing_dialog.gd",
		"res://scripts/transport_service.gd",
	]:
		_check(load(path) != null, "parses: " + path)

# Smoke: the extracted widgets instantiate and build their UI.
func _test_widgets_instantiate() -> void:
	var sv: Node = load("res://scripts/stockpile_view.gd").new()
	add_child(sv)
	sv.set_tile("")
	_check(sv.get_child_count() > 0, "StockpileView builds its UI")
	sv.queue_free()

	var ig: Node = load("res://scripts/infra_grid.gd").new()
	add_child(ig)
	ig.set_slots([{
		"cell_size": Vector2(80, 80), "icon": null, "state": "add",
		"internal_name": "roads", "button_tooltip": "Add Roads",
		"display_label": "Roads", "label_tooltip": "", "max_label_lines": 2,
	}])
	_check(ig.get_child_count() == 1, "InfraGrid renders one slot")
	ig.queue_free()

# Regression: recipe_row.tscn must instantiate + setup (catches script/root type
# mismatches — recipe rows are only built on expand, so the main-scene test misses them).
func _test_recipe_row_instantiates() -> void:
	var packed: PackedScene = load("res://scenes/recipe_row.tscn")
	var ok: bool = packed != null
	if ok:
		var row: Node = packed.instantiate()
		add_child(row)
		row.call("setup", {
			"recipe_id": "r_001", "display_name": "Test Recipe",
			"output_good_id": "g_001", "output_name": "coal", "output_qty": 10,
			"inputs": [], "energy_req": 4,
		}, "b_001")
		ok = row.get_node_or_null("Row/OutputIcon") != null
		row.queue_free()
	_check(ok, "recipe_row instantiates + setup runs")

# Regression: a stockpile legend row's label must render with non-zero width
# (a fixed-width label was removed; with ellipsis trimming the label collapsed
# to zero and only the colour swatch showed).
func _test_stockpile_legend_label_visible() -> void:
	var sv: Node = load("res://scripts/stockpile_view.gd").new()
	add_child(sv)
	var row: Control = sv.call("_make_row", "Coal", "g_001")
	add_child(row)
	await get_tree().process_frame
	var label := row.get_child(0) as Label
	var ok: bool = label != null and label.text == "Coal" and label.size.x > 0.0
	_check(ok, "stockpile legend label renders with width (not collapsed)")
	row.queue_free()
	sv.queue_free()
	await get_tree().process_frame

# Smoke: the big scene still loads as a resource (catches main.tscn corruption).
func _test_scene_loads() -> void:
	_check(load("res://scenes/main.tscn") != null, "main.tscn loads")

# Instantiate the whole main scene and confirm the tile panel's @onready node
# paths still resolve. This is the net for layout/scene restructuring (Slice D):
# a broken node path leaves an @onready var null, which this catches.
func _test_main_scene_instantiates() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	if packed == null:
		_check(false, "main.tscn instantiates")
		return
	var inst: Node = packed.instantiate()
	add_child(inst)
	await get_tree().process_frame
	var panel: Node = inst.find_child("TileInfoPanel", true, false)
	_check(panel != null and panel.has_method("show_tile"),
		"main.tscn instantiates; the tile panel exists and exposes show_tile")
	# Exactly one tile panel: the classic (v1) panel is gone for good.
	var hud_content: Node = inst.find_child("HUDContent", true, false)
	var panel_count := 0
	if hud_content != null:
		for child in hud_content.get_children():
			if str(child.name).begins_with("TileInfoPanel"):
				panel_count += 1
	_check(panel_count == 1, "exactly one tile panel lives under HUDContent (found %d)" % panel_count)
	# Guards the theme-cascade fix: DS variations must actually resolve on panels.
	var tl = panel.get("_title_label") if panel != null else null
	_check(tl != null and tl.get_theme_font_size("font_size") == DS.FS["H1"],
		"DS theme reaches the tile panel (title uses the DS Title font)")
	# Selecting a tile through the terrain layer's click signal opens the panel.
	var terrain: Node = inst.find_child("TerrainLayer", true, false)
	if panel != null and terrain != null and not terrain.tiles.is_empty():
		var td: Dictionary = terrain.tiles[terrain.tiles.keys()[0]]
		terrain.tile_selected.emit(td)
		await get_tree().process_frame
		_check(panel.visible, "selecting a tile opens the tile panel")
		panel.hide()
	else:
		_check(false, "terrain layer with tiles available for tile-select test")
	inst.queue_free()
	await get_tree().process_frame

# Logic: the data CSVs load into the Catalog as expected.
func _test_catalog_loaded() -> void:
	_check(Catalog.all_goods().size() == 40, "Catalog has 40 goods")
	var _all_classed := true
	for g in Catalog.all_goods():
		if str(g.get("transport_class", "")) == "":
			_all_classed = false
	_check(_all_classed, "every loaded good has a transport_class")
	_check(Catalog.all_recipes().size() >= 18, "Catalog promotes a healthy recipe set (>=18)")
	_check(Catalog.all_buildings().size() == 37, "Catalog has 37 buildings")

# Logic: recipe requirements parse correctly (guards the build-mode path that
# silently broke earlier in the merge).
func _test_recipe_requirements() -> void:
	var recipe: Dictionary = Catalog.get_recipe("r_001")
	var reqs: Array = recipe.get("requirements", [])
	var ok: bool = reqs.size() == 1 \
		and reqs[0].get("type", "") == "deposit" \
		and reqs[0].get("value", "") == "coal"
	_check(ok, "r_001 (Coal Mining) requires deposit:coal")
	_check(recipe.get("recipe_type", "") == "extraction", "r_001 recipe_type is extraction")
	# Promotion gate: every active recipe's inputs + outputs resolve to real goods.
	var no_phantom := true
	for r in Catalog.all_recipes():
		for o in r.get("outputs", []):
			if o.get("good_id", "") == "":
				no_phantom = false
		for inp in r.get("inputs", []):
			if inp.get("good_id", "") == "":
				no_phantom = false
	_check(no_phantom, "promotion gate: active recipes only reference real goods")
	var mine_b: Dictionary = Catalog.get_building("b_001")
	_check("extraction" in mine_b.get("building_type", []), "Mine building_type contains extraction")

# Logic: the regenerated bottom-menu icons import and load as textures.
func _test_menu_icons() -> void:
	var all_ok := true
	for key in ["resources", "buildings", "map_overlays", "markets", "politics", "construct", "tech"]:
		var path := "res://assets/icons/ui_icons/200/%s.png" % key
		if not (ResourceLoader.exists(path) and load(path) is Texture2D):
			all_ok = false
	_check(all_ok, "bottom-menu icons (200px tier) import and load")

func _test_bottom_menu_default() -> void:
	_check(MatchState.use_alt_bottom_menu, "white-rimmed bottom menu is the default")
	var all_ok := true
	for key in ["construct", "goods", "building_ledger", "mapmodes", "market", "politics", "research", "people"]:
		var path := "res://assets/icons/ui_icons/alt/%s.png" % key
		if not (ResourceLoader.exists(path) and load(path) is Texture2D):
			all_ok = false
	_check(all_ok, "white-rimmed bottom-menu icons import and load")
