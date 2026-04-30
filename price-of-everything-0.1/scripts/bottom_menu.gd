extends Control

@onready var bottom_menu = %BottomMenu
@onready var construct_panel = %ConstructPanel
@onready var resource_panel: PanelContainer = %ResourcePanel
@onready var market_panel: PanelContainer = %MarketPanel
@onready var mapmodes_button: Button = %MapmodesButton
@onready var mapmodes_panel: PanelContainer = %MapModesPanel
@onready var top_bar: PanelContainer = %TopBar
@onready var money_panel: PanelContainer = %MoneyPanel


func _ready() -> void:
	%ConstructButton.pressed.connect(_on_construct_pressed)
	%ResourcesButton.pressed.connect(_on_resources_pressed)
	%BuildingsButton.pressed.connect(_on_buildings_pressed)
	%MarketButton.pressed.connect(_on_market_pressed)
	%PoliticsButton.pressed.connect(_on_politics_pressed)
	%TechButton.pressed.connect(_on_tech_pressed)
	
	# All panels start hidden
	construct_panel.hide()
	resource_panel.hide()
	market_panel.hide()
	mapmodes_button.pressed.connect(_on_mapmodes_pressed)
	mapmodes_panel.hide()
	top_bar.money_widget_clicked.connect(_on_money_widget_clicked)
	money_panel.hide()

func _hide_all_panels() -> void:
	construct_panel.hide()
	resource_panel.hide()
	market_panel.hide()
	mapmodes_panel.hide()
	money_panel.hide()

func _on_construct_pressed() -> void:
	_hide_all_panels()
	construct_panel.show()

func _on_resources_pressed() -> void:
	_hide_all_panels()
	resource_panel.show()

func _on_mapmodes_pressed() -> void:
	mapmodes_panel.show()

func _on_market_pressed() -> void:
	_hide_all_panels()
	market_panel.show()

func _on_buildings_pressed() -> void:
	print("Buildings panel not yet implemented")

func _on_politics_pressed() -> void:
	print("Politics panel not yet implemented")

func _on_tech_pressed() -> void:
	print("Tech panel not yet implemented")
	
func _on_money_widget_clicked() -> void:
	_hide_all_panels()
	money_panel.show()
