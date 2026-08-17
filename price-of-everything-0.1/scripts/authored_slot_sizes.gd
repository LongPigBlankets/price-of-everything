extends RefCounted
## Which slot size each building needs.
##
## THE RULE (owner, 2026-08-16, split four ways 2026-08-17): `area` is farms and forests,
## whose authored polygon becomes the footprint. Everything else lands in the smallest BOX
## class whose ceiling its art fits under — see `AuthoredMap.SLOT_CLASS_CEILINGS`. The split
## exists because one wide class reserves ground for nobody: before it, the average medium
## building covered 48% of its slot.
##
## CLASSIFIED BY MAXIMUM-LEVEL EXTENT, never by the level a building happens to be at. That
## is not a choice — it is what the engine already does: every level shares the L3 frame and
## an L1 building already reserves the ground its L3 form needs
## (`_test_ink_art_reserves_upgrade_space`). Sizing a slot to an L1 footprint would strand
## the upgrade.
##
## The table is DERIVED, not hand-written, so it cannot drift from the art. Run
## `tools/map_editor/slot_size_table.tscn` to print it for review; per-building overrides go
## in [constant OVERRIDES] and are the owner's to set.
##
## Deliberately has NO `class_name` (the headless global-class-cache trap).

const AuthoredMap := preload("res://scripts/authored_map.gd")
## The art's own size constants, read rather than copied. One direction only: building_visuals
## must never preload this file back, or the two form a cycle.
const BuildingVisualsRef := preload("res://scenes/building_visuals.gd")

## Buildings whose class the owner has fixed by hand, whatever the art measures.
const OVERRIDES := {}

## Internal names that take an authored POLYGON rather than a slot: their footprint is the
## shape the designer drew, not a box the art is fitted into.
##
## These are CATALOG internal names, checked against the catalog by
## `_test_authored_area_buildings_exist`. The list used to read
## ["farm", "forest", "forestry", "tree_farm"] — three of which are not buildings in this
## game at all, while the two that are (`new_forest`, `old_forest`) were missing. Both
## forests were therefore being sized into a box like any factory.
const AREA_BUILDINGS := ["farm", "new_forest", "old_forest"]


## The class a building needs, from its catalog entry.
static func class_for_building(building_id: String) -> String:
	var building: Dictionary = Catalog.get_building(building_id)
	var internal := str(building.get("internal_name", ""))
	if OVERRIDES.has(internal):
		return str(OVERRIDES[internal])
	if AREA_BUILDINGS.has(internal):
		return AuthoredMap.SLOT_AREA_CLASS
	return AuthoredMap.slot_class_for(max_extent_for(internal, building), false)


## The largest drawn size this building ever reaches, in world units.
##
## Mirrors `BuildingVisuals._art_size_for`: the drawn target scales with the building's
## `size_units` between ART_DRAWN_MIN and ART_DRAWN_MAX, with a per-recipe override for the
## few that are sized deliberately. Reading the same constants rather than guessing keeps the
## table honest when they are retuned.
static func max_extent_for(internal_name: String, building: Dictionary) -> float:
	var size_units := float(building.get("tile_size_used", 1.0))
	var art_key := str(BuildingVisualsRef.INK_ART_KEY.get(internal_name, internal_name))
	if BuildingVisualsRef.ART_SIZE_OVERRIDE.has(art_key):
		return float(BuildingVisualsRef.ART_SIZE_OVERRIDE[art_key])
	# CSV size runs 1..30; the drawn size lerps across that range.
	var t := clampf((size_units - 1.0) / 29.0, 0.0, 1.0)
	return lerpf(BuildingVisualsRef.ART_DRAWN_MIN, BuildingVisualsRef.ART_DRAWN_MAX, t)


## The whole table, for review and for tests: `[{internal, id, size_units, extent, class}]`,
## sorted by extent so the boundary cases sit next to each other.
static func table() -> Array:
	var rows: Array = []
	for building_value in Catalog.all_buildings():
		var building: Dictionary = building_value
		var internal := str(building.get("internal_name", ""))
		if internal == "":
			continue
		rows.append({
			"internal": internal,
			"id": str(building.get("id", "")),
			"size_units": float(building.get("tile_size_used", 1.0)),
			"extent": max_extent_for(internal, building),
			"class": class_for_building(str(building.get("id", ""))),
		})
	rows.sort_custom(func(a, b) -> bool: return float(a["extent"]) < float(b["extent"]))
	return rows
