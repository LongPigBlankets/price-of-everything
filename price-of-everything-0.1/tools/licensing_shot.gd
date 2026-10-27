extends Node
## Boots a Metal Magnate game windowed and captures research licensing (docs/pacing-labour-mining-licensing-spec.md
## §10, AC36.2): the Licence groups drawer with a ready drawing, a licensed one and an in-house one; crops of those
## drawings; the licence dialog and the licence-out dialog; Metallurgy with an in-house process to license out; the
## old research canvas's licence strips; and the money panel after a turn with royalties and a licence sale.
##   LICENSING_SHOT_DIR=... AGENT_GODOT_WINDOW=1 godot --path . res://tools/licensing_shot.tscn -- --no-telemetry
## Writes <nn>_<view>.png to LICENSING_SHOT_DIR (default user://licensing).

const Harness := preload("res://tools/shot_harness.gd")
const Licensing := preload("res://scripts/research_licensing.gd")
const LicenceDialog := preload("res://scripts/licence_dialog.gd")

var _dir := ""
var _world: Node
var _panel: Control
var _view: Control
var _n := 0


func _ready() -> void:
	Harness.prepare_window(get_window(), Vector2i(1920, 1080))
	Harness.arm_watchdog(self, 300.0)
	AudioServer.set_bus_mute(0, true)
	TelemetryState.set_next_run_consent(false)
	UiPrefs.set_use_research_ds2(true)
	_dir = OS.get_environment("LICENSING_SHOT_DIR")
	if _dir == "":
		_dir = OS.get_user_data_dir().path_join("licensing")
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
	for _i in 6:
		TurnManager.commit_turn()
		if TurnManager.is_resolving:
			await TurnManager.turn_resolution_completed
		await _sleep(0.3)
	_dismiss_intro(get_tree().root)
	await _sleep(0.4)
	_stage()
	get_viewport().gui_disable_input = true
	_panel = _world.get_node("UILayer/HUD/HUDContent/ResearchPanel")
	PanelStack.push(_panel)
	_panel.show()
	_view = _panel.call("ds2_view")
	_view.call("open_drawer", "Licence groups")
	await _shot("licence_groups")
	(_view.call("board_view") as Control).call("zoom_to_fit")
	await _shot("licence_groups_zoomed_out")
	(_view.call("board_view") as Control).call("reset")
	await _crop("cards_ready_licensed_developed", [_view.call("card_for", "Basic Blast Furnaces"),
		_view.call("card_for", "Continuous Casting"), _view.call("card_for", "Reheat Turbine Cycles")])
	var ready: Control = _view.call("card_for", "Basic Blast Furnaces")
	if ready != null:
		(_view.call("board") as Control).call("_on_card_hover", ready, true)
		await _shot("ready_detail")
		(_view.call("board") as Control).call("_on_card_hover", ready, false)
	var dialog := LicenceDialog.open(_view, "Basic Blast Furnaces")
	await _shot("licence_dialog")
	if dialog != null:
		dialog.queue_free()
	_view.call("open_drawer", "Metallurgy")
	await _shot("metallurgy_in_house")
	var his: Control = _view.call("card_for", "HIsarna")
	if his != null:
		(_view.call("board_view") as Control).call("ensure_visible", his)
		await _crop("card_license_out", [his])
	dialog = LicenceDialog.open(_view, "HIsarna")
	await _shot("licence_out_dialog")
	if dialog != null:
		dialog.queue_free()
	UiPrefs.set_use_research_ds2(false)
	await _sleep(0.5)
	_panel.call("select_category", "Metallurgy")
	await _shot("old_canvas_metallurgy")
	_panel.call("_zoom_tree_by_factor", 3.2, Vector2(820, 700))
	await _shot("old_canvas_metallurgy_zoomed")
	UiPrefs.set_use_research_ds2(true)
	_panel.hide()
	PanelStack.remove(_panel)
	# A turn with a royalty and a licence sale, then the money panel.
	Licensing.license("Basic Blast Furnaces")
	Licensing.license_out("HIsarna")
	get_viewport().gui_disable_input = false
	TurnManager.commit_turn()
	if TurnManager.is_resolving:
		await TurnManager.turn_resolution_completed
	await _sleep(0.5)
	get_viewport().gui_disable_input = true
	var hud: Node = _world.get_node_or_null("UILayer/HUD")
	var money: Control = hud.get("money_panel") if hud != null else null
	if money != null:
		money.show()
		await _shot("money_panel")
		money.hide()
	var s: Dictionary = Production.last_turn_summary
	print("[LICENSING] last turn: royalties £%.2f, licence sales £%.2f, revenue £%.2f" % [float(s.get("royalties_paid", 0.0)),
		float(s.get("licence_income", 0.0)), float(s.get("goods_sales_revenue", 0.0)) + float(s.get("power_sales_revenue", 0.0))])
	print("[LICENSING] done, %d captures" % _n)
	get_tree().quit(0)


## Iron and steel: Basic Blast Furnaces ready, Continuous Casting licensed for £200, Pulverised Carbon Injection
## locked behind HIsarna. Coal power: Reheat Turbine Cycles developed in house. HIsarna developed in house (rank II),
## so Metallurgy shows a process to license out.
func _stage() -> void:
	ResearchState.licence_ready_titles["Continuous Casting"] = TurnManager.current_turn
	Licensing.license("Continuous Casting")
	ResearchState.licence_ready_titles["Basic Blast Furnaces"] = TurnManager.current_turn
	ResearchState.licence_ready_titles["Steam Turbine Upgrades"] = TurnManager.current_turn
	ResearchState.grant_free_unlocks(1)
	(_world.get_node("UILayer/HUD/HUDContent/ResearchPanel") as Control).call("choose_free_unlock", "Reheat Turbine Cycles")
	ResearchState.grant_unlock("HIsarna")


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
	img.get_region(px).save_png(_dir.path_join("%02d_%s.png" % [_n, label]))
	_n += 1


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
	print("[LICENSING] saved %s" % path)


func _sleep(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame


func _wait(max_seconds: float, done: Callable) -> void:
	var until := Time.get_ticks_msec() + int(max_seconds * 1000.0)
	while Time.get_ticks_msec() < until and not done.call():
		await get_tree().process_frame
	await _sleep(1.0)
