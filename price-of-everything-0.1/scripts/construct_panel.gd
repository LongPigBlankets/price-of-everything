extends PanelContainer

@onready var title_label: Label = $MarginContainer/VBoxContainer/HeaderRow/TitleLabel
@onready var close_button: Button = $MarginContainer/VBoxContainer/HeaderRow/CloseButton
@onready var content_vbox: VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/ContentVBox

const BuildingRowScene: PackedScene = preload("res://scenes/building_row.tscn")

const SECTION_ORDER: Array = ["production", "power", "infrastructure", "battery"]
const SECTION_DISPLAY_NAMES: Dictionary = {
	"production": "PRODUCTION",
	"power": "POWER",
	"infrastructure": "INFRASTRUCTURE",
	"battery": "BATTERY",
}
const HEADER_HEIGHT := 40.0
const SECTION_HEADER_COLOR := Color(0.05, 0.18, 0.32, 0.92)
const SECTION_HEADER_TEXT_COLOR := Color(0.78, 0.9, 1.0)

var buildings_by_category: Dictionary = {}  # category -> Array of building data
var recipes_by_building: Dictionary = {}    # building_id -> Array of recipe data
var take_loan_dialog: PanelContainer = null
var overlay_rows: Array = []
var _dragging := false
var _drag_offset := Vector2.ZERO
var _section_containers: Dictionary = {}
var _section_toggle_buttons: Dictionary = {}
var _section_labels: Dictionary = {}
var _section_expanded: Dictionary = {}
var _building_rows: Array = []

# --- Search / filter / sort ---
const FILTER_TYPES: Array = ["extraction", "refinery", "metallurgy", "electrochemistry",
	"farm_forests", "power", "infrastructure", "water", "manufacturing"]
@onready var search_input: LineEdit = $MarginContainer/VBoxContainer/ControlsVBox/SearchInput
@onready var filter_bar: HFlowContainer = $MarginContainer/VBoxContainer/ControlsVBox/FilterBar
@onready var sort_option: OptionButton = $MarginContainer/VBoxContainer/ControlsVBox/SortRow/SortOption
var _search_query: String = ""
var _active_filters: Dictionary = {}   # building_type -> true
@onready var controls_vbox: Control = $MarginContainer/VBoxContainer/ControlsVBox
var _output_good_filter: String = ""   # when set, show only producers of this good
var _opened_for_good := false
var _sort_mode: int = 0                # 0 name, 1 build cost, 2 materials cost
# When opened from the TVP "Build" button: restrict to buildings/recipes valid for
# this tile, and build directly there (no placement map-mode).
var _tile_filter: String = ""
var _tile_filter_data: Dictionary = {}
var _opened_for_tile := false
# The anchored "home" position; the panel always reopens here (item: don't reopen
# where it was last dragged to).
var _home_offset := Vector2.ZERO

func _ready() -> void:
	close_button.pressed.connect(hide)
	if not BuildMode.mode_entered.is_connected(_on_build_mode_entered):
		BuildMode.mode_entered.connect(_on_build_mode_entered)
	if not BuildMode.mode_exited.is_connected(_on_build_mode_exited):
		BuildMode.mode_exited.connect(_on_build_mode_exited)
	if not MatchState.money_changed.is_connected(_on_money_changed):
		MatchState.money_changed.connect(_on_money_changed)
	if not MatchState.unlock_granted.is_connected(_on_unlock_granted):
		MatchState.unlock_granted.connect(_on_unlock_granted)
	title_label.text = "Construct Building"
	if not MatchState.show_construct_for_good.is_connected(open_for_output_good):
		MatchState.show_construct_for_good.connect(open_for_output_good)
	_load_data()
	_setup_controls()
	_build_panel_content()
	_home_offset = Vector2(offset_left, offset_top)

func _reset_position() -> void:
	# Restore the anchored home position (undo any drag). Setting position keeps
	# the current size and just moves the panel back.
	position = _home_offset

## Open from the TVP "Build" button: only buildings/recipes valid for this tile,
## and selecting a recipe builds it directly on this tile.
func open_for_tile(tile_id: String, tile_data: Dictionary) -> void:
	_opened_for_tile = true
	_tile_filter = tile_id
	_tile_filter_data = tile_data
	_output_good_filter = ""
	controls_vbox.visible = false
	title_label.text = "Build on %s" % Catalog.tile_label(tile_id)
	_load_data()
	_build_panel_content()
	show()
	_opened_for_tile = false

func open_for_output_good(good_id: String) -> void:
	# Open the panel showing only buildings/recipes that produce good_id, with the
	# search/filter/sort controls hidden.
	_opened_for_good = true
	_output_good_filter = good_id
	controls_vbox.visible = false
	title_label.text = "Produces %s" % Catalog.get_display_name(good_id)
	_load_data()
	_build_panel_content()
	show()
	_opened_for_good = false

func _setup_controls() -> void:
	# Click-only focus + release focus whenever the panel opens, so the search bar
	# never auto-captures keystrokes — WASD keeps navigating the map. (The
	# X-triggered search overlay is the only field that auto-focuses.)
	search_input.focus_mode = Control.FOCUS_CLICK
	visibility_changed.connect(_on_visibility_changed)
	search_input.text_changed.connect(func(t: String) -> void:
		_search_query = t
		_build_panel_content())
	sort_option.clear()
	sort_option.add_item("Name")
	sort_option.add_item("Build cost")
	sort_option.add_item("Materials cost")
	sort_option.item_selected.connect(func(i: int) -> void:
		_sort_mode = i
		_build_panel_content())
	for t in FILTER_TYPES:
		var chip := Button.new()
		chip.toggle_mode = true
		chip.focus_mode = Control.FOCUS_NONE
		chip.text = String(t).capitalize().replace("_", " ")
		chip.add_theme_font_size_override("font_size", 13)
		chip.toggled.connect(_on_filter_toggled.bind(t))
		filter_bar.add_child(chip)

func _on_visibility_changed() -> void:
	if not visible:
		return
	search_input.release_focus()
	# Always reopen at the anchored home position (undo any prior drag).
	_reset_position.call_deferred()
	_load_data()
	var opened_special := _opened_for_good or _opened_for_tile
	if not opened_special and (_output_good_filter != "" or _tile_filter != ""):
		# Normal open after a filtered ("produces X" / tile) open: restore browser.
		_output_good_filter = ""
		_tile_filter = ""
		_tile_filter_data = {}
		controls_vbox.visible = true
		title_label.text = "Construct Building"
	_build_panel_content()

func _on_unlock_granted(_title: String, _description: String, _via_condition: bool) -> void:
	_load_data()
	if visible:
		_build_panel_content()

func _on_filter_toggled(pressed: bool, t: String) -> void:
	if pressed:
		_active_filters[t] = true
	else:
		_active_filters.erase(t)
	_build_panel_content()

func _load_data() -> void:
	# Buildings + recipes come from Catalog — single source of truth, with the
	# recipe promotion gate already applied.
	buildings_by_category.clear()
	recipes_by_building.clear()
	for building in Catalog.all_buildings():
		var bld_req: String = str(building.get("required_research", ""))
		if bld_req != "" and not MatchState.is_unlocked(bld_req):
			continue  # research/cheat-gated building (e.g. hydro via 'unlock hydro')
		var category: String = building.get("category", "production")
		if not buildings_by_category.has(category):
			buildings_by_category[category] = []
		buildings_by_category[category].append(building)
	for recipe in Catalog.all_recipes():
		var building_id: String = recipe.get("building_id", "")
		if building_id == "":
			continue
		var rec_req: String = str(recipe.get("required_research", ""))
		if rec_req != "" and not MatchState.is_unlocked(rec_req):
			continue  # research/cheat-gated recipe — hidden until its tech is unlocked
		if not recipes_by_building.has(building_id):
			recipes_by_building[building_id] = []
		recipes_by_building[building_id].append(recipe)

func _on_infrastructure_build_pressed(building_id: String) -> void:
	var building_data: Dictionary = _find_building_data(building_id)
	var infra_key: String = building_data.get("internal_name", "")
	if infra_key == "":
		push_warning("Infrastructure %s has no internal_name" % building_id)
		return
	BuildMode.enter_infrastructure_mode(infra_key)
	_refresh_build_mode_selection()

func _find_building_data(building_id: String) -> Dictionary:
	for category in buildings_by_category.keys():
		for b in buildings_by_category[category]:
			if b.id == building_id:
				return b
	return {}

func _build_panel_content() -> void:
	for child in content_vbox.get_children():
		child.queue_free()
	_section_containers.clear()
	_section_toggle_buttons.clear()
	_section_labels.clear()
	_section_expanded.clear()
	_building_rows.clear()

	if _tile_filter != "":
		# Only buildings with at least one recipe valid for this tile, showing only
		# the valid recipes.
		var any_tile := false
		for category in buildings_by_category.keys():
			for b in buildings_by_category[category]:
				var valid_recipes: Array = []
				for r in recipes_by_building.get(b.id, []):
					if _recipe_valid_for_tile(r, _tile_filter_data):
						valid_recipes.append(r)
				if not valid_recipes.is_empty():
					any_tile = true
					_add_building_row(b, content_vbox, true, valid_recipes)
		if not any_tile:
			var none := Label.new()
			none.text = "No buildings can be built on this tile."
			none.theme_type_variation = &"Caption"
			content_vbox.add_child(none)
		_refresh_build_mode_selection()
		return

	if _output_good_filter != "":
		var by_building: Dictionary = {}
		for r in Catalog.recipes_producing(_output_good_filter):
			var bid := str(r.get("building_id", ""))
			if bid == "":
				continue
			var rec_req2: String = str(r.get("required_research", ""))
			if rec_req2 != "" and not MatchState.is_unlocked(rec_req2):
				continue  # research/cheat-gated recipe
			if not by_building.has(bid):
				by_building[bid] = []
			by_building[bid].append(r)
		var any := false
		for category in buildings_by_category.keys():
			for b in buildings_by_category[category]:
				if by_building.has(b.id):
					any = true
					_add_building_row(b, content_vbox, true, by_building[b.id])
		if not any:
			var empty := Label.new()
			empty.text = "Nothing produces %s yet." % Catalog.get_display_name(_output_good_filter)
			empty.theme_type_variation = &"Caption"
			content_vbox.add_child(empty)
		_refresh_build_mode_selection()
		return

	var has_search: bool = _search_query.strip_edges() != ""
	var has_filter: bool = not _active_filters.is_empty()

	if not has_search and not has_filter:
		# Default: collapsible category sections, sorted within each.
		for category in SECTION_ORDER:
			if not buildings_by_category.has(category):
				continue
			_add_section(category)
			var section_container: VBoxContainer = _section_containers[category]
			for building_data in _sorted(buildings_by_category[category]):
				_add_building_row(building_data, section_container, false)
	else:
		# Flat filtered / searched list.
		var candidates: Array = []
		for category in buildings_by_category.keys():
			for b in buildings_by_category[category]:
				if has_filter and not _passes_filter(b):
					continue
				if has_search and not _matches_search(b):
					continue
				candidates.append(b)
		candidates = _sorted(candidates)
		if candidates.is_empty():
			var empty := Label.new()
			empty.text = "No buildings match."
			empty.theme_type_variation = &"Caption"
			content_vbox.add_child(empty)
		for building_data in candidates:
			_add_building_row(building_data, content_vbox, has_search)

	_refresh_build_mode_selection()

func _add_building_row(building_data: Dictionary, parent: Node, expand_for_search: bool, recipes_override: Array = []) -> void:
	var row := BuildingRowScene.instantiate()
	parent.add_child(row)
	var building_id: String = building_data.id
	var recipes_for_this: Array = recipes_override if not recipes_override.is_empty() else recipes_by_building.get(building_id, [])
	row.setup(building_data, recipes_for_this)
	row.set_affordable(_is_building_affordable(building_data), MatchState.money)
	row.recipe_selected.connect(_on_recipe_selected)
	row.expand_toggled.connect(_on_expand_toggled)
	row.infrastructure_build_pressed.connect(_on_infrastructure_build_pressed)
	_building_rows.append(row)
	if (expand_for_search and recipes_for_this.size() > 1) or not recipes_override.is_empty():
		row.call("_set_expanded", true)

func _passes_filter(b: Dictionary) -> bool:
	for t in b.get("building_type", []):
		if _active_filters.has(t):
			return true
	return false

func _matches_search(b: Dictionary) -> bool:
	var q: String = _search_query.strip_edges().to_lower()
	if q == "":
		return true
	if b.get("display_name", "").to_lower().contains(q):
		return true
	for recipe in recipes_by_building.get(b.get("id", ""), []):
		if recipe.get("display_name", "").to_lower().contains(q):
			return true
		var out_id: String = recipe.get("output_good_id", "")
		if out_id != "" and Catalog.get_display_name(out_id).to_lower().contains(q):
			return true
		for inp in recipe.get("inputs", []):
			var gid: String = inp.get("good_id", "")
			if gid != "" and Catalog.get_display_name(gid).to_lower().contains(q):
				return true
	return false

func _sorted(buildings: Array) -> Array:
	var arr: Array = buildings.duplicate()
	match _sort_mode:
		1:  # build cost
			arr.sort_custom(func(a, b): return float(a.get("base_price", 0)) < float(b.get("base_price", 0)))
		2:  # materials cost
			arr.sort_custom(func(a, b): return _materials_value(a) < _materials_value(b))
		_:  # name
			arr.sort_custom(func(a, b): return a.get("display_name", "").naturalnocasecmp_to(b.get("display_name", "")) < 0)
	return arr

func _materials_value(b: Dictionary) -> float:
	var total: float = 0.0
	for mat in b.get("materials", []):
		var good: Dictionary = Catalog.get_good_by_internal_name(mat.get("name", ""))
		total += float(good.get("base_price", 0.0)) * float(mat.get("qty", 0))
	return total

func _add_section(category: String) -> void:
	var header_panel := PanelContainer.new()
	header_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var header_style := StyleBoxFlat.new()
	header_style.bg_color = SECTION_HEADER_COLOR
	header_style.corner_radius_top_left = 4
	header_style.corner_radius_top_right = 4
	header_style.corner_radius_bottom_left = 4
	header_style.corner_radius_bottom_right = 4
	header_style.content_margin_left = 8
	header_style.content_margin_top = 4
	header_style.content_margin_right = 6
	header_style.content_margin_bottom = 4
	header_panel.add_theme_stylebox_override("panel", header_style)
	content_vbox.add_child(header_panel)

	var header_row := HBoxContainer.new()
	header_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_theme_constant_override("separation", 8)
	header_panel.add_child(header_row)

	var label := Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", SECTION_HEADER_TEXT_COLOR)
	header_row.add_child(label)

	var toggle_button := Button.new()
	toggle_button.custom_minimum_size = Vector2(28, 28)
	toggle_button.add_theme_font_size_override("font_size", 16)
	header_row.add_child(toggle_button)

	var section_container := VBoxContainer.new()
	content_vbox.add_child(section_container)

	_section_containers[category] = section_container
	_section_labels[category] = label
	_section_toggle_buttons[category] = toggle_button
	_section_expanded[category] = true
	_update_section_header(category)
	toggle_button.pressed.connect(_on_section_header_pressed.bind(category))

func _on_section_header_pressed(category: String) -> void:
	var expanded: bool = _section_expanded.get(category, true)
	_section_expanded[category] = not expanded
	_section_containers[category].visible = not expanded
	_update_section_header(category)

func _update_section_header(category: String) -> void:
	var expanded: bool = _section_expanded.get(category, true)
	var marker := "v" if expanded else ">"
	var label: String = SECTION_DISPLAY_NAMES.get(category, category.to_upper())
	_section_labels[category].text = label
	_section_toggle_buttons[category].text = marker

func _on_recipe_selected(building_id: String, recipe_id: String) -> void:
	Audio.click_primary()   # recipe row isn't a Button (gui_input) — click it explicitly
	if _tile_filter != "":
		# Opened from the TVP "Build": build directly on the known tile, no map-mode.
		BuildMode.attempt_direct_build(building_id, recipe_id, _tile_filter)
		hide()
		return
	BuildMode.enter_build_mode(building_id, recipe_id)
	_refresh_build_mode_selection()

## A recipe is valid for a tile when its deposit / potential requirements are met.
func _recipe_valid_for_tile(recipe: Dictionary, tile_data: Dictionary) -> bool:
	# Terrain rule: sea/deep_sea accept only offshore buildings; offshore buildings can't go
	# on land. (Applied only when filtering for a specific tile — empty type = no filter.)
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

## Deposit knowledge is survey-gated: on an unsurveyed tile the build menu must
## NOT consult the map's hidden deposit list — offering/hiding mining recipes by
## the true deposits would let players prospect for free from the build panel.
## Unknown = offered: the blind-build flow (world_map) warns and reveals on
## placement. Water is exempt — rivers/water are always visible on the map.
func _deposit_known_or_possible(tile_data: Dictionary, token: String) -> bool:
	if token == "water":
		return _tile_has_deposit(tile_data, token)
	var tile_id := _tile_filter if _tile_filter != "" else str(tile_data.get("id", ""))
	if MatchState.survey_status(tile_id, str(tile_data.get("type", ""))) == "unsurveyed":
		return true
	return _tile_has_deposit(tile_data, token)

func _tile_has_deposit(tile_data: Dictionary, name: String) -> bool:
	for deposit in tile_data.get("deposits", []):
		var bare := str(deposit).split("(")[0].strip_edges().to_lower()
		if bare == name or bare.replace(" ", "_") == name or bare.replace("_", " ") == name:
			return true
	return false

func _on_expand_toggled(building_id: String, is_expanded: bool) -> void:
	print("Expand toggled: ", building_id, " expanded=", is_expanded)

func _on_build_mode_entered(_building_id: String, _recipe_id: String) -> void:
	_refresh_build_mode_selection()

func _on_build_mode_exited() -> void:
	_refresh_build_mode_selection()

func _on_money_changed(_new_amount: float) -> void:
	# money_changed fires per transaction during PROCESS; the O(rows × buildings)
	# rescan only matters on screen. _on_visibility_changed fully rebuilds the
	# panel on show, so hidden panels need no catch-up flag.
	if not is_visible_in_tree():
		return
	_refresh_affordability()

func _refresh_affordability() -> void:
	for row in _building_rows:
		if row == null:
			continue
		var building_data: Dictionary = _find_building_data(row.building_id)
		row.set_affordable(_is_building_affordable(building_data), MatchState.money)

func _refresh_build_mode_selection() -> void:
	for row in _building_rows:
		if row == null:
			continue
		var active_building_id := ""
		var active_recipe_id := ""
		var active_infrastructure_key := ""
		if BuildMode.is_active and BuildMode.kind == BuildMode.Kind.BUILDING:
			active_building_id = BuildMode.current_building_id
			active_recipe_id = BuildMode.current_recipe_id
		elif BuildMode.is_active and BuildMode.kind == BuildMode.Kind.INFRASTRUCTURE:
			active_infrastructure_key = BuildMode.current_infrastructure_type
		row.set_build_mode_selection(active_building_id, active_recipe_id, active_infrastructure_key)

func _is_building_affordable(building_data: Dictionary) -> bool:
	# Catalog buildings carry "base_price" (building_row reads the same key);
	# the old "cost" key never existed, so every building read as affordable
	# and the red-flash/"Needs £X" gate was dead.
	return float(building_data.get("base_price", 0.0)) <= MatchState.money




func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# Only start drag if click is in the top strip
			if event.position.y > HEADER_HEIGHT:
				return
			_dragging = true
			_drag_offset = global_position - get_global_mouse_position()
			accept_event()
		else:
			_dragging = false
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		global_position = get_global_mouse_position() + _drag_offset
		accept_event()
