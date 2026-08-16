extends Node2D
## S0 UI-hidden SettlementPlan diagnostic for Silkstown.

const SettlementPlanDebugVisualsScript = preload("res://tools/settlement_plan_debug_visuals.gd")

@export_enum("s0", "s1") var capture_phase := "s0"

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
	var plan := fabric.settlement_plan("silkstown")
	if plan == null:
		push_error("settlement_plan_shot: Silkstown plan was not built")
		get_tree().quit(1)
		return
	for name in ["HillVisuals", "ForestVisuals", "UrbanFabricVisuals",
			"RiverVisuals", "BuildingVisuals", "RoadNetworkVisuals", "PortVisuals"]:
		var item := game.get_node_or_null(name) as CanvasItem
		if item != null:
			item.visible = false
	var overlay := SettlementPlanDebugVisualsScript.new()
	overlay.plan = plan
	overlay.show_zoning = capture_phase == "s1"
	game.add_child(overlay)
	overlay.queue_redraw()
	var cam := get_viewport().get_camera_2d()
	cam.set_process(false)
	cam.set_physics_process(false)
	cam.position = Vector2(4330.0, 4735.0)
	cam.zoom = Vector2(0.82, 0.82)
	if "_target_zoom" in cam:
		cam.set("_target_zoom", cam.zoom)
	for _i in 20:
		await get_tree().process_frame
	RenderingServer.force_draw()
	var image := get_viewport().get_texture().get_image()
	var size := Vector2i(mini(960, image.get_width()), mini(720, image.get_height()))
	var origin := Vector2i((image.get_width() - size.x) / 2,
		(image.get_height() - size.y) / 2)
	var output_stem := "/tmp/poe_plan_silkstown_%s" % capture_phase
	image.get_region(Rect2i(origin, size)).save_png("%s.png" % output_stem)
	var file := FileAccess.open("%s.json" % output_stem, FileAccess.WRITE)
	file.store_string(JSON.stringify(plan.summary(), "  "))
	file.close()
	var gate_errors := PackedStringArray()
	if float(plan.diagnostics.max_endpoint_distance) > 0.25:
		gate_errors.append("decorative street endpoint does not meet a real road")
	if int(plan.diagnostics.water_samples) != 0:
		gate_errors.append("decorative street enters water")
	if int(plan.diagnostics.face_self_intersections) != 0:
		gate_errors.append("enclosed face self-intersects")
	if int(plan.diagnostics.enclosed_district_guides) < int(plan.diagnostics.required_enclosed_district_guides):
		gate_errors.append("intended district area is not enclosed")
	if not (plan.diagnostics.geometry_errors as Array).is_empty():
		gate_errors.append("plan geometry validation failed")
	print("[SETTLEMENT PLAN] Silkstown %s: %d faces, %d streets, %d water samples, max endpoint %.2fu" % [
		capture_phase.to_upper(),
		plan.faces.size(), plan.decorative_streets.size(),
		int(plan.diagnostics.water_samples), float(plan.diagnostics.max_endpoint_distance),
	])
	MapStyle.set_midcentury(false)
	if not gate_errors.is_empty():
		push_error("settlement_plan_shot: S0 hard gates failed: %s" % "; ".join(gate_errors))
	get_tree().quit(0 if gate_errors.is_empty() else 2)
