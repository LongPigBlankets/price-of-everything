extends Control

@onready var bottom_menu = $BottomMenu
@onready var construct_panel = $ConstructPanel
@onready var resource_panel: PanelContainer = %ResourcePanel
@onready var market_panel: PanelContainer = %MarketPanel

func _ready() -> void:
	$BottomMenu/ConstructButton.pressed.connect(_on_construct_pressed)
	$BottomMenu/ResourcesButton.pressed.connect(_on_resources_pressed)
	$BottomMenu/BuildingsButton.pressed.connect(_on_buildings_pressed)
	$BottomMenu/MarketButton.pressed.connect(_on_market_pressed)
	$BottomMenu/PoliticsButton.pressed.connect(_on_politics_pressed)
	$BottomMenu/TechButton.pressed.connect(_on_tech_pressed)
	
	# All panels start hidden
	construct_panel.hide()
	resource_panel.hide()
	market_panel.hide()

func _hide_all_panels() -> void:
	construct_panel.hide()
	resource_panel.hide()
	market_panel.hide()

func _on_construct_pressed() -> void:
	_hide_all_panels()
	construct_panel.show()

func _on_resources_pressed() -> void:
	_hide_all_panels()
	resource_panel.show()

func _on_market_pressed() -> void:
	_hide_all_panels()
	market_panel.show()

func _on_buildings_pressed() -> void:
	print("Buildings panel not yet implemented")

func _on_politics_pressed() -> void:
	print("Politics panel not yet implemented")

func _on_tech_pressed() -> void:
	print("Tech panel not yet implemented")
