extends "res://tests/test_base.gd"
## MarketRules (scripts/market_rules.gd): the market panel's figures, proved against the engine's own sale
## paths. A figure the board shows must be the figure the turn's cash moves by.

const FEATURE := "market"
const TAGS := {
	"_test_market_rules_sell_quote_parity": ["market", "stockpile"],
	"_test_market_rules_sale_price_is_paid": ["market", "stockpile"],
	"_test_market_rules_sell_sources": ["market", "stockpile"],
}

const MarketRules := preload("res://scripts/market_rules.gd")
const PORT := "tile_5_10"
const INLAND := "tile_3_8"
const OTHER := "tile_9_5"
const COAL := "g_001"


## The sale price is what a sale pays per unit, uplifts included, on both sale paths: the manual sale
## (execute_sale, behind queue_sell and the bulk and recurring sales) and the sell phase's stock sale.
func _test_market_rules_sale_price_is_paid() -> void:
	var saved_money := MatchState.money
	var saved_credit: bool = LoanState.transit_credit_enabled
	LoanState.transit_credit_enabled = false
	var mod := Modifiers.add({"id": "test_market_rules_uplift", "domain": "market_price", "target": "*", "pct": 3.0})
	var raw := MarketState.get_price(COAL)
	var paid := MarketRules.sale_price(COAL)
	_check(paid > raw, "sale price: an uplift lifts the sale price above the market price (%.4f > %.4f)" % [paid, raw])
	_check(paid <= MarketState.get_buy_price(COAL) + 0.000001, "sale price: never above the buy price")
	_check(MarketRules.buy_price(COAL) == MarketState.get_buy_price(COAL), "buy price: the raw market buy price, no transport")

	# Manual sale from the port tile: settles now, so the cash is the revenue less the port charge.
	Stockpile.consume(PORT, COAL, 1 << 30)
	Stockpile.add(PORT, COAL, 40)
	var before := MatchState.money
	var result: Dictionary = MarketState.execute_sale(PORT, {COAL: 40}, {"log_oneoff": false})
	_check(not result.is_empty() and not bool(result.get("deferred", true)), "sale price: a port tile's sale settles now")
	var revenue := float(result.get("total_revenue", 0.0))
	_check(absf(revenue / 40.0 - paid) < 0.000001, "sale price: execute_sale pays sale_price a unit (%.4f vs %.4f)" % [revenue / 40.0, paid])
	var charges := float(result.get("transport_cost", 0.0))
	_check(absf((MatchState.money - before) - (revenue - charges)) < 0.001,
		"sale price: the cash received is the revenue less the charges, accounted separately")

	# The sell phase's stock sale pays the same price (it paid the bare market price before).
	Stockpile.add(PORT, COAL, 25)
	var summary := {"sold": {}, "transport_paid": 0.0, "money_out": 0.0, "money_in": 0.0, "goods_sales_revenue": 0.0,
		"transport_breakdown": {}}
	var record: Dictionary = Production._sell_stockpile_totals(PORT, {COAL: 25}, summary, false)
	var item: Dictionary = (record.get("items", []) as Array)[0] if not (record.get("items", []) as Array).is_empty() else {}
	_check(int(item.get("qty", 0)) == 25, "sale price: the sell phase sold the stock")
	_check(absf(float(item.get("revenue", 0.0)) / 25.0 - paid) < 0.000001,
		"sale price: the sell phase pays sale_price a unit too")
	Modifiers.remove(mod)
	_check(absf(MarketRules.sale_price(COAL) - MarketState.get_price(COAL)) < 0.000001, "sale price: no uplift, the market price")
	Stockpile.consume(PORT, COAL, 1 << 30)
	Production._pending_external_sales.clear()
	MatchState.money = saved_money
	LoanState.transit_credit_enabled = saved_credit


## The board's figures come from the engine: prices, last turn's sales, the cost, profit and their tones,
## and the arrow's trend.
func _test_market_rules_board_row() -> void:
	var saved_summary: Dictionary = Production.last_turn_summary.duplicate(true)
	var saved_costs: Dictionary = CostSolver.last_result.duplicate(true)
	var saved_impact: Dictionary = MarketState.impact_pct.duplicate(true)
	Production.last_turn_summary = {"sold": {COAL: {"qty": 12, "revenue": 30.0}}, "purchased": {COAL: 4}}
	var sell := MarketRules.sale_price(COAL)
	CostSolver.last_result = {"per_good": {COAL: {"unit_cost": sell * 0.5}}}
	var row := MarketRules.board_row(COAL)
	_check(float(row.sell) == sell and float(row.buy) == MarketState.get_buy_price(COAL), "board row: raw buy and sale prices")
	_check(int(row.sold) == 12 and int(row.bought) == 4, "board row: last turn's sales and purchases")
	_check(bool(row.made) and absf(float(row.profit) - sell * 0.5) < 0.000001, "board row: profit is the sale price less your cost")
	_check(str(row.cost_tone) == "ok" and str(row.profit_tone) == "ok", "board row: a cheap good is green twice")
	CostSolver.last_result = {"per_good": {COAL: {"unit_cost": sell * 1.5}}}
	row = MarketRules.board_row(COAL)
	_check(str(row.cost_tone) == "bad" and str(row.profit_tone) == "bad", "board row: a dear good is red twice")
	CostSolver.last_result = {"per_good": {COAL: {"unit_cost": sell * (1.0 - MarketRules.BREAK_EVEN_SHARE * 0.5)}}}
	row = MarketRules.board_row(COAL)
	_check(str(row.cost_tone) == "ok" and str(row.profit_tone) == "warn", "board row: break even is amber profit, cost still below")
	CostSolver.last_result = {"per_good": {}}
	row = MarketRules.board_row(COAL)
	_check(not bool(row.made) and is_nan(float(row.profit)) and str(row.cost_tone) == "", "board row: a good you don't make has no cost or profit")
	MarketState.impact_pct[COAL] = -12.0
	row = MarketRules.board_row(COAL)
	_check(int(row.dir) == 1 and float(row.impact) == -12.0, "board row: a glutted price with a quiet window is recovering")
	_check(float(row.sell_before_impact) > float(row.sell), "board row: the impact free sale price is above a glutted one")
	var ladder := MarketRules.impact_ladder(COAL)
	_check((ladder.rungs as Array).size() == EconomyConfig.PRICE_IMPACT_LADDER.size(), "impact ladder: one rung a ladder step")
	_check(int((ladder.rungs as Array)[0].threshold) == MarketState.impact_thresholds(COAL)[0], "impact ladder: the engine's thresholds")
	Production.last_turn_summary = saved_summary
	CostSolver.last_result = saved_costs
	MarketState.impact_pct = saved_impact


## The price history records what the player sold and bought each turn, at the turn it was traded.
func _test_market_rules_history_volumes() -> void:
	var saved: Dictionary = MarketState.export_state()
	var saved_turn := int(TurnManager.current_turn)
	TurnManager.current_turn = 7
	MarketState.import_state({})
	MarketState.record_market_sale_volume(COAL, 30)
	MarketState.record_market_buy_volume(COAL, 5)
	TurnManager.current_turn = 8
	MarketState.tick_turn()
	MarketState._record_price_history()
	var h := MarketRules.history(COAL)
	_check(h.size() == 2 and int(h[0].turn) == 7 and int(h[0].sold) == 30 and int(h[0].bought) == 5,
		"history: turn 7's sales and purchases sit on turn 7")
	_check(int(h[1].sold) == 0 and int(h[1].bought) == 0, "history: a quiet turn reads zero")
	MarketState._record_price_history()
	_check(int(MarketRules.history(COAL)[0].sold) == 30, "history: re-recording a turn keeps its trades")
	var round_trip: Dictionary = MarketState.export_state()
	MarketState.import_state(round_trip)
	_check(int(MarketRules.history(COAL)[0].sold) == 30, "history: trades survive a save round trip")
	_check(MarketRules.history(COAL, 1).size() == 1 and int(MarketRules.history(COAL, 1)[0].turn) == 8, "history: the last N turns")
	TurnManager.current_turn = saved_turn
	MarketState.import_state(saved)


## Every tile that holds or makes the good, with what it holds and makes.
func _test_market_rules_sell_sources() -> void:
	Stockpile.consume(INLAND, COAL, 1 << 30)
	Stockpile.consume(OTHER, COAL, 1 << 30)
	Stockpile.add(INLAND, COAL, 9)
	Stockpile.add(OTHER, COAL, 31)
	var rows := MarketRules.sell_sources(COAL)
	var tiles: Array = rows.map(func(r: Dictionary) -> String: return str(r.tile))
	_check(tiles.has(INLAND) and tiles.has(OTHER), "sell sources: both holding tiles listed")
	_check(tiles.find(OTHER) < tiles.find(INLAND), "sell sources: most held first")
	_check(int((rows[tiles.find(OTHER)] as Dictionary).held) == 31, "sell sources: what each tile holds")
	var named: Dictionary = rows[tiles.find(INLAND)]
	_check(str(named.name) == Catalog.tile_name(INLAND) and not str(named.name).contains("("), "sell sources: a named place shows its name, no coordinates")
	Stockpile.consume(INLAND, COAL, 1 << 30)
	Stockpile.consume(OTHER, COAL, 1 << 30)


## The sell panel's preview is what the sale then pays: units, revenue and charges, per mode, across tiles
## that share a port (the port charge counted up tile by tile as the sale books it).
func _test_market_rules_sell_quote_parity() -> void:
	var saved_money := MatchState.money
	var saved_ships := TransportState.pending_transport_shipments.size()
	var saved_credit: bool = LoanState.transit_credit_enabled
	LoanState.transit_credit_enabled = false
	for mode_qty: Array in [[MarketRules.MODE_ALL, 0], [MarketRules.MODE_ALL_BUT, 7], [MarketRules.MODE_ONLY, 11]]:
		var mode := str(mode_qty[0])
		var qty := int(mode_qty[1])
		for t in [PORT, INLAND, OTHER]:
			Stockpile.consume(t, COAL, 1 << 30)
		Stockpile.add(PORT, COAL, 20)
		Stockpile.add(INLAND, COAL, 16)
		Stockpile.add(OTHER, COAL, 5)
		var tiles := [PORT, INLAND, OTHER]
		var quote := MarketRules.sell_quote(COAL, tiles, mode, qty)
		var ships_before := TransportState.get_pending_transport_shipments().size()
		var money_before := MatchState.money
		var result: Dictionary = MatchState.sell_all_to_market(quote.params)
		var deferred_revenue := 0.0
		var shipments: Array = TransportState.get_pending_transport_shipments()
		for i in range(ships_before, shipments.size()):
			deferred_revenue += float(((shipments[i] as Dictionary).get("sale_record", {}) as Dictionary).get("total_revenue", 0.0))
		var revenue := float(result.get("revenue", 0.0))
		var charges_paid := (revenue - deferred_revenue) - (MatchState.money - money_before)
		_check(int(result.get("total_qty", 0)) == int(quote.total.units),
			"sell quote (%s): units match the sale (%d vs %d)" % [mode, int(result.get("total_qty", 0)), int(quote.total.units)])
		_check(absf(revenue - float(quote.total.revenue)) < 0.001,
			"sell quote (%s): revenue matches the sale (%.4f vs %.4f)" % [mode, revenue, float(quote.total.revenue)])
		_check(absf(charges_paid - float(quote.total.charges)) < 0.001,
			"sell quote (%s): charges match what the sale paid (%.4f vs %.4f)" % [mode, charges_paid, float(quote.total.charges)])
		var want := {MarketRules.MODE_ALL: [20, 16, 5], MarketRules.MODE_ALL_BUT: [13, 9, 0], MarketRules.MODE_ONLY: [11, 11, 5]}[mode] as Array
		var left := [20 - int(want[0]), 16 - int(want[1]), 5 - int(want[2])]
		_check(Stockpile.get_at_tile(PORT, COAL) == int(left[0]) and Stockpile.get_at_tile(INLAND, COAL) == int(left[1])
			and Stockpile.get_at_tile(OTHER, COAL) == int(left[2]), "sell quote (%s): each tile sold what the mode says" % mode)
	# Only the chosen tiles sell.
	for t in [PORT, INLAND, OTHER]:
		Stockpile.consume(t, COAL, 1 << 30)
	Stockpile.add(INLAND, COAL, 8)
	Stockpile.add(OTHER, COAL, 8)
	var only_inland := MarketRules.sell_quote(COAL, [INLAND], MarketRules.MODE_ALL, 0)
	_check(int(only_inland.total.units) == 8 and (only_inland.tiles as Array).size() == 1, "sell quote: only the chosen tiles")
	MatchState.sell_all_to_market(only_inland.params)
	_check(Stockpile.get_at_tile(OTHER, COAL) == 8 and Stockpile.get_at_tile(INLAND, COAL) == 0, "sell: an unchosen tile keeps its stock")
	for t in [PORT, INLAND, OTHER]:
		Stockpile.consume(t, COAL, 1 << 30)
	_drop_shipments(saved_ships)
	MatchState.money = saved_money
	LoanState.transit_credit_enabled = saved_credit


## Takes back the shipments a test queued and the immediate sales waiting to be booked into the next turn,
## so a later test's turn neither lands nor books them.
func _drop_shipments(keep: int) -> void:
	TransportState.pending_transport_shipments.resize(mini(keep, TransportState.pending_transport_shipments.size()))
	MatchState._recompute_unpaid_purchases()
	Production._pending_external_sales.clear()


## Transactions carry their money value; recurring buys can be cancelled.
func _test_market_rules_ledger_value_and_cancel() -> void:
	var saved_money := MatchState.money
	var saved_ships := TransportState.pending_transport_shipments.size()
	MatchState.money = 100000.0
	var buy: Dictionary = MatchState.queue_buy(INLAND, COAL, 6)
	var rows: Array = MatchState.get_oneoff_transaction_rows()
	var last: Dictionary = rows[rows.size() - 1]
	_check(absf(float(last.get("value", -1.0)) - float(buy.get("goods_cost", 0.0))) < 0.001, "ledger: a buy carries its goods' value")
	Stockpile.add(INLAND, COAL, 10)
	var sale: Dictionary = MatchState.queue_sell(INLAND, {COAL: 10})
	rows = MatchState.get_oneoff_transaction_rows()
	last = rows[rows.size() - 1]
	_check(absf(float(last.get("value", -1.0)) - float(sale.get("revenue", 0.0))) < 0.001, "ledger: a sale carries its revenue")
	MatchState.add_recurring_buy(INLAND, COAL, 3)
	var entry: Dictionary = MatchState.recurring_buys[MatchState.recurring_buys.size() - 1]
	var found := false
	for r: Dictionary in MatchState.get_recurring_transaction_rows():
		if str(r.get("sub", "")) == "buy" and r.get("entry") == entry:
			found = true
	_check(found, "ledger: a recurring buy's row carries its order")
	_check(MatchState.remove_recurring_order("buy", entry) and not MatchState.recurring_buys.has(entry), "recurring buy: Cancel removes it")
	_check(not MatchState.remove_recurring_order("buy", entry), "recurring buy: cancelling twice does nothing")
	_drop_shipments(saved_ships)
	MatchState.money = saved_money
