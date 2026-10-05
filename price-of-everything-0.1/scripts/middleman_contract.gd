extends RefCounted
## Phase-0 pure contract. No autoload, trade execution, loans, stock or turn hooks.
## Production integration and authoritative holdings/settlement remain phase 1.
const VERSION := 1
const TARIFF_ID := "local_suppliers_hub_haulage_v3"
const AD_VALOREM := 0.005
## The cargo classes Local Suppliers trade, with the flat haulage per unit a snapshot without its own haul rate is
## priced on.
const CLASS_RATES := {"solid_light": 0.025, "solid_heavy": 0.08, "ultra_heavy": 0.6, "safe_liquid": 0.08, "hazard_liquid": 0.15, "gas": 0.2}
const PROTOTYPE_GOODS := ["g_006", "g_007", "g_008"]
## What Local Suppliers pay against how much a hub area has sold of a good this turn, in multiples of the good's
## band size (one building's base output, inflated as the market's impact thresholds are): [up to, price change].
## Each unit is priced by the band it falls in, so selling more never lowers what the earlier units fetched.
const SALE_BANDS := [[3.0, 0.05], [4.5, 0.0], [INF, -0.05]]
const EPSILON := 0.00000001

static func _reject(reason: String) -> Dictionary:
	return {"ok":false,"reason":reason}

static func _quantity(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0.0 and float(value) == floorf(float(value))

static func operation_id(match_id: String, turn: int, building_id: String) -> String:
	# JSON tuple avoids ambiguous delimiter collisions and includes match identity.
	return JSON.stringify([match_id, turn, building_id])

## prices[good] contains reference/get_price, buy/get_buy_price, sale/get_sale_price,
## and transport_class. Caller snapshots all three from the ordinary market APIs.
## Fee reference is BEFORE buying markup, including market impact and carbon.
## A live snapshot also carries haul_rate (the good's freight per leg) and band_units (its sale band size).
## coefficient is the location's haul multiplier: trips to its hub times its settlement factor.
## area_sold is what the selling tile's hub area has already sold this turn, by good; it places a sale in its bands.
static func quote(side: String, lines: Array, prices: Dictionary, coefficient: float, allowed_goods: Array = PROTOTYPE_GOODS, area_sold: Dictionary = {}) -> Dictionary:
	if side not in ["buy", "sell"]: return _reject("invalid_side")
	if not is_finite(coefficient) or coefficient <= 0.0: return _reject("unsupported_location")
	var quantities := {}
	for line in lines:
		if not line is Dictionary or not _quantity(line.get("quantity", null)): return _reject("invalid_quantity")
		var qty := int(line.quantity)
		if qty == 0: continue
		var good := str(line.get("good", ""))
		if good not in allowed_goods: return _reject("unsupported_good")
		quantities[good] = int(quantities.get(good, 0)) + qty
	var goods: Array = quantities.keys()
	goods.sort()
	var goods_value := 0.0
	var fee := 0.0
	var band_adjustment := 0.0
	var items := []
	# Entire quote validates before callers can acquire anything. No live mutation.
	for good in goods:
		if not prices.get(good, null) is Dictionary: return _reject("missing_price")
		var p: Dictionary = prices[good]
		for key in ["reference", "buy", "sale"]:
			if not (p.get(key) is int or p.get(key) is float) or not is_finite(float(p[key])) or float(p[key]) < 0.0:
				return _reject("invalid_price")
		if not bool(p.get("is_buyable" if side == "buy" else "is_sellable", true)): return _reject("not_tradeable")
		var cargo := str(p.get("transport_class", ""))
		if not CLASS_RATES.has(cargo): return _reject("unsupported_class")
		var qty := int(quantities[good])
		var unit := float(p.buy if side == "buy" else p.sale)
		var value := qty * unit
		if side == "sell":
			value = banded_sale_value(qty, unit, float(p.buy), float(p.get("band_units", 0.0)), int(area_sold.get(good, 0)))
		# The port's base charge on the unit (its ad valorem and weight charge), then the haul between the tile
		# and its hub. A snapshot without a port charge takes the ad valorem on its reference.
		var port_part := float(p.port_charge) if p.has("port_charge") else AD_VALOREM * float(p.reference)
		var haul := float(p.haul_rate) if p.has("haul_rate") else float(CLASS_RATES[cargo])
		var service := qty * (port_part + haul * coefficient)
		goods_value += value
		fee += service
		band_adjustment += value - qty * unit
		items.append({"good":good,"quantity":qty,"unit_price":unit,"fee_reference":float(p.reference),"goods_value":value,
			"band_adjustment":value - qty * unit,"fee":service})
	return {"ok":true,"contract_version":VERSION,"tariff_id":TARIFF_ID,"side":side,"coefficient":coefficient,
		"items":items,"goods_value":goods_value,"band_adjustment":band_adjustment,"fee":fee,
		"cash_out":goods_value+fee if side=="buy" else 0.0,
		"net_receipt":goods_value-fee if side=="sell" else 0.0}

## What `qty` units fetch at `unit` each when the hub area has already sold `sold_before` this turn: each unit takes
## the price change of the band it falls in, never above the market's buy price. No band size means no bands.
static func banded_sale_value(qty: int, unit: float, buy: float, band_units: float, sold_before: int) -> float:
	if band_units <= 0.0 or qty <= 0: return qty * unit
	var value := 0.0
	var placed := 0
	for band: Array in SALE_BANDS:
		var top: float = float(band[0]) * band_units
		var room: int = qty - placed if is_inf(top) else clampi(int(floorf(top)) - (sold_before + placed), 0, qty - placed)
		if room <= 0: continue
		value += room * minf(unit * (1.0 + float(band[1])), buy)
		placed += room
		if placed >= qty: break
	return value

## Caller passes holdings for THIS building only and already-known feasibility.
## running_reserve is conservative batch labour+maintenance+grid obligations.
## commitments protects due obligations and previously reserved future purchases.
## No expected-sales parameter: sales cannot enter the admission budget.
static func plan_batch(required: Dictionary, private_holdings: Dictionary, prices: Dictionary,
		coefficient: float, budget: Dictionary, feasible: bool = true, allowed_goods: Array = PROTOTYPE_GOODS) -> Dictionary:
	if not feasible: return _reject("production_blocked")
	for key in ["cash", "credit_available", "commitments", "running_reserve", "minimum_loan"]:
		if not (budget.get(key) is int or budget.get(key) is float) or not is_finite(float(budget[key])):
			return _reject("invalid_budget")
		if key != "cash" and float(budget[key]) < 0.0: return _reject("invalid_budget")
	for good in private_holdings:
		if not _quantity(private_holdings[good]): return _reject("invalid_holding")
		if int(private_holdings[good]) > 0 and not required.has(good): return _reject("unreleased_holding")
	var reuse := {}
	var lines := []
	for good in required:
		if not _quantity(required[good]) or str(good) not in allowed_goods: return _reject("unsupported_requirement")
		if int(private_holdings.get(good, 0)) > int(required[good]): return _reject("holding_exceeds_cycle")
		var held := int(private_holdings.get(good, 0))
		reuse[good] = held
		lines.append({"good":str(good),"quantity":int(required[good])-held})
	var buy := quote("buy", lines, prices, coefficient, allowed_goods)
	if not bool(buy.ok): return buy
	var reserved := float(buy.cash_out) + float(budget.running_reserve)
	var available_cash := float(budget.cash) - float(budget.commitments)
	var shortfall := maxf(0.0, reserved - available_cash)
	var draw := maxf(shortfall, float(budget.minimum_loan)) if shortfall > EPSILON else 0.0
	if draw > float(budget.credit_available) + EPSILON: return _reject("insufficient_funding")
	return {"ok":true,"purchase":buy,"reuse":reuse,"funding_draw":draw,"batch_reserve":reserved,
		"cash_after_purchase":float(budget.cash)+draw-float(buy.cash_out),
		"unallocated_cash":available_cash+draw-reserved,
		"credit_remaining":float(budget.credit_available)-draw}
