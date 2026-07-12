extends PanelContainer
## Experimental construct-panel redesign, reached only through
## `swap construct_panel`.
##
## The sequence is intentionally independent of a tile:
##   browse building → choose recipe → confirm → choose tile on the map.
## The final map click still goes through BuildMode/world_map, retaining every
## existing terrain, capacity, money, material and construction-order check.

const GoodIcons := preload("res://scripts/good_icons.gd")
const BuildingIcon := preload("res://scripts/building_icon.gd")

const NAVY := Color("#0b1726")
const NAVY_RAISED := Color("#10233a")
const NAVY_FIELD := Color("#0a1725")
const NAVY_LINE := Color("#22384f")
const TEXT := Color("#e6edf5")
const MUTED := Color("#8da0b6")
const GOLD := Color("#e6b34a")
const GOLD_DARK := Color("#c48d35")
const GREEN := Color("#5fbf6b")
const CREAM := Color("#f4e6c0")
const CREAM_SHADOW := Color("#9f875d")
const METAL_LIGHT := Color("#c4ced8")
const RECIPE_ROW_HEIGHT := 116

enum View { BROWSE, CONFIRM }


## A self-painted recipe plate in the same visual family as the ledger and tile
## building cards: brushed navy metal with a raised silver bezel, lit from the
## top-left and shaded at the bottom-right.
class MetalRecipeRow extends Button:
	const PLATE_TL := Color("#1d466d")
	const PLATE_MID := Color("#102b47")
	const PLATE_BR := Color("#07182a")
	const BEZEL_LT := Color("#c1cbd5")
	const BEZEL_DK := Color("#46515d")

	func _ready() -> void:
		flat = true
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)
		focus_entered.connect(queue_redraw)
		focus_exited.connect(queue_redraw)

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size).grow(-1.0)
		if r.size.x <= 2.0 or r.size.y <= 2.0:
			return
		var outer := StyleBoxFlat.new()
		outer.bg_color = BEZEL_DK
		outer.border_color = BEZEL_LT
		outer.set_border_width_all(1)
		outer.set_corner_radius_all(11)
		draw_style_box(outer, r)
		var inner := r.grow(-3.0)
		var fill := StyleBoxFlat.new()
		fill.bg_color = PLATE_MID.lightened(0.08) if is_hovered() else PLATE_MID
		fill.set_corner_radius_all(8)
		draw_style_box(fill, inner)
		# Layered corner tints reproduce the tile cards' directional, brushed-metal
		# sheen without relying on a renderer-specific shader.
		var sheen_quad := PackedVector2Array([
			inner.position + Vector2(2, 2),
			Vector2(inner.end.x - 2, inner.position.y + 2),
			inner.end - Vector2(2, 2),
			Vector2(inner.position.x + 2, inner.end.y - 2),
		])
		draw_polygon(sheen_quad, PackedColorArray([
			Color(PLATE_TL.lightened(0.16), 0.72),
			Color(PLATE_TL, 0.10),
			Color(PLATE_BR, 0.08),
			Color(PLATE_BR, 0.30),
		]))
		draw_line(inner.position + Vector2(2, 1), Vector2(inner.end.x - 2, inner.position.y + 1), PLATE_TL, 2.0)
		draw_line(inner.position + Vector2(1, 2), Vector2(inner.position.x + 1, inner.end.y - 2), PLATE_TL.lightened(0.18), 2.0)
		draw_line(Vector2(inner.position.x + 2, inner.end.y - 1), inner.end - Vector2(2, 1), PLATE_BR, 2.0)
		draw_line(Vector2(inner.end.x - 1, inner.position.y + 2), inner.end - Vector2(1, 2), PLATE_BR.darkened(0.22), 2.0)
		# Fine horizontal brush strokes match the ledger and tile-view cards.
		var brush_y := inner.position.y + 5.0
		var brush_index := 0
		while brush_y < inner.end.y - 4.0:
			var alpha := 0.018 + 0.016 * absf(sin(float(brush_index) * 12.9898))
			draw_line(Vector2(inner.position.x + 4, brush_y), Vector2(inner.end.x - 4, brush_y), Color(0.84, 0.91, 0.98, alpha), 1.0)
			brush_y += 3.0
			brush_index += 1

var _header_title: Label
var _header_subtitle: Label
var _close_button: Button
var _search_input: LineEdit
var _filter_scroll: ScrollContainer
var _filter_row: HBoxContainer
var _scroll: ScrollContainer
var _content: VBoxContainer
var _footer: HBoxContainer

var _view := View.BROWSE
var _buildings: Array = []
var _recipes_by_building: Dictionary = {}
var _active_category := "all"
var _search_query := ""
var _expanded_building_id := ""
var _selected_building: Dictionary = {}
var _selected_recipe: Dictionary = {}
var _output_good_filter := ""


func _ready() -> void:
	name = "ConstructPanelV2"
	visible = false
	offset_left = 16.0
	offset_top = 78.0
	offset_right = 576.0
	offset_bottom = 958.0
	custom_minimum_size = Vector2(510, 720)
	add_theme_stylebox_override("panel", _panel_style(NAVY, GOLD_DARK, 2, 14, 0))
	_build_shell()
	_load_data()
	if not MatchState.unlock_granted.is_connected(_on_unlock_granted):
		MatchState.unlock_granted.connect(_on_unlock_granted)
	if not MatchState.show_construct_for_good.is_connected(open_for_output_good):
		MatchState.show_construct_for_good.connect(open_for_output_good)
	if not MarketState.prices_updated.is_connected(_on_prices_updated):
		MarketState.prices_updated.connect(_on_prices_updated)
	visibility_changed.connect(_on_visibility_changed)


func open_for_output_good(good_id: String) -> void:
	if not MatchState.use_construct_panel_v2:
		return
	_output_good_filter = good_id
	_reset_to_browse()
	_load_data()
	_render()
	show()


func open_browser() -> void:
	if not MatchState.use_construct_panel_v2:
		return
	_output_good_filter = ""
	_reset_to_browse()
	_load_data()
	_render()
	show()


## Kept as a compatible entry point for the Tile View Panel. The V2 flow does
## not retain this tile: the player still confirms the build first, then chooses
## a site on the map.
func open_for_tile(_tile_id: String, _tile_data: Dictionary) -> void:
	if not MatchState.use_construct_panel_v2:
		return
	_output_good_filter = ""
	_reset_to_browse()
	_load_data()
	_render()
	show()


func _reset_to_browse() -> void:
	_active_category = "all"
	_search_query = ""
	_expanded_building_id = ""
	_selected_building = {}
	_selected_recipe = {}
	_view = View.BROWSE
	if _search_input != null:
		_search_input.text = ""


func _on_visibility_changed() -> void:
	if not visible:
		PanelStack.remove(self)
		return
	if not MatchState.use_construct_panel_v2:
		hide()
		return
	_load_data()
	_render()


func _on_unlock_granted(_title: String, _description: String, _via_condition: bool) -> void:
	_load_data()
	if visible:
		_render()


func _on_prices_updated() -> void:
	if visible and _view == View.BROWSE:
		_render()


func _build_shell() -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 0)
	margin.add_child(root)

	var header := HBoxContainer.new()
	header.custom_minimum_size = Vector2(0, 42)
	header.add_theme_constant_override("separation", 10)
	root.add_child(header)

	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.add_theme_constant_override("separation", 1)
	header.add_child(title_box)
	_header_title = Label.new()
	_header_title.text = "CONSTRUCT"
	_header_title.add_theme_font_size_override("font_size", 21)
	_header_title.add_theme_color_override("font_color", TEXT)
	title_box.add_child(_header_title)
	_header_subtitle = Label.new()
	_header_subtitle.text = "Choose a building, recipe, then construction site"
	_header_subtitle.add_theme_font_size_override("font_size", 11)
	_header_subtitle.add_theme_color_override("font_color", MUTED)
	title_box.add_child(_header_subtitle)

	_close_button = Button.new()
	_close_button.text = "×"
	_close_button.tooltip_text = "Close construct panel"
	_close_button.custom_minimum_size = Vector2(32, 32)
	_close_button.add_theme_font_size_override("font_size", 20)
	_style_button(_close_button, NAVY_RAISED, NAVY_LINE, TEXT)
	_close_button.pressed.connect(hide)
	header.add_child(_close_button)

	var rule := HSeparator.new()
	rule.add_theme_constant_override("separation", 8)
	root.add_child(rule)

	_search_input = LineEdit.new()
	_search_input.placeholder_text = "Search buildings and recipes"
	_search_input.clear_button_enabled = true
	_search_input.custom_minimum_size = Vector2(0, 38)
	_search_input.add_theme_font_size_override("font_size", 13)
	_search_input.add_theme_color_override("font_color", TEXT)
	_search_input.add_theme_color_override("font_placeholder_color", MUTED)
	_search_input.add_theme_stylebox_override("normal", _panel_style(NAVY_FIELD, NAVY_LINE, 1, 8, 9))
	_search_input.add_theme_stylebox_override("focus", _panel_style(NAVY_FIELD, GOLD_DARK, 1, 8, 9))
	_search_input.text_changed.connect(_on_search_changed)
	root.add_child(_search_input)

	var filter_margin := MarginContainer.new()
	filter_margin.add_theme_constant_override("margin_top", 9)
	filter_margin.add_theme_constant_override("margin_bottom", 10)
	root.add_child(filter_margin)
	_filter_scroll = ScrollContainer.new()
	_filter_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_filter_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	filter_margin.add_child(_filter_scroll)
	_filter_row = HBoxContainer.new()
	_filter_row.add_theme_constant_override("separation", 6)
	_filter_scroll.add_child(_filter_row)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(_scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 8)
	_scroll.add_child(_content)

	_footer = HBoxContainer.new()
	_footer.visible = false
	_footer.custom_minimum_size = Vector2(0, 62)
	_footer.add_theme_constant_override("separation", 10)
	root.add_child(_footer)


func _load_data() -> void:
	_buildings.clear()
	_recipes_by_building.clear()
	for recipe in Catalog.all_recipes():
		var recipe_req := str(recipe.get("required_research", ""))
		if recipe_req != "" and not MatchState.is_unlocked(recipe_req):
			continue
		var building_id := str(recipe.get("building_id", ""))
		if building_id == "":
			continue
		if not _recipes_by_building.has(building_id):
			_recipes_by_building[building_id] = []
		_recipes_by_building[building_id].append(recipe)
	for building in Catalog.all_buildings():
		var building_req := str(building.get("required_research", ""))
		if building_req != "" and not MatchState.is_unlocked(building_req):
			continue
		# Keep non-producers visible as disabled cards, so the catalogue stays
		# complete without allowing a build flow that has no recipe to select.
		_buildings.append(building)
	_buildings.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("display_name", "")).naturalnocasecmp_to(str(b.get("display_name", ""))) < 0)


func _render() -> void:
	for child in _content.get_children():
		child.queue_free()
	for child in _footer.get_children():
		child.queue_free()
	_footer.visible = false
	if _view == View.CONFIRM:
		_render_confirm()
	else:
		_render_browse()


func _render_browse() -> void:
	_header_title.text = "CONSTRUCT"
	_header_subtitle.text = "Choose a building, then a recipe"
	_search_input.visible = true
	_filter_scroll.visible = true
	_rebuild_filters()

	var shown := _filtered_buildings()
	if shown.is_empty():
		var empty := Label.new()
		empty.text = "No buildings match your search."
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_color_override("font_color", MUTED)
		empty.add_theme_font_size_override("font_size", 13)
		empty.custom_minimum_size = Vector2(0, 120)
		_content.add_child(empty)
		return

	for building in shown:
		_content.add_child(_make_building_card(building))


func _rebuild_filters() -> void:
	for child in _filter_row.get_children():
		child.queue_free()
	var categories: Array = ["all"]
	for recipes in _recipes_by_building.values():
		for recipe in recipes:
			var category := _recipe_category(recipe)
			if category != "" and not categories.has(category):
				categories.append(category)
	for category in categories:
		var button := Button.new()
		button.text = "All" if category == "all" else category
		button.custom_minimum_size = Vector2(0, 30)
		button.add_theme_font_size_override("font_size", 11)
		var selected: bool = category == _active_category
		_style_button(button, GOLD if selected else NAVY_FIELD, GOLD_DARK if selected else NAVY_LINE,
			NAVY if selected else MUTED)
		button.pressed.connect(_on_category_pressed.bind(category))
		_filter_row.add_child(button)


func _filtered_buildings() -> Array:
	var result: Array = []
	var q := _search_query.strip_edges().to_lower()
	for building in _buildings:
		var building_id := str(building.get("id", ""))
		var recipes: Array = _recipes_by_building.get(building_id, [])
		if _active_category != "all" and not _has_recipe_category(recipes, _active_category):
			continue
		if _output_good_filter != "":
			var produces := false
			for recipe in recipes:
				if Catalog.recipe_produces(recipe, _output_good_filter):
					produces = true
					break
			if not produces:
				continue
		if q != "" and not _building_matches(building, recipes, q):
			continue
		result.append(building)
	return result


func _recipe_category(recipe: Dictionary) -> String:
	return str(recipe.get("recipe_type", "")).strip_edges()


func _has_recipe_category(recipes: Array, category: String) -> bool:
	for recipe in recipes:
		if _recipe_category(recipe) == category:
			return true
	return false


func _building_matches(building: Dictionary, recipes: Array, query: String) -> bool:
	if str(building.get("display_name", "")).to_lower().contains(query):
		return true
	for recipe in recipes:
		if str(recipe.get("display_name", "")).to_lower().contains(query):
			return true
		var output_id := str(recipe.get("output_good_id", ""))
		if output_id != "" and Catalog.get_display_name(output_id).to_lower().contains(query):
			return true
	return false


func _make_building_card(building: Dictionary) -> Control:
	var building_id := str(building.get("id", ""))
	var recipe_count: Array = _recipes_by_building.get(building_id, [])
	var disabled := recipe_count.is_empty()
	var expanded := building_id == _expanded_building_id
	var card := PanelContainer.new()
	var card_bg := Color("#111924") if disabled else (NAVY_RAISED if expanded else NAVY_FIELD)
	var card_border := Color("#3a4653") if disabled else (Color("#3c5c7e") if expanded else NAVY_LINE)
	card.add_theme_stylebox_override("panel", _panel_style(card_bg, card_border, 1, 11, 0))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	card.add_child(box)

	var header := Button.new()
	header.flat = true
	header.custom_minimum_size = Vector2(0, 70)
	header.disabled = disabled
	header.tooltip_text = "No unlocked recipes are available" if disabled else "Show recipes"
	if not disabled:
		header.pressed.connect(_on_building_pressed.bind(building_id))
	box.add_child(header)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	header.add_child(row)
	row.add_child(_building_icon(building, 42))
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.mouse_filter = Control.MOUSE_FILTER_IGNORE
	details.add_theme_constant_override("separation", 3)
	row.add_child(details)
	var name_row := HBoxContainer.new()
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	details.add_child(name_row)
	var building_name := Label.new()
	building_name.text = str(building.get("display_name", ""))
	building_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	building_name.add_theme_font_size_override("font_size", 15)
	building_name.add_theme_color_override("font_color", Color("#748190") if disabled else TEXT)
	building_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_row.add_child(building_name)
	var category := Label.new()
	category.text = "NO RECIPES" if disabled else str(recipe_count.size()) + (" RECIPE" if recipe_count.size() == 1 else " RECIPES")
	category.add_theme_font_size_override("font_size", 9)
	category.add_theme_color_override("font_color", Color("#697583") if disabled else MUTED)
	category.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_row.add_child(category)
	var value := Label.new()
	value.text = "CONSTRUCTION COST  %s" % _money(Construction.market_value(building_id))
	value.add_theme_font_size_override("font_size", 11)
	value.add_theme_color_override("font_color", Color("#78818a") if disabled else GOLD)
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	details.add_child(value)
	var chevron := Label.new()
	chevron.text = "—" if disabled else ("⌄" if expanded else "›")
	chevron.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chevron.add_theme_font_size_override("font_size", 20)
	chevron.add_theme_color_override("font_color", MUTED)
	chevron.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(chevron)

	if expanded and not disabled:
		var divider := HSeparator.new()
		box.add_child(divider)
		var hint := Label.new()
		hint.text = "%d recipe%s" % [recipe_count.size(), "" if recipe_count.size() == 1 else "s"]
		hint.add_theme_font_size_override("font_size", 10)
		hint.add_theme_color_override("font_color", MUTED)
		hint.add_theme_constant_override("outline_size", 0)
		box.add_child(hint)
		for recipe in recipe_count:
			box.add_child(_make_recipe_button(building_id, recipe))
	return card


func _make_recipe_button(building_id: String, recipe: Dictionary) -> Button:
	var button := MetalRecipeRow.new()
	button.custom_minimum_size = Vector2(0, RECIPE_ROW_HEIGHT)
	button.tooltip_text = "Choose this recipe"
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_hover_color", TEXT)
	button.add_theme_color_override("font_pressed_color", TEXT)
	var clear := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, clear)
	button.pressed.connect(_on_recipe_pressed.bind(building_id, str(recipe.get("recipe_id", ""))))
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 14)
	button.add_child(row)
	var output_id := str(recipe.get("output_good_id", ""))
	row.add_child(_good_icon(output_id, 64))
	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_box.add_theme_constant_override("separation", 6)
	row.add_child(text_box)
	var recipe_name := Label.new()
	recipe_name.text = str(recipe.get("display_name", ""))
	recipe_name.add_theme_font_size_override("font_size", 16)
	recipe_name.add_theme_color_override("font_color", TEXT)
	recipe_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_box.add_child(recipe_name)
	var detail := Label.new()
	detail.text = _recipe_summary(recipe)
	detail.add_theme_font_size_override("font_size", 12)
	detail.add_theme_color_override("font_color", MUTED)
	detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_box.add_child(detail)
	var arrow := Label.new()
	arrow.text = "›"
	arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	arrow.add_theme_font_size_override("font_size", 26)
	arrow.add_theme_color_override("font_color", METAL_LIGHT)
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(arrow)
	return button


func _render_confirm() -> void:
	_search_input.visible = false
	_filter_scroll.visible = false
	var building_name := str(_selected_building.get("display_name", ""))
	var recipe_name := str(_selected_recipe.get("display_name", ""))
	_header_title.text = "CONFIRM CONSTRUCTION"
	_header_subtitle.text = "%s · %s" % [building_name, recipe_name if recipe_name != "" else "infrastructure"]

	var back := Button.new()
	back.text = "‹  Back to recipes"
	back.custom_minimum_size = Vector2(0, 34)
	_style_button(back, NAVY_RAISED, NAVY_LINE, MUTED)
	back.pressed.connect(_on_back_to_browse)
	_content.add_child(back)

	var hero := PanelContainer.new()
	hero.add_theme_stylebox_override("panel", _panel_style(NAVY_RAISED, Color("#3c5c7e"), 1, 11, 12))
	_content.add_child(hero)
	var hero_row := HBoxContainer.new()
	hero_row.add_theme_constant_override("separation", 11)
	hero.add_child(hero_row)
	hero_row.add_child(_building_icon(_selected_building, 48))
	var hero_text := VBoxContainer.new()
	hero_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hero_row.add_child(hero_text)
	var title := Label.new()
	title.text = recipe_name if recipe_name != "" else building_name
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", TEXT)
	hero_text.add_child(title)
	var sub := Label.new()
	sub.text = building_name if recipe_name != "" else "Infrastructure"
	sub.add_theme_font_size_override("font_size", 11)
	sub.add_theme_color_override("font_color", MUTED)
	hero_text.add_child(sub)

	if not _selected_recipe.is_empty():
		_content.add_child(_section_label("RECIPE"))
		var flow := Label.new()
		flow.text = _recipe_flow(_selected_recipe)
		flow.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		flow.add_theme_font_size_override("font_size", 13)
		flow.add_theme_color_override("font_color", TEXT)
		flow.add_theme_stylebox_override("normal", _panel_style(NAVY_FIELD, NAVY_LINE, 1, 9, 11))
		_content.add_child(flow)

	_content.add_child(_section_label("CONSTRUCTION MATERIALS"))
	var material_note := Label.new()
	material_note.text = "These resources are required at the tile you select next."
	material_note.add_theme_font_size_override("font_size", 11)
	material_note.add_theme_color_override("font_color", MUTED)
	_content.add_child(material_note)
	_content.add_child(_materials_grid(_selected_building))

	var value_card := PanelContainer.new()
	value_card.add_theme_stylebox_override("panel", _panel_style(NAVY_FIELD, GOLD_DARK, 1, 9, 10))
	_content.add_child(value_card)
	var value_row := HBoxContainer.new()
	value_card.add_child(value_row)
	var value_label := Label.new()
	value_label.text = "Construction cost this turn"
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_label.add_theme_font_size_override("font_size", 12)
	value_label.add_theme_color_override("font_color", MUTED)
	value_row.add_child(value_label)
	var value := Label.new()
	value.text = _money(Construction.market_value(str(_selected_building.get("id", ""))))
	value.add_theme_font_size_override("font_size", 16)
	value.add_theme_color_override("font_color", GOLD)
	value_row.add_child(value)

	var placement_note := Label.new()
	placement_note.text = "Confirming does not place the building. You will choose a tile on the map next."
	placement_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	placement_note.add_theme_font_size_override("font_size", 11)
	placement_note.add_theme_color_override("font_color", GREEN)
	_content.add_child(placement_note)

	_footer.visible = true
	var total := Label.new()
	total.text = _money(Construction.market_value(str(_selected_building.get("id", ""))))
	total.custom_minimum_size = Vector2(90, 0)
	total.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	total.add_theme_font_size_override("font_size", 16)
	total.add_theme_color_override("font_color", GOLD)
	_footer.add_child(total)
	var confirm := Button.new()
	confirm.text = "Confirm · select tile"
	confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm.add_theme_font_size_override("font_size", 14)
	_style_button(confirm, GOLD, GOLD_DARK, NAVY)
	confirm.pressed.connect(_on_confirm_pressed)
	_footer.add_child(confirm)


func _materials_grid(building: Dictionary) -> Control:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", _panel_style(NAVY_FIELD, NAVY_LINE, 1, 9, 10))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)
	for material in building.get("materials", []):
		var internal := str(material.get("name", ""))
		var good := Catalog.get_good_by_internal_name(internal)
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 6)
		grid.add_child(item)
		item.add_child(_good_icon(str(good.get("id", "")), 28))
		var description := Label.new()
		description.text = "%s ×%d" % [Catalog.get_display_name(str(good.get("id", ""))), int(material.get("qty", 0))]
		description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		description.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		description.add_theme_font_size_override("font_size", 11)
		description.add_theme_color_override("font_color", TEXT)
		item.add_child(description)
	if grid.get_child_count() == 0:
		var none := Label.new()
		none.text = "No material kit required"
		none.add_theme_color_override("font_color", MUTED)
		grid.add_child(none)
	return box


func _section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", MUTED)
	return label


func _building_icon(building: Dictionary, icon_size: int) -> TextureRect:
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(icon_size, icon_size)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var building_id := str(building.get("id", ""))
	var internal := str(building.get("internal_name", ""))
	# BuildingIcon removes the navy PNG backdrop, trims the surviving off-white
	# glyph and centres it in a square — the same treatment used by the ledger.
	icon.texture = BuildingIcon.clean_texture(building_id, internal)
	return icon


func _good_icon(good_id: String, icon_size: int) -> Control:
	# Cream, rounded-square pedestal. The art deliberately overhangs the plate by
	# 5%, making the good feel inset into the metal recipe row rather than trapped
	# inside a flat UI tile.
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(icon_size, icon_size)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var plate := PanelContainer.new()
	plate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var plate_style := StyleBoxFlat.new()
	plate_style.bg_color = CREAM
	plate_style.border_color = CREAM_SHADOW
	plate_style.set_border_width_all(2)
	plate_style.set_corner_radius_all(maxi(7, int(round(float(icon_size) * 0.16))))
	plate.add_theme_stylebox_override("panel", plate_style)
	holder.add_child(plate)
	var art := TextureRect.new()
	art.texture = GoodIcons.texture_for(good_id, Catalog.get_internal_name(good_id), true)
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var spill := maxf(1.0, float(icon_size) * 0.05)
	art.offset_left = -spill
	art.offset_top = -spill
	art.offset_right = spill
	art.offset_bottom = spill
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(art)
	return holder


func _recipe_summary(recipe: Dictionary) -> String:
	var output_name := Catalog.get_display_name(str(recipe.get("output_good_id", "")))
	return "%s ×%d  ·  %d power" % [output_name, int(recipe.get("output_qty", 0)), int(recipe.get("energy_req", 0))]


func _recipe_flow(recipe: Dictionary) -> String:
	var parts: Array = []
	for input in recipe.get("inputs", []):
		parts.append("%s ×%d" % [Catalog.get_display_name(str(input.get("good_id", ""))), int(input.get("qty", 0))])
	var input_text := "Raw extraction" if parts.is_empty() else " + ".join(parts)
	return "%s  →  %s ×%d" % [input_text, Catalog.get_display_name(str(recipe.get("output_good_id", ""))), int(recipe.get("output_qty", 0))]


func _on_search_changed(text: String) -> void:
	_search_query = text
	_render()


func _on_category_pressed(category: String) -> void:
	_active_category = category
	_render()


func _on_building_pressed(building_id: String) -> void:
	_expanded_building_id = "" if _expanded_building_id == building_id else building_id
	_render()


func _on_recipe_pressed(building_id: String, recipe_id: String) -> void:
	_selected_building = Catalog.get_building(building_id)
	_selected_recipe = Catalog.get_recipe(recipe_id)
	if _selected_building.is_empty() or _selected_recipe.is_empty():
		return
	_view = View.CONFIRM
	_render()


func _on_infrastructure_selected(building_id: String) -> void:
	_selected_building = Catalog.get_building(building_id)
	_selected_recipe = {}
	if _selected_building.is_empty():
		return
	_view = View.CONFIRM
	_render()


func _on_back_to_browse() -> void:
	_view = View.BROWSE
	_selected_building = {}
	_selected_recipe = {}
	_render()


func _on_confirm_pressed() -> void:
	var building_id := str(_selected_building.get("id", ""))
	if building_id == "":
		return
	if _selected_recipe.is_empty():
		BuildMode.enter_infrastructure_mode(str(_selected_building.get("internal_name", "")))
	else:
		BuildMode.enter_build_mode(building_id, str(_selected_recipe.get("recipe_id", "")))
	MatchState.request_toast("Construction confirmed — select a tile for %s." % str(_selected_building.get("display_name", "this building")), "info")
	hide()


func _money(value: float) -> String:
	return "£%s" % _format_number(value)


func _format_number(value: float) -> String:
	var rounded := roundf(value * 100.0) / 100.0
	var text := "%.2f" % rounded
	while text.ends_with("0"):
		text = text.trim_suffix("0")
	if text.ends_with("."):
		text = text.trim_suffix(".")
	return text


func _panel_style(background: Color, border: Color, border_width: int, radius: int, padding: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(padding)
	return style


func _style_button(button: Button, background: Color, border: Color, foreground: Color) -> void:
	button.add_theme_color_override("font_color", foreground)
	button.add_theme_color_override("font_hover_color", foreground)
	button.add_theme_color_override("font_pressed_color", foreground)
	button.add_theme_stylebox_override("normal", _panel_style(background, border, 1, 8, 7))
	button.add_theme_stylebox_override("hover", _panel_style(background.lightened(0.07), border.lightened(0.1), 1, 8, 7))
	button.add_theme_stylebox_override("pressed", _panel_style(background.darkened(0.08), border, 1, 8, 7))
