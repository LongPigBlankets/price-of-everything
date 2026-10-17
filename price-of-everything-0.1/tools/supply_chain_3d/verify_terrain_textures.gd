extends Node
## Verify a representation-only migration against its original package.
const Package := preload("res://tools/supply_chain_3d/bake_package.gd")

func _ready() -> void:
	var before := Package.Cache.BUNDLED; var after := ""; var output := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--before-package="):before=arg.trim_prefix("--before-package=")
		if arg.begins_with("--package-output="):after=arg.trim_prefix("--package-output=")
		if arg.begins_with("--report-output="):output=arg.trim_prefix("--report-output=")
	assert(not after.is_empty() and not output.is_empty())
	var old: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(before.path_join("manifest.json")))
	var current: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(after.path_join("manifest.json")))
	assert(old.tiles==current.tiles and old.resources.size()==current.resources.size())
	for key in old.resources: assert(current.resources.has(key))
	assert(FileAccess.get_sha256(before.path_join("source_fingerprints.json"))==FileAccess.get_sha256(after.path_join("source_fingerprints.json")))
	var indexed := {}
	for tid in current.tiles:
		for tier in ["medium","near"]:indexed[current.tiles[tid][tier]]={"tile":tid,"tier":tier,"type":Catalog.tile_type(tid)}
	var report := {"before":0,"after":0,"changed":0,"unchanged":0,"groups":{},"records":[]}
	for key in current.resources:
		report.before+=int(old.resources[key].bytes);report.after+=int(current.resources[key].bytes)
		var group: String=indexed.get(key,{}).get("tier",key.get_slice("-",0))
		if not report.groups.has(group):report.groups[group]={"before":0,"after":0,"source_texture_bytes":0,"texture_bytes":0,"scales":{}}
		var totals: Dictionary=report.groups[group]
		totals.before+=int(old.resources[key].bytes);totals.after+=int(current.resources[key].bytes)
		if old.resources[key].sha256==current.resources[key].sha256:
			report.unchanged+=1;continue
		var first := Package.persisted_data(before.path_join(key+".res"),key)
		var second := Package.persisted_data(after.path_join(key+".res"),key)
		assert(second.has("terrain_texture"),"Unexpected changed resource: "+key)
		var info: Dictionary=second.terrain_texture
		assert(info.version==Package.TextureEncoding.VERSION)
		assert(info.source_size==Vector2i(first.texture.get_width(),first.texture.get_height()))
		assert(info.size==Package.TextureEncoding.target_size(info.source_size,info.scale),"Texture extent changed unexpectedly: "+key)
		var pixels: Image=second.texture.get_image()
		assert(pixels.get_format()==Image.FORMAT_BPTC_RGBA and pixels.has_mipmaps())
		assert(pixels.get_data_size()==info.bytes and pixels.get_size()==info.size)
		totals.source_texture_bytes+=int(info.source_bytes);totals.texture_bytes+=int(info.bytes)
		totals.scales[str(info.scale)]=int(totals.scales.get(str(info.scale),0))+1
		var record := info.duplicate()
		record.merge(indexed.get(key,{"tile":"","tier":"auxiliary","type":""}))
		record.key=key;record.before=old.resources[key].bytes;record.after=current.resources[key].bytes
		report.records.append(record)
		first.erase("texture");second.erase("texture");second.erase("terrain_texture")
		assert(Package.same_payload(first,second),"Non-texture payload changed: "+key)
		report.changed+=1
		if report.changed%50==0:await get_tree().process_frame
	report.ok=true
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("[TERRAIN VERIFICATION] changed=",report.changed," unchanged=",report.unchanged," before=",report.before," after=",report.after)
	get_tree().quit()
