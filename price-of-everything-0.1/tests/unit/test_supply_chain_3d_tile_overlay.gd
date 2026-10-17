extends "res://tests/test_base.gd"
const FEATURE := "supply_chain_3d"
const TileOverlay := preload("res://scripts/supply_chain_3d/tile_overlay.gd")

## Left of x = 0 is tile_a, right is tile_b.
class SplitGround extends RefCounted:
	func tile_at(p: Vector2) -> String: return "tile_a" if p.x < 0.0 else "tile_b"

func _base() -> Dictionary:
	return {
		"tiles": {"tile_a": {"center": Vector2(-100, 0), "store": false}, "tile_b": {"center": Vector2(100, 0), "store": true, "pylon": {}}},
		"standing": [
			{"iid": "1", "tile": "tile_a", "kind": "building", "internal_name": "furnace", "level": 1},
			{"iid": "h1", "tile": "tile_a", "kind": "house"},
			{"iid": "2", "tile": "tile_b", "kind": "building", "internal_name": "mine", "level": 2},
			{"iid": "p1", "tile": "tile_b", "kind": "port"},
			{"iid": "r1", "tile": "tile_b", "kind": "building", "internal_name": "rail_hub"},
		],
		"roads": [{"tile": "tile_a", "a": Vector2(-150, 0), "b": Vector2(-50, 0)}, {"tile": "tile_b", "a": Vector2(50, 0), "b": Vector2(150, 0)}],
		"trial_rail_segments": [{"a": Vector2(-120, 5), "b": Vector2(-80, 5)}, {"a": Vector2(-20, 5), "b": Vector2(20, 5)}, {"a": Vector2(80, 5), "b": Vector2(120, 5)}],
		"district_blocks": {"plots": [{"tile": "tile_a", "id": "base_a"}, {"tile": "tile_b", "id": "base_b"}], "paths": []},
		"dense_tiles": ["tile_a"],
		"neighbourhood": {},
		"authored_region": {},
		"flows": [{"id": "old"}],
	}

func _test_identity_compares_inputs_not_outputs() -> void:
	var base := _base()
	var ids := TileOverlay.identity(base)
	_check(not str(ids.get("tile_a", "")).contains("h1"), "tile overlay: decor houses are layout output, not identity")
	_check(not str(ids.get("tile_b", "")).contains("p1") and not str(ids.get("tile_b", "")).contains("r1"),
		"tile overlay: ports and rail hubs stay shipped and are left out of identity")
	_check(str(ids.get("tile_b", "")).contains("tile|true"), "tile overlay: a store or pylon tile record is part of identity")
	var live := base.duplicate(true)
	live.standing[1].pos = Vector2(1, 2)
	live.standing.append({"iid": "h2", "tile": "tile_a", "kind": "house"})
	_check(TileOverlay.divergent(ids, TileOverlay.identity(live), {"tile_a": true, "tile_b": true}).is_empty(),
		"tile overlay: moved or extra decor houses do not make a tile diverge")
	live.standing[2].level = 3
	_check(TileOverlay.divergent(ids, TileOverlay.identity(live), {"tile_a": true, "tile_b": true}) == ["tile_b"],
		"tile overlay: a building level change diverges only its own tile")
	live.standing.append({"iid": "9", "tile": "tile_a", "kind": "building", "internal_name": "smelter", "level": 1})
	_check(TileOverlay.divergent(ids, TileOverlay.identity(live), {"tile_b": true}) == ["tile_b"],
		"tile overlay: divergence is only reported inside the scope")

func _test_merge_takes_changed_tiles_from_the_sub_model() -> void:
	var base := _base()
	var sub := {
		"tiles": {"tile_b": {"center": Vector2(100, 0), "store": false, "polluters": 2}},
		"standing": [{"iid": "2", "tile": "tile_b", "kind": "building", "internal_name": "mine", "level": 3},
			{"iid": "x", "tile": "tile_a", "kind": "house"}],
		"district_blocks": {"plots": [{"tile": "tile_b", "id": "new_b"}, {"tile": "tile_a", "id": "stray"}]},
		"dense_tiles": ["tile_b"],
		"flows": [{"id": "live"}],
	}
	var merged := TileOverlay.merge(base, sub, ["tile_b"])
	var b_items: Array = merged.standing.filter(func(s: Dictionary) -> bool: return s.tile == "tile_b")
	_check(b_items.size() == 1 and int(b_items[0].level) == 3, "tile overlay merge: a changed tile's standing comes from the sub-model")
	_check(merged.standing.filter(func(s: Dictionary) -> bool: return s.tile == "tile_a").size() == 2,
		"tile overlay merge: unchanged tiles keep the base standing, sub-model items elsewhere are ignored")
	_check(merged.tiles.tile_b.store == false and merged.tiles.tile_b.polluters == 2 and not merged.tiles.tile_b.has("pylon"),
		"tile overlay merge: layout fields of a changed tile record come from the sub-model")
	var plot_ids: Array = merged.district_blocks.plots.map(func(p: Dictionary) -> String: return p.id)
	_check(plot_ids == ["base_a", "new_b"], "tile overlay merge: plots are replaced per changed tile only")
	_check(merged.dense_tiles == ["tile_a", "tile_b"] and merged.flows[0].id == "live", "tile overlay merge: dense tiles merge per tile and flows are live")
	_check(base.tiles.tile_b.store == true and base.standing.size() == 5, "tile overlay merge: the shipped base is not mutated")

func _test_restrict_with_index_matches_the_full_scan() -> void:
	var base := _base()
	var probe := {"lines": [], "flows": [{"id": "live"}], "made": [], "lanes": []}
	var ground := SplitGround.new()
	var scanned := TileOverlay.restrict(base, probe, ["tile_a"], ground)
	var indexed := TileOverlay.restrict(base, probe, ["tile_a"], ground, TileOverlay.index(base, ground))
	_check(indexed.roads == scanned.roads and indexed.roads.size() == 1, "tile overlay restrict: indexed roads match the scan")
	_check(indexed.trial_rail_segments == scanned.trial_rail_segments and indexed.trial_rail_segments.size() == 2,
		"tile overlay restrict: indexed rail segments match the scan, including one crossing the tile edge, in order")
	indexed.standing[0].level = 9
	_check(int(base.standing[0].level) == 1, "tile overlay restrict: standing items are copies, never the cached shipped items")
	_check(indexed.tiles.keys() == ["tile_a"] and indexed.flows[0].id == "live", "tile overlay restrict: only kept tiles, with live flows")
