extends Node
## Dev tool: hill_visuals costs ~82 of the map's ~89ms panning frame (measured by
## lod_judder_probe), and — the odd part — hiding it and showing it again leaves it CHEAP
## (~10ms total frame) for the rest of the run. Something about the visibility toggle changes
## which path it draws. This dumps its state either side of the toggle so the difference is a
## fact rather than a theory.
##   <godot> --path . res://tools/lod_state_probe.tscn --quit-after 3000

var _cam: Camera2D
var _hv: Node
var _home := Vector2.ZERO


func _ready() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(40)
	_cam = get_viewport().get_camera_2d()
	_hv = get_tree().get_first_node_in_group("hill_visuals")
	if _cam == null or _hv == null:
		push_error("cam=%s hv=%s" % [_cam, _hv])
		get_tree().quit(1)
		return
	_home = _cam.position

	print("BEFORE  %s  frame %.2f ms" % [_state(), await _ms()])
	_hv.visible = false
	await _settle(20)
	print("HIDDEN  %s  frame %.2f ms" % [_state(), await _ms()])
	_hv.visible = true
	await _settle(20)
	print("AFTER   %s  frame %.2f ms" % [_state(), await _ms()])
	get_tree().quit(0)


func _state() -> String:
	return "mode=%s meshes_warm=%s mesh_cache=%d baked_tex=%s polys=%d" % [
		("TEXTURE" if int(_hv.get("_mode")) == 0 else "VECTOR"),
		_hv.get("_meshes_warm"), (_hv.get("_mesh_cache") as Dictionary).size(),
		_hv.get("_baked_tex") != null, (_hv.get("_polys") as Array).size()]


func _ms() -> float:
	for i in range(10):
		_drive(i)
		await get_tree().process_frame
	var total := 0.0
	for i in range(30):
		_drive(10 + i)
		var t0 := Time.get_ticks_usec()
		await get_tree().process_frame
		total += float(Time.get_ticks_usec() - t0) / 1000.0
	return total / 30.0


func _drive(i: int) -> void:
	_cam.zoom = Vector2.ONE * 0.30
	_cam.set("_target_zoom", Vector2.ONE * 0.30)
	var phase: float = float(i % 24) / 24.0
	var off: float = (phase if phase < 0.5 else 1.0 - phase) * 4.0 - 1.0
	_cam.position = _home + Vector2(off * 132.0, off * 44.0)


func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
