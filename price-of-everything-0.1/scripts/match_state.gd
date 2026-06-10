extends Node

# MatchState: the canonical store for everything that changes during a match.
# Other systems read and write here; never store match data elsewhere.

# --- Player resources ---
const LOCAL_PLAYER := "player_1"
var money: float = 1000.0  # was: int = 1000

# --- Ruleset ---
# Which rule variant this match plays under. Carried in saves and start configs so
# future rule changes (scoring, brakes, era pacing, …) can key off it; only "name"
# is defined today — add per-rule keys beside it as rules become real.
const DEFAULT_RULESET := {"name": "standard"}
var ruleset: Dictionary = DEFAULT_RULESET.duplicate(true)

const DEFAULT_TILE_LAND_OWNED := 100
const LAND_PATCH_SIZE := 10
const LAND_PATCH_COST := 10.0
const MAX_TILE_LAND := 200

# --- Building instances ---
# Flat dictionary: instance_id -> building data dict
# Building data: {instance_id, building_id, recipe_id, tile_coord, owner}
var buildings: Dictionary = {}

# --- Tile occupancy index (derived from buildings, kept in sync) ---
# tile_id -> Array of instance_ids
# This is for fast "what's on this tile" queries.
var tile_buildings: Dictionary = {}

# --- Instance ID generation ---
var _next_instance_counter: int = 0

# --- Labour Slider ---
var labour_multiplier: float = EconomyConfig.LABOUR_MULTIPLIER_DEFAULT

# --- Output routing ---
var output_stockpile_destinations: Dictionary = {}  # instance_id -> {tile_id, good_id}
const MARKET_DESTINATION := "__market__"  # sentinel tile_id: route this building's output to market
var input_tile_only: Dictionary = {}  # "instance_id|good_id" -> true (tile stockpile ONLY; default buys from market)
var pending_output_stockpile_selection: Dictionary = {}
var queued_stockpile_market_sales: Dictionary = {}  # tile_id -> true
var sell_surplus_tiles: Dictionary = {}              # tile_id -> true (master: auto-sell ALL surplus goods)
var auto_sell_goods: Dictionary = {}                 # tile_id -> { good_id -> true } (per-good auto-sell overrides)
const IMPACT_ANY := -1                               # auto-sell tolerance sentinel: no per-turn volume cap
var auto_sell_impact: Dictionary = {}                # tile_id -> max price-impact % tolerated per turn (or IMPACT_ANY)
var pending_transport_shipments: Array = []
# Shipments that arrived at a destination tile whose stockpile was full and so
# couldn't unload. They wait here and retry each turn until there's room.
# Record: {source_tile, destination_tile, good_id, qty, turns_waiting, construction_instance_id}
var overflow_shipments: Array = []
# Realised market sales per source tile THIS TURN: tile_id -> {units, revenue}.
# Reset at the start of each turn's processing so the figure is per-turn, not
# accumulated.
var sales_by_tile: Dictionary = {}
var _shipment_id_counter: int = 0
var recurring_moves: Array = []   # [{source, dest, goods}] re-issued every turn
var scheduled_moves: Array = []   # [{source, dest, goods}] one-shot, fired next turn (e.g. split)
var recurring_sells: Array = []   # [{source, goods}] re-sold to the nearest port every turn
var recurring_bulk_sells: Array = []  # [{params, turn_started}] re-run via sell_all_to_market every turn
var recurring_buys: Array = []  # [{dest, good, qty}] re-bought from market every turn
# View-only ledgers for the Transactions / Movements tabs (one-off entries; recurring
# rules are read from the recurring_* arrays). Rows: {good_id, qty, tile_from, tile_to,
# turn_started, turn_ended} (+ kind for transactions).
var transaction_log: Array = []
var move_log: Array = []
const LEDGER_MAX := 500  # keep the newest N entries so the logs stay bounded
const LARGE_SHIPMENT_THRESHOLD := 500
const LARGE_SHIPMENT_SURCHARGE := 2.0   # >500 units in one move costs 2x transport (tunable)
var tile_land_owned: Dictionary = {}

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

# Research unlocks: which are unlocked (by free choice or by meeting a condition),
# and progress toward the action+object+quantity conditions (e.g. "Survey|tiles").
var unlocked_titles: Dictionary = {}
var _unlock_progress: Dictionary = {}
var _unlock_defs: Array = []   # [{title, action, object, qty, prereqs, description}]
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

# Debug-only: when true the alternate tabbed Tile View Panel (TVP v2) is shown
# instead of the classic one. Toggled at runtime via the `swap tvp` cheat.
# Session-only; never persisted. Defaults to the alternate panel; `swap tvp`
# flips back to the classic one.
var use_alt_tvp: bool = true

# Debug-only: when true the bottom menu shows the alternate icon set instead of
# the old circular icon set. Toggled at runtime via the `swap bottom menu` cheat.
# Session-only; never persisted. Defaults to the white-rimmed alternate buttons.
var use_alt_bottom_menu: bool = true

# --- Signals ---
signal money_changed(new_amount: float) 
signal building_added(instance: Dictionary)
signal building_removed(instance_id: String)
signal state_reset
signal sell_mode_changed(new_mode: int)
signal route_objective_changed(new_objective: int)
signal labour_multiplier_changed(new_value: float)
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
## Market row "Move" — start the on-map transfer flow for this good.
signal transfer_for_good_requested(good_id: String)
## Market-row "Purchase" asked to open the per-good buy flow.
signal purchase_for_good_requested(good_id: String)
## A UI element asked to open an Encyclopedia entry (e.g. a "More info" link).
signal encyclopedia_entry_requested(entry_id: String)
signal output_stockpile_selection_started(selection: Dictionary)
signal output_stockpile_selection_cancelled
signal output_stockpile_destination_changed(instance_id: String, tile_id: String, good_id: String)
signal stockpile_market_sale_queue_changed(tile_id: String)
signal stockpile_market_sale_completed(sale_record: Dictionary)
signal sell_surplus_changed(tile_id: String)
signal transport_shipments_changed
signal tile_land_owned_changed(tile_id: String)
## The set of surveyed tiles changed (drives the Surveying mapmode + tile panel).
signal surveyed_tiles_changed
## A tile's in-progress survey changed (started / ticked down / finished).
signal surveying_in_progress_changed
## A tile's deposit remaining amount changed (depleted by mining).
signal deposits_changed(tile_id: String)
## A tile's deposit just reached 0 this turn (fires once, on the 0 transition).
signal deposit_exhausted(tile_id: String, token: String)
## A research unlock was granted. via_condition is true when earned by meeting its
## condition (shows the "Unlocked …" dialog); false for a free-chosen unlock.
signal unlock_granted(title: String, description: String, via_condition: bool)
## A tile finished being surveyed (drives the on-map survey animation). deposit_goods
## is an array of {good_id, internal_name} for the non-water deposits revealed.
signal tile_survey_completed(tile_id: String, deposit_goods: Array)
## A shipment arrived at a full tile and is now waiting to unload.
signal overflow_shipment_held(record: Dictionary)
## Debug cheat `swap tvp` flipped which Tile View Panel is active.
signal alt_tvp_changed(enabled: bool)
## Debug cheat `swap bottom menu` flipped which bottom-menu icon set is active.
signal alt_bottom_menu_changed(enabled: bool)

# --- Initialization ---
func _ready() -> void:
	money = EconomyConfig.STARTING_MONEY
	money_changed.emit(money)
	_load_unlock_defs()
	# TurnManager is registered after MatchState, so wire the per-turn survey tick
	# once every autoload exists.
	call_deferred("_connect_turn_signals")

func _connect_turn_signals() -> void:
	if TurnManager != null and not TurnManager.phase_started.is_connected(_on_survey_phase_started):
		TurnManager.phase_started.connect(_on_survey_phase_started)

func _on_survey_phase_started(phase: int) -> void:
	if phase == TurnManager.Phase.PROCESS:
		tick_surveys()
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

# --- Public API: buildings ---
func is_player_owned(building: Dictionary) -> bool:
	# NPC-owned infrastructure (e.g. the shipping corporation's ports) is not the
	# player's to pay for. Buildings default to the local player when owner is unset.
	return str(building.get("owner", LOCAL_PLAYER)) == LOCAL_PLAYER

func add_building(building_id: String, recipe_id: String, tile_id: String, owner: String = "player_1", instance_id: String = "") -> String:
	# Pass the building_id here! An explicit instance_id lets a construction project keep one
	# stable id from placement through completion; empty means generate a fresh one.
	if instance_id == "":
		instance_id = _generate_instance_id(building_id)

	var instance := {
		"instance_id": instance_id,
		"building_id": building_id,
		"recipe_id": recipe_id,
		"tile_id": tile_id,
		"owner": owner,
	}
	
	buildings[instance_id] = instance
	
	# Update tile index
	if not tile_buildings.has(tile_id):
		tile_buildings[tile_id] = []
	tile_buildings[tile_id].append(instance_id)
	
	building_added.emit(instance)
	return instance_id

func remove_building(instance_id: String) -> bool:
	if not buildings.has(instance_id):
		return false
	
	var instance: Dictionary = buildings[instance_id]
	var tile_id: String = instance.tile_id
	
	# Remove from tile index
	if tile_buildings.has(tile_id):
		tile_buildings[tile_id].erase(instance_id)
		if tile_buildings[tile_id].is_empty():
			tile_buildings.erase(tile_id)
	
	buildings.erase(instance_id)
	output_stockpile_destinations.erase(instance_id)
	building_removed.emit(instance_id)
	return true

func get_buildings_on_tile(tile_id: String) -> Array:
	# Returns an Array of building instance dicts on the given tile.
	if not tile_buildings.has(tile_id):
		return []
	
	var result: Array = []
	for instance_id in tile_buildings[tile_id]:
		if buildings.has(instance_id):
			result.append(buildings[instance_id])
	return result

func get_tile_space_used(tile_id: String) -> float:
	var total := 0.0
	for instance in get_buildings_on_tile(tile_id):
		var building_id: String = instance.get("building_id", "")
		var building_data := Catalog.get_building(building_id)
		total += float(building_data.get("tile_size_used", 1.0))
	# Pending construction projects reserve their footprint up front (Phase 1: none linger).
	total += Construction.reserved_space_on_tile(tile_id)
	return total

# --- Public API: survey state ---
## Seed the surveyed set with the NPC port tiles (called once at match start).
func seed_surveyed_ports() -> void:
	for port in Catalog.all_ports():
		var tile_id := str(port.get("tile_id", ""))
		if tile_id != "":
			surveyed_tiles[tile_id] = true
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
	record_unlock_progress("Survey", "tiles", 1)
	record_unlock_progress("Survey", "deposits", found.size())
	tile_survey_completed.emit(tile_id, found)
	request_toast(_survey_toast(tile_id, found), "info")
	if not reveal_nearby:
		return
	# A full survey auto-(partially-)surveys a neighbour; Spectral Crystallography
	# reveals one extra ("+1 adjacent tile revealed when surveying").
	var reveals := 2 if is_unlocked("Spectral Crystallography") else 1
	for _i in reveals:
		var fresh: Array = []
		for n in Catalog.tile_neighbours(tile_id):
			if not surveyed_tiles.has(n) and not partially_surveyed_tiles.has(n) and not surveying_in_progress.has(n):
				fresh.append(n)
		if fresh.is_empty():
			break
		mark_tile_partial(str(fresh[randi() % fresh.size()]))

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
			if token == "" or token == "water" or qty <= 0:
				continue
			if not deposit_remaining.has(tid):
				deposit_remaining[tid] = {}
			deposit_remaining[tid][token] = qty

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

# --- Public API: research unlocks ---
func _load_unlock_defs() -> void:
	_unlock_defs.clear()
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
		var prereqs: Array = []
		for col in ["prereq_1", "prereq_2", "prereq_3"]:
			var p := _csv_at(row, idx, col)
			if p != "":
				prereqs.append(p)
		var q := _csv_at(row, idx, "Quantity")
		_unlock_defs.append({
			"title": _csv_at(row, idx, "title"),
			"action": _csv_at(row, idx, "Action"),
			"object": _csv_at(row, idx, "Object"),
			"qty": int(q) if q.is_valid_int() else 0,
			"prereqs": prereqs,
			"description": _csv_at(row, idx, "description"),
		})
	f.close()

func _csv_at(row: PackedStringArray, idx: Dictionary, col: String) -> String:
	if not idx.has(col):
		return ""
	var i: int = idx[col]
	return row[i].strip_edges() if i < row.size() else ""

func is_unlocked(title: String) -> bool:
	return unlocked_titles.has(title)

## Grant an unlock. via_condition true => earned by its condition (drives the
## "Unlocked …" dialog); false => a free-chosen unlock (no dialog).
func grant_unlock(title: String, via_condition: bool = false) -> void:
	if title == "" or unlocked_titles.has(title):
		return
	unlocked_titles[title] = true
	_surveyable_dirty = true  # e.g. Geoscanning changes survey range
	var desc := ""
	for d in _unlock_defs:
		if str(d.title) == title:
			desc = str(d.description)
			break
	unlock_granted.emit(title, desc, via_condition)

## Record progress toward action+object conditions (e.g. record("Survey","tiles")).
func record_unlock_progress(action: String, object: String, amount: int = 1) -> void:
	if amount <= 0:
		return
	var key := (action + "|" + object).to_lower()
	_unlock_progress[key] = int(_unlock_progress.get(key, 0)) + amount
	_check_unlock_conditions()

func _check_unlock_conditions() -> void:
	for d in _unlock_defs:
		var title := str(d.title)
		if title == "" or unlocked_titles.has(title) or int(d.qty) <= 0:
			continue
		if str(d.action) == "" or str(d.object) == "":
			continue
		var prereqs_met := true
		for p in d.prereqs:
			if not unlocked_titles.has(str(p)):
				prereqs_met = false
				break
		if not prereqs_met:
			continue
		var key := (str(d.action) + "|" + str(d.object)).to_lower()
		if int(_unlock_progress.get(key, 0)) >= int(d.qty):
			grant_unlock(title, true)

# --- Public API: survey range ---
func survey_range() -> int:
	return SURVEY_RANGE_BASE + (1 if is_unlocked("Computer Assisted Geoscanning") else 0)

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

func get_tile_land_owned(tile_id: String) -> int:
	return int(tile_land_owned.get(tile_id, DEFAULT_TILE_LAND_OWNED))

func get_tile_land_patches_available(tile_id: String) -> int:
	var remaining := MAX_TILE_LAND - get_tile_land_owned(tile_id)
	return maxi(0, int(floor(float(remaining) / float(LAND_PATCH_SIZE))))

func purchase_tile_land(tile_id: String, patches: int = 1) -> bool:
	if tile_id == "":
		return false
	var available := get_tile_land_patches_available(tile_id)
	if available <= 0:
		return false
	var clamped_patches: int = clampi(patches, 1, available)
	var cost := float(clamped_patches) * LAND_PATCH_COST
	if not deduct_money(cost):
		return false
	var owned := get_tile_land_owned(tile_id)
	tile_land_owned[tile_id] = mini(MAX_TILE_LAND, owned + clamped_patches * LAND_PATCH_SIZE)
	tile_land_owned_changed.emit(tile_id)
	return true

func get_building(instance_id: String) -> Dictionary:
	# Returns the instance dict, or empty dict if not found
	return buildings.get(instance_id, {})

# --- Helpers ---
func _generate_instance_id(building_id: String) -> String:
	_next_instance_counter += 1
	# %s injects the string, %06x injects the hex counter
	return "inst_%s_%06x" % [building_id, _next_instance_counter]

# Public: reserve a unique instance id before the building exists. Used by Construction so a
# project keeps the same id from placement to completion.
func reserve_instance_id(building_id: String) -> String:
	return _generate_instance_id(building_id)

# --- Reset (useful for new game / testing) ---
func reset() -> void:
	money = 1000
	buildings.clear()
	tile_buildings.clear()
	output_stockpile_destinations.clear()
	pending_output_stockpile_selection.clear()
	queued_stockpile_market_sales.clear()
	sell_surplus_tiles.clear()
	auto_sell_goods.clear()
	auto_sell_impact.clear()
	pending_transport_shipments.clear()
	overflow_shipments.clear()
	sales_by_tile.clear()
	tile_land_owned.clear()
	recurring_moves.clear()
	scheduled_moves.clear()
	recurring_sells.clear()
	recurring_bulk_sells.clear()
	recurring_buys.clear()
	transaction_log.clear()
	move_log.clear()
	input_tile_only.clear()
	_next_instance_counter = 0
	ruleset = DEFAULT_RULESET.duplicate(true)
	state_reset.emit()

# --- Debug ---
func debug_dump() -> Dictionary:
	# Returns the full state as a dict, useful for save/load and debugging
	return {
		"money": money,
		"buildings": buildings.duplicate(true),
		"tile_buildings": tile_buildings.duplicate(true),
		"output_stockpile_destinations": output_stockpile_destinations.duplicate(true),
		"queued_stockpile_market_sales": queued_stockpile_market_sales.duplicate(true),
		"pending_transport_shipments": pending_transport_shipments.duplicate(true),
		"tile_land_owned": tile_land_owned.duplicate(true),
		"_next_instance_counter": _next_instance_counter,
	}

# --- Save/load (orchestrated by the SaveLoad autoload; docs/save_load_spec.md) ---

# Route geometry (tiles/path/legs) is stripped from shipments on save — it can hold
# Vector2s (not JSON-safe) and is purely visual; it is re-quoted from the live route
# graph on import so paths stay valid even if infrastructure changed.
const _SHIPMENT_ROUTE_KEYS: Array = ["tiles", "path", "legs"]

func export_state() -> Dictionary:
	return {
		"money": money,
		"ruleset": ruleset.duplicate(true),
		"next_instance_counter": _next_instance_counter,
		"shipment_id_counter": _shipment_id_counter,
		"buildings": buildings.duplicate(true),
		"tile_land_owned": tile_land_owned.duplicate(true),
		"labour_multiplier": labour_multiplier,
		"sell_mode": sell_mode,
		"route_objective": route_objective,
		"output_stockpile_destinations": output_stockpile_destinations.duplicate(true),
		"input_tile_only": input_tile_only.duplicate(true),
		"recurring_moves": recurring_moves.duplicate(true),
		"scheduled_moves": scheduled_moves.duplicate(true),
		"recurring_sells": recurring_sells.duplicate(true),
		"recurring_bulk_sells": recurring_bulk_sells.duplicate(true),
		"recurring_buys": recurring_buys.duplicate(true),
		"sell_surplus_tiles": sell_surplus_tiles.duplicate(true),
		"auto_sell_goods": auto_sell_goods.duplicate(true),
		"auto_sell_impact": auto_sell_impact.duplicate(true),
		"queued_stockpile_market_sales": queued_stockpile_market_sales.duplicate(true),
		"pending_transport_shipments": _shipments_for_save(),
		"overflow_shipments": overflow_shipments.duplicate(true),
		"transaction_log": transaction_log.duplicate(true),
		"move_log": move_log.duplicate(true),
		"surveyed_tiles": surveyed_tiles.duplicate(true),
		"partially_surveyed_tiles": partially_surveyed_tiles.duplicate(true),
		"surveying_in_progress": surveying_in_progress.duplicate(true),
		"surveying_reveal": surveying_reveal.duplicate(true),
		"revealed_deposits": revealed_deposits.duplicate(true),
		"deposit_remaining": deposit_remaining.duplicate(true),
		"unlocked_titles": unlocked_titles.duplicate(true),
		"unlock_progress": _unlock_progress.duplicate(true),
		"seaport_auto_subscribe": seaport_auto_subscribe,
		"seaport_subscribed": seaport_subscribed.duplicate(true),
	}

func import_state(d: Dictionary) -> void:
	# Silent full overwrite of every exported field — SaveLoad emits the refresh
	# signals once after every system has imported. Missing keys fall back to the
	# new-game default, so older/partial snapshots (and Phase 3 start configs) load.
	money = float(d.get("money", EconomyConfig.STARTING_MONEY))
	ruleset = (d.get("ruleset", DEFAULT_RULESET) as Dictionary).duplicate(true)
	_next_instance_counter = int(d.get("next_instance_counter", 0))
	_shipment_id_counter = int(d.get("shipment_id_counter", 0))
	buildings = (d.get("buildings", {}) as Dictionary).duplicate(true)
	tile_land_owned = (d.get("tile_land_owned", {}) as Dictionary).duplicate(true)
	labour_multiplier = float(d.get("labour_multiplier", EconomyConfig.LABOUR_MULTIPLIER_DEFAULT))
	sell_mode = int(d.get("sell_mode", SellMode.STOCKPILE_ALL))
	route_objective = int(d.get("route_objective", RouteObjective.FASTEST))
	output_stockpile_destinations = (d.get("output_stockpile_destinations", {}) as Dictionary).duplicate(true)
	input_tile_only = (d.get("input_tile_only", {}) as Dictionary).duplicate(true)
	recurring_moves = (d.get("recurring_moves", []) as Array).duplicate(true)
	scheduled_moves = (d.get("scheduled_moves", []) as Array).duplicate(true)
	recurring_sells = (d.get("recurring_sells", []) as Array).duplicate(true)
	recurring_bulk_sells = (d.get("recurring_bulk_sells", []) as Array).duplicate(true)
	recurring_buys = (d.get("recurring_buys", []) as Array).duplicate(true)
	sell_surplus_tiles = (d.get("sell_surplus_tiles", {}) as Dictionary).duplicate(true)
	auto_sell_goods = (d.get("auto_sell_goods", {}) as Dictionary).duplicate(true)
	auto_sell_impact = (d.get("auto_sell_impact", {}) as Dictionary).duplicate(true)
	queued_stockpile_market_sales = (d.get("queued_stockpile_market_sales", {}) as Dictionary).duplicate(true)
	pending_transport_shipments = (d.get("pending_transport_shipments", []) as Array).duplicate(true)
	overflow_shipments = (d.get("overflow_shipments", []) as Array).duplicate(true)
	transaction_log = (d.get("transaction_log", []) as Array).duplicate(true)
	move_log = (d.get("move_log", []) as Array).duplicate(true)
	surveyed_tiles = (d.get("surveyed_tiles", {}) as Dictionary).duplicate(true)
	partially_surveyed_tiles = (d.get("partially_surveyed_tiles", {}) as Dictionary).duplicate(true)
	surveying_in_progress = (d.get("surveying_in_progress", {}) as Dictionary).duplicate(true)
	surveying_reveal = (d.get("surveying_reveal", {}) as Dictionary).duplicate(true)
	revealed_deposits = (d.get("revealed_deposits", {}) as Dictionary).duplicate(true)
	# Default to the CURRENT value, not {}: a start config carries no deposit data,
	# so the CSV-seeded yields from world_map._ready must survive the import. Full
	# saves always carry the key and overwrite as usual.
	deposit_remaining = (d.get("deposit_remaining", deposit_remaining) as Dictionary).duplicate(true)
	unlocked_titles = (d.get("unlocked_titles", {}) as Dictionary).duplicate(true)
	_unlock_progress = (d.get("unlock_progress", {}) as Dictionary).duplicate(true)
	seaport_auto_subscribe = bool(d.get("seaport_auto_subscribe", false))
	seaport_subscribed = (d.get("seaport_subscribed", {}) as Dictionary).duplicate(true)
	# Derived state: the tile index is rebuilt, never saved; caches invalidate.
	_rebuild_tile_index()
	_surveyable_dirty = true
	pending_output_stockpile_selection.clear()
	sales_by_tile.clear()
	_requote_shipment_routes()

func _shipments_for_save() -> Array:
	var out: Array = []
	for shipment in pending_transport_shipments:
		var s: Dictionary = shipment.duplicate(true)
		for key in _SHIPMENT_ROUTE_KEYS:
			s.erase(key)
		out.append(s)
	return out

func _rebuild_tile_index() -> void:
	tile_buildings.clear()
	for instance_id in buildings:
		var tile_id := str(buildings[instance_id].get("tile_id", ""))
		if tile_id == "":
			continue
		if not tile_buildings.has(tile_id):
			tile_buildings[tile_id] = []
		tile_buildings[tile_id].append(instance_id)

func _requote_shipment_routes() -> void:
	# Restore the visual route geometry stripped on save. Countdown fields
	# (turns_remaining / transport_turns) are the saved truth and stay untouched.
	for shipment in pending_transport_shipments:
		var src := str(shipment.get("source_tile", ""))
		var dst := str(shipment.get("destination_tile", ""))
		if src == "" or dst == "":
			continue
		var route: Dictionary = TransportService.route(src, dst, str(shipment.get("good_id", "")))
		for key in _SHIPMENT_ROUTE_KEYS:
			shipment[key] = route.get(key, [])

func set_sell_mode(mode: int) -> void:
	sell_mode = mode
	sell_mode_changed.emit(mode)

## Debug cheat: switch between the classic and alternate Tile View Panels.
## Returns the new state. Session-only, never persisted.
func set_use_alt_tvp(enabled: bool) -> bool:
	if enabled == use_alt_tvp:
		return use_alt_tvp
	use_alt_tvp = enabled
	alt_tvp_changed.emit(use_alt_tvp)
	return use_alt_tvp

func toggle_use_alt_tvp() -> bool:
	return set_use_alt_tvp(not use_alt_tvp)

## Debug cheat: switch between the current and alternate bottom-menu icon sets.
## Returns the new state. Session-only, never persisted.
func set_use_alt_bottom_menu(enabled: bool) -> bool:
	if enabled == use_alt_bottom_menu:
		return use_alt_bottom_menu
	use_alt_bottom_menu = enabled
	alt_bottom_menu_changed.emit(use_alt_bottom_menu)
	return use_alt_bottom_menu

func toggle_use_alt_bottom_menu() -> bool:
	return set_use_alt_bottom_menu(not use_alt_bottom_menu)

func set_route_objective(objective: int) -> void:
	if objective == route_objective:
		return
	route_objective = objective
	route_objective_changed.emit(objective)

func begin_output_stockpile_selection(instance_id: String, good_id: String) -> void:
	if instance_id == "" or good_id == "":
		return
	pending_output_stockpile_selection = {
		"instance_id": instance_id,
		"good_id": good_id,
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
	pending_output_stockpile_selection.clear()
	output_stockpile_destination_changed.emit(instance_id, tile_id, good_id)

func clear_output_stockpile_destination(instance_id: String, good_id: String = "") -> void:
	if instance_id == "":
		return
	if good_id == "":
		output_stockpile_destinations.erase(instance_id)  # clear the whole building
		return
	var per_good: Dictionary = output_stockpile_destinations.get(instance_id, {})
	per_good.erase(good_id)
	if per_good.is_empty():
		output_stockpile_destinations.erase(instance_id)
	else:
		output_stockpile_destinations[instance_id] = per_good

func get_output_stockpile_destination(instance_id: String, good_id: String = "") -> String:
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

func route_output_to_market(instance_id: String, good_id: String) -> void:
	# Per-building, per-good "send output to market" — does NOT touch global sell_mode.
	if instance_id == "" or good_id == "":
		return
	var per_good: Dictionary = output_stockpile_destinations.get(instance_id, {})
	per_good[good_id] = MARKET_DESTINATION
	output_stockpile_destinations[instance_id] = per_good
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

func queue_transport_shipment(shipment: Dictionary) -> void:
	var s := shipment.duplicate(true)
	if not s.has("id"):
		_shipment_id_counter += 1
		s["id"] = _shipment_id_counter  # stable id so the overlay can track it across turns
	pending_transport_shipments.append(s)
	transport_shipments_changed.emit()

func request_toast(message: String, toast_type: String = "success") -> void:
	toast_requested.emit(message, toast_type)

func queue_move(source_tile: String, dest_tile: String, goods_qtys: Dictionary, log_oneoff: bool = true, extra: Dictionary = {}) -> Dictionary:
	# Move goods from one tile to another: consume now, ship via the router, deliver
	# to the destination stockpile on arrival. Returns a summary for the UI/toast.
	if source_tile == "" or dest_tile == "" or source_tile == dest_tile:
		return {}
	var items: Array = []
	var manifest: Dictionary = {}
	var total_qty := 0
	for good_id in goods_qtys.keys():
		var want := int(goods_qtys[good_id])
		if want <= 0:
			continue
		var moved := Stockpile.consume(source_tile, str(good_id), want)
		if moved <= 0:
			continue
		total_qty += moved
		items.append({"good_id": str(good_id), "qty": moved})
		manifest[str(good_id)] = int(manifest.get(str(good_id), 0)) + moved
	if items.is_empty():
		return {}
	var surcharge := LARGE_SHIPMENT_SURCHARGE if total_qty > LARGE_SHIPMENT_THRESHOLD else 1.0
	var quote := TransportService.quote_manifest(source_tile, dest_tile, manifest, {"surcharge": surcharge})
	var route: Dictionary = quote.get("route", {})
	var turns: int = int(quote.get("turns", 0))
	items = quote.get("items", [])
	var total_cost := float(quote.get("cost", 0.0))
	if total_cost > 0.0:
		add_money(-total_cost)
	for it in items:
		if turns >= 1:
			var shipment: Dictionary = {
				"source_tile": source_tile,
				"destination_tile": dest_tile,
				"good_id": it.good_id,
				"qty": it.qty,
				"turns_remaining": turns,
				"transport_turns": turns,
				"transport_cost": it.cost,
				"tiles": route.get("tiles", []),
				"path": route.get("path", []),
				"legs": route.get("legs", []),
			}
			shipment.merge(extra, true)  # optional tags, e.g. construction_instance_id
			queue_transport_shipment(shipment)
		else:
			Stockpile.add(dest_tile, it.good_id, it.qty)
	if log_oneoff:
		for it in items:
			log_move_shipment(source_tile, dest_tile, str(it.good_id), int(it.qty), turns)
	return {"items": items, "total_qty": total_qty, "turns": turns,
		"cost": total_cost, "source": source_tile, "dest": dest_tile, "surcharged": surcharge > 1.0}

func preview_move(source_tile: String, dest_tile: String, goods_qtys: Dictionary) -> Dictionary:
	# Cost/turns for a move WITHOUT consuming — used to populate the large-shipment dialog.
	var manifest: Dictionary = {}
	var total_qty := 0
	for good_id in goods_qtys.keys():
		var qty := mini(int(goods_qtys[good_id]), Stockpile.get_at_tile(source_tile, str(good_id)))
		if qty > 0:
			manifest[str(good_id)] = qty
			total_qty += qty
	var surcharge := LARGE_SHIPMENT_SURCHARGE if total_qty > LARGE_SHIPMENT_THRESHOLD else 1.0
	var quote := TransportService.quote_manifest(source_tile, dest_tile, manifest, {"surcharge": surcharge})
	var turns: int = int(quote.get("turns", 0))
	var total_cost := float(quote.get("cost", 0.0))
	return {"turns": turns, "cost": total_cost, "total_qty": total_qty,
		"per_turn": total_cost / float(maxi(turns, 1)), "surcharged": surcharge > 1.0}

func add_recurring_move(source_tile: String, dest_tile: String, goods_qtys: Dictionary) -> void:
	recurring_moves.append({"source": source_tile, "dest": dest_tile, "goods": goods_qtys.duplicate(true), "turn_started": _ledger_turn()})

func add_scheduled_move(source_tile: String, dest_tile: String, goods_qtys: Dictionary) -> void:
	scheduled_moves.append({"source": source_tile, "dest": dest_tile, "goods": goods_qtys.duplicate(true)})

func run_recurring_and_scheduled_moves() -> void:
	# Fire one-shot scheduled moves (e.g. the split second half) then re-issue recurring moves.
	var due: Array = scheduled_moves
	scheduled_moves = []
	for m in due:
		queue_move(str(m.source), str(m.dest), m.goods, true)  # split second-half = a one-off
	for m in recurring_moves:
		queue_move(str(m.source), str(m.dest), m.goods, false)
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

func add_recurring_bulk_sell(params: Dictionary) -> void:
	recurring_bulk_sells.append({"params": params.duplicate(true), "turn_started": _ledger_turn()})

func add_recurring_buy(dest_tile: String, good_id: String, qty: int) -> void:
	recurring_buys.append({"dest": dest_tile, "good": good_id, "qty": qty, "turn_started": _ledger_turn()})

# --- Ledger helpers for the Transactions / Movements tabs ---

func _ledger_turn() -> int:
	return int(TurnManager.current_turn) if TurnManager else 0

func _log_transaction(entry: Dictionary) -> void:
	transaction_log.append(entry)
	if transaction_log.size() > LEDGER_MAX:
		transaction_log = transaction_log.slice(transaction_log.size() - LEDGER_MAX)

func _log_move(entry: Dictionary) -> void:
	move_log.append(entry)
	if move_log.size() > LEDGER_MAX:
		move_log = move_log.slice(move_log.size() - LEDGER_MAX)

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

func log_move_shipment(source_tile: String, dest_tile: String, good_id: String, qty: int, turns: int) -> void:
	# Production calls this when output is routed to ANOTHER tile's stockpile (a tile-to-tile move).
	if qty <= 0:
		return
	var started := _ledger_turn()
	_log_move({
		"good_id": str(good_id), "qty": int(qty),
		"tile_from": source_tile, "tile_to": dest_tile,
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

# --- Seaport subscriptions ---
# A subscribed good transfers through a seaport in 1 turn at ANY volume for a flat
# per-turn fee (see EconomyConfig.SEAPORT_SUBSCRIPTION_COST_PER_GOOD), with no per-unit
# market shipping cost. The sim sets seaport_auto_subscribe = true (every traded good
# is covered from turn 1); the game will expose per-good toggles.
var seaport_auto_subscribe: bool = false
var seaport_subscribed: Dictionary = {}

func seaport_covers(good_id: String) -> bool:
	if seaport_auto_subscribe:
		seaport_subscribed[good_id] = true
		return true
	return seaport_subscribed.has(good_id)

func seaport_would_cover(good_id: String) -> bool:
	return seaport_auto_subscribe or seaport_subscribed.has(good_id)

func subscribe_seaport(good_id: String) -> void:
	seaport_subscribed[good_id] = true

func seaport_subscription_fee() -> float:
	return float(seaport_subscribed.size()) * EconomyConfig.SEAPORT_SUBSCRIPTION_COST_PER_GOOD

func queue_buy(dest_tile: String, good_id: String, qty: int, log_oneoff: bool = true, extra: Dictionary = {}) -> Dictionary:
	# Buy goods from the nearest port to dest_tile: pay now (price + transport), ship in,
	# arrive in N turns. The reusable buy primitive for market-sourced inputs (and later a Buy tab).
	if dest_tile == "" or good_id == "" or qty <= 0:
		return {}
	var covered := seaport_covers(good_id)
	var quote := TransportService.quote_market_buy(dest_tile, good_id, qty, covered)
	if quote.is_empty():
		return {}
	var port := str(quote.get("port", ""))
	var route: Dictionary = quote.get("route", {})
	var turns: int = int(quote.get("turns", 0))
	var unit_price := MarketState.get_buy_price(good_id)
	var transport := float(quote.get("transport_cost", 0.0))
	var total := float(quote.get("cost", 0.0))
	if total > money:
		# Best-effort: buy as much as we can afford rather than nothing (avoids an
		# all-or-nothing starvation cliff when cash dips below a full order).
		var per_unit := unit_price + transport / float(maxi(qty, 1))
		qty = mini(qty, int(floor(money / maxf(per_unit, 0.0001))))
		if qty <= 0:
			return {}
		quote = TransportService.quote_market_buy(dest_tile, good_id, qty, covered)
		route = quote.get("route", {})
		turns = int(quote.get("turns", 0))
		transport = float(quote.get("transport_cost", 0.0))
		total = float(quote.get("cost", 0.0))
		if total > money:
			return {}
	add_money(-total)
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
			"tiles": route.get("tiles", []), "path": route.get("path", []), "legs": route.get("legs", []),
		}
		shipment.merge(extra, true)  # optional tags, e.g. construction_instance_id
		queue_transport_shipment(shipment)
	else:
		Stockpile.add(dest_tile, good_id, qty)
	return {"qty": qty, "turns": turns, "cost": total,
		"goods_cost": float(qty) * unit_price, "transport_cost": transport, "port": port}

func tiles_producing(good_id: String) -> Dictionary:
	var out: Dictionary = {}
	for inst in buildings.values():
		if Catalog.recipe_produces(Catalog.get_recipe(str(inst.get("recipe_id", ""))), good_id):
			out[str(inst.get("tile_id", ""))] = true
	return out

func tiles_consuming(good_id: String) -> Dictionary:
	var out: Dictionary = {}
	for inst in buildings.values():
		for input in Catalog.get_recipe(str(inst.get("recipe_id", ""))).get("inputs", []):
			if str(input.get("good_id", "")) == good_id:
				out[str(inst.get("tile_id", ""))] = true
				break
	return out

func preview_buy(dest_tile: String, good_id: String, qty: int) -> Dictionary:
	# Cost/turns for a buy WITHOUT executing — for the Purchases "Cost to buy" line.
	if dest_tile == "" or good_id == "" or qty <= 0:
		return {}
	var quote := TransportService.quote_market_buy(dest_tile, good_id, qty, seaport_would_cover(good_id))
	if quote.is_empty():
		return {}
	return {"cost": float(quote.get("cost", 0.0)), "goods_cost": float(quote.get("goods_cost", 0.0)),
		"transport_cost": float(quote.get("transport_cost", 0.0)), "turns": int(quote.get("turns", 0)),
		"port": str(quote.get("port", ""))}

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

func get_oneoff_move_rows() -> Array:
	var rows: Array = []
	for m in move_log:
		rows.append(_move_row(Catalog.get_display_name(str(m.get("good_id", ""))), int(m.get("qty", 0)),
			str(m.get("tile_from", "")), str(m.get("tile_to", "")),
			int(m.get("turn_started", 0)), int(m.get("turn_ended", -1))))
	return rows

func get_recurring_move_rows() -> Array:
	var rows: Array = []
	for m in recurring_moves:
		for gid in m.get("goods", {}).keys():
			rows.append(_move_row(Catalog.get_display_name(str(gid)), int(m.goods[gid]),
				str(m.get("source", "")), str(m.get("dest", "")), int(m.get("turn_started", 0)), -1))
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
	# Sell specific goods/qtys from a tile: ship to the nearest port, pay out on arrival.
	if source_tile == "":
		return {}
	var route := TransportService.route_to_nearest_port(source_tile)
	var port := str(route.get("port", ""))
	var turns: int = int(route.get("turns", 0))
	var items: Array = []
	var total_qty := 0
	var total_revenue := 0.0
	for good_id in goods_qtys.keys():
		var want := int(goods_qtys[good_id])
		if want <= 0:
			continue
		var sold := Stockpile.consume(source_tile, str(good_id), want)
		if sold <= 0:
			continue
		var revenue := float(sold) * MarketState.get_price(str(good_id))
		items.append({"good_id": str(good_id), "qty": sold, "revenue": revenue})
		total_qty += sold
		total_revenue += revenue
	if items.is_empty():
		return {}
	var sale_record := {"tile_id": source_tile, "items": items, "total_qty": total_qty, "total_revenue": total_revenue}
	if port != "" and turns >= 1:
		queue_transport_shipment({
			"is_sale": true, "source_tile": source_tile, "destination_tile": port,
			"sale_record": sale_record.duplicate(true),
			"turns_remaining": turns, "transport_turns": turns,
			"tiles": route.get("tiles", []), "path": route.get("path", []), "legs": route.get("legs", []),
		})
	else:
		for it in items:
			add_money(float(it.revenue))
		emit_stockpile_market_sale_completed(sale_record)
		if port != "":
			market_sale_arrived_at_port.emit(port, total_revenue)
	if log_oneoff:
		for it in items:
			log_market_sale(source_tile, port, str(it.good_id), int(it.qty), turns)
	return {"items": items, "total_qty": total_qty, "revenue": total_revenue, "turns": turns, "port": port}

## A shipment couldn't fully unload at a full tile — hold the remainder so the
## goods aren't lost; it retries each turn.
func hold_overflow_shipment(record: Dictionary) -> void:
	var rec := record.duplicate(true)
	rec["turns_waiting"] = int(rec.get("turns_waiting", 0))
	overflow_shipments.append(rec)
	overflow_shipment_held.emit(rec)
	transport_shipments_changed.emit()

func get_overflow_shipments_for_tile(tile_id: String) -> Array:
	var out: Array = []
	for r in overflow_shipments:
		if str(r.get("destination_tile", "")) == tile_id:
			out.append(r)
	return out

## Retry unloading every waiting shipment into its destination stockpile. Fully
## unloaded ones drop off the list; the rest wait another turn. Call this before
## construction claims materials so unloaded build materials are picked up.
func retry_overflow_unload() -> void:
	if overflow_shipments.is_empty():
		return
	var remaining: Array = []
	for r in overflow_shipments:
		var dest := str(r.get("destination_tile", ""))
		var gid := str(r.get("good_id", ""))
		var qty := int(r.get("qty", 0))
		var added := Stockpile.add(dest, gid, qty) if (dest != "" and gid != "" and qty > 0) else 0
		if added >= qty:
			continue  # fully unloaded — drop it
		r["qty"] = qty - added
		r["turns_waiting"] = int(r.get("turns_waiting", 0)) + 1
		remaining.append(r)
	overflow_shipments = remaining
	transport_shipments_changed.emit()

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

func get_pending_transport_shipments() -> Array:
	return pending_transport_shipments.duplicate(true)

func get_inbound_transport_shipments(destination_tile: String, good_id: String = "") -> Array:
	var result: Array = []
	for shipment in pending_transport_shipments:
		if shipment.get("destination_tile", "") != destination_tile:
			continue
		if good_id != "" and shipment.get("good_id", "") != good_id:
			continue
		# Shallow copy: callers only read scalar fields (qty, turns_remaining). Avoids
		# deep-cloning the heavy path/tiles/legs/sale_record arrays every call (this runs
		# per building, per market input, every turn).
		result.append(shipment.duplicate())
	return result

func advance_transport_shipments() -> Array:
	var arrived: Array = []
	var remaining: Array = []
	# Decrement in place — Dictionaries are references, and the only mutation is the
	# countdown. The previous deep-copy of every shipment (with its path/tiles arrays)
	# every turn was a top sim hot-spot. Arrived shipments are read-only consumed by the
	# caller and then discarded; remaining keep their identity in the live list.
	for shipment in pending_transport_shipments:
		shipment.turns_remaining = int(shipment.get("turns_remaining", 0)) - 1
		if int(shipment.turns_remaining) <= 0:
			arrived.append(shipment)
		else:
			remaining.append(shipment)
	pending_transport_shipments = remaining
	if not arrived.is_empty():
		transport_shipments_changed.emit()
	return arrived

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

func set_labour_multiplier(value: float) -> void:
	# Clamp to valid range
	value = clamp(value, EconomyConfig.LABOUR_MULTIPLIER_MIN, EconomyConfig.LABOUR_MULTIPLIER_MAX)
	if value == labour_multiplier:
		return
	labour_multiplier = value
	labour_multiplier_changed.emit(value)
	print("[MatchState] Labour multiplier set to: %.2fx" % value)
