extends Node
## Convert a staged production package; no world generation or runtime encoding.
const Cache := preload("res://scripts/supply_chain_3d/bake_cache.gd")
const Package := preload("res://tools/supply_chain_3d/bake_package.gd")
const Encoding := preload("res://scripts/supply_chain_3d/terrain_texture.gd")

class EncodeJob extends RefCounted:
	var key: String
	var tid: String
	var data: Dictionary
	var before: Dictionary
	var image: Image
	var eligible: bool
	var task: int
	var result := {}
	func run() -> void:
		result=Encoding.encode_image(image,eligible)
		image=null

func _ready() -> void:
	var directory := ""; var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--package-output="): directory=arg.trim_prefix("--package-output=")
		if arg.begins_with("--only-tiles="): only=arg.trim_prefix("--only-tiles=")
	assert(not directory.is_empty(), "Specify a staged --package-output directory")
	var result := await migrate(directory, self, only.split(",",false))
	print("[TERRAIN TEXTURES] ",JSON.stringify(result))
	get_tree().quit()

static func fingerprint() -> String:
	return Cache.digest([Encoding.VERSION,FileAccess.get_sha256("res://scripts/supply_chain_3d/terrain_texture.gd")])

static func save_manifest(path: String, manifest: Dictionary) -> void:
	FileAccess.open(path+".tmp",FileAccess.WRITE).store_string(JSON.stringify(manifest,"\t")+"\n")
	assert(DirAccess.rename_absolute(path+".tmp",path)==OK)

static func migrate(directory: String, host: Node, only := PackedStringArray()) -> Dictionary:
	var path := directory.path_join("manifest.json")
	var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	var eligibility := Encoding.package_eligibility(manifest.tiles.keys())
	var tiles_by_key := {}
	for tid in manifest.tiles:
		for tier in ["medium","near"]: tiles_by_key[manifest.tiles[tid][tier]]=tid
	var writer := Cache.new(); writer.enabled=true; writer.directory=directory; writer.defer_trim=true
	var report := {"changed":0,"before":0,"after":0,"reduced":0,"eligible":0,"records":[]}
	var start := Time.get_ticks_msec()
	var jobs: Array[EncodeJob]=[]
	for key in manifest.resources:
		if not (key.begins_with("tile-") or key.begins_with("continent-")): continue
		var tid: String=tiles_by_key.get(key,"")
		if not only.is_empty() and not tid in only: continue
		var data := Package.persisted_data(directory.path_join(key+".res"),key)
		if not data.get("texture") is Texture2D: continue
		if data.get("terrain_texture",{}).get("version",0)==Encoding.VERSION:
			# Recover a completed atomic resource write after an interrupted manifest checkpoint.
			manifest.resources[key]=Package.file_record(directory,key)
			continue
		var before := Package.file_record(directory,key)
		assert(before.sha256==manifest.resources[key].sha256)
		var job := EncodeJob.new()
		job.key=key;job.tid=tid;job.data=data;job.before=before
		job.image=data.texture.get_image();job.eligible=eligibility.get(tid,false)
		job.task=WorkerThreadPool.add_task(job.run)
		jobs.append(job)
		if jobs.size()==4:
			await _finish_jobs(jobs,writer,manifest,report,path,host,start)
			jobs.clear()
	await _finish_jobs(jobs,writer,manifest,report,path,host,start)
	if only.is_empty():
		manifest.terrain_texture_version=Encoding.VERSION
		manifest.terrain_texture_fingerprint=fingerprint()
	save_manifest(path,manifest)
	report.elapsed_ms=Time.get_ticks_msec()-start
	FileAccess.open(directory.path_join("terrain_texture_report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	return {"changed":report.changed,"before":report.before,"after":report.after,"reduced":report.reduced,"eligible":report.eligible,"elapsed_ms":report.elapsed_ms}

static func _finish_jobs(jobs: Array[EncodeJob], writer: RefCounted, manifest: Dictionary, report: Dictionary, path: String, host: Node, start: int) -> void:
	for job in jobs:
		while not WorkerThreadPool.is_task_completed(job.task): await host.get_tree().process_frame
		WorkerThreadPool.wait_for_task_completion(job.task)
		assert(job.result.has("image"),"Terrain encoding failed: "+job.key)
		job.data.texture=ImageTexture.create_from_image(job.result.image)
		job.data.terrain_texture=job.result.terrain_texture
		job.data.terrain_texture.source_disk_bytes=job.before.bytes
		writer.write(job.key,job.data)
		var after := Package.file_record(writer.directory,job.key)
		assert(after.sha256!=job.before.sha256)
		manifest.resources[job.key]=after
		report.changed+=1;report.before+=int(job.before.bytes);report.after+=int(after.bytes)
		report.reduced+=int(job.data.terrain_texture.reduced);report.eligible+=int(job.eligible)
		var record: Dictionary=job.data.terrain_texture.duplicate()
		record.tile=job.tid;record.key=job.key;record.before=job.before.bytes;record.after=after.bytes
		report.records.append(record)
		if report.changed%20==0:
			print("[TERRAIN TEXTURE] ",report.changed," reduced=",report.reduced," bytes=",report.after," elapsed_ms=",Time.get_ticks_msec()-start)
			save_manifest(path,manifest)
		await host.get_tree().process_frame
