extends PanelContainer
## The construct panel's flow, state and settings: the base of the construction lot (construct_ds2/construct_ds2.gd),
## which builds the panel's shell and draws the catalogue and the build order.
##
## The sequence is intentionally independent of a tile:
##   browse building → choose recipe → confirm → choose tile on the map.
## The final map click still goes through BuildMode/world_map, retaining every
## existing terrain, capacity, money, material and construction-order check.

const NAVY := Color("#0b1726")
const NAVY_RAISED := Color("#10233a")
const NAVY_FIELD := Color("#0a1725")
const NAVY_LINE := Color("#22384f")
const TEXT := Color("#e6edf5")
const GOLD := Color("#e6b34a")
const GOLD_DARK := Color("#c48d35")
const BuildingNaming := preload("res://scripts/building_naming.gd")
enum View { BROWSE, CONFIRM, SETTINGS }

var _search_input: LineEdit
var _scroll: ScrollContainer
var _content: VBoxContainer
var _pinned: VBoxContainer

var _view := View.BROWSE
var _buildings: Array = []
var _recipes_by_building: Dictionary = {}
var _active_filters: Dictionary = {}  # the building_type shown (one category at a time)

# Land bought as part of THIS build, decided on the confirm screen. Zero unless the locked
# tile is short and there is land left to buy on it.
var _land_purchase_units := 0
var _land_purchase_cost := 0.0
var _buy_land_wanted := false
var _search_query := ""
var _expanded_building_id := ""
var _selected_building: Dictionary = {}
var _selected_recipe: Dictionary = {}
var _output_good_filter := ""
# When opened from a tile's "Build" button, the flow LOCKS to that tile: the list
# shows only buildings/recipes the terrain (and deposits/potential) permit, and
# Confirm builds directly there — no map pick. Empty = the tile-independent flow
# (confirm first, then choose a site on the map).
var _locked_tile_id := ""
var _locked_tile_data: Dictionary = {}

# ── The build order's state ──────────────────────────────────────────────────
# The sim projections are computed once per render and cached here so every part of
# the build order reads the same numbers.
var _v3_ledger: Dictionary = {}        # Construction.materials_ledger for this render
var _v3_forecast: Dictionary = {}      # BuildForecast.project for this render
var _v3_land: Dictionary = {}          # _v3_compute_land() facts for this render
# Whether the player has chosen on the land THIS confirm session. Once true,
# _v3_compute_land() stops defaulting _buy_land_wanted on every re-render, so a live
# money/price recompute never overrides the player's choice. Reset whenever a fresh
# confirm opens.
var _land_toggle_touched := false


func _ready() -> void:
	name = "ConstructPanelV2"
	if DS and DS.theme:
		theme = DS.theme
	visible = false
	offset_left = 16.0
	offset_top = 36.0
	offset_right = 576.0
	offset_bottom = 958.0
	custom_minimum_size = Vector2(510, 720)
	_build_shell()
	_load_data()
	if not ResearchState.unlock_granted.is_connected(_on_unlock_granted):
		ResearchState.unlock_granted.connect(_on_unlock_granted)
	if not MatchState.show_construct_for_good.is_connected(open_for_output_good):
		MatchState.show_construct_for_good.connect(open_for_output_good)
	if not MarketState.prices_updated.is_connected(_on_prices_updated):
		MarketState.prices_updated.connect(_on_prices_updated)
	if not MatchState.money_changed.is_connected(_on_money_changed):
		MatchState.money_changed.connect(_on_money_changed)
	if not MatchState.construct_settings_changed.is_connected(_on_construct_settings_changed):
		MatchState.construct_settings_changed.connect(_on_construct_settings_changed)
	if not BuildMode.mode_exited_with_selection.is_connected(_on_build_mode_exited_with_selection):
		BuildMode.mode_exited_with_selection.connect(_on_build_mode_exited_with_selection)
	visibility_changed.connect(_on_visibility_changed)


func open_for_output_good(good_id: String) -> void:
	_output_good_filter = good_id
	_reset_to_browse()
	_load_data()
	_render()
	show()


func open_browser() -> void:
	_output_good_filter = ""
	_reset_to_browse()
	_load_data()
	_render()
	show()


## Opened from the Tile View Panel "Build" button. The flow LOCKS to this tile:
## the catalogue is filtered to what the tile's terrain/deposits/potential allow,
## and Confirm builds directly here — no map pick.
func open_for_tile(tile_id: String, tile_data: Dictionary) -> void:
	_output_good_filter = ""
	_reset_to_browse()
	_locked_tile_id = tile_id
	_locked_tile_data = tile_data
	_load_data()
	_render()
	show()


## Expand a building card so its recipe rows exist (RecipeRow_<id> nodes) — used by
## the tutorial to reveal the recipe it wants to spotlight without a manual click.
func expand_building(building_id: String) -> void:
	if not visible or _view != View.BROWSE:
		return
	_expanded_building_id = building_id
	_render()
	# The recipe rows now exist; the coach overlay scrolls its spotlight target
	# (RecipeRow_<id>) into view itself, so no scrolling is needed here.


func _reset_to_browse() -> void:
	_active_filters.clear()
	_search_query = ""
	_expanded_building_id = ""
	_selected_building = {}
	_selected_recipe = {}
	_locked_tile_id = ""
	_locked_tile_data = {}
	_view = View.BROWSE
	_land_toggle_touched = false
	if _search_input != null:
		_search_input.text = ""


func _on_visibility_changed() -> void:
	if not visible:
		PanelStack.remove(self)
		return
	# push() pairs with the remove() above so world_map's Esc handler
	# (PanelStack.close_top()) finds this panel registered.
	PanelStack.push(self)
	_load_data()
	_render()


func _on_unlock_granted(_title: String, _description: String, _via_condition: bool) -> void:
	_load_data()
	if visible:
		_render()


func _on_prices_updated() -> void:
	if visible and (_view == View.BROWSE or _v3_confirm_live()):
		_render()


func _on_money_changed(_new_amount: float) -> void:
	# Rebuild the browse cards while visible so a loan, sale, or other cash
	# change immediately updates which buildings can be selected. The build order
	# recomputes live too: its verdict, refusal and totals follow the bank balance
	# while the player is deciding.
	if visible and (_view == View.BROWSE or _v3_confirm_live()):
		_render()


## True when a recipe's build order is the live view, the confirm that recomputes on money and price
## changes. Infrastructure's confirm has no ledger to recompute.
func _v3_confirm_live() -> bool:
	return _view == View.CONFIRM and not _selected_recipe.is_empty()

func _on_construct_settings_changed() -> void:
	if visible:
		_render()


func _on_build_mode_exited_with_selection(building_id: String, recipe_id: String, infra_type: String, return_to_construct_v2: bool) -> void:
	if not return_to_construct_v2:
		return
	if building_id == "":
		building_id = str(Catalog.get_building_by_internal_name(infra_type).get("id", ""))
	_selected_building = Catalog.get_building(building_id)
	_selected_recipe = Catalog.get_recipe(recipe_id) if recipe_id != "" else {}
	if _selected_building.is_empty():
		return
	_view = View.CONFIRM
	_output_good_filter = ""
	_land_toggle_touched = false
	_render()
	show()


## The panel's shell, its catalogue and its build order are the construction lot's (construct_ds2.gd), which
## builds every member above and draws each stage into them.
func _build_shell() -> void:
	pass


func _render_browse() -> void:
	pass


func _render_confirm() -> void:
	pass


func _load_data() -> void:
	_buildings.clear()
	_recipes_by_building.clear()
	for recipe in Catalog.all_recipes():
		var recipe_req := str(recipe.get("tech_unlock_req", ""))
		if recipe_req != "" and not ResearchState.is_unlocked(recipe_req):
			continue
		# Tile-locked: drop recipes the terrain/deposits/potential forbid here.
		if _locked_tile_id != "" and not _recipe_valid_for_tile(recipe, _locked_tile_data):
			continue
		var building_id := str(recipe.get("building_id", ""))
		if building_id == "":
			continue
		if not _recipes_by_building.has(building_id):
			_recipes_by_building[building_id] = []
		_recipes_by_building[building_id].append(recipe)
	for building in Catalog.all_buildings():
		if not MatchState.is_building_available(str(building.get("id", ""))):
			continue
		var building_req := str(building.get("required_research", ""))
		if building_req != "" and not ResearchState.is_unlocked(building_req):
			continue
		# Tile-locked: hide any building left with no tile-permitted recipe (this
		# also drops infrastructure, which has no recipes) so only actually-buildable
		# options show. Otherwise keep non-producers as disabled cards.
		if _locked_tile_id != "" and _recipes_by_building.get(str(building.get("id", "")), []).is_empty():
			continue
		_buildings.append(building)
	_buildings.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("display_name", "")).naturalnocasecmp_to(str(b.get("display_name", ""))) < 0)


## Tile-validity gate for the locked flow.
## Terrain rule: sea/deep_sea accept only offshore buildings and vice versa; then
## per-recipe deposit/potential requirements against this tile.
func _recipe_valid_for_tile(recipe: Dictionary, tile_data: Dictionary) -> bool:
	var tile_type := str(tile_data.get("type", ""))
	if tile_type != "" and not Catalog.is_building_allowed_on_tile_type(str(recipe.get("building_id", "")), tile_type):
		return false
	for req in recipe.get("requirements", []):
		var rtype := str(req.get("type", "")).to_lower()
		var rval := str(req.get("value", "")).strip_edges().to_lower()
		match rtype:
			"deposit":
				if not _deposit_known_or_possible(tile_data, rval):
					return false
			"potential":
				if rval == "wind" and int(tile_data.get("wind_potential", 0)) <= 0:
					return false
				if rval == "solar" and int(tile_data.get("solar_potential", 0)) <= 0:
					return false
			_:
				pass  # other requirement types don't gate tile validity here
	return true


## Deposit knowledge is survey-gated: an unsurveyed tile must NOT consult the map's
## hidden deposit list (that would let players prospect for free from the panel).
## Unknown = offered; the placement flow warns/reveals. Water is always visible.
func _deposit_known_or_possible(tile_data: Dictionary, token: String) -> bool:
	if token == "water":
		return _tile_has_deposit(tile_data, token)
	var tile_id := _locked_tile_id if _locked_tile_id != "" else str(tile_data.get("id", ""))
	if MatchState.survey_status(tile_id, str(tile_data.get("type", ""))) == "unsurveyed":
		return true
	return _tile_has_deposit(tile_data, token)


func _tile_has_deposit(tile_data: Dictionary, name: String) -> bool:
	for deposit in tile_data.get("deposits", []):
		var bare := str(deposit).split("(")[0].strip_edges().to_lower()
		if bare == name or bare.replace(" ", "_") == name or bare.replace("_", " ") == name:
			return true
	return false


func _render() -> void:
	# remove_child() BEFORE queue_free(), not queue_free() alone: _render() can and
	# does re-enter before the previous pass's deferred frees land (a signal-driven
	# rebuild landing mid-frame, same as this file's own _rebuild() comment already
	# warns about) — a still-attached-but-pending-free sibling collides on name with
	# its freshly-built replacement, and Godot resolves that collision by discarding
	# BOTH cards' readable names (e.g. "BuildingCard_b_007") for the anonymous
	# @ClassName@N form, breaking every find_child("BuildingCard_...")-style lookup
	# (tutorial spotlights, screenshot/test tooling) until the stale pass is freed.
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	for child in _pinned.get_children():
		_pinned.remove_child(child)
		child.queue_free()
	_pinned.visible = false
	if _view == View.SETTINGS:
		_render_settings()
	elif _view == View.CONFIRM:
		_render_confirm()
	else:
		_render_browse()


func _on_settings_pressed() -> void:
	_view = View.SETTINGS
	_render()


func _render_settings() -> void:
	_search_input.visible = false

	var back := Button.new()
	back.text = "‹  Back to construct"
	back.custom_minimum_size = Vector2(0, 34)
	_style_button(back, NAVY_RAISED, NAVY_LINE, DS.PALETTE.TEXT_MUTED)
	back.pressed.connect(_on_back_from_settings)
	_content.add_child(back)
	_content.add_child(_section_label("CONSTRUCTION DEFAULTS"))

	var output_card := PanelContainer.new()
	output_card.add_theme_stylebox_override("panel", _panel_style(NAVY_FIELD, NAVY_LINE, 1, 9, 11))
	_content.add_child(output_card)
	var output_box := VBoxContainer.new()
	output_box.add_theme_constant_override("separation", 8)
	output_card.add_child(output_box)
	var output_title := Label.new()
	output_title.text = "Send output by default to"
	output_title.add_theme_font_size_override("font_size", 14)
	output_title.add_theme_color_override("font_color", TEXT)
	output_box.add_child(output_title)
	var output_note := Label.new()
	output_note.text = "This applies to recipes started after changing the setting."
	output_note.add_theme_font_size_override("font_size", 11)
	output_note.add_theme_color_override("font_color", DS.PALETTE.TEXT_MUTED)
	output_box.add_child(output_note)
	var output_choices := HBoxContainer.new()
	output_choices.add_theme_constant_override("separation", 6)
	output_box.add_child(output_choices)
	var output_group := ButtonGroup.new()
	for option in [{"id": "market", "label": "Market"}, {"id": "same_tile", "label": "Same tile stockpile"}]:
		var option_id := str(option.get("id", ""))
		var choice := _settings_choice_button(str(option.get("label", "")), MatchState.construct_output_destination == option_id, output_group)
		choice.pressed.connect(_on_output_destination_selected.bind(option_id))
		output_choices.add_child(choice)

	var source_card := PanelContainer.new()
	source_card.add_theme_stylebox_override("panel", _panel_style(NAVY_FIELD, NAVY_LINE, 1, 9, 11))
	_content.add_child(source_card)
	var source_box := VBoxContainer.new()
	source_box.add_theme_constant_override("separation", 7)
	source_card.add_child(source_box)
	var source_title := Label.new()
	source_title.text = "Source of construction materials"
	source_title.add_theme_font_size_override("font_size", 14)
	source_title.add_theme_color_override("font_color", TEXT)
	source_box.add_child(source_title)
	var source_note := Label.new()
	source_note.text = "Choose what happens when the selected tile does not hold the full kit."
	source_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	source_note.add_theme_font_size_override("font_size", 11)
	source_note.add_theme_color_override("font_color", DS.PALETTE.TEXT_MUTED)
	source_box.add_child(source_note)
	var source_group := ButtonGroup.new()
	for option in [
		{"id": "middleman", "title": "Local Suppliers (default)", "detail": "Delivered to the site on the next turn"},
		{"id": "market", "title": "Market — always buy in", "detail": "Never blocks; costs money"},
		{"id": "same_tile", "title": "Same tile — always", "detail": "Uses local stockpile only"},
		{"id": "any_tile", "title": "Any tile with surplus", "detail": "Pulls spare goods network-wide"},
	]:
		var option_id := str(option.get("id", ""))
		if option_id == "middleman" and not ResearchState.logistics_progression_active():
			continue
		var selected := _effective_material_source(MatchState.construct_material_source) == option_id
		var radio_text := "●" if selected else "○"
		var choice := _settings_choice_button(
			"%s  %s\n    %s" % [radio_text, str(option.get("title", "")), str(option.get("detail", ""))],
			selected, source_group, true)
		if preload("res://scripts/middleman_service.gd").active():
			if option_id == "market" and not ResearchState.global_trade_license_available():
				choice.disabled = true
				choice.tooltip_text = "Government Import/Export License is required for direct global-market construction purchases."
			elif option_id in ["same_tile", "any_tile"] and not ResearchState.open_logistics_contracts_available():
				choice.disabled = true
				choice.tooltip_text = "Open Logistics Contracts is required to use tile stockpiles for construction."
		choice.pressed.connect(_on_material_source_selected.bind(option_id))
		source_box.add_child(choice)

	_content.add_child(_settings_toggle_card(
		"Start at half capacity",
		"New buildings use half their inputs, power and output for their first successful operating turn. Existing projects are unchanged.",
		MatchState.construct_start_half_capacity, _on_start_capacity_toggled))
	_content.add_child(_settings_toggle_card(
		"Auto-buy land when building",
		"If the chosen tile does not have enough of your land for the building, buy just enough to fit it as part of confirming. Tiles that already have room buy nothing.",
		MatchState.construct_auto_buy_land, _on_auto_buy_land_toggled))
	_content.add_child(_settings_toggle_card(
		"Expanded mode",
		"Recipe cards show the full diagram with quantities, sized to what's actually in the recipe. Off shows a compact icons-only row instead.",
		UiPrefs.construct_expanded_recipe_mode, _on_expanded_recipe_mode_toggled))


## A settings row: title + explanatory note on the left, ON/OFF toggle on the right.
## Extracted when the second such setting (auto-buy land) arrived rather than copying
## the twenty-odd lines a second time.
func _settings_toggle_card(title_text: String, note_text: String, is_on: bool, on_toggled: Callable) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _panel_style(NAVY_FIELD, NAVY_LINE, 1, 9, 11))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", 4)
	row.add_child(copy)
	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", TEXT)
	copy.add_child(title)
	var note := Label.new()
	note.text = note_text
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 11)
	note.add_theme_color_override("font_color", DS.PALETTE.TEXT_MUTED)
	copy.add_child(note)
	var toggle := Button.new()
	toggle.text = "ON" if is_on else "OFF"
	toggle.toggle_mode = true
	toggle.button_pressed = is_on
	toggle.custom_minimum_size = Vector2(58, 34)
	toggle.focus_mode = Control.FOCUS_NONE
	_style_button(toggle,
		GOLD if is_on else NAVY_RAISED,
		GOLD_DARK if is_on else NAVY_LINE,
		NAVY if is_on else TEXT)
	toggle.toggled.connect(on_toggled)
	row.add_child(toggle)
	return card


func _on_auto_buy_land_toggled(enabled: bool) -> void:
	MatchState.set_construct_auto_buy_land(enabled)
	_render()


func _on_expanded_recipe_mode_toggled(enabled: bool) -> void:
	UiPrefs.set_construct_expanded_recipe_mode(enabled)
	_render()


func _on_back_from_settings() -> void:
	_view = View.BROWSE
	_render()


func _settings_choice_button(label_text: String, selected: bool, group: ButtonGroup, multiline: bool = false) -> Button:
	var choice := Button.new()
	choice.text = label_text
	choice.toggle_mode = true
	choice.button_group = group
	choice.button_pressed = selected
	choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choice.custom_minimum_size = Vector2(0, 38 if not multiline else 60)
	choice.focus_mode = Control.FOCUS_NONE
	choice.alignment = HORIZONTAL_ALIGNMENT_LEFT
	choice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_style_button(choice,
		DS.PALETTE.ACCENT if selected else NAVY_RAISED,
		DS.PALETTE.ACCENT if selected else NAVY_LINE,
		DS.PALETTE.BG_PANEL if selected else TEXT)
	choice.add_theme_font_size_override("font_size", 13 if not multiline else 14)
	return choice


func _on_output_destination_selected(destination: String) -> void:
	MatchState.set_construct_output_destination(destination)


func _on_material_source_selected(source: String) -> void:
	MatchState.set_construct_material_source(source)


func _on_start_capacity_toggled(enabled: bool) -> void:
	MatchState.set_construct_start_half_capacity(enabled)


func _filtered_buildings() -> Array:
	var result: Array = []
	var q := _search_query.strip_edges().to_lower()
	for building in _buildings:
		if not _active_filters.is_empty() and not _building_matches_filters(building):
			continue
		var recipes := _visible_recipes_for(building, q)
		if recipes.is_empty():
			# Keep recipe-less buildings in the unfiltered catalogue as disabled
			# cards. Infrastructure is the one exception: it remains actionable.
			if _output_good_filter != "" or (q != "" and not str(building.get("display_name", "")).to_lower().contains(q)):
				continue
		result.append(building)
	return result


func _building_matches_filters(building: Dictionary) -> bool:
	for building_type in building.get("building_type", []):
		if _active_filters.has(str(building_type)):
			return true
	return false


func _visible_recipes_for(building: Dictionary, query: String = "") -> Array:
	var result: Array = []
	for recipe in _recipes_by_building.get(str(building.get("id", "")), []):
		if _output_good_filter != "" and not Catalog.recipe_produces(recipe, _output_good_filter):
			continue
		if query != "" and not _recipe_matches(recipe, query):
			continue
		result.append(recipe)
	return result


func _recipe_category(recipe: Dictionary) -> String:
	return str(recipe.get("recipe_type", "")).strip_edges()


func _recipe_matches(recipe: Dictionary, query: String) -> bool:
	if str(recipe.get("display_name", "")).to_lower().contains(query):
		return true
	if BuildingNaming.name_for_recipe(str(recipe.get("recipe_id", ""))).to_lower().contains(query):
		return true
	if _recipe_category(recipe).to_lower().contains(query):
		return true
	var output_id := str(recipe.get("output_good_id", ""))
	if output_id != "" and Catalog.get_display_name(output_id).to_lower().contains(query):
		return true
	for input in recipe.get("inputs", []):
		if Catalog.get_display_name(str(input.get("good_id", ""))).to_lower().contains(query):
			return true
	return false


## The land facts for this confirm, and the purchase folded into it when the player
## buys. `_land_purchase_units`/`_land_purchase_cost` always hold what a full purchase
## of the shortfall WOULD cost; `_buy_land_wanted`, preserved across re-renders once
## the player has chosen (_land_toggle_touched), decides whether that cost applies.
## `covered` reflects that choice, so the land requirement and the refusal agree.
func _v3_compute_land() -> Dictionary:
	var needed := int(round(maxf(0.0, float(_selected_building.get("tile_size_used", 1)))))
	var out := {"needed": needed, "free": 0, "short": 0, "units": 0, "cost": 0.0,
		"for_sale": 0, "purchasable": false, "covered": true}
	_land_purchase_units = 0
	_land_purchase_cost = 0.0
	if _locked_tile_id == "":
		_buy_land_wanted = false
		return out
	var owned := BuildingState.get_tile_land_owned(_locked_tile_id)
	var used := int(round(BuildingState.get_tile_player_space_used(_locked_tile_id)))
	var free := maxi(0, owned - used)
	out.free = free
	if free >= needed:
		_buy_land_wanted = false
		return out
	var short := needed - free
	out.short = short
	out.covered = false
	var for_sale := BuildingState.get_tile_land_patches_available(_locked_tile_id)
	out.for_sale = for_sale
	if for_sale <= 0:
		_buy_land_wanted = false
		return out
	var patches := mini(int(ceil(float(short) / float(BuildingState.LAND_PATCH_SIZE))), for_sale)
	var units := patches * BuildingState.LAND_PATCH_SIZE
	var cost := AdvisorState.purchase_cost_after_advisor(
		float(patches) * BuildingState.LAND_PATCH_COST, {"tile_id": _locked_tile_id})
	out.units = units
	out.cost = cost
	if free + units < needed:
		# Not enough for sale here to close the gap even fully bought — nothing
		# to toggle, this is a hard failure.
		_buy_land_wanted = false
		out.covered = false
		return out
	out.purchasable = true
	if not _land_toggle_touched:
		_buy_land_wanted = true   # default ON — untouched behaves like the old auto-include
	_land_purchase_units = units
	_land_purchase_cost = cost
	out.covered = _buy_land_wanted
	return out


func _current_material_source() -> String:
	var s := MatchState.pending_build_material_source if MatchState.pending_build_material_source != "" else MatchState.construct_material_source
	return _effective_material_source(s)

## Only Logistics Intermediary games have an intermediary. Elsewhere the "middleman"
## default buys from the market, exactly as the build flow resolves it.
func _effective_material_source(source: String) -> String:
	if source == "ask" or source == "":
		source = "middleman"
	if source == "middleman" and not ResearchState.logistics_progression_active():
		return "market"
	return source


## The first fact that blocks this build, in words, or "" when nothing does: the lot reads it off its quote.
func _v3_confirm_block_reason() -> String:
	return ""


## A ruled section head (DS.ruled_section_head): fine ruled lines in ledger grammar.
func _section_label(text: String) -> Control:
	return DS.ruled_section_head(text)


func _on_search_changed(text: String) -> void:
	_search_query = text
	_render()


func _on_filter_toggled(pressed: bool, category: String) -> void:
	# Single-select: the categories read as alternative views of the catalogue, not as
	# stackable predicates, so a new pick replaces the previous one and picking the
	# active one clears the filter.
	_active_filters.clear()
	if pressed:
		_active_filters[category] = true
	_render()


func _on_building_pressed(building_id: String) -> void:
	_expanded_building_id = "" if _expanded_building_id == building_id else building_id
	_render()


func _on_recipe_pressed(building_id: String, recipe_id: String) -> void:
	if not _is_building_affordable(building_id):
		_show_insufficient_funds(building_id)
		return
	_selected_building = Catalog.get_building(building_id)
	_selected_recipe = Catalog.get_recipe(recipe_id)
	if _selected_building.is_empty() or _selected_recipe.is_empty():
		return
	_view = View.CONFIRM
	_land_toggle_touched = false
	_render()


func _is_building_affordable(building_id: String) -> bool:
	var cost := _construction_display_cost(building_id)
	if _buy_land_wanted:
		cost += _land_purchase_cost
	return cost <= MatchState.money + 0.0001


func _show_insufficient_funds(building_id: String) -> void:
	var needed := _construction_display_cost(building_id) + (
		_land_purchase_cost if _buy_land_wanted else 0.0)
	MatchState.request_toast("Insufficient funds. Need %s and have %s." % [_money(needed), _money(MatchState.money)], "caution")


func _on_infrastructure_selected(building_id: String) -> void:
	_selected_building = Catalog.get_building(building_id)
	_selected_recipe = {}
	if _selected_building.is_empty():
		return
	_view = View.CONFIRM
	_render()


## The chosen building's name: by its recipe once one is chosen ("Iron Furnace"), else its type's.
func _selected_name() -> String:
	return BuildingNaming.name_for(str(_selected_building.get("id", "")), str(_selected_recipe.get("recipe_id", "")))


func _on_back_to_browse() -> void:
	_view = View.BROWSE
	_selected_building = {}
	_selected_recipe = {}
	_land_toggle_touched = false
	_render()


func _on_confirm_pressed() -> void:
	var building_id := str(_selected_building.get("id", ""))
	if building_id == "":
		return
	if _v3_confirm_live():
		# The build order already refuses with the reason on screen; this is the
		# belt-and-braces re-check against the same quote, not the retail-priced
		# estimate (which overstates a build on a stocked tile).
		if _v3_confirm_block_reason() != "":
			return
	elif not _is_building_affordable(building_id):
		_show_insufficient_funds(building_id)
		return
	if _locked_tile_id != "":
		# Tile-locked (opened from a tile's Build): build directly here, no map pick.
		# Only recipe-based buildings reach this flow — infrastructure has no recipes
		# and is filtered out of the locked list — but guard defensively anyway.
		if _selected_recipe.is_empty():
			return
		# One intent: the land shortfall is bought inside the build attempt's own space gate
		# (world_map._space_check_for_build via BuildMode.attempt_buy_land), and returned with its
		# cash if the build is refused, so a refusal leaves nothing bought. A refusal of any kind
		# reports false: the map has said why; keep the selection on screen.
		if not BuildMode.attempt_direct_build(building_id,
				str(_selected_recipe.get("recipe_id", "")), _locked_tile_id,
				_buy_land_wanted and _land_purchase_units > 0):
			return
		MatchState.request_toast("Building %s on %s." % [_selected_name(), Catalog.tile_label(_locked_tile_id)], "info")
		hide()
		return
	if _selected_recipe.is_empty():
		BuildMode.enter_infrastructure_mode(str(_selected_building.get("internal_name", "")), true)
	else:
		BuildMode.enter_build_mode(building_id, str(_selected_recipe.get("recipe_id", "")), true)
	MatchState.request_toast("Construction confirmed — select a tile for %s." % _selected_name(), "info")
	hide()


func _money(value: float) -> String:
	return "£%s" % _format_number(value)


func _construction_display_cost(building_id: String) -> float:
	# Before a tile is selected: the deterministic cash leg plus the actual buy-side
	# market price of the resolved material kit. Freight/warehousing is site-dependent
	# and left out.
	var building := Catalog.get_building(building_id)
	return maxf(0.0, float(building.get("base_price", 0.0))) + Construction.market_purchase_value(building_id)


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
