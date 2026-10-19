@tool
extends EditorPlugin
## Registers DemoExport, which writes filtered data files into any export carrying the
## `demo` feature tag. Regular exports pass through untouched.

const DemoExport := preload("res://addons/demo_export/demo_export.gd")

var _export: EditorExportPlugin


func _enter_tree() -> void:
	_export = DemoExport.new()
	add_export_plugin(_export)


func _exit_tree() -> void:
	remove_export_plugin(_export)
	_export = null
