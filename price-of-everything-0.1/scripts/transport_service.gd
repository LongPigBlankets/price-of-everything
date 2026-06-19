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
			"path": [source_tile] if source_tile != "" else [],
			"legs": [],
			"tiles": [source_tile] if source_tile != "" else [],
		}

	var routed := Catalog.route(source_tile, dest, good_id)
	var turns: int = int(routed.get("turns", 0))
	if turns >= INF_TURNS:
		turns = EconomyConfig.transport_turns_for_tile_distance(tile_distance(source_tile, dest))
	return {
		"tile_distance": tile_distance(source_tile, dest),
		"turns": turns,
		"delayed": turns > 1,
		"path": routed.get("path", []),
		"legs": routed.get("legs", []),
		"tiles": routed.get("tiles", []),
	}


func route_to_nearest_port(source_tile: String, good_id: String = "") -> Dictionary:
	var port := nearest_port_tile(source_tile) if source_tile != "" else ""
	var r := route(source_tile, port, good_id)
	r["port"] = port
	return r


func transport_cost(good_id: String, qty: int, transport_turns: int, mode_mult: float = 1.0) -> float:
	return EconomyConfig.transport_cost_for(good_id, qty, transport_turns, mode_mult)


func transport_cost_for_route(good_id: String, qty: int, route_data: Dictionary, surcharge: float = 1.0) -> float:
	var cost: float = EconomyConfig.transport_cost_for_route(good_id, qty, route_data) * surcharge
	# transport_cost modifiers (research like Route Optimization) trim haulage cost.
	cost = Modifiers.apply("transport_cost", good_id, cost, {"good_id": good_id})
	# Throughput congestion: +100% over a link's capacity, +200% over capacity + L1 cap.
	match MatchState.route_congestion_tier(route_data):
		1: cost *= 2.0
		2: cost *= 3.0
	return cost


func quote_manifest(source_tile: String, destination_tile: String, goods_qtys: Dictionary, options: Dictionary = {}) -> Dictionary:
	var route_good_id := str(options.get("route_good_id", ""))
	var surcharge := float(options.get("surcharge", 1.0))
	var route_data := route(source_tile, destination_tile, route_good_id)
	var turns := int(route_data.get("turns", 0))
	var items: Array = []
	var total_qty := 0
	var total_cost := 0.0
	for good_id in goods_qtys.keys():
		var qty := int(goods_qtys[good_id])
		if qty <= 0:
			continue
		var good_key := str(good_id)
		var cost := transport_cost_for_route(good_key, qty, route_data, surcharge)
		items.append({"good_id": good_key, "qty": qty, "cost": cost})
		total_qty += qty
		total_cost += cost
	return {
		"source": source_tile,
		"dest": destination_tile,
		"route": route_data,
		"turns": turns,
		"items": items,
		"total_qty": total_qty,
		"cost": total_cost,
		"per_turn": total_cost / float(maxi(turns, 1)),
		"surcharged": surcharge > 1.0,
	}


func quote_market_buy(dest_tile: String, good_id: String, qty: int, covered: bool = false) -> Dictionary:
	var port := nearest_port_tile(dest_tile)
	if dest_tile == "" or good_id == "" or qty <= 0 or port == "":
		return {}
	var route_data := route(port, dest_tile, good_id)
	var turns := int(route_data.get("turns", 0))
	var in_range := tile_distance(port, dest_tile) <= EconomyConfig.SEAPORT_RANGE_TILES
	var seaport_covered := covered and in_range
	if seaport_covered:
		turns = 1
		route_data["turns"] = turns
		route_data["delayed"] = false
	var unit_price := MarketState.get_buy_price(good_id)
	var goods_cost := float(qty) * unit_price
	var transport := 0.0 if seaport_covered else transport_cost_for_route(good_id, qty, route_data)
	return {
		"port": port,
		"route": route_data,
		"turns": turns,
		"qty": qty,
		"goods_cost": goods_cost,
		"transport_cost": transport,
		"cost": goods_cost + transport,
		"covered": seaport_covered,
	}


func quote_market_sell(source_tile: String, goods_qtys: Dictionary, covered_goods: Dictionary = {}) -> Dictionary:
	var port := nearest_port_tile(source_tile) if source_tile != "" else ""
	if source_tile == "" or port == "":
		return {}
	var route_data := route(source_tile, port)
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
	return {"tile_distance": 0, "turns": 0, "delayed": false, "path": [], "legs": [], "tiles": []}
