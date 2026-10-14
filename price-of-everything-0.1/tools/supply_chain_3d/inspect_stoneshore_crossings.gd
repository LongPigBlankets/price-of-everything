extends Node
## Read-only export of the installed scoped transport package for engineering review.
const ROOT := "res://assets/supply_chain_3d/stoneshore_trial_bakes"
func _ready() -> void:
	TelemetryState.enabled=false; SaveLoad.autosave_enabled=false
	var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(ROOT+"/manifest.json"))
	assert(manifest.tile_count==5)
	var data: Dictionary=load(ROOT+"/"+manifest.transport_key+".res").data
	var rail_layouts: Array=[]
	for key in manifest.rail_layout_keys:
		var layout: Dictionary=load(ROOT+"/"+key+".res").data
		var lines: Array=[]
		for line in layout.lines:
			if line.a in ["tile_4_9","tile_4_10","tile_5_9","tile_5_10","tile_6_9"] or line.b in ["tile_4_9","tile_4_10","tile_5_9","tile_5_10","tile_6_9"]: lines.append(line)
		rail_layouts.append({"lines":lines,"anchor":layout.anchors.tile_5_10,"depots":layout.depots})
	if "--engineer-crossings" in OS.get_cmdline_user_args():
		var grade := preload("res://scripts/supply_chain_3d/road_grade.gd").new()
		for field in data.grade: grade.set(field,data.grade[field])
		for node in grade.nodes.values(): node.h=node.base;node.core=false
		grade.bridges=[];grade.refresh()
		var urban := preload("res://scripts/supply_chain_3d/rail_urban.gd").new()
		for field in data.urban:urban.set(field,data.urban[field])
		preload("res://scripts/supply_chain_3d/rail_crossings.gd").build(grade,data.rail_plan,urban,urban.depots)
		data.grade.crossings=grade.crossings;data.grade.bridges=grade.bridges
	var result := {"roads":data.roads,"grade":data.grade,"urban":data.urban,"rail_plan":data.rail_plan,"layouts":rail_layouts}
	var out := "/private/tmp/stoneshore-crossings-before.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--crossings-output="): out=arg.trim_prefix("--crossings-output=")
	FileAccess.open(out,FileAccess.WRITE).store_string(JSON.stringify(serial(result)))
	print("[CROSSINGS INPUT] ",out)
	get_tree().quit()
func serial(value: Variant) -> Variant:
	if value is Vector2 or value is Vector2i: return [value.x,value.y]
	if value is Vector3: return [value.x,value.y,value.z]
	if value is Array or value is PackedVector2Array:
		var out: Array=[]
		for item in value: out.append(serial(item))
		return out
	if value is Dictionary:
		var out := {}
		for key in value: out[str(key)]=serial(value[key])
		return out
	return value
