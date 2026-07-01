extends Node

const FORECAST_TURNS := 10

var prices: Dictionary = {}  # good_id -> current price (float)

signal prices_updated()

func _ready() -> void:
	await get_tree().process_frame
	_init_prices_from_catalog()
	TurnManager.turn_advanced.connect(_on_turn_advanced)

func _on_turn_advanced(_new_turn: int) -> void:
	tick_turn()

func _init_prices_from_catalog() -> void:
	for good in Catalog.all_goods():
		prices[good.id] = good.base_price
	prices_updated.emit()

func get_price(good_id: String) -> float:
	# The price you RECEIVE when selling a unit to the market.
	return prices.get(good_id, 1.0)

func get_buy_price(good_id: String) -> float:
	# The price you PAY to buy a unit from the market — the sale price plus the
	# market spread (EconomyConfig.MARKET_BUY_MARKUP).
	return get_price(good_id) * (1.0 + EconomyConfig.MARKET_BUY_MARKUP)

func get_estimated_price_in_n_turns(good_id: String, n: int) -> float:
	var current: float = prices.get(good_id, 1.0)
	var good: Dictionary = Catalog.get_good(good_id)
	var decay: float = good.get("decay_rate", 0.0)
	return current * pow(1.0 - decay, n)

# --- Save/load (orchestrated by the SaveLoad autoload; docs/save_load_spec.md) ---

func export_state() -> Dictionary:
	return {"prices": prices.duplicate(true)}

func import_state(d: Dictionary) -> void:
	# Re-seed from the catalog first so goods added since the save keep their base
	# price, then overlay the saved (decayed) prices. Silent: SaveLoad emits
	# prices_updated once after every system imports.
	for good in Catalog.all_goods():
		prices[good.id] = good.base_price
	var saved: Dictionary = d.get("prices", {})
	for good_id in saved:
		prices[good_id] = float(saved[good_id])

func tick_turn() -> void:
	for good_id in prices.keys():
		var good: Dictionary = Catalog.get_good(good_id)
		var decay: float = good.get("decay_rate", 0.0)
		prices[good_id] = prices[good_id] * (1.0 - decay)
	prices_updated.emit()

# --- Unified sell primitive -------------------------------------------------
# All four sell paths (the player-driven queue_sell, the bulk sell_all_to_market,
# the recurring sell orders, and Production's market-routed output) ultimately
# come through here. It is the one place that:
#   - looks up the port + route via TransportService,
#   - prices the goods via get_price(),
#   - decides immediate vs. deferred settlement,
#   - logs to MatchState's ledger and emits market signals.
# Future price-impact / modifier work plugs in here.
#
# source_tile     a tile_X_Y string the goods leave from.
# goods_qtys      {good_id: qty} — at least one positive entry, or {} (no-op).
# opts
#   skip_consume:                bool  default false  Don't pull from Stockpile —
#                                                     the caller already has the
#                                                     goods in hand (Production
#                                                     dispatches output directly).
#   pay_transport_from_seller:   bool  default false  Subtract transport cost
#                                                     upfront from the player's
#                                                     cash (production case).
#   log_oneoff:                  bool  default true   Write a transaction ledger
#                                                     row per item.
#   good_id_hint:                String def ""        Passed to
#                                                     TransportService for type-
#                                                     aware port selection.
#   special_order_id:            String def ""        Tags the sale as committed
#                                                     to an active special order.
#   special_order_source_mode:   String def ""        Records whether the
#                                                     commitment came from tile
#                                                     view, building detail, etc.
#
# Returns {} if nothing was sold, otherwise a dict with the original sale_record,
# plus `transport_cost`, `deferred`, `turns`, `port`, `total_qty`, `total_revenue`.
func execute_sale(source_tile: String, goods_qtys: Dictionary, opts: Dictionary = {}) -> Dictionary:
	if source_tile == "" or goods_qtys.is_empty():
		return {}

	var skip_consume: bool = bool(opts.get("skip_consume", false))
	var pay_transport_from_seller: bool = bool(opts.get("pay_transport_from_seller", false))
	var log_oneoff: bool = bool(opts.get("log_oneoff", true))
	var good_id_hint: String = str(opts.get("good_id_hint", ""))
	var special_order_id: String = str(opts.get("special_order_id", ""))
	var special_order_source_mode: String = str(opts.get("special_order_source_mode", ""))

	var route := TransportService.route_to_nearest_port(source_tile, good_id_hint)
	var port := str(route.get("port", ""))
	var turns: int = int(route.get("turns", 0))

	var items: Array = []
	var total_qty := 0
	var total_revenue := 0.0
	for gid in goods_qtys.keys():
		var want := int(goods_qtys[gid])
		if want <= 0:
			continue
		var sold: int = want if skip_consume else Stockpile.consume(source_tile, str(gid), want)
		if sold <= 0:
			continue
		# market_price modifiers (research like Forward Contracts) lift the SALE price
		# only — applied here, not in get_price(), so buy prices are unaffected.
		var unit_price: float = Modifiers.apply("market_price", str(gid), get_price(str(gid)),
			{"good_id": str(gid), "good_internal": str(Catalog.get_good(str(gid)).get("internal_name", ""))})
		var revenue: float = float(sold) * unit_price
		items.append({"good_id": str(gid), "qty": sold, "revenue": revenue})
		total_qty += sold
		total_revenue += revenue
	if items.is_empty():
		return {}

	# Victory feed: one goods movement per sale routed through execute_sale —
	# production-output dispatch + the player/UI queue_sell & bulk sell_all_to_market.
	# (The PROCESS sell_phase's stockpile auto-sell, production.gd _sell_stockpile_totals,
	# is a separate path that emits its own "sale" event.) Sales never break Autarky.
	MatchState.goods_movement_recorded.emit("sale", "", turns)

	var transport_cost := 0.0
	if pay_transport_from_seller:
		for it in items:
			transport_cost += TransportService.transport_cost_for_route(str(it.good_id), int(it.qty), route)
		if transport_cost > 0.0:
			MatchState.add_money(-transport_cost)

	var sale_record := {
		"tile_id": source_tile,
		"items": items,
		"total_qty": total_qty,
		"total_revenue": total_revenue,
	}
	var returned_sale_record := sale_record
	var returned_items := items
	var returned_total_qty := total_qty
	var returned_total_revenue := total_revenue

	if log_oneoff:
		for it in items:
			MatchState.log_market_sale(source_tile, port, str(it.good_id), int(it.qty), turns)

	var special_order_committed := false
	if special_order_id != "":
		for it in items:
			var committed := SpecialOrderState.commit_units(special_order_id, int(it.qty), special_order_source_mode, str(it.good_id))
			if not committed.is_empty():
				special_order_committed = true

	var deferred := port != "" and turns >= 1
	if deferred:
		var shipment := {
			"is_sale": true,
			"source_tile": source_tile,
			"destination_tile": port,
			"sale_record": sale_record.duplicate(true),
			"tile_distance": int(route.get("tile_distance", 0)),
			"transport_turns": turns,
			"turns_remaining": turns,
			"tiles": route.get("tiles", []),
			"path": route.get("path", []),
			"legs": route.get("legs", []),
		}
		if special_order_committed:
			shipment["special_order_id"] = special_order_id
			shipment["special_order_source_mode"] = special_order_source_mode
		MatchState.queue_transport_shipment(shipment)
	else:
		if special_order_committed:
			var paid_record := _settle_immediate_special_order_sale(sale_record, port, special_order_id, special_order_source_mode)
			returned_sale_record = paid_record
			returned_items = paid_record.get("items", [])
			returned_total_qty = int(paid_record.get("total_qty", 0))
			returned_total_revenue = float(paid_record.get("total_revenue", 0.0))
			if float(paid_record.get("total_revenue", 0.0)) > 0.0:
				MatchState.emit_stockpile_market_sale_completed(paid_record)
				if port != "":
					MatchState.market_sale_arrived_at_port.emit(port, float(paid_record.get("total_revenue", 0.0)))
		else:
			for it in items:
				MatchState.add_money(float(it.revenue))
			MatchState.emit_stockpile_market_sale_completed(sale_record)
			if port != "":
				MatchState.market_sale_arrived_at_port.emit(port, total_revenue)

	return {
		"items": returned_items,
		"total_qty": returned_total_qty,
		"total_revenue": returned_total_revenue,
		"transport_cost": transport_cost,
		"deferred": deferred,
		"turns": turns,
		"port": port,
		"special_order_id": special_order_id if special_order_committed else "",
		"special_order_committed": special_order_committed,
		"sale_record": returned_sale_record,
	}

func _settle_immediate_special_order_sale(sale_record: Dictionary, port_tile: String, order_id: String, source_mode: String) -> Dictionary:
	var paid_record := {
		"tile_id": str(sale_record.get("tile_id", "")),
		"items": [],
		"total_qty": 0,
		"total_revenue": 0.0,
	}
	for item in sale_record.get("items", []):
		var gid := str(item.get("good_id", ""))
		var qty := int(item.get("qty", 0))
		var revenue := float(item.get("revenue", 0.0))
		var unit_revenue := revenue / float(maxi(qty, 1))
		var order_before := SpecialOrderState.get_order(order_id)
		if order_before.is_empty():
			_offer_immediate_special_order_overflow(sale_record, port_tile, order_id, source_mode, gid, qty, unit_revenue)
			continue
		if str(order_before.get("good_id", "")) != gid:
			MatchState.add_money(revenue)
			_add_paid_sale_item(paid_record, gid, qty, revenue)
			continue
		var remaining := maxi(0, int(order_before.get("qty_required", 0)) - int(order_before.get("qty_delivered", 0)))
		var paid_qty := mini(qty, remaining)
		var overflow_qty := maxi(0, qty - paid_qty)
		var paid_revenue := unit_revenue * float(paid_qty)
		if paid_revenue > 0.0:
			MatchState.add_money(paid_revenue)
			_add_paid_sale_item(paid_record, gid, paid_qty, paid_revenue)
		SpecialOrderState.settle_delivery(order_id, gid, qty, revenue)
		if overflow_qty > 0:
			_offer_immediate_special_order_overflow(sale_record, port_tile, order_id, source_mode, gid, overflow_qty, unit_revenue)
	return paid_record

func _add_paid_sale_item(sale_record: Dictionary, good_id: String, qty: int, revenue: float) -> void:
	if good_id == "" or qty <= 0 or revenue <= 0.0:
		return
	sale_record.items.append({"good_id": good_id, "qty": qty, "revenue": revenue})
	sale_record.total_qty = int(sale_record.get("total_qty", 0)) + qty
	sale_record.total_revenue = float(sale_record.get("total_revenue", 0.0)) + revenue

func _offer_immediate_special_order_overflow(
	sale_record: Dictionary,
	port_tile: String,
	order_id: String,
	source_mode: String,
	good_id: String,
	qty: int,
	unit_revenue: float
) -> void:
	if good_id == "" or qty <= 0:
		return
	MatchState.offer_special_order_overflow({
		"order_id": order_id,
		"source_mode": source_mode,
		"source_tile": str(sale_record.get("tile_id", "")),
		"port_tile": port_tile,
		"good_id": good_id,
		"good_display": Catalog.get_display_name(good_id),
		"qty": qty,
		"unit_revenue": unit_revenue,
		"total_revenue": unit_revenue * float(qty),
		"shipment_id": 0,
	})
