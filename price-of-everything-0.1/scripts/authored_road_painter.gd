extends RefCounted
## Draws authored road strokes onto any canvas. Extracted from `authored_road_visuals.gd` so
## the LIVE renderer and the TEXTURE BAKE paint through one body of code: a baked tile that
## disagreed with the vector fallback by even a hairline would be invisible in review and
## permanent on disk, and the only way to rule that out by construction is to have one painter.
## `authored_fabric_painter.gd` already serves the fabric layer the same way.
##
## PASS ORDER IS GLOBAL, NOT PER STROKE. Every casing is laid down before any bed, because
## per-stroke casing-then-bed lets a later stroke's dark edge cut across an earlier stroke's
## carriageway at every junction. Callers must therefore hand over the WHOLE set of strokes
## that touch the canvas in one call — for the bake that means every stroke reaching the tile
## rect, including ones whose bulk lies outside it.

const AuthoredRoadStyle := preload("res://scripts/authored_road_style.gd")
const AuthoredRoadGeometry := preload("res://scripts/authored_road_geometry.gd")

## Bridge glyph proportions, matching `road_network_visuals._draw_bridge_glyph` so an authored
## crossing reads like every other crossing on the map.
const BRIDGE_DECK_SCALE := 1.15
const BRIDGE_RAIL_WIDTH := 1.4


## Paint `strokes` (already filtered to what should be visible) onto `canvas`.
## `geometry_cache` is an optional stroke id -> polyline dictionary the caller owns; sampling
## and wobbling a stroke cannot change unless the document does, so the live renderer keeps
## one across redraws. Pass a fresh dictionary (or omit it) for a one-shot bake.
static func draw_strokes(canvas: CanvasItem, strokes: Array, geometry_cache: Dictionary = {}) -> void:
	for stroke_class in AuthoredRoadStyle.class_order():
		for stroke in strokes:
			if str((stroke as Dictionary).get("class", "mid")) != stroke_class:
				continue
			var points := polyline_for(stroke as Dictionary, geometry_cache)
			if points.size() >= 2:
				canvas.draw_polyline(points, AuthoredRoadStyle.casing_color(stroke_class),
					AuthoredRoadStyle.casing_width(stroke_class), true)
	for stroke_class in AuthoredRoadStyle.class_order():
		for stroke in strokes:
			if str((stroke as Dictionary).get("class", "mid")) != stroke_class:
				continue
			var points := polyline_for(stroke as Dictionary, geometry_cache)
			if points.size() >= 2:
				canvas.draw_polyline(points, AuthoredRoadStyle.bed_color(stroke_class),
					AuthoredRoadStyle.bed_width(stroke_class), true)
	for stroke in strokes:
		draw_bridges(canvas, stroke as Dictionary)


## The styled polyline for a stroke, memoised in `geometry_cache` when one is supplied.
static func polyline_for(stroke: Dictionary, geometry_cache: Dictionary = {}) -> PackedVector2Array:
	var id := str(stroke.get("id", ""))
	if id != "" and geometry_cache.has(id):
		return geometry_cache[id]
	var points := AuthoredRoadGeometry.polyline(stroke)
	if id != "":
		geometry_cache[id] = points
	return points


## Bridge decks at the stroke's authored crossings. A deck is drawn across the road, its
## length set by the class, so a major road's bridge reads as the heavier structure.
static func draw_bridges(canvas: CanvasItem, stroke: Dictionary) -> void:
	var crossings: Array = stroke.get("bridges", []) as Array
	if crossings.is_empty():
		return
	var stroke_class := str(stroke.get("class", "mid"))
	var half := AuthoredRoadStyle.casing_width(stroke_class) * BRIDGE_DECK_SCALE * 0.5
	for crossing_value in crossings:
		if typeof(crossing_value) != TYPE_ARRAY:
			continue
		var crossing: Array = crossing_value
		if crossing.size() < 4:
			continue
		var centre := Vector2(float(crossing[0]), float(crossing[1]))
		var tangent := Vector2(float(crossing[2]), float(crossing[3]))
		if tangent.length() < 0.001:
			continue
		tangent = tangent.normalized()
		var across := Vector2(-tangent.y, tangent.x) * half
		canvas.draw_line(centre - across, centre + across, MapStyle.road_bridge(),
			BRIDGE_RAIL_WIDTH * 2.0, true)
