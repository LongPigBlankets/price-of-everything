extends Control
# A simple centred modal: a title, a body line and one or two buttons. Reused for
# the "no deposit found" and "deposit exhausted" prompts. The button callbacks are
# wired by the opener via the `action_chosen` signal; for now they just close.

signal action_chosen(id: String)

var _title_label: Label = null
var _body_label: Label = null
var _button_row: HBoxContainer = null

func _ready() -> void:
	# Root sized explicitly in open(); children fill the root via anchors.
	mouse_filter = Control.MOUSE_FILTER_STOP   # block clicks to the map behind it
	visible = false

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	_fill_parent(dim)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_fill_parent(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(460, 0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	margin.add_child(vb)

	_title_label = Label.new()
	_title_label.theme_type_variation = &"Section"
	vb.add_child(_title_label)

	_body_label = Label.new()
	_body_label.theme_type_variation = &"Body"
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.custom_minimum_size = Vector2(420, 0)
	vb.add_child(_body_label)

	vb.add_child(HSeparator.new())

	_button_row = HBoxContainer.new()
	_button_row.add_theme_constant_override("separation", 12)
	_button_row.alignment = BoxContainer.ALIGNMENT_END
	vb.add_child(_button_row)

## Show the dialog. buttons is an array of {id, label}.
func open(title: String, body: String, buttons: Array) -> void:
	_title_label.text = title
	_body_label.text = body
	for child in _button_row.get_children():
		child.queue_free()
	for b in buttons:
		var btn := Button.new()
		btn.text = str(b.get("label", ""))
		btn.custom_minimum_size = Vector2(120, 0)
		btn.pressed.connect(_on_button_pressed.bind(str(b.get("id", ""))))
		_button_row.add_child(btn)
	# Fill the screen regardless of parent layout, so the CenterContainer centres.
	position = Vector2.ZERO
	size = get_viewport().get_visible_rect().size
	visible = true
	move_to_front()

func _on_button_pressed(id: String) -> void:
	visible = false
	action_chosen.emit(id)

# Anchor a control to fill its parent (explicit, so it works regardless of when
# it's added to the tree).
func _fill_parent(c: Control) -> void:
	c.anchor_left = 0.0
	c.anchor_top = 0.0
	c.anchor_right = 1.0
	c.anchor_bottom = 1.0
	c.offset_left = 0.0
	c.offset_top = 0.0
	c.offset_right = 0.0
	c.offset_bottom = 0.0
