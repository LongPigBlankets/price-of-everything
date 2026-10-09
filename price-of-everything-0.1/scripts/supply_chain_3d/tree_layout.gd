extends RefCounted
## Source species, seeds and roadside rows, with the same clearance rules. Shared
## candidate generation keeps the 2D and 3D versions' landscape composition aligned.
const Legacy := preload("res://scripts/empire_board.gd")
const Model := preload("res://scripts/empire_board_model.gd")
const Ground := preload("res://scripts/empire_board_ground.gd")
const Streets := preload("res://scripts/empire_board_streets.gd")

static func placements(tid: String, tile: Dictionary, relief: Dictionary, standing: Array,
		roads: Array, lines: Array, rivers: Array) -> Array:
	if str(tile.type) in ["sea", "deep_sea", "mountain"]: return []
	var used := {}
	var pads: Array[Rect2] = []
	var pipes: Array = []
	for road in roads:
		if str(road.tile) != tid: continue
		var a := Streets.nid(road.a - tile.center)
		var b := Streets.nid(road.b - tile.center)
		used["%s|%s" % [a if a < b else b, b if a < b else a]] = true
	for s in standing:
		if str(s.tile) != tid: continue
		var half := float(s.get("pad", s.side)) * 0.5 + (34.0 if str(s.get("internal_name", "")) == "mine" else 8.0)
		pads.append(Rect2(s.pos - Vector2.ONE * half, Vector2.ONE * half * 2.0))
	for line in lines:
		if not Model.PIPE_MODES.has(str(line.mode)): continue
		for i in range(line.pts.size() - 1): pipes.append([line.pts[i].p, line.pts[i + 1].p])
	var result: Array = []
	for spot in Legacy._tree_spots(tid, str(tile.type)):
		if str(spot.edge) != "" and not used.has(str(spot.edge)): continue
		var p: Vector2 = tile.center + spot.p
		if not Geometry2D.is_point_in_polygon(p, Model.hex_points(tile.center)) or Ground.is_water(relief, p): continue
		var blocked := false
		for pad in pads: blocked = blocked or pad.has_point(p)
		for road in roads:
			blocked = blocked or Geometry2D.get_closest_point_to_segment(p, road.a, road.b).distance_to(p) < float(Legacy._road_widths(int(road.level))[0]) + 4.0
		for seg in pipes: blocked = blocked or Geometry2D.get_closest_point_to_segment(p, seg[0], seg[1]).distance_to(p) < 9.0
		for river in rivers:
			for i in range(river.points.size() - 1):
				blocked = blocked or Geometry2D.get_closest_point_to_segment(p, river.points[i], river.points[i + 1]).distance_to(p) < 16.0
		if not blocked: result.append({"pos": p, "kind": spot.kind, "height": float(Legacy._TREE_HEIGHT[spot.kind]) * float(spot.scale), "edge": spot.edge})
	return result
