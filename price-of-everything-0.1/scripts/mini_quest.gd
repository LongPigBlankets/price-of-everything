extends Node
const MiddlemanService := preload("res://scripts/middleman_service.gd")
## Modular mini missions: a short, concrete goal for the moment a start (or the tutorial)
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

# Missions are exposed as two independent trees.  The older chain API below remains in place
# for save compatibility and reward evaluation; these definitions are the presentation and
# progression contract used by the mission panel.  A start tree can therefore run beside the
# shared logistics tree without forcing every start into the same linear sequence.
const GENERIC_TREE_ID := "logistics"
const TREE_DEFINITIONS := {
	"logistics": {
		"title": "Logistics",
		"subtitle": "Open the routes that let your business trade on its own terms.",
		"nodes": [
			{"id": "middleman_contracts", "parent": "", "title": "Open Logistics Contracts",
				"subtitle": "Ship at least 300 units of three goods through the Logistics Intermediary.",
				"reward": "Unlock tile-stockpile routes", "research": "Open Logistics Contracts"},
			{"id": "tile_stockpile", "parent": "middleman_contracts", "title": "Use a tile stockpile",
				"subtitle": "Move one input or output to a tile stockpile and complete a production cycle.",
				"reward": "+5% output for 20 turns", "requires": ["middleman_contracts"]},
			{"id": "global_license", "parent": "", "title": "Secure the Import/Export License",
				"subtitle": "Make £75 profit a turn for 3 turns in a row, then accept the government’s £150 license decision.",
				"reward": "Unlock global-market buying and selling", "research": "Government Import/Export License"},
			{"id": "global_surplus", "parent": "tile_stockpile", "parents": ["tile_stockpile", "global_license"],
				"title": "Sell surplus to the global market",
				"subtitle": "Route a tile surplus to the global market and complete a sale.",
				"reward": "+2% sale price for 10 turns", "requires": ["tile_stockpile", "global_license"]},
		],
	},
	"magnate": {
		"title": "Metal Magnate",
		"subtitle": "Build a reliable domestic metals chain.",
		"nodes": [
			{"id": "steel", "parent": "", "title": "Produce Steel",
				"subtitle": "Smelt your own ingots into steel.", "kind": "steel"},
			{"id": "deposits", "parent": "steel", "title": "Secure lasting deposits",
				"subtitle": "Put coal and iron on deposits that never run out.", "kind": "deposits"},
		],
	},
}

const GENERIC_SALE_REWARD_ID := "mini_quest_global_surplus_sale_price"
const GENERIC_SALE_REWARD_PCT := 2.0
const GENERIC_SALE_REWARD_TURNS := 10

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
var generic_done: Dictionary = {}
var generic_granted: Dictionary = {}
## good_id of the product picked to sell the surplus on as. "" until they pick one.
var monetised_good := ""
## Does the deposits mission include "supply coal to your steel building"? -1 until the mission
## is triggered, then frozen. See _deposits_wants_coal_steel.
var deposits_coal_step := -1
## The themed boards (data/mission_boards.json): finished stations, rewards granted, the branch the player
## chose at each choice point (choice id -> station id), and the board whose current station the top bar shows
## ("" = the start's own missions, as before boards).
var board_done: Dictionary = {}
var board_granted: Dictionary = {}
var board_choices: Dictionary = {}
var followed_board := ""
## What each counted station had already reached when it opened (station id -> value), and the running totals
## the counted verbs read: units sold, buildings and infrastructure the player built, buildings opened.
var board_baseline: Dictionary = {}
var units_sold_total := 0
var buildings_built := 0
var infra_built := 0
var buildings_opened := 0


func _ready() -> void:
	await get_tree().process_frame
	MatchState.state_reset.connect(_on_state_reset)
	Production.turn_processed.connect(_on_turn_processed)
	Construction.construction_completed.connect(_on_construction_completed)
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
	generic_done = {}
	generic_granted = {}
	monetised_good = ""
	deposits_coal_step = -1
	board_done = {}
	board_granted = {}
	board_choices = {}
	followed_board = ""
	board_baseline = {}
	units_sold_total = 0
	buildings_built = 0
	infra_built = 0
	buildings_opened = 0
	quest_changed.emit()


## Mission progress is match state, not profile state.  Older saves simply omit this block and
## start with a clean tree; the definition itself remains code-owned so renamed nodes cannot
## inject arbitrary rewards from a save file.
func export_fields() -> Dictionary:
	return {
		"chain": chain,
		"done": done.duplicate(true),
		"granted": granted.duplicate(true),
		"generic_done": generic_done.duplicate(true),
		"generic_granted": generic_granted.duplicate(true),
		"monetised_good": monetised_good,
		"deposits_coal_step": deposits_coal_step,
		"board_done": board_done.duplicate(true),
		"board_granted": board_granted.duplicate(true),
		"board_choices": board_choices.duplicate(true),
		"followed_board": followed_board,
		"board_baseline": board_baseline.duplicate(true),
		"units_sold_total": units_sold_total,
		"buildings_built": buildings_built,
		"infra_built": infra_built,
		"buildings_opened": buildings_opened,
	}


func import_fields(fields: Dictionary) -> void:
	chain = str(fields.get("chain", ""))
	done = (fields.get("done", {}) as Dictionary).duplicate(true)
	granted = (fields.get("granted", {}) as Dictionary).duplicate(true)
	generic_done = (fields.get("generic_done", {}) as Dictionary).duplicate(true)
	generic_granted = (fields.get("generic_granted", {}) as Dictionary).duplicate(true)
	monetised_good = str(fields.get("monetised_good", ""))
	deposits_coal_step = int(fields.get("deposits_coal_step", -1))
	board_done = (fields.get("board_done", {}) as Dictionary).duplicate(true)
	board_granted = (fields.get("board_granted", {}) as Dictionary).duplicate(true)
	board_choices = (fields.get("board_choices", {}) as Dictionary).duplicate(true)
	followed_board = str(fields.get("followed_board", ""))
	board_baseline = (fields.get("board_baseline", {}) as Dictionary).duplicate(true)
	units_sold_total = int(fields.get("units_sold_total", 0))
	buildings_built = int(fields.get("buildings_built", 0))
	infra_built = int(fields.get("infra_built", 0))
	buildings_opened = int(fields.get("buildings_opened", 0))
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
	# The generic branch is part of every campaign. It remains visible while its unlocks are
	# locked, so a normal start never loses the mission affordance before its first shipment.
	return true


## Presentation model for the modular mission panel.  Every node carries a derived state:
## "complete", "active", or "locked".  The returned dictionaries are copies so the panel can
## annotate/layout them without mutating mission state.
func mission_trees() -> Array:
	if not is_available():
		return []
	var out: Array = []
	# Show the generic branch first on every campaign, including as a locked branch for starts
	# that have not opted into the intermediary ruleset yet. This keeps the shared progression
	# visible and genuinely parallel to any start-specific branch.
	out.append(_tree_view(GENERIC_TREE_ID))
	if chain == "magnate":
		out.append(_tree_view("magnate"))
	elif chain == "glass":
		out.append(_tree_view("glass"))
	elif chain == "aluminium":
		out.append(_tree_view("aluminium"))
	return out


func _has_named_start() -> bool:
	return _effective_start_id() != ""


func _effective_start_id() -> String:
	var start_id := str(MatchState.ruleset.get("start_id", "")).strip_edges()
	if start_id != "":
		return start_id
	# Directly authored starts predate the New Game override and only carry scenario_name.
	# Treat that field as the same stable start identity for mission selection.
	return str(MatchState.scenario_name).strip_edges()


func tree_definition(tree_id: String) -> Dictionary:
	return (TREE_DEFINITIONS.get(tree_id, {}) as Dictionary).duplicate(true)


func _tree_view(tree_id: String) -> Dictionary:
	var definition := tree_definition(tree_id)
	if definition.is_empty() and CHAINS.has(tree_id):
		definition = {"id": tree_id, "title": str((CHAINS[tree_id] as Dictionary).get("title", tree_id.capitalize())),
			"subtitle": str((CHAINS[tree_id] as Dictionary).get("subtitle", "")), "nodes": []}
		var previous := ""
		for raw_kind: Variant in (CHAINS[tree_id] as Dictionary).get("missions", []) as Array:
			var kind := str(raw_kind)
			definition.nodes.append({"id": kind, "parent": previous, "title": title(kind), "subtitle": subtitle(kind), "reward": reward_text(kind), "kind": kind})
			previous = kind
	var nodes: Array = []
	for raw: Variant in definition.get("nodes", []) as Array:
		var node: Dictionary = (raw as Dictionary).duplicate(true)
		node["state"] = _tree_node_state(tree_id, node)
		node["depth"] = _tree_node_depth(tree_id, str(node.get("id", "")))
		if str(node.get("kind", "")) != "":
			node["steps"] = steps(str(node.kind))
			node["step_done"] = _step_values(str(node.kind))
		nodes.append(node)
	definition["id"] = tree_id
	definition["nodes"] = nodes
	return definition


func _tree_node_depth(tree_id: String, node_id: String) -> int:
	var definition := TREE_DEFINITIONS.get(tree_id, {}) as Dictionary
	var depth := 0
	var parent := ""
	for raw: Variant in definition.get("nodes", []) as Array:
		var node := raw as Dictionary
		if str(node.get("id", "")) == node_id:
			parent = str(node.get("parent", ""))
			break
	while parent != "" and depth < 8:
		depth += 1
		var current_parent := parent
		parent = ""
		for raw: Variant in definition.get("nodes", []) as Array:
			var node := raw as Dictionary
			if str(node.get("id", "")) == current_parent:
				parent = str(node.get("parent", ""))
				break
	return depth


func _tree_node_state(tree_id: String, node: Dictionary) -> String:
	var node_id := str(node.get("id", ""))
	if tree_id == GENERIC_TREE_ID:
		match node_id:
			"middleman_contracts":
				return "complete" if ResearchState.open_logistics_contracts_available() else ("active" if str(MatchState.ruleset.get("logistics_model", "")) == "middleman_v1" else "locked")
			"tile_stockpile":
				if _has_tile_stockpile_route(): return "complete"
				return "active" if ResearchState.open_logistics_contracts_available() else "locked"
			"global_license":
				return "complete" if ResearchState.global_trade_license_available() else ("active" if ResearchState.global_trade_license_unlocked() else "locked")
			"global_surplus":
				if bool(generic_done.get("global_surplus", false)): return "complete"
				return "active" if ResearchState.global_trade_license_available() and _has_tile_stockpile_route() else "locked"
	if tree_id == "magnate":
		var kind := str(node.get("kind", node_id))
		if _all_done(kind): return "complete"
		var definition := TREE_DEFINITIONS.get(tree_id, {}) as Dictionary
		var parent := str(node.get("parent", ""))
		if parent != "":
			for raw: Variant in definition.get("nodes", []) as Array:
				if str((raw as Dictionary).get("id", "")) == parent and not _all_done(str((raw as Dictionary).get("kind", parent))):
					return "locked"
		return "active"
	# Existing non-magnate start chains still render as a separate branch. Their old mission
	# rows remain the authoritative state; this fallback keeps the migration incremental.
	var kind_fallback := str(node.get("kind", node_id))
	return "complete" if _all_done(kind_fallback) else "active"


func _step_values(kind: String) -> Array:
	var values: Array = []
	var slots := _slots(kind)
	for value: Variant in slots:
		values.append(bool(value))
	return values


func _has_tile_stockpile_route() -> bool:
	for iid: Variant in BuildingState.buildings:
		var id := str(iid)
		if not BuildingState.is_player_owned(BuildingState.buildings[iid] as Dictionary):
			continue
		var recipe := Catalog.get_recipe(str((BuildingState.buildings[iid] as Dictionary).get("recipe_id", "")))
		for input: Variant in recipe.get("inputs", []) as Array:
			var gid := str((input as Dictionary).get("good_id", ""))
			if gid != "" and MiddlemanService.enabled(id) and MiddlemanService.mode_for(id, "input", gid) == "managed": return true
		for output: Variant in recipe.get("outputs", []) as Array:
			var gid := str((output as Dictionary).get("good_id", ""))
			if gid != "" and MatchState.get_output_stockpile_destination(id, gid) != "": return true
	return false


func _has_market_surplus_route() -> bool:
	for tile: Variant in MatchState.get_sell_surplus_tiles():
		if MatchState.get_sell_surplus_destination(str(tile)) == "market":
			return true
	return false


func spec() -> Dictionary:
	return CHAINS.get(chain, {}) as Dictionary


func missions() -> Array:
	return spec().get("missions", []) as Array


## The first unfinished mission, or the last one when they are all done.
func active_mission() -> String:
	if has_match_boards():
		var board := effective_followed_board()
		if board != "":
			return board_current_station(board)
		# Every board finished: rest on the last station of the last board.
		var last: Array = (match_boards().back() as Dictionary).get("nodes", []) as Array
		return str((last.back() as Dictionary).get("id", "")) if not last.is_empty() else ""
	var list := missions()
	for kind in list:
		if not _all_done(str(kind)):
			return str(kind)
	if not list.is_empty():
		return str(list[list.size() - 1])
	var trees := mission_trees()
	if not trees.is_empty():
		for node: Variant in (trees[0] as Dictionary).get("nodes", []) as Array:
			if str((node as Dictionary).get("state", "locked")) != "complete":
				return str((node as Dictionary).get("id", ""))
	return ""


## The five text accessors below default to the ACTIVE mission — which is what the module and
## the flyout want — but take an explicit kind, because the announcement needs to describe the
## mission that just finished, and by then the active one has already moved on.
func title(kind := "") -> String:
	if kind == "":
		kind = active_mission()
	var station := _board_node(kind)
	if not station.is_empty():
		return str(station.get("title", ""))
	if kind in ["middleman_contracts", "tile_stockpile", "global_license", "global_surplus"]:
		return str(_generic_node(kind).get("title", ""))
	if kind == "monetise":
		return MONETISE_TITLE
	if MISSION_TEXT.has(kind):
		return str(MISSION_TEXT[kind].title)
	return str(spec().get("title", ""))


func subtitle(kind := "") -> String:
	if kind == "":
		kind = active_mission()
	var station := _board_node(kind)
	if not station.is_empty():
		return station_condition_text(station)
	if kind in ["middleman_contracts", "tile_stockpile", "global_license", "global_surplus"]:
		return str(_generic_node(kind).get("subtitle", ""))
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
	if kind in ["middleman_contracts", "tile_stockpile", "global_license", "global_surplus"]:
		return [subtitle(kind)]
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


## The mission's count for the top bar, as Vector2i(have, need), or Vector2i.ZERO when the mission asks
## for one thing only. A research mission counts its condition; a mission of several steps counts steps.
func progress(kind := "") -> Vector2i:
	if kind == "":
		kind = active_mission()
	var station := _board_node(kind)
	if not station.is_empty():
		return _station_progress(station)
	if kind in ["middleman_contracts", "tile_stockpile", "global_license", "global_surplus"]:
		var d := ResearchState.get_unlock_def(str(_generic_node(kind).get("research", "")))
		if d.is_empty() or ResearchState.is_unlocked(str(d.get("title", ""))):
			return Vector2i.ZERO
		var need := int(d.get("qty", 0))
		var count := maxi(1, str(d.get("unit", "")).to_int())
		match str(d.get("action", "")):
			"Ship Through Logistics Intermediary":
				return ResearchState.intermediary_shipping_progress(need, count)
			"Profit":
				return Vector2i(mini(ResearchState.profit_streak(float(need)), count), count) if count > 1 else Vector2i.ZERO
		return Vector2i.ZERO
	var list := steps(kind)
	if list.size() < 2:
		return Vector2i.ZERO
	var done := 0
	for i in list.size():
		if step_done(i, kind):
			done += 1
	return Vector2i(done, list.size())


func step_done(i: int, kind := "") -> bool:
	var d := _slots(kind if kind != "" else active_mission())
	return i < d.size() and bool(d[i])


func reward_text(kind := "") -> String:
	if kind == "":
		kind = active_mission()
	var station := _board_node(kind)
	if not station.is_empty():
		return str((station.get("reward", {}) as Dictionary).get("text", ""))
	if kind in ["middleman_contracts", "tile_stockpile", "global_license", "global_surplus"]:
		return str(_generic_node(kind).get("reward", ""))
	if kind == "monetise":
		var what := _display(monetised_good) if monetised_good != "" else "the new good"
		return "%d%% increased output of %s for %d turns" % [int(MONETISE_PCT), what, MONETISE_TURNS]
	if MISSION_TEXT.has(kind):
		return str(MISSION_TEXT[kind].reward)
	return REWARD_TEXT


func hint(kind := "") -> String:
	if kind == "":
		kind = active_mission()
	if kind in ["middleman_contracts", "tile_stockpile", "global_license", "global_surplus"]:
		return "Follow the Logistics tree to unlock the next route."
	if kind == "monetise":
		return "If unsure, check the Goods Graph for %s." % _display(_surplus_id())
	if MISSION_TEXT.has(kind):
		return str(MISSION_TEXT[kind].hint)
	return str(spec().get("hint", ""))


func _generic_node(node_id: String) -> Dictionary:
	for raw: Variant in (TREE_DEFINITIONS[GENERIC_TREE_ID] as Dictionary).get("nodes", []) as Array:
		var node := raw as Dictionary
		if str(node.get("id", "")) == node_id:
			return node
	return {}


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
	if has_match_boards():
		# A start with its own boards runs on them alone: the legacy chain and the shared Logistics
		# missions would grant their rewards a second time under other names.
		_count_turn(summary)
		_eval_boards(summary)
		quest_changed.emit()
		return
	_eval_generic(summary)
	if chain == "":
		chain = _pick_chain(produced)
		if chain == "":
			quest_changed.emit()
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


func _eval_generic(summary: Dictionary) -> void:
	if not is_available() and str(MatchState.ruleset.get("logistics_model", "")) != "middleman_v1":
		return
	if ResearchState.open_logistics_contracts_available():
		generic_done["middleman_contracts"] = true
	if _has_tile_stockpile_route():
		generic_done["tile_stockpile"] = true
	if ResearchState.global_trade_license_available():
		generic_done["global_license"] = true
	var sold: Dictionary = summary.get("sold", {})
	var had_sale := false
	for value: Variant in sold.values():
		if value is Dictionary and int((value as Dictionary).get("qty", 0)) > 0:
			had_sale = true
		elif value is int or value is float:
			had_sale = had_sale or float(value) > 0.0
	if bool(generic_done.get("tile_stockpile", false)) and bool(generic_done.get("global_license", false)) \
		and _has_market_surplus_route() and had_sale:
		generic_done["global_surplus"] = true
	for node_id: String in ["middleman_contracts", "tile_stockpile", "global_license", "global_surplus"]:
		if bool(generic_done.get(node_id, false)) and not bool(generic_granted.get(node_id, false)):
			generic_granted[node_id] = true
			_grant_generic(node_id)
			_announce_generic(node_id)


func _grant_generic(node_id: String) -> void:
	if node_id == "global_surplus":
		_add(GENERIC_SALE_REWARD_ID, {
			"domain": "market_price", "target": "*", "pct": GENERIC_SALE_REWARD_PCT,
			"duration_turns": GENERIC_SALE_REWARD_TURNS, "label": "Global surplus sale",
			"source": "quest:global_surplus"})


func _announce_generic(node_id: String) -> void:
	var node := _generic_node(node_id)
	var mission_title := str(node.get("title", node_id))
	var reward := str(node.get("reward", ""))
	mission_completed.emit(node_id, mission_title, reward)
	MatchState.request_toast("Mission complete: %s\nReward: %s" % [mission_title, reward], "success")


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
		var recipe: Dictionary = Catalog.get_recipe(str((BuildingState.buildings[iid] as Dictionary).get("recipe_id", "")))
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
	for iid in BuildingState.buildings:
		var inst: Dictionary = BuildingState.buildings[iid]
		if not BuildingState.is_player_owned(inst):
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
		var inst: Dictionary = BuildingState.buildings[iid]
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
		var tid := str((BuildingState.buildings[iid] as Dictionary).get("tile_id", ""))
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
	for iid in BuildingState.buildings:
		var inst: Dictionary = BuildingState.buildings[iid]
		if not BuildingState.is_player_owned(inst):
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
	var start := _effective_start_id()
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
	MatchState.request_toast(("Mission complete: %s\nReward: %s" % [mission, reward]) if reward != "" else "Mission complete: %s" % mission, "success")


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



# ── Mission boards ───────────────────────────────────────────────────────────
# The missions panel shows one board per tab. A start with boards in data/mission_boards.json (Metal Magnate:
# its Tutorial and its own board) shows those; any other start shows its legacy missions as boards. A board is a
# small graph of stations: each waits on all its parents, and stations that share a `choice` are alternatives
# the player picks between by throwing the points lever (choose()); the others close for good, with every
# station after them. A station that counts something counts from the turn it opened (board_baseline).

const BOARDS_PATH := "res://data/mission_boards.json"
## Where the legacy missions stand on their boards: [row, lane].
const LEGACY_LAYOUT := {
	"middleman_contracts": [0, 0], "tile_stockpile": [1, 0], "global_license": [0, 1], "global_surplus": [2, 0],
	"steel": [0, 0], "deposits": [1, 0], "integrate": [0, 0], "monetise": [1, 0],
}
const BOARD_REWARD_PREFIX := "mission_board_"
## Building types that count as infrastructure for "Infrastructure" (the port is a building, not track).
const INFRA_BUILDINGS := ["b_005", "b_006", "b_017", "b_018", "b_019"]
## Verbs measured from the turn their station opened: the value then is kept in board_baseline.
const COUNTED_VERBS := ["Units Sold", "Build Any", "Infrastructure", "Research Count", "Build Consumers", "Produce Tier", "Open Building"]

var _boards_cache: Array = []


## Every board definition in the file, read once.
func board_definitions() -> Array:
	if _boards_cache.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(BOARDS_PATH))
		if parsed is Dictionary:
			_boards_cache = ((parsed as Dictionary).get("boards", []) as Array).duplicate(true)
	return _boards_cache


## The boards this match plays: enabled ones whose `starts` name the match's start (or that name none).
func match_boards() -> Array:
	var start := _effective_start_id()
	var out: Array = []
	for raw: Variant in board_definitions():
		var def := raw as Dictionary
		if not bool(def.get("enabled", true)):
			continue
		var starts: Array = def.get("starts", []) as Array
		if not starts.is_empty() and not starts.has(start):
			continue
		out.append(def)
	return out


func has_match_boards() -> bool:
	return not match_boards().is_empty()


func _board_def(board_id: String) -> Dictionary:
	for raw: Variant in board_definitions():
		if str((raw as Dictionary).get("id", "")) == board_id:
			return raw as Dictionary
	return {}


func _board_node(node_id: String) -> Dictionary:
	if node_id == "":
		return {}
	for raw: Variant in board_definitions():
		for node: Variant in (raw as Dictionary).get("nodes", []) as Array:
			if str((node as Dictionary).get("id", "")) == node_id:
				return node as Dictionary
	return {}


## The boards for the panel's tabs. Each node carries col (its row, top to bottom), lane (its side), parents,
## choice, state and progress, so the panel only draws. States: complete, active, choice (its choice is still
## to make), locked, closed (a branch not taken).
func mission_boards() -> Array:
	if not is_available():
		return []
	var out: Array = []
	if not has_match_boards():
		var trees := mission_trees()
		trees.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("id", "")) != GENERIC_TREE_ID and str(b.get("id", "")) == GENERIC_TREE_ID)
		for tree: Variant in trees:
			out.append(_legacy_board(tree as Dictionary))
		return out
	for raw: Variant in match_boards():
		var def := raw as Dictionary
		var board := {"id": str(def.get("id", "")), "title": str(def.get("title", "")), "subtitle": str(def.get("subtitle", "")),
			"themed": true, "nodes": []}
		for node: Variant in def.get("nodes", []) as Array:
			var n := (node as Dictionary).duplicate(true)
			n["state"] = board_node_state(str(n.get("id", "")))
			n["subtitle"] = station_condition_text(n)
			n["reward"] = str((n.get("reward", {}) as Dictionary).get("text", ""))
			n["progress"] = progress(str(n.get("id", "")))
			(board.nodes as Array).append(n)
		out.append(board)
	return out


func _legacy_board(tree: Dictionary) -> Dictionary:
	var board := {"id": str(tree.get("id", "")), "title": str(tree.get("title", "")), "subtitle": str(tree.get("subtitle", "")),
		"themed": false, "nodes": []}
	for raw: Variant in tree.get("nodes", []) as Array:
		var node := (raw as Dictionary).duplicate(true)
		var id := str(node.get("id", ""))
		var at: Array = LEGACY_LAYOUT.get(id, [0, 0]) as Array
		var parents: Array = (node.get("parents", []) as Array).duplicate()
		if parents.is_empty() and str(node.get("parent", "")) != "":
			parents = [str(node.parent)]
		node["col"] = int(at[0])
		node["lane"] = int(at[1])
		node["parents"] = parents
		if str(node.get("reward", "")) == "":
			node["reward"] = reward_text(str(node.get("kind", id)))
		node["progress"] = progress(str(node.get("kind", id)))
		(board.nodes as Array).append(node)
	return board


## A board station's state. See mission_boards().
func board_node_state(node_id: String) -> String:
	var node := _board_node(node_id)
	if node.is_empty():
		return "locked"
	if bool(board_done.get(node_id, false)):
		return "complete"
	if _station_closed(node, 0):
		return "closed"
	for parent: Variant in node.get("parents", []) as Array:
		if not bool(board_done.get(str(parent), false)):
			return "locked"
	var group := str(node.get("choice", ""))
	if group != "" and not board_choices.has(group):
		return "choice"
	return "active"


## True when this station, or one before it, lies on a branch the player did not choose.
func _station_closed(node: Dictionary, depth: int) -> bool:
	var group := str(node.get("choice", ""))
	if group != "" and board_choices.has(group) and str(board_choices[group]) != str(node.get("id", "")):
		return true
	if depth > 16:
		return false
	for parent: Variant in node.get("parents", []) as Array:
		var p := _board_node(str(parent))
		if not p.is_empty() and _station_closed(p, depth + 1):
			return true
	return false


## Throws the points: `node_id` is taken at its choice and the alternatives close for good. Only while the
## choice is open and the station's parents are done.
func choose(node_id: String) -> bool:
	if board_node_state(node_id) != "choice":
		return false
	board_choices[str(_board_node(node_id).get("choice", ""))] = node_id
	_baseline_station(_board_node(node_id))
	quest_changed.emit()
	return true


## A board's current station: its first open one (active, or a choice to make), top to bottom; "" when the
## board is finished.
func board_current_station(board_id: String) -> String:
	var best := ""
	var best_key := Vector2i(1 << 20, 1 << 20)
	for node: Variant in (_board_def(board_id).get("nodes", []) as Array):
		var id := str((node as Dictionary).get("id", ""))
		var state := board_node_state(id)
		if state != "active" and state != "choice":
			continue
		var key := Vector2i(int((node as Dictionary).get("col", 0)), absi(int((node as Dictionary).get("lane", 0))))
		if key.x < best_key.x or (key.x == best_key.x and key.y < best_key.y):
			best_key = key
			best = id
	return best


## Shows `board_id`'s current station on the top bar.
func follow_board(board_id: String) -> void:
	followed_board = board_id if not _board_def(board_id).is_empty() else ""
	quest_changed.emit()


## The board the top bar shows: the one the player follows while it has a station open, else the first of the
## match's boards that has one (the Tutorial, then the start's own). "" without boards.
func effective_followed_board() -> String:
	if followed_board != "" and board_current_station(followed_board) != "":
		return followed_board
	for raw: Variant in match_boards():
		var id := str((raw as Dictionary).get("id", ""))
		if board_current_station(id) != "":
			return id
	return ""


## A station's condition in plain words: its own `detail` when it has one, else from its verb.
func station_condition_text(node: Dictionary) -> String:
	if str(node.get("detail", "")) != "":
		return str(node.detail)
	var c := _station_condition(node)
	var qty := int(c.qty)
	match str(c.action):
		"Acquire":
			return "Buy %d %s from other companies." % [qty, "building" if qty == 1 else "buildings"]
		"Open Building":
			return "Open one of your buildings to see what it makes and what it needs."
		"Units Sold":
			return "Sell %d units of what you make." % qty
		"Build Any":
			return "Build %d %s." % [qty, "building" if qty == 1 else "buildings"]
		"Infrastructure":
			return "Build %d pieces of infrastructure: roads, rail, pipes or cables." % qty
		"Fast To Port":
			return "Have a building whose goods reach a port in under %d turns." % qty
		"Research Count":
			return "Unlock %d research." % qty
		"Upgrade":
			return "Upgrade %d of your buildings to Level 2." % qty
	var text := ResearchState.condition_text(c)
	return text if text != "" else str(node.get("title", ""))


func _station_condition(node: Dictionary) -> Dictionary:
	var c := (node.get("condition", {}) as Dictionary)
	return {"action": str(c.get("action", "")), "object": str(c.get("object", "")), "qty": int(c.get("qty", 0)),
		"quantity_raw": str(c.get("qty", "")), "unit": str(c.get("unit", "")), "title": str(node.get("id", ""))}


## The running total a counted verb measures, now.
func _metric(c: Dictionary) -> float:
	match str(c.action):
		"Units Sold": return float(units_sold_total)
		"Build Any": return float(buildings_built)
		"Infrastructure": return float(infra_built)
		"Open Building": return float(buildings_opened)
		"Research Count": return float(ResearchState.unlocked_titles.size())
		"Build Consumers": return float(_consumer_count())
		"Produce Tier":
			var tiers := str(c.object).split("|", false)
			var total := 0.0
			for good: Variant in Catalog.all_goods():
				if tiers.has(str((good as Dictionary).get("goods_graph_tier", ""))):
					total += float(Production.lifetime_total(str((good as Dictionary).get("id", ""))))
			return total
	return 0.0


## How far a counted station has come since it opened. A first station counts from the start of the match;
## a later one from the moment the station before it finished (_open_children).
func _counted(node: Dictionary) -> float:
	var c := _station_condition(node)
	var since := 0.0 if (node.get("parents", []) as Array).is_empty() else _metric(c)
	return _metric(c) - float(board_baseline.get(str(node.get("id", "")), since))


## Notes the baseline of every station that `done_id` finishing opens.
func _open_children(done_id: String) -> void:
	for raw: Variant in match_boards():
		for node: Variant in (raw as Dictionary).get("nodes", []) as Array:
			var n := node as Dictionary
			var id := str(n.get("id", ""))
			if (n.get("parents", []) as Array).has(done_id) and board_node_state(id) == "active":
				_baseline_station(n)


## Notes where a counted station starts counting from, the first time it opens.
func _baseline_station(n: Dictionary) -> void:
	var id := str(n.get("id", ""))
	if board_baseline.has(id):
		return
	var c := _station_condition(n)
	if COUNTED_VERBS.has(str(c.action)):
		board_baseline[id] = _metric(c)
	elif str(c.action) == "Faster To Port":
		board_baseline[id] = float(_fastest_to_port(_good_id(str(c.object))))


func _station_met(node: Dictionary, summary: Dictionary) -> bool:
	var c := _station_condition(node)
	var qty := int(c.qty)
	var obj := str(c.object)
	if COUNTED_VERBS.has(str(c.action)):
		return _counted(node) >= float(maxi(1, qty))
	match str(c.action):
		"Acquire":
			return _acquired_count() >= qty
		"Fast To Port":
			return _fastest_to_port("") < qty
		"Faster To Port":
			var base := float(board_baseline.get(str(node.get("id", "")), INF))
			return float(_fastest_to_port(_good_id(obj))) < base
		"Build Any Of":
			var n := 0
			var kinds := obj.split("|", false)
			for b: Variant in BuildingState.buildings.values():
				var inst := b as Dictionary
				if BuildingState.is_player_owned(inst) and not bool(inst.get("acquired_from_npc", false)) \
						and kinds.has(str(Catalog.get_building(str(inst.get("building_id", ""))).get("internal_name", ""))):
					n += 1
			return n >= maxi(1, qty)
		"Own Recipe":
			var runs := 0
			for b: Variant in BuildingState.buildings.values():
				if BuildingState.is_player_owned(b as Dictionary) and str((b as Dictionary).get("recipe_id", "")) == obj:
					runs += 1
			return runs >= maxi(1, qty)
		"Research":
			if obj == "Government Import/Export License":
				return ResearchState.global_trade_license_available()
			return ResearchState.is_unlocked(obj)
		"Supply":
			for pair: String in obj.split("|", false):
				var parts := pair.split(">")
				if parts.size() != 2 or not _supplied(_good_id(parts[0]), _good_id(parts[0]), _good_id(parts[1]), summary):
					return false
			return true
		"Sell On Market":
			# The global market, not the intermediary: the License in force, a building of the good's
			# routed to the market rather than to the intermediary, and some of it sold this turn.
			var gid := _good_id(obj)
			if not ResearchState.global_trade_license_available() or int(((summary.get("sold", {}) as Dictionary).get(gid, {}) as Dictionary).get("qty", 0)) <= 0:
				return false
			for iid in _producers_of(gid):
				if MatchState.is_output_market(str(iid), gid) and not MiddlemanService.buys_output(str(iid), gid):
					return true
			return false
		"Mine Infinite":
			return _mines_on_infinite(_good_id(obj), obj).size() >= maxi(1, qty)
		"Supply From Infinite":
			return _supplied_anywhere(_mines_on_infinite(_good_id(obj), obj), _good_id(obj), summary)
		"Upgrade":
			var upgraded := 0
			for b: Variant in BuildingState.buildings.values():
				var inst := b as Dictionary
				if BuildingState.is_player_owned(inst) and int(inst.get("level", 1)) >= 2 and not INFRA_BUILDINGS.has(str(inst.get("building_id", ""))):
					upgraded += 1
			return upgraded >= maxi(1, qty)
	return ResearchState.condition_met(c)


## Player buildings bought from another company rather than built.
func _acquired_count() -> int:
	var n := 0
	for b: Variant in BuildingState.buildings.values():
		if b is Dictionary and BuildingState.is_player_owned(b as Dictionary) and bool((b as Dictionary).get("acquired_from_npc", false)):
			n += 1
	return n


## Player buildings whose recipe uses a good the player also makes.
func _consumer_count() -> int:
	var made := {}
	for b: Variant in BuildingState.buildings.values():
		var inst := b as Dictionary
		if BuildingState.is_player_owned(inst):
			for out: Variant in Catalog.get_recipe(str(inst.get("recipe_id", ""))).get("outputs", []) as Array:
				made[str((out as Dictionary).get("good_id", ""))] = true
	var n := 0
	for b: Variant in BuildingState.buildings.values():
		var inst := b as Dictionary
		if not BuildingState.is_player_owned(inst):
			continue
		for inp: Variant in Catalog.get_recipe(str(inst.get("recipe_id", ""))).get("inputs", []) as Array:
			if made.has(str((inp as Dictionary).get("good_id", ""))):
				n += 1
				break
	return n


## The fewest turns any of the player's buildings making `good_id` ("" for any good) takes to reach a port.
## 1 << 20 when none can.
func _fastest_to_port(good_id: String) -> int:
	var best := 1 << 20
	for b: Variant in BuildingState.buildings.values():
		var inst := b as Dictionary
		if not BuildingState.is_player_owned(inst):
			continue
		for out: Variant in Catalog.get_recipe(str(inst.get("recipe_id", ""))).get("outputs", []) as Array:
			var gid := str((out as Dictionary).get("good_id", ""))
			if gid == "" or (good_id != "" and gid != good_id) or not Catalog.is_good_sellable(gid):
				continue
			var r := TransportService.route_to_nearest_port(str(inst.get("tile_id", "")), gid)
			if TransportService.route_is_reachable(r):
				best = mini(best, int(r.get("turns", best)))
	return best


## _supplied_from, to any tile where a building of the player's uses the good.
func _supplied_anywhere(instances: Array, ship_good: String, summary: Dictionary) -> bool:
	var supplied: Dictionary = summary.get("tile_supplied", {})
	var consumed: Dictionary = summary.get("tile_consumed", {})
	for iid in instances:
		var tile := str(MatchState.get_output_stockpile_destination(str(iid), ship_good))
		if tile == "":
			continue
		if float((supplied.get(tile, {}) as Dictionary).get(ship_good, 0)) > 0.0 \
				and float((consumed.get(tile, {}) as Dictionary).get(ship_good, 0)) > 0.0:
			return true
	return false


## Keeps the running totals the counted verbs read, from one resolved turn.
func _count_turn(summary: Dictionary) -> void:
	for gid: Variant in (summary.get("sold", {}) as Dictionary):
		var row: Variant = (summary.sold as Dictionary)[gid]
		units_sold_total += int((row as Dictionary).get("qty", 0)) if row is Dictionary else int(row)


## A construction finished: count it as a building or as infrastructure.
func _on_construction_completed(_instance_id: String, _tile_id: String) -> void:
	var bid := Construction.last_completed_building_id
	if INFRA_BUILDINGS.has(bid):
		infra_built += 1
	elif bid != "b_004":
		buildings_built += 1


## The player opened one of their buildings (Building Detail).
func note_building_opened() -> void:
	buildings_opened += 1
	if has_match_boards():
		_eval_boards({})
		quest_changed.emit()


## Ticks every open station whose condition holds, grants its reward and announces it. Notes the baseline of a
## counted station the first time it is seen open.
func _eval_boards(summary: Dictionary) -> void:
	if not is_available():
		return
	for raw: Variant in match_boards():
		for node: Variant in (raw as Dictionary).get("nodes", []) as Array:
			var n := node as Dictionary
			var id := str(n.get("id", ""))
			if board_node_state(id) != "active":
				continue
			var c := _station_condition(n)
			if not board_baseline.has(id) and str(c.action) == "Faster To Port":
				board_baseline[id] = float(_fastest_to_port(_good_id(str(c.object))))
			if not _station_met(n, summary):
				continue
			board_done[id] = true
			_open_children(id)
			if not bool(board_granted.get(id, false)):
				board_granted[id] = true
				_grant_station(n)
				_announce(id)


func _grant_station(node: Dictionary) -> void:
	var reward := node.get("reward", {}) as Dictionary
	var list: Array = (reward.get("modifiers", []) as Array).duplicate()
	if reward.has("modifier"):
		list.append(reward.modifier)
	for i in list.size():
		var m := list[i] as Dictionary
		var fields := {"domain": str(m.get("domain", "")), "target": str(m.get("target", "*")), "pct": float(m.get("pct", 0.0)),
			"label": str(node.get("title", "")), "source": "quest:%s" % str(node.get("id", ""))}
		if m.has("target_match"):
			fields["target_match"] = (m.target_match as Dictionary).duplicate(true)
		if int(m.get("turns", 0)) > 0:
			fields["duration_turns"] = int(m.turns)
		_add(BOARD_REWARD_PREFIX + str(node.get("id", "")) + ("" if i == 0 else "_%d" % i), fields)
	if int(reward.get("free_unlocks", 0)) > 0:
		ResearchState.grant_free_unlocks(int(reward.free_unlocks))


## A station's count, for the verbs that count something the player can watch grow.
func _station_progress(node: Dictionary) -> Vector2i:
	var c := _station_condition(node)
	var need := int(c.qty)
	var id := str(node.get("id", ""))
	var state := board_node_state(id)
	if need < 2 or state == "complete" or state == "closed":
		return Vector2i.ZERO
	if COUNTED_VERBS.has(str(c.action)):
		var have := int(_counted(node)) if state == "active" else 0
		return Vector2i(clampi(have, 0, need), need)
	match str(c.action):
		"Acquire":
			return Vector2i(mini(_acquired_count(), need), need)
	return Vector2i.ZERO
