extends RefCounted
## The sell panel's DS2 look (scripts/market_sell_panel.gd): a sheet of the panel's navy steel over the
## market, as a sell ticket:
##   the raised title (Sell Coal) and the Back key;
##   on the key bed, the quantity keys (All, All but X, Only X) with X on a screen, and One off or Recurring;
##   a module a place: a latching Sell key (down while the place is chosen; All over them chooses every place),
##     the place's name over what it holds and makes, then the units, the revenue, the charges and the net on
##     LED screens after a printed £;
##   the totals on a module of their own, a line on when the money comes, and the guarded Confirm sale key.
## Behaviour is the panel's; this only draws it.

const MarketRules := preload("res://scripts/market_rules.gd")
const MParts := preload("res://scripts/market_ds2/parts.gd")
const Parts := preload("res://scripts/ds2/parts.gd")
const LedgerV3 := preload("res://scripts/ledger_v3/ledger_v3.gd")
const LatchKey := preload("res://scripts/ds2/latch_key.gd")
const GuardKey := preload("res://scripts/ds2/guard_key.gd")
const Nine := preload("res://scripts/bdp_v3_nine.gd")
const Title := preload("res://scripts/bdp_v3_title.gd")
const Key := preload("res://scripts/bdp_v3_key.gd")

const GAP := 6
const TICK_W := 74.0
const PLACE_W := 170.0
const UNITS_W := 48.0
const GUARD_PX := 46.0
const MODES := [["all", "All"], ["all_but", "All but X"], ["only", "Only X"]]

var _panel: Control
var _title: Control
var _mode_keys: Dictionary = {}
var _once: Control
var _recurring: Control
var _qty: LineEdit
var _all: Control
var _rows: VBoxContainer
var _total: HBoxContainer
var _note: Label
var _guard: Control
var _guard_label: Label


static func money_w() -> float:
	return MParts.money_width(MParts.MONEY_CELLS, true)


func build(panel: Control) -> void:
	_panel = panel
	var bg := StyleBoxFlat.new()
	bg.bg_color = DS.PALETTE["BG_PANEL"]
	bg.set_corner_radius_all(10)
	bg.set_content_margin_all(0)
	panel.add_theme_stylebox_override("panel", bg)
	var backing: Control = Nine.make("panel_backing", LedgerV3.BACKING_CORNER)
	backing.name = "SellBacking"
	panel.add_child(backing)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, LedgerV3.CONTENT_MARGIN)
	panel.add_child(margin)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	margin.add_child(body)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	_title = Title.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(_title)
	var back: TextureButton = Key.make("back", Title.line_height())
	back.name = "CloseSell"
	back.pressed.connect(func() -> void: panel.call("close"))
	head.add_child(back)
	body.add_child(head)

	body.add_child(_controls(panel))
	body.add_child(LedgerV3.seam())
	body.add_child(_headings(panel))
	var t := LedgerV3.table()
	t.scroll.name = "SellScroll"
	_rows = t.rows
	body.add_child(t.scroll)

	_total = HBoxContainer.new()
	_total.name = "SellTotal"
	_total.add_theme_constant_override("separation", GAP)
	var total_wrap := MarginContainer.new()
	var inset := roundi(Parts.case_margin() + Parts.PAD.x)
	total_wrap.add_theme_constant_override("margin_left", inset)
	total_wrap.add_theme_constant_override("margin_right", inset)
	total_wrap.add_child(_total)
	body.add_child(total_wrap)
	_note = Parts.body("")
	_note.name = "SellNote"
	body.add_child(_note)

	var confirm := HBoxContainer.new()
	confirm.alignment = BoxContainer.ALIGNMENT_END
	confirm.add_theme_constant_override("separation", 14)
	_guard_label = Parts.caption("Confirm sale", 18)
	confirm.add_child(_guard_label)
	_guard = GuardKey.new(GUARD_PX)
	_guard.name = "ConfirmSale"
	_guard.connect("pressed", func() -> void: panel.call("confirm"))
	var holder := MarginContainer.new()
	holder.add_theme_constant_override("margin_top", ceili(GuardKey.overhang(GUARD_PX)))
	holder.add_child(_guard)
	confirm.add_child(holder)
	body.add_child(confirm)


func _controls(panel: Control) -> PanelContainer:
	var bed := PanelContainer.new()
	bed.name = "SellKeys"
	var pad := StyleBoxEmpty.new()
	pad.set_content_margin_all(10)
	bed.add_theme_stylebox_override("panel", pad)
	bed.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	bed.draw.connect(func() -> void:
		Nine.paint(bed, LedgerV3.KEYBED, Rect2(Vector2.ZERO, bed.size).grow(LedgerV3.KEYBED_MARGIN / LedgerV3.LAYOUT),
			(LedgerV3.KEYBED_MARGIN + LedgerV3.KEYBED_CORNER) * LedgerV3.TEXELS))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	bed.add_child(line)
	for spec: Array in MODES:
		var m := str(spec[0])
		var key: Control = LatchKey.new()
		key.name = "Mode_%s" % m
		key.set("text", str(spec[1]))
		key.custom_minimum_size.x = 104.0
		key.connect("pressed", func() -> void: panel.call("set_mode", m))
		line.add_child(key)
		_mode_keys[m] = key
	var screen: Control = LedgerV3._search_screen(func(t: String) -> void:
		var digits := ""
		for ch in t:
			if ch >= "0" and ch <= "9":
				digits += ch
		if digits != t:
			_qty.text = digits
			_qty.caret_column = digits.length()
		panel.call("set_qty", int(digits) if digits != "" else 0))
	screen.name = "QtyScreen"
	screen.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_qty = screen.get_meta("edit")
	_qty.name = "SellQty"
	_qty.placeholder_text = "X"
	_qty.clear_button_enabled = false
	_qty.custom_minimum_size.x = 76.0
	line.add_child(screen)
	var spring := Control.new()
	spring.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(spring)
	_once = LatchKey.new()
	_once.name = "OneOff"
	_once.set("text", "One off")
	_once.custom_minimum_size.x = 104.0
	_once.connect("pressed", func() -> void: panel.call("set_recurring", false))
	line.add_child(_once)
	_recurring = LatchKey.new()
	_recurring.name = "Recurring"
	_recurring.set("text", "Recurring")
	_recurring.custom_minimum_size.x = 104.0
	_recurring.connect("pressed", func() -> void: panel.call("set_recurring", true))
	line.add_child(_recurring)
	return bed


func _headings(panel: Control) -> MarginContainer:
	var wrap := MarginContainer.new()
	var inset := roundi(Parts.case_margin() + Parts.PAD.x)
	wrap.add_theme_constant_override("margin_left", inset)
	wrap.add_theme_constant_override("margin_right", inset)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", GAP)
	wrap.add_child(row)
	_all = LatchKey.new()
	_all.name = "SelectAll"
	_all.set("text", "All")
	_all.custom_minimum_size.x = TICK_W
	_all.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_all.connect("pressed", func() -> void:
		var every: bool = panel.call("selected_tiles").size() == (panel.get("sources") as Array).size()
		panel.call("set_all_selected", not every))
	row.add_child(_all)
	for spec: Array in [["Place", PLACE_W], ["Units", UNITS_W], ["Revenue", money_w()], ["Charges", money_w()], ["Net", money_w()]]:
		var l := Parts.caption(str(spec[0]), Parts.CAPTION_PX, HORIZONTAL_ALIGNMENT_CENTER)
		l.custom_minimum_size.x = float(spec[1])
		row.add_child(l)
	return wrap


func sync(panel: Control) -> void:
	var mode := str(panel.get("mode"))
	for m in _mode_keys:
		_mode_keys[m].set("latched", m == mode)
	var recurring := bool(panel.get("recurring"))
	_once.set("latched", not recurring)
	_recurring.set("latched", recurring)
	_qty.editable = mode != MarketRules.MODE_ALL
	var q := int(panel.get("qty"))
	var want := str(q) if q > 0 else ""
	if _qty.text != want:
		_qty.text = want


func refresh(panel: Control) -> void:
	var gid := str(panel.get("good_id"))
	_title.call("set_text", "Sell %s" % Catalog.get_display_name(gid))
	var quote: Dictionary = panel.get("_quote")
	var by_tile: Dictionary = quote.get("by_tile", {})
	var sources: Array = panel.get("sources")
	var selected: Dictionary = panel.get("selected")
	_all.set("latched", not sources.is_empty() and (panel.call("selected_tiles") as Array).size() == sources.size())
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	if sources.is_empty():
		var none := Parts.body("You hold no %s and make none." % Catalog.get_display_name(gid))
		none.name = "NoSources"
		_rows.add_child(none)
	for s: Dictionary in sources:
		var tile := str(s.tile)
		_rows.add_child(_place_row(panel, s, by_tile.get(tile, {}), bool(selected.get(tile, false))))
	for c in _total.get_children():
		_total.remove_child(c)
		c.queue_free()
	var total: Dictionary = quote.get("total", {})
	_total.add_child(Parts.spacer(TICK_W, 0))
	var label := Parts.caption("Total", 18)
	label.custom_minimum_size.x = PLACE_W
	_total.add_child(label)
	var units := Parts.body(str(int(total.get("units", 0))))
	units.name = "TotalUnits"
	units.custom_minimum_size.x = UNITS_W
	units.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	units.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_total.add_child(units)
	_add_figures(_total, float(total.get("revenue", 0.0)), float(total.get("charges", 0.0)), float(total.get("net", 0.0)), true)
	_note.text = str(panel.call("note_text"))
	_guard_label.text = "Confirm recurring sale" if bool(panel.get("recurring")) else "Confirm sale"
	_guard.set("disabled", not bool(panel.call("can_confirm")))


func _place_row(panel: Control, s: Dictionary, line: Dictionary, ticked: bool) -> PanelContainer:
	var tile := str(s.tile)
	var m := Parts.module("Place_%s" % tile)
	m.custom_minimum_size.y = 0
	var row := Parts.row_of(m)
	row.custom_minimum_size.y = 52
	row.add_theme_constant_override("separation", GAP)
	var tick: Control = LatchKey.new()
	tick.name = "Tick_%s" % tile
	tick.set("text", "Sell")
	tick.set("latched", ticked)
	tick.custom_minimum_size.x = TICK_W
	tick.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	tick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tick.connect("pressed", func() -> void: panel.call("set_tile_selected", tile, not ticked))
	row.add_child(tick)
	var held := "Holds %d" % int(s.held)
	if int(s.made) > 0:
		held += ", makes %d a turn" % int(s.made)
	var col := VBoxContainer.new()
	col.custom_minimum_size.x = PLACE_W
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override("separation", 1)
	var name := Parts.body(str(s.name))
	name.add_theme_font_override("font", Parts.FONT_TITLE)
	name.custom_minimum_size.x = PLACE_W
	col.add_child(name)
	var under := Parts.body(held)
	under.custom_minimum_size.x = PLACE_W
	col.add_child(under)
	row.add_child(col)
	var n := int(line.get("units", 0))
	var units := Parts.body(str(n) if ticked else "")
	units.name = "Units"
	units.custom_minimum_size.x = UNITS_W
	units.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	units.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	units.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(units)
	if ticked and n > 0:
		_add_figures(row, float(line.revenue), float(line.charges), float(line.net), false)
	elif ticked and not bool(line.get("reachable", true)):
		row.add_child(Parts.body("No route to a port"))
	return m


func _add_figures(row: HBoxContainer, revenue: float, charges: float, net: float, total: bool) -> void:
	var w := money_w()
	for spec: Array in [["Revenue", revenue, DS.PALETTE["TEXT"]], ["Charges", charges, DS.PALETTE["DANGER"]],
			["Net", net, DS.PALETTE["OK"] if net >= 0.0 else DS.PALETTE["DANGER"]]]:
		var box := LedgerV3._boxed(MParts.money(float(spec[1]), spec[2], MParts.MONEY_CELLS, true), w)
		box.name = ("Total" if total else "") + str(spec[0])
		row.add_child(box)
