extends Node
## Backfill Stoneshore's loose-fringe and North/Stoneshore road-edge planting treatments
## into procedural areas already present in the active authored document. New
## `enable procedural <region>` imports do both themselves; this tool migrates older maps.
##
##   <godot> --path . res://tools/map_editor/apply_region_tree_pattern.tscn --quit-after 60000

const ShotHarness := preload("res://tools/shot_harness.gd")

const MAX_WAIT_FRAMES := 1200


func _ready() -> void:
	ShotHarness.prepare_window(get_window())
	ShotHarness.arm_watchdog(self, 60.0)
	var packed := load("res://tools/map_editor/map_editor.tscn") as PackedScene
	if packed == null:
		push_error("[TREE-PATTERN] could not load the map editor")
		get_tree().quit(1)
		return
	var editor := packed.instantiate()
	add_child(editor)
	var waited := 0
	while waited < MAX_WAIT_FRAMES and not bool(editor.call("is_ready_to_edit")):
		await get_tree().process_frame
		waited += 1
	if not bool(editor.call("is_ready_to_edit")):
		push_error("[TREE-PATTERN] editor did not become ready")
		get_tree().quit(1)
		return
	var result := str(editor.call("apply_procedural_tree_pattern", "all"))
	print("[TREE-PATTERN] %s" % result)
	var roadside_result := str(editor.call("apply_procedural_roadside_trees"))
	print("[TREE-PATTERN] %s" % roadside_result)
	if OS.get_environment("POE_TREE_DRY_RUN") == "1":
		print("[TREE-PATTERN] dry run — active document not saved")
		get_tree().quit(0)
		return
	editor.call("run_action", "save")
	await get_tree().process_frame
	var document: RefCounted = editor.call("document")
	if document != null and bool(document.call("is_dirty")):
		push_error("[TREE-PATTERN] the active document remained dirty after save")
		get_tree().quit(1)
		return
	print("[TREE-PATTERN] saved the active authored document")
	get_tree().quit(0)
