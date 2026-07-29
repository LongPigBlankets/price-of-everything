extends Control

signal recipe_build_requested(building_id: String, recipe_id: String)

const PLACEHOLDER_TEXT := "Begin typing to search for goods, recipes or buildings"
const MAX_RESULTS_PER_COLUMN := 8
const SEARCH_TOP_OFFSET := 72.0
const SEARCH_WIDTH := 1040.0
const SEARCH_HEIGHT := 660.0
const SCREEN_MARGIN := 48.0
const BAR_HEIGHT := 58.0
const RESULT_HEIGHT := 58.0
const DETAIL_IMAGE_SIZE := Vector2(216, 180)
const ACCORDION_ICON_SIZE := Vector2(80, 80)
const BUILDING_ICON_DIR := "res://assets/icons/buildings"
const HAMMER_ICON_PATH := "res://assets/icons/ui_icons/hammer_off_white.png"
const BUILD_BUTTON_SIZE := Vector2(46, 46)
const GoodIcons := preload("res://scripts/good_icons.gd")

# Palette aligned to the DS navy theme (was bespoke pure-black). Dark surfaces use
# DS navy (#040F1B) / highlight (#002E54); muted text uses DS TEXT_MUTED; the build
# button uses DS ACTION_BLUE. The cream accent already matches DS ACCENT. Kept as
# consts (DS.PALETTE is a runtime autoload, not a compile-time constant).
const OFF_WHITE := Color(0.995234, 0.930806, 0.763265, 1.0)
const DIM_BLACK := Color(0.0, 0.0, 0.0, 0.40)
const BAR_BLACK := Color(0.015686, 0.058824, 0.105882, 1.0)
const RESULT_BLACK := Color(0.015686, 0.058824, 0.105882, 0.98)
const RESULT_HOVER := Color(0.0, 0.180392, 0.329412, 0.98)
const RESULT_BORDER := Color(0.995234, 0.930806, 0.763265, 0.22)
const SUBTITLE_COLOR := Color(0.760784, 0.823529, 0.898039, 1.0)
const MUTED_PANEL := Color(0.015686, 0.058824, 0.105882, 0.96)
const BUILD_BUTTON_BLUE := Color(0.176471, 0.439216, 0.658824, 1.0)
const BUILD_BUTTON_HOVER_BLUE := Color(0.250980, 0.529412, 0.749020, 1.0)

# Encyclopedia "Game mechanics" entries (content-light for now; bodies built in _mechanic_body).
const MECHANIC_ENTRIES := [
	{"id": "market_price_mechanics", "title": "Market price mechanics"},
	{"id": "intermittency", "title": "Power intermittency"},
	{"id": "building_economics", "title": "Building Economics"},
]

var _search_stack: VBoxContainer = null
var _search_input: LineEdit = null
var _results_panel: PanelContainer = null
var _columns_row: HBoxContainer = null
# When a good's entry shows the two-column "Produced by / Used in" recipe panel,
# the overlay grows to full height minus the bottom menu.
var _recipe_view_active := false
const BOTTOM_RESERVE := 112.0   # room left for the bottom menu below the tall panel
var _empty_view := "none"
var _accordion_expanded: Dictionary = {
	"Goods": true,
	"Recipes": false,
	"Buildings": false,
	"Game mechanics": false,
}

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()
	visibility_changed.connect(_on_visibility_changed)
	hide()
	call_deferred("_layout_search_stack")

func open_search() -> void:
	show()
	PanelStack.push(self)
	move_to_front()
	_empty_view = "none"
	_search_input.text = ""
	_refresh_results("")
	call_deferred("_focus_search_input")

func open_encyclopedia() -> void:
	show()
	PanelStack.push(self)
	move_to_front()
	_empty_view = "encyclopedia"
	_search_input.text = ""
	_show_encyclopedia_landing()

## Deep-link straight to a GOOD's entry (the Produced by / Used in recipe view).
## Used by the Goods Graph's expanded-card "Encyclopedia entry" button.
func open_encyclopedia_good(good_id: String) -> void:
	var good: Dictionary = Catalog.get_good(good_id)
	if good.is_empty():
		open_encyclopedia()
		return
	show()
	PanelStack.push(self)
	move_to_front()
	_empty_view = "encyclopedia"
	_search_input.text = ""
	_show_result_detail({"type": "good", "id": good_id,
		"title": str(good.get("display_name", good_id)), "payload": good})

func open_encyclopedia_entry(entry_id: String) -> void:
	# Deep-link straight to a Mechanics entry (used by in-game "More info" links).
	show()
	PanelStack.push(self)
	move_to_front()
	_empty_view = "encyclopedia"
	_search_input.text = ""
	for entry in MECHANIC_ENTRIES:
		if str(entry.get("id", "")) == entry_id:
			_show_result_detail(_mechanic_result(entry))
			return
	_show_encyclopedia_landing()

func _mechanic_result(entry: Dictionary) -> Dictionary:
	return {
		"type": "mechanic",
		"id": str(entry.get("id", "")),
		"title": str(entry.get("title", "")),
		"subtitle": "Game mechanic",
		"payload": entry,
	}

func _mechanic_body(entry_id: String) -> String:
	if entry_id == "market_price_mechanics":
		var glut: int = EconomyConfig.GLUT_UNITS
		var maxp: int = EconomyConfig.MAX_PRICE_IMPACT_PCT
		return ("Every good has a market price that drifts over time and reacts to how much you sell.\n\n"
			+ "Selling is gentle up to a point: move up to %d units of a single good in one turn and the price barely notices. "
			+ "Push past that and you flood the market — every further %d units knocks roughly another 1%% off the price that turn, up to about %d%%. "
			+ "Dumping a large stockpile all at once can crash the price temporarily; it recovers over the following turns.\n\n"
			+ "The per-tile auto-sell control lets you cap this: pick how much price impact you'll tolerate each turn and it ships only enough to stay within that band, keeping the rest stockpiled for later.\n\n"
			+ "(Detailed numbers and worked examples will live here in a later content pass.)") % [glut, glut, maxp]
	if entry_id == "intermittency":
		var derate_pct: int = int(round(EconomyConfig.INTERMITTENCY_DERATE * 100.0))
		return ("Solar and wind power are GREEN but INTERMITTENT — the sun and wind aren't always there. "
			+ "A building relying on unfirmed intermittent power loses up to %d%% of its output that turn.\n\n"
			+ "Hydro and biomass/waste power are green but STEADY, and never take this penalty. Fossil and national-grid power are grey and steady.\n\n"
			+ "Batteries 'firm' intermittent power on a tile: up to their storage capacity, intermittent green is treated as steady and the penalty disappears. Build storage where you generate or draw intermittent green to cancel the intermittency.\n\n"
			+ "A few processes can follow a ragged supply and take no penalty at all, needing no battery to escape it — Membraneless Electrolysis is the first. Its cells have no membrane to dry out or pressure-balance, so they can ramp with the wind instead of demanding a steady load.\n\n"
			+ "(This is an early stub — worked numbers, the per-tile allocation order, and storage scaling will be detailed here in a later content pass.)") % [derate_pct]
	if entry_id == "building_economics":
		var tax_pct: int = int(round(EconomyConfig.TAX_RATE * 100.0))
		var div_pct: int = int(round(EconomyConfig.DIVIDEND_RATE * 100.0))
		return ("Open any building and its economics show a per-turn NET: the market value of everything it makes, minus what it costs to run — inputs, power, labour, maintenance and transport.\n\n"
			+ "Treat that net as a GUIDE, not cash in the bank. It values a building's whole output at the current market price whether or not you actually sell it — so a building that feeds another of yours looks like it 'earns' the market value of goods it never sells.\n\n"
			+ "IMPORTANT: you CANNOT simply add up the net value-add of your buildings. When one building hands its output to another instead of selling it, it gives up a market sale — one building is quietly subsidising the next. The producer is credited the full market price; the consumer books that same input at its cheaper cost-to-make. The only honest total of what you're really earning is the profit shown in the Turn Summary and the Money panel.\n\n"
			+ "A few things one building's net can't see, either: %d%% tax and a %d%% dividend come off your profit before it reaches your balance; selling a lot of one good in a single turn floods the market and lowers the price you actually get; and shipping goods between tiles costs freight. Chase the bottom line in the Turn Summary — not the sum of the parts.") % [tax_pct, div_pct]
	return ""

func close_search() -> void:
	if not visible:
		return
	hide()
	PanelStack.remove(self)

func _focus_search_input() -> void:
	if visible and _search_input != null:
		_search_input.grab_focus()

func _on_visibility_changed() -> void:
	if visible:
		return
	PanelStack.remove(self)
	if _search_input != null:
		_search_input.release_focus()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_search_stack()

## Esc must close in ONE press. _unhandled_input alone took two: while the search
## LineEdit holds focus, the GUI consumes the first Esc to release focus and only
## the second ever reached _unhandled_input. _input runs BEFORE the GUI, so this
## sees the first press regardless of focus.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close_search()
		get_viewport().set_input_as_handled()

func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = DIM_BLACK
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Clicking the dimmed area outside the search bar / entry panel closes the
	# overlay (owner 2026-07-19). Panels above the dim still swallow their clicks.
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			close_search())
	add_child(dim)

	_search_stack = VBoxContainer.new()
	_search_stack.name = "SearchStack"
	_search_stack.add_theme_constant_override("separation", 8)
	add_child(_search_stack)

	var bar_panel := PanelContainer.new()
	bar_panel.name = "SearchBar"
	bar_panel.custom_minimum_size = Vector2(0, BAR_HEIGHT)
	bar_panel.add_theme_stylebox_override("panel", _make_panel_style(BAR_BLACK, OFF_WHITE, 0.34, 6, 12))
	_search_stack.add_child(bar_panel)

	var bar_margin := MarginContainer.new()
	bar_margin.add_theme_constant_override("margin_left", 14)
	bar_margin.add_theme_constant_override("margin_right", 14)
	bar_margin.add_theme_constant_override("margin_top", 8)
	bar_margin.add_theme_constant_override("margin_bottom", 8)
	bar_panel.add_child(bar_margin)

	_search_input = LineEdit.new()
	_search_input.name = "SearchInput"
	_search_input.placeholder_text = PLACEHOLDER_TEXT
	_search_input.clear_button_enabled = true
	_search_input.caret_blink = true
	_search_input.add_theme_font_size_override("font_size", 20)
	_search_input.add_theme_color_override("font_color", OFF_WHITE)
	_search_input.add_theme_color_override("font_placeholder_color", OFF_WHITE)
	_search_input.add_theme_color_override("caret_color", OFF_WHITE)
	_search_input.add_theme_stylebox_override("normal", _make_line_edit_style(false))
	_search_input.add_theme_stylebox_override("focus", _make_line_edit_style(true))
	_search_input.text_changed.connect(_on_search_text_changed)
	bar_margin.add_child(_search_input)

	_results_panel = PanelContainer.new()
	_results_panel.name = "ResultsPanel"
	_results_panel.visible = false
	_results_panel.add_theme_stylebox_override("panel", _make_panel_style(BAR_BLACK, OFF_WHITE, 0.18, 6, 8))
	_search_stack.add_child(_results_panel)

	_columns_row = HBoxContainer.new()
	_columns_row.name = "ResultColumns"
	_columns_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_columns_row.add_theme_constant_override("separation", 8)
	_results_panel.add_child(_columns_row)

func _layout_search_stack() -> void:
	if _search_stack == null:
		return
	var width: float = minf(SEARCH_WIDTH, maxf(280.0, size.x - SCREEN_MARGIN))
	_search_stack.anchor_left = 0.5
	_search_stack.anchor_right = 0.5
	_search_stack.anchor_top = 0.0
	_search_stack.anchor_bottom = 0.0
	_search_stack.offset_left = -width * 0.5
	_search_stack.offset_right = width * 0.5
	_search_stack.offset_top = SEARCH_TOP_OFFSET
	# The recipe panel wants the whole height down to the bottom menu; normal search
	# keeps the compact fixed height.
	var stack_h := SEARCH_HEIGHT
	if _recipe_view_active:
		stack_h = maxf(SEARCH_HEIGHT, size.y - SEARCH_TOP_OFFSET - BOTTOM_RESERVE)
	_search_stack.offset_bottom = SEARCH_TOP_OFFSET + stack_h
	if _results_panel != null:
		_results_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL if _recipe_view_active else Control.SIZE_FILL

func _on_search_text_changed(new_text: String) -> void:
	_refresh_results(new_text)

func _refresh_results(query: String) -> void:
	_clear_results_content()

	var cleaned_query := query.strip_edges().to_lower()
	if cleaned_query == "":
		if _empty_view == "encyclopedia":
			_show_encyclopedia_landing()
		else:
			_results_panel.visible = false
		return

	var goods := _goods_results(cleaned_query)
	var recipes := _recipe_results(cleaned_query)
	var buildings := _building_results(cleaned_query)
	_results_panel.visible = true
	_columns_row.add_child(_make_result_column("Goods", goods))
	_columns_row.add_child(_make_result_column("Recipes", recipes))
	_columns_row.add_child(_make_result_column("Buildings", buildings))

func _clear_results_content() -> void:
	_recipe_view_active = false
	_layout_search_stack()  # collapse back to compact height whenever content changes
	for child in _columns_row.get_children():
		_columns_row.remove_child(child)
		child.queue_free()

func _goods_results(query: String) -> Array:
	var results: Array = []
	for good in Catalog.all_goods():
		var display_name: String = good.get("display_name", "")
		var internal_name: String = good.get("internal_name", "")
		var best_match := _best_text_match(query, [
			{"text": display_name, "reason": "Good name"},
			{"text": internal_name, "reason": "Internal good name"},
		])
		if int(best_match.score) <= 0:
			continue
		results.append({
			"type": "good",
			"id": good.get("id", ""),
			"score": best_match.score,
			"title": display_name,
			"subtitle": best_match.reason,
			"payload": good,
		})
	return _sorted_limited_results(results)

func _recipe_results(query: String) -> Array:
	var results: Array = []
	for recipe in Catalog.all_recipes():
		if not MatchState.is_building_available(str(recipe.get("building_id", ""))):
			continue
		var display_name: String = recipe.get("display_name", "")
		var building_name := Catalog.get_building_display_name(recipe.get("building_id", ""))
		var output_names := _recipe_output_names(recipe)
		var input_names := _recipe_input_names(recipe)
		var best_match := _best_text_match(query, [
			{"text": display_name, "reason": "Recipe name"},
			{"text": recipe.get("recipe_id", ""), "reason": "Recipe ID"},
			{"text": building_name, "reason": "Building needed"},
		])
		var output_match := _best_named_match(query, output_names, "Produces")
		var input_match := _best_named_match(query, input_names, "Uses")
		best_match = _better_match(best_match, output_match)
		best_match = _better_match(best_match, input_match)
		if int(best_match.score) <= 0:
			continue
		results.append({
			"type": "recipe",
			"id": recipe.get("recipe_id", ""),
			"score": best_match.score,
			"title": display_name,
			"subtitle": best_match.reason,
			"payload": recipe,
		})
	return _sorted_limited_results(results)

func _building_results(query: String) -> Array:
	var results: Array = []
	for building in Catalog.all_buildings():
		if not MatchState.is_building_available(str(building.get("id", ""))):
			continue
		var display_name: String = building.get("display_name", "")
		var internal_name: String = building.get("internal_name", "")
		var best_match := _best_text_match(query, [
			{"text": display_name, "reason": "Building name"},
			{"text": internal_name, "reason": "Internal building name"},
			{"text": building.get("category", ""), "reason": "Building category"},
		])
		if int(best_match.score) <= 0:
			continue
		results.append({
			"type": "building",
			"id": building.get("id", ""),
			"score": best_match.score,
			"title": display_name,
			"subtitle": best_match.reason,
			"payload": building,
		})
	return _sorted_limited_results(results)

func _sorted_limited_results(results: Array) -> Array:
	results.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.score) == int(b.score):
			return str(a.title) < str(b.title)
		return int(a.score) > int(b.score)
	)
	if results.size() > MAX_RESULTS_PER_COLUMN:
		return results.slice(0, MAX_RESULTS_PER_COLUMN)
	return results

func _best_text_match(query: String, candidates: Array) -> Dictionary:
	var best := {"score": 0, "reason": ""}
	for candidate in candidates:
		var candidate_text: String = str(candidate.get("text", ""))
		var score := _score_text(query, candidate_text)
		if score <= int(best.score):
			continue
		best = {
			"score": score,
			"reason": "%s: %s" % [candidate.get("reason", "Match"), _match_kind(score)],
		}
	return best

func _best_named_match(query: String, names: Array, reason_prefix: String) -> Dictionary:
	var best := {"score": 0, "reason": ""}
	for name in names:
		var display_name: String = str(name)
		var score := _score_text(query, display_name)
		if score <= int(best.score):
			continue
		best = {
			"score": max(1, score - 8),
			"reason": "%s %s" % [reason_prefix, display_name],
		}
	return best

func _better_match(a: Dictionary, b: Dictionary) -> Dictionary:
	return b if int(b.score) > int(a.score) else a

func _score_text(query: String, text: String) -> int:
	if text == "":
		return 0
	var text_lower := text.to_lower()
	if text_lower == query:
		return 100
	if text_lower.begins_with(query):
		return 80
	if text_lower.contains(query):
		return 50
	return 0

func _match_kind(score: int) -> String:
	if score >= 100:
		return "exact match"
	if score >= 80:
		return "starts with query"
	return "contains query"

func _recipe_output_names(recipe: Dictionary) -> Array:
	var names: Array = []
	for output in recipe.get("outputs", []):
		var internal_name: String = output.get("internal_name", "")
		if internal_name != "":
			names.append(_good_display_from_internal(internal_name))
	return names

func _recipe_input_names(recipe: Dictionary) -> Array:
	var names: Array = []
	for input in recipe.get("inputs", []):
		var internal_name: String = input.get("internal_name", "")
		if internal_name != "":
			names.append(_good_display_from_internal(internal_name))
	return names

func _good_display_from_internal(internal_name: String) -> String:
	var good: Dictionary = Catalog.get_good_by_internal_name(internal_name)
	return good.get("display_name", internal_name)

func _make_result_column(title: String, results: Array) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 6)

	var heading := Label.new()
	heading.text = title
	heading.add_theme_font_size_override("font_size", 13)
	heading.add_theme_color_override("font_color", OFF_WHITE)
	column.add_child(heading)

	if results.is_empty():
		var empty := Label.new()
		empty.text = "No matches"
		empty.add_theme_font_size_override("font_size", 12)
		empty.add_theme_color_override("font_color", SUBTITLE_COLOR)
		column.add_child(empty)
		return column

	for result in results:
		column.add_child(_make_result_row(result))
	return column

func _make_result_row(result: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, RESULT_HEIGHT)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_set_result_row_hover(panel, false)
	panel.mouse_entered.connect(func() -> void:
		_set_result_row_hover(panel, true)
	)
	panel.mouse_exited.connect(func() -> void:
		_set_result_row_hover(panel, false)
	)
	panel.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			call_deferred("_show_result_detail", result)
			panel.accept_event()
	)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	panel.add_child(margin)

	var content_row := HBoxContainer.new()
	content_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_row.add_theme_constant_override("separation", 8)
	margin.add_child(content_row)

	var text_stack := VBoxContainer.new()
	text_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_stack.add_theme_constant_override("separation", 2)
	content_row.add_child(text_stack)

	var title := Label.new()
	title.text = result.get("title", "")
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", OFF_WHITE)
	text_stack.add_child(title)

	var subtitle := Label.new()
	subtitle.text = result.get("subtitle", "")
	subtitle.clip_text = true
	subtitle.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	subtitle.add_theme_font_size_override("font_size", 12)
	subtitle.add_theme_color_override("font_color", SUBTITLE_COLOR)
	text_stack.add_child(subtitle)

	if _result_has_build_action(result):
		content_row.add_child(_make_build_button(result))

	return panel

func _result_has_build_action(result: Dictionary) -> bool:
	# Mirror the construct panel's research gate (construct_panel._load_data):
	# gated recipes/buildings stay searchable as encyclopedia entries, but only
	# grow a Build button once their tech is unlocked. Without this, search was
	# a research bypass — any gated recipe was buildable from turn 1.
	var result_type: String = result.get("type", "")
	if result_type == "recipe":
		return _recipe_buildable(result.get("payload", {}))
	if result_type == "building":
		var req := str((result.get("payload", {}) as Dictionary).get("required_research", ""))
		return req == "" or MatchState.is_unlocked(req)
	return false

func _recipe_buildable(recipe: Dictionary) -> bool:
	var rec_req := str(recipe.get("tech_unlock_req", ""))
	if rec_req != "" and not MatchState.is_unlocked(rec_req):
		return false
	# The recipe's building can be gated independently (e.g. hydro).
	var building: Dictionary = Catalog.get_building(str(recipe.get("building_id", "")))
	var bld_req := str(building.get("required_research", ""))
	return bld_req == "" or MatchState.is_unlocked(bld_req)

func _make_build_button(result: Dictionary) -> Button:
	var button := Button.new()
	button.custom_minimum_size = BUILD_BUTTON_SIZE
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.tooltip_text = "Build"
	button.icon = load(HAMMER_ICON_PATH) as Texture2D
	button.add_theme_stylebox_override("normal", _make_panel_style(BUILD_BUTTON_BLUE, Color.TRANSPARENT, 0.0, 4, 6))
	button.add_theme_stylebox_override("hover", _make_panel_style(BUILD_BUTTON_HOVER_BLUE, Color.TRANSPARENT, 0.0, 4, 6))
	button.add_theme_stylebox_override("pressed", _make_panel_style(BUILD_BUTTON_BLUE.darkened(0.12), Color.TRANSPARENT, 0.0, 4, 6))
	button.pressed.connect(func() -> void:
		var result_type: String = result.get("type", "")
		if result_type == "recipe":
			_start_recipe_build(result.get("payload", {}))
		elif result_type == "building":
			_show_mini_construct_panel(result.get("payload", {}))
	)
	return button

func _start_recipe_build(recipe: Dictionary) -> void:
	var building_id: String = recipe.get("building_id", "")
	var recipe_id: String = recipe.get("recipe_id", "")
	if building_id == "" or recipe_id == "":
		return
	if not _recipe_buildable(recipe):
		return  # backstop: research-gated (button shouldn't exist, but stale rows happen)
	recipe_build_requested.emit(building_id, recipe_id)
	close_search()

func _show_result_detail(result: Dictionary) -> void:
	var result_type: String = result.get("type", "")
	if result_type != "good" and result_type != "recipe" and result_type != "building" and result_type != "mechanic":
		return
	_clear_results_content()
	_results_panel.visible = true
	_recipe_view_active = result_type == "good"
	_columns_row.add_child(_make_encyclopedia_entry(result))
	_layout_search_stack()  # grow to full height if the recipe panel is showing

func _make_encyclopedia_entry(result: Dictionary) -> Control:
	# A good's entry is a full-height two-column recipe panel (Produced by / Used in).
	if result.get("type", "") == "good":
		return _make_good_recipes_entry(result)

	var entry := HBoxContainer.new()
	entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	entry.add_theme_constant_override("separation", 16)

	var main := VBoxContainer.new()
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 10)
	entry.add_child(main)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	main.add_child(header)

	var back_button := Button.new()
	back_button.custom_minimum_size = Vector2(92, 26)
	back_button.text = "RESULTS"
	back_button.flat = true
	back_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	back_button.add_theme_font_size_override("font_size", 12)
	back_button.add_theme_color_override("font_color", OFF_WHITE)
	back_button.add_theme_color_override("font_hover_color", OFF_WHITE)
	back_button.pressed.connect(func() -> void:
		_refresh_results(_search_input.text)
		_focus_search_input()
	)
	header.add_child(back_button)

	var title := Label.new()
	title.text = result.get("title", "")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", OFF_WHITE)
	header.add_child(title)

	var media_row := HBoxContainer.new()
	media_row.add_theme_constant_override("separation", 12)
	main.add_child(media_row)

	media_row.add_child(_make_entry_image(result))

	var body_stack := VBoxContainer.new()
	body_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_stack.add_theme_constant_override("separation", 8)
	media_row.add_child(body_stack)

	var type_label := Label.new()
	type_label.text = _result_type_label(result)
	type_label.add_theme_font_size_override("font_size", 12)
	type_label.add_theme_color_override("font_color", SUBTITLE_COLOR)
	body_stack.add_child(type_label)

	var body := Label.new()
	body.text = _entry_placeholder_text(result)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 15)
	body.add_theme_color_override("font_color", OFF_WHITE)
	body_stack.add_child(body)

	var note := Label.new()
	note.text = "Detailed encyclopedia copy will live here in a later content pass."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 13)
	note.add_theme_color_override("font_color", SUBTITLE_COLOR)
	main.add_child(note)

	var facts_panel := PanelContainer.new()
	facts_panel.custom_minimum_size = Vector2(300, 0)
	facts_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	facts_panel.add_theme_stylebox_override("panel", _make_panel_style(MUTED_PANEL, RESULT_BORDER, 1.0, 6, 10))
	entry.add_child(facts_panel)

	var facts_scroll := ScrollContainer.new()
	facts_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	facts_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	facts_panel.add_child(facts_scroll)

	var facts := VBoxContainer.new()
	facts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	facts.add_theme_constant_override("separation", 7)
	facts_scroll.add_child(facts)

	var facts_title := Label.new()
	facts_title.text = "Facts"
	facts_title.add_theme_font_size_override("font_size", 14)
	facts_title.add_theme_color_override("font_color", OFF_WHITE)
	facts.add_child(facts_title)

	for fact in _entry_facts(result):
		facts.add_child(_make_fact_label(fact))

	return entry

# --- Good → recipes panel -----------------------------------------------------
# A good's encyclopedia entry as two full-height scrolling columns: every recipe that
# PRODUCES this good, and every recipe that USES it — each rendered with the shared
# DS recipe-diagram builder. Recipes gated behind a hidden building are skipped, to
# match the hidden-building filtering used elsewhere in the overlay.
func _make_good_recipes_entry(result: Dictionary) -> Control:
	var good_id := str(result.get("id", (result.get("payload", {}) as Dictionary).get("id", "")))
	var produced_by: Array = []
	var used_in: Array = []
	for recipe in Catalog.all_recipes():
		if not MatchState.is_building_available(str(recipe.get("building_id", ""))):
			continue
		for o in recipe.get("outputs", []):
			if str(o.get("good_id", "")) == good_id:
				produced_by.append(recipe)
				break
		for inp in recipe.get("inputs", []):
			if str(inp.get("good_id", "")) == good_id:
				used_in.append(recipe)
				break

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 10)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	root.add_child(header)
	var back_button := Button.new()
	back_button.custom_minimum_size = Vector2(92, 26)
	back_button.text = "RESULTS"
	back_button.flat = true
	back_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	back_button.add_theme_font_size_override("font_size", 12)
	back_button.add_theme_color_override("font_color", OFF_WHITE)
	back_button.add_theme_color_override("font_hover_color", OFF_WHITE)
	back_button.pressed.connect(func() -> void:
		_refresh_results(_search_input.text)
		_focus_search_input()
	)
	header.add_child(back_button)
	var title := Label.new()
	title.text = str(result.get("title", ""))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", OFF_WHITE)
	header.add_child(title)

	# The good's authored balancing band ("Tier: Processed") — the same vocabulary
	# as the Goods Graph's band headers.
	var tier_value := str(Catalog.get_good(good_id).get("goods_graph_tier", ""))
	if tier_value != "":
		var tier_label := Label.new()
		tier_label.text = "Tier: %s" % tier_value.capitalize()
		tier_label.add_theme_font_size_override("font_size", 14)
		tier_label.add_theme_color_override("font_color", SUBTITLE_COLOR)
		header.add_child(tier_label)

	var cols := HBoxContainer.new()
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 12)
	cols.add_child(_make_recipe_column("Produced by", produced_by))
	cols.add_child(_make_recipe_column("Used in", used_in))
	root.add_child(cols)
	return root

func _make_recipe_column(heading_text: String, recipes: Array) -> Control:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)

	var heading := Label.new()
	heading.text = "%s  (%d)" % [heading_text, recipes.size()]
	heading.add_theme_font_size_override("font_size", 15)
	heading.add_theme_color_override("font_color", OFF_WHITE)
	col.add_child(heading)

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(MUTED_PANEL, RESULT_BORDER, 1.0, 6, 10))
	col.add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 14)
	scroll.add_child(list)

	if recipes.is_empty():
		var none := Label.new()
		none.text = "No recipes."
		none.add_theme_font_size_override("font_size", 13)
		none.add_theme_color_override("font_color", SUBTITLE_COLOR)
		list.add_child(none)
	else:
		for recipe in recipes:
			list.add_child(_recipe_caption(recipe))
			list.add_child(DS.recipe_diagram_for(recipe))
	return col

func _recipe_caption(recipe: Dictionary) -> Label:
	var l := Label.new()
	var rname := str(recipe.get("display_name", recipe.get("recipe_id", "")))
	var bname := Catalog.get_building_display_name(recipe.get("building_id", ""))
	l.text = ("%s  ·  %s" % [rname, bname]) if bname != "" else rname
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", SUBTITLE_COLOR)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func _make_entry_image(result: Dictionary) -> PanelContainer:
	var image_panel := PanelContainer.new()
	image_panel.custom_minimum_size = DETAIL_IMAGE_SIZE
	image_panel.add_theme_stylebox_override("panel", _make_panel_style(MUTED_PANEL, RESULT_BORDER, 1.0, 6, 8))

	var texture := _entry_texture(result)
	if texture == null:
		var empty := Label.new()
		empty.text = "No image"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty.add_theme_font_size_override("font_size", 13)
		empty.add_theme_color_override("font_color", SUBTITLE_COLOR)
		image_panel.add_child(empty)
		return image_panel

	var image := TextureRect.new()
	image.texture = texture
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.custom_minimum_size = DETAIL_IMAGE_SIZE
	image_panel.add_child(image)
	return image_panel

func _entry_texture(result: Dictionary) -> Texture2D:
	if result.get("type", "") == "good":
		return _load_good_texture(result.get("payload", {}), false)
	if result.get("type", "") == "recipe":
		var recipe: Dictionary = result.get("payload", {})
		var outputs: Array = recipe.get("outputs", [])
		if not outputs.is_empty():
			var output_good: Dictionary = _good_from_recipe_item(outputs[0])
			var output_texture: Texture2D = _load_good_texture(output_good, false)
			if output_texture != null:
				return output_texture
		return _load_building_texture(recipe.get("building_id", ""))
	if result.get("type", "") == "building":
		var building: Dictionary = result.get("payload", {})
		return _load_building_texture(building.get("id", ""))
	return null

func _load_good_texture(good: Dictionary, prefer_small := true) -> Texture2D:
	var good_id: String = good.get("id", good.get("good_id", ""))
	var internal_name: String = good.get("internal_name", "")
	if good_id == "" and internal_name != "":
		good_id = str(Catalog.get_good_by_internal_name(internal_name).get("id", ""))
	if internal_name == "" and good_id != "":
		internal_name = Catalog.get_internal_name(good_id)
	if good_id == "":
		return null
	return GoodIcons.texture_for(good_id, internal_name, prefer_small)

func _load_building_texture(building_id: String) -> Texture2D:
	var building: Dictionary = Catalog.get_building(building_id)
	var internal_name: String = building.get("internal_name", "")
	var paths: Array = []
	if building_id == "":
		return null
	if internal_name != "":
		paths.append("%s/%s_%s.png" % [BUILDING_ICON_DIR, building_id, internal_name])
		paths.append("%s/%s_%s.PNG" % [BUILDING_ICON_DIR, building_id, internal_name])
	paths.append("%s/%s.png" % [BUILDING_ICON_DIR, building_id])
	paths.append("%s/%s.PNG" % [BUILDING_ICON_DIR, building_id])
	for path in paths:
		if ResourceLoader.exists(path):
			return load(path) as Texture2D
	return null

func _entry_placeholder_text(result: Dictionary) -> String:
	var title: String = result.get("title", "")
	if result.get("type", "") == "mechanic":
		return _mechanic_body(str(result.get("id", "")))
	if result.get("type", "") == "good":
		return "%s is part of the production economy. This entry will later explain where it comes from, what it enables, and the tradeoffs around storing, selling, and routing it." % title
	if result.get("type", "") == "recipe":
		return "%s is a production recipe. This entry will later explain the industrial context, sourcing constraints, and downstream uses for its outputs." % title
	return "%s is a building. This entry will later explain its role, placement constraints, operating costs, and the recipes it can host." % title

func _entry_facts(result: Dictionary) -> Array:
	if result.get("type", "") == "good":
		return _good_facts(result.get("payload", {}))
	if result.get("type", "") == "recipe":
		return _recipe_facts(result.get("payload", {}))
	if result.get("type", "") == "building":
		return _building_facts(result.get("payload", {}))
	return []

func _good_facts(good: Dictionary) -> Array:
	var good_id: String = good.get("id", "")
	var producing := _recipes_producing_good(good_id)
	var using := _recipes_using_good(good_id)
	return [
		{"label": "Base price", "value": _decimal_text(float(good.get("base_price", 0.0)))},
		{"label": "Category", "value": _title_or_dash(good.get("category", ""))},
		{"label": "Good type", "value": _title_or_dash(good.get("good_type", ""))},
		{"label": "Transport class", "value": _title_or_dash(good.get("transport_class", ""))},
		{"label": "Buyable", "value": _yes_no(bool(good.get("is_buyable", false)))},
		{"label": "Sellable", "value": _yes_no(bool(good.get("is_sellable", false)))},
		{"label": "Decay rate", "value": _decimal_text(float(good.get("decay_rate", 0.0)))},
		{"label": "Recipes producing it", "value": _recipe_name_list(producing)},
		{"label": "Recipes using it", "value": _recipe_name_list(using)},
	]

func _recipe_facts(recipe: Dictionary) -> Array:
	return [
		{"label": "Building needed", "value": Catalog.get_building_display_name(recipe.get("building_id", ""))},
		{"label": "Energy required", "value": str(recipe.get("energy_req", 0))},
		{"label": "Inputs", "value": _recipe_items_text(recipe.get("inputs", []), "None")},
		{"label": "Outputs", "value": _recipe_items_text(recipe.get("outputs", []), "None")},
		{"label": "Requirements", "value": _requirements_text(recipe.get("requirements", []))},
	]

func _building_facts(building: Dictionary) -> Array:
	var building_id: String = building.get("id", "")
	var recipes: Array = Catalog.get_recipes_for_building(building_id)
	return [
		{"label": "Category", "value": _title_or_dash(building.get("category", ""))},
		{"label": "Build cost", "value": _decimal_text(float(building.get("base_price", 0.0)))},
		{"label": "Tile size", "value": str(building.get("tile_size_used", 1))},
		{"label": "Build duration", "value": str(building.get("build_duration", 0))},
		{"label": "Maintenance", "value": _nullable_decimal_text(building.get("maintenance_cost", null))},
		{"label": "Unskilled labour", "value": str(building.get("labour_unskilled_required", 0))},
		{"label": "Skilled labour", "value": str(building.get("labour_skilled_required", 0))},
		{"label": "Recipes", "value": _recipe_name_list(recipes)},
	]

func _result_type_label(result: Dictionary) -> String:
	var result_type: String = result.get("type", "")
	if result_type == "good":
		return "GOOD"
	if result_type == "recipe":
		return "RECIPE"
	if result_type == "building":
		return "BUILDING"
	if result_type == "mechanic":
		return "MECHANIC"
	return ""

func _make_fact_label(fact: Dictionary) -> Label:
	var label := Label.new()
	label.text = "%s: %s" % [fact.get("label", ""), fact.get("value", "-")]
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", OFF_WHITE)
	return label

func _recipes_producing_good(good_id: String) -> Array:
	var recipes: Array = []
	for recipe in Catalog.all_recipes():
		for output in recipe.get("outputs", []):
			if output.get("good_id", "") == good_id:
				recipes.append(recipe)
				break
	return recipes

func _recipes_using_good(good_id: String) -> Array:
	var recipes: Array = []
	for recipe in Catalog.all_recipes():
		for input in recipe.get("inputs", []):
			if input.get("good_id", "") == good_id:
				recipes.append(recipe)
				break
	return recipes

func _recipe_name_list(recipes: Array) -> String:
	if recipes.is_empty():
		return "None"
	var names: Array = []
	for recipe in recipes:
		names.append(recipe.get("display_name", recipe.get("recipe_id", "")))
	return ", ".join(names)

func _recipe_items_text(items: Array, empty_text: String) -> String:
	if items.is_empty():
		return empty_text
	var parts: Array = []
	for item in items:
		var good: Dictionary = _good_from_recipe_item(item)
		var qty: int = int(item.get("qty", 0))
		parts.append("%d %s" % [qty, good.get("display_name", item.get("internal_name", ""))])
	return ", ".join(parts)

func _requirements_text(requirements: Array) -> String:
	if requirements.is_empty():
		return "None"
	var parts: Array = []
	for requirement in requirements:
		var kind: String = requirement.get("type", "")
		var value: String = requirement.get("value", "")
		parts.append("%s: %s" % [_title_or_dash(kind), _good_display_from_internal(value)])
	return ", ".join(parts)

func _good_from_recipe_item(item: Dictionary) -> Dictionary:
	var good_id: String = item.get("good_id", "")
	if good_id != "":
		var by_id: Dictionary = Catalog.get_good(good_id)
		if not by_id.is_empty():
			return by_id
	var internal_name: String = item.get("internal_name", "")
	if internal_name != "":
		return Catalog.get_good_by_internal_name(internal_name)
	return {}

func _decimal_text(value: float) -> String:
	return "%.2f" % value

func _nullable_decimal_text(value: Variant) -> String:
	if value == null:
		return "-"
	return _decimal_text(float(value))

func _title_or_dash(value: String) -> String:
	if value == "":
		return "-"
	return value.replace("_", " ").capitalize()

func _yes_no(value: bool) -> String:
	return "Yes" if value else "No"

func _show_encyclopedia_landing() -> void:
	_clear_results_content()
	_results_panel.visible = true
	_columns_row.add_child(_make_encyclopedia_landing())

func _make_encyclopedia_landing() -> Control:
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 12)

	var header := Label.new()
	header.text = "Game Concepts Encyclopedia"
	header.add_theme_font_size_override("font_size", 28)
	header.add_theme_color_override("font_color", OFF_WHITE)
	root.add_child(header)

	var accordion := PanelContainer.new()
	accordion.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	accordion.add_theme_stylebox_override("panel", _make_panel_style(MUTED_PANEL, RESULT_BORDER, 1.0, 8, 10))
	root.add_child(accordion)

	var sections := VBoxContainer.new()
	sections.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sections.add_theme_constant_override("separation", 8)
	accordion.add_child(sections)

	_add_accordion_section(sections, "Goods", Catalog.all_goods(), "good")
	_add_accordion_section(sections, "Recipes", Catalog.all_recipes(), "recipe")
	_add_accordion_section(sections, "Buildings", Catalog.all_buildings(), "building")
	_add_accordion_section(sections, "Game mechanics", MECHANIC_ENTRIES, "mechanic")
	return root

func _add_accordion_section(parent: VBoxContainer, title: String, items: Array, result_type: String) -> void:
	var expanded: bool = _accordion_expanded.get(title, false)

	var header := Button.new()
	header.custom_minimum_size = Vector2(0, 34)
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	header.text = "%s  %s" % ["v" if expanded else ">", title]
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.add_theme_font_size_override("font_size", 16)
	header.add_theme_color_override("font_color", OFF_WHITE)
	header.add_theme_color_override("font_disabled_color", SUBTITLE_COLOR)
	header.add_theme_stylebox_override("normal", _make_panel_style(RESULT_BLACK, RESULT_BORDER, 1.0, 5, 8))
	header.add_theme_stylebox_override("hover", _make_panel_style(RESULT_HOVER, RESULT_BORDER, 1.0, 5, 8))
	parent.add_child(header)

	header.pressed.connect(func() -> void:
		var next_expanded := not bool(_accordion_expanded.get(title, false))
		for section_title in ["Goods", "Recipes", "Buildings", "Game mechanics"]:
			_accordion_expanded[section_title] = false
		_accordion_expanded[title] = next_expanded
		_show_encyclopedia_landing()
	)

	if not expanded:
		return

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 220)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid)

	for item in items:
		var result: Dictionary = _result_from_catalog_item(item, result_type)
		grid.add_child(_make_accordion_item(result))

func _make_accordion_item(result: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(300, 96)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	panel.add_theme_stylebox_override("panel", _make_panel_style(RESULT_BLACK, RESULT_BORDER, 1.0, 5, 8))
	panel.mouse_entered.connect(func() -> void:
		panel.add_theme_stylebox_override("panel", _make_panel_style(RESULT_HOVER, RESULT_BORDER, 1.0, 5, 8))
	)
	panel.mouse_exited.connect(func() -> void:
		panel.add_theme_stylebox_override("panel", _make_panel_style(RESULT_BLACK, RESULT_BORDER, 1.0, 5, 8))
	)
	panel.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			call_deferred("_show_result_detail", result)
			panel.accept_event()
	)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	margin.add_child(row)

	row.add_child(_make_catalog_icon(result))

	var labels := VBoxContainer.new()
	labels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	labels.add_theme_constant_override("separation", 4)
	row.add_child(labels)

	var title := Label.new()
	title.text = result.get("title", "")
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", OFF_WHITE)
	labels.add_child(title)

	var subtitle := Label.new()
	subtitle.text = _catalog_item_subtitle(result)
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_font_size_override("font_size", 12)
	subtitle.add_theme_color_override("font_color", SUBTITLE_COLOR)
	labels.add_child(subtitle)

	if _result_has_build_action(result):
		row.add_child(_make_build_button(result))

	return panel

func _make_catalog_icon(result: Dictionary) -> Control:
	if result.get("type", "") == "recipe":
		return _make_recipe_placeholder_icon()

	var texture: Texture2D = null
	if result.get("type", "") == "good":
		texture = _load_good_texture(result.get("payload", {}), true)
	elif result.get("type", "") == "building":
		var building: Dictionary = result.get("payload", {})
		texture = _load_building_texture(building.get("id", ""))
	if texture == null:
		return _make_empty_icon("No icon")
	return _make_texture_icon(texture)

func _make_texture_icon(texture: Texture2D) -> TextureRect:
	var icon := TextureRect.new()
	icon.custom_minimum_size = ACCORDION_ICON_SIZE
	icon.texture = texture
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return icon

func _make_recipe_placeholder_icon() -> Panel:
	var icon := Panel.new()
	icon.custom_minimum_size = ACCORDION_ICON_SIZE
	icon.add_theme_stylebox_override("panel", _make_panel_style(Color(1, 1, 1, 0.92), Color(1, 1, 1, 0.0), 0.0, 4, 0))
	return icon

func _make_empty_icon(text: String) -> PanelContainer:
	var icon := PanelContainer.new()
	icon.custom_minimum_size = ACCORDION_ICON_SIZE
	icon.add_theme_stylebox_override("panel", _make_panel_style(MUTED_PANEL, RESULT_BORDER, 1.0, 4, 4))
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", SUBTITLE_COLOR)
	icon.add_child(label)
	return icon

func _catalog_item_subtitle(result: Dictionary) -> String:
	var result_type: String = result.get("type", "")
	var payload: Dictionary = result.get("payload", {})
	if result_type == "good":
		return "Base price %s" % _decimal_text(float(payload.get("base_price", 0.0)))
	if result_type == "recipe":
		return "Made in %s" % Catalog.get_building_display_name(payload.get("building_id", ""))
	if result_type == "building":
		return _title_or_dash(payload.get("category", ""))
	if result_type == "mechanic":
		return "Game mechanic"
	return ""

func _result_from_catalog_item(item: Dictionary, result_type: String) -> Dictionary:
	if result_type == "mechanic":
		return _mechanic_result(item)
	if result_type == "good":
		return {
			"type": "good",
			"id": item.get("id", ""),
			"title": item.get("display_name", ""),
			"subtitle": "Good",
			"payload": item,
		}
	if result_type == "recipe":
		return {
			"type": "recipe",
			"id": item.get("recipe_id", ""),
			"title": item.get("display_name", ""),
			"subtitle": "Recipe",
			"payload": item,
		}
	return {
		"type": "building",
		"id": item.get("id", ""),
		"title": item.get("display_name", ""),
		"subtitle": "Building",
		"payload": item,
	}

func _show_mini_construct_panel(building: Dictionary) -> void:
	_clear_results_content()
	_results_panel.visible = true
	_columns_row.add_child(_make_mini_construct_panel(building))

func _make_mini_construct_panel(building: Dictionary) -> Control:
	var building_id: String = building.get("id", "")
	var recipes: Array = Catalog.get_recipes_for_building(building_id)

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 12)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	root.add_child(header)

	var back_button := Button.new()
	back_button.custom_minimum_size = Vector2(92, 26)
	back_button.text = "RESULTS"
	back_button.flat = true
	back_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	back_button.add_theme_font_size_override("font_size", 12)
	back_button.add_theme_color_override("font_color", OFF_WHITE)
	back_button.add_theme_color_override("font_hover_color", OFF_WHITE)
	back_button.pressed.connect(func() -> void:
		_refresh_results(_search_input.text)
	)
	header.add_child(back_button)

	var title := Label.new()
	title.text = "Construct: %s" % building.get("display_name", building_id)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", OFF_WHITE)
	header.add_child(title)

	var summary := HBoxContainer.new()
	summary.add_theme_constant_override("separation", 12)
	root.add_child(summary)

	var image_result: Dictionary = _result_from_catalog_item(building, "building")
	summary.add_child(_make_entry_image(image_result))

	var copy := Label.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.text = "Choose one of this building's recipes to enter build mode for that building and recipe combination."
	copy.add_theme_font_size_override("font_size", 15)
	copy.add_theme_color_override("font_color", OFF_WHITE)
	summary.add_child(copy)

	var recipes_title := Label.new()
	recipes_title.text = "Recipes"
	recipes_title.add_theme_font_size_override("font_size", 16)
	recipes_title.add_theme_color_override("font_color", OFF_WHITE)
	root.add_child(recipes_title)

	if recipes.is_empty():
		var empty := Label.new()
		empty.text = "No recipes are currently available for this building."
		empty.add_theme_font_size_override("font_size", 14)
		empty.add_theme_color_override("font_color", SUBTITLE_COLOR)
		root.add_child(empty)
		return root

	for recipe in recipes:
		root.add_child(_make_mini_recipe_row(recipe))
	return root

func _make_mini_recipe_row(recipe: Dictionary) -> PanelContainer:
	var result: Dictionary = _result_from_catalog_item(recipe, "recipe")
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 64)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	panel.add_theme_stylebox_override("panel", _make_panel_style(RESULT_BLACK, RESULT_BORDER, 1.0, 5, 8))
	panel.mouse_entered.connect(func() -> void:
		panel.add_theme_stylebox_override("panel", _make_panel_style(RESULT_HOVER, RESULT_BORDER, 1.0, 5, 8))
	)
	panel.mouse_exited.connect(func() -> void:
		panel.add_theme_stylebox_override("panel", _make_panel_style(RESULT_BLACK, RESULT_BORDER, 1.0, 5, 8))
	)
	panel.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_start_recipe_build(recipe)
			panel.accept_event()
	)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	margin.add_child(row)

	var labels := VBoxContainer.new()
	labels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	labels.add_theme_constant_override("separation", 2)
	row.add_child(labels)

	var title := Label.new()
	title.text = recipe.get("display_name", "")
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", OFF_WHITE)
	labels.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Inputs: %s  |  Outputs: %s" % [
		_recipe_items_text(recipe.get("inputs", []), "None"),
		_recipe_items_text(recipe.get("outputs", []), "None"),
	]
	subtitle.clip_text = true
	subtitle.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	subtitle.add_theme_font_size_override("font_size", 12)
	subtitle.add_theme_color_override("font_color", SUBTITLE_COLOR)
	labels.add_child(subtitle)

	if _result_has_build_action(result):
		row.add_child(_make_build_button(result))
	return panel

func _set_result_row_hover(panel: PanelContainer, hovered: bool) -> void:
	var bg := RESULT_HOVER if hovered else RESULT_BLACK
	var border_alpha := 0.62 if hovered else 1.0
	panel.add_theme_stylebox_override("panel", _make_panel_style(bg, RESULT_BORDER, border_alpha, 4, 8))

func _make_panel_style(bg: Color, border: Color, border_alpha: float, radius: int, margin: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = Color(border.r, border.g, border.b, border.a * border_alpha)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.content_margin_left = margin
	style.content_margin_top = margin
	style.content_margin_right = margin
	style.content_margin_bottom = margin
	return style

func _make_line_edit_style(focused: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = BAR_BLACK
	style.border_color = Color(OFF_WHITE.r, OFF_WHITE.g, OFF_WHITE.b, 0.42 if focused else 0.0)
	style.border_width_left = 1 if focused else 0
	style.border_width_top = 1 if focused else 0
	style.border_width_right = 1 if focused else 0
	style.border_width_bottom = 1 if focused else 0
	style.content_margin_left = 8
	style.content_margin_top = 5
	style.content_margin_right = 8
	style.content_margin_bottom = 5
	return style
