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
const MidcenturyStyle := preload("res://scripts/map_midcentury_style.gd")
## The shipped layer's own view helpers, reused rather than re-derived: the editor culls to
## the same rect, with the same "has the view actually moved" test.
const AuthoredBake := preload("res://scripts/authored_bake.gd")
const ViewStream := preload("res://scripts/view_stream.gd")

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
## At a whole-map zoom, a building is a few pixels and its shadow + ink outline are no longer
## legible. Retain one true polygon fill per building instead of three canvas commands.
const FABRIC_DETAIL_ZOOM := 0.18
## Retained CanvasItem commands are replayed every frame. At the normal 0.9 editing zoom,
## full-density authored woods alone cost ~70 ms/frame; a canopy wash plus a deterministic
## sample of their crowns reads as the same wood and brings the command list under the
## 30-fps budget. Zooming in progressively restores every tree for close inspection.
const FOREST_HALF_ZOOM := 1.15
const FOREST_FULL_ZOOM := 1.60
const FOREST_FAR_ZOOM := 0.75

var editor: Node = null
var half: int = Half.STANDING
## The view the current drawing was culled against, and the stamp it was drawn at.
var _view_rect := Rect2()
var _drawn_revision := -1
var _drawn_preview_revision := -1


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
	var revision := int(editor.call("document_revision"))
	# The stamp preview is fabric, but selection/tool chrome is not. Watch the broad preview
	# stamp only while a real building stamp is visible; otherwise clicks leave this retained
	# command list alone and the overlay changes selection cheaply above it.
	var shape: RefCounted = editor.call("shape_tool")
	var stamping := shape != null and bool(shape.call("is_stamping"))
	var preview_revision := int(editor.call("preview_revision")) if stamping else -1
	var view := AuthoredBake.visible_world_rect(self, VIEW_MARGIN)
	if revision == _drawn_revision and preview_revision == _drawn_preview_revision \
			and ViewStream.settled(view, _view_rect, VIEW_MARGIN):
		return
	_drawn_revision = revision
	_drawn_preview_revision = preview_revision
	_view_rect = view
	queue_redraw()


func _draw() -> void:
	if editor == null:
		return
	# Building-layout mode keeps the geometry people need to place and select, but replaces
	# foliage with cheap silhouettes. This is a VIEW choice only: the working document still
	# contains every forest and compact tree point, and P restores the exact painter whenever
	# the designer wants to judge the finished planting.
	var fast_preview := bool(editor.call("fast_preview"))
	var document: Dictionary = editor.call("document").call("data")
	var settlements_value: Variant = document.get("settlements", {})
	if typeof(settlements_value) != TYPE_DICTIONARY:
		return
	var settlements: Dictionary = settlements_value
	# Woods are drawn as their canopy outline rather than as trees once a tree is about a
	# pixel across. Below this the individual trees are not visible ANYWAY, and drawing them
	# is what made a zoomed-out editor unusable: the whole map holds well over a hundred
	# thousand of them. Above it nothing changes — every zoom anyone edits at draws the real
	# thing, which is the point of previewing with the game's own painter.
	var camera: Camera2D = editor.call("camera")
	var trees_readable := camera == null or camera.zoom.x >= TREE_ZOOM
	var details_readable := not fast_preview \
		and (camera == null or camera.zoom.x >= FABRIC_DETAIL_ZOOM)
	var forest_stride := 1
	if camera != null:
		if camera.zoom.x < FOREST_FAR_ZOOM:
			forest_stride = 8
		elif camera.zoom.x < FOREST_HALF_ZOOM:
			forest_stride = 6
		elif camera.zoom.x < FOREST_FULL_ZOOM:
			forest_stride = 2
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
			for park in _entries(settlement, "parks"):
				if not _visible_now(_outline_of(park)):
					continue
				AuthoredFabricPainter.draw_park(self, park)
			for area in _entries(settlement, "farms"):
				if not _visible_now(_outline_of(area)):
					continue
				AuthoredFabricPainter.draw_farm(self, area)
			continue
		for mass in _entries(settlement, "decor"):
			var mass_polys: Array = AuthoredFabricPainter.mass_polygons(mass)
			if not _any_visible(mass_polys):
				continue
			if details_readable:
				AuthoredFabricPainter.draw_mass(self, mass)
				_mark_hijack(mass, mass_polys)
			else:
				var colour := MidcenturyStyle.urban_block(str(mass.get("id", "")), 0.6)
				for polygon in mass_polys:
					draw_colored_polygon(polygon as PackedVector2Array, colour)
				_mark_hijack(mass, mass_polys)
		for special in _entries(settlement, "specials"):
			var special_polys: Array = [AuthoredSpecialShapesRef.render_polygon(special)]
			if not _any_visible(special_polys):
				continue
			if details_readable:
				AuthoredFabricPainter.draw_special(self, special)
				_mark_hijack(special, special_polys)
			else:
				var colour := MidcenturyStyle.urban_block(str(special.get("id", "")), 0.6)
				draw_colored_polygon(special_polys[0] as PackedVector2Array, colour)
				_mark_hijack(special, special_polys)
		for area in _entries(settlement, "forests"):
			var canopy := _outline_of(area)
			if not _visible_now(canopy):
				continue
			if fast_preview:
				if canopy.size() >= 3:
					draw_colored_polygon(canopy, MapStyle.tree_fill(false))
			elif trees_readable:
				if forest_stride > 1 and canopy.size() >= 3:
					draw_colored_polygon(canopy, MapStyle.tree_fill(false))
				AuthoredFabricPainter.draw_forest(self, area, _view_rect, forest_stride)
			elif canopy.size() >= 3:
				draw_colored_polygon(canopy, MapStyle.tree_fill(false))
		# Planted trees, through the same painter the game uses. At map zoom they are sub-pixel,
		# so emitting hundreds of invisible crowns only bloats the retained canvas command list;
		# at editing zoom the painter rejects points outside the camera's buffered view.
		if trees_readable and not fast_preview:
			AuthoredFabricPainter.draw_settlement_trees(self, settlement, str(key), _view_rect)

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
