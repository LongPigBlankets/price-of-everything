extends Node
const Paths := preload("res://scripts/app_paths.gd")
const OUT := "/tmp/middleman-p2"
func _enter_tree() -> void:
	Paths._base=OUT+"/runtime"
	RunMetrics.enabled=false
	TelemetryState.enabled=false
func settle(frames: int=15) -> void:
	for i in frames: await get_tree().process_frame
func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT+"/"+name+".png")
func _ready() -> void:
	TelemetryState.enabled=false
	preload("res://tools/shot_harness.gd").arm_watchdog(self,150.0)
	preload("res://tools/shot_harness.gd").prepare_window(get_window(), Vector2i(1920,1080))
	get_viewport().gui_embed_subwindows=true
	AudioServer.set_bus_mute(0,true)
	DirAccess.make_dir_recursive_absolute(OUT)
	if OS.get_cmdline_user_args().has("--menu"):
		var menu: Node = load("res://scenes/main_menu.tscn").instantiate()
		add_child(menu)
		await settle(20)
		menu._show_new_game_panel()
		await settle(80)
		var panel: Control = menu._new_game_panel
		panel.modulate.a=1.0
		panel._card_buttons[0].button_pressed=true
		await settle(15)
		await shot("new-game")
		get_tree().quit()
		return
	SaveLoad.autosave_enabled=false
	SaveLoad.prepare_new_game("res://data/starts/pepper_valley_motors_playable.json")
	var world: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(world)
	await get_tree().process_frame
	get_tree().current_scene=world
	await settle(180)
	await shot("intro")
	Tutorial._on_overlay_skipped()
	var iid := str(MatchState.middleman_service.buildings.keys()[0])
	MatchState.focus_building_requested.emit(iid)
	await settle(40)
	await shot("building")
	var detail: Control = world._bdp_v2
	if OS.get_cmdline_user_args().has("--global-logistics"):
		var service = preload("res://scripts/middleman_service.gd")
		detail.hide()
		var extra := BuildingState.add_building("b_007", "r_009", "tile_5_4", MatchState.LOCAL_PLAYER)
		service.set_mode(extra, "input", "middleman")
		service.set_mode(extra, "output", "middleman")
		MatchState.transport_panel_requested.emit()
		await settle(20)
		var panel: Control = world.find_child("TransportPanel", true, false)
		assert(panel != null and panel.visible)
		await shot("global-logistics-controls")
		panel.find_child("GlobalLogisticsInputs", true, false).pressed.emit()
		await settle(10)
		var prompt := panel.get_node("GlobalLogisticsConfirmation")
		assert(prompt.size.y < 600)
		assert(prompt.get_ok_button().visible and prompt.get_cancel_button().visible)
		await shot("global-logistics-confirmation")
		prompt.canceled.emit()
		await settle(10)
		assert(service.uses_inputs(iid) and service.uses_inputs(extra))
		panel.find_child("GlobalLogisticsInputs", true, false).pressed.emit()
		await settle(5)
		panel.get_node("GlobalLogisticsConfirmation").confirmed.emit()
		await settle(15)
		assert(not service.uses_inputs(iid) and not service.uses_inputs(extra))
		assert(service.uses_outputs(iid) and service.uses_outputs(extra))
		assert(panel.find_child("GlobalLogisticsInputs", true, false).text == "Switch Inputs to Logistics Intermediary")
		await shot("global-logistics-managed")
		panel.find_child("GlobalLogisticsInputs", true, false).pressed.emit()
		await settle(5)
		panel.get_node("GlobalLogisticsConfirmation").confirmed.emit()
		await settle(15)
		assert(service.uses_inputs(iid) and service.uses_inputs(extra))
		print("GLOBAL_LOGISTICS_PREVIEW_PASS")
		get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--tile-ledger"):
		var service = preload("res://scripts/middleman_service.gd")
		var tile_panel: Control = world.info_panel
		detail.hide()
		tile_panel._select_tab("stock")
		await settle(20)
		assert(tile_panel.find_child("TileLogisticsInput", true, false) != null)
		await shot("tile-all-intermediary")
		var input_check: BaseButton = tile_panel.find_child("TileLogisticsInput", true, false)
		input_check.button_pressed = false
		await settle(10)
		var prompt := tile_panel.get_node_or_null("TransportSupplierConfirmation")
		assert(prompt != null)
		prompt.canceled.emit()
		await settle(10)
		assert(service.uses_inputs(iid))
		assert(tile_panel.find_child("TileLogisticsInput", true, false).button_pressed)
		input_check = tile_panel.find_child("TileLogisticsInput", true, false)
		input_check.button_pressed = false
		await settle(10)
		prompt = tile_panel.get_node("TransportSupplierConfirmation")
		prompt.confirmed.emit()
		await settle(20)
		assert(not service.uses_inputs(iid) and service.uses_outputs(iid))
		assert(tile_panel.find_child("ManageTileLogistics", true, false) != null)
		await shot("tile-mixed-logistics")
		tile_panel.find_child("ManageTileLogistics", true, false).pressed.emit()
		await settle(30)
		var ledger: Control = world.find_child("BuildingLedgerPanel", true, false)
		assert(ledger != null and ledger.visible)
		await shot("logistics-ledger")
		var route_button: Button = ledger.find_child("LogisticsInput0", true, false)
		assert(route_button != null and route_button.tooltip_text == "Global Market")
		route_button.pressed.emit()
		await settle(20)
		assert(not ledger.visible and detail.visible and detail._sheet != null)
		await shot("ledger-opened-logistics")
		print("TILE_LEDGER_PREVIEW_PASS")
		get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--rollout"):
		var service = preload("res://scripts/middleman_service.gd")
		for rid in ["r_012", "r_004"]:
			var recipe := Catalog.get_recipe(rid)
			var added := BuildingState.add_building(str(recipe.building_id), rid, "tile_5_4", MatchState.LOCAL_PLAYER)
			assert(service.enable(added).ok)
			MatchState.focus_building_requested.emit(added)
			await settle(30)
			await shot("rollout-"+rid)
			detail._open_logistics_sheet(BuildingState.get_building(added))
			await settle(20)
			await shot("rollout-logistics-"+rid)
			detail._close_sheet()
		get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--p3"):
		var b:=BuildingState.get_building(iid)
		detail._open_logistics_sheet(b)
		await settle(30)
		await shot("p3-logistics")
		detail._open_input_sources_sheet(b,Catalog.get_recipe(str(b.recipe_id)))
		await settle(30)
		await shot("p3-private-inputs")
		detail._request_logistics_mode(b, "input", "managed")
		await settle(10)
		await shot("p3-supplier-warning")
		var prompt := detail.get_node("TransportSupplierConfirmation") as ConfirmationDialog
		assert(preload("res://scripts/middleman_service.gd").uses_inputs(iid))
		prompt.canceled.emit()
		await settle(5)
		assert(preload("res://scripts/middleman_service.gd").uses_inputs(iid))
		detail._request_logistics_mode(b, "input", "managed")
		prompt = detail.get_node("TransportSupplierConfirmation") as ConfirmationDialog
		(prompt.find_child("DontShowSupplierAgain", true, false) as CheckBox).button_pressed = true
		prompt.confirmed.emit()
		await settle(10)
		assert(not preload("res://scripts/middleman_service.gd").uses_inputs(iid))
		assert(preload("res://scripts/middleman_service.gd").uses_outputs(iid))
		detail._close_sheet()
		await settle(10)
		await shot("p3-mixed-controls")
		assert(detail.find_child("ManageInputLogistics", true, false) == null)
		assert(detail.find_child("ManageOutputLogistics", true, false) != null)
		# Returning is immediate; the checked warning remains suppressed on the next departure.
		detail._request_logistics_mode(b, "input", "middleman")
		detail._request_logistics_mode(b, "input", "managed")
		assert(detail.get_node_or_null("TransportSupplierConfirmation") == null)
		assert(not preload("res://scripts/middleman_service.gd").uses_inputs(iid))
		# Exercise the actual route-option wrapper, including the post-switch destination.
		detail._open_output_sheet(b, Catalog.get_recipe(str(b.recipe_id)))
		await settle(10)
		await shot("p3-output-selector")
		var applied := [false]
		var choice: Control = detail._logistics_route_option(b, "output", "Global market", "", false, func() -> void:
			MatchState.route_output_to_market(iid, "g_008")
			applied[0] = true)
		detail.add_child(choice)
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		choice.gui_input.emit(click)
		assert(applied[0] and MatchState.is_output_market(iid, "g_008"))
		assert(not preload("res://scripts/middleman_service.gd").uses_outputs(iid))
		choice.queue_free()
		detail._request_logistics_mode(b, "output", "middleman")
		BuildingState.add_building("b_002","r_003","tile_6_4",MatchState.LOCAL_PLAYER)
		detail._open_input_sources_sheet(b,Catalog.get_recipe(str(b.recipe_id)))
		await settle(30)
		await shot("p3-managed-inputs")
		detail._close_sheet()
		var tile_panel:=world.find_child("TileInfoPanel",true,false)
		if tile_panel!=null:
			tile_panel._open_tile_logistics()
			await settle(30)
			await shot("p3-tile-logistics")
			for child in tile_panel.get_children():
				if child is AcceptDialog: child.queue_free()
			await settle(10)
			MatchState.transport_panel_requested.emit()
			await settle(30)
			await shot("p3-company-logistics")
		else: push_error("P3 tile panel not found")
		get_tree().quit()
		return
	detail.hide()
	var ev: Node = world.empire_view
	ev.toggle()
	await settle(40)
	var gw: Node = ev.get_node("GraphWorld")
	gw.focus_on(iid)
	await get_tree().create_timer(2.0).timeout
	await settle(5)
	await shot("empire")
	print("P2_PREVIEW_COMPLETE ", OUT)
	get_tree().quit()
