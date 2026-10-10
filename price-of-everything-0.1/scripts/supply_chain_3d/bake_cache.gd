extends RefCounted
## Content-addressed disk cache. Bundled bakes are read-only; new maps/edits go to user://.
const Data := preload("res://scripts/supply_chain_3d/bake_data.gd")
const SCHEMA := 1
const BUNDLED := "res://assets/supply_chain_3d/bakes"
const SOURCES := ["world_builder.gd", "terrain_paint.gd", "water_art.gd", "geometry.gd", "road_surface.gd", "detail.gd", "tree_layout.gd"]
const SHARED := ["empire_board.gd", "empire_board_ground.gd", "empire_board_relief.gd", "empire_board_model.gd"]
const MAX_BYTES := 2 * 1024 * 1024 * 1024
static var _source_key := ""
var directory := "user://supply_chain_3d_bakes"
var enabled := DisplayServer.get_name() != "headless"
var hits := 0
var misses := 0
var writes := 0

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

static func source_key() -> String:
	if _source_key == "":
		var files: Array = [SCHEMA, Engine.get_version_info().string]
		for name in SOURCES: files.append(FileAccess.get_sha256("res://scripts/supply_chain_3d/" + name))
		for name in SHARED: files.append(FileAccess.get_sha256("res://scripts/" + name))
		_source_key = digest(files)
	return _source_key

func read(key: String) -> Dictionary:
	if not enabled: return {}
	for root in [BUNDLED, directory]:
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
	if ResourceSaver.save(bake, temporary, ResourceSaver.FLAG_COMPRESS) != OK: return
	if DirAccess.rename_absolute(temporary, path) != OK: return
	writes += 1
	if writes % 8 == 0: trim()

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
