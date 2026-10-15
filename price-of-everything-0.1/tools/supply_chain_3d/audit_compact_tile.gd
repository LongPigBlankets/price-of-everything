extends Node
## Compare stored triangle/vertex counts, without generating any geometry.
const Cache := preload("res://scripts/supply_chain_3d/bake_cache.gd")
func _counts(mesh: ArrayMesh) -> Dictionary:
	var vertices:=0;var triangles:=0
	for surface in mesh.get_surface_count():
		vertices+=mesh.surface_get_array_len(surface)
		var indices:=mesh.surface_get_array_index_len(surface)
		triangles+=(indices if indices>0 else mesh.surface_get_array_len(surface))/3
	return {"vertices":vertices,"triangles":triangles}
func _ready() -> void:
	var before:="";var after:=Cache.BUNDLED;var tid:="tile_4_9"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--before-package="):before=arg.trim_prefix("--before-package=")
		if arg.begins_with("--after-package="):after=arg.trim_prefix("--after-package=")
		if arg.begins_with("--tile="):tid=arg.trim_prefix("--tile=")
	var report:={"tile":tid}
	for label in ["before","after"]:
		var directory:=before if label=="before" else after
		assert(not directory.is_empty())
		var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("manifest.json")))
		var counts:={}
		for tier in ["base","medium","near"]:
			var key:String=manifest.tiles[tid][tier]
			var saved:=load(directory.path_join(key+".res")) as Cache.Data
			var data:=saved.values()
			counts[tier]=_counts(data.mesh)
			if tier=="base":
				counts.roads=_counts(data.road_drawing.mesh if data.has("road_drawing") else data.roads_mesh)
				counts.road_texture_bytes=int(data.get("road_drawing",{}).get("texture_bytes",0))
		report[label]=counts
	var output:="res://../outputs/supply-chain-3d/surface-compaction/geometry.json"
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("[COMPACT TILE] ",JSON.stringify(report))
	get_tree().quit()
