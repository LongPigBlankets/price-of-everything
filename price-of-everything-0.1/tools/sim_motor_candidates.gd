extends SceneTree
# Search compact motor-chain layouts under live production/economy rules.
#
# Run:
#   <godot> --headless --path . --script res://tools/sim_motor_candidates.gd -- [turns]

const DEFAULT_TURNS := 100
const STARTING_CASH := 50000.0
const PORT_INFRA := ["roads", "rail", "cables"]
const MAX_PLACEMENTS := 4

var MatchState: Node
var Stockpile: Node
var MarketState: Node
var Catalog: Node
var Production: Node
var TurnManager: Node
var RunMetrics: Node
var LoanState: Node
var TransportService: Node
var Construction: Node

var _deposits: Dictionary = {}
var _turn_times_ms: Array[float] = []
var _stub: Node = null
var _base_tile_infra: Dictionary = {}


func _initialize() -> void:
	_resolve()
	await process_frame
	await process_frame
	_base_tile_infra = (Catalog.get("_tile_infra") as Dictionary).duplicate(true)
	var turns := _requested_turns()
	_load_deposits()
	var candidates := _build_candidates()
	var results: Array = []
	for candidate in candidates:
		var result := await _run_candidate(candidate, turns)
		results.append(result)
	results.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if bool(a.get("profitable", false)) != bool(b.get("profitable", false)):
			return bool(a.get("profitable", false))
		if not is_equal_approx(float(a.get("profit_post_tax", -INF)), float(b.get("profit_post_tax", -INF))):
			return float(a.get("profit_post_tax", -INF)) > float(b.get("profit_post_tax", -INF))
		return int(a.get("building_count", 0)) < int(b.get("building_count", 0))
	)
	print("\n==== MOTOR CANDIDATE SEARCH (%d turns) ====" % turns)
	for row in results.slice(0, mini(16, results.size())):
		print("%s" % JSON.stringify(row))
	print("==== DONE MOTOR CANDIDATE SEARCH ====\n")
	quit(0)


func _resolve() -> void:
	var r := get_root()
	MatchState = r.get_node("MatchState")
	Stockpile = r.get_node("Stockpile")
	MarketState = r.get_node("MarketState")
	Catalog = r.get_node("Catalog")
	Production = r.get_node("Production")
	TurnManager = r.get_node("TurnManager")
	RunMetrics = r.get_node("RunMetrics")
	LoanState = r.get_node("LoanState")
	TransportService = r.get_node("TransportService")
	Construction = r.get_node("Construction")


func _requested_turns() -> int:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and str(args[0]).is_valid_int():
		return maxi(1, int(args[0]))
	return DEFAULT_TURNS


func _reset_state() -> void:
	TurnManager.fast_mode = true
	TurnManager.phase_pause_duration = 0.0
	TurnManager.reset_for_test()
	MatchState.reset()
	Stockpile.clear_all()
	Construction.construction_projects.clear()
	LoanState.loans.clear()
	LoanState.set("_next_loan_id", 1)
	LoanState.set("_profit_history", [])
	LoanState.set("_revenue_history", [])
	LoanState.last_payment_total = 0.0
	Production.last_turn_summary.clear()
	Production.last_turn_run.clear()
	Production.missing_by_building.clear()
	Production.produced_by_building.clear()
	Production.full_output_streak_by_building.clear()
	MarketState.prices.clear()
	for good in Catalog.all_goods():
		MarketState.prices[str(good.get("id", ""))] = float(good.get("base_price", 1.0))
	Catalog.set("_tile_infra", _base_tile_infra.duplicate(true))
	Catalog.set("_route_cache", {})
	if RunMetrics != null and RunMetrics.has_method("reset"):
		RunMetrics.reset()
	if _stub == null:
		_stub = _HexMapStub.new()
		get_root().add_child(_stub)
	else:
		_stub.set("tiles", {})
	MatchState.money = STARTING_CASH
	MatchState.money_changed.emit(MatchState.money)
	_turn_times_ms.clear()


func _load_deposits() -> void:
	_deposits.clear()
	var file := FileAccess.open("res://data/tile_properties.csv", FileAccess.READ)
	if file == null:
		return
	file.get_csv_line()
	while not file.eof_reached():
		var line := file.get_csv_line()
		if line.size() < 4 or str(line[0]) == "":
			continue
		var tile_id := str(line[0])
		if not Catalog.is_land_tile(tile_id):
			continue
		for raw_dep in str(line[3]).split("|"):
			var dep := str(raw_dep).strip_edges()
			var p := dep.find("(")
			if p >= 0:
				dep = dep.substr(0, p)
			if dep == "":
				continue
			if not _deposits.has(dep):
				_deposits[dep] = []
			_deposits[dep].append(tile_id)
	file.close()


func _build_candidates() -> Array:
	var ratios := [
		{"name": "minimal_8", "coal": 1, "iron": 1, "copper": 1, "pig": 1, "steel": 1, "copper_furnace": 1, "wire": 1, "motor": 1},
		{"name": "ore_balanced_10", "coal": 1, "iron": 2, "copper": 2, "pig": 1, "steel": 1, "copper_furnace": 1, "wire": 1, "motor": 1},
		{"name": "coal_ore_11", "coal": 2, "iron": 2, "copper": 2, "pig": 1, "steel": 1, "copper_furnace": 1, "wire": 1, "motor": 1},
		{"name": "motor2_14", "coal": 1, "iron": 2, "copper": 3, "pig": 1, "steel": 1, "copper_furnace": 2, "wire": 2, "motor": 2},
		{"name": "motor2_coal_15", "coal": 2, "iron": 2, "copper": 3, "pig": 1, "steel": 1, "copper_furnace": 2, "wire": 2, "motor": 2},
	]
	var placements: Array = []
	for port in Catalog.all_ports():
		var port_tile := str(port.get("tile_id", ""))
		var coal_tiles := _nearest_deposit_tiles("coal", port_tile, 5)
		var iron_tiles := _nearest_deposit_tiles("iron_ore", port_tile, 5)
		var copper_tiles := _nearest_deposit_tiles("copper_ore", port_tile, 5)
		for coal in coal_tiles:
			for iron in iron_tiles:
				for copper in copper_tiles:
					if coal == "" or iron == "" or copper == "":
						continue
					for central in ["iron", "copper"]:
						var motor_tile := str(iron) if central == "iron" else str(copper)
						var score: int = Catalog.tile_hex_distance(str(coal), str(iron)) \
							+ Catalog.tile_hex_distance(str(iron), motor_tile) \
							+ Catalog.tile_hex_distance(str(copper), motor_tile) \
							+ Catalog.tile_hex_distance(motor_tile, port_tile)
						placements.append({
							"port_name": str(port.get("name", "")),
							"port": port_tile,
							"coal_tile": coal,
							"iron_tile": iron,
							"copper_tile": copper,
							"central": central,
							"score": score,
						})
	placements.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("score", 9999)) < int(b.get("score", 9999))
	)
	var out: Array = []
	for placement in placements.slice(0, mini(MAX_PLACEMENTS, placements.size())):
		for ratio in ratios:
			var row: Dictionary = placement.duplicate(true)
			row["ratio"] = ratio
			row["name"] = "%s_%s_%s_%s_%s" % [
				str(placement.get("port_name", "")),
				str(ratio.name),
				str(placement.get("central", "")),
				str(placement.get("iron_tile", "")),
				str(placement.get("copper_tile", "")),
			]
			out.append(row)
	return out


func _nearest_deposit_tiles(dep: String, port_tile: String, limit: int) -> Array:
	var tiles: Array = (_deposits.get(dep, []) as Array).duplicate()
	tiles.sort_custom(func(a, b) -> bool:
		return Catalog.tile_hex_distance(str(a), port_tile) < Catalog.tile_hex_distance(str(b), port_tile)
	)
	return tiles.slice(0, mini(limit, tiles.size()))


func _run_candidate(candidate: Dictionary, turns: int) -> Dictionary:
	_reset_state()
	await process_frame
	await process_frame
	var ids := _ids()
	var ratio: Dictionary = candidate.ratio
	var coal_tile := str(candidate.coal_tile)
	var iron_tile := str(candidate.iron_tile)
	var copper_tile := str(candidate.copper_tile)
	var motor_tile := iron_tile if str(candidate.central) == "iron" else copper_tile
	var build_spend := 0.0
	var infra_spend := 0.0
	for tile_id in [coal_tile, iron_tile, copper_tile, motor_tile, str(candidate.port)]:
		infra_spend += _add_infra(tile_id, PORT_INFRA)
	infra_spend += _add_corridor(coal_tile, iron_tile, "rail")
	infra_spend += _add_corridor(copper_tile, motor_tile, "rail")
	infra_spend += _add_corridor(iron_tile, motor_tile, "rail")
	infra_spend += _add_corridor(motor_tile, str(candidate.port), "rail")

	for i in int(ratio.coal):
		build_spend += _place(ids.mine, ids.coal_mining, coal_tile)
	for i in int(ratio.iron):
		build_spend += _place(ids.mine, ids.iron_mining, iron_tile)
	for i in int(ratio.copper):
		build_spend += _place(ids.mine, ids.copper_mining, copper_tile)
	for i in int(ratio.pig):
		build_spend += _building_cost(ids.furnace)
		var inst: String = str(_place(ids.furnace, ids.pig_iron, iron_tile, true))
		_set_tile_only(inst, [ids.iron_ore, ids.coal])
	for i in int(ratio.steel):
		build_spend += _building_cost(ids.furnace)
		var inst: String = str(_place(ids.furnace, ids.steel, iron_tile, true))
		_set_tile_only(inst, [ids.iron_ingots, ids.coal])
		_route(inst, ids.steel, motor_tile)
	for i in int(ratio.copper_furnace):
		build_spend += _building_cost(ids.furnace)
		var inst: String = str(_place(ids.furnace, ids.copper_ingots, copper_tile, true))
		_set_tile_only(inst, [ids.copper_ore])
	for i in int(ratio.wire):
		build_spend += _building_cost(ids.factory)
		var inst: String = str(_place(ids.factory, ids.copper_wiring, copper_tile, true))
		_set_tile_only(inst, [ids.copper_ingots])
		_route(inst, ids.copper_wiring, motor_tile)
	for i in int(ratio.motor):
		build_spend += _building_cost(ids.factory)
		var inst: String = str(_place(ids.factory, ids.motor, motor_tile, true))
		_set_tile_only(inst, [ids.steel, ids.copper_wiring])
		MatchState.route_output_to_market(inst, ids.motor)

	for inst in MatchState.get_buildings_on_tile(coal_tile):
		var b: Dictionary = MatchState.get_building(str(inst))
		if str(b.get("recipe_id", "")) == ids.coal_mining:
			_route(str(inst), ids.coal, iron_tile)
	for tile_id in [coal_tile, iron_tile, copper_tile, motor_tile]:
		MatchState.set_auto_sell_impact(tile_id, MatchState.IMPACT_ANY)
		MatchState.enable_sell_surplus(tile_id)

	var cash_after_build: float = MatchState.money
	for _i in range(turns):
		var t0 := Time.get_ticks_usec()
		TurnManager.commit_turn()
		await TurnManager.turn_resolution_completed
		_turn_times_ms.append(float(Time.get_ticks_usec() - t0) / 1000.0)
	var rows: Array = RunMetrics.read_rows() if RunMetrics.has_method("read_rows") else []
	var totals := _summarise_rows(rows)
	var stats := _stats(_turn_times_ms)
	return {
		"name": candidate.name,
		"profitable": float(totals.profit_post_tax) > 0.0,
		"profit_post_tax": snappedf(float(totals.profit_post_tax), 0.01),
		"revenue": snappedf(float(totals.revenue), 0.01),
		"final_cash": snappedf(MatchState.money, 0.01),
		"cash_delta_after_build": snappedf(MatchState.money - cash_after_build, 0.01),
		"build_spend": snappedf(build_spend, 0.01),
		"infra_spend": snappedf(infra_spend, 0.01),
		"building_count": MatchState.buildings.size(),
		"coal": coal_tile,
		"iron": iron_tile,
		"copper": copper_tile,
		"motor": motor_tile,
		"avg_starved": snappedf(float(totals.starved_count) / float(maxi(rows.size(), 1)), 0.01),
		"most_missing": totals.most_missing,
		"capacity_lost": int(totals.capacity_lost),
		"turn_mean_ms": snappedf(float(stats.mean), 0.01),
		"turn_p95_ms": snappedf(float(stats.p95), 0.01),
	}


func _ids() -> Dictionary:
	var ids := {}
	for internal in ["coal", "iron_ore", "copper_ore", "iron_ingots", "copper_ingots", "steel", "copper_wiring", "motor"]:
		ids[internal] = str(Catalog.get_good_by_internal_name(internal).get("id", ""))
	ids.mine = str(Catalog.get_building_by_internal_name("mine").get("id", ""))
	ids.furnace = str(Catalog.get_building_by_internal_name("furnace").get("id", ""))
	ids.factory = str(Catalog.get_building_by_internal_name("industrial_factory").get("id", ""))
	ids.coal_mining = _recipe_for(ids.mine, ids.coal)
	ids.iron_mining = _recipe_for(ids.mine, ids.iron_ore)
	ids.copper_mining = _recipe_for(ids.mine, ids.copper_ore)
	ids.pig_iron = _recipe_for(ids.furnace, ids.iron_ingots)
	ids.steel = _recipe_for(ids.furnace, ids.steel)
	ids.copper_ingots = _recipe_for(ids.furnace, ids.copper_ingots)
	ids.copper_wiring = _recipe_for(ids.factory, ids.copper_wiring)
	ids.motor = _recipe_for(ids.factory, ids.motor)
	return ids


func _recipe_for(building_id: String, output_id: String) -> String:
	for recipe in Catalog.all_recipes():
		if str(recipe.get("building_id", "")) == building_id and Catalog.recipe_produces(recipe, output_id):
			return str(recipe.get("recipe_id", ""))
	return ""


func _place(building_id: String, recipe_id: String, tile_id: String, return_id: bool = false):
	var cost := float(Catalog.get_building(building_id).get("base_price", 0.0))
	MatchState.add_money(-cost)
	var inst: String = str(MatchState.add_building(building_id, recipe_id, tile_id))
	return inst if return_id else cost


func _building_cost(building_id: String) -> float:
	return float(Catalog.get_building(building_id).get("base_price", 0.0))


func _set_tile_only(instance_id: String, goods: Array) -> void:
	for good_id in goods:
		MatchState.set_input_tile_only(instance_id, str(good_id), true)


func _route(instance_id: String, good_id: String, tile_id: String) -> void:
	if tile_id != str(MatchState.get_building(instance_id).get("tile_id", "")):
		MatchState.set_output_stockpile_destination(instance_id, tile_id, good_id)


func _add_infra(tile_id: String, infra_types: Array) -> float:
	var cost := 0.0
	for infra in infra_types:
		if str(infra) == "cables" and _stub != null:
			_stub.call("set_cabled_tile", tile_id)
		if not Catalog.tile_has_infrastructure(tile_id, str(infra)):
			Catalog.add_tile_infrastructure(tile_id, str(infra))
			var internal := "rails" if str(infra) == "rail" else str(infra)
			var bid := str(Catalog.get_building_by_internal_name(internal).get("id", ""))
			cost += float(Catalog.get_building(bid).get("base_price", 0.0))
			MatchState.add_money(-float(Catalog.get_building(bid).get("base_price", 0.0)))
	return cost


func _add_corridor(src: String, dst: String, infra: String) -> float:
	if src == "" or dst == "":
		return 0.0
	var cost := 0.0
	for tile_id in _tile_path(src, dst):
		cost += _add_infra(str(tile_id), [infra])
	return cost


func _tile_path(src: String, dst: String) -> Array:
	if src == dst:
		return [src]
	var prev: Dictionary = {src: ""}
	var q: Array = [src]
	var head := 0
	while head < q.size():
		var u := str(q[head])
		head += 1
		if u == dst:
			break
		for nb in Catalog.tile_neighbours(u):
			var n := str(nb)
			if prev.has(n):
				continue
			if n != dst and not Catalog.is_land_tile(n):
				continue
			prev[n] = u
			q.append(n)
	if not prev.has(dst):
		return [src, dst]
	var out: Array = [dst]
	var cur := dst
	while cur != src:
		cur = str(prev[cur])
		out.push_front(cur)
	return out


func _summarise_rows(rows: Array) -> Dictionary:
	var out := {"revenue": 0.0, "profit_post_tax": 0.0, "starved_count": 0, "capacity_lost": 0, "most_missing": ""}
	var missing_counts := {}
	for row in rows:
		out.revenue += float(row.get("revenue", "0"))
		out.profit_post_tax += float(row.get("profit_post_tax", "0"))
		out.starved_count += int(row.get("starved_count", "0"))
		out.capacity_lost += int(row.get("capacity_lost", "0"))
		var missing := str(row.get("most_missing_input", ""))
		if missing != "":
			missing_counts[missing] = int(missing_counts.get(missing, 0)) + 1
	var best_count := 0
	for key in missing_counts.keys():
		if int(missing_counts[key]) > best_count:
			best_count = int(missing_counts[key])
			out.most_missing = str(key)
	return out


func _stats(values: Array[float]) -> Dictionary:
	if values.is_empty():
		return {"mean": 0.0, "p95": 0.0}
	var sorted := values.duplicate()
	sorted.sort()
	var sum := 0.0
	for v in sorted:
		sum += float(v)
	var p95_idx := clampi(int(ceil(float(sorted.size()) * 0.95)) - 1, 0, sorted.size() - 1)
	return {"mean": sum / float(sorted.size()), "p95": float(sorted[p95_idx])}


class _HexMapStub extends Node:
	var tiles: Dictionary = {}

	func _enter_tree() -> void:
		add_to_group("hex_map")

	func set_cabled_tile(tile_id: String) -> void:
		tiles[id_to_coord(tile_id)] = {"infrastructure_present": ["cables"]}

	func id_to_coord(id: String) -> Vector2i:
		var p := id.split("_")
		if p.size() != 3 or p[0] != "tile" or not p[1].is_valid_int() or not p[2].is_valid_int():
			return Vector2i(-1, -1)
		return Vector2i(int(p[1]) - 1, int(p[2]) - 1)
