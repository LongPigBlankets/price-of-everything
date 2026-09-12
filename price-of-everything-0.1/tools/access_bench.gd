extends Node
## Micro-benchmark: what does reading sim state through another autoload cost, compared with
## a member of the same script? Headless: <godot> --headless --path . res://tools/access_bench.tscn
## Reports ns per operation for 2,000,000 iterations each.

var _local_float: float = 42.0
var _local_dict: Dictionary = {}

func _local_getter(id: String) -> Dictionary:
	return _local_dict.get(id, {})

func _ready() -> void:
	const N := 2_000_000
	MatchState.money = 42.0
	var iid: String = BuildingState.add_building("b_001", "r_001", "tile_3_8", "player_1", "bench_1")
	_local_dict[iid] = BuildingState.buildings[iid]
	var sink := 0.0
	var t0 := Time.get_ticks_usec()
	for i in N:
		sink += _local_float
	var t_local := Time.get_ticks_usec() - t0
	t0 = Time.get_ticks_usec()
	for i in N:
		sink += MatchState.money
	var t_remote := Time.get_ticks_usec() - t0
	t0 = Time.get_ticks_usec()
	for i in N:
		sink += float((_local_dict.get(iid, {}) as Dictionary).get("level", 1))
	var t_local_dict := Time.get_ticks_usec() - t0
	t0 = Time.get_ticks_usec()
	for i in N:
		sink += float((BuildingState.buildings.get(iid, {}) as Dictionary).get("level", 1))
	var t_remote_dict := Time.get_ticks_usec() - t0
	t0 = Time.get_ticks_usec()
	for i in N:
		sink += float(_local_getter(iid).get("level", 1))
	var t_local_call := Time.get_ticks_usec() - t0
	t0 = Time.get_ticks_usec()
	for i in N:
		sink += float(BuildingState.get_building(iid).get("level", 1))
	var t_remote_call := Time.get_ticks_usec() - t0
	t0 = Time.get_ticks_usec()
	for i in N:
		sink += float(BuildingState.get_buildings_on_tile("tile_3_8").size())
	var t_remote_tile := Time.get_ticks_usec() - t0
	BuildingState.remove_building(iid)
	print("[bench] iterations=%d  (sink %f)" % [N, sink])
	print("[bench] float read   same-script %6.1f ns   cross-autoload %6.1f ns" % [t_local * 1000.0 / N, t_remote * 1000.0 / N])
	print("[bench] dict lookup  same-script %6.1f ns   cross-autoload %6.1f ns" % [t_local_dict * 1000.0 / N, t_remote_dict * 1000.0 / N])
	print("[bench] getter call  same-script %6.1f ns   cross-autoload %6.1f ns" % [t_local_call * 1000.0 / N, t_remote_call * 1000.0 / N])
	print("[bench] get_buildings_on_tile cross-autoload %6.1f ns" % [t_remote_tile * 1000.0 / N])
	get_tree().quit(0)
