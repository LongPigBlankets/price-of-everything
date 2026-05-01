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

func _ready() -> void:
	close_button.pressed.connect(hide)
	title_label.text = "Money & Budget"
	
	take_loan_button.pressed.connect(_on_take_loan_pressed)
	
	MatchState.money_changed.connect(_on_money_changed)
	LoanState.loans_updated.connect(_refresh)
	LoanState.payment_made.connect(_on_payment_made)
	
	_refresh()
	Production.turn_processed.connect(_on_turn_processed)
	labour_low_button.pressed.connect(_on_labour_pressed.bind(0.75))
	labour_normal_button.pressed.connect(_on_labour_pressed.bind(1.00))
	labour_high_button.pressed.connect(_on_labour_pressed.bind(1.25))
	_refresh_labour_buttons()
	
	MatchState.labour_multiplier_changed.connect(_on_labour_multiplier_changed)
	MarketState.prices_updated.connect(_refresh_projection)
	LoanState.loans_updated.connect(_refresh_projection)
	_refresh_balance_sheet()
	_refresh_projection()
	
	MatchState.building_added.connect(_on_buildings_changed)
	MatchState.building_removed.connect(_on_buildings_changed)
	
func _on_turn_processed(_summary: Dictionary) -> void:
	_refresh_balance_sheet()
	_refresh_projection()

func _on_money_changed(_amount: float) -> void:
	_refresh()

func _on_payment_made(_total: float) -> void:
	_refresh()

func _refresh() -> void:
	# Stats
	money_value.text = "£%.2f" % MatchState.money
	var outstanding: float = LoanState.total_outstanding()
	debt_value.text = "£%.2f / £%.2f" % [outstanding, EconomyConfig.LOAN_MAX_CAPACITY]
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
	var power_purchase: float = summary.get("power_purchase_cost", 0.0)
	var interest: float = summary.get("interest_paid", 0.0)
	var tax: float = summary.get("taxes_paid", 0.0)
	var dividends: float = summary.get("dividends_paid", 0.0)
	
	# Compute derived
	var total_revenue: float = goods_revenue + power_revenue
	var total_costs: float = maintenance + labour + power_purchase
	var operating_profit: float = total_revenue - total_costs
	var pretax: float = operating_profit - interest
	var posttax: float = pretax - tax
	var net_cashflow: float = posttax - dividends
	
	# Render
	goods_value.text = "+£%.2f" % goods_revenue
	power_sales_value.text = "+£%.2f" % power_revenue
	total_revenue_value.text = "+£%.2f" % total_revenue
	
	maintenance_value.text = "-£%.2f" % maintenance
	labour_value.text = "-£%.2f" % labour
	power_purchase_value.text = "-£%.2f" % power_purchase
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
	
	net_cashflow_value.text = _format_signed(net_cashflow)
	_color_for_value(net_cashflow_value, net_cashflow)

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
	labour_low_button.button_pressed = (v == 0.75)
	labour_normal_button.button_pressed = (v == 1.00)
	labour_high_button.button_pressed = (v == 1.25)

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
		var recipe: Dictionary = Catalog.get_recipe(building.get("recipe_id", ""))
		if recipe.is_empty():
			continue
		
		# Output revenue
		var output_name: String = recipe.get("output_name", "")
		var output_qty: int = recipe.get("output_qty", 0)
		if output_name == "power":
			power_supply += output_qty
		elif output_name != "":
			var good: Dictionary = Catalog.get_good_by_internal_name(output_name)
			if not good.is_empty():
				goods_revenue += output_qty * MarketState.get_price(good.id)
		
		# Power demand
		power_demand += recipe.get("energy_req", 0)
		
		# Per-building costs
		maintenance += EconomyConfig.MAINTENANCE_PER_BUILDING
		labour += _calculate_projected_labour_cost(building)
	
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
	var total_costs: float = maintenance + labour + power_purchase
	var operating_profit: float = total_revenue - total_costs
	var pretax: float = operating_profit - interest
	var tax: float = max(pretax, 0.0) * EconomyConfig.TAX_RATE
	var posttax: float = pretax - tax
	var dividends: float = max(posttax, 0.0) * EconomyConfig.DIVIDEND_RATE
	var net_cashflow: float = posttax - dividends
	
	return {
		"goods_revenue": goods_revenue,
		"power_revenue": power_revenue,
		"total_revenue": total_revenue,
		"maintenance": maintenance,
		"labour": labour,
		"power_purchase": power_purchase,
		"total_costs": total_costs,
		"operating_profit": operating_profit,
		"interest": interest,
		"pretax": pretax,
		"tax": tax,
		"posttax": posttax,
		"dividends": dividends,
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
	return base_cost * MatchState.labour_multiplier


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
