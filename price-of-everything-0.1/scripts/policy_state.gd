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

# Blocking "Understood" story notices, reserved so they present on `present_turn`'s
# DECIDE (reservations fire in the PREVIOUS turn's NARRATIVE). Re-armed on every
# seed/load (DecisionState reservations don't persist); `until_turn` stops arming once
# the policy itself is in force.
const NOTICES: Array = [
	{"def": "carbon_tax_notice", "present_turn": 90, "until_turn": 101},
	{"def": "green_subsidy_notice", "present_turn": 100, "until_turn": 105},
	{"def": "green_subsidy_end_notice", "present_turn": 180, "until_turn": 191},
]

# The levy ramps in (owner: "ramps up from turn 91 to turn 101"): the per-unit charge
# scales linearly from 1/11 of P1 at turn 91 to full P1 at turn 101, then follows the
# phase table (P2/P3).
const CO2_RAMP_FIRST_TURN := 91
const CO2_P1_TURN := 101

# The election that sets the whole arc in motion (news item, dismissible).
const ELECTION_NEWS_TURN := 84
# Government Affairs insider tip: if a maxed-Influencing (3/3) officer holds the seat on
# any turn in this window, they leak the coming carbon tax as a critical (dismissible)
# update. No qualifying officer → no update. The window closes before the official
# notice at turn 90 makes the rumour redundant.
const INSIDER_TIP_FIRST_TURN := 86
const INSIDER_TIP_LAST_TURN := 89
const INSIDER_TIP_SEAT := "government_affairs"
const INSIDER_TIP_MIN_INF := 3

# Green subsidy window (owner ruling): full rate from t105 through t180, then a linear
# wind-down of 10% per turn across 181..190 (t181 pays 90%, t190 pays 10%), ended
# completely at t191.
const GREEN_SUBSIDY_FULL_LAST_TURN := 180
const GREEN_SUBSIDY_WIND_DOWN_PER_TURN := 0.10
const GREEN_SUBSIDY_END_TURN := 191

var _seeded: bool = false
var _insider_tip_fired: bool = false

func _ready() -> void:
	MatchState.state_reset.connect(_on_state_reset)
	TurnManager.turn_resolution_completed.connect(_on_turn_resolution_completed)
	# A brand-new session (no save loaded, no reset yet) still needs the schedule:
	# seed after the autoload settles unless a load beat us to it.
	call_deferred("_seed_if_needed")

func _on_turn_resolution_completed() -> void:
	_maybe_fire_insider_tip()
	_enforce_new_prohibitions()

# --- Live levels (pure functions of the turn) ---------------------------------------

## Highest CO2-tax phase in force at `turn` (0 = the levy is not yet in force).
func co2_tax_level(turn: int) -> int:
	var lvl := 0
	for e in Schedule.SCHEDULE:
		if str(e.policy) == "co2_tax" and turn >= int(e.effective_turn):
			lvl = maxi(lvl, int(e.level))
	return lvl

## The wind-down factor: 1.0 through t180, −10% per turn across 181..190, 0.0 from 191.
func green_subsidy_wind_down(turn: int) -> float:
	if turn <= GREEN_SUBSIDY_FULL_LAST_TURN:
		return 1.0
	return maxf(0.0, 1.0 - GREEN_SUBSIDY_WIND_DOWN_PER_TURN * float(turn - GREEN_SUBSIDY_FULL_LAST_TURN))

## £ per green MW generated at `turn` (0.0 before the subsidy window opens; ramps
## down 10%/turn across 181..190; gone at 191).
func green_subsidy_rate(turn: int) -> float:
	var wind := green_subsidy_wind_down(turn)
	if wind <= 0.0:
		return 0.0
	var lvl := 0
	for e in Schedule.SCHEDULE:
		if str(e.policy) == "green_subsidy" and turn >= int(e.effective_turn):
			lvl = maxi(lvl, int(e.level))
	if lvl <= 0 or lvl >= EconomyConfig.GREEN_SUBSIDY_PHASE_SCALE.size():
		lvl = mini(lvl, EconomyConfig.GREEN_SUBSIDY_PHASE_SCALE.size() - 1)
	return EconomyConfig.GREEN_SUBSIDY_RATE * float(EconomyConfig.GREEN_SUBSIDY_PHASE_SCALE[lvl]) * wind

## The scale factor for the carbon charge at `turn`: 0 before the ramp, a linear
## ramp-in across turns 91..100 ((turn-90)/11 of P1), then the phase table from 101.
func co2_tax_scale(turn: int) -> float:
	if turn < CO2_RAMP_FIRST_TURN:
		return 0.0
	if turn < CO2_P1_TURN:
		return float(turn - (CO2_RAMP_FIRST_TURN - 1)) / float(CO2_P1_TURN - (CO2_RAMP_FIRST_TURN - 1))
	var lvl := clampi(co2_tax_level(turn), 0, EconomyConfig.CO2_TAX_PHASE_SCALE.size() - 1)
	return float(EconomyConfig.CO2_TAX_PHASE_SCALE[lvl])

## --- PROHIBITIONS -------------------------------------------------------------
## A ban is a pure function of (turn, schedule) plus one cheat override, so nothing
## about it needs to survive a save beyond that override — the levels themselves are
## always re-derived. Two kinds:
##   "produce" — recipes whose OUTPUT is the good stop running and cannot be selected
##   "import"  — the good cannot be bought by ANY route (queue_buy is the single primitive)
## `-1` means the cheat is not engaged; otherwise bans are live from that turn onward.
var _ban_override_turn: int = -1

## Goods travel through the codebase as catalog IDs ("g_001") in some places and as
## internal names ("coal") in others; the schedule is authored in internal names
## because a human writes it. Normalise so callers can pass either.
func _internal_name_of(good_ref: String) -> String:
	var by_id: Dictionary = Catalog.get_good(good_ref)
	var n: String = str(by_id.get("internal_name", ""))
	return n if n != "" else good_ref

## Every good banned for `kind` at `turn`, as a set of INTERNAL NAMES. Cheap enough to
## call per recipe/purchase: the schedule is a handful of rows.
func _banned_set(kind: String, turn: int) -> Dictionary:
	var out: Dictionary = {}
	if _ban_override_turn >= 0 and turn >= _ban_override_turn:
		out["coal"] = true
	for e in Schedule.SCHEDULE:
		if turn < int(e.effective_turn):
			continue
		var bans: Dictionary = e.get("bans", {})
		for gid in bans.get(kind, []):
			out[str(gid)] = true
	return out

## True when producing `good_id` is prohibited at `turn`. Accepts a catalog ID or an
## internal name.
func produce_banned(good_id: String, turn: int) -> bool:
	return _banned_set("produce", turn).has(_internal_name_of(good_id))

## True when buying `good_id` is prohibited at `turn` — checked by MatchState.queue_buy,
## which every purchase route (automated top-up, recurring, construction, upgrade,
## manual) funnels through.
func import_banned(good_id: String, turn: int) -> bool:
	return _banned_set("import", turn).has(_internal_name_of(good_id))

## True when any prohibition is live at `turn` (drives UI copy).
func any_ban_active(turn: int) -> bool:
	return not (_banned_set("produce", turn).is_empty() and _banned_set("import", turn).is_empty())

## What a prohibition costs the player the turn it lands, and the cancellation it forces.
##
## Called at the end of the resolution on the turn a ban first becomes live (the
## "newly banned" set is `bans(turn) - bans(turn-1)`, so it is self-limiting and needs
## no extra saved state — the cheat, which sets its override to the current turn, trips
## the same edge). Standing recurring buy orders for a prohibited good are CANCELLED,
## because they would otherwise re-issue an illegal purchase every turn. Shipments
## already paid for and in transit are deliberately left to land: the player has
## already been charged, and seizing them would be a second, unannounced penalty.
func _enforce_new_prohibitions() -> void:
	var turn: int = int(TurnManager.current_turn)
	var newly_produce: Dictionary = _newly_banned("produce", turn)
	var newly_import: Dictionary = _newly_banned("import", turn)
	if newly_produce.is_empty() and newly_import.is_empty():
		return

	# Buildings whose current recipe is now illegal (they halt in _can_run_recipe).
	var halted: int = 0
	for iid in MatchState.buildings:
		var b: Dictionary = MatchState.buildings[iid]
		var recipe: Dictionary = Catalog.get_recipe(str(b.get("recipe_id", "")))
		if recipe.is_empty():
			continue
		if Catalog.is_recipe_prohibited(recipe):
			halted += 1

	# Standing market orders that can no longer be honoured.
	var cancelled: int = 0
	var kept: Array = []
	for order in MatchState.recurring_buys:
		var gid: String = str((order as Dictionary).get("good", ""))
		if newly_import.has(_internal_name_of(gid)):
			cancelled += 1
		else:
			kept.append(order)
	if cancelled > 0:
		MatchState.recurring_buys = kept

	var goods: Array = newly_produce.keys()
	for g in newly_import:
		if not goods.has(g):
			goods.append(g)
	goods.sort()   # deterministic wording (rule #3)
	var named: String = ", ".join(goods)
	EventScheduler.emit_event({
		"id": "policy:prohibition_impact:%d" % turn,
		"kind": "policy_enacted",
		"severity": "critical",
		"title": "Prohibition in force — %s" % named,
		"body": "%d %s stopped and %d standing market %s cancelled. Shipments already paid for will still arrive; nothing new can be ordered. Switch those buildings to another recipe or demolish them — they keep costing maintenance and labour while idle." % [
			halted, "building" if halted == 1 else "buildings",
			cancelled, "order" if cancelled == 1 else "orders"],
		"source": "policy",
		"deeplink": {"panel": "money"},
		"persistent": true,
		"auto_dismiss_turns": 6,
	})

## Goods newly prohibited for `kind` on `turn` (live now, not live last turn).
func _newly_banned(kind: String, turn: int) -> Dictionary:
	var now: Dictionary = _banned_set(kind, turn)
	if now.is_empty():
		return {}
	var before: Dictionary = _banned_set(kind, turn - 1)
	var out: Dictionary = {}
	for g in now:
		if not before.has(g):
			out[g] = true
	return out

## Cheat hook: engage the coal prohibition from the current turn, or lift it.
func cheat_set_coal_ban(on: bool, turn: int) -> void:
	_ban_override_turn = turn if on else -1

func coal_ban_override_turn() -> int:
	return _ban_override_turn

## How carbon-intensive the NATIONAL GRID is at `turn`, as a fraction of a fully fossil grid.
##
## 1.0 through turn 70, then falling linearly to GRID_CARBON_FLOOR on the last playable turn.
## The world decarbonises whether or not the player does, so importing power gets cleaner over
## the game while a coal plant stays exactly as dirty as coal — which is the pressure the curve
## exists to create. Scales the carbon priced into imported power, not the levy on any fuel the
## player burns themselves.
func grid_carbon_intensity(turn: int) -> float:
	if turn <= EconomyConfig.GRID_CARBON_FULL_TURN:
		return 1.0
	var span := float(TurnManager.MAX_TURNS - EconomyConfig.GRID_CARBON_FULL_TURN)
	if span <= 0.0:
		return EconomyConfig.GRID_CARBON_FLOOR
	var t := clampf(float(turn - EconomyConfig.GRID_CARBON_FULL_TURN) / span, 0.0, 1.0)
	return lerpf(1.0, EconomyConfig.GRID_CARBON_FLOOR, t)

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
	_insider_tip_fired = false
	_ban_override_turn = -1
	call_deferred("_seed_if_needed")

func _seed_if_needed() -> void:
	# Notice reservations live in DecisionState state that is NOT saved, so they are
	# re-armed on every seed AND every load (guarded against double-fires inside).
	_arm_notices()
	if _seeded:
		return
	_seeded = true
	# The election that opens the arc: a dismissible news item READ on turn 84.
	# Scheduled events fire during their turn's NARRATIVE (mid-resolution), surfacing on
	# the NEXT turn's DECIDE — so fire it one turn early to land on 84 itself.
	EventScheduler.schedule(ELECTION_NEWS_TURN - 1, {
		"id": "policy:election_markets_party",
		"kind": "policy_enacted",
		"severity": "warning",
		"title": "Markets Party wins the election",
		"body": "After a long rule by the State Party, the Markets Party has won the election — and is expected to make sweeping changes.",
		"forewarn_turns": 0,
		"source": "policy",
		"persistent": true,
		"auto_dismiss_turns": 6,
	})
	# The subsidy's end news at t191 (the wind-down's zero turn). The advance warning is
	# the blocking green_subsidy_end_notice at t180, so no passive forewarn here.
	EventScheduler.schedule(GREEN_SUBSIDY_END_TURN, {
		"id": "policy:green_subsidy_end",
		"kind": "policy_enacted",
		"severity": "warning",
		"title": "Green Energy Subsidy — programme ended",
		"body": "The green subsidy has ended. I hope we didn't get too attached to the gravy train. Of course, publicly we will complain how it's affecting the country's competitiveness but I reckon we'll be fine. Right?",
		"forewarn_turns": 0,
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

# Reserve the blocking "Understood" notices (see NOTICES). Guarded so a notice the
# player already answered (history) or has pending never re-fires; late loads inside
# the window still get theirs on the next turn.
func _arm_notices() -> void:
	var turn := int(TurnManager.current_turn)
	for n in NOTICES:
		var def_id := str(n.def)
		if turn >= int(n.until_turn):
			continue
		if _notice_seen(def_id):
			continue
		DecisionState.reserve(maxi(int(n.present_turn) - 1, turn), def_id)

func _notice_seen(def_id: String) -> bool:
	for rec in DecisionState.history():
		if str(rec.get("def_id", "")) == def_id:
			return true
	for d in DecisionState.pending_queue:
		if str(d.get("def_id", "")) == def_id:
			return true
	return false

# Government Affairs insider leak: a 3/3-Influencing officer seated during turns 86..89
# tips the player off that a coal/oil consumption tax is coming (critical, dismissible
# news). Fires at most once per match; no qualifying officer → nothing.
func _maybe_fire_insider_tip() -> void:
	if _insider_tip_fired:
		return
	var turn := int(TurnManager.current_turn)
	if turn < INSIDER_TIP_FIRST_TURN or turn > INSIDER_TIP_LAST_TURN:
		return
	var aid := get_insider_tip_officer()
	if aid == "":
		return
	_insider_tip_fired = true
	var officer_name := str(MatchState.get_advisor(aid).get("name", "Your Government Affairs officer"))
	EventScheduler.emit_event({
		"kind": "advisor_tip",
		"severity": "critical",
		"title": "%s: a carbon tax is coming" % officer_name,
		"body": "%s thinks a tax on consuming coal and oil is coming — or at least that's what they've heard from their contacts in government. Nothing is official yet, but it may be wise to start preparing." % officer_name,
		"source": "policy",
		"persistent": true,
		"auto_dismiss_turns": 5,
	})

## The seated Government Affairs advisor id, if their Influencing is maxed (3/3); else "".
## Raw discipline stats live on ADVISOR_ROSTER (the display dicts don't carry them).
func get_insider_tip_officer() -> String:
	var aid := MatchState.get_advisor_in_seat(INSIDER_TIP_SEAT)
	if aid == "":
		return ""
	if int(MatchState._roster_entry(aid).get("inf", 0)) < INSIDER_TIP_MIN_INF:
		return ""
	return aid

# --- Save / load (additive key; tolerant reader, no version bump) ---------------------

func export_state() -> Dictionary:
	return {
		"seeded": _seeded,
		"insider_tip_fired": _insider_tip_fired,
		"ban_override_turn": _ban_override_turn,
	}

func import_state(d: Dictionary) -> void:
	# Old saves (no "policy" key) arrive as {} → seeded=false → the schedule seeds on
	# this load; beats already past their turn simply won't re-fire (their turn is gone)
	# while the LEVELS are pure functions of the turn and are always correct.
	_seeded = bool(d.get("seeded", false))
	_insider_tip_fired = bool(d.get("insider_tip_fired", false))
	# Old saves have no key → -1 → no cheat prohibition, schedule bans still apply.
	_ban_override_turn = int(d.get("ban_override_turn", -1))
	call_deferred("_seed_if_needed")
