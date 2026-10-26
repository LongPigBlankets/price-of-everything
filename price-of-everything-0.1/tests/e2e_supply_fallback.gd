extends RefCounted
## The Stoneshore e2e's choice when a seam feeding the chain runs out (docs/pacing-labour-mining-licensing-spec.md
## §14.1, AC25.6): a new mine on the nearest tile with that deposit and room under its free amount, or the
## input back on Local Suppliers, whichever delivers a unit for less.
##
## A mine's unit is its running cost at that site (labour and maintenance with the site's M once it is
## counted, power at the grid price), plus the haul to the consumer, plus its build fee, materials and land
## spread over CAPEX_TURNS, over what it digs a turn. Local Suppliers' unit is their buy quote for a turn of
## the consumer's need, fees included, over that need.

const MiningSites := preload("res://scripts/mining_sites.gd")
const Middleman := preload("res://scripts/middleman_service.gd")
const Contract := preload("res://scripts/middleman_contract.gd")
const LandPrice := preload("res://scripts/land_price.gd")
const BuildForecast := preload("res://scripts/build_forecast.gd")
const ConstructionRules := preload("res://scripts/construction_rules.gd")

## The turns a new mine's build cost is spread over.
const CAPEX_TURNS := 30
const MINE := "b_001"


## The choice for the building `consumer` short of `good_id`: {choice ("mine" or "local_suppliers"), tile (the
## mine's, "" for none), recipe_id, mine_unit (INF with no site), ls_unit, need}. Tiles in `exclude` are skipped.
static func choose(consumer: Dictionary, good_id: String, exclude: Array = []) -> Dictionary:
	var need := _need(consumer, good_id)
	var ls_unit := local_suppliers_unit(consumer, good_id, need)
	var site := nearest_site(str(consumer.get("tile_id", "")), good_id, exclude)
	var mine_unit := INF
	if not site.is_empty():
		mine_unit = mine_unit_cost(str(site.tile), str(site.recipe_id), str(consumer.get("tile_id", "")), good_id)
	return {"choice": "mine" if mine_unit < ls_unit else "local_suppliers", "tile": str(site.get("tile", "")),
		"recipe_id": str(site.get("recipe_id", "")), "mine_unit": mine_unit, "ls_unit": ls_unit, "need": need}


## What `consumer` uses of `good_id` a turn.
static func _need(consumer: Dictionary, good_id: String) -> int:
	for item: Dictionary in Catalog.get_recipe(str(consumer.get("recipe_id", ""))).get("inputs", []):
		if str(item.get("good_id", "")) == good_id:
			return maxi(1, roundi(Production._modified_input_qty(item, consumer) * MatchState.run_multiplier(consumer)))
	return 1


## Local Suppliers' delivered price a unit of `good_id` at the consumer's tile, for `qty` units.
static func local_suppliers_unit(consumer: Dictionary, good_id: String, qty: int) -> float:
	var q := Contract.quote("buy", [{"good": good_id, "quantity": qty}], Middleman.prices(), Middleman.coefficient(consumer),
		Middleman.goods())
	return float(q.get("cash_out", INF)) / float(qty) if bool(q.get("ok", false)) else INF


## The nearest land tile to `near` with a deposit of `good_id` left, where one more level 1 mine keeps the seam
## within its free amount: {tile, recipe_id, distance}, or {} for none.
static func nearest_site(near: String, good_id: String, exclude: Array = []) -> Dictionary:
	var token := str(Catalog.get_good(good_id).get("internal_name", ""))
	var recipe_id := mining_recipe(token)
	if recipe_id == "":
		return {}
	var best := {}
	for tile_id: String in Catalog.all_tile_ids():
		if tile_id in exclude or Catalog.tile_type(tile_id) in ["sea", "deep_sea"]:
			continue
		if not _has_deposit(tile_id, token) or MatchState.deposit_depleted(tile_id, token):
			continue
		var after := MiningSites.site_after(MINE, recipe_id, tile_id, 1)
		if float(after.get("draw", 0.0)) > float(after.get("free", 0.0)) + 0.001:
			continue
		var d := Catalog.tile_hex_distance(near, tile_id)
		if best.is_empty() or d < int(best.distance) or (d == int(best.distance) and tile_id < str(best.tile)):
			best = {"tile": tile_id, "recipe_id": recipe_id, "distance": d}
	return best


## The recipe that mines `token`, or "".
static func mining_recipe(token: String) -> String:
	for r: Variant in Catalog.get_recipes_for_building(MINE):
		var recipe: Dictionary = r if r is Dictionary else Catalog.get_recipe(str(r))
		if MiningSites.token_of(recipe) == token:
			return str(recipe.get("recipe_id", ""))
	return ""


static func _has_deposit(tile_id: String, token: String) -> bool:
	for part: String in Catalog.tile_deposits_raw(tile_id).split("|"):
		if part.get_slice("(", 0).strip_edges() == token:
			return true
	return false


## A new level 1 mine's cost a unit delivered to `to_tile`: running cost with the site's M once it is counted,
## the haul, and its build cost spread over CAPEX_TURNS. INF when it would dig nothing.
static func mine_unit_cost(tile_id: String, recipe_id: String, to_tile: String, good_id: String) -> float:
	var p := mine_unit_parts(tile_id, recipe_id, to_tile, good_id)
	if float(p.units) <= 0.0:
		return INF
	return (float(p.running) + float(p.haul) + float(p.capex) / float(CAPEX_TURNS)) / float(p.units)


## The figures mine_unit_cost is made of, a turn: {units, running, haul, capex}.
static func mine_unit_parts(tile_id: String, recipe_id: String, to_tile: String, good_id: String) -> Dictionary:
	var recipe := Catalog.get_recipe(recipe_id)
	var probe := {"instance_id": "", "building_id": MINE, "recipe_id": recipe_id, "tile_id": tile_id, "level": 1,
		"owner": MatchState.LOCAL_PLAYER}
	var token := MiningSites.token_of(recipe)
	var units := float(BuildForecast._permanent_output_qty(recipe_id, good_id, token, roundi(MiningSites.base_rate(recipe)))) \
		* MatchState.throughput_multiplier(probe)
	var running := Production._calculate_labour_cost(probe, recipe) + Production._calculate_maintenance_cost(probe) \
		+ float(Production._effective_energy_req(probe, recipe)) * Power.grid_import_price()
	var haul := 0.0
	if to_tile != tile_id and units > 0.0:
		var leg := TransportService.route(tile_id, to_tile, good_id)
		haul = TransportService.transport_cost_for_route(good_id, roundi(units), leg) if int(leg.get("turns", 1 << 30)) < (1 << 30) else INF
	return {"units": units, "running": running, "haul": haul, "capex": capex(tile_id)}


## A new mine's build fee, its materials through Local Suppliers and the land it lacks on `tile_id`.
static func capex(tile_id: String) -> float:
	var fee := ConstructionRules.build_fee(MINE, 1.0)
	var materials := Construction.estimate_middleman_cost(tile_id, MINE)
	var short := Catalog.land_units(Catalog.get_building(MINE)) + BuildingState.get_tile_player_space_used(tile_id) \
		- float(BuildingState.get_tile_land_owned(tile_id))
	var land := 0.0
	if short > 0.0:
		land = float(LandPrice.quote(tile_id, ceili(short / float(BuildingState.LAND_PATCH_SIZE)), false).get("total", 0.0))
	return fee + materials + land
