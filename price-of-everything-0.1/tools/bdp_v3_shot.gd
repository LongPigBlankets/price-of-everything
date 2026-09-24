extends Node2D
## Building Detail v3 (`toggle bdp v3`) screenshots, each cropped to the panel: its top with the
## status lamp (and again without the lamp's overlay, and without the lamp at all), the cost gauges, the lamp in each state, the body scrolled partway and to the end (the scrollbar's
## slider along its rail), the recipe sheet sliding in and settled, the Modifiers open, the economics (the motor
## factory's, closed and open, a coal power plant's and a coal mine's), and the shipments of recipes with three or four inputs and
## with five or more. Places a motor factory (r_009) with its
## inputs in stock on tile_5_10, so the panel is long enough to scroll.
##   Godot --path . res://tools/bdp_v3_shot.tscn --quit-after 3000 -- --no-telemetry
## Writes /tmp/poe_bdp_v3_*.png, or into $BDP_SHOT_DIR when it is set. tools/bdp_v3_compare.py checks
## them against the saved standard (artifacts/bdp_v3_standard/).

## The game runs in a SubViewport of a fixed size, so every capture has the same pixels whatever the
## display the window is on: LOGICAL at two pixels each.
const LOGICAL := Vector2i(1920, 1200)

var _wm
var _vp: SubViewport


func _ready() -> void:
	UiPrefs.set_use_bdp_v3(true)
	_vp = SubViewport.new()
	_vp.size = LOGICAL * 2
	_vp.size_2d_override = LOGICAL
	_vp.size_2d_override_stretch = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.gui_embed_subwindows = true
	add_child(_vp)
	var packed := load("res://scenes/main.tscn") as PackedScene
	_wm = packed.instantiate()
	_vp.add_child(_wm)
	await _settle(140)
	var cam := _vp.get_camera_2d()
	if cam != null:
		cam.edge_pan_enabled = false

	var iid: String = BuildingState.add_building("b_007", "r_009", "tile_5_10", "player_1", "bdpv3shot")
	Stockpile.add("tile_5_10", str(Catalog.get_good_by_internal_name("steel").get("id", "")), 60)
	Stockpile.add("tile_5_10", str(Catalog.get_good_by_internal_name("copper_wiring").get("id", "")), 64)
	var building: Dictionary = BuildingState.get_building(iid)
	# A cost-to-produce reading, as the cost solver would leave it: the motor under its market price,
	# steel over it, so the gauges show two zones.
	var motor := str(Catalog.get_good_by_internal_name("motor").get("id", ""))
	var steel := str(Catalog.get_good_by_internal_name("steel").get("id", ""))
	CostSolver.last_result = {"per_building": {iid: {"output_good_id": motor, "unit_cost": Catalog.get_base_price(motor) * 0.72,
		"output_costs": {motor: Catalog.get_base_price(motor) * 0.72, steel: Catalog.get_base_price(steel) * 1.28}}}, "per_good": {}}
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
	print("[BDP_V3_SHOT] viewport %s, panel %s" % [_vp.get_visible_rect().size, panel.get_global_rect()])
	panel._shade.visible = true
	await _settle(3)

	for st in [["Running", "ok"], ["Starting", "warn"], ["Stalled", "bad"], ["NPC-owned", "info"]]:
		panel._set_badge({"label": st[0], "tone": st[1]})
		await _settle(3)
		_save(panel, "lamp_" + str(st[1]))
	panel._set_badge(load("res://scripts/building_readout.gd").status(building, Catalog.get_recipe("r_009"), false))

	var bar: VScrollBar = panel._scroll.get_v_scroll_bar()
	panel._scroll.scroll_vertical = int((bar.max_value - bar.page) * 0.3)
	await _settle(6)
	_save(panel, "cost")
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
	await _settle(4)
	_save(panel, "sheet_sliding")
	await get_tree().create_timer(0.5).timeout
	_save(panel, "sheet")
	panel._close_sheet()

	# The Modifiers key latched down, its white sheet open under it.
	panel._v3_modifiers_open = true
	panel._rebuild(building)
	await _settle(8)
	var mod_sheet: Control = panel.find_child("ModifiersSheet", true, false)
	if mod_sheet != null:
		panel._scroll.ensure_control_visible(mod_sheet)
		await _settle(6)
		_save(panel, "modifiers")
	panel._v3_modifiers_open = false

	# The economics: the motor factory's, then a coal power plant's (output free to ship) and a coal
	# mine's (inputs free).
	var econ: Control = panel.find_child("EconomicsV3", true, false)
	if econ != null:
		panel._scroll.ensure_control_visible(econ)
		await _settle(6)
		_save(panel, "economics")
		# ...and with value added in production and transport costs open.
		panel._v3_econ_open = {"value_added": true, "transport": true}
		panel._rebuild(building)
		await _settle(8)
		econ = panel.find_child("EconomicsV3", true, false)
		panel._scroll.ensure_control_visible(econ)
		await _settle(6)
		_save(panel, "economics_open")
		panel._v3_econ_open = {}
		panel._rebuild(building)
		await _settle(4)
	for pair in [["b_003", "r_004", "economics_power"], ["b_001", "r_001", "economics_mine"]]:
		var iid_e: String = BuildingState.add_building(pair[0], pair[1], "tile_5_10", "player_1", "bdpv3shot_" + str(pair[2]))
		_wm._open_building_detail(BuildingState.get_building(iid_e))
		await _settle(20)
		var card: Control = _wm.building_panel_v2.find_child("EconomicsV3", true, false)
		if card != null:
			_wm.building_panel_v2._scroll.ensure_control_visible(card)
			await _settle(8)
			_save(_wm.building_panel_v2, str(pair[2]))

	# The shipments of a recipe with three or four inputs (the door down over the bay's empty top row) and
	# of one with five or more (the door rolled up). The first input is stocked, so its lamp is green and
	# the others red.
	var some := ""
	var many := ""
	for r: Dictionary in Catalog.get_recipes_for_building("b_007"):
		var n := (r.get("inputs", []) as Array).size()
		if n >= 3 and n <= 4 and some == "":
			some = str(r.get("recipe_id", ""))
		elif n >= 5 and many == "":
			many = str(r.get("recipe_id", ""))
	print("[BDP_V3_SHOT] shipments recipes: %s (3-4 inputs), %s (5+ inputs)" % [some, many])
	for pair in [[some, "shipments_some"], [many, "shipments_many"]]:
		if str(pair[0]) == "":
			continue
		var iid_n: String = BuildingState.add_building("b_007", pair[0], "tile_5_10", "player_1", "bdpv3shot_" + str(pair[1]))
		var first: Dictionary = (Catalog.get_recipe(pair[0]).get("inputs", []) as Array)[0]
		Stockpile.add("tile_5_10", str(first.get("good_id", "")), int(first.get("qty", 0)) * 2)
		_wm._open_building_detail(BuildingState.get_building(iid_n))
		await _settle(20)
		var ships: Control = _wm.building_panel_v2.find_child("ShipmentsV3", true, false)
		if ships != null:
			_wm.building_panel_v2._scroll.ensure_control_visible(ships.get_parent().get_parent())
			await _settle(8)
			_save(_wm.building_panel_v2, str(pair[1]))
	get_tree().quit(0)


func _save(panel: Control, tag: String) -> void:
	var img := _vp.get_texture().get_image()
	var k := img.get_width() / _vp.get_visible_rect().size.x
	var r := panel.get_global_rect().grow(6.0)
	var crop := Rect2i(Vector2i(r.position * k), Vector2i(r.size * k)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var path := _out_dir().path_join("poe_bdp_v3_%s.png" % tag)
	img.get_region(crop).save_png(path)
	print("[BDP_V3_SHOT] saved %s" % path)


func _save_bar(bar: Control, tag: String) -> void:
	var img := _vp.get_texture().get_image()
	var k := img.get_width() / _vp.get_visible_rect().size.x
	var r := bar.get_global_rect().grow(4.0)
	var crop := Rect2i(Vector2i(r.position * k), Vector2i(r.size * k)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var path := _out_dir().path_join("poe_bdp_v3_%s.png" % tag)
	img.get_region(crop).save_png(path)
	print("[BDP_V3_SHOT] saved %s" % path)


func _out_dir() -> String:
	var dir := OS.get_environment("BDP_SHOT_DIR")
	return dir if dir != "" else "/tmp"


func _settle(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
