extends PanelContainer
## DS-styled modal for surveying the clicked tile (opened from the Surveying
## mapmode). Shows the cost — £5 plus a number of computers — and two ways to
## source the computers: order from the market (pay money) or take them from a
## stockpile. An unsurveyed tile starts a 2-turn survey; a partially surveyed tile
## completes immediately.

const COMPUTER := "g_051"   # the "Computer" good
const MONEY_COST := 5.0

var _tile_id := ""
var _is_partial := false
var _computers := 2

var _title_label: Label
var _cost_label: Label
var _note_label: Label
var _market_btn: Button
var _stock_btn: Button

func _ready() -> void:
	theme = DS.theme
	visible = false
	# Centre on screen, sized to content (grow symmetrically from the centre anchor).
	anchor_left = 0.5
	anchor_top = 0.5
	anchor_right = 0.5
	anchor_bottom = 0.5
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	custom_minimum_size = Vector2(400.0, 0.0)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var margin := MarginContainer.new()
	for s in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + s, 16)
	add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	margin.add_child(vb)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	_title_label = Label.new()
	_title_label.theme_type_variation = "Title"
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title_label)
	var close := Button.new()
	close.text = "✕"
	close.custom_minimum_size = Vector2(30.0, 30.0)
	close.pressed.connect(_close)
	header.add_child(close)
	vb.add_child(header)
	vb.add_child(HSeparator.new())

	_cost_label = Label.new()
	_cost_label.theme_type_variation = "Section"
	vb.add_child(_cost_label)

	_note_label = Label.new()
	_note_label.theme_type_variation = "Caption"
	_note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note_label.text = "Surveying a tile may automatically survey nearby tiles."
	vb.add_child(_note_label)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_market_btn = Button.new()
	_market_btn.theme_type_variation = "Primary"
	_market_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_market_btn.pressed.connect(_on_market)
	_stock_btn = Button.new()
	_stock_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stock_btn.pressed.connect(_on_stock)
	row.add_child(_market_btn)
	row.add_child(_stock_btn)
	vb.add_child(row)

func open_for(tile_id: String, tile_name: String, is_partial: bool) -> void:
	_tile_id = tile_id
	_is_partial = is_partial
	_computers = 1 if is_partial else 2
	_title_label.text = "Survey %s" % tile_name
	_cost_label.text = "Cost: £%d  +  %d Computer%s   ·   %d turns" % [
		int(MONEY_COST), _computers, "" if _computers == 1 else "s", MatchState.SURVEY_TURNS]
	_note_label.visible = not is_partial  # auto-reveal only happens on a full 2-turn survey
	var buy_total: float = MONEY_COST + float(_computers) * MarketState.get_buy_price(COMPUTER)
	_market_btn.text = "Order from market (£%d)" % int(round(buy_total))
	_stock_btn.text = "Get from a tile's stockpile"
	_market_btn.disabled = MatchState.money < buy_total
	_stock_btn.disabled = MatchState.money < MONEY_COST or Stockpile.get_total(COMPUTER) < _computers
	visible = true
	PanelStack.push(self)

func _on_market() -> void:
	var total: float = MONEY_COST + float(_computers) * MarketState.get_buy_price(COMPUTER)
	if not MatchState.deduct_money(total):
		MatchState.request_toast("Not enough money to survey.", "error")
		return
	_finish_survey()

func _on_stock() -> void:
	if Stockpile.get_total(COMPUTER) < _computers:
		MatchState.request_toast("Not enough computers in stockpiles.", "error")
		return
	if not MatchState.deduct_money(MONEY_COST):
		MatchState.request_toast("Not enough money to survey.", "error")
		return
	Stockpile.consume_anywhere(COMPUTER, _computers)
	_finish_survey()

func _finish_survey() -> void:
	# Partially surveyed tiles don't auto-reveal a neighbour when finished.
	MatchState.begin_survey(_tile_id, not _is_partial)
	MatchState.request_toast("Survey started — %d turns." % MatchState.SURVEY_TURNS, "success")
	_close()

func _close() -> void:
	visible = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not visible:
		PanelStack.remove(self)
