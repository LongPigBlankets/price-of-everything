extends Control
## The decision modal (docs/decision-events-spec.md §7). DS-themed, built in code
## on the buy_building_dialog shell (full-rect scrim + centred card on a high
## CanvasLayer, mounted by DecisionState).
##
## Deliberately INESCAPABLE (owner ruling, spec §13.1): scrim clicks are inert (a
## card nudge signals "you must choose"), it does not register with PanelStack so
## Esc never closes it, and there is no cancel path — the only way out is a choice.
## Read-only against the sim: the single mutation is DecisionState.resolve().

const CARD_WIDTH := 1180.0        # MAX width: choices sit side by side as columns…
const CARD_MARGIN := 60.0         # …but never wider than the viewport minus this margin
const CHOICE_MIN_WIDTH := 300.0   # each choice column; columns wrap when they don't fit
const PORTRAIT_SIZE := 132.0      # large advocate portrait atop each column

var _card: PanelContainer
var _scroll: ScrollContainer
var _content: VBoxContainer
var _cash_label: Label
var _nudge_tween: Tween = null

func _ready() -> void:
	theme = DS.theme
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_fit_to_viewport()
	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_fit_to_viewport):
		vp.size_changed.connect(_fit_to_viewport)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var scrim := ColorRect.new()
	scrim.color = Color(0.0, 0.0, 0.0, 0.55)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	scrim.gui_input.connect(_on_scrim_input)
	add_child(scrim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_card = PanelContainer.new()
	center.add_child(_card)

	# A scroll wrapper so a tall modal (choices wrapped into rows on a narrow window)
	# scrolls inside the card instead of running off-screen.
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_card.add_child(_scroll)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", DS.SP.MD)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_content)

	MatchState.money_changed.connect(_on_money_changed)
	DecisionState.pending_changed.connect(_on_pending_changed)
	_fit_to_viewport()
	visible = false

func open() -> void:
	# Safety valve: never show an inescapable modal with nothing to click. If the view
	# is somehow empty, abort the decision (no effects) rather than soft-lock the game.
	var view: Dictionary = DecisionState.pending_view()
	if view.is_empty() or (view.get("choices", []) as Array).is_empty():
		push_error("[Decisions] present aborted — empty view for %s" % str(DecisionState.pending))
		DecisionState.abort_pending()
		return
	_rebuild()
	visible = true
	move_to_front()

func _on_pending_changed() -> void:
	# Resolved (or reset/load) — the modal's job is done.
	if not DecisionState.has_pending():
		visible = false
	elif visible:
		_rebuild()

func _on_money_changed(_money: float) -> void:
	if visible and _cash_label != null and is_instance_valid(_cash_label):
		_cash_label.text = "Cash: £%.0f" % MatchState.money

func _fit_to_viewport() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var rect := vp.get_visible_rect().size
	size = rect
	position = Vector2.ZERO
	if _card != null:
		_card.custom_minimum_size.x = clampf(CARD_WIDTH, 320.0, rect.x - CARD_MARGIN)
	# Cap the card height to the viewport so a tall modal scrolls instead of spilling off.
	if _scroll != null and is_instance_valid(_content):
		_scroll.custom_minimum_size.y = minf(_content.get_combined_minimum_size().y, rect.y - CARD_MARGIN)

# Scrim clicks never dismiss — nudge the card so the "must choose" contract reads.
func _on_scrim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_nudge_card()

func _nudge_card() -> void:
	if _nudge_tween != null and _nudge_tween.is_running():
		return
	var base := _card.position
	_nudge_tween = create_tween()
	_nudge_tween.tween_property(_card, "position:x", base.x + 8.0, 0.05)
	_nudge_tween.tween_property(_card, "position:x", base.x - 8.0, 0.08)
	_nudge_tween.tween_property(_card, "position:x", base.x, 0.05)


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

func _rebuild() -> void:
	for child in _content.get_children():
		child.queue_free()
	var view: Dictionary = DecisionState.pending_view()
	if view.is_empty():
		return

	# Header: title left, live cash right (the player can't browse panels first).
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", DS.SP.MD)
	var title := Label.new()
	title.text = str(view.title)
	title.theme_type_variation = "Title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_cash_label = Label.new()
	_cash_label.theme_type_variation = "Numeric"
	_cash_label.text = "Cash: £%.0f" % MatchState.money
	header.add_child(_cash_label)
	_content.add_child(header)

	var body := Label.new()
	body.text = str(view.body)
	body.theme_type_variation = "Body"
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(body)

	# Target line + read-only camera peek behind the scrim.
	var target: Dictionary = view.get("target", {})
	if str(target.get("name", "")) != "":
		var target_row := HBoxContainer.new()
		target_row.add_theme_constant_override("separation", DS.SP.SM)
		var where := Label.new()
		where.theme_type_variation = "Caption"
		where.text = "Affects: %s" % str(target.name)
		where.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		target_row.add_child(where)
		if str(target.get("tile_id", "")) != "":
			var focus := Button.new()
			focus.text = "Focus"
			focus.focus_mode = Control.FOCUS_NONE
			focus.pressed.connect(_on_focus_pressed.bind(str(target.tile_id)))
			target_row.add_child(focus)
		_content.add_child(target_row)

	# Choices sit left-to-right as columns, wrapping to more rows on a narrow window
	# so they never run off-screen (a wide fixed card once soft-locked a small window).
	var choice_list: Array = view.get("choices", [])
	var vp := get_viewport()
	var avail := (vp.get_visible_rect().size.x if vp != null else CARD_WIDTH) - CARD_MARGIN
	var card_w := clampf(CARD_WIDTH, 320.0, avail)
	var cols := clampi(int(card_w / (CHOICE_MIN_WIDTH + DS.SP.MD)), 1, maxi(1, choice_list.size()))
	var grid := GridContainer.new()
	grid.columns = cols
	grid.add_theme_constant_override("h_separation", DS.SP.MD)
	grid.add_theme_constant_override("v_separation", DS.SP.MD)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for choice: Dictionary in choice_list:
		grid.add_child(_choice_card(choice))
	_content.add_child(grid)
	call_deferred("_fit_to_viewport")

func _on_focus_pressed(tile_id: String) -> void:
	var cam := get_viewport().get_camera_2d()
	if cam != null and cam.has_method("pan_to_tile"):
		cam.pan_to_tile(tile_id)

func _choice_card(choice: Dictionary) -> Control:
	var available := bool(choice.get("available", true))
	var card := _ChoiceCard.new()
	card.choice_id = str(choice.id)
	card.disabled = not available
	card.custom_minimum_size = Vector2(CHOICE_MIN_WIDTH, 0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if available:
		card.pressed.connect(_on_choice_pressed.bind(str(choice.id)))

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", DS.SP.SM)
	card.add_child(rows)

	# Advocate first — the big portrait heads the column (feature: prominent advisor).
	var advocate: Dictionary = choice.get("advocate", {})
	if not advocate.is_empty():
		rows.add_child(_advocate_strip(advocate))

	var label := Label.new()
	label.theme_type_variation = "Section"
	label.text = str(choice.get("label", ""))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(label)

	var consequence := Label.new()
	consequence.theme_type_variation = "Body"
	consequence.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	consequence.text = str(choice.get("consequence", ""))
	rows.add_child(consequence)

	# Unaffordable cash choice: still selectable — picking it takes a distress
	# loan for the shortfall (owner ruling, spec §12.1). Say so, in warning tones.
	var shortfall := float(choice.get("loan_shortfall", 0.0))
	if available and shortfall > 0.0:
		var loan_note := Label.new()
		loan_note.theme_type_variation = "Caption"
		loan_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if MatchState.money < 0.0:
			loan_note.text = "You're in the red — the full £%.0f cost is covered by a loan." % shortfall
		else:
			loan_note.text = "You're short £%.0f — picking this takes out a loan to cover it." % shortfall
		loan_note.add_theme_color_override("font_color", DS.PALETTE["WARN"])
		rows.add_child(loan_note)

	if not available:
		var lock := Label.new()
		lock.theme_type_variation = "Caption"
		lock.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lock.text = "🔒 %s" % str(choice.get("lock_reason", ""))
		lock.add_theme_color_override("font_color", DS.PALETTE["TEXT_MUTED"])
		rows.add_child(lock)
		card.modulate = Color(1, 1, 1, 0.55)
	return card

# The advocate block that heads a choice column: a large centred portrait, then
# seat/name, the stance quote, and the loyalty stakes — all centred.
func _advocate_strip(advocate: Dictionary) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", DS.SP.XS)

	var portrait_center := CenterContainer.new()
	portrait_center.add_child(_portrait(advocate))
	col.add_child(portrait_center)

	var who := Label.new()
	who.theme_type_variation = "Caption"
	who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	who.text = "%s — %s" % [str(advocate.name), str(advocate.seat_name)]
	col.add_child(who)

	var stance := Label.new()
	stance.theme_type_variation = "Body"
	stance.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stance.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stance.text = "“%s”" % str(advocate.stance)
	col.add_child(stance)

	var stakes := Label.new()
	stakes.theme_type_variation = "Numeric"
	stakes.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stakes.add_theme_font_size_override("font_size", 12)
	stakes.text = "Follow: %+.1f loyalty · Ignore: %+.1f" \
		% [float(advocate.follow_delta), float(advocate.ignore_delta)]
	stakes.add_theme_color_override("font_color", DS.PALETTE["TEXT_MUTED"])
	col.add_child(stakes)
	return col

# Advisor portrait with the accent-coloured frame; several cast members have no
# portrait art, so fall back to accent + initials (people_panel's convention).
func _portrait(advocate: Dictionary) -> Control:
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	frame.clip_contents = true
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var accent: Color = advocate.get("accent", Color("#53687A"))
	var box := StyleBoxFlat.new()
	box.bg_color = accent.darkened(0.45)
	box.border_color = accent
	box.set_border_width_all(2)
	box.set_corner_radius_all(8)
	frame.add_theme_stylebox_override("panel", box)

	var texture := _portrait_texture(str(advocate.get("portrait_path", "")))
	if texture != null:
		var image := TextureRect.new()
		image.texture = texture
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(image)
	else:
		var center := CenterContainer.new()
		frame.add_child(center)
		var initials := Label.new()
		initials.theme_type_variation = "Section"
		initials.text = str(advocate.get("initials", "?"))
		center.add_child(initials)
	return frame

func _portrait_texture(path: String) -> Texture2D:
	if path == "":
		return null
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	if image == null or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)

func _on_choice_pressed(choice_id: String) -> void:
	var err: String = DecisionState.resolve(choice_id)
	if err != "":
		MatchState.request_toast(err, "warning")
	# pending_changed hides the dialog on success.


# Clickable card with rich content — the pattern of record (a PanelContainer with
# a hand-wired pressed signal; Buttons don't size to child containers).
class _ChoiceCard extends PanelContainer:
	signal pressed
	var choice_id := ""
	var disabled := false
	var _hover := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		theme_type_variation = "Card"
		mouse_entered.connect(func() -> void: _set_hover(true))
		mouse_exited.connect(func() -> void: _set_hover(false))

	func _set_hover(on: bool) -> void:
		if disabled:
			return
		_hover = on
		self_modulate = Color(1.12, 1.12, 1.12) if on else Color(1, 1, 1)

	func _gui_input(event: InputEvent) -> void:
		if disabled:
			return
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			pressed.emit()
