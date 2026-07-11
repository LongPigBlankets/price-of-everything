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
const MAX_TURNS := 300            # campaign length (== TurnManager.MAX_TURNS); UI progress

const TRACK_MAX := {
	"autarkic": 1000, "logistics": 1000, "richest": 1000,
	"widest": 1000, "greenest": 1000,
}
# Display order: 3 on the top row + 2 below, in the panel.
const TRACK_ORDER: Array = ["autarkic", "logistics", "richest", "widest", "greenest"]

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
const TRACK_NAMES := {
	"autarkic": "Autarkic", "logistics": "Logistics", "richest": "Richest",
	"widest": "Widest", "greenest": "Greenest",
}
const TRACK_COLOR_KEYS := {
	"autarkic": "WARN", "logistics": "ACCENT", "richest": "OK",
	"widest": "ACTION_BLUE_TOP", "greenest": "OK",
}
const TRACK_EXPLAIN := {
	"autarkic": "Consecutive turns buying nothing from the market — source every input, build & upgrade material yourself. Power is exempt: draw from the grid freely, and generated MW don't count toward the unlock.",
	"logistics": "Share of this turn's goods movements arriving in 1 turn or less — extend rail/pipe so deliveries are instant. Power isn't shipped, so electricity never counts.",
	"richest": "Sustained post-tax profit, smoothed over recent turns — keep margins high turn after turn.",
	"widest": "Distinct tiles holding one of your (non-infrastructure) buildings — spread out across the map.",
	"greenest": "Green share of the power you generate — replace fossil plants with solar & wind. Counts once your network generates 5,000 MW and draws 1,000 MW per turn.",
}

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

# ── Transient (not saved) ──────────────────────────────────────────────────
var _last_summary: Dictionary = {}       # cached from Production.turn_processed
var _scored_turn: int = 1                # the turn _last_summary belongs to (captured
                                         # during PROCESS, before TurnManager increments)
var _last_breakdown: Dictionary = {}     # what get_breakdown() serves between ticks
var _green_ids: Array = []               # building_ids resolved from GREEN_BUILDINGS

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

# Points needed to win at a given turn — the RISING BAR (owner 2026-07-11). Flat at
# WIN_MIN_THRESHOLD until WIN_START_TURN, then +WIN_STEP_POINTS per WIN_STEP_TURNS,
# capped at WIN_MAX_THRESHOLD. Public for tests.
func win_threshold_for_turn(turn: int) -> int:
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
	logistics_total += 1
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
	# Don't re-fire victory_achieved on load (spec §6 edge); just publish the state.
	_emit_refresh()

# ── Signal handlers ─────────────────────────────────────────────────────────

func _on_turn_processed(summary: Dictionary) -> void:
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
	for good_id in produced:
		if str(good_id) == "power":
			continue
		produced_units_lifetime += int(produced[good_id])
	# Richest: push this turn's retained (post-tax, post-dividend) profit and smooth.
	var rp := float(_last_summary.get("money_in", 0.0)) - float(_last_summary.get("money_out", 0.0))
	richest_window.append(rp)
	while richest_window.size() > RICHEST_WINDOW:
		richest_window.pop_front()
	# Live progress per track, then raise the best-ever (monotonic).
	var live := {}
	for key in TRACK_ORDER:
		var lv := _live_progress(key)
		live[key] = lv
		track_best[key] = maxf(float(track_best.get(key, 0.0)), lv)
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
		"win_threshold_max": WIN_MAX_THRESHOLD,           # the eventual (turn-300) requirement
		"won": won,
		"won_turn": won_turn,
		"turn": turn,
		"max_turns": MAX_TURNS,
		"tracks": tracks,
	}

func _metric_text(key: String) -> String:
	match key:
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
	_last_summary = {}
	_scored_turn = TurnManager.current_turn

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
