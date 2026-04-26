extends Node2D

@onready var terrain_layer: TileMapLayer = %TerrainLayer
@onready var info_panel: PanelContainer = %TileInfoPanel
@onready var building_panel: PanelContainer = %BuildingDetailPanel

func _ready() -> void:
	terrain_layer.tile_selected.connect(info_panel.show_tile)
	info_panel.building_clicked.connect(building_panel.show_building)
	print("WorldMap ready, signals connected")
