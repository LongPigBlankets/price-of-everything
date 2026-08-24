extends Node
## Windowed shot: the anomaly cards under their modules, at the owner's sizing — as wide
## as the module they belong to, three lines then an ellipsis, 6px padding, 16px off-white.

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
	# One short card and one long one, so both the module width and the 3-line trim show.
	var anchor: Variant = bar.get("money_widget")
	if anchor == null:
		anchor = bar.get("_power_btn")
	if anchor == null:
		push_error("no module anchor to hang a card on"); get_tree().quit(1); return
	bar.call("_show_anomaly_stack", [
		{"text": "Revenue jumped: four shipments landed in the same turn."},
		{"text": "Freight is up by half again on the last three turns — the new smelter is hauling ore nine tiles over roads, and every leg of that is charged separately, which is the whole of the difference and then some more besides."},
	], anchor)
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
