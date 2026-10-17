extends RefCounted
## Offline-derived intermediate contours. The regular map's data stays immutable.
const PATH := "res://data/supply_chain_half_relief.json"
const Legacy := preload("res://scripts/empire_board.gd")
static var _polys: Array = []
static var _by_band := {}

static func polys() -> Array:
	if not _polys.is_empty(): return _polys
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	for entry in doc.get("polys", []):
		var points := PackedVector2Array()
		for i in range(0, entry.p.size(), 2): points.append(Vector2(entry.p[i], entry.p[i + 1]))
		var rec := {"b": float(entry.b), "p": points, "box": Legacy._box_of(points)}
		_polys.append(rec)
		(_by_band.get_or_add(floori(rec.b), []) as Array).append(rec)
	return _polys

static func land(source: Array) -> Array:
	polys()
	var result: Array = []
	for entry in source:
		result.append(entry)
		# Interleave within the original paint order: a later valley/depression
		# still paints over its containing mountain, with no changes to full bands.
		var box := Legacy._box_of(entry.p)
		for half in _by_band.get(int(entry.b), []):
			if not box.intersects(half.box): continue
			for piece in Geometry2D.intersect_polygons(entry.p, half.p):
				if not Geometry2D.is_polygon_clockwise(piece): result.append({"b": half.b, "p": piece})
	return result

static func color(band: float, colors: Array) -> Color:
	var index := clampf(band, 0.0, colors.size() - 1.0)
	return (colors[floori(index)] as Color).lerp(colors[ceili(index)], index - floorf(index))
