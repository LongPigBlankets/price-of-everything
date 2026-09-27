extends RefCounted
## DS2 market, the order book tabs:
##   Orders     Special Orders: a ticket per active order, the good in its well with the target on its pill, the
##              units delivered against the target on an LED meter, the turns left on a drum, the premium, and
##              the bonus it pays when filled (SpecialOrderState.premium_quote at MarketRules.order_price).
##   Recurring  every standing order in one list, sales, bulk sales, buys and moves (decision 12), each with
##              Cancel (MatchState.remove_recurring_order).
##   History    the blotter: every one off buy, sale and move, newest first, with its value
##              (MarketRules.blotter). HISTORY_PAGE lines at a time.

const MarketRules := preload("res://scripts/market_rules.gd")
const MParts := preload("res://scripts/market_ds2/parts.gd")
const Parts := preload("res://scripts/tvp_v3/buildings_parts.gd")
const LedgerV3 := preload("res://scripts/ledger_v3/ledger_v3.gd")
const Metrics := preload("res://scripts/ds2/metrics.gd")
const LedMeter := preload("res://scripts/ds2/led_meter.gd")
const Drum := preload("res://scripts/ds2/drum_figure.gd")
const CreamKey := preload("res://scripts/ds2/cream_key.gd")


## A headed table: the headings over a plastic case in a scroll. `columns` [[heading, width]].
static func table(owner: VBoxContainer, columns: Array, gap: int) -> VBoxContainer:
	owner.add_theme_constant_override("separation", 10)
	var wrap := MarginContainer.new()
	wrap.name = "Headings"
	var left := roundi(Parts.case_margin() + Parts.PAD.x)
	wrap.add_theme_constant_override("margin_left", left)
	wrap.add_theme_constant_override("margin_right", left)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", gap)
	wrap.add_child(row)
	for col: Array in columns:
		var l := Parts.caption(str(col[0]), Parts.CAPTION_PX, HORIZONTAL_ALIGNMENT_CENTER)
		l.custom_minimum_size.x = float(col[1])
		row.add_child(l)
	owner.add_child(wrap)
	var t := LedgerV3.table()
	owner.add_child(t.scroll)
	return t.rows


static func clear(rows: VBoxContainer) -> void:
	for c in rows.get_children():
		rows.remove_child(c)
		c.queue_free()


static func words(text: String, w: float, semibold := false) -> Label:
	var l := Parts.body(text)
	l.custom_minimum_size.x = w
	l.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if semibold:
		l.add_theme_font_override("font", Parts.FONT_TITLE)
	return l


static func two_lines(top: String, under: String, w: float) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.custom_minimum_size.x = w
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var a := words(top, w, true)
	a.name = "Top"
	col.add_child(a)
	if under != "":
		var b := words(under, w)
		b.name = "Under"
		col.add_child(b)
	return col


static func empty_line(rows: VBoxContainer, text: String) -> void:
	var l := Parts.body(text)
	l.name = "Empty"
	rows.add_child(l)


class Orders extends VBoxContainer:
	static func BookTabs() -> GDScript:
		return load("res://scripts/market_ds2/book_tabs.gd")

	const GAP := 8
	const COLUMNS := [["", 72.0], ["Order", 170.0], ["Delivered", 170.0], ["Turns left", 76.0], ["Premium", 64.0], ["Bonus", 0.0]]
	var _rows: VBoxContainer

	func _init() -> void:
		var cols := COLUMNS.duplicate(true)
		cols[5][1] = MParts.money_width(MParts.MONEY_CELLS, true)
		_rows = BookTabs().table(self, cols, GAP)

	func refresh() -> void:
		BookTabs().clear(_rows)
		var orders: Array = SpecialOrderState.get_active_orders()
		orders.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return int(a.get("expires_turn", 0)) < int(b.get("expires_turn", 0)))
		if orders.is_empty():
			BookTabs().empty_line(_rows, "No special orders open.")
		for o: Dictionary in orders:
			_rows.add_child(ticket(o))

	func ticket(o: Dictionary) -> PanelContainer:
		var gid := str(o.get("good_id", ""))
		var m := Parts.module("Order_%s" % str(o.get("id", gid)))
		m.custom_minimum_size.y = Metrics.CARD_H
		var line := Parts.row_of(m)
		line.add_theme_constant_override("separation", GAP)
		var target := int(o.get("qty_required", 0))
		var delivered := int(o.get("qty_delivered", 0))
		var committed := int(o.get("qty_committed", 0))
		line.add_child(LedgerV3._boxed(Parts.good_in_well(gid, target, "Target %d" % target, true, Metrics.GOOD_ICON), 72.0))
		var due := int(o.get("expires_turn", 0))
		line.add_child(BookTabs().two_lines(Catalog.get_display_name(gid), "Due turn %d" % due, 170.0))
		var meter_col := VBoxContainer.new()
		meter_col.custom_minimum_size.x = 170.0
		meter_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		meter_col.add_theme_constant_override("separation", 3)
		var meter: Control = LedMeter.new()
		meter.name = "DeliveredMeter"
		meter.call("set_load", float(delivered), float(maxi(1, target)), 0.999, "ok" if delivered >= target else "warn")
		meter_col.add_child(meter)
		var said: Label = BookTabs().words("%d of %d, %d committed" % [delivered, target, committed], 170.0)
		said.name = "Delivered"
		meter_col.add_child(said)
		line.add_child(meter_col)
		var left := maxi(0, due - int(TurnManager.current_turn))
		var drum_box := LedgerV3._boxed(Drum.new(Drum.led_height(), 2, left), 76.0)
		drum_box.name = "TurnsLeft"
		line.add_child(drum_box)
		var premium: Label = BookTabs().words("+%d%%" % roundi(float(o.get("premium_pct", 0.0)) * 100.0), 64.0)
		premium.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		line.add_child(premium)
		var bonus := SpecialOrderState.premium_quote(o, MarketRules.order_price(gid))
		var box := LedgerV3._boxed(MParts.money(bonus, DS.PALETTE["OK"], MParts.MONEY_CELLS, true), MParts.money_width(MParts.MONEY_CELLS, true))
		box.name = "Bonus"
		line.add_child(box)
		m.tooltip_text = "Deliver from the tile view or the building's panel."
		return m


class Recurring extends VBoxContainer:
	static func BookTabs() -> GDScript:
		return load("res://scripts/market_ds2/book_tabs.gd")

	const GAP := 10
	const COLUMNS := [["", 72.0], ["Order", 260.0], ["From", 150.0], ["Since", 70.0], ["", 110.0]]
	var _rows: VBoxContainer

	func _init() -> void:
		_rows = BookTabs().table(self, COLUMNS, GAP)
		MatchState.recurring_orders_changed.connect(func() -> void:
			if is_visible_in_tree():
				refresh())

	func refresh() -> void:
		BookTabs().clear(_rows)
		var orders := MarketRules.standing_orders()
		if orders.is_empty():
			BookTabs().empty_line(_rows, "No recurring orders. Set one up from a good's Sell key, or from the tile view.")
		var i := 0
		for r: Dictionary in orders:
			_rows.add_child(order_row(r, i))
			i += 1

	## What an order does, in words, and where its goods go.
	static func describe(r: Dictionary) -> Dictionary:
		var entry: Dictionary = r.get("entry", {})
		var qty := int(r.get("qty", 0))
		match str(r.get("sub", "")):
			"sell":
				return {"what": "Sell %d a turn" % qty, "to": "To the market", "from": MarketRules.place_name(str(entry.get("source", "")))}
			"bulk":
				var p: Dictionary = entry.get("params", {})
				var tiles: Array = p.get("tiles", [])
				var from := "Every place" if tiles.is_empty() else (MarketRules.place_name(str(tiles[0])) if tiles.size() == 1 else "%d places" % tiles.size())
				var what := "Sell everything"
				if int(p.get("per_tile_max", 0)) > 0:
					what = "Sell up to %d a turn from each" % int(p.get("per_tile_max", 0))
				elif int(p.get("per_tile_keep", 0)) > 0:
					what = "Sell all but %d on each" % int(p.get("per_tile_keep", 0))
				return {"what": what, "to": "To the market", "from": from}
			"buy":
				return {"what": "Buy %d a turn" % qty, "to": "To %s" % MarketRules.place_name(str(entry.get("dest", ""))), "from": "The market"}
			"move":
				return {"what": "Move %d a turn" % qty, "to": "To %s" % MarketRules.place_name(str(entry.get("dest", ""))),
					"from": MarketRules.place_name(str(entry.get("source", "")))}
		return {"what": "", "to": "", "from": ""}

	func order_row(r: Dictionary, i: int) -> PanelContainer:
		var m := Parts.module("Standing_%d" % i)
		m.custom_minimum_size.y = Metrics.CARD_H
		var line := Parts.row_of(m)
		line.add_theme_constant_override("separation", GAP)
		var gid := str(r.get("good_id", ""))
		if gid == "":
			var entry: Dictionary = r.get("entry", {})
			gid = str(entry.get("good", (entry.get("params", {}) as Dictionary).get("good_id", "")))
			if gid == "":
				var goods: Dictionary = entry.get("goods", {})
				gid = str(goods.keys()[0]) if not goods.is_empty() else ""
		if gid != "":
			line.add_child(LedgerV3._boxed(Parts.good_in_well(gid, -1, Catalog.get_display_name(gid), true, Metrics.GOOD_ICON), 72.0))
		else:
			line.add_child(Parts.spacer(72.0, 0))
		var d := describe(r)
		var name := str(r.get("good", "")) if gid == "" else Catalog.get_display_name(gid)
		line.add_child(BookTabs().two_lines("%s: %s" % [name, str(d.what)], str(d.to), 260.0))
		line.add_child(BookTabs().words(str(d.from), 150.0))
		var since: Label = BookTabs().words("Turn %d" % int(r.get("turn_started", 0)), 70.0)
		since.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		line.add_child(since)
		var cancel: Button = CreamKey.make("CancelRecurring", "Cancel", "", 110.0, false, false, 0.8)
		var sub := str(r.get("sub", ""))
		var entry2: Dictionary = r.get("entry", {})
		cancel.pressed.connect(func() -> void:
			if MatchState.remove_recurring_order(sub, entry2):
				MatchState.request_toast("Recurring order cancelled", "success")
				refresh())
		line.add_child(LedgerV3._boxed(cancel, 110.0))
		m.set_meta("sub", sub)
		return m


class History extends VBoxContainer:
	static func BookTabs() -> GDScript:
		return load("res://scripts/market_ds2/book_tabs.gd")

	const GAP := 6
	const PAGE := 60
	const COLUMNS := [["", 44.0], ["Good", 130.0], ["Units", 50.0], ["From", 130.0], ["To", 130.0], ["Value", 0.0], ["Turn", 48.0]]
	var _rows: VBoxContainer
	var _limit := PAGE

	func _init() -> void:
		var cols := COLUMNS.duplicate(true)
		cols[5][1] = MParts.money_width(MParts.MONEY_CELLS, true)
		_rows = BookTabs().table(self, cols, GAP)

	func refresh() -> void:
		BookTabs().clear(_rows)
		var rows := MarketRules.blotter()
		if rows.is_empty():
			BookTabs().empty_line(_rows, "Nothing bought, sold or moved yet.")
		for i in mini(_limit, rows.size()):
			_rows.add_child(line(rows[i], i))
		if rows.size() > _limit:
			var more := Parts.key_button("Show %d more" % mini(PAGE, rows.size() - _limit), "ShowMore", 0.8)
			more.pressed.connect(func() -> void:
				_limit += PAGE
				refresh())
			_rows.add_child(more)

	func line(r: Dictionary, i: int) -> PanelContainer:
		var m := Parts.module("Trade_%d" % i, true)
		m.custom_minimum_size.y = 0
		var row := Parts.row_of(m)
		row.custom_minimum_size.y = 0
		row.add_theme_constant_override("separation", GAP)
		row.add_child(BookTabs().words(str(r.get("type", "")), 44.0, true))
		row.add_child(BookTabs().words(str(r.get("good", "")), 130.0))
		var q: Label = BookTabs().words(str(int(r.get("qty", 0))), 50.0)
		q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(q)
		row.add_child(BookTabs().words(_place(str(r.get("from", ""))), 130.0))
		row.add_child(BookTabs().words(_place(str(r.get("to", ""))), 130.0))
		var value := float(r.get("value", -1.0))
		var w := MParts.money_width(MParts.MONEY_CELLS, true)
		if value >= 0.0:
			var ink := DS.PALETTE["OK"] if str(r.get("type", "")) == "Sell" else DS.PALETTE["DANGER"]
			var box := LedgerV3._boxed(MParts.money(value, ink, MParts.MONEY_CELLS, true), w)
			box.name = "Value"
			row.add_child(box)
		else:
			row.add_child(Parts.spacer(w, 0))
		var t: Label = BookTabs().words(str(int(r.get("turn_started", 0))), 48.0)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(t)
		return m

	## A ledger label ("Stoneshore Docks - (5, 10)") as a place name, without its coordinates.
	static func _place(label: String) -> String:
		var cut := label.find(" - (")
		return label.substr(0, cut) if cut > 0 else label

