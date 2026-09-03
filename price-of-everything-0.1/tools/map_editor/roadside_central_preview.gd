extends Node
## Non-saving visual QA for the roadside migration, Capital's future import, and the exact
## `enable procedural central buildings` review layer.

const ShotHarness := preload("res://tools/shot_harness.gd")
const RegionImport := preload("res://scripts/map_editor/map_editor_region_import.gd")

const MAX_WAIT_FRAMES := 1200
const PAINT_FRAMES := 24


func _ready() -> void:
	ShotHarness.prepare_window(get_window())
	ShotHarness.arm_watchdog(self, 90.0)
	get_window().size = Vector2i(1280, 800)
	var packed := load("res://tools/map_editor/map_editor.tscn") as PackedScene
	if packed == null:
		push_error("[ROADSIDE-PREVIEW] could not load the map editor")
		get_tree().quit(1)
		return
	var editor := packed.instantiate()
	add_child(editor)
	var waited := 0
	while waited < MAX_WAIT_FRAMES and not bool(editor.call("is_ready_to_edit")):
		await get_tree().process_frame
		waited += 1
	if not bool(editor.call("is_ready_to_edit")):
		push_error("[ROADSIDE-PREVIEW] editor did not become ready")
		get_tree().quit(1)
		return

	if OS.get_environment("POE_PREVIEW_CENTRAL_ONLY") != "1":
		print("[ROADSIDE-PREVIEW] %s" % editor.call("apply_procedural_roadside_trees"))
		await _capture(editor, "tile_22_16", 0.62, "/tmp/poe_roadside_vandel.png")

		var capital_result := str(editor.call("procedural_region_command", "enable", "capital"))
		print("[ROADSIDE-PREVIEW] %s" % capital_result)
		if capital_result.begins_with("procedural capital:"):
			await _capture(editor, str(RegionImport.REGION_ANCHORS.capital), 0.5,
				"/tmp/poe_roadside_capital.png")

	var central_result := str(editor.call("procedural_central_buildings_command", "enable"))
	print("[ROADSIDE-PREVIEW] %s" % central_result)
	if central_result.begins_with("procedural central buildings:"):
		await _capture(editor, RegionImport.CENTRAL_BUILDING_FOCUS_TILE, 0.7,
			"/tmp/poe_central_buildings.png")
	get_tree().quit(0)


func _capture(editor: Node, tile_id: String, zoom: float, path: String) -> void:
	editor.call("focus_tile", tile_id, zoom)
	for _i in PAINT_FRAMES:
		await get_tree().process_frame
	RenderingServer.force_draw()
	get_viewport().get_texture().get_image().save_png(path)
	print("[ROADSIDE-PREVIEW] wrote %s" % path)
