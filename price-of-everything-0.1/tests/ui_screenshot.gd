extends Node
## Renders the real scenes with the new save/load UI open and saves viewport
## screenshots to /tmp for visual inspection. Needs a window (NOT --headless):
##   <godot> --path . res://tests/ui_screenshot.tscn

func _ready() -> void:
	# Fixture saves so the load list has rows.
	SaveLoad.save_slot("screenshot_fixture_a")
	SaveLoad.save_slot("screenshot_fixture_b")

	# 1. Main menu with the Load Game screen open.
	var menu_scene: Node = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	add_child(menu_scene)
	await _settle(8)
	SaveLoadScreen.open(menu_scene, SaveLoadScreen.Mode.LOAD)
	await _settle(8)
	_shot("/tmp/poe_mainmenu_load.png")
	menu_scene.queue_free()
	await _settle(3)

	# 2. In-game: Esc pause menu, then the Save Game screen.
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(20)
	var hud: Control = game.get_node("UILayer/HUD")
	var pause: PauseMenu = PauseMenu.open(hud)
	await _settle(8)
	_shot("/tmp/poe_pause.png")
	pause.hide()
	await _settle(3)
	SaveLoadScreen.open(hud, SaveLoadScreen.Mode.SAVE)
	await _settle(8)
	_shot("/tmp/poe_save.png")

	DirAccess.remove_absolute("user://saves/screenshot_fixture_a.json")
	DirAccess.remove_absolute("user://saves/screenshot_fixture_b.json")
	get_tree().quit(0)

func _shot(path: String) -> void:
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)

func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
