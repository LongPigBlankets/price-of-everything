class_name RoadsBaked
extends RefCounted
## Loader for the baked starting anchor network (data/roads_baked.json,
## produced by tools/bake_roads.tscn). A fresh match imports this into
## RoadNetwork so the trunk spine exists from turn 0 and runtime routing
## collapses to cheap connect-to-anchor jobs (spec 4.5b).

const BAKED_PATH := "res://data/roads_baked.json"

static var _cache: Dictionary = {}
static var _loaded := false

static func data() -> Dictionary:
	if _loaded:
		return _cache
	_loaded = true
	if not FileAccess.file_exists(BAKED_PATH):
		push_warning("RoadsBaked: %s missing — run tools/bake_roads.tscn (after bake_hills)." % BAKED_PATH)
		return _cache
	var file := FileAccess.open(BAKED_PATH, FileAccess.READ)
	if file == null:
		return _cache
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("RoadsBaked: %s did not parse." % BAKED_PATH)
		return _cache
	_cache = parsed
	if str(_cache.get("hills_hash", "")) != HillBaked.source_hash():
		push_warning("RoadsBaked: starting network is STALE vs the terrain bake — rerun tools/bake_roads.tscn.")
	return _cache

static func network_state() -> Dictionary:
	return data().get("network", {})

static func anchors() -> Array:
	return data().get("anchors", [])

static func reset_for_tests() -> void:
	_cache = {}
	_loaded = false
