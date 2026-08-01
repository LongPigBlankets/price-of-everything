extends Node
## Dev tool: prove the tile panel's "Stock Utilisation last turn" row and the Stockpile TAB
## BUTTON report different things. They used to be computed from the same current level, so they
## always agreed and the row could never explain a "tile cannot receive more goods" alert.
##
## Drives a real tile through a turn shape that separates them: fill it past its cap (some goods
## are turned away), then drain most of it, so the END-of-turn level is low while the PEAK was
## at capacity. Opens the Stockpile tab and shoots it.
##   <godot> --path . res://tools/stock_utilisation_shot.tscn --quit-after 900

func _ready() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(30)

	var tile := "tile_5_10"
	var panel: Node = game.get_node_or_null("UILayer/HUD/HUDContent/TileInfoPanel")
	if panel == null:
		for n in game.get_node("UILayer/HUD/HUDContent").get_children():
			if n.get_script() != null and str(n.get_script().resource_path).ends_with("tile_info_panel_v2.gd"):
				panel = n
				break
	if panel == null:
		push_error("tile panel not found")
		get_tree().quit(1)
		return

	# One turn's worth of stockpile movement on this tile: a spike well past the cap, then the
	# drain that production and sales would do.
	Stockpile.roll_turn_peaks()
	var cap := Stockpile.get_capacity(tile)
	Stockpile.add(tile, "g_001", cap + 260)      # 260 of these can never land
	Stockpile.consume(tile, "g_001", cap - 90)   # ...and most of what did lands elsewhere later
	print("TILE %s: capacity=%d | current used=%d (the TAB BUTTON) | peak=%d refused=%d (the ROW)"
		% [tile, cap, Stockpile.get_used_capacity(tile), Stockpile.get_peak_used(tile),
			Stockpile.get_refused(tile)])

	var terrain := get_tree().get_first_node_in_group("hex_map")
	var coord = terrain.id_to_coord(tile)
	panel.call("show_tile", terrain.tiles[coord])
	await _settle(6)
	panel.call("_select_tab", "stock")     # show_tile always lands on Buildings
	await _settle(14)
	# Filling the tile pops the capacity dialog over the panel; this shot is about the panel.
	for sib in panel.get_parent().get_parent().get_children():
		if sib != panel.get_parent() and sib is CanvasItem and (sib as CanvasItem).visible:
			(sib as CanvasItem).visible = false
	await _settle(6)
	var img := get_viewport().get_texture().get_image()
	img.save_png("/tmp/poe_stock_utilisation.png")
	print("SAVED /tmp/poe_stock_utilisation.png")
	get_tree().quit(0)


func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
