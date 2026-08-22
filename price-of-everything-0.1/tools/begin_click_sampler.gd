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

	print("BEGIN button offered at t+%d ms — clicking" % (now - _t0))
	_clicked_at = now
	_last = Time.get_ticks_msec()
	b.pressed.emit()


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
	var sec := 0
	var acc := 0
	var cnt := 0
	var line := "CLICK fps by second: "
	for g in _gaps:
		acc += g
		cnt += 1
		if acc >= 1000:
			line += "%d " % cnt
			sec += 1
			acc = 0
			cnt = 0
	print(line.strip_edges())
	if _shot_dir != "":
		get_viewport().get_texture().get_image().save_png("%s/after_begin.png" % _shot_dir)
		print("CLICK shot: the map, %.1f s after the click" % POST_SECS)
	get_tree().quit()
