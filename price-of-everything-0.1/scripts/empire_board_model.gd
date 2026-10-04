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
##   standing: [{kind, iid, tile, pos, sprite, level, name, side, pad}]  kind: building|site|warehouse|port|pylon
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

## A flat-topped hex of the map's tile size (assets/main_tileset.tres: 540 x 480).
const HEX_HALF := Vector2(270.0, 240.0)
## How tall each kind of tile stands, in map units. Land is a plate over the dark; hills and
## mountains are taller plates. Finer relief is the terraces the board draws on top.
const TILE_HEIGHT := {
	"deep_sea": 6.0, "sea": 10.0, "rural": 34.0, "urban": 34.0, "hill": 66.0, "mountain": 100.0,
}
const DEFAULT_HEIGHT := 34.0
## The footprint a standing thing gets, as a share of its slot. Level 3 is the only one that
## fills it: LEVEL_SHARE sizes a plain block, and a sprite carries its level's size itself.
const FOOT_SHARE := 0.9
const LEVEL_SHARE := {1: 0.72, 2: 0.86, 3: 1.0}
const PORT_BUILDING_ID := "b_004"
const WAREHOUSE_SPRITE := "warehouse"
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


static func tile_height(tile_type: String) -> float:
	return float(TILE_HEIGHT.get(tile_type, DEFAULT_HEIGHT))


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
## on a river while a dry place is free.
## With `town`, housing stands on slots the works leave free.
static func build(terrain: Object, graph: Dictionary, true_pos: Dictionary = {},
		rivers_by_tile: Dictionary = {}, town: bool = false) -> Dictionary:
	var tiles: Dictionary = {}
	var by_tile: Dictionary = {}          # tile_id -> [standing dict]
	var stores: Dictionary = {}           # tile_id -> true: the tile has a warehouse
	var makers: Dictionary = {}           # "tile|good" -> [iid]
	var users: Dictionary = {}            # "tile|good" -> [iid]
	var outputs: Array = []
	var feeds: Array = []                 # [{iid, tile, good, out: bool}] building <-> warehouse
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
			feeds.append({"iid": iid, "tile": tile, "good": g, "out": true})
		var draws := int(recipe.get("energy_req", 0)) > 0
		for ip in recipe.get("inputs", []):
			var gi := str((ip as Dictionary).get("good_id", ""))
			if gi == "":
				continue
			if _is_power(gi):
				draws = true
				continue
			(users.get_or_add(tile + "|" + gi, []) as Array).append(iid)
			feeds.append({"iid": iid, "tile": tile, "good": gi, "out": false})
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

	for tid in drawn:
		var coord: Vector2i = terrain.id_to_coord(str(tid))
		if coord.x < 0:
			continue
		var ttype := str(Catalog.tile_type(str(tid)))
		var c: Vector2 = tile_center(terrain, str(tid))
		tiles[tid] = {
			"id": tid, "center": c, "type": ttype,
			"height": tile_height(ttype), "store": stores.has(tid),
			"label": str(Catalog.tile_label(str(tid))), "hub": c,
			"level": clampi(int(Catalog.tile_infra_level(str(tid), "roads")), 1, 3),
			"paved": Catalog.tile_has_infrastructure(str(tid), "roads"),
			"polluters": int(polluters.get(tid, 0)),
		}
		if pylon_tiles.has(tid):
			tiles[tid]["pylon"] = c + PYLON_AT
			tiles[tid]["power_icon"] = power_icon

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
			if _wet(c, Streets.HUB_SIDE, rivers):
				var nearest: Array = range(Streets.SLOTS.size())
				nearest.sort_custom(func(x: int, y: int) -> bool:
					return (Streets.SLOTS[x] as Vector2).length_squared() < (Streets.SLOTS[y] as Vector2).length_squared())
				for i in nearest:
					if not _wet(c + Streets.SLOTS[i], Streets.SLOT_SIDE, rivers):
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
					ok = ok and i != hub_slot and not _wet(c + Streets.SLOTS[i], Streets.SLOT_SIDE * TOWER_SHARE, rivers)
				if ok:
					tower_slots = pair
					break
		var taken: Array = tower_slots.duplicate()
		if hub_slot >= 0:
			taken.append(hub_slot)
		var free: Array = Streets.places(things.size(), taken)
		for place in free:
			place["wet"] = _wet(c + (place["pos"] as Vector2), float(place["side"]), rivers)
		for thing in things:
			var td: Dictionary = thing
			var want: Vector2 = Streets.SLOTS[0]
			if true_pos.has(str(td["iid"])):
				want = (true_pos[str(td["iid"])] as Vector2) - c
			elif td["kind"] == "port":
				want = Streets.SLOTS[2]
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
			for place in free:
				if homes >= limit:
					break
				if bool(place["wet"]):
					continue
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
				standing.append({"kind": "house", "iid": hid, "tile": tid, "pos": c + (place["pos"] as Vector2),
					"sprite": BuildingSprites.texture_for("house", variety), "level": 3, "name": "Housing",
					"side": float(place["side"]) * FOOT_SHARE, "pad": float(place["side"]), "polluting": false})
				door_of[hid] = Streets.nid(Streets.slot_door(int(place["slot"])))
				homes += 1
		if t.has("pylon"):
			standing.append({"kind": "pylon", "iid": "pylon:" + str(tid), "tile": tid,
				"sprite": BuildingSprites.texture_for("pylon", 1), "level": 3, "pos": t["pylon"],
				"side": PYLON_SIDE, "name": "Power line"})

	# What each tile's rivers add to the stretches of street that cross them.
	var river_cost: Dictionary = {}       # tile_id -> {"a|b": cost}
	for tid in tiles:
		var costs: Dictionary = {}
		var c: Vector2 = tiles[tid]["center"]
		for e in Streets.edges():
			var a: Vector2 = c + Streets.node_pos(str(e[0]))
			var b: Vector2 = c + Streets.node_pos(str(e[1]))
			for line in rivers_by_tile.get(tid, []):
				var pts: PackedVector2Array = line
				for i in range(pts.size() - 1):
					if Geometry2D.segment_intersects_segment(a, b, pts[i], pts[i + 1]) != null:
						costs[str(e[0]) + "|" + str(e[1])] = Streets.RIVER_COST
		river_cost[tid] = costs
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
	var add_feed := func(iid: String, tile: String, good: String, out: bool) -> void:
		var fkey := "%s|%s|%s" % [iid, good, out]
		if seen_feed.has(fkey) or not tiles.has(tile) or not door_of.has(iid):
			return
		seen_feed[fkey] = true
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
			add_feed.call(str(f["iid"]), str(f["tile"]), str(f["good"]), bool(f["out"]))

	# The crossroads before a city's towers: the street past both, the avenue out to the
	# tile's edge and across to the other street.
	for tid in tiles:
		if not tiles[tid].has("crossroads"):
			continue
		var sy := float(tiles[tid]["crossroads"])
		var cross := Streets.nid(Vector2(Streets.AVENUE_X, Streets.STREET_Y * sy))
		for other in [Vector2(Streets.AVENUE_X, Streets.TOP_Y * sy), Vector2(Streets.AVENUE_X, -Streets.STREET_Y * sy),
				Vector2(0.0, Streets.STREET_Y * sy), Vector2(110.0, Streets.STREET_Y * sy)]:
			walk.call(str(tid), [cross, Streets.nid(other)], "roads")

	# A home has its own short way onto the street.
	for st in standing:
		if str(st["kind"]) == "house":
			var door := str(door_of[str(st["iid"])])
			walk.call(str(st["tile"]), route.call(str(st["tile"]), door, str(tiles[str(st["tile"])]["hub_node"])), "roads")

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

	return {"tiles": tiles, "standing": standing, "lines": lines, "roads": roads.values(),
		"flows": flows, "lanes": lane_rows}


## Does a river run under a pad of this side centred at p?
static func _wet(p: Vector2, side: float, rivers: Array) -> bool:
	for line in rivers:
		var pts: PackedVector2Array = line
		for i in range(pts.size() - 1):
			if Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1]).distance_to(p) < side * 0.5 + RIVER_MARGIN:
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
