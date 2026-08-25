extends Node
## Dev tool: render the New Game settings panel open over the main menu and save a
## PNG, to verify layout + theming. Needs a window (NOT --headless):
##   <godot> --path . res://tools/new_game_shot.tscn --quit-after 1200
## Pass a start index to verify the detail updates on selection:
##   <godot> --path . res://tools/new_game_shot.tscn --quit-after 1200 -- 1

func _ready() -> void:
	# Width from the second user arg so the FIXED panel width can be checked against both a
	# 1080p screen and the owner's ultrawide. /tmp does not exist on Windows — user:// does,
	# and lands in AppData/Roaming/Godot/app_userdata.
	get_window().size = Vector2i(_arg_width(), 1080)
	var menu: Node = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	add_child(menu)
	await _settle(10)
	if menu.has_method("_show_new_game_panel"):
		menu.call("_show_new_game_panel")
	await _settle(40)   # let the reveal tween finish
	var panel: Variant = menu.get("_new_game_panel")
	var idx := _arg_index()
	if idx > 0 and panel != null:
		var btns: Variant = (panel as Object).get("_card_buttons")
		if btns is Array and idx < (btns as Array).size():
			((btns as Array)[idx] as BaseButton).button_pressed = true
		await _settle(10)
	# Force the final reveal alpha (offscreen render can throttle the tween).
	if panel != null:
		(panel as Control).modulate.a = 1.0
	await _settle(3)
	var out := "user://poe_new_game_%d_%d.png" % [idx, _arg_width()]
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
	get_tree().quit(0)

func _arg_width() -> int:
	var seen := 0
	for a in OS.get_cmdline_user_args():
		if a.is_valid_int():
			seen += 1
			if seen == 2:
				return a.to_int()
	return 1920


func _arg_index() -> int:
	for a in OS.get_cmdline_user_args():
		if a.is_valid_int():
			return a.to_int()
	return 0

func _settle(frames: int) -> void:
	for _i in range(frames):
		await get_tree().process_frame
