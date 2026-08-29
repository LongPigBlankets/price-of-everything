extends Node

const FORECAST_TURNS := 10

var prices: Dictionary = {}  # good_id -> impact-FREE base price (float); STATIC since decay retired

# --- Price impact (glut / deficit) ---
# THE price model: per-good price decay is retired (owner ruling 2026-08-28,
# docs/price-impact-ladder-spec.md), so accumulated glut/deficit impact is the
# only thing that moves a price. Negative = glut discount (net player selling
# over threshold), positive = deficit premium (net buying). Accrual is LINEAR —
# percentage points of the static base price, applied once in get_price() —
# clamped to [EconomyConfig.PRICE_IMPACT_FLOOR_PCT, PRICE_IMPACT_CEILING_PCT]
# (price 40%..250% of base). The rolling window of the last
# PRICE_IMPACT_RECOVERY_TURNS turns of net volume gates the regime: while its
# average stays over the first ladder rung the market believes the pressure is
# real (quiet turns HOLD — no pulsing exploit); once it falls back to or under
# 1x, the price walks home to base over PRICE_IMPACT_RECOVERY_TURNS turns.
# Ladder + inflation schedule in economy_config.gd.
var impact_pct: Dictionary = {}     # good_id -> accumulated %
var _net_history: Dictionary = {}   # good_id -> Array[float], recent per-turn net volume
var _recovery_step: Dictionary = {} # good_id -> %-points/turn of the in-progress walk-back
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
##
## Once the carbon levy is in force the price carries the carbon EMBODIED in making the good,
## so buying it costs what making it the conventional way would have cost in levy. Without
## this the market is a laundering route: a player buys steel instead of smelting it and the
## carbon squeeze never reaches them. Added on top of the decayed base rather than folded into
## it because a policy overlay should not compound with per-turn price drift.
func get_base_price_now(good_id: String) -> float:
	return prices.get(good_id, 1.0) + carbon_component(good_id)

## The carbon slice of this turn's price — £0 until the levy starts, and broken out so the
## market tab and the building readout can show WHY a good got dearer.
##
## Power is the one good whose carbon is not fixed by its recipe: it comes off the national
## grid, and the grid decarbonises over the game. Scaling it here rather than at each call
## site means grid imports (Power._settle) and market purchases of power move together
## instead of drifting apart.
func carbon_component(good_id: String) -> float:
	var embodied := Catalog.embodied_carbon(good_id)
	if embodied <= 0.0:
		return 0.0
	var turn := int(TurnManager.current_turn)
	var carbon := embodied * EconomyConfig.CO2_TAX_RATE * PolicyState.co2_tax_scale(turn)
	if good_id == str(Catalog.get_good_by_internal_name("power").get("id", "")):
		carbon *= PolicyState.grid_carbon_intensity(turn)
	return carbon

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

## The ladder's per-turn volume thresholds for a good at the CURRENT turn
## (threshold inflation applied), or [] when the good has no active producing
## recipe (no base output → no impact). One entry per EconomyConfig ladder rung;
## entry i is the largest net volume that does NOT yet accrue rung i's rate.
func impact_thresholds(good_id: String) -> PackedInt32Array:
	var base_out := Catalog.base_output_for_good(good_id)
	if base_out <= 0:
		return PackedInt32Array()
	var scale: float = EconomyConfig.impact_threshold_scale(int(TurnManager.current_turn))
	var out := PackedInt32Array()
	for rung in EconomyConfig.PRICE_IMPACT_LADDER:
		out.append(int(floorf(float(rung[0]) * float(base_out) * scale)))
	return out

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
	# Projects the SUSTAINED course — "if you keep doing what you have been doing".
	# It reads the rolling window, NOT the per-turn trackers: tick_turn clears
	# those at end of turn, so during DECIDE (when the player reads the market
	# panel) they are always empty, and projecting off them told a player
	# mid-glut that their price was about to recover while it was still falling.
	# The regime logic here mirrors _tick_impact so the two cannot disagree.
	var avg: float = rolling_net_volume(good_id)
	var base_out: int = Catalog.base_output_for_good(good_id)
	var scale: float = EconomyConfig.impact_threshold_scale(int(TurnManager.current_turn))
	var rate: float = EconomyConfig.price_impact_rate(avg, base_out, scale)
	var a: float = get_impact_pct(good_id)
	var projected: float = a
	if rate > 0.0:
		projected = a + (-rate if avg > 0.0 else rate) * float(n)
	elif absf(a) > 0.0:
		projected = move_toward(a, 0.0, absf(a) / float(EconomyConfig.PRICE_IMPACT_RECOVERY_TURNS) * float(n))
	projected = clampf(projected, EconomyConfig.PRICE_IMPACT_FLOOR_PCT, EconomyConfig.PRICE_IMPACT_CEILING_PCT)
	return get_base_price_now(good_id) * (1.0 + projected / 100.0)

## Mean net market volume over the rolling window (positive = net selling). This
## is the number the impact model actually runs on, so UI should show it rather
## than a single turn's figure.
func rolling_net_volume(good_id: String) -> float:
	var hist: Array = _net_history.get(good_id, [])
	if hist.is_empty():
		return 0.0
	var total := 0.0
	for v in hist:
		total += float(v)
	return total / float(hist.size())

# --- Save/load (orchestrated by the SaveLoad autoload; docs/save_load_spec.md) ---

func export_state() -> Dictionary:
	# Per-turn volume trackers are transient (consumed by tick_turn the same
	# frame the turn resolves; saving is DECIDE-only). Persist accumulated price
	# impact, the rolling net-volume window it depends on, any in-progress
	# walk-back step, and lifetime sale volume used by research conditions.
	# Base prices are NOT saved: they are static catalog data now decay is
	# retired (docs/price-impact-ladder-spec.md §7).
	return {
		"impact_pct": impact_pct.duplicate(true),
		"net_history": _net_history.duplicate(true),
		"recovery_step": _recovery_step.duplicate(true),
		"lifetime_sold": _lifetime_sold.duplicate(true),
	}

func import_state(d: Dictionary) -> void:
	# Re-seed every price from the catalog. Saved prices are deliberately NOT
	# overlaid: with decay retired the base series is static, and a pre-change
	# save carries decayed (lower) prices — re-anchoring moves them UP to base,
	# never down (tolerant reader; no version bump). Silent: SaveLoad emits
	# prices_updated once after every system imports.
	for good in Catalog.all_goods():
		prices[good.id] = good.base_price
	impact_pct = (d.get("impact_pct", {}) as Dictionary).duplicate(true)
	_net_history = (d.get("net_history", {}) as Dictionary).duplicate(true)
	_recovery_step = (d.get("recovery_step", {}) as Dictionary).duplicate(true)
	_lifetime_sold = (d.get("lifetime_sold", {}) as Dictionary).duplicate(true)
	_turn_sold.clear()
	_turn_bought.clear()

func tick_turn() -> void:
	# Price decay is RETIRED (owner ruling 2026-08-28, reversing 2026-07-27's
	# "prices always fall" — docs/price-impact-ladder-spec.md). Base prices are
	# static; only glut/deficit impact moves what the player sees, and the
	# downward squeeze rests on the carbon levy, port fees and input premia.
	for good_id in prices.keys():
		_tick_impact(str(good_id))
	_turn_sold.clear()
	_turn_bought.clear()
	prices_updated.emit()

## Fold this turn's net player volume into the good's accumulated impact.
## Over-threshold volume accrues at the ladder rung's rate (glut down / deficit
## up). The rolling window of the last PRICE_IMPACT_RECOVERY_TURNS turns of net
## volume gates recovery: while its average stays over the first rung, quiet
## turns HOLD the price where it is (pausing buys no forgiveness); once the
## average falls to or under 1x, the impact walks linearly back to zero over
## PRICE_IMPACT_RECOVERY_TURNS turns. Clamp to [floor, ceiling].
func _tick_impact(good_id: String) -> void:
	var net: int = int(_turn_sold.get(good_id, 0)) - int(_turn_bought.get(good_id, 0))
	var a := get_impact_pct(good_id)
	if net == 0 and a == 0.0 and not _net_history.has(good_id):
		return  # untouched good — keep the window dict (and the save) sparse
	var hist: Array = _net_history.get(good_id, [])
	hist.append(float(net))
	while hist.size() > EconomyConfig.PRICE_IMPACT_RECOVERY_TURNS:
		hist.pop_front()
	_net_history[good_id] = hist
	var avg := 0.0
	for v in hist:
		avg += float(v)
	avg /= float(hist.size())
	var base_out: int = Catalog.base_output_for_good(good_id)
	var scale: float = EconomyConfig.impact_threshold_scale(int(TurnManager.current_turn))
	if EconomyConfig.price_impact_rate(avg, base_out, scale) > 0.0:
		# The window says the pressure is real: accrue this turn's rung. A quiet
		# turn inside a loud window holds — it does not recover.
		var rate: float = EconomyConfig.price_impact_rate(float(net), base_out, scale)
		if rate > 0.0:
			a += -rate if net > 0 else rate
		_recovery_step.erase(good_id)
	elif absf(a) > 0.0:
		# The window has gone quiet: snapshot the gap once, close it linearly.
		if not _recovery_step.has(good_id):
			_recovery_step[good_id] = absf(a) / float(EconomyConfig.PRICE_IMPACT_RECOVERY_TURNS)
		a = move_toward(a, 0.0, float(_recovery_step[good_id]))
	a = clampf(a, EconomyConfig.PRICE_IMPACT_FLOOR_PCT, EconomyConfig.PRICE_IMPACT_CEILING_PCT)
	if absf(a) < 0.0001:
		impact_pct.erase(good_id)
		_recovery_step.erase(good_id)
		# A fully-recovered, currently-quiet good drops its window too.
		if net == 0 and absf(avg) < 0.0001:
			_net_history.erase(good_id)
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
	var transport_breakdown: Dictionary = {}
	if pay_transport_from_seller:
		for it in items:
			var good_id := str(it.good_id)
			var qty := int(it.qty)
			transport_cost += TransportService.transport_cost_for_route(good_id, qty, route)
			var route_breakdown := TransportService.transport_cost_breakdown_for_route(good_id, qty, route)
			for mode in route_breakdown:
				transport_breakdown[mode] = float(transport_breakdown.get(mode, 0.0)) + float(route_breakdown[mode])
	# Sea costs apply to every market sale. Manual sales keep their historical gross
	# inland freight, but never avoid the port charge.
	for it in items:
		var sea_charge := MatchState.commit_sea_shipping(port, str(it.good_id), int(it.qty), "sell")
		transport_cost += float(sea_charge.get("total", 0.0))
		transport_breakdown["port_fees"] = float(transport_breakdown.get("port_fees", 0.0)) + float(sea_charge.get("base_fee", 0.0))
		transport_breakdown["port_insurance"] = float(transport_breakdown.get("port_insurance", 0.0)) + float(sea_charge.get("insurance_fee", 0.0))
	if transport_cost > 0.0:
		MatchState.add_money(-transport_cost)

	var sale_record := {
		"tile_id": source_tile,
		"items": items,
		"total_qty": total_qty,
		"total_revenue": total_revenue,
		"transport_turns": turns,
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
		"transport_breakdown": transport_breakdown,
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
