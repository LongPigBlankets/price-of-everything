extends PanelContainer
## "Unlocked …" popup, shown when a research unlock is earned by meeting its
## condition (never for a free-chosen unlock). Shows the unlock name, its reward
## (the CSV description), and a Continue button.

var _title_label: Label
var _reward_label: Label

func _ready() -> void:
	theme = DS.theme
	visible = false
	anchor_left = 0.5
	anchor_top = 0.5
	anchor_right = 0.5
	anchor_bottom = 0.5
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	custom_minimum_size = Vector2(420.0, 0.0)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var margin := MarginContainer.new()
	for s in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + s, 18)
	add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	margin.add_child(vb)

	_title_label = Label.new()
	_title_label.theme_type_variation = "Title"
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_title_label)

	_reward_label = Label.new()
	_reward_label.theme_type_variation = "Section"
	_reward_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reward_label.add_theme_color_override("font_color", DS.PALETTE.OK)
	vb.add_child(_reward_label)

	var cont := Button.new()
	cont.theme_type_variation = "Primary"
	cont.text = "Continue"
	cont.size_flags_horizontal = Control.SIZE_SHRINK_END
	cont.pressed.connect(_close)
	vb.add_child(cont)

func show_unlock(title: String, description: String) -> void:
	_title_label.text = "Unlocked  %s" % title
	_reward_label.text = description if description != "" else "New technology available."
	visible = true
	PanelStack.push(self)

func _close() -> void:
	visible = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not visible:
		PanelStack.remove(self)
