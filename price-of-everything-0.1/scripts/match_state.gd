extends Node

# MatchState: the canonical store for everything that changes during a match.
# Other systems read and write here; never store match data elsewhere.

# --- Player resources ---
const LOCAL_PLAYER := "player_1"
var money: float = 1000.0  # was: int = 1000

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

enum SellMode { SELL_ALL, STOCKPILE_ALL, BUILDING_BY_BUILDING }
var sell_mode: int = SellMode.STOCKPILE_ALL

# How the transport router picks a path between two tiles. FASTEST by default.
enum RouteObjective { FASTEST, CHEAPEST, BLENDED }
var route_objective: int = RouteObjective.FASTEST

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

# --- Initialization ---
func _ready() -> void:
	pass  # nothing to do at startup; systems push state into MatchState as they boot
	money = EconomyConfig.STARTING_MONEY
	money_changed.emit(money)
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

func add_building(building_id: String, recipe_id: String, tile_id: String, owner: String = "player_1") -> String:
	# Pass the building_id here!
	var instance_id := _generate_instance_id(building_id) 
	
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
	return total

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

func set_sell_mode(mode: int) -> void:
	sell_mode = mode
	sell_mode_changed.emit(mode)

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

func set_output_stockpile_destination(instance_id: String, tile_id: String, good_id: String) -> void:
	if instance_id == "" or tile_id == "" or good_id == "":
		return
	output_stockpile_destinations[instance_id] = {
		"tile_id": tile_id,
		"good_id": good_id,
	}
	pending_output_stockpile_selection.clear()
	output_stockpile_destination_changed.emit(instance_id, tile_id, good_id)

func clear_output_stockpile_destination(instance_id: String) -> void:
	if instance_id == "":
		return
	output_stockpile_destinations.erase(instance_id)

func get_output_stockpile_destination(instance_id: String, good_id: String = "") -> String:
	var destination: Dictionary = output_stockpile_destinations.get(instance_id, {})
	if destination.is_empty():
		return ""
	if good_id != "" and destination.get("good_id", "") != good_id:
		return ""
	var tile_id := str(destination.get("tile_id", ""))
	if tile_id == MARKET_DESTINATION:
		return ""  # a market route is not a stockpile tile
	return tile_id

func route_output_to_market(instance_id: String, good_id: String) -> void:
	# Per-building "send output to market" — does NOT touch the global sell_mode.
	if instance_id == "" or good_id == "":
		return
	output_stockpile_destinations[instance_id] = {
		"tile_id": MARKET_DESTINATION,
		"good_id": good_id,
	}
	pending_output_stockpile_selection.clear()
	output_stockpile_destination_changed.emit(instance_id, MARKET_DESTINATION, good_id)

func is_output_market(instance_id: String, good_id: String = "") -> bool:
	var destination: Dictionary = output_stockpile_destinations.get(instance_id, {})
	if destination.is_empty():
		return false
	if good_id != "" and destination.get("good_id", "") != good_id:
		return false
	return str(destination.get("tile_id", "")) == MARKET_DESTINATION

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

func queue_move(source_tile: String, dest_tile: String, goods_qtys: Dictionary, log_oneoff: bool = true) -> Dictionary:
	# Move goods from one tile to another: consume now, ship via the router, deliver
	# to the destination stockpile on arrival. Returns a summary for the UI/toast.
	if source_tile == "" or dest_tile == "" or source_tile == dest_tile:
		return {}
	var route := Catalog.route(source_tile, dest_tile)
	var turns: int = int(route.get("turns", 0))
	if turns >= (1 << 30):
		turns = EconomyConfig.transport_turns_for_tile_distance(Catalog.tile_hex_distance(source_tile, dest_tile))
	var items: Array = []
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
	if items.is_empty():
		return {}
	var surcharge := LARGE_SHIPMENT_SURCHARGE if total_qty > LARGE_SHIPMENT_THRESHOLD else 1.0
	var total_cost := 0.0
	for it in items:
		it["cost"] = EconomyConfig.transport_cost_for(str(it.good_id), int(it.qty), turns) * surcharge
		total_cost += it.cost
	if total_cost > 0.0:
		add_money(-total_cost)
	for it in items:
		if turns >= 1:
			queue_transport_shipment({
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
			})
		else:
			Stockpile.add(dest_tile, it.good_id, it.qty)
	if log_oneoff:
		for it in items:
			log_move_shipment(source_tile, dest_tile, str(it.good_id), int(it.qty), turns)
	return {"items": items, "total_qty": total_qty, "turns": turns,
		"cost": total_cost, "source": source_tile, "dest": dest_tile, "surcharged": surcharge > 1.0}

func preview_move(source_tile: String, dest_tile: String, goods_qtys: Dictionary) -> Dictionary:
	# Cost/turns for a move WITHOUT consuming — used to populate the large-shipment dialog.
	var route := Catalog.route(source_tile, dest_tile)
	var turns: int = int(route.get("turns", 0))
	if turns >= (1 << 30):
		turns = EconomyConfig.transport_turns_for_tile_distance(Catalog.tile_hex_distance(source_tile, dest_tile))
	var total_qty := 0
	for good_id in goods_qtys.keys():
		total_qty += mini(int(goods_qtys[good_id]), Stockpile.get_at_tile(source_tile, str(good_id)))
	var surcharge := LARGE_SHIPMENT_SURCHARGE if total_qty > LARGE_SHIPMENT_THRESHOLD else 1.0
	var total_cost := 0.0
	for good_id in goods_qtys.keys():
		var qty := mini(int(goods_qtys[good_id]), Stockpile.get_at_tile(source_tile, str(good_id)))
		total_cost += EconomyConfig.transport_cost_for(str(good_id), qty, turns) * surcharge
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

func subscribe_seaport(good_id: String) -> void:
	seaport_subscribed[good_id] = true

func seaport_subscription_fee() -> float:
	return float(seaport_subscribed.size()) * EconomyConfig.SEAPORT_SUBSCRIPTION_COST_PER_GOOD

func queue_buy(dest_tile: String, good_id: String, qty: int, log_oneoff: bool = true) -> Dictionary:
	# Buy goods from the nearest port to dest_tile: pay now (price + transport), ship in,
	# arrive in N turns. The reusable buy primitive for market-sourced inputs (and later a Buy tab).
	if dest_tile == "" or good_id == "" or qty <= 0:
		return {}
	var port := Catalog.nearest_port_tile(dest_tile)
	if port == "":
		return {}
	var covered := seaport_covers(good_id)
	var route := Catalog.route(port, dest_tile)
	var turns: int = int(route.get("turns", 0))
	if turns >= (1 << 30):
		turns = EconomyConfig.transport_turns_for_tile_distance(Catalog.tile_hex_distance(port, dest_tile))
	if covered:
		turns = 1   # seaport delivers any volume in 1 turn
	var unit_price := MarketState.get_buy_price(good_id)
	var transport := 0.0 if covered else EconomyConfig.transport_cost_for(good_id, qty, turns)
	var total := float(qty) * unit_price + transport
	if total > money:
		# Best-effort: buy as much as we can afford rather than nothing (avoids an
		# all-or-nothing starvation cliff when cash dips below a full order).
		var per_unit := unit_price + transport / float(maxi(qty, 1))
		qty = mini(qty, int(floor(money / maxf(per_unit, 0.0001))))
		if qty <= 0:
			return {}
		transport = EconomyConfig.transport_cost_for(good_id, qty, turns)
		total = float(qty) * unit_price + transport
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
		queue_transport_shipment({
			"source_tile": port, "destination_tile": dest_tile,
			"good_id": good_id, "qty": qty,
			"turns_remaining": turns, "transport_turns": turns,
			"transport_cost": transport, "is_purchase": true,
			"tiles": route.get("tiles", []), "path": route.get("path", []), "legs": route.get("legs", []),
		})
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
	var port := Catalog.nearest_port_tile(dest_tile)
	if port == "":
		return {}
	var route := Catalog.route(port, dest_tile)
	var turns: int = int(route.get("turns", 0))
	if turns >= (1 << 30):
		turns = EconomyConfig.transport_turns_for_tile_distance(Catalog.tile_hex_distance(port, dest_tile))
	var transport := EconomyConfig.transport_cost_for(good_id, qty, turns)
	var goods_cost := float(qty) * MarketState.get_buy_price(good_id)
	return {"cost": goods_cost + transport, "goods_cost": goods_cost,
		"transport_cost": transport, "turns": turns, "port": port}

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
		var port := Catalog.nearest_port_tile(str(m.get("source", "")))
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
			Catalog.nearest_port_tile(str(b.get("dest", ""))), str(b.get("dest", "")), int(b.get("turn_started", 0)), -1))
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
	var port := Catalog.nearest_port_tile(source_tile)
	var route := Catalog.route(source_tile, port) if port != "" else {}
	var turns: int = int(route.get("turns", 0))
	if turns >= (1 << 30):
		turns = EconomyConfig.transport_turns_for_tile_distance(Catalog.tile_hex_distance(source_tile, port))
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

func get_pending_transport_shipments() -> Array:
	return pending_transport_shipments.duplicate(true)

func get_inbound_transport_shipments(destination_tile: String, good_id: String = "") -> Array:
	var result: Array = []
	for shipment in pending_transport_shipments:
		if shipment.get("destination_tile", "") != destination_tile:
			continue
		if good_id != "" and shipment.get("good_id", "") != good_id:
			continue
		result.append(shipment.duplicate(true))
	return result

func advance_transport_shipments() -> Array:
	var arrived: Array = []
	var remaining: Array = []
	for shipment in pending_transport_shipments:
		var record: Dictionary = shipment.duplicate(true)
		record.turns_remaining = int(record.get("turns_remaining", 0)) - 1
		if int(record.turns_remaining) <= 0:
			arrived.append(record)
		else:
			remaining.append(record)
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
