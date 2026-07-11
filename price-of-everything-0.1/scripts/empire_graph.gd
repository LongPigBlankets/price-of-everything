extends RefCounted
## Empire view — graph builder (Milestone 2).
##
## Reads the live sim (read-only, CLAUDE.md rule #5) and produces the node + edge lists the
## Empire view renders. Nodes = the player's own production / power / battery buildings. Ports
## come from Catalog.all_ports() and are kept in a separate list (drawn as gold hexagons later).
## All other NPC buildings and all infrastructure are excluded.
##
## Edges are a static "source of inputs" capability graph: building A (produces good g) -> building
## B (consumes good g). The sim pools goods per tile and does not record building->building routing,
## so this is inferred from recipes — same model as build_goods_flow.py. No per-turn volumes.
##
## Returned shape:
##   { nodes: Array[Dictionary], ports: Array[Dictionary], edges: Array[Dictionary], signature: String }
## Node dict: { iid, building_id, name, level, output_good, output_qty, seed:Vector2, half:Vector2, is_port }
## Edge dict: { from:iid, to:iid, good:good_id }

const EmpireLayout := preload("res://scripts/empire_layout.gd")
const BuildingLevels := preload("res://scripts/building_levels.gd")
const BuildingStatus := preload("res://scripts/building_status.gd")
const BuildingIcon := preload("res://scripts/building_icon.gd")
const GoodIcons := preload("res://scripts/good_icons.gd")
const BuildingNaming := preload("res://scripts/building_naming.gd")

const PORT_BUILDING_ID := "b_004"
const BASE_HALF := Vector2(152.0, 90.0)           # L1 panel half-extent in layout px; level-scaled per node
const PORT_HALF := Vector2(86.0, 78.0)            # gold port hexagon half-extent

# Ports always read left -> right in this order. Matched as case-insensitive substrings of the name.
const PORT_ORDER := ["stoneshore", "arin", "vandel", "capital"]


static func build(terrain: Object) -> Dictionary:
	var nodes: Array = []
	var ports: Array = []
	var producers: Dictionary = {}                # good_id -> [iid]
	var consumers: Dictionary = {}                # good_id -> [iid]
	var idx := 0

	for b in MatchState.buildings.values():
		idx += 1
		if not MatchState.is_player_owned(b):
			continue
		var bid := str(b.get("building_id", ""))
		if bid == PORT_BUILDING_ID:
			continue                              # ports drawn separately
		var bdata: Dictionary = Catalog.get_building(bid)
		if str(bdata.get("category", "")) == "infrastructure":
			continue                              # roads / cables / pipes / rails hidden
		var iid := str(b.get("instance_id", ""))
		var level := int(b.get("level", 1))
		var recipe: Dictionary = Catalog.get_recipe(str(b.get("recipe_id", "")))
		var outs: Array = recipe.get("outputs", [])
		var out_good := ""
		var out_name := ""
		var out_internal := ""
		var out_qty := 0
		var good_icon: Texture2D = null
		if outs.size() > 0:
			out_good = str((outs[0] as Dictionary).get("good_id", ""))
			out_internal = str((outs[0] as Dictionary).get("internal_name", ""))
			out_qty = int(round(float((outs[0] as Dictionary).get("qty", 0)) * BuildingLevels.mult("output", level)))
			out_name = _good_name(out_good)
			if out_good != "":
				good_icon = GoodIcons.texture_for(out_good, out_internal, true)

		nodes.append({
			"iid": iid,
			"building_id": bid,
			# Full public name: "<Type> - <Output> - <Letter>" (shared with the detail panel).
			"name": BuildingNaming.label_for_tile(str(b.get("tile_id", "")), iid, bid, str(b.get("recipe_id", ""))),
			"level": level,
			"output_good": out_good,
			"output_name": out_name,
			"output_qty": out_qty,
			"tile_id": str(b.get("tile_id", "")),
			"seed": _tile_world_pos(terrain, str(b.get("tile_id", "")), idx),
			"half": BASE_HALF * EmpireLayout.level_scale(level),
			"is_port": false,
			"icon": BuildingIcon.clean_texture(bid, str(bdata.get("internal_name", ""))),
			"good_icon": good_icon,
			# The six RAG indicators as DATA, computed once here (single source: building_status.gd).
			"rag": BuildingStatus.rag_indicators(b, recipe, false),
		})

		for o in outs:
			var g := str((o as Dictionary).get("good_id", ""))
			if g != "":
				_append(producers, g, iid)
		for ip in recipe.get("inputs", []):
			var gi := str((ip as Dictionary).get("good_id", ""))
			if gi != "":
				_append(consumers, gi, iid)

	var port_internal := str(Catalog.get_building(PORT_BUILDING_ID).get("internal_name", "port"))
	var port_icon: Texture2D = BuildingIcon.clean_texture(PORT_BUILDING_ID, port_internal)
	var pidx := 0
	for p in Catalog.all_ports():
		var pname := str((p as Dictionary).get("name", "Port"))
		ports.append({
			"iid": "port_" + str((p as Dictionary).get("id", pidx)),
			"building_id": PORT_BUILDING_ID,
			"name": pname,
			"level": 1,
			"output_good": "",
			"output_qty": 0,
			"tile_id": str((p as Dictionary).get("tile_id", "")),
			"order": _port_order(pname),
			"seed": _tile_world_pos(terrain, str((p as Dictionary).get("tile_id", "")), 100000 + pidx),
			"half": PORT_HALF,
			"is_port": true,
			"icon": port_icon,
		})
		pidx += 1
	# Fixed left-to-right port order: Stoneshore, Arin, Vandel, Capital.
	ports.sort_custom(func(a, b):
		if int(a["order"]) != int(b["order"]):
			return int(a["order"]) < int(b["order"])
		return str(a["name"]) < str(b["name"]))

	return {
		"nodes": nodes,
		"ports": ports,
		"edges": _build_edges(producers, consumers),
		"sell_edges": _build_sell_edges(nodes, ports, consumers),
		"signature": _signature(nodes),
	}


## Market-sale edges: a building whose output good is NOT consumed by any player building is
## attached to its nearest export port. Drawn SOLID when the output actually ships to market
## (explicit market route, global sell-all, or the tile's sell-surplus toggle) and DASHED when
## it is only the standing default — "this is where sales would leave" (goods are in fact
## pooling in the tile stockpile). A building explicitly routed to another tile gets no port
## edge at all: the player gave a different directive. (Nearest port is a heuristic — the sim
## pools/sells per turn without recording the exact export port.)
static func _build_sell_edges(nodes: Array, ports: Array, consumers: Dictionary) -> Array:
	var port_by_tile: Dictionary = {}
	for p in ports:
		port_by_tile[str(p["tile_id"])] = str(p["iid"])
	var sell: Array = []
	for n in nodes:
		var og := str(n["output_good"])
		if og == "":
			continue
		if consumers.has(og) and not (consumers[og] as Array).is_empty():
			continue                                  # consumed internally -> not a market sale
		if not Catalog.has_method("nearest_port_tile"):
			continue
		var iid := str(n["iid"])
		var tile := str(n["tile_id"])
		if MatchState.get_output_stockpile_destination(iid, og) != "":
			continue                                  # explicitly routed to a tile -> no port edge
		var actual := MatchState.is_output_market(iid, og) \
			or MatchState.sell_mode == MatchState.SellMode.SELL_ALL \
			or MatchState.is_sell_surplus_enabled(tile)
		var ptile := str(Catalog.nearest_port_tile(tile))
		if ptile != "" and port_by_tile.has(ptile):
			sell.append({"from": iid, "to": port_by_tile[ptile], "good": og, "actual": actual})
	return sell


static func _port_order(name: String) -> int:
	var lname := name.to_lower()
	for i in range(PORT_ORDER.size()):
		if lname.contains(PORT_ORDER[i]):
			return i
	return PORT_ORDER.size()


## Producer good ∩ consumer good -> directed edge, deduped by (from,to).
static func _build_edges(producers: Dictionary, consumers: Dictionary) -> Array:
	var edge_map: Dictionary = {}
	for g in producers:
		if not consumers.has(g):
			continue
		for a in producers[g]:
			for b in consumers[g]:
				if a == b:
					continue
				var key: String = str(a) + "|" + str(b)
				if not edge_map.has(key):
					edge_map[key] = {"from": a, "to": b, "good": g}
	return edge_map.values()


## Good display name for a good_id, falling back to the id if the catalog can't resolve it.
static func _good_name(good_id: String) -> String:
	if good_id == "":
		return ""
	if Catalog.has_method("get_display_name"):
		var dn := str(Catalog.get_display_name(good_id))
		if dn != "":
			return dn
	return good_id


static func _append(d: Dictionary, key: String, value: String) -> void:
	if not d.has(key):
		d[key] = []
	(d[key] as Array).append(value)


## World position of a tile's centre via the HexMap (group "hex_map"). Falls back to a spread
## grid when no terrain is available (e.g. headless tests), so build() never hard-depends on it.
static func _tile_world_pos(terrain: Object, tile_id: String, fallback_index: int) -> Vector2:
	if terrain != null and is_instance_valid(terrain) \
			and terrain.has_method("id_to_coord") \
			and terrain.has_method("map_coord_for_tile_coord") \
			and terrain.has_method("map_to_local") \
			and tile_id != "":
		var coord = terrain.id_to_coord(tile_id)
		return terrain.map_to_local(terrain.map_coord_for_tile_coord(coord))
	return Vector2(float(fallback_index % 8) * 240.0, float(fallback_index / 8) * 180.0)


## Stable signature of the empire's shape, so the view can skip rebuilding when nothing changed.
static func _signature(nodes: Array) -> String:
	var parts: Array = []
	for n in nodes:
		parts.append("%s:%d:%s" % [n["iid"], int(n["level"]), str(n["output_good"])])
	parts.sort()
	return "|".join(parts)
