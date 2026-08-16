class_name SettlementPlanDebugVisuals
extends Node2D

var plan: SettlementPlan
var show_zoning := false
var show_water_safety := false

func _draw() -> void:
	if plan == null:
		return
	for poly_value in plan.extent_polygons:
		var poly: PackedVector2Array = poly_value
		draw_colored_polygon(poly, Color("d6c58d", 0.34))
		draw_polyline(_closed(poly), Color("7d593c"), 2.2, true)
	for i in plan.faces.size():
		var face: Dictionary = plan.faces[i]
		var poly: PackedVector2Array = face.poly
		var color := Color("78906c", 0.42) if i % 3 == 0 else (Color("8c8174", 0.36) if i % 3 == 1 else Color("b49a68", 0.34))
		draw_colored_polygon(poly, color)
		draw_polyline(_closed(poly), Color("4a4036", 0.70), 1.0, true)
	if show_water_safety:
		for i in plan.water_exclusions.size():
			var exclusion: Dictionary = plan.water_exclusions[i]
			var poly: PackedVector2Array = exclusion.poly
			draw_colored_polygon(poly, Color("396f92", 0.34))
			draw_polyline(_closed(poly), Color("234d68", 0.92), 1.8, true)
		for mass_value in plan.masses:
			var mass: Dictionary = mass_value
			var poly: PackedVector2Array = mass.poly
			var face_index := _face_index_for_point(_center(poly))
			var color := _bank_face_color(face_index)
			if str(mass.get("role", "ordinary")) == "industry-support":
				color = Color("b85b45", 0.90)
			draw_colored_polygon(poly, color)
			draw_polyline(_closed(poly), Color("312b27", 0.86), 0.9, true)
	if show_zoning:
		for parcel_value in plan.parcels:
			var parcel: Dictionary = parcel_value
			var poly: PackedVector2Array = parcel.poly
			var color := Color("756d64", 0.68)
			match str(parcel.role):
				"park":
					color = Color("769365", 0.76)
				"yard":
					color = Color("b08a55", 0.66)
				"open":
					color = Color("d5c99e", 0.42)
			draw_colored_polygon(poly, color)
			draw_polyline(_closed(poly), Color("4a4036", 0.48), 0.85, true)
	for spline_value in plan.boundary_splines:
		var spline: Dictionary = spline_value
		var points: PackedVector2Array = spline.points
		var rendered_width := float(spline.get("rendered_width", 12.0))
		draw_polyline(points, Color("446779", 0.50), rendered_width + 2.7, true)
		draw_polyline(points, Color("73a1b4"), rendered_width, true)
	for road_value in plan.authoritative_roads:
		var road: Dictionary = road_value
		draw_line(road.a, road.b, Color("40382f", 0.72), 8.0, true)
		draw_line(road.a, road.b, Color("efe3bd"), 5.2, true)
	for street_value in plan.decorative_streets:
		var street: Dictionary = street_value
		var points: PackedVector2Array = street.points
		draw_polyline(points, Color("8e4e3c"), 7.0, true)
		draw_polyline(points, Color("f3d89d"), 3.8, true)
		draw_circle(points[0], 4.2, Color("c54f3d"))
		draw_circle(points[points.size() - 1], 4.2, Color("c54f3d"))
	for reservation_value in plan.industrial_reservations:
		var reservation: Dictionary = reservation_value
		var poly: PackedVector2Array = reservation.poly
		draw_colored_polygon(poly, Color("ad5a4a", 0.46))
		draw_polyline(_closed(poly), Color("6d3029"), 1.5, true)
	for lot_value in plan.open_lots:
		var lot: Dictionary = lot_value
		var poly: PackedVector2Array = lot.poly
		draw_colored_polygon(poly, Color("d3b568", 0.28))
		draw_polyline(_closed(poly), Color("80622c"), 1.1, true)
	for guide_value in plan.district_guides:
		var guide: Dictionary = guide_value
		draw_circle(guide.point, 5.0, Color("f1ca4d"))
		draw_arc(guide.point, 8.0, 0.0, TAU, 20, Color("40382f"), 1.2, true)

func _closed(poly: PackedVector2Array) -> PackedVector2Array:
	var out := poly.duplicate()
	if not out.is_empty():
		out.append(out[0])
	return out

func _center(poly: PackedVector2Array) -> Vector2:
	var center := Vector2.ZERO
	for point in poly:
		center += point
	return center / maxf(1.0, float(poly.size()))

func _face_index_for_point(point: Vector2) -> int:
	for i in plan.faces.size():
		if Geometry2D.is_point_in_polygon(point,
				(plan.faces[i] as Dictionary).poly):
			return i
	return -1

func _bank_face_color(index: int) -> Color:
	var colors := [
		Color("795d52", 0.82), Color("8f765b", 0.82),
		Color("596f65", 0.82), Color("6d677b", 0.82),
		Color("8a675e", 0.82), Color("617884", 0.82),
	]
	return colors[posmod(index, colors.size())] if index >= 0 else Color("ad9d75", 0.72)
