extends Node
## Checks the cheat-gated Map Editor entry end to end, in a real running menu:
## boot main_menu.tscn, run `debug CandC` through the terminal exactly as a player would,
## and report whether the button becomes visible.
##
##   <godot> --path . res://tools/map_editor/menu_gate_check.tscn --quit-after 900
##
## WINDOWED. Autoloads must exist, so this cannot be a bare --script run.

func _ready() -> void:
	var menu := (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	add_child(menu)
	for _i in 30:
		await get_tree().process_frame

	var terminal_script: Variant = load("res://scripts/debug_terminal.gd")
	print("[GATE] static accessor reachable on a loaded script: ",
		terminal_script.has_method("cheats_are_unlocked"))

	var button: Button = _find_button(menu, "Map Editor")
	print("[GATE] button found=%s visible_before=%s" % [button != null, button != null and button.visible])

	var terminal: Node = null
	for child in menu.get_children():
		if child.get_script() == terminal_script:
			terminal = child
	print("[GATE] terminal in menu=", terminal != null)
	if terminal == null:
		get_tree().quit(1)
		return
	print("[GATE] signal connected=", terminal.is_connected("cheats_unlocked",
		Callable(menu, "_on_cheats_unlocked")))

	var reply: Variant = terminal.call("_run_command", "debug CandC")
	print("[GATE] reply=", reply)
	print("[GATE] cheats_are_unlocked()=", terminal_script.call("cheats_are_unlocked"))
	await get_tree().process_frame
	print("[GATE] visible_after=", button != null and button.visible)
	# visible == true is NOT the same as on screen: a button can be laid out past the bottom
	# of its panel, or clipped by it. Report the rect and capture the frame.
	if button != null:
		print("[GATE] button rect=%s  window=%s" % [button.get_global_rect(), get_window().size])
	for _i in 10:
		await get_tree().process_frame
	RenderingServer.force_draw()
	get_viewport().get_texture().get_image().save_png("/tmp/poe_menu_gate.png")
	print("[GATE] wrote /tmp/poe_menu_gate.png")
	print("[GATE] RESULT=%s" % ("PASS" if (button != null and button.visible) else "FAIL"))
	get_tree().quit(0)


func _find_button(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text == text:
		return node
	for child in node.get_children():
		var found := _find_button(child, text)
		if found != null:
			return found
	return null
