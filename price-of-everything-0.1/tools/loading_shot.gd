extends Node
## Dev tool: render the loading hex-intro background at several time points to verify
## the draw-in + gold corner-path sweep. Needs a window (NOT --headless):
##   <godot> --path . res://tools/loading_shot.tscn --quit-after 1200

const LoadingHexBg := preload("res://scripts/loading_hex_bg.gd")

func _ready() -> void:
	get_window().size = Vector2i(1920, 1080)
	var bg: Control = LoadingHexBg.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	await _settle(4)
	for t in [6.0, 11.0, 15.0, 20.0, 25.0, 30.0]:
		bg.call("seek", float(t))
		await _settle(2)
		var out := "/tmp/poe_loading_%02d.png" % int(t)
		get_viewport().get_texture().get_image().save_png(out)
		print("saved ", out)
	get_tree().quit(0)

func _settle(frames: int) -> void:
	for _i in range(frames):
		await get_tree().process_frame
