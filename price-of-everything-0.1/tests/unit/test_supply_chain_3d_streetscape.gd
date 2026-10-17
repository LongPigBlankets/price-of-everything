extends "res://tests/test_base.gd"
const FEATURE := "supply_chain_3d"
const Curves := preload("res://scripts/supply_chain_3d/street_curves.gd")
const Plazas := preload("res://scripts/supply_chain_3d/urban_plazas.gd")
const Green := preload("res://scripts/supply_chain_3d/stoneshore_greenery.gd")
func _test_streetscape_curves_and_flared_joints() -> void:
	var points := Curves.rounded_path(PackedVector2Array([Vector2(-80,0),Vector2.ZERO,Vector2(0,80)]),20)
	_check(points[0]==Vector2(-80,0) and points[-1]==Vector2(0,80),"Street curves: road connections remain fixed")
	var maximum := 0.0
	for i in range(1,points.size()-1):maximum=maxf(maximum,absf((points[i]-points[i-1]).angle_to(points[i+1]-points[i])))
	_check(maximum<deg_to_rad(15) and not points.has(Vector2.ZERO),"Street curves: a right-angle bend becomes a tangent-continuous curve")
	_check(Curves.flare(Vector2.ZERO,Vector2.RIGHT,Vector2.LEFT,5,5).is_empty(),"Street joints: straight connections do not acquire a round bulge")
	var flare := Curves.flare(Vector2.ZERO,Vector2.RIGHT,Vector2.DOWN,5,5,4)
	_check(Geometry2D.is_point_in_polygon(Vector2(5.5,5.5),flare) and not Geometry2D.is_point_in_polygon(Vector2(9,9),flare),"Street joints: the gentle fillet fills the inside corner without a broad bulb")
func _test_streetscape_plaza_uses_building_type_not_generic_house_kind() -> void:
	_check(Plazas.eligible({"kind":"house","decor_family":"civic_office"},"civic_office_lvl1"),"Plazas: decorative offices qualify despite the shared house rendering category")
	_check(not Plazas.eligible({"kind":"house"},"house_lvl1") and not Plazas.eligible({"kind":"house","decor_family":"civic_semi"},"civic_semi_lvl1"),"Plazas: terrace and semidetached homes keep their gardens")
	_check(Plazas.eligible({"kind":"house"},"house_lvl3"),"Plazas: apartment blocks receive concrete forecourts")
	_check(not Plazas.eligible({"kind":"house","decor_family":"civic_pond"},"civic_pond_lvl1"),"Plazas: ponds and parks retain their ground")
func _test_streetscape_beach_and_canopy_union() -> void:
	var all := PackedVector2Array([Vector2.ZERO,Vector2(100,0),Vector2(100,100),Vector2(0,100)])
	var grass := PackedVector2Array([Vector2(30,0),Vector2(100,0),Vector2(100,100),Vector2(30,100)])
	var rel := {"land":[{"p":all,"beach":true},{"p":grass,"b":1}]}
	_check(Green.beach(Vector2(10,20),rel) and not Green.beach(Vector2(50,20),rel),"Greenery: beach limits apply only to exposed sand, not the base land mask under grass")
	var green := Green.new()
	for y in range(-10,11):
		for x in range(-10,11):green.land[Vector2i(x,y)]=true
	var tree := {"kind":"small","height":22.0,"pos":Vector2.ZERO}
	var first := green._mark(tree);var second := green._mark(tree)
	_check(first>0 and second==0,"Greenery: overlapping canopies are counted only once")

func _test_streetscape_port_road_matches_asset_deck_in_both_directions() -> void:
	var approach := preload("res://scripts/supply_chain_3d/port_approach.gd")
	var plan := {"points":PackedVector2Array([Vector2.ZERO,Vector2(50,0),Vector2(50,30)]),"start_height":34.0,"deck":36.0}
	var forward := {"source":approach.SOURCE,"a":Vector2(50,10),"b":Vector2(50,30)}
	var reverse := {"source":approach.SOURCE,"b":Vector2(50,10),"a":Vector2(50,30)}
	approach.grade([forward,reverse],plan)
	_check(absf(forward.road_hb+1.09-36.0)<.001,"Port approach: asphalt height matches the existing asset road")
	_check(is_equal_approx(forward.road_ha,reverse.road_hb) and is_equal_approx(forward.road_hb,reverse.road_ha),"Port approach: engineering direction cannot reverse the ramp")
