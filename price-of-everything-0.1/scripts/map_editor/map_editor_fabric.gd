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

## Buildings marked as hijack slots (J): a BLUE ring + bbox cross (owner, 2026-08-27).
## An outline rather than a tint for the same reason the selection hatches — the fill
## colour is what the designer is judging the composition by. The cross says "hidden in
## play" at a glance. Blue is free here now that the industrial zone wash no longer
## draws; it is the same blue that wash used, so the editor's "a building goes here"
## colour is unchanged — it has just moved onto the thing that actually says so.
const HIJACK_COLOR := Color(0.30, 0.60, 1.00, 0.95)
const HIJACK_WIDTH := 1.8

## Which half of the fabric this node paints. GROUND (plazas, parks, worked land) is mounted
## BELOW the procedural fabric so it sits under the decorative buildings the generator draws;
## STANDING (masses, specials, woodland) is mounted above, with the shipped authored node.
##
## The split exists because the editor shows procedural fabric while you draw authored content
## over it. In the GAME the two never meet — authored tiles suppress the procedural fabric
## entirely — so this is the editor telling the truth about a situation only the editor has.
enum Half { GROUND, STANDING }

var editor: Node = null
var half: int = Half.STANDING


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
		# worked land, then everything that stands on it.
		if half == Half.GROUND:
			for plaza in _entries(settlement, "plazas"):
				AuthoredFabricPainter.draw_plaza(self, plaza)
				_mark(selected, plaza, [_outline_of(plaza)])
			for park in _entries(settlement, "parks"):
				AuthoredFabricPainter.draw_park(self, park)
				_mark(selected, park, [_outline_of(park)])
			for area in _entries(settlement, "farms"):
				AuthoredFabricPainter.draw_farm(self, area)
				_mark(selected, area, [_outline_of(area)])
			continue
		for mass in _entries(settlement, "decor"):
			AuthoredFabricPainter.draw_mass(self, mass)
			var mass_polys: Array = AuthoredFabricPainter.mass_polygons(mass)
			_mark_hijack(mass, mass_polys)
			_mark(selected, mass, mass_polys)
		for special in _entries(settlement, "specials"):
			AuthoredFabricPainter.draw_special(self, special)
			var special_polys: Array = [AuthoredSpecialShapesRef.render_polygon(special)]
			_mark_hijack(special, special_polys)
			_mark(selected, special, special_polys)
		for area in _entries(settlement, "forests"):
			AuthoredFabricPainter.draw_forest(self, area)

	if half == Half.GROUND:
		return
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
		_hatch(polygons, bool(editor.call("is_shape_mode")))


func _mark_hijack(record: Dictionary, polygons: Array) -> void:
	if not bool(record.get("hijack", false)):
		return
	for polygon_value in polygons:
		var polygon: PackedVector2Array = polygon_value
		if polygon.size() < 3:
			continue
		var ring := polygon.duplicate()
		ring.append(polygon[0])
		draw_polyline(ring, HIJACK_COLOR, HIJACK_WIDTH, true)
		var bounds := Rect2(polygon[0], Vector2.ZERO)
		for point in polygon:
			bounds = bounds.expand(point)
		draw_line(bounds.position, bounds.end, HIJACK_COLOR, 1.2, true)
		draw_line(Vector2(bounds.end.x, bounds.position.y),
			Vector2(bounds.position.x, bounds.end.y), HIJACK_COLOR, 1.2, true)


func _outline_of(record: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	for entry in (record.get("outline", []) as Array):
		var values: Array = entry as Array
		if values != null and values.size() >= 2:
			out.append(Vector2(float(values[0]), float(values[1])))
	return out


## Diagonal hatching clipped to a set of polygons, in world units — this node draws in world
## space, so no camera transform is needed and the density is stable by construction.
func _hatch(polygons: Array, horizontal: bool = false) -> void:
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
			# Side-to-side while reshaping, 45 degrees otherwise — the hatch is what says
			# which mode you are in.
			var offset: Vector2
			var line: PackedVector2Array
			if horizontal:
				offset = bounds.position + Vector2(0.0, float(i) * HATCH_SPACING)
				line = PackedVector2Array([offset, offset + Vector2(bounds.size.x, 0.0)])
			else:
				offset = bounds.position + Vector2(float(i) * HATCH_SPACING - bounds.size.y, 0.0)
				line = PackedVector2Array([offset, offset + Vector2(bounds.size.y, bounds.size.y)])
			for piece in Geometry2D.intersect_polyline_with_polygon(line, polygon):
				if (piece as PackedVector2Array).size() >= 2:
					draw_polyline(piece, HATCH_COLOR, HATCH_WIDTH, true)
