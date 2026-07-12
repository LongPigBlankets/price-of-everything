extends Node
## Dev tool: render the real game and screenshot the End Turn Dock at rest — the
## navy plate with the centred END TURN button. The per-turn financial breakdown
## now lives in the top bar's Treasury mini-panel, not here.
## Needs a window (NOT --headless):
##   <godot> --path . res://tools/end_turn_dock_shot.tscn --quit-after 900

func _ready() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(30)

	# Resting state — what players see between turns.
	await _shot("/tmp/poe_end_turn_dock.png")

	# Disabled state — while a turn resolves (world_map toggles this).
	var btn: Button = game.get_node("UILayer/HUD/HUDContent/EndTurnDock/EndTurnButton")
	btn.disabled = true
	await _settle(6)
	await _shot("/tmp/poe_end_turn_dock_disabled.png")

	get_tree().quit(0)

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw   # capture the freshly-rendered frame
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)

func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
