extends Node
## Offline, lossless RSCC block repacking. The native Godot reader remains the
## only runtime decoder. Format: core/io/file_access_compressed.cpp (Godot 4.6).
const VERSION := 1
const MAGIC := 0x43435352
const BLOCKS := [262144, 1048576]

func _ready() -> void:
	var directory := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--package-output="): directory=arg.trim_prefix("--package-output=")
	if directory.is_empty():
		push_error("Specify a staged --package-output directory");get_tree().quit(1);return
	var report := await migrate(directory,self)
	print("[BAKE STORAGE] ",JSON.stringify(report))
	get_tree().quit(0 if report.ok else 1)

static func decode(bytes: PackedByteArray) -> PackedByteArray:
	if bytes.size()<20 or bytes.decode_u32(0)!=MAGIC or bytes.decode_u32(4)!=FileAccess.COMPRESSION_ZSTD: return PackedByteArray()
	var block := bytes.decode_u32(8)
	var total := bytes.decode_u32(12)
	if block==0 or total==0: return PackedByteArray()
	var count := total / block + 1
	var pos := 16+4*count
	if pos>bytes.size()-4: return PackedByteArray()
	var result := PackedByteArray()
	for i in count:
		var size := bytes.decode_u32(16+4*i)
		if size>bytes.size()-4-pos: return PackedByteArray()
		var expected := mini(block,total-i*block)
		# Godot stores an empty final block when total is a multiple of block.
		if expected>0:
			var decoded := bytes.slice(pos,pos+size).decompress(expected,FileAccess.COMPRESSION_ZSTD)
			if decoded.size()!=expected: return PackedByteArray()
			result.append_array(decoded)
		pos+=size
	if pos!=bytes.size()-4 or bytes.decode_u32(pos)!=MAGIC: return PackedByteArray()
	return result

static func encode(raw: PackedByteArray, block: int) -> PackedByteArray:
	if raw.is_empty() or block<=0: return PackedByteArray()
	var count := raw.size()/block+1
	var result := PackedByteArray();result.resize(16+4*count)
	result.encode_u32(0,MAGIC);result.encode_u32(4,FileAccess.COMPRESSION_ZSTD)
	result.encode_u32(8,block);result.encode_u32(12,raw.size())
	for i in count:
		var packed := raw.slice(i*block,mini((i+1)*block,raw.size())).compress(FileAccess.COMPRESSION_ZSTD)
		result.encode_u32(16+4*i,packed.size());result.append_array(packed)
	result.append_array("RSCC".to_ascii_buffer())
	return result

static func migrate(directory: String, host: Node, only := PackedStringArray()) -> Dictionary:
	var path := directory.path_join("manifest.json")
	var report := {"ok":true,"changed":0,"before":0,"after":0,"verified_payloads":0,"records":[],"errors":[]}
	var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or not parsed.get("resources") is Dictionary:
		report.ok=false;report.errors.append("Missing or invalid package manifest");return report
	var manifest: Dictionary=parsed
	# Preserve the deliberately uncompressed variant used by profiling tools.
	if manifest.get("storage","")=="raw":
		report.skipped="Package is not configured for Zstd storage"
		return report
	if manifest.get("storage","")!="zstd":
		report.ok=false;report.errors.append("Unsupported package storage");return report
	var started := Time.get_ticks_msec()
	var previous: Dictionary=manifest.get("storage_blocks",{})
	var records: Dictionary=previous.get("resources",{}) if int(previous.get("version",0))==VERSION else {}
	for key in records.keys():
		if not manifest.resources.has(key):records.erase(key)
	for key in manifest.resources:
		if not only.is_empty() and not key in only: continue
		var file: String=directory.path_join(key+".res")
		var original := FileAccess.get_file_as_bytes(file)
		var sha := FileAccess.get_sha256(file)
		if sha!=manifest.resources[key].sha256 or original.size()!=int(manifest.resources[key].bytes):
			report.errors.append("Source checksum mismatch: "+key);break
		if records.get(key,{}).get("sha256","")==sha: continue
		var raw := decode(original)
		if raw.is_empty():
			report.errors.append("Expected a valid native Zstd bake: "+key);break
		var best := original
		for block in BLOCKS:
			var candidate := encode(raw,block)
			if not candidate.is_empty() and candidate.size()<best.size(): best=candidate
		if decode(best)!=raw:
			report.errors.append("Lossless round-trip failed: "+key);break
		report.verified_payloads+=1
		report.before+=original.size();report.after+=best.size()
		if best!=original:
			var temporary := file+".tmp"
			var output := FileAccess.open(temporary,FileAccess.WRITE)
			if output==null:
				report.errors.append("Cannot write: "+temporary);break
			output.store_buffer(best);output.close()
			if FileAccess.get_file_as_bytes(temporary)!=best or DirAccess.rename_absolute(temporary,file)!=OK:
				report.errors.append("Cannot install verified resource: "+key);break
			report.changed+=1
		var record := {"bytes":best.size(),"sha256":FileAccess.get_sha256(file)}
		manifest.resources[key]=record
		records[key]={"sha256":record.sha256,"block_bytes":best.decode_u32(8)}
		report.records.append({"key":key,"before":original.size(),"after":best.size(),"block_bytes":best.decode_u32(8)})
		# Persist each completed resource; a checksum mismatch stops the migration.
		manifest.storage_blocks={"version":VERSION,"resources":records}
		if not save_json(path,manifest):
			report.errors.append("Cannot checkpoint manifest");break
		if report.verified_payloads%100==0: print("[REPACK] ",report.verified_payloads," saved_bytes=",report.before-report.after)
		await host.get_tree().process_frame
	report.ok=report.errors.is_empty()
	report.elapsed_ms=Time.get_ticks_msec()-started
	save_json(directory.path_join("storage_report.json"),report)
	return report

static func save_json(path: String, value: Dictionary) -> bool:
	var file := FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file==null: return false
	file.store_string(JSON.stringify(value,"\t")+"\n");file.close()
	return DirAccess.rename_absolute(path+".tmp",path)==OK
