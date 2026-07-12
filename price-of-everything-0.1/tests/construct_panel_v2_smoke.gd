extends Node
## One-off regression probe for the `swap construct_panel` experiment.

func _ready() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	for _i in 8:
		await get_tree().process_frame

	assert(MatchState.use_construct_panel_v2, "Construct Panel V2 should be the default")
	var top_bar := get_tree().root.find_child("TopBar", true, false)
	assert(top_bar != null, "Top bar was not instantiated")
	top_bar.call("_open_fly", "treasury")
	await get_tree().process_frame
	var money_mini_panel := top_bar.get("_fly_panel") as PanelContainer
	assert(money_mini_panel != null and money_mini_panel.custom_minimum_size.x == 510.0,
		"Treasury money mini-panel uses the expanded two-column width")
	assert(is_equal_approx(money_mini_panel.size.y, money_mini_panel.get_combined_minimum_size().y),
		"Treasury money mini-panel fits its content instead of filling the viewport")
	assert(money_mini_panel.find_child("RevenueColumn", true, false) != null
		and money_mini_panel.find_child("CostsColumn", true, false) != null,
		"Treasury money mini-panel has Revenue and Costs columns")
	assert(money_mini_panel.find_child("FlyTakeLoanButton", true, false) != null
		and money_mini_panel.find_child("FlyBalanceButton", true, false) != null
		and money_mini_panel.find_child("FlyChartsButton", true, false) != null,
		"Treasury money mini-panel exposes loan, balance, and chart shortcuts")
	top_bar.call("_close_fly")
	var full_money_panel := get_tree().root.find_child("MoneyPanel", true, false) as PanelContainer
	var money_tabs := full_money_panel.get_node("MarginContainer/ModalLayout/TabContainer") as TabContainer
	for index in money_tabs.get_tab_count():
		var title := money_tabs.get_tab_title(index)
		if title in ["Stats", "Budget"]:
			assert(money_tabs.is_tab_hidden(index), "%s is not exposed in Money" % title)
	for target in [["FlyTakeLoanButton", "Loans"], ["FlyBalanceButton", "Balance"], ["FlyChartsButton", "Charts"]]:
		top_bar.call("_open_fly", "treasury")
		await get_tree().process_frame
		var action := (top_bar.get("_fly_panel") as PanelContainer).find_child(str(target[0]), true, false) as Button
		action.pressed.emit()
		await get_tree().process_frame
		assert(full_money_panel.visible and money_tabs.get_tab_title(money_tabs.current_tab) == str(target[1]),
			"Treasury %s shortcut opens the %s tab" % [target[0], target[1]])
		full_money_panel.hide()
	var panel := get_tree().root.find_child("ConstructPanelV2", true, false)
	assert(panel != null, "V2 construct panel was not instantiated")
	panel.call("open_browser")
	await get_tree().process_frame
	var loaded_buildings: Array = panel.get("_buildings")
	var recipes_by_building: Dictionary = panel.get("_recipes_by_building")
	var disabled_building: Dictionary = {}
	var building_type := ""
	for building in loaded_buildings:
		if disabled_building.is_empty() and str(building.get("category", "")).to_lower() != "infrastructure":
			disabled_building = building
		if building_type == "" and not building.get("building_type", []).is_empty():
			building_type = str(building.get("building_type", [])[0])
	assert(not disabled_building.is_empty(), "Expected a visible non-infrastructure building")
	# Make a controlled no-recipe case so this remains a regression test even
	# when the current catalogue gives every visible building a recipe.
	recipes_by_building.erase(str(disabled_building.get("id", "")))
	var filtered_without_recipe: Array = panel.call("_filtered_buildings")
	assert(disabled_building in filtered_without_recipe, "Buildings with no recipes remain visible in the catalogue")
	var disabled_card: Control = panel.call("_make_building_card", disabled_building)
	var disabled_header := disabled_card.get_child(0).get_child(0) as Button
	assert(disabled_header.disabled, "Buildings with no recipes must be disabled")
	assert(building_type != "", "Expected at least one classic building-type filter")
	panel.set("_active_filters", {building_type: true})
	for building in panel.call("_filtered_buildings"):
		assert(building_type in building.get("building_type", []), "Classic filter included a different building type")
	panel.set("_active_filters", {})

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
	BuildMode.exit_build_mode()
	await get_tree().process_frame
	assert(panel.visible, "Cancelling V2 build mode reopens the construct panel")
	assert(str((panel.get("_header_title") as Label).text) == "CONFIRM CONSTRUCTION",
		"Cancelling V2 build mode restores the confirmation screen")

	panel.call("open_browser")
	await get_tree().process_frame
	assert((panel.get("_settings_button") as Button).visible, "Construct settings gear is visible while browsing")
	panel.call("_on_settings_pressed")
	await get_tree().process_frame
	assert(str((panel.get("_header_title") as Label).text) == "CONSTRUCT SETTINGS", "Settings gear opens construct settings")
	MatchState.set_construct_cost_display("list")
	MatchState.set_construct_start_half_capacity(true)
	MatchState.set_construct_material_source("any_tile")
	MatchState.set_construct_output_destination("same_tile")
	assert(MatchState.construct_cost_display == "list" and MatchState.construct_start_half_capacity,
		"Construct settings update the match defaults")
	var startup_project := Construction.start_on_tile("b_001", "r_001", "tile_construct_setting_probe")
	var startup_data: Dictionary = Construction.construction_projects.get(startup_project, {})
	assert(bool(startup_data.get("startup_half_capacity", false)),
		"New construction captures the half-capacity default")
	assert(str(startup_data.get("output_destination", "")) == "same_tile",
		"New construction captures the output destination default")
	Construction.cancel(startup_project)
	MatchState.set_construct_cost_display("grid")
	MatchState.set_construct_start_half_capacity(false)
	MatchState.set_construct_material_source("ask")
	MatchState.set_construct_output_destination("market")
	panel.call("_on_back_from_settings")

	var cable_requirements := Construction.requirements_for("b_006")
	assert(int(cable_requirements.get("g_007", 0)) == 5 and int(cable_requirements.get("g_036", 0)) == 2,
		"Cable construction resolves its copper wiring and electrical equipment kit")
	var map_overlay := get_tree().root.find_child("MapOverlay", true, false)
	assert(map_overlay != null, "Map overlay was not instantiated")
	BuildMode.enter_infrastructure_mode("cables")
	await get_tree().process_frame
	assert(not (map_overlay.get("build_overlays") as Array).is_empty(),
		"Infrastructure build mode renders a placement overlay")
	BuildMode.exit_build_mode()
	print("construct_panel_v2 smoke: PASS")
	get_tree().quit(0)
