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
	# The price you RECEIVE when selling a unit to the market.
	return prices.get(good_id, 1.0)

func get_buy_price(good_id: String) -> float:
	# The price you PAY to buy a unit from the market — the sale price plus the
	# market spread (EconomyConfig.MARKET_BUY_MARKUP).
	return get_price(good_id) * (1.0 + EconomyConfig.MARKET_BUY_MARKUP)

func get_estimated_price_in_n_turns(good_id: String, n: int) -> float:
	var current: float = prices.get(good_id, 1.0)
	var good: Dictionary = Catalog.get_good(good_id)
	var decay: float = good.get("decay_rate", 0.0)
	return current * pow(1.0 - decay, n)

# --- Save/load (orchestrated by the SaveLoad autoload; docs/save_load_spec.md) ---

func export_state() -> Dictionary:
	return {"prices": prices.duplicate(true)}

func import_state(d: Dictionary) -> void:
	# Re-seed from the catalog first so goods added since the save keep their base
	# price, then overlay the saved (decayed) prices. Silent: SaveLoad emits
	# prices_updated once after every system imports.
	for good in Catalog.all_goods():
		prices[good.id] = good.base_price
	var saved: Dictionary = d.get("prices", {})
	for good_id in saved:
		prices[good_id] = float(saved[good_id])

func tick_turn() -> void:
	for good_id in prices.keys():
		var good: Dictionary = Catalog.get_good(good_id)
		var decay: float = good.get("decay_rate", 0.0)
		prices[good_id] = prices[good_id] * (1.0 - decay)
	prices_updated.emit()
