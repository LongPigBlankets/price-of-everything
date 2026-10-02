extends RefCounted
## Supply chain board — one atlas of baked pieces (pipes or roads) and how to draw from it.
##
## bake_pipes.py packs a kind's pieces into res://assets/iso/<kind>/<kind>.png, a grid of
## square cells, with <kind>.json naming each cell and carrying the dimensions the pieces were
## built to. A piece's anchor is its cell's centre.

## The part of a piece's frame that is drawn: clear of the frame's edge, which the bake leaves
## empty so a neighbouring cell cannot bleed in at a small scale.
const DRAW_HALF := 28.0

var _index: Dictionary = {}
var _texture: Texture2D = null


func _init(kind: String) -> void:
	var index_path := "res://assets/iso/%s/%s.json" % [kind, kind]
	var atlas_path := "res://assets/iso/%s/%s.png" % [kind, kind]
	if not FileAccess.file_exists(index_path) or not ResourceLoader.exists(atlas_path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(index_path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	_index = parsed
	_texture = load(atlas_path)


## False when the pieces have not been baked.
func ok() -> bool:
	return _texture != null


func texture() -> Texture2D:
	return _texture


func dim(name: String) -> float:
	return float((_index.get("dims", {}) as Dictionary).get(name, 0.0))


func px_per_unit() -> float:
	return float(_index.get("px_per_unit", 4.0))


func has(name: String) -> bool:
	return (_index.get("cells", {}) as Dictionary).has(name)


## A piece's cell in the atlas, in pixels; an empty rect when there is no such piece.
func cell(name: String) -> Rect2:
	var cells: Dictionary = _index.get("cells", {})
	if not cells.has(name):
		return Rect2()
	var f := float(_index.get("frame", 256))
	return Rect2(float(cells[name][0]) * f, float(cells[name][1]) * f, f, f)


## The polygons that draw one straight run from tiles of its piece: [{points, uvs, depth}], in
## board space with uvs into the atlas. `item` is {name, a, b, step, depth_a, depth_b}: the
## run's two ends, and `step` the board vector of one repeat of the piece. Each tile is the
## piece's own frame cut to the stretch of the run it covers, so whatever repeats along the
## piece carries on evenly from one tile to the next.
func run_polys(item: Dictionary) -> Array:
	var out: Array = []
	var src := cell(str(item["name"]))
	if src.size.x <= 0.0:
		return out
	var a: Vector2 = item["a"]
	var b: Vector2 = item["b"]
	var length := a.distance_to(b)
	var tile := (item["step"] as Vector2).length()
	if length < 0.05 or tile < 0.05:
		return out
	var dir := (b - a) / length
	var ppu := px_per_unit()
	var asize := Vector2(_texture.get_width(), _texture.get_height())
	var count := int(ceil(length / tile))
	for i in range(count):
		var from := float(i) * tile
		var to := minf(length, from + tile + 0.15)
		var anchor := a + dir * (from + tile * 0.5)
		var poly := PackedVector2Array([
			anchor + Vector2(-DRAW_HALF, -DRAW_HALF), anchor + Vector2(DRAW_HALF, -DRAW_HALF),
			anchor + Vector2(DRAW_HALF, DRAW_HALF), anchor + Vector2(-DRAW_HALF, DRAW_HALF)])
		poly = clip(poly, a + dir * from, dir)
		poly = clip(poly, a + dir * to, -dir)
		if poly.size() < 3:
			continue
		var uvs := PackedVector2Array()
		for q in poly:
			uvs.append((src.position + src.size * 0.5 + (q - anchor) * ppu) / asize)
		out.append({"points": poly, "uvs": uvs, "depth": lerpf(float(item.get("depth_a", 0.0)),
			float(item.get("depth_b", 0.0)), clampf((from + to) * 0.5 / length, 0.0, 1.0))})
	return out


## Keep the part of a convex polygon on the `normal` side of the line through `origin`.
static func clip(poly: PackedVector2Array, origin: Vector2, normal: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(poly.size()):
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		var dp := (p - origin).dot(normal)
		var dq := (q - origin).dot(normal)
		if dp >= 0.0:
			out.append(p)
		if (dp >= 0.0) != (dq >= 0.0):
			out.append(p.lerp(q, dp / (dp - dq)))
	return out


## Where a whole piece is drawn and from which part of the atlas: [destination, source].
func fit_rects(name: String, at: Vector2) -> Array:
	var src := cell(name)
	var ppu := px_per_unit()
	var half_px := minf(src.size.x * 0.5 - 2.0, DRAW_HALF * ppu)
	var half := half_px / ppu
	return [Rect2(at - Vector2(half, half), Vector2(half, half) * 2.0),
		Rect2(src.get_center() - Vector2(half_px, half_px), Vector2(half_px, half_px) * 2.0)]
