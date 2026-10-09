extends RefCounted
## Builds the supply-chain world's static geometry. Map-space coordinates and the shared
## height field are authoritative; the camera never participates in generation.
const Geo := preload("res://scripts/supply_chain_3d/geometry.gd")
const Legacy := preload("res://scripts/empire_board.gd")
const Model := preload("res://scripts/empire_board_model.gd")
const Ground := preload("res://scripts/empire_board_ground.gd")
const Assets := preload("res://scripts/supply_chain_3d/assets.gd")
const CELL := 12.0
const Detail := preload("res://scripts/supply_chain_3d/detail.gd")
const Paint := preload("res://scripts/supply_chain_3d/terrain_paint.gd")
const GroundShader := preload("res://scripts/supply_chain_3d/ground.gdshader")
const TreeLayout := preload("res://scripts/supply_chain_3d/tree_layout.gd")
const GlintShader := preload("res://scripts/supply_chain_3d/water_glints.gdshader")
const RoadSurface := preload("res://scripts/supply_chain_3d/road_surface.gd")
var terrain_lods: Array = []
var detail_nodes: Array = []
var building_visuals: Array = []
var grade_range := Vector2.ZERO
var active_lod := -1
var shadow_batch := Geo.Batch.new()
var origin := Vector2.ZERO
var ground: RefCounted
var rivers: Dictionary = {}
var tiles: Dictionary = {}
var terrain_cache: Dictionary = {}
var mat := ShaderMaterial.new()
var line_mat := Geo.material(true)
var bounds := AABB()
var pickables: Array = []
var labels: Array = []
var flows: Array = []
var cars: Array = []
var smoke: Array = []
var glows: Array = []
var roads: Array = []
var lines: Array = []
var tree_placements: Dictionary = {}
var road_surface := RoadSurface.new()
var pits: Dictionary = {}

func configure_pits(standing: Array) -> void:
	pits.clear()
	for s in standing:
		if str(s.get("internal_name", "")) != "mine": continue
		var data := Assets.pit_for(int(s.get("level", 1)))
		if data.is_empty(): continue
		var rim := PackedVector2Array()
		var side := float(s.get("side", 80.0))
		for xy in data.rim: rim.append((s.pos as Vector2) + Vector2(xy[0], xy[1]) * side)
		var area := Rect2(rim[0], Vector2.ZERO)
		for p in rim: area = area.expand(p)
		pits[str(s.iid)] = {"rim": rim, "area": area, "tile": str(s.tile), "height": ground.height(s.pos),
			"sink": float(data.sink) * side, "step": float(data.step) * side, "pos": s.pos, "side": side, "seed": hash(str(s.iid))}

func _mine_grade(p: Vector2) -> Vector2:
	var result := Vector2.ZERO # weight, mine datum
	for pit in pits.values():
		var distance := p.distance_to(pit.pos) / float(pit.side)
		if distance >= 0.80: continue
		var weight := 1.0 - smoothstep(0.62, 0.80, distance)
		if weight > result.x: result = Vector2(weight, pit.height)
	return result

func surface_height(p: Vector2) -> float:
	var grade := _mine_grade(p)
	return lerpf(ground.height(p), grade.y, grade.x)

func surface_gradient(p: Vector2) -> Vector2:
	var grade := _mine_grade(p)
	if grade.x == 0.0: return ground.gradient(p)
	if grade.x == 1.0: return Vector2.ZERO
	return Vector2(surface_height(p + Vector2.RIGHT) - surface_height(p - Vector2.RIGHT),
		surface_height(p + Vector2.DOWN) - surface_height(p - Vector2.DOWN)) * 0.5

func _cut_pits(poly: PackedVector2Array) -> Array[PackedVector2Array]:
	var parts: Array[PackedVector2Array] = [poly]
	var bounds := Rect2(poly[0], Vector2.ZERO)
	for p in poly: bounds = bounds.expand(p)
	for pit in pits.values():
		if not bounds.intersects(pit.area): continue
		var cut: Array[PackedVector2Array] = []
		for part in parts: cut.append_array(Geometry2D.clip_polygons(part, pit.rim))
		parts = cut
	return parts

func mine_rims_node() -> MeshInstance3D:
	# The sprite cut pass kept the first inward-facing wall of the removed earth
	# block. In 3D it joins the terrain opening to the first submerged bench.
	var batch := Geo.Batch.new()
	for pit in pits.values():
		var rim: PackedVector2Array = pit.rim
		for i in rim.size():
			var a := rim[i]
			var b := rim[(i + 1) % rim.size()]
			var steps := maxi(1, ceili(a.distance_to(b) / 3.0))
			for j in steps:
				var p := a.lerp(b, float(j) / steps)
				var q := a.lerp(b, float(j + 1) / steps)
				var h: float = pit.height - pit.step
				batch.quad(point(p, 0.08), point(q, 0.08), at_height(q, h), at_height(p, h), Color(0.310, 0.273, 0.226))
	var material := Assets.mesh_for(Assets.key_for("mine", 1)).surface_get_material(0)
	return Geo.instance(batch.mesh(), material)

func point(p: Vector2, lift: float = 0.0) -> Vector3:
	return Vector3(p.x - origin.x, surface_height(p) + lift, p.y - origin.y)

func at_height(p: Vector2, height: float) -> Vector3:
	return Vector3(p.x - origin.x, height, p.y - origin.y)

func configure_grade() -> void:
	grade_range = Vector2(INF, -INF)
	for tile in tiles.values():
		for p in Model.hex_points(tile.center):
			var y := Legacy.iso(p, ground.height(p)).y
			grade_range.x = minf(grade_range.x, y)
			grade_range.y = maxf(grade_range.y, y)
	mat.shader = GroundShader
	mat.set_shader_parameter("grade_range", grade_range)
	Assets.set_grade(grade_range)

func terrain_key(tid: String) -> String:
	var holes: Array = []
	var bounds := Rect2((tiles[tid].center as Vector2) - Model.HEX_HALF, Model.HEX_HALF * 2.0)
	for pit in pits.values():
		var reach := float(pit.side) * 0.80
		if bounds.intersects(Rect2((pit.pos as Vector2) - Vector2.ONE * reach, Vector2.ONE * reach * 2.0)):
			holes.append([pit.rim, pit.height, pit.seed])
	return "%s:%s:%s" % [tid, ground.get_instance_id(), hash([MapStyle.band_colors(), MapStyle.sea_colors(), holes])]

func prepare_tile(host: Node, tid: String) -> void:
	var key := terrain_key(tid)
	if terrain_cache.has(key): return
	var textures := await Paint.bake(host, tiles[tid], Legacy._relief_of(tid, tiles[tid].center), rivers.get(tid, []), pits.values(), surface_height)
	var meshes: Array = []
	for cell in Detail.CELLS:
		meshes.append(_surface(tid, cell))
		await host.get_tree().process_frame
	terrain_cache[key] = {"textures": textures, "meshes": meshes}

func _surface(tid: String, cell: float) -> ArrayMesh:
	var center: Vector2 = tiles[tid].center
	var hex := Model.hex_points(center)
	var batch := Geo.Batch.new()
	var low := ((center - Model.HEX_HALF) / cell).floor()
	var high := ((center + Model.HEX_HALF) / cell).ceil()
	for y in range(int(low.y), int(high.y)):
		for x in range(int(low.x), int(high.x)):
			var a := Vector2(x, y) * cell
			var square := PackedVector2Array([a, a + Vector2(cell, 0), a + Vector2(cell, cell), a + Vector2(0, cell)])
			for tile_part in Geometry2D.intersect_polygons(square, hex):
				for poly in _cut_pits(tile_part):
					var indices := Geometry2D.triangulate_polygon(poly)
					for i in range(0, indices.size(), 3):
						var before := batch.vertices.size()
						batch.triangle(point(poly[indices[i]]), point(poly[indices[i + 2]]), point(poly[indices[i + 1]]), Color.WHITE)
						for j in range(before, batch.vertices.size()):
							var v: Vector3 = batch.vertices[j]
							var grad := surface_gradient(Vector2(v.x, v.z) + origin)
							batch.normals[j] = Vector3(-grad.x, 1, -grad.y).normalized()
	return batch.mesh(Rect2(center - origin - Paint.EXTENT * 0.5, Paint.EXTENT))

func tile_node(tid: String) -> Node3D:
	var tile: Dictionary = tiles[tid]
	var center: Vector2 = tile.center
	var root := Node3D.new()
	root.name = tid
	var data: Dictionary = terrain_cache[terrain_key(tid)]
	var surface: ArrayMesh = data.meshes[0]
	var paint := mat.duplicate() as ShaderMaterial
	paint.set_shader_parameter("textured", true)
	if not data.textures.is_empty(): paint.set_shader_parameter("artwork", data.textures[0])
	var land := Geo.instance(surface, paint)
	land.name = "Terrain"
	root.add_child(land)
	terrain_lods.append({"node": land, "material": paint, "data": data})
	# Picking remains the same through LOD changes; the shared spline is authoritative.
	var body := StaticBody3D.new()
	body.name = "TilePick"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("tile_id", tid)
	var collider := CollisionShape3D.new()
	collider.shape = surface.create_trimesh_shape()
	body.add_child(collider)
	root.add_child(body)
	var rim := Geo.Batch.new()
	var lip := Geo.Batch.new()
	var relief: Dictionary = Legacy._relief_of(tid, center)
	var is_sea := str(tile.type) in ["sea", "deep_sea"]
	var sea := MapStyle.sea_colors()
	var hex := Model.hex_points(center)
	var centers: Dictionary = {}
	for t in tiles.values(): centers[Vector2i((t.center as Vector2).round())] = true
	for i in 6:
		var a: Vector2 = hex[i]
		var b: Vector2 = hex[(i + 1) % 6]
		if centers.has(Vector2i((a + b - center).round())): continue
		var steps := ceili(a.distance_to(b) / 4.0)
		for j in steps:
			var pa := a.lerp(b, float(j) / steps)
			var pb := a.lerp(b, float(j + 1) / steps)
			var ah := surface_height(pa)
			var bh := surface_height(pb)
			# Coast cutaways keep the original blue water depth above the strata;
			# dry land has a thin turf lip. Both follow the real surface at every edge.
			var inward := (center - (pa + pb) * 0.5).normalized()
			var edge_width := (b - a).orthogonal().normalized() * Legacy._INK_W * 0.65
			lip.quad(point(pa - edge_width, 0.12), point(pb - edge_width, 0.12),
				point(pb + edge_width, 0.12), point(pa + edge_width, 0.12), Legacy._INK)
			var wet := is_sea or Ground.is_water(relief, (pa + pb) * 0.5 + inward * 3.0)
			var depth := Legacy._WATER_DEPTH if wet else Legacy._TURF
			var first_lip := lip.vertices.size()
			lip.quad(at_height(pa, ah), at_height(pb, bh), at_height(pb, bh - depth), at_height(pa, ah - depth),
				sea[4].lightened(0.12) if wet else Legacy._warm(sea[5]).darkened(0.38))
			if wet:
				for k in range(first_lip, lip.vertices.size()):
					var v: Vector3 = lip.vertices[k]
					var h := surface_height(Vector2(v.x, v.z) + origin)
					lip.colors[k] = sea[4].lightened(0.12).lerp(sea[1], clampf((h - v.y) / depth, 0.0, 1.0))
				lip.quad(at_height(pa, ah - depth), at_height(pb, bh - depth),
					at_height(pb, bh - depth - 1.6), at_height(pa, ah - depth - 1.6), Legacy._INK)
			ah -= depth
			bh -= depth
			rim.quad(at_height(pa, ah), at_height(pb, bh), at_height(pb, -150.0), at_height(pa, -150.0), Color.WHITE)
			var ua := float(j) / steps
			var ub := float(j + 1) / steps
			var va := (100.0 - ah) / 250.0
			var vb := (100.0 - bh) / 250.0
			rim.uvs.append_array(PackedVector2Array([Vector2(ua, va), Vector2(ub, 1), Vector2(ub, vb), Vector2(ua, va), Vector2(ua, 1), Vector2(ub, 1)]))
	var strata := mat.duplicate() as ShaderMaterial
	strata.set_shader_parameter("textured", true)
	strata.set_shader_parameter("strata", true)
	strata.set_shader_parameter("artwork", load("res://assets/iso/ground/strata.png"))
	root.add_child(Geo.instance(rim.mesh(), strata))
	root.add_child(Geo.instance(lip.mesh(), mat))
	root.add_child(water_glints(tid, tile, relief))
	labels.append({"tile": tid, "text": tile.label, "point": point(center + Vector2(135, 240) * 0.72, 4.0)})
	return root

func water_glints(tid: String, tile: Dictionary, relief: Dictionary) -> MeshInstance3D:
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
			batch.triangle(point(polygon[tris[i]], 0.35), point(polygon[tris[i + 1]], 0.35), point(polygon[tris[i + 2]], 0.35), Color.WHITE)
		while batch.uvs.size() < batch.vertices.size(): batch.uvs.append(Vector2(phase, rate))
		found += 1
	var material := ShaderMaterial.new()
	material.shader = GlintShader
	return Geo.instance(batch.mesh(), material)

func set_detail(tier: int) -> void:
	if tier == active_lod: return
	active_lod = tier
	for item in terrain_lods:
		item.node.mesh = item.data.meshes[tier]
		if item.data.textures.size() == 3: item.material.set_shader_parameter("artwork", item.data.textures[tier])
	for item in detail_nodes: item.node.visible = tier >= int(item.minimum)
	# Imported glTF mesh LODs handle individual buildings as projected size changes.
	for visual in building_visuals: visual.lod_bias = [0.8, 1.2, 2.0][tier]
	Assets.set_detail(tier)

func add_detail(parent: Node3D, mesh: Mesh, minimum: int) -> void:
	var node := Geo.instance(mesh, mat)
	parent.add_child(node)
	detail_nodes.append({"node": node, "minimum": minimum})

func shadow(p: Vector2, side: float, tree: bool = false) -> void:
	# The old board's north-west shadow, with a feathered perimeter and soft contact.
	var throw := Vector2(-0.70710678, -0.70710678) * side * 0.38
	var center := p + throw * 0.45
	var radii := Vector2(side * 0.62, side * 0.48) if tree else Vector2(side * 0.69, side * 0.69)
	var count := 16
	for ring in 4:
		var r0 := float(ring) / 4.0
		var r1 := float(ring + 1) / 4.0
		for j in count:
			var a := TAU * j / count
			var b := TAU * (j + 1) / count
			var pa := center + Vector2(cos(a), sin(a)) * radii * r0
			var pb := center + Vector2(cos(b), sin(b)) * radii * r0
			var pc := center + Vector2(cos(b), sin(b)) * radii * r1
			var pd := center + Vector2(cos(a), sin(a)) * radii * r1
			var start := shadow_batch.colors.size()
			shadow_batch.quad(point(pa, 1.0), point(pb, 1.0), point(pc, 1.0), point(pd, 1.0), Color(0.04, 0.06, 0.14, 0.12))
			# Vertex alpha makes the edge soft without translucent overlapping disks.
			for k in range(start, shadow_batch.vertices.size()):
				var v: Vector3 = shadow_batch.vertices[k]
				var dist := ((Vector2(v.x, v.z) + origin - center) / radii).length()
				shadow_batch.colors[k].a = 0.17 * (1.0 - smoothstep(0.35, 1.0, dist))

func shadows_node() -> MeshInstance3D:
	var material := Geo.material(true)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return Geo.instance(shadow_batch.mesh(), material)

func ribbon(batch: RefCounted, path: PackedVector2Array, width: float, color: Color, lift: float, road: bool = false) -> void:
	for i in range(path.size() - 1):
		var a := path[i]
		var b := path[i + 1]
		var normal := (b - a).orthogonal().normalized() * width * 0.5
		var steps := maxi(1, ceili(a.distance_to(b) / 9.0))
		for j in steps:
			var p := a.lerp(b, float(j) / steps)
			var q := a.lerp(b, float(j + 1) / steps)
			if road:
				batch.quad(at_height(p - normal, road_height(p) + lift), at_height(q - normal, road_height(q) + lift),
					at_height(q + normal, road_height(q) + lift), at_height(p + normal, road_height(p) + lift), color)
			else:
				batch.quad(point(p - normal, lift), point(q - normal, lift), point(q + normal, lift), point(p + normal, lift), color)

## Keep streets and traffic over a river valley rather than diving into its water.
func road_height(p: Vector2) -> float:
	var h := surface_height(p)
	for tid in rivers:
		if not tiles.has(tid) or (tiles[tid].center as Vector2).distance_squared_to(p) > 360000.0: continue
		for rec in rivers[tid]:
			var line: PackedVector2Array = rec.points
			var half := (float(rec.start_width) + float(rec.end_width)) * 0.25 + 17.0
			for k in range(line.size() - 1):
				var closest := Geometry2D.get_closest_point_to_segment(p, line[k], line[k + 1])
				if closest.distance_squared_to(p) < half * half:
					var n := (line[k + 1] - line[k]).orthogonal().normalized() * (half + 20.0)
					h = maxf(h, maxf(ground.height(closest - n), ground.height(closest + n)) + 2.0)
	return h

func infrastructure(model: Dictionary, show: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Infrastructure"
	var streets := Geo.Batch.new()
	var details := Geo.Batch.new()
	roads = model.get("roads", [])
	lines = model.get("lines", [])
	if bool(show["roads"]):
		road_surface.configure(roads, road_height, origin)
		for tid in tiles:
			var surface := Geo.instance(road_surface.mesh_for(str(tid)), mat)
			surface.name = "JoinedRoads_" + str(tid).validate_node_name()
			root.add_child(surface)
		road_surface.finish_build()
		for rec in roads:
			var a: Vector2 = rec.a
			var b: Vector2 = rec.b
			var across := (b - a).orthogonal().normalized()
			var half := float(Legacy._road_widths(int(rec.level))[0])
			if int(rec.level) > 1 and bool(rec.get("paved", true)):
				for k in range(1, int(a.distance_to(b) / 55.0)):
					var p := a.move_toward(b, k * 55.0) + across * (half + 1.5)
					var foot := at_height(p, road_height(p) + 1.0)
					streets.tube(foot, foot + Vector3.UP * 14, 0.55, Color("50565e"), 5)
					streets.box(foot + Vector3(0, 14, 0), Vector3(2.5, 1.3, 2.5), Color("efd68e"))
					if int(tiles.get(str(rec.get("tile", "")), {}).get("polluters", 0)) > 0:
						glows.append({"point": foot + Vector3.UP * 14, "size": Vector2(15, 15)})
			if a.distance_to(b) > 80.0:
				cars.append({"a": a, "b": b, "phase": fmod(absf(float(hash(str(a)))), 100.0) / 100.0})
	root.add_child(Geo.instance(streets.mesh(), mat))
	var tubes := Geo.Batch.new()
	for rec in model.get("lines", []):
		var mode := str(rec.get("mode", ""))
		if not bool(show.get(mode, true)): continue
		var path: Array = rec.get("pts", [])
		for i in range(path.size() - 1):
			var a: Vector2 = path[i].p
			var b: Vector2 = path[i + 1].p
			if mode == "rails":
				var line := PackedVector2Array([a, b])
				ribbon(tubes, line, 10.0, Color("766956"), 2.0, true)
				var across := (b - a).orthogonal().normalized() * 2.4
				for k in int(a.distance_to(b) / 6.0):
					var p := a.move_toward(b, k * 6.0)
					ribbon(details, PackedVector2Array([p - across * 1.7, p + across * 1.7]), 1.3, Color("524939"), 2.6, true)
				for sign_v in [-1.0, 1.0]:
					ribbon(tubes, PackedVector2Array([a + across * sign_v, b + across * sign_v]), 0.9, Color("d7d4c0"), 2.8, true)
			else:
				var cable := mode == "cables"
				var count := maxi(2, ceili(a.distance_to(b) / 12.0))
				var previous := Vector3.ZERO
				for j in range(count + 1):
					var t := float(j) / count
					var p := a.lerp(b, t)
					var h := lerpf(ground.height(a), ground.height(b), t) + 62.0 - sin(t * PI) * 12.0 if cable else road_height(p) + 5.5
					var current := at_height(p, h)
					if j > 0: tubes.tube(previous, current, 0.8 if cable else 2.4, Color("d6b560") if cable else (Color("a0a7aa") if mode == "reinf_pipes" else Color("b78552")))
					previous = current
	root.add_child(Geo.instance(tubes.mesh(), mat))
	add_detail(root, details.mesh(), 1)
	return root

func standing_node(s: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = str(s["iid"]).validate_node_name()
	var kind := str(s["kind"])
	var family := str(s.get("internal_name", ""))
	if kind == "warehouse" or kind == "suppliers": family = "warehouse"
	elif kind == "port": family = "port"
	elif kind == "pylon": family = "pylon"
	elif kind == "site": family = "construction_site"
	elif kind == "house": family = "towers" if bool(s.get("tall", false)) else "house"
	var level := int(s.get("level", 1))
	# Decorative metadata uses level 3 for footprint sizing, while its chosen sprite
	# carries the actual house/tower variety. Preserve that variety in the 3D mesh.
	if kind == "house" and s.get("sprite") is Texture2D:
		var filename: String = s.sprite.resource_path.get_file().get_basename()
		if filename.begins_with(family + "_lvl"):
			level = filename.trim_prefix(family + "_lvl").to_int()
	var key := Assets.key_for(family, level)
	var mesh: Mesh = Assets.mesh_for(key)
	var side := float(s.get("side", 80.0))
	var p: Vector2 = s.pos
	var floor_h := surface_height(p)
	var low_h := floor_h
	var half := side * 0.42
	for off in [Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)]:
		var h := surface_height(p + off)
		floor_h = maxf(floor_h, h)
		low_h = minf(low_h, h)
	var pit: Dictionary = pits.get(str(s.iid), {})
	if not pit.is_empty(): floor_h = float(pit.height)
	root.position = at_height(p, floor_h - float(pit.sink) if not pit.is_empty() else floor_h + 1.0)
	var dimension := Assets.dimensions(key) * side
	var visual := MeshInstance3D.new()
	if mesh != null:
		visual.mesh = mesh
		visual.scale = Vector3.ONE * side
	else:
		# Unmodelled catalog types still have solid geometry and truthful picking bounds.
		var box := BoxMesh.new()
		box.size = Vector3(side * 0.8, side * 0.55, side * 0.65)
		visual.mesh = box
		visual.position.y = box.size.y * 0.5
		var fallback := StandardMaterial3D.new()
		fallback.albedo_color = Color("cbc6a8")
		visual.material_override = fallback
		dimension = box.size
	if mesh != null and int(tiles.get(str(s.tile), {}).get("polluters", 0)) > 0 and kind != "pylon" and family != "mine":
		visual.material_override = Assets.lit_material(family == "towers")
		glows.append({"point": root.position + Vector3(0, dimension.y * 0.3, side * 0.45), "size": Vector2(side * 1.3, side * 0.7)})
	root.add_child(visual)
	building_visuals.append(visual)
	var contour := Assets.contour_for(key)
	if contour != null:
		var outline := MeshInstance3D.new()
		outline.name = "OuterContour"
		outline.mesh = contour
		outline.scale = visual.scale
		root.add_child(outline)
		building_visuals.append(outline)
	if kind != "pylon" and pit.is_empty(): shadow(p, side)
	# Match the source board: foundations bridge uneven ground, rather than adding
	# a concrete square under every building whose asset already contains its footing.
	if pit.is_empty() and floor_h - low_h > 0.75:
		var plinth := Geo.Batch.new()
		var depth := floor_h - low_h + 1.0
		plinth.box(Vector3(0, -depth * 0.5, 0), Vector3(side * 0.96, depth, side * 0.96), Color("999786"))
		root.add_child(Geo.instance(plinth.mesh(), mat))

	if kind in ["building", "site", "warehouse", "suppliers"]:
		var body := StaticBody3D.new()
		body.collision_layer = 2 if pit.is_empty() else 3
		body.collision_mask = 0
		body.set_meta("standing", s)
		body.set_meta("tile_id", str(s.tile))
		var shape := BoxShape3D.new()
		shape.size = dimension.max(Vector3.ONE * 6.0)
		if not pit.is_empty(): shape.size.y = maxf(shape.size.y, float(pit.sink) + 3.0)
		var collider := CollisionShape3D.new()
		collider.shape = shape
		collider.position.y = shape.size.y * 0.5
		body.add_child(collider)
		root.add_child(body)
	pickables.append({"iid": s.iid, "kind": kind, "tile": s.tile, "point": root.position + Vector3.UP * dimension.y * 0.5, "top": root.position + Vector3.UP * (dimension.y + 12.0), "size": dimension})
	if bool(s.get("polluting", false)):
		smoke.append({"point": root.position + Vector3.UP * dimension.y, "radius": maxf(4.0, side * 0.08)})
	return root

func trees_node(tid: String, standing: Array) -> Node3D:
	var root := Node3D.new()
	root.name = "LandscapeDetail"
	var near := Geo.Batch.new()
	var c: Vector2 = tiles[tid].center
	var rel: Dictionary = Legacy._relief_of(tid, c)
	var placements := TreeLayout.placements(tid, tiles[tid], rel, standing, roads, lines, rivers.get(tid, []))
	tree_placements[tid] = placements
	for kind in ["small", "fir", "large"]:
		var level: int = {"small": 1, "fir": 2, "large": 3}[kind]
		var key := Assets.key_for("tree", level)
		# Godot selects a MultiMesh's mesh LOD from the node transform. Keep the
		# species' main scale there, rather than hiding a 20x scale in each instance;
		# otherwise tiny LODs and their contour shells diverge even at close zoom.
		var species_scale := float(Legacy._TREE_HEIGHT[kind]) / Assets.projected_height(key)
		var transforms: Array[Transform3D] = []
		for tree in placements:
			if tree.kind != kind: continue
			var scale := float(tree.height) / Assets.projected_height(key)
			transforms.append(Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * scale / species_scale), point(tree.pos) / species_scale))
			var radius := Assets.dimensions(key).x * scale * 0.5
			shadow(tree.pos, radius * 2.0, true)
		if transforms.is_empty(): continue
		for mesh in [Assets.mesh_for(key), Assets.contour_for(key)]:
			if mesh == null: continue
			var multi := MultiMesh.new()
			multi.transform_format = MultiMesh.TRANSFORM_3D
			multi.mesh = mesh
			multi.instance_count = transforms.size()
			for i in transforms.size(): multi.set_instance_transform(i, transforms[i])
			var node := MultiMeshInstance3D.new()
			node.name = "Trees_" + kind
			node.multimesh = multi
			node.scale = Vector3.ONE * species_scale
			if mesh == Assets.mesh_for(key): node.material_override = Assets.tree_material(kind == "fir")
			root.add_child(node)
			building_visuals.append(node)
	# Retain close-up ground detail without replacing the source tree composition.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(tid)
	for i in 130:
		var p := c + Vector2(rng.randf_range(-260, 260), rng.randf_range(-235, 235))
		if not _plantable(p, tid, rel, standing, 6.0): continue
		var foot := point(p, 0.2)
		if i % 7 == 0:
			# Sparse stones belong on exposed slopes; uniformly scattered grey
			# pebbles made the source board's clear grass read as visual noise.
			if i % 21 != 0 or surface_gradient(p).length() < 0.25: continue
			_crown(near, foot + Vector3.UP * 0.55, Vector3(1.5, 1.1, 1.2), Color("85816b"), 5)
		else:
			for j in 3:
				var angle := float(j) * PI / 3.0
				var side := Vector3(cos(angle), 0, sin(angle)) * 0.6
				near.triangle(foot - side, foot + Vector3.UP * rng.randf_range(1.5, 3.2), foot + side, Color("81834c"))
	add_detail(root, near.mesh(), 2)
	return root

func _plantable(p: Vector2, tid: String, rel: Dictionary, standing: Array, road_margin: float = 19.0) -> bool:
	if not Geometry2D.is_point_in_polygon(p, Model.hex_points(tiles[tid].center)) or Ground.is_water(rel, p): return false
	for s in standing:
		if (s.pos as Vector2).distance_to(p) < float(s.get("side", 80)) * 0.74 + 12.0: return false
	for road in roads:
		if Geometry2D.get_closest_point_to_segment(p, road.a, road.b).distance_to(p) < road_margin: return false
	for rec in rivers.get(tid, []):
		for j in range(rec.points.size() - 1):
			if Geometry2D.get_closest_point_to_segment(p, rec.points[j], rec.points[j + 1]).distance_to(p) < (float(rec.start_width) + float(rec.end_width)) * 0.25 + 6.0: return false
	return true

func _crown(batch: RefCounted, center: Vector3, radius: Vector3, color: Color, sides: int) -> void:
	# Rounded, faceted broadleaf crowns rather than the first pass's pointed diamonds.
	var levels := [-0.82, -0.35, 0.30, 0.78]
	for ring in range(levels.size() - 1):
		var y0: float = levels[ring]
		var y1: float = levels[ring + 1]
		var r0 := sqrt(1.0 - y0 * y0)
		var r1 := sqrt(1.0 - y1 * y1)
		for j in sides:
			var a := TAU * j / sides
			var b := TAU * (j + 1) / sides
			batch.quad(center + Vector3(cos(a) * r0, y0, sin(a) * r0) * radius,
				center + Vector3(cos(b) * r0, y0, sin(b) * r0) * radius,
				center + Vector3(cos(b) * r1, y1, sin(b) * r1) * radius,
				center + Vector3(cos(a) * r1, y1, sin(a) * r1) * radius, color)
	for j in sides:
		var a := TAU * j / sides
		var b := TAU * (j + 1) / sides
		batch.triangle(center + Vector3(cos(a) * 0.626, 0.78, sin(a) * 0.626) * radius,
			center + Vector3.UP * radius.y, center + Vector3(cos(b) * 0.626, 0.78, sin(b) * 0.626) * radius, color.lightened(0.04))

func prepare_flows(model: Dictionary) -> void:
	flows.clear()
	for flow in model.get("flows", []):
		var points := PackedVector3Array()
		var distances := PackedFloat32Array([0.0])
		var source: Array = flow.get("pts", [])
		var cable := str(flow.get("mode", "")) == "cables"
		for i in range(source.size() - 1):
			var a: Vector2 = source[i].p
			var b: Vector2 = source[i + 1].p
			var count := maxi(1, ceili(a.distance_to(b) / 18.0))
			for j in range(count + (1 if i == source.size() - 2 else 0)):
				var t := float(j) / count
				var p := a.lerp(b, t)
				var h := lerpf(ground.height(a), ground.height(b), t) + 70.0 - sin(t * PI) * 12.0 if cable else road_height(p) + 16.0
				var at := at_height(p, h)
				if not points.is_empty(): distances.append(distances[-1] + points[-1].distance_to(at))
				points.append(at)
		if points.size() >= 2:
			flows.append({"points": points, "distances": distances, "length": distances[-1], "icon": flow.get("icon"), "good": flow.get("good", "")})
