extends VBoxContainer
## A market goods row: 60x60 icon + name button + market/cost columns, with an
## expandable Sell / Purchase / Move / Expand action block underneath.

const GoodIcons := preload("res://scripts/good_icons.gd")

const ICON_SIZE := 60
const NAME_W := 160.0
const COL_PRICE := 80.0
const COL_EST := 90.0
const COL_SOLD := 80.0
const COL_BOUGHT := 90.0
const COL_COST := 100.0
const COL_PROFIT := 110.0
const FORECAST := 10  # "price in 10 turns"

const COST_GREEN := Color(0.36, 0.82, 0.40)
const COST_AMBER := Color(0.95, 0.72, 0.22)
const COST_RED := Color(0.90, 0.38, 0.38)
const COST_GREY := Color(0.62, 0.62, 0.62)
const COST_LEGEND := "Green: cheaper than market (<90%) · Amber: about even (90–110%) · Red: dearer than market (>110%)"

var good_id: String = ""
var internal_name: String = ""

var _price_label: Label = null
var _est_label: Label = null
var _sold_label: Label = null
var _bought_label: Label = null
var _cost_label: Label = null
var _profit_label: Label = null
var _expand_section: VBoxContainer = null
var _expanded := false

func setup(good_data: Dictionary) -> void:
	good_id = str(good_data.get("id", ""))
	internal_name = str(good_data.get("internal_name", ""))

	var main := HBoxContainer.new()
	main.custom_minimum_size = Vector2(0, ICON_SIZE + 6)
	main.add_theme_constant_override("separation", 10)
	add_child(main)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var tex: Texture2D = GoodIcons.texture_for(good_id, internal_name)
	if tex != null:
		icon.texture = tex
	main.add_child(icon)

	var name_btn := Button.new()
	name_btn.text = str(good_data.get("display_name", good_id))
	name_btn.custom_minimum_size = Vector2(NAME_W, ICON_SIZE)
	name_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_btn.pressed.connect(_toggle_expand)
	main.add_child(name_btn)

	_price_label = _make_col(COL_PRICE)
	_est_label = _make_col(COL_EST)
	_sold_label = _make_col(COL_SOLD)
	_bought_label = _make_col(COL_BOUGHT)
	_cost_label = _make_col(COL_COST)
	_profit_label = _make_col(COL_PROFIT)
	for l in [_price_label, _est_label, _sold_label, _bought_label, _cost_label, _profit_label]:
		main.add_child(l)

	_expand_section = VBoxContainer.new()
	_expand_section.visible = false
	_expand_section.add_theme_constant_override("separation", 4)
	for action in ["Sell", "Purchase", "Move", "Expand"]:
		var b := Button.new()
		b.text = action
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if action == "Expand":
			b.pressed.connect(_on_expand_to_construct)
		_expand_section.add_child(b)
	add_child(_expand_section)

	if not CostSolver.costs_updated.is_connected(_refresh):
		CostSolver.costs_updated.connect(_refresh)
	if not Production.turn_processed.is_connected(_on_turn_processed):
		Production.turn_processed.connect(_on_turn_processed)
	_refresh()

func _make_col(width: float) -> Label:
	var l := Label.new()
	l.custom_minimum_size = Vector2(width, ICON_SIZE)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l

func _toggle_expand() -> void:
	_expanded = not _expanded
	_expand_section.visible = _expanded

func _on_expand_to_construct() -> void:
	MatchState.show_construct_for_good.emit(good_id)

func _on_turn_processed(_summary: Dictionary) -> void:
	_refresh()

func _refresh() -> void:
	if _price_label == null:
		return
	_price_label.text = "£%.2f" % MarketState.get_price(good_id)
	_est_label.text = "£%.2f" % MarketState.get_estimated_price_in_n_turns(good_id, FORECAST)

	var summary: Dictionary = Production.last_turn_summary
	var sold_entry: Dictionary = summary.get("sold", {}).get(good_id, {})
	var sold_qty := int(sold_entry.get("qty", 0))
	var sold_rev := float(sold_entry.get("revenue", 0.0))
	var bought_qty := int(summary.get("purchased", {}).get(good_id, 0))
	_sold_label.text = str(sold_qty)
	_bought_label.text = str(bought_qty)

	var uc: float = CostSolver.get_good_unit_cost(good_id)
	var price: float = MarketState.get_price(good_id)
	if uc < 0.0:
		_cost_label.text = "—"
		_cost_label.add_theme_color_override("font_color", COST_GREY)
		_cost_label.tooltip_text = "Not produced yet.\n" + COST_LEGEND
	else:
		var pct: float = (uc / price * 100.0) if price > 0.0 else 0.0
		var color := COST_AMBER
		if pct < 90.0:
			color = COST_GREEN
		elif pct > 110.0:
			color = COST_RED
		_cost_label.text = "£%.2f" % uc
		_cost_label.add_theme_color_override("font_color", color)
		_cost_label.tooltip_text = "Production cost per unit: £%.2f (%.1f%% of market)\n%s" % [uc, pct, COST_LEGEND]

	if sold_qty > 0:
		var sale_price := sold_rev / float(sold_qty)
		var profit := sale_price - (uc if uc >= 0.0 else 0.0)
		_profit_label.text = "£%.2f" % profit
		_profit_label.add_theme_color_override("font_color", COST_GREEN if profit > 0.0 else COST_RED)
		_profit_label.tooltip_text = "Profit per unit = avg sale £%.2f − cost £%.2f" % [sale_price, maxf(0.0, uc)]
	else:
		_profit_label.text = "No sales"
		_profit_label.add_theme_color_override("font_color", COST_GREY)
		_profit_label.tooltip_text = "No units sold to market last turn."
