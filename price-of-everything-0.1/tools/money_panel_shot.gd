extends Node2D
## Renders the money panel's Balance tab. Exists because a runtime reparent of BalanceContent
## emptied this tab and shipped unnoticed — the unit suite cannot see a blank panel.
var _wm
func _ready() -> void:
	get_window().size = Vector2i(1920, 1080)   # the playtester's screen
	_wm = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_wm)
	for _i in range(160):
		await get_tree().process_frame
	var menu = _wm.get_node_or_null("UILayer/HUD")
	if menu == null or menu.money_panel == null:
		print("[MONEY_SHOT] money panel not found"); get_tree().quit(1); return
	var panel = menu.money_panel
	panel.show()
	# The panel sizes itself now (_fit_to_screen); forcing it here would mask that.
	for _i in range(12):
		await get_tree().process_frame
	# find_child, not a fixed path: BalanceContent moves under BalanceScroll at runtime.
	var content = panel.find_child("BalanceContent", true, false)
	# What the player can actually SEE versus what the sheet is: the gap is the bug.
	var tab = panel.find_child("TabContainer", true, false)
	print("[MONEY_SHOT] window=%s panel=%s tab_h=%.0f content_h=%.0f children=%d" % [
		str(get_window().size), str(panel.size),
		(tab.size.y if tab else -1.0), (content.size.y if content else -1.0),
		content.get_child_count() if content else -1])
	var fits_screen: bool = panel.size.y <= get_window().size.y
	print("[MONEY_SHOT] fits_screen=%s scrolls=%s" % [
		str(fits_screen), str(content and tab and content.size.y > tab.size.y)])
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://money_panel_shot.png")
	print("SAVED money_panel_shot.png")
	get_tree().quit()
