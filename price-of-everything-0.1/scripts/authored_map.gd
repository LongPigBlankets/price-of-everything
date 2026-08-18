extends RefCounted
## Loader, schema and writer for the hand-authored map document
## (`data/map_authored.json`, produced by the map editor — see
## `docs/map-editor-plan.md`).
##
## The document holds the hand-drawn look of a settlement: roads (curves and
## straights in three width classes, some revealed only when their tiles gain the
## road flag), decorative masses, parks, farm and forest polygons, and the slots
## gameplay buildings drop into. Only PRESENTATION lives here. Nothing in this file
## reaches the simulation: per-tile infrastructure flags and levels remain the sole
## gameplay surface (CLAUDE.md, "what on the map is GAMEPLAY and what is AESTHETIC").
##
## ABSENCE IS NORMAL. The feature is opt-in, exactly like the midcentury style: with
## no document on disk every getter returns empty, [method covers] is false for every
## tile, and the game renders precisely as it does today. This is why a missing file
## is silent here, unlike `roads_baked.gd` where absence means a broken bake.
##
## Deliberately has NO `class_name`, following `scripts/mass_form_shapes.gd`: a newly
## declared global class is absent from the headless global-script-class cache until an
## `--import`, and the suite then fails with "Identifier not declared". Reference it as
##     const AuthoredMap := preload("res://scripts/authored_map.gd")
##
## The EDITOR writes this file; the GAME only reads it. Editor-only code lives under
## `scripts/map_editor/` and is excluded from exported builds — this loader is not, and
## must never reference it.

## Where documents live. `res://` because these are authored content committed with the
## project (the `data/*.json` convention: hills, roads, start buildings, settlement
## profiles), not player data.
##
## THERE ARE MANY DOCUMENTS AND ONE ACTIVE ONE. The editor saves under a name so variants
## can be tried side by side and compared; the game reads whichever is named in
## [constant ACTIVE_PATH]. Picking a different one is a one-line change to that file, by
## hand or from the editor — no copying, and nothing about the losing variants is lost.
const DOC_DIR := "res://data/map_authored"
## A single line naming the active document, without the `.json`. A plain text pointer
## rather than a key inside one of the documents: whichever document is chosen, the choice
## is not part of any of them.
const ACTIVE_PATH := "res://data/map_authored/active.txt"

## Filename characters allowed in a document name. Everything else is rejected rather than
## sanitised, so a name in the editor is always the name on disk.
const NAME_PATTERN := "^[A-Za-z0-9 _-]{1,48}$"

## Bumped when the document's shape changes in a way older files cannot satisfy.
## [method validate] rejects a future version; a past version is a migration decision.
const SCHEMA_VERSION := 1

## Road width classes, in WORLD UNITS, measured as the carriageway bed. Derived from the
## owner's 20/14/7 px at full zoom: the camera clamps `zoom_max` to `viewport.y / 1200`
## (`camera_controller.gd`), i.e. ~1.107 px per world unit on a 1328-tall window, so the
## spec's pixels are these world widths. Stored in world units because the pixel figure is
## display-relative while the geometry must not be — roads are zoom-invariant
## (`docs/map-editor-plan.md` section 2), so these never vary with camera zoom.
const ROAD_WIDTHS := {
	"major": 18.0,
	"mid": 12.6,
	"minor": 6.3,
}

## Slot size classes. ONE box for every non-infrastructure building (owner, 2026-08-17).
##
## The four-way split it replaces was tighter per building but wrong in practice: a slot is
## authored before anyone knows what will stand in it, and the player picks by economics, not
## by the mix a designer guessed. A tile over good ore fills with mines while its small slots
## sit empty. One box dissolves that — every slot takes any non-infra building — at the cost
## of reserving for the largest member everywhere.
##
## `infra` is separate because pipes, cables, rails and the airport draw at a third the size
## and giving them a standard box would waste most of a tile. It is decided by MEASURED ART,
## not by `category == "infrastructure"` — that category also holds the PORT, a full 60 u
## building that would have been seated in a 44 u box. The art separates them cleanly on its
## own: those five draw at 30-31.3 and the smallest of everything else is 41.8.
##
## `area` is not a box at all: farms take an authored polygon as their footprint, so a
## building may not have an `area` slot for being "bigger". Forests are `area` by
## classification but never reach a slot — ForestVisuals draws them.
##
## Classification is by MAXIMUM-level extent, which matches the engine: a building already
## reserves its L3 frame at L1 (pinned by `_test_ink_art_reserves_upgrade_space`).
const SLOT_BOX_CLASSES := ["infra", "standard"]
const SLOT_AREA_CLASS := "area"
const SLOT_CLASSES := ["infra", "standard", "area"]

## Legacy class names, mapped to what they mean now. Documents authored before the unified
## box carry these, and a document that fails validation never loads — so they are migrated
## on read rather than rejected. Every old BOX class becomes `standard`: the unified box is
## at least as large as any of them, so the reservation a designer made still holds.
const LEGACY_SLOT_CLASSES := {
	"very_small": "infra",
	"small": "standard",
	"medium": "standard",
	"large": "standard",
}

## The DRAWN-ART extent each box class tops out at, world units, turned into reserved ground
## by `building_visuals.AUTHORED_SLOT_BOXES`.
##
## `standard` must clear the largest drawn thing, which is the MINE and the SOLAR FARM at
## 61.4 — not ART_DRAWN_MAX. It was 68 (= ART_DRAWN_MAX) while the wind farms were pinned
## there by ART_SIZE_OVERRIDE; compressing them to 70% took them to 47.6 and let this follow,
## which is worth 6 u off the reserved box of EVERY building on the map (84 -> 78).
##
## Tracks the art rather than the band, so retune it with `tile_size_used` and the overrides.
## `_test_authored_slot_box_holds_its_class` fails the moment a building outgrows it, and it
## asserts the fit is TIGHT as well, so this cannot quietly drift back up either.
const SLOT_CLASS_CEILINGS := {
	"infra": 32.0,
	"standard": 62.0,
}

## Farm and forest outlines are authored as simple polygons of at most this many vertices.
const AREA_MAX_VERTICES := 8

## INDUSTRIAL ZONES (docs/industrial-zones-plan.md). A zone reserves no ground and has no
## size — it is the region a gameplay building may be placed IN, which is what lets a tile
## hold six mines or thirteen workshops depending on what the player builds, instead of
## whatever mix of slot sizes a designer guessed.
##
## `industrial` is used first; `industrial_reserve` only once it is full, so a town visibly
## spills into its reserve rather than silently refusing a building. `extraction` is for
## mines and wells — the buildings that are hardcoded to seek a tile edge today — and is the
## only kind that gates WHO may use it.
##
## WATER PUMPS ARE NOT EXTRACTION (owner, 2026-08-17): they take the industrial zones like any
## other plant, whatever their recipe looks like. Recorded here because the name invites the
## opposite assumption every time.
const ZONE_KINDS := ["industrial", "industrial_reserve", "extraction"]

## Zones are drawn to fit a tile's usable ground rather than a building, so they need more
## corners than a farm field does.
const ZONE_MAX_VERTICES := 10

static var _cache: Dictionary = {}
static var _loaded := false
## Set by the tools to read a specific document regardless of the active pointer.
static var _override_name := ""
## tile_id -> settlement key, built lazily from the settlements' `tiles` lists.
static var _tile_index: Dictionary = {}
static var _tile_index_built := false


## The parsed document, or an empty one when no file is present (the normal state until
## authoring begins). Cached for the process; call [method reset_for_tests] to reload.
static func data() -> Dictionary:
	if _loaded:
		return _cache
	_loaded = true
	var path := active_path()
	if path == "" or not FileAccess.file_exists(path):
		return _cache   # opt-in feature: no document is not an error
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("AuthoredMap: %s exists but could not be opened." % path)
		return _cache
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("AuthoredMap: %s did not parse as a document." % path)
		return _cache
	var doc: Dictionary = parsed
	var errors := validate(doc)
	if not errors.is_empty():
		# Refuse a malformed document rather than half-drawing it: a partially applied
		# authored map would suppress procedural fabric it cannot replace.
		push_warning("AuthoredMap: %s rejected — %s" % [path, ", ".join(errors)])
		return _cache
	if str(doc.get("hills_hash", "")) != HillBaked.source_hash():
		push_warning("AuthoredMap: authored map is STALE vs the terrain bake — "
			+ "relief may have moved under the authored geometry.")
	_cache = doc
	return _cache


## True when the document has any authored content at all. Callers that suppress
## procedural systems should gate on this first: it is the cheap "is this feature even
## in use" test, and it keeps an empty install on exactly today's code paths.
static func is_active() -> bool:
	return not settlements().is_empty()


static func settlements() -> Dictionary:
	var doc := data()
	var value: Variant = doc.get("settlements", {})
	return value if typeof(value) == TYPE_DICTIONARY else {}


## Every authored tile id -> the settlement key that authored it.
static func tile_index() -> Dictionary:
	if _tile_index_built:
		return _tile_index
	_tile_index_built = true
	_tile_index = {}
	var all := settlements()
	var keys := all.keys()
	keys.sort()   # deterministic ownership when two settlements name the same tile
	for key in keys:
		var settlement: Dictionary = all[key]
		for tile_value in _array(settlement, "tiles"):
			var tile_id := str(tile_value)
			if not _tile_index.has(tile_id):
				_tile_index[tile_id] = str(key)
	return _tile_index


## THE SUPPRESSION KEY. True when this tile's look is hand-authored, and the procedural
## fabric, forest discs, accommodation sites and road-geometry jobs must stand down for it
## (`docs/map-editor-plan.md` section 6). Cheap enough for per-tile calls.
static func covers(tile_id: String) -> bool:
	return tile_index().has(tile_id)


## The settlement dictionary that authored `tile_id`, or an empty dictionary.
static func settlement_for_tile(tile_id: String) -> Dictionary:
	var key: String = str(tile_index().get(tile_id, ""))
	if key == "":
		return {}
	var value: Variant = settlements().get(key, {})
	return value if typeof(value) == TYPE_DICTIONARY else {}


static func roads_for_settlement(key: String) -> Array:
	var value: Variant = settlements().get(key, {})
	return _array(value if typeof(value) == TYPE_DICTIONARY else {}, "roads")


## Slots authored for one tile: `{pins, frames, large, area}`. Always returns every key so
## callers need no defaults. `large` is the legacy name of the polygon list and is kept so
## older documents still read; `area` is the same list under the name the classes now use.
static func slots_for_tile(tile_id: String) -> Dictionary:
	var settlement := settlement_for_tile(tile_id)
	var slots_value: Variant = settlement.get("slots", {})
	var slots: Dictionary = slots_value if typeof(slots_value) == TYPE_DICTIONARY else {}
	var tile_value: Variant = slots.get(tile_id, {})
	var tile_slots: Dictionary = tile_value if typeof(tile_value) == TYPE_DICTIONARY else {}
	return {
		"pins": _array(tile_slots, "pins"),
		"frames": _array(tile_slots, "frames"),
		"large": _array(tile_slots, "large"),
		"area": _array(tile_slots, "area"),
	}


## A road stroke is visible when EVERY tile it touches carries the road flag — the
## connection rule (owner, 2026-08-16). A stroke inside one roadless tile appears when
## that tile gains roads; a connector from an already-roaded neighbour appears exactly
## when the new tile can join it, and appears whole rather than as a stub at the seam.
## `flagged` is the same `{tile_id: true}` shape the road renderer builds.
static func road_visible(stroke: Dictionary, flagged: Dictionary) -> bool:
	if not bool(stroke.get("unlockable", false)):
		return true
	for tile_value in _array(stroke, "tiles"):
		if not flagged.has(str(tile_value)):
			return false
	return true


## Bed width in world units for a stroke's class, defaulting to `mid` for an unknown one
## (a document that fails validation never reaches a renderer, so this is belt-and-braces).
static func road_width(stroke_class: String) -> float:
	return float(ROAD_WIDTHS.get(stroke_class, ROAD_WIDTHS["mid"]))


## The slot class a building belongs in, from the largest extent its art ever reaches.
## `is_area` marks farms and forests, which take an authored polygon as their footprint.
## A stored class name as this build understands it, migrating legacy names.
static func canonical_slot_class(value: String) -> String:
	if SLOT_CLASSES.has(value):
		return value
	return str(LEGACY_SLOT_CLASSES.get(value, SLOT_BOX_CLASSES[SLOT_BOX_CLASSES.size() - 1]))


static func slot_class_for(max_extent: float, is_area: bool) -> String:
	if is_area:
		return SLOT_AREA_CLASS
	for slot_class in SLOT_BOX_CLASSES:
		if max_extent < float(SLOT_CLASS_CEILINGS[slot_class]):
			return slot_class
	# Above every ceiling: the biggest box is still the honest answer, and the box test is
	# what catches art that has outgrown it.
	return SLOT_BOX_CLASSES[SLOT_BOX_CLASSES.size() - 1]


## May a building of class `wanted` stand in a slot of class `offered`? Equal or larger only,
## and never in an `area` slot — that is a farm polygon, not a bigger box.
static func slot_fits(wanted: String, offered: String) -> bool:
	if offered == SLOT_AREA_CLASS or wanted == SLOT_AREA_CLASS:
		return wanted == offered
	var wanted_rank := SLOT_BOX_CLASSES.find(wanted)
	var offered_rank := SLOT_BOX_CLASSES.find(offered)
	return wanted_rank >= 0 and offered_rank >= wanted_rank


## An empty, valid document — what the editor starts from and what the game falls back to.
static func empty_document() -> Dictionary:
	return {
		"version": SCHEMA_VERSION,
		"hills_hash": HillBaked.source_hash(),
		"settlements": {},
	}


## Schema check. Returns an empty array for a good document, else one message per problem.
## Shared by the loader, the editor's save path and the unit suite, so a document that
## loads in game is exactly one the editor would have written.
static func validate(doc: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	var version := int(doc.get("version", 0))
	if version <= 0:
		errors.append("missing 'version'")
	elif version > SCHEMA_VERSION:
		errors.append("version %d is newer than this build understands (%d)" % [version, SCHEMA_VERSION])
	var settlements_value: Variant = doc.get("settlements", {})
	if typeof(settlements_value) != TYPE_DICTIONARY:
		errors.append("'settlements' must be a dictionary")
		return errors
	var all: Dictionary = settlements_value
	for key_value in all.keys():
		var key := str(key_value)
		var settlement_value: Variant = all[key_value]
		if typeof(settlement_value) != TYPE_DICTIONARY:
			errors.append("settlement '%s' is not a dictionary" % key)
			continue
		var settlement: Dictionary = settlement_value
		if _array(settlement, "tiles").is_empty():
			errors.append("settlement '%s' names no tiles" % key)
		for road_value in _array(settlement, "roads"):
			if typeof(road_value) != TYPE_DICTIONARY:
				errors.append("settlement '%s' has a malformed road" % key)
				continue
			errors.append_array(_validate_road(key, road_value))
		for field in ["farms", "forests"]:
			for area_value in _array(settlement, field):
				if typeof(area_value) != TYPE_DICTIONARY:
					errors.append("settlement '%s' has a malformed %s entry" % [key, field])
					continue
				errors.append_array(_validate_area(key, field, area_value))
		errors.append_array(_validate_slots(key, settlement))
		for zone_value in _array(settlement, "zones"):
			if typeof(zone_value) != TYPE_DICTIONARY:
				errors.append("settlement '%s' has a malformed zone" % key)
				continue
			errors.append_array(_validate_zone(key, zone_value))
	return errors


## A zone is an area like a farm, with a kind that decides who may build in it.
static func _validate_zone(key: String, zone: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	var id := str(zone.get("id", ""))
	if id == "":
		errors.append("settlement '%s' has a zone with no id" % key)
	var kind := str(zone.get("kind", ""))
	if not ZONE_KINDS.has(kind):
		errors.append("zone '%s' has unknown kind '%s'" % [id, kind])
	var outline := _array(zone, "outline")
	if outline.size() < 3:
		errors.append("zone '%s' needs at least three corners" % id)
	elif outline.size() > ZONE_MAX_VERTICES:
		errors.append("zone '%s' has %d corners (max %d)"
			% [id, outline.size(), ZONE_MAX_VERTICES])
	return errors


## Every zone of one kind over a tile, for the placement mask and for the editor.
static func zones_for_tile(tile_id: String, kind: String) -> Array:
	var settlement := settlement_for_tile(tile_id)
	var out: Array = []
	for zone_value in _array(settlement, "zones"):
		if typeof(zone_value) != TYPE_DICTIONARY:
			continue
		var zone: Dictionary = zone_value
		if str(zone.get("kind", "")) != kind:
			continue
		var tiles: Array = _array(zone, "tiles")
		if tiles.is_empty() or tiles.has(tile_id):
			out.append(zone)
	return out


## Slots reserve the ground a gameplay building will stand on, so a malformed one is not a
## drawing defect — it is a building with nowhere legal to go, discovered at build time. The
## readers all coerce defensively, which means a bad slot block loads quietly and fails much
## later; validating here turns that into a refused save.
static func _validate_slots(key: String, settlement: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	var slots_value: Variant = settlement.get("slots", {})
	if typeof(slots_value) != TYPE_DICTIONARY:
		errors.append("settlement '%s' has a malformed 'slots' block" % key)
		return errors
	var slots: Dictionary = slots_value
	for tile_value in slots.keys():
		var tile_id := str(tile_value)
		if typeof(slots[tile_value]) != TYPE_DICTIONARY:
			errors.append("slots for '%s' are not a dictionary" % tile_id)
			continue
		var pins_value: Variant = (slots[tile_value] as Dictionary).get("pins", [])
		if typeof(pins_value) != TYPE_ARRAY:
			errors.append("slot pins for '%s' are not a list" % tile_id)
			continue
		var pins: Array = pins_value
		for index in pins.size():
			if typeof(pins[index]) != TYPE_DICTIONARY:
				errors.append("slot %d on '%s' is not a dictionary" % [index, tile_id])
				continue
			var pin: Dictionary = pins[index]
			var slot_class := str(pin.get("size", ""))
			if not SLOT_CLASSES.has(slot_class) and not LEGACY_SLOT_CLASSES.has(slot_class):
				errors.append("slot %d on '%s' has unknown size '%s'"
					% [index, tile_id, slot_class])
			var pos_value: Variant = pin.get("pos", null)
			if typeof(pos_value) != TYPE_ARRAY or (pos_value as Array).size() < 2:
				errors.append("slot %d on '%s' needs a two-number 'pos'" % [index, tile_id])
	return errors


static func _validate_road(key: String, road: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	var id := str(road.get("id", ""))
	if id == "":
		errors.append("settlement '%s' has a road with no id" % key)
	var stroke_class := str(road.get("class", ""))
	if not ROAD_WIDTHS.has(stroke_class):
		errors.append("road '%s' has unknown class '%s'" % [id, stroke_class])
	if _array(road, "points").size() < 2:
		errors.append("road '%s' needs at least two points" % id)
	# The connection rule needs the touched-tile set; without it an unlockable stroke
	# would either never appear or appear unconditionally.
	if bool(road.get("unlockable", false)) and _array(road, "tiles").is_empty():
		errors.append("road '%s' is unlockable but lists no tiles" % id)
	return errors


static func _validate_area(key: String, field: String, area: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	var id := str(area.get("id", ""))
	if id == "":
		errors.append("settlement '%s' has a %s with no id" % [key, field])
	var outline := _array(area, "outline")
	if outline.size() < 3:
		errors.append("%s '%s' needs at least three vertices" % [field, id])
	elif outline.size() > AREA_MAX_VERTICES:
		errors.append("%s '%s' has %d vertices (max %d)" % [field, id, outline.size(), AREA_MAX_VERTICES])
	return errors


## The document as it will exist after a load. Godot's JSON parser returns EVERY number as
## a float, so `{"cols": 3}` reads back as `3.0` — meaning a document that had been saved,
## loaded and saved again would differ byte-for-byte from one saved straight after
## authoring, purely by edit history. This file is committed to git and hand-reviewed, so
## that churn is not acceptable: writing the canonical form makes saving IDEMPOTENT.
## (Consumers must still not assume int types — read through `int()`/`float()`.)
static func canonical(doc: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(doc))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


## Serialise exactly as [method save_to] writes: pretty-printed, sorted keys, canonical
## number types. Exposed so the editor and the suite can compare documents by their written
## bytes rather than by in-memory equality, which JSON cannot preserve.
static func to_text(doc: Dictionary) -> String:
	return JSON.stringify(canonical(doc), "  ", true)


## Write a document to an ABSOLUTE path (the editor globalizes the document path first —
## `FileAccess` writes to `res://` do not persist in a running build; see
## `tools/strip_icon_bg.gd`). Refuses to write a document that would not load.
## Returns an empty string on success, else the reason.
## Names a harness may write. Anything running under POE_EDITOR_SCRATCH is a TOOL, and a
## tool has no business writing a document a person drew.
const SCRATCH_ONLY_NAMES := ["__scratch__", "_unlock_check", "_slot_check", "_probe"]


## Is this process a harness rather than a person editing? Scratch mode is set by every tool
## that drives the editor from synthetic input.
static func is_scratch_process() -> bool:
	return OS.get_environment("POE_EDITOR_SCRATCH") == "1"


## THE WRITE BARRIER.
##
## A harness clicked a real document twice in this project's life: once it pressed the panel's
## Save button and grew stoneshore-alpha from 35 records to 84, and once it moved five slot
## pins and deleted a road from stoneshore-procedural. Both times the tool believed it was in
## scratch mode. Convention is clearly not enough, so this is a rule the writer enforces
## rather than a promise the caller makes: under POE_EDITOR_SCRATCH, only a scratch name can
## be written, whatever the caller passes and however the override got lost.
static func writable(absolute_path: String) -> String:
	if not is_scratch_process():
		return ""
	var name := absolute_path.get_file().get_basename()
	if SCRATCH_ONLY_NAMES.has(name):
		return ""
	return "refusing to write '%s': this process is a harness (POE_EDITOR_SCRATCH)" % name


static func save_to(doc: Dictionary, absolute_path: String) -> String:
	var barred := writable(absolute_path)
	if barred != "":
		push_error("[AuthoredMap] %s" % barred)
		return barred
	var errors := validate(doc)
	if not errors.is_empty():
		return "refusing to save an invalid document: " + ", ".join(errors)
	var file := FileAccess.open(absolute_path, FileAccess.WRITE)
	if file == null:
		return "could not open %s for writing (error %d)" % [absolute_path, FileAccess.get_open_error()]
	file.store_string(to_text(doc))
	file.close()
	return ""


## The full path of a named document.
static func path_for(name: String) -> String:
	return "%s/%s.json" % [DOC_DIR, name]


static func is_valid_name(name: String) -> bool:
	var regex := RegEx.new()
	regex.compile(NAME_PATTERN)
	return regex.search(name) != null


## The name of the document the game reads, or "" when none is set.
static func active_name() -> String:
	if _override_name != "":
		return _override_name
	if not FileAccess.file_exists(ACTIVE_PATH):
		return ""
	var file := FileAccess.open(ACTIVE_PATH, FileAccess.READ)
	if file == null:
		return ""
	var name := file.get_as_text().strip_edges()
	file.close()
	return name


static func active_path() -> String:
	var name := active_name()
	return path_for(name) if name != "" else ""


## Read a specific document for this process, whatever the pointer says. For tools that
## validate a named variant without disturbing which one the game would load.
static func set_override(name: String) -> void:
	_override_name = name
	_cache = {}
	_loaded = false
	_tile_index = {}
	_tile_index_built = false


## Every document name on disk, sorted.
static func list_documents() -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(DOC_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.ends_with(".json"):
			out.append(entry.get_basename())
		entry = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


## Point the game at a document. `absolute_dir` is the globalized `DOC_DIR` — writes to
## `res://` from a running build do not persist, so the caller supplies the real path.
static func write_active(name: String, absolute_dir: String) -> String:
	if not is_valid_name(name):
		return "'%s' is not a usable document name" % name
	DirAccess.make_dir_recursive_absolute(absolute_dir)
	var file := FileAccess.open("%s/active.txt" % absolute_dir, FileAccess.WRITE)
	if file == null:
		return "could not write the active pointer (error %d)" % FileAccess.get_open_error()
	file.store_string(name)
	file.close()
	return ""


## Drop the cache so the next read re-parses, KEEPING any override in place. Used by the
## editor after a save and by tools that have deliberately pointed themselves at one
## document: clearing the override here sent a harness back to whatever the active pointer
## named, which is how scratch mode leaked and a check ran against a real 220-road map.
static func reset_cache() -> void:
	_cache = {}
	_loaded = false
	_tile_index = {}
	_tile_index_built = false


## Full reset, including the override. For the suite, between cases.
## Install a document IN MEMORY, without touching disk. The unit suite needs to exercise
## placement against specific fabric-and-slot arrangements, and the alternative — writing a
## fixture into `data/map_authored/` — would put test files in a tracked directory holding
## hand-drawn work. Pass `{}` to clear.
static func set_document_for_tests(doc: Dictionary) -> void:
	_cache = doc
	_loaded = true
	_tile_index = {}
	_tile_index_built = false


static func reset_for_tests() -> void:
	reset_cache()
	_override_name = ""
	_tile_index = {}
	_tile_index_built = false


static func _array(source: Dictionary, key: String) -> Array:
	var value: Variant = source.get(key, [])
	return value if typeof(value) == TYPE_ARRAY else []
