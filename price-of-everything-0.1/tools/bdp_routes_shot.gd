extends Node2D
## Building Detail v3's Input sources and Output destination sheets in DS2 (UiPrefs.use_routes_ds2,
## scripts/bdp_v3_routes.gd), cropped to the panel: a motor factory's inputs and output; an option hovered;
## the output split between two tiles; the same factory in a Logistics Intermediary game (Source and
## Fallback knobs, the All inputs and All outputs knobs); a coal power plant's output.
##   Godot --path . res://tools/bdp_routes_shot.tscn --quit-after 4000 -- --no-telemetry
## Writes poe_bdp_routes_*.png into $BDP_SHOT_DIR (or /tmp).

## The game runs in a SubViewport of a fixed size, so every capture has the same pixels whatever the
## display the window is on: LOGICAL at two pixels each.
const LOGICAL := Vector2i(1920, 1200)

var _wm
var _vp: SubViewport


func _ready() -> void:
	UiPrefs.set_use_bdp_v3(true)
	UiPrefs.use_routes_ds2 = true
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
	var recipe := Catalog.get_recipe("r_009")
	print("[BDP_ROUTES_SHOT] panel %s, its minimum %s, PANEL_WIDTH %s" % [panel.get_global_rect(), panel.get_combined_minimum_size(), panel.PANEL_WIDTH])
	panel._open_input_sources_sheet(building, recipe)
	await _settle(30)
	_save(panel, "inputs")
	for n in ["ActionSheet", "SheetClip", "SheetSlide", "SheetMargin", "RoutesReadout", "ActionSheetScroll", "InputPlates"]:
		var c: Control = panel.find_child(n, true, false)
		if c != null:
			print("[BDP_ROUTES_SHOT] %s %s min %s" % [n, c.get_global_rect(), c.get_combined_minimum_size()])
	print("[BDP_ROUTES_SHOT] panel now %s" % panel.get_global_rect())
	var option: Button = panel.find_child("RouteOption_GlobalMarket", true, false)
	if option != null:
		option.mouse_entered.emit()
		await _settle(4)
		_save(panel, "inputs_hover")
	panel._open_output_sheet(building, recipe)
	await _settle(30)
	_save(panel, "outputs")
	# The motor split between this tile and the next, one share typed in.
	MatchState.add_output_split_destination(iid, motor, "tile_5_10")
	MatchState.add_output_split_destination(iid, motor, "tile_6_10")
	MatchState.set_output_split_quantity(iid, motor, "tile_6_10", 12)
	panel._open_output_sheet(building, recipe)
	await _settle(30)
	_save(panel, "outputs_split")
	MatchState.route_output_to_market(iid, motor)
	# A Logistics Intermediary game: the licence and the contracts researched.
	MatchState.ruleset["logistics_model"] = "middleman_v1"
	for title in [ResearchState.GLOBAL_TRADE_LICENSE_TITLE, ResearchState.OPEN_LOGISTICS_CONTRACTS_TITLE]:
		ResearchState.grant_unlock(title)
	panel._close_sheet()
	_wm._open_building_detail(BuildingState.get_building(iid))
	await _settle(20)
	panel._open_input_sources_sheet(BuildingState.get_building(iid), recipe)
	await _settle(30)
	_save(panel, "inputs_intermediary")
	var scroll: ScrollContainer = panel.find_child("ActionSheetScroll", true, false)
	if scroll != null:
		scroll.scroll_vertical = 100000
		await _settle(6)
		_save(panel, "inputs_intermediary_end")
	panel._open_output_sheet(BuildingState.get_building(iid), recipe)
	await _settle(30)
	_save(panel, "outputs_intermediary")
	MatchState.ruleset["logistics_model"] = ""
	# A coal power plant's output.
	var plant: String = BuildingState.add_building("b_003", "r_004", "tile_5_10", "player_1", "bdproutes_power")
	panel._close_sheet()
	_wm._open_building_detail(BuildingState.get_building(plant))
	await _settle(20)
	panel._open_output_sheet(BuildingState.get_building(plant), Catalog.get_recipe("r_004"))
	await _settle(30)
	_save(panel, "outputs_power")
	print("[BDP_ROUTES_SHOT] done")
	get_tree().quit(0)


func _save(panel: Control, tag: String) -> void:
	var img := _grab()
	var k := img.get_width() / _vp.get_visible_rect().size.x
	var r := panel.get_global_rect().grow(6.0)
	var crop := Rect2i(Vector2i(r.position * k), Vector2i(r.size * k)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var path := _out_dir().path_join("poe_bdp_routes_%s.png" % tag)
	img.get_region(crop).save_png(path)
	print("[BDP_ROUTES_SHOT] saved %s" % path)


func _save_bar(bar: Control, tag: String) -> void:
	var img := _grab()
	var k := img.get_width() / _vp.get_visible_rect().size.x
	var r := bar.get_global_rect().grow(4.0)
	var crop := Rect2i(Vector2i(r.position * k), Vector2i(r.size * k)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var path := _out_dir().path_join("poe_bdp_routes_%s.png" % tag)
	img.get_region(crop).save_png(path)
	print("[BDP_ROUTES_SHOT] saved %s" % path)


## The SubViewport's current picture. Drawn here, not taken from the last frame: macOS stops the game
## drawing while no window can be seen (the screen locked or asleep), though the run goes on, so a
## capture would repeat the last frame drawn.
func _grab() -> Image:
	RenderingServer.force_draw(false)
	return _vp.get_texture().get_image()


func _primary_output(recipe: Dictionary) -> String:
	return load("res://scripts/building_status.gd").primary_output_good_id(recipe)


func _output_qty(recipe: Dictionary, gid: String) -> int:
	for o: Dictionary in load("res://scripts/building_status.gd").flow_output_items(recipe):
		if str(o.get("good_id", "")) == gid:
			return int(o.get("qty", 0))
	return 0


func _out_dir() -> String:
	var dir := OS.get_environment("BDP_SHOT_DIR")
	return dir if dir != "" else "/tmp"


func _settle(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
