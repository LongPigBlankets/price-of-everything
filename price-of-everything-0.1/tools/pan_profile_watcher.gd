extends Node
## Where does a PAN FRAME at max zoom go?  (parented to the root by tools/pan_profile.gd)
##
## The build had frame_anatomy_watcher; a play frame needs its own accounting, because the
## segments mean different things once nothing is awaiting process_frame:
##
##   nodes    t_first -> t_last       every _process callback in the tree
##   flush    t_last  -> flush_end    MessageQueue: every CanvasItem._draw that was queued
##   render   flush_end -> next t_sig RenderingServer sync + submit + present + vsync
##
## _draw does NOT run in the process step. Godot queues queue_redraw() onto the MessageQueue
## and flushes it in Main::iteration AFTER the whole process step, so a layer's paint lands in
## what a naive split would call "render". This separates them by timestamping every
## CanvasItem's `draw` signal, which fires immediately after that item's _draw returns. The
## census covers the WHOLE tree -- HUD panels included, because a label that re-lays-out every
## frame costs exactly as much as a map layer that repaints every frame and is far easier to
## miss.
##
## READ THE COLUMNS CORRECTLY. `repaints` is exact -- one signal, one paint. `ms/paint` is NOT:
## it is the gap since the PREVIOUS draw signal, so anything the MessageQueue ran in between,
## and the frame's own lead-in, is charged to whichever node happens to draw next. Measured:
## AuthoredRoadVisuals read 80 ms/paint; hiding it moved the same 80 ms onto HexGridOverlay,
## the next node in the flush, and the four layers carrying the repo's own LOAD_PROF wrapper
## reported no draw over 50 ms in the same run. So the ms column ranks candidates; it does not
## price them. To price one, wrap its _draw the way authored_road_visuals.gd does and run with
## LOAD_PROF=1. The segment totals above the table are sound either way.
##
## The renderer reports its own halves via viewport_set_measure_render_time, so CPU-submit and
## GPU-execute are separated too, and whatever is neither is the present/vsync wait.
##
## Env knobs:
##   PAN_W / PAN_H    window size (default 1920x1080). Vary to test fill-rate scaling.
##   PAN_SECS         seconds of panning to sample (default 8)
##   PAN_WARM         seconds to burn before sampling starts (default 0). USE IT for zoom-out:
##                    the hill mesh warm runs for the first several seconds of play and is not
##                    part of a steady frame.
##   PAN_SPEED        world units/sec of camera travel. Default: the camera's own
##                    pan_speed / zoom, i.e. exactly what holding an arrow key does.
##   PAN_ZOOM         fraction from zoom_min to zoom_max (default 1.0 = max zoom in)
##   PAN_STILL=1      do not pan at all -- the still-camera control
##   PAN_VSYNC=1      leave vsync on (default OFF, so frame time is the real cost)
##   PAN_HIDE=<names> comma-separated child names of the world to hide before sampling
##   PAN_NOROADS=1    RoadNetwork.roads_visible = false. Not the same as PAN_HIDE=
##                    RoadNetworkVisuals: that layer's _process re-asserts its own visibility
##                    every frame, so hiding the node does nothing and reads as "costs zero".
##   PAN_TILE=<id>    centre on this tile first, so two runs frame identical ground
##   PAN_SHOT=<path>  save a PNG of the final frame (verify the picture, not just the counters)
##   PAN_CSV=<path>   per-frame rows


## Runs first in the frame; hands its timestamp to the profiler.
class FirstProbe extends Node:
	var prof: Node
	func _ready() -> void:
		process_priority = -10000
	func _process(_d: float) -> void:
		prof.set("_t_first", Time.get_ticks_usec())


var _t_sig := 0
var _t_first := 0
var _t_last := 0

# The draw census. Keyed by node path; value = [total_ms, repaint_count].
var _census: Dictionary = {}
var _draw_mark := 0
var _flush_end := 0

var _sampling := false
var _pan_secs := 8.0
var _elapsed := 0.0
## Seconds to burn BEFORE sampling. reveal_for_play() kicks off hill_visuals.warm_meshes_deferred()
## — 8.6 s of contour triangulation sliced into play frames — and at 5-16 fps that overlaps a
## whole sample. Runs that included it read 134-226 ms; the settled frame is 59. Any zoom-out
## number taken without this is measuring the warm, not the frame.
var _warm_left := 0.0
var _pan_dir := Vector2.RIGHT
var _pan_speed := 0.0
var _cam: Camera2D = null
var _no_cam := 0

var _wall: PackedFloat32Array = PackedFloat32Array()
var _nodes: PackedFloat32Array = PackedFloat32Array()
var _flush: PackedFloat32Array = PackedFloat32Array()
var _rend: PackedFloat32Array = PackedFloat32Array()
var _rcpu: PackedFloat32Array = PackedFloat32Array()
var _rgpu: PackedFloat32Array = PackedFloat32Array()
var _drawc: PackedInt32Array = PackedInt32Array()


func _ready() -> void:
	process_priority = 10000
	_pan_secs = float(_env("PAN_SECS", "8"))
	_warm_left = float(_env("PAN_WARM", "0"))
	get_tree().process_frame.connect(_on_process_frame)
	var probe := FirstProbe.new()
	probe.prof = self
	add_child(probe)
	if OS.get_environment("PAN_VSYNC") == "":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	print("PANPROF watcher up, vsync=%d" % DisplayServer.window_get_vsync_mode())


func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else d


func _on_process_frame() -> void:
	_t_sig = Time.get_ticks_usec()


func _all(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_all(c))
	return out


## Every CanvasItem in the tree reports the moment its _draw returned. The gap since the
## previous report is that item's own cost: the message queue runs them back to back.
func _connect_census() -> void:
	var n := 0
	for node in _all(get_tree().root):
		if node is CanvasItem and not node.draw.is_connected(_on_item_drawn):
			node.draw.connect(_on_item_drawn.bind(node))
			n += 1
	print("PANPROF census watching %d CanvasItems" % n)


func _on_item_drawn(node: Node) -> void:
	var now := Time.get_ticks_usec()
	if not _sampling:
		_draw_mark = now
		return
	var ms := float(now - _draw_mark) / 1000.0
	_draw_mark = now
	_flush_end = now
	var key := str(node.get_path())
	var e = _census.get(key)
	if e == null:
		_census[key] = [ms, 1]
	else:
		e[0] += ms
		e[1] += 1


func _process(delta: float) -> void:
	var prev_last := _t_last
	var now := Time.get_ticks_usec()
	_t_last = now

	var scene := get_tree().current_scene
	if not _sampling:
		if scene == null or scene.get("build_complete") == null or not bool(scene.get("build_complete")):
			_draw_mark = now
			return
		_start_sampling(scene)
		_draw_mark = now
		return

	# The frame that just ended. [prev_last .. now] is one whole wall-clock frame; inside it
	# prev_last -> flush_end was the MessageQueue (every _draw), flush_end -> _t_sig was the
	# renderer and the present, and _t_first -> now was the process step.
	var flush_end := maxi(_flush_end, prev_last)
	_wall.append(float(now - prev_last) / 1000.0)
	_nodes.append(float(now - _t_first) / 1000.0)
	_flush.append(float(flush_end - prev_last) / 1000.0)
	_rend.append(float(_t_sig - flush_end) / 1000.0)
	var vp := get_viewport().get_viewport_rid()
	_rcpu.append(RenderingServer.viewport_get_measured_render_time_cpu(vp))
	_rgpu.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
	_drawc.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	_flush_end = 0
	_draw_mark = now

	_drive_pan(delta)
	_elapsed += delta
	if _warm_left > 0.0:
		_warm_left -= delta
		if _warm_left <= 0.0:
			print("PANPROF warm-up done, sampling starts now")
		_wall.resize(0); _nodes.resize(0); _flush.resize(0)
		_rend.resize(0); _rcpu.resize(0); _rgpu.resize(0); _drawc.resize(0)
		_census.clear()
		_elapsed = 0.0
		return
	if _elapsed >= _pan_secs:
		_report()
		await _maybe_shoot()
		get_tree().quit(0)


## PAN_SHOT=<path>: save what the profiler was looking at. A layer whose draw-call count fell
## is not the same claim as a layer that still draws the right picture.
func _maybe_shoot() -> void:
	var path := _env("PAN_SHOT", "")
	if path == "":
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("PANPROF shot -> %s" % path)


func _start_sampling(scene: Node) -> void:
	_cam = get_viewport().get_camera_2d()
	if _cam == null:
		_no_cam += 1
		if _no_cam % 120 == 1:
			print("PANPROF waiting for a current Camera2D (%d frames)" % _no_cam)
		if _no_cam > 600:
			print("PANPROF giving up: no current Camera2D")
			get_tree().quit(1)
		return
	if scene.has_method("reveal_for_play"):
		scene.call("reveal_for_play")
	for c in get_tree().root.get_children():
		if c is LoadingScreen:
			(c as CanvasLayer).visible = false
	# PAN_TILE pins the camera so two runs frame the SAME ground. Without it the intro focus
	# tween is still settling when sampling starts, and it settles further at 60 fps than at 15 —
	# so a before/after pair of screenshots is two different views, not two renderings of one.
	var tile := _env("PAN_TILE", "")
	if tile != "" and scene.has_method("_focus_camera_on_tile"):
		scene.call("_focus_camera_on_tile", tile)
	var zmin: float = _cam.call("_effective_zoom_min") if _cam.has_method("_effective_zoom_min") else float(_cam.get("zoom_min"))
	var zmax := float(_cam.get("zoom_max"))
	var z: float = lerpf(zmin, zmax, float(_env("PAN_ZOOM", "1.0")))
	_cam.zoom = Vector2.ONE * z
	_cam.set("_target_zoom", _cam.zoom)
	_cam.set("input_blocked", true)   # our pan only; no edge-pan from a stray mouse
	var speed := float(_env("PAN_SPEED", "0"))
	if speed <= 0.0:
		speed = float(_cam.get("pan_speed")) / z   # exactly what holding an arrow key does
	_pan_speed = 0.0 if OS.get_environment("PAN_STILL") != "" else speed
	if OS.get_environment("PAN_NOROADS") != "":
		RoadNetwork.roads_visible = false
		print("PANPROF roads off (RoadNetwork.roads_visible = false)")
	# PAN_HILLPROBE: the far-zoom relief is ONE draw_texture_rect, and hiding it took the frame
	# from 134 to 60 ms — so what that single quad actually costs the sampler is worth knowing.
	if OS.get_environment("PAN_HILLPROBE") != "":
		var hv := scene.get_node_or_null("HillVisuals")
		var tex: Texture2D = hv.get("_baked_tex") if hv != null else null
		if tex == null:
			print("PANPROF hill probe: no baked texture (vector mode)")
		else:
			var img := tex.get_image()
			print("PANPROF hill probe: %s %dx%d mipmaps=%s fmt=%d  node filter=%d" %
				[tex.get_class(), tex.get_width(), tex.get_height(),
				str(img.has_mipmaps()) if img != null else "?",
				int(img.get_format()) if img != null else -1,
				int(hv.texture_filter)])
	var flt := _env("PAN_HILLFILTER", "")
	if flt != "":
		var hv2 := scene.get_node_or_null("HillVisuals")
		if hv2 != null:
			hv2.texture_filter = int(flt)
			print("PANPROF hill texture_filter := %d" % int(flt))
	var hide_list := _env("PAN_HIDE", "")
	if hide_list != "":
		for hide_name in hide_list.split(","):
			var node := scene.get_node_or_null(NodePath(hide_name.strip_edges()))
			if node != null:
				node.set("visible", false)
				print("PANPROF hid %s" % hide_name)
			else:
				print("PANPROF no such node to hide: %s" % hide_name)
	_connect_census()
	_census.clear()
	_sampling = true
	print("PANPROF sampling: zoom %.3f (min %.3f max %.3f), pan %.1f world u/s, %.0f s" %
		[z, zmin, zmax, _pan_speed, _pan_secs])
	print("PANPROF viewport %s  window %s" %
		[str(get_viewport().get_visible_rect().size), str(get_window().size)])


## A slow serpentine inside the map bounds, so the sample is a real traverse over varied ground
## rather than a loop over the same twenty hexes.
func _drive_pan(delta: float) -> void:
	if _cam == null or _pan_speed <= 0.0:
		return
	var lo: Vector2 = _cam.get("map_min")
	var hi: Vector2 = _cam.get("map_max")
	var p := _cam.position + _pan_dir * _pan_speed * delta
	if p.x > hi.x - 20.0 or p.x < lo.x + 20.0:
		_pan_dir.x = -_pan_dir.x
		p.y += 40.0
		if p.y > hi.y - 20.0:
			p.y = lo.y + 20.0
	_cam.position = p


func _pct(a: PackedFloat32Array, q: float) -> float:
	var s := Array(a)
	s.sort()
	if s.is_empty():
		return 0.0
	return s[clampi(int(s.size() * q), 0, s.size() - 1)]


func _mean(a: PackedFloat32Array) -> float:
	var t := 0.0
	for v in a:
		t += v
	return t / maxf(1.0, float(a.size()))


func _mean_i(a: PackedInt32Array) -> float:
	var t := 0.0
	for v in a:
		t += float(v)
	return t / maxf(1.0, float(a.size()))


func _report() -> void:
	var n := _wall.size()
	if n == 0:
		print("PANPROF no frames sampled")
		return
	print("\nPANPROF ===== %d frames, %.1f fps, %.2f ms/frame (p50 %.2f p90 %.2f p99 %.2f) =====" %
		[n, 1000.0 / maxf(0.001, _mean(_wall)), _mean(_wall),
		_pct(_wall, 0.5), _pct(_wall, 0.9), _pct(_wall, 0.99)])
	print("PANPROF   nodes  (_process callbacks)      %7.2f ms/f  p90 %6.2f" % [_mean(_nodes), _pct(_nodes, 0.9)])
	print("PANPROF   flush  (CanvasItem._draw)        %7.2f ms/f  p90 %6.2f" % [_mean(_flush), _pct(_flush, 0.9)])
	print("PANPROF   render (sync+submit+present)     %7.2f ms/f  p90 %6.2f" % [_mean(_rend), _pct(_rend, 0.9)])
	print("PANPROF     of which renderer-reported CPU %7.2f ms/f" % _mean(_rcpu))
	print("PANPROF     of which renderer-reported GPU %7.2f ms/f" % _mean(_rgpu))
	print("PANPROF   draw calls %.0f/f" % _mean_i(_drawc))

	var rows: Array = []
	for k in _census:
		var e: Array = _census[k]
		rows.append([e[0] / float(n), e[1], k, e[0] / maxf(1.0, float(e[1]))])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	print("\nPANPROF ----- who repaints (counts exact; ms is gap-since-previous, see header) -----")
	print("PANPROF   %8s %8s %9s  %s" % ["ms/f", "repaints", "ms/paint", "node"])
	var shown := 0
	var tail := 0.0
	for r in rows:
		if shown < 30:
			print("PANPROF   %8.3f %8d %9.3f  %s" % [r[0], r[1], r[3], r[2]])
			shown += 1
		else:
			tail += r[0]
	if tail > 0.0:
		print("PANPROF   %8.3f          (%d more nodes)" % [tail, rows.size() - shown])

	var csv := OS.get_environment("PAN_CSV")
	if csv != "":
		var f := FileAccess.open(csv, FileAccess.WRITE)
		if f != null:
			f.store_line("frame,wall_ms,nodes_ms,flush_ms,render_ms,rcpu_ms,rgpu_ms,draw_calls")
			for i in n:
				f.store_line("%d,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%d" %
					[i, _wall[i], _nodes[i], _flush[i], _rend[i], _rcpu[i], _rgpu[i], _drawc[i]])
			f.close()
			print("PANPROF per-frame csv -> %s" % csv)
