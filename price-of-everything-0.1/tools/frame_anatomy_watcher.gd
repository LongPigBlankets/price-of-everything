extends Node
## Where does a new-game BUILD FRAME actually go?
##
## The frames-over-buildings arithmetic said a placement costs ~115 ms; timing the
## placement directly said ~28 ms. Both were right about their own quantity, which
## means the rest of the frame is spent somewhere that is not the job we instrumented.
## Counting the job harder cannot find it, so this counts the FRAME, by timestamping
## three points in every frame and letting the gaps between them add up to wall clock:
##
##   t_sig    SceneTree.process_frame fires. Every `await tree.process_frame` in the
##            build resumes off this signal, so THE BUILD'S OWN WORK lands in the gap
##            that starts here.
##   t_first  a helper node with process_priority -10000: the first _process of the frame.
##   t_last   this node, process_priority +10000: the last _process of the frame.
##
## giving four segments per frame, which sum to wall by construction:
##
##   coroutines   t_sig  -> t_first   the build (and anything else awaiting the signal)
##   nodes        t_first-> t_last    every _process callback in the tree
##   frame_end    t_last -> next t_sig  render, present, vsync, engine overhead
##
## Do NOT use Performance.TIME_PROCESS for this: it reports the per-second MAXIMUM
## frame, not the current frame, so summing it over frames overcounts wildly (it read
## 217% of wall). That mistake is what this file exists to avoid repeating.
##
##   <godot> --path . res://tools/load_phase_check.tscn --quit-after 20000   (ANATOMY=1)
##
## ANATOMY_CSV=<path> writes one row per frame for offline slicing.


## Runs first in the frame; hands its timestamp to the watcher.
class FirstProbe extends Node:
	var owner_watcher: Node
	func _ready() -> void:
		process_priority = -10000
	func _process(_d: float) -> void:
		owner_watcher.set("_t_first", Time.get_ticks_usec())


var _t0 := 0
var _t_sig := 0
var _t_first := 0
var _t_last := 0
var _done := false

# Per-frame segments, all ms.
var _wall: PackedFloat32Array = PackedFloat32Array()
var _coro: PackedFloat32Array = PackedFloat32Array()
var _nodes: PackedFloat32Array = PackedFloat32Array()
var _endf: PackedFloat32Array = PackedFloat32Array()
var _bldg: PackedInt32Array = PackedInt32Array()
var _draws: PackedInt32Array = PackedInt32Array()

var _sec_start := 0
var _sec_first_frame := 0


func _ready() -> void:
	process_priority = 10000       # sample last: one sample = one whole frame
	_t0 = Time.get_ticks_usec()
	_t_last = _t0
	_sec_start = _t0
	# Connect BEFORE the world scene exists so this callback is ahead of the build's
	# own `await` resumptions in the signal's connection list — t_sig is then the
	# true start of the signal step, with the build's work still ahead of it.
	get_tree().process_frame.connect(_on_process_frame)
	var probe := FirstProbe.new()
	probe.owner_watcher = self
	add_child(probe)
	print("ANATOMY sampling started (vsync=%d max_fps=%d)" %
		[DisplayServer.window_get_vsync_mode(), Engine.max_fps])


func _on_process_frame() -> void:
	_t_sig = Time.get_ticks_usec()


## A/B switches. Pacing is untouched by either — `_loading_screen_active()` tests for
## a LoadingScreen NODE, not for whether it is visible or playing — so the build does
## exactly the same work in the same order, and any difference in frame time is the
## thing that was switched off.
##   HIDE_SCREEN=1  hide the loading screen (its film + UI stop DRAWING; still decodes)
##   NO_VIDEO=1     pause the film (stops DECODING; the rest of the screen still draws)
var _ab_applied := false

func _apply_ab_switches() -> void:
	if _ab_applied:
		return
	_ab_applied = true
	for c in get_tree().root.get_children():
		if not (c is LoadingScreen):
			continue
		if OS.get_environment("HIDE_SCREEN") != "":
			(c as CanvasLayer).visible = false
			print("ANATOMY A/B: loading screen HIDDEN (draw off, decode on)")
		if OS.get_environment("NO_VIDEO") != "":
			for n in _all_descendants(c):
				if n is VideoStreamPlayer:
					(n as VideoStreamPlayer).paused = true
					print("ANATOMY A/B: film PAUSED (decode off, draw on)")
	# HIDE_MAP=1 / HIDE_ALL=1: hide the map layers world_map's own MAP_LAYER_NAMES misses
	# — above all TerrainLayer, the hex tilemap, which is the bulk of the draw calls.
	# HIDE_ALL also takes UILayer (the HUD). Nothing here is visible anyway: the loading
	# screen is opaque and covers the window.
	# NO_PHYSICS=1: stop the physics catch-up. A 126 ms frame owes the 60 Hz physics clock
	# ~8 ticks, which is exactly the default max_physics_steps_per_frame cap — and those
	# ticks run in Main::iteration BEFORE the process step, i.e. inside the frame_end
	# segment. If frame_end collapses here, the loading screen is paying for physics it
	# has no use for while the world is being built.
	if OS.get_environment("NO_PHYSICS") != "":
		Engine.max_physics_steps_per_frame = 1
		Engine.physics_ticks_per_second = 1
		print("ANATOMY A/B: physics throttled to 1 tick/s, 1 step/frame")
	# CAP_STEPS=1: the minimal version of the same idea — physics keeps its 60 Hz rate,
	# but a slow frame runs ONE tick instead of catching up eight.
	if OS.get_environment("CAP_STEPS") != "":
		Engine.max_physics_steps_per_frame = 1
		print("ANATOMY A/B: max_physics_steps_per_frame = 1 (rate left at %d Hz)" %
			Engine.physics_ticks_per_second)
	if OS.get_environment("HIDE_MAP") != "" or OS.get_environment("HIDE_ALL") != "":
		var all := OS.get_environment("HIDE_ALL") != ""
		var hidden: Array = []
		for c in get_tree().current_scene.get_children():
			if c.name == "UILayer" and not all:
				continue
			if c is CanvasItem:
				(c as CanvasItem).visible = false
				hidden.append(c.name)
			elif c is CanvasLayer:
				(c as CanvasLayer).visible = false
				hidden.append(c.name)
		print("ANATOMY A/B: hid %d map layers: %s" % [hidden.size(), ", ".join(hidden)])


func _all_descendants(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		out.append(c)
		out.append_array(_all_descendants(c))
	return out


func _process(_d: float) -> void:
	var prev_last := _t_last
	var now := Time.get_ticks_usec()
	_t_last = now
	if _done:
		return
	if not _ab_applied and get_tree().current_scene != null \
			and get_tree().current_scene.get("build_complete") != null:
		_apply_ab_switches()

	# Segments. frame_end belongs to the PREVIOUS frame's tail: it runs from the last
	# _process of frame k-1 up to this frame's signal.
	_wall.append(float(now - prev_last) / 1000.0)
	_endf.append(float(_t_sig - prev_last) / 1000.0)
	_coro.append(float(_t_first - _t_sig) / 1000.0)
	_nodes.append(float(now - _t_first) / 1000.0)
	_bldg.append(MatchState.buildings.size())
	_draws.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))

	if now - _sec_start >= 1000000:
		_report_window(_sec_first_frame, _wall.size(), now)
		_sec_start = now
		_sec_first_frame = _wall.size()

	var cur := get_tree().current_scene
	if cur != null and cur.get("build_complete") != null and bool(cur.get("build_complete")):
		_done = true
		_report_window(_sec_first_frame, _wall.size(), now)
		_report_total()
		get_tree().quit(0)


func _mean(a: PackedFloat32Array, from_i: int, to_i: int) -> float:
	var s := 0.0
	for i in range(from_i, to_i):
		s += a[i]
	return s / maxf(1.0, float(to_i - from_i))


func _sum(a: PackedFloat32Array, from_i: int, to_i: int) -> float:
	var s := 0.0
	for i in range(from_i, to_i):
		s += a[i]
	return s


## One second of frames: the mean anatomy, so a slow stretch shows its own shape.
func _report_window(from_i: int, to_i: int, now: int) -> void:
	var n := to_i - from_i
	if n <= 0:
		return
	print("ANATOMY t+%6d ms  %3d f  wall %6.1f | coroutines %6.1f  nodes %6.1f  frame_end %6.1f  (%.1f fps) buildings=%4d draws=%5d" %
		[(now - _t0) / 1000, n, _mean(_wall, from_i, to_i), _mean(_coro, from_i, to_i),
		_mean(_nodes, from_i, to_i), _mean(_endf, from_i, to_i),
		1000.0 * n / maxf(1.0, _sum(_wall, from_i, to_i)), _bldg[to_i - 1], _draws[to_i - 1]])


## The whole run, and then the build alone — the build is what we are trying to shrink,
## and the idle frames before the scene change would otherwise flatter every average.
func _report_total() -> void:
	var n := _wall.size()
	if n == 0:
		return
	# The scene instantiation is the single longest frame; the build is everything from
	# there on. Splitting there keeps the pre-build idle frames out of the build's mean.
	var big := 0
	for i in n:
		if _wall[i] > _wall[big]:
			big = i
	_report_span("whole run", 0, n)
	_report_span("BUILD (from the instantiation frame)", big, n)
	print("ANATOMY   scene instantiation, one frame: %.0f ms" % _wall[big])

	var sorted := Array(_wall.slice(big, n))
	sorted.sort()
	var m := sorted.size()
	print("ANATOMY   build frame wall ms  p50 %.1f  p90 %.1f  p99 %.1f  max %.1f" %
		[sorted[int(m * 0.50)], sorted[int(m * 0.90)], sorted[mini(int(m * 0.99), m - 1)], sorted[m - 1]])

	var csv := OS.get_environment("ANATOMY_CSV")
	if csv != "":
		var f := FileAccess.open(csv, FileAccess.WRITE)
		if f != null:
			f.store_line("frame,wall_ms,coroutines_ms,nodes_ms,frame_end_ms,buildings,draw_calls")
			for i in n:
				f.store_line("%d,%.3f,%.3f,%.3f,%.3f,%d,%d" %
					[i, _wall[i], _coro[i], _nodes[i], _endf[i], _bldg[i], _draws[i]])
			f.close()
			print("ANATOMY   per-frame csv -> %s" % csv)


func _report_span(label: String, from_i: int, to_i: int) -> void:
	var n := to_i - from_i
	if n <= 0:
		return
	var w := _sum(_wall, from_i, to_i)
	var c := _sum(_coro, from_i, to_i)
	var nd := _sum(_nodes, from_i, to_i)
	var e := _sum(_endf, from_i, to_i)
	print("\nANATOMY ===== %s: %.1f s over %d frames (%.1f fps, %.1f ms/frame) =====" %
		[label, w / 1000.0, n, 1000.0 * n / w, w / n])
	print("ANATOMY   coroutines (the build's own work) %8.2f s  %5.1f%%  %6.1f ms/f" %
		[c / 1000.0, 100.0 * c / w, c / n])
	print("ANATOMY   nodes (_process callbacks)        %8.2f s  %5.1f%%  %6.1f ms/f" %
		[nd / 1000.0, 100.0 * nd / w, nd / n])
	print("ANATOMY   frame_end (render/present/engine) %8.2f s  %5.1f%%  %6.1f ms/f" %
		[e / 1000.0, 100.0 * e / w, e / n])
