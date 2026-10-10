extends "res://tests/test_base.gd"
const FEATURE := "supply_chain_3d"
const Cables := preload("res://scripts/supply_chain_3d/pylon_cables.gd")
const Assets := preload("res://scripts/supply_chain_3d/assets.gd")
const Builder := preload("res://scripts/supply_chain_3d/world_builder.gd")

func _test_pylon_medium_uses_continuous_geometry() -> void:
	var key := Assets.key_for("pylon", 1)
	var s := {"kind": "pylon", "iid": "pylon:a", "tile": "a", "pos": Vector2.ZERO, "side": 62.0}
	var builder := Builder.new()
	builder.lazy_assets = true
	builder.standing_frames[s.iid] = {"key": key, "position": Vector3.ZERO,
		"dimension": Assets.dimensions(key) * 62.0, "plinth_depth": 0.0}
	builder.pylon_layout = {"yaws": {s.iid: PI / 3.0}}
	var root := builder.standing_node(s)
	builder.set_detail(1)
	var pair: Dictionary = builder.sprite_pairs[0]
	_check(pair.medium == null and not pair.near.is_empty() and pair.near[0].visible,
		"Pylons: medium uses continuous mesh geometry so cable clamps cannot drift with sprite angles")
	_check(is_equal_approx(root.rotation.y, PI / 3.0), "Pylons: displayed mesh uses the cable layout's orientation")
	builder.set_overview_scale(0.20)
	_check(pair.far.visible and not pair.near[0].visible, "Pylons: far zoom retains the small cached sprite")
	root.free()

func _test_pylon_clamps_and_sloped_span() -> void:
	var key := Assets.key_for("pylon", 1)
	var local := Assets.cable_anchors(key)
	_check(local.size() == 4, "Pylons: four exported insulator clamps")
	if local.size() != 4: return
	var height := Assets.dimensions(key).y
	_check(local[0].y > height * 0.75 and local[2].y > height * 0.60,
		"Pylons: conductors attach to the two upper arm tiers")
	var model := {"standing": [
		{"kind": "pylon", "iid": "a", "pos": Vector2(10, 20), "side": 62.0},
		{"kind": "pylon", "iid": "b", "pos": Vector2(250, 340), "side": 62.0}],
		"lines": [{"mode": "cables", "ids": ["a", "b"]}]}
	var frame_for := func(s: Dictionary) -> Dictionary:
		return {"key": key, "position": Vector3(s.pos.x, 80.0 if s.iid == "a" else 125.0, s.pos.y)}
	var layout := Cables.layout(model, frame_for)
	_check(layout.spans.size() == 4, "Pylons: one span per insulator instead of a central cable")
	var direction := Vector3(240, 0, 320).normalized()
	var across := Basis(Vector3.UP, layout.yaws.a) * Vector3.BACK
	_check(absf(across.dot(direction)) < 0.00001, "Pylons: arms lie across the power line")
	var upper_a := Vector3(10, 80, 20) + Basis(Vector3.UP, layout.yaws.a) * local[0] * 62.0
	_check(upper_a.is_equal_approx(layout.anchors.a[0]), "Pylons: attachment shares the model's scale, orientation and foundation height")
	for span in layout.spans:
		var points := Cables.curve(span.a, span.b)
		_check(points[0] == span.a and points[-1] == span.b, "Pylons: sloping conductors end exactly on their clamps")
		_check(layout.anchors.a.has(points[0]) and layout.anchors.b.has(points[-1]), "Pylons: neither endpoint falls back to a guessed ground offset")
		var mid := points.size() / 2
		var straight: Vector3 = span.a.lerp(span.b, float(mid) / (points.size() - 1))
		_check(points[mid].y < straight.y - 10.0, "Pylons: conductor hangs below the line between clamps")
	var original: Dictionary = layout.duplicate(true)
	model.lines[0].ids.reverse()
	layout = Cables.layout(model, frame_for)
	_check(is_equal_approx(layout.yaws.a, original.yaws.a) and is_equal_approx(layout.yaws.b, original.yaws.b),
		"Pylons: reversing a network link does not turn its towers")

func _test_pylon_branches_and_missing_endpoints() -> void:
	var key := Assets.key_for("pylon", 1)
	var model := {"standing": [
		{"kind": "pylon", "iid": "a", "pos": Vector2(-100, 0), "side": 62.0},
		{"kind": "pylon", "iid": "b", "pos": Vector2.ZERO, "side": 62.0},
		{"kind": "pylon", "iid": "c", "pos": Vector2(100, 100), "side": 62.0}],
		"lines": [{"mode": "cables", "ids": ["a", "b"]}, {"mode": "cables", "ids": ["b", "c"]},
			{"mode": "cables", "ids": ["a", "missing"]}, {"mode": "pipes", "ids": ["a", "c"]}]}
	var frame_for := func(s: Dictionary) -> Dictionary:
		return {"key": key, "position": Vector3(s.pos.x, 0, s.pos.y)}
	var layout := Cables.layout(model, frame_for)
	_check(layout.spans.size() == 8, "Pylons: only complete cable links emit conductors")
	_check(is_equal_approx(layout.yaws.b, -PI / 8.0), "Pylons: a shared tower bisects the line bend")
	for tier in 2:
		var ends := []
		for span in layout.spans.slice(0, 4):
			if int(span.tier) == tier: ends.append(span.b)
		_check(ends.size() == 2 and ends[0] != ends[1], "Pylons: each tier uses distinct clamps at a junction")
