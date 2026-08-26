extends Node2D
## Verification for the build-mode hover cost preview (map_overlay.gd,
## build_cost_preview.gd). Loads the real main scene, enters BuildMode for a
## real building, and renders the preview on a real tile via the same
## production code path map_overlay._update_build_cost_hover() uses — without
## needing to simulate mouse motion over a specific screen position, which
## the actual hover-detection (terrain_layer.tile_id_under_mouse(), mirroring
## the already-proven infra-hover pattern) doesn't need re-verifying visually.
##   Godot --path . res://tools/build_hover_shot.tscn --quit-after 1200
## Writes res://build_hover_shot.png

var _wm


func _ready() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	_wm = packed.instantiate()
	add_child(_wm)
	await _settle(140)
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		cam.edge_pan_enabled = false

	var map_overlay: Node2D = _wm.get_node_or_null("MapOverlay")
	var terrain_layer = _wm.get_node_or_null("%TerrainLayer")
	if map_overlay == null or terrain_layer == null:
		print("[HOVER_SHOT] MapOverlay or TerrainLayer not found — aborting")
		get_tree().quit(1)
		return

	BuildMode.enter_build_mode("b_002", "r_005")
	await _settle(4)

	var tile_id := "tile_5_10"
	var coord: Vector2i = terrain_layer.id_to_coord(tile_id)
	var rows: Array = map_overlay.call("_build_cost_rows", tile_id)
	print("[HOVER_SHOT] rows=%s" % str(rows))

	var BuildCostPreviewScript: Script = load("res://scripts/build_cost_preview.gd")
	var preview := Node2D.new()
	preview.set_script(BuildCostPreviewScript)
	preview.set("tile_size", map_overlay.call("_tile_size"))
	preview.set("rows", rows)
	preview.position = map_overlay.call("_tile_world_pos", coord)
	map_overlay.add_child(preview)
	await _settle(4)

	# Centre the camera tight on the tile so it fills most of the frame — the
	# earlier wide shot showed mostly fogged/unsurveyed terrain, too small to
	# judge "covers roughly a third of the tile" against.
	if cam != null:
		cam.global_position = preview.global_position
		cam.zoom = Vector2(3.5, 3.5)
	await _settle(6)

	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://build_hover_shot.png")
	print("SAVED build_hover_shot.png")
	get_tree().quit()


func _settle(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
