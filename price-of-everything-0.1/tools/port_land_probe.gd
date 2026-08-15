extends SceneTree
## Diagnostic probe only. Answers one question: does the NavGrid water class the
## port gates trust agree with the RENDERED coastline (the band-5 "land base"
## polygon whose boundary hill_visuals strokes as the coast)? Disagreement would
## mean the port audit and the picture are measuring different worlds.
## Samples only the coastal band, where any disagreement would live.

const COAST_BAND_DISTANCE := 60.0

func _init() -> void:
	var land_polys: Array = []
	for entry_value in HillBaked.sea():
		var entry: Dictionary = entry_value
		if int(entry.b) != 5:
			continue
		var poly: PackedVector2Array = entry.p
		if poly.size() >= 3:
			land_polys.append({"poly": poly, "bb": _bbox(poly)})
	var nav := NavGrid.instance()
	print("band-5 land polygons: %d ; navgrid ready=%s step=%.1f gw=%d gh=%d" % [
		land_polys.size(), str(nav.is_ready()), nav.step, nav.gw, nav.gh])
	var total := 0
	var agree := 0
	var nav_sea_render_land := 0
	var nav_land_render_sea := 0
	for iy in range(nav.gh):
		for ix in range(nav.gw):
			if nav.water_distance(ix, iy) > COAST_BAND_DISTANCE:
				continue
			var point := nav.world_of(ix, iy)
			var nav_is_sea := nav.water(ix, iy) == NavGrid.WATER_SEA
			var render_is_land := _inside_any(point, land_polys)
			total += 1
			if nav_is_sea != render_is_land:
				agree += 1
			elif nav_is_sea:
				nav_sea_render_land += 1
			else:
				nav_land_render_sea += 1
	print("coastal-band samples=%d agreement=%.3f%% navSea/renderLand=%d navLand/renderSea=%d" % [
		total, 100.0 * float(agree) / maxf(1.0, float(total)),
		nav_sea_render_land, nav_land_render_sea])
	quit(0)

func _inside_any(point: Vector2, records: Array) -> bool:
	for record_value in records:
		var record: Dictionary = record_value
		if not (record.bb as Rect2).has_point(point):
			continue
		if Geometry2D.is_point_in_polygon(point, record.poly):
			return true
	return false

func _bbox(poly: PackedVector2Array) -> Rect2:
	var lo := poly[0]
	var hi := poly[0]
	for point in poly:
		lo = lo.min(point)
		hi = hi.max(point)
	return Rect2(lo, hi - lo)
