extends Node
## One-off headless probe: instantiate the real game scene, open the pause menu
## and both save/load screens, and print every control rect so misplacement is
## visible without a GUI. Run: <godot> --headless res://tests/ui_probe.tscn

func _ready() -> void:
	var inst: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(inst)
	await get_tree().process_frame
	await get_tree().process_frame
	var hud: Control = inst.get_node("UILayer/HUD")
	print("viewport size: ", get_viewport().get_visible_rect().size)
	print("HUD rect: ", hud.get_global_rect())

	var menu: PauseMenu = PauseMenu.open(hud)
	await get_tree().process_frame
	await get_tree().process_frame
	print("\n--- PauseMenu ---")
	print("root anchors: L=%s T=%s R=%s B=%s offsets: L=%s T=%s R=%s B=%s" % [
		menu.anchor_left, menu.anchor_top, menu.anchor_right, menu.anchor_bottom,
		menu.offset_left, menu.offset_top, menu.offset_right, menu.offset_bottom])
	_dump(menu, 0)
	menu.hide()
	await get_tree().process_frame

	var screen: SaveLoadScreen = SaveLoadScreen.open(hud, SaveLoadScreen.Mode.SAVE)
	await get_tree().process_frame
	await get_tree().process_frame
	print("\n--- SaveLoadScreen (SAVE) ---")
	_dump(screen, 0)
	screen.hide()
	await get_tree().process_frame
	get_tree().quit(0)

func _dump(node: Node, depth: int) -> void:
	if node is Control:
		var c: Control = node
		print("%s%s [%s] rect=%s visible=%s mouse=%d" % [
			"  ".repeat(depth), c.name, c.get_class(), c.get_global_rect(), c.visible, c.mouse_filter])
	for child in node.get_children():
		_dump(child, depth + 1)
