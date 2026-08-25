extends Node
## Dev tool: render the tile-view panel's four summary tabs, so the metal plates, the brass
## rims and the status lamps are checked as a player sees them.
##   Godot --path . res://tools/tile_tabs_shot.tscn --quit-after 1200

func _ready() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(120)
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		cam.edge_pan_enabled = false

	var tile := "tile_5_10"
	MatchState.add_building("b_001", "r_001", tile, "player_1", "tabs_probe", false)
	Stockpile.add(tile, "g_001", 180)
	await _settle(4)

	var panel: Node = _find_by_method(game, "show_tile")
	if panel == null:
		print("[TABS] tile panel not found")
		get_tree().quit(1)
		return
	var coord: Vector2i = game.terrain_layer.id_to_coord(tile)
	var tile_data: Dictionary = game.terrain_layer.tiles.get(coord, {})
	panel.call("show_tile", tile_data)
	await _settle(20)

	# Force one tab to each status, so all three lamp colours appear in one shot rather
	# than only the healthy case a fresh tile happens to produce.
	panel.call("_set_tile", "power", "warn", "-40", "/turn")
	panel.call("_set_tile", "prod", "problem", "£0", "/turn")
	panel.call("_apply_tile_styles")
	await _settle(10)
	get_viewport().get_texture().get_image().save_png("user://poe_tile_tabs.png")
	print("[TABS] wrote poe_tile_tabs.png")
	get_tree().quit(0)


func _find_by_method(n: Node, method: String) -> Node:
	if n.has_method(method):
		return n
	for c in n.get_children():
		var hit := _find_by_method(c, method)
		if hit != null:
			return hit
	return null


func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
