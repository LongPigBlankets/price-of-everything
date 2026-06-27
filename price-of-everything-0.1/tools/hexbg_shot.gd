extends Node
## Dev tool: render the Empire-view hex-field background to PNGs so the pattern + animation can be
## iterated without the node graph covering them. Windowed (NOT --headless):
##   <godot> --path . res://tools/hexbg_shot.tscn --quit-after 600
##
## Drives the animation deterministically (processing off, clock/explosions set by hand) and captures
## one frame per animation mode: a1 building pulses, a2 wave, a3 glow, a4 single ring, a4 two-ring clash.

func _ready() -> void:
	var bg: Control = (load("res://scripts/empire_hex_bg.gd") as GDScript).new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var layer := CanvasLayer.new()
	add_child(layer)
	layer.add_child(bg)
	await get_tree().process_frame
	await get_tree().process_frame
	bg.set_process(false)   # drive the clock ourselves for reproducible frames

	var vp := get_viewport().get_visible_rect().size
	# Fake building positions for the building-origin pulse (no graph here).
	bg.call("set_origins", PackedVector2Array([
		vp * Vector2(0.28, 0.42), vp * Vector2(0.60, 0.30),
		vp * Vector2(0.48, 0.66), vp * Vector2(0.78, 0.56),
	]))

	await _grab(bg, 1, 2.4, [], "/tmp/poe_hexbg_a1.png")
	await _grab(bg, 2, 2.0, [], "/tmp/poe_hexbg_a2.png")
	await _grab(bg, 3, 6.0, [], "/tmp/poe_hexbg_a3.png")
	# anim 4 — single expanding ring (one explosion, mid-life).
	await _grab(bg, 4, 2.0, [
		{"origin": vp * Vector2(0.46, 0.52), "t0": 1.0},
	], "/tmp/poe_hexbg_a4_single.png")
	# anim 4 — two rings overlapping (the "clash and merge").
	await _grab(bg, 4, 2.0, [
		{"origin": vp * Vector2(0.38, 0.50), "t0": 0.5},
		{"origin": vp * Vector2(0.60, 0.54), "t0": 0.9},
	], "/tmp/poe_hexbg_a4_double.png")

	get_tree().quit(0)


func _grab(bg: Control, anim: int, t: float, explosions: Array, path: String) -> void:
	bg.set("empire_view_animation", anim)
	bg.set("_t", t)
	bg.set("_explosions", explosions)
	bg.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("SAVED ", path)
