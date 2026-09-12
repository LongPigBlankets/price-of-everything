extends "res://tests/test_base.gd"
## Decision events, policy state and politics.

const FEATURE := "decisions"
## Tests that also belong to other features (run under any of their tags).
const TAGS := {
	"_test_decision_resolve_effects_and_loyalty": ["decisions", "research"],
	"_test_decision_loan_fallback": ["decisions", "finance"],
	"_test_insider_tip": ["decisions", "events"],
}

func _politics_titles(panel: Control) -> Array:
	var out: Array = []
	for e: Dictionary in (panel.call("_entries") as Array):
		out.append(str(e.get("title", "")))
	return out

func _test_founder_decision_fires_on_a_new_game() -> void:
	# Reproduces the REAL new-game path, which is what a reservation-based booking could not
	# survive: MatchState.reset() runs first, then SaveLoad calls DecisionState.import_state()
	# with the snapshot's "decisions" key — and a fresh start has no such key, so import_state({})
	# cleared the booking milliseconds after it was made. Reported from a live game: turn 5 of
	# metal_magnate with no Andrew Keeler.
	# DecisionState is inert headless (enabled = DisplayServer != headless), so the fixture
	# turns it on — without this the test passes vacuously by drawing nothing at all.
	var decisions_enabled: bool = DecisionState.enabled
	DecisionState.enabled = true
	MatchState.reset()
	DecisionState.reset()
	DecisionState.import_state({})            # the step that used to wipe it
	TurnManager.current_turn = DecisionState.FOUNDER_DECISION_TURN
	DecisionState._tick_narrative()
	var found := false
	for d in DecisionState.pending_queue:
		if str((d as Dictionary).get("def_id", "")) == "family_friend":
			found = true
	_check(found, "founder: the offer fires on turn %d of a new game, after import_state"
		% DecisionState.FOUNDER_DECISION_TURN)

	# Once offered it never returns, and a later turn does not re-draw it.
	DecisionState.pending_queue.clear()
	DecisionState._tick_narrative()
	var again := false
	for d in DecisionState.pending_queue:
		if str((d as Dictionary).get("def_id", "")) == "family_friend":
			again = true
	_check(not again, "founder: the offer is made once and does not repeat")

	# A player who loads in past the turn still gets it — it is their introduction to the board.
	MatchState.reset()
	DecisionState.reset()
	DecisionState.import_state({})
	TurnManager.current_turn = DecisionState.FOUNDER_DECISION_TURN + 6
	DecisionState._tick_narrative()
	var late := false
	for d in DecisionState.pending_queue:
		if str((d as Dictionary).get("def_id", "")) == "family_friend":
			late = true
	_check(late, "founder: a run already past the turn still gets the offer")

	# The tutorial teaches one chain; a board appointment is noise inside it.
	MatchState.reset()
	MatchState.ruleset = {"name": "tutorial", "tutorial_enabled": true}
	DecisionState.reset()
	DecisionState.import_state({})
	TurnManager.current_turn = DecisionState.FOUNDER_DECISION_TURN
	DecisionState._tick_narrative()
	var in_tutorial := false
	for d in DecisionState.pending_queue:
		if str((d as Dictionary).get("def_id", "")) == "family_friend":
			in_tutorial = true
	_check(not in_tutorial, "founder: the offer is suppressed in the tutorial")
	# Finishing the coach used to make the overdue turn-3 event fire immediately. Tutorial
	# startup now spends it permanently before tutorial_enabled is removed.
	DecisionState.suppress_family_friend_for_match()
	MatchState.ruleset["tutorial_enabled"] = false
	TurnManager.current_turn = DecisionState.FOUNDER_DECISION_TURN + 30
	DecisionState._tick_narrative()
	var after_tutorial := false
	for d in DecisionState.pending_queue:
		if str((d as Dictionary).get("def_id", "")) == "family_friend":
			after_tutorial = true
	_check(not after_tutorial, "founder: a tutorial-started match never receives the offer after hand-off")
	DecisionState.enabled = decisions_enabled
	MatchState.reset()
	TurnManager.current_turn = 1

## The Politics panel is a RECORD of the decarbonisation arc: it repeats what the player was
## already told, in one place they can re-read. So the rule under test is what it shows WHEN
## — nothing before the election, each beat appearing on its turn, and the "ramping up until
## turn X" line giving way to "in full effect" rather than standing there stating something
## that stopped being true.
func _test_politics_panel_entries() -> void:
	var panel: Control = load("res://scripts/politics_panel.gd").new()
	add_child(panel)
	var saved_turn: int = TurnManager.current_turn

	var election: int = PolicyState.beat("election_news")
	var tax_notice: int = PolicyState.beat("tax_notice")
	var ramp: int = PolicyState.beat("ramp_first")
	var p1: int = PolicyState.beat("p1")
	var subsidy: int = PolicyState.beat("subsidy")

	TurnManager.current_turn = maxi(1, election - 1)
	_check((panel.call("_entries") as Array).is_empty(),
		"politics: nothing before the election — the panel says 'No Political Events yet'")

	TurnManager.current_turn = election
	var at_election: Array = panel.call("_entries")
	_check(at_election.size() == 1
			and str((at_election[0] as Dictionary).get("title", "")) == "A new government elected!",
		"politics: the election is the first entry")

	TurnManager.current_turn = tax_notice
	var titles: Array = _politics_titles(panel)
	_check(titles.has("Carbon Tax announced"), "politics: the tax announcement appears on its turn")

	# Mid-ramp: the countdown entry is present and names the turn the levy tops out.
	TurnManager.current_turn = maxi(ramp, mini(ramp, p1 - 1))
	titles = _politics_titles(panel)
	var ramping := false
	for t in titles:
		if str(t).begins_with("Carbon Tax ramping up until turn "):
			ramping = true
			_check(str(t).ends_with(str(p1)), "politics: the ramp entry names the turn it tops out (%d)" % p1)
	_check(ramping, "politics: the ramp entry shows while the levy is still climbing")

	# At full rate the countdown must be GONE, replaced by the standing entry.
	TurnManager.current_turn = p1
	titles = _politics_titles(panel)
	var still_ramping := false
	for t in titles:
		if str(t).begins_with("Carbon Tax ramping up"):
			still_ramping = true
	_check(not still_ramping, "politics: the ramp entry gives way once the levy is at full rate")
	_check(titles.has("Carbon Tax in full effect"), "politics: the levy's standing entry replaces it")

	# The whole arc, once the subsidy has landed.
	TurnManager.current_turn = maxi(subsidy, p1)
	titles = _politics_titles(panel)
	for expected in ["A new government elected!", "Carbon Tax announced",
			"Carbon Tax in full effect", "Subsidy for Green energy",
			"Green Power subsidy in full effect"]:
		_check(titles.has(expected), "politics: '%s' is in the record" % expected)
	# Only the six authored beats, ever — this panel is deliberately not a news feed.
	_check(titles.size() <= 6, "politics: the record stays to the authored beats (%d)" % titles.size())
	# Every entry carries one of the three icons and a body.
	var well_formed := true
	for e: Dictionary in (panel.call("_entries") as Array):
		if not (str(e.get("icon", "")) in ["gavel", "coal_banned", "power"]):
			well_formed = false
		if str(e.get("body", "")) == "":
			well_formed = false
	_check(well_formed, "politics: every entry has one of the three icons and a body")

	TurnManager.current_turn = saved_turn
	panel.queue_free()


func _test_decision_tenure_gate() -> void:
	var snap := _decision_board_snapshot()
	TurnManager.current_turn = 20
	if not AdvisorState.permanent_advisor_ids.has("vera"):
		AdvisorState.permanent_advisor_ids.append("vera")
	AdvisorState.advisor_hired_turn["vera"] = 20
	_check(not AdvisorState.is_advisor_tenured("vera"),
		"decision tenure: an advisor hired THIS turn does not count")
	AdvisorState.advisor_hired_turn["vera"] = 19
	_check(AdvisorState.is_advisor_tenured("vera"),
		"decision tenure: hired on an earlier turn counts")
	_check(not AdvisorState.is_advisor_tenured("nobody"),
		"decision tenure: unknown/unemployed advisors never count")
	# The gate as the dialog sees it: research choice locked until tenured.
	AdvisorState.advisor_seats = {"research_director": "vera"}
	AdvisorState.advisor_hired_turn["vera"] = 20
	DecisionState.reset()
	DecisionState.pending = {"uid": "t1", "def_id": "worker_innovation",
		"target": {"scope": "building", "instance_id": "inst_x", "name": "Test Works"},
		"turn_drawn": 20}
	var view: Dictionary = DecisionState.pending_view()
	var research_choice: Dictionary = {}
	for c in view.choices:
		if str(c.id) == "research":
			research_choice = c
	_check(not bool(research_choice.get("available", true)),
		"decision gate: seat filled by an untenured hire stays locked")
	_check(str(research_choice.get("lock_reason", "")) != "",
		"decision gate: locked choices carry a requirement line")
	AdvisorState.advisor_hired_turn["vera"] = 15
	view = DecisionState.pending_view()
	for c in view.choices:
		if str(c.id) == "research":
			research_choice = c
	_check(bool(research_choice.get("available", false)),
		"decision gate: a tenured seat unlocks the choice")
	_decision_board_restore(snap)

func _test_decision_resolve_effects_and_loyalty() -> void:
	var snap := _decision_board_snapshot()
	Modifiers.reset()
	DecisionState.reset()
	TurnManager.current_turn = 30
	TurnManager.current_phase = TurnManager.Phase.DECIDE
	for aid in ["vera", "tom"]:
		if not AdvisorState.permanent_advisor_ids.has(aid):
			AdvisorState.permanent_advisor_ids.append(aid)
		AdvisorState.advisor_hired_turn[aid] = 20
		AdvisorState.advisor_loyalty[aid] = 0.0
	# CFO advocates hold_line, COO advocates pay_rise (union_demands catalog entry).
	AdvisorState.advisor_seats = {"cfo": "vera", "coo": "tom"}
	DecisionState.pending = {"uid": "t2", "def_id": "union_demands",
		"target": {"scope": "building_type", "building_id": "b_001", "name": "Coal Mine"},
		"turn_drawn": 30}
	var err: String = DecisionState.resolve("hold_line")
	_check(err == "", "decision resolve: valid choice resolves without error (%s)" % err)
	_check(not DecisionState.has_pending(), "decision resolve: pending clears")
	_check(DecisionState.history().size() == 1, "decision resolve: history records the outcome")
	var found := false
	for m in Modifiers.active():
		if str(m.domain) == "recipe_output" and float(m.get("pct", 0.0)) == -10.0 \
				and str((m.get("target_match", {}) as Dictionary).get("building_id", "")) == "b_001":
			found = true
			_check(int(m.get("expires_turn", 0)) == 39,
				"decision modifier: 10-turn DECIDE grant expires at turn 39")
	_check(found, "decision resolve: the output-hit modifier lands, scoped to the building type")
	_check(absf(AdvisorState.advisor_loyalty_value("vera") - 0.5) < 0.001,
		"decision loyalty: followed advisor gains +0.5 on a local-scope decision")
	_check(absf(AdvisorState.advisor_loyalty_value("tom") - (-0.5)) < 0.001,
		"decision loyalty: ignored advocating advisor takes -0.5")
	_decision_board_restore(snap)

func _test_decision_company_scope_loyalty() -> void:
	var snap := _decision_board_snapshot()
	DecisionState.reset()
	TurnManager.current_turn = 30
	TurnManager.current_phase = TurnManager.Phase.DECIDE
	if not AdvisorState.permanent_advisor_ids.has("vera"):
		AdvisorState.permanent_advisor_ids.append("vera")
	AdvisorState.advisor_hired_turn["vera"] = 20
	AdvisorState.advisor_loyalty["vera"] = 0.0
	AdvisorState.advisor_seats = {"cfo": "vera"}
	DecisionState.pending = {"uid": "t3", "def_id": "brokers_offer",
		"target": {"scope": "company", "good_id": "g_001", "name": "Coal"},
		"turn_drawn": 30}
	var err: String = DecisionState.resolve("decline")
	_check(err == "", "decision company scope: resolve ok (%s)" % err)
	_check(absf(AdvisorState.advisor_loyalty_value("vera") - 2.0) < 0.001,
		"decision loyalty: followed advisor gains +2.0 on a company-scope decision")
	_decision_board_restore(snap)

func _test_decision_loan_fallback() -> void:
	var snap := _decision_board_snapshot()
	var loans_before: Array = LoanState.loans.duplicate(true)
	DecisionState.reset()
	TurnManager.current_turn = 30
	TurnManager.current_phase = TurnManager.Phase.DECIDE
	AdvisorState.advisor_seats = {}
	MatchState.money = 10.0
	DecisionState.pending = {"uid": "t4", "def_id": "planning_pushback",
		"target": {"scope": "building", "instance_id": "no_such_project", "name": "Test Site"},
		"turn_drawn": 30}
	var err: String = DecisionState.resolve("accelerate")   # costs £50, we hold £10
	_check(err == "", "decision loan: unaffordable cash choice still resolves (%s)" % err)
	_check(LoanState.loans.size() == loans_before.size() + 1,
		"decision loan: the shortfall arrives as a new loan")
	if LoanState.loans.size() > loans_before.size():
		var loan: Dictionary = LoanState.loans.back()
		_check(absf(float(loan.principal_initial) - 40.0) < 0.001,
			"decision loan: borrowed exactly the £40 shortfall")
	_check(absf(MatchState.money) < 0.001,
		"decision loan: cost paid in full after the loan lands (money at 0)")
	# Already in the red: only the COST is financed — the pre-existing overdraft is
	# NOT refinanced (regression: it used to reset any negative balance to £0).
	MatchState.money = -100.0
	DecisionState.pending = {"uid": "t4b", "def_id": "planning_pushback",
		"target": {"scope": "building", "instance_id": "no_such_project", "name": "Test Site"},
		"turn_drawn": 30}
	var loans_mid: int = LoanState.loans.size()
	err = DecisionState.resolve("accelerate")   # costs £50 at −£100
	_check(err == "", "decision loan (in the red): resolves without error (%s)" % err)
	_check(LoanState.loans.size() == loans_mid + 1
		and absf(float(LoanState.loans.back().principal_initial) - 50.0) < 0.001,
		"decision loan (in the red): borrows exactly the £50 cost, not the deficit")
	_check(absf(MatchState.money - (-100.0)) < 0.001,
		"decision loan (in the red): the overdraft is NOT refinanced back to £0")
	LoanState.loans = loans_before
	_decision_board_restore(snap)

func _test_decision_commit_guard_and_auto_resolve() -> void:
	var snap := _decision_board_snapshot()
	DecisionState.reset()
	AdvisorState.advisor_seats = {}
	TurnManager.current_turn = 40
	TurnManager.current_phase = TurnManager.Phase.DECIDE
	var was_resolving := TurnManager.is_resolving
	DecisionState.auto_resolve = false
	DecisionState.pending = {"uid": "t5", "def_id": "land_deal",
		"target": {"scope": "tile", "tile_id": "tile_1_1", "name": "Test Tile"},
		"turn_drawn": 40}
	TurnManager.commit_turn()
	_check(TurnManager.current_turn == 40 and not TurnManager.is_resolving,
		"decision guard: commit_turn refuses while a decision is pending")
	_check(DecisionState.has_pending(), "decision guard: the decision is still pending")
	# Non-interactive path: the default choice resolves (loyalty rules included).
	DecisionState.auto_resolve = true
	DecisionState.auto_resolve_pending()
	_check(not DecisionState.has_pending(), "decision auto-resolve: default choice clears pending")
	_check(str(DecisionState.history().back().get("choice_id", "")) == "keep",
		"decision auto-resolve: the definition's default_choice was picked")
	DecisionState.auto_resolve = false
	TurnManager.is_resolving = was_resolving
	_decision_board_restore(snap)

func _test_decision_roundtrip() -> void:
	var snap := _decision_board_snapshot()
	DecisionState.reset()
	DecisionState.pending = {"uid": "t6", "def_id": "union_demands",
		"target": {"scope": "building_type", "building_id": "b_002", "name": "Furnace"},
		"turn_drawn": 12}
	DecisionState.flags["env_exempt:inst_9"] = true
	DecisionState.reserve(80, "environmental_inspection")
	var exported: Dictionary = DecisionState.export_state()
	DecisionState.reset()
	_check(not DecisionState.has_pending(), "decision roundtrip: reset clears pending")
	DecisionState.import_state(exported)
	_check(str(DecisionState.pending.get("def_id", "")) == "union_demands",
		"decision roundtrip: pending decision survives export/import")
	_check(DecisionState.flags.has("env_exempt:inst_9"),
		"decision roundtrip: flags survive export/import")
	_check(str(DecisionState._reservations.get(80, "")) == "environmental_inspection",
		"decision roundtrip: story reservations survive (int keys restored)")
	_decision_board_restore(snap)


func _test_decision_story_not_random() -> void:
	# A story-priority decision (e.g. distressed_asset) must NEVER surface from the
	# random scheduler — only reserve()/force_draw() may draw it.
	var snap := _decision_board_snapshot()
	DecisionState.reset()
	for t in range(10, 400):
		var picked: String = DecisionState._pick_random_definition(t)
		if picked != "":
			_check(int((DecisionState.DECISION_DEFINITIONS[picked] as Dictionary).get("priority", 2)) != 0,
				"scheduler: random draw never returns a story-priority decision")
			# advance recency so the loop keeps exploring different picks
			DecisionState._recent_draws.append({"turn": t, "id": picked,
				"category": str((DecisionState.DECISION_DEFINITIONS[picked] as Dictionary).get("category", ""))})
	# And force_draw CAN still summon it directly.
	DecisionState.reset()
	_check(DecisionState.force_draw("distressed_asset") == "",
		"scheduler: force_draw can still summon a story decision")
	DecisionState.reset()
	_decision_board_restore(snap)


func _test_decision_pulse_pipeline() -> void:
	# Pull now, reveal PULSE_LEAD_TURNS later; 20-turn per-category spacing; bounded cadence.
	var snap := _decision_board_snapshot()
	DecisionState.reset()
	DecisionState.auto_resolve = false
	TurnManager.current_turn = 30
	_check(DecisionState._pull("distressed_asset", 30), "pulse: _pull schedules a decision")
	_check(int(DecisionState._scheduled_pull.get("show_turn", 0)) == 30 + DecisionState.PULSE_LEAD_TURNS,
		"pulse: reveal is scheduled PULSE_LEAD_TURNS after the pull")
	_check(not DecisionState.has_pending(), "pulse: nothing is pending during the lead time")
	DecisionState._promote_scheduled()
	_check(DecisionState.has_pending() and DecisionState._scheduled_pull.is_empty(),
		"pulse: promotion moves the scheduled pull into pending")

	DecisionState.reset()
	DecisionState._recent_draws = [{"turn": 30, "id": "union_demands", "category": "labour"}]
	var elig_10: Array = DecisionState._eligible_ids(40)     # 10 turns after a labour event
	var elig_20: Array = DecisionState._eligible_ids(50)     # 20 turns after
	_check(not elig_10.has("union_demands") and not elig_10.has("headhunters"),
		"pulse: the same event type (labour) is ineligible within 20 turns")
	_check(elig_20.has("union_demands") or elig_20.has("headhunters"),
		"pulse: the event type becomes eligible again after 20 turns")

	for t in [12, 40, 120]:
		var iv: int = DecisionState._pulse_interval(int(t))
		_check(iv >= DecisionState.PULSE_MIN and iv <= DecisionState.PULSE_MAX,
			"pulse: interval stays within [PULSE_MIN, PULSE_MAX]")
	DecisionState.reset()
	_decision_board_restore(snap)


# --- Turn Briefing (docs/turn-briefing-panel-spec.md) -------------------------
func _test_decision_queue_stacking() -> void:
	# Several decisions can coexist (the Briefing's mini-menu case): stacking,
	# uid-keyed resolve, the commit guard holding until the LAST one resolves, and
	# auto_resolve clearing the whole queue.
	var snap := _decision_board_snapshot()
	DecisionState.reset()
	AdvisorState.advisor_seats = {}
	TurnManager.current_turn = 40
	TurnManager.current_phase = TurnManager.Phase.DECIDE
	DecisionState.pending_queue = [
		{"uid": "q1", "def_id": "brokers_offer",
			"target": {"scope": "company", "good_id": "g_001", "name": "Coal"}, "turn_drawn": 40},
		{"uid": "q2", "def_id": "land_deal",
			"target": {"scope": "tile", "tile_id": "tile_1_1", "name": "Test Tile"}, "turn_drawn": 40},
	]
	_check(DecisionState.pending_views().size() == 2, "queue: two decisions expand to two views")
	_check(str(DecisionState.pending_view("q2").get("uid", "")) == "q2",
		"queue: pending_view resolves a specific uid")
	# Resolving the SECOND leaves the first pending; commit stays guarded.
	_check(DecisionState.resolve("keep", "q2") == "", "queue: uid-keyed resolve works")
	_check(DecisionState.has_pending(), "queue: one decision still pending after resolving the other")
	var turn_before := TurnManager.current_turn
	TurnManager.commit_turn()
	_check(TurnManager.current_turn == turn_before and not TurnManager.is_resolving,
		"queue: commit_turn refuses while ANY decision is pending")
	DecisionState.auto_resolve = true
	DecisionState.auto_resolve_pending()
	DecisionState.auto_resolve = false
	_check(not DecisionState.has_pending(), "queue: auto_resolve clears the whole queue")
	_decision_board_restore(snap)

## The Balance tab's "Net Cash Flow per turn" is the same promise as the top bar's "/ turn" and
## the Treasury mini-panel's, which both read money_in − money_out. They drifted apart silently:
## advisor salaries moved cash with no row on the sheet at all, and building-tab deferrals were
## charged to the sheet as if paid while money_out excluded them (£1,844 apart on one turn of a
## tabbed build-out). Nothing in 2,000 assertions noticed, because nothing compared them.

## Fluids may now leave the pipe network by road or rail, at a tanker premium
## (EconomyConfig.FLUID_OVERLAND_COST_MULT). Two things have to hold together: the premium
## itself, and the routing preference — the router is FASTEST-first and rail out-ranges pipe
## 4 tiles to 2, so without an explicit pipe-first pass every fluid would desert a working
## pipe network for the nearest railhead and silently cost 3-5x more.

func _test_decision_view_never_empty() -> void:
	# Every decision, with a STALE target (entity gone — the pulse 3-turn lead can
	# leave targets stale), must still yield a non-empty view with choices, and the
	# real dialog must build visible content. A soft-lock happens if the inescapable
	# modal ever shows with no card.
	var snap := _decision_board_snapshot()
	var DialogScript = load("res://scripts/decision_dialog.gd")
	var dlg = DialogScript.new()
	add_child(dlg)
	await get_tree().process_frame
	for def_id in DecisionState.DECISION_DEFINITIONS.keys():
		var def: Dictionary = DecisionState.DECISION_DEFINITIONS[def_id]
		DecisionState.pending = {
			"uid": "diag_%s" % def_id,
			"def_id": str(def_id),
			"target": {"scope": str(def.get("scope", "company")), "name": "Ghost Works",
				"instance_id": "__gone__", "tile_id": "__gone__",
				"building_id": "__gone__", "good_id": "__gone__"},
			"turn_drawn": 30,
		}
		var view: Dictionary = DecisionState.pending_view()
		_check(not view.is_empty() and (view.get("choices", []) as Array).size() > 0,
			"decision '%s': pending_view yields choices even with a stale target" % def_id)
		dlg._rebuild()
		_check(dlg._content.get_child_count() > 0,
			"decision '%s': dialog builds visible content (no empty scrim)" % def_id)
	dlg.queue_free()
	DecisionState.pending = {}
	_decision_board_restore(snap)


func _test_policy_state() -> void:
	# Decarbonisation squeeze (docs/co2-tax-and-green-subsidy-announcements-spec.md):
	# phase levels are pure functions of the turn; the carbon charge reads the dormant
	# co2_tax_multiplier column (now parsed); the biomass ethylene route is tech-gated.
	_check(PolicyState.co2_tax_level(100) == 0, "policy: CO2 tax not in force before turn 101")
	_check(PolicyState.co2_tax_level(101) == 1, "policy: CO2 tax phase 1 at turn 101 (announced t91)")
	_check(PolicyState.co2_tax_level(164) == 1, "policy: still phase 1 at turn 164")
	_check(PolicyState.co2_tax_level(165) == 2, "policy: phase 2 at turn 165")
	_check(PolicyState.co2_tax_level(230) == 3, "policy: phase 3 at turn 230")
	_check(PolicyState.green_subsidy_rate(104) == 0.0, "policy: no subsidy before turn 105")
	_check(absf(PolicyState.green_subsidy_rate(105) - EconomyConfig.GREEN_SUBSIDY_RATE) < 0.0001,
		"policy: subsidy rate live from turn 105")
	# Wind-down: full through 180, −10%/turn across 181..190, gone at 191.
	var full_rate: float = PolicyState.green_subsidy_rate(180)
	_check(absf(full_rate - EconomyConfig.GREEN_SUBSIDY_RATE) < 0.0001, "policy: subsidy at full rate through turn 180")
	_check(absf(PolicyState.green_subsidy_rate(181) - full_rate * 0.9) < 0.0001, "policy: subsidy 90% at turn 181")
	_check(absf(PolicyState.green_subsidy_rate(186) - full_rate * 0.4) < 0.0001, "policy: subsidy 40% at turn 186")
	_check(absf(PolicyState.green_subsidy_rate(189) - full_rate * 0.1) < 0.0001, "policy: subsidy 10% at turn 189 (last paying turn)")
	_check(PolicyState.green_subsidy_rate(190) == 0.0, "policy: subsidy reaches zero at turn 190")
	_check(PolicyState.green_subsidy_rate(191) == 0.0, "policy: subsidy gone at turn 191 (end announcement)")
	# The blocking "Understood" notice: a story-priority decision (never randomly
	# pulled) with a single acknowledge choice, reserved by PolicyState for turn 90.
	var notice: Dictionary = DecisionState.DECISION_DEFINITIONS.get("carbon_tax_notice", {})
	_check(not notice.is_empty(), "policy: carbon_tax_notice decision exists")
	_check(int(notice.get("priority", 99)) == DecisionState.PRIORITY_STORY,
		"policy: notice is story-priority (reserve-only, never randomly pulled)")
	_check((notice.get("choices", []) as Array).size() == 1
		and str((notice.get("choices", [])[0] as Dictionary).get("id", "")) == "understood",
		"policy: notice has the single Understood choice")
	_check(str(notice.get("headline", "")).begins_with("The new government"), "policy: carbon notice carries the owner headline")
	var sub_notice: Dictionary = DecisionState.DECISION_DEFINITIONS.get("green_subsidy_notice", {})
	_check(not sub_notice.is_empty(), "policy: green_subsidy_notice decision exists")
	_check(int(sub_notice.get("priority", 99)) == DecisionState.PRIORITY_STORY,
		"policy: subsidy notice is story-priority (reserve-only)")
	_check((sub_notice.get("choices", []) as Array).size() == 1
		and str((sub_notice.get("choices", [])[0] as Dictionary).get("id", "")) == "understood",
		"policy: subsidy notice has the single Understood choice")
	_check(str(sub_notice.get("headline", "")).begins_with("The government wants"), "policy: subsidy notice carries the owner headline")
	var saved_copy_rules := MatchState.ruleset.duplicate(true)
	var saved_copy_pending := DecisionState.pending_queue.duplicate(true)
	for timeline in ["campaign", "demo_itch"]:
		MatchState.ruleset["policy_timeline"] = timeline
		DecisionState.pending_queue = [{"uid": "copy_notice", "def_id": "carbon_tax_notice",
			"target": {"scope": "company", "name": "Company"}}]
		var copy_view := DecisionState.pending_view()
		_check(str(copy_view.headline).contains("turn " + str(PolicyState.beat("ramp_first")))
			and str(copy_view.headline).contains("turn " + str(PolicyState.beat("p1"))),
			"policy copy uses the active levy dates: " + timeline)
		_check(str(copy_view.choices[0].consequence).contains(str(PolicyState.beat("ramp_first")))
			and not str(copy_view.choices[0].consequence).contains("{levy"),
			"policy consequence resolves dates in both rulesets")
		DecisionState.pending_queue[0].def_id = "green_subsidy_notice"
		copy_view = DecisionState.pending_view()
		_check(str(copy_view.headline).contains("turn " + str(PolicyState.beat("subsidy"))),
			"subsidy copy uses the active start date: " + timeline)
	MatchState.ruleset = saved_copy_rules
	DecisionState.pending_queue = saved_copy_pending

	var end_notice: Dictionary = DecisionState.DECISION_DEFINITIONS.get("green_subsidy_end_notice", {})
	_check(not end_notice.is_empty() and int(end_notice.get("priority", 99)) == DecisionState.PRIORITY_STORY
		and (end_notice.get("choices", []) as Array).size() == 1,
		"policy: subsidy end notice exists (story-priority, single Understood)")
	# Catalog now parses the multiplier column (was dormant).
	var coal: Dictionary = Catalog.get_good_by_internal_name("coal")
	_check(absf(float(coal.get("co2_tax_multiplier", 0.0)) - 0.5) < 0.0001, "catalog: coal carbon intensity 0.5")
	var eth: Dictionary = Catalog.get_good_by_internal_name("ethylene")
	_check(absf(float(eth.get("co2_tax_multiplier", 0.0)) - 1.0) < 0.0001, "catalog: ethylene carbon intensity 1.0")
	# Charge math: 20 coal at P1 = 20 × 0.5 × 1.0 × 1.0 = £10; ×2 at P2; 0 before the
	# ramp; a linear ramp-in across 91..100 ((turn−90)/11 of P1).
	var coal_id := str(coal.get("id", ""))
	_check(absf(PolicyState.carbon_charge(coal_id, 20, 101) - 10.0) < 0.001, "policy: 20 coal at P1 charges £10")
	_check(absf(PolicyState.carbon_charge(coal_id, 20, 165) - 20.0) < 0.001, "policy: 20 coal at P2 charges £20")
	_check(PolicyState.carbon_charge(coal_id, 20, 10) == 0.0, "policy: no charge before the levy")
	_check(PolicyState.carbon_charge(coal_id, 20, 90) == 0.0, "policy: no charge at turn 90 (notice turn)")
	_check(absf(PolicyState.carbon_charge(coal_id, 20, 91) - 10.0 / 11.0) < 0.001, "policy: ramp begins at turn 91 (1/11 of P1)")
	_check(absf(PolicyState.carbon_charge(coal_id, 20, 96) - 10.0 * 6.0 / 11.0) < 0.001, "policy: mid-ramp at turn 96 (6/11 of P1)")
	_check(PolicyState.carbon_charge(coal_id, 20, 100) < 10.0, "policy: still below full P1 at turn 100")
	var biomass_id := str(Catalog.get_good_by_internal_name("biomass").get("id", ""))
	_check(PolicyState.carbon_charge(biomass_id, 100, 230) == 0.0, "policy: biomass is untaxed even at P3")
	# The biomass→ethylene escape route: r_228 Bio Ethylene (chem_plant, biomass direct)
	# promotes and is gated behind the new Biomass Cracking node. r_155 stays in the
	# dormant pool (bio_chem_plant / spec_microbes don't exist — original state).
	var r228: Dictionary = Catalog.get_recipe("r_228")
	_check(not r228.is_empty(), "recipe: r_228 (Bio Ethylene) promotes")
	_check(str(r228.get("tech_unlock_req", ""))
			== ResearchState.research_node_id_for_title("Biomass Cracking"),
		"recipe: r_228 gated behind Biomass Cracking")
	_check(Catalog.get_recipe("r_155").is_empty(), "recipe: r_155 stays dormant (original pool state)")
	var found_node := false
	for d in ResearchState._unlock_defs:
		if str(d.get("title", "")) == "Biomass Cracking":
			found_node = true
			_check(str(d.get("action", "")) == "Produce" and str(d.get("object", "")) == "biomass",
				"research: Biomass Cracking unlocks by producing biomass (fireable condition)")
	_check(found_node, "research: Biomass Cracking node exists")


func _test_insider_tip() -> void:
	# Government Affairs insider leak (turns 86..89): fires only with a 3/3-Influencing
	# officer in the seat, once per match; dismissible-critical news, not a decision.
	var seats_before: Dictionary = AdvisorState.advisor_seats.duplicate(true)
	var turn_before: int = TurnManager.current_turn
	PolicyState._insider_tip_fired = false

	# No officer → nothing, even inside the window.
	AdvisorState.advisor_seats = {}
	TurnManager.current_turn = 86
	PolicyState._maybe_fire_insider_tip()
	_check(not PolicyState._insider_tip_fired, "insider tip: silent with no Government Affairs officer")

	# A low-Influencing officer (Tom, inf 1) doesn't leak.
	AdvisorState.advisor_seats = {"government_affairs": "tom"}
	_check(PolicyState.get_insider_tip_officer() == "", "insider tip: inf < 3 officer doesn't qualify")
	PolicyState._maybe_fire_insider_tip()
	_check(not PolicyState._insider_tip_fired, "insider tip: silent with a low-Influencing officer")

	# Rufus (Silver Tongue, inf 3/3) leaks — but only inside the window.
	AdvisorState.advisor_seats = {"government_affairs": "rufus"}
	_check(PolicyState.get_insider_tip_officer() == "rufus", "insider tip: 3/3 officer qualifies")
	TurnManager.current_turn = 85
	PolicyState._maybe_fire_insider_tip()
	_check(not PolicyState._insider_tip_fired, "insider tip: not before turn 86")
	TurnManager.current_turn = 90
	PolicyState._maybe_fire_insider_tip()
	_check(not PolicyState._insider_tip_fired, "insider tip: not from turn 90 (official notice imminent)")
	TurnManager.current_turn = 87
	PolicyState._maybe_fire_insider_tip()
	_check(PolicyState._insider_tip_fired, "insider tip: fires in the window with a 3/3 officer")
	var found := false
	var tip_id := ""
	for ev in EventScheduler.active_events():
		if str(ev.get("kind", "")) == "advisor_tip":
			found = true
			tip_id = str(ev.get("id", ""))
			_check(str(ev.get("severity", "")) == "critical", "insider tip: critical severity")
			_check(str(ev.get("title", "")).begins_with("Rufus Ashby"), "insider tip: names the officer")
	_check(found, "insider tip: lands as an active (dismissible) event")

	# Once per match: a second window turn doesn't re-fire.
	var count_before: int = EventScheduler.active_events().size()
	TurnManager.current_turn = 88
	PolicyState._maybe_fire_insider_tip()
	_check(EventScheduler.active_events().size() == count_before, "insider tip: never fires twice")

	if tip_id != "":
		EventScheduler.dismiss(tip_id)
	PolicyState._insider_tip_fired = false
	AdvisorState.advisor_seats = seats_before
	TurnManager.current_turn = turn_before
