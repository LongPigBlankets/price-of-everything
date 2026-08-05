extends Node
# Dev-only: capture the bottom menu strip so icon/button changes can be eyeballed —
# once at rest and once with the Empire button's hover glow + specular forced on.
# Run (windowed, NOT --headless, so it actually renders):
#   Godot --path . res://tools/bottom_menu_shot.tscn --quit-after 900

func _ready() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(30)

	var vp := get_viewport()
	var full: Image = vp.get_texture().get_image()
	_save_strip(full, game, "/tmp/poe_bottom_menu.png")

	# Force the Empire hover look (AltGlow + Specular are created by bottom_menu.gd).
	var empire := game.find_child("EmpireButton", true, false) as Button
	if empire != null:
		var glow := empire.get_node_or_null("AltGlow") as TextureRect
		if glow != null:
			glow.visible = true
		await _settle(6)
		if glow != null:
			glow.visible = true   # re-assert: a stray hover signal can reset it mid-settle
			await _settle(2)
		_save_strip(vp.get_texture().get_image(), game, "/tmp/poe_bottom_menu_hover.png")
	get_tree().quit(0)

func _save_strip(full: Image, game: Node, path: String) -> void:
	var menu := game.find_child("BottomMenu", true, false) as Control
	var rect := Rect2i(Vector2i(menu.get_global_rect().position) - Vector2i(20, 60),
			Vector2i(menu.get_global_rect().size) + Vector2i(40, 80))
	rect = rect.intersection(Rect2i(Vector2i.ZERO, full.get_size()))
	full.get_region(rect).save_png(path)
	print("SAVED ", path)

func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
