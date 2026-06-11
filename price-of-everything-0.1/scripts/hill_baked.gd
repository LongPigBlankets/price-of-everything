class_name HillBaked
extends RefCounted
## Loader for the baked hill data (data/hills_baked.json) produced by
## tools/bake_hills.tscn. The map is hand-painted, so the baked output is the
## canonical hill shape: the game NEVER regenerates at runtime — it only loads
## this file, guaranteeing identical hills every start.
##
## Staleness: the bake stores an MD5 over the tile/river CSVs + generator
## version + seed. If the CSVs change without re-baking, loading warns once
## (the stale shape still loads — rerun the bake to refresh):
##   <godot> --headless res://tools/bake_hills.tscn

const BAKED_PATH := "res://data/hills_baked.json"
const SEED := 1337
const SOURCE_CSVS := ["res://data/tile_properties.csv", "res://data/river_properties.csv"]

static var _cache: Dictionary = {}
static var _loaded := false

static func data() -> Dictionary:
	if _loaded:
		return _cache
	_loaded = true
	if not FileAccess.file_exists(BAKED_PATH):
		push_warning("HillBaked: %s missing — run tools/bake_hills.tscn to bake hills." % BAKED_PATH)
		return _cache
	var file := FileAccess.open(BAKED_PATH, FileAccess.READ)
	if file == null:
		push_warning("HillBaked: could not open %s." % BAKED_PATH)
		return _cache
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("HillBaked: %s did not parse." % BAKED_PATH)
		return _cache
	_cache = parsed
	if str(_cache.get("source_hash", "")) != source_hash():
		push_warning("HillBaked: baked hills are STALE (map CSVs or generator changed) — rerun tools/bake_hills.tscn.")
	return _cache

static func source_hash() -> String:
	var blob := "v%d|seed%d" % [HillField.GEN_VERSION, SEED]
	for path in SOURCE_CSVS:
		blob += "|" + FileAccess.get_md5(path)
	return blob.md5_text()

## Paint-ordered polygons: Array of {b: int band, p: PackedVector2Array}.
static func polys() -> Array:
	var out: Array = []
	for entry in data().get("polys", []):
		var flat: Array = entry.get("p", [])
		var pts := PackedVector2Array()
		var i := 0
		while i + 1 < flat.size():
			pts.append(Vector2(float(flat[i]), float(flat[i + 1])))
			i += 2
		out.append({"b": int(entry.get("b", 1)), "p": pts})
	return out

## tile_id -> Array of blocked subtile bit indices ((row-1)*27 + (col-1)).
static func blocked() -> Dictionary:
	return data().get("blocked", {})

## Organic lake polygons (drawn river-coloured over the bands).
static func lakes() -> Array:
	var out: Array = []
	for entry in data().get("lakes", []):
		out.append(_unflatten(entry.get("p", [])))
	return out

## Paint-ordered coast/sea polygons: {b: 0..5, p} where 0 = lv -6 navy,
## 4 = shelf (river blue), 5 = land base (beige). Drawn UNDER the land bands.
static func sea() -> Array:
	var out: Array = []
	for entry in data().get("sea", []):
		out.append({"b": int(entry.get("b", 5)), "p": _unflatten(entry.get("p", []))})
	return out

## Roads-v2 routing navgrid (12u lattice: band + water class + water distance).
static func navgrid() -> Dictionary:
	return data().get("navgrid", {})

static func _unflatten(flat: Array) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var i := 0
	while i + 1 < flat.size():
		pts.append(Vector2(float(flat[i]), float(flat[i + 1])))
		i += 2
	return pts
