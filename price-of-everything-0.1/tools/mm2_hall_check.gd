extends Node
## Open the Hall of Records (with a fake win for content), screenshot it, then press
## the Back button and confirm the panel closes.

func _ready() -> void:
	get_window().size = Vector2i(1920, 1080)
	PlayerProfile.wins = [
		{"date": "2026-07-12", "title": "The Full Ledger", "turn": 142, "secured": 5, "epithet": "a grand-slam victory."},
		{"date": "2026-07-09", "title": "Cash is King", "turn": 205, "secured": 1, "epithet": "richest in the land."},
	]
	var menu: Node = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	add_child(menu)
	await _settle(30)
	menu.call("_on_hall_of_records_pressed")
	await _settle(20)
	var hall: Control = menu.get("_hall_of_records_panel")
	print("[CHK] hall visible after open = ", hall.visible)
	var out := ProjectSettings.globalize_path("res://mm2_hall.png")
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)

	var back := _find_button(hall, "Back")
	print("[CHK] back button found=", back != null, " size=", (back.size if back != null else Vector2.ZERO))
	if back != null:
		back.pressed.emit()
	await _settle(25)
	print("[CHK] after Back: hall visible = ", hall.visible, " (expect false)")
	get_tree().quit(0)

func _find_button(root: Node, text: String) -> Button:
	for n in root.find_children("*", "Button", true, false):
		if str((n as Button).text) == text:
			return n
	return null

func _settle(frames: int) -> void:
	for _i in range(frames):
		await get_tree().process_frame
