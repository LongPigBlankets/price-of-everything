extends "res://scripts/supply_chain_3d/bake_cache.gd"
var probe: Dictionary = {}
var compressed_bytes := 0
func read(key: String) -> Dictionary:
	var start := Time.get_ticks_usec()
	var result := super.read(key)
	var ms := (Time.get_ticks_usec() - start) / 1000.0
	var group := key.get_slice("-", 0)
	(probe.get_or_add(group, []) as Array).append(ms)
	for root in [BUNDLED, directory]:
		var path: String = root.path_join(key + ".res")
		if FileAccess.file_exists(path):
			var file := FileAccess.open(path, FileAccess.READ)
			compressed_bytes += file.get_length()
			break
	return result
