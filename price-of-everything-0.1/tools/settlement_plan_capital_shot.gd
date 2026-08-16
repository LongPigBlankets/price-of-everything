extends Node2D
## C0 UI-hidden SettlementPlan diagnostic for Capital Port continuity.

const SettlementPlanDebugVisualsScript = preload("res://tools/settlement_plan_debug_visuals.gd")

func _ready() -> void:
	get_viewport().set_disable_input(true)
	var game := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	for _i in 150:
		await get_tree().process_frame
	var ui := game.get_node_or_null("UILayer") as CanvasLayer
	if ui != null:
		ui.visible = false
	var grid := game.find_child("HexGridOverlay", true, false) as CanvasItem
	if grid != null:
		grid.visible = false
	MapStyle.set_midcentury(true)
	for _i in 24:
		await get_tree().process_frame
	var fabric := game.get_node("UrbanFabricVisuals") as UrbanFabricVisuals
	var plan := fabric.settlement_plan("capital-port")
	if plan == null:
		push_error("settlement_plan_capital_shot: Capital plan was not built")
		get_tree().quit(1)
		return
	for name in ["HillVisuals", "ForestVisuals", "UrbanFabricVisuals",
			"RiverVisuals", "BuildingVisuals", "RoadNetworkVisuals", "PortVisuals"]:
		var item := game.get_node_or_null(name) as CanvasItem
		if item != null:
			item.visible = false
	var overlay := SettlementPlanDebugVisualsScript.new()
	overlay.plan = plan
	overlay.show_water_safety = true
	game.add_child(overlay)
	overlay.queue_redraw()
	var camera := get_viewport().get_camera_2d()
	camera.set_process(false)
	camera.set_physics_process(false)
	camera.position = Vector2(10685.0, 4835.0)
	camera.zoom = Vector2(0.72, 0.72)
	if "_target_zoom" in camera:
		camera.set("_target_zoom", camera.zoom)
	for _i in 20:
		await get_tree().process_frame
	RenderingServer.force_draw()
	var image := get_viewport().get_texture().get_image()
	var size := Vector2i(mini(1280, image.get_width()), mini(720, image.get_height()))
	var origin := Vector2i((image.get_width() - size.x) / 2,
		(image.get_height() - size.y) / 2)
	image.get_region(Rect2i(origin, size)).save_png("/tmp/poe_plan_capital_c0.png")
	var file := FileAccess.open("/tmp/poe_plan_capital_c0.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(plan.summary(), "  "))
	file.close()
	var errors := PackedStringArray()
	if int(plan.diagnostics.internal_edge_count) != 8:
		errors.append("Capital plan does not contain all 8 internal component edges")
	if int(plan.diagnostics.face_self_intersections) != 0:
		errors.append("Capital face self-intersects")
	if not (plan.diagnostics.geometry_errors as Array).is_empty():
		errors.append("Capital plan geometry validation failed")
	for key in [
		"ordinary_mass_water_overlap_area",
		"industrial_support_water_overlap_area",
		"cross_bank_mass_count",
		"disconnected_mass_after_water_clip_count",
		"roof_element_water_overlap_count",
		"shadow_water_overlap_count",
		"uncovered_river_join_count",
	]:
		if float(plan.diagnostics.get(key, -1.0)) != 0.0:
			errors.append("Capital water-safety gate failed: %s=%s" % [
				key, plan.diagnostics.get(key, "missing")])
	print("[SETTLEMENT PLAN] Capital C0: %d faces, %.1f%% internal coverage, %.1fu empty strip" % [
		plan.faces.size(), 100.0 * float(plan.diagnostics.internal_band_coverage),
		float(plan.diagnostics.longest_internal_empty_strip)])
	MapStyle.set_midcentury(false)
	if not errors.is_empty():
		push_error("settlement_plan_capital_shot: %s" % "; ".join(errors))
	get_tree().quit(0 if errors.is_empty() else 2)
