extends Node
## Why is the map editor slow? Measures the two phases a person actually feels — the wait
## before the editor responds, and the frame cadence afterwards — and attributes the second
## one by toggling layers on and off within a SINGLE run.
##
##   <godot> --path . res://tools/map_editor/editor_perf_probe.tscn --quit-after 600000
##
## WINDOWED. A headless run draws nothing, and drawing is the thing under suspicion.
##
## Runs against the REAL active document, deliberately: scratch mode opens an empty one, and
## an empty document is exactly the case that is fast. It never clicks and never saves — the
## md5 it prints at both ends is the proof it left the document alone.
##
## A/B WITHIN ONE RUN, ALTERNATING. Two adjacent runs are not an A/B (the load-frame lesson):
## caches, the shader compiler and the OS all move between processes. Each configuration is
## measured, reverted, and measured again.

const AuthoredMap := preload("res://scripts/authored_map.gd")

## Frames per measured window. Enough to average over, few enough that a 3 s frame does not
## make the probe itself take an hour.
const WINDOW := 24
## Give up on the editor after this many frames rather than hanging forever.
const MAX_BOOT_FRAMES := 4000

## Where the closing captures go, and the tile they frame — a Stoneshore tile with woods,
## fabric and roads on it, so a capture shows every kind of record the preview draws.
const SHOT_PREFIX := "/tmp/poe_editor_perf"
const SHOT_TILE := "tile_5_10"

var _editor: Node = null


func _ready() -> void:
	get_window().size = Vector2i(1600, 1000)
	var doc_path := ProjectSettings.globalize_path(AuthoredMap.active_path())
	print("[PERF] document: %s" % AuthoredMap.active_name())
	print("[PERF] md5 before: %s" % FileAccess.get_md5(doc_path))

	var packed := load("res://tools/map_editor/map_editor.tscn") as PackedScene
	var t_start := Time.get_ticks_msec()
	_editor = packed.instantiate()
	add_child(_editor)
	print("[PERF] instantiate+add_child returned after %d ms" % (Time.get_ticks_msec() - t_start))

	# PHASE 1 — the wait. Frame deltas while the editor boots, so a long freeze is
	# distinguishable from many merely-slow frames.
	var frames := 0
	var slowest := 0
	var previous := Time.get_ticks_msec()
	while frames < MAX_BOOT_FRAMES and not bool(_editor.call("is_ready_to_edit")):
		await get_tree().process_frame
		var delta := Time.get_ticks_msec() - previous
		previous = Time.get_ticks_msec()
		slowest = maxi(slowest, delta)
		frames += 1
		if delta > 250:
			print("[PERF]   boot frame %d took %d ms" % [frames, delta])
	var boot_ms := Time.get_ticks_msec() - t_start
	print("[PERF] READY after %.1f s, %d frames (slowest single frame %d ms)"
		% [boot_ms / 1000.0, frames, slowest])

	_report_document()

	# PHASE 2 — the cadence, attributed. Each label is measured twice, in a different
	# neighbourhood of the run, so a one-off (a shader compile, a GC) cannot masquerade as
	# the answer.
	print("[PERF] --- steady state, %d frames per window ---" % WINDOW)
	# Each configuration is a one-argument callable: true installs it, false reverts. Written
	# as lambdas rather than `bind`, which appends its argument and so called these with the
	# install flag first — the miscall that cost the first run's attribution windows.
	var fabric_off := func(install: bool) -> void: _set_editor_fabric(install)
	var no_forests := func(install: bool) -> void: _strip("forests", install)
	var no_content := func(install: bool) -> void: _strip("forests,specials,decor,parks,plazas", install)
	await _measure("everything on")
	await _measure("editor fabric preview OFF", fabric_off)
	await _measure("everything on (repeat)")
	await _measure("editor fabric preview OFF (repeat)", fabric_off)
	await _measure("forests removed from the document", no_forests)
	await _measure("forests+specials+decor+ground removed", no_content)
	await _measure("everything on (final)")
	# The camera the owner navigates with: at the far end of the zoom range the whole map is
	# in view, which is where culling stops helping and the far-zoom stand-in takes over.
	# A NUMBER IS NOT A PICTURE. Culling and the far-zoom stand-in both change what is drawn,
	# so the run ends by capturing what the editor actually looks like at each zoom — a fast
	# editor that had quietly stopped drawing half the map would score beautifully here.
	await _shoot("working", 0.9)
	var camera: Camera2D = _editor.call("camera")
	if camera != null:
		camera.zoom = Vector2(0.12, 0.12)
		await get_tree().process_frame
		await _measure("whole map in view (zoom 0.12)")
	await _shoot("far", 0.12)
	print("[PERF] md5 after:  %s" % FileAccess.get_md5(doc_path))
	get_tree().quit(0)


## Frame the editor on a wooded stretch of the map at `zoom` and write a PNG. `force_draw`
## rather than awaiting `frame_post_draw`: an occluded window never presents, and every
## capture then comes back as the same stale frame.
func _shoot(label: String, zoom: float) -> void:
	var camera: Camera2D = _editor.call("camera")
	if camera == null:
		return
	if not bool(_editor.call("focus_tile", SHOT_TILE, zoom)):
		print("[PERF] cannot frame %s for the %s capture" % [SHOT_TILE, label])
		return
	for _i in 12:
		await get_tree().process_frame
	RenderingServer.force_draw()
	var path := "%s_%s.png" % [SHOT_PREFIX, label]
	var problem := get_viewport().get_texture().get_image().save_png(path)
	print("[PERF] %s (%s)" % [path if problem == OK else "capture FAILED", label])


## Measure WINDOW frames under `apply`, then put everything back. `apply` takes a bool: true
## to install the configuration, false to revert it.
func _measure(label: String, apply: Callable = Callable()) -> void:
	if apply.is_valid():
		apply.call(true)
	# One settling frame so the change is in effect before the clock starts.
	await get_tree().process_frame
	var worst := 0
	var total := 0
	var previous := Time.get_ticks_msec()
	for _i in WINDOW:
		await get_tree().process_frame
		var delta := Time.get_ticks_msec() - previous
		previous = Time.get_ticks_msec()
		total += delta
		worst = maxi(worst, delta)
	var mean := float(total) / float(WINDOW)
	print("[PERF] %-38s mean %6.1f ms/frame  (%.1f fps)  worst %d ms"
		% [label, mean, 1000.0 / maxf(mean, 0.001), worst])
	if apply.is_valid():
		apply.call(false)


## The editor's own preview layers (`MapEditorFabric`, ground and standing).
func _set_editor_fabric(off: bool) -> void:
	for node_name in ["MapEditorFabric", "MapEditorFabricGround"]:
		var node := _find(get_tree().root, node_name)
		if node != null:
			node.set_process(not off)
			(node as CanvasItem).visible = not off


## Temporarily lift record lists out of the WORKING document (never saved), to price them.
var _stashed: Dictionary = {}


func _strip(fields: String, off: bool = true) -> void:
	var document: Dictionary = _editor.call("document").call("data")
	var settlements: Dictionary = document.get("settlements", {})
	for key in settlements.keys():
		var settlement: Dictionary = settlements[key]
		for field in fields.split(",", false):
			var slot := "%s|%s" % [str(key), str(field)]
			if off:
				_stashed[slot] = settlement.get(str(field), [])
				settlement[str(field)] = []
			elif _stashed.has(slot):
				settlement[str(field)] = _stashed[slot]
	if not off:
		_stashed.clear()
	# Tell the editor the document changed. Without this the preview layers — which now redraw
	# on the stamp rather than every frame — keep showing the picture from before the strip,
	# and the window measures a stale drawing instead of the configuration it names.
	_editor.call("_repaint")


func _report_document() -> void:
	var document: Dictionary = _editor.call("document").call("data")
	var settlements: Dictionary = document.get("settlements", {})
	var counts: Dictionary = {}
	for key in settlements.keys():
		var settlement: Dictionary = settlements[key]
		for field in ["roads", "specials", "decor", "parks", "plazas", "forests", "trees", "zones"]:
			var value: Variant = settlement.get(field, [])
			if typeof(value) == TYPE_ARRAY:
				counts[field] = int(counts.get(field, 0)) + (value as Array).size()
	var camera: Camera2D = _editor.call("camera")
	print("[PERF] document holds %s   (camera zoom %.3f)"
		% [str(counts), camera.zoom.x if camera != null else -1.0])


func _find(node: Node, node_name: String) -> Node:
	if node.name == node_name:
		return node
	for child in node.get_children():
		var found := _find(child, node_name)
		if found != null:
			return found
	return null
