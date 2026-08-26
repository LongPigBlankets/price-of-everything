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
var _pinned: VBoxContainer
var _footer: HBoxContainer
var _footer_panel: PanelContainer   # background wrapper around _footer; see _build_shell
var _footer_rule: Control           # ledger double-rule above the footer; toggles with it

var _view := View.BROWSE
var _buildings: Array = []
var _recipes_by_building: Dictionary = {}
var _active_filters: Dictionary = {}  # classic Construct building_type filters

# Land bought as part of THIS build, decided on the confirm screen. Zero unless the locked
# tile is short and there is land left to buy on it.
var _land_purchase_units := 0
var _land_purchase_cost := 0.0
var _buy_land_wanted := false
var _buy_land_checkbox: CheckBox = null
var _confirm_total_label: Label = null
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

# ── Confirm V3 state (`swap construct_panel_v3`) ─────────────────────────────
# The sim projections are computed once per render and cached here so every band
# (verdict strip, requirements, timeline, materials, footer reason) reads the
# same numbers — the reconciliation the spec asks for is structural.
var _v3_ledger: Dictionary = {}        # Construction.materials_ledger for this render
var _v3_forecast: Dictionary = {}      # BuildForecast.project for this render
var _v3_land: Dictionary = {}          # _v3_compute_land() facts for this render
var _v3_last_total := -1.0             # previous grand total, for the change tick
var _v3_verdict_total_label: Label = null
# Whether the player has touched the land-purchase toggle THIS confirm session
# (v3.1, owner 2026-08-26: the toggle is back, ticked by default). Once true,
# _v3_compute_land() stops defaulting _buy_land_wanted back to true on every
# re-render — a live money/price recompute must not silently re-tick a box the
# player just unticked. Reset whenever a fresh confirm opens.
var _land_toggle_touched := false
# Priority-supply choice for intermittent-power buildings (v3.1 preview, owner
# 2026-08-26: stub the control, no sim wiring). "grid" | "buildings". Panel-local
# only — never read by BuildForecast or Production. Reset per confirm session.
var _v3_priority_supply := "grid"


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
	if not MatchState.construct_panel_v3_changed.is_connected(_on_construct_panel_v3_changed):
		MatchState.construct_panel_v3_changed.connect(_on_construct_panel_v3_changed)
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
	_v3_last_total = -1.0
	_v3_verdict_total_label = null
	_land_toggle_touched = false
	_v3_priority_supply = "grid"
	if _search_input != null:
		_search_input.text = ""


func _on_visibility_changed() -> void:
	if not visible:
		PanelStack.remove(self)
		return
	if not MatchState.use_construct_panel_v2:
		hide()
		return
	# Owner 2026-08-26: Esc didn't close this panel — remove() was already here,
	# but push() never was, so world_map's Esc handler (PanelStack.close_top())
	# never found it registered. Every other panel pairs the two; this one was
	# missing half the contract.
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
	# change immediately updates which buildings can be selected. The V3 confirm
	# recomputes live too (spec §7): affordability chip, reason line and totals
	# follow the bank balance while the player is deciding.
	if visible and (_view == View.BROWSE or _v3_confirm_live()):
		_render()


## True when the V3 confirm screen is the live view — the layout that recomputes
## on money/price changes. Infrastructure confirms keep the V2 layout and its
## static behaviour.
func _v3_confirm_live() -> bool:
	return _view == View.CONFIRM and MatchState.use_construct_panel_v3 \
		and not _selected_recipe.is_empty()

func _on_construct_settings_changed() -> void:
	if visible:
		_render()


## The `swap construct_panel_v3` cheat flipped: re-render so the V3-gated visuals
## (icon-plate keyline, confirm redesign as it lands) apply without reopening.
func _on_construct_panel_v3_changed(_enabled: bool) -> void:
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
	_v3_last_total = -1.0
	_land_toggle_touched = false
	_v3_priority_supply = "grid"
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
	_search_input.add_theme_color_override("font_placeholder_color", _muted_tone())
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

	# V3 confirm: bands 1–2 (identity + verdict strip) pin here, ABOVE the scroll,
	# so the decision survives above the fold at every panel height (spec §1).
	# Bands 3–5 scroll underneath in _content as before.
	_pinned = VBoxContainer.new()
	_pinned.visible = false
	_pinned.add_theme_constant_override("separation", 8)
	root.add_child(_pinned)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(_scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 8)
	_scroll.add_child(_content)

	_footer = HBoxContainer.new()
	_footer.custom_minimum_size = Vector2(0, 62)
	_footer.add_theme_constant_override("separation", 10)
	# A real background + the same ledger double-rule that marks the verdict strip
	# (DS.section_rule) so the footer reads as a docked band regardless of what's
	# scrolled up against it. A plain NAVY_LINE border was tried first and proved
	# too close in value to both the fill and the panel's own near-black backing
	# to read as a divider at all — BORDER_SOFT (what section_rule draws) is the
	# tone this theme actually uses for a visible structural line on these navies.
	_footer_rule = DS.section_rule(true)
	_footer_rule.visible = false
	root.add_child(_footer_rule)
	_footer_panel = PanelContainer.new()
	_footer_panel.visible = false
	_footer_panel.add_theme_stylebox_override("panel", _panel_style(NAVY_RAISED, NAVY_RAISED, 0, 0, 0))
	_footer_panel.add_child(_footer)
	root.add_child(_footer_panel)


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
	for child in _pinned.get_children():
		child.queue_free()
	_pinned.visible = false
	_footer_panel.visible = false
	_footer_rule.visible = false
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
	_style_button(back, NAVY_RAISED, NAVY_LINE, _muted_tone())
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
	output_note.add_theme_color_override("font_color", _muted_tone())
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
	source_note.add_theme_color_override("font_color", _muted_tone())
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

	# Credit facility default. Greyed out without a CFO: the facility is arranged BY the CFO, so
	# offering the choice with the seat empty would promise something the sim will refuse.
	var has_cfo := MatchState.cfo_seated()
	var credit_card := PanelContainer.new()
	credit_card.add_theme_stylebox_override("panel", _panel_style(NAVY_FIELD, NAVY_LINE, 1, 9, 11))
	_content.add_child(credit_card)
	var credit_box := VBoxContainer.new()
	credit_box.add_theme_constant_override("separation", 7)
	credit_card.add_child(credit_box)
	var credit_title := Label.new()
	credit_title.text = "Credit facility for new buildings"
	credit_title.add_theme_font_size_override("font_size", 14)
	credit_title.add_theme_color_override("font_color", TEXT if has_cfo else _muted_tone())
	credit_box.add_child(credit_title)
	var credit_note := Label.new()
	credit_note.text = "A new building's first %d turns of inputs, labour, energy and maintenance can be carried instead of paid." % MatchState.TAB_WINDOW_TURNS
	credit_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	credit_note.add_theme_font_size_override("font_size", 11)
	credit_note.add_theme_color_override("font_color", _muted_tone())
	credit_box.add_child(credit_note)
	if not has_cfo:
		var need_cfo := Label.new()
		need_cfo.text = "Requires a CFO to enable"
		need_cfo.add_theme_font_size_override("font_size", 12)
		need_cfo.add_theme_color_override("font_color", RED)
		credit_box.add_child(need_cfo)
	var credit_group := ButtonGroup.new()
	for option in [
		{"id": "ask", "title": "Always choose", "detail": "Prompt each time a building is a turn from finishing"},
		{"id": "slices", "title": "%d turns, no interest" % MatchState.TAB_SLICES, "detail": "Repay in equal interest-free instalments"},
		{"id": "loan", "title": "Take it as a loan", "detail": "Smaller payments over a full loan term, with interest"},
		{"id": "none", "title": "Don't use the facility", "detail": "Costs hit cash as they fall"},
	]:
		var option_id := str(option.get("id", ""))
		var selected := MatchState.construct_credit_default == option_id
		var radio_text := "●" if selected else "○"
		var choice := _settings_choice_button(
			"%s  %s\n    %s" % [radio_text, str(option.get("title", "")), str(option.get("detail", ""))],
			selected, credit_group, true)
		choice.disabled = not has_cfo
		if has_cfo:
			choice.pressed.connect(_on_credit_default_selected.bind(option_id))
		credit_box.add_child(choice)

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
	note.add_theme_color_override("font_color", _muted_tone())
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


func _on_credit_default_selected(mode: String) -> void:
	MatchState.set_construct_credit_default(mode)
	_render()


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
		empty.add_theme_color_override("font_color", _muted_tone())
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
			NAVY if selected else _muted_tone())
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
	category.add_theme_color_override("font_color", Color("#697583") if disabled or not affordable else _muted_tone())
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
	chevron.add_theme_color_override("font_color", _muted_tone())
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
		hint.add_theme_color_override("font_color", _muted_tone())
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
	detail.add_theme_color_override("font_color", _muted_tone())
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
	# V3 gets its own confirm layout (bands in decision order, spec §1). The
	# infrastructure confirm — no recipe, no cash story — keeps the V2 layout.
	if MatchState.use_construct_panel_v3 and not _selected_recipe.is_empty():
		_render_confirm_v3()
		return
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
	_style_button(back, NAVY_RAISED, NAVY_LINE, _muted_tone())
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
	sub.add_theme_color_override("font_color", _muted_tone())
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
	material_note.add_theme_color_override("font_color", _muted_tone())
	_content.add_child(material_note)
	_content.add_child(_materials_grid(_selected_building))

	var value_card := PanelContainer.new()
	value_card.add_theme_stylebox_override("panel", _panel_style(NAVY_FIELD, GOLD_DARK, 1, 9, 10))
	_content.add_child(value_card)
	var value_row := HBoxContainer.new()
	value_card.add_child(value_row)
	var value_label := Label.new()
	value_label.text = "Construction cost estimate + freight and warehousing"
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_label.add_theme_font_size_override("font_size", 12)
	value_label.add_theme_color_override("font_color", _muted_tone())
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

	# Land sits with the Confirm button, not up with the material kit: buying it is a
	# DECISION the player makes at the moment of committing, and it costs money the total
	# below has to include (owner 2026-08-23).
	_content.add_child(_land_row(_selected_building))

	_footer_panel.visible = true
	_footer_rule.visible = true
	var total := Label.new()
	_confirm_total_label = total
	total.text = _money(_confirm_total_cost())
	total.custom_minimum_size = Vector2(90, 0)
	total.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	total.add_theme_font_size_override("font_size", 16)
	total.add_theme_color_override("font_color", TEXT)
	_footer.add_child(total)
	var confirm := Button.new()
	confirm.name = "BuildConfirmButton"   # tutorial spotlight target
	confirm.text = "Confirm" if _locked_tile_id != "" else "Confirm · select tile"
	confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# The CTA stays the steel-blue Primary in V3 too (owner 2026-08-26): every
	# commit button in the game is steel blue, and consistency beats the spec's
	# brass here. The DS "Brass" variation remains available for accents.
	confirm.theme_type_variation = "Primary"
	confirm.focus_mode = Control.FOCUS_NONE
	confirm.pressed.connect(_on_confirm_pressed)
	_footer.add_child(confirm)


# ── Confirm V3 (spec "Confirm Construction Panel v2"; `swap construct_panel_v3`) ──
# Five bands in decision order: identity and the verdict strip pin above the
# scroll; requirements, the cash timeline and the materials ledger scroll under
# them; the sticky footer carries the grand total, Confirm, and — whenever the
# button is disabled — the reason in words. Site coordinates appear ONCE, in the
# header subtitle, and nowhere else.

const V3_PHASE_LABELS := {
	"building": "Building", "completes": "Completes",
	"shipping": "First production run", "selling": "Selling",
}


func _render_confirm_v3() -> void:
	_search_input.visible = false
	_filter_scroll.visible = false
	_mode_toggle.visible = false
	_settings_button.visible = false
	_confirm_flash_pending = false   # the verdict strip is the "look here" now

	var building_id := str(_selected_building.get("id", ""))
	_header_title.text = "CONFIRM CONSTRUCTION"
	_header_subtitle.text = Catalog.tile_label(_locked_tile_id) if _locked_tile_id != "" \
		else "Site: chosen on the map after confirming"

	_v3_land = _v3_compute_land()
	_v3_ledger = Construction.materials_ledger(building_id, _locked_tile_id)
	_v3_forecast = BuildForecast.project(building_id,
		str(_selected_recipe.get("recipe_id", "")), _locked_tile_id)

	_pinned.visible = true
	_pinned.add_child(_v3_header_band())
	_pinned.add_child(_v3_verdict_strip())

	_content.add_child(_section_label("REQUIREMENTS"))
	for row in _v3_requirement_rows():
		_content.add_child(row)

	# Priority supply (v3.1 preview, owner 2026-08-26: stub only, no sim wiring —
	# every intermittent building still prices as fully grid-sold).
	if str(_selected_building.get("internal_name", "")) in EconomyConfig.POWER_INTERMITTENT_BUILDINGS:
		_content.add_child(_section_label("SETTINGS"))
		_content.add_child(_v3_priority_supply_band())

	if not (_v3_forecast.get("phases", []) as Array).is_empty():
		_content.add_child(_section_label("WHAT IT DOES TO YOUR CASH"))
		if bool(_v3_forecast.get("no_supply", false)):
			var warn := Label.new()
			warn.text = "No supply route on this tile for %s — it would sit idle." \
				% ", ".join(PackedStringArray(_v3_forecast.get("input_names", [])))
			warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			warn.add_theme_font_size_override("font_size", 11)
			warn.add_theme_color_override("font_color", RED)
			_content.add_child(warn)
		_content.add_child(_v3_cash_timeline())
		# Buffer / run rate / payback sit beside the timeline they explain (v3.1,
		# from the V4 iteration) rather than crowding the always-visible verdict
		# strip, which now carries only the total, build time and the chip.
		_content.add_child(_v3_cash_facts())
		var caption := Label.new()
		caption.text = "Per turn, at today's prices: goods, freight, port fees, storage, power, labour and upkeep. Assumes it sells straight to market with any pipework already built."
		caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		caption.add_theme_font_size_override("font_size", 11)
		caption.add_theme_color_override("font_color", _muted_tone())
		_content.add_child(caption)

	_content.add_child(_section_label("MATERIALS"))
	for row in _v3_material_rows():
		_content.add_child(row)
	_content.add_child(_v3_materials_totals())

	# The recipe survives, demoted below the decision bands: reference material,
	# not part of the verdict (owner 2026-08-26: shown open, not behind a tap —
	# the v3.1 collapse-by-default read as hiding it, not demoting it).
	_content.add_child(_section_label("RECIPE"))
	_content.add_child(_recipe_diagram(_selected_recipe))

	_v3_build_footer()
	_v3_pulse_if_changed(_v3_total_cost())


## Band 1 — identity: icon plate, recipe + building name, and the small
## "‹ Recipe" back link. The header's X stays the single close control (§7):
## never two same-weight exits.
func _v3_header_band() -> Control:
	var band := HBoxContainer.new()
	band.add_theme_constant_override("separation", 11)
	band.add_child(_building_icon(_selected_building, 48))
	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text_box.add_theme_constant_override("separation", 1)
	band.add_child(text_box)
	var title := Label.new()
	title.text = str(_selected_recipe.get("display_name", ""))
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", TEXT)
	text_box.add_child(title)
	var sub := Label.new()
	sub.text = str(_selected_building.get("display_name", ""))
	sub.add_theme_font_size_override("font_size", 11)
	sub.add_theme_color_override("font_color", _muted_tone())
	text_box.add_child(sub)
	var back := Button.new()
	back.text = "‹ Recipe"
	back.flat = true
	back.focus_mode = Control.FOCUS_NONE
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back.add_theme_font_size_override("font_size", 13)
	back.add_theme_color_override("font_color", _muted_tone())
	back.add_theme_color_override("font_hover_color", TEXT)
	back.pressed.connect(_on_back_to_browse)
	band.add_child(back)
	return band


## Band 2 — the decision in one band (§2), kept minimal (v3.1, from the V4
## iteration): itemised grand total, build time, affordability chip. Buffer, run
## rate and payback moved to sit beside the cash timeline that explains them
## (_v3_cash_facts) — the strip stays the one thing that's ALWAYS pinned. Fill
## only, no border — borders carry semantics, and the strip is structure. The
## double rule above it is the ledger's mark for a totals band.
func _v3_verdict_strip() -> Control:
	var box := VBoxContainer.new()
	box.name = "V3VerdictStrip"
	box.add_theme_constant_override("separation", 5)
	box.add_child(DS.section_rule(true))

	var strip := PanelContainer.new()
	strip.add_theme_stylebox_override("panel", _panel_style(NAVY_RAISED, NAVY_RAISED, 0, 9, 10))
	box.add_child(strip)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	strip.add_child(col)

	var total_row := HBoxContainer.new()
	total_row.add_theme_constant_override("separation", 9)
	col.add_child(total_row)
	var total := Label.new()
	total.name = "V3Total"
	total.theme_type_variation = "Numeric"
	total.add_theme_font_size_override("font_size", 20)
	total.text = _money(_v3_total_cost())
	_v3_verdict_total_label = total
	total_row.add_child(total)
	var itemised := Label.new()
	if _buy_land_wanted and _land_purchase_cost > 0.0:
		itemised.text = "construction %s + land %s" % [
			_money(_v3_construction_cost()), _money(_land_purchase_cost)]
	else:
		itemised.text = "construction"
	itemised.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	itemised.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	itemised.add_theme_font_size_override("font_size", 11)
	itemised.add_theme_color_override("font_color", _muted_tone())
	total_row.add_child(itemised)
	total_row.add_child(_v3_afford_chip())

	var facts := GridContainer.new()
	facts.columns = 2
	facts.add_theme_constant_override("h_separation", 12)
	facts.add_theme_constant_override("v_separation", 2)
	col.add_child(facts)
	var build_turns := int(_v3_forecast.get("build_turns", 0))
	_v3_fact(facts, "Build time", "%d turn%s" % [build_turns, "" if build_turns == 1 else "s"], TEXT, "")
	return box


## Buffer, run rate and payback (v3.1, moved out of the verdict strip — see
## _v3_verdict_strip): placed right beside the cash timeline they explain instead
## of crowding the band that has to stay pinned at every panel height.
func _v3_cash_facts() -> Control:
	var facts := GridContainer.new()
	facts.columns = 2
	facts.add_theme_constant_override("h_separation", 14)
	facts.add_theme_constant_override("v_separation", 5)
	_v3_fact(facts, "Buffer", "needs %s in the bank to reach the first sale"
		% _money(float(_v3_forecast.get("cash_needed", 0.0))), TEXT,
		"What the building costs from the day it completes until its first sale lands: labour, upkeep, inputs, power and storage.")
	var steady := float(_v3_forecast.get("steady_net", 0.0))
	_v3_fact(facts, "Run rate", "%s/turn once selling" % _signed_money(steady),
		GREEN if steady > 0.0 else RED, "")
	var payback := BuildForecast.payback_turn(_v3_total_cost(),
		float(_v3_forecast.get("cash_needed", 0.0)), steady,
		int(_v3_forecast.get("first_selling_turn", 0)))
	_v3_fact(facts, "Payback",
		"pays back ~turn %d" % payback if payback > 0 else "never at today's prices",
		TEXT if payback > 0 else RED,
		"At today's prices: construction, land and every pre-revenue cost, earned back at the steady per-turn margin.")
	return facts


## Owner 2026-08-26: these read as the panel's decisive facts, so they carry
## more weight than a caption/value pair usually would — bigger and bold
## (Numeric = SemiBold in this theme), not just a quiet key beside a value.
func _v3_fact(grid: GridContainer, key: String, value: String, tone: Color, tip: String) -> void:
	var key_label := Label.new()
	key_label.text = key
	key_label.add_theme_font_size_override("font_size", 13)
	key_label.add_theme_color_override("font_color", _muted_tone())
	grid.add_child(key_label)
	var value_label := Label.new()
	value_label.text = value
	value_label.theme_type_variation = "Numeric"
	value_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_label.add_theme_font_size_override("font_size", 15)
	value_label.add_theme_color_override("font_color", tone)
	if tip != "":
		value_label.tooltip_text = tip
		value_label.mouse_filter = Control.MOUSE_FILTER_PASS
	grid.add_child(value_label)


## The RAG chip (§2): green = affordable incl. buffer · amber = affordable but the
## buffer is not covered · red = cannot afford. Always states its verdict in words —
## never colour-only. One of the four places a coloured border is allowed (§4).
func _v3_afford_chip() -> Control:
	var verdict := BuildForecast.affordability_verdict(_v3_total_cost(),
		float(_v3_forecast.get("cash_needed", 0.0)), MatchState.money)
	var text := "Affordable"
	var tone := GREEN
	match verdict:
		"buffer_short":
			text = "Buffer not covered"
			tone = GOLD
		"unaffordable":
			text = "Can't afford"
			tone = RED
	var chip := PanelContainer.new()
	chip.name = "V3AffordChip"
	chip.add_theme_stylebox_override("panel", _panel_style(NAVY_FIELD, tone, 1, 7, 5))
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.tooltip_text = "Against current cash of %s: green covers the build and the buffer, amber covers the build only, red covers neither." % _money(MatchState.money)
	chip.mouse_filter = Control.MOUSE_FILTER_PASS
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", tone)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(label)
	return chip


## Band 3 — requirements as a compact checklist (§3): passes collapse to one line
## with no callout box, failures expand in a red-bordered row that states the fix.
## Land is a requirement row here, not a checkbox (§7) — the purchase it includes
## is itemised in the verdict total.
func _v3_requirement_rows() -> Array:
	var rows: Array = []
	var locked := _locked_tile_id != ""
	for need in _site_requirement_needs():
		var infra_key := str(need.get("infra_key", ""))
		var infra_name := _infra_connection_name(infra_key)
		var goods := _good_name_list(need.get("good_ids", []))
		var is_output := bool(need.get("is_output", false))
		if not locked:
			rows.append(_v3_req_line("•", _muted_tone(),
				"%s — needed for %s; make sure one reaches the site you choose" % [infra_name, goods]))
		elif bool(need.get("satisfied", false)):
			rows.append(_v3_req_line("✓", GREEN,
				"%s — connected on this tile (%s)" % [infra_name, goods]))
		else:
			var fix := ("build one or its output of %s cannot be sold or shipped" % goods) \
				if is_output else ("build one or its supply of %s cannot arrive" % goods)
			rows.append(_v3_req_fail("%s — none on this tile; %s." % [infra_name, fix]))
	rows.append(_v3_land_requirement_row())
	# Intermittent power stays an amber attention row — marginal, not a failure.
	if str(_selected_building.get("internal_name", "")) in EconomyConfig.POWER_INTERMITTENT_BUILDINGS:
		rows.append(_intermittent_power_row())
	return rows


func _v3_req_line(mark: String, mark_tone: Color, text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	var mark_label := Label.new()
	mark_label.text = mark
	mark_label.custom_minimum_size = Vector2(14, 0)
	mark_label.add_theme_font_size_override("font_size", 12)
	mark_label.add_theme_color_override("font_color", mark_tone)
	row.add_child(mark_label)
	var text_label := Label.new()
	text_label.text = text
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_label.add_theme_font_size_override("font_size", 12)
	text_label.add_theme_color_override("font_color", TEXT)
	row.add_child(text_label)
	return row


func _v3_req_fail(text: String) -> Control:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", _panel_style(NAVY_FIELD, RED, 1, 9, 7))
	row.add_child(_v3_req_line("✗", RED, text))
	return row


func _v3_land_requirement_row() -> Control:
	var needed := int(_v3_land.get("needed", 0))
	if _locked_tile_id == "":
		return _v3_req_line("•", _muted_tone(),
			"Land — needs %d on the site you choose" % needed)
	var free := int(_v3_land.get("free", 0))
	if int(_v3_land.get("short", 0)) <= 0:
		return _v3_req_line("✓", GREEN, "Land — needs %d · %d free on this tile" % [needed, free])
	if not bool(_v3_land.get("purchasable", false)):
		if int(_v3_land.get("for_sale", 0)) <= 0:
			return _v3_req_fail("Land — needs %d, %d free, and no more is for sale on this tile." % [needed, free])
		return _v3_req_fail("Land — needs %d, %d free; only %d more can be bought here — still short."
			% [needed, free, int(_v3_land.get("units", 0))])
	# A real, reversible choice (v3.1, owner 2026-08-26: the toggle is back — the
	# shortfall CAN be covered by a purchase, so whether to make it is genuinely
	# the player's call, not an auto-included fact).
	return _v3_land_toggle_row(needed, free)


## The land-purchase toggle (v3.1): ticked by default, so leaving it alone
## behaves exactly like the old auto-include. Unticking is a deliberate
## "build without this room" choice — it blocks Confirm with a stated reason,
## the same as any other requirement failure, never a silent dead end.
func _v3_land_toggle_row(needed: int, free: int) -> Control:
	var lots := "" if MatchState.LAND_PATCH_SIZE <= 1 else " (sold in lots of %d)" % MatchState.LAND_PATCH_SIZE
	var outer := PanelContainer.new()
	outer.add_theme_stylebox_override("panel",
		_panel_style(NAVY_FIELD, GOLD if _buy_land_wanted else RED, 1, 9, 7))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	outer.add_child(box)

	var toggle := Button.new()
	toggle.name = "V3LandToggle"
	toggle.toggle_mode = true
	toggle.button_pressed = _buy_land_wanted
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.custom_minimum_size = Vector2(0, 22)
	var clear := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		toggle.add_theme_stylebox_override(state, clear)
	box.add_child(toggle)
	var line := HBoxContainer.new()
	line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", 8)
	toggle.add_child(line)

	var glyph := PanelContainer.new()
	glyph.custom_minimum_size = Vector2(16, 16)
	glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var glyph_style := StyleBoxFlat.new()
	glyph_style.bg_color = GOLD if _buy_land_wanted else NAVY_FIELD
	glyph_style.border_color = GOLD_DARK if _buy_land_wanted else NAVY_LINE
	glyph_style.set_border_width_all(1)
	glyph_style.set_corner_radius_all(4)
	glyph.add_theme_stylebox_override("panel", glyph_style)
	line.add_child(glyph)
	if _buy_land_wanted:
		var check := Label.new()
		check.text = "✓"
		check.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		check.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		check.add_theme_font_size_override("font_size", 11)
		check.add_theme_color_override("font_color", NAVY)
		check.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		glyph.add_child(check)

	var label := Label.new()
	label.text = "Buy %d land on this tile · %s%s" % [
		int(_v3_land.get("units", 0)), _money(float(_v3_land.get("cost", 0.0))), lots]
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", TEXT)
	line.add_child(label)
	toggle.toggled.connect(_on_v3_land_toggled)

	var note := Label.new()
	note.text = ("Needs %d land · %d free on this tile." % [needed, free]) if _buy_land_wanted \
		else "Short %d land — this build will be refused until you tick this or free up room." % (needed - free)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 11)
	note.add_theme_color_override("font_color", TEXT if _buy_land_wanted else RED)
	box.add_child(note)
	return outer


func _on_v3_land_toggled(pressed: bool) -> void:
	_buy_land_wanted = pressed
	_land_toggle_touched = true
	_render()


## The land facts for this confirm, and the purchase V3 folds into it when the
## toggle is on. `_land_purchase_units`/`_land_purchase_cost` always hold what a
## full purchase of the shortfall WOULD cost (so the toggle row and a re-tick
## always show live numbers); `_buy_land_wanted` — preserved across re-renders
## once the player has touched it (_land_toggle_touched) — decides whether that
## cost actually applies. `covered` reflects the CURRENT toggle state, so the
## requirement row, the confirm-block reason and the affordability chip all agree.
func _v3_compute_land() -> Dictionary:
	var needed := int(round(maxf(0.0, float(_selected_building.get("tile_size_used", 1)))))
	var out := {"needed": needed, "free": 0, "short": 0, "units": 0, "cost": 0.0,
		"for_sale": 0, "purchasable": false, "covered": true}
	_land_purchase_units = 0
	_land_purchase_cost = 0.0
	if _locked_tile_id == "":
		_buy_land_wanted = false
		return out
	var owned := MatchState.get_tile_land_owned(_locked_tile_id)
	var used := int(round(MatchState.get_tile_player_space_used(_locked_tile_id)))
	var free := maxi(0, owned - used)
	out.free = free
	if free >= needed:
		_buy_land_wanted = false
		return out
	var short := needed - free
	out.short = short
	out.covered = false
	var for_sale := MatchState.get_tile_land_patches_available(_locked_tile_id)
	out.for_sale = for_sale
	if for_sale <= 0:
		_buy_land_wanted = false
		return out
	var patches := mini(int(ceil(float(short) / float(MatchState.LAND_PATCH_SIZE))), for_sale)
	var units := patches * MatchState.LAND_PATCH_SIZE
	var cost := MatchState.purchase_cost_after_advisor(
		float(patches) * MatchState.LAND_PATCH_COST, {"tile_id": _locked_tile_id})
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


## Band 4 — the money story as a flowing timeline, not a table (§4): each phase is
## turn-range · name · £/turn, chained left to right. "Making, not yet paid" reads
## as "First production run" here.
func _v3_cash_timeline() -> Control:
	var plate := PanelContainer.new()
	plate.add_theme_stylebox_override("panel", _panel_style(NAVY_FIELD, NAVY_FIELD, 0, 9, 8))
	var flow := HBoxContainer.new()
	flow.alignment = BoxContainer.ALIGNMENT_CENTER
	flow.add_theme_constant_override("separation", 5)
	plate.add_child(flow)
	var phases: Array = _v3_forecast.get("phases", [])
	for i in phases.size():
		var phase: Dictionary = phases[i]
		if i > 0:
			var arrow := Label.new()
			arrow.text = "→"
			arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			arrow.add_theme_font_size_override("font_size", 13)
			arrow.add_theme_color_override("font_color", _muted_tone())
			flow.add_child(arrow)
		var cell := VBoxContainer.new()
		cell.alignment = BoxContainer.ALIGNMENT_CENTER
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_theme_constant_override("separation", 1)
		flow.add_child(cell)
		var turns := int(phase.get("turns", 0))
		var marker := Label.new()
		marker.text = str(phase.get("range", "")) + ("  ·  %d turns" % turns if turns > 1 else "")
		marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		marker.add_theme_font_size_override("font_size", 10)
		marker.add_theme_color_override("font_color", _muted_tone())
		cell.add_child(marker)
		var name := Label.new()
		name.text = str(V3_PHASE_LABELS.get(str(phase.get("kind", "")), str(phase.get("label", ""))))
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name.add_theme_font_size_override("font_size", 11)
		name.add_theme_color_override("font_color", TEXT)
		cell.add_child(name)
		var per_turn := float(phase.get("per_turn", 0.0))
		var money := Label.new()
		money.text = _signed_money(per_turn) + ("/turn" if str(phase.get("kind", "")) == "selling" else "")
		money.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		money.theme_type_variation = "Numeric"
		money.add_theme_font_size_override("font_size", 14)
		if str(phase.get("kind", "")) == "building":
			money.add_theme_color_override("font_color", _muted_tone())
		else:
			money.add_theme_color_override("font_color", GREEN if per_turn >= 0.0 else RED)
		cell.add_child(money)
	return plate


const V3_MAT_ICON_SIZE := 60
const V3_MAT_COL_ONTILE := 58
const V3_MAT_COL_ELSEWHERE := 70
const V3_MAT_COL_MARKET := 92

## Band 5 — the bill of materials as a table (v3.1, from the V4 iteration): icon ·
## name · on tile · elsewhere · market price, header row first. "Elsewhere" is
## uncommitted surplus on every OTHER tile (Construction.network_surplus_for_good)
## — informational regardless of the active material-sourcing setting. Shortfall
## lines take the red border and a note beneath; everything else is boxless. The
## subtotal below reconciles to the verdict's construction figure because both
## read _v3_ledger's market_cost — market_price here is a display-only estimate,
## never summed.
func _v3_material_rows() -> Array:
	var entries: Array = _v3_ledger.get("rows", [])
	if entries.is_empty():
		var none := Label.new()
		none.text = "No material kit required"
		none.add_theme_font_size_override("font_size", 12)
		none.add_theme_color_override("font_color", _muted_tone())
		return [none]
	var rows: Array = [_v3_material_header()]
	for entry in entries:
		rows.append(_v3_material_row(entry))
	return rows


func _v3_material_header() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var lead := Label.new()   # header for the icon column — centred over it (owner 2026-08-26)
	lead.text = "GOOD"
	lead.custom_minimum_size = Vector2(V3_MAT_ICON_SIZE, 0)
	lead.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lead.add_theme_font_size_override("font_size", 9)
	lead.add_theme_color_override("font_color", _muted_tone())
	row.add_child(lead)
	for col in [
		{"text": "ON TILE", "width": V3_MAT_COL_ONTILE, "tip": ""},
		{"text": "ELSEWHERE", "width": V3_MAT_COL_ELSEWHERE,
			"tip": "Uncommitted surplus on your other tiles — what an \"any tile with surplus\" source could actually draw on."},
		{"text": "MARKET PRICE", "width": V3_MAT_COL_MARKET,
			"tip": "Reference estimate to buy the full amount needed at today's price. What this build actually pays is the materials subtotal below."},
	]:
		var head := Label.new()
		head.text = str(col.text)
		head.custom_minimum_size = Vector2(int(col.width), 0)
		head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		head.add_theme_font_size_override("font_size", 9)
		head.add_theme_color_override("font_color", _muted_tone())
		if str(col.tip) != "":
			head.tooltip_text = str(col.tip)
			head.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(head)
	return row


func _v3_material_row(entry: Dictionary) -> Control:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	# 60px icon (owner 2026-08-26: more visible), name dropped from the row and
	# moved to a hover tooltip on the icon instead — _good_icon returns its
	# holder with mouse_filter IGNORE (so it never blocks clicks elsewhere);
	# PASS is needed here so the tooltip actually fires.
	var icon := _good_icon(str(entry.get("good_id", "")), V3_MAT_ICON_SIZE, -1, int(entry.get("need", 0)))
	icon.tooltip_text = str(entry.get("name", ""))
	icon.mouse_filter = Control.MOUSE_FILTER_PASS
	line.add_child(icon)
	line.add_child(_v3_mat_figure(int(entry.get("have", 0)), V3_MAT_COL_ONTILE))
	line.add_child(_v3_mat_figure(int(entry.get("elsewhere", 0)), V3_MAT_COL_ELSEWHERE))
	var market := Label.new()
	market.text = "~%s" % _money(float(entry.get("market_price", 0.0)))
	market.custom_minimum_size = Vector2(V3_MAT_COL_MARKET, 0)
	market.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	market.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	market.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	market.theme_type_variation = "Numeric"
	market.add_theme_font_size_override("font_size", 12)
	market.add_theme_color_override("font_color", _muted_tone())
	line.add_child(market)

	var short := int(entry.get("short", 0))
	if short <= 0:
		return line
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 2)
	var boxed := PanelContainer.new()
	boxed.add_theme_stylebox_override("panel", _panel_style(NAVY_FIELD, RED, 1, 9, 6))
	boxed.add_child(line)
	wrap.add_child(boxed)
	var short_note := Label.new()
	short_note.text = "short ×%d — this site must hold every material before building" % short
	short_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	short_note.add_theme_font_size_override("font_size", 10)
	short_note.add_theme_color_override("font_color", RED)
	wrap.add_child(short_note)
	return wrap


func _v3_mat_figure(qty: int, col_width: int) -> Label:
	var label := Label.new()
	label.text = str(qty)
	label.custom_minimum_size = Vector2(col_width, 0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.theme_type_variation = "Numeric"
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", TEXT if qty > 0 else _muted_tone())
	return label


## Materials subtotal, the flat cash fee (base_price — what construction costs
## regardless of the kit), and a Total that reconciles to the verdict strip's
## construction figure (owner 2026-08-26): the materials band is now
## self-contained — it explains its own total instead of leaving the player to
## do (construction total) − (materials subtotal) = "what's the rest?" in their head.
func _v3_materials_totals() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	box.add_child(_v3_totals_row("Materials subtotal", float(_v3_ledger.get("subtotal", 0.0)),
		"V3MaterialsSubtotal", false))
	box.add_child(_v3_totals_row("Cash fee", maxf(0.0, float(_selected_building.get("base_price", 0.0))),
		"", false))
	box.add_child(DS.section_rule())
	box.add_child(_v3_totals_row("Total", _v3_construction_cost(), "V3MaterialsTotal", true))
	return box


func _v3_totals_row(label_text: String, amount: float, node_name: String, emphasize: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_font_size_override("font_size", 14 if emphasize else 11)
	label.add_theme_color_override("font_color", TEXT if emphasize else _muted_tone())
	row.add_child(label)
	var value := Label.new()
	if node_name != "":
		value.name = node_name
	value.text = _money(amount)
	value.theme_type_variation = "Numeric"
	value.add_theme_font_size_override("font_size", 16 if emphasize else 13)
	value.add_theme_color_override("font_color", TEXT)
	row.add_child(value)
	return row


## Priority-supply preview (v3.1 stub, owner 2026-08-26): "stub the control, no
## sim wiring". Shown only for buildings in EconomyConfig.POWER_INTERMITTENT_
## BUILDINGS. _v3_priority_supply is panel-local state ONLY — BuildForecast and
## Production never read it. Every intermittent building is still priced (and
## will run) as fully grid-sold; the copy says so, so the preview can't mislead.
func _v3_priority_supply_band() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var seg_panel := PanelContainer.new()
	seg_panel.add_theme_stylebox_override("panel", _panel_style(NAVY_FIELD, NAVY_LINE, 1, 9, 3))
	box.add_child(seg_panel)
	var seg := HBoxContainer.new()
	seg.add_theme_constant_override("separation", 4)
	seg_panel.add_child(seg)
	for option in [["grid", "Grid"], ["buildings", "Your buildings"]]:
		var opt_id := str(option[0])
		var on := _v3_priority_supply == opt_id
		var btn := Button.new()
		btn.text = str(option[1])
		btn.toggle_mode = true
		btn.button_pressed = on
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(0, 30)
		btn.add_theme_font_size_override("font_size", 12)
		_style_button(btn, GOLD if on else NAVY_FIELD, GOLD_DARK if on else NAVY_LINE,
			NAVY if on else _muted_tone())
		btn.pressed.connect(_on_v3_priority_supply_selected.bind(opt_id))
		seg.add_child(btn)
	var note := Label.new()
	note.text = ("All output sells to the grid at spot price each turn — steady, unaffected by intermittency."
			if _v3_priority_supply == "grid"
			else "Preview only — production still sells every unit to the grid today; local-first routing isn't wired up yet.")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 11)
	note.add_theme_color_override("font_color", _muted_tone())
	box.add_child(note)
	return box


func _on_v3_priority_supply_selected(option_id: String) -> void:
	_v3_priority_supply = option_id
	_render()


## Sticky footer (v3.1, from the V4 iteration): "Cash after" replaces a second
## restatement of the grand total — the verdict strip already shows the spend, so
## the footer answers the next question, what's left. Confirm keeps a reason line
## under it when blocked (§7) rather than folding the reason into the button
## label: the one line has to cover land, materials AND funds, which a short
## button caption can't hold uniformly the way V4's two-case version could.
func _v3_build_footer() -> void:
	_footer_panel.visible = true
	_footer_rule.visible = true
	var cash_box := VBoxContainer.new()
	cash_box.custom_minimum_size = Vector2(112, 0)
	cash_box.add_theme_constant_override("separation", 1)
	_footer.add_child(cash_box)
	var cash_caption := Label.new()
	cash_caption.text = "CASH AFTER"
	cash_caption.add_theme_font_size_override("font_size", 10)
	cash_caption.add_theme_color_override("font_color", _muted_tone())
	cash_box.add_child(cash_caption)
	var total := Label.new()
	total.name = "BuildCostValue"   # tutorial spotlight target, same as V2
	_confirm_total_label = total
	var total_cost := _v3_total_cost()
	var after := MatchState.money - total_cost
	var affordable := after >= -0.0001
	var below_buffer := affordable and after < float(_v3_forecast.get("cash_needed", 0.0))
	total.text = _money(after)
	total.theme_type_variation = "Numeric"
	total.add_theme_font_size_override("font_size", 16)
	total.add_theme_color_override("font_color", RED if not affordable else (GOLD if below_buffer else TEXT))
	cash_box.add_child(total)
	if below_buffer:
		var below := Label.new()
		below.text = "below buffer"
		below.add_theme_font_size_override("font_size", 9)
		below.add_theme_color_override("font_color", GOLD)
		cash_box.add_child(below)
	var cta_box := VBoxContainer.new()
	cta_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cta_box.add_theme_constant_override("separation", 2)
	_footer.add_child(cta_box)
	var confirm := Button.new()
	confirm.name = "BuildConfirmButton"   # tutorial spotlight target
	confirm.text = "Confirm" if _locked_tile_id != "" else "Confirm · select tile"
	confirm.theme_type_variation = "Primary"
	confirm.focus_mode = Control.FOCUS_NONE
	confirm.pressed.connect(_on_confirm_pressed)
	cta_box.add_child(confirm)
	var reason := _v3_confirm_block_reason()
	if reason != "":
		confirm.disabled = true
		var why := Label.new()
		why.name = "V3ConfirmReason"
		why.text = reason
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		why.add_theme_font_size_override("font_size", 11)
		why.add_theme_color_override("font_color", RED)
		cta_box.add_child(why)


## The first fact that blocks this confirm, in words — or "" when nothing does.
## Order mirrors what the player can actually fix: land, then materials the site
## must hold, then money.
func _v3_confirm_block_reason() -> String:
	if _locked_tile_id != "" and not bool(_v3_land.get("covered", true)):
		if bool(_v3_land.get("purchasable", false)):
			return "Short %d land — tick \"Buy land\" above, or choose a tile with more room." \
				% (int(_v3_land.get("needed", 0)) - int(_v3_land.get("free", 0)))
		return "Not enough land — needs %d, %d free, and what's for sale here doesn't cover it." \
			% [int(_v3_land.get("needed", 0)), int(_v3_land.get("free", 0))]
	var shorts := PackedStringArray()
	for entry in _v3_ledger.get("rows", []):
		if int((entry as Dictionary).get("short", 0)) > 0:
			shorts.append("×%d %s" % [int((entry as Dictionary).get("short", 0)),
				str((entry as Dictionary).get("name", ""))])
	if not shorts.is_empty():
		return "Short %s — this site must hold every material before building." % ", ".join(shorts)
	var total := _v3_total_cost()
	if MatchState.money + 0.0001 < total:
		return "Insufficient funds — need %s, have %s." % [_money(total), _money(MatchState.money)]
	return ""


## V3 construction figure: the money leg plus the materials-ledger subtotal — what
## this confirm actually spends on the build, with on-site stock already free. The
## V2 display cost prices the full kit at retail regardless of stock, which
## overstates a build on a stocked tile.
func _v3_construction_cost() -> float:
	return maxf(0.0, float(_selected_building.get("base_price", 0.0))) \
		+ float(_v3_ledger.get("subtotal", 0.0))


func _v3_total_cost() -> float:
	return _v3_construction_cost() + (_land_purchase_cost if _buy_land_wanted else 0.0)


func _signed_money(value: float) -> String:
	if is_zero_approx(value):
		return "£0"
	return "%s£%s" % ["+" if value > 0.0 else "−", _format_number(absf(value))]


## Live-recompute tick (§7): when a re-render lands a different grand total, the
## verdict number flashes warm for a beat so the change is noticed, not silent.
func _v3_pulse_if_changed(new_total: float) -> void:
	var changed := _v3_last_total >= 0.0 and absf(new_total - _v3_last_total) > 0.005
	_v3_last_total = new_total
	if not changed or _v3_verdict_total_label == null:
		return
	var label := _v3_verdict_total_label
	label.modulate = Color(1.0, 0.82, 0.45)
	var tween := label.create_tween()
	tween.tween_property(label, "modulate", Color.WHITE, 0.45).set_trans(Tween.TRANS_SINE)


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
		none.add_theme_color_override("font_color", _muted_tone())
		grid.add_child(none)
	return box


## Land, immediately above Confirm. On a tile that has room this is one quiet line. On a
## tile that does not, it becomes a TICKBOX with the purchase price on it, ticked already,
## because buying the land is what the player is going to have to do and the alternative is
## a build that gets refused. Untick to be refused deliberately rather than by surprise.
func _land_row(building: Dictionary) -> Control:
	var needed := int(round(maxf(0.0, float(building.get("tile_size_used", 1)))))
	if _locked_tile_id == "":
		_land_purchase_units = 0
		_land_purchase_cost = 0.0
		return _land_required_row(building)
	var owned := MatchState.get_tile_land_owned(_locked_tile_id)
	var used := int(round(MatchState.get_tile_player_space_used(_locked_tile_id)))
	var free := maxi(0, owned - used)
	if free >= needed:
		_land_purchase_units = 0
		_land_purchase_cost = 0.0
		return _land_required_row(building)

	# Land is sold in whole patches, so round the shortfall up to one.
	var short := needed - free
	var patches := int(ceil(float(short) / float(MatchState.LAND_PATCH_SIZE)))
	var for_sale := MatchState.get_tile_land_patches_available(_locked_tile_id)
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", _panel_style(NAVY_FIELD, GOLD_DARK, 1, 9, 8))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	row.add_child(box)

	if for_sale <= 0:
		# Nothing left to buy on this tile — the NPC buildings hold the rest of it.
		_land_purchase_units = 0
		_land_purchase_cost = 0.0
		var none := Label.new()
		none.text = ("Needs %d land · %d free on %s · no more land for sale here"
			% [needed, free, Catalog.tile_label(_locked_tile_id)])
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		none.add_theme_font_size_override("font_size", 12)
		none.add_theme_color_override("font_color", GOLD)
		box.add_child(none)
		return row

	patches = mini(patches, for_sale)
	_land_purchase_units = patches * MatchState.LAND_PATCH_SIZE
	_land_purchase_cost = MatchState.purchase_cost_after_advisor(
		float(patches) * MatchState.LAND_PATCH_COST, {"tile_id": _locked_tile_id})

	var check := CheckBox.new()
	check.text = "Buy %d land on %s  ·  %s" % [
		_land_purchase_units, Catalog.tile_label(_locked_tile_id), _money(_land_purchase_cost)]
	check.button_pressed = true      # ticked already: without it the build is refused
	check.focus_mode = Control.FOCUS_NONE
	check.add_theme_font_size_override("font_size", 13)
	check.add_theme_color_override("font_color", TEXT)
	check.toggled.connect(_on_buy_land_toggled)
	_buy_land_checkbox = check
	_buy_land_wanted = true
	box.add_child(check)

	var detail := Label.new()
	detail.text = "Needs %d land · %d free on this tile" % [needed, free]
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_theme_font_size_override("font_size", 11)
	detail.add_theme_color_override("font_color", _muted_tone())
	box.add_child(detail)
	return row

func _on_buy_land_toggled(pressed: bool) -> void:
	_buy_land_wanted = pressed
	_refresh_confirm_total()

## "Land required: N" under the material kit. When the flow is locked to a tile the line
## also reports what is actually free there, and says whether auto-buy will cover the gap —
## running out of land mid-build was the single most confusing dead end in playtesting.
func _land_required_row(building: Dictionary) -> Control:
	var needed := int(round(maxf(0.0, float(building.get("tile_size_used", 1)))))
	var text := "Land required: %d" % needed
	var tint := _muted_tone()
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
	# The intermittency warning is not about the RECIPE, it is about the building, so it comes
	# before the early return: solar and wind carry it whichever recipe is selected.
	if str(_selected_building.get("internal_name", "")) in EconomyConfig.POWER_INTERMITTENT_BUILDINGS:
		rows.append(_intermittent_power_row())
	for need in _site_requirement_needs():
		rows.append(_infra_requirement_row(str(need.get("infra_key", "")),
			need.get("good_ids", []), bool(need.get("is_output", false))))
	return rows


## The routing facts the confirm screen judges, as data: one entry per
## infrastructure connection the recipe needs ({infra_key, good_ids, is_output,
## satisfied}). `satisfied` is only meaningful with a locked tile — without one
## the site is unknown and every entry is a requirement, not a verdict. Shared by
## the V2 rows and the V3 checklist so the two screens can never disagree.
func _site_requirement_needs() -> Array:
	var needs_list: Array = []
	if _selected_recipe.is_empty():
		return needs_list   # infrastructure builds have no recipe, so no supply to route
	var input_needs := _infra_needs_for(_selected_recipe.get("inputs", []))
	if int(_selected_recipe.get("energy_req", 0)) > 0:
		_add_infra_need(input_needs, "cables",
			str(Catalog.get_good_by_internal_name("power").get("id", "")))
	for infra_key in INFRA_ROW_ORDER:
		if input_needs.has(infra_key):
			needs_list.append({"infra_key": infra_key, "good_ids": input_needs[infra_key],
				"is_output": false, "satisfied": _infra_satisfied(infra_key)})
	if _locked_tile_id != "":
		var output_needs := _infra_needs_for(_selected_recipe.get("outputs", []))
		for infra_key in INFRA_ROW_ORDER:
			if output_needs.has(infra_key):
				needs_list.append({"infra_key": infra_key, "good_ids": output_needs[infra_key],
					"is_output": true, "satisfied": _infra_satisfied(infra_key)})
	return needs_list


func _infra_satisfied(infra_key: String) -> bool:
	return _locked_tile_id != "" and Catalog.tile_has_infrastructure(_locked_tile_id, infra_key)


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


## Solar and wind make power the grid cannot lean on: a recipe running on UNFIRMED intermittent
## green is derated (EconomyConfig.INTERMITTENCY_DERATE), so the player who builds one and walks
## away is quietly paid less than the nameplate suggests. That is a property of the BUILDING, not
## of a tile or a recipe, so unlike the routing rows it is never "satisfied" and never turns
## green — it names the fix instead. Membership comes from EconomyConfig, the same list the
## production code derates on, so a fourth renewable is covered without editing this file.
func _intermittent_power_row() -> PanelContainer:
	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(0, INFRA_ROW_HEIGHT)
	row.add_theme_stylebox_override("panel", _panel_style(NAVY_FIELD, GOLD, 1, 9, 6))
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	row.add_child(body)
	# The battery is the remedy, and the routing rows already set the precedent that the icon
	# shows what to build rather than what is being built.
	body.add_child(_building_icon(Catalog.get_building_by_internal_name("battery"), INFRA_ROW_ICON))

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
	text.text = "This building produces intermittent power. Stabilise it with [b]battery storage[/b] to avoid reducing output."
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


## Secondary-label tone. V3 raises it one step (spec §6): the local grey reads as
## grey-on-grey on the panel navies at the 10–14 px this panel actually uses —
## the pattern the standing contrast rule in CLAUDE.md forbids. DS.TEXT_MUTED is
## the blessed quiet tone; V2 keeps its original grey untouched.
func _muted_tone() -> Color:
	return DS.PALETTE.TEXT_MUTED if MatchState.use_construct_panel_v3 else MUTED


func _section_label(text: String, double_rule: bool = false) -> Control:
	# V3 (spec §4): fine ruled lines replace the gold tick-bar — ledger grammar,
	# no status colour spent on furniture. double_rule marks the verdict band.
	if MatchState.use_construct_panel_v3:
		return DS.ruled_section_head(text, double_rule)
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
	# V3 drops the darker keyline around the cream plate — the plate reads as one
	# clean pedestal instead of an outlined chip.
	if not MatchState.use_construct_panel_v3:
		plate_style.border_color = CREAM_SHADOW
		plate_style.set_border_width_all(2)
	plate_style.set_corner_radius_all(maxi(7, int(round(float(icon_size) * 0.16))))
	plate.add_theme_stylebox_override("panel", plate_style)
	holder.add_child(plate)
	var art := TextureRect.new()
	art.texture = GoodIcons.texture_for(good_id, Catalog.get_internal_name(good_id))
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
	card.name = "RecipeDiagramCard"   # test/tutorial spotlight handle
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
	art.texture = GoodIcons.texture_for_size(good_id, Catalog.get_internal_name(good_id), float(size_px))
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
	# Same V3 keyline removal as _good_icon — the power plate is the same pedestal.
	if not MatchState.use_construct_panel_v3:
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
		name.add_theme_color_override("font_color", _muted_tone())
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
	caption.add_theme_color_override("font_color", _muted_tone())
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
	_v3_last_total = -1.0   # a fresh confirm never pulses its opening total
	_land_toggle_touched = false
	_v3_priority_supply = "grid"
	_render()


func _on_unaffordable_recipe_pressed(building_id: String) -> void:
	_show_insufficient_funds(building_id)


## What the Confirm button is about to spend: the build, plus the land if the player left
## the box ticked. The footer used to show the build alone, which understated a confirm that
## was about to buy land as well. On the V3 confirm the ledger-based total is the truth
## (on-site stock already free, land always itemised in).
func _confirm_total_cost() -> float:
	if _v3_confirm_live() and not _v3_ledger.is_empty():
		return _v3_total_cost()
	var cost := _construction_display_cost(str(_selected_building.get("id", "")))
	if _buy_land_wanted:
		cost += _land_purchase_cost
	return cost

func _refresh_confirm_total() -> void:
	if _confirm_total_label != null and is_instance_valid(_confirm_total_label):
		_confirm_total_label.text = _money(_confirm_total_cost())

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
	_confirm_flash_pending = true
	_render()


func _on_back_to_browse() -> void:
	_view = View.BROWSE
	_selected_building = {}
	_selected_recipe = {}
	_v3_last_total = -1.0
	_v3_verdict_total_label = null
	_land_toggle_touched = false
	_v3_priority_supply = "grid"
	_render()


func _on_confirm_pressed() -> void:
	var building_id := str(_selected_building.get("id", ""))
	if building_id == "":
		return
	if _v3_confirm_live():
		# The V3 footer already disables Confirm with the reason on screen; this is
		# the belt-and-braces re-check against the same ledger-based facts, not the
		# V2 retail-priced estimate (which overstates a build on a stocked tile).
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
		if MatchState.use_construct_panel_v3:
			# V3: one intent. The land shortfall is bought inside the build attempt's own
			# space gate (world_map._space_check_for_build via BuildMode.attempt_buy_land),
			# so a build refused upstream of that gate can no longer leave the player
			# owning land they bought for nothing.
			if not BuildMode.attempt_direct_build(building_id,
					str(_selected_recipe.get("recipe_id", "")), _locked_tile_id,
					_buy_land_wanted and _land_purchase_units > 0):
				# Refused — the map has already said why; keep the selection on screen.
				return
		else:
			# Buy the land FIRST, or the build is refused for the room it was about to have.
			if _buy_land_wanted and _land_purchase_units > 0:
				var patches := int(ceil(float(_land_purchase_units) / float(MatchState.LAND_PATCH_SIZE)))
				if not MatchState.purchase_tile_land(_locked_tile_id, patches):
					MatchState.request_toast(
						"Could not buy the land on %s — the build needs it first."
							% Catalog.tile_label(_locked_tile_id), "warning")
					return
			if not BuildMode.attempt_direct_build(building_id,
					str(_selected_recipe.get("recipe_id", "")), _locked_tile_id):
				# Refused — no land, no room, sea. The map has already said which, so stay exactly
				# as we are: the building, the recipe and the tile are all still chosen, and the
				# player can buy the land or pick another tile without starting the selection over.
				return
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
