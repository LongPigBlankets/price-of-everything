extends RefCounted
## MarketRules: the questions the market panel asks, answered in one place and without side effects.
## What a good sells and buys for this turn, what one row of the board shows, where the good's price is
## heading and why, its price and trades turn by turn, where the player holds or makes it, and what a sale
## from several tiles would pay.
##
## Each rule is the one the engine applies. MarketState.execute_sale and the sell phase
## (Production._sell_stockpile_totals) pay `sale_price`; MatchState.sell_all_to_market sells what
## `sell_plan` lists; so a panel that reads these shows the figure the turn's cash moves by
## (docs/ds2-theme.md §8, docs/market-ds2-plan.md §6).
##
## Preload by path (no class_name until the editor has scanned the file):
##   const MarketRules := preload("res://scripts/market_rules.gd")
##
## The panel's jobs and the helpers they read:
##   The board      board_row(), sale_price(), buy_price(), cost_tone(), profit_tone()
##   A good's slip  impact_ladder(), history()
##   The sell panel sell_sources(), sell_params(), sell_quote(); the sale itself is
##                  MatchState.sell_all_to_market(sell_params(...)) or, recurring,
##                  MatchState.add_recurring_bulk_sell(sell_params(...))

const Readout := preload("res://scripts/building_readout.gd")

## Profit within this share of the sale price either way reads as break even (amber); above it green,
## below it red. Your cost is green below the sale price, red above it, amber only at the price itself.
const BREAK_EVEN_SHARE := 0.02
## The sell panel's quantity modes: everything on each tile, everything but X on each tile, only X from
## each tile.
const MODE_ALL := "all"
const MODE_ALL_BUT := "all_but"
const MODE_ONLY := "only"


# --- Prices ---------------------------------------------------------------------------------

## The context a good's sale price is resolved in, the one execute_sale passes (a modifier may target a
## good by its id or its internal name).
static func sale_ctx(good_id: String) -> Dictionary:
	return {"good_id": good_id, "good_internal": Catalog.get_internal_name(good_id)}


## What a unit of the good is paid when sold to the market this turn: the price with its market_price
## uplifts (research, advisors, events), clamped to the buy price. Every market sale pays it: the manual
## sale, the recurring and bulk sales (all through MarketState.execute_sale) and the sell phase's stock
## sales. Freight and the port charge are the sale's own costs, quoted by sell_quote.
static func sale_price(good_id: String) -> float:
	return MarketState.get_sale_price(good_id, sale_ctx(good_id))


## What a unit delivered to a special order is paid before the order's premium: the market price with its
## uplifts, not clamped to the buy price (the premium pays for the fulfilment). execute_sale prices an order's
## units with it.
static func order_price(good_id: String) -> float:
	return Modifiers.apply("market_price", good_id, MarketState.get_price(good_id), sale_ctx(good_id))


## What a unit costs to buy at the market, before freight and the port charge: the raw price on the board.
static func buy_price(good_id: String) -> float:
	return MarketState.get_buy_price(good_id)


## A place's name for the player, without coordinates.
static func place_name(tile_id: String) -> String:
	var named := Catalog.tile_name(tile_id)
	return named if named != "" else Catalog.tile_label(tile_id)


## No explicit "finished" tier in the MVP, so a finished good is any good that is neither raw nor power.
static func is_finished_good(good_id: String) -> bool:
	var gt := str(Catalog.get_good(good_id).get("good_type", ""))
	return gt != "" and gt != "raw" and gt != "power"


# --- The board ------------------------------------------------------------------------------

## Everything one row of the board shows, each figure from the engine:
##   buy, sell            buy_price and sale_price (raw, no transport)
##   buy_before_impact,   the same at the impact free price (MarketState.get_base_price_now), for today's
##   sell_before_impact   panel's brackets
##   sold, sold_revenue,  last turn's market sales and purchases (Production.last_turn_summary)
##   bought
##   cost                 what the player makes a unit for (CostSolver.get_good_unit_cost), -1 when not made
##   made                 whether the player makes it
##   profit               sell less cost, NAN when not made
##   cost_tone,           "ok", "warn" or "bad" ("" when not made), by cost_tone and profit_tone
##   profit_tone
##   trend                MarketState.price_trend: {dir, regime, rate, rung, avg, impact}
##   dir, impact          the trend's direction and the accumulated impact in %
static func board_row(good_id: String) -> Dictionary:
	var sell := sale_price(good_id)
	var buy := buy_price(good_id)
	var base_now := MarketState.get_base_price_now(good_id)
	var summary: Dictionary = Production.last_turn_summary
	var sold_entry: Dictionary = (summary.get("sold", {}) as Dictionary).get(good_id, {})
	var cost: float = CostSolver.get_good_unit_cost(good_id)
	var made := cost >= 0.0
	var profit := sell - cost if made else NAN
	var trend: Dictionary = MarketState.price_trend(good_id)
	return {
		"good_id": good_id,
		"name": Catalog.get_display_name(good_id),
		"buy": buy,
		"sell": sell,
		"buy_before_impact": MarketState.buy_price_from(good_id, base_now),
		"sell_before_impact": MarketState.sale_price_from(good_id, base_now, sale_ctx(good_id)),
		"sold": int(sold_entry.get("qty", 0)),
		"sold_revenue": float(sold_entry.get("revenue", 0.0)),
		"bought": int((summary.get("purchased", {}) as Dictionary).get(good_id, 0)),
		"cost": cost,
		"made": made,
		"profit": profit,
		"cost_tone": cost_tone(cost, sell) if made else "",
		"profit_tone": profit_tone(profit, sell) if made else "",
		"trend": trend,
		"dir": int(trend.dir),
		"impact": float(trend.impact),
		"buyable": Catalog.is_good_buyable(good_id),
		"sellable": Catalog.is_good_sellable(good_id),
	}


## Your cost against the sale price: green below it, red above it, amber at it.
static func cost_tone(cost: float, sell: float) -> String:
	if cost < 0.0:
		return ""
	if cost < sell - 0.005:
		return "ok"
	if cost > sell + 0.005:
		return "bad"
	return "warn"


## Profit per unit: green above break even, red below it, amber within BREAK_EVEN_SHARE of the sale price
## (at least a penny) either way.
static func profit_tone(profit: float, sell: float) -> String:
	if is_nan(profit):
		return ""
	var band := maxf(0.01, absf(sell) * BREAK_EVEN_SHARE)
	if profit > band:
		return "ok"
	if profit < -band:
		return "bad"
	return "warn"


# --- A good's slip --------------------------------------------------------------------------

## The good's impact ladder, as the old impact columns showed it: one rung per EconomyConfig ladder step,
## each with the net units a turn that start it (this turn's threshold, inflation applied) and the %/turn
## it moves the price, the rung the window's average sits on marked. `rungs` is empty for a good with no
## producing recipe (it takes no impact). {rungs: [{mult, rate, threshold, active}], rung, avg, impact,
## base_output, scale, recovery_turns}.
static func impact_ladder(good_id: String) -> Dictionary:
	var thresholds: PackedInt32Array = MarketState.impact_thresholds(good_id)
	var trend: Dictionary = MarketState.price_trend(good_id)
	var rungs: Array = []
	if not thresholds.is_empty():
		for i in EconomyConfig.PRICE_IMPACT_LADDER.size():
			rungs.append({
				"mult": float(EconomyConfig.PRICE_IMPACT_LADDER[i][0]),
				"rate": float(EconomyConfig.PRICE_IMPACT_LADDER[i][1]),
				"threshold": thresholds[i],
				"active": i == int(trend.rung),
			})
	return {
		"rungs": rungs,
		"rung": int(trend.rung),
		"avg": float(trend.avg),
		"impact": float(trend.impact),
		"dir": int(trend.dir),
		"regime": str(trend.regime),
		"rate": float(trend.rate),
		"base_output": Catalog.base_output_for_good(good_id),
		"scale": EconomyConfig.impact_threshold_scale(int(TurnManager.current_turn)),
		"recovery_turns": EconomyConfig.PRICE_IMPACT_RECOVERY_TURNS,
	}


## The good's last `turns` recorded turns, oldest first, never a turn after this one: [{turn, price (the
## market price that turn), sale (what a sale was paid), cost_basis (the player's unit cost then, -1 when
## not made), sold, bought (the units the player sold to and bought from the market that turn)}].
static func history(good_id: String, turns: int = 0) -> Array:
	var now := int(TurnManager.current_turn)
	var out: Array = []
	for sample: Dictionary in MarketState.history_for(good_id):
		if int(sample.get("turn", 0)) > now:
			continue
		var price := float(sample.get("price", 0.0))
		out.append({
			"turn": int(sample.get("turn", 0)),
			"price": price,
			"sale": float(sample.get("sale", price)),
			"cost_basis": float(sample.get("cost_basis", -1.0)),
			"sold": int(sample.get("sold", 0)),
			"bought": int(sample.get("bought", 0)),
		})
	if turns > 0 and out.size() > turns:
		out = out.slice(out.size() - turns)
	return out


# --- The sell panel -------------------------------------------------------------------------

## Every tile of the player's that holds the good or makes it: [{tile, name, held (in its stockpile),
## made (this turn's output of the good by the player's running buildings there)}], most held first.
static func sell_sources(good_id: String) -> Array:
	var by_tile: Dictionary = {}
	for key: Variant in Stockpile.tiles_with_stock():
		var tile := str(key)
		if not tile.begins_with("tile_"):
			continue
		var held := Stockpile.get_at_tile(tile, good_id)
		if held > 0:
			by_tile[tile] = {"tile": tile, "name": place_name(tile), "held": held, "made": 0}
	for b: Variant in BuildingState.buildings.values():
		var building: Dictionary = b
		if not BuildingState.is_player_owned(building):
			continue
		var recipe: Dictionary = Catalog.get_recipe(str(building.get("recipe_id", "")))
		if recipe.is_empty() or not Catalog.recipe_produces(recipe, good_id):
			continue
		var tile := str(building.get("tile_id", ""))
		var made := 0
		if not BuildingWorks.is_building_paused(str(building.get("instance_id", ""))):
			for o: Dictionary in Readout.flow(building, recipe, true).get("outputs", []):
				if str(o.get("good_id", "")) == good_id:
					made += int(o.get("qty", 0))
		if not by_tile.has(tile):
			by_tile[tile] = {"tile": tile, "name": place_name(tile), "held": Stockpile.get_at_tile(tile, good_id), "made": 0}
		by_tile[tile].made = int(by_tile[tile].made) + made
	var rows: Array = by_tile.values()
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.held) != int(b.held):
			return int(a.held) > int(b.held)
		if int(a.made) != int(b.made):
			return int(a.made) > int(b.made)
		return str(a.tile) < str(b.tile))
	return rows


## The bulk sale the sell panel makes for one good: the tiles chosen, and in `mode` MODE_ALL everything on
## each, MODE_ALL_BUT everything but `qty` on each, MODE_ONLY no more than `qty` from each. The params
## MatchState.sell_all_to_market sells and add_recurring_bulk_sell repeats.
static func sell_params(good_id: String, tiles: Array, mode: String, qty: int) -> Dictionary:
	var params := {"good_id": good_id, "finished_only": false, "per_tile_keep": 0, "tiles": tiles.duplicate()}
	match mode:
		MODE_ALL_BUT:
			params.per_tile_keep = maxi(0, qty)
		MODE_ONLY:
			params["per_tile_max"] = maxi(0, qty)
	return params


## What a bulk sale sells from each tile, in the order it sells them: [{tile, goods: {good id: qty}}].
## params:
##   good_id        "" for every good, else one good
##   finished_only  only goods that are neither raw nor power
##   per_tile_keep  leave this many of each good on each tile, sell the rest
##   per_tile_max   sell no more than this many of each good from each tile (0 or absent: no cap)
##   tiles          only these tiles (empty or absent: every tile)
## MatchState.sell_all_to_market sells exactly this, a queue_sell per step.
static func sell_plan(params: Dictionary) -> Array:
	var good_filter := str(params.get("good_id", ""))
	var finished_only := bool(params.get("finished_only", false))
	var keep: int = maxi(0, int(params.get("per_tile_keep", 0)))
	var cap: int = maxi(0, int(params.get("per_tile_max", 0)))
	var only: Array = params.get("tiles", [])
	var steps: Array = []
	for tile_key: Variant in Stockpile.tiles_with_stock():
		var tile_id := str(tile_key)
		if not tile_id.begins_with("tile_"):
			continue
		if not only.is_empty() and not only.has(tile_id):
			continue
		var totals: Dictionary = Stockpile.get_tile_totals(tile_id)
		var goods_qtys: Dictionary = {}
		for gid: Variant in totals.keys():
			var g := str(gid)
			if not Catalog.is_good_sellable(g):
				continue
			if good_filter != "" and g != good_filter:
				continue
			if finished_only and not is_finished_good(g):
				continue
			var surplus := int(totals[gid]) - keep
			if cap > 0:
				surplus = mini(surplus, cap)
			if surplus > 0:
				goods_qtys[g] = surplus
		if not goods_qtys.is_empty():
			steps.append({"tile": tile_id, "goods": goods_qtys})
	return steps


## A preview of selling the good from `tiles` in `mode` (sell_params), exactly as the sale will go: the
## plan's steps in order, each priced at sale_price and charged what MarketState.execute_sale charges a
## manual sale (the port charge; the buyer pays the inland freight), with the port's use counted up
## tile by tile as the sale books it. Books nothing.
## {good_id, unit_price, params, tiles: [{tile, name, held, units, revenue, freight, port, charges, net,
## turns, reachable}], by_tile: {tile: line}, total: {units, revenue, freight, port, charges, net, turns}}.
## A tile with no route to a port sells nothing (units 0, reachable false), as the sale refuses it.
## Revenue reaches the cash when the goods reach the port (`turns`), or at once from the transit credit
## line when it is on; the charges are paid when the goods leave.
static func sell_quote(good_id: String, tiles: Array, mode: String, qty: int) -> Dictionary:
	var params := sell_params(good_id, tiles, mode, qty)
	var unit := sale_price(good_id)
	var reservations: Array = []
	var lines: Array = []
	var by_tile: Dictionary = {}
	var total := {"units": 0, "revenue": 0.0, "freight": 0.0, "port": 0.0, "charges": 0.0, "net": 0.0, "turns": 0}
	for step: Dictionary in sell_plan(params):
		var tile := str(step.tile)
		var goods: Dictionary = step.goods
		var units := int(goods.get(good_id, 0))
		var route := TransportService.route_to_nearest_port(tile, TransportService.route_good_for_manifest(goods))
		var port := str(route.get("port", ""))
		var line := {"tile": tile, "name": place_name(tile), "held": Stockpile.get_at_tile(tile, good_id),
			"units": units, "revenue": 0.0, "freight": 0.0, "port": 0.0, "charges": 0.0, "net": 0.0,
			"turns": int(route.get("turns", 0)), "reachable": true, "port_tile": port}
		if port == "" or not TransportService.route_is_reachable(route):
			line.reachable = false
			line.units = 0
		else:
			var charges: Dictionary = MarketState.sale_charges_with(port, route, [{"good_id": good_id, "qty": units}],
				false, false, reservations)
			var breakdown: Dictionary = charges.transport_breakdown
			var port_part := float(breakdown.get("port_fees", 0.0)) + float(breakdown.get("port_insurance", 0.0))
			line.revenue = float(units) * unit
			line.port = port_part
			line.freight = float(charges.transport_cost) - port_part
			line.charges = float(charges.transport_cost)
			line.net = float(line.revenue) - float(line.charges)
			reservations.append({"source_tile": port, "good_id": good_id, "qty": units,
				"is_purchase": true, "construction_order_pending": true})
			total.units = int(total.units) + units
			total.revenue = float(total.revenue) + float(line.revenue)
			total.freight = float(total.freight) + float(line.freight)
			total.port = float(total.port) + float(line.port)
			total.charges = float(total.charges) + float(line.charges)
			total.net = float(total.net) + float(line.net)
			total.turns = maxi(int(total.turns), int(line.turns))
		lines.append(line)
		by_tile[tile] = line
	return {"good_id": good_id, "unit_price": unit, "params": params, "mode": mode, "qty": qty,
		"tiles": lines, "by_tile": by_tile, "total": total}


# --- The head: the key strip and the ticker -------------------------------------------------

## The goods whose price is moving, among `goods` (ids): [{good_id, name, dir}], rising first, then falling,
## each by name. The Prices key's figure and the ticker both read it, so they agree.
static func movers(goods: Array) -> Array:
	var up: Array = []
	var down: Array = []
	for g: Variant in goods:
		var gid := str(g)
		var dir := int(MarketState.price_trend(gid).dir)
		if dir == 0:
			continue
		var row := {"good_id": gid, "name": Catalog.get_display_name(gid), "dir": dir}
		(up if dir > 0 else down).append(row)
	var by_name := func(a: Dictionary, b: Dictionary) -> bool: return str(a.name) < str(b.name)
	up.sort_custom(by_name)
	down.sort_custom(by_name)
	return up + down


## Special orders falling due within `turns` turns (this one included): [{order, good_id, name, due}], soonest
## first.
static func orders_due(turns: int) -> Array:
	var now := int(TurnManager.current_turn)
	var out: Array = []
	for o: Dictionary in SpecialOrderState.get_active_orders():
		var due := int(o.get("expires_turn", 0))
		if due >= now and due - now < turns:
			var gid := str(o.get("good_id", ""))
			out.append({"order": o, "good_id": gid, "name": Catalog.get_display_name(gid), "due": due})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.due) < int(b.due) if int(a.due) != int(b.due) else str(a.name) < str(b.name))
	return out


## The standing orders the Recurring tab lists: recurring sales, bulk sales and buys (with their Cancel),
## and recurring moves.
static func standing_orders() -> Array:
	var rows: Array = MatchState.get_recurring_transaction_rows()
	for m: Dictionary in TransportState.recurring_moves:
		var goods: Dictionary = m.get("goods", {})
		for gid: Variant in goods:
			rows.append({"type": "Move", "sub": "move", "entry": m, "good": Catalog.get_display_name(str(gid)),
				"good_id": str(gid), "qty": int(goods[gid]), "from": place_name(str(m.get("source", ""))),
				"to": place_name(str(m.get("dest", ""))), "turn_started": int(m.get("turn_started", 0))})
	return rows


## Every one off buy, sale and move, newest first: [{type, from, to, good, qty, value, turn_started,
## turn_ended}] (value -1 where none was booked, as for a move).
static func blotter() -> Array:
	var rows: Array = MatchState.get_oneoff_transaction_rows() + TransportState.get_oneoff_move_rows()
	var indexed: Array = []
	for i in rows.size():
		indexed.append([i, rows[i]])
	indexed.sort_custom(func(a: Array, b: Array) -> bool:
		var ta := int((a[1] as Dictionary).get("turn_started", 0))
		var tb := int((b[1] as Dictionary).get("turn_started", 0))
		return ta > tb if ta != tb else int(a[0]) > int(b[0]))
	return indexed.map(func(p: Array) -> Dictionary: return p[1])

