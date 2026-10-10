extends "res://scripts/empire_board.gd"
## Reuse the original coastline, mouth clipping and estuary tessellation in a
## horizontal texture bake. This helper is never added to the scene tree: only
## its drawing geometry is used, with zero projection height, then unprojected.

func _height_at(_p: Vector2) -> float:
	return 0.0

func artwork(tile: Dictionary, relief: Dictionary, rivers: Array, height: Callable) -> ArrayMesh:
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var indices := PackedInt32Array()
	var hex := Model.hex_points(tile.center)
	var ocean := str(tile.type) in ["sea", "deep_sea"]
	var water: Color = MapStyle.sea_colors()[4]
	var coast: Array = [] if ocean or relief.get("sea", []).is_empty() else _shore_of(relief, hex)
	for band in [[_SHALLOWS_OUT, _SHALLOWS_W, water.lightened(0.14)], [_SHALLOWS_OUT * 0.45, _SHALLOWS_W * 0.6, water.lightened(0.3)],
			[-_STRAND * 0.5, _STRAND, _SAND], [0.6, 3.4, _SAND.darkened(0.16)], [2.6, 1.1, _FOAM]]:
		for seg in coast:
			var out: Vector2 = seg[2] * float(band[0])
			if not Geometry2D.is_point_in_polygon(((seg[0] as Vector2) + seg[1]) * 0.5
					+ seg[2] * (float(band[0]) + signf(float(band[0])) * float(band[1]) * 0.5), hex): continue
			_stroke_on(verts, cols, indices, PackedVector2Array([seg[0] + out, seg[1] + out]), float(band[1]), band[2])
	for lake in relief.get("lakes", []):
		var ring := PackedVector2Array(lake)
		ring.append(ring[0])
		_stroke_on(verts, cols, indices, ring, 4.0, _SAND.darkened(0.08))
		_stroke_on(verts, cols, indices, ring, 1.6, water.lightened(0.3))
	var sea: Array = []
	for e in relief.get("sea", []): sea.append(e.p)
	# Continue through the bake gutter, so separately filtered tiles still meet.
	var area := _skirted(hex, [true, true, true, true, true, true], 4.0)
	for rec in rivers:
		var width := (float(rec.start_width) + float(rec.end_width)) * 0.5
		for part in Geometry2D.intersect_polyline_with_polygon(rec.points, area):
			for run in _to_mouth(relief, _aim_mouth(relief, part, coast, width), coast, width):
				var profile := profile_for(run.pts, height)
				var pts: PackedVector2Array = profile[0]
				var hs: PackedFloat32Array = profile[1]
				var flat := PackedFloat32Array()
				flat.resize(pts.size())
				_stroke_to(verts, cols, indices, pts, width, water, run.cuts, _MOUTH, flat)
				_stroke_to(verts, cols, indices, pts, width * 0.45, water.lightened(0.16), run.cuts, _MOUTH, flat)
				for side in [-1.0, 1.0]:
					_stroke_to(verts, cols, indices, _beside(pts, (width * 0.5 + 1.4) * side), 3.0, _BANK, run.cuts, 0.0, flat)
					_stroke_to(verts, cols, indices, _beside(pts, width * 0.5 * side), 0.9, _INK_SOFT, run.cuts, 0.0, flat)
				_plan_white_water(verts, cols, indices, pts, hs, width)
				for cut in run.cuts: _estuary(verts, cols, indices, pts, cut, width, water, hex, sea)
	for i in verts.size():
		var q := verts[i]
		verts[i] = Vector3((q.x / ISO_X + q.y / ISO_Y) * 0.5, (q.y / ISO_Y - q.x / ISO_X) * 0.5, 0.0)
	return _mesh_of(verts, cols, indices)

static func profile_for(line: PackedVector2Array, height: Callable) -> Array:
	var pts := PackedVector2Array()
	var hs := PackedFloat32Array()
	for i in line.size():
		if i == 0:
			pts.append(line[0])
			hs.append(float(height.call(line[0])))
			continue
		var a := line[i - 1]
		var b := line[i]
		if a.distance_to(b) < 0.01: continue
		var samples: Array = []
		var count := maxi(1, ceili(a.distance_to(b) / PROFILE_STEP))
		for k in range(count + 1):
			var t := float(k) / count
			samples.append([t, float(height.call(a.lerp(b, t)))])
		var simplified := _simplify(samples)
		for k in range(1, simplified.size()):
			pts.append(a.lerp(b, float(simplified[k][0])))
			hs.append(float(simplified[k][1]))
	return [pts, hs]

## Same foam layout and drop threshold as the source; heights detect the falls,
## but the marks themselves go into the plan texture and follow the 3D terrain.
static func _plan_white_water(verts: PackedVector3Array, cols: PackedColorArray, idx: PackedInt32Array,
		pts: PackedVector2Array, hs: PackedFloat32Array, width: float) -> void:
	var i := 0
	while i < pts.size() - 1:
		if absf(hs[i + 1] - hs[i]) < 0.05:
			i += 1
			continue
		var j := i
		while j < pts.size() - 1 and absf(hs[j + 1] - hs[j]) >= 0.05:
			j += 1
		var fall := absf(hs[j] - hs[i])
		if fall >= RAPIDS_DROP:
			# Down the fall: short streaks of foam, staggered either side of the middle.
			var n := 0
			for k in range(i, j):
				var a := pts[k]
				var b := pts[k + 1]
				var length := a.distance_to(b)
				var dir := (b - a) / maxf(length, 0.001)
				var d := 1.5
				while d < length - 1.0:
					var off := dir.orthogonal() * width * (0.18 if n % 2 == 0 else -0.18)
					var p0 := a + dir * d + off
					var p1 := a + dir * minf(d + 4.0, length) + off
					_poly_along(verts, cols, idx, _bar(p0, p1, width * 0.22), p0, p1,
						0.0, 0.0, _FOAM)
					d += 6.5
					n += 1
			# The foot: the lower end of the fall, which may be the tile's own edge, so the mark is
			# laid just up the fall from it.
			var foot := j if hs[j] < hs[i] else i
			var up := foot - 1 if foot == j else foot + 1
			var back := pts[up] - pts[foot]
			var run := maxf(back.length(), 0.001)
			var across := back.orthogonal().normalized() * width * 0.62
			for mark in [[1.0, 1.0, _INK_SOFT], [3.5, 3.0, _FOAM]]:
				var d := minf(float(mark[0]), run)
				var at := pts[foot] + back / run * d
				_stroke(verts, cols, idx, PackedVector2Array([at - across, at + across]), float(mark[1]),
					0.0, mark[2])
		i = j
