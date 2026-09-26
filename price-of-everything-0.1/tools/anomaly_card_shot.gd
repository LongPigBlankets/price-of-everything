extends Node
## Windowed shot: two notices as amber rows in the bottom-left updates dock, one short and
## one long, so the row wrapping shows.

const START := "res://data/starts/metal_magnate.json"

func _ready() -> void:
	get_window().size = Vector2i(1920, 1080)
	SaveLoad.prepare_new_game(START)
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	var f := 0
	while f < 5000 and main.get("build_complete") != true:
		await get_tree().process_frame
		f += 1
	await _settle(20)
	var bar: Node = main.find_child("TopBar", true, false)
	if bar == null:
		push_error("no TopBar"); get_tree().quit(1); return
	bar.call("_post_notices", [
		{"id": "payment", "word": "earned you £912", "tone": "good",
			"text": "You sold 40 units of Steel to the global market, which earned you £912."},
		{"id": "transport", "word": "Transport", "tone": "bad",
			"text": "Transport costs are through the roof. Check if we are shipping by the most efficient transport, because every leg of a long haul is charged separately and the new smelter is nine tiles out."},
	])
	await _settle(30)
	await _shot("user://poe_anomaly_cards.png")
	get_tree().quit(0)

func _settle(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("[ANOM] saved ", path)
