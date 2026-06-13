extends Node2D

# Draws every (non-forest, non-road) building as a coloured polygon footprint —
# Phase 1 of the polygon-buildings plan: one square per building at its tile
# slot, filled with the size-chart CATEGORY colour, NPC-owned ones outlined in
# thick white. The slot layout + viewport cull are the old icon-grid machinery;
# later phases swap the slot positions for a road-frontage layout engine. Held
# as plain placement data, drawn in one _draw() pass (no child nodes).

const TileViewData := preload("res://scripts/tile_view_data.gd")

# Per-tile occupancy: tile_id -> count, to assign the next grid slot.
var tile_building_counts: Dictionary = {}

# Ordered placements + an index for O(1) removal. Each placement:
#   {instance_id, slot, pos, texture, is_npc}
var _placements: Array = []
var _placement_index: Dictionary = {}   # instance_id -> index into _placements

const ICONS_PER_ROW := 4
const ICON_ROWS := 3
const ROADS_BUILDING_ID := "b_005"
const FOREST_BUILDING_IDS := {"b_015": true, "b_016": true}
const MAX_VISIBLE_BUILDINGS := 12  # 4 cols × 3 rows
const OVERFLOW_INDEX := 11         # 12th slot (0-indexed)
const SQUARE_FILL := 0.42          # square half as a fraction of the slot (leaves a gap)
const NPC_OUTLINE_W := 7.0         # thick white outline for NPC-owned buildings
const CASING := Color(0.12, 0.10, 0.06, 0.85)
const CASING_W := 2.0
## Viewport culling: when no more than this many icons are on screen (zoomed in)
## draw only the visible ones and redraw as the camera moves; above it (zoomed
## out) draw everything once and stay static. Drawing all ~560 buildings every
## frame at max zoom was a hard bottleneck.
const CULL_CAP := 160
const CULL_MARGIN := 600.0   # world units — pop icons in just off-screen

@onready var terrain_layer: HexMap = %TerrainLayer

var _cull := false           # currently in culled (zoomed-in) mode
var _view := Rect2()

func on_building_placed(tile_id: String, building_id: String, _recipe_id: String, instance_id: String, coord: Vector2i) -> void:
	# Roads aren't buildings; forests are drawn by ForestVisuals.
	if building_id == ROADS_BUILDING_ID or FOREST_BUILDING_IDS.has(building_id):
		return

	if not tile_building_counts.has(tile_id):
		tile_building_counts[tile_id] = 0
	var slot_index: int = tile_building_counts[tile_id]
	tile_building_counts[tile_id] = slot_index + 1
	if slot_index > OVERFLOW_INDEX:
		return  # past the overflow indicator — nothing more to draw on this tile

	var tile_center := _tile_center_world_pos(coord)
	var is_npc := not MatchState.is_player_owned(MatchState.get_building(instance_id))
	var color: Color = TileViewData.category_color(Catalog.get_building(building_id))

	var pos := _slot_position(tile_center, slot_index)
	var sq_half := _icon_slot_size() * SQUARE_FILL
	var bb_half := sq_half + Vector2(NPC_OUTLINE_W, NPC_OUTLINE_W)
	var placement := {
		"instance_id": instance_id,
		"slot": slot_index,
		"pos": pos,
		"half": sq_half,
		"color": color,
		"is_npc": is_npc,
		"bb": Rect2(pos - bb_half, bb_half * 2.0),
	}
	if instance_id != "":
		_placement_index[instance_id] = _placements.size()
	_placements.append(placement)
	queue_redraw()

## Cull to the viewport when zoomed in (few icons on screen), else draw all and
## stay static — so panning while zoomed out doesn't redraw ~560 icons a frame.
func _process(_delta: float) -> void:
	if _placements.is_empty():
		return
	var view := _visible_world_rect()
	if view.size.x <= 0.0:
		return
	var visible := 0
	for p in _placements:
		if view.intersects(p.bb):
			visible += 1
	var want_cull := visible <= CULL_CAP
	if want_cull != _cull:
		_cull = want_cull
		_view = view
		queue_redraw()
	elif _cull and view != _view:
		_view = view   # camera moved while zoomed in — recull next draw
		queue_redraw()

func _visible_world_rect() -> Rect2:
	var vp := get_viewport()
	if vp == null:
		return Rect2()
	var size := vp.get_visible_rect().size
	if size.x <= 0.0:
		return Rect2()
	return (vp.get_canvas_transform().affine_inverse() * Rect2(Vector2.ZERO, size)).grow(CULL_MARGIN)

func clear_all() -> void:
	# Used when a loaded save rebuilds the map visuals (world_map._rebuild_after_load).
	_placements.clear()
	_placement_index.clear()
	tile_building_counts.clear()
	queue_redraw()

func remove_instance(instance_id: String) -> void:
	# A cancelled construction frees its icon; the slot is left vacant (no reindex).
	if not _placement_index.has(instance_id):
		return
	var idx: int = _placement_index[instance_id]
	_placements.remove_at(idx)
	_placement_index.erase(instance_id)
	# Indices after the removed one shifted down by one.
	for iid in _placement_index:
		if _placement_index[iid] > idx:
			_placement_index[iid] -= 1
	queue_redraw()

func _draw() -> void:
	for placement in _placements:
		if _cull and not _view.intersects(placement.bb):
			continue
		if int(placement.slot) == OVERFLOW_INDEX:
			_draw_overflow(placement.pos)
			continue
		_draw_square(placement.pos, placement.half, placement.color, bool(placement.is_npc))

func _draw_square(center: Vector2, half: Vector2, color: Color, is_npc: bool) -> void:
	var verts := PackedVector2Array([
		center + Vector2(-half.x, -half.y), center + Vector2(half.x, -half.y),
		center + Vector2(half.x, half.y), center + Vector2(-half.x, half.y),
	])
	draw_colored_polygon(verts, color)
	var loop := verts.duplicate()
	loop.append(verts[0])
	# NPC: thick white outline; player: thin dark casing.
	if is_npc:
		draw_polyline(loop, Color.WHITE, NPC_OUTLINE_W, true)
	else:
		draw_polyline(loop, CASING, CASING_W, true)

func _draw_overflow(slot_pos: Vector2) -> void:
	var font := ThemeDB.fallback_font
	var size := roundi(_tile_size().y * 0.08)
	draw_string(font, slot_pos - Vector2(size * 0.25, -size * 0.35), "…",
		HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0.9, 0.9, 0.9))

func _tile_center_world_pos(coord: Vector2i) -> Vector2:
	if terrain_layer != null:
		return terrain_layer.map_to_local(terrain_layer.map_coord_for_tile_coord(coord))
	return Vector2.ZERO

func _slot_position(tile_center: Vector2, slot_index: int) -> Vector2:
	# Lay out icons left-to-right, top-to-bottom in the icon area, centered on the tile.
	var col := slot_index % ICONS_PER_ROW
	var row := slot_index / ICONS_PER_ROW
	var icon_area := _icon_area_size()
	var icon_size := _icon_slot_size()
	var area_top_left := tile_center - (icon_area * 0.5)
	var slot_x := area_top_left.x + col * icon_size.x + icon_size.x / 2
	var slot_y := area_top_left.y + row * icon_size.y + icon_size.y / 2
	return Vector2(slot_x, slot_y)

func _tile_size() -> Vector2:
	if terrain_layer != null and terrain_layer.tile_set != null:
		return Vector2(terrain_layer.tile_set.tile_size)
	return Vector2(540, 480)

func _icon_area_size() -> Vector2:
	var tile_size := _tile_size()
	return Vector2(tile_size.x * 0.72, tile_size.y * 0.56)

func _icon_slot_size() -> Vector2:
	var icon_area := _icon_area_size()
	return Vector2(icon_area.x / ICONS_PER_ROW, icon_area.y / ICON_ROWS)
