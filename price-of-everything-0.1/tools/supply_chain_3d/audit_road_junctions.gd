extends SceneTree
## Headless read-only topology audit of the packaged supply-chain layout.
const Index := preload("res://scripts/supply_chain_3d/road_index.gd")
const Cache := preload("res://scripts/supply_chain_3d/bake_cache.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var output := "/private/tmp/road-junction-audit.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Cache.BUNDLED.path_join("manifest.json")))
	var resource: Resource = load(Cache.BUNDLED.path_join(str(manifest.layout_key) + ".res"))
	var network: Dictionary = resource.data.authored_network
	var paths: Array = network.paths
	var report := {"authored": Index.audit(paths), "paths": paths.size()}
	report.trimmed_stubs = network.get("trimmed_stubs", [])
	if "--verify-cleanup" in OS.get_cmdline_user_args():
		var repeated := paths.duplicate(true)
		report.repeat_passes = []
		for i in 3:
			var trimmed := Index.trim_stubs(repeated)
			report.repeat_passes.append({"removed": trimmed, "remaining": Index.audit(repeated).stubs})
		report.stub_paths = paths.filter(func(p: Dictionary) -> bool:
			return report.authored.stubs.any(func(s: Dictionary) -> bool: return s.source == p.id))
	var largest := {}
	for frontage in resource.data.frontages.values():
		if not frontage.metrics.has("trimmed_stubs"): continue
		if frontage.paths.size() >= largest.get("paths", []).size(): largest = frontage
	if largest.is_empty():
		for frontage in resource.data.frontages.values():
			if frontage.roads.size() >= largest.get("roads", []).size(): largest = frontage
	# New frontages persist the complete cleaned paths. Older packages stored
	# only access paths, so they remain useful as the before-cleanup reference.
	var combined: Array = largest.get("paths", [])
	if not combined.any(func(p: Dictionary) -> bool: return not str(p.id).begins_with("access:")):
		combined = paths + combined
	report.with_access = Index.audit(combined)
	FileAccess.open(output, FileAccess.WRITE).store_string(JSON.stringify(report, "\t") + "\n")
	print("[ROAD AUDIT] ", output, " paths=", paths.size(), " near endpoints=", report.authored.near_endpoints_within_3u,
		" stubs=", report.authored.stubs_under_3u, " including access: near=", report.with_access.near_endpoints_within_3u,
		" stubs=", report.with_access.stubs_under_3u)
	quit()
