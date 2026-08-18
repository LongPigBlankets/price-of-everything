extends Node2D
## Draws the hand-authored roads (`data/map_authored.json`) and enforces the unlock rule.
##
## Sits beside `RoadNetworkVisuals` in `scenes/main.tscn`; the world map has no `z_index`
## anywhere, so SIBLING ORDER IS THE LAYERING. On authored tiles the baked network stands
## down (`RoadNetworkVisuals` skips their runs), so the two never draw the same ground.
##
## THE UNLOCK RULE (owner, 2026-08-16). A stroke marked `unlockable` draws only when EVERY
## tile it touches carries the road flag:
##   * a street inside one roadless tile appears when that tile gains roads;
##   * a connector between two tiles appears when the second one gains roads — that is, at
##     the moment the new tile's network can actually join the neighbour's.
## It appears WHOLE. The baked network clips its geometry point by point and leaves a stub
## hanging at the seam; an authored connector is one designed object, so it is all-or-nothing.
##
## Redraws are event-driven, never per frame: the flag signal, a settled road order, and a
## style change. Vector rendering here is P1; P4 swaps in the per-tile baked textures and
## keeps this as the debug fallback.

const AuthoredMap := preload("res://scripts/authored_map.gd")
const AuthoredRoadStyle := preload("res://scripts/authored_road_style.gd")
const AuthoredRoadGeometry := preload("res://scripts/authored_road_geometry.gd")

## Bridge glyph proportions, matching `road_network_visuals._draw_bridge_glyph` so an
## authored crossing reads like every other crossing on the map.
const BRIDGE_DECK_SCALE := 1.15
const BRIDGE_RAIL_WIDTH := 1.4

## stroke id -> drawn polyline. Sampling and wobbling every stroke on each redraw would
## repeat work that cannot change unless the document does; the procedural layer needed the
## same cache when footprint polls started redrawing it repeatedly.
var _geometry_cache: Dictionary = {}
var _terrain: Node = null


func _ready() -> void:
	# Authored content is opt-in. With no document this node costs one boolean per redraw.
	MapStyle.style_changed.connect(_on_style_changed)
	if not RoadWorks.order_settled.is_connected(_on_order_settled):
		RoadWorks.order_settled.connect(_on_order_settled)
	var world := get_parent()
	if world != null and world.has_signal("tile_infrastructure_changed"):
		world.tile_infrastructure_changed.connect(_on_tile_infrastructure_changed)


func _on_style_changed() -> void:
	# Style changes alter widths and wobble, so the styled geometry is stale.
	_geometry_cache.clear()
	queue_redraw()


func _on_order_settled(_id: int) -> void:
	queue_redraw()


## A tile gaining (or losing) roads changes which unlockable strokes qualify. The baked
## network notices a flag flip only by side effect — its edge count is unchanged — which is
## why `world_map.tutorial_install_infrastructure` has to poke the renderer by hand. The
## signal makes it explicit for authored roads.
## Both parameters are required even though neither is read: a handler with fewer arguments
## than the signal carries still CONNECTS, and only fails when the signal fires — silently
## as far as the feature is concerned, since the error goes to the log and the picture
## simply never updates.
func _on_tile_infrastructure_changed(_tile_id: String, _infra_type: String) -> void:
	queue_redraw()


func _draw() -> void:
	if not AuthoredMap.is_active():
		return
	if not RoadNetwork.roads_visible:
		return
	var flagged := _flagged_tile_ids()
	# Two passes over the whole map, casings then beds: per-stroke casing-then-bed would
	# let a later stroke's dark edge cut across an earlier stroke's carriageway at every
	# junction. The river layer needs the same discipline for its bank casings.
	var visible_strokes := _visible_strokes(flagged)
	for stroke_class in AuthoredRoadStyle.class_order():
		for stroke in visible_strokes:
			if str(stroke.get("class", "mid")) != stroke_class:
				continue
			var points: PackedVector2Array = _geometry_for(stroke)
			if points.size() >= 2:
				draw_polyline(points, AuthoredRoadStyle.casing_color(stroke_class),
					AuthoredRoadStyle.casing_width(stroke_class), true)
	for stroke_class in AuthoredRoadStyle.class_order():
		for stroke in visible_strokes:
			if str(stroke.get("class", "mid")) != stroke_class:
				continue
			var points: PackedVector2Array = _geometry_for(stroke)
			if points.size() >= 2:
				draw_polyline(points, AuthoredRoadStyle.bed_color(stroke_class),
					AuthoredRoadStyle.bed_width(stroke_class), true)
	for stroke in visible_strokes:
		_draw_bridges(stroke)


## Ids of the strokes currently drawing. A read-only seam for the verification harness and
## for tests: "is the unlock rule working" is a question about this list, and answering it
## by comparing screenshots is how a stale frame gets mistaken for a passing gate.
func visible_stroke_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for stroke in _visible_strokes(_flagged_tile_ids()):
		out.append(str((stroke as Dictionary).get("id", "")))
	return out


## Every stroke whose tiles are all flagged, across every settlement.
func _visible_strokes(flagged: Dictionary) -> Array:
	var out: Array = []
	var settlements := AuthoredMap.settlements()
	var keys := settlements.keys()
	keys.sort()   # stable draw order, so overlapping strokes stack the same way every run
	for key in keys:
		var settlement_value: Variant = settlements[key]
		if typeof(settlement_value) != TYPE_DICTIONARY:
			continue
		for stroke_value in ((settlement_value as Dictionary).get("roads", []) as Array):
			if typeof(stroke_value) != TYPE_DICTIONARY:
				continue
			var stroke: Dictionary = stroke_value
			if AuthoredMap.road_visible(stroke, flagged):
				out.append(stroke)
	return out


func _geometry_for(stroke: Dictionary) -> PackedVector2Array:
	var id := str(stroke.get("id", ""))
	if _geometry_cache.has(id):
		return _geometry_cache[id]
	var points := AuthoredRoadGeometry.polyline(stroke)
	_geometry_cache[id] = points
	return points


## Bridge decks at the stroke's authored crossings. A deck is drawn across the road, its
## length set by the class, so a major road's bridge reads as the heavier structure.
func _draw_bridges(stroke: Dictionary) -> void:
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
		draw_line(centre - across, centre + across, MapStyle.road_bridge(),
			BRIDGE_RAIL_WIDTH * 2.0, true)


## `{tile_id: true}` for every tile carrying roads. The procedural renderer keys the same
## set by COORD; authored documents name tiles by id (ids are the stable handle, and the
## codebase forbids deriving identity by arithmetic on them), so this builds the id form.
func _flagged_tile_ids() -> Dictionary:
	var out: Dictionary = {}
	var terrain := _terrain_layer()
	if terrain == null:
		return out
	var tiles: Dictionary = terrain.get("tiles")
	for coord in tiles:
		var tile: Dictionary = tiles[coord]
		if (tile.get("infrastructure_present", []) as Array).has("roads"):
			out[str(tile.get("id", ""))] = true
	return out


func _terrain_layer() -> Node:
	if _terrain != null and is_instance_valid(_terrain):
		return _terrain
	_terrain = get_tree().get_first_node_in_group("hex_map")
	return _terrain
