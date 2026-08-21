extends Node2D
## Port dockhouse glyphs: every port tile (data/ports.csv) gets a large white
## harbour building hugging its sea-facing edge, with rectangular pier fingers
## sticking out into the sea. Static decoration — geometry computed once in
## setup(), drawn once, no _process (CLAUDE.md rule #2).

## Dockhouse/pier/outline colors live in MapStyle ('toggle ink' swaps them).
# The dockhouse reads ~40 screen px thick at max zoom: max zoom frames ~2.5
# tile-heights per ~1080px viewport, so 40px ≈ 0.09 tile heights.
const THICKNESS_FRAC := 0.09
const LENGTH_FRAC := 0.52      # dockhouse length along the shore, in tile heights
const PIER_LEN_FRAC := 0.30    # how far the pier fingers reach into the sea
const PIER_COUNT := 3
## Breakwater arms: poured concrete, a shade cooler and greyer than the timber decks
## (Color("c8b890")) so the two structures stay legible where an arm meets a quay.
const ARM_COLOR := Color("b9ad93")

var _glyphs: Array = []   # [{pos: Vector2, angle: float, tile_h: float}]
var _hex_map: TileMapLayer = null
var _midcentury_plans: Array = []
var _rebuild_queued := false
var _diagnostic_overlay := false

func _ready() -> void:
	MapStyle.style_changed.connect(queue_redraw)
	if not RoadWorks.order_settled.is_connected(_on_authoritative_geometry_changed):
		RoadWorks.order_settled.connect(_on_authoritative_geometry_changed)

func setup(hex_map: TileMapLayer) -> void:
	_hex_map = hex_map
	_glyphs.clear()
	_midcentury_plans.clear()
	var tile_h := float(hex_map.tile_set.tile_size.y)
	for p in Catalog.all_ports():
		var coord: Vector2i = hex_map.id_to_coord(str(p.get("tile_id", "")))
		if coord == Vector2i(-1, -1) or not hex_map.tiles.has(coord):
			continue
		var cell: Vector2i = hex_map.map_coord_for_tile_coord(coord)
		var center: Vector2 = hex_map.map_to_local(cell)
		# Face the first sea neighbour — ports sit on the coast by construction.
		var sea_dir := Vector2.ZERO
		for ncell in hex_map.get_surrounding_cells(cell):
			var ntile: Dictionary = hex_map.tiles.get(hex_map.tile_coord_for_map_coord(ncell), {})
			if str(ntile.get("type", "")) in ["sea", "deep_sea"]:
				sea_dir = (hex_map.map_to_local(ncell) - center).normalized()
				break
		if sea_dir == Vector2.ZERO:
			continue   # no adjacent sea — nothing sensible to draw
		_glyphs.append({
			"pos": to_local(hex_map.to_global(center + sea_dir * tile_h * 0.30)),
			"angle": sea_dir.angle(),
			"tile_h": tile_h,
		})
	var footprint_source := get_tree().get_first_node_in_group("building_footprints")
	if footprint_source != null and footprint_source.has_signal("footprints_changed") and \
			not footprint_source.footprints_changed.is_connected(
			_on_footprints_changed):
		footprint_source.footprints_changed.connect(_on_footprints_changed)
	_rebuild_midcentury_plans()
	queue_redraw()

func _on_footprints_changed(_version: int, affected_tile_ids: Array) -> void:
	# Ports are fixed coastal geometry; the 4-port planner costs ~15-20s to re-run. Only replan
	# when a PORT tile's footprint actually changes — not when a mine/furnace lands elsewhere,
	# which was re-triggering the whole planner on every 'order from market' (owner lag, 2026-08-19).
	if not _footprints_touch_a_port(affected_tile_ids):
		return
	_queue_plan_rebuild()

func _footprints_touch_a_port(tile_ids: Array) -> bool:
	if tile_ids == null or tile_ids.is_empty():
		return true   # unknown scope — rebuild to be safe
	var port_tiles := {}
	for p in Catalog.all_ports():
		port_tiles[str((p as Dictionary).get("tile_id", ""))] = true
	for t in tile_ids:
		if port_tiles.has(str(t)):
			return true
	return false

func _on_authoritative_geometry_changed(_order_id: int) -> void:
	MidcenturyPortPlan.invalidate_cache()
	_queue_plan_rebuild()

func _queue_plan_rebuild() -> void:
	if _rebuild_queued:
		return
	_rebuild_queued = true
	_rebuild_midcentury_plans.call_deferred()

func _rebuild_midcentury_plans() -> void:
	_rebuild_queued = false
	_midcentury_plans.clear()
	if _hex_map == null:
		return
	var source := get_tree().get_first_node_in_group("building_footprints")
	var instances: Array = []
	if source != null and source.has_method("midcentury_port_instances"):
		instances = source.midcentury_port_instances()
	else:
		for port_value in Catalog.all_ports():
			var port: Dictionary = port_value
			instances.append({"tile_id": str(port.get("tile_id", "")),
				"instance_id": str(port.get("id", ""))})
	instances.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if str(a.tile_id) != str(b.tile_id):
			return str(a.tile_id) < str(b.tile_id)
		return str(a.instance_id) < str(b.instance_id))
	for instance_value in instances:
		var instance: Dictionary = instance_value
		var plan := MidcenturyPortPlan.build(_hex_map,
			str(instance.get("tile_id", "")), str(instance.get("instance_id", "")))
		if not plan.is_empty() and bool(plan.get("valid", false)):
			_midcentury_plans.append(plan)
	queue_redraw()

func _draw() -> void:
	# THE PLAN IS THE PORT. When the coastline planner has produced a valid harbour it is
	# drawn in every style, not just under the midcentury toggle. The plan was already being
	# computed on every load regardless of style (setup -> _rebuild_midcentury_plans), and
	# nothing in the shipped game ever turns midcentury ON — only a debug cheat does — so the
	# two arms, the basin and the quay were being paid for and then thrown away, while the
	# player saw the older pier-fingers glyph. The map's fabric is already drawn from the
	# midcentury palette (the authored document), so the harbour now matches its town.
	if not _midcentury_plans.is_empty():
		_draw_midcentury_ports()
		return
	if MapStyle.is_midcentury():
		return   # midcentury with no valid plan: draw nothing rather than a foreign glyph
	if MapStyle.uses_ink_linework():
		# Ink mode: the shape-language port (quay spine + warehouses +
		# container stacks + plank piers + jib cranes), world-lit like every
		# other generated building. Ports are neutral infrastructure -> npc
		# tint off.
		# Anchor design-space (74, 78) — the quay spine's seaward edge — at the
		# glyph position on the shoreline, so the spine hugs the coast and the
		# three piers reach out to sea (owner ruling; -20% size).
		# City plate washes the compound logistics tan; transparent elsewhere
		# leaves the generator's own neutral greys.
		var pwash := MapStyle.port_art_wash()
		for g in _glyphs:
			InkBuildingGen.draw(self, "port", 1, g["pos"] as Vector2, float(g["angle"]), float(g["tile_h"]) * 0.44, false, Vector2(74, 78), pwash)
		return
	var dockhouse := MapStyle.port_dockhouse()
	var outline := MapStyle.port_outline()
	var pier := MapStyle.port_pier()
	for g in _glyphs:
		var tile_h: float = g["tile_h"]
		var thick := tile_h * THICKNESS_FRAC
		var b_len := tile_h * LENGTH_FRAC
		var pier_len := tile_h * PIER_LEN_FRAC
		var pier_w := thick * 0.45
		# Local +x points seaward; the dockhouse slab sits on the land side of
		# the origin, the piers finger out into the water.
		draw_set_transform(g["pos"] as Vector2, float(g["angle"]), Vector2.ONE)
		for i in range(PIER_COUNT):
			var t := (float(i) - float(PIER_COUNT - 1) / 2.0) / float(PIER_COUNT)
			var y := t * b_len * 0.8 - pier_w * 0.5
			draw_rect(Rect2(Vector2(0.0, y), Vector2(pier_len, pier_w)), pier, true)
			draw_rect(Rect2(Vector2(0.0, y), Vector2(pier_len, pier_w)), outline, false, tile_h * 0.008)
			if MapStyle.uses_ink_linework():
				# Timber read: plank tick hairlines across each finger.
				var plank := MapStyle.pier_plank_color()
				var px := 5.0
				while px < pier_len - 2.0:
					draw_line(Vector2(px, y), Vector2(px, y + pier_w), plank, 0.9, true)
					px += 6.0
		draw_rect(Rect2(Vector2(-thick, -b_len * 0.5), Vector2(thick, b_len)), dockhouse, true)
		draw_rect(Rect2(Vector2(-thick, -b_len * 0.5), Vector2(thick, b_len)), outline, false, tile_h * 0.012)
	draw_set_transform_matrix(Transform2D.IDENTITY)

func midcentury_plans() -> Array:
	return _midcentury_plans.duplicate(true)

## Capture-tool seam only. The overlay is disabled by default and never toggled
## by gameplay or the style cheat.
func set_diagnostic_overlay(on: bool) -> void:
	_diagnostic_overlay = on
	queue_redraw()

func _draw_midcentury_ports() -> void:
	for plan_value in _midcentury_plans:
		var plan: Dictionary = plan_value
		for poly_value in plan.apron_polygons:
			_draw_filled_poly(poly_value,
				MapMidcenturyStyle.industrial_yard("%s|land" % str(plan.key)))
		# THE TWO ARMS. Parallel moles reaching seaward off the apron, one per side, enclosing
		# the basin — the thing that makes this read as a harbour rather than a wharf. Drawn
		# before the decks so a deck sitting on an arm root reads as built ON it, and shadowed
		# like every other raised structure so they sit above the water rather than in it.
		for poly_value in plan.left_arm_polygons:
			_draw_shadow(poly_value)
		for poly_value in plan.right_arm_polygons:
			_draw_shadow(poly_value)
		for poly_value in plan.left_arm_polygons:
			_draw_filled_poly(poly_value, ARM_COLOR)
		for poly_value in plan.right_arm_polygons:
			_draw_filled_poly(poly_value, ARM_COLOR)
		for poly_value in plan.deck_polygons:
			_draw_shadow(poly_value)
		for poly_value in plan.deck_polygons:
			_draw_filled_poly(poly_value, Color("c8b890"))
		for poly_value in plan.warehouse_polygons:
			_draw_shadow(poly_value)
			_draw_filled_poly(poly_value,
				MapMidcenturyStyle.gameplay_block_top("brick"))
			_draw_warehouse_cap(poly_value, str(plan.key))
		for poly_value in plan.container_polygons:
			var poly: PackedVector2Array = poly_value
			var index := RoadHash.pick("%s|container|%s" % [str(plan.key),
				str(_poly_center(poly))], InkBuildingGen.CONTAINER_COLS.size())
			_draw_filled_poly(poly, InkBuildingGen.CONTAINER_COLS[index])
		for crane_value in plan.crane_sites:
			var crane: Dictionary = crane_value
			_draw_crane(crane)
		var access: PackedVector2Array = plan.road_access
		if access.size() >= 2:
			draw_polyline(access, Color(MapMidcenturyStyle.INK, 0.62), 6.2, true)
			draw_polyline(access, MapMidcenturyStyle.PAPER, 4.2, true)
	if _diagnostic_overlay:
		_draw_midcentury_diagnostics()

func _draw_midcentury_diagnostics() -> void:
	for plan_value in _midcentury_plans:
		var plan: Dictionary = plan_value
		var basin: PackedVector2Array = plan.basin_polygon
		draw_colored_polygon(basin, Color(0.12, 0.48, 0.83, 0.24))
		draw_polyline(_closed(basin), Color("2472ae"), 2.2, true)
		var corridor: PackedVector2Array = plan.open_water_corridor
		draw_colored_polygon(corridor, Color(0.18, 0.78, 0.92, 0.20))
		draw_polyline(_closed(corridor), Color("2ca5b8"), 1.7, true)
		for poly_value in plan.land_polygons:
			draw_polyline(_closed(poly_value), Color("f4c542"), 2.6, true)
		for poly_value in plan.left_arm_polygons:
			draw_polyline(_closed(poly_value), Color("e05353"), 2.4, true)
		for poly_value in plan.right_arm_polygons:
			draw_polyline(_closed(poly_value), Color("a34ed4"), 2.4, true)
		var ring: PackedVector2Array = plan.get("interarm_ring",
			PackedVector2Array())
		if ring.size() >= 3:
			draw_polyline(_closed(ring), Color("18d06a"), 2.0, true)
		for poly_value in plan.river_exclusions:
			draw_polyline(_closed(poly_value), Color(0.92, 0.20, 0.20, 0.82),
				2.0, true)
		for point in (plan.coastline_samples as PackedVector2Array):
			draw_circle(point, 2.2, Color("f4c542"))
		var access: PackedVector2Array = plan.road_access
		if access.size() >= 2:
			draw_polyline(access, Color("f7f7f7"), 5.4, true)
			draw_polyline(access, Color("5b35d5"), 2.0, true)

func _draw_shadow(poly_value: Variant) -> void:
	var poly: PackedVector2Array = poly_value
	var shadow := PackedVector2Array()
	for point in poly:
		shadow.append(point + Vector2(2.2, 2.8))
	draw_colored_polygon(shadow, Color(MapMidcenturyStyle.SHADOW, 0.72))

func _draw_warehouse_cap(poly_value: Variant, key: String) -> void:
	var poly: PackedVector2Array = poly_value
	var center := _poly_center(poly)
	var cap := PackedVector2Array()
	var scale := 0.72 + float(RoadHash.pick("%s|warehouse-cap" % key, 9)) * 0.012
	for point in poly:
		cap.append(center + (point - center) * scale)
	_draw_shadow(cap)
	_draw_filled_poly(cap, Color("a6634f"))

func _draw_crane(crane: Dictionary) -> void:
	var position: Vector2 = crane.position
	var direction: Vector2 = crane.direction
	var cross: Vector2 = crane.cross
	var arm := str(crane.arm)
	var basin_direction := -cross if arm == "left" else cross
	var span := float(crane.gantry_span)
	var jib := float(crane.jib_length)
	var base: PackedVector2Array = crane.base_polygon
	_draw_shadow(base)
	_draw_filled_poly(base, MapMidcenturyStyle.gameplay_block_top("mustard"))
	var rail_a := position - cross * span * 0.5
	var rail_b := position + cross * span * 0.5
	var shadow_offset := Vector2(2.2, 2.8)
	draw_line(rail_a + shadow_offset, rail_b + shadow_offset,
		Color(MapMidcenturyStyle.SHADOW, 0.72), 4.8, true)
	draw_line(rail_a, rail_b, MapMidcenturyStyle.INK, 3.2, true)
	for side in [-1.0, 1.0]:
		var leg := position + cross * float(side) * span * 0.40
		draw_circle(leg, 2.8, MapMidcenturyStyle.gameplay_block_top("mustard"))
		draw_arc(leg, 2.8, 0.0, TAU, 12, MapMidcenturyStyle.INK, 1.1, true)
	var jib_end := position + basin_direction * jib + direction * 4.0
	draw_line(position + shadow_offset, jib_end + shadow_offset,
		Color(MapMidcenturyStyle.SHADOW, 0.72), 4.6, true)
	draw_line(position, jib_end,
		MapMidcenturyStyle.gameplay_block_top("mustard"), 3.0, true)
	draw_line(position, jib_end, MapMidcenturyStyle.INK, 1.0, true)
	draw_circle(jib_end, 2.1, MapMidcenturyStyle.INK)

func _draw_filled_poly(poly: PackedVector2Array, color: Color) -> void:
	draw_colored_polygon(poly, color)
	draw_polyline(PackedVector2Array(Array(poly) + [poly[0]]),
		MapMidcenturyStyle.INK, 1.05, true)

func _poly_center(poly: PackedVector2Array) -> Vector2:
	var center := Vector2.ZERO
	for point in poly:
		center += point
	return center / maxf(1.0, float(poly.size()))

func _closed(poly_value: Variant) -> PackedVector2Array:
	var poly: PackedVector2Array = poly_value
	var out := poly.duplicate()
	if not out.is_empty():
		out.append(out[0])
	return out
