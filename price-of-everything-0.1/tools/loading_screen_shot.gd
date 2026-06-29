extends Node
## Dev tool: render the real LoadingScreen (hex bg + metallic "Loading…" plate) to
## verify the integration. Windowed:
##   <godot> --path . res://tools/loading_screen_shot.tscn --quit-after 900

const LoadingScreenScript := preload("res://scripts/loading_screen.gd")

func _ready() -> void:
	get_window().size = Vector2i(1920, 1080)
	var ls: Node = LoadingScreenScript.new()
	add_child(ls)
	await _settle(12)
	var hex: Variant = ls.get("_hex_bg")
	if hex != null:
		(hex as Object).call("seek", 14.0)   # into the gold sweep
	await _settle(3)
	get_viewport().get_texture().get_image().save_png("/tmp/poe_loading_screen.png")
	print("saved /tmp/poe_loading_screen.png")
	get_tree().quit(0)

func _settle(frames: int) -> void:
	for _i in range(frames):
		await get_tree().process_frame
