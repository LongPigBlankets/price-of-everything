extends Node
## Hunts the reported "map snaps right after the highlight animation ends". Enters a step
## that recentres the camera, then logs per-frame camera position/zoom and reports the
## largest single-frame jump and when it happened relative to the 1s settle.
var _t := 0.0
var _built := false
var _armed := false
var _t0 := 0.0
var _last := Vector2.ZERO
var _last_zoom := 0.0
var _worst := 0.0
var _worst_t := 0.0
var _worst_zoom := ""
var _done := false
func _process(delta: float) -> void:
	if _done: return
	_t += delta
	var cam := get_viewport().get_camera_2d()
	if not _built:
		var scene := get_tree().current_scene
		if scene != null and bool(scene.get("build_complete")) and cam != null:
			_built = true
			cam.set("edge_pan_enabled", false)
			_t = 0.0
		return
	if not _armed and _t > 2.0:
		_armed = true
		_t0 = _t
		_last = cam.position
		_last_zoom = cam.zoom.x
		Tutorial._enter(Tutorial._index_of_id("view_shipment"))
		print("[SNAP] entered step; watching for per-frame jumps")
		return
	if _armed:
		var d := _last.distance_to(cam.position)
		if d > 0.5:
			print("[SNAP]   t=%.2fs  move=%7.2fpx  zoom %.4f->%.4f" % [_t - _t0, d, _last_zoom, cam.zoom.x])
		if d > _worst:
			_worst = d
			_worst_t = _t - _t0
			_worst_zoom = "%.4f->%.4f" % [_last_zoom, cam.zoom.x]
		_last = cam.position
		_last_zoom = cam.zoom.x
		if _t - _t0 > 3.0:
			_done = true
			print("[SNAP] worst single-frame move = %.2f px at t=%.2fs after entry (zoom %s)"
				% [_worst, _worst_t, _worst_zoom])
			print("[SNAP] reveal duration is 1.00s; a jump at ~1.0s is the settle ending")
			get_tree().quit(0)
