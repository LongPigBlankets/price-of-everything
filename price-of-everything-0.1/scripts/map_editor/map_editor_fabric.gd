extends Node2D
## The authored fabric being EDITED, drawn in the world rather than on the editor's overlay.
##
## EDITOR-ONLY (see the header of `map_editor.gd`).
##
## This exists because of a layering bug that no amount of reordering inside the overlay could
## fix. The overlay is a CanvasLayer at layer 64 — above the whole world — so anything drawn
## there sits over the game's buildings and roads whatever order it is drawn in. A park drawn
## in the editor therefore appeared on top of the buildings it should sit under, while the
## same park in the game drew correctly underneath.
##
## So the working document is painted by a Node2D inserted at `AuthoredFabricVisuals`' own
## place in the world, and it layers exactly as the shipped node does because it IS in the
## same stack. The overlay keeps the things that are genuinely scaffolding — the grid, the
## pen, handles, zones, the marquee — which belong above everything by design.
##
## The shipped node reads the SAVED document; this one reads the document being edited. That
## is the whole reason both exist.

const AuthoredFabricPainter := preload("res://scripts/authored_fabric_painter.gd")
const AuthoredSpecialShapesRef := preload("res://scripts/authored_special_shapes.gd")

## Selected shapes are hatched rather than tinted: a tint changes the colour you are judging
## the composition by. Matches the overlay's own treatment.
const HATCH_COLOR := Color(0.99, 0.97, 0.90, 0.75)
const HATCH_SPACING := 7.0
const HATCH_WIDTH := 1.6

var editor: Node = null


func _ready() -> void:
	set_process(true)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if editor == null:
		return
	var document: Dictionary = editor.call("document").call("data")
	var settlements_value: Variant = document.get("settlements", {})
	if typeof(settlements_value) != TYPE_DICTIONARY:
		return
	var settlements: Dictionary = settlements_value
	var selected: Dictionary = editor.call("selected_ids")
	var keys := settlements.keys()
	keys.sort()   # stable draw order, so overlaps stack the same way every run
	for key in keys:
		var settlement_value: Variant = settlements[key]
		if typeof(settlement_value) != TYPE_DICTIONARY:
			continue
		var settlement: Dictionary = settlement_value
		# GROUND LOWEST, and plazas lowest of all (owner, 2026-08-17): plaza, then park, then
		# worked land, then everything that stands on it. Identical to
		# `authored_fabric_visuals.gd` — an editor that stacks them differently is showing a
		# composition nobody will ever see.
		for plaza in _entries(settlement, "plazas"):
			AuthoredFabricPainter.draw_plaza(self, plaza)
			_mark(selected, plaza, [_outline_of(plaza)])
		for park in _entries(settlement, "parks"):
			AuthoredFabricPainter.draw_park(self, park)
			_mark(selected, park, [_outline_of(park)])
		for area in _entries(settlement, "farms"):
			AuthoredFabricPainter.draw_farm(self, area)
			_mark(selected, area, [_outline_of(area)])
		for mass in _entries(settlement, "decor"):
			AuthoredFabricPainter.draw_mass(self, mass)
			_mark(selected, mass, AuthoredFabricPainter.mass_polygons(mass))
		for special in _entries(settlement, "specials"):
			AuthoredFabricPainter.draw_special(self, special)
			_mark(selected, special, [AuthoredSpecialShapesRef.render_polygon(special)])
		for area in _entries(settlement, "forests"):
			AuthoredFabricPainter.draw_forest(self, area)

	# The stamp being dragged, previewed as the real thing.
	var shape: RefCounted = editor.call("shape_tool")
	if shape != null and bool(shape.call("is_stamping")):
		var preview: Dictionary = shape.call("stamp_preview", "__preview__")
		if not preview.is_empty():
			AuthoredFabricPainter.draw_mass(self, preview)


func _entries(settlement: Dictionary, key: String) -> Array:
	var out: Array = []
	for value in (settlement.get(key, []) as Array):
		if typeof(value) == TYPE_DICTIONARY:
			out.append(value)
	return out


func _mark(selected: Dictionary, record: Dictionary, polygons: Array) -> void:
	if selected.has(str(record.get("id", ""))):
		_hatch(polygons)


func _outline_of(record: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	for entry in (record.get("outline", []) as Array):
		var values: Array = entry as Array
		if values != null and values.size() >= 2:
			out.append(Vector2(float(values[0]), float(values[1])))
	return out


## Diagonal hatching clipped to a set of polygons, in world units — this node draws in world
## space, so no camera transform is needed and the density is stable by construction.
func _hatch(polygons: Array) -> void:
	for polygon_value in polygons:
		var polygon: PackedVector2Array = polygon_value
		if polygon.size() < 3:
			continue
		var bounds := Rect2(polygon[0], Vector2.ZERO)
		for point in polygon:
			bounds = bounds.expand(point)
		var reach := bounds.size.x + bounds.size.y
		var steps := int(reach / HATCH_SPACING) + 1
		for i in steps:
			var offset := bounds.position + Vector2(float(i) * HATCH_SPACING - bounds.size.y, 0.0)
			var line := PackedVector2Array([offset, offset + Vector2(bounds.size.y, bounds.size.y)])
			for piece in Geometry2D.intersect_polyline_with_polygon(line, polygon):
				if (piece as PackedVector2Array).size() >= 2:
					draw_polyline(piece, HATCH_COLOR, HATCH_WIDTH, true)
