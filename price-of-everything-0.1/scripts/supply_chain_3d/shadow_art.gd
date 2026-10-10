extends RefCounted
## Static contact shadows in map space. The same feathered footprint is painted
## into the continent atlas and each closer tile, so zoom cannot remove it.
const Geo := preload("res://scripts/supply_chain_3d/geometry.gd")

static func footprint(p: Vector2, side: float, tree: bool) -> Dictionary:
	var throw := Vector2(-0.70710678, -0.70710678) * side * 0.38
	return {"center": p + throw * 0.45,
		"radii": Vector2(side * 0.62, side * 0.48) if tree else Vector2.ONE * side * 0.69}

static func bounds(record: Dictionary) -> Rect2:
	return Rect2(record.center - record.radii, record.radii * 2.0)

static func artwork(records: Array) -> ArrayMesh:
	var batch := Geo.Batch.new()
	for record in records:
		for ring in 4:
			var r0 := float(ring) / 4.0
			var r1 := float(ring + 1) / 4.0
			for sector in 16:
				var a := TAU * sector / 16.0
				var b := TAU * (sector + 1) / 16.0
				var points := [Vector2(cos(a), sin(a)) * r0, Vector2(cos(b), sin(b)) * r0,
					Vector2(cos(b), sin(b)) * r1, Vector2(cos(a), sin(a)) * r1]
				var start := batch.vertices.size()
				var world: Array[Vector3] = []
				for p in points:
					var at: Vector2 = record.center + p * record.radii
					world.append(Vector3(at.x, at.y, 0.0))
				batch.quad(world[0], world[1], world[2], world[3], Color(0.04, 0.06, 0.14, 0.0))
				for i in range(start, batch.vertices.size()):
					var v: Vector3 = batch.vertices[i]
					var radius: float = ((Vector2(v.x, v.y) - record.center) / record.radii).length()
					batch.colors[i].a = 0.17 * (1.0 - smoothstep(0.35, 1.0, radius))
	return batch.mesh()
