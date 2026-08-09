extends Node2D
## Renders the construct panel's SETTINGS view twice: without a CFO (credit section greyed and
## the red requirement showing) and with one seated.
##   Godot --path . res://tools/construct_settings_shot.tscn --quit-after 1600
var _wm
func _ready() -> void:
	get_window().size = Vector2i(700, 1000)
	_wm = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_wm)
	for _i in range(160):
		await get_tree().process_frame
	var menu = _wm.get_node_or_null("UILayer/HUD")
	var panel = menu.construct_panel_v2 if menu else null
	if panel == null:
		print("[CS_SHOT] construct panel missing"); get_tree().quit(1); return
	await _shot(panel, "res://construct_settings_no_cfo.png", "no CFO")
	MatchState.permanent_advisor_ids = ["vera"]
	MatchState.all_seats_unlocked = true
	MatchState.assign_advisor_to_seat("cfo", "vera")
	await _shot(panel, "res://construct_settings_cfo.png", "CFO seated")
	get_tree().quit()

func _shot(panel, path: String, label: String) -> void:
	panel.show()
	panel._view = panel.View.SETTINGS
	panel._render()
	for _i in range(10):
		await get_tree().process_frame
	if panel._scroll != null:
		panel._scroll.scroll_vertical = 10000
	for _i in range(6):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("[CS_SHOT] %s cfo=%s -> %s" % [label, str(MatchState.cfo_seated()), path])
