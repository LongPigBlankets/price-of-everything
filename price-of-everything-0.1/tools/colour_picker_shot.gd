extends Node
## Dev tool: open the New Game panel, drop the Company colour dropdown open, and save a PNG
## — the only way to see all eight liveries and their 20px swatches at once, since the popup
## is a separate window the ordinary panel shot never captures. Needs a window (NOT
## --headless):
##   <godot> --path . res://tools/colour_picker_shot.tscn --quit-after 1800
##
## The popup is rendered into the SAME viewport image here (embedded subwindows), which is
## why the shot has to force `gui_embed_subwindows` on rather than trusting the project's
## default — an OS-level popup window would be a second surface and photograph as a hole.

func _ready() -> void:
	get_window().size = Vector2i(1920, 1080)
	get_window().gui_embed_subwindows = true
	var menu: Node = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	add_child(menu)
	await _settle(10)
	if menu.has_method("_show_new_game_panel"):
		menu.call("_show_new_game_panel")
	await _settle(40)
	var panel: Variant = menu.get("_new_game_panel")
	if panel != null:
		(panel as Control).modulate.a = 1.0
	var option := _find_option(panel as Node)
	if option == null:
		push_error("colour_picker_shot: no OptionButton found in the New Game panel")
		get_tree().quit(1)
		return
	print("livery items: ", option.item_count)
	for i in option.item_count:
		print("  %d  %s  icon=%s" % [i, option.get_item_text(i),
			"yes" if option.get_item_icon(i) != null else "NO"])
	option.show_popup()
	await _settle(8)
	var out := "user://poe_colour_picker.png"
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
	get_tree().quit(0)


## Depth-first hunt for the livery dropdown. By TYPE rather than by node path: the panel
## builds its tree in code, so a path would break the moment a container moved.
func _find_option(node: Node) -> OptionButton:
	if node == null:
		return null
	if node is OptionButton:
		return node as OptionButton
	for child in node.get_children():
		var found := _find_option(child)
		if found != null:
			return found
	return null


func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
