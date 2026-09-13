extends RefCounted
## Supplemental authentic UI states for the 10 September trailer. Run through
## trailer_growth.tscn -- --launch-20260910; owns no save or production settings.
const OUT := "/Users/crisu/Price of Everything/price-of-everything/outputs/trailer-2026-09-10/capture"
var host: Node
var layer: CanvasLayer
var evidence: Dictionary = {}

func run(owner_node: Node) -> void:
	host = owner_node
	DirAccess.make_dir_recursive_absolute(OUT)
	if "--approach" in OS.get_cmdline_user_args():
		await approach()
		return
	layer = CanvasLayer.new()
	host.add_child(layer)
	MatchState.money = 100000.0
	host.camera.position = host.tile_position("tile_5_10")
	host.camera.zoom = Vector2.ONE * 0.75
	if "--hydraulic-delivery" in OS.get_cmdline_user_args():
		await hydraulic_delivery()
		return
	if "--research-only" in OS.get_cmdline_user_args():
		await research()
		var research_file := FileAccess.open(OUT + "/research_evidence.json", FileAccess.WRITE)
		research_file.store_string(JSON.stringify(evidence, "\t"))
		research_file.close()
		print("RESEARCH_CAPTURE_DONE")
		return
	await build_and_site()
	await market()
	await research()
	var file := FileAccess.open(OUT + "/evidence.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(evidence, "\t"))
	file.close()
	print("LAUNCH_CAPTURE_DONE")

func hydraulic_delivery() -> void:
	# Isolated L3 factory, using the normal supply-chain panel and native bay FX.
	UiPrefs.use_empire_sprite_view = true
	var tile := "tile_5_10"
	var iid: String = BuildingState.add_building("b_007", "r_236", tile, "player_1", "trailer_hydraulics_l3", false)
	assert(iid != "")
	BuildingState.buildings[iid]["level"] = 3
	BuildingWorks.building_upgraded.emit(iid, 3)
	var recipe: Dictionary = Catalog.get_recipe("r_236")
	for input: Dictionary in recipe.inputs:
		Stockpile.add(tile, str(input.good_id), int(input.qty) * 12)
	var empire: Control = host.world.find_child("EmpireView", true, false)
	expose(empire, Rect2(0, 0, 1920, 1080))
	empire.refresh_graph()
	await wait_frames(20)
	var graph: Control = empire.find_child("GraphWorld", true, false)
	assert(graph.has_building(iid))
	graph.focus_on(iid, true)
	await wait_frames(20)
	var panel: Control
	for entry: Dictionary in graph.get("_panels"):
		if str(entry.iid) == iid:
			panel = entry.ctrl
	assert(panel != null and int(panel.get("_level")) == 3)
	var fx: Control
	for child: Node in panel.find_children("*", "Control", true, false):
		if child.get_script() == load("res://scripts/empire_fx.gd"):
			fx = child
	assert(fx != null)
	var bay: Dictionary = fx.get("_bay")
	assert(not bay.is_empty(), "L3 factory must have the native lorry loading bay")
	graph.restore_camera({"zoom":2.1,"offset":Vector2.ZERO})
	await wait_frames(3)
	var sprite_root: Control = panel.get("_sprite_root")
	var content: Rect2 = panel.get("_sprite_content")
	var center: Vector2 = sprite_root.get_global_transform() * content.get_center()
	var camera: Dictionary = graph.capture_camera()
	camera.offset += Vector2(1040, 390) - center
	graph.restore_camera(camera)
	await wait_frames(3)
	panel.call("_on_hover", true)
	# Use the actual recipe title on the native card, avoiding its clipped long
	# building/recipe concatenation in this close-up.
	for label: Label in panel.find_children("*", "Label", true, false):
		if label.text.contains("Industrial Goods Factory"):
			label.text = str(recipe.display_name)
	fx.set_process(false)
	var probe: bool = "--delivery-probe" in OS.get_cmdline_user_args()
	var count: int = 1 if probe else 98
	for frame in count:
		var t: float = 1.5 if probe else float(frame) / 30.0
		var phase: float = 3.5 + t * 3.2
		fx.set("_clock", phase - float(bay.t0))
		fx.queue_redraw()
		var lights: Control = fx.get("_fire_layer")
		if lights != null:
			lights.queue_redraw()
		await wait_frames(1)
		await shot("hydraulic_probe" if probe else "hydraulic_%03d" % frame)
	var file := FileAccess.open(OUT + "/hydraulic_evidence.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"instance":BuildingState.get_building(iid),"recipe":recipe,
		"level":panel.get("_level"),"native_fx":"empire_fx.gd", "bay":bay,
		"phase_start_s":3.5,"animation_speed":3.2,"frames":count,"fps":30,
		"caption":recipe.display_name,
		"description":"Native cosmetic bay animation: reverse to dock, unload crates, close door. Isolated staging; no saved match."}, "\t"))
	file.close()
	print("HYDRAULIC_CAPTURE_DONE")

func approach() -> void:
	# Render the actual maximum camera zoom, preserving native map detail and FX.
	var cam: Camera2D = host.camera
	cam.call("_configure_for_map")
	var max_zoom: float = cam.get("zoom_max")
	var stoneshore: Vector2 = host.tile_position("tile_5_10")
	var ships: Node2D = host.world.find_child("PortShipVisuals", true, false)
	var port := stoneshore
	var berth_count := 0
	for berth: Dictionary in ships.get("_berths"):
		if str(berth.get("tile_id", "")) == "tile_5_10":
			if berth_count == 0:
				port = Vector2.ZERO
			port += Vector2(berth.berth)
			berth_count += 1
	if berth_count > 0:
		port /= float(berth_count)
	assert(berth_count > 0, "Stoneshore harbour must exist")
	var chimney := stoneshore
	var nearest := INF
	for stack: Dictionary in host.buildings.smoke_stacks():
		var gap: float = Vector2(stack.pos).distance_to(port)
		if gap < nearest:
			nearest = gap
			chimney = stack.pos
	assert(nearest < INF)
	var target: Vector2 = port.lerp(chimney, 0.35) + Vector2(0, 10)
	var ship_clock := 20.0
	for route: Dictionary in ships.get("_callers"):
		var berth: Dictionary = route.berth
		if str(berth.get("tile_id", "")) == "tile_5_10" and not route.arrivals.is_empty():
			ship_clock = float(route.arrivals[0]) - 1.0
			break
	var fx: Array[Node2D] = []
	for node_name: String in ["SmokeVisuals", "PortShipVisuals", "BirdVisuals", "ConstructionVisuals"]:
		var node: Node2D = host.world.find_child(node_name, true, false)
		if node != null:
			node.set_process(false)
			fx.append(node)
	var probe: bool = "--approach-probe" in OS.get_cmdline_user_args()
	var count: int = 1 if probe else 173
	for frame in count:
		var t: float = 5.0 if probe else float(frame) / 30.0
		var u: float = smoothstep(0.0, 4.5, t)
		cam.position = stoneshore.lerp(target, u)
		cam.zoom = Vector2.ONE * exp(lerpf(log(max_zoom * 0.25), log(max_zoom), u))
		cam.force_update_scroll()
		for node: Node2D in fx:
			node.set("_clock", (ship_clock if node == ships else 20.0) + t)
			node.queue_redraw()
		await wait_frames(1)
		await shot("approach_probe" if probe else "approach_%03d" % frame)
	var file := FileAccess.open(OUT + "/approach_evidence.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"max_zoom":max_zoom,"end_zoom":cam.zoom.x,
		"camera_target":target,"port":port,"nearest_chimney":chimney,
		"port_berths":berth_count,"ship_clock_start":ship_clock,"frames":count,"fps":30}, "\t"))
	file.close()
	print("APPROACH_CAPTURE_DONE")

func wait_frames(n: int = 12) -> void:
	for i in n:
		await host.get_tree().process_frame

func expose(panel: Control, rect: Rect2) -> void:
	panel.reparent(layer)
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.position = rect.position
	panel.size = rect.size
	panel.show()

func shot(name: String) -> void:
	# Explicit draw/readback also works when the window is behind the review browser.
	RenderingServer.force_draw()
	var im: Image = host.get_viewport().get_texture().get_image()
	assert(im.save_png(OUT + "/" + name + ".png") == OK)
	im = null
	print("LAUNCH_SHOT ", name)

func market() -> void:
	var panel: Control = host.world.find_child("MarketPanel", true, false)
	expose(panel, Rect2(55, 70, 1810, 900))
	await wait_frames()
	panel._set_impact_expanded(true)
	panel.size = Vector2(1810, 850)
	panel.position = Vector2(55, 75)
	panel._search.text = "iron ore"
	panel._search.text_changed.emit("iron ore")
	await wait_frames()
	var good: String = str(Catalog.get_good_by_internal_name("iron_ore").id)
	var chart: Control
	for row: Control in panel.rows:
		if str(row.get("good_id")) == good:
			row._toggle_expand()
			# Enlarge the native, read-only history chart for trailer readability.
			chart = row._price_chart
			chart.reparent(layer)
			chart.set_anchors_preset(Control.PRESET_TOP_LEFT)
			chart.position = Vector2(525, 377)
			chart.custom_minimum_size = Vector2(1300, 505)
			chart.size = Vector2(1300, 505)
			chart.show()
	var qty: int = Catalog.base_output_for_good(good) * 8
	var records: Array = []
	for i in 16:
		qty = Catalog.base_output_for_good(good) * (2 + i)
		if i > 0:
			var result: Dictionary = MatchState.queue_buy("tile_5_10", good, qty)
			assert(int(result.get("qty", 0)) == qty, "Trailer market purchase must really succeed")
			TurnManager.current_turn += 1
			MarketState.tick_turn()
			MarketState._record_price_history()
			MarketState.prices_updated.emit()
		panel._queue_refresh()
		await wait_frames(3)
		# The row refresh also lays out its chart; restore the capture framing
		# after that native refresh has settled, without altering the chart data.
		chart.position = Vector2(525, 377)
		chart.size = Vector2(1300, 505)
		records.append({"turn":TurnManager.current_turn,"price":MarketState.get_buy_price(good),"impact":MarketState.get_impact_pct(good),"buy_qty":qty if i > 0 else 0})
		await shot("market_%02d" % i)
	evidence.market = records
	assert(float(records[-1].price) > float(records[0].price))
	for child: Node in layer.get_children():
		if child.name == "PriceHistoryChart":
			(child as Control).hide()
	panel.hide()

func build_and_site() -> void:
	var menu: Node = host.world.get_node("UILayer/HUD")
	var panel: Control = menu.construct_panel_v2
	expose(panel, Rect2(500, 75, 920, 930))
	panel._locked_tile_id = "tile_5_10"
	panel._on_building_pressed("b_002")
	await wait_frames()
	await shot("build_menu")
	panel._on_recipe_pressed("b_002", "r_005")
	await wait_frames()
	await shot("build_confirm")
	if panel._scroll != null:
		panel._scroll.scroll_vertical = 10000
	await wait_frames()
	await shot("build_payback")
	panel.hide()
	var site_tile := "tile_3_8"
	var iid: String = Construction.start_awaiting_market("b_002", "r_005", site_tile, 0.0)
	assert(iid != "")
	var bdp: Control = host.world.find_child("BuildingDetailPanelV2", true, false)
	expose(bdp, Rect2(610, 70, 700, 930))
	bdp.show_building({"instance_id":iid,"building_id":"b_002","recipe_id":"r_005","tile_id":site_tile,"level":1})
	await wait_frames()
	await shot("construction_eta")
	evidence.construction = Construction.construction_projects[iid].duplicate(true)
	bdp.hide()
	var empire: Control = host.world.find_child("EmpireView", true, false)
	expose(empire, Rect2(0, 0, 1920, 1080))
	empire.refresh_graph()
	await wait_frames(20)
	var graph: Control = empire.find_child("GraphWorld", true, false)
	graph.focus_on(iid, true)
	await wait_frames(20)
	var shortest_eta := 10000
	for lane: Dictionary in graph._site_lanes(iid):
		assert(bool(lane.ordered) and not bool(lane.blocked))
		shortest_eta = mini(shortest_eta, int(lane.eta))
	if shortest_eta > 1:
		assert(TransportState.advance_transport_shipments().is_empty())
		TurnManager.current_turn += 1
	for frame in 90:
		await host.get_tree().process_frame
		await shot("site_%03d" % frame)
	evidence.site_lanes = graph._site_lanes(iid)
	empire.hide()

func research() -> void:
	var panel: Control = host.world.find_child("ResearchPanel", true, false)
	expose(panel, Rect2(40, 65, 1840, 950))
	panel._selected_category = "Vehicle Production"
	var title := "Electric Vehicle Assembly"
	assert(ResearchState.is_node_available(title))
	var layout: Dictionary = panel._layout_unlocks(panel._category_unlocks("Vehicle Production"))
	var node_rect: Rect2 = layout[title]
	var zoom := 1.05
	var pan: Vector2 = Vector2(900, 480) - panel._tree_origin() - node_rect.get_center() * zoom
	panel._category_view_state["Vehicle Production"] = {"zoom":zoom,"pan":pan}
	panel.begin_free_unlock_choice()
	var pick: Vector2 = panel._tree_origin() + pan + node_rect.get_center() * zoom
	panel._update_hover_unlock(pick)
	panel.queue_redraw()
	await wait_frames()
	await shot("research_before")
	panel.hide()
	var view: Control = host.world.find_child("GoodsGraphView", true, false)
	expose(view, Rect2(0, 0, 1920, 1080))
	view.open_focused("ev_car")
	await wait_frames(20)
	var graph: Control = view.find_child("GraphWorld", true, false)
	graph.set("_focus_t", 1.0)
	graph.set("_view_zoom", 0.65)
	var good := "ev_car"
	var positions: Dictionary = graph.get("_fpos")
	if positions.has(good):
		graph.set("_view_offset", Vector2(1300, 530) - positions[good] * 0.65)
	graph.queue_redraw()
	await wait_frames()
	await shot("graph_locked")
	view.hide()
	panel.show()
	assert(panel._try_choose_free_unlock(pick))
	assert(ResearchState.is_unlocked(title))
	await wait_frames()
	await shot("research_after")
	panel.hide()
	view.open_focused("ev_car")
	await wait_frames(20)
	graph.set("_focus_t", 1.0)
	graph.set("_view_zoom", 0.65)
	positions = graph.get("_fpos")
	if positions.has(good):
		graph.set("_view_offset", Vector2(1300, 530) - positions[good] * 0.65)
	graph.queue_redraw()
	await wait_frames()
	await shot("graph_unlocked")
	evidence.research = {"title":title,"unlocked":ResearchState.is_unlocked(title),"pick_screen":pick,"free_remaining":panel._free_unlocks}
	view.hide()
