extends Node
## Boots a Metal Magnate game windowed with the Research panel's DS2 look on (UiPrefs.use_research_ds2) and
## captures it: Extraction with a mix of states (some granted, one licensed, progress on others), the big
## drawers (Chemistry, Infrastructure, Renewable Power), a search and a search narrowed to one drawer, licence
## choosing, a drawing pointed at with its threads, close crops of a granted and an in progress drawing, and the
## same panel in a 1280 x 720 window.
##   AGENT_GODOT_WINDOW=1 godot --path . res://tools/research_ds2_shot.tscn -- --no-telemetry
## Writes <nn>_<view>.png to RESEARCH_SHOT_DIR (default user://research_ds2).

const Harness := preload("res://tools/shot_harness.gd")

var _dir := ""
var _world: Node
var _panel: Control
var _view: Control
var _n := 0


func _ready() -> void:
	Harness.prepare_window(get_window(), Vector2i(1920, 1080))
	Harness.arm_watchdog(self, 300.0)
	AudioServer.set_bus_mute(0, true)
	TelemetryState.set_next_run_consent(false, false)
	UiPrefs.set_use_research_ds2(true)
	_dir = OS.get_environment("RESEARCH_SHOT_DIR")
	if _dir == "":
		_dir = OS.get_user_data_dir().path_join("research_ds2")
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
	TurnManager.fast_mode = true
	for _i in 2:
		TurnManager.commit_turn()
		if TurnManager.is_resolving:
			await TurnManager.turn_resolution_completed
		await _sleep(0.4)
	_dismiss_intro(get_tree().root)
	await _sleep(0.4)
	_stage_states()
	_panel = _world.get_node("UILayer/HUD/HUDContent/ResearchPanel")
	PanelStack.push(_panel)
	_panel.show()
	_view = _panel.call("ds2_view")
	print("[RESEARCH] ds2 view: %s" % str(_view))
	_panel.call("select_category", "Extraction")
	await _shot("extraction")
	var granted: Control = _view.call("card_for", "Reinforced Shaft Tunnels")
	var going: Control = _view.call("card_for", "Improved Coal Mining")
	var locked: Control = _view.call("card_for", "Reservoir Stimulation")
	await _crop("cards_granted_and_in_progress", [granted, going])
	await _crop("cards_licensed", [_view.call("card_for", "Composite Drill Bits")])
	if locked != null:
		_view.call("card_rect", "Reservoir Stimulation")
		await _crop("card_locked_needs", [locked])
	var scroll0: ScrollContainer = _view.call("board_scroll")
	scroll0.scroll_vertical = 0
	var pointed: Control = _view.call("card_for", "Microseismic Monitoring")
	if pointed != null:
		(_view.call("board") as Control).call("_on_card_hover", pointed, true)
		await _shot("extraction_threads")
		(_view.call("board") as Control).call("_on_card_hover", pointed, false)
	var scroll: ScrollContainer = _view.call("board_scroll")
	scroll.scroll_vertical = 100000
	await _shot("extraction_scrolled")
	for cat in ["Chemistry", "Infrastructure", "Renewable Power"]:
		_panel.call("select_category", cat)
		await _shot(cat.to_lower().replace(" ", "_"))
		scroll.scroll_vertical = 100000
		await _shot(cat.to_lower().replace(" ", "_") + "_scrolled")
	_panel.call("open_with_search", "steel")
	await _shot("search_steel")
	_view.call("open_drawer", "Metallurgy")
	await _shot("search_steel_metallurgy")
	_panel.call("open_with_search", "")
	_panel.call("select_category", "Extraction")
	ResearchState.grant_free_unlocks(2)
	_panel.call("begin_free_unlock_choice")
	await _shot("licence_choosing")
	var pick: Control = _view.call("card_for", "Beneficiated Iron Mining")
	if pick != null:
		(_view.call("board") as Control).call("_on_card_hover", pick, true)
		await _shot("licence_choosing_pointed")
	_panel.call("end_free_unlock_choice")
	_panel.call("open_with_search", "Bauxite Carbochlorination", true)
	await _shot("link_exact")
	_panel.call("open_with_search", "")
	_panel.call("select_category", "Extraction")
	get_window().size = Vector2i(1280, 720)
	await _sleep(1.0)
	await _shot("extraction_1280x720")
	print("[RESEARCH] done, %d captures" % _n)
	get_tree().quit(0)


## Extraction with a mix: three rank I patents granted (rank II opens), one licensed free, and progress on others.
func _stage_states() -> void:
	Production.produced_by_building["research_shot"] = {"coal": 212, "iron_ore": 340, "crude_oil": 120, "copper_ore": 45}
	for t in ["Reinforced Shaft Tunnels", "Hyperspectral Remote Sensing", "Bench Blasting Expansion", "Directional & Horizontal Drilling"]:
		ResearchState.grant_unlock(t, false)
	var panel: Control = _world.get_node("UILayer/HUD/HUDContent/ResearchPanel")
	ResearchState.grant_free_unlocks(1)
	panel.call("choose_free_unlock", "Composite Drill Bits")


func _crop(label: String, cards: Array) -> void:
	await _sleep(0.8)
	var box := Rect2()
	var first := true
	for c in cards:
		if c == null:
			continue
		var r: Rect2 = (c as Control).get_global_rect().grow(18.0)
		box = r if first else box.merge(r)
		first = false
	if first:
		return
	RenderingServer.force_draw(false)
	var img := get_viewport().get_texture().get_image()
	var k := float(img.get_width()) / get_viewport().get_visible_rect().size.x
	var px := Rect2i(Vector2i(box.position * k), Vector2i(box.size * k)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var crop := img.get_region(px)
	var path := _dir.path_join("%02d_%s.png" % [_n, label])
	crop.save_png(path)
	_n += 1
	print("[RESEARCH] saved %s" % path)


func _dismiss_intro(n: Node) -> void:
	for c: Node in n.get_children():
		_dismiss_intro(c)
	var sc: Script = n.get_script() as Script
	if sc != null and sc.resource_path.ends_with("_intro.gd") and n.has_method("_on_begin"):
		n.call("_on_begin")


func _shot(label: String) -> void:
	await _sleep(1.0)
	RenderingServer.force_draw(false)
	var img := get_viewport().get_texture().get_image()
	var path := _dir.path_join("%02d_%s.png" % [_n, label])
	img.save_png(path)
	_n += 1
	print("[RESEARCH] saved %s" % path)


func _sleep(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame


func _wait(max_seconds: float, done: Callable) -> void:
	var until := Time.get_ticks_msec() + int(max_seconds * 1000.0)
	while Time.get_ticks_msec() < until and not done.call():
		await get_tree().process_frame
	await _sleep(1.0)
