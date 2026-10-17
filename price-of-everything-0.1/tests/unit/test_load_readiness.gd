extends "res://tests/test_base.gd"
const FEATURE := "startup"
class Screen extends "res://scripts/loading_screen.gd":
	var complete := false
	func _world_ready() -> bool: return complete

func _test_begin_requires_completed_work_without_timed_delay() -> void:
	var screen := Screen.new()
	screen._wall_t0=Time.get_ticks_msec()-120000
	_check(not screen._ready_to_begin(),"Startup: elapsed time cannot expose unfinished generation")
	screen.complete=true
	screen._wall_t0=Time.get_ticks_msec()
	_check(screen._ready_to_begin(),"Startup: completed work enables Begin immediately")
	screen.free()
