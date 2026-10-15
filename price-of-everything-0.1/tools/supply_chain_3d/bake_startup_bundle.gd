extends Node
## Repackage existing validated startup data. No terrain or artwork generation.
const Package := preload("res://tools/supply_chain_3d/bake_package.gd")
const Bundle := preload("res://scripts/supply_chain_3d/startup_bundle.gd")

func _ready() -> void:
	await get_tree().process_frame
	var directory: String = Package.Cache.BUNDLED
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("manifest.json")))
	var installed := install(directory,manifest)
	var report := await Package.validate(directory,self)
	report.startup=installed
	print("[STARTUP BUNDLE] ",JSON.stringify(report))
	get_tree().quit(0 if report.ok else 1)

static func install(directory: String, manifest: Dictionary) -> Dictionary:
	var writer := Package.Cache.new()
	writer.enabled=true; writer.defer_trim=true; writer.directory=directory
	var index := {"version":Bundle.VERSION,"keys":{},"parts":{}}
	var auxiliary: Array = manifest.get("auxiliary_keys",[])
	var bytes := 0
	# Three bounded native files keep the package portable to source hosts with
	# individual-file size limits. Each layout is one fast binary value block.
	for pair in [["snapshot","world_snapshot_key"],["transport","transport_key"],["scenery","scenery_key"]]:
		var source_key: String = manifest[pair[1]]
		index.keys[pair[1]]=source_key
		var values := Package.persisted_data(directory.path_join(source_key+".res"),source_key)
		assert(not values.is_empty(), "Missing source bake for startup bundle")
		var payload := Bundle.pack(values)
		assert(Package.same_payload(values,Bundle.unpack(payload)), "Startup encoding must preserve every value and resource")
		var key: String = "startup-"+pair[0]+"-"+Package.Cache.digest([Bundle.VERSION,source_key])
		writer.write(key,payload)
		index.parts[pair[0]]=key
		if not auxiliary.has(key): auxiliary.append(key)
		manifest.resources[key]=Package.file_record(directory,key)
		bytes+=int(manifest.resources[key].bytes)
	var key := "world-startup-"+Package.Cache.digest([Bundle.VERSION,index.keys])
	writer.write(key,index)
	# Retire only the previous startup package's records, never unrelated bakes.
	for previous in manifest.get("startup_keys",[]):
		if previous!=key and not index.parts.values().has(previous):
			auxiliary.erase(previous); manifest.resources.erase(previous)
	if not auxiliary.has(key): auxiliary.append(key)
	manifest.world_startup_key=key
	manifest.startup_keys=index.parts.values()+[key]
	manifest.resources[key]=Package.file_record(directory,key)
	manifest.auxiliary_keys=auxiliary
	FileAccess.open(directory.path_join("manifest.json"),FileAccess.WRITE).store_string(JSON.stringify(manifest,"\t")+"\n")
	return {"key":key,"bytes":bytes+int(manifest.resources[key].bytes),"resources":index.parts.size()+1}
