@tool
extends EditorExportPlugin
## For a preset with the `demo` feature tag, replaces each file DemoDataFilter knows with its
## filtered text. The game reads these files with FileAccess, so the replacement is the file.

const DemoDataFilter := preload("res://addons/demo_export/demo_data_filter.gd")
const FEATURE := "demo"


func _get_name() -> String:
	return "DemoExport"


func _export_file(path: String, _type: String, features: PackedStringArray) -> void:
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
