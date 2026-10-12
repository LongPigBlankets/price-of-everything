extends "res://tests/test_base.gd"
const FEATURE := "supply_chain_3d"
const Markings := preload("res://scripts/supply_chain_3d/road_markings.gd")
const Surface := preload("res://scripts/supply_chain_3d/road_surface.gd")
const Geo := preload("res://scripts/supply_chain_3d/geometry.gd")

func _way(a: Vector2, b: Vector2, tile := "t", source := "road", level := 2, layer := 0) -> Dictionary:
	return {"a": a, "b": b, "tile": tile, "source": source, "level": level, "layer": layer,
		"widths": [8.0, 7.0, 6.5, 6.0], "paved": true}

func _painted(stripes: Array, point: Vector2) -> bool:
	for stripe in stripes:
		if Geometry2D.is_point_in_polygon(point, stripe.points): return true
	return false

func _area(stripes: Array) -> float:
	var area := 0.0
	for stripe in stripes:
		var points: PackedVector2Array = stripe.points
		for i in range(1, points.size() - 1):
			area += absf((points[i] - points[0]).cross(points[i + 1] - points[0])) * 0.5
	return area

func _test_road_marks_continent_precision() -> void:
	# A single 80u x 0.44u solid stripe must retain its full area in every grid.
	# Previously the polygon winding test shredded it at far-from-origin coords.
	for cell in [3.0, 6.0]:
		for origin in [Vector2.ZERO, Vector2(4500, 8040), Vector2(-12000, 15000)]:
			var surface := Surface.new()
			surface.cell_size = cell
			surface.configure([], func(_p: Vector2) -> float: return 0.0, origin)
			var points := PackedVector2Array([Vector2(0, -0.22), Vector2(80, -0.22), Vector2(80, 0.22), Vector2(0, 0.22)])
			for i in points.size(): points[i] += origin
			var batch := Geo.Batch.new()
			surface._add_band(batch, points, Color.WHITE, 4)
			var area := 0.0
			for i in range(0, batch.vertices.size(), 3):
				area += (batch.vertices[i + 1] - batch.vertices[i]).cross(batch.vertices[i + 2] - batch.vertices[i]).length() * 0.5
			_check(absf(area - 35.2) < 0.12, "road_marks: thin stripes retain their area at %s with %du grid" % [origin, cell])
			surface.finish_build()

func _test_road_marks_sampling_and_tiles() -> void:
	var single := Markings.new()
	single.configure([_way(Vector2.ZERO, Vector2(192, 0))])
	var pieces: Array = []
	for x in range(0, 192, 3): pieces.append(_way(Vector2(x, 0), Vector2(x + 3, 0), "left" if x < 96 else "right"))
	var sampled := Markings.new()
	sampled.configure(pieces)
	var base := single.polygons_for("t")
	var split := sampled.polygons_for("left") + sampled.polygons_for("right")
	var same := true
	for x in range(11, 181): same = same and _painted(base, Vector2(x + 0.4, 0)) == _painted(split, Vector2(x + 0.4, 0))
	_check(same, "road_marks: curve sampling and tile boundaries never restart the dash phase")
	_check(_painted(split, Vector2(20, 0)) and not _painted(split, Vector2(28, 0)), "road_marks: short segments still alternate 8u paint and 8u gap")

func _test_road_marks_overlaps_and_layers() -> void:
	var road := _way(Vector2.ZERO, Vector2(192, 0))
	var reverse := _way(Vector2(192, 0), Vector2.ZERO, "t", "duplicate")
	var base := Markings.new(); base.configure([road])
	var duplicate := Markings.new(); duplicate.configure([reverse, road])
	_check(duplicate.duplicate_segments == 1 and is_equal_approx(_area(base.polygons_for("t")), _area(duplicate.polygons_for("t"))),
		"road_marks: reversed duplicates produce exactly one set of paint")
	var partial := Markings.new()
	partial.configure([_way(Vector2.ZERO, Vector2(96, 0), "t", "a"), _way(Vector2(20, 2), Vector2(160, 2), "t", "b")])
	_check(partial.suppressed_overlaps > 0 and not _painted(partial.polygons_for("t"), Vector2(52, 2))
		and _painted(partial.polygons_for("t"), Vector2(136, 2)), "road_marks: a partial overlapping stroke yields to the main road only along their shared stretch")
	var separated := Markings.new()
	separated.configure([road, _way(Vector2(0, 15), Vector2(192, 15), "t", "parallel")])
	_check(separated.suppressed_overlaps == 0 and is_equal_approx(_area(separated.polygons_for("t")), 2.0 * _area(base.polygons_for("t"))),
		"road_marks: separate parallel carriageways keep their own paint")
	var layers := Markings.new()
	layers.configure([road, _way(Vector2.ZERO, Vector2(192, 0), "t", "bridge", 2, 1)])
	_check(layers.duplicate_segments == 0 and layers.suppressed_overlaps == 0 and is_equal_approx(_area(layers.polygons_for("t")), 2.0 * _area(base.polygons_for("t"))),
		"road_marks: roads on different elevation layers are never deduplicated")
	var diverging := Markings.new()
	diverging.configure([_way(Vector2.ZERO, Vector2(192, 0), "t", "a"),
		_way(Vector2(0, -12), Vector2(192, 12), "t", "b")])
	_check(_painted(diverging.polygons_for("t"), Vector2(20, -9.5))
		and not _painted(diverging.polygons_for("t"), Vector2(100, 0.5)),
		"road_marks: shallow crossing roads share paint only where their centre lines are within 3u")

func _test_road_marks_bends_junctions_and_lanes() -> void:
	var bent := Markings.new()
	bent.configure([_way(Vector2.ZERO, Vector2(48, 0), "t", "a", 3), _way(Vector2(48, 0), Vector2(80, 32), "t", "b", 3)])
	var stripes := bent.polygons_for("t")
	_check(_painted(stripes, Vector2(47.5, 0.55)), "road_marks: solid centre paint stays joined through a bend between authored strokes")
	var lanes := Markings.lane_lines(3, 6.0)
	_check(lanes.size() == 6 and lanes.filter(func(l: Array) -> bool: return l[1]).size() == 4,
		"road_marks: level 3 has four dashed lane dividers and one double centre line for six lanes")
	var junction := Markings.new()
	junction.configure([_way(Vector2(-60, 0), Vector2.ZERO), _way(Vector2.ZERO, Vector2(60, 0)),
		_way(Vector2.ZERO, Vector2(0, 60), "t", "branch", 1)])
	var clear := true
	for x in range(-9, 10): clear = clear and not _painted(junction.polygons_for("t"), Vector2(x, 0))
	_check(clear, "road_marks: true junctions remain clear of paint even when the branch is unmarked")
	var loop := Markings.new()
	loop.configure([_way(Vector2.ZERO, Vector2(40, 0)), _way(Vector2(40, 0), Vector2(70, 30)),
		_way(Vector2(70, 30), Vector2(40, 60)), _way(Vector2(40, 60), Vector2(0, 60)),
		_way(Vector2(0, 60), Vector2(-30, 30)), _way(Vector2(-30, 30), Vector2.ZERO)])
	_check(_area(loop.polygons_for("t")) > 45.0, "road_marks: a closed chain is painted without dropping a segment or looping forever")
