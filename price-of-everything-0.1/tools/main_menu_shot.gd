extends Node
## Dev tool: render the real main menu (title plate + animated goods board) and
## save a PNG to verify the board fills with unique good icons. Needs a window
## (NOT --headless):
##   <godot> --path . res://tools/main_menu_shot.tscn --quit-after 900

func _ready() -> void:
	var menu: Node = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	add_child(menu)
	await _settle(40)
	get_viewport().get_texture().get_image().save_png("/tmp/poe_main_menu.png")
	print("saved /tmp/poe_main_menu.png")
	get_tree().quit(0)

func _settle(frames: int) -> void:
	for _i in range(frames):
		await get_tree().process_frame
