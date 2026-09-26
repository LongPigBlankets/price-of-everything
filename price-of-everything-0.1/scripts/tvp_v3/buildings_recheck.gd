extends Node
## Tile view v3, Buildings tab: after a refresh drawn from readings kept on the panel, works each of them
## out again over the next frames, a few milliseconds a frame, and keeps the new ones. If anything shown
## has changed, it asks the panel for one refresh, which then draws the new readings. It lives in the tab's
## pane, so the next rebuild frees it and starts another.

const Readings := preload("res://scripts/tvp_v3/buildings_readings.gd")
## Time spent a frame. The diagnostics take about 3 ms a building, so one or two a frame.
const BUDGET_USEC := 4000

var panel: Control
var queue: Array = []
var _changed := false


func _init(p: Control, buildings: Array) -> void:
	name = "BuildingsRecheck"
	panel = p
	queue = buildings.duplicate()


func _process(_delta: float) -> void:
	if panel == null or not is_instance_valid(panel):
		queue_free()
		return
	var t0 := Time.get_ticks_usec()
	var kept: Dictionary = panel.get_meta(Readings.META_READINGS, {})
	while not queue.is_empty() and Time.get_ticks_usec() - t0 < BUDGET_USEC:
		var b: Dictionary = queue.pop_front()
		var hit: Dictionary = kept.get(str(b.get("instance_id", "")), {})
		if hit.is_empty():
			continue
		var fresh := Readings.reading(b)
		if Readings.digest(fresh) != Readings.digest(hit.r):
			_changed = true
		hit["r"] = fresh
	if not queue.is_empty():
		return
	set_process(false)
	var pane := get_parent() as Control
	if _changed and pane != null and pane.is_visible_in_tree():
		panel.call("_refresh_if_visible")
	queue_free()
