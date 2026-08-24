extends Node
## Windowed shot: the Resources table with its new columns, and one good expanded to its
## freight breakdown.

const START := "res://data/starts/metal_magnate.json"

func _ready() -> void:
	get_window().size = Vector2i(1600, 1000)
	SaveLoad.prepare_new_game(START)
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	var f := 0
	while f < 5000 and main.get("build_complete") != true:
		await get_tree().process_frame
		f += 1
	for _i in range(20):
		await get_tree().process_frame
	var panel: Node = main.find_child("ResourcePanel", true, false)
	if panel == null:
		push_error("no ResourcePanel"); get_tree().quit(1); return
	panel.call("show")
	await _settle(20)
	await _shot("user://poe_resources.png")
	# Expand a solid and a fluid so both freight tables are on screen.
	panel.call("_toggle_good", "g_001")
	panel.call("_toggle_good", "g_016")
	await _settle(20)
	await _shot("user://poe_resources_open.png")
	get_tree().quit(0)

func _settle(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("[RES_SHOT] saved ", path)
