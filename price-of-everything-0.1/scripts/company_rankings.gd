extends Node
## Cosmetic league table. Rival revenue is derived from the match seed and never
## participates in the economic simulation; only the player's short UI history is saved.

const CompanyNames := preload("res://scripts/company_names.gd")

const RIVAL_COUNT := 9
## Fewest rival companies that contest any one good. The most is RIVAL_COUNT.
const GOOD_MIN_COMPETITORS := 3
const PARTICIPATION_SALT := 7717
const TIEBREAK_SALT := 9931
const TOTAL_COMPANIES := RIVAL_COUNT + 1
## Rivals open level with the player rather than a third of the way behind. At 100 the
## player led the table for the first dozen turns simply by existing, which banked most of
## the Crown track before a single decision was made.
## Where every rival starts. Lives in the difficulty preset with the rest of the rival tuning;
## the alias is kept because callers and tests read CompanyRankings.STARTING_REVENUE.
static var STARTING_REVENUE: float = float(difficulty()["starting_revenue"])
const HISTORY_TURNS := 5
const PLAYER_ID := "player"
const PLAYER_NAME := "Your Company"
## What the PLAYER actually earns per turn, measured off a full 100-turn demo run: £145 on
## turn 1 rising to about £1,100 by turn 100 — a shade over 2% a turn, compounded. Every
## rival ceiling below is expressed against this curve rather than as a flat number, for
## three reasons. It is a race for the whole match instead of a wall in the first fifty
## turns and a walkover in the last fifty. It is calibrated to something measured rather
## than guessed. And a 300-turn campaign scales itself, instead of needing its own constant.
const REFERENCE_START := 145.0
const REFERENCE_END := 1100.0
const REFERENCE_TURNS := 100
## ── Rival difficulty ────────────────────────────────────────────────────────────────────
##
## Everything above is the YARDSTICK — the player's own measured earnings — and is not a
## difficulty knob. What follows is: where the nine rivals sit against that yardstick, and how
## hard they push. It is a named preset rather than loose constants so that a difficulty
## selector, when there is one, has somewhere to point (owner, 25 Aug: "save the growth curve
## above as a 'hard' difficulty setting for the future"). Switching ACTIVE_DIFFICULTY is the
## whole switch — nothing else in this file carries a number of its own.
##
## Only the calibrated preset exists today. Adding "standard" and "gentle" is a balance pass
## with its own measured run behind it, not a guess made here.
##
##   leader_ceiling / tail_ceiling — the band the nine occupy, as multiples of the yardstick.
##       The narrow top is the point: at 1.5x the leader was out of reach and the podium was a
##       spectator sport, where at 1.2x a player on the reference run trades second and third
##       place, and a run 20% better than it leads outright.
##   headroom_exponent — growth is damped by the SQUARE ROOT of the headroom left, not the
##       headroom itself. Damping linearly makes a firm creep: it stalls at roughly two thirds
##       of a ceiling that is itself still rising, so the leader never reaches its own band.
##       The square root leaves early growth alone (headroom starts at 1, its own root) and
##       only bites near the top.
const DIFFICULTIES := {
	# Calibrated against the owner's full 100-turn run, 25 Aug 2026.
	"hard": {
		"starting_revenue": 150.0,
		"leader_ceiling": 1.2,
		"tail_ceiling": 0.6,
		"headroom_exponent": 0.5,
		"growth_mean": 0.15,
		"growth_standard_deviation": 0.05,
	},
}
const ACTIVE_DIFFICULTY := "hard"

static func difficulty() -> Dictionary:
	return DIFFICULTIES.get(ACTIVE_DIFFICULTY, DIFFICULTIES["hard"])

static var LEADER_CEILING_MULTIPLE: float = float(difficulty()["leader_ceiling"])
static var TAIL_CEILING_MULTIPLE: float = float(difficulty()["tail_ceiling"])
static var HEADROOM_EXPONENT: float = float(difficulty()["headroom_exponent"])
static var GROWTH_MEAN: float = float(difficulty()["growth_mean"])
static var GROWTH_STANDARD_DEVIATION: float = float(difficulty()["growth_standard_deviation"])
const GROWTH_MIN := 0.01
const GROWTH_MAX := 0.25
const DECAY_MIN := 0.01
const DECAY_MAX := 0.05

const ROSTER_SALT := 101
const CYCLE_SALT := 211
const DRAW_SALT := 307
const GOODS_DRAW_SALT := 401
const INDEX_STRIDE := 10_000_000
const TURN_STRIDE := 10_000
const GOODS_INCREMENT_TURNS := 5
const GOODS_INCREMENT_FACTORS: Array[float] = [0.0, 0.2, 0.5, 1.0]

enum CyclePhase { GROW, DECAY, FLAT }

signal rankings_updated

# Presentation-only state. The final item is the revenue from the latest resolved
# turn; retaining five values lets the panel survive save/load with the same trend.
var _player_revenue_history: Array[float] = []
var _player_goods_produced: Dictionary = {}  # good_id -> last resolved turn quantity
## The player's place in the revenue table, one entry per resolved turn, kept for the whole
## match. The revenue history above is trimmed to HISTORY_TURNS because the table only needs
## a trend; the end screen needs the whole arc, and it cannot be reconstructed afterwards —
## VictoryState's revenue series is SALES revenue while the table ranks money in, so
## replaying standings_for() over it would draw a curve the player never saw.
var player_rank_history: Array[int] = []

func _ready() -> void:
	TurnManager.phase_started.connect(_on_phase_started)
	MatchState.state_reset.connect(reset)

func reset() -> void:
	_player_revenue_history.clear()
	_player_goods_produced.clear()
	player_rank_history.clear()
	rankings_updated.emit()

func _on_phase_started(phase: int) -> void:
	if phase != TurnManager.Phase.AI:
		return
	_record_player_revenue(float(Production.last_turn_summary.get("money_in", 0.0)))
	_record_player_goods(Production.last_turn_summary.get("produced", {}))
	_record_player_rank()
	rankings_updated.emit()

func _record_player_revenue(revenue: float) -> void:
	_player_revenue_history.append(revenue)
	while _player_revenue_history.size() > HISTORY_TURNS:
		_player_revenue_history.pop_front()

## One standings build a turn — the same one the rankings panel asks for when it is open,
## and the only way to keep an honest arc of where the company stood.
func _record_player_rank() -> void:
	for row: Dictionary in standings():
		if bool(row.get("is_player", false)):
			player_rank_history.append(int(row.get("rank", TOTAL_COMPANIES)))
			return


func _record_player_goods(produced: Variant) -> void:
	_player_goods_produced.clear()
	if not (produced is Dictionary):
		return
	for key: Variant in (produced as Dictionary):
		_player_goods_produced[str(key)] = int((produced as Dictionary)[key])

## Current table at the beginning of a DECIDE phase. During AI, callers should
## use standings_for() explicitly with the in-flight turn if they need a preview.
func standings() -> Array[Dictionary]:
	var completed_turn: int = maxi(0, int(TurnManager.current_turn) - 1)
	return standings_for(MatchState.match_rng_seed, completed_turn, _player_revenue_history)

## Pure table builder used by the UI and tests. `player_revenues` contains the
## latest resolved revenues in chronological order and is deliberately independent
## from MatchState's simulation RNG.
func standings_for(match_seed: int, completed_turn: int, player_revenues: Array[float]) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var names := _rival_names_for(match_seed)
	for i: int in range(RIVAL_COUNT):
		var history := _rival_history_for(match_seed, i, completed_turn)
		rows.append({
			"id": "rival_%d" % i,
			"name": names[i],
			"is_player": false,
			"revenue": float(history.back()) if not history.is_empty() else STARTING_REVENUE,
			"trend_average": _average(history),
		})
	var player_history := _trim_history(player_revenues)
	rows.append({
		"id": PLAYER_ID,
		"name": PLAYER_NAME,
		"is_player": true,
		"revenue": float(player_history.back()) if not player_history.is_empty() else 0.0,
		"trend_average": _average(player_history),
	})
	_sort_rows(rows)
	for i: int in range(rows.size()):
		rows[i]["rank"] = i + 1

	var previous_player_revenues: Array[float] = []
	if player_revenues.size() >= 2:
		previous_player_revenues = player_revenues.slice(0, player_revenues.size() - 1)
	var previous := _rows_for_previous_turn(match_seed, completed_turn, previous_player_revenues)
	var previous_rank_by_id: Dictionary = {}
	for previous_row: Dictionary in previous:
		previous_rank_by_id[str(previous_row["id"])] = int(previous_row["rank"])
	for row: Dictionary in rows:
		var old_rank: int = int(previous_rank_by_id.get(str(row["id"]), int(row["rank"])))
		row["rank_change"] = old_rank - int(row["rank"])
	return rows

## Per-good production table. Rival output is cosmetic and derived from the
## seed; the player's row is the real quantity produced in the latest turn.
func goods_standings() -> Array[Dictionary]:
	var completed_turn: int = maxi(0, int(TurnManager.current_turn) - 1)
	return goods_standings_for(MatchState.match_rng_seed, completed_turn, _player_goods_produced)

func goods_standings_for(match_seed: int, completed_turn: int, player_produced: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var names := _rival_names_for(match_seed)
	for good_variant: Variant in MatchState.visible_goods():
		var good: Dictionary = good_variant as Dictionary
		var good_id := str(good.get("id", ""))
		var apex: bool = str(good.get("goods_graph_tier", "")) == "apex"
		var rows: Array[Dictionary] = []
		if not apex and Catalog.base_output_for_good(good_id) > 0:
			# Only the companies that are IN this good, not all nine. Every good used to list
			# all of them at identical output, so the sort fell through to the id tiebreak and
			# the same three names topped every good in the panel.
			for competitor_index: int in _competitors_for_good(match_seed, good_id):
				rows.append({
					"id": "rival_%d" % competitor_index,
					"name": names[competitor_index],
					"is_player": false,
					"quantity": _rival_good_output_for(match_seed, good_id, competitor_index, completed_turn),
					"tiebreak": _good_tiebreak(match_seed, good_id, competitor_index),
				})
			_sort_good_rows(rows)
			rows = rows.slice(0, 3)
		rows.append({
			"id": PLAYER_ID,
			"name": PLAYER_NAME,
			"is_player": true,
			"quantity": _player_good_quantity(good_id, player_produced),
		})
		_sort_good_rows(rows)
		for i: int in range(rows.size()):
			rows[i]["rank"] = i + 1
		out.append({
			"good_id": good_id,
			"internal_name": str(good.get("internal_name", "")),
			"display_name": str(good.get("display_name", good_id)),
			"is_apex": apex,
			"producers": rows,
		})
	return out

## Which rival companies compete in a given good, as rival indices.
##
## Deterministic from (match_seed, good_id), like every other rival figure here — the same
## match always shows the same table — but DIFFERENT per good, which is the point: coal and
## copper are not contested by the same firms, and a panel that said they were looked broken.
## Between GOOD_MIN_COMPETITORS and RIVAL_COUNT of them, so some goods are crowded and some
## are nearly the player's alone.
func _competitors_for_good(match_seed: int, good_id: String) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = _goods_seed_for(match_seed, good_id, 0, PARTICIPATION_SALT)
	var pool: Array = []
	for i: int in range(RIVAL_COUNT):
		pool.append(i)
	# Fisher-Yates on our own RNG. Array.shuffle() would draw from the global RNG, which
	# this module must never touch (a test pins that table generation leaves it alone).
	for i: int in range(pool.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var swap: Variant = pool[i]
		pool[i] = pool[j]
		pool[j] = swap
	var count: int = rng.randi_range(GOOD_MIN_COMPETITORS, RIVAL_COUNT)
	return pool.slice(0, count)

## A stable per-(good, company) ordering key. Rival outputs are identical until the first
## increment lands, so without this the display order inside one good is just id order.
func _good_tiebreak(match_seed: int, good_id: String, competitor_index: int) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = _goods_seed_for(match_seed, good_id, competitor_index, TIEBREAK_SALT)
	return rng.randi()

func _player_good_quantity(good_id: String, player_produced: Dictionary) -> int:
	# Power is keyed by its internal name in Production's summary, unlike normal goods.
	if good_id == "g_010":
		return int(player_produced.get("power", 0))
	return int(player_produced.get(good_id, 0))

func _rival_good_output_for(match_seed: int, good_id: String, competitor_index: int, completed_turn: int) -> int:
	var base: int = Catalog.base_output_for_good(good_id)
	if base <= 0:
		return 0
	var quantity := base
	var completed_batches: int = completed_turn / GOODS_INCREMENT_TURNS
	for batch: int in range(1, completed_batches + 1):
		var rng := RandomNumberGenerator.new()
		rng.seed = _goods_seed_for(match_seed, good_id, competitor_index, batch)
		quantity += _goods_increment(base, rng)
	return quantity

func _goods_increment(base: int, rng: RandomNumberGenerator) -> int:
	var factor: float = GOODS_INCREMENT_FACTORS[rng.randi_range(0, GOODS_INCREMENT_FACTORS.size() - 1)]
	return int(round(float(base) * factor))

func _goods_seed_for(match_seed: int, good_id: String, competitor_index: int, batch: int) -> int:
	var numeric_good_id: int = int(good_id.trim_prefix("g_"))
	return _seed_for(match_seed, competitor_index, batch, GOODS_DRAW_SALT + numeric_good_id * 101)

func _sort_good_rows(rows: Array[Dictionary]) -> void:
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_quantity: int = int(a["quantity"])
		var b_quantity: int = int(b["quantity"])
		if a_quantity != b_quantity:
			return a_quantity > b_quantity
		var a_is_player: bool = bool(a["is_player"])
		var b_is_player: bool = bool(b["is_player"])
		if a_is_player != b_is_player:
			return a_is_player
		# Equal output: use the per-good key when the rows carry one (the goods tables do),
		# so the order inside a good is that good's, not a global id order.
		if a.has("tiebreak") and b.has("tiebreak"):
			return int(a["tiebreak"]) < int(b["tiebreak"])
		return str(a["id"]) < str(b["id"])
	)

func _rows_for_previous_turn(match_seed: int, completed_turn: int, player_revenues: Array[float]) -> Array[Dictionary]:
	if completed_turn <= 0:
		return []
	var rows: Array[Dictionary] = []
	var names := _rival_names_for(match_seed)
	for i: int in range(RIVAL_COUNT):
		rows.append({
			"id": "rival_%d" % i,
			"name": names[i],
			"is_player": false,
			"revenue": _rival_revenue_for(match_seed, i, completed_turn - 1),
		})
	rows.append({
		"id": PLAYER_ID,
		"name": PLAYER_NAME,
		"is_player": true,
		"revenue": float(player_revenues.back()) if not player_revenues.is_empty() else 0.0,
	})
	_sort_rows(rows)
	for i: int in range(rows.size()):
		rows[i]["rank"] = i + 1
	return rows

func _sort_rows(rows: Array[Dictionary]) -> void:
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_revenue: float = float(a["revenue"])
		var b_revenue: float = float(b["revenue"])
		if not is_equal_approx(a_revenue, b_revenue):
			return a_revenue > b_revenue
		var a_is_player: bool = bool(a["is_player"])
		var b_is_player: bool = bool(b["is_player"])
		if a_is_player != b_is_player:
			return a_is_player
		return str(a["id"]) < str(b["id"])
	)

func _rival_names_for(match_seed: int) -> Array[String]:
	var shuffled: Array[String] = []
	for company_name: String in CompanyNames.NAMES:
		shuffled.append(company_name)
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed_for(match_seed, -1, 0, ROSTER_SALT)
	_shuffle_strings(shuffled, rng)
	var roster: Array[String] = []
	for i: int in range(RIVAL_COUNT):
		roster.append(shuffled[i])
	return roster

func _rival_history_for(match_seed: int, competitor_index: int, completed_turn: int) -> Array[float]:
	var out: Array[float] = []
	var first_turn: int = maxi(0, completed_turn - HISTORY_TURNS + 1)
	for turn: int in range(first_turn, completed_turn + 1):
		out.append(_rival_revenue_for(match_seed, competitor_index, turn))
	return out

func _rival_revenue_for(match_seed: int, competitor_index: int, completed_turn: int) -> float:
	var revenue := STARTING_REVENUE
	var cycle := _cycle_for(match_seed, competitor_index)
	for turn: int in range(1, completed_turn + 1):
		var phase: int = cycle[turn % cycle.size()]
		if phase == CyclePhase.FLAT:
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = _seed_for(match_seed, competitor_index, turn, DRAW_SALT)
		if phase == CyclePhase.GROW:
			# Damped by how much headroom this firm has left against ITS ceiling for THIS turn.
			# Undamped, this line compounds five turns in every nine at a 15% mean and never
			# stops: x1,197 by turn 100 and x1.7 BILLION by turn 300, which is how the table
			# came to read £50k a turn against a player earning £1.1k. The market these firms
			# trade in is finite and it grows at the pace the player's does; the curve now says
			# so. Early growth is untouched, because headroom starts at 1.
			revenue *= 1.0 + _growth_rate(rng) * _headroom(revenue, _ceiling_for(competitor_index, turn))
		else:
			revenue *= 1.0 - _decay_rate(rng)
	return revenue


## What a player on the measured run is earning per turn at `turn`. Exponential rather than
## straight-line, because an economy compounds — a linear reading would put the reference far
## too high through the opening fifty turns, which is exactly where the demo lives.
func _reference_revenue(turn: int) -> float:
	return REFERENCE_START * pow(REFERENCE_END / REFERENCE_START, float(turn) / float(REFERENCE_TURNS))


## The ceiling for one rival slot on one turn. Slot 0 is the leader; each slot after it sits
## a step lower, which is what makes the table fan out into positions rather than a huddle.
## Seeded name shuffling means slot 0 is a different company every match, so a fixed ladder
## here does not mean the same firm always wins.
func _ceiling_for(competitor_index: int, turn: int) -> float:
	var step: float = float(competitor_index) / float(maxi(RIVAL_COUNT - 1, 1))
	return _reference_revenue(turn) * lerpf(LEADER_CEILING_MULTIPLE, TAIL_CEILING_MULTIPLE, step)


## How much of its growth a firm still has in front of it, 1 at the start and falling to 0
## at the ceiling. Decay still bites at full strength, so firms near the top oscillate
## under it rather than pinning to it.
func _headroom(revenue: float, ceiling: float) -> float:
	return pow(clampf(1.0 - revenue / maxf(ceiling, 1.0), 0.0, 1.0), HEADROOM_EXPONENT)

## Normal draws favour 10–20% while the hard limits prevent an exceptional
## sample from making a runaway one-turn jump.
func _growth_rate(rng: RandomNumberGenerator) -> float:
	return clampf(rng.randfn(GROWTH_MEAN, GROWTH_STANDARD_DEVIATION), GROWTH_MIN, GROWTH_MAX)

func _decay_rate(rng: RandomNumberGenerator) -> float:
	return rng.randf_range(DECAY_MIN, DECAY_MAX)

func _cycle_for(match_seed: int, competitor_index: int) -> Array[int]:
	var cycle: Array[int] = [
		CyclePhase.GROW, CyclePhase.GROW, CyclePhase.GROW, CyclePhase.GROW, CyclePhase.GROW,
		CyclePhase.DECAY, CyclePhase.DECAY,
		CyclePhase.FLAT, CyclePhase.FLAT,
	]
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed_for(match_seed, competitor_index, 0, CYCLE_SALT)
	for i: int in range(cycle.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var swap: int = cycle[i]
		cycle[i] = cycle[j]
		cycle[j] = swap
	return cycle

func _shuffle_strings(items: Array[String], rng: RandomNumberGenerator) -> void:
	for i: int in range(items.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var swap: String = items[i]
		items[i] = items[j]
		items[j] = swap

func _seed_for(match_seed: int, competitor_index: int, turn: int, salt: int) -> int:
	return match_seed + (competitor_index + 2) * INDEX_STRIDE + turn * TURN_STRIDE + salt

func _trim_history(values: Array[float]) -> Array[float]:
	var out: Array[float] = []
	var first: int = maxi(0, values.size() - HISTORY_TURNS)
	for i: int in range(first, values.size()):
		out.append(float(values[i]))
	return out

func _average(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value: float in values:
		total += value
	return total / float(values.size())

func export_state() -> Dictionary:
	return {
		"player_revenue_history": _player_revenue_history.duplicate(),
		"player_goods_produced": _player_goods_produced.duplicate(),
		"player_rank_history": player_rank_history.duplicate(),
	}

func import_state(d: Dictionary) -> void:
	_player_revenue_history.clear()
	var raw: Variant = d.get("player_revenue_history", [])
	if raw is Array:
		for value: Variant in raw:
			_player_revenue_history.append(float(value))
	_player_revenue_history = _trim_history(_player_revenue_history)
	player_rank_history.clear()
	var raw_rank: Variant = d.get("player_rank_history", [])
	if raw_rank is Array:
		for value: Variant in raw_rank:
			player_rank_history.append(int(value))
	_player_goods_produced.clear()
	var raw_goods: Variant = d.get("player_goods_produced", {})
	if raw_goods is Dictionary:
		for good_id: Variant in (raw_goods as Dictionary):
			_player_goods_produced[str(good_id)] = int((raw_goods as Dictionary)[good_id])
	rankings_updated.emit()
