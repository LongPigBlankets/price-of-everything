extends PanelContainer
## The Turn Briefing's collapsed form (spec §4.5): a 200x50 strip centred under the top
## bar, showing one icon per outstanding item — coloured when critical (decisions,
## alerts, news), off-white when routine (research, sales, completions) — up to a cap,
## then a "+k", then a chevron. Clicking anywhere expands the panel. Hidden when empty.

# Nested INTO the top bar (which spans y=0..58): the strip's squared bottom edge sits
# flush with the bar's bottom border so it reads as part of the bar, not a plate floating
# below it.
const STRIP_TOP := 8.0
# Fixed footprint: the strip never resizes on refresh — it just swaps the icons —
# so it can't flicker/expand for a frame while the turn resolves. Content is capped
# to always fit within FIXED_W.
const FIXED_W := 200.0
const MIN_H := 50.0
const CELL := 26.0
const MAX_ICONS := 4

var _row: HBoxContainer
var _pulse_tween: Tween = null

func _ready() -> void:
	theme = DS.theme
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size = Vector2(FIXED_W, MIN_H)
	clip_contents = true   # never let a stray overflow grow the fixed footprint
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#0C1D30")
	sb.border_color = Color(Color("#CDB98A"), 0.4)
	sb.set_border_width_all(1)
	# Rounded top, squared (cut-off) bottom — matches the notched-plate aesthetic used on
	# tabs/plates elsewhere, and makes the strip read as a tab hanging from the top bar.
	sb.corner_radius_top_left = 10
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_left = 0
	sb.corner_radius_bottom_right = 0
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
	call_deferred("_reposition")   # position once; fixed width means it never moves on refresh

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
	# No reposition here: the width is fixed, so refresh only swaps icons in place.

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
	# Constant footprint centred under the top bar — depends only on the viewport
	# width, never on the item count, so it holds steady while items swap.
	var vp := get_viewport()
	if vp == null:
		return
	size = Vector2(FIXED_W, MIN_H)
	position = Vector2((vp.get_visible_rect().size.x - FIXED_W) / 2.0, STRIP_TOP)

func _on_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		TurnBriefing.expand()
