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
const AuthoredSpecialShapes := preload("res://scripts/authored_special_shapes.gd")

var _sacrificed: Dictionary = {}
## Regions the fabric is CUT AROUND rather than deleted inside — the harbours, each grown by a
## clearance so the town stops a little short of the quay instead of touching it. Set by
## PortVisuals once its plans are built.
var _keep_out: Array = []


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


## Replace the keep-out regions (world polygons). Cheap and idempotent: a redraw only happens
## when the set actually changes, because PortVisuals recomputes its plans on every footprint
## change on a port tile and would otherwise repaint the whole fabric each time.
func set_keep_out(regions: Array) -> void:
	if regions.size() == _keep_out.size():
		var same := true
		for i in regions.size():
			if (regions[i] as PackedVector2Array) != (_keep_out[i] as PackedVector2Array):
				same = false
				break
		if same:
			return
	_keep_out = regions.duplicate()
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
				AuthoredFabricPainter.draw_mass(self, mass, _keep_out)
	for settlement in ordered:
		# Imported harbours draw as ONE grouped structure (draw_port_group): a dock and
		# its arms are one deck, so outlining each imported shape on its own would put
		# an ink seam across every junction. Everything else draws on its own.
		var harbours: Dictionary = {}
		for special in _list(settlement, "specials"):
			if _sacrificed.has(str(special.get("id", ""))):
				continue
			var port_tile := str(special.get("port", ""))
			if port_tile != "":
				if not harbours.has(port_tile):
					harbours[port_tile] = []
				(harbours[port_tile] as Array).append(special)
				continue
			AuthoredFabricPainter.draw_special(self, special, _keep_out)
		var harbour_keys := harbours.keys()
		harbour_keys.sort()
		for port_tile in harbour_keys:
			AuthoredFabricPainter.draw_port_group(self, harbours[port_tile],
				str(port_tile), _keep_out)
	for settlement in ordered:
		for area in _list(settlement, "forests"):
			AuthoredFabricPainter.draw_forest(self, area)


## READ-ONLY SEAM FOR AUDITS. Every decorative mass and special this layer is CURRENTLY
## drawing, as world polygons with their ids. Evicted masses are absent, so an audit asking
## "is anything still standing under this port" gets the same answer the screen shows —
## which is the whole point: comparing a plan against the document would keep reporting
## masses that were cleared, and comparing screenshots would mistake a stale frame for a pass.
func visible_mass_polygons() -> Array:
	var out: Array = []
	if not AuthoredMap.is_active():
		return out
	var settlements := AuthoredMap.settlements()
	var keys := settlements.keys()
	keys.sort()
	for key in keys:
		var settlement_value: Variant = settlements[key]
		if typeof(settlement_value) != TYPE_DICTIONARY:
			continue
		var settlement: Dictionary = settlement_value
		for record in _list(settlement, "decor"):
			if _sacrificed.has(str(record.get("id", ""))):
				continue
			for poly_value in AuthoredFabricPainter.mass_polygons(record):
				for piece in AuthoredFabricPainter.surviving_pieces(
						poly_value as PackedVector2Array, _keep_out):
					_append_visible(out, piece as PackedVector2Array, record)
		for record in _list(settlement, "specials"):
			if _sacrificed.has(str(record.get("id", ""))):
				continue
			for piece in AuthoredFabricPainter.surviving_pieces(
					AuthoredSpecialShapes.render_polygon(record), _keep_out):
				_append_visible(out, piece as PackedVector2Array, record)
	return out


func _append_visible(out: Array, poly: PackedVector2Array, record: Dictionary) -> void:
	if poly.size() < 3:
		return
	var bb := Rect2(poly[0], Vector2.ZERO)
	for point in poly:
		bb = bb.expand(point)
	out.append({"id": str(record.get("id", "")), "poly": poly, "bb": bb})


func _list(settlement: Dictionary, key: String) -> Array:
	var out: Array = []
	for value in (settlement.get(key, []) as Array):
		if typeof(value) == TYPE_DICTIONARY:
			out.append(value)
	return out
