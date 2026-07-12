extends Node
## Windowed shot of the "proceed without the Tutorial?" prompt: boot the real main
## menu, force the profile to "tutorial not done", click New Game, capture the modal.
##   <godot> --path . res://tools/tutorial_prompt_shot.tscn --quit-after 900

func _ready() -> void:
	PlayerProfile.tutorial_completed = false   # guarantee the prompt fires
	var menu: Node = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	add_child(menu)
	await _settle(30)
	menu.call("_on_new_game_pressed")
	await _settle(20)
	var prompt: Control = menu.get("_tutorial_prompt")
	print("[SHOT] prompt visible on New Game (tutorial not done) = ", prompt.visible)
	var out := ProjectSettings.globalize_path("res://tutorial_prompt.png")
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)

	# CTA 1: press the real "Go to Tutorial" button (its lambda closes the prompt).
	var go := _find_link(prompt, "Go to Tutorial")
	if go != null:
		go.pressed.emit()
	await _settle(20)
	print("[SHOT] after Go to Tutorial: prompt visible=", prompt.visible,
		" tutorial_panel visible=", menu.get("_tutorial_panel").visible)

	# CTA 2: reopen, press the "New Game without Tutorial" link.
	menu.call("_on_new_game_pressed")
	await _settle(15)
	var link := _find_link(prompt, "New Game without Tutorial")
	if link != null:
		link.pressed.emit()
	await _settle(20)
	print("[SHOT] after Proceed link: prompt visible=", prompt.visible,
		" new_game_panel visible=", menu.get("_new_game_panel").visible)

	# Gate: once the tutorial is done, New Game skips the prompt entirely.
	PlayerProfile.tutorial_completed = true
	menu.get("_new_game_panel").visible = false
	menu.call("_on_new_game_pressed")
	await _settle(15)
	print("[SHOT] tutorial done → prompt visible=", prompt.visible,
		" (expect false) new_game_panel visible=", menu.get("_new_game_panel").visible, " (expect true)")
	get_tree().quit(0)

func _find_link(root: Node, text: String) -> BaseButton:
	for n in root.find_children("*", "BaseButton", true, false):
		if str((n as BaseButton).text) == text:
			return n
	return null

func _settle(frames: int) -> void:
	for _i in range(frames):
		await get_tree().process_frame
