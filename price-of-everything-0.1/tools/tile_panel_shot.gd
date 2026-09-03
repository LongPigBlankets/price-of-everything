extends Node
## Dev tool: the tile-info panel as a player first sees it — opened once, on a tile with
## several buildings, so a card's height can be checked against its content.
##   /tmp/poe_tile_panel_<tile>.png
## Windowed: <godot> --path . res://tools/tile_panel_shot.tscn --quit-after 30000 -- --tiles=tile_5_10

func _ready() -> void:
	var tiles: Array = ["tile_5_10"]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tiles="):
			tiles = a.trim_prefix("--tiles=").split(",")
	SaveLoad.prepare_new_game("res://data/starts/metal_magnate.json", {"ruleset": {
		"start_id": "metal_magnate", "difficulty": "normal", "speed_turns": 100,
		"policy_timeline": "demo_itch", "victory_set": "demo_itch",
		"tutorial_enabled": false, "survey_all_tiles": true, "company_colour": "diesel_red",
	}})
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(240)
	# The start intro sits over the HUD on a fresh match; it is not what is under test.
	for node in get_tree().root.find_children("*", "CanvasLayer", true, false):
		var script_res: Variant = node.get_script()
		if script_res != null and str((script_res as Script).resource_path).ends_with("_intro.gd"):
			node.queue_free()
	await _settle(10)
	var terrain: Node = game.get("terrain_layer")
	var panel: Node = game.find_child("TileInfoPanel", true, false)
	if terrain == null or panel == null:
		push_error("[TILE PANEL] no terrain layer or panel"); get_tree().quit(1); return
	for tile_value in tiles:
		var tile_id := str(tile_value)
		var coord: Vector2i = terrain.id_to_coord(tile_id)
		var tiles_dict: Dictionary = terrain.get("tiles")
		if not tiles_dict.has(coord):
			push_warning("[TILE PANEL] unknown tile %s" % tile_id)
			continue
		# Opened exactly once, as a click would: the first-open layout is the thing under test.
		panel.call("show_tile", tiles_dict[coord])
		await _settle(45)
		var card := _first_card(panel)
		if card != null:
			print("[TILE PANEL] %s first card '%s' height=%.0f px" % [tile_id, card.name, (card as Control).size.y])
		await RenderingServer.frame_post_draw
		var path := "/tmp/poe_tile_panel_%s.png" % tile_id
		get_viewport().get_texture().get_image().save_png(path)
		print("[TILE PANEL] saved ", path)
	get_tree().quit(0)

## The first building card in the panel, so its height can be reported next to the shot.
func _first_card(n: Node) -> Node:
	if str(n.name).begins_with("BuildingCard_"):
		return n
	for c in n.get_children():
		var hit := _first_card(c)
		if hit != null:
			return hit
	return null

func _settle(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
