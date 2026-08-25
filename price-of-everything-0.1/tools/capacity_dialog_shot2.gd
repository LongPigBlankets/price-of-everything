extends Node
## Dev tool: render the capacity dialog in BOTH states — a tile that can still expand, and
## one whose storage is already maxed (the state a playtester found showing three enormous
## empty boxes and no goods at all).
##   Godot --path . res://tools/capacity_dialog_shot2.tscn --quit-after 1400

func _ready() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(120)

	var tile := "tile_5_10"
	MatchState.add_building("b_001", "r_001", tile, "player_1", "cap_probe", false)
	# Something on the tile to overflow with, in unequal amounts so the sort is visible.
	for row: Array in [["g_001", 220], ["g_002", 140], ["g_004", 90], ["g_005", 55], ["g_003", 20]]:
		Stockpile.add(tile, str(row[0]), int(row[1]))
	await _settle(4)

	var dlg: Node = _find_by_method(game, "_on_tile_reached_capacity")
	if dlg == null:
		print("[CAP] capacity dialog not found")
		get_tree().quit(1)
		return

	# State A: storage can still be expanded.
	dlg.set("_current_tile", tile)
	dlg.call("_refresh_for_tile")
	(dlg as Control).visible = true
	(dlg as Control).move_to_front()
	await _settle(20)
	get_viewport().get_texture().get_image().save_png("user://poe_capacity_expandable.png")
	print("[CAP] wrote poe_capacity_expandable.png")

	# State B: storage maxed — the broken one.
	Stockpile.set_warehouse_level(tile, EconomyConfig.WAREHOUSE_STORAGE_CAP.size())
	await _settle(4)
	dlg.call("_refresh_for_tile")
	await _settle(20)
	get_viewport().get_texture().get_image().save_png("user://poe_capacity_maxed.png")
	print("[CAP] wrote poe_capacity_maxed.png")
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
