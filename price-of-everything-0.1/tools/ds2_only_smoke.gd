extends Node
## Boots a Metal Magnate game windowed and opens every DS2 panel in turn, a capture each.
##   AGENT_GODOT_WINDOW=1 godot --path . res://tools/ds2_only_smoke.tscn -- --no-telemetry
## Writes <nn>_<panel>.png to DS2_SMOKE_DIR (default user://ds2_smoke).

const Harness := preload("res://tools/shot_harness.gd")

var _dir := ""
var _world: Node
var _hud: Node
var _bar: Node
var _n := 0


func _ready() -> void:
	Harness.prepare_window(get_window(), Vector2i(1920, 1080))
	Harness.arm_watchdog(self, 400.0)
	AudioServer.set_bus_mute(0, true)
	TelemetryState.set_next_run_consent(false, false)
	_dir = OS.get_environment("DS2_SMOKE_DIR")
	if _dir == "":
		_dir = OS.get_user_data_dir().path_join("ds2_smoke")
	DirAccess.make_dir_recursive_absolute(_dir)
	SaveLoad.prepare_new_game("res://data/starts/metal_magnate.json", {})
	_world = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_world)
	await _wait(25.0, func() -> bool: return _world.get("build_complete") == true)
	_world.call("reveal_for_play")
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		cam.set("edge_pan_enabled", false)
	DecisionState.enabled = false
	_hud = _world.get_node("UILayer/HUD")
	_bar = _world.find_child("TopBar", true, false)
	TurnManager.fast_mode = true
	for _i in 2:
		TurnManager.commit_turn()
		if TurnManager.is_resolving:
			await TurnManager.turn_resolution_completed
		await _sleep(0.5)
	_dismiss_intro(get_tree().root)
	await _sleep(0.5)
	var iid := ""
	for id: String in BuildingState.buildings:
		var b: Dictionary = BuildingState.buildings[id]
		if BuildingState.is_player_owned(b) and str(Catalog.get_building(str(b.get("building_id", ""))).get("category", "")) != "infrastructure":
			iid = id
			break
	var tile := str(BuildingState.get_building(iid).get("tile_id", "tile_5_10")) if iid != "" else "tile_5_10"
	print("[SMOKE] building %s on %s" % [iid, tile])

	await _shot("top_bar_and_desk")
	MatchState.focus_tile_requested.emit(tile)
	await _shot("tile_view")
	_close_all()
	if iid != "":
		MatchState.focus_building_requested.emit(iid)
		await _shot("building_detail")
		var bdp: Node = _world.get("building_panel_v2")
		bdp.call("_open_input_sources_sheet", BuildingState.get_building(iid), Catalog.get_recipe(str(BuildingState.get_building(iid).get("recipe_id", ""))))
		await _shot("building_detail_inputs")
		bdp.call("_close_sheet")
		bdp.call("_open_upgrade_sheet", BuildingState.get_building(iid))
		await _shot("upgrade")
		var dialog: Node = bdp.get("_upgrade_dialog")
		if dialog != null:
			dialog.call("close")
	_close_all()
	await _menu("_on_buildings_pressed", "ledger")
	await _menu("_on_resources_pressed", "resources")
	await _menu("_on_politics_pressed", "politics")
	MatchState.transport_panel_requested.emit()
	await _shot("shipments")
	_close_all()
	await _menu("_on_people_pressed", "people")
	await _menu("_on_market_pressed", "market")
	await _menu("_on_construct_pressed", "construct")
	TurnBriefing.expand("")
	await _shot("briefing")
	TurnBriefing.collapse()
	_close_all()
	_bar.call("_open_fly", "quest")
	await _shot("missions")
	_bar.call("_close_fly")
	_bar.call("_open_fly", "treasury")
	await _shot("treasury")
	_bar.call("_close_fly")
	_bar.call("_module_pressed", "victory")
	await _shot("victory")
	_close_all()
	MatchState.goods_graph_requested.emit()
	await _shot("goods_graph")
	_close_all()
	MatchState.empire_view_requested.emit()
	await _shot("supply_chain")
	_close_all()
	PauseMenu.open(_world.get("_hud"))
	await _shot("pause_menu")
	print("[SMOKE] done, %d captures" % _n)
	get_tree().quit(0)


func _menu(opener: String, label: String) -> void:
	_hud.call("_hide_all_panels")
	_hud.call(opener)
	await _shot(label)
	_close_all()


func _close_all() -> void:
	for _i in 6:
		if not PanelStack.close_top():
			break
	if _hud != null:
		_hud.call("_hide_all_panels")
	for prop: String in ["info_panel", "building_panel_v2"]:
		var p := _world.get(prop) as Control
		if p != null:
			p.hide()
	for view: String in ["EmpireView", "GoodsGraphView"]:
		var v := _world.find_child(view, true, false) as CanvasItem
		if v != null and v.visible:
			v.hide()


func _dismiss_intro(n: Node) -> void:
	for c: Node in n.get_children():
		_dismiss_intro(c)
	var sc: Script = n.get_script() as Script
	if sc != null and sc.resource_path.ends_with("_intro.gd") and n.has_method("_on_begin"):
		n.call("_on_begin")


func _shot(label: String) -> void:
	await _sleep(1.2)
	RenderingServer.force_draw(false)
	var img := get_viewport().get_texture().get_image()
	var path := _dir.path_join("%02d_%s.png" % [_n, label])
	img.save_png(path)
	img = null
	_n += 1
	print("[SMOKE] saved %s" % path)


func _sleep(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame


func _wait(max_seconds: float, done: Callable) -> void:
	var until := Time.get_ticks_msec() + int(max_seconds * 1000.0)
	while Time.get_ticks_msec() < until and not done.call():
		await get_tree().process_frame
	await _sleep(1.0)
