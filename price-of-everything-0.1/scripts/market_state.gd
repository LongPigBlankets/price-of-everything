extends Node

const FORECAST_TURNS := 10

var prices: Dictionary = {}  # good_id -> impact-FREE base price (float), drifts by decay_rate

# --- Price impact (glut / deficit) ---
# Accumulated impact in percent per good: negative = glut discount (net player
# selling over threshold), positive = deficit premium (net buying). Capped at
# ±EconomyConfig.PRICE_IMPACT_CAP_PCT; recovers by PRICE_IMPACT_RECOVERY_PCT per
# turn while volume stays under the 2x threshold. `prices` stays the impact-free
# base series; get_price() applies the impact multiplicatively, so the impact
# stacks on top of the normal per-turn drift. Model spec in economy_config.gd.
var impact_pct: Dictionary = {}   # good_id -> accumulated %
var _turn_sold: Dictionary = {}   # good_id -> units the player sold to market this turn
var _turn_bought: Dictionary = {} # good_id -> units the player bought this turn
var _lifetime_sold: Dictionary = {} # good_id -> units sold over the saved match

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
	# The price you RECEIVE when selling a unit to the market: the impact-free
	# base price times the accumulated glut/deficit impact.
	return get_base_price_now(good_id) * (1.0 + get_impact_pct(good_id) / 100.0)

## This turn's impact-FREE price (what the price would be with zero glut/deficit
## impact) — the bracketed number in the market tab.
func get_base_price_now(good_id: String) -> float:
	return prices.get(good_id, 1.0)

func get_impact_pct(good_id: String) -> float:
	return float(impact_pct.get(good_id, 0.0))

## Player market volume this turn — every sell path (execute_sale, the PROCESS
## stockpile auto-sell) and every buy path (queue_buy) reports here; tick_turn
## folds the net into impact_pct. Special-order deliveries are contract-priced,
## not market volume, so they do NOT report.
func record_market_sale_volume(good_id: String, qty: int) -> void:
	if good_id == "" or qty <= 0:
		return
	_turn_sold[good_id] = int(_turn_sold.get(good_id, 0)) + qty
	record_lifetime_sale_volume(good_id, qty)

## Research "Sell N units" conditions need a saved lifetime counter. This is
## separate from price-impact volume so grid exports and contract sales can count
## as sales without moving the ordinary spot-market glut calculation.
func record_lifetime_sale_volume(good_id: String, qty: int) -> void:
	if good_id == "" or qty <= 0:
		return
	_lifetime_sold[good_id] = int(_lifetime_sold.get(good_id, 0)) + qty

func lifetime_sold(good_id: String) -> int:
	return int(_lifetime_sold.get(good_id, 0))

func lifetime_sold_total() -> int:
	var total := 0
	for qty in _lifetime_sold.values():
		total += int(qty)
	return total

func reset_lifetime_sales() -> void:
	_lifetime_sold.clear()

func record_market_buy_volume(good_id: String, qty: int) -> void:
	if good_id == "" or qty <= 0:
		return
	_turn_bought[good_id] = int(_turn_bought.get(good_id, 0)) + qty

## The 2x/3x/4x per-turn volume thresholds for a good, or [] when the good has
## no active producing recipe (no base output → no impact).
func impact_thresholds(good_id: String) -> PackedInt32Array:
	var base_out := Catalog.base_output_for_good(good_id)
	if base_out <= 0:
		return PackedInt32Array()
	return PackedInt32Array([base_out * 2, base_out * 3, base_out * 4])

func get_buy_price(good_id: String) -> float:
	# The price you PAY to buy a unit from the market — the sale price plus the
	# market spread (EconomyConfig.MARKET_BUY_MARKUP), which a Chief Markets advisor
	# can tighten via the "market_spread" modifier domain.
	var spread_mult: float = maxf(0.0, 1.0 + float(Modifiers.resolve_pct("market_spread", "*", {}).get("net", 0.0)) / 100.0)
	return get_price(good_id) * (1.0 + EconomyConfig.MARKET_BUY_MARKUP * spread_mult)

# The realised market SALE price for one unit: get_price() plus any market_price
# uplift (research / Chief Markets), CLAMPED so it can never exceed the buy price.
# Game rule: sale price <= buy price, otherwise a player could buy from the market
# and resell at a profit (arbitrage). Special-order deliveries are the sole exception
# — their premium pays for fulfilment and is priced separately, so they bypass this.
func get_sale_price(good_id: String, ctx: Dictionary = {}) -> float:
	var lifted: float = Modifiers.apply("market_price", good_id, get_price(good_id), ctx)
	return minf(lifted, get_buy_price(good_id))

func get_estimated_price_in_n_turns(good_id: String, n: int) -> float:
	# Forecast off the EFFECTIVE price (impact held constant): base decay is the
	# only component we can extrapolate.
	var current: float = get_price(good_id)
	var good: Dictionary = Catalog.get_good(good_id)
	var decay: float = good.get("decay_rate", 0.0)
	return current * pow(1.0 - decay, n)

# --- Save/load (orchestrated by the SaveLoad autoload; docs/save_load_spec.md) ---

func export_state() -> Dictionary:
	# Per-turn volume trackers are transient (consumed by tick_turn the same
	# frame the turn resolves; saving is DECIDE-only). Persist accumulated price
	# impact and lifetime sale volume used by research conditions.
	return {
		"prices": prices.duplicate(true),
		"impact_pct": impact_pct.duplicate(true),
		"lifetime_sold": _lifetime_sold.duplicate(true),
	}

func import_state(d: Dictionary) -> void:
	# Re-seed from the catalog first so goods added since the save keep their base
	# price, then overlay the saved (decayed) prices. Silent: SaveLoad emits
	# prices_updated once after every system imports.
	for good in Catalog.all_goods():
		prices[good.id] = good.base_price
	var saved: Dictionary = d.get("prices", {})
	for good_id in saved:
		prices[good_id] = float(saved[good_id])
	impact_pct = (d.get("impact_pct", {}) as Dictionary).duplicate(true)
	_lifetime_sold = (d.get("lifetime_sold", {}) as Dictionary).duplicate(true)
	_turn_sold.clear()
	_turn_bought.clear()

## Per-good price decay is suppressed until this turn (owner ruling 2026-07-27), then runs
## the existing per-good path unchanged. The monotonic downward drift is deliberate design
## pressure — this is a GRACE PERIOD, not mean-reversion: it gives the opening ~30 turns a
## flat margin so a player learning the game doesn't watch their number rot while they read
## the tutorial. Measured: the cluster's net moves only +16.00 -> +15.71 across t1..t20.
const DECAY_FIRST_TURN := 30

func tick_turn() -> void:
	var decay_live: bool = int(TurnManager.current_turn) >= DECAY_FIRST_TURN
	for good_id in prices.keys():
		var good: Dictionary = Catalog.get_good(good_id)
		var decay: float = float(good.get("decay_rate", 0.0)) if decay_live else 0.0
		prices[good_id] = prices[good_id] * (1.0 - decay)
		_tick_impact(str(good_id))
	_turn_sold.clear()
	_turn_bought.clear()
	prices_updated.emit()

## Fold this turn's net player volume into the good's accumulated impact.
## Over-threshold volume accrues at the band's rate (glut down / deficit up);
## at-or-under-threshold turns recover toward 0. Cap ±PRICE_IMPACT_CAP_PCT.
func _tick_impact(good_id: String) -> void:
	var net: int = int(_turn_sold.get(good_id, 0)) - int(_turn_bought.get(good_id, 0))
	var rate: float = EconomyConfig.price_impact_rate(net, Catalog.base_output_for_good(good_id))
	var a := get_impact_pct(good_id)
	if rate > 0.0:
		a += -rate if net > 0 else rate
	else:
		# Recovery scales with how deep the impact is, so the continuous curve can't
		# ratchet a good to the floor and pin it there (see EconomyConfig).
		a = move_toward(a, 0.0, EconomyConfig.price_impact_recovery(a))
	a = clampf(a, -EconomyConfig.PRICE_IMPACT_CAP_PCT, EconomyConfig.PRICE_IMPACT_CAP_PCT)
	if absf(a) < 0.0001:
		impact_pct.erase(good_id)
	else:
		impact_pct[good_id] = a

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

	if good_id_hint == "":
		good_id_hint = TransportService.route_good_for_manifest(goods_qtys)
	var route := TransportService.route_to_nearest_port(source_tile, good_id_hint)
	var port := str(route.get("port", ""))
	if port == "" or not TransportService.route_is_reachable(route):
		return {}
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
		# market_price modifiers (research like Forward Contracts, Chief Markets) lift the
		# SALE price only — applied here, not in get_price(), so buy prices are unaffected.
		# Ordinary market sales are clamped to the buy price (no arbitrage); special-order
		# deliveries keep the raw uplifted price and add their premium downstream.
		var _ctx := {"good_id": str(gid), "good_internal": str(Catalog.get_good(str(gid)).get("internal_name", ""))}
		var unit_price: float = (Modifiers.apply("market_price", str(gid), get_price(str(gid)), _ctx)
			if special_order_id != "" else get_sale_price(str(gid), _ctx))
		var revenue: float = float(sold) * unit_price
		items.append({"good_id": str(gid), "qty": sold, "revenue": revenue})
		total_qty += sold
		total_revenue += revenue
	if items.is_empty():
		return {}

	# Glut feed: ordinary market sales move the price (special-order deliveries
	# are contract-priced and don't).
	if special_order_id == "":
		for it in items:
			record_market_sale_volume(str(it.good_id), int(it.qty))
	else:
		for it in items:
			record_lifetime_sale_volume(str(it.good_id), int(it.qty))

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
