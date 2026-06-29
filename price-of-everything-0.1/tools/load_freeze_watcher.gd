extends Node
## Survives the change_scene to measure the loading screen's per-frame gaps (a big gap = the
## loading animation froze because the main thread was blocked building the world).
var _t0 := 0
var _last := 0
var _max := 0
func _ready() -> void:
	_t0 = Time.get_ticks_msec()
	_last = _t0
func _process(_d: float) -> void:
	var now := Time.get_ticks_msec()
	var gap := now - _last
	if gap > 250:
		print("  LOAD GAP %4d ms  at t+%d ms" % [gap, now - _t0])
	_max = maxi(_max, gap)
	_last = now
	var cur := get_tree().current_scene
	if cur != null and cur.get("build_complete") != null and bool(cur.get("build_complete")):
		print("LOAD done at t+%d ms; MAX loading-screen frame gap (freeze) = %d ms" % [now - _t0, _max])
		get_tree().quit(0)
