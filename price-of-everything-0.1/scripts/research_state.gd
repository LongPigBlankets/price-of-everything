extends Node
## ResearchState: research unlocks — the definitions loaded from data/research_unlocks.csv,
## which titles are unlocked, and the progress accumulators the live "unlock by doing"
## conditions read (port sales, infrastructure-usage streaks, profitable-run streaks,
## stockpile-feed streaks). Extracted from MatchState on 2026-09-11; the save keys are
## unchanged and still live under the "match" section (MatchState.export_state merges
## export_fields(), import_state calls import_fields(), reset() calls reset()).
##
## Turn hook: TurnManager._wire_sim_listeners connects _on_phase_started so the NARRATIVE
## refresh runs after MatchState's own hook and before EventScheduler / Modifiers — the
## documented order (unlock checks precede the event tick precedes modifier pruning).
##
## Reads MatchState for the shared core (buildings, land, money, advisor flags) and
## never writes it except through MatchState's own API.

## The research title that opens the rest of the council (data/research_unlocks.csv).
const SEATS_UNLOCK_TITLE := "Executive Search"

# Legacy research rows use a mix of internal names, display names and names of
# the process/research concept that represents a building group. Resolve those
# labels centrally so live conditions do not depend on CSV casing or wording.
const RESEARCH_BUILDING_ALIASES := {
	"oil_refinery": ["petro_refinery"],
	"coal_power_plant": ["power_plant"],
	"factory": ["industrial_factory"],
	"steel_mill": ["furnace"],
	"polymer_feedstocks": ["poly_plant"],
	"precision_reagent_handling": ["chem_plant"],
	"bioreactor": ["farm"],
	"cell_culture_automation": ["farm"],
	"modular_factory_cells": ["industrial_factory"],
	"grid_synchronous_generation": [
		"power_plant", "solar_farm", "onshore_wind_farm", "offshore_wind_farm",
		"hydro_power_plant",
	],
	"wind_farm": ["onshore_wind_farm", "offshore_wind_farm"],
	"renewable_dispatch_forecasting": [
		"solar_farm", "onshore_wind_farm", "offshore_wind_farm", "hydro_power_plant",
	],
	"pipe_network": ["pipes", "reinf_pipes"],
	"utility_corridor": ["roads", "rails", "pipes", "reinf_pipes", "cables"],
	"battery": ["battery"],
	"offshore_platform": ["offshore_oil_platform"],
	"forest": ["new_forest", "old_forest"],
	# Not keyed "power_plant": the coal plant has that internal name, and the alias key
	# would otherwise swallow the literal building and make every
	# coal-plant-specific gate satisfiable by a solar farm.
	"any_power_plant": [
		"power_plant", "solar_farm", "onshore_wind_farm", "offshore_wind_farm",
		"hydro_power_plant",
	],
}
const RESEARCH_GOOD_ALIASES := {
	"bioplastics": "plastics",
	"motors": "motor",
}

## A research unlock was granted. via_condition is true when earned by meeting its
## condition (shows the "Unlocked …" dialog); false for a free-chosen unlock.
signal unlock_granted(title: String, description: String, via_condition: bool)

# Research unlocks: which are unlocked (by free choice or by meeting a condition),
# and progress toward the action+object+quantity conditions (e.g. "Survey|tiles").
var unlocked_titles: Dictionary = {}
var _unlock_progress: Dictionary = {}
# Lifetime sales routed through any seaport. These deliberately do not share the
# market's general sales ledger: the logistics research chain requires that the
# goods actually crossed a port.
var _port_sale_total: int = 0
## Lifetime units EXPORTED through each port (port_tile -> units). Drives the Logistics
## shipping line's "through each port" condition — see docs/early-game-onboarding-spec.md §4.2b.
var _port_sales_by_port: Dictionary = {}
var _port_sales_by_class: Dictionary = {}
# Consecutive-turn progress for the infrastructure-utilisation research gates.
# Kept separately from the legacy action/object accumulator because its Quantity is
# the number of busy segments, while its duration lives in the Unit field.
var _infrastructure_usage_streaks: Dictionary = {}
var _infrastructure_usage_last_turn: Dictionary = {}
# Per-building consecutive turns that were both productive and profitable at the
# live market price. This backs the timed "Run … profitably" research gates.
var _profitable_run_streaks: Dictionary = {}
# Research conditions draw from several simulation services (production, market,
# construction, ports and CostSolver).  They must be resolved after those services
# have settled for the turn, not once for every individual shipment or building
# completion.  Mutations merely mark this central snapshot dirty; NARRATIVE owns
# the single authoritative refresh.
var _research_progress_dirty: bool = true
var _research_progress_last_turn: int = -1
# Per-tile CONSECUTIVE-turn streak of "stockpile fed by 3+ distinct buildings this
# turn" — the Just-in-Time Logistics unlock condition. Updated by Production at
# output flush; tiles that miss the bar in a turn drop out (streak resets). Saved.
var stockpile_feed_streaks: Dictionary = {}
var _unlock_defs: Array = []   # [{research_node_id, title, action, object, qty, prereqs, description}]
var _node_id_by_title: Dictionary = {}   # lazy title -> research_node_id (see research_node_id_for_title)
var _title_by_node_id: Dictionary = {}   # lazy research_node_id -> title (see research_title_for_node_id)


func _ready() -> void:
	_load_unlock_defs()


func _on_phase_started(phase: int) -> void:
	if phase == TurnManager.Phase.NARRATIVE:
		# Production, costs and run-streaks have settled for the turn — one central
		# research pass reads the final production/sales/profitability state.  This
		# deliberately replaces per-shipment and per-completion scans.
		_update_profitable_run_streaks()
		_refresh_research_progress()


## Match-scoped: a reset (new game / scenario start) must clear it, or unlocks leak from the
## previous match. Load overwrites it via import_fields, so this only bites the
## reset-without-import paths.
func reset() -> void:
	unlocked_titles.clear()
	_unlock_progress.clear()
	_port_sale_total = 0
	_port_sales_by_port.clear()
	_port_sales_by_class.clear()
	_infrastructure_usage_streaks.clear()
	_infrastructure_usage_last_turn.clear()
	_profitable_run_streaks.clear()
	_research_progress_dirty = true
	_research_progress_last_turn = -1
	stockpile_feed_streaks.clear()


## Saved under MatchState's "match" section (keys unchanged from before the extraction).
func export_fields() -> Dictionary:
	return {
		"unlocked_titles": unlocked_titles.duplicate(true),
		"unlock_progress": _unlock_progress.duplicate(true),
		"port_sale_total": _port_sale_total,
		"port_sales_by_port": _port_sales_by_port.duplicate(true),
		"port_sales_by_class": _port_sales_by_class.duplicate(true),
		"infrastructure_usage_streaks": _infrastructure_usage_streaks.duplicate(true),
		"infrastructure_usage_last_turn": _infrastructure_usage_last_turn.duplicate(true),
		"profitable_run_streaks": _profitable_run_streaks.duplicate(true),
		"stockpile_feed_streaks": stockpile_feed_streaks.duplicate(true),
	}


func import_fields(d: Dictionary) -> void:
	unlocked_titles = (d.get("unlocked_titles", {}) as Dictionary).duplicate(true)
	# Research saves still store display titles. Preserve the node when its title
	# becomes more specific, so an existing Containerized Freight unlock keeps its
	# Tier-II position and receives the revised port-fee effect.
	if unlocked_titles.has("Containerized Freight"):
		unlocked_titles["Multimodal Containerized Freight"] = unlocked_titles["Containerized Freight"]
		unlocked_titles.erase("Containerized Freight")
	_unlock_progress = (d.get("unlock_progress", {}) as Dictionary).duplicate(true)
	_port_sale_total = int(d.get("port_sale_total", 0))
	_port_sales_by_port = (d.get("port_sales_by_port", {}) as Dictionary).duplicate(true)
	_port_sales_by_class = (d.get("port_sales_by_class", {}) as Dictionary).duplicate(true)
	_infrastructure_usage_streaks = (d.get("infrastructure_usage_streaks", {}) as Dictionary).duplicate(true)
	_infrastructure_usage_last_turn = (d.get("infrastructure_usage_last_turn", {}) as Dictionary).duplicate(true)
	_profitable_run_streaks = (d.get("profitable_run_streaks", {}) as Dictionary).duplicate(true)
	_research_progress_dirty = true
	_research_progress_last_turn = -1
	stockpile_feed_streaks = (d.get("stockpile_feed_streaks", {}) as Dictionary).duplicate(true)


## Lifetime seaport export ledger, fed by MatchState.commit_sea_shipping. Kept apart from
## the market's general sales ledger: the logistics research chain requires that the goods
## actually crossed a port.
func note_port_sale(transport_class: String, port_tile: String, qty: int) -> void:
	_port_sale_total += qty
	_port_sales_by_class[transport_class] = int(_port_sales_by_class.get(transport_class, 0)) + qty
	_port_sales_by_port[port_tile] = int(_port_sales_by_port.get(port_tile, 0)) + qty


## Research nodes hidden for the demo. The CSV row is kept so the node
## can return post-demo, but it never loads: no tab card, no condition, no prereq link.
## Its recipe is hidden in step via Catalog.HIDDEN_RECIPE_IDS.
const HIDDEN_RESEARCH_IDS := {
	"research_petro_020": true,   # Methane Pyrolysis — no methane in the demo
	"research_biochem_002": true, # Enzyme Screening — bioplastics chain not in the demo
	"research_biochem_003": true, # Bioplastic Precursors — same
	"research_inorg_023": true,   # Zero-Liquid Discharge — replaced by Novel Membrane Filtration (inorg_025)
	"research_biochem_005": true, # Cell Culture Automation — bioplastics chain not in the demo
}

## Shared content gate, independent of tiers and prerequisites. Search and every
## grant path must respect these flags, including exact-title links and free picks.
func is_research_visible(definition: Dictionary) -> bool:
	var node_id := str(definition.get("research_node_id", ""))
	if HIDDEN_RESEARCH_IDS.has(node_id):
		return false
	if str(definition.get("category", "")) == "Recycling" and not MatchState.is_recycling_available():
		return false
	if node_id in ["research_people_008", "research_people_009", "research_people_010", "research_people_011"] and not AdvisorState.advisors_unlocked:
		return false
	return true

# --- Public API: research unlocks ---
func _load_unlock_defs() -> void:
	_unlock_defs.clear()
	_node_id_by_title.clear()   # rebuilt lazily against the rows loaded below
	_title_by_node_id.clear()
	var path := "res://data/research_unlocks.csv"
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var header := f.get_csv_line()
	var idx := {}
	for i in header.size():
		idx[header[i].strip_edges()] = i
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.is_empty() or row[0].strip_edges() == "":
			continue
		if HIDDEN_RESEARCH_IDS.has(_csv_at(row, idx, "research_node_id")):
			continue   # demo-hidden node: never loads, so nothing can link to it
		var prereqs: Array = []
		for col in ["prereq_1", "prereq_2", "prereq_3"]:
			var p := _csv_at(row, idx, col)
			if p != "":
				prereqs.append(p)
		var q := _csv_at(row, idx, "Quantity")
		var rank_raw := _csv_at(row, idx, "rank").strip_edges().to_upper()
		_unlock_defs.append({
			"research_node_id": _csv_at(row, idx, "research_node_id"),
			"title": _csv_at(row, idx, "title"),
			"category": _csv_at(row, idx, "category"),
			"rank": rank_raw if rank_raw != "" else "I",
			"action": _csv_at(row, idx, "Action"),
			"object": _csv_at(row, idx, "Object"),
			"qty": int(q) if q.is_valid_int() else _leading_int(q, 0),
			"quantity_raw": q,
			"unit": _csv_at(row, idx, "Unit"),
			"prereqs": prereqs,
			"description": _csv_at(row, idx, "description"),
		})
	f.close()

func _csv_at(row: PackedStringArray, idx: Dictionary, col: String) -> String:
	if not idx.has(col):
		return ""
	var i: int = idx[col]
	return row[i].strip_edges() if i < row.size() else ""

## Stable id for a research node's display title, or "" if the title is unknown.
## `research_node_id` (research_unlocks.csv, assigned by tools/assign_research_ids.py) is
## the permanent handle: renaming a node's title must not silently deaden the effects
## keyed to it, which is what happened twice while UNLOCK_MODIFIERS was title-keyed.
## Titles remain the canonical key in SAVES for now — see docs note in that tool.
func research_node_id_for_title(title: String) -> String:
	if _node_id_by_title.is_empty():
		for d in _unlock_defs:
			var t := str(d.get("title", ""))
			var nid := str(d.get("research_node_id", ""))
			if t != "" and nid != "":
				_node_id_by_title[t] = nid
	return str(_node_id_by_title.get(title, ""))


## Display title for a research node id, or "" if unknown. The inverse of
## research_node_id_for_title — used where a stored id has to be shown to the player
## (a gated recipe's "requires research: …" line) so raw ids never reach the UI.
func research_title_for_node_id(node_id: String) -> String:
	if _title_by_node_id.is_empty():
		for d in _unlock_defs:
			var t := str(d.get("title", ""))
			var nid := str(d.get("research_node_id", ""))
			if t != "" and nid != "":
				_title_by_node_id[nid] = t
	return str(_title_by_node_id.get(node_id, ""))


## Accepts a research_node_id (what prereq columns and recipe gates now store), a display
## title (what SAVES still store), or a bare cheat token like "hydro"/"consumer" that has
## no node at all. Taking all three keeps every gate call site unchanged across the id
## migration — only what the DATA stores changed.
func is_unlocked(title_or_id: String) -> bool:
	if unlocked_titles.has(title_or_id):
		return true
	var mapped := research_title_for_node_id(title_or_id)
	return mapped != "" and unlocked_titles.has(mapped)

# Grant the first not-yet-unlocked research node in a category (an advisor-mission
# reward). Returns the granted title, or "" if the category is already fully unlocked.
func grant_first_locked_in_category(category: String) -> String:
	for d in _unlock_defs:
		if str(d.get("category", "")) == category:
			var title := str(d.get("title", ""))
			if title != "" and not is_unlocked(title) and is_research_visible(d):
				grant_unlock(title)
				return title
	return ""

# Deposit penalty + mining-yield research now live in the Modifiers system as
# recipe_output tiles (Modifiers.EXTRACTION_PENALTY_PCT + the mining UNLOCK_MODIFIERS),
# so they apply through the one production hook and surface in the recipe card's
# net-modifier indicator. The old get_deposit_yield()/PENALISED_EXTRACTION/
# RESEARCH_YIELD_BONUS triplet was removed.

## Grant an unlock. via_condition true => earned by its condition (drives the
## "Unlocked …" dialog); false => a free-chosen unlock (no dialog).
func grant_unlock(title: String, via_condition: bool = false) -> void:
	if title == "" or unlocked_titles.has(title):
		return
	var definition := get_unlock_def(title)
	if definition.is_empty() or not is_research_visible(definition):
		return
	unlocked_titles[title] = true
	# Opening the rest of the council is not a modifier, so it is applied here rather than
	# through apply_unlock_modifier. See docs/early-game-onboarding-spec.md §5.4.
	if title == SEATS_UNLOCK_TITLE:
		AdvisorState.all_seats_unlocked = true
		AdvisorState.advisors_changed.emit()
	MatchState._surveyable_dirty = true  # e.g. Geoscanning changes survey range
	AdvisorState.flag_agenda_event(AdvisorState.AGENDA_TECH_UNLOCK)
	# Apply any standing modifier this unlock grants NOW, not only via the signal
	# below: unlocks fired during game setup (e.g. a start's buildings hitting
	# "Operational Team Managers" at 3 buildings) can emit before ModifierState's
	# unlock_granted listener is connected, and grant_unlock is one-shot — so the
	# signal alone would drop the bonus. Idempotent (add() keys by id).
	Modifiers.apply_unlock_modifier(title)
	var desc := ""
	for d in _unlock_defs:
		if str(d.title) == title:
			desc = str(d.description)
			break
	unlock_granted.emit(title, desc, via_condition)

## The loaded unlock definition for a research title (empty if unknown).
func get_unlock_def(title: String) -> Dictionary:
	for d in _unlock_defs:
		if str(d.get("title", "")) == title:
			return d
	return {}

# ── Research tier gating (per category) ──────────────────────────────────────
## Nodes of the prior tier needed to open the next one. Two, not three:
## Petrochemistry had exactly three Tier I nodes, so "three of the prior tier" meant ALL of
## them, and Tier II was gated behind clearing a whole tier rather than committing to it.
const TIER_UNLOCK_THRESHOLD := 1
const _TIER_ORDER := ["I", "II", "III"]

## True when `category`'s roman `tier` is open. Tier I is always open; a higher
## tier opens once >= min(TIER_UNLOCK_THRESHOLD, nodes-in-prior-tier) of the
## immediately lower tier in the same category are unlocked. The clamp lets thin
## categories (fewer than 3 nodes in a tier) advance by unlocking ALL of them, so
## they can never permanently softlock.
func is_tier_available(category: String, tier: String) -> bool:
	var t := tier.strip_edges().to_upper()
	var i := _TIER_ORDER.find(t)
	if i <= 0:
		return true
	var prev: String = _TIER_ORDER[i - 1]
	var total := _tier_node_count(category, prev)
	if total <= 0:
		return true
	return _tier_unlocked_count(category, prev) >= mini(TIER_UNLOCK_THRESHOLD, total)

func _tier_node_count(category: String, tier: String) -> int:
	var n := 0
	for d in _unlock_defs:
		if is_research_visible(d) and str(d.get("category", "")) == category and str(d.get("rank", "I")) == tier:
			n += 1
	return n

func _tier_unlocked_count(category: String, tier: String) -> int:
	var n := 0
	for d in _unlock_defs:
		if is_research_visible(d) and str(d.get("category", "")) == category and str(d.get("rank", "I")) == tier \
				and unlocked_titles.has(str(d.get("title", ""))):
			n += 1
	return n

## A research node is currently available (workable toward / grantable / free-pickable)
## when its category tier is open AND every listed prereq is already unlocked.
func is_node_available(title: String) -> bool:
	var d := get_unlock_def(title)
	if d.is_empty() or not is_research_visible(d):
		return false
	if not is_tier_available(str(d.get("category", "")), str(d.get("rank", "I"))):
		return false
	for p in d.get("prereqs", []):
		# prereqs are research_node_ids; is_unlocked resolves them against the
		# title-keyed unlocked set.
		if not is_unlocked(str(p)):
			return false
	return true

## Human-readable "unlock-by-doing" condition for a research title — the same
## wording the research panel shows on a node card. Empty when the node carries
## no real condition (Placeholder / missing fields).
func unlock_condition_text(title: String) -> String:
	var d := get_unlock_def(title)
	if d.is_empty():
		return ""
	var action := str(d.get("action", "")).strip_edges()
	if action == "Placeholder":
		return ""
	var object_name := str(d.get("object", "")).strip_edges()
	var qty := int(d.get("qty", 0))
	var unit := str(d.get("unit", "")).strip_edges()
	if action.is_empty() or object_name.is_empty() or qty <= 0 or unit.is_empty():
		return ""
	if action == "Produce All":
		var goods := object_name.split("|", false)
		var quantities := str(d.get("quantity_raw", "")).split("|", false)
		if goods.size() == quantities.size() and not goods.is_empty():
			var parts: Array = []
			for index in goods.size():
				parts.append("%s %s" % [str(quantities[index]), _condition_good_label(str(goods[index]))])
			return "Produce %s" % MatchState._join_and(parts)
	if action == "Produce Any":
		# OR across goods: 500 of EITHER good unlocks it. A single Quantity applies to
		# every good; a "a|b" Quantity gives per-good thresholds like Produce All.
		var any_goods := object_name.split("|", false)
		var any_qtys := str(d.get("quantity_raw", "")).split("|", false)
		if not any_goods.is_empty():
			var parts: Array = []
			for index in any_goods.size():
				var want := qty
				if any_qtys.size() == any_goods.size() and str(any_qtys[index]).is_valid_int():
					want = int(str(any_qtys[index]))
				parts.append("%d %s" % [want, _condition_good_label(str(any_goods[index]))])
			return "Produce %s" % MatchState._join_or(parts)
	match action:
		"Produce": return "Produce %d %s" % [qty, _condition_good_label(object_name)]
		"Sell": return "Sell %d units through the market" % qty if _research_key(object_name) == "freight" else "Sell %d %s through the market" % [qty, _condition_good_label(object_name)]
		"Sell Through Ports": return "Sell %d units through ports" % qty
		"Sell Through Every Port": return "Export %d units through EVERY port" % qty
		"Own Port At Level": return "Own a port upgraded to level %d" % qty
		"Sell Through Ports Classes": return "Sell at least %d units of each weight class through ports" % qty
		"Purchase Ports": return "Purchase all %d ports" % qty
		"Build": return "Build %d %s" % [qty, _condition_building_label(object_name, qty)]
		"Own": return "Own %d land plots" % qty if _research_key(object_name) == "land" else "Own %d %s" % [qty, _condition_good_label(object_name)]
		"Run":
			var run_turns := _leading_int(unit, 0)
			return "Operate at least %d %s at full capacity for %d consecutive turns" % [qty, _condition_building_label(object_name, qty), run_turns] if run_turns > 0 else "Operate 1 %s at full capacity for %d consecutive turns" % [_condition_building_label(object_name, 1), qty]
		"Run L1": return "Operate %d Level 1 %s at full capacity for %s" % [qty, _condition_building_label(object_name, qty), unit]
		"Run Profitable":
			var profitable_turns := _leading_int(unit, 0)
			return "Operate at least %d %s profitably for %d consecutive turns" % [qty, _condition_building_label(object_name, qty), profitable_turns] if profitable_turns > 0 else "Operate %d %s profitably" % [qty, _condition_building_label(object_name, qty)]
		"Run Profitable L2": return "Operate %d Level 2 %s profitably" % [qty, _condition_building_label(object_name, qty)]
		"Run Same Tile":
			var same_turns := _leading_int(unit, 0)
			return "Operate %d %s on the same tile at full capacity for %d consecutive turns" % [qty, _condition_building_label(object_name, qty), same_turns] if same_turns > 0 else "Operate %d %s on the same tile" % [qty, _condition_building_label(object_name, qty)]
		"Own On Tiles": return "Own %s on at least %d different tiles" % [_condition_building_label(object_name, 2), qty]
		"Run Distinct Recipes": return "Operate %d %s, each on a different recipe" % [qty, _condition_building_label(object_name, qty)]
		"Own All":
			var own_parts: Array = []
			var own_names := object_name.split("|", false)
			var own_qtys := str(d.get("quantity_raw", "")).split("|", false)
			for index in own_names.size():
				var own_n := qty
				if own_qtys.size() == own_names.size() and str(own_qtys[index]).is_valid_int():
					own_n = int(str(own_qtys[index]))
				own_parts.append("%d %s" % [own_n, _condition_building_label(str(own_names[index]), own_n)])
			return "Own %s" % MatchState._join_and(own_parts)
		"Run Producing":
			var prod_turns := _leading_int(unit, 0)
			var prod_who := "a building" if qty <= 1 else "%d buildings" % qty
			return "Operate %s making %s at full capacity for %d consecutive turns" % [prod_who, _condition_good_label(object_name), prod_turns] if prod_turns > 0 else "Operate %s making %s at full capacity" % [prod_who, _condition_good_label(object_name)]
		"Run Profitable L1": return "Operate %d Level 1 %s profitably for %s" % [qty, _condition_building_label(object_name, qty), unit]
		"All Of":
			var all_parts: Array = []
			for spec in object_name.split(";", false):
				var sub := _parse_sub_condition(str(spec))
				if not sub.is_empty():
					all_parts.append(_sub_condition_text(sub))
			return MatchState._join_and(all_parts).capitalize() if all_parts.is_empty() else (MatchState._join_and(all_parts)[0].to_upper() + MatchState._join_and(all_parts).substr(1))
		"Ship Multimodal": return "Move at least %d freight in a single turn using more than one mode of transport" % qty
		"Produce Per Turn": return "Produce at least %d %s in a single turn" % [qty, _condition_good_label(object_name)]
		"Produce Per Turn Any":
			var rate_parts: Array = []
			var rate_names := object_name.split("|", false)
			var rate_raw := str(d.get("quantity_raw", "")).split("|", false)
			for index in rate_names.size():
				var rate_n := qty
				if rate_raw.size() == rate_names.size() and str(rate_raw[index]).is_valid_int():
					rate_n = int(str(rate_raw[index]))
				rate_parts.append("%d %s" % [rate_n, _condition_good_label(str(rate_names[index]))])
			return "Produce at least %s in a single turn" % MatchState._join_or(rate_parts)
		"Run Multiple": return _run_multiple_condition_text(d)
		"Fulfil Special Orders": return "Fulfil at least %d special orders" % qty
		"Run Recipe Profitable": return "Run %d buildings with %s recipes profitably" % [qty, "steelmaking" if _research_key(object_name) == "steel_production" else object_name.to_lower()]
		"Run Recipe": return "Operate %d building%s using a %s recipe" % [qty, "" if qty == 1 else "s", object_name]
		"Survey": return "Survey %d %s" % [qty, object_name]
		"Stockpile filled": return "Supply one stockpile from %s for %d consecutive turns" % [object_name, qty]
		"Sustain": return "Maintain %s for %d consecutive turns" % [object_name, qty]
		"Use Infrastructure":
			var use_turns := _leading_int(unit.get_slice("for", 1), 5) if "for" in unit else 0
			if "of l1" in unit.to_lower():
				# Absolute bar against Level-1 capacity (see _infrastructure_usage_met).
				var use_pct := _leading_int(unit, 80)
				return "Carry %d%% of Level-1 capacity on %d %s for %d consecutive turns" % [use_pct, qty, object_name.capitalize(), use_turns] if use_turns > 0 else "Carry %d%% of Level-1 capacity on %d %s" % [use_pct, qty, object_name.capitalize()]
			return "Use at least %d %s at 80%% throughput or higher" % [qty, _condition_good_label(object_name)] if use_turns <= 0 else "Use %d %s at 80%% capacity for %d consecutive turns" % [qty, object_name.capitalize(), use_turns]
		"Firm Intermittency": return "Firm at least %d power of intermittent generation" % qty
	return "%s %s %d" % [action, object_name, qty]

## Record progress toward action+object conditions (e.g. record("Survey","tiles")).
## Advance/reset the per-tile "stockpile fed by 7+ buildings" streaks from this
## turn's flush: {tile_id -> distinct producing buildings}. Tiles at the bar
## extend their streak; every other tile (including ones absent this turn) resets.
const STOCKPILE_FEED_STREAK_BUILDINGS := 7

func update_stockpile_feed_streaks(fed_counts: Dictionary) -> void:
	var next: Dictionary = {}
	for t in fed_counts:
		if int(fed_counts[t]) >= STOCKPILE_FEED_STREAK_BUILDINGS:
			next[t] = int(stockpile_feed_streaks.get(t, 0)) + 1
	stockpile_feed_streaks = next

func max_stockpile_feed_streak() -> int:
	var best := 0
	for t in stockpile_feed_streaks:
		best = maxi(best, int(stockpile_feed_streaks[t]))
	return best

func record_unlock_progress(action: String, object: String, amount: int = 1) -> void:
	if amount <= 0:
		return
	var key := (action + "|" + object).to_lower()
	_unlock_progress[key] = int(_unlock_progress.get(key, 0)) + amount
	_mark_research_progress_dirty()


## Mark the central research snapshot stale.  The next NARRATIVE phase performs
## exactly one complete evaluation after every upstream metric is final.
func _mark_research_progress_dirty() -> void:
	_research_progress_dirty = true


## One authoritative research-progress refresh per resolved turn.  Keeping this
## separate from `_check_unlock_conditions()` preserves the latter as a useful
## immediate diagnostic/test API while removing it from high-frequency game paths.
func _refresh_research_progress() -> void:
	var turn := int(TurnManager.current_turn)
	if _research_progress_last_turn == turn and not _research_progress_dirty:
		return
	_research_progress_last_turn = turn
	_research_progress_dirty = false
	_check_unlock_conditions()

func _check_unlock_conditions() -> void:
	for d in _unlock_defs:
		var title := str(d.title)
		if title == "" or unlocked_titles.has(title) or int(d.qty) <= 0 or not is_research_visible(d):
			continue
		var action := str(d.action)
		if action == "" or str(d.object) == "":
			continue
		# Per-category tier-lock: a higher tier's conditions can't be met until enough
		# of the prior tier is unlocked (see is_tier_available). Reuses `d` so this
		# stays a single pass over _unlock_defs.
		if not is_tier_available(str(d.get("category", "")), str(d.get("rank", "I"))):
			continue
		var prereqs_met := true
		for p in d.prereqs:
			if not is_unlocked(str(p)):   # prereqs are research_node_ids
				prereqs_met = false
				break
		if not prereqs_met:
			continue
		# Live conditions evaluated against current state (production/sales totals,
		# owned land/buildings, profitability and run-streaks). Legacy CSV Objects
		# may be IDs, internal names, display names or explicit concept aliases.
		# Level-filtered verbs ("Run L1", "Run Profitable L2") are forward-compatible:
		# every building is Level 1 until the leveling mechanic ships, so L1 gates can
		# already fire and L2 gates wait for it.
		if _live_condition_met(d):
			grant_unlock(title, true)
			continue
		# Legacy flat action|object accumulator (Survey progress, etc.).
		var key := (action + "|" + str(d.object)).to_lower()
		if int(_unlock_progress.get(key, 0)) >= int(d.qty):
			grant_unlock(title, true)

# True when a research def's live condition is satisfied right now. Survey also
# retains the legacy accumulator below, while all other shipped verbs resolve here.
func _live_condition_met(d: Dictionary) -> bool:
	var action := str(d.action)
	var obj := str(d.object)
	var need := int(d.qty)
	match action:
		"Produce":
			var produce_good := _research_good_id(obj)
			return produce_good != "" and Production.lifetime_total(produce_good) >= need
		"Produce All":
			var goods := obj.split("|", false)
			var quantities := str(d.get("quantity_raw", need)).split("|", false)
			if goods.is_empty() or goods.size() != quantities.size():
				return false
			for index in goods.size():
				var good_id := _research_good_id(str(goods[index]))
				var quantity_text := str(quantities[index])
				if good_id == "" or not quantity_text.is_valid_int() or Production.lifetime_total(good_id) < int(quantity_text):
					return false
			return true
		"Produce Any":
			# OR: producing `need` of ANY listed good satisfies it. A "a|b" Quantity
			# gives per-good thresholds; a single Quantity applies to every good.
			var any_goods := obj.split("|", false)
			var any_qtys := str(d.get("quantity_raw", need)).split("|", false)
			for index in any_goods.size():
				var gid := _research_good_id(str(any_goods[index]))
				if gid == "":
					continue
				var want := need
				if any_qtys.size() == any_goods.size() and str(any_qtys[index]).is_valid_int():
					want = int(str(any_qtys[index]))
				if Production.lifetime_total(gid) >= want:
					return true
			return false
		"Sell":
			if _research_key(obj) == "freight":
				return MarketState.lifetime_sold_total() >= need
			var sell_good := _research_good_id(obj)
			return sell_good != "" and MarketState.lifetime_sold(sell_good) >= need
		"Sell Through Ports":
			return _port_sale_total >= need
		"Sell Through Every Port":
			# Every port on the map must have carried `need` units of the player's exports.
			# Volume is the small part; the real ask is REACH.
			for port in Catalog.all_ports():
				var ptile := str(port.get("tile_id", ""))
				if ptile != "" and int(_port_sales_by_port.get(ptile, 0)) < need:
					return false
			return true
		"Own Port At Level":
			# A port building (b_004) the player owns, upgraded to at least `need`.
			for b in BuildingState.buildings.values():
				if not (b is Dictionary) or not BuildingState.is_player_owned(b):
					continue
				if str(b.get("building_id", "")) == "b_004" and int(b.get("level", 1)) >= need:
					return true
			return false
		"Sell Through Ports Classes":
			var classes := obj.split("|", false)
			if classes.is_empty():
				return false
			for transport_kind in classes:
				if int(_port_sales_by_class.get(str(transport_kind), 0)) < need:
					return false
			return true
		"Purchase Ports":
			return TransportState._owned_port_count() >= need
		"Build":
			# Own N player-built buildings of this type (any level/run state).
			return _count_buildings(obj, -1, false, 0) >= need
		"Own":
			if _research_key(obj) == "land":
				return _research_owned_land_units() >= need
			if _research_key(obj) == "offshore_oil_land":
				return _owned_offshore_oil_land() >= need
			return _count_buildings(obj, -1, false, 0) >= need
		"Run":
			# Plain Run conditions mean one matching building sustaining full output
			# for Quantity turns ("Run Mine for 15 turns"). Rows with a turn count
			# in Unit instead mean N matching buildings for that many turns.
			var run_turns := _leading_int(str(d.get("unit", "")), 0)
			return _count_buildings(obj, -1, false, run_turns) >= need if run_turns > 0 else _count_buildings(obj, -1, false, need) >= 1
		"Run Profitable":
			return _count_buildings(obj, -1, true, _leading_int(str(d.get("unit", "")), 0)) >= need
		"Run L1":
			# "Run N Level-1 buildings of this type for <Unit> turns."
			var turns := _leading_int(str(d.get("unit", "")), 20)
			return _count_buildings(obj, 1, false, turns) >= need
		"Run Profitable L2":
			return _count_buildings(obj, 2, true, 0) >= need
		"Run Same Tile":
			# N running buildings of this type on ONE tile; a leading int in Unit adds a
			# full-output streak ("4 mines on the same tile for 15 turns").
			return _max_same_tile_count(obj, _leading_int(str(d.get("unit", "")), 0)) >= need
		"Own On Tiles":
			# This building type present on at least N distinct tiles (reach, not volume).
			return _tiles_with_building(obj) >= need
		"Run Distinct Recipes":
			# N running buildings of this type each on a DIFFERENT recipe ("3 chem plants
			# with different recipes") — breadth of process, not fleet size.
			return _distinct_recipes_running(obj) >= need
		"Own All":
			# "a|b" building types with "x|y" counts: own at least each ("a chem plant AND
			# a power plant"). Mirrors Produce All.
			var own_targets := obj.split("|", false)
			var own_counts := str(d.get("quantity_raw", need)).split("|", false)
			if own_targets.is_empty():
				return false
			for index in own_targets.size():
				var want_n := need
				if own_counts.size() == own_targets.size() and str(own_counts[index]).is_valid_int():
					want_n = int(str(own_counts[index]))
				if _count_buildings(str(own_targets[index]), -1, false, 0) < want_n:
					return false
			return true
		"Run Producing":
			# N buildings whose CURRENT recipe outputs this good, at full output for the
			# streak in Unit ("run a recipe producing chlorine for 15 turns") — by output,
			# so it spans recipes in different categories.
			return _count_running_producing(_research_good_id(obj), _leading_int(str(d.get("unit", "")), 0)) >= need
		"Run Profitable L1":
			# N Level-1 buildings profitable for the streak in Unit.
			return _count_buildings(obj, 1, true, _leading_int(str(d.get("unit", "")), 0)) >= need
		"All Of":
			# Compound AND: Object is ";"-separated clauses, each "Action|Object|Qty|Unit"
			# ("operate 5 refineries AND produce alloy metals"). Every clause must hold.
			var clauses := obj.split(";", false)
			if clauses.is_empty():
				return false
			for spec in clauses:
				var sub := _parse_sub_condition(str(spec))
				if sub.is_empty() or not _live_condition_met(sub):
					return false
			return true
		"Produce Per Turn":
			# A RATE: the last resolved turn's output of this good, not lifetime volume
			# ("produce at least 300 steel per turn").
			var rate_good := _research_good_id(obj)
			return rate_good != "" and int((Production.last_turn_summary.get("produced", {}) as Dictionary).get(rate_good, 0)) >= need
		"Ship Multimodal":
			# Last turn's freight reached `need` units AND travelled by more than one transport
			# mode ("100 freight per turn using more than 1 mode").
			var mm := _multimodal_freight_last_turn()
			return int(mm.get("total", 0)) >= need and (mm.get("modes", {}) as Dictionary).size() >= 2
		"Produce Per Turn Any":
			# A rate on ANY of an "a|b" list: last turn's output of any listed good reached its
			# threshold ("30 pet coke per turn OR 30 biomass per turn"). Shared qty, or per-good "x|y".
			var rate_goods := obj.split("|", false)
			var rate_qtys := str(d.get("quantity_raw", need)).split("|", false)
			var produced_last: Dictionary = Production.last_turn_summary.get("produced", {})
			for index in rate_goods.size():
				var rg := _research_good_id(str(rate_goods[index]))
				if rg == "":
					continue
				var want_rate := need
				if rate_qtys.size() == rate_goods.size() and str(rate_qtys[index]).is_valid_int():
					want_rate = int(str(rate_qtys[index]))
				if int(produced_last.get(rg, 0)) >= want_rate:
					return true
			return false
		"Run Recipe Profitable":
			return _count_buildings_running_recipe_type(obj, 1, true) >= need
		"Run Recipe":
			# "Run N player buildings currently set to a recipe of this category"
			# (e.g. furnaces on a Glassmaking recipe). A leading int in Unit optionally
			# requires a minimum full-output run-streak.
			var recipe_streak := _leading_int(str(d.get("unit", "")), 0)
			return _count_buildings_running_recipe_type(obj, recipe_streak) >= need
		"Stockpile filled":
			# Just-in-Time Logistics: some tile's stockpile received goods from 3+
			# buildings for <qty> consecutive turns (streaks kept at output flush).
			return max_stockpile_feed_streak() >= need
		"Sustain":
			var threshold := _leading_int(obj, 0)
			return threshold == int(AdvisorState.ADVISOR_SLOT_PROFIT_5) \
				and AdvisorState._advisor_profit_streak >= need
		"Use Infrastructure":
			return _infrastructure_usage_met(d)
		"Firm Intermittency":
			return Production.firmed_intermittent_power() >= need
		"Run Multiple":
			return _run_multiple_buildings_met(d)
		"Fulfil Special Orders":
			return SpecialOrderState.fulfilled_count >= need
	return false


func _run_multiple_buildings_met(d: Dictionary) -> bool:
	var targets := str(d.get("object", "")).split("|", false)
	var quantities := str(d.get("quantity_raw", "")).split("|", false)
	var turns := _leading_int(str(d.get("unit", "")), 0)
	if targets.is_empty() or targets.size() != quantities.size() or turns <= 0:
		return false
	for index in targets.size():
		var count_text := str(quantities[index])
		if not count_text.is_valid_int() or _count_buildings(str(targets[index]), -1, false, turns) < int(count_text):
			return false
	return true


func _run_multiple_condition_text(d: Dictionary) -> String:
	var targets := str(d.get("object", "")).split("|", false)
	var quantities := str(d.get("quantity_raw", "")).split("|", false)
	var turns := _leading_int(str(d.get("unit", "")), 0)
	if targets.is_empty() or targets.size() != quantities.size() or turns <= 0:
		return ""
	var parts: Array[String] = []
	for index in targets.size():
		parts.append("%s %s" % [str(quantities[index]), _condition_building_label(str(targets[index]), int(quantities[index]))])
	return "Operate at least %s at full capacity for %d consecutive turns" % [MatchState._join_and(parts), turns]


func _condition_good_label(raw: String) -> String:
	var good: Dictionary = Catalog.get_good(_research_good_id(raw))
	return str(good.get("display_name", raw.capitalize()))

func _condition_building_label(raw: String, quantity: int = 1) -> String:
	var key := _research_key(raw)
	if key == "high_tech_manufactory|assembly_plant":
		return "High Tech Manufactories and/or Assembly Plants"
	if key == "any":
		return "buildings"
	var label: String = str({
		"high_tech_manufactory": "High Tech Manufactory",
		"assembly_plant": "Assembly Plant",
		"solar_farm": "Solar Farm",
		"farm": "Farm",
		"chem_plant": "Chemical Plant",
		"petro_refinery": "Petrochemical Refinery",
		"poly_plant": "Polymerisation Refinery",
		"desal": "Desalination Plant",
		"eaf": "Electric Arc Furnace",
	}.get(key, raw.capitalize()))
	if quantity != 1:
		if label.ends_with("y"):
			return "%sies" % label.left(label.length() - 1)
		return "%ss" % label
	return label


## Count player-owned infrastructure segments carrying at least 80% of their
## current capacity. Transport flow is the same per-tile metric surfaced by the
## infrastructure overlay; cables use actual draw/generation against their power cap.
## A segment set must sustain the target utilisation for the number of turns encoded
## after "for" in the Unit cell (normally "80% for 5 turns").
func _infrastructure_usage_met(d: Dictionary) -> bool:
	var title := str(d.get("title", ""))
	var need_segments := int(d.get("qty", 0))
	if title == "" or need_segments <= 0:
		return false
	var unit := str(d.get("unit", ""))
	var duration := 1
	if "for" in unit:
		duration = _leading_int(unit.get_slice("for", 1), 5)
	# "N% of L1 for T turns": an ABSOLUTE bar — N% of the LEVEL-1 capacity — so upgrading a
	# link never makes the gate harder, and 120%+ is reachable through congestion.
	# Plain "80% for T turns" keeps the legacy meaning: 80% of CURRENT capacity.
	var of_l1 := "of l1" in unit.to_lower()
	var bar_fraction := float(_leading_int(unit, 80)) / 100.0
	var turn := int(TurnManager.current_turn)
	# Conditions are evaluated from several hooks. Only advance/reset the streak
	# once per resolved turn, after the actual transport and power use has settled.
	if TurnManager.current_phase == TurnManager.Phase.NARRATIVE \
			and int(_infrastructure_usage_last_turn.get(title, -1)) != turn:
		_infrastructure_usage_last_turn[title] = turn
		var active_segments := 0
		var targets := _research_building_targets(str(d.get("object", "")))
		for inst in BuildingState.buildings.values():
			if not BuildingState.is_player_owned(inst) or not targets.has(_building_internal(inst)):
				continue
			var internal := _building_internal(inst)
			var tile_id := str(inst.get("tile_id", ""))
			var capacity := 0.0
			var usage := 0.0
			if internal == "cables":
				# L1 yardstick is the RAW table cap: throughput research must not move the bar.
				capacity = float(EconomyConfig.CABLE_POWER_CAP.get(1, 0)) if of_l1 else float(Power.tile_power_cap(tile_id))
				usage = float(maxi(int(Power.tile_drawn.get(tile_id, 0)), int(Power.tile_produced.get(tile_id, 0))))
			else:
				var mode := "rail" if internal == "rails" else internal
				capacity = float(TransportService.link_capacity(mode, 1)) if of_l1 else TransportState.tile_mode_capacity(mode, TransportState._tile_infra_level(tile_id, mode))
				usage = float(TransportState.tile_mode_flow(tile_id, mode))
			var bar := capacity * (bar_fraction if of_l1 else 0.80)
			if capacity > 0.0 and usage >= bar:
				active_segments += 1
		if active_segments >= need_segments:
			_infrastructure_usage_streaks[title] = int(_infrastructure_usage_streaks.get(title, 0)) + 1
		else:
			_infrastructure_usage_streaks[title] = 0
	return int(_infrastructure_usage_streaks.get(title, 0)) >= duration


func _research_key(value: String) -> String:
	var key := value.strip_edges().to_lower()
	for token in [" ", "-", "/", "."]:
		key = key.replace(token, "_")
	while "__" in key:
		key = key.replace("__", "_")
	return key.trim_prefix("_").trim_suffix("_")


func _research_building_targets(raw: String) -> Array:
	if "|" in raw:
		var combined: Array = []
		for part in raw.split("|", false):
			for target in _research_building_targets(str(part)):
				if not combined.has(target):
					combined.append(target)
		return combined
	var key := _research_key(raw)
	if key == "" or key == "any":
		return []
	var targets: Array = []
	if RESEARCH_BUILDING_ALIASES.has(key):
		for internal in RESEARCH_BUILDING_ALIASES[key]:
			if not targets.has(str(internal)):
				targets.append(str(internal))
	for building in Catalog.all_buildings():
		var internal := str(building.get("internal_name", ""))
		if key in [
			_research_key(str(building.get("id", ""))),
			_research_key(internal),
			_research_key(str(building.get("display_name", ""))),
		] and not targets.has(internal):
			targets.append(internal)
	return targets


func _research_good_id(raw: String) -> String:
	var key := _research_key(raw)
	var internal_alias := str(RESEARCH_GOOD_ALIASES.get(key, key))
	for good in Catalog.all_goods():
		if internal_alias in [
			_research_key(str(good.get("id", ""))),
			_research_key(str(good.get("internal_name", ""))),
			_research_key(str(good.get("display_name", ""))),
		]:
			return str(good.get("id", ""))
	return ""


## Land the player owns on SEA tiles that carry an oil deposit — the offshore drilling gate.
##
## Deliberately land UNITS on qualifying tiles, not a tile count: the point of the condition
## is that the player has committed real money to a specific offshore field, which is the
## thing offshore drilling is actually about. Seven tiles on the shipped map qualify, each
## with 200 capacity, so the 50 units the CSV asks for fit on any one of them.
func _owned_offshore_oil_land() -> int:
	var total := 0
	for tile_id in BuildingState.tile_land_owned:
		var tid := str(tile_id)
		var owned := int(BuildingState.tile_land_owned[tile_id])
		if owned <= 0 or not tid.begins_with("tile_"):
			continue
		if not Catalog.tile_type(tid) in ["sea", "deep_sea"]:
			continue
		if not "oil" in Catalog.tile_deposits_raw(tid).to_lower():
			continue
		total += owned
	return total

func _research_owned_land_units() -> int:
	var total := 0
	for tile_id in BuildingState.tile_land_owned:
		if str(tile_id).begins_with("tile_") and int(BuildingState.tile_land_owned[tile_id]) > 0:
			total += 1
	return total


## Dataset audit used by tests and diagnostics. Placeholder nodes deliberately
## carry no live condition; every other row should resolve to a live metric.
func research_condition_issues() -> Array:
	var issues: Array = []
	for d in _unlock_defs:
		var reason := _research_condition_issue(d)
		if reason != "":
			issues.append({
				"title": str(d.get("title", "")),
				"action": str(d.get("action", "")),
				"object": str(d.get("object", "")),
				"reason": reason,
			})
	return issues


func _research_condition_issue(d: Dictionary) -> String:
	var action := str(d.get("action", ""))
	var obj := str(d.get("object", ""))
	if action == "Placeholder":
		return ""
	if action == "All Of":
		# Every ";"-separated clause must itself pass the audit.
		var all_clauses := obj.split(";", false)
		if all_clauses.is_empty():
			return "empty All Of condition"
		for spec in all_clauses:
			var sub := _parse_sub_condition(str(spec))
			if sub.is_empty():
				return "malformed All Of clause"
			var sub_issue := _research_condition_issue(sub)
			if sub_issue != "":
				return sub_issue
		return ""
	if action == "Ship Multimodal":
		return "" if _research_key(obj) == "freight" else "unsupported multimodal target"
	if action == "Produce Per Turn":
		return "" if _research_good_id(obj) != "" else "unknown good target"
	if action == "Produce Per Turn Any":
		var rate_goods := obj.split("|", false)
		if rate_goods.is_empty():
			return "invalid multi-good production condition"
		for g in rate_goods:
			if _research_good_id(str(g)) == "":
				return "unknown good target"
		return ""
	if action == "Own All":
		# "a|b" building types — every one must resolve.
		var own_all_targets := obj.split("|", false)
		if own_all_targets.is_empty():
			return "invalid multi-building ownership condition"
		for t in own_all_targets:
			if _research_building_targets(str(t)).is_empty():
				return "unknown ownership target"
		return ""
	if action == "Run Producing":
		return "" if _research_good_id(obj) != "" else "unknown good target"
	if action in ["Build", "Run", "Run Profitable", "Run L1", "Run Profitable L2", "Run Multiple", "Use Infrastructure", "Run Same Tile", "Own On Tiles", "Run Distinct Recipes", "Run Profitable L1"]:
		if _research_key(obj) != "any" and _research_building_targets(obj).is_empty():
			return "unknown building target"
		return ""
	if action == "Fulfil Special Orders":
		return "" if _research_key(obj) == "special_order" else "unsupported special-order target"
	if action == "Own":
		if _research_key(obj) == "offshore_oil_land":
			return ""
		if _research_key(obj) != "land" and _research_building_targets(obj).is_empty():
			return "unknown ownership target"
		return ""
	if action == "Purchase Ports":
		return "" if _research_key(obj) == "ports" else "unsupported port ownership target"
	if action == "Sell Through Ports":
		return "" if _research_key(obj) == "ports" else "unsupported port-sale target"
	if action == "Sell Through Every Port" or action == "Own Port At Level":
		return "" if _research_key(obj) == "ports" else "unsupported port target"
	if action == "Sell Through Ports Classes":
		var classes := obj.split("|", false)
		if classes.is_empty():
			return "missing port transport classes"
		for transport_kind in classes:
			if not ["solid_light", "solid_heavy", "ultra_heavy", "safe_liquid", "hazard_liquid", "gas"].has(str(transport_kind)):
				return "unsupported port transport class"
		return ""
	if action == "Produce All":
		var goods := obj.split("|", false)
		var quantities := str(d.get("quantity_raw", "")).split("|", false)
		if goods.is_empty() or goods.size() != quantities.size():
			return "invalid multi-good production condition"
		for index in goods.size():
			if _research_good_id(str(goods[index])) == "" or not str(quantities[index]).is_valid_int():
				return "unknown good target"
		return ""
	if action == "Produce Any":
		# OR list "a|b": every listed good must resolve. A single Quantity applies to all;
		# a per-good "a|b" Quantity must be all-integer.
		var any_goods := obj.split("|", false)
		if any_goods.is_empty():
			return "invalid multi-good production condition"
		var any_qtys := str(d.get("quantity_raw", "")).split("|", false)
		var per_good := any_qtys.size() == any_goods.size()
		for index in any_goods.size():
			if _research_good_id(str(any_goods[index])) == "":
				return "unknown good target"
			if per_good and not str(any_qtys[index]).is_valid_int():
				return "unknown good target"
		return ""
	if action in ["Produce", "Sell"]:
		if action == "Sell" and _research_key(obj) == "freight":
			return ""
		if _research_good_id(obj) == "":
			return "unknown good target"
		return ""
	if action in ["Run Recipe", "Run Recipe Profitable"]:
		var wanted := _research_key(obj)
		for recipe in Catalog.all_recipes():
			if _research_key(str(recipe.get("recipe_type", ""))) == wanted:
				return ""
		return "unknown recipe type"
	if action == "Survey":
		return "" if _research_key(obj) in ["tiles", "deposits"] else "unknown survey target"
	if action == "Stockpile filled":
		return ""
	if action == "Firm Intermittency":
		return "" if _research_key(obj) == "power" else "unsupported intermittency target"
	if action == "Sustain":
		return "" if _leading_int(obj, 0) == int(AdvisorState.ADVISOR_SLOT_PROFIT_5) \
			else "unsupported sustain threshold"
	return "unsupported action"

# Count player-owned buildings resolved from an ID/internal/display/concept name,
# optionally filtered by level (-1 = any), profitability, and a minimum consecutive
# run-streak. `internal` == "any" (or "") matches every non-infrastructure building.
## Largest number of player buildings of `internal` sharing ONE tile, counting only those
## that (when `min_streak` > 0) have sustained full output for that many consecutive turns.
## Backs the "Run Same Tile" verb — co-location is the ask, not fleet size.
func _max_same_tile_count(internal: String, min_streak: int) -> int:
	var any_type: bool = _research_key(internal) == "any" or internal == ""
	var targets := _research_building_targets(internal)
	var per_tile: Dictionary = {}
	for inst in BuildingState.buildings.values():
		if not BuildingState.is_player_owned(inst):
			continue
		if any_type:
			if str(Catalog.get_building(str(inst.get("building_id", ""))).get("category", "")) == "infrastructure":
				continue   # "any" means production buildings, as in _count_buildings
		elif not targets.has(_building_internal(inst)):
			continue
		if min_streak > 0 and int(Production.full_output_streak_by_building.get(str(inst.get("instance_id", "")), 0)) < min_streak:
			continue
		var t := str(inst.get("tile_id", ""))
		per_tile[t] = int(per_tile.get(t, 0)) + 1
	var best := 0
	for t in per_tile:
		best = maxi(best, int(per_tile[t]))
	return best

## Last resolved turn's freight, by transport mode, from the same shipment snapshot the
## congestion model uses (_last_transit_shipments). Each shipment's units count once per
## mode it travels by — no inflation by route length. Leg-less overland moves count as
## "overland". Backs "Ship Multimodal": {"total": units, "modes": {mode: units}}.
func _multimodal_freight_last_turn() -> Dictionary:
	var by_mode: Dictionary = {}
	var total := 0
	for s in TransportState._last_transit_shipments:
		var units := TransportState._shipment_total_units(s as Dictionary)
		if units <= 0:
			continue
		var modes: Dictionary = {}
		for leg in (s as Dictionary).get("legs", []):
			var mode := str((leg as Dictionary).get("mode", ""))
			if mode != "":
				modes[mode] = true
		if modes.is_empty():
			modes["overland"] = true
		for mode in modes:
			by_mode[mode] = int(by_mode.get(mode, 0)) + units
		total += units
	return {"total": total, "modes": by_mode}

## One "Action|Object|Qty|Unit" clause of an "All Of" condition, as the condition dict the
## live check, the audit and the card text consume. Empty when malformed. (Clauses whose own
## Object needs "|" — Produce All, Own All — can't nest here; none do.)
func _parse_sub_condition(spec: String) -> Dictionary:
	# Action | Object… | Qty | Unit — the LAST two fields are qty and unit, so an Object that
	# itself carries "|" (an a|b good list for the *Any / *All verbs) survives inside a clause.
	var parts := spec.split("|", false)
	if parts.size() < 4:
		return {}
	var q := str(parts[parts.size() - 2]).strip_edges()
	var object_parts: Array = []
	for i in range(1, parts.size() - 2):
		object_parts.append(str(parts[i]).strip_edges())
	return {
		"action": str(parts[0]).strip_edges(), "object": "|".join(PackedStringArray(object_parts)),
		"qty": int(q) if q.is_valid_int() else _leading_int(q, 0), "quantity_raw": q,
		"unit": str(parts[parts.size() - 1]).strip_edges(),
	}

## Card text for one All Of clause — the verbs that actually appear in compound gates.
func _sub_condition_text(sub: Dictionary) -> String:
	var a := str(sub.get("action", "")); var o := str(sub.get("object", "")); var n := int(sub.get("qty", 0)); var u := str(sub.get("unit", ""))
	var turns := _leading_int(u, 0)
	match a:
		"Produce": return "produce %d %s" % [n, _condition_good_label(o)]
		"Produce Per Turn Any":
			var choices: Array = []
			for good in o.split("|", false):
				choices.append("%d %s" % [n, _condition_good_label(str(good))])
			return "produce %s in one turn" % MatchState._join_or(choices)
		"Own On Tiles": return "own %s on at least %d different tiles" % [_condition_building_label(o, 2), n]
		"Own": return "own %d %s" % [n, _condition_building_label(o, n)]
		"Run": return "operate %d %s at full capacity for %d turns" % [n, _condition_building_label(o, n), turns] if turns > 0 else "operate a %s at full capacity for %d turns" % [_condition_building_label(o, 1), n]
		"Run Profitable": return "operate %d %s profitably" % [n, _condition_building_label(o, n)]
		"Run Producing": return "operate %s making %s at full capacity for %d turns" % ["a building" if n <= 1 else "%d buildings" % n, _condition_good_label(o), turns]
	return "%s %s %d %s" % [a, o, n, u]

## Number of DIFFERENT recipes currently running (full-output streak >= 1) across the
## player's buildings of `internal`. Backs "Run Distinct Recipes" — breadth of process.
func _distinct_recipes_running(internal: String) -> int:
	var targets := _research_building_targets(internal)
	var recipes: Dictionary = {}
	for inst in BuildingState.buildings.values():
		if not BuildingState.is_player_owned(inst) or not targets.has(_building_internal(inst)):
			continue
		if int(Production.full_output_streak_by_building.get(str(inst.get("instance_id", "")), 0)) < 1:
			continue
		var rid := str(inst.get("recipe_id", ""))
		if rid != "":
			recipes[rid] = true
	return recipes.size()

## Player buildings whose CURRENT recipe outputs `good_id`, at full output for at least
## `min_streak` consecutive turns. Backs "Run Producing" — matched by output good, so a
## condition like "make chlorine" spans recipes that live in different categories.
func _count_running_producing(good_id: String, min_streak: int) -> int:
	if good_id == "":
		return 0
	var n := 0
	for inst in BuildingState.buildings.values():
		if not BuildingState.is_player_owned(inst):
			continue
		var recipe: Dictionary = Catalog.get_recipe(str(inst.get("recipe_id", "")))
		if recipe.is_empty() or not Catalog.recipe_produces(recipe, good_id):
			continue
		if int(Production.full_output_streak_by_building.get(str(inst.get("instance_id", "")), 0)) < maxi(min_streak, 1):
			continue
		n += 1
	return n

## Number of distinct tiles carrying at least one player building of `internal`.
## Backs the "Own On Tiles" verb — geographic reach, not building count.
func _tiles_with_building(internal: String) -> int:
	var any_type: bool = _research_key(internal) == "any" or internal == ""
	var targets := _research_building_targets(internal)
	var tiles: Dictionary = {}
	for inst in BuildingState.buildings.values():
		if not BuildingState.is_player_owned(inst):
			continue
		if any_type:
			if str(Catalog.get_building(str(inst.get("building_id", ""))).get("category", "")) == "infrastructure":
				continue   # "any" means production buildings, as in _count_buildings
		elif not targets.has(_building_internal(inst)):
			continue
		tiles[str(inst.get("tile_id", ""))] = true
	return tiles.size()

func _count_buildings(internal: String, level: int, require_profitable: bool, min_streak: int) -> int:
	var match_any: bool = _research_key(internal) == "any" or internal == ""
	var targets := _research_building_targets(internal)
	var n := 0
	for inst in BuildingState.buildings.values():
		if not BuildingState.is_player_owned(inst):
			continue
		if match_any and str(Catalog.get_building(str(inst.get("building_id", ""))).get("category", "")) == "infrastructure":
			continue   # "build N buildings" (any-type scale unlocks) ignores infrastructure
		if not match_any and not targets.has(_building_internal(inst)):
			continue
		if level >= 0 and _building_level(inst) != level:
			continue
		var streaks: Dictionary = _profitable_run_streaks if require_profitable else Production.full_output_streak_by_building
		if min_streak > 0 and int(streaks.get(str(inst.get("instance_id", "")), 0)) < min_streak:
			continue
		if require_profitable and not _is_building_profitable(inst):
			continue
		n += 1
	return n

# Count player-owned buildings whose CURRENTLY-ASSIGNED recipe has recipe_type ==
# `recipe_type` (case-insensitive), optionally requiring a minimum full-output
# run-streak. Powers recipe-specific research gates (e.g. "run furnaces on a
# Glassmaking recipe"). Because glassmaking recipes only exist in the furnace,
# matching recipe_type already means "a furnace running glassmaking".
func _count_buildings_running_recipe_type(recipe_type: String, min_streak: int, require_profitable: bool = false) -> int:
	var want := recipe_type.strip_edges().to_lower()
	if want == "":
		return 0
	var n := 0
	for inst in BuildingState.buildings.values():
		if not BuildingState.is_player_owned(inst):
			continue
		var recipe: Dictionary = Catalog.get_recipe(str(inst.get("recipe_id", "")))
		if recipe.is_empty():
			continue
		if str(recipe.get("recipe_type", "")).strip_edges().to_lower() != want:
			continue
		if min_streak > 0 and int(Production.full_output_streak_by_building.get(str(inst.get("instance_id", "")), 0)) < min_streak:
			continue
		if require_profitable and (BuildingWorks.is_building_paused(str(inst.get("instance_id", ""))) or not _is_building_profitable(inst)):
			continue
		n += 1
	return n

func _building_internal(inst: Dictionary) -> String:
	return str(Catalog.get_building(str(inst.get("building_id", ""))).get("internal_name", ""))

# Imported legacy buildings may lack a level; treat those as Level 1. Player-built
# and upgraded instances carry their actual level in the live state.
func _building_level(inst: Dictionary) -> int:
	return int(inst.get("level", 1))

# Profitable = the building's modelled cost per unit is below the market price of
# what it makes. Needs a fresh CostSolver pass; returns false if cost is unknown.
func _is_building_profitable(inst: Dictionary) -> bool:
	var iid := str(inst.get("instance_id", ""))
	if iid == "":
		return false
	var uc: float = CostSolver.get_building_unit_cost(iid)
	if uc < 0.0:
		return false
	var bd: Dictionary = CostSolver.last_result.get("per_building", {}).get(iid, {})
	var good_id: String = str(bd.get("output_good_id", ""))
	if good_id == "":
		return false
	var price: float = MarketState.get_price(good_id)
	return price > 0.0 and uc < price


func _update_profitable_run_streaks() -> void:
	var next: Dictionary = {}
	for inst in BuildingState.buildings.values():
		if not BuildingState.is_player_owned(inst):
			continue
		var iid := str(inst.get("instance_id", ""))
		if iid == "" or int(Production.full_output_streak_by_building.get(iid, 0)) <= 0:
			continue
		if _is_building_profitable(inst):
			next[iid] = int(_profitable_run_streaks.get(iid, 0)) + 1
	_profitable_run_streaks = next

# Leading integer of a string like "20 turns" -> 20; falls back to `default`.
func _leading_int(s: String, default_val: int) -> int:
	var digits := ""
	for ch in s.strip_edges():
		if ch >= "0" and ch <= "9":
			digits += ch
		elif digits != "":
			break
	return int(digits) if digits != "" else default_val
