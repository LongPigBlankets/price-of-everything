extends Control

# --- UI References ---
@onready var bottom_menu = $BottomMenu
@onready var construct_panel = $ConstructPanel  # adjust path to wherever it actually lives
# Add references to other panels as you build them:
# @onready var resources_panel = $ResourcesPanel
# @onready var buildings_panel = $BuildingsPanel
# @onready var market_panel = $MarketPanel
# @onready var politics_panel = $PoliticsPanel
# @onready var tech_panel = $TechPanel

func _ready() -> void:
	# Connect the 6 bottom menu buttons
	$BottomMenu/ConstructButton.pressed.connect(_on_construct_pressed)
	$BottomMenu/ResourcesButton.pressed.connect(_on_resources_pressed)
	$BottomMenu/BuildingsButton.pressed.connect(_on_buildings_pressed)
	$BottomMenu/MarketButton.pressed.connect(_on_market_pressed)
	$BottomMenu/PoliticsButton.pressed.connect(_on_politics_pressed)
	$BottomMenu/TechButton.pressed.connect(_on_tech_pressed)
	
	# All panels start hidden
	construct_panel.hide()

# --- Button Handlers ---

func _on_construct_pressed() -> void:
	construct_panel.show()

func _on_resources_pressed() -> void:
	print("Resources panel not yet implemented")

func _on_buildings_pressed() -> void:
	print("Buildings panel not yet implemented")

func _on_market_pressed() -> void:
	print("Market panel not yet implemented")

func _on_politics_pressed() -> void:
	print("Politics panel not yet implemented")

func _on_tech_pressed() -> void:
	print("Tech panel not yet implemented")
