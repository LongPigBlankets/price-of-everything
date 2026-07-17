extends RefCounted
## Resolves where the game keeps its persistent data (saves, profile, logs).
##
## Portable-by-default: in a real (exported) build the data sits NEXT TO the executable;
## when run from the editor it goes in the project folder. Layout under the base folder:
##   <base>/savegames/   save slots, autosaves, profile.json
##   <base>/logs/        session logs + run/turn telemetry
## so an exported build reads:  Carbon and Capital (Experimental)/ > savegames, logs, exe
##
## Falls back to the OS user-data dir (the classic user:// location) when the preferred
## folder isn't writable — e.g. macOS app-translocation of a quarantined bundle, or a
## read-only /Applications install — so saving never silently fails.
##
## Reference via `const AppPaths := preload("res://scripts/app_paths.gd")`, NOT the bare
## class name (a freshly-added class_name may be missing from the headless class cache).

static var _base := ""


## Base folder that holds savegames/ and logs/. Resolved once, then cached.
static func base_dir() -> String:
	if _base == "":
		var pref := _preferred_base()
		_base = pref if _writable(pref) else OS.get_user_data_dir()
	return _base


static func saves_dir() -> String:
	return _ensure(base_dir().path_join("savegames"))


static func logs_dir() -> String:
	return _ensure(base_dir().path_join("logs"))


## Test hook: drop the cached base so the next call re-resolves.
static func reset_cache() -> void:
	_base = ""


static func _preferred_base() -> String:
	# Exported builds carry no "editor" feature; the editor and headless tooling both do.
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://").trim_suffix("/")
	var exe := OS.get_executable_path()
	if OS.has_feature("macos"):
		return _macos_bundle_parent(exe)
	return exe.get_base_dir()  # Windows / Linux: the folder containing the executable


## <parent>/Foo.app/Contents/MacOS/<bin>  ->  <parent> (the folder holding the .app).
static func _macos_bundle_parent(exe: String) -> String:
	return exe.get_base_dir().get_base_dir().get_base_dir().get_base_dir()


static func _ensure(dir: String) -> String:
	DirAccess.make_dir_recursive_absolute(dir)
	return dir


static func _writable(dir: String) -> bool:
	DirAccess.make_dir_recursive_absolute(dir)
	if not DirAccess.dir_exists_absolute(dir):
		return false
	var probe := dir.path_join(".write_test")
	var f := FileAccess.open(probe, FileAccess.WRITE)
	if f == null:
		return false
	f.close()
	DirAccess.remove_absolute(probe)
	return true
