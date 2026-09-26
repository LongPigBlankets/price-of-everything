extends Node2D
## Captures of the tile view v3's Stock tab in the cases tools/tvp_v3_shot.gd lacks: the Move or sell sheet
## (sliding in, settled, a destination chosen, a special order), the warehouse's expansion sheet, a bay
## with more goods than it shows (closed and opened), a full warehouse with goods turned away and
## shipments waiting, the routing knobs of an intermediary game, land you own with nothing stored, a tile
## about to fill, a peak near the bar's end, and a tile that isn't yours. Beside the captures it checks the
## tab's contract and its rules: the forecast line against the transport panel's own rule, last turn's peak
## and the stored figure against the stockpile summary's thresholds, one line when full with the backlog
## straight under it, one text column, no tag line fanning out across the bar, the bar's tags picking and
## lighting goods as the bay does, the licence's name, and that neither the body nor a sheet asks for more
## width than the scroll shows.
## Same setup as tools/tvp_v3_shot.gd: the real HUD at 1920 x 1080, two pixels each, a busy tile you own.
##   Godot --path . res://tools/tvp_v3_stock_shot.tscn --quit-after 40000 -- --no-telemetry
## Writes tvp_v3_stock_<case>.png into $TVP_SHOT_DIR (or /tmp).

const TileViewData := preload("res://scripts/tile_view_data.gd")
const LOGICAL := Vector2i(1920, 1080)
const TILE := "tile_5_10"
const EMPTY_TILE := "tile_6_1"

var _vp: SubViewport
var _wm
var _out := "/tmp"
var _panel: Control


func _ready() -> void:
	var dir := OS.get_environment("TVP_SHOT_DIR")
	if dir != "":
		_out = dir
	_vp = SubViewport.new()
	_vp.size = LOGICAL * 2
	_vp.size_2d_override = LOGICAL
	_vp.size_2d_override_stretch = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.gui_embed_subwindows = true
	add_child(_vp)
	_wm = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	_vp.add_child(_wm)
	await _settle(140)
	var cam := _vp.get_camera_2d()
	if cam != null:
		cam.edge_pan_enabled = false

	MatchState.money = 8000.0
	BuildingState.add_building("b_007", "r_009", TILE, MatchState.LOCAL_PLAYER, "tvpshotm1")
	BuildingState.add_building("b_007", "r_003", TILE, MatchState.LOCAL_PLAYER, "tvpshots1")
	BuildingState.add_building("b_025", "r_037", TILE, MatchState.LOCAL_PLAYER, "tvpshotw1")
	Stockpile.add(TILE, _gid("steel"), 40)
	Stockpile.add(TILE, _gid("copper_wiring"), 40)
	TurnManager.fast_mode = true
	DecisionState.auto_resolve = true
	for _i in 3:
		TurnManager.commit_turn()
		if TurnManager.is_resolving:
			await TurnManager.turn_resolution_completed
	var dock: Node = _wm.find_child("EndTurnDock", true, false)
	if dock != null and dock.get("_expanded") == true:
		dock.call("_collapse")
	var toasts: Node = _wm.get_node_or_null("UILayer/HUD/ToastLayer")
	if toasts != null:
		toasts.call("clear")
	await _settle(30)

	_panel = _wm.find_child("TileInfoPanel", true, false)
	UiPrefs.set_use_tvp_v3(true)
	await _settle(6)
	var td := _tile_data(TILE)
	var only := OS.get_environment("TVP_STOCK_CASES")
	var cases := only.split(",") if only != "" else PackedStringArray(["checks", "rules", "hover", "sheet", "sheet_tile", "expand", "few", "maxed", "many", "full", "logistics", "owned_empty", "idle", "idle_port"])

	if "checks" in cases:
		await _checks(td)

	if "rules" in cases:
		await _rules(td)

	if "hover" in cases:
		# Pointing at a good in the bay lights its slice in the warehouse's bar.
		_panel.call("show_tile", td, "stock")
		await _settle(10)
		var cell: Control = _panel.find_child("StoredGood_" + _gid("copper_wiring"), true, false)
		if cell != null:
			cell.mouse_entered.emit()
		await _settle(4)
		await _save("hover")
		if cell != null:
			cell.mouse_exited.emit()
		# And pointing at the knob's port icon names that route in the surplus line.
		var port_icon: Control = _panel.find_child("SellSurplusToggle", true, false)
		if port_icon != null:
			port_icon.mouse_entered.emit()
		await _settle(4)
		await _save("hover_knob")
		if port_icon != null:
			port_icon.mouse_exited.emit()

	if "sheet" in cases:
		_panel.call("show_tile", td, "stock")
		await _settle(12)
		_panel.call("select_stock_good", _gid("steel"))
		await _settle(3)
		await _save("sheet_sliding")
		await _settle(30)
		await _save("sheet")
		_panel.set("_stock_dest", "__market__")
		_panel.set("_stock_recurring", true)
		_panel.call("_refresh_pane", "stock")
		await _settle(8)
		await _save("sheet_market")
		SpecialOrderState.create_order("steel", -1, 4, 30)
		_panel.set("_stock_dest", "__special_order__")
		_panel.call("_refresh_pane", "stock")
		await _settle(8)
		await _save("sheet_special")
		_bottom()
		await _settle(4)
		await _save("sheet_bottom")
		_panel.set("_stock_sel", {})
		_panel.set("_stock_dest", "")
		_panel.set("_stock_recurring", false)

	if "sheet_tile" in cases:
		# Moving to another tile: the freight on a screen over the key, the tile by name.
		_panel.call("show_tile", td, "stock")
		await _settle(8)
		_panel.call("select_stock_good", _gid("steel"))
		await _settle(4)
		_panel.set("_stock_dest", "tile_6_10")
		_panel.set("_stock_qty", 40)
		_panel.call("_refresh_pane", "stock")
		await _settle(30)
		await _save("sheet_tile")
		_panel.set("_stock_sel", {})
		_panel.set("_stock_dest", "")

	if "expand" in cases:
		_panel.call("show_tile", td, "stock")
		await _settle(8)
		_panel.set("_warehouse_expand", true)
		_panel.call("_refresh_pane", "stock")
		await _settle(30)
		await _save("expand")
		_panel.set("_warehouse_expand", false)

	if "few" in cases:
		# Land of yours with three goods: the bay is one row, the door up.
		BuildingState.tile_land_owned[EMPTY_TILE] = 20
		Stockpile.add(EMPTY_TILE, _gid("steel"), 30)
		Stockpile.add(EMPTY_TILE, _gid("coal"), 12)
		Stockpile.add(EMPTY_TILE, _gid("copper_wiring"), 7)
		_panel.call("show_tile", _tile_data(EMPTY_TILE), "stock")
		await _settle(12)
		await _save("few")
		_bottom()
		await _settle(4)
		await _save("few_bottom")
		for g in ["steel", "coal", "copper_wiring"]:
			Stockpile.consume(EMPTY_TILE, _gid(g), 999)
		BuildingState.tile_land_owned.erase(EMPTY_TILE)
		# The goods came and went within this turn: forget the high-water mark they left, as a new turn would.
		Stockpile._peak_used.erase(str(Stockpile.call("_tile_key", EMPTY_TILE)))

	if "maxed" in cases:
		# A warehouse at its last level: the capacity line says so instead of Expand.
		var was := Stockpile.get_warehouse_level(TILE)
		Stockpile.set_warehouse_level(TILE, EconomyConfig.WAREHOUSE_STORAGE_CAP.size())
		_panel.call("show_tile", td, "stock")
		await _settle(12)
		_top()
		await _settle(4)
		await _save("maxed")
		Stockpile.set_warehouse_level(TILE, was)

	if "many" in cases:
		for i in range(1, 14):
			Stockpile.add(TILE, "g_%03d" % i, 12 + i * 3)
		_panel.call("show_tile", td, "stock")
		await _settle(8)
		_scroll_to("GoodsBay")
		await _settle(4)
		await _save("many")
		var many_tags: Array = _panel.find_child("StockGauge", true, false).call("tags")
		var more := many_tags.filter(func(t: Dictionary) -> bool: return str(t.kind) == "more")
		var goods_n := Stockpile.get_tile_totals(TILE).size()
		var shown := many_tags.filter(func(t: Dictionary) -> bool: return str(t.kind) == "good").size()
		_check(more.size() == 1 and shown + (more[0].goods as Array).size() == goods_n,
			"many goods: %d tagged, one +N tag for the other %d" % [shown, goods_n - shown])
		_panel.set_meta("tvp_stock_all_goods", TILE)
		_panel.call("_refresh_pane", "stock")
		await _settle(8)
		_scroll_to("GoodsBay")
		await _settle(4)
		await _save("many_open")
		_panel.set_meta("tvp_stock_all_goods", "")

	if "full" in cases:
		Stockpile.add(TILE, _gid("steel"), 5000)
		Stockpile.add(TILE, _gid("coal"), 120)
		TransportState.hold_overflow_shipment({"source_tile": "tile_6_10", "destination_tile": TILE,
			"good_id": _gid("coal"), "qty": 60, "turns_waiting": 2})
		_panel.call("show_tile", td, "stock")
		await _settle(12)
		_top()
		await _settle(4)
		await _save("full")
		var readings: Node = _panel.find_child("WarehouseReadings", true, false)
		var reds := 0
		for l: Node in readings.find_children("*", "Label", true, false):
			if (l as Label).get_theme_color("font_color") == DS.PALETTE.DANGER:
				reds += 1
		var way := _panel.find_child("LineWayOut", true, false) as Label
		_check(_panel.find_child("FullRow", true, false) != null and _panel.find_child("PeakRow", true, false) == null
			and _panel.find_child("TrendRow", true, false) == null and reds == 1 and way != null and way.text != "",
			"full: one red line (%d), the way out under it (%s)" % [reds, way.text if way != null else "none"])
		_text_column("full")
		_tag_lines("full")
		_led_tone("full", TileViewData.stockpile_summary(TILE))
		# The backlog sits in the readings, straight under the full line, a line's gap apart, each
		# shipment's wait in its own sentence.
		var full_row: Control = _panel.find_child("FullRow", true, false)
		var head: Control = _panel.find_child("OverflowHead", true, false)
		var StockTab := load("res://scripts/tvp_v3/stock_tab.gd")
		var under := full_row != null and head != null and head.get_parent() == readings \
			and head.get_index() == full_row.get_index() + 1
		var gap := head.global_position.y - full_row.get_global_rect().end.y if under else -1.0
		var words: Node = _panel.find_child("ShipmentWords", true, false)
		_check(under and absf(gap - float(StockTab.LINE_GAP)) <= 0.5 and words != null and "waiting" in str(words.get("text")),
			"the backlog sits straight under the full line (%.1f px apart), the wait in its sentence" % gap)
		var clean := true
		for row: Node in _panel.find_children("OverflowShipment", "", true, false):
			for l: Node in row.find_children("*", "RichTextLabel", true, false):
				if "(" in (l as RichTextLabel).get_parsed_text():
					clean = false
		_check(clean and _panel.find_child("OverflowShipment", true, false) != null,
			"shipments waiting to unload name their tile without coordinates")
		_bottom()
		await _settle(4)
		await _save("full_bottom")

	if "logistics" in cases:
		var model_was = MatchState.ruleset.get("logistics_model", null)
		MatchState.ruleset["logistics_model"] = "middleman_v1"
		ResearchState.grant_unlock(ResearchState.OPEN_LOGISTICS_CONTRACTS_TITLE)
		_panel.call("show_tile", td, "stock")
		await _settle(12)
		_bottom()
		await _settle(4)
		await _save("logistics")
		var market: Control = _panel.find_child("Input_Market", true, false)
		var port: Control = _panel.find_child("SellSurplusToggle", true, false)
		var named := market != null and ResearchState.GLOBAL_TRADE_LICENSE_TITLE in market.tooltip_text
		if port != null and not ResearchState.global_trade_license_available():
			port.mouse_entered.emit()
			var words := _panel.find_child("SurplusWords", true, false) as Label
			named = named and words != null and ResearchState.GLOBAL_TRADE_LICENSE_TITLE in words.text
			port.mouse_exited.emit()
		_check(named, "the licence is named as the research is (%s)" % (market.tooltip_text if market != null else "no market option"))
		# Back to the game's own model, so the cases after this one aren't intermediary games.
		if model_was == null:
			MatchState.ruleset.erase("logistics_model")
		else:
			MatchState.ruleset["logistics_model"] = model_was

	if "owned_empty" in cases:
		BuildingState.tile_land_owned[EMPTY_TILE] = 20
		_panel.call("show_tile", _tile_data(EMPTY_TILE), "stock")
		await _settle(12)
		await _save("owned_empty")
		BuildingState.tile_land_owned.erase(EMPTY_TILE)

	if "idle" in cases:
		# A tile that isn't yours: the heading says what it holds, the door is one bay row high.
		_panel.call("show_tile", _tile_data(EMPTY_TILE), "stock")
		await _settle(12)
		await _save("idle")
		var door: Control = _panel.find_child("IdleDoor", true, false)
		var holds: Node = _panel.find_child("IdleCapacity", true, false)
		var Door := load("res://scripts/bdp_v3_door.gd")
		var StockTab := load("res://scripts/tvp_v3/stock_tab.gd")
		_check(door != null and door.size.y <= Door.rolled_up_height() + StockTab.CELL_H + 0.5
			and holds != null and _panel.find_child("WarehouseHead", true, false).is_ancestor_of(holds)
			and _panel.find_child("SurplusKnob", true, false) == null and _panel.find_child("GoodsBay", true, false) == null,
			"not yours: no controls, the heading holds the capacity, the door one row high (%.0f px)" % (door.size.y if door != null else -1.0))

	if "idle_port" in cases:
		# Another port tile that isn't yours: the shut door, and what its capacity is made of.
		var port := Catalog.nearest_port_tile(EMPTY_TILE)
		if port != "" and port != TILE and not bool(_panel.call("player_present_on_tile", port)):
			_panel.call("show_tile", _tile_data(port), "stock")
			await _settle(12)
			await _save("idle_port")
		else:
			print("[TVP_SHOT] idle_port skipped: no unowned port tile near %s" % EMPTY_TILE)

	UiPrefs.set_use_tvp_v3(false)
	print("[TVP_CHECK] all cases: %d failed" % _failed)
	print("[TVP_SHOT] done")
	get_tree().quit(0)


## The tab's contract, driven as a player would: its names, the bay opening the Move or sell sheet, Back,
## Expand opening its sheet, and the wide key opening every good.
func _checks(td: Dictionary) -> void:
	var steel := _gid("steel")
	_panel.call("show_tile", td, "stock")
	await _settle(8)
	_check(_panel.find_child("SurplusKnob", true, false) != null and _panel.find_child("SellSurplusToggle", true, false) is Button,
		"the surplus knob as built, its port icon still SellSurplusToggle")
	var goods := Stockpile.get_tile_totals(TILE).size()
	var rack: Node = _panel.find_child("StockpileAllGoods", true, false)
	_check(rack != null and rack.find_children("StoredGood_*", "Button", true, false).size() == goods,
		"every good on the tile is a StoredGood_ button in the bay (%d)" % goods)
	var named := 0
	for b: Node in rack.find_children("StoredGood_*", "Button", true, false):
		var gid := str(b.name).trim_prefix("StoredGood_")
		var label := b.find_child("GoodName", true, false) as Label
		if label != null and label.text == Catalog.get_display_name(gid):
			named += 1
	_check(named == goods, "every good in the bay is named under its icon (%d of %d)" % [named, goods])
	var surplus_knob: Node = _panel.find_child("SurplusKnob", true, false)
	_check(surplus_knob != null and _panel.find_child("WarehouseSection", true, false).is_ancestor_of(surplus_knob),
		"the surplus knob stands in the warehouse, beside its gauge")
	_text_column("busy")
	var gauge: Control = _panel.find_child("StockGauge", true, false)
	var tags: Array = gauge.call("tags") if gauge != null else []
	var top: Array = TileViewData.stockpile_summary(TILE).goods
	_check(not tags.is_empty() and str(tags[0].get("good_id", "")) == str(top[0].good_id),
		"the bar tags its biggest good first (%d tags)" % tags.size())
	_tag_lines("busy")
	# Pointing at a tag lights that good's cell in the bay; picking it opens its sheet, as the bay does.
	var first_gid := str(tags[0].get("good_id", ""))
	gauge.call("_point", first_gid)
	var first_cell: Control = _panel.find_child("StoredGood_" + first_gid, true, false)
	var lit_col: Control = first_cell.get_child(0) as Control if first_cell != null else null
	_check(lit_col != null and lit_col.modulate.r > 1.05 and str(gauge.get("hot")) == first_gid,
		"pointing at a tag lights its good's cell in the bay")
	gauge.call("_point", "")
	gauge.emit_signal("picked", first_gid)
	await _settle(6)
	_check(_panel.find_child("StockGoodActions", true, false) != null and str((_panel.get("_stock_sel") as Dictionary).get("good_id", "")) == first_gid,
		"picking a tag opens its good's Move or sell sheet")
	(_panel.find_child("SheetBack", true, false) as BaseButton).pressed.emit()
	await _settle(6)
	var expand_key: Control = _panel.find_child("ExpandWarehouse", true, false)
	var quote := MatchState.warehouse_upgrade_quote(TILE)
	var after := Stockpile.get_capacity(TILE) - int(quote.get("current_cap", 0)) + int(quote.get("next_cap", 0))
	_check(expand_key != null and str(expand_key.get("text")) == "Expand to %d" % after
		and _panel.find_child("WarehouseHead", true, false).is_ancestor_of(expand_key),
		"Expand sits on the capacity line and says what the tile will hold (%s)" % (str(expand_key.get("text")) if expand_key != null else "none"))
	var cell := _panel.find_child("StoredGood_" + steel, true, false) as Button
	cell.pressed.emit()
	await _settle(6)
	_check(_panel.find_child("StockGoodActions", true, false) != null and str((_panel.get("_stock_sel") as Dictionary).get("good_id", "")) == steel,
		"picking a good in the bay opens its Move or sell sheet")
	(_panel.find_child("DestMarket", true, false) as Control).emit_signal("pressed")
	await _settle(6)
	_check(str(_panel.get("_stock_dest")) == "__market__" and bool(_panel.find_child("DestMarket", true, false).get("latched"))
		and not bool(_panel.find_child("ConfirmStockAction", true, false).get("disabled")),
		"Market latches down and arms the confirm key")
	var detail := _panel.find_child("QuoteDetail", true, false) as Label
	var screen: Node = _panel.find_child("QuoteRow", true, false).find_child("BdpV3Led", true, false) if _panel.find_child("QuoteRow", true, false) != null else null
	var qty := int(_panel.get("_stock_qty"))
	var route := TransportService.route_to_nearest_port(TILE, steel)
	var ctx := {"good_id": steel, "good_internal": "steel"}
	var expected: float = float(qty) * MarketState.get_sale_price(steel, ctx) \
		- float(MarketState.sale_charges(str(route.get("port", "")), route, [{"good_id": steel, "qty": qty}], false, false).transport_cost)
	_check(detail != null and detail.text != "" and screen != null and str(screen.call("figure")).strip_edges() == "%.2f" % expected,
		"the sale's worth sits over the key, from the engine's quote (%s, expected %.2f)" % [
			str(screen.call("figure")) if screen != null else "no screen", expected])
	(_panel.find_child("SheetBack", true, false) as BaseButton).pressed.emit()
	await _settle(6)
	_check(_panel.find_child("StockGoodActions", true, false) == null and _panel.find_child("WarehouseSection", true, false) != null
		and (_panel.get("_stock_sel") as Dictionary).is_empty(), "Back closes the sheet and drops the pick")
	(_panel.find_child("ExpandWarehouse", true, false) as Control).emit_signal("pressed")
	await _settle(6)
	_check(_panel.find_child("WarehouseExpansion", true, false) != null and _panel.find_child("ExpandFromMarket", true, false) != null,
		"Expand opens the warehouse's sheet with its ways to pay")
	(_panel.find_child("SheetBack", true, false) as BaseButton).pressed.emit()
	await _settle(6)
	for i in range(1, 14):
		Stockpile.add(TILE, "g_%03d" % i, 5)
	_panel.call("_refresh_pane", "stock")
	await _settle(6)
	var more: Control = _panel.find_child("OtherGoodsBar", true, false)
	_check(more != null and _panel.find_child("StockpileAllGoods", true, false) == null, "more than eight goods: the wide key, eight in the bay")
	more.emit_signal("toggled", true)
	await _settle(6)
	rack = _panel.find_child("StockpileAllGoods", true, false)
	_check(rack != null and rack.find_children("StoredGood_*", "Button", true, false).size() == Stockpile.get_tile_totals(TILE).size(),
		"the wide key opens every good")
	_panel.set_meta("tvp_stock_all_goods", "")
	for i in range(1, 14):
		Stockpile.consume(TILE, "g_%03d" % i, 5)
	print("[TVP_CHECK] %d failed" % _failed)


## The forecast and fill rules, driven through the states that matter, each compared with the rule it
## must match: the transport panel's own words and colour for the forecast, the stockpile summary's status
## for the fill. The warehouse is filled with steel to each level and its history set to each trend, then
## put back as it was.
func _rules(td: Dictionary) -> void:
	var StockTab := load("res://scripts/tvp_v3/stock_tab.gd")
	var tp: Node = load("res://scripts/transport_panel.gd").new()
	var steel := _gid("steel")
	var key := str(Stockpile.call("_tile_key", TILE))
	var saved_hist: Array = (Stockpile._fill_history.get(key, []) as Array).duplicate()
	var saved_peak := int(Stockpile._peak_used.get(key, 0))
	var saved_refused := int(Stockpile._refused.get(key, 0))
	var saved_steel := int(Stockpile.get_tile_totals(TILE).get(steel, 0))
	var cap := Stockpile.get_capacity(TILE)
	var colour_tone := {DS.PALETTE.DANGER: "bad", DS.PALETTE.WARN: "warn"}
	var status_tone := {"problem": "bad", "warn": "warn", "ok": "ok", "muted": "off"}
	# [room left, change a turn, what the line must say or "" for any]
	var cases := [[10, 50, "Full next turn at this rate"], [150, 50, "Full in 3 turns at this rate"],
		[220, 10, "Full in 22 turns at this rate"], [700, -30, "Emptying, down about 30 a turn"],
		[700, 0, "Steady over the last 3 turns"], [100, 0, ""], [210, 0, ""]]
	for c: Array in cases:
		var want := cap - int(c[0])
		var now := Stockpile.get_used_capacity(TILE)
		if want > now:
			Stockpile.add(TILE, steel, want - now)
		elif want < now:
			Stockpile.consume(TILE, steel, now - want)
		var used := Stockpile.get_used_capacity(TILE)
		var step := int(c[1])
		Stockpile._fill_history[key] = [used - 3 * step, used - 2 * step, used - step, used]
		var stock: Dictionary = TileViewData.stockpile_summary(TILE)
		var ahead: Dictionary = StockTab.eta(TILE, stock)
		var fill := float(used) / float(cap)
		var their_tone := str(colour_tone.get(tp.call("_eta_color", TILE, fill), "neutral"))
		var ours := str(ahead.get("tone", "none"))
		var agree := their_tone == ours or (their_tone == "neutral" and ours in ["ok", "off"])
		_check(agree and (str(c[2]) == "" or str(ahead.get("text", "")) == str(c[2])),
			"forecast at %d of %d, %+d a turn: \"%s\" %s, the transport panel says \"%s\" %s" % [
				used, cap, step, str(ahead.get("text", "")), ours, str(tp.call("_full_eta_text", TILE, fill)), their_tone])
		_check(StockTab.fill_tone(used, cap) == str(status_tone.get(str(stock.status), "?")),
			"the fill's rule at %d%%: %s, the stockpile summary's %s" % [roundi(fill * 100.0), StockTab.fill_tone(used, cap), str(stock.status)])
		if int(c[0]) == 10:
			_panel.call("show_tile", td, "stock")
			await _settle(10)
			var row: Node = _panel.find_child("TrendRow", true, false)
			var lamp: Node = row.find_child("BdpV3Lamp", true, false) if row != null else null
			_check(row != null and lamp != null and str(lamp.get("colour")) == "red" and row.find_child("LineWayOut", true, false) != null,
				"a tile about to fill shows it on its forecast line, lamp red, the way out under it")
			_led_tone("filling", stock)
			await _save("filling")
	# Last turn's peak is judged by the fill's own thresholds: amber at 92%, green at 85%.
	for pct in [85, 92]:
		Stockpile._peak_used[key] = roundi(cap * pct / 100.0)
		_panel.call("_refresh_pane", "stock")
		await _settle(6)
		var peak_row: Node = _panel.find_child("PeakRow", true, false)
		var lamp: Node = peak_row.find_child("BdpV3Lamp", true, false) if peak_row != null else null
		var want_colour := "amber" if pct >= 90 else "green"
		_check(lamp != null and str(lamp.get("colour")) == want_colour,
			"last turn's peak at %d%% lights %s, as the fill would" % [pct, str(lamp.get("colour")) if lamp != null else "nothing"])
		if pct == 92:
			# A peak near the bar's end leaves no room on the glass: PEAK is a tag right over its mark.
			_tag_lines("peak_high")
			await _save("peak_high")
	tp.free()
	var now := int(Stockpile.get_tile_totals(TILE).get(steel, 0))
	if now > saved_steel:
		Stockpile.consume(TILE, steel, now - saved_steel)
	elif now < saved_steel:
		Stockpile.add(TILE, steel, saved_steel - now)
	Stockpile._fill_history[key] = saved_hist
	Stockpile._peak_used[key] = saved_peak
	if saved_refused > 0:
		Stockpile._refused[key] = saved_refused
	else:
		Stockpile._refused.erase(key)
	_panel.call("_refresh_pane", "stock")
	await _settle(4)


## Every warehouse line's words, and every waiting shipment, start in one column.
func _text_column(tag: String) -> void:
	var readings: Node = _panel.find_child("WarehouseSection", true, false)
	if readings == null:
		return
	var xs: Array = []
	for n: Node in readings.find_children("*", "Label", true, false):
		if str(n.name) in ["LineWords", "SurplusWords"]:
			xs.append((n as Control).global_position.x)
	for n: Node in readings.find_children("OverflowShipment", "", true, false):
		xs.append(((n as Control).get_child(0) as Control).global_position.x)
	var lo: float = xs.min() if not xs.is_empty() else 0.0
	var hi: float = xs.max() if not xs.is_empty() else 0.0
	_check(xs.size() >= 2 and hi - lo <= 0.5, "%s: the warehouse's %d lines share one text column (%.1f to %.1f)" % [tag, xs.size(), lo, hi])


## No tag's line fans out across the bar: a tag with its own line sits within half a tile of what it names,
## tags that had to spread stand on a shelf whose legs are on the ends of their goods' stretch of fill, and
## PEAK is lit on the glass beside its mark or is a tag right over it.
func _tag_lines(tag: String) -> void:
	var gauge: Control = _panel.find_child("StockGauge", true, false)
	if gauge == null:
		_check(false, "%s: no gauge" % tag)
		return
	var StockGauge := load("res://scripts/tvp_v3/stock_gauge.gd")
	var ok := true
	var worst := 0.0
	var on_shelf := 0
	var peak_ok := not bool(gauge.call("peak_marked")) or bool(gauge.call("peak_on_glass"))
	for t: Dictionary in gauge.call("tags"):
		var run := absf(float(t.at) - float(t.target))
		if str(t.kind) == "peak":
			peak_ok = run <= float(t.w) * 0.5
			continue
		if int(t.shelf) >= 0:
			on_shelf += 1
			continue
		worst = maxf(worst, run)
		ok = ok and run <= StockGauge.ICON_PX * 0.5
	for sh: Dictionary in gauge.call("shelves"):
		var x_lo: float = gauge.call("_x", 0.0)
		ok = ok and float(sh.x1) >= float(sh.x0) and float(sh.x0) >= x_lo - 0.5
	_check(ok and peak_ok, "%s: no line fans out (own lines run at most %.0f px sideways, %d tags on shelves, PEAK %s)" % [
		tag, worst, on_shelf, "on the glass" if bool(gauge.call("peak_on_glass")) else ("over its mark" if bool(gauge.call("peak_marked")) else "not marked")])


## What is stored is lit in the fill's tone: white, amber when nearly full, red when full.
func _led_tone(tag: String, stock: Dictionary) -> void:
	var led: Node = _panel.find_child("StoredLed", true, false)
	var want: Color = {"problem": DS.PALETTE.DANGER, "warn": DS.PALETTE.WARN}.get(str(stock.status), DS.PALETTE.TEXT)
	_check(led != null and led.get("colour") == want, "%s: the stored figure is lit as the fill (%s)" % [tag, str(stock.status)])


var _failed := 0


func _check(ok: bool, what: String) -> void:
	print("[TVP_CHECK] %s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_failed += 1


func _gid(internal: String) -> String:
	return str(Catalog.get_good_by_internal_name(internal).get("id", ""))


func _tile_data(tile: String) -> Dictionary:
	var terrain: Node = _wm.get("terrain_layer")
	var td: Dictionary = {"id": tile}
	if terrain != null and terrain.has_method("id_to_coord"):
		td = terrain.tiles.get(terrain.id_to_coord(tile), td)
	return td


func _top() -> void:
	var scroll: ScrollContainer = _panel.find_child("BodyScroll", true, false)
	if scroll != null:
		scroll.scroll_vertical = 0


func _bottom() -> void:
	var scroll: ScrollContainer = _panel.find_child("BodyScroll", true, false)
	if scroll != null:
		scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)


func _scroll_to(node_name: String) -> void:
	var scroll: ScrollContainer = _panel.find_child("BodyScroll", true, false)
	var target: Control = _panel.find_child(node_name, true, false)
	if scroll != null and target != null:
		scroll.scroll_vertical = int(target.global_position.y - scroll.global_position.y + scroll.scroll_vertical - 8.0)


func _save(tag: String) -> void:
	# The game's own prompt when a tile fills would stand over the panel's left side.
	var prompt_script := load("res://scripts/capacity_dialog.gd")
	for n in _wm.find_children("*", "PanelContainer", true, false):
		if n.get_script() == prompt_script:
			(n as Control).visible = false
	await _settle(2)
	# Width discipline (docs/ds2-theme.md §7.12): the body never asks for more than the scroll shows.
	var scroll: ScrollContainer = _panel.find_child("BodyScroll", true, false)
	var host: Control = _panel.get("_pane_host")
	if scroll != null and host != null:
		var bar := scroll.get_v_scroll_bar().size.x if scroll.get_v_scroll_bar().visible else 0.0
		var need := host.get_combined_minimum_size().x
		print("[TVP_SHOT] width %s: body asks %.0f of %.0f %s" % [tag, need, scroll.size.x - bar, "ok" if need <= scroll.size.x - bar + 0.5 else "CREEP"])
		# A sheet's holder clips, so a row too wide for it would be cut off rather than widen the body.
		var plate: Control = _panel.find_child("SheetPlate", true, false)
		if plate != null and plate.get_parent() is Control:
			var holder := plate.get_parent() as Control
			var ask := plate.get_combined_minimum_size().x
			var fits := ask <= holder.size.x + 0.5
			print("[TVP_SHOT] width %s: sheet asks %.0f of %.0f %s" % [tag, ask, holder.size.x, "ok" if fits else "CLIPPED"])
			_check(fits, "the %s sheet fits its holder (%.0f of %.0f)" % [tag, ask, holder.size.x])
	RenderingServer.force_draw(false)
	var r := _panel.get_global_rect().grow(16.0)
	var img := _vp.get_texture().get_image()
	var k := img.get_width() / float(LOGICAL.x)
	var px := Rect2i(Vector2i(r.position * k), Vector2i(r.size * k)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	img.get_region(px).save_png(_out.path_join("tvp_v3_stock_%s.png" % tag))
	print("[TVP_SHOT] saved %s" % tag)


func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
