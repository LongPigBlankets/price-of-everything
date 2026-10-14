extends RefCounted
## Portable precomputed road grades, switchbacks, tunnels and rail topology.
## Lookup precedes engineering: loading a valid landscape must not solve it again.
const Cache := preload("res://scripts/supply_chain_3d/bake_cache.gd")
const VERSION := 3
const ALIGNMENT := ["portals","switchbacks","constrained","grade_eased"]
const GRADE := ["segments","buckets","earth_buckets","nodes","bridges","junctions","crossings"]
const URBAN := ["solved","components","distance_field","centers","depots","tile_index","busy","buckets","tracks","track_buckets"]

static func key_for(builder: RefCounted, model: Dictionary) -> String:
	var plots: Array=[]
	for s in model.get("standing",[]):
		plots.append([s.get("pos"),s.get("pad",s.get("side",16)),s.get("footprints",[s.get("footprint",[])])])
	var geography := {}
	for tid in builder.tiles: geography[tid]=[builder.tiles[tid].center,builder.tiles[tid].type]
	return "transport-"+Cache.digest([VERSION,Cache.source_key("transport"),Cache.source_key("roads"),Cache.source_key("scenery"),
		Cache.source_key("terrain"),builder.ground.get("tiles"),builder.ground.get("bands"),builder.ground.get("lakes"),builder.ground.get("rivers"),
		builder.rivers,builder.pits,geography,plots,model.get("roads",[]),model.get("lines",[]),model.get("depots",[]),model.get("stations",[]),
		model.get("authored_region",{}).get("paths",[]),model.get("authored_region",{}).get("tiles",{})])

static func _fields(object: RefCounted, names: Array) -> Dictionary:
	var result := {}
	for name in names: result[name]=object.get(name)
	return result

static func packed(builder: RefCounted) -> Dictionary:
	return {"version":VERSION,"roads":builder.roads,"alignment":_fields(builder.road_alignment,ALIGNMENT),
		"grade":_fields(builder.road_grade,GRADE),"urban":_fields(builder.rail_urban,URBAN),
		"rail_plan":builder.rail_plan,"authored":builder.authored_profile.packed()}

static func restore(builder: RefCounted, data: Dictionary) -> bool:
	if data.get("version",-1)!=VERSION: return false
	for field in ["roads","alignment","grade","urban","rail_plan","authored"]:
		if not data.has(field): return false
	for item in [[builder.road_alignment,ALIGNMENT,"alignment"],[builder.road_grade,GRADE,"grade"],[builder.rail_urban,URBAN,"urban"]]:
		for name in item[1]:
			if not data[item[2]].has(name): return false
	builder.roads=data.roads
	for item in [[builder.road_alignment,ALIGNMENT,"alignment"],[builder.road_grade,GRADE,"grade"],[builder.rail_urban,URBAN,"urban"]]:
		for name in item[1]: item[0].set(name,data[item[2]][name])
	builder.rail_plan=data.rail_plan
	builder.authored_profile.restore(data.authored)
	return true
