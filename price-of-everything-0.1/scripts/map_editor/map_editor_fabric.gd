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
## The shipped layer's own view helpers, reused rather than re-derived: the editor culls to
## the same rect, with the same "has the view actually moved" test.
const AuthoredBake := preload("res://scripts/authored_bake.gd")
const ViewStream := preload("res://scripts/view_stream.gd")

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

## World units of slack around the view. Content within the margin is drawn before it is on
## screen, so a pan reveals finished map rather than shapes popping in — and the layer only
## has to re-cull once the camera has moved a fraction of it.
##
## KEPT TIGHT, because the margin is not free after the drawing is built: Godot replays a
## canvas item's commands every frame whether or not `_draw` ran again, and a wood is
## thousands of them. At 900 the layer held about four times the visible area and cost 87 ms
## a frame to replay; a third of a screen costs a fifth of that and still hides the pop-in.
const VIEW_MARGIN := 300.0

## Below this zoom (px per world unit) a wood draws as its canopy outline instead of as
## individual trees. A small tree is 2.6 u across, so at 0.3 it is under a pixel.
const TREE_ZOOM := 0.3

var editor: Node = null
var half: int = Half.STANDING
## The view the current drawing was culled against, and the stamp it was drawn at.
var _view_rect := Rect2()
var _drawn_revision := -1


func _ready() -> void:
	set_process(true)


## REDRAW ON CHANGE, NOT ON EVERY FRAME. See `map_editor._repaint` for the measurement that
## forced this: a per-frame repaint of a map-sized document ran at nine seconds a frame.
##
## Two things can change what this layer should show. The document (every mutation, selection
## and tool change bumps the editor's stamp), and the VIEW — not because the drawing moves
## with the camera (this is a world-space layer, so panning needs no repaint at all) but
## because [method _visible_now] culls to the view, and content sliding in from off screen has
## to be drawn when it arrives. The margin is what makes that cheap: the cull keeps a screen's
## worth of slack around the view, so the rect only has to be re-tested once the camera has
## travelled a fair fraction of it.
func _process(_delta: float) -> void:
	if editor == null:
		return
	var revision := int(editor.call("preview_revision"))
	var view := AuthoredBake.visible_world_rect(self, VIEW_MARGIN)
	if revision == _drawn_revision and ViewStream.settled(view, _view_rect, VIEW_MARGIN):
		return
	_drawn_revision = revision
	_view_rect = view
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
	# Woods are drawn as their canopy outline rather than as trees once a tree is about a
	# pixel across. Below this the individual trees are not visible ANYWAY, and drawing them
	# is what made a zoomed-out editor unusable: the whole map holds well over a hundred
	# thousand of them. Above it nothing changes — every zoom anyone edits at draws the real
	# thing, which is the point of previewing with the game's own painter.
	var camera: Camera2D = editor.call("camera")
	var trees_readable := camera == null or camera.zoom.x >= TREE_ZOOM
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
				if not _visible_now(_outline_of(plaza)):
					continue
				AuthoredFabricPainter.draw_plaza(self, plaza)
				_mark(selected, plaza, [_outline_of(plaza)])
			for park in _entries(settlement, "parks"):
				if not _visible_now(_outline_of(park)):
					continue
				AuthoredFabricPainter.draw_park(self, park)
				_mark(selected, park, [_outline_of(park)])
			for area in _entries(settlement, "farms"):
				if not _visible_now(_outline_of(area)):
					continue
				AuthoredFabricPainter.draw_farm(self, area)
				_mark(selected, area, [_outline_of(area)])
			continue
		for mass in _entries(settlement, "decor"):
			var mass_polys: Array = AuthoredFabricPainter.mass_polygons(mass)
			if not _any_visible(mass_polys):
				continue
			AuthoredFabricPainter.draw_mass(self, mass)
			_mark_hijack(mass, mass_polys)
			_mark(selected, mass, mass_polys)
		for special in _entries(settlement, "specials"):
			var special_polys: Array = [AuthoredSpecialShapesRef.render_polygon(special)]
			if not _any_visible(special_polys):
				continue
			AuthoredFabricPainter.draw_special(self, special)
			_mark_hijack(special, special_polys)
			_mark(selected, special, special_polys)
		for area in _entries(settlement, "forests"):
			var canopy := _outline_of(area)
			if not _visible_now(canopy):
				continue
			if trees_readable:
				AuthoredFabricPainter.draw_forest(self, area)
			elif canopy.size() >= 3:
				draw_colored_polygon(canopy, MapStyle.tree_fill(false))
		# Planted trees, through the same painter the game uses — an editor that draws its own
		# version of a record is an editor you cannot trust about what you are making.
		AuthoredFabricPainter.draw_trees(self, _entries(settlement, "trees"))

	if half == Half.GROUND:
		return
	# The stamp being dragged, previewed as the real thing.
	var shape: RefCounted = editor.call("shape_tool")
	if shape != null and bool(shape.call("is_stamping")):
		var preview: Dictionary = shape.call("stamp_preview", "__preview__")
		if not preview.is_empty():
			AuthoredFabricPainter.draw_mass(self, preview)


## Is any of this polygon inside the view the current drawing was culled against? The test is
## a bounding box, deliberately: it is a handful of comparisons against a shape whose drawing
## costs hundreds of draw calls, and a false positive only costs a shape drawn just off screen.
func _visible_now(points: PackedVector2Array) -> bool:
	if points.is_empty():
		return false
	if _view_rect.size.x <= 0.0 or _view_rect.size.y <= 0.0:
		return true   # no view measured yet — draw everything rather than nothing
	var low := points[0]
	var high := points[0]
	for point in points:
		low = Vector2(minf(low.x, point.x), minf(low.y, point.y))
		high = Vector2(maxf(high.x, point.x), maxf(high.y, point.y))
	return _view_rect.intersects(Rect2(low, high - low))


func _any_visible(polygons: Array) -> bool:
	for polygon in polygons:
		if _visible_now(polygon as PackedVector2Array):
			return true
	return false


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
