extends Node
## Close captures of one tile in a Metal Magnate game as it starts, then with a rail line built on it, to check
## what stands on the tile and how big the infrastructure's building is.
##   AGENT_GODOT_WINDOW=1 godot --path . res://tools/tile_look_shot.tscn -- --no-telemetry
## TILE picks the tile (Greyroad, tile_9_9, by default). Writes tile_<tile>_<view>.png into $TILE_SHOT_DIR (or /tmp).
## ZOOMS, a comma list such as "1.1,2.4", adds a start capture per zoom (tile_<tile>_start_z<zoom>.png).

const ShotHarness := preload("res://tools/shot_harness.gd")

var _out := "/tmp"


func _ready() -> void:
	var dir := OS.get_environment("TILE_SHOT_DIR")
	if dir != "":
		_out = dir
	var tile := OS.get_environment("TILE")
	if tile == "":
		tile = "tile_9_9"
	DirAccess.make_dir_recursive_absolute(_out)
	ShotHarness.arm_watchdog(self, 240.0)
	ShotHarness.prepare_window(get_window(), Vector2i(1920, 1080))
	TelemetryState.enabled = false
	SaveLoad.autosave_enabled = false
	AudioServer.set_bus_mute(0, true)
	SaveLoad.prepare_new_game("res://data/starts/metal_magnate.json")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	get_tree().current_scene = main
	await _settle(200)
	MatchState.ruleset["opener_done"] = true
	Tutorial._on_overlay_skipped()
	DecisionState.enabled = false
	for layer in get_tree().root.find_children("*", "CanvasLayer", true, false):
		var sc := (layer as Node).get_script() as Script
		if sc != null and sc.resource_path.ends_with("_intro.gd"):
			layer.queue_free()
	await _settle(20)
	var cam := get_viewport().get_camera_2d()
	cam.set("edge_pan_enabled", false)
	var terrain: Node = main.get("terrain_layer")
	var coord: Vector2i = terrain.call("id_to_coord", tile)
	var cell: Vector2i = terrain.call("map_coord_for_tile_coord", coord)
	cam.zoom = Vector2.ONE * 1.1
	cam.set("_target_zoom", cam.zoom)
	cam.global_position = (terrain as Node2D).to_global(terrain.call("map_to_local", cell))
	await _wait(1.2)
	await _shot("%s_start" % tile)
	for zoom_text in OS.get_environment("ZOOMS").split(",", false):
		cam.zoom = Vector2.ONE * float(zoom_text)
		cam.set("_target_zoom", cam.zoom)
		await _wait(1.5)
		await _shot("%s_start_z%s" % [tile, zoom_text.strip_edges()])
	cam.zoom = Vector2.ONE * 1.1
	cam.set("_target_zoom", cam.zoom)
	await _wait(0.5)
	# Built as the build flow does: the building, then the map told where it stands.
	var iid := BuildingState.add_building("b_019", "", tile, MatchState.LOCAL_PLAYER)
	main.emit_signal("building_placed", tile, "b_019", "", iid, coord)
	await _wait(1.5)
	await _shot("%s_rails" % tile)
	get_tree().quit()


func _shot(name: String) -> void:
	RenderingServer.force_draw(false)
	get_viewport().get_texture().get_image().save_png(_out.path_join("tile_%s.png" % name))
	await get_tree().process_frame


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout
