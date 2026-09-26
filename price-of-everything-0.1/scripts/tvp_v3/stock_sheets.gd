extends RefCounted
## Tile view v3, the Stock tab: its two action sheets, each a worn steel plate that slides in over the tab's
## body as Building Detail's sheets do (docs/tile-view-ds2-plan.md §5, Phase 5; stock_parts.gd `sheet`).
##   Move or sell: the good picked in the bay or on the warehouse's bar, in its well with its quantity pill,
##   how many, where to (the market, a special order for it, or a tile picked on the map), once or every
##   turn, what that is worth (the sale after port charges, or the freight, a turn when it repeats), then
##   the key that does it; under it the good's standing order, selling all but a set amount every turn.
##   The panel keeps the choice (_stock_sel, _stock_qty, _stock_dest, _stock_recurring) and carries it out
##   (_confirm_stock_action), as v2 does.
##   Upgrade the warehouse: its capacity now and at the next level on a dot matrix, the materials the works
##   use with what you hold and what the market charges (MatchState.warehouse_upgrade_quote), and the two
##   ways to pay.

const Metrics := preload("res://scripts/ds2/metrics.gd")
const Parts := preload("res://scripts/tvp_v3/stock_parts.gd")
const Led := preload("res://scripts/bdp_v3_led.gd")
const Toggle := preload("res://scripts/bdp_v3_toggle.gd")
const Heading := preload("res://scripts/bdp_v3_heading.gd")
const CabinetKey := preload("res://scripts/ds2/latch_key.gd")

const MARKET_DEST := "__market__"
const SPECIAL_ORDER_DEST := "__special_order__"
const GOOD_PX := Metrics.GOOD_ICON
const MATERIAL_PX := Metrics.GOOD_ICON
## The destination keys' width, and the sheet's captions' column (three keys and the caption fit the
## narrowest body).
const DEST_KEY_W := 116.0
const CAPTION_W := 92.0


static func _refresh(panel: Control) -> void:
	panel.call_deferred("_refresh_pane", "stock")


## What already leaves this tile every turn for `good_id`: its standing order (sell all but a set amount,
## MatchState.auto_sell_goods), recurring sales (MatchState.recurring_sells) and recurring moves
## (TransportState.recurring_moves), as [{kind ("auto", "sell", "move"), text, entry, single}]; `single`
## when the recurring entry carries this good alone, so stopping it stops nothing else.
static func standing(tile: String, gid: String) -> Array:
	var out: Array = []
	if MatchState.is_auto_sell_good(tile, gid):
		out.append({"kind": "auto", "text": "Sells all but %d here" % MatchState.auto_sell_keep_for(tile, gid), "entry": {}, "single": true})
	for e: Dictionary in MatchState.recurring_sells:
		var goods: Dictionary = e.get("goods", {})
		if str(e.get("source", "")) == tile and goods.has(gid):
			out.append({"kind": "sell", "text": "Sells %d at the port" % int(goods[gid]), "entry": e, "single": goods.size() == 1})
	for e: Dictionary in TransportState.recurring_moves:
		var goods: Dictionary = e.get("goods", {})
		if str(e.get("source", "")) == tile and goods.has(gid):
			var dest := str(e.get("dest", ""))
			out.append({"kind": "move", "text": "Moves %d to %s" % [int(goods[gid]), Parts.tile_words(dest)], "entry": e,
				"single": goods.size() == 1, "dest": dest})
	return out


## The Move or sell sheet for the good the panel has picked. False when the good has gone from the tile
## (the pick is dropped and the tab shows instead).
static func move_or_sell(panel: Control, tile: String) -> bool:
	var sel: Dictionary = panel.get("_stock_sel")
	var gid := str(sel.get("good_id", ""))
	var good_name := str(sel.get("name", Catalog.get_display_name(gid)))
	var available := int(Stockpile.get_tile_totals(tile).get(gid, 0))
	if gid == "" or available <= 0:
		panel.set("_stock_sel", {})
		panel.set("_stock_dest", "")
		return false
	sel["qty"] = available
	var order: Dictionary = SpecialOrderState.get_active_order_for_good(gid)
	var dest := str(panel.get("_stock_dest"))
	if dest == SPECIAL_ORDER_DEST and order.is_empty():
		dest = ""
		panel.set("_stock_dest", "")
	var max_qty := available
	if dest == SPECIAL_ORDER_DEST:
		max_qty = mini(available, SpecialOrderState.remaining_uncommitted(order))
	var qty := clampi(int(panel.get("_stock_qty")), 1, maxi(1, max_qty))
	panel.set("_stock_qty", qty)
	var recurring := bool(panel.get("_stock_recurring")) and dest != SPECIAL_ORDER_DEST
	panel.set("_stock_recurring", recurring)

	var rows := Parts.sheet(panel, "move:" + gid, "StockGoodActions", "Move or sell %s" % good_name, func() -> void:
		panel.set("_stock_sel", {})
		panel.set("_stock_dest", "")
		panel.set("_stock_recurring", false)
		_refresh(panel))

	# The good in its well, how much of it is here on its quantity pill, as in the bay.
	var good := HBoxContainer.new()
	good.name = "SheetGood"
	good.add_theme_constant_override("separation", 14)
	good.add_child(Parts.good_in_well(gid, GOOD_PX, available, true))
	var here := Parts.metal("On this tile")
	here.tooltip_text = "%d %s on this tile" % [available, good_name]
	here.mouse_filter = Control.MOUSE_FILTER_PASS
	good.add_child(here)
	rows.add_child(good)

	# How many: typed on a screen, or All. The confirm key's words and the quote follow what is typed.
	var qty_row := Parts.sheet_row("Quantity", CAPTION_W)
	qty_row.name = "QuantityRow"
	var live := {"key": null, "quote": func(_q: int) -> void: pass}
	var entry := Parts.entry(qty, 1, maxi(1, max_qty), 96.0, func(v: int) -> void:
		panel.set("_stock_qty", v)
		if live.key != null and is_instance_valid(live.key):
			(live.key as Control).set("text", _confirm_text(dest, v, good_name, recurring))
		(live.quote as Callable).call(v))
	qty_row.add_child(entry)
	var all_key: Control = CabinetKey.new()
	all_key.name = "QuantityAll"
	all_key.text = "All"
	all_key.custom_minimum_size.x = 76.0
	all_key.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	all_key.tooltip_text = "All %d" % max_qty
	all_key.pressed.connect(func() -> void:
		panel.set("_stock_qty", maxi(1, max_qty))
		_refresh(panel))
	qty_row.add_child(all_key)
	rows.add_child(qty_row)

	# Where to: latching keys, the chosen one down.
	var dest_row := Parts.sheet_row("Send to", CAPTION_W)
	dest_row.name = "DestinationRow"
	var keys := HBoxContainer.new()
	keys.add_theme_constant_override("separation", 8)
	keys.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dest_row.add_child(keys)
	var market_key: Control = _dest_key("Market", "DestMarket", dest == MARKET_DEST)
	market_key.tooltip_text = "Sell on the global market through the nearest port"
	market_key.pressed.connect(func() -> void:
		panel.set("_stock_dest", MARKET_DEST)
		_refresh(panel))
	keys.add_child(market_key)
	if not order.is_empty():
		var special_key: Control = _dest_key("Special order", "DestSpecialOrder", dest == SPECIAL_ORDER_DEST)
		var remaining := SpecialOrderState.remaining_uncommitted(order)
		special_key.disabled = remaining <= 0
		special_key.tooltip_text = "This special order is already fully committed." if remaining <= 0 \
			else "Send to the special order for %s: %d more wanted" % [good_name, remaining]
		special_key.pressed.connect(func() -> void:
			panel.set("_stock_dest", SPECIAL_ORDER_DEST)
			panel.set("_stock_recurring", false)
			if remaining > 0:
				panel.set("_stock_qty", mini(int(panel.get("_stock_qty")), remaining))
			_refresh(panel))
		keys.add_child(special_key)
	var to_tile := dest != "" and dest != MARKET_DEST and dest != SPECIAL_ORDER_DEST
	var tile_key: Control = _dest_key("A tile", "DestTile", to_tile)
	tile_key.tooltip_text = "Pick a tile on the map to move it to"
	tile_key.pressed.connect(func() -> void:
		panel.emit_signal("pick_destination_requested")
		MatchState.request_toast("Pick a destination tile on the map", "caution"))
	keys.add_child(tile_key)
	rows.add_child(dest_row)
	if to_tile:
		var to_line := Parts.sheet_row("", CAPTION_W)
		to_line.name = "DestinationName"
		var to_name := Parts.body("To %s" % Parts.tile_words(dest, "the tile you picked"), true)
		to_name.tooltip_text = Parts.coords(dest)
		to_name.mouse_filter = Control.MOUSE_FILTER_PASS
		to_line.add_child(to_name)
		rows.add_child(to_line)

	# Once, or every turn: Building Detail's slide switch, its two sides named in raised letters.
	var repeat_row := Parts.sheet_row("Repeat", CAPTION_W)
	repeat_row.name = "RepeatRow"
	if dest == SPECIAL_ORDER_DEST:
		repeat_row.add_child(Parts.body("A special order goes once"))
	else:
		repeat_row.add_child(_switch("Once", "Every turn", recurring, func(right: bool) -> void:
			panel.set("_stock_recurring", right)
			_refresh(panel)))
	rows.add_child(repeat_row)

	# What it is worth, right over the key that does it.
	var quote := _quote(tile, gid, dest, order, recurring)
	if quote.row != null:
		rows.add_child(quote.row)
		live.quote = quote.update
		(quote.update as Callable).call(qty)

	# The key that does it, saying what it will do.
	var go: Control = CabinetKey.new()
	go.name = "ConfirmStockAction"
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	go.text = _confirm_text(dest, qty, good_name, recurring)
	live.key = go
	var fully_committed := dest == SPECIAL_ORDER_DEST and (order.is_empty() or SpecialOrderState.remaining_uncommitted(order) <= 0)
	go.disabled = dest == "" or fully_committed or str(quote.blocked) != ""
	if str(quote.blocked) != "":
		go.tooltip_text = str(quote.blocked)
	go.pressed.connect(func() -> void: panel.call_deferred("_confirm_stock_action"))
	rows.add_child(go)

	rows.add_child(_rule())

	# What already goes every turn, each with its Stop beside it (the standing order below has its own switch).
	var recurring_rows: Array = standing(tile, gid).filter(func(r: Dictionary) -> bool: return str(r.kind) != "auto")
	if not recurring_rows.is_empty():
		var every := VBoxContainer.new()
		every.name = "EveryTurn"
		every.add_theme_constant_override("separation", 8)
		var ev_head := HBoxContainer.new()
		ev_head.add_child(Parts.heading("Every turn"))
		every.add_child(ev_head)
		for r: Dictionary in recurring_rows:
			every.add_child(_recurring_row(panel, r))
		rows.add_child(every)
		rows.add_child(_rule())

	# The good's standing order: sell all but a set amount here, every turn. It applies the moment it is on.
	var standing := VBoxContainer.new()
	standing.name = "StandingOrder"
	standing.add_theme_constant_override("separation", 8)
	var st_head := HBoxContainer.new()
	st_head.add_child(Parts.heading("Standing order"))
	standing.add_child(st_head)
	standing.add_child(Parts.para("Every turn, sell all %s here except the amount you keep. Inputs this tile's buildings need are always kept on top." % good_name))
	var keep_row := Parts.sheet_row("Keep", CAPTION_W)
	var on := MatchState.is_auto_sell_good(tile, gid)
	var keep_now := MatchState.auto_sell_keep_for(tile, gid)
	var keep_entry := Parts.entry(keep_now, 0, 999999, 96.0, func(v: int) -> void:
		MatchState.set_auto_sell_keep(tile, gid, v))
	keep_row.add_child(keep_entry)
	keep_row.add_child(Parts.spacer())
	keep_row.add_child(_switch("Off", "On", on, func(right: bool) -> void:
		var field := keep_entry.find_child("Entry", true, false) as LineEdit
		var keep := field.text.to_int() if field != null else 0
		if right:
			MatchState.enable_auto_sell_good(tile, gid)
			MatchState.set_auto_sell_keep(tile, gid, keep)
			MatchState.request_toast("Selling all %s above %d every turn" % [good_name, keep], "success")
		else:
			MatchState.disable_auto_sell_good(tile, gid)
			MatchState.set_auto_sell_keep(tile, gid, 0)))
	standing.add_child(keep_row)
	rows.add_child(standing)
	return true


## A recurring sale or move of this good: what it does, and Stop beside it. An entry that carries other goods
## too is stopped from the Market panel, so it says so instead of offering a Stop that would end them all.
static func _recurring_row(panel: Control, r: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Recurring_%s" % str(r.kind).capitalize()
	row.add_theme_constant_override("separation", 10)
	row.add_child(Parts.raised_icon("res://assets/ui/bdp_v3/diag_icon_%s.png" % ("port" if str(r.kind) == "sell" else "route"), 24.0))
	var words := Parts.para(str(r.text))
	if r.has("dest"):
		words.tooltip_text = Parts.coords(str(r.dest))
		words.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(words)
	if bool(r.single):
		var stop: Control = CabinetKey.new()
		stop.name = "StopRecurring"
		stop.text = "Stop"
		stop.custom_minimum_size.x = 96.0
		stop.size_flags_horizontal = Control.SIZE_SHRINK_END
		stop.tooltip_text = "Stop this every turn"
		var entry: Dictionary = r.entry
		var kind := str(r.kind)
		stop.pressed.connect(func() -> void:
			if kind == "sell":
				MatchState.remove_recurring_sell(entry)
			else:
				TransportState.remove_recurring_move(entry)
			_refresh(panel))
		row.add_child(stop)
	else:
		var elsewhere := Parts.metal("Stop it in the Market panel", HORIZONTAL_ALIGNMENT_RIGHT)
		elsewhere.tooltip_text = "It sells or moves other goods too"
		elsewhere.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(elsewhere)
	return row


## What the chosen destination is worth for `qty`, quoted by the engine's own helpers and redone as the
## quantity is typed:
##   the market: the sale price (MarketState.get_sale_price) less the port's charges
##     (MarketState.sale_charges, previewed), the sum MarketState.execute_sale moves;
##   a special order: the order's price (the market price with its uplifts, as execute_sale prices an
##     order) less the port's charges, and the order's bonus when it is filled;
##   a tile: the freight (TransportService.transport_cost_for_route with queue_move's large shipment
##     surcharge) and the turns it takes.
## Repeating every turn, the figure is a turn's, at today's price, and the words say so.
## {row (null with no destination), update: Callable(qty), blocked: why the key can't go, or ""}.
static func _quote(tile: String, gid: String, dest: String, order: Dictionary, recurring := false) -> Dictionary:
	var none := {"row": null, "update": func(_q: int) -> void: pass, "blocked": ""}
	if dest == "":
		return none
	var selling := dest == MARKET_DEST or dest == SPECIAL_ORDER_DEST
	var route := TransportService.route_to_nearest_port(tile, gid) if selling else TransportService.route(tile, dest, gid)
	var port := str(route.get("port", ""))
	var row := Parts.sheet_row("You get" if selling else "Freight", CAPTION_W)
	row.name = "QuoteRow"
	if (selling and port == "") or not TransportService.route_is_reachable(route):
		var why := "No route to a port from here" if selling else "No route from here to that tile"
		row.add_child(Parts.lamp("bad"))
		row.add_child(Parts.body(why))
		return {"row": row, "update": none.update, "blocked": why}
	var money := Parts.money(0.0, DS.PALETTE.OK)
	var screen: Control = money.get_child(1)
	row.add_child(money)
	var words := Parts.para("")
	words.name = "QuoteDetail"
	row.add_child(words)
	var turns := int(route.get("turns", 0))
	var ctx := {"good_id": gid, "good_internal": Catalog.get_internal_name(gid)}
	var update: Callable
	if selling:
		var special := dest == SPECIAL_ORDER_DEST
		var unit := Modifiers.apply("market_price", gid, MarketState.get_price(gid), ctx) if special \
			else MarketState.get_sale_price(gid, ctx)
		var bonus := roundi(float(order.get("premium_pct", 0.0)) * 100.0)
		update = func(q: int) -> void:
			var charges: Dictionary = MarketState.sale_charges(port, route, [{"good_id": gid, "qty": q}], false, false)
			var fees := float(charges.get("transport_cost", 0.0))
			var net := float(q) * unit - fees
			screen.call("set_figure", "%.2f" % net, DS.PALETTE.OK if net >= 0.0 else DS.PALETTE.DANGER)
			var said := ("after £%.2f port charges" % fees) if fees > 0.005 else "no port charges"
			if recurring:
				said = "/turn, " + said
			else:
				said += (", ships in %d turn%s" % [turns, "" if turns == 1 else "s"]) if turns > 0 else ", sold now"
			if special and bonus > 0:
				said += ", plus a %d%% bonus when the order is filled" % bonus
			words.text = said
			words.tooltip_text = ("%d/turn at today's price, £%.2f each" if recurring else "%d at £%.2f each") % [q, unit]
	else:
		update = func(q: int) -> void:
			var surcharge := TransportState.LARGE_SHIPMENT_SURCHARGE if q > TransportState.LARGE_SHIPMENT_THRESHOLD else 1.0
			var cost := TransportService.transport_cost_for_route(gid, q, route, surcharge)
			screen.call("set_figure", "%.2f" % cost, DS.PALETTE.DANGER)
			var said := "arrives in %d turn%s" % [turns, "" if turns == 1 else "s"]
			if recurring:
				said = "/turn, each " + said
			if surcharge > 1.0:
				said += ", double rate over %d units" % TransportState.LARGE_SHIPMENT_THRESHOLD
			words.text = said
	words.mouse_filter = Control.MOUSE_FILTER_PASS
	return {"row": row, "update": update, "blocked": ""}


## What the tile would hold with its warehouse at `level`: that level's own room, the storage the tile's
## buildings add (the port's 600) and the capacity modifiers, added up as Stockpile.get_capacity does.
static func capacity_at(tile: String, level: int) -> int:
	var base := int(EconomyConfig.WAREHOUSE_STORAGE_CAP.get(level, Stockpile.TILE_CAPACITY))
	var boost := 0
	for iid in BuildingState.tile_buildings.get(tile, []):
		var bd: Dictionary = Catalog.get_building(str(BuildingState.get_building(str(iid)).get("building_id", "")))
		boost += int(bd.get("storage_boost", 0))
	return int(round(Modifiers.apply("stockpile_capacity", tile, float(base + boost), {"tile_id": tile})))


## A capacity now and after an upgrade, as the dot matrix shows it: "1400 → 2200".
static func capacity_change(now: int, after: int) -> String:
	return "%d → %d" % [now, after]


## The warehouse's upgrade sheet: its capacity now and at the next level, the bill of materials and the two
## ways to pay, with why a way is shut when it is.
static func expand(panel: Control, tile: String) -> void:
	var quote: Dictionary = MatchState.warehouse_upgrade_quote(tile)
	var level := int(quote.get("level", 1))
	var next_level := int(quote.get("next_level", level + 1))
	var rows := Parts.sheet(panel, "expand", "WarehouseExpansion", "Upgrade to Lvl%d" % next_level, func() -> void:
		panel.set("_warehouse_expand", false)
		_refresh(panel))
	var now := Stockpile.get_capacity(tile)
	var after := capacity_at(tile, next_level)

	# The capacity now and after, on a dot matrix, as the strip under the upgrade key.
	var holds := Parts.sheet_row("Capacity", CAPTION_W)
	holds.name = "HoldsRow"
	var shown := Parts.dots(capacity_change(now, after))
	shown.name = "CapacityDots"
	holds.add_child(shown)
	rows.add_child(holds)
	rows.add_child(Parts.para("Level %d to level %d adds %d units of storage. The works use these materials." % [level, next_level, after - now]))

	var materials: Array = quote.get("materials", [])
	var cost_digits := 0
	for m: Dictionary in materials:
		cost_digits = maxi(cost_digits, Led.cells_for("%.2f" % float(m.get("market_cost", 0.0))).size())
	var bill := VBoxContainer.new()
	bill.name = "MaterialsBill"
	bill.add_theme_constant_override("separation", 16)
	var short: Array = []
	for m: Dictionary in materials:
		var good_id := str(m.get("good_id", ""))
		var need := int(m.get("qty", 0))
		var have := int(m.get("have_empire", 0))
		if have < need:
			short.append(Catalog.get_display_name(good_id))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.add_child(Parts.good_in_well(good_id, MATERIAL_PX, need, true))
		var names := VBoxContainer.new()
		names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		names.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		names.add_theme_constant_override("separation", 0)
		var title := Parts.body(Catalog.get_display_name(good_id), true)
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		title.clip_text = true
		title.custom_minimum_size.x = 120.0
		names.add_child(title)
		# What you hold across your tiles: white words, the lamp says whether it is enough.
		var held_row := HBoxContainer.new()
		held_row.add_theme_constant_override("separation", 6)
		held_row.add_child(Parts.lamp("ok" if have >= need else "bad", 0.5))
		held_row.add_child(Parts.body("You have %d" % have))
		names.add_child(held_row)
		row.add_child(names)
		row.add_child(Parts.money(float(m.get("market_cost", 0.0)), DS.PALETTE.DANGER, cost_digits))
		bill.add_child(row)
	rows.add_child(bill)
	rows.add_child(_rule())
	var pay := HBoxContainer.new()
	pay.name = "PayKeys"
	pay.add_theme_constant_override("separation", 10)
	var total := float(quote.get("market_total", 0.0))
	var market: Control = CabinetKey.new()
	market.name = "ExpandFromMarket"
	market.text = "Buy from market £%s" % _whole(total)
	market.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	market.disabled = not bool(quote.get("money_ok", false))
	market.tooltip_text = ("Not enough cash, £%s needed" % _whole(total)) if market.disabled \
		else "Materials bought at the market's price with freight to this tile"
	market.pressed.connect(func() -> void: panel.call_deferred("_commit_warehouse_upgrade", "market"))
	pay.add_child(market)
	var stock: Control = CabinetKey.new()
	stock.name = "ExpandFromStock"
	stock.text = "Use your stock"
	stock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stock.disabled = not bool(quote.get("empire_ok", false))
	stock.tooltip_text = "Takes the materials from goods already on your tiles"
	stock.pressed.connect(func() -> void: panel.call_deferred("_commit_warehouse_upgrade", "empire"))
	pay.add_child(stock)
	rows.add_child(pay)
	# Why a way to pay is shut, on the sheet rather than only on hover.
	var why := PackedStringArray()
	if market.disabled:
		why.append("Buying needs £%s, more than your cash." % _whole(total))
	if stock.disabled and not short.is_empty():
		why.append("Using your stock needs more %s across your tiles." % _and_list(short))
	if not why.is_empty():
		var note := Parts.para(" ".join(why))
		note.name = "PayNote"
		rows.add_child(note)


## "a", "a and b", "a, b and c".
static func _and_list(names: Array) -> String:
	if names.size() <= 1:
		return "" if names.is_empty() else str(names[0])
	var head := PackedStringArray()
	for i in names.size() - 1:
		head.append(str(names[i]))
	return "%s and %s" % [", ".join(head), str(names[names.size() - 1])]


## What the confirm key will do, in its own words.
static func _confirm_text(dest: String, qty: int, good_name: String, recurring: bool) -> String:
	var what := ""
	match dest:
		"":
			return "Choose where to send it"
		MARKET_DEST:
			what = "Sell %d %s" % [qty, good_name]
		SPECIAL_ORDER_DEST:
			what = "Send %d %s to the order" % [qty, good_name]
		_:
			what = "Move %d %s" % [qty, good_name]
	return what + (" every turn" if recurring else "")


static func _whole(v: float) -> String:
	var s := str(roundi(v))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out


static func _dest_key(text: String, node_name: String, chosen: bool) -> Control:
	var key: Control = CabinetKey.new()
	key.name = node_name
	key.text = text
	key.latched = chosen
	key.custom_minimum_size.x = DEST_KEY_W
	key.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return key


## Building Detail's slide switch with its two sides named in raised letters (the diagnostics' VISUAL and
## TEXT), thrown to the right when `right`.
static func _switch(left_name: String, right_name: String, right: bool, toggled: Callable) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.name = "Switch"
	hb.add_theme_constant_override("separation", 8)
	hb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(Parts.heading(left_name))
	var sw: Control = Toggle.new()
	sw.set_right(right)
	sw.toggled.connect(toggled)
	hb.add_child(sw)
	hb.add_child(Parts.heading(right_name))
	return hb


## A thin engraved line across a sheet.
static func _rule() -> Control:
	var line := Control.new()
	line.custom_minimum_size.y = 4.0
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.draw.connect(func() -> void:
		var y := line.size.y * 0.5
		line.draw_line(Vector2(0.0, y), Vector2(line.size.x, y), Color(0, 0, 0, 0.45), 1.0)
		line.draw_line(Vector2(0.0, y + 1.0), Vector2(line.size.x, y + 1.0), Color(1, 1, 1, 0.18), 1.0))
	return line
