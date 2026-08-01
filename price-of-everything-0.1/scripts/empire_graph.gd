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
const BuildingSprites := preload("res://scripts/building_sprites.gd")
const GoodIcons := preload("res://scripts/good_icons.gd")
const BuildingNaming := preload("res://scripts/building_naming.gd")
const NodePanel := preload("res://scripts/empire_node_panel.gd")

const PORT_BUILDING_ID := "b_004"
const BASE_HALF := Vector2(152.0, 90.0)           # L1 panel half-extent in layout px; level-scaled per node


## The sprite's opaque content as a rect measured from the PANEL CENTRE, in unscaled panel px.
## The 800px texture is drawn into a SPRITE_PX box (aspect-kept, so a uniform half scale) at the
## top of the panel, and the panel centre sits SPRITE_PX/2 above the plate — hence the offset.
static func _sprite_content_offset(sprite_tex) -> Rect2:
	if not (MatchState.use_empire_sprite_view and sprite_tex != null):
		return Rect2()
	var used: Rect2 = BuildingSprites.content_rect(sprite_tex)
	if used.size.x <= 0.0 or used.size.y <= 0.0:
		return Rect2()
	var k: float = NodePanel.SPRITE_PX / maxf(1.0, float(sprite_tex.get_width()))
	var centre := Vector2(NodePanel.SPRITE_PX * 0.5,
			(NodePanel.SPRITE_PX + BASE_HALF.y * 2.0) * 0.5)
	return Rect2(used.position * k - centre, used.size * k)


## Half-extent of a node as the layout must see it. Classic: the level-scaled plate. Sprite
## view: a box wide enough for the sprite and tall enough for sprite + plate, centred on the
## Control (which is why `plate_dy` is exactly half the sprite height).
static func _node_half(level: int, sprite_tex) -> Vector2:
	var plate: Vector2 = BASE_HALF * EmpireLayout.level_scale(level)
	if not (MatchState.use_empire_sprite_view and sprite_tex != null):
		return plate
	return Vector2(maxf(BASE_HALF.x, NodePanel.SPRITE_PX * 0.5),
			(NodePanel.SPRITE_PX + BASE_HALF.y * 2.0) * 0.5)
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
		var sprite_tex: Texture2D = BuildingSprites.texture_for(str(bdata.get("internal_name", "")), level)

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
			# The half-extent the LAYOUT separates by. In sprite view the panel is not the
			# plate: it is SPRITE_PX tall growing UPWARD with the plate hung beneath, so
			# separating by the plate alone let sprites sit on top of their neighbours and
			# on the port hexes above them. Plates stay L1-sized in sprite view (the sprite
			# carries the level), which is why this does not level-scale.
			"half": _node_half(level, sprite_tex),
			# The PLATE's own half-extent — what edges anchor to. Distinct from `half`, which
			# is the layout footprint: in sprite view those differ by the whole 400px sprite,
			# and anchoring to `half` puts every arrow out in open space beside the plate.
			# Plates stay L1-sized in sprite view, so this does not level-scale there either.
			"plate_half": (BASE_HALF if (MatchState.use_empire_sprite_view and sprite_tex != null)
					else BASE_HALF * EmpireLayout.level_scale(level)),
			# The sprite's OPAQUE box, as an offset rect from the panel centre (unscaled px).
			# Routing may cross a sprite's transparent padding — that is the whole point of
			# dropping the sprite behind the lines — but never the building itself.
			"sprite_rect": _sprite_content_offset(sprite_tex),
			# Set below once the sell edges are known: the icon of the port this building
			# ships to, which the plate wears as a gold hex badge instead of drawing a line
			# across the whole view. Null on buildings that do not sell to market.
			"port_badge": null,
			"is_port": false,
			"icon": BuildingIcon.clean_texture(bid, str(bdata.get("internal_name", ""))),
			# 2.5D isometric sprite (null while unsprited) — drawn large above the plate
			# when `swap empire view sprite` is on; see building_sprites.gd.
			"sprite": sprite_tex,
			# Screen-px offset from the panel CENTRE down to the PLATE centre. In sprite view
			# the Control grows upward by the 400px sprite, so the plate centre sits half the
			# sprite height below the Control centre; edges anchor to the plate via this
			# (empire_graph_world._plate_screen_of). Zero in classic mode / unsprited.
			"plate_dy": ((NodePanel.SPRITE_PX * 0.5)
					if (MatchState.use_empire_sprite_view and sprite_tex != null) else 0.0),
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
			"plate_half": PORT_HALF,
			"is_port": true,
			"icon": port_icon,
		})
		pidx += 1
	# Fixed left-to-right port order: Stoneshore, Arin, Vandel, Capital.
	ports.sort_custom(func(a, b):
		if int(a["order"]) != int(b["order"]):
			return int(a["order"]) < int(b["order"])
		return str(a["name"]) < str(b["name"]))

	# The BUY row: the same four ports mirrored on the TOP edge — market inputs arrive
	# through them, market sales leave through the bottom row. One mirror per port, same
	# name and fixed order; only the iid differs so the two rows stay distinct nodes.
	var buy_ports: Array = []
	for p in ports:
		var bp: Dictionary = (p as Dictionary).duplicate()
		bp["iid"] = "buy_" + str((p as Dictionary)["iid"])
		bp["mirror_of"] = str((p as Dictionary)["iid"])
		buy_ports.append(bp)

	_append_construction_nodes(nodes, ports, terrain, idx)
	var sell_edges: Array = _build_sell_edges(nodes, ports, consumers)
	_stamp_port_badges(nodes, ports, sell_edges)
	return {
		"nodes": nodes,
		"ports": ports,
		"buy_ports": buy_ports,
		"edges": _build_edges(producers, consumers),
		"sell_edges": sell_edges,
		"market_edges": _build_market_edges(nodes, ports, consumers, producers),
		"signature": _signature(nodes),
	}


## Buildings still being BUILT. They join the graph as nodes with no edges at all — nothing
## flows in or out of a site that is not finished — wearing the construction sprite rather than
## the building's own. Because they have no sell edge, the sector vote cannot place them, so
## each carries a `port_hint`: the port its MATERIALS come through (Catalog.nearest_port_tile,
## the very port queue_buy sources from), falling back to the nearest port by world distance if
## that tile is not one of the four. One fact, two consumers — the layout places the site in
## that port's sector, and the focus chart draws the delivery run from the same hex.
static func _append_construction_nodes(nodes: Array, ports: Array, terrain: Object,
		idx: int) -> void:
	var projects: Dictionary = Construction.construction_projects
	if projects.is_empty():
		return
	var site_tex: Texture2D = BuildingSprites.texture_for("construction_site", 1)
	var port_pos: Array = []
	var port_by_tile: Dictionary = {}
	for p in ports:
		port_pos.append([str((p as Dictionary)["iid"]),
				_tile_world_pos(terrain, str((p as Dictionary).get("tile_id", "")), 0)])
		port_by_tile[str((p as Dictionary).get("tile_id", ""))] = str((p as Dictionary)["iid"])
	for proj in projects.values():
		var pd: Dictionary = proj
		var tile := str(pd.get("tile_id", ""))
		var iid := str(pd.get("instance_id", ""))
		if iid == "":
			continue
		idx += 1
		var seed_pos: Vector2 = _tile_world_pos(terrain, tile, idx)
		var hint := str(port_by_tile.get(str(Catalog.nearest_port_tile(tile)), ""))
		if hint == "":
			var bestd := INF
			for pp in port_pos:
				var d: float = (seed_pos - (pp[1] as Vector2)).length()
				if d < bestd:
					bestd = d
					hint = str(pp[0])
		var bid := str(pd.get("building_id", ""))
		var turns := int(pd.get("turns_remaining", 0))
		var awaiting := str(pd.get("status", "")) == Construction.STATUS_AWAITING_MATERIALS
		nodes.append({
			"iid": iid,
			"building_id": bid,
			"name": str(pd.get("name", "Under construction")),
			# The plate has no output, no RAG and no good icon to show, so the state gets its
			# own line — otherwise a site's caption is just a name on an empty plate. A project
			# waiting on materials is NOT counting down (turns_remaining is its full duration
			# and does not move), so printing a countdown for one would be a lie.
			"status_line": ("awaiting materials" if awaiting
					else ("ready next turn" if turns <= 1 else "%d turns to completion" % turns)),
			"level": 1,
			"output_good": "",
			"output_name": "under construction",
			"output_qty": turns,
			"tile_id": tile,
			"seed": seed_pos,
			"half": _node_half(1, site_tex),
			"plate_half": (BASE_HALF if (MatchState.use_empire_sprite_view and site_tex != null)
					else BASE_HALF),
			"sprite_rect": _sprite_content_offset(site_tex),
			"port_badge": null,
			"is_port": false,
			"under_construction": true,
			"turns_remaining": turns,
			"port_hint": hint,
			# The glyph of the building being BUILT — with the site sprite standing in for every
			# industry, this is the only thing on the card that says which one it will be. Needs
			# the real internal name: InfraIcons.texture_for returns null without it.
			"icon": BuildingIcon.clean_texture(bid,
					str(Catalog.get_building(bid).get("internal_name", ""))),
			"sprite": site_tex,
			"plate_dy": ((NodePanel.SPRITE_PX * 0.5)
					if (MatchState.use_empire_sprite_view and site_tex != null) else 0.0),
			"good_icon": null,
			"rag": [],
		})


## Give every building that ships to market the icon of the port it ships to. The empire view
## wears this as a small gold hex on the plate INSTEAD of drawing a line across the whole graph:
## measured, the port lines were 22 of 30 edges and 37 of 43 crossings, while carrying a
## building-to-MARKET fact rather than the building-to-building relationships the view is for.
static func _stamp_port_badges(nodes: Array, ports: Array, sell_edges: Array) -> void:
	var icon_of: Dictionary = {}
	for p in ports:
		icon_of[str((p as Dictionary)["iid"])] = (p as Dictionary).get("icon")
	var badge: Dictionary = {}
	for e in sell_edges:
		var f := str((e as Dictionary).get("from", ""))
		if f != "" and not badge.has(f):
			badge[f] = icon_of.get(str((e as Dictionary).get("to", "")))
	for n in nodes:
		var iid := str((n as Dictionary)["iid"])
		if badge.has(iid):
			(n as Dictionary)["port_badge"] = badge[iid]


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


## Market-input edges: one dashed line per building that consumes a good NO player building
## produces — by the graph's own capability model that input can only be bought from the
## market. One edge per building (its alphabetically first market-fed good), sourced from
## the BUY mirror of the building's nearest port — the same nearest-port heuristic (and the
## same honesty caveat) as the sell edges.
static func _build_market_edges(nodes: Array, ports: Array, consumers: Dictionary, producers: Dictionary) -> Array:
	var fed: Dictionary = {}                          # iid -> first market-fed good
	var goods: Array = consumers.keys()
	goods.sort()                                      # deterministic pick of the "first" good
	for g in goods:
		if producers.has(g) and not (producers[g] as Array).is_empty():
			continue
		for iid in consumers[g]:
			if not fed.has(iid):
				fed[iid] = g
	var tile_of: Dictionary = {}
	for n in nodes:
		tile_of[str(n["iid"])] = str(n["tile_id"])
	var port_by_tile: Dictionary = {}
	for p in ports:
		port_by_tile[str(p["tile_id"])] = str(p["iid"])
	var fallback := "buy_" + str((ports[0] as Dictionary)["iid"]) if not ports.is_empty() else ""
	var out: Array = []
	var iids: Array = fed.keys()
	iids.sort()
	for iid in iids:
		var src := fallback
		if Catalog.has_method("nearest_port_tile") and tile_of.has(iid):
			var ptile := str(Catalog.nearest_port_tile(tile_of[iid]))
			if port_by_tile.has(ptile):
				src = "buy_" + str(port_by_tile[ptile])
		if src != "":
			out.append({"from": src, "to": iid, "good": fed[iid]})
	return out


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
