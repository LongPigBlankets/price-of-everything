extends Node2D
## Fixed UI-hidden Phase-A capture and hard-gate oracle for oriented compounds.

const ZERO_DIAGNOSTICS := [
	"apron_missing_count",
	"apron_containment_failure_count",
	"apron_unrelated_gameplay_overlap_count",
	"apron_water_overlap_count",
	"apron_road_overlap_count",
	"apron_relief_overlap_count",
	"support_building_overlap_count",
]

func _ready() -> void:
	print("[INDUSTRY COMPOUND] harness start")
	get_viewport().set_disable_input(true)
	var game := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	print("[INDUSTRY COMPOUND] world instantiated")
	for _i in 150:
		await get_tree().process_frame
	print("[INDUSTRY COMPOUND] initial frames complete")
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
	var fabric := game.get_node("UrbanFabricVisuals") as UrbanFabricVisuals
	var record := {"plans": {}, "generic": fabric.metrics().get(
		"industry_compound_diagnostics", {})}
	var errors := PackedStringArray()
	var rotated_targets: Array = []
	for plan_key in ["silkstown", "capital-port"]:
		var plan := fabric.settlement_plan(plan_key)
		if plan == null:
			errors.append("missing SettlementPlan %s" % plan_key)
			continue
		record.plans[plan_key] = plan.summary()
		_check_diagnostics(plan_key, plan.diagnostics, errors)
		for reservation_value in plan.industrial_reservations:
			var reservation: Dictionary = reservation_value
			var angle := absf(wrapf((reservation.tangent as Vector2).angle(),
				-PI * 0.5, PI * 0.5))
			var axis_deviation := minf(angle, absf(PI * 0.5 - angle))
			rotated_targets.append({"reservation": reservation,
				"axis_deviation": axis_deviation})
	for key_value in (record.generic as Dictionary).keys():
		_check_diagnostics(str(key_value), (record.generic as Dictionary)[key_value],
			errors)
	rotated_targets.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.axis_deviation) > float(b.axis_deviation))
	for i in mini(3, rotated_targets.size()):
		var reservation: Dictionary = (rotated_targets[i] as Dictionary).reservation
		await _capture(camera, _poly_center(reservation.footprint_poly), 2.15,
			"/tmp/poe_compound_rotated_%d.png" % (i + 1))
	if rotated_targets.size() < 3:
		errors.append("fewer than three rotated industry reservations available")
	var file := FileAccess.open("/tmp/poe_compound_metrics.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(record, "  "))
	file.close()
	MapStyle.set_midcentury(false)
	if not errors.is_empty():
		push_error("midcentury_industry_compound_shot: %s" % "; ".join(errors))
	get_tree().quit(0 if errors.is_empty() else 2)

func _check_diagnostics(label: String, diagnostics: Dictionary,
		errors: PackedStringArray) -> void:
	for key in ZERO_DIAGNOSTICS:
		if not diagnostics.has(key):
			continue
		if float(diagnostics[key]) != 0.0:
			errors.append("%s %s=%s" % [label, key, diagnostics[key]])
	var axis_difference := float(diagnostics.get(
		"max_principal_axis_difference_degrees", 0.0))
	if axis_difference > 0.05:
		errors.append("%s principal-axis difference %.5f degrees" % [
			label, axis_difference])

func _capture(camera: Camera2D, position: Vector2, zoom: float,
		path: String) -> void:
	camera.position = position
	camera.zoom = Vector2(zoom, zoom)
	if "_target_zoom" in camera:
		camera.set("_target_zoom", camera.zoom)
	for _i in 18:
		await get_tree().process_frame
	RenderingServer.force_draw()
	var image := get_viewport().get_texture().get_image()
	var size := Vector2i(mini(640, image.get_width()), mini(480, image.get_height()))
	var origin := Vector2i((image.get_width() - size.x) / 2,
		(image.get_height() - size.y) / 2)
	image.get_region(Rect2i(origin, size)).save_png(path)
	print("[INDUSTRY COMPOUND] captured %s" % path)

func _poly_center(poly: PackedVector2Array) -> Vector2:
	var center := Vector2.ZERO
	for point in poly:
		center += point
	return center / maxf(1.0, float(poly.size()))
