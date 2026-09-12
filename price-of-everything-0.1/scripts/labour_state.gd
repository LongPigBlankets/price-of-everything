extends Node
## LabourState: the workforce — the labour slider (labour_multiplier and the output pressure
## it builds up), the idle-labour pay policy, and the workforce policies (safety spectrum,
## pensions, bonuses, profit share, automation, HR-director unlocks) with their per-turn
## effects on output, maintenance, labour cost and dividends. Extracted from MatchState on
## 2026-09-12; the save keys are unchanged and still live under the "match" section
## (MatchState.export_state merges export_fields(), import_state calls import_fields(),
## reset() calls reset()).
##
## Turn hooks: TurnManager._wire_sim_listeners connects _on_phase_started FIRST so the
## output-pressure tick precedes MatchState's PROCESS hook; Production calls
## tick_workforce_policies() at its fixed PROCESS point. Advisor-gated policies read the
## council through AdvisorState.


const WORKFORCE_POLICY_GENEROUS_PENSIONS := "generous_pensions"
const WORKFORCE_POLICY_EXTENDED_ANNUAL_LEAVE := "extended_annual_leave"
const WORKFORCE_POLICY_GENEROUS_PARENTAL_LEAVE := "generous_parental_leave"
const WORKFORCE_POLICY_STRICT_SAFETY := "strict_safety_procedures"
const WORKFORCE_POLICY_STANDARD_SAFETY := "standard_safety_procedures"
const WORKFORCE_POLICY_LAX_SAFETY := "lax_safety_procedures"
const WORKFORCE_POLICY_ANNUAL_BONUS := "annual_bonus"
const WORKFORCE_POLICY_ANNUAL_PROFIT_SHARE := "annual_profit_share"
# The former Labour-tab placeholder rungs, now wired. Ids must stay exactly these
# strings: saves from before the wiring already carry them as no-effect entries.
const WORKFORCE_POLICY_PENSIONS_MINIMUM := "pensions_minimum_legal"
const WORKFORCE_POLICY_SMALL_BONUS := "annual_bonus_small"
const WORKFORCE_POLICY_PROFIT_SHARE_10 := "profit_share_10"
const WORKFORCE_POLICY_PUSH_AUTOMATION := "push_automation"
# HR Director unlocks: Long Tenure Awards (any HR Director) and Stock Options
# (only a Leadership-3 HR Director).
const WORKFORCE_POLICY_LONG_TENURE := "long_tenure_awards"
const WORKFORCE_POLICY_STOCK_OPTIONS := "stock_options"
const WORKFORCE_POLICY_GAME_LENGTH_TURNS := 300
const WORKFORCE_SAFETY_POLICIES := [
	WORKFORCE_POLICY_STRICT_SAFETY,
	WORKFORCE_POLICY_STANDARD_SAFETY,
	WORKFORCE_POLICY_LAX_SAFETY,
]
# Mutually-exclusive spectrum groups: enabling one member disables the others
# sim-side, so a tampered or pre-wiring save can never double-dip a spectrum.
const WORKFORCE_EXCLUSIVE_GROUPS := [
	WORKFORCE_SAFETY_POLICIES,
	[WORKFORCE_POLICY_PENSIONS_MINIMUM, WORKFORCE_POLICY_GENEROUS_PENSIONS],
	[WORKFORCE_POLICY_SMALL_BONUS, WORKFORCE_POLICY_ANNUAL_BONUS],
	[WORKFORCE_POLICY_ANNUAL_PROFIT_SHARE, WORKFORCE_POLICY_PROFIT_SHARE_10],
]
## "Worker pay while building not running": what share of a workforce's pay a building owes on a
## turn it produced NOTHING. 1.0 is the old behaviour (they are paid in full regardless).
## Deliberately keyed on zero output, never on "starving": a derated building still ran and is
## still in CostSolver, and paying it less would make its imputed cost FALL as it got sicker.
const IDLE_LABOUR_PAY_CHOICES: Array[float] = [0.5, 0.75, 1.0]

signal labour_multiplier_changed(new_value: float)
signal workforce_policies_changed

var labour_multiplier: float = EconomyConfig.LABOUR_MULTIPLIER_DEFAULT
# Accumulated output response (in percent) to the labour effort setting —
# negative = pressure from reduced effort, positive = overtime momentum.
# Accrued once per PROCESS by tick_labour_output_pressure(), applied by
# workforce_output_multiplier().
var labour_output_pressure_pct: float = 0.0
var workforce_policies: Dictionary = {}
var workforce_policy_effects: Dictionary = {}
var idle_labour_pay_share: float = 1.0


## Match-scoped: cleared by MatchState.reset() (new game / scenario start).
func reset() -> void:
	workforce_policies.clear()
	workforce_policy_effects.clear()
	labour_multiplier = EconomyConfig.LABOUR_MULTIPLIER_DEFAULT
	labour_output_pressure_pct = 0.0
	idle_labour_pay_share = 1.0


## Saved under MatchState's "match" section (keys unchanged from before the extraction).
func export_fields() -> Dictionary:
	return {
		"labour_multiplier": labour_multiplier,
		"labour_output_pressure_pct": labour_output_pressure_pct,
		"idle_labour_pay_share": idle_labour_pay_share,
		"workforce_policies": workforce_policies.duplicate(true),
		"workforce_policy_effects": workforce_policy_effects.duplicate(true),
	}


func import_fields(d: Dictionary) -> void:
	labour_multiplier = float(d.get("labour_multiplier", EconomyConfig.LABOUR_MULTIPLIER_DEFAULT))
	labour_output_pressure_pct = float(d.get("labour_output_pressure_pct", 0.0))
	idle_labour_pay_share = float(d.get("idle_labour_pay_share", 1.0))
	workforce_policies = (d.get("workforce_policies", {}) as Dictionary).duplicate(true)
	workforce_policy_effects = (d.get("workforce_policy_effects", {}) as Dictionary).duplicate(true)


func _on_phase_started(phase: int) -> void:
	if phase == TurnManager.Phase.PROCESS:
		# First thing in PROCESS, before MatchState's survey/battery ticks and long before
		# production reads the labour multiplier (the order the listener list guarantees).
		tick_labour_output_pressure()

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

func set_labour_multiplier(value: float) -> void:
	value = clamp(value, EconomyConfig.LABOUR_MULTIPLIER_MIN, EconomyConfig.LABOUR_MULTIPLIER_MAX)
	if value == labour_multiplier:
		return
	labour_multiplier = value
	labour_multiplier_changed.emit(value)
	print("[MatchState] Labour multiplier set to: %.2fx" % value)

## Per-PROCESS accrual of the labour setting's output response, exactly as the
## People panel promises: 0.8× builds output pressure (−2%/turn, floor −30%),
## 1.2× builds momentum (+1%/turn, cap +10%), 1.0× recovers 1%/turn toward 0.
## Runs at the start of PROCESS (before the production cascade), so the setting
## affects output from the first worked turn.
func tick_labour_output_pressure() -> void:
	var p := labour_output_pressure_pct
	if labour_multiplier < 1.0 - 0.001:
		p += EconomyConfig.LABOUR_OUTPUT_PRESSURE_PER_TURN
	elif labour_multiplier > 1.0 + 0.001:
		p += EconomyConfig.LABOUR_OUTPUT_MOMENTUM_PER_TURN
	else:
		p = move_toward(p, 0.0, EconomyConfig.LABOUR_OUTPUT_RECOVERY_PER_TURN)
	labour_output_pressure_pct = clampf(p,
		EconomyConfig.LABOUR_OUTPUT_PRESSURE_FLOOR,
		EconomyConfig.LABOUR_OUTPUT_MOMENTUM_CAP)

# Whether a policy can currently be toggled on. Long Tenure needs any seated HR
# Director; Stock Options is the unique policy unlocked by an HR advisor's mission V.
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
	else:
		workforce_policies.erase(policy_id)
	workforce_policies_changed.emit()

func is_workforce_policy_enabled(policy_id: String) -> bool:
	return bool(workforce_policies.get(policy_id, false))

func workforce_policy_game_third_turns() -> int:
	return maxi(10, int(round(float(WORKFORCE_POLICY_GAME_LENGTH_TURNS) / 30.0)) * 10)

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
		if not active and absf(float(effect.get("output_pct", 0.0))) < 0.00001 and absf(float(effect.get("labour_pct", 0.0))) < 0.00001 and absf(float(effect.get("dividend_pct", 0.0))) < 0.00001 and absf(float(effect.get("maint_pct", 0.0))) < 0.00001:
			workforce_policy_effects.erase(policy_id)
		else:
			workforce_policy_effects[policy_id] = effect

# Advance one policy's accrued effect by a single turn (mutates `effect` in place).
# Shared by the live tick and the forward projection the Labour panel uses for its
# 10-turn estimate, so both stay in lockstep.
func _advance_workforce_effect(policy_id: String, effect: Dictionary, active: bool) -> void:
	effect["active_turns"] = int(effect.get("active_turns", 0)) + (1 if active else 0)
	var output_pct := float(effect.get("output_pct", 0.0))
	var labour_pct := float(effect.get("labour_pct", 0.0))

	match policy_id:
		WORKFORCE_POLICY_GENEROUS_PENSIONS:
			if active:
				output_pct = minf(0.05, output_pct + 0.0005)
				labour_pct += _pension_labour_step(int(effect.get("active_turns", 0)))
			else:
				output_pct = maxf(0.0, output_pct - 0.001)
				labour_pct = 0.0
		WORKFORCE_POLICY_EXTENDED_ANNUAL_LEAVE, WORKFORCE_POLICY_GENEROUS_PARENTAL_LEAVE:
			if active:
				labour_pct = maxf(-0.05, labour_pct - 0.001)
			else:
				labour_pct = minf(0.0, labour_pct + 0.0025)
		WORKFORCE_POLICY_STRICT_SAFETY:
			if active:
				labour_pct = maxf(-0.15, labour_pct - 0.005)
			else:
				labour_pct = minf(0.0, labour_pct + 0.0025)
		WORKFORCE_POLICY_LAX_SAFETY:
			# Cutting corners lifts output a little but lets the plant rot: maintenance
			# climbs +5% every turn the policy runs, up to +100% (2× upkeep), then eases
			# back off when strict/standard safety is restored.
			var maint_pct := float(effect.get("maint_pct", 0.0))
			if active:
				labour_pct = minf(0.15, labour_pct + 0.005)
				maint_pct = minf(1.0, maint_pct + 0.05)
			else:
				labour_pct = maxf(0.0, labour_pct - 0.0025)
				maint_pct = maxf(0.0, maint_pct - 0.05)
			effect["maint_pct"] = maint_pct
		WORKFORCE_POLICY_LONG_TENURE:
			# Long-serving staff get cheaper over time (to -10%); a periodic awards
			# payout (+10% one turn every 10th) is added in workforce_labour_cost_delta.
			if active:
				labour_pct = maxf(-0.10, labour_pct - 0.001)
			else:
				labour_pct = minf(0.0, labour_pct + 0.0025)
		WORKFORCE_POLICY_STOCK_OPTIONS:
			# Ownership stake lifts output (to +5%) and grows the dividend (to +10pp).
			var div_pct := float(effect.get("dividend_pct", 0.0))
			if active:
				output_pct = minf(0.05, output_pct + 0.001)
				div_pct = minf(0.10, div_pct + 0.0005)
			else:
				output_pct = maxf(0.0, output_pct - 0.001)
				div_pct = maxf(0.0, div_pct - 0.001)
			effect["dividend_pct"] = div_pct
		WORKFORCE_POLICY_PENSIONS_MINIMUM:
			# Cheapest legal cover: the wage bill thins while it runs, and people
			# quietly leave for better shops, dragging output down until cover improves.
			if active:
				labour_pct = maxf(-0.05, labour_pct - 0.001)
				output_pct = maxf(-0.05, output_pct - 0.0005)
			else:
				labour_pct = minf(0.0, labour_pct + 0.0025)
				output_pct = minf(0.0, output_pct + 0.001)
		WORKFORCE_POLICY_PUSH_AUTOMATION:
			# Machines replace hands: labour falls (to −15%) while the extra plant
			# pushes maintenance up (to +10%); both ease back when the push stops.
			var auto_maint := float(effect.get("maint_pct", 0.0))
			if active:
				labour_pct = maxf(-0.15, labour_pct - 0.002)
				auto_maint = minf(0.10, auto_maint + 0.02)
			else:
				labour_pct = minf(0.0, labour_pct + 0.0025)
				auto_maint = maxf(0.0, auto_maint - 0.02)
			effect["maint_pct"] = auto_maint

	effect["output_pct"] = output_pct
	effect["labour_pct"] = labour_pct

func _pension_labour_step(active_turns: int) -> float:
	var third := workforce_policy_game_third_turns()
	if active_turns <= third:
		return 0.001
	if active_turns <= third * 2:
		return 0.0025
	return 0.004

func workforce_output_multiplier(turn_number: int = -1) -> float:
	var turn := int(TurnManager.current_turn) if turn_number < 0 else turn_number
	# Labour-effort pressure/momentum accrued by tick_labour_output_pressure().
	var multiplier := 1.0 + labour_output_pressure_pct / 100.0
	if is_workforce_policy_enabled(WORKFORCE_POLICY_GENEROUS_PENSIONS):
		var pensions: Dictionary = workforce_policy_effects.get(WORKFORCE_POLICY_GENEROUS_PENSIONS, {})
		multiplier *= 1.0 + float(pensions.get("output_pct", 0.0))
	if is_workforce_policy_enabled(WORKFORCE_POLICY_PENSIONS_MINIMUM):
		var min_pensions: Dictionary = workforce_policy_effects.get(WORKFORCE_POLICY_PENSIONS_MINIMUM, {})
		multiplier *= 1.0 + float(min_pensions.get("output_pct", 0.0))
	if is_workforce_policy_enabled(WORKFORCE_POLICY_STOCK_OPTIONS):
		var stock: Dictionary = workforce_policy_effects.get(WORKFORCE_POLICY_STOCK_OPTIONS, {})
		multiplier *= 1.0 + float(stock.get("output_pct", 0.0))
	if is_workforce_policy_enabled(WORKFORCE_POLICY_EXTENDED_ANNUAL_LEAVE) and turn % 10 == 0:
		multiplier *= 0.95
	if is_workforce_policy_enabled(WORKFORCE_POLICY_GENEROUS_PARENTAL_LEAVE):
		var ten_turn_block := int(floor(float(maxi(turn, 1) - 1) / 10.0))
		if ten_turn_block % 2 == 0:
			multiplier *= 0.95
	if is_workforce_policy_enabled(WORKFORCE_POLICY_STRICT_SAFETY):
		multiplier *= 0.90
	if is_workforce_policy_enabled(WORKFORCE_POLICY_LAX_SAFETY):
		multiplier *= 1.05
	if is_workforce_policy_enabled(WORKFORCE_POLICY_ANNUAL_BONUS) and turn % 10 == 0:
		multiplier *= 1.20
	if is_workforce_policy_enabled(WORKFORCE_POLICY_SMALL_BONUS) and turn % 10 == 0:
		multiplier *= 1.10
	if is_workforce_policy_enabled(WORKFORCE_POLICY_ANNUAL_PROFIT_SHARE):
		multiplier *= 1.10
	if is_workforce_policy_enabled(WORKFORCE_POLICY_PROFIT_SHARE_10):
		multiplier *= 1.15
	return multiplier

# Empire-wide maintenance multiplier from workforce policy: every effect's accrued
# maint_pct sums (Lax Safety's neglect ramp to +100%, the automation push to +10%).
# Applied per building in the maintenance_labour phase. 1.0 = no change.
func workforce_maintenance_multiplier() -> float:
	var pct := 0.0
	for effect in workforce_policy_effects.values():
		if effect is Dictionary:
			pct += maxf(0.0, float(effect.get("maint_pct", 0.0)))
	return 1.0 + pct

# Summed workforce-policy labour delta (a fraction, e.g. -0.10 for -10%). Policies
# combine ADDITIVELY here; callers apply this to the 100% base alongside the labour
# slider and research trims rather than compounding it on top of them.
func workforce_labour_cost_delta(turn_number: int = -1) -> float:
	var turn := int(TurnManager.current_turn) if turn_number < 0 else turn_number
	var delta := 0.0
	for effect in workforce_policy_effects.values():
		if effect is Dictionary:
			delta += float(effect.get("labour_pct", 0.0))
	if is_workforce_policy_enabled(WORKFORCE_POLICY_ANNUAL_BONUS):
		delta += 0.05
	if is_workforce_policy_enabled(WORKFORCE_POLICY_SMALL_BONUS):
		delta += 0.025
	# Long Tenure Awards: a payout spike of +10% labour one turn every 10th turn.
	if is_workforce_policy_enabled(WORKFORCE_POLICY_LONG_TENURE) and turn > 0 and turn % 10 == 0:
		delta += 0.10
	return delta

# Accrued Stock Options dividend bonus (0..0.10), added on top of the base dividend
# rate at the payout site; persists (decaying) after the policy is switched off.
func workforce_dividend_bonus() -> float:
	var e = workforce_policy_effects.get(WORKFORCE_POLICY_STOCK_OPTIONS, {})
	return float(e.get("dividend_pct", 0.0)) if e is Dictionary else 0.0

func workforce_labour_cost_multiplier() -> float:
	return maxf(0.0, 1.0 + workforce_labour_cost_delta())

# Project the summed workforce-policy labour delta `turns_ahead` turns forward,
# assuming the currently-enabled policies stay enabled. Runs the same per-turn
# accrual as tick_workforce_policies on a throwaway copy (no live state touched),
# so the Labour panel's 10-turn estimate matches what the sim will actually charge.
func projected_workforce_labour_delta(turns_ahead: int) -> float:
	if turns_ahead <= 0:
		return workforce_labour_cost_delta()
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
	var delta := 0.0
	for effect in effects.values():
		if effect is Dictionary:
			delta += float(effect.get("labour_pct", 0.0))
	if is_workforce_policy_enabled(WORKFORCE_POLICY_ANNUAL_BONUS):
		delta += 0.05
	if is_workforce_policy_enabled(WORKFORCE_POLICY_SMALL_BONUS):
		delta += 0.025
	return delta

# Combined labour multiplier from the slider + workforce policies, applied
# ADDITIVELY to the 100% base (no compounding). Per-building research head-count
# trims add on top of this in Production.labour_cost_factor. Display sites that lack
# a specific building (money projection, per-tier rows) use this global factor.
func labour_policy_factor() -> float:
	return maxf(0.0, 1.0 + (labour_multiplier - 1.0) + workforce_labour_cost_delta())

# ── Advisor seat framework (docs/advisor-system-spec.md §2-6) ──────────────
# Phase 0 CORE: data model + scaling + idempotent modifier reconciler. The
# effects are inert placeholders here (spec §12.1 Phase 0 = "nothing works yet");
# real domain modifiers land in Phase 1. The display roster (_advisor_definitions)
# is merged onto ADVISOR_ROSTER in a later increment.

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
