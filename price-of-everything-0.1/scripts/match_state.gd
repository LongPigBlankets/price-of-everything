extends Node

# MatchState: the canonical store for everything that changes during a match.
# Other systems read and write here; never store match data elsewhere.

# --- Player resources ---
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
var pending_output_stockpile_selection: Dictionary = {}
var queued_stockpile_market_sales: Dictionary = {}  # tile_id -> true
var sell_surplus_tiles: Dictionary = {}              # tile_id -> true (standing order)
var pending_transport_shipments: Array = []
var _shipment_id_counter: int = 0
var recurring_moves: Array = []   # [{source, dest, goods}] re-issued every turn
var scheduled_moves: Array = []   # [{source, dest, goods}] one-shot, fired next turn (e.g. split)
var recurring_sells: Array = []   # [{source, goods}] re-sold to the nearest port every turn
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
	pending_transport_shipments.clear()
	tile_land_owned.clear()
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
	return destination.get("tile_id", "")

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

func queue_move(source_tile: String, dest_tile: String, goods_qtys: Dictionary) -> Dictionary:
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
	recurring_moves.append({"source": source_tile, "dest": dest_tile, "goods": goods_qtys.duplicate(true)})

func add_scheduled_move(source_tile: String, dest_tile: String, goods_qtys: Dictionary) -> void:
	scheduled_moves.append({"source": source_tile, "dest": dest_tile, "goods": goods_qtys.duplicate(true)})

func run_recurring_and_scheduled_moves() -> void:
	# Fire one-shot scheduled moves (e.g. the split second half) then re-issue recurring moves.
	var due: Array = scheduled_moves
	scheduled_moves = []
	for m in due:
		queue_move(str(m.source), str(m.dest), m.goods)
	for m in recurring_moves:
		queue_move(str(m.source), str(m.dest), m.goods)
	for m in recurring_sells:
		queue_sell(str(m.source), m.goods)

func add_recurring_sell(source_tile: String, goods_qtys: Dictionary) -> void:
	recurring_sells.append({"source": source_tile, "goods": goods_qtys.duplicate(true)})

func _is_finished_good(good_id: String) -> bool:
	# No explicit "finished" tier in the MVP, so "finished/manufactured" = non-raw, non-power.
	var gt := str(Catalog.get_good(good_id).get("good_type", ""))
	return gt != "" and gt != "raw" and gt != "power"

func sell_all_to_market(params: Dictionary) -> Dictionary:
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
			if good_filter != "" and g != good_filter:
				continue
			if finished_only and not _is_finished_good(g):
				continue
			var surplus := int(totals[gid]) - keep
			if surplus > 0:
				goods_qtys[g] = surplus
		if goods_qtys.is_empty():
			continue
		var summary := queue_sell(tile_id, goods_qtys)
		if not summary.is_empty():
			total_qty += int(summary.get("total_qty", 0))
			total_revenue += float(summary.get("revenue", 0.0))
			tiles_sold += 1
	return {"total_qty": total_qty, "revenue": total_revenue, "tiles": tiles_sold}

func queue_sell(source_tile: String, goods_qtys: Dictionary) -> Dictionary:
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

func set_labour_multiplier(value: float) -> void:
	# Clamp to valid range
	value = clamp(value, EconomyConfig.LABOUR_MULTIPLIER_MIN, EconomyConfig.LABOUR_MULTIPLIER_MAX)
	if value == labour_multiplier:
		return
	labour_multiplier = value
	labour_multiplier_changed.emit(value)
	print("[MatchState] Labour multiplier set to: %.2fx" % value)
