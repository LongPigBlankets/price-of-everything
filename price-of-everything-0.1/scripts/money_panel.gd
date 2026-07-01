extends PanelContainer

const LoanRowScene: PackedScene = preload("res://scenes/loan_row.tscn")
const HEADER_HEIGHT := 40.0

@onready var title_label: Label = $MarginContainer/ModalLayout/HeaderRow/TitleLabel
@onready var close_button: Button = $MarginContainer/ModalLayout/HeaderRow/CloseButton

# Balance tab @onready references
@onready var goods_value: Label = $MarginContainer/ModalLayout/TabContainer/Balance/MarginContainer/BalanceContent/RevenueSection/GoodsRow/GoodsValue
@onready var power_sales_value: Label = $MarginContainer/ModalLayout/TabContainer/Balance/MarginContainer/BalanceContent/RevenueSection/PowerSalesRow/PowerSalesValue
@onready var total_revenue_value: Label = $MarginContainer/ModalLayout/TabContainer/Balance/MarginContainer/BalanceContent/RevenueSection/TotalRevenueRow/TotalRevenueValue

@onready var maintenance_value: Label = $MarginContainer/ModalLayout/TabContainer/Balance/MarginContainer/BalanceContent/CostsSection/MaintenanceRow/MaintenanceValue
@onready var labour_value: Label = $MarginContainer/ModalLayout/TabContainer/Balance/MarginContainer/BalanceContent/CostsSection/LabourRow/LabourValue
@onready var power_purchase_value: Label = $MarginContainer/ModalLayout/TabContainer/Balance/MarginContainer/BalanceContent/CostsSection/PowerPurchaseRow/PowerPurchaseValue
@onready var total_costs_value: Label = $MarginContainer/ModalLayout/TabContainer/Balance/MarginContainer/BalanceContent/CostsSection/TotalCostsRow/TotalCostsValue

@onready var operating_profit_value: Label = $MarginContainer/ModalLayout/TabContainer/Balance/MarginContainer/BalanceContent/OperatingProfitRow/OperatingProfitValue
@onready var interest_value: Label = $MarginContainer/ModalLayout/TabContainer/Balance/MarginContainer/BalanceContent/InterestRow/InterestValue
@onready var pretax_value: Label = $MarginContainer/ModalLayout/TabContainer/Balance/MarginContainer/BalanceContent/PreTaxRow/PreTaxValue
@onready var tax_value: Label = $MarginContainer/ModalLayout/TabContainer/Balance/MarginContainer/BalanceContent/TaxRow/TaxValue
@onready var posttax_value: Label = $MarginContainer/ModalLayout/TabContainer/Balance/MarginContainer/BalanceContent/PostTaxRow/PostTaxValue
@onready var dividends_value: Label = $MarginContainer/ModalLayout/TabContainer/Balance/MarginContainer/BalanceContent/DividendsRow/DividendsValue
@onready var net_cashflow_value: Label = $MarginContainer/ModalLayout/TabContainer/Balance/MarginContainer/BalanceContent/NetCashflowRow/NetCashflowValue

# Stats tab
@onready var money_value: Label = $MarginContainer/ModalLayout/TabContainer/Stats/MarginContainer/StatsContent/MoneyRow/MoneyValue
@onready var debt_value: Label = $MarginContainer/ModalLayout/TabContainer/Stats/MarginContainer/StatsContent/DebtRow/DebtValue
@onready var payment_value: Label = $MarginContainer/ModalLayout/TabContainer/Stats/MarginContainer/StatsContent/PaymentRow/PaymentValue

# Loans tab
@onready var loans_vbox: VBoxContainer = $MarginContainer/ModalLayout/TabContainer/Loans/MarginContainer/ContentVBox/LoansVBox
@onready var take_loan_button: Button = $MarginContainer/ModalLayout/TabContainer/Loans/MarginContainer/ContentVBox/ActionsRow/TakeLoanButton

# Budget tab — labour buttons
@onready var labour_low_button: Button = $MarginContainer/ModalLayout/TabContainer/Budget/MarginContainer/BudgetContent/LabourSection/LabourButtonsRow/LabourLowButton
@onready var labour_normal_button: Button = $MarginContainer/ModalLayout/TabContainer/Budget/MarginContainer/BudgetContent/LabourSection/LabourButtonsRow/LabourNormalButton
@onready var labour_high_button: Button = $MarginContainer/ModalLayout/TabContainer/Budget/MarginContainer/BudgetContent/LabourSection/LabourButtonsRow/LabourHighButton

# Budget tab — projection labels (long but explicit; replace with %UniqueName if you prefer)
@onready var proj_goods_value: Label = $MarginContainer/ModalLayout/TabContainer/Budget/MarginContainer/BudgetContent/ScrollContainer/ProjectionContent/Proj_RevenueSection/Proj_GoodsRow/GoodsValue
@onready var proj_power_sales_value: Label = $MarginContainer/ModalLayout/TabContainer/Budget/MarginContainer/BudgetContent/ScrollContainer/ProjectionContent/Proj_RevenueSection/Proj_PowerSalesRow/PowerSalesValue
@onready var proj_total_revenue_value: Label = $MarginContainer/ModalLayout/TabContainer/Budget/MarginContainer/BudgetContent/ScrollContainer/ProjectionContent/Proj_RevenueSection/Proj_TotalRevenueRow/TotalRevenueValue

@onready var proj_maintenance_value: Label = $MarginContainer/ModalLayout/TabContainer/Budget/MarginContainer/BudgetContent/ScrollContainer/ProjectionContent/Proj_CostsSection/Proj_MaintenanceRow/MaintenanceValue
@onready var proj_labour_value: Label = $MarginContainer/ModalLayout/TabContainer/Budget/MarginContainer/BudgetContent/ScrollContainer/ProjectionContent/Proj_CostsSection/Proj_LabourRow/LabourValue
@onready var proj_power_purchase_value: Label = $MarginContainer/ModalLayout/TabContainer/Budget/MarginContainer/BudgetContent/ScrollContainer/ProjectionContent/Proj_CostsSection/Proj_PowerPurchaseRow/PowerPurchaseValue
@onready var _costs_section: VBoxContainer = $MarginContainer/ModalLayout/TabContainer/Balance/MarginContainer/BalanceContent/CostsSection
@onready var _proj_costs_section: VBoxContainer = $MarginContainer/ModalLayout/TabContainer/Budget/MarginContainer/BudgetContent/ScrollContainer/ProjectionContent/Proj_CostsSection
var _transport_value: Label
var _proj_transport_value: Label
var _goods_purchased_value: Label
var _proj_goods_purchased_value: Label
var _profit_sharing_value: Label
var _proj_profit_sharing_value: Label
@onready var proj_total_costs_value: Label = $MarginContainer/ModalLayout/TabContainer/Budget/MarginContainer/BudgetContent/ScrollContainer/ProjectionContent/Proj_CostsSection/Proj_TotalCostsRow/TotalCostsValue
@onready var proj_operating_profit_value: Label = $MarginContainer/ModalLayout/TabContainer/Budget/MarginContainer/BudgetContent/ScrollContainer/ProjectionContent/Proj_OperatingProfitRow/OperatingProfitValue
@onready var proj_interest_value: Label = $MarginContainer/ModalLayout/TabContainer/Budget/MarginContainer/BudgetContent/ScrollContainer/ProjectionContent/Proj_InterestRow/InterestValue
@onready var proj_pretax_value: Label = $MarginContainer/ModalLayout/TabContainer/Budget/MarginContainer/BudgetContent/ScrollContainer/ProjectionContent/Proj_PreTaxRow/PreTaxValue
@onready var proj_tax_value: Label = $MarginContainer/ModalLayout/TabContainer/Budget/MarginContainer/BudgetContent/ScrollContainer/ProjectionContent/Proj_TaxRow/TaxValue
@onready var proj_posttax_value: Label = $MarginContainer/ModalLayout/TabContainer/Budget/MarginContainer/BudgetContent/ScrollContainer/ProjectionContent/Proj_PostTaxRow/PostTaxValue
@onready var proj_dividends_value: Label = $MarginContainer/ModalLayout/TabContainer/Budget/MarginContainer/BudgetContent/ScrollContainer/ProjectionContent/Proj_DividendsRow/DividendsValue
@onready var proj_net_cashflow_value: Label = $MarginContainer/ModalLayout/TabContainer/Budget/MarginContainer/BudgetContent/ScrollContainer/ProjectionContent/Proj_NetCashflowRow/NetCashflowValue


var take_loan_dialog: PanelContainer = null
var overlay_rows: Array = []
var _dragging := false
var _drag_offset := Vector2.ZERO

# Charts tab
const CHART_MAX_TURNS := 10
const DEFAULT_PANEL_SIZE := Vector2(560, 620)
const CHART_PANEL_SIZE := Vector2(620, 600)
@onready var _tab_container: TabContainer = $MarginContainer/ModalLayout/TabContainer
@onready var _chart: Control = $MarginContainer/ModalLayout/TabContainer/Charts/MarginContainer/ChartsContent/Chart
@onready var _chart_revenue_button: Button = $MarginContainer/ModalLayout/TabContainer/Charts/MarginContainer/ChartsContent/ToggleRow/RevenueButton
@onready var _chart_costs_button: Button = $MarginContainer/ModalLayout/TabContainer/Charts/MarginContainer/ChartsContent/ToggleRow/CostsButton
var _chart_history: Array = []   # ring buffer of the last CHART_MAX_TURNS turn breakdowns
var _chart_mode: String = "revenue"

func _insert_cost_row(section: VBoxContainer, after_node_name: String, label_text: String) -> Label:
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	var name_label := Label.new()
	name_label.custom_minimum_size = Vector2(80, 0)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.text = label_text
	row.add_child(name_label)
	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(80, 0)
	value_label.text = "-£0.00"
	row.add_child(value_label)
	section.add_child(row)
	var after := section.get_node_or_null(after_node_name)
	if after != null:
		section.move_child(row, after.get_index() + 1)
	return value_label

func _insert_finance_row(section: VBoxContainer, after_node_name: String, label_text: String, default_text: String) -> Label:
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	var name_label := Label.new()
	name_label.custom_minimum_size = Vector2(80, 0)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.text = label_text
	row.add_child(name_label)
	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(80, 0)
	value_label.text = default_text
	row.add_child(value_label)
	section.add_child(row)
	var after := section.get_node_or_null(after_node_name)
	if after != null:
		section.move_child(row, after.get_index() + 1)
	return value_label

func _ready() -> void:
	_transport_value = _insert_cost_row(_costs_section, "PowerPurchaseRow", "Transport")
	_proj_transport_value = _insert_cost_row(_proj_costs_section, "Proj_PowerPurchaseRow", "Transport")
	_goods_purchased_value = _insert_cost_row(_costs_section, "PowerPurchaseRow", "Goods purchased")
	_proj_goods_purchased_value = _insert_cost_row(_proj_costs_section, "Proj_PowerPurchaseRow", "Goods purchased")
	var balance_content := $MarginContainer/ModalLayout/TabContainer/Balance/MarginContainer/BalanceContent as VBoxContainer
	var projection_content := $MarginContainer/ModalLayout/TabContainer/Budget/MarginContainer/BudgetContent/ScrollContainer/ProjectionContent as VBoxContainer
	_profit_sharing_value = _insert_finance_row(balance_content, "DividendsRow", "Profit Sharing", "-£0.00")
	_proj_profit_sharing_value = _insert_finance_row(projection_content, "Proj_DividendsRow", "Profit Sharing", "-£0.00")
	close_button.pressed.connect(hide)
	title_label.text = "Money & Budget"
	
	take_loan_button.pressed.connect(_on_take_loan_pressed)
	
	MatchState.money_changed.connect(_on_money_changed)
	LoanState.loans_updated.connect(_refresh)
	LoanState.payment_made.connect(_on_payment_made)
	
	_refresh()
	Production.turn_processed.connect(_on_turn_processed)
	labour_low_button.pressed.connect(_on_labour_pressed.bind(0.8))
	labour_normal_button.pressed.connect(_on_labour_pressed.bind(1.00))
	labour_high_button.pressed.connect(_on_labour_pressed.bind(1.2))
	_refresh_labour_buttons()
	
	MatchState.labour_multiplier_changed.connect(_on_labour_multiplier_changed)
	MatchState.workforce_policies_changed.connect(_refresh_projection)
	MarketState.prices_updated.connect(_refresh_projection)
	LoanState.loans_updated.connect(_refresh_projection)
	_refresh_balance_sheet()
	_refresh_projection()
	
	MatchState.building_added.connect(_on_buildings_changed)
	MatchState.building_removed.connect(_on_buildings_changed)

	_chart_revenue_button.pressed.connect(_on_chart_mode_pressed.bind("revenue"))
	_chart_costs_button.pressed.connect(_on_chart_mode_pressed.bind("costs"))
	_tab_container.tab_changed.connect(_on_tab_changed)
	_apply_tab_size(_tab_container.current_tab)

func _on_turn_processed(_summary: Dictionary) -> void:
	_refresh_balance_sheet()
	_refresh_projection()
	_record_chart_history(_summary)
	_refresh_chart()

func _on_money_changed(_amount: float) -> void:
	_refresh()

func _on_payment_made(_total: float) -> void:
	_refresh()

func _refresh() -> void:
	# Stats
	money_value.text = "£%.2f" % MatchState.money
	var outstanding: float = LoanState.total_outstanding()
	debt_value.text = "£%.2f / £%.2f" % [outstanding, LoanState.capacity_total()]
	payment_value.text = "£%.2f" % LoanState.total_per_turn_payment()
	
	if MatchState.money < 0:
		money_value.add_theme_color_override("font_color", Color(0.9, 0.2, 0.2))
	elif MatchState.money < 10:
		money_value.add_theme_color_override("font_color", Color(1.0, 0.6, 0.2))
	else:
		money_value.add_theme_color_override("font_color", Color.WHITE)
	
	# Loans list
	for child in loans_vbox.get_children():
		child.queue_free()
	
	if LoanState.loans.is_empty():
		var empty_label := Label.new()
		empty_label.text = "(no active loans)"
		empty_label.modulate = Color(0.7, 0.7, 0.7)
		loans_vbox.add_child(empty_label)
	else:
		for loan in LoanState.loans:
			var row := LoanRowScene.instantiate()
			loans_vbox.add_child(row)
			row.setup(loan)
			row.repay_pressed.connect(_on_repay_loan)
	
	take_loan_button.disabled = LoanState.available_capacity() < 1.0

func _on_take_loan_pressed() -> void:
	if take_loan_dialog == null:
		push_warning("[MoneyPanel] take_loan_dialog not wired")
		return
	take_loan_dialog.open()

func _on_repay_loan(loan_id: int) -> void:
	var ok: bool = LoanState.repay_loan(loan_id)
	if not ok:
		print("[MoneyPanel] Repay failed for loan %d (insufficient money?)" % loan_id)

func _on_buildings_changed(_arg = null) -> void:
	_refresh_projection()

func _refresh_balance_sheet() -> void:
	var summary: Dictionary = Production.last_turn_summary
	if summary.is_empty():
		# No turn has run yet — show zeros
		_render_balance_sheet({})
		return
	_render_balance_sheet(summary)

func _render_balance_sheet(summary: Dictionary) -> void:
	# Pull values, defaulting to 0 if missing
	var goods_revenue: float = summary.get("goods_sales_revenue", 0.0)
	var power_revenue: float = summary.get("power_sales_revenue", 0.0)
	var maintenance: float = summary.get("maintenance_paid", 0.0)
	var labour: float = summary.get("labour_paid", 0.0)
	var transport: float = summary.get("transport_paid", 0.0)
	var power_purchase: float = summary.get("power_purchase_cost", 0.0)
	var goods_purchased: float = summary.get("goods_purchased_cost", 0.0)
	var interest: float = summary.get("interest_paid", 0.0)
	var tax: float = summary.get("taxes_paid", 0.0)
	var dividends: float = summary.get("dividends_paid", 0.0)
	var profit_sharing: float = summary.get("profit_sharing_paid", 0.0)

	# Compute derived
	var total_revenue: float = goods_revenue + power_revenue
	var total_costs: float = maintenance + labour + transport + power_purchase + goods_purchased
	var operating_profit: float = total_revenue - total_costs
	var pretax: float = operating_profit - interest
	var posttax: float = pretax - tax
	var net_cashflow: float = posttax - dividends - profit_sharing
	
	# Render
	goods_value.text = "+£%.2f" % goods_revenue
	power_sales_value.text = "+£%.2f" % power_revenue
	total_revenue_value.text = "+£%.2f" % total_revenue
	
	maintenance_value.text = "-£%.2f" % maintenance
	labour_value.text = "-£%.2f" % labour
	power_purchase_value.text = "-£%.2f" % power_purchase
	_transport_value.text = "-£%.2f" % transport
	_goods_purchased_value.text = "-£%.2f" % goods_purchased
	total_costs_value.text = "-£%.2f" % total_costs
	
	operating_profit_value.text = _format_signed(operating_profit)
	_color_for_value(operating_profit_value, operating_profit)
	
	interest_value.text = "-£%.2f" % interest
	
	pretax_value.text = _format_signed(pretax)
	_color_for_value(pretax_value, pretax)
	
	tax_value.text = "-£%.2f" % tax
	
	posttax_value.text = _format_signed(posttax)
	_color_for_value(posttax_value, posttax)
	
	dividends_value.text = "-£%.2f" % dividends
	_profit_sharing_value.text = "-£%.2f" % profit_sharing
	
	net_cashflow_value.text = _format_signed(net_cashflow)
	_color_for_value(net_cashflow_value, net_cashflow)

	# Per-building-type breakdown tooltips.
	_apply_breakdown_tooltip(maintenance_value, summary.get("maintenance_by_type", {}), "maintenance")
	_apply_breakdown_tooltip(labour_value, summary.get("labour_by_type", {}), "labour")
	_apply_breakdown_tooltip(power_purchase_value, summary.get("power_purchase_by_type", {}), "power")
	_apply_breakdown_tooltip(_goods_purchased_value, summary.get("goods_purchased_by_type", {}), "goods purchased")

func _apply_breakdown_tooltip(value_label: Label, by_type: Dictionary, category: String) -> void:
	if value_label == null:
		return
	var tip := _format_breakdown(by_type, category)
	var row := value_label.get_parent()
	var controls: Array = [value_label]
	if row != null:
		controls.append(row)
		if row.get_child_count() > 0:
			controls.append(row.get_child(0))  # the name label
	for c in controls:
		if c is Control:
			c.mouse_filter = Control.MOUSE_FILTER_STOP
			c.tooltip_text = tip

func _format_breakdown(by_type: Dictionary, category: String) -> String:
	if by_type.is_empty():
		return "No %s costs this turn." % category
	var keys: Array = by_type.keys()
	keys.sort_custom(func(a, b): return float(by_type[a].get("amount", 0.0)) > float(by_type[b].get("amount", 0.0)))
	var lines: Array = []
	for k in keys:
		var entry: Dictionary = by_type[k]
		var amt: float = float(entry.get("amount", 0.0))
		var count: int = int(entry.get("count", 0))
		var bname: String = "Purchase orders" if str(k) == "" else Catalog.get_building_display_name(str(k))
		if count > 0:
			var plural := "s" if count != 1 else ""
			lines.append("%d %s%s: £%.2f" % [count, bname, plural, amt])
		else:
			lines.append("%s: £%.2f" % [bname, amt])
	return "\n".join(lines)

func _format_signed(amount: float) -> String:
	if amount > 0.005:
		return "+£%.2f" % amount
	elif amount < -0.005:
		return "-£%.2f" % abs(amount)
	else:
		return "£0.00"

func _color_for_value(label: Label, amount: float) -> void:
	if amount > 0.005:
		label.add_theme_color_override("font_color", Color(0.4, 0.85, 0.4))  # green
	elif amount < -0.005:
		label.add_theme_color_override("font_color", Color(0.9, 0.4, 0.4))  # red
	else:
		label.add_theme_color_override("font_color", Color.WHITE)  # neutral

func _on_labour_pressed(value: float) -> void:
	MatchState.set_labour_multiplier(value)
	
func _on_labour_multiplier_changed(_value: float) -> void:
	_refresh_labour_buttons()
	_refresh_projection()

func _refresh_labour_buttons() -> void:
	# Set the button toggle state to match current labour_multiplier
	var v: float = MatchState.labour_multiplier
	labour_low_button.button_pressed = absf(v - 0.8) < 0.001
	labour_normal_button.button_pressed = (v == 1.00)
	labour_high_button.button_pressed = absf(v - 1.2) < 0.001

func _refresh_projection() -> void:
	var proj: Dictionary = _project_next_turn()
	_render_projection(proj)

func _render_projection(proj: Dictionary) -> void:
	proj_goods_value.text = "+£%.2f" % proj.goods_revenue
	proj_power_sales_value.text = "+£%.2f" % proj.power_revenue
	proj_total_revenue_value.text = "+£%.2f" % proj.total_revenue
	
	proj_maintenance_value.text = "-£%.2f" % proj.maintenance
	proj_labour_value.text = "-£%.2f" % proj.labour
	proj_power_purchase_value.text = "-£%.2f" % proj.power_purchase
	_proj_transport_value.text = "-£%.2f" % proj.transport
	_proj_goods_purchased_value.text = "-£%.2f" % proj.goods_purchased
	proj_total_costs_value.text = "-£%.2f" % proj.total_costs
	
	proj_operating_profit_value.text = _format_signed(proj.operating_profit)
	_color_for_value(proj_operating_profit_value, proj.operating_profit)
	
	proj_interest_value.text = "-£%.2f" % proj.interest
	
	proj_pretax_value.text = _format_signed(proj.pretax)
	_color_for_value(proj_pretax_value, proj.pretax)
	
	proj_tax_value.text = "-£%.2f" % proj.tax
	
	proj_posttax_value.text = _format_signed(proj.posttax)
	_color_for_value(proj_posttax_value, proj.posttax)
	
	proj_dividends_value.text = "-£%.2f" % proj.dividends
	_proj_profit_sharing_value.text = "-£%.2f" % proj.profit_sharing
	
	proj_net_cashflow_value.text = _format_signed(proj.net_cashflow)
	_color_for_value(proj_net_cashflow_value, proj.net_cashflow)

func _project_next_turn() -> Dictionary:
	# Iterate buildings that ran last turn (they'll likely run again).
	# For each: compute revenue (output × current market price), demand, costs.
	
	var goods_revenue: float = 0.0
	var power_supply: int = 0
	var power_demand: int = 0
	var maintenance: float = 0.0
	var labour: float = 0.0
	var transport: float = 0.0
	var goods_purchased: float = 0.0

	# Use last_turn_run if available; else iterate all buildings
	var building_ids_to_consider: Array
	if Production.last_turn_run.is_empty():
		# Game hasn't run a turn yet — fall back to all buildings (optimistic projection)
		building_ids_to_consider = MatchState.buildings.keys()
	else:
		building_ids_to_consider = Production.last_turn_run.keys()
	
	for inst_id in building_ids_to_consider:
		var building: Dictionary = MatchState.buildings.get(inst_id, {})
		if building.is_empty():
			continue
		if not MatchState.is_player_owned(building):
			continue  # don't project costs for NPC-owned infrastructure
		var recipe: Dictionary = Catalog.get_recipe(building.get("recipe_id", ""))
		if recipe.is_empty():
			continue
		
		# Output revenue
		var output_name: String = recipe.get("output_name", "")
		var output_qty: int = int(round(float(recipe.get("output_qty", 0)) * MatchState.workforce_output_multiplier()))
		if output_name == "power":
			power_supply += output_qty
		elif output_name != "":
			var good: Dictionary = Catalog.get_good_by_internal_name(output_name)
			if not good.is_empty():
				goods_revenue += output_qty * MarketState.get_price(good.id)
		
		# Power demand
		power_demand += recipe.get("energy_req", 0)
		
		# Per-building costs
		var bdata: Dictionary = Catalog.get_building(str(building.get("building_id", "")))
		var bmaint = bdata.get("maintenance_cost", null)
		maintenance += EconomyConfig.MAINTENANCE_PER_BUILDING if bmaint == null else float(bmaint)
		labour += _calculate_projected_labour_cost(building)
		transport += _projected_transport_cost(building, recipe)
		# Market-sourced inputs (upper bound: full per-turn demand at the buy price)
		for input in recipe.get("inputs", []):
			var in_gid: String = str(input.get("good_id", ""))
			if in_gid == "" or MatchState.is_input_tile_only(inst_id, in_gid):
				continue
			goods_purchased += int(input.get("qty", 0)) * MarketState.get_buy_price(in_gid)
	
	# Grid settlement
	var net_power: int = power_supply - power_demand
	var power_revenue: float = 0.0
	var power_purchase: float = 0.0
	if net_power > 0:
		power_revenue = net_power * EconomyConfig.GRID_SELL_PRICE
	elif net_power < 0:
		power_purchase = -net_power * EconomyConfig.GRID_BUY_PRICE
	
	# Loan interest (known exactly)
	var interest: float = LoanState.total_per_turn_payment()
	
	# Compute the chain
	var total_revenue: float = goods_revenue + power_revenue
	var total_costs: float = maintenance + labour + transport + power_purchase + goods_purchased
	var operating_profit: float = total_revenue - total_costs
	var pretax: float = operating_profit - interest
	var taxable_profit := maxf(pretax, 0.0)
	var tax: float = minf(taxable_profit, taxable_profit * EconomyConfig.TAX_RATE)
	var posttax: float = pretax - tax
	var dividend_base := maxf(posttax, 0.0)
	var dividends: float = minf(dividend_base, dividend_base * EconomyConfig.DIVIDEND_RATE)
	var profit_sharing := 0.0
	if MatchState.is_workforce_policy_enabled(MatchState.WORKFORCE_POLICY_ANNUAL_PROFIT_SHARE):
		profit_sharing = maxf(0.0, posttax - dividends) * 0.05
	var net_cashflow: float = posttax - dividends - profit_sharing
	
	return {
		"goods_revenue": goods_revenue,
		"power_revenue": power_revenue,
		"total_revenue": total_revenue,
		"maintenance": maintenance,
		"labour": labour,
		"transport": transport,
		"power_purchase": power_purchase,
		"goods_purchased": goods_purchased,
		"total_costs": total_costs,
		"operating_profit": operating_profit,
		"interest": interest,
		"pretax": pretax,
		"tax": tax,
		"posttax": posttax,
		"dividends": dividends,
		"profit_sharing": profit_sharing,
		"net_cashflow": net_cashflow,
	}

func _calculate_projected_labour_cost(_building: Dictionary) -> float:
	# Mirrors Production._calculate_labour_cost so projection matches reality
	var unskilled := 100
	var skilled := 50
	var high_skilled := 50
	var base_cost: float = (
		unskilled * EconomyConfig.LABOUR_UNSKILLED_RATE
		+ skilled * EconomyConfig.LABOUR_SKILLED_RATE
		+ high_skilled * EconomyConfig.LABOUR_HIGH_SKILLED_RATE
	)
	return base_cost * MatchState.labour_multiplier * MatchState.workforce_labour_cost_multiplier()

func _projected_transport_cost(building: Dictionary, recipe: Dictionary) -> float:
	var instance_id: String = building.get("instance_id", "")
	var source_tile: String = building.get("tile_id", "")
	var cost := 0.0
	for output in _recipe_output_items(recipe):
		var good_id: String = output.get("good_id", "")
		if good_id == "":
			var internal_name: String = output.get("internal_name", "")
			var good: Dictionary = Catalog.get_good_by_internal_name(internal_name)
			good_id = good.get("id", "")
		var destination_tile := MatchState.get_output_stockpile_destination(instance_id, good_id)
		if destination_tile == "" or good_id == "":
			continue
		var route := TransportService.route(source_tile, destination_tile, good_id)
		cost += TransportService.transport_cost_for_route(good_id, int(output.get("qty", 0)), route)
	return cost

func _recipe_output_items(recipe: Dictionary) -> Array:
	if recipe.has("outputs"):
		return recipe.get("outputs", [])
	var output_name: String = recipe.get("output_name", "")
	var output_qty: int = recipe.get("output_qty", 0)
	if output_name == "" or output_qty <= 0:
		return []
	return [{
		"good_id": recipe.get("output_good_id", ""),
		"internal_name": output_name,
		"qty": output_qty,
	}]

# --- Charts tab ---

func _on_tab_changed(idx: int) -> void:
	_apply_tab_size(idx)
	if _tab_container.get_tab_title(idx) == "Charts":
		_refresh_chart()

func _apply_tab_size(idx: int) -> void:
	# The Charts tab needs more room; every other tab uses the compact panel size.
	var is_charts := _tab_container.get_tab_title(idx) == "Charts"
	custom_minimum_size = Vector2.ZERO
	size = CHART_PANEL_SIZE if is_charts else DEFAULT_PANEL_SIZE

func _on_chart_mode_pressed(mode: String) -> void:
	_chart_mode = mode
	_chart_revenue_button.button_pressed = (mode == "revenue")
	_chart_costs_button.button_pressed = (mode == "costs")
	_refresh_chart()

func _refresh_chart() -> void:
	if _chart != null and _chart.has_method("set_data"):
		_chart.set_data(_chart_history, _chart_mode)

func _record_chart_history(summary: Dictionary) -> void:
	var revenue := {
		"finished": 0.0, "intermediate": 0.0, "raw": 0.0, "construction": 0.0, "power": 0.0,
	}
	var costs := {
		"raw": 0.0, "intermediate": 0.0, "construction": 0.0, "power": 0.0,
		"maintenance": 0.0, "labour": 0.0, "taxes": 0.0, "dividends": 0.0, "interest": 0.0,
	}

	# Goods sold, split by tier.
	var sold: Dictionary = summary.get("sold", {})
	for gid in sold:
		var tier := _good_tier(str(gid))
		var rev := float(sold[gid].get("revenue", 0.0))
		match tier:
			"finished", "intermediate", "raw", "construction":
				revenue[tier] += rev
			_:
				revenue["intermediate"] += rev  # mixed/waste fall back to intermediate
	revenue["power"] = float(summary.get("power_sales_revenue", 0.0))

	# Goods purchased, split by tier (goods value only — transport is excluded).
	var purchased: Dictionary = summary.get("purchased_cost", {})
	for gid in purchased:
		var tier := _good_tier(str(gid))
		var cost := float(purchased[gid])
		match tier:
			"raw", "intermediate", "construction":
				costs[tier] += cost
			_:
				costs["intermediate"] += cost  # finished/mixed inputs are rare; lump in
	costs["power"] = float(summary.get("power_purchase_cost", 0.0))
	costs["maintenance"] = float(summary.get("maintenance_paid", 0.0))
	costs["labour"] = float(summary.get("labour_paid", 0.0))
	costs["taxes"] = float(summary.get("taxes_paid", 0.0))
	costs["dividends"] = float(summary.get("dividends_paid", 0.0))
	costs["profit_sharing"] = float(summary.get("profit_sharing_paid", 0.0))
	costs["interest"] = float(summary.get("interest_paid", 0.0))

	_chart_history.append({
		"turn": int(TurnManager.current_turn),
		"revenue": revenue,
		"costs": costs,
	})
	while _chart_history.size() > CHART_MAX_TURNS:
		_chart_history.pop_front()

func _good_tier(good_id: String) -> String:
	# Construction is a good category that spans several good_types; it takes priority
	# so construction materials chart as their own band. Otherwise classify by good_type.
	var good: Dictionary = Catalog.get_good(good_id)
	if good.is_empty():
		return "other"
	if str(good.get("category", "")).to_lower() == "construction":
		return "construction"
	var gt := str(good.get("good_type", "")).to_lower()
	if gt == "finished" or gt == "intermediate" or gt == "raw":
		return gt
	return "other"

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# Only start drag if click is in the top strip
			if event.position.y > HEADER_HEIGHT:
				return
			_dragging = true
			_drag_offset = global_position - get_global_mouse_position()
			accept_event()
		else:
			_dragging = false
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		global_position = get_global_mouse_position() + _drag_offset
		accept_event()
