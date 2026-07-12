extends Control
## "Are you sure you want to proceed without the Tutorial?" — the confirmation shown
## when a player who has never finished the tutorial clicks New Game. A dimmed modal
## (decision_dialog pattern): scrim + centred DS card, a primary "Go to Tutorial" CTA
## and a plain underlined "New Game without Tutorial" text link.
##
## Pure UI: emits `go_to_tutorial` / `proceed_anyway`; the main menu owns what each does.
## Referenced from main_menu via a preload const (no class_name) for headless.

signal go_to_tutorial
signal proceed_anyway

const OFF_WHITE := Color(0.995234, 0.930806, 0.763265)

var _card: PanelContainer = null


func _ready() -> void:
	theme = DS.theme
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	_build()


func _input(event: InputEvent) -> void:
	# Esc dismisses the prompt without choosing (stay on the menu).
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func open() -> void:
	visible = true
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.16)


func close() -> void:
	visible = false


func _build() -> void:
	# Dim scrim that swallows clicks behind the card.
	var scrim := ColorRect.new()
	scrim.color = Color(0.0, 0.0, 0.0, 0.55)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(scrim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_card = PanelContainer.new()
	_card.custom_minimum_size = Vector2(560, 0)
	center.add_child(_card)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	_card.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(col)

	var title := Label.new()
	title.text = "Are you sure you want to proceed without the Tutorial?"
	title.theme_type_variation = &"Title"
	title.add_theme_font_size_override("font_size", 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(title)

	var blurb := Label.new()
	blurb.text = "The tutorial takes about ten minutes and teaches the basics — buying a building, powering it, and integrating your first supply chain. It's the fastest way to get your bearings."
	blurb.theme_type_variation = &"Body"
	blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.custom_minimum_size = Vector2(520, 0)
	col.add_child(blurb)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 4)
	col.add_child(spacer)

	# Primary CTA: Go to Tutorial.
	var go := Button.new()
	go.text = "Go to Tutorial"
	go.theme_type_variation = &"Primary"
	go.custom_minimum_size = Vector2(0, 58)
	go.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	go.add_theme_font_size_override("font_size", 24)
	go.pressed.connect(func() -> void:
		close()
		go_to_tutorial.emit())
	col.add_child(go)

	# Secondary: a plain underlined text link, not a styled button.
	var skip := LinkButton.new()
	skip.text = "New Game without Tutorial"
	skip.underline = LinkButton.UNDERLINE_MODE_ALWAYS
	skip.focus_mode = Control.FOCUS_NONE
	skip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	skip.add_theme_color_override("font_color", Color(OFF_WHITE, 0.72))
	skip.add_theme_color_override("font_hover_color", OFF_WHITE)
	skip.pressed.connect(func() -> void:
		close()
		proceed_anyway.emit())
	col.add_child(skip)
