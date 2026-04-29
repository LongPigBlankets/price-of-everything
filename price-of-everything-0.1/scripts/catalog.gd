extends Node

const CSV_PATH := "res://data/Goods - goodsMVP.csv"

var _goods_by_id: Dictionary = {}
var _goods_by_internal_name: Dictionary = {}
var _all_goods: Array = []

func _ready() -> void:
	_load()

func _load() -> void:
	if not FileAccess.file_exists(CSV_PATH):
		push_error("GoodsCatalog: CSV not found at %s" % CSV_PATH)
		return
	
	var file := FileAccess.open(CSV_PATH, FileAccess.READ)
	var headers := file.get_csv_line()
	
	while not file.eof_reached():
		var line := file.get_csv_line()
		if line.size() < headers.size() or line[0] == "":
			continue
		var good := _parse_row(headers, line)
		if good.is_empty():
			continue
		_all_goods.append(good)
		_goods_by_id[good.id] = good
		if good.internal_name != "":
			_goods_by_internal_name[good.internal_name] = good
	
	file.close()
	print("GoodsCatalog: loaded %d goods" % _all_goods.size())

func _parse_row(headers: PackedStringArray, line: PackedStringArray) -> Dictionary:
	var raw := {}
	for i in headers.size():
		var key := headers[i].strip_edges().to_lower().replace(" ", "_")
		var val: String = line[i].strip_edges() if i < line.size() else ""
		raw[key] = val
	
	return {
		"id": raw.get("id", ""),
		"internal_name": raw.get("internal_name", ""),
		"display_name": raw.get("display_name", raw.get("internal_name", "")),
		"category": raw.get("category", ""),
		"good_type": raw.get("good_type", ""),
		"base_price": float(raw.get("base_price", "1")),
		"decay_rate": float(raw.get("decay_rate", "0")),
		"is_buyable": raw.get("is_buyable", "").to_upper() == "TRUE",
		"is_sellable": raw.get("is_sellable", "").to_upper() == "TRUE",
		"is_fossil_fuel": raw.get("is_fossil_fuel", "").to_lower() == "yes",
	}

# Public API
func all() -> Array:
	return _all_goods

func get_good(good_id: String) -> Dictionary:
	return _goods_by_id.get(good_id, {})

func get_by_internal_name(internal_name: String) -> Dictionary:
	return _goods_by_internal_name.get(internal_name, {})

func get_display_name(good_id: String) -> String:
	var g: Dictionary = _goods_by_id.get(good_id, {})
	return g.get("display_name", good_id)

func get_internal_name(good_id: String) -> String:
	var g: Dictionary = _goods_by_id.get(good_id, {})
	return g.get("internal_name", "")

func get_base_price(good_id: String) -> float:
	var g: Dictionary = _goods_by_id.get(good_id, {})
	return g.get("base_price", 1.0)

func is_raw(good_id: String) -> bool:
	var g: Dictionary = _goods_by_id.get(good_id, {})
	return g.get("good_type", "") == "raw"
