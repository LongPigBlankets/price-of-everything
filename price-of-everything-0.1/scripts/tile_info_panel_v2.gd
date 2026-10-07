extends PanelContainer
## The Tile View Panel, the site's control cabinet (docs/tile-view-ds2-plan.md §9).
##
## Pattern: the nameplate, the land row (the tile's hex, its status line and land figures), then the key bed:
## five latching keys, each tab's figure on the dot-matrix display above its key, then the open tab's body on
## a navy sheet. Each tab's body is its own script in scripts/tvp_v3/, which calls back into this panel for
## the tile, its signals and its shared actions.
##
## All numbers come from TileViewData.

signal building_clicked(building: Dictionary)
## The survey call-to-action was clicked — opens the survey dialog for this tile.
signal survey_requested(tile_data: Dictionary)
## Asks the host (world_map) to enter map "pick a destination tile" mode; the
## result comes back via on_destination_picked().
signal pick_destination_requested()
## The Location key: centre the map on this tile.
signal locate_requested(tile_id: String)

const Metrics := preload("res://scripts/ds2/metrics.gd")
const TileViewData := preload("res://scripts/tile_view_data.gd")
const GoodIcons := preload("res://scripts/good_icons.gd")
const UIFonts := preload("res://scripts/ui_fonts.gd")
const ROUTE_STOCKPILE_ICON: Texture2D = preload("res://assets/icons/ui_icons/route_stockpile.png")
## The rotary selector (the white plastic knob), for choices of two to seven options.
const RotarySelector := preload("res://scripts/rotary_selector.gd")
const ROUTE_MARKET_ICON: Texture2D = preload("res://assets/icons/ui_icons/route_port.png")
const ROUTE_MIDDLEMAN_ICON: Texture2D = preload("res://assets/icons/ui_icons/route_lorry.png")
## The tabs, one latching key each; Transport holds the tile's infrastructure.
const TABS := [
	{"id": "bl", "label": "Buildings"},
	{"id": "power", "label": "Power"},
	{"id": "prod", "label": "Goods"},
	{"id": "stock", "label": "Stockpile"},
	{"id": "transport", "label": "Transport"},
]
## The tab bodies, one script each, loaded when the tab is drawn so a fault in one leaves the others working.
const V3_TAB_BODIES := {
	"bl": "res://scripts/tvp_v3/buildings_tab.gd",
	"power": "res://scripts/tvp_v3/power_tab.gd",
	"prod": "res://scripts/tvp_v3/goods_tab.gd",
	"stock": "res://scripts/tvp_v3/stock_tab.gd",
	"transport": "res://scripts/tvp_v3/transport_tab.gd",
}
const Nine := preload("res://scripts/bdp_v3_nine.gd")
const V3Lamp := preload("res://scripts/bdp_v3_lamp.gd")
const V3Key := preload("res://scripts/bdp_v3_key.gd")
const CabinetKey := preload("res://scripts/ds2/latch_key.gd")
const DotMatrix := preload("res://scripts/ds2/dot_matrix.gd")
## The display's marks for a tab that needs a look.
const V3_KEY_MARK := {"warn": Color("#ffb21f"), "bad": Color("#ff3b2f")}
## The key display's dots (a character 7 dots tall, so 14 px at 2.0) and the extra room above and below them,
## so the figures sit smaller on a taller glass.
const V3_FIGURE_PITCH := 2.0
## The land breakdown's swatch: its side, and its stainless bezel's face, shadow and lit edge.
const V3_SWATCH := 18.0
const V3_SWATCH_STEEL := Color("#b9c0c8")
const V3_SWATCH_STEEL_DK := Color("#5d656e")
const V3_SWATCH_STEEL_LT := Color("#e6eaee")
const V3_DISPLAY_ROOM := 5.0
## The planning limit's explanation, on hover of the term in the land line.
const V3_PLANNING_NOTE := "Above the planning limit, local opposition makes construction more complex, increasing materials requirements by 50%"
## The body sheet's padding, logical pixels (DS2's room between a plate's edge and what it holds), and how
## much nearer its edge the scroll rail stands than the content does.
const V3_BODY_PAD := Metrics.PLATE_PAD
const V3_RAIL_NUDGE := 5
## Deposit icons in the status line, logical pixels.
const V3_DEPOSIT_ICON := 22.0
const LandHex := preload("res://scripts/tile_land_hex.gd")
const PlayerColours := preload("res://scripts/player_colours.gd")
const Plate := preload("res://scripts/bdp_v3_plate.gd")
const MoneyFigure := preload("res://scripts/ds2/money_figure.gd")
## The cabinet's renders (tools/button_mockup/cluster.html?export&only=tiledoor,tilekey), their numbers from
## layout.json in layout pixels (1.875 to a logical pixel, 2/1.875 texels to a layout pixel).
const V3_LAYOUT := 1.875
const V3_TEXELS := 2.0 / 1.875
const V3_DOOR: Texture2D = preload("res://assets/ui/bdp_v3/tile_door.png")
const V3_DOOR_MARGIN := 24.0
const V3_DOOR_CORNER := 96.0
const V3_DOOR_PIPE_INSET := 0.0
const V3_FLANGE_H: Texture2D = preload("res://assets/ui/bdp_v3/tile_flange_h.png")
const V3_FLANGE_V: Texture2D = preload("res://assets/ui/bdp_v3/tile_flange_v.png")
const V3_FLANGE := 64.0
const V3_NAMEPLATE: Texture2D = preload("res://assets/ui/bdp_v3/tile_nameplate.png")
const V3_NAMEPLATE_MARGIN := 14.0
const V3_NAMEPLATE_CAP := 60.0
const V3_KEYBED: Texture2D = preload("res://assets/ui/bdp_v3/tile_keybed.png")
const V3_KEYBED_MARGIN := 14.0
const V3_KEYBED_CORNER := 40.0
const V3_SHEET: Texture2D = preload("res://assets/ui/bdp_v3/bar_sheet.png")
const V3_SHEET_MARGIN := 10.0
const V3_SHEET_CORNER := 60.0
## Room inside the door: DS2's plate padding from the stainless, past the half of the pipe run round its
## edge that lies on the door (tile_door pipe_radius 8 layout px, centred on the edge).
const V3_PAD := Metrics.PLATE_PAD + 4
## Print on the stainless: navy, engraved and filled (DS2 rule 3); the name on the black nameplate in white.
const V3_INK := Color("#0b2340")
const V3_NAME_INK := Color("#eef1f5")
const V3_BODY_PX := 14
const V3_CAPTION_PX := 15
## Buy Land's and Survey's keys beside the land gauge.
const V3_SIDE_KEY_W := 104.0
## A link counts as near capacity at this share of it.
const V3_LINK_NEAR := 0.9
## The terrain glyphs, cut from the owner's sprite sheet by tools/extract_terrain_icons.py at one scale for
## the set, and how many logical pixels each texture pixel takes over the mini hex (a city's glyph 33 tall).
const TERRAIN_ICON := "res://assets/icons/ui_icons/terrain/terrain_%s.png"
const TERRAIN_ICON_SCALE := 0.27
## What each terrain is, for the glyph's tooltip.
const TERRAIN_GROUND := {"rural": "Open country", "urban": "Built-up ground", "hill": "Rough ground",
	"mountain": "Steep ground", "sea": "Open water", "deep_sea": "Deep water"}
## The keys' names where the owner's differ from the tabs' labels.
const V3_KEY_NAMES := {"stock": "Stock"}


static var _route_icon_cache: Dictionary = {}

# Seaport special-building card (top of the Buildings tab) + its NPC buy-confirm dialog.
const PORT_BUILDING_ID := "b_004"
const BuyDialog := preload("res://scripts/buy_building_dialog.gd")
var _port_buy_dialog: Node = null
var _port_buy_layer: CanvasLayer = null
var _pending_port_buy: Dictionary = {}

# The Stock tab's "Move or sell" choice (persists across pane rebuilds).
const MARKET_DEST := "__market__"
const SPECIAL_ORDER_DEST := "__special_order__"
var _stock_sel: Dictionary = {}   # {good_id, name, qty} of the selected good, or {}
var _stock_qty: int = 0
var _stock_dest: String = ""      # "" = none, MARKET_DEST, SPECIAL_ORDER_DEST, or a tile_id
var _stock_recurring: bool = false
# Warehouse-expansion inline confirmation open? (Persists across pane rebuilds,
# resets when a different tile is shown.)
var _warehouse_expand: bool = false

var _current_tile_data: Dictionary = {}
var _current_tile_id: String = ""
var _active_tab: String = "bl"

var _status_line: Container = null
var _drag_delta := Vector2.ZERO   # user-applied offset from dragging the nameplate
var _dragging := false
var _tiles: Dictionary = {}        # tab_id -> {root: its key, figure: its display, tone}
var _panes: Dictionary = {}        # tab_id -> Control (body container)
var _pane_host: VBoxContainer = null
var _nameplate: Control = null
var _nameplate_text := ""
var _land_hex: Control = null
var _terrain_glyph: TextureRect = null
var _land_readout: HFlowContainer = null
var _survey_key: Control = null
## The land in full, shown in the body's place while open.
var _land_open := false
var _land_view: ScrollContainer = null
var _land_full: Control = null
var _land_list: VBoxContainer = null
var _land_view_readout: HFlowContainer = null
var _body_scroll: ScrollContainer = null

func _enter_tree() -> void:
	# the hex grid overlay mirrors this panel's tile as its brass selection
	add_to_group("tile_view_panel")

func _ready() -> void:
	_apply_anchors()
	_apply_panel_style()
	_apply_token_theme()
	_build_ui()
	# Live data refresh while open.
	BuildingState.building_added.connect(func(_i): _refresh_if_visible())
	BuildingState.building_removed.connect(func(_i): _refresh_if_visible())
	BuildingState.building_owner_changed.connect(func(_i): _refresh_if_visible())
	BuildingState.tile_land_owned_changed.connect(func(_t): _refresh_if_visible())
	Stockpile.stockpile_changed.connect(_refresh_if_visible)
	Production.turn_processed.connect(func(_summary): _refresh_if_visible())
	SpecialOrderState.orders_changed.connect(func(): _refresh_if_visible())
	Construction.construction_started.connect(func(_a = null, _b = null): _refresh_if_visible())
	Construction.construction_completed.connect(func(_a = null, _b = null): _refresh_if_visible())
	Construction.construction_cancelled.connect(func(_a = null, _b = null): _refresh_if_visible())
	MatchState.surveyed_tiles_changed.connect(func(): _refresh_if_visible())
	MatchState.deposits_changed.connect(func(_t = null): _refresh_if_visible())
	# Awaiting-materials projects fire materials_ordered (not construction_started),
	# so listen for it too — show the build the same turn it's placed.
	Construction.materials_ordered.connect(func(_a = null, _b = null): _refresh_if_visible())
	if Construction.has_signal("construction_materials_updated"):
		Construction.construction_materials_updated.connect(func(_a = null, _b = null): _refresh_if_visible())
	TransportState.transport_shipments_changed.connect(_refresh_if_visible)
	# Money changing (loan taken, building sold, etc.) can move a build above/below
	# its affordability threshold — refresh so power build buttons re-enable.
	MatchState.money_changed.connect(func(_m): _refresh_if_visible())
	MatchState.sell_surplus_changed.connect(func(_t): _refresh_if_visible())
	visible = false

func _apply_anchors() -> void:
	var panel_w := 655.0
	custom_minimum_size = Vector2(panel_w, 0)
	anchor_left = 1.0
	anchor_right = 1.0
	offset_left = -(panel_w + 30.0) + _drag_delta.x
	# Clears the top bar and its shadow (72 px down the screen; HUDContent starts at 36);
	# aligns with the left-slot panels.
	offset_top = 36.0 + _drag_delta.y
	offset_right = -30.0 + _drag_delta.x
	offset_bottom = 948.0 + _drag_delta.y  # taller panel (top pinned near the screen top, so it grows down)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN


## Standardise the panel's type tokens by overriding the DS label variations
## locally (so every label that uses a variation picks up the right face/size):
##   Title → Bebas 32 (kept) · Section → Bebas 21 (overlay/section title) ·
##   Numeric → Plex SemiBold tabular (all numerals) · Body → Plex Medium 14
##   (row titles) · Caption → Plex Regular 10 (floor).
func _apply_token_theme() -> void:
	var t: Theme = (DS.theme as Theme).duplicate(true) if (DS and DS.theme) else Theme.new()
	t.set_font("font", "Section", UIFonts.BEBAS)
	t.set_font_size("font_size", "Section", 21)
	t.set_font("font", "Numeric", UIFonts.mono())
	t.set_font("font", "Body", UIFonts.PLEX_MED)
	t.set_font_size("font_size", "Body", 14)
	t.set_font("font", "Caption", UIFonts.PLEX_MED)
	t.set_font_size("font_size", "Caption", 10)
	theme = t

func _apply_panel_style() -> void:
	# The cabinet door is painted in _draw; the stylebox only keeps the content clear of its pipe.
	var bare := StyleBoxEmpty.new()
	bare.set_content_margin_all(V3_PAD)
	add_theme_stylebox_override("panel", bare)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

# ─────────────────────────────────────────────────────────────────────────────
# UI construction
# ─────────────────────────────────────────────────────────────────────────────
## The cabinet door: brushed stainless with the black iron pipe run round its edge, and a flange at the
## middle of each side.
func _draw() -> void:
	Nine.paint(self, V3_DOOR, Rect2(Vector2.ZERO, size).grow(V3_DOOR_MARGIN / V3_LAYOUT),
		(V3_DOOR_MARGIN + V3_DOOR_CORNER) * V3_TEXELS)
	var p := V3_DOOR_PIPE_INSET / V3_LAYOUT
	var f := V3_FLANGE / V3_LAYOUT
	for spot: Array in [[Vector2(size.x * 0.5, p), V3_FLANGE_H], [Vector2(size.x * 0.5, size.y - p), V3_FLANGE_H],
			[Vector2(p, size.y * 0.5), V3_FLANGE_V], [Vector2(size.x - p, size.y * 0.5), V3_FLANGE_V]]:
		draw_texture_rect(spot[1], Rect2((spot[0] as Vector2) - Vector2(f, f) * 0.5, Vector2(f, f)), false)


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.name = "Cabinet"
	root.add_theme_constant_override("separation", 12)
	add_child(root)
	# The fixed part, top to bottom (docs/tile-view-ds2-plan.md §4.2): what the place is, whether you can
	# use it, and whether anything is wrong. Each action sits beside the figure it changes.
	root.add_child(_build_nameplate_row())
	root.add_child(_build_land_row())
	root.add_child(_build_key_bed())

	# The body: the open tab on a sheet of the bar's navy steel, the dark ground the tabs were built on,
	# until each is restyled.
	# Room enough inside the sheet's rim for the cases the tabs set in it, whose renders reach past their
	# edges for their shadows (the section frame's 18 layout px, the plastic plate's 14).
	var body_sheet := _v3_sheet(V3_BODY_PAD)
	body_sheet.name = "BodySheet"
	# The rail stands V3_RAIL_NUDGE nearer the sheet's edge; while it hides, the panes keep that room.
	(body_sheet.get_theme_stylebox("panel") as StyleBoxEmpty).content_margin_right = V3_BODY_PAD - V3_RAIL_NUDGE
	body_sheet.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body_sheet)
	var scroll := ScrollContainer.new()
	scroll.name = "BodyScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body_sheet.add_child(scroll)
	_body_scroll = scroll
	# Building Detail's steel rail and grip rather than Godot's thin grey bar.
	load("res://scripts/bdp_v3_scroll.gd").apply(scroll, true)
	var room := MarginContainer.new()
	room.name = "PaneRoom"
	room.size_flags_vertical = Control.SIZE_EXPAND_FILL
	room.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(room)
	var bar := scroll.get_v_scroll_bar()
	var follow := func() -> void: room.add_theme_constant_override("margin_right", 0 if bar.visible else V3_RAIL_NUDGE)
	bar.visibility_changed.connect(follow)
	follow.call()
	_pane_host = VBoxContainer.new()
	_pane_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_pane_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	room.add_child(_pane_host)
	for tab in TABS:
		var pane := VBoxContainer.new()
		pane.add_theme_constant_override("separation", 9)
		pane.size_flags_vertical = Control.SIZE_EXPAND_FILL
		pane.visible = false
		_pane_host.add_child(pane)
		_panes[tab.id] = pane
	# The land in full takes the body's place while it is open (the sheet fits both to its room).
	_land_view = _build_land_view()
	body_sheet.add_child(_land_view)
	# The lamp over the cabinet, the door, its pipe and its sheets (docs/ds2-theme.md §4).
	preload("res://scripts/ds2/lamp_overlay.gd").attach(self)


## A sheet of the top bar's navy steel (its flyouts' plate) with `pad` of room inside.
func _v3_sheet(pad: int) -> PanelContainer:
	var sheet := PanelContainer.new()
	var bare := StyleBoxEmpty.new()
	bare.set_content_margin_all(pad)
	sheet.add_theme_stylebox_override("panel", bare)
	sheet.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sheet.draw.connect(func() -> void:
		Nine.paint(sheet, V3_SHEET, Rect2(Vector2.ZERO, sheet.size).grow(V3_SHEET_MARGIN / V3_LAYOUT),
			(V3_SHEET_MARGIN + V3_SHEET_CORNER) * V3_TEXELS))
	return sheet


## The engraved nameplate riveted to the door (the site's name; its coordinates on hover), which drags the
## panel, then Building Detail's Location and Close keys.
func _build_nameplate_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "NameplateRow"
	row.add_theme_constant_override("separation", 8)
	_nameplate = Control.new()
	_nameplate.name = "Nameplate"
	_nameplate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_nameplate.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_nameplate.custom_minimum_size = Vector2(0, 36)
	_nameplate.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_nameplate.mouse_filter = Control.MOUSE_FILTER_STOP
	_nameplate.mouse_default_cursor_shape = Control.CURSOR_MOVE
	_nameplate.gui_input.connect(_on_header_drag)
	_nameplate.draw.connect(_draw_nameplate)
	row.add_child(_nameplate)
	var locate := V3Key.make("pin")
	locate.name = "LocationKey"
	locate.tooltip_text = "Show this tile on the map"
	locate.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	locate.pressed.connect(func() -> void: locate_requested.emit(_current_tile_id))
	row.add_child(locate)
	var close := V3Key.make("close")
	close.name = "CloseKey"
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(hide)
	row.add_child(close)
	return row


func _draw_nameplate() -> void:
	var n := _nameplate
	var out := V3_NAMEPLATE_MARGIN / V3_LAYOUT
	var dest := Rect2(Vector2.ZERO, n.size).grow(out)
	var cap_px := V3_NAMEPLATE_CAP / V3_LAYOUT
	var cap_tx := V3_NAMEPLATE_CAP * V3_TEXELS
	var tw := float(V3_NAMEPLATE.get_width())
	var th := float(V3_NAMEPLATE.get_height())
	n.draw_texture_rect_region(V3_NAMEPLATE, Rect2(dest.position, Vector2(cap_px, dest.size.y)), Rect2(0, 0, cap_tx, th))
	n.draw_texture_rect_region(V3_NAMEPLATE, Rect2(dest.position.x + cap_px, dest.position.y, dest.size.x - 2.0 * cap_px, dest.size.y),
		Rect2(cap_tx, 0, tw - 2.0 * cap_tx, th))
	n.draw_texture_rect_region(V3_NAMEPLATE, Rect2(dest.end.x - cap_px, dest.position.y, cap_px, dest.size.y), Rect2(tw - cap_tx, 0, cap_tx, th))
	if _nameplate_text == "":
		return
	# Cut into the enamel and filled white: the cut's upper wall shows as a dark line over the letters.
	var font: Font = UIFonts.BEBAS
	var fs := 28
	var room := n.size.x - 44.0
	while fs > 16 and font.get_string_size(_nameplate_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > room:
		fs -= 1
	var base := n.size.y * 0.5 + (font.get_ascent(fs) - font.get_descent(fs)) * 0.5
	n.draw_string(font, Vector2(22, base - 1), _nameplate_text, HORIZONTAL_ALIGNMENT_LEFT, room, fs, Color(0, 0, 0, 0.7))
	n.draw_string(font, Vector2(22, base), _nameplate_text, HORIZONTAL_ALIGNMENT_LEFT, room, fs, V3_NAME_INK)


## The land: at a glance, the tile's hex on its LED screen (a click opens it in full), and beside it the status
## line, the land's figures, Buy Land, and Survey while the tile is unsurveyed.
func _build_land_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "LandRow"
	row.add_theme_constant_override("separation", 14)
	# The terrain's glyph stands over the hex; hovering it says what the terrain does to the tile's land.
	var hex_col := VBoxContainer.new()
	hex_col.name = "HexColumn"
	hex_col.add_theme_constant_override("separation", 4)
	row.add_child(hex_col)
	_terrain_glyph = TextureRect.new()
	_terrain_glyph.name = "TerrainIcon"
	_terrain_glyph.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_terrain_glyph.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_terrain_glyph.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_terrain_glyph.self_modulate = V3_INK
	_terrain_glyph.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_terrain_glyph.mouse_filter = Control.MOUSE_FILTER_STOP
	hex_col.add_child(_terrain_glyph)
	_land_hex = LandHex.new()
	_land_hex.name = "TileLandChart"   # tutorial spotlight target
	_land_hex.expand_requested.connect(func() -> void: _set_land_open(not _land_open))
	hex_col.add_child(_land_hex)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)
	row.add_child(col)
	var status := HFlowContainer.new()
	status.name = "StatusLine"
	status.add_theme_constant_override("h_separation", 10)
	status.add_theme_constant_override("v_separation", 4)
	_status_line = status
	col.add_child(status)
	_land_readout = HFlowContainer.new()
	_land_readout.name = "LandFigures"
	_land_readout.add_theme_constant_override("h_separation", 0)
	col.add_child(_land_readout)
	var keys := HBoxContainer.new()
	keys.add_theme_constant_override("separation", 10)
	col.add_child(keys)
	var buy := CabinetKey.new()
	buy.name = "BLBuyLandButton"   # tutorial spotlight target
	buy.text = "Buy Land"
	buy.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	buy.custom_minimum_size.x = V3_SIDE_KEY_W
	buy.pressed.connect(func() -> void: _on_buy_land_pressed(buy))
	keys.add_child(buy)
	_survey_key = CabinetKey.new()
	_survey_key.name = "SurveyKey"
	_survey_key.text = "Survey"
	_survey_key.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_survey_key.custom_minimum_size.x = V3_SIDE_KEY_W
	_survey_key.pressed.connect(func() -> void: survey_requested.emit(_current_tile_data))
	keys.add_child(_survey_key)
	return row


## The land in full, shown in the body's place: the tile's hex as an annunciator panel, and beside it your
## buildings broken out in their shades, then free land, other companies', land to buy, the tile's
## maximum and the planning limit.
func _build_land_view() -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = "LandView"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.visible = false
	var view := VBoxContainer.new()
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.add_theme_constant_override("separation", 14)
	scroll.add_child(view)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	view.add_child(head)
	var title := _v3_print_white("LAND")
	title.add_theme_font_override("font", Plate.FONT_SEMI)
	title.add_theme_font_size_override("font_size", V3_CAPTION_PX)
	head.add_child(title)
	_land_view_readout = HFlowContainer.new()
	_land_view_readout.add_theme_constant_override("h_separation", 0)
	_land_view_readout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_land_view_readout)
	var close := V3Key.make("close")
	close.name = "LandCloseKey"
	close.tooltip_text = "Back to the tab"
	close.pressed.connect(func() -> void: _set_land_open(false))
	head.add_child(close)
	var main := HBoxContainer.new()
	main.add_theme_constant_override("separation", 18)
	view.add_child(main)
	_land_full = LandHex.new()
	_land_full.name = "TileLandFull"
	_land_full.expanded = true
	_land_full.building_clicked.connect(_on_chart_segment_clicked)
	main.add_child(_land_full)
	_land_list = VBoxContainer.new()
	_land_list.name = "LandList"
	_land_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_land_list.add_theme_constant_override("separation", 5)
	main.add_child(_land_list)
	return scroll


## Opens or closes the land in full in the body's place. The tab under it keeps its place; pressing a key
## closes the land and opens that tab.
func _set_land_open(on: bool) -> void:
	_land_open = on
	if _land_view != null:
		_land_view.visible = _land_open
	if _body_scroll != null:
		_body_scroll.visible = not _land_open
	if _land_hex != null:
		_land_hex.open = _land_open
	if _land_open:
		_refresh_land_view()
	_apply_tile_styles()


func _refresh_land_view() -> void:
	if _land_full == null or _current_tile_id == "":
		return
	var chart := TileViewData.land_chart_data(_current_tile_id, _current_tile_data)
	var totals := TileViewData.land_totals(_current_tile_id, _current_tile_data)
	_land_full.configure(chart, totals)
	_fill_land_line(_land_view_readout, DS.PALETTE.TEXT)
	for child in _land_list.get_children():
		_land_list.remove_child(child)
		child.queue_free()
	var groups: Array = _land_full.groups
	var yours: Array = []
	var theirs := 0.0
	var theirs_count := 0
	var features := 0.0
	var free := {}
	var buy := {}
	for g: Dictionary in groups:
		match str(g.kind):
			"yours": yours.append(g)
			"theirs":
				theirs += float(g.units)
				theirs_count += 1
			"feature": features += float(g.units)
			"free": free = g
			"buy": buy = g
	_land_list.add_child(_land_caption("Your buildings"))
	if yours.is_empty():
		_land_list.add_child(_land_line(null, "None yet", ""))
	for g: Dictionary in yours:
		var label := str(g.short) if str(g.short) != "" else str(g.name)
		var line := _land_line(g.colour, label + (", under construction" if bool(g.construction) else ""), str(roundi(float(g.units))))
		line.tooltip_text = str(g.name)
		var iid := str(g.instance_id)
		if iid != "":
			line.mouse_filter = Control.MOUSE_FILTER_STOP
			line.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			line.gui_input.connect(func(e: InputEvent) -> void:
				if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
					_on_chart_segment_clicked(iid))
		_land_list.add_child(line)
	_land_list.add_child(_land_caption("The rest of the tile"))
	_land_list.add_child(_land_line(_land_full.colour_of(groups.find(free)) if not free.is_empty() else LandHex.UNLIT_WINDOW,
		"Your free land", str(int(totals.free))))
	if theirs_count > 0:
		_land_list.add_child(_land_line(PlayerColours.NPC, "Other companies, %d %s" % [theirs_count, "building" if theirs_count == 1 else "buildings"],
			str(roundi(theirs))))
	if features > 0.0:
		_land_list.add_child(_land_line(LandHex.STONE, "Woods and ruins", str(roundi(features))))
	_land_list.add_child(_land_line(LandHex.UNLIT_WINDOW, "To buy", str(int(totals.buyable))))
	_land_list.add_child(_land_line(null, "Tile maximum", str(int(chart.get("type_cap", 0)))))
	if int(chart.get("type_cap", 0)) > int(BuildingState.DENSITY_SOFT_CAPACITY):
		_land_list.add_child(_land_line("hazard", "Planning limit", str(int(BuildingState.DENSITY_SOFT_CAPACITY))))


func _land_caption(text: String) -> Label:
	var l := _v3_print_white(text.to_upper())
	l.add_theme_font_override("font", Plate.FONT_SEMI)
	l.add_theme_font_size_override("font_size", V3_CAPTION_PX)
	return l


## One line of the land's breakdown: its swatch ("hazard" for the planning limit's tape), what it is and how
## much land. Each swatch sits in a small stainless bezel with a black line round the colour, so a dark
## colour reads against the bright steel and a light one against the black line, whatever the plate under it.
func _land_line(colour: Variant, text: String, units: String) -> HBoxContainer:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	var sw := Control.new()
	sw.custom_minimum_size = Vector2(V3_SWATCH, V3_SWATCH)
	sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sw.draw.connect(func() -> void:
		if not colour is Color and str(colour) != "hazard":
			return
		var box := Rect2(Vector2.ZERO, sw.size)
		sw.draw_rect(box, V3_SWATCH_STEEL_DK)
		sw.draw_rect(box.grow(-1.0), V3_SWATCH_STEEL)
		sw.draw_rect(Rect2(box.position + Vector2(1, 1), Vector2(box.size.x - 2.0, 1.0)), V3_SWATCH_STEEL_LT)
		var inner := box.grow(-3.0)
		sw.draw_rect(inner, Color.BLACK)
		inner = inner.grow(-1.0)
		if colour is Color:
			sw.draw_rect(inner, colour)
		else:
			var tape: Dictionary = LandHex.tape()
			sw.draw_rect(inner, tape.band)
			var x := inner.position.x
			while x < inner.end.x:
				sw.draw_rect(Rect2(x, inner.position.y + 2.0, minf(2.5, inner.end.x - x), inner.size.y - 4.0), tape.stripe)
				x += 5.0)
	line.add_child(sw)
	var name_label := _v3_print_white(text)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.clip_text = true
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(name_label)
	var figure := _v3_print_white(units)
	figure.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	figure.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(figure)
	return line


## The land in words: how much land until the planning limit (underlined, its hover the explanation) and
## how much until the tile's cap, both counting everyone's buildings as the build check does.
func _fill_land_line(box: HFlowContainer, ink: Color) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
	var cap := BuildingState.max_tile_land(_current_tile_id)
	var used := BuildingState.get_tile_space_used(_current_tile_id)
	var limit := BuildingState.DENSITY_SOFT_CAPACITY
	var words := func(text: String) -> Label:
		var l := _v3_print_white(text)
		l.add_theme_color_override("font_color", ink)
		box.add_child(l)
		return l
	if cap > int(limit):
		var room := limit - used
		words.call(("%d land until the " % floori(room)) if room >= 0.0 else "Past the ")
		var term: Label = words.call("planning limit")
		term.name = "PlanningLimitTerm"
		term.tooltip_text = V3_PLANNING_NOTE
		term.mouse_filter = Control.MOUSE_FILTER_STOP
		term.mouse_default_cursor_shape = Control.CURSOR_HELP
		_v3_underline(term, ink)
		words.call(". ")
	words.call("%d land until max cap." % maxi(0, cap - ceili(used)))


## Underlines a label's text, for a term with an explanation on hover or a link.
func _v3_underline(label: Label, ink: Color) -> void:
	label.draw.connect(func() -> void:
		var font := label.get_theme_font("font")
		var fs := label.get_theme_font_size("font_size")
		var w := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var y := (label.size.y + font.get_ascent(fs) - font.get_descent(fs)) * 0.5 + 2.0
		label.draw_line(Vector2(0, y), Vector2(w, y), Color(ink, 0.8), 1.0))


## The five latching keys on their black key bed, and over them one wide, short dot-matrix display with each
## tab's figure above its key in white, an amber or red mark before it when the tab needs a look.
func _build_key_bed() -> PanelContainer:
	var bed := PanelContainer.new()
	bed.name = "KeyBed"
	var bare := StyleBoxEmpty.new()
	bare.content_margin_left = 10
	bare.content_margin_right = 10
	bare.content_margin_top = 10
	bare.content_margin_bottom = 12
	bed.add_theme_stylebox_override("panel", bare)
	bed.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	bed.draw.connect(func() -> void:
		Nine.paint(bed, V3_KEYBED, Rect2(Vector2.ZERO, bed.size).grow(V3_KEYBED_MARGIN / V3_LAYOUT),
			(V3_KEYBED_MARGIN + V3_KEYBED_CORNER) * V3_TEXELS))
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 10)
	bed.add_child(stack)
	# The display: the mini screen's bezel and glass stretched across the bed, its figures in columns
	# that line up with the keys under them.
	var display := PanelContainer.new()
	display.name = "KeyDisplay"
	var inset := StyleBoxEmpty.new()
	inset.set_content_margin_all(DotMatrix.RIM / V3_LAYOUT + 2.0)
	inset.content_margin_top += V3_DISPLAY_ROOM
	inset.content_margin_bottom += V3_DISPLAY_ROOM
	display.add_theme_stylebox_override("panel", inset)
	display.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var corner := (DotMatrix.MARGIN + DotMatrix.RIM + DotMatrix.RADIUS + 2.0) * V3_TEXELS
	display.draw.connect(func() -> void:
		var r := Rect2(Vector2.ZERO, display.size)
		Nine.paint(display, DotMatrix.SCREEN, r.grow(DotMatrix.MARGIN / V3_LAYOUT), corner)
		display.draw_rect(r.grow(-DotMatrix.RIM / V3_LAYOUT), DotMatrix.PANE))
	var glass := Control.new()
	glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glass.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	glass.draw.connect(func() -> void:
		Nine.paint(glass, DotMatrix.GLASS, Rect2(-Vector2.ONE * (DotMatrix.RIM / V3_LAYOUT + 2.0),
			display.size).grow(DotMatrix.MARGIN / V3_LAYOUT), corner))
	var figures := HBoxContainer.new()
	figures.add_theme_constant_override("separation", 8)
	display.add_child(figures)
	display.add_child(glass)
	stack.add_child(display)
	var keys := HBoxContainer.new()
	keys.add_theme_constant_override("separation", 8)
	stack.add_child(keys)
	for tab in TABS:
		var id: String = tab.id
		var figure := DotMatrix.new()
		figure.name = "Figure_%s" % id
		figure.framed = false
		figure.pitch = V3_FIGURE_PITCH
		figure.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		figure.mouse_filter = Control.MOUSE_FILTER_PASS
		figures.add_child(figure)
		var key := CabinetKey.new()
		key.name = "TabKey_%s" % id
		key.text = str(V3_KEY_NAMES.get(id, tab.label))
		key.pressed.connect(func() -> void: _select_tab(id))
		keys.add_child(key)
		_tiles[id] = {"root": key, "figure": figure, "tone": "off"}
	return bed


func _v3_print_white(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UIFonts.PLEX_MED)
	l.add_theme_font_size_override("font_size", V3_BODY_PX)
	l.add_theme_color_override("font_color", DS.PALETTE.TEXT)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


## A word of the status line: engraved into the stainless and filled navy.
func _v3_tag(text: String) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_override("font", Plate.FONT_SEMI)
	l.add_theme_font_size_override("font_size", V3_CAPTION_PX)
	l.add_theme_color_override("font_color", V3_INK)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


## The terrain's glyph over the hex, from the owner's sprite sheet, inked navy like the print on the steel;
## its tooltip says how much land the terrain lets the tile hold.
func _refresh_terrain_glyph(terrain: String) -> void:
	var key := terrain.to_lower().replace(" ", "_")
	var path := TERRAIN_ICON % key
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_terrain_glyph.texture = tex
	_terrain_glyph.visible = tex != null
	if tex != null:
		_terrain_glyph.custom_minimum_size = tex.get_size() * TERRAIN_ICON_SCALE
	var cap := BuildingState.max_tile_land(_current_tile_id)
	var most := BuildingState.MAX_TILE_LAND
	var room := ("%d less than open country" % (most - cap)) if cap < most else "the most any tile can hold"
	_terrain_glyph.tooltip_text = "%s. %s holds up to %d land, %s.\nOnce %d are in use, new buildings cost 50%% more." % [
		terrain.capitalize(), str(TERRAIN_GROUND.get(key, "This ground")), cap, room, int(BuildingState.DENSITY_SOFT_CAPACITY)]


## One key's figure on the display. `tone` is ok, warn, bad or off: warn and bad put an amber or red mark
## before the figure; `pre` and `unit` print either side of it, the unit after a narrow space unless it is
## a sign that sits against the figure (% or /N).
func _set_key_v3(tab_id: String, tone: String, figure: String, pre: String, unit: String, tip: String) -> void:
	var t: Dictionary = _tiles[tab_id]
	var joint := "" if unit == "" or unit.begins_with("%") or unit.begins_with("/") else DotMatrix.THIN
	var words := "%s%s%s%s" % [pre, figure, joint, unit]
	var runs: Array = []
	if tone in ["warn", "bad"]:
		runs.append({"text": "● ", "colour": V3_KEY_MARK[tone]})
	runs.append({"text": words, "colour": Color.WHITE})
	(t.figure as Control).call("set_runs", runs)
	t["tone"] = tone
	(t.figure as Control).tooltip_text = tip
	(t.root as Control).tooltip_text = tip


## When the tile has no cables but your buildings on it make or draw power, what can't happen: "Cables
## missing. Power production not possible." (or consumption, or both); otherwise "". Power only moves on
## a tile through its cables (Power.tile_power_cap is 0 without them).
static func cables_missing_text(tile_id: String) -> String:
	if tile_id == "" or Power.tile_power_cap(tile_id) > 0:
		return ""
	var makes := false
	var draws := false
	for b: Dictionary in BuildingState.get_buildings_on_tile(tile_id):
		if not BuildingState.is_player_owned(b):
			continue
		var recipe := Catalog.get_recipe(str(b.get("recipe_id", "")))
		if str(recipe.get("output_name", "")) == "power" or str(recipe.get("output_1", "")) == "power":
			makes = true
		if int(recipe.get("energy_req", 0)) > 0:
			draws = true
	if not makes and not draws:
		return ""
	var what := "production and consumption" if makes and draws else ("production" if makes else "consumption")
	return "Cables missing. Power %s not possible." % what


## A power figure and its unit for the display: whole MW up to 999, then GW to one place ("1.2 GW").
static func power_figure(mw: int) -> Array:
	if absi(mw) <= 999:
		return [str(mw), "MW"]
	return ["%.1f" % (mw / 1000.0), "GW"]


## The keys' figures (docs/tile-view-ds2-plan.md §4.2): your buildings, or the stalled and problem ones
## when any; net MW; net value added; stock fill; links near capacity of those built.
func _refresh_keys_v3() -> void:
	var tone := func(status: String) -> String: return {"warn": "warn", "problem": "bad"}.get(status, "off")
	var bl := TileViewData.buildings_land_summary(_current_tile_id, _current_tile_data)
	var yours := 0
	var stalled := 0
	var problems := 0
	for row: Dictionary in bl.buildings:
		var inst := BuildingState.get_building(str(row.get("instance_id", "")))
		if bool(row.get("is_infra", false)) or inst.is_empty() or not BuildingState.is_player_owned(inst):
			continue
		yours += 1
		match str(row.get("status", "ok")):
			"problem": problems += 1
			"warn": stalled += 1
	if problems > 0:
		_set_key_v3("bl", "bad", str(problems), "", "need you", "%d of your buildings need you" % problems)
	elif stalled > 0:
		_set_key_v3("bl", "warn", str(stalled), "", "stalled", "%d of your buildings stalled last turn" % stalled)
	else:
		_set_key_v3("bl", "off", str(yours), "", "", "Your buildings on this tile")

	var power := TileViewData.power_summary(_current_tile_id)
	var stranded := cables_missing_text(_current_tile_id)
	if stranded != "":
		_set_key_v3("power", "bad", "0", "", "MW", stranded)
	else:
		var watts := power_figure(0 if power.status == "muted" else int(power.net))
		_set_key_v3("power", tone.call(str(power.status)), watts[0], "", watts[1], "Net power on this tile: made less drawn")

	var prod := TileViewData.production_summary(_current_tile_id)
	var money := MoneyFigure.led(float(prod.net_value))
	_set_key_v3("prod", tone.call(str(prod.status)), str(money.figure), "£", str(money.suffix),
		"Net value added/turn by your buildings")

	var stock := TileViewData.stockpile_summary(_current_tile_id)
	_set_key_v3("stock", "bad" if stock.is_full else tone.call(str(stock.status)), str(roundi(float(stock.pct) * 100.0)), "", "%",
		"Storage used: %d of %d" % [int(stock.used), int(stock.capacity)])

	var built := 0
	var near := 0
	var over := 0
	for slot: Dictionary in TileViewData.infrastructure_summary(_current_tile_id, _current_tile_data):
		if str(slot.get("state", "")) != "exists":
			continue
		built += 1
		var pct := float((slot.get("transit", {}) as Dictionary).get("pct", 0.0))
		if pct > 1.0:
			over += 1
		elif pct >= V3_LINK_NEAR:
			near += 1
	_set_key_v3("transport", "bad" if over > 0 else ("warn" if near > 0 else "off"), str(near + over), "", "/%d" % built,
		"Links near or over capacity, of the %d built on this tile" % built)


## The status line (owner, terrain, survey, deposits, seaport) led by the owner's lamp, and the land.
func _refresh_status_line_v3(tile_data: Dictionary) -> void:
	var tid := str(tile_data.get("id", ""))
	_nameplate_text = Catalog.tile_name(tid)
	if _nameplate_text == "":
		_nameplate_text = _tile_coordinates(tid)
	if _nameplate != null:
		_nameplate.tooltip_text = _tile_coordinates(tid)
		_nameplate.queue_redraw()
	for child in _status_line.get_children():
		_status_line.remove_child(child)
		child.queue_free()
	var yours := BuildingState.get_tile_land_owned(tid) > 0
	var others := false
	var port := {}
	for b: Dictionary in BuildingState.get_buildings_on_tile(tid):
		var mine := BuildingState.is_player_owned(b)
		yours = yours or mine
		if str(b.get("building_id", "")) == PORT_BUILDING_ID:
			port = b
		elif not mine and not TileViewData._is_ruins(Catalog.get_building(str(b.get("building_id", "")))) \
				and not BuildingState.is_land_owned_wood(b):
			others = true
	# The lamp says whose land it is; a tile of yours needs no word for it.
	var lamp := V3Lamp.new()
	lamp.name = "OwnerLamp"
	lamp.lamp_scale = 0.55
	lamp.set_tone("ok" if yours else "off")
	lamp.mouse_filter = Control.MOUSE_FILTER_STOP
	lamp.tooltip_text = "You hold land or buildings here" if yours else ("Other companies hold land here" if others else "Nobody holds land here yet")
	_status_line.add_child(lamp)
	var words: Array = [] if yours else ["Other companies" if others else "Unowned"]
	var terrain := str(tile_data.get("type", Catalog.tile_type(tid))).strip_edges()
	if terrain != "":
		words.append(terrain.capitalize())
	_refresh_terrain_glyph(terrain)
	var survey := _survey_status_for_tile(tile_data)
	words.append(survey)
	var gated: Dictionary = TileViewData.survey_gated_deposits(tid, tile_data)
	if gated.status == "unsurveyed":
		words.append("Deposits unknown")
	if not (gated.rows as Array).is_empty():
		words.append(_v3_deposit_tags(gated.rows, gated.status != "unsurveyed"))
	if not port.is_empty():
		words.append(_v3_port_link(port))
	for i in words.size():
		if i > 0:
			var rule := ColorRect.new()
			rule.color = Color(V3_INK, 0.45)
			rule.custom_minimum_size = Vector2(1.5, 14)
			rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_status_line.add_child(rule)
		_status_line.add_child(words[i] if words[i] is Control else _v3_tag(str(words[i])))

	var totals := TileViewData.land_totals(tid, tile_data)
	_land_hex.configure(TileViewData.land_chart_data(tid, tile_data), totals)
	_fill_land_line(_land_readout, V3_INK)
	if _land_open:
		_refresh_land_view()
	var surveyed := survey == "Surveyed"
	_survey_key.visible = not surveyed
	_survey_key.disabled = not MatchState.is_tile_surveyable(tid)
	_survey_key.tooltip_text = "Survey this tile" if not _survey_key.disabled \
		else "This tile is out of survey range. Survey more tiles to extend your range."


## The tile's deposits in the status line, after the word Deposits (left out on an unsurveyed tile, whose
## line already says the deposits are unknown): each good's icon with its size after it where the game
## tracks one (a question mark while unknown), the full name and size on hover.
func _v3_deposit_tags(rows: Array, captioned: bool) -> HBoxContainer:
	var tags := HBoxContainer.new()
	tags.name = "Deposits"
	tags.add_theme_constant_override("separation", 10)
	if captioned:
		tags.add_child(_v3_tag("Deposits"))
	for row: Dictionary in rows:
		var tag := HBoxContainer.new()
		tag.name = "Deposit_%s" % str(row.get("good_id", ""))
		tag.add_theme_constant_override("separation", 3)
		tag.mouse_filter = Control.MOUSE_FILTER_STOP
		tag.tooltip_text = str(row.get("chip_label", row.get("display_name", "")))
		var tex: Texture2D = GoodIcons.texture_for(str(row.get("good_id", "")), str(row.get("internal_name", "")))
		if tex != null:
			var icon := TextureRect.new()
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.texture = tex
			icon.custom_minimum_size = Vector2(V3_DEPOSIT_ICON, V3_DEPOSIT_ICON)
			icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tag.add_child(icon)
		var size := int(row.get("size_qty", -1))
		if size != -1:
			var n := _v3_tag("?" if size == -2 else str(size))
			n.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tag.add_child(n)
		tags.add_child(tag)
	return tags


## The seaport in the status line, underlined as a link: it opens the port's detail, where it can be bought.
func _v3_port_link(port: Dictionary) -> Label:
	var link := _v3_tag("Seaport" if BuildingState.is_player_owned(port) else "Seaport (NPC)")
	link.name = "SeaportLink"
	link.mouse_filter = Control.MOUSE_FILTER_STOP
	link.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	link.tooltip_text = "Open the port"
	_v3_underline(link, V3_INK)
	link.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			building_clicked.emit(port))
	return link


## "Coordinates 5, 10" from a tile id such as "tile_5_10".
static func _tile_coordinates(tile_id: String) -> String:
	var parts := tile_id.split("_")
	if parts.size() == 3 and parts[1].is_valid_int() and parts[2].is_valid_int():
		return "Coordinates %s, %s" % [parts[1], parts[2]]
	return tile_id


# Drag the whole panel by its nameplate.
func _on_header_drag(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_drag_delta += event.relative
		_apply_anchors()
		accept_event()


func _select_tab(tab_id: String) -> void:
	if _land_open:
		_set_land_open(false)
	_active_tab = tab_id
	for tab in TABS:
		var id: String = tab.id
		_panes[id].visible = (id == tab_id)
	_apply_tile_styles()
	_refresh_active_pane()

# ─────────────────────────────────────────────────────────────────────────────
# Public entry point
# ─────────────────────────────────────────────────────────────────────────────

## Whether the tile is yours to run: you own land on it, or have goods stored there.
static func player_present_on_tile(tile_id: String) -> bool:
	return BuildingState.get_tile_land_owned(tile_id) > 0 or Stockpile.get_used_capacity(tile_id) > 0
## Opens a tile's panel on `tab` ("bl" Buildings, "power", "goods", "stock"): a new tile opens on Buildings, a
## deep link names the tab it points at.
func show_tile(tile_data: Dictionary, tab: String = "bl") -> void:
	# A different tile opens at the top of its tab, not wherever the last one was scrolled to.
	if _body_scroll != null and str(tile_data.get("id", "")) != _current_tile_id:
		_body_scroll.scroll_vertical = 0
	_stock_sel.clear()
	_stock_dest = ""
	_current_tile_data = tile_data
	_current_tile_id = str(tile_data.get("id", ""))
	Audio.tile_ambience(str(tile_data.get("type", "")))  # looping terrain ambience while this panel is open
	_active_tab = tab if _panes.has(tab) else "bl"
	_warehouse_expand = false
	_refresh_status_line_v3(tile_data)
	_refresh_tiles()
	_select_tab(_active_tab)
	visible = true
	PanelStack.push(self)

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not visible:
		Audio.stop_tile_ambience()  # silence terrain ambience when the panel closes
		PanelStack.remove(self)

# Coalesced (notification_bell pattern): money_changed/stockpile_changed fire
# per transaction during PROCESS — dozens to hundreds of times in one burst —
# far too many to tear down and rebuild the entire pane on each. Signals defer ONE
# rebuild per frame; deferring also means a rebuild can never free a row button
# mid-`pressed` dispatch.
var _refresh_queued := false

func _refresh_if_visible(_a = null) -> void:
	if not visible or _current_tile_id == "" or _refresh_queued:
		return
	_refresh_queued = true
	call_deferred("_apply_refresh")

func _apply_refresh() -> void:
	_refresh_queued = false
	if not visible or _current_tile_id == "":
		return
	_refresh_status_line_v3(_current_tile_data)  # keeps the land figures + survey live
	_refresh_tiles()
	_refresh_active_pane()

# ─────────────────────────────────────────────────────────────────────────────
# Keys
# ─────────────────────────────────────────────────────────────────────────────
func _refresh_tiles() -> void:
	_refresh_keys_v3()
	_apply_tile_styles()


func _apply_tile_styles() -> void:
	for tab in TABS:
		var key := (_tiles[tab.id] as Dictionary).get("root") as CabinetKey
		if key != null:
			key.latched = tab.id == _active_tab and not _land_open

# ─────────────────────────────────────────────────────────────────────────────
# Pane dispatch
# ─────────────────────────────────────────────────────────────────────────────
func _refresh_active_pane() -> void:
	_refresh_pane(_active_tab)

func _refresh_pane(tab_id: String) -> void:
	var pane: VBoxContainer = _panes[tab_id]
	for child in pane.get_children():
		pane.remove_child(child)
		child.queue_free()
	# Each tab's body lives in its own script (scripts/tvp_v3/).
	var body := load(str(V3_TAB_BODIES[tab_id])) as Script
	if body != null and body.can_instantiate():
		body.call("build", self, pane)


func _on_power_goto() -> void:
	# Open the Power map mode without closing the TVP.
	MapMode.clear_all()
	MapMode.add_selection(MapMode.Mode.POWER_BALANCE, MapMode.POWER_SENTINEL)


func _open_port_buy(iid: String, price: int) -> void:
	if Tutorial.port_purchase_disabled(PORT_BUILDING_ID):
		return
	if _port_buy_layer == null or not is_instance_valid(_port_buy_layer):
		_port_buy_layer = CanvasLayer.new()
		_port_buy_layer.layer = 130
		get_tree().root.add_child(_port_buy_layer)
	if _port_buy_dialog == null or not is_instance_valid(_port_buy_dialog):
		_port_buy_dialog = BuyDialog.new()
		_port_buy_layer.add_child(_port_buy_dialog)
		_port_buy_dialog.connect("confirmed", _on_port_buy_confirmed)
	_pending_port_buy = {"iid": iid, "price": price}
	_port_buy_dialog.call("open", "Port", price)

func _on_port_buy_confirmed(_dont_ask: bool) -> void:
	var iid := str(_pending_port_buy.get("iid", ""))
	var price := int(_pending_port_buy.get("price", 0))
	if Tutorial.port_purchase_disabled(PORT_BUILDING_ID):
		return
	if iid == "" or not BuildingState.buildings.has(iid):
		return
	if not MatchState.deduct_money(float(price)):
		MatchState.build_rejected_no_funds.emit("Not enough money to buy the Port — need £%d, you have £%.0f" % [price, MatchState.money])
		return
	BuildingState.set_building_owner(iid, MatchState.LOCAL_PLAYER)
	MatchState.request_toast("Purchased the Port for £%d" % price, "success")
	Audio.transaction()  # building_owner_changed → _refresh_if_visible re-renders the card as owned


## Buy Land → a dropdown of fixed increments (10/20/30/40/50) up to the maximum,
## plus a "Buy maximum (N)" option. Increments above the max are omitted, so a
## small remaining cap collapses to just the maximum.
func _on_buy_land_pressed(anchor: Control) -> void:
	var patch := BuildingState.LAND_PATCH_SIZE
	var cap := TileViewData.tile_max_capacity(_current_tile_data)
	# Exact purchasable units (the last patch may be a clipped sliver next to NPC land).
	var max_land := BuildingState.get_tile_land_units_available(_current_tile_id, cap)
	if max_land <= 0:
		MatchState.request_toast("No more land available to buy on this tile", "caution")
		return
	var entries: Array = []   # [label, land_amount]
	for inc in [10, 20, 30, 40, 50]:
		if inc < max_land:
			entries.append(["Buy %d%s" % [inc, " (min)" if inc == 10 else ""], inc])
	entries.append(["Buy maximum (%d)" % max_land, max_land])

	var popup := PopupPanel.new()
	if DS and DS.theme:
		popup.theme = DS.theme
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	popup.add_child(vb)
	for e in entries:
		var land := int(e[1])
		var cost := int(round(float(land) / float(patch) * BuildingState.LAND_PATCH_COST))
		var affordable := MatchState.money >= float(cost)
		var b := Button.new()
		b.text = "%s — £%d" % [str(e[0]), cost]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(240, 30)
		b.add_theme_font_size_override("font_size", 13)
		b.focus_mode = Control.FOCUS_NONE
		if affordable:
			b.pressed.connect(func(): _buy_land_amount(land); popup.hide())
		else:
			# Disabled look (darker, muted), but still hoverable so the tooltip shows.
			var s := StyleBoxFlat.new()
			s.bg_color = DS.PALETTE.BG_PANEL
			s.set_corner_radius_all(6)
			s.content_margin_left = 10
			s.content_margin_right = 10
			s.content_margin_top = 6
			s.content_margin_bottom = 6
			b.add_theme_stylebox_override("normal", s)
			b.add_theme_stylebox_override("hover", s)
			b.add_theme_stylebox_override("pressed", s)
			b.add_theme_color_override("font_color", DS.PALETTE.TEXT_DIM)
			b.add_theme_color_override("font_hover_color", DS.PALETTE.TEXT_DIM)
			b.tooltip_text = "You do not have enough money to buy that land"
		vb.add_child(b)
	add_child(popup)
	popup.popup_hide.connect(func(): popup.queue_free())
	popup.popup(Rect2i(Vector2i(anchor.global_position) + Vector2i(0, int(anchor.size.y)), Vector2i(260, 0)))

func _buy_land_amount(land_amount: int) -> void:
	var patches := ceili(float(land_amount) / float(BuildingState.LAND_PATCH_SIZE))
	if patches > 0:
		var cap := TileViewData.tile_max_capacity(_current_tile_data)
		if BuildingState.purchase_tile_land(_current_tile_id, patches, cap):
			Audio.transaction()

func _on_bl_build_pressed() -> void:
	# The construct panel locks to this tile: the catalogue is filtered to what the
	# terrain allows and Confirm builds directly here (no map pick).
	var cp := get_tree().root.find_child("ConstructPanelV2", true, false)
	if cp != null and cp.has_method("open_for_tile"):
		cp.open_for_tile(_current_tile_id, _current_tile_data)
		PanelStack.push(cp)


func _on_infra_add_pressed(internal_name: String, content: Control, button: Button, built_overlay: TextureRect) -> void:
	if internal_name == "" or _current_tile_id == "":
		return
	BuildMode.infrastructure_attempted.emit(internal_name, _current_tile_id)
	# Flash, then cross-fade plus → building icon over 1s to signal "being built".
	var flash := create_tween()
	flash.tween_property(content, "modulate", Color(1.7, 1.7, 1.7, 1.0), 0.12)
	flash.tween_property(content, "modulate", Color(1, 1, 1, 1.0), 0.18)
	if built_overlay.texture != null:
		var fade := create_tween()
		fade.set_parallel(true)
		fade.tween_property(button, "modulate", Color(1, 1, 1, 0), 1.0).set_delay(0.2)
		fade.tween_property(built_overlay, "modulate", Color(1, 1, 1, 1), 1.0).set_delay(0.2)

func _on_infra_pressed(instance: Dictionary, _internal_name: String, _action: String) -> void:
	if not instance.is_empty():
		building_clicked.emit(instance)


func _on_deposit_build(deposit_token: String, good_id: String, anchor: Control) -> void:
	var opts := TileViewData.deposit_build_options(deposit_token)
	if opts.is_empty():
		# Fall back to the construct panel filtered to producers of this good.
		MatchState.show_construct_for_good.emit(good_id)
		return
	if opts.size() == 1:
		# Single option → build it directly on this tile (same as selecting the
		# building+recipe and clicking the tile).
		_build_deposit_option(opts[0])
		return
	# Multiple options → choose one; selecting builds it directly on this tile.
	var menu := PopupMenu.new()
	for i in opts.size():
		var o: Dictionary = opts[i]
		var label := str(o.building_name)
		if str(o.recipe_name) != "":
			label += " · " + str(o.recipe_name)
		menu.add_item(label, i)
	add_child(menu)
	menu.id_pressed.connect(func(idx): _build_deposit_option(opts[idx]))
	menu.close_requested.connect(func(): menu.queue_free())
	menu.popup(Rect2i(Vector2i(anchor.global_position) + Vector2i(0, int(anchor.size.y)), Vector2i(220, 0)))

func _build_deposit_option(opt: Dictionary) -> void:
	# Build directly on the current tile (no interactive placement).
	BuildMode.attempt_direct_build(str(opt.building_id), str(opt.recipe_id), _current_tile_id)

func _go_to_building(instance_id: String) -> void:
	var inst := BuildingState.get_building(instance_id)
	if not inst.is_empty():
		building_clicked.emit(inst)

# --- Warehouse expansion (per-tile storage upgrade, paid in materials) -------

func _commit_warehouse_upgrade(source: String) -> void:
	var res := MatchState.upgrade_warehouse(_current_tile_id, source)
	if bool(res.get("ok", false)):
		_warehouse_expand = false
	else:
		MatchState.request_toast("Warehouse expansion failed: %s" % str(res.get("reason", "unknown")), "warning")
	_refresh_pane("stock")

# --- Tile-wide surplus and logistics controls -------------------------------

## The tile's surplus route on the rotary selector: one icon per route on its arc (click one and the knob
## turns to it; its name is its tooltip), "SURPLUS" printed under it. The routes the player cannot use yet
## are shown, faint, with the reason on hover.
func _make_surplus_knob() -> Control:
	var box := VBoxContainer.new()
	box.name = "SurplusControls"
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	var selected := MatchState.get_sell_surplus_destination(_current_tile_id)
	var routes := [
		{"id": "none", "icon": ROUTE_STOCKPILE_ICON, "name": "Keep in this tile's stockpile", "enabled": true},
	]
	if ResearchState.logistics_progression_active():
		var ok := ResearchState.open_logistics_contracts_available()
		routes.append({"id": "middleman", "icon": ROUTE_MIDDLEMAN_ICON, "enabled": ok,
			"name": "Sell to Local Suppliers" if ok else "Sell to Local Suppliers: needs Open Logistics Contracts"})
	var licensed := ResearchState.global_trade_license_available()
	routes.append({"id": "market", "icon": ROUTE_MARKET_ICON, "enabled": licensed,
		"name": "Sell on the global market through the nearest port" if licensed else "Sell through a port: needs the Government Import/Export License"})
	var knob: Control = RotarySelector.new()
	knob.name = "SurplusKnob"
	knob.knob_size = 118.0
	knob.set("label", "SURPLUS")
	knob.set("label_colour", DS.PALETTE.TEXT)
	knob.call("set_options", routes)
	for i in routes.size():
		var b: Button = (knob.get("option_buttons") as Array)[i]
		# The port route keeps the tutorial's "SellSurplusToggle" spotlight name.
		b.name = "SellSurplusToggle" if routes[i].id == "market" else "Surplus_%s" % str(routes[i].id).capitalize()
		if str(routes[i].id) == selected:
			knob.call("set_value_no_signal", i + 1)
	knob.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	knob.value_changed.connect(func(v: int) -> void:
		MatchState.set_sell_surplus_destination(_current_tile_id, str(routes[v - 1].id))
		_refresh_active_pane.call_deferred())
	box.add_child(knob)
	return box


func _off_white_route_icon(texture: Texture2D) -> Texture2D:
	if texture == null:
		return texture
	var key := texture.resource_path
	if key == "":
		return texture
	if _route_icon_cache.has(key):
		return _route_icon_cache[key] as Texture2D
	var image := texture.get_image()
	if image == null:
		return texture
	image = image.duplicate()
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	image.clear_mipmaps()
	var data := image.get_data()
	var cream := Color(0.995234, 0.930806, 0.763265, 1.0)
	for offset in range(0, data.size(), 4):
		if data[offset + 3] > 0:
			data[offset] = int(round(cream.r * 255.0))
			data[offset + 1] = int(round(cream.g * 255.0))
			data[offset + 2] = int(round(cream.b * 255.0))
	var recoloured := Image.create_from_data(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8, data)
	recoloured.generate_mipmaps()
	var result := ImageTexture.create_from_image(recoloured)
	_route_icon_cache[key] = result
	return result


func _tile_logistics_choice_active(mode: String, side: String, ids: Array) -> bool:
	return preload("res://scripts/middleman_service.gd").tile_policy_active(_current_tile_id, side, mode, ids)

func _apply_tile_logistics_policy(side: String, mode: String, logistics: Dictionary) -> void:
	var ids: Array = logistics.get(side, []) as Array
	if ids.is_empty():
		return
	var apply := func() -> bool:
		var result: Dictionary = preload("res://scripts/middleman_service.gd").apply_tile_policy(_current_tile_id, side, mode, ids)
		if not bool(result.get("ok", false)):
			MatchState.request_toast(str(result.get("reason", "")), "warning")
			return false
		_refresh_pane("stock")
		return true
	var confirmation := preload("res://scripts/logistics_confirmation.gd")
	confirmation.request(self, "middleman" if mode == "middleman" else "managed", apply, func() -> void: _refresh_pane("stock"),
		{"side": side, "destination": mode if mode in ["market", "stockpile"] else "", "tile": _current_tile_id})


## Shared entry point for the bay's goods and stockpile notifications.
func select_stock_good(good_id: String) -> void:
	var qty := int(Stockpile.get_tile_totals(_current_tile_id).get(good_id, 0))
	if qty <= 0:
		return
	_stock_sel = {"good_id": good_id, "name": Catalog.get_display_name(good_id), "qty": qty}
	_stock_qty = qty
	_stock_dest = ""
	_stock_recurring = false
	_select_tab("stock")
	_reveal_stock_actions.call_deferred()

func _reveal_stock_actions() -> void:
	await get_tree().process_frame
	if not visible or _active_tab != "stock":
		return
	var card := _pane_host.find_child("StockGoodActions", true, false) as Control
	if is_instance_valid(card) and is_instance_valid(_body_scroll):
		_body_scroll.ensure_control_visible(card)


## Called by world_map once the player picks a destination tile (or "" to cancel).
func on_destination_picked(tile_id: String) -> void:
	if tile_id != "" and tile_id != _current_tile_id:
		_stock_dest = tile_id
	if _active_tab == "stock":
		_refresh_pane("stock")

func _confirm_stock_action() -> void:
	if _stock_sel.is_empty() or _stock_dest == "":
		return
	var gid := str(_stock_sel.get("good_id", ""))
	var good_name := str(_stock_sel.get("name", ""))
	var qty := clampi(_stock_qty, 1, int(_stock_sel.get("qty", 1)))
	var goods := {gid: qty}
	var recurring := _stock_recurring
	# Fluids move ONLY through pipelines: explain the blocked route instead of
	# a silent failure (sells) or an optimistic success toast (moves).
	if Catalog.requires_pipeline(gid):
		var fluid_route := (TransportService.route_to_nearest_port(_current_tile_id, gid)
			if (_stock_dest == MARKET_DEST or _stock_dest == SPECIAL_ORDER_DEST)
			else TransportService.route(_current_tile_id, _stock_dest, gid))
		if not TransportService.route_is_reachable(fluid_route):
			MatchState.request_toast(
				"%s can only move through pipelines or reinforced pipelines — connect this tile with pipes first." % good_name,
				"warning")
			return
	if _stock_dest == MARKET_DEST:
		var locked := preload("res://scripts/middleman_service.gd").route_lock("market")
		if locked != "":
			MatchState.request_toast("Selling to the global market. " + locked, "warning")
			return
		MatchState.queue_sell(_current_tile_id, goods)
		if recurring:
			MatchState.add_recurring_sell(_current_tile_id, goods)
		MatchState.request_toast("%s %d %s to market" % ["Recurring sell of" if recurring else "Selling", qty, good_name], "success")
	elif _stock_dest == SPECIAL_ORDER_DEST:
		var order := SpecialOrderState.get_active_order_for_good(gid)
		var order_id := str(order.get("id", ""))
		qty = mini(qty, SpecialOrderState.remaining_uncommitted(order))
		var result := SpecialOrderState.queue_from_tile(_current_tile_id, order_id, gid, qty)
		if result.is_empty():
			MatchState.request_toast("No active special order can take %s" % good_name, "warning")
			return
		MatchState.request_toast("Sending %d %s to special order" % [int(result.get("total_qty", qty)), good_name], "success")
	else:
		TransportState.queue_move(_current_tile_id, _stock_dest, goods)
		if recurring:
			TransportState.add_recurring_move(_current_tile_id, _stock_dest, goods)
		MatchState.request_toast("%s %d %s to %s" % ["Recurring move of" if recurring else "Moving", qty, good_name, Catalog.tile_label(_stock_dest)], "success")
	_stock_sel = {}
	_stock_dest = ""
	_stock_recurring = false
	_refresh_pane("stock")


# A rectangle in the land-size chart was clicked — open that building's detail panel.
func _on_chart_segment_clicked(instance_id: String) -> void:
	_open_building_or_construction(instance_id)

# Open the building detail panel for either a finished building OR a construction
# project (the detail panel renders an "under construction" variation for the latter).
func _open_building_or_construction(instance_id: String) -> void:
	if instance_id == "":
		return
	var inst := BuildingState.get_building(instance_id)
	if not inst.is_empty():
		building_clicked.emit(inst)
		return
	var project: Dictionary = Construction.construction_projects.get(instance_id, {})
	if not project.is_empty():
		building_clicked.emit({
			"instance_id": instance_id,
			"building_id": str(project.get("building_id", "")),
			"recipe_id": str(project.get("recipe_id", "")),
			"tile_id": str(project.get("tile_id", "")),
		})


# ─────────────────────────────────────────────────────────────────────────────
# Small helpers
# ─────────────────────────────────────────────────────────────────────────────


func _survey_status_for_tile(tile_data: Dictionary) -> String:
	var explicit := str(tile_data.get("survey_status", "")).strip_edges()
	if explicit != "":
		return explicit
	match MatchState.survey_status(str(tile_data.get("id", "")), str(tile_data.get("type", ""))):
		"surveyed": return "Surveyed"
		"partial": return "Partially surveyed"
		_: return "Unsurveyed"
