extends Node
func _ready() -> void:
	get_window().size = Vector2i(1600, 1000)
	var game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	for i in 60:
		await get_tree().process_frame
	var panel = game.get_node("UILayer/HUD/HUDContent/ResearchPanel")
	PanelStack.push(panel)
	panel.show()
	if "--tree" in OS.get_cmdline_user_args():
		panel.set("_selected_category", "Infrastructure")
		panel.queue_redraw()
		for frame in 25:
			await get_tree().process_frame
		RenderingServer.force_draw()
		get_viewport().get_texture().get_image().save_png("/private/tmp/research-infrastructure.png")
		get_tree().quit()
		return
	panel.open_with_search("Moving Assembly Lines", true)
	panel.set("_expanded_requirement_titles", {"Moving Assembly Lines": true})
	var rows: Array = panel.call("_category_unlocks", "Extraction")
	var layout: Dictionary = panel.call("_layout_unlocks", rows)
	var card: Rect2 = layout["Moving Assembly Lines"]
	var tree: Rect2 = panel.call("_tree_rect")
	var origin: Vector2 = panel.call("_tree_origin")
	panel.set("_category_view_state", {"Extraction": {"zoom": 1.0, "pan": tree.get_center() - origin - card.get_center()}})
	panel.queue_redraw()
	for i in 20:
		await get_tree().process_frame
	RenderingServer.force_draw()
	get_viewport().get_texture().get_image().save_png("/private/tmp/research-requirements.png")
	get_tree().quit()
