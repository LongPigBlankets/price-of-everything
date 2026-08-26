extends Node
## The post-tutorial mini missions: integrate the chain you were just taught to run, then find
## a second buyer for what it leaves you holding.
##
## The tutorial ends with the player's furnace switched to a better recipe and its inputs still
## coming off the market, which is the moment "what now?" arrives. Mission 1 answers it by
## walking back up the chain; mission 2 answers the problem mission 1 creates — you now make
## more of an intermediate than the one building can eat.
##
## TWO CHAINS, ONE SHAPE. The tutorial forks. A glass player is left on High Strength
## Glassmaking (r_054), which eats SILICA; an aluminium player on Bauxite Carbochlorination
## (r_232), which eats CHLORINE and BAUXITE as two independent inputs — chlorine comes from the
## Chlor-Alkali process, not from bauxite, so the aluminium mission is two parallel supplies
## rather than the glass mission's two-deep chain. The step wording differs for that reason.
##
## Mission 1 pays the same on both sides, and that is not a coincidence: Window Manufacturing
## (r_056) consumes GLASS AND ALUMINIUM, so +5% windows output really is the end of both.
##
## STEPS ARE STICKY. A step ticks the turn it is true and stays ticked. Production swings with
## prices and storage, and a mission that un-ticked itself because one turn's silica was bought
## rather than made would read as a bug rather than a setback.
##
## GOOD IDS, NOT INTERNAL NAMES. Production keys its turn summary by `good.id` (g_020), never by
## internal_name (silica). Checking the summary with internal names silently never matches — it
## does not error, it just never fires — so everything here resolves through Catalog first.

const MISSION_INTEGRATE := 0
const MISSION_MONETISE := 1

const REWARD_ID_INTEGRATE := "mini_quest_chain_integration"
const REWARD_ID_MONETISE := "mini_quest_surplus_monetised"
const REWARD_PCT := 5.0
const REWARD_GOOD := "windows"
const REWARD_TEXT := "+5% output when producing windows"
const MONETISE_PCT := 15.0
const MONETISE_TURNS := 20

## `made` identifies the chain the player went into. `mid` and `ore` are the two supplies
## mission 1 asks them to own; `mid` doubles as the SURPLUS mission 2 asks them to sell on.
const CHAINS := {
	"glass": {
		"made": "glass",
		"mid": "silica",
		"ore": "sand",
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
		"made": "aluminium",
		"mid": "chlorine",
		"ore": "bauxite_ore",
		"title": "Integrate aluminium and bauxite production",
		"subtitle": "Make your own chlorine",
		# Chlorine and bauxite both feed the smelter directly (r_232), so this is two supplies
		# to one building rather than the glass chain's sand -> silica -> furnace ladder.
		"steps": [
			"Produce your own chlorine",
			"Supply it to your aluminium smelter",
			"Mine your own bauxite",
			"Supply it to the same smelter",
		],
		"hint": "If unsure, check the Goods Graph for Aluminium.",
	},
}

const MONETISE_TITLE := "Monetise the production surplus"
const MONETISE_HINT := "If unsure, check the Goods Graph for %s."

signal quest_changed

## "" until the player has produced something that picks a chain.
var chain := ""
var done: Array = [[false, false, false, false], [false, false, false]]
var granted: Array = [false, false]
## good_id of the product they chose to sell the surplus on as. "" until they pick one.
var monetised_good := ""


func _ready() -> void:
	await get_tree().process_frame
	MatchState.state_reset.connect(_on_state_reset)
	Production.turn_processed.connect(_on_turn_processed)


func _on_state_reset() -> void:
	chain = ""
	done = [[false, false, false, false], [false, false, false]]
	granted = [false, false]
	monetised_good = ""
	quest_changed.emit()


# ── What the top bar asks ────────────────────────────────────────────────────

## Shown only once the tutorial is behind the player: during a tutorial match the coach owns
## their attention, and before they have ever finished one there is no "what now?" to answer.
## A chain must also have picked itself — a player producing neither glass nor aluminium is not
## being asked to integrate one.
func is_available() -> bool:
	if bool(MatchState.ruleset.get("tutorial_enabled", false)):
		return false
	if not PlayerProfile.tutorial_completed:
		return false
	return chain != ""


## Mission 1 until it is done, then mission 2. Both finished leaves mission 2 showing, complete.
func active_mission() -> int:
	return MISSION_MONETISE if _all_done(MISSION_INTEGRATE) else MISSION_INTEGRATE


func spec() -> Dictionary:
	return CHAINS.get(chain, {}) as Dictionary


func title() -> String:
	if active_mission() == MISSION_MONETISE:
		return MONETISE_TITLE
	return str(spec().get("title", ""))


func subtitle() -> String:
	var m := active_mission()
	if is_mission_complete(m):
		return "Complete — %s" % reward_text()
	if m == MISSION_MONETISE:
		return "Find a second buyer for your %s" % _display(_surplus_id())
	return str(spec().get("subtitle", ""))


func steps() -> Array:
	if active_mission() == MISSION_MONETISE:
		return [
			"Figure out what else can use %s" % _display(_surplus_id()),
			"Build a production building to consume it",
			"Sell the new good to the market",
		]
	return spec().get("steps", []) as Array


func step_done(i: int) -> bool:
	var d: Array = done[active_mission()]
	return i < d.size() and bool(d[i])


func reward_text() -> String:
	if active_mission() == MISSION_MONETISE:
		var what := _display(monetised_good) if monetised_good != "" else "the new good"
		return "%d%% increased output of %s for %d turns" % [int(MONETISE_PCT), what, MONETISE_TURNS]
	return REWARD_TEXT


func hint() -> String:
	if active_mission() == MISSION_MONETISE:
		return MONETISE_HINT % _display(_surplus_id())
	return str(spec().get("hint", ""))


func is_mission_complete(m: int) -> bool:
	return chain != "" and _all_done(m)


## Kept for callers that only care whether there is anything left to do.
func is_complete() -> bool:
	return is_mission_complete(MISSION_INTEGRATE) and is_mission_complete(MISSION_MONETISE)


# ── Evaluation ───────────────────────────────────────────────────────────────

func _on_turn_processed(summary: Dictionary) -> void:
	var produced: Dictionary = summary.get("produced", {})
	var consumed: Dictionary = summary.get("consumed", {})
	var sold: Dictionary = summary.get("sold", {})
	if chain == "":
		chain = _pick_chain(produced)
		if chain == "":
			return
	var s := spec()
	if s.is_empty():
		return
	var mid := _good_id(str(s.mid))
	var ore := _good_id(str(s.ore))
	# "Produce your own X" is simply that X came out of one of your buildings this turn.
	# "Supply it to Y" is SELF-SUFFICIENCY rather than a delivery trace: you used the good and
	# made at least as much of it as you used, so none of that consumption leaned on the
	# market. It is the claim a player can verify for themselves in the Goods Graph, and it
	# does not need the transport layer to expose per-shipment provenance.
	_tick(MISSION_INTEGRATE, 0, float(produced.get(mid, 0)) > 0.0)
	_tick(MISSION_INTEGRATE, 1, _self_supplied(produced, consumed, mid))
	_tick(MISSION_INTEGRATE, 2, float(produced.get(ore, 0)) > 0.0)
	_tick(MISSION_INTEGRATE, 3, _self_supplied(produced, consumed, ore))
	if _all_done(MISSION_INTEGRATE) and not granted[MISSION_INTEGRATE]:
		_grant_integrate()

	# Mission 2 only starts counting once mission 1 is done — its whole premise is a surplus
	# that mission 1 created.
	if _all_done(MISSION_INTEGRATE):
		_evaluate_monetise(produced, sold)
	quest_changed.emit()


## Three escalating states: you have PICKED a second use (a building of yours is set to a
## recipe that eats the surplus and makes something else), that building is RUNNING, and its
## output has SOLD.
func _evaluate_monetise(produced: Dictionary, sold: Dictionary) -> void:
	var picked := _new_consumer_output()
	if picked != "":
		monetised_good = picked
	_tick(MISSION_MONETISE, 0, monetised_good != "")
	if monetised_good != "":
		_tick(MISSION_MONETISE, 1, float(produced.get(monetised_good, 0)) > 0.0)
		_tick(MISSION_MONETISE, 2, float(sold.get(monetised_good, 0)) > 0.0)
	if _all_done(MISSION_MONETISE) and not granted[MISSION_MONETISE]:
		_grant_monetise()


## The output good of any building of theirs whose recipe consumes the surplus and makes
## something OTHER than the chain's own product — i.e. the second buyer the mission asks for.
func _new_consumer_output() -> String:
	var surplus := _surplus_id()
	if surplus == "":
		return ""
	var own := _good_id(str(spec().get("made", "")))
	for iid in MatchState.buildings:
		var inst: Dictionary = MatchState.buildings[iid]
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


static func _self_supplied(produced: Dictionary, consumed: Dictionary, good_id: String) -> bool:
	if good_id == "":
		return false
	var used := float(consumed.get(good_id, 0))
	return used > 0.0 and float(produced.get(good_id, 0)) >= used


## Sticky — see the header.
func _tick(mission: int, i: int, met: bool) -> void:
	if met:
		(done[mission] as Array)[i] = true


func _all_done(mission: int) -> bool:
	for d in (done[mission] as Array):
		if not d:
			return false
	return true


## Whichever of the two the player actually makes. On the rare run that works both lines the
## larger output wins — the mission should name the chain they are already invested in.
func _pick_chain(produced: Dictionary) -> String:
	var best := ""
	var best_qty := 0.0
	for key in CHAINS:
		var qty := float(produced.get(_good_id(str(CHAINS[key].made)), 0))
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


func _grant_integrate() -> void:
	granted[MISSION_INTEGRATE] = true
	if Modifiers.has(REWARD_ID_INTEGRATE):
		return
	Modifiers.add({
		"id": REWARD_ID_INTEGRATE,
		"domain": "recipe_output",
		"target_match": {"good_internal": REWARD_GOOD},
		"pct": REWARD_PCT,
		"label": "Integrated supply chain",
		"source": "quest:chain_integration",
	})


## Timed, unlike mission 1's: duration_turns is ModifierState's own convenience and it handles
## the expiry phase arithmetic, so this does not need its own clock.
func _grant_monetise() -> void:
	granted[MISSION_MONETISE] = true
	if monetised_good == "" or Modifiers.has(REWARD_ID_MONETISE):
		return
	Modifiers.add({
		"id": REWARD_ID_MONETISE,
		"domain": "recipe_output",
		"target_match": {"good_internal": Catalog.get_internal_name(monetised_good)},
		"pct": MONETISE_PCT,
		"duration_turns": MONETISE_TURNS,
		"label": "Monetised surplus",
		"source": "quest:surplus_monetised",
	})
