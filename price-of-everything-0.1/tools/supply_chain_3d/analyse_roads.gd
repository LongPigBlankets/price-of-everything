extends RefCounted
## Read-only inventory of the regular map's visible road geometry and near misses.
const Authored := preload("res://scripts/authored_map.gd")
const Geometry := preload("res://scripts/authored_road_geometry.gd")
const BUCKET := 64.0

static func inspect(main: Node) -> Dictionary:
	var authored: Node = main.get_node("AuthoredRoadVisuals")
	var network_view: Node = main.get_node("RoadNetworkVisuals")
	var terrain: Node = network_view._terrain()
	var flags: Dictionary = network_view._flagged_tiles(terrain)
	var strokes: Array = authored._visible_strokes(authored._flagged_tile_ids())
	var roads := []
	for stroke in strokes:
		# Measure the route before visual wobble: jitter must not define topology.
		roads.append({"id": "authored:" + str(stroke.id), "points": Geometry.sample(stroke)})
	var network := RoadNetwork.instance()
	var visible_edges := 0
	for id in network.edges:
		var edge: Dictionary = network.edges[id]
		if str(edge.state) != RoadNetwork.STATE_BUILT: continue
		var runs: Array = [edge.geometry] if network_view._all_tiles_flagged(edge.tiles, flags) else network_view._clip_to_built(edge.geometry, terrain, flags)
		if not runs.is_empty(): visible_edges += 1
		for i in runs.size(): roads.append({"id": "network:%s:%d" % [id, i], "points": runs[i]})
	var segments := {}
	var vertices := 0
	for road in roads:
		var points: PackedVector2Array = road.points
		vertices += points.size()
		for i in range(1, points.size()):
			var rect := Rect2(points[i - 1], Vector2.ZERO).expand(points[i]).grow(2.0)
			var lo := Vector2i((rect.position / BUCKET).floor())
			var hi := Vector2i((rect.end / BUCKET).floor())
			for y in range(lo.y, hi.y + 1):
				for x in range(lo.x, hi.x + 1):
					(segments.get_or_add(Vector2i(x, y), []) as Array).append({"id": road.id, "a": points[i - 1], "b": points[i]})
	var connected := 0
	var candidates := []
	for road in roads:
		var points: PackedVector2Array = road.points
		if points.size() < 2: continue
		for index in [0, points.size() - 1]:
			var point := points[index]
			var best := INF
			var target := {}
			for segment in segments.get(Vector2i((point / BUCKET).floor()), []):
				if segment.id == road.id: continue
				var nearest := Geometry2D.get_closest_point_to_segment(point, segment.a, segment.b)
				var distance := point.distance_to(nearest)
				if distance < best:
					best = distance
					target = {"source": road.id, "target": segment.id, "gap": distance, "at": point, "join": nearest}
			if best <= 0.01: connected += 1
			elif best <= 2.0: candidates.append(target)
	return {"active_document": Authored.active_path(), "visible_authored_strokes": strokes.size(),
		"network_edges_total": network.edges.size(), "visible_network_edges": visible_edges,
		"visible_polylines": roads.size(), "vertices_before_styling": vertices,
		"xy_float32_bytes": vertices * 8, "exact_connected_endpoints": connected,
		"near_endpoints_within_2u": candidates.size(), "near_candidates": candidates,
		"note": "Candidates only, not approved joins: bridge/elevation, water and branch checks still needed. No data modified."}
