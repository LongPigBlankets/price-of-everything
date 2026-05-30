extends Control

const BUILDING_LEDGER_PANEL_SCENE := preload("res://scenes/building_ledger_panel.tscn")

# Bottom-menu buttons that have multi-resolution circular art in
# assets/icons/ui_icons/{100,200,400}/.
const MENU_ICONS := {
	"ConstructButton": "construct",
	"ResourcesButton": "resources",
	"BuildingsButton": "buildings",
	"MapmodesButton": "map_overlays",
	"MarketButton": "markets",
	"PoliticsButton": "politics",
	"TechButton": "tech",
}

@onready var bottom_menu = %BottomMenu
@onready var construct_panel = %ConstructPanel
@onready var resource_panel: PanelContainer = %ResourcePanel
@onready var market_panel: PanelContainer = %MarketPanel
@onready var mapmodes_button: Button = %MapmodesButton
@onready var mapmodes_panel: PanelContainer = %MapModesPanel
@onready var top_bar: PanelContainer = %TopBar
@onready var money_panel: PanelContainer = %MoneyPanel
@onready var take_loan_dialog: PanelContainer = %TakeLoanDialog

# Building ledger is instantiated lazily on first open (no main.tscn edit needed).
var building_ledger_panel: PanelContainer = null

func _ready() -> void:
	_apply_menu_icons()
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

func _icon_tier() -> String:
	# Pick icon resolution from window height: sub-1080p -> 100, 1080p -> 200,
	# above 1080p -> 400. The buttons render small, so a larger source downscales
	# crisply (with the BottomMenu's Linear texture filter).
	var h := DisplayServer.window_get_size().y
	if h >= 1440:
		return "400"
	if h >= 1080:
		return "200"
	return "100"

func _apply_menu_icons() -> void:
	var tier := _icon_tier()
	for button_name in MENU_ICONS:
		var path := "res://assets/icons/ui_icons/%s/%s.png" % [tier, MENU_ICONS[button_name]]
		if not ResourceLoader.exists(path):
			continue
		var button := get_node_or_null("%" + button_name) as Button
		if button != null:
			button.icon = load(path)

func _hide_all_panels() -> void:
	_set_panel_visible(construct_panel, false)
	_set_panel_visible(resource_panel, false)
	_set_panel_visible(market_panel, false)
	_set_panel_visible(mapmodes_panel, false)
	_set_panel_visible(money_panel, false)
	if is_instance_valid(building_ledger_panel):
		_set_panel_visible(building_ledger_panel, false)

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
	_hide_all_panels()
	if not is_instance_valid(building_ledger_panel):
		building_ledger_panel = BUILDING_LEDGER_PANEL_SCENE.instantiate()
		# Add as sibling to the other panels so it lives in HUDContent.
		construct_panel.get_parent().add_child(building_ledger_panel)
		building_ledger_panel.hide()
		building_ledger_panel.close_requested.connect(
			func(): _set_panel_visible(building_ledger_panel, false)
		)
	_set_panel_visible(building_ledger_panel, true)

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
