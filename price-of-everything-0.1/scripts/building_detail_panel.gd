extends PanelContainer

@onready var title_label: Label = $MarginContainer/VBoxContainer/HeaderRow/TitleLabel
@onready var close_button: Button = $MarginContainer/VBoxContainer/HeaderRow/CloseButton

func _ready() -> void:
	close_button.pressed.connect(hide)

func show_building(building_name: String) -> void:
	title_label.text = building_name
	visible = true
