extends Node
## Dev tool: find what makes the map judder while the camera MOVES, per zoom level. Judder is a
## moving-camera symptom and a VARIANCE symptom, so this records the frame-time spread and the
## hitch count, not just an average — a steady 60ms reads as slow, a 20ms mean with 90ms spikes
## reads as juddery, and only the second one is what the eye calls judder.
##
## Hypotheses killed here, so nobody re-runs them:
##  1. hill_visuals flapping between its vector and baked-texture LOD at the VECTOR_CAP crossover.
##     MEASURED: only ~376 contour polys are on screen even fully zoomed out, against a cap of
##     450 — the texture LOD never engages on this map and the mode never flips, in either
##     direction across the whole zoom range.
##  2. Attribution by hiding one layer at a time with a free-running camera. MEASURED: the camera
##     panned monotonically and walked off the map, so every later reading was cheaper regardless
##     of the layer hidden (savings summed to 322ms against an 84ms baseline). The camera must be
##     re-centred per sample and oscillate, and the baseline must be re-measured between layers.
##   <godot> --path . res://tools/lod_judder_probe.tscn --quit-after 6000

const ZOOMS := [0.30, 0.50, 0.70, 0.90, 1.10, 1.40]
const WARM := 10
const SAMPLES := 48
const PAN := 22.0            # px/frame, oscillating — enough to force a recull every frame

var _cam: Camera2D
var _game: Node
var _home := Vector2.ZERO


func _ready() -> void:
	_game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_game)
	await _settle(40)
	_cam = get_viewport().get_camera_2d()
	if _cam == null:
		push_error("no camera")
		get_tree().quit(1)
		return
	_home = _cam.position

	print("PANNING FRAME TIME (ms) per zoom — median / p95 / worst, and hitches (>1.5x median)")
	var base: Dictionary = {}
	for z in ZOOMS:
		var r: Dictionary = await _measure(z)
		base[z] = r
		print("  zoom %.2f   median %6.2f   p95 %6.2f   worst %6.2f   hitches %2d/%d"
			% [z, r["p50"], r["p95"], r["max"], r["hitch"], SAMPLES])

	# Attribution at the WORST zoom by median. Re-measure the baseline between every layer so
	# drift shows up as a moving baseline instead of being misread as a saving.
	var worst_z: float = ZOOMS[0]
	for z in ZOOMS:
		if float((base[z] as Dictionary)["p50"]) > float((base[worst_z] as Dictionary)["p50"]):
			worst_z = z
	print("")
	print("ATTRIBUTION at zoom %.2f — each layer hidden in turn, baseline re-measured each time:"
		% worst_z)
	var layers: Dictionary = _map_layers()
	for lname in layers:
		var node: CanvasItem = layers[lname]
		if not node.visible:
			continue
		var before: Dictionary = await _measure(worst_z)
		node.visible = false
		var off: Dictionary = await _measure(worst_z)
		node.visible = true
		print("    %-26s %6.2f -> %6.2f ms median  (saves %6.2f)"
			% [lname, before["p50"], off["p50"], float(before["p50"]) - float(off["p50"])])
	get_tree().quit(0)


func _map_layers() -> Dictionary:
	var out: Dictionary = {}
	for c in _game.get_children():
		if c is Camera2D or not (c is CanvasItem):
			continue
		var s: Script = c.get_script() as Script
		var label: String = str(c.name)
		if s != null:
			label = str(s.resource_path).get_file().get_basename()
		out[label] = c
	return out


## Camera re-centred every sample and oscillated about `_home`, so the view covers the same
## ground for every reading and no measurement can drift cheaper than the one before it.
func _measure(z: float) -> Dictionary:
	for i in range(WARM):
		_drive(z, i)
		await get_tree().process_frame
	var ms: Array = []
	for i in range(SAMPLES):
		_drive(z, WARM + i)
		var t0 := Time.get_ticks_usec()
		await get_tree().process_frame
		ms.append(float(Time.get_ticks_usec() - t0) / 1000.0)
	ms.sort()
	var p50: float = float(ms[int(ms.size() * 0.50)])
	var p95: float = float(ms[int(ms.size() * 0.95)])
	var hitch := 0
	for v in ms:
		if float(v) > p50 * 1.5:
			hitch += 1
	return {"p50": p50, "p95": p95, "max": float(ms[ms.size() - 1]), "hitch": hitch}


func _drive(z: float, i: int) -> void:
	_cam.zoom = Vector2.ONE * z
	_cam.set("_target_zoom", Vector2.ONE * z)
	# Oscillate, don't travel: a triangle wave keeps the camera over the same ground while still
	# moving every frame, which is what forces the per-frame reculls.
	var phase: float = float(i % 24) / 24.0
	var off: float = (phase if phase < 0.5 else 1.0 - phase) * 4.0 - 1.0
	_cam.position = _home + Vector2(off * PAN * 6.0, off * PAN * 2.0)


func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
