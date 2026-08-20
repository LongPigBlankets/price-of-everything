extends Node2D
## Draws authored ground and fabric in the game: farmland, woodland, parks and decorative
## masses (`data/map_authored/<active>.json`).
##
## Sits at `UrbanFabricVisuals`' place in `scenes/main.tscn` — sibling order is the whole
## layering system here — so rivers, buildings and roads all draw over it, exactly as they do
## over the procedural fabric it replaces.
##
## DRAW ORDER WITHIN THE LAYER is ground first, then things standing on it: farmland, parks,
## masses, woodland. Woodland last because a canopy overhangs what it grows beside, and a
## tree drawn under a mass would read as the mass sitting in a hole.
##
## Unlike roads, none of this is unlockable: ground and fabric are simply there. Only roads
## carry the connection rule, because only roads are something the player builds.

const AuthoredMap := preload("res://scripts/authored_map.gd")
const AuthoredFabricPainter := preload("res://scripts/authored_fabric_painter.gd")

var _sacrificed: Dictionary = {}


func _ready() -> void:
	# Findable by the placement path, which evicts a mass when a gameplay building takes the
	# ground it stands on. Same shape as `building_footprints`, and the only coupling between
	# the two — placement reads no fabric geometry from here, it measures the document.
	add_to_group("authored_fabric")
	MapStyle.style_changed.connect(func() -> void: queue_redraw())


## Hide a decorative mass because a gameplay building has taken its ground (the eviction rule
## — only masses marked `sacrificial` in the editor are ever passed here).
func evict(mass_id: String) -> void:
	_sacrificed[mass_id] = true
	queue_redraw()


func restore_all() -> void:
	_sacrificed.clear()
	queue_redraw()


func _draw() -> void:
	if not AuthoredMap.is_active():
		return
	var settlements := AuthoredMap.settlements()
	var keys := settlements.keys()
	keys.sort()   # stable draw order, so overlaps stack the same way every run
	var ordered: Array = []   # valid settlements in stable key order
	for key in keys:
		var settlement_value: Variant = settlements[key]
		if typeof(settlement_value) == TYPE_DICTIONARY:
			ordered.append(settlement_value)

	# LAYER-MAJOR, not settlement-major. Every settlement's GROUND (plazas, then parks, then
	# worked land) is laid down before ANY settlement's standing things, so a plaza or park in
	# one settlement can never cover the decorative buildings of a neighbour it overlaps. This
	# map is exactly that case: two settlements share the same ground — one holds the building
	# masses, the other the greens laid over them — and a per-settlement loop (draw one whole,
	# then the next) painted the greens on top of the buildings. This mirrors the editor, which
	# mounts GROUND below STANDING as two separate nodes for the very same reason
	# (see map_editor_fabric.gd). The node itself still sits before BuildingVisuals in
	# main.tscn, so all of this stays under the gameplay buildings.

	# GROUND: paving lowest, then greens, then worked land — surfaces everything stands on.
	for settlement in ordered:
		for plaza in _list(settlement, "plazas"):
			AuthoredFabricPainter.draw_plaza(self, plaza)
	for settlement in ordered:
		for park in _list(settlement, "parks"):
			AuthoredFabricPainter.draw_park(self, park)
	for settlement in ordered:
		for area in _list(settlement, "farms"):
			AuthoredFabricPainter.draw_farm(self, area)
	# STANDING: decorative masses, then specials. Woodland is drawn last of all (a canopy
	# overhangs what it grows beside, so a tree under a mass would read as the mass in a hole).
	for settlement in ordered:
		for mass in _list(settlement, "decor"):
			if not _sacrificed.has(str(mass.get("id", ""))):
				AuthoredFabricPainter.draw_mass(self, mass)
	for settlement in ordered:
		for special in _list(settlement, "specials"):
			if not _sacrificed.has(str(special.get("id", ""))):
				AuthoredFabricPainter.draw_special(self, special)
	for settlement in ordered:
		for area in _list(settlement, "forests"):
			AuthoredFabricPainter.draw_forest(self, area)


func _list(settlement: Dictionary, key: String) -> Array:
	var out: Array = []
	for value in (settlement.get(key, []) as Array):
		if typeof(value) == TYPE_DICTIONARY:
			out.append(value)
	return out
