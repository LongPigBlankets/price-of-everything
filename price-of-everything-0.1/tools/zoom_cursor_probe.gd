extends Node2D
## Verifies scroll-zoom anchors on the CURSOR: the world point under the mouse must stay
## put across a zoom step. Previously _adjust_zoom only changed the zoom, so the camera
## drifted to screen centre and whatever you pointed at slid away.
var _wm
var _fails := 0
func _ready() -> void:
	_wm = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_wm)
	await _settle(120)
	var cam := get_viewport().get_camera_2d()
	cam.set("edge_pan_enabled", false)
	var vp := get_viewport_rect().size
	# Zoom in off the minimum first: at full zoom-out the map is smaller than the viewport,
	# so _clamp_to_bounds force-centres the camera and NO anchor can hold. That limit is
	# inherent to the clamp, not to the cursor maths — test where the player actually is.
	for _i in 6:
		cam.call("_adjust_zoom", 1.0, false)
		await _settle(4)
	await _settle(20)
	# Probe an off-centre cursor so a centre-anchored zoom would visibly drift.
	for probe in [Vector2(vp.x * 0.25, vp.y * 0.30), Vector2(vp.x * 0.80, vp.y * 0.70)]:
		Input.warp_mouse(probe)
		await _settle(3)
		var z0: float = cam.zoom.x
		var world_before: Vector2 = cam.position + (probe - vp * 0.5) / z0
		cam.call("_adjust_zoom", 1.0)          # one scroll-up step, cursor-anchored
		await _settle(60)                      # let the smoothing settle on the new zoom
		var z1: float = cam.zoom.x
		var world_after: Vector2 = cam.position + (probe - vp * 0.5) / z1
		var drift := world_before.distance_to(world_after)
		_check("cursor at (%.0f,%.0f): zoom %.2f→%.2f, world point drift %.2fpx" % [probe.x, probe.y, z0, z1, drift],
			drift < 1.0)
	# Keyboard zoom must stay centre-anchored (mouse position irrelevant).
	Input.warp_mouse(Vector2(vp.x * 0.9, vp.y * 0.1))
	await _settle(3)
	var pos_before: Vector2 = cam.position
	cam.call("_adjust_zoom", -1.0, false)
	await _settle(60)
	_check("keyboard zoom does not pan (moved %.2fpx)" % pos_before.distance_to(cam.position),
		pos_before.distance_to(cam.position) < 0.01)
	print("==== ZOOM CURSOR %s ====" % ("PASS" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit(0 if _fails == 0 else 1)
func _check(msg: String, ok: bool) -> void:
	if not ok: _fails += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", msg])
func _settle(n: int) -> void:
	for _i in n: await get_tree().process_frame
