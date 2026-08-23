extends RefCounted
## Runtime reader/writer for the baked START LAYOUT — where every match-start building stands,
## and all the per-tile working state its placement produced. Written by
## tools/bake_start_layout.tscn, read by world_map at the top of the placement passes.
##
## WHY IT EXISTS. Laying out the ~417 start buildings was 55 s of every new-game load, and it
## computed the same answer every time: the packer is seeded, the map is hand-authored, the
## road network comes off its own bake, and the sim half of the job (MatchState.add_building)
## measured 4.5 ms for the whole set. All 55 s was the VISUAL half — searching each tile for a
## spot the search had already found on every previous run.
##
## ABSENCE IS NORMAL, AND SO IS DISAGREEMENT. With no bake, or a bake whose inputs have moved,
## the placement passes run exactly as they always did. With a bake that is valid but does not
## know about some particular building, that ONE building is placed live and any placement the
## bake holds for a building the game no longer emits is removed. So the failure modes are
## "slower" and "slower for one tile", never "wrong picture".
##
## TWO SEPARATE QUESTIONS, ANSWERED SEPARATELY:
##
##   WHERE things go — the map document, the road bake, the hill bake, the tile CSV, and the
##   placement code itself. If any of these move, every answer in the file is suspect, so the
##   whole bake is refused (`content_hash`).
##
##   WHAT is placed — which buildings the passes emit, which depends on the start, the ruleset
##   and the catalog. This is NOT hashed: it is reconciled per building at emit time, because
##   adding one building to start_buildings.json should not throw away 400 good answers.

const AuthoredMap := preload("res://scripts/authored_map.gd")

const BAKE_PATH := "res://data/start_layout_bake.bin"
const REBAKE_HINT := "rerun tools/bake_start_layout.tscn"

## Bumped when placement itself changes — the packer, the masks, the block grid, the
## subcomponent build, or the shape of the exported state. An old file is then refused rather
## than believed, which is the difference between a slow load and a wrong map.
const BAKE_VERSION := 1

## Files that decide WHERE a building can stand. A change to any of them invalidates the
## whole bake. (start_buildings.json / ports.csv are deliberately NOT here: they decide WHAT
## is placed, which is reconciled per building instead.)
const PLACEMENT_INPUTS := [
	"res://data/hills_baked.json",       # water, elevation and the coastline the masks cut against
	"res://data/roads_baked.json",       # the start road network buildings lay out along
	"res://data/tile_properties.csv",    # tile types, so which tiles are land at all
	"res://data/river_properties.csv",   # river arms and their reserved bank corridors
]

static var _cache: Dictionary = {}
static var _loaded := false


## Identity of everything that decides WHERE things go. The active authored document is
## included by md5 — it carries the zones, slots and decorative fabric placement reads.
static func content_hash() -> String:
	var blob := "v%d" % BAKE_VERSION
	for path in PLACEMENT_INPUTS:
		blob += "|" + FileAccess.get_md5(path)
	var doc: String = AuthoredMap.active_name()
	blob += "|doc=" + doc
	if doc != "":
		blob += "|" + FileAccess.get_md5(AuthoredMap.path_for(doc))
	return blob.md5_text()


## The baked state, or an empty dictionary when there is nothing usable on disk.
static func state() -> Dictionary:
	if _loaded:
		return _cache
	_loaded = true
	if not FileAccess.file_exists(BAKE_PATH):
		return _cache   # no bake yet: the placement passes run as they always did
	var file := FileAccess.open(BAKE_PATH, FileAccess.READ)
	if file == null:
		return _cache
	# Binary, not JSON: the state is full of PackedByteArray masks, PackedVector2Array
	# footprints, Vector2i coords and Rect2 bounds, and store_var/get_var round-trips every
	# one of those EXACTLY. A JSON round-trip would hand back Arrays of floats and every
	# typed consumer downstream would break on the first draw.
	var parsed: Variant = file.get_var(false)   # false: no Objects in, none out
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("StartLayoutBaked: %s did not parse — %s." % [BAKE_PATH, REBAKE_HINT])
		return _cache
	var doc: Dictionary = parsed
	if int(doc.get("bake_version", -1)) != BAKE_VERSION:
		_warn("StartLayoutBaked: bake is version %s, this build wants %d — %s."
			% [str(doc.get("bake_version", "?")), BAKE_VERSION, REBAKE_HINT])
		return _cache
	if str(doc.get("content_hash", "")) != content_hash():
		_warn("StartLayoutBaked: the map, roads or hills have changed since the layout was baked — placing live. %s."
			% REBAKE_HINT)
		return _cache
	_cache = doc
	return _cache


static func is_available() -> bool:
	return not state().is_empty()


## Write a freshly-computed layout. Called only by the bake tool.
static func save(layout: Dictionary) -> bool:
	var doc := {
		"bake_version": BAKE_VERSION,
		"content_hash": content_hash(),
		"layout": layout,
	}
	var file := FileAccess.open(BAKE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("StartLayoutBaked: could not write %s." % BAKE_PATH)
		return false
	file.store_var(doc, false)
	file.close()
	return true


## The layout payload itself (what building_visuals.import_layout_state consumes).
static func layout() -> Dictionary:
	var doc := state()
	var value: Variant = doc.get("layout", {})
	return value if typeof(value) == TYPE_DICTIONARY else {}


static func reset_for_tests() -> void:
	_cache = {}
	_loaded = false


static func _warn(message: String) -> void:
	push_warning(message)
	print(message)
