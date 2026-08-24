extends PanelContainer

const LoanRowScene: PackedScene = preload("res://scenes/loan_row.tscn")
const UIHelpers := preload("res://scripts/ui_helpers.gd")
const HEADER_HEIGHT := 40.0

@onready var title_label: Label = $MarginContainer/ModalLayout/HeaderRow/TitleLabel
@onready var close_button: Button = $MarginContainer/ModalLayout/HeaderRow/CloseButton

# Balance tab @onready references
@onready var goods_value: Label = $MarginContainer/ModalLayout/TabContainer/Balance/MarginContainer/BalanceScroll/BalanceContent/RevenueSection/GoodsRow/GoodsValue
@onready var power_sales_value: Label = $MarginContainer/ModalLayout/TabContainer/Balance/MarginContainer/BalanceScroll/BalanceContent/RevenueSection/PowerSalesRow/PowerSalesValue
@onready var total_revenue_value: Label = $MarginContainer/ModalLayout/TabContainer/Balance/MarginContainer/BalanceScroll/BalanceContent/RevenueSection/TotalRevenueRow/TotalRevenueValue

@onready var maintenance_value: Label = $MarginContainer/ModalLayout/TabContainer/Balance/MarginContainer/BalanceScroll/BalanceContent/CostsSection/MaintenanceRow/MaintenanceValue
@onready var labour_value: Label = $MarginContainer/ModalLayout/TabContainer/Balance/MarginContainer/BalanceScroll/BalanceContent/CostsSection/LabourRow/LabourValue
@onready var power_purchase_value: Label = $MarginContainer/ModalLayout/TabContainer/Balance/MarginContainer/BalanceScroll/BalanceContent/CostsSection/PowerPurchaseRow/PowerPurchaseValue
@onready var total_costs_value: Label = $MarginContainer/ModalLayout/TabContainer/Balance/MarginContainer/BalanceScroll/BalanceContent/CostsSection/TotalCostsRow/TotalCostsValue

@onready var operating_profit_value: Label = $MarginContainer/ModalLayout/TabContainer/Balance/MarginContainer/BalanceScroll/BalanceContent/OperatingProfitRow/OperatingProfitValue
@onready var interest_value: Label = $MarginContainer/ModalLayout/TabContainer/Balance/MarginContainer/BalanceScroll/BalanceContent/InterestRow/InterestValue
@onready var pretax_value: Label = $MarginContainer/ModalLayout/TabContainer/Balance/MarginContainer/BalanceScroll/BalanceContent/PreTaxRow/PreTaxValue
@onready var tax_value: Label = $MarginContainer/ModalLayout/TabContainer/Balance/MarginContainer/BalanceScroll/BalanceContent/TaxRow/TaxValue
@onready var posttax_value: Label = $MarginContainer/ModalLayout/TabContainer/Balance/MarginContainer/BalanceScroll/BalanceContent/PostTaxRow/PostTaxValue
@onready var dividends_value: Label = $MarginContainer/ModalLayout/TabContainer/Balance/MarginContainer/BalanceScroll/BalanceContent/DividendsRow/DividendsValue
@onready var net_cashflow_value: Label = $MarginContainer/ModalLayout/TabContainer/Balance/MarginContainer/BalanceScroll/BalanceContent/NetCashflowRow/NetCashflowValue

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
@onready var _costs_section: VBoxContainer = $MarginContainer/ModalLayout/TabContainer/Balance/MarginContainer/BalanceScroll/BalanceContent/CostsSection
@onready var _revenue_section: VBoxContainer = $MarginContainer/ModalLayout/TabContainer/Balance/MarginContainer/BalanceScroll/BalanceContent/RevenueSection
## One gap between balance rows, everywhere. See _normalise_balance_rows.
const BALANCE_ROW_GAP := 6
@onready var _proj_costs_section: VBoxContainer = $MarginContainer/ModalLayout/TabContainer/Budget/MarginContainer/BudgetContent/ScrollContainer/ProjectionContent/Proj_CostsSection
var _transport_value: Label
var _transport_caret: Button
var _transport_breakdown_values: Dictionary = {}
var _transport_breakdown_amounts: Dictionary = {}
var _transport_expanded := false
var _section_carets: Dictionary = {}      # "revenue" / "costs" -> the fold Button
var _section_expanded: Dictionary = {}
var _proj_transport_value: Label
var _goods_purchased_value: Label
var _proj_goods_purchased_value: Label
var _warehousing_value: Label
var _advisor_value: Label
var _building_tab_value: Label
var _proj_warehousing_value: Label
var _profit_sharing_value: Label
var _proj_profit_sharing_value: Label
var _carbon_tax_value: Label
var _proj_carbon_tax_value: Label
var _green_subsidy_value: Label
var _proj_green_subsidy_value: Label
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
const CHART_PANEL_SIZE := Vector2(820, 840)   # wider and taller: the legend is tickboxes now
# Breathing room so the panel never runs to the screen edge.
const PANEL_SCREEN_MARGIN := 90.0
# Floor for the Balance tab on a short screen: below this the sheet is all scrollbar.
const MIN_BALANCE_PANEL_HEIGHT := 360.0
## The balance sheet reads at 18, not the theme's 14 (owner 2026-08-24). It is a document —
## the one screen in the game a player scans line by line — and it was set at the size the
## rest of the UI uses for captions.
const BALANCE_ROW_FONT := 18
const BALANCE_HEADER_FONT := 22
const TRANSPORT_BREAKDOWN_ROWS := [
	["port_inbound", "Port Charges — Imports"],
	["port_outbound", "Port Charges — Exports"],
	["nothing", "No infrastructure"],
	["rail", "Rail Transport"],
	["roads", "Road Transport"],
	["pipes", "Pipe Transport"],
	["reinf_pipes", "Reinforced Pipe Transport"],
]
@onready var _tab_container: TabContainer = $MarginContainer/ModalLayout/TabContainer
@onready var _balance_content: VBoxContainer = $MarginContainer/ModalLayout/TabContainer/Balance/MarginContainer/BalanceScroll/BalanceContent
@onready var _chart: Control = $MarginContainer/ModalLayout/TabContainer/Charts/MarginContainer/ChartsContent/Chart
@onready var _chart_revenue_button: Button = $MarginContainer/ModalLayout/TabContainer/Charts/MarginContainer/ChartsContent/ToggleRow/RevenueButton
@onready var _chart_costs_button: Button = $MarginContainer/ModalLayout/TabContainer/Charts/MarginContainer/ChartsContent/ToggleRow/CostsButton
var _chart_history: Array = []   # ring buffer of the last CHART_MAX_TURNS turn breakdowns
var _chart_mode: String = "revenue"

# Refreshes are coalesced (notification_bell pattern): money_changed alone fires
# once per building payment during PROCESS, and each used to rebuild the whole
# loans list — hundreds of teardown/instantiate cycles per turn, even hidden.
# Signals now set a dirty flag and defer ONE full refresh; while hidden the
# panel stays dirty and refreshes once on show.
var _refresh_queued := false
var _dirty := false

## Give every row in the balance sheet its natural height.
##
## Both the scene rows and the ones inserted here were EXPAND_FILL, which inside a VBox
## does not mean 'fill the row' — it means 'share the container's leftover space'. Rows
## whose content differs in height then take different shares, so the gaps between them
## came out uneven and drifted again whenever a row was added or removed. Natural height
## plus the VBox separation gives one gap, the same everywhere.
## REVENUE and OPERATING COSTS fold (owner 2026-08-24). The sheet runs past the bottom of a
## 1080p screen with everything open, and a player checking their profit line should not have
## to scroll past fourteen cost rows to reach it. The header becomes a caret + title that
## toggles every row under it; the totals stay with their own section, so a folded section
## still shows what it came to.
func _build_section_accordions() -> void:
	for pair: Array in [[_revenue_section, "SectionHeader_Revenue", "revenue"],
			[_costs_section, "SectionHeader_Costs", "costs"]]:
		var section := pair[0] as VBoxContainer
		if section == null:
			continue
		var header := section.get_node_or_null(str(pair[1])) as Label
		if header == null:
			continue
		var key := str(pair[2])
		var row := HBoxContainer.new()
		row.name = "SectionHeaderRow_%s" % key
		row.add_theme_constant_override("separation", 6)
		var caret := Button.new()
		caret.flat = true
		caret.focus_mode = Control.FOCUS_NONE
		caret.custom_minimum_size = Vector2(26, 0)
		caret.add_theme_font_size_override("font_size", BALANCE_HEADER_FONT)
		caret.pressed.connect(_toggle_section.bind(key))
		row.add_child(caret)
		section.add_child(row)
		section.move_child(row, header.get_index())
		header.reparent(row)
		header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_theme_font_size_override("font_size", BALANCE_HEADER_FONT)
		_section_carets[key] = caret
		_section_expanded[key] = true
		_apply_section_expanded(key)


func _toggle_section(key: String) -> void:
	_section_expanded[key] = not bool(_section_expanded.get(key, true))
	_apply_section_expanded(key)
	if _tab_container != null and _tab_container.get_tab_title(_tab_container.current_tab) == "Balance":
		_apply_tab_size.call_deferred(_tab_container.current_tab)


func _apply_section_expanded(key: String) -> void:
	var section: VBoxContainer = _revenue_section if key == "revenue" else _costs_section
	var caret := _section_carets.get(key) as Button
	if section == null or caret == null:
		return
	var open := bool(_section_expanded.get(key, true))
	caret.text = "⌄" if open else "›"
	caret.tooltip_text = "Hide these rows" if open else "Show these rows"
	for child in section.get_children():
		if child is Control and not str(child.name).begins_with("SectionHeaderRow_"):
			(child as Control).visible = open
	# A folded section still shows what it came to.
	if not open:
		return
	if key == "costs":
		_set_transport_expanded(_transport_expanded)


## Every label on the sheet at the reading size, and every row vertically centred so a
## taller value never drags its own row out of line with the rest.
func _apply_balance_type() -> void:
	for section: Node in [_revenue_section, _costs_section, _balance_content]:
		if section != null:
			_restyle_balance_labels(section)


func _restyle_balance_labels(node: Node) -> void:
	for child in node.get_children():
		if child is Label:
			var lbl := child as Label
			if not str(lbl.name).begins_with("SectionHeader"):
				lbl.add_theme_font_size_override("font_size", BALANCE_ROW_FONT)
			lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		elif child is Container:
			_restyle_balance_labels(child)


func _normalise_balance_rows() -> void:
	for section: Node in [_revenue_section, _costs_section]:
		if section == null:
			continue
		for child in section.get_children():
			if child is Control:
				(child as Control).size_flags_vertical = Control.SIZE_FILL
		(section as VBoxContainer).add_theme_constant_override("separation", BALANCE_ROW_GAP)


func _insert_cost_row(section: VBoxContainer, after_node_name: String, label_text: String) -> Label:
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_FILL   # natural height; see _normalise_balance_rows
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


func _insert_transport_accordion(section: VBoxContainer, after_node_name: String) -> Label:
	var group := VBoxContainer.new()
	group.name = "TransportCostGroup"
	group.add_theme_constant_override("separation", 4)
	var header := HBoxContainer.new()
	header.name = "TransportCostHeader"
	header.add_theme_constant_override("separation", 8)
	group.add_child(header)
	_transport_caret = Button.new()
	_transport_caret.name = "TransportCostCaret"
	_transport_caret.flat = true
	_transport_caret.focus_mode = Control.FOCUS_NONE
	_transport_caret.custom_minimum_size = Vector2(22, 0)
	_transport_caret.pressed.connect(_toggle_transport_breakdown)
	header.add_child(_transport_caret)
	var name_label := Label.new()
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.text = "Transport"
	header.add_child(name_label)
	var value_label := Label.new()
	value_label.name = "TransportCostValue"
	value_label.custom_minimum_size = Vector2(80, 0)
	value_label.text = "-£0.00"
	header.add_child(value_label)
	for spec: Array in TRANSPORT_BREAKDOWN_ROWS:
		var row := HBoxContainer.new()
		row.name = "TransportCostRow_%s" % str(spec[0])
		row.visible = false
		row.add_theme_constant_override("separation", 8)
		var indent := Control.new()
		indent.custom_minimum_size = Vector2(30, 0)
		row.add_child(indent)
		var detail_label := Label.new()
		detail_label.text = str(spec[1])
		detail_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		detail_label.add_theme_color_override("font_color", Color(0.65, 0.72, 0.8))
		row.add_child(detail_label)
		var detail_value := Label.new()
		detail_value.name = "TransportCostValue_%s" % str(spec[0])
		detail_value.custom_minimum_size = Vector2(80, 0)
		detail_value.text = "-£0.00"
		row.add_child(detail_value)
		var key := str(spec[0])
		_transport_breakdown_values[key] = detail_value
		_transport_breakdown_amounts[key] = 0.0
		group.add_child(row)
	section.add_child(group)
	var after := section.get_node_or_null(after_node_name)
	if after != null:
		section.move_child(group, after.get_index() + 1)
	_set_transport_expanded(false)
	return value_label


func _toggle_transport_breakdown() -> void:
	_set_transport_expanded(not _transport_expanded)


func _set_transport_expanded(expanded: bool) -> void:
	_transport_expanded = expanded
	if _transport_caret == null:
		return
	_transport_caret.text = "⌄" if expanded else "›"
	_transport_caret.tooltip_text = "Hide transport cost breakdown" if expanded else "Show transport cost breakdown"
	for key: String in _transport_breakdown_values:
		var value_label := _transport_breakdown_values[key] as Label
		(value_label.get_parent() as Control).visible = expanded \
			and _transport_amount_is_visible(float(_transport_breakdown_amounts.get(key, 0.0)))
	# Expanding makes the sheet longer: grow with it while the screen allows, then scroll.
	if _tab_container != null and _tab_container.get_tab_title(_tab_container.current_tab) == "Balance":
		_apply_tab_size.call_deferred(_tab_container.current_tab)

func _insert_finance_row(section: VBoxContainer, after_node_name: String, label_text: String, default_text: String) -> Label:
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_FILL   # natural height; see _normalise_balance_rows
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
	_transport_value = _insert_transport_accordion(_costs_section, "PowerPurchaseRow")
	_proj_transport_value = _insert_cost_row(_proj_costs_section, "Proj_PowerPurchaseRow", "Transport")
	_goods_purchased_value = _insert_cost_row(_costs_section, "PowerPurchaseRow", "Goods purchased")
	_proj_goods_purchased_value = _insert_cost_row(_proj_costs_section, "Proj_PowerPurchaseRow", "Goods purchased")
	_advisor_value = _insert_cost_row(_costs_section, "LabourRow", "Advisor salaries")
	_building_tab_value = _insert_cost_row(_costs_section, "PowerPurchaseRow", "Put on building credit")
	# Running costs a new building charged to its credit window instead of paying in cash
	# this turn. It reads as a CREDIT here because the lines above already charged it in
	# full; this is the part that did not leave the bank yet. The tab settles when the
	# window closes (MatchState.tick_building_tabs).
	if _building_tab_value != null and _building_tab_value.get_parent() != null:
		_building_tab_value.get_parent().tooltip_text = "Running costs charged to a new building's credit window rather than paid in cash this turn. They are already counted in the costs above; this line takes back the part you have not actually paid yet, and the tab settles when the window closes."
	_normalise_balance_rows()
	_warehousing_value = _insert_cost_row(_costs_section, "PowerPurchaseRow", "Warehousing")
	_proj_warehousing_value = _insert_cost_row(_proj_costs_section, "Proj_PowerPurchaseRow", "Warehousing")
	_carbon_tax_value = _insert_cost_row(_costs_section, "PowerPurchaseRow", "Carbon tax")
	_proj_carbon_tax_value = _insert_cost_row(_proj_costs_section, "Proj_PowerPurchaseRow", "Carbon tax")
	# Green subsidy is INCOME: insert into the revenue sections after the power-sales row.
	var revenue_section := $MarginContainer/ModalLayout/TabContainer/Balance/MarginContainer/BalanceScroll/BalanceContent/RevenueSection as VBoxContainer
	var proj_revenue_section := $MarginContainer/ModalLayout/TabContainer/Budget/MarginContainer/BudgetContent/ScrollContainer/ProjectionContent/Proj_RevenueSection as VBoxContainer
	_green_subsidy_value = _insert_finance_row(revenue_section, "PowerSalesRow", "Green subsidy", "+£0.00")
	_proj_green_subsidy_value = _insert_finance_row(proj_revenue_section, "Proj_PowerSalesRow", "Green subsidy", "+£0.00")
	var projection_content := $MarginContainer/ModalLayout/TabContainer/Budget/MarginContainer/BudgetContent/ScrollContainer/ProjectionContent as VBoxContainer
	_profit_sharing_value = _insert_finance_row(_balance_content, "DividendsRow", "Profit Sharing", "-£0.00")
	_proj_profit_sharing_value = _insert_finance_row(projection_content, "Proj_DividendsRow", "Profit Sharing", "-£0.00")
	# After every row exists, not before: both passes walk the finished sheet.
	_normalise_balance_rows()
	_apply_balance_type()
	_build_section_accordions()
	close_button.pressed.connect(hide)
	title_label.text = "Money"
	# Own copy of the shared navy stylebox: keep the navy fill, drop the cream border,
	# and zero content_margin so the brass overlay reaches the panel edge.
	var _base_sb := get_theme_stylebox("panel")
	if _base_sb is StyleBoxFlat:
		var _sb := (_base_sb as StyleBoxFlat).duplicate() as StyleBoxFlat
		_sb.set_border_width_all(0)
		_sb.set_content_margin_all(0)
		add_theme_stylebox_override("panel", _sb)
	for _side in ["left", "right", "top", "bottom"]:
		$MarginContainer.add_theme_constant_override("margin_" + _side, 26)
	
	take_loan_button.pressed.connect(_on_take_loan_pressed)
	
	MatchState.money_changed.connect(_on_money_changed)
	LoanState.loans_updated.connect(_on_loans_updated)
	LoanState.payment_made.connect(_on_payment_made)

	_refresh()
	Production.turn_processed.connect(_on_turn_processed)
	labour_low_button.pressed.connect(_on_labour_pressed.bind(0.8))
	labour_normal_button.pressed.connect(_on_labour_pressed.bind(1.00))
	labour_high_button.pressed.connect(_on_labour_pressed.bind(1.2))
	_refresh_labour_buttons()

	MatchState.labour_multiplier_changed.connect(_on_labour_multiplier_changed)
	MatchState.workforce_policies_changed.connect(_queue_refresh)
	MarketState.prices_updated.connect(_queue_refresh)
	_refresh_balance_sheet()
	_refresh_projection()

	MatchState.building_added.connect(_on_buildings_changed)
	MatchState.building_removed.connect(_on_buildings_changed)
	visibility_changed.connect(_on_panel_visibility_changed)

	_chart_revenue_button.pressed.connect(_on_chart_mode_pressed.bind("revenue"))
	_chart_costs_button.pressed.connect(_on_chart_mode_pressed.bind("costs"))
	_build_sales_tab()
	_build_purchases_tab()
	_hide_redundant_tabs()
	_tab_container.tab_changed.connect(_on_tab_changed)
	get_viewport().size_changed.connect(_on_viewport_resized)
	open_tab("Balance")
	add_child(preload("res://scripts/brass_pipe_frame.gd").new())   # brass frame, drawn on top

# The Treasury mini-panel owns the compact cash snapshot. Keep the detailed
# Balance, Loans, and Charts views here; Stats and Budget are no longer exposed
# as tabs, while their nodes stay alive for save-compatible calculations.
func _hide_redundant_tabs() -> void:
	for tab_name in ["Stats", "Budget"]:
		for index in _tab_container.get_tab_count():
			if _tab_container.get_tab_title(index) == tab_name:
				_tab_container.set_tab_hidden(index, true)
				break

func open_tab(tab_name: String) -> void:
	for index in _tab_container.get_tab_count():
		if _tab_container.get_tab_title(index) != tab_name or _tab_container.is_tab_hidden(index):
			continue
		_tab_container.current_tab = index
		_on_tab_changed(index)
		return
	push_warning("[MoneyPanel] Requested unavailable tab: %s" % tab_name)


## Stable tutorial entry point for the full Balance sheet (the top-bar money
## widget normally opens a compact treasury flyout instead).
func open_transport_breakdown() -> void:
	open_tab("Balance")
	_set_transport_expanded(true)
	show()
	PanelStack.push(self)
	_queue_refresh()


func close_for_tutorial() -> void:
	if visible:
		PanelStack.remove(self)
	hide()


## The opening Capital exercise and the west-coast factory lesson are intentionally
## separate financial examples. Drop the former's local chart caches at the handoff.
func reset_for_tutorial_handoff() -> void:
	_chart_history.clear()
	_sales_history.clear()
	_purchases_history.clear()
	_queue_refresh()

func _on_turn_processed(_summary: Dictionary) -> void:
	# History capture must run even while hidden — it's data, not display.
	_record_chart_history(_summary)
	_queue_refresh()

func _on_money_changed(_amount: float) -> void:
	_queue_refresh()

func _on_payment_made(_total: float) -> void:
	_queue_refresh()

func _on_loans_updated() -> void:
	_queue_refresh()

func _queue_refresh(_arg: Variant = null) -> void:
	_dirty = true
	if _refresh_queued:
		return
	_refresh_queued = true
	call_deferred("_apply_refresh")

func _apply_refresh() -> void:
	_refresh_queued = false
	if not _dirty:
		return
	if not visible:
		return  # stays dirty; _on_panel_visibility_changed refreshes on show
	_dirty = false
	_refresh()
	_refresh_balance_sheet()
	_refresh_projection()
	_refresh_chart()
	_refresh_sales()
	_refresh_purchases()

func _on_panel_visibility_changed() -> void:
	if not visible:
		return
	# Re-fit on show: global_position is only meaningful once the panel has been laid out.
	_apply_tab_size(_tab_container.current_tab)
	if _dirty:
		_queue_refresh()

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

# ── The balance sheet's arithmetic, as pure functions of the turn summary ───────────────────
# Static and summary-only so the test suite can hold the bottom line against the top bar's
# money_in − money_out without instantiating the panel. They diverged silently twice: advisor
# salaries were charged to cash with no row here at all, and building-tab deferrals were shown
# as a debt total while the deferred running costs were still charged as if paid. Any new cash
# movement in production.gd needs a line here, or the two numbers part again.

static func total_revenue_of(s: Dictionary) -> float:
	return float(s.get("goods_sales_revenue", 0.0)) + float(s.get("power_sales_revenue", 0.0)) \
		+ float(s.get("green_subsidy_received", 0.0))

static func operating_costs_of(s: Dictionary) -> float:
	return float(s.get("maintenance_paid", 0.0)) + float(s.get("labour_paid", 0.0)) \
		+ float(s.get("advisor_paid", 0.0)) + float(s.get("transport_paid", 0.0)) \
		+ float(s.get("power_purchase_cost", 0.0)) + float(s.get("goods_purchased_cost", 0.0)) \
		+ float(s.get("warehousing_paid", 0.0)) + float(s.get("carbon_tax_paid", 0.0)) \
		- float(s.get("building_tab_carried", 0.0))

## MUST equal money_in − money_out for the same turn — that is what the row promises and what
## the top bar and the Treasury mini-panel both show.
static func net_cash_of(s: Dictionary) -> float:
	return total_revenue_of(s) - operating_costs_of(s) - float(s.get("interest_paid", 0.0)) \
		- float(s.get("taxes_paid", 0.0)) - float(s.get("dividends_paid", 0.0)) \
		- float(s.get("profit_sharing_paid", 0.0))


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
	var advisor: float = summary.get("advisor_paid", 0.0)
	var tab_carried: float = summary.get("building_tab_carried", 0.0)
	var transport: float = summary.get("transport_paid", 0.0)
	var power_purchase: float = summary.get("power_purchase_cost", 0.0)
	var goods_purchased: float = summary.get("goods_purchased_cost", 0.0)
	var warehousing: float = summary.get("warehousing_paid", 0.0)
	var interest: float = summary.get("interest_paid", 0.0)
	var tax: float = summary.get("taxes_paid", 0.0)
	var dividends: float = summary.get("dividends_paid", 0.0)
	var profit_sharing: float = summary.get("profit_sharing_paid", 0.0)
	var carbon_tax: float = summary.get("carbon_tax_paid", 0.0)
	var green_subsidy: float = summary.get("green_subsidy_received", 0.0)

	# Derived through the statics above, so the displayed total and the tested one cannot drift.
	var total_revenue: float = total_revenue_of(summary)
	var total_costs: float = operating_costs_of(summary)
	var operating_profit: float = total_revenue - total_costs
	var pretax: float = operating_profit - interest
	var posttax: float = pretax - tax
	var net_cashflow: float = net_cash_of(summary)
	
	# Render
	goods_value.text = "+£%.2f" % goods_revenue
	power_sales_value.text = "+£%.2f" % power_revenue
	total_revenue_value.text = "+£%.2f" % total_revenue
	
	maintenance_value.text = "-£%.2f" % maintenance
	labour_value.text = "-£%.2f" % labour
	_advisor_value.text = "-£%.2f" % advisor
	power_purchase_value.text = "-£%.2f" % power_purchase
	_transport_value.text = "-£%.2f" % transport
	_render_transport_breakdown(transport, summary.get("transport_breakdown", {}))
	_goods_purchased_value.text = "-£%.2f" % goods_purchased
	_warehousing_value.text = "-£%.2f" % warehousing
	# A CREDIT, not a charge: these running costs are charged in full on the lines above and
	# then carried, so the row gives the money back and the total tells the truth. What is owed
	# across every tab is a running balance, not this turn's movement — it goes in the tooltip.
	_building_tab_value.text = "+£%.2f" % tab_carried
	_building_tab_value.tooltip_text = "Deferred onto building tabs this turn.\nOutstanding across all tabs: £%.2f" % MatchState.total_building_tab_debt()
	_carbon_tax_value.text = "-£%.2f" % carbon_tax
	_green_subsidy_value.text = "+£%.2f" % green_subsidy
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


func _render_transport_breakdown(transport: float, raw_breakdown: Dictionary) -> void:
	var breakdown: Dictionary = raw_breakdown.duplicate()
	# Direct building-output sales use MarketState's more granular export keys.
	# Fold those into the same export row used by stockpile sales and imports.
	breakdown["port_outbound"] = float(breakdown.get("port_outbound", 0.0)) \
		+ float(breakdown.get("port_fees", 0.0)) + float(breakdown.get("port_insurance", 0.0))
	breakdown.erase("port_fees")
	breakdown.erase("port_insurance")
	var component_total := 0.0
	for spec: Array in TRANSPORT_BREAKDOWN_ROWS:
		component_total += float(breakdown.get(str(spec[0]), 0.0))
	# Preserve reconciliation for an old summary or an as-yet-unclassified cost.
	breakdown["roads"] = float(breakdown.get("roads", 0.0)) + (transport - component_total)
	var remaining := transport
	for index in TRANSPORT_BREAKDOWN_ROWS.size():
		var spec: Array = TRANSPORT_BREAKDOWN_ROWS[index]
		var key := str(spec[0])
		var amount: float = float(breakdown.get(key, 0.0))
		# The final component receives the fractional-penny remainder, so the
		# breakdown always adds up to the displayed Transport total.
		if index == TRANSPORT_BREAKDOWN_ROWS.size() - 1:
			amount = remaining
		else:
			amount = snappedf(amount, 0.01)
			remaining -= amount
		amount = snappedf(amount, 0.01)
		_transport_breakdown_amounts[key] = amount
		var value_label := _transport_breakdown_values.get(key) as Label
		if value_label != null:
			value_label.text = "-£%.2f" % amount
			(value_label.get_parent() as Control).visible = _transport_expanded \
				and _transport_amount_is_visible(amount)
	# A newly used mode can add a row, while a superseded mode can remove one. Keep
	# the Balance sheet fitted to its visible breakdown rather than its full mode list.
	if _transport_expanded and _tab_container != null \
			and _tab_container.get_tab_title(_tab_container.current_tab) == "Balance":
		_apply_tab_size.call_deferred(_tab_container.current_tab)


func _transport_amount_is_visible(amount: float) -> bool:
	# Match the two-decimal money display: a component rendered as £0.00 is not a
	# useful breakdown row, and stale zero rows make old transport modes look active.
	return not is_zero_approx(snappedf(amount, 0.01))

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
	_proj_warehousing_value.text = "-£%.2f" % proj.get("warehousing", 0.0)
	_proj_carbon_tax_value.text = "-£%.2f" % proj.get("carbon_tax", 0.0)
	_proj_green_subsidy_value.text = "+£%.2f" % proj.get("green_subsidy", 0.0)
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
	var carbon_tax: float = 0.0
	var green_mw: float = 0.0
	var proj_turn: int = int(TurnManager.current_turn)

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
			# Green generation qualifies for the subsidy (mirrors Production._power_quality).
			var internal := str(Catalog.get_building(str(building.get("building_id", ""))).get("internal_name", ""))
			if internal in EconomyConfig.POWER_INTERMITTENT_BUILDINGS or internal in EconomyConfig.POWER_STEADY_BUILDINGS:
				green_mw += float(output_qty)
			else:
				for inp in recipe.get("inputs", []):
					if str(inp.get("internal_name", "")) in EconomyConfig.POWER_STEADY_FUELS:
						green_mw += float(output_qty)
						break
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
			if in_gid == "":
				continue
			# Carbon levy on taxed inputs (charged regardless of sourcing).
			carbon_tax += PolicyState.carbon_charge(in_gid, int(input.get("qty", 0)), proj_turn)
			if MatchState.is_input_tile_only(inst_id, in_gid):
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

	# Warehousing on what's stored right now (per unit × transport-class rate).
	var warehousing: float = 0.0
	for wt in Stockpile.tiles_with_stock():
		if not str(wt).begins_with("tile_"):
			continue
		var wtot: Dictionary = Stockpile.get_tile_totals(wt)
		for wg in wtot:
			warehousing += float(wtot[wg]) * EconomyConfig.warehousing_cost_per_unit(str(wg))

	# Green subsidy on projected green generation.
	var green_subsidy: float = green_mw * PolicyState.green_subsidy_rate(proj_turn)

	# Compute the chain
	var total_revenue: float = goods_revenue + power_revenue + green_subsidy
	var total_costs: float = maintenance + labour + transport + power_purchase + goods_purchased + warehousing + carbon_tax
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
		"warehousing": warehousing,
		"carbon_tax": carbon_tax,
		"green_subsidy": green_subsidy,
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

func _calculate_projected_labour_cost(building: Dictionary) -> float:
	# Mirrors Production._calculate_labour_cost so projection matches reality.
	# Recipe-owned workforce takes precedence once the labour migration is present.
	var building_data: Dictionary = Catalog.get_building(building.get("building_id", ""))
	var recipe: Dictionary = Catalog.get_recipe(building.get("recipe_id", ""))
	var source: Dictionary = recipe if int(recipe.get("labour_unskilled_required", -1)) >= 0 else building_data
	var unskilled := int(source.get("labour_unskilled_required", EconomyConfig.STUB_UNSKILLED_PER_BUILDING))
	var skilled := int(source.get("labour_skilled_required", EconomyConfig.STUB_SKILLED_PER_BUILDING))
	var high_skilled := int(source.get("labour_h_skilled_required", EconomyConfig.STUB_HIGH_SKILLED_PER_BUILDING))
	var base_cost: float = (
		unskilled * EconomyConfig.LABOUR_UNSKILLED_RATE
		+ skilled * EconomyConfig.LABOUR_SKILLED_RATE
		+ high_skilled * EconomyConfig.LABOUR_HIGH_SKILLED_RATE
	)
	# Labour slider + workforce policies apply additively to the 100% base (matches
	# Production._calculate_labour_cost; no compounding).
	return base_cost * MatchState.labour_policy_factor()

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
	# The Charts tab needs more room; Balance sizes itself to the sheet and the screen;
	# every other tab uses the compact panel size.
	custom_minimum_size = Vector2.ZERO
	match _tab_container.get_tab_title(idx):
		"Charts":
			# Capped to the screen like the Balance tab — a fixed height taller than the
			# viewport puts the legend's buttons under the bottom dock.
			var avail: float = get_viewport_rect().size.y - global_position.y - PANEL_SCREEN_MARGIN
			size = Vector2(CHART_PANEL_SIZE.x, minf(CHART_PANEL_SIZE.y, maxf(420.0, avail)))
		"Balance":
			size = Vector2(DEFAULT_PANEL_SIZE.x, _balance_panel_height())
		_:
			size = DEFAULT_PANEL_SIZE


## Behind BalanceScroll the sheet no longer pushes the panel taller — which is the point, it was
## 1117 px on a 1080p screen — but it means nothing else asks for height either, so the panel has
## to work it out: as tall as the sheet wants, capped to what fits below its top edge. Whatever
## does not fit scrolls. get_combined_minimum_size() here is the panel WITHOUT the sheet (a
## ScrollContainer's minimum is zero), i.e. header + tab bar + margins.
func _balance_panel_height() -> float:
	var chrome: float = get_combined_minimum_size().y
	var wanted: float = chrome + _balance_content.get_combined_minimum_size().y
	var available: float = get_viewport_rect().size.y - global_position.y - PANEL_SCREEN_MARGIN
	return maxf(MIN_BALANCE_PANEL_HEIGHT, minf(wanted, available))


## The viewport can change under a live panel (window resize, fullscreen toggle).
func _on_viewport_resized() -> void:
	if _tab_container != null:
		_apply_tab_size(_tab_container.current_tab)

func _on_chart_mode_pressed(mode: String) -> void:
	_chart_mode = mode
	_chart_revenue_button.button_pressed = (mode == "revenue")
	_chart_costs_button.button_pressed = (mode == "costs")
	_refresh_chart()

func _refresh_chart() -> void:
	if _chart != null and _chart.has_method("set_data"):
		_chart.set_data(_chart_history, _chart_mode)

# ── Sales tab: which goods (and power) made money from sales ────────────────
var _sales_tab_root: VBoxContainer
var _sales_history: Array = []   # last CHART_MAX_TURNS of {goods: sold-dict, power: float}

func _build_sales_tab() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "Sales"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 10)
	scroll.add_child(margin)
	_sales_tab_root = VBoxContainer.new()
	_sales_tab_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sales_tab_root.add_theme_constant_override("separation", 8)
	margin.add_child(_sales_tab_root)
	_tab_container.add_child(scroll)

func _refresh_sales() -> void:
	if _sales_tab_root == null:
		return
	for c in _sales_tab_root.get_children():
		c.queue_free()
	if _sales_history.is_empty():
		var empty := Label.new()
		empty.text = "No sales yet — income by good appears here after your first turn."
		empty.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		_sales_tab_root.add_child(empty)
		return
	_add_sales_section("Last turn", [_sales_history.back()])
	if _sales_history.size() > 1:
		_add_sales_section("Last %d turns" % _sales_history.size(), _sales_history)

func _add_sales_section(title: String, entries: Array) -> void:
	# Aggregate per good across the given turns; power is its own row.
	var by_good: Dictionary = {}
	var power_total := 0.0
	for e in entries:
		var goods: Dictionary = (e as Dictionary).get("goods", {})
		for gid in goods:
			var rec: Dictionary = by_good.get(str(gid), {"qty": 0, "revenue": 0.0})
			rec.qty = int(rec.qty) + int((goods[gid] as Dictionary).get("qty", 0))
			rec.revenue = float(rec.revenue) + float((goods[gid] as Dictionary).get("revenue", 0.0))
			by_good[str(gid)] = rec
		power_total += float((e as Dictionary).get("power", 0.0))

	var rows: Array = []
	for gid in by_good:
		rows.append({"gid": str(gid), "label": Catalog.get_display_name(str(gid)),
			"qty": int(by_good[gid].qty), "amount": float(by_good[gid].revenue)})
	if power_total > 0.0:
		rows.append({"gid": "", "label": "Power (grid exports)", "qty": -1, "amount": power_total})
	rows = rows.filter(func(r: Dictionary) -> bool: return float(r.amount) > 0.005)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.amount) > float(b.amount))
	_add_breakdown_section(_sales_tab_root, title, rows, "No sales income in this window.", "Total sales income")

# A per-good breakdown section (icon · name · ×qty · bar · £amount) shared by Sales and Purchases.
func _add_breakdown_section(root: VBoxContainer, title: String, rows: Array, empty_text: String, total_label: String) -> void:
	var header := Label.new()
	header.text = title
	header.theme_type_variation = &"Section"
	root.add_child(header)
	if rows.is_empty():
		var none := Label.new()
		none.text = empty_text
		none.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		root.add_child(none)
		return
	var total := 0.0
	var max_amt := 0.0
	for r in rows:
		total += float(r.amount)
		max_amt = maxf(max_amt, float(r.amount))
	for r in rows:
		root.add_child(_breakdown_row(str(r.get("gid", "")), str(r.label), int(r.qty), float(r.amount), max_amt))
	var total_row := HBoxContainer.new()
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(30, 0)
	total_row.add_child(spacer)
	var total_name := Label.new()
	total_name.text = total_label
	total_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	total_row.add_child(total_name)
	var total_val := Label.new()
	total_val.text = "£%.2f" % total
	total_val.theme_type_variation = &"Numeric"
	total_row.add_child(total_val)
	root.add_child(total_row)

## Good-icon size in the sales / purchases breakdowns.
const BREAKDOWN_ICON := 40

# One breakdown row: plain good icon (or spacer for power/no-good) · name · ×qty · bar · £amount.
func _breakdown_row(gid: String, label: String, qty: int, amount: float, max_amount: float) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	if gid != "":
		# Frameless and bigger: at 30 px the metal bevel took most of the cell and the good
		# itself was a few pixels of art. Cream plate, rounded, 40 px (owner 2026-08-23).
		var icon := UIHelpers.make_plain_good_icon(gid, Catalog.get_internal_name(gid), BREAKDOWN_ICON)
		icon.custom_minimum_size = Vector2(BREAKDOWN_ICON, BREAKDOWN_ICON)
		row.add_child(icon)
	else:
		var sp := Control.new()
		sp.custom_minimum_size = Vector2(BREAKDOWN_ICON, 0)
		row.add_child(sp)
	var name_l := Label.new()
	name_l.text = label
	name_l.custom_minimum_size = Vector2(150, 0)
	name_l.clip_text = true
	row.add_child(name_l)
	var qty_l := Label.new()
	qty_l.text = ("×%d" % qty) if qty >= 0 else ""
	qty_l.custom_minimum_size = Vector2(54, 0)
	qty_l.add_theme_color_override("font_color", Color(0.65, 0.72, 0.8))
	row.add_child(qty_l)
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = amount / max_amount if max_amount > 0.0 else 0.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 10)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)
	var amt_l := Label.new()
	amt_l.text = "£%.2f" % amount
	amt_l.theme_type_variation = &"Numeric"
	amt_l.custom_minimum_size = Vector2(88, 0)
	amt_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(amt_l)
	return row

# ── Purchases tab: what we PAID to buy each good (mirrors Sales) ─────────────
var _purchases_tab_root: VBoxContainer
var _purchases_history: Array = []   # last CHART_MAX_TURNS of {goods: {gid: {qty, cost}}}

func _build_purchases_tab() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "Purchases"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 10)
	scroll.add_child(margin)
	_purchases_tab_root = VBoxContainer.new()
	_purchases_tab_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_purchases_tab_root.add_theme_constant_override("separation", 8)
	margin.add_child(_purchases_tab_root)
	_tab_container.add_child(scroll)

func _refresh_purchases() -> void:
	if _purchases_tab_root == null:
		return
	for c in _purchases_tab_root.get_children():
		c.queue_free()
	if _purchases_history.is_empty():
		var empty := Label.new()
		empty.text = "No purchases yet — spend by good (materials bought from the market) appears here after your first turn."
		empty.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		_purchases_tab_root.add_child(empty)
		return
	_add_purchases_section("Last turn", [_purchases_history.back()])
	if _purchases_history.size() > 1:
		_add_purchases_section("Last %d turns" % _purchases_history.size(), _purchases_history)

func _add_purchases_section(title: String, entries: Array) -> void:
	var by_good: Dictionary = {}
	for e in entries:
		var goods: Dictionary = (e as Dictionary).get("goods", {})
		for gid in goods:
			var rec: Dictionary = by_good.get(str(gid), {"qty": 0, "cost": 0.0})
			rec.qty = int(rec.qty) + int((goods[gid] as Dictionary).get("qty", 0))
			rec.cost = float(rec.cost) + float((goods[gid] as Dictionary).get("cost", 0.0))
			by_good[str(gid)] = rec
	var rows: Array = []
	for gid in by_good:
		rows.append({"gid": str(gid), "label": Catalog.get_display_name(str(gid)),
			"qty": int(by_good[gid].qty), "amount": float(by_good[gid].cost)})
	rows = rows.filter(func(r: Dictionary) -> bool: return float(r.amount) > 0.005)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.amount) > float(b.amount))
	_add_breakdown_section(_purchases_tab_root, title, rows, "No material purchases in this window.", "Total spent on purchases")

func _record_chart_history(summary: Dictionary) -> void:
	# Per-good sales history for the Sales tab (same 10-turn window as charts).
	_sales_history.append({
		"goods": (summary.get("sold", {}) as Dictionary).duplicate(true),
		"power": float(summary.get("power_sales_revenue", 0.0)),
	})
	while _sales_history.size() > CHART_MAX_TURNS:
		_sales_history.pop_front()
	# Per-good PURCHASE history for the Purchases tab (units bought + £ paid, market inputs).
	var pq: Dictionary = summary.get("purchased", {})
	var pc: Dictionary = summary.get("purchased_cost", {})
	var pgoods: Dictionary = {}
	for gid in pq:
		pgoods[str(gid)] = {"qty": int(pq[gid]), "cost": float(pc.get(gid, 0.0))}
	_purchases_history.append({"goods": pgoods})
	while _purchases_history.size() > CHART_MAX_TURNS:
		_purchases_history.pop_front()
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
	revenue["green_subsidy"] = float(summary.get("green_subsidy_received", 0.0))

	# Goods purchased, split by tier. Freight rides in on the same order but is its own series
	# below — splitting it across the goods tiers would hide the single largest cost an empire
	# has, which is exactly what it did before: transport was recorded nowhere and charted
	# nowhere, so the Costs chart quietly understated every turn by the whole freight bill.
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
	costs["transport"] = float(summary.get("transport_paid", 0.0))
	costs["warehousing"] = float(summary.get("warehousing_paid", 0.0))
	costs["advisor"] = float(summary.get("advisor_paid", 0.0))
	costs["carbon_tax"] = float(summary.get("carbon_tax_paid", 0.0))
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
