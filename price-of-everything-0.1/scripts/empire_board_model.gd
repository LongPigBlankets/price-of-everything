extends RefCounted
## Supply chain board — the model.
##
## The board is the supply chain view's resting picture: the tiles the company touches, drawn
## as an isometric plate, with the company's buildings standing on them and goods travelling
## the routes between them. This script turns the live sim and the supply graph
## (empire_graph.gd) into plain data the board draws. It reads the sim and never writes it.
##
## THE POOLED MODEL. The sim pools goods per tile: a building never ships to another building,
## it ships to a tile's stockpile and a consumer draws from its own tile's stockpile. So every
## flow here runs building -> its tile's warehouse -> the transport route -> the destination
## tile's warehouse -> building. The warehouse is the hub of its tile, which is what the game
## actually does.
##
## Returned shape (see build()):
##   tiles:    tile_id -> {id, center, type, height, store, label, level, paved, pylon?}
##   standing: [{kind, iid, tile, pos, sprite, level, name, side, pad}]  kind: building|site|warehouse|port|pylon|
##             suppliers (Local Suppliers' depot: the white NPC warehouse on a tile they serve)
##   roads:    [{tile, a, b, kind, level, paved}]                    the stretches of street in use
##   lines:    [{mode, good, kind, pts: [{p, tile, edge}], reverse}]  pipes, cables, and any way
##                                                                    that cannot follow the streets
##   flows:    [{good, icon, kind, mode, pts: [{p, tile, edge}], live}]  what travels them
##   lanes:    [{kind, good, from, to, sources, dests, live, hops}]   the real movements behind them
##
## THE STREET PLAN. Every tile is laid out the same way (empire_board_streets.gd): the
## warehouse at the centre, ten slots around it, streets between. Goods travel the streets, and
## only the stretches something travels are drawn.
##
## REAL MOVEMENTS. A line between two tiles is drawn only where goods really move: a shipment
## in transit, a trade or move the ledgers logged in the last few turns, a standing move
## order, or a building whose output is routed to another tile or to market. Each movement is
## mapped to the buildings it comes from (the ones on the source tile that make the good) and
## goes to (the ones on the destination tile that use it, or the site it was ordered for).

const BuildingSprites := preload("res://scripts/building_sprites.gd")
const GoodIcons := preload("res://scripts/good_icons.gd")
const Streets := preload("res://scripts/empire_board_streets.gd")
const Rails := preload("res://scripts/empire_board_rails.gd")
const Service := preload("res://scripts/middleman_service.gd")
const Relief := preload("res://scripts/empire_board_relief.gd")

## A flat-topped hex of the map's tile size (assets/main_tileset.tres: 540 x 480).
const HEX_HALF := Vector2(270.0, 240.0)
## A tile stands at its tile height (empire_board_relief.gd plates), settled over the whole map;
## this is lowland's, for a tile the map does not hold.
const DEFAULT_HEIGHT := 34.0
## The footprint a standing thing gets, as a share of its slot. Level 3 is the only one that
## fills it: LEVEL_SHARE sizes a plain block, and a sprite carries its level's size itself.
const FOOT_SHARE := 0.9
const LEVEL_SHARE := {1: 0.72, 2: 0.86, 3: 1.0}
const PORT_BUILDING_ID := "b_004"
const WAREHOUSE_SPRITE := "warehouse"
## Local Suppliers' depot: the level 1 warehouse as an NPC building, in a tile's front left corner.
const SUPPLIERS_NAME := "Local Suppliers"
const SUPPLIERS_CORNER := Vector2(-400.0, 300.0)
## The mode drawn for power: cables carry it, and no goods route does.
const MODE_CABLE := "cables"
## A ledger entry this many turns old still counts as a way goods move.
const RECENT_TURNS := 3
## Where the pylon stands: by the tile's far corner, behind the back row of slots.
const PYLON_AT := Vector2(-121.0, -216.0)
const PYLON_SIDE := 62.0
## Homes stood on a tile that has works but is not a town.
const HOMES_PER_TILE := 3
const TOWERS_SPRITE := "towers"
## A tower's footprint as a share of its slot: tall things on a whole slot would dwarf the tile.
const TOWER_SHARE := 0.46
## Housing keeps this far from a mine on the side nearer the eye.
const MINE_CLEAR := 190.0
## What standing on a river costs a slot when buildings are placed: more than any distance.
const WET_COST := 1.0e7
## How close a river may come to a pad's centre, beyond the pad's own half-width.
const RIVER_MARGIN := 10.0
## How far open water keeps from what stands, beyond its own footprint: a building may stand on the
## beach, right down to the water's edge, but not over the water.
const SEA_MARGIN := 2.5
## How finely a footprint's edge is looked along for open water.
const SEA_STEP := 3.0
## A works' ground reaches this far past its footprint, a mine's worked earth the furthest; it keeps
## off the water too.
const WORKS_REACH := 1.35
## How far either side of its middle a stretch of street is looked at for open water: a street is
## kept wholly off the water, not only its middle.
const STREET_KEEP := 7.0
## A home on the shore: how far it may move from its plot's middle, and how much smaller it may be
## made, to stand on dry ground.
const HOME_SHIFT := 15.0
const HOME_SHRINK := [1.0, 0.85, 0.7]
## A street along the beach (_shore_street): the grid it is found on, how far inland of the waterline
## it keeps to, how strongly, how far from a home's door it may start, and how closely its eased
## corners keep to the way found.
const SHORE_CELL := 6.0
const SHORE_INLAND := 11.0
const SHORE_PULL := 1.5
const SHORE_REACH := 30.0
const SHORE_EASE := 4.0
## Where else the pylon may stand when the sea covers its place: the tile's other corners.
const PYLON_ALT: Array[Vector2] = [Vector2(121.0, -216.0), Vector2(-121.0, 216.0), Vector2(121.0, 216.0)]
## A pipe crosses a tile edge this far along it beyond the railway.
const PIPE_EDGE_GAP := 26.0
const PIPE_MODES := ["pipes", "reinf_pipes"]
## Neighbouring tile centres are 471 or 480 apart; anything further is not a neighbour.
const ADJACENT_REACH := 500.0
## The short run from a building to its tile's warehouse.
const MODE_DRIVE := "drive"


static func hex_points(center: Vector2) -> PackedVector2Array:
	var h := HEX_HALF
	return PackedVector2Array([
		center + Vector2(h.x, 0.0), center + Vector2(h.x * 0.5, h.y),
		center + Vector2(-h.x * 0.5, h.y), center + Vector2(-h.x, 0.0),
		center + Vector2(-h.x * 0.5, -h.y), center + Vector2(h.x * 0.5, -h.y),
	])


static func tile_center(terrain: Object, tile_id: String) -> Vector2:
	var coord: Vector2i = terrain.id_to_coord(tile_id)
	return terrain.map_to_local(terrain.map_coord_for_tile_coord(coord))


## Each consecutive tile pair of a route with the mode that carries it: [{a, b, mode}].
static func route_hops(route: Dictionary) -> Array:
	var tiles: Array = route.get("tiles", [])
	var legs: Array = route.get("legs", [])
	var hops: Array = []
	var idx := 0
	for leg in legs:
		var mode := str((leg as Dictionary).get("mode", ""))
		var to := str((leg as Dictionary).get("to", ""))
		while idx < tiles.size() - 1:
			hops.append({"a": str(tiles[idx]), "b": str(tiles[idx + 1]), "mode": mode})
			idx += 1
			if str(tiles[idx]) == to:
				break
	return hops


## One real movement of a good between two tiles.
static func _lane(lanes: Dictionary, kind: String, good: String, from: String, to: String) -> Dictionary:
	var key := "%s|%s|%s|%s" % [kind, good, from, to]
	if not lanes.has(key):
		lanes[key] = {"kind": kind, "good": good, "from": from, "to": to, "live": [],
			"sites": {}, "route": {}}
	return lanes[key]


## Every real movement of goods between tiles, as lanes keyed by kind, good and tile pair.
## `outputs` is [{iid, tile, good}] for the company's finished buildings.
static func real_lanes(outputs: Array) -> Dictionary:
	var lanes: Dictionary = {}
	for s in TransportState.get_pending_transport_shipments():
		var sh: Dictionary = s
		var from := str(sh.get("source_tile", ""))
		var to := str(sh.get("destination_tile", ""))
		if not from.begins_with("tile_") or not to.begins_with("tile_"):
			continue
		var kind := "sell" if bool(sh.get("is_sale", false)) else ("buy" if bool(sh.get("is_purchase", false)) else "move")
		var items: Array = []
		if kind == "sell":
			for it in (sh.get("sale_record", {}) as Dictionary).get("items", []):
				items.append([str((it as Dictionary).get("good_id", "")), int((it as Dictionary).get("qty", 0))])
		else:
			items.append([str(sh.get("good_id", "")), int(sh.get("qty", 0))])
		for it in items:
			if str(it[0]) == "" or int(it[1]) <= 0:
				continue
			var lane: Dictionary = _lane(lanes, kind, str(it[0]), from, to)
			var duration := maxi(1, int(sh.get("transport_turns", 1)))
			(lane["live"] as Array).append({"qty": int(it[1]), "duration": duration,
				"remaining": clampi(int(sh.get("turns_remaining", duration)), 0, duration),
				"waiting": bool(sh.get("construction_order_pending", false))})
			if (lane["route"] as Dictionary).is_empty() and not (sh.get("tiles", []) as Array).is_empty():
				lane["route"] = {"tiles": sh.get("tiles", []), "legs": sh.get("legs", [])}
			for tag in ["construction_instance_id", "upgrade_instance_id"]:
				if str(sh.get(tag, "")) != "":
					(lane["sites"] as Dictionary)[str(sh[tag])] = true
	var now := int(TurnManager.current_turn) if TurnManager else 0
	for t in MatchState.transaction_log:
		var td: Dictionary = t
		var k := str(td.get("kind", ""))
		if not (k in ["buy", "sell"]) or now - int(td.get("turn_started", -99)) > RECENT_TURNS:
			continue
		var tf := str(td.get("tile_from", ""))
		var tt := str(td.get("tile_to", ""))
		if tf.begins_with("tile_") and tt.begins_with("tile_"):
			_lane(lanes, k, str(td.get("good_id", "")), tf, tt)
	for m in TransportState.move_log:
		var md: Dictionary = m
		if now - int(md.get("turn_started", -99)) > RECENT_TURNS:
			continue
		var mf := str(md.get("tile_from", ""))
		var mt := str(md.get("tile_to", ""))
		if mf.begins_with("tile_") and mt.begins_with("tile_") and mf != mt:
			_lane(lanes, "move", str(md.get("good_id", "")), mf, mt)
	for m in TransportState.recurring_moves:
		var rd: Dictionary = m
		var rf := str(rd.get("source", ""))
		var rt := str(rd.get("dest", ""))
		if not rf.begins_with("tile_") or not rt.begins_with("tile_") or rf == rt:
			continue
		for gid in (rd.get("goods", {}) as Dictionary):
			_lane(lanes, "move", str(gid), rf, rt)
	# Standing output routes: a building told to send its output to another tile, or to market. Output the
	# intermediary buys never travels to a port, so it has no lane.
	for o in outputs:
		var od: Dictionary = o
		if preload("res://scripts/middleman_service.gd").buys_output(str(od["iid"]), str(od["good"])):
			continue
		var dest := str(MatchState.get_output_stockpile_destination(str(od["iid"]), str(od["good"])))
		if dest.begins_with("tile_") and dest != str(od["tile"]):
			_lane(lanes, "move", str(od["good"]), str(od["tile"]), dest)
		elif MatchState.is_output_market(str(od["iid"]), str(od["good"])):
			var port := str(Catalog.nearest_port_tile(str(od["tile"])))
			if port.begins_with("tile_"):
				_lane(lanes, "sell", str(od["good"]), str(od["tile"]), port)
	return lanes


## A shortest chain of cabled tiles from `from` to any tile in `targets`, or [] when none.
static func _cable_path(from: String, targets: Dictionary) -> Array:
	var prev: Dictionary = {from: ""}
	var queue: Array = [from]
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		if cur != from and targets.has(cur):
			var path: Array = []
			while cur != "":
				path.push_front(cur)
				cur = str(prev[cur])
			return path
		for nb in Catalog.tile_neighbours(cur):
			if not prev.has(str(nb)) and Power.cable_level(str(nb)) > 0:
				prev[str(nb)] = cur
				queue.append(str(nb))
	return []


static func _pt(p: Vector2, tile: String, edge: bool = false) -> Dictionary:
	return {"p": p, "tile": tile, "edge": edge}


## Build the board from the live sim. `terrain` is the HexMap, `graph` is empire_graph.build().
## `true_pos` maps a building's iid to where it really stands on the map; it only steers which
## slot the building takes. `rivers_by_tile` is tile_id -> [PackedVector2Array]: nothing stands
## on a river while a dry place is free. `water` is (tile_id, point) -> bool, open sea or lake at
## a point: nothing stands on it either while a dry place is free, and the streets keep off it.
## `shores` is (tile_id) -> [[p0, p1]], the edges between the tile's land and its open water: with it
## what stands and the streets are measured against the shoreline itself, exactly and quickly; without
## it, the water test is sampled. With `town`, housing stands on slots the works leave free.
static func build(terrain: Object, graph: Dictionary, true_pos: Dictionary = {},
		rivers_by_tile: Dictionary = {}, town: bool = false, water: Callable = Callable(),
		shores: Callable = Callable()) -> Dictionary:
	_shores = shores
	_shore_cache.clear()
	var tiles: Dictionary = {}
	var by_tile: Dictionary = {}          # tile_id -> [standing dict]
	var stores: Dictionary = {}           # tile_id -> true: the tile has a warehouse
	var makers: Dictionary = {}           # "tile|good" -> [iid]
	var users: Dictionary = {}            # "tile|good" -> [iid]
	var outputs: Array = []
	var feeds: Array = []                 # [{iid, tile, good, out: bool, suppliers: bool}] building <-> warehouse or depot
	var suppliers: Dictionary = {}        # tile_id -> true: Local Suppliers serve a building there
	var power_ends: Array = []            # [{iid, tile, out: bool}]
	var polluters: Dictionary = {}        # tile_id -> how many dirty buildings stand on it

	for n in graph.get("nodes", []):
		var nd: Dictionary = n
		var tile := str(nd.get("tile_id", ""))
		var iid := str(nd["iid"])
		if tile == "":
			continue
		stores[tile] = true
		var site := bool(nd.get("under_construction", false))
		(by_tile.get_or_add(tile, []) as Array).append({
			"kind": "site" if site else "building", "iid": iid, "tile": tile,
			"sprite": nd.get("sprite"), "level": int(nd.get("level", 1)),
			"name": str(nd.get("name", "")), "icon": nd.get("icon"),
			"internal_name": str(nd.get("internal_name", "")), "polluting": false,
		})
		if site:
			continue
		var b: Dictionary = BuildingState.buildings.get(iid, {})
		var recipe: Dictionary = Catalog.get_recipe(str(b.get("recipe_id", "")))
		# Dirty: it burns something the carbon levy bites (the map's own rule for grey smoke),
		# or it digs coal.
		var dirty := false
		for ip in recipe.get("inputs", []):
			if float(Catalog.get_good(str((ip as Dictionary).get("good_id", ""))).get("co2_tax_multiplier", 0.0)) > 0.0:
				dirty = true
		for o in recipe.get("outputs", []):
			if _internal_name(str((o as Dictionary).get("good_id", ""))) == "coal":
				dirty = true
		((by_tile[tile] as Array)[(by_tile[tile] as Array).size() - 1] as Dictionary)["polluting"] = dirty
		if dirty:
			polluters[tile] = int(polluters.get(tile, 0)) + 1
		for o in recipe.get("outputs", []):
			var g := str((o as Dictionary).get("good_id", ""))
			if g == "":
				continue
			if _is_power(g):
				power_ends.append({"iid": iid, "tile": tile, "out": true, "good": g})
				continue
			(makers.get_or_add(tile + "|" + g, []) as Array).append(iid)
			outputs.append({"iid": iid, "tile": tile, "good": g})
			var sold := Service.buys_output(iid, g)
			feeds.append({"iid": iid, "tile": tile, "good": g, "out": true, "suppliers": sold})
			if sold:
				suppliers[tile] = true
		var draws := int(recipe.get("energy_req", 0)) > 0
		for ip in recipe.get("inputs", []):
			var gi := str((ip as Dictionary).get("good_id", ""))
			if gi == "":
				continue
			if _is_power(gi):
				draws = true
				continue
			(users.get_or_add(tile + "|" + gi, []) as Array).append(iid)
			var supplied := Service.supplies_good(iid, gi) or Service.bridges_good(iid, gi)
			feeds.append({"iid": iid, "tile": tile, "good": gi, "out": false, "suppliers": supplied})
			if supplied:
				suppliers[tile] = true
		if draws:
			power_ends.append({"iid": iid, "tile": tile, "out": false})
	for key in Stockpile.tiles_with_stock():
		var tid := str(key)
		if tid.begins_with("tile_") and Stockpile.get_used_capacity(tid) > 0:
			stores[tid] = true

	var port_node: Dictionary = {}        # tile_id -> port dict
	for p in graph.get("ports", []):
		var ptile := str((p as Dictionary).get("tile_id", ""))
		if ptile != "":
			port_node[ptile] = p

	# The real movements, each with its route as tile hops.
	var lanes: Dictionary = real_lanes(outputs)
	var drawn: Dictionary = {}
	for tid in stores:
		drawn[tid] = true
	for key in lanes:
		var lane: Dictionary = lanes[key]
		var hops: Array = []
		if str(lane["from"]) != str(lane["to"]):
			var r: Dictionary = lane["route"]
			if r.is_empty():
				r = TransportService.route(str(lane["from"]), str(lane["to"]), str(lane["good"]))
			hops = route_hops(r)
		lane["hops"] = hops
		lane["blocked"] = hops.is_empty() and str(lane["from"]) != str(lane["to"])
		if bool(lane["blocked"]):
			drawn[str(lane["from"])] = true
			continue
		if str(lane["kind"]) != "sell":
			stores[str(lane["to"])] = true
		drawn[str(lane["from"])] = true
		drawn[str(lane["to"])] = true
		for hop in hops:
			drawn[str(hop["a"])] = true
			drawn[str(hop["b"])] = true

	# Power: every cabled tile the company makes or draws power on, joined through cabled tiles.
	var power_tiles: Dictionary = {}
	for pe in power_ends:
		if Power.cable_level(str(pe["tile"])) > 0:
			power_tiles[str(pe["tile"])] = true
	var cable_links: Dictionary = {}      # "a|b" (a < b) -> true
	var pylon_tiles: Dictionary = power_tiles.duplicate()
	var joined: Dictionary = {}
	var order: Array = power_tiles.keys()
	order.sort()
	for tid in order:
		if joined.is_empty():
			joined[tid] = true
			continue
		if joined.has(tid):
			continue
		var path: Array = _cable_path(str(tid), joined)
		joined[tid] = true
		for i in range(path.size()):
			pylon_tiles[str(path[i])] = true
			joined[str(path[i])] = true
			drawn[str(path[i])] = true
			if i > 0:
				cable_links[mini_str(str(path[i - 1]), str(path[i])) + "|" + maxi_str(str(path[i - 1]), str(path[i]))] = true

	# The icon the pylons carry: the power the company makes, or failing that any power good.
	var power_good := ""
	for pe in power_ends:
		if str(pe.get("good", "")) != "":
			power_good = str(pe["good"])
			break
	if power_good == "":
		for g in Catalog.all_goods():
			var gid := str((g as Dictionary).get("id", (g as Dictionary).get("good_id", "")))
			if gid != "" and _is_power(gid):
				power_good = gid
				break
	var power_icon: Texture2D = GoodIcons.texture_for(power_good, _internal_name(power_good)) if power_good != "" else null

	var plates: Dictionary = Relief.plates(terrain, rivers_by_tile)
	for tid in drawn:
		var coord: Vector2i = terrain.id_to_coord(str(tid))
		if coord.x < 0:
			continue
		var ttype := str(Catalog.tile_type(str(tid)))
		var c: Vector2 = tile_center(terrain, str(tid))
		tiles[tid] = {
			"id": tid, "center": c, "type": ttype,
			"height": float(plates.get(str(tid), DEFAULT_HEIGHT)), "store": stores.has(tid),
			"label": str(Catalog.tile_label(str(tid))), "hub": c,
			"level": clampi(int(Catalog.tile_infra_level(str(tid), "roads")), 1, 3),
			"paved": Catalog.tile_has_infrastructure(str(tid), "roads"),
			"polluters": int(polluters.get(tid, 0)),
		}
		if pylon_tiles.has(tid):
			var at := PYLON_AT
			for alt in [PYLON_AT] + PYLON_ALT:
				if not _at_sea(str(tid), c + (alt as Vector2), PYLON_SIDE * 0.5, water):
					at = alt
					break
			tiles[tid]["pylon"] = c + at
			tiles[tid]["power_icon"] = power_icon

	# What each tile's rivers add to the stretches of street that cross them, and the sea to
	# those that run over it.
	var river_cost: Dictionary = {}       # tile_id -> {"a|b": cost}
	for tid in tiles:
		# The sea and the rivers do not move: a tile's costs are worked out once for as long as they stand.
		var cost_key := "%s|%s|%s|%s" % [tid, tiles[tid]["center"], hash(rivers_by_tile.get(tid, [])), water.hash()]
		if _street_costs.has(cost_key):
			river_cost[tid] = _street_costs[cost_key]
			continue
		var costs: Dictionary = {}
		var c: Vector2 = tiles[tid]["center"]
		for e in Streets.edges():
			var a: Vector2 = c + Streets.node_pos(str(e[0]))
			var b: Vector2 = c + Streets.node_pos(str(e[1]))
			if _sea_between(str(tid), a, b, water):
				costs[str(e[0]) + "|" + str(e[1])] = Streets.SEA_COST
				continue
			for line in rivers_by_tile.get(tid, []):
				var pts: PackedVector2Array = line
				for i in range(pts.size() - 1):
					if Geometry2D.segment_intersects_segment(a, b, pts[i], pts[i + 1]) != null:
						costs[str(e[0]) + "|" + str(e[1])] = Streets.RIVER_COST
		river_cost[tid] = costs
		_street_costs[cost_key] = costs

	# Stand everything on the tile's street plan: the warehouse at the centre, and each building,
	# site and port on the free slot nearest where it really is on the map.
	var standing: Array = []
	var pos_of: Dictionary = {}           # iid | "store:<tile>" | "port:<tile>" -> Vector2
	var door_of: Dictionary = {}          # the same keys -> the street node at its spur's end
	var spot_of: Dictionary = {}          # the same keys -> its slot's centre, relative to the tile's
	for tid in tiles:
		var t: Dictionary = tiles[tid]
		var c: Vector2 = t["center"]
		var rivers: Array = rivers_by_tile.get(tid, [])
		var hub_slot := -1
		t["hub_node"] = Streets.nid(Streets.hub_door())
		t["manifold"] = Streets.pipe_point(Vector2.ZERO)
		if bool(t["store"]):
			# The warehouse stands at the centre unless a river runs there; then it takes the
			# dry slot nearest the centre, and that slot's spur.
			var hub_rel := Vector2.ZERO
			if _wet(c, Streets.HUB_SIDE, rivers) or _at_sea(str(tid), c, Streets.HUB_SIDE * FOOT_SHARE, water):
				var nearest: Array = range(Streets.SLOTS.size())
				nearest.sort_custom(func(x: int, y: int) -> bool:
					return (Streets.SLOTS[x] as Vector2).length_squared() < (Streets.SLOTS[y] as Vector2).length_squared())
				for i in nearest:
					if not _wet(c + Streets.SLOTS[i], Streets.SLOT_SIDE, rivers) \
							and not _at_sea(str(tid), c + Streets.SLOTS[i], Streets.HUB_SIDE * FOOT_SHARE, water):
						hub_slot = i
						hub_rel = Streets.SLOTS[i]
						t["hub_node"] = Streets.nid(Streets.slot_door(i))
						t["manifold"] = Streets.pipe_point(Streets.SLOTS[i])
						break
			t["hub"] = c + hub_rel
			var level: int = Stockpile.get_warehouse_level(tid)
			standing.append({"kind": "warehouse", "iid": "store:" + str(tid), "tile": tid, "pos": c + hub_rel,
				"sprite": BuildingSprites.texture_for(WAREHOUSE_SPRITE, level), "level": level,
				"side": Streets.HUB_SIDE * FOOT_SHARE, "pad": Streets.HUB_SIDE,
				"name": "%s warehouse" % str(t["label"])})
			pos_of["store:" + str(tid)] = c + hub_rel
			door_of["store:" + str(tid)] = str(t["hub_node"])
		var things: Array = []
		if port_node.has(tid):
			var pn: Dictionary = port_node[tid]
			things.append({"kind": "port", "iid": "port:" + str(tid), "tile": tid,
				"sprite": BuildingSprites.texture_for("port", 1), "level": 3,
				"name": str(pn.get("name", "Port")), "port_iid": str(pn["iid"])})
		if suppliers.has(tid):
			things.append({"kind": "suppliers", "iid": "suppliers:" + str(tid), "tile": tid,
				"sprite": BuildingSprites.npc_texture_for(WAREHOUSE_SPRITE, 1), "level": 1, "name": SUPPLIERS_NAME})
		var own: Array = by_tile.get(tid, [])
		own.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return str(x["iid"]) < str(y["iid"]))
		things.append_array(own)
		# A city's two towers stand either side of the avenue, the crossroads between them.
		# Their slots are theirs whatever is built: the works take the others, and the
		# housing gives way.
		var tower_slots: Array = []
		if town and str(t["type"]) == "urban":
			for pair in Streets.TOWER_PAIRS:
				var ok := true
				for i in pair:
					ok = ok and i != hub_slot and not _wet(c + Streets.SLOTS[i], Streets.SLOT_SIDE * TOWER_SHARE, rivers) \
						and not _at_sea(str(tid), c + Streets.SLOTS[i], Streets.SLOT_SIDE * TOWER_SHARE, water)
				if ok:
					tower_slots = pair
					break
		var taken: Array = tower_slots.duplicate()
		if hub_slot >= 0:
			taken.append(hub_slot)
		var free: Array = Streets.places(things.size(), taken)
		# A place is wet for works when a river runs under it or the water comes within their reach; a
		# home, which is only its footprint, may stand nearer.
		for place in free:
			var at: Vector2 = c + (place["pos"] as Vector2)
			var foot := float(place["side"]) * FOOT_SHARE
			var river := _wet(at, float(place["side"]), rivers)
			place["wet"] = river or _at_sea(str(tid), at, foot * WORKS_REACH, water)
			place["home_wet"] = river or _at_sea(str(tid), at, foot, water)
		for thing in things:
			var td: Dictionary = thing
			var want: Vector2 = Streets.SLOTS[0]
			if true_pos.has(str(td["iid"])):
				want = (true_pos[str(td["iid"])] as Vector2) - c
			elif td["kind"] == "port":
				want = Streets.SLOTS[2]
			elif td["kind"] == "suppliers":
				want = SUPPLIERS_CORNER
			var best := 0
			var best_cost := INF
			for i in range(free.size()):
				var cost := (free[i]["pos"] as Vector2).distance_squared_to(want) + (WET_COST if bool(free[i]["wet"]) else 0.0)
				if cost < best_cost:
					best_cost = cost
					best = i
			var place: Dictionary = free[best]
			free.remove_at(best)
			td["pos"] = c + (place["pos"] as Vector2)
			td["pad"] = float(place["side"])
			# A sprite set shares one scale, so a level 1 sprite is already drawn smaller inside
			# its frame; only a plain block needs the level's share applied here.
			var share := 1.0
			if td.get("sprite") == null:
				share = float(LEVEL_SHARE.get(clampi(int(td["level"]), 1, 3), 1.0))
			td["side"] = float(place["side"]) * FOOT_SHARE * share
			pos_of[str(td["iid"])] = td["pos"]
			door_of[str(td["iid"])] = Streets.nid(Streets.slot_door(int(place["slot"])))
			spot_of[str(td["iid"])] = Streets.SLOTS[int(place["slot"])]
			standing.append(td)
		for n in range(tower_slots.size()):
			var slot: int = tower_slots[n]
			var tower_id := "tower:%s:%d" % [str(tid), n]
			# The glass tower, the taller, is the one nearer the tile's middle.
			standing.append({"kind": "house", "iid": tower_id, "tile": tid, "pos": c + Streets.SLOTS[slot],
				"sprite": BuildingSprites.texture_for(TOWERS_SPRITE, 2 - n), "level": 3, "name": "City",
				"side": Streets.SLOT_SIDE * TOWER_SHARE, "pad": Streets.SLOT_SIDE, "polluting": false,
				"tall": true})
			door_of[tower_id] = Streets.nid(Streets.slot_door(slot))
		if not tower_slots.is_empty():
			t["crossroads"] = signf((Streets.SLOTS[int(tower_slots[0])] as Vector2).y)
		# Housing: where the works are there are homes. A city tile fills its free slots with
		# them, works or none; any other tile with works takes a few. Each keeps to dry ground.
		if town and (bool(t["store"]) or str(t["type"]) == "urban") and things.size() <= Streets.SLOTS.size():
			var homes := 0
			var limit := Streets.SLOTS.size() if str(t["type"]) == "urban" else HOMES_PER_TILE
			var costs: Dictionary = river_cost.get(tid, {})
			var beach_ways: Array = []               # the tile's streets along the beach, so far
			var reached: Array = []               # where a street along the beach may join the plan's
			for place in free:
				if homes >= limit:
					break
				# On the shore a home takes what dry ground its plot has: moved a little inland, or made
				# a little smaller, so it stands on the beach but never over the water.
				var room: Variant = _home_room(str(tid), c + (place["pos"] as Vector2), float(place["side"]), rivers, water)
				if room == null:
					continue
				var at: Vector2 = room[0]
				var foot := float(room[1])
				var plot := Rect2(at - Vector2(foot, foot) * 0.5, Vector2(foot, foot))
				var crossed := false
				for way in beach_ways:
					crossed = crossed or _crosses(way, plot.grow(STREET_KEEP))
				if crossed:
					continue
				# Its way onto the street keeps off the water. Where the plan's streets reach it only over
				# the water, a street along the beach does, to where they are dry.
				var door: Vector2 = Streets.slot_door(int(place["slot"]))
				var shore := PackedVector2Array()
				if _sea_route(Streets.path(Streets.nid(door), str(t["hub_node"]), costs, str(tid)), costs):
					if reached.is_empty():
						reached = _dry_nodes(str(tid), str(t["hub_node"]), costs)
					var keep_off: Array = [plot.grow(2.0)]
					for st in standing:
						if str(st["tile"]) == str(tid) and str(st["kind"]) != "pylon":
							var half := float(st.get("pad", st["side"])) * 0.5
							keep_off.append(Rect2((st["pos"] as Vector2) - Vector2(half, half), Vector2(half, half) * 2.0).grow(2.0))
					var goals: Array = []
					for id in reached:
						goals.append(c + Streets.node_pos(str(id)))
					shore = _shore_street(str(tid), c, c + door, goals, keep_off, water)
					if shore.is_empty():
						continue
					beach_ways.append(shore)
				# Nothing decorative stands in front of a mine: its pit is in the ground and
				# anything nearer the eye would cover it.
				var hides := false
				for thing in things:
					if str((thing as Dictionary).get("internal_name", "")) != "mine":
						continue
					var gap: Vector2 = c + (place["pos"] as Vector2) - ((thing as Dictionary)["pos"] as Vector2)
					hides = hides or (gap.x + gap.y > 0.0 and gap.length() < MINE_CLEAR)
				if hides:
					continue
				var hid := "house:%s:%d" % [str(tid), int(place["slot"])]
				var variety := 1 + (hash(hid) % 3)
				var home := {"kind": "house", "iid": hid, "tile": tid, "pos": at,
					"sprite": BuildingSprites.texture_for("house", variety), "level": 3, "name": "Housing",
					"side": foot, "pad": foot / FOOT_SHARE, "polluting": false}
				door_of[hid] = Streets.nid(door)
				if not shore.is_empty():
					# Its street along the beach ends at a node of the plan: from there on, the plan's.
					home["shore"] = shore
					door_of[hid] = Streets.nid(shore[shore.size() - 1] - c)
				standing.append(home)
				homes += 1
		if t.has("pylon"):
			standing.append({"kind": "pylon", "iid": "pylon:" + str(tid), "tile": tid,
				"sprite": BuildingSprites.texture_for("pylon", 1), "level": 3, "pos": t["pylon"],
				"side": PYLON_SIDE, "name": "Power line"})

	var route := func(tile: String, from: String, to: String) -> Array:
		return Streets.path(from, to, river_cost.get(tile, {}), tile)

	var lines: Array = []                 # pipes, cables, and any way that cannot follow the plan
	var flows: Array = []
	var roads: Dictionary = {}            # "tile|a|b" -> the stretch of street between two nodes
	# Walk node ids along a tile's streets: marks each stretch as used and returns the points.
	var walk := func(tile: String, ids: Array, mode: String) -> Array:
		var t: Dictionary = tiles[tile]
		var c: Vector2 = t["center"]
		var pts: Array = []
		for i in range(ids.size()):
			var rel: Vector2 = Streets.node_pos(str(ids[i]))
			pts.append(_pt(c + rel, tile, Streets.is_exit(rel)))
			if i == 0:
				continue
			var a := str(ids[i - 1])
			var b := str(ids[i])
			var rkey := "%s|%s|%s" % [tile, mini_str(a, b), maxi_str(a, b)]
			if not roads.has(rkey):
				var kind: String = Streets.kind_of(a, b)
				roads[rkey] = {"tile": tile, "a": c + Streets.node_pos(a), "b": c + Streets.node_pos(b),
					"kind": kind, "level": 1 if kind == "spur" else int(t["level"]),
					"paved": bool(t["paved"])}
		return pts

	# Lay track along a tile's railway: returns the points, and keeps them as track to draw.
	var track := func(tile: String, rels: Array) -> Array:
		var c: Vector2 = tiles[tile]["center"]
		var pts: Array = []
		for rel in rels:
			pts.append(_pt(c + (rel as Vector2), tile, Rails.is_exit(rel)))
		if pts.size() >= 2:
			lines.append({"mode": "rail", "good": "", "kind": "track", "pts": pts})
		return pts

	# A pipe's run from the thing at `iid` to its tile's warehouse, beside the streets.
	var seen_line: Dictionary = {}
	var pipe_feed := func(iid: String, tile: String, good: String, toward_thing: bool) -> void:
		var lkey := "%s|%s" % [iid, good]
		if seen_line.has(lkey) or not spot_of.has(iid):
			return
		seen_line[lkey] = true
		var c: Vector2 = tiles[tile]["center"]
		var entry: Vector2 = Streets.pipe_point(spot_of[iid])
		var manifold: Vector2 = tiles[tile]["manifold"]
		if entry.distance_to(manifold) < 1.0:
			return
		# Behind its own row, then by the trunk to the warehouse's line: never across a slot.
		var pts: Array = []
		for rel in Streets.pipe_run(entry, manifold):
			pts.append(_pt(c + (rel as Vector2), tile))
		lines.append({"mode": _pipe_mode(tile), "good": good, "kind": "feed", "pts": pts,
			"reverse": toward_thing})

	# Each building's own run to its tile's warehouse: a pipe for a fluid on a piped tile, the
	# streets for everything else.
	var seen_feed: Dictionary = {}
	# Goods Local Suppliers handle run between the building and their depot instead.
	var add_feed := func(iid: String, tile: String, good: String, out: bool, by_suppliers: bool = false) -> void:
		var fkey := "%s|%s|%s" % [iid, good, out]
		if seen_feed.has(fkey) or not tiles.has(tile) or not door_of.has(iid):
			return
		seen_feed[fkey] = true
		var depot := "suppliers:" + tile
		if by_suppliers and door_of.has(depot):
			var way: Array = walk.call(tile, route.call(tile, str(door_of[iid]), str(door_of[depot])), "roads")
			if not out:
				way.reverse()
			flows.append({"good": good, "kind": "feed", "mode": MODE_DRIVE, "pts": way, "live": [],
				"icon": GoodIcons.texture_for(good, _internal_name(good))})
			return
		if Catalog.requires_pipeline(good) and _pipe_mode(tile) != "":
			pipe_feed.call(iid, tile, good, not out)
			return
		var ids: Array = route.call(tile, str(door_of[iid]), str(tiles[tile]["hub_node"]))
		var pts: Array = walk.call(tile, ids, "roads")
		if not out:
			pts.reverse()
		flows.append({"good": good, "kind": "feed", "mode": MODE_DRIVE, "pts": pts, "live": [],
			"icon": GoodIcons.texture_for(good, _internal_name(good))})
	for f in feeds:
		if tiles.has(str(f["tile"])) and bool(tiles[str(f["tile"])]["store"]):
			add_feed.call(str(f["iid"]), str(f["tile"]), str(f["good"]), bool(f["out"]), bool(f.get("suppliers", false)))

	# The crossroads before a city's towers: the street past both, the avenue out to the
	# tile's edge and across to the other street.
	for tid in tiles:
		if not tiles[tid].has("crossroads"):
			continue
		var sy := float(tiles[tid]["crossroads"])
		var cross := Streets.nid(Vector2(Streets.AVENUE_X, Streets.STREET_Y * sy))
		for other in [Vector2(Streets.AVENUE_X, Streets.TOP_Y * sy), Vector2(Streets.AVENUE_X, -Streets.STREET_Y * sy),
				Vector2(0.0, Streets.STREET_Y * sy), Vector2(110.0, Streets.STREET_Y * sy)]:
			var ends: Array = [cross, Streets.nid(other)]
			ends.sort()
			if float((river_cost.get(tid, {}) as Dictionary).get("|".join(ends), 0.0)) >= Streets.SEA_COST:
				continue                      # it would run out over the sea
			walk.call(str(tid), [cross, Streets.nid(other)], "roads")

	# A home has its own short way onto the street; one the plan's streets reach only over the water,
	# its street along the beach first.
	for st in standing:
		if str(st["kind"]) == "house":
			var tile := str(st["tile"])
			var door := str(door_of[str(st["iid"])])
			if st.has("shore"):
				var shore: PackedVector2Array = st["shore"]
				for i in range(1, shore.size()):
					roads["%s|shore|%s|%d" % [tile, str(st["iid"]), i]] = {"tile": tile, "a": shore[i - 1], "b": shore[i],
						"kind": "shore", "level": int(tiles[tile]["level"]), "paved": bool(tiles[tile]["paved"])}
			walk.call(tile, route.call(tile, door, str(tiles[tile]["hub_node"])), "roads")

	# Each real movement: its way from tile to tile, and the buildings at either end.
	var lane_rows: Array = []
	var seen_way: Dictionary = {}
	for key in lanes:
		var lane: Dictionary = lanes[key]
		var from_tile := str(lane["from"])
		var to_tile := str(lane["to"])
		var good := str(lane["good"])
		if not tiles.has(from_tile) or not tiles.has(to_tile) or bool(lane["blocked"]):
			continue
		var sources: Array = makers.get(from_tile + "|" + good, [])
		var dests: Array = (users.get(to_tile + "|" + good, []) as Array).duplicate()
		for sid in lane["sites"]:
			if pos_of.has(str(sid)) and not dests.has(str(sid)):
				dests.append(str(sid))
				add_feed.call(str(sid), to_tile, good, false)
		lane_rows.append({"kind": lane["kind"], "good": good, "from": from_tile, "to": to_tile,
			"sources": sources, "dests": dests, "live": lane["live"], "hops": lane["hops"]})
		var hops: Array = lane["hops"]
		var from_port := str(lane["kind"]) == "buy" and door_of.has("port:" + from_tile)
		var to_port := str(lane["kind"]) == "sell" and door_of.has("port:" + to_tile)
		if not hops.is_empty() and PIPE_MODES.has(str(hops[0]["mode"])):
			# Piped: one pipe per good between each pair of tiles, and into the port at the end.
			for hop in hops:
				var a := str(hop["a"])
				var b := str(hop["b"])
				if not tiles.has(a) or not tiles.has(b):
					continue
				var lo := mini_str(a, b)
				var hi := maxi_str(a, b)
				var wkey := "%s|%s|%s|%s" % [lo, hi, str(hop["mode"]), good]
				if seen_way.has(wkey):
					continue
				seen_way[wkey] = true
				lines.append({"mode": str(hop["mode"]), "good": good, "kind": "way", "reverse": a != lo,
					"pts": _pipe_way(tiles[lo], tiles[hi])})
			if from_port:
				pipe_feed.call("port:" + from_tile, from_tile, good, false)
			if to_port:
				pipe_feed.call("port:" + to_tile, to_tile, good, true)
			continue
		var pts: Array = []
		var mode := "roads"
		# Where the goods stand on the tile they are on: a street node, or a point on the railway.
		var at: String = str(door_of["port:" + from_tile]) if from_port else (str(tiles[from_tile]["hub_node"]) if bool(tiles[from_tile]["store"]) else "")
		var here := at                        # the door the goods wait at on this tile
		var at_rail := Vector2.INF
		for hop in hops:
			var a := str(hop["a"])
			var b := str(hop["b"])
			if not tiles.has(a) or not tiles.has(b):
				continue
			mode = str(hop["mode"])
			var off: Vector2 = (tiles[b]["center"] as Vector2) - (tiles[a]["center"] as Vector2)
			var out_rel: Vector2 = Streets.exit_point(off)
			if out_rel == Vector2.ZERO:
				# Two tiles that do not touch: no street joins them, so the way runs straight over.
				var jump: Array = [_pt(tiles[a]["center"], a), _pt(tiles[b]["center"], b)]
				lines.append({"mode": mode, "good": "", "kind": "way", "pts": jump})
				pts.append_array(jump)
				at = str(tiles[b]["hub_node"])
				here = at
				at_rail = Vector2.INF
				continue
			var hub_a := str(tiles[a]["hub_node"])
			if mode == "rail":
				if at_rail == Vector2.INF:
					# Brought here by road: it goes to the warehouse and is loaded there.
					if at != "" and at != here:
						pts.append_array(walk.call(a, route.call(a, at, hub_a), "roads"))
						here = hub_a
					at_rail = Rails.stop(Streets.node_pos(here if here != "" else hub_a))
				pts.append_array(track.call(a, Rails.path(at_rail, Rails.exit_point(off))))
				at_rail = Rails.exit_point(-off)
				pts.append(_pt((tiles[b]["center"] as Vector2) + at_rail, b, true))
				at = ""
				here = str(tiles[b]["hub_node"])
				continue
			if at_rail != Vector2.INF:
				# Brought here by rail: unloaded at the warehouse, and on by road from there.
				pts.append_array(track.call(a, Rails.path(at_rail, Rails.stop(Streets.node_pos(hub_a)))))
				at_rail = Vector2.INF
				at = hub_a
			var out_id: String = Streets.nid(out_rel)
			if at == "":
				at = out_id
			pts.append_array(walk.call(a, route.call(a, at, out_id), mode))
			at = Streets.nid(Streets.exit_point(-off))
			pts.append(_pt((tiles[b]["center"] as Vector2) + Streets.node_pos(at), b, true))
			here = str(tiles[b]["hub_node"])
		var goal: String = str(door_of["port:" + to_tile]) if to_port else (str(tiles[to_tile]["hub_node"]) if bool(tiles[to_tile]["store"]) else "")
		if at_rail != Vector2.INF:
			if goal != "":
				pts.append_array(track.call(to_tile, Rails.path(at_rail, Rails.stop(Streets.node_pos(goal)))))
		elif goal != "" and at != "":
			pts.append_array(walk.call(to_tile, route.call(to_tile, at, goal), mode))
		if pts.size() < 2:
			continue
		flows.append({"good": good, "kind": str(lane["kind"]), "mode": mode, "pts": pts,
			"live": lane["live"], "icon": GoodIcons.texture_for(good, _internal_name(good))})

	# Cables run from pylon to pylon between tiles. A tile's own buildings are not wired up
	# one by one: the pylon stands for the tile's connection.
	for ck in cable_links:
		var a := str(ck).get_slice("|", 0)
		var b := str(ck).get_slice("|", 1)
		if tiles.has(a) and tiles.has(b) and tiles[a].has("pylon") and tiles[b].has("pylon"):
			lines.append({"mode": MODE_CABLE, "good": "", "kind": "way",
				"pts": [_pt(tiles[a]["pylon"], a), _pt(tiles[b]["pylon"], b)],
				"ids": ["pylon:" + a, "pylon:" + b]})

	# What each building makes, for the board at rest: iid -> [good].
	var made: Dictionary = {}
	for f in feeds:
		if bool(f["out"]) and not (made.get_or_add(str(f["iid"]), []) as Array).has(str(f["good"])):
			(made[str(f["iid"])] as Array).append(str(f["good"]))
	_shores = Callable()
	_shore_cache.clear()
	return {"tiles": tiles, "standing": standing, "lines": lines, "roads": roads.values(),
		"flows": flows, "lanes": lane_rows, "made": made}


## Does a river run under a pad of this side centred at p?
static func _wet(p: Vector2, side: float, rivers: Array) -> bool:
	for line in rivers:
		var pts: PackedVector2Array = line
		for i in range(pts.size() - 1):
			if Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1]).distance_to(p) < side * 0.5 + RIVER_MARGIN:
				return true
	return false


## The shoreline of the build under way (build's `shores`), and each tile's, as asked for.
static var _shores: Callable = Callable()
static var _shore_cache: Dictionary = {}


## A tile's shoreline edges near a box: none when the box is clear of them all.
static func _shore_edges(tile: String, near: Rect2) -> Array:
	if not _shore_cache.has(tile):
		var edges: Array = _shores.call(tile)
		var box := Rect2()
		for k in range(edges.size()):
			var r := Rect2(edges[k][0], Vector2.ZERO).expand(edges[k][1])
			box = r if k == 0 else box.merge(r)
		_shore_cache[tile] = {"edges": edges, "box": box}
	var kept: Dictionary = _shore_cache[tile]
	if (kept["edges"] as Array).is_empty() or not (kept["box"] as Rect2).grow(1.0).intersects(near):
		return []
	return kept["edges"]


## Does a stretch from a to b come within `reach` of the shoreline anywhere?
static func _near_shore(tile: String, a: Vector2, b: Vector2, reach: float) -> bool:
	for e in _shore_edges(tile, Rect2(a, Vector2.ZERO).expand(b).grow(reach)):
		var pts := Geometry2D.get_closest_points_between_segments(a, b, e[0], e[1])
		if pts[0].distance_to(pts[1]) < reach:
			return true
	return false


## Does open water lie under a square footprint of this side centred at p, or within SEA_MARGIN of
## it? With the shoreline: when the footprint's middle or a corner is on the water, or the shoreline
## runs through it. Without: its edge is looked along closely, where the shore comes in, and its
## inside more loosely, for a pond lying wholly within it.
static func _at_sea(tile: String, p: Vector2, side: float, water: Callable) -> bool:
	if not water.is_valid():
		return false
	var r := side * 0.5 + SEA_MARGIN
	if _shores.is_valid():
		for q in [Vector2.ZERO, Vector2(-r, -r), Vector2(r, -r), Vector2(r, r), Vector2(-r, r)]:
			if bool(water.call(tile, p + (q as Vector2))):
				return true
		var box := Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0)
		for e in _shore_edges(tile, box):
			var a: Vector2 = e[0]
			var b: Vector2 = e[1]
			if box.has_point(a) or box.has_point(b):
				return true
			for k in range(4):
				var c0 := [box.position, Vector2(box.end.x, box.position.y), box.end, Vector2(box.position.x, box.end.y)][k] as Vector2
				var c1 := [Vector2(box.end.x, box.position.y), box.end, Vector2(box.position.x, box.end.y), box.position][k] as Vector2
				if Geometry2D.segment_intersects_segment(a, b, c0, c1) != null:
					return true
		return false
	var n := maxi(2, ceili(r * 2.0 / SEA_STEP))
	for k in range(n + 1):
		var t := -r + r * 2.0 * float(k) / float(n)
		for q in [Vector2(t, -r), Vector2(t, r), Vector2(-r, t), Vector2(r, t)]:
			if bool(water.call(tile, p + (q as Vector2))):
				return true
	for gx in range(-3, 4):
		for gy in range(-3, 4):
			if bool(water.call(tile, p + Vector2(float(gx), float(gy)) * r / 3.0)):
				return true
	return false


## Does a stretch of street from a to b run over open water anywhere along it, kerb to kerb?
static func _sea_between(tile: String, a: Vector2, b: Vector2, water: Callable) -> bool:
	if not water.is_valid():
		return false
	if _shores.is_valid():
		return bool(water.call(tile, a)) or bool(water.call(tile, b)) or _near_shore(tile, a, b, STREET_KEEP)
	var across := (b - a).normalized().orthogonal() * STREET_KEEP
	var steps := maxi(1, ceili(a.distance_to(b) / SEA_STEP))
	for i in range(steps + 1):
		var q := a.lerp(b, float(i) / float(steps))
		if bool(water.call(tile, q)) or bool(water.call(tile, q + across)) or bool(water.call(tile, q - across)):
			return true
	return false


## Where a home stands on its plot of `side` centred at p: the whole plot's footprint where it is dry, or
## moved a little inland or made a little smaller where the sea or a lake comes onto it. A river's plot
## is left to its valley as it was. Returns [centre, footprint side], or null when no dry footprint fits.
static func _home_room(tile: String, p: Vector2, side: float, rivers: Array, water: Callable) -> Variant:
	if _wet(p, side, rivers):
		return null
	for scale in HOME_SHRINK:
		var foot := side * FOOT_SHARE * float(scale)
		var best: Variant = null
		for dx in range(-3, 4):
			for dy in range(-3, 4):
				var off := Vector2(float(dx), float(dy)) * HOME_SHIFT / 3.0
				if best != null and off.length() >= (best as Vector2).length():
					continue
				if not _wet(p + off, side, rivers) and not _at_sea(tile, p + off, foot, water):
					best = off
		if best != null:
			return [p + (best as Vector2), foot]
	return null


## Does a street (a polyline in plan) run through a rectangle?
static func _crosses(way: PackedVector2Array, r: Rect2) -> bool:
	for i in range(1, way.size()):
		var n := maxi(1, ceili(way[i - 1].distance_to(way[i]) / SEA_STEP))
		for k in range(n + 1):
			if r.has_point(way[i - 1].lerp(way[i], float(k) / float(n))):
				return true
	return false


## The nodes of a tile's streets (no slot's door, and not where they leave the tile) that its hub
## reaches without running over open water.
static func _dry_nodes(tile: String, hub: String, costs: Dictionary) -> Array:
	var seen: Dictionary = {}
	for e in Streets.edges():
		for k in range(2):
			var id := str(e[k])
			if seen.has(id) or Streets.kind_of(str(e[0]), str(e[1])) == "spur" or Streets.is_exit(Streets.node_pos(id)):
				continue
			seen[id] = not _sea_route(Streets.path(id, hub, costs, tile), costs)
	var out: Array = []
	for id in seen:
		if bool(seen[id]):
			out.append(id)
	return out


## A street along the beach, from `from` to the nearest of `goals`, as a plan polyline; empty when there
## is none. It keeps off the water by a street's width at least, and keeps close to the shore, at
## SHORE_INLAND from the waterline, as far as it can on its way, turning inland only to reach its goal,
## so it follows the shoreline. It keeps off `keep_off` (the tile's plots) and within the tile.
## Worked out on a grid over the tile: how far each cell lies from the water, then the cheapest way
## across it, then the way's corners eased off where that keeps it dry.
static func _shore_street(tile: String, c: Vector2, from: Vector2, goals: Array, keep_off: Array, water: Callable) -> PackedVector2Array:
	# The sea does not move: a street found once is kept for as long as what it was found among stands.
	var key := str([tile, from, goals, keep_off, water.hash()])
	if not _shore_streets.has(key):
		_shore_streets[key] = _find_shore_street(tile, c, from, goals, keep_off, water)
	return _shore_streets[key]


static var _shore_streets: Dictionary = {}
static var _street_costs: Dictionary = {}


static func _find_shore_street(tile: String, c: Vector2, from: Vector2, goals: Array, keep_off: Array, water: Callable) -> PackedVector2Array:
	var cell := SHORE_CELL
	var origin := c - HEX_HALF
	var cols := ceili(HEX_HALF.x * 2.0 / cell)
	var rows := ceili(HEX_HALF.y * 2.0 / cell)
	var hexp := hex_points(c)
	var at := func(i: int, j: int) -> Vector2: return origin + Vector2(float(i) + 0.5, float(j) + 0.5) * cell
	# How far each cell lies from the water, in plan units: a two-pass chamfer over the grid.
	var far := PackedFloat32Array()
	far.resize(cols * rows)
	for j in range(rows):
		for i in range(cols):
			far[j * cols + i] = 0.0 if bool(water.call(tile, at.call(i, j))) else INF
	var diag := cell * 1.4142
	for pass_dir in [1, -1]:
		var js: Array = range(rows) if pass_dir == 1 else range(rows - 1, -1, -1)
		var is_: Array = range(cols) if pass_dir == 1 else range(cols - 1, -1, -1)
		for j in js:
			for i in is_:
				var best := far[j * cols + i]
				for d in [[-pass_dir, 0, cell], [0, -pass_dir, cell], [-pass_dir, -pass_dir, diag], [pass_dir, -pass_dir, diag]]:
					var ni := int(i) + int(d[0])
					var nj := int(j) + int(d[1])
					if ni >= 0 and nj >= 0 and ni < cols and nj < rows:
						best = minf(best, far[nj * cols + ni] + float(d[2]))
				far[j * cols + i] = best
	var open_cell := func(i: int, j: int) -> bool:
		var q: Vector2 = at.call(i, j)
		if far[j * cols + i] < STREET_KEEP + cell * 0.5 or not Geometry2D.is_point_in_polygon(q, hexp):
			return false
		for r in keep_off:
			if (r as Rect2).has_point(q):
				return false
		return true
	var cell_of := func(q: Vector2) -> Vector2i: return Vector2i(((q - origin) / cell).floor())
	# The cheapest way from the cell nearest `from` to any cell by a goal.
	var start := Vector2i(-1, -1)
	var start_d := INF
	var goal_cells: Dictionary = {}           # cell index -> goal point
	for j in range(rows):
		for i in range(cols):
			if not bool(open_cell.call(i, j)):
				continue
			var q: Vector2 = at.call(i, j)
			if q.distance_to(from) < start_d and q.distance_to(from) <= SHORE_REACH:
				start_d = q.distance_to(from)
				start = Vector2i(i, j)
			for g in goals:
				if q.distance_to(g) <= cell:
					goal_cells[j * cols + i] = g
	if start.x < 0 or goal_cells.is_empty():
		return PackedVector2Array()
	var cost := PackedFloat32Array()
	cost.resize(cols * rows)
	cost.fill(INF)
	var prev := PackedInt32Array()
	prev.resize(cols * rows)
	prev.fill(-1)
	cost[start.y * cols + start.x] = 0.0
	var frontier: Array = [start.y * cols + start.x]
	var reached := -1
	while not frontier.is_empty():
		var bi := 0
		for k in range(1, frontier.size()):
			if cost[int(frontier[k])] < cost[int(frontier[bi])]:
				bi = k
		var cur := int(frontier[bi])
		frontier.remove_at(bi)
		if goal_cells.has(cur):
			reached = cur
			break
		var ci := cur % cols
		var cj := cur / cols
		for d in [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [1, -1], [-1, 1], [-1, -1]]:
			var ni := ci + int(d[0])
			var nj := cj + int(d[1])
			if ni < 0 or nj < 0 or ni >= cols or nj >= rows or not bool(open_cell.call(ni, nj)):
				continue
			var step := cell * (1.4142 if int(d[0]) != 0 and int(d[1]) != 0 else 1.0)
			# Dearer the further it strays from its line along the shore.
			var stray := clampf(absf(far[nj * cols + ni] - SHORE_INLAND) / SHORE_INLAND, 0.0, 2.0)
			var nc := cost[cur] + step * (1.0 + SHORE_PULL * stray)
			if nc < cost[nj * cols + ni]:
				if cost[nj * cols + ni] == INF:
					frontier.append(nj * cols + ni)
				cost[nj * cols + ni] = nc
				prev[nj * cols + ni] = cur
	if reached < 0:
		return PackedVector2Array()
	var path := PackedVector2Array([goal_cells[reached]])
	var k := reached
	while k >= 0:
		path.append(at.call(k % cols, k / cols))
		k = prev[k]
	# From the door itself where the way to it is dry; else from the dry ground nearest it.
	if not _sea_between(tile, from, path[path.size() - 1], water):
		path.append(from)
	path.reverse()
	return _ease_off(tile, path, water)


## A cell-by-cell way reduced to its corners, each stretch between them kept off the water.
static func _ease_off(tile: String, path: PackedVector2Array, water: Callable) -> PackedVector2Array:
	var out := PackedVector2Array([path[0]])
	var i := 0
	while i < path.size() - 1:
		var j := path.size() - 1
		while j > i + 1 and (_sea_between(tile, path[i], path[j], water) or _off_line(path, i, j) > SHORE_EASE):
			j -= 1
		out.append(path[j])
		i = j
	return out


## How far the points of a way between i and j stray from the straight line between them.
static func _off_line(path: PackedVector2Array, i: int, j: int) -> float:
	var worst := 0.0
	for k in range(i + 1, j):
		worst = maxf(worst, Geometry2D.get_closest_point_to_segment(path[k], path[i], path[j]).distance_to(path[k]))
	return worst


## Does a way along the streets (node ids) run over open water anywhere: any stretch of it costed as sea.
static func _sea_route(ids: Array, costs: Dictionary) -> bool:
	for i in range(1, ids.size()):
		var a := str(ids[i - 1])
		var b := str(ids[i])
		if float(costs.get((a + "|" + b) if a < b else (b + "|" + a), 0.0)) >= Streets.SEA_COST:
			return true
	return false


## A pipe between two neighbouring tiles' warehouses: out beside the streets to the shared
## edge and in again the same way. It crosses the edge beside the road, not on it.
static func _pipe_way(ta: Dictionary, tb: Dictionary) -> Array:
	var ca: Vector2 = ta["center"]
	var cb: Vector2 = tb["center"]
	var off := cb - ca
	var out_rel: Vector2 = Streets.exit_point(off)
	if out_rel == Vector2.ZERO:
		return [_pt(ca + (ta.get("manifold", Vector2.ZERO) as Vector2), str(ta["id"])),
			_pt(cb + (tb.get("manifold", Vector2.ZERO) as Vector2), str(tb["id"]))]
	var cross: Vector2
	if absf(off.x) < 1.0:
		cross = ca + Vector2(Streets.PIPE_TRUNK_X, out_rel.y)
	else:
		# Along the edge the road is in the middle and the railway to one side of it; the pipe
		# crosses beyond the railway, the same gap again.
		var rail: Vector2 = Rails.exit_point(off)
		cross = ca + rail + (rail - out_rel).normalized() * PIPE_EDGE_GAP
	var pts: Array = []
	for end in [[ta, false], [tb, true]]:
		var tile: Dictionary = end[0]
		var c: Vector2 = tile["center"]
		var rel: Vector2 = cross - c
		var manifold: Vector2 = tile.get("manifold", Streets.pipe_point(Vector2.ZERO))
		# Out by the trunk to the row's line nearest that edge, along it, and off to the edge.
		var line_y := Streets.PIPE_EDGE * (1.0 if rel.y > 0.0 else -1.0)
		var part: Array = []
		if absf(off.x) < 1.0:
			part = Streets.pipe_run(manifold, Vector2(Streets.PIPE_TRUNK_X, line_y))
		else:
			part = Streets.pipe_run(manifold, Vector2(150.0 * signf(rel.x), line_y))
		var here: Array = []
		for q in part:
			here.append(_pt(c + (q as Vector2), str(tile["id"])))
		here.append(_pt(cross, str(tile["id"]), true))
		if bool(end[1]):
			here.reverse()
		pts.append_array(here)
	return pts


## The pipework a tile has: reinforced when that is all it has, plain otherwise, "" for none.
static func _pipe_mode(tile: String) -> String:
	for m in PIPE_MODES:
		if Catalog.tile_has_infrastructure(tile, m):
			return m
	return ""


static func mini_str(a: String, b: String) -> String:
	return a if a < b else b


static func maxi_str(a: String, b: String) -> String:
	return b if a < b else a


static func _internal_name(good_id: String) -> String:
	var g: Dictionary = Catalog.get_good(good_id)
	return str(g.get("internal_name", ""))


static func _is_power(good_id: String) -> bool:
	return Catalog.get_transport_class(good_id) == "electricity"
