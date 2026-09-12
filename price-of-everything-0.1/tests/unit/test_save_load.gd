extends "res://tests/test_base.gd"
## Save/load round-trips, migrations, autosave and start configs.

const FEATURE := "save_load"
## Tests that also belong to other features (run under any of their tags).
const TAGS := {
	"_test_recording_toasts": ["decisions", "events", "save_load"],
	"_test_cost_save_isolation": ["finance", "save_load"],
	"_test_save_load_roundtrip": ["finance", "save_load", "special_orders", "stockpile"],
	"_test_start_config_applies_on_scene_ready": ["finance", "save_load", "stockpile"],
	"_test_save_version_migration": ["save_load", "special_orders"],
	"_test_save_load_ui": ["save_load", "ui"],
}

# Both sides of a comparison pass through stringify -> parse -> normalize so 5.0
# (native float) and 5 (JSON-round-tripped int) canonicalise identically.
func _canonical_json(section: Variant) -> String:
	return JSON.stringify(SaveLoad.normalize_jsonish(JSON.parse_string(JSON.stringify(section))))

func _collect_buttons(node: Node, out: Array) -> void:
	if node is Button:
		out.append(node)
	for child in node.get_children():
		_collect_buttons(child, out)

func _test_start_labour_preset() -> void:
	# A start config may ship with a work-effort policy already chosen. metal_magnate (the
	# easy start) opens on 1.2x overtime with its output momentum already at the cap, so it
	# reads as an inherited going concern. See docs/early-game-onboarding-spec.md §5.5.
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/starts/metal_magnate.json"))
	_check(parsed is Dictionary, "metal_magnate start config parses")
	var expanded: Dictionary = SaveLoad.expand_start_config(parsed as Dictionary)
	var match_block: Dictionary = expanded.get("match", {})
	_check(is_equal_approx(float(match_block.get("labour_multiplier", 0.0)), EconomyConfig.LABOUR_MULTIPLIER_MAX)
		and is_equal_approx(float(match_block.get("labour_output_pressure_pct", -1.0)),
			EconomyConfig.LABOUR_OUTPUT_MOMENTUM_CAP),
		"metal_magnate starts on 1.2x work effort with output momentum at the cap")

	# Every other start is untouched: default effort, no accrued momentum.
	var plain: Dictionary = SaveLoad.expand_start_config({"name": "plain", "money": 100})
	var plain_match: Dictionary = plain.get("match", {})
	_check(is_equal_approx(float(plain_match.get("labour_multiplier", 0.0)), EconomyConfig.LABOUR_MULTIPLIER_DEFAULT)
		and is_equal_approx(float(plain_match.get("labour_output_pressure_pct", -1.0)), 0.0),
		"starts without a labour block keep the default work effort")

	# Authored values are clamped to the configured range, not trusted.
	var wild: Dictionary = SaveLoad.expand_start_config({
		"name": "wild", "labour": {"multiplier": 99.0, "output_pressure_pct": 999.0}})
	var wild_match: Dictionary = wild.get("match", {})
	_check(is_equal_approx(float(wild_match.get("labour_multiplier", 0.0)), EconomyConfig.LABOUR_MULTIPLIER_MAX)
		and is_equal_approx(float(wild_match.get("labour_output_pressure_pct", 0.0)),
			EconomyConfig.LABOUR_OUTPUT_MOMENTUM_CAP),
		"start labour values are clamped to the configured range")

func _test_recording_toasts() -> void:
	var toast = load("res://scripts/toast_manager.gd").new()
	var first := {"items": [{"good_id": "g_008", "qty": 10, "revenue": 20.0}], "total_revenue": 20.0}
	var second := {"items": [{"good_id": "g_008", "qty": 5, "revenue": 10.0}, {"good_id": "g_006", "qty": 4, "revenue": 8.0}], "total_revenue": 18.0}
	_check(toast._format_sales_batch([first, second]) == "Last turn you sold 19 units of 2 goods, totalling £38.00.", "sales toasts: sums revenue and units, counts distinct goods")
	_check(toast._format_sales_batch([first]) == toast._format_stockpile_sale_message(first), "sales toasts: preserves a single sale's existing copy")
	var panel = toast._make_toast("Planning", "caution")
	_check(panel.get_node("Countdown").mouse_filter == Control.MOUSE_FILTER_IGNORE, "toast countdown: overlay never intercepts input")
	_check(panel.get_child(panel.get_child_count() - 1) is Label, "toast countdown: text renders above the countdown")
	panel.free()
	add_child(toast)
	toast.show_caution("Planning")
	toast.show_caution("Planning")
	_check(toast._success_stack.get_child_count() == 1, "planning toasts: repeated amber message appears once")
	toast._on_building_added({"building_id": "b_004", "owner": "Three Diamonds Shipping Corporation"})
	_check(toast._success_stack.get_child_count() == 1, "building toasts: NPC ports create no notification")
	toast.queue_free()
	var snapshot: Dictionary = SaveLoad.export_snapshot()
	DecisionState.pending = {"uid": "recording-test", "def_id": "planning_pushback", "target": {"scope": "building", "instance_id": "missing", "name": "Test"}, "turn_drawn": 30}
	DecisionState.set_hide_updates(true)
	_check(not DecisionState.has_pending(), "recording: resolves pending first choices")
	_check(str(DecisionState._history[-1].choice_id) == "consult", "recording: selects the first displayed option")
	TurnBriefing.expand()
	_check(not TurnBriefing.expanded, "recording: update panel stays hidden")
	DecisionState.set_hide_updates(false)
	SaveLoad.import_snapshot(snapshot)

func _test_cost_save_isolation() -> void:
	var original: Dictionary = SaveLoad.export_snapshot()
	var costs := {"per_building": {"test": {"unit_cost": 0.65}}, "per_good": {"g_008": {"unit_cost": 0.65}}}
	CostSolver.import_state(costs)
	var saved: Dictionary = SaveLoad.export_snapshot()
	CostSolver.import_state({"per_good": {"g_008": {"unit_cost": 99.0}}})
	SaveLoad.import_snapshot(saved)
	_check(CostSolver.export_state() == costs, "save costs: restores per-building and per-good results across matches")
	CostSolver.import_state({})
	SaveLoad.import_snapshot(saved)
	_check(is_equal_approx(CostSolver.get_good_unit_cost("g_008"), 0.65), "save costs: restores immediately with an empty initial cache")
	saved.erase("cost_solver")
	SaveLoad.import_snapshot(saved)
	_check(CostSolver.get_good_unit_cost("g_008") < 0.0, "save costs: legacy snapshot never retains another match's costs")
	var legacy := {"save_version": 10, "turn": {"current_turn": 30}, "market": {"price_history": {"g_008": [{"turn": 30, "cost_basis": 0.65, "price": 1.42}]}}}
	var migrated: Dictionary = SaveLoad._migrate(legacy)
	_check(is_equal_approx(float(migrated.cost_solver.per_good.g_008.unit_cost), 0.65), "save costs: migration recovers the recorded current cost")
	CostSolver.import_state(costs)
	MatchState.reset()
	_check(CostSolver.get_good_unit_cost("g_008") < 0.0, "save costs: new match clears costs")
	SaveLoad.import_snapshot(original)

# Save/load round-trip: populate every save-relevant system, export → JSON → import
# into the reset systems → export again; the two snapshots must agree section by
# section. Catches any state field a later change forgets to serialize.
func _test_save_load_roundtrip() -> void:
	MatchState.add_money(123.0)
	var inst: String = BuildingState.add_building("b_001", "r_001", "tile_12_4")
	var inst_data: Dictionary = BuildingState.buildings[inst]
	inst_data["level"] = 3
	BuildingState.buildings[inst] = inst_data
	Stockpile.add("tile_12_4", "g_001", 25)
	MatchState.mark_tile_surveyed("tile_12_4")
	TransportState.add_recurring_move("tile_12_4", "tile_12_2", {"g_001": 5})
	MatchState.add_recurring_sell("tile_12_4", {"g_001": 3})
	MatchState.add_recurring_buy("tile_12_4", "g_001", 7)
	MatchState.add_recurring_bulk_sell({"good_id": "", "finished_only": true, "per_tile_keep": 2})
	TransportState.queue_move("tile_12_4", "tile_3_8", {"g_001": 5})  # an in-flight shipment
	_check(LoanState.take_loan(30.0), "roundtrip: loan taken for debt state")
	var special_order: Dictionary = SpecialOrderState.create_order("coal", TurnManager.current_turn, 5, 25)
	SpecialOrderState.commit_units(str(special_order.get("id", "")), 4, "tile_view")
	var hm = get_tree().get_first_node_in_group("hex_map")
	if hm != null:
		var coord: Vector2i = hm.id_to_coord("tile_12_4")
		if hm.tiles.has(coord):
			var tile: Dictionary = hm.tiles[coord]
			var infra: Array = tile.get("infrastructure_present", [])
			if not infra.has("pipes"):
				infra.append("pipes")
			var levels: Dictionary = tile.get("infrastructure_levels", {})
			levels["pipes"] = 2
			tile["infrastructure_present"] = infra
			tile["infrastructure_levels"] = levels
			hm.tiles[coord] = tile
			Catalog.add_tile_infrastructure("tile_12_4", "pipes")

	var snap1: Dictionary = SaveLoad.export_snapshot()
	# Real file round-trip via the slot API (covers JSON I/O + slot listing too).
	var save_error := SaveLoad.save_slot("__test_roundtrip")
	_check(save_error == "", "save_slot writes without error (%s)" % save_error)
	var found := false
	for s in SaveLoad.list_slots():
		if str(s.slot) == "__test_roundtrip":
			found = true
	_check(found, "list_slots sees the new save")
	# restart_scene=false: apply in place (the default scene-reload path needs the
	# full game scene; the visual rebuild is exercised manually / by scene tests).
	_check(SaveLoad.load_slot("__test_roundtrip", false) == "", "load_slot applies without error")
	var snap2: Dictionary = SaveLoad.export_snapshot()
	for section in ["turn", "match", "stockpile", "loans", "construction", "market", "special_orders", "production", "events", "modifiers", "infrastructure"]:
		_check(_canonical_json(snap1[section]) == _canonical_json(snap2[section]),
			"round-trip preserves '%s'" % section)

	# Spot-check the loaded state is live, not just equal-on-paper.
	_check(str(BuildingState.get_building(inst).get("tile_id", "")) == "tile_12_4",
		"loaded building is queryable")
	_check(int(BuildingState.get_building(inst).get("level", 0)) == 3,
		"loaded building level survives the round-trip")
	if hm != null:
		var loaded_coord: Vector2i = hm.id_to_coord("tile_12_4")
		var loaded_tile: Dictionary = hm.tiles.get(loaded_coord, {})
		_check(int((loaded_tile.get("infrastructure_levels", {}) as Dictionary).get("pipes", 0)) == 2,
			"loaded infrastructure level survives the round-trip")
		var saved_infra: Dictionary = (snap2.get("infrastructure", {}) as Dictionary).get("tile_12_4", {})
		_check((saved_infra.get("present", []) as Array).has("pipes")
				and int((saved_infra.get("levels", {}) as Dictionary).get("pipes", 0)) == 2,
			"infrastructure snapshot stores present types plus levels")
	_check(Stockpile.get_at_tile("tile_12_4", "g_001") == 20, "loaded stockpile intact (25 - 5 moved)")
	_check(LoanState.total_outstanding() > 0.0, "loaded debt outstanding")
	_check(TransportState.recurring_moves.size() == 1 and MatchState.recurring_buys.size() == 1,
		"recurring orders survive the round-trip")
	var requoted := true
	for shipment in TransportState.pending_transport_shipments:
		if not (shipment.has("tiles") and shipment.has("path") and shipment.has("legs")):
			requoted = false
	_check(requoted, "in-flight shipment routes re-quoted on load")
	DirAccess.remove_absolute(AppPaths.saves_dir().path_join("__test_roundtrip.json"))

# Phase 2 load sequencing: a pending snapshot must apply at the end of
# world_map._ready (after NPC ports/deposit seeding) and overwrite fresh-match
# state — this is the path the main menu's Load Game and the terminal use.
func _test_pending_load_applies_on_scene_ready() -> void:
	var before_money: float = MatchState.money
	var before_buildings: int = BuildingState.buildings.size()
	var snap: Dictionary = SaveLoad.export_snapshot()
	MatchState.add_money(777.0)  # diverge so the apply is observable
	SaveLoad._pending_snapshot = snap
	var inst: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(inst)
	await get_tree().process_frame
	_check(not SaveLoad.has_pending(), "pending save is consumed when the map scene readies")
	_check(absf(MatchState.money - before_money) < 0.001, "pending save restores money over fresh-match state")
	_check(BuildingState.buildings.size() == before_buildings, "pending save restores the building set")
	inst.queue_free()
	await get_tree().process_frame

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
	# New Game panel overrides merge into the match ruleset (survey_all_tiles etc.).
	var ov_snap: Dictionary = SaveLoad.expand_start_config(
		{"start": true, "ruleset": {"name": "standard"}},
		{"ruleset": {"survey_all_tiles": true, "tutorial_enabled": false}})
	var ov_rules: Dictionary = (ov_snap.get("match", {}) as Dictionary).get("ruleset", {})
	_check(bool(ov_rules.get("survey_all_tiles", false)) == true,
		"start config: override survey_all_tiles merges into the match ruleset")
	_check(str(ov_rules.get("name", "")) == "standard",
		"start config: override merge keeps the start's ruleset name")
	# Per-building output routing (output_to) → output_stockpile_destinations, keyed by
	# the minted instance_id, resolving the recipe's output good. And modifiers passthrough.
	var routed: Dictionary = SaveLoad.expand_start_config({
		"start": true,
		"buildings": [
			{"building_id": "b_001", "recipe_id": "r_001", "tile_id": "tile_6_8", "output_to": "tile_6_9"},
			{"building_id": "b_002", "recipe_id": "r_005", "tile_id": "tile_6_9", "output_to": "market"},
		],
		"modifiers": [
			{"id": "start_test_iron", "domain": "recipe_output", "target_match": {"good_internal": "iron_ingots"}, "pct": 10.0, "label": "Test Start"},
		],
	})
	var rmatch: Dictionary = routed.get("match", {})
	var dests: Dictionary = rmatch.get("output_stockpile_destinations", {})
	var mine_route := false
	var furn_market := false
	for iid in dests:
		var per_good: Dictionary = dests[iid]
		if str(iid).begins_with("inst_b_001_") and str(per_good.get("g_001", "")) == "tile_6_9":
			mine_route = true
		if str(iid).begins_with("inst_b_002_") and str(per_good.get("g_004", "")) == MatchState.MARKET_DESTINATION:
			furn_market = true
	_check(mine_route, "start config: output_to tile routes the mine's coal output to the furnace tile")
	_check(furn_market, "start config: output_to market routes the furnace's iron_ingots to __market__")
	var seeded_mods: Dictionary = (routed.get("modifiers", {}) as Dictionary).get("modifiers", {})
	var tm: Dictionary = seeded_mods.get("start_test_iron", {})
	_check(float(tm.get("pct", 0.0)) == 10.0 and str(tm.get("domain", "")) == "recipe_output"
		and float(tm.get("mult", 0.0)) == 1.0 and tm.has("expires_turn"),
		"start config: modifiers passthrough fills the ModifierState import shape (pct/domain/mult/expires_turn)")

# Phase 3 end-to-end: a start config applied through the scene pipeline keeps
# the scene-seeded NPC buildings (ports/ruins), seeds debt WITHOUT cash, and
# leaves the CSV deposit yields intact (the config carries no deposit data).
func _test_start_config_applies_on_scene_ready() -> void:
	# Inline fixture (NOT the live coal_baron.json) so gameplay-content edits to the
	# shipped starts can't break this pipeline test. Mirrors a rich start: cash kept
	# separate from loan principal, a player mine on a CSV coal tile (tile_6_8), a
	# seeded stockpile and a recurring sell.
	var cfg: Dictionary = {
		"start": true, "name": "test_fixture", "ruleset": "standard",
		"money": 350,
		"loans": [ {"principal": 150} ],
		"buildings": [ {"building_id": "b_001", "recipe_id": "r_001", "tile_id": "tile_6_8"} ],
		"stockpile": { "tile_6_8": {"g_001": 50} },
		"land": { "tile_6_8": 120 },
		"recurring": { "sells": [ {"source": "tile_6_8", "goods": {"g_001": 10}} ] },
	}
	_check(not cfg.is_empty(), "fixture start config built")
	SaveLoad._pending_snapshot = SaveLoad.expand_start_config(cfg)
	var inst: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(inst)
	await get_tree().process_frame
	_check(absf(MatchState.money - 350.0) < 0.001, "start: money is the configured 350 (no loan cash)")
	_check(absf(LoanState.total_outstanding() - 165.0) < 0.001, "start: debt outstanding 165")
	var mines := 0
	var npc := 0
	for iid in BuildingState.buildings:
		var b: Dictionary = BuildingState.buildings[iid]
		# Only the player's: the start-building pool seeds NPC mines map-wide.
		if str(b.get("building_id", "")) == "b_001" and BuildingState.is_player_owned(b):
			mines += 1
		if not BuildingState.is_player_owned(b):
			npc += 1
	_check(mines == 1, "start: configured mine exists")
	_check(npc >= 5, "start: scene-seeded NPC ports/ruins survive the start import")
	_check(Stockpile.get_at_tile("tile_6_8", "g_001") == 50, "start: stockpile seeded")
	_check(MatchState.recurring_sells.size() == 1, "start: recurring sell order live")
	_check(MatchState.deposit_remaining_for("tile_6_8", "coal") == 2000,
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
	var legacy_infra: Dictionary = (snap.get("infrastructure", {}) as Dictionary).duplicate(true)
	legacy_infra["tile_12_4"] = ["pipes"]
	snap["infrastructure"] = legacy_infra
	var migrated_snap: Dictionary = SaveLoad._migrate(snap.duplicate(true))
	var migrated_infra: Dictionary = (migrated_snap.get("infrastructure", {}) as Dictionary).get("tile_12_4", {})
	_check((migrated_infra.get("present", []) as Array).has("pipes")
			and migrated_infra.has("levels"),
		"v1 -> v5 migration upgrades infrastructure arrays to structured entries")
	DirAccess.make_dir_recursive_absolute(AppPaths.saves_dir())
	var f := FileAccess.open(AppPaths.saves_dir().path_join("__test_v1.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(snap))
	f.close()
	MatchState.ruleset = {"name": "__sentinel__"}
	_check(SaveLoad.load_slot("__test_v1", false) == "", "v1 save loads through migration")
	_check(str(MatchState.ruleset.get("name", "")) == "standard",
		"v1 -> v2 migration fills in the standard ruleset")
	_check(str(SaveLoad.export_snapshot().get("meta", {}).get("ruleset", "")) == "standard",
		"migrated save re-exports with meta.ruleset")
	_check(SpecialOrderState.get_active_orders().is_empty(),
		"v1 -> v3 migration starts with no active special orders")
	DirAccess.remove_absolute(AppPaths.saves_dir().path_join("__test_v1.json"))

# Phase 4: the autosave hook fires only on every Nth finished turn and rotates
# its slot index. (Drive the handler directly; committing 10 real turns is slow.)
func _test_autosave_rotation() -> void:
	var saved_turn: int = TurnManager.current_turn
	var saved_index: int = SaveLoad._autosave_index
	SaveLoad._autosave_index = 0
	TurnManager.current_turn = SaveLoad.AUTOSAVE_EVERY_TURNS + 1  # turn N just finished
	SaveLoad._on_turn_resolution_completed()
	var auto_snapshot: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(AppPaths.saves_dir().path_join("autosave_1.json")))
	var history: Array = auto_snapshot.market.price_history.get("g_008", [])
	_check(not history.is_empty() and int(history[-1].turn) == TurnManager.current_turn, "autosave: serializes the current chart observation before the history listener")
	_check(SaveLoad._autosave_index == 1 and FileAccess.file_exists(AppPaths.saves_dir().path_join("autosave_1.json")),
		"autosave fires on the Nth finished turn into slot 1")
	TurnManager.current_turn = SaveLoad.AUTOSAVE_EVERY_TURNS + 2  # off-cadence turn
	SaveLoad._on_turn_resolution_completed()
	_check(SaveLoad._autosave_index == 1, "no autosave between cadence points")
	TurnManager.current_turn = 2 * SaveLoad.AUTOSAVE_EVERY_TURNS + 1
	SaveLoad._on_turn_resolution_completed()
	_check(SaveLoad._autosave_index == 2, "next cadence point rotates to slot 2")
	DirAccess.remove_absolute(AppPaths.saves_dir().path_join("autosave_1.json"))
	DirAccess.remove_absolute(AppPaths.saves_dir().path_join("autosave_2.json"))
	TurnManager.current_turn = saved_turn
	SaveLoad._autosave_index = saved_index

# --- EventScheduler ----------------------------------------------------------
# Substrate tests. The bell UI lives separately and has its own UI smoke test.

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
	_check(FileAccess.file_exists(AppPaths.saves_dir().path_join("__test_ui_named.json")),
		"save screen: writes the named slot")
	_check(not save_screen.visible, "save screen: closes after saving")
	await get_tree().process_frame

	var menu: PauseMenu = PauseMenu.open(self)
	await get_tree().process_frame
	var menu_buttons: Array = []
	_collect_buttons(menu, menu_buttons)
	# Return to game / Save / Load / Settings / Exit to Main Menu / Exit to Desktop
	_check(menu_buttons.size() == 6, "pause menu: shows the 6 options")
	var menu_labels: Array = menu_buttons.map(func(b: Button) -> String: return b.text)
	_check(menu_labels.has("Exit to Main Menu"), "pause menu: has Exit to Main Menu")
	_check(menu_labels.has("Exit to Desktop"), "pause menu: has Exit to Desktop")
	_check(PanelStack.close_top() and not menu.visible, "pause menu: Esc path (close_top) closes it")
	await get_tree().process_frame
	DirAccess.remove_absolute(AppPaths.saves_dir().path_join("__test_ui.json"))
	DirAccess.remove_absolute(AppPaths.saves_dir().path_join("__test_ui_named.json"))

func _test_start_layout_baked_fresh() -> void:
	var script := load("res://scripts/start_layout_baked.gd")
	_check(FileAccess.file_exists(script.BAKE_PATH), "start layout: baked file exists")
	var doc: Dictionary = script.state()
	_check(not doc.is_empty(), "start layout: baked file parses")
	_check(str(doc.get("content_hash", "")) == script.content_hash(),
		"start layout: bake is fresh (re-run tools/bake_start_layout.tscn after a map, "
		+ "roads or hills re-bake — a stale one costs ~40 s of load)")


# Roads-v2 Phase 2: baked navgrid, predetermined crossings, the hierarchical
# realizer (determinism + water/forest avoidance), and network save round-trip.
# The pre-existing NPC building pool (data/start_buildings.json): coherent data,
# catalog-valid recipes, mixed phases, and a virtual NPC economy that keeps the
# companies alive without ever touching the player's money.
func _test_start_buildings() -> void:
	StartBuildings.reset_for_tests()
	var entries := StartBuildings.entries()
	_check(entries.size() >= 400, "start buildings: pool present (%d)" % entries.size())
	if entries.is_empty():
		return
	var ids := {}
	var ids_unique := true
	var recipes_ok := true
	var phases_ok := true
	var capital := 0
	var types_by_phase := {}
	for e in entries:
		var iid := str(e.instance_id)
		if ids.has(iid):
			ids_unique = false
		ids[iid] = true
		var phase := int(e.phase)
		if phase < 1 or phase > 5:
			phases_ok = false
		if str(e.region) == "capital_port":
			capital += 1
		if not types_by_phase.has(phase):
			types_by_phase[phase] = {}
		types_by_phase[phase][str(e.building)] = true
		var rid := str(e.recipe)
		if rid != "":
			var recipe: Dictionary = Catalog.get_recipe(rid)
			if recipe.is_empty() or str(recipe.get("building_id", "")) != str(e.building):
				recipes_ok = false
	_check(ids_unique, "start buildings: instance ids unique")
	_check(recipes_ok, "start buildings: every recipe resolves to its building")
	_check(phases_ok, "start buildings: phase tags within 1-5")
	_check(capital == 25, "start buildings: capital pool is 25 (%d)" % capital)
	var mixed := true
	for p in range(1, 6):
		if (types_by_phase.get(p, {}) as Dictionary).size() < 8:
			mixed = false
	_check(mixed, "start buildings: every phase carries a mix of building types")

	# NPC buildings are inert scenery until bought. Inertness is structural: every
	# seeded building is NPC-owned, and production iterates player-owned buildings
	# only — so a seeded furnace is never simulated, costs nothing, produces nothing.
	var all_npc := true
	for e in entries:
		if str(e.owner) == "" or str(e.owner) == MatchState.LOCAL_PLAYER:
			all_npc = false
			break
	_check(all_npc, "start buildings: every seeded building is NPC-owned (inert until bought)")
