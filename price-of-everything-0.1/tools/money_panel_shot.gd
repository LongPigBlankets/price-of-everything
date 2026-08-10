extends Node2D
## Renders the money panel's Balance tab, top and bottom. Exists because a runtime reparent of
## BalanceContent emptied this tab and shipped unnoticed — the unit suite cannot see a blank panel.
## The measurements below are the ones the earlier attempts got right while the tab drew NOTHING:
## a sheet taller than its tab proves only that a scroll is warranted, not that anything is on
## screen. What matters is BalanceScroll's own height and its scrollbar.
var _wm
func _ready() -> void:
	get_window().size = Vector2i(1920, 1080)   # the playtester's screen
	_wm = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_wm)
	for _i in range(160):
		await get_tree().process_frame
	var menu = _wm.get_node_or_null("UILayer/HUD")
	if menu == null or menu.money_panel == null:
		print("[MONEY_SHOT] money panel not found"); get_tree().quit(1); return
	var panel = menu.money_panel
	panel.show()
	# Turn 1 is all zeros, and a sheet of zeros hides arithmetic bugs as effectively as a blank
	# one hides layout bugs — transport was absent from the Costs chart for as long as this tool
	# only ever shot turn 1. Feed the panel eight turns of realistic movement first.
	_feed(panel)
	# The panel sizes itself (_apply_tab_size); forcing a size here would mask that.
	for _i in range(12):
		await get_tree().process_frame

	var scroll := panel.find_child("BalanceScroll", true, false) as ScrollContainer
	var content := panel.find_child("BalanceContent", true, false) as Control
	if scroll == null or content == null:
		print("[MONEY_SHOT] BalanceScroll/BalanceContent missing"); get_tree().quit(1); return
	var bar := scroll.get_v_scroll_bar()
	print("[MONEY_SHOT] window=%s panel=%s scroll_h=%.0f sheet_h=%.0f rows=%d" % [
		str(get_window().size), str(panel.size), scroll.size.y, content.size.y,
		content.get_child_count()])
	var bottom: float = panel.global_position.y + panel.size.y
	print("[MONEY_SHOT] fits_screen=%s viewport_visible=%s scrollbar=%s bottom_gap=%.0f" % [
		str(bottom <= get_window().size.y), str(scroll.size.y > 0),
		str(bar != null and bar.visible), get_window().size.y - bottom])

	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://money_panel_shot.png")

	# Scrolled to the end: the rows the playtester could not reach must be on screen here.
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
	for _i in range(6):
		await get_tree().process_frame
	print("[MONEY_SHOT] scrolled_to=%d of %d" % [
		scroll.scroll_vertical, int(maxf(0.0, content.size.y - scroll.size.y))])
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://money_panel_shot_bottom.png")

	# The Costs chart: every cost the sheet lists needs a band here too.
	panel.open_tab("Charts")
	panel._on_chart_mode_pressed("costs")
	for _i in range(10):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://money_panel_costs_chart.png")
	print("SAVED money_panel_shot.png + _bottom.png + _costs_chart.png")
	get_tree().quit()


## Eight turns of plausible movement, fed straight into the panel's own recorders. Freight is the
## biggest line on purpose: it is the one that was missing from the chart.
func _feed(panel) -> void:
	for t in range(1, 9):
		var f := float(t)
		TurnManager.current_turn = t
		var s := {
			"sold": {"g_012": {"revenue": 210.0 + 18.0 * f, "qty": 40}},
			"goods_sales_revenue": 210.0 + 18.0 * f,
			"power_sales_revenue": 26.0 + 2.0 * f,
			"purchased": {}, "purchased_cost": {"g_003": 44.0 + 3.0 * f},
			"goods_purchased_cost": 44.0 + 3.0 * f,
			"transport_paid": 51.0 + 6.5 * f,
			"warehousing_paid": 7.0 + 0.6 * f,
			"maintenance_paid": 22.0, "labour_paid": 38.0 + f,
			"advisor_paid": 11.0 + 0.4 * f,
			"power_purchase_cost": 19.0 + f,
			"carbon_tax_paid": 4.0 * f,
			"taxes_paid": 12.0, "dividends_paid": 9.0, "profit_sharing_paid": 3.0,
			"interest_paid": 6.0, "building_tab_carried": (35.0 if t <= 3 else 0.0),
			"transport_breakdown": {"roads": 20.0 + 3.0 * f, "rail": 18.0 + 2.0 * f,
				"port_outbound": 13.0 + 1.5 * f},
		}
		panel._record_chart_history(s)
		# Through last_turn_summary, not _render_balance_sheet directly: the panel refreshes
		# itself on show and would otherwise paint zeros straight back over the numbers.
		Production.last_turn_summary = s
