extends Node
## Dev tool: open the Empire view, focus a building, and shoot the MINI-CHART — the state the
## resting empire_shot.gd never reaches, and where the 2026-08-14 chart pass lives:
##   1. shipment icons at _EDGE_GOOD_PX, stepped back off junctions (_clear_icon_point)
##   2. ports drawn at _PORT_SPRITE_MULT x the building sprite box
##   3. the gold port badge fading out in focus (it is a resting-empire mark)
##   4. the good a building BUYS carried on the dashed buy-port -> building run
## Needs a window (NOT --headless):
##   <godot> --path . res://tools/empire_focus_shot.tscn --quit-after 1400

func _ready() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(30)

	# Windowed scripted runs park the mouse in the window corner, which makes edge-pan fire
	# every frame and fight the view (cnc-godot-discipline).
	var cam: Node = game.get_node_or_null("Camera2D")
	if cam != null:
		cam.set("edge_pan_enabled", false)

	_seed_empire()
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

	# RESTING first: this is the ONLY state that should still show the gold port badge.
	print("BADGE-FLAG: show_port_badge=", MatchState.show_port_badge,
		"  sprite_view=", MatchState.use_empire_sprite_view)
	# A zero-size badge can never raise a tooltip, so assert it has a real rect and the text.
	for pan in (gw.get("_panels") as Array):
		var bctrl = (pan["ctrl"] as Node).get("_badge")
		if bctrl != null:
			print("BADGE-HOVER: size=", (bctrl as Control).size,
				"  filter=", (bctrl as Control).mouse_filter,
				"  tooltip=\"", (bctrl as Control).tooltip_text, "\"")
			break
	_shot("/tmp/poe_focus_rest.png")

	# Pick a target that exercises all four: it must BUY from a port (a dashed market edge, for
	# the new icon) and preferably take produced inputs too (more lines => more junctions).
	var market: Array = gw.get("_market_edges")
	var edges: Array = gw.get("_edges")
	var buys: Dictionary = {}
	for e in market:
		buys[str(e["to"])] = int(buys.get(str(e["to"]), 0)) + 1
	var ins: Dictionary = {}
	for e in edges:
		ins[str(e["to"])] = int(ins.get(str(e["to"]), 0)) + 1
	# A SELL edge matters most: it is the only way to see the good-on-the-gold-line icon.
	var sells: Dictionary = {}
	for e in (gw.get("_sell_edges") as Array):
		sells[str(e["from"])] = int(sells.get(str(e["from"]), 0)) + 1
	var best := ""
	var best_score := -1
	for iid in buys.keys():
		var score: int = int(sells.get(iid, 0)) * 100 + int(buys[iid]) * 10 + int(ins.get(iid, 0))
		if score > best_score:
			best_score = score
			best = str(iid)
	if best == "":
		# No market edge anywhere in this seed — still worth shooting the busiest chart.
		for iid in ins.keys():
			if int(ins[iid]) > best_score:
				best_score = int(ins[iid])
				best = str(iid)
	print("FOCUS: iid=", best, "  market_inputs=", int(buys.get(best, 0)),
		"  produced_inputs=", int(ins.get(best, 0)))
	if best == "":
		push_error("no focusable building in the seed")
		get_tree().quit(1)
		return

	gw.call("focus_on", best)
	# _FOCUS_SECS is 1.5s of REAL time and this run draws well above 60fps, so frame count is a
	# poor proxy — 130 frames only got _focus_t to 0.63. Wait on the tween itself.
	var guard := 0
	while float(gw.get("_focus_t")) < 0.999 and guard < 1200:
		guard += 1
		await get_tree().process_frame
	await _settle(4)
	print("FOCUSED: focus_iid=", gw.call("focus_iid"),
		"  focus_t=", gw.get("_focus_t"),
		"  icon_rects=", (gw.get("_edge_icon_rects") as Array).size())
	_shot("/tmp/poe_focus_chart.png")

	# Zoomed in on the chart: the icons and the port sprite at readable size.
	gw.call("_zoom_at", Vector2(1180.0, 664.0), 1.5)
	gw.call("queue_redraw")
	await _settle(8)
	print("ZOOM : view_zoom=", gw.get("_view_zoom"))
	_shot("/tmp/poe_focus_zoom.png")

	# Hover each shipment icon in turn and print the cost row the tooltip would show, so the
	# transport-cost readout is checked per EDGE KIND rather than eyeballed on one of them.
	var rects: Array = gw.get("_edge_icon_rects")
	print("---- tooltip cost row, per edge kind ----")
	for i in range(rects.size()):
		var entry: Dictionary = rects[i]
		var ed: Dictionary = entry.get("edge", {})
		var kind := str(entry.get("kind", "input"))
		var tc: Dictionary = gw.call("_edge_transport_cost", ed, kind)
		print("  %-6s %s -> %s | %s | known=%s cost=£%.4f" % [
			kind, str(ed.get("from", "")), str(ed.get("to", "")), str(ed.get("good", "")),
			str(tc.get("known", false)), float(tc.get("cost", 0.0))])
	# Park the cursor on the first icon so the panel itself renders in the shot.
	if rects.size() > 0:
		gw.set("_hover_edge", rects[0])
		gw.call("queue_redraw")
		await _settle(4)
		_shot("/tmp/poe_focus_tooltip.png")

	get_tree().quit(0)


## Same seeding as empire_shot.gd: real tiles, valid recipes, mixed levels, so edges actually form.
func _seed_empire() -> void:
	var tiles: Array = []
	for b in MatchState.buildings.values():
		var t := str(b.get("tile_id", ""))
		if t != "" and not tiles.has(t):
			tiles.append(t)
	tiles.sort()
	for fb in ["tile_9_10", "tile_7_9", "tile_10_11", "tile_8_9"]:
		if not tiles.has(fb):
			tiles.append(fb)

	var bids := ["b_001", "b_002", "b_003", "b_007", "b_008", "b_009", "b_010", "b_011",
		"b_012", "b_013", "b_014", "b_020", "b_021", "b_036"]
	var levels := [1, 1, 2, 1, 3, 1, 2, 1, 1, 2, 1, 1, 3, 1]
	var placed := 0
	for k in range(bids.size()):
		var bid: String = bids[k]
		var recs: Array = Catalog.get_recipes_for_building(bid)
		if recs.is_empty():
			continue
		var rid := str((recs[0] as Dictionary).get("recipe_id", ""))
		var tid: String = tiles[(k * 3) % tiles.size()]
		var iid := "emp_%d" % k
		MatchState.add_building(bid, rid, tid, "player_1", iid)
		if MatchState.buildings.has(iid):
			MatchState.buildings[iid]["level"] = levels[k]
		placed += 1
	print("seeded ", placed, " player buildings across ", tiles.size(), " candidate tiles")


func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame


func _shot(path: String) -> void:
	# force_draw() renders AND swaps synchronously. Without it the capture is whatever frame the
	# compositor last presented — and an occluded/background window stops presenting entirely, so
	# every shot in the run comes back byte-identical (it did: rest, chart and zoom all hashed the
	# same). Same guard map_style_shot.gd and the hill bake use.
	RenderingServer.force_draw()
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("SAVED ", path, " ", img.get_width(), "x", img.get_height())
