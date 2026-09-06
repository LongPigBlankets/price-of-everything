extends "res://scripts/research_panel.gd"
func _ready() -> void:
	super._ready()
	get_window().size = Vector2i(1500, 900)
	set_deferred("size", Vector2(1900, 1100))
	if _search_input != null: _search_input.hide()
	for title in ["Atomic Layer Deposition", "Pulverised Carbon Injection", "Flexible Manufacturing Cells", "Carbon Substitution"]:
		_expanded_requirement_titles[title] = true
	await get_tree().process_frame
	queue_redraw()
	await get_tree().process_frame
	for frame in 10:
		await get_tree().process_frame
	RenderingServer.force_draw()
	get_viewport().get_texture().get_image().save_png("/private/tmp/research-cards.png")
	get_tree().quit()
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#102b44"))
	var titles := ["Atomic Layer Deposition", "Pulverised Carbon Injection", "Flexible Manufacturing Cells", "Carbon Substitution"]
	for index in titles.size():
		for row in _unlock_rows:
			if row.title == titles[index]:
				_draw_unlock(row, Rect2(Vector2(25 + index * 380, 80), UNLOCK_SIZE), 0.0)
