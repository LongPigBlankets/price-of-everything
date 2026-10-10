extends RefCounted
## Content-addressed disk cache. Bundled bakes are read-only; new maps/edits go to user://.
const Data := preload("res://scripts/supply_chain_3d/bake_data.gd")
const SCHEMA := 2
const BUNDLED := "res://assets/supply_chain_3d/bakes"
## Bump the relevant revision when world_builder changes generated data. Runtime
## visibility/loading edits must not invalidate unrelated terrain artwork.
const REVISIONS := {"terrain": 2, "roads": 1, "scenery": 1, "continent": 2, "detail": 1}
const SOURCES := {
	"terrain": ["terrain_paint.gd", "water_art.gd", "geometry.gd", "detail.gd", "shadow_art.gd", "relief.gd"],
	"roads": ["road_surface.gd", "geometry.gd"],
	"scenery": ["tree_layout.gd", "shadow_art.gd"],
	"continent": ["geometry.gd"],
	"detail": ["local_detail.gd", "geometry.gd"],
}
const SHARED := ["empire_board.gd", "empire_board_ground.gd", "empire_board_relief.gd", "empire_board_model.gd"]
const MAX_BYTES := 2 * 1024 * 1024 * 1024
static var _source_keys: Dictionary = {}
var directory := "user://supply_chain_3d_bakes"
var bundled_directory := BUNDLED
var enabled := DisplayServer.get_name() != "headless"
var hits := 0
var misses := 0
var writes := 0
var defer_trim := false
## Keep prepared geometry but store it losslessly compressed. Raw remains available
## for controlled profiling; both encodings load through the native resource reader.
var compress := true

static func is_raw(path: String) -> bool:
	return storage_format(path) == "raw"

static func storage_format(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() < 8: return "invalid"
	var header := file.get_buffer(4).get_string_from_ascii()
	if header == "RSRC": return "raw"
	if header == "RSCC" and file.get_32() == FileAccess.COMPRESSION_ZSTD: return "zstd"
	return "unsupported"

static func digest(value: Variant) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(var_to_bytes(_ordered(value)))
	return context.finish().hex_encode()

static func _ordered(value: Variant) -> Variant:
	if value is Dictionary:
		var keys: Array = value.keys()
		keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
		var pairs: Array = []
		for key in keys: pairs.append([key, _ordered(value[key])])
		return ["dictionary", pairs]
	if value is Array:
		var values: Array = []
		for item in value: values.append(_ordered(item))
		return values
	return value

static func source_fingerprints() -> Dictionary:
	var layers := {}
	for layer in SOURCES: layers[layer] = source_key(layer)
	return {"schema": SCHEMA, "engine": Engine.get_version_info().string, "revisions": REVISIONS, "layers": layers}

static func fingerprints_match(saved: Dictionary, expected: Dictionary) -> bool:
	if int(saved.get("schema", -1)) != int(expected.schema) or saved.get("engine") != expected.engine: return false
	for name in expected.revisions:
		if int(saved.get("revisions", {}).get(name, -1)) != int(expected.revisions[name]): return false
	return saved.get("layers", {}) == expected.layers

static func _packaged_fingerprint(layer: String) -> String:
	# Export remaps .gd to compiled .gdc. Preserve the editor's content keys rather
	# than hashing nonexistent source files and missing every shipped bake.
	if FileAccess.file_exists("res://scripts/supply_chain_3d/" + SOURCES[layer][0]): return ""
	var path := BUNDLED.path_join("source_fingerprints.json")
	if not FileAccess.file_exists(path): return ""
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not saved is Dictionary or int(saved.get("schema", -1)) != SCHEMA or saved.get("engine") != Engine.get_version_info().string: return ""
	for name in REVISIONS:
		if int(saved.get("revisions", {}).get(name, -1)) != REVISIONS[name]: return ""
	return str(saved.get("layers", {}).get(layer, ""))

static func _source_file_hash(path: String) -> String:
	if FileAccess.file_exists(path): return FileAccess.get_sha256(path)
	# A mismatched/missing package deliberately gets a new key, still including
	# the compiled source, so runtime-generated maps cannot reuse stale art.
	var remap := ConfigFile.new()
	if remap.load(path + ".remap") == OK:
		return FileAccess.get_sha256(str(remap.get_value("remap", "path", "")))
	return "missing:" + path

static func source_key(layer: String = "terrain") -> String:
	if not _source_keys.has(layer):
		var packaged := _packaged_fingerprint(layer)
		if not packaged.is_empty():
			_source_keys[layer] = packaged
			return packaged
		var files: Array = [SCHEMA, REVISIONS[layer], Engine.get_version_info().string]
		for name in SOURCES[layer]: files.append(_source_file_hash("res://scripts/supply_chain_3d/" + name))
		for name in SHARED: files.append(_source_file_hash("res://scripts/" + name))
		_source_keys[layer] = digest(files)
	return _source_keys[layer]

func read(key: String) -> Dictionary:
	if not enabled: return {}
	for root in [bundled_directory, directory]:
		var path: String = root.path_join(key + ".res")
		if not FileAccess.file_exists(path): continue
		# Content hashes are immutable; reuse any live resource and its subresources.
		var bake := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE) as Data
		if bake != null and bake.schema == SCHEMA and bake.key == key and not bake.data.is_empty():
			hits += 1
			return bake.data
	misses += 1
	return {}

func write(key: String, data: Dictionary) -> void:
	if not enabled: return
	if DirAccess.make_dir_recursive_absolute(directory) != OK: return
	var bake := Data.new()
	bake.schema = SCHEMA
	bake.key = key
	bake.data = data
	var path := directory.path_join(key + ".res")
	var temporary := directory.path_join(key + ".tmp.res")
	# Generated meshes/textures are internal subresources already. Bundling the
	# GDScript class itself breaks its external script reference in binary saves.
	if ResourceSaver.save(bake, temporary, ResourceSaver.FLAG_COMPRESS if compress else 0) != OK: return
	if DirAccess.rename_absolute(temporary, path) != OK: return
	writes += 1
	# A continent writes hundreds of chunks; its caller trims once after the
	# root manifest is durable, avoiding repeated directory scans mid-bake.
	if not defer_trim and writes % 8 == 0: trim()

func trim() -> void:
	# Bound runtime storage; packaged bakes are never removed. Old content hashes
	# remain useful for savegames until space is needed by newer bakes.
	var files: Array = []
	var total := 0
	for name in DirAccess.get_files_at(directory):
		if not name.ends_with(".res"): continue
		var path := directory.path_join(name)
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null: continue
		var bytes := file.get_length()
		file.close()
		total += bytes
		files.append({"path": path, "bytes": bytes, "time": FileAccess.get_modified_time(path)})
	files.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.time < b.time)
	for item in files:
		if total <= MAX_BYTES: break
		if DirAccess.remove_absolute(item.path) == OK: total -= int(item.bytes)
