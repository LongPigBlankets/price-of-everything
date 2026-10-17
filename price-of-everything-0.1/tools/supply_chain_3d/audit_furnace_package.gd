extends Node
func _ready() -> void:
	var cache := preload("res://scripts/supply_chain_3d/bake_cache.gd").new()
	cache.enabled = true
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(cache.BUNDLED+"/manifest.json"))
	var snapshot: Dictionary = cache.read(manifest.world_snapshot_key)
	var found := []
	for s in snapshot.get("model",{}).get("standing",[]):
		if s.get("internal_name","") == "furnace":
			found.append({"id":s.get("iid"),"level":s.get("level"),"tile":s.get("tile"),"side":s.get("side")})
	var levels := {}
	for entry in found: levels[str(entry.level)] = int(levels.get(str(entry.level),0))+1
	print("[FURNACE PACKAGE INSTANCES] ",JSON.stringify({"count":found.size(),"levels":levels}))
	get_tree().quit()
