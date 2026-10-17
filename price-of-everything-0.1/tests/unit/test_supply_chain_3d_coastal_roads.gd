extends "res://tests/test_base.gd"
const FEATURE := "supply_chain_3d"
const Coast := preload("res://scripts/supply_chain_3d/coastal_roads.gd")
func _test_coastal_roads_reject_sea_and_preserve_inland_bridges() -> void:
	var centers := {"t":Vector2.ZERO}
	var left := PackedVector2Array([Vector2(-200,-80),Vector2(-20,-80),Vector2(-20,80),Vector2(-200,80)])
	var right := PackedVector2Array([Vector2(20,-80),Vector2(200,-80),Vector2(200,80),Vector2(20,80)])
	var path := {"id":"shore","class":"minor","layer":0,"points":PackedVector2Array([Vector2(-100,0),Vector2(100,0)])}
	var clipped := Coast.clip([path],centers,{"t":[left,right]})
	_check(clipped.paths.size()==2 and absf(clipped.removed[0].sea_length-40)<.01,"Coastal roads: a sea inlet splits the road into two dry portions")
	_check(clipped.paths[0].points[-1].is_equal_approx(Vector2(-20,0)) and clipped.paths[1].points[0].is_equal_approx(Vector2(20,0)),"Coastal roads: no segment connects across the sea gap")
	_check(clipped.paths[0].id!=clipped.paths[1].id and path.points.size()==2,"Coastal roads: fragments have unique sources without mutating the authored path")
	var whole := PackedVector2Array([Vector2(-200,-80),Vector2(200,-80),Vector2(200,80),Vector2(-200,80)])
	path.bridges=[[0,0]]
	var inland := Coast.clip([path],centers,{"t":[whole]})
	_check(inland.paths==[path] and inland.removed.is_empty(),"Coastal roads: inland river/lake bridge annotations and source geometry are unchanged")
	_check(Coast.clip([path],centers,{"t":[]}).paths.is_empty(),"Coastal roads: entirely offshore roads are omitted")
