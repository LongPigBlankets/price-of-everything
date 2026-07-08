extends Node
## Windowed screenshot of the bankruptcy game-over screen (feature 6): the cautionary
## copy, the switchable finance chart, and the Return to Main Menu CTA. Seeds a fake
## run history so the chart has a curve. Writes /tmp/poe_game_over_shot.png.
##   "$GODOT_BIN" --path . res://tools/game_over_shot.tscn --quit-after 900

func _ready() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(140)
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		cam.edge_pan_enabled = false

	# A plausible boom-to-bust arc for the chart.
	var history: Array = []
	for t in range(1, 41):
		var money := 200.0 + 60.0 * float(t) - 6.0 * float(t) * float(t) / 4.0
		history.append({
			"turn": t,
			"money": money,
			"profit": 60.0 - 3.0 * float(t),
			"empire_value": 400.0 + 120.0 * float(t) - float(t) * float(t),
			"output_value": maxf(0.0, 300.0 + 40.0 * float(t) - 2.0 * float(t) * float(t)),
		})

	var panel: Control = load("res://scripts/game_over_panel.gd").new()
	var layer := CanvasLayer.new()
	layer.layer = 200
	add_child(layer)
	layer.add_child(panel)
	panel.open(history)
	await _settle(20)

	get_viewport().get_texture().get_image().save_png("/tmp/poe_game_over_shot.png")
	print("[game_over_shot] wrote /tmp/poe_game_over_shot.png")
	get_tree().quit(0)

func _settle(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
