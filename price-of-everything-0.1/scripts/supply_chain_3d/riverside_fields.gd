extends RefCounted
## Presentation-only enlargement of the west-bank Stoneshore farm. Keep its
## barn pose and repeated crop lattice; reserve the new parcel before infill.
const Fields := preload("res://scripts/supply_chain_3d/farm_fields.gd")
const Coast := preload("res://scripts/supply_chain_3d/coast.gd")
const Cache := preload("res://scripts/supply_chain_3d/bake_cache.gd")
const Legacy := preload("res://scripts/empire_board.gd")
const Clip := preload("res://scripts/supply_chain_3d/sea_fringe.gd")
const FARM := "start_b_014_tile_6_9"
const EAST_REACH := 120.0
const BANK_MARGIN := 6.0 # beyond the water edge, including its painted bank

static func river_masks(relief: Dictionary, rivers: Array) -> Array:
	var masks: Array = []
	for rec in rivers:
		# Use the same mouth adjustment as WaterArt, not the upstream source line.
		var width := (float(rec.start_width) + float(rec.end_width)) * .5
		var line := Legacy._aim_mouth(relief, rec.points, relief.shore, width)
		for run in Legacy._to_mouth(relief, line, relief.shore, width):
			masks.append_array(Geometry2D.offset_polyline(run.pts, width * .5 + BANK_MARGIN,
				Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND))
	return masks

static func extend(original: PackedVector2Array, anchor: Vector2, land: Array, masks: Array) -> PackedVector2Array:
	var swept := original.duplicate()
	for p in original: swept.append(p + Vector2.RIGHT * EAST_REACH)
	var envelope := Geometry2D.convex_hull(swept)
	var parts: Array = []
	for polygon in land: parts.append_array(Geometry2D.intersect_polygons(envelope, polygon))
	for mask in masks:
		var remaining: Array = []
		for part in parts: remaining.append_array(Clip._subtract(part, mask))
		parts = remaining
	# Cutting the river can leave a second piece on the opposite bank. Only the
	# parcel connected to this barn belongs to this field.
	for part in parts:
		if Geometry2D.is_point_in_polygon(anchor, part): return part
	return original

static func apply(model: Dictionary, rivers: Dictionary, prepared: Dictionary) -> void:
	for s in model.standing:
		if str(s.iid) != FARM or not Fields.is_plot(s): continue
		var records: Array = rivers.get(str(s.tile), [])
		if records.is_empty(): return
		var key := Cache.digest([Cache.source_key("roads"), Cache.source_key("terrain"), s.footprint, s.pos, records])
		var saved: Dictionary = prepared.get("riverside_fields", {})
		if saved.get("key", "") != key:
			var relief := Coast.relief_of(str(s.tile), model.tiles[s.tile].center)
			var water := Coast.Water.for_tile(str(s.tile))
			var masks := river_masks(relief, records)
			# Do not inset the tile polygon: that would create an artificial seam
			# at its edge. Only actual coastlines and lakes receive a bank margin.
			for edge in water.shore:
				masks.append(Legacy._capsule(edge[0], edge[1], BANK_MARGIN, [true, true]))
			for lake in water.lakes: masks.append_array(Geometry2D.offset_polygon(lake, BANK_MARGIN))
			saved = {"key": key, "polygon": extend(s.footprint, s.pos, water.land, masks)}
			prepared.riverside_fields = saved
		s.source_field_footprint = s.footprint
		s.footprint = saved.polygon
