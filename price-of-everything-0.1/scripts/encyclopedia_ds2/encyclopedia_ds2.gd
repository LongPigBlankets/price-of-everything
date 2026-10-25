extends Control
## The encyclopedia in DS2: a midcentury trade catalogue in a ring binder open on the desk (the study:
## tools/button_mockup/cluster.html, set `encyclopediacatalog`). The default, behind UiPrefs.use_encyclopedia_ds2;
## the cheat `toggle encyclopedia ds2` brings the old search panel back. The search overlay (search_overlay.gd)
## keeps its signals, its Esc and its dimmed backdrop, and hands every open to this book.
##
## Across the head the registry's navy steel header: the ENCYCLOPEDIA nameplate, the label tape the look up is
## typed on, and the Back key. Under it the binder: two white pages on the cloth, three chrome rings down the
## spine and a divider tab a section at the fore edge, the open one pulled forward.
##
## Every view is a spread. The left page holds the thing itself: a good's picture, name and specification lines
## (Price impact underlined, opening Mechanics), the buildings that make it and what goes into it, and a navy
## outline key to its Goods Graph; a building's or a recipe's the same way. The right page runs one column of
## sections (Made by, then Used in, grouped by what each recipe makes), every recipe a full width card in a ruled
## border with its formula in pictures and its building's mark large at the right, named on hover. It pages along
## its foot when it runs over: Previous page bottom left, Next page bottom right, a dot a page. The look up is the
## catalogue's index; the contents list the four sections. No page numbers anywhere.
##
## Every size is in the render's layout px (docs/ds2-theme.md §2) unless it says logical; `L` converts.

const Data := preload("res://scripts/encyclopedia_ds2/catalogue.gd")
const PParts := preload("res://scripts/people_ds2/parts.gd")
const Plate := preload("res://scripts/bdp_v3_plate.gd")
const SmallKey := preload("res://scripts/bdp_v3_key.gd")
const LampOverlay := preload("res://scripts/ds2/lamp_overlay.gd")
const GoodIcons := preload("res://scripts/good_icons.gd")
const BuildingIcon := preload("res://scripts/building_icon.gd")
const BEBAS: FontFile = preload("res://assets/fonts/BebasNeue-Regular.ttf")
const BARLOW: FontFile = preload("res://assets/fonts/BarlowCondensed-Bold.ttf")
const BARLOW_SEMI: FontFile = preload("res://assets/fonts/BarlowCondensed-SemiBold.ttf")
const PLEX: FontFile = preload("res://assets/fonts/IBMPlexSans-Medium.ttf")
const PLEX_SEMI: FontFile = preload("res://assets/fonts/IBMPlexSans-SemiBold.ttf")
const GRAPH_OUTLINE: Texture2D = preload("res://assets/ui/bdp_v3/ency_graph_outline.png")

signal closed_requested()

const L := 1.0 / 1.875
const NAVY := Color("#0b2340")
const PAPER := Color("#fbfaf6")
const TINT := Color("#f1eee6")
const ACCENT := Color("#cf4527")
const MUSTARD := Color("#e2a720")
const TEAL := Color("#2a7a76")
const RULE := Color(0.043, 0.137, 0.251, 0.2)
const HOLE := Color("#1b3335")
const INK_SHADOW := Color(1, 1, 1, 0.5)
const WHITE_SHADOW := Color(0, 0, 0, 0.9)
const TAPE_INK := Color("#f1f1ee")

## The desk, the header and the binder, as the study lays them out (layout px).
const PW := 2617.0
const PH := 1600.0
const PAD := 40.0
const DESK := {"margin": 30.0, "corner": 60.0}
const HEAD := Rect2(40, 20, 2537, 112)
const HEAD_NINE := {"margin": 16.0, "corner": 30.0, "screw": 16.0}
const NAMEPLATE := Rect2(52, 8, 560, 96)
const NAMEPLATE_NINE := {"margin": 14.0, "cap": 60.0}
const TAPE := Rect2(1168.5, 43, 620, 66)
const TAPE_NINE := {"margin": 10.0, "cap": 20.0}
const BINDER := Rect2(60, 170, 2387, 1390)
const BINDER_NINE := {"margin": 24.0, "corner": 40.0}
const PAGE_GAP := 34.0
const PAGE_W := 1129.0
const PAGE_H := 1322.0
const PAGE_NINE := {"margin": 16.0, "corner": 20.0}
const RING_SIZE := Vector2(150, 100)
const RING_MARGIN := 22.0
const RING_AT := [0.18, 0.5, 0.82]
const TAB := {"w": 150.0, "h": 190.0, "margin": 14.0, "first": 80.0, "pitch": 214.0, "tuck": 30.0}
const TAB_COLOURS := {"goods": ACCENT, "recipes": TEAL, "buildings": MUSTARD, "mechanics": NAVY}

## The page's print (layout px, page local).
const M := 56.0                 # the page's side margin
const TOP := 104.0              # where the first section starts under the running head
const ROOM := 1100.0            # a right page's height for its column, above the pager
const BAR_H := 66.0
const GROUP_H := 66.0
const CARD_H := 108.0
const CARD_GAP := 12.0
const ITEM_H := 96.0
const TILE := 110.0
const TILE_ROW_H := 176.0
const NAME_W := 330.0
const ZONE_PAD := 32.0
const MIN_PX := 12              # logical: no print under 12 px

var _overlay: Control           # the search overlay this book sits in
var _view: Dictionary = {}
var _history: Array = []
var _page := 0
var _pages: Array = []          # the right page's parts, a page each
var _left_pages: Array = []     # a mechanic's flow on the left page, a spread each
var _hover := ""

var _book: Control
var _header: Control
var _tape: LineEdit
var _back: Control
var _left: Control
var _right: Control
var _tabs: Array = []
var _spaced_cache: Dictionary = {}


func _init(overlay: Control = null) -> void:
	_overlay = overlay


func _ready() -> void:
	name = "EncyclopediaDs2"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if DS != null and DS.theme != null:
		theme = DS.theme
	_book = Control.new()
	_book.name = "Book"
	_book.mouse_filter = Control.MOUSE_FILTER_STOP
	_book.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_book.size = Vector2(PW, PH) * L
	_book.draw.connect(_draw_book)
	add_child(_book)

	_header = _region("Header", _draw_header)
	_place(_header, HEAD)
	_tape = LineEdit.new()
	_tape.name = "LookUp"
	_tape.placeholder_text = "TYPE A GOOD, RECIPE, BUILDING OR TILE"
	_tape.caret_blink = true
	_tape.flat = true
	_tape.add_theme_font_override("font", BARLOW)
	_tape.add_theme_font_size_override("font_size", 21)
	_tape.add_theme_color_override("font_color", TAPE_INK)
	_tape.add_theme_color_override("font_placeholder_color", Color(TAPE_INK, 0.75))
	_tape.add_theme_color_override("caret_color", TAPE_INK)
	_tape.add_theme_color_override("selection_color", Color(1, 1, 1, 0.25))
	for st in ["normal", "focus", "read_only"]:
		_tape.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	_tape.text_changed.connect(_on_tape_changed)
	_book.add_child(_tape)
	_place(_tape, Rect2(TAPE.position + Vector2(24, 4), TAPE.size - Vector2(40, 8)))
	_back = SmallKey.make("back", 40.0)
	_back.name = "BackKey"
	_back.tooltip_text = "Back"
	(_back as BaseButton).pressed.connect(go_back)
	_book.add_child(_back)
	var kp := Vector2(PW - PAD - 62, HEAD.position.y + HEAD.size.y * 0.5) * L
	_back.position = kp - _back.size * 0.5

	# The tabs go under the right page (it covers their tucked ends), the pages over the binder.
	for i in Data.SECTIONS.size():
		var sec: String = Data.SECTIONS[i]
		var tab := _hit(_book, "", func() -> void: open_section(sec))
		tab.name = "Tab_" + sec
		tab.set_meta("section", sec)
		_tabs.append(tab)
	_left = _region("LeftPage", func() -> void: _draw_page(_left, true))
	_place(_left, Rect2(BINDER.position.x + PAGE_GAP, BINDER.position.y + PAGE_GAP, PAGE_W, PAGE_H))
	_right = _region("RightPage", func() -> void: _draw_page(_right, false))
	_place(_right, Rect2(_right_x(), BINDER.position.y + PAGE_GAP, PAGE_W, PAGE_H))
	var rings := _region("Rings", _draw_rings)
	_place(rings, Rect2(Vector2.ZERO, Vector2(PW, PH)))
	resized.connect(_fit)
	visibility_changed.connect(_fit)
	_fit.call_deferred()
	LampOverlay.attach(_book)
	if _view.is_empty():
		_view = {"kind": "contents", "section": "goods"}
	_render()


func _right_x() -> float:
	return BINDER.position.x + BINDER.size.x * 0.5 + 30.0


## The book at its own size, centred between the top bar and the bottom menu, smaller only if the screen is.
func _fit() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var top := 72.0
	var bottom := 112.0
	var avail := Vector2(size.x - 48.0, size.y - top - bottom)
	var k := minf(1.0, minf(avail.x / _book.size.x, avail.y / _book.size.y))
	_book.scale = Vector2(k, k)
	_book.position = Vector2((size.x - _book.size.x * k) * 0.5, top + maxf(0.0, (avail.y - _book.size.y * k) * 0.5))


func _region(node_name: String, painter: Callable) -> Control:
	var c := Control.new()
	c.name = node_name
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	c.draw.connect(painter)
	_book.add_child(c)
	return c


static func _place(c: Control, r: Rect2) -> void:
	c.position = r.position * L
	c.size = r.size * L


# ── Views ───────────────────────────────────────────────────────────────────────

func current_view() -> Dictionary:
	return _view


func page_index() -> int:
	return _page


func page_count() -> int:
	return maxi(_pages.size(), _left_pages.size())


func history_size() -> int:
	return _history.size()


func focus_tape() -> void:
	if is_inside_tree():
		_tape.grab_focus()
		_tape.caret_column = _tape.text.length()


## Opens a view fresh: what was open before is forgotten.
func open_fresh(view: Dictionary) -> void:
	_history.clear()
	_set_tape(str(view.get("query", "")))
	_show(view)


## Opens a view from this one: Back returns here.
func open_view(view: Dictionary) -> void:
	if not _view.is_empty():
		var was := _view.duplicate()
		was["page"] = _page
		_history.append(was)
	_show(view)


func go_back() -> void:
	if _history.is_empty():
		closed_requested.emit()
		return
	var view: Dictionary = _history.pop_back()
	_set_tape(str(view.get("query", "")) if str(view.kind) == "index" else _tape.text)
	_show(view, int(view.get("page", 0)))


func open_section(section: String) -> void:
	if section == "mechanics" and Data.mechanics_locked():
		return
	open_view({"kind": "contents", "section": section})


func open_entry(kind: String, id: String) -> void:
	if kind == "tile":
		closed_requested.emit()
		MatchState.focus_tile_requested.emit(id)
		return
	if kind == "good":
		TelemetryState.track_interaction("good_encyclopedia_opened", "encyclopedia", id)
	open_view({"kind": kind, "id": id})


func next_page() -> void:
	if _page < page_count() - 1:
		_page += 1
		_render_pages()


func previous_page() -> void:
	if _page > 0:
		_page -= 1
		_render_pages()


func _show(view: Dictionary, page := 0) -> void:
	_view = view
	_page = page
	if is_inside_tree():
		_render()


func _set_tape(text: String) -> void:
	if _tape != null and _tape.text != text:
		_tape.text = text


func _on_tape_changed(text: String) -> void:
	var upper := text.to_upper()
	if upper != text:
		var col := _tape.caret_column
		_tape.text = upper
		_tape.caret_column = col
	var q := upper.strip_edges()
	var view := {"kind": "index", "query": q} if q != "" else {"kind": "contents", "section": "goods"}
	if str(_view.get("kind", "")) == "index" or str(_view.get("kind", "")) == "contents":
		_show(view)
	else:
		open_view(view)


# ── Building a spread ───────────────────────────────────────────────────────────

var _left_paint: Callable
var _left_hits: Array = []

func _render() -> void:
	_left_hits = []
	_left_pages = []
	var parts: Array = []
	match str(_view.get("kind", "")):
		"good":
			_left_paint = _good_left.bind(str(_view.id))
			parts = _good_parts(str(_view.id))
		"building":
			_left_paint = _building_left.bind(str(_view.id))
			parts = _building_parts(str(_view.id))
		"recipe":
			_left_paint = _recipe_left.bind(str(_view.id))
			parts = _recipe_parts(str(_view.id))
		"mechanic":
			_left_paint = _mechanic_left.bind(str(_view.id))
			parts = []
		"index":
			_left_paint = _index_left.bind(str(_view.query))
			parts = _index_parts(str(_view.query))
		_:
			_left_paint = _contents_left
			parts = _section_parts(str(_view.get("section", "goods")))
	if str(_view.get("kind", "")) == "mechanic":
		_flow_mechanic(str(_view.id))
	else:
		_pages = Data.paginate(parts, func(_i: int) -> float: return ROOM)
	_page = clampi(_page, 0, maxi(0, page_count() - 1))
	_render_pages()


func _render_pages() -> void:
	for page: Control in [_left, _right]:
		for child in page.get_children():
			page.remove_child(child)
			child.queue_free()
	_left_hits = []
	_hover = ""
	# The left page paints and lists its targets in one pass.
	_left_paint.call(null)
	for h: Dictionary in _left_hits:
		_add_target(_left, h)
	for h: Dictionary in _right_targets():
		_add_target(_right, h)
	if not _left_pages.is_empty() and _page < _left_pages.size():
		_place_passages(_right, _left_pages[_page][1], TOP, true)
	_place_tabs()
	_left.queue_redraw()
	_right.queue_redraw()
	_book.queue_redraw()


## The current section, for the tab pulled forward.
func _section() -> String:
	match str(_view.get("kind", "")):
		"good": return "goods"
		"recipe": return "recipes"
		"building": return "buildings"
		"mechanic": return "mechanics"
		"contents": return str(_view.get("section", "goods"))
	return "goods"


func _place_tabs() -> void:
	var active := _section()
	for i in _tabs.size():
		var tab: Control = _tabs[i]
		var sec := str(tab.get_meta("section"))
		var on := sec == active
		var out: float = TAB.w - 20.0 - (0.0 if on else TAB.tuck)
		_place(tab, Rect2(_right_x() + PAGE_W, BINDER.position.y + TAB.first + i * TAB.pitch, out, TAB.h))
		var locked := sec == "mechanics" and Data.mechanics_locked()
		(tab as BaseButton).disabled = locked
		tab.set("tip", "Not available in the Demo" if locked else "")
		tab.tooltip_text = "Not available in the Demo" if locked else Data.SECTION_TITLES[sec].capitalize()


# ── Targets: a button over every part that opens something ──────────────────────

class HitButton extends Button:
	var tip := ""
	func _make_custom_tooltip(_for_text: String) -> Object:
		if tip == "":
			return null
		var p := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("#16233a")
		sb.set_corner_radius_all(4)
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_top = 5
		sb.content_margin_bottom = 5
		p.add_theme_stylebox_override("panel", sb)
		var l := Label.new()
		l.text = tip
		l.add_theme_font_override("font", PLEX_SEMI)
		l.add_theme_font_size_override("font_size", 13)
		l.add_theme_color_override("font_color", DS.PALETTE["TEXT"])
		p.add_child(l)
		return p


func _hit(parent: Control, tip: String, action: Callable) -> HitButton:
	var b := HitButton.new()
	b.tip = tip
	b.tooltip_text = tip if tip != "" else " "
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for st in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func _add_target(page: Control, h: Dictionary) -> void:
	var b := _hit(page, str(h.get("tip", "")), h.action)
	b.name = str(h.get("name", "Target"))
	if h.has("key"):
		var key := str(h.key)
		b.set_meta("key", key)
		b.mouse_entered.connect(func() -> void:
			_hover = key
			page.queue_redraw())
		b.mouse_exited.connect(func() -> void:
			if _hover == key:
				_hover = ""
				page.queue_redraw())
	_place(b, h.rect)


## Opens a recipe, a good or a building from a part on the page.
func _open(kind: String, id: String) -> Callable:
	return func() -> void: open_entry(kind, id)


# ── Drawing: the desk, the header, the binder, the rings, the tabs ──────────────

func _draw_book() -> void:
	PParts.draw_nine(_book, PParts.tex("registry_desk"), Rect2(Vector2.ZERO, _book.size), DESK.margin, DESK.corner)
	PParts.draw_nine(_book, PParts.tex("ency_binder"), Rect2(BINDER.position * L, BINDER.size * L), BINDER_NINE.margin, BINDER_NINE.corner)
	var active := _section()
	for i in Data.SECTIONS.size():
		var sec: String = Data.SECTIONS[i]
		var on := sec == active
		var x := _right_x() + PAGE_W - 20.0 - (0.0 if on else TAB.tuck)
		var y: float = BINDER.position.y + TAB.first + i * TAB.pitch
		var r := Rect2(Vector2(x, y) * L, Vector2(TAB.w, TAB.h) * L)
		PParts.draw_nine(_book, PParts.tex("ency_tab_" + sec), r, TAB.margin, 20.0)
		var ink: Color = NAVY if sec == "buildings" else PAPER
		var locked := sec == "mechanics" and Data.mechanics_locked()
		if locked:
			ink = Color(ink, 0.45)
		var out: float = TAB.w - 20.0 - (0.0 if on else TAB.tuck)
		var mid := Vector2(_right_x() + PAGE_W + out * 0.5, y + TAB.h * 0.5) * L
		_book.draw_set_transform(mid, PI * 0.5, Vector2.ONE)
		_spaced(_book, Data.SECTION_TITLES[sec], Vector2.ZERO, 28, ink, HORIZONTAL_ALIGNMENT_CENTER, 3.0, TAB.h - 30.0)
		_book.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_header() -> void:
	var c := _header
	var r := Rect2(Vector2.ZERO, c.size)
	PParts.draw_nine(c, PParts.tex("registry_header"), r, HEAD_NINE.margin, HEAD_NINE.corner)
	var screw: Texture2D = PParts.tex("screw_silver")
	var s := screw.get_size() * 0.5
	var si: float = HEAD_NINE.screw * L
	for p in [Vector2(si, si), Vector2(r.size.x - si, si), Vector2(si, r.size.y - si), Vector2(r.size.x - si, r.size.y - si)]:
		c.draw_texture_rect(screw, Rect2(p - s * 0.5, s), false)
	var plate := Rect2(NAMEPLATE.position * L, NAMEPLATE.size * L)
	PParts.draw_h3(c, PParts.tex("tile_nameplate"), plate, NAMEPLATE_NINE.margin, NAMEPLATE_NINE.cap - NAMEPLATE_NINE.margin)
	var fs := 30
	var tw := BEBAS.get_string_size("ENCYCLOPEDIA", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var at := Vector2(plate.get_center().x - tw * 0.5, plate.get_center().y + (BEBAS.get_ascent(fs) - BEBAS.get_descent(fs)) * 0.5)
	c.draw_string(BEBAS, at + Vector2(1, 1), "ENCYCLOPEDIA", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, WHITE_SHADOW)
	c.draw_string(BEBAS, at, "ENCYCLOPEDIA", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, DS.PALETTE["TEXT"])
	var tape := Rect2((TAPE.position - HEAD.position) * L, TAPE.size * L)
	PParts.draw_h3(c, PParts.tex("ency_tape"), tape, TAPE_NINE.margin, TAPE_NINE.cap)
	_white(c, PLEX_SEMI, 15, "Look up", Vector2(tape.position.x - 13.0, tape.get_center().y), HORIZONTAL_ALIGNMENT_RIGHT)
	_white(c, PLEX_SEMI, 15, "Back", Vector2((PW - PAD - 118 - HEAD.position.x) * L, r.size.y * 0.5), HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_rings() -> void:
	var c: Control = _book.get_node("Rings")
	var t: Texture2D = PParts.tex("ency_ring")
	var full := (RING_SIZE + Vector2.ONE * 2.0 * RING_MARGIN) * L
	var x := (BINDER.position.x + BINDER.size.x * 0.5) * L
	for f: float in RING_AT:
		var y := (BINDER.position.y + PAGE_GAP + PAGE_H * f) * L
		c.draw_texture_rect(t, Rect2(Vector2(x, y) - full * 0.5, full), false)


func _draw_page(page: Control, left: bool) -> void:
	PParts.draw_nine(page, PParts.tex("ency_page"), Rect2(Vector2.ZERO, page.size), PAGE_NINE.margin, PAGE_NINE.corner)
	var hx := (PAGE_W - 26.0) if left else 26.0
	for f: float in RING_AT:
		page.draw_circle(Vector2(hx, PAGE_H * f) * L, 13.0 * L, HOLE)
	if left:
		_left_paint.call(page)
	else:
		_paint_right(page)


# ── The right page: a column of parts, a page at a time ─────────────────────────

func _paint_right(c: Control) -> void:
	_running_head(c, _right_head()[0], _right_head()[1])
	if not _left_pages.is_empty():
		_paint_flow(c, _left_pages[_page][1] if _page < _left_pages.size() else [], TOP)
	elif _page < _pages.size():
		_paint_flow(c, _pages[_page], TOP)
	if page_count() > 1:
		_pager(c)


func _right_targets() -> Array:
	var hits: Array = []
	var parts: Array = []
	if not _left_pages.is_empty():
		parts = _left_pages[_page][1] if _page < _left_pages.size() else []
	elif _page < _pages.size():
		parts = _pages[_page]
	_flow_targets(parts, TOP, hits)
	if page_count() > 1:
		var y := PAGE_H - 58.0
		if _page > 0:
			hits.append({"name": "PreviousPage", "rect": Rect2(M, y - 26, 260, 52), "action": previous_page})
		if _page < page_count() - 1:
			hits.append({"name": "NextPage", "rect": Rect2(PAGE_W - M - 230, y - 26, 230, 52), "action": next_page})
	return hits


func _right_head() -> Array:
	match str(_view.get("kind", "")):
		"good": return [Catalog.get_display_name(str(_view.id)).to_upper(), "GOODS"]
		"building": return [str(Catalog.get_building(str(_view.id)).get("display_name", "")).to_upper(), "BUILDINGS"]
		"recipe": return [str(Catalog.get_recipe(str(_view.id)).get("display_name", "")).to_upper(), "RECIPES"]
		"mechanic": return [_mechanic_title(str(_view.id)).to_upper(), "MECHANICS"]
		"index": return ["LOOKED UP: %s" % str(_view.query), "INDEX"]
	return [Data.SECTION_TITLES[str(_view.get("section", "goods"))], "CONTENTS"]


## Parts: {h, bar, count, colour, fg} a section's heading; {h, head, good, head_name} a group's; {h, row} a recipe;
## {h, item} a good, building, tile or mechanic named in a list; {h, tiles} a row of pictures; {h, text} a passage.
func _paint_flow(c: Control, parts: Array, top: float) -> void:
	var y := top
	for p: Dictionary in parts:
		if p.has("bar"):
			_bar(c, M, y, PAGE_W - 2.0 * M, str(p.bar), str(p.get("count", "")), p.get("colour", NAVY), p.get("fg", PAPER))
		elif p.has("head"):
			_picture(c, str(p.good), Rect2(M, y + 2.0, 54, 54))
			_text(c, BARLOW, 28, str(p.head_name), Vector2(M + 68.0, y + 30.0), NAVY, HORIZONTAL_ALIGNMENT_LEFT, PAGE_W - 2.0 * M - 70.0)
		elif p.has("row"):
			_recipe_card(c, Rect2(M, y, PAGE_W - 2.0 * M, float(p.h) - CARD_GAP), p.row)
		elif p.has("item"):
			_item_card(c, Rect2(M, y, PAGE_W - 2.0 * M, float(p.h) - CARD_GAP), p.item)
		elif p.has("tiles"):
			_tile_row(c, Rect2(M, y, PAGE_W - 2.0 * M, float(p.h)), p.tiles)
		y += float(p.h)


func _flow_targets(parts: Array, top: float, hits: Array) -> void:
	var y := top
	for p: Dictionary in parts:
		if p.has("row"):
			_recipe_targets(Rect2(M, y, PAGE_W - 2.0 * M, float(p.h) - CARD_GAP), p.row, hits)
		elif p.has("item") and str((p.item as Dictionary).kind) != "note":
			var it: Dictionary = p.item
			hits.append({"name": "Item_" + str(it.id), "key": "item:" + str(it.id), "rect": Rect2(M, y, PAGE_W - 2.0 * M, float(p.h) - CARD_GAP),
				"action": _open(str(it.kind), str(it.id))})
		elif p.has("tiles"):
			var tiles: Array = p.tiles
			var cw := (PAGE_W - 2.0 * M) / 4.0
			for i in tiles.size():
				var t: Dictionary = tiles[i]
				hits.append({"name": "Tile_" + str(t.id), "tip": str(t.name), "rect": Rect2(M + i * cw, y, cw, float(p.h) - 10.0),
					"action": _open(str(t.kind), str(t.id))})
		elif p.has("head") and str(p.good) != "":
			hits.append({"name": "Group_" + str(p.good), "tip": Catalog.get_display_name(str(p.good)), "rect": Rect2(M, y, 60, 60),
				"action": _open("good", str(p.good))})
		y += float(p.h)


# ── A recipe card ───────────────────────────────────────────────────────────────

## A recipe as one full width row in a ruled border: its name at the left (two lines when long, a star while it
## needs research), the formula in pictures, and its building's mark large at the right behind a rule. A formula
## too wide for the row goes under the name, across the card.
func _recipe_card(c: Control, r: Rect2, row: Dictionary) -> void:
	var lay := _card_layout(r, row)
	var hovered := _hover == "recipe:" + str(row.id)
	_fill(c, r, TINT if hovered else PAPER)
	_stroke(c, r, 2.0, NAVY)
	var zone: float = lay.zone
	_fill(c, Rect2(r.end.x - zone, r.position.y + 12.0, 1.5, r.size.y - 24.0), RULE)
	_symbol(c, str(row.plant), Rect2(r.end.x - zone + 16.0, r.position.y + 10.0, zone - 32.0, zone - 32.0).abs())
	var nx: float = r.position.x + 18.0
	var name_mid: float = lay.name_y
	if bool(row.research):
		_star(c, Vector2(nx + 10.0, name_mid), 11.0)
		nx += 28.0
	var lines: Array = lay.lines
	for i in lines.size():
		_text(c, BARLOW, 27, str(lines[i]), Vector2(nx, name_mid + (i - (lines.size() - 1) * 0.5) * 31.0), NAVY, HORIZONTAL_ALIGNMENT_LEFT, lay.name_w)
	_formula(c, lay.formula_at, float(lay.px), row.inputs, row.outputs)


func _recipe_targets(r: Rect2, row: Dictionary, hits: Array) -> void:
	var lay := _card_layout(r, row)
	hits.append({"name": "Recipe_" + str(row.id), "key": "recipe:" + str(row.id), "rect": r, "action": _open("recipe", str(row.id))})
	var zone: float = lay.zone
	hits.append({"name": "Plant_" + str(row.plant), "tip": str(Catalog.get_building(str(row.plant)).get("display_name", "")),
		"rect": Rect2(r.end.x - zone + 8.0, r.position.y + 6.0, zone - 16.0, r.size.y - 12.0), "action": _open("building", str(row.plant))})
	if bool(row.research):
		hits.append({"name": "Research", "tip": "Needs research first", "rect": Rect2(r.position.x + 12.0, lay.name_y - 16.0, 32, 32), "action": _open("recipe", str(row.id))})
	for g: Dictionary in _formula_spots(lay.formula_at, float(lay.px), row.inputs, row.outputs):
		hits.append({"name": "Good_" + str(g.id), "tip": Catalog.get_display_name(str(g.id)), "rect": g.rect, "action": _open("good", str(g.id))})


## Where a card's name, formula and mark go, and its height.
func _card_layout(r: Rect2, row: Dictionary) -> Dictionary:
	var zone := CARD_H - 20.0 + ZONE_PAD
	var star := 28.0 if bool(row.research) else 0.0
	var name_w := NAME_W - star
	var lines := _wrap(BARLOW, 27, str(row.name), name_w, 2)
	var px := 62.0 if (row.inputs as Array).size() > 2 else 72.0
	var beside := r.size.x - zone - (NAME_W + 40.0) - 16.0
	if _formula_width(px, row.inputs, row.outputs) <= beside:
		return {"stacked": false, "zone": zone, "lines": lines, "name_w": name_w, "name_y": r.position.y + r.size.y * 0.5, "px": px,
			"formula_at": Vector2(r.position.x + NAME_W + 40.0, r.position.y + (r.size.y - px) * 0.5)}
	var across := r.size.x - zone - 36.0
	px = 62.0
	while px > 40.0 and _formula_width(px, row.inputs, row.outputs) > across:
		px -= 2.0
	lines = _wrap(BARLOW, 27, str(row.name), across - star, 1)
	return {"stacked": true, "zone": zone, "lines": lines, "name_w": across - star, "name_y": r.position.y + 32.0, "px": px,
		"formula_at": Vector2(r.position.x + 18.0, r.position.y + 58.0)}


func _row_height(row: Dictionary) -> float:
	var r := Rect2(0, 0, PAGE_W - 2.0 * M, CARD_H)
	var lay := _card_layout(r, row)
	if bool(lay.stacked):
		return 58.0 + float(lay.px) + 18.0 + CARD_GAP
	return CARD_H + CARD_GAP


func _qty_size(px: float) -> int:
	return int(round(px * 0.42))


func _formula_width(px: float, inputs: Array, outputs: Array) -> float:
	var w := 0.0
	for pair: Array in inputs:
		w += px + 4.0 + _str_w(BARLOW, _qty_size(px), "×%d" % int(pair[1])) + 14.0
	w += 48.0
	for pair: Array in outputs:
		w += px + 4.0 + _str_w(BARLOW, _qty_size(px), "×%d" % int(pair[1])) + 14.0
	return w


## The formula in pictures from `at` (its top left): each input and its quantity, an arrow, each output.
func _formula(c: Control, at: Vector2, px: float, inputs: Array, outputs: Array) -> void:
	var x := at.x
	var mid := at.y + px * 0.5
	for pair: Array in inputs:
		_picture(c, str(pair[0]), Rect2(x, at.y, px, px))
		var q := "×%d" % int(pair[1])
		_text(c, BARLOW, _qty_size(px), q, Vector2(x + px + 4.0, mid), NAVY)
		x += px + 4.0 + _str_w(BARLOW, _qty_size(px), q) + 14.0
	if inputs.is_empty():
		x += 0.0
	_fill(c, Rect2(x, mid - 2.0, 26.0, 4.0), ACCENT)
	c.draw_colored_polygon(PackedVector2Array([Vector2(x + 24.0, mid - 9.0) * L, Vector2(x + 38.0, mid) * L, Vector2(x + 24.0, mid + 9.0) * L]), ACCENT)
	x += 48.0
	for pair: Array in outputs:
		_picture(c, str(pair[0]), Rect2(x, at.y, px, px))
		var q := "×%d" % int(pair[1])
		_text(c, BARLOW, _qty_size(px), q, Vector2(x + px + 4.0, mid), NAVY)
		x += px + 4.0 + _str_w(BARLOW, _qty_size(px), q) + 14.0


func _formula_spots(at: Vector2, px: float, inputs: Array, outputs: Array) -> Array:
	var out: Array = []
	var x := at.x
	for pair: Array in inputs:
		out.append({"id": str(pair[0]), "rect": Rect2(x, at.y, px, px)})
		x += px + 4.0 + _str_w(BARLOW, _qty_size(px), "×%d" % int(pair[1])) + 14.0
	x += 48.0
	for pair: Array in outputs:
		out.append({"id": str(pair[0]), "rect": Rect2(x, at.y, px, px)})
		x += px + 4.0 + _str_w(BARLOW, _qty_size(px), "×%d" % int(pair[1])) + 14.0
	return out


## A good, building, tile or mechanic named in a list: its picture or mark, its name and a note, in a border.
func _item_card(c: Control, r: Rect2, it: Dictionary) -> void:
	_fill(c, r, TINT if _hover == "item:" + str(it.id) else PAPER)
	_stroke(c, r, 2.0, NAVY)
	var px := r.size.y - 20.0
	var pic := Rect2(r.position.x + 12.0, r.position.y + 10.0, px, px)
	match str(it.kind):
		"good": _picture(c, str(it.id), pic)
		"building": _symbol(c, str(it.id), pic)
		_: _fill(c, Rect2(pic.position + Vector2(px * 0.3, px * 0.3), Vector2(px * 0.4, px * 0.4)), TEAL if str(it.kind) == "tile" else NAVY)
	_text(c, BARLOW, 27, str(it.name), Vector2(pic.end.x + 20.0, r.position.y + r.size.y * 0.5 - (12.0 if str(it.get("note", "")) != "" else 0.0)), NAVY,
		HORIZONTAL_ALIGNMENT_LEFT, r.size.x - px - 60.0)
	if str(it.get("note", "")) != "":
		_text(c, PLEX, 21, str(it.note), Vector2(pic.end.x + 20.0, r.position.y + r.size.y * 0.5 + 16.0), NAVY, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - px - 60.0)


## A row of up to four pictures with their names under them.
func _tile_row(c: Control, r: Rect2, tiles: Array) -> void:
	var cw := r.size.x / 4.0
	for i in tiles.size():
		var t: Dictionary = tiles[i]
		var pic := Rect2(r.position.x + i * cw + (cw - TILE) * 0.5, r.position.y + 6.0, TILE, TILE)
		if str(t.kind) == "building":
			_symbol(c, str(t.id), pic)
		else:
			_picture(c, str(t.id), pic)
		_text(c, BARLOW, 24, str(t.name), Vector2(r.position.x + i * cw + cw * 0.5, pic.end.y + 26.0), NAVY, HORIZONTAL_ALIGNMENT_CENTER, cw - 12.0)
		if t.has("qty"):
			_text(c, PLEX_SEMI, 21, "×%d" % int(t.qty), Vector2(r.position.x + i * cw + cw * 0.5, pic.end.y + 54.0), NAVY, HORIZONTAL_ALIGNMENT_CENTER, cw - 12.0)


func _pager(c: Control) -> void:
	var y := PAGE_H - 58.0
	_fill(c, Rect2(M, y - 40.0, PAGE_W - 2.0 * M, 1.5), NAVY)
	if _page > 0:
		c.draw_colored_polygon(PackedVector2Array([Vector2(72, y - 11) * L, Vector2(56, y) * L, Vector2(72, y + 11) * L]), ACCENT)
		_spaced(c, "PREVIOUS PAGE", Vector2(84, y + 1), 24, NAVY, HORIZONTAL_ALIGNMENT_LEFT, 3.0)
	if _page < page_count() - 1:
		var ex := PAGE_W - 72.0
		c.draw_colored_polygon(PackedVector2Array([Vector2(ex, y - 11) * L, Vector2(ex + 16, y) * L, Vector2(ex, y + 11) * L]), ACCENT)
		_spaced(c, "NEXT PAGE", Vector2(ex - 12, y + 1), 24, NAVY, HORIZONTAL_ALIGNMENT_RIGHT, 3.0)
	var n := page_count()
	for i in n:
		var d := Vector2(PAGE_W * 0.5 + (i - (n - 1) * 0.5) * 26.0, y) * L
		if i == _page:
			c.draw_circle(d, 7.0 * L, NAVY)
		else:
			c.draw_arc(d, 6.0 * L, 0.0, TAU, 20, NAVY, 2.0 * L)


# ── The left page: a good ───────────────────────────────────────────────────────

func _good_left(c: Control, good_id: String) -> void:
	var good: Dictionary = Catalog.get_good(good_id)
	if c != null:
		_running_head(c, "GOODS", str(good.get("category", "")).to_upper())
	var w := PAGE_W
	_feature(c, Rect2(M, 104, w - 2.0 * M, 520), "good", good_id, str(good.get("display_name", "")), Data.describe_good(good), Data.good_facts(good_id), 380.0, 150.0, "GOODS", NAVY, PAPER)
	var gx := w - M - 20.0 - 92.0
	if c != null:
		_fill(c, Rect2(gx, 174, 92, 92), PAPER)
		_stroke(c, Rect2(gx, 174, 92, 92), 2.5, NAVY)
		c.draw_texture_rect(GRAPH_OUTLINE, Rect2(Vector2(gx + 12, 186) * L, Vector2(68, 68) * L), false, NAVY)
	_left_hits.append({"name": "GoodsGraphLink", "tip": "Go to %s's Goods Graph" % str(good.get("display_name", "")), "rect": Rect2(gx, 174, 92, 92),
		"action": func() -> void:
			closed_requested.emit()
			MatchState.goods_graph_good_requested.emit(good_id)})
	var y := 654.0
	var makers := Data.makers(good_id)
	if not makers.is_empty():
		y = _plants_block(c, y, "BUILDINGS THAT MAKE IT", makers)
	var ins := Data.inputs_of(good_id)
	if not ins.is_empty():
		_pictures_block(c, y, "SEE ALSO, WHAT GOES INTO IT", ins.map(func(gid: String) -> Dictionary: return {"kind": "good", "id": gid, "name": Catalog.get_display_name(gid)}), NAVY)


## The thing's box: a tint across the page, its picture large at the left, its name in Bebas, what it is and its
## specification lines; a link line underlined. Paints when `c` is set and lists its targets either way.
func _feature(c: Control, r: Rect2, kind: String, id: String, title: String, line: String, facts: Array, px: float, size: float,
		bar_title: String, bar_colour: Color, bar_fg: Color) -> void:
	if c != null:
		_bar(c, r.position.x, r.position.y, r.size.x, bar_title, "", bar_colour, bar_fg)
	var box := Rect2(r.position.x, r.position.y + 50.0, r.size.x, r.size.y - 50.0)
	var tx := box.position.x + px + 54.0
	var tw := box.size.x - px - 90.0 - (112.0 if kind == "good" else 0.0)
	var title_lines := _wrap(BEBAS, int(size), title.to_upper(), tw, 1)
	var tsize := size
	while tsize > 72.0 and _str_w(BEBAS, int(tsize), title.to_upper()) > tw:
		tsize -= 4.0
	if _str_w(BEBAS, int(tsize), title.to_upper()) > tw:
		title_lines = _wrap(BEBAS, int(tsize), title.to_upper(), tw, 2)
	var ty := box.position.y + 34.0 + tsize * 0.45
	if c != null:
		_fill(c, box, TINT)
		var pic := Rect2(box.position.x + 20.0, box.position.y + (box.size.y - px) * 0.5, px, px)
		if kind == "good":
			_picture(c, id, pic)
		else:
			_symbol(c, id if kind == "building" else str(Catalog.get_recipe(id).get("building_id", "")), pic)
		for i in title_lines.size():
			_text(c, BEBAS, int(tsize), str(title_lines[i]), Vector2(tx - 4.0, ty + i * tsize * 0.92), NAVY)
	ty += (title_lines.size() - 1) * tsize * 0.92
	var ly := ty + tsize * 0.55 + 16.0
	if c != null:
		_text(c, PLEX, 24, line, Vector2(tx, ly), NAVY, HORIZONTAL_ALIGNMENT_LEFT, box.size.x - px - 90.0)
	var fy := ly + 50.0
	for i in facts.size():
		var f: Array = facts[i]
		var ry := fy + i * 42.0
		if c != null:
			_fill(c, Rect2(tx, ry + 21.0, box.size.x - px - 90.0, 1.0), RULE)
			_text(c, PLEX, 22, str(f[0]), Vector2(tx, ry), NAVY, HORIZONTAL_ALIGNMENT_LEFT, 160.0)
			var yes := str(f[1]) == "YES" or str(f[1]) == "NO"
			_text(c, BARLOW if yes else PLEX_SEMI, 24, str(f[1]), Vector2(tx + 170.0, ry), NAVY, HORIZONTAL_ALIGNMENT_LEFT, box.size.x - px - 270.0)
			if str(f[2]) != "":
				_fill(c, Rect2(tx + 170.0, ry + 14.0, _str_w(PLEX_SEMI, 24, str(f[1])), 2.0), NAVY)
		if str(f[2]) != "":
			var entry := str(f[2])
			_left_hits.append({"name": "Link_" + entry, "tip": "Mechanics, Price impact", "rect": Rect2(tx + 160.0, ry - 20.0, _str_w(PLEX_SEMI, 24, str(f[1])) + 20.0, 40.0),
				"action": func() -> void: open_view({"kind": "mechanic", "id": entry})})


## A section of building marks with their names and how many recipes they run: two to a row.
func _plants_block(c: Control, y: float, title: String, makers: Array) -> float:
	var w := PAGE_W - 2.0 * M
	if c != null:
		_bar(c, M, y, w, title, str(makers.size()), MUSTARD, NAVY)
	var px := 150.0 if makers.size() <= 2 else 96.0
	var per := 2
	var row_h := px + 30.0
	var shown := makers.slice(0, 4)
	for i in shown.size():
		var mk: Dictionary = shown[i]
		var bx := M + (i % per) * (w / per)
		var by := y + 66.0 + floorf(i / float(per)) * row_h
		var bw := w / per - 16.0
		if c != null:
			_symbol(c, str(mk.id), Rect2(bx + 10.0, by, px, px))
			_text(c, BARLOW, 30, str(Catalog.get_building(str(mk.id)).get("display_name", "")), Vector2(bx + px + 30.0, by + px * 0.5 - 18.0), NAVY, HORIZONTAL_ALIGNMENT_LEFT, bw - px - 40.0)
			var n := int(mk.get("count", 0))
			if n > 0:
				_text(c, PLEX, 22, "Makes it, %d %s" % [n, "recipe" if n == 1 else "recipes"], Vector2(bx + px + 30.0, by + px * 0.5 + 20.0), NAVY, HORIZONTAL_ALIGNMENT_LEFT, bw - px - 40.0)
		_left_hits.append({"name": "Maker_" + str(mk.id), "tip": str(Catalog.get_building(str(mk.id)).get("display_name", "")), "rect": Rect2(bx, by, bw, px),
			"action": _open("building", str(mk.id))})
	return y + 66.0 + ceilf(shown.size() / float(per)) * row_h + 20.0


## A section of pictures, four to a row, two rows at most; with quantities when the parts carry them.
func _pictures_block(c: Control, y: float, title: String, items: Array, colour: Color) -> float:
	var w := PAGE_W - 2.0 * M
	if c != null:
		_bar(c, M, y, w, title, str(items.size()), colour, PAPER if colour != MUSTARD else NAVY)
	var room := PAGE_H - 60.0 - (y + 66.0)
	var extra := 66.0 + (26.0 if not items.is_empty() and (items[0] as Dictionary).has("qty") else 0.0)
	var want := 2 if items.size() > 4 else 1
	# The pictures shrink, not below 72, so a second row of them fits.
	var px := clampf(room / want - extra, 72.0, 96.0)
	var row_h := px + extra
	var rows := clampi(int(room / row_h), 1, want)
	var shown := items.slice(0, rows * 4)
	var cw := w / 4.0
	for i in shown.size():
		var it: Dictionary = shown[i]
		var sx := M + (i % 4) * cw
		var sy := y + 66.0 + floorf(i / 4.0) * row_h
		var pic := Rect2(sx + (cw - px) * 0.5, sy, px, px)
		if c != null:
			if str(it.kind) == "building":
				_symbol(c, str(it.id), pic)
			else:
				_picture(c, str(it.id), pic)
			_text(c, BARLOW, 24, str(it.name), Vector2(sx + cw * 0.5, sy + px + 26.0), NAVY, HORIZONTAL_ALIGNMENT_CENTER, cw - 10.0)
			if it.has("qty"):
				_text(c, PLEX_SEMI, 21, "×%d" % int(it.qty), Vector2(sx + cw * 0.5, sy + px + 54.0), NAVY, HORIZONTAL_ALIGNMENT_CENTER, cw - 10.0)
		_left_hits.append({"name": "Picture_" + str(it.id), "tip": str(it.name), "rect": Rect2(sx, sy, cw, px + 40.0), "action": _open(str(it.kind), str(it.id))})
	return y + 66.0 + ceilf(shown.size() / 4.0) * row_h + 10.0


# ── The right page parts for each view ──────────────────────────────────────────

func _bar_part(title: String, count: String, colour: Color, fg := PAPER) -> Dictionary:
	return {"h": BAR_H, "bar": title, "count": count, "colour": colour, "fg": fg}


func _rows_parts(rows: Array) -> Array:
	return rows.map(func(row: Dictionary) -> Dictionary: return {"h": _row_height(row), "row": row})


func _good_parts(good_id: String) -> Array:
	var parts: Array = []
	var made := Data.made_by(good_id)
	parts.append(_bar_part("MADE BY", _count(made.size()), TEAL))
	if made.is_empty():
		parts.append({"h": ITEM_H, "item": {"kind": "note", "id": "none_made", "name": "Not made by any recipe", "note": "It comes from the market or the ground."}})
	parts.append_array(_rows_parts(made))
	var groups := Data.used_in_groups(good_id)
	parts.append(_bar_part("USED IN", _count(Data.used_in_count(good_id)), ACCENT))
	if groups.is_empty():
		parts.append({"h": ITEM_H, "item": {"kind": "note", "id": "none_used", "name": "Used in no recipe", "note": "It is made to be sold."}})
	for g: Dictionary in groups:
		parts.append({"h": GROUP_H, "head": true, "good": str(g.good), "head_name": str(g.name)})
		parts.append_array(_rows_parts(g.rows))
	return parts


func _building_parts(building_id: String) -> Array:
	var rows := Data.building_recipes(building_id)
	var parts: Array = [_bar_part("RECIPES IT RUNS", _count(rows.size()), TEAL)]
	if rows.is_empty():
		parts.append({"h": ITEM_H, "item": {"kind": "note", "id": "none", "name": "Runs no recipe", "note": "It serves the buildings around it."}})
	parts.append_array(_rows_parts(rows))
	return parts


func _recipe_parts(recipe_id: String) -> Array:
	var recipe := Catalog.get_recipe(recipe_id)
	var parts: Array = [_bar_part("THE RECIPE", "", TEAL)]
	parts.append({"h": _row_height(Data.row_for(recipe)), "row": Data.row_for(recipe)})
	var rivals := Data.rival_recipes(recipe)
	if not rivals.is_empty():
		parts.append(_bar_part("OTHER WAYS TO MAKE %s" % Catalog.get_display_name(str(recipe.get("output_good_id", ""))).to_upper(), _count(rivals.size()), ACCENT))
		parts.append_array(_rows_parts(rivals))
	var siblings := Data.sibling_recipes(recipe)
	if not siblings.is_empty():
		parts.append(_bar_part("ALSO IN THE %s" % str(Catalog.get_building(str(recipe.get("building_id", ""))).get("display_name", "")).to_upper(), _count(siblings.size()), MUSTARD, NAVY))
		parts.append_array(_rows_parts(siblings))
	return parts


func _index_parts(query: String) -> Array:
	var found := Data.look_up(query)
	var best := Data.best_match(found)
	var parts: Array = []
	if not (found.recipes as Array).is_empty():
		parts.append(_bar_part("RECIPES", str((found.recipes as Array).size()), TEAL))
		parts.append_array(_rows_parts(found.recipes))
	for pair in [["goods", "GOODS", NAVY, PAPER], ["buildings", "BUILDINGS", MUSTARD, NAVY], ["tiles", "TILES", TEAL, PAPER], ["mechanics", "MECHANICS", NAVY, PAPER]]:
		var list: Array = (found[pair[0]] as Array).filter(func(it: Dictionary) -> bool: return not (str(it.kind) == str(best.get("kind", "")) and str(it.id) == str(best.get("id", ""))))
		if list.is_empty():
			continue
		parts.append(_bar_part(pair[1], str(list.size()), pair[2], pair[3]))
		for it: Dictionary in list:
			var item := it.duplicate()
			if not item.has("note"):
				item["note"] = _item_note(item)
			parts.append({"h": ITEM_H, "item": item})
	if parts.is_empty():
		parts.append({"h": ITEM_H, "item": {"kind": "note", "id": "nothing", "name": "Nothing else matches", "note": "Try fewer letters."}})
	return parts


func _item_note(it: Dictionary) -> String:
	match str(it.kind):
		"good": return Data.describe_good(Catalog.get_good(str(it.id)))
		"building": return Data.describe_building(Catalog.get_building(str(it.id)))
		"mechanic": return "How it works."
	return ""


## The contents' right page: a section's index. Goods and buildings as pictures by category, recipes by category,
## mechanics a line each.
func _section_parts(section: String) -> Array:
	var parts: Array = []
	match section:
		"goods", "buildings":
			var by_cat: Dictionary = {}
			var cats: Array = []
			var list: Array = Data.goods() if section == "goods" else Data.buildings()
			for x: Dictionary in list:
				var cat := str(x.get("category", "")).replace("_", " ").to_upper()
				if cat == "":
					cat = "OTHER"
				if not by_cat.has(cat):
					by_cat[cat] = []
					cats.append(cat)
				(by_cat[cat] as Array).append({"kind": "good" if section == "goods" else "building", "id": str(x.get("id", "")), "name": str(x.get("display_name", ""))})
			cats.sort()
			for cat: String in cats:
				var items: Array = by_cat[cat]
				items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.name) < str(b.name))
				parts.append(_bar_part(cat, str(items.size()), NAVY if section == "goods" else MUSTARD, PAPER if section == "goods" else NAVY))
				for i in range(0, items.size(), 4):
					parts.append({"h": TILE_ROW_H, "tiles": items.slice(i, i + 4)})
		"recipes":
			var by_cat: Dictionary = {}
			var cats: Array = []
			for r: Dictionary in Data.recipes():
				var cat := str(r.get("recipe_type", "")).to_upper()
				if cat == "":
					cat = "OTHER"
				if not by_cat.has(cat):
					by_cat[cat] = []
					cats.append(cat)
				(by_cat[cat] as Array).append(Data.row_for(r))
			cats.sort()
			for cat: String in cats:
				parts.append(_bar_part(cat, str((by_cat[cat] as Array).size()), TEAL))
				parts.append_array(_rows_parts(by_cat[cat]))
		"mechanics":
			parts.append(_bar_part("MECHANICS", str(Data.mechanics().size()), NAVY))
			for m: Dictionary in Data.mechanics():
				parts.append({"h": ITEM_H, "item": {"kind": "mechanic", "id": str(m.id), "name": str(m.title), "note": "How it works."}})
	return parts


func _count(n: int) -> String:
	return "%d %s" % [n, "RECIPE" if n == 1 else "RECIPES"]


# ── The left page for the other views ───────────────────────────────────────────

func _building_left(c: Control, building_id: String) -> void:
	var b: Dictionary = Catalog.get_building(building_id)
	if c != null:
		_running_head(c, "BUILDINGS", str(b.get("category", "")).to_upper())
	_feature(c, Rect2(M, 104, PAGE_W - 2.0 * M, 520), "building", building_id, str(b.get("display_name", "")), Data.describe_building(b), Data.building_facts(building_id), 340.0, 130.0, "BUILDINGS", MUSTARD, NAVY)
	var y := 654.0
	var mats := Data.building_materials(building_id)
	if not mats.is_empty():
		y = _pictures_block(c, y, "BUILT FROM", mats.map(func(p: Array) -> Dictionary: return {"kind": "good", "id": str(p[0]), "name": Catalog.get_display_name(str(p[0])), "qty": int(p[1])}), NAVY)
	var outs := Data.building_outputs(building_id)
	if not outs.is_empty() and y < PAGE_H - 300.0:
		_pictures_block(c, y, "WHAT IT MAKES", outs.map(func(gid: String) -> Dictionary: return {"kind": "good", "id": gid, "name": Catalog.get_display_name(gid)}), ACCENT)


func _recipe_left(c: Control, recipe_id: String) -> void:
	var recipe := Catalog.get_recipe(recipe_id)
	if c != null:
		_running_head(c, "RECIPES", str(recipe.get("recipe_type", "")).to_upper())
	_feature(c, Rect2(M, 104, PAGE_W - 2.0 * M, 520), "recipe", recipe_id, str(recipe.get("display_name", "")), Data.describe_recipe(recipe), Data.recipe_facts(recipe), 300.0, 110.0, "RECIPES", TEAL, PAPER)
	var row := Data.row_for(recipe)
	var y := 654.0
	if not (row.inputs as Array).is_empty():
		y = _pictures_block(c, y, "WHAT GOES IN", (row.inputs as Array).map(func(p: Array) -> Dictionary: return {"kind": "good", "id": str(p[0]), "name": Catalog.get_display_name(str(p[0])), "qty": int(p[1])}), NAVY)
	if not (row.outputs as Array).is_empty() and y < PAGE_H - 300.0:
		_pictures_block(c, y, "WHAT COMES OUT", (row.outputs as Array).map(func(p: Array) -> Dictionary: return {"kind": "good", "id": str(p[0]), "name": Catalog.get_display_name(str(p[0])), "qty": int(p[1])}), ACCENT)
	var bid := str(recipe.get("building_id", ""))
	_left_hits.append({"name": "Plant_" + bid, "tip": str(Catalog.get_building(bid).get("display_name", "")), "rect": Rect2(M + 20.0, 154.0 + 50.0, 300.0, 400.0), "action": _open("building", bid)})


## The index's left page: how many entries the look up found, its best match as the thing's box, and, for a good,
## the buildings that make it and what goes into it; for a building, what it makes.
func _index_left(c: Control, query: String) -> void:
	if c != null:
		_running_head(c, "INDEX", "LOOKED UP: %s" % query)
	var found := Data.look_up(query)
	var n := Data.entry_count(found)
	if c != null:
		_text(c, BARLOW, 30, "%d %s" % [n, "ENTRY" if n == 1 else "ENTRIES"], Vector2(M, 128), ACCENT)
	var best := Data.best_match(found)
	if best.is_empty():
		if c != null:
			_text(c, PLEX, 26, "No good or building matches." if n > 0 else "Nothing matches.", Vector2(M, 220), NAVY, HORIZONTAL_ALIGNMENT_LEFT, PAGE_W - 2.0 * M)
		return
	var kind := str(best.kind)
	var id := str(best.id)
	var box := Rect2(M, 170, PAGE_W - 2.0 * M, 380)
	if kind == "good":
		var good := Catalog.get_good(id)
		_feature(c, box, "good", id, str(good.get("display_name", "")), Data.describe_good(good), [], 290.0, 120.0, "GOODS", NAVY, PAPER)
	else:
		var b := Catalog.get_building(id)
		_feature(c, box, "building", id, str(b.get("display_name", "")), Data.describe_building(b), [], 290.0, 110.0, "BUILDINGS", MUSTARD, NAVY)
	if c != null:
		var name_w := _str_w(BEBAS, 120, str(best.name).to_upper())
		var tag := Rect2(minf(M + 290.0 + 54.0 + name_w + 30.0, PAGE_W - M - 180.0), 288.0, 160.0, 40.0)
		_fill(c, tag, ACCENT)
		_spaced(c, "BEST MATCH", Vector2(tag.position.x + 14.0, tag.get_center().y + 1.0), 20, PAPER, HORIZONTAL_ALIGNMENT_LEFT, 2.0)
	_left_hits.append({"name": "BestMatch", "key": "best", "rect": Rect2(M, 220, PAGE_W - 2.0 * M, 330), "action": _open(kind, id)})
	var y := 590.0
	if kind == "good":
		var makers := Data.makers(id)
		if not makers.is_empty():
			y = _plants_block(c, y, "BUILDINGS THAT MAKE IT", makers)
		var ins := Data.inputs_of(id)
		if not ins.is_empty() and y < PAGE_H - 300.0:
			_pictures_block(c, y, "SEE ALSO, WHAT GOES INTO IT", ins.map(func(gid: String) -> Dictionary: return {"kind": "good", "id": gid, "name": Catalog.get_display_name(gid)}), NAVY)
	else:
		var outs := Data.building_outputs(id)
		if not outs.is_empty():
			_pictures_block(c, y, "WHAT IT MAKES", outs.map(func(gid: String) -> Dictionary: return {"kind": "good", "id": gid, "name": Catalog.get_display_name(gid)}), ACCENT)


## The contents: the four sections, each a coloured band with its count and a line on what it holds.
func _contents_left(c: Control) -> void:
	if c != null:
		_running_head(c, "CONTENTS", "THE CATALOGUE")
		_text(c, BEBAS, 120, "THE CATALOGUE", Vector2(M - 4.0, 200), NAVY, HORIZONTAL_ALIGNMENT_LEFT, PAGE_W - 2.0 * M)
		_text(c, PLEX, 24, "Every good, recipe and building in the game, and how it works.", Vector2(M, 290), NAVY, HORIZONTAL_ALIGNMENT_LEFT, PAGE_W - 2.0 * M)
	var lines := {
		"goods": [Data.goods().size(), "What is made, bought and sold."],
		"recipes": [Data.recipes().size(), "How each good is made, and from what."],
		"buildings": [Data.buildings().size(), "Where the recipes run."],
		"mechanics": [Data.mechanics().size(), "How the market, power and land behave."],
	}
	var y := 360.0
	for sec: String in Data.SECTIONS:
		var locked := sec == "mechanics" and Data.mechanics_locked()
		var colour: Color = TAB_COLOURS[sec]
		var fg := NAVY if sec == "buildings" else PAPER
		var r := Rect2(M, y, PAGE_W - 2.0 * M, 190)
		if c != null:
			_fill(c, r, TINT if _hover == "section:" + sec else PAPER)
			_stroke(c, r, 2.0, NAVY)
			_bar(c, r.position.x, r.position.y, r.size.x, Data.SECTION_TITLES[sec], "" if locked else str(lines[sec][0]), Color(colour, 0.5) if locked else colour, fg)
			_text(c, PLEX, 24, "Not available in the Demo." if locked else str(lines[sec][1]), Vector2(M + 24.0, y + 104.0), NAVY, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 48.0)
			if not locked:
				_spaced(c, "OPEN", Vector2(r.end.x - 40.0, y + 150.0), 22, NAVY, HORIZONTAL_ALIGNMENT_RIGHT, 3.0)
				c.draw_colored_polygon(PackedVector2Array([Vector2(r.end.x - 30.0, y + 140.0) * L, Vector2(r.end.x - 16.0, y + 150.0) * L, Vector2(r.end.x - 30.0, y + 160.0) * L]), ACCENT)
		if not locked:
			var s := sec
			_left_hits.append({"name": "Section_" + sec, "key": "section:" + sec, "rect": r, "action": func() -> void: open_section(s)})
		y += 214.0


# ── A mechanic: its words flow down the left page, then the right, a spread at a time ─────

func _mechanic_title(entry_id: String) -> String:
	for m: Dictionary in Data.mechanics():
		if str(m.id) == entry_id:
			return str(m.title)
	return ""


func _mechanic_body(entry_id: String) -> String:
	return str(_overlay.call("_mechanic_body", entry_id)) if _overlay != null and _overlay.has_method("_mechanic_body") else ""


const TEXT_W := PAGE_W - 2.0 * M
const PASSAGE_GAP := 22.0


## Where a mechanic's words start on the left page: under its title, one line or two.
func _text_top(entry_id: String) -> float:
	return 230.0 + (_wrap(BEBAS, 104, _mechanic_title(entry_id).to_upper(), PAGE_W - 2.0 * M, 2).size() - 1) * 96.0 + 90.0

func _mechanic_left(c: Control, entry_id: String) -> void:
	if c != null:
		_running_head(c, "MECHANICS", "HOW IT WORKS")
		_bar(c, M, 104, PAGE_W - 2.0 * M, "MECHANICS", "", NAVY, PAPER)
		var lines := _wrap(BEBAS, 104, _mechanic_title(entry_id).to_upper(), PAGE_W - 2.0 * M, 2)
		for i in lines.size():
			_text(c, BEBAS, 104, str(lines[i]), Vector2(M - 4.0, 230.0 + i * 96.0), NAVY)
	if _page < _left_pages.size():
		_place_passages(_left, _left_pages[_page][0], _text_top(entry_id), c == null)


## Splits the body into paragraphs and lays them down the spreads: the left page under the title, then the right.
func _flow_mechanic(entry_id: String) -> void:
	_pages = []
	var paras := _mechanic_body(entry_id).split("\n\n", false)
	var probe := _passage("")
	_book.add_child(probe)
	var spreads: Array = []
	var cur := [[], []]
	var side := 0
	var y := 0.0
	var rooms := [PAGE_H - 80.0 - _text_top(entry_id), ROOM]
	for p: String in paras:
		probe.text = p.strip_edges()
		var h := probe.get_content_height() / L + PASSAGE_GAP
		# The gap goes between passages: the last one on a page needs only its own height.
		if y > 0.0 and y + h - PASSAGE_GAP > float(rooms[side]):
			side += 1
			y = 0.0
			if side > 1:
				spreads.append(cur)
				cur = [[], []]
				side = 0
		(cur[side] as Array).append({"text": p.strip_edges(), "h": h})
		y += h
	spreads.append(cur)
	probe.queue_free()
	_left_pages = spreads


func _passage(text: String) -> RichTextLabel:
	var t := RichTextLabel.new()
	t.bbcode_enabled = true
	t.fit_content = true
	t.scroll_active = false
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.add_theme_font_override("normal_font", PLEX)
	t.add_theme_font_override("bold_font", PLEX_SEMI)
	t.add_theme_font_size_override("normal_font_size", 14)
	t.add_theme_font_size_override("bold_font_size", 14)
	t.add_theme_color_override("default_color", NAVY)
	t.add_theme_constant_override("line_separation", 3)
	t.size = Vector2(TEXT_W * L, 10)
	t.custom_minimum_size = Vector2(TEXT_W * L, 0)
	t.text = text
	return t


## The passages as text on the page; placed once a render, after the page is cleared.
func _place_passages(page: Control, passages: Array, top: float, place: bool) -> void:
	if not place:
		return
	var y := top
	for p: Dictionary in passages:
		var t := _passage(str(p.text))
		t.position = Vector2(M, y) * L
		page.add_child(t)
		y += float(p.h)


# ── Print helpers (layout px in, logical px drawn) ──────────────────────────────

func _px(size: float) -> int:
	return maxi(MIN_PX, int(round(size * L)))


func _str_w(font: Font, size: int, text: String) -> float:
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _px(size)).x / L


## Navy print on paper, its middle at `at.y`, shrunk to fit `max_w` when given; a faint light shadow.
func _text(c: CanvasItem, font: Font, size: int, text: String, at: Vector2, colour: Color = NAVY,
		align := HORIZONTAL_ALIGNMENT_LEFT, max_w := -1.0) -> void:
	if text == "" or c == null:
		return
	var fs := _px(size)
	if max_w > 0.0:
		fs = maxi(MIN_PX, Plate._fit(font, text, fs, max_w * L))
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var x := at.x * L - (tw * 0.5 if align == HORIZONTAL_ALIGNMENT_CENTER else (tw if align == HORIZONTAL_ALIGNMENT_RIGHT else 0.0))
	var base := Vector2(x, at.y * L + (font.get_ascent(fs) - font.get_descent(fs)) * 0.5)
	if colour == NAVY:
		c.draw_string(font, base + Vector2(0.5, 0.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, INK_SHADOW)
	c.draw_string(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, colour)


## White print with its dark shadow, for the header's steel (logical px in).
func _white(c: CanvasItem, font: Font, px: int, text: String, at: Vector2, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var x := at.x - (tw * 0.5 if align == HORIZONTAL_ALIGNMENT_CENTER else (tw if align == HORIZONTAL_ALIGNMENT_RIGHT else 0.0))
	var base := Vector2(x, at.y + (font.get_ascent(px) - font.get_descent(px)) * 0.5)
	c.draw_string(font, base + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, WHITE_SHADOW)
	c.draw_string(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, DS.PALETTE["TEXT"])


## Letterspaced capitals (Barlow Bold), as the catalogue's running heads and bars print them.
func _spaced(c: CanvasItem, text: String, at: Vector2, size: int, colour: Color, align := HORIZONTAL_ALIGNMENT_LEFT, gap := 3.0, max_w := -1.0) -> void:
	if c == null:
		return
	var key := "%d" % int(round(gap * L * 10.0))
	if not _spaced_cache.has(key):
		var fv := FontVariation.new()
		fv.base_font = BARLOW
		fv.spacing_glyph = int(round(gap * L))
		_spaced_cache[key] = fv
	_text(c, _spaced_cache[key], size, text, at, colour, align, max_w)


func _running_head(c: Control, left: String, right: String) -> void:
	if c == null:
		return
	_spaced(c, left, Vector2(M, 50), 22, NAVY, HORIZONTAL_ALIGNMENT_LEFT, 3.0, PAGE_W * 0.5 - M)
	_spaced(c, right, Vector2(PAGE_W - M, 50), 22, NAVY, HORIZONTAL_ALIGNMENT_RIGHT, 3.0, PAGE_W * 0.5 - M)
	_fill(c, Rect2(M, 70, PAGE_W - 2.0 * M, 4), NAVY)
	_fill(c, Rect2(M, 79, PAGE_W - 2.0 * M, 1.5), NAVY)


## A section's bar: reversed capitals on a band of colour, its count at the right.
func _bar(c: Control, x: float, y: float, w: float, title: String, count: String, colour: Color, fg: Color) -> void:
	if c == null:
		return
	_fill(c, Rect2(x, y, w, 50), colour)
	_spaced(c, title, Vector2(x + 16.0, y + 26.0), 26, fg, HORIZONTAL_ALIGNMENT_LEFT, 3.0, w - 200.0)
	if count != "":
		_spaced(c, count, Vector2(x + w - 16.0, y + 26.0), 22, fg, HORIZONTAL_ALIGNMENT_RIGHT, 2.0)


func _fill(c: CanvasItem, r: Rect2, colour: Color) -> void:
	c.draw_rect(Rect2(r.position * L, r.size * L), colour, true)


func _stroke(c: CanvasItem, r: Rect2, width: float, colour: Color) -> void:
	var w := width * L
	c.draw_rect(Rect2(r.position * L + Vector2.ONE * w * 0.5, r.size * L - Vector2.ONE * w), colour, false, w)


func _star(c: CanvasItem, at: Vector2, s: float) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var rr := s if i % 2 == 0 else s * 0.42
		var a := -PI * 0.5 + i * PI / 5.0
		pts.append((at + Vector2(cos(a), sin(a)) * rr) * L)
	c.draw_colored_polygon(pts, ACCENT)


## A good's picture fitted in its square; a good with no picture yet gets its name in a ruled box.
func _picture(c: CanvasItem, good_id: String, r: Rect2) -> void:
	if c == null or good_id == "":
		return
	var internal := Catalog.get_internal_name(good_id)
	var tex := GoodIcons.texture_for_size(good_id, internal, r.size.x * L)
	if tex == null:
		_stroke(c, r.grow(-4.0), 2.0, NAVY)
		_text(c, BARLOW, int(r.size.x * 0.24), Catalog.get_display_name(good_id).split(" ")[0].to_upper(), r.get_center(), NAVY, HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 14.0)
		return
	var ts := tex.get_size()
	var k := minf(r.size.x / ts.x, r.size.y / ts.y)
	var s := ts * k
	c.draw_texture_rect(tex, Rect2((r.get_center() - s * 0.5) * L, s * L), false)


## A building's mark in navy, fitted in its square.
func _symbol(c: CanvasItem, building_id: String, r: Rect2) -> void:
	if c == null or building_id == "":
		return
	var tex := BuildingIcon.clean_texture(building_id, str(Catalog.get_building(building_id).get("internal_name", "")))
	if tex == null:
		return
	var ts := tex.get_size()
	var k := minf(r.size.x / ts.x, r.size.y / ts.y)
	var s := ts * k
	c.draw_texture_rect(tex, Rect2((r.get_center() - s * 0.5) * L, s * L), false, NAVY)


## Words broken into at most `max_lines` lines of `max_w`; the last keeps what is left (the print shrinks it).
func _wrap(font: Font, size: int, text: String, max_w: float, max_lines: int) -> Array:
	var words := text.split(" ", false)
	var lines: Array = []
	var line := ""
	for wd: String in words:
		var t := wd if line == "" else line + " " + wd
		if line != "" and _str_w(font, size, t) > max_w and lines.size() < max_lines - 1:
			lines.append(line)
			line = wd
		else:
			line = t
	if line != "":
		lines.append(line)
	return lines
