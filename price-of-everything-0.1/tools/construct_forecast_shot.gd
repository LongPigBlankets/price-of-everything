extends Node2D
## Verification for the build-forecast section in the construct panel's CONFIRM view.
## Loads the real main scene, opens Construct, and drives it to the confirm step for a real
## building + recipe so the trajectory chart renders at true panel width.
##   Godot --path . res://tools/construct_forecast_shot.tscn --quit-after 1200
## Writes res://construct_forecast_shot.png

var _wm


func _ready() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	_wm = packed.instantiate()
	add_child(_wm)
	await _settle(140)
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		cam.edge_pan_enabled = false

	# bottom_menu.gd is attached to the HUD node itself, not to a node called BottomMenu.
	var menu = _wm.get_node_or_null("UILayer/HUD")
	if menu == null or menu.get("construct_panel_v2") == null:
		print("[FORECAST_SHOT] construct panel v2 not found — aborting")
		get_tree().quit(1)
		return
	var panel = menu.construct_panel_v2

	# Confirm view for pig iron smelting on the magnate's smelter tile: a real recipe with a
	# real dip and a real steady margin.
	panel.show()
	panel._locked_tile_id = "tile_5_10"
	panel._on_recipe_pressed("b_002", "r_005")
	await _settle(12)

	# The forecast sits below the materials grid, so scroll it into frame.
	if panel._scroll != null:
		panel._scroll.scroll_vertical = 10000
		await _settle(6)

	print("[FORECAST_SHOT] view=%s money=%.2f scroll=%d" % [
		str(panel._view), MatchState.money, panel._scroll.scroll_vertical if panel._scroll else -1])
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://construct_forecast_shot.png")
	print("SAVED construct_forecast_shot.png")
	get_tree().quit()


func _settle(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
