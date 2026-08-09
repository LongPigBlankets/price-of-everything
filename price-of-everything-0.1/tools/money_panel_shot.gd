extends Node2D
## Renders the money panel's Balance tab. Exists because a runtime reparent of BalanceContent
## emptied this tab and shipped unnoticed — the unit suite cannot see a blank panel.
var _wm
func _ready() -> void:
	get_window().size = Vector2i(900, 760)
	_wm = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_wm)
	for _i in range(160):
		await get_tree().process_frame
	var menu = _wm.get_node_or_null("UILayer/HUD")
	if menu == null or menu.money_panel == null:
		print("[MONEY_SHOT] money panel not found"); get_tree().quit(1); return
	var panel = menu.money_panel
	panel.show()
	for _i in range(12):
		await get_tree().process_frame
	var content = panel.get_node_or_null("MarginContainer/ModalLayout/TabContainer/Balance/MarginContainer/BalanceContent")
	print("[MONEY_SHOT] visible=%s balance_content=%s size=%s children=%d" % [
		str(panel.visible), "found" if content else "MISSING",
		str(content.size) if content else "-", content.get_child_count() if content else -1])
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://money_panel_shot.png")
	print("SAVED money_panel_shot.png")
	get_tree().quit()
