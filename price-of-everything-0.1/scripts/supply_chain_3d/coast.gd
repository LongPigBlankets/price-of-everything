extends RefCounted
## The regular map paints sea band 5 as reclaimed/beach land. The old board
## omitted it and treated the narrower height-band footprint as the coastline.
const Legacy := preload("res://scripts/empire_board.gd")
const Ground := preload("res://scripts/empire_board_ground.gd")
const Heights := preload("res://scripts/empire_board_relief.gd")
const Model := preload("res://scripts/empire_board_model.gd")
static var _land: Array = []
static var _reliefs := {}
static var _ground: RefCounted
static var _terrain_id := 0

static func relief_of(tid: String, center: Vector2) -> Dictionary:
	if _reliefs.has(tid): return _reliefs[tid]
	if _land.is_empty():
		for rec in HillBaked.sea():
			if int(rec.b) == 5: _land.append({"p": rec.p, "box": Legacy._box_of(rec.p)})
	var rel := Legacy._relief_of(tid, center).duplicate(true)
	rel.erase("shore") # the legacy cache may already contain the narrower shoreline
	var land: Array = []
	var hex := Model.hex_points(center)
	var box := Legacy._box_of(hex)
	for rec in _land:
		if not box.intersects(rec.box): continue
		for polygon in Legacy._clip(rec.p, hex): land.append({"b": 0, "p": polygon, "beach": true})
	land.append_array(rel.land)
	rel.land = land
	_reliefs[tid] = rel
	return rel

static func ground_for(terrain: Node, rivers: Dictionary, plates: Dictionary) -> RefCounted:
	if _ground != null and _terrain_id == terrain.get_instance_id(): return _ground
	# Separate cache and samplers: never modify the regular/legacy map's ground.
	var source := Ground.for_map(terrain, rivers, plates, Callable(Legacy, "_relief_of"))
	var ground := Ground.new()
	ground.tiles = source.tiles.duplicate(true)
	ground.bands = HillBaked.polys()
	ground.lakes = source.lakes
	ground.rivers = source.rivers
	ground.flows = source.flows
	ground.level_at = Callable(Heights, "map_level")
	ground.relief = Callable(_self_script(), "relief_of")
	ground.may_be_wet = Callable(Heights, "hex_has_water")
	ground.setup()
	_ground = ground
	_terrain_id = terrain.get_instance_id()
	return ground

static func _self_script() -> GDScript:
	return load("res://scripts/supply_chain_3d/coast.gd")
