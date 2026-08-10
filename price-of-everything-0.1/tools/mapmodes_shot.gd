extends Node2D
## Dev tool: render the Mapmodes panel. The panel self-sizes to its rows
## (mapmodes_panel._resize_to_content) and is capped at the bottom menu's top, so every added
## mapmode row is a chance for the list to start scrolling instead of growing — the print below
## says which of the two happened.
##   "$GODOT_BIN" --path . res://tools/mapmodes_shot.tscn --quit-after 900
var _wm
func _ready() -> void:
	get_window().size = Vector2i(1920, 1080)
	_wm = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_wm)
	for _i in range(160):
		await get_tree().process_frame
	var hud = _wm.get_node_or_null("UILayer/HUD")
	var panel = hud.mapmodes_panel if hud != null else null
	if panel == null:
		print("[MAPMODES_SHOT] panel not found"); get_tree().quit(1); return
	panel.show()
	for _i in range(16):
		await get_tree().process_frame

	var scroll: ScrollContainer = panel.scroll
	var content: Control = panel.content_vbox
	var wanted: float = content.get_combined_minimum_size().y
	var got: float = scroll.custom_minimum_size.y
	var rows: int = panel.ROWS.size()
	print("[MAPMODES_SHOT] rows=%d panel=%s bottom=%.0f rows_need=%.0f rows_got=%.0f scrolling=%s" % [
		rows, str(panel.size), panel.global_position.y + panel.size.y, wanted, got,
		str(got + 0.5 < wanted)])
	var menu := _wm.find_child("BottomMenu", true, false) as Control
	if menu != null:
		print("[MAPMODES_SHOT] clears bottom menu=%s (panel bottom %.0f vs menu top %.0f)" % [
			str(panel.global_position.y + panel.size.y <= menu.global_position.y),
			panel.global_position.y + panel.size.y, menu.global_position.y])
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://mapmodes_shot.png")
	print("SAVED mapmodes_shot.png")
	get_tree().quit()
