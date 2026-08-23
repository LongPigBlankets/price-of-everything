extends Node
## Parse EVERY .gd in the project and report the ones that fail.
##
## This exists because `--headless --editor --quit` does NOT catch a parse error in a script
## the editor happens not to reload — it reports nothing and exits 0, which reads exactly
## like a clean check. A broken `victory_end_screen.gd` passed that check AND the whole unit
## suite (which never loads the end screen) before failing at runtime.
##
##   Godot --headless --path . res://tools/parse_check.tscn --quit-after 600
##
## Exits 1 if anything failed to parse, so it can gate a commit.
##
## Runs as a SCENE, not with --script, because GDScript resolves autoload names (DS,
## MatchState, VictoryState...) at COMPILE time. Under --script the autoloads do not exist,
## every script that touches one fails to compile, and the check reports 283 of 458 broken.
##
## The test is reload(), not `load() == null`: ResourceLoader hands back a GDScript object
## for a file with a parse error too, so a null check passes everything.

const ROOTS: Array[String] = ["res://scripts", "res://tools", "res://tests"]

## Known false positive: reload() returns an error for this one on a clean tree, with no
## message, and nothing in the file explains it. Listed rather than silently skipped, so
## the exception stays visible and can be revisited.
const KNOWN_UNRELOADABLE: Array[String] = ["res://scripts/road_realizer.gd"]


func _ready() -> void:
	var files: Array[String] = []
	for root: String in ROOTS:
		_collect(root, files)
	files.sort()
	var autoloads := _autoload_paths()
	var failed: Array[String] = []
	var skipped := 0
	for path: String in files:
		# The autoloads are live instances; reload() refuses to touch a script in use, and it
		# would report every one of them as broken. They are also the scripts LEAST in need of
		# checking — the game did not reach this line without compiling all of them.
		# ...and this file, which is the running scene's own script.
		if autoloads.has(path) or path == (get_script() as Script).resource_path:
			skipped += 1
			continue
		# Load the way the game does, then ask whether the result actually COMPILED.
		var res := ResourceLoader.load(path, "GDScript")
		if res == null or not (res is GDScript):
			failed.append(path)
			continue
		# can_instantiate() is not the test either — it is false for plenty of good scripts.
		if (res as GDScript).reload() != OK:
			if path in KNOWN_UNRELOADABLE:
				skipped += 1
				continue
			failed.append(path)
	print("[parse_check] %d scripts, %d failed (%d skipped — autoloads, self, known)" % [
		files.size(), failed.size(), skipped])
	for path: String in failed:
		print("[parse_check] FAILED  %s" % path)
	get_tree().quit(1 if not failed.is_empty() else 0)


## Every script registered as an autoload, by res:// path (the setting may name a uid://).
func _autoload_paths() -> Dictionary:
	var out: Dictionary = {}
	for prop: Dictionary in ProjectSettings.get_property_list():
		var key := str(prop.get("name", ""))
		if not key.begins_with("autoload/"):
			continue
		var value := str(ProjectSettings.get_setting(key, ""))
		if value.begins_with("*"):
			value = value.substr(1)
		if value.begins_with("uid://"):
			var id := ResourceUID.text_to_id(value)
			if ResourceUID.has_id(id):
				value = ResourceUID.get_id_path(id)
		if value.ends_with(".gd"):
			out[value] = true
	return out

func _collect(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.begins_with("."):
			name = dir.get_next()
			continue
		var full := dir_path.path_join(name)
		if dir.current_is_dir():
			_collect(full, out)
		elif name.ends_with(".gd"):
			out.append(full)
		name = dir.get_next()
	dir.list_dir_end()
