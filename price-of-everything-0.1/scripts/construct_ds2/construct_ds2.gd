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
const Catalogue := preload("res://scripts/construct_ds2/catalogue.gd")
const MoneyFigure := preload("res://scripts/ds2/money_figure.gd")
const Plate := preload("res://scripts/bdp_v3_plate.gd")
const Key := preload("res://scripts/bdp_v3_key.gd")
const Scroll := preload("res://scripts/bdp_v3_scroll.gd")
const LampOverlay := preload("res://scripts/ds2/lamp_overlay.gd")
const Light := preload("res://scripts/bdp_v3_light.gd")
const Parts := preload("res://scripts/tvp_v3/buildings_parts.gd")

const CAPTURE_SCALE := 1.875
const TEXELS := 2.0
## layout.json construct_panel: the panel at 1125 layout px (600 logical), the content column from x 80, 1005 wide.
const WIDTH := 1125.0 / CAPTURE_SCALE
const CONTENT_X := 80.0 / CAPTURE_SCALE
const CONTENT_W := 1005.0 / CAPTURE_SCALE
const HEAD_H := 244.0 / CAPTURE_SCALE
## Where the catalogue's control plate starts (its tab rises under the jib, between the cab and the site's plate).
const PLATE_Y := 152.0 / CAPTURE_SCALE
## The Construct settings on the crane: a steel plate bolted over the jib's root, a white key with a navy gear
## (layout.json construct_settings: the render's origin and size).
const SETTINGS_AT := Vector2(336.0, 34.0) / CAPTURE_SCALE
const SETTINGS_SIZE := Vector2(122.0, 118.0) / CAPTURE_SCALE
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
var _settings_key: TextureButton
var _catplate: Control
var _quote: Dictionary = {}
## The glow over what blocks a refused build, and what it last pointed at (for tests).
var _flash: BlockerGlow
var last_flagged := ""
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
	var gear := TextureButton.new()
	gear.name = "SettingsKey"
	gear.texture_normal = Plate.tex("construct_settings")
	gear.texture_pressed = Plate.tex("construct_settings_pressed")
	gear.ignore_texture_size = true
	gear.stretch_mode = TextureButton.STRETCH_SCALE
	gear.position = SETTINGS_AT
	gear.size = SETTINGS_SIZE
	gear.tooltip_text = "Construct settings"
	gear.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	gear.pressed.connect(func() -> void:
		if _view == View.SETTINGS:
			_on_back_from_settings()
		else:
			_on_settings_pressed())
	_head.add_child(gear)
	_settings_key = gear
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
	_search_margin.add_child(_search_input)

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

	# The catalogue's control plate: the search set into its tab, the category keys.
	_catplate = Catalogue.control_plate(_search_input, _pick_category)
	_catplate.visible = false
	body.add_child(_catplate)

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
	# A glow belongs to the view it pointed into.
	if _flash != null and is_instance_valid(_flash):
		_flash.stop()
	super._render()
	_sync_head()


## The head follows the stage: on the build order the Back key shows and the head reaches down to where the
## board hangs; the site's plate hangs from the jib whenever a site is chosen.
func _sync_head() -> void:
	if _head == null:
		return
	var order := _is_build_order()
	var browsing := _view == View.BROWSE
	_head.custom_minimum_size.y = BOARD_Y if order else (PLATE_Y if browsing else HEAD_H)
	_back_key.visible = _view == View.CONFIRM
	_catplate.visible = browsing
	_mode_toggle.visible = false
	_search_margin.visible = false
	_filter_margin.visible = false
	var site := _site_name()
	_placard_label.text = site.to_upper()
	_placard_label.visible = site != ""
	queue_redraw()


func _is_build_order() -> bool:
	return _view == View.CONFIRM


func _site_name() -> String:
	if _locked_tile_id == "":
		return ""
	return Catalog.tile_name(_locked_tile_id)


## The catalogue: the control plate under the crane, then the site boards two to a row; the building opened
## across the width with its recipe tags hung under it.
func _render_browse() -> void:
	_set_panel_width(false)
	_search_input.visible = true
	Catalogue.show_filter(_catplate, _active_filters)
	_content.add_theme_constant_override("separation", roundi(Catalogue.CARD_GAP))
	if _output_good_filter != "":
		_content.add_child(_goods_tag())
	var query := _search_query.strip_edges().to_lower()
	var shown := _filtered_buildings()
	if shown.is_empty():
		var nothing_here := _locked_tile_id != "" and query == "" and _active_filters.is_empty()
		var empty := Parts.body("Nothing can be built on this tile." if nothing_here else "No buildings match.")
		empty.name = "CatalogueEmpty"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.custom_minimum_size = Vector2(0, 80)
		_content.add_child(empty)
		return
	var half := (CONTENT_W - Catalogue.CARD_GAP) * 0.5
	var source := _current_material_source()
	var condensed := not UiPrefs.construct_expanded_recipe_mode
	var row: HBoxContainer = null
	for building: Dictionary in shown:
		var bid := str(building.get("id", ""))
		var infra := str(building.get("category", "")).to_lower() == "infrastructure"
		var recipes := _visible_recipes_for(building, query)
		var price := Catalogue.price(bid, _locked_tile_id, _locked_tile_data, source)
		var reason := ""
		if recipes.is_empty() and not infra:
			reason = "No recipe of it can be built here."
		elif MatchState.money + 0.0001 < price:
			reason = "Needs %s, you have %s." % [MoneyFigure.text(price), MoneyFigure.text(MatchState.money)]
		var press := func() -> void: pass
		if infra:
			press = func() -> void: _on_infrastructure_selected(bid)
		elif not recipes.is_empty():
			press = func() -> void: _on_building_pressed(bid)
		if bid == _expanded_building_id and not infra and not recipes.is_empty():
			row = null
			_content.add_child(Catalogue.site_card(building, CONTENT_W, price, reason, press))
			for recipe: Dictionary in recipes:
				var rid := str(recipe.get("recipe_id", ""))
				var drop := Control.new()
				# The rows' own gap falls either side of this spacer, so the tag hangs TAG_DROP below.
				drop.custom_minimum_size = Vector2(0, maxf(0.0, Catalogue.TAG_DROP - 2.0 * roundi(Catalogue.CARD_GAP)))
				drop.mouse_filter = Control.MOUSE_FILTER_IGNORE
				_content.add_child(drop)
				_content.add_child(Catalogue.recipe_tag(bid, recipe, condensed, func() -> void: _on_recipe_pressed(bid, rid)))
			continue
		if row == null or row.get_child_count() >= 2:
			row = HBoxContainer.new()
			row.add_theme_constant_override("separation", roundi(Catalogue.CARD_GAP))
			_content.add_child(row)
		row.add_child(Catalogue.site_card(building, half, price, reason, press))


## A category key pressed: that category alone, or all again when it was already the one shown.
func _pick_category(id: String) -> void:
	_on_filter_toggled(not _active_filters.has(id), id)


## The goods filter, shown and removable: the catalogue narrowed to what makes a good.
func _goods_tag() -> Control:
	var row := HBoxContainer.new()
	row.name = "GoodsFilter"
	row.add_theme_constant_override("separation", 10)
	var words := Parts.body("Buildings that make %s." % Catalog.get_display_name(_output_good_filter))
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(words)
	var clear := Parts.key_button("Show all", "ClearGoodsFilter", 0.62)
	clear.size_flags_horizontal = Control.SIZE_SHRINK_END
	clear.custom_minimum_size.x = 104.0
	clear.pressed.connect(func() -> void:
		_output_good_filter = ""
		_load_data()
		_render())
	row.add_child(clear)
	return row


## Every confirm is the build order, whatever the v3 confirm toggle says: a recipe's, and infrastructure's with
## its purpose on the sign and its levels in place of the outlook.
func _render_confirm() -> void:
	_render_confirm_v3()


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
	_v3_forecast = BuildForecast.project(building_id, recipe_id, _locked_tile_id) if recipe_id != "" else {}
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


## The land this build buys follows the Construct setting "Auto-buy land" until the player chooses on the
## build order itself (the Land row's Buy land key).
func _v3_compute_land() -> Dictionary:
	var out := super._v3_compute_land()
	if bool(out.get("purchasable", false)) and not _land_toggle_touched:
		_buy_land_wanted = MatchState.construct_auto_buy_land
		out.covered = _buy_land_wanted
	return out


## The Land row's Buy land key: this build buys the land it is short.
func buy_land() -> void:
	_land_toggle_touched = true
	_buy_land_wanted = true
	_render()


## A refused Build pressed: the part that blocks it glows, the money on the verdict or the requirement's row on the
## feeder pillar (brought into view first), as the quote's first block says.
func flag_blocker() -> void:
	var blocks: Array = quote().get("blocks", [])
	if blocks.is_empty():
		return
	var want := BuildOrder.blocker_for(str((blocks[0] as Dictionary).get("key", "")))
	var target: Control = null
	for n in find_children("*", "Control", true, false):
		if str((n as Control).get_meta("blocker", "")) == want and (n as Control).is_visible_in_tree():
			target = n
			break
	if target == null:
		return
	last_flagged = want
	if _content.is_ancestor_of(target):
		_scroll.ensure_control_visible(target)
		await get_tree().process_frame
	if _flash == null or not is_instance_valid(_flash):
		_flash = BlockerGlow.new()
		add_child(_flash)
	move_child(_flash, get_child_count() - 1)
	_flash.pulse(Rect2(target.global_position - global_position, target.size))


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


## A red lamp glow laid over a part of the panel and pulsed twice: what blocks a refused build. Drawn over the
## panel's children, added in (the lamp glows' material), so the part reads as lit, not covered.
class BlockerGlow extends Control:
	const PULSES := 2
	const UP := 0.16
	const DOWN := 0.42
	const SPREAD := Vector2(40.0, 30.0)
	## Added twice at the peak: over a lit red LED one pass barely shows.
	const PASSES := 2
	var _rect := Rect2()
	var strength := 0.0:
		set(v):
			strength = v
			queue_redraw()

	func _init() -> void:
		name = "BlockerGlow"
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)
		material = Light.glow_material()
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

	var _tween: Tween

	func stop() -> void:
		if _tween != null and _tween.is_valid():
			_tween.kill()
		strength = 0.0

	func pulse(rect: Rect2) -> void:
		stop()
		_rect = rect
		var tw := create_tween()
		_tween = tw
		for i in PULSES:
			tw.tween_property(self, "strength", 1.0, UP).set_trans(Tween.TRANS_SINE)
			tw.tween_property(self, "strength", 0.0, DOWN).set_trans(Tween.TRANS_SINE)

	func _draw() -> void:
		if strength <= 0.0:
			return
		var tex := Plate.tex("lamp_glow_red")
		if tex != null:
			for i in PASSES:
				draw_texture_rect(tex, _rect.grow_individual(SPREAD.x, SPREAD.y, SPREAD.x, SPREAD.y), false, Color(1, 1, 1, strength))
