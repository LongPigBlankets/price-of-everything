extends PanelContainer
## The Turn Briefing's collapsed form (spec §4.5): a ~300x50 strip centred under the
## top bar. One icon per outstanding decision (dot = unanswered), a red badge counting
## critical alerts, an amber badge for warnings, an "n updates" hint, and a chevron.
## Clicking anywhere expands the panel. Hidden entirely when the briefing is empty.

const STRIP_TOP := 58.0
const CHIP := 26.0

var _row: HBoxContainer
var _pulse_tween: Tween = null

func _ready() -> void:
	theme = DS.theme
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#0C1D30")
	sb.border_color = Color(Color("#CDB98A"), 0.4)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 14
	sb.content_margin_right = 12
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	add_theme_stylebox_override("panel", sb)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 8)
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_row)
	gui_input.connect(_on_input)
	get_viewport().size_changed.connect(_reposition)

func refresh() -> void:
	for c in _row.get_children():
		c.queue_free()
	var decisions: Array = TurnBriefing.unresolved_decisions()
	var crits: Array = TurnBriefing.critical_alerts().filter(
		func(it) -> bool: return str(it.kind) != "decision")
	var warns := 0
	var infos := 0
	for it in TurnBriefing.items():
		if str(it.section) == "alerts" or str(it.section) == "news":
			if str(it.severity) == "warning":
				warns += 1
		elif str(it.section) == "info":
			infos += 1
	# Decision chips (up to 4, then +k) — the persistent "turn is blocked" reminder.
	for d in decisions.slice(0, 4):
		_row.add_child(_decision_chip(TurnBriefing.category_color(str(d.get("category", "")))))
	if decisions.size() > 4:
		_row.add_child(_caption("+%d" % (decisions.size() - 4)))
	if not decisions.is_empty() and (not crits.is_empty() or warns > 0 or infos > 0):
		_row.add_child(_divider())
	if not crits.is_empty():
		_row.add_child(_badge(crits.size(), DS.PALETTE["DANGER"]))
	if warns > 0:
		_row.add_child(_badge(warns, DS.PALETTE["WARN"]))
	if infos > 0:
		_row.add_child(_caption("%d update%s" % [infos, "" if infos == 1 else "s"]))
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

func _decision_chip(tint: Color) -> Control:
	var chip := PanelContainer.new()
	chip.custom_minimum_size = Vector2(CHIP, CHIP)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(tint, 0.12)
	sb.border_color = tint
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(7)
	chip.add_theme_stylebox_override("panel", sb)
	var glyph := Label.new()
	glyph.text = "⚖"
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph.add_theme_font_size_override("font_size", 13)
	glyph.add_theme_color_override("font_color", tint)
	chip.add_child(glyph)
	return chip

func _badge(n: int, tint: Color) -> Control:
	var badge := PanelContainer.new()
	badge.custom_minimum_size = Vector2(20, 20)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(tint, 0.14)
	sb.border_color = tint
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	badge.add_theme_stylebox_override("panel", sb)
	var count := Label.new()
	count.theme_type_variation = "Numeric"
	count.text = str(n)
	count.add_theme_font_size_override("font_size", 11)
	count.add_theme_color_override("font_color", tint)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.add_child(count)
	return badge

func _caption(text: String) -> Control:
	var c := Label.new()
	c.theme_type_variation = "Caption"
	c.text = text
	c.add_theme_font_size_override("font_size", 11)
	return c

func _divider() -> Control:
	var d := ColorRect.new()
	d.color = Color("#22384F")
	d.custom_minimum_size = Vector2(1, 20)
	return d

func _reposition() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var w := get_combined_minimum_size().x
	size = get_combined_minimum_size()
	position = Vector2((vp.get_visible_rect().size.x - w) / 2.0, STRIP_TOP)

func _on_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		TurnBriefing.expand()
