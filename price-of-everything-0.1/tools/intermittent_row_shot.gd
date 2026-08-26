extends Node2D
## Verification for the intermittency warning in the construct panel's CONFIRM view.
## Drives the real panel to confirm for the Solar Farm, whose power is intermittent, and again
## for a steady generator, so the shot shows both that the row appears and that it does NOT
## appear on a building that has no such problem.
##   Godot --path . res://tools/intermittent_row_shot.tscn --quit-after 1800
## Writes res://intermittent_row_shot.png and res://intermittent_row_control.png

var _wm


func _ready() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	_wm = packed.instantiate()
	add_child(_wm)
	await _settle(140)
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		cam.edge_pan_enabled = false

	var menu = _wm.get_node_or_null("UILayer/HUD")
	if menu == null or menu.get("construct_panel_v2") == null:
		print("[INTERMITTENT_SHOT] construct panel v2 not found — aborting")
		get_tree().quit(1)
		return
	var panel = menu.construct_panel_v2

	# Solar Farm (b_024) — r_146 Solar Power Generation. Expect the warning row.
	await _shoot(panel, "b_024", "r_146", "res://intermittent_row_shot.png", true)
	# Coal power (b_003 / r_004) — steady generation. Expect NO warning row. It must go through
	# _on_recipe_pressed like the case above: _on_building_pressed only toggles the browse list
	# and leaves _selected_building untouched, which silently kept the solar farm selected and
	# made the control "fail".
	await _shoot(panel, "b_003", "r_004", "res://intermittent_row_control.png", false)
	get_tree().quit()


func _shoot(panel, building_id: String, recipe_id: String, out: String, expect: bool) -> void:
	panel.show()
	panel._locked_tile_id = "tile_5_10"
	panel._on_recipe_pressed(building_id, recipe_id)
	await _settle(14)
	# Assert on the model, not on pixels: the screenshot is for the look, this is for the logic.
	var rows: Array = panel._site_requirement_rows()
	var found := false
	for r in rows:
		for n in _all(r):
			if n is RichTextLabel and "intermittent power" in String(n.text):
				found = true
	print("[INTERMITTENT_SHOT] %s rows=%d warning=%s expected=%s %s" %
		[building_id, rows.size(), str(found), str(expect), "OK" if found == expect else "MISMATCH"])
	if panel._scroll != null:
		panel._scroll.scroll_vertical = 0
		await _settle(6)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	print("SAVED ", out)


func _all(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_all(c))
	return out


func _settle(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
