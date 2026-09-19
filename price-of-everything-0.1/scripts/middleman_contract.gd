extends RefCounted
## Phase-0 pure contract. No autoload, trade execution, loans, stock or turn hooks.
## Production integration and authoritative holdings/settlement remain phase 1.
const VERSION := 1
const TARIFF_ID := "middleman_dynamic_v1"
const AD_VALOREM := 0.005
const CLASS_RATES := {"solid_light": 0.02, "solid_heavy": 0.05, "ultra_heavy": 0.5, "safe_liquid": 0.05, "hazard_liquid": 0.1, "gas": 0.125}
const PROTOTYPE_GOODS := ["g_006", "g_007", "g_008"]
const LOCATION_FACTORS := [1.05, 1.25, 1.5, 1.75, 2.0, 2.5]
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
static func quote(side: String, lines: Array, prices: Dictionary, coefficient: float, allowed_goods: Array = PROTOTYPE_GOODS) -> Dictionary:
	if side not in ["buy", "sell"]: return _reject("invalid_side")
	if coefficient not in LOCATION_FACTORS: return _reject("unsupported_location")
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
		var service := qty * (AD_VALOREM * float(p.reference) + float(CLASS_RATES[cargo]) * coefficient)
		goods_value += value
		fee += service
		items.append({"good":good,"quantity":qty,"unit_price":unit,"fee_reference":float(p.reference),"goods_value":value,"fee":service})
	return {"ok":true,"contract_version":VERSION,"tariff_id":TARIFF_ID,"side":side,"coefficient":coefficient,
		"items":items,"goods_value":goods_value,"fee":fee,"cash_out":goods_value+fee if side=="buy" else 0.0,
		"net_receipt":goods_value-fee if side=="sell" else 0.0}

## Caller passes holdings for THIS building only and already-known feasibility.
## running_reserve is conservative batch labour+maintenance+grid obligations.
## commitments protects due obligations and previously reserved future purchases.
## No expected-sales parameter: sales cannot enter the admission budget.
static func plan_batch(required: Dictionary, private_holdings: Dictionary, prices: Dictionary,
		coefficient: float, budget: Dictionary, feasible: bool = true, allowed_goods: Array = PROTOTYPE_GOODS) -> Dictionary:
	if not feasible: return _reject("production_blocked")
	if bool(budget.get("building_credit_tab", false)): return _reject("unsupported_building_credit_tab")
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
