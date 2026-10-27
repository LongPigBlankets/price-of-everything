extends Node
## LabourState: the workforce (docs/pacing-labour-mining-licensing-spec.md §4). The eight Labour
## knobs (work effort, pay while idle, safety, pensions, annual bonus, profit share, union, work
## week), the automation switch and the locker policies, and the labour SATISFACTION they set.
##
## Every policy trades three things: THROUGHPUT (inputs, outputs and power scale together, through
## MatchState.run_multiplier), cash (labour, maintenance, power) and satisfaction. No policy makes
## product from nothing; the only output-only effect is the +5% prize at satisfaction of +90.
##
## Satisfaction (−100…+100) moves toward a TARGET built from the policies' contributions, the
## company's own (workforce size, the HR Director) and timed target shifts, by max(10% of the gap,
## 2) a turn. Reneging on union agreements is the only instant change.
##
## A Comprehensive Union Agreement halves every labour cost REDUCTION gained after it is signed.
## The cuts in force at signing are recorded by source id and keep their full strength, and the
## halving outlives the union until the company reneges.
##
## Saved under MatchState's "match" section (MatchState.export_state merges export_fields(),
## import_state calls import_fields(), reset() calls reset()). Turn hooks: TurnManager wires
## _on_phase_started first in PROCESS; Production calls tick_workforce_policies() at its fixed
## PROCESS point.


const WORKFORCE_POLICY_GENEROUS_PENSIONS := "generous_pensions"
const WORKFORCE_POLICY_EXTENDED_ANNUAL_LEAVE := "extended_annual_leave"
const WORKFORCE_POLICY_GENEROUS_PARENTAL_LEAVE := "generous_parental_leave"
const WORKFORCE_POLICY_STRICT_SAFETY := "strict_safety_procedures"
const WORKFORCE_POLICY_STANDARD_SAFETY := "standard_safety_procedures"
const WORKFORCE_POLICY_LAX_SAFETY := "lax_safety_procedures"
const WORKFORCE_POLICY_ANNUAL_BONUS := "annual_bonus"
const WORKFORCE_POLICY_ANNUAL_PROFIT_SHARE := "annual_profit_share"
# Ids must stay exactly these strings: older saves carry them.
const WORKFORCE_POLICY_PENSIONS_MINIMUM := "pensions_minimum_legal"
const WORKFORCE_POLICY_SMALL_BONUS := "annual_bonus_small"
const WORKFORCE_POLICY_PROFIT_SHARE_10 := "profit_share_10"
const WORKFORCE_POLICY_PUSH_AUTOMATION := "push_automation"
# HR Director unlocks: Long Tenure Awards (any HR Director) and Stock Options (an HR mission).
const WORKFORCE_POLICY_LONG_TENURE := "long_tenure_awards"
const WORKFORCE_POLICY_STOCK_OPTIONS := "stock_options"
# The two union tiers. The union is a knob, stored as one of these flags (or neither).
const WORKFORCE_POLICY_UNION_PARTIAL := "union_partial"
const WORKFORCE_POLICY_UNION_COMPREHENSIVE := "union_comprehensive"
const WORKFORCE_POLICY_GAME_LENGTH_TURNS := 300
const WORKFORCE_SAFETY_POLICIES := [
	WORKFORCE_POLICY_STRICT_SAFETY,
	WORKFORCE_POLICY_STANDARD_SAFETY,
	WORKFORCE_POLICY_LAX_SAFETY,
]
const WORKFORCE_UNION_POLICIES := [WORKFORCE_POLICY_UNION_PARTIAL, WORKFORCE_POLICY_UNION_COMPREHENSIVE]
# Mutually-exclusive spectrum groups: enabling one member disables the others
# sim-side, so a tampered or pre-wiring save can never double-dip a spectrum.
const WORKFORCE_EXCLUSIVE_GROUPS := [
	WORKFORCE_SAFETY_POLICIES,
	[WORKFORCE_POLICY_PENSIONS_MINIMUM, WORKFORCE_POLICY_GENEROUS_PENSIONS],
	[WORKFORCE_POLICY_SMALL_BONUS, WORKFORCE_POLICY_ANNUAL_BONUS],
	[WORKFORCE_POLICY_ANNUAL_PROFIT_SHARE, WORKFORCE_POLICY_PROFIT_SHARE_10],
	WORKFORCE_UNION_POLICIES,
]
## "Worker pay while building not running": what share of a workforce's pay a building owes on a
## turn it produced NOTHING. Keyed on zero output, never on "starving".
const IDLE_LABOUR_PAY_CHOICES: Array[float] = [0.5, 0.75, 1.0]

## Mines, furnaces, power plants, EAFs, refineries, chemical and polymer plants and oil wells. Safety
## acts here: Minimal safety's throughput, High safety's labour cost.
const HAZARDOUS_BUILDINGS := {
	"b_001": true, "b_002": true, "b_003": true, "b_008": true, "b_011": true,
	"b_012": true, "b_013": true, "b_032": true, "b_033": true, "b_034": true,
}

# --- Work effort (the labour_multiplier knob: 0.8 Lean, 1.0 Standard, 1.2 Overtime) ---
const EFFORT_SALARY := {"lean": -0.20, "standard": 0.0, "overtime": 0.25}
const EFFORT_THROUGHPUT_PCT := {"lean": -10.0, "standard": 0.0, "overtime": 15.0}
const EFFORT_SATISFACTION := {"lean": -15.0, "standard": 0.0, "overtime": -25.0}

# --- Work week ---
const WORK_WEEK_HOURS: Array[int] = [35, 40, 45, 50]
const WORK_WEEK_DEFAULT := 45
const WORK_WEEK_THROUGHPUT_PCT := {35: 5.0, 40: 9.0, 45: 12.0, 50: 14.5}
const WORK_WEEK_UNION_LABOUR_PER_LEVEL := 0.10
const WORK_WEEK_SATISFACTION_PER_LEVEL := -2.5

# --- Safety, pensions, bonus, profit share, automation, lockers ---
const MINIMAL_SAFETY_THROUGHPUT_PCT := 10.0
const MINIMAL_SAFETY_LABOUR := -0.05
const HIGH_SAFETY_LABOUR := 0.05
const MINIMUM_PENSIONS_LABOUR := -0.05
const GENEROUS_PENSIONS_MATURE_TURNS := 30
const SMALL_BONUS_LABOUR := 0.025
const GENEROUS_BONUS_LABOUR := 0.05
const AUTOMATION_MIN_LEVEL := 2
const AUTOMATION_LABOUR := -0.15
const AUTOMATION_POWER_MULT := 1.10
const AUTOMATION_MAINT_MULT := 1.10
const LEAVE_THROUGHPUT_PCT := -2.0
const LONG_TENURE_PAYOUT := 0.10
## Satisfaction from the pay while idle setting, by its share: below 60%, below 90%, otherwise.
const IDLE_PAY_SATISFACTION := {"half": -10.0, "most": -5.0, "full": 5.0}
const MINIMAL_SAFETY_SATISFACTION := -20.0
const HIGH_SAFETY_SATISFACTION := 10.0
const MINIMUM_PENSIONS_SATISFACTION := -10.0
const AUTOMATION_SATISFACTION := -5.0
## Metal Magnate's and Glass Merchant's workforce while the company still owns the Original Furnace (LegacyPerk).
const LIKE_FAMILY_SATISFACTION := 25.0

# --- Unions ---
const UNION_NONE := 0
const UNION_PARTIAL := 1
const UNION_COMPREHENSIVE := 2
const UNION_LABOUR_BASE := 0.10
const UNION_LABOUR_PER_ROUND := 0.01
const UNION_LABOUR_CAP := 0.25
const UNION_PAY_ROUND_TURNS := 10
const UNION_STEP_DOWN_REVENUE_SHARE := 0.05
const UNION_STEP_DOWN_SHIFT := -15.0
const UNION_STEP_DOWN_DECAY := 0.5
const UNION_HALVING := 0.5
const RENEGE_SATISFACTION := -50.0

# --- Satisfaction ---
const SATISFACTION_MIN := -100.0
const SATISFACTION_MAX := 100.0
const SATISFACTION_STEP_SHARE := 0.10
const SATISFACTION_STEP_MIN := 2.0
const SATISFACTION_PRIZE_AT := 90.0
const SATISFACTION_PRIZE_OUTPUT := 1.05
const BAND_FAST_AT := 50.0
const BAND_SLOW_BELOW := -5.0
const BAND_STRIKE_BELOW := -70.0
const BAND_STRIKE_HEAVY_BELOW := -90.0
const FILL_TURNS := {"fast": 5, "normal": 8, "slow": 12}
const EVENT_SHIFT_TURNS := 10
const WORKFORCE_SIZE_STEPS: Array[int] = [5000, 25000]
const WORKFORCE_SIZE_STEP_SATISFACTION := 5.0
const HR_TIER_SATISFACTION := {1: -5.0, 2: 0.0, 3: 5.0}

signal labour_multiplier_changed(new_value: float)
signal workforce_policies_changed
## Satisfaction, its target or its ledger changed (tick, policy change, renege).
signal satisfaction_changed
## A strike warning, strike, pay rise or accident changed (LabourUnrest).
signal unrest_changed

var labour_multiplier: float = EconomyConfig.LABOUR_MULTIPLIER_DEFAULT
var workforce_policies: Dictionary = {}
var workforce_policy_effects: Dictionary = {}
var idle_labour_pay_share: float = 1.0
var work_week_hours: int = WORK_WEEK_DEFAULT
var satisfaction: float = 0.0
## Timed target shifts: [{id, label, value, decay, turns_left}]. A shift with decay > 0 shrinks
## toward 0 by `decay` a turn and goes at 0; one without counts `turns_left` down.
var target_shifts: Array = []
## Turns a union agreement (either tier) has stood without a break: the pay-round ramp.
var union_active_turns: int = 0
var union_halving_active := false
var union_signed_turn: int = 0
## Source ids of the labour reductions in force when Comprehensive was signed (id -> true).
var union_grandfathered_ids: Dictionary = {}
## Harness switch, never saved: the unit suite turns the policies' throughput off so recipe tests
## see base quantities (tests/test_runner.gd). The game, the e2e and the probes leave it on.
var policy_throughput_enabled := true
## Strikes, pay rises and accidents (docs/pacing-labour-mining-licensing-spec.md §6, §4.5).
const LabourUnrest := preload("res://scripts/labour_unrest.gd")
const LegacyPerk := preload("res://scripts/legacy_perk.gd")
var unrest: LabourUnrest = LabourUnrest.new()


func _init() -> void:
	unrest.changed.connect(func() -> void: unrest_changed.emit())


## Match-scoped: cleared by MatchState.reset() (new game / scenario start).
func reset() -> void:
	workforce_policies.clear()
	workforce_policy_effects.clear()
	labour_multiplier = EconomyConfig.LABOUR_MULTIPLIER_DEFAULT
	idle_labour_pay_share = 1.0
	work_week_hours = WORK_WEEK_DEFAULT
	satisfaction = 0.0
	target_shifts.clear()
	union_active_turns = 0
	union_halving_active = false
	union_signed_turn = 0
	union_grandfathered_ids.clear()
	unrest.reset()


## Saved under MatchState's "match" section.
func export_fields() -> Dictionary:
	return {
		"labour_multiplier": labour_multiplier,
		"idle_labour_pay_share": idle_labour_pay_share,
		"workforce_policies": workforce_policies.duplicate(true),
		"workforce_policy_effects": workforce_policy_effects.duplicate(true),
		"work_week_hours": work_week_hours,
		"labour_satisfaction": satisfaction,
		"labour_target_shifts": target_shifts.duplicate(true),
		"union_active_turns": union_active_turns,
		"union_halving_active": union_halving_active,
		"union_signed_turn": union_signed_turn,
		"union_grandfathered_ids": union_grandfathered_ids.keys(),
	}.merged(unrest.export_fields())


## Older saves carry `labour_output_pressure_pct`; it is retired and ignored.
func import_fields(d: Dictionary) -> void:
	labour_multiplier = float(d.get("labour_multiplier", EconomyConfig.LABOUR_MULTIPLIER_DEFAULT))
	idle_labour_pay_share = float(d.get("idle_labour_pay_share", 1.0))
	workforce_policies = (d.get("workforce_policies", {}) as Dictionary).duplicate(true)
	workforce_policy_effects = (d.get("workforce_policy_effects", {}) as Dictionary).duplicate(true)
	var hours := int(d.get("work_week_hours", WORK_WEEK_DEFAULT))
	work_week_hours = hours if WORK_WEEK_HOURS.has(hours) else WORK_WEEK_DEFAULT
	satisfaction = clampf(float(d.get("labour_satisfaction", 0.0)), SATISFACTION_MIN, SATISFACTION_MAX)
	target_shifts.clear()
	for raw in d.get("labour_target_shifts", []) as Array:
		if raw is Dictionary:
			target_shifts.append(_clean_shift(raw as Dictionary))
	union_active_turns = maxi(0, int(d.get("union_active_turns", 0)))
	union_halving_active = bool(d.get("union_halving_active", false))
	union_signed_turn = int(d.get("union_signed_turn", 0))
	union_grandfathered_ids.clear()
	for id in d.get("union_grandfathered_ids", []) as Array:
		union_grandfathered_ids[str(id)] = true
	unrest.import_fields(d)


func _on_phase_started(phase: int) -> void:
	if phase == TurnManager.Phase.PROCESS:
		# First thing in PROCESS, before production reads the throughput and the output prize. Strikes and
		# accidents follow, on the satisfaction just reached.
		tick_satisfaction()
		unrest.tick(TurnManager.current_turn)


# ── Knobs ─────────────────────────────────────────────────────────────────────────────────────

func set_idle_labour_pay_share(value: float) -> void:
	# Off-menu values are REFUSED, not rounded: this is a three-position policy switch, and
	# silently snapping an unexpected value would hide a caller bug behind a plausible number.
	var matched := false
	for choice in IDLE_LABOUR_PAY_CHOICES:
		if is_equal_approx(choice, value):
			matched = true
	if not matched or is_equal_approx(value, idle_labour_pay_share):
		return
	idle_labour_pay_share = value
	labour_multiplier_changed.emit(labour_multiplier)   # the People panel repaints on this
	satisfaction_changed.emit()

func set_labour_multiplier(value: float) -> void:
	value = clamp(value, EconomyConfig.LABOUR_MULTIPLIER_MIN, EconomyConfig.LABOUR_MULTIPLIER_MAX)
	if value == labour_multiplier:
		return
	labour_multiplier = value
	_prune_grandfathered()
	labour_multiplier_changed.emit(value)
	satisfaction_changed.emit()

## "lean", "standard" or "overtime" from the effort knob.
func effort_key() -> String:
	if labour_multiplier < 1.0 - 0.001:
		return "lean"
	if labour_multiplier > 1.0 + 0.001:
		return "overtime"
	return "standard"

func set_work_week(hours: int) -> void:
	if not WORK_WEEK_HOURS.has(hours) or hours == work_week_hours:
		return
	work_week_hours = hours
	workforce_policies_changed.emit()
	satisfaction_changed.emit()

## 1 for 35 hours up to 4 for 50.
func work_week_level() -> int:
	return WORK_WEEK_HOURS.find(work_week_hours) + 1

func is_workforce_policy_available(policy_id: String) -> bool:
	match policy_id:
		WORKFORCE_POLICY_LONG_TENURE:
			return _hr_director_leadership() >= 0
		WORKFORCE_POLICY_STOCK_OPTIONS:
			return AdvisorState.advisor_mission_policies.has(WORKFORCE_POLICY_STOCK_OPTIONS)
		_:
			return true

# Leadership stat of the seated HR Director, or -1 if the seat is empty.
func _hr_director_leadership() -> int:
	var a: Dictionary = AdvisorState._roster_entry(str(AdvisorState.advisor_seats.get("hr_director", "")))
	return int(a.get("lead", 0)) if not a.is_empty() else -1

func set_workforce_policy_enabled(policy_id: String, enabled: bool) -> void:
	if policy_id == "":
		return
	# The union is a tier, with step-down costs: route its flags through set_union_tier.
	if WORKFORCE_UNION_POLICIES.has(policy_id):
		if enabled:
			set_union_tier(UNION_PARTIAL if policy_id == WORKFORCE_POLICY_UNION_PARTIAL else UNION_COMPREHENSIVE)
		elif is_workforce_policy_enabled(policy_id):
			set_union_tier(UNION_NONE)
		return
	if enabled and not is_workforce_policy_available(policy_id):
		return   # locked (HR Director not seated / lacks the required leadership)
	var was_enabled := bool(workforce_policies.get(policy_id, false))
	if was_enabled == enabled:
		return
	if enabled:
		for group in WORKFORCE_EXCLUSIVE_GROUPS:
			if (group as Array).has(policy_id):
				for member_id in (group as Array):
					if str(member_id) != policy_id:
						workforce_policies.erase(str(member_id))
		workforce_policies[policy_id] = true
		if not workforce_policy_effects.has(policy_id):
			workforce_policy_effects[policy_id] = {}
		if policy_id == WORKFORCE_POLICY_PUSH_AUTOMATION:
			add_target_shift("automation_on_%d" % int(TurnManager.current_turn), "Automation layoffs", -10.0)
	else:
		workforce_policies.erase(policy_id)
	_prune_grandfathered()
	workforce_policies_changed.emit()
	satisfaction_changed.emit()

func is_workforce_policy_enabled(policy_id: String) -> bool:
	return bool(workforce_policies.get(policy_id, false))

func workforce_policy_game_third_turns() -> int:
	return maxi(10, int(round(float(WORKFORCE_POLICY_GAME_LENGTH_TURNS) / 30.0)) * 10)


# ── Unions ────────────────────────────────────────────────────────────────────────────────────

## 0 none, 1 Partial, 2 Comprehensive.
func union_tier() -> int:
	if is_workforce_policy_enabled(WORKFORCE_POLICY_UNION_COMPREHENSIVE):
		return UNION_COMPREHENSIVE
	if is_workforce_policy_enabled(WORKFORCE_POLICY_UNION_PARTIAL):
		return UNION_PARTIAL
	return UNION_NONE

## Moves the union knob. Stepping down charges 5% of revenue per tier and a −15 target shift per
## tier decaying 0.5 a turn; Comprehensive to none is both steps. Signing Comprehensive records
## the labour cuts then in force (kept while a halving already stands).
func set_union_tier(tier: int) -> void:
	tier = clampi(tier, UNION_NONE, UNION_COMPREHENSIVE)
	var old := union_tier()
	if tier == old:
		return
	if tier < old:
		_step_down_union(old - tier)
	workforce_policies.erase(WORKFORCE_POLICY_UNION_PARTIAL)
	workforce_policies.erase(WORKFORCE_POLICY_UNION_COMPREHENSIVE)
	if tier == UNION_PARTIAL:
		workforce_policies[WORKFORCE_POLICY_UNION_PARTIAL] = true
	elif tier == UNION_COMPREHENSIVE:
		workforce_policies[WORKFORCE_POLICY_UNION_COMPREHENSIVE] = true
		unrest.clear_strike_breaking()
		if not union_halving_active:
			union_halving_active = true
			union_signed_turn = int(TurnManager.current_turn)
			union_grandfathered_ids = active_labour_reduction_ids()
	if tier == UNION_NONE:
		union_active_turns = 0
	workforce_policies_changed.emit()
	satisfaction_changed.emit()

func _step_down_union(steps: int) -> void:
	var turn := int(TurnManager.current_turn)
	var amount := LoanState.average_revenue() * UNION_STEP_DOWN_REVENUE_SHARE * float(steps)
	if amount > 0.0:
		MatchState.one_off_charges.append({"turn": turn, "amount": snappedf(amount, 0.01), "label": "Union settlement"})
	for i in range(steps):
		add_target_shift("union_step_down_%d_%d" % [turn, i], "Union agreement withdrawn",
			UNION_STEP_DOWN_SHIFT, 0, UNION_STEP_DOWN_DECAY)

## The labour cost of a standing union: +10%, then +1% each pay round (every 10 turns), to +25%.
func union_labour_delta(active_turns: int = -1) -> float:
	if union_tier() == UNION_NONE:
		return 0.0
	var turns := union_active_turns if active_turns < 0 else active_turns
	var rounds := floori(float(turns) / float(UNION_PAY_ROUND_TURNS))
	return minf(UNION_LABOUR_CAP, UNION_LABOUR_BASE + UNION_LABOUR_PER_ROUND * float(rounds))

func can_renege() -> bool:
	return union_tier() == UNION_NONE and union_halving_active

## Ends the Comprehensive halving for good: every labour cut counts in full again, and satisfaction
## falls 50 at once (the system's only instant change).
func renege_union_agreements() -> bool:
	if not can_renege():
		return false
	union_halving_active = false
	union_signed_turn = 0
	union_grandfathered_ids.clear()
	satisfaction = clampf(satisfaction + RENEGE_SATISFACTION, SATISFACTION_MIN, SATISFACTION_MAX)
	workforce_policies_changed.emit()
	satisfaction_changed.emit()
	return true

## 1.0, or 0.5 for a labour reduction gained after a Comprehensive signing while the halving stands.
func halving_weight(source_id: String, delta: float) -> float:
	if not union_halving_active or delta >= 0.0 or union_grandfathered_ids.has(source_id):
		return 1.0
	return UNION_HALVING

## Every labour reduction in force, across the generic company and each player building (id -> true).
func active_labour_reduction_ids() -> Dictionary:
	var ids: Dictionary = {}
	for part in labour_cost_parts({}):
		if float(part.delta) < 0.0:
			ids[str(part.id)] = true
	for b in BuildingState.buildings.values():
		if not BuildingState.is_player_owned(b):
			continue
		for part in labour_cost_parts(b):
			if float(part.delta) < 0.0:
				ids[str(part.id)] = true
	return ids

# A grandfathered cut that has ended leaves the record, so bringing it back later counts as new.
func _prune_grandfathered() -> void:
	if union_grandfathered_ids.is_empty():
		return
	var active := active_labour_reduction_ids()
	for id in union_grandfathered_ids.keys():
		if not active.has(id):
			union_grandfathered_ids.erase(id)


# ── Throughput and output ──────────────────────────────────────────────────────────────────────

## The labour policies' throughput for a building type, in percent (MatchState.run_multiplier adds
## the throughput modifiers to it).
func throughput_pct_for(building_id: String) -> float:
	var pct := 0.0
	for part in throughput_parts_for(building_id):
		pct += float(part.pct)
	return pct

## The same as labelled parts, for the Modifiers row and the ledger.
func throughput_parts_for(building_id: String) -> Array:
	var parts: Array = []
	if not policy_throughput_enabled:
		return parts
	var effort := float(EFFORT_THROUGHPUT_PCT[effort_key()])
	if effort != 0.0:
		parts.append({"pct": effort, "label": "Overtime" if effort > 0.0 else "Lean effort"})
	parts.append({"pct": float(WORK_WEEK_THROUGHPUT_PCT.get(work_week_hours, 0.0)), "label": "%d hour week" % work_week_hours})
	if is_workforce_policy_enabled(WORKFORCE_POLICY_LAX_SAFETY) and HAZARDOUS_BUILDINGS.has(building_id):
		parts.append({"pct": MINIMAL_SAFETY_THROUGHPUT_PCT, "label": "Minimal safety"})
	if is_workforce_policy_enabled(WORKFORCE_POLICY_EXTENDED_ANNUAL_LEAVE):
		parts.append({"pct": LEAVE_THROUGHPUT_PCT, "label": "Extended Annual Leave"})
	if is_workforce_policy_enabled(WORKFORCE_POLICY_GENEROUS_PARENTAL_LEAVE):
		parts.append({"pct": LEAVE_THROUGHPUT_PCT, "label": "Generous Parental Leave"})
	return parts

## The one output-only labour effect: +5% output on every building at satisfaction of +90 or more.
func workforce_output_multiplier(_turn_number: int = -1) -> float:
	return SATISFACTION_PRIZE_OUTPUT if satisfaction >= SATISFACTION_PRIZE_AT else 1.0

## Automation raises upkeep on the level 2+ buildings it runs. 1.0 = no change.
func workforce_maintenance_multiplier(building: Dictionary = {}) -> float:
	return AUTOMATION_MAINT_MULT if _automated(building) else 1.0

## Automation's extra power draw on the level 2+ buildings it runs. 1.0 = no change.
func workforce_power_multiplier(building: Dictionary = {}) -> float:
	return AUTOMATION_POWER_MULT if _automated(building) else 1.0

func _automated(building: Dictionary) -> bool:
	return is_workforce_policy_enabled(WORKFORCE_POLICY_PUSH_AUTOMATION) \
		and int(building.get("level", 1)) >= AUTOMATION_MIN_LEVEL

# Accrued Stock Options dividend bonus (0..0.10), added on top of the base dividend
# rate at the payout site; persists (decaying) after the policy is switched off.
func workforce_dividend_bonus() -> float:
	var e = workforce_policy_effects.get(WORKFORCE_POLICY_STOCK_OPTIONS, {})
	return float(e.get("dividend_pct", 0.0)) if e is Dictionary else 0.0


# ── Labour cost ─────────────────────────────────────────────────────────────────────────────────

## The labour policies' cost changes for `building` as [{id, label, delta}], fractions of its base
## bill. `{}` is a generic company building (not hazardous, level 1). `turns_ahead` projects the
## policy ramps and the union's pay rounds.
func labour_cost_components(building: Dictionary, turns_ahead: int = 0, at_turn: int = -1) -> Array:
	var effects: Dictionary = workforce_policy_effects if turns_ahead <= 0 else _projected_effects(turns_ahead)
	var turn := (int(TurnManager.current_turn) + maxi(0, turns_ahead)) if at_turn < 0 else at_turn
	var bid := str(building.get("building_id", ""))
	var parts: Array = []
	var key := effort_key()
	if key != "standard":
		parts.append({"id": "effort_" + key, "label": "Overtime" if key == "overtime" else "Lean effort", "delta": float(EFFORT_SALARY[key])})
	if is_workforce_policy_enabled(WORKFORCE_POLICY_LAX_SAFETY):
		parts.append({"id": WORKFORCE_POLICY_LAX_SAFETY, "label": "Minimal safety", "delta": MINIMAL_SAFETY_LABOUR})
	if is_workforce_policy_enabled(WORKFORCE_POLICY_STRICT_SAFETY) and HAZARDOUS_BUILDINGS.has(bid):
		parts.append({"id": WORKFORCE_POLICY_STRICT_SAFETY, "label": "High safety", "delta": HIGH_SAFETY_LABOUR})
	if is_workforce_policy_enabled(WORKFORCE_POLICY_PENSIONS_MINIMUM):
		parts.append({"id": WORKFORCE_POLICY_PENSIONS_MINIMUM, "label": "Minimum legal pensions", "delta": MINIMUM_PENSIONS_LABOUR})
	if is_workforce_policy_enabled(WORKFORCE_POLICY_GENEROUS_PENSIONS):
		var pension := float((effects.get(WORKFORCE_POLICY_GENEROUS_PENSIONS, {}) as Dictionary).get("labour_pct", 0.0))
		parts.append({"id": WORKFORCE_POLICY_GENEROUS_PENSIONS, "label": "Generous pensions", "delta": pension})
	if is_workforce_policy_enabled(WORKFORCE_POLICY_SMALL_BONUS):
		parts.append({"id": WORKFORCE_POLICY_SMALL_BONUS, "label": "Small annual bonus", "delta": SMALL_BONUS_LABOUR})
	if is_workforce_policy_enabled(WORKFORCE_POLICY_ANNUAL_BONUS):
		parts.append({"id": WORKFORCE_POLICY_ANNUAL_BONUS, "label": "Generous annual bonus", "delta": GENEROUS_BONUS_LABOUR})
	if _automated(building):
		parts.append({"id": WORKFORCE_POLICY_PUSH_AUTOMATION, "label": "Automation", "delta": AUTOMATION_LABOUR})
	var tenure := float((effects.get(WORKFORCE_POLICY_LONG_TENURE, {}) as Dictionary).get("labour_pct", 0.0))
	if absf(tenure) > 0.000001:
		parts.append({"id": WORKFORCE_POLICY_LONG_TENURE, "label": "Long Tenure Awards", "delta": tenure})
	# Long Tenure Awards: a payout spike of +10% labour one turn every 10th turn.
	if is_workforce_policy_enabled(WORKFORCE_POLICY_LONG_TENURE) and turn > 0 and turn % 10 == 0:
		parts.append({"id": "long_tenure_awards_payout", "label": "Long Tenure payout", "delta": LONG_TENURE_PAYOUT})
	var raise_left := int(unrest.pay_raises.get(str(building.get("instance_id", "")), 0))
	if raise_left > maxi(0, turns_ahead):
		parts.append({"id": "pay_raise", "label": "Pay rise", "delta": LabourUnrest.PAY_RAISE})
	var union := union_tier()
	if union != UNION_NONE:
		var union_id := WORKFORCE_POLICY_UNION_COMPREHENSIVE if union == UNION_COMPREHENSIVE else WORKFORCE_POLICY_UNION_PARTIAL
		parts.append({"id": union_id, "label": "Union agreement",
			"delta": union_labour_delta(union_active_turns + maxi(0, turns_ahead))})
		parts.append({"id": "work_week", "label": "%d hour week" % work_week_hours,
			"delta": WORK_WEEK_UNION_LABOUR_PER_LEVEL * float(work_week_level())})
	return parts

## Every labour cost change for `building`: the policies plus its head-count modifiers (research,
## advisor seats, mission rewards), each with the weight the Comprehensive halving gives it.
func labour_cost_parts(building: Dictionary, turns_ahead: int = 0) -> Array:
	var parts := labour_cost_components(building, turns_ahead)
	var bid := str(building.get("building_id", ""))
	var res: Dictionary = Modifiers.resolve_pct("labour_headcount", bid,
		{"building_id": bid, "instance_id": str(building.get("instance_id", ""))})
	for p in res.get("parts", []) as Array:
		parts.append({"id": str((p as Dictionary).get("id", "")), "label": str((p as Dictionary).get("label", "")),
			"delta": float((p as Dictionary).get("pct", 0.0)) / 100.0})
	for p in parts:
		(p as Dictionary)["weight"] = halving_weight(str(p.id), float(p.delta))
	return parts

## The labour cost factor for `building`: 1 + every weighted labour change, floored at
## EconomyConfig.LABOUR_FACTOR_MIN (the floor applies after the halving).
func labour_cost_factor_for(building: Dictionary, turns_ahead: int = 0) -> float:
	var total := 0.0
	for p in labour_cost_parts(building, turns_ahead):
		total += float(p.delta) * float(p.weight)
	return maxf(EconomyConfig.LABOUR_FACTOR_MIN, 1.0 + total)

## The policies' summed labour change for a generic building (displays and the advisor tests).
## `turn_number` only moves the Long Tenure payout turn; the ramps stay at today's values.
func workforce_labour_cost_delta(turn_number: int = -1) -> float:
	var total := 0.0
	for p in labour_cost_components({}, 0, turn_number):
		total += float(p.delta) * halving_weight(str(p.id), float(p.delta))
	return total

func workforce_labour_cost_multiplier() -> float:
	return maxf(0.0, 1.0 + workforce_labour_cost_delta())

## The policies' summed labour change `turns_ahead` turns forward (the Labour panel's estimate).
func projected_workforce_labour_delta(turns_ahead: int) -> float:
	var total := 0.0
	for p in labour_cost_components({}, maxi(0, turns_ahead)):
		total += float(p.delta) * halving_weight(str(p.id), float(p.delta))
	return total

## The generic labour factor (no building context) for displays that lack a building.
func labour_policy_factor() -> float:
	return labour_cost_factor_for({})


# ── Policy ramps (generous pensions, long tenure, stock options) ─────────────────────────────

func tick_workforce_policies() -> void:
	var ids: Array = workforce_policy_effects.keys()
	for policy_id in workforce_policies.keys():
		if not ids.has(policy_id):
			ids.append(policy_id)
	for raw_id in ids:
		var policy_id := str(raw_id)
		var active := is_workforce_policy_enabled(policy_id)
		var effect: Dictionary = workforce_policy_effects.get(policy_id, {})
		_advance_workforce_effect(policy_id, effect, active)
		if not active and absf(float(effect.get("labour_pct", 0.0))) < 0.00001 and absf(float(effect.get("dividend_pct", 0.0))) < 0.00001:
			workforce_policy_effects.erase(policy_id)
		else:
			workforce_policy_effects[policy_id] = effect

# Advance one policy's accrued effect by a single turn (mutates `effect` in place). Shared by the
# live tick and the projection, so both stay in lockstep.
func _advance_workforce_effect(policy_id: String, effect: Dictionary, active: bool) -> void:
	effect["active_turns"] = int(effect.get("active_turns", 0)) + 1 if active else 0
	var labour_pct := float(effect.get("labour_pct", 0.0))
	match policy_id:
		WORKFORCE_POLICY_GENEROUS_PENSIONS:
			labour_pct = labour_pct + _pension_labour_step(int(effect.get("active_turns", 0))) if active else 0.0
		WORKFORCE_POLICY_LONG_TENURE:
			# Long-serving staff get cheaper over time (to -10%).
			if active:
				labour_pct = maxf(-0.10, labour_pct - 0.001)
			else:
				labour_pct = minf(0.0, labour_pct + 0.0025)
		WORKFORCE_POLICY_STOCK_OPTIONS:
			# Ownership stake grows the dividend (to +10pp).
			var div_pct := float(effect.get("dividend_pct", 0.0))
			if active:
				div_pct = minf(0.10, div_pct + 0.0005)
			else:
				div_pct = maxf(0.0, div_pct - 0.001)
			effect["dividend_pct"] = div_pct
			labour_pct = 0.0
		_:
			labour_pct = 0.0
	effect["labour_pct"] = labour_pct
	effect.erase("output_pct")
	effect.erase("maint_pct")

func _pension_labour_step(active_turns: int) -> float:
	var third := workforce_policy_game_third_turns()
	if active_turns <= third:
		return 0.001
	if active_turns <= third * 2:
		return 0.0025
	return 0.004

func _projected_effects(turns_ahead: int) -> Dictionary:
	var effects: Dictionary = {}
	for k in workforce_policy_effects.keys():
		var e = workforce_policy_effects[k]
		effects[str(k)] = (e as Dictionary).duplicate(true) if e is Dictionary else {}
	var ids: Array = effects.keys()
	for policy_id in workforce_policies.keys():
		if not ids.has(str(policy_id)):
			ids.append(str(policy_id))
	for _turn in range(turns_ahead):
		for raw_id in ids:
			var policy_id := str(raw_id)
			var effect: Dictionary = effects.get(policy_id, {})
			_advance_workforce_effect(policy_id, effect, is_workforce_policy_enabled(policy_id))
			effects[policy_id] = effect
	return effects


# ── Satisfaction ───────────────────────────────────────────────────────────────────────────────

## Every standing contribution to the target as [{id, label, value}], zero ones left out.
func satisfaction_contributions() -> Array:
	var parts: Array = []
	_add_part(parts, "effort", "Overtime" if effort_key() == "overtime" else "Lean effort", float(EFFORT_SATISFACTION[effort_key()]))
	var idle := float(IDLE_PAY_SATISFACTION.full)
	if idle_labour_pay_share < 0.6:
		idle = float(IDLE_PAY_SATISFACTION.half)
	elif idle_labour_pay_share < 0.9:
		idle = float(IDLE_PAY_SATISFACTION.most)
	_add_part(parts, "idle_pay", "Pay while idle %d%%" % int(round(idle_labour_pay_share * 100.0)), idle)
	if is_workforce_policy_enabled(WORKFORCE_POLICY_LAX_SAFETY):
		_add_part(parts, WORKFORCE_POLICY_LAX_SAFETY, "Minimal safety", MINIMAL_SAFETY_SATISFACTION)
	elif is_workforce_policy_enabled(WORKFORCE_POLICY_STRICT_SAFETY):
		_add_part(parts, WORKFORCE_POLICY_STRICT_SAFETY, "High safety", HIGH_SAFETY_SATISFACTION)
	if is_workforce_policy_enabled(WORKFORCE_POLICY_PENSIONS_MINIMUM):
		_add_part(parts, WORKFORCE_POLICY_PENSIONS_MINIMUM, "Minimum legal pensions", MINIMUM_PENSIONS_SATISFACTION)
	elif is_workforce_policy_enabled(WORKFORCE_POLICY_GENEROUS_PENSIONS):
		var turns := int((workforce_policy_effects.get(WORKFORCE_POLICY_GENEROUS_PENSIONS, {}) as Dictionary).get("active_turns", 0))
		_add_part(parts, WORKFORCE_POLICY_GENEROUS_PENSIONS, "Generous pensions", 20.0 if turns >= GENEROUS_PENSIONS_MATURE_TURNS else 10.0)
	if is_workforce_policy_enabled(WORKFORCE_POLICY_SMALL_BONUS):
		_add_part(parts, WORKFORCE_POLICY_SMALL_BONUS, "Small annual bonus", 8.0)
	elif is_workforce_policy_enabled(WORKFORCE_POLICY_ANNUAL_BONUS):
		_add_part(parts, WORKFORCE_POLICY_ANNUAL_BONUS, "Generous annual bonus", 15.0)
	if is_workforce_policy_enabled(WORKFORCE_POLICY_ANNUAL_PROFIT_SHARE):
		_add_part(parts, WORKFORCE_POLICY_ANNUAL_PROFIT_SHARE, "Profit share 5%", 10.0)
	elif is_workforce_policy_enabled(WORKFORCE_POLICY_PROFIT_SHARE_10):
		_add_part(parts, WORKFORCE_POLICY_PROFIT_SHARE_10, "Profit share 10%", 20.0)
	match union_tier():
		UNION_PARTIAL:
			_add_part(parts, WORKFORCE_POLICY_UNION_PARTIAL, "Partial Union Agreement", 15.0)
		UNION_COMPREHENSIVE:
			_add_part(parts, WORKFORCE_POLICY_UNION_COMPREHENSIVE, "Comprehensive Union Agreement", 30.0)
		_:
			_add_part(parts, "work_week", "%d hour week" % work_week_hours, WORK_WEEK_SATISFACTION_PER_LEVEL * float(work_week_level()))
	if is_workforce_policy_enabled(WORKFORCE_POLICY_PUSH_AUTOMATION):
		_add_part(parts, WORKFORCE_POLICY_PUSH_AUTOMATION, "Automation", AUTOMATION_SATISFACTION)
	if is_workforce_policy_enabled(WORKFORCE_POLICY_EXTENDED_ANNUAL_LEAVE):
		_add_part(parts, WORKFORCE_POLICY_EXTENDED_ANNUAL_LEAVE, "Extended Annual Leave", 8.0)
	if is_workforce_policy_enabled(WORKFORCE_POLICY_GENEROUS_PARENTAL_LEAVE):
		_add_part(parts, WORKFORCE_POLICY_GENEROUS_PARENTAL_LEAVE, "Generous Parental Leave", 8.0)
	if is_workforce_policy_enabled(WORKFORCE_POLICY_LONG_TENURE):
		_add_part(parts, WORKFORCE_POLICY_LONG_TENURE, "Long Tenure Awards", 5.0)
	if is_workforce_policy_enabled(WORKFORCE_POLICY_STOCK_OPTIONS):
		_add_part(parts, WORKFORCE_POLICY_STOCK_OPTIONS, "Stock Options", 10.0)
	if LegacyPerk.holds():
		_add_part(parts, "like_family", "Like Family", LIKE_FAMILY_SATISFACTION)
	if unrest.routinely_broke:
		_add_part(parts, "routinely_broke_strikes", "Routinely broke strikes", LabourUnrest.ROUTINE_SATISFACTION)
	var workers := workforce_headcount()
	for step in WORKFORCE_SIZE_STEPS:
		if workers > step:
			_add_part(parts, "workforce_%d" % step, "Workforce over %s" % _thousands(step), WORKFORCE_SIZE_STEP_SATISFACTION)
	var tier := hr_director_tier()
	_add_part(parts, "hr_director", "HR Director, %d star%s" % [tier, "" if tier == 1 else "s"], float(HR_TIER_SATISFACTION.get(tier, 0.0)))
	return parts

func _add_part(parts: Array, id: String, label: String, value: float) -> void:
	if absf(value) > 0.0001:
		parts.append({"id": id, "label": label, "value": value})

## The company's workforce: the Labour tab's headcount (Production.labour_headcount).
func workforce_headcount() -> int:
	var heads: Dictionary = Production.labour_headcount()
	return int(heads.get("unskilled", 0)) + int(heads.get("skilled", 0)) + int(heads.get("high_skilled", 0))

## The seated HR Director's seat tier (stars), or 0 with the seat empty.
func hr_director_tier() -> int:
	var aid := str(AdvisorState.advisor_seats.get("hr_director", ""))
	if aid == "":
		return 0
	return AdvisorState.advisor_seat_tier(aid, "hr_director")

## The target: contributions plus the timed shifts, clamped.
func target_satisfaction() -> float:
	var total := 0.0
	for part in satisfaction_contributions():
		total += float(part.value)
	for shift in target_shifts:
		total += float((shift as Dictionary).get("value", 0.0))
	return clampf(total, SATISFACTION_MIN, SATISFACTION_MAX)

## Adds a timed target shift. With `decay` > 0 it shrinks by that much a turn and goes at 0;
## otherwise it lasts `turns` turns.
func add_target_shift(id: String, label: String, value: float, turns: int = EVENT_SHIFT_TURNS, decay: float = 0.0) -> void:
	target_shifts.append(_clean_shift({"id": id, "label": label, "value": value, "decay": decay,
		"turns_left": turns if decay <= 0.0 else -1}))
	satisfaction_changed.emit()

func _clean_shift(d: Dictionary) -> Dictionary:
	return {"id": str(d.get("id", "")), "label": str(d.get("label", "")), "value": float(d.get("value", 0.0)),
		"decay": maxf(0.0, float(d.get("decay", 0.0))), "turns_left": int(d.get("turns_left", -1))}

# One turn of ageing for a list of shifts (live or projected copy); returns what remains.
func _aged_shifts(shifts: Array) -> Array:
	var kept: Array = []
	for raw in shifts:
		var s: Dictionary = (raw as Dictionary).duplicate()
		if float(s["decay"]) > 0.0:
			var v := float(s["value"])
			v = minf(0.0, v + float(s["decay"])) if v < 0.0 else maxf(0.0, v - float(s["decay"]))
			s["value"] = v
			if absf(v) > 0.0001:
				kept.append(s)
		else:
			s["turns_left"] = int(s["turns_left"]) - 1
			if int(s["turns_left"]) > 0:
				kept.append(s)
	return kept

## One turn of movement: max(10% of the gap, 2) toward the target, landing on it within 2.
static func step_toward(current: float, target: float) -> float:
	var gap := target - current
	if absf(gap) <= SATISFACTION_STEP_MIN:
		return target
	return current + signf(gap) * maxf(absf(gap) * SATISFACTION_STEP_SHARE, SATISFACTION_STEP_MIN)

## Once a turn at the start of PROCESS: move toward the target, age the shifts, count the union's
## pay rounds.
func tick_satisfaction() -> void:
	satisfaction = step_toward(satisfaction, target_satisfaction())
	target_shifts = _aged_shifts(target_shifts)
	if union_tier() != UNION_NONE:
		union_active_turns += 1
	_prune_grandfathered()
	satisfaction_changed.emit()

## Satisfaction `turns` ticks from now with today's policies (the dial's ghost needle).
func projected_satisfaction(turns: int) -> float:
	var value := satisfaction
	var shifts := target_shifts.duplicate(true)
	var base := 0.0
	for part in satisfaction_contributions():
		base += float(part.value)
	for _i in range(maxi(0, turns)):
		var target := base
		for s in shifts:
			target += float((s as Dictionary).get("value", 0.0))
		value = step_toward(value, clampf(target, SATISFACTION_MIN, SATISFACTION_MAX))
		shifts = _aged_shifts(shifts)
	return value

## "prize" (+90 and up), "fast" (+50), "normal" (−5 to +50), "slow" (under −5), "strike" (under
## −70), "strike_heavy" (under −90).
func satisfaction_band(value: float = INF) -> String:
	var v := satisfaction if is_inf(value) else value
	if v < BAND_STRIKE_HEAVY_BELOW:
		return "strike_heavy"
	if v < BAND_STRIKE_BELOW:
		return "strike"
	if v < BAND_SLOW_BELOW:
		return "slow"
	if v >= SATISFACTION_PRIZE_AT:
		return "prize"
	if v >= BAND_FAST_AT:
		return "fast"
	return "normal"

## Turns a new site takes to fill its staff in the current band (used by staffing, phase 2).
func fill_turns() -> int:
	var band := satisfaction_band()
	if band == "prize" or band == "fast":
		return int(FILL_TURNS.fast)
	if band == "normal":
		return int(FILL_TURNS.normal)
	return int(FILL_TURNS.slow)

## The band as the panels describe it: {title, tone, words}. Only effects that are live are named.
func band_summary(value: float = INF) -> Dictionary:
	match satisfaction_band(value):
		"prize":
			return {"title": "Proud", "tone": "ok", "words": "Every building makes 5% more while satisfaction holds at 90 or above."}
		"fast":
			return {"title": "Content", "tone": "ok", "words": "At 90+, output increases by 5%"}
		"normal":
			return {"title": "Steady", "tone": "", "words": "At 90+, output increases by 5%"}
		"slow":
			return {"title": "Unhappy", "tone": "warn", "words": "Better pay, shorter hours or a union bring it back up."}
	return {"title": "Restless", "tone": "bad", "words": "Better pay, shorter hours or a union bring it back up."}

## A satisfaction figure as the panels print it: "+42", "−18", "0".
## A contribution as the ledger and the knobs show it: whole points, or a half point where there is one (−2.5).
static func contribution_text(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return signed_text(value)
	return ("+%.1f" if value > 0.0 else "−%.1f") % absf(value)

## The size of a contribution without its sign, for the knob words: "15", "2.5".
static func points_text(value: float) -> String:
	return contribution_text(absf(value)).trim_prefix("+")

static func signed_text(value: float) -> String:
	var n := roundi(value)
	if n > 0:
		return "+%d" % n
	if n < 0:
		return "−%d" % -n
	return "0"

## "rising", "falling" or "steady": where satisfaction is heading this turn.
func satisfaction_trend() -> String:
	var gap := target_satisfaction() - satisfaction
	if absf(gap) < 0.05:
		return "steady"
	return "rising" if gap > 0.0 else "falling"

## A building left the company: a demolished staffed building moves the target −15 for 10 turns.
func on_building_demolished(instance_id: String) -> void:
	add_target_shift("demolished_%s" % instance_id, "Building demolished", -15.0)

## A sold building moves the target −5 for 10 turns.
func on_building_sold(instance_id: String) -> void:
	add_target_shift("sold_%s" % instance_id, "Building sold", -5.0)

static func _thousands(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out


# ── Advisor seat framework hooks ────────────────────────────────────────────────────────────────

# Switch off any HR-gated workforce policy whose advisor requirement is no longer met
# (e.g. the HR Director was un-seated or fired) so the benefit can't outlive the seat.
func _revoke_unavailable_workforce_policies() -> void:
	for pid in [WORKFORCE_POLICY_LONG_TENURE, WORKFORCE_POLICY_STOCK_OPTIONS]:
		if is_workforce_policy_enabled(pid) and not is_workforce_policy_available(pid):
			set_workforce_policy_enabled(pid, false)

func _count_enabled_workforce_policies() -> int:
	var n := 0
	for pid in workforce_policies:
		if bool(workforce_policies[pid]):
			n += 1
	return n
