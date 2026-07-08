extends Control
## Shown when the auto-bridge loan fires (SolvencyState): the balance went negative and
## a loan was taken automatically to lift it back toward £0. Informational + dismissible:
## the message, the remaining loan capacity as a big number on its own row, and a
## Continue CTA. DS-themed (buy_building_dialog shell).

signal continued

const CARD_WIDTH := 520.0
const CARD_MARGIN := 60.0

var _card: PanelContainer
var _content: VBoxContainer

func _ready() -> void:
	theme = DS.theme
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

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
	center.add_child(_card)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", DS.SP["MD"])
	_card.add_child(_content)
	_fit()
	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_fit):
		vp.size_changed.connect(_fit)
	visible = false

func open(amount: float, capacity_left: float) -> void:
	for c in _content.get_children():
		c.queue_free()

	var title := Label.new()
	title.theme_type_variation = "Title"
	title.text = "Bridge loan taken"
	_content.add_child(title)

	var body := Label.new()
	body.theme_type_variation = "Body"
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.text = "Your balance went into the red, so we took a loan of £%s to bridge you until next turn." % _fmt(amount)
	_content.add_child(body)

	var cap_label := Label.new()
	cap_label.theme_type_variation = "Caption"
	cap_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap_label.text = "Loan capacity left"
	_content.add_child(cap_label)

	# The remaining capacity as a big number on its own row.
	var big := Label.new()
	big.theme_type_variation = "Numeric"
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big.add_theme_font_size_override("font_size", 40)
	big.add_theme_color_override("font_color",
		DS.PALETTE["WARN"] if capacity_left < 100.0 else DS.PALETTE["OK"])
	big.text = "£%s" % _fmt(capacity_left)
	_content.add_child(big)

	var cont := Button.new()
	cont.theme_type_variation = "Primary"
	cont.focus_mode = Control.FOCUS_NONE
	cont.text = "Continue"
	cont.custom_minimum_size = Vector2(0, 48)
	cont.pressed.connect(_on_continue)
	_content.add_child(cont)

	visible = true
	move_to_front()

func _on_continue() -> void:
	visible = false
	continued.emit()

func _fit() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	size = vp.get_visible_rect().size
	position = Vector2.ZERO
	if _card != null:
		_card.custom_minimum_size.x = clampf(CARD_WIDTH, 300.0, size.x - CARD_MARGIN)

func _fmt(v: float) -> String:
	if absf(v) >= 1000.0:
		return "%.1fk" % (v / 1000.0)
	return "%.0f" % v
