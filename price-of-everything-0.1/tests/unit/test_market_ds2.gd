extends "res://tests/test_base.gd"
## The market's DS2 look (UiPrefs.use_market_ds2, `toggle market ds2`): behaviour, not looks. The switch off
## restores today's panel; the figures on the board are MarketRules'; every tab keeps to the one width; the
## sell panel in DS2 sells what it previews; the slip's chart hover reads the history; Cancel and a lot's Buy work.

const FEATURE := "market"
const TAGS := {
	"_test_market_ds2_sell_panel": ["market", "stockpile"],
	"_test_market_ds2_lot_buy": ["market", "finance"],
}

const MarketRules := preload("res://scripts/market_rules.gd")
const MoneyFigure := preload("res://scripts/ds2/money_figure.gd")
const LedgerV3 := preload("res://scripts/ledger_v3/ledger_v3.gd")
const MarketDs2 := preload("res://scripts/market_ds2/market_ds2.gd")
const COAL := "g_001"
const INLAND := "tile_3_8"


func _panel(ds2: bool) -> Control:
	UiPrefs.set_use_market_ds2(ds2)
	var panel: Control = load("res://scenes/market_panel.tscn").instantiate()
	add_child(panel)
	return panel


func _done(panel: Control) -> void:
	panel.queue_free()
	UiPrefs.set_use_market_ds2(false)


func _cleanup_trades(ships: int) -> void:
	Stockpile.consume(INLAND, COAL, 1 << 30)
	TransportState.pending_transport_shipments.resize(mini(ships, TransportState.pending_transport_shipments.size()))
	MatchState._recompute_unpaid_purchases()
	Production._pending_external_sales.clear()


## The digital display rule: the point in its own cell, five cells at most.
func _test_market_ds2_money_display_rule() -> void:
	var cases := {0.6: "0.60", 20.0: "20.00", 99.994: "99.99", 481.26: "481.3", 1153.0: "1153", 9999.4: "9999", 15600.0: "15.6", 1010000.0: "1.01"}
	for v: float in cases:
		_check(str(MoneyFigure.display(v).figure) == str(cases[v]), "display rule: %s shows %s (got %s)" % [v, cases[v], MoneyFigure.display(v).figure])
	_check(str(MoneyFigure.display(15600.0).suffix) == "K" and str(MoneyFigure.display(1010000.0).suffix) == "M", "display rule: K and M printed after")
	_check(str(MoneyFigure.display(-12.34).figure).length() <= 5, "display rule: a loss keeps to five cells")
	var led: Control = load("res://scripts/bdp_v3_led.gd").new()
	led.set("point_cell", true)
	led.call("set_figure", "0.57", Color.WHITE)
	var own: float = led.custom_minimum_size.x
	led.set("point_cell", false)
	led.call("set_figure", "0.57", Color.WHITE)
	_check(own > led.custom_minimum_size.x, "display rule: the point takes a cell of its own on the market's screens")
	led.free()


## With the switch off the panel is today's; on, the exchange; off again, today's once more.
func _test_market_ds2_switch_restores_today() -> void:
	var panel := _panel(false)
	var v2 := panel.get_node("MarginContainer") as Control
	var v2_box := panel.get_theme_stylebox("panel")
	_check(panel.call("ds2") == null and v2.visible, "switch off: today's panel")
	UiPrefs.set_use_market_ds2(true)
	var ds2: Control = panel.call("ds2")
	_check(ds2 != null and not v2.visible and ds2.is_inside_tree(), "switch on: the exchange over today's panel, which is hidden")
	_check((ds2.call("tab_keys") as Array) == ["prices", "buildings", "special_orders", "recurring", "history"], "switch on: the five tabs")
	_check((panel.call("tab_keys") as Array).size() == 5, "switch on: the panel's tabs are the exchange's")
	UiPrefs.set_use_market_ds2(false)
	_check(panel.call("ds2") == null and v2.visible, "switch off again: today's panel is back")
	_check(panel.find_child("MarketDs2", true, false) == null and panel.find_child("MarketBacking", true, false) == null,
		"switch off again: nothing of the exchange is left")
	_check(panel.get_theme_stylebox("panel").get_class() == v2_box.get_class(), "switch off again: today's frame")
	_check((panel.call("tab_keys") as Array).size() == 6, "switch off again: today's six tabs")
	_done(panel)


## The board's figures are MarketRules'.
func _test_market_ds2_board_figures() -> void:
	var panel := _panel(true)
	panel.show()
	await get_tree().process_frame
	var ds2: Control = panel.call("ds2")
	var prices: Control = ds2.call("tab", "prices")
	_check(prices != null and str(ds2.call("current_tab")) == "prices", "board: opens on Prices")
	var row: Control = prices.call("row_for", COAL)
	_check(row != null, "board: a row for coal")
	if row != null:
		var r := MarketRules.board_row(COAL)
		var sell := row.find_child("Sell", true, false).find_child("Money", true, false) as Control
		var buy := row.find_child("Buy", true, false).find_child("Money", true, false) as Control
		_check(str(sell.get_meta("figure")) == str(MoneyFigure.display(float(r.sell)).figure) + str(MoneyFigure.display(float(r.sell)).suffix),
			"board: Sell is MarketRules.sale_price")
		_check(str(buy.get_meta("figure")) == str(MoneyFigure.display(float(r.buy)).figure) + str(MoneyFigure.display(float(r.buy)).suffix),
			"board: Buy is MarketRules.buy_price, no transport")
		var impact := row.find_child("Impact", true, false) as Control
		_check(impact != null and impact.tooltip_text.contains("PRICE IMPACT") and not (impact.get("tip") as Dictionary).is_empty(),
			"board: the impact carries its ladder card")
		var sold := row.find_child("Sold", true, false) as Label
		_check(sold != null and sold.text == str(int(r.sold)), "board: sold last turn")
	# A made good's cost and profit screens are lit by the tones.
	var saved_costs: Dictionary = CostSolver.last_result.duplicate(true)
	CostSolver.last_result = {"per_good": {COAL: {"unit_cost": MarketRules.sale_price(COAL) * 2.0}}}
	prices.call("refresh")
	row = prices.call("row_for", COAL)
	var cost_led := row.find_child("Cost", true, false).find_child("Led", true, false) as Control
	var profit_led := row.find_child("Profit", true, false).find_child("Led", true, false) as Control
	_check(cost_led.get("colour") == DS.PALETTE["DANGER"] and profit_led.get("colour") == DS.PALETTE["DANGER"], "board: dear cost and a loss read red")
	CostSolver.last_result = {"per_good": {COAL: {"unit_cost": MarketRules.sale_price(COAL) * 0.5}}}
	prices.call("refresh")
	row = prices.call("row_for", COAL)
	cost_led = row.find_child("Cost", true, false).find_child("Led", true, false) as Control
	profit_led = row.find_child("Profit", true, false).find_child("Led", true, false) as Control
	_check(cost_led.get("colour") == DS.PALETTE["OK"] and profit_led.get("colour") == DS.PALETTE["OK"], "board: cheap cost and a profit read green")
	prices.call("set_filter", "produce", true)
	_check((prices.call("shown_rows") as Array).size() == 1, "board: You produce shows the goods you make")
	prices.call("set_filter", "produce", false)
	CostSolver.last_result = saved_costs
	prices.call("sort_by", "sell")
	var shown: Array = prices.call("shown_rows")
	_check(shown.size() > 1 and float(shown[0].sell) >= float(shown[1].sell), "board: Sell sorts, dearest first")
	_done(panel)


## Every tab keeps to the one width: nothing in a tab asks for more than the panel's width allows.
func _test_market_ds2_width_discipline() -> void:
	var panel := _panel(true)
	panel.show()
	await get_tree().process_frame
	var ds2: Control = panel.call("ds2")
	var room: float = MarketDs2.WIDTH - 2.0 * LedgerV3.CONTENT_MARGIN
	for key: String in ds2.call("tab_keys"):
		ds2.call("show_tab", key)
		await get_tree().process_frame
		var want: float = ds2.get_combined_minimum_size().x
		_check(want <= room + 0.5, "width: %s fits the panel (%.1f of %.1f)" % [key, want, room])
	ds2.call("show_tab", "prices")
	ds2.get("_tabs")["prices"].call("toggle_slip", COAL)
	await get_tree().process_frame
	_check(ds2.get_combined_minimum_size().x <= room + 0.5, "width: an open slip fits")
	panel.call("open_sell_panel", COAL)
	await get_tree().process_frame
	var sell: Control = panel.call("sell_panel")
	_check(sell.get_combined_minimum_size().x <= MarketDs2.WIDTH + 0.5, "width: the sell panel fits")
	_done(panel)


## In DS2 the sell panel is skinned and still sells exactly what it previews.
func _test_market_ds2_sell_panel() -> void:
	var ships := TransportState.pending_transport_shipments.size()
	var saved_money := MatchState.money
	var panel := _panel(true)
	Stockpile.consume(INLAND, COAL, 1 << 30)
	Stockpile.add(INLAND, COAL, 25)
	panel.call("open_sell_panel", COAL)
	var sell: Control = panel.call("sell_panel")
	_check(bool(sell.get("ds2")) and sell.find_child("SellBacking", true, false) != null, "sell panel: the DS2 skin")
	sell.call("set_tile_selected", INLAND, true)
	for s: Dictionary in sell.get("sources"):
		if str(s.tile) != INLAND:
			sell.call("set_tile_selected", str(s.tile), false)
	sell.call("set_mode", MarketRules.MODE_ALL_BUT)
	sell.call("set_qty", 5)
	var units := sell.find_child("TotalUnits", true, false) as Label
	var preview: Dictionary = sell.call("quote")
	_check(units != null and units.text == str(int(preview.total.units)) and int(preview.total.units) == 20, "sell panel: the total shows the preview")
	var guard := sell.find_child("ConfirmSale", true, false) as Control
	guard.call("lift")
	guard.emit_signal("pressed")
	_check(Stockpile.get_at_tile(INLAND, COAL) == 5, "sell panel: the guarded key sold what the preview said")
	UiPrefs.set_use_market_ds2(false)
	_check(not bool(sell.get("ds2")) and sell.find_child("SellTable", true, false) != null, "sell panel: back to today's look with the switch")
	_done(panel)
	_cleanup_trades(ships)
	MatchState.money = saved_money


## The slip's chart hover shows that turn's price and the units sold and bought.
func _test_market_ds2_slip_chart_hover() -> void:
	var saved: Dictionary = MarketState.export_state()
	var saved_turn := int(TurnManager.current_turn)
	TurnManager.current_turn = 3
	MarketState.import_state({})
	MarketState.record_market_sale_volume(COAL, 21)
	MarketState.record_market_buy_volume(COAL, 4)
	TurnManager.current_turn = 4
	MarketState.tick_turn()
	MarketState._record_price_history()
	var panel := _panel(true)
	panel.show()
	await get_tree().process_frame
	var prices: Control = panel.call("ds2").call("tab", "prices")
	prices.call("toggle_slip", COAL)
	var slip: Control = prices.call("open_slip")
	_check(slip != null and str(slip.get("good_id")) == COAL, "slip: opens inline under its row")
	slip.call("hover_sample", 0)
	var h := MarketRules.history(COAL)
	_check(str(slip.call("shown_text")).contains("TURN 3") and str(slip.call("shown_text")).contains("SOLD 21")
		and str(slip.call("shown_text")).contains("BOUGHT 4"), "slip: the hover names the turn's sales and purchases (%s)" % str(slip.call("shown_text")))
	_check(str(slip.call("shown_text")).contains(MoneyFigure.display_text(float(h[0].sale))), "slip: and that turn's price")
	var chart: Control = slip.get("chart")
	var i: int = chart.call("sample_at_x", chart.size.x)
	_check(i == h.size() - 1, "slip: the chart's right edge is the latest turn")
	_done(panel)
	TurnManager.current_turn = saved_turn
	MarketState.import_state(saved)


## Recurring lists every standing order with Cancel; Cancel stops it.
func _test_market_ds2_recurring_cancel() -> void:
	MatchState.add_recurring_buy(INLAND, COAL, 3)
	var entry: Dictionary = MatchState.recurring_buys[MatchState.recurring_buys.size() - 1]
	var panel := _panel(true)
	panel.show()
	await get_tree().process_frame
	var ds2: Control = panel.call("ds2")
	ds2.call("show_tab", "recurring")
	var tab: Control = ds2.call("tab", "recurring")
	var cancel: Button = null
	for m in tab.find_children("Standing_*", "", true, false):
		if str(m.get_meta("sub", "")) == "buy":
			cancel = m.find_child("CancelRecurring", true, false) as Button
	_check(cancel != null, "recurring: the buy is listed with Cancel")
	if cancel != null:
		cancel.pressed.emit()
	_check(not MatchState.recurring_buys.has(entry), "recurring: Cancel stops the buy")
	_done(panel)


## A lot's guarded Buy key buys it at the price on its row.
func _test_market_ds2_lot_buy() -> void:
	var saved_money := MatchState.money
	var tile := "ds2_lot_tile"
	var iid: String = BuildingState.add_building("b_007", "", tile, "Test NPC Co", "", false)
	MatchState.money = 100000.0
	var panel := _panel(true)
	panel.show()
	await get_tree().process_frame
	panel.call("open_buildings_for_tile", tile)
	var lots: Control = panel.call("ds2").call("tab", "buildings")
	_check(str(lots.call("sort_key")) == "name" and not bool(lots.call("grouped")), "lots: sorted by the building's name by default")
	var shown: Array = lots.call("shown_lots")
	_check(shown.size() == 1 and str(shown[0].instance_id) == iid, "lots: the tile filter shows the tile's lot")
	var price := int(shown[0].price)
	var guard := lots.find_child("BuyLot", true, false) as Control
	_check(guard != null, "lots: a guarded Buy key")
	var before := MatchState.money
	guard.call("lift")
	guard.emit_signal("pressed")
	_check(BuildingState.is_player_owned(BuildingState.get_building(iid)), "lots: bought")
	_check(absf((before - MatchState.money) - float(price)) < 0.01, "lots: at the price shown")
	panel.hide()
	_check(str(lots.call("tile_filter")) == "", "lots: the tile filter drops when the panel closes")
	_done(panel)
	BuildingState.remove_building(iid)
	BuildingState.tile_land_owned.erase(tile)
	MatchState.money = saved_money


## Lots sort by the building's name by default, with no owner headings; Sort by owner groups them under raised
## owner headings, in owner order; pressing it again goes back to names.
func _test_market_ds2_lots_sort_by_owner() -> void:
	var tile := "ds2_sort_tile"
	var made: Array = []
	for spec: Array in [["b_007", "Zeta Works Co."], ["b_002", "Alpha Holdings Co."], ["b_007", "Alpha Holdings Co."]]:
		made.append(BuildingState.add_building(str(spec[0]), "", tile, str(spec[1]), "", false))
	var panel := _panel(true)
	panel.show()
	await get_tree().process_frame
	panel.call("open_buildings_for_tile", tile)
	var lots: Control = panel.call("ds2").call("tab", "buildings")
	var shown: Array = lots.call("shown_lots")
	var names: Array = shown.map(func(vm: Dictionary) -> String: return str(vm.name).to_lower())
	var sorted_names := names.duplicate()
	sorted_names.sort()
	_check(names == sorted_names, "lots sort: by name by default (%s)" % ", ".join(PackedStringArray(names)))
	_check(lots.find_children("*", "MarginContainer", true, false).filter(func(n: Node) -> bool: return n.has_meta("owner")).is_empty(),
		"lots sort: no owner headings by name")
	var key := lots.find_child("SortByOwner", true, false) as Control
	_check(key != null and not bool(key.get("latched")), "lots sort: a Sort by owner key, up")
	key.emit_signal("pressed")
	await get_tree().process_frame
	_check(bool(lots.call("grouped")) and bool(key.get("latched")), "lots sort: the key groups by owner and stays down")
	# Same-named siblings are renamed: find the headings by their meta.
	var heads := lots.find_children("*", "MarginContainer", true, false).filter(func(n: Node) -> bool: return n.has_meta("owner"))
	var owners: Array = heads.map(func(h: Node) -> String: return str(h.get_meta("owner")))
	_check(owners == ["Alpha Holdings Co.", "Zeta Works Co."], "lots sort: one raised heading an owner, in order (%s)" % str(owners))
	var rows: Node = heads[0].get_parent() if not heads.is_empty() else null
	if rows != null:
		var first_lot: Node = rows.get_child(heads[0].get_index() + 1)
		_check(str(first_lot.name).begins_with("Lot_"), "lots sort: an owner's lots follow its heading")
	key.emit_signal("pressed")
	await get_tree().process_frame
	_check(str(lots.call("sort_key")) == "name" and lots.find_children("*", "MarginContainer", true, false).filter(
		func(n: Node) -> bool: return n.has_meta("owner")).is_empty(),
		"lots sort: pressed again, back to names without headings")
	_done(panel)
	for iid in made:
		BuildingState.remove_building(str(iid))
	BuildingState.tile_land_owned.erase(tile)


## The lamp over the DS2 market (docs/ds2-theme.md §4): every part darkened by it, the sell panel's sheet and tabs
## built later too, the text taking back half, LED segments, dot matrix dots and meter cells not darkened at all,
## glows at full strength; gone with the switch off, every part back to its own material.
func _test_market_ds2_lamp_overlay() -> void:
	var Overlay: GDScript = load("res://scripts/ds2/lamp_overlay.gd")
	var panel := _panel(true)
	panel.show()
	await get_tree().process_frame
	_check(Overlay.find(panel) != null and panel.material == Overlay.shade_material(), "lamp: on, the panel's own plate darkened")
	var labels := panel.find_children("*", "Label", true, false)
	var lit := labels.filter(func(l: Node) -> bool: return (l as Label).material == Overlay.text_material())
	_check(not labels.is_empty() and lit.size() == labels.size(), "lamp: every label takes back half (%d of %d)" % [lit.size(), labels.size()])
	var segs := panel.find_children("Segments", "", true, false)
	_check(not segs.is_empty() and segs.all(func(n: Node) -> bool: return (n as CanvasItem).material == null), "lamp: LED segments are not darkened")
	var dots := panel.find_children("Dots", "", true, false)
	_check(not dots.is_empty() and dots.all(func(n: Node) -> bool: return (n as CanvasItem).material == null), "lamp: dot matrix dots are not darkened")
	var glows := panel.find_children("Glow", "", true, false)
	_check(not glows.is_empty() and glows.all(func(n: Node) -> bool: return (n as CanvasItem).material == Overlay.glow_material()),
		"lamp: glows add at full strength")
	var modules := panel.find_children("MarketRow_*", "", true, false)
	_check(not modules.is_empty() and (modules[0] as CanvasItem).material == Overlay.shade_material(), "lamp: a row's plastic is darkened")
	panel.call("open_sell_panel", COAL)
	await get_tree().process_frame
	var sell: Node = panel.call("sell_panel")
	_check((sell as CanvasItem).material == Overlay.shade_material() and sell.find_children("*", "Label", true, false).all(
		func(l: Node) -> bool: return (l as Label).material == Overlay.text_material()), "lamp: the sell panel's sheet and its text too")
	var ds2: Control = panel.call("ds2")
	ds2.call("show_tab", "history")
	await get_tree().process_frame
	var hist := (ds2.call("tab", "history") as Node).find_children("*", "Label", true, false)
	_check(not hist.is_empty() and hist.all(func(l: Node) -> bool: return (l as Label).material == Overlay.text_material()),
		"lamp: a tab built later is lit too")
	UiPrefs.set_use_market_ds2(false)
	_check(Overlay.find(panel) == null and panel.material == null, "lamp: gone with the switch off")
	var left := panel.find_children("*", "CanvasItem", true, false).filter(func(n: Node) -> bool: return (n as CanvasItem).has_meta(Overlay.ORIGINAL))
	_check(left.is_empty(), "lamp: every part has its own material back")
	var v2_labels := panel.find_children("*", "Label", true, false).filter(func(l: Node) -> bool: return (l as Label).material != null)
	_check(v2_labels.is_empty(), "lamp: today's labels keep no material")
	_done(panel)


## The ledger DS2, its upgrade sheet and the tile view v3 carry the lamp too; the ledger's v2 look does not.
func _test_ds2_panels_lamp_overlay() -> void:
	var Overlay: GDScript = load("res://scripts/ds2/lamp_overlay.gd")
	var was_ledger: bool = UiPrefs.use_ledger_ds2
	UiPrefs.set_use_ledger_ds2(true)
	var ledger: Control = load("res://scenes/building_ledger_panel.tscn").instantiate()
	add_child(ledger)
	await get_tree().process_frame
	_check(Overlay.find(ledger) != null, "lamp: the ledger DS2 has the overlay")
	UiPrefs.set_use_ledger_ds2(false)
	_check(Overlay.find(ledger) == null, "lamp: the ledger v2 has none")
	ledger.queue_free()
	UiPrefs.set_use_ledger_ds2(was_ledger)
	var dialog: Control = load("res://scripts/ledger_v3/upgrade_dialog_ds2.gd").new()
	add_child(dialog)
	await get_tree().process_frame
	var card := dialog.find_child("UpgradeSheet", true, false) as Control
	_check(card != null and Overlay.find(card) != null, "lamp: the DS2 upgrade sheet has the overlay")
	dialog.queue_free()
	var was_tvp: bool = UiPrefs.use_tvp_v3
	UiPrefs.set_use_tvp_v3(true)
	var tvp: Control = load("res://scripts/tile_info_panel_v2.gd").new()
	add_child(tvp)
	await get_tree().process_frame
	_check(Overlay.find(tvp) != null, "lamp: the tile view v3 has the overlay")
	UiPrefs.set_use_tvp_v3(false)
	await get_tree().process_frame
	_check(Overlay.find(tvp) == null, "lamp: the tile view v2 has none")
	tvp.queue_free()
	UiPrefs.set_use_tvp_v3(was_tvp)

