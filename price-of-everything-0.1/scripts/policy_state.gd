extends Node
## PolicyState: the decarbonisation squeeze — CO2 tax phases + green-energy subsidy.
## (docs/co2-tax-and-green-subsidy-announcements-spec.md)
##
## The timeline is const data (policy_schedule.gd), so the live levels are PURE
## functions of the turn — deterministic, headless-safe, nothing to serialize for the
## effect itself. This autoload only:
##   1. answers co2_tax_level(turn) / green_subsidy_rate(turn) for production.gd, and
##   2. seeds the forewarn + enactment announcements into EventScheduler once per match
##      (the `_seeded` flag round-trips in saves so a load never double-seeds — the
##      scheduled events themselves already live in EventScheduler's saved state).
##
## Announcement UI is passive (news items in the bell + Turn Briefing); the economic
## effects run everywhere, including the e2e balance harness — that pressure is the
## point of the feature.

const Schedule := preload("res://scripts/policy_schedule.gd")

# The carbon levy's advance notice: a blocking "Understood" story decision reserved for
# turn NOTICE_PRESENT_TURN's DECIDE (reservations fire in the PREVIOUS turn's NARRATIVE).
const CO2_NOTICE_DEF := "carbon_tax_notice"
const CO2_NOTICE_PRESENT_TURN := 90
const CO2_P1_TURN := 101

# Green subsidy window: live from the schedule's effective turn (105), guaranteed
# through GREEN_SUBSIDY_MIN_LAST_TURN, then lapses on a seed-picked turn so each match
# ends the programme somewhere in [186, 191]. Derived arithmetically from the match
# seed (no RNG stream consumed, stable across engine versions).
const GREEN_SUBSIDY_MIN_LAST_TURN := 185
const GREEN_SUBSIDY_END_SPREAD := 6

var _seeded: bool = false

func _ready() -> void:
	MatchState.state_reset.connect(_on_state_reset)
	# A brand-new session (no save loaded, no reset yet) still needs the schedule:
	# seed after the autoload settles unless a load beat us to it.
	call_deferred("_seed_if_needed")

# --- Live levels (pure functions of the turn) ---------------------------------------

## Highest CO2-tax phase in force at `turn` (0 = the levy is not yet in force).
func co2_tax_level(turn: int) -> int:
	var lvl := 0
	for e in Schedule.SCHEDULE:
		if str(e.policy) == "co2_tax" and turn >= int(e.effective_turn):
			lvl = maxi(lvl, int(e.level))
	return lvl

## The last turn the subsidy pays out: at least 185, stretching 0..5 further by match
## seed — so the programme lapses (first unpaid turn) somewhere in [186, 191].
func green_subsidy_last_turn() -> int:
	return GREEN_SUBSIDY_MIN_LAST_TURN + posmod(int(MatchState.match_rng_seed), GREEN_SUBSIDY_END_SPREAD)

## £ per green MW generated at `turn` (0.0 before the subsidy window opens or after
## the programme lapses).
func green_subsidy_rate(turn: int) -> float:
	if turn > green_subsidy_last_turn():
		return 0.0
	var lvl := 0
	for e in Schedule.SCHEDULE:
		if str(e.policy) == "green_subsidy" and turn >= int(e.effective_turn):
			lvl = maxi(lvl, int(e.level))
	if lvl <= 0 or lvl >= EconomyConfig.GREEN_SUBSIDY_PHASE_SCALE.size():
		lvl = mini(lvl, EconomyConfig.GREEN_SUBSIDY_PHASE_SCALE.size() - 1)
	return EconomyConfig.GREEN_SUBSIDY_RATE * float(EconomyConfig.GREEN_SUBSIDY_PHASE_SCALE[lvl])

## The scale factor for the current CO2 phase (0.0 when not in force).
func co2_tax_scale(turn: int) -> float:
	var lvl := co2_tax_level(turn)
	lvl = clampi(lvl, 0, EconomyConfig.CO2_TAX_PHASE_SCALE.size() - 1)
	return float(EconomyConfig.CO2_TAX_PHASE_SCALE[lvl])

## £ carbon levy for consuming `qty` units of the good at `turn` (0 for untaxed goods).
func carbon_charge(good_id: String, qty: int, turn: int) -> float:
	if qty <= 0:
		return 0.0
	var mult := float(Catalog.get_good(good_id).get("co2_tax_multiplier", 0.0))
	if mult <= 0.0:
		return 0.0
	return float(qty) * mult * EconomyConfig.CO2_TAX_RATE * co2_tax_scale(turn)

# --- Announcement seeding -------------------------------------------------------------

func _on_state_reset() -> void:
	# New game (or pre-load reset): re-arm. If a load follows, import_state overwrites
	# _seeded and EventScheduler restores its own scheduled events.
	_seeded = false
	call_deferred("_seed_if_needed")

func _seed_if_needed() -> void:
	# The notice reservation lives in DecisionState state that is NOT saved, so it is
	# re-armed on every seed AND every load (guarded against double-fires inside).
	_arm_carbon_notice()
	if _seeded:
		return
	_seeded = true
	# The subsidy's lapse announcement isn't in the const table (its turn is per-match,
	# seed-derived): first unpaid turn ∈ [186, 191], forewarned 5 turns ahead.
	EventScheduler.schedule(green_subsidy_last_turn() + 1, {
		"id": "policy:green_subsidy_end",
		"kind": "policy_enacted",
		"severity": "warning",
		"title": "Green Energy Subsidy — programme ended",
		# LOREM — owner lore pending.
		"body": "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Subsidium energiae viridis finitum est; merces pro megawatt iam non solvitur.",
		"forewarn_turns": 5,
		# LOREM — owner lore pending.
		"forewarn_body": "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Subsidium viridis mox exspirabit.",
		"source": "policy",
		"deeplink": {"panel": "money"},
		"persistent": true,
		"auto_dismiss_turns": 6,
	})
	for e in Schedule.SCHEDULE:
		EventScheduler.schedule(int(e.effective_turn), {
			"id": "policy:%s" % str(e.id),
			"kind": "policy_enacted",
			"severity": str(e.get("severity", "warning")),
			"title": "%s now in effect" % str(e.title),
			"body": str(e.get("body", "")),                      # LOREM — owner lore pending
			"forewarn_turns": int(e.get("forewarn_turns", 0)),
			"forewarn_body": str(e.get("forewarn_body", "")),    # LOREM — owner lore pending
			"source": "policy",
			"deeplink": {"panel": "money"},
			"persistent": true,
			"auto_dismiss_turns": 6,
		})

# Reserve the blocking "Understood" notice so it presents on turn 90's DECIDE
# (reservations fire in the previous turn's NARRATIVE). Re-armed on every seed/load
# because DecisionState reservations don't persist in saves; guarded so a notice the
# player already answered (history) or has pending never re-fires, and skipped
# entirely once the levy itself is in force.
func _arm_carbon_notice() -> void:
	var turn := int(TurnManager.current_turn)
	if turn >= CO2_P1_TURN:
		return
	for rec in DecisionState.history():
		if str(rec.get("def_id", "")) == CO2_NOTICE_DEF:
			return
	for d in DecisionState.pending_queue:
		if str(d.get("def_id", "")) == CO2_NOTICE_DEF:
			return
	# Late loads (turn 90..100 without the notice answered) still get it next turn.
	DecisionState.reserve(maxi(CO2_NOTICE_PRESENT_TURN - 1, turn), CO2_NOTICE_DEF)

# --- Save / load (additive key; tolerant reader, no version bump) ---------------------

func export_state() -> Dictionary:
	return {"seeded": _seeded}

func import_state(d: Dictionary) -> void:
	# Old saves (no "policy" key) arrive as {} → seeded=false → the schedule seeds on
	# this load; beats already past their turn simply won't re-fire (their turn is gone)
	# while the LEVELS are pure functions of the turn and are always correct.
	_seeded = bool(d.get("seeded", false))
	call_deferred("_seed_if_needed")
