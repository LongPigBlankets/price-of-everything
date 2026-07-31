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


func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame


func _shot(path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("SAVED ", path, " ", img.get_width(), "x", img.get_height())
