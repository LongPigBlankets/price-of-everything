extends Node

const FORECAST_TURNS := 10

var prices: Dictionary = {}  # good_id -> current price (float)

signal prices_updated()

func _ready() -> void:
	await get_tree().process_frame
	_init_prices_from_catalog()
	TurnManager.turn_advanced.connect(_on_turn_advanced)

func _on_turn_advanced(_new_turn: int) -> void:
	tick_turn()

func _init_prices_from_catalog() -> void:
	for good in Catalog.all_goods():
		prices[good.id] = good.base_price
	prices_updated.emit()

func get_price(good_id: String) -> float:
	return prices.get(good_id, 1.0)

func get_estimated_price_in_n_turns(good_id: String, n: int) -> float:
	var current: float = prices.get(good_id, 1.0)
	var good: Dictionary = Catalog.get_good(good_id)
	var decay: float = good.get("decay_rate", 0.0)
	return current * pow(1.0 - decay, n)

func tick_turn() -> void:
	for good_id in prices.keys():
		var good: Dictionary = Catalog.get_good(good_id)
		var decay: float = good.get("decay_rate", 0.0)
		prices[good_id] = prices[good_id] * (1.0 - decay)
	prices_updated.emit()
