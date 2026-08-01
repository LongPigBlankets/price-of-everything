extends Node
## Dev tool: MEASURE the empire view's sprite layout instead of eyeballing it. Seeds every
## sprited building (plus one unsprited, to keep the glyph fallback covered), opens the Empire
## view, and at several ZOOM levels reports:
##   * panel <-> panel overlaps            (cards/sprites sitting on each other)
##   * panel <-> port-hex overlaps         (sprites eating the port row)
##   * edge endpoints landing in MIDAIR    (not on a plate or a port hex)
##   * edge segments crossing a panel rect (lines disappearing under a sprite)
## Screenshots go alongside so the numbers can be checked against a picture.
## Needs a window (NOT --headless):
##   <godot> --path . res://tools/empire_overlap_probe.tscn --quit-after 1200

const _ZOOMS := [0.30, 0.55, 1.00]

func _ready() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(30)
	_seed()
	await _settle(4)

	var ev: Node = game.get_node_or_null("UILayer/HUD/HUDContent/EmpireView")
	if ev == null:
		push_error("EmpireView not found")
		get_tree().quit(1)
		return
	ev.call("toggle")
	await _settle(16)
	var gw: Node = ev.get_node_or_null("GraphWorld")
	if gw == null:
		push_error("GraphWorld not found")
		get_tree().quit(1)
		return

	print("DEFAULT use_empire_sprite_view=", MatchState.use_empire_sprite_view)

	# CONSTRUCTION: start two projects and confirm they join the graph as edge-less nodes
	# wearing the construction sprite, each placed in the sector of its nearest port.
	_seed_construction()
	ev.call("refresh_graph")
	await _settle(16)
	gw = ev.get_node_or_null("GraphWorld")
	var sites := 0
	var with_sprite := 0
	var with_edges := 0
	var hints: Array = []
	for n in (gw.get("_nodes") as Array):
		if not bool(n.get("under_construction", false)):
			continue
		sites += 1
		if n.get("sprite") != null:
			with_sprite += 1
		hints.append(str(n.get("port_hint", "")))
		for e in (gw.get("_edges") as Array) + (gw.get("_sell_edges") as Array) + (gw.get("_market_edges") as Array):
			if str(e["from"]) == str(n["iid"]) or str(e["to"]) == str(n["iid"]):
				with_edges += 1
	print("CONSTRUCTION: %d site nodes, %d with the site sprite, %d touched by an edge, port hints=%s"
		% [sites, with_sprite, with_edges, hints])
	# Frame ON a site so the screenshot proves it, not just the counters.
	for n in (gw.get("_nodes") as Array):
		if not bool(n.get("under_construction", false)):
			continue
		gw.set("_view_zoom", 0.65)
		gw.set("_view_offset", gw.size * 0.5 - (n["pos"] as Vector2) * 0.65)
		gw.queue_redraw()
		await _settle(12)
		_shot("/tmp/poe_construction_site.png")
		break
	# CARD CLOSE-UP: one sprited building framed big enough to judge the plate itself — the
	# glyph is back beside the good icon in sprite view (owner 2026-08-01), and whether it earns
	# its space is a judgement about THIS card, not about the whole composition.
	for n in (gw.get("_nodes") as Array):
		if n.get("sprite") == null or bool(n.get("under_construction", false)):
			continue
		if n.get("icon") == null or str(n.get("output_good", "")) == "":
			continue                       # want a card carrying BOTH icons
		if str(n.get("building_id", "")) != "b_013":
			continue                       # poly plant: sprited AND one of the swapped glyphs
		gw.set("_view_zoom", 0.95)
		gw.set("_view_offset", gw.size * 0.5 - (n["pos"] as Vector2) * 0.95)
		gw.queue_redraw()
		await _settle(12)
		# NOTE: do NOT call _hide_overlays here. Hiding a HUD panel that PanelStack is tracking
		# pops the empire view off the stack, and the shot comes out as the world map.
		print("CARD CLOSE-UP on %s (%s): glyph=%s good_icon=%s"
			% [str(n["iid"]), str(n["name"]), n.get("icon") != null, n.get("good_icon") != null])
		_shot("/tmp/poe_empire_card.png")
		break

	for z in _ZOOMS:
		# Set zoom AND re-frame: _zoom_at keeps the cursor point fixed, so stepping the zoom
		# without recentring walks the graph off screen and the screenshot shows an edge.
		gw.set("_view_zoom", z)
		var bb: Rect2 = gw.call("_layout_bbox")
		gw.set("_view_offset", gw.size * 0.5 - bb.get_center() * z)
		gw.queue_redraw()
		await _settle(14)
		_report(gw, z)
		_shot("/tmp/poe_empire_z%03d.png" % int(round(z * 100.0)))

	_report_crossings(gw)
	_report_routed(gw)
	_report_sprite_hits(gw)

	await _report_site_focus(gw, ev)

	# The two blocked-while-broke projects have been read; put the money back before any turn
	# is committed, so the turn test isn't measuring a bankruptcy.
	MatchState.money = 500000.0

	# EVERY TURN THIS UPDATES: commit turns with the view OPEN and a chart FOCUSED, then check
	# the chart survived the rebuild and the goods actually moved down their lanes.
	var site_iid := ""
	for n in (gw.get("_nodes") as Array):
		if bool(n.get("under_construction", false)) and not bool(
				((gw.call("_site_lanes", str(n["iid"])) as Array)[0] as Dictionary)["delivered"]):
			site_iid = str(n["iid"])
			break
	if site_iid != "":
		gw.call("focus_on", site_iid)
		await _settle(26)
		var before: Array = gw.call("_site_lanes", site_iid)
		for _t in range(2):
			TurnManager.commit_turn()
			await _settle(10)
		gw = ev.get_node_or_null("GraphWorld")
		var after: Array = gw.call("_site_lanes", site_iid)
		print("TURN UPDATE: focus held=%s (%s) | eta %d -> %d | at %.2f -> %.2f | caption=%s"
			% [str(gw.call("focus_iid")) == site_iid, str(gw.call("focus_iid")),
				int((before[0] as Dictionary)["eta"]), int((after[0] as Dictionary)["eta"]),
				float((before[0] as Dictionary)["at"]), float((after[0] as Dictionary)["at"]),
				str((gw.get("_box_by_iid") as Dictionary).get(site_iid, {}).get("status_line", "?"))])
		_hide_overlays(ev)
		await _settle(6)
		_shot("/tmp/poe_site_after_turns.png")
		gw.call("clear_focus")
		await _settle(20)

	# FOCUS mini-chart: pick the building with the most connections so the chart has both
	# sides, select it, and check only depth-1 nodes survive.
	var best_iid := ""
	var best_n := -1
	var deg: Dictionary = {}
	for e in (gw.get("_edges") as Array) + (gw.get("_sell_edges") as Array):
		deg[str(e["from"])] = int(deg.get(str(e["from"]), 0)) + 1
		deg[str(e["to"])] = int(deg.get(str(e["to"]), 0)) + 1
	for pan in (gw.get("_panels") as Array):
		var iid4: String = str(pan["iid"])
		if int(deg.get(iid4, 0)) > best_n:
			best_n = int(deg.get(iid4, 0))
			best_iid = iid4
	gw.call("focus_on", best_iid)
	await _settle(30)
	var members: Dictionary = gw.get("_focus_members")
	var vis := 0
	for pan in (gw.get("_panels") as Array):
		if (pan["ctrl"] as Control).visible:
			vis += 1
	print("FOCUS on %s (degree %d): members=%d visible_panels=%d focus_t=%.2f"
		% [best_iid, best_n, members.size(), vis, float(gw.get("_focus_t"))])
	_shot("/tmp/poe_empire_focus.png")
	gw.call("clear_focus")
	await _settle(30)
	print("UNFOCUS: focus_t=%.2f visible=%d" % [float(gw.get("_focus_t")),
		(gw.get("_panels") as Array).filter(func(x): return (x["ctrl"] as Control).visible).size()])
	get_tree().quit(0)


## Rects are taken from the LIVE per-frame state (`_screen_by_iid` + the panel Controls), so
## what is measured is exactly what is drawn — not the layout's intent.
func _report(gw: Node, z: float) -> void:
	var by_iid: Dictionary = gw.get("_screen_by_iid")
	var panels: Array = gw.get("_panels")
	var ports: Array = gw.get("_ports")
	var sc: float = clampf(float(gw.get("_view_zoom")), 0.05, 1.0)

	var prects: Array = []
	for pan in panels:
		var iid: String = str(pan["iid"])
		if not by_iid.has(iid):
			continue
		var ctrl := pan["ctrl"] as Control
		var h: Vector2 = ctrl.size * (0.5 * sc)
		prects.append({"iid": iid, "r": Rect2((by_iid[iid] as Vector2) - h, h * 2.0)})
	var hrects: Array = []
	for p in ports:
		var iid2: String = str(p["iid"])
		if not by_iid.has(iid2):
			continue
		var h2: Vector2 = (p["half"] as Vector2) * sc
		hrects.append({"iid": iid2, "r": Rect2((by_iid[iid2] as Vector2) - h2, h2 * 2.0)})

	var pp := 0
	var worst_pp := 0.0
	for i in range(prects.size()):
		for j in range(i + 1, prects.size()):
			var a: Rect2 = prects[i]["r"]
			var b: Rect2 = prects[j]["r"]
			if a.intersects(b):
				pp += 1
				var o: Rect2 = a.intersection(b)
				worst_pp = maxf(worst_pp, minf(o.size.x, o.size.y))
	var ph := 0
	var worst_ph := 0.0
	var min_gap := 1.0e9
	for pr in prects:
		for hr in hrects:
			var a2: Rect2 = pr["r"]
			var b2: Rect2 = hr["r"]
			if a2.intersects(b2):
				ph += 1
				var o2: Rect2 = a2.intersection(b2)
				worst_ph = maxf(worst_ph, minf(o2.size.x, o2.size.y))
			else:
				var dx: float = maxf(0.0, maxf(b2.position.x - a2.end.x, a2.position.x - b2.end.x))
				var dy: float = maxf(0.0, maxf(b2.position.y - a2.end.y, a2.position.y - b2.end.y))
				min_gap = minf(min_gap, maxf(dx, dy))

	# Endpoint check: every edge must START on its source plate's boundary and END on its
	# target's. Anchors come from the same `plate_half` the routing uses, so a mismatch here
	# means the two have drifted apart — which is exactly how arrows end up in open space.
	var edges: Array = gw.get("_edges")
	var sells: Array = gw.get("_sell_edges")
	var nodes: Array = gw.get("_nodes")
	var node_by: Dictionary = {}
	for n in nodes:
		node_by[str(n["iid"])] = n
	var midair := 0
	var worst_off := 0.0
	for e in (edges + sells):
		for key in ["from", "to"]:
			var iid3: String = str(e[key])
			if not (node_by.has(iid3) and by_iid.has(iid3)):
				continue
			var nd: Dictionary = node_by[iid3]
			var eh: Vector2 = (nd.get("plate_half", nd["half"]) as Vector2) * sc
			var c: Vector2 = (by_iid[iid3] as Vector2) + Vector2(0.0, float(nd.get("plate_dy", 0.0)) * sc)
			var plate := Rect2(c - eh, eh * 2.0)
			# the drawn plate rect, from the live Control, for comparison
			for pan2 in panels:
				if str(pan2["iid"]) != iid3:
					continue
				var ctl := pan2["ctrl"] as Control
				var pr2: Rect2 = ctl.get("_plate_rect")
				var drawn := Rect2(ctl.position + pr2.position * sc, pr2.size * sc)
				var d2: float = maxf((drawn.get_center() - plate.get_center()).length(),
						(drawn.size - plate.size).length())
				if d2 > 4.0:
					midair += 1
					worst_off = maxf(worst_off, d2)
					if midair <= 2:
						print("      MISMATCH %s: anchor=%s drawn=%s ctrl.size=%s plate_dy=%s"
							% [iid3, plate, drawn, ctl.size, nd.get("plate_dy", 0.0)])
	print("            edge anchors vs drawn plates: %d mismatched (worst %.0fpx)" % [midair, worst_off])

	# PORT BADGE: it now hangs off the sprite's bottom-right corner, so for a sprite that fills
	# its frame the hex sticks out past the panel. Check that overhang never lands on a
	# NEIGHBOUR's artwork — that is the only thing the move could actually break.
	var badge_hits := 0
	var worst_badge := 0.0
	for pan in panels:
		var iid5: String = str(pan["iid"])
		if not by_iid.has(iid5):
			continue
		var ctl2 := pan["ctrl"] as Control
		var bhex: Rect2 = ctl2.get("_badge_rect") if ctl2.get("_badge_rect") != null else Rect2()
		if bhex.size.x <= 0.0:
			continue
		var bworld := Rect2((by_iid[iid5] as Vector2) - ctl2.size * (0.5 * sc) + bhex.position * sc,
				bhex.size * sc)
		for n2 in nodes:
			var oid: String = str(n2["iid"])
			if oid == iid5 or not by_iid.has(oid):
				continue
			var sr2: Rect2 = n2.get("sprite_rect", Rect2())
			if sr2.size.x <= 0.0:
				continue
			var oart := Rect2((by_iid[oid] as Vector2) + sr2.position * sc, sr2.size * sc)
			if bworld.intersects(oart):
				badge_hits += 1
				var ov: Rect2 = bworld.intersection(oart)
				worst_badge = maxf(worst_badge, minf(ov.size.x, ov.size.y))
	print("            port badges landing on a NEIGHBOUR's art: %d (worst %.0fpx)"
		% [badge_hits, worst_badge])

	print("ZOOM %.2f | panels=%d ports=%d | panel-panel overlaps=%d (worst %.0fpx) | panel-port overlaps=%d (worst %.0fpx) | closest panel-port gap=%.0fpx (%.2f x sprite)"
		% [z, prects.size(), hrects.size(), pp, worst_pp, ph, worst_ph,
			(0.0 if min_gap > 1.0e8 else min_gap), (0.0 if min_gap > 1.0e8 else min_gap / maxf(1.0, 400.0 * sc))])


## Straight-line crossing count over the LAYOUT graph (node centre to node centre). This is the
## standard metric the ordering pass is trying to minimise, and it is independent of how the
## router later bends each edge — so it measures the LAYOUT, not the drawing.
func _report_crossings(gw: Node) -> void:
	var pos: Dictionary = {}
	for arr in [gw.get("_nodes"), gw.get("_ports"), gw.get("_buy_ports")]:
		for n in (arr as Array):
			pos[str(n["iid"])] = n["pos"]
	var segs: Array = []
	var spans: Dictionary = {}
	var cols: Dictionary = {}
	for n in (gw.get("_nodes") as Array):
		cols[str(n["iid"])] = int(round(((n["pos"] as Vector2).x) / 620.0))
	var kinds: Array = []
	# Only edges actually DRAWN at rest. With the port badge on, sell lines are focus-only, so
	# counting them would measure a picture nobody sees.
	var grps: Array = [{"a": gw.get("_edges"), "k": "input"}, {"a": gw.get("_market_edges"), "k": "buy"}]
	if not MatchState.show_port_badge:
		grps.append({"a": gw.get("_sell_edges"), "k": "sell"})
	for grp in grps:
		for e in (grp["a"] as Array):
			var f := str(e["from"])
			var t := str(e["to"])
			if not (pos.has(f) and pos.has(t)):
				continue
			segs.append([pos[f], pos[t]])
			kinds.append(str(grp["k"]))
			if str(grp["k"]) == "input" and cols.has(f) and cols.has(t):
				var sp: int = absi(int(cols[t]) - int(cols[f]))
				spans[sp] = int(spans.get(sp, 0)) + 1
	for e in []:
		var f := str(e["from"])
		var t := str(e["to"])
		if pos.has(f) and pos.has(t):
			segs.append([pos[f], pos[t]])
			if cols.has(f) and cols.has(t):
				var sp: int = absi(int(cols[t]) - int(cols[f]))
				spans[sp] = int(spans.get(sp, 0)) + 1
	var x := 0
	var tally: Dictionary = {}
	for i in range(segs.size()):
		for j in range(i + 1, segs.size()):
			if not _seg_cross(segs[i][0], segs[i][1], segs[j][0], segs[j][1]):
				continue
			x += 1
			var pair: Array = [str(kinds[i]), str(kinds[j])]
			pair.sort()
			var key := "%s+%s" % [pair[0], pair[1]]
			tally[key] = int(tally.get(key, 0)) + 1
	print("CROSSINGS BY PAIR: ", tally)
	var multi := 0
	var total := 0
	for k in spans:
		total += int(spans[k])
		if int(k) > 1:
			multi += int(spans[k])
	print("CROSSINGS: %d over %d edges | edges spanning >1 column: %d of %d (%.0f%%) | spans=%s"
		% [x, segs.size(), multi, total, (100.0 * float(multi) / maxf(1.0, float(total))), spans])


## Crossings between the ROUTED polylines actually drawn — which is what the channel lane
## ordering changes. The centre-to-centre metric cannot see it: that measures the layout, this
## measures the picture.
func _report_routed(gw: Node) -> void:
	var boxes: Dictionary = gw.get("_box_by_iid")
	var sc: float = clampf(float(gw.get("_view_zoom")), 0.05, 1.0)
	var paths: Array = []
	for e in (gw.get("_edges") as Array):
		if not (boxes.has(str(e["from"])) and boxes.has(str(e["to"]))):
			continue
		paths.append(gw.call("_route_input", boxes[str(e["from"])], boxes[str(e["to"])],
			int(e.get("lane", 0)), int(e.get("lane_n", 1)), sc))
	for e in (gw.get("_market_edges") as Array):
		if not (boxes.has(str(e["from"])) and boxes.has(str(e["to"]))):
			continue
		paths.append(gw.call("_route_market", boxes[str(e["from"])], boxes[str(e["to"])],
			int(e.get("slot", 0)), int(e.get("slot_n", 1)), sc))
	var x := 0
	for i in range(paths.size()):
		for j in range(i + 1, paths.size()):
			var pa: PackedVector2Array = paths[i]
			var pb: PackedVector2Array = paths[j]
			for u in range(pa.size() - 1):
				for v in range(pb.size() - 1):
					if _seg_cross(pa[u], pa[u + 1], pb[v], pb[v + 1]):
						x += 1
	print("ROUTED CROSSINGS: %d over %d drawn polylines" % [x, paths.size()])


## Do any DRAWN lines cross an OPAQUE building sprite? Crossing the transparent padding is
## allowed (that is why the sprite sits behind the lines); crossing the building itself is the
## defect — the line vanishes under it. Construction sites are the sharp case: they anchor no
## edges at all, so nothing ever legitimately enters or leaves one.
func _report_sprite_hits(gw: Node) -> void:
	var boxes: Dictionary = gw.get("_box_by_iid")
	var screen: Dictionary = gw.get("_screen_by_iid")
	var sc: float = clampf(float(gw.get("_view_zoom")), 0.05, 1.0)
	var rects: Array = []
	for n in (gw.get("_nodes") as Array):
		var iid: String = str(n["iid"])
		var r: Rect2 = n.get("sprite_rect", Rect2())
		if r.size.x <= 0.0 or r.size.y <= 0.0 or not screen.has(iid):
			continue
		rects.append({"iid": iid, "site": bool(n.get("under_construction", false)),
			"r": Rect2((screen[iid] as Vector2) + r.position * sc, r.size * sc)})
	var paths: Array = []
	for e in (gw.get("_edges") as Array):
		if boxes.has(str(e["from"])) and boxes.has(str(e["to"])):
			paths.append({"a": str(e["from"]), "b": str(e["to"]),
				"p": gw.call("_route_input", boxes[str(e["from"])], boxes[str(e["to"])],
					int(e.get("lane", 0)), int(e.get("lane_n", 1)), sc)})
	for e in (gw.get("_market_edges") as Array):
		if boxes.has(str(e["from"])) and boxes.has(str(e["to"])):
			paths.append({"a": str(e["from"]), "b": str(e["to"]),
				"p": gw.call("_route_market", boxes[str(e["from"])], boxes[str(e["to"])],
					int(e.get("slot", 0)), int(e.get("slot_n", 1)), sc)})
	var hits := 0
	var site_hits := 0
	var worst := ""
	for path in paths:
		for rc in rects:
			if str(rc["iid"]) == str(path["a"]) or str(rc["iid"]) == str(path["b"]):
				continue
			if not bool(gw.call("_blocked", path["p"], [rc["r"]])):
				continue
			hits += 1
			if bool(rc["site"]):
				site_hits += 1
				if worst == "":
					worst = "%s->%s crosses site %s" % [path["a"], path["b"], rc["iid"]]
	print("SPRITE HITS: %d drawn lines cross an opaque sprite (%d of them a CONSTRUCTION SITE) over %d lines x %d sprites%s"
		% [hits, site_hits, paths.size(), rects.size(), ("  |  e.g. " + worst) if worst != "" else ""])


func _seg_cross(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	if a.is_equal_approx(c) or a.is_equal_approx(d) or b.is_equal_approx(c) or b.is_equal_approx(d):
		return false      # shared endpoint is not a crossing
	var r := b - a
	var s := d - c
	var den := r.cross(s)
	if absf(den) < 0.00001:
		return false
	var t := (c - a).cross(s) / den
	var u := (c - a).cross(r) / den
	return t > 0.001 and t < 0.999 and u > 0.001 and u < 0.999


## Five projects, one per state the delivery chart has to draw:
##   0  materials already on the tile  -> under_construction, every lane "on site"
##   1  bought from the market, with ONE material part-stocked on the tile first -> that lane
##      must split into two icons (what landed at the site, what is still owed)
##   2  a CHEM PLANT (b_012)           -> its industrial_acids is a hazard_liquid, so with no
##      reinforced pipework to the site that material can NEVER ship: blocked "infra" while
##      the solid materials on the same build travel normally
##   3  started while broke            -> queue_buy refuses the order: blocked "cash"
##   4  started while broke on a FULL tile -> nowhere to unload: blocked "capacity" (which
##      outranks cash — no point affording goods the site cannot take)
## 3 and 4 need the money to STAY low, or the cause evaporates before it is read; the main
## flow restores it before committing any turns.
func _seed_construction() -> void:
	var tiles: Array = []
	for b in MatchState.buildings.values():
		var t := str(b.get("tile_id", ""))
		if t != "" and not tiles.has(t):
			tiles.append(t)
	tiles.sort()
	MatchState.add_money(500000.0)                 # the market orders have to be affordable
	var plan := [{"bid": "b_007", "mode": "tile"}, {"bid": "b_002", "mode": "part"},
			{"bid": "b_012", "mode": "market"}, {"bid": "b_001", "mode": "broke"},
			{"bid": "b_003", "mode": "broke_full"}]
	for k in range(plan.size()):
		var bid := str(plan[k]["bid"])
		var recs: Array = Catalog.get_recipes_for_building(bid)
		if recs.is_empty():
			continue
		var tile: String = tiles[(k * 5) % tiles.size()]
		var rid := str((recs[0] as Dictionary).get("recipe_id", ""))
		var reqs: Dictionary = Construction.requirements_for(bid)
		var mode := str(plan[k]["mode"])
		match mode:
			"tile":
				# Stock the tile so start_on_tile's consume() is satisfied, then begin the build.
				for gid in reqs:
					Stockpile.add(tile, gid, int(reqs[gid]) + 10)
				Construction.start_on_tile(bid, rid, tile, 0.0)
			"part":
				# Put HALF of one material on the tile: start_awaiting_market reserves that
				# part and orders only the shortfall, which is the split-delivery case.
				var keys: Array = reqs.keys()
				keys.sort()
				if not keys.is_empty() and int(reqs[keys[0]]) > 1:
					Stockpile.add(tile, str(keys[0]), int(reqs[keys[0]]) / 2)
				Construction.start_awaiting_market(bid, rid, tile, 0.0)
			"broke", "broke_full":
				if mode == "broke_full":
					# Fill the tile with something that is NOT one of its build materials, so
					# the fill can't be mistaken for delivered kit.
					var filler := ""
					for g in Catalog.all_goods():
						if not reqs.has(str((g as Dictionary).get("id", ""))):
							filler = str((g as Dictionary).get("id", ""))
							break
					if filler != "":
						Stockpile.add(tile, filler, Stockpile.get_capacity(tile))
				MatchState.money = -250000.0
				Construction.start_awaiting_market(bid, rid, tile, 0.0)
			_:
				Construction.start_awaiting_market(bid, rid, tile, 0.0)
	print("started ", Construction.construction_projects.size(), " construction projects")


## The delivery chart, per site: what the lanes say, and whether any of it crosses the sprite
## it is delivering to. Focuses each site in turn (the chart is live sim state, so this is the
## picture the player gets), and shoots the two interesting ones.
func _report_site_focus(gw: Node, ev: Node) -> void:
	for n in (gw.get("_nodes") as Array):
		if not bool(n.get("under_construction", false)):
			continue
		var iid := str(n["iid"])
		gw.call("focus_on", iid)
		await _settle(26)
		_hide_overlays(ev)
		await _settle(4)
		var members: Dictionary = gw.get("_focus_members")
		var site: Dictionary = gw.get("_focus_site")
		var lanes: Array = gw.call("_site_lanes", iid)
		var desc: Array = []
		var blocked := 0
		var split := 0
		for l in lanes:
			var tag := ""
			if bool(l["blocked"]):
				tag = " BLOCKED[%s]%s" % [str(l["cause"]),
					(" icon" if l["infra_icon"] != null else "")]
				blocked += 1
			elif bool(l["delivered"]):
				tag = " on-site"
			elif not bool(l["ordered"]):
				tag = " unordered"
			if int(l["arrived"]) > 0 and int(l["outstanding"]) > 0:
				split += 1
				tag += " SPLIT"
			desc.append("%s %d/%d@%.2f eta=%d%s" % [str(l["good"]), int(l["arrived"]),
				int(l["required"]), float(l["at"]), int(l["eta"]), tag])
		print("SITE FOCUS %s: members=%d port=%s lanes=%d blocked=%d split=%d  %s"
			% [iid, members.size(), str(site.get("port", "")), lanes.size(), blocked, split, desc])
		# Geometry from the SAME plan the drawing consumes: every lane on its own row (that is
		# what "different materials on different lanes" means), no lane crossing the site
		# sprite, and — the new rule — no drawn line piece crossing ANY goods icon.
		var sc: float = clampf(float(gw.get("_view_zoom")), 0.05, 1.0)
		var scr: Dictionary = gw.get("_screen_by_iid")
		var plan: Array = gw.call("site_lane_plan", sc)
		var rows: Dictionary = {}
		if scr.has(iid) and not plan.is_empty():
			var sr: Rect2 = n.get("sprite_rect", Rect2())
			var art := Rect2((scr[iid] as Vector2) + sr.position * sc, sr.size * sc)
			var art_hits := 0
			var goods_in_art := 0
			var icon_hits := 0
			var icons := 0
			# The rule is about the WHOLE focused view, so gather every goods icon on the
			# chart first and test every line piece from every lane against all of them.
			var boxes: Array = []
			for row in plan:
				for m in (row["marks"] as Array):
					boxes.append(Rect2((m as Dictionary)["c"] - Vector2(37.0, 37.0) * sc,
						Vector2(74.0, 74.0) * sc))
					icons += 1
			for row2 in plan:
				rows[int(round(float(row2["y"])))] = true
				for piece in (row2["pieces"] as Array):
					if bool(gw.call("_blocked", piece, [art])):
						art_hits += 1
					if bool(gw.call("_blocked", piece, boxes)):
						icon_hits += 1
				for m2 in (row2["marks"] as Array):
					if art.grow(37.0 * sc).has_point((m2 as Dictionary)["c"] as Vector2):
						goods_in_art += 1
			print("      lane rows=%d of %d distinct | lines crossing the site sprite=%d | goods icons on the sprite=%d | line pieces crossing a goods icon=%d (over %d icons)"
				% [rows.size(), plan.size(), art_hits, goods_in_art, icon_hits, icons])
		if blocked > 0:
			_shot("/tmp/poe_site_blocked_%s.png" % str((lanes as Array).filter(
				func(l): return bool(l["blocked"]))[0]["cause"]))
		elif split > 0:
			_shot("/tmp/poe_site_split.png")
		elif lanes.size() > 0 and not bool((lanes[0] as Dictionary)["delivered"]):
			_shot("/tmp/poe_site_transit.png")
		else:
			_shot("/tmp/poe_site_delivered.png")
		gw.call("clear_focus")
		await _settle(26)


func _seed() -> void:
	var tiles: Array = []
	for b in MatchState.buildings.values():
		var t := str(b.get("tile_id", ""))
		if t != "" and not tiles.has(t):
			tiles.append(t)
	tiles.sort()
	# every sprited building at a spread of levels, plus b_008 (unsprited -> glyph fallback)
	# Dense on purpose: lane ordering only bites when a channel carries several legs, and a
	# thin graph cannot tell a good solver from a bad one.
	var bids := ["b_007", "b_002", "b_001", "b_003", "b_011", "b_013",
			"b_007", "b_002", "b_001", "b_003", "b_011", "b_013", "b_008",
			"b_007", "b_002", "b_001", "b_003", "b_011", "b_013",
			"b_007", "b_002", "b_001", "b_003", "b_011", "b_013"]
	var levels := [1, 2, 3, 2, 3, 2, 3, 1, 2, 3, 1, 3, 1,
			2, 1, 2, 3, 2, 1, 3, 3, 1, 1, 2, 2]
	for k in range(bids.size()):
		var recs: Array = Catalog.get_recipes_for_building(bids[k])
		if recs.is_empty():
			continue
		var rid := str((recs[0] as Dictionary).get("recipe_id", ""))
		var iid := "ovl_%d" % k
		MatchState.add_building(bids[k], rid, tiles[(k * 3) % tiles.size()], "player_1", iid)
		if MatchState.buildings.has(iid):
			MatchState.buildings[iid]["level"] = levels[k]
	print("seeded ", bids.size(), " buildings")


## Seeding a full tile pops the capacity dialog, and committing a turn pops the briefing —
## both land on top of the view. Hide whatever else is showing so a screenshot is of the CHART.
func _hide_overlays(ev: Node) -> void:
	for sib in ev.get_parent().get_children():
		if sib != ev and sib is CanvasItem and (sib as CanvasItem).visible:
			(sib as CanvasItem).visible = false
	# The capacity dialog is parented to the HUD itself, not to HUDContent alongside the view
	# (world_map._hud.add_child), so hiding the view's own siblings does not reach it. Walk one
	# level further up and hide everything on that level except the branch holding the view.
	var content := ev.get_parent()
	var hud := content.get_parent()
	if hud != null:
		for sib in hud.get_children():
			if sib != content and sib is CanvasItem and (sib as CanvasItem).visible:
				(sib as CanvasItem).visible = false


func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame


func _shot(path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("SAVED ", path, " ", img.get_width(), "x", img.get_height())
