extends Node
## Sequential mini missions: a short, concrete goal for the moment a start (or the tutorial)
## stops telling the player what to do.
##
## THREE CHAINS, AND THEY DO NOT SHARE A SHAPE.
##
##   glass / aluminium (post-tutorial)  integrate the chain you were just taught, then find a
##                                      second buyer for the surplus that creates.
##   magnate (the Metal Magnate start)  smelt your own ingots into steel, then get both ores
##                                      onto deposits that never run out.
##
## Glass is a ladder — sand -> silica (r_035) -> furnace (r_054) — so its second supply step
## points at a DIFFERENT building one rung up. Aluminium is two siblings: r_232 takes bauxite
## and chlorine as independent inputs (chlorine is Chlor-Alkali, from salt and water), so both
## its supply steps feed the same smelter. The wording differs because the graph does.
##
## STEPS ARE STICKY. A step ticks the turn it is true and stays ticked. Production swings with
## prices and storage, and a mission that un-ticked itself because one turn's silica was bought
## rather than made would read as a bug rather than a setback.
##
## GOOD IDS, NOT INTERNAL NAMES. Production keys its turn summary by `good.id` (g_020), never by
## internal_name (silica). Checking the summary with internal names silently never matches — it
## does not error, it just never fires — so everything here resolves through Catalog first. The
## same trap applies to modifier `target_match`, whose keys are matched against the APPLY-SITE
## ctx: recipe_output carries `good_internal`, building_power carries `building_id`, and
## transport_cost carries `good_id`. Each reward below uses the key its own domain provides.

## Fixed-length missions. `deposits` is absent on purpose — its length depends on the recipe
## the player's steel plant runs, so it is measured from _deposits_steps instead.
const MISSION_KINDS := {
	"integrate": 4, "monetise": 3, "steel": 2,
}

# ── Chain definitions ────────────────────────────────────────────────────────

const CHAINS := {
	"glass": {
		"made": "glass", "mid": "silica", "ore": "sand",
		"missions": ["integrate", "monetise"],
		"title": "Integrate glass and sand production",
		"subtitle": "Make your own sand",
		"steps": [
			"Produce your own silica",
			"Supply it to your glass furnace",
			"Mine your own sand",
			"Supply it to the silica producing building",
		],
		"hint": "If unsure, check the Goods Graph for Glass.",
	},
	"aluminium": {
		"made": "aluminium", "mid": "chlorine", "ore": "bauxite_ore",
		"missions": ["integrate", "monetise"],
		"title": "Integrate aluminium and bauxite production",
		"subtitle": "Make your own chlorine",
		"steps": [
			"Produce your own chlorine",
			"Supply it to your aluminium smelter",
			"Mine your own bauxite",
			"Supply it to the same smelter",
		],
		"hint": "If unsure, check the Goods Graph for Aluminium.",
	},
	"magnate": {
		"made": "steel",
		"missions": ["steel", "deposits"],
	},
}

## Starts whose chain is known the moment the match loads, so the module can appear on turn 1
## rather than after the first turn resolves. Both demo starts are here — the magnate already
## smelts ingots on turn 1 and the glass merchant already makes glass, so there is nothing to
## wait for. The tutorial fork is NOT here: it records no start_id for which way the player went,
## so its chain is inferred from output in _pick_chain instead.
const START_CHAINS := {
	"metal_magnate": "magnate",
	"glass_merchant": "glass",
}

const REWARD_ID_INTEGRATE := "mini_quest_chain_integration"
const REWARD_ID_MONETISE := "mini_quest_surplus_monetised"
const REWARD_ID_STEEL := "mini_quest_steel_furnace_power"
const REWARD_ID_DEPOSITS := "mini_quest_ore_transport"

const REWARD_PCT := 5.0
const REWARD_GOOD := "windows"
const REWARD_TEXT := "+5% output when producing windows"
const MONETISE_PCT := 15.0
const MONETISE_TURNS := 20
## Every building the furnace-power reward lands on. b_002 is the Furnace and b_008 the Electric
## Arc Furnace, and BOTH make steel — r_003/r_025/r_077 in the furnace, r_076 Electric Arc
## Steelmaking in the EAF. Granting only b_002 was the first cut and it was wrong: an EAF player
## finished the mission and the modifier appeared on a building they may not even own, which is
## indistinguishable from no reward at all (owner, 26 Aug).
const STEEL_BUILDINGS := ["b_002", "b_008"]
const STEEL_POWER_PCT := -10.0
const ORE_TRANSPORT_PCT := -10.0

const MISSION_TEXT := {
	"steel": {
		"title": "Produce Steel",
		"subtitle": "Smelt your own ingots into steel",
		"steps": [
			"Produce your own steel",
			"Supply your iron ingots to the steel furnace",
		],
		"reward": "-10% power in furnaces",
		"hint": "If unsure, check the Goods Graph for Steel.",
	},
	"deposits": {
		"title": "Secure lasting coal and iron deposits",
		"subtitle": "Mine deposits that never run out",
		# Steps are BUILT, not listed — see _deposits_steps. There is no "supply iron to your
		# steel building" step at all: every steel recipe takes iron INGOTS, never ore
		# (r_003 ingots+coal, r_025 ingots+oxygen+limestone, r_076 ingots+hydrogen,
		# r_077 ingots+oxygen+coal), so it has no path through the graph and could never tick.
		# Owner's call, 25 Aug.
		"steps": [],
		"reward": "-10% transport cost for coal and iron",
		# No hint. Surveying is not a thing the demo asks the player to do, so pointing at it
		# was advice for a game they are not playing (owner, 26 Aug). The flyout skips an empty
		# hint rather than rendering a blank line.
		"hint": "",
	},
}

const MONETISE_TITLE := "Monetise the production surplus"

signal quest_changed
## A mission just finished and its reward is live. Carries the finished mission's own text,
## because by the time this fires the module has already moved on to the next one.
signal mission_completed(kind: String, mission_title: String, reward: String)

var chain := ""
var done: Dictionary = {}      # mission kind -> Array[bool]
var granted: Dictionary = {}   # mission kind -> bool
## good_id of the product picked to sell the surplus on as. "" until they pick one.
var monetised_good := ""
## Does the deposits mission include "supply coal to your steel building"? -1 until the mission
## is triggered, then frozen. See _deposits_wants_coal_steel.
var deposits_coal_step := -1


func _ready() -> void:
	await get_tree().process_frame
	MatchState.state_reset.connect(_on_state_reset)
	Production.turn_processed.connect(_on_turn_processed)
	# Why TWO more hooks, not just turn_processed? A start whose chain is known up front should
	# show the module on turn 1, not after the first turn resolves. The ruleset (with its
	# start_id) is only in place once the snapshot is applied, which match_loaded announces — but
	# that can fire a hair before this autoload finishes connecting on a fast boot, so it is not
	# leaned on alone. phase_started(DECIDE) fires at the top of every turn INCLUDING turn 1,
	# well after setup, and is the reliable one. Both only nudge a refresh; is_available() does
	# the actual resolving, lazily, so it cannot matter which nudge lands first or whether one is
	# missed.
	SaveLoad.match_loaded.connect(func() -> void: quest_changed.emit())
	TurnManager.phase_started.connect(_on_phase_started)


func _on_phase_started(phase: int) -> void:
	if phase == TurnManager.Phase.DECIDE:
		quest_changed.emit()


func _on_state_reset() -> void:
	chain = ""
	done = {}
	granted = {}
	monetised_good = ""
	deposits_coal_step = -1
	quest_changed.emit()


# ── What the top bar asks ────────────────────────────────────────────────────

## SHOWN BY DEFAULT. The missions are hidden in exactly two situations, and both are about the
## tutorial rather than about the player:
##
##   the tutorial is RUNNING      the coach owns the screen; nothing else competes with it.
##   they SKIPPED it early        a skip before the second-to-last step leaves them without the
##                                setup the missions assume, so offering one would point at a
##                                chain they never built. Skipping later, or finishing, keeps
##                                them: _complete_tutorial clears tutorial_enabled, so the
##                                missions appear in that same match.
##
## It deliberately does NOT check PlayerProfile.tutorial_completed. That was the first cut and it
## was wrong: the owner's own profile reads tutorial_completed=false after four finished games,
## because the flag is only set by pressing End Tutorial, not by playing. Anyone who skipped the
## tutorial, or finished it before the flag existed, would never see a mission again.
func is_available() -> bool:
	if Tutorial.active:
		return false
	# A skip leaves tutorial rules on (only End Tutorial clears them), which is how a bailed-out
	# run is told apart from a normal match — where tutorial_enabled was never set at all.
	if bool(MatchState.ruleset.get("tutorial_enabled", false)) and not Tutorial.setup_reached:
		return false
	# Resolve the chain lazily and cache it. For a START_CHAINS start this needs no production,
	# so the module can answer "available" on turn 1 the first time anything asks — no dependence
	# on which setup signal fired when. The tutorial fork returns "" here (no start_id, nothing
	# produced yet) and is filled in later by _on_turn_processed.
	if chain == "":
		chain = _pick_chain({})
	return chain != ""


func spec() -> Dictionary:
	return CHAINS.get(chain, {}) as Dictionary


func missions() -> Array:
	return spec().get("missions", []) as Array


## The first unfinished mission, or the last one when they are all done.
func active_mission() -> String:
	var list := missions()
	for kind in list:
		if not _all_done(str(kind)):
			return str(kind)
	return str(list[list.size() - 1]) if not list.is_empty() else ""


## The five text accessors below default to the ACTIVE mission — which is what the module and
## the flyout want — but take an explicit kind, because the announcement needs to describe the
## mission that just finished, and by then the active one has already moved on.
func title(kind := "") -> String:
	if kind == "":
		kind = active_mission()
	if kind == "monetise":
		return MONETISE_TITLE
	if MISSION_TEXT.has(kind):
		return str(MISSION_TEXT[kind].title)
	return str(spec().get("title", ""))


func subtitle(kind := "") -> String:
	if kind == "":
		kind = active_mission()
	if _all_done(kind):
		return "Complete — %s" % reward_text(kind)
	if kind == "monetise":
		return "Find a second buyer for your %s" % _display(_surplus_id())
	if MISSION_TEXT.has(kind):
		return str(MISSION_TEXT[kind].subtitle)
	return str(spec().get("subtitle", ""))


func steps(kind := "") -> Array:
	if kind == "":
		kind = active_mission()
	if kind == "monetise":
		return [
			"Figure out what else can use %s" % _display(_surplus_id()),
			"Build a production building to consume it",
			"Sell the new good to the market",
		]
	if kind == "deposits":
		return _deposits_steps()
	if MISSION_TEXT.has(kind):
		return MISSION_TEXT[kind].steps as Array
	return spec().get("steps", []) as Array


func step_done(i: int, kind := "") -> bool:
	var d := _slots(kind if kind != "" else active_mission())
	return i < d.size() and bool(d[i])


func reward_text(kind := "") -> String:
	if kind == "":
		kind = active_mission()
	if kind == "monetise":
		var what := _display(monetised_good) if monetised_good != "" else "the new good"
		return "%d%% increased output of %s for %d turns" % [int(MONETISE_PCT), what, MONETISE_TURNS]
	if MISSION_TEXT.has(kind):
		return str(MISSION_TEXT[kind].reward)
	return REWARD_TEXT


func hint(kind := "") -> String:
	if kind == "":
		kind = active_mission()
	if kind == "monetise":
		return "If unsure, check the Goods Graph for %s." % _display(_surplus_id())
	if MISSION_TEXT.has(kind):
		return str(MISSION_TEXT[kind].hint)
	return str(spec().get("hint", ""))


func is_mission_complete(kind: String) -> bool:
	return chain != "" and _all_done(kind)


func is_complete() -> bool:
	for kind in missions():
		if not _all_done(str(kind)):
			return false
	return chain != ""


# ── Evaluation ───────────────────────────────────────────────────────────────

func _on_turn_processed(summary: Dictionary) -> void:
	var produced: Dictionary = summary.get("produced", {})
	var consumed: Dictionary = summary.get("consumed", {})
	var sold: Dictionary = summary.get("sold", {})
	if chain == "":
		chain = _pick_chain(produced)
		if chain == "":
			return
	for kind in missions():
		var k := str(kind)
		# Missions run in order: each one's premise is the previous one's result, so a later
		# mission does not start counting until its predecessor is finished.
		if k != str(missions()[0]) and not _all_done(_previous(k)):
			continue
		match k:
			"integrate": _eval_integrate(produced, consumed)
			"monetise": _eval_monetise(produced, sold)
			"steel": _eval_steel(produced, summary)
			"deposits": _eval_deposits(summary)
		if _all_done(k) and not bool(granted.get(k, false)):
			_grant(k)
			_announce(k)
	quest_changed.emit()


func _eval_integrate(produced: Dictionary, consumed: Dictionary) -> void:
	var mid := _good_id(str(spec().get("mid", "")))
	var ore := _good_id(str(spec().get("ore", "")))
	# "Produce your own X" is simply that X came out of one of your buildings this turn.
	# "Supply it to Y" is SELF-SUFFICIENCY rather than a delivery trace: you used the good and
	# made at least as much of it as you used, so none of that consumption leaned on the
	# market. (The magnate missions below CAN trace delivery, because a mine declares where it
	# ships; a furnace consuming silica does not say where the silica came from.)
	_tick("integrate", 0, float(produced.get(mid, 0)) > 0.0)
	_tick("integrate", 1, _self_supplied(produced, consumed, mid))
	_tick("integrate", 2, float(produced.get(ore, 0)) > 0.0)
	_tick("integrate", 3, _self_supplied(produced, consumed, ore))


## Three escalating states: a second use has been PICKED (a building of theirs is set to a
## recipe that eats the surplus and makes something else), it is RUNNING, and its output SOLD.
func _eval_monetise(produced: Dictionary, sold: Dictionary) -> void:
	var picked := _new_consumer_output()
	if picked != "":
		monetised_good = picked
	_tick("monetise", 0, monetised_good != "")
	if monetised_good != "":
		_tick("monetise", 1, float(produced.get(monetised_good, 0)) > 0.0)
		_tick("monetise", 2, float(sold.get(monetised_good, 0)) > 0.0)


func _eval_steel(produced: Dictionary, summary: Dictionary) -> void:
	var steel := _good_id("steel")
	var ingots := _good_id("iron_ingots")
	_tick("steel", 0, float(produced.get(steel, 0)) > 0.0)
	# Delivery AND use, not self-sufficiency: an ingots building of theirs routes its ingots to
	# a tile where a steel plant of theirs stands that actually consumes ingots, and ingots were
	# consumed this turn. Per-building consumption is not recorded anywhere, so the empire-wide
	# figure is the closest honest second half.
	_tick("steel", 1, _supplied(ingots, ingots, steel, summary))


## Coal and iron each: a mine standing on an inexhaustible deposit, then that mine's output
## routed to the buildings that need it. "That mine" is exact here — a producer declares its
## destination tile, so this is a real delivery check rather than a balance of totals.
## The coal-to-steel step only exists if their steel plant actually BURNS coal. r_003
## Steelmaking and r_077 HIsarna do; Basic Oxygen (oxygen + limestone), Electric Arc
## (hydrogen) and Scrap Recycling do not — asking an EAF player to route coal into it would be
## a step they could never complete.
##
## FROZEN AT TRIGGER. Decided the first time the mission is evaluated, which is the turn
## mission 1 finishes, and never re-read: a player who retools mid-mission should not watch the
## list they are working through change shape underneath them.
func _deposits_wants_coal_steel() -> bool:
	if deposits_coal_step < 0:
		deposits_coal_step = 1 if _steel_recipe_needs_coal() else 0
	return deposits_coal_step == 1


func _steel_recipe_needs_coal() -> bool:
	var coal := _good_id("coal")
	for iid in _producers_of(_good_id("steel")):
		var recipe: Dictionary = Catalog.get_recipe(str((MatchState.buildings[iid] as Dictionary).get("recipe_id", "")))
		for entry in (recipe.get("inputs", []) as Array):
			if str((entry as Dictionary).get("good_id", "")) == coal:
				return true
	return false


func _deposits_steps() -> Array:
	var out: Array = [
		"Run a mine on an infinite coal deposit",
		"Supply coal from that mine to your ingots building",
	]
	if _deposits_wants_coal_steel():
		out.append("Supply coal from that mine to your steel building")
	out.append("Run a mine on an infinite iron deposit")
	out.append("Supply iron from that mine to your ingots building")
	return out


func _eval_deposits(summary: Dictionary) -> void:
	var coal := _good_id("coal")
	var iron := _good_id("iron_ore")
	var ingots := _good_id("iron_ingots")
	var steel := _good_id("steel")
	var coal_mines := _mines_on_infinite(coal, "coal")
	var iron_mines := _mines_on_infinite(iron, "iron_ore")
	# Built in the SAME branch order as _deposits_steps, so a dropped step cannot leave the
	# labels and the checks pointing at different things.
	# `coal_mines` is already the player's, and already stood on an inexhaustible deposit, so
	# _supplied_from restricts the same test to exactly those mines.
	var conds: Array = [
		not coal_mines.is_empty(),
		_supplied_from(coal_mines, coal, ingots, summary),
	]
	if _deposits_wants_coal_steel():
		conds.append(_supplied_from(coal_mines, coal, steel, summary))
	conds.append(not iron_mines.is_empty())
	conds.append(_supplied_from(iron_mines, iron, ingots, summary))
	for i in conds.size():
		_tick("deposits", i, bool(conds[i]))


# ── Building queries ─────────────────────────────────────────────────────────

## Instance ids of the PLAYER'S buildings whose recipe's primary output is `good_id`. The
## ownership filter is not decoration: MatchState.buildings holds NPC-owned buildings in the
## same dictionary, so without it a rival's mine or furnace could tick the player's mission.
func _producers_of(good_id: String) -> Array:
	var out: Array = []
	if good_id == "":
		return out
	for iid in MatchState.buildings:
		var inst: Dictionary = MatchState.buildings[iid]
		if not MatchState.is_player_owned(inst):
			continue
		var recipe: Dictionary = Catalog.get_recipe(str(inst.get("recipe_id", "")))
		if not recipe.is_empty() and str(recipe.get("output_good_id", "")) == good_id:
			out.append(str(iid))
	return out


## {tile_id: true} for tiles where a building of the player's makes `produces` AND its recipe
## actually EATS `eats`.
##
## Delivering to a tile is not the same as being used there. A building consumes its inputs from
## the tile it stands on (production._consume_inputs -> Stockpile.consume(tile_id, ...)), so the
## destination has to host a consumer of the good, not merely a building that happens to be the
## right kind. Without the `eats` half, routing coal at an Electric Arc steel plant — which
## burns none — would tick "supply coal to your steel building".
func _tiles_consuming(produces: String, eats: String) -> Dictionary:
	var out: Dictionary = {}
	if eats == "":
		return out
	for iid in _producers_of(produces):
		var inst: Dictionary = MatchState.buildings[iid]
		var recipe: Dictionary = Catalog.get_recipe(str(inst.get("recipe_id", "")))
		var takes := false
		for entry in (recipe.get("inputs", []) as Array):
			if str((entry as Dictionary).get("good_id", "")) == eats:
				takes = true
				break
		var tid := str(inst.get("tile_id", ""))
		if takes and tid != "":
			out[tid] = true
	return out


## Producers of `good_id` that stand on an inexhaustible deposit of `token`.
func _mines_on_infinite(good_id: String, token: String) -> Array:
	var out: Array = []
	for iid in _producers_of(good_id):
		var tid := str((MatchState.buildings[iid] as Dictionary).get("tile_id", ""))
		if tid != "" and MatchState.has_infinite_deposit(tid, token):
			out.append(iid)
	return out


## _supplied, but from a named set of producers — the mines already filtered to "the player's,
## on an inexhaustible deposit", so the mission's "that mine" is exact.
func _supplied_from(instances: Array, ship_good: String, to_good: String, summary: Dictionary) -> bool:
	var destinations := _tiles_consuming(to_good, ship_good)
	if destinations.is_empty():
		return false
	var supplied: Dictionary = summary.get("tile_supplied", {})
	var consumed: Dictionary = summary.get("tile_consumed", {})
	for iid in instances:
		var tile := str(MatchState.get_output_stockpile_destination(str(iid), ship_good))
		if tile == "" or not destinations.has(tile):
			continue
		if float((supplied.get(tile, {}) as Dictionary).get(ship_good, 0)) <= 0.0:
			continue
		if float((consumed.get(tile, {}) as Dictionary).get(ship_good, 0)) > 0.0:
			return true
	return false


## THE WHOLE SUPPLY TEST, in one place.
##
## Four things have to be true, and none of them is implied by the others:
##   1. the producer is the PLAYER'S (MatchState.buildings holds NPC buildings too),
##   2. it ROUTES the good to a tile where a building of theirs making `to_good` actually eats
##      that good — delivering to an Electric Arc plant that burns no coal is not supply,
##   3. the good ARRIVED there from their own production this turn (summary.tile_supplied
##      counts only own output, so a sack bought off the market does not qualify), and
##   4. that tile CONSUMED it (summary.tile_consumed). A building consumes from the tile it
##      stands on, so tile-scoped use is as close to per-building as the sim records.
##
## 3 and 4 are what make it supply rather than intent: a route with nothing moving down it, or
## goods piling up unused, both fail.
func _supplied(from_good: String, ship_good: String, to_good: String, summary: Dictionary) -> bool:
	return _supplied_from(_producers_of(from_good), ship_good, to_good, summary)


## The output good of any building of theirs whose recipe consumes the surplus and makes
## something OTHER than the chain's own product — the second buyer the mission asks for.
func _new_consumer_output() -> String:
	var surplus := _surplus_id()
	if surplus == "":
		return ""
	var own := _good_id(str(spec().get("made", "")))
	for iid in MatchState.buildings:
		var inst: Dictionary = MatchState.buildings[iid]
		if not MatchState.is_player_owned(inst):
			continue
		var recipe: Dictionary = Catalog.get_recipe(str(inst.get("recipe_id", "")))
		if recipe.is_empty():
			continue
		var out_id := str(recipe.get("output_good_id", ""))
		if out_id == "" or out_id == own:
			continue
		for entry in (recipe.get("inputs", []) as Array):
			if str((entry as Dictionary).get("good_id", "")) == surplus:
				return out_id
	return ""


# ── Plumbing ─────────────────────────────────────────────────────────────────

static func _self_supplied(produced: Dictionary, consumed: Dictionary, good_id: String) -> bool:
	if good_id == "":
		return false
	var used := float(consumed.get(good_id, 0))
	return used > 0.0 and float(produced.get(good_id, 0)) >= used


func _slots(kind: String) -> Array:
	if not done.has(kind):
		var n := _deposits_steps().size() if kind == "deposits" else int(MISSION_KINDS.get(kind, 0))
		var a: Array = []
		for _i in n:
			a.append(false)
		done[kind] = a
	return done[kind] as Array


## Sticky — see the header.
func _tick(kind: String, i: int, met: bool) -> void:
	if met:
		var a := _slots(kind)
		if i < a.size():
			a[i] = true


func _all_done(kind: String) -> bool:
	if kind == "":
		return false
	var a := _slots(kind)
	if a.is_empty():
		return false
	for d in a:
		if not d:
			return false
	return true


func _previous(kind: String) -> String:
	var list := missions()
	var i := list.find(kind)
	return str(list[i - 1]) if i > 0 else ""


## A named start decides the chain outright; the tutorial fork, which records nothing in the
## ruleset, is inferred from whichever of glass/aluminium the player makes more of. The start
## check comes first and needs no production, which is why a START_CHAINS start resolves the
## instant the match loads rather than after a turn.
func _pick_chain(produced: Dictionary) -> String:
	var start := str(MatchState.ruleset.get("start_id", ""))
	if START_CHAINS.has(start):
		return str(START_CHAINS[start])
	var best := ""
	var best_qty := 0.0
	for key in CHAINS:
		var made := str((CHAINS[key] as Dictionary).get("made", ""))
		if key == "magnate" or made == "":
			continue
		var qty := float(produced.get(_good_id(made), 0))
		if qty > best_qty:
			best_qty = qty
			best = str(key)
	return best


func _surplus_id() -> String:
	return _good_id(str(spec().get("mid", "")))


static func _good_id(internal_name: String) -> String:
	if internal_name == "":
		return ""
	return str(Catalog.get_good_by_internal_name(internal_name).get("id", ""))


static func _display(good_id: String) -> String:
	return Catalog.get_display_name(good_id) if good_id != "" else ""


# ── Rewards ──────────────────────────────────────────────────────────────────

func _grant(kind: String) -> void:
	granted[kind] = true
	match kind:
		"integrate":
			_add(REWARD_ID_INTEGRATE, {
				"domain": "recipe_output", "target_match": {"good_internal": REWARD_GOOD},
				"pct": REWARD_PCT, "label": "Integrated supply chain",
				"source": "quest:chain_integration"})
		"monetise":
			if monetised_good == "":
				return
			_add(REWARD_ID_MONETISE, {
				"domain": "recipe_output",
				"target_match": {"good_internal": Catalog.get_internal_name(monetised_good)},
				"pct": MONETISE_PCT, "duration_turns": MONETISE_TURNS,
				"label": "Monetised surplus", "source": "quest:surplus_monetised"})
		"steel":
			# building_power's apply-site ctx carries `building_id`, so that is the key to match
			# on — and one modifier per steel building, since target_match takes a single id.
			for bid in STEEL_BUILDINGS:
				_add("%s_%s" % [REWARD_ID_STEEL, str(bid)], {
					"domain": "building_power", "target_match": {"building_id": str(bid)},
					"pct": STEEL_POWER_PCT, "label": "Steelworks heat recovery",
					"source": "quest:steel"})
		"deposits":
			# transport_cost's ctx carries `good_id`, not `good_internal` — one entry per ore.
			for token in ["coal", "iron_ore"]:
				_add("%s_%s" % [REWARD_ID_DEPOSITS, token], {
					"domain": "transport_cost", "target_match": {"good_id": _good_id(token)},
					"pct": ORE_TRANSPORT_PCT, "label": "Secured ore deposits",
					"source": "quest:deposits"})


## Nothing used to mark the moment a mission landed. The module quietly retitled itself to the
## next one and the reward appeared as a line in a panel the player had no reason to open, so a
## finished mission and an unfinished one looked the same (owner, 26 Aug). Two channels, because
## they answer different questions: the toast says WHAT happened, the signal lets the top bar
## pulse the module so the player's eye goes to WHERE it happened.
func _announce(kind: String) -> void:
	var mission := title(kind)
	var reward := reward_text(kind)
	mission_completed.emit(kind, mission, reward)
	MatchState.request_toast("Mission complete: %s\nReward: %s" % [mission, reward], "success")


## The modifier ids one mission's reward creates. Neither of the magnate rewards is a single id
## — the steel one is per building and the deposits one per ore — so callers that want to check
## a reward really landed ask here rather than guessing the id.
func reward_modifier_ids(kind: String) -> Array:
	match kind:
		"integrate":
			return [REWARD_ID_INTEGRATE]
		"monetise":
			return [REWARD_ID_MONETISE]
		"steel":
			var out: Array = []
			for bid in STEEL_BUILDINGS:
				out.append("%s_%s" % [REWARD_ID_STEEL, str(bid)])
			return out
		"deposits":
			return ["%s_coal" % REWARD_ID_DEPOSITS, "%s_iron_ore" % REWARD_ID_DEPOSITS]
	return []


func _add(id: String, fields: Dictionary) -> void:
	if Modifiers.has(id):
		return
	var m := fields.duplicate(true)
	m["id"] = id
	Modifiers.add(m)
