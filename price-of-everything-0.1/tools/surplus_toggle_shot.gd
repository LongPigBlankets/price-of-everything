extends Node
## Dev tool: verify the "Sell all Surplus" toggle placement (under the chart,
## outside the per-good flow) and its confirmation dialog. Needs a window (NOT
## --headless):  <godot> --path . res://tools/surplus_toggle_shot.tscn --quit-after 1200

func _ready() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(140)

	# Seed some stock on a starting-company tile so the stockpile pane has bars.
	var tile := "tile_5_10"
	for pair in [["g_001", 120], ["g_012", 40], ["g_030", 12]]:
		Stockpile.add(tile, str(pair[0]), int(pair[1]))
	await _settle(4)

	var info: Node = game.find_child("TileInfoPanel", true, false)
	if info == null:
		print("no TVP found"); get_tree().quit(1); return
	var td := _tile_data(game, tile)
	info.call("show_tile", td)
	await _settle(6)
	# Switch to the Stockpile tab.
	info.set("_active_tab", "stock")
	info.call("_select_tab", "stock")
	await _settle(8)
	_shot("/tmp/poe_surplus_toggle.png")

	# Tick the toggle to raise the confirmation dialog.
	info.call("_on_sell_surplus_toggled", tile, CheckBox.new(), true)
	await _settle(8)
	_shot("/tmp/poe_surplus_dialog.png")
	get_tree().quit(0)

func _tile_data(game: Node, tile_id: String) -> Dictionary:
	var hm: Node = game.find_child("TerrainLayer", true, false)
	if hm == null:
		hm = get_tree().get_first_node_in_group("hex_map")
	var coord: Vector2i = hm.id_to_coord(tile_id)
	return hm.tiles.get(coord, {})

func _shot(path: String) -> void:
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)

func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
