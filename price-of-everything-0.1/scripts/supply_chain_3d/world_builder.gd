extends RefCounted
## Builds the supply-chain world's static geometry. Map-space coordinates and the shared
## height field are authoritative; the camera never participates in generation.
const Geo := preload("res://scripts/supply_chain_3d/geometry.gd")
const Legacy := preload("res://scripts/empire_board.gd")
const Model := preload("res://scripts/empire_board_model.gd")
const Ground := preload("res://scripts/empire_board_ground.gd")
const Assets := preload("res://scripts/supply_chain_3d/assets.gd")
const CELL := 12.0
var origin := Vector2.ZERO
var ground: RefCounted
var rivers: Dictionary = {}
var tiles: Dictionary = {}
var terrain_cache: Dictionary = {}
var mat := Geo.material()
var line_mat := Geo.material(true)
var bounds := AABB()
var pickables: Array = []
var labels: Array = []
var flows: Array = []
var cars: Array = []
var smoke: Array = []
var roads: Array = []
var _helpers: Control = Legacy.new()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(_helpers):
		_helpers.free()

func point(p: Vector2, lift: float = 0.0) -> Vector3:
	return Vector3(p.x - origin.x, ground.height(p) + lift, p.y - origin.y)

func at_height(p: Vector2, height: float) -> Vector3:
	return Vector3(p.x - origin.x, height, p.y - origin.y)

func tile_node(tid: String) -> Node3D:
	var tile: Dictionary = tiles[tid]
	var center: Vector2 = tile["center"]
	var root := Node3D.new()
	root.name = tid
	var hex := Model.hex_points(center)
	var rel: Dictionary = Legacy._relief_of(tid, center)
	var key := "%s:%s:%s" % [tid, ground.get_instance_id(), origin]
	var surface: ArrayMesh
	if terrain_cache.has(key):
		surface = terrain_cache[key]
	else:
		var batch := Geo.Batch.new()
		var low := ((center - Model.HEX_HALF) / CELL).floor()
		var high := ((center + Model.HEX_HALF) / CELL).ceil()
		var bands: Array[Color] = MapStyle.band_colors()
		var sea: Array[Color] = MapStyle.sea_colors()
		var is_sea := str(tile["type"]) in ["sea", "deep_sea"]
		var top: Color = sea[0 if str(tile["type"]) == "deep_sea" else 2] if is_sea else Legacy._warm(sea[5])
		for y in range(int(low.y), int(high.y)):
			for x in range(int(low.x), int(high.x)):
				var a := Vector2(x, y) * CELL
				var square := PackedVector2Array([a, a + Vector2(CELL, 0), a + Vector2(CELL, CELL), a + Vector2(0, CELL)])
				for poly in Geometry2D.intersect_polygons(square, hex):
					for i in range(1, poly.size() - 1):
						var p: Vector2 = (poly[0] + poly[i] + poly[i + 1]) / 3.0
						var color: Color = _helpers.call("_ground_colour", rel, p, top, is_sea, bands, sea, sea[4], rivers.get(tid, []))
						var before := batch.vertices.size()
						batch.triangle(point(poly[0]), point(poly[i + 1]), point(poly[i]), color)
						if batch.vertices.size() == before: continue
						# Smooth ground normals, including across tile seams.
						var n := batch.normals.size()
						for j in 3:
							var v: Vector3 = batch.vertices[n - 3 + j]
							var grad: Vector2 = ground.gradient(Vector2(v.x, v.z) + origin)
							batch.normals[n - 3 + j] = Vector3(-grad.x, 1.0, -grad.y).normalized()
		surface = batch.mesh()
		terrain_cache[key] = surface
	var land := Geo.instance(surface, mat)
	land.name = "Terrain"
	root.add_child(land)
	var body := StaticBody3D.new()
	body.name = "TilePick"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("tile_id", tid)
	var collider := CollisionShape3D.new()
	collider.shape = surface.create_trimesh_shape()
	body.add_child(collider)
	root.add_child(body)
	# The exposed cutaway rim is independent of the cached terrain surface.
	var rim := Geo.Batch.new()
	var centers: Dictionary = {}
	for t in tiles.values(): centers[Vector2i((t.center as Vector2).round())] = true
	var strata: Array[Color] = [Color("847857"), Color("56596c"), Color("ab7853"), Color("423f48")]
	for i in 6:
		var a: Vector2 = hex[i]
		var b: Vector2 = hex[(i + 1) % 6]
		if centers.has(Vector2i((a + b - center).round())): continue
		var steps := ceili(a.distance_to(b) / CELL)
		for j in steps:
			var pa := a.lerp(b, float(j) / steps)
			var pb := a.lerp(b, float(j + 1) / steps)
			var ah: float = ground.height(pa)
			var bh: float = ground.height(pb)
			for band in 4:
				var top_a := lerpf(ah, -100.0, float(band) / 4.0)
				var top_b := lerpf(bh, -100.0, float(band) / 4.0)
				var bot_a := lerpf(ah, -100.0, float(band + 1) / 4.0)
				var bot_b := lerpf(bh, -100.0, float(band + 1) / 4.0)
				rim.quad(at_height(pa, top_a), at_height(pb, top_b), at_height(pb, bot_b), at_height(pa, bot_a), strata[band])
	var cutaway := Geo.instance(rim.mesh(), mat)
	cutaway.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(cutaway)
	var water := Geo.Batch.new()
	for rec in rivers.get(tid, []):
		var line: PackedVector2Array = rec["points"]
		var width := (float(rec["start_width"]) + float(rec["end_width"])) * 0.5
		ribbon(water, line, width + 5.0, Color("c9c08f"), 1.0)
		ribbon(water, line, width, Color("5790af"), 1.5)
		ribbon(water, line, width * 0.45, Color("70a5ba"), 1.7)
	root.add_child(Geo.instance(water.mesh(), mat))
	labels.append({"tile": tid, "text": tile["label"], "point": point(center, 12.0)})
	return root

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
	var h: float = ground.height(p)
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
	roads = model.get("roads", [])
	if bool(show["roads"]):
		for rec in roads:
			var path := PackedVector2Array([rec.a, rec.b])
			var width := 8.0 if str(rec.get("kind", "")) == "drive" else 15.0
			var paved := bool(rec.get("paved", true))
			ribbon(streets, path, width + 3.0, Color("b9b4a6"), 1.0, true)
			ribbon(streets, path, width, Color("555957") if paved else Color("9c855f"), 1.3, true)
			if width > 10.0 and paved:
				var a: Vector2 = rec.a
				var b: Vector2 = rec.b
				var length := a.distance_to(b)
				for j in range(int(length / 18.0)):
					var pa := a.move_toward(b, j * 18.0)
					var pb := a.move_toward(b, minf(length, j * 18.0 + 8.0))
					ribbon(streets, PackedVector2Array([pa, pb]), 0.8, Color("d5cfaf"), 1.6, true)
			if (rec.a as Vector2).distance_to(rec.b) > 80.0:
				cars.append({"a": rec.a, "b": rec.b, "phase": fmod(absf(float(hash(str(rec.a)))), 100.0) / 100.0})
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
	var key := Assets.key_for(family, level)
	var mesh: Mesh = Assets.mesh_for(key)
	var side := float(s.get("side", 80.0))
	var p: Vector2 = s.pos
	var floor_h: float = ground.height(p)
	var half := side * 0.42
	for off in [Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)]:
		floor_h = maxf(floor_h, ground.height(p + off))
	root.position = at_height(p, floor_h + 1.0)
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
	root.add_child(visual)
	# A grounded foundation remains solid from every side of a slope.
	var plinth := Geo.Batch.new()
	var depth := maxf(2.0, floor_h - ground.height(p) + 3.0)
	plinth.box(Vector3(0, -depth * 0.5, 0), Vector3(side * 0.96, depth, side * 0.96), Color("999786"))
	root.add_child(Geo.instance(plinth.mesh(), mat))
	if kind in ["building", "site", "warehouse", "suppliers"]:
		var body := StaticBody3D.new()
		body.collision_layer = 2
		body.collision_mask = 0
		body.set_meta("standing", s)
		body.set_meta("tile_id", str(s.tile))
		var shape := BoxShape3D.new()
		shape.size = dimension.max(Vector3.ONE * 6.0)
		var collider := CollisionShape3D.new()
		collider.shape = shape
		collider.position.y = dimension.y * 0.5
		body.add_child(collider)
		root.add_child(body)
	pickables.append({"iid": s.iid, "kind": kind, "tile": s.tile, "point": root.position + Vector3.UP * dimension.y * 0.5, "top": root.position + Vector3.UP * (dimension.y + 12.0), "size": dimension})
	if bool(s.get("polluting", false)):
		smoke.append({"point": root.position + Vector3.UP * dimension.y, "radius": maxf(4.0, side * 0.08)})
	return root

func trees_node(tid: String, standing: Array) -> Node3D:
	var batch := Geo.Batch.new()
	var c: Vector2 = tiles[tid].center
	var rel: Dictionary = Legacy._relief_of(tid, c)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(tid)
	for i in 26:
		var p := c + Vector2(rng.randf_range(-215, 215), rng.randf_range(-200, 200))
		if not Geometry2D.is_point_in_polygon(p, Model.hex_points(c)) or Ground.is_water(rel, p): continue
		var clear := true
		for s in standing:
			if (s.pos as Vector2).distance_to(p) < float(s.get("side", 80)) * 0.75 + 15.0: clear = false
		for road in roads:
			if Geometry2D.get_closest_point_to_segment(p, road.a, road.b).distance_to(p) < 18.0: clear = false
		if not clear: continue
		var base := point(p)
		var h := rng.randf_range(17, 30)
		batch.tube(base, base + Vector3.UP * h * 0.6, 1.4, Color("645743"), 5)
		var r := h * 0.28
		for j in 7:
			var a := TAU * float(j) / 7.0
			var b := TAU * float(j + 1) / 7.0
			var p1 := base + Vector3(cos(a) * r, h * 0.48, sin(a) * r)
			var p2 := base + Vector3(cos(b) * r, h * 0.48, sin(b) * r)
			batch.triangle(p1, base + Vector3.UP * h, p2, Color("647950"))
			batch.triangle(p1, p2, base + Vector3.UP * h * 0.23, Color("536b49"))
	return Geo.instance(batch.mesh(), mat)

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
