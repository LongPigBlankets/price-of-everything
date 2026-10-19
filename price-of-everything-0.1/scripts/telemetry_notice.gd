extends Control
## First-menu explanation. Agreement acceptance remains the first screen.

const CreamKey := preload("res://scripts/ds2/cream_key.gd")
const MESSAGE := "This game tracks key game metrics like power generated, buildings built, goods produced and profit and sends it to the developer for balancing. You can always disable this in Settings."
var understood_button: Button


static func should_show() -> bool:
	return not PlayerProfile.telemetry_notice_seen


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 300
	var scrim := ColorRect.new()
	scrim.color = Color(0, 0, 0, 0.7)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scrim)
	var outer := MarginContainer.new()
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		outer.add_theme_constant_override("margin_" + side, 24)
	add_child(outer)
	var center := CenterContainer.new()
	outer.add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(600, 0)
	var backing := StyleBoxTexture.new()
	backing.texture = preload("res://assets/ui/bdp_v3/panel_backing.png")
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		backing.set_texture_margin(side, 40)
		backing.set_content_margin(side, 28)
	card.add_theme_stylebox_override("panel", backing)
	center.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 22)
	card.add_child(col)
	var title := Label.new()
	title.text = "Telemetry"
	title.theme_type_variation = &"Title"
	title.add_theme_color_override("font_color", DS.PALETTE.TEXT)
	col.add_child(title)
	for copy in [MESSAGE, "A basic launch event is still sent when gameplay telemetry is disabled."]:
		var text := Label.new()
		text.text = copy
		text.theme_type_variation = &"Body"
		text.add_theme_color_override("font_color", DS.PALETTE.TEXT)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.custom_minimum_size.x = 540
		col.add_child(text)
	understood_button = CreamKey.make("Understood", "Understood", "", 210.0, false, false)
	understood_button.focus_mode = Control.FOCUS_ALL
	understood_button.pressed.connect(_acknowledge)
	col.add_child(understood_button)
	understood_button.grab_focus()
	PanelStack.push(self)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()


func _acknowledge() -> void:
	PlayerProfile.acknowledge_telemetry_notice()
	PanelStack.remove(self)
	queue_free()


func _exit_tree() -> void:
	PanelStack.remove(self)
