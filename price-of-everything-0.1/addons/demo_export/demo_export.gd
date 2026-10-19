@tool
extends EditorExportPlugin
## For a preset with the `demo` feature tag, replaces each file DemoDataFilter knows with its
## filtered text. The game reads these files with FileAccess, so the replacement is the file.

const DemoDataFilter := preload("res://addons/demo_export/demo_data_filter.gd")
const FEATURE := "demo"


## Written into the staged copy by tools/demo_build/build_demo.py, which also strips the
## `# demo:strip` regions. A demo export without it would ship the full scripts.
const STAGE_MARKER := "res://demo_stage.txt"

var _unstaged := false


func _get_name() -> String:
	return "DemoExport"


func _export_begin(features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
	_unstaged = features.has(FEATURE) and not FileAccess.file_exists(STAGE_MARKER)
	if _unstaged:
		push_error("DemoExport: export the demo with `python3 tools/demo_build/build_demo.py export`. "
			+ "This project is not the staged demo source, so nothing is packed.")


func _export_file(path: String, _type: String, features: PackedStringArray) -> void:
	if _unstaged:
		skip()
		return
	if not features.has(FEATURE) or not DemoDataFilter.FILTERED.has(path):
		return
	var source := FileAccess.get_file_as_string(path)
	var filtered := DemoDataFilter.filter(path, source)
	if filtered == "":
		push_error("DemoExport: filtering %s produced nothing" % path)
		return
	skip()
	add_file(path, filtered.to_utf8_buffer(), false)
	print("DemoExport: %s %d -> %d bytes" % [path, source.length(), filtered.length()])
