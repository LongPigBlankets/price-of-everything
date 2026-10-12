extends Node
const Cache := preload("res://scripts/supply_chain_3d/bake_cache.gd")
class Ground extends RefCounted:
	var tiles := {}
	var bands := []
	var lakes := []
	var rivers := {}
	func height(p: Vector2) -> float: return 34+p.y*0.2
class Builder extends "res://scripts/supply_chain_3d/world_builder.gd":
	func open_water(_p: Vector2) -> bool: return false
	func railway_level(_p: Vector2) -> float: return 2
func make_builder(folder: String) -> Builder:
	var b := Builder.new()
	b.ground=Ground.new()
	b.tiles={"test":{"center":Vector2.ZERO,"type":"urban"}}
	b.bake_cache.enabled=true
	b.bake_cache.directory=folder
	b.bake_cache.bundled_directory="/private/tmp/nonexistent-transport-bundle"
	return b
func _ready() -> void:
	TelemetryState.enabled=false; SaveLoad.autosave_enabled=false
	var folder := "/private/tmp/transport-cache-check-"+str(Time.get_ticks_usec())
	var model := {"tiles":{"test":{"center":Vector2.ZERO}},"roads":[{"a":Vector2(-120,0),"b":Vector2(120,0),"tile":"test","level":2,"widths":[6.0,5.7,5.4,4.7]}],"lines":[{"mode":"rails","level":2,"pts":[{"p":Vector2(0,-120)},{"p":Vector2(0,120)}]}]}
	var cold := make_builder(folder)
	cold.prepare_transport(model.duplicate(true))
	assert(not cold.transport_profile.cache_hit and cold.bake_cache.writes==1)
	var warm := make_builder(folder)
	warm.prepare_transport(model.duplicate(true))
	assert(warm.transport_profile.cache_hit and warm.bake_cache.writes==0)
	assert(Cache.digest(cold.TransportBake.packed(cold))==Cache.digest(warm.TransportBake.packed(warm)))
	for x in range(-100,100,5):
		for y in range(-20,20,5):
			var p := Vector2(x,y)
			assert(is_equal_approx(cold.surface_height(p),warm.surface_height(p)))
			assert(is_equal_approx(cold.road_grade.height_at(p,0),warm.road_grade.height_at(p,0)))
	var changed := model.duplicate(true)
	changed.roads[0].b+=Vector2(0,20)
	assert(warm.TransportBake.key_for(warm,changed)!=cold.transport_key)
	warm.ground.bands.append({"height":9})
	assert(warm.TransportBake.key_for(warm,model)!=cold.transport_key)
	assert(not warm.TransportBake.restore(warm,{"version":1}))
	print("[transport cache] disk restore, surface/grade parity, road/terrain invalidation passed")
	get_tree().quit()
