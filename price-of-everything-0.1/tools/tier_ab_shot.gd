extends Node
## Dev tool: what did the near bake tier actually buy? Shoots the SAME frame twice in ONE run
## — once off the far textures, once off the near ones — at the camera's maximum zoom.
##
## One run, deliberately: this engine hands successive runs different window heights, the
## canvas scale rides on the window, and so a pair shot across two processes compares two
## framings while both honestly report the same camera zoom. Same process, same window, same
## camera; the tier is the only thing that moves.
##   /tmp/poe_tier_far_<tile>.png, /tmp/poe_tier_near_<tile>.png
## Windowed: <godot> --path . res://tools/tier_ab_shot.tscn --quit-after 20000 -- --tiles=tile_23_8

const AuthoredBakeScript := preload("res://scripts/authored_bake.gd")
const CROP := Vector2i(1000, 1000)

func _ready() -> void:
	var tiles: Array = ["tile_23_8"]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tiles="):
			tiles = a.trim_prefix("--tiles=").split(",")
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(200)
	var ui := game.get_node_or_null("UILayer") as CanvasLayer
	if ui != null:
		ui.visible = false
	for node in get_tree().root.find_children("*", "CanvasLayer", true, false):
		var script_res: Variant = node.get_script()
		if script_res != null and str((script_res as Script).resource_path).ends_with("_intro.gd"):
			node.queue_free()
	# Animation would differ between the three captures and swamp the thing being measured.
	for name in ["SmokeVisuals", "BirdVisuals"]:
		var animated: Node = game.find_child(name, true, false)
		if animated is CanvasItem:
			(animated as CanvasItem).visible = false
	var cam: Camera2D = get_viewport().get_camera_2d()
	var terrain: Node = game.get("terrain_layer")
	if cam == null or terrain == null:
		push_error("[TIER AB] no camera or terrain"); get_tree().quit(1); return
	cam.set_process(false)
	cam.set_physics_process(false)
	for field in ["_intro_tween", "_pan_tween"]:
		var tween: Variant = cam.get(field)
		if tween is Tween and (tween as Tween).is_valid():
			(tween as Tween).kill()
	if "edge_pan_enabled" in cam:
		cam.set("edge_pan_enabled", false)
	# The camera's own ceiling, so this photographs the zoom a player can actually reach.
	# --zoom lets this photograph a zoom the CURRENT window cannot reach: max zoom scales with
	# the logical viewport, so a 4K player reaches ~3.6 px/u where this 1080p-logical one stops
	# at ~1.8, and whether the near tier earns its keep depends entirely on which of those the
	# picture is being judged at.
	var max_zoom := float(cam.get("zoom_max"))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--zoom="):
			max_zoom = float(a.trim_prefix("--zoom="))
	print("[TIER AB] window=%s viewport=%s zoom_max=%.3f near_available=%s" % [
		str(DisplayServer.window_get_size()), str(get_viewport().get_visible_rect().size),
		max_zoom, str(AuthoredBakeScript.near_available())])
	for tile_value in tiles:
		var tile_id := str(tile_value)
		var coord: Vector2i = terrain.id_to_coord(tile_id)
		var tiles_dict: Dictionary = terrain.get("tiles")
		if not tiles_dict.has(coord):
			push_warning("[TIER AB] unknown tile %s" % tile_id)
			continue
		cam.position = terrain.map_to_local(terrain.map_coord_for_tile_coord(coord))
		cam.zoom = Vector2(max_zoom, max_zoom)
		if "_target_zoom" in cam:
			cam.set("_target_zoom", cam.zoom)
		for tier in ["far", "near"]:
			AuthoredBakeScript.force_tier = tier
			_repaint_map(game)
			await _settle(30)
			RenderingServer.force_draw()
			# Is the tier actually on screen? A tier switch asks for textures that are not
			# resident yet, and the draw falls back to the far ones for the frames they take to
			# land — so a shot taken too early photographs the wrong tier and says nothing.
			var resident := 0
			var near_resident := 0
			for path in AuthoredBakeScript._textures.keys():
				resident += 1
				if str(path).find("_near/") >= 0:
					near_resident += 1
			print("[TIER AB]   resident=%d of which near=%d pending=%d" % [
				resident, near_resident, AuthoredBakeScript._pending.size()])
			var image := get_viewport().get_texture().get_image()
			var crop := Vector2i(mini(CROP.x, image.get_width()), mini(CROP.y, image.get_height()))
			var origin := Vector2i((image.get_width() - crop.x) / 2, (image.get_height() - crop.y) / 2)
			var path := "/tmp/poe_tier_%s_%s.png" % [tier, tile_id]
			image.get_region(Rect2i(origin, crop)).save_png(path)
			print("[TIER AB] %s: tier=%s zoom=%.3f -> %s" % [tile_id, tier, cam.zoom.x, path])
	AuthoredBakeScript.force_tier = ""
	get_tree().quit(0)

## Both streaming layers hold their last-drawn view, so a tier change has to force the repaint.
func _repaint_map(game: Node) -> void:
	for name in ["AuthoredFabricVisuals", "AuthoredRoadVisuals"]:
		var layer: Node = game.find_child(name, true, false)
		if layer is CanvasItem:
			(layer as CanvasItem).queue_redraw()

func _settle(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
