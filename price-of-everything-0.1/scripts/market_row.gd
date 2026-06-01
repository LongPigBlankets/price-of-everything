extends HBoxContainer

@onready var name_label: Label = $NameLabel
@onready var price_label: Label = $PriceLabel
@onready var est_price_label: Label = $EstPriceLabel

const PROD_COST_LEGEND := "Green: cheaper than market (<90%) · Amber: about even (90–110%) · Red: dearer than market (>110%)"
const COST_GREEN := Color(0.36, 0.82, 0.40)
const COST_AMBER := Color(0.95, 0.72, 0.22)
const COST_RED := Color(0.90, 0.38, 0.38)
const COST_GREY := Color(0.62, 0.62, 0.62)

var good_id: String = ""
var _prod_cost_label: Label = null

func setup(good_data: Dictionary) -> void:
	good_id = good_data.id
	name_label.text = good_data.display_name
	_prod_cost_label = Label.new()
	_prod_cost_label.custom_minimum_size = Vector2(120, 0)
	_prod_cost_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_prod_cost_label.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_prod_cost_label)
	if not CostSolver.costs_updated.is_connected(_update_prod_cost):
		CostSolver.costs_updated.connect(_update_prod_cost)
	_update_price()
	_update_prod_cost()

func _update_price() -> void:
	var price: float = MarketState.get_price(good_id)
	var est: float = MarketState.get_estimated_price_in_n_turns(good_id, MarketState.FORECAST_TURNS)
	price_label.text = "£%.2f" % price
	est_price_label.text = "£%.2f" % est

func _update_prod_cost() -> void:
	if _prod_cost_label == null:
		return
	var uc: float = CostSolver.get_good_unit_cost(good_id)
	if uc < 0.0:
		_prod_cost_label.text = "—"
		_prod_cost_label.add_theme_color_override("font_color", COST_GREY)
		_prod_cost_label.tooltip_text = "Not produced yet.\n" + PROD_COST_LEGEND
		return
	var price: float = MarketState.get_price(good_id)
	var pct: float = (uc / price * 100.0) if price > 0.0 else 0.0
	var color := COST_AMBER
	if pct < 90.0:
		color = COST_GREEN
	elif pct > 110.0:
		color = COST_RED
	_prod_cost_label.text = "£%.2f/unit" % uc
	_prod_cost_label.add_theme_color_override("font_color", color)
	_prod_cost_label.tooltip_text = "Production cost per unit: £%.2f (%.1f%% of market price)\n%s" % [uc, pct, PROD_COST_LEGEND]
