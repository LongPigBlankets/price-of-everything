extends RefCounted
## Offline reuse after a road-engineering edit. Compare actual terrain inputs,
## not just the globally changed road key. Never used by the runtime loader.
const Package := preload("res://tools/supply_chain_3d/bake_package.gd")
const Index := preload("res://scripts/supply_chain_3d/road_index.gd")
var directory := ""
var manifest := {}
var eligible := {}
var reused := 0
var configured := false
var previous_road_source := ""

func enable_layout_reuse(source: String, previous_alignment: String) -> void:
	var fingerprints: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(source.path_join("source_fingerprints.json")))
	var cache=Package.Cache
	var files: Array=[cache.SCHEMA,cache.REVISIONS.roads,Engine.get_version_info().string]
	for name in cache.SOURCES.roads:
		files.append(FileAccess.get_sha256(previous_alignment) if name=="road_alignment.gd" else cache._source_file_hash("res://scripts/supply_chain_3d/"+name))
	for name in cache.SHARED:files.append(cache._source_file_hash("res://scripts/"+name))
	previous_road_source=cache.digest(files)
	assert(previous_road_source==fingerprints.layers.roads,"Only road_alignment.gd may differ when reusing the upstream layout")
	preload("res://scripts/supply_chain_3d/board.gd").offline_layout_reuse=_reuse_frontage

func _reuse_frontage(model: Dictionary, prepared: Dictionary, rivers: Dictionary, asset_key: Callable) -> void:
	var assets=preload("res://scripts/supply_chain_3d/assets.gd")
	preload("res://scripts/supply_chain_3d/urban_sidewalks.gd").apply(model.roads,model.tiles)
	var inputs: Array=[]
	for s in model.standing:
		inputs.append([s.iid,s.kind,s.tile,s.pos,s.side,s.get("yaw",0.0),s.get("footprint",[]),s.get("harbour",{}),s.get("decor_family",""),s.get("decor_asset",""),s.get("max_relief",12.0),assets.dimensions(str(asset_key.call(s)))])
	var values: Array=[previous_road_source,Package.Cache.source_key("terrain"),model.roads,inputs,rivers,
		preload("res://scripts/supply_chain_3d/civic_layout.gd").catalog_signature(),model.get("trial_rail_segments",[]),model.get("depots",[]),model.get("stations",[])]
	var previous := Package.Cache.digest(values)
	values[0]=Package.Cache.source_key("roads")
	var current := Package.Cache.digest(values)
	var variants: Dictionary=prepared.get_or_add("frontages",{})
	if variants.has(current): return
	assert(variants.has(previous),"No exact upstream frontage memo to reuse")
	variants[current]=variants[previous].duplicate(true)
	variants.erase(previous)
	print("[LAYOUT REUSE] exact upstream frontage memo, tiles=",model.tiles.size())

func configure(source: String, builder: RefCounted, model: Dictionary) -> void:
	assert(not previous_road_source.is_empty(),"Verify the previous alignment source before reusing terrain")
	directory=source
	manifest=JSON.parse_string(FileAccess.get_file_as_string(source.path_join("manifest.json")))
	var fingerprints: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(source.path_join("source_fingerprints.json")))
	var current := Package.Cache.source_fingerprints()
	assert(fingerprints.layers.roads==previous_road_source,"The reuse package must match the verified previous generator")
	assert(int(fingerprints.schema)==int(current.schema) and fingerprints.engine==current.engine)
	for layer in current.revisions:
		assert(int(fingerprints.revisions.get(layer,-1))==int(current.revisions[layer]),"Changed generator revision: "+layer)
	for layer in current.layers:
		assert(layer=="roads" or fingerprints.layers[layer]==current.layers[layer],"Terrain reuse is limited to road engineering changes")
	var snapshot := _read(manifest.world_snapshot_key)
	var transport := _read(manifest.transport_key)
	var scenery := _read(manifest.scenery_key)
	assert(snapshot.model.tiles==builder.tiles and snapshot.pits==builder.pits and snapshot.rivers==builder.rivers)
	for field in ["depots","stations"]:
		assert(snapshot.model.get(field,[])==model.get(field,[]),"Changed formation: "+field)
	assert(transport.urban.get("solved",false) and builder.rail_urban.solved,"Terrain reuse requires resolved rail elevations")
	# These are all the rail inputs consumed by cut_height/track_profile.
	for field in ["tracks","track_buckets"]:
		if transport.urban.get(field)!=builder.rail_urban.get(field):
			print("[TERRAIN REUSE] rail cutting changed; conservatively rebuild all terrain")
			configured=true
			return
	var old_grade: Array=transport.grade.segments
	var new_grade: Array=builder.road_grade.segments
	var old_index := Index.segments(old_grade,40)
	var new_index := Index.segments(new_grade,40)
	for tid in builder.tiles:
		if not manifest.tiles.has(tid): continue
		var area := Rect2(builder.tiles[tid].center-Package.Paint.EXTENT*.5,Package.Paint.EXTENT).grow(40)
		eligible[tid]=_grade_inputs(old_grade,old_index,area)==_grade_inputs(new_grade,new_index,area) \
			and scenery.shadows.get(tid,[])==builder.static_shadows.get(tid,[]) \
			and scenery.get("urban_plazas",{}).get("tiles",{}).get(tid,[])==builder.urban_plazas.tiles.get(tid,[])
	print("[TERRAIN REUSE] unchanged tiles=",eligible.values().count(true),"/",builder.tiles.size())
	configured=true

static func _grade_inputs(segments: Array, index: Dictionary, area: Rect2) -> Array:
	var inputs: Array=[]
	var ids: Array=Index.query(index,area)
	ids.sort()
	for id in ids:
		var rec: Dictionary=segments[id]
		if not area.intersects(Index.bounds(rec.a,rec.b,float(rec.half)+8.0),true): continue
		# Deliberately exclude IDs/edge indices: insertions elsewhere shift them.
		inputs.append([rec.a,rec.b,rec.ha,rec.hb,rec.half,rec.bridge,rec.earthwork,rec.cut])
	return inputs

func read_tile(tid: String, tier: String) -> Dictionary:
	if not eligible.get(tid,false): return {}
	var data := _read(manifest.tiles[tid][tier])
	if not data.is_empty(): reused+=1
	return data

func _read(key: String) -> Dictionary:
	var record := Package.file_record(directory,key)
	assert(record.sha256==manifest.resources[key].sha256 and int(record.bytes)==int(manifest.resources[key].bytes),"Changed reuse source: "+key)
	return Package.persisted_data(directory.path_join(key+".res"),key)
