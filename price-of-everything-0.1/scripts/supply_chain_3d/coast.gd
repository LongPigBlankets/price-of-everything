extends RefCounted
## The regular map paints sea band 5 as reclaimed/beach land. The old board
## omitted it and treated the narrower height-band footprint as the coastline.
const Legacy := preload("res://scripts/empire_board.gd")
const Ground := preload("res://scripts/empire_board_ground.gd")
const DisplayGround := preload("res://scripts/supply_chain_3d/ground.gd")
const HalfRelief := preload("res://scripts/supply_chain_3d/half_relief.gd")
const Heights := preload("res://scripts/empire_board_relief.gd")
const Model := preload("res://scripts/empire_board_model.gd")
const Water := preload("res://scripts/supply_chain_3d/water_geography.gd")
static var _land: Array = []
static var _reliefs := {}
static var _source_reliefs := {}
static var _grounds := {}
static var _terrain_id := 0

static func relief_of(tid: String, center: Vector2) -> Dictionary:
	if _reliefs.has(tid): return _reliefs[tid]
	var rel := source_relief_of(tid, center).duplicate(true)
	var water := Water.for_tile(tid)
	var land: Array = []
	for p in water.land: land.append({"b": 0, "p": p, "beach": true})
	for e in rel.land:
		if e.get("beach", false): continue
		for mask in water.land:
			for piece in Legacy._clip(e.p, mask): land.append({"b": e.b, "p": piece})
	rel.land = land
	rel.lakes = water.lakes
	rel.shore = water.shore
	rel.water_ink = water.ink
	_reliefs[tid] = rel
	return rel

static func source_relief_of(tid: String, center: Vector2) -> Dictionary:
	if _source_reliefs.has(tid): return _source_reliefs[tid]
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
	land.append_array(HalfRelief.land(rel.land))
	rel.land = land
	_source_reliefs[tid] = rel
	return rel

static func ground_for(terrain: Node, rivers: Dictionary, plates: Dictionary, intermediate: bool = false) -> RefCounted:
	if _terrain_id != terrain.get_instance_id():
		_grounds.clear()
		_terrain_id = terrain.get_instance_id()
	if _grounds.has(intermediate): return _grounds[intermediate]
	# Separate cache and samplers: never modify the regular/legacy map's ground.
	# Depot seeding also calls this function. Its default keeps the original
	# sampler; only the 3D board opts into visual intermediate contours.
	var source := Ground.for_map(terrain, rivers, plates, Callable(Legacy, "_relief_of"))
	var ground: RefCounted = DisplayGround.new() if intermediate else Ground.new()
	ground.tiles = source.tiles.duplicate(true)
	ground.bands = HillBaked.polys()
	if intermediate: ground.bands.append_array(HalfRelief.polys())
	ground.lakes = Water.lakes().map(func(lake): return lake.p) if intermediate else source.lakes
	ground.rivers = source.rivers
	ground.flows = source.flows
	ground.level_at = Callable(Heights, "map_level")
	ground.relief = Callable(_self_script(), "relief_of" if intermediate else "source_relief_of")
	ground.may_be_wet = func(_center): return true if intermediate else Heights.hex_has_water(_center)
	ground.setup()
	if intermediate:
		ground.water_geography = true
		for i in Water.lakes().size(): ground._lake_level[i] = Water.lakes()[i].level
	_grounds[intermediate] = ground
	return ground

static func _self_script() -> GDScript:
	return load("res://scripts/supply_chain_3d/coast.gd")
