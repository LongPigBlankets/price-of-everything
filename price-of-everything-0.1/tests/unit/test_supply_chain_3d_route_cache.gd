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
	queries.data={"costs":{},"shores":{},"paths":{},"relief":Queries.Landscape._relief_cache.duplicate(true),
		"authored_network":{},"frontages":{},"district_blocks":{},"depot_roads":prepared.duplicate(true)}
	queries._cost_suffix="|depot-route-test";queries._shore_suffix="|depot-route-test"
	queries._previous_paths=Queries.Model.Streets._paths
	Queries.Model.Streets._paths={}
	queries.finish(cache)
	_check(queries.data.get("depot_roads",{})==prepared,"Route cache: the final layout snapshot retains the prepared depot roads")
	_check(cache.writes==0,"Route cache: an unchanged bundled layout does not trigger a runtime write")
