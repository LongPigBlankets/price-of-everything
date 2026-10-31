extends "res://tests/test_base.gd"
## Phase 7 of docs/pacing-labour-mining-licensing-spec.md: freight priced by distance and transport speed (§7.6).
## Each test names the acceptance criteria (AC…) it checks.

const FEATURE := "freight"
const TAGS := {
	"_test_route_cost_is_tiles": ["freight", "transport"],
	"_test_cheapest_route": ["freight", "transport"],
	"_test_equal_cost_takes_fewer_turns": ["freight", "transport"],
	"_test_routing_switch": ["freight", "transport"],
	"_test_routing_switch_saves": ["freight", "transport", "save"],
	"_test_local_suppliers_unchanged": ["freight", "transport", "middleman"],
}

const MiddlemanLocations := preload("res://scripts/middleman_locations.gd")
const COAL := "g_001"
const WATER := "g_009"


func _isolate() -> Dictionary:
	Modifiers.reset()
	var saved := {"infra": Catalog._tile_infra.duplicate(true), "levels": Catalog._tile_infra_levels.duplicate(true),
		"flow": TransportState._last_link_flow.duplicate(true)}
	Catalog.clear_tile_infrastructure()
	TransportState._last_link_flow = {}
	return saved


func _restore(saved: Dictionary) -> void:
	Catalog._tile_infra = saved.infra
	Catalog._tile_infra_levels = saved.levels
	TransportState._last_link_flow = saved.flow
	Catalog._route_cache.clear()


func _lay(tiles: Array, infra: String, level: int = 1) -> void:
	for t in tiles:
		Catalog.add_tile_infrastructure(str(t), infra)
		if level != 1:
			Catalog.set_tile_infra_level(str(t), infra, level)
	Catalog._route_cache.clear()


func _row_chain(row: int, from_col: int, to_col: int) -> Array:
	var chain: Array = []
	for col in range(from_col, to_col + 1):
		chain.append("tile_%d_%d" % [col, row])
	return chain


## AC37.1, AC37.6: the per-tile table, and a route charges tiles x weight x qty x the leg's multiplier.
func _test_per_tile_table() -> void:
	var want := {"roads": [0.5, 1.0 / 3.0, 0.2], "rail": [0.125, 0.5 / 6.0, 0.5 / 9.0], "pipes": [0.5, 1.0 / 3.0, 0.2],
		"reinf_pipes": [0.5, 1.0 / 3.0, 0.2], "nothing": [2.0, 2.0, 2.0]}
	var ok := true
	for mode: String in want:
		for i in 3:
			if not is_equal_approx(EconomyConfig.freight_tile_mult(COAL, mode, i + 1), float(want[mode][i])):
				ok = false
	_check(ok, "AC37.1 per tile: road 0.5/0.333/0.2, rail 0.125/0.083/0.056, pipe 0.5/0.333/0.2, bare ground 2.0")
	_check(is_equal_approx(EconomyConfig.FREIGHT_TILE_SCALE, 1.0), "AC37.6 one scale on every per-tile multiplier, 1.0")
	# A fluid on road or rail pays its tanker premium spread over the same tiles.
	_check(is_equal_approx(EconomyConfig.freight_tile_mult(WATER, "rail", 1), 3.0 / 4.0)
			and is_equal_approx(EconomyConfig.freight_tile_mult(WATER, "roads", 3), 6.0 / 5.0),
		"AC37.1 a safe fluid pays 3/4 a rail tile at L1 and 6/5 a road tile at L3")
	var rate := EconomyConfig.transport_rate_for_good(COAL)
	var route := {"legs": [{"mode": "roads", "tiles": 3, "level": 2}, {"mode": "rail", "tiles": 5, "level": 1}]}
	var want_cost := 10.0 * rate * (3.0 / 3.0 + 5.0 * 0.125)
	_check(is_equal_approx(EconomyConfig.transport_cost_for_route(COAL, 10, route), want_cost),
		"AC37.1 a route is the sum over legs of tiles x weight x qty x the per-tile multiplier")


## AC37.2, AC37.3, AC37.4: a whole old leg keeps its price, a part leg pays for its tiles, a straight haul pays bare
## ground on its tile distance.
func _test_calibration() -> void:
	var rate := EconomyConfig.transport_rate_for_good(COAL)
	# Before: every leg cost qty x rate x the mode multiplier (road 1, rail 0.5), whatever it reached.
	var whole := [["roads", 1, 2, 1.0], ["roads", 2, 3, 1.0], ["roads", 3, 5, 1.0], ["rail", 1, 4, 0.5], ["rail", 2, 6, 0.5],
		["rail", 3, 9, 0.5], ["pipes", 1, 2, 1.0], ["pipes", 3, 5, 1.0]]
	var ok := true
	for w: Array in whole:
		var cost := EconomyConfig.transport_cost_for_route(COAL, 100, {"legs": [{"mode": w[0], "tiles": w[2], "level": w[1]}]})
		if not is_equal_approx(cost, 100.0 * rate * float(w[3])):
			ok = false
	_check(ok, "AC37.2 a whole leg at its old reach costs what it did, every mode and level")
	var water_rate := EconomyConfig.transport_rate_for_good(WATER)
	var water_rail := EconomyConfig.transport_cost_for_route(WATER, 100, {"legs": [{"mode": "rail", "tiles": 9, "level": 3}]})
	_check(is_equal_approx(water_rail, 100.0 * water_rate * 3.0), "AC37.2 a whole L3 rail tanker leg (9 tiles) costs its old 3x")
	var part := EconomyConfig.transport_cost_for_route(COAL, 100, {"legs": [{"mode": "roads", "tiles": 3, "level": 1}]})
	_check(is_equal_approx(part, 1.5 * 100.0 * rate), "AC37.3 3 road tiles at L1 cost 1.5 old legs, not 2")
	var straight := EconomyConfig.transport_cost_for_route(COAL, 10, {"legs": [], "tile_distance": 4})
	_check(is_equal_approx(straight, 4.0 * 2.0 * 10.0 * rate), "AC37.4 a straight-line haul pays bare ground per tile")


## AC37.5: the Resources panel's per-tile quote, times the tiles, is what a one-mode route charges with no research
## and no congestion.
func _test_route_cost_is_tiles() -> void:
	var saved := _isolate()
	var chain := _row_chain(5, 5, 10)
	_lay(chain, "roads", 2)
	var route := TransportService.route(str(chain[0]), str(chain[-1]), COAL)
	var tiles := 0
	for leg: Dictionary in route.get("legs", []):
		tiles += int(leg.get("tiles", 0))
	var charged := TransportService.transport_cost_for_route(COAL, 50, route)
	var quoted := TransportService.freight_per_tile(COAL, "roads", 2) * float(tiles) * 50.0
	_check(tiles == 5 and charged > 0.0 and is_equal_approx(charged, quoted),
		"AC37.5 the per-tile quote x 5 tiles is the charge (%.4f vs %.4f)" % [quoted, charged])
	var parts := TransportService.transport_cost_breakdown_for_route(COAL, 50, route)
	_check(parts.size() == 1 and is_equal_approx(float(parts.get("roads", 0.0)), charged), "AC37.5 the breakdown adds back to the charge")
	_restore(saved)


## AC38.1: speed sets the turns, not the price.
func _test_speed_sets_turns() -> void:
	var saved := _isolate()
	var chain := _row_chain(5, 5, 10)   # 5 steps
	_lay(chain, "roads")
	var by_level := []
	for level in [1, 2, 3]:
		for t in chain:
			Catalog.set_tile_infra_level(str(t), "roads", level)
		Catalog._route_cache.clear()
		by_level.append(int(Catalog.route(str(chain[0]), str(chain[-1]), COAL).get("turns", -1)))
	_check(by_level == [5, 3, 2], "AC38.1 5 road tiles take 5 / 3 / 2 turns at L1 / L2 / L3 (got %s)" % str(by_level))
	_check(EconomyConfig.transport_turns_for_tile_distance(5) == 5, "AC39.2 a straight haul takes a turn a tile over bare ground")
	_restore(saved)


## AC38.2 (owner ruling): the cheapest route. A level 1 road around a tile is taken over the straight run of bare
## ground through it, though it is a turn slower; rail is taken over road on the same line.
func _test_cheapest_route() -> void:
	var saved := _isolate()
	var picked := _straight_and_detour()
	_check(not picked.is_empty(), "AC38.2 found three land tiles in a column with a land detour")
	if picked.is_empty():
		_restore(saved)
		return
	var detour: Array = picked.detour
	_lay(detour, "roads")
	var route: Dictionary = Catalog.route(str(picked.src), str(picked.dst), COAL)
	var all_road := not (route.get("legs", []) as Array).is_empty()
	for leg: Dictionary in route.get("legs", []):
		all_road = all_road and str(leg.get("mode", "")) == "roads"
	_check(all_road and int(route.get("turns", -1)) == detour.size() - 1,
		"AC38.2 the %d-tile road is taken over 2 tiles of bare ground (legs %s, %d turns)" % [detour.size() - 1,
			str((route.get("legs", []) as Array).map(func(l: Dictionary) -> String: return str(l.mode))), int(route.get("turns", -1))])
	var road_cost := EconomyConfig.transport_cost_for_route(COAL, 10, route)
	var bare_cost := EconomyConfig.transport_cost_for_route(COAL, 10, {"legs": [], "tile_distance": 2})
	_check(road_cost < bare_cost, "AC38.2 and it is the cheaper (%.3f vs %.3f)" % [road_cost, bare_cost])
	# Rail beside road on one line: rail is cheaper a tile, so the whole run goes by rail.
	Catalog.clear_tile_infrastructure()
	var chain := _row_chain(5, 5, 11)
	_lay(chain, "roads")
	_lay(chain, "rails")
	var modes := {}
	for leg: Dictionary in Catalog.route(str(chain[0]), str(chain[-1]), COAL).get("legs", []):
		modes[str(leg.get("mode", ""))] = true
	_check(modes.keys() == ["rail"], "AC38.2 rail is taken over road on the same line (got %s)" % str(modes.keys()))
	_restore(saved)


## AC38.2: between routes that cost the same, the one with fewer turns. A level 2 road charges the same a tile
## whichever way its 4 tiles are split into turn-moves; the route takes 2 turns, not 4.
func _test_equal_cost_takes_fewer_turns() -> void:
	var saved := _isolate()
	var chain := _row_chain(5, 5, 9)
	_lay(chain, "roads", 2)
	var route: Dictionary = Catalog.route(str(chain[0]), str(chain[-1]), COAL)
	_check(int(route.get("turns", -1)) == 2, "AC38.2 equal cost: 4 L2 road tiles in 2 turns (got %d)" % int(route.get("turns", -1)))
	var tiles_ok := true
	for leg: Dictionary in route.get("legs", []):
		tiles_ok = tiles_ok and int(leg.get("tiles", 0)) == 2 and int(leg.get("level", 0)) == 2
	_check(tiles_ok, "AC38.2 each leg records its tiles and the level it leaves from")
	_restore(saved)


## AC38.6: the Routing switch. Beside a straight run of bare ground, a cheaper road detour a turn slower: Fastest
## takes the bare ground, Cheapest (the default) and Blended the road. Each setting keeps its own cached route, and a
## fluid still goes by pipe first under Fastest.
func _test_routing_switch() -> void:
	var saved := _isolate()
	var was := MatchState.route_objective
	MatchState.reset()
	_check(MatchState.route_objective == MatchState.RouteObjective.CHEAPEST, "AC38.6 a new game routes by Cheapest")
	var picked := _straight_and_detour()
	_check(not picked.is_empty(), "AC38.6 found three land tiles in a column with a land detour")
	if picked.is_empty():
		MatchState.set_route_objective(was)
		_restore(saved)
		return
	_lay(picked.detour, "roads")
	var src := str(picked.src)
	var dst := str(picked.dst)
	var routes := {}
	for objective: int in [MatchState.RouteObjective.CHEAPEST, MatchState.RouteObjective.FASTEST, MatchState.RouteObjective.BLENDED]:
		MatchState.set_route_objective(objective)
		var r: Dictionary = Catalog.route(src, dst, COAL)
		routes[objective] = {"turns": int(r.get("turns", -1)), "cost": EconomyConfig.transport_cost_for_route(COAL, 10, r),
			"modes": (r.get("legs", []) as Array).map(func(l: Dictionary) -> String: return str(l.mode))}
	var cheap: Dictionary = routes[MatchState.RouteObjective.CHEAPEST]
	var fast: Dictionary = routes[MatchState.RouteObjective.FASTEST]
	var blend: Dictionary = routes[MatchState.RouteObjective.BLENDED]
	_check(int(cheap.turns) == 3 and (cheap.modes as Array).all(func(m: String) -> bool: return m == "roads"),
		"AC38.6 Cheapest takes the 3 tile road (%s, %d turns)" % [str(cheap.modes), int(cheap.turns)])
	_check(int(fast.turns) == 2 and float(fast.cost) > float(cheap.cost),
		"AC38.6 Fastest takes 2 turns of bare ground at more freight (%s, £%.3f vs £%.3f)" % [str(fast.modes), float(fast.cost), float(cheap.cost)])
	var score := func(r: Dictionary) -> float:
		return 0.5 * float(r.cost) / float(cheap.cost) + 0.5 * float(r.turns) / float(fast.turns)
	_check(str(blend.modes) == str(cheap.modes) and float(score.call(blend)) <= minf(float(score.call(cheap)), float(score.call(fast))) + 0.0001,
		"AC38.6 Blended weighs freight and turns half each and takes the road here (score %.3f, bare ground %.3f)"
			% [float(score.call(blend)), float(score.call(fast))])
	MatchState.set_route_objective(MatchState.RouteObjective.CHEAPEST)
	_check(int(Catalog.route(src, dst, COAL).get("turns", -1)) == 3, "AC38.6 switching back gives the cheapest route again, not a cached fastest one")
	# A fluid stays in its pipes under Fastest, though level 3 rail on the same line is quicker.
	Catalog.clear_tile_infrastructure()
	var chain := _row_chain(5, 5, 11)
	_lay(chain, "pipes")
	_lay(chain, "rails", 3)
	MatchState.set_route_objective(MatchState.RouteObjective.FASTEST)
	var piped := true
	for leg: Dictionary in Catalog.route(str(chain[0]), str(chain[-1]), WATER).get("legs", []):
		piped = piped and EconomyConfig.PIPE_MODES.has(str(leg.get("mode", "")))
	_check(piped, "AC38.6 a fluid still goes by pipe first under Fastest")
	MatchState.set_route_objective(was)
	_restore(saved)


## AC38.7: a save from before the switch worked (version 18 or older) loads on Cheapest whatever it shows; a newer
## save keeps its setting.
func _test_routing_switch_saves() -> void:
	var was := MatchState.route_objective
	var old: Dictionary = SaveLoad._migrate({"save_version": 18, "match": {"route_objective": MatchState.RouteObjective.FASTEST}})
	_check(int(old.save_version) == SaveLoad.SAVE_VERSION and int(old.match.route_objective) == MatchState.RouteObjective.CHEAPEST,
		"AC38.7 a version 18 save showing Fastest loads on Cheapest")
	MatchState.set_route_objective(MatchState.RouteObjective.BLENDED)
	var saved: Dictionary = MatchState.export_state()
	MatchState.reset()
	MatchState.import_state(saved)
	_check(MatchState.route_objective == MatchState.RouteObjective.BLENDED, "AC38.7 a current save keeps Blended")
	MatchState.set_route_objective(was)


## AC38.5: a leg saved before freight was priced by distance has no tile count, and is costed on its hex distance.
func _test_old_saved_legs() -> void:
	var rate := EconomyConfig.transport_rate_for_good(COAL)
	var leg := {"mode": "roads", "from": "tile_5_5", "to": "tile_7_5"}
	var hex := Catalog.tile_hex_distance("tile_5_5", "tile_7_5")
	_check(EconomyConfig.leg_tiles(leg) == hex, "AC38.5 a saved leg without tiles reads its hex distance (%d)" % hex)
	var cost := EconomyConfig.transport_cost_for_route(COAL, 10, {"legs": [leg]})
	_check(is_equal_approx(cost, float(hex) * 0.5 * 10.0 * rate), "AC38.5 and is charged per tile at the departure tile's level")


## AC39.1, AC39.2: Local Suppliers count trips on their own constant, so their quotes do not follow transport speed.
func _test_local_suppliers_unchanged() -> void:
	_check(EconomyConfig.LOCAL_SUPPLIERS_TILES_PER_TRIP == 2, "AC39.1 Local Suppliers trips are 2 tiles, as before")
	var ok := true
	var checked := 0
	for tile: String in MiddlemanLocations.factors().keys():
		var hub := MiddlemanLocations.hub_for(tile)
		if hub == "":
			continue
		checked += 1
		var want := maxi(1, ceili(float(Catalog.tile_hex_distance(tile, hub)) / 2.0))
		if MiddlemanLocations.trips(tile) != want or not is_equal_approx(MiddlemanLocations.coefficient(tile),
				float(want) * MiddlemanLocations.settlement_factor(tile)):
			ok = false
	_check(checked > 100 and ok, "AC39.1 every tile's trips and coefficient are unchanged (%d tiles)" % checked)
	_check(is_equal_approx(TransportService.freight_rate(COAL), EconomyConfig.transport_rate_for_good(COAL)),
		"AC39.1 Local Suppliers haul on the unchanged freight rate")
	var offenders: Array = []
	var files: Array[String] = []
	_collect("res://scripts", files)
	for path in files:
		if FileAccess.get_file_as_string(path).find("TRANSPORT_MAX_TILES_PER_TURN") >= 0:
			offenders.append(path)
	_check(offenders.is_empty(), "AC39.2 TRANSPORT_MAX_TILES_PER_TURN is gone %s" % str(offenders))


## Three land tiles straight down a column (src, mid, dst) and the shortest land path between src and dst that avoids
## mid: {src, dst, detour}. Empty when none is found.
func _straight_and_detour() -> Dictionary:
	for col in range(8, 20):
		for row in range(4, 14):
			var src := "tile_%d_%d" % [col, row]
			var mid := "tile_%d_%d" % [col, row + 1]
			var dst := "tile_%d_%d" % [col, row + 2]
			if not (_land(src) and _land(mid) and _land(dst)) or Catalog.tile_hex_distance(src, dst) != 2:
				continue
			var path := _land_path_avoiding(src, dst, mid)
			if path.size() == 4:
				return {"src": src, "dst": dst, "detour": path}
	return {}


func _land(tile: String) -> bool:
	return bool(Catalog._tile_land.get(tile, false))


func _land_path_avoiding(src: String, dst: String, avoid: String) -> Array:
	var prev := {src: ""}
	var queue: Array = [src]
	var head := 0
	while head < queue.size():
		var u: String = queue[head]
		head += 1
		if u == dst:
			break
		for nb: String in Catalog.tile_neighbours(u):
			if prev.has(nb) or nb == avoid or not _land(nb):
				continue
			prev[nb] = u
			queue.append(nb)
	if not prev.has(dst):
		return []
	var path: Array = [dst]
	while str(prev[path[0]]) != "":
		path.push_front(prev[path[0]])
	return path


func _collect(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for f in dir.get_files():
		if f.ends_with(".gd"):
			out.append(dir_path.path_join(f))
	for d in dir.get_directories():
		_collect(dir_path.path_join(d), out)
