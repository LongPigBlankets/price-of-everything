extends RefCounted
## Strikes, pay rises and accidents (docs/pacing-labour-mining-licensing-spec.md §6, §4.5). Owned by LabourState
## (`LabourState.unrest`), saved with its fields and ticked first thing in PROCESS, right after satisfaction moves.
##
## Strikes are checked every 10th turn T. In the resolution of turn T−3 a workforce below −70 names its strikers,
## a quarter of the company's production and power buildings (half below −90), so the player sees the warning
## from turn T−2. In the resolution of T the named buildings strike if satisfaction is still below −70: their
## output falls 30% for 3 turns (a per-building `recipe_output` mult 0.7 modifier) while their inputs are still
## consumed and their labour costs half. A union agreement or a pay rise for all strikers keeps strikes away.
## Breaking a strike ends it for a turn of wages and a fall in satisfaction; done routinely, the workforce
## remembers it until a Comprehensive Union Agreement is signed.
## Accidents happen only under Minimal safety, at hazardous buildings, and stop a building for 2 turns.

signal changed

const BuildingStatus := preload("res://scripts/building_status.gd")

const CHECK_EVERY := 10
## The warning is drawn this many resolutions before the check turn: in T−3, seen from turn T−2.
const WARNING_LEAD := 3
const STRIKE_BELOW := -70.0
const HEAVY_STRIKE_BELOW := -90.0
const STRIKE_SHARE := 0.25
const HEAVY_STRIKE_SHARE := 0.5
const STRIKE_TURNS := 3
const STRIKE_OUTPUT_MULT := 0.7
## Struck buildings pay this share of their labour cost.
const STRIKE_LABOUR_SHARE := 0.5
const STRIKE_END_SHIFT := 5.0
const PAY_RAISE := 0.20
const PAY_RAISE_TURNS := 10
const STRIKE_FREE_TURNS := 15
const RECORD_CAP := 20
## The Strikes tab's Upcoming count takes strikes starting within this many turns.
const UPCOMING_WITHIN := 5
## Breaking a strike: replacement crews and guards cost this many turns of a building's base wage bill, paid
## this turn, and lower the satisfaction target by 5 a building or 20 for a whole round, for 10 turns.
const BREAK_COST_TURNS := 1.0
const BREAK_SHIFT_ONE := -5.0
const BREAK_SHIFT_ROUND := -20.0
## Two whole rounds broken, or ten buildings broken one at a time, and the workforce remembers for good:
## "Routinely broke strikes", until a Comprehensive Union Agreement is signed.
const ROUTINE_ROUNDS := 2
const ROUTINE_BUILDINGS := 10
const ROUTINE_SATISFACTION := -15.0
const ACCIDENT_CHANCE_START := 0.02
const ACCIDENT_CHANCE_STEP := 0.0025
const ACCIDENT_CHANCE_MAX := 0.06
const ACCIDENT_DOWN_TURNS := 2
const ACCIDENT_SHIFT := -10.0
const ACCIDENT_COMPENSATION_TURNS := 2
## An accident this recent doubles the building's weight in the strike draw.
const ACCIDENT_MEMORY := 10
const BATTERY_BUILDINGS := {"b_028": true, "b_029": true}
## Seeds the labour RNG from the match seed (stable arithmetic, never hash()).
const RNG_SALT := 0x57A41E

## The open warning: {turn: T, buildings: [iid], heavy: bool, light: int}. Empty when none.
var warning: Dictionary = {}
## Buildings on strike: iid -> turns left, counting the current one.
var active: Dictionary = {}
## Past strikes, newest last: [{turn, buildings: [{iid, name}], outcome, lost}]. Capped at RECORD_CAP.
var record: Array = []
## Buildings under a pay rise: iid -> turns left.
var pay_raises: Dictionary = {}
## No warnings or strikes before this turn.
var strike_free_until := 0
## Buildings stopped by an accident: iid -> turns left.
var accident_down: Dictionary = {}
## The turn of each building's last accident.
var accident_turns: Dictionary = {}
## Turns Minimal safety has been on without a break: the accident chance's ramp.
var minimal_safety_turns := 0
## Whole rounds broken, and buildings broken one at a time, since the last Comprehensive signing.
var rounds_broken := 0
var buildings_broken := 0
## "Routinely broke strikes": a standing −15 on the satisfaction target until Comprehensive is signed.
var routinely_broke := false
var _rng := RandomNumberGenerator.new()
var _rng_seeded := false


func reset() -> void:
	warning = {}
	active.clear()
	record.clear()
	pay_raises.clear()
	strike_free_until = 0
	accident_down.clear()
	accident_turns.clear()
	minimal_safety_turns = 0
	rounds_broken = 0
	buildings_broken = 0
	routinely_broke = false
	_rng_seeded = false


func export_fields() -> Dictionary:
	_ensure_rng()
	return {
		"strike_warning": warning.duplicate(true),
		"strike_active": active.duplicate(true),
		"strike_record": record.duplicate(true),
		"strike_pay_raises": pay_raises.duplicate(true),
		"strike_free_until": strike_free_until,
		"accident_down": accident_down.duplicate(true),
		"accident_turns": accident_turns.duplicate(true),
		"accident_minimal_turns": minimal_safety_turns,
		"strike_rounds_broken": rounds_broken,
		"strike_buildings_broken": buildings_broken,
		"strike_routinely_broke": routinely_broke,
		"labour_rng_seed": SaveLoad.int64_out(_rng.seed),
		"labour_rng_state": SaveLoad.int64_out(_rng.state),
	}


## Older saves carry none of this and load quiet.
func import_fields(d: Dictionary) -> void:
	warning = (d.get("strike_warning", {}) as Dictionary).duplicate(true)
	active = _int_values(d.get("strike_active", {}))
	record = (d.get("strike_record", []) as Array).duplicate(true)
	pay_raises = _int_values(d.get("strike_pay_raises", {}))
	strike_free_until = int(d.get("strike_free_until", 0))
	accident_down = _int_values(d.get("accident_down", {}))
	accident_turns = _int_values(d.get("accident_turns", {}))
	minimal_safety_turns = maxi(0, int(d.get("accident_minimal_turns", 0)))
	rounds_broken = maxi(0, int(d.get("strike_rounds_broken", 0)))
	buildings_broken = maxi(0, int(d.get("strike_buildings_broken", 0)))
	routinely_broke = bool(d.get("strike_routinely_broke", false))
	_rng_seeded = d.has("labour_rng_seed")
	if _rng_seeded:
		_rng.seed = SaveLoad.int64_in(d.get("labour_rng_seed"), 0)
		_rng.state = SaveLoad.int64_in(d.get("labour_rng_state"), _rng.state)


static func _int_values(raw: Variant) -> Dictionary:
	var out := {}
	if raw is Dictionary:
		for k in raw:
			out[str(k)] = int(raw[k])
	return out


func _ensure_rng() -> void:
	if _rng_seeded:
		return
	_rng.seed = int(MatchState.match_rng_seed) ^ RNG_SALT
	_rng_seeded = true


# ── The turn ─────────────────────────────────────────────────────────────────────────────────────

## One turn of unrest, in the resolution of `turn`: pay rises, strikes and downtime age, accidents are rolled,
## a check turn's strike starts or is called off, and a coming check's warning is drawn.
func tick(turn: int) -> void:
	_age(pay_raises)
	_age(accident_down)
	for iid in active.keys():
		active[iid] = int(active[iid]) - 1
		if int(active[iid]) <= 0:
			active.erase(iid)
			_strike_over(str(iid))
	_roll_accidents(turn)
	if not warning.is_empty() and int(warning.get("turn", 0)) <= turn:
		_resolve_warning(turn)
	if (turn + WARNING_LEAD) % CHECK_EVERY == 0 and warning.is_empty():
		_draw_warning(turn + WARNING_LEAD)
	changed.emit()


static func _age(timers: Dictionary) -> void:
	for k in timers.keys():
		timers[k] = int(timers[k]) - 1
		if int(timers[k]) <= 0:
			timers.erase(k)


## The production and power buildings strikes count and draw from: the player's, with a recipe, not paused,
## not infrastructure or a battery. Sorted by id so the draw is the same for the same state.
func eligible_buildings() -> Array:
	var out: Array = []
	for b: Dictionary in BuildingState.buildings.values():
		if not BuildingState.is_player_owned(b) or str(b.get("recipe_id", "")) == "":
			continue
		var bid := str(b.get("building_id", ""))
		if BATTERY_BUILDINGS.has(bid) or str(Catalog.get_building(bid).get("category", "production")) == "infrastructure":
			continue
		if BuildingWorks.is_building_paused(str(b.get("instance_id", ""))):
			continue
		out.append(str(b.get("instance_id", "")))
	out.sort()
	return out


## Strikes cannot happen: a union agreement is in force, or a pay rise for all strikers still protects.
func strikes_blocked(turn: int) -> bool:
	return LabourState.union_tier() != LabourState.UNION_NONE or turn < strike_free_until


func strike_size(n: int, heavy: bool) -> int:
	return ceili(float(n) * (HEAVY_STRIKE_SHARE if heavy else STRIKE_SHARE))


func _draw_warning(check_turn: int) -> void:
	if strikes_blocked(check_turn) or LabourState.satisfaction >= STRIKE_BELOW:
		return
	var heavy := LabourState.satisfaction < HEAVY_STRIKE_BELOW
	var all := eligible_buildings()
	var count := strike_size(all.size(), heavy)
	var named := draw(all.filter(func(iid: String) -> bool: return not pay_raises.has(iid)), count, check_turn)
	if named.is_empty():
		return
	warning = {"turn": check_turn, "buildings": named, "heavy": heavy, "light": strike_size(all.size(), false)}
	_bell("strike_warning", "warning", "Strike warning",
		"%s will strike on turn %d unless satisfaction reaches %s. You can settle or break it on the Strikes tab." % [
			_names_text(named), check_turn, LabourState.signed_text(STRIKE_BELOW)])


## `count` buildings from `pool`, weighted: hazardous ×2 while safety is Minimal, an accident in the last 10
## turns ×2. Seeded, without replacement.
func draw(pool: Array, count: int, turn: int) -> Array:
	_ensure_rng()
	var left := pool.duplicate()
	var picked: Array = []
	while picked.size() < count and not left.is_empty():
		var weights: Array = []
		var total := 0.0
		for iid in left:
			var w := strike_weight(str(iid), turn)
			weights.append(w)
			total += w
		var roll := _rng.randf() * total
		var i := 0
		while i < left.size() - 1 and roll >= float(weights[i]):
			roll -= float(weights[i])
			i += 1
		picked.append(left[i])
		left.remove_at(i)
	return picked


func strike_weight(iid: String, turn: int) -> float:
	var w := 1.0
	var bid := str(BuildingState.get_building(iid).get("building_id", ""))
	if LabourState.is_workforce_policy_enabled(LabourState.WORKFORCE_POLICY_LAX_SAFETY) \
			and LabourState.HAZARDOUS_BUILDINGS.has(bid):
		w *= 2.0
	if accident_turns.has(iid) and turn - int(accident_turns[iid]) <= ACCIDENT_MEMORY:
		w *= 2.0
	return w


func _resolve_warning(turn: int) -> void:
	var named: Array = []
	for iid in warning.get("buildings", []):
		var b := BuildingState.get_building(str(iid))
		if not b.is_empty() and BuildingState.is_player_owned(b) and not pay_raises.has(str(iid)):
			named.append(str(iid))
	var s := LabourState.satisfaction
	if strikes_blocked(turn) or s >= STRIKE_BELOW or named.is_empty():
		_add_record(turn, named, "called off", 0.0)
		_bell("strike_called_off", "info", "Strike called off", "%s went back to work." % _names_text(named))
		warning = {}
		return
	if bool(warning.get("heavy", false)) and s >= HEAVY_STRIKE_BELOW:
		named = named.slice(0, int(warning.get("light", named.size())))
	var lost := 0.0
	for iid: String in named:
		active[iid] = STRIKE_TURNS
		Modifiers.add({"id": "strike_%s" % iid, "domain": "recipe_output", "target": "*",
			"target_match": {"instance_id": iid}, "mult": STRIKE_OUTPUT_MULT, "duration_turns": STRIKE_TURNS,
			"source": "strike", "label": "On strike"})
		lost += expected_loss(iid)
	_add_record(turn, named, "struck", lost)
	warning = {}
	_bell("strike_started", "critical", "Strike",
		"%s %s on strike: output down %d%% for %d turns." % [_names_text(named), "is" if named.size() == 1 else "are", output_cut_pct(), STRIKE_TURNS])


func _strike_over(iid: String) -> void:
	Modifiers.remove("strike_%s" % iid)
	var b := BuildingState.get_building(iid)
	if b.is_empty() or not BuildingState.is_player_owned(b):
		return   # sold or demolished while on strike: nobody comes back
	LabourState.add_target_shift("strike_over_%s" % iid, "Strike over", STRIKE_END_SHIFT)
	_bell("strike_over", "info", "Strike over", "%s is back at full output." % _name(iid))


## Ends a strike without its +5: a pay rise bought the workers back.
func _end_strike_bought(iid: String) -> void:
	active.erase(iid)
	Modifiers.remove("strike_%s" % iid)


func is_on_strike(iid: String) -> bool:
	return active.has(iid)


## The share of its labour cost a building pays: half while on strike.
func labour_share(iid: String) -> float:
	return STRIKE_LABOUR_SHARE if active.has(iid) else 1.0


func strike_turns_left(iid: String) -> int:
	return int(active.get(iid, 0))


func is_named(iid: String) -> bool:
	return (warning.get("buildings", []) as Array).has(iid)


## The share of output a strike takes, in whole percent (30).
static func output_cut_pct() -> int:
	return roundi((1.0 - STRIKE_OUTPUT_MULT) * 100.0)


## The next check turn after `turn`.
static func next_check_turn(turn: int) -> int:
	return (turn / CHECK_EVERY + 1) * CHECK_EVERY


## What a building's strike costs: the output it loses a turn at today's prices, for the turns a strike runs.
func expected_loss(iid: String) -> float:
	return output_value_per_turn(iid) * (1.0 - STRIKE_OUTPUT_MULT) * float(STRIKE_TURNS)


## A building's standing output at today's sale prices (power at the grid's export price).
func output_value_per_turn(iid: String) -> float:
	var b := BuildingState.get_building(iid)
	if b.is_empty():
		return 0.0
	var recipe := Catalog.get_recipe(str(b.get("recipe_id", "")))
	if str(recipe.get("output_name", "")) == "power":
		return float(Production._effective_power_output(b, recipe)) * EconomyConfig.GRID_SELL_PRICE
	var value := 0.0
	for output: Dictionary in recipe.get("outputs", []):
		var single := {"outputs": [output], "recipe_id": str(recipe.get("recipe_id", "")),
			"recipe_type": str(recipe.get("recipe_type", ""))}
		value += float(BuildingStatus.effective_output_qty(b, single)) * MarketState.get_sale_price(str(output.get("good_id", "")))
	return value


# ── Pay rises (§6.2) ─────────────────────────────────────────────────────────────────────────────

## What raising pay at `iid` costs over its 10 turns: 20% of its base wage bill a turn.
func pay_raise_cost(iid: String) -> float:
	var b := BuildingState.get_building(iid)
	if b.is_empty():
		return 0.0
	return Production._base_labour_cost(b) * PAY_RAISE * float(PAY_RAISE_TURNS)


## The named buildings whose strike starts within UPCOMING_WITHIN turns of `turn`.
func upcoming(turn: int) -> Array:
	if warning.is_empty() or int(warning.get("turn", 0)) - turn > UPCOMING_WITHIN:
		return []
	return (warning.get("buildings", []) as Array).duplicate()


## The buildings on strike, in id order.
func ongoing() -> Array:
	var out: Array = active.keys()
	out.sort()
	return out


## The buildings a pay rise for all strikers covers: those named or on strike.
func affected_buildings() -> Array:
	var out: Array = (warning.get("buildings", []) as Array).duplicate()
	for iid in active:
		if not out.has(iid):
			out.append(iid)
	return out


## Settle one named or striking building's strike with a pay rise: +20% labour there for 10 turns, its strike ends or it leaves
## the warning. No change to satisfaction.
func raise_pay(iid: String) -> bool:
	if not is_named(iid) and not is_on_strike(iid):
		return false
	pay_raises[iid] = PAY_RAISE_TURNS
	_end_one(iid)
	changed.emit()
	return true


## Ends one building's part in the round: its strike ends without the +5, or it leaves the warning.
func _end_one(iid: String) -> void:
	if is_on_strike(iid):
		_end_strike_bought(iid)
	if is_named(iid):
		var left: Array = (warning.buildings as Array).filter(func(x: String) -> bool: return x != iid)
		if left.is_empty():
			warning = {}
		else:
			warning["buildings"] = left


## Settle every strike with a pay rise at each named or striking building (or those of them in `only`): each +20% for 10 turns, their
## strikes end, they leave the warning, and there are no strikes for 15 turns.
func raise_pay_all(turn: int, only: Array = []) -> bool:
	var all := _round(only)
	if all.is_empty():
		return false
	for iid: String in all:
		pay_raises[iid] = PAY_RAISE_TURNS
		_end_one(iid)
	strike_free_until = turn + STRIKE_FREE_TURNS
	changed.emit()
	return true


# ── Breaking strikes ─────────────────────────────────────────────────────────────────────────────

## What breaking `iid`'s strike costs, paid this turn: a turn of its base wage bill.
func break_cost(iid: String) -> float:
	var b := BuildingState.get_building(iid)
	if b.is_empty():
		return 0.0
	return Production._base_labour_cost(b) * BREAK_COST_TURNS


## Break one named or striking building's strike: it pays break_cost this turn, its workers go back (a named
## one never strikes), and the satisfaction target falls 5 for 10 turns. The tenth building broken this way
## makes it routine.
func break_strike(iid: String, turn: int) -> bool:
	if not is_named(iid) and not is_on_strike(iid):
		return false
	_charge_break(break_cost(iid), turn)
	_end_one(iid)
	LabourState.add_target_shift("strike_broken_%s_%d" % [iid, turn], "Strike broken", BREAK_SHIFT_ONE)
	_add_record(turn, [iid], "broken", 0.0)
	buildings_broken += 1
	if buildings_broken >= ROUTINE_BUILDINGS:
		_make_routine()
	_bell("strike_broken", "warning", "Strike broken", "%s is back at work. Satisfaction %s for %d turns." % [
		_name(iid), LabourState.signed_text(BREAK_SHIFT_ONE), LabourState.EVENT_SHIFT_TURNS])
	changed.emit()
	return true


## Break the whole round: every named and striking building (or those of them in `only`) goes back to work
## at once, each paying break_cost this turn, and the satisfaction target falls 20 for 10 turns. The second round broken makes it
## routine. No protection follows, unlike a pay rise for all.
func break_all(turn: int, only: Array = []) -> bool:
	var all := _round(only)
	if all.is_empty():
		return false
	var cost := 0.0
	for iid: String in all:
		cost += break_cost(iid)
		_end_one(iid)
	_charge_break(cost, turn)
	LabourState.add_target_shift("strikes_broken_%d" % turn, "Strikes broken", BREAK_SHIFT_ROUND)
	_add_record(turn, all, "broken", 0.0)
	rounds_broken += 1
	if rounds_broken >= ROUTINE_ROUNDS:
		_make_routine()
	_bell("strikes_broken", "warning", "Strikes broken", "%s %s back at work. Satisfaction %s for %d turns." % [
		_names_text(all), "is" if all.size() == 1 else "are", LabourState.signed_text(BREAK_SHIFT_ROUND), LabourState.EVENT_SHIFT_TURNS])
	changed.emit()
	return true


## The buildings an action for all acts on: every named and striking one, or those of them in `only`.
func _round(only: Array) -> Array:
	var all := affected_buildings()
	if only.is_empty():
		return all
	return all.filter(func(iid: String) -> bool: return only.has(iid))


## Whether breaking `target` ("all" or a building) now would make strike breaking routine.
func break_makes_routine(target: String) -> bool:
	if routinely_broke:
		return false
	return rounds_broken + 1 >= ROUTINE_ROUNDS if target == "all" else buildings_broken + 1 >= ROUTINE_BUILDINGS


func _charge_break(amount: float, turn: int) -> void:
	if amount > 0.0:
		MatchState.one_off_charges.append({"turn": turn, "amount": snappedf(amount, 0.01), "label": "Strike breaking"})


func _make_routine() -> void:
	if routinely_broke:
		return
	routinely_broke = true
	LabourState.satisfaction_changed.emit()
	_bell("strikes_routinely_broken", "critical", "Routinely broke strikes",
		"The workforce will not forget. Satisfaction %s until a Comprehensive Union Agreement is signed." % LabourState.signed_text(ROUTINE_SATISFACTION))


## A Comprehensive Union Agreement wipes the slate: the standing −15 and the counts toward it.
func clear_strike_breaking() -> void:
	rounds_broken = 0
	buildings_broken = 0
	routinely_broke = false


# ── Accidents (§4.5) ─────────────────────────────────────────────────────────────────────────────

## This turn's accident chance at each hazardous building: 2%, +0.25 points a turn Minimal safety stays on,
## to 6%. 0 without Minimal safety.
func accident_chance() -> float:
	if not LabourState.is_workforce_policy_enabled(LabourState.WORKFORCE_POLICY_LAX_SAFETY):
		return 0.0
	return minf(ACCIDENT_CHANCE_MAX, ACCIDENT_CHANCE_START + ACCIDENT_CHANCE_STEP * float(minimal_safety_turns))


func _roll_accidents(turn: int) -> void:
	if not LabourState.is_workforce_policy_enabled(LabourState.WORKFORCE_POLICY_LAX_SAFETY):
		minimal_safety_turns = 0
		return
	_ensure_rng()
	var chance := accident_chance()
	for iid: String in eligible_buildings():
		var b := BuildingState.get_building(iid)
		if not LabourState.HAZARDOUS_BUILDINGS.has(str(b.get("building_id", ""))) or accident_down.has(iid):
			continue
		if _rng.randf() < chance:
			_accident(iid, b, turn)
	minimal_safety_turns += 1


func _accident(iid: String, b: Dictionary, turn: int) -> void:
	accident_down[iid] = ACCIDENT_DOWN_TURNS
	accident_turns[iid] = turn
	LabourState.add_target_shift("accident_%s_%d" % [iid, turn], "Accident", ACCIDENT_SHIFT)
	var compensation := Production._calculate_labour_cost(b) * float(ACCIDENT_COMPENSATION_TURNS)
	if compensation > 0.0:
		MatchState.one_off_charges.append({"turn": turn, "amount": compensation, "label": "Accident compensation"})
	_bell("accident", "warning", "Accident at %s" % _name(iid),
		"It is down for %d turns. Compensation £%.0f." % [ACCIDENT_DOWN_TURNS, compensation])


## An accident at `iid` from outside the Minimal safety roll (robbed pillars, docs/pacing-labour-mining-licensing-spec.md
## §8.7): the same 2 turns down, compensation and target shift. Nothing for a building already down.
func cause_accident(iid: String, turn: int) -> void:
	var b := BuildingState.get_building(iid)
	if b.is_empty() or accident_down.has(iid):
		return
	_accident(iid, b, turn)
	changed.emit()


func is_down(iid: String) -> bool:
	return accident_down.has(iid)


func down_turns_left(iid: String) -> int:
	return int(accident_down.get(iid, 0))


# ── Words ────────────────────────────────────────────────────────────────────────────────────────

func _add_record(turn: int, iids: Array, outcome: String, lost: float) -> void:
	var names: Array = []
	for iid in iids:
		names.append({"iid": str(iid), "name": _name(str(iid))})
	record.append({"turn": turn, "buildings": names, "outcome": outcome, "lost": snappedf(lost, 0.01)})
	while record.size() > RECORD_CAP:
		record.pop_front()


func _name(iid: String) -> String:
	var b := BuildingState.get_building(iid)
	return preload("res://scripts/building_naming.gd").of(b) if not b.is_empty() else iid


func _names_text(iids: Array) -> String:
	var names := PackedStringArray()
	for iid in iids:
		names.append(_name(str(iid)))
	if names.size() <= 1:
		return names[0] if names.size() == 1 else "Nobody"
	return ", ".join(names.slice(0, names.size() - 1)) + " and " + names[names.size() - 1]


func _bell(kind: String, severity: String, title: String, body: String) -> void:
	EventScheduler.emit_event({"kind": kind, "severity": severity, "title": title, "body": body,
		"source": "labour", "persistent": false, "auto_dismiss_turns": 3})
