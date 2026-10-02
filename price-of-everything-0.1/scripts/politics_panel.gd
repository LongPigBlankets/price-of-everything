extends PanelContainer
## The Politics panel: the decarbonisation arc as a plain list of what has already happened.
##
## It reports NOTHING the player has not already been told — every entry here also arrived as
## a news item, a blocking notice or a flyout when it happened. The point is that those are
## easy to miss and impossible to re-read: by turn 150 a player who skimmed the carbon-tax
## notice has no way back to it. So this is a record, not a source, and it stays deliberately
## small (owner 2026-08-29): the election, the levy's three beats, and the subsidy's two.
##
## Everything is DERIVED from PolicyState's beats rather than stored, so it cannot drift from
## the schedule that actually drives the sim, and it works on either timeline (the demo runs
## the same arc ~30 turns earlier — see PolicyState.TIMELINES).
##
## Before the election there is nothing to show, and the panel says so rather than opening
## empty. Read-only against the sim (CLAUDE.md #5).

signal close_requested

const UIHelpers := preload("res://scripts/ui_helpers.gd")
const GoodIcons := preload("res://scripts/good_icons.gd")
# The DS2 look (UiPrefs.use_politics_ds2): the ledger's shell and the kit's shared parts.
const LedgerV3 := preload("res://scripts/ledger_v3/ledger_v3.gd")
const Parts := preload("res://scripts/ds2/parts.gd")
const Metrics := preload("res://scripts/ds2/metrics.gd")
const LampOverlay := preload("res://scripts/ds2/lamp_overlay.gd")
const Nine := preload("res://scripts/bdp_v3_nine.gd")
const Title := preload("res://scripts/bdp_v3_title.gd")
const Key := preload("res://scripts/bdp_v3_key.gd")
const Scroll := preload("res://scripts/bdp_v3_scroll.gd")

# Tall enough for the whole six-beat record without scrolling at 1080p — the panel exists to
# be read in one go, and a record that needs scrolling to reach the subsidy defeats that.
const PANEL_SIZE := Vector2(560, 720)
const HEADER_HEIGHT := 56.0
const ICON_BOX := 46.0
const ROW_GAP := 10

## The gavel the bottom menu already uses for this panel — a political act, not an
## industrial one.
const GAVEL_ICON := "res://assets/icons/ui_icons/alt/politics.png"
## DS2: the panel's size, and the title's size on an event's module.
const DS2_SIZE := Vector2(640, 720)
const DS2_TITLE_PX := 16
const DS2_EMPTY := "No political events yet."
const DS2_INK := Color("#0b2340")
## DS2, the courtroom (render set `court`, tools/button_mockup/cluster.html): the oak wall in its moulded frame at
## the panel's size, the bar of the court (a rail of turned balusters) under the title, a pad of dark leather with a
## brass stud in each corner for an event and a brass plate for its turn. From layout.json, in layout px: each render's shadow room, the wall's
## frame, the rail's height, the 9-slices' corners.
const COURT_WALL: Texture2D = preload("res://assets/ui/bdp_v3/court_backing.png")
const COURT_RAIL: Texture2D = preload("res://assets/ui/bdp_v3/court_rail.png")
const COURT_PANEL: Texture2D = preload("res://assets/ui/bdp_v3/court_panel.png")
const COURT_PLATE: Texture2D = preload("res://assets/ui/bdp_v3/court_plate.png")
const CAPTURE_SCALE := 1.875
const TEXELS_PER_PIXEL := 2.0
const WALL_MARGIN := 24.0
const WALL_FRAME := 30.0
const RAIL_MARGIN := 18.0
const RAIL_H := 112.0
const PANEL_MARGIN := 16.0
const PANEL_CORNER := 34.0
const PLATE_MARGIN := 8.0
const PLATE_CORNER := 14.0
## The plate's print: the brass plates' dark ink.
const PLATE_INK := Color("#2b170d")
const PLATE_PX := 14
## DS2: the rows shown before the record scrolls, the gap between rows, and the wall's 9-slice corner (its shadow
## room, its frame and the frame's bead), so the wall follows the panel's height with its frame kept true.
const MAX_ROWS := 5
const ROW_GAP_DS2 := 10
const WALL_CORNER := 60.0
## The record's least height, so a short record leaves wall under it and the wall's sides are never squeezed.
const MIN_LIST_H := 330.0

var _list: VBoxContainer = null
var _empty_label: Label = null
var _dragging := false
var _drag_offset := Vector2.ZERO
## Whether the DS2 look is built, and the size the panel is built at.
var _ds2 := false
var _panel_size := PANEL_SIZE
var _scroll: ScrollContainer = null

func _ready() -> void:
	name = "PoliticsPanel"
	if DS and DS.theme:
		theme = DS.theme
	theme_type_variation = &"PanelContainer"
	_build_look()
	_centre_in_viewport()
	UiPrefs.politics_ds2_changed.connect(func(_on: bool) -> void: _build_look())
	# The arc advances on turn resolution, so a panel left open stays current.
	TurnManager.turn_resolution_completed.connect(_refresh)
	visibility_changed.connect(func() -> void:
		if visible:
			_refresh())


func _centre_in_viewport() -> void:
	var vp := get_viewport_rect().size
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	offset_left = maxf(0.0, (vp.x - _panel_size.x) / 2.0)
	offset_top = maxf(0.0, (vp.y - _panel_size.y) / 2.0)
	offset_right = offset_left + _panel_size.x
	offset_bottom = offset_top + _panel_size.y


# ── Look: v2, or DS2 behind UiPrefs.use_politics_ds2 ─────────────────────────────────────
## Builds the panel in the look the switch asks for, taking down the other first. It stays where it is.
func _build_look() -> void:
	LampOverlay.detach(self)
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_list = null
	_scroll = null
	_ds2 = UiPrefs.use_politics_ds2
	_panel_size = DS2_SIZE if _ds2 else PANEL_SIZE
	custom_minimum_size = _panel_size
	size = _panel_size
	if _ds2:
		_build_ds2()
		# The lamp over the whole panel (docs/ds2-theme.md §4).
		LampOverlay.attach(self)
	else:
		add_theme_stylebox_override("panel", preload("res://scripts/pipe_frame.gd").dark_brown_stylebox(8.0))
		_build()


## DS2, a courtroom: the oak wall in its moulded frame, the raised title and the Close key, the bar of the
## court (a rail of turned balusters), then the record on leather pads, an event a pad.
func _build_ds2() -> void:
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var wall := Control.new()
	wall.name = "CourtWall"
	wall.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wall.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	wall.draw.connect(func() -> void:
		Nine.paint(wall, COURT_WALL, Rect2(Vector2.ZERO, wall.size).grow(WALL_MARGIN / CAPTURE_SCALE),
			(WALL_MARGIN + WALL_CORNER) * TEXELS_PER_PIXEL / CAPTURE_SCALE))
	add_child(wall)
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, LedgerV3.CONTENT_MARGIN)
	add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	margin.add_child(layout)

	var header := HBoxContainer.new()
	header.name = "PoliticsTitleRow"
	header.add_theme_constant_override("separation", 12)
	header.mouse_filter = Control.MOUSE_FILTER_STOP
	header.mouse_default_cursor_shape = Control.CURSOR_MOVE
	header.gui_input.connect(_on_header_input)
	layout.add_child(header)
	var title: Control = Title.new()
	title.call("set_text", "Politics")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(title)
	var close: TextureButton = Key.make("close", Title.line_height())
	close.name = "CloseKey"
	close.pressed.connect(func() -> void: close_requested.emit())
	header.add_child(close)

	# The bar of the court, from one side of the wall's frame to the other.
	var rail := Control.new()
	rail.name = "CourtRail"
	rail.custom_minimum_size.y = RAIL_H / CAPTURE_SCALE
	rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rail.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var reach := float(LedgerV3.CONTENT_MARGIN) - WALL_FRAME / CAPTURE_SCALE - 4.0
	rail.draw.connect(func() -> void:
		rail.draw_texture_rect(COURT_RAIL, Rect2(Vector2.ZERO, rail.size).grow_individual(reach, 0, reach, 0).grow(RAIL_MARGIN / CAPTURE_SCALE), false))
	layout.add_child(rail)

	var scroll := ScrollContainer.new()
	scroll.name = "PoliticsScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	Scroll.apply(scroll, true)
	layout.add_child(scroll)
	_scroll = scroll
	_list = VBoxContainer.new()
	_list.name = "PoliticsCase"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", ROW_GAP_DS2)
	scroll.add_child(_list)
	_refresh()


## DS2: the panel is as tall as its rows, up to MAX_ROWS of them. Past that the record scrolls on the steel rail,
## the first MAX_ROWS in view. The rows' heights follow their wrapped words, so they are read once laid out.
func _fit_rows() -> void:
	for _i in 2:
		if not is_inside_tree():
			return
		await get_tree().process_frame
	if not _ds2 or _scroll == null or not is_instance_valid(_scroll) or _list == null:
		return
	var rows := _list.get_child_count()
	var shown := mini(MAX_ROWS, rows)
	var h := float(ROW_GAP_DS2 * maxi(0, shown - 1))
	for i in shown:
		h += (_list.get_child(i) as Control).get_combined_minimum_size().y
	_scroll.custom_minimum_size.y = maxf(h, MIN_LIST_H)
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if rows > MAX_ROWS else ScrollContainer.SCROLL_MODE_SHOW_NEVER
	custom_minimum_size = Vector2(DS2_SIZE.x, 0)
	size = Vector2(DS2_SIZE.x, 0)


## DS2: an event's row, a stitched pad of dark leather with a brass stud in each corner (the court's 9-slice),
## its parts in one row inside.
func _oak_panel(panel_name: String) -> PanelContainer:
	var m := PanelContainer.new()
	m.name = panel_name
	var pad := StyleBoxEmpty.new()
	pad.content_margin_left = 18
	pad.content_margin_right = 18
	pad.content_margin_top = 14
	pad.content_margin_bottom = 14
	m.add_theme_stylebox_override("panel", pad)
	m.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	m.draw.connect(func() -> void:
		Nine.paint(m, COURT_PANEL, Rect2(Vector2.ZERO, m.size).grow(PANEL_MARGIN / CAPTURE_SCALE),
			(PANEL_MARGIN + PANEL_CORNER) * TEXELS_PER_PIXEL / CAPTURE_SCALE))
	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(row)
	return m


## DS2: the turn an event happened, engraved on a small brass plate.
func _turn_plate(turn: int) -> Control:
	var plate := PanelContainer.new()
	plate.name = "Turn"
	plate.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var pad := StyleBoxEmpty.new()
	pad.content_margin_left = 14
	pad.content_margin_right = 14
	pad.content_margin_top = 2
	pad.content_margin_bottom = 3
	plate.add_theme_stylebox_override("panel", pad)
	plate.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	plate.draw.connect(func() -> void:
		Nine.paint(plate, COURT_PLATE, Rect2(Vector2.ZERO, plate.size).grow(PLATE_MARGIN / CAPTURE_SCALE),
			(PLATE_MARGIN + PLATE_CORNER) * TEXELS_PER_PIXEL / CAPTURE_SCALE))
	var l := Label.new()
	l.name = "Print"
	l.text = "TURN %d" % turn
	l.add_theme_font_override("font", preload("res://scripts/bdp_v3_plate.gd").FONT_SEMI)
	l.add_theme_font_size_override("font_size", PLATE_PX)
	l.add_theme_color_override("font_color", PLATE_INK)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(l)
	plate.set_meta("text", l.text)
	return plate


## DS2: one event's leather pad. Its icon on a cream tile in a well, its title over its words, and the turn it
## happened on a brass plate.
func _entry_module(entry: Dictionary, index: int) -> Control:
	var m := _oak_panel("PoliticsEvent_%d" % index)
	m.custom_minimum_size.y = Metrics.CARD_H
	var row := m.get_child(0) as HBoxContainer
	var well := _ds2_icon(str(entry.get("icon", "")))
	well.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(well)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(head)
	var title := Parts.body(str(entry.get("title", "")))
	title.name = "Title"
	title.add_theme_font_override("font", Parts.FONT_TITLE)
	title.add_theme_font_size_override("font_size", DS2_TITLE_PX)
	head.add_child(title)
	if int(entry.get("turn", 0)) > 0:
		head.add_child(_turn_plate(int(entry.turn)))
	var body := Parts.body(str(entry.get("body", "")))
	body.name = "Body"
	col.add_child(body)
	return m


## DS2: an event's icon on the goods' cream tile under the icon well's frame.
func _ds2_icon(kind: String) -> Control:
	var px := float(Metrics.GOOD_ICON)
	var good := "power" if kind == "power" else ("coal" if kind == "coal_banned" else "")
	var holder: Control
	if good != "":
		holder = Parts.good_in_well(str(Catalog.get_good_by_internal_name(good).get("id", "")), -1, "")
	else:
		holder = Control.new()
		holder.custom_minimum_size = Vector2(px, px)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		var tile := Panel.new()
		var paper := StyleBoxFlat.new()
		paper.bg_color = UIHelpers.PILL_PAPER
		paper.set_corner_radius_all(roundi(Parts.WELL_RADIUS))
		tile.add_theme_stylebox_override("panel", paper)
		tile.set_anchors_preset(Control.PRESET_FULL_RECT)
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(tile)
		var art := TextureRect.new()
		art.texture = load(GAVEL_ICON) as Texture2D
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		var inset := roundi(px * 0.12)
		art.offset_left = inset
		art.offset_top = inset
		art.offset_right = -inset
		art.offset_bottom = -inset
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# The gavel is drawn in white for the navy menu. On the cream tile it is printed in the keys' navy.
		art.self_modulate = DS2_INK
		holder.add_child(art)
		var frame := Control.new()
		frame.set_anchors_preset(Control.PRESET_FULL_RECT)
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.draw.connect(func() -> void:
			Nine.paint(frame, Parts.WELL, Rect2(Vector2.ZERO, frame.size).grow(Parts.WELL_REACH), Parts.WELL_CORNER))
		frame.resized.connect(frame.queue_redraw)
		holder.add_child(frame)
	if kind == "coal_banned":
		var cross := Control.new()
		cross.name = "Cross"
		cross.set_anchors_preset(Control.PRESET_FULL_RECT)
		cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cross.draw.connect(_draw_cross.bind(cross))
		holder.add_child(cross)
	return holder


func _build() -> void:
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	margin.add_child(layout)

	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_STOP
	header.gui_input.connect(_on_header_input)
	layout.add_child(header)

	var title := Label.new()
	title.text = "Politics"
	title.theme_type_variation = &"Title"
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var close_button := Button.new()
	close_button.text = "X"
	close_button.custom_minimum_size = Vector2(32, 32)
	close_button.pressed.connect(func() -> void: close_requested.emit())
	header.add_child(close_button)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(scroll)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", ROW_GAP)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Fill the scroll's viewport even when the content is shorter than it, so the empty-state
	# line can centre itself in the panel instead of clinging to the top of a tall blank box.
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	_refresh()


## The entries whose turn has arrived, oldest first — the arc reads as a story, and a player
## opening this for the first time at turn 150 wants to start at the election.
##
## `icon` is one of: "gavel" (a political act), "coal_banned" (the levy, which is the coal and
## oil story), "power" (the subsidy, which is the green-power story).
func _entries() -> Array:
	var turn := int(TurnManager.current_turn)
	var out: Array = []

	if turn >= PolicyState.beat("election_news"):
		out.append({
			"icon": "gavel",
			"title": "A new government elected!",
			"turn": PolicyState.beat("election_news"),
			"body": "The Party of Markets is now in government. They are likely to pursue their agenda of reducing pollution through some sort of tax.",
		})
	if turn >= PolicyState.beat("tax_notice"):
		out.append({
			"icon": "coal_banned",
			"title": "Carbon Tax announced",
			"turn": PolicyState.beat("tax_notice"),
			"body": "There will be a tax on carbon emissions. Any production or power generation that uses coal or crude oil (or their polluting byproducts) will be subject to a tax.",
		})
	# The ramp entry names the turn the levy reaches full rate, and is replaced by the
	# "in full effect" entry once it gets there — a live "ramping up until turn X" left
	# standing after turn X would be telling the player something untrue.
	var p1: int = PolicyState.beat("p1")
	if turn >= PolicyState.beat("ramp_first") and turn < p1:
		out.append({
			"icon": "coal_banned",
			"title": "Carbon Tax ramping up until turn %d" % p1,
			"turn": PolicyState.beat("ramp_first"),
			"body": "The carbon tax will keep increasing until turn %d." % p1,
		})
	if turn >= p1:
		out.append({
			"icon": "coal_banned",
			"title": "Carbon Tax in full effect",
			"turn": PolicyState.beat("p1"),
			"body": "Adapt or pay. The government insists it's here to stay. The Ministry of Finance is rather satisfied with the extra revenue too.",
		})
	if turn >= PolicyState.beat("subsidy_notice"):
		out.append({
			"icon": "power",
			"title": "Subsidy for Green energy",
			"turn": PolicyState.beat("subsidy_notice"),
			"body": "A green subsidy has been announced. The objective is to push more companies to invest in green power.",
		})
	if turn >= PolicyState.beat("subsidy"):
		out.append({
			"icon": "power",
			"title": "Green Power subsidy in full effect",
			"turn": PolicyState.beat("subsidy"),
			"body": "The green subsidy has taken effect. It is unknown how much longer the government will keep it around, as it's proving oversubscribed.",
		})
	return out


## The entries in the order they happened, entries of one turn keeping their own order.
static func by_turn(entries: Array) -> Array:
	var keyed: Array = []
	for i in entries.size():
		keyed.append([int((entries[i] as Dictionary).get("turn", 0)), i])
	keyed.sort()
	return keyed.map(func(k: Array) -> Dictionary: return entries[int(k[1])])


func _refresh(_a: Variant = null) -> void:
	if _list == null or not is_instance_valid(_list):
		return
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var entries := _entries()
	if _ds2:
		# Each module prints its turn, so the record runs in the order things happened.
		entries = by_turn(entries)
		if entries.is_empty():
			var none := _oak_panel("PoliticsEmpty")
			var words := Parts.body(DS2_EMPTY)
			words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			none.get_child(0).add_child(words)
			_list.add_child(none)
		for i in entries.size():
			_list.add_child(_entry_module(entries[i], i))
		_fit_rows()
		return
	if entries.is_empty():
		# Nothing has happened yet, and saying so is the whole content of the panel until
		# the election. An empty box would read as a broken panel.
		_empty_label = Label.new()
		_empty_label.text = "No Political Events yet"
		_empty_label.theme_type_variation = &"Body"
		_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_empty_label.add_theme_color_override("font_color", DS.PALETTE["TEXT_MUTED"])
		_empty_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_list.add_child(_empty_label)
		return
	for e: Dictionary in entries:
		_list.add_child(_entry_card(e))


## One event: its icon on the left, title and body stacked beside it, on the DS inset card
## the other panels use for a self-contained item.
func _entry_card(entry: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.theme_type_variation = &"Inset"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var pad := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 10)
	card.add_child(pad)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	pad.add_child(row)

	var icon := _icon_for(str(entry.get("icon", "")))
	icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(icon)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)

	var title := Label.new()
	title.text = str(entry.get("title", ""))
	title.theme_type_variation = &"Section"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(title)

	var body := Label.new()
	body.text = str(entry.get("body", ""))
	body.theme_type_variation = &"Body"
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_color_override("font_color", DS.PALETTE["TEXT"])
	col.add_child(body)
	return card


func _icon_for(kind: String) -> Control:
	match kind:
		"power":
			# Power AS A GOOD (what the subsidy pays for), so the isometric good icon — the
			# flat lightning is the energy-cost mark. See the 2026-08-29 icon ruling.
			# "power" (g_010), not "green_power": the EA catalog carries one power good, and
			# asking for a green_power that does not exist returned a blank icon box.
			var pw := Catalog.get_good_by_internal_name("power")
			var gid := str(pw.get("id", ""))
			var tex: Texture2D = GoodIcons.texture_for_size(gid, "power", ICON_BOX) if gid != "" else null
			return _texture_box(tex)
		"coal_banned":
			return _coal_banned_icon()
		_:
			return _texture_box(load(GAVEL_ICON) as Texture2D)


func _texture_box(tex: Texture2D) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(ICON_BOX, ICON_BOX)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(tr)
	return holder


## Coal struck through in red: the levy's subject, and the mark the coal prohibition uses
## conceptually. Drawn rather than baked so there is no new asset to keep in step with the
## goods art, and so the cross scales with ICON_BOX.
func _coal_banned_icon() -> Control:
	var coal := Catalog.get_good_by_internal_name("coal")
	var gid := str(coal.get("id", ""))
	var holder := _texture_box(GoodIcons.texture_for_size(gid, "coal", ICON_BOX) if gid != "" else null)
	var cross := Control.new()
	cross.set_anchors_preset(Control.PRESET_FULL_RECT)
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cross.draw.connect(_draw_cross.bind(cross))
	holder.add_child(cross)
	return holder


func _draw_cross(host: Control) -> void:
	var r := host.get_rect().size
	if r.x <= 0.0 or r.y <= 0.0:
		return
	var pad := r.x * 0.12
	var w := maxf(3.0, r.x * 0.10)
	var red: Color = DS.PALETTE["DANGER"]
	# A dark backing stroke first: the goods art is busy, and a bare red line loses itself
	# against the coal's own highlights.
	host.draw_line(Vector2(pad, pad), Vector2(r.x - pad, r.y - pad), Color(0, 0, 0, 0.55), w + 2.0, true)
	host.draw_line(Vector2(r.x - pad, pad), Vector2(pad, r.y - pad), Color(0, 0, 0, 0.55), w + 2.0, true)
	host.draw_line(Vector2(pad, pad), Vector2(r.x - pad, r.y - pad), red, w, true)
	host.draw_line(Vector2(r.x - pad, pad), Vector2(pad, r.y - pad), red, w, true)


## Drag by the header strip, matching the other free-floating panels.
func _on_header_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if _dragging:
			_drag_offset = global_position - get_global_mouse_position()
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		global_position = get_global_mouse_position() + _drag_offset
		accept_event()
