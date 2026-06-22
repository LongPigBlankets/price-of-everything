extends RefCounted
## Shared building status / cost helpers, extracted from building_detail_panel.gd so the
## detail panel and the Building Ledger compute RAG colours, power supply, primary output,
## lifetime production, etc. from ONE source of truth (no drift).
##
## All functions are STATIC and pure w.r.t. UI state — they read only autoload singletons
## (Catalog, Production, Power, Stockpile, MatchState). Consumers `preload` this as
## `const BuildingStatus := preload("res://scripts/building_status.gd")` (no class_name, so
## it resolves in headless test runs too — see the GDScript gotcha in the test setup notes).

const BuildingLevels := preload("res://scripts/building_levels.gd")

# RAG palette — identical values to building_detail_panel.gd's STATUS_* consts (the contract
# the detail panel's status dots already render against). power_supply()'s return strings are
# likewise a contract: power_status_color() compares against the literal "Owned Supply".
const STATUS_GREEN := Color("#5BD180")   # DS PALETTE OK
const STATUS_RED := Color("#E66060")     # DS PALETTE DANGER
const STATUS_GREY := Color(0.45, 0.48, 0.52)
const STATUS_YELLOW := Color("#E6B85C")  # DS PALETTE WARN

# --- Recipe / output introspection ---------------------------------------------------------

static func flow_output_items(recipe: Dictionary) -> Array:
	if recipe.has("outputs"):
		return recipe.get("outputs", [])
	var output_name: String = recipe.get("output_name", "")
	var output_qty: int = int(recipe.get("output_qty", 0))
	if output_name == "" or output_qty <= 0:
		return []
	return [{
		"good_id": recipe.get("output_good_id", ""),
		"internal_name": output_name,
		"qty": output_qty,
	}]

static func primary_output_good_id(recipe: Dictionary) -> String:
	for output in flow_output_items(recipe):
		var gid: String = str(output.get("good_id", ""))
		if gid != "":
			return gid
		var internal_name: String = str(output.get("internal_name", ""))
		if internal_name != "":
			return str(Catalog.get_good_by_internal_name(internal_name).get("id", ""))
	return ""

# Primary output's internal_name — the key deposit/mining-yield modifiers match on.
static func primary_output_internal(recipe: Dictionary) -> String:
	for output in flow_output_items(recipe):
		var internal_name: String = str(output.get("internal_name", ""))
		if internal_name != "":
			return internal_name
		var gid: String = str(output.get("good_id", ""))
		if gid != "":
			return str(Catalog.get_good(gid).get("internal_name", ""))
	return ""

static func primary_output_qty(recipe: Dictionary) -> int:
	for output in flow_output_items(recipe):
		return int(output.get("qty", 0))
	return 0

# Post-modifier output qty of the building's PRIMARY good this turn — mirrors
# production.gd._produce_outputs: recipe_output modifiers, then the level OUTPUT_MULT.
# Returns the per-turn output capacity (0 for power/infra or unknown goods).
static func effective_output_qty(building: Dictionary, recipe: Dictionary) -> int:
	for output in flow_output_items(recipe):
		var internal_name: String = str(output.get("internal_name", ""))
		var base_qty: int = int(output.get("qty", 0))
		if internal_name == "" or base_qty <= 0:
			continue
		var good: Dictionary = Catalog.get_good_by_internal_name(internal_name)
		if good.is_empty():
			continue
		var recipe_id: String = str(recipe.get("recipe_id", ""))
		var ctx := {
			"recipe_id": recipe_id,
			"recipe_type": str(recipe.get("recipe_type", "")).to_lower(),
			"building_id": str(building.get("building_id", "")),
			"good_id": str(good.id),
			"good_internal": internal_name,
		}
		var q: int = int(round(Modifiers.apply("recipe_output", recipe_id, float(base_qty), ctx)))
		q = int(round(float(q) * BuildingLevels.mult("output", int(building.get("level", 1)))))
		return maxi(0, q)
	return 0

# Power CONSUMPTION this turn (post building_power modifiers × level ENERGY_MULT) — mirrors
# production.gd._effective_energy_req. 0 when the recipe needs no power.
static func effective_energy_req(building: Dictionary, recipe: Dictionary) -> int:
	var energy_req: int = int(recipe.get("energy_req", 0))
	if energy_req <= 0:
		return energy_req
	var bid: String = str(building.get("building_id", ""))
	var eff := Modifiers.apply("building_power", bid, float(energy_req), {"building_id": bid})
	return int(round(eff * BuildingLevels.mult("energy", int(building.get("level", 1)))))

# Power GENERATION this turn (post recipe_output modifiers × level OUTPUT_MULT) — mirrors
# production.gd._effective_power_output. 0 when the recipe produces no power.
static func effective_power_output(building: Dictionary, recipe: Dictionary) -> int:
	var output_qty: int = int(recipe.get("output_qty", 0))
	if output_qty <= 0 or str(recipe.get("output_name", "")) != "power":
		return 0
	var rid: String = str(recipe.get("recipe_id", ""))
	var ctx := {
		"recipe_id": rid,
		"recipe_type": str(recipe.get("recipe_type", "")).to_lower(),
		"building_id": str(building.get("building_id", "")),
		"good_id": "power",
		"good_internal": "power",
	}
	var eff := Modifiers.apply("recipe_output", rid, float(output_qty), ctx)
	return int(round(eff * BuildingLevels.mult("output", int(building.get("level", 1)))))

static func good_display_from_internal(internal_name: String) -> String:
	return str(Catalog.get_good_by_internal_name(internal_name).get("display_name", internal_name))

static func primary_output_display_name(recipe: Dictionary) -> String:
	var output_name: String = str(recipe.get("output_name", ""))
	if output_name == "":
		return ""
	return good_display_from_internal(output_name)

# --- Deposit / extraction ------------------------------------------------------------------

static func recipe_deposit_exhausted(building: Dictionary, recipe: Dictionary) -> bool:
	var tile_id := str(building.get("tile_id", ""))
	if tile_id == "":
		return false
	for req in recipe.get("requirements", []):
		if str(req.get("type", "")) != "deposit":
			continue
		var token := str(req.get("value", ""))
		if token == "" or token == "water":
			continue
		if MatchState.deposit_remaining_for(tile_id, token) == 0:
			return true
	return false

# --- Power ---------------------------------------------------------------------------------

static func tile_power_state(tile_id: String) -> Dictionary:
	var connected := Power.is_supplied(tile_id, 1)
	var supply := 0
	var demand := 0
	var has_power_plant := false
	for building in MatchState.get_buildings_on_tile(tile_id):
		var recipe: Dictionary = Catalog.get_recipe(str(building.get("recipe_id", "")))
		if str(recipe.get("output_name", "")) == "power":
			has_power_plant = true
			supply += int(recipe.get("output_qty", 0))
		demand += int(recipe.get("energy_req", 0))
	return {
		"connected": connected,
		"supply": supply,
		"demand": demand,
		"has_power_plant": has_power_plant,
	}

# Returns one of the contract strings: "Owned Supply" / "Grid" / "Not connected".
static func power_supply(building: Dictionary) -> String:
	var power_state := tile_power_state(str(building.get("tile_id", "")))
	if not power_state.get("connected", false):
		return "Not connected"
	if not power_state.get("has_power_plant", false) or int(power_state.get("supply", 0)) < int(power_state.get("demand", 0)):
		return "Grid"
	return "Owned Supply"

static func power_status_color(building: Dictionary, recipe: Dictionary, is_infrastructure: bool) -> Color:
	if is_infrastructure:
		return STATUS_GREY
	var energy_req: int = int(recipe.get("energy_req", 0))
	var produces_power: bool = str(recipe.get("output_name", "")) == "power"
	if energy_req <= 0 and not produces_power:
		return STATUS_GREY
	if not Power.is_supplied(str(building.get("tile_id", "")), energy_req):
		return STATUS_RED
	return STATUS_GREEN if power_supply(building) == "Owned Supply" else STATUS_YELLOW

# --- Inputs / run status -------------------------------------------------------------------

static func input_status_color(building: Dictionary, recipe: Dictionary, is_infrastructure: bool) -> Color:
	if is_infrastructure:
		return STATUS_GREY
	# An extraction building whose deposit is mined out can no longer produce.
	if recipe_deposit_exhausted(building, recipe):
		return STATUS_RED
	var instance_id: String = str(building.get("instance_id", ""))
	if instance_id != "" and Production.last_turn_run.has(instance_id):
		return STATUS_GREEN
	if instance_id != "" and Production.missing_by_building.has(instance_id):
		return STATUS_RED
	var inputs: Array = recipe.get("inputs", [])
	if inputs.is_empty():
		return STATUS_GREEN
	var tile_id: String = str(building.get("tile_id", ""))
	for input in inputs:
		if Stockpile.get_at_tile(tile_id, str(input.get("good_id", ""))) < int(input.get("qty", 0)):
			return STATUS_RED
	return STATUS_YELLOW

# --- Cost RAG (the pure pct->colour band split out of _update_cost_label) -------------------
# unit_cost < 0 (unsolved / mined-out) -> grey. Bands: <90% green, 90-110% amber, >110% red.
static func cost_rag_color(unit_cost: float, base_price: float) -> Color:
	if unit_cost < 0.0:
		return STATUS_GREY
	var pct: float = (unit_cost / base_price * 100.0) if base_price > 0.0 else 0.0
	if pct < 90.0:
		return STATUS_GREEN
	elif pct <= 110.0:
		return STATUS_YELLOW
	return STATUS_RED

# --- Lifetime production / streak ----------------------------------------------------------

static func produced_good_display_name(good_key: String, recipe: Dictionary) -> String:
	if good_key == "power":
		return "Power"
	var good: Dictionary = Catalog.get_good(good_key)
	if not good.is_empty():
		return str(good.get("display_name", good_key))
	for output in flow_output_items(recipe):
		if str(output.get("internal_name", "")) == good_key:
			return good_display_from_internal(good_key)
	return good_key

static func produced_since_construction(building: Dictionary, recipe: Dictionary) -> String:
	var instance_id: String = str(building.get("instance_id", ""))
	var totals: Dictionary = Production.produced_by_building.get(instance_id, {}) as Dictionary
	if totals.is_empty():
		return "0"
	var parts: Array = []
	for good_key in totals.keys():
		parts.append("%d %s" % [int(totals[good_key]), produced_good_display_name(str(good_key), recipe)])
	return ", ".join(parts)

static func full_output_streak(building: Dictionary) -> int:
	return int(Production.full_output_streak_by_building.get(str(building.get("instance_id", "")), 0))

# --- Costs ---------------------------------------------------------------------------------

static func maintenance_cost(building_data: Dictionary) -> float:
	# catalog.gd stores null when the CSV maintenance cell is blank — guard it.
	var value = building_data.get("maintenance_cost", 0.0)
	if value == null:
		return 0.0
	return float(value)
