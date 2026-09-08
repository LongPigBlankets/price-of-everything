extends CanvasLayer
## Explicit exit feedback, separate from passive telemetry consent.
signal submitted(rating: String, comment: String)
signal skipped

const RATINGS: Array[String] = ["Great", "Good", "Average", "Bad", "Terrible"]
var _was_paused: bool = false
var rating: String = ""
var comment: TextEdit
var submit_button: Button
var error_label: Label

func _ready() -> void:
	_was_paused = get_tree().paused
	get_tree().paused = true
	layer = 250
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = DS.theme
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var card := PanelContainer.new()
	card.theme_type_variation = &"Outlined"
	card.custom_minimum_size.x = 720
	center.add_child(card)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	card.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	margin.add_child(column)
	var title := Label.new()
	title.text = "Thanks for playing. Tell me if you enjoyed it."
	title.theme_type_variation = &"BuildingName"
	title.add_theme_color_override("font_color", DS.PALETTE.TEXT)
	column.add_child(title)
	var scale := HBoxContainer.new()
	scale.add_theme_constant_override("separation", 8)
	column.add_child(scale)
	var group := ButtonGroup.new()
	for value: String in RATINGS:
		var button := Button.new()
		button.text = value
		button.toggle_mode = true
		button.button_group = group
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 44
		button.toggled.connect(func(selected: bool) -> void:
			button.theme_type_variation = &"Brass" if selected else &"")
		button.pressed.connect(func() -> void:
			rating = value
			submit_button.disabled = false)
		scale.add_child(button)
	comment = TextEdit.new()
	comment.placeholder_text = "Anything else you'd like to share? (optional)"
	comment.add_theme_color_override("font_color", DS.PALETTE.TEXT)
	comment.add_theme_color_override("font_placeholder_color", DS.PALETTE.TEXT)
	comment.add_theme_font_size_override("font_size", 18)
	comment.custom_minimum_size.y = 3 * 26 + 16
	comment.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	column.add_child(comment)
	error_label = Label.new()
	error_label.text = "Couldn't save your response. Please try again."
	error_label.add_theme_color_override("font_color", DS.PALETTE.DANGER)
	error_label.hide()
	column.add_child(error_label)
	submit_button = Button.new()
	submit_button.text = "Submit & close game"
	submit_button.theme_type_variation = &"Silver"
	submit_button.custom_minimum_size.y = 48
	submit_button.disabled = true
	submit_button.pressed.connect(func() -> void:
		if rating in RATINGS:
			submit_button.disabled = true
			submitted.emit(rating, comment.text.strip_edges().left(4000)))
	column.add_child(submit_button)
	var skip := Button.new()
	skip.text = "Close without submitting"
	skip.flat = true
	skip.pressed.connect(func() -> void: skipped.emit())
	column.add_child(skip)

func show_save_error() -> void:
	error_label.show()
	submit_button.disabled = false

func _exit_tree() -> void:
	get_tree().paused = _was_paused
