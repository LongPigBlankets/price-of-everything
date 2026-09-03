extends Node
## Windowed QA for the Stoneshore-derived procedural planting. Each region is enabled only in
## the editor's working copy, captured, then removed again; the active document is never saved.
##
##   <godot> --path . res://tools/map_editor/tree_pattern_preview.tscn --quit-after 90000

const ShotHarness := preload("res://tools/shot_harness.gd")
const RegionImport := preload("res://scripts/map_editor/map_editor_region_import.gd")

const MAX_WAIT_FRAMES := 1200
const PAINT_FRAMES := 20
const CAPTURE_ZOOM := 0.5


func _ready() -> void:
	ShotHarness.prepare_window(get_window())
	ShotHarness.arm_watchdog(self, 90.0)
	get_window().size = Vector2i(1280, 800)
	var packed := load("res://tools/map_editor/map_editor.tscn") as PackedScene
	if packed == null:
		push_error("[TREE-PREVIEW] could not load the map editor")
		get_tree().quit(1)
		return
	var editor := packed.instantiate()
	add_child(editor)
	var waited := 0
	while waited < MAX_WAIT_FRAMES and not bool(editor.call("is_ready_to_edit")):
		await get_tree().process_frame
		waited += 1
	if not bool(editor.call("is_ready_to_edit")):
		push_error("[TREE-PREVIEW] editor did not become ready")
		get_tree().quit(1)
		return

	var regions: Array = RegionImport.REGIONS.duplicate()
	var requested := OS.get_environment("POE_TREE_PREVIEW_REGION")
	if RegionImport.is_region(requested):
		regions = [requested]
	for region in regions:
		var result := str(editor.call("procedural_region_command", "enable", str(region)))
		print("[TREE-PREVIEW] %s" % result)
		if result.begins_with("procedural %s:" % region):
			editor.call("focus_tile", str(RegionImport.REGION_ANCHORS[region]), CAPTURE_ZOOM)
			for _i in PAINT_FRAMES:
				await get_tree().process_frame
			RenderingServer.force_draw()
			var path := "/tmp/poe_tree_pattern_%s.png" % region
			get_viewport().get_texture().get_image().save_png(path)
			print("[TREE-PREVIEW] wrote %s" % path)
			editor.call("procedural_region_command", "disable", str(region))
			await get_tree().process_frame
	get_tree().quit(0)
