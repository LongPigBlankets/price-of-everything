extends Node
## Measures the worst frame gap on the "menu" thread while MapPrewarm builds the base, i.e. how
## much the prewarm hitches the menu.  <godot> --path . res://tools/prewarm_hitch.tscn --quit-after 2500
var _last := 0
var _maxgap := 0
var _t0 := 0
var _on := false

func _ready() -> void:
	get_window().size = Vector2i(1280, 720)
	for _i in range(15):
		await get_tree().process_frame
	_t0 = Time.get_ticks_msec()
	_last = _t0
	_on = true
	MapPrewarm.start_prewarm()
	await MapPrewarm.warmed
	_on = false
	print("HITCH warm in %d ms; MAX menu frame gap during prewarm = %d ms" % [Time.get_ticks_msec() - _t0, _maxgap])
	get_tree().quit(0)

func _process(_d: float) -> void:
	if not _on:
		return
	var now := Time.get_ticks_msec()
	var gap := now - _last
	if gap > 300:
		print("  GAP %4d ms  at t+%d ms" % [gap, now - _t0])
	_maxgap = maxi(_maxgap, gap)
	_last = now
