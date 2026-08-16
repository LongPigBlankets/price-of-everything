class_name SettlementPlan
extends RefCounted
## Draw-only urban plan consumed by the optional mid-century renderer.
##
## A plan deliberately separates settlement-scale authorship from the map's
## authoritative tile, road, river, placement, and simulation records. Nothing
## stored here owns land, participates in pathfinding, or changes interaction.

var key := ""
var tile_ids: Array[String] = []

# 1. Settlement extent: authored visible boundaries, not tile silhouettes.
var extent_polygons: Array = []
# 2. Street/boundary graph.
var authoritative_roads: Array = []
var decorative_streets: Array = []
var boundary_splines: Array = []
# Shared renderer-derived water safety geometry. Entries are draw-only merged
# polygons plus their source paths/lakes; no NavGrid or simulation state changes.
var water_exclusions: Array = []
var water_paths: Array = []
var water_lakes: Array = []
# Shared renderer-derived land relief. Shoulder polygons follow HillVisuals'
# exact baked contour boundaries; plateau records are read-only diagnostics.
var relief_shoulders: Array = []
var relief_plateaus: Array = []
var material_relief_bands: Array = []
# 3. District guides.
var district_guides: Array = []
var suburban_districts: Array = []
var density_guides: Array = []
var height_guides: Array = []
# 4. Enclosed block faces.
var faces: Array = []
# 5. Parcel roles and ordinary massing.
var parcels: Array = []
var masses: Array = []
var industrial_reservations: Array = []
var open_lots: Array = []
var accommodation_sites: Array = []
# Final rendered records retained only for independent water diagnostics.
var visual_shadows: Array = []
var visual_roof_elements: Array = []
var visual_roof_marks: Array = []
# 6–7. Retained as explicit later consumers; this prototype leaves them quiet.
var height_accents: Array = []
var far_zoom_silhouettes: Array = []

var diagnostics: Dictionary = {}

func _init(plan_key: String = "") -> void:
	key = plan_key

func extent_area() -> float:
	var area := 0.0
	for poly_value in extent_polygons:
		area += polygon_area(poly_value as PackedVector2Array)
	return area

func face_area() -> float:
	var area := 0.0
	for face_value in faces:
		var face: Dictionary = face_value
		area += polygon_area(face.poly as PackedVector2Array)
	return area

func summary() -> Dictionary:
	return {
		"key": key,
		"tile_ids": tile_ids.duplicate(),
		"extent_polygons": extent_polygons.size(),
		"extent_area": extent_area(),
		"authoritative_road_segments": authoritative_roads.size(),
		"decorative_streets": decorative_streets.size(),
		"boundary_splines": boundary_splines.size(),
		"water_exclusions": water_exclusions.size(),
		"water_paths": water_paths.size(),
		"water_lakes": water_lakes.size(),
		"relief_shoulders": relief_shoulders.size(),
		"relief_plateaus": relief_plateaus.size(),
		"material_relief_bands": material_relief_bands.duplicate(),
		"district_guides": district_guides.size(),
		"suburban_districts": suburban_districts.size(),
		"faces": faces.size(),
		"face_area": face_area(),
		"parcels": parcels.size(),
		"masses": masses.size(),
		"industrial_reservations": industrial_reservations.size(),
		"open_lots": open_lots.size(),
		"accommodation_sites": accommodation_sites.size(),
		"visual_shadows": visual_shadows.size(),
		"visual_roof_elements": visual_roof_elements.size(),
		"visual_roof_marks": visual_roof_marks.size(),
		"height_accents": height_accents.size(),
		"far_zoom_silhouettes": far_zoom_silhouettes.size(),
		"diagnostics": diagnostics.duplicate(true),
	}

func validate_geometry() -> PackedStringArray:
	var errors := PackedStringArray()
	if key == "":
		errors.append("plan key is empty")
	for i in extent_polygons.size():
		_validate_polygon(extent_polygons[i] as PackedVector2Array,
			"extent[%d]" % i, errors)
	for i in decorative_streets.size():
		var street: Dictionary = decorative_streets[i]
		var points: PackedVector2Array = street.get("points", PackedVector2Array())
		if points.size() < 2:
			errors.append("decorative_street[%d] has fewer than two points" % i)
	for i in faces.size():
		var face: Dictionary = faces[i]
		_validate_polygon(face.get("poly", PackedVector2Array()),
			"face[%d]" % i, errors)
	for i in industrial_reservations.size():
		var reservation: Dictionary = industrial_reservations[i]
		_validate_polygon(reservation.get("poly", PackedVector2Array()),
			"industrial_reservation[%d]" % i, errors)
	return errors

func _validate_polygon(poly: PackedVector2Array, label: String,
		errors: PackedStringArray) -> void:
	if poly.size() < 3:
		errors.append("%s has fewer than three points" % label)
		return
	if polygon_area(poly) <= 0.01:
		errors.append("%s has zero area" % label)
	if polygon_self_intersects(poly):
		errors.append("%s self-intersects" % label)

static func polygon_area(poly: PackedVector2Array) -> float:
	var twice_area := 0.0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		twice_area += a.x * b.y - b.x * a.y
	return absf(twice_area) * 0.5

static func polygon_self_intersects(poly: PackedVector2Array) -> bool:
	if poly.size() < 4:
		return false
	for i in poly.size():
		var a0 := poly[i]
		var a1 := poly[(i + 1) % poly.size()]
		for j in range(i + 1, poly.size()):
			if j == i or j == (i + 1) % poly.size():
				continue
			if i == 0 and j == poly.size() - 1:
				continue
			var b0 := poly[j]
			var b1 := poly[(j + 1) % poly.size()]
			if Geometry2D.segment_intersects_segment(a0, a1, b0, b1) != null:
				return true
	return false
