extends PanelContainer
## The market's sell panel: sell one good from the tiles that hold or make it. Opened by a good's Sell key
## on the board. Bulk sell is this panel for one good.
##   a table of every tile that holds the good or makes it (MarketRules.sell_sources), a tick box each and
##     Select all over them;
##   the quantity: everything on each tile, everything but X on each tile, or only X from each tile;
##   One off (the default) or Recurring;
##   the preview, per tile and in total (MarketRules.sell_quote, the figures the sale pays);
##   a guarded Confirm sale key (scripts/ds2/guard_key.gd): the first click lifts its cover, the second
##     sells. One off sells now (MatchState.sell_all_to_market, the queue_sell path); Recurring sets up
##     the same sale every turn from the chosen tiles (MatchState.add_recurring_bulk_sell).
## The panel covers its host (the market panel) until closed. Its state (the good, the ticks, the mode, the
## quantity and One off or Recurring) is plain data, so tests drive it without clicking: open(),
## set_tile_selected(), set_all_selected(), set_mode(), set_qty(), set_recurring(), quote(), confirm().
## Its look is the DS2 skin (scripts/market_ds2/sell_skin.gd); the behaviour is here.

signal closed
signal sold(result: Dictionary)

const MarketRules := preload("res://scripts/market_rules.gd")

var good_id := ""
var mode := MarketRules.MODE_ALL
var qty := 0
var recurring := false
## tile -> ticked
var selected: Dictionary = {}
var sources: Array = []
var _quote: Dictionary = {}
var _skin: RefCounted = null


func _init() -> void:
	name = "MarketSellPanel"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL


func _ready() -> void:
	if get_child_count() == 0:
		_build()


## Opens the panel on `gid`: every source ticked, everything from each, one off.
func open(gid: String) -> void:
	good_id = gid
	mode = MarketRules.MODE_ALL
	qty = 0
	recurring = false
	selected.clear()
	sources = MarketRules.sell_sources(good_id)
	for s: Dictionary in sources:
		selected[str(s.tile)] = true
	if get_child_count() == 0:
		_build()
	visible = true
	_sync_controls()
	refresh()


func close() -> void:
	visible = false
	closed.emit()


func selected_tiles() -> Array:
	var out: Array = []
	for s: Dictionary in sources:
		if bool(selected.get(str(s.tile), false)):
			out.append(str(s.tile))
	return out


func set_tile_selected(tile: String, on: bool) -> void:
	selected[tile] = on
	refresh()


func set_all_selected(on: bool) -> void:
	for s: Dictionary in sources:
		selected[str(s.tile)] = on
	refresh()


func set_mode(m: String) -> void:
	mode = m
	_sync_controls()
	refresh()


func set_qty(n: int) -> void:
	qty = maxi(0, n)
	refresh()


func set_recurring(on: bool) -> void:
	recurring = on
	_sync_controls()
	refresh()


## The preview for the panel's state, as the sale will pay it.
func quote() -> Dictionary:
	return MarketRules.sell_quote(good_id, selected_tiles(), mode, qty)


## Whether Confirm sale would do anything: a one off needs units to sell; a recurring sale needs a tile
## and, for Only X, an X.
func can_confirm() -> bool:
	if selected_tiles().is_empty():
		return false
	if recurring:
		return mode != MarketRules.MODE_ONLY or qty > 0
	return int((_quote.get("total", {}) as Dictionary).get("units", 0)) > 0


## Sells (one off) or sets up the recurring sale, as the preview said. Returns the sale's result
## ({total_qty, revenue, tiles}), or {recurring: true, params} for a recurring sale; {} when nothing to do.
func confirm() -> Dictionary:
	_quote = quote()
	if not can_confirm():
		return {}
	var params: Dictionary = _quote.params
	var result: Dictionary = {}
	var name_text := Catalog.get_display_name(good_id)
	if recurring:
		MatchState.add_recurring_bulk_sell(params)
		result = {"recurring": true, "params": params}
		MatchState.request_toast("Selling %s every turn from %d place%s" % [name_text, selected_tiles().size(),
			"" if selected_tiles().size() == 1 else "s"], "success")
	else:
		result = MatchState.sell_all_to_market(params)
		var units := int(result.get("total_qty", 0))
		var places := int(result.get("tiles", 0))
		if units > 0:
			MatchState.request_toast("Selling %d %s from %d place%s" % [units, name_text, places, "" if places == 1 else "s"], "success")
		else:
			MatchState.request_toast("Nothing to sell", "warning")
	sold.emit(result)
	sources = MarketRules.sell_sources(good_id)
	refresh()
	return result


## Re-reads the preview and redraws the table and the figures.
func refresh() -> void:
	if good_id == "":
		return
	_quote = quote()
	_skin.call("refresh", self)


func figure(amount: float) -> String:
	return "£%.2f" % amount


# --- the look ----------------------------------------------------------------------------------

func _build() -> void:
	_skin = load("res://scripts/market_ds2/sell_skin.gd").new()
	_skin.call("build", self)


func _sync_controls() -> void:
	_skin.call("sync", self)


## One line on when the money comes and what repeats.
func note_text() -> String:
	var total: Dictionary = _quote.get("total", {})
	var unit := float(_quote.get("unit_price", 0.0))
	if recurring:
		return "Sells every turn from the ticked places at that turn's price. The figures are this turn's, at %s a unit." % figure(unit)
	var turns := int(total.get("turns", 0))
	if int(total.get("units", 0)) <= 0:
		return "Nothing to sell from the ticked places."
	if turns <= 0:
		return "Sold at %s a unit and paid now." % figure(unit)
	if LoanState.transit_credit_available() and LoanState.transit_credit_enabled:
		return "Sold at %s a unit. The transit credit line pays now, the goods reach the port in %d turn%s." % [
			figure(unit), turns, "" if turns == 1 else "s"]
	return "Sold at %s a unit. Paid when the goods reach the port, in up to %d turn%s." % [figure(unit), turns, "" if turns == 1 else "s"]

