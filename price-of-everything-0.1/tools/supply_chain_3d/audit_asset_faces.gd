extends Node
## Read-only mesh export for independent overlap triage; never changes assets.
const Assets := preload("res://scripts/supply_chain_3d/assets.gd")
func _ready() -> void:
	var destination := "res://../outputs/supply-chain-3d/continent-rollout/asset-faces.json"
	Assets.key_for("house",1)
	var result := {}
	for key in Assets._manifest:
		if str(key).begins_with("tree_") or str(key).begins_with("pylon_"):continue
		var mesh := Assets.mesh_for(key)
		if mesh==null:continue
		var faces: Array=[]
		for p in mesh.get_faces():faces.append([p.x,p.y,p.z])
		result[key]={"height":Assets.dimensions(key).y,"faces":faces}
	DirAccess.make_dir_recursive_absolute(destination.get_base_dir())
	FileAccess.open(destination,FileAccess.WRITE).store_string(JSON.stringify(result))
	print("[AUDIT ASSETS] ",result.size()," meshes exported to ",destination)
	get_tree().quit()
