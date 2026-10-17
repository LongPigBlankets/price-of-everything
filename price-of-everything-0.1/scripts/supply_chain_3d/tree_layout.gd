extends RefCounted
## Source species, seeds and roadside rows, with the same clearance rules. Shared
## candidate generation keeps the 2D and 3D versions' landscape composition aligned.
const Legacy := preload("res://scripts/empire_board.gd")
const Model := preload("res://scripts/empire_board_model.gd")
const Ground := preload("res://scripts/empire_board_ground.gd")
const Streets := preload("res://scripts/empire_board_streets.gd")
const Assets := preload("res://scripts/supply_chain_3d/assets.gd")
const Placement := preload("res://scripts/supply_chain_3d/road_placement.gd")
const Sidewalks := preload("res://scripts/supply_chain_3d/urban_sidewalks.gd")
const SIZES := [1.0, 0.75, 0.5]

static func size_for(tid: String, spot: Dictionary) -> float:
	return SIZES[posmod(hash(tid + ":" + str(spot.p) + ":" + str(spot.kind)), SIZES.size())]

static func canopy(tree: Dictionary) -> float:
	var key := Assets.key_for("tree", {"small": 1, "fir": 2, "large": 3}[tree.kind])
	var dimension := Assets.dimensions(key)
	return maxf(dimension.x, dimension.z) * float(tree.height) / Assets.projected_height(key) * 0.5

static func placements(tid: String, tile: Dictionary, relief: Dictionary, standing: Array,
		roads: Array, lines: Array, rivers: Array, corridor: RefCounted = null, height: Callable = Callable()) -> Array:
	if str(tile.type) in ["sea", "deep_sea", "mountain"]: return []
	var used := {}
	var pads: Array[Rect2] = []
	var shapes: Array = []
	var pipes: Array = []
	for road in roads:
		if str(road.tile) != tid: continue
		var a := Streets.nid(road.a - tile.center)
		var b := Streets.nid(road.b - tile.center)
		used["%s|%s" % [a if a < b else b, b if a < b else a]] = true
	for s in standing:
		if s.has("harbour"):
			pads.append((s.harbour.bounds as Rect2).grow(8.0))
			continue # piers and yards can occupy a neighbouring tile
		if Placement.exact_building(s) and s.has("footprints"):
			shapes.append_array(s.footprints)
			continue
		if s.has("footprint") and not s.footprint.is_empty():
			var box := Rect2(s.footprint[0], Vector2.ZERO)
			for p in s.footprint: box = box.expand(p)
			pads.append(box.grow(34.0 if str(s.get("internal_name", "")) == "mine" else 8.0))
			continue
		if str(s.tile) != tid: continue
		var half := float(s.get("pad", s.side)) * 0.5 + (34.0 if str(s.get("internal_name", "")) == "mine" else 8.0)
		pads.append(Rect2(s.pos - Vector2.ONE * half, Vector2.ONE * half * 2.0))
	for line in lines:
		if not Model.PIPE_MODES.has(str(line.mode)): continue
		for i in range(line.pts.size() - 1): pipes.append([line.pts[i].p, line.pts[i + 1].p])
	var result: Array = []
	var candidates: Array = []
	for spot in Legacy._tree_spots(tid, str(tile.type)):
		if str(spot.edge) != "" and not used.has(str(spot.edge)): continue
		var p: Vector2 = tile.center + spot.p
		var size := 0.5 if corridor != null and corridor.beside_rail(p) else size_for(tid, spot)
		candidates.append({"pos": p, "kind": spot.kind, "height": float(Legacy._TREE_HEIGHT[spot.kind]) * float(spot.scale) * size,
			"size_scale": size, "edge": spot.edge})
	if corridor != null: candidates.append_array(corridor.rows.get(tid, []))
	for tree in candidates:
		var p: Vector2 = tree.pos
		if not Geometry2D.is_point_in_polygon(p, Model.hex_points(tile.center)) or Ground.is_water(relief, p): continue
		var radius := canopy(tree)
		if corridor != null and not corridor.clear(p, radius): continue
		var blocked := false
		for pad in pads: blocked = blocked or pad.has_point(p)
		for shape in shapes: blocked = blocked or Placement.distance_to_polygon(p,p,shape) < radius
		for road in roads:
			if road.get("tunnel", false): continue
			blocked = blocked or Geometry2D.get_closest_point_to_segment(p, road.a, road.b).distance_to(p) < float(road.get("widths", Legacy._road_widths(int(road.level)))[0]) + maxf(4.0, Sidewalks.width(road) + radius)
		for seg in pipes: blocked = blocked or Geometry2D.get_closest_point_to_segment(p, seg[0], seg[1]).distance_to(p) < 9.0
		for river in rivers:
			for i in range(river.points.size() - 1):
				blocked = blocked or Geometry2D.get_closest_point_to_segment(p, river.points[i], river.points[i + 1]).distance_to(p) < 16.0
		if tree.get("source", "") == "rail_row":
			for other in result:
				if p.distance_to(other.pos) < radius + canopy(other) + 1.0: blocked = true; break
			if height.is_valid():
				var base := float(height.call(p))
				for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
					if absf(float(height.call(p + direction * radius)) - base) > 4.0: blocked = true
		if not blocked: result.append(tree)
	return result
