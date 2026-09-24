extends Node
const Paths := preload("res://scripts/app_paths.gd")
const Harness := preload("res://tools/shot_harness.gd")
const OUT := "/tmp/cnc-stockpile-ui"
var failures := 0

func _enter_tree() -> void:
	Paths._base = OUT + "/runtime"
	TelemetryState.enabled = false
	RunMetrics.enabled = false

func check(ok: bool, message: String) -> void:
	print("[stockpile UI] ", "PASS " if ok else "FAIL ", message)
	if not ok:
		failures += 1

func _ready() -> void:
	Harness.prepare_window(get_window(), Vector2i(1920, 1080))
	Harness.arm_watchdog(self, 180.0)
	AudioServer.set_bus_mute(0, true)
	TelemetryState.set_next_run_consent(false, false)
	SaveLoad.prepare_new_game("res://data/starts/metal_magnate.json", {})
	var world: Node = load("res://scenes/main.tscn").instantiate()
	add_child(world)
	await settle(150)
	world.reveal_for_play()
	var camera := get_viewport().get_camera_2d()
	if camera != null:
		camera.set_process(false)
		camera.set_physics_process(false)
	var tile := "tile_5_10"
	for index in range(1, 13):
		Stockpile.add(tile, "g_%03d" % index, 20 + index * 2)
	world._on_go_to_tile_stockpile(tile)
	await settle(8)
	var panel: Node = world.info_panel
	var other: Control = panel.find_child("OtherGoodsBar", true, false)
	check(other != null, "other-goods column is interactive")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	other.gui_input.emit(click)
	await settle(8)
	var drawer: PanelContainer = panel.get("_goods_drawer")
	check(drawer != null and drawer.visible, "grey bar opens side drawer")
	check(absf(drawer.global_position.y - panel.global_position.y) < 1.0 and absf(drawer.size.y - panel.size.y) < 1.0, "drawer matches tile panel height and vertical position")
	check(drawer.global_position.x + drawer.size.x <= panel.global_position.x, "drawer opens horizontally beside panel")
	var buttons := drawer.find_children("StoredGood_*", "Button", true, false)
	check(buttons.size() == Stockpile.get_tile_totals(tile).size(), "drawer lists every stored good")
	snap("all-goods.png")
	var button: Button = drawer.find_child("StoredGood_g_008", true, false)
	button.pressed.emit()
	await settle(8)
	check(str(panel.get("_stock_sel").get("good_id", "")) == "g_008", "overflow good uses shared Move/Sell selection")
	snap("selected-good.png")
	panel._select_tab("bl")
	check(panel.get("_goods_drawer") == null, "changing tabs closes the drawer")
	var producer := BuildingState.add_building("b_002", "r_007", tile, "player_1", "guidance_capture_smelter", false)
	BuildingState.add_building("b_002", "r_026", tile, "player_1", "guidance_capture_pipe", false)
	MatchState.set_output_stockpile_destination(producer, tile, "g_005")
	preload("res://scripts/stockpile_route_prompt.gd").offer(world.hud_content, tile, "g_005")
	await settle(8)
	var prompt := world.find_child("StockpileRoutePrompt", true, false)
	check(prompt != null, "redirection offers per-good surplus selling")
	var dont_show := prompt.find_child("DontShowSurplusAgain", true, false) as CheckBox
	check(dont_show != null and not dont_show.button_pressed, "don't-show-again checkbox starts unticked")
	var sell_button := prompt.find_child("EnableGoodSurplus", true, false) as Button
	check(dont_show.global_position.y >= sell_button.get_parent().get_global_rect().end.y, "don't-show-again sits below both CTAs")
	snap("routing-prompt.png")
	dont_show.button_pressed = true
	preload("res://scripts/stockpile_route_prompt.gd").offer(world.hud_content, tile, "g_004")
	(prompt.find_child("EnableGoodSurplus", true, false) as Button).pressed.emit()
	await settle(4)
	check(MatchState.should_auto_sell_good(tile, "g_005") and not MatchState.should_auto_sell_good(tile, "g_012"), "accepting prompt enables only the named good")
	preload("res://scripts/stockpile_route_prompt.gd").offer(world.hud_content, tile, "g_004")
	await settle(4)
	check(world.find_child("StockpileRoutePrompt", true, false) == null and preload("res://scripts/stockpile_route_prompt.gd")._pending.is_empty(), "don't-show-again suppresses queued and future prompts")
	check(not MatchState.should_auto_sell_good(tile, "g_004"), "suppressing a prompt does not silently change another good's route or sales")
	preload("res://scripts/stockpile_route_prompt.gd")._dont_show_again = false
	MatchState.disable_auto_sell_good(tile, "g_005")
	preload("res://scripts/stockpile_route_prompt.gd").offer(world.hud_content, tile, "g_005")
	await settle(4)
	prompt = world.find_child("StockpileRoutePrompt", true, false)
	(prompt.find_child("DontShowSurplusAgain", true, false) as CheckBox).button_pressed = true
	(prompt.find_child("KeepSurplusStock", true, false) as Button).pressed.emit()
	await settle(4)
	check(preload("res://scripts/stockpile_route_prompt.gd")._dont_show_again and not MatchState.should_auto_sell_good(tile, "g_005"), "keep-stock also remembers the checkbox without enabling sales")
	var top: Node = world.find_child("TopBar", true, false)
	if top == null:
		top = find_method(world, "_post_notices")
	var hit := {"text": "Copper ingots accumulating at Stoneshore (+19/turn). Open stockpile to move or sell.", "word": "accumulating", "tone": "warn", "stock_tile": tile, "stock_good": "g_005"}
	# Notices only show from the second turn.
	TurnManager.current_turn = maxi(2, int(TurnManager.current_turn))
	top._post_notices([hit])
	await settle(8)
	snap("accumulation-notice.png")
	var notice_row: Control = null
	for row: Node in world.get_node("UILayer/HUD/ToastLayer").find_child("RowList", true, false).get_children():
		if str(row.get_meta("toast_message", "")) == str(hit.text):
			notice_row = row
	check(notice_row != null and str(notice_row.get_meta("tone", "")) == "amber", "notice arrives as an amber row in the updates dock")
	if notice_row != null:
		notice_row.gui_input.emit(click)
	await settle(6)
	check(str(panel.get("_stock_sel").get("good_id", "")) == "g_005", "notice opens exact tile and selects its good")
	check(str(panel.get("_active_tab")) == "stock", "notice lands on Stockpile tab")
	print("[stockpile UI] failures=", failures)
	get_tree().quit(1 if failures else 0)

func find_method(root: Node, method: String) -> Node:
	if root.has_method(method):
		return root
	for child in root.get_children():
		var found := find_method(child, method)
		if found != null:
			return found
	return null

func settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame

func snap(filename: String) -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	RenderingServer.force_draw()
	get_viewport().get_texture().get_image().save_png(OUT.path_join(filename))
