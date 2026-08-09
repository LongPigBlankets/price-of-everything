extends RefCounted
## Projects the per-turn cash effect of a building the player is about to construct, so the
## construct panel can show the shape of the commitment BEFORE the money is spent.
##
## The first playtest (2026-08-08) had a player double their smelting capacity and go from
## +£27/turn to −£106/turn in a single turn, with nothing in the UI to warn them. That is the
## failure this exists to prevent — see docs/early-game-onboarding-spec.md §5.1.
##
## Deliberately a FORECAST, not a simulation. Stated assumptions, held constant:
##   * output sells straight to market at today's price (no glut drift, no contracts)
##   * pipes / reinforced pipes are already built where the recipe needs them
##   * inputs are bought from the market at today's buy price every producing turn
##   * prices do not move over the window
## Everything it charges is charged by the engine too; the numbers come from the same
## helpers production.gd uses, so the forecast and the real turn cannot silently diverge.

const WINDOW_TURNS := 10

## Returns:
##   points        Array[float] — net cash effect per turn, index 0 = next turn
##   build_turns   int          — leading turns still under construction (net 0)
##   sale_delay    int          — turns between producing and the money landing
##   steady_net    float        — the per-turn net once revenue is flowing
##   first_profit  int          — index of the first positive point, or -1
##   payback_turn  int          — 1-based turn where cumulative net clears capex, or -1
##   capex         float        — construction cost, for the payback calculation
##   no_supply     bool         — the recipe needs inputs and this tile has no route to any
##   input_names   Array[String]— unroutable inputs, for the warning line
static func project(building_id: String, recipe_id: String, tile_id: String) -> Dictionary:
	var building_def: Dictionary = Catalog.get_building(building_id)
	var recipe: Dictionary = Catalog.get_recipe(recipe_id)
	var out := {
		"points": [], "build_turns": 0, "sale_delay": 1, "steady_net": 0.0,
		"first_profit": -1, "payback_turn": -1, "capex": 0.0,
		"no_supply": false, "input_names": [],
	}
	if building_def.is_empty() or recipe.is_empty():
		return out

	# A stand-in for the finished building. The cost helpers only read these fields, so the
	# forecast prices the same building the engine will.
	var probe := {
		"instance_id": "", "building_id": building_id, "recipe_id": recipe_id,
		"tile_id": tile_id, "level": 1,
	}

	var revenue: float = 0.0
	for item in Production._recipe_output_items(recipe):
		var gid := str(item.get("good_id", ""))
		if gid == "" and str(item.get("internal_name", "")) != "":
			gid = str(Catalog.get_good_by_internal_name(str(item.get("internal_name", ""))).get("id", ""))
		if gid != "":
			revenue += float(item.get("qty", 0)) * MarketState.get_price(gid)

	var input_cost: float = 0.0
	var unroutable: Array[String] = []
	for item in recipe.get("inputs", []):
		var gid := str(item.get("good_id", ""))
		if gid == "":
			continue
		input_cost += float(item.get("qty", 0)) * MarketState.get_buy_price(gid)
		if tile_id != "" and not _input_reachable(tile_id, gid):
			unroutable.append(str(Catalog.get_good(gid).get("display_name", gid)))

	var power_cost := float(Production._effective_energy_req(probe, recipe)) * EconomyConfig.GRID_BUY_PRICE
	var running_cost: float = input_cost + power_cost \
			+ Production._calculate_labour_cost(probe, recipe) \
			+ Production._calculate_maintenance_cost(probe)

	var build_turns: int = maxi(0, MatchState.effective_build_duration(building_id))
	var sale_delay: int = _sale_delay(tile_id)
	var capex: float = float(Construction.estimate_market_cost(tile_id, building_id))

	# Under construction: nothing produced, nothing owed. Then costs start on the first
	# producing turn while revenue is still in transit — that gap IS the dip players fall into.
	var points: Array[float] = []
	for i in range(WINDOW_TURNS):
		if i < build_turns:
			points.append(0.0)
			continue
		var producing_turn: int = i - build_turns
		var net: float = -running_cost
		if producing_turn >= sale_delay:
			net += revenue
		points.append(net)

	var first_profit := -1
	var cumulative: float = 0.0
	var payback := -1
	for i in points.size():
		if first_profit < 0 and points[i] > 0.0:
			first_profit = i
		cumulative += points[i]
		if payback < 0 and cumulative >= capex and capex > 0.0:
			payback = i + 1

	out.points = points
	out.build_turns = build_turns
	out.sale_delay = sale_delay
	out.steady_net = revenue - running_cost
	out.first_profit = first_profit
	out.payback_turn = payback
	out.capex = capex
	out.no_supply = not unroutable.is_empty()
	out.input_names = unroutable
	return out


## Can this tile get the good at all — from its own stock, a tile that has it, or the port?
## Only a routing question; affordability is the player's problem and the chart's dip.
static func _input_reachable(tile_id: String, good_id: String) -> bool:
	if Stockpile.get_at_tile(tile_id, good_id) > 0:
		return true
	var source: Dictionary = Construction.find_source_tile(tile_id, {good_id: 1})
	if not source.is_empty() and str(source.get("tile_id", "")) != "":
		return true
	var port := TransportService.nearest_port_tile(tile_id)
	if port == "":
		return false
	return TransportService.route_is_reachable(TransportService.route(tile_id, port, good_id))


## Turns between producing a good and the cash landing: the haul to the port, floored at 1
## so the forecast never promises same-turn money.
static func _sale_delay(tile_id: String) -> int:
	if tile_id == "":
		return 1
	var port := TransportService.nearest_port_tile(tile_id)
	if port == "":
		return 1
	var route: Dictionary = TransportService.route(tile_id, port)
	if not TransportService.route_is_reachable(route):
		return 1
	return maxi(1, int(route.get("turns", 1)))
