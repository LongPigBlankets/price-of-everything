extends Node
## Dev tool: render the real game, open the ResearchPanel on the new Recycling
## tab, and save a PNG. Needs a window (NOT --headless):
##   <godot> --path . res://tools/research_shot.tscn --quit-after 600

func _ready() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(30)
	var panel: Control = game.get_node("UILayer/HUD/HUDContent/ResearchPanel")
	PanelStack.push(panel)
	panel.show()
	panel.set("_selected_category", "Recycling")
	panel.queue_redraw()
	await _settle(16)
	get_viewport().get_texture().get_image().save_png("/tmp/poe_research_recycling.png")
	print("saved /tmp/poe_research_recycling.png")
	get_tree().quit(0)

func _settle(frames: int) -> void:
	for _i in range(frames):
		await get_tree().process_frame
