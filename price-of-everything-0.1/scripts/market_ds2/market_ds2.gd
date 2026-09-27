extends VBoxContainer
## The market panel in DS2, the commodities exchange (docs/market-ds2-plan.md §5 and §8), built into the market
## panel (scripts/market_panel.gd) while UiPrefs.use_market_ds2 is on. One width for every tab (WIDTH).
##
## The head is fixed on every tab: the MARKET nameplate and the exchange bell (it rings as a turn's prices are
## set), Close; five latching tab keys on the tile view's key bed under one dot matrix strip that carries each
## tab's figure; the ticker, the goods on the move and the orders falling due, scrolling on a dot matrix board;
## the rubber seam. Under it one tab's body at a time:
##   Prices          the board, a module per good (scripts/market_ds2/prices_tab.gd), its slip under it
##   Buildings       the lots for sale with a guarded Buy key each (lots_tab.gd)
##   Special Orders  a ticket per order (book_tabs.gd)
##   Recurring       every standing order with Cancel (book_tabs.gd)
##   History         the blotter, every one off buy, sale and move with its value (book_tabs.gd)
## Everything here is presentation: the figures come from MarketRules (scripts/market_rules.gd).

signal close_requested
signal drag_input(event: InputEvent)

const MarketRules := preload("res://scripts/market_rules.gd")
const MParts := preload("res://scripts/market_ds2/parts.gd")
const Parts := preload("res://scripts/tvp_v3/buildings_parts.gd")
const LedgerV3 := preload("res://scripts/ledger_v3/ledger_v3.gd")
const DotMatrix := preload("res://scripts/ds2/dot_matrix.gd")
const LatchKey := preload("res://scripts/ds2/latch_key.gd")
const Nine := preload("res://scripts/bdp_v3_nine.gd")
const Key := preload("res://scripts/bdp_v3_key.gd")
const Title := preload("res://scripts/bdp_v3_title.gd")
const PricesTab := preload("res://scripts/market_ds2/prices_tab.gd")
const LotsTab := preload("res://scripts/market_ds2/lots_tab.gd")
const BookTabs := preload("res://scripts/market_ds2/book_tabs.gd")

## The panel's one width, every tab (owner, decision 2).
const WIDTH := 960.0
const TABS := [["prices", "Prices"], ["buildings", "Buildings"], ["special_orders", "Special Orders"],
	["recurring", "Recurring"], ["history", "History"]]
const LAYOUT := 1.875
const TEXELS := 2.0 / 1.875
const KEYBED_MARGIN := 14.0
const KEYBED_CORNER := 40.0
const FIGURE_PITCH := 2.0
const TICKER_PITCH := 2.0
## The ticker's crawl, in logical pixels a second, and the orders it announces (due within this many turns).
const TICKER_SPEED := 36.0
const TICKER_DUE_TURNS := 5
const MARK_UP := Color("#4fe38a")
const MARK_DOWN := Color("#ff4d3d")
const MARK_DUE := Color("#ffb23a")

var host: Control = null
var _keys: Dictionary = {}
var _figures: Dictionary = {}
var _tabs: Dictionary = {}
var _body: Control
var _current := ""
var _bell: Control
var _ticker_clip: Control
var _ticker_text: Control
var _ticker_x := 0.0
var _pending_tile := ""


func _init() -> void:
	name = "MarketDs2"
	add_theme_constant_override("separation", 10)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_title_row())
	add_child(_key_bed())
	add_child(_ticker())
	add_child(LedgerV3.seam())
	_body = VBoxContainer.new()
	_body.name = "Body"
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_body)
	set_process(false)
	visibility_changed.connect(func() -> void: set_process(is_visible_in_tree()))


func tab_keys() -> Array:
	return TABS.map(func(t: Array) -> String: return str(t[0]))


func current_tab() -> String:
	return _current


func tab(key: String) -> Control:
	return _tabs.get(key, null)


## Shows the tab `key`, building its body the first time.
func show_tab(key: String) -> void:
	if not _keys.has(key):
		return
	if not _tabs.has(key):
		_tabs[key] = _make_tab(key)
		_body.add_child(_tabs[key])
	_current = key
	for k in _tabs:
		(_tabs[k] as Control).visible = k == key
	for k in _keys:
		_keys[k].set("latched", k == key)
	if _tabs[key].has_method("refresh"):
		_tabs[key].call("refresh")


func _make_tab(key: String) -> Control:
	var t: Control
	match key:
		"prices":
			t = PricesTab.new()
			t.connect("sell_requested", func(gid: String) -> void:
				if host != null:
					host.call("open_sell_panel", gid))
		"buildings":
			t = LotsTab.new()
			t.connect("lot_opened", func(iid: String) -> void:
				MatchState.focus_building_requested.emit(iid)
				if host != null:
					host.hide())
		"special_orders":
			t = BookTabs.Orders.new()
		"recurring":
			t = BookTabs.Recurring.new()
		"history":
			t = BookTabs.History.new()
	t.name = "Tab_%s" % key
	t.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return t


## Opens Buildings filtered to a tile (the tile view's Buy Buildings); the filter drops when the panel closes.
func open_buildings_for_tile(tile_id: String) -> void:
	show_tab("buildings")
	_tabs["buildings"].call("set_tile_filter", tile_id)


func clear_tile_filter() -> void:
	if _tabs.has("buildings"):
		_tabs["buildings"].call("set_tile_filter", "")


## Re-reads every figure: the strip, the ticker, the bell and the tab on show.
func refresh() -> void:
	_bell.call("set_turn", int(TurnManager.current_turn))
	_refresh_figures()
	_refresh_ticker()
	if _tabs.has(_current) and _tabs[_current].has_method("refresh"):
		_tabs[_current].call("refresh")


## A turn's prices are set: the bell rings.
func ring() -> void:
	_bell.call("ring")


## Views the capture tool shows beyond the tabs (hovers): [{name, show: Callable, hide: Callable}].
func capture_views() -> Array:
	var views: Array = []
	if _tabs.has("prices"):
		views.append_array(_tabs["prices"].call("capture_views"))
	views.append({"name": "buildings_by_owner", "show": func() -> void:
		show_tab("buildings")
		_tabs["buildings"].call("set_by_owner", true),
		"hide": func() -> void:
			_tabs["buildings"].call("set_by_owner", false)
			show_tab("prices")})
	return views


# --- the head ----------------------------------------------------------------------------------

func _title_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "MarketTitleRow"
	row.add_theme_constant_override("separation", 16)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_default_cursor_shape = Control.CURSOR_MOVE
	row.gui_input.connect(func(e: InputEvent) -> void: drag_input.emit(e))
	row.add_child(MParts.nameplate())
	_bell = MParts.Bell.new()
	row.add_child(_bell)
	var spring := Control.new()
	spring.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spring)
	var close: TextureButton = Key.make("close", Title.line_height())
	close.name = "CloseKey"
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(func() -> void: close_requested.emit())
	row.add_child(close)
	return row


## The five latching keys on the key bed, one dot matrix strip over them with each tab's figure over its key.
func _key_bed() -> PanelContainer:
	var bed := PanelContainer.new()
	bed.name = "KeyBed"
	var bare := StyleBoxEmpty.new()
	bare.content_margin_left = 10
	bare.content_margin_right = 10
	bare.content_margin_top = 10
	bare.content_margin_bottom = 12
	bed.add_theme_stylebox_override("panel", bare)
	bed.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	bed.draw.connect(func() -> void:
		Nine.paint(bed, LedgerV3.KEYBED, Rect2(Vector2.ZERO, bed.size).grow(KEYBED_MARGIN / LAYOUT),
			(KEYBED_MARGIN + KEYBED_CORNER) * TEXELS))
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 10)
	bed.add_child(stack)
	var display := _screen("KeyDisplay", 5.0)
	var figures := HBoxContainer.new()
	figures.add_theme_constant_override("separation", 8)
	display.add_child(figures)
	display.move_child(figures, 0)
	stack.add_child(display)
	var keys := HBoxContainer.new()
	keys.add_theme_constant_override("separation", 8)
	stack.add_child(keys)
	for t: Array in TABS:
		var id := str(t[0])
		var figure: Control = DotMatrix.new()
		figure.name = "Figure_%s" % id
		figure.set("framed", false)
		figure.set("pitch", FIGURE_PITCH)
		figure.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		figure.mouse_filter = Control.MOUSE_FILTER_PASS
		figures.add_child(figure)
		_figures[id] = figure
		var key: Control = LatchKey.new()
		key.name = "TabKey_%s" % id
		key.set("text", str(t[1]))
		key.connect("pressed", func() -> void: show_tab(id))
		keys.add_child(key)
		_keys[id] = key
	return bed


## A dark glass screen in the mini screen's bezel (the key display's and the ticker's), its content inset;
## the glass is drawn over the content by its last child.
func _screen(screen_name: String, room: float) -> PanelContainer:
	var display := PanelContainer.new()
	display.name = screen_name
	var inset := StyleBoxEmpty.new()
	inset.set_content_margin_all(DotMatrix.RIM / LAYOUT + 2.0)
	inset.content_margin_top += room
	inset.content_margin_bottom += room
	display.add_theme_stylebox_override("panel", inset)
	display.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var corner := (DotMatrix.MARGIN + DotMatrix.RIM + DotMatrix.RADIUS + 2.0) * TEXELS
	display.draw.connect(func() -> void:
		var r := Rect2(Vector2.ZERO, display.size)
		Nine.paint(display, DotMatrix.SCREEN, r.grow(DotMatrix.MARGIN / LAYOUT), corner)
		display.draw_rect(r.grow(-DotMatrix.RIM / LAYOUT), DotMatrix.PANE))
	var glass := Control.new()
	glass.name = "Glass"
	glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glass.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	glass.draw.connect(func() -> void:
		Nine.paint(glass, DotMatrix.GLASS, Rect2(-Vector2.ONE * (DotMatrix.RIM / LAYOUT + 2.0),
			display.size).grow(DotMatrix.MARGIN / LAYOUT), corner))
	display.add_child(glass)
	return display


## The ticker: a long dot matrix board, the goods on the move and the orders falling due crawling across it.
func _ticker() -> PanelContainer:
	var screen := _screen("Ticker", 2.0)
	_ticker_clip = Control.new()
	_ticker_clip.name = "TickerClip"
	_ticker_clip.clip_contents = true
	_ticker_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ticker_clip.custom_minimum_size.y = DotMatrix.ROWS * TICKER_PITCH + 6.0
	screen.add_child(_ticker_clip)
	screen.move_child(_ticker_clip, 0)
	_ticker_text = DotMatrix.new()
	_ticker_text.name = "TickerText"
	_ticker_text.set("framed", false)
	_ticker_text.set("pitch", TICKER_PITCH)
	_ticker_text.set("align", HORIZONTAL_ALIGNMENT_LEFT)
	_ticker_clip.add_child(_ticker_text)
	return screen


## The ticker's words and marks: ▲ for a rising good, ▼ for a falling one, ● for an order falling due. Money
## stays on the LEDs.
static func ticker_runs(goods: Array) -> Array:
	var runs: Array = []
	for m: Dictionary in MarketRules.movers(goods):
		runs.append({"text": "▲ " if int(m.dir) > 0 else "▼ ", "colour": MARK_UP if int(m.dir) > 0 else MARK_DOWN})
		runs.append({"text": "%s    " % str(m.name), "colour": Color.WHITE})
	for o: Dictionary in MarketRules.orders_due(TICKER_DUE_TURNS):
		runs.append({"text": "● ", "colour": MARK_DUE})
		runs.append({"text": "%s ORDER DUE TURN %d    " % [str(o.name), int(o.due)], "colour": Color.WHITE})
	if runs.is_empty():
		runs.append({"text": "PRICES STEADY    ", "colour": Color.WHITE})
	return runs


func ticker_text() -> String:
	return str(_ticker_text.get("text"))


func _refresh_ticker() -> void:
	var runs := ticker_runs(_visible_goods())
	# Twice over, so the crawl wraps without a gap.
	_ticker_text.call("set_runs", runs + runs)
	_ticker_text.size = _ticker_text.get_combined_minimum_size()


func _process(delta: float) -> void:
	if _ticker_text == null:
		return
	var half: float = _ticker_text.size.x * 0.5
	if half <= 0.0 or half < _ticker_clip.size.x * 0.5:
		_ticker_text.position.x = 0.0
		return
	_ticker_x = fmod(_ticker_x + delta * TICKER_SPEED, half)
	_ticker_text.position = Vector2(-_ticker_x, (_ticker_clip.size.y - _ticker_text.size.y) * 0.5)


func _visible_goods() -> Array:
	return MatchState.visible_goods().map(func(g: Dictionary) -> String: return str(g.get("id", "")))


## Each key's figure: Prices the goods rising and falling, Buildings the lots for sale, Special Orders the
## active orders, Recurring the standing orders, History the one off trades.
func _refresh_figures() -> void:
	var moving := MarketRules.movers(_visible_goods())
	var up := moving.filter(func(m: Dictionary) -> bool: return int(m.dir) > 0).size()
	var down := moving.size() - up
	_figures["prices"].call("set_runs", [{"text": "▲", "colour": MARK_UP}, {"text": "%d " % up, "colour": Color.WHITE},
		{"text": "▼", "colour": MARK_DOWN}, {"text": "%d" % down, "colour": Color.WHITE}])
	_figures["buildings"].set("text", str(LotsTab.lot_count()))
	_figures["special_orders"].set("text", str(SpecialOrderState.get_active_orders().size()))
	_figures["recurring"].set("text", str(MarketRules.standing_orders().size()))
	_figures["history"].set("text", str(MatchState.transaction_log.size() + TransportState.move_log.size()))
