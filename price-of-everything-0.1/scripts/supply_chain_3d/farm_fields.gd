extends RefCounted
## Repeated pieces of the reviewed farm. Plot size changes the count, never scale.
const Assets := preload("res://scripts/supply_chain_3d/assets.gd")
const Geo := preload("res://scripts/supply_chain_3d/geometry.gd")
const Index := preload("res://scripts/supply_chain_3d/road_index.gd")
const Roads := preload("res://scripts/empire_board.gd")
## A farm's slot size before the 3D building scale (authored_region.gd sizes farms with it).
const SIDE := 72.0
## The size crop cells and the farmhouse are drawn at: the farm grows with every building.
const DRAWN := SIDE * preload("res://scripts/supply_chain_3d/building_scale.gd").BUILDINGS_SCALE
const SOIL := Color("896b50")
const CROP := Color(0.34, 0.438, 0.263)
const LIFT := 1.25
const ROAD_VERGE := 1.0

static func is_plot(s: Dictionary) -> bool:
	return str(s.get("internal_name", "")) == "farm" and s.get("footprint", []).size() >= 3

static func build(builder: RefCounted, tid: String, standing: Array) -> Dictionary:
	var plots := standing.filter(func(s: Dictionary) -> bool: return is_plot(s) and str(s.tile) == tid)
	if plots.is_empty(): return {}
	plots.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.iid) < str(b.iid))
	var key := Assets.key_for("farm_crop_cell", 1)
	var metadata := Assets.component_for(key)
	var pitch := Vector2(metadata.pitch[0], metadata.pitch[1]) * DRAWN
	var half := Vector2(Assets.dimensions(key).x, Assets.dimensions(key).z) * DRAWN * 0.5
	var soil := Geo.Batch.new()
	var crops := Geo.Batch.new()
	var poses: Array[Transform3D] = []
	var road_masks := road_clearance(builder.roads)
	var occupied: Array = []
	var yards: Array = []
	for farm in standing:
		if not is_plot(farm): continue
		# Nearby plots may overlap or cross a tile boundary. Reserve every barn
		# before planting, independent of the order in which plots are filled.
		if not plots.any(func(s: Dictionary) -> bool: return (s.pos as Vector2).distance_squared_to(farm.pos) < 360000.0): continue
		var dim := Assets.dimensions(Assets.key_for("farm_building", int(farm.get("level", 1)))) * DRAWN
		yards.append({"pos": farm.pos, "angle": -float(farm.get("yaw", 0.0)),
			"box": Rect2(-Vector2(dim.x, dim.z) * 0.5, Vector2(dim.x, dim.z)).grow(3.0 + half.length())})
	for s in plots:
		var polygon: PackedVector2Array = s.footprint
		var angle := -float(s.get("yaw", 0.0))
		var local := PackedVector2Array()
		for p in polygon: local.append((p - s.pos).rotated(-angle))
		var bounds := Rect2(local[0], Vector2.ZERO)
		for p in local: bounds = bounds.expand(p)
		# Clip small soil patches at the actual plot edge. Subdivision follows the
		# height field, rather than placing a flat rectangle over a sloping farm.
		for y in range(floori(bounds.position.y / 8.0), ceili(bounds.end.y / 8.0)):
			for x in range(floori(bounds.position.x / 8.0), ceili(bounds.end.x / 8.0)):
				var square := PackedVector2Array([Vector2(x, y), Vector2(x + 1, y), Vector2(x + 1, y + 1), Vector2(x, y + 1)])
				for i in square.size(): square[i] *= 8.0
				for cut in Geometry2D.intersect_polygons(local, square):
					var world := PackedVector2Array()
					for p in cut: world.append(s.pos + p.rotated(angle))
					var pieces: Array = [world]
					for previous in occupied:
						var remaining: Array = []
						for piece in pieces: remaining.append_array(Geometry2D.clip_polygons(piece, previous))
						pieces = remaining
					# Soil sits above the road surface. Cut its footprint as well as
					# the crops; lowering it would bury fields on graded/sloping roads.
					for road_id in Index.query(road_masks.index, Roads._box_of(world)):
						var remaining: Array = []
						for piece in pieces: remaining.append_array(_subtract_road(piece, road_masks.polygons[road_id]))
						pieces = remaining
					for piece in pieces: _soil(soil, builder, piece)
		var core := Assets.dimensions(Assets.key_for("farm_building", int(s.get("level", 1)))) * DRAWN
		var yard := Rect2(-Vector2(core.x, core.z) * 0.5, Vector2(core.x, core.z)).grow(3.0)
		# Cell centres form a fixed grid. A rejected edge cell leaves an earth
		# margin; it is never squashed to fit the remainder of the polygon.
		for row in range(floori(bounds.position.y / pitch.y), ceili(bounds.end.y / pitch.y)):
			var run := PackedVector2Array()
			for column in range(floori(bounds.position.x / pitch.x), ceili(bounds.end.x / pitch.x)):
				var p := Vector2((column + 0.5) * pitch.x, (row + 0.5) * pitch.y)
				var world: Vector2 = s.pos + p.rotated(angle)
				var allowed: bool = fits(p, half, local, yard) and not builder.open_water(world)
				if allowed:
					for reserved in yards:
						if reserved.box.has_point((world - reserved.pos).rotated(-reserved.angle)):
							allowed = false; break
				for previous in occupied:
					if Geometry2D.is_point_in_polygon(world, previous): allowed = false; break
				if allowed:
					# The radius also covers the full pitch of the far-LOD ribbons.
					var radius := Vector2(maxf(half.x, pitch.x * 0.5), half.y).length()
					for road_id in Index.query(road_masks.index, Rect2(world, Vector2.ZERO).grow(radius)):
						var road: Dictionary = road_masks.roads[road_id]
						if Geometry2D.get_closest_point_to_segment(world, road.a, road.b).distance_to(world) < road.radius + radius:
							allowed = false; break
				if not allowed:
					_ribbons(crops, builder, s.pos, angle, run, pitch.x, half.y)
					run.clear()
					continue
				run.append(p)
				var gradient: Vector2 = builder.surface_gradient(world)
				var up := Vector3(-gradient.x, 1.0, -gradient.y).normalized()
				var along := Vector3(cos(angle), 0.0, sin(angle))
				var across := along.cross(up).normalized()
				along = up.cross(across).normalized()
				poses.append(Transform3D(Basis(along, up, across).scaled(Vector3.ONE * DRAWN), builder.point(world, LIFT + 0.05)))
			_ribbons(crops, builder, s.pos, angle, run, pitch.x, half.y)
		occupied.append(polygon)
	var soil_mesh := soil.mesh()
	return {"soil": soil_mesh, "far": Geo.joined([soil_mesh, crops.mesh()]), "poses": poses}

static func road_clearance(roads: Array) -> Dictionary:
	var result := {"roads": [], "polygons": [], "index": {}}
	for road in roads:
		# A tunnel has no surface carriageway to reserve through a field.
		if road.get("tunnel", false) or (road.a as Vector2).distance_to(road.b) < 0.5: continue
		var radius := float(road.get("widths", Roads._road_widths(int(road.get("level", 1))))[0]) + ROAD_VERGE
		var id: int = result.roads.size()
		result.roads.append({"a": road.a, "b": road.b, "radius": radius})
		result.polygons.append(Roads._capsule(road.a, road.b, radius))
		Index.insert(result.index, Index.bounds(road.a, road.b, radius), id)
	return result

static func _subtract_road(polygon: PackedVector2Array, mask: PackedVector2Array) -> Array:
	var pieces := Geometry2D.clip_polygons(polygon, mask)
	if not pieces.any(func(p: PackedVector2Array) -> bool: return Geometry2D.is_polygon_clockwise(p)):
		return pieces
	# A short road wholly inside a patch leaves a hole. Godot triangulation does
	# not accept hole rings: partition against each convex capsule edge instead.
	var result: Array = []
	var indices := Geometry2D.triangulate_polygon(polygon)
	for i in range(0, indices.size(), 3):
		var inside := PackedVector2Array([polygon[indices[i]], polygon[indices[i + 1]], polygon[indices[i + 2]]])
		for j in mask.size():
			if inside.size() < 3: break
			var a := mask[j]
			var direction := mask[(j + 1) % mask.size()] - a
			var next := PackedVector2Array()
			var outside := PackedVector2Array()
			for k in inside.size():
				var p := inside[k]
				var q := inside[(k + 1) % inside.size()]
				var dp := direction.cross(p - a)
				var dq := direction.cross(q - a)
				if dp >= 0.0: next.append(p)
				else: outside.append(p)
				if (dp < 0.0) != (dq < 0.0):
					var crossing := p.lerp(q, dp / (dp - dq))
					next.append(crossing); outside.append(crossing)
			if outside.size() >= 3: result.append(outside)
			inside = next
	return result

static func fits(p: Vector2, half: Vector2, polygon: PackedVector2Array, yard: Rect2) -> bool:
	if yard.intersects(Rect2(p - half, half * 2.0).grow(0.6)): return false
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		if not Geometry2D.is_point_in_polygon(p + corner * (half + Vector2.ONE * 0.5), polygon): return false
	# Reject cells spanning a concave notch even when all four corners fit.
	var box := Rect2(p - half - Vector2.ONE * 0.5, half * 2.0 + Vector2.ONE)
	for vertex in polygon:
		if box.has_point(vertex): return false
	return Geometry2D.is_point_in_polygon(p, polygon)

static func _soil(batch: RefCounted, builder: RefCounted, polygon: PackedVector2Array) -> void:
	var indices := Geometry2D.triangulate_polygon(polygon)
	for i in range(0, indices.size(), 3):
		var a := polygon[indices[i]]
		var b := polygon[indices[i + 1]]
		var c := polygon[indices[i + 2]]
		if builder.open_water((a + b + c) / 3.0): continue
		var gradient: Vector2 = builder.surface_gradient((a + b + c) / 3.0)
		batch.triangle(builder.point(a, LIFT), builder.point(b, LIFT), builder.point(c, LIFT), SOIL,
			Vector3(-gradient.x, 1.0, -gradient.y).normalized())

static func _ribbons(batch: RefCounted, builder: RefCounted, center: Vector2, angle: float, run: PackedVector2Array, step: float, half_width: float) -> void:
	if run.is_empty(): return
	# Far LOD coalesces the same cells into long strips; cap sections at 8u so
	# they still follow terrain. Both source ribbons retain their earth gap.
	var start := run[0].x - step * 0.5
	var end := run[-1].x + step * 0.5
	var sections := ceili((end - start) / 8.0)
	for row in [-1.0, 1.0]:
		var y: float = run[0].y + row * half_width * 0.5
		var w := half_width * 0.13 / 0.46
		for i in sections:
			var a := lerpf(start, end, float(i) / sections)
			var b := lerpf(start, end, float(i + 1) / sections)
			batch.quad(builder.point(center + Vector2(a, y - w).rotated(angle), LIFT + 2.7),
				builder.point(center + Vector2(a, y + w).rotated(angle), LIFT + 2.7),
				builder.point(center + Vector2(b, y + w).rotated(angle), LIFT + 2.7),
				builder.point(center + Vector2(b, y - w).rotated(angle), LIFT + 2.7), CROP)

static func cells(data: Dictionary, medium: bool) -> MultiMeshInstance3D:
	var node := MultiMeshInstance3D.new()
	var mesh := MultiMesh.new()
	mesh.transform_format = MultiMesh.TRANSFORM_3D
	# Crop .glb.import files disable generated LODs: automatic decimation was
	# collapsing the tiny instanced pieces prematurely. The explicit medium/near
	# derivatives are sufficient and preserve plants and source proportions.
	mesh.mesh = Assets.mesh_for(Assets.key_for("farm_crop_cell_medium" if medium else "farm_crop_cell", 1))
	mesh.instance_count = data.poses.size()
	for i in data.poses.size(): mesh.set_instance_transform(i, data.poses[i])
	node.multimesh = mesh
	node.name = "FarmRowsMedium" if medium else "FarmRowsNear"
	return node
