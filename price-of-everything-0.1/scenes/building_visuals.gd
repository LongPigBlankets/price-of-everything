extends Node2D

# Polygon building footprints (polygon-buildings plan, phases 1-2). Each
# non-forest, non-road building is a coloured SHAPE (square/rect/L×2/squared-C),
# its AREA = (tile_size_used / build_capacity) × the tile's buildable area (hex
# minus water), packed onto the tile's free LAND cells without overlap. Category
# colour from the size chart; NPC = thick white outline. Placement is incremental
# and stable — a building keeps its spot until demolished. Phase 3 swaps the
# centre-out pack for road-frontage gravitation + low-ground + edge rules and
# starts avoiding roads/forests (today only water is avoided).

const TileViewData := preload("res://scripts/tile_view_data.gd")

const ROADS_BUILDING_ID := "b_005"
const FOREST_BUILDING_IDS := {"b_015": true, "b_016": true}

# Buildable grid: 27×24 cells of 20u in the tile-local frame. The hex is FLAT-TOP
# (verts (135,0)(405,0)(540,240)(405,480)(135,480)(0,240), centre (270,240)) — the
# geometry roads/forests/navgrid all use; SubtileGrid's hex_polygon is pointy-top
# and inconsistent, so we test the hex ourselves.
const GRID_COLS := 27
const GRID_ROWS := 24
const CELL := 20.0
const TILE_CENTER := Vector2(270.0, 240.0)
const DESIGN_GAP := 5.0              # gap kept around each footprint
const BUILDABLE_MIN_AREA := 400.0    # never size a footprint below ~1 cell

const NPC_OUTLINE_W := 7.0
const CASING := Color(0.12, 0.10, 0.06, 0.85)
const CASING_W := 2.0

## Viewport culling: when no more than this many footprints are on screen (zoomed
## in) draw only the visible ones; above it draw everything once and stay static.
const CULL_CAP := 160
const CULL_MARGIN := 600.0

@onready var terrain_layer: HexMap = %TerrainLayer

# Per-placement: {instance_id, tile_id, cells: PackedInt32Array, verts, color, is_npc, bb}
var _placements: Array = []
var _placement_index: Dictionary = {}   # instance_id -> index into _placements

# Per-tile caches (built lazily, on first building)
var _tile_land: Dictionary = {}    # tile_id -> PackedByteArray (1 = in-hex land cell)
var _tile_occ: Dictionary = {}     # tile_id -> PackedByteArray (1 = taken by a footprint)
var _tile_order: Dictionary = {}   # tile_id -> Array[int] cell keys, centre-out scan order
var _tile_area: Dictionary = {}    # tile_id -> buildable area (u²)

var _cull := false
var _view := Rect2()

func on_building_placed(tile_id: String, building_id: String, _recipe_id: String, instance_id: String, coord: Vector2i) -> void:
	if building_id == ROADS_BUILDING_ID or FOREST_BUILDING_IDS.has(building_id):
		return  # roads aren't buildings; forests are drawn by ForestVisuals
	# Re-placement (e.g. a load re-emitting building_placed) must not orphan the
	# old footprint — drop it first so its cells free and it can't ghost.
	if instance_id != "" and _placement_index.has(instance_id):
		remove_instance(instance_id)
	_ensure_tile(tile_id, coord)
	var bd := Catalog.get_building(building_id)
	var size_units := int(bd.get("tile_size_used", 1))
	var capacity := maxi(int(terrain_layer.tiles.get(coord, {}).get("build_capacity", 200)), 1)
	var area := maxf(float(size_units) / float(capacity) * float(_tile_area[tile_id]), BUILDABLE_MIN_AREA)
	var kind: String = BuildingShapes.KINDS[RoadHash.pick("poly|%s|%s|kind" % [tile_id, instance_id], BuildingShapes.KINDS.size())]
	var seed_v := RoadHash.pick("poly|%s|%s|var" % [tile_id, instance_id], 9)

	# Place at the requested area; shrink and retry if the tile is too full.
	var placed := _pack(tile_id, coord, kind, area, seed_v)
	var tries := 0
	while placed.is_empty() and tries < 4:
		area *= 0.6
		placed = _pack(tile_id, coord, kind, maxf(area, BUILDABLE_MIN_AREA), seed_v)
		tries += 1
	if placed.is_empty():
		return  # genuinely no room left on the tile

	var verts: PackedVector2Array = placed.verts
	var placement := {
		"instance_id": instance_id,
		"tile_id": tile_id,
		"cells": placed.cells,
		"verts": verts,
		"color": TileViewData.category_color(bd),
		"is_npc": not MatchState.is_player_owned(MatchState.get_building(instance_id)),
		"bb": _verts_bb(verts).grow(NPC_OUTLINE_W),
	}
	if instance_id != "":
		_placement_index[instance_id] = _placements.size()
	_placements.append(placement)
	queue_redraw()

## Build (once) the tile's land mask, buildable area, and a centre-out scan order.
func _ensure_tile(tile_id: String, coord: Vector2i) -> void:
	if _tile_land.has(tile_id):
		return
	var n := GRID_COLS * GRID_ROWS
	var land := PackedByteArray()
	land.resize(n)
	var occ := PackedByteArray()
	occ.resize(n)
	var center := _tile_center_world_pos(coord)
	var nav := NavGrid.instance()
	var nav_ok := nav != null and nav.is_ready()
	var order: Array = []   # [dist2, key]
	var land_count := 0
	for row in GRID_ROWS:
		for col in GRID_COLS:
			var rel := Vector2((col + 0.5) * CELL, (row + 0.5) * CELL) - TILE_CENTER
			if absf(rel.x) > 270.0 or absf(rel.y) > 240.0 or 240.0 * absf(rel.x) + 135.0 * absf(rel.y) > 64800.0:
				continue   # outside the flat-top hex
			if nav_ok:
				var c := nav.cell_of(center + rel)
				if nav.water(c.x, c.y) != 0:
					continue   # water (sea/lake/river) — not buildable
			var key := row * GRID_COLS + col
			land[key] = 1
			land_count += 1
			order.append([rel.length_squared(), key])
	order.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	var keys := PackedInt32Array()
	for entry in order:
		keys.append(int(entry[1]))
	_tile_land[tile_id] = land
	_tile_occ[tile_id] = occ
	_tile_order[tile_id] = keys
	_tile_area[tile_id] = maxf(float(land_count) * CELL * CELL, BUILDABLE_MIN_AREA)

## Find the first free, all-land pocket (centre-out) the shape's bbox fits in,
## place it there, and return {verts (world), cells (occupied keys)}; {} if none.
func _pack(tile_id: String, coord: Vector2i, kind: String, area: float, seed_v: int) -> Dictionary:
	if not _tile_land.has(tile_id):
		return {}   # caller must _ensure_tile first; never KeyError-crash on a miss
	var shape := BuildingShapes.make(kind, area, seed_v)
	var half: Vector2 = shape.half
	var chw := int(ceil((half.x + DESIGN_GAP) / CELL))
	var chh := int(ceil((half.y + DESIGN_GAP) / CELL))
	var land: PackedByteArray = _tile_land[tile_id]
	var occ: PackedByteArray = _tile_occ[tile_id]
	for key in (_tile_order[tile_id] as PackedInt32Array):
		var col := key % GRID_COLS
		var row := key / GRID_COLS   # int/int = integer division (inverse of row*GRID_COLS+col)
		if col < chw or col >= GRID_COLS - chw or row < chh or row >= GRID_ROWS - chh:
			continue
		if not _fits(land, occ, col, row, chw, chh):
			continue
		var cells := _mark(occ, col, row, chw, chh)
		var center := _tile_center_world_pos(coord)
		var world_center := center + (Vector2((col + 0.5) * CELL, (row + 0.5) * CELL) - TILE_CENTER)
		var verts := PackedVector2Array()
		for v in (shape.verts as PackedVector2Array):
			verts.append(world_center + v)
		return {"verts": verts, "cells": cells}
	return {}

func _fits(land: PackedByteArray, occ: PackedByteArray, col: int, row: int, chw: int, chh: int) -> bool:
	for r in range(row - chh, row + chh + 1):
		var base := r * GRID_COLS
		for c in range(col - chw, col + chw + 1):
			var key := base + c
			if land[key] == 0 or occ[key] == 1:
				return false
	return true

func _mark(occ: PackedByteArray, col: int, row: int, chw: int, chh: int) -> PackedInt32Array:
	var cells := PackedInt32Array()
	for r in range(row - chh, row + chh + 1):
		var base := r * GRID_COLS
		for c in range(col - chw, col + chw + 1):
			occ[base + c] = 1
			cells.append(base + c)
	return cells

func _verts_bb(verts: PackedVector2Array) -> Rect2:
	var lo := verts[0]
	var hi := verts[0]
	for v in verts:
		lo = Vector2(minf(lo.x, v.x), minf(lo.y, v.y))
		hi = Vector2(maxf(hi.x, v.x), maxf(hi.y, v.y))
	return Rect2(lo, hi - lo)

## Cull to the viewport when zoomed in, else draw all once and stay static.
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
		_view = view
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
	# A loaded save rebuilds visuals (world_map._rebuild_after_load).
	_placements.clear()
	_placement_index.clear()
	_tile_land.clear()
	_tile_occ.clear()
	_tile_order.clear()
	_tile_area.clear()
	queue_redraw()

func remove_instance(instance_id: String) -> void:
	# A cancelled/demolished building frees its footprint cells.
	if not _placement_index.has(instance_id):
		return
	var idx: int = _placement_index[instance_id]
	var p: Dictionary = _placements[idx]
	# Free the footprint's cells. Direct dict access (not .get with a default) so
	# the write lands on the cached array, not a throwaway; guard a missing tile.
	if _tile_occ.has(p.tile_id):
		var occ: PackedByteArray = _tile_occ[p.tile_id]
		for key in (p.cells as PackedInt32Array):
			if key >= 0 and key < occ.size():
				occ[key] = 0
	_placements.remove_at(idx)
	_placement_index.erase(instance_id)
	for iid in _placement_index:
		if _placement_index[iid] > idx:
			_placement_index[iid] -= 1
	queue_redraw()

func _draw() -> void:
	for placement in _placements:
		if _cull and not _view.intersects(placement.bb):
			continue
		var verts: PackedVector2Array = placement.verts
		draw_colored_polygon(verts, placement.color)
		var loop := verts.duplicate()
		loop.append(verts[0])
		if bool(placement.is_npc):
			draw_polyline(loop, Color.WHITE, NPC_OUTLINE_W, true)
		else:
			draw_polyline(loop, CASING, CASING_W, true)

func _tile_center_world_pos(coord: Vector2i) -> Vector2:
	if terrain_layer != null:
		return terrain_layer.map_to_local(terrain_layer.map_coord_for_tile_coord(coord))
	return Vector2.ZERO
