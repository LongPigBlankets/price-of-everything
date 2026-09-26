extends Node2D
## Captures of the tile view v3's Stock tab in the cases tools/tvp_v3_shot.gd lacks: the Move or sell sheet
## (sliding in over the body, settled, a destination chosen, every turn, a special order), the warehouse's
## upgrade sheet, a bay with more goods than it shows (closed and opened), a full warehouse with goods
## turned away and shipments waiting, the routing knobs of an intermediary game, land you own with nothing
## stored, a tile about to fill, a peak near the bar's end, a tile that isn't yours, and the whole Move or
## sell flow driven with real clicks and keys. Beside the captures it checks the tab's contract and its
## rules: the forecast line against the transport panel's own rule, last turn's peak and the stored figure
## against the stockpile summary's thresholds, one line when full with the backlog straight under it, one
## text column, no tag line fanning out across the bar, the bar's tags picking and lighting goods as the
## bay does, the licence's name, the upgrade key and its strip against the engine's capacity at the next
## level, figures that aren't money on dot matrices, no case's rim over another's, the sheet laid over the
## body rather than in its place, the flow's effects in the engine's own state, and that neither the body
## nor a sheet asks for more width than the scroll shows.
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
	var cases := only.split(",") if only != "" else PackedStringArray(["checks", "rules", "hover", "sheet", "sheet_tile", "expand", "few", "maxed", "many", "full", "logistics", "owned_empty", "idle", "idle_port", "flow"])

	if "checks" in cases:
		await _checks(td)

	if "rules" in cases:
		await _rules(td)

	if "hover" in cases:
		# Pointing at a good in the bay lights its slice in the warehouse's bar.
		_panel.call("show_tile", td, "stock")
		await _settle(10)
		_top()
		await _settle(3)
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
		_scroll_to("GoodsBay")
		await _settle(4)
		var body_at := _body_scroll()
		_panel.call("select_stock_good", _gid("steel"))
		await _settle(3)
		await _save("sheet_sliding")
		await _settle(30)
		await _save("sheet")
		_sheet_over_body("sheet", body_at)
		# It is the Stock tab's alone: leaving the tab takes it off, the land's full view hides it, and coming
		# back to Stock with the good still picked lays it over the body again.
		_panel.call("_select_tab", "bl")
		await _settle(4)
		var gone := _no_cover()
		_panel.call("_select_tab", "stock")
		await _settle(4)
		var back := not _no_cover()
		_panel.call("_set_land_open", true)
		await _settle(4)
		var lid: Control = _panel.find_child("StockGoodActions", true, false)
		var hidden := lid != null and not lid.visible
		_panel.call("_set_land_open", false)
		await _settle(4)
		lid = _panel.find_child("StockGoodActions", true, false)
		_check(gone and back and hidden and lid != null and lid.visible,
			"the sheet goes with the Stock tab (%s), returns with it (%s), and hides under the land's full view (%s)" % [str(gone), str(back), str(hidden)])
		_panel.set("_stock_dest", "__market__")
		_panel.call("_refresh_pane", "stock")
		await _settle(8)
		var once_words := str((_panel.find_child("QuoteDetail", true, false) as Label).text)
		await _save("sheet_market_once")
		_panel.set("_stock_recurring", true)
		_panel.call("_refresh_pane", "stock")
		await _settle(8)
		var every_words := str((_panel.find_child("QuoteDetail", true, false) as Label).text)
		_check(every_words.begins_with("a turn") and not once_words.contains("a turn"),
			"the price line says a turn when it repeats (\"%s\"), not when once (\"%s\")" % [every_words, once_words])
		await _save("sheet_market")
		SpecialOrderState.create_order("steel", -1, 4, 30)
		_panel.set("_stock_dest", "__special_order__")
		_panel.call("_refresh_pane", "stock")
		await _settle(8)
		await _save("sheet_special")
		_sheet_bottom()
		await _settle(4)
		await _save("sheet_bottom")
		# A rebuild of the same sheet (a key on it pressed) keeps it where it was scrolled to.
		var sheet_scroll: ScrollContainer = _panel.find_child("SheetScroll", true, false)
		var was := sheet_scroll.scroll_vertical if sheet_scroll != null else -1
		_panel.call("_refresh_pane", "stock")
		await _settle(8)
		sheet_scroll = _panel.find_child("SheetScroll", true, false)
		_check(was > 0 and sheet_scroll != null and absi(sheet_scroll.scroll_vertical - was) <= 1,
			"a sheet rebuilt in place keeps its scroll (%d, now %d)" % [was, sheet_scroll.scroll_vertical if sheet_scroll != null else -1])
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
		_panel.set("_stock_recurring", true)
		_panel.call("_refresh_pane", "stock")
		await _settle(30)
		await _save("sheet_tile")
		_panel.set("_stock_recurring", false)
		_panel.set("_stock_sel", {})
		_panel.set("_stock_dest", "")

	if "expand" in cases:
		_panel.call("show_tile", td, "stock")
		await _settle(8)
		_panel.set("_warehouse_expand", true)
		_panel.call("_refresh_pane", "stock")
		await _settle(30)
		await _save("expand")
		var dots: Node = _panel.find_child("CapacityDots", true, false)
		var quote := MatchState.warehouse_upgrade_quote(TILE)
		var after := _capacity_at_level(TILE, int(quote.get("next_level", 2)))
		_check(dots != null and str(dots.get("text")) == "%d → %d" % [Stockpile.get_capacity(TILE), after]
			and _panel.find_child("WarehouseExpansion", true, false).find_child("BdpV3Led", true, false) != null,
			"the upgrade sheet's capacity is on a dot matrix (%s), its money on LEDs" % (str(dots.get("text")) if dots != null else "none"))
		_panel.set("_warehouse_expand", false)
		_panel.call("_refresh_pane", "stock")
		await _settle(6)
		_check(_panel.find_child("WarehouseExpansion", true, false) == null and _no_cover(),
			"closing the upgrade sheet takes it off the body")

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
		var maxed_key: Node = _panel.find_child("WarehouseMaxed", true, false)
		var maxed_strip: Node = _panel.find_child("CapacityStrip", true, false)
		_check(maxed_key != null and bool(maxed_key.get("disabled")) and maxed_strip != null
			and str(maxed_strip.get("text")) == "CAPACITY: %d" % Stockpile.get_capacity(TILE),
			"at the top level the key is greyed and the strip says the capacity (%s)" % (str(maxed_strip.get("text")) if maxed_strip != null else "none"))
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
		# A click on the +N tag opens every good in the bay and brings the bay into view.
		_top()
		await _settle(3)
		var many_gauge: Control = _panel.find_child("StockGauge", true, false)
		await _click(many_gauge.get_global_transform() * (many_gauge.call("_tag_rect", more[0]) as Rect2).get_center())
		await _settle(6)
		var all_rack: Control = _panel.find_child("StockpileAllGoods", true, false)
		var view: Rect2 = (_panel.find_child("BodyScroll", true, false) as Control).get_global_rect()
		var bay_top: float = (_panel.find_child("GoodsBay", true, false) as Control).global_position.y
		_check(all_rack != null and all_rack.find_children("StoredGood_*", "Button", true, false).size() == goods_n
			and bay_top >= view.position.y - 0.5 and bay_top <= view.position.y + 40.0,
			"a click on the +N tag opens every good in the bay and brings it into view (%d goods, the bay %.0f px down the view)" % [
				all_rack.find_children("StoredGood_*", "Button", true, false).size() if all_rack != null else 0, bay_top - view.position.y])
		await _save("many_more_clicked")
		_panel.set_meta("tvp_stock_all_goods", "")
		_panel.set_meta("tvp_stock_all_goods", TILE)
		_panel.call("_refresh_pane", "stock")
		await _settle(8)
		_scroll_to("GoodsBay")
		await _settle(4)
		await _save("many_open")
		_panel.set_meta("tvp_stock_all_goods", "")

	if "full" in cases:
		var had_steel := Stockpile.get_at_tile(TILE, _gid("steel"))
		var had_coal := Stockpile.get_at_tile(TILE, _gid("coal"))
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
		_stored_tone("full", TileViewData.stockpile_summary(TILE))
		_overlaps("full")
		# The backlog sits in the readings, straight under the full line, a line's gap apart, each
		# shipment's wait in its own sentence.
		var full_row: Control = _panel.find_child("FullRow", true, false)
		var head: Control = _panel.find_child("OverflowHead", true, false)
		var StockTab := load("res://scripts/tvp_v3/stock_tab.gd")
		var under := full_row != null and head != null and head.get_parent() == readings \
			and head.get_index() == full_row.get_index() + 1
		var gap := head.global_position.y - full_row.get_global_rect().end.y if under else -1.0
		var words: Node = _panel.find_child("ShipmentWords", true, false)
		_check(under and absf(gap - float(StockTab.LINE_GAP)) <= 0.5 and words != null and "waiting" in (words as RichTextLabel).get_parsed_text(),
			"the backlog sits straight under the full line (%.1f px apart), each shipment's wait beside it" % gap)
		# Each shipment on one line: its good's quantity on the pill in its well, its name and wait unwrapped.
		var one_line := true
		var pills := 0
		for row: Node in _panel.find_children("OverflowShipment", "", true, false):
			var said := row.find_child("ShipmentWords", true, false) as RichTextLabel
			var well: Control = row.find_child("GoodInWell", true, false)
			if row.find_child("QtyPill", true, false) != null:
				pills += 1
			one_line = one_line and said != null and said.get_line_count() == 1 and "waiting" in said.get_parsed_text() \
				and well != null and absf(well.get_global_rect().get_center().y - said.get_global_rect().get_center().y) <= 1.5 \
				and not "(" in said.get_parsed_text()
		_check(one_line and pills == _panel.find_children("OverflowShipment", "", true, false).size() and pills > 0,
			"each waiting shipment sits on one line, its quantity on its well's pill, no coordinates (%d)" % pills)
		_bottom()
		await _settle(4)
		await _save("full_bottom")
		# Back as it was, so the cases after this one have room.
		Stockpile.consume(TILE, _gid("steel"), Stockpile.get_at_tile(TILE, _gid("steel")) - had_steel)
		Stockpile.consume(TILE, _gid("coal"), Stockpile.get_at_tile(TILE, _gid("coal")) - had_coal)
		TransportState.overflow_shipments = TransportState.overflow_shipments.filter(func(r: Dictionary) -> bool:
			return not (str(r.get("destination_tile", "")) == TILE and str(r.get("source_tile", "")) == "tile_6_10"))
		Stockpile._refused.erase(str(Stockpile.call("_tile_key", TILE)))

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
		# The bar sits under the head, as on a busy tile, not floated down beside the knob.
		var head_e: Control = _panel.find_child("WarehouseHead", true, false)
		var gauge_e: Control = _panel.find_child("StockGauge", true, false)
		var fill_e: Control = _panel.find_child("WarehouseFill", true, false)
		var lift := gauge_e.global_position.y - fill_e.global_position.y if gauge_e != null and fill_e != null else -1.0
		_check(head_e != null and gauge_e != null and lift <= 0.5,
			"owned and empty: the bar starts at the top of its column, under the head (%.1f px down)" % lift)
		_overlaps("owned_empty")
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
		_overlaps("idle")
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

	if "flow" in cases:
		await _flow(td)

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
	# Picked with the mouse, as a player does, from each of the three places a good can be picked.
	for how: String in ["tag", "slice", "bay"]:
		_top()
		await _settle(3)
		gauge = _panel.find_child("StockGauge", true, false)
		var gid := first_gid if how == "tag" else (_gid("copper_wiring") if how == "slice" else steel)
		var at := _tag_point(gauge, gid) if how == "tag" else (_slice_point(gauge, gid) if how == "slice" else Vector2.ZERO)
		if how == "bay":
			_scroll_to("StoredGood_" + gid)
			await _settle(3)
			at = (_panel.find_child("StoredGood_" + gid, true, false) as Control).get_global_rect().get_center()
		await _click(at)
		await _settle(4)
		var picked := str((_panel.get("_stock_sel") as Dictionary).get("good_id", ""))
		# And nothing else took the click (a good's icon elsewhere opens its encyclopedia entry).
		var search: Control = _wm.find_child("SearchOverlay", true, false)
		var opened := search != null and search.visible
		if opened:
			search.call("close_search")
		_check(_panel.find_child("StockGoodActions", true, false) != null and picked == gid and not opened,
			"a click on the good's %s opens its Move or sell sheet (%s)" % [{"tag": "tag over the bar", "slice": "slice of the bar", "bay": "cell in the bay"}[how], Catalog.get_display_name(picked)])
		await _click((_panel.find_child("SheetBack", true, false) as Control).get_global_rect().get_center())
		await _settle(4)
		_check(_panel.find_child("StockGoodActions", true, false) == null and (_panel.get("_stock_sel") as Dictionary).is_empty(),
			"Back, clicked, takes the %s pick's sheet off" % how)
	# The head: the stored figure against the capacity on a dot matrix, the upgrade key over its strip.
	var head: Control = _panel.find_child("WarehouseHead", true, false)
	var up_key: Control = _panel.find_child("UpgradeWarehouse", true, false)
	var strip: Control = _panel.find_child("CapacityStrip", true, false)
	var quote := MatchState.warehouse_upgrade_quote(TILE)
	var next_level := int(quote.get("next_level", 2))
	var cap_now := Stockpile.get_capacity(TILE)
	var after := _capacity_at_level(TILE, next_level)
	var strip_ok := up_key != null and strip != null and absf(strip.global_position.x - up_key.global_position.x) <= 0.5 \
		and absf(strip.size.x - up_key.size.x) <= 0.5 and strip.global_position.y > up_key.get_global_rect().end.y
	_check(up_key != null and str(up_key.get("text")) == "Upgrade to Lvl%d" % next_level and head.is_ancestor_of(up_key) and strip_ok
		and str(strip.get("text")) == "CAPACITY: %d → %d" % [cap_now, after],
		"the upgrade key says \"%s\", the strip under it \"%s\" (the engine holds %d at level %d)" % [
			str(up_key.get("text")) if up_key != null else "none", str(strip.get("text")) if strip != null else "none", after, next_level])
	var stored: Node = _panel.find_child("StoredDots", true, false)
	_check(stored != null and str(stored.get("text")).ends_with("%d OF %d" % [Stockpile.get_used_capacity(TILE), cap_now])
		and _panel.find_child("WarehouseSection", true, false).find_child("BdpV3Led", true, false) == null,
		"the stored figure is on a dot matrix (%s), no seven segment screen in the warehouse" % (str(stored.get("text")) if stored != null else "none"))
	_overlaps("busy")
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
	(_panel.find_child("UpgradeWarehouse", true, false) as Control).emit_signal("pressed")
	await _settle(6)
	_check(_panel.find_child("WarehouseExpansion", true, false) != null and _panel.find_child("ExpandFromMarket", true, false) != null
		and str((_panel.find_child("SheetTitle", true, false) as Label).text) == "Upgrade to Lvl%d" % next_level,
		"the upgrade key opens the warehouse's sheet with its ways to pay")
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
			_stored_tone("filling", stock)
			_top()
			await _settle(3)
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
			_top()
			await _settle(3)
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


## What is stored is in white on its dot matrix, a mark before it lit amber when nearly full, red when full.
func _stored_tone(tag: String, stock: Dictionary) -> void:
	var dots: Node = _panel.find_child("StoredDots", true, false)
	var runs: Array = dots.get("_runs") if dots != null else []
	var want: Variant = {"problem": DS.PALETTE.DANGER, "warn": DS.PALETTE.WARN}.get(str(stock.status), null)
	var ok := dots != null and not runs.is_empty() and Color(runs[-1].colour) == Color.WHITE
	if want == null:
		ok = ok and runs.size() == 1
	else:
		ok = ok and runs.size() == 2 and Color(runs[0].colour) == want and str(runs[0].text).begins_with("●")
	_check(ok, "%s: the stored figure is white, its mark lit as the fill (%s)" % [tag, str(stock.status)])



## The whole Move or sell flow, driven with real clicks and keys through the viewport as a player would, then
## checked in the engine's own state:
##   once to the market (picked on the bar's slice): the goods leave the tile and the sale is paid;
##   every turn to the market (picked in the bay): the entry is filed, and after a turn it has sold again;
##   to a special order (picked on the bar's tag): the order is committed;
##   every turn to a tile picked on the map (picked on the bar's slice): the freight is paid, the shipment is
##   on its way, the entry is filed, and after a turn another has gone.
## Plastics and glass stand in for the goods: none of the tile's buildings make or use them.
func _flow(td: Dictionary) -> void:
	var plastics := _gid("plastics")
	var glass := _gid("glass")
	var steel := _gid("steel")
	var dest := "tile_6_10"
	Stockpile.add(TILE, plastics, 40 - Stockpile.get_at_tile(TILE, plastics))
	Stockpile.add(TILE, glass, 40 - Stockpile.get_at_tile(TILE, glass))
	MatchState.money = 8000.0
	_panel.call("show_tile", td, "stock")
	await _settle(10)

	# 1. Once to the market, picked on the plastics' slice of the warehouse's bar.
	var money0 := MatchState.money
	await _pick_on_bar(plastics, false)
	await _save("flow_picked")
	await _type_qty(7)
	await _click_named("DestMarket")
	var net := _screen_figure("QuoteRow")
	var said := _text_of("ConfirmStockAction")
	await _save("flow_market_once")
	await _click_named("ConfirmStockAction")
	await _settle(6)
	var paid := MatchState.money - money0
	_check(said == "Sell 7 Plastics" and Stockpile.get_at_tile(TILE, plastics) == 33 and absf(paid - net) <= 0.05 and _no_cover(),
		"flow, once to the market: \"%s\" took 7 Plastics off the tile (%d left) and paid £%.2f (quoted £%.2f), the sheet closed" % [
			said, Stockpile.get_at_tile(TILE, plastics), paid, net])

	# 2. Every turn to the market, picked in the bay.
	await _pick_in_bay(plastics)
	await _type_qty(5)
	await _click_named("DestMarket")
	await _click_switch()
	said = _text_of("ConfirmStockAction")
	var words := _text_of("QuoteDetail")
	await _save("flow_market_every")
	await _click_named("ConfirmStockAction")
	await _settle(6)
	var filed_sell := MatchState.recurring_sells.filter(func(e: Dictionary) -> bool:
		return str(e.get("source", "")) == TILE and int((e.get("goods", {}) as Dictionary).get(plastics, 0)) == 5)
	_check(said == "Sell 5 Plastics every turn" and words.begins_with("a turn") and Stockpile.get_at_tile(TILE, plastics) == 28
		and filed_sell.size() == 1, "flow, every turn to the market: \"%s\" (%s) sold 5 now (%d left) and filed the every turn sale" % [
			said, words, Stockpile.get_at_tile(TILE, plastics)])

	# 3. A special order, picked on the steel's tag over the bar.
	var order := SpecialOrderState.get_active_order_for_good(steel)
	if order.is_empty():
		order = SpecialOrderState.create_order("steel", -1, 4, 30)
	var committed0 := int(order.get("qty_committed", 0))
	var steel0 := Stockpile.get_at_tile(TILE, steel)
	await _pick_on_bar(steel, true)
	await _click_named("DestSpecialOrder")
	await _type_qty(6)
	said = _text_of("ConfirmStockAction")
	await _save("flow_special")
	await _click_named("ConfirmStockAction")
	await _settle(6)
	order = SpecialOrderState.get_order(str(order.get("id", "")))
	_check(said == "Send 6 Steel to the order" and int(order.get("qty_committed", 0)) == committed0 + 6
		and Stockpile.get_at_tile(TILE, steel) == steel0 - 6, "flow, special order: \"%s\" committed 6 more to the order (%d) and took them off the tile" % [
			said, int(order.get("qty_committed", 0))])

	# 4. Every turn to a tile picked on the map, picked on the glass's slice.
	money0 = MatchState.money
	var shipments0 := _shipments(glass, dest)
	await _pick_on_bar(glass, false)
	await _type_qty(10)
	await _click_named("DestTile")
	var picking := bool(_wm.get("_v2_picking_dest"))
	# The map's own click on the tile, as the terrain layer reports it.
	(_wm.get("terrain_layer") as Node).emit_signal("stockpile_destination_selected", _tile_data(dest), false, false)
	await _settle(6)
	await _click_switch()
	var freight := _screen_figure("QuoteRow")
	said = _text_of("ConfirmStockAction")
	var to := _text_of("DestinationName")
	await _save("flow_tile_every")
	await _click_named("ConfirmStockAction")
	await _settle(6)
	var filed_move := TransportState.recurring_moves.filter(func(e: Dictionary) -> bool:
		return str(e.get("source", "")) == TILE and str(e.get("dest", "")) == dest and int((e.get("goods", {}) as Dictionary).get(glass, 0)) == 10)
	var spent := money0 - MatchState.money
	_check(picking and said == "Move 10 Glass every turn" and Stockpile.get_at_tile(TILE, glass) == 30 and _shipments(glass, dest) == shipments0 + 10
		and absf(spent - freight) <= 0.05 and filed_move.size() == 1,
		"flow, every turn to a tile: the map was asked for a tile (%s), \"%s\" %s sent 10 Glass (on the way %d), paid £%.2f freight (quoted £%.2f), filed the every turn move" % [
			str(picking), said, to, _shipments(glass, dest), spent, freight])

	# A turn later the every turn ones have gone again.
	TurnManager.commit_turn()
	if TurnManager.is_resolving:
		await TurnManager.turn_resolution_completed
	await _settle(10)
	_check(Stockpile.get_at_tile(TILE, plastics) == 23 and Stockpile.get_at_tile(TILE, glass) == 20,
		"flow, a turn later: the every turn sale and move ran again (Plastics %d, Glass %d on the tile)" % [
			Stockpile.get_at_tile(TILE, plastics), Stockpile.get_at_tile(TILE, glass)])
	for e: Dictionary in filed_sell:
		MatchState.remove_recurring_sell(e)
	for e: Dictionary in filed_move:
		TransportState.remove_recurring_move(e)


## Units of `good` on their way from the busy tile to `dest`, or already there.
func _shipments(good: String, dest: String) -> int:
	var n := Stockpile.get_at_tile(dest, good)
	for sh: Dictionary in TransportState.pending_transport_shipments:
		if str(sh.get("source_tile", "")) == TILE and str(sh.get("destination_tile", "")) == dest and str(sh.get("good_id", "")) == good:
			n += int(sh.get("qty", 0))
	return n


func _pick_on_bar(gid: String, on_tag: bool) -> void:
	_top()
	await _settle(3)
	var gauge: Control = _panel.find_child("StockGauge", true, false)
	await _click(_tag_point(gauge, gid) if on_tag else _slice_point(gauge, gid))
	await _settle(6)


func _pick_in_bay(gid: String) -> void:
	var open := _panel.find_child("OtherGoodsBar", true, false)
	if open != null and _panel.find_child("StoredGood_" + gid, true, false) == null:
		open.emit_signal("toggled", true)
		await _settle(4)
	_scroll_to("StoredGood_" + gid)
	await _settle(3)
	await _click((_panel.find_child("StoredGood_" + gid, true, false) as Control).get_global_rect().get_center())
	await _settle(6)


## Types a quantity into the sheet's screen: click it, clear it, the digits, Enter.
func _type_qty(qty: int) -> void:
	var field: LineEdit = _panel.find_child("QuantityRow", true, false).find_child("Entry", true, false)
	await _click_control(field)
	_key(KEY_END)
	for _i in 8:
		_key(KEY_BACKSPACE)
	for ch in str(qty):
		_key(KEY_0 + int(ch), ch.unicode_at(0))
	_key(KEY_ENTER)
	await _settle(3)


func _key(code: Key, unicode := 0) -> void:
	for down in [true, false]:
		var k := InputEventKey.new()
		k.keycode = code
		k.physical_keycode = code
		k.unicode = unicode if down else 0
		k.pressed = down
		_vp.push_input(k, true)


## Throws the sheet's Once / Every turn switch.
func _click_switch() -> void:
	var sw: Node = _panel.find_child("RepeatRow", true, false).find_child("Switch", true, false)
	await _click_control(sw.get_child(1) as Control)
	await _settle(6)


func _click_named(node_name: String) -> void:
	await _click_control(_panel.find_child(node_name, true, false) as Control)
	await _settle(6)


## Scrolls a control into view within the sheet's own scroll when it is on the sheet, then clicks its middle.
func _click_control(c: Control) -> void:
	var p: Node = c.get_parent()
	while p != null and not (p is ScrollContainer):
		p = p.get_parent()
	if p != null:
		(p as ScrollContainer).ensure_control_visible(c)
		await _settle(3)
	await _click(c.get_global_rect().get_center())


## A left click at `at` (the HUD's logical pixels), pushed through the viewport as the mouse's would be.
func _click(at: Vector2) -> void:
	var move := InputEventMouseMotion.new()
	move.position = at
	move.global_position = at
	_vp.push_input(move, true)
	for down in [true, false]:
		var b := InputEventMouseButton.new()
		b.button_index = MOUSE_BUTTON_LEFT
		b.pressed = down
		b.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		b.position = at
		b.global_position = at
		_vp.push_input(b, true)
	await _settle(2)


## The middle of a good's tag over the gauge's bar, and of its slice on the bar, in the HUD's pixels.
func _tag_point(gauge: Control, gid: String) -> Vector2:
	for t: Dictionary in gauge.call("tags"):
		if str(t.kind) == "good" and str(t.good_id) == gid:
			return gauge.get_global_transform() * (gauge.call("_tag_rect", t) as Rect2).get_center()
	return Vector2(-1, -1)


func _slice_point(gauge: Control, gid: String) -> Vector2:
	var pane: Rect2 = gauge.call("_pane")
	for sl: Dictionary in gauge.get("slices"):
		if str(sl.good_id) == gid:
			var x := (float(gauge.call("_x", float(sl.from))) + float(gauge.call("_x", float(sl.to)))) * 0.5
			return gauge.get_global_transform() * Vector2(x, pane.get_center().y)
	return Vector2(-1, -1)


func _text_of(node_name: String) -> String:
	var n: Node = _panel.find_child(node_name, true, false)
	if n == null:
		return ""
	if "text" in n:
		return str(n.get("text"))
	var said := PackedStringArray()
	for l: Node in n.find_children("*", "Label", true, false):
		if (l as Label).text != "":
			said.append((l as Label).text)
	return " ".join(said)


func _screen_figure(row_name: String) -> float:
	var row: Node = _panel.find_child(row_name, true, false)
	var screen: Node = row.find_child("BdpV3Led", true, false) if row != null else null
	return str(screen.call("figure")).strip_edges().to_float() if screen != null else NAN


## What the engine says the tile holds with its warehouse at `level`: the level set, the capacity read, the
## level put back.
func _capacity_at_level(tile: String, level: int) -> int:
	var key := str(Stockpile.call("_tile_key", tile))
	var had := int(Stockpile._warehouse_levels.get(key, 1))
	Stockpile.set_warehouse_level(tile, level)
	var cap := Stockpile.get_capacity(tile)
	Stockpile.set_warehouse_level(tile, had)
	return cap


func _body_scroll() -> int:
	var scroll: ScrollContainer = _panel.find_child("BodyScroll", true, false)
	return scroll.scroll_vertical if scroll != null else -1


## The sheet lies over the body, which is still built under it and scrolled where it was: the sheet's cover
## is the scroll's sibling on the navy sheet and covers exactly the scroll's view.
func _sheet_over_body(tag: String, body_at: int) -> void:
	var scroll: ScrollContainer = _panel.find_child("BodyScroll", true, false)
	var lid: Control = _panel.find_child("StockGoodActions", true, false)
	var same := lid != null and scroll != null and lid.get_parent() == scroll.get_parent() \
		and lid.get_global_rect().position.distance_to(scroll.get_global_rect().position) <= 0.5 \
		and lid.get_global_rect().size.distance_to(scroll.get_global_rect().size) <= 0.5
	_check(same and _panel.find_child("WarehouseSection", true, false) != null and _panel.find_child("GoodsBay", true, false) != null
		and scroll.scroll_vertical == body_at,
		"%s: the sheet lies over the body's view, the body built under it and scrolled where it was (%d, was %d)" % [
			tag, scroll.scroll_vertical if scroll != null else -1, body_at])


func _sheet_bottom() -> void:
	var s: ScrollContainer = _panel.find_child("SheetScroll", true, false)
	if s != null:
		s.scroll_vertical = int(s.get_v_scroll_bar().max_value)


func _no_cover() -> bool:
	var scroll: ScrollContainer = _panel.find_child("BodyScroll", true, false)
	for c: Node in scroll.get_parent().get_children():
		if c.has_meta("tvp_stock_sheet_cover") and not c.is_queued_for_deletion():
			return false
	return true


## No case's rim over another's: the sections stand apart and inside the body's view, clear of its rail;
## each rolling door stops inside its section's dark plate, clear of the frame's rim; the upgrade key's
## bezel stays clear of the strip under it; and no two wells of waiting shipments meet.
func _overlaps(tag: String) -> void:
	var Section := load("res://scripts/bdp_v3_section.gd")
	var Key := load("res://scripts/ds2/latch_key.gd")
	var Parts := load("res://scripts/tvp_v3/stock_parts.gd")
	var scroll: ScrollContainer = _panel.find_child("BodyScroll", true, false)
	var pane: Node = (_panel.get("_panes") as Dictionary).get("stock")
	var view := scroll.get_global_rect()
	var rail_x := scroll.get_v_scroll_bar().global_position.x if scroll.get_v_scroll_bar().visible else view.end.x
	var bad := PackedStringArray()
	var sections: Array = pane.find_children("*", "MarginContainer", true, false).filter(func(n: Node) -> bool:
		return n.get_script() == Section)
	for i in sections.size():
		var r := (sections[i] as Control).get_global_rect()
		if r.position.x < view.position.x - 0.5 or r.end.x > rail_x + 0.5:
			bad.append("%s past the view (%.0f to %.0f of %.0f to %.0f)" % [sections[i].name, r.position.x, r.end.x, view.position.x, rail_x])
		for j in range(i + 1, sections.size()):
			if r.intersects((sections[j] as Control).get_global_rect()):
				bad.append("%s meets %s" % [sections[i].name, sections[j].name])
	for door: Node in pane.find_children("BayDoor", "", true, false) + pane.find_children("IdleDoor", "", true, false):
		var d := (door as Control).get_global_rect()
		var reach := float(door.get("reach"))
		var sec: Node = door.get_parent()
		while sec != null and sec.get_script() != Section:
			sec = sec.get_parent()
		if sec != null:
			var inner := (sec as Control).get_global_rect().grow(-Section.RIM - 2.0)
			if d.position.x - reach < inner.position.x - 0.5 or d.end.x + reach > inner.end.x + 0.5:
				bad.append("%s's housing on %s's rim" % [door.name, sec.name])
	var key: Control = pane.find_child("UpgradeWarehouse", true, false)
	if key == null:
		key = pane.find_child("WarehouseMaxed", true, false)
	var strip: Control = pane.find_child("CapacityStrip", true, false)
	if key != null and strip != null and strip.global_position.y - key.get_global_rect().end.y < Key.KEY_INSET / Key.CAPTURE_SCALE - 1.0:
		bad.append("the key's bezel on the strip (%.1f px apart)" % (strip.global_position.y - key.get_global_rect().end.y))
	var wells: Array = []
	for row: Node in pane.find_children("OverflowShipment", "", true, false):
		wells.append((row.find_child("GoodInWell", true, false) as Control).get_global_rect())
	for i in range(1, wells.size()):
		if (wells[i] as Rect2).position.y - (wells[i - 1] as Rect2).end.y < 2.0 * Parts.SCREEN_RIM:
			bad.append("two waiting shipments' wells meet")
	_check(bad.is_empty(), "%s: no case's rim over another's (%s)" % [tag, "clear" if bad.is_empty() else "; ".join(bad)])

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
