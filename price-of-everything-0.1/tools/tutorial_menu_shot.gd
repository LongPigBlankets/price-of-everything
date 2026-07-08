extends Node
## Dev shot: render the mini "Begin Tutorial" panel open over the main menu, to verify
## the Tutorial button + panel. Needs a window (NOT --headless):
##   <godot> --path . res://tools/tutorial_menu_shot.tscn --quit-after 1200

func _ready() -> void:
	get_window().size = Vector2i(1920, 1080)
	var menu: Node = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	add_child(menu)
	await _settle(10)
	# Show the panel directly (bypass the fade tween, which throttles offscreen).
	var panel: Variant = menu.get("_tutorial_panel")
	if panel != null:
		(panel as Control).visible = true
		(panel as Control).modulate.a = 1.0
	await _settle(6)
	var out := ProjectSettings.globalize_path("res://tutorial_menu_shot.png")
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
	get_tree().quit(0)

func _settle(frames: int) -> void:
	for _i in range(frames):
		await get_tree().process_frame
