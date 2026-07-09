extends Control
## The Turn Briefing's expanded form (spec §2): a mid-screen panel — header (This Turn ·
## TURN n · cash · collapse), a left mini-menu sectioned DECISIONS / ALERTS / NEWS /
## INFO, a detail area for the selected item, and a footer status line. No scrim: the
## map stays visible and reachable; decisions gate End Turn, not input (owner ruling).
## Read-only against the sim — mutations go through DecisionState / TurnBriefing.

const MENU_WIDTH := 224.0
const CARD_MAX_W := 900.0
const CARD_MAX_H := 640.0
const MARGIN := 64.0
const CHOICE_MIN_W := 190.0
const CHOICE_MIN_H := 300.0   # taller decision cards

var _card: PanelContainer
var _menu_list: VBoxContainer
var _detail_scroll: ScrollContainer
var _detail: VBoxContainer
var _footer_label: Label
var _cash_label: Label
var _turn_chip: Label
var _sel := ""
var _flash_tween: Tween = null

func _ready() -> void:
	theme = DS.theme
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_card = PanelContainer.new()
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#0B1B2C")
	sb.border_color = Color(Color("#CDB98A"), 0.55)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(14)
	sb.shadow_size = 24
	sb.shadow_color = Color(0, 0, 0, 0.45)
	_card.add_theme_stylebox_override("panel", sb)
	center.add_child(_card)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	_card.add_child(col)

	# ── header ──
	var header := HBoxContainer.new()
	header.custom_minimum_size = Vector2(0, 52)
	header.add_theme_constant_override("separation", DS.SP["MD"])
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 16)
	pad.add_theme_constant_override("margin_right", 12)
	pad.add_child(header)
	col.add_child(pad)

	var title := Label.new()
	title.theme_type_variation = "Title"
	title.text = "This Turn"
	header.add_child(title)
	_turn_chip = Label.new()
	_turn_chip.theme_type_variation = "Caption"
	_turn_chip.add_theme_color_override("font_color", Color("#CDB98A"))
	header.add_child(_turn_chip)
	var spring := Control.new()
	spring.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spring)
	_cash_label = Label.new()
	_cash_label.theme_type_variation = "Numeric"
	_cash_label.add_theme_color_override("font_color", DS.PALETTE["WARN"])
	header.add_child(_cash_label)
	var collapse_btn := Button.new()
	collapse_btn.text = "▴"
	collapse_btn.tooltip_text = "Collapse to the strip"
	collapse_btn.focus_mode = Control.FOCUS_NONE
	collapse_btn.custom_minimum_size = Vector2(30, 30)
	collapse_btn.pressed.connect(func() -> void: TurnBriefing.collapse())
	header.add_child(collapse_btn)
	col.add_child(HSeparator.new())

	# ── body: mini-menu | detail ──
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	col.add_child(body)

	var menu_scroll := ScrollContainer.new()
	menu_scroll.custom_minimum_size = Vector2(MENU_WIDTH, 0)
	menu_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(menu_scroll)
	_menu_list = VBoxContainer.new()
	_menu_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_menu_list.add_theme_constant_override("separation", 2)
	menu_scroll.add_child(_menu_list)
	body.add_child(VSeparator.new())

	_detail_scroll = ScrollContainer.new()
	_detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(_detail_scroll)
	_detail = VBoxContainer.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.add_theme_constant_override("separation", DS.SP["SM"])
	var detail_pad := MarginContainer.new()
	detail_pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_pad.add_theme_constant_override("margin_left", 16)
	detail_pad.add_theme_constant_override("margin_right", 16)
	detail_pad.add_theme_constant_override("margin_top", 14)
	detail_pad.add_theme_constant_override("margin_bottom", 14)
	detail_pad.add_child(_detail)
	_detail_scroll.add_child(detail_pad)

	col.add_child(HSeparator.new())

	# ── footer ──
	var footer := HBoxContainer.new()
	footer.custom_minimum_size = Vector2(0, 42)
	footer.add_theme_constant_override("separation", DS.SP["MD"])
	var fpad := MarginContainer.new()
	fpad.add_theme_constant_override("margin_left", 16)
	fpad.add_theme_constant_override("margin_right", 12)
	fpad.add_child(footer)
	col.add_child(fpad)
	_footer_label = Label.new()
	_footer_label.theme_type_variation = "Caption"
	_footer_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_footer_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	footer.add_child(_footer_label)
	var collapse2 := Button.new()
	collapse2.text = "Collapse ▴"
	collapse2.focus_mode = Control.FOCUS_NONE
	collapse2.pressed.connect(func() -> void: TurnBriefing.collapse())
	footer.add_child(collapse2)

	TurnBriefing.items_changed.connect(_on_items_changed)
	MatchState.money_changed.connect(func(m: float) -> void:
		if visible and is_instance_valid(_cash_label):
			_cash_label.text = "£%.0f" % m)
	get_viewport().size_changed.connect(_fit)
	# Hide FIRST, connect after: the initial hide must not read as "the player closed
	# it" (that once collapsed the briefing the moment the panel was instantiated).
	visible = false
	visibility_changed.connect(_on_visibility_changed)

func open(select_id: String = "") -> void:
	# On open, always land on the first outstanding decision unless the caller asked
	# for a specific item (e.g. the bankruptcy strip). Clearing _sel makes
	# _ensure_selection re-pick, and it prefers decisions first.
	_sel = select_id
	_ensure_selection()
	_fit()
	_rebuild()
	visible = true
	move_to_front()
	PanelStack.push(self)

## One-shot amber flash — "you tried to end the turn with decisions outstanding".
func flash() -> void:
	if _flash_tween != null and _flash_tween.is_running():
		return
	_flash_tween = create_tween()
	_flash_tween.tween_property(_card, "self_modulate", Color(1.35, 1.2, 0.85), 0.15)
	_flash_tween.tween_property(_card, "self_modulate", Color(1, 1, 1), 0.5)

func _on_visibility_changed() -> void:
	if not visible:
		PanelStack.remove(self)
		if TurnBriefing.expanded:   # hidden externally (e.g. Esc via PanelStack)
			TurnBriefing.collapse()

func _fit() -> void:
	var vp := get_viewport()
	if vp == null or _card == null:
		return
	var rect := vp.get_visible_rect().size
	# Directly under a CanvasLayer FULL_RECT resolves to nothing — size to the
	# viewport by hand (same rule as the confirm dialogs).
	size = rect
	position = Vector2.ZERO
	_card.custom_minimum_size = Vector2(
		clampf(CARD_MAX_W, 320.0, rect.x - MARGIN),
		clampf(CARD_MAX_H, 260.0, rect.y - 150.0))

func _on_items_changed() -> void:
	if visible:
		_ensure_selection()
		_rebuild()

func _ensure_selection() -> void:
	var items: Array = TurnBriefing.items()
	if items.any(func(it) -> bool: return str(it.id) == _sel):
		return
	var pick := items.filter(func(it) -> bool: return str(it.kind) == "decision")
	if pick.is_empty():
		pick = items.filter(func(it) -> bool:
			return str(it.section) == "alerts" and str(it.severity) == "critical")
	if pick.is_empty():
		pick = items
	_sel = str(pick[0].id) if not pick.is_empty() else ""

func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.pressed:
		return
	if event.keycode != KEY_UP and event.keycode != KEY_DOWN:
		return
	var items: Array = TurnBriefing.items()
	var idx := -1
	for i in items.size():
		if str(items[i].id) == _sel:
			idx = i
	var next: int = clampi(idx + (1 if event.keycode == KEY_DOWN else -1), 0, items.size() - 1)
	if next != idx and next < items.size():
		_sel = str(items[next].id)
		_rebuild()
		accept_event()


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

const _SECTIONS := [["decisions", "Decisions"], ["alerts", "Alerts"], ["news", "News"], ["info", "Info"]]

func _rebuild() -> void:
	_turn_chip.text = "TURN %d" % TurnManager.current_turn
	_cash_label.text = "£%.0f" % MatchState.money
	var items: Array = TurnBriefing.items()

	for c in _menu_list.get_children():
		c.queue_free()
	for section in _SECTIONS:
		var rows: Array = items.filter(func(it) -> bool: return str(it.section) == str(section[0]))
		if rows.is_empty():
			continue
		var head := Label.new()
		head.theme_type_variation = "Caption"
		head.text = "%s (%d)" % [str(section[1]).to_upper(), rows.size()]
		head.add_theme_font_size_override("font_size", 10)
		_menu_list.add_child(head)
		for it in rows:
			_menu_list.add_child(_menu_row(it))

	for c in _detail.get_children():
		c.queue_free()
	var selected := {}
	for it in items:
		if str(it.id) == _sel:
			selected = it
	if selected.is_empty():
		var none := Label.new()
		none.theme_type_variation = "Caption"
		none.text = "Nothing selected."
		_detail.add_child(none)
	elif str(selected.kind) == "decision":
		_build_decision_detail(selected)
	else:
		_build_generic_detail(selected)

	var n := TurnBriefing.unresolved_decisions().size()
	_footer_label.text = ("%d decision%s must be answered before you can end the turn." \
		% [n, "" if n == 1 else "s"]) if n > 0 else "All caught up — you can end the turn."
	_footer_label.add_theme_color_override("font_color",
		DS.PALETTE["WARN"] if n > 0 else DS.PALETTE["OK"])

func _item_color(it: Dictionary) -> Color:
	if str(it.kind) == "decision":
		return TurnBriefing.category_color(str(it.get("category", "")))
	return TurnBriefing.severity_color(str(it.get("severity", "info")))

func _menu_row(it: Dictionary) -> Control:
	var row := PanelContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var on := str(it.id) == _sel
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#15304A") if on else Color(0, 0, 0, 0)
	sb.border_color = Color("#2F5578") if on else Color(0, 0, 0, 0)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 8
	sb.content_margin_right = 6
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	row.add_theme_stylebox_override("panel", sb)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 7)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(hb)

	var tint := _item_color(it)
	var chip := Label.new()
	chip.text = TurnBriefing.item_glyph(it)
	chip.custom_minimum_size = Vector2(20, 0)
	chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip.add_theme_color_override("font_color", tint)
	hb.add_child(chip)

	var title := Label.new()
	title.theme_type_variation = "Caption"
	title.text = str(it.title)
	title.clip_text = true
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_color_override("font_color", Color("#F3F8FD") if on else DS.PALETTE["TEXT_MUTED"])
	hb.add_child(title)

	var glyph := Label.new()
	glyph.add_theme_font_size_override("font_size", 11)
	if str(it.kind) == "decision":
		glyph.text = "●"
		glyph.add_theme_color_override("font_color", tint)
	elif str(it.section) == "alerts":
		glyph.text = "⚠"
		glyph.add_theme_color_override("font_color", tint)
	else:
		glyph.text = "✓" if bool(it.get("acked", false)) else "◔"
		glyph.add_theme_color_override("font_color",
			DS.PALETTE["OK"] if bool(it.get("acked", false)) else DS.PALETTE["TEXT_MUTED"])
	hb.add_child(glyph)

	# ✕ dismiss on everything except decisions (owner ruling).
	if bool(it.get("dismissible", false)):
		var x := Button.new()
		x.text = "✕"
		x.flat = true
		x.focus_mode = Control.FOCUS_NONE
		x.custom_minimum_size = Vector2(18, 18)
		x.add_theme_font_size_override("font_size", 10)
		x.tooltip_text = "Dismiss"
		x.mouse_filter = Control.MOUSE_FILTER_STOP
		x.pressed.connect(func() -> void: TurnBriefing.dismiss(str(it.id)))
		hb.add_child(x)

	var id := str(it.id)
	row.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			row.accept_event()
			_sel = id
			_rebuild())
	return row

func _detail_head(it: Dictionary, tag_text: String, tag_color: Color) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", DS.SP["SM"])
	var tint := _item_color(it)
	var chip := Label.new()
	chip.text = TurnBriefing.item_glyph(it)
	chip.add_theme_font_size_override("font_size", 18)
	chip.add_theme_color_override("font_color", tint)
	hb.add_child(chip)
	var title := Label.new()
	title.theme_type_variation = "Section"
	title.text = str(it.title)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(title)
	if tag_text != "":
		var tag := Label.new()
		tag.theme_type_variation = "Caption"
		tag.text = tag_text
		tag.add_theme_color_override("font_color", tag_color)
		hb.add_child(tag)
	return hb


# ── decision detail: prompt + choice columns ──────────────────────────────

func _build_decision_detail(it: Dictionary) -> void:
	var view: Dictionary = it.view
	var tint := _item_color(it)
	_detail.add_child(_detail_head(it, "must be answered", tint))
	var prompt := Label.new()
	prompt.theme_type_variation = "Body"
	prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt.text = str(view.body)
	_detail.add_child(prompt)
	if str((view.get("target", {}) as Dictionary).get("name", "")) != "":
		var affects := Label.new()
		affects.theme_type_variation = "Caption"
		affects.text = "Affects: %s" % str(view.target.name)
		_detail.add_child(affects)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", DS.SP["SM"])
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for choice: Dictionary in view.get("choices", []):
		row.add_child(_choice_card(view, choice))
	_detail.add_child(row)

func _choice_card(view: Dictionary, choice: Dictionary) -> Control:
	var available := bool(choice.get("available", true))
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(CHOICE_MIN_W, CHOICE_MIN_H)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#0A1623")
	sb.border_color = Color("#1C3149")
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 11
	sb.content_margin_right = 11
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	card.add_theme_stylebox_override("panel", sb)
	if not available:
		card.modulate = Color(1, 1, 1, 0.55)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	card.add_child(vb)

	# Advocate block (portrait + name + seat), when a tenured advisor speaks.
	var advocate: Dictionary = choice.get("advocate", {})
	if not advocate.is_empty():
		var arow := HBoxContainer.new()
		arow.add_theme_constant_override("separation", 8)
		arow.add_child(_portrait(advocate, 36))
		var acol := VBoxContainer.new()
		acol.add_theme_constant_override("separation", 0)
		var aname := Label.new()
		aname.theme_type_variation = "Caption"
		aname.text = str(advocate.name)
		aname.add_theme_color_override("font_color", Color("#DBE6F2"))
		acol.add_child(aname)
		var aseat := Label.new()
		aseat.theme_type_variation = "Caption"
		aseat.add_theme_font_size_override("font_size", 10)
		aseat.text = str(advocate.seat_name)
		aseat.add_theme_color_override("font_color", advocate.get("accent", Color("#8298AC")))
		acol.add_child(aseat)
		arow.add_child(acol)
		vb.add_child(arow)
		var stance := Label.new()
		stance.theme_type_variation = "Caption"
		stance.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		stance.text = "“%s”" % str(advocate.stance)
		vb.add_child(stance)

	var label := Label.new()
	label.theme_type_variation = "BuildingName"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = str(choice.get("label", ""))
	vb.add_child(label)

	# Consequence lines with tone dots (split from the honest one-liner).
	for line: String in _consequence_lines(str(choice.get("consequence", ""))):
		var lrow := HBoxContainer.new()
		lrow.add_theme_constant_override("separation", 6)
		var dot := Label.new()
		dot.text = "•"
		dot.add_theme_color_override("font_color", _line_tone(line))
		lrow.add_child(dot)
		var text := Label.new()
		text.theme_type_variation = "Caption"
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.text = line
		lrow.add_child(text)
		vb.add_child(lrow)

	# Loyalty chips: follow this advocate, snub every other advocate (spec §6.2).
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 4)
	if not advocate.is_empty():
		chips.add_child(_loyalty_chip(str(advocate.name), float(advocate.follow_delta), true))
	for other: Dictionary in view.get("choices", []):
		if str(other.id) == str(choice.id):
			continue
		var oadv: Dictionary = other.get("advocate", {})
		if not oadv.is_empty():
			chips.add_child(_loyalty_chip(str(oadv.name), -0.5, false))
	if chips.get_child_count() > 0:
		vb.add_child(chips)

	var shortfall := float(choice.get("loan_shortfall", 0.0))
	if available and shortfall > 0.0:
		var note := Label.new()
		note.theme_type_variation = "Caption"
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.add_theme_color_override("font_color", DS.PALETTE["WARN"])
		note.text = ("You're in the red — the full £%.0f cost is covered by a loan." % shortfall) \
			if MatchState.money < 0.0 else ("You're short £%.0f — a loan covers it." % shortfall)
		vb.add_child(note)
	if not available:
		var lock := Label.new()
		lock.theme_type_variation = "Caption"
		lock.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lock.add_theme_color_override("font_color", DS.PALETTE["TEXT_MUTED"])
		lock.text = "🔒 %s" % str(choice.get("lock_reason", ""))
		vb.add_child(lock)

	# An expanding spacer eats the leftover height so the CTA anchors to the card
	# bottom, regardless of how many text rows precede it (uniform across choices).
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.custom_minimum_size = Vector2(0, DS.SP["SM"])
	vb.add_child(spacer)

	var choose := Button.new()
	choose.theme_type_variation = "Primary"
	choose.focus_mode = Control.FOCUS_NONE
	choose.text = "Choose"
	choose.disabled = not available
	choose.custom_minimum_size = Vector2(0, 32)
	var uid := str(view.uid)
	var cid := str(choice.id)
	choose.pressed.connect(func() -> void:
		var err: String = DecisionState.resolve(cid, uid)
		if err != "":
			MatchState.request_toast(err, "warning"))
	vb.add_child(choose)
	return card

func _consequence_lines(consequence: String) -> Array:
	var out: Array = []
	for part in consequence.split(". "):
		var p := str(part).strip_edges().trim_suffix(".")
		if p != "":
			out.append(p)
	return out

func _line_tone(line: String) -> Color:
	if line.begins_with("−") or line.begins_with("-") or line.contains("−£") or line.contains("delayed"):
		return DS.PALETTE["DANGER"]
	if line.begins_with("+"):
		return DS.PALETTE["OK"]
	return DS.PALETTE["TEXT_MUTED"]

func _loyalty_chip(advisor_name: String, delta: float, up: bool) -> Control:
	var chip := Label.new()
	chip.theme_type_variation = "Caption"
	chip.add_theme_font_size_override("font_size", 10)
	var last := advisor_name.split(" ")
	chip.text = "%s %s%.1f %s" % ["▲" if up else "▼", "+" if delta > 0.0 else "", delta, last[last.size() - 1]]
	chip.add_theme_color_override("font_color", DS.PALETTE["OK"] if up else DS.PALETTE["DANGER"])
	return chip

func _portrait(advocate: Dictionary, px: int) -> Control:
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(px, px)
	frame.clip_contents = true
	var accent: Color = advocate.get("accent", Color("#53687A"))
	var sb := StyleBoxFlat.new()
	sb.bg_color = accent.darkened(0.45)
	sb.border_color = accent
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(int(px / 2.0))
	frame.add_theme_stylebox_override("panel", sb)
	var path := str(advocate.get("portrait_path", ""))
	var tex: Texture2D = null
	if path != "":
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		if img != null and not img.is_empty():
			tex = ImageTexture.create_from_image(img)
	if tex != null:
		var rect := TextureRect.new()
		rect.texture = tex
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		frame.add_child(rect)
	else:
		var initials := Label.new()
		initials.text = str(advocate.get("initials", "?"))
		initials.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		initials.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		frame.add_child(initials)
	return frame


# ── alert / news / info detail ─────────────────────────────────────────────

func _build_generic_detail(it: Dictionary) -> void:
	var tag := ""
	if str(it.section) == "alerts":
		tag = "critical" if str(it.severity) == "critical" else "warning"
	_detail.add_child(_detail_head(it, tag, _item_color(it)))

	var body := Label.new()
	body.theme_type_variation = "Body"
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.text = str(it.get("body", ""))
	_detail.add_child(body)

	# Stat rows (2-column grid of label/value cards).
	var rows: Array = it.get("rows", [])
	if not rows.is_empty():
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", DS.SP["SM"])
		grid.add_theme_constant_override("v_separation", DS.SP["SM"])
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for r: Array in rows:
			grid.add_child(_stat_card(str(r[0]), str(r[1]), str(r[2]) if r.size() > 2 else ""))
		_detail.add_child(grid)

	# Deep-link rows (starved buildings etc.) → focus the building on the map.
	for entry: Dictionary in it.get("list", []):
		_detail.add_child(_list_row(entry, _item_color(it)))
	if int(it.get("list_more", 0)) > 0:
		var more := Label.new()
		more.theme_type_variation = "Caption"
		more.text = "…and %d more in the Ledger" % int(it.list_more)
		_detail.add_child(more)

	# Action row: deep-link · acknowledge (news) · dismiss.
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", DS.SP["SM"])
	var dl: Dictionary = it.get("deeplink", {})
	if str(dl.get("tile_id", "")) != "" or str(dl.get("building_id", "")) != "":
		var go := Button.new()
		go.text = "Go to it  ➤"
		go.focus_mode = Control.FOCUS_NONE
		go.pressed.connect(func() -> void: _navigate(dl))
		actions.add_child(go)
	if bool(it.get("ackable", false)):
		if bool(it.get("acked", false)):
			var done := Label.new()
			done.theme_type_variation = "Caption"
			done.text = "✓ Acknowledged"
			done.add_theme_color_override("font_color", DS.PALETTE["OK"])
			actions.add_child(done)
		else:
			var ack := Button.new()
			ack.theme_type_variation = "Primary"
			ack.text = "Acknowledge ✓"
			ack.focus_mode = Control.FOCUS_NONE
			ack.pressed.connect(func() -> void: TurnBriefing.acknowledge(str(it.id)))
			actions.add_child(ack)
	if bool(it.get("dismissible", false)):
		var dismiss := Button.new()
		dismiss.text = "✕ Dismiss"
		dismiss.focus_mode = Control.FOCUS_NONE
		dismiss.pressed.connect(func() -> void: TurnBriefing.dismiss(str(it.id)))
		actions.add_child(dismiss)
		if str(it.section) == "alerts":
			var hint := Label.new()
			hint.theme_type_variation = "Caption"
			hint.add_theme_font_size_override("font_size", 10)
			hint.text = "re-surfaces only if it worsens · stays in the bell"
			hint.add_theme_color_override("font_color", DS.PALETTE["TEXT_MUTED"])
			actions.add_child(hint)
	_detail.add_child(actions)

func _stat_card(label: String, value: String, tone: String) -> Control:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#0A1623")
	sb.border_color = Color("#1C3149")
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	card.add_theme_stylebox_override("panel", sb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 1)
	card.add_child(vb)
	var k := Label.new()
	k.theme_type_variation = "Caption"
	k.add_theme_font_size_override("font_size", 10)
	k.text = label
	vb.add_child(k)
	var v := Label.new()
	v.theme_type_variation = "Numeric"
	v.text = value
	match tone:
		"bad": v.add_theme_color_override("font_color", DS.PALETTE["DANGER"])
		"warn": v.add_theme_color_override("font_color", DS.PALETTE["WARN"])
		"ok": v.add_theme_color_override("font_color", DS.PALETTE["OK"])
	vb.add_child(v)
	return card

func _list_row(entry: Dictionary, tint: Color) -> Control:
	var row := Button.new()
	row.focus_mode = Control.FOCUS_NONE
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var iid := str(entry.get("instance_id", ""))
	var tile := str(entry.get("tile_id", ""))
	row.text = "%s   %s   — %s" % [Catalog.tile_label(tile), tile, str(entry.get("why", ""))]
	row.add_theme_color_override("font_color", tint)
	row.pressed.connect(func() -> void:
		_navigate({"building_id": iid, "tile_id": tile, "panel": "building"}))
	return row

func _navigate(dl: Dictionary) -> void:
	# The bell's deep-link contract: buildings focus the detail panel, tiles the camera.
	var building_id := str(dl.get("building_id", ""))
	var tile_id := str(dl.get("tile_id", ""))
	if str(dl.get("panel", "")) == "building" and building_id != "":
		MatchState.focus_building_requested.emit(building_id)
	elif tile_id != "":
		MatchState.focus_tile_requested.emit(tile_id)
