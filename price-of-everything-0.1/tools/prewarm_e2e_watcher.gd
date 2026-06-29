extends Node
## Survives the reveal (which frees the stand-in "menu") and asserts the prewarm→reveal→finish
## flow behind a real loading screen: it times every frame (max gap = freeze detector) and waits
## for the revealed map's build_complete, then reports buildings placed + screenshots the result.
var screen: Node
var _t0 := 0
var _last := 0
var _maxgap := 0

func _ready() -> void:
	_t0 = Time.get_ticks_msec()
	_last = _t0

func _process(_d: float) -> void:
	var now := Time.get_ticks_msec()
	_maxgap = maxi(_maxgap, now - _last)
	_last = now
	var cur := get_tree().current_scene
	if cur == null or cur.get("build_complete") == null:
		return
	if not bool(cur.get("build_complete")):
		return
	set_process(false)
	var got := 0
	for iid in MatchState.buildings:
		if MatchState.is_player_owned(MatchState.buildings[iid]):
			got += 1
	print("E2E build_complete after %d ms; MAX frame gap during reveal+finish = %d ms" % [now - _t0, _maxgap])
	print("E2E player buildings placed: %d (want 4 for coal_baron)" % got)
	print("E2E loading screen ready_to_begin = %s" % str(screen.call("_ready_to_begin")))
	await _finish()

func _finish() -> void:
	for _i in range(6):
		await get_tree().process_frame
	if is_instance_valid(screen):
		screen.queue_free()   # drop the loading screen so the screenshot shows the revealed map
	for _i in range(6):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/tmp/poe_prewarm_e2e.png")
	print("E2E saved /tmp/poe_prewarm_e2e.png")
	get_tree().quit(0)
