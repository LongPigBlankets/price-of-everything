extends Node2D
## Fixed UI-hidden Silkstown S2 render captures at two readable scales.

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
	var camera := get_viewport().get_camera_2d()
	camera.set_process(false)
	camera.set_physics_process(false)
	camera.position = Vector2(4320.0, 4800.0)
	await _capture(camera, 1.35, Vector2i(960, 480),
		"/tmp/poe_plan_silkstown_s2_close.png")
	await _capture(camera, 0.82, Vector2i(960, 720),
		"/tmp/poe_plan_silkstown_s2_regional.png")
	var fabric := game.get_node("UrbanFabricVisuals") as UrbanFabricVisuals
	var file := FileAccess.open("/tmp/poe_plan_silkstown_s2.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"plan": fabric.settlement_plan("silkstown").summary(),
		"fabric": fabric.metrics().get("settlements", {}).get(
			"settlement-plan|silkstown", {}),
	}, "  "))
	file.close()
	MapStyle.set_midcentury(false)
	get_tree().quit(0)

func _capture(camera: Camera2D, zoom: float, size: Vector2i, path: String) -> void:
	camera.zoom = Vector2(zoom, zoom)
	if "_target_zoom" in camera:
		camera.set("_target_zoom", camera.zoom)
	for _i in 18:
		await get_tree().process_frame
	RenderingServer.force_draw()
	var image := get_viewport().get_texture().get_image()
	var crop_size := Vector2i(mini(size.x, image.get_width()),
		mini(size.y, image.get_height()))
	var origin := Vector2i((image.get_width() - crop_size.x) / 2,
		(image.get_height() - crop_size.y) / 2)
	image.get_region(Rect2i(origin, crop_size)).save_png(path)
	print("[SETTLEMENT PLAN] captured %s" % path)
