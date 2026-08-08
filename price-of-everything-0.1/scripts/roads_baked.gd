class_name RoadsBaked
extends RefCounted
## Loader for the baked starting anchor network (data/roads_baked.json,
## produced by tools/bake_roads.tscn). A fresh match imports this into
## RoadNetwork so the trunk spine exists from turn 0 and runtime routing
## collapses to cheap connect-to-anchor jobs (spec 4.5b).

const BAKED_PATH := "res://data/roads_baked.json"
## Alternate bakes, swappable in-match by the `swap density` cheat. The road layout
## is an OFFLINE artefact (a bake is ~25s), so comparing two densities live means
## shipping both files and re-seeding from the other one — not re-baking.
const VARIANTS := {
	"dense": BAKED_PATH,                              # shipped default (region overlay applied)
	"baseline": "res://data/roads_baked_baseline.json",  # pre-overlay, for A/B
}

static var _cache: Dictionary = {}
static var _loaded := false
static var _variant := "dense"

static func variant() -> String:
	return _variant

## Point the loader at another bake and drop the cache. Callers must re-seed
## RoadNetwork afterwards — this only changes what the next data() call reads.
static func set_variant(name: String) -> bool:
	if not VARIANTS.has(name) or not FileAccess.file_exists(str(VARIANTS[name])):
		return false
	_variant = name
	_cache = {}
	_loaded = false
	return true

static func path() -> String:
	return str(VARIANTS.get(_variant, BAKED_PATH))

static func data() -> Dictionary:
	if _loaded:
		return _cache
	_loaded = true
	var baked_path := path()
	if not FileAccess.file_exists(baked_path):
		push_warning("RoadsBaked: %s missing — run tools/bake_roads.tscn (after bake_hills)." % baked_path)
		return _cache
	var file := FileAccess.open(baked_path, FileAccess.READ)
	if file == null:
		return _cache
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("RoadsBaked: %s did not parse." % baked_path)
		return _cache
	_cache = parsed
	if str(_cache.get("hills_hash", "")) != HillBaked.source_hash():
		push_warning("RoadsBaked: starting network is STALE vs the terrain bake — rerun tools/bake_roads.tscn.")
	return _cache

static func network_state() -> Dictionary:
	return data().get("network", {})

static func anchors() -> Array:
	return data().get("anchors", [])

## roads-v3: every tile the baked network crosses (anchors + corridor tiles).
## A fresh match applies "roads" infrastructure to all of these.
static func flagged_tiles() -> Array:
	return data().get("flagged_tiles", [])

static func reset_for_tests() -> void:
	_cache = {}
	_loaded = false
