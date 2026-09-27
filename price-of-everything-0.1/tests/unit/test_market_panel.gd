extends "res://tests/test_base.gd"
## The market panel's behaviour: the Sell key opens the sell panel, the sell panel sells what its preview
## says (one off) or sets up the recurring sale, recurring orders cancel, transactions carry their value.

const FEATURE := "market"
const TAGS := {
	"_test_market_sell_panel_sells_its_preview": ["market", "stockpile"],
	"_test_market_sell_panel_recurring": ["market", "stockpile"],
}

const MarketRules := preload("res://scripts/market_rules.gd")
const INLAND := "tile_3_8"
const OTHER := "tile_9_5"
const COAL := "g_001"


func _panel() -> Control:
	var panel: Control = load("res://scenes/market_panel.tscn").instantiate()
	add_child(panel)
	panel.call("_ensure_built")
	return panel


func _stock(a: int, b: int) -> void:
	for t in [INLAND, OTHER]:
		Stockpile.consume(t, COAL, 1 << 30)
	Stockpile.add(INLAND, COAL, a)
	Stockpile.add(OTHER, COAL, b)


func _cleanup(ships: int) -> void:
	for t in [INLAND, OTHER]:
		Stockpile.consume(t, COAL, 1 << 30)
	TransportState.pending_transport_shipments.resize(mini(ships, TransportState.pending_transport_shipments.size()))
	MatchState._recompute_unpaid_purchases()
	Production._pending_external_sales.clear()


## A row's Sell key opens the sell panel for its good, every source ticked.
func _test_market_sell_key_opens_sell_panel() -> void:
	_stock(12, 4)
	var panel := _panel()
	var tabs: TabContainer = panel.get("_tabs")
	tabs.current_tab = 0
	panel.call("_ensure_current_tab_built")
	var row: Node = null
	for r in panel.get("rows"):
		if str(r.get("good_id")) == COAL:
			row = r
	_check(row != null, "sell key: the coal row exists")
	if row != null:
		var key := row.find_child("SellKey", true, false) as Button
		_check(key != null and not key.disabled, "sell key: the row has a live Sell key")
		key.pressed.emit()
		var sell: Control = panel.call("sell_panel")
		_check(sell != null and sell.visible and str(sell.get("good_id")) == COAL, "sell key: opens the sell panel on the good")
		var tiles: Array = sell.call("selected_tiles")
		_check(tiles.has(INLAND) and tiles.has(OTHER), "sell panel: every source is ticked at first")
		_check(not bool(sell.get("recurring")) and str(sell.get("mode")) == MarketRules.MODE_ALL, "sell panel: one off, all, by default")
	panel.queue_free()
	_cleanup(TransportState.pending_transport_shipments.size())


## One off: the sale sells exactly what the preview said, from the ticked tiles, in each mode.
func _test_market_sell_panel_sells_its_preview() -> void:
	var saved_money := MatchState.money
	var ships := TransportState.pending_transport_shipments.size()
	var panel := _panel()
	panel.call("open_sell_panel", COAL)
	var sell: Control = panel.call("sell_panel")
	for spec: Array in [[MarketRules.MODE_ALL, 0], [MarketRules.MODE_ALL_BUT, 5], [MarketRules.MODE_ONLY, 3]]:
		_stock(12, 9)
		sell.call("open", COAL)
		sell.call("set_mode", str(spec[0]))
		sell.call("set_qty", int(spec[1]))
		sell.call("set_tile_selected", OTHER, false)
		var preview: Dictionary = sell.call("quote")
		var result: Dictionary = sell.call("confirm")
		_check(int(result.get("total_qty", -1)) == int(preview.total.units) and int(preview.total.units) > 0,
			"sell panel (%s): sold the units the preview said (%d)" % [str(spec[0]), int(preview.total.units)])
		_check(absf(float(result.get("revenue", 0.0)) - float(preview.total.revenue)) < 0.001,
			"sell panel (%s): the revenue the preview said" % str(spec[0]))
		_check(Stockpile.get_at_tile(OTHER, COAL) == 9, "sell panel (%s): an unticked tile keeps its stock" % str(spec[0]))
	_stock(0, 0)
	sell.call("open", COAL)
	_check(not bool(sell.call("can_confirm")) and (sell.call("confirm") as Dictionary).is_empty(), "sell panel: nothing held, nothing to confirm")
	panel.queue_free()
	_cleanup(ships)
	MatchState.money = saved_money


## Recurring: the panel sets up the sale for the ticked tiles and sells nothing now; the order sells each
## turn and can be cancelled.
func _test_market_sell_panel_recurring() -> void:
	var ships := TransportState.pending_transport_shipments.size()
	var panel := _panel()
	_stock(20, 20)
	panel.call("open_sell_panel", COAL)
	var sell: Control = panel.call("sell_panel")
	sell.call("set_tile_selected", OTHER, false)
	sell.call("set_mode", MarketRules.MODE_ONLY)
	sell.call("set_qty", 6)
	sell.call("set_recurring", true)
	var before := MatchState.recurring_bulk_sells.size()
	var result: Dictionary = sell.call("confirm")
	_check(bool(result.get("recurring", false)) and MatchState.recurring_bulk_sells.size() == before + 1, "recurring: one order set up")
	_check(Stockpile.get_at_tile(INLAND, COAL) == 20, "recurring: nothing sold at once")
	var entry: Dictionary = MatchState.recurring_bulk_sells[MatchState.recurring_bulk_sells.size() - 1]
	MatchState.run_recurring_and_scheduled_moves()
	_check(Stockpile.get_at_tile(INLAND, COAL) == 14 and Stockpile.get_at_tile(OTHER, COAL) == 20,
		"recurring: each turn sells only X from the ticked tile")
	var found := false
	for r: Dictionary in MatchState.get_recurring_transaction_rows():
		if str(r.get("sub", "")) == "bulk" and r.get("entry") == entry:
			found = true
	_check(found, "recurring: the order is listed with its Cancel")
	panel.call("_cancel_recurring", "bulk", entry)
	_check(not MatchState.recurring_bulk_sells.has(entry), "recurring: Cancel stops it")
	panel.queue_free()
	_cleanup(ships)


## The Transactions tab shows each transaction's value and a Cancel on each recurring order, recurring
## buys included; the Sales tab has no bulk sell form any more.
func _test_market_transactions_value_and_cancel() -> void:
	var ships := TransportState.pending_transport_shipments.size()
	var saved_money := MatchState.money
	MatchState.money = 100000.0
	MatchState.queue_buy(INLAND, COAL, 4)
	MatchState.add_recurring_buy(INLAND, COAL, 2)
	var entry: Dictionary = MatchState.recurring_buys[MatchState.recurring_buys.size() - 1]
	var panel := _panel()
	panel.show()
	panel.call("_ensure_tab_built", "transactions")
	panel.call("_refresh_ledgers")
	var root: Control = (panel.get("_tab_roots") as Dictionary)["transactions"]
	var heads: Array = []
	var grids := root.find_children("LedgerGrid", "GridContainer", true, false)
	for g in grids:
		for i in (g as GridContainer).columns:
			heads.append(str(((g as GridContainer).get_child(i) as Label).text))
	_check(heads.has("Value"), "transactions: a Value column")
	var cancels := root.find_children("CancelRecurring", "Button", true, false)
	_check(cancels.size() >= 1, "transactions: recurring orders have Cancel")
	var cancel_for_buy: Button = null
	for c in cancels:
		cancel_for_buy = c
	cancel_for_buy.pressed.emit()
	_check(not MatchState.recurring_buys.has(entry), "transactions: Cancel stops the recurring buy")
	panel.call("_ensure_tab_built", "sales")
	var sales: Control = (panel.get("_tab_roots") as Dictionary)["sales"]
	_check(sales.find_children("*", "SpinBox", true, false).is_empty() and sales.find_children("*", "OptionButton", true, false).size() == 1,
		"sales tab: no bulk sell form (only the recurring list's good filter)")
	panel.queue_free()
	_cleanup(ships)
	MatchState.money = saved_money
