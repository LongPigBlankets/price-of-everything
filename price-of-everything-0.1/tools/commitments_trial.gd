extends Node
const Forecast := preload("res://scripts/cash_commitments.gd")
const Paths := preload("res://scripts/app_paths.gd")
const Harness := preload("res://tools/shot_harness.gd")
const OUT := "/tmp/cnc-commitments-trial"
var failures := 0
var results: Array = []
var _cash_before_turn := 0.0
var _credit_trial := false
var _cash_checks: Array = []

func _enter_tree() -> void:
	Paths._base = OUT + "/runtime"
	RunMetrics.enabled = false

func check(ok: bool, label: String) -> void:
	print("[CommitmentsTrial] ", "PASS " if ok else "FAIL ", label)
	if not ok:
		failures += 1

func _ready() -> void:
	_credit_trial = OS.get_cmdline_user_args().has("--credit-reconciliation")
	DirAccess.make_dir_recursive_absolute(OUT)
	var shots := DisplayServer.get_name() != "headless"
	if shots:
		Harness.prepare_window(get_window(), Vector2i(1920, 1080))
	Harness.arm_watchdog(self, 240.0)
	AudioServer.set_bus_mute(0, true)
	SaveLoad.prepare_new_game("res://data/starts/metal_magnate.json", {"ruleset": {
		"start_id": "metal_magnate", "difficulty": "normal", "speed_turns": 100,
		"policy_timeline": "demo_itch", "victory_set": "demo_itch", "tutorial_enabled": false,
		"company_colour": "diesel_red"}})
	var world: Node = load("res://scenes/main.tscn").instantiate()
	add_child(world)
	await settle(160)
	world.reveal_for_play()
	TurnManager.fast_mode = true
	DecisionState.auto_resolve = true
	for child in world.get_children():
		if child.get_script() != null and str(child.get_script().resource_path).ends_with("metal_magnate_intro.gd"):
			child._on_begin()
		if child.get_script() != null and str(child.get_script().resource_path).ends_with("sale_effects.gd"):
			child.hide() # Keep transient world-sale glyphs out of UI screenshots.
	world.get_node("UILayer/HUD/ToastLayer").hide()
	if get_viewport().get_camera_2d() != null:
		get_viewport().get_camera_2d().set_process(false)
		get_viewport().get_camera_2d().set_physics_process(false)
	var money: Node = world.find_child("MoneyPanel", true, false)
	check(money != null, "real money panel exists")
	if OS.get_cmdline_user_args().has("--prepayment"):
		await prepayment_trial(world, money, shots)
		get_tree().quit(1 if failures else 0)
		return
	var first := Forecast.snapshot()
	check(is_zero_approx(float(Forecast.next_turn_costs(first).total)), "Metal Magnate starts with zero extra costs")
	if OS.get_cmdline_user_args().has("--middleman-study"):
		middleman_quotes()
	if _credit_trial:
		Production.turn_processed.connect(_check_cash_reconciliation)
	if shots:
		money.open_tab("Upcoming")
		money.show()
		money._queue_refresh()
		await settle(12)
		snap("upcoming-zero.png")
		var initial_total := money.find_child("UpcomingCostTotal", true, false) as Label
		check(initial_total != null and initial_total.text == "≈ £0.00", "Metal Magnate panel displays zero extra costs")
		money.open_tab("Balance")
		await settle(8)
		var initial_link := money.find_child("UpcomingCostsLink", true, false) as LinkButton
		check(initial_link != null and initial_link.text.ends_with("£0.00"), "Metal Magnate Balance link agrees at zero")
		var initial_bar: Node = world.get_node("UILayer/HUD/TopBar")
		initial_bar._refresh_money_notices(true)
		await settle(4)
		check(not world.get_node("UILayer/HUD/ToastLayer").has_row("notice:upcoming:%d" % int(TurnManager.current_turn)), "zero extra costs do not create an upcoming-bill notice")
	for index in 6:
		if index == 2:
			# Additional scenario: existing shipment bills, a standing order, and a build
			# visibly one turn from completion. Funds isolate prediction from bankruptcy.
			MatchState.add_money(5000.0)
			MatchState.queue_buy("tile_5_10", "g_005", 19)
			LoanState._create_loan(100.0, 0.1, 10, 0)
			# Known, already placed material bill arriving next turn; fee includes freight.
			TransportState.queue_transport_shipment({"source_tile": "tile_5_11", "destination_tile": "tile_5_10", "good_id": "g_003", "qty": 10, "turns_remaining": 1, "transport_turns": 1, "purchase_cost": 127.5, "purchase_goods_cost": 125.0, "is_purchase": true, "construction_instance_id": "trial_paid_materials"})
			MatchState._recompute_unpaid_purchases()
			MatchState.add_recurring_buy("tile_5_10", "g_003", 3)
			if _credit_trial:
				MatchState.building_tabs["trial_repayment"] = {"turns_left": 0, "accrued": 120.0, "mode": "slices", "slices_left": 3}
				MatchState.building_tabs["trial_refinance"] = {"turns_left": 3, "accrued": 90.0, "mode": "loan", "slices_left": 0}
				for iid: String in Production.last_turn_run:
					if BuildingState.is_player_owned(BuildingState.get_building(iid)):
						MatchState.building_tabs[iid] = {"turns_left": 2, "accrued": 0.0, "mode": "slices", "slices_left": 0}
						break
			var id := Construction.start_on_tile("b_002", "r_007", "tile_5_10")
			if not id.is_empty():
				Construction.construction_projects[id]["turns_remaining"] = 1
		if shots and index == 2:
			money.hide()
			var notices: Node = world.get_node("UILayer/HUD/TopBar")
			notices._money_notice_hits = [{"id": "loan", "text": "Lower-priority loan notice.", "tone": "warn"}, {"id": "spend", "text": "Lower-priority spending notice.", "tone": "warn"}]
			notices._refresh_money_notices(true)
			await settle(8)
			var dock: Node = world.get_node("UILayer/HUD/ToastLayer")
			var turn := int(TurnManager.current_turn)
			check(dock.has_row("notice:upcoming:%d" % turn) and dock.has_row("notice:loan:%d" % turn) and not dock.has_row("notice:spend:%d" % turn),
				"upcoming commitments take first priority within the notice cap")
			var upcoming_row: Control = null
			for row: Node in dock.find_child("RowList", true, false).get_children():
				if str(row.get_meta("key", "")) == "notice:upcoming:%d" % turn:
					upcoming_row = row
			if upcoming_row != null:
				var text := str(upcoming_row.get_meta("toast_message", ""))
				check("coming next turn." in text, "notice identifies next-turn bill")
				check(("£%d" % Forecast.recommended_buffer(float(Forecast.next_turn_costs(Forecast.snapshot()).total))) in text, "notice buffer rounds shared panel total upward")
			snap("upcoming-notice.png")
			if upcoming_row != null:
				var press := InputEventMouseButton.new()
				press.button_index = MOUSE_BUTTON_LEFT
				press.pressed = true
				upcoming_row.gui_input.emit(press)
				await settle(6)
				check(money.visible and money.get_node("MarginContainer/ModalLayout/TabContainer").get_current_tab_control().name == "Upcoming", "the notice's row opens Upcoming")
			var rows_before: int = dock.row_count()
			notices._refresh_money_notices()
			check(dock.row_count() == rows_before, "unchanged costs post no new notice")
			money.open_tab("Balance")
			money.show()
			money._queue_refresh()
			await settle(10)
			var link := money.find_child("UpcomingCostsLink", true, false) as LinkButton
			check(link != null and link.text.begins_with("Upcoming extra costs:"), "Balance has labelled upcoming-costs link")
			check(link != null and link.underline == LinkButton.UNDERLINE_MODE_ALWAYS and link.get_theme_color("font_color") == DS.PALETTE.ACCENT, "Upcoming link is underlined cream tertiary text")
			snap("balance-link.png")
			link.pressed.emit()
			await settle(8)
			check(money.get_node("MarginContainer/ModalLayout/TabContainer").get_current_tab_control().name == "Upcoming", "tertiary Balance link opens Upcoming")
			var shown_total := money.find_child("UpcomingCostTotal", true, false) as Label
			check(shown_total != null and shown_total.text == "≈ £%.2f" % float(Forecast.next_turn_costs(Forecast.snapshot()).total), "Upcoming tab reconciles with the notice and link")
			snap("upcoming-before.png")
			var details: ScrollContainer = money.get_node("MarginContainer/ModalLayout/TabContainer/Upcoming")
			details.scroll_vertical = 600
			await settle(4)
			snap("upcoming-orders.png")
		if DecisionState.has_pending():
			DecisionState.auto_resolve_pending()
		var state_dict := state_snapshot()
		var state_before := JSON.stringify(state_dict)
		var expected := Forecast.snapshot()
		var state_after := state_snapshot()
		for field: String in state_dict:
			if JSON.stringify(state_dict[field]) != JSON.stringify(state_after.get(field)):
				print("[STATE DIFF] ", field, " BEFORE ", JSON.stringify(state_dict[field]).left(700), " AFTER ", JSON.stringify(state_after.get(field)).left(700))
		check(state_before == JSON.stringify(state_after), "forecast does not mutate match state at turn %d" % TurnManager.current_turn)
		_cash_before_turn = MatchState.money
		TurnManager.commit_turn()
		await TurnManager.turn_resolution_completed
		var result := Forecast.last_comparison.duplicate(true)
		check(not result.is_empty(), "turn produces forecast/actual comparison")
		check(absf(float(result.forecast.due) - float(expected.due)) < 0.001, "captured due forecast matches the pre-turn preview")
		check(absf(float(result.due_error)) < 0.01, "booked bills and scheduled repayments match actual payments")
		check(absf(float(result.order_error)) < 0.01, "estimated new-order cost matches actual in this scenario")
		var predicted_qty := preload("res://scripts/cash_commitments_view.gd").quantities(result.forecast.orders)
		var actual_qty := preload("res://scripts/cash_commitments_view.gd").quantities(result.actual_orders)
		check(predicted_qty == actual_qty, "predicted goods/quantities match actual orders")
		check(absf(float(result.actual_maintenance) - float(result.forecast.maintenance)) < 0.01, "maintenance estimate matches actual")
		print("[CommitmentsTrial] turn=%d due=%.2f/%.2f orders=%.2f/%.2f preview_ms=%.2f" % [int(result.turn), float(result.forecast.due), float(result.actual_due), float(result.forecast.orders_total), float(result.actual_orders_total), float(expected.ms)])
		results.append(result)
		if shots and _credit_trial and index == 2:
			money.open_tab("Balance")
			money._queue_refresh()
			await settle(8)
			var balance_scroll: ScrollContainer = money.get_node("MarginContainer/ModalLayout/TabContainer/Balance/MarginContainer/BalanceScroll")
			balance_scroll.scroll_vertical = 10000
			await settle(4)
			snap("credit-balance.png")
			money.hide()
			var bar: Node = world.get_node("UILayer/HUD/TopBar")
			bar._open_fly("treasury")
			await settle(6)
			check(absf(_sum_cash_rows(bar) - Production.cash_change_of(Production.last_turn_summary)) < 0.02, "Treasury displayed rows add up to the cash change")
			snap("credit-treasury.png")
			bar._close_fly()
			money.show()
	if shots:
		world.get_node("UILayer/HUD/ToastLayer").collapse(false)
		money.open_tab("Upcoming")
		money._queue_refresh()
		await settle(12)
		var scroll: ScrollContainer = money.get_node("MarginContainer/ModalLayout/TabContainer/Upcoming")
		scroll.scroll_vertical = 10000
		await settle(4)
		snap("upcoming-actuals.png")
		money.hide()
		var top_bar: Node = world.get_node("UILayer/HUD/TopBar")
		top_bar._open_fly("treasury")
		await settle(6)
		snap("treasury-link.png")
		check(LoanState.repayment_label(LoanState.loans[0]) == "Repay Turn 3–12", "Treasury loan dates retain first and last payment turns after four payments")
		var treasury_link := top_bar.find_child("FlyUpcomingButton", true, false) as LinkButton
		check(treasury_link != null, "Treasury has tertiary upcoming-costs link")
		if treasury_link != null:
			treasury_link.pressed.emit()
			await settle(4)
			check(money.visible and money.get_node("MarginContainer/ModalLayout/TabContainer").get_current_tab_control().name == "Upcoming", "Treasury row opens Upcoming")
		money.open_tab("Loans")
		await settle(6)
		snap("loan-schedules.png")
		money.hide()
		var panel: Node = world.get_node("UILayer/HUD").construct_panel_v2
		panel.show()
		panel._locked_tile_id = "tile_5_10"
		panel._on_recipe_pressed("b_002", "r_007")
		await settle(12)
		var card := panel.find_child("BuildUpcomingPayments", true, false) as Control
		check(card != null, "demo construction confirmation includes upcoming payments")
		if card != null:
			check(card.get_child_count() == 2 and card.get_child(0).text.begins_with("Recommended buffer (cash or loan) for"), "build buffer contains only purpose and amount")
			panel._scroll.ensure_control_visible(card)
		await settle(6)
		snap("build-commitments.png")
	var file := FileAccess.open(OUT + "/comparisons.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"initial": first, "turns": results, "cash_checks": _cash_checks, "failures": failures}, "\t"))
	print("[CommitmentsTrial] failures=", failures)
	get_tree().quit(1 if failures else 0)

func settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame

func snap(filename: String) -> void:
	RenderingServer.force_draw()
	get_viewport().get_texture().get_image().save_png(OUT.path_join(filename))

func state_snapshot() -> Dictionary:
	return {"match": MatchState.export_state(), "stockpile": Stockpile.export_state(), "market": MarketState.export_state()}

func _sum_cash_rows(node: Node) -> float:
	var amount := float(node.get_meta("cash_amount", 0.0))
	for child in node.get_children():
		amount += _sum_cash_rows(child)
	return amount

func middleman_quotes() -> void:
	# Read-only full-L1 trade quotes on real map routes. No proposed fees applied to sim.
	var tiles: Dictionary = {}
	for tile: String in Catalog.all_tile_ids():
		if not bool(Catalog._tile_land.get(tile, false)):
			continue
		var port := TransportService.nearest_port_tile(tile)
		var distance := TransportService.tile_distance(port, tile)
		if not [0, 2, 4, 6, 8].has(distance) or tiles.has(distance):
			continue
		if not TransportService.quote_market_buy(tile, "g_003", 10).is_empty():
			tiles[distance] = tile
	var rows: Array = []
	for distance: int in tiles:
		var tile := str(tiles[distance])
		for rid: String in ["r_005", "r_009", "r_236"]:
			var recipe := Catalog.get_recipe(rid)
			if recipe.is_empty():
				continue
			var inputs: Array = []
			var input_value := 0.0
			var input_freight := 0.0
			var input_delay := 0
			var valid := true
			for item: Dictionary in recipe.get("inputs", []):
				var quote := TransportService.quote_market_buy(tile, str(item.good_id), int(item.qty))
				if quote.is_empty():
					valid = false
					break
				inputs.append({"good": item.good_id, "qty": item.qty, "value": quote.goods_cost, "freight": quote.transport_cost, "turns": quote.turns})
				input_value += float(quote.goods_cost)
				input_freight += float(quote.transport_cost)
				input_delay = maxi(input_delay, int(quote.turns))
			if not valid:
				continue
			var manifest: Dictionary = {}
			var sale_value := 0.0
			for item: Dictionary in recipe.get("outputs", []):
				manifest[str(item.good_id)] = int(item.qty)
				sale_value += float(item.qty) * MarketState.get_price(str(item.good_id))
			var sale := TransportService.quote_market_sell(tile, manifest)
			if sale.is_empty():
				continue
			var sale_freight := float(sale.transport_cost)
			for gid: String in manifest:
				sale_freight += float(TransportState.preview_sea_shipping(str(sale.port), gid, int(manifest[gid])).get("total", 0.0))
			rows.append({"recipe": rid, "tile": tile, "port": sale.port, "distance": distance, "inputs": inputs,
				"input_value": input_value, "sale_value": sale_value, "input_freight": input_freight,
				"sale_freight": sale_freight, "input_delay": input_delay, "sale_delay": sale.turns,
				"shipments": inputs.size() + manifest.size()})
	var file := FileAccess.open(OUT + "/middleman-quotes.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(rows, "\t"))

func _check_cash_reconciliation(summary: Dictionary) -> void:
	var actual := MatchState.money - _cash_before_turn
	var display := Production.cash_change_of(summary)
	var balance := preload("res://scripts/money_panel.gd").net_cash_of(summary)
	check(absf(display - actual) < 0.01, "reported cash change matches actual treasury movement")
	check(absf(balance - actual) < 0.01, "Balance itemised total matches actual treasury movement")
	var row := {"turn": TurnManager.current_turn, "actual": actual, "reported": display, "balance": balance,
		"deferred": summary.get("building_tab_carried", 0.0), "repaid": summary.get("building_credit_repaid", 0.0),
		"credit_loan_received": summary.get("building_credit_loan_received", 0.0)}
	_cash_checks.append(row)
	print("[CreditReconciliation] ", JSON.stringify(row))

func prepayment_trial(world: Node, money: Node, shots: bool) -> void:
	MatchState.add_money(10000.0)
	MatchState.construct_material_source = "market"
	var initial_land := BuildingState.get_tile_land_owned("tile_5_10")
	var initial_cash := MatchState.money
	var initial_stock := Stockpile.get_tile_totals("tile_5_10").duplicate()
	var prior := Construction.construction_projects.keys()
	var materials := Construction.estimate_market_cost("tile_5_10", "b_002")
	var needed_land := maxf(0.0, BuildingState.get_tile_player_space_used("tile_5_10") + float(Catalog.get_building("b_002").get("tile_size_used", 0.0)) - initial_land)
	var patches := ceili(needed_land / BuildingState.LAND_PATCH_SIZE)
	var land_cost := AdvisorState.purchase_cost_after_advisor(float(patches) * BuildingState.LAND_PATCH_COST, {"tile_id": "tile_5_10"})
	world._on_construction_buy_requested("b_002", "r_007", "tile_5_10")
	var iid := ""
	for key: String in Construction.construction_projects:
		if not prior.has(key):
			iid = key
	check(iid != "", "prepayment: real confirmation creates construction")
	if iid == "":
		return
	var fee := float(Construction.construction_projects[iid].build_cost)
	var land_after_confirm := BuildingState.get_tile_land_owned("tile_5_10")
	var charged := initial_cash - MatchState.money
	check(absf(charged - fee - materials - land_cost) < 0.01, "prepayment: live confirmation accounts for land, fee and full quoted kit")
	check(Forecast.payments().is_empty(), "prepayment: fully paid build has no future material bill")
	money.open_tab("Upcoming")
	money.show()
	money._queue_refresh()
	await settle(10)
	if shots:
		snap("construction-paid-now.png")
	money.hide()
	world._on_tile_selected(world._tile_data_by_id("tile_5_10"))
	await settle(10)
	var cancel: Button
	for candidate in world.info_panel.find_children("*", "Button", true, false):
		if candidate.text == "Cancel":
			cancel = candidate
			break
	check(cancel != null, "prepayment: original tile-panel Cancel button is available")
	if cancel != null:
		var ancestor: Node = cancel.get_parent()
		while ancestor != null:
			if ancestor is ScrollContainer:
				ancestor.ensure_control_visible(cancel)
			ancestor = ancestor.get_parent()
		await settle(4)
		if shots:
			snap("construction-tile-cancel.png")
		cancel.pressed.emit()
	await settle(10)
	check(not Construction.construction_projects.has(iid), "prepayment: existing tile-panel button cancels the project")
	check(is_equal_approx(MatchState.money, initial_cash - land_cost), "prepayment: existing cancel refunds construction while keeping the land purchase paid")
	check(land_after_confirm > initial_land and BuildingState.get_tile_land_owned("tile_5_10") == land_after_confirm, "prepayment: auto-bought land remains owned after cancellation")
	check(Stockpile.get_tile_totals("tile_5_10") == initial_stock, "prepayment: cancel restores existing stock without granting purchased goods")
	check(TransportState.pending_transport_shipments.is_empty(), "prepayment: cancel leaves no incoming material order")
	if shots:
		snap("construction-refunded.png")
	print("[CommitmentsTrial] prepayment charged=", charged, " materials=", materials, " fee=", fee, " land retained=", land_cost, " refunded=", fee + materials)
	print("[CommitmentsTrial] failures=", failures)
