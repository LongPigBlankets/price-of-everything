extends RefCounted
## Deterministic local geometry prepared offline and retained with each base tile.
const Geo := preload("res://scripts/supply_chain_3d/geometry.gd")
const Legacy := preload("res://scripts/empire_board.gd")
const Model := preload("res://scripts/empire_board_model.gd")
const Ground := preload("res://scripts/empire_board_ground.gd")
const Assets := preload("res://scripts/supply_chain_3d/assets.gd")
const Sprites := preload("res://scripts/supply_chain_3d/far_sprites.gd")

static func build(builder: RefCounted, tid: String, standing: Array) -> Dictionary:
	var tile: Dictionary = builder.tiles[tid]
	var rel := Legacy._relief_of(tid, tile.center)
	var land := str(tile.type) not in ["sea", "deep_sea"]
	return {"clutter_mesh": clutter(builder, tid, standing) if land else ArrayMesh.new(),
		"glint_mesh": glints(builder, tid, tile, rel),
		"tree_cards": tree_cards(builder, tid, standing) if land else {}}

static func tree_cards(builder: RefCounted, tid: String, standing: Array) -> Dictionary:
	var cards := {}
	for tree in builder.placements_for(tid, standing):
		var key := Assets.key_for("tree", {"small": 1, "fir": 2, "large": 3}[tree.kind])
		var scale := float(tree.height) / Assets.projected_height(key)
		(cards.get_or_add(tree.kind, []) as Array).append(Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * scale),
			builder.point(tree.pos) + Sprites.center(key) * scale))
	return cards

static func clutter(builder: RefCounted, tid: String, standing: Array) -> Mesh:
	var near := Geo.Batch.new()
	var c: Vector2 = builder.tiles[tid].center
	var rel := Legacy._relief_of(tid, c)
	var area := Rect2(c - Model.HEX_HALF, Model.HEX_HALF * 2.0).grow(30.0)
	var local_roads: Array = builder.roads.filter(func(road: Dictionary) -> bool: return area.intersects(Rect2(road.a, Vector2.ZERO).expand(road.b).grow(20.0)))
	var local_standing := standing.filter(func(item: Dictionary) -> bool: return (item.pos as Vector2).distance_squared_to(c) < 500000.0)
	# Retain close-up ground detail without replacing the source tree composition.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(tid)
	for i in 130:
		var p := c + Vector2(rng.randf_range(-260, 260), rng.randf_range(-235, 235))
		if not builder._plantable(p, tid, rel, local_standing, 6.0, local_roads): continue
		var foot: Vector3 = builder.point(p, 0.2)
		if i % 7 == 0:
			# Sparse stones belong on exposed slopes; uniformly scattered grey
			# pebbles made the source board's clear grass read as visual noise.
			if i % 21 != 0 or builder.surface_gradient(p).length() < 0.25: continue
			builder._crown(near, foot + Vector3.UP * 0.55, Vector3(1.5, 1.1, 1.2), Color("85816b"), 5)
		else:
			for j in 3:
				var angle := float(j) * PI / 3.0
				var side := Vector3(cos(angle), 0, sin(angle)) * 0.6
				near.triangle(foot - side, foot + Vector3.UP * rng.randf_range(1.5, 3.2), foot + side, Color("81834c"))
	return near.mesh()

static func glints(builder: RefCounted, tid: String, tile: Dictionary, relief: Dictionary) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("glint|" + tid)
	var batch := Geo.Batch.new()
	var found := 0
	var ocean := str(tile.type) in ["sea", "deep_sea"]
	for attempt in 140:
		if found >= Legacy._GLINTS_PER_TILE: break
		var p: Vector2 = tile.center + Vector2(rng.randf_range(-270, 270), rng.randf_range(-240, 240))
		if not Geometry2D.is_point_in_polygon(p, Model.hex_points(tile.center)): continue
		if not ocean and not Ground.is_water(relief, p): continue
		var phase := rng.randf() * TAU
		var rate := rng.randf_range(0.7, 1.3)
		# A rounded pill on the water, not a camera-facing billboard.
		var polygon := Legacy._capsule(p - Vector2(5, 0), p + Vector2(5, 0), 0.8, [true, true])
		var tris := Geometry2D.triangulate_polygon(polygon)
		for i in range(0, tris.size(), 3):
			batch.triangle(builder.point(polygon[tris[i]], 0.35), builder.point(polygon[tris[i + 1]], 0.35), builder.point(polygon[tris[i + 2]], 0.35), Color.WHITE)
		while batch.uvs.size() < batch.vertices.size(): batch.uvs.append(Vector2(phase, rate))
		found += 1
	return batch.mesh()
