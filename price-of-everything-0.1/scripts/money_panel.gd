extends PanelContainer

@onready var title_label: Label = $MarginContainer/ModalLayout/HeaderRow/TitleLabel
@onready var close_button: Button = $MarginContainer/ModalLayout/HeaderRow/CloseButton

func _ready() -> void:
	close_button.pressed.connect(hide)
	title_label.text = "Money & Budget"
