extends Node
## Which layer owns the draw calls?  (parented to the root by tools/pan_profile.gd, DRAW_SWEEP=1)
##
## pan_profile_watcher answers "where does the frame go" and gets: the renderer, submitting
## ~5,700 draw calls, on a camera that is not even moving. This answers the next question --
## WHOSE draw calls -- and it has to do it inside ONE run, because the obvious experiment (one
## process per hidden layer) was tried and is worthless: each run's camera walks a different
## path, so the run-to-run noise is larger than most of the layers being measured.
##
## So: park the camera, and sweep. Everything else is identical between measurements -- same
## view, same world, same process -- so the difference IS the node.
##
## TWO MODES, because hide-one and hide-all-so-far do not answer the same question:
##
##   peel (default)  hide each node in turn and NEVER put it back. Cumulative, monotone, and
##                   the last number is the FLOOR -- what the frame still costs with every
##                   sweepable node gone. Hide-one sums to less than the total and leaves you
##                   guessing whether the shortfall is batching or a node you failed to hide;
##                   peel shows the shortfall directly, as the floor.
##   one             hide, measure, restore. Each node's cost with all the others present.
##
## Draw calls are the column to trust. Wall time on a single step is noisy at 10 fps, and the
## GPU overlaps the CPU, so a node's ms is only meaningful once its draws are large.
##
##   DRAW_SWEEP=1 <godot> --path . res://tools/pan_profile.tscn --quit-after 200000
##
## Env knobs:
##   PAN_ZOOM      fraction from zoom_min to zoom_max (default 1.0 = max zoom in)
##   SWEEP_MODE    "peel" (default) or "one"
##   SWEEP_FRAMES  frames measured per node (default 12)
##   SWEEP_WARM    frames to settle before the baseline (default 40) -- the first paint after
##                 the reveal is an outlier and would poison every delta measured against it
##   SWEEP_DEPTH   how deep under the scene root to sweep (default 3)
##   SWEEP_TILE    tile id to centre on first, e.g. tile_5_10 (default: wherever the game left
##                 the camera)
##   PAN_NOROADS=1 RoadNetwork.roads_visible = false before the sweep starts. RoadNetworkVisuals
##                 re-asserts its own visibility every frame, so the sweep cannot hide it and
##                 reports it as free; this is the switch that actually turns it off, and with
##                 it the sweep attributes what is left underneath.

const SETTLE := 3

var _cam: Camera2D = null
var _no_cam := 0
var _armed := false
var _peel := true

var _targets: Array = []       # [{node, path}]
var _idx := -2                 # -2 = warm-up, -1 = baseline, >=0 = a target
var _phase := 0
var _frames := 12
var _warm := 40
var _hidden: Node = null
var _escaped: Array = []       # nodes that put themselves back on screen mid-measurement

var _acc_calls := 0.0
var _acc_wall := 0.0
var _acc_rcpu := 0.0
var _acc_rgpu := 0.0
var _n := 0

var _base := {}
var _prev := {}
var _rows: Array = []
var _t_last := 0


func _ready() -> void:
	process_priority = 10000
	_frames = int(_env("SWEEP_FRAMES", "12"))
	_warm = int(_env("SWEEP_WARM", "40"))
	_peel = _env("SWEEP_MODE", "peel") != "one"
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	print("SWEEP watcher up (mode=%s)" % ("peel" if _peel else "one"))


func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else d


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var wall := float(now - _t_last) / 1000.0
	_t_last = now

	var scene := get_tree().current_scene
	if not _armed:
		if scene == null or scene.get("build_complete") == null or not bool(scene.get("build_complete")):
			return
		_arm(scene)
		return

	_phase += 1
	if _idx == -2:
		# Warm-up: no measuring, just let the first-paint frames pass.
		if _phase >= _warm:
			_idx = -1
			_reset_acc()
		return
	if _phase <= SETTLE:
		return
	# A node that re-shows itself (a layer whose _process owns its own visibility) would be
	# measured as costing nothing. Catch it and say so rather than reporting a quiet zero.
	if _hidden != null and is_instance_valid(_hidden) and bool(_hidden.get("visible")):
		if not _escaped.has(str(_hidden.get_path())):
			_escaped.append(str(_hidden.get_path()))
	var vp := get_viewport().get_viewport_rid()
	_acc_calls += float(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_acc_wall += wall
	_acc_rcpu += RenderingServer.viewport_get_measured_render_time_cpu(vp)
	_acc_rgpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
	_n += 1
	if _n < _frames:
		return
	_close_step()


func _arm(scene: Node) -> void:
	_cam = get_viewport().get_camera_2d()
	if _cam == null:
		_no_cam += 1
		if _no_cam > 600:
			print("SWEEP giving up: no current Camera2D")
			get_tree().quit(1)
		return
	if scene.has_method("reveal_for_play"):
		scene.call("reveal_for_play")
	for c in get_tree().root.get_children():
		if c is LoadingScreen:
			(c as CanvasLayer).visible = false
	var tile := _env("SWEEP_TILE", "")
	if tile != "" and scene.has_method("_focus_camera_on_tile"):
		scene.call("_focus_camera_on_tile", tile)
	var zmin: float = _cam.call("_effective_zoom_min") if _cam.has_method("_effective_zoom_min") else float(_cam.get("zoom_min"))
	var zmax := float(_cam.get("zoom_max"))
	var z: float = lerpf(zmin, zmax, float(_env("PAN_ZOOM", "1.0")))
	_cam.zoom = Vector2.ONE * z
	_cam.set("_target_zoom", _cam.zoom)
	_cam.set("input_blocked", true)   # nothing may move the camera during a sweep
	if OS.get_environment("PAN_NOROADS") != "":
		RoadNetwork.roads_visible = false
		print("SWEEP roads off (RoadNetwork.roads_visible = false)")
	_collect(scene, 0, int(_env("SWEEP_DEPTH", "3")))
	_armed = true
	_phase = 0
	print("SWEEP zoom %.3f at %s, viewport %s, %d nodes, %d frames each" %
		[z, str(_cam.position), str(get_viewport().get_visible_rect().size),
		_targets.size(), _frames])


## Every visible canvas node down to SWEEP_DEPTH. Hidden ones are skipped: hiding them again
## measures nothing, and they are the bulk of the tree (every closed HUD panel).
func _collect(node: Node, depth: int, max_depth: int) -> void:
	if depth > max_depth:
		return
	for c in node.get_children():
		if (c is CanvasItem or c is CanvasLayer) and bool(c.get("visible")):
			_targets.append({"node": c, "path": str(c.get_path())})
			_collect(c, depth + 1, max_depth)


func _reset_acc() -> void:
	_acc_calls = 0.0
	_acc_wall = 0.0
	_acc_rcpu = 0.0
	_acc_rgpu = 0.0
	_n = 0
	_phase = 0


func _close_step() -> void:
	var f := float(_frames)
	var rec := {
		"calls": _acc_calls / f, "wall": _acc_wall / f,
		"rcpu": _acc_rcpu / f, "rgpu": _acc_rgpu / f,
	}
	if _idx < 0:
		_base = rec
		_prev = rec
		print("SWEEP baseline: %.0f draw calls, %.2f ms/f (rcpu %.2f rgpu %.2f)" %
			[rec.calls, rec.wall, rec.rcpu, rec.rgpu])
	else:
		var against: Dictionary = _prev if _peel else _base
		_rows.append({
			"path": str(_targets[_idx].path),
			"calls": against.calls - rec.calls,
			"wall": against.wall - rec.wall,
			"rcpu": against.rcpu - rec.rcpu,
			"rgpu": against.rgpu - rec.rgpu,
			"left": rec.calls,
			"left_ms": rec.wall,
		})
		if _peel:
			_prev = rec           # keep it hidden; the next node is measured against this
		elif _hidden != null and is_instance_valid(_hidden):
			_hidden.set("visible", true)
		_hidden = null
	_reset_acc()

	_idx += 1
	while _idx < _targets.size():
		var node: Node = _targets[_idx].node
		# In peel mode a node under an already-hidden parent is redundant: its own flag is
		# still true but it is drawing nothing, so skip it rather than credit it with zero.
		if is_instance_valid(node) and bool(node.get("visible")) \
				and (not _peel or (node is CanvasItem and (node as CanvasItem).is_visible_in_tree()) or node is CanvasLayer):
			node.set("visible", false)
			_hidden = node
			return
		_idx += 1
	_report()
	get_tree().quit(0)


func _report() -> void:
	if not _peel:
		_rows.sort_custom(func(a, b): return a.calls > b.calls)
	print("\nSWEEP ===== baseline %.0f draw calls, %.2f ms/frame (%.1f fps) =====" %
		[_base.calls, _base.wall, 1000.0 / maxf(0.001, _base.wall)])
	print("SWEEP   mode=%s -- %s" % [
		"peel" if _peel else "one",
		"cumulative: each row is hidden and STAYS hidden" if _peel else "each row hidden alone"])
	print("SWEEP   %9s %7s %8s %9s %9s  %s" %
		["draws", "share", "wall ms", "left", "left ms", "node"])
	for r in _rows:
		if absf(r.calls) < 1.0 and absf(r.wall) < 0.5:
			continue
		print("SWEEP   %9.0f %6.1f%% %8.2f %9.0f %9.2f  %s" %
			[r.calls, 100.0 * r.calls / maxf(1.0, _base.calls), r.wall, r.left, r.left_ms, r.path])
	if _peel and not _rows.is_empty():
		var last: Dictionary = _rows[_rows.size() - 1]
		print("SWEEP   FLOOR: %.0f draw calls, %.2f ms/frame with every swept node hidden" %
			[last.left, last.left_ms])
	if not _escaped.is_empty():
		print("SWEEP   NOT ACTUALLY HIDDEN (put themselves back): %s" % ", ".join(_escaped))
