extends Node
# Static reference data: goods, recipes, (later: buildings).
# Loaded once at game start. Never mutated during a match.

const GOODS_CSV_PATH := "res://data/Goods - goodsMVP.csv"
const RECIPES_CSV_PATH := "res://data/recipes_all.csv"
const BUILDINGS_CSV_PATH := "res://data/Buildings - buildingsMVP.csv"

# recipes_all.csv references buildings by internal_name; a few don't match the
# game's building internal_names, so alias them here. Recipes whose building can't
# be resolved (or whose goods don't all exist) are dropped by the promotion gate.
const BUILDING_ALIAS := {
	"power_plant": "coal_power",
	"factory": "industrial_factory",
	"industrial_goods_factory": "industrial_factory",
	"consumer_goods_factory": "consumer_factory",
	"water_well": "water_pump",
	"desal_plant": "desal",
	"water_treatment_plant": "water_recycling",
	"hydro_dam": "hydro_power_plant",
	"forest": "new_forest",
}

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
	_load_buildings()
	_load_recipes()

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
		"transport_class": raw.get("transport_class", EconomyConfig.DEFAULT_TRANSPORT_WEIGHT_CLASS),
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

func get_transport_class(good_id: String) -> String:
	var g: Dictionary = _goods_by_id.get(good_id, {})
	var weight_class: String = g.get("transport_class", "")
	return EconomyConfig.DEFAULT_TRANSPORT_WEIGHT_CLASS if weight_class == "" else weight_class

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
	
	# Inputs: input_1/qty_1 .. input_6/qty_6
	var inputs: Array = []
	for i in range(1, 7):
		var input_name: String = raw.get("input_%d" % i, "")
		var input_qty_str: String = raw.get("qty_%d" % i, "")
		if input_name == "" or input_qty_str == "":
			continue
		var good: Dictionary = get_good_by_internal_name(input_name)
		inputs.append({
			"good_id": good.get("id", ""),
			"internal_name": input_name,
			"qty": int(input_qty_str),
		})

	# Outputs: output_1/output_qty_1 .. output_5/output_qty_5
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

	# --- Promotion gate ---
	# Active only if the building resolves, there's at least one output, and EVERY
	# input + output is an existing good. Otherwise the recipe stays dormant.
	var resolved_building_id := _resolve_building_id(raw.get("building_id", ""))
	if resolved_building_id == "" or outputs.is_empty():
		return {}
	for inp in inputs:
		if inp.good_id == "":
			return {}
	for outp in outputs:
		if outp.good_id == "":
			return {}

	return {
		"recipe_id": raw.get("recipe_id", ""),
		"display_name": raw.get("display_name", ""),
		"building_id": resolved_building_id,
		"recipe_type": raw.get("category", ""),
		"inputs": inputs,
		"outputs": outputs,
		"output_name": outputs[0].internal_name,
		"output_good_id": outputs[0].good_id,
		"output_qty": outputs[0].qty,
		"energy_req": int(raw.get("energy_req", "0")),
		"requirements": _parse_requirements(raw.get("requirements", "")),
	}

# Parses the requirements string into a list of typed entries.
# Format: "type:value" entries joined by ";" (or "|"). Bare "wind"/"solar"
# tokens are treated as potential requirements. Supported types: deposit,
# produces, potential. Unknown tokens are kept as {"type": "other", ...}.
func _parse_requirements(raw_str: String) -> Array:
	var out: Array = []
	if raw_str == "":
		return out
	var parts: PackedStringArray = raw_str.replace("|", ";").split(";", false)
	for part in parts:
		var token: String = part.strip_edges()
		if token == "":
			continue
		if token.ends_with("_deposit"):
			out.append({"type": "deposit", "value": token.trim_suffix("_deposit")})
			continue
		if token == "wind" or token == "solar":
			out.append({"type": "potential", "value": token})
			continue
		var colon: int = token.find(":")
		if colon < 0:
			out.append({"type": "other", "value": token})
			continue
		var key: String = token.substr(0, colon).strip_edges()
		var val: String = token.substr(colon + 1).strip_edges()
		match key:
			"deposit", "produces":
				out.append({"type": key, "value": val})
			"potential":
				out.append({"type": "potential", "value": val})
			_:
				out.append({"type": "other", "value": token})
	return out

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
		"building_type": _split_types(raw.get("building_type", "")),
		"base_price": float(raw.get("build_cost_money", "0")),
		"tile_size_used": 1 if raw.get("tile_size_used", "") == "" else int(raw.get("tile_size_used", "1")),
		"build_duration": 0 if raw.get("build_duration", "") == "" else int(raw.get("build_duration", "0")),
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

# Resolve a recipe's building reference (internal_name, possibly aliased) to a b_id.
func _resolve_building_id(building_field: String) -> String:
	if building_field == "":
		return ""
	var internal: String = BUILDING_ALIAS.get(building_field, building_field)
	var b: Dictionary = _buildings_by_internal_name.get(internal, {})
	return b.get("id", "")

# Split a pipe-separated building_type field into an array of trimmed tokens.
func _split_types(s: String) -> Array:
	var result: Array = []
	for t in s.split("|", false):
		var tt: String = t.strip_edges()
		if tt != "":
			result.append(tt)
	return result
