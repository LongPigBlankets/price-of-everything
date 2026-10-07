extends Control
## The turn briefing in DS2 (docs/briefing-ds2-plan.md; the owner's rulings in docs/ds2-owner-decisions.md,
## "Briefing"), the panel TurnBriefing shows. Its contract: open(select_id), flash(), and closing it (the Close key,
## Esc through PanelStack) collapses the briefing.
##
## One width, 540 logical px, in the middle of the screen under the top bar (many decisions are mandatory), opening
## by itself when a decision arrives. A plate of the top bar's navy steel: the THIS TURN nameplate and the one Close
## key; the gate, a screen that says whether the turn can end; then, scrolling on Building Detail's rail, the
## decision as a letter on the foreman's clipboard ("1 of 2"), the answers as cream keys on a gunmetal slab with
## their figures on LED screens and drums (DecisionState.choice_figures, the effects resolve applies), and the
## annunciator: a window per kind of alert that is live, lit amber or red, green for information; with none live, a
## line says there are no other updates. A lit window picked shows its readout, its rows (a good in its well, the place, Go to) and Silence alert, which
## quiets that alert until it gets worse. Read-only against the sim: answers go through DecisionState.resolve,
## silencing through TurnBriefing.dismiss.

const Parts := preload("res://scripts/briefing_ds2/parts.gd")
const AlertWindow := preload("res://scripts/briefing_ds2/annunciator.gd")
const Kit := preload("res://scripts/ds2/parts.gd")
const Key := preload("res://scripts/bdp_v3_key.gd")
const CreamKey := preload("res://scripts/ds2/cream_key.gd")
const Scroll := preload("res://scripts/bdp_v3_scroll.gd")
const LampOverlay := preload("res://scripts/ds2/lamp_overlay.gd")
const Plate := preload("res://scripts/bdp_v3_plate.gd")
const Metrics := preload("res://scripts/ds2/metrics.gd")
const UIFonts := preload("res://scripts/ui_fonts.gd")

## One width for every state (owner ruling), and the plate's inside margins.
const WIDTH := 540.0
const PAD_X := 18
const PAD_TOP := 16
const PAD_BOTTOM := 18
## The column's gaps: between the head, the gate and the body; between the body's parts.
const GAP := 12
const BODY_GAP := 14
## Room kept at the body's right for the scroll rail, so nothing reflows when it shows.
const GUTTER := 14.0
## The top bar's line, and the room kept to the screen's edges.
const TOP_BAR := 72.0
const EDGE := 16.0
## The nameplate (the tile view's tile_nameplate, a horizontal three-slice) and its print.
const NAMEPLATE_SIZE := Vector2(176, 40)
const NAMEPLATE_MARGIN := 14.0
const NAMEPLATE_CAP := 60.0
const NAME_INK := Color("#eef1f5")
const CLOSE_KEY_PX := 40.0
## The clipboard: the board's edge round the letter, the room above it for the clip, and the clip's scale.
const BOARD_EDGE := 14
const CLIP_ROOM := 30
const CLIP_SCALE := 0.85
## The answer keys' width, and the rows' Go to and Silence keys'.
const ANSWER_KEY_W := 196.0
const GO_KEY_W := 84.0
const SILENCE_KEY_W := 140.0
const WINDOW_COLUMNS := 4
## What the body says under a letter when no alert is live. With no letter the gate line says it all.
const NO_UPDATES := "No other updates."

var _card: Control
var _head: HBoxContainer
var _gate: PanelContainer
var _scroll: ScrollContainer
var _body: VBoxContainer
var _windows: Array = []
## The annunciator window the player picked ("" for none).
var _picked := ""
var _flash_tween: Tween = null
var _fit_queued := false


func _init() -> void:
	name = "BriefingDs2"


func _ready() -> void:
	theme = DS.theme
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card = Control.new()
	_card.name = "Card"
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_card.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_card.draw.connect(func() -> void:
		Parts.crop_v(_card, Parts.tex("brief_backing"), Rect2(Vector2.ZERO, _card.size), Parts.BACKING_MARGIN, Parts.BACKING_FOOT))
	_card.resized.connect(_card.queue_redraw)
	add_child(_card)
	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", PAD_X)
	margin.add_theme_constant_override("margin_right", PAD_X)
	margin.add_theme_constant_override("margin_top", PAD_TOP)
	margin.add_theme_constant_override("margin_bottom", PAD_BOTTOM)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(margin)
	var col := VBoxContainer.new()
	col.name = "Column"
	col.add_theme_constant_override("separation", GAP)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(col)
	_head = _make_head()
	col.add_child(_head)
	_gate = Parts.screen_box("Gate", "")
	col.add_child(_gate)
	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	Scroll.apply(_scroll, true)
	col.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.name = "Body"
	_body.add_theme_constant_override("separation", BODY_GAP)
	_body.custom_minimum_size.x = body_width()
	_body.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.minimum_size_changed.connect(_queue_fit)
	_scroll.add_child(_body)
	LampOverlay.attach(_card)
	TurnBriefing.items_changed.connect(_on_items_changed)
	get_viewport().size_changed.connect(_queue_fit)
	# Hide FIRST, connect after: the first hide must not read as the player closing it.
	visible = false
	visibility_changed.connect(_on_visibility_changed)


## The body's width: the plate's inside less the rail's room.
static func body_width() -> float:
	return WIDTH - 2.0 * PAD_X - GUTTER


func open(select_id: String = "") -> void:
	_picked = ""
	if select_id != "" and not select_id.begins_with("dec:"):
		for w: Dictionary in TurnBriefing.alert_windows():
			if (w.items as Array).has(select_id):
				_picked = str(w.kind)
	_rebuild()
	visible = true
	move_to_front()
	PanelStack.push(self)
	_fit()
	_queue_fit()


## One amber flash: the player tried to end the turn with a decision waiting, or pressed the pen with the panel up.
func flash() -> void:
	if _flash_tween != null and _flash_tween.is_running():
		return
	_flash_tween = create_tween()
	_flash_tween.tween_property(_card, "self_modulate", Color(1.35, 1.2, 0.85), 0.15)
	_flash_tween.tween_property(_card, "self_modulate", Color(1, 1, 1), 0.5)


func _on_visibility_changed() -> void:
	if not visible:
		PanelStack.remove(self)
		if TurnBriefing.expanded:   # hidden from outside (Esc through PanelStack)
			TurnBriefing.collapse()


func _on_items_changed() -> void:
	if visible:
		_rebuild()


# --- the head -----------------------------------------------------------------------------------

func _make_head() -> HBoxContainer:
	var head := HBoxContainer.new()
	head.name = "Head"
	head.add_theme_constant_override("separation", 12)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var plate := Control.new()
	plate.name = "Nameplate"
	plate.custom_minimum_size = NAMEPLATE_SIZE
	plate.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	plate.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.draw.connect(func() -> void: _draw_nameplate(plate))
	head.add_child(plate)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(gap)
	var close: TextureButton = Key.make("close", CLOSE_KEY_PX)
	close.name = "CloseKey"
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(func() -> void: TurnBriefing.collapse())
	head.add_child(close)
	return head


## The tile view's black enamel nameplate, three-sliced, THIS TURN printed white in Bebas, centred.
func _draw_nameplate(n: Control) -> void:
	Parts.PeopleParts.draw_h3(n, Parts.tex("tile_nameplate"), Rect2(Vector2.ZERO, n.size), NAMEPLATE_MARGIN,
		NAMEPLATE_CAP - NAMEPLATE_MARGIN)
	var font: Font = UIFonts.BEBAS
	var fs := 30
	var text := "THIS TURN"
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var base := n.size.y * 0.5 + (font.get_ascent(fs) - font.get_descent(fs)) * 0.5
	var x := (n.size.x - w) * 0.5
	n.draw_string(font, Vector2(x, base - 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.7))
	n.draw_string(font, Vector2(x, base), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, NAME_INK)


# --- the body -----------------------------------------------------------------------------------

func _rebuild() -> void:
	var decisions: Array = TurnBriefing.unresolved_decisions()
	_set_gate(decisions.size())
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	_windows.clear()
	if not decisions.is_empty():
		_body.add_child(_clipboard(decisions[0], 1, decisions.size()))
		_body.add_child(_answer(decisions[0]))
	var windows: Array = TurnBriefing.alert_windows()
	var lit := windows.filter(func(w) -> bool: return str((w as Dictionary).tone) != "")
	if not lit.any(func(w) -> bool: return str((w as Dictionary).kind) == _picked):
		_picked = ""
	# With no decision waiting the worst lit window opens by itself; with one, the letter keeps the room.
	if _picked == "" and decisions.is_empty() and not lit.is_empty():
		_picked = _worst(lit)
	# Only the kinds that are live: the annunciator shows the lit windows, and with none under a letter a line
	# says so.
	if lit.is_empty():
		if decisions.is_empty():
			_queue_fit()
			return
		var none := Parts.body(NO_UPDATES)
		none.name = "NoUpdatesLine"
		_body.add_child(none)
	else:
		_body.add_child(_annunciator(lit))
	if _picked == "" and not lit.is_empty():
		var said := Parts.body("%s lit. Pick one for its detail." % _count(lit.size(), "alert"))
		said.name = "AnnunciatorLine"
		_body.add_child(said)
	else:
		for w: Dictionary in windows:
			if str(w.kind) == _picked:
				_detail(w)
	_queue_fit()


func _set_gate(n: int) -> void:
	var lamp: Control = _gate.get_node("Row/Lamp")
	lamp.visible = true
	lamp.call("set_tone", "warn" if n > 0 else "ok")
	var lines := Parts.lines_of(_gate)
	for c in lines.get_children():
		lines.remove_child(c)
		c.queue_free()
	var said := Parts.title(TurnBriefing.gate_line())
	said.name = "GateLine"
	lines.add_child(said)


static func _count(n: int, noun: String) -> String:
	return "%d %s%s" % [n, noun, "" if n == 1 else "s"]


## The first of the lit windows with the worst tone.
static func _worst(lit: Array) -> String:
	for tone in ["bad", "warn", "ok"]:
		for w: Dictionary in lit:
			if str(w.tone) == tone:
				return str(w.kind)
	return ""


# --- the letter ---------------------------------------------------------------------------------

## The decision as a letter of cream plastic clipped to the foreman's hardboard board: DECISION and "1 of 2" over
## the title, a rule, the headline when there is one and the story (narrative, as written).
func _clipboard(it: Dictionary, index: int, total: int) -> Control:
	var view: Dictionary = it.get("view", {})
	var board := MarginContainer.new()
	board.name = "Clipboard"
	board.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.add_theme_constant_override("margin_left", BOARD_EDGE)
	board.add_theme_constant_override("margin_right", BOARD_EDGE)
	board.add_theme_constant_override("margin_top", BOARD_EDGE + CLIP_ROOM)
	board.add_theme_constant_override("margin_bottom", BOARD_EDGE)
	board.draw.connect(func() -> void:
		Parts.crop_v(board, Parts.tex("brief_board"), Rect2(Vector2.ZERO, board.size), Parts.BOARD_MARGIN, Parts.BOARD_FOOT))
	board.resized.connect(board.queue_redraw)
	var letter := PanelContainer.new()
	letter.name = "Letter"
	letter.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	letter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pad := StyleBoxEmpty.new()
	pad.content_margin_left = 18
	pad.content_margin_right = 18
	pad.content_margin_top = 22
	pad.content_margin_bottom = 16
	letter.add_theme_stylebox_override("panel", pad)
	letter.draw.connect(func() -> void:
		Parts.draw_nine(letter, Parts.tex("sheet_white"), Rect2(Vector2.ZERO, letter.size), Parts.LETTER_MARGIN, Parts.LETTER_CORNER))
	letter.resized.connect(letter.queue_redraw)
	board.add_child(letter)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	letter.add_child(col)
	var kicker := HBoxContainer.new()
	kicker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	kicker.add_child(Parts.ink("DECISION", 14, Plate.FONT_BOLD))
	var of := Parts.ink("%d of %d" % [index, total], 14, Plate.FONT_SEMI)
	of.name = "LetterCount"
	of.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	kicker.add_child(of)
	col.add_child(kicker)
	var title := Parts.ink(str(view.get("title", it.get("title", ""))), 22, Plate.FONT_BOLD)
	title.name = "LetterTitle"
	col.add_child(title)
	var rule := ColorRect.new()
	rule.color = Color(Parts.NAVY, 0.5)
	rule.custom_minimum_size = Vector2(0, 1.5)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(rule)
	var headline := str(view.get("headline", ""))
	if headline != "":
		col.add_child(Parts.ink(headline, 15, Kit.FONT_TITLE))
	for para in str(view.get("body", "")).split("\n"):
		if str(para).strip_edges() != "":
			var story := Parts.ink(str(para).strip_edges(), 14, Kit.FONT_BODY)
			story.name = "LetterBody"
			col.add_child(story)
	# The clip, over the letter's head: a later child of the board, so it draws on top.
	var clip := Control.new()
	clip.name = "Clip"
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	clip.draw.connect(func() -> void:
		var t := Parts.tex("brief_clip")
		var s := t.get_size() / 2.0 * CLIP_SCALE
		# The jaw's top (the render's margin + 32 layout px) sits 8 px above the letter's edge.
		var jaw_top := (Parts.CLIP_MARGIN + 32.0) / Parts.LAYOUT * CLIP_SCALE
		clip.draw_texture_rect(t, Rect2(Vector2((clip.size.x - s.x) * 0.5, -8.0 - jaw_top), s), false))
	board.add_child(clip)
	return board


# --- the answers --------------------------------------------------------------------------------

## The answers on a gunmetal slab: a cream key per choice with its label, centred on what the choice brings beside
## it, its words (white) then its figures on screens and drums, with the loan a short purse needs and why a key is
## locked. An engraved line between one choice and the next.
func _answer(it: Dictionary) -> Control:
	var view: Dictionary = it.get("view", {})
	var slab := Parts.slab("Answer")
	var col := Parts.content_of(slab)
	col.add_theme_constant_override("separation", 14)
	col.add_child(Parts.caption("Your answer"))
	var first := true
	for choice: Dictionary in view.get("choices", []):
		if not first:
			col.add_child(Parts.rule())
		first = false
		var row := HBoxContainer.new()
		row.name = "Choice_%s" % str(choice.get("id", ""))
		row.add_theme_constant_override("separation", 12)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var key: Button = CreamKey.make("Answer_%s" % str(choice.get("id", "")), str(choice.get("label", "")), "", ANSWER_KEY_W)
		key.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		key.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		var available := bool(choice.get("available", true))
		if not available:
			key.set_spent(true)
			key.tooltip_text = str(choice.get("lock_reason", ""))
		var uid := str(view.get("uid", ""))
		var cid := str(choice.get("id", ""))
		key.pressed.connect(func() -> void:
			var err: String = DecisionState.resolve(cid, uid)
			if err != "":
				MatchState.request_toast(err, "warning"))
		row.add_child(key)
		var said := VBoxContainer.new()
		said.name = "Brings"
		said.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		said.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		said.add_theme_constant_override("separation", 6)
		said.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(said)
		for w in (choice.get("words", []) as Array):
			said.add_child(Parts.body(str(w)))
		for f: Dictionary in (choice.get("figures", []) as Array):
			var line := HBoxContainer.new()
			line.name = "Figure"
			line.add_theme_constant_override("separation", 8)
			line.mouse_filter = Control.MOUSE_FILTER_IGNORE
			line.add_child(Parts.body(str(f.get("caption", ""))))
			var fig := Parts.figure(f)
			fig.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			line.add_child(fig)
			said.add_child(line)
		var advocate: Dictionary = choice.get("advocate", {})
		if not advocate.is_empty():
			said.add_child(Parts.body("%s, %s: “%s”" % [str(advocate.get("name", "")), str(advocate.get("seat_name", "")),
				str(advocate.get("stance", ""))]))
		var shortfall := float(choice.get("loan_shortfall", 0.0))
		if available and shortfall > 0.0:
			var loan := Parts.body(TurnBriefing.shortfall_line(shortfall))
			loan.add_theme_color_override("font_color", DS.PALETTE["WARN"])
			said.add_child(loan)
		if not available:
			var lock := Parts.body(str(choice.get("lock_reason", "")))
			lock.add_theme_color_override("font_color", DS.PALETTE["WARN"])
			said.add_child(lock)
		if said.get_child_count() == 0:
			said.add_child(Parts.body("No other effect."))
		col.add_child(row)
	return slab


# --- the annunciator ----------------------------------------------------------------------------

func _annunciator(windows: Array) -> Control:
	var case := Kit.plastic_case("Annunciator")
	var rows: VBoxContainer = case.get_child(0)
	var grid := GridContainer.new()
	grid.name = "Windows"
	grid.columns = WINDOW_COLUMNS
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 10)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(grid)
	for w: Dictionary in windows:
		var win: Control = AlertWindow.new(str(w.kind), str(w.legend))
		win.tone = str(w.tone)
		win.count = int(w.count)
		win.latched = str(w.kind) == _picked
		win.tooltip_text = "" if str(w.tone) == "" else "Show its detail"
		win.pressed.connect(_on_window_pressed)
		grid.add_child(win)
		_windows.append(win)
	return case


func _on_window_pressed(kind: String) -> void:
	_picked = "" if _picked == kind else kind
	# Deferred: the window pressed is freed by the rebuild, and it is still handling its click.
	_rebuild.call_deferred()


## A picked window's detail: its readout (what is wrong and what to do), its figures, its rows and Silence alert.
func _detail(w: Dictionary) -> void:
	var items: Array = []
	for id in (w.items as Array):
		for it: Dictionary in TurnBriefing.items():
			if str(it.get("id", "")) == str(id):
				items.append(it)
	if items.is_empty():
		return
	var first: Dictionary = items[0]
	var readout := Parts.screen_box("Readout", str(w.tone))
	var lines := Parts.lines_of(readout)
	var name_line := Parts.title(str(first.get("title", "")) if items.size() == 1 else "%d deposits exhausted" % items.size())
	name_line.name = "ReadoutName"
	lines.add_child(name_line)
	var body_text := str(first.get("body", ""))
	if body_text != "":
		var detail := Parts.body(body_text)
		detail.name = "ReadoutDetail"
		lines.add_child(detail)
	_body.add_child(readout)
	var figures: Array = first.get("figures", [])
	var stat_rows: Array = first.get("rows", [])
	if not figures.is_empty() or not stat_rows.is_empty():
		var slab := Parts.slab("Figures")
		var col := Parts.content_of(slab)
		if not figures.is_empty():
			for f: Dictionary in figures:
				col.add_child(_figure_line(str(f.get("caption", "")), Parts.figure(f)))
		else:
			for r: Array in stat_rows:
				var value := Parts.title(str(r[1]))
				value.autowrap_mode = TextServer.AUTOWRAP_OFF
				value.custom_minimum_size.x = 0
				value.size_flags_horizontal = Control.SIZE_SHRINK_END
				value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
				col.add_child(_figure_line(str(r[0]), value))
		_body.add_child(slab)
	var entries: Array = []
	var more := 0
	for it: Dictionary in items:
		entries.append_array(it.get("list", []))
		more += int(it.get("list_more", 0))
	if not entries.is_empty():
		var slab := Parts.slab("Rows")
		var col := Parts.content_of(slab)
		col.add_theme_constant_override("separation", 12)
		var to_stock := str(w.kind) == "stockpile_small"
		for e: Dictionary in entries:
			col.add_child(_place_row(e, to_stock))
		if more > 0:
			col.add_child(Parts.body("%d more not shown." % more))
		_body.add_child(slab)
	if items.any(func(it) -> bool: return bool((it as Dictionary).get("dismissible", false))):
		var foot := HBoxContainer.new()
		foot.name = "SilenceRow"
		foot.add_theme_constant_override("separation", 12)
		foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var silence: Button = CreamKey.make("SilenceKey", TurnBriefing.SILENCE_LABEL, "", SILENCE_KEY_W)
		silence.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		var ids: Array = (w.items as Array).duplicate()
		silence.pressed.connect(func() -> void:
			for id in ids:
				TurnBriefing.dismiss(str(id))
			_picked = "")
		foot.add_child(silence)
		var hint := Parts.body(TurnBriefing.SILENCE_HINT)
		hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		foot.add_child(hint)
		_body.add_child(foot)


func _figure_line(caption: String, figure: Control) -> HBoxContainer:
	var line := HBoxContainer.new()
	line.name = "Figure"
	line.add_theme_constant_override("separation", 8)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(Parts.body(caption))
	figure.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(figure)
	return line


## A row naming a building or a place: the good it lacks in its well, its name and why, and Go to.
func _place_row(e: Dictionary, to_stock: bool) -> Control:
	var row := HBoxContainer.new()
	row.name = "PlaceRow"
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gid := str(e.get("good_id", ""))
	if gid != "" and not Catalog.get_good(gid).is_empty():
		var well := Kit.good_in_well(gid, -1, "")
		well.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(well)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	words.add_theme_constant_override("separation", 2)
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var place := Parts.title(TurnBriefing.row_title(e))
	place.name = "RowTitle"
	words.add_child(place)
	var why := Parts.body(TurnBriefing.row_detail(e))
	why.name = "RowDetail"
	words.add_child(why)
	row.add_child(words)
	var go: Button = CreamKey.make("GoTo", "Go to", "", GO_KEY_W)
	var iid := str(e.get("instance_id", ""))
	var tile := str(e.get("tile_id", ""))
	go.pressed.connect(func() -> void: _navigate(iid, tile, to_stock))
	row.add_child(go)
	return row


## A building focuses Building Detail; a place moves the camera to its tile, the stockpile rows on its Stockpile tab.
func _navigate(iid: String, tile: String, to_stock: bool) -> void:
	if iid != "" and not BuildingState.get_building(iid).is_empty():
		MatchState.focus_building_requested.emit(iid)
	elif tile != "":
		MatchState.focus_tile_requested.emit(tile)
		if to_stock:
			MatchState.tile_stockpile_requested.emit(tile)


# --- size and place -----------------------------------------------------------------------------

func _queue_fit() -> void:
	if _fit_queued:
		return
	_fit_queued = true
	_fit.call_deferred()


## One width; as tall as its content, never above the top bar's line or past the screen's foot (the body scrolls);
## centred across the screen and in the room under the top bar.
func _fit() -> void:
	_fit_queued = false
	var vp := get_viewport()
	if vp == null or _card == null:
		return
	var rect := vp.get_visible_rect().size
	size = rect
	position = Vector2.ZERO
	var w := minf(WIDTH, rect.x - 2.0 * EDGE)
	var fixed := PAD_TOP + PAD_BOTTOM + _head.get_combined_minimum_size().y + GAP + _gate.get_combined_minimum_size().y + GAP
	var want := fixed + _body.get_combined_minimum_size().y
	var room := rect.y - TOP_BAR - 2.0 * EDGE
	var h := minf(want, room)
	_card.size = Vector2(w, h)
	_card.position = Vector2(roundf((rect.x - w) * 0.5), roundf(TOP_BAR + EDGE + (room - h) * 0.5))


## Test and capture seams.
func card() -> Control:
	return _card


func windows() -> Array:
	return _windows


func picked() -> String:
	return _picked
