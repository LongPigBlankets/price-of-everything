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
const InfrastructureInfo := preload("res://scripts/infrastructure_info.gd")
const UIHelpers := preload("res://scripts/ui_helpers.gd")

const NAVY := Color("#0b1726")
const NAVY_RAISED := Color("#10233a")
const NAVY_FIELD := Color("#0a1725")
const NAVY_LINE := Color("#22384f")
const TEXT := Color("#e6edf5")
const MUTED := Color("#8da0b6")
const GOLD := Color("#e6b34a")
const GOLD_DARK := Color("#c48d35")
const GREEN := Color("#5fbf6b")
const RED := DS.PALETTE["DANGER"]   # shared with the forecast chart's losing segments
const BuildForecast := preload("res://scripts/build_forecast.gd")
const BuildForecastTable := preload("res://scripts/build_forecast_table.gd")
const CREAM := Color("#f4e6c0")
const CREAM_SHADOW := Color("#9f875d")
const METAL_LIGHT := Color("#c4ced8")
const DIAGRAM_PAPER := Color("#ffefc3")
const DIAGRAM_NAVY := Color("#001e3f")
const RECIPE_ARROW_PATH := "res://assets/icons/ui_icons/recipe_arrow.png"
const RECIPE_POWER_ICON_PATH := "res://assets/icons/ui_icons/recipe_power_icon.png"
const RECIPE_ROW_HEIGHT := 116
const FILTER_TYPES: Array = ["extraction", "refinery", "metallurgy", "electrochemistry",
	"farm_forests", "power", "infrastructure", "water", "manufacturing"]

# --- Site requirements (confirm screen) -------------------------------------
# Fluids and gases move ONLY by pipe and power only over cables, so a recipe that
# touches one and a tile that has no pipe/cable is a hard stall the build flow
# never mentioned. Roads and rail are deliberately absent: solids always keep the
# overland fallback (Catalog._modes_for_good hands non-fluids ROUTE_MODE_NONE), so
# their absence slows a chain rather than blocking it.
const INFRA_ROW_HEIGHT := 50
const INFRA_ROW_ICON := 40
const INFRA_ROW_ORDER: Array = ["cables", "pipes", "reinf_pipes"]
# The DS body face is IBM Plex Medium; RichTextLabel gets no theming from DS, and
# `[b]` on an unthemed RichTextLabel renders identically to the normal font. Load
# the real SemiBold cut so the bolded infrastructure name actually reads as bold.
const SEMIBOLD_FONT_PATH := "res://assets/fonts/IBMPlexSans-SemiBold.ttf"
const INFRA_FLASH_DELAY := 1.0     # seconds after the confirm screen appears
const INFRA_FLASH_UP := 0.3        # white ramps in ...
const INFRA_FLASH_DOWN := 0.7      # ... then fades out — 1.0s of flash in total
const INFRA_FLASH_PEAK := 0.45

enum View { BROWSE, CONFIRM, SETTINGS }


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


## The parent building plate deliberately shares Tile View's exact brushed-navy
## and machined-silver treatment, so choosing a recipe reads as a clear parent →
## child relationship rather than two unrelated card styles.
class TileBuildingCard extends PanelContainer:
	const NAVY_TL := Color(0.05, 0.205, 0.365)
	const NAVY_BR := Color(0.0, 0.075, 0.155)
	const SILVER_LT := Color("#b3bcc6")
	const SILVER_DK := Color("#5b636e")
	const SILVER_HOVER := Color("#dbe2ea")
	var radius := 10.0
	var hovered := false:
		set(value):
			hovered = value
			queue_redraw()
	var muted := false:
		set(value):
			muted = value
			queue_redraw()

	func _init(margin_h: int = 12, margin_v: int = 8, corner_radius: float = 10.0) -> void:
		radius = corner_radius
		var style := StyleBoxEmpty.new()
		style.content_margin_left = margin_h
		style.content_margin_right = margin_h
		style.content_margin_top = margin_v
		style.content_margin_bottom = margin_v
		add_theme_stylebox_override("panel", style)
		resized.connect(queue_redraw)

	func _rounded_points(rect: Rect2, corner: float) -> PackedVector2Array:
		var points := PackedVector2Array()
		var centres: Array[Vector2] = [
			Vector2(rect.position.x + corner, rect.position.y + corner),
			Vector2(rect.end.x - corner, rect.position.y + corner),
			Vector2(rect.end.x - corner, rect.end.y - corner),
			Vector2(rect.position.x + corner, rect.end.y - corner),
		]
		var starts: Array[float] = [PI, PI * 1.5, 0.0, PI * 0.5]
		for corner_index in 4:
			for step in 7:
				var angle: float = starts[corner_index] + (PI * 0.5) * float(step) / 6.0
				points.append(centres[corner_index] + Vector2(cos(angle), sin(angle)) * corner)
		return points

	func _draw() -> void:
		if size.x < 4.0 or size.y < 4.0:
			return
		var rect := Rect2(Vector2.ZERO, size).grow(-1.0)
		var points := _rounded_points(rect, radius)
		var diagonal := maxf(1.0, size.x + size.y)
		var mid := NAVY_TL.lerp(NAVY_BR, 0.45)
		if muted:
			mid = mid.lerp(Color("#17202b"), 0.58)
		draw_colored_polygon(points, mid.lightened(0.08) if hovered and not muted else mid)
		var quad := PackedVector2Array([
			rect.position + Vector2(1.5, 1.5), Vector2(rect.end.x - 1.5, rect.position.y + 1.5),
			rect.end - Vector2(1.5, 1.5), Vector2(rect.position.x + 1.5, rect.end.y - 1.5),
		])
		var top_left := NAVY_TL.lightened(0.16)
		draw_polygon(quad, PackedColorArray([
			Color(top_left, 0.9 if not muted else 0.25), Color(top_left, 0.15),
			Color(top_left, 0.0), Color(top_left, 0.35),
		]))
		draw_polygon(quad, PackedColorArray([
			Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.12),
			Color(0, 0, 0, 0.30), Color(0, 0, 0, 0.08),
		]))
		var brush_y := rect.position.y + 4.0
		var brush_index := 0
		while brush_y < rect.end.y - 3.0:
			var alpha := (0.022 + 0.02 * absf(sin(float(brush_index) * 12.9898))) * (0.35 if muted else 1.0)
			draw_line(Vector2(rect.position.x + 3.0, brush_y), Vector2(rect.end.x - 3.0, brush_y), Color(1, 1, 1, alpha), 1.0)
			brush_y += 3.0
			brush_index += 1
		var rim := PackedColorArray()
		for point in points:
			var gradient := clampf((point.x + point.y) / diagonal, 0.0, 1.0)
			rim.append((SILVER_HOVER if hovered and not muted else SILVER_LT).lerp(SILVER_DK, gradient))
		var closed := points.duplicate()
		closed.append(points[0])
		rim.append(rim[0])
		draw_polyline_colors(closed, rim, 1.5, true)
		draw_line(Vector2(rect.position.x + radius, rect.position.y + 2.2),
			Vector2(rect.end.x - radius, rect.position.y + 2.2), Color(1, 1, 1, 0.10 if not muted else 0.04), 1.0)


## Four-pixel gold connector used to link a parent building card to its recipe
## rows. Its first/last caps make a clean single or multi-recipe branch.
class RecipeBranchConnector extends Control:
	const ROW_HEIGHT := 116.0
	var first := false
	var last := false

	func _init(is_first: bool, is_last: bool) -> void:
		first = is_first
		last = is_last
		custom_minimum_size = Vector2(30, ROW_HEIGHT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var x := 15.0
		var centre := size.y * 0.5
		var top := 0.0
		var bottom := centre if last else size.y
		draw_line(Vector2(x, top), Vector2(x, bottom), GOLD_DARK, 4.0, true)
		draw_line(Vector2(x, centre), Vector2(size.x, centre), GOLD_DARK, 4.0, true)


class RecipeBranchLead extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(30, 19)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_line(Vector2(15, 0), Vector2(15, size.y), GOLD_DARK, 4.0, true)


## The power chip belongs in the confirm-screen recipe diagram only. Keeping it
## as a drawn pentagon makes its navy fill, cream keyline and contents scale as
## one unit instead of layering a power label on top of the generic arrow PNG.
class RecipePowerPentagon extends Control:
	const FACE := Color("#001e3f")
	const OUTLINE := Color("#ffefc3")

	func _draw() -> void:
		var point := minf(size.x * 0.30, size.y * 0.42)
		var poly := PackedVector2Array([
			Vector2(1.5, 1.5), Vector2(size.x - point, 1.5), Vector2(size.x - 1.5, size.y * 0.5),
			Vector2(size.x - point, size.y - 1.5), Vector2(1.5, size.y - 1.5),
		])
		draw_colored_polygon(poly, FACE)
		draw_polyline(PackedVector2Array([poly[0], poly[1], poly[2], poly[3], poly[4], poly[0]]), OUTLINE, 2.0, true)

var _header_title: Label
var _header_subtitle: Label
var _close_button: Button
var _settings_button: Button
var _mode_toggle: HBoxContainer
var _search_input: LineEdit
var _filter_scroll: ScrollContainer
var _filter_row: HBoxContainer
var _scroll: ScrollContainer
var _content: VBoxContainer
var _footer: HBoxContainer

var _view := View.BROWSE
var _buildings: Array = []
var _recipes_by_building: Dictionary = {}
var _active_filters: Dictionary = {}  # classic Construct building_type filters
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
# Armed when the confirm screen is ENTERED, consumed by the first _render_confirm().
# _render() also re-runs on unrelated signals (construct settings), and the flash is a
# one-shot "look here" cue — re-arming it on every rebuild would make it a strobe.
var _confirm_flash_pending := false
var _semibold_cache: Font = null
var _semibold_looked_up := false


func _ready() -> void:
	name = "ConstructPanelV2"
	if DS and DS.theme:
		theme = DS.theme
	visible = false
	offset_left = 16.0
	offset_top = 78.0
	offset_right = 576.0
	offset_bottom = 958.0
	custom_minimum_size = Vector2(510, 720)
	add_theme_stylebox_override("panel", preload("res://scripts/pipe_frame.gd").dark_brown_stylebox(8.0))
	_build_shell()
	_load_data()
	if not MatchState.unlock_granted.is_connected(_on_unlock_granted):
		MatchState.unlock_granted.connect(_on_unlock_granted)
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


## Opened from the Tile View Panel "Build" button. The flow LOCKS to this tile:
## the catalogue is filtered to what the tile's terrain/deposits/potential allow,
## and Confirm builds directly here — no map pick.
func open_for_tile(tile_id: String, tile_data: Dictionary) -> void:
	if not MatchState.use_construct_panel_v2:
		return
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


func _on_money_changed(_new_amount: float) -> void:
	# Rebuild the browse cards while visible so a loan, sale, or other cash
	# change immediately updates which buildings can be selected.
	if visible and _view == View.BROWSE:
		_render()

func _on_construct_settings_changed() -> void:
	if visible:
		_render()


func _on_build_mode_exited_with_selection(building_id: String, recipe_id: String, infra_type: String, return_to_construct_v2: bool) -> void:
	if not return_to_construct_v2 or not MatchState.use_construct_panel_v2:
		return
	if building_id == "":
		building_id = str(Catalog.get_building_by_internal_name(infra_type).get("id", ""))
	_selected_building = Catalog.get_building(building_id)
	_selected_recipe = Catalog.get_recipe(recipe_id) if recipe_id != "" else {}
	if _selected_building.is_empty():
		return
	_view = View.CONFIRM
	_confirm_flash_pending = true
	_output_good_filter = ""
	_render()
	show()


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
	_header_title.theme_type_variation = "Title"
	title_box.add_child(_header_title)
	_header_subtitle = Label.new()
	_header_subtitle.text = "Choose a building, recipe, then construction site"
	_header_subtitle.theme_type_variation = "Caption"
	title_box.add_child(_header_subtitle)

	var header_actions := VBoxContainer.new()
	header_actions.add_theme_constant_override("separation", 4)
	header.add_child(header_actions)
	_close_button = Button.new()
	_close_button.text = "×"
	_close_button.tooltip_text = "Close construct panel"
	_close_button.custom_minimum_size = Vector2(36, 36)
	_close_button.focus_mode = Control.FOCUS_NONE
	_close_button.pressed.connect(hide)
	header_actions.add_child(_close_button)
	_settings_button = Button.new()
	_settings_button.text = "⚙"
	_settings_button.tooltip_text = "Construct settings"
	_settings_button.custom_minimum_size = Vector2(36, 32)
	_settings_button.focus_mode = Control.FOCUS_NONE
	_settings_button.add_theme_font_size_override("font_size", 17)
	_settings_button.pressed.connect(_on_settings_pressed)

	var rule := HSeparator.new()
	rule.add_theme_constant_override("separation", 8)
	root.add_child(rule)

	_mode_toggle = HBoxContainer.new()
	_mode_toggle.custom_minimum_size = Vector2(0, 36)
	_mode_toggle.add_theme_constant_override("separation", 6)
	root.add_child(_mode_toggle)
	var building_mode := Button.new()
	building_mode.text = "Building"
	building_mode.toggle_mode = true
	building_mode.button_pressed = true
	building_mode.disabled = false
	building_mode.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	building_mode.focus_mode = Control.FOCUS_NONE
	# The active mode uses the same off-white plate with navy type as the
	# Tile View NPC ownership banner; this makes the selected state read as a
	# deliberate chip rather than an accent-colour button.
	_style_button(building_mode, DS.PALETTE.ACCENT, DS.PALETTE.ACCENT, DS.PALETTE.BG_PANEL)
	_mode_toggle.add_child(building_mode)
	var blueprint_mode := Button.new()
	blueprint_mode.text = "🔒  Blueprint"
	blueprint_mode.tooltip_text = "Blueprint construction is not unlocked yet"
	blueprint_mode.disabled = true
	blueprint_mode.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	blueprint_mode.focus_mode = Control.FOCUS_NONE
	blueprint_mode.add_theme_color_override("font_disabled_color", Color("#6f7d8d"))
	blueprint_mode.add_theme_stylebox_override("disabled", _panel_style(Color("#111c2a"), NAVY_LINE, 1, 8, 7))
	_mode_toggle.add_child(blueprint_mode)
	_settings_button.custom_minimum_size = Vector2(36, 36)
	_settings_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_mode_toggle.add_child(_settings_button)

	var search_margin := MarginContainer.new()
	search_margin.add_theme_constant_override("margin_top", 8)
	root.add_child(search_margin)
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
	search_margin.add_child(_search_input)

	var filter_margin := MarginContainer.new()
	filter_margin.add_theme_constant_override("margin_top", 13)
	filter_margin.add_theme_constant_override("margin_bottom", 15)
	root.add_child(filter_margin)
	_filter_scroll = ScrollContainer.new()
	_filter_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_filter_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_filter_scroll.custom_minimum_size = Vector2(0, 45)
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
		var recipe_req := str(recipe.get("tech_unlock_req", ""))
		if recipe_req != "" and not MatchState.is_unlocked(recipe_req):
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
		if building_req != "" and not MatchState.is_unlocked(building_req):
			continue
		# Tile-locked: hide any building left with no tile-permitted recipe (this
		# also drops infrastructure, which has no recipes) so only actually-buildable
		# options show. Otherwise keep non-producers as disabled cards.
		if _locked_tile_id != "" and _recipes_by_building.get(str(building.get("id", "")), []).is_empty():
			continue
		_buildings.append(building)
	_buildings.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("display_name", "")).naturalnocasecmp_to(str(b.get("display_name", ""))) < 0)


## Tile-validity gate for the locked flow (lifted from construct_panel.gd v1).
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
	for child in _content.get_children():
		child.queue_free()
	for child in _footer.get_children():
		child.queue_free()
	_footer.visible = false
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
	_filter_scroll.visible = false
	_mode_toggle.visible = false
	_settings_button.visible = false
	_header_title.text = "CONSTRUCT SETTINGS"
	_header_subtitle.text = "Defaults apply to constructions started from now on"

	var back := Button.new()
	back.text = "‹  Back to construct"
	back.custom_minimum_size = Vector2(0, 34)
	_style_button(back, NAVY_RAISED, NAVY_LINE, MUTED)
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
	output_note.add_theme_color_override("font_color", MUTED)
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
	source_note.add_theme_color_override("font_color", MUTED)
	source_box.add_child(source_note)
	var source_group := ButtonGroup.new()
	for option in [
		{"id": "ask", "title": "Ask every time", "detail": "Prompt on each delivery"},
		{"id": "market", "title": "Market — always buy in", "detail": "Never blocks; costs money"},
		{"id": "same_tile", "title": "Same tile — always", "detail": "Uses local stockpile only"},
		{"id": "any_tile", "title": "Any tile with surplus", "detail": "Pulls spare goods network-wide"},
	]:
		var option_id := str(option.get("id", ""))
		var selected := MatchState.construct_material_source == option_id
		var radio_text := "●" if selected else "○"
		var choice := _settings_choice_button(
			"%s  %s\n    %s" % [radio_text, str(option.get("title", "")), str(option.get("detail", ""))],
			selected, source_group, true)
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
	note.add_theme_color_override("font_color", MUTED)
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


func _on_back_from_settings() -> void:
	_view = View.BROWSE
	_render()


func _on_cost_display_selected(display: String) -> void:
	# Kept as a compatibility hook for older save/tests; the V2 settings no
	# longer expose the grid/compact/list presentation choice.
	MatchState.set_construct_cost_display(display)


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


func _render_browse() -> void:
	if _locked_tile_id != "":
		_header_title.text = "BUILD ON %s" % Catalog.tile_label(_locked_tile_id).to_upper()
		_header_subtitle.text = "Only what this tile allows — choose a building and recipe"
	else:
		_header_title.text = "CONSTRUCT"
		_header_subtitle.text = "Choose a building, then a recipe"
	_settings_button.visible = true
	_mode_toggle.visible = true
	_search_input.visible = true
	_filter_scroll.visible = true
	_rebuild_filters()

	var shown := _filtered_buildings()
	if shown.is_empty():
		var empty := Label.new()
		if _locked_tile_id != "" and _search_query.strip_edges() == "" and _active_filters.is_empty():
			empty.text = "Nothing can be built on this tile."
		else:
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
	for category in FILTER_TYPES:
		var button := Button.new()
		button.text = category.capitalize().replace("_", " ")
		button.toggle_mode = true
		button.button_pressed = _active_filters.has(category)
		button.custom_minimum_size = Vector2(0, 45)
		button.add_theme_font_size_override("font_size", 14)
		var selected: bool = _active_filters.has(category)
		_style_button(button, GOLD if selected else NAVY_FIELD, GOLD_DARK if selected else NAVY_LINE,
			NAVY if selected else MUTED)
		button.toggled.connect(_on_filter_toggled.bind(category))
		_filter_row.add_child(button)


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
	if _recipe_category(recipe).to_lower().contains(query):
		return true
	var output_id := str(recipe.get("output_good_id", ""))
	if output_id != "" and Catalog.get_display_name(output_id).to_lower().contains(query):
		return true
	for input in recipe.get("inputs", []):
		if Catalog.get_display_name(str(input.get("good_id", ""))).to_lower().contains(query):
			return true
	return false


func _make_building_card(building: Dictionary) -> Control:
	var building_id := str(building.get("id", ""))
	var recipe_count := _visible_recipes_for(building, _search_query.strip_edges().to_lower())
	var is_infra := str(building.get("category", "")).to_lower() == "infrastructure"
	var no_recipe_disabled := recipe_count.is_empty() and not is_infra
	var affordable := _is_building_affordable(building_id)
	var disabled := no_recipe_disabled
	var expanded := building_id == _expanded_building_id
	# Tile View building cards are 100px tall (90px content + 5px metal inset).
	# Keep the construct parent card on that same rhythm.
	var card := TileBuildingCard.new(12, 5, 10)
	card.name = "BuildingCard_%s" % building_id   # tutorial spotlight / scroll target
	card.muted = disabled or not affordable
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	card.add_child(box)

	var header := Button.new()
	header.flat = true
	header.custom_minimum_size = Vector2(0, 90)
	header.disabled = disabled
	header.tooltip_text = "No unlocked recipes are available" if disabled else ("Choose infrastructure" if is_infra else "Show recipes")
	header.mouse_entered.connect(func(): card.hovered = true)
	header.mouse_exited.connect(func(): card.hovered = false)
	if is_infra:
		header.pressed.connect(_on_infrastructure_selected.bind(building_id))
	elif not disabled:
		header.pressed.connect(_on_building_pressed.bind(building_id))
	box.add_child(header)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not affordable:
		row.modulate = Color(0.68, 0.72, 0.77, 1.0)
	row.add_theme_constant_override("separation", 10)
	header.add_child(row)
	row.add_child(_building_icon(building, 90))
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
	building_name.add_theme_color_override("font_color", Color("#748190") if disabled or not affordable else TEXT)
	building_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_row.add_child(building_name)
	var category := Label.new()
	category.text = "INSUFFICIENT FUNDS" if not affordable and not disabled else ("INFRASTRUCTURE" if is_infra else ("NO RECIPES" if disabled else str(recipe_count.size()) + (" RECIPE" if recipe_count.size() == 1 else " RECIPES")))
	category.add_theme_font_size_override("font_size", 9)
	category.add_theme_color_override("font_color", Color("#697583") if disabled or not affordable else MUTED)
	category.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_row.add_child(category)
	var value := Label.new()
	value.text = "CONSTRUCTION COST  %s" % _money(_construction_display_cost(building_id))
	value.add_theme_font_size_override("font_size", 11)
	value.add_theme_color_override("font_color", Color("#78818a") if disabled or not affordable else GOLD)
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	details.add_child(value)
	var chevron := Label.new()
	chevron.text = "—" if disabled else ("›" if is_infra else ("⌄" if expanded else "›"))
	chevron.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chevron.add_theme_font_size_override("font_size", 20)
	chevron.add_theme_color_override("font_color", MUTED)
	chevron.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(chevron)

	if expanded and not disabled and not is_infra:
		var divider := HSeparator.new()
		box.add_child(divider)
		var recipe_branch := VBoxContainer.new()
		recipe_branch.add_theme_constant_override("separation", 0)
		box.add_child(recipe_branch)
		var branch_heading := HBoxContainer.new()
		branch_heading.add_theme_constant_override("separation", 0)
		recipe_branch.add_child(branch_heading)
		branch_heading.add_child(RecipeBranchLead.new())
		var hint := Label.new()
		hint.text = "%d recipe%s" % [recipe_count.size(), "" if recipe_count.size() == 1 else "s"]
		hint.add_theme_font_size_override("font_size", 10)
		hint.add_theme_color_override("font_color", MUTED)
		hint.add_theme_constant_override("outline_size", 0)
		hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		branch_heading.add_child(hint)
		for recipe_index in range(recipe_count.size()):
			var recipe_row := HBoxContainer.new()
			recipe_row.add_theme_constant_override("separation", 0)
			recipe_branch.add_child(recipe_row)
			recipe_row.add_child(RecipeBranchConnector.new(recipe_index == 0, recipe_index == recipe_count.size() - 1))
			var recipe_button := _make_recipe_button(building_id, recipe_count[recipe_index], affordable)
			recipe_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			recipe_row.add_child(recipe_button)
	return card


func _make_recipe_button(building_id: String, recipe: Dictionary, affordable: bool = true) -> Button:
	var button := MetalRecipeRow.new()
	button.name = "RecipeRow_%s" % str(recipe.get("recipe_id", ""))   # tutorial spotlight target
	button.custom_minimum_size = Vector2(0, RECIPE_ROW_HEIGHT)
	button.tooltip_text = "Choose this recipe" if affordable else "Insufficient funds"
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_hover_color", TEXT)
	button.add_theme_color_override("font_pressed_color", TEXT)
	if not affordable:
		button.modulate = Color(0.62, 0.67, 0.72, 1.0)
	var clear := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, clear)
	if affordable:
		button.pressed.connect(_on_recipe_pressed.bind(building_id, str(recipe.get("recipe_id", ""))))
	else:
		button.pressed.connect(_on_unaffordable_recipe_pressed.bind(building_id))
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 5
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 14)
	button.add_child(row)
	var output_id := str(recipe.get("output_good_id", ""))
	var output_icon := _good_icon(output_id, 106, 96, int(recipe.get("output_qty", 0)))
	# Leave a deliberate 5px top/bottom gutter inside the 116px recipe card;
	# the icon frame and its goods art are both smaller than the old stretched
	# full-height control, without changing the confirm-screen material icons.
	output_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(output_icon)
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
	if affordable:
		var chevron := Label.new()
		chevron.text = "›"
		chevron.custom_minimum_size = Vector2(28, 0)
		chevron.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		chevron.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		chevron.add_theme_font_size_override("font_size", 25)
		chevron.add_theme_color_override("font_color", TEXT)
		chevron.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(chevron)
	return button


func _render_confirm() -> void:
	_search_input.visible = false
	_filter_scroll.visible = false
	_mode_toggle.visible = false
	_settings_button.visible = false
	var building_name := str(_selected_building.get("display_name", ""))
	var recipe_name := str(_selected_recipe.get("display_name", ""))
	_header_title.text = "CONFIRM CONSTRUCTION"
	# The hero card below already names the building and recipe; keep the title
	# line uncluttered on the confirm screen.
	_header_subtitle.text = ""

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
		_content.add_child(_recipe_diagram(_selected_recipe))
	else:
		_content.add_child(_infrastructure_details(_selected_building))

	var requirement_rows := _site_requirement_rows()
	if not requirement_rows.is_empty():
		_content.add_child(_section_label("SITE REQUIREMENTS"))
		for row in requirement_rows:
			_content.add_child(row)
		if _confirm_flash_pending:
			_confirm_flash_pending = false
			for row in requirement_rows:
				_flash_row(row)

	_content.add_child(_section_label("CONSTRUCTION MATERIALS"))
	var material_note := Label.new()
	material_note.text = _material_source_note()
	material_note.add_theme_font_size_override("font_size", 11)
	material_note.add_theme_color_override("font_color", MUTED)
	_content.add_child(material_note)
	_content.add_child(_materials_grid(_selected_building))
	_content.add_child(_land_required_row(_selected_building))

	var value_card := PanelContainer.new()
	value_card.add_theme_stylebox_override("panel", _panel_style(NAVY_FIELD, GOLD_DARK, 1, 9, 10))
	_content.add_child(value_card)
	var value_row := HBoxContainer.new()
	value_card.add_child(value_row)
	var value_label := Label.new()
	value_label.text = "Construction cost estimate + freight and warehousing"
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_label.add_theme_font_size_override("font_size", 12)
	value_label.add_theme_color_override("font_color", MUTED)
	value_row.add_child(value_label)
	var value := Label.new()
	value.name = "BuildCostValue"   # tutorial spotlight target (build-cost step)
	value.text = _money(_construction_display_cost(str(_selected_building.get("id", ""))))
	value.add_theme_font_size_override("font_size", 16)
	value.add_theme_color_override("font_color", TEXT)
	value_row.add_child(value)

	_add_forecast_section()

	var placement_note := Label.new()
	if _locked_tile_id != "":
		placement_note.text = "Confirm to build on %s." % Catalog.tile_label(_locked_tile_id)
	else:
		placement_note.text = "Confirming does not place the building. You will choose a tile on the map next."
	placement_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	placement_note.add_theme_font_size_override("font_size", 11)
	placement_note.add_theme_color_override("font_color", GREEN)
	_content.add_child(placement_note)

	_footer.visible = true
	var total := Label.new()
	total.text = _money(_construction_display_cost(str(_selected_building.get("id", ""))))
	total.custom_minimum_size = Vector2(90, 0)
	total.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	total.add_theme_font_size_override("font_size", 16)
	total.add_theme_color_override("font_color", TEXT)
	_footer.add_child(total)
	var confirm := Button.new()
	confirm.name = "BuildConfirmButton"   # tutorial spotlight target
	confirm.text = "Confirm" if _locked_tile_id != "" else "Confirm · select tile"
	confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm.theme_type_variation = "Primary"
	confirm.focus_mode = Control.FOCUS_NONE
	confirm.pressed.connect(_on_confirm_pressed)
	_footer.add_child(confirm)


func _materials_grid(building: Dictionary) -> Control:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", _panel_style(NAVY_FIELD, NAVY_LINE, 1, 9, 10))
	# Use the exact resolved kit Construction consumes. This keeps the confirm
	# panel and placement validation in lockstep, including infrastructure.
	var requirements := Construction.requirements_for(str(building.get("id", "")))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)
	for good_id in requirements:
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 6)
		grid.add_child(item)
		item.add_child(_good_icon(str(good_id), 60, -1, int(requirements.get(good_id, 0))))
		var description := Label.new()
		description.text = Catalog.get_display_name(str(good_id))
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


## "Land required: N" under the material kit. When the flow is locked to a tile the line
## also reports what is actually free there, and says whether auto-buy will cover the gap —
## running out of land mid-build was the single most confusing dead end in playtesting.
func _land_required_row(building: Dictionary) -> Control:
	var needed := int(round(maxf(0.0, float(building.get("tile_size_used", 1)))))
	var text := "Land required: %d" % needed
	var tint := MUTED
	if _locked_tile_id != "":
		var owned := MatchState.get_tile_land_owned(_locked_tile_id)
		var used := int(round(MatchState.get_tile_player_space_used(_locked_tile_id)))
		var free := maxi(0, owned - used)
		text += "  ·  %d free on %s" % [free, Catalog.tile_label(_locked_tile_id)]
		if free < needed:
			if MatchState.construct_auto_buy_land:
				text += "  ·  %d will be bought automatically" % (needed - free)
				tint = GREEN
			else:
				text += "  ·  not enough — buy land first"
				tint = GOLD
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", _panel_style(NAVY_FIELD, NAVY_LINE, 1, 9, 8))
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", tint)
	row.add_child(label)
	return row


# ── Site requirements ────────────────────────────────────────────────────────
# The confirm screen's answer to the commonest dead end in the build flow: a
# building whose recipe moves a fluid or draws power, dropped on a tile with no
# pipe or cable, which then quietly refuses to run. Rows are derived from the
# recipe's own goods, so new content is covered without editing this file.

## Ordered requirement rows, or empty when nothing on the recipe needs routing.
## Without a locked tile we can only state what the recipe will need. WITH one we
## know what the site already has, so inputs read as a verdict rather than a
## warning — and the OUTPUT side is worth checking too, because a fluid (or power)
## output with no way off the tile cannot be sold or shipped at all.
func _site_requirement_rows() -> Array:
	var rows: Array = []
	if _selected_recipe.is_empty():
		return rows   # infrastructure builds have no recipe, so no supply to route
	var input_needs := _infra_needs_for(_selected_recipe.get("inputs", []))
	if int(_selected_recipe.get("energy_req", 0)) > 0:
		_add_infra_need(input_needs, "cables",
			str(Catalog.get_good_by_internal_name("power").get("id", "")))
	for infra_key in INFRA_ROW_ORDER:
		if input_needs.has(infra_key):
			rows.append(_infra_requirement_row(infra_key, input_needs[infra_key], false))
	if _locked_tile_id != "":
		var output_needs := _infra_needs_for(_selected_recipe.get("outputs", []))
		for infra_key in INFRA_ROW_ORDER:
			if output_needs.has(infra_key):
				rows.append(_infra_requirement_row(infra_key, output_needs[infra_key], true))
	return rows


## {infra_key: [good_id, ...]} for the goods in `entries` that cannot move without
## infrastructure. Entries are recipe input/output dicts ({good_id, qty, ...}).
func _infra_needs_for(entries: Array) -> Dictionary:
	var needs: Dictionary = {}
	for entry in entries:
		var good_id := str((entry as Dictionary).get("good_id", ""))
		var infra_key := _infra_key_for_good(good_id)
		if infra_key != "":
			_add_infra_need(needs, infra_key, good_id)
	return needs


func _add_infra_need(needs: Dictionary, infra_key: String, good_id: String) -> void:
	if good_id == "":
		return
	var goods: Array = needs.get(infra_key, [])
	if not goods.has(good_id):
		goods.append(good_id)
	needs[infra_key] = goods


## The infrastructure one good needs to reach or leave a tile, or "" when it can
## travel overland. Mirrors infrastructure.csv's good_types_tolerated: hazardous
## liquids need the reinforced pipe, other liquids and gases accept the plain one,
## and power only moves on cables.
func _infra_key_for_good(good_id: String) -> String:
	if good_id == "":
		return ""
	match Catalog.get_transport_class(good_id):
		"hazard_liquid":
			return "reinf_pipes"
		"safe_liquid", "liquid", "gas":
			return "pipes"
		"electricity":
			return "cables"
		_:
			return ""


func _infra_requirement_row(infra_key: String, good_ids: Array, is_output: bool) -> PanelContainer:
	# Only a locked tile can be inspected. In the tile-independent flow the site is
	# still unknown, so every row states a requirement instead of passing a verdict.
	var satisfied := _locked_tile_id != "" \
		and Catalog.tile_has_infrastructure(_locked_tile_id, infra_key)

	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(0, INFRA_ROW_HEIGHT)
	row.add_theme_stylebox_override("panel",
		_panel_style(NAVY_FIELD, GREEN if satisfied else GOLD, 1, 9, 6))
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	row.add_child(body)
	body.add_child(_building_icon(Catalog.get_building_by_internal_name(infra_key), INFRA_ROW_ICON))

	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.add_theme_font_size_override("normal_font_size", 12)
	text.add_theme_font_size_override("bold_font_size", 12)
	text.add_theme_color_override("default_color", TEXT)
	var bold := _semibold_font()
	if bold != null:
		text.add_theme_font_override("bold_font", bold)
	text.text = _infra_requirement_text(infra_key, good_ids, is_output, satisfied)
	body.add_child(text)
	return row


func _infra_requirement_text(infra_key: String, good_ids: Array, is_output: bool, satisfied: bool) -> String:
	var infra := "[b]%s[/b]" % _infra_connection_name(infra_key)
	var goods := _good_name_list(good_ids)
	# One good reads better named twice ("...or you cannot sell or ship the Chlorine");
	# a list of three does not, so the second reference collapses to a pronoun.
	var them := "the %s" % goods if good_ids.size() == 1 else "them"
	if is_output:
		if satisfied:
			return "This tile already has a %s connection, so this building's output of %s can be sold or shipped." % [infra, goods]
		return "This building's output of %s requires a %s connection. Ensure you build one or you cannot sell or ship %s." % [goods, infra, them]
	if satisfied:
		return "This tile already has a %s connection for this building's supply of %s." % [infra, goods]
	return "This building requires a %s connection for its supply of %s. Ensure you build one or it cannot run." % [infra, goods]


func _good_name_list(good_ids: Array) -> String:
	var names := PackedStringArray()
	for good_id in good_ids:
		names.append(Catalog.get_display_name(str(good_id)))
	return ", ".join(names)


## The infrastructure's name as it reads inside "a ___ connection". Everywhere else
## the UI calls this infrastructure "Cables" (plural — the tile panel dial, the
## overlay legend), but "a Cables connection" is not English, so this one sentence
## takes the singular. Pipework and Reinforced Pipework are mass nouns and stand as
## infrastructure.csv names them; cables have no routing row there (power is settled
## by the grid, not the router), hence the building-name fallback.
func _infra_connection_name(infra_key: String) -> String:
	if infra_key == "cables":
		return "Cable"
	var display := str(Catalog.infra(infra_key).get("display_name", ""))
	if display == "":
		display = str(Catalog.get_building_by_internal_name(infra_key).get("display_name", ""))
	return display if display != "" else infra_key.capitalize()


func _semibold_font() -> Font:
	if not _semibold_looked_up:
		_semibold_looked_up = true
		if ResourceLoader.exists(SEMIBOLD_FONT_PATH):
			_semibold_cache = load(SEMIBOLD_FONT_PATH) as Font
	return _semibold_cache


## One white wash across a requirement row, a beat after the confirm screen lands —
## late enough that the player has begun reading, early enough to catch the eye
## before they reach Confirm. A ColorRect overlay lets the tween animate a plain
## property instead of mutating the row's shared StyleBox.
func _flash_row(row: Control) -> void:
	var wash := ColorRect.new()
	wash.color = Color(1, 1, 1, 0)
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(wash)
	var tween := row.create_tween()
	tween.tween_interval(INFRA_FLASH_DELAY)
	tween.tween_property(wash, "color:a", INFRA_FLASH_PEAK, INFRA_FLASH_UP) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(wash, "color:a", 0.0, INFRA_FLASH_DOWN) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_callback(wash.queue_free)


func _section_label(text: String) -> Control:
	# Matches the Tile View's compact section heading: a clear uppercase title,
	# off-white type and a restrained accent rule rather than plain body text.
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 21)
	row.add_theme_constant_override("separation", 7)
	var rule := ColorRect.new()
	rule.color = GOLD_DARK
	rule.custom_minimum_size = Vector2(3, 0)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(rule)
	var label := Label.new()
	label.text = text.to_upper()
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", TEXT)
	row.add_child(label)
	return row


func _building_icon(building: Dictionary, icon_size: int) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(icon_size, icon_size)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var building_id := str(building.get("id", ""))
	var internal := str(building.get("internal_name", ""))
	# BuildingIcon removes the navy PNG tile and crops the glyph. Stack a cast
	# shadow, top-left catch and clean off-white art to emboss it into the same
	# brushed-metal face used by the Tile View building cards.
	var texture := BuildingIcon.clean_texture(building_id, internal)
	if texture == null:
		return holder
	for layer in [
		{"offset": Vector2(5.0, 5.0), "tint": Color(0.02, 0.035, 0.045, 0.38)},
		{"offset": Vector2(3.0, 3.0), "tint": Color(0.01, 0.02, 0.03, 0.68)},
		{"offset": Vector2(-1.0, -1.0), "tint": Color(1, 1, 1, 0.45)},
		{"offset": Vector2.ZERO, "tint": Color(0.93, 0.96, 1.0)},
	]:
		var art := TextureRect.new()
		art.texture = texture
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		var offset: Vector2 = layer.get("offset", Vector2.ZERO)
		art.offset_left = offset.x
		art.offset_top = offset.y
		art.offset_right = offset.x
		art.offset_bottom = offset.y
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.modulate = layer.get("tint", Color.WHITE)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(art)
	return holder


func _good_icon(good_id: String, icon_size: int, plate_width: int = -1, qty: int = 0) -> Control:
	# Cream, rounded-square pedestal. Leave a deliberate internal gutter so the
	# goods read as inset objects, never bleeding into the frame or neighbouring row.
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(icon_size if plate_width < 0 else plate_width, icon_size)
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
	var inset := maxf(4.0, float(icon_size) * 0.12)
	art.offset_left = inset
	art.offset_top = inset
	art.offset_right = -inset
	art.offset_bottom = -inset
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(art)
	if qty > 0:
		var pill := UIHelpers.make_quantity_pill(str(qty), 24, 14)
		var pill_size := pill.custom_minimum_size
		pill.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		pill.offset_left = -pill_size.x - 2
		pill.offset_top = -pill_size.y - 2
		pill.offset_right = -2
		pill.offset_bottom = -2
		pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(pill)
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


func _recipe_diagram(recipe: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = DIAGRAM_PAPER
	card_style.set_corner_radius_all(2)
	card_style.set_content_margin_all(0)
	card.add_theme_stylebox_override("panel", card_style)
	var diagram_root := Control.new()
	# Match Building Details' flow card: 62px goods cells in a compact 2x2
	# grid, with enough vertical room for the second row and quantity pills.
	diagram_root.custom_minimum_size = Vector2(0, 140)
	diagram_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(diagram_root)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 10
	row.offset_top = 8
	row.offset_right = -10
	row.offset_bottom = -8
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	diagram_root.add_child(row)
	var inputs := GridContainer.new()
	inputs.columns = 1
	inputs.add_theme_constant_override("h_separation", 4)
	inputs.add_theme_constant_override("v_separation", 0)
	inputs.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(inputs)
	var source := recipe.get("inputs", []) as Array
	if source.is_empty():
		var raw := Label.new()
		raw.text = "RAW\nEXTRACTION"
		raw.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		raw.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		raw.add_theme_font_size_override("font_size", 11)
		raw.add_theme_color_override("font_color", DIAGRAM_NAVY)
		inputs.add_child(raw)
	else:
		inputs.columns = 2 if source.size() > 2 else 1
		var input_size := 62
		for input in source:
			inputs.add_child(_recipe_flow_cell(str(input.get("good_id", "")), int(input.get("qty", 0)), input_size))
	var energy := int(recipe.get("energy_req", 0))
	var arrow := RecipePowerPentagon.new() if energy > 0 else Control.new()
	arrow.custom_minimum_size = Vector2(96, 58)
	arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if energy > 0:
		var badge := HBoxContainer.new()
		badge.alignment = BoxContainer.ALIGNMENT_CENTER
		badge.set_anchors_preset(Control.PRESET_FULL_RECT)
		badge.add_theme_constant_override("separation", 3)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var energy_label := Label.new()
		energy_label.text = str(energy)
		energy_label.add_theme_font_size_override("font_size", 16)
		energy_label.add_theme_color_override("font_color", DIAGRAM_PAPER)
		badge.add_child(energy_label)
		var bolt := TextureRect.new()
		bolt.texture = load(RECIPE_POWER_ICON_PATH) as Texture2D
		bolt.custom_minimum_size = Vector2(16, 16)
		bolt.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bolt.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		badge.add_child(bolt)
		arrow.add_child(badge)
	else:
		var arrow_art := TextureRect.new()
		arrow_art.texture = load(RECIPE_ARROW_PATH) as Texture2D
		arrow_art.set_anchors_preset(Control.PRESET_FULL_RECT)
		arrow_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		arrow_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		arrow_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		arrow.add_child(arrow_art)
	row.add_child(arrow)
	var output := VBoxContainer.new()
	output.alignment = BoxContainer.ALIGNMENT_CENTER
	var output_good_id := str(recipe.get("output_good_id", ""))
	var output_qty := int(recipe.get("output_qty", 0))
	if Catalog.get_internal_name(output_good_id) == "power":
		output.add_child(_power_output_cell(output_qty, 62))
	else:
		output.add_child(_recipe_flow_cell(output_good_id, output_qty, 62))
	row.add_child(output)
	# The navy rule is intentionally inside the cream card, four pixels from its
	# edge; it belongs to the recipe diagram, not the recipe-selection row.
	var inset_rule := Panel.new()
	inset_rule.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inset_rule.offset_left = 4
	inset_rule.offset_top = 4
	inset_rule.offset_right = -4
	inset_rule.offset_bottom = -4
	inset_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var inset_style := StyleBoxFlat.new()
	inset_style.bg_color = Color(0, 0, 0, 0)
	inset_style.border_color = DIAGRAM_NAVY
	inset_style.set_border_width_all(3)
	inset_style.set_corner_radius_all(0)
	inset_rule.add_theme_stylebox_override("panel", inset_style)
	diagram_root.add_child(inset_rule)
	return card


func _recipe_flow_cell(good_id: String, qty: int, size_px: int) -> Panel:
	var cell := Panel.new()
	cell.custom_minimum_size = Vector2(size_px, size_px)
	cell.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var clear := StyleBoxFlat.new()
	clear.bg_color = Color(1, 1, 1, 0)
	cell.add_theme_stylebox_override("panel", clear)
	var art := TextureRect.new()
	art.texture = GoodIcons.texture_for(good_id, Catalog.get_internal_name(good_id), size_px < 80)
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.offset_left = 3
	art.offset_top = 3
	art.offset_right = -3
	art.offset_bottom = -3
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(art)
	if qty > 0:
		var pill := UIHelpers.make_quantity_pill(str(qty), 24, 14)
		var pill_size := pill.custom_minimum_size
		pill.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		pill.offset_left = -pill_size.x - 2
		pill.offset_top = -pill_size.y - 2
		pill.offset_right = -2
		pill.offset_bottom = -2
		cell.add_child(pill)
	return cell


func _power_output_cell(qty: int, size_px: int = 62) -> Control:
	# Power outputs use the same cream tile-view card treatment as the power
	# cards, with the yellow lightning icon and navy quantity pill inset.
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(size_px, size_px)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var plate := PanelContainer.new()
	plate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = CREAM
	style.border_color = CREAM_SHADOW
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	plate.add_theme_stylebox_override("panel", style)
	holder.add_child(plate)
	var icon := TextureRect.new()
	icon.texture = load(RECIPE_POWER_ICON_PATH) as Texture2D
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 7
	icon.offset_top = 7
	icon.offset_right = -7
	icon.offset_bottom = -7
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(icon)
	if qty > 0:
		var pill := UIHelpers.make_quantity_pill(str(qty), 24, 14)
		var pill_size := pill.custom_minimum_size
		pill.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		pill.offset_left = -pill_size.x - 2
		pill.offset_top = -pill_size.y - 2
		pill.offset_right = -2
		pill.offset_bottom = -2
		pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(pill)
	return holder


func _infrastructure_details(building: Dictionary) -> VBoxContainer:
	var result := VBoxContainer.new()
	result.add_theme_constant_override("separation", 7)
	result.add_child(_section_label("INFRASTRUCTURE"))
	var purpose := Label.new()
	purpose.text = InfrastructureInfo.purpose(InfrastructureInfo.key_for(building))
	purpose.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	purpose.add_theme_font_size_override("font_size", 13)
	purpose.add_theme_color_override("font_color", TEXT)
	purpose.add_theme_stylebox_override("normal", _panel_style(NAVY_FIELD, NAVY_LINE, 1, 9, 10))
	result.add_child(purpose)
	var key := InfrastructureInfo.key_for(building)
	if InfrastructureInfo.has_level_stats(key):
		result.add_child(_section_label("STATS"))
		var stat_card := PanelContainer.new()
		stat_card.add_theme_stylebox_override("panel", _panel_style(NAVY_FIELD, NAVY_LINE, 1, 9, 7))
		var levels := VBoxContainer.new()
		levels.add_theme_constant_override("separation", 4)
		stat_card.add_child(levels)
		for level in range(1, 4):
			levels.add_child(_infrastructure_level_accordion(key, level))
		result.add_child(stat_card)
	return result


func _infrastructure_level_accordion(key: String, level: int) -> VBoxContainer:
	var box := VBoxContainer.new()
	var stats := InfrastructureInfo.level_stats(key, level)
	var header := Button.new()
	header.text = "Level %d   ▸" % level
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.custom_minimum_size = Vector2(0, 28)
	_style_button(header, NAVY_RAISED, NAVY_LINE, TEXT)
	box.add_child(header)
	var details := VBoxContainer.new()
	details.visible = level == 1
	details.add_theme_constant_override("separation", 3)
	box.add_child(details)
	for item in [[str(stats.get("capacity_label", "Transport soft cap")), str(stats.get("capacity", "—"))], ["Tiles covered in 1 turn", str(stats.get("tiles", "—"))], ["Cost per unit", str(stats.get("cost", "—"))]]:
		var line := HBoxContainer.new()
		var name := Label.new()
		name.text = str(item[0])
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name.add_theme_font_size_override("font_size", 10)
		name.add_theme_color_override("font_color", MUTED)
		line.add_child(name)
		var value := Label.new()
		value.text = str(item[1])
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.add_theme_font_size_override("font_size", 10)
		value.add_theme_color_override("font_color", TEXT)
		line.add_child(value)
		details.add_child(line)
	header.pressed.connect(func() -> void:
		details.visible = not details.visible
		header.text = "Level %d   %s" % [level, "▾" if details.visible else "▸"])
	return box


func _on_search_changed(text: String) -> void:
	_search_query = text
	_render()


func _on_filter_toggled(pressed: bool, category: String) -> void:
	# Single-select: the chips read as alternative views of the catalogue, not as
	# stackable predicates, so a new pick replaces the previous one and clicking the
	# active chip clears the filter. _rebuild_filters sets button_pressed before it
	# connects this signal, so the re-render can't feed a toggle back in.
	_active_filters.clear()
	if pressed:
		_active_filters[category] = true
	_render()


func _on_building_pressed(building_id: String) -> void:
	_expanded_building_id = "" if _expanded_building_id == building_id else building_id
	_render()


## The trajectory the player is buying: construction turns, the dip while inputs are bought
## before the first sale settles, then the steady margin. Added to the CONFIRM view because
## that is the last moment the decision is free. See docs/early-game-onboarding-spec.md §5.1.
func _add_forecast_section() -> void:
	var building_id := str(_selected_building.get("id", ""))
	var recipe_id := str(_selected_recipe.get("recipe_id", ""))
	if building_id == "" or recipe_id == "":
		return
	var data: Dictionary = BuildForecast.project(building_id, recipe_id, _locked_tile_id)
	var phases: Array = data.get("phases", [])
	if phases.is_empty():
		return

	_content.add_child(_section_label("WHAT IT DOES TO YOUR CASH"))

	# A tile with no route to an input is the run-D failure: the player builds, the building
	# never runs, and nothing says why. Say it here, in red, before the money moves.
	if bool(data.get("no_supply", false)):
		var warn := Label.new()
		warn.text = "No supply route on this tile for %s — it would sit idle." \
			% ", ".join(PackedStringArray(data.get("input_names", [])))
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		warn.add_theme_font_size_override("font_size", 11)
		warn.add_theme_color_override("font_color", RED)
		_content.add_child(warn)

	var table: PanelContainer = BuildForecastTable.new()
	table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table.set_forecast(data)
	_content.add_child(table)

	# The one number that decides whether this build is affordable: what the phases before
	# revenue will take out of the bank. The playtester's failed expansion was exactly this —
	# affordable to build, unaffordable to run until it sold anything.
	var cash_needed := float(data.get("cash_needed", 0.0))
	var steady := float(data.get("steady_net", 0.0))
	var summary := Label.new()
	if steady <= 0.0:
		summary.text = "Costs %s before the first sale, then still loses %s a turn at today's prices." \
			% [_money(cash_needed), _money(-steady)]
		summary.add_theme_color_override("font_color", RED)
	else:
		summary.text = "Needs %s in the bank to reach the first sale, then earns %s a turn." \
			% [_money(cash_needed), _money(steady)]
		summary.add_theme_color_override("font_color", GREEN if MatchState.money >= cash_needed else RED)
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.add_theme_font_size_override("font_size", 12)
	_content.add_child(summary)

	var caption := Label.new()
	caption.text = "Per turn, at today's prices: goods, freight, port fees, storage, power, labour and upkeep. Assumes it sells straight to market with any pipework already built."
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.add_theme_font_size_override("font_size", 10)
	caption.add_theme_color_override("font_color", MUTED)
	_content.add_child(caption)


func _on_recipe_pressed(building_id: String, recipe_id: String) -> void:
	if not _is_building_affordable(building_id):
		_show_insufficient_funds(building_id)
		return
	_selected_building = Catalog.get_building(building_id)
	_selected_recipe = Catalog.get_recipe(recipe_id)
	if _selected_building.is_empty() or _selected_recipe.is_empty():
		return
	_view = View.CONFIRM
	_confirm_flash_pending = true
	_render()


func _on_unaffordable_recipe_pressed(building_id: String) -> void:
	_show_insufficient_funds(building_id)


func _is_building_affordable(building_id: String) -> bool:
	return _construction_display_cost(building_id) <= MatchState.money + 0.0001


func _show_insufficient_funds(building_id: String) -> void:
	var needed := _construction_display_cost(building_id)
	MatchState.request_toast("Insufficient funds. Need %s and have %s." % [_money(needed), _money(MatchState.money)], "caution")


func _on_infrastructure_selected(building_id: String) -> void:
	_selected_building = Catalog.get_building(building_id)
	_selected_recipe = {}
	if _selected_building.is_empty():
		return
	_view = View.CONFIRM
	_confirm_flash_pending = true
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
	if not _is_building_affordable(building_id):
		_show_insufficient_funds(building_id)
		return
	if _locked_tile_id != "":
		# Tile-locked (opened from a tile's Build): build directly here, no map pick.
		# Only recipe-based buildings reach this flow — infrastructure has no recipes
		# and is filtered out of the locked list — but guard defensively anyway.
		if _selected_recipe.is_empty():
			return
		BuildMode.attempt_direct_build(building_id, str(_selected_recipe.get("recipe_id", "")), _locked_tile_id)
		MatchState.request_toast("Building %s on %s." % [str(_selected_building.get("display_name", "this building")), Catalog.tile_label(_locked_tile_id)], "info")
		hide()
		return
	if _selected_recipe.is_empty():
		BuildMode.enter_infrastructure_mode(str(_selected_building.get("internal_name", "")), true)
	else:
		BuildMode.enter_build_mode(building_id, str(_selected_recipe.get("recipe_id", "")), true)
	MatchState.request_toast("Construction confirmed — select a tile for %s." % str(_selected_building.get("display_name", "this building")), "info")
	hide()


func _money(value: float) -> String:
	return "£%s" % _format_number(value)


func _construction_display_cost(building_id: String) -> float:
	# Before a tile is selected, show the deterministic cash leg plus the actual
	# buy-side market price of the resolved material kit. Freight/warehousing is
	# site-dependent and is called out in the estimate label above.
	var building := Catalog.get_building(building_id)
	return maxf(0.0, float(building.get("base_price", 0.0))) + Construction.market_purchase_value(building_id)


func _material_source_note() -> String:
	# In the tile-locked flow the site is already known, so name it instead of
	# "the tile you select next".
	var where := Catalog.tile_label(_locked_tile_id) if _locked_tile_id != "" else "the tile you select next"
	match MatchState.construct_material_source:
		"market":
			return "Materials will be bought from the market when needed at %s." % where
		"same_tile":
			return "The selected tile must already hold every required construction material."
		"any_tile":
			return "Materials will be pulled from a tile with surplus when one is available."
		_:
			return "These resources are required at %s." % where


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
