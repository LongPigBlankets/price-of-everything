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
const AuthoredRoadPainter := preload("res://scripts/authored_road_painter.gd")
const AuthoredBake := preload("res://scripts/authored_bake.gd")
const BakeLayout := preload("res://scripts/authored_bake_layout.gd")

## Keep baked textures resident a little past the camera (world units), so a tile loads before
## it scrolls in. Matches authored_fabric_visuals.
const STREAM_MARGIN := 600.0

## Last view rect the baked path drew for; a change means recull and redraw.
var _view_rect := Rect2()

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
	# One painter for the live render and the texture bake (see authored_road_painter.gd),
	# which also owns the global casings-then-beds pass order.
	if AuthoredBake.is_available():
		# The 287 permanent strokes come from the textures; the ~37 UNLOCKABLE ones are drawn
		# live over them, because whether they are visible depends on flags that move during
		# the match. Keeping them vector is what preserves the whole-stroke reveal with no
		# overlay artifacts to bake, and at this count it costs nothing.
		AuthoredBake.draw_layer(self, "roads", AuthoredBake.visible_world_rect(self, STREAM_MARGIN))
		AuthoredRoadPainter.draw_strokes(self, _unlockable_strokes(flagged), _geometry_cache)
		return
	AuthoredRoadPainter.draw_strokes(self, _visible_strokes(flagged), _geometry_cache)


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


## The visible strokes the bake could not contain: unlockable ones that have since been
## revealed. Their permanent siblings are already in the texture, so drawing these over it
## reproduces the full picture exactly.
func _unlockable_strokes(flagged: Dictionary) -> Array:
	var out: Array = []
	for stroke in _visible_strokes(flagged):
		if not BakeLayout.road_is_static(stroke as Dictionary):
			out.append(stroke)
	return out


## Baked mode streams by camera, so the layer has to notice the camera moving.
func _process(_delta: float) -> void:
	if not visible or not AuthoredBake.is_available():
		return
	var view := AuthoredBake.visible_world_rect(self, STREAM_MARGIN)
	if view != _view_rect:
		_view_rect = view
		queue_redraw()


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
