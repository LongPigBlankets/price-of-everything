extends VBoxContainer

signal build_requested(building_id: String)
signal recipe_selected(building_id: String, recipe_id: String)
signal infrastructure_build_pressed(infrastructure_id: String)
signal expand_toggled(building_id: String, is_expanded: bool)

const RecipeRowScene: PackedScene = preload("res://scenes/recipe_row.tscn")
const GoodIcons := preload("res://scripts/good_icons.gd")
const MAT_SLOT_SIZE := Vector2(50, 50)
const BADGE_DIAMETER := 24
const BADGE_TEXT_SIZE := 14
const BADGE_NAVY := Color(0.0, 0.119856, 0.243095, 1.0)
const BADGE_PAPER := Color(0.9725, 0.9333, 0.8431, 1.0)
const ROW_HOVER_TOOLTIP := "Click to build"
const ACTIVE_COLOR := Color(0.15, 0.48, 0.76, 0.72)
const UNAFFORDABLE_COLOR := Color(0.12, 0.12, 0.12, 0.28)
const UNAFFORDABLE_FLASH_COLOR := Color(0.7, 0.12, 0.08, 0.52)

@onready var main_row: HBoxContainer = $MainRow
@onready var icon_texture: TextureRect = $MainRow/IconTexture
@onready var name_label: Label = $MainRow/NameLabel
@onready var cost_label: Label = $MainRow/CostLabel
@onready var materials_container: HBoxContainer = $MainRow/MaterialsContainer
@onready var build_button: Button = $MainRow/BuildButton
@onready var expand_button: Button = $MainRow/ExpandButton
@onready var recipes_container: VBoxContainer = $RecipesContainer

var building_id: String = ""
var is_expanded: bool = false
var recipes_for_this_building: Array = []
var is_infrastructure: bool = false
var infrastructure_key: String = ""
var build_cost: float = 0.0
var is_affordable: bool = true
var _active_building_id: String = ""
var _active_recipe_id: String = ""
var _active_infrastructure_key: String = ""
var _unaffordable_flash := false

func setup(data: Dictionary, recipes: Array) -> void:
	building_id = data.get("id", "")
	is_infrastructure = data.get("category", "") == "infrastructure"
	infrastructure_key = data.get("internal_name", "")
	build_cost = float(data.get("base_price", data.get("cost", 0.0)))
	recipes_for_this_building = recipes

	mouse_filter = Control.MOUSE_FILTER_PASS
	main_row.mouse_filter = Control.MOUSE_FILTER_STOP
	main_row.tooltip_text = ROW_HOVER_TOOLTIP
	if not main_row.gui_input.is_connected(_on_main_row_gui_input):
		main_row.gui_input.connect(_on_main_row_gui_input)

	_load_icon(data)
	name_label.text = data.get("display_name", data.get("name", ""))
	cost_label.text = _money_text(build_cost)

	for child in materials_container.get_children():
		child.queue_free()

	var materials: Array = data.get("materials", [])
	for mat in materials:
		var mat_label := Label.new()
		var mat_name: String = mat.get("name", "")
		var mat_qty: int = mat.get("qty", 0)
		mat_label.text = "%s +%d" % [mat_name.substr(0, 3).to_upper(), mat_qty]
		materials_container.add_child(mat_label)

	# Build-material requirements as a 3x2 grid (good icon + qty pill badge, hatched
	# placeholder for empty slots) inside a white rectangle.
	materials_container.visible = false
	_build_material_grid(materials)

	build_button.visible = false
	expand_button.visible = false
	recipes_container.visible = false
	_update_visual_state()

func _load_icon(data: Dictionary) -> void:
	icon_texture.texture = null
	var icon_paths: Array = []
	var internal_name: String = data.get("internal_name", "")

	if building_id == "":
		return

	if internal_name != "":
		icon_paths.append("res://assets/icons/buildings/%s_%s.png" % [building_id, internal_name])
	icon_paths.append("res://assets/icons/buildings/%s.png" % building_id)

	for icon_path in icon_paths:
		if ResourceLoader.exists(icon_path):
			icon_texture.texture = load(icon_path)
			return

func _on_build_pressed() -> void:
	_on_row_pressed()

func _on_expand_pressed() -> void:
	_set_expanded(not is_expanded)

func _on_main_row_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_on_row_pressed()
		accept_event()

func _on_row_pressed() -> void:
	if is_infrastructure:
		if not is_affordable:
			_flash_unaffordable()
			return
		infrastructure_build_pressed.emit(building_id)
		return

	if recipes_for_this_building.size() == 1:
		if not is_affordable:
			_flash_unaffordable()
			return
		var only_recipe: Dictionary = recipes_for_this_building[0]
		recipe_selected.emit(building_id, only_recipe.recipe_id)
		return

	if recipes_for_this_building.size() > 1:
		_set_expanded(not is_expanded)

func _set_expanded(expanded: bool) -> void:
	is_expanded = expanded
	if is_expanded:
		_populate_recipes_container()
		recipes_container.visible = true
	else:
		recipes_container.visible = false
		for child in recipes_container.get_children():
			child.queue_free()

	expand_toggled.emit(building_id, is_expanded)
	queue_redraw()

func _populate_recipes_container() -> void:
	for child in recipes_container.get_children():
		child.queue_free()
	recipes_container.add_theme_constant_override("separation", 8)  # navy gaps between cards

	# Group recipes by recipe_type, preserving first-seen order. Only show the
	# type sub-headers when a building actually hosts more than one type.
	var groups: Dictionary = {}
	var order: Array = []
	for recipe in recipes_for_this_building:
		var rtype: String = recipe.get("recipe_type", "")
		if not groups.has(rtype):
			groups[rtype] = []
			order.append(rtype)
		groups[rtype].append(recipe)

	var show_headers: bool = order.size() > 1
	for rtype in order:
		if show_headers and rtype != "":
			var header := Label.new()
			header.text = rtype.to_upper().replace("_", " ")
			header.theme_type_variation = &"Caption"
			recipes_container.add_child(header)
		for recipe in groups[rtype]:
			var recipe_row := RecipeRowScene.instantiate()
			recipes_container.add_child(recipe_row)
			recipe_row.setup(recipe, building_id)
			recipe_row.set_affordable(is_affordable)
			recipe_row.set_selected(recipe.recipe_id == _active_recipe_id and building_id == _active_building_id)
			recipe_row.recipe_selected.connect(_on_recipe_row_selected)

func _on_recipe_row_selected(b_id: String, r_id: String) -> void:
	if not is_affordable:
		_flash_unaffordable()
		return
	recipe_selected.emit(b_id, r_id)
	_active_building_id = b_id
	_active_recipe_id = r_id
	_update_recipe_selection()
	_update_visual_state()

func set_affordable(value: bool, current_money: float = 0.0) -> void:
	is_affordable = value
	var price_text := _money_text(build_cost)
	var money_text := _money_text(current_money)
	tooltip_text = "" if is_affordable else "Needs %s. Current money: %s" % [price_text, money_text]
	main_row.tooltip_text = tooltip_text if tooltip_text != "" else ROW_HOVER_TOOLTIP
	_update_recipe_affordability()
	_update_visual_state()

func set_build_mode_selection(active_building_id: String, active_recipe_id: String, active_infrastructure_key: String = "") -> void:
	_active_building_id = active_building_id
	_active_recipe_id = active_recipe_id
	_active_infrastructure_key = active_infrastructure_key
	_update_recipe_selection()
	_update_visual_state()

func _update_recipe_selection() -> void:
	for child in recipes_container.get_children():
		if child.has_method("set_selected"):
			child.set_selected(child.recipe_id == _active_recipe_id and building_id == _active_building_id)

func _update_recipe_affordability() -> void:
	for child in recipes_container.get_children():
		if child.has_method("set_affordable"):
			child.set_affordable(is_affordable)

func _update_visual_state() -> void:
	var dim := 0.42 if not is_affordable else 1.0
	icon_texture.modulate = Color(1, 1, 1, dim)
	name_label.modulate = Color(1, 1, 1, dim)
	cost_label.modulate = Color(1.0, 0.45, 0.42, 1.0) if not is_affordable else Color(1, 1, 1, 1)
	materials_container.modulate = Color(1, 1, 1, dim)
	if _is_active_building() and not is_expanded and recipes_for_this_building.size() > 1:
		_set_expanded(true)
	queue_redraw()

func _is_active_building() -> bool:
	if is_infrastructure:
		return infrastructure_key != "" and infrastructure_key == _active_infrastructure_key
	return building_id != "" and building_id == _active_building_id

func _draw() -> void:
	if _unaffordable_flash:
		draw_rect(Rect2(Vector2.ZERO, size), UNAFFORDABLE_FLASH_COLOR, true)
	elif not is_affordable:
		draw_rect(Rect2(Vector2.ZERO, size), UNAFFORDABLE_COLOR, true)

func _flash_unaffordable() -> void:
	_unaffordable_flash = true
	queue_redraw()
	await get_tree().create_timer(0.14).timeout
	_unaffordable_flash = false
	queue_redraw()

func _money_text(value: float) -> String:
	var text := "%.2f" % value
	while text.ends_with("0"):
		text = text.trim_suffix("0")
	if text.ends_with("."):
		text = text.trim_suffix(".")
	return "\u00a3%s" % text

# A navy square with diagonal off-white hatching (placeholder build-material slot).
class HatchSquare extends Control:
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.015686275, 0.058823529, 0.105882353), true)
		var off := Color(0.995234, 0.930806, 0.763265, 0.55)
		var step := 7.0
		var x := -size.y
		while x < size.x:
			draw_line(Vector2(x, size.y), Vector2(x + size.y, 0.0), off, 1.5)
			x += step

func _build_material_grid(materials: Array) -> void:
	if has_node("MaterialGrid"):
		return
	var panel := PanelContainer.new()
	panel.name = "MaterialGrid"
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var white := StyleBoxFlat.new()
	white.bg_color = Color(0.995234, 0.930806, 0.763265)
	white.set_corner_radius_all(6)
	white.set_content_margin_all(6)
	panel.add_theme_stylebox_override("panel", white)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 5)
	panel.add_child(grid)
	for i in range(6):
		var mat: Dictionary = materials[i] if i < materials.size() else {}
		grid.add_child(_make_material_slot(mat))
	main_row.add_child(panel)
	main_row.move_child(panel, 2)  # name swapped left of the materials grid

func _make_material_slot(material: Dictionary) -> Control:
	var slot := Control.new()
	slot.custom_minimum_size = MAT_SLOT_SIZE
	var hatch := HatchSquare.new()
	hatch.set_anchors_preset(Control.PRESET_FULL_RECT)
	hatch.clip_contents = true
	hatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(hatch)
	if material.is_empty():
		return slot
	var good: Dictionary = Catalog.get_good_by_internal_name(material.get("name", ""))
	var tex: Texture2D = GoodIcons.texture_for(good.get("id", ""), material.get("name", ""))
	if tex != null:
		var icon := TextureRect.new()
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.texture = tex
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(icon)
	slot.add_child(_make_qty_badge(int(material.get("qty", 0))))
	return slot

# Quantity pill badge matching the build-details recipe cards.
func _make_qty_badge(qty: int) -> Control:
	var qty_text := str(qty)
	var h: int = BADGE_DIAMETER
	var w: int = h if qty_text.length() <= 1 else maxi(h, qty_text.length() * 9 + 14)
	var badge := PanelContainer.new()
	badge.custom_minimum_size = Vector2(w, h)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	var overlap: int = maxi(4, roundi(MAT_SLOT_SIZE.x * 0.10))
	badge.offset_left = -w + overlap
	badge.offset_top = -h + overlap
	badge.offset_right = overlap
	badge.offset_bottom = overlap
	var style := StyleBoxFlat.new()
	style.bg_color = BADGE_NAVY
	style.border_color = BADGE_PAPER
	style.set_border_width_all(2)
	style.set_corner_radius_all(int(h / 2.0))
	style.set_content_margin_all(0)
	badge.add_theme_stylebox_override("panel", style)
	var ls := LabelSettings.new()
	ls.font_color = BADGE_PAPER
	ls.font_size = BADGE_TEXT_SIZE
	var label := Label.new()
	label.text = qty_text
	label.custom_minimum_size = Vector2(w, h)
	label.label_settings = ls
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(label)
	return badge
