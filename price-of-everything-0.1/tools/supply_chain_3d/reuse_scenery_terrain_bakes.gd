extends "res://tools/supply_chain_3d/reuse_terrain_bakes.gd"
## Offline-only reuse for scenery edits. A changed shared key need not repaint
## unrelated tiles. Heights may differ by at most 0.001u after recomputation.
const EPS := 0.001

static func equivalent(a: Variant, b: Variant) -> bool:
	if typeof(a)!=typeof(b): return false
	if a is float: return absf(a-b)<=EPS
	if a is Vector2: return a.distance_to(b)<=EPS
	if a is Vector3: return a.distance_to(b)<=EPS
	if a is Dictionary:
		if a.size()!=b.size(): return false
		for key in a:
			if not b.has(key) or not equivalent(a[key],b[key]): return false
		return true
	if a is Array:
		if a.size()!=b.size(): return false
		for i in a.size():
			if not equivalent(a[i],b[i]): return false
		return true
	return a==b

func configure(source: String, builder: RefCounted, model: Dictionary) -> void:
	directory=source
	manifest=JSON.parse_string(FileAccess.get_file_as_string(source.path_join("manifest.json")))
	var fingerprints:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(source.path_join("source_fingerprints.json")))
	var current:=Package.Cache.source_fingerprints()
	assert(fingerprints.engine==current.engine and int(fingerprints.schema)==int(current.schema))
	for layer in current.layers:
		if layer not in ["scenery","detail"]:
			assert(fingerprints.layers[layer]==current.layers[layer],"Unexpected generator change: "+layer)
	var snapshot:=_read(manifest.world_snapshot_key)
	var transport:=_read(manifest.transport_key)
	var scenery:=_read(manifest.scenery_key)
	assert(snapshot.model.tiles==builder.tiles and snapshot.pits==builder.pits and snapshot.rivers==builder.rivers)
	# Prove that geography, water, road source, lines, depots, stations and layout
	# are unchanged: substituting only the old roads must recover the old key.
	var old_map:=Package.Cache.digest([Package.Cache.source_key("terrain"),builder.ground.get("tiles"),builder.ground.get("bands"),
		builder.ground.get("lakes"),builder.ground.get("rivers"),MapStyle.band_colors(),MapStyle.sea_colors(),transport.roads,
		model.get("lines",[]),model.get("depots",[]),model.get("stations",[]),model.get("neighbourhood",{}),Package.Cache.source_key("roads")])
	assert(old_map==manifest.map_key,"Unverified map inputs: cannot reuse terrain")
	assert(equivalent(transport.alignment,Package.persisted_data(builder.bake_cache.directory.path_join(builder.transport_key+".res"),builder.transport_key).alignment),"Road alignment changed")
	# Per-tile grades and rail cuts include all fields consumed by the sampler.
	var old_grade:Array=transport.grade.segments
	var new_grade:Array=builder.road_grade.segments
	var old_index:=Index.segments(old_grade,40);var new_index:=Index.segments(new_grade,40)
	var old_tracks:Array=transport.urban.tracks;var new_tracks:Array=builder.rail_urban.tracks
	var old_rail_index:=Index.segments(old_tracks,40);var new_rail_index:=Index.segments(new_tracks,40)
	for tid in builder.tiles:
		var area:=Rect2(builder.tiles[tid].center-Package.Paint.EXTENT*.5,Package.Paint.EXTENT).grow(40)
		eligible[tid]=equivalent(_grade_inputs(old_grade,old_index,area),_grade_inputs(new_grade,new_index,area)) \
			and equivalent(_rail_inputs(old_tracks,old_rail_index,area),_rail_inputs(new_tracks,new_rail_index,area)) \
			and scenery.shadows.get(tid,[])==builder.static_shadows.get(tid,[]) \
			and scenery.get("urban_plazas",{}).get("tiles",{}).get(tid,[])==builder.urban_plazas.tiles.get(tid,[])
	configured=true
	print("[SCENERY TERRAIN REUSE] ",eligible.values().count(true),"/",builder.tiles.size())

static func _rail_inputs(tracks:Array,index:Dictionary,area:Rect2) -> Array:
	var result:=[]
	var ids:Array=Index.query(index,area);ids.sort()
	for id in ids:
		var rec:Dictionary=tracks[id]
		if not area.intersects(Index.bounds(rec.a,rec.b,32.0),true): continue
		result.append([rec.a,rec.b,rec.ha,rec.hb,rec.base_a,rec.base_b,rec.hidden_a,rec.hidden_b,rec.active])
	return result
