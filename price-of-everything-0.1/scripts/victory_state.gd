extends Node

# VictoryState (autoload) — the single source of truth for the victory score.
#
# Score = five independent TRACK scores (Autarkic, Logistics, Richest, Widest,
# Greenest), each 0..1000, stored best-ever (monotonic — bars only fill up). You
# START AT 0. The RISING WIN BAR is the time pressure: the points needed to win
# climb from 1 maxed track at turn 105 to 4 maxed tracks by turn 300 (one extra
# track per 65 turns), so a fast finish needs fewer tracks. It recomputes once per
# turn and latches a win the first turn `total >= win_threshold_for_turn(turn)`.
# See docs/victory-system-spec.md for the full design.
#
# Wiring (all reads, never writes sim state — UI is read-only, rule #5):
#   Production.turn_processed(summary)            -> cache the turn's economics
#   TurnManager.turn_resolution_completed         -> recompute + win check (the tick)
#   MatchState.goods_movement_recorded(k,c,turns) -> Logistics + Autarky live feed
#   MatchState.state_reset                        -> reset() on new game / pre-load
#
# Saves round-trip via export_state()/import_state(); SaveLoad owns the snapshot.

# ── Tunables — all victory balance lives here (spec §10) ───────────────────
# The RISING WIN BAR (owner 2026-07-11): you start at 0 points and the points needed
# to win climb from WIN_MIN_THRESHOLD (1 maxed track) at WIN_START_TURN to
# WIN_MAX_THRESHOLD (4 maxed tracks) at MAX_TURNS — one extra required track per
# WIN_STEP_TURNS. Milestones: turn 105 → 1 track, 170 → 2, 235 → 3, 300 → 4.
const WIN_MIN_THRESHOLD := 1000   # 1 maxed track — winnable from turn 105 (flat before)
const WIN_MAX_THRESHOLD := 4000   # 4 maxed tracks — required by turn 300
const WIN_START_TURN := 105       # the bar is flat at 1 track until here, then rises
const WIN_STEP_TURNS := 65        # turns per additional required track (105→170→235→300)
const WIN_STEP_POINTS := 1000     # points per additional required track
## The match length. Was a const 300, which was true of every match until the length
## selector became real — a 100-turn demo then showed "turn 7 of 300" in the victory panel
## while the top bar counted to 100. Read through, so there is one answer.
var MAX_TURNS: int:
	get:
		return TurnManager.MAX_TURNS

const CAMPAIGN_TRACK_MAX := {
	"autarkic": 1000, "logistics": 1000, "richest": 1000,
	"widest": 1000, "greenest": 1000,
}
# Display order: 3 on the top row + 2 below, in the panel.
const CAMPAIGN_TRACK_ORDER: Array = ["autarkic", "logistics", "richest", "widest", "greenest"]

const AUTARKIC_START := 10
const AUTARKIC_CAP := 30
# Minimum-scale gate: the Autarkic track only scores once you've actually self-supplied at
# volume — a real, buy-nothing economy, not an idle one that trivially "buys nothing". Until
# the player has produced this many units in total, the track contributes 0.
const AUTARKIC_MIN_UNITS := 10000
const LOGI_MIN_MOVES := 100  # moves THIS TURN before the track scores (per-turn, owner 2026-07-10)
const LOGI_EFF_TURNS := 1
const LOGI_FLOOR := 0.25
const RICHEST_WINDOW := 5
const RICHEST_LO := 2000.0
const RICHEST_HI := 12000.0
const WIDEST_LO := 30
const WIDEST_HI := 230
const GREEN_MIN_POWER := 5000      # MW your network must GENERATE/turn before the % counts
const GREEN_MIN_CONSUMED := 1000   # MW your network must CONSUME/turn before the % counts
const GREEN_FLOOR := 0.20
const GREEN_BUILDINGS: Array = ["solar_farm", "onshore_wind_farm", "offshore_wind_farm"]
const PURCHASE_CATEGORIES: Array = ["input", "building", "upgrade", "other"]
const TREND_LEN := 10

# Per-track display metadata. Colours are DS.PALETTE *keys* (resolved by the UI,
# since the sim has no theme); the panel/widget read these from the breakdown.
const CAMPAIGN_TRACK_NAMES := {
	"autarkic": "Autarkic", "logistics": "Logistics", "richest": "Richest",
	"widest": "Widest", "greenest": "Greenest",
}
const CAMPAIGN_TRACK_COLOR_KEYS := {
	"autarkic": "WARN", "logistics": "ACCENT", "richest": "OK",
	"widest": "ACTION_BLUE_TOP", "greenest": "OK",
}
const CAMPAIGN_TRACK_EXPLAIN := {
	"autarkic": "Consecutive turns buying nothing from the market — source every input, build & upgrade material yourself. Power is exempt: draw from the grid freely, and generated MW don't count toward the unlock.",
	"logistics": "Share of this turn's goods movements arriving in 1 turn or less — extend rail/pipe so deliveries are instant. Power isn't shipped, so electricity never counts.",
	"richest": "Sustained post-tax profit, smoothed over recent turns — keep margins high turn after turn.",
	"widest": "Distinct tiles holding one of your (non-infrastructure) buildings — spread out across the map.",
	"greenest": "Green share of the power you generate — replace fossil plants with solar & wind. Counts once your network generates 5,000 MW and draws 1,000 MW per turn.",
}

# ── Demo victory set (owner, 23 Aug) ───────────────────────────────────────
#
# The campaign tracks are written for 300 turns: they measure sustained states — a buying
# streak, a profit average, a green SHARE — that a 100-turn demo has no room to build. The
# demo set asks for reachable milestones instead, and every one of them is a thing the
# player can see themselves doing.
#
# Each track still maxes at TRACK_MAX (1000), so the shapes downstream are unchanged and
# the arithmetic the owner specified lands exactly on it:
#   crown     20 turns x 50            = 1000
#   tiers     5 tiers x 200 cap        = 1000
#   distance  10 shipments x 100       = 1000
#   green     4000 power / 100 x 25    = 1000
#   estate    30 buildings x 30 + 100  = 1000
const DEMO_TRACK_ORDER: Array = ["crown", "tiers", "distance", "green_demo", "estate"]
const DEMO_TRACK_NAMES := {
	"crown": "Crown", "tiers": "Tiers", "distance": "Distance",
	"green_demo": "Green", "estate": "Estate",
}
## One tone each, so five meters side by side are told apart at a glance — the campaign
## set repeats OK twice and gets away with it because its two green tracks are never
## adjacent; these five are. All five are light tones: ACTION_BLUE_TOP is dark enough on
## the panel navy that a half-filled meter barely reads as filled at all.
const DEMO_TRACK_COLOR_KEYS := {
	"crown": "WARN", "tiers": "ACCENT", "distance": "TEXT_MUTED",
	"green_demo": "OK", "estate": "BUTTON_RIM_LIGHT",
}
const DEMO_TRACK_EXPLAIN := {
	"crown": "Turns spent top of the revenue ranking. Cumulative — a turn at the top is banked and never lost, so 20 of them wins the track however they are spread.",
	"tiers": "Units produced this turn in each tier, up to 5 a tier. Every tier pays, so a broad chain beats a deep one — five units of each of the five tiers fills it.",
	"distance": "Shipments delivered over a journey of more than 10 turns. Cumulative, and long hauls only: ten of them fills the track.",
	"green_demo": "Wind and solar generated THIS TURN. It does not accumulate between turns — your best single turn is what stands, and 4,000 MW fills it.",
	"estate": "Non-infrastructure buildings you own, up to 30, plus a bonus once 30 or more are running at once.",
}
## The demo's flat win bar: 2.5 maxed tracks, and it does not rise (owner). A 100-turn
## game has no room for a bar that climbs — the campaign's reaches 2 tracks only at turn
## 170, so a rising bar inside 100 turns would either never move or move meaninglessly.
const DEMO_WIN_THRESHOLD := 2500

## Every demo track is worth exactly 1000, which is what makes "2.5 tracks" a round 2500:
##   crown    20 turns x 50            = 1000
##   tiers    5 tiers x 200 a tier     = 1000
##   distance 10 hauls x 100           = 1000
##   green    4000 MW / 100 x 25       = 1000
##   estate   30 buildings x 30 + 100  = 1000
## The numbers below are the owner's (23 Aug); the equalities above are pinned by the suite.
const DEMO_CROWN_TURNS := 20        # turns at the top of the revenue ranking to fill it
const DEMO_CROWN_POINTS_PER_TURN := 50
const DEMO_TIER_UNITS := 5          # units per tier per turn that pay
const DEMO_TIER_POINTS_PER_UNIT := 40
const DEMO_TIER_CAP := 200          # per tier, per turn
const DEMO_LONG_HAUL_TURNS := 10    # a shipment must beat this to count
const DEMO_LONG_HAULS := 10         # ...and this many fill the track
const DEMO_GREEN_TARGET := 4000.0   # MW of wind+solar in ONE turn
const DEMO_ESTATE_BUILDINGS := 30
const DEMO_ESTATE_POINTS_PER_BUILDING := 30
const DEMO_ESTATE_RUNNING_BONUS := 100
## The tier bands, in the order the goods CSV names them.
const DEMO_TIERS: Array[String] = ["raw", "processed", "intermediate", "finished", "apex"]

# ── The live track set ─────────────────────────────────────────────────────
#
# VARIABLES, not constants: a match picks its set from the ruleset, and everything that
# renders a track — the top bar's meters, the victory panel, the end screen, telemetry —
# reads these rather than knowing the names, so a different set needs no changes there.
var TRACK_ORDER: Array = CAMPAIGN_TRACK_ORDER.duplicate()
var TRACK_MAX: Dictionary = CAMPAIGN_TRACK_MAX.duplicate()
var TRACK_NAMES: Dictionary = CAMPAIGN_TRACK_NAMES.duplicate()
var TRACK_COLOR_KEYS: Dictionary = CAMPAIGN_TRACK_COLOR_KEYS.duplicate()
var TRACK_EXPLAIN: Dictionary = CAMPAIGN_TRACK_EXPLAIN.duplicate()
var _demo_rules := false

## Point the track tables at the set this match runs. Called whenever the ruleset lands
## (new game and load alike), so a save carries its own answer.
func apply_ruleset(rules: Dictionary) -> void:
	_demo_rules = str(rules.get("victory_set", "")) == "demo_itch"
	TRACK_ORDER = (DEMO_TRACK_ORDER if _demo_rules else CAMPAIGN_TRACK_ORDER).duplicate()
	TRACK_NAMES = (DEMO_TRACK_NAMES if _demo_rules else CAMPAIGN_TRACK_NAMES).duplicate()
	TRACK_COLOR_KEYS = (DEMO_TRACK_COLOR_KEYS if _demo_rules else CAMPAIGN_TRACK_COLOR_KEYS).duplicate()
	TRACK_EXPLAIN = (DEMO_TRACK_EXPLAIN if _demo_rules else CAMPAIGN_TRACK_EXPLAIN).duplicate()
	TRACK_MAX = {}
	for key in TRACK_ORDER:
		TRACK_MAX[key] = int(CAMPAIGN_TRACK_MAX.get(key, 1000))

# ── Saved state (round-trips via export/import — spec §3) ──────────────────
var autarkic_streak: int = 0
var produced_units_lifetime: int = 0     # cumulative units produced (Autarkic scale gate)
var logistics_total: int = 0             # movements THIS TURN (reset each tick — per-turn track)
var logistics_efficient: int = 0         # ...of which arrived in <= LOGI_EFF_TURNS
var richest_window: Array = []           # trailing retained-profit buffer (<= RICHEST_WINDOW)
var track_best: Dictionary = {}          # track key -> best-ever progress (0..1)
var score_history: Array = []            # last TREND_LEN snapshots {turn,total,base,tracks{}}
var won: bool = false
var won_turn: int = 0
var purchases_this_turn: Dictionary = {} # category -> count (reset each turn)
var purchases_lifetime: Dictionary = {}  # category -> cumulative count
# End-of-game history for the Victory / Defeat screen (per-turn series + lifetime
# per-good production + the turn each track was first secured). Bounded to MAX_TURNS.
var history_revenue: Array = []          # per-turn goods+power sales revenue (£)
var history_output: Array = []           # per-turn produced GOODS units (power excluded)
var history_buildings: Array = []        # per-turn standing player building count
var produced_by_good: Dictionary = {}    # good_id -> lifetime units produced (power excluded)
var track_secured_turn: Dictionary = {}  # track key -> turn its best first hit 1.0

# ── Transient (not saved) ──────────────────────────────────────────────────
var _last_summary: Dictionary = {}       # cached from Production.turn_processed
var _scored_turn: int = 1                # the turn _last_summary belongs to (captured
                                         # during PROCESS, before TurnManager increments)
var _last_breakdown: Dictionary = {}     # what get_breakdown() serves between ticks
var _green_ids: Array = []               # building_ids resolved from GREEN_BUILDINGS

# Demo counters. Only these two accumulate; the other three demo tracks are read fresh
# from the turn and kept by the same monotonic track_best the campaign uses.
var demo_crown_turns: int = 0            # turns finished top of the revenue ranking
var demo_long_hauls: int = 0             # shipments delivered over a long journey

signal score_changed(total: int, breakdown: Dictionary)
signal victory_achieved(total: int, turn: int)

func _ready() -> void:
	_reset_fields()
	_resolve_green_ids()
	Production.turn_processed.connect(_on_turn_processed)
	TurnManager.turn_resolution_completed.connect(_on_turn_resolution_completed)
	MatchState.goods_movement_recorded.connect(_on_goods_movement_recorded)
	MatchState.state_reset.connect(reset)
	_refresh_breakdown()

# ── Public API ─────────────────────────────────────────────────────────────

# Everything the UI renders (spec §8.3). Cached at the last tick; base is constant
# between ticks (turn only changes on resolution) so the cache stays valid.
func get_breakdown() -> Dictionary:
	if _last_breakdown.is_empty():
		_refresh_breakdown()
	return _last_breakdown

## Tutorial turns teach the systems without advancing or satisfying victory tracks.
## The terminal End tutorial action clears the ruleset flag and resets this state.
func conditions_enabled() -> bool:
	return not bool(MatchState.ruleset.get("tutorial_enabled", false))

# Points needed to win at a given turn — the RISING BAR (owner 2026-07-11). Flat at
# WIN_MIN_THRESHOLD until WIN_START_TURN, then +WIN_STEP_POINTS per WIN_STEP_TURNS,
# capped at WIN_MAX_THRESHOLD. Public for tests.
func win_threshold_for_turn(turn: int) -> int:
	if _demo_rules:
		return DEMO_WIN_THRESHOLD   # flat: 2.5 tracks, whatever the turn
	var steps := float(maxi(0, turn - WIN_START_TURN)) / float(WIN_STEP_TURNS)
	return int(clampf(float(WIN_MIN_THRESHOLD) + steps * float(WIN_STEP_POINTS),
		float(WIN_MIN_THRESHOLD), float(WIN_MAX_THRESHOLD)))

# total = Σ round(best_progress * TRACK_MAX). You start at 0 — no base. Public for tests.
func total_for_turn(_turn: int = 0) -> int:
	var total := 0
	for key in TRACK_ORDER:
		total += int(round(float(track_best.get(key, 0.0)) * float(TRACK_MAX[key])))
	return total

# Logistics + Autarky live feed (spec §4.2 / §5.1 / §5.2). Called by the
# goods_movement_recorded signal handler, and directly by tests. Logistics
# counters are per-turn: they accumulate during the turn and reset at the tick.
func record_movement(kind: String, category: String, transport_turns: int) -> void:
	if not conditions_enabled():
		return
	logistics_total += 1
	# Demo Distance track: a shipment that spent longer than DEMO_LONG_HAUL_TURNS on the
	# road. Counted for every kind of movement — a long haul is a long haul whether the
	# goods were sold, moved or bought.
	if transport_turns > DEMO_LONG_HAUL_TURNS:
		demo_long_hauls += 1
	if transport_turns <= LOGI_EFF_TURNS:
		logistics_efficient += 1
	# Only market BUYS break the Autarkic streak; moves & sales never do.
	if kind == "buy":
		var c: String = category if category in PURCHASE_CATEGORIES else "other"
		purchases_this_turn[c] = int(purchases_this_turn.get(c, 0)) + 1
		purchases_lifetime[c] = int(purchases_lifetime.get(c, 0)) + 1

func reset() -> void:
	_reset_fields()
	# state_reset fires on new game AND just before a load overwrites us via
	# import_state. Either way, publishing a fresh-state score keeps the UI synced.
	_emit_refresh()

func export_state() -> Dictionary:
	return {
		"autarkic_streak": autarkic_streak,
		"produced_units_lifetime": produced_units_lifetime,
		"logistics_total": logistics_total,
		"logistics_efficient": logistics_efficient,
		"richest_window": richest_window.duplicate(),
		"track_best": track_best.duplicate(true),
		"score_history": score_history.duplicate(true),
		"won": won,
		"won_turn": won_turn,
		"purchases_this_turn": purchases_this_turn.duplicate(),
		"purchases_lifetime": purchases_lifetime.duplicate(),
		"history_revenue": history_revenue.duplicate(),
		"history_output": history_output.duplicate(),
		"history_buildings": history_buildings.duplicate(),
		"produced_by_good": produced_by_good.duplicate(),
		"track_secured_turn": track_secured_turn.duplicate(),
		"demo_crown_turns": demo_crown_turns,
		"demo_long_hauls": demo_long_hauls,
	}

func import_state(d: Dictionary) -> void:
	_reset_fields()
	autarkic_streak = int(d.get("autarkic_streak", 0))
	produced_units_lifetime = int(d.get("produced_units_lifetime", 0))
	logistics_total = int(d.get("logistics_total", 0))
	logistics_efficient = int(d.get("logistics_efficient", 0))
	for v in (d.get("richest_window", []) as Array):
		richest_window.append(float(v))
	while richest_window.size() > RICHEST_WINDOW:
		richest_window.pop_front()
	var tb: Dictionary = d.get("track_best", {})
	for k in TRACK_ORDER:
		track_best[k] = clampf(float(tb.get(k, 0.0)), 0.0, 1.0)
	for snap in (d.get("score_history", []) as Array):
		if snap is Dictionary:  # tolerate a corrupted/hand-edited save without crashing
			score_history.append((snap as Dictionary).duplicate(true))
	while score_history.size() > TREND_LEN:
		score_history.pop_front()
	won = bool(d.get("won", false))
	won_turn = int(d.get("won_turn", 0))
	var pt: Dictionary = d.get("purchases_this_turn", {})
	var pl: Dictionary = d.get("purchases_lifetime", {})
	for c in PURCHASE_CATEGORIES:
		purchases_this_turn[c] = int(pt.get(c, 0))
		purchases_lifetime[c] = int(pl.get(c, 0))
	for v in (d.get("history_revenue", []) as Array):
		history_revenue.append(float(v))
	for v in (d.get("history_output", []) as Array):
		history_output.append(int(v))
	for v in (d.get("history_buildings", []) as Array):
		history_buildings.append(int(v))
	var pbg: Dictionary = d.get("produced_by_good", {})
	for g in pbg:
		produced_by_good[str(g)] = int(pbg[g])
	demo_crown_turns = int(d.get("demo_crown_turns", 0))
	demo_long_hauls = int(d.get("demo_long_hauls", 0))
	var tst: Dictionary = d.get("track_secured_turn", {})
	for k in tst:
		track_secured_turn[str(k)] = int(tst[k])
	# Don't re-fire victory_achieved on load (spec §6 edge); just publish the state.
	_emit_refresh()

# ── Signal handlers ─────────────────────────────────────────────────────────

func _on_turn_processed(summary: Dictionary) -> void:
	if not conditions_enabled():
		_last_summary = {}
		return
	# Fires during PROCESS, while TurnManager.current_turn still equals the turn
	# being resolved (it increments only after all phases). Capture it now so the
	# scoring tick (on turn_resolution_completed, after the increment) scores the
	# turn whose economics this summary describes.
	_scored_turn = TurnManager.current_turn
	_last_summary = summary

func _on_turn_resolution_completed() -> void:
	_tick()

func _on_goods_movement_recorded(kind: String, category: String, transport_turns: int) -> void:
	record_movement(kind, category, transport_turns)

# ── The per-turn scoring tick ───────────────────────────────────────────────

func _tick() -> void:
	if not conditions_enabled():
		# Discard transient counters so turning victory back on starts from a clean turn,
		# even if this match was loaded from a tutorial save made by an older build.
		_last_summary = {}
		for c in PURCHASE_CATEGORIES:
			purchases_this_turn[c] = 0
		logistics_total = 0
		logistics_efficient = 0
		_emit_refresh()
		return
	# Score the turn just resolved (NOT TurnManager.current_turn, which has already
	# ticked to the next turn by the time turn_resolution_completed fires).
	var turn: int = _scored_turn
	# Autarkic: any market buy this turn (any category) resets the streak.
	var bought_any := false
	for c in PURCHASE_CATEGORIES:
		if int(purchases_this_turn.get(c, 0)) > 0:
			bought_any = true
			break
	autarkic_streak = 0 if bought_any else autarkic_streak + 1
	# Autarkic scale gate: accumulate this turn's produced GOODS units (the streak only
	# starts scoring once lifetime production clears AUTARKIC_MIN_UNITS). POWER is ignored
	# — the Autarkic track doesn't care about electricity, so generating MW never inflates
	# the gate and drawing from the grid never breaks the streak (grid draws aren't market
	# buys, so they're already exempt above).
	var produced: Dictionary = _last_summary.get("produced", {})
	var turn_output := 0
	for good_id in produced:
		if str(good_id) == "power":
			continue
		var q := int(produced[good_id])
		produced_units_lifetime += q
		turn_output += q
		# Lifetime per-good production feeds the end screen's "biggest outputs" chart.
		produced_by_good[str(good_id)] = int(produced_by_good.get(str(good_id), 0)) + q
	# End-of-game per-turn series (bounded to MAX_TURNS).
	if turn <= MAX_TURNS:
		history_revenue.append(float(_last_summary.get("goods_sales_revenue", 0.0)) + float(_last_summary.get("power_sales_revenue", 0.0)))
		history_output.append(turn_output)
		history_buildings.append(_count_player_buildings())
	# Richest: push this turn's retained (post-tax, post-dividend) profit and smooth.
	var rp := float(_last_summary.get("money_in", 0.0)) - float(_last_summary.get("money_out", 0.0))
	richest_window.append(rp)
	while richest_window.size() > RICHEST_WINDOW:
		richest_window.pop_front()
	# Demo counters advance before progress is read, so a turn spent top of the ranking
	# scores on the turn it happened rather than the next one.
	if _demo_rules:
		_demo_tick_counters()
	# Live progress per track, then raise the best-ever (monotonic).
	var live := {}
	for key in TRACK_ORDER:
		var lv := _live_progress(key)
		live[key] = lv
		track_best[key] = maxf(float(track_best.get(key, 0.0)), lv)
		# Record the turn a track is first fully secured (for the end screen's pennants).
		if float(track_best.get(key, 0.0)) >= 1.0 and not track_secured_turn.has(key):
			track_secured_turn[key] = turn
	# Recompute total + latch the win against the turn's (rising) threshold.
	var total := total_for_turn(turn)
	if not won and total >= win_threshold_for_turn(turn):
		won = true
		won_turn = turn
		victory_achieved.emit(total, turn)
	_push_history(turn, total, live)
	# Build the breakdown (captures this turn's purchase + movement tallies) BEFORE
	# clearing them.
	_last_breakdown = _build_breakdown(turn, total)
	for c in PURCHASE_CATEGORIES:
		purchases_this_turn[c] = 0
	# Logistics is a per-turn track: next turn's movements start from zero.
	logistics_total = 0
	logistics_efficient = 0
	score_changed.emit(total, _last_breakdown)

# ── Per-track live progress (spec §5.1–§5.5) ────────────────────────────────

func _live_progress(key: String) -> float:
	match key:
		"crown":
			return _demo_crown_progress()
		"tiers":
			return _demo_tiers_progress()
		"distance":
			return _demo_distance_progress()
		"green_demo":
			return _demo_green_progress()
		"estate":
			return _demo_estate_progress()
		"autarkic":
			if produced_units_lifetime < AUTARKIC_MIN_UNITS:
				return 0.0
			return clampf(float(autarkic_streak - AUTARKIC_START) / float(AUTARKIC_CAP - AUTARKIC_START), 0.0, 1.0)
		"logistics":
			if logistics_total < LOGI_MIN_MOVES:
				return 0.0
			var eff := float(logistics_efficient) / float(maxi(1, logistics_total))
			return clampf((eff - LOGI_FLOOR) / (1.0 - LOGI_FLOOR), 0.0, 1.0)
		"richest":
			var metric := _richest_metric()
			return clampf((metric - RICHEST_LO) / (RICHEST_HI - RICHEST_LO), 0.0, 1.0)
		"widest":
			var tiles := _count_widest_tiles()
			return clampf(float(tiles - WIDEST_LO) / float(WIDEST_HI - WIDEST_LO), 0.0, 1.0)
		"greenest":
			var g := _greenest_stats()
			# Gate: generate >= 5000 MW AND your network consumes >= 1000 MW/turn, then
			# score the green share above the 20% floor.
			if int(g.total) < GREEN_MIN_POWER or int(g.consumed) < GREEN_MIN_CONSUMED or float(g.share) < GREEN_FLOOR:
				return 0.0
			return clampf((float(g.share) - GREEN_FLOOR) / (1.0 - GREEN_FLOOR), 0.0, 1.0)
	return 0.0

func _richest_metric() -> float:
	if richest_window.is_empty():
		return 0.0
	var sum := 0.0
	for v in richest_window:
		sum += float(v)
	return sum / float(richest_window.size())

# Distinct player-owned tiles holding a non-infrastructure building (spec §5.4):
# Catalog.get_building(id).category != "infrastructure". The category field is the
# lowercased building_category string ("production"/"infrastructure"/"power"/...), so
# roads/rail/pipes/cables/ports drop out while power, battery and landfill all count.
func _count_widest_tiles() -> int:
	var tiles := {}
	for inst in MatchState.buildings.values():
		if not MatchState.is_player_owned(inst):
			continue
		var static_b: Dictionary = Catalog.get_building(str(inst.get("building_id", "")))
		if str(static_b.get("category", "")) == "infrastructure":
			continue
		tiles[str(inst.get("tile_id", ""))] = true
	return tiles.size()

# {total, green, share} for the current cached power summary (spec §5.5).
# Prefers the typed power-quality split (green = intermittent + steady, so hydro/biomass
# count too); falls back to the building-id heuristic for summaries predating the split.
# ── Demo track scoring ─────────────────────────────────────────────────────
#
# Two of these are CUMULATIVE counters (crown, long hauls) and three are read fresh from
# the turn (tiers, green, estate). The monotonic track_best that the campaign relies on
# does the rest: a per-turn track keeps the best turn the player ever had, which is what
# "does not stack from one turn to the next" means for the green track.

## Turns spent top of the revenue ranking. Banked — a turn at the top is never lost.
func _demo_crown_progress() -> float:
	return clampf(float(demo_crown_turns) / float(DEMO_CROWN_TURNS), 0.0, 1.0)

## Units produced THIS TURN per tier, DEMO_TIER_UNITS a tier paying
## DEMO_TIER_POINTS_PER_UNIT each, capped at DEMO_TIER_CAP per tier. Every tier pays
## separately, so breadth beats depth.
func _demo_tiers_progress() -> float:
	var produced: Dictionary = _last_summary.get("produced", {})
	if produced.is_empty():
		return 0.0
	var per_tier: Dictionary = {}
	for good_id in produced:
		if str(good_id) == "power":
			continue   # power is not a good; it has its own track
		var tier := str(Catalog.get_good(str(good_id)).get("goods_graph_tier", ""))
		if tier == "":
			continue
		per_tier[tier] = int(per_tier.get(tier, 0)) + int(produced[good_id])
	var points := 0
	for tier: String in DEMO_TIERS:
		var units: int = mini(int(per_tier.get(tier, 0)), DEMO_TIER_UNITS)
		points += mini(units * DEMO_TIER_POINTS_PER_UNIT, DEMO_TIER_CAP)
	return clampf(float(points) / float(DEMO_TIERS.size() * DEMO_TIER_CAP), 0.0, 1.0)

## Shipments delivered over a journey longer than DEMO_LONG_HAUL_TURNS. Cumulative.
func _demo_distance_progress() -> float:
	return clampf(float(demo_long_hauls) / float(DEMO_LONG_HAULS), 0.0, 1.0)

## Wind and solar generated THIS TURN. Deliberately not cumulative — the owner's rule is
## that it does not stack between turns, so the standing score is the best single turn.
func _demo_green_progress() -> float:
	return clampf(float(_greenest_stats().green) / DEMO_GREEN_TARGET, 0.0, 1.0)

## Non-infrastructure buildings owned, up to DEMO_ESTATE_BUILDINGS, plus a bonus once that
## many are running at once.
func _demo_estate_progress() -> float:
	var counts := demo_estate_counts()
	var points := mini(int(counts.owned), DEMO_ESTATE_BUILDINGS) * DEMO_ESTATE_POINTS_PER_BUILDING
	if int(counts.running) >= DEMO_ESTATE_BUILDINGS:
		points += DEMO_ESTATE_RUNNING_BONUS
	var max_points := DEMO_ESTATE_BUILDINGS * DEMO_ESTATE_POINTS_PER_BUILDING + DEMO_ESTATE_RUNNING_BONUS
	return clampf(float(points) / float(max_points), 0.0, 1.0)

## The estate, counted once: {owned, running}. Public because the end screen prints the
## same two numbers and they must not be able to disagree with the track.
func demo_estate_counts() -> Dictionary:
	var owned := 0
	var running := 0
	# Keyed walk, not .values(): last_turn_run is indexed by instance id, and the id a
	# building is filed under is the one that answers "did this one run".
	for iid in MatchState.buildings:
		var building: Dictionary = MatchState.buildings[iid]
		if not MatchState.is_player_owned(building):
			continue
		if _is_infrastructure(str(building.get("building_id", ""))):
			continue
		owned += 1
		if bool(Production.last_turn_run.get(str(iid), false)):
			running += 1
	return {"owned": owned, "running": running}

## Infrastructure is excluded from the estate count — roads and pipes are not an industrial
## estate, and counting them would let a player fill the track by paving. Same test the
## Widest track and the building panel use: the authored category, which covers the port
## and the airport as well as the linear stuff.
func _is_infrastructure(building_id: String) -> bool:
	return str(Catalog.get_building(building_id).get("category", "")) == "infrastructure"

## Called once per tick, before progress is read: advance the cumulative demo counters.
func _demo_tick_counters() -> void:
	for row: Dictionary in CompanyRankings.standings():
		if bool(row.get("is_player", false)):
			if int(row.get("rank", 99)) == 1:
				demo_crown_turns += 1
			break

func _greenest_stats() -> Dictionary:
	var total_power := int(_last_summary.get("power_supply", 0))
	var consumed := int(_last_summary.get("power_demand", 0))   # MW your network drew this turn
	var green := 0.0
	var by_quality: Dictionary = _last_summary.get("power_supply_by_quality", {})
	if not by_quality.is_empty():
		green = float(by_quality.get("green_intermittent", 0)) + float(by_quality.get("green_steady", 0))
	else:
		if _green_ids.is_empty():
			_resolve_green_ids()
		var by_type: Dictionary = _last_summary.get("power_supply_by_type", {})
		for bid in _green_ids:
			green += float((by_type.get(bid, {}) as Dictionary).get("amount", 0.0))
	var share := green / float(maxi(1, total_power))
	return {"total": total_power, "green": green, "share": share, "consumed": consumed}

func _resolve_green_ids() -> void:
	_green_ids = []
	for nm in GREEN_BUILDINGS:
		var bid := str(Catalog.get_building_by_internal_name(nm).get("id", ""))
		if bid != "":
			_green_ids.append(bid)

# ── Breakdown / trend assembly ──────────────────────────────────────────────

func _build_breakdown(turn: int, total: int) -> Dictionary:
	var tracks: Array = []
	for key in TRACK_ORDER:
		var best := float(track_best.get(key, 0.0))
		var entry := {
			"key": key,
			"name": String(TRACK_NAMES[key]),
			"color_key": String(TRACK_COLOR_KEYS[key]),
			"progress": best,
			"live": _live_progress(key),
			"contribution": int(round(best * float(TRACK_MAX[key]))),
			"max_score": int(TRACK_MAX[key]),
			"metric_text": _metric_text(key),
			"explain": String(TRACK_EXPLAIN[key]),
			"trend": _trend_for(key),
		}
		if key == "autarkic":
			entry["purchases_this_turn"] = purchases_this_turn.duplicate()
			entry["purchases_lifetime"] = purchases_lifetime.duplicate()
		tracks.append(entry)
	return {
		"total": total,
		"base": 0,                                        # no base score — you start at 0
		"track_total": total,
		"win_threshold": win_threshold_for_turn(turn),    # the rising bar for THIS turn
		# The eventual requirement: the campaign's turn-300 bar, or the demo's flat one.
		"win_threshold_max": DEMO_WIN_THRESHOLD if _demo_rules else WIN_MAX_THRESHOLD,
		"won": won,
		"won_turn": won_turn,
		"turn": turn,
		"max_turns": MAX_TURNS,
		"conditions_enabled": conditions_enabled(),
		"tracks": tracks,
	}

func _metric_text(key: String) -> String:
	match key:
		"crown":
			return "%d / %d turns top of the ranking (%d points a turn, banked)" % [
				demo_crown_turns, DEMO_CROWN_TURNS, DEMO_CROWN_POINTS_PER_TURN]
		"tiers":
			return "%d%% this turn — %d units in each of the %d tiers fills it" % [
				int(round(100.0 * _demo_tiers_progress())), DEMO_TIER_UNITS, DEMO_TIERS.size()]
		"distance":
			return "%d / %d shipments over %d turns' travel" % [
				demo_long_hauls, DEMO_LONG_HAULS, DEMO_LONG_HAUL_TURNS]
		"green_demo":
			return "%d / %d MW of wind and solar THIS TURN (does not carry over)" % [
				int(round(float(_greenest_stats().green))), int(DEMO_GREEN_TARGET)]
		"estate":
			var e := demo_estate_counts()
			return "%d / %d buildings, %d running (all %d running is worth another %d)" % [
				int(e.owned), DEMO_ESTATE_BUILDINGS, int(e.running), DEMO_ESTATE_BUILDINGS,
				DEMO_ESTATE_RUNNING_BONUS]
		"autarkic":
			if produced_units_lifetime < AUTARKIC_MIN_UNITS:
				return "Produce %s / %s units to unlock (self-supply at scale first)" % [
					_thousands(produced_units_lifetime), _thousands(AUTARKIC_MIN_UNITS)]
			return "Streak %d / %d turns (scores from %d)" % [autarkic_streak, AUTARKIC_CAP, AUTARKIC_START]
		"logistics":
			if logistics_total == 0:
				return "No movements this turn (need %d / turn, then 25%%→100%% efficient)" % LOGI_MIN_MOVES
			var eff := int(round(100.0 * float(logistics_efficient) / float(maxi(1, logistics_total))))
			if logistics_total < LOGI_MIN_MOVES:
				return "Efficiency %d%% over %d moves this turn (need %d)" % [eff, logistics_total, LOGI_MIN_MOVES]
			return "Efficiency %d%% over %d moves this turn" % [eff, logistics_total]
		"richest":
			return "Avg profit £%.1fk / turn (£%dk → £%dk)" % [_richest_metric() / 1000.0, int(RICHEST_LO / 1000.0), int(RICHEST_HI / 1000.0)]
		"widest":
			return "%d / %d tiles (scores from %d)" % [_count_widest_tiles(), WIDEST_HI, WIDEST_LO]
		"greenest":
			var g := _greenest_stats()
			var share_pct := int(round(100.0 * float(g.share)))
			return "Green %d%% · %d MW made, %d MW used (need %d made · %d used · 20%%)" % [
				share_pct, int(g.total), int(g.consumed), GREEN_MIN_POWER, GREEN_MIN_CONSUMED]
	return ""

func _thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if n < 0 else "") + out

func _trend_for(key: String) -> Array:
	var out: Array = []
	for snap in score_history:
		out.append(float((snap.get("tracks", {}) as Dictionary).get(key, 0.0)))
	return out

func _push_history(turn: int, total: int, live: Dictionary) -> void:
	var snap := {"turn": turn, "total": total, "base": 0, "tracks": {}}
	for key in TRACK_ORDER:
		snap.tracks[key] = float(live.get(key, 0.0))
	score_history.append(snap)
	while score_history.size() > TREND_LEN:
		score_history.pop_front()

# ── Internal reset / refresh ────────────────────────────────────────────────

func _reset_fields() -> void:
	autarkic_streak = 0
	produced_units_lifetime = 0
	logistics_total = 0
	logistics_efficient = 0
	richest_window = []
	track_best = {}
	for k in TRACK_ORDER:
		track_best[k] = 0.0
	score_history = []
	won = false
	won_turn = 0
	purchases_this_turn = _zero_categories()
	purchases_lifetime = _zero_categories()
	history_revenue = []
	history_output = []
	history_buildings = []
	produced_by_good = {}
	track_secured_turn = {}
	demo_crown_turns = 0
	demo_long_hauls = 0
	_last_summary = {}
	_scored_turn = TurnManager.current_turn

# Standing player-owned buildings (all categories) — the end screen's "buildings" series.
func _count_player_buildings() -> int:
	return MatchState.player_building_count()

func _zero_categories() -> Dictionary:
	var d := {}
	for c in PURCHASE_CATEGORIES:
		d[c] = 0
	return d

func _refresh_breakdown() -> void:
	# Between ticks the displayed score reflects the last-scored turn (base is
	# constant until the next resolution), so the UI stays consistent with the
	# last emitted total.
	_last_breakdown = _build_breakdown(_scored_turn, total_for_turn(_scored_turn))

func _emit_refresh() -> void:
	_refresh_breakdown()
	score_changed.emit(int(_last_breakdown.get("total", 0)), _last_breakdown)
