extends "res://tests/test_base.gd"
## Victory tracks, demo endings, end-game data and company rankings.

const FEATURE := "victory"
## Tests that also belong to other features (run under any of their tags).
const TAGS := {
	"_test_endgame_continuity_verdict": ["production", "victory"],
	"_test_game_ended_persists": ["save_load", "victory"],
	"_test_demo_itch_speed": ["decisions", "victory"],
	"_test_demo_victory_tracks": ["production", "victory"],
}

## First good the catalog files under `tier`, by the id the production summary uses, so
## the tiers test names real goods rather than assuming which one sits where.
func _a_good_in_tier(tier: String) -> String:
	for good_variant: Variant in Catalog.all_goods():
		var good: Dictionary = good_variant
		if str(good.get("goods_graph_tier", "")) == tier:
			return str(good.get("id", ""))
	return ""

func _test_company_rankings() -> void:
	var history: Array[float] = [80.0, 95.0, 120.0, 140.0, 160.0]
	var first: Array[Dictionary] = CompanyRankings.standings_for(24680, 50, history)
	var second: Array[Dictionary] = CompanyRankings.standings_for(24680, 50, history)
	_check(JSON.stringify(first) == JSON.stringify(second),
		"company rankings: same seed, turn, and player history reconstruct the same table")
	_check(first.size() == CompanyRankings.TOTAL_COMPANIES,
		"company rankings: table contains nine rivals plus Your Company")
	var names: Dictionary = {}
	for row: Dictionary in first:
		names[str(row.get("name", ""))] = true
	_check(names.size() == CompanyRankings.TOTAL_COMPANIES and names.has("Your Company"),
		"company rankings: seeded roster has unique rivals and the fixed player name")
	var cycle: Array[int] = CompanyRankings._cycle_for(24680, 0)
	var grows := 0
	var decays := 0
	var flats := 0
	for phase: int in cycle:
		if phase == CompanyRankings.CyclePhase.GROW:
			grows += 1
		elif phase == CompanyRankings.CyclePhase.DECAY:
			decays += 1
		else:
			flats += 1
	_check(grows == 5 and decays == 2 and flats == 2,
		"company rankings: every rival cycle has 5 growth, 2 decay, and 2 flat turns")
	# Rival revenue used to compound with nothing stopping it, and reached £50k a turn against
	# a player earning £1.1k before anyone noticed — a cosmetic table, but one that made the
	# Crown track unwinnable after the opening. Nothing in the suite could see it, because
	# nothing asserted a scale. This does, at both ends of the demo and out into a campaign.
	var band_ok := true
	var fanned_out := true
	for check_turn: int in [25, 100, 300]:
		var curve: float = CompanyRankings._reference_revenue(check_turn)
		var top := 0.0
		var bottom := INF
		for rival: int in range(CompanyRankings.RIVAL_COUNT):
			var r: float = CompanyRankings._rival_revenue_for(24680, rival, check_turn)
			top = maxf(top, r)
			bottom = minf(bottom, r)
		# 2% of slack: the ceiling is an asymptote applied per discrete turn, so one maximal
		# 25% draw taken at 98% of the cap can land ~1.5% over it before decay and the next
		# turn's higher ceiling pull it back. The runaway this guards against was 4,500%.
		band_ok = band_ok and top <= curve * CompanyRankings.LEADER_CEILING_MULTIPLE * 1.02
		fanned_out = fanned_out and bottom < top * 0.75
	_check(band_ok,
		"company rankings: no rival ever passes 1.5x what the player earns, at turn 25, 100 or 300")
	_check(fanned_out,
		"company rankings: the field fans out into positions rather than bunching at the ceiling")
	# Turn 0: every rival is still on STARTING_REVENUE, so matching it is a real tie. Written
	# against the constant rather than a literal, because the literal silently stopped tying
	# the moment rivals were moved off 100 to open level with the player.
	var tied: Array[Dictionary] = CompanyRankings.standings_for(
		24680, 0, [CompanyRankings.STARTING_REVENUE])
	_check(bool(tied[0].get("is_player", false)) and int(tied[0].get("rank", 0)) == 1,
		"company rankings: equal revenue always favours Your Company")
	var player_row: Dictionary = {}
	for row: Dictionary in first:
		if bool(row.get("is_player", false)):
			player_row = row
	_check(is_equal_approx(float(player_row.get("trend_average", 0.0)), 119.0),
		"company rankings: player trend is the average of the last five revenues")
	var bar := preload("res://scripts/top_bar.gd").new()
	var risk_rows: Array[Dictionary] = [
		{"is_player": true, "revenue": 100.0, "revenue_change": -5.0},
		{"is_player": false, "revenue": 90.0, "revenue_change": 10.0}]
	_check(bar._ranking_position_at_risk(risk_rows), "rankings warn when the next rival is on course to overtake")
	risk_rows[1].revenue_change = 0.0
	_check(not bar._ranking_position_at_risk(risk_rows), "rankings do not warn while the lead remains safe")
	bar.free()
	var growth_rng := RandomNumberGenerator.new()
	growth_rng.seed = 97531
	var growth_total := 0.0
	var growth_in_bounds := true
	var decay_in_bounds := true
	for _i: int in range(1000):
		var growth_rate: float = CompanyRankings._growth_rate(growth_rng)
		var decay_rate: float = CompanyRankings._decay_rate(growth_rng)
		growth_total += growth_rate
		growth_in_bounds = growth_in_bounds and growth_rate >= CompanyRankings.GROWTH_MIN and growth_rate <= CompanyRankings.GROWTH_MAX
		decay_in_bounds = decay_in_bounds and decay_rate >= CompanyRankings.DECAY_MIN and decay_rate <= CompanyRankings.DECAY_MAX
	_check(growth_in_bounds and decay_in_bounds,
		"company rankings: growth stays within 1–25%% and decay within 1–5%%")
	_check(absf(growth_total / 1000.0 - CompanyRankings.GROWTH_MEAN) < 0.01,
		"company rankings: sampled growth remains centred near 15%%")
	var goods_tables: Array[Dictionary] = CompanyRankings.goods_standings_for(24680, 0, {"g_001": 7})
	var coal_table: Dictionary = {}
	var cpu_table: Dictionary = {}
	for good_table: Dictionary in goods_tables:
		if str(good_table.get("good_id", "")) == "g_001":
			coal_table = good_table
		elif str(good_table.get("good_id", "")) == "g_041":
			cpu_table = good_table
	var coal_rows: Array = coal_table.get("producers", []) as Array
	var cpu_rows: Array = cpu_table.get("producers", []) as Array
	# The podium rule, checked on EVERY good rather than on coal alone: three rows when the
	# player is among the top three, four when they are not, and never more than the field holds.
	# The old assertion pinned "always 4", which was the bug — rivals were cut to three and the
	# player appended, so a player leading a good pushed a fourth-place rival onto the card.
	var podium_ok := true
	var player_on_every_card := true
	var rank_exceeds_card := false
	for good_table: Dictionary in goods_tables:
		var producers: Array = good_table.get("producers", []) as Array
		var own_row: Dictionary = {}
		for row_variant: Variant in producers:
			var card_row: Dictionary = row_variant
			if bool(card_row.get("is_player", false)):
				own_row = card_row
		if own_row.is_empty():
			player_on_every_card = false
			continue
		var player_rank: int = int(own_row.get("rank", 0))
		var shown: int = CompanyRankings.GOOD_ROWS_SHOWN
		if player_rank > CompanyRankings.GOOD_ROWS_SHOWN:
			shown += 1
		if producers.size() != mini(shown, int(good_table.get("field_size", shown))):
			podium_ok = false
		if player_rank > producers.size():
			rank_exceeds_card = true
	_check(podium_ok and player_on_every_card and coal_rows.size() >= 3
		and cpu_rows.size() == 1 and bool((cpu_rows[0] as Dictionary).get("is_player", false)),
		"company rankings: a good shows the top three plus the player; apex goods show only player")
	_check(rank_exceeds_card,
		"company rankings: an off-podium player keeps their rank in the whole field, not on the card")
	var coal_base: int = Catalog.base_output_for_good("g_001")
	_check(int((coal_rows[0] as Dictionary).get("quantity", 0)) >= coal_base
		and coal_rows.any(func(row: Dictionary) -> bool: return bool(row.get("is_player", false)) and int(row.get("quantity", 0)) == 7),
		"company rankings: rival goods start at base recipe output and retain actual player output")
	var coal_before_increment: int = CompanyRankings._rival_good_output_for(24680, "g_001", 0, 4)
	var coal_after_increment: int = CompanyRankings._rival_good_output_for(24680, "g_001", 0, 5)
	_check(coal_before_increment == coal_base and coal_after_increment >= coal_base
		and coal_after_increment - coal_base in [0, int(round(coal_base * 0.2)), int(round(coal_base * 0.5)), coal_base],
		"company rankings: goods gain one allowed integer increment every five turns")
	var rng_before: int = MatchState._match_rng.state
	CompanyRankings.standings_for(13579, 300, history)
	CompanyRankings.goods_standings_for(13579, 300, {"g_001": 20})
	_check(MatchState._match_rng.state == rng_before,
		"company rankings: table generation does not consume the simulation RNG")
	# Per-good competitors. Every good used to list all nine rivals at identical output, so
	# the id tiebreak put the same three names on top of every good in the panel.
	var name_sets: Dictionary = {}
	var sizes_ok := true
	var goods_checked := 0
	for good_table: Dictionary in goods_tables:
		if bool(good_table.get("is_apex", false)):
			continue
		var producers: Array = good_table.get("producers", []) as Array
		if producers.size() < 2:
			continue   # a good no rival produces
		goods_checked += 1
		var key: Array = []
		for row_variant: Variant in producers:
			var row: Dictionary = row_variant
			if not bool(row.get("is_player", false)):
				key.append(str(row.get("id", "")))
		key.sort()
		name_sets[", ".join(key)] = true
	_check(goods_checked > 10 and name_sets.size() >= 5,
		"company rankings: goods are contested by different companies, not the same three")
	var participants: Array = CompanyRankings._competitors_for_good(24680, "g_001")
	_check(participants.size() >= CompanyRankings.GOOD_MIN_COMPETITORS
		and participants.size() <= CompanyRankings.RIVAL_COUNT,
		"company rankings: a good is contested by 3 to RIVAL_COUNT companies")
	var unique_participants: Dictionary = {}
	for idx_variant: Variant in participants:
		unique_participants[int(idx_variant)] = true
	_check(unique_participants.size() == participants.size(),
		"company rankings: no company competes against itself in a good")
	_check(CompanyRankings._competitors_for_good(24680, "g_001") == participants
		and CompanyRankings._competitors_for_good(13579, "g_001") != participants,
		"company rankings: the field is fixed for a match and differs between matches")
	var rng_before_field: int = MatchState._match_rng.state
	CompanyRankings._competitors_for_good(24680, "g_002")
	_check(MatchState._match_rng.state == rng_before_field,
		"company rankings: picking the field does not consume the simulation RNG")

	var saved: Dictionary = CompanyRankings.export_state()
	CompanyRankings.import_state({"player_revenue_history": history, "player_goods_produced": {"g_001": 9}})
	var restored: Dictionary = CompanyRankings.export_state()
	_check(restored.get("player_revenue_history", []) == history and int((restored.get("player_goods_produced", {}) as Dictionary).get("g_001", 0)) == 9,
		"company rankings: player revenue history and goods output persist after load")
	CompanyRankings.import_state(saved)

func _test_endgame_continuity_verdict() -> void:
	# Three outcomes, not two: reaching the bell with no track secured is only RECEIVERSHIP if
	# the company was also losing money. Still in profit = "Continuity", amber (owner 2026-08-01).
	var EGD := load("res://scripts/end_game_data.gd")
	_check(EGD._title("continuity", 0, []) == "Continuity", "endgame: continuity is titled Continuity")
	_check(EGD._title("defeat", 0, []) == "Receivership", "endgame: a loss-making end is still Receivership")
	_check(EGD._title("victory", 5, []) == "The Full Ledger", "endgame: victory titles are untouched")
	var copy: Array = EGD._copy("continuity", 0, 300, [])
	_check(copy.size() == 1, "endgame: continuity copy is the owner's single paragraph")
	_check(str(copy[0]).begins_with("You continued your predecessors' task"),
		"endgame: continuity copy opens with the owner's wording")
	_check(str(copy[0]).ends_with("we can't afford the fancy stuff."),
		"endgame: continuity copy closes with the owner's wording")
	# The verdict is driven by the SAME net/turn the top bar prints, so the two can never disagree.
	var saved: Dictionary = Production.last_turn_summary.duplicate(true)
	Production.last_turn_summary = {"money_in": 500.0, "money_out": 400.0}
	_check(EGD._net_per_turn() > 0.0, "endgame: net/turn reads money_in - money_out (in profit)")
	Production.last_turn_summary = {"money_in": 100.0, "money_out": 900.0}
	_check(EGD._net_per_turn() < 0.0, "endgame: net/turn goes negative when outgoings win")
	Production.last_turn_summary = saved


# Phase 4: a finished game stays finished across save/load.
func _test_game_ended_persists() -> void:
	var snap: Dictionary = SaveLoad.export_snapshot()
	(snap.get("turn", {}) as Dictionary)["game_ended"] = true
	(snap.get("turn", {}) as Dictionary)["current_turn"] = TurnManager.MAX_TURNS + 1
	SaveLoad.import_snapshot(snap)
	_check(TurnManager.game_ended and TurnManager.current_turn == TurnManager.MAX_TURNS + 1,
		"game_ended + final turn survive a load")
	TurnManager.reset_for_test()

# ── Victory system (scripts/victory_state.gd; docs/victory-system-spec.md §12) ──
func _test_victory_base_curve() -> void:
	# No base score any more — you start at 0. The rising WIN BAR is the time pressure.
	VictoryState.reset()
	_check(VictoryState.total_for_turn() == 0, "victory: start at 0 (no base score)")
	_check(VictoryState.win_threshold_for_turn(1) == 1000, "victory bar: turn 1 = 1000 (flat before 105)")
	_check(VictoryState.win_threshold_for_turn(105) == 1000, "victory bar: turn 105 = 1000 (1 track)")
	_check(VictoryState.win_threshold_for_turn(170) == 2000, "victory bar: turn 170 = 2000 (2 tracks)")
	_check(VictoryState.win_threshold_for_turn(235) == 3000, "victory bar: turn 235 = 3000 (3 tracks)")
	_check(VictoryState.win_threshold_for_turn(300) == 4000, "victory bar: turn 300 = 4000 (4 tracks)")
	_check(VictoryState.win_threshold_for_turn(350) == 4000, "victory bar: turn 350 = 4000 (clamped)")

func _test_victory_disabled_in_tutorial() -> void:
	var rules_saved: Dictionary = MatchState.ruleset.duplicate(true)
	MatchState.ruleset = {"name": "tutorial", "tutorial_enabled": true}
	VictoryState.reset()
	VictoryState._on_turn_processed({"produced": {"steel": 500}, "money_in": 15000.0, "money_out": 0.0})
	VictoryState.record_movement("buy", "input", 0)
	VictoryState._tick()
	_check(not VictoryState.conditions_enabled()
		and VictoryState.total_for_turn() == 0
		and VictoryState.produced_units_lifetime == 0
		and VictoryState.logistics_total == 0
		and int(VictoryState.purchases_lifetime.get("input", 0)) == 0,
		"victory: tutorial turns do not advance victory conditions")
	MatchState.ruleset = rules_saved
	VictoryState.reset()

func _test_victory_win_curve() -> void:
	VictoryState.reset()
	# 1 maxed track (1000) wins at turn 105 but not once the bar has risen past it.
	_check(1000 >= VictoryState.win_threshold_for_turn(105), "victory curve: 1 track wins at turn 105")
	_check(1000 < VictoryState.win_threshold_for_turn(170), "victory curve: 1 track falls short at turn 170")
	_check(3000 < VictoryState.win_threshold_for_turn(300), "victory curve: 3 tracks fall short at turn 300")
	_check(4000 >= VictoryState.win_threshold_for_turn(300), "victory curve: 4 tracks win at turn 300")

func _test_victory_autarkic() -> void:
	MatchState.reset()
	VictoryState.reset()
	# A buy of each category increments that category's tally (this turn + lifetime).
	VictoryState.record_movement("buy", "input", 0)
	VictoryState.record_movement("buy", "building", 2)
	VictoryState.record_movement("buy", "upgrade", 0)
	VictoryState.record_movement("buy", "other", 1)
	_check(int(VictoryState.purchases_this_turn["input"]) == 1
		and int(VictoryState.purchases_this_turn["building"]) == 1
		and int(VictoryState.purchases_this_turn["upgrade"]) == 1
		and int(VictoryState.purchases_this_turn["other"]) == 1,
		"victory autarkic: a buy of each category increments purchases_this_turn")
	_check(int(VictoryState.purchases_lifetime["input"]) == 1
		and int(VictoryState.purchases_lifetime["other"]) == 1,
		"victory autarkic: lifetime tally accumulates")
	# A turn with any purchase resets the streak.
	TurnManager.current_turn = 5
	VictoryState.autarkic_streak = 9
	VictoryState._tick()
	_check(VictoryState.autarkic_streak == 0, "victory autarkic: a turn with any buy resets the streak")
	# A turn with only a move or sale does NOT reset.
	VictoryState.record_movement("move", "", 0)
	VictoryState.record_movement("sale", "", 3)
	VictoryState.autarkic_streak = 4
	VictoryState._tick()
	_check(VictoryState.autarkic_streak == 5, "victory autarkic: a move/sale-only turn keeps the streak (4 -> 5)")
	# Scale gate: the track scores 0 until lifetime production clears AUTARKIC_MIN_UNITS,
	# even with a maxed streak.
	VictoryState.autarkic_streak = 40
	VictoryState.produced_units_lifetime = VictoryState.AUTARKIC_MIN_UNITS - 1
	_check(absf(VictoryState._live_progress("autarkic")) < 0.001, "victory autarkic: gated to 0 below the 10k-unit floor despite a maxed streak")
	VictoryState.produced_units_lifetime = VictoryState.AUTARKIC_MIN_UNITS
	_check(absf(VictoryState._live_progress("autarkic") - 1.0) < 0.001, "victory autarkic: scores once the units floor is cleared")
	# Progress ramps from streak 10 to 30 (units gate cleared above).
	VictoryState.autarkic_streak = 10
	_check(absf(VictoryState._live_progress("autarkic")) < 0.001, "victory autarkic: progress 0 at streak 10")
	VictoryState.autarkic_streak = 20
	_check(absf(VictoryState._live_progress("autarkic") - 0.5) < 0.001, "victory autarkic: progress 0.5 at streak 20")
	VictoryState.autarkic_streak = 30
	_check(absf(VictoryState._live_progress("autarkic") - 1.0) < 0.001, "victory autarkic: progress caps at streak 30")
	VictoryState.autarkic_streak = 40
	_check(absf(VictoryState._live_progress("autarkic") - 1.0) < 0.001, "victory autarkic: progress stays capped above 30")
	# Accumulator sums this turn's produced GOODS units — POWER is ignored (owner 2026-07-11:
	# Autarkic ignores electricity), so 30 coal + 20 iron_ore = 50, the 9000 MW doesn't count.
	VictoryState.produced_units_lifetime = 0
	VictoryState._last_summary = {"produced": {"coal": 30, "iron_ore": 20, "power": 9000}}
	VictoryState._tick()
	_check(VictoryState.produced_units_lifetime == 50, "victory autarkic: _tick sums produced goods, ignores power (30+20)")
	# Drawing from the grid (grid_bought) with NO market buys must NOT break the streak.
	VictoryState.reset()
	VictoryState.autarkic_streak = 12
	VictoryState._last_summary = {"produced": {"steel": 40}, "grid_bought": 800}
	VictoryState._tick()
	_check(VictoryState.autarkic_streak == 13, "victory autarkic: drawing grid power doesn't break the streak")

func _test_victory_logistics() -> void:
	VictoryState.reset()
	# 50 efficient movements is below the 100-move gate -> progress 0.
	for _i in range(50):
		VictoryState.record_movement("move", "", 0)
	_check(absf(VictoryState._live_progress("logistics")) < 0.001, "victory logistics: 0 below 100 moves")
	# Top up to 100 total: 25 inefficient (3 turns) + 25 efficient (1 turn) -> 75/100.
	for _i in range(25):
		VictoryState.record_movement("buy", "input", 3)
	for _i in range(25):
		VictoryState.record_movement("sale", "", 1)
	_check(VictoryState.logistics_total == 100 and VictoryState.logistics_efficient == 75,
		"victory logistics: counts total + efficient (0/1-turn movements count as efficient)")
	# eff 0.75 -> (0.75-0.25)/0.75 = 0.667.
	_check(absf(VictoryState._live_progress("logistics") - (0.5 / 0.75)) < 0.001,
		"victory logistics: 75% efficiency maps to ~0.667 progress")
	# Per-turn track: the tick latches the best, then resets the movement counters,
	# so next turn starts from zero (no cumulative credit since game start).
	TurnManager.current_turn = 50
	VictoryState._on_turn_processed({"money_in": 0.0, "money_out": 0.0})
	VictoryState._tick()
	_check(VictoryState.logistics_total == 0 and VictoryState.logistics_efficient == 0
		and absf(float(VictoryState.track_best["logistics"]) - (0.5 / 0.75)) < 0.001,
		"victory logistics: tick latches best then resets per-turn counters")
	_check(absf(VictoryState._live_progress("logistics")) < 0.001,
		"victory logistics: live progress is 0 again after the per-turn reset")
	# Power is grid-settled, never shipped — generating/consuming it emits no goods
	# movement, so a turn of pure power activity adds nothing to the logistics tally.
	VictoryState.reset()
	VictoryState._last_summary = {"produced": {"power": 9000}, "grid_bought": 500, "grid_sold": 1200}
	VictoryState._tick()
	_check(VictoryState.logistics_total == 0,
		"victory logistics: power generation/grid trade counts no movements")

func _test_victory_richest() -> void:
	MatchState.reset()
	VictoryState.reset()
	# Smoothed metric of a flat £7k/turn window -> (7000-2000)/10000 = 0.5.
	VictoryState.richest_window = [7000.0, 7000.0, 7000.0, 7000.0, 7000.0]
	_check(absf(VictoryState._live_progress("richest") - 0.5) < 0.001,
		"victory richest: 5-turn avg of £7k maps to 0.5")
	# Best-ever capture: a great turn lifts best; a bad turn cannot claw it back.
	VictoryState.reset()
	TurnManager.current_turn = 50
	VictoryState._on_turn_processed({"money_in": 12000.0, "money_out": 0.0})
	VictoryState._tick()
	var best_after_good := float(VictoryState.track_best["richest"])
	VictoryState._on_turn_processed({"money_in": 0.0, "money_out": 0.0})
	VictoryState._tick()
	_check(best_after_good > 0.0 and float(VictoryState.track_best["richest"]) >= best_after_good,
		"victory richest: best-ever does not regress after a bad turn")

func _test_victory_widest() -> void:
	MatchState.reset()
	VictoryState.reset()
	# Two player non-infra tiles (mine), one player INFRA tile (port, excluded),
	# one NPC tile (excluded by ownership).
	BuildingState.buildings["w1"] = {"building_id": "b_001", "tile_id": "t1", "owner": "player_1"}
	BuildingState.buildings["w2"] = {"building_id": "b_001", "tile_id": "t2", "owner": "player_1"}
	BuildingState.buildings["w3"] = {"building_id": "b_004", "tile_id": "t3", "owner": "player_1"}
	BuildingState.buildings["w4"] = {"building_id": "b_001", "tile_id": "t4", "owner": "ai_corp"}
	# Landfill is category=production (building_type=infrastructure) -> counts per spec §5.4.
	BuildingState.buildings["w5"] = {"building_id": "b_023", "tile_id": "t5", "owner": "player_1"}
	_check(VictoryState._count_widest_tiles() == 3,
		"victory widest: counts player non-infra tiles incl. landfill (excludes port + NPC)")
	# 80 distinct player tiles -> (80-30)/200 = 0.25.
	MatchState.reset()
	VictoryState.reset()
	for i in range(80):
		BuildingState.buildings["wt%d" % i] = {"building_id": "b_001", "tile_id": "wtile%d" % i, "owner": "player_1"}
	_check(absf(VictoryState._live_progress("widest") - 0.25) < 0.001,
		"victory widest: 80 tiles maps to 0.25 on the [30,230] ramp")
	MatchState.reset()

func _test_victory_greenest() -> void:
	VictoryState.reset()
	VictoryState._resolve_green_ids()
	# 6000 MW solar of 10000 MW made, 2000 MW used -> share 0.6 -> (0.6-0.2)/0.8 = 0.5.
	VictoryState._last_summary = {"power_supply": 10000, "power_demand": 2000, "power_supply_by_type": {"b_024": {"count": 1, "amount": 6000.0}}}
	_check(absf(VictoryState._live_progress("greenest") - 0.5) < 0.001,
		"victory greenest: 60% green share maps to 0.5")
	# Below the 5000 MW GENERATED gate -> 0 (even fully green, plenty consumed).
	VictoryState._last_summary = {"power_supply": 4000, "power_demand": 3000, "power_supply_by_type": {"b_024": {"count": 1, "amount": 4000.0}}}
	_check(absf(VictoryState._live_progress("greenest")) < 0.001,
		"victory greenest: under 5000 MW generated is gated to 0")
	# Enough generated + green share, but network CONSUMES under 1000 MW -> 0.
	VictoryState._last_summary = {"power_supply": 10000, "power_demand": 500, "power_supply_by_type": {"b_024": {"count": 1, "amount": 6000.0}}}
	_check(absf(VictoryState._live_progress("greenest")) < 0.001,
		"victory greenest: under 1000 MW consumed is gated to 0")
	# Above both gates but below 20% green share -> 0.
	VictoryState._last_summary = {"power_supply": 10000, "power_demand": 2000, "power_supply_by_type": {"b_024": {"count": 1, "amount": 1000.0}}}
	_check(absf(VictoryState._live_progress("greenest")) < 0.001,
		"victory greenest: under 20% green share is gated to 0")

func _test_victory_total_and_win() -> void:
	MatchState.reset()
	VictoryState.reset()
	var fired := [0]
	var on_win := func(_total: int, _turn: int) -> void: fired[0] += 1
	VictoryState.victory_achieved.connect(on_win)
	# One maxed track at turn 105: total 1000 >= the turn-105 bar (1000) -> win latches.
	VictoryState.track_best["richest"] = 1.0
	TurnManager.current_turn = 105
	VictoryState._on_turn_processed({"money_in": 0.0, "money_out": 0.0})
	VictoryState._tick()
	_check(VictoryState.won and VictoryState.won_turn == 105 and fired[0] == 1,
		"victory win: reaching the turn-105 bar (1 track) latches the win, fires once")
	# By turn 300 the bar has risen to 4000; the 1-track total (1000) no longer clears
	# it, but the win stays latched with no second emit.
	TurnManager.current_turn = 300
	VictoryState._on_turn_processed({"money_in": 0.0, "money_out": 0.0})
	VictoryState._tick()
	_check(VictoryState.total_for_turn(300) < VictoryState.win_threshold_for_turn(300)
		and VictoryState.won and fired[0] == 1,
		"victory win: stays latched as the bar rises, with no second emit")
	VictoryState.victory_achieved.disconnect(on_win)

func _test_victory_tick_scores_resolved_turn() -> void:
	# Regression: TurnManager increments current_turn BEFORE emitting
	# turn_resolution_completed, so the tick must score the turn just resolved
	# (captured at turn_processed time), not the already-incremented current_turn.
	MatchState.reset()
	VictoryState.reset()
	TurnManager.current_turn = 100
	VictoryState._on_turn_processed({"money_in": 0.0, "money_out": 0.0})  # summary belongs to turn 100
	VictoryState.track_best["richest"] = 1.0
	TurnManager.current_turn = 101  # the increment that lands before completion fires
	VictoryState._on_turn_resolution_completed()
	var b := VictoryState.get_breakdown()
	# At turn 100 the bar is still 1000 (flat before 105); 1 maxed track (1000) wins.
	_check(int(b["turn"]) == 100 and int(b["win_threshold"]) == 1000
		and VictoryState.won and VictoryState.won_turn == 100,
		"victory tick: scores resolved turn 100 (bar 1000, won_turn 100), not turn 101")

func _test_victory_save_load() -> void:
	VictoryState.reset()
	VictoryState.autarkic_streak = 15
	VictoryState.logistics_total = 120
	VictoryState.logistics_efficient = 90
	VictoryState.richest_window = [5000.0, 6000.0]
	VictoryState.track_best["richest"] = 0.5
	VictoryState.track_best["widest"] = 0.25
	VictoryState.score_history = [{"turn": 10, "total": 3100, "base": 3000, "tracks": {"richest": 0.1}}]
	VictoryState.won = true
	VictoryState.won_turn = 42
	VictoryState.purchases_this_turn["input"] = 3
	VictoryState.purchases_lifetime["input"] = 9
	VictoryState.purchases_lifetime["building"] = 2
	var snap := VictoryState.export_state()
	VictoryState.reset()
	_check(VictoryState.autarkic_streak == 0 and not VictoryState.won, "victory save/load: reset clears state")
	VictoryState.import_state(snap)
	_check(VictoryState.autarkic_streak == 15
		and VictoryState.logistics_total == 120
		and VictoryState.logistics_efficient == 90
		and VictoryState.richest_window.size() == 2
		and absf(float(VictoryState.track_best["richest"]) - 0.5) < 0.001
		and absf(float(VictoryState.track_best["widest"]) - 0.25) < 0.001
		and VictoryState.score_history.size() == 1
		and VictoryState.won and VictoryState.won_turn == 42
		and int(VictoryState.purchases_this_turn["input"]) == 3
		and int(VictoryState.purchases_lifetime["input"]) == 9
		and int(VictoryState.purchases_lifetime["building"]) == 2,
		"victory save/load: export -> reset -> import round-trips every field")
	VictoryState.reset()

func _test_greenest_reads_quality() -> void:
	VictoryState.reset()
	# green = intermittent 3000 + steady 3000 = 6000 of 10000 made, 2000 used -> share 0.6.
	VictoryState._last_summary = {"power_supply": 10000, "power_demand": 2000,
		"power_supply_by_quality": {"green_intermittent": 3000, "green_steady": 3000, "grey": 4000}}
	_check(absf(VictoryState._live_progress("greenest") - 0.5) < 0.001,
		"greenest: reads power_supply_by_quality (steady + intermittent count green)")

# The Itch.io demo length: 100 turns with its own decarbonisation timeline. The campaign
# arc opens at turn 84 and lands the subsidy at 105, so a 100-turn game at campaign timings
# would end before the subsidy exists — which is the whole reason this timeline exists.
func _test_demo_itch_speed() -> void:
	var saved_rules: Dictionary = MatchState.ruleset.duplicate(true)
	var saved_cap: int = TurnManager.MAX_TURNS

	# The length selector reaches the turn cap at all. It used to be collected into the
	# ruleset and never read, so every game ran 300 turns whichever length was chosen.
	TurnManager.apply_ruleset({"speed_turns": 100})
	_check(TurnManager.MAX_TURNS == 100, "demo: speed_turns sets the turn cap")
	TurnManager.apply_ruleset({})
	_check(TurnManager.MAX_TURNS == TurnManager.DEFAULT_MAX_TURNS,
		"demo: a ruleset with no length falls back to the campaign")

	# Campaign timeline unchanged — the demo must not move anyone else's beats.
	MatchState.ruleset = {"name": "standard"}
	_check(PolicyState.timeline_id() == PolicyState.TIMELINE_CAMPAIGN, "demo: default is the campaign timeline")
	_check(PolicyState.beat("election_news") == 84, "campaign: election still turn 84")
	_check(PolicyState.beat("ramp_first") == 91, "campaign: levy still ramps from 91")
	_check(PolicyState.beat("p1") == 101, "campaign: levy still full force at 101")
	_check(PolicyState.beat("subsidy") == 105, "campaign: subsidy still turn 105")
	_check(is_equal_approx(PolicyState.co2_tax_scale(90), 0.0), "campaign: no levy at turn 90")
	_check(PolicyState.co2_tax_level(101) >= 1, "campaign: levy in force at 101")

	# The demo's authored beats (owner, 23 Aug).
	MatchState.ruleset = {"name": "standard", "policy_timeline": PolicyState.TIMELINE_DEMO}
	_check(PolicyState.timeline_id() == PolicyState.TIMELINE_DEMO, "demo: ruleset selects the demo timeline")
	for row: Array in [["election_news", 54], ["tax_notice", 58], ["ramp_first", 65],
			["p1", 75], ["subsidy", 80]]:
		_check(PolicyState.beat(str(row[0])) == int(row[1]),
			"demo: %s on turn %d" % [str(row[0]), int(row[1])])

	# The levy ramp runs 65 -> 75 and nothing before it.
	_check(is_equal_approx(PolicyState.co2_tax_scale(64), 0.0), "demo: no levy at turn 64")
	_check(PolicyState.co2_tax_scale(65) > 0.0, "demo: levy starts biting at 65")
	_check(PolicyState.co2_tax_scale(70) > PolicyState.co2_tax_scale(65), "demo: the levy ramps")
	_check(is_equal_approx(PolicyState.co2_tax_scale(75), 1.0), "demo: levy at full force by 75")
	_check(PolicyState.co2_tax_level(74) == 0, "demo: levy phase 1 not yet in force at 74")
	_check(PolicyState.co2_tax_level(75) >= 1, "demo: levy phase 1 in force at 75")

	# The subsidy arrives inside the demo's 100 turns, which it never did at campaign timings.
	_check(is_zero_approx(PolicyState.green_subsidy_rate(79)), "demo: no subsidy at turn 79")
	_check(PolicyState.green_subsidy_rate(80) > 0.0, "demo: subsidy live at turn 80")
	_check(PolicyState.green_subsidy_rate(100) > 0.0, "demo: subsidy still live at the final turn")

	# Every beat has to land inside the demo, or the player never sees it.
	var inside := true
	for key: String in ["election_news", "insider_first", "insider_last", "tax_notice",
			"ramp_first", "p1", "subsidy_notice", "subsidy"]:
		if PolicyState.beat(key) < 1 or PolicyState.beat(key) > 100:
			inside = false
	_check(inside, "demo: every policy beat falls inside the 100 turns")
	# ...and in the order the story needs.
	_check(PolicyState.beat("election_news") < PolicyState.beat("tax_notice")
		and PolicyState.beat("tax_notice") < PolicyState.beat("ramp_first")
		and PolicyState.beat("ramp_first") < PolicyState.beat("p1")
		and PolicyState.beat("p1") <= PolicyState.beat("subsidy"),
		"demo: election → notice → ramp → full force → subsidy, in that order")

	# The length row itself. Everything above tests what a ruleset DOES; this tests that the
	# only thing that writes one actually says it — the first cut of this shipped a demo
	# timeline nothing could select, because the row was never added to the table.
	var demo_row: Dictionary = {}
	for opt_variant: Variant in NewGamePanel.SPEEDS:
		var opt: Dictionary = opt_variant
		if str(opt.get("id", "")) == NewGamePanel.DEMO_SPEED_ID:
			demo_row = opt
	_check(not demo_row.is_empty(), "demo: the length selector has a Demo - Itch.io row")
	_check(int(demo_row.get("turns", 0)) == 100, "demo: the row is 100 turns long")
	_check(str(demo_row.get("policy_timeline", "")) == PolicyState.TIMELINE_DEMO,
		"demo: the row carries the demo policy timeline")
	_check(str(demo_row.get("victory_set", "")) == "demo_itch",
		"demo: the row carries the demo victory set")
	_check(NewGamePanel.SPEED_DEFAULT_DEMO >= 0
		and NewGamePanel.SPEED_DEFAULT_DEMO < NewGamePanel.SPEEDS.size()
		and str((NewGamePanel.SPEEDS[NewGamePanel.SPEED_DEFAULT_DEMO] as Dictionary).get("id", ""))
			== NewGamePanel.DEMO_SPEED_ID,
		"demo: a demo build starts on the one row it leaves enabled")
	# ...and that a ruleset built from that row moves every system at once.
	var demo_rules := {"speed_turns": int(demo_row.get("turns", 0)),
		"policy_timeline": str(demo_row.get("policy_timeline", "")),
		"victory_set": str(demo_row.get("victory_set", ""))}
	MatchState.ruleset = demo_rules
	TurnManager.apply_ruleset(demo_rules)
	VictoryState.apply_ruleset(demo_rules)
	_check(TurnManager.MAX_TURNS == 100
		and PolicyState.timeline_id() == PolicyState.TIMELINE_DEMO
		and VictoryState.TRACK_ORDER == VictoryState.DEMO_TRACK_ORDER
		and VictoryState.win_threshold_for_turn(100) == 2500,
		"demo: the row's ruleset sets the length, the timeline and the victory set together")

	MatchState.ruleset = saved_rules
	TurnManager.MAX_TURNS = saved_cap
	VictoryState.apply_ruleset(saved_rules)


# ── Demo victory set (owner 2026-08-23; five tracks over 100 turns) ─────────
func _test_demo_victory_tracks() -> void:
	var saved_rules: Dictionary = MatchState.ruleset.duplicate(true)
	var saved_run: Dictionary = Production.last_turn_run.duplicate()

	# The campaign set is the default and stays untouched by any of this.
	VictoryState.apply_ruleset({})
	_check(VictoryState.TRACK_ORDER == VictoryState.CAMPAIGN_TRACK_ORDER,
		"demo victory: a ruleset with no set runs the campaign tracks")
	_check(VictoryState.win_threshold_for_turn(300) == 4000,
		"demo victory: the campaign bar still rises to 4000")

	# The demo set replaces the tracks wholesale, and everything that renders a track
	# reads these tables, so no panel needs to know the names.
	MatchState.ruleset = {"name": "standard", "victory_set": "demo_itch"}
	VictoryState.apply_ruleset(MatchState.ruleset)
	VictoryState.reset()
	_check(VictoryState.TRACK_ORDER == VictoryState.DEMO_TRACK_ORDER
		and VictoryState.TRACK_ORDER.size() == 5,
		"demo victory: the ruleset selects the five demo tracks")
	var named := true
	for key: String in VictoryState.TRACK_ORDER:
		if not (VictoryState.TRACK_NAMES.has(key) and VictoryState.TRACK_EXPLAIN.has(key)
				and VictoryState.TRACK_COLOR_KEYS.has(key) and VictoryState.TRACK_MAX.has(key)):
			named = false
	_check(named, "demo victory: every demo track has a name, an explainer, a colour and a max")

	# The bar does not rise: 2.5 tracks of 1000, at every turn of the demo.
	_check(VictoryState.win_threshold_for_turn(1) == 2500
		and VictoryState.win_threshold_for_turn(65) == 2500
		and VictoryState.win_threshold_for_turn(100) == 2500,
		"demo victory: a flat 2500 bar — 2.5 tracks — whatever the turn")
	var all_1000 := true
	for key: String in VictoryState.TRACK_ORDER:
		if int(VictoryState.TRACK_MAX[key]) != 1000:
			all_1000 = false
	_check(all_1000, "demo victory: each track is worth 1000, so five tracks total 5000")
	# ...and the tunables have to ADD UP to that 1000, or a track that reads as full would
	# score something other than its max and "2.5 tracks" would stop meaning 2500.
	var vs := VictoryState
	var crown_rates_add_up := true
	for place: int in vs.DEMO_CROWN_TURNS_BY_RANK:
		crown_rates_add_up = crown_rates_add_up and (
			int(vs.DEMO_CROWN_TURNS_BY_RANK[place]) * int(vs.DEMO_CROWN_POINTS_BY_RANK[place])
			== vs.DEMO_CROWN_TARGET)
	_check(crown_rates_add_up and vs.DEMO_CROWN_TARGET == 1000,
		"demo arithmetic: 20 turns first, 40 second and 100 third each reach the same 1000")
	_check(vs.DEMO_TIERS.size() * vs.DEMO_TIER_CAP == 1000
		and vs.DEMO_TIER_UNITS * vs.DEMO_TIER_POINTS_PER_UNIT == vs.DEMO_TIER_CAP,
		"demo arithmetic: 5 units x 40 caps a tier at 200, and 5 tiers = 1000")
	_check(vs.DEMO_LONG_HAULS * 100 == 1000, "demo arithmetic: 10 hauls x 100 = 1000")
	_check(int(vs.DEMO_GREEN_TARGET) / 100 * 25 == 1000, "demo arithmetic: 4000 MW at 25 per 100 = 1000")
	_check(vs.DEMO_ESTATE_BUILDINGS * vs.DEMO_ESTATE_POINTS_PER_BUILDING
		+ vs.DEMO_ESTATE_RUNNING_BONUS == 1000,
		"demo arithmetic: 30 buildings x 30 + 100 running bonus = 1000")
	_check(vs.DEMO_WIN_THRESHOLD == 2500 and vs.DEMO_WIN_THRESHOLD * 2 == 5 * 1000,
		"demo arithmetic: the 2500 bar is exactly half of five full tracks")

	# 1 · Crown — podium points, banked: 50 for first, 25 for second, 10 for third, nothing
	# below. Counting POINTS rather than turns is what lets the three places mix and match.
	VictoryState.demo_crown_points = 0
	_check(is_zero_approx(VictoryState._live_progress("crown")), "demo crown: nothing off the podium")
	VictoryState.demo_crown_points = 500
	_check(absf(VictoryState._live_progress("crown") - 0.5) < 0.001,
		"demo crown: 500 points is half the track — ten turns leading, or twenty in second")
	VictoryState.demo_crown_points = VictoryState.DEMO_CROWN_TARGET
	_check(is_equal_approx(VictoryState._live_progress("crown"), 1.0),
		"demo crown: 1000 points tops the track")
	VictoryState.demo_crown_points = VictoryState.DEMO_CROWN_TARGET * 3
	_check(is_equal_approx(VictoryState._live_progress("crown"), 1.0),
		"demo crown: a long run on the podium does not overflow it")
	# The mix the owner asked for: a season split between places has to land on the same
	# 1000 as a season spent wholly at any one of them.
	var mixed: int = 10 * int(VictoryState.DEMO_CROWN_POINTS_BY_RANK[1])
	mixed += 10 * int(VictoryState.DEMO_CROWN_POINTS_BY_RANK[2])
	mixed += 25 * int(VictoryState.DEMO_CROWN_POINTS_BY_RANK[3])
	_check(mixed == VictoryState.DEMO_CROWN_TARGET,
		"demo crown: 10 turns first + 10 second + 25 third also fills it exactly")
	_check(not VictoryState.DEMO_CROWN_POINTS_BY_RANK.has(4),
		"demo crown: fourth place and below pay nothing")

	# 2 · Tiers — 5 units a tier, 40 points each, capped at 200 a tier. Every tier pays
	# separately, so breadth is the ask and depth in one tier cannot substitute.
	VictoryState._last_summary = {"produced": {}}
	_check(is_zero_approx(VictoryState._live_progress("tiers")), "demo tiers: an idle turn scores nothing")
	var raw_good := _a_good_in_tier("raw")
	VictoryState._last_summary = {"produced": {raw_good: 5}}
	_check(absf(VictoryState._live_progress("tiers") - 0.2) < 0.001,
		"demo tiers: one tier at 5 units is a fifth of the track")
	VictoryState._last_summary = {"produced": {raw_good: 500}}
	_check(absf(VictoryState._live_progress("tiers") - 0.2) < 0.001,
		"demo tiers: 500 units of one tier still caps at that tier's 200 points")
	var five_tiers := {}
	for tier: String in VictoryState.DEMO_TIERS:
		five_tiers[_a_good_in_tier(tier)] = 5
	VictoryState._last_summary = {"produced": five_tiers}
	_check(is_equal_approx(VictoryState._live_progress("tiers"), 1.0),
		"demo tiers: 5 units in each of the five tiers tops the track")
	# Power is not a good and must not leak into a tier.
	VictoryState._last_summary = {"produced": {"power": 9999}}
	_check(is_zero_approx(VictoryState._live_progress("tiers")),
		"demo tiers: generating power scores nothing on the goods track")

	# 3 · Distance — 10 shipments that spent longer than 10 turns travelling.
	VictoryState.demo_long_hauls = 0
	VictoryState.record_movement("sell", "output", 10)
	_check(VictoryState.demo_long_hauls == 0, "demo distance: exactly 10 turns is not over 10")
	VictoryState.record_movement("sell", "output", 11)
	VictoryState.record_movement("move", "output", 30)
	_check(VictoryState.demo_long_hauls == 2, "demo distance: any long movement counts, sold or moved")
	_check(absf(VictoryState._live_progress("distance") - 0.2) < 0.001,
		"demo distance: 2 of 10 hauls is a fifth of the track")
	VictoryState.demo_long_hauls = 10
	_check(is_equal_approx(VictoryState._live_progress("distance"), 1.0),
		"demo distance: 10 long hauls tops the track")

	# 4 · Green — 4000 MW of wind and solar IN ONE TURN. Deliberately not cumulative.
	VictoryState._last_summary = {"power_supply": 4000,
		"power_supply_by_quality": {"green_intermittent": 2000.0, "green_steady": 0.0}}
	_check(absf(VictoryState._live_progress("green_demo") - 0.5) < 0.001,
		"demo green: 2000 MW of green is half the track")
	VictoryState._last_summary = {"power_supply": 9000,
		"power_supply_by_quality": {"green_intermittent": 4000.0, "green_steady": 0.0}}
	_check(is_equal_approx(VictoryState._live_progress("green_demo"), 1.0),
		"demo green: 4000 MW in a turn tops the track")
	VictoryState._last_summary = {"power_supply": 9000,
		"power_supply_by_quality": {"green_intermittent": 0.0, "green_steady": 0.0}}
	_check(is_zero_approx(VictoryState._live_progress("green_demo")),
		"demo green: a turn of coal scores nothing, however much it generates")

	# 5 · Estate — 30 non-infrastructure buildings owned, plus 100 for having them all run.
	MatchState.reset()
	MatchState.ruleset = {"name": "standard", "victory_set": "demo_itch"}
	VictoryState.apply_ruleset(MatchState.ruleset)
	Production.last_turn_run.clear()
	var max_points := (VictoryState.DEMO_ESTATE_BUILDINGS * VictoryState.DEMO_ESTATE_POINTS_PER_BUILDING
		+ VictoryState.DEMO_ESTATE_RUNNING_BONUS)
	_check(is_zero_approx(VictoryState._live_progress("estate")), "demo estate: no buildings, no points")
	for i in range(15):
		BuildingState.buildings["e%d" % i] = {"building_id": "b_001", "tile_id": "et%d" % i, "owner": "player_1"}
	_check(absf(VictoryState._live_progress("estate") - (15.0 * 30.0) / float(max_points)) < 0.001,
		"demo estate: 15 idle buildings score 450 of 1000")
	# The port is infrastructure: owning it must not move the track.
	BuildingState.buildings["eport"] = {"building_id": "b_004", "tile_id": "etport", "owner": "player_1"}
	_check(absf(VictoryState._live_progress("estate") - (15.0 * 30.0) / float(max_points)) < 0.001,
		"demo estate: infrastructure is not part of the estate")
	# A rival's 30 buildings are not yours either.
	for i in range(30):
		BuildingState.buildings["r%d" % i] = {"building_id": "b_001", "tile_id": "rt%d" % i, "owner": "ai_corp"}
	_check(absf(VictoryState._live_progress("estate") - (15.0 * 30.0) / float(max_points)) < 0.001,
		"demo estate: a rival's estate is not counted")
	for i in range(15, 30):
		BuildingState.buildings["e%d" % i] = {"building_id": "b_001", "tile_id": "et%d" % i, "owner": "player_1"}
	_check(absf(VictoryState._live_progress("estate") - 900.0 / float(max_points)) < 0.001,
		"demo estate: 30 owned but idle is 900 — the last 100 is for running them")
	for i in range(30):
		Production.last_turn_run["e%d" % i] = true
	_check(is_equal_approx(VictoryState._live_progress("estate"), 1.0),
		"demo estate: 30 owned AND running tops the track")

	# Two and a half tracks is a win at turn 100; two is not.
	VictoryState.reset()
	VictoryState.track_best["crown"] = 1.0
	VictoryState.track_best["tiers"] = 1.0
	_check(VictoryState.total_for_turn(100) == 2000
		and VictoryState.total_for_turn(100) < VictoryState.win_threshold_for_turn(100),
		"demo victory: two maxed tracks fall short at turn 100")
	VictoryState.track_best["distance"] = 0.5
	_check(VictoryState.total_for_turn(100) == 2500
		and VictoryState.total_for_turn(100) >= VictoryState.win_threshold_for_turn(100),
		"demo victory: two and a half tracks wins at turn 100")

	# The counters survive a save, or a demo run reloaded is a demo run reset.
	VictoryState.demo_crown_points = 350
	VictoryState.demo_long_hauls = 3
	var snapshot: Dictionary = VictoryState.export_state()
	VictoryState.reset()
	_check(VictoryState.demo_crown_points == 0 and VictoryState.demo_long_hauls == 0,
		"demo victory: reset clears the demo counters")
	VictoryState.import_state(snapshot)
	_check(VictoryState.demo_crown_points == 350 and VictoryState.demo_long_hauls == 3,
		"demo victory: the demo counters round-trip through a save")
	# Saves written before the Crown paid by place hold a first-place TURN count, not points.
	VictoryState.import_state({"demo_crown_turns": 7})
	_check(VictoryState.demo_crown_points == 7 * int(VictoryState.DEMO_CROWN_POINTS_BY_RANK[1]),
		"demo victory: an older save's crown turns convert to points on load")
	VictoryState.import_state(snapshot)

	# Back to the campaign, and nothing of the demo is left behind.
	MatchState.reset()
	MatchState.ruleset = saved_rules
	VictoryState.apply_ruleset(saved_rules)
	VictoryState.reset()
	Production.last_turn_run = saved_run
	_check(VictoryState.TRACK_ORDER == VictoryState.CAMPAIGN_TRACK_ORDER,
		"demo victory: leaving the demo restores the campaign tracks")

# ── The demo's five endings (owner 2026-08-23) ──────────────────────────────
func _test_demo_endings() -> void:
	var saved_rules: Dictionary = MatchState.ruleset.duplicate(true)
	var EGD := EndGameData

	# Precedence, not a score-band lookup: the conditions overlap and the first match wins.
	_check(EGD.demo_ending_id(5, 5000, true) == "bankruptcy",
		"demo ending: bankruptcy outranks everything, including a full ledger")
	_check(EGD.demo_ending_id(0, 0, true) == "bankruptcy",
		"demo ending: bankruptcy does not care about the score")
	_check(EGD.demo_ending_id(4, 4000, false) == "full_ledger",
		"demo ending: 4 tracks is the full ledger")
	_check(EGD.demo_ending_id(5, 5000, false) == "full_ledger",
		"demo ending: 5 tracks is still the full ledger")
	_check(EGD.demo_ending_id(3, 3200, false) != "full_ledger",
		"demo ending: 3 tracks is not the full ledger")

	# Jack of all trades — points WITHOUT a completed track. One finished track disqualifies
	# it however high the score, which is the whole point of the ending.
	_check(EGD.demo_ending_id(0, 2000, false) == "jack_of_all_trades",
		"demo ending: 2000 points and no track is the jack of all trades")
	_check(EGD.demo_ending_id(0, 2400, false) == "jack_of_all_trades",
		"demo ending: still the jack well above 2000")
	_check(EGD.demo_ending_id(1, 2400, false) == "sequel",
		"demo ending: one finished track disqualifies the jack")
	_check(EGD.demo_ending_id(0, 1999, false) == "sequel",
		"demo ending: a point short of 2000 is the sequel, not the jack")

	# The two score bands either side of 500.
	_check(EGD.demo_ending_id(0, 501, false) == "sequel", "demo ending: 501 points is the sequel")
	_check(EGD.demo_ending_id(0, 500, false) == "lukewarm",
		"demo ending: exactly 500 falls to the lukewarm follow-up")
	_check(EGD.demo_ending_id(0, 499, false) == "lukewarm", "demo ending: 499 points is lukewarm")
	_check(EGD.demo_ending_id(0, 0, false) == "lukewarm", "demo ending: a scoreless run is lukewarm")

	# Every ending is reachable, and every one is complete.
	var reachable: Dictionary = {}
	for row: Array in [[5, 5000, true], [4, 4000, false], [0, 2000, false],
			[0, 900, false], [0, 10, false]]:
		reachable[EGD.demo_ending_id(int(row[0]), int(row[1]), bool(row[2]))] = true
	_check(reachable.size() == EGD.DEMO_ENDINGS.size(),
		"demo ending: every authored ending is reachable")
	var complete := true
	for id in EGD.DEMO_ENDINGS:
		var e: Dictionary = EGD.DEMO_ENDINGS[id]
		if str(e.get("title", "")) == "" or str(e.get("copy", "")) == "":
			complete = false
		if not (str(e.get("result", "")) in ["victory", "continuity", "defeat"]):
			complete = false
	_check(complete, "demo ending: every ending has a title, a verdict and its copy")

	# Per-start copy: three endings speak in the Metal Magnate's voice (the inherited
	# father), which is not the Glass Merchant's story. Overrides swap those and only those.
	var scenario_saved: String = MatchState.scenario_name
	MatchState.scenario_name = "metal_magnate"
	for id in EGD.DEMO_ENDINGS:
		_check(EGD.ending_copy(str(id)) == str((EGD.DEMO_ENDINGS[id] as Dictionary).copy),
			"ending copy: a start with no overrides gets the authored default (%s)" % str(id))
	MatchState.scenario_name = "glass_merchant"
	var glass_overrides: Dictionary = EGD.START_ENDING_COPY["glass_merchant"]
	for id in EGD.DEMO_ENDINGS:
		var copy: String = EGD.ending_copy(str(id))
		_check(copy != "", "ending copy: the glass merchant has copy for every ending (%s)" % str(id))
		if glass_overrides.has(id):
			_check(copy == str(glass_overrides[id]),
				"ending copy: the glass merchant's own words are used (%s)" % str(id))
			_check(not ("father" in copy.to_lower()),
				"ending copy: no inherited father in the glass merchant's ending (%s)" % str(id))
		else:
			_check(copy == str((EGD.DEMO_ENDINGS[id] as Dictionary).copy),
				"ending copy: start-agnostic endings are left alone (%s)" % str(id))
	# Every override must name an ending that actually exists, or it can never be shown.
	for start_id in EGD.START_ENDING_COPY:
		for id in (EGD.START_ENDING_COPY[start_id] as Dictionary):
			_check(EGD.DEMO_ENDINGS.has(id),
				"ending copy: override '%s' targets a real ending (%s)" % [str(start_id), str(id)])
	MatchState.scenario_name = scenario_saved

	# The endings follow the TRACKS. A campaign match keeps the campaign's titles.
	MatchState.ruleset = {"name": "standard"}
	VictoryState.apply_ruleset(MatchState.ruleset)
	_check(not EGD.demo_endings_apply(), "demo ending: a campaign match does not use them")

	MatchState.ruleset = {"name": "standard", "victory_set": "demo_itch",
		"speed_turns": 100, "policy_timeline": "demo_itch"}
	VictoryState.apply_ruleset(MatchState.ruleset)
	TurnManager.apply_ruleset(MatchState.ruleset)
	VictoryState.reset()
	_check(EGD.demo_endings_apply(), "demo ending: a demo match does")

	# Through the real assembler: a run with points banked but no track finished.
	VictoryState.track_best["crown"] = 0.8
	VictoryState.track_best["tiers"] = 0.7
	VictoryState.track_best["distance"] = 0.6
	var jack: Dictionary = EGD.gather()
	_check(str(jack.get("ending_id", "")) == "jack_of_all_trades"
		and str(jack.get("title", "")) == "The Jack of All Trades",
		"demo ending: gather() names the jack of all trades")
	_check((jack.get("copy", []) as Array).size() == 1
		and str((jack.get("copy", []) as Array)[0]).begins_with("You've taken a business"),
		"demo ending: the jack's copy is the owner's, in one paragraph")
	_check(str(jack.get("epithet", "")).contains("no track secured")
		and str(jack.get("epithet", "")).contains("2,100"),
		"demo ending: the epithet carries the figures the copy leaves out")
	# 2,100 is short of the 2,500 bar, so the banner must NOT read VICTORY over it.
	_check(not bool(jack.get("won", true)) and str(jack.get("result", "")) == "continuity",
		"demo ending: a jack short of the bar is not stamped a victory")
	# ...but one that crosses it is.
	VictoryState.track_best["green_demo"] = 1.0
	VictoryState.won = true
	var jack_won: Dictionary = EGD.gather()
	_check(str(jack_won.get("result", "")) == "victory",
		"demo ending: crossing the bar makes any ending a victory")
	VictoryState.won = false

	# ...and one with four tracks home.
	VictoryState.reset()
	for key: String in ["crown", "tiers", "distance", "green_demo"]:
		VictoryState.track_best[key] = 1.0
	var full: Dictionary = EGD.gather()
	_check(str(full.get("ending_id", "")) == "full_ledger"
		and str(full.get("title", "")) == "The Full Ledger"
		and str(full.get("result", "")) == "victory",
		"demo ending: four tracks home is the full ledger, and a victory")
	_check(int(full.get("secured_count", 0)) == 4 and int(full.get("total", 0)) == 4000,
		"demo ending: the full ledger's figures agree with the tracks")

	# A losing turn must not stamp DEFEAT over copy that reads as a compliment.
	VictoryState.reset()
	VictoryState.track_best["crown"] = 0.9
	var sequel: Dictionary = EGD.gather()
	_check(str(sequel.get("ending_id", "")) == "sequel"
		and str(sequel.get("result", "")) == "continuity",
		"demo ending: the sequel is never shown under DEFEAT")
	# The lukewarm one, by contrast, is authored as the downbeat verdict and keeps it.
	VictoryState.reset()
	VictoryState.track_best["crown"] = 0.3
	var luke: Dictionary = EGD.gather()
	_check(str(luke.get("ending_id", "")) == "lukewarm"
		and str(luke.get("result", "")) == "defeat",
		"demo ending: the lukewarm follow-up keeps its downbeat verdict")

	# Bankruptcy is the fifth ending and has its own screen — the charts one SolvencyState
	# mounts mid-game, not the turn-100 end screen. It reads the same table.
	var panel: Object = (load("res://scripts/game_over_panel.gd") as GDScript).new()
	_check(str(panel.call("_ending_title")) == "Bankruptcy"
		and str(panel.call("_ending_body")).begins_with("Nothing more to say."),
		"demo ending: the bankruptcy screen carries the demo ending")
	MatchState.ruleset = {"name": "standard"}
	VictoryState.apply_ruleset(MatchState.ruleset)
	_check(str(panel.call("_ending_title")) == "Your legacy ends here",
		"demo ending: a campaign bankruptcy keeps the campaign copy")
	panel.free()

	MatchState.ruleset = saved_rules
	VictoryState.apply_ruleset(saved_rules)
	VictoryState.reset()
