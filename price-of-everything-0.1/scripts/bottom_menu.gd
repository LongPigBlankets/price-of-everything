extends Control

@onready var bottom_menu = %BottomMenu
@onready var construct_panel = %ConstructPanel
@onready var resource_panel: PanelContainer = %ResourcePanel
@onready var market_panel: PanelContainer = %MarketPanel
@onready var mapmodes_button: Button = %MapmodesButton
@onready var mapmodes_panel: PanelContainer = %MapModesPanel
@onready var top_bar: PanelContainer = %TopBar
@onready var money_panel: PanelContainer = %MoneyPanel
@onready var take_loan_dialog: PanelContainer = %TakeLoanDialog

func _ready() -> void:
	%ConstructButton.pressed.connect(_on_construct_pressed)
	%ResourcesButton.pressed.connect(_on_resources_pressed)
	%BuildingsButton.pressed.connect(_on_buildings_pressed)
	%MarketButton.pressed.connect(_on_market_pressed)
	%PoliticsButton.pressed.connect(_on_politics_pressed)
	%TechButton.pressed.connect(_on_tech_pressed)
	money_panel.take_loan_dialog = take_loan_dialog
	take_loan_dialog.loan_confirmed.connect(_on_loan_confirmed)
	take_loan_dialog.hide()
	
	# All panels start hidden
	construct_panel.hide()
	resource_panel.hide()
	market_panel.hide()
	mapmodes_button.pressed.connect(_on_mapmodes_pressed)
	mapmodes_panel.hide()
	top_bar.money_widget_clicked.connect(_on_money_widget_clicked)
	money_panel.hide()

func _hide_all_panels() -> void:
	_set_panel_visible(construct_panel, false)
	_set_panel_visible(resource_panel, false)
	_set_panel_visible(market_panel, false)
	_set_panel_visible(mapmodes_panel, false)
	_set_panel_visible(money_panel, false)

func _set_panel_visible(panel: Control, show_it: bool) -> void:
	if show_it:
		panel.show()
		PanelStack.push(panel)
	else:
		if panel.visible:
			PanelStack.remove(panel)
		panel.hide()

func hide_bottom_menu() -> void:
	_hide_all_panels()
	bottom_menu.hide()

func show_bottom_menu() -> void:
	bottom_menu.show()

func _on_construct_pressed() -> void:
	_hide_all_panels()
	_set_panel_visible(construct_panel, true)

func _on_resources_pressed() -> void:
	_hide_all_panels()
	_set_panel_visible(resource_panel, true)

func _on_mapmodes_pressed() -> void:
	_set_panel_visible(mapmodes_panel, true)

func _on_market_pressed() -> void:
	_hide_all_panels()
	_set_panel_visible(market_panel, true)

func _on_buildings_pressed() -> void:
	print("Buildings panel not yet implemented")

func _on_politics_pressed() -> void:
	print("Politics panel not yet implemented")

func _on_tech_pressed() -> void:
	print("Tech panel not yet implemented")
	
func _on_money_widget_clicked() -> void:
	_hide_all_panels()
	_set_panel_visible(money_panel, true)
	
func _on_loan_confirmed(amount: float) -> void:
	var ok: bool = LoanState.take_loan(amount)
	if not ok:
		print("[HUD] Loan request failed for £%.2f" % amount)
	# Auto-switch Money panel to Loans tab
	var tab_container: TabContainer = money_panel.get_node("MarginContainer/ModalLayout/TabContainer")
	tab_container.current_tab = 3  # 0=Stats, 1=Balance, 2=Budget, 3=Loans
	money_panel.show()
