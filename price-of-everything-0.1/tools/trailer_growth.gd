extends Node2D
## Isolated promotional staging; never saves a match. Sales uses real market settlement.
const ShotHarness = preload("res://tools/shot_harness.gd")
const OUT = "/Users/crisu/Price of Everything/price-of-everything/outputs/launch-clips-2026-09-07"
var world: Node
var terrain: Node
var buildings: Node
var camera: Camera2D
var selected: Array = []

func _ready() -> void:
	ShotHarness.prepare_window(get_window(), Vector2i(960, 540))
	ShotHarness.arm_watchdog(self, 240.0)
	get_viewport().set_disable_input(true)
	AudioServer.set_bus_mute(0, true)
	world = load("res://scenes/main.tscn").instantiate()
	add_child(world)
	for i in 150:
		await get_tree().process_frame
	ShotHarness.prepare_window(get_window(), Vector2i(1920, 1080))
	for i in 15:
		await get_tree().process_frame
	terrain = world.get_node("%TerrainLayer")
	buildings = world.get_node("%BuildingVisuals")
	var ui: CanvasLayer = world.get_node_or_null("UILayer")
	if ui: ui.visible = false
	var grid: CanvasItem = world.find_child("HexGridOverlay", true, false)
	if grid: grid.visible = false
	camera = get_viewport().get_camera_2d()
	camera.set_process(false)
	camera.set_physics_process(false)
	camera.position_smoothing_enabled = false
	if "--sales" in OS.get_cmdline_user_args():
		await capture_sales()
		get_tree().quit()
		return
	if "--specialties" in OS.get_cmdline_user_args():
		await capture_specialties()
		get_tree().quit()
		return
	if "--upgrades" in OS.get_cmdline_user_args():
		await capture_upgrades()
		get_tree().quit()
		return
	var center: Vector2 = tile_position("tile_5_10")
	for coord in terrain.tiles:
		var td: Dictionary = terrain.tiles[coord]
		var kind: String = str(td.get("type", "")).to_lower()
		if kind not in ["urban", "rural"]: continue
		var tid: String = "tile_%d_%d" % [coord.x, coord.y]
		selected.append({"id":tid, "coord":coord, "pos":tile_position(tid), "distance":tile_position(tid).distance_to(center)})
	selected.sort_custom(func(a,b): return a.distance < b.distance)
	selected = selected.slice(0, 36)
	print("TRAILER_SELECTED ", selected)
	var mn: Vector2 = center
	var mx: Vector2 = center
	for tile in selected:
		mn = mn.min(tile.pos)
		mx = mx.max(tile.pos)
	var final_center: Vector2 = (mn + mx) * 0.5 + Vector2(550, 0)
	var extent: Vector2 = mx - mn + Vector2(750,750)
	var final_zoom: float = minf(1920.0/extent.x,1080.0/extent.y) * 1.08
	var probe: bool = "--probe" in OS.get_cmdline_user_args()
	if probe:
		camera.position = final_center
		camera.zoom = Vector2.ONE * final_zoom
		await settle()
		await snap("growth-before.png")
		for tile in selected:
			world._apply_built_infrastructure(tile.coord, tile.id, "roads")
			for j in 6: place(tile,j)
		await settle()
		await snap("growth-after.png")
		print("TRAILER_PROBE_DONE")
	else:
		DirAccess.make_dir_recursive_absolute(OUT + "/growth-frames")
		print("TRAILER_CAPTURE_SIZE ", get_viewport().get_texture().get_image().get_size())
		var n: int = 0
		# 216 buildings, alternating one/two per quarter second: 36 seconds.
		for frame in 1110:
			var t: float = frame / 30.0
			var u: float = clampf(t/36.0, 0.0, 1.0)
			camera.position = center.lerp(final_center, smoothstep(0,1,u))
			camera.zoom = Vector2.ONE * exp(lerpf(log(1.05),log(final_zoom),smoothstep(0,1,u)))
			var target: int = mini(216, int(floor(t / 0.25) * 1.5))
			while n < target:
				var tile: Dictionary = selected[n / 6]
				if n % 6 == 0: world._apply_built_infrastructure(tile.coord, tile.id, "roads")
				place(tile,n % 6)
				n += 1
			await get_tree().process_frame
			RenderingServer.force_draw()
			var im: Image = get_viewport().get_texture().get_image()
			im.save_jpg(OUT + "/growth-frames/%04d.jpg" % frame, 0.96)
			im = null
			if frame % 90 == 0: print("TRAILER_FRAME ",frame," BUILDINGS ",n)
	var visible_count: int = 0
	for tile in selected:
		for j in 6:
			if buildings.has_placement("trailer_%s_%d" % [tile.id,j]): visible_count += 1
	print("TRAILER_VERIFIED_PLACEMENTS ",visible_count," TILES ",selected.size())
	print("TRAILER_DONE")
	get_tree().quit()

func tile_position(tid: String) -> Vector2:
	return terrain.map_to_local(terrain.map_coord_for_tile_coord(terrain.id_to_coord(tid)))

func place(tile: Dictionary, n: int) -> void:
	var bid: String = ["b_007","b_002","b_009","b_011","b_012","b_007"][n]
	var iid: String = BuildingState.add_building(bid,"",tile.id,"player_1","trailer_%s_%d" % [tile.id,n],false)
	buildings.on_building_placed(tile.id,bid,"",iid,tile.coord)

func settle() -> void:
	for i in 20: await get_tree().process_frame

func snap(name: String) -> void:
	RenderingServer.force_draw()
	var im: Image = get_viewport().get_texture().get_image()
	im.save_png(OUT+"/"+name)
	im = null

func capture_upgrades() -> void:
	# Capture actual level-dependent building art; no costs, turns or saves.
	DirAccess.make_dir_recursive_absolute(OUT + "/upgrade-stills")
	UiPrefs.use_empire_sprite_view = true
	var overlay: CanvasLayer = CanvasLayer.new()
	add_child(overlay)
	var backdrop: Control = load("res://scripts/empire_hex_bg.gd").new()
	backdrop.size = Vector2(1920, 1080)
	overlay.add_child(backdrop)
	backdrop.set_process(false)
	backdrop.set("_t", 0.0)
	for bid: String in ["b_002", "b_007"]:
		var iid: String = ""
		var nearest: float = INF
		for key: String in BuildingState.buildings:
			var candidate: Dictionary = BuildingState.buildings[key]
			if str(candidate.get("building_id", "")) != bid or not buildings.has_placement(key):
				continue
			var distance: float = tile_position(str(candidate.tile_id)).distance_to(tile_position("tile_5_10"))
			if distance < nearest:
				iid = key
				nearest = distance
		assert(iid != "", "No placed upgrade subject")
		BuildingState.set_building_owner(iid, "player_1")
		for level: int in [1, 2, 3]:
			BuildingState.buildings[iid]["level"] = level
			BuildingWorks.building_upgraded.emit(iid, level)
			var graph: Dictionary = preload("res://scripts/empire_graph.gd").build(terrain)
			var subject: Dictionary = {}
			for node: Dictionary in graph.nodes:
				if str(node.iid) == iid: subject = node
			assert(not subject.is_empty() and subject.get("sprite") != null)
			var panel: Control = load("res://scripts/empire_node_panel.gd").new()
			overlay.add_child(panel)
			panel.setup(subject)
			panel.scale = Vector2.ONE * 1.45
			panel.position = Vector2(960 - panel.size.x * 1.45 / 2.0, 210)
			await settle()
			await snap("upgrade-stills/%s_L%d.png" % [bid, level])
			print("TRAILER_UPGRADE ", bid, " LEVEL ", level, " SPRITE ", subject.sprite.resource_path)
			panel.queue_free()
			await get_tree().process_frame
	print("TRAILER_UPGRADES_DONE")

func capture_specialties() -> void:
	DirAccess.make_dir_recursive_absolute(OUT + "/specialty-stills")
	var view: Control = world.find_child("GoodsGraphView", true, false)
	# Keep the actual graph renderer and focus layout, framed for a title above it.
	var overlay: CanvasLayer = CanvasLayer.new()
	add_child(overlay)
	view.reparent(overlay)
	view.position = Vector2.ZERO
	view.size = Vector2(1920, 1080)
	for good: String in ["silica", "hydraulic_components", "plastics", "iron_ingots"]:
		view.open_focused(good)
		await settle()
		var graph: Control = view.find_child("GraphWorld", true, false)
		graph.set("_focus_t", 1.0)
		graph.set("_view_zoom", 1.0)
		var positions: Dictionary = graph.get("_fpos")
		graph.set("_view_offset", Vector2(960, 610) - (positions[good] as Vector2))
		graph.queue_redraw()
		await settle()
		await snap("specialty-stills/%s.png" % good)
		print("TRAILER_SPECIALTY ", good)
	print("TRAILER_SPECIALTIES_DONE")

func capture_sales() -> void:
	DirAccess.make_dir_recursive_absolute(OUT + "/sales-frames")
	var steel: String = str(Catalog.get_good_by_internal_name("steel").get("id", ""))
	var iron: String = str(Catalog.get_good_by_internal_name("iron_ingots").get("id", ""))
	var route: Dictionary = TransportService.route_to_nearest_port("tile_5_10", steel)
	var port: String = str(route.get("port", ""))
	assert(port != "", "Sales capture needs a reachable port")
	Stockpile.add(port, iron, 92)
	var baseline: Dictionary = MarketState.execute_sale(port, {iron:92}, {"log_oneoff":false})
	assert(not baseline.is_empty() and not bool(baseline.get("deferred", true)))
	var iron_revenue: float = float(baseline.total_revenue)
	var panel: Control = world.find_child("MoneyPanel", true, false)
	var overlay: CanvasLayer = CanvasLayer.new()
	add_child(overlay)
	panel.reparent(overlay)
	panel.visible = true
	panel.open_tab("Sales")
	await settle()
	panel.size = Vector2(1050, 540)
	panel.scale = Vector2.ONE * 1.35
	panel.position = Vector2(251, 175)
	var rows: Array = [
		{"gid":steel, "label":Catalog.get_display_name(steel), "qty":0, "amount":0.0},
		{"gid":iron, "label":Catalog.get_display_name(iron), "qty":92, "amount":iron_revenue}]
	# Use the panel's native renderer, retaining an explicit zero steel row for comparison.
	render_sales_rows(panel, rows)
	await settle()
	await snap("sales-frames/before.png")
	var sale: Dictionary = {}
	for frame: int in 90:
		if frame == 45:
			Stockpile.add(port, steel, 84)
			sale = MarketState.execute_sale(port, {steel:84}, {"log_oneoff":false})
			assert(int(sale.get("total_qty",0)) == 84 and not bool(sale.get("deferred",true)))
			assert(float(sale.total_revenue) > 0.0)
			# Let deferred native refreshes settle before rebuilding the stable comparison.
			await settle()
			rows[0]["qty"] = int(sale.total_qty)
			rows[0]["amount"] = float(sale.total_revenue)
			render_sales_rows(panel, rows)
			await settle()
			await snap("sales-frames/after.png")
		await get_tree().process_frame
		RenderingServer.force_draw()
		var im: Image = get_viewport().get_texture().get_image()
		im.save_jpg(OUT + "/sales-frames/%04d.jpg" % frame, 0.97)
		im = null
	var proof: Dictionary = {"port":port, "before_steel_qty":0, "after_steel_qty":int(sale.total_qty),
		"before_revenue":iron_revenue, "after_revenue":iron_revenue+float(sale.total_revenue),
		"baseline_transaction":baseline, "steel_transaction":sale,
		"presentation":"Native money panel renderer; zero steel row retained explicitly; settled refresh at frame 45"}
	var evidence: FileAccess = FileAccess.open(OUT + "/sales-frames/settlement.json", FileAccess.WRITE)
	evidence.store_string(JSON.stringify(proof, "  "))
	evidence.close()
	print("TRAILER_SALES_VERIFIED ", JSON.stringify(proof))

func render_sales_rows(panel: Control, rows: Array) -> void:
	var root: VBoxContainer = panel.get("_sales_tab_root")
	for child: Node in root.get_children():
		root.remove_child(child)
		child.queue_free()
	panel._add_breakdown_section(root, "Last turn", rows, "No sales", "Total sales income")
