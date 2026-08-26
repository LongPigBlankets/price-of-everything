extends Node2D
## Verification shot for the Construct V3 confirm redesign (`swap construct_panel_v3`).
## Loads the real main scene, enables the V3 cheat, and drives the construct panel to
## the confirm step so the gated visuals render: ruled section heads, raised muted
## tone, borderless cream icon plates, and the brass Confirm.
##   Godot --path . res://tools/construct_v3_shot.tscn --quit-after 1200
## Writes res://construct_v3_shot_top.png and res://construct_v3_shot_bottom.png

var _wm


func _ready() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	_wm = packed.instantiate()
	add_child(_wm)
	await _settle(140)
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		cam.edge_pan_enabled = false

	MatchState.set_use_construct_panel_v3(true)

	# bottom_menu.gd is attached to the HUD node itself, not to a node called BottomMenu.
	var menu = _wm.get_node_or_null("UILayer/HUD")
	if menu == null or menu.get("construct_panel_v2") == null:
		print("[V3_SHOT] construct panel v2 not found — aborting")
		get_tree().quit(1)
		return
	var panel = menu.construct_panel_v2

	# Confirm view for pig iron smelting on the magnate's smelter tile — the same
	# scenario the forecast shot uses, so before/after comparisons line up.
	panel.show()
	panel._locked_tile_id = "tile_5_10"
	panel._on_recipe_pressed("b_002", "r_005")
	await _settle(12)

	print("[V3_SHOT] v3=%s view=%s money=%.2f" % [
		str(MatchState.use_construct_panel_v3), str(panel._view), MatchState.money])
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://construct_v3_shot_top.png")
	print("SAVED construct_v3_shot_top.png")

	if panel._scroll != null:
		panel._scroll.scroll_vertical = 10000
		await _settle(6)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://construct_v3_shot_bottom.png")
	print("SAVED construct_v3_shot_bottom.png")

	# Third: the land toggle unticked — new in v3.1.
	panel._scroll.scroll_vertical = 0
	var land_toggle: Button = panel.find_child("V3LandToggle", true, false)
	if land_toggle != null:
		land_toggle.button_pressed = false
		land_toggle.toggled.emit(false)
		await _settle(4)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://construct_v3_shot_land_off.png")
		print("SAVED construct_v3_shot_land_off.png")
	else:
		print("[V3_SHOT] no V3LandToggle found — skipping land-off shot")

	# Fourth: an intermittent-power building — the priority-supply preview band.
	var solar_recipe_id := ""
	for recipe in Catalog.all_recipes():
		if str(recipe.get("building_id", "")) == "b_024":
			solar_recipe_id = str(recipe.get("recipe_id", ""))
			break
	if solar_recipe_id != "":
		panel._locked_tile_id = "tile_5_10"
		panel._on_recipe_pressed("b_024", solar_recipe_id)
		await _settle(6)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://construct_v3_shot_solar.png")
		print("SAVED construct_v3_shot_solar.png")
	else:
		print("[V3_SHOT] no solar-farm recipe found (b_024) — skipping priority-supply shot")

	get_tree().quit()


func _settle(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
