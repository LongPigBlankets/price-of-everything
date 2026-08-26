extends RefCounted
## Many polygons, ONE draw call.
##
## The gl_compatibility canvas charges per COMMAND, not per pixel. Measured 25 Aug with
## tools/pan_profile.tscn: a fully zoomed-out frame spent 226 ms submitting 21,762 draw calls,
## and 92.5% of them belonged to two layers drawing hundreds of small polygons one at a time —
## 10,913 for BuildingVisuals, 9,612 for the farm layer. Shrinking the window to 640x360 changed
## nothing, so none of it was fill rate; it was the count.
##
## `canvas_item_add_triangle_array` takes the whole screenful as a single command, so the fix is
## the same shape wherever it is applied: triangulate once, CACHE the triangles, concatenate with
## `append_array` (a memcpy), submit once.
##
## NON-INDEXED ON PURPOSE. An indexed array is ~4x smaller, but concatenating two of them means
## offsetting every index of the second — a per-vertex GDScript loop on the repaint path, which
## is exactly what made a first cut of the road ribbons SLOWER than the draw_polyline calls it
## replaced (38-86 ms per repaint). A flat triangle list concatenates with no arithmetic at all,
## and the identity index array it needs is grown once for the run and sliced.

static var _seq := PackedInt32Array()


## 0, 1, 2, ... n-1. Grown once for the whole run; the slice is a memcpy.
static func sequence(n: int) -> PackedInt32Array:
	if _seq.size() < n:
		var was := _seq.size()
		_seq.resize(n)
		for i in range(was, n):
			_seq[i] = i
	return _seq.slice(0, n)


## A simple polygon as a flat, non-indexed triangle list. Empty when the polygon will not
## triangulate — degenerate or self-intersecting — so a caller draws NOTHING rather than a wrong
## shape. Callers are expected to cache the result; this walks every vertex.
static func polygon_soup(poly: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	if poly.size() < 3:
		return out
	var idx := Geometry2D.triangulate_polygon(poly)
	if idx.is_empty():
		return out
	out.resize(idx.size())
	for i in idx.size():
		out[i] = poly[idx[i]]
	return out


## Submit an accumulated triangle list as one command. No-op when empty.
static func flush(canvas: CanvasItem, pts: PackedVector2Array, cols: PackedColorArray) -> void:
	var n := pts.size()
	if n == 0:
		return
	RenderingServer.canvas_item_add_triangle_array(canvas.get_canvas_item(), sequence(n), pts, cols)
