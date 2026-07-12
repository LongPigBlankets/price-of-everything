extends Node
## One-off regression probe for the `swap construct_panel` experiment.

func _ready() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	for _i in 8:
		await get_tree().process_frame

	MatchState.set_use_construct_panel_v2(true)
	var panel := get_tree().root.find_child("ConstructPanelV2", true, false)
	assert(panel != null, "V2 construct panel was not instantiated")
	panel.call("open_browser")
	await get_tree().process_frame
	var loaded_buildings: Array = panel.get("_buildings")
	var recipes_by_building: Dictionary = panel.get("_recipes_by_building")
	var disabled_building: Dictionary = {}
	var recipe_category := ""
	for building in loaded_buildings:
		var recipes: Array = recipes_by_building.get(str(building.get("id", "")), [])
		if recipes.is_empty() and disabled_building.is_empty():
			disabled_building = building
		if not recipes.is_empty() and recipe_category == "":
			recipe_category = str(recipes[0].get("recipe_type", ""))
	assert(not disabled_building.is_empty(), "Expected a visible building with no recipes")
	var disabled_card: Control = panel.call("_make_building_card", disabled_building)
	var disabled_header := disabled_card.get_child(0).get_child(0) as Button
	assert(disabled_header.disabled, "Buildings with no recipes must be disabled")
	assert(recipe_category != "", "Expected at least one recipe category")
	panel.call("_on_category_pressed", recipe_category)
	for building in panel.call("_filtered_buildings"):
		var matches := false
		for recipe in recipes_by_building.get(str(building.get("id", "")), []):
			matches = matches or str(recipe.get("recipe_type", "")) == recipe_category
		assert(matches, "Recipe-category filter included a building with no matching recipe")
	panel.call("_on_category_pressed", "all")

	var building_id := ""
	var recipe_id := ""
	for recipe in Catalog.all_recipes():
		var candidate := str(recipe.get("building_id", ""))
		if candidate != "" and not Catalog.get_building(candidate).is_empty():
			building_id = candidate
			recipe_id = str(recipe.get("recipe_id", ""))
			break
	assert(building_id != "" and recipe_id != "", "No constructible building/recipe fixture")

	panel.call("_on_building_pressed", building_id)
	panel.call("_on_recipe_pressed", building_id, recipe_id)
	await get_tree().process_frame
	assert(panel.visible, "Recipe selection should open the confirm screen")
	panel.call("_on_confirm_pressed")
	assert(BuildMode.is_active, "Confirmation should enter map placement mode")
	assert(BuildMode.current_building_id == building_id, "Confirmation selected the wrong building")
	assert(BuildMode.current_recipe_id == recipe_id, "Confirmation selected the wrong recipe")
	assert(not panel.visible, "Confirmation should close the V2 panel for map placement")
	print("construct_panel_v2 smoke: PASS")
	get_tree().quit(0)
