extends Node2D
## Building Detail v3 (`toggle bdp v3`) screenshots, each cropped to the panel: its top with the
## status lamp (and again without the lamp's overlay, and without the lamp at all), the lamp in each state, the body scrolled partway and to the end (the scrollbar's
## slider along its rail), and the recipe sheet's scrollbar. Places a motor factory (r_009) with its
## inputs in stock on tile_5_10, so the panel is long enough to scroll.
##   Godot --path . res://tools/bdp_v3_shot.tscn --quit-after 3000 -- --no-telemetry
## Writes /tmp/poe_bdp_v3_*.png.

var _wm


func _ready() -> void:
	UiPrefs.set_use_bdp_v3(true)
	var packed := load("res://scenes/main.tscn") as PackedScene
	_wm = packed.instantiate()
	add_child(_wm)
	await _settle(140)
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		cam.edge_pan_enabled = false

	var iid: String = BuildingState.add_building("b_007", "r_009", "tile_5_10", "player_1", "bdpv3shot")
	Stockpile.add("tile_5_10", str(Catalog.get_good_by_internal_name("steel").get("id", "")), 60)
	Stockpile.add("tile_5_10", str(Catalog.get_good_by_internal_name("copper_wiring").get("id", "")), 64)
	var building: Dictionary = BuildingState.get_building(iid)
	# Open the tile view panel too, so the detail panel matches its height as it does in play.
	var coord: Vector2i = _wm.terrain_layer.id_to_coord("tile_5_10")
	var tile_data: Dictionary = _wm.terrain_layer.tiles.get(coord, {})
	if _wm.info_panel != null and not tile_data.is_empty():
		_wm.info_panel.show_tile(tile_data)
	await _settle(10)
	_wm._open_building_detail(building)
	await _settle(24)
	var panel = _wm.building_panel_v2
	_save(panel, "top")
	# The same view without the lamp's overlay, to measure what the overlay does (the ratio of the two).
	panel._shade.visible = false
	await _settle(3)
	_save(panel, "top_unshaded")
	# And with the text's give-back off too: the panel as it would be with no lamp at all.
	for n in panel._margin.find_children("*", "Label", true, false):
		(n as CanvasItem).material = null
	await _settle(3)
	_save(panel, "top_unlit")
	panel._apply_v3_text_light()
	print("[BDP_V3_SHOT] viewport %s, panel %s" % [get_viewport().get_visible_rect().size, panel.get_global_rect()])
	panel._shade.visible = true
	await _settle(3)

	for st in [["Running", "ok"], ["Starting", "warn"], ["Stalled", "bad"], ["NPC-owned", "info"]]:
		panel._set_badge({"label": st[0], "tone": st[1]})
		await _settle(3)
		_save(panel, "lamp_" + str(st[1]))
	panel._set_badge(load("res://scripts/building_readout.gd").status(building, Catalog.get_recipe("r_009"), false))

	var bar: VScrollBar = panel._scroll.get_v_scroll_bar()
	panel._scroll.scroll_vertical = int((bar.max_value - bar.page) * 0.45)
	await _settle(6)
	_save(panel, "mid")
	panel._scroll.scroll_vertical = int(bar.max_value)
	await _settle(6)
	_save(panel, "bottom")

	# The slider's hover and held tints, each drawn in the slider's place (Godot picks them itself as
	# the pointer moves and presses; this shows what each draws).
	panel._scroll.scroll_vertical = int((bar.max_value - bar.page) * 0.5)
	await _settle(4)
	var normal: StyleBox = bar.get_theme_stylebox(&"grabber")
	for state in ["normal", "highlight", "pressed"]:
		bar.add_theme_stylebox_override(&"grabber", normal if state == "normal" else bar.get_theme_stylebox("grabber_" + state))
		bar.queue_redraw()
		await _settle(4)
		_save_bar(bar, "thumb_" + state)
	bar.add_theme_stylebox_override(&"grabber", normal)
	panel._scroll.scroll_vertical = 0

	panel._open_recipe_sheet(building)
	await _settle(10)
	_save(panel, "sheet")
	panel._close_sheet()
	get_tree().quit(0)


func _save(panel: Control, tag: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var k := img.get_width() / get_viewport().get_visible_rect().size.x
	var r := panel.get_global_rect().grow(6.0)
	var crop := Rect2i(Vector2i(r.position * k), Vector2i(r.size * k)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var path := "/tmp/poe_bdp_v3_%s.png" % tag
	img.get_region(crop).save_png(path)
	print("[BDP_V3_SHOT] saved %s" % path)


func _save_bar(bar: Control, tag: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var k := img.get_width() / get_viewport().get_visible_rect().size.x
	var r := bar.get_global_rect().grow(4.0)
	var crop := Rect2i(Vector2i(r.position * k), Vector2i(r.size * k)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var path := "/tmp/poe_bdp_v3_%s.png" % tag
	img.get_region(crop).save_png(path)
	print("[BDP_V3_SHOT] saved %s" % path)


func _settle(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
