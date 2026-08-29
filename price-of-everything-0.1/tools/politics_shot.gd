extends Node
## Dev tool: render the Politics panel at two points in the arc — before the election (the
## empty state) and after the subsidy lands (the full record). Needs a window:
##   <godot> --path . res://tools/politics_shot.tscn --quit-after 1200
func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(30)
	var hud: Node = game.find_child("HUD", true, false)
	if hud == null or not hud.has_method("_on_politics_pressed"):
		push_error("politics_shot: HUD handlers not found")
		get_tree().quit(1)
		return

	TurnManager.current_turn = 10
	hud.call("_on_politics_pressed")
	await _settle(12)
	_shot("/tmp/poe_politics_empty.png")

	# Past the subsidy: every beat in the record.
	TurnManager.current_turn = 110
	var panel = hud.get("politics_panel")
	panel.call("_refresh")
	await _settle(12)
	print("entries at t110: ", (panel.call("_entries") as Array).size())
	_shot("/tmp/poe_politics_full.png")
	get_tree().quit(0)

func _shot(path: String) -> void:
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)

func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
