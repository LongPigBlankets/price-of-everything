extends RefCounted
## Where every gameplay slot sits in world space, and how big its reserved box is.
##
## EDITOR-ONLY (see the header of `map_editor.gd`): excluded from exported builds.
##
## This was two near-identical builders — one reading the saved document, one reading the
## document being edited — and they drifted. The live one grew `tile_id` and `index` so that
## a click could resolve a box back to the record behind it; the saved one did not. Every
## editor check runs on a scratch document, where the live branch is always the one taken, so
## nothing caught it: the editor crashed the first time it opened a document it had not just
## edited, which is to say the first time anyone used it for real.
##
## So: one builder, one shape, and the tile centres handed in rather than looked up from the
## scene. Node-free means the unit suite can hold it to the shape its callers read, headless,
## against the real map documents — which is the check that was missing.

## The box each class reserves, in world units. Taken from the SHIPPED side rather than
## restated here: `building_visuals.gd` is what actually seats a building in a slot, and an
## editor drawing a box of its own size would be drawing a promise the game does not keep.
const BuildingVisualsRef := preload("res://scenes/building_visuals.gd")
const AuthoredMapRef := preload("res://scripts/authored_map.gd")

## Every key a box carries. The overlay and the click test both read all of these, so this is
## the contract the unit suite pins.
const KEYS := ["centre", "size", "angle", "class", "tile_id", "index"]


static func sizes() -> Dictionary:
	return BuildingVisualsRef.AUTHORED_SLOT_BOXES


static func size_for(slot_class: String) -> Vector2:
	var table := sizes()
	return table.get(AuthoredMapRef.canonical_slot_class(slot_class), table["standard"])


## `centres` maps tile id to that tile's centre in world units. A slot on a tile absent from
## it is skipped rather than drawn at the origin — a document may name a tile this map does
## not have, and a box in the corner of the world is worse than no box.
static func build(settlements: Dictionary, centres: Dictionary) -> Array:
	var out: Array = []
	for key in settlements.keys():
		var settlement_value: Variant = settlements[key]
		if typeof(settlement_value) != TYPE_DICTIONARY:
			continue
		var slots_value: Variant = (settlement_value as Dictionary).get("slots", {})
		if typeof(slots_value) != TYPE_DICTIONARY:
			continue
		var slots: Dictionary = slots_value
		for tile_id in slots.keys():
			if not centres.has(str(tile_id)):
				continue
			var tile_value: Variant = slots[tile_id]
			if typeof(tile_value) != TYPE_DICTIONARY:
				continue
			var pins_value: Variant = (tile_value as Dictionary).get("pins", [])
			if typeof(pins_value) != TYPE_ARRAY:
				continue
			var centre: Vector2 = centres[str(tile_id)]
			var pins: Array = pins_value
			for index in pins.size():
				if typeof(pins[index]) != TYPE_DICTIONARY:
					continue
				var pin: Dictionary = pins[index]
				var pos_value: Variant = pin.get("pos", [0, 0])
				if typeof(pos_value) != TYPE_ARRAY or (pos_value as Array).size() < 2:
					continue
				var pos: Array = pos_value
				var slot_class := AuthoredMapRef.canonical_slot_class(
					str(pin.get("size", "standard")))
				out.append({
					"centre": centre + Vector2(float(pos[0]), float(pos[1])),
					"size": size_for(slot_class),
					"angle": float(pin.get("angle", 0.0)),
					"class": slot_class,
					"tile_id": str(tile_id),
					"index": index,
				})
	return out


## Tile ids a document reserves slots on, for building the centre table.
static func tile_ids(settlements: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for key in settlements.keys():
		var settlement_value: Variant = settlements[key]
		if typeof(settlement_value) != TYPE_DICTIONARY:
			continue
		var slots_value: Variant = (settlement_value as Dictionary).get("slots", {})
		if typeof(slots_value) != TYPE_DICTIONARY:
			continue
		for tile_id in (slots_value as Dictionary).keys():
			if not out.has(str(tile_id)):
				out.append(str(tile_id))
	return out
