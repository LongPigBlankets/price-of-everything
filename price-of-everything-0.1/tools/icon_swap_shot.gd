extends Node
## Dev tool: show the four swapped building icons where the player actually meets them — the
## tile panel's building cards (90px, the size the owner flagged as the one that has to work)
## and the Build menu. Seeds one of each type on a single tile so all four land in one frame.
##   <godot> --path . res://tools/icon_swap_shot.tscn --quit-after 900

const IDS := ["b_002", "b_003", "b_014", "b_013", "b_010", "b_012"]  # the six swapped glyphs

func _ready() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(30)

	var tile := "tile_5_10"
	for i in range(IDS.size()):
		var recs: Array = Catalog.get_recipes_for_building(IDS[i])
		var rid := str((recs[0] as Dictionary).get("recipe_id", "")) if not recs.is_empty() else ""
		MatchState.add_building(IDS[i], rid, tile, MatchState.LOCAL_PLAYER, "iconshot_%d" % i)
	await _settle(4)

	var panel: Node = null
	for n in game.get_node("UILayer/HUD/HUDContent").get_children():
		if n.get_script() != null and str(n.get_script().resource_path).ends_with("tile_info_panel_v2.gd"):
			panel = n
			break
	if panel == null:
		push_error("tile panel not found")
		get_tree().quit(1)
		return
	var terrain := get_tree().get_first_node_in_group("hex_map")
	panel.call("show_tile", terrain.tiles[terrain.id_to_coord(tile)])
	await _settle(14)
	for sib in panel.get_parent().get_parent().get_children():
		if sib != panel.get_parent() and sib is CanvasItem and (sib as CanvasItem).visible:
			(sib as CanvasItem).visible = false
	await _settle(6)
	get_viewport().get_texture().get_image().save_png("/tmp/poe_icons_tile_panel.png")
	print("SAVED /tmp/poe_icons_tile_panel.png")
	get_tree().quit(0)


func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
