extends PanelContainer
## The Turn Briefing's collapsed form (spec §4.5): a 200x50 strip centred under the top
## bar, showing one icon per outstanding item — coloured when critical (decisions,
## alerts, news), off-white when routine (research, sales, completions) — up to a cap,
## then a "+k", then a chevron. Clicking anywhere expands the panel. Hidden when empty.

const STRIP_TOP := 58.0
const MIN_W := 200.0
const MIN_H := 50.0
const CELL := 30.0
const MAX_ICONS := 6

var _row: HBoxContainer
var _pulse_tween: Tween = null

func _ready() -> void:
	theme = DS.theme
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size = Vector2(MIN_W, MIN_H)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#0C1D30")
	sb.border_color = Color(Color("#CDB98A"), 0.4)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 14
	sb.content_margin_right = 12
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	add_theme_stylebox_override("panel", sb)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 6)
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_row)
	gui_input.connect(_on_input)
	get_viewport().size_changed.connect(_reposition)

func refresh() -> void:
	for c in _row.get_children():
		c.queue_free()
	var items: Array = TurnBriefing.items()
	var shown: Array = items.slice(0, MAX_ICONS)
	for it in shown:
		_row.add_child(_icon(it))
	if items.size() > shown.size():
		var more := Label.new()
		more.theme_type_variation = "Caption"
		more.text = "+%d" % (items.size() - shown.size())
		more.add_theme_font_size_override("font_size", 12)
		_row.add_child(more)
	var chevron := Label.new()
	chevron.text = "▾"
	chevron.add_theme_color_override("font_color", DS.PALETTE["TEXT_MUTED"])
	_row.add_child(chevron)
	call_deferred("_reposition")

## One-shot red glow when a new critical item arrives while collapsed.
func pulse() -> void:
	if _pulse_tween != null and _pulse_tween.is_running():
		return
	_pulse_tween = create_tween()
	_pulse_tween.tween_property(self, "modulate", Color(1.5, 0.9, 0.85), 0.2)
	_pulse_tween.tween_property(self, "modulate", Color(1, 1, 1), 0.6)

# One reserved cell: a coloured chip (tinted bg + border) when the item is critical,
# a plain off-white glyph when it's routine.
func _icon(it: Dictionary) -> Control:
	var critical: bool = TurnBriefing.item_is_critical(it)
	var color: Color = TurnBriefing.item_display_color(it)
	var cell := PanelContainer.new()
	cell.custom_minimum_size = Vector2(CELL, CELL + 4.0)
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.tooltip_text = str(it.get("title", ""))
	if critical:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(color, 0.14)
		sb.border_color = color
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(7)
		cell.add_theme_stylebox_override("panel", sb)
	var glyph := Label.new()
	glyph.text = TurnBriefing.item_glyph(it)
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph.add_theme_font_size_override("font_size", 15)
	glyph.add_theme_color_override("font_color", color)
	cell.add_child(glyph)
	# Unanswered-decision dot, top-right.
	if str(it.get("kind", "")) == "decision":
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(7, 7)
		dot.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		dot.position = Vector2(CELL - 8.0, 2.0)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var dsb := StyleBoxFlat.new()
		dsb.bg_color = color
		dsb.set_corner_radius_all(4)
		dot.add_theme_stylebox_override("panel", dsb)
		cell.add_child(dot)
	return cell

func _reposition() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var w: float = maxf(MIN_W, get_combined_minimum_size().x)
	size = Vector2(w, MIN_H)
	position = Vector2((vp.get_visible_rect().size.x - w) / 2.0, STRIP_TOP)

func _on_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		TurnBriefing.expand()
