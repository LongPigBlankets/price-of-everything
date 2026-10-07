extends Control
## The Research panel in DS2, built into the research panel (scripts/research_panel.gd) while
## UiPrefs.use_research_ds2 is on: a patent office and a drawing office's archive in one cabinet.
##
## The cabinet is Building Detail's navy steel backing with its raised title, the search on a screen and the
## Close key, then the rubber seam. Under it, down the left, the plan chest (plan_chest.gd): a drawer per
## research category. To its right, over the board, the licence office (the knowledge sharing offers: when the
## next comes, the free licences in hand, and the key that starts choosing) beside a readout of the drawing
## pointed at. Then the patent board (patent_board.gd) in its steel frame, seen through board_view.gd, which
## zooms and pans it: the open drawer's research pinned up as patent drawings (blueprint_card.gd), rank by rank.
## Resting the pointer on a drawing a moment dims the panel round it and shows it large (detail_sheet.gd).
## The panel is lit by the DS2 lamp from the top left (scripts/ds2/lamp_overlay.gd).
##
## Everything the view shows is the research panel's state and ResearchState's: the open category, the search
## (the panel's own box, moved onto this screen while the view is up and handed back after), the free unlocks
## and the choosing. The view asks the panel to act (open a category, start or stop choosing, license a
## research) and redraws when the panel calls refresh().

const Ink := preload("res://scripts/research_ds2/ink.gd")
const PlanChest := preload("res://scripts/research_ds2/plan_chest.gd")
const PatentBoard := preload("res://scripts/research_ds2/patent_board.gd")
const Nine := preload("res://scripts/bdp_v3_nine.gd")
const Title := preload("res://scripts/bdp_v3_title.gd")
const Key := preload("res://scripts/bdp_v3_key.gd")
const BoardView := preload("res://scripts/research_ds2/board_view.gd")
const DetailSheet := preload("res://scripts/research_ds2/detail_sheet.gd")
const LampOverlay := preload("res://scripts/ds2/lamp_overlay.gd")
const DotMatrix := preload("res://scripts/ds2/dot_matrix.gd")
const CreamKey := preload("res://scripts/ds2/cream_key.gd")
const LedgerV3 := preload("res://scripts/ledger_v3/ledger_v3.gd")
const UIFonts := preload("res://scripts/ui_fonts.gd")

const RANKS := ["I", "II", "III"]
## Building Detail's backing (panel_backing): its 9-slice corner in texels and the brass trim's width.
const BACKING_CORNER := 64.0
const MARGIN := Vector4(28, 18, 28, 24)
## The plan chest's width: a share of the panel's, within these bounds.
const CHEST_SHARE := 0.15
const CHEST_MIN := 214.0
const CHEST_MAX := 284.0
## The strip over the board, and the board frame's steel rim.
const STRIP_H := 82.0
const FRAME := 12.0
const SEARCH_W := 400.0
const SEARCH_H := 36.0
const PLACEHOLDER := "Search research by name or reward"
## The old canvas's print colour (research_panel.gd RESEARCH_TEXT), put back on the search box when it is handed back.
const OLD_PRINT := Color("#f6eedc")
## How long the pointer rests on a drawing before the detail sheet shows, so a sweep across the board does not flicker.
const DETAIL_DELAY := 0.25

var _host: Control
var _search: LineEdit
var _search_placeholder := ""
var _chest: Control
var _board: Control
var _view: Control
var _detail: Control
var _detail_for: Control = null
var _detail_wait := 0
var _licence_turns: Control
var _licence_count: Control
var _licence_key: Button
var _readout: Control
var _readout_name: Label
var _readout_reward: Label
var _readout_need: Label
## A search narrowed to one drawer ("" shows every drawer's matches), and the query it was for.
var _narrow := ""
var _query := ""
var _shown_key := ""
var _hovered: Control = null


func _init() -> void:
	name = "ResearchDs2"
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## The research panel this view shows. Call before the view enters the tree.
func bind(host: Control) -> void:
	_host = host


func _ready() -> void:
	if DS and DS.theme:
		theme = DS.theme
	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", int(MARGIN.x))
	margin.add_theme_constant_override("margin_top", int(MARGIN.y))
	margin.add_theme_constant_override("margin_right", int(MARGIN.z))
	margin.add_theme_constant_override("margin_bottom", int(MARGIN.w))
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	var col := VBoxContainer.new()
	col.name = "Cabinet"
	col.add_theme_constant_override("separation", 10)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(col)
	col.add_child(_head())
	col.add_child(LedgerV3.seam())
	var body := HBoxContainer.new()
	body.name = "Body"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(body)
	_chest = PlanChest.new()
	_chest.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chest.connect("drawer_pressed", _on_drawer_pressed)
	body.add_child(_chest)
	_chest.call("build", _categories())
	var right := VBoxContainer.new()
	right.name = "BoardColumn"
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 12)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(right)
	var strip := HBoxContainer.new()
	strip.name = "OfficeStrip"
	strip.custom_minimum_size.y = STRIP_H
	strip.add_theme_constant_override("separation", 14)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(strip)
	strip.add_child(_licence_office())
	strip.add_child(_readout_screen())
	right.add_child(_board_frame())
	_detail = DetailSheet.new()
	add_child(_detail)
	resized.connect(_size_chest)
	_size_chest()
	refresh()
	LampOverlay.attach(self)


## Hands the panel's search box back as it was found.
func release() -> void:
	if _search == null or _host == null:
		return
	var p := _search.get_parent()
	if p != null:
		p.remove_child(_search)
	_host.add_child(_search)
	for s in ["normal", "focus"]:
		_search.remove_theme_stylebox_override(s)
	_search.remove_theme_font_override("font")
	_search.remove_theme_font_size_override("font_size")
	_search.remove_theme_color_override("caret_color")
	_search.add_theme_color_override("font_placeholder_color", OLD_PRINT)
	_search.placeholder_text = _search_placeholder
	_search.custom_minimum_size = Vector2.ZERO
	_search.size_flags_horizontal = Control.SIZE_FILL
	_search.size_flags_vertical = Control.SIZE_FILL
	_search = null


func _draw() -> void:
	Nine.paint(self, Ink.tex("panel_backing"), Rect2(Vector2.ZERO, size), BACKING_CORNER)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _size_chest() -> void:
	if _chest != null:
		_chest.custom_minimum_size.x = clampf(size.x * CHEST_SHARE, CHEST_MIN, CHEST_MAX)


func _categories() -> Array:
	return _host.call("categories") if _host != null else []


# --- the head ------------------------------------------------------------------------------------

func _head() -> HBoxContainer:
	var head := HBoxContainer.new()
	head.name = "ResearchHead"
	head.add_theme_constant_override("separation", 16)
	var title: Control = Title.new()
	title.call("set_text", "Research")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(title)
	head.add_child(_search_screen())
	var close: TextureButton = Key.make("close", Title.line_height())
	close.name = "CloseKey"
	close.pressed.connect(func() -> void:
		if _host != null:
			_host.call("_close_panel"))
	head.add_child(close)
	return head


## The search on one of Building Detail's mini screens, white print on the dark glass. The field is the research
## panel's own box, so its text, its signal and its name (which the tutorial finds it by) are the ones it has.
func _search_screen() -> PanelContainer:
	var screen := PanelContainer.new()
	screen.name = "SearchScreen"
	screen.custom_minimum_size = Vector2(SEARCH_W, SEARCH_H)
	screen.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	screen.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var inset := StyleBoxEmpty.new()
	inset.set_content_margin_all(DotMatrix.RIM / DotMatrix.CAPTURE_SCALE + 3.0)
	inset.content_margin_left += 6.0
	screen.add_theme_stylebox_override("panel", inset)
	var corner := (DotMatrix.MARGIN + DotMatrix.RIM + DotMatrix.RADIUS + 2.0) * 2.0 / DotMatrix.CAPTURE_SCALE
	screen.draw.connect(func() -> void:
		var r := Rect2(Vector2.ZERO, screen.size)
		Nine.paint(screen, DotMatrix.SCREEN, r.grow(DotMatrix.MARGIN / DotMatrix.CAPTURE_SCALE), corner)
		screen.draw_rect(r.grow(-DotMatrix.RIM / DotMatrix.CAPTURE_SCALE), DotMatrix.PANE))
	screen.resized.connect(screen.queue_redraw)
	_search = _host.get("_search_input") if _host != null else null
	if _search == null:
		_search = LineEdit.new()
		_search.name = "ResearchSearchInput"
	else:
		var p := _search.get_parent()
		if p != null:
			p.remove_child(_search)
	_search_placeholder = _search.placeholder_text
	_search.placeholder_text = PLACEHOLDER
	_search.visible = true
	_search.position = Vector2.ZERO
	_search.custom_minimum_size = Vector2(160, SEARCH_H - 2.0 * (DotMatrix.RIM / DotMatrix.CAPTURE_SCALE + 3.0))
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	_search.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_search.add_theme_font_override("font", UIFonts.PLEX_MED)
	_search.add_theme_font_size_override("font_size", 15)
	_search.add_theme_color_override("font_color", Ink.TEXT)
	_search.add_theme_color_override("font_placeholder_color", Color(Ink.TEXT, 0.78))
	_search.add_theme_color_override("caret_color", DS.PALETTE["ACCENT"])
	screen.add_child(_search)
	return screen


# --- the licence office and the readout ----------------------------------------------------------

## The licence office: a blackened steel plate screwed over the board. Its name, when the next knowledge sharing
## offer comes and the free licences in hand on two dot matrix screens, and the key that starts choosing.
func _licence_office() -> PanelContainer:
	var plate := PanelContainer.new()
	plate.name = "LicenceOffice"
	plate.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var pad := StyleBoxEmpty.new()
	pad.content_margin_left = 22
	pad.content_margin_right = 18
	pad.content_margin_top = 10
	pad.content_margin_bottom = 10
	plate.add_theme_stylebox_override("panel", pad)
	plate.draw.connect(func() -> void: _draw_steel_plate(plate, Rect2(Vector2.ZERO, plate.size)))
	plate.resized.connect(plate.queue_redraw)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(row)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 0)
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	names.add_child(_label("Licence office", Ink.LABEL_FONT, 18, true))
	names.add_child(_label("Knowledge sharing", Ink.BODY_FONT, 13, false))
	row.add_child(names)
	var screens := VBoxContainer.new()
	screens.add_theme_constant_override("separation", 6)
	screens.alignment = BoxContainer.ALIGNMENT_CENTER
	screens.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_licence_turns = _dots("LicenceNext")
	_licence_count = _dots("LicenceCount")
	screens.add_child(_licence_turns)
	screens.add_child(_licence_count)
	row.add_child(screens)
	_licence_key = CreamKey.make("ChooseLicences", "Choose patents to license", "", 236.0)
	_licence_key.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_licence_key.pressed.connect(_on_licence_key)
	row.add_child(_licence_key)
	return plate


func _dots(node_name: String) -> Control:
	var d: Control = DotMatrix.new()
	d.name = node_name
	d.set("pitch", 1.8)
	d.set("align", HORIZONTAL_ALIGNMENT_LEFT)
	d.custom_minimum_size.x = 150.0
	return d


## The readout: a dark glass screen showing the drawing pointed at, what it grants and what it asks.
func _readout_screen() -> PanelContainer:
	var screen := PanelContainer.new()
	screen.name = "Readout"
	screen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	screen.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var inset := StyleBoxEmpty.new()
	inset.set_content_margin_all(DotMatrix.RIM / DotMatrix.CAPTURE_SCALE + 6.0)
	inset.content_margin_left += 6.0
	screen.add_theme_stylebox_override("panel", inset)
	var corner := (DotMatrix.MARGIN + DotMatrix.RIM + DotMatrix.RADIUS + 2.0) * 2.0 / DotMatrix.CAPTURE_SCALE
	screen.draw.connect(func() -> void:
		var r := Rect2(Vector2.ZERO, screen.size)
		Nine.paint(screen, DotMatrix.SCREEN, r.grow(DotMatrix.MARGIN / DotMatrix.CAPTURE_SCALE), corner)
		screen.draw_rect(r.grow(-DotMatrix.RIM / DotMatrix.CAPTURE_SCALE), DotMatrix.PANE))
	screen.resized.connect(screen.queue_redraw)
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 1)
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(lines)
	_readout_name = _label("", Ink.BODY_SEMI, 15, false)
	_readout_name.name = "ReadoutName"
	_readout_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	lines.add_child(_readout_name)
	_readout_reward = _label("", Ink.BODY_FONT, 13, false)
	_readout_reward.name = "ReadoutReward"
	_readout_reward.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_readout_reward.max_lines_visible = 2
	lines.add_child(_readout_reward)
	_readout_need = _label("", Ink.SPEC_FONT, 14, true)
	_readout_need.name = "ReadoutNeed"
	_readout_need.add_theme_color_override("font_color", Color("#ffd27a"))
	_readout_need.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	lines.add_child(_readout_need)
	_readout = screen
	return screen


## White print standing off a dark surface, its shadow cast away from the light.
func _label(text: String, font: Font, px: int, caps: bool) -> Label:
	var l := Label.new()
	l.text = text
	l.uppercase = caps
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", Ink.TEXT)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	var off := Ink.shadow_offset(1.4)
	l.add_theme_constant_override("shadow_offset_x", int(roundf(off.x)))
	l.add_theme_constant_override("shadow_offset_y", int(roundf(off.y)))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.clip_text = false
	return l


## A blackened steel plate (the kit's dark plate, cropped at 2 texels a px) with a bevel and a screw in each corner.
func _draw_steel_plate(ci: CanvasItem, r: Rect2) -> void:
	Ink.cast_shadow(ci, r, 4.0, 0.5, 4)
	var t := Ink.tex("dark_plate")
	if t != null:
		var src := Rect2(Vector2(60, 200), r.size * 2.0)
		src.size = src.size.min(t.get_size() - Vector2(120, 260))
		ci.draw_texture_rect_region(t, r, src)
	else:
		ci.draw_rect(r, Color("#22262c"))
	Ink.bevel(ci, r, 2.0, Color(1, 1, 1, 0.22), Color(0, 0, 0, 0.55))
	var screw := Ink.tex("screw_silver")
	if screw != null:
		for p in [Vector2(9, 9), Vector2(r.size.x - 9, 9), Vector2(9, r.size.y - 9), Vector2(r.size.x - 9, r.size.y - 9)]:
			ci.draw_texture_rect(screw, Rect2(r.position + p - Vector2(5, 5), Vector2(10, 10)), false)


# --- the board -----------------------------------------------------------------------------------

## The board in its steel frame: a gunmetal rim, lit along the edges facing the light, screwed at its corners;
## the board is zoomed and panned inside it (board_view.gd).
func _board_frame() -> MarginContainer:
	var frame := MarginContainer.new()
	frame.name = "BoardFrame"
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		frame.add_theme_constant_override(side, int(FRAME))
	frame.draw.connect(func() -> void: _draw_frame(frame))
	frame.resized.connect(frame.queue_redraw)
	_view = BoardView.new()
	_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_view.connect("interacted", _hide_detail)
	frame.add_child(_view)
	_board = _view.get("board")
	_board.connect("card_hover", _on_card_hover)
	_board.connect("card_picked", _on_card_picked)
	return frame


func _draw_frame(frame: Control) -> void:
	var r := Rect2(Vector2.ZERO, frame.size)
	Ink.cast_shadow(frame, r, 5.0, 0.5, 3)
	frame.draw_rect(r, Color("#3b424b"))
	var inner := r.grow(-FRAME)
	# The rim's faces: the outer edges and the inner lip, each lit on the side facing the light.
	Ink.bevel(frame, r, 3.0, Color(1, 1, 1, 0.26), Color(0, 0, 0, 0.5))
	Ink.bevel(frame, inner.grow(2.0), 2.0, Color(0, 0, 0, 0.55), Color(1, 1, 1, 0.2))
	frame.draw_rect(inner, Color("#151719"))
	var screw := Ink.tex("screw_silver")
	if screw != null:
		for p in [Vector2(6, 6), Vector2(r.size.x - 6, 6), Vector2(6, r.size.y - 6), Vector2(r.size.x - 6, r.size.y - 6)]:
			frame.draw_texture_rect(screw, Rect2(p - Vector2(4.5, 4.5), Vector2(9, 9)), false)


# --- refresh -------------------------------------------------------------------------------------

## Redraws the chest, the board and the office from the research panel's state.
func refresh() -> void:
	if _host == null or _board == null:
		return
	var query := str(_host.get("_search_query")).strip_edges()
	var searching := query != ""
	if query != _query:
		_query = query
		_narrow = ""
	var selected := str(_host.get("_selected_category"))
	var nodes: Array = []
	for u: Dictionary in _host.call("_category_unlocks", selected):
		if not bool(u.get("is_category_root", false)):
			nodes.append(u)
	# A link to one research lands in its drawer.
	if searching and str(_host.get("_search_exact_title")) != "" and nodes.size() == 1:
		_narrow = str(nodes[0].get("category", ""))
		if _narrow != selected and _categories().has(_narrow):
			_host.set("_selected_category", _narrow)
			selected = _narrow
	var matches := {}
	if searching:
		for u: Dictionary in nodes:
			var c := str(u.get("category", ""))
			matches[c] = int(matches.get(c, 0)) + 1
	var shown: Array = nodes
	if searching and _narrow != "":
		shown = nodes.filter(func(u: Dictionary) -> bool: return str(u.get("category", "")) == _narrow)
	_chest.call("set_figures", _drawer_figures(selected, searching, matches))
	var choosing := bool(_host.get("_choosing_free_unlock"))
	_board.call("populate", _rows(shown, selected, searching), _needs(), choosing,
		"No patents found" if searching else "")
	var key := "%s|%s|%s" % [selected, _narrow, query]
	if key != _shown_key:
		_shown_key = key
		_view.call("reset")
	_hovered = null
	_hide_detail()
	_refresh_office(choosing)
	_show_readout(null)


func _is_granted(title: String) -> bool:
	return ResearchState.is_unlocked(title) or (_host.get("_free_unlocked_titles") as Dictionary).has(title)


func _rank_of(u: Dictionary) -> String:
	return str(_host.call("_rank_value", u))


## Each drawer's figures: its count granted, its ranks' lamps, and while searching its matches.
func _drawer_figures(selected: String, searching: bool, matches: Dictionary) -> Dictionary:
	var out := {}
	var rows: Array = _host.get("_unlock_rows")
	for cat: String in _categories():
		var total := 0
		var granted := 0
		var per_rank := {"I": [0, 0], "II": [0, 0], "III": [0, 0]}
		for u: Dictionary in rows:
			if str(u.get("category", "")) != cat or not ResearchState.is_research_visible(u):
				continue
			total += 1
			var g := _is_granted(str(u.get("title", "")))
			if g:
				granted += 1
			var rk := _rank_of(u)
			per_rank[rk][1] += 1
			if g:
				per_rank[rk][0] += 1
		var lamps: Array = []
		for rk: String in RANKS:
			var pr: Array = per_rank[rk]
			if int(pr[1]) > 0 and int(pr[0]) >= int(pr[1]):
				lamps.append("done")
			elif int(pr[1]) > 0 and ResearchState.is_tier_available(cat, rk):
				lamps.append("open")
			else:
				lamps.append("off")
		var m := int(matches.get(cat, 0))
		out[cat] = {
			"granted": granted, "total": total, "ranks": lamps,
			"open": (not searching and cat == selected) or (searching and cat == _narrow),
			"matches": m if searching else -1,
			"lit": searching and m > 0,
			"dim": searching and m == 0,
		}
	return out


## The board's rows from the research `shown`, I first.
func _rows(shown: Array, selected: String, searching: bool) -> Array:
	var by_rank := {"I": [], "II": [], "III": []}
	for u: Dictionary in shown:
		by_rank[_rank_of(u)].append(u)
	var rows: Array = []
	var choosing := bool(_host.get("_choosing_free_unlock"))
	for rk: String in RANKS:
		var list: Array = by_rank[rk]
		if list.is_empty():
			continue
		list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var oa := int((_host.call("_presentation", a) as Dictionary).get("order", 0))
			var ob := int((_host.call("_presentation", b) as Dictionary).get("order", 0))
			return oa < ob if oa != ob else str(a.get("title", "")) < str(b.get("title", "")))
		var rank_open := searching or ResearchState.is_tier_available(selected, rk)
		var granted := 0
		var cards: Array = []
		for u: Dictionary in list:
			var title := str(u.get("title", ""))
			var licensed := (_host.get("_free_unlocked_titles") as Dictionary).has(title)
			var is_granted := _is_granted(title)
			if is_granted:
				granted += 1
			var cat := str(u.get("category", ""))
			var state := "open"
			var note := ""
			if licensed:
				state = "licensed"
			elif is_granted:
				state = "granted"
			elif not ResearchState.is_node_available(title):
				state = "locked"
				if not ResearchState.is_tier_available(cat, rk):
					note = "Rank %s closed" % rk if searching else ""
				else:
					for p: String in _host.call("_prereq_titles", u):
						if not ResearchState.is_unlocked(p):
							note = "Needs %s" % p
							break
			if note == "" and searching:
				note = cat
			cards.append({
				"unlock": u,
				"presentation": _host.call("_presentation", u),
				"state": state,
				"spec": str(_host.call("_collapsed_condition", u)),
				"progress": Vector2i.ZERO if is_granted else ResearchState.condition_progress(title),
				"note": note,
				"eligible": choosing and bool(_host.call("can_choose_free_unlock", title)),
			})
		rows.append({
			"rank": rk, "open": rank_open, "granted": granted, "total": list.size(),
			"notice": _rank_notice(selected, rk), "cards": cards,
		})
	return rows


## The notice pinned over a closed rank: what opens it and how far that has come.
func _rank_notice(category: String, rank: String) -> Dictionary:
	var i := RANKS.find(rank)
	if i <= 0:
		return {}
	var prev: String = RANKS[i - 1]
	var prior := 0
	var prior_granted := 0
	for u: Dictionary in _host.get("_unlock_rows"):
		if str(u.get("category", "")) == category and _rank_of(u) == prev and ResearchState.is_research_visible(u):
			prior += 1
			if ResearchState.is_unlocked(str(u.get("title", ""))):
				prior_granted += 1
	var need := mini(ResearchState.TIER_UNLOCK_THRESHOLD, prior)
	return {
		"heading": "Rank %s closed" % rank,
		"line": "Opens when %d Rank %s %s granted." % [need, prev, "patent is" if need == 1 else "patents are"],
		"count": "%d/%d" % [mini(prior_granted, need), need],
	}


## Every research title's prerequisites, as titles, for the threads.
func _needs() -> Dictionary:
	var out := {}
	for u: Dictionary in _host.get("_unlock_rows"):
		var pre: Array = _host.call("_prereq_titles", u)
		if not pre.is_empty():
			out[str(u.get("title", ""))] = pre
	return out


func _refresh_office(choosing: bool) -> void:
	var free := int(_host.get("_free_unlocks"))
	var next := _next_offer_turns()
	_licence_turns.set("text", ("NEXT IN %d TURNS" % next) if next > 0 else "NO MORE OFFERS")
	_licence_count.set("text", "%d FREE %s" % [free, "LICENCE" if free == 1 else "LICENCES"])
	_licence_count.set("colour", Color("#ffd27a") if free > 0 else Color.WHITE)
	_licence_key.set("chosen", choosing)
	_licence_key.set("title", "Stop choosing" if choosing else "Choose patents to license")
	_licence_key.call("set_spent", free <= 0 and not choosing)
	_licence_key.tooltip_text = "Click a lit drawing to license it free. Esc stops." if choosing else \
		("License research free with the licences from knowledge sharing." if free > 0 else "No free licences in hand.")
	_licence_key.queue_redraw()


## Turns until the next knowledge sharing offer, or 0 when none is left.
func _next_offer_turns() -> int:
	var grants: Dictionary = _host.get("_knowledge_grants")
	var turns := grants.keys()
	turns.sort()
	for t in turns:
		if TurnManager.current_turn < int(t):
			return int(t) - TurnManager.current_turn
	return 0


func _show_readout(card: Control) -> void:
	if _readout_name == null:
		return
	if bool(_host.get("_choosing_free_unlock")) and card == null:
		_readout_name.text = "Choosing a licence"
		_readout_reward.text = "Click a lit drawing to license it free. Esc stops choosing."
		_readout_need.text = ""
		return
	if card == null:
		var sel := str(_host.get("_selected_category"))
		var drawer: Control = _chest.call("drawer_for", sel)
		if _query != "":
			_readout_name.text = "Search: %s" % _query
			_readout_reward.text = "Drawers holding a match are lit. Open one to see only its patents."
		else:
			_readout_name.text = "%s: %d of %d granted" % [sel, int(drawer.get("granted")) if drawer != null else 0, int(drawer.get("total")) if drawer != null else 0]
			_readout_reward.text = "Point at a drawing to read what it grants."
		_readout_need.text = ""
		return
	var title := str(card.get("title"))
	var u: Dictionary = ResearchState.get_unlock_def(title)
	var row: Dictionary = {}
	for r: Dictionary in _host.get("_unlock_rows"):
		if str(r.get("title", "")) == title:
			row = r
			break
	_readout_name.text = "%s   Rank %s" % [title, _rank_of(row)]
	_readout_reward.text = str(u.get("description", ""))
	var state := str(card.get("state"))
	if state == "granted":
		_readout_need.text = "Granted"
	elif state == "licensed":
		_readout_need.text = "Licensed free"
	else:
		var p: Vector2i = card.get("progress")
		var cond := str(_host.call("_condition_text", row))
		_readout_need.text = cond + ("   %d/%d" % [p.x, p.y] if p != Vector2i.ZERO else "")


func _on_card_hover(card: Control, on: bool) -> void:
	if on:
		_hovered = card
		_show_readout(card)
		_detail_wait += 1
		var wait := _detail_wait
		get_tree().create_timer(DETAIL_DELAY).timeout.connect(func() -> void:
			if wait == _detail_wait and _hovered == card and is_instance_valid(card) and card.is_visible_in_tree():
				show_detail(card))
	elif _hovered == card:
		_hovered = null
		_show_readout(null)
		_hide_detail()


## Shows `card`'s research large, the panel dimmed round the card.
func show_detail(card: Control) -> void:
	if _detail == null or card == null:
		return
	_detail_for = card
	var r := card.get_global_rect()
	var local := Rect2(r.position - get_global_rect().position, r.size)
	var top := _view.get_global_rect().position.y - get_global_rect().position.y - 96.0
	_detail.call("show_for", _detail_data(card), local, maxf(top, 60.0))


func _hide_detail() -> void:
	_detail_wait += 1
	_detail_for = null
	if _detail != null and _detail.visible:
		_detail.call("hide_sheet")


## Everything the detail sheet shows for `card`'s research, from the research panel and ResearchState.
func _detail_data(card: Control) -> Dictionary:
	var title := str(card.get("title"))
	var row: Dictionary = {}
	for r: Dictionary in _host.get("_unlock_rows"):
		if str(r.get("title", "")) == title:
			row = r
			break
	var state := str(card.get("state"))
	var needs: Array = []
	var waiting := ""
	for p: String in _host.call("_prereq_titles", row):
		var got := ResearchState.is_unlocked(p)
		needs.append({"title": p, "granted": got})
		if not got and waiting == "":
			waiting = p
	var leads: Array = []
	for r: Dictionary in _host.get("_unlock_rows"):
		if not ResearchState.is_research_visible(r):
			continue
		if (_host.call("_prereq_titles", r) as Array).has(title):
			leads.append(str(r.get("title", "")))
	var rank := _rank_of(row)
	var category := str(row.get("category", ""))
	var state_text := ""
	match state:
		"granted":
			state_text = "Granted"
		"licensed":
			state_text = "Licensed free from a knowledge sharing offer"
		"locked":
			if not ResearchState.is_tier_available(category, rank):
				state_text = "Locked: Rank %s is closed" % rank
			elif waiting != "":
				state_text = "Locked: needs %s" % waiting
			else:
				state_text = "Locked"
	var spec: Dictionary = _host.call("_presentation", row)
	return {
		"title": title, "rank": rank, "category": category, "node_id": str(row.get("research_node_id", "")),
		"description": str(row.get("description", "")),
		"condition": str(_host.call("_condition_text", row)),
		"progress": card.get("progress"),
		"parts": ResearchState.condition_parts(title),
		"needs": needs, "leads": leads, "state": state, "state_text": state_text,
		"icon_kind": str(spec.get("kind", "system")), "icon_base": str(spec.get("base", "")),
		"icon_glyph": str(spec.get("glyph", "gears")),
	}


func _on_card_picked(card: Control) -> void:
	if _host != null:
		_host.call("choose_free_unlock", str(card.get("title")))


func _on_licence_key() -> void:
	if _host == null:
		return
	if bool(_host.get("_choosing_free_unlock")):
		_host.call("end_free_unlock_choice")
	else:
		_host.call("begin_free_unlock_choice")


func _on_drawer_pressed(category: String) -> void:
	if _host == null:
		return
	if _query != "":
		_narrow = "" if _narrow == category else category
		if _narrow != "":
			_host.set("_selected_category", category)
		refresh()
	else:
		_host.call("select_category", category)


# --- for the tutorial, the tests and the tools ---------------------------------------------------

func chest() -> Control:
	return _chest


func board() -> Control:
	return _board


func board_view() -> Control:
	return _view


func detail_sheet() -> Control:
	return _detail


func drawers() -> Array:
	return _chest.call("drawers") if _chest != null else []


func card_for(title: String) -> Control:
	return _board.call("card_for", title) if _board != null else null


## Opens `category`'s drawer as a click would.
func open_drawer(category: String) -> void:
	_on_drawer_pressed(category)


## The on screen rect of `title`'s drawing, scrolled into view first; empty when it is not on the board.
func card_rect(title: String) -> Rect2:
	var card := card_for(title)
	if card == null:
		return Rect2()
	_view.call("ensure_visible", card)
	return card.get_global_rect().grow(8.0)


## True when at least half of `title`'s drawing shows inside the board's frame.
func card_visible(title: String) -> bool:
	var card := card_for(title)
	if card == null or not card.is_visible_in_tree():
		return false
	var view := _view.get_global_rect()
	var r := card.get_global_rect()
	return view.has_point(r.get_center()) and view.intersection(r).get_area() >= r.get_area() * 0.5
