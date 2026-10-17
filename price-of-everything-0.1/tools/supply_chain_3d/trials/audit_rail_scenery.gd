extends Node
const Cache := preload("res://scripts/supply_chain_3d/bake_cache.gd")
func _ready() -> void:
	var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(Cache.BUNDLED+"/manifest.json"))
	var old:Dictionary=(load(Cache.BUNDLED+"/"+manifest.scenery_key+".res") as Cache.Data).values()
	var fresh:Dictionary=(load("/private/tmp/stream-ready-bake-cache/scenery-34583e092d2b6722ccee70c139670085c227aaab2f813e9347843cc605f4fbf1.res") as Cache.Data).values()
	var report:={"trees_changed":[],"shadows_changed":[]}
	for tid in old.trees:
		if Cache.digest(old.trees[tid])!=Cache.digest(fresh.trees[tid]):report.trees_changed.append(tid)
		if Cache.digest(old.shadows[tid])!=Cache.digest(fresh.shadows[tid]):report.shadows_changed.append(tid)
	var old_transport:Dictionary=(load(Cache.BUNDLED+"/"+manifest.transport_key+".res") as Cache.Data).values()
	var new_transport:Dictionary=(load("/private/tmp/stream-ready-bake-cache/transport-112448de0e1bacdff1d4295f1fe5660238a454533efdb38fbf5722f6f9785b24.res") as Cache.Data).values()
	report.transport_equal={}
	for field in old_transport:
		report.transport_equal[field]=Cache.digest(old_transport[field])==Cache.digest(new_transport[field])
	report.urban_equal={}
	for field in old_transport.urban:
		report.urban_equal[field]=Cache.digest(old_transport.urban[field])==Cache.digest(new_transport.urban[field])
	report.grade_equal={}
	for field in old_transport.grade:
		report.grade_equal[field]=Cache.digest(old_transport.grade[field])==Cache.digest(new_transport.grade[field])
	report.track_changes=[]
	report.road_changes=[]
	report.junction_degrees={}
	for junction in old_transport.rail_plan.junctions:
		report.junction_degrees[junction.arms]=int(report.junction_degrees.get(junction.arms,0))+1
	for pair in [["track_changes",old_transport.urban.tracks,new_transport.urban.tracks],["road_changes",old_transport.grade.segments,new_transport.grade.segments]]:
		for i in mini(pair[1].size(),pair[2].size()):
			if pair[1][i]!=pair[2][i] and report[pair[0]].size()<5:
				var diff:={}
				for field in pair[1][i]:
					if pair[1][i][field]!=pair[2][i].get(field):diff[field]=[str(pair[1][i][field]),str(pair[2][i].get(field))]
				report[pair[0]].append(diff)
	FileAccess.open("/private/tmp/rail-scenery-changes.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("[RAIL SCENERY] ",JSON.stringify(report))
	get_tree().quit()
