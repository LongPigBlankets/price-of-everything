extends RefCounted
## A start's legacy perk (docs/pacing-labour-mining-licensing-spec.md §3.2): Metal Magnate's Legacy of Metal and
## Glass Merchant's Ashmouth Glassworks, with Like Family's satisfaction (§4.4), hold while the start's Original
## Furnace is still the player's.
##
## The start file marks the furnace (`"legacy_anchor": true`, `"name": "Original Furnace"`) and each perk modifier
## (`"condition": "legacy_anchor"`). reconcile() runs at PROCESS start, before production: once no building the
## player owns carries the mark, the conditioned modifiers are removed, and since nothing adds them back, buying
## the furnace back does not restore them. Nothing new is saved: the mark rides on the building, the condition on
## the modifier.

const CONDITION := "legacy_anchor"
## The perk's condition, as every place that shows the perk prints it.
const CONDITION_TEXT := "While the original furnace is still owned"
const ANCHOR_NAME := "Original Furnace"


## True while a building the player owns carries the legacy mark.
static func anchor_owned() -> bool:
	for b: Dictionary in BuildingState.buildings.values():
		if bool(b.get(CONDITION, false)) and BuildingState.is_player_owned(b):
			return true
	return false


## True while the start's legacy holds: the Original Furnace is the player's and the perk was never lost. Selling
## the furnace ends it for good, as it ends the perk modifiers; buying it back restores neither. Like Family
## (LabourState.LIKE_FAMILY_SATISFACTION) reads this.
static func holds() -> bool:
	return anchor_owned() and not perk_modifiers().is_empty()


## The modifiers held by the legacy condition.
static func perk_modifiers() -> Array:
	return Modifiers.active().filter(func(m: Dictionary) -> bool: return str(m.get("condition", "")) == CONDITION)


## Removes the perk for good once the Original Furnace is no longer the player's. Idempotent.
static func reconcile() -> void:
	var perks := perk_modifiers()
	if perks.is_empty() or anchor_owned():
		return
	for m: Dictionary in perks:
		Modifiers.remove(str(m.get("id", "")))
	var name := str(perks[0].get("label", "")).get_slice(":", 0)
	EventScheduler.emit_event({"kind": "legacy_lost", "severity": "warning", "title": "%s ends" % name,
		"body": "The Original Furnace has left the company. %s is gone for good." % name,
		"source": "legacy", "persistent": false, "auto_dismiss_turns": 5})


## A save from before the anchor existed: its start perks gain the condition, and the start's furnace, if the
## player still owns one on the start file's tile, becomes the Original Furnace. Without one the perk ends at
## the next reconcile.
static func migrate(start_id: String) -> void:
	var sources := {"metal_magnate": "start:metals_magnate", "glass_merchant": "start:glass_merchant"}
	if not sources.has(start_id):
		return
	var untagged := Modifiers.active().filter(func(m: Dictionary) -> bool:
		return str(m.get("source", "")) == str(sources[start_id]) and str(m.get("condition", "")) == "")
	if untagged.is_empty():
		return
	for m: Dictionary in untagged:
		m["condition"] = CONDITION
	if anchor_owned():
		return
	var cfg: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/starts/%s.json" % start_id))
	for entry: Variant in (cfg.get("buildings", []) if cfg is Dictionary else []):
		if not bool((entry as Dictionary).get(CONDITION, false)):
			continue
		for b: Dictionary in BuildingState.get_buildings_on_tile(str(entry.get("tile_id", ""))):
			if BuildingState.is_player_owned(b) and str(b.get("building_id", "")) == str(entry.get("building_id", "")):
				b[CONDITION] = true
				b["name"] = ANCHOR_NAME
				return
