extends "res://tests/test_base.gd"
const FEATURE := "supply_chain_3d"
const Alignment := preload("res://scripts/supply_chain_3d/road_alignment.gd")
const Memo := preload("res://scripts/supply_chain_3d/road_alignment_memo.gd")

## A hillside rising to the east: a road running east is steep, one running
## north is flat.
func _height(p: Vector2) -> float: return p.x * 0.4
func _level(_p: Vector2) -> float: return 0.0

func _model(extra_roads: Array = [], standing: Array = []) -> Dictionary:
	var roads: Array = [
		{"a": Vector2(-200, 0), "b": Vector2(200, 0), "level": 1, "tile": "hill"},
		{"a": Vector2(2000, -100), "b": Vector2(2000, 100), "level": 1, "tile": "far"},
	]
	roads.append_array(extra_roads)
	return {"roads": roads, "tiles": {"hill": {"center": Vector2.ZERO}, "far": {"center": Vector2(2000, 0)}}, "standing": standing, "depots": []}

func _memo() -> RefCounted:
	var memo: RefCounted = Memo.new()
	memo.memo_enabled = true
	return memo

func _test_alignment_memo_reproduces_a_fresh_solve() -> void:
	Memo._memo.clear()
	var fresh: Array = Alignment.new().configure(_model(), _height, _level)
	var first: RefCounted = _memo()
	var solved: Array = first.configure(_model(), _height, _level)
	_check(var_to_str(solved) == var_to_str(fresh) and first.memo_misses == 2 and first.memo_hits == 0,
		"alignment memo: a cold memo solves every chain and matches the plain alignment")
	var second: RefCounted = _memo()
	var reused: Array = second.configure(_model(), _height, _level)
	_check(var_to_str(reused) == var_to_str(fresh) and second.memo_hits == 2 and second.memo_misses == 0,
		"alignment memo: the same roads are read back from the memo, identical to a fresh solve")
	Memo._memo.clear()

func _test_alignment_memo_solves_only_chains_a_change_reaches() -> void:
	Memo._memo.clear()
	_memo().configure(_model(), _height, _level)
	var far_road := [{"a": Vector2(2100, -100), "b": Vector2(2100, 100), "level": 1, "tile": "far"}]
	var grown: RefCounted = _memo()
	var aligned: Array = grown.configure(_model(far_road), _height, _level)
	_check(grown.memo_misses == 1 and grown.memo_hits == 2, "alignment memo: a road joining far away solves only its own chain")
	_check(var_to_str(aligned) == var_to_str(Alignment.new().configure(_model(far_road), _height, _level)),
		"alignment memo: reused and new chains together match a fresh solve")
	var building := [{"iid": "b1", "tile": "hill", "kind": "building", "pos": Vector2(0, 80), "side": 40}]
	var blocked: RefCounted = _memo()
	blocked.configure(_model([], building), _height, _level)
	_check(blocked.memo_misses == 1 and blocked.memo_hits == 1,
		"alignment memo: a building beside the steep road solves that chain again, the flat one is reused")
	Memo._memo.clear()
