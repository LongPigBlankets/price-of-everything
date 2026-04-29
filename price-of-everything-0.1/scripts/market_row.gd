extends HBoxContainer

@onready var name_label: Label = $NameLabel
@onready var price_label: Label = $PriceLabel
@onready var est_price_label: Label = $EstPriceLabel

var good_id: String = ""

func setup(good_data: Dictionary) -> void:
	good_id = good_data.id
	name_label.text = good_data.display_name
	_update_price()

func _update_price() -> void:
	var price: float = MarketState.get_price(good_id)
	var est: float = MarketState.get_estimated_price_in_n_turns(good_id, MarketState.FORECAST_TURNS)
	price_label.text = "£%.2f" % price
	est_price_label.text = "£%.2f" % est
