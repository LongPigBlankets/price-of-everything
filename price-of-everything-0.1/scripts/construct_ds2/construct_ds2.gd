extends "res://scripts/construct_panel_v2.gd"
## The construct panel in DS2, the construction lot with its crane (docs/construct-ds2-plan.md), behind
## `toggle construct ds2` (UiPrefs.use_construct_ds2). The same panel as construct_panel_v2.gd, its ways in,
## its state, its Confirm and every handle the tutorial and the tests look up (ConstructPanelV2,
## BuildConfirmButton, RecipeRow_<id>, ConstructionMaterialsSection), in the lot's look: a navy steel hoarding,
## the yellow tower crane along its top with CONSTRUCT on its cab and the site's name on a plate hung from its
## jib, one width for every stage.
##
## The build order (build_order.gd) hangs the site board from the hook: what is built, then the verdict, then
## the requirements, the cost, the materials yard, the outlook and the land. Its figures and its refusal are
## ConstructionRules.quote()'s. The catalogue and the settings keep today's bodies inside the hoarding until
## their own DS2 bodies are built (plan §7, phases 4 and 5).
##
## The parts are renders (tools/button_mockup/cluster.html, sets constructhead, constructboard, constructyard)
## placed at the layout's own coordinates: layout px from the panel's top-left, divided by CAPTURE_SCALE.

const BuildOrder := preload("res://scripts/construct_ds2/build_order.gd")
const Plate := preload("res://scripts/bdp_v3_plate.gd")
const Key := preload("res://scripts/bdp_v3_key.gd")
const Scroll := preload("res://scripts/bdp_v3_scroll.gd")
const LampOverlay := preload("res://scripts/ds2/lamp_overlay.gd")
const Parts := preload("res://scripts/tvp_v3/buildings_parts.gd")

const CAPTURE_SCALE := 1.875
const TEXELS := 2.0
## layout.json construct_panel: the panel at 1125 layout px (600 logical), the content column from x 80, 1005 wide.
const WIDTH := 1125.0 / CAPTURE_SCALE
const CONTENT_X := 80.0 / CAPTURE_SCALE
const CONTENT_W := 1005.0 / CAPTURE_SCALE
const HEAD_H := 244.0 / CAPTURE_SCALE
## Where the build order's site board hangs (under the hook, the spreader and its chains).
const BOARD_Y := 334.0 / CAPTURE_SCALE
## The tower's bay under the head, repeated down the hoarding's left edge.
const MAST_AT := 244.0 / CAPTURE_SCALE
const MAST_SIZE := Vector2(120.0, 104.0) / CAPTURE_SCALE
## The site's name plate hung from the jib: the render's origin and size, and the face the name is printed on.
const PLACARD_AT := Vector2(749.0, 128.0) / CAPTURE_SCALE
const PLACARD_SIZE := Vector2(272.0, 104.0) / CAPTURE_SCALE
const PLACARD_FACE := Rect2(775.0, 157.0, 216.0, 56.0)
## The trolley's render (its centre 42 layout px in from its left) and where it rides on the jib: over the
## catalogue, and over the site board on the build order, where the rig hangs from it.
const TROLLEY_AT_Y := 106.0 / CAPTURE_SCALE
const TROLLEY_SIZE := Vector2(84.0, 48.0) / CAPTURE_SCALE
const TROLLEY_CENTRE := 42.0 / CAPTURE_SCALE
const TROLLEY_BROWSE_X := 668.0 / CAPTURE_SCALE
const TROLLEY_ORDER_X := 585.5 / CAPTURE_SCALE
const RIG_AT := Vector2(80.0, 136.0) / CAPTURE_SCALE
const RIG_SIZE := Vector2(1005.0, 222.0) / CAPTURE_SCALE
## The Close and Back keys at the hoarding's right edge, beside the jib's tip.
const CLOSE_CENTRE := Vector2(1065.0, 76.0) / CAPTURE_SCALE
const BACK_CENTRE := Vector2(1065.0, 160.0) / CAPTURE_SCALE
const KEY_PX := 34.0
## The site's name: Bebas on the black enamel plate.
const PLACARD_FONT: FontFile = preload("res://assets/fonts/BebasNeue-Regular.ttf")
const PLACARD_PX := 22

var _head: Control
var _placard_label: Label
var _back_key: Control
var _settings_key: Control
var _quote: Dictionary = {}
## The build order last shown (building, recipe, site): a new one opens at its top.
var _view_opened := ""


func _ready() -> void:
	super._ready()
	var bare := StyleBoxEmpty.new()
	add_theme_stylebox_override("panel", bare)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_set_panel_width(false)
	LampOverlay.attach(self)


## One width for every stage (plan §4), whatever the stage asks for.
func _set_panel_width(_narrow: bool) -> void:
	offset_right = offset_left + WIDTH
	custom_minimum_size.x = WIDTH


## The shell: the head (the crane's room, the keys, the site's name), then today's search, filters and pinned
## band, the scrolling body and the footer, in the content column. Every member the panel's code reads is
## built, so its stages render into it unchanged.
func _build_shell() -> void:
	var root := VBoxContainer.new()
	root.name = "LotRoot"
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	_head = Control.new()
	_head.name = "LotHead"
	_head.mouse_filter = Control.MOUSE_FILTER_PASS
	_head.custom_minimum_size = Vector2(WIDTH, HEAD_H)
	root.add_child(_head)
	var close: TextureButton = Key.make("close", KEY_PX)
	close.name = "CloseKey"
	close.position = CLOSE_CENTRE - Vector2(KEY_PX, KEY_PX) * 0.5
	close.tooltip_text = "Close"
	close.pressed.connect(hide)
	_head.add_child(close)
	var back: TextureButton = Key.make("back", KEY_PX)
	back.name = "BackKey"
	back.position = BACK_CENTRE - Vector2(KEY_PX, KEY_PX) * 0.5
	back.tooltip_text = "Back to the buildings"
	back.pressed.connect(_on_back_to_browse)
	back.visible = false
	_head.add_child(back)
	_back_key = back
	_placard_label = Label.new()
	_placard_label.name = "SiteName"
	_placard_label.add_theme_font_override("font", PLACARD_FONT)
	_placard_label.add_theme_font_size_override("font_size", PLACARD_PX)
	_placard_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_placard_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_placard_label.clip_text = true
	_placard_label.position = PLACARD_FACE.position / CAPTURE_SCALE
	_placard_label.size = PLACARD_FACE.size / CAPTURE_SCALE
	_placard_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Parts.emboss(_placard_label)
	_placard_label.visible = false
	_head.add_child(_placard_label)

	var column := MarginContainer.new()
	column.name = "LotColumn"
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("margin_left", roundi(CONTENT_X))
	column.add_theme_constant_override("margin_right", roundi(WIDTH - CONTENT_X - CONTENT_W))
	column.add_theme_constant_override("margin_bottom", 14)
	root.add_child(column)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 0)
	column.add_child(body)

	# What the panel's code reads, kept but not shown in DS2: the header labels, the gear and the mode row.
	_header_title = Label.new()
	_header_subtitle = Label.new()
	_close_button = Button.new()
	_close_button.pressed.connect(hide)
	_settings_button = Button.new()
	_settings_button.name = "SettingsButton"
	_settings_button.pressed.connect(_on_settings_pressed)
	_mode_toggle = HBoxContainer.new()
	_mode_toggle.visible = false
	for n: Control in [_header_title, _header_subtitle, _close_button, _settings_button]:
		n.visible = false
		_mode_toggle.add_child(n)
	body.add_child(_mode_toggle)

	_search_margin = MarginContainer.new()
	_search_margin.add_theme_constant_override("margin_top", 4)
	body.add_child(_search_margin)
	_search_input = LineEdit.new()
	_search_input.placeholder_text = "Search buildings and recipes"
	_search_input.clear_button_enabled = true
	_search_input.custom_minimum_size = Vector2(0, 38)
	_search_input.add_theme_font_size_override("font_size", 13)
	_search_input.text_changed.connect(_on_search_changed)
	_search_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var search_row := HBoxContainer.new()
	search_row.add_theme_constant_override("separation", 10)
	_search_margin.add_child(search_row)
	search_row.add_child(_search_input)
	# The Construct settings, at the end of the search row on the catalogue.
	var settings := Parts.key_button("Settings", "SettingsKey", 0.62)
	settings.size_flags_horizontal = Control.SIZE_SHRINK_END
	settings.custom_minimum_size.x = 96.0
	settings.pressed.connect(_on_settings_pressed)
	search_row.add_child(settings)
	_settings_key = settings

	_filter_margin = MarginContainer.new()
	_filter_margin.add_theme_constant_override("margin_top", 10)
	_filter_margin.add_theme_constant_override("margin_bottom", 12)
	body.add_child(_filter_margin)
	_filter_scroll = ScrollContainer.new()
	_filter_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_filter_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_filter_scroll.custom_minimum_size = Vector2(0, 45)
	_filter_margin.add_child(_filter_scroll)
	_filter_row = HBoxContainer.new()
	_filter_row.add_theme_constant_override("separation", 6)
	_filter_scroll.add_child(_filter_row)

	# The build order's fixed head: the site board and the verdict, the seam under them.
	_pinned = VBoxContainer.new()
	_pinned.name = "LotPinned"
	_pinned.visible = false
	_pinned.add_theme_constant_override("separation", 0)
	body.add_child(_pinned)

	_scroll = ScrollContainer.new()
	_scroll.name = "LotScroll"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	Scroll.apply(_scroll, true)
	body.add_child(_scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 8)
	_scroll.add_child(_content)

	_footer_rule = Control.new()
	_footer_rule.visible = false
	body.add_child(_footer_rule)
	_footer_panel = PanelContainer.new()
	_footer_panel.visible = false
	_footer_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_footer = HBoxContainer.new()
	_footer.custom_minimum_size = Vector2(0, 54)
	_footer.add_theme_constant_override("separation", 10)
	_footer_panel.add_child(_footer)
	body.add_child(_footer_panel)


func _render() -> void:
	super._render()
	_sync_head()


## The head follows the stage: on the build order the Back key shows and the head reaches down to where the
## board hangs; the site's plate hangs from the jib whenever a site is chosen.
func _sync_head() -> void:
	if _head == null:
		return
	var order := _is_build_order()
	_head.custom_minimum_size.y = BOARD_Y if order else HEAD_H
	_back_key.visible = _view == View.CONFIRM
	_settings_key.visible = _view == View.BROWSE
	_mode_toggle.visible = false
	var site := _site_name()
	_placard_label.text = site.to_upper()
	_placard_label.visible = site != ""
	queue_redraw()


func _is_build_order() -> bool:
	return _view == View.CONFIRM and not _selected_recipe.is_empty()


func _site_name() -> String:
	if _locked_tile_id == "":
		return ""
	return Catalog.tile_name(_locked_tile_id)


## Every recipe's confirm is the build order, whatever the v3 confirm toggle says; infrastructure keeps
## today's confirm inside the hoarding until the build order takes it (plan §7, phase 3).
func _render_confirm() -> void:
	if not _selected_recipe.is_empty():
		_render_confirm_v3()
		return
	super._render_confirm()


func _render_confirm_v3() -> void:
	_set_panel_width(false)
	_search_input.visible = false
	_search_margin.visible = false
	_filter_scroll.visible = false
	_filter_margin.visible = false
	_confirm_flash_pending = false
	# The state Confirm reads (the land to buy, the ledger, the forecast), as the v3 confirm computes it.
	var building_id := str(_selected_building.get("id", ""))
	var recipe_id := str(_selected_recipe.get("recipe_id", ""))
	_v3_land = _v3_compute_land()
	_v3_ledger = Construction.materials_ledger(building_id, _locked_tile_id)
	_v3_forecast = BuildForecast.project(building_id, recipe_id, _locked_tile_id)
	_quote = quote()
	if _view_opened != _order_key():
		_view_opened = _order_key()
		_scroll.scroll_vertical = 0
	_pinned.visible = true
	BuildOrder.build(self, _quote)


func _order_key() -> String:
	return "%s|%s|%s" % [str(_selected_building.get("id", "")), str(_selected_recipe.get("recipe_id", "")), _locked_tile_id]


## The build order's figures and verdict: ConstructionRules.quote() for this building, recipe, site, source
## and land choice, the same the build acts on.
func quote() -> Dictionary:
	return BuildOrder.Rules.quote(str(_selected_building.get("id", "")), str(_selected_recipe.get("recipe_id", "")),
		_locked_tile_id, _locked_tile_data, {"source": _current_material_source(), "buy_land": _buy_land_wanted})


## The Build key's refusal: the quote's first block, in its own words.
func _v3_confirm_block_reason() -> String:
	var q := quote()
	var blocks: Array = q.get("blocks", [])
	return str((blocks[0] as Dictionary).get("text", "")) if not blocks.is_empty() else ""


## The source knob turned: this build's materials come from `id` (the Construct setting keeps its own).
func pick_material_source(id: String) -> void:
	MatchState.pending_build_material_source = id
	_render()


## The hoarding, the tower down its left edge and the crane's head; the site's plate when a site is chosen;
## the trolley, and on the build order the rig lowering the site board. All under the panel's children.
func _draw() -> void:
	var w := size.x
	var h := size.y
	var hoarding := Plate.tex("construct_hoarding")
	if hoarding != null:
		var src_h := minf(h * TEXELS, hoarding.get_height())
		draw_texture_rect_region(hoarding, Rect2(0, 0, w, src_h / TEXELS), Rect2(0, 0, minf(w * TEXELS, hoarding.get_width()), src_h))
	var mast := Plate.tex("construct_mast")
	if mast != null:
		var y := MAST_AT
		while y < h:
			var part := minf(MAST_SIZE.y, h - y)
			draw_texture_rect_region(mast, Rect2(0, y, MAST_SIZE.x, part), Rect2(0, 0, mast.get_width(), part * TEXELS))
			y += MAST_SIZE.y
	if _placard_label != null and _placard_label.visible:
		_draw_layer("construct_placard", Rect2(PLACARD_AT, PLACARD_SIZE))
	var order := _is_build_order()
	var tx := TROLLEY_ORDER_X if order else TROLLEY_BROWSE_X
	if order:
		_draw_layer("construct_rig", Rect2(RIG_AT, RIG_SIZE))
	_draw_layer("construct_head", Rect2(Vector2.ZERO, Vector2(WIDTH, HEAD_H)))
	_draw_layer("construct_trolley", Rect2(Vector2(tx - TROLLEY_CENTRE, TROLLEY_AT_Y), TROLLEY_SIZE))


func _draw_layer(layer: String, rect: Rect2) -> void:
	var tex := Plate.tex(layer)
	if tex != null:
		draw_texture_rect(tex, rect, false)
