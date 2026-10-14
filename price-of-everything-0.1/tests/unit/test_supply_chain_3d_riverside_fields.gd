extends "res://tests/test_base.gd"
const FEATURE := "supply_chain_3d"
const Riverside := preload("res://scripts/supply_chain_3d/riverside_fields.gd")
const Clip := preload("res://scripts/supply_chain_3d/sea_fringe.gd")

func _test_riverside_eastward_field_stops_at_curved_bank() -> void:
	var original := PackedVector2Array([Vector2(-30,-50),Vector2(15,-50),Vector2(15,50),Vector2(-30,50)])
	var land := PackedVector2Array([Vector2(-100,-100),Vector2(160,-100),Vector2(160,100),Vector2(-100,100)])
	var river := PackedVector2Array([Vector2(50,-120),Vector2(35,-30),Vector2(70,30),Vector2(60,120)])
	var masks: Array = Geometry2D.offset_polyline(river, 16, Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND)
	var field := Riverside.extend(original,Vector2.ZERO,[land],masks)
	_check(Clip.area(field)>Clip.area(original)*1.3,"Riverside farm: the existing parcel expands into the eastern wedge")
	_check(Geometry2D.is_point_in_polygon(Vector2(38,35),field),"Riverside farm: rows can follow the river's outward bend")
	_check(not Geometry2D.is_point_in_polygon(Vector2(105,0),field),"Riverside farm: disconnected land across the river is discarded")
	var intrusion := 0.0
	for mask in masks:
		for part in Geometry2D.intersect_polygons(field,mask): intrusion+=Clip.area(part)
	_check(intrusion<.01,"Riverside farm: the complete field polygon clears water and its bank margin")
	var retained := 0.0
	for part in Geometry2D.intersect_polygons(field,original):retained+=Clip.area(part)
	_check(absf(retained-Clip.area(original))<.01,"Riverside farm: the existing barn parcel is retained")

func _test_riverside_coast_clips_field_without_replacing_the_barn_anchor() -> void:
	var original := PackedVector2Array([Vector2(-30,-40),Vector2(10,-40),Vector2(10,40),Vector2(-30,40)])
	var land := PackedVector2Array([Vector2(-100,-100),Vector2(200,-100),Vector2(200,-10),Vector2(10,50),Vector2(-100,50)])
	var field := Riverside.extend(original,Vector2.ZERO,[land],[])
	_check(Geometry2D.is_point_in_polygon(Vector2.ZERO,field),"Riverside farm: the field stays attached to its original barn")
	_check(not Geometry2D.is_point_in_polygon(Vector2(90,40),field),"Riverside farm: the extension respects the estuary coastline")
	_check(Array(field).any(func(p: Vector2):return p.x>80),"Riverside farm: dry space above the estuary is filled")
