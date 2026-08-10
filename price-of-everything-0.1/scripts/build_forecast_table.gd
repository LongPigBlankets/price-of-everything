extends PanelContainer
## The build forecast as four columns, one per phase of the building's first turns.
##
## This replaced a line chart. The chart was honest but unreadable: the pre-revenue hole is
## several times deeper than the steady margin is tall, so any shared axis flattened the
## number the player actually wants (the £/turn they end up with) into a hairline against a
## huge red slab. Four columns give every phase its own space and exact figures, and they
## carry what a line never did — how MANY turns each phase lasts.
##
## See docs/early-game-onboarding-spec.md §5.1.

const NAVY_FIELD := Color("#0a1725")
const NAVY_LINE := Color("#22384f")
const TEXT := Color("#e6edf5")
const MUTED := Color("#8da0b6")
const GREEN := Color("#5fbf6b")
const GREY := Color("#7f8fa3")


func set_forecast(data: Dictionary) -> void:
	for child in get_children():
		child.queue_free()
	var phases: Array = data.get("phases", [])
	if phases.is_empty():
		return

	add_theme_stylebox_override("panel", _plate())
	var grid := GridContainer.new()
	grid.columns = phases.size()
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 2)
	add_child(grid)

	# Row 1 — what is happening.
	for phase in phases:
		grid.add_child(_cell(str(phase.get("label", "")), 10, MUTED, true))
	# Row 2 — the money, which is the whole point.
	for phase in phases:
		var per_turn := float(phase.get("per_turn", 0.0))
		var colour: Color = GREY
		if str(phase.get("kind", "")) != "building":
			colour = GREEN if per_turn >= 0.0 else DS.PALETTE["DANGER"]
		grid.add_child(_cell(_money_per_turn(per_turn), 15, colour, true))
	# Row 3 — when, and for how long.
	for phase in phases:
		var turns := int(phase.get("turns", 0))
		var suffix := ""
		if turns > 1:
			suffix = "  ·  %d turns" % turns
		grid.add_child(_cell("%s%s" % [str(phase.get("range", "")), suffix], 9, MUTED, true))


func _cell(text: String, font_size: int, colour: Color, centred: bool) -> Control:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if centred else HORIZONTAL_ALIGNMENT_LEFT
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _money_per_turn(value: float) -> String:
	if is_zero_approx(value):
		return "£0"
	var sign_char := "+" if value > 0.0 else "−"
	return "%s£%s" % [sign_char, _thousands(absf(value))]


func _thousands(v: float) -> String:
	var whole := int(round(v))
	var s := str(whole)
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return out


func _plate() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = NAVY_FIELD
	style.border_color = NAVY_LINE
	style.set_border_width_all(1)
	style.set_corner_radius_all(9)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style
