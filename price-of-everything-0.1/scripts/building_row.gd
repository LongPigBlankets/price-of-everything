extends VBoxContainer

signal build_requested(building_id: String)
signal recipe_selected(building_id: String, recipe_id: String)
signal expand_toggled(building_id: String, is_expanded: bool)

const RecipeRowScene: PackedScene = preload("res://scenes/recipe_row.tscn")

@onready var icon_label: Label = $MainRow/IconLabel
@onready var name_label: Label = $MainRow/NameLabel
@onready var cost_label: Label = $MainRow/CostLabel
@onready var materials_container: HBoxContainer = $MainRow/MaterialsContainer
@onready var build_button: Button = $MainRow/BuildButton
@onready var expand_button: Button = $MainRow/ExpandButton
@onready var recipes_container: VBoxContainer = $RecipesContainer

var building_id: String = ""
var is_expanded: bool = false
var recipes_for_this_building: Array = []

func setup(data: Dictionary, recipes: Array) -> void:
	building_id = data.get("id", "")
	icon_label.text = data.get("icon", "•")
	name_label.text = data.get("name", "")
	cost_label.text = "£%s" % data.get("cost", "0")
	recipes_for_this_building = recipes
	
	# Clear and populate material costs
	for child in materials_container.get_children():
		child.queue_free()
	
	var materials: Array = data.get("materials", [])
	for mat in materials:
		var mat_label := Label.new()
		var mat_name: String = mat.get("name", "")
		var mat_qty: int = mat.get("qty", 0)
		mat_label.text = "%s +%d" % [mat_name.substr(0, 3).to_upper(), mat_qty]
		materials_container.add_child(mat_label)
	
	build_button.text = "+"
	expand_button.text = "^"
	
	# Hide expand button if 0 or 1 recipes (nothing to expand to)
	if recipes_for_this_building.size() <= 1:
		expand_button.visible = false
	
	# Recipes container starts hidden
	recipes_container.visible = false
	
	build_button.pressed.connect(_on_build_pressed)
	expand_button.pressed.connect(_on_expand_pressed)

func _on_build_pressed() -> void:
	# Auto-select if only one recipe
	if recipes_for_this_building.size() == 1:
		var only_recipe: Dictionary = recipes_for_this_building[0]
		recipe_selected.emit(building_id, only_recipe.recipe_id)
		return
	
	# Multiple recipes: toggle expansion
	if recipes_for_this_building.size() > 1 and not is_expanded:
		_set_expanded(true)
		return
	
	if is_expanded:
		_set_expanded(false)

func _on_expand_pressed() -> void:
	_set_expanded(not is_expanded)

func _set_expanded(expanded: bool) -> void:
	is_expanded = expanded
	expand_button.text = "v" if is_expanded else "^"
	
	if is_expanded:
		_populate_recipes_container()
		recipes_container.visible = true
	else:
		recipes_container.visible = false
		for child in recipes_container.get_children():
			child.queue_free()
	
	expand_toggled.emit(building_id, is_expanded)

func _populate_recipes_container() -> void:
	for child in recipes_container.get_children():
		child.queue_free()
	
	for recipe in recipes_for_this_building:
		var recipe_row := RecipeRowScene.instantiate()
		recipes_container.add_child(recipe_row)
		recipe_row.setup(recipe, building_id)
		recipe_row.recipe_selected.connect(_on_recipe_row_selected)

func _on_recipe_row_selected(b_id: String, r_id: String) -> void:
	recipe_selected.emit(b_id, r_id)
	_set_expanded(false)
