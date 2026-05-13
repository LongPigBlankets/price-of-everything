extends Node
# Static reference data: goods, recipes, (later: buildings).
# Loaded once at game start. Never mutated during a match.

const GOODS_CSV_PATH := "res://data/Goods - goodsMVP.csv"
const RECIPES_CSV_PATH := "res://data/recipesMVP.csv"
const BUILDINGS_CSV_PATH := "res://data/Buildings - buildingsMVP.csv"

# --- Goods storage ---
var _goods_by_id: Dictionary = {}
var _goods_by_internal_name: Dictionary = {}
var _all_goods: Array = []

# --- Recipes storage ---
var _recipes_by_id: Dictionary = {}
var _recipes_by_building: Dictionary = {}
var _all_recipes: Array = []

# Buildings storage
var _buildings_by_id: Dictionary = {}
var _buildings_by_internal_name: Dictionary = {}
var _all_buildings: Array = []

func _ready() -> void:
	_load_goods()
	_load_recipes()
	_load_buildings()

# =========================================================================
# GOODS
# =========================================================================

func _load_goods() -> void:
	if not FileAccess.file_exists(GOODS_CSV_PATH):
		push_error("Catalog: goods CSV not found at %s" % GOODS_CSV_PATH)
		return
	
	var file := FileAccess.open(GOODS_CSV_PATH, FileAccess.READ)
	var headers := file.get_csv_line()
	
	while not file.eof_reached():
		var line := file.get_csv_line()
		if line.size() < headers.size() or line[0] == "":
			continue
		var good := _parse_good_row(headers, line)
		if good.is_empty():
			continue
		_all_goods.append(good)
		_goods_by_id[good.id] = good
		if good.internal_name != "":
			_goods_by_internal_name[good.internal_name] = good
	
	file.close()
	print("Catalog: loaded %d goods" % _all_goods.size())


func _parse_good_row(headers: PackedStringArray, line: PackedStringArray) -> Dictionary:
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

# Public API: goods
func all_goods() -> Array:
	return _all_goods

func get_good(good_id: String) -> Dictionary:
	return _goods_by_id.get(good_id, {})

func get_good_by_internal_name(internal_name: String) -> Dictionary:
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

# =========================================================================
# RECIPES
# =========================================================================

func _load_recipes() -> void:
	if not FileAccess.file_exists(RECIPES_CSV_PATH):
		push_error("Catalog: recipes CSV not found at %s" % RECIPES_CSV_PATH)
		return
	
	var file := FileAccess.open(RECIPES_CSV_PATH, FileAccess.READ)
	var headers := file.get_csv_line()
	
	while not file.eof_reached():
		var line := file.get_csv_line()
		if line.size() < headers.size() or line[0] == "":
			continue
		var recipe := _parse_recipe_row(headers, line)
		if recipe.is_empty():
			continue
		_all_recipes.append(recipe)
		_recipes_by_id[recipe.recipe_id] = recipe
		var building_id: String = recipe.get("building_id", "")
		if building_id != "":
			if not _recipes_by_building.has(building_id):
				_recipes_by_building[building_id] = []
			_recipes_by_building[building_id].append(recipe)
	
	file.close()
	print("Catalog: loaded %d recipes" % _all_recipes.size())

func _parse_recipe_row(headers: PackedStringArray, line: PackedStringArray) -> Dictionary:
	var raw := {}
	for i in headers.size():
		var key := headers[i].strip_edges().to_lower().replace(" ", "_")
		var val: String = line[i].strip_edges() if i < line.size() else ""
		raw[key] = val
	
	# Build inputs array from input_1/qty_1 through input_5/qty_5
	var inputs: Array = []
	for i in range(1, 6):
		var input_name: String = raw.get("input_%d" % i, "")
		var input_qty_str: String = raw.get("qty_%d" % i, "")
		if input_name == "" or input_qty_str == "":
			continue
		# Look up good_id from internal_name (goods loaded first, so this works)
		var good: Dictionary = get_good_by_internal_name(input_name)
		var input_good_id: String = good.get("id", "") if not good.is_empty() else ""
		inputs.append({
			"good_id": input_good_id,
			"internal_name": input_name,
			"qty": int(input_qty_str),
		})
	
	# Output: single output for MVP
	var output_internal: String = raw.get("output_1", "")
	var output_qty: int = int(raw.get("output_qty_1", "0"))
	var output_good: Dictionary = get_good_by_internal_name(output_internal) if output_internal != "" else {}
	var output_good_id: String = output_good.get("id", "")
	var outputs: Array = []
	for i in range(1, 6):
		var output_name: String = raw.get("output_%d" % i, "")
		var output_qty_str: String = raw.get("output_qty_%d" % i, "")
		if output_name == "" or output_qty_str == "":
			continue
		var parsed_output_qty: int = int(output_qty_str)
		if parsed_output_qty <= 0:
			continue
		var output_good_data: Dictionary = get_good_by_internal_name(output_name)
		outputs.append({
			"good_id": output_good_data.get("id", ""),
			"internal_name": output_name,
			"qty": parsed_output_qty,
		})
	
	return {
		"recipe_id": raw.get("recipe_id", ""),
		"display_name": raw.get("display_name", ""),
		"building_id": raw.get("building_id", ""),
		"inputs": inputs,
		"outputs": outputs,
		"output_name": output_internal,
		"output_good_id": output_good_id,
		"output_qty": output_qty,
		"energy_req": int(raw.get("energy_req", "0")),
	}

# Public API: recipes
func all_recipes() -> Array:
	return _all_recipes

func get_recipe(recipe_id: String) -> Dictionary:
	return _recipes_by_id.get(recipe_id, {})

func get_recipes_for_building(building_id: String) -> Array:
	return _recipes_by_building.get(building_id, [])
	
	
# =========================================================================
# BUILDINGS
# =========================================================================
func _load_buildings() -> void:
	if not FileAccess.file_exists(BUILDINGS_CSV_PATH):
		push_error("Catalog: buildings CSV not found at %s" % BUILDINGS_CSV_PATH)
		return
	
	var file := FileAccess.open(BUILDINGS_CSV_PATH, FileAccess.READ)
	var headers := file.get_csv_line()
	
	while not file.eof_reached():
		var line := file.get_csv_line()
		if line.size() < headers.size() or line[0] == "":
			continue
		var building := _parse_building_row(headers, line)
		if building.is_empty():
			continue
		_all_buildings.append(building)
		_buildings_by_id[building.id] = building
		if building.internal_name != "":
			_buildings_by_internal_name[building.internal_name] = building
	
	file.close()
	print("Catalog: loaded %d buildings" % _all_buildings.size())

func _parse_building_row(headers: PackedStringArray, line: PackedStringArray) -> Dictionary:
	var raw := {}
	for i in headers.size():
		var key := headers[i].strip_edges().to_lower().replace(" ", "_")
		var val: String = line[i].strip_edges() if i < line.size() else ""
		raw[key] = val
	
	return {
		"id": raw.get("id", ""),
		"internal_name": raw.get("internal_name", ""),
		"display_name": raw.get("display_name", raw.get("internal_name", "")),
		"category": raw.get("building_category", "production").to_lower(),
		"base_price": float(raw.get("build_cost_money", "0")),
		"tile_size_used": 1 if raw.get("tile_size_used", "") == "" else int(raw.get("tile_size_used", "1")),
		"maintenance_cost": null if raw.get("maintenance_cost", "") == "" else float(raw.get("maintenance_cost", "0")),
		"labour_unskilled_required": int(raw.get("labour_unskilled_required", "0")),
		"labour_skilled_required": int(raw.get("labour_skilled_required", "0")),
		"labour_h_skilled_required": int(raw.get("labour_h_skilled_required", "0")),
	}

# Public API
func all_buildings() -> Array:
	return _all_buildings

func get_building(building_id: String) -> Dictionary:
	return _buildings_by_id.get(building_id, {})

func get_building_by_internal_name(internal_name: String) -> Dictionary:
	return _buildings_by_internal_name.get(internal_name, {})

func get_building_display_name(building_id: String) -> String:
	var b: Dictionary = _buildings_by_id.get(building_id, {})
	return b.get("display_name", building_id)
