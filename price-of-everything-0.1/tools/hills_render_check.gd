extends Node
## Render the map after a full build and screenshot it, to verify the hill LOD + cached-mesh bake
## still look correct.  <godot> --path . res://tools/hills_render_check.tscn --quit-after 2500
func _ready() -> void:
	get_window().size = Vector2i(1280, 720)
	SaveLoad.prepare_new_game("res://data/starts/coal_baron.json")
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	while not bool(main.get("build_complete")):
		await get_tree().process_frame
	for _i in range(40):
		await get_tree().process_frame   # let hills warm + the bake (if zoomed out) settle
	get_viewport().get_texture().get_image().save_png("/tmp/poe_hills_check.png")
	print("HILLS saved /tmp/poe_hills_check.png")
	get_tree().quit(0)
