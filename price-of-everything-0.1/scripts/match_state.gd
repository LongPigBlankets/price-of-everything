extends Node
const BuildingLevels := preload("res://scripts/building_levels.gd")
const BuildingPrice := preload("res://scripts/building_price.gd")

# MatchState: the canonical store for everything that changes during a match.
# Other systems read and write here; never store match data elsewhere.

# --- Player resources ---
const LOCAL_PLAYER := "player_1"
var money: float = 1000.0  # was: int = 1000

# Three legacy/prototype buildings are deliberately absent from normal matches.
# `unlock hidden_buildings` is an explicit development cheat for testing them.
const HIDDEN_BUILDING_IDS := {"b_029": true, "b_030": true, "b_031": true, "b_035": true}
var hidden_buildings_unlocked: bool = false

# Recycling is off the table for the demo: the waste chain is a whole
# second economy — collect it, sort it, feed it back — and a 100-turn demo has no room to
# teach it. `unlock recycling` in the debug terminal puts it back for development.
const RECYCLING_BUILDING_IDS := {"b_022": true, "b_036": true}
# Waste Water, Scrap Metal, Bio Waste, Electronic Waste — the goods that only exist to be
# recycled. Hidden alongside the plants, or the encyclopedia advertises a chain with no
# building that can process it.
const RECYCLING_GOOD_IDS := {"g_063": true, "g_067": true, "g_073": true, "g_074": true}
var recycling_unlocked: bool = false


# --- Ruleset ---
# Which rule variant this match plays under. Carried in saves and start configs so
# future rule changes (scoring, brakes, era pacing, …) can key off it; only "name"
# is defined today — add per-rule keys beside it as rules become real.
const DEFAULT_RULESET := {"name": "standard"}
var ruleset: Dictionary = DEFAULT_RULESET.duplicate(true)
## Which start config this match began from ("metal_magnate", "tutorial", …). Telemetry's
## primary segmentation field; empty for matches built without a start config (tests).
## Unlike ruleset.name this is NOT reset by state_reset mid-teardown, so it stays readable.
var scenario_name: String = ""
## Sticky once any debug command moves the sim. Telemetry reports it so cheat runs can be
## excluded from aggregates instead of silently poisoning them.
var cheats_used: bool = false


# --- Match RNG (the one seeded RNG threaded through the sim; state is saved) ---
const DEFAULT_MATCH_RNG_SEED := 5060301
var _match_rng := RandomNumberGenerator.new()
var match_rng_seed: int = DEFAULT_MATCH_RNG_SEED   # seeded match RNG (draws + tile reveal)

var fake_money_this_turn: float = 0.0              # cheat-added cash this turn ("fake money")

# --- Output routing ---
var output_stockpile_destinations: Dictionary = {}  # instance_id -> {tile_id, good_id}
# Optional split routes. Shape: instance_id -> {good_id -> [{tile_id, qty}]}. A
# qty of 0 means "automatic equal share"; otherwise it is the units per turn sent
# to that tile. Kept separate from the legacy single-route map for save compatibility.
var output_split_destinations: Dictionary = {}
var output_special_order_destinations: Dictionary = {}  # instance_id -> {good_id -> special_order_id}
const MARKET_DESTINATION := "__market__"  # sentinel tile_id: route this building's output to market
# Per-good SHIPPING CAP for an explicit tile route (the CTRL+click "send a specific
# amount every turn" flow): only min(cap, produced) ships to the destination each
# turn; the remainder stays in the origin tile's stockpile. 0 / absent = ship all.
var output_ship_quantities: Dictionary = {}  # instance_id -> {good_id -> int}
var input_tile_only: Dictionary = {}  # "instance_id|good_id" -> true (tile stockpile ONLY; default buys from market)
var pending_output_stockpile_selection: Dictionary = {}
var queued_stockpile_market_sales: Dictionary = {}  # tile_id -> true
var sell_surplus_tiles: Dictionary = {}              # tile_id -> true (master: auto-sell ALL surplus goods)
var auto_sell_goods: Dictionary = {}                 # tile_id -> { good_id -> true } (per-good auto-sell overrides)
var auto_sell_keep: Dictionary = {}                  # tile_id -> { good_id -> units always left on the tile ("sell all except X") }
const IMPACT_ANY := -1                               # auto-sell tolerance sentinel: no per-turn volume cap
var auto_sell_impact: Dictionary = {}                # tile_id -> max price-impact % tolerated per turn (or IMPACT_ANY)

# Realised market sales per source tile THIS TURN: tile_id -> {units, revenue}.
# Reset at the start of each turn's processing so the figure is per-turn, not
# accumulated.
var sales_by_tile: Dictionary = {}
var recurring_sells: Array = []   # [{source, goods}] re-sold to the nearest port every turn
var recurring_bulk_sells: Array = []  # [{params, turn_started}] re-run via sell_all_to_market every turn
var recurring_buys: Array = []  # [{dest, good, qty}] re-bought from market every turn
# View-only ledgers for the Transactions / Movements tabs (one-off entries; recurring
# rules are read from the recurring_* arrays). Rows: {good_id, qty, tile_from, tile_to,
# turn_started, turn_ended} (+ kind for transactions).
var transaction_log: Array = []
const LEDGER_MAX := 500  # keep the newest N entries so the logs stay bounded

# Survey state: the set of tiles the player has surveyed (tile_id -> true).
# Dynamic; seeded with the port tiles at match start (see seed_surveyed_ports).
# A tile not in this set reads as "unsurveyed", except urban tiles and tiles in
# partially_surveyed_tiles, which read as "partially surveyed" until fully surveyed.
var surveyed_tiles: Dictionary = {}
var partially_surveyed_tiles: Dictionary = {}   # tile_id -> true (auto-revealed nearby)
var surveying_in_progress: Dictionary = {}      # tile_id -> turns remaining (>0)
var surveying_reveal: Dictionary = {}           # tile_id -> bool (auto-reveal a neighbour on completion)
const SURVEY_TURNS := 2                          # surveying a tile takes 2 turns
# Temporary-deposit depletion: remaining yield per tile per deposit token (e.g.
# tile_5_3 -> {"coal": 480}). Seeded from the CSV "(amount)" on each deposit;
# water never depletes so it is never tracked. Reaching 0 means the deposit is gone.
var deposit_remaining: Dictionary = {}
var _deposit_terrain = null  # HexMap, for counting a tile's deposits when surveyed
# Single deposits revealed by building a mine on an unsurveyed tile: existence is
# known but the size stays hidden and the tile remains "unsurveyed".
var revealed_deposits: Dictionary = {}  # tile_id -> {token: true}

# Survey range: how many tiles out from a surveyed tile you may survey. The red
# limit line and the click check both use it; +1 once Geoscanning is unlocked.
const SURVEY_RANGE_BASE := 2
var _surveyable_cache: Dictionary = {}
var _surveyable_dirty := true

enum SellMode { SELL_ALL, STOCKPILE_ALL, BUILDING_BY_BUILDING }
var sell_mode: int = SellMode.STOCKPILE_ALL

# How the transport router picks a path between two tiles. FASTEST by default.
enum RouteObjective { FASTEST, CHEAPEST, BLENDED }
var route_objective: int = RouteObjective.FASTEST


# When true (the default), building clicks open the redesigned Building Detail v2
# panel. The classic v1 panel is kept as a fallback behind a dev toggle.
# Session-only; never persisted. See docs/building-detail-v2-plan.md.


var construct_start_half_capacity: bool = false
## When on, confirming a build on a tile the player has too little land for buys exactly
## enough land patches to cover the shortfall first (see world_map._space_check_for_build).
var construct_auto_buy_land: bool = true
## Last public-road expansion batch applied; persisted so loading cannot repeat a batch.
var public_roads_last_turn: int = 0
# Defaults captured by constructions when they are started. "ask" preserves the
# existing delivery prompt; the other modes choose a source automatically.
var construct_material_source: String = "market"
## A one-build override picked from the confirm panel's materials accordion (which retired the old
## "construction materials missing" modal). NOT saved: it applies to the next build attempt only and
## clears once consumed. Empty = fall back to the standing construct_material_source setting.
var pending_build_material_source: String = ""
# New production defaults to market routing unless the player explicitly chooses
# the building's own tile stockpile.
var construct_output_destination: String = "market"
# Power supply priority: "self" (this category's generation covers
# local building demand before anything sells) or "grid" (this category's
# generation always sells; local demand for it is bought from the grid instead).
# Defaults avoid exposing buildings to intermittency: coal/gas (steady) self-
# serves, wind/solar (intermittent) sells and buys firm grid power instead. A
# match setting, read live every turn by Production/Power — applies to every
# power_plant/wind/solar building that exists AND any built after the player
# changes it, not captured per-instance at construction (contrast
# construct_material_source above, which IS captured per-construction).
var power_priority_coal_gas: String = "self"
var power_priority_wind_solar: String = "grid"

# --- Signals ---
signal money_changed(new_amount: float) 
signal state_reset
## A goods movement was committed this turn (Victory-track feed). `kind` is
## "buy" | "move" | "sale"; `category` is the buy bucket ("input" | "building" |
## "upgrade" | "other"; "" for moves/sales); `transport_turns` is the delivery
## delay (0 = instant). Fires once per queue_buy / queue_move / MarketState.execute_sale,
## including 0-turn instant deliveries. Drives Logistics efficiency + Autarkic streak.
signal goods_movement_recorded(kind: String, category: String, transport_turns: int)
signal sell_mode_changed(new_mode: int)
signal route_objective_changed(new_objective: int)
signal toast_requested(message: String, toast_type: String)
## A market sale was finalised at a port this turn (drives the £-rise effect).
signal market_sale_arrived_at_port(port_tile_id: String, revenue: float)
## A build was rejected for lack of funds (drives the error toast + money flash).
signal build_rejected_no_funds(message: String)
## Purchases tab asked the player to pick a delivery tile on the map.
signal buy_tile_pick_requested()
signal buy_tile_picked(tile_id: String)  # tile_id == "" means cancelled
## Market row "Expand" — open the construct panel filtered to producers of this good.
signal show_construct_for_good(good_id: String)
## Tile-view "Buy Buildings" — open the Market on the Buildings tab, filtered to this tile.
signal buildings_market_for_tile_requested(tile_id: String)
## Market row "Move" — start the on-map transfer flow for this good.
signal transfer_for_good_requested(good_id: String)
## Market-row "Purchase" asked to open the per-good buy flow.
signal purchase_for_good_requested(good_id: String)
## A UI element asked to open an Encyclopedia entry (e.g. a "More info" link).
signal encyclopedia_entry_requested(entry_id: String)
## A UI element (top-bar module, Resources-panel button) asked to toggle the
## full-screen Goods Graph view (scripts/goods_graph_view.gd).
signal goods_graph_requested
## A bottom-menu control asked to toggle the full-screen Empire View
## (scripts/empire_view.gd).
signal empire_view_requested
## The Goods Graph's expanded card asked for a good's Encyclopedia entry.
signal encyclopedia_good_requested(good_id: String)
## A good icon anywhere in the UI was clicked: open the Goods Graph focused on it, so a
## good the player is reading about is one click from how it is made and what it feeds.
signal goods_graph_good_requested(good_id: String)
## A UI element (e.g. the tile-view intermittency "see more" link) asked to open the
## building ledger pre-filtered to a single filter key (e.g. "green_intermittent").
signal building_ledger_filter_requested(filter_key: String)
## A research REQUIREMENT shown somewhere else in the UI was clicked — the tech gating a
## building upgrade, for instance. Opens the Research panel with its search box already
## holding that title, so the player lands on the node rather than on the whole tree.
signal research_search_requested(query: String)
signal output_stockpile_selection_started(selection: Dictionary)
signal output_stockpile_selection_cancelled
signal output_stockpile_destination_changed(instance_id: String, tile_id: String, good_id: String)
signal stockpile_market_sale_queue_changed(tile_id: String)
signal stockpile_market_sale_completed(sale_record: Dictionary)
signal sell_surplus_changed(tile_id: String)
## A standing recurring move / sell / bulk-sell was added or cancelled — the Market
## panel's Movements/Sales lists refresh on this.
signal recurring_orders_changed
## The set of surveyed tiles changed (drives the Surveying mapmode + tile panel).
signal surveyed_tiles_changed
## A tile's in-progress survey changed (started / ticked down / finished).
signal surveying_in_progress_changed
## A tile's deposit remaining amount changed (depleted by mining).
signal deposits_changed(tile_id: String)
## A tile's deposit just reached 0 this turn (fires once, on the 0 transition).
signal deposit_exhausted(tile_id: String, token: String)
signal hidden_buildings_enabled
## A tile finished being surveyed (drives the on-map survey animation). deposit_goods
## is an array of {good_id, internal_name} for the non-water deposits revealed.
signal tile_survey_completed(tile_id: String, deposit_goods: Array)
signal construct_settings_changed
signal power_priority_changed
## A UI surface (notification deep-link, etc.) asks the map to focus a tile:
## centre the camera on it and open its tile panel. world_map handles it.
signal focus_tile_requested(tile_id: String)
## Like focus_tile_requested, but opens the building detail panel for a specific
## building instance (centring the camera on its tile). Used by starvation
## notifications' "Go to".
signal focus_building_requested(instance_id: String)
## The top bar's Transport module asks world_map to open the logistics panel.
signal transport_panel_requested
## A transport-panel stockpile row asks the map to open that tile's Stockpile tab.
signal tile_stockpile_requested(tile_id: String)

# --- Initialization ---
func _ready() -> void:
	money = EconomyConfig.STARTING_MONEY
	money_changed.emit(money)


func _on_survey_phase_started(phase: int) -> void:
	if phase == TurnManager.Phase.PROCESS:
		tick_surveys()
		Power.tick_battery_fills()
# --- Public API: money ---
func add_money(delta: float) -> void:
	money += delta
	money_changed.emit(money)

func deduct_money(amount: float) -> bool:  # was: int
	if money < amount:
		return false
	money -= amount
	money_changed.emit(money)
	return true

# --- CFO tax-loss carry-forward (money) ---
# CFO tax-loss carry-forward: while a CFO is seated, a losing turn banks a credit worth
# CFO_TAX_CREDIT_RATE of that turn's revenue, usable to reduce the tax bill over the next
# CFO_TAX_CREDIT_TURNS turns. Each entry is {amount: float, turns_left: int}.
const CFO_TAX_CREDIT_RATE := 0.05
const CFO_TAX_CREDIT_TURNS := 5
var cfo_tax_credit_pool: Array = []                # [{amount, turns_left}] oldest first
var cfo_tax_credit_intro_shown: bool = false       # the one-time CFO explainer has fired
signal cfo_tax_credit_filed(amount: float)         # fired once, when the FIRST credit is banked

# ── CFO tax-loss carry-forward ───────────────────────────────────────────────
func cfo_seated() -> bool:
	return AdvisorState.get_advisor_in_seat("cfo") != ""

# Bank a credit worth 5% of the turn's revenue on a losing turn. Fires the one-time
# explainer signal the first time. Returns the amount banked.
func cfo_bank_tax_credit(revenue: float) -> float:
	var amount := maxf(0.0, revenue) * CFO_TAX_CREDIT_RATE
	if amount < 0.01:
		return 0.0
	cfo_tax_credit_pool.append({"amount": amount, "turns_left": CFO_TAX_CREDIT_TURNS})
	if not cfo_tax_credit_intro_shown:
		cfo_tax_credit_intro_shown = true
		cfo_tax_credit_filed.emit(amount)
	return amount

# Consume banked credits (oldest first) to offset a tax bill. Returns the amount applied.
func cfo_apply_tax_credit(tax: float) -> float:
	if tax <= 0.0 or cfo_tax_credit_pool.is_empty():
		return 0.0
	var remaining := tax
	var applied := 0.0
	for entry in cfo_tax_credit_pool:
		if remaining <= 0.0:
			break
		var take := minf(float(entry.get("amount", 0.0)), remaining)
		entry["amount"] = float(entry.get("amount", 0.0)) - take
		applied += take
		remaining -= take
	_prune_tax_credits()
	return applied

# Tick every banked credit's 5-turn window down by one; drop the exhausted/expired.
func cfo_age_tax_credits() -> void:
	for entry in cfo_tax_credit_pool:
		entry["turns_left"] = int(entry.get("turns_left", 0)) - 1
	_prune_tax_credits()

func cfo_tax_credit_available() -> float:
	var total := 0.0
	for entry in cfo_tax_credit_pool:
		total += float(entry.get("amount", 0.0))
	return total

func _prune_tax_credits() -> void:
	var kept: Array = []
	for entry in cfo_tax_credit_pool:
		if int(entry.get("turns_left", 0)) > 0 and float(entry.get("amount", 0.0)) > 0.005:
			kept.append(entry)
	cfo_tax_credit_pool = kept


# --- Public API: survey state ---
## Seed the surveyed set with the NPC port tiles (called once at match start).
func seed_surveyed_ports() -> void:
	for port in Catalog.all_ports():
		var tile_id := str(port.get("tile_id", ""))
		if tile_id != "":
			surveyed_tiles[tile_id] = true
	_surveyable_dirty = true
	surveyed_tiles_changed.emit()

## Mark a batch of tiles surveyed in one shot (one signal emit). Used by the
## "All tiles surveyed at game start" Advanced Setting at world build.
func mark_tiles_surveyed(tile_ids: Array) -> void:
	var changed := false
	for tid in tile_ids:
		var s := str(tid)
		if s != "" and not surveyed_tiles.has(s):
			surveyed_tiles[s] = true
			changed = true
	if changed:
		_surveyable_dirty = true
		surveyed_tiles_changed.emit()

func is_tile_surveyed(tile_id: String) -> bool:
	return surveyed_tiles.has(tile_id)

## Mark a tile fully surveyed (no-op if already surveyed).
func mark_tile_surveyed(tile_id: String) -> void:
	if tile_id == "" or surveyed_tiles.has(tile_id):
		return
	surveyed_tiles[tile_id] = true
	_surveyable_dirty = true
	surveyed_tiles_changed.emit()

## Survey status for a tile: "surveyed", "partial", or "unsurveyed". Urban tiles
## (and tiles auto-revealed by a nearby survey) read as partially surveyed until
## fully surveyed; pass the tile's type so this needs no tile-data lookup.
func survey_status(tile_id: String, tile_type: String = "") -> String:
	if surveyed_tiles.has(tile_id):
		return "surveyed"
	if partially_surveyed_tiles.has(tile_id) or tile_type.strip_edges().to_lower() == "urban":
		return "partial"
	return "unsurveyed"

func is_survey_in_progress(tile_id: String) -> bool:
	return surveying_in_progress.has(tile_id)

func survey_turns_left(tile_id: String) -> int:
	return int(surveying_in_progress.get(tile_id, 0))

## Begin a 2-turn survey of a tile (cost is charged by the caller). reveal_nearby
## auto-(partially-)surveys one neighbour on completion — true for a full survey of
## an unsurveyed tile, false when just finishing a partially surveyed tile.
func begin_survey(tile_id: String, reveal_nearby: bool = true) -> void:
	if tile_id == "" or surveyed_tiles.has(tile_id) or surveying_in_progress.has(tile_id):
		return
	surveying_in_progress[tile_id] = SURVEY_TURNS
	surveying_reveal[tile_id] = reveal_nearby
	surveying_in_progress_changed.emit()

## Mark a tile partially surveyed (auto-revealed by a nearby survey).
func mark_tile_partial(tile_id: String) -> void:
	if tile_id == "" or surveyed_tiles.has(tile_id) or partially_surveyed_tiles.has(tile_id):
		return
	partially_surveyed_tiles[tile_id] = true
	surveyed_tiles_changed.emit()

## Tick every in-progress survey down by one turn; complete any that hit zero.
## Called once per turn during the PROCESS phase.
func tick_surveys() -> void:
	if surveying_in_progress.is_empty():
		return
	var done: Array = []
	for tile_id in surveying_in_progress:
		surveying_in_progress[tile_id] = int(surveying_in_progress[tile_id]) - 1
		if int(surveying_in_progress[tile_id]) <= 0:
			done.append(tile_id)
	for tile_id in done:
		var reveal: bool = bool(surveying_reveal.get(tile_id, true))
		surveying_in_progress.erase(tile_id)
		surveying_reveal.erase(tile_id)
		_complete_survey(tile_id, reveal)
	surveying_in_progress_changed.emit()

func _complete_survey(tile_id: String, reveal_nearby: bool) -> void:
	partially_surveyed_tiles.erase(tile_id)
	mark_tile_surveyed(tile_id)
	# Surveying a tile counts toward the research conditions (tiles + deposits found,
	# pure water excluded) and drives the on-map survey animation.
	var found: Array = _tile_deposit_goods(tile_id)
	ResearchState.record_unlock_progress("Survey", "tiles", 1)
	ResearchState.record_unlock_progress("Survey", "deposits", found.size())
	tile_survey_completed.emit(tile_id, found)
	request_toast(_survey_toast(tile_id, found), "info")
	if not reveal_nearby:
		return
	# A full survey auto-(partially-)surveys a neighbour; Hyperspectral Remote Sensing
	# reveals one extra ("+1 adjacent tile revealed when surveying").
	var reveals := 2 if ResearchState.is_unlocked("Hyperspectral Remote Sensing") else 1
	for _i in reveals:
		var fresh: Array = []
		for n in Catalog.tile_neighbours(tile_id):
			if not surveyed_tiles.has(n) and not partially_surveyed_tiles.has(n) and not surveying_in_progress.has(n):
				fresh.append(n)
		if fresh.is_empty():
			break
		mark_tile_partial(str(fresh[_match_rng_int(fresh.size())]))

# --- Public API: depletable deposits ---
## Seed each tile's depletable-deposit yields from its CSV deposits. Water is
## permanent and never seeded. Call once at match start (see world_map._ready).
func seed_deposits(terrain) -> void:
	_deposit_terrain = terrain
	deposit_remaining.clear()
	for coord in terrain.tiles:
		var td: Dictionary = terrain.tiles[coord]
		var tid := str(td.get("id", ""))
		for dep in td.get("deposits", []):
			var token := _deposit_token_of(str(dep))
			var qty := _deposit_qty_of(str(dep))
			qty = _normalized_deposit_qty(token, qty)
			if token == "" or token == "water" or qty <= 0:
				continue
			if not deposit_remaining.has(tid):
				deposit_remaining[tid] = {}
			deposit_remaining[tid][token] = qty

## True when `tile_id` carries an INEXHAUSTIBLE deposit of `token`.
##
## Not answerable from `deposit_remaining`: seed_deposits skips anything with qty <= 0, so an
## infinite deposit is absent from that map entirely and `deposit_remaining_for` returns -1
## for "inexhaustible" and for "no deposit here" alike. The distinction lives in the terrain,
## which is what this reads.
func has_infinite_deposit(tile_id: String, token: String) -> bool:
	for d in _tile_deposit_goods(tile_id):
		if str((d as Dictionary).get("internal_name", "")) == token:
			return bool((d as Dictionary).get("infinite", false))
	return false

## Remaining yield of a deposit, or -1 if the deposit isn't tracked (e.g. water,
## or a deposit given no amount in the CSV). 0 means it has been mined out.
func deposit_remaining_for(tile_id: String, token: String) -> int:
	return int((deposit_remaining.get(tile_id, {}) as Dictionary).get(token, -1))

func deposit_depleted(tile_id: String, token: String) -> bool:
	return int((deposit_remaining.get(tile_id, {}) as Dictionary).get(token, -1)) == 0

## Reduce a tile's deposit by the amount mined this turn (floored at 0 = gone).
func deplete_deposit(tile_id: String, token: String, amount: int) -> void:
	if amount <= 0 or not deposit_remaining.has(tile_id):
		return
	var t: Dictionary = deposit_remaining[tile_id]
	if not t.has(token) or int(t[token]) <= 0:
		return
	t[token] = maxi(0, int(t[token]) - amount)
	deposits_changed.emit(tile_id)
	if int(t[token]) == 0:
		deposit_exhausted.emit(tile_id, token)

## True if a deposit's existence is known to the player: fully surveyed reveals
## everything; otherwise a deposit must have been individually revealed (by
## building a mine on it).
func is_deposit_revealed(tile_id: String, token: String) -> bool:
	if surveyed_tiles.has(tile_id):
		return true
	return (revealed_deposits.get(tile_id, {}) as Dictionary).has(token)

## Reveal one deposit's existence (size stays hidden, tile stays unsurveyed).
func reveal_deposit(tile_id: String, token: String) -> void:
	if tile_id == "" or token == "":
		return
	if not revealed_deposits.has(tile_id):
		revealed_deposits[tile_id] = {}
	if revealed_deposits[tile_id].has(token):
		return
	revealed_deposits[tile_id][token] = true
	surveyed_tiles_changed.emit()  # refresh tile panel + deposits overlay

func _deposit_token_of(raw: String) -> String:
	var p := raw.find("(")
	return (raw.substr(0, p) if p >= 0 else raw).strip_edges().to_lower()

func _deposit_qty_of(raw: String) -> int:
	var o := raw.find("(")
	var c := raw.find(")")
	if o >= 0 and c > o:
		var digits := ""
		for ch in raw.substr(o + 1, c - o - 1):
			if ch >= "0" and ch <= "9":
				digits += ch
		if digits != "":
			return int(digits)
	return -1

func _normalized_deposit_qty(token: String, qty: int) -> int:
	if token != "coal" and token != "iron_ore":
		return qty
	if qty <= 0:
		return qty
	if qty <= 2000:
		return 2000
	if qty <= 4000:
		return 4000
	return -1

## The non-water deposits on a tile as [{good_id, internal_name}]. Pure water is
## excluded (it is permanent and does not count as a found deposit / for unlocks).
func _tile_deposit_goods(tile_id: String) -> Array:
	var out: Array = []
	if _deposit_terrain == null:
		return out
	var coord: Vector2i = _deposit_terrain.id_to_coord(tile_id)
	if not _deposit_terrain.tiles.has(coord):
		return out
	for dep in _deposit_terrain.tiles[coord].get("deposits", []):
		var token := _deposit_token_of(str(dep))
		if token == "" or token == "water":
			continue
		var qty := _deposit_qty_of(str(dep))  # -1 => no amount given => infinite deposit
		var good: Dictionary = Catalog.get_good_by_internal_name(token)
		out.append({
			"good_id": str(good.get("id", token)),
			"internal_name": token,
			"display_name": str(good.get("display_name", token)),
			"qty": qty,
			"infinite": qty < 0,
		})
	return out

## "Survey complete." toast describing what a finished survey revealed.
func _survey_toast(tile_id: String, found: Array) -> String:
	var label := tile_id.trim_prefix("tile_")
	if found.is_empty():
		return "Survey complete. Tile %s showed no resources." % label
	var parts: Array = []
	for d in found:
		var name := str(d.get("display_name", d.get("internal_name", ""))).capitalize()
		if bool(d.get("infinite", false)):
			parts.append("an inexhaustible deposit of %s" % name)
		else:
			var size := "large" if int(d.get("qty", 0)) >= 500 else "small"
			parts.append("a %s deposit of %s" % [size, name])
	return "Survey complete. Tile %s revealed %s." % [label, _join_and(parts)]

func _join_and(parts: Array) -> String:
	if parts.size() <= 1:
		return str(parts[0]) if parts.size() == 1 else ""
	if parts.size() == 2:
		return "%s and %s" % [str(parts[0]), str(parts[1])]
	var head: Array = parts.slice(0, parts.size() - 1)
	return "%s, and %s" % [", ".join(head), str(parts[parts.size() - 1])]

func _join_or(parts: Array) -> String:
	if parts.size() <= 1:
		return str(parts[0]) if parts.size() == 1 else ""
	if parts.size() == 2:
		return "%s or %s" % [str(parts[0]), str(parts[1])]
	var head: Array = parts.slice(0, parts.size() - 1)
	return "%s, or %s" % [", ".join(head), str(parts[parts.size() - 1])]

# --- Public API: survey range ---
func survey_range() -> int:
	return SURVEY_RANGE_BASE + (1 if ResearchState.is_unlocked("Computer Assisted Geoscanning") else 0)

## A tile is surveyable when it lies within survey_range() tiles of a surveyed
## tile. Cached; invalidated whenever the surveyed set or range changes.
func is_tile_surveyable(tile_id: String) -> bool:
	if _surveyable_dirty:
		_rebuild_surveyable()
	return _surveyable_cache.has(tile_id)

func _rebuild_surveyable() -> void:
	_surveyable_cache.clear()
	var rng := survey_range()
	var dist: Dictionary = {}
	var queue: Array = []
	for t in surveyed_tiles:
		dist[t] = 0
		_surveyable_cache[t] = true
		queue.append(t)
	var head := 0
	while head < queue.size():
		var t: String = str(queue[head])
		head += 1
		var d := int(dist[t])
		if d >= rng:
			continue
		for n in Catalog.tile_neighbours(t):
			if not dist.has(n):
				dist[n] = d + 1
				_surveyable_cache[n] = true
				queue.append(n)
	_surveyable_dirty = false

# --- Cheats (debug terminal) ---
func _all_tile_ids() -> Array:
	var out: Array = []
	if _deposit_terrain == null:
		return out
	for coord in _deposit_terrain.tiles:
		var tid := str(_deposit_terrain.tiles[coord].get("id", ""))
		if tid != "":
			out.append(tid)
	return out

## Instantly fully-survey every tile currently within the survey limit.
func cheat_survey_within_limits() -> void:
	var targets: Array = []
	for tid in _all_tile_ids():
		if is_tile_surveyable(tid):
			targets.append(tid)
	for tid in targets:
		_cheat_reveal(tid)

## Instantly fully-survey every tile on the map.
func cheat_survey_all() -> void:
	for tid in _all_tile_ids():
		_cheat_reveal(tid)

## Cheat: unlock every research node. Skips the deliberately-dangling gates like
## 'hydro'/'consumer' (no node exists, so that content stays locked). Returns count.
func cheat_unlock_all_research() -> int:
	var n := 0
	for d in ResearchState._unlock_defs:
		var t := str(d.get("title", ""))
		if t != "" and not ResearchState.unlocked_titles.has(t):
			ResearchState.grant_unlock(t, false)
			n += 1
	return n

## Survey one tile and play its reveal animation (but no per-tile toast).
func _cheat_reveal(tile_id: String) -> void:
	if surveyed_tiles.has(tile_id):
		return
	tile_survey_completed.emit(tile_id, _tile_deposit_goods(tile_id))
	mark_tile_surveyed(tile_id)

## Partially survey every tile within the survey limit (already-surveyed tiles stay surveyed).
func cheat_partial_within_limits() -> void:
	var targets: Array = []
	for tid in _all_tile_ids():
		if is_tile_surveyable(tid):
			targets.append(tid)
	for tid in targets:
		mark_tile_partial(tid)

## Partially survey the whole map (already-surveyed tiles stay surveyed).
func cheat_partial_all() -> void:
	for tid in _all_tile_ids():
		mark_tile_partial(tid)

## Cheat: apply a -60% labour-cost modifier for 10 turns. A single -60% lands
## exactly on EconomyConfig.LABOUR_FACTOR_MIN (1 - 0.60 = 0.40), so it exercises
## both the labour-floor clamp and the People-panel "max reduction" flag at once.
func cheat_labour_discount() -> void:
	Modifiers.add({
		"id": "cheat_labour_discount",
		"domain": "labour_headcount",
		"pct": -60.0,
		"duration_turns": 10,
		"label": "Debug: labour -60%",
		"source": "cheat",
	})


# --- Battery storage (deposit model — docs/battery-storage-spec.md) ---


# Cash rebate a Chief Investment advisor gives toward a build: a fraction of the
# required build materials' CURRENT market value (tier3 +10% / tier2 +5% / tier1 -5%
# surcharge). Returned as a positive amount to subtract from the money cost.
# A seated Chief Investment advisor unlocks paying for construction on credit
# (LoanState.take_construction_loan — the 4th option on the missing-materials dialog).
func construction_credit_available() -> bool:
	return not AdvisorState._roster_entry(str(AdvisorState.advisor_seats.get("chief_investment", ""))).is_empty()

func construction_material_rebate(building_id: String) -> float:
	if building_id == "":
		return 0.0
	return _materials_rebate(Construction.requirements_for(building_id))

# Cash rebate = a fraction of the given materials' current market value, using the
# Chief Investment "construction_rebate" tier fraction (tier3 +10% / tier2 +5% / tier1 -5%).
# Shared by new builds and upgrades (the upgrade kit is valued the same way).
func _materials_rebate(reqs: Dictionary) -> float:
	var frac: float = float(Modifiers.resolve_pct("construction_rebate", "*", {}).get("net", 0.0)) / 100.0
	if frac == 0.0:
		return 0.0
	var mat_value := 0.0
	for good_id in reqs:
		mat_value += float(int(reqs[good_id])) * MarketState.get_price(str(good_id))
	return mat_value * frac


# Construction takes one turn longer than the raw CSV value (BUILD_DURATION_BUMP).
# The master-builder advisor (an Ops-3 veteran in the COO seat) shaves a turn off;
# real builds never drop below BUILD_DURATION_MIN. Instant (0-turn) buildings stay instant.
const BUILD_DURATION_BUMP := 1
const BUILD_DURATION_MIN := 1


func effective_build_duration(building_id: String) -> int:
	var base := int(Catalog.get_building(building_id).get("build_duration", 0))
	if base <= 0:
		return base   # instant buildings (infrastructure) stay instant
	var dur := base + BUILD_DURATION_BUMP
	if AdvisorState.is_master_builder_active():
		dur -= 1
	return maxi(BUILD_DURATION_MIN, dur)


# --- Land sales (decision events; decision-events-spec.md D8) -----------------
# Only surplus above the universal default holding is sellable, and only on tiles
# with no player buildings or construction projects, so a sale can never undercut
# a building footprint (land gates placement at get_tile_land_owned).


func is_building_available(building_id: String) -> bool:
	# Ports are map infrastructure that may be bought from their existing owner, never built.
	if building_id == "b_004":
		return false
	if RECYCLING_BUILDING_IDS.has(building_id) and not is_recycling_available():
		return false
	return hidden_buildings_unlocked or not HIDDEN_BUILDING_IDS.has(building_id)

## Is this good shown to the player at all? Only the recycling chain is ever hidden today.
func is_recycling_available() -> bool:
	return recycling_unlocked or preload("res://scripts/debug_terminal.gd").demo_is_unlocked()

func is_good_available(good_id: String) -> bool:
	return is_recycling_available() or not RECYCLING_GOOD_IDS.has(good_id)

## Every good the player may see, in catalogue order. The one place the gate is applied, so
## a panel opts in by calling this instead of Catalog.all_goods() — the market and telemetry
## deliberately keep the full set (a price for a hidden good is harmless; a gap is not).
func visible_goods() -> Array:
	if is_recycling_available():
		return Catalog.all_goods()
	var out: Array = []
	for good_variant: Variant in Catalog.all_goods():
		var good: Dictionary = good_variant
		if is_good_available(str(good.get("id", ""))):
			out.append(good)
	return out

## Cheat (`unlock recycling`): put the waste chain and its two plants back.
func cheat_unlock_recycling() -> void:
	if recycling_unlocked:
		return
	recycling_unlocked = true
	ResearchState.unlock_granted.emit("Recycling", "The waste chain and its plants are enabled.", false)
	hidden_buildings_enabled.emit()   # the catalogue panels already refresh on this

func cheat_unlock_hidden_buildings() -> void:
	if hidden_buildings_unlocked:
		return
	hidden_buildings_unlocked = true
	# Existing catalogue panels already refresh from this signal after research cheats.
	ResearchState.unlock_granted.emit("Hidden Buildings", "Legacy prototype buildings enabled.", false)
	hidden_buildings_enabled.emit()

## Cheat (`unlock advisors`): open the full advisor roster, every seat, and the
## People-Management seat-unlock research — all hidden by default in the demo, which
## ships only Andrew/Vera/Gerald and the CFO/COO/Technical Director/Chief Markets seats.
func cheat_unlock_advisors() -> void:
	if AdvisorState.advisors_unlocked:
		return
	AdvisorState.advisors_unlocked = true
	AdvisorState.all_seats_unlocked = true
	for a in AdvisorState.ADVISOR_ROSTER:
		var id := str(a.get("id", ""))
		if id != "" and not AdvisorState.recruited_advisor_ids.has(id):
			AdvisorState.recruited_advisor_ids.append(id)
	AdvisorState.advisors_changed.emit()


# --- Reset (useful for new game / testing) ---
func reset() -> void:
	money = 1000
	hidden_buildings_unlocked = false
	recycling_unlocked = false
	UiPrefs.reset()
	construct_start_half_capacity = false
	construct_auto_buy_land = true
	public_roads_last_turn = 0
	construct_material_source = "ask"
	construct_output_destination = "market"
	power_priority_coal_gas = "self"
	power_priority_wind_solar = "grid"
	BuildingState.reset()
	output_stockpile_destinations.clear()
	output_split_destinations.clear()
	output_special_order_destinations.clear()
	output_ship_quantities.clear()
	pending_output_stockpile_selection.clear()
	queued_stockpile_market_sales.clear()
	sell_surplus_tiles.clear()
	auto_sell_goods.clear()
	auto_sell_keep.clear()
	auto_sell_impact.clear()
	TransportState.reset()
	_unpaid_purchase_total = 0.0
	BuildingWorks.reset()
	sales_by_tile.clear()
	Power.reset()
	LabourState.reset()
	AdvisorState.reset()
	ghost_holdings.clear()
	building_tabs.clear()
	construct_credit_default = "ask"
	fake_money_this_turn = 0.0
	match_rng_seed = DEFAULT_MATCH_RNG_SEED
	_match_rng.seed = match_rng_seed
	recurring_sells.clear()
	recurring_bulk_sells.clear()
	recurring_buys.clear()
	cfo_tax_credit_pool.clear()
	cfo_tax_credit_intro_shown = false
	transaction_log.clear()
	input_tile_only.clear()
	ResearchState.reset()
	# These research ledgers live in their owning simulation systems, but share
	# the match lifetime. Reset-without-import paths (tests/scenarios) must not let
	# production or sale progress leak into the next match.
	MarketState.reset_lifetime_sales()
	Production.reset_lifetime_research_metrics()
	ruleset = DEFAULT_RULESET.duplicate(true)
	TurnManager.apply_ruleset(ruleset)   # back to the campaign length until a match sets one
	VictoryState.apply_ruleset(ruleset)   # and back to the campaign victory tracks
	scenario_name = ""
	cheats_used = false
	state_reset.emit()
	AdvisorState.advisors_changed.emit()

# --- Debug ---
func debug_dump() -> Dictionary:
	# Returns the full state as a dict, useful for save/load and debugging
	return {
		"money": money,
		"buildings": BuildingState._buildings_for_save(),
		"tile_buildings": BuildingState.tile_buildings.duplicate(true),
		"output_stockpile_destinations": output_stockpile_destinations.duplicate(true),
		"output_split_destinations": output_split_destinations.duplicate(true),
		"output_special_order_destinations": output_special_order_destinations.duplicate(true),
		"output_ship_quantities": output_ship_quantities.duplicate(true),
		"queued_stockpile_market_sales": queued_stockpile_market_sales.duplicate(true),
		"pending_transport_shipments": TransportState.pending_transport_shipments.duplicate(true),
		"tile_land_owned": BuildingState.tile_land_owned.duplicate(true),
		"_next_instance_counter": BuildingState._next_instance_counter,
	}

# --- Save/load (orchestrated by the SaveLoad autoload; docs/save_load_spec.md) ---


func export_state() -> Dictionary:
	var d := {
		"money": money,
		"ruleset": ruleset.duplicate(true),
		"scenario_name": scenario_name,
		"cheats_used": cheats_used,
		"construct_start_half_capacity": construct_start_half_capacity,
		"construct_auto_buy_land": construct_auto_buy_land,
		"public_roads_last_turn": public_roads_last_turn,
		"construct_material_source": construct_material_source,
		"construct_output_destination": construct_output_destination,
		"power_priority_coal_gas": power_priority_coal_gas,
		"power_priority_wind_solar": power_priority_wind_solar,
		"ghost_holdings": ghost_holdings.duplicate(true),
		"building_tabs": building_tabs.duplicate(true),
		"construct_credit_default": construct_credit_default,
		"advisor_rng_seed": match_rng_seed,
		"advisor_rng_state": _match_rng.state,
		"cfo_tax_credit_pool": cfo_tax_credit_pool.duplicate(true),
		"cfo_tax_credit_intro_shown": cfo_tax_credit_intro_shown,
		"sell_mode": sell_mode,
		"route_objective": route_objective,
		"output_stockpile_destinations": output_stockpile_destinations.duplicate(true),
		"output_split_destinations": output_split_destinations.duplicate(true),
		"output_special_order_destinations": output_special_order_destinations.duplicate(true),
		"output_ship_quantities": output_ship_quantities.duplicate(true),
		"input_tile_only": input_tile_only.duplicate(true),
		"recurring_sells": recurring_sells.duplicate(true),
		"recurring_bulk_sells": recurring_bulk_sells.duplicate(true),
		"recurring_buys": recurring_buys.duplicate(true),
		"sell_surplus_tiles": sell_surplus_tiles.duplicate(true),
		"auto_sell_goods": auto_sell_goods.duplicate(true),
		"auto_sell_keep": auto_sell_keep.duplicate(true),
		"auto_sell_impact": auto_sell_impact.duplicate(true),
		"queued_stockpile_market_sales": queued_stockpile_market_sales.duplicate(true),
		# Additive (v3 transport panel): an older save has neither, and the empty
		# default reads correctly as "no history yet" until turns accrue.
		"transaction_log": transaction_log.duplicate(true),
		"surveyed_tiles": surveyed_tiles.duplicate(true),
		"partially_surveyed_tiles": partially_surveyed_tiles.duplicate(true),
		"surveying_in_progress": surveying_in_progress.duplicate(true),
		"surveying_reveal": surveying_reveal.duplicate(true),
		"revealed_deposits": revealed_deposits.duplicate(true),
		"deposit_remaining": deposit_remaining.duplicate(true),
	}
	d.merge(ResearchState.export_fields())
	d.merge(AdvisorState.export_fields())
	d.merge(BuildingWorks.export_fields())
	d.merge(LabourState.export_fields())
	d.merge(TransportState.export_fields())
	d.merge(Power.export_fields())
	d.merge(BuildingState.export_fields())
	return d

func import_state(d: Dictionary) -> void:
	# Silent full overwrite of every exported field — SaveLoad emits the refresh
	# signals once after every system has imported. Missing keys fall back to the
	# new-game default, so older/partial snapshots (and Phase 3 start configs) load.
	money = float(d.get("money", EconomyConfig.STARTING_MONEY))
	ruleset = (d.get("ruleset", DEFAULT_RULESET) as Dictionary).duplicate(true)
	# The campaign length lives in the ruleset, so this is the one moment it is known —
	# for a new game and for a load alike. TurnManager reads nothing else about the match.
	TurnManager.apply_ruleset(ruleset)
	VictoryState.apply_ruleset(ruleset)   # which set of victory tracks this match runs
	# Tolerant readers: saves from before these existed load as an unknown start, uncheated.
	scenario_name = str(d.get("scenario_name", ""))
	cheats_used = bool(d.get("cheats_used", false))
	set_construct_start_half_capacity(bool(d.get("construct_start_half_capacity", false)), false)
	# Additive key: saves written before this setting existed use automatic land buying.
	set_construct_auto_buy_land(bool(d.get("construct_auto_buy_land", true)), false)
	public_roads_last_turn = int(d.get("public_roads_last_turn", 0))
	set_construct_material_source(str(d.get("construct_material_source", "ask")), false)
	set_construct_output_destination(str(d.get("construct_output_destination", "market")), false)
	# Additive key: saves written before this setting existed default to the same
	# intermittency-avoiding defaults a fresh match starts with.
	set_power_priority("coal_gas", str(d.get("power_priority_coal_gas", "self")), false)
	set_power_priority("wind_solar", str(d.get("power_priority_wind_solar", "grid")), false)
	BuildingState.import_fields(d)
	TransportState.import_fields(d)
	Power.import_fields(d)
	LabourState.import_fields(d)
	AdvisorState.import_fields(d)
	cfo_tax_credit_pool = (d.get("cfo_tax_credit_pool", []) as Array).duplicate(true)
	cfo_tax_credit_intro_shown = bool(d.get("cfo_tax_credit_intro_shown", false))
	ghost_holdings = (d.get("ghost_holdings", {}) as Dictionary).duplicate(true)
	building_tabs = (d.get("building_tabs", {}) as Dictionary).duplicate(true)
	construct_credit_default = str(d.get("construct_credit_default", "ask"))
	match_rng_seed = int(d.get("advisor_rng_seed", DEFAULT_MATCH_RNG_SEED))
	_match_rng.seed = match_rng_seed
	_match_rng.state = int(d.get("advisor_rng_state", _match_rng.state))
	sell_mode = int(d.get("sell_mode", SellMode.STOCKPILE_ALL))
	route_objective = int(d.get("route_objective", RouteObjective.FASTEST))
	output_stockpile_destinations = (d.get("output_stockpile_destinations", {}) as Dictionary).duplicate(true)
	output_split_destinations = (d.get("output_split_destinations", {}) as Dictionary).duplicate(true)
	output_special_order_destinations = (d.get("output_special_order_destinations", {}) as Dictionary).duplicate(true)
	output_ship_quantities = (d.get("output_ship_quantities", {}) as Dictionary).duplicate(true)
	input_tile_only = (d.get("input_tile_only", {}) as Dictionary).duplicate(true)
	recurring_sells = (d.get("recurring_sells", []) as Array).duplicate(true)
	recurring_bulk_sells = (d.get("recurring_bulk_sells", []) as Array).duplicate(true)
	recurring_buys = (d.get("recurring_buys", []) as Array).duplicate(true)
	sell_surplus_tiles = (d.get("sell_surplus_tiles", {}) as Dictionary).duplicate(true)
	auto_sell_goods = (d.get("auto_sell_goods", {}) as Dictionary).duplicate(true)
	auto_sell_keep = (d.get("auto_sell_keep", {}) as Dictionary).duplicate(true)
	auto_sell_impact = (d.get("auto_sell_impact", {}) as Dictionary).duplicate(true)
	queued_stockpile_market_sales = (d.get("queued_stockpile_market_sales", {}) as Dictionary).duplicate(true)
	_recompute_unpaid_purchases()  # rebuilt from the shipments so the accumulator can't drift
	BuildingWorks.import_fields(d)
	transaction_log = (d.get("transaction_log", []) as Array).duplicate(true)
	surveyed_tiles = (d.get("surveyed_tiles", {}) as Dictionary).duplicate(true)
	partially_surveyed_tiles = (d.get("partially_surveyed_tiles", {}) as Dictionary).duplicate(true)
	surveying_in_progress = (d.get("surveying_in_progress", {}) as Dictionary).duplicate(true)
	surveying_reveal = (d.get("surveying_reveal", {}) as Dictionary).duplicate(true)
	revealed_deposits = (d.get("revealed_deposits", {}) as Dictionary).duplicate(true)
	# Default to the CURRENT value, not {}: a start config carries no deposit data,
	# so the CSV-seeded yields from world_map._ready must survive the import. Full
	# saves always carry the key and overwrite as usual.
	deposit_remaining = (d.get("deposit_remaining", deposit_remaining) as Dictionary).duplicate(true)
	ResearchState.import_fields(d)
	# Derived state: the tile index is rebuilt, never saved; caches invalidate.
	BuildingState._rebuild_tile_index()
	_surveyable_dirty = true
	pending_output_stockpile_selection.clear()
	sales_by_tile.clear()
	TransportState._requote_shipment_routes()


func set_sell_mode(mode: int) -> void:
	sell_mode = mode
	sell_mode_changed.emit(mode)


func set_construct_start_half_capacity(enabled: bool, emit_change: bool = true) -> void:
	if construct_start_half_capacity == enabled:
		return
	construct_start_half_capacity = enabled
	if emit_change:
		construct_settings_changed.emit()

func set_construct_auto_buy_land(enabled: bool, emit_change: bool = true) -> void:
	if construct_auto_buy_land == enabled:
		return
	construct_auto_buy_land = enabled
	if emit_change:
		construct_settings_changed.emit()


## The material source the NEXT build attempt should use: the one-build accordion override if the
## player picked one, else the standing setting. Legacy "ask" resolves to "market" — the modal is
## retired, so a build never blocks waiting for a choice (the accordion is where the choice is made
## now). Clears the one-build override so it applies exactly once.
func consume_build_material_source() -> String:
	var src := pending_build_material_source if pending_build_material_source != "" else construct_material_source
	pending_build_material_source = ""
	if src == "ask" or src == "":
		src = "market"
	return src

func set_construct_material_source(value: String, emit_change: bool = true) -> void:
	var resolved := value.to_lower().strip_edges()
	if resolved not in ["ask", "market", "same_tile", "any_tile"]:
		resolved = "market"
	if construct_material_source == resolved:
		return
	construct_material_source = resolved
	if emit_change:
		construct_settings_changed.emit()

func set_construct_output_destination(value: String, emit_change: bool = true) -> void:
	var resolved := value.to_lower().strip_edges()
	if resolved not in ["market", "same_tile"]:
		resolved = "market"
	if construct_output_destination == resolved:
		return
	construct_output_destination = resolved
	if emit_change:
		construct_settings_changed.emit()

## `category` is "coal_gas" or "wind_solar"; `priority` is "self" or "grid" — see
## the vars' own comment. Applies live (no per-instance capture), so nothing else
## needs to touch existing buildings when this changes.
func set_power_priority(category: String, priority: String, emit_change: bool = true) -> void:
	var resolved := priority.to_lower().strip_edges()
	if resolved not in ["self", "grid"]:
		return
	if category == "coal_gas":
		if power_priority_coal_gas == resolved:
			return
		power_priority_coal_gas = resolved
	elif category == "wind_solar":
		if power_priority_wind_solar == resolved:
			return
		power_priority_wind_solar = resolved
	else:
		return
	if emit_change:
		power_priority_changed.emit()

## "self" or "grid" for the given category ("coal_gas" / "wind_solar"); "self" for
## anything else (e.g. hydro, or a non-power building) — this feature's priority
## only ever gates generation EconomyConfig.power_priority_category() actually
## names, so "no category" must never be read as "sells to the grid".
func power_priority_for(category: String) -> String:
	if category == "coal_gas":
		return power_priority_coal_gas
	if category == "wind_solar":
		return power_priority_wind_solar
	return "self"

## Multiplier applied only to a new building's first successful operating turn.
## It is stored on the instance, so changing the default later cannot alter an
## already-started project or a completed building.
func startup_capacity_multiplier(building: Dictionary) -> float:
	return 0.5 if bool(building.get("startup_half_capacity", false)) else 1.0

func consume_startup_capacity(instance_id: String) -> void:
	if instance_id == "" or not BuildingState.buildings.has(instance_id):
		return
	BuildingState.buildings[instance_id].erase("startup_half_capacity")

func set_route_objective(objective: int) -> void:
	if objective == route_objective:
		return
	route_objective = objective
	route_objective_changed.emit(objective)

func begin_output_stockpile_selection(instance_id: String, good_id: String, allow_split: bool = true) -> void:
	if instance_id == "" or good_id == "":
		return
	pending_output_stockpile_selection = {
		"instance_id": instance_id,
		"good_id": good_id,
		"allow_split": allow_split,
	}
	output_stockpile_selection_started.emit(pending_output_stockpile_selection.duplicate())

func cancel_output_stockpile_selection() -> void:
	if pending_output_stockpile_selection.is_empty():
		return
	pending_output_stockpile_selection.clear()
	output_stockpile_selection_cancelled.emit()

# Destinations are stored PER OUTPUT GOOD so a multi-output building (e.g. a
# chlor-alkali plant making chlorine + sodium hydroxide + hydrogen) can route each
# output independently. Shape: instance_id -> { good_id -> tile_id|MARKET_DESTINATION }.
func set_output_stockpile_destination(instance_id: String, tile_id: String, good_id: String) -> void:
	if instance_id == "" or tile_id == "" or good_id == "":
		return
	var per_good: Dictionary = output_stockpile_destinations.get(instance_id, {})
	per_good[good_id] = tile_id
	output_stockpile_destinations[instance_id] = per_good
	_clear_output_split_destinations(instance_id, good_id)
	_clear_output_special_order_tag(instance_id, good_id)
	set_output_ship_quantity(instance_id, good_id, 0)  # plain routing ships ALL; a cap is set explicitly after
	pending_output_stockpile_selection.clear()
	output_stockpile_destination_changed.emit(instance_id, tile_id, good_id)

# Cap how much of `good_id` ships to the explicit destination each turn (the CTRL+click
# "send a specific amount" flow). qty <= 0 clears the cap (ship everything).
func set_output_ship_quantity(instance_id: String, good_id: String, qty: int) -> void:
	if instance_id == "" or good_id == "":
		return
	var per_good: Dictionary = output_ship_quantities.get(instance_id, {})
	if qty <= 0:
		per_good.erase(good_id)
	else:
		per_good[good_id] = qty
	if per_good.is_empty():
		output_ship_quantities.erase(instance_id)
	else:
		output_ship_quantities[instance_id] = per_good

func get_output_ship_quantity(instance_id: String, good_id: String) -> int:
	return int((output_ship_quantities.get(instance_id, {}) as Dictionary).get(good_id, 0))

func clear_output_stockpile_destination(instance_id: String, good_id: String = "") -> void:
	if instance_id == "":
		return
	if good_id == "":
		output_stockpile_destinations.erase(instance_id)  # clear the whole building
		output_split_destinations.erase(instance_id)
		output_special_order_destinations.erase(instance_id)
		output_ship_quantities.erase(instance_id)
		return
	var per_good: Dictionary = output_stockpile_destinations.get(instance_id, {})
	per_good.erase(good_id)
	if per_good.is_empty():
		output_stockpile_destinations.erase(instance_id)
	else:
		output_stockpile_destinations[instance_id] = per_good
	set_output_ship_quantity(instance_id, good_id, 0)
	_clear_output_split_destinations(instance_id, good_id)
	_clear_output_special_order_tag(instance_id, good_id)

func get_output_stockpile_destination(instance_id: String, good_id: String = "") -> String:
	var split := get_output_split_destinations(instance_id, good_id)
	if not split.is_empty():
		return str((split[0] as Dictionary).get("tile_id", ""))
	var per_good: Dictionary = output_stockpile_destinations.get(instance_id, {})
	if per_good.is_empty():
		return ""
	var tile_id := ""
	if good_id != "":
		tile_id = str(per_good.get(good_id, ""))
	elif per_good.size() == 1:
		tile_id = str(per_good.values()[0])  # unambiguous single-output building
	if tile_id == "" or tile_id == MARKET_DESTINATION:
		return ""  # unset, or a market route (not a stockpile tile)
	return tile_id

# Returns the selected destinations for a split route in selection order. A single
# destination remains a legacy route, so callers only split production when this has
# two or three entries.
func get_output_split_destinations(instance_id: String, good_id: String) -> Array:
	if instance_id == "" or good_id == "":
		return []
	var per_good: Dictionary = output_split_destinations.get(instance_id, {})
	var raw: Array = per_good.get(good_id, [])
	var destinations: Array = []
	for item in raw:
		if not (item is Dictionary):
			continue
		var tile_id := str(item.get("tile_id", ""))
		if tile_id == "" or tile_id == MARKET_DESTINATION:
			continue
		destinations.append({"tile_id": tile_id, "qty": clampi(int(item.get("qty", 0)), 0, 999)})
	return destinations

func add_output_split_destination(instance_id: String, good_id: String, tile_id: String) -> int:
	if instance_id == "" or good_id == "" or tile_id == "":
		return get_output_split_destinations(instance_id, good_id).size()
	var destinations := get_output_split_destinations(instance_id, good_id)
	for item in destinations:
		if str((item as Dictionary).get("tile_id", "")) == tile_id:
			return destinations.size()
	if destinations.size() >= 3:
		return destinations.size()
	# The first Shift-click starts a new split selection, replacing the old route.
	if destinations.is_empty():
		var legacy: Dictionary = output_stockpile_destinations.get(instance_id, {})
		legacy.erase(good_id)
		if legacy.is_empty():
			output_stockpile_destinations.erase(instance_id)
		else:
			output_stockpile_destinations[instance_id] = legacy
		set_output_ship_quantity(instance_id, good_id, 0)
		_clear_output_special_order_tag(instance_id, good_id)
	destinations.append({"tile_id": tile_id, "qty": 0})
	var per_good: Dictionary = output_split_destinations.get(instance_id, {})
	per_good[good_id] = destinations
	output_split_destinations[instance_id] = per_good
	output_stockpile_destination_changed.emit(instance_id, tile_id, good_id)
	return destinations.size()

func set_output_split_quantity(instance_id: String, good_id: String, tile_id: String, qty: int) -> void:
	var destinations := get_output_split_destinations(instance_id, good_id)
	var changed := false
	for item in destinations:
		if str((item as Dictionary).get("tile_id", "")) == tile_id:
			item["qty"] = clampi(qty, 0, 999)
			changed = true
			break
	if not changed:
		return
	var per_good: Dictionary = output_split_destinations.get(instance_id, {})
	per_good[good_id] = destinations
	output_split_destinations[instance_id] = per_good
	output_stockpile_destination_changed.emit(instance_id, tile_id, good_id)

func _clear_output_split_destinations(instance_id: String, good_id: String = "") -> void:
	if good_id == "":
		output_split_destinations.erase(instance_id)
		return
	var per_good: Dictionary = output_split_destinations.get(instance_id, {})
	per_good.erase(good_id)
	if per_good.is_empty():
		output_split_destinations.erase(instance_id)
	else:
		output_split_destinations[instance_id] = per_good

## True when ANY destination is recorded for this building+good — including a market route,
## which get_output_stockpile_destination() reports as "" because it isn't a stockpile tile.
## Construction uses this so completing a build defaults the route without overwriting a
## choice the player already made while it was under construction.
func has_output_destination(instance_id: String, good_id: String) -> bool:
	if instance_id == "" or good_id == "":
		return false
	return not get_output_split_destinations(instance_id, good_id).is_empty() \
		or str((output_stockpile_destinations.get(instance_id, {}) as Dictionary).get(good_id, "")) != ""

func route_output_to_market(instance_id: String, good_id: String) -> void:
	# Per-building, per-good "send output to market" — does NOT touch global sell_mode.
	if instance_id == "" or good_id == "":
		return
	var per_good: Dictionary = output_stockpile_destinations.get(instance_id, {})
	per_good[good_id] = MARKET_DESTINATION
	output_stockpile_destinations[instance_id] = per_good
	_clear_output_split_destinations(instance_id, good_id)
	set_output_ship_quantity(instance_id, good_id, 0)
	_clear_output_special_order_tag(instance_id, good_id)
	pending_output_stockpile_selection.clear()
	output_stockpile_destination_changed.emit(instance_id, MARKET_DESTINATION, good_id)

func route_output_to_special_order(instance_id: String, good_id: String, special_order_id: String) -> void:
	if instance_id == "" or good_id == "" or special_order_id == "":
		return
	var order := SpecialOrderState.get_order(special_order_id)
	if order.is_empty() or str(order.get("good_id", "")) != good_id:
		return
	var per_good: Dictionary = output_stockpile_destinations.get(instance_id, {})
	per_good[good_id] = MARKET_DESTINATION
	output_stockpile_destinations[instance_id] = per_good
	_clear_output_split_destinations(instance_id, good_id)
	var per_order: Dictionary = output_special_order_destinations.get(instance_id, {})
	per_order[good_id] = special_order_id
	output_special_order_destinations[instance_id] = per_order
	pending_output_stockpile_selection.clear()
	output_stockpile_destination_changed.emit(instance_id, MARKET_DESTINATION, good_id)

func is_output_market(instance_id: String, good_id: String = "") -> bool:
	var per_good: Dictionary = output_stockpile_destinations.get(instance_id, {})
	if per_good.is_empty():
		return false
	if good_id != "":
		return str(per_good.get(good_id, "")) == MARKET_DESTINATION
	for v in per_good.values():
		if str(v) == MARKET_DESTINATION:
			return true
	return false

func get_output_special_order_id(instance_id: String, good_id: String = "") -> String:
	var per_good: Dictionary = output_special_order_destinations.get(instance_id, {})
	if per_good.is_empty():
		return ""
	if good_id != "":
		return str(per_good.get(good_id, ""))
	if per_good.size() == 1:
		return str(per_good.values()[0])
	return ""

func is_output_special_order(instance_id: String, good_id: String = "") -> bool:
	return get_output_special_order_id(instance_id, good_id) != ""

func _clear_output_special_order_tag(instance_id: String, good_id: String = "") -> void:
	if instance_id == "":
		return
	if good_id == "":
		output_special_order_destinations.erase(instance_id)
		return
	var per_order: Dictionary = output_special_order_destinations.get(instance_id, {})
	if per_order.is_empty():
		return
	per_order.erase(good_id)
	if per_order.is_empty():
		output_special_order_destinations.erase(instance_id)
	else:
		output_special_order_destinations[instance_id] = per_order

func queue_stockpile_market_sale(tile_id: String) -> void:
	if tile_id == "":
		return
	queued_stockpile_market_sales[tile_id] = true
	stockpile_market_sale_queue_changed.emit(tile_id)

func clear_stockpile_market_sale_queue(tile_id: String) -> void:
	if tile_id == "":
		return
	if queued_stockpile_market_sales.erase(tile_id):
		stockpile_market_sale_queue_changed.emit(tile_id)

func is_stockpile_market_sale_queued(tile_id: String) -> bool:
	return queued_stockpile_market_sales.has(tile_id)

func consume_queued_stockpile_market_sales() -> Array:
	var queued_tiles: Array = queued_stockpile_market_sales.keys()
	queued_stockpile_market_sales.clear()
	for tile_id in queued_tiles:
		stockpile_market_sale_queue_changed.emit(str(tile_id))
	return queued_tiles

func emit_stockpile_market_sale_completed(sale_record: Dictionary) -> void:
	stockpile_market_sale_completed.emit(sale_record)

## Running total of market purchases that are in transit and NOT yet paid for. Kept as an
## accumulator rather than summed over pending_transport_shipments on every order, because
## a busy turn places many orders and the shipment list is a known sim hot-spot. Rebuilt
## from the shipment list on load (_recompute_unpaid_purchases) so it can't drift.
var _unpaid_purchase_total: float = 0.0

## What a new market purchase may still commit: cash on hand, PLUS what the player could
## still borrow, MINUS purchases already in transit that haven't been paid for yet.
## Pay-on-arrival means an order may legitimately push the balance
## negative — the auto-bridge loan is what catches that. The line it must not cross is the
## point where the debt could no longer be financed at all. Because in-transit commitments
## are subtracted, orders placed in the same turn resolve SEQUENTIALLY: each one consumes
## the headroom the next is measured against, so a big order fails without blocking the
## small ones behind it.
func purchase_headroom() -> float:
	return money + maxf(0.0, LoanState.available_capacity()) - _unpaid_purchase_total

func unpaid_purchase_total() -> float:
	return _unpaid_purchase_total

## Cash leaves when the goods land. Called once per arriving purchase shipment.
func settle_arrived_purchase(cost: float) -> void:
	if cost <= 0.0:
		return
	add_money(-cost)
	_unpaid_purchase_total = maxf(0.0, _unpaid_purchase_total - cost)

func _recompute_unpaid_purchases() -> void:
	var total := 0.0
	for shipment in TransportState.pending_transport_shipments:
		total += float((shipment as Dictionary).get("purchase_cost", 0.0))
	_unpaid_purchase_total = total


func request_toast(message: String, toast_type: String = "success") -> void:
	toast_requested.emit(message, toast_type)


# --- Cancel recurring orders (Market panel Movements/Sales tabs). Erase-by-value: the

func remove_recurring_sell(entry: Dictionary) -> bool:
	if not recurring_sells.has(entry):
		return false
	recurring_sells.erase(entry)
	recurring_orders_changed.emit()
	return true

func remove_recurring_bulk_sell(entry: Dictionary) -> bool:
	if not recurring_bulk_sells.has(entry):
		return false
	recurring_bulk_sells.erase(entry)
	recurring_orders_changed.emit()
	return true


func run_recurring_and_scheduled_moves() -> void:
	# Fire one-shot scheduled moves (e.g. the split second half) then re-issue recurring moves.
	var due: Array = TransportState.scheduled_moves
	TransportState.scheduled_moves = []
	for m in due:
		TransportState.queue_move(str(m.source), str(m.dest), m.goods, true)  # split second-half = a one-off
	for m in TransportState.recurring_moves:
		TransportState.queue_move(str(m.source), str(m.dest), m.goods, false)
	for m in recurring_sells:
		_run_recurring_sell(m)
	for r in recurring_bulk_sells:
		sell_all_to_market(r.get("params", {}), false)

func _run_recurring_sell(entry: Dictionary) -> void:
	# Sell the configured qty of each good every turn, drawing from the bound source
	# tile first and then any other tile that holds the good. This keeps "sell N coal
	# every turn" working even after the source tile is drained — the produced coal
	# now sits on the mine tiles, not the tile the order was created from.
	var source := str(entry.get("source", ""))
	var goods: Dictionary = entry.get("goods", {})
	for good_id in goods.keys():
		var remaining := int(goods[good_id])
		if remaining <= 0:
			continue
		# Ordered draw list: source tile first, then other tiles holding the good.
		var draw_tiles: Array = []
		if source != "" and Stockpile.get_at_tile(source, str(good_id)) > 0:
			draw_tiles.append(source)
		for t in Stockpile.tiles_with_stock():
			var ts := str(t)
			if ts == source or not ts.begins_with("tile_"):
				continue
			if Stockpile.get_at_tile(ts, str(good_id)) > 0:
				draw_tiles.append(ts)
		for t in draw_tiles:
			if remaining <= 0:
				break
			var avail := Stockpile.get_at_tile(str(t), str(good_id))
			var take: int = mini(remaining, avail)
			if take <= 0:
				continue
			queue_sell(str(t), {good_id: take}, false)
			remaining -= take

func add_recurring_sell(source_tile: String, goods_qtys: Dictionary) -> void:
	recurring_sells.append({"source": source_tile, "goods": goods_qtys.duplicate(true), "turn_started": _ledger_turn()})
	recurring_orders_changed.emit()

func add_recurring_bulk_sell(params: Dictionary) -> void:
	recurring_bulk_sells.append({"params": params.duplicate(true), "turn_started": _ledger_turn()})
	recurring_orders_changed.emit()

func add_recurring_buy(dest_tile: String, good_id: String, qty: int) -> void:
	recurring_buys.append({"dest": dest_tile, "good": good_id, "qty": qty, "turn_started": _ledger_turn()})

# --- Ledger helpers for the Transactions / Movements tabs ---

func _ledger_turn() -> int:
	return int(TurnManager.current_turn) if TurnManager else 0

func _log_transaction(entry: Dictionary) -> void:
	transaction_log.append(entry)
	if transaction_log.size() > LEDGER_MAX:
		transaction_log = transaction_log.slice(transaction_log.size() - LEDGER_MAX)


func log_market_sale(source_tile: String, port_tile: String, good_id: String, qty: int, turns: int) -> void:
	# Production calls this when output / stockpile sells to market, so the ledger reflects it.
	if qty <= 0:
		return
	var started := _ledger_turn()
	_log_transaction({
		"kind": "sell", "good_id": str(good_id), "qty": int(qty),
		"tile_from": source_tile, "tile_to": port_tile if port_tile != "" else "Market",
		"turn_started": started, "turn_ended": started + maxi(0, turns),
	})


func _ledger_tile_label(tile_id: String) -> String:
	if tile_id == "":
		return "—"
	if tile_id.begins_with("tile_"):
		return Catalog.tile_label(tile_id)
	return tile_id  # e.g. "Market", "All tiles"

func _txn_row(kind: String, good: String, qty: int, tile_from: String, tile_to: String, started: int, ended: int) -> Dictionary:
	return {
		"type": "Buy" if kind == "buy" else "Sell",
		"from": _ledger_tile_label(tile_from), "to": _ledger_tile_label(tile_to),
		"good": good, "qty": qty, "turn_started": started, "turn_ended": ended,
	}

func _move_row(good: String, qty: int, tile_from: String, tile_to: String, started: int, ended: int) -> Dictionary:
	return {
		"type": "Move", "from": _ledger_tile_label(tile_from), "to": _ledger_tile_label(tile_to),
		"good": good, "qty": qty, "turn_started": started, "turn_ended": ended,
	}

func _input_key(instance_id: String, good_id: String) -> String:
	return instance_id + "|" + good_id

func set_input_tile_only(instance_id: String, good_id: String, tile_only: bool) -> void:
	# Default (not set) = "stockpile then market" (buys the shortfall). tile_only = never buy.
	if instance_id == "" or good_id == "":
		return
	if tile_only:
		input_tile_only[_input_key(instance_id, good_id)] = true
	else:
		input_tile_only.erase(_input_key(instance_id, good_id))

func is_input_tile_only(instance_id: String, good_id: String) -> bool:
	return bool(input_tile_only.get(_input_key(instance_id, good_id), false))

# --- Seaport subscriptions and sea freight ---


func queue_buy(dest_tile: String, good_id: String, qty: int, log_oneoff: bool = true, extra: Dictionary = {}) -> Dictionary:
	# Buy goods from the nearest port to dest_tile: pay now (price + transport), ship in,
	# arrive in N turns. The reusable buy primitive for market-sourced inputs (and later a Buy tab).
	if dest_tile == "" or good_id == "" or qty <= 0:
		return {}
	# An import prohibition is enforced HERE because every purchase route funnels
	# through this primitive: automated market top-up, recurring buys, construction
	# and upgrade materials, and the manual buy. One guard closes all of them.
	if PolicyState.import_banned(good_id, TurnManager.current_turn):
		return {}
	var covered := TransportState.seaport_covers(good_id)
	var quote := TransportService.quote_market_buy(dest_tile, good_id, qty, covered)
	if quote.is_empty():
		return {}
	var port := str(quote.get("port", ""))
	var route: Dictionary = quote.get("route", {})
	var turns: int = int(quote.get("turns", 0))
	var unit_price := MarketState.get_buy_price(good_id)
	var transport := float(quote.get("transport_cost", 0.0))
	var total := float(quote.get("cost", 0.0))
	# Gate on the FINANCEABLE headroom, not on cash in hand — see purchase_headroom().
	var headroom := purchase_headroom()
	if total > headroom:
		# Best-effort: take as much as the headroom allows rather than nothing (avoids an
		# all-or-nothing starvation cliff when the balance dips below a full order).
		var per_unit := unit_price + transport / float(maxi(qty, 1))
		qty = mini(qty, int(floor(headroom / maxf(per_unit, 0.0001))))
		if qty <= 0:
			return {}
		quote = TransportService.quote_market_buy(dest_tile, good_id, qty, covered)
		route = quote.get("route", {})
		turns = int(quote.get("turns", 0))
		transport = float(quote.get("transport_cost", 0.0))
		total = float(quote.get("cost", 0.0))
		if total > headroom:
			return {}
	# The quote previews a mutable port-capacity charge. Commit only after the final,
	# financeable quantity is known, then reconcile in case an earlier shipment used capacity.
	var sea_quote := float(quote.get("sea_transport_cost", 0.0))
	var sea_charge := TransportState.commit_sea_shipping(port, good_id, qty, "buy")
	if not sea_charge.is_empty():
		var actual_sea := float(sea_charge.get("total", 0.0))
		transport += actual_sea - sea_quote
		total += actual_sea - sea_quote
	var transport_breakdown: Dictionary = (quote.get("route_transport_breakdown", {}) as Dictionary).duplicate()
	if not sea_charge.is_empty():
		# Split by DIRECTION: this is the import leg. The ad valorem rides its own "sea" line
		# rather than being folded in, because it is the component about to carry the freight
		# redesign and needs to be watchable on its own.
		# The whole port charge, by direction. Splitting fee-from-ad-valorem left both direction
		# lines reading zero once the flat fee was retired — reported from a turn-63 save.
		transport_breakdown["port_inbound"] = float(transport_breakdown.get("port_inbound", 0.0)) \
			+ float(sea_charge.get("base_fee", 0.0)) + float(sea_charge.get("insurance_fee", 0.0))
	# Goods with a transit leg are paid for ON ARRIVAL; instant (0-turn) deliveries have no
	# transit to defer over, so they settle here.
	if turns < 1:
		add_money(-total)
	# Deficit feed: heavy player buying in one good pushes its price up (the
	# mirror of the sell-side glut) — see MarketState._tick_impact.
	MarketState.record_market_buy_volume(good_id, qty)
	if log_oneoff:
		var started := _ledger_turn()
		_log_transaction({
			"kind": "buy", "good_id": good_id, "qty": qty,
			"tile_from": port, "tile_to": dest_tile,
			"turn_started": started, "turn_ended": started + maxi(0, turns),
		})
	if turns >= 1:
		var shipment: Dictionary = {
			"source_tile": port, "destination_tile": dest_tile,
			"good_id": good_id, "qty": qty,
			"turns_remaining": turns, "transport_turns": turns,
			"transport_cost": transport, "is_purchase": true,
			# The unpaid bill rides with the goods. Production settles it on arrival and
			# books it into that turn's summary, so money_out always matches real cash.
			# Additive save field: an old save's in-flight shipments have no purchase_cost,
			# which correctly reads as "already paid for" under the old charge-on-order rule.
			"purchase_cost": total,
			"purchase_goods_cost": total - transport,
			"transport_breakdown": transport_breakdown,
			"tiles": route.get("tiles", []), "path": route.get("path", []), "legs": route.get("legs", []),
		}
		shipment.merge(extra, true)  # optional tags, e.g. construction_instance_id
		_unpaid_purchase_total += total
		TransportState.queue_transport_shipment(shipment)
	else:
		Stockpile.add(dest_tile, good_id, qty)
	# Victory feed: every successful buy (including 0-turn instant deliveries) is a
	# goods movement. Category is derived from the optional tags so the Autarkic
	# track can show what broke the streak (input / building / upgrade / other).
	var buy_category := "other"
	if extra.has("construction_instance_id"):
		buy_category = "building"
	elif extra.has("upgrade_instance_id"):
		buy_category = "upgrade"
	elif str(extra.get("buy_kind", "")) != "":
		buy_category = str(extra.get("buy_kind", ""))
	goods_movement_recorded.emit("buy", buy_category, turns)
	# `deferred` tells the caller the cash has NOT left yet — Production books a deferred
	# purchase into the summary when it arrives, not here, so money_out tracks real cash.
	return {"qty": qty, "turns": turns, "cost": total, "deferred": turns >= 1,
		"goods_cost": float(qty) * unit_price, "transport_cost": transport,
		"transport_breakdown": transport_breakdown, "port": port}

func tiles_producing(good_id: String) -> Dictionary:
	var out: Dictionary = {}
	for inst in BuildingState.buildings.values():
		if Catalog.recipe_produces(Catalog.get_recipe(str(inst.get("recipe_id", ""))), good_id):
			out[str(inst.get("tile_id", ""))] = true
	return out

func tiles_consuming(good_id: String) -> Dictionary:
	var out: Dictionary = {}
	for inst in BuildingState.buildings.values():
		for input in Catalog.get_recipe(str(inst.get("recipe_id", ""))).get("inputs", []):
			if str(input.get("good_id", "")) == good_id:
				out[str(inst.get("tile_id", ""))] = true
				break
	return out

func preview_buy(dest_tile: String, good_id: String, qty: int) -> Dictionary:
	# Cost/turns for a buy WITHOUT executing — for the Purchases "Cost to buy" line.
	if dest_tile == "" or good_id == "" or qty <= 0:
		return {}
	# Mirrors the queue_buy guard so the UI never quotes a price for a purchase that
	# would be refused.
	if PolicyState.import_banned(good_id, TurnManager.current_turn):
		return {}
	var quote := TransportService.quote_market_buy(dest_tile, good_id, qty, TransportState.seaport_would_cover(good_id))
	if quote.is_empty():
		return {}
	return {"cost": float(quote.get("cost", 0.0)), "goods_cost": float(quote.get("goods_cost", 0.0)),
		"transport_cost": float(quote.get("transport_cost", 0.0)), "turns": int(quote.get("turns", 0)),
		"port": str(quote.get("port", ""))}

# --- Warehouse expansion (per-tile storage upgrade paid in materials) ---

## Everything the tile panel needs to render the "Expand Warehouse" offer:
## the next level's material bill with per-good empire stock vs market cost
## (ask + freight to the tile), plus affordability flags.
func warehouse_upgrade_quote(tile_id: String) -> Dictionary:
	var level := Stockpile.get_warehouse_level(tile_id)
	var next_level := level + 1
	if tile_id == "" or not EconomyConfig.WAREHOUSE_UPGRADE_COSTS.has(next_level):
		return {"maxed": true, "level": level}
	var costs: Dictionary = EconomyConfig.WAREHOUSE_UPGRADE_COSTS[next_level]
	var materials: Array = []
	var market_total := 0.0
	var empire_ok := true
	for good_id in costs:
		var qty := int(costs[good_id])
		var have := Stockpile.get_total(str(good_id))
		var quote := TransportService.quote_market_buy(tile_id, str(good_id), qty, TransportState.seaport_would_cover(str(good_id)))
		var cost := float(quote.get("cost", float(qty) * MarketState.get_buy_price(str(good_id))))
		materials.append({"good_id": str(good_id), "qty": qty, "have_empire": have, "market_cost": cost})
		market_total += cost
		if have < qty:
			empire_ok = false
	return {
		"maxed": false, "level": level, "next_level": next_level,
		"current_cap": int(EconomyConfig.WAREHOUSE_STORAGE_CAP.get(level, Stockpile.TILE_CAPACITY)),
		"next_cap": int(EconomyConfig.WAREHOUSE_STORAGE_CAP.get(next_level, Stockpile.TILE_CAPACITY)),
		"materials": materials, "market_total": market_total,
		"empire_ok": empire_ok, "money_ok": market_total <= money,
	}

## Commit the expansion. source = "market" (pay cash at ask + freight; the materials
## are consumed by the works, nothing ships) or "empire" (pull the bill from stock
## across the player's tiles). Applies immediately, like road/rail infra purchases.
func upgrade_warehouse(tile_id: String, source: String) -> Dictionary:
	var q := warehouse_upgrade_quote(tile_id)
	if bool(q.get("maxed", false)):
		return {"ok": false, "reason": "maxed"}
	var next_level := int(q.get("next_level", 0))
	var materials: Array = q.get("materials", [])
	match source:
		"market":
			var total := float(q.get("market_total", 0.0))
			if total > money:
				return {"ok": false, "reason": "money"}
			add_money(-total)
			for m in materials:
				# Deficit feed: these are real market purchases (price impact applies).
				MarketState.record_market_buy_volume(str(m.good_id), int(m.qty))
			goods_movement_recorded.emit("buy", "upgrade", 0)
		"empire":
			for m in materials:
				if Stockpile.get_total(str(m.good_id)) < int(m.qty):
					return {"ok": false, "reason": "materials"}
			for m in materials:
				Stockpile.consume_anywhere(str(m.good_id), int(m.qty))
		_:
			return {"ok": false, "reason": "unknown_source"}
	Stockpile.set_warehouse_level(tile_id, next_level)
	request_toast("Warehouse expanded to level %d — %d storage" % [next_level, int(q.get("next_cap", 0))], "success")
	return {"ok": true, "level": next_level, "capacity": int(q.get("next_cap", 0))}

func get_oneoff_transaction_rows() -> Array:
	var rows: Array = []
	for t in transaction_log:
		rows.append(_txn_row(str(t.get("kind", "sell")), Catalog.get_display_name(str(t.get("good_id", ""))),
			int(t.get("qty", 0)), str(t.get("tile_from", "")), str(t.get("tile_to", "")),
			int(t.get("turn_started", 0)), int(t.get("turn_ended", -1))))
	return rows

func get_recurring_transaction_rows() -> Array:
	var rows: Array = []
	for m in recurring_sells:
		var port := TransportService.nearest_port_tile(str(m.get("source", "")))
		for gid in m.get("goods", {}).keys():
			rows.append(_txn_row("sell", Catalog.get_display_name(str(gid)), int(m.goods[gid]),
				str(m.get("source", "")), port, int(m.get("turn_started", 0)), -1))
	for r in recurring_bulk_sells:
		var p: Dictionary = r.get("params", {})
		var good_label := "All goods" if str(p.get("good_id", "")) == "" else Catalog.get_display_name(str(p.get("good_id", "")))
		if bool(p.get("finished_only", false)):
			good_label += " (finished)"
		rows.append(_txn_row("sell", good_label, -1, "All tiles", "Market", int(r.get("turn_started", 0)), -1))
	for b in recurring_buys:
		rows.append(_txn_row("buy", Catalog.get_display_name(str(b.get("good", ""))), int(b.get("qty", 0)),
			TransportService.nearest_port_tile(str(b.get("dest", ""))), str(b.get("dest", "")), int(b.get("turn_started", 0)), -1))
	return rows


func _is_finished_good(good_id: String) -> bool:
	# No explicit "finished" tier in the MVP, so "finished/manufactured" = non-raw, non-power.
	var gt := str(Catalog.get_good(good_id).get("good_type", ""))
	return gt != "" and gt != "raw" and gt != "power"

func sell_all_to_market(params: Dictionary, log_oneoff: bool = true) -> Dictionary:
	# Stories 4 & 5: sweep every tile's stockpile and sell to the nearest port, filtered by
	#   good_id     ("" = all goods, else a specific good)
	#   finished_only (only manufactured/non-raw goods)
	#   per_tile_keep (leave this many of each good per tile; sell the surplus above it)
	var good_filter := str(params.get("good_id", ""))
	var finished_only := bool(params.get("finished_only", false))
	var keep: int = maxi(0, int(params.get("per_tile_keep", 0)))
	var total_qty := 0
	var total_revenue := 0.0
	var tiles_sold := 0
	for tile_key in Stockpile.tiles_with_stock():
		var tile_id := str(tile_key)
		if not tile_id.begins_with("tile_"):
			continue
		var totals: Dictionary = Stockpile.get_tile_totals(tile_id)
		var goods_qtys: Dictionary = {}
		for gid in totals.keys():
			var g := str(gid)
			if not Catalog.is_good_sellable(g):
				continue
			if good_filter != "" and g != good_filter:
				continue
			if finished_only and not _is_finished_good(g):
				continue
			var surplus := int(totals[gid]) - keep
			if surplus > 0:
				goods_qtys[g] = surplus
		if goods_qtys.is_empty():
			continue
		var summary := queue_sell(tile_id, goods_qtys, log_oneoff)
		if not summary.is_empty():
			total_qty += int(summary.get("total_qty", 0))
			total_revenue += float(summary.get("revenue", 0.0))
			tiles_sold += 1
	return {"total_qty": total_qty, "revenue": total_revenue, "tiles": tiles_sold}

func queue_sell(source_tile: String, goods_qtys: Dictionary, log_oneoff: bool = true) -> Dictionary:
	# Sell specific goods/qtys from a tile: consume from the stockpile, ship to the
	# nearest port, pay out on arrival. All of that lives in MarketState.execute_sale
	# now; this wrapper preserves the public API (note: returns `revenue`, not
	# `total_revenue`, for back-compat with existing callers).
	var result := MarketState.execute_sale(source_tile, goods_qtys, {"log_oneoff": log_oneoff})
	if result.is_empty():
		return {}
	Production.record_external_transport_cost(float(result.get("transport_cost", 0.0)), result.get("transport_breakdown", {}))
	if not bool(result.get("deferred", false)):
		var sale_record: Dictionary = result.get("sale_record", {})
		record_tile_sale(source_tile, int(result.get("total_qty", 0)), float(result.get("total_revenue", 0.0)))
		Production.record_external_goods_sale(sale_record)
	return {
		"items": result.items,
		"total_qty": result.total_qty,
		"revenue": result.total_revenue,
		"turns": result.turns,
		"port": result.port,
		"deferred": result.deferred,
	}


## Clear per-turn sales at the start of each turn's processing.
func reset_tile_sales_for_turn() -> void:
	sales_by_tile.clear()

## Record a realised market sale shipped from a source tile (units + £ revenue).
func record_tile_sale(tile_id: String, units: int, revenue: float) -> void:
	if tile_id == "" or (units <= 0 and revenue <= 0.0):
		return
	var rec: Dictionary = sales_by_tile.get(tile_id, {"units": 0, "revenue": 0.0})
	rec["units"] = int(rec.get("units", 0)) + units
	rec["revenue"] = float(rec.get("revenue", 0.0)) + revenue
	sales_by_tile[tile_id] = rec

func get_tile_sales(tile_id: String) -> Dictionary:
	return sales_by_tile.get(tile_id, {"units": 0, "revenue": 0.0})


func enable_sell_surplus(tile_id: String) -> void:
	if tile_id == "" or sell_surplus_tiles.has(tile_id):
		return
	sell_surplus_tiles[tile_id] = true
	sell_surplus_changed.emit(tile_id)

func disable_sell_surplus(tile_id: String) -> void:
	if tile_id == "" or not sell_surplus_tiles.has(tile_id):
		return
	sell_surplus_tiles.erase(tile_id)
	sell_surplus_changed.emit(tile_id)

func is_sell_surplus_enabled(tile_id: String) -> bool:
	return sell_surplus_tiles.has(tile_id)

func get_sell_surplus_tiles() -> Array:
	return sell_surplus_tiles.keys()

# --- Per-good auto-sell (a standing order to sell a specific good's surplus every turn) ---

func enable_auto_sell_good(tile_id: String, good_id: String) -> void:
	if tile_id == "" or good_id == "":
		return
	if not auto_sell_goods.has(tile_id):
		auto_sell_goods[tile_id] = {}
	if auto_sell_goods[tile_id].has(good_id):
		return
	auto_sell_goods[tile_id][good_id] = true
	sell_surplus_changed.emit(tile_id)

func disable_auto_sell_good(tile_id: String, good_id: String) -> void:
	if not auto_sell_goods.has(tile_id):
		return
	if auto_sell_goods[tile_id].erase(good_id):
		if (auto_sell_goods[tile_id] as Dictionary).is_empty():
			auto_sell_goods.erase(tile_id)
		sell_surplus_changed.emit(tile_id)

func is_auto_sell_good(tile_id: String, good_id: String) -> bool:
	return auto_sell_goods.get(tile_id, {}).has(good_id)

# "Sell all except X": units of a good the auto-sell always leaves on the tile,
# on top of whatever the tile's own buildings claim as inputs.
func set_auto_sell_keep(tile_id: String, good_id: String, keep: int) -> void:
	if tile_id == "" or good_id == "":
		return
	if keep <= 0:
		if auto_sell_keep.has(tile_id):
			(auto_sell_keep[tile_id] as Dictionary).erase(good_id)
			if (auto_sell_keep[tile_id] as Dictionary).is_empty():
				auto_sell_keep.erase(tile_id)
	else:
		if not auto_sell_keep.has(tile_id):
			auto_sell_keep[tile_id] = {}
		auto_sell_keep[tile_id][good_id] = keep
	sell_surplus_changed.emit(tile_id)

func auto_sell_keep_for(tile_id: String, good_id: String) -> int:
	return int((auto_sell_keep.get(tile_id, {}) as Dictionary).get(good_id, 0))

func get_auto_sell_good_tiles() -> Array:
	return auto_sell_goods.keys()

func should_auto_sell_good(tile_id: String, good_id: String) -> bool:
	# A good auto-sells if the master "sell everything" order is on for the tile,
	# or it has an explicit per-good auto-sell override.
	return sell_surplus_tiles.has(tile_id) or auto_sell_goods.get(tile_id, {}).has(good_id)

func get_auto_sell_tiles() -> Array:
	# Union of tiles with the master order and tiles with any per-good override.
	var tiles: Dictionary = {}
	for t in sell_surplus_tiles.keys():
		tiles[t] = true
	for t in auto_sell_goods.keys():
		tiles[t] = true
	return tiles.keys()

func set_auto_sell_impact(tile_id: String, max_pct: int) -> void:
	# max_pct is the largest per-turn price impact the auto-sell may cause (or IMPACT_ANY for no cap).
	if tile_id == "":
		return
	auto_sell_impact[tile_id] = max_pct
	sell_surplus_changed.emit(tile_id)

func get_auto_sell_impact(tile_id: String) -> int:
	return int(auto_sell_impact.get(tile_id, IMPACT_ANY))

func auto_sell_unit_cap(tile_id: String) -> int:
	# Per-turn, per-good sell cap implied by the tile's price-impact tolerance.
	# Returns a very large number when ANY impact is allowed (effectively uncapped).
	var impact: int = get_auto_sell_impact(tile_id)
	if impact == IMPACT_ANY:
		return 1 << 30
	return EconomyConfig.units_cap_for_impact(impact)


# governing tier -> multiplier on base_pct. 3 = full, 2 = half, 1 = half malus.
const _TIER_MULT := {3: 1.0, 2: 0.5, 1: -0.5, 0: 0.0}


# Assign a HIRED, rostered advisor to a seat. Enforces the slot cap and
# one-seat-per-advisor. Returns false if rejected.
## Building operational loans (spec §5.3). A newly CONSTRUCTED building has no cash flow yet,
## so its first TAB_WINDOW_TURNS of running costs are carried rather than paid: each turn they
## are charged as normal and then refunded onto the tab, which keeps every existing cost site
## and the money panel's ledger honest instead of diverting four separate charge paths.
##
## Exposure is bounded by construction — exactly five turns — which is why the earlier
## open-ended version's 1x-capex cap and forced sale are gone. Requires a seated CFO: with no
## one to arrange it, costs simply hit cash as before.
const TAB_WINDOW_TURNS := 5
const TAB_SLICES := 12
## What to do when a build's credit facility comes up: "ask" raises the dialog, the other three
## answer it silently. Stored beside the other construct-panel defaults.
const CREDIT_DEFAULT_CHOICES: Array[String] = ["ask", "slices", "loan", "none"]
var construct_credit_default: String = "ask"

func set_construct_credit_default(value: String) -> void:
	if not CREDIT_DEFAULT_CHOICES.has(value) or value == construct_credit_default:
		return
	construct_credit_default = value
	construct_settings_changed.emit()
var building_tabs: Dictionary = {}   # instance_id -> {turns_left, accrued, mode, slices_left}


func can_open_building_tab() -> bool:
	return cfo_seated()


## Start carrying a building's running costs. Called the turn BEFORE it completes, because that
## is when its inputs are ordered and the first money moves.
func open_building_tab(instance_id: String, mode: String = "slices") -> bool:
	if not can_open_building_tab() or instance_id == "" or building_tabs.has(instance_id):
		return false
	building_tabs[instance_id] = {
		"turns_left": TAB_WINDOW_TURNS, "accrued": 0.0,
		"mode": mode, "slices_left": 0,
	}
	return true


## The player's answer to the credit offer. "none" closes the tab so this building's costs hit
## cash exactly as they would have without the facility.
func set_building_tab_mode(instance_id: String, mode: String) -> void:
	if not building_tabs.has(instance_id):
		return
	if mode == "none":
		building_tabs.erase(instance_id)
		return
	var tab: Dictionary = building_tabs[instance_id]
	tab["mode"] = mode
	building_tabs[instance_id] = tab


func building_tab_debt(instance_id: String) -> float:
	return float((building_tabs.get(instance_id, {}) as Dictionary).get("accrued", 0.0))


## What a building's tab actually takes each turn, and for how many more turns — the pair the
## detail panel shows, because "you owe £900" tells a player nothing about whether they can
## afford it, while "£75 a turn for 12 turns" is the thing they budget against.
##
## Inside the interest-free window nothing is repaid yet, so the schedule quoted is the one it
## WILL run to (the accrued total over TAB_SLICES) and `starts_in` counts the turns until the
## first slice. Once repayment begins the slice is constant: each turn takes accrued/slices_left
## and decrements both, which leaves the quotient where it was.
func building_tab_repayment(instance_id: String) -> Dictionary:
	var tab: Dictionary = building_tabs.get(instance_id, {})
	var accrued := float(tab.get("accrued", 0.0))
	if tab.is_empty() or accrued <= 0.0:
		return {"accrued": 0.0, "per_turn": 0.0, "turns_left": 0, "starts_in": 0}
	var slices := int(tab.get("slices_left", 0))
	if slices > 0:
		return {"accrued": accrued, "per_turn": accrued / float(slices),
			"turns_left": slices, "starts_in": 0}
	return {"accrued": accrued, "per_turn": accrued / float(TAB_SLICES),
		"turns_left": TAB_SLICES, "starts_in": int(tab.get("turns_left", 0))}


## Everything the player still owes across every building tab — the money panel's row.
func total_building_tab_debt() -> float:
	var total := 0.0
	for iid in building_tabs:
		total += float(building_tabs[iid].get("accrued", 0.0))
	return total


## Carry one turn of a building's running costs. Returns the amount refunded onto the tab, which
## the caller credits back so the turn's cash matches what the player actually paid.
func accrue_building_tab(instance_id: String, amount: float) -> float:
	var tab: Dictionary = building_tabs.get(instance_id, {})
	if tab.is_empty() or int(tab.get("turns_left", 0)) <= 0 or amount <= 0.0:
		return 0.0
	tab["accrued"] = float(tab.get("accrued", 0.0)) + amount
	building_tabs[instance_id] = tab
	return amount


## End of turn: wind the window down and settle any tab that has run its course.
func tick_building_tabs() -> void:
	for iid in building_tabs.keys():
		var tab: Dictionary = building_tabs[iid]
		var left := int(tab.get("turns_left", 0))
		if left > 0:
			tab["turns_left"] = left - 1
			if tab["turns_left"] == 0:
				_settle_building_tab(str(iid), tab)
				# Settling may have closed the tab outright (the loan route converts and
				# erases). Writing it back unconditionally would resurrect it.
				if not building_tabs.has(iid):
					continue
			building_tabs[iid] = tab
			continue
		# Repayment: one interest-free slice a turn until it is cleared.
		if str(tab.get("mode", "slices")) == "slices" and int(tab.get("slices_left", 0)) > 0:
			var slice: float = float(tab.get("accrued", 0.0)) / float(tab.get("slices_left", 1))
			add_money(-slice)
			tab["accrued"] = maxf(0.0, float(tab.get("accrued", 0.0)) - slice)
			tab["slices_left"] = int(tab.get("slices_left", 0)) - 1
			building_tabs[iid] = tab
			if int(tab["slices_left"]) <= 0 or float(tab["accrued"]) <= 0.01:
				building_tabs.erase(iid)


func _settle_building_tab(instance_id: String, tab: Dictionary) -> void:
	var owed := float(tab.get("accrued", 0.0))
	if owed <= 0.0:
		building_tabs.erase(instance_id)
		return
	if str(tab.get("mode", "slices")) == "loan":
		# Converts to an ordinary loan — smaller payments, but it carries interest.
		LoanState.take_distress_loan(owed)
		building_tabs.erase(instance_id)
		return
	tab["slices_left"] = TAB_SLICES


## Purchased buildings arrive with PURCHASE_SEED_TURNS of their recipe's inputs — a going
## concern comes with stock, where a fresh build comes with a ramp to finance (§5.3's tab).
## Infra and input-less recipes get nothing: there is no inventory to seed.
const PURCHASE_SEED_TURNS := 2
## Goods that could not fit in the tile when a purchase was seeded. They exist, the player can
## see them on the building's detail panel, and NOTHING else can draw on them — they drain into
## the tile as real capacity frees up. instance_id -> {good_id: qty}
var ghost_holdings: Dictionary = {}


## What the stock a purchase arrives with is worth at market. The buyer pays for PURCHASE_SEED_
## TURNS of it — an advisor may hand over a THIRD turn's worth, but the two are always paid for.
func purchase_kit_cost(building: Dictionary) -> float:
	var recipe: Dictionary = Catalog.get_recipe(str(building.get("recipe_id", "")))
	var total := 0.0
	for input in recipe.get("inputs", []):
		var gid := str(input.get("good_id", ""))
		if gid != "":
			total += float(int(input.get("qty", 0)) * PURCHASE_SEED_TURNS) * MarketState.get_buy_price(gid)
	return total


## The full asking price for an NPC building: the advisor-adjusted sale value plus the stock it
## comes with. One helper so the listing, the Buy button and the charge cannot disagree.
func building_purchase_price(building: Dictionary) -> int:
	return int(round(
		AdvisorState.purchase_cost_after_advisor(float(BuildingPrice.sale_price(building)))
		+ purchase_kit_cost(building)))


## How many turns of inputs a purchase actually receives. The player pays for PURCHASE_SEED_
## TURNS; a seated COO throws in one more (§5.4) — a gift of goods, not a discount on price.
func purchase_seed_turns() -> int:
	return PURCHASE_SEED_TURNS + (1 if AdvisorState.get_advisor_in_seat("coo") != "" else 0)


## Seed a newly-bought building with stock. Returns the total units seeded (0 for infra, for
## input-less recipes, and for a building that already has its own stock on the tile).
func seed_purchase_inventory(instance_id: String) -> int:
	var building: Dictionary = BuildingState.buildings.get(instance_id, {})
	if building.is_empty():
		return 0
	var recipe: Dictionary = Catalog.get_recipe(str(building.get("recipe_id", "")))
	var inputs: Array = recipe.get("inputs", [])
	if inputs.is_empty():
		return 0
	var tile_id := str(building.get("tile_id", ""))
	if tile_id == "":
		return 0
	var seeded := 0
	for input in inputs:
		var gid := str(input.get("good_id", ""))
		var qty := int(input.get("qty", 0)) * purchase_seed_turns()
		if gid == "" or qty <= 0:
			continue
		var placed: int = Stockpile.add(tile_id, gid, qty)
		seeded += qty
		var overflow := qty - placed
		if overflow > 0:
			_add_ghost_holding(instance_id, gid, overflow)
	return seeded


func _add_ghost_holding(instance_id: String, good_id: String, qty: int) -> void:
	if qty <= 0:
		return
	var held: Dictionary = ghost_holdings.get(instance_id, {})
	held[good_id] = int(held.get(good_id, 0)) + qty
	ghost_holdings[instance_id] = held
	print("[Purchase] %s: %d %s held off-tile (no room) — will move in as space frees" % [
		instance_id, qty, good_id])


## What is waiting off-tile for this building, for its detail panel's
## "x units stored for this building" line.
func ghost_holding_for(instance_id: String) -> Dictionary:
	return (ghost_holdings.get(instance_id, {}) as Dictionary).duplicate()


func ghost_holding_units(instance_id: String) -> int:
	var total := 0
	for gid in (ghost_holdings.get(instance_id, {}) as Dictionary):
		total += int(ghost_holdings[instance_id][gid])
	return total


## Move held goods onto the tile as capacity allows. Called each turn before production, so a
## building that could not be fully stocked on purchase fills up as it consumes what it has.
func drain_ghost_holdings() -> void:
	if ghost_holdings.is_empty():
		return
	for instance_id in ghost_holdings.keys():
		var building: Dictionary = BuildingState.buildings.get(str(instance_id), {})
		if building.is_empty():
			ghost_holdings.erase(instance_id)   # building gone; the goods go with it
			continue
		var tile_id := str(building.get("tile_id", ""))
		var held: Dictionary = ghost_holdings[instance_id]
		for gid in held.keys():
			var want := int(held[gid])
			if want <= 0:
				held.erase(gid)
				continue
			var placed: int = Stockpile.add(tile_id, str(gid), want)
			if placed > 0:
				held[gid] = want - placed
			if int(held.get(gid, 0)) <= 0:
				held.erase(gid)
		if held.is_empty():
			ghost_holdings.erase(instance_id)
		else:
			ghost_holdings[instance_id] = held


func _match_rng_int(max_exclusive: int) -> int:
	if max_exclusive <= 0:
		return 0
	return _match_rng.randi_range(0, max_exclusive - 1)


# Debug cheat: add cash, tracked as "fake money" for the turn summary.
func cheat_add_cash(amount: float) -> void:
	add_money(amount)
	fake_money_this_turn += amount

## Sticky taint flag for telemetry — set by the debug terminal for any command that can
## move the sim. Once set it rides the save for the rest of the match.
func note_cheat_used() -> void:
	cheats_used = true


# --- Workforce / agenda hooks that stay sim-side (they feed AdvisorState) ---

# Record a build this turn (drives the idle-building + build-while-unprofitable agendas).
func note_building_built() -> void:
	AdvisorState._agenda_last_build_turn = int(TurnManager.current_turn)
	AdvisorState._agenda_flags["_built"] = true


# --- Text helpers ---

func _roman(n: int) -> String:
	return ["", "I", "II", "III", "IV", "V"][clampi(n, 0, 5)]


func _signed_percent_text(value: float) -> String:
	var sign := "+" if value > 0.0 else ""
	return "%s%.0f%%" % [sign, value]

