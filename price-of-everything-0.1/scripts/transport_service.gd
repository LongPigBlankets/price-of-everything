extends Node
## Stateless transport quoting and routing facade.
##
## MatchState owns shipment persistence. Catalog owns the route graph. This service
## is the single public seam for route fallback, per-good transport cost, market
## gateway quotes, and multi-good manifest quotes.

const INF_TURNS := 1 << 30


func nearest_port_tile(from_tile_id: String) -> String:
	return Catalog.nearest_port_tile(from_tile_id)


func tile_distance(source_tile: String, destination_tile: String) -> int:
	if source_tile == "" or destination_tile == "":
		return 0
	return Catalog.tile_hex_distance(source_tile, destination_tile)


func route(source_tile: String, destination_tile, good_id: String = "") -> Dictionary:
	if destination_tile == null or str(destination_tile) == "":
		return _empty_route()
	var dest := str(destination_tile)
	if source_tile == "" or source_tile == dest:
		return {
			"tile_distance": tile_distance(source_tile, dest),
			"turns": 0,
			"delayed": false,
			"reachable": source_tile != "",
			"path": [source_tile] if source_tile != "" else [],
			"legs": [],
			"tiles": [source_tile] if source_tile != "" else [],
		}

	var routed := Catalog.route(source_tile, dest, good_id)
	var turns: int = int(routed.get("turns", 0))
	if turns >= INF_TURNS:
		if Catalog.requires_pipeline(good_id):
			return _unreachable_route(source_tile, dest)
		turns = EconomyConfig.transport_turns_for_tile_distance(tile_distance(source_tile, dest))
	return {
		"tile_distance": tile_distance(source_tile, dest),
		"turns": turns,
		"delayed": turns > 1,
		"reachable": true,
		"path": routed.get("path", []),
		"legs": routed.get("legs", []),
		"tiles": routed.get("tiles", []),
	}


func route_to_nearest_port(source_tile: String, good_id: String = "") -> Dictionary:
	var port := nearest_port_tile(source_tile) if source_tile != "" else ""
	var r := route(source_tile, port, good_id)
	r["port"] = port
	return r

func route_good_for_manifest(goods_qtys: Dictionary) -> String:
	return _route_good_for_manifest(goods_qtys)

func route_is_reachable(route_data: Dictionary) -> bool:
	if route_data.is_empty():
		return false
	return bool(route_data.get("reachable", int(route_data.get("turns", INF_TURNS)) < INF_TURNS))


func transport_cost(good_id: String, qty: int, transport_turns: int, mode_mult: float = 1.0) -> float:
	return EconomyConfig.transport_cost_for(good_id, qty, transport_turns, mode_mult)


func transport_cost_for_route(good_id: String, qty: int, route_data: Dictionary, surcharge: float = 1.0) -> float:
	# A route that can't be travelled costs nothing — the INF_TURNS sentinel would
	# otherwise explode the per-turn cost into the billions (fluids with no pipe
	# network to their destination were charged ~£1e9 and never delivered).
	if not route_is_reachable(route_data):
		return 0.0
	var cost: float = EconomyConfig.transport_cost_for_route(good_id, qty, route_data) * surcharge
	# transport_cost modifiers (research like Route Optimization) trim haulage cost.
	cost = Modifiers.apply("transport_cost", good_id, cost, {"good_id": good_id})
	# Throughput congestion, charged MARGINALLY: only the units above a congested link's
	# remaining capacity pay the surcharge (+100% over cap, +200% over cap + L1 buffer).
	# The units that still fit ride at the base rate, so upgrading infra pays back by
	# moving quantity out of the penalised band rather than by discounting the whole haul.
	var cong: Dictionary = MatchState.route_congestion(route_data)
	var tier: int = int(cong.get("tier", 0))
	if tier > 0 and qty > 0:
		var mult: float = 2.0 if tier == 1 else 3.0
		var over: int = maxi(0, qty - int(cong.get("headroom", 0)))
		var within: int = qty - over
		cost *= (float(within) + float(over) * mult) / float(qty)
	return cost


## Split a route's *actual* freight charge by infrastructure mode.  The base
## route price is used only as a weighting; the resulting rows include research
## discounts and congestion, and therefore add back to transport_cost_for_route.
## A route with no built leg is the ordinary overland road haul.
func transport_cost_breakdown_for_route(good_id: String, qty: int, route_data: Dictionary, surcharge: float = 1.0) -> Dictionary:
	if not route_is_reachable(route_data) or qty <= 0:
		return {}
	var weights: Dictionary = {}
	var legs: Array = route_data.get("legs", [])
	var class_rate := EconomyConfig.transport_rate_for_good(good_id)
	if legs.is_empty():
		var turns := maxi(int(route_data.get("turns", 0)), 0)
		weights["roads"] = float(qty) * float(turns) * class_rate * surcharge
	else:
		for leg: Dictionary in legs:
			var mode := str(leg.get("mode", "roads"))
			weights[mode] = float(weights.get(mode, 0.0)) + float(qty) * class_rate * float(EconomyConfig.TRANSPORT_MODE_COST_MULT.get(mode, 1.0)) * surcharge
	return scale_transport_breakdown(weights, transport_cost_for_route(good_id, qty, route_data, surcharge))


## Rescale a component dictionary while preserving its proportions. Used when a
## modifier applies to a whole route rather than to individual links.
func scale_transport_breakdown(breakdown: Dictionary, target_total: float) -> Dictionary:
	var source_total := 0.0
	for value in breakdown.values():
		source_total += float(value)
	if source_total <= 0.0 or target_total <= 0.0:
		return {}
	var scaled: Dictionary = {}
	for key in breakdown.keys():
		scaled[str(key)] = float(breakdown[key]) * target_total / source_total
	return scaled


func link_capacity(mode: String, level: int) -> float:
	return EconomyConfig.transport_link_capacity(mode, level)


func quote_manifest(source_tile: String, destination_tile: String, goods_qtys: Dictionary, options: Dictionary = {}) -> Dictionary:
	var surcharge := float(options.get("surcharge", 1.0))
	var items: Array = []
	var total_qty := 0
	var total_cost := 0.0
	var max_turns := 0
	var first_route: Dictionary = {}
	for good_id in goods_qtys.keys():
		var qty := int(goods_qtys[good_id])
		if qty <= 0:
			continue
		var good_key := str(good_id)
		var route_data := route(source_tile, destination_tile, good_key)
		if not route_is_reachable(route_data):
			continue
		var turns := int(route_data.get("turns", 0))
		var cost := transport_cost_for_route(good_key, qty, route_data, surcharge)
		items.append({"good_id": good_key, "qty": qty, "cost": cost, "route": route_data, "turns": turns})
		total_qty += qty
		total_cost += cost
		max_turns = maxi(max_turns, turns)
		if first_route.is_empty():
			first_route = route_data
	if items.is_empty():
		return {}
	return {
		"source": source_tile,
		"dest": destination_tile,
		"route": first_route,
		"turns": max_turns,
		"items": items,
		"total_qty": total_qty,
		"cost": total_cost,
		"per_turn": total_cost / float(maxi(max_turns, 1)),
		"surcharged": surcharge > 1.0,
	}


func quote_market_buy(dest_tile: String, good_id: String, qty: int, covered: bool = false) -> Dictionary:
	var port := nearest_port_tile(dest_tile)
	if dest_tile == "" or good_id == "" or qty <= 0 or port == "":
		return {}
	# A liquid/gas can only come ashore where the port tile has the pipe for it — pipes, or
	# reinf_pipes for hazard liquids. This closes the same-tile loophole (a building sitting ON
	# the port used to get fluids delivered with no pipe at all); off-port buyers are also gated
	# by the pipe network in route() below. Solids are unaffected (helper returns true for them).
	if not Catalog.tile_can_pipe_good(port, good_id):
		return {}
	var route_data := route(port, dest_tile, good_id)
	if not route_is_reachable(route_data):
		return {}
	var turns := int(route_data.get("turns", 0))
	var in_range := tile_distance(port, dest_tile) <= EconomyConfig.SEAPORT_RANGE_TILES
	var seaport_covered := covered and in_range
	if seaport_covered:
		turns = 1
		route_data["turns"] = turns
		route_data["delayed"] = false
	var unit_price := MarketState.get_buy_price(good_id)
	var goods_cost := float(qty) * unit_price
	var route_transport := 0.0 if seaport_covered else transport_cost_for_route(good_id, qty, route_data)
	var route_breakdown: Dictionary = {} if seaport_covered else transport_cost_breakdown_for_route(good_id, qty, route_data)
	# Risk Desk Procedures applies only to materials bought FROM the market, never
	# to player sales or ordinary inter-tile freight.
	route_transport = Modifiers.apply("market_input_transport", good_id, route_transport, {"good_id": good_id})
	route_breakdown = scale_transport_breakdown(route_breakdown, route_transport)
	# Sea freight replaces the old standing subscription charge. It is deliberately
	# quoted without mutating port usage; MatchState commits it only after the buy clears funds.
	var sea_transport := MatchState.preview_sea_shipping(port, good_id, qty)
	var sea_cost := float(sea_transport.get("total", 0.0))
	var transport := route_transport + sea_cost
	return {
		"port": port,
		"route": route_data,
		"turns": turns,
		"qty": qty,
		"goods_cost": goods_cost,
		"transport_cost": transport,
		"cost": goods_cost + transport,
		"sea_transport_cost": sea_cost,
		"sea_transport": sea_transport,
		"route_transport_breakdown": route_breakdown,
		"covered": seaport_covered,
	}


func quote_market_sell(source_tile: String, goods_qtys: Dictionary, covered_goods: Dictionary = {}) -> Dictionary:
	var port := nearest_port_tile(source_tile) if source_tile != "" else ""
	if source_tile == "" or port == "":
		return {}
	var route_good_id := _route_good_for_manifest(goods_qtys)
	var route_data := route(source_tile, port, route_good_id)
	if not route_is_reachable(route_data):
		return {}
	var in_range := tile_distance(source_tile, port) <= EconomyConfig.SEAPORT_RANGE_TILES
	var covered_all := in_range and not goods_qtys.is_empty()
	for good_id in goods_qtys.keys():
		if int(goods_qtys[good_id]) > 0 and not bool(covered_goods.get(str(good_id), false)):
			covered_all = false
	var turns := 1 if covered_all else int(route_data.get("turns", 0))
	var transport := 0.0
	for good_id in goods_qtys.keys():
		var qty := int(goods_qtys[good_id])
		if qty <= 0:
			continue
		var good_key := str(good_id)
		if not (in_range and bool(covered_goods.get(good_key, false))):
			transport += transport_cost_for_route(good_key, qty, route_data)
	return {
		"port": port,
		"route": route_data,
		"turns": turns,
		"transport_cost": transport,
		"covered_all": covered_all,
	}


func shipment_route_fields(route_data: Dictionary) -> Dictionary:
	return {
		"tile_distance": int(route_data.get("tile_distance", 0)),
		"transport_turns": int(route_data.get("turns", 0)),
		"turns_remaining": int(route_data.get("turns", 0)),
		"path": route_data.get("path", []),
		"legs": route_data.get("legs", []),
		"tiles": route_data.get("tiles", []),
	}


func _empty_route() -> Dictionary:
	return {"tile_distance": 0, "turns": 0, "delayed": false, "reachable": false, "path": [], "legs": [], "tiles": []}

func _unreachable_route(source_tile: String, dest_tile: String) -> Dictionary:
	return {
		"tile_distance": tile_distance(source_tile, dest_tile),
		"turns": INF_TURNS,
		"delayed": true,
		"reachable": false,
		"path": [],
		"legs": [],
		"tiles": [],
	}

func _route_good_for_manifest(goods_qtys: Dictionary) -> String:
	var first_good := ""
	for good_id in goods_qtys.keys():
		if int(goods_qtys[good_id]) <= 0:
			continue
		var key := str(good_id)
		if first_good == "":
			first_good = key
		if Catalog.requires_pipeline(key):
			return key
	return first_good
