extends Node

# VictoryState (autoload) — the single source of truth for the victory score.
#
# Score = a decaying base TIME score + five independent TRACK scores
# (Autarkic, Logistics, Richest, Widest, Greenest). It recomputes once per turn
# and latches a win the first turn `total >= WIN_THRESHOLD`. Track contributions
# are stored best-ever (monotonic — bars only fill up); the base decays with the
# turn count, which IS the intended time pressure (a fast finish needs fewer
# tracks). See docs/victory-system-spec.md for the full design.
#
# Wiring (all reads, never writes sim state — UI is read-only, rule #5):
#   Production.turn_processed(summary)            -> cache the turn's economics
#   TurnManager.turn_resolution_completed         -> recompute + win check (the tick)
#   MatchState.goods_movement_recorded(k,c,turns) -> Logistics + Autarky live feed
#   MatchState.state_reset                        -> reset() on new game / pre-load
#
# Saves round-trip via export_state()/import_state(); SaveLoad owns the snapshot.

# ── Tunables — all victory balance lives here (spec §10) ───────────────────
const WIN_THRESHOLD := 4000
const BASE_MAX := 3000      # base = max(0, BASE_MAX - max(0, turn-BASE_FREE)*BASE_DECAY)
const BASE_FREE := 100      # full base through turn 100
const BASE_DECAY := 15      # = BASE_MAX/(BASE_ZERO-BASE_FREE); base reaches 0 at turn 300
const BASE_ZERO := 300      # == TurnManager.MAX_TURNS (documentary; decay derived from it)

const TRACK_MAX := {
	"autarkic": 1000, "logistics": 1000, "richest": 1000,
	"widest": 1000, "greenest": 1000,
}
# Display order: 3 on the top row + 2 below, in the panel.
const TRACK_ORDER: Array = ["autarkic", "logistics", "richest", "widest", "greenest"]

const AUTARKIC_START := 10
const AUTARKIC_CAP := 30
const LOGI_MIN_MOVES := 100
const LOGI_EFF_TURNS := 1
const LOGI_FLOOR := 0.25
const RICHEST_WINDOW := 5
const RICHEST_LO := 2000.0
const RICHEST_HI := 12000.0
const WIDEST_LO := 30
const WIDEST_HI := 230
const GREEN_MIN_POWER := 500
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
	"autarkic": "Consecutive turns buying nothing from the market — source every input, build & upgrade material yourself.",
	"logistics": "Share of goods movements that arrive in 1 turn or less — extend rail/pipe so deliveries are instant.",
	"richest": "Sustained post-tax profit, smoothed over recent turns — keep margins high turn after turn.",
	"widest": "Distinct tiles holding one of your (non-infrastructure) buildings — spread out across the map.",
	"greenest": "Green share of the power you generate — replace fossil plants with solar & wind.",
}

# ── Saved state (round-trips via export/import — spec §3) ──────────────────
var autarkic_streak: int = 0
var logistics_total: int = 0
var logistics_efficient: int = 0
var richest_window: Array = []           # trailing retained-profit buffer (<= RICHEST_WINDOW)
var track_best: Dictionary = {}          # track key -> best-ever progress (0..1)
var score_history: Array = []            # last TREND_LEN snapshots {turn,total,base,tracks{}}
var won: bool = false
var won_turn: int = 0
var purchases_this_turn: Dictionary = {} # category -> count (reset each turn)
var purchases_lifetime: Dictionary = {}  # category -> cumulative count

# ── Transient (not saved) ──────────────────────────────────────────────────
var _last_summary: Dictionary = {}       # cached from Production.turn_processed
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

# The decaying base time score for a given turn (spec §5.0). Public for tests.
func base_for_turn(turn: int) -> int:
	return int(maxf(0.0, float(BASE_MAX) - maxf(0.0, float(turn - BASE_FREE)) * float(BASE_DECAY)))

# total = base + Σ round(best_progress * TRACK_MAX). Public for tests.
func total_for_turn(turn: int) -> int:
	var total := base_for_turn(turn)
	for key in TRACK_ORDER:
		total += int(round(float(track_best.get(key, 0.0)) * float(TRACK_MAX[key])))
	return total

# Logistics + Autarky live feed (spec §4.2 / §5.1 / §5.2). Called by the
# goods_movement_recorded signal handler, and directly by tests.
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
	_last_summary = summary

func _on_turn_resolution_completed() -> void:
	_tick()

func _on_goods_movement_recorded(kind: String, category: String, transport_turns: int) -> void:
	record_movement(kind, category, transport_turns)

# ── The per-turn scoring tick ───────────────────────────────────────────────

func _tick() -> void:
	var turn: int = TurnManager.current_turn
	# Autarkic: any market buy this turn (any category) resets the streak.
	var bought_any := false
	for c in PURCHASE_CATEGORIES:
		if int(purchases_this_turn.get(c, 0)) > 0:
			bought_any = true
			break
	autarkic_streak = 0 if bought_any else autarkic_streak + 1
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
	# Recompute total + latch the win.
	var total := total_for_turn(turn)
	if not won and total >= WIN_THRESHOLD:
		won = true
		won_turn = turn
		victory_achieved.emit(total, turn)
	_push_history(turn, total, live)
	# Build the breakdown (captures this turn's purchase tally) BEFORE clearing it.
	_last_breakdown = _build_breakdown(turn, total)
	for c in PURCHASE_CATEGORIES:
		purchases_this_turn[c] = 0
	score_changed.emit(total, _last_breakdown)

# ── Per-track live progress (spec §5.1–§5.5) ────────────────────────────────

func _live_progress(key: String) -> float:
	match key:
		"autarkic":
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
			if int(g.total) < GREEN_MIN_POWER or float(g.share) < GREEN_FLOOR:
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

# Distinct player-owned tiles holding a non-infrastructure building (spec §5.4).
# NOTE: `category` on the building dict is a numeric code, not the word
# "infrastructure" — the reliable discriminator is the `building_type` array.
func _count_widest_tiles() -> int:
	var tiles := {}
	for inst in MatchState.buildings.values():
		if not MatchState.is_player_owned(inst):
			continue
		var static_b: Dictionary = Catalog.get_building(str(inst.get("building_id", "")))
		if "infrastructure" in (static_b.get("building_type", []) as Array):
			continue
		tiles[str(inst.get("tile_id", ""))] = true
	return tiles.size()

# {total, green, share} for the current cached power summary (spec §5.5).
func _greenest_stats() -> Dictionary:
	var total_power := int(_last_summary.get("power_supply", 0))
	if _green_ids.is_empty():
		_resolve_green_ids()
	var by_type: Dictionary = _last_summary.get("power_supply_by_type", {})
	var green := 0.0
	for bid in _green_ids:
		green += float((by_type.get(bid, {}) as Dictionary).get("amount", 0.0))
	var share := green / float(maxi(1, total_power))
	return {"total": total_power, "green": green, "share": share}

func _resolve_green_ids() -> void:
	_green_ids = []
	for nm in GREEN_BUILDINGS:
		var bid := str(Catalog.get_building_by_internal_name(nm).get("id", ""))
		if bid != "":
			_green_ids.append(bid)

# ── Breakdown / trend assembly ──────────────────────────────────────────────

func _build_breakdown(turn: int, total: int) -> Dictionary:
	var base := base_for_turn(turn)
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
		"base": base,
		"track_total": total - base,
		"win_threshold": WIN_THRESHOLD,
		"won": won,
		"won_turn": won_turn,
		"turn": turn,
		"max_turns": BASE_ZERO,
		"tracks": tracks,
	}

func _metric_text(key: String) -> String:
	match key:
		"autarkic":
			return "Streak %d / %d turns (scores from %d)" % [autarkic_streak, AUTARKIC_CAP, AUTARKIC_START]
		"logistics":
			if logistics_total == 0:
				return "No movements yet (need %d, then 25%%→100%% efficient)" % LOGI_MIN_MOVES
			var eff := int(round(100.0 * float(logistics_efficient) / float(maxi(1, logistics_total))))
			if logistics_total < LOGI_MIN_MOVES:
				return "Efficiency %d%% over %d moves (need %d)" % [eff, logistics_total, LOGI_MIN_MOVES]
			return "Efficiency %d%% over %d moves" % [eff, logistics_total]
		"richest":
			return "Avg profit £%.1fk / turn (£%dk → £%dk)" % [_richest_metric() / 1000.0, int(RICHEST_LO / 1000.0), int(RICHEST_HI / 1000.0)]
		"widest":
			return "%d / %d tiles (scores from %d)" % [_count_widest_tiles(), WIDEST_HI, WIDEST_LO]
		"greenest":
			var g := _greenest_stats()
			var share_pct := int(round(100.0 * float(g.share)))
			return "Green %d%% of %d MW (need %d MW & 20%%)" % [share_pct, int(g.total), GREEN_MIN_POWER]
	return ""

func _trend_for(key: String) -> Array:
	var out: Array = []
	for snap in score_history:
		out.append(float((snap.get("tracks", {}) as Dictionary).get(key, 0.0)))
	return out

func _push_history(turn: int, total: int, live: Dictionary) -> void:
	var snap := {"turn": turn, "total": total, "base": base_for_turn(turn), "tracks": {}}
	for key in TRACK_ORDER:
		snap.tracks[key] = float(live.get(key, 0.0))
	score_history.append(snap)
	while score_history.size() > TREND_LEN:
		score_history.pop_front()

# ── Internal reset / refresh ────────────────────────────────────────────────

func _reset_fields() -> void:
	autarkic_streak = 0
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

func _zero_categories() -> Dictionary:
	var d := {}
	for c in PURCHASE_CATEGORIES:
		d[c] = 0
	return d

func _refresh_breakdown() -> void:
	var turn: int = TurnManager.current_turn
	_last_breakdown = _build_breakdown(turn, total_for_turn(turn))

func _emit_refresh() -> void:
	_refresh_breakdown()
	score_changed.emit(int(_last_breakdown.get("total", 0)), _last_breakdown)
