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
##   tiles:    tile_id -> {id, center, type, height, store, label}
##   standing: [{kind, iid, tile, pos, sprite, level, name, side}]   kind: building|site|warehouse|port
##   lines:    [{mode, good, kind, pts: [{p, tile, edge}], ends}]    every drawn way, in plan
##   flows:    [{good, icon, kind, mode, pts: [{p, tile, edge}], live}]  what travels them
##   lanes:    [{kind, good, from, to, sources, dests, live}]         the real movements behind them
##
## REAL MOVEMENTS. A line between two tiles is drawn only where goods really move: a shipment
## in transit, a trade or move the ledgers logged in the last few turns, a standing move
## order, or a building whose output is routed to another tile or to market. Each movement is
## mapped to the buildings it comes from (the ones on the source tile that make the good) and
## goes to (the ones on the destination tile that use it, or the site it was ordered for).

const BuildingSprites := preload("res://scripts/building_sprites.gd")
const GoodIcons := preload("res://scripts/good_icons.gd")

## A flat-topped hex of the map's tile size (assets/main_tileset.tres: 540 x 480).
const HEX_HALF := Vector2(270.0, 240.0)
## How tall each kind of tile stands, in map units. Land is a plate over the dark; hills and
## mountains are taller plates. Finer relief is the terraces the board draws on top.
const TILE_HEIGHT := {
	"deep_sea": 6.0, "sea": 10.0, "rural": 34.0, "urban": 34.0, "hill": 66.0, "mountain": 100.0,
}
const DEFAULT_HEIGHT := 34.0
## Slot lattice: the pitch starts here and tightens until the tile's standing things all fit.
const SLOT_PITCH_MAX := 190.0
const SLOT_PITCH_MIN := 60.0
const SLOT_PITCH_STEP := 10.0
## A slot keeps this share of the pitch clear of the tile's edge.
const SLOT_EDGE_SHARE := 0.34
## A slot this close to a river is passed over while enough dry ones remain.
const RIVER_CLEAR := 46.0
## The footprint a standing thing gets, as a share of the slot pitch. Level 3 is the only one
## that fills it: LEVEL_SHARE sizes a plain block, and a sprite carries its level's size itself.
const FOOT_SHARE := 0.62
const LEVEL_SHARE := {1: 0.72, 2: 0.86, 3: 1.0}
const WAREHOUSE_SHARE := 0.85
const PORT_BUILDING_ID := "b_004"
const WAREHOUSE_SPRITE := "warehouse"
## The mode drawn for power: cables carry it, and no goods route does.
const MODE_CABLE := "cables"
## A ledger entry this many turns old still counts as a way goods move.
const RECENT_TURNS := 3
## The tile corner the pylon stands near: the far one, so it hides nothing.
const PYLON_CORNER := Vector2(-135.0, -240.0)
const PYLON_INSET := 0.74
const PYLON_SIDE := 80.0
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


## Candidate standing positions on one tile at lattice pitch `pitch`: a hex lattice through the
## tile centre, kept clear of the tile's edge. Ordered centre outward, so the first is the hub.
static func slot_candidates(center: Vector2, pitch: float) -> Array:
	var keep := 1.0 - pitch * SLOT_EDGE_SHARE / HEX_HALF.y
	var inner := PackedVector2Array()
	for p in hex_points(Vector2.ZERO):
		inner.append(p * keep)
	var out: Array = []
	var reach := int(ceil(HEX_HALF.x / pitch)) + 1
	for j in range(-reach, reach + 1):
		for i in range(-reach, reach + 1):
			var p := Vector2((float(i) + (0.5 if (j & 1) != 0 else 0.0)) * pitch, float(j) * pitch * 0.8660254)
			if Geometry2D.is_point_in_polygon(p, inner):
				out.append(center + p)
	out.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		var da := (a - center).length_squared()
		var db := (b - center).length_squared()
		if absf(da - db) > 0.5:
			return da < db
		return (a - center).angle() < (b - center).angle())
	return out


## The slots for `count` standing things on a tile: the widest lattice that holds them, with
## slots on a river passed over while enough dry ones remain, and none beside an `avoid` point
## (the tile's pylon). Returns {pitch, slots}.
static func slots_for(center: Vector2, count: int, rivers: Array, avoid: Array = []) -> Dictionary:
	var pitch := SLOT_PITCH_MAX
	var slots: Array = []
	while true:
		var all: Array = []
		for p in slot_candidates(center, pitch):
			var clear := true
			for a in avoid:
				clear = clear and (p as Vector2).distance_to(a) >= pitch * 0.6
			if clear:
				all.append(p)
		var dry: Array = []
		for p in all:
			if not _near_river(p, rivers):
				dry.append(p)
		slots = dry if dry.size() >= count else all
		if slots.size() >= count or pitch <= SLOT_PITCH_MIN:
			break
		pitch -= SLOT_PITCH_STEP
	return {"pitch": pitch, "slots": slots}


static func _near_river(p: Vector2, rivers: Array) -> bool:
	for line in rivers:
		var pts: PackedVector2Array = line
		for i in range(pts.size() - 1):
			if Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1]).distance_to(p) < RIVER_CLEAR:
				return true
	return false


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
	# Standing output routes: a building told to send its output to another tile, or to market.
	for o in outputs:
		var od: Dictionary = o
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
## `rivers_by_tile` is tile_id -> [PackedVector2Array] and `true_pos` maps a building's iid to
## where it really stands on the map (both optional: they only steer which slot a thing takes).
static func build(terrain: Object, graph: Dictionary, rivers_by_tile: Dictionary = {},
		true_pos: Dictionary = {}) -> Dictionary:
	var tiles: Dictionary = {}
	var by_tile: Dictionary = {}          # tile_id -> [standing dict]
	var stores: Dictionary = {}           # tile_id -> true: the tile has a warehouse
	var makers: Dictionary = {}           # "tile|good" -> [iid]
	var users: Dictionary = {}            # "tile|good" -> [iid]
	var outputs: Array = []
	var feeds: Array = []                 # [{iid, tile, good, out: bool}] building <-> warehouse
	var power_ends: Array = []            # [{iid, tile, out: bool}]

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
		})
		if site:
			continue
		var b: Dictionary = BuildingState.buildings.get(iid, {})
		var recipe: Dictionary = Catalog.get_recipe(str(b.get("recipe_id", "")))
		for o in recipe.get("outputs", []):
			var g := str((o as Dictionary).get("good_id", ""))
			if g == "":
				continue
			if _is_power(g):
				power_ends.append({"iid": iid, "tile": tile, "out": true})
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

	for tid in drawn:
		var coord: Vector2i = terrain.id_to_coord(str(tid))
		if coord.x < 0:
			continue
		var ttype := str(Catalog.tile_type(str(tid)))
		var c: Vector2 = tile_center(terrain, str(tid))
		tiles[tid] = {
			"id": tid, "center": c, "type": ttype,
			"height": tile_height(ttype), "store": stores.has(tid),
			"label": str(Catalog.tile_label(str(tid))),
			"hub": c, "junction": c, "pipe_node": c + Vector2(34.0, -34.0),
		}
		if pylon_tiles.has(tid):
			tiles[tid]["pylon"] = c + PYLON_CORNER * PYLON_INSET

	# Stand everything: the warehouse takes the slot nearest the centre, then each building the
	# free slot nearest where it really is on the map.
	var standing: Array = []
	var pos_of: Dictionary = {}           # iid | "store:<tile>" | "port:<tile>" -> Vector2
	var side_of: Dictionary = {}
	for tid in tiles:
		var t: Dictionary = tiles[tid]
		var things: Array = []
		if bool(t["store"]):
			things.append({"kind": "warehouse", "iid": "store:" + str(tid), "tile": tid,
				"sprite": BuildingSprites.texture_for(WAREHOUSE_SPRITE, Stockpile.get_warehouse_level(tid)),
				"level": Stockpile.get_warehouse_level(tid), "name": "%s warehouse" % str(t["label"])})
		if port_node.has(tid):
			var pn: Dictionary = port_node[tid]
			things.append({"kind": "port", "iid": "port:" + str(tid), "tile": tid,
				"sprite": BuildingSprites.texture_for("port", 1), "level": 3,
				"name": str(pn.get("name", "Port")), "port_iid": str(pn["iid"])})
		var own: Array = by_tile.get(tid, [])
		own.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return str(x["iid"]) < str(y["iid"]))
		things.append_array(own)
		if not things.is_empty():
			var fit: Dictionary = slots_for(t["center"], things.size(), rivers_by_tile.get(tid, []),
				[t["pylon"]] if t.has("pylon") else [])
			var free: Array = (fit["slots"] as Array).duplicate()
			var pitch := float(fit["pitch"])
			t["pitch"] = pitch
			for thing in things:
				var td: Dictionary = thing
				var want: Vector2 = t["center"]
				if td["kind"] != "warehouse" and true_pos.has(str(td["iid"])):
					want = true_pos[str(td["iid"])]
				elif td["kind"] == "port":
					want = (t["center"] as Vector2) + Vector2(HEX_HALF.x, HEX_HALF.y) * 0.5
				var pos: Vector2 = want
				if not free.is_empty():
					var best := 0
					for i in range(1, free.size()):
						if (free[i] as Vector2).distance_squared_to(want) < (free[best] as Vector2).distance_squared_to(want):
							best = i
					pos = free[best]
					free.remove_at(best)
				td["pos"] = pos
				# A sprite set shares one scale, so a level 1 sprite is already drawn smaller inside
				# its frame; only a plain block needs the level's share applied here.
				var share := 1.0
				if td.get("sprite") == null:
					share = float(LEVEL_SHARE.get(clampi(int(td["level"]), 1, 3), 1.0))
				if td["kind"] == "warehouse":
					share *= WAREHOUSE_SHARE
				td["side"] = pitch * FOOT_SHARE * share
				if td["kind"] == "warehouse":
					# Roads meet on one side of the warehouse and pipes on another: in front of its
					# dock and at its right hand when it stands at the tile's centre, and otherwise
					# on whichever sides face the centre, so neither ends up off the tile.
					t["hub"] = pos
					var reach := float(td["side"]) * 0.95
					var sides: Array = [Vector2(0.0, reach), Vector2(reach, 0.0), Vector2(-reach, 0.0), Vector2(0.0, -reach)]
					var centre: Vector2 = t["center"]
					var rank := func(o: Vector2) -> float: return (pos + o).distance_to(centre)
					for i in range(sides.size()):
						for j in range(i + 1, sides.size()):
							if rank.call(sides[j]) < rank.call(sides[i]) - 0.5:
								var swap: Vector2 = sides[i]
								sides[i] = sides[j]
								sides[j] = swap
					t["junction"] = pos + sides[0]
					t["pipe_node"] = pos + sides[1]
				pos_of[str(td["iid"])] = pos
				side_of[str(td["iid"])] = float(td["side"])
				standing.append(td)
		if t.has("pylon"):
			standing.append({"kind": "pylon", "iid": "pylon:" + str(tid), "tile": tid,
				"sprite": BuildingSprites.texture_for("pylon", 1), "level": 3, "pos": t["pylon"],
				"side": PYLON_SIDE, "name": "Power line"})

	# Lanes across each tile edge: every road-like mode shares one way; each piped good has its own.
	var ways: Dictionary = {}             # "pair|mode|good" -> {a, b, mode, good}
	var ways_by_pair: Dictionary = {}
	for key in lanes:
		var lane: Dictionary = lanes[key]
		for hop in lane["hops"]:
			var a := str(hop["a"])
			var b := str(hop["b"])
			if not tiles.has(a) or not tiles.has(b):
				continue
			var mode := str(hop["mode"])
			var piped := PIPE_MODES.has(mode)
			var pair := mini_str(a, b) + "|" + maxi_str(a, b)
			var wkey := "%s|%s|%s" % [pair, mode, str(lane["good"]) if piped else ""]
			hop["way"] = wkey
			if not ways.has(wkey):
				ways[wkey] = {"a": mini_str(a, b), "b": maxi_str(a, b), "mode": mode,
					"good": str(lane["good"]) if piped else "", "pair": pair, "key": wkey,
					"reverse": a != mini_str(a, b)}
				(ways_by_pair.get_or_add(pair, []) as Array).append(wkey)
	for pair in ways_by_pair:
		var keys: Array = ways_by_pair[pair]
		keys.sort()
		for i in range(keys.size()):
			ways[keys[i]]["lane"] = float(i) - float(keys.size() - 1) * 0.5

	var lines: Array = []
	var flows: Array = []
	var seen_line: Dictionary = {}
	# The ways between tiles.
	for wkey in ways:
		var w: Dictionary = ways[wkey]
		var ta: Dictionary = tiles[w["a"]]
		var tb: Dictionary = tiles[w["b"]]
		var node := "pipe_node" if PIPE_MODES.has(str(w["mode"])) else "junction"
		# Two tiles that do not touch have no shared edge to cross: the way runs straight over.
		if (ta["center"] as Vector2).distance_to(tb["center"]) > ADJACENT_REACH:
			w["mid"] = null
			lines.append({"mode": str(w["mode"]), "good": str(w["good"]), "kind": "way",
				"reverse": bool(w["reverse"]),
				"pts": [_pt(ta[node], str(w["a"])), _pt(tb[node], str(w["b"]))]})
			continue
		var mid := crossing(ta["center"], tb["center"], float(w["lane"]), true)
		w["mid"] = mid
		lines.append({"mode": str(w["mode"]), "good": str(w["good"]), "kind": "way",
			"reverse": bool(w["reverse"]),
			"pts": [_pt(ta[node], str(w["a"])), _pt(mid, str(w["a"]), true),
				_pt(mid, str(w["b"]), true), _pt(tb[node], str(w["b"]))]})

	# A building's own run to its tile's warehouse: a pipe for a fluid on a piped tile, a drive
	# for everything else. One per building per good for pipes, one drive per building.
	var feed_line := func(iid: String, tile: String, good: String, toward_thing: bool = false) -> Array:
		if not tiles.has(tile) or not pos_of.has(iid):
			return []
		var t: Dictionary = tiles[tile]
		var piped: bool = Catalog.requires_pipeline(good) and _tile_piped(tile)
		var mode := "pipes" if piped else MODE_DRIVE
		var from: Vector2 = pos_of[iid]
		var pts: Array
		if piped:
			# The pipe leaves the ground beside the building, not from inside it.
			var dir := ((t["pipe_node"] as Vector2) - from).normalized()
			pts = [_pt(from + dir * float(side_of.get(iid, 40.0)) * 0.72, tile), _pt(t["pipe_node"], tile)]
		else:
			pts = [_pt(from, tile), _pt(t["junction"], tile)]
		var lkey := "%s|%s|%s" % [iid, mode, good if piped else ""]
		if not seen_line.has(lkey):
			seen_line[lkey] = true
			# `reverse` says what the line carries runs against the order of its points.
			lines.append({"mode": mode, "good": good if piped else "", "kind": "feed", "pts": pts,
				"reverse": toward_thing})
		return [mode, pts]
	var seen_feed: Dictionary = {}
	var add_feed := func(iid: String, tile: String, good: String, out: bool, kind: String) -> void:
		var fkey := "%s|%s|%s" % [iid, good, out]
		if seen_feed.has(fkey):
			return
		seen_feed[fkey] = true
		var made: Array = feed_line.call(iid, tile, good, not out)
		if made.is_empty():
			return
		var pts: Array = (made[1] as Array).duplicate()
		if not out:
			pts.reverse()
		flows.append({"good": good, "kind": kind, "mode": str(made[0]), "pts": pts, "live": [],
			"icon": GoodIcons.texture_for(good, _internal_name(good))})
	for f in feeds:
		if tiles.has(str(f["tile"])) and bool(tiles[str(f["tile"])]["store"]):
			add_feed.call(str(f["iid"]), str(f["tile"]), str(f["good"]), bool(f["out"]), "feed")

	# Each real movement: its trunk from tile to tile, and the buildings at either end.
	var lane_rows: Array = []
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
				add_feed.call(str(sid), to_tile, good, false, "feed")
		lane_rows.append({"kind": lane["kind"], "good": good, "from": from_tile, "to": to_tile,
			"sources": sources, "dests": dests, "live": lane["live"], "hops": lane["hops"]})
		var pts: Array = []
		var first_mode := str(lane["hops"][0]["mode"]) if not (lane["hops"] as Array).is_empty() else MODE_DRIVE
		var piped_first := PIPE_MODES.has(first_mode)
		# A purchase starts at the port, a sale ends at one; everything else runs hub to hub.
		var from_port := str(lane["kind"]) == "buy" and pos_of.has("port:" + from_tile)
		var to_port := str(lane["kind"]) == "sell" and pos_of.has("port:" + to_tile)
		if from_port:
			var made: Array = feed_line.call("port:" + from_tile, from_tile, good) if not (lane["hops"] as Array).is_empty() and piped_first else []
			if made.is_empty():
				pts.append(_pt(pos_of["port:" + from_tile], from_tile))
				_port_drive(lines, seen_line, tiles, pos_of, from_tile)
			else:
				pts.append_array(made[1])
		if pts.is_empty() or not ((pts[pts.size() - 1]["p"] as Vector2).is_equal_approx(tiles[from_tile]["pipe_node" if piped_first else "junction"])):
			pts.append(_pt(tiles[from_tile]["pipe_node" if piped_first else "junction"], from_tile))
		var last_mode := first_mode
		for hop in lane["hops"]:
			if not hop.has("way"):
				continue
			var w: Dictionary = ways[hop["way"]]
			var b := str(hop["b"])
			last_mode = str(hop["mode"])
			if w["mid"] != null:
				pts.append(_pt(w["mid"], str(hop["a"]), true))
				pts.append(_pt(w["mid"], b, true))
			pts.append(_pt(tiles[b]["pipe_node" if PIPE_MODES.has(last_mode) else "junction"], b))
		if to_port:
			var piped_last := PIPE_MODES.has(last_mode)
			if piped_last:
				var made2: Array = feed_line.call("port:" + to_tile, to_tile, good, true)
				if not made2.is_empty():
					pts.append((made2[1] as Array)[0])
			else:
				pts.append(_pt(pos_of["port:" + to_tile], to_tile))
				_port_drive(lines, seen_line, tiles, pos_of, to_tile)
		if pts.size() < 2:
			continue
		flows.append({"good": good, "kind": str(lane["kind"]), "mode": last_mode, "pts": pts,
			"live": lane["live"], "icon": GoodIcons.texture_for(good, _internal_name(good))})

	# Cables: each power building to its tile's pylon, and pylon to pylon between tiles.
	for pe in power_ends:
		var tile := str(pe["tile"])
		if not tiles.has(tile) or not tiles[tile].has("pylon") or not pos_of.has(str(pe["iid"])):
			continue
		var pts: Array = [_pt(pos_of[str(pe["iid"])], tile), _pt(tiles[tile]["pylon"], tile)]
		var ids: Array = [str(pe["iid"]), "pylon:" + tile]
		lines.append({"mode": MODE_CABLE, "good": "", "kind": "feed", "pts": pts, "ids": ids})
		flows.append({"good": "", "kind": "power", "mode": MODE_CABLE, "pts": pts, "ids": ids,
			"reverse": not bool(pe["out"]), "live": [], "icon": null})
	for ck in cable_links:
		var a := str(ck).get_slice("|", 0)
		var b := str(ck).get_slice("|", 1)
		if tiles.has(a) and tiles.has(b) and tiles[a].has("pylon") and tiles[b].has("pylon"):
			lines.append({"mode": MODE_CABLE, "good": "", "kind": "way",
				"pts": [_pt(tiles[a]["pylon"], a), _pt(tiles[b]["pylon"], b)],
				"ids": ["pylon:" + a, "pylon:" + b]})

	return {"tiles": tiles, "standing": standing, "lines": lines, "flows": flows, "lanes": lane_rows}


## A port's own short road to its tile's junction, drawn once.
static func _port_drive(lines: Array, seen: Dictionary, tiles: Dictionary, pos_of: Dictionary, tile: String) -> void:
	var key := "port:%s|drive" % tile
	if seen.has(key):
		return
	seen[key] = true
	lines.append({"mode": MODE_DRIVE, "good": "", "kind": "feed",
		"pts": [_pt(pos_of["port:" + tile], tile), _pt(tiles[tile]["junction"], tile)]})


static func _tile_piped(tile: String) -> bool:
	for m in PIPE_MODES:
		if Catalog.tile_has_infrastructure(tile, m):
			return true
	return false


## Where a way crosses from one tile to the next: the midpoint of the shared edge, moved
## sideways by its lane. `forward` says the hop runs in the pair's own order, so both
## directions of a way share one crossing.
const LANE_GAP := 30.0
static func crossing(ca: Vector2, cb: Vector2, lane: float, forward: bool) -> Vector2:
	var dir := (cb - ca).normalized()
	if not forward:
		dir = -dir
	return (ca + cb) * 0.5 + dir.orthogonal() * lane * LANE_GAP


static func mini_str(a: String, b: String) -> String:
	return a if a < b else b


static func maxi_str(a: String, b: String) -> String:
	return b if a < b else a


static func _internal_name(good_id: String) -> String:
	var g: Dictionary = Catalog.get_good(good_id)
	return str(g.get("internal_name", ""))


static func _is_power(good_id: String) -> bool:
	return Catalog.get_transport_class(good_id) == "electricity"
