extends PanelContainer
## The Tile View Panel — tabbed modular dashboard.
##
## Pattern: a persistent banner, then a row of four STATUS METRIC TILES that act
## as the tab bar (each shows a status pip + a status-coloured headline number),
## then the selected tab's body. The Stockpile pane renders stored goods as a
## vertical bar chart.
##
## All numbers come from TileViewData (shared with the classic panel). DS theme
## fonts/colours are used throughout.

signal building_clicked(building: Dictionary)
## The survey call-to-action was clicked — opens the survey dialog for this tile.
signal survey_requested(tile_data: Dictionary)
## Asks the host (world_map) to enter map "pick a destination tile" mode; the
## result comes back via on_destination_picked().
signal pick_destination_requested()

const TileViewData := preload("res://scripts/tile_view_data.gd")
const INFRA_DIAL := preload("res://scripts/infra_dial.gd")
const LAND_BAR := preload("res://scripts/land_bar.gd")
const LAND_CHART := preload("res://scripts/land_chart.gd")
const GoodIcons := preload("res://scripts/good_icons.gd")
const UIFonts := preload("res://scripts/ui_fonts.gd")
const BuildingNaming := preload("res://scripts/building_naming.gd")
const UIHelpers := preload("res://scripts/ui_helpers.gd")
const SellSurplusDialog := preload("res://scripts/sell_surplus_dialog.gd")
const GOODS_FRAME := preload("res://assets/ui/goods_frame.tres")
const PLUS_ICON_PATH := "res://assets/icons/ui_icons/plus_off_white.png"
# Classic TileInfoPanel footprint is 760×630; this is 120px narrower, 100px taller.
const TABS := [
	{"id": "bl", "label": "Buildings"},
	{"id": "power", "label": "Power"},
	{"id": "prod", "label": "Goods"},
	{"id": "stock", "label": "Stockpile"},
]
const CHART_HEIGHT := 170.0
const STOCK_BAR_WIDTH := 60.0
const STOCK_ICON_SIZE := 60.0
const STOCK_MAX_BARS := 7
const STOCK_NAME_MAX_CHARS := 15

var _plus_icon: Texture2D = null

# Stockpile "Move or Sell" contextual menu state (persists across pane rebuilds).
const MARKET_DEST := "__market__"
const SPECIAL_ORDER_DEST := "__special_order__"
var _stock_sel: Dictionary = {}   # {good_id, name, qty} of the selected good, or {}
var _stock_qty: int = 0
var _stock_dest: String = ""      # "" = none, MARKET_DEST, SPECIAL_ORDER_DEST, or a tile_id
var _stock_recurring: bool = false

# "Sell all Surplus" confirmation. The suppress flag is session-wide (static) so
# "Do not show again for other tiles" carries across every tile's panel.
static var _skip_sell_surplus_confirm := false
var _sell_surplus_layer: CanvasLayer = null
var _sell_surplus_dialog = null
var _pending_surplus_tile: String = ""
var _pending_surplus_toggle: CheckBox = null

var _current_tile_data: Dictionary = {}
var _current_tile_id: String = ""
var _active_tab: String = "bl"

var _title_label: Label = null
var _chips_row: VBoxContainer = null
var _drag_delta := Vector2.ZERO   # user-applied offset from dragging the title bar
var _dragging := false
var _land_chart: Control = null
var _rail_owned_label: Label = null
var _rail_total_label: Label = null
var _density_note: Label = null
var _land_rail: VBoxContainer = null
var _rail_expanded := false
var _banner_texture: TextureRect = null
var _rural_banner_tex: Texture2D = null
const RURAL_BANNER_PATH := "res://assets/tile_banners/rural_banner.jpg"
var _tiles: Dictionary = {}        # tab_id -> {root, pip, metric, unit}
var _panes: Dictionary = {}        # tab_id -> Control (body container)
var _pane_host: VBoxContainer = null
var _show_player_buildings_only := false
var _player_only_checkbox: CheckBox = null

func _enter_tree() -> void:
	# the hex grid overlay mirrors this panel's tile as its brass selection
	add_to_group("tile_view_panel")

func _ready() -> void:
	_apply_anchors()
	_apply_panel_style()
	_apply_token_theme()
	_build_ui()
	# Live data refresh while open.
	MatchState.building_added.connect(func(_i): _refresh_if_visible())
	MatchState.building_removed.connect(func(_i): _refresh_if_visible())
	MatchState.building_owner_changed.connect(func(_i): _refresh_if_visible())
	MatchState.tile_land_owned_changed.connect(func(_t): _refresh_if_visible())
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
	MatchState.transport_shipments_changed.connect(_refresh_if_visible)
	# Money changing (loan taken, building sold, etc.) can move a build above/below
	# its affordability threshold — refresh so power build buttons re-enable.
	MatchState.money_changed.connect(func(_m): _refresh_if_visible())
	visible = false

func _apply_anchors() -> void:
	# Rail is 75px collapsed / 200px expanded; widen the whole panel to match.
	var panel_w := 780.0 if _rail_expanded else 655.0
	custom_minimum_size = Vector2(panel_w, 0)
	anchor_left = 1.0
	anchor_right = 1.0
	offset_left = -(panel_w + 30.0) + _drag_delta.x
	offset_top = 30.0 + _drag_delta.y
	offset_right = -30.0 + _drag_delta.x
	offset_bottom = 900.0 + _drag_delta.y  # taller panel (top pinned near the screen top, so it grows down)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN

const TILE_MODAL_FRAME_PATH := "res://assets/ui/tile_modal_pipe_frame.png"
const TILE_MODAL_FRAME_SLICE := 32.0
const TILE_MODAL_FRAME_OUTSET := 11.0

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
	t.set_font("font", "Caption", UIFonts.PLEX)
	t.set_font_size("font_size", "Caption", 10)
	theme = t

func _apply_panel_style() -> void:
	# Same 9-slice pipe frame as the classic TVP.
	var tex := load(TILE_MODAL_FRAME_PATH) as Texture2D
	if tex == null:
		var fallback := StyleBoxFlat.new()
		fallback.bg_color = Color(DS.PALETTE.BG_PANEL, 0.99)
		fallback.border_color = DS.PALETTE.BORDER_SOFT
		fallback.set_border_width_all(1)
		fallback.set_corner_radius_all(14)
		fallback.set_content_margin_all(18)
		add_theme_stylebox_override("panel", fallback)
		return
	var style := StyleBoxTexture.new()
	style.texture = tex
	style.draw_center = true
	style.texture_margin_left = TILE_MODAL_FRAME_SLICE
	style.texture_margin_top = TILE_MODAL_FRAME_SLICE
	style.texture_margin_right = TILE_MODAL_FRAME_SLICE
	style.texture_margin_bottom = TILE_MODAL_FRAME_SLICE
	style.expand_margin_left = TILE_MODAL_FRAME_OUTSET
	style.expand_margin_top = TILE_MODAL_FRAME_OUTSET
	style.expand_margin_right = TILE_MODAL_FRAME_OUTSET
	style.expand_margin_bottom = TILE_MODAL_FRAME_OUTSET
	# Inset the content inside the pipe frame (classic uses a 20px margin container).
	style.content_margin_left = 18.0
	style.content_margin_top = 18.0
	style.content_margin_right = 18.0
	style.content_margin_bottom = 18.0
	add_theme_stylebox_override("panel", style)

# ─────────────────────────────────────────────────────────────────────────────
# UI construction
# ─────────────────────────────────────────────────────────────────────────────
func _build_ui() -> void:
	# Outer row: land rail on the left, main panel content on the right.
	var outer := HBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	add_child(outer)
	outer.add_child(_build_land_rail())
	outer.add_child(VSeparator.new())

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 11)
	outer.add_child(root)

	root.add_child(_build_header())
	root.add_child(_build_banner())
	root.add_child(_build_tab_bar())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_pane_host = VBoxContainer.new()
	_pane_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_pane_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_pane_host)
	for tab in TABS:
		var pane := VBoxContainer.new()
		pane.add_theme_constant_override("separation", 9)
		pane.size_flags_vertical = Control.SIZE_EXPAND_FILL
		pane.visible = false
		_pane_host.add_child(pane)
		_panes[tab.id] = pane

func _build_land_rail() -> VBoxContainer:
	_land_rail = VBoxContainer.new()
	_land_rail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_land_rail.add_theme_constant_override("separation", 6)
	_populate_land_rail()
	return _land_rail

func _populate_land_rail() -> void:
	for c in _land_rail.get_children():
		_land_rail.remove_child(c)
		c.queue_free()
	_rail_owned_label = null
	_rail_total_label = null
	_land_rail.custom_minimum_size = Vector2(200 if _rail_expanded else 75, 0)

	# Expand / Collapse toggle (top row).
	var toggle := Button.new()
	toggle.text = "Collapse ›" if _rail_expanded else "‹ Expand"
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.add_theme_font_size_override("font_size", 13)  # one size up
	toggle.pressed.connect(_toggle_rail)
	_land_rail.add_child(toggle)

	# Chart fills all leftover space. Expanded: pushed to the left (less padding).
	_land_chart = LAND_CHART.new()
	_land_chart.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN if _rail_expanded else Control.SIZE_SHRINK_CENTER
	_land_chart.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_land_chart.segment_clicked.connect(_on_chart_segment_clicked)
	_land_rail.add_child(_land_chart)

	if _rail_expanded:
		# built | buyable | max, beneath the chart (like the tile overview).
		_rail_total_label = Label.new()
		_rail_total_label.theme_type_variation = &"Numeric"
		_rail_total_label.add_theme_font_size_override("font_size", 12)
		_rail_total_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_rail_total_label.custom_minimum_size = Vector2(0, 18)
		_land_rail.add_child(_rail_total_label)
		var caption := Label.new()
		caption.text = "BUILT | BUYABLE | MAX"
		caption.theme_type_variation = &"Caption"
		caption.add_theme_font_size_override("font_size", 9)
		caption.add_theme_color_override("font_color", DS.PALETTE.TEXT_MUTED)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_land_rail.add_child(caption)
		_density_note = Label.new()
		_density_note.text = "⚠ +50% build cost — high density"
		_density_note.theme_type_variation = &"Body"  # same face/size as the Rural/Urban chips
		_density_note.add_theme_font_size_override("font_size", 13)
		_density_note.add_theme_color_override("font_color", DS.PALETTE.WARN)
		_density_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_density_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_density_note.visible = false  # only when built footprint crosses 100
		_land_rail.add_child(_density_note)
	else:
		_rail_owned_label = Label.new()
		_rail_owned_label.theme_type_variation = &"Numeric"
		_rail_owned_label.add_theme_font_size_override("font_size", 12)
		_rail_owned_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_rail_owned_label.custom_minimum_size = Vector2(0, 18)
		_land_rail.add_child(_rail_owned_label)
		var legend := Label.new()
		legend.text = "OWNED / BUYABLE"
		legend.theme_type_variation = &"Caption"
		legend.add_theme_font_size_override("font_size", 9)
		legend.add_theme_color_override("font_color", DS.PALETTE.TEXT_MUTED)
		legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_land_rail.add_child(legend)

	var buy := _make_action_button("Buy Land")
	buy.add_theme_font_size_override("font_size", 14)  # one size up
	buy.pressed.connect(func(): _on_buy_land_pressed(buy))
	_land_rail.add_child(buy)
	_refresh_land_rail()

func _toggle_rail() -> void:
	_rail_expanded = not _rail_expanded
	_apply_anchors()
	_populate_land_rail()

func _refresh_land_rail() -> void:
	if _land_chart == null or _current_tile_id == "":
		return
	var data := TileViewData.land_chart_data(_current_tile_id, _current_tile_data)
	if _rail_expanded:
		var totals := TileViewData.land_totals(_current_tile_id, _current_tile_data)
		if _rail_total_label != null:
			_rail_total_label.text = "%d | %d | %d" % [int(totals.built), int(totals.buyable), int(totals.max)]
		if _density_note != null:
			_density_note.visible = int(totals.built) > 100  # only once built crosses 100
		_land_chart.configure(data.segments, float(data.type_cap), int(data.type_cap), true, int(data.owned), int(totals.buyable))
	else:
		var owned := int(data.owned)
		var buyable := maxi(0, int(data.max_possible) - owned)
		if _rail_owned_label != null:
			_rail_owned_label.text = "%d / %d" % [owned, buyable]
		_land_chart.configure(data.segments, float(data.axis_max), int(data.max_possible), false)

func _build_header() -> HBoxContainer:
	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.custom_minimum_size = Vector2(0, 40)  # tall grab strip (title + padding)
	header.mouse_filter = Control.MOUSE_FILTER_STOP  # capture drags on the title bar
	header.mouse_default_cursor_shape = Control.CURSOR_MOVE
	header.gui_input.connect(_on_header_drag)
	_title_label = Label.new()
	_title_label.theme_type_variation = &"Title"
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE  # let the header get the drag
	header.add_child(_title_label)
	var close_button := Button.new()
	close_button.text = "✕"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(hide)
	header.add_child(close_button)
	return header

# Drag the whole panel by its title bar.
func _on_header_drag(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_drag_delta += event.relative
		_apply_anchors()
		accept_event()

const BANNER_HEIGHT := 135      # row height; image fills it, pills fill the rest
const BANNER_IMG_H := 135       # image as tall as the container…
const BANNER_IMG_W := 240       # …and 16:9 (240×135)
const BANNER_PILLS_WIDTH := 200 # right rail of pills

func _build_banner() -> HBoxContainer:
	# Fixed 192×108 banner image (left) + a vertical rail of survey/terrain/deposit
	# pills (right).
	var banner_row := HBoxContainer.new()
	banner_row.add_theme_constant_override("separation", 8)
	banner_row.custom_minimum_size = Vector2(0, BANNER_HEIGHT)

	var banner := PanelContainer.new()
	banner.custom_minimum_size = Vector2(BANNER_IMG_W, BANNER_IMG_H)
	banner.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	banner.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	banner.clip_contents = true  # rounds the image corners
	var bs := StyleBoxFlat.new()
	bs.bg_color = DS.PALETTE.BG_HIGHLIGHT
	bs.border_color = DS.PALETTE.BORDER_SOFT
	bs.set_border_width_all(1)
	bs.set_corner_radius_all(10)
	bs.set_content_margin_all(0)  # image fills edge-to-edge; container rounds it
	banner.add_theme_stylebox_override("panel", bs)

	# The tile render fills the fixed box (cover-fit, cropping any overflow). The
	# banner stays exactly BANNER_IMG_W×BANNER_IMG_H — it never widens or shrinks
	# with the panel's content.
	var inner := Control.new()
	inner.custom_minimum_size = Vector2(BANNER_IMG_W, BANNER_IMG_H)
	inner.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	inner.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	banner.add_child(inner)
	_banner_texture = TextureRect.new()
	_banner_texture.set_anchors_preset(Control.PRESET_FULL_RECT)
	_banner_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_banner_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_banner_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(_banner_texture)
	banner_row.add_child(banner)

	_chips_row = VBoxContainer.new()
	_chips_row.custom_minimum_size = Vector2(BANNER_PILLS_WIDTH, 0)
	_chips_row.add_theme_constant_override("separation", 6)
	banner_row.add_child(_chips_row)
	return banner_row

func _build_tab_bar() -> PanelContainer:
	var wrap := PanelContainer.new()
	var ws := StyleBoxFlat.new()
	ws.bg_color = DS.PALETTE.BG_INSET
	ws.set_corner_radius_all(11)
	ws.set_content_margin_all(5)
	wrap.add_theme_stylebox_override("panel", ws)

	var grid := GridContainer.new()
	grid.columns = TABS.size()
	grid.add_theme_constant_override("h_separation", 5)
	wrap.add_child(grid)

	for tab in TABS:
		grid.add_child(_make_tile(tab.id, tab.label))
	return wrap

func _make_tile(tab_id: String, label_text: String) -> PanelContainer:
	var tile := PanelContainer.new()
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.custom_minimum_size = Vector2(0, 62)  # 10px shorter
	tile.mouse_filter = Control.MOUSE_FILTER_STOP
	tile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tile.gui_input.connect(func(e): _on_tile_input(e, tab_id))
	tile.mouse_entered.connect(func(): _set_tile_hover(tab_id, true))
	tile.mouse_exited.connect(func(): _set_tile_hover(tab_id, false))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	tile.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(vbox)

	# Tab NAME — the prominent, always-visible label (wraps so long names fit).
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 4)
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var name_label := Label.new()
	name_label.text = label_text
	name_label.theme_type_variation = &"Numeric"  # semibold font
	name_label.add_theme_font_size_override("font_size", 14)  # one token step up (was 12)
	name_label.add_theme_color_override("font_color", DS.PALETTE.ACCENT)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(name_label)
	vbox.add_child(name_row)

	var metric_row := HBoxContainer.new()
	metric_row.add_theme_constant_override("separation", 3)
	metric_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var metric := Label.new()
	metric.theme_type_variation = &"Numeric"
	metric.add_theme_font_size_override("font_size", 17)
	metric_row.add_child(metric)
	var unit := Label.new()
	unit.theme_type_variation = &"Caption"
	unit.add_theme_font_size_override("font_size", 9)
	unit.add_theme_color_override("font_color", DS.PALETTE.TEXT_DIM)
	unit.size_flags_vertical = Control.SIZE_SHRINK_END
	metric_row.add_child(unit)
	vbox.add_child(metric_row)

	_tiles[tab_id] = {"root": tile, "color": DS.PALETTE.TEXT_DIM, "metric": metric, "unit": unit, "hover": false}
	return tile

func _set_tile_hover(tab_id: String, hovered: bool) -> void:
	if _tiles.has(tab_id):
		_tiles[tab_id]["hover"] = hovered
		_apply_tile_styles()

func _on_tile_input(event: InputEvent, tab_id: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_select_tab(tab_id)
		accept_event()

func _select_tab(tab_id: String) -> void:
	_active_tab = tab_id
	for tab in TABS:
		var id: String = tab.id
		_panes[id].visible = (id == tab_id)
	_apply_tile_styles()
	_refresh_active_pane()

# ─────────────────────────────────────────────────────────────────────────────
# Public entry point
# ─────────────────────────────────────────────────────────────────────────────
func show_tile(tile_data: Dictionary) -> void:
	_current_tile_data = tile_data
	_current_tile_id = str(tile_data.get("id", ""))
	_active_tab = "bl"  # always land on the Buildings tab when a new tile is selected
	_refresh_banner(tile_data)
	_refresh_land_rail()
	_refresh_tiles()
	_select_tab(_active_tab)
	visible = true
	PanelStack.push(self)

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not visible:
		PanelStack.remove(self)

# Coalesced (notification_bell pattern): money_changed/stockpile_changed fire
# per transaction during PROCESS — dozens to hundreds of times in one burst —
# and each used to tear down and rebuild the entire pane. Signals now defer ONE
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
	_refresh_banner(_current_tile_data)  # keeps built|buyable|max + survey live
	_refresh_land_rail()
	_refresh_tiles()
	_refresh_active_pane()

# ─────────────────────────────────────────────────────────────────────────────
# Banner
# ─────────────────────────────────────────────────────────────────────────────
func _refresh_banner(tile_data: Dictionary) -> void:
	var tid := str(tile_data.get("id", ""))
	_title_label.text = Catalog.tile_label(tid)
	_refresh_banner_image(tile_data)
	for child in _chips_row.get_children():
		child.queue_free()
	# Vertical pill rail to the right of the banner image: survey first, then terrain,
	# then deposits (always named "<x> deposit").
	var survey := _survey_status_for_tile(tile_data)
	if survey == "Surveyed":
		_chips_row.add_child(_make_chip(survey, DS.PALETTE.OK))
	else:
		# Not (fully) surveyed → a double-height, full-width call-to-action button.
		_chips_row.add_child(_make_survey_button(survey))
	# Deposits, gated by survey status (unknown / "size ?" / actual size; water always shown).
	var gated: Dictionary = TileViewData.survey_gated_deposits(str(tile_data.get("id", "")), tile_data)
	# Terrain type and Pure Water sit together on one row; other deposits go below.
	var terrain := str(tile_data.get("type", "")).strip_edges().capitalize()
	var terrain_row := HBoxContainer.new()
	terrain_row.add_theme_constant_override("separation", 6)
	terrain_row.add_child(_make_chip(terrain if terrain != "" else "—", DS.PALETTE.TEXT_MUTED))
	var other_rows: Array = []
	for row in gated.rows:
		if bool(row.get("is_water", false)):
			terrain_row.add_child(_make_chip(str(row.chip_label), DS.PALETTE.TEXT_MUTED))
		else:
			other_rows.append(row)
	_chips_row.add_child(terrain_row)
	if gated.status == "unsurveyed":
		_chips_row.add_child(_make_chip("Deposits Unknown", DS.PALETTE.TEXT_MUTED))
	for row in other_rows:
		_chips_row.add_child(_make_chip(str(row.chip_label), DS.PALETTE.TEXT_MUTED))
	# built | buyable | max — one row, same figures as the land rail.
	var totals := TileViewData.land_totals(_current_tile_id, _current_tile_data)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chips_row.add_child(spacer)
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 4)
	stats.add_child(_make_land_stat("built", int(totals.built)))
	stats.add_child(_make_pipe())
	stats.add_child(_make_land_stat("buyable", int(totals.buyable)))
	stats.add_child(_make_pipe())
	stats.add_child(_make_land_stat("max", int(totals.max)))
	_chips_row.add_child(stats)

# Survey call-to-action: a darker section showing the status + hint, with a DS
# "Survey" button underneath. The button opens the survey dialog.
func _make_survey_button(status: String) -> Control:
	var section := PanelContainer.new()
	section.size_flags_horizontal = Control.SIZE_FILL
	section.custom_minimum_size = Vector2(0, 72)  # status + hint + a skinny Survey button
	var sb := StyleBoxFlat.new()
	sb.bg_color = DS.PALETTE.BG_CARD  # darker section background
	sb.border_color = Color(DS.PALETTE.WARN, 0.6)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	section.add_theme_stylebox_override("panel", sb)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 4)
	section.add_child(col)
	var top := Label.new()
	top.text = status if status != "" else "Survey"
	top.theme_type_variation = &"Caption"
	top.add_theme_font_size_override("font_size", 12)
	top.add_theme_color_override("font_color", DS.PALETTE.WARN)
	top.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(top)
	var sub := Label.new()
	sub.text = "Surveying will reveal deposits"
	sub.theme_type_variation = &"Caption"
	sub.add_theme_font_size_override("font_size", 9)
	sub.add_theme_color_override("font_color", DS.PALETTE.TEXT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(sub)
	# Same DS button as the "Build" action (matching height), bluish-grey metal edges.
	var btn := _make_action_button("Survey")
	btn.pressed.connect(func(): survey_requested.emit(_current_tile_data))
	if MatchState.is_tile_surveyable(_current_tile_id):
		btn.tooltip_text = "Survey this tile"
	else:
		btn.disabled = true
		btn.tooltip_text = "This tile is out of survey range. Survey more tiles to extend your range."
	col.add_child(btn)
	return section

# ─────────────────────────────────────────────────────────────────────────────
# Metric tiles
# ─────────────────────────────────────────────────────────────────────────────
func _refresh_tiles() -> void:
	var power := TileViewData.power_summary(_current_tile_id)
	var bl := TileViewData.buildings_land_summary(_current_tile_id, _current_tile_data)
	var prod := TileViewData.production_summary(_current_tile_id)
	var stock := TileViewData.stockpile_summary(_current_tile_id)

	_set_tile("power", power.status, _power_metric(power), "/turn")
	_set_tile("bl", bl.status, _bl_metric(bl), _bl_unit(bl))
	_set_tile("prod", prod.status, "£%d" % roundi(prod.net_value), "/turn")
	_set_tile("stock", stock.status, _stock_metric(stock), "%d/%d" % [stock.used, stock.capacity])
	_apply_tile_styles()

func _power_metric(power: Dictionary) -> String:
	if power.status == "muted":
		return "0"
	var net := int(power.net)
	return "%+d" % net

func _bl_metric(bl: Dictionary) -> String:
	if int(bl.problems) > 0:
		return str(int(bl.problems))
	if int(bl.stalled) > 0:
		return str(int(bl.stalled))
	return str(int(bl.count))

func _bl_unit(bl: Dictionary) -> String:
	if int(bl.problems) > 0:
		return "problem"
	if int(bl.stalled) > 0:
		return "stalled"
	return "buildings"

func _stock_metric(stock: Dictionary) -> String:
	if stock.is_full:
		return "FULL"
	return "%d%%" % roundi(float(stock.pct) * 100.0)

func _set_tile(tab_id: String, status: String, metric_text: String, unit_text: String) -> void:
	var t: Dictionary = _tiles[tab_id]
	var color := _status_color(status)
	t["color"] = color
	(t.metric as Label).text = metric_text
	(t.metric as Label).add_theme_color_override("font_color", color)
	(t.unit as Label).text = unit_text

func _apply_tile_styles() -> void:
	for tab in TABS:
		var id: String = tab.id
		var t: Dictionary = _tiles[id]
		var active := (id == _active_tab)
		var hovered: bool = bool(t.get("hover", false)) and not active
		var color: Color = t.get("color", DS.PALETTE.TEXT_DIM)
		var style := StyleBoxFlat.new()
		style.bg_color = Color(color, 0.16) if color != DS.PALETTE.TEXT_DIM else DS.PALETTE.BG_CARD
		if hovered:
			style.bg_color = DS.PALETTE.BG_HIGHLIGHT  # hover state for non-selected tabs
		style.set_corner_radius_all(9)
		style.set_content_margin_all(0)
		style.border_color = DS.PALETTE.ACCENT if active else (Color(DS.PALETTE.ACCENT, 0.4) if hovered else Color(color, 0.0))
		style.set_border_width_all(2 if active else (1 if hovered else 0))
		(t.root as PanelContainer).add_theme_stylebox_override("panel", style)

# ─────────────────────────────────────────────────────────────────────────────
# Pane dispatch
# ─────────────────────────────────────────────────────────────────────────────
func _refresh_active_pane() -> void:
	_refresh_pane(_active_tab)

func _refresh_pane(tab_id: String) -> void:
	var pane: VBoxContainer = _panes[tab_id]
	for child in pane.get_children():
		child.queue_free()
	match tab_id:
		"power": _build_power_pane(pane)
		"bl": _build_bl_pane(pane)
		"prod": _build_prod_pane(pane)
		"stock": _build_stock_pane(pane)

const POWER_BUILDS := [
	["Power Plant (Coal)", "coal_power", "coal"],
	["Power Plant (Processed Oil)", "coal_power", "processed_oil"],
	["Power Plant (Biomass)", "coal_power", "biomass"],
	["Solar Farm", "solar_farm", ""],
	["Wind Farm", "onshore_wind_farm", ""],
]
const POWER_INTERMITTENCY := [
	["Battery Storage", "battery", ""],
	["Thermal Battery", "heat_battery", ""],
]

# --- Power pane -------------------------------------------------------------
func _build_power_pane(pane: VBoxContainer) -> void:
	var power := TileViewData.power_summary(_current_tile_id)
	var produced := int(power.produced)
	var consumed := int(power.consumed)
	var net := int(power.net)
	var connected: bool = power.get("connected", false)
	var grid_name := str(power.get("grid_name", ""))

	pane.add_child(_make_power_stat("Production this turn", "+%d ⚡" % produced, DS.PALETTE.OK))
	pane.add_child(_make_power_stat("Consumption this turn", "−%d ⚡" % consumed, DS.PALETTE.DANGER))
	var net_text := "%+d ⚡" % net
	if connected and net != 0:
		net_text += "  from grid" if net < 0 else "  to grid"
	pane.add_child(_make_power_stat("Net power", net_text, _status_color(power.status)))

	_build_intermittency_rows(pane)

	pane.add_child(HSeparator.new())

	# Grid row: name on the left, a "Go To" link (opens the Power map mode) right.
	var grid_row := HBoxContainer.new()
	var grid_lbl := Label.new()
	grid_lbl.text = "Grid: %s" % (grid_name if grid_name != "" else "None — not connected (no cables)")
	grid_lbl.theme_type_variation = &"Body"
	grid_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_row.add_child(grid_lbl)
	var goto := Button.new()
	goto.text = "Go To →"
	goto.focus_mode = Control.FOCUS_NONE
	goto.flat = true
	goto.add_theme_color_override("font_color", DS.PALETTE.ACCENT)
	goto.add_theme_color_override("font_hover_color", DS.PALETTE.ACCENT)
	goto.add_theme_font_size_override("font_size", 12)
	goto.pressed.connect(_on_power_goto)
	grid_row.add_child(goto)
	pane.add_child(grid_row)

	pane.add_child(_make_section_title("Build more power production", "", "ok"))
	for spec in POWER_BUILDS:
		pane.add_child(_make_power_build_item(spec))

	if TileViewData.grid_has_intermittent():
		pane.add_child(_make_section_title("Reduce intermittency", "", "ok"))
		for spec in POWER_INTERMITTENCY:
			pane.add_child(_make_power_build_item(spec))

func _make_power_stat(label_text: String, value_text: String, color: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 22)
	var l := Label.new()
	l.text = label_text + ":"
	l.theme_type_variation = &"Body"
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var v := Label.new()
	v.text = value_text
	v.theme_type_variation = &"Numeric"
	v.add_theme_font_size_override("font_size", 14)
	v.add_theme_color_override("font_color", color)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(v)
	return row

# Green-power + intermittency rows for this tile (data from the post-cascade allocation).
# Shown only when the tile actually touches green power.
func _build_intermittency_rows(pane: VBoxContainer) -> void:
	var im: Dictionary = Production.get_tile_intermittency(_current_tile_id)
	if im.is_empty():
		return
	var green_prod := int(im.get("green_produced", 0))
	var green_cons := int(round(float(im.get("green_consumed", 0.0))))
	var battery_cap := int(im.get("battery_cap", 0))
	var affected: Array = im.get("affected", [])
	if green_prod <= 0 and green_cons <= 0 and battery_cap <= 0 and affected.is_empty():
		return

	pane.add_child(HSeparator.new())
	pane.add_child(_make_section_header("Green power & intermittency", "", "ok"))

	# Row 1: green power produced | consumed.
	pane.add_child(_make_power_stat("Green produced | consumed", "%d | %d ⚡" % [green_prod, green_cons], DS.PALETTE.OK))

	# Row 2: buildings affected by intermittency.
	var green_int_prod := int(im.get("green_intermittent_produced", 0))
	if affected.size() > 0:
		pane.add_child(_make_power_stat("Buildings affected by intermittency", "%d" % affected.size(), DS.PALETTE.DANGER))
		var total_cons := int(im.get("total_consumed", 0))
		var total_prod := int(im.get("total_produced", 0))
		var unfirmed_cons := float(im.get("unfirmed_consumed", 0.0))
		var pct_cons := int(round(100.0 * unfirmed_cons / float(total_cons))) if total_cons > 0 else 0
		var pct_prod := int(round(100.0 * float(green_int_prod) / float(total_prod))) if total_prod > 0 else 0
		pane.add_child(_make_power_subrow("%d%% of power consumed affected" % pct_cons, ""))
		pane.add_child(_make_power_subrow("%d%% of power produced affected" % pct_prod, ""))
		for i in mini(3, affected.size()):
			var a: Dictionary = affected[i]
			var iid := str(a.get("iid", ""))
			var live: Dictionary = MatchState.get_building(iid)
			var full_name := BuildingNaming.label_for_tile(_current_tile_id, iid, str(a.get("building_id", "")), str(live.get("recipe_id", "")))
			pane.add_child(_make_power_affected_row(full_name, iid))
		pane.add_child(_make_power_see_more("see more →", "green_intermittent"))
	elif battery_cap > 0 and green_int_prod > 0:
		# Intermittent green is present but fully firmed by the tile's batteries.
		var solved := _make_power_subrow("ALL GREEN POWER COVERED BY BATTERIES. NO INTERMITTENCY.", "")
		(solved.get_child(1) as Label).add_theme_color_override("font_color", DS.PALETTE.OK)
		pane.add_child(solved)
	else:
		pane.add_child(_make_power_stat("Buildings affected by intermittency", "0", DS.PALETTE.TEXT_DIM))

	# Row 3: battery storage table + per-type cell load/unload (deposit model).
	pane.add_child(_make_battery_table(_current_tile_id, green_prod, green_cons))

# Battery storage: Prod / Cons / Max Storage table (Max Storage = the tile's live firming
# capacity), then per-type cell load/unload controls when there is battery housing here.
func _make_battery_table(tile_id: String, prod: int, cons: int) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.add_child(_make_section_header("Battery storage", "", "ok"))
	var slots := MatchState.tile_battery_slots(tile_id)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 24)
	for h in ["Prod", "Cons", "Max Storage"]:
		var hl := Label.new()
		hl.text = h
		hl.theme_type_variation = &"Caption"
		hl.add_theme_color_override("font_color", DS.PALETTE.TEXT_DIM)
		grid.add_child(hl)
	for v in [prod, cons, MatchState.tile_firming_cap(tile_id)]:
		var vl := Label.new()
		vl.text = "%d ⚡" % int(v)
		vl.theme_type_variation = &"Numeric"
		vl.add_theme_color_override("font_color", DS.PALETTE.TEXT)
		grid.add_child(vl)
	box.add_child(grid)
	if slots > 0:
		box.add_child(_make_power_subrow("Storage in use: %d / %d ⚡" % [int(MatchState.tile_loaded_firming(tile_id)), slots], ""))
		for internal in ["lithium_battery", "sodium_battery", "iron_battery"]:
			box.add_child(_make_battery_load_row(tile_id, internal))
	return box

# One battery-type row: name + loaded/in-stock, with Load / Unload links (or a locked hint).
func _make_battery_load_row(tile_id: String, internal: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 22)
	var indent := Control.new()
	indent.custom_minimum_size = Vector2(16, 0)
	row.add_child(indent)
	var gid := str(Catalog.get_good_by_internal_name(internal).get("id", ""))
	var gname := str(Catalog.get_good(gid).get("display_name", internal))
	var lbl := Label.new()
	lbl.theme_type_variation = &"Body"
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not MatchState.is_unlocked(str(EconomyConfig.BATTERY_TYPE_UNLOCK.get(internal, ""))):
		lbl.text = "🔒 %s — %s" % [gname, str(EconomyConfig.BATTERY_TYPE_UNLOCK.get(internal, "locked"))]
		lbl.add_theme_color_override("font_color", DS.PALETTE.TEXT_DIM)
		row.add_child(lbl)
		return row
	var loaded := int(MatchState.get_tile_battery_cells(tile_id).get(gid, 0))
	var stock := Stockpile.get_at_tile(tile_id, gid)
	var free_firming := float(MatchState.tile_battery_slots(tile_id)) - MatchState.tile_loaded_firming(tile_id)
	lbl.text = "%s: %d loaded · %d in stock" % [gname, loaded, stock]
	lbl.add_theme_color_override("font_color", DS.PALETTE.TEXT)
	row.add_child(lbl)
	# load_battery_cells caps by firming headroom + stock; offer the button when either could add.
	var can_load := stock > 0 and free_firming > 0.0
	var load_btn := _make_inline_link("Load", DS.PALETTE.ACCENT if can_load else DS.PALETTE.TEXT_DIM)
	if can_load:
		load_btn.pressed.connect(func() -> void:
			MatchState.load_battery_cells(tile_id, gid, stock)
			_refresh_pane("power"))
	row.add_child(load_btn)
	var unload_btn := _make_inline_link("Unload", DS.PALETTE.ACCENT if loaded > 0 else DS.PALETTE.TEXT_DIM)
	if loaded > 0:
		unload_btn.pressed.connect(func() -> void:
			MatchState.unload_battery_cells(tile_id, gid, loaded)
			_refresh_pane("power"))
	row.add_child(unload_btn)
	return row

# Small flat text-link button.
func _make_inline_link(text: String, color: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.flat = true
	b.add_theme_color_override("font_color", color)
	b.add_theme_color_override("font_hover_color", color)
	b.add_theme_font_size_override("font_size", 12)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return b

# Indented sub-row in normal off-white body text (matches the other power rows), with an
# optional right-aligned numeric value.
func _make_power_subrow(label_text: String, value_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 22)
	var indent := Control.new()
	indent.custom_minimum_size = Vector2(16, 0)
	row.add_child(indent)
	var l := Label.new()
	l.text = label_text
	l.theme_type_variation = &"Body"
	l.add_theme_color_override("font_color", DS.PALETTE.TEXT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	if value_text != "":
		var v := Label.new()
		v.text = value_text
		v.theme_type_variation = &"Numeric"
		v.add_theme_color_override("font_color", DS.PALETTE.TEXT)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(v)
	return row

# Indented affected-building row: full building name (off-white body text) + a right-anchored
# "Go to" link that opens that building's detail panel.
func _make_power_affected_row(name_text: String, instance_id: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 22)
	var indent := Control.new()
	indent.custom_minimum_size = Vector2(16, 0)
	row.add_child(indent)
	var l := Label.new()
	l.text = name_text
	l.theme_type_variation = &"Body"
	l.add_theme_color_override("font_color", DS.PALETTE.TEXT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(l)
	var link := Button.new()
	link.text = "Go to →"
	link.focus_mode = Control.FOCUS_NONE
	link.flat = true
	link.add_theme_color_override("font_color", DS.PALETTE.ACCENT)
	link.add_theme_color_override("font_hover_color", DS.PALETTE.ACCENT)
	link.add_theme_font_size_override("font_size", 12)
	link.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	link.pressed.connect(func(): MatchState.focus_building_requested.emit(instance_id))
	row.add_child(link)
	return row

# Indented underlined-style "link" (flat ACCENT button) → opens the building ledger
# pre-filtered to buildings affected by intermittency.
func _make_power_see_more(text: String, filter_key: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var indent := Control.new()
	indent.custom_minimum_size = Vector2(16, 0)
	row.add_child(indent)
	var link := Button.new()
	link.text = text
	link.focus_mode = Control.FOCUS_NONE
	link.flat = true
	link.add_theme_color_override("font_color", DS.PALETTE.ACCENT)
	link.add_theme_color_override("font_hover_color", DS.PALETTE.ACCENT)
	link.add_theme_font_size_override("font_size", 12)
	link.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	link.pressed.connect(func(): MatchState.building_ledger_filter_requested.emit(filter_key))
	row.add_child(link)
	return row

func _make_power_build_item(spec: Array) -> VBoxContainer:
	var item := VBoxContainer.new()
	item.add_theme_constant_override("separation", 4)
	var opt := TileViewData.power_build_option(str(spec[1]), str(spec[2]), _current_tile_id, _current_tile_data)
	# Button takes only half the row width (truncates if the label is too long).
	var btn_row := HBoxContainer.new()
	var btn := _make_power_build_button(spec, opt)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.size_flags_stretch_ratio = 1.0
	btn.clip_text = true
	btn_row.add_child(btn)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.size_flags_stretch_ratio = 1.0
	btn_row.add_child(spacer)
	item.add_child(btn_row)
	# Recipe card beneath the button, framed like the build-materials dialog.
	var card := _make_recipe_card(str(opt.get("recipe_id", "")))
	if card != null:
		item.add_child(card)
	return item

func _make_power_build_button(spec: Array, opt: Dictionary) -> Button:
	var btn := Button.new()
	btn.text = str(spec[0])
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 14)  # one size up
	if bool(opt.enabled):
		var bid := str(opt.building_id)
		var rid := str(opt.recipe_id)
		btn.pressed.connect(func(): _build_power(bid, rid))
	else:
		# Greyed: darker, muted text, hover tooltip explains why — does nothing.
		var s := StyleBoxFlat.new()
		s.bg_color = DS.PALETTE.BG_PANEL
		s.set_corner_radius_all(6)
		s.content_margin_left = 10
		s.content_margin_right = 10
		s.content_margin_top = 6
		s.content_margin_bottom = 6
		btn.add_theme_stylebox_override("normal", s)
		btn.add_theme_stylebox_override("hover", s)
		btn.add_theme_stylebox_override("pressed", s)
		btn.add_theme_color_override("font_color", DS.PALETTE.TEXT_DIM)
		btn.add_theme_color_override("font_hover_color", DS.PALETTE.TEXT_DIM)
		btn.tooltip_text = str(opt.reason)
	return btn

func _build_power(building_id: String, recipe_id: String) -> void:
	BuildMode.attempt_direct_build(building_id, recipe_id, _current_tile_id)

func _on_power_goto() -> void:
	# Open the Power map mode without closing the TVP.
	MapMode.clear_all()
	MapMode.add_selection(MapMode.Mode.POWER_BALANCE, MapMode.POWER_SENTINEL)

const RECIPE_CELL := 50  # 50% bigger than the dialog's ~33px cells
const RECIPE_POWER_ICON := "res://assets/icons/ui_icons/recipe_power_icon.png"
const RECIPE_ARROW_ICON := "res://assets/icons/ui_icons/recipe_arrow.png"
const RECIPE_ARROW_NAVY := Color(0.0, 0.119856, 0.243095, 1.0)

const RECIPE_BIG_CELL := 48  # larger good icons so they fill the frame better

# Recipe card, framed like the build-materials dialog. Left half = "Cost to build"
# in a 3×2 grid (centred); right half = "Recipe" inputs in a 2×2 grid. Labels in
# Rural font / navy.
func _make_recipe_card(recipe_id: String) -> Control:
	if recipe_id == "":
		return null
	var recipe: Dictionary = Catalog.get_recipe(recipe_id)
	if recipe.is_empty():
		return null
	var in_items := _recipe_input_items(recipe)
	var building: Dictionary = Catalog.get_building(str(recipe.get("building_id", "")))
	var cost_items: Array = []
	for m in building.get("materials", []):
		var gid := str(Catalog.get_good_by_internal_name(str(m.get("name", ""))).get("id", ""))
		if gid != "":
			cost_items.append({"kind": "good", "gid": gid, "qty": int(m.get("qty", 0))})
	if in_items.is_empty() and cost_items.is_empty():
		return null
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", GOODS_FRAME)
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.custom_minimum_size = Vector2(0, 140)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 6)
	pad.add_theme_constant_override("margin_right", 6)
	pad.add_theme_constant_override("margin_top", 6)
	pad.add_theme_constant_override("margin_bottom", 6)
	frame.add_child(pad)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	pad.add_child(row)

	# Left half — cost to build (3×2 grid, centred).
	var left := _make_card_column("Cost to build")
	var left_center := CenterContainer.new()
	left_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if cost_items.is_empty():
		var none := Label.new()
		none.text = "No materials"
		none.add_theme_color_override("font_color", DS.PALETTE.BG_PANEL)
		left_center.add_child(none)
	else:
		left_center.add_child(_make_io_grid(cost_items, 3, RECIPE_BIG_CELL))
	left.add_child(left_center)
	row.add_child(left)

	row.add_child(VSeparator.new())

	# Right half — inputs (2×2 grid, centred).
	var right := _make_card_column("Recipe")
	var right_center := CenterContainer.new()
	right_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_center.add_child(_make_io_grid(in_items, 2, RECIPE_BIG_CELL))
	right.add_child(right_center)
	row.add_child(right)
	return frame

# A fixed-column grid of io cells (cost materials / inputs).
func _make_io_grid(items: Array, cols: int, cell: int) -> Control:
	var grid := GridContainer.new()
	grid.columns = cols
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	for it in items:
		grid.add_child(_make_io_cell(it, cell))
	return grid

func _make_card_column(title: String) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_stretch_ratio = 1.0
	var hdr := Label.new()
	hdr.text = title
	hdr.theme_type_variation = &"Body"  # Rural font…
	hdr.add_theme_font_size_override("font_size", 13)
	hdr.add_theme_color_override("font_color", DS.PALETTE.BG_PANEL)  # …in navy
	hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(hdr)
	return col

# Lay out 1..N good/potential/power cells. Two items → half-size, stacked.
func _make_io_area(items: Array) -> Control:
	if items.size() == 2:
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 4)
		vb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		for it in items:
			vb.add_child(_make_io_cell(it, 30))
		return vb
	if items.size() <= 1:
		var hb := HBoxContainer.new()
		hb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		for it in items:
			hb.add_child(_make_io_cell(it, 46))
		return hb
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 5)
	grid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for it in items:
		grid.add_child(_make_io_cell(it, 30))
	return grid

func _make_io_cell(item: Dictionary, size: int) -> Control:
	match str(item.get("kind", "")):
		"power":
			return _make_power_cell(int(item.get("qty", 0)), size)
		"potential":
			return _make_potential_cell(str(item.get("value", "")), size)
		_:
			var gid := str(item.get("gid", ""))
			if Catalog.get_internal_name(gid) == "power":
				return _make_power_cell(int(item.get("qty", 0)), size)
			return _make_recipe_cell(gid, int(item.get("qty", 0)), size)

# Input descriptors = good inputs + any wind/solar potential.
func _recipe_input_items(recipe: Dictionary) -> Array:
	var items: Array = []
	for inp in recipe.get("inputs", []):
		var gid := _recipe_good_id(inp)
		if gid != "":
			items.append({"kind": "good", "gid": gid, "qty": int(inp.get("qty", 0))})
	var potential := _recipe_potential(recipe)
	if potential != "":
		items.append({"kind": "potential", "value": potential})
	return items

func _recipe_output_items(recipe: Dictionary) -> Array:
	var items: Array = []
	for o in _recipe_card_outputs(recipe):
		items.append({"kind": "good", "gid": str(o.good_id), "qty": int(o.qty)})
	return items

# Navy flow arrow matching the building-detail panel; overlays the power req.
func _make_recipe_arrow(energy_req: int) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(48, RECIPE_CELL)
	holder.size_flags_vertical = Control.SIZE_FILL
	var arrow := TextureRect.new()
	arrow.texture = load(RECIPE_ARROW_ICON)
	arrow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	arrow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	arrow.set_anchors_preset(Control.PRESET_FULL_RECT)
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(arrow)
	if energy_req > 0:
		var badge := PanelContainer.new()
		badge.set_anchors_preset(Control.PRESET_CENTER)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bs := StyleBoxFlat.new()
		bs.bg_color = RECIPE_ARROW_NAVY
		bs.set_corner_radius_all(4)
		bs.content_margin_left = 4
		bs.content_margin_right = 4
		bs.content_margin_top = 1
		bs.content_margin_bottom = 1
		badge.add_theme_stylebox_override("panel", bs)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 1)
		hb.alignment = BoxContainer.ALIGNMENT_CENTER
		badge.add_child(hb)
		var lbl := Label.new()
		lbl.text = str(energy_req)
		lbl.add_theme_font_override("font", UIFonts.mono())
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.add_theme_color_override("font_color", Color.WHITE)
		hb.add_child(lbl)
		var ico := TextureRect.new()
		ico.texture = load(RECIPE_POWER_ICON)
		ico.custom_minimum_size = Vector2(13, 13)
		ico.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ico.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ico.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(ico)
		holder.add_child(badge)
	return holder

# Power output cell — the same lightning the building-detail flow diagram uses.
func _make_power_cell(qty: int, size: int = RECIPE_CELL) -> Control:
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(size, size)
	var tr := TextureRect.new()
	tr.texture = load(RECIPE_POWER_ICON)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.tooltip_text = "Power"
	slot.add_child(tr)
	if qty > 0:
		slot.add_child(_make_recipe_qty_badge(qty, size))
	return slot

func _recipe_grid() -> GridContainer:
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 6)
	g.add_theme_constant_override("v_separation", 6)
	g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return g

# Input cells = good inputs + any wind/solar potential as a text cell.
func _recipe_input_cells(recipe: Dictionary) -> Array:
	var cells: Array = []
	for inp in recipe.get("inputs", []):
		var gid := _recipe_good_id(inp)
		if gid != "":
			cells.append(_make_recipe_cell(gid, int(inp.get("qty", 0))))
	var potential := _recipe_potential(recipe)
	if potential != "":
		cells.append(_make_potential_cell(potential))
	return cells

# Wind/solar farms have no good inputs; their "input" is the tile's wind/solar
# potential. Power-gen recipes carry no parsed potential requirement, so fall back
# to the building's internal name. Returns "solar", "wind" or "".
func _recipe_potential(recipe: Dictionary) -> String:
	for req in recipe.get("requirements", []):
		if str(req.get("type", "")).to_lower() == "potential":
			var v := str(req.get("value", "")).to_lower()
			if v.contains("solar"):
				return "solar"
			if v.contains("wind"):
				return "wind"
	var internal := str(Catalog.get_building(str(recipe.get("building_id", ""))).get("internal_name", "")).to_lower()
	if internal.contains("solar_farm"):
		return "solar"
	if internal.contains("wind_farm"):
		return "wind"
	return ""

func _make_potential_cell(value: String, size: int = RECIPE_CELL) -> Control:
	var slot := PanelContainer.new()
	slot.custom_minimum_size = Vector2(size, size)
	var s := StyleBoxFlat.new()
	s.bg_color = DS.PALETTE.BG_INSET
	s.border_color = DS.PALETTE.BORDER_SOFT
	s.set_border_width_all(1)
	s.set_corner_radius_all(6)
	slot.add_theme_stylebox_override("panel", s)
	var l := Label.new()
	l.text = "%s\npotential" % value.capitalize()
	l.add_theme_font_size_override("font_size", 8 if size < 36 else 9)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	slot.add_child(l)
	return slot

func _recipe_card_outputs(recipe: Dictionary) -> Array:
	var out: Array = []
	if recipe.has("outputs"):
		for o in recipe.get("outputs", []):
			var gid := _recipe_good_id(o)
			if gid != "":
				out.append({"good_id": gid, "qty": int(o.get("qty", 0))})
	else:
		var name := str(recipe.get("output_name", ""))
		if name != "":
			var gid := str(Catalog.get_good_by_internal_name(name).get("id", ""))
			if gid != "":
				out.append({"good_id": gid, "qty": int(recipe.get("output_qty", 0))})
	return out

func _recipe_good_id(item: Dictionary) -> String:
	var gid := str(item.get("good_id", ""))
	if gid != "":
		return gid
	var internal := str(item.get("internal_name", ""))
	if internal != "":
		return str(Catalog.get_good_by_internal_name(internal).get("id", ""))
	return ""

func _make_recipe_cell(good_id: String, qty: int, size: int = RECIPE_CELL) -> Control:
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(size, size)
	var icon := GoodIcons.texture_for(good_id, Catalog.get_internal_name(good_id))
	if icon != null:
		var tr := TextureRect.new()
		tr.texture = icon
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.tooltip_text = Catalog.get_display_name(good_id)
		slot.add_child(tr)
	else:
		var ph := Label.new()
		ph.text = Catalog.get_display_name(good_id)
		ph.add_theme_font_size_override("font_size", 8)
		ph.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		ph.set_anchors_preset(Control.PRESET_FULL_RECT)
		slot.add_child(ph)
	if qty > 0:
		slot.add_child(_make_recipe_qty_badge(qty, size))
	return slot

func _make_recipe_qty_badge(qty: int, cell_size: int = RECIPE_CELL) -> Control:
	var qty_text := str(qty)
	var h := clampi(roundi(cell_size * 0.4), 12, 18)
	var w := h if qty_text.length() <= 1 else maxi(h, qty_text.length() * 8 + 8)
	var badge := PanelContainer.new()
	badge.custom_minimum_size = Vector2(w, h)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	badge.offset_left = -w + 4
	badge.offset_top = -h + 4
	badge.offset_right = 4
	badge.offset_bottom = 4
	var style := StyleBoxFlat.new()
	style.bg_color = DS.PALETTE.BG_PANEL
	style.border_color = DS.PALETTE.ACCENT
	style.set_border_width_all(1)
	style.set_corner_radius_all(int(h / 2.0))
	badge.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = qty_text
	label.add_theme_font_override("font", UIFonts.mono())
	label.add_theme_font_size_override("font_size", 8 if h < 16 else 10)
	label.add_theme_color_override("font_color", DS.PALETTE.ACCENT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(label)
	return badge

# --- Buildings & Land pane --------------------------------------------------
func _build_bl_pane(pane: VBoxContainer) -> void:
	var bl := TileViewData.buildings_land_summary(_current_tile_id, _current_tile_data)
	# The land visualisation now lives in the left rail; this pane is buildings +
	# infrastructure plus the Build / Buy Buildings actions.
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	var build_btn := _make_action_button("Build")
	build_btn.add_theme_font_size_override("font_size", 14)  # one size up
	build_btn.pressed.connect(_on_bl_build_pressed)
	actions.add_child(build_btn)
	var buy_buildings := _make_action_button("Buy Buildings")
	buy_buildings.add_theme_font_size_override("font_size", 14)  # one size up
	buy_buildings.pressed.connect(func(): MatchState.buildings_market_for_tile_requested.emit(_current_tile_id))
	actions.add_child(buy_buildings)
	pane.add_child(actions)

	var projects := Construction.projects_on_tile(_current_tile_id)
	var built_rows: Array = []
	for b in bl.buildings:
		if not bool(b.is_infra):
			built_rows.append(b)
	if _show_player_buildings_only:
		built_rows = _player_owned_building_rows(built_rows)
	pane.add_child(_make_buildings_header("Production", "(%d)" % (built_rows.size() + projects.size())))
	# Group buildings of the same type + recipe into one expandable group card.
	var groups: Dictionary = {}
	var order: Array = []
	for b in built_rows:
		var key := "%s|%s" % [str(b.building_id), str(b.get("recipe_id", ""))]
		if not groups.has(key):
			groups[key] = []
			order.append(key)
		(groups[key] as Array).append(b)
	for key in order:
		pane.add_child(_make_building_group_card(groups[key]))
	for project in projects:
		pane.add_child(_make_construction_row(project))
	if built_rows.is_empty() and projects.is_empty():
		var empty_text := "No player-owned buildings on this tile" if _show_player_buildings_only else "No buildings on this tile"
		pane.add_child(_make_muted_label(empty_text))

	# Infrastructure gets its own section: a grid of dialled add/built slots.
	pane.add_child(_make_section_title("Infrastructure", "transit / capacity", "ok"))
	pane.add_child(_make_infra_grid())

func _make_buildings_header(title: String, right_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.custom_minimum_size = Vector2(0, 30)
	var title_label := Label.new()
	title_label.text = title
	title_label.theme_type_variation = &"BuildingName"
	title_label.add_theme_color_override("font_color", DS.PALETTE.ACCENT)
	title_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(title_label)
	if right_text != "":
		var count := Label.new()
		count.text = right_text
		count.theme_type_variation = &"Caption"
		count.add_theme_color_override("font_color", DS.PALETTE.TEXT_DIM)
		count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(count)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var filter_label := Label.new()
	filter_label.text = "Show your buildings only"
	filter_label.theme_type_variation = &"Caption"
	filter_label.add_theme_font_size_override("font_size", 11)
	filter_label.add_theme_color_override("font_color", DS.PALETTE.TEXT_DIM)
	filter_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(filter_label)
	_player_only_checkbox = UIHelpers.make_custom_checkbox()
	_player_only_checkbox.name = "PlayerBuildingsOnlyCheckbox"
	_player_only_checkbox.custom_minimum_size = Vector2(24, 24)
	_player_only_checkbox.tooltip_text = "Show only buildings you own on this tile"
	_player_only_checkbox.set_pressed_no_signal(_show_player_buildings_only)
	_player_only_checkbox.toggled.connect(_on_player_buildings_only_toggled)
	row.add_child(_player_only_checkbox)
	return row

func _player_owned_building_rows(rows: Array) -> Array:
	var filtered: Array = []
	for row in rows:
		var inst := MatchState.get_building(str((row as Dictionary).get("instance_id", "")))
		if not inst.is_empty() and MatchState.is_player_owned(inst):
			filtered.append(row)
	return filtered

func _on_player_buildings_only_toggled(pressed: bool) -> void:
	if _show_player_buildings_only == pressed:
		return
	_show_player_buildings_only = pressed
	_refresh_active_pane()

## Buy Land → a dropdown of fixed increments (10/20/30/40/50) up to the maximum,
## plus a "Buy maximum (N)" option. Increments above the max are omitted, so a
## small remaining cap collapses to just the maximum.
func _on_buy_land_pressed(anchor: Control) -> void:
	var patch := MatchState.LAND_PATCH_SIZE
	var max_land := MatchState.get_tile_land_patches_available(_current_tile_id) * patch
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
		var cost := int(round(float(land) / float(patch) * MatchState.LAND_PATCH_COST))
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
	var patches := int(land_amount / MatchState.LAND_PATCH_SIZE)
	if patches > 0:
		if MatchState.purchase_tile_land(_current_tile_id, patches):
			Audio.transaction()

func _on_bl_build_pressed() -> void:
	# Open the construct panel filtered to this tile's valid buildings/recipes;
	# selecting a recipe there builds directly on this tile.
	var cp := get_tree().root.find_child("ConstructPanel", true, false)
	if cp != null and cp.has_method("open_for_tile"):
		cp.open_for_tile(_current_tile_id, _current_tile_data)
		PanelStack.push(cp)

func _make_infra_grid() -> Control:
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	for slot in TileViewData.infrastructure_summary(_current_tile_id, _current_tile_data):
		grid.add_child(_make_infra_cell(slot))
	return grid

func _make_infra_cell(slot: Dictionary) -> VBoxContainer:
	var cell := VBoxContainer.new()
	cell.add_theme_constant_override("separation", 3)
	cell.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var dial := INFRA_DIAL.new()
	var transit: Dictionary = slot.get("transit", {})
	match str(transit.get("dial", "track")):
		"fill": dial.configure("fill", float(transit.get("pct", 0.0)))
		"full_green": dial.configure("full_green")
		_: dial.configure("track")

	var state := str(slot.state)
	var tooltip := str(transit.get("tooltip", ""))
	match state:
		"exists":
			dial.set_content(_make_infra_button(_building_texture(slot.get("building_data", {})), null, DS.PALETTE.BG_INSET, DS.PALETTE.BG_HIGHLIGHT, tooltip, func(b): _on_infra_pressed(slot.instance, "", "")))
		"add":
			dial.set_content(_make_infra_add_content(slot, tooltip))
		_:
			var b := _make_infra_button(_get_plus_icon(), null, DS.PALETTE.BG_INSET, DS.PALETTE.BG_INSET, "%s — not available yet" % slot.label, Callable())
			b.disabled = true
			b.modulate = Color(1, 1, 1, 0.4)
			dial.set_content(b)
	cell.add_child(dial)

	var label := Label.new()
	label.text = str(slot.label)
	label.theme_type_variation = &"Caption"
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", DS.PALETTE.ACCENT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(INFRA_DIAL.BUTTON_SIZE + 22, 0)
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	cell.add_child(label)

	# Transit capacity beneath the name (Infinite for uncapped cables/HVDC).
	var cap_label := Label.new()
	if not bool(slot.get("capped", false)):
		cap_label.text = "Infinite"
	elif state == "exists":
		cap_label.text = "%d/%d" % [int(transit.get("used", 0)), int(slot.get("cap", 0))]
	else:
		cap_label.text = "%d cap" % int(slot.get("cap", 0))
	cap_label.theme_type_variation = &"Caption"
	cap_label.add_theme_font_size_override("font_size", 9)
	cap_label.add_theme_color_override("font_color", DS.PALETTE.TEXT_DIM)
	cap_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap_label.custom_minimum_size = Vector2(INFRA_DIAL.BUTTON_SIZE + 22, 0)
	cell.add_child(cap_label)
	return cell

func _make_infra_button(icon: Texture2D, _unused, bg: Color, hover_bg: Color, tooltip: String, on_press: Callable) -> Button:
	var button := Button.new()
	button.set_anchors_preset(Control.PRESET_FULL_RECT)
	button.custom_minimum_size = Vector2(56, 56)
	button.focus_mode = Control.FOCUS_NONE
	button.expand_icon = true
	button.icon = icon
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	button.tooltip_text = tooltip
	button.add_theme_stylebox_override("normal", _infra_btn_style(bg))
	button.add_theme_stylebox_override("hover", _infra_btn_style(hover_bg))  # lighter on hover
	button.add_theme_stylebox_override("pressed", _infra_btn_style(hover_bg))
	button.add_theme_stylebox_override("disabled", _infra_btn_style(bg))
	button.mouse_entered.connect(Audio.hover)   # custom-styled, so wire the hover cue here
	if on_press.is_valid():
		button.pressed.connect(func(): on_press.call(button))
	return button

func _infra_btn_style(bg: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(7)
	s.set_content_margin_all(6)
	return s

## "Add" infra cell: a plus button with a built-icon overlay that flashes and
## cross-fades from plus → building icon over 1s when pressed (build affordance).
func _make_infra_add_content(slot: Dictionary, tooltip: String) -> Control:
	var content := Control.new()
	content.custom_minimum_size = Vector2(56, 56)

	var built_tex := _building_texture(slot.get("building_data", {}))
	var internal := str(slot.internal_name)
	var button: Button = _make_infra_button(_get_plus_icon(), null, DS.PALETTE.ACTION_BLUE, DS.PALETTE.ACTION_BLUE_HOVER, tooltip, Callable())
	content.add_child(button)

	var built_overlay := TextureRect.new()
	built_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	built_overlay.texture = built_tex
	built_overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	built_overlay.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	built_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	built_overlay.modulate = Color(1, 1, 1, 0)
	content.add_child(built_overlay)

	button.pressed.connect(func(): _on_infra_add_pressed(internal, content, button, built_overlay))
	return content

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

func _get_plus_icon() -> Texture2D:
	if _plus_icon == null and ResourceLoader.exists(PLUS_ICON_PATH):
		_plus_icon = load(PLUS_ICON_PATH) as Texture2D
	return _plus_icon

# --- Production pane --------------------------------------------------------
func _build_prod_pane(pane: VBoxContainer) -> void:
	var prod := TileViewData.production_summary(_current_tile_id)
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 8)
	cards.add_child(_make_stat_card("Net value", "£%.1f/turn" % float(prod.net_value), _status_color(prod.status)))
	cards.add_child(_make_stat_card("Outputs", "%d goods" % int(prod.outputs), DS.PALETTE.TEXT))
	var sales := TileViewData.sales_summary(_current_tile_id)
	cards.add_child(_make_stat_card("Sales", "£%.0f/turn" % float(sales.revenue), DS.PALETTE.OK, "%d units/turn" % int(sales.units)))
	pane.add_child(cards)

	pane.add_child(_make_section_title("Outputs", "by value", "ok"))
	if prod.rows.is_empty():
		pane.add_child(_make_muted_label("No production on this tile last turn"))
	for r in prod.rows:
		pane.add_child(_make_production_row(r))

	# Deposits on this tile — gated by survey status; buildable, with a Build action.
	var gated: Dictionary = TileViewData.survey_gated_deposits(_current_tile_id, _current_tile_data)
	if gated.status == "unsurveyed" or not gated.rows.is_empty():
		pane.add_child(_make_section_header("Deposits", "buildable", "ok"))
		if gated.status == "unsurveyed":
			var unknown := Label.new()
			unknown.text = "Deposits Unknown"
			unknown.theme_type_variation = &"Body"
			unknown.add_theme_color_override("font_color", DS.PALETTE.TEXT_MUTED)
			pane.add_child(unknown)
		for d in gated.rows:
			pane.add_child(_make_deposit_row(d))

func _make_deposit_row(d: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.custom_minimum_size = Vector2(0, 34)

	var name_label := Label.new()
	name_label.text = str(d.display_name) if bool(d.get("is_water", false)) else "%s deposit" % str(d.display_name)
	name_label.theme_type_variation = &"Body"
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	var size_qty := int(d.get("size_qty", int(d.get("qty", -1))))
	var qty := Label.new()
	qty.text = "?" if size_qty == -2 else (("%d" % size_qty) if size_qty >= 0 else "—")
	qty.theme_type_variation = &"Numeric"
	qty.add_theme_font_size_override("font_size", 12)
	qty.add_theme_color_override("font_color", DS.PALETTE.TEXT_MUTED)
	qty.custom_minimum_size = Vector2(48, 0)
	qty.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(qty)

	var build_text := "Build"
	if _deposit_under_construction(str(d.deposit_token)):
		build_text = "Build another"
	var action := _make_action_button("Go to building" if bool(d.has_building) else build_text)
	action.size_flags_horizontal = Control.SIZE_SHRINK_END
	action.custom_minimum_size = Vector2(124, 0)
	if bool(d.has_building):
		var inst_id := str(d.instance_id)
		action.pressed.connect(func(): _go_to_building(inst_id))
	else:
		var token := str(d.deposit_token)
		var gid := str(d.good_id)
		action.pressed.connect(func(): _on_deposit_build(token, gid, action))
	row.add_child(action)
	return row

## True when a building+recipe that exploits this deposit is already under
## construction on this tile (drives the "Build another" label).
func _deposit_under_construction(deposit_token: String) -> bool:
	var opts := TileViewData.deposit_build_options(deposit_token)
	if opts.is_empty():
		return false
	var pairs := {}
	for o in opts:
		pairs["%s|%s" % [str(o.building_id), str(o.recipe_id)]] = true
	for project in Construction.projects_on_tile(_current_tile_id):
		if pairs.has("%s|%s" % [str(project.get("building_id", "")), str(project.get("recipe_id", ""))]):
			return true
	return false

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
	var inst := MatchState.get_building(instance_id)
	if not inst.is_empty():
		building_clicked.emit(inst)

# --- Stockpile pane (vertical bar chart) ------------------------------------
func _build_stock_pane(pane: VBoxContainer) -> void:
	var stock := TileViewData.stockpile_summary(_current_tile_id)
	var pct_text := "FULL · %d/%d" % [stock.used, stock.capacity] if stock.is_full else "%d/%d · %d%%" % [stock.used, stock.capacity, roundi(float(stock.pct) * 100.0)]
	# The "Stockpile" heading now lives inside the chart's outline.
	pane.add_child(_make_stock_chart(stock.goods, pct_text, str(stock.status)))

	# Whole-tile "Sell all Surplus" — applies to every good, so it sits under the
	# chart, outside the per-good "select a good" flow.
	pane.add_child(_make_sell_surplus_toggle())

	if _stock_sel.is_empty():
		pane.add_child(_make_muted_label("Select a good above to move or sell it"))
	else:
		pane.add_child(_make_stock_context_menu())

	# Overflow shipments: arrived at this tile but can't unload (stockpile full).
	var overflow := MatchState.get_overflow_shipments_for_tile(_current_tile_id)
	if not overflow.is_empty():
		pane.add_child(_make_section_header("Overflow Shipments", "can't unload", "problem"))
		for r in overflow:
			pane.add_child(_make_overflow_row(r))

# Whole-tile "Sell all Surplus" toggle. Enabling it (unless suppressed) opens a
# confirmation dialog first; the box only commits once the player confirms.
func _make_sell_surplus_toggle() -> CheckBox:
	var tile_id_now := _current_tile_id
	var toggle := CheckBox.new()
	toggle.text = "Sell all Surplus every turn"
	toggle.tooltip_text = ("Each turn, sells every good on this tile that its buildings don't reserve as inputs.\n"
		+ "Demand is re-checked every turn, so adding a consuming building automatically reduces the sales.")
	toggle.button_pressed = MatchState.is_sell_surplus_enabled(tile_id_now)
	toggle.toggled.connect(func(v: bool) -> void: _on_sell_surplus_toggled(tile_id_now, toggle, v))
	return toggle

func _on_sell_surplus_toggled(tile_id: String, toggle: CheckBox, enabled: bool) -> void:
	if not enabled:
		MatchState.disable_sell_surplus(tile_id)
		return
	if _skip_sell_surplus_confirm:
		_commit_sell_surplus(tile_id)
		return
	# Hold the enable until the player confirms; revert the box on cancel.
	_ensure_sell_surplus_dialog()
	_pending_surplus_tile = tile_id
	_pending_surplus_toggle = toggle
	_sell_surplus_dialog.open()

func _ensure_sell_surplus_dialog() -> void:
	if _sell_surplus_dialog != null and is_instance_valid(_sell_surplus_dialog):
		return
	if _sell_surplus_layer == null or not is_instance_valid(_sell_surplus_layer):
		_sell_surplus_layer = CanvasLayer.new()
		_sell_surplus_layer.layer = 130  # above the tile view panel + HUD
		get_tree().root.add_child(_sell_surplus_layer)
	_sell_surplus_dialog = SellSurplusDialog.new()
	_sell_surplus_layer.add_child(_sell_surplus_dialog)
	_sell_surplus_dialog.confirmed.connect(_on_sell_surplus_confirmed)
	_sell_surplus_dialog.cancelled.connect(_on_sell_surplus_cancelled)

func _on_sell_surplus_confirmed(dont_ask_again: bool) -> void:
	if dont_ask_again:
		_skip_sell_surplus_confirm = true
	if _pending_surplus_tile != "":
		_commit_sell_surplus(_pending_surplus_tile)
	_pending_surplus_tile = ""
	_pending_surplus_toggle = null

func _on_sell_surplus_cancelled() -> void:
	# Revert the checkbox — the enable was never committed.
	if _pending_surplus_toggle != null and is_instance_valid(_pending_surplus_toggle):
		_pending_surplus_toggle.set_pressed_no_signal(false)
	_pending_surplus_tile = ""
	_pending_surplus_toggle = null

func _commit_sell_surplus(tile_id: String) -> void:
	MatchState.enable_sell_surplus(tile_id)
	MatchState.request_toast("Selling this tile's unused surplus every turn", "success")

func _make_overflow_row(r: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.custom_minimum_size = Vector2(0, 28)
	var src := str(r.get("source_tile", ""))
	var route := Label.new()
	route.text = "%s → %s" % [Catalog.tile_label(src) if src != "" else "—", Catalog.tile_label(str(r.get("destination_tile", "")))]
	route.theme_type_variation = &"Caption"
	route.custom_minimum_size = Vector2(150, 0)
	row.add_child(route)
	var contents := Label.new()
	contents.text = "%d %s" % [int(r.get("qty", 0)), Catalog.get_display_name(str(r.get("good_id", "")))]
	contents.theme_type_variation = &"Body"
	contents.add_theme_font_size_override("font_size", 12)
	contents.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(contents)
	var waited := Label.new()
	var turns := int(r.get("turns_waiting", 0))
	waited.text = "waiting %d turn%s" % [turns, "" if turns == 1 else "s"]
	waited.theme_type_variation = &"Caption"
	waited.add_theme_color_override("font_color", DS.PALETTE.WARN)
	waited.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(waited)
	return row

# Contextual "Move or Sell <good>" menu shown under the chart when a good is picked.
func _make_stock_context_menu() -> PanelContainer:
	var card := PanelContainer.new()
	var cs := StyleBoxFlat.new()
	cs.bg_color = DS.PALETTE.BG_CARD
	cs.border_color = DS.PALETTE.BORDER_SOFT
	cs.set_border_width_all(1)
	cs.set_corner_radius_all(10)
	cs.set_content_margin_all(12)
	card.add_theme_stylebox_override("panel", cs)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 9)
	card.add_child(vbox)

	var selected_good_id := str(_stock_sel.get("good_id", ""))
	var active_order: Dictionary = SpecialOrderState.get_active_order_for_good(selected_good_id)
	if _stock_dest == SPECIAL_ORDER_DEST and active_order.is_empty():
		_stock_dest = ""
	var available_qty := int(_stock_sel.get("qty", 0))
	var max_qty := available_qty
	if _stock_dest == SPECIAL_ORDER_DEST:
		max_qty = mini(available_qty, SpecialOrderState.remaining_uncommitted(active_order))
	var title := Label.new()
	title.text = "Move or Sell %s" % str(_stock_sel.get("name", ""))
	title.theme_type_variation = &"Section"
	vbox.add_child(title)

	# --- Quantity: All button + number spinner ---
	var qty_row := HBoxContainer.new()
	qty_row.add_theme_constant_override("separation", 8)
	var qty_label := Label.new()
	qty_label.text = "Quantity"
	qty_label.theme_type_variation = &"Body"  # Rural font
	qty_label.add_theme_font_size_override("font_size", 13)
	qty_label.custom_minimum_size = Vector2(72, 0)
	qty_row.add_child(qty_label)
	var spin := SpinBox.new()
	spin.min_value = 1
	spin.max_value = maxi(1, max_qty)
	spin.step = 1
	spin.update_on_text_changed = true   # typed numbers apply immediately, no Enter needed
	_stock_qty = clampi(_stock_qty, 1, maxi(1, max_qty))
	spin.value = _stock_qty
	spin.custom_minimum_size = Vector2(110, 0)
	spin.value_changed.connect(func(v): _stock_qty = int(v))
	qty_row.add_child(spin)
	var all_btn := _make_action_button("All")
	all_btn.add_theme_font_size_override("font_size", 14)  # one size up
	all_btn.custom_minimum_size = Vector2(56, 0)
	all_btn.pressed.connect(func():
		_stock_qty = max_qty
		spin.value = maxi(1, max_qty))
	qty_row.add_child(all_btn)
	vbox.add_child(qty_row)

	# --- Destination: Market / Tile ---
	var dest_row := HBoxContainer.new()
	dest_row.add_theme_constant_override("separation", 8)
	var dest_label := Label.new()
	dest_label.text = "Destination"
	dest_label.theme_type_variation = &"Body"  # Rural font
	dest_label.add_theme_font_size_override("font_size", 13)
	dest_label.custom_minimum_size = Vector2(72, 0)
	dest_row.add_child(dest_label)
	dest_row.add_child(_make_toggle_button("Market", _stock_dest == MARKET_DEST, func():
		_stock_dest = MARKET_DEST
		_refresh_pane("stock")))
	if not active_order.is_empty():
		var special_btn := _make_toggle_button("Special Order", _stock_dest == SPECIAL_ORDER_DEST, func():
			_stock_dest = SPECIAL_ORDER_DEST
			_stock_recurring = false
			var remaining := SpecialOrderState.remaining_uncommitted(SpecialOrderState.get_active_order_for_good(selected_good_id))
			if remaining > 0:
				_stock_qty = mini(_stock_qty, remaining)
			_refresh_pane("stock"))
		if SpecialOrderState.remaining_uncommitted(active_order) <= 0:
			special_btn.disabled = true
			special_btn.tooltip_text = "This special order is already fully committed."
		dest_row.add_child(special_btn)
	dest_row.add_child(_make_toggle_button("Tile", _stock_dest != "" and _stock_dest != MARKET_DEST and _stock_dest != SPECIAL_ORDER_DEST, func():
		pick_destination_requested.emit()
		MatchState.request_toast("Pick a destination tile on the map", "caution")))
	var dest_value := Label.new()
	dest_value.text = _stock_dest_text().to_upper()  # capitalise the tile name / MARKET
	dest_value.theme_type_variation = &"Caption"
	dest_value.add_theme_color_override("font_color", DS.PALETTE.TEXT_MUTED)
	dest_value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dest_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	dest_row.add_child(dest_value)
	vbox.add_child(dest_row)

	# --- Make recurring ---
	var recurring := CheckBox.new()
	recurring.text = "Make recurring"
	if _stock_dest == SPECIAL_ORDER_DEST:
		_stock_recurring = false
		recurring.disabled = true
		recurring.tooltip_text = "Special orders are one-off commitments."
	recurring.button_pressed = _stock_recurring
	recurring.toggled.connect(func(v): _stock_recurring = v)
	vbox.add_child(recurring)

	# --- Per-good standing order: "sell all except X" (whole-tile surplus lives
	# under the chart in _build_stock_pane, since it doesn't need a selected good).
	vbox.add_child(HSeparator.new())
	var tile_id_now := _current_tile_id
	var keep_row := HBoxContainer.new()
	keep_row.add_theme_constant_override("separation", 6)
	var keep_toggle := CheckBox.new()
	var good_display := str(_stock_sel.get("name", selected_good_id))
	keep_toggle.text = "Sell all %s except" % good_display
	keep_toggle.tooltip_text = ("A standing order: every turn, sell this good down to the amount on the right\n"
		+ "(local buildings' input needs are always protected on top).")
	keep_toggle.button_pressed = MatchState.is_auto_sell_good(tile_id_now, selected_good_id)
	keep_row.add_child(keep_toggle)
	var keep_spin := SpinBox.new()
	keep_spin.min_value = 0
	keep_spin.max_value = 999999
	keep_spin.step = 1
	keep_spin.update_on_text_changed = true
	keep_spin.value = MatchState.auto_sell_keep_for(tile_id_now, selected_good_id)
	keep_spin.custom_minimum_size = Vector2(86, 0)
	keep_spin.editable = keep_toggle.button_pressed
	keep_spin.value_changed.connect(func(v: float) -> void:
		MatchState.set_auto_sell_keep(tile_id_now, selected_good_id, int(v)))
	keep_row.add_child(keep_spin)
	var keep_suffix := Label.new()
	keep_suffix.text = "left on tile"
	keep_suffix.theme_type_variation = &"Caption"
	keep_suffix.add_theme_color_override("font_color", DS.PALETTE.TEXT_MUTED)
	keep_row.add_child(keep_suffix)
	keep_toggle.toggled.connect(func(v: bool) -> void:
		keep_spin.editable = v
		if v:
			MatchState.enable_auto_sell_good(tile_id_now, selected_good_id)
			MatchState.set_auto_sell_keep(tile_id_now, selected_good_id, int(keep_spin.value))
			MatchState.request_toast("Selling all %s above %d every turn" % [good_display, int(keep_spin.value)], "success")
		else:
			MatchState.disable_auto_sell_good(tile_id_now, selected_good_id)
			MatchState.set_auto_sell_keep(tile_id_now, selected_good_id, 0))
	vbox.add_child(keep_row)

	# --- Confirm ---
	var confirm := _make_action_button("Confirm")
	confirm.add_theme_font_size_override("font_size", 14)  # one size up
	confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm.custom_minimum_size = Vector2(0, 34)
	confirm.disabled = _stock_dest == "" or (_stock_dest == SPECIAL_ORDER_DEST and (active_order.is_empty() or SpecialOrderState.remaining_uncommitted(active_order) <= 0))
	confirm.pressed.connect(_confirm_stock_action)
	vbox.add_child(confirm)
	return card

func _stock_dest_text() -> String:
	if _stock_dest == MARKET_DEST:
		return "Market"
	if _stock_dest == SPECIAL_ORDER_DEST:
		var order := SpecialOrderState.get_active_order_for_good(str(_stock_sel.get("good_id", "")))
		if not order.is_empty():
			return "Special Order: %s" % str(order.get("display_name", Catalog.get_display_name(str(_stock_sel.get("good_id", "")))))
		return "Special Order"
	if _stock_dest != "":
		return Catalog.tile_label(_stock_dest)
	return "— none —"

func _on_stock_bar_input(event: InputEvent, good_id: String, good_name: String, qty: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_stock_sel = {"good_id": good_id, "name": good_name, "qty": qty}
		_stock_qty = qty
		_stock_dest = ""
		_stock_recurring = false
		_refresh_pane("stock")

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
		MatchState.queue_move(_current_tile_id, _stock_dest, goods)
		if recurring:
			MatchState.add_recurring_move(_current_tile_id, _stock_dest, goods)
		MatchState.request_toast("%s %d %s to %s" % ["Recurring move of" if recurring else "Moving", qty, good_name, Catalog.tile_label(_stock_dest)], "success")
	_stock_sel = {}
	_stock_dest = ""
	_stock_recurring = false
	_refresh_pane("stock")

func _make_stock_chart(goods: Array, pct_text: String, status: String) -> Control:
	var holder := PanelContainer.new()
	var hs := StyleBoxFlat.new()
	hs.bg_color = DS.PALETTE.BG_CARD
	hs.border_color = DS.PALETTE.BORDER_SOFT
	hs.set_border_width_all(1)
	hs.set_corner_radius_all(8)
	hs.set_content_margin_all(10)
	holder.add_theme_stylebox_override("panel", hs)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	holder.add_child(col)

	# "Stockpile" heading sits INSIDE the chart outline (semibold 22, off-white).
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var title := Label.new()
	title.text = "Stockpile"
	title.theme_type_variation = &"BuildingName"  # Barlow SemiBold 22
	title.add_theme_color_override("font_color", DS.PALETTE.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var pct := Label.new()
	pct.text = pct_text
	pct.theme_type_variation = &"Caption"
	pct.add_theme_color_override("font_color", _status_color(status) if status != "ok" else DS.PALETTE.TEXT_DIM)
	pct.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(pct)
	col.add_child(head)

	if goods.is_empty():
		col.add_child(_make_muted_label("Stockpile is empty"))
		return holder

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)

	# Lump overflow goods into a single "Other goods" bar.
	var shown: Array = goods
	var other: Array = []
	if goods.size() > STOCK_MAX_BARS:
		shown = goods.slice(0, STOCK_MAX_BARS - 1)
		other = goods.slice(STOCK_MAX_BARS - 1)

	var max_qty := 1
	for g in shown:
		max_qty = maxi(max_qty, int(g.qty))
	var other_sum := 0
	for g in other:
		other_sum += int(g.qty)
	max_qty = maxi(max_qty, other_sum)

	var palette := [DS.PALETTE.OK, Color(0.42, 0.65, 0.84), DS.PALETTE.WARN, DS.PALETTE.TEXT_MUTED, Color(0.55, 0.62, 0.70)]
	var i := 0
	for g in shown:
		row.add_child(_make_stock_bar(str(g.display_name), str(g.good_id), int(g.qty), max_qty, palette[i % palette.size()], ""))
		i += 1
	if not other.is_empty():
		var lines: Array[String] = []
		for g in other:
			lines.append("%s: %d" % [str(g.display_name), int(g.qty)])
		row.add_child(_make_stock_bar("Other goods", "", other_sum, max_qty, DS.PALETTE.TEXT_DIM, "\n".join(lines)))
	return holder

func _make_stock_bar(name: String, good_id: String, qty: int, max_qty: int, color: Color, tooltip: String) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_END
	col.custom_minimum_size = Vector2(STOCK_BAR_WIDTH, CHART_HEIGHT + STOCK_ICON_SIZE + 44)
	var selected := false
	if tooltip != "":
		col.tooltip_text = tooltip
		col.mouse_filter = Control.MOUSE_FILTER_STOP
	if good_id != "":
		# The whole column (bar included) selects the good.
		col.tooltip_text = name
		col.mouse_filter = Control.MOUSE_FILTER_STOP
		col.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		col.gui_input.connect(func(e): _on_stock_bar_input(e, good_id, name, qty))
		selected = str(_stock_sel.get("good_id", "")) == good_id

	# Selection marker at the very top of the column.
	var marker := ColorRect.new()
	marker.custom_minimum_size = Vector2(STOCK_BAR_WIDTH, 3)
	marker.color = DS.PALETTE.ACCENT if selected else Color(0, 0, 0, 0)
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(marker)

	var value := Label.new()
	value.text = str(qty)
	value.theme_type_variation = &"Caption"
	value.add_theme_font_size_override("font_size", 11)
	value.add_theme_color_override("font_color", DS.PALETTE.ACCENT if selected else DS.PALETTE.TEXT)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(value)

	var bar := PanelContainer.new()
	var bar_h := maxf(4.0, CHART_HEIGHT * (float(qty) / float(max_qty)))
	bar.custom_minimum_size = Vector2(STOCK_BAR_WIDTH, bar_h)
	bar.size_flags_vertical = Control.SIZE_SHRINK_END
	bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bs := StyleBoxFlat.new()
	bs.bg_color = color
	bs.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("panel", bs)
	col.add_child(bar)

	# 60×60 good icon (blank slot for "Other goods").
	var icon_slot := Control.new()
	icon_slot.custom_minimum_size = Vector2(STOCK_ICON_SIZE, STOCK_ICON_SIZE)
	icon_slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tex: Texture2D = null
	if good_id != "":
		tex = GoodIcons.texture_for(good_id, Catalog.get_internal_name(good_id))
		UIHelpers.attach_good_name_tooltip(icon_slot, good_id)  # hover shows the good's name
	if tex != null:
		var icon := TextureRect.new()
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.texture = tex
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_slot.add_child(icon)
	col.add_child(icon_slot)

	# Full name, character-wrapped to fill 2 lines then ellipsis. The selected
	# good gets an off-white background behind its name.
	var label := Label.new()
	label.text = name
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.theme_type_variation = &"Caption"
	label.add_theme_font_size_override("font_size", 9)
	label.add_theme_color_override("font_color", DS.PALETTE.BG_PANEL if selected else DS.PALETTE.TEXT_MUTED)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	label.max_lines_visible = 2
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.clip_text = true
	label.custom_minimum_size = Vector2(STOCK_BAR_WIDTH + 8, 26)
	if selected:
		var name_bg := StyleBoxFlat.new()
		name_bg.bg_color = DS.PALETTE.ACCENT
		name_bg.set_corner_radius_all(4)
		name_bg.content_margin_left = 3
		name_bg.content_margin_right = 3
		name_bg.content_margin_top = 1
		name_bg.content_margin_bottom = 1
		label.add_theme_stylebox_override("normal", name_bg)
	col.add_child(label)
	return col

func _truncate(text: String, max_chars: int) -> String:
	if text.length() <= max_chars:
		return text
	return "%s…" % text.substr(0, maxi(1, max_chars - 1))

# ─────────────────────────────────────────────────────────────────────────────
# Shared widget builders
# ─────────────────────────────────────────────────────────────────────────────
func _make_status_banner(text: String, color: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color(color, 0.14)
	s.border_color = Color(color, 0.4)
	s.set_border_width_all(1)
	s.set_corner_radius_all(9)
	s.set_content_margin_all(9)
	p.add_theme_stylebox_override("panel", s)
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"Body"
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	p.add_child(l)
	return p

func _make_meter_row(label_text: String, value: int, denom: int, color: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.custom_minimum_size = Vector2(0, 20)
	var label := Label.new()
	label.text = label_text
	label.theme_type_variation = &"Caption"
	label.custom_minimum_size = Vector2(74, 0)
	row.add_child(label)
	var track := PanelContainer.new()
	track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	track.custom_minimum_size = Vector2(0, 10)
	var ts := StyleBoxFlat.new()
	ts.bg_color = Color(1, 1, 1, 0.10)
	ts.set_corner_radius_all(5)
	track.add_theme_stylebox_override("panel", ts)
	var track_row := HBoxContainer.new()
	track_row.add_theme_constant_override("separation", 0)
	track.add_child(track_row)
	var ratio := clampf(float(value) / float(maxi(1, denom)), 0.0, 1.0)
	if ratio > 0.0:
		var fill := PanelContainer.new()
		fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fill.size_flags_stretch_ratio = ratio
		var fs := StyleBoxFlat.new()
		fs.bg_color = color
		fs.set_corner_radius_all(5)
		fill.add_theme_stylebox_override("panel", fs)
		track_row.add_child(fill)
	if ratio < 1.0:
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spacer.size_flags_stretch_ratio = 1.0 - ratio
		track_row.add_child(spacer)
	row.add_child(track)
	var amount := Label.new()
	amount.text = "%d/t" % value
	amount.theme_type_variation = &"Numeric"
	amount.add_theme_font_size_override("font_size", 12)
	amount.custom_minimum_size = Vector2(42, 0)
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(amount)
	return row

func _make_net_row(label_text: String, net: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.theme_type_variation = &"Caption"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var value := Label.new()
	value.text = "%+d/turn %s" % [net, ("← grid" if net < 0 else ("→ grid" if net > 0 else ""))]
	value.theme_type_variation = &"Numeric"
	value.add_theme_font_size_override("font_size", 13)
	value.add_theme_color_override("font_color", DS.PALETTE.DANGER if net < 0 else DS.PALETTE.OK)
	row.add_child(value)
	return row

# A proper DS section heading (Barlow Bold 22, ACCENT, tracked) with an optional
# right-aligned caption.
func _make_section_title(title: String, right_text: String, status: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var title_label := Label.new()
	title_label.text = title
	title_label.theme_type_variation = &"BuildingName"  # Barlow SemiBold 22
	title_label.add_theme_color_override("font_color", DS.PALETTE.ACCENT)  # off-white
	title_label.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(title_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	if right_text != "":
		var right := Label.new()
		right.text = right_text
		right.theme_type_variation = &"Caption"
		right.add_theme_color_override("font_color", _status_color(status) if status != "ok" else DS.PALETTE.TEXT_DIM)
		right.size_flags_vertical = Control.SIZE_SHRINK_END
		row.add_child(right)
	return row

func _make_section_header(title: String, right_text: String, status: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.custom_minimum_size = Vector2(0, 16)
	var title_label := Label.new()
	title_label.text = title.to_upper()
	title_label.add_theme_font_override("font", UIFonts.section())
	title_label.add_theme_font_size_override("font_size", 11)
	title_label.add_theme_color_override("font_color", DS.PALETTE.TEXT_DIM)
	row.add_child(title_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	if right_text != "":
		var right := Label.new()
		right.text = right_text
		right.theme_type_variation = &"Caption"
		right.add_theme_font_size_override("font_size", 11)
		right.add_theme_color_override("font_color", _status_color(status) if status != "ok" else DS.PALETTE.TEXT_DIM)
		row.add_child(right)
	return row

func _make_line_row(left: String, right: String, right_color: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 26)
	var l := Label.new()
	l.text = left
	l.theme_type_variation = &"Body"
	l.add_theme_font_size_override("font_size", 13)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var r := Label.new()
	r.text = right
	r.theme_type_variation = &"Numeric"
	r.add_theme_font_size_override("font_size", 13)
	r.add_theme_color_override("font_color", right_color)
	row.add_child(r)
	return row

const GROUP_TILE := 90   # shared outer size for the icon AND the goods frame (max 90×90)
const GROUP_CARD_H := 100 # group-card header height

# A group card aggregates all buildings of the same type + recipe. Click the row or
# the ▶ button to expand into the individual building rows. When the "group" holds a
# single building it renders as a SOLO card instead: no count badge, no expand arrow,
# the building's public name + RAG strip inline, and clicking opens its detail panel.
func _make_building_group_card(members: Array) -> VBoxContainer:
	var first: Dictionary = members[0]
	var building_id := str(first.building_id)
	var recipe_id := str(first.get("recipe_id", ""))
	var recipe: Dictionary = Catalog.get_recipe(recipe_id)
	var bd: Dictionary = Catalog.get_building(building_id)
	var count := members.size()
	var solo := count == 1

	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 4)

	# ── Header row (clickable), in a differentiated card with an off-white outline ─
	var header_panel := PanelContainer.new()
	var hp_style := StyleBoxFlat.new()
	hp_style.bg_color = DS.PALETTE.BG_HIGHLIGHT
	hp_style.border_color = DS.PALETTE.ACCENT  # off-white outline
	hp_style.set_border_width_all(1)
	hp_style.set_corner_radius_all(10)
	hp_style.set_content_margin_all(5)
	header_panel.add_theme_stylebox_override("panel", hp_style)
	card.add_child(header_panel)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 5)
	header.custom_minimum_size = Vector2(0, GROUP_CARD_H - 10)
	header.mouse_filter = Control.MOUSE_FILTER_STOP
	header.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	header_panel.add_child(header)

	# Small left gutter so the count badge's overhang isn't clipped.
	var gutter := Control.new()
	gutter.custom_minimum_size = Vector2(14, 0)
	gutter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(gutter)

	# Icon with the count badge half-overlapping its top-left corner.
	var icon_holder := Control.new()
	icon_holder.custom_minimum_size = Vector2(GROUP_TILE, GROUP_TILE)
	icon_holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := _make_building_icon(building_id, 1.0, GROUP_TILE)
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon_holder.add_child(icon)
	if not solo:  # no count badge for a single building
		var badge := _make_count_badge(count)  # 30×30
		badge.position = Vector2(-15, 12)       # half over the icon, half to the left
		icon_holder.add_child(badge)
	header.add_child(icon_holder)

	# Outputs goods frame (same outer size as the icon), 5px to its right.
	header.add_child(_make_output_goods_frame(recipe, building_id))

	# Recipe name (offset 20px from the top) + cost basis (offset 20px from the bottom).
	var info_margin := MarginContainer.new()
	info_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var v_inset := 8 if solo else 20  # solo also shows a RAG strip, so less inset
	info_margin.add_theme_constant_override("margin_top", v_inset)
	info_margin.add_theme_constant_override("margin_bottom", v_inset)
	info_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_margin.add_child(info)
	var name_label := Label.new()
	# Solo card shows the building's public name ("Mine - Coal - A"); a real group
	# shows the shared recipe name.
	name_label.text = str(first.get("name", "")) if solo else str(recipe.get("display_name", bd.get("display_name", "Building")))
	name_label.theme_type_variation = &"BuildingName"  # next size up (Barlow Semi 22)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # spills onto next row
	info.add_child(name_label)
	if solo:  # at-a-glance status for the single building
		info.add_child(_make_building_rag_strip(first))
	var pusher := Control.new()
	pusher.size_flags_vertical = Control.SIZE_EXPAND_FILL  # pushes cost basis to the bottom
	pusher.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(pusher)
	var cost_header := Label.new()
	cost_header.text = "Cost Basis"
	cost_header.theme_type_variation = &"Body"  # same face/size as the Rural/Urban chips
	cost_header.add_theme_font_size_override("font_size", 13)
	cost_header.add_theme_color_override("font_color", DS.PALETTE.TEXT_MUTED)
	info.add_child(cost_header)
	var cost_values := Label.new()
	cost_values.text = str(first.get("production_cost", "—"))
	cost_values.theme_type_variation = &"Numeric"
	cost_values.add_theme_font_size_override("font_size", 14)
	info.add_child(cost_values)
	header.add_child(info_margin)

	# ── SOLO: clickable straight through to the building detail panel ────────────
	if solo:
		var iid := str(first.get("instance_id", ""))
		header_panel.mouse_entered.connect(func(): hp_style.border_color = DS.PALETTE.OK; header_panel.queue_redraw())
		header_panel.mouse_exited.connect(func(): hp_style.border_color = DS.PALETTE.ACCENT; header_panel.queue_redraw())
		header.gui_input.connect(func(e):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				_open_building_or_construction(iid)
				accept_event()
		)
		return card

	# ── GROUP: expand button + expandable list of individual buildings ───────────
	# Large expand button on the far right — standard DS (steel-blue) button styling.
	# The same › glyph rotates 90° to point down when expanded (no glyph swap).
	var arrow := Button.new()
	arrow.text = "›"
	arrow.focus_mode = Control.FOCUS_NONE
	arrow.custom_minimum_size = Vector2(44, 44)
	arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	arrow.add_theme_font_size_override("font_size", 30)
	header.add_child(arrow)

	# Expanded list of individual buildings, joined to the group by an off-white
	# vertical line running down the left edge.
	var expand := HBoxContainer.new()
	expand.visible = false
	expand.add_theme_constant_override("separation", 0)
	var vline := Panel.new()
	var vl_style := StyleBoxFlat.new()
	vl_style.bg_color = DS.PALETTE.ACCENT
	vl_style.set_corner_radius_all(3)
	vline.add_theme_stylebox_override("panel", vl_style)
	vline.custom_minimum_size = Vector2(5, 0)  # 5px thick
	vline.size_flags_vertical = Control.SIZE_FILL
	vline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Indent the whole line block so it sits under the group icon.
	var indent := Control.new()
	indent.custom_minimum_size = Vector2(20, 0)
	indent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	expand.add_child(indent)
	expand.add_child(vline)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 6)
	for m in members:
		rows.add_child(_make_building_row(m))
	expand.add_child(rows)
	card.add_child(expand)

	var toggle := func() -> void:
		expand.visible = not expand.visible
		arrow.pivot_offset = arrow.size * 0.5
		arrow.rotation = PI * 0.5 if expand.visible else 0.0
	arrow.pressed.connect(toggle)
	header.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			toggle.call()
			accept_event()
	)
	return card

func _make_count_badge(count: int) -> Control:
	var badge := PanelContainer.new()
	badge.custom_minimum_size = Vector2(30, 30)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := StyleBoxFlat.new()
	s.bg_color = DS.PALETTE.ACCENT  # standard off-white
	s.set_corner_radius_all(6)
	s.content_margin_left = 4
	s.content_margin_right = 4
	s.content_margin_top = 2
	s.content_margin_bottom = 2
	badge.add_theme_stylebox_override("panel", s)
	var l := Label.new()
	l.text = str(count)
	l.add_theme_font_override("font", UIFonts.mono())
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", DS.PALETTE.BG_PANEL)  # navy text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_child(l)
	return badge

# Outputs of the recipe in a frame that is pixel-identical in size/shape to the
# building icon (the ornate goods-frame art is a non-square 330×293 texture that
# distorted when squashed into a square box, so the two read as different sizes).
func _make_output_goods_frame(recipe: Dictionary, building_id: String = "") -> Control:
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(GROUP_TILE, GROUP_TILE)
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var s := StyleBoxFlat.new()  # off-white rounded square
	s.bg_color = DS.PALETTE.ACCENT
	s.border_color = DS.PALETTE.BORDER_SOFT
	s.set_border_width_all(1)
	s.set_corner_radius_all(8)
	s.set_content_margin_all(8)
	frame.add_theme_stylebox_override("panel", s)
	var center := CenterContainer.new()
	frame.add_child(center)
	# Battery storage: show the loaded chemistry (good icon + qty pill) instead of a recipe output.
	if str(Catalog.get_building(building_id).get("category", "")) == "battery":
		var chem := _primary_battery_chem(_current_tile_id)
		if chem.is_empty():
			var e := Label.new()
			e.text = "—"
			e.add_theme_color_override("font_color", DS.PALETTE.TEXT_DIM)
			center.add_child(e)
		else:
			center.add_child(_output_cell({"good_id": chem.good_id, "qty": chem.qty}, GROUP_TILE - 24))
		return frame
	var outs := _recipe_card_outputs(recipe)
	if outs.is_empty():
		var l := Label.new()
		l.text = "—"
		l.add_theme_color_override("font_color", DS.PALETTE.TEXT_DIM)
		center.add_child(l)
		return frame
	if outs.size() == 1:
		center.add_child(_output_cell(outs[0], GROUP_TILE - 24))
		return frame
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	center.add_child(grid)
	for outp in outs:
		grid.add_child(_output_cell(outp, int((GROUP_TILE - 24 - 6) / 2.0)))
	return frame

# The dominant battery chemistry loaded on a tile {good_id, qty} (or {} if none).
func _primary_battery_chem(tile_id: String) -> Dictionary:
	var cells: Dictionary = MatchState.get_tile_battery_cells(tile_id)
	var best_gid := ""
	var best_qty := 0
	for gid in cells:
		if int(cells[gid]) > best_qty:
			best_qty = int(cells[gid])
			best_gid = str(gid)
	return {} if best_gid == "" else {"good_id": best_gid, "qty": best_qty}

func _output_cell(outp: Dictionary, size: int) -> Control:
	var ogid := str(outp.good_id)
	if Catalog.get_internal_name(ogid) == "power":
		return _make_power_cell(int(outp.qty), size)
	return _make_recipe_cell(ogid, int(outp.qty), size)

const CONNECTOR_W := 18  # width of the perpendicular connector stub

# A child building card (sits under a group). No icon — it's indented under the
# group's connector line, with a perpendicular stub joining it to that line.
func _make_building_row(b: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)

	# Perpendicular connector stub joining the group's vertical line to this card.
	var stub := Control.new()
	stub.custom_minimum_size = Vector2(CONNECTOR_W, 0)
	stub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar := Panel.new()
	var bar_s := StyleBoxFlat.new()
	bar_s.bg_color = DS.PALETTE.ACCENT
	bar_s.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("panel", bar_s)
	bar.anchor_left = 0.0
	bar.anchor_right = 0.0
	bar.anchor_top = 0.5
	bar.anchor_bottom = 0.5
	bar.offset_left = 0
	bar.offset_right = CONNECTOR_W
	bar.offset_top = -2.5
	bar.offset_bottom = 2.5
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stub.add_child(bar)
	row.add_child(stub)

	# The card itself (hover state, clickable).
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0, 84)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var base_style := _building_card_style(false)
	card.add_theme_stylebox_override("panel", base_style)
	card.mouse_entered.connect(func(): card.add_theme_stylebox_override("panel", _building_card_style(true)))
	card.mouse_exited.connect(func(): card.add_theme_stylebox_override("panel", _building_card_style(false)))
	card.gui_input.connect(func(e): _on_building_row_input(e, b))

	var info := VBoxContainer.new()
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.add_theme_constant_override("separation", 3)
	card.add_child(info)

	# Title row: name + destination ('this tile'/'market') on the same row.
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	var name_label := Label.new()
	name_label.text = str(b.name)
	name_label.theme_type_variation = &"BuildingName"  # Barlow Semi 22
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_row.add_child(name_label)
	# NPC buildings (a rival company's, not yours) are tagged so they're distinguishable
	# from your own in a shared type+recipe group; the owner is in the tooltip.
	var inst := MatchState.get_building(str(b.get("instance_id", "")))
	if not inst.is_empty() and not MatchState.is_player_owned(inst):
		var npc_tag := Label.new()
		npc_tag.text = "NPC"
		npc_tag.theme_type_variation = &"BuildingName"
		npc_tag.add_theme_font_size_override("font_size", 20)
		npc_tag.add_theme_color_override("font_color", Color.WHITE)
		npc_tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		npc_tag.tooltip_text = "Operated by %s" % str(inst.get("owner", "an independent operator"))
		title_row.add_child(npc_tag)
	var dest := Label.new()
	dest.text = str(b.get("route_label", ""))
	dest.theme_type_variation = &"Body"  # same face/size as the Rural/Urban chips
	dest.add_theme_font_size_override("font_size", 13)
	dest.add_theme_color_override("font_color", DS.PALETTE.TEXT_MUTED)
	dest.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_row.add_child(dest)
	info.add_child(title_row)

	var sub := Label.new()
	sub.text = str(b.subtitle)
	sub.theme_type_variation = &"Body"  # Rural font
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", DS.PALETTE.TEXT_MUTED)
	info.add_child(sub)

	# RAG strip + land size (capitalised) on the same row.
	var rag_row := HBoxContainer.new()
	rag_row.add_theme_constant_override("separation", 8)
	var strip := _make_building_rag_strip(b)
	rag_row.add_child(strip)
	var rag_spacer := Control.new()
	rag_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rag_row.add_child(rag_spacer)
	var land := Label.new()
	land.text = ("%s LAND" % _fmt_size(float(b.land)))
	land.theme_type_variation = &"Caption"
	land.add_theme_font_size_override("font_size", 11)
	land.add_theme_color_override("font_color", DS.PALETTE.TEXT_DIM)
	rag_row.add_child(land)
	info.add_child(rag_row)
	row.add_child(card)
	return row

func _building_card_style(hovered: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = DS.PALETTE.BG_HIGHLIGHT if hovered else DS.PALETTE.BG_CARD
	s.border_color = DS.PALETTE.ACCENT if hovered else DS.PALETTE.BORDER_SOFT
	s.set_border_width_all(1)
	s.set_corner_radius_all(8)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s

const _RAG_STRIP := [
	["power", "Power"],
	["inputs_status", "Inputs"],
	["duration_status", "Transport duration"],
	["transport_cost_status", "Transport cost"],
	["produce_cost_status", "Cost to produce"],
]

func _make_building_rag_strip(b: Dictionary) -> HBoxContainer:
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 4)
	strip.custom_minimum_size = Vector2(0, 14)
	strip.mouse_filter = Control.MOUSE_FILTER_STOP
	var tip_lines: Array[String] = []
	for entry in _RAG_STRIP:
		var key: String = entry[0]
		var label_text: String = entry[1]
		var status := str(b.get("power_status" if key == "power" else key, "muted"))
		var rect := ColorRect.new()
		rect.custom_minimum_size = Vector2(20, 10)
		rect.color = _status_color(status)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		strip.add_child(rect)
		tip_lines.append("%s — %s" % [label_text, _rag_desc(label_text, status)])
	strip.tooltip_text = "\n".join(tip_lines)
	return strip

func _rag_desc(label_text: String, status: String) -> String:
	match label_text:
		"Power":
			return {"ok": "self supplied", "warn": "via grid", "problem": "not powered", "muted": "no power needed"}.get(status, status)
		"Inputs":
			return {"ok": "from your supply", "warn": "from market", "problem": "missing", "muted": "no inputs"}.get(status, status)
		"Transport duration":
			return {"ok": "arrives same turn", "warn": "multi-turn shipment", "problem": "—", "muted": "didn't run"}.get(status, status)
		"Transport cost":
			return {"ok": "no shipping cost", "warn": "paying to ship", "problem": "—", "muted": "didn't run"}.get(status, status)
		"Cost to produce":
			return {"ok": "cheaper than market", "warn": "even with market", "problem": "dearer than market", "muted": "unknown"}.get(status, status)
		_:
			return status

func _make_metric_line(label_text: String, value: String, value_color: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	var l := Label.new()
	l.text = label_text
	l.theme_type_variation = &"Caption"
	l.add_theme_font_size_override("font_size", 10)
	l.add_theme_color_override("font_color", DS.PALETTE.TEXT_DIM)
	row.add_child(l)
	var v := Label.new()
	v.text = value
	v.theme_type_variation = &"Numeric"
	v.add_theme_font_size_override("font_size", 11)
	v.add_theme_color_override("font_color", value_color)
	row.add_child(v)
	return row

func _make_supply_indicator(label_text: String, status: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	row.alignment = BoxContainer.ALIGNMENT_END
	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(9, 9)
	dot.color = _status_color(status)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.tooltip_text = _supply_tooltip(label_text, status)
	dot.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_child(dot)
	var l := Label.new()
	l.text = label_text
	l.theme_type_variation = &"Caption"
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", DS.PALETTE.TEXT_MUTED)
	row.add_child(l)
	return row

func _supply_tooltip(label_text: String, status: String) -> String:
	match status:
		"ok": return "%s: supplied by you" % label_text
		"warn": return "%s: from grid / market" % label_text
		"problem": return "%s: not supplied" % label_text
		_: return label_text

func _on_building_row_input(event: InputEvent, b: Dictionary) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_open_building_or_construction(str(b.instance_id))
		accept_event()

# A rectangle in the land-size chart was clicked — open that building's detail panel.
func _on_chart_segment_clicked(instance_id: String) -> void:
	_open_building_or_construction(instance_id)

# Open the building detail panel for either a finished building OR a construction
# project (the detail panel renders an "under construction" variation for the latter).
func _open_building_or_construction(instance_id: String) -> void:
	if instance_id == "":
		return
	var inst := MatchState.get_building(instance_id)
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

func _make_construction_row(project: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.custom_minimum_size = Vector2(0, 124)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var click_id := str(project.get("instance_id", ""))
	row.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_open_building_or_construction(click_id)
			accept_event()
	)

	var icon := _make_building_icon(str(project.get("building_id", "")), 0.55)
	row.add_child(icon)

	var bd: Dictionary = Catalog.get_building(project.get("building_id", ""))
	var p_recipe: Dictionary = Catalog.get_recipe(str(project.get("recipe_id", "")))
	var p_name := str(p_recipe.get("display_name", "")).strip_edges()
	if p_name == "":
		p_name = str(bd.get("display_name", project.get("building_id", "")))
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.add_theme_constant_override("separation", 2)
	var name_label := Label.new()
	name_label.text = p_name
	name_label.theme_type_variation = &"Body"
	name_label.add_theme_font_size_override("font_size", 14)
	info.add_child(name_label)

	var status := str(project.get("status", Construction.STATUS_UNDER_CONSTRUCTION))
	var turns_remaining := int(project.get("turns_remaining", 0))
	var status_label := Label.new()
	status_label.theme_type_variation = &"Caption"
	status_label.add_theme_font_size_override("font_size", 11)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if status == Construction.STATUS_AWAITING_MATERIALS:
		var eta := Construction.materials_eta(project)
		var eta_text := "pending delivery" if eta < 0 else "%d turn%s" % [eta, "" if eta == 1 else "s"]
		status_label.text = "Awaiting materials (%s) · %d turn build after" % [eta_text, turns_remaining]
		status_label.add_theme_color_override("font_color", DS.PALETTE.WARN)
	else:
		status_label.text = "Under construction · %d turn%s left" % [turns_remaining, "" if turns_remaining == 1 else "s"]
		status_label.add_theme_color_override("font_color", DS.PALETTE.TEXT_MUTED)
	info.add_child(status_label)
	row.add_child(info)

	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cancel.add_theme_font_size_override("font_size", 12)
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color(DS.PALETTE.DANGER, 0.16)
	cs.border_color = DS.PALETTE.DANGER
	cs.set_border_width_all(1)
	cs.set_corner_radius_all(7)
	cs.content_margin_left = 12
	cs.content_margin_right = 12
	cs.content_margin_top = 7
	cs.content_margin_bottom = 7
	cancel.add_theme_stylebox_override("normal", cs)
	cancel.add_theme_stylebox_override("hover", cs)
	cancel.add_theme_stylebox_override("pressed", cs)
	cancel.add_theme_color_override("font_color", DS.PALETTE.DANGER)
	var inst_id := str(project.get("instance_id", ""))
	cancel.pressed.connect(func(): Construction.cancel(inst_id))
	row.add_child(cancel)
	return row

func _make_building_icon(building_id: String, alpha: float, size: int = 80) -> Control:
	var holder := PanelContainer.new()
	holder.custom_minimum_size = Vector2(size, size)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# Let clicks fall through to the row so the icon is part of the clickable area.
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := StyleBoxFlat.new()
	s.bg_color = DS.PALETTE.BG_INSET
	s.border_color = DS.PALETTE.BORDER_SOFT
	s.set_border_width_all(1)
	s.set_corner_radius_all(8)
	s.set_content_margin_all(6)
	holder.add_theme_stylebox_override("panel", s)
	var bd: Dictionary = Catalog.get_building(building_id)
	var tex := _building_texture(bd)
	if tex != null:
		var rect := TextureRect.new()
		rect.texture = tex
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.modulate = Color(1, 1, 1, alpha)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(rect)
	else:
		var fallback := Label.new()
		fallback.text = str(bd.get("display_name", "?")).substr(0, 3).to_upper()
		fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		fallback.theme_type_variation = &"Numeric"
		fallback.modulate = Color(1, 1, 1, alpha)
		fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(fallback)
	return holder

func _building_texture(building_data: Dictionary) -> Texture2D:
	var building_id := str(building_data.get("id", ""))
	var internal := str(building_data.get("internal_name", ""))
	var paths: Array[String] = []
	if building_id != "" and internal != "":
		paths.append("res://assets/icons/buildings/%s_%s.png" % [building_id, internal])
	if building_id != "":
		paths.append("res://assets/icons/buildings/%s.png" % building_id)
	if internal != "":
		paths.append("res://assets/icons/buildings/%s.png" % internal)
	for p in paths:
		if ResourceLoader.exists(p):
			return load(p) as Texture2D
	return null

func _make_land_bar(bl: Dictionary) -> Control:
	var owned := float(bl.owned)
	var max_land := float(bl.max)
	var built := float(bl.used_size)
	var construction := Construction.reserved_space_on_tile(_current_tile_id)
	var owned_empty := maxf(0.0, owned - built - construction)
	var buyable := maxf(0.0, max_land - owned)

	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", 4)

	var scale := Label.new()
	scale.text = "0      %d owned      %d max" % [int(owned), int(max_land)]
	scale.theme_type_variation = &"Caption"
	scale.add_theme_font_size_override("font_size", 10)
	scale.add_theme_color_override("font_color", DS.PALETTE.TEXT_MUTED)
	container.add_child(scale)

	var bar := LAND_BAR.new()
	bar.configure(built, construction, owned_empty, buyable, max_land)
	container.add_child(bar)
	return container

func _add_bar_segment(bar: HBoxContainer, ratio: float, color: Color) -> void:
	if ratio <= 0.0:
		return
	var seg := PanelContainer.new()
	seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seg.size_flags_stretch_ratio = maxf(0.001, ratio)
	var s := StyleBoxFlat.new()
	s.bg_color = color
	bar.add_child(seg)
	seg.add_theme_stylebox_override("panel", s)

func _make_land_stat(label_text: String, value: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	var l := Label.new()
	l.text = label_text.to_upper()  # thinnest text is always uppercased
	l.theme_type_variation = &"Caption"
	l.add_theme_color_override("font_color", DS.PALETTE.TEXT_DIM)
	row.add_child(l)
	var v := Label.new()
	v.text = str(value)
	v.theme_type_variation = &"Numeric"
	v.add_theme_font_size_override("font_size", 13)
	row.add_child(v)
	return row

func _make_pipe() -> Label:
	var p := Label.new()
	p.text = "|"
	p.theme_type_variation = &"Caption"
	p.add_theme_color_override("font_color", DS.PALETTE.TEXT_DIM)
	return p

func _make_swatch(text: String, color: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	var sw := ColorRect.new()
	sw.custom_minimum_size = Vector2(11, 11)
	sw.color = color
	sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(sw)
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"Caption"
	l.add_theme_font_size_override("font_size", 10)
	l.add_theme_color_override("font_color", DS.PALETTE.TEXT_MUTED)
	row.add_child(l)
	return row

func _make_stat_card(title: String, value: String, value_color: Color, sub: String = "") -> PanelContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var s := StyleBoxFlat.new()
	s.bg_color = DS.PALETTE.BG_INSET
	s.border_color = DS.PALETTE.BORDER_SOFT
	s.set_border_width_all(1)
	s.set_corner_radius_all(10)
	s.set_content_margin_all(9)
	card.add_theme_stylebox_override("panel", s)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_child(vbox)
	var t := Label.new()
	t.text = title
	t.theme_type_variation = &"Caption"
	t.add_theme_font_size_override("font_size", 11)
	t.add_theme_color_override("font_color", DS.PALETTE.TEXT_MUTED)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER  # centre the 3 data points
	vbox.add_child(t)
	var v := Label.new()
	v.text = value
	v.theme_type_variation = &"Numeric"
	v.add_theme_font_size_override("font_size", 17)
	v.add_theme_color_override("font_color", value_color)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(v)
	if sub != "":
		var sub_label := Label.new()
		sub_label.text = sub
		sub_label.theme_type_variation = &"Caption"
		sub_label.add_theme_font_size_override("font_size", 11)
		sub_label.add_theme_color_override("font_color", DS.PALETTE.TEXT_MUTED)
		sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(sub_label)
	return card

# Each output good in its own card (same look as the building group cards): the
# good icon on an off-white rounded square, then name/destination + value/qty.
func _make_production_row(r: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0, GROUP_CARD_H)
	var cs := StyleBoxFlat.new()
	cs.bg_color = DS.PALETTE.BG_HIGHLIGHT
	cs.border_color = DS.PALETTE.ACCENT
	cs.set_border_width_all(1)
	cs.set_corner_radius_all(10)
	cs.set_content_margin_all(5)
	card.add_theme_stylebox_override("panel", cs)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)

	# Off-white rounded icon square (same size as the building group-card icon).
	var sq := PanelContainer.new()
	sq.custom_minimum_size = Vector2(GROUP_TILE, GROUP_TILE)
	sq.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var ss := StyleBoxFlat.new()
	ss.bg_color = DS.PALETTE.ACCENT
	ss.border_color = DS.PALETTE.BORDER_SOFT
	ss.set_border_width_all(1)
	ss.set_corner_radius_all(8)
	ss.set_content_margin_all(8)
	sq.add_theme_stylebox_override("panel", ss)
	sq.add_child(_make_recipe_cell(str(r.good_id), 0, GROUP_TILE - 16))
	row.add_child(sq)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.add_theme_constant_override("separation", 2)
	var name_label := Label.new()
	name_label.text = str(r.display_name)
	name_label.theme_type_variation = &"BuildingName"  # match the group cards
	info.add_child(name_label)
	# Quantity produced on this tile, under the name (Rural font). No destination line.
	var qty_sub := Label.new()
	qty_sub.text = "%d per turn" % int(r.qty)
	qty_sub.theme_type_variation = &"Body"
	qty_sub.add_theme_font_size_override("font_size", 13)
	qty_sub.add_theme_color_override("font_color", DS.PALETTE.TEXT_MUTED)
	info.add_child(qty_sub)
	row.add_child(info)

	var value := VBoxContainer.new()
	value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var val := Label.new()
	val.text = "£%.0f" % float(r.value)
	val.theme_type_variation = &"Numeric"
	val.add_theme_font_size_override("font_size", 15)
	val.add_theme_color_override("font_color", DS.PALETTE.WARN)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.add_child(val)
	row.add_child(value)
	return card

func _make_chip(text: String, accent: Color) -> Label:
	var chip := Label.new()
	chip.text = text
	chip.theme_type_variation = &"Body"
	chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN  # pill hugs its text in the rail
	chip.add_theme_font_size_override("font_size", 13)  # one token step up (was 11)
	chip.add_theme_color_override("font_color", accent)
	var style := StyleBoxFlat.new()
	style.bg_color = DS.PALETTE.BG_HIGHLIGHT
	style.border_color = Color(accent, 0.4)
	style.set_border_width_all(1)
	style.set_corner_radius_all(999)
	style.content_margin_left = 13
	style.content_margin_right = 13
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	chip.add_theme_stylebox_override("normal", style)
	return chip

func _make_action_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 12)
	return b

func _make_toggle_button(text: String, on: bool, on_press: Callable = Callable()) -> Button:
	var b := _make_action_button(text)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var make_box := func(bg: Color) -> StyleBoxFlat:
		var s := StyleBoxFlat.new()
		s.bg_color = bg
		s.set_corner_radius_all(7)
		s.content_margin_left = 17   # +5 each side → 10px wider
		s.content_margin_right = 17
		s.content_margin_top = 6
		s.content_margin_bottom = 6
		return s
	var normal_bg: Color = DS.PALETTE.WARN if on else DS.PALETTE.BG_INSET
	var hover_bg: Color = Color(DS.PALETTE.WARN).lightened(0.12) if on else DS.PALETTE.BG_HIGHLIGHT
	b.add_theme_stylebox_override("normal", make_box.call(normal_bg))
	b.add_theme_stylebox_override("hover", make_box.call(hover_bg))      # hover: colour only
	b.add_theme_stylebox_override("pressed", make_box.call(hover_bg))
	# Keep the text identical on hover (only the background colour changes).
	var fg: Color = DS.PALETTE.BG_PANEL if on else DS.PALETTE.TEXT_MUTED
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg)
	b.add_theme_color_override("font_pressed_color", fg)
	if on_press.is_valid():
		b.pressed.connect(on_press)
	return b

func _make_muted_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"Caption"
	l.add_theme_color_override("font_color", DS.PALETTE.TEXT_DIM)
	return l

# ─────────────────────────────────────────────────────────────────────────────
# Small helpers
# ─────────────────────────────────────────────────────────────────────────────
func _status_color(status: String) -> Color:
	match status:
		"ok": return DS.PALETTE.OK
		"warn": return DS.PALETTE.WARN
		"problem": return DS.PALETTE.DANGER
		_: return DS.PALETTE.TEXT_DIM

func _status_glyph(status: String) -> String:
	match status:
		"problem": return "⛔"
		"warn": return "⚠"
		_: return "✓"

func _fmt_size(value: float) -> String:
	var rounded := roundf(value)
	return str(int(rounded)) if is_equal_approx(value, rounded) else "%.1f" % value

func _sell_mode_text() -> String:
	match MatchState.sell_mode:
		MatchState.SellMode.STOCKPILE_ALL: return "this tile"
		MatchState.SellMode.BUILDING_BY_BUILDING: return "per building"
		_: return "market"

const TILE_BANNERS := {
	"rural": "res://assets/tile_banners/rural_banner.jpg",
	"grass": "res://assets/tile_banners/rural_banner.jpg",
	"urban": "res://assets/tile_banners/urban_banner.jpg",
	"hill": "res://assets/tile_banners/hill_banner.jpg",
	"hills": "res://assets/tile_banners/hill_banner.jpg",
	"mountain": "res://assets/tile_banners/mountain_banner.jpg",
	"mountains": "res://assets/tile_banners/mountain_banner.jpg",
	"sea": "res://assets/tile_banners/sea_banner.jpg",
	"ocean": "res://assets/tile_banners/sea_banner.jpg",
	"deep sea": "res://assets/tile_banners/deep_sea_banner.jpg",
	"deep_sea": "res://assets/tile_banners/deep_sea_banner.jpg",
	"deep ocean": "res://assets/tile_banners/deep_sea_banner.jpg",
}
var _banner_cache: Dictionary = {}  # path -> Texture2D

func _refresh_banner_image(tile_data: Dictionary) -> void:
	if _banner_texture == null:
		return
	var tile_type := str(tile_data.get("type", "")).strip_edges().to_lower()
	var path := str(TILE_BANNERS.get(tile_type, ""))
	if path == "":
		_banner_texture.texture = null
		return
	if not _banner_cache.has(path):
		_banner_cache[path] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	_banner_texture.texture = _banner_cache.get(path)

func _survey_status_for_tile(tile_data: Dictionary) -> String:
	var explicit := str(tile_data.get("survey_status", "")).strip_edges()
	if explicit != "":
		return explicit
	match MatchState.survey_status(str(tile_data.get("id", "")), str(tile_data.get("type", ""))):
		"surveyed": return "Surveyed"
		"partial": return "Partially surveyed"
		_: return "Unsurveyed"
