extends RefCounted
## A production building's economics for one turn, as the Building Detail panel's Economics section
## shows them:
##   value added in production  its output at market value, less its inputs (the ones it buys at the
##                              market's buy price, the company's own at what they would sell for),
##                              labour and upkeep (maintenance, power, storage and the carbon levy);
##   transport costs            what it pays to bring its inputs in and take its output to market,
##                              by the routes it actually uses: inland freight and the port charge,
##                              or the logistics intermediary's fee where it trades through one;
##   net value added            the first less the second.
## Every figure is quoted by the engine's own helpers, the ones the turn's cash moves by, without
## booking anything. Output that stays in stock is valued as if sold, with what shipping it to market
## would cost; `sold` says whether it is sold this turn. Freight between the company's own tiles is the
## sender's, as the engine charges it, so an input from another of its tiles costs this building no
## transport. Tax, dividends and loan repayments are the company's, not the building's, and are left out.

const Readout := preload("res://scripts/building_readout.gd")
const Status := preload("res://scripts/building_status.gd")
const Middleman := preload("res://scripts/middleman_service.gd")

## The transport lamps: green while transport costs less than this share of the goods' value on its
## side (inputs or outputs), amber below the next, red above it.
const LAMP_AMBER_SHARE := 0.03
const LAMP_RED_SHARE := 0.08
## How each part of a route's cost is named: its mode, the port, or the intermediary.
const METHOD_NAMES := {
	"roads": "Road", "rail": "Rail", "pipes": "Pipe", "reinf_pipes": "Pipe", "cables": "Cable",
	"port_fees": "Port", "port_insurance": "Port", "port_inbound": "Port", "port_outbound": "Port",
	"intermediary": "Logistics intermediary",
}


## The building's economics this turn. `shown` is false for a building with neither inputs nor
## outputs (a battery): its running costs alone are no measure beside a producer's.
static func per_turn(building: Dictionary) -> Dictionary:
	var recipe: Dictionary = Catalog.get_recipe(str(building.get("recipe_id", "")))
	var power_out := str(recipe.get("output_name", "")) == "power"
	var has_inputs := not (recipe.get("inputs", []) as Array).is_empty()
	var has_outputs := power_out or not Status.flow_output_items(recipe).is_empty()
	if not has_inputs and not has_outputs:
		return {"shown": false}
	var iid := str(building.get("instance_id", ""))
	var quote: Dictionary = Middleman.preview(iid) if Middleman.enabled(iid) else {}
	if not bool(quote.get("ok", false)):
		quote = {}

	var outputs: Array = []
	if power_out:
		# Power leaves by cable: no freight, no port. Valued at what the grid pays for it.
		var energy := float(Production._effective_power_output(building, recipe))
		outputs.append({"good_id": "power", "qty": energy, "value": energy * Power.grid_export_price(),
			"sold": true, "cost": 0.0, "breakdown": {}})
	else:
		for o: Dictionary in Readout.flow(building, recipe, true).get("outputs", []):
			var gid := str(o.get("good_id", ""))
			var qty := int(o.get("qty", 0))
			if gid != "" and qty > 0:
				outputs.append(_output_line(building, recipe, gid, qty, quote))
	var inputs: Array = []
	for inp: Dictionary in recipe.get("inputs", []):
		var qty := Production._scaled_input_qty(inp, building)
		if str(inp.get("good_id", "")) != "" and qty > 0:
			inputs.append(_input_line(building, inp, qty, quote))

	var output_value := _sum(outputs, "value")
	var input_value := _sum(inputs, "value")
	var labour := 0.0 if BuildingWorks.is_building_paused(iid) else Production._calculate_labour_cost(building, recipe)
	var maintenance := Production._calculate_maintenance_cost(building)
	var power := Power.allocated_draw_cost(str(building.get("tile_id", "")), Production._effective_energy_req(building, recipe))
	var warehousing := CostSolver.warehousing_share(iid)
	var carbon := PolicyState.run_carbon_levy(building, recipe)
	var upkeep := maintenance + power + warehousing + carbon
	var value_added := output_value - input_value - labour - upkeep
	var transport_in := _sum(inputs, "cost")
	var transport_out := _sum(outputs, "cost")
	var sold := true
	var reachable := true
	for o: Dictionary in outputs:
		sold = sold and bool(o.sold)
		reachable = reachable and not bool(o.get("unreachable", false))
	var inputs_free := input_value <= 0.0 and transport_in <= 0.0
	var output_free := not outputs.is_empty() and reachable and transport_out <= 0.0
	return {
		"shown": true,
		"outputs": outputs, "inputs": inputs,
		"output_value": output_value, "input_value": input_value,
		"labour": labour, "maintenance": maintenance, "power": power, "warehousing": warehousing,
		"carbon": carbon, "upkeep": upkeep,
		"value_added": value_added,
		"transport_in": transport_in, "transport_out": transport_out,
		"transport": transport_in + transport_out,
		"methods_in": _methods(inputs), "methods_out": _methods(outputs),
		"net_value_added": value_added - transport_in - transport_out,
		"inputs_free": inputs_free,
		"output_free_to_ship": output_free,
		"sold": sold,
		"lamp_in": "off" if inputs_free else transport_tone(transport_in, input_value),
		"lamp_out": "off" if output_free or outputs.is_empty() else transport_tone(transport_out, output_value),
	}


## A transport lamp's tone for `cost` against the value of the goods it moves.
static func transport_tone(cost: float, goods_value: float) -> String:
	var share := cost / goods_value if goods_value > 0.0 else (0.0 if cost <= 0.0 else 1.0)
	if share < LAMP_AMBER_SHARE:
		return "ok"
	return "warn" if share < LAMP_RED_SHARE else "bad"


## How a building gets an input: the logistics intermediary, its own tile's stockpile, a transfer from
## another tile, or the global market. `inbound_from` is the tile a shipment of it is coming from, if any.
static func input_supply(building: Dictionary, recipe: Dictionary, gid: String, inbound_from: String) -> String:
	var iid := str(building.get("instance_id", ""))
	if Middleman.supplies_good(iid, gid):
		return "Logistics intermediary"
	var tile := str(building.get("tile_id", ""))
	var other_tile := inbound_from != ""
	for src: Dictionary in Readout.input_sources(building, recipe):
		if str(src.get("good_id", "")) != gid:
			continue
		if str(src.get("tile_id", "")) == tile:
			return "From the tile stockpile"
		other_tile = true
	return "Tile-to-tile transfer" if other_tile else "Global market"


# --- lines --------------------------------------------------------------------------------------

## One output's value and what it costs to get it to market, by the way it goes.
static func _output_line(building: Dictionary, recipe: Dictionary, gid: String, qty: int, quote: Dictionary) -> Dictionary:
	var iid := str(building.get("instance_id", ""))
	var tile := str(building.get("tile_id", ""))
	if not quote.is_empty() and Middleman.buys_output(iid, gid):
		var item := _intermediary_item(quote.get("sale", {}), gid)
		return {"good_id": gid, "qty": qty, "value": float(item.get("goods_value", 0.0)), "sold": true,
			"cost": float(item.get("fee", 0.0)), "breakdown": {"intermediary": float(item.get("fee", 0.0))}}
	var line := {"good_id": gid, "qty": qty, "cost": 0.0, "breakdown": {}}
	var disposition := Readout._output_disposition(building, recipe, gid)
	if str(disposition.get("mode", "")) == "market":
		# Straight to market from the building, at the sale price (research uplifts included).
		var ctx := {"good_id": gid, "good_internal": str(Catalog.get_good(gid).get("internal_name", ""))}
		line.value = float(qty) * MarketState.get_sale_price(gid, ctx)
		line.sold = true
		var route := TransportService.route_to_nearest_port(tile, gid)
		if str(route.get("port", "")) != "" and TransportService.route_is_reachable(route):
			var charges := MarketState.sale_charges(str(route.port), route, [{"good_id": gid, "qty": qty}], true, false)
			line.cost = float(charges.transport_cost)
			line.breakdown = charges.transport_breakdown
		else:
			line.unreachable = true
		return line
	# Into a stockpile, this tile's or the one it is routed to, and sold from there: this turn when that
	# tile sells its surplus, otherwise valued as if it did.
	line.value = float(qty) * MarketState.get_price(gid)
	line.sold = str(disposition.get("mode", "")) == "tile_sales"
	var lands := str(disposition.get("sell_tile", tile))
	var breakdown: Dictionary = {}
	var cost := 0.0
	if lands != "" and lands != tile:
		var leg := TransportService.route(tile, lands, gid)
		if TransportService.route_is_reachable(leg):
			cost += TransportService.land_cost_after_credit(gid, qty, leg, false)
			_add(breakdown, TransportService.transport_cost_breakdown_for_route(gid, qty, leg))
	var sale := TransportService.quote_market_sell(lands, {gid: qty})
	if sale.is_empty():
		line.unreachable = true
	else:
		var port := str(sale.get("port", ""))
		var waived := TransportState.seaport_covers(gid) and TransportService.tile_distance(lands, port) <= EconomyConfig.SEAPORT_RANGE_TILES
		cost += Production.stock_sale_charges(port, sale.get("route", {}), gid, qty, waived, false, breakdown)
	line.cost = cost
	line.breakdown = breakdown
	return line


## One input's value and what it costs to bring in. What the company makes itself and routes here is
## valued at what it would sell for (the sale it forgoes) and arrives with no transport cost here; the
## rest is bought on the market, delivered, or through the intermediary where it supplies the good.
static func _input_line(building: Dictionary, inp: Dictionary, qty: int, quote: Dictionary) -> Dictionary:
	var iid := str(building.get("instance_id", ""))
	var tile := str(building.get("tile_id", ""))
	var gid := str(inp.get("good_id", ""))
	if not quote.is_empty() and Middleman.supplies_good(iid, gid):
		var item := _intermediary_item(quote.get("buy", {}), gid)
		return {"good_id": gid, "qty": qty, "value": float(item.get("goods_value", 0.0)),
			"cost": float(item.get("fee", 0.0)), "breakdown": {"intermediary": float(item.get("fee", 0.0))}}
	var own := mini(qty, _own_supply(inp, iid, tile))
	var line := {"good_id": gid, "qty": qty, "value": float(own) * MarketState.get_price(gid), "cost": 0.0, "breakdown": {}}
	var bought := qty - own
	if bought > 0:
		var buy := TransportService.quote_market_buy(tile, gid, bought, TransportState.seaport_would_cover(gid))
		if buy.is_empty():
			line.value = float(line.value) + float(bought) * MarketState.get_buy_price(gid)
		else:
			line.value = float(line.value) + float(buy.get("goods_cost", 0.0))
			line.cost = float(buy.get("transport_cost", 0.0))
			var breakdown: Dictionary = (buy.get("route_transport_breakdown", {}) as Dictionary).duplicate()
			breakdown["port_inbound"] = float(buy.get("sea_transport_cost", 0.0))
			line.breakdown = breakdown
	return line


## What the company's own buildings make of an input and route to this building's tile, this turn.
static func _own_supply(inp: Dictionary, iid: String, tile: String) -> int:
	var gid := str(inp.get("good_id", ""))
	var made := 0
	for producer: Dictionary in Readout._producers_for_input(inp, iid, tile):
		if not BuildingState.is_player_owned(producer):
			continue
		var r: Dictionary = Catalog.get_recipe(str(producer.get("recipe_id", "")))
		for o: Dictionary in Readout.flow(producer, r, true).get("outputs", []):
			if str(o.get("good_id", "")) == gid:
				made += int(o.get("qty", 0))
	return made


static func _intermediary_item(side: Dictionary, gid: String) -> Dictionary:
	for item: Dictionary in side.get("items", []):
		if str(item.get("good", "")) == gid:
			return item
	return {}


## What one good's transport costs by how it goes (Road, Rail, Pipe, Port, the logistics intermediary),
## most first: [{name, cost}].
static func line_methods(line: Dictionary) -> Array:
	return _methods([line])


## The ways a side's goods travel, named once each, in the order they cost most.
static func _methods(lines: Array) -> Array:
	var by_name := {}
	for line: Dictionary in lines:
		for key in (line.get("breakdown", {}) as Dictionary):
			var amount := float(line.breakdown[key])
			if amount <= 0.0:
				continue
			var n := str(METHOD_NAMES.get(str(key), str(key).capitalize()))
			by_name[n] = float(by_name.get(n, 0.0)) + amount
	var names: Array = by_name.keys()
	names.sort_custom(func(a: String, b: String) -> bool: return float(by_name[a]) > float(by_name[b]))
	return names.map(func(n: String) -> Dictionary: return {"name": n, "cost": float(by_name[n])})


static func _sum(lines: Array, key: String) -> float:
	var total := 0.0
	for line: Dictionary in lines:
		total += float(line.get(key, 0.0))
	return total


static func _add(into: Dictionary, part: Dictionary) -> void:
	for key in part:
		into[key] = float(into.get(key, 0.0)) + float(part[key])
