extends "res://tests/test_base.gd"
const FEATURE := "supply_chain_3d"
const Queries := preload("res://scripts/supply_chain_3d/layout_queries.gd")

class CacheProbe extends RefCounted:
	var writes := 0
	func write(_key: String, _data: Dictionary) -> void:writes+=1

func _test_route_cache_retains_prepared_depot_connections() -> void:
	var queries := Queries.new()
	var cache := CacheProbe.new()
	var prepared := {"key":"prepared-route", "proposal":{"b":PackedVector2Array([Vector2.ZERO,Vector2(40,30)])}}
	var curves := {"prepared":{"roads":[{"a":Vector2.ZERO,"b":Vector2(4,2)}]}}
	var port := {"key":"moved-port","plan":{"entry":Vector2(26,57),"frame":Transform3D.IDENTITY}}
	queries.data={"costs":{},"shores":{},"paths":{},"relief":Queries.Landscape._relief_cache.duplicate(true),
		"riverside_fields":{"key":"field","polygon":PackedVector2Array([Vector2.ZERO,Vector2(1,1),Vector2(2,0)])},"authored_network":{},"frontages":{},"district_blocks":{},"street_curves":curves,"port_approach":port,"depot_roads":prepared.duplicate(true)}
	queries._cost_suffix="|depot-route-test";queries._shore_suffix="|depot-route-test"
	queries._previous_paths=Queries.Model.Streets._paths
	Queries.Model.Streets._paths={}
	queries.finish(cache)
	_check(queries.data.get("depot_roads",{})==prepared,"Route cache: the final layout snapshot retains the prepared depot roads")
	_check(queries.data.street_curves==curves and queries.data.port_approach==port,"Route cache: rounded roads and the port pose survive the final snapshot")
	_check(queries.data.riverside_fields.key=="field", "Route cache: the prepared riverside field survives the final snapshot")
	_check(cache.writes==0,"Route cache: an unchanged bundled layout does not trigger a runtime write")
	queries._prepared_keys=Queries.prepared_signature(queries.data)
	queries.data.frontages["new-layout"]={"placements":{}}
	queries._previous_paths=Queries.Model.Streets._paths;Queries.Model.Streets._paths={}
	queries.finish(cache)
	_check(cache.writes==1,"Route cache: a newly prepared shared frontage variant is saved even when geography is unchanged")
	queries._previous_paths=Queries.Model.Streets._paths;Queries.Model.Streets._paths={}
	queries.finish(cache)
	_check(cache.writes==1,"Route cache: saving a new variant does not cause repeated unchanged writes")
