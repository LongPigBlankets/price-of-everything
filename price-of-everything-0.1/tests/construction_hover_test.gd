extends Node

const Preview := preload("res://scripts/construction_hover.gd")
var failures := 0
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func settle(frames: int = 3) -> void:
	for i in frames:
		await get_tree().process_frame

func move_mouse(point: Vector2) -> void:
	if DisplayServer.get_name() != "headless":
		get_viewport().warp_mouse(point)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	get_viewport().push_input(motion, true)
	await settle()

func _ready() -> void:
	var world := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(world)
	await settle(160)
	var camera := get_viewport().get_camera_2d()
	camera.set("edge_pan_enabled", false)
	camera.set_process(false)
	var panel = world.get_node("UILayer/HUD").construct_panel_v2
	MatchState.set_use_construct_panel_v3(true)
	panel.open_browser()
	panel._on_recipe_pressed("b_002", "r_005")
	await settle()
	check(panel.find_child("V3CashTimeline", true, false) == null, "Unselected-site confirm omits the cash timeline")
	var duration: Control = panel.find_child("V3DurationBox", true, false)
	var total: Control = panel.find_child("V3Total", true, false)
	check(duration.get_parent() == total.get_parent(), "Build duration shares the total's column inside the hero row")
	panel.open_for_tile("tile_5_10", {"type": ""})
	panel._on_recipe_pressed("b_002", "r_005")
	await settle()
	check(panel.find_child("V3CashTimeline", true, false) != null, "Selected-site confirm retains the cash timeline")
	panel.hide()
	var cash := MatchState.money
	for tile_id in ["tile_5_10", "tile_23_8"]:
		var data := Preview.preview(tile_id, "b_002", "r_005")
		var ledger := Construction.materials_ledger("b_002", tile_id)
		check(is_equal_approx(float(data.materials) + float(data.transport), float(ledger.subtotal)), "Materials and transport reconcile with the live ledger on " + tile_id)
		check(is_equal_approx(float(data.total), float(ledger.subtotal) + float(data.land) + float(data.fee)), "Preview total includes all construction costs on " + tile_id)
		for row in ledger.rows:
			if int(row.market_qty) > 0:
				var quote := MatchState.preview_buy(tile_id, str(row.good_id), int(row.market_qty))
				check(is_equal_approx(float(row.transport_cost), float(quote.get("transport_cost", 0))), "Freight uses the purchase quote")
	check(MatchState.money == cash, "Hover quotes do not spend cash")
	var hover = world.get_node("ConstructionHover")
	BuildMode.enter_build_mode("b_002", "r_005", true)
	var terrain: HexMap = world.get_node("TerrainLayer")
	var coord := terrain.id_to_coord("tile_5_10")
	var center := terrain.to_global(terrain.map_to_local(terrain.map_coord_for_tile_coord(coord)))
	camera.position = center
	camera.zoom = Vector2(0.5, 0.5)
	camera.reset_smoothing()
	camera.force_update_scroll()
	await settle()
	var screen := get_viewport().get_canvas_transform() * center
	await move_mouse(screen)
	check(hover.card.visible, "Hovering map space displays the preview through the HUD's empty area")
	check(str(hover._key).begins_with("tile_5_10|"), "Preview follows the actual hovered tile: " + str(hover._key))
	check(hover.card.size.y < 600, "Hover card fits its content without empty vertical space")
	var timeline: GridContainer = hover.card.find_child("RevenueTimeline", true, false)
	check(timeline != null and timeline.get_child_count() == 15, "Revenue table ends with stable production after its three post-construction phases")
	check(timeline.get_child(13).text == "Stable production", "Unfinanced forecast ends with stable production")
	check(hover.card.size.x >= 440, "Hover panel has room for the longer cash-flow labels")
	var table_script := preload("res://scripts/build_forecast_table.gd")
	for sample in [[-15.0, "Deficit"], [-14.99, "Small Deficit"], [-0.01, "Small Deficit"],
		[0.0, "Even"], [0.01, "Small Surplus"], [14.99, "Small Surplus"], [15.0, "Surplus"]]:
		check(table_script._cash_direction(float(sample[0])) == sample[1], "Cash-flow threshold: " + str(sample[0]))
	check(hover.card.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Preview does not intercept tile selection")
	var payback: Label = hover.card.find_child("ForecastPayback", true, false)
	check(payback != null and payback.get_theme_font_size("font_size") == 20, "Payback is prominent")
	for label in timeline.get_children():
		check(not label.text.contains("£"), "Forecast avoids money amounts")
	MatchState.advisor_seats = {"cfo": "vera"}
	MatchState.set_construct_credit_default("slices")
	await settle()
	timeline = hover.card.find_child("RevenueTimeline", true, false)
	check(timeline.get_child_count() == 18 and timeline.get_child(13).text == "During repayment", "CFO adds one repayment row")
	check(timeline.get_child(16).text == "Stable production\nafter repayment", "Stable production follows the CFO repayment row")
	var forecast: Dictionary = Preview.preview("tile_5_10", "b_002", "r_005").forecast
	check(timeline.get_child(15).text == "Turn %d onwards" % (int(forecast.financing.end) + 1), "Stable production starts after the last repayment")
	check(timeline.get_child(17).text == table_script._cash_direction(float(forecast.steady_net)), "Final outlook excludes temporary repayment costs")
	check(hover.card.size.y < 500, "CFO hover remains compact")

	Stockpile.stockpile_changed.emit()
	check(hover._key == "", "Material changes invalidate the site quote without moving the cursor")
	await settle()
	check(str(hover._key).begins_with("tile_5_10|"), "The site quote refreshes after material changes")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/construction_hover.png")
	var bar: Control = world.get_node("UILayer/HUD/TopBar")
	await move_mouse(bar.get_global_rect().get_center())
	check(not hover.card.visible, "Hover preview hides over the top bar")
	await move_mouse(screen)
	check(hover.card.visible, "Preview returns when moving back to the map")
	BuildMode.exit_build_mode()
	check(not hover.card.visible and not hover.is_processing(), "Leaving build mode hides the preview and stops its updates")
	# The saved demo flag hides forecasts in both construction flows, while the
	# campaign keeps the full table. Construction price quotes remain visible.
	var saved_rules := MatchState.ruleset.duplicate(true)
	MatchState.ruleset["victory_set"] = "demo_itch"
	hover.show_preview("tile_5_10", "b_002", "r_005")
	await settle()
	check(hover.card.find_child("RevenueTimeline", true, false) == null, "Demo hover hides balance impact")
	check(hover.card.find_child("ForecastPayback", true, false) != null, "Demo hover retains payback")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/construction_hover_demo.png")
	hover.card.hide()
	panel.open_for_tile("tile_5_10", {"type": "urban"})
	panel._on_recipe_pressed("b_002", "r_005")
	await settle()
	check(panel.find_child("RevenueTimeline", true, false) == null, "Demo confirm hides balance impact")
	check(panel.find_child("ForecastPayback", true, false) != null, "Demo confirm retains payback")
	check(not panel.find_child("BuildCostValue", true, false).is_visible_in_tree(), "Demo confirm hides cash-after balance")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/construction_confirm_demo.png")
	panel.hide()
	MatchState.ruleset = saved_rules
	hover.show_preview("tile_5_10", "b_002", "r_005")
	check(hover.card.find_child("RevenueTimeline", true, false) != null, "Campaign balance impact remains available")

	print("[construction_hover] %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
