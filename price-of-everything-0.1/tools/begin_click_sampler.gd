extends Node
## Times every frame either side of the Begin click. See begin_click_probe.gd.

const POST_SECS := 20.0         # how long to keep timing after the click
const BUDGET_MS := 33.0         # one frame at 30 fps — the film's budget, and the map's
const BAD_MS := 100.0           # a gap a player would call a freeze

var screen: Node = null

var _t0 := 0
var _last := 0
var _clicked_at := 0
var _shot_dir := ""
var _gaps: Array[int] = []
## Per frame, alongside the gap: how much of it the SCRIPT owned, and how much the renderer
## was asked to do. A frame that is long while TIME_PROCESS is short is not our code — it is
## the renderer, and no amount of baking GDScript work will touch it.
var _proc_ms: Array[float] = []
var _draws: Array[int] = []
var _objs: Array[int] = []
## How many times each CanvasItem actually REDREW after the click. CanvasItem emits `draw`
## whenever it re-runs _draw, so this needs no cooperation from the nodes and catches every
## one of them. A node redrawing once is doing its job; a node redrawing every frame on a map
## nobody is touching is the bill.
var _redraws: Dictionary = {}
var _hooked := false
var _redraw_sec: Array[int] = []      # redraws in each second after the click
var _cam_sec: Array[int] = []         # camera-rect CHANGES in each second
var _tick := 0
var _tick_redraws := 0
var _tick_cam := 0
var _last_cam := Rect2()
var _worst := 0
var _worst_at := 0
var _done := false
var _pre_shot := false


func _ready() -> void:
	_t0 = Time.get_ticks_msec()
	_last = _t0
	_shot_dir = OS.get_environment("BEGIN_SHOT")


func _process(_d: float) -> void:
	var now := Time.get_ticks_msec()
	var gap := now - _last
	_last = now

	if _clicked_at > 0:
		_gaps.append(gap)
		_proc_ms.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		_draws.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		_objs.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)))
		# Does the CAMERA ever stop? The heavy layers redraw on an exact Rect2 compare of the
		# visible world, so a view that never settles is a redraw that never stops.
		var cam := get_viewport().get_camera_2d()
		if cam != null:
			var vr := Rect2(cam.get_screen_center_position()
				- get_viewport().get_visible_rect().size * 0.5 * cam.zoom,
				get_viewport().get_visible_rect().size * cam.zoom)
			if vr != _last_cam:
				_last_cam = vr
				_tick_cam += 1
		_tick += gap
		if _tick >= 1000:
			_redraw_sec.append(_tick_redraws)
			_cam_sec.append(_tick_cam)
			_tick = 0
			_tick_redraws = 0
			_tick_cam = 0
		if gap > _worst:
			_worst = gap
			_worst_at = now - _clicked_at
		if not _done and now - _clicked_at >= int(POST_SECS * 1000.0):
			_report(now)
		return

	# Waiting for the button. It is a child of the plate now, so reach it through the screen.
	var btn: Object = screen.get("_begin") if is_instance_valid(screen) else null
	if btn == null or not (btn is Button):
		return
	var b := btn as Button
	if not b.visible or b.modulate.a < 0.9:
		return

	if _shot_dir != "" and not _pre_shot:
		# One frame with the button fully up, before anything is clicked.
		_pre_shot = true
		get_viewport().get_texture().get_image().save_png(
			"%s/begin_panel.png" % _shot_dir)
		print("BEGIN shot: panel with the button, at t+%d ms" % (now - _t0))
		return

	_hook_draws()
	# EDGE PANNING OFF, or this measures the harness rather than the game. The camera
	# edge-pans when the pointer is within 30 px of a window edge, and an automated window has
	# the cursor wherever it happens to be — usually outside it. That panned the camera 4-7
	# times a SECOND for the full twenty, repainting every streaming layer each time, and made
	# the first readings of this probe unrepeatable. A player sitting still is the case worth
	# measuring; a player panning is a different question.
	var cam := get_viewport().get_camera_2d()
	if cam != null and "edge_pan_enabled" in cam:
		cam.set("edge_pan_enabled", false)
		print("CLICK edge pan disabled for the measurement")
	print("BEGIN button offered at t+%d ms — clicking" % (now - _t0))
	_clicked_at = now
	_last = Time.get_ticks_msec()
	b.pressed.emit()


## Count every CanvasItem redraw from here on.
func _hook_draws() -> void:
	if _hooked:
		return
	_hooked = true
	var scene := get_tree().current_scene
	if scene == null:
		return
	var stack: Array[Node] = [scene]
	var n := 0
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for c in node.get_children():
			stack.append(c)
		if node is CanvasItem:
			var key := "%s (%s)" % [node.name, node.get_class()]
			node.draw.connect(func() -> void:
				_redraws[key] = int(_redraws.get(key, 0)) + 1
				_tick_redraws += 1)
			n += 1
	print("CLICK hooked %d CanvasItems" % n)


func _report(now: int) -> void:
	_done = true
	var over_budget := 0
	var over_bad := 0
	var total := 0
	for g in _gaps:
		total += g
		if float(g) > BUDGET_MS:
			over_budget += 1
		if float(g) > BAD_MS:
			over_bad += 1
	var n := maxi(1, _gaps.size())
	print("CLICK ==== %d frames over %.1f s after the click ====" % [_gaps.size(), float(total) / 1000.0])
	print("CLICK mean frame %.1f ms, worst %d ms at t+%d ms after the click"
		% [float(total) / float(n), _worst, _worst_at])
	print("CLICK over %d ms budget: %d frames (%.1f%%)"
		% [int(BUDGET_MS), over_budget, 100.0 * float(over_budget) / float(n)])
	print("CLICK over %d ms (a visible freeze): %d frames" % [int(BAD_MS), over_bad])
	# The five worst, with when they happened — one 800 ms stall and forty 40 ms frames are
	# very different complaints, and the mean hides which one this is.
	var idx: Array[int] = []
	for i in _gaps.size():
		idx.append(i)
	idx.sort_custom(func(a: int, b: int) -> bool: return _gaps[a] > _gaps[b])
	var t := 0
	var at: Array[int] = []
	for g in _gaps:
		at.append(t)
		t += g
	for i in mini(5, idx.size()):
		print("CLICK   %2d. %4d ms at t+%5d ms" % [i + 1, _gaps[idx[i]], at[idx[i]]])
	# Per-second frame counts: a stall that CLEARS is a different complaint from a map that
	# just runs slowly, and only the shape over time separates them.
	# Second by second: frames, mean frame time, how much of it was SCRIPT, and what the
	# renderer was handed. This is the table that says whether a ramp is ours to fix.
	print("CLICK  sec   frames   frame_ms   script_ms   draw_calls   objects")
	var acc := 0
	var cnt := 0
	var f_sum := 0
	var p_sum := 0.0
	var d_last := 0
	var o_last := 0
	var sec := 0
	for i in _gaps.size():
		acc += _gaps[i]
		cnt += 1
		f_sum += _gaps[i]
		p_sum += _proc_ms[i]
		d_last = _draws[i]
		o_last = _objs[i]
		if acc >= 1000:
			print("CLICK  %3d   %6d   %8.1f   %9.1f   %10d   %7d"
				% [sec, cnt, float(f_sum) / float(cnt), p_sum / float(cnt), d_last, o_last])
			sec += 1
			acc = 0
			cnt = 0
			f_sum = 0
			p_sum = 0.0
	var names := _redraws.keys()
	names.sort_custom(func(a: String, b: String) -> bool:
		return int(_redraws[a]) > int(_redraws[b]))
	var rl := "CLICK redraws/sec: "
	for v in _redraw_sec:
		rl += "%d " % v
	print(rl.strip_edges())
	var cl := "CLICK camera-rect changes/sec: "
	for v in _cam_sec:
		cl += "%d " % v
	print(cl.strip_edges())
	print("CLICK redraws in %.0f s (frames drawn = %d):" % [POST_SECS, _gaps.size()])
	for i in mini(14, names.size()):
		print("CLICK   %5d  %s" % [int(_redraws[names[i]]), names[i]])
	if _shot_dir != "":
		get_viewport().get_texture().get_image().save_png("%s/after_begin.png" % _shot_dir)
		print("CLICK shot: the map, %.1f s after the click" % POST_SECS)
	get_tree().quit()
