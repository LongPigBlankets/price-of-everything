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
##   links:    [{a, b, mode, lane, goods}]                           one per tile pair per mode
##   flows:    [{good, icon, kind, path: [{p: Vector2, tile}], hops}]  token paths, tile by tile

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
## slots on a river passed over while enough dry ones remain. Returns {pitch, slots}.
static func slots_for(center: Vector2, count: int, rivers: Array) -> Dictionary:
	var pitch := SLOT_PITCH_MAX
	var slots: Array = []
	while true:
		var all: Array = slot_candidates(center, pitch)
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


## Build the board from the live sim. `terrain` is the HexMap, `graph` is empire_graph.build().
## `rivers_by_tile` is tile_id -> [PackedVector2Array] and `true_pos` maps a building's iid to
## where it really stands on the map (both optional: they only steer which slot a thing takes).
static func build(terrain: Object, graph: Dictionary, rivers_by_tile: Dictionary = {},
		true_pos: Dictionary = {}) -> Dictionary:
	var tiles: Dictionary = {}
	var by_tile: Dictionary = {}          # tile_id -> [standing dict], hub first
	var node_tile: Dictionary = {}        # iid -> tile_id
	var stores: Dictionary = {}           # tile_id -> true: the tile has a warehouse

	for n in graph.get("nodes", []):
		var nd: Dictionary = n
		var tile := str(nd.get("tile_id", ""))
		if tile == "":
			continue
		node_tile[str(nd["iid"])] = tile
		stores[tile] = true
		var site := bool(nd.get("under_construction", false))
		(by_tile.get_or_add(tile, []) as Array).append({
			"kind": "site" if site else "building", "iid": str(nd["iid"]), "tile": tile,
			"sprite": nd.get("sprite"), "level": int(nd.get("level", 1)),
			"name": str(nd.get("name", "")), "icon": nd.get("icon"),
		})
	for key in Stockpile.tiles_with_stock():
		var tid := str(key)
		if tid.begins_with("tile_") and Stockpile.get_used_capacity(tid) > 0:
			stores[tid] = true

	var port_tile: Dictionary = {}        # port iid -> tile_id
	var port_node: Dictionary = {}        # tile_id -> port dict
	for p in graph.get("ports", []):
		var pd: Dictionary = p
		var ptile := str(pd.get("tile_id", ""))
		if ptile == "":
			continue
		port_tile[str(pd["iid"])] = ptile
		port_tile["buy_" + str(pd["iid"])] = ptile
		port_node[ptile] = pd

	# The flows, as tile sequences: where each one starts and ends, and the hops between.
	var raw_flows: Array = []
	var seen: Dictionary = {}
	for e in graph.get("edges", []):
		var ed: Dictionary = e
		var a := str(node_tile.get(str(ed["from"]), ""))
		var b := str(node_tile.get(str(ed["to"]), ""))
		if a == "" or b == "":
			continue
		_add_flow(raw_flows, seen, "supply", str(ed["good"]), str(ed["from"]), str(ed["to"]), a, b)
	for e in graph.get("sell_edges", []):
		var sd: Dictionary = e
		var src_tile := str(node_tile.get(str(sd["from"]), ""))
		if src_tile == "":
			continue
		var dst_tile := str(port_tile.get(str(sd["to"]), ""))
		# Output that is only pooling in the stockpile, or sold through the intermediary, goes
		# as far as the warehouse and no further.
		if dst_tile == "" or not bool(sd.get("actual", true)):
			_add_flow(raw_flows, seen, "store", str(sd["good"]), str(sd["from"]), "", src_tile, src_tile)
		else:
			_add_flow(raw_flows, seen, "sell", str(sd["good"]), str(sd["from"]), "port:" + dst_tile, src_tile, dst_tile)
	for e in graph.get("market_edges", []):
		var md: Dictionary = e
		var to_tile := str(node_tile.get(str(md["to"]), ""))
		var from_tile := str(port_tile.get(str(md["from"]), ""))
		if to_tile == "" or from_tile == "":
			continue
		_add_flow(raw_flows, seen, "buy", str(md["good"]), "port:" + from_tile, str(md["to"]), from_tile, to_tile)
	for s in TransportState.get_pending_transport_shipments():
		var sh: Dictionary = s
		var st := str(sh.get("source_tile", ""))
		var dt := str(sh.get("destination_tile", ""))
		var good := str(sh.get("good_id", ""))
		if not st.begins_with("tile_") or not dt.begins_with("tile_") or good == "" or st == dt:
			continue
		stores[dt] = true
		_add_flow(raw_flows, seen, "shipment", good, "", "", st, dt,
			{"tiles": sh.get("tiles", []), "legs": sh.get("legs", [])})

	# Which tiles are drawn: the ones the company stands on, stores in or routes through.
	var drawn: Dictionary = {}
	for tid in stores:
		drawn[tid] = true
	for f in raw_flows:
		for hop in (f as Dictionary)["hops"]:
			drawn[str(hop["a"])] = true
			drawn[str(hop["b"])] = true
		drawn[str(f["src_tile"])] = true
		drawn[str(f["dst_tile"])] = true
	for tid in drawn:
		var coord: Vector2i = terrain.id_to_coord(str(tid))
		if coord.x < 0:
			continue
		var ttype := str(Catalog.tile_type(str(tid)))
		tiles[tid] = {
			"id": tid, "center": tile_center(terrain, str(tid)), "type": ttype,
			"height": tile_height(ttype), "store": stores.has(tid),
			"label": str(Catalog.tile_label(str(tid))),
		}

	# Stand everything: the warehouse takes the slot nearest the centre, then each building the
	# free slot nearest where it really is on the map.
	var standing: Array = []
	var pos_of: Dictionary = {}           # iid | "store:<tile>" | "port:<tile>" -> Vector2
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
		t["hub"] = t["center"]
		if things.is_empty():
			continue
		var fit: Dictionary = slots_for(t["center"], things.size(), rivers_by_tile.get(tid, []))
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
				t["hub"] = pos
			td["side"] = pitch * FOOT_SHARE * share
			pos_of[str(td["iid"])] = pos
			standing.append(td)

	# Links: one drawn line per tile pair per mode, with a lane so parallel modes sit side by side.
	var link_by_key: Dictionary = {}
	var modes_by_pair: Dictionary = {}
	for f in raw_flows:
		for hop in (f as Dictionary)["hops"]:
			var a := str(hop["a"])
			var b := str(hop["b"])
			var pair := (a + "|" + b) if a < b else (b + "|" + a)
			var key := pair + "|" + str(hop["mode"])
			if not link_by_key.has(key):
				link_by_key[key] = {"a": mini_str(a, b), "b": maxi_str(a, b), "mode": str(hop["mode"]),
					"goods": {}, "pair": pair}
				(modes_by_pair.get_or_add(pair, []) as Array).append(str(hop["mode"]))
			(link_by_key[key]["goods"] as Dictionary)[str(f["good"])] = true
	for key in link_by_key:
		var link: Dictionary = link_by_key[key]
		var modes: Array = modes_by_pair[link["pair"]]
		modes.sort()
		link["lane"] = float(modes.find(link["mode"])) - float(modes.size() - 1) * 0.5

	# Flow paths: building, hub, then tile by tile through the links, hub, building.
	var flows: Array = []
	for f in raw_flows:
		var fd: Dictionary = f
		var path: Array = []
		var src_tile := str(fd["src_tile"])
		var dst_tile := str(fd["dst_tile"])
		if not tiles.has(src_tile) or not tiles.has(dst_tile):
			continue
		var from_key := str(fd["from"])
		if from_key != "" and pos_of.has(from_key):
			path.append({"p": pos_of[from_key], "tile": src_tile, "mode": MODE_DRIVE})
		path.append({"p": tiles[src_tile]["hub"], "tile": src_tile, "mode": MODE_DRIVE})
		for hop in fd["hops"]:
			var a := str(hop["a"])
			var b := str(hop["b"])
			if not tiles.has(a) or not tiles.has(b):
				continue
			var pair := (a + "|" + b) if a < b else (b + "|" + a)
			var lane := float(link_by_key[pair + "|" + str(hop["mode"])]["lane"])
			var mid := crossing(tiles[a]["center"], tiles[b]["center"], lane, a < b)
			path.append({"p": mid, "tile": a, "mode": str(hop["mode"])})
			path.append({"p": mid, "tile": b, "mode": str(hop["mode"])})
			path.append({"p": tiles[b]["hub"], "tile": b, "mode": str(hop["mode"])})
		var to_key := str(fd["to"])
		if to_key != "" and pos_of.has(to_key):
			path.append({"p": pos_of[to_key], "tile": dst_tile, "mode": MODE_DRIVE})
		if path.size() < 2:
			continue
		flows.append({"good": str(fd["good"]), "kind": str(fd["kind"]), "path": path,
			"from": from_key, "to": to_key,
			"icon": GoodIcons.texture_for(str(fd["good"]), _internal_name(str(fd["good"])))})

	return {"tiles": tiles, "standing": standing, "links": link_by_key.values(), "flows": flows}


## Where a link crosses from one tile to the next: the midpoint of the shared edge, moved
## sideways by its lane. `forward` says the hop runs in the pair's own order, so both
## directions of a link share one crossing.
const LANE_GAP := 22.0
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


static func _add_flow(out: Array, seen: Dictionary, kind: String, good: String, from: String,
		to: String, src_tile: String, dst_tile: String, route: Dictionary = {}) -> void:
	var key := "%s|%s|%s|%s|%s" % [good, from, to, src_tile, dst_tile]
	if seen.has(key):
		return
	seen[key] = true
	var hops: Array = []
	if src_tile != dst_tile:
		var power := _is_power(good)
		var r: Dictionary = route
		if r.is_empty():
			# Power has no goods route; its line follows the ordinary way between the tiles.
			r = TransportService.route(src_tile, dst_tile, "" if power else good)
		hops = route_hops(r)
		if power:
			for hop in hops:
				hop["mode"] = MODE_CABLE
		# No way through (a fluid with no pipe, say): the goods get as far as the warehouse.
		if hops.is_empty():
			out.append({"kind": "blocked", "good": good, "from": from, "to": "",
				"src_tile": src_tile, "dst_tile": src_tile, "hops": []})
			return
	out.append({"kind": kind, "good": good, "from": from, "to": to,
		"src_tile": src_tile, "dst_tile": dst_tile, "hops": hops})
