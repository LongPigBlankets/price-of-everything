extends RefCounted
## Triangles for the river layer, gathered once and handed to the GPU as ONE mesh.
##
## RiverVisuals used to paint every river as antialiased draw_line calls, one per bezier sample.
## The engine turns each of those into five canvas primitives (the quad and four feather
## strips), so the river network alone was ~288,000 canvas objects EVERY frame: eighteen times
## the GL Compatibility renderer's instance buffer (16,384), whose growth path can crash the
## engine when the GPU is behind. A mesh is one object however many triangles it holds.
##
## The antialiasing is the engine's own, rebuilt: a FEATHER wide strip either side whose outer
## vertices carry the same colour at zero alpha. Samples are joined as one mitred ribbon
## instead of separate quads, so a translucent bank no longer darkens where quads overlapped.

const FEATHER := 1.25   # the engine's draw_line / draw_polyline feather, in canvas units
const CIRCLE_POINTS := 32
const MIN_MITRE := 0.5   # caps the widening at a sharp bend (1 / 0.5 = twice the width)

var verts := PackedVector2Array()
var colours := PackedColorArray()
var indices := PackedInt32Array()

func is_empty() -> bool:
	return indices.is_empty()

func mesh() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_INDEX] = indices
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m

## A feathered ribbon through `points`, widths[i] wide at each sample: draw_polyline(..., true)
## as the engine draws it, but mitred. `start_dir` / `end_dir` pin the end tangents (two paths
## meeting at a tile edge share one, so their butt ends line up exactly); ZERO derives them.
## `cap_start` / `cap_end` feather the butt ends too; leave them off where a neighbour continues.
func stroke(points: PackedVector2Array, widths: PackedFloat32Array, colour: Color,
		closed: bool = false, start_dir: Vector2 = Vector2.ZERO, end_dir: Vector2 = Vector2.ZERO,
		cap_start: bool = true, cap_end: bool = true) -> void:
	var n := points.size()
	if n < 2:
		return
	var clear := Color(colour, 0.0)
	var rows := PackedInt32Array()   # per sample: outer left, left, right, outer right
	var normals := PackedVector2Array()
	for i in n:
		var p := points[i]
		var prev := points[(i - 1 + n) % n] if closed else points[maxi(i - 1, 0)]
		var next := points[(i + 1) % n] if closed else points[mini(i + 1, n - 1)]
		var dir := (next - prev).normalized()
		if not closed and i == 0 and start_dir != Vector2.ZERO:
			dir = start_dir.normalized()
		elif not closed and i == n - 1 and end_dir != Vector2.ZERO:
			dir = end_dir.normalized()
		if dir == Vector2.ZERO:
			dir = Vector2.RIGHT
		var normal := Vector2(-dir.y, dir.x)
		var scale := 1.0
		var into := p - prev
		if into.length_squared() > 0.0001 and (closed or (i > 0 and i < n - 1)):
			var seg_normal := Vector2(-into.y, into.x).normalized()
			scale = 1.0 / maxf(absf(normal.dot(seg_normal)), MIN_MITRE)
		var half := widths[i] * 0.5 * scale
		var feather := FEATHER * scale
		rows.append(_v(p + normal * (half + feather), clear))
		rows.append(_v(p + normal * half, colour))
		rows.append(_v(p - normal * half, colour))
		rows.append(_v(p - normal * (half + feather), clear))
		normals.append(normal)
	var spans := n if closed else n - 1
	for i in spans:
		var a := i * 4
		var b := ((i + 1) % n) * 4
		for k in 3:
			_quad(rows[a + k], rows[b + k], rows[b + k + 1], rows[a + k + 1])
	if closed:
		return
	# normal = (-dir.y, dir.x), so dir = (normal.y, -normal.x).
	if cap_start:
		_cap(points[0], normals[0], -Vector2(normals[0].y, -normals[0].x), widths[0],
			rows, 0, clear)
	if cap_end:
		_cap(points[n - 1], normals[n - 1], Vector2(normals[n - 1].y, -normals[n - 1].x),
			widths[n - 1], rows, (n - 1) * 4, clear)

## A butt end's feather, pushed FEATHER out along `out`, with its two corner triangles.
func _cap(p: Vector2, normal: Vector2, out: Vector2, width: float, rows: PackedInt32Array,
		row: int, clear: Color) -> void:
	var half := width * 0.5
	var a := _v(p + normal * half + out * FEATHER, clear)
	var b := _v(p - normal * half + out * FEATHER, clear)
	_quad(rows[row + 1], rows[row + 2], b, a)
	_tri(rows[row], rows[row + 1], a)
	_tri(rows[row + 2], rows[row + 3], b)

func line(a: Vector2, b: Vector2, width: float, colour: Color) -> void:
	stroke(PackedVector2Array([a, b]), PackedFloat32Array([width, width]), colour)

## draw_circle: filled, not antialiased.
func circle(centre: Vector2, radius: float, colour: Color) -> void:
	var mid := _v(centre, colour)
	var first := verts.size()
	for i in CIRCLE_POINTS:
		var angle := TAU * float(i) / float(CIRCLE_POINTS)
		_v(centre + Vector2(cos(angle), sin(angle)) * radius, colour)
	for i in CIRCLE_POINTS:
		_tri(mid, first + i, first + (i + 1) % CIRCLE_POINTS)

## draw_colored_polygon / draw_polygon: filled, not antialiased. One colour, or one per point.
func polygon(points: PackedVector2Array, colour: Color,
		point_colours: PackedColorArray = PackedColorArray()) -> void:
	if points.size() < 3:
		return
	var tris := Geometry2D.triangulate_polygon(points)
	if tris.is_empty():
		for i in range(1, points.size() - 1):
			tris.append_array(PackedInt32Array([0, i, i + 1]))
	var first := verts.size()
	for i in points.size():
		_v(points[i], point_colours[i] if point_colours.size() == points.size() else colour)
	for t in tris:
		indices.append(first + t)

func _v(p: Vector2, c: Color) -> int:
	verts.append(p)
	colours.append(c)
	return verts.size() - 1

func _tri(a: int, b: int, c: int) -> void:
	indices.append(a)
	indices.append(b)
	indices.append(c)

func _quad(a: int, b: int, c: int, d: int) -> void:
	_tri(a, b, c)
	_tri(a, c, d)
