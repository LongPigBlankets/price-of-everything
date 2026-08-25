extends Node
## Dev tool: render the build-refusal flash — the red tile plus the reason under it that a
## refused infrastructure placement now shows, instead of returning silently.
##   Godot --path . res://tools/build_refusal_shot.tscn --quit-after 900

func _ready() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(120)
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		cam.edge_pan_enabled = false

	var overlay: Node = game.get_node_or_null("MapOverlay")
	print("[REFUSAL] overlay=%s has_method=%s" % [
		str(overlay != null),
		str(overlay != null and overlay.has_method("flash_build_refusal"))])
	if overlay == null or not overlay.has_method("flash_build_refusal"):
		get_tree().quit(1)
		return

	# The tile nearest the camera, so the flash is actually on screen. Moving the camera to a
	# chosen tile does not work: the controller clamps it to the map limits and re-asserts its
	# own position every frame, so the first attempt shot an empty stretch of map.
	var centre: Vector2 = cam.global_position if cam != null else Vector2.ZERO
	var coord := Vector2i.ZERO
	var best := INF
	for c_variant: Variant in game.terrain_layer.tiles:
		var c: Vector2i = c_variant
		var d: float = (overlay.call("_tile_world_pos", c) as Vector2).distance_to(centre)
		if d < best:
			best = d
			coord = c
	overlay.call("flash_build_refusal", coord, "Insufficient land — buy more here")
	await _settle(8)
	var nodes: Array = overlay.get("_refusal_nodes")
	print("[REFUSAL] nodes=%d  tile_world=%s  cam=%s  overlay_vis=%s" % [
		nodes.size(), str(overlay.call("_tile_world_pos", coord)),
		str(cam.global_position) if cam != null else "no cam",
		str((overlay as Node2D).visible)])
	for n in nodes:
		if n is Node2D:
			print("[REFUSAL]   Node2D %s pos=%s vis=%s mod=%s" % [
				n.name, str((n as Node2D).position), str((n as Node2D).visible),
				str((n as Node2D).modulate)])
		elif n is Control:
			print("[REFUSAL]   Control %s pos=%s size=%s vis=%s" % [
				n.name, str((n as Control).position), str((n as Control).size),
				str((n as Control).visible)])
	get_viewport().get_texture().get_image().save_png("user://poe_build_refusal.png")
	print("[REFUSAL] wrote poe_build_refusal.png")

	# ...and that it clears itself rather than staying on the map.
	await _settle(360)   # comfortably past REFUSAL_SECONDS at 60 fps
	var left: int = (overlay.get("_refusal_nodes") as Array).size()
	print("[REFUSAL] nodes left after the timeout: %d" % left)
	get_tree().quit(0)


func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
