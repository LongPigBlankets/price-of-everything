extends "res://tests/test_base.gd"
## Boot, parse and instantiate checks. Wildcard: runs under every --tags filter.

const FEATURE := ""

func _shoelace(pts: PackedVector2Array) -> float:
	var area := 0.0
	var n := pts.size()
	for i in n:
		var p := pts[i]
		var q := pts[(i + 1) % n]
		area += p.x * q.y - q.x * p.y
	return area * 0.5

func _tile_types_from_csv() -> Dictionary:
	var out := {}
	var file := FileAccess.open("res://data/tile_properties.csv", FileAccess.READ)
	if file == null:
		return out
	var header := file.get_csv_line()
	var id_i := header.find("id")
	var type_i := header.find("type")
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() > maxi(id_i, type_i):
			out[row[id_i]] = row[type_i]
	file.close()
	return out

func _find_node_by_script(node: Node, script_path: String) -> Node:
	var s: Script = node.get_script() as Script
	if s != null and s.resource_path == script_path:
		return node
	for child in node.get_children():
		var hit := _find_node_by_script(child, script_path)
		if hit != null:
			return hit
	return null

func _gd_files_in(directory: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(directory)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := "%s/%s" % [directory, entry]
		if dir.current_is_dir():
			if not entry.begins_with("."):
				out.append_array(_gd_files_in(full))
		elif entry.ends_with(".gd"):
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	return out


# ======================================================================================
# Authored roads (scripts/authored_road_{geometry,style,visuals}.gd)
#
# Three properties decide whether a hand-drawn road behaves: its geometry is deterministic
# and keeps the endpoints the designer placed; the touched-tile set is COMPLETE, because
# the unlock rule reads it; and the three width classes stay a real hierarchy.
# ======================================================================================

# Smoke: every script we touch must still parse. load() returns null on a parse
# error — this is the check that catches the bug class we couldn't verify by hand.
func _test_scripts_parse() -> void:
	for path in [
		"res://scripts/stockpile_view.gd",
		"res://scripts/infra_grid.gd",
		"res://scripts/tile_info_panel_v2.gd",
		"res://scripts/building_connection_visuals.gd",
		"res://scripts/world_map.gd",
		"res://scripts/map_overlay.gd",
		"res://scripts/build_mode_hex_overlay.gd",
		"res://scripts/build_mode_backdrop.gd",
		"res://scripts/power_hex_overlay.gd",
		"res://scripts/water_overlay.gd",
		"res://scripts/hex_map.gd",
		"res://scripts/ds.gd",
		"res://scripts/search_overlay.gd",
		"res://scripts/good_icons.gd",
		"res://scripts/catalog.gd",
		"res://scripts/construct_panel.gd",
		"res://scripts/construct_panel_v2.gd",
		"res://scripts/building_detail_panel_v2.gd",
		"res://scripts/infrastructure_info.gd",
		"res://scripts/build_mode.gd",
		"res://scripts/building_row.gd",
		"res://scripts/recipe_row.gd",
		"res://scripts/logistics_overlay.gd",
		"res://scripts/mapmodes_panel.gd",
		"res://scripts/overlay_legend.gd",
		"res://scripts/debug_terminal.gd",
		"res://scripts/sale_effects.gd",
		"res://scripts/ui_helpers.gd",
		"res://scripts/market_panel.gd",
		"res://scripts/construction.gd",
		"res://scripts/construction_missing_dialog.gd",
		"res://scripts/transport_service.gd",
		"res://scripts/event_scheduler.gd",
		"res://scripts/modifier_state.gd",
		"res://scripts/notification_bell.gd",
		"res://scripts/road_regions.gd",
		"res://scripts/special_order_state.gd",
		"res://scripts/special_order_resolution_dialog.gd",
		"res://scripts/unlock_dialog.gd",
		"res://scripts/people_panel.gd",
		"res://scripts/main_menu.gd",
		"res://scripts/new_game_panel.gd",
		"res://scripts/tutorial_intro_panel.gd",
		"res://scripts/camera_controller.gd",
		"res://scripts/tutorial/tutorial_engine.gd",
		"res://scripts/tutorial/coach_overlay.gd",
		"res://scripts/tutorial/tutorial_recipe_flow_panel.gd",
		"res://scripts/tutorial/tutorial_route_highlight.gd",
		"res://scripts/tutorial/tutorial_steps.gd",
		"res://scripts/tutorial/tutorial_detectors.gd",
		"res://scripts/company_names.gd",
		"res://scripts/company_rankings.gd",
		"res://scripts/top_bar.gd",
	]:
		_check(load(path) != null, "parses: " + path)

func _test_shipped_code_avoids_editor_only_paths() -> void:
	# The map editor lives in the game project but is EXCLUDED from exported builds
	# (export_presets.cfg). A shipped script that preloads an excluded path resolves it at
	# parse time and breaks the exported game — so shipped code may only reach the editor
	# by a path STRING guarded with ResourceLoader.exists, as main_menu.gd does.
	var excluded := ["res://scripts/map_editor/", "res://tools/", "res://tests/"]
	var offenders := PackedStringArray()
	var scanned := 0
	for directory in ["res://scripts", "res://scenes"]:
		for file_path in _gd_files_in(directory):
			if file_path.begins_with("res://scripts/map_editor/"):
				continue   # the editor may reference itself
			var file := FileAccess.open(file_path, FileAccess.READ)
			if file == null:
				continue
			var text := file.get_as_text()
			file.close()
			scanned += 1
			for line in text.split("\n"):
				var trimmed := line.strip_edges()
				if not (trimmed.begins_with("const ") or trimmed.begins_with("var ")
					or trimmed.begins_with("@onready")) or not trimmed.contains("preload("):
					continue
				for path in excluded:
					if trimmed.contains(path):
						offenders.append("%s: %s" % [file_path.get_file(), trimmed])
	_check(scanned > 50,
		"export isolation: the shipped-script scan actually read the scripts (%d files)" % scanned)
	_check(offenders.is_empty(),
		"export isolation: no shipped script preloads an export-excluded path (%s)"
		% ", ".join(offenders))

	# The launch path itself: the menu must hold the editor as a string and probe for it.
	var menu := FileAccess.open("res://scripts/main_menu.gd", FileAccess.READ)
	_check(menu != null, "export isolation: main_menu.gd is readable")
	if menu != null:
		var menu_text := menu.get_as_text()
		menu.close()
		_check(menu_text.contains("ResourceLoader.exists(MAP_EDITOR_SCENE)"),
			"export isolation: the menu probes for the editor scene before offering it")
		_check(not menu_text.contains("preload(\"res://tools/"),
			"export isolation: the menu never preloads the editor")


# Smoke: the extracted widgets instantiate and build their UI.
func _test_widgets_instantiate() -> void:
	var sv: Node = load("res://scripts/stockpile_view.gd").new()
	add_child(sv)
	sv.set_tile("")
	_check(sv.get_child_count() > 0, "StockpileView builds its UI")
	sv.queue_free()

	var ig: Node = load("res://scripts/infra_grid.gd").new()
	add_child(ig)
	ig.set_slots([{
		"cell_size": Vector2(80, 80), "icon": null, "state": "add",
		"internal_name": "roads", "button_tooltip": "Add Roads",
		"display_label": "Roads", "label_tooltip": "", "max_label_lines": 2,
	}])
	_check(ig.get_child_count() == 1, "InfraGrid renders one slot")
	ig.queue_free()

	var saved_advisors := AdvisorState.permanent_advisor_ids.duplicate(true)
	var saved_recruited := AdvisorState.recruited_advisor_ids.duplicate(true)
	var saved_fired := AdvisorState.fired_advisor_cooldowns.duplicate(true)
	var saved_seats := AdvisorState.advisor_seats.duplicate(true)
	AdvisorState.fired_advisor_cooldowns.clear()
	AdvisorState.permanent_advisor_ids.clear()
	AdvisorState.advisor_seats.clear()
	var _all_ids: Array = []
	for _a in AdvisorState.advisor_pool():
		_all_ids.append(str(_a.get("id", "")))
	AdvisorState.recruited_advisor_ids = _all_ids
	# This fixture exercises the FULL council (all seats + roster), so open the demo gate;
	# restored after pp is freed below.
	var _saved_adv_unlocked := AdvisorState.advisors_unlocked
	AdvisorState.advisors_unlocked = true
	AdvisorState.advisors_changed.emit()
	var pp: Node = load("res://scripts/people_panel.gd").new()
	add_child(pp)
	_check(
		_tree_has_label_text(pp, "Labour") and _tree_has_label_text(pp, "Advisors")
		and _tree_has_label_text(pp, "0.8x") and _tree_has_label_text(pp, "WORKFORCE POLICIES"),
		"PeoplePanel builds Labour and Advisors tabs")
	# The Advisors tab is now the ROLE-FIRST council view: one card per SEAT.
	# Hiring opens at the founder's decision turn; this fixture exercises the hire flow.
	TurnManager.current_turn = maxi(TurnManager.current_turn, DecisionState.FOUNDER_DECISION_TURN)
	var council_tab: Node = _find_node_by_script(pp, "res://scripts/advisor_council_tab.gd")
	_check(council_tab != null and _tree_has_label_text(pp, "COUNCIL SEATS")
		and _tree_has_label_text(pp, "CFO") and _tree_has_label_text(pp, "VP Logistics"),
		"PeoplePanel shows advisor payroll at the top")
	_check(pp.find_child("AdvisorAddNewButton", true, false) != null,
		"PeoplePanel exposes a stable Add new advisor button for the tutorial spotlight")
	_check(AdvisorState.available_advisors().size() == AdvisorState.advisor_pool().size()
		and AdvisorState.permanent_advisors().is_empty(),
		"PeoplePanel starts with all advisors available and none permanent")
	council_tab.call("_set_view", {"mode": "picker", "hire_seat": "cfo", "back": "roster"})
	_check(_tree_has_label_text(pp, "Vera Ashby") and _tree_has_label_text(pp, "Rufus Ashby")
		and _tree_has_label_text(pp, "Hiring for"),
		"PeoplePanel plus slot opens the available advisor pool")
	var first_advisor: Dictionary = AdvisorState.available_advisors()[0]
	var first_id := str(first_advisor.get("id", ""))
	council_tab.call("_set_view", {"mode": "detail", "sel_id": first_id, "hire_seat": "cfo", "back": "picker"})
	_check(_tree_has_label_text(pp, str(first_advisor.get("name", "")))
		and not AdvisorState.permanent_advisor_ids.has(first_id),
		"PeoplePanel clicking an available advisor opens the profile, not an instant hire")
	var default_confirm := pp.find_child("AdvisorHireAssignButton", true, false) as Button
	var default_cfo := pp.find_child("AdvisorSeatChoice_cfo", true, false) as Button
	var default_coo := pp.find_child("AdvisorSeatChoice_coo", true, false) as Button
	_check(pp.find_child("AdvisorBonusPrompt", true, false) != null
		and pp.find_child("AdvisorBonusSection", true, false) == null
		and default_confirm != null and default_confirm.disabled
		and default_cfo != null and not default_cfo.button_pressed
		and default_coo != null and not default_coo.button_pressed,
		"PeoplePanel candidate profile starts with no position or bonus preview selected")
	var cfo_rows: Array = council_tab.call("_advisor_bonus_rows", first_id, "cfo")
	var coo_rows: Array = council_tab.call("_advisor_bonus_rows", first_id, "coo")
	default_cfo.pressed.emit()
	var cfo_bonus := pp.find_child("AdvisorBonusSection", true, false) as Label
	var cfo_bonus_value := pp.find_child("AdvisorBonusValue", true, false) as Label
	var cfo_salary_value := pp.find_child("AdvisorSalaryValue", true, false) as Label
	var selected_cfo := pp.find_child("AdvisorSeatChoice_cfo", true, false) as Button
	var selected_cfo_style := selected_cfo.get_theme_stylebox("normal") if selected_cfo != null else null
	_check(cfo_bonus != null and cfo_bonus.text.contains("CFO")
		and selected_cfo != null and selected_cfo.button_pressed,
		"PeoplePanel selecting CFO rebuilds the CFO bonus preview")
	_check(cfo_bonus_value != null and cfo_bonus_value.text.begins_with("Preview bonuses: £")
		and cfo_salary_value != null and cfo_salary_value.text.begins_with("Salary: £")
		and cfo_bonus_value.text.ends_with(" per turn")
		and cfo_salary_value.text.ends_with(" per turn"),
		"PeoplePanel selected position compares snapshot bonuses with salary")
	_check(selected_cfo != null and selected_cfo.theme_type_variation == &"ChoiceSelected"
		and selected_cfo_style is StyleBoxFlat,
		"PeoplePanel selected position uses the dedicated selected-choice surface")
	_check(selected_cfo_style is StyleBoxFlat
		and (selected_cfo_style as StyleBoxFlat).bg_color.is_equal_approx(DS.PALETTE["ACCENT"]),
		"PeoplePanel selected-choice surface is off-white (got %s, want %s)" % [
			str((selected_cfo_style as StyleBoxFlat).bg_color) if selected_cfo_style is StyleBoxFlat else "not flat",
			str(DS.PALETTE["ACCENT"]),
		])
	_check(selected_cfo.get_theme_color("font_color").is_equal_approx(DS.PALETTE["BG_PANEL"])
		and selected_cfo.get_theme_color("font_pressed_color").is_equal_approx(DS.PALETTE["BG_PANEL"]),
		"PeoplePanel selected-choice text is navy (got %s/%s, want %s)" % [
			str(selected_cfo.get_theme_color("font_color")),
			str(selected_cfo.get_theme_color("font_pressed_color")),
			str(DS.PALETTE["BG_PANEL"]),
		])
	var cfo_state_coo := pp.find_child("AdvisorSeatChoice_coo", true, false) as Button
	cfo_state_coo.pressed.emit()
	var coo_bonus := pp.find_child("AdvisorBonusSection", true, false) as Label
	var selected_coo := pp.find_child("AdvisorSeatChoice_coo", true, false) as Button
	var unselected_cfo := pp.find_child("AdvisorSeatChoice_cfo", true, false) as Button
	_check(coo_bonus != null and coo_bonus.text.contains("COO")
		and cfo_rows != coo_rows
		and selected_coo != null and selected_coo.button_pressed
		and unselected_cfo != null and not unselected_cfo.button_pressed
		and unselected_cfo.theme_type_variation == &"",
		"PeoplePanel changes the bonus preview and selected button with each position")
	_check(pp.find_child("AdvisorHireAssignButton", true, false) != null
		and not (pp.find_child("AdvisorHireAssignButton", true, false) as Button).disabled,
		"PeoplePanel enables Hire & assign only after a position is selected")
	# The Hire & assign confirm runs exactly this hire + seat-assign pair.
	var hired_ok := AdvisorState.hire_advisor(first_id) and AdvisorState.assign_advisor_to_seat("cfo", first_id)
	council_tab.call("_set_view", {"mode": "roster"})
	_check(hired_ok and AdvisorState.permanent_advisor_ids.has(first_id)
		and _tree_has_label_text(pp, str(first_advisor.get("name", ""))),
		"PeoplePanel Confirm Hire from the profile hires a permanent advisor and updates payroll")
	_check(pp.find_child("AdvisorBonusValue", true, false) != null
		and pp.find_child("AdvisorSalaryValue", true, false) != null,
		"PeoplePanel keeps the bonus-versus-salary comparison after hiring")
	# Fire flow: the profile footer for an employed advisor benches them.
	pp.call("_open_advisor_detail", first_advisor)
	var fire_footer: Control = pp.call("_advisor_detail_footer", first_advisor, true, false) as Control
	_check(fire_footer is Button and (fire_footer as Button).text == "Fire Advisor",
		"PeoplePanel employed-advisor footer offers Fire Advisor")
	var fid := str(first_advisor.get("id", ""))
	# Net-modifiers readout + the "See all advisor modifiers" DS panel.
	AdvisorState.assign_advisor_to_seat("cfo", fid)
	_check((pp.call("_advisor_net_modifiers") as Array).size() > 0,
		"PeoplePanel net-modifiers aggregates seated advisor effects")
	pp.call("_open_advisor_modifiers_panel")
	var modpanel: Node = pp.get("_advisor_modifiers_panel")
	_check(is_instance_valid(modpanel) and (modpanel as Control).visible,
		"PeoplePanel See-all opens the DS modifiers panel")
	if is_instance_valid(modpanel):
		PanelStack.remove(modpanel)
		modpanel.queue_free()
	AdvisorState.fire_advisor(fid)
	_check(not AdvisorState.permanent_advisor_ids.has(fid)
		and AdvisorState.is_fired(fid)
		and AdvisorState.fire_cooldown_remaining(fid) == AdvisorState.FIRE_COOLDOWN_TURNS
		and not AdvisorState.hire_advisor(fid),
		"PeoplePanel firing benches the advisor for the cooldown and blocks re-hire")
	# Cooldown counts down each turn; the advisor returns to the pool at 0.
	for _i in AdvisorState.FIRE_COOLDOWN_TURNS:
		AdvisorState._tick_fire_cooldowns()
	_check(not AdvisorState.is_fired(fid) and AdvisorState.hire_advisor(fid),
		"PeoplePanel fired advisor returns to the pool after the cooldown and can be re-hired")
	pp.call("_close_advisor_detail")
	var permanent: Array = pp.get("_permanent_advisors")
	var card: Control = pp.call("_advisor_card", permanent[0], true, false) as Control
	var portrait: Control = card.find_child("AdvisorPortrait", true, false) as Control
	_check(card.mouse_filter == Control.MOUSE_FILTER_STOP and portrait != null
		and portrait.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"PeoplePanel advisor card click surface includes the portrait")
	_check(card.find_child("AssignedAdvisorRole", true, false) == null,
		"PeoplePanel advisor card leaves role blank until the advisor is assigned")
	card.free()
	AdvisorState.assign_advisor_to_seat("cfo", str((permanent[0] as Dictionary).get("id", "")))
	var assigned_card: Control = pp.call("_advisor_card", permanent[0], true, false) as Control
	_check(_tree_has_label_text(assigned_card, "CFO")
			and assigned_card.find_child("AssignedAdvisorRole", true, false) != null,
		"PeoplePanel advisor card shows the assigned seat once assigned")
	assigned_card.free()
	if not permanent.is_empty():
		pp.call("_open_advisor_detail", permanent[0])
	var detail: Node = pp.get("_advisor_detail_panel")
	_check(detail != null and detail.visible and _tree_has_label_text(detail, "Impact") and _tree_has_label_text(detail, "Seats"),
		"PeoplePanel opens advisor detail shell")
	var demo_terminal := preload("res://scripts/debug_terminal.gd")
	var was_demo_unlocked: bool = demo_terminal._demo_unlocked
	demo_terminal._demo_unlocked = false
	pp.call("_open_advisor_detail", permanent[0])
	_check(not _tree_has_label_text(detail, "Agenda") and not _tree_has_label_text(detail, "Missions"),
		"demo advisor detail hides loyalty agenda and missions")
	demo_terminal._demo_unlocked = true
	pp.call("_open_advisor_detail", permanent[0])
	_check(_tree_has_label_text(detail, "Agenda") and _tree_has_label_text(detail, "Missions"),
		"unlock demo restores advisor loyalty concepts")
	demo_terminal._demo_unlocked = was_demo_unlocked
	pp.call("_close_advisor_detail")
	if detail != null:
		detail.queue_free()
	pp.queue_free()
	AdvisorState.advisors_unlocked = _saved_adv_unlocked
	AdvisorState.permanent_advisor_ids = saved_advisors
	AdvisorState.recruited_advisor_ids = saved_recruited
	AdvisorState.fired_advisor_cooldowns = saved_fired
	AdvisorState.advisor_seats = saved_seats
	AdvisorState.reconcile_advisor_modifiers()
	AdvisorState.advisors_changed.emit()

# Smoke: the big scene still loads as a resource (catches main.tscn corruption).
func _test_scene_loads() -> void:
	_check(load("res://scenes/main.tscn") != null, "main.tscn loads")

# Instantiate the whole main scene and confirm the tile panel's @onready node
# paths still resolve. This is the net for layout/scene restructuring (Slice D):
# a broken node path leaves an @onready var null, which this catches.
func _test_main_scene_instantiates() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	if packed == null:
		_check(false, "main.tscn instantiates")
		return
	var inst: Node = packed.instantiate()
	add_child(inst)
	await get_tree().process_frame
	var panel: Node = inst.find_child("TileInfoPanel", true, false)
	_check(panel != null and panel.has_method("show_tile"),
		"main.tscn instantiates; the tile panel exists and exposes show_tile")
	# Exactly one tile panel: the classic (v1) panel is gone for good.
	var hud_content: Node = inst.find_child("HUDContent", true, false)
	var panel_count := 0
	if hud_content != null:
		for child in hud_content.get_children():
			if str(child.name).begins_with("TileInfoPanel"):
				panel_count += 1
	_check(panel_count == 1, "exactly one tile panel lives under HUDContent (found %d)" % panel_count)
	# Guards the theme-cascade fix: DS variations must actually resolve on panels.
	var tl = panel.get("_title_label") if panel != null else null
	_check(tl != null and tl.get_theme_font_size("font_size") == DS.FS["H1"],
		"DS theme reaches the tile panel (title uses the DS Title font)")
	# Selecting a tile through the terrain layer's click signal opens the panel.
	var terrain: Node = inst.find_child("TerrainLayer", true, false)
	if panel != null and terrain != null and not terrain.tiles.is_empty():
		var td: Dictionary = terrain.tiles[terrain.tiles.keys()[0]]
		terrain.tile_selected.emit(td)
		await get_tree().process_frame
		_check(panel.visible, "selecting a tile opens the tile panel")
		panel.hide()
	else:
		_check(false, "terrain layer with tiles available for tile-select test")
	# Step 24 provides a single exact white tile cue; its destination picker must still
	# capture clicks without repainting every eligible tile green.
	var tutorial_active_saved: bool = Tutorial.active
	var tutorial_steps_saved: Array = Tutorial._steps
	var tutorial_index_saved: int = Tutorial._index
	Tutorial.active = true
	Tutorial._steps = [{"id": "transport_redirect_pick"}]
	Tutorial._index = 0
	inst.call("_on_v2_pick_destination")
	_check(bool(terrain.get("_stockpile_destination_selection_active"))
		and not bool(terrain.get("_selection_paint")),
		"tutorial: Step 24 destination picker captures clicks without the green overlay")
	terrain.end_stockpile_destination_selection()
	inst.set("_v2_picking_dest", false)
	Tutorial.active = tutorial_active_saved
	Tutorial._steps = tutorial_steps_saved
	Tutorial._index = tutorial_index_saved
	# Buying a building can refresh its detail from building_owner_changed and then focus it
	# again from the tutorial in the same frame. Rebuilding twice must replace, not temporarily
	# stack, the old body controls; stacked generations inflated the panel to viewport width.
	var detail := inst.find_child("BuildingDetailPanelV2", true, false)
	var detail_fixture: Dictionary = {}
	for candidate in BuildingState.buildings.values():
		if candidate is Dictionary and str((candidate as Dictionary).get("building_id", "")) == "b_007":
			detail_fixture = candidate as Dictionary
			break
	if detail != null and not detail_fixture.is_empty():
		detail.show_building(detail_fixture)
		var detail_body := detail.get("_body") as VBoxContainer
		var first_generation_count := detail_body.get_child_count() if detail_body != null else 0
		detail.show_building(detail_fixture)
		var second_generation_count := detail_body.get_child_count() if detail_body != null else 0
		_check(first_generation_count > 0 and second_generation_count == first_generation_count,
			"building detail: same-frame rebuild replaces old controls")
		await get_tree().process_frame
		_check((detail as Control).size.x <= 520.0,
			"building detail: same-frame rebuild stays at its narrow panel width")
		detail.hide()
	else:
		_check(false, "building detail: Industrial Goods Factory fixture is available")
	inst.queue_free()
	await get_tree().process_frame

# Logic: the data CSVs load into the Catalog as expected.
func _test_catalog_loaded() -> void:
	_check(Catalog.all_goods().size() == 77, "Catalog has 77 goods")
	var _all_classed := true
	for g in Catalog.all_goods():
		if str(g.get("transport_class", "")) == "":
			_all_classed = false
	_check(_all_classed, "every loaded good has a transport_class")
	_check(Catalog.all_recipes().size() >= 18, "Catalog promotes a healthy recipe set (>=18)")
	_check(Catalog.all_buildings().size() == 37, "Catalog has 37 buildings")
	# Regression (farm buildability): the agri goods (biomass, waste_water, fertilisers) exist, so the
	# biomass farm recipes promote and the farm is no longer recipe-less — the "clicking the farm does
	# nothing" bug, caused by every farm recipe being dropped at the promotion gate for missing goods.
	_check(not Catalog.get_good_by_internal_name("biomass").is_empty(), "good 'biomass' is loaded")
	_check(not Catalog.get_good_by_internal_name("waste_water").is_empty(), "good 'waste_water' is loaded")
	_check(not Catalog.get_good_by_internal_name("fertilisers").is_empty(), "good 'fertilisers' is loaded")
	var farm_id: String = str(Catalog.get_building_by_internal_name("farm").get("id", ""))
	var farm_recipe_ids: Array = []
	for r in Catalog.get_recipes_for_building(farm_id):
		farm_recipe_ids.append(str(r.get("recipe_id", "")))
	# r_208 (Sustainable Biomass Production) is now tech-gated behind "Energy Crop Cultivation",
	# so it is intentionally absent from the start-active set; the base biomass recipes remain.
	var has_all_biomass: bool = farm_recipe_ids.has("r_209") \
		and farm_recipe_ids.has("r_211") and farm_recipe_ids.has("r_212")
	_check(has_all_biomass, "farm has its base biomass recipes (buildable, not recipe-less): %s" % str(farm_recipe_ids))
	_check(int(Catalog.get_building_by_internal_name("farm").get("tile_size_used", 0)) == 20,
		"farm building is tile_size_used 20")

	# The three acid recipes (r_114/115/116) were moved to the Chemical Plant
	# (owner request 2026-07-13); they used to sit on the Industrial Factory via the
	# industrial_goods_factory→industrial_factory alias.
	var chem_id: String = str(Catalog.get_building_by_internal_name("chem_plant").get("id", ""))
	var indf_id: String = str(Catalog.get_building_by_internal_name("industrial_factory").get("id", ""))
	var chem_recipe_ids: Array = []
	for r in Catalog.get_recipes_for_building(chem_id):
		chem_recipe_ids.append(str(r.get("recipe_id", "")))
	var indf_recipe_ids: Array = []
	for r in Catalog.get_recipes_for_building(indf_id):
		indf_recipe_ids.append(str(r.get("recipe_id", "")))
	for acid in ["r_114", "r_115", "r_116"]:
		_check(chem_recipe_ids.has(acid), "%s (acid) is now on the Chemical Plant" % acid)
		_check(not indf_recipe_ids.has(acid), "%s (acid) is no longer on the Industrial Factory" % acid)
	_check(not indf_recipe_ids.is_empty(), "Industrial Factory still has recipes (not farm-bugged by the move)")

func _test_bottom_menu_default() -> void:
	var all_ok := true
	for key in ["construct", "goods", "building_ledger", "mapmodes", "market", "politics", "research", "people"]:
		var path := "res://assets/icons/ui_icons/alt/%s.png" % key
		if not (ResourceLoader.exists(path) and load(path) is Texture2D):
			all_ok = false
	_check(all_ok, "white-rimmed bottom-menu icons import and load")

func _test_panel_stack_focus() -> void:
	var holder := Control.new()
	add_child(holder)
	var a := PanelContainer.new()
	var b := PanelContainer.new()
	var child := Button.new()
	a.name = "FocusA"
	b.name = "FocusB"
	a.add_child(child)
	holder.add_child(a)
	holder.add_child(b)
	PanelStack.push(a)
	PanelStack.push(b)
	_check(PanelStack.top() == b, "panel stack: last pushed panel is top")
	_check(holder.get_child(holder.get_child_count() - 1) == b,
		"panel stack: last pushed panel is front sibling")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	child.emit_signal("gui_input", click)
	_check(PanelStack.top() == a, "panel stack: clicking inside a panel focuses it")
	_check(holder.get_child(holder.get_child_count() - 1) == a,
		"panel stack: focused panel moves to front sibling")
	_check(PanelStack.close_top() and not a.visible, "panel stack: close_top hides focused panel")
	PanelStack.remove(b)
	holder.queue_free()


# --- Decision events (docs/decision-events-spec.md) --------------------------

func _test_debug_terminal() -> void:
	var term: Node = load("res://scripts/debug_terminal.gd").new()
	add_child(term)
	await get_tree().process_frame
	# Commands are gated behind `debug CandC` (case-sensitive, per app run).
	term._cheats_unlocked = false
	_check(term._run_command("cash 250") == "invalid operation", "terminal: locked before unlock")
	_check(term._run_command("debug candc") == "invalid operation", "terminal: pass-phrase is case-sensitive")
	_check(term._run_command("help") == "invalid operation", "terminal: help locked too")
	_check("enabled" in term._run_command("debug CandC"), "terminal: debug CandC unlocks")
	_check("already" in term._run_command("debug CandC"), "terminal: repeat unlock reported")
	var before: float = MatchState.money
	var result: String = term._run_command("cash 250")
	_check(absf(MatchState.money - (before + 250.0)) < 0.001, "terminal: cash adds the amount")
	_check("250" in result, "terminal: cash reports the amount")
	_check(term._run_command("bogus").begins_with("unknown"), "terminal: unknown command handled")
	# 'toggle heightmap' flips the hill/sea/lake layer; default is visible
	var fake_layer := Node2D.new()
	fake_layer.add_to_group("hill_visuals")
	add_child(fake_layer)
	_check(fake_layer.visible, "terminal: heightmap starts visible")
	_check("off" in term._run_command("toggle heightmap"), "terminal: toggle heightmap reports off")
	_check(not fake_layer.visible, "terminal: heightmap hidden after first toggle")
	_check("on" in term._run_command("toggle heightmap"), "terminal: toggle heightmap reports on")
	_check(fake_layer.visible, "terminal: heightmap visible after second toggle")
	fake_layer.queue_free()
	term.queue_free()

func _test_app_paths() -> void:
	# Portable data layout: saves/logs sit next to the build, in the project when in-editor.
	var AppPaths = load("res://scripts/app_paths.gd")
	# The macOS base is the folder CONTAINING the .app — 4 levels up from the binary.
	var sample := "/Users/x/Carbon and Capital (Experimental)/Carbon and Capital.app/Contents/MacOS/Carbon and Capital"
	_check(AppPaths._macos_bundle_parent(sample) == "/Users/x/Carbon and Capital (Experimental)",
		"app_paths: macOS base resolves to the folder containing the .app")
	var base: String = AppPaths.base_dir()
	_check(AppPaths.saves_dir() == base.path_join("savegames"), "app_paths: saves_dir is <base>/savegames")
	_check(AppPaths.logs_dir() == base.path_join("logs"), "app_paths: logs_dir is <base>/logs")
	_check(DirAccess.dir_exists_absolute(AppPaths.saves_dir()), "app_paths: savegames dir is created on demand")
	_check(DirAccess.dir_exists_absolute(AppPaths.logs_dir()), "app_paths: logs dir is created on demand")
	# In the editor + headless runner (both carry the "editor" feature) the base is the project folder.
	_check(base == ProjectSettings.globalize_path("res://").trim_suffix("/"),
		"app_paths: editor/test base is the project folder, not user://")

func _test_hills_baked_fresh() -> void:
	_check(FileAccess.file_exists(HillBaked.BAKED_PATH), "hills: baked file exists")
	var doc := HillBaked.data()
	_check(not doc.is_empty(), "hills: baked file parses")
	_check(str(doc.get("source_hash", "")) == HillBaked.source_hash(),
		"hills: bake is fresh (re-run tools/bake_hills.tscn after map/generator edits)")
	var polys := HillBaked.polys()
	_check(polys.size() > 100, "hills: baked polys present (%d)" % polys.size())
	var bands_ok := true
	var has_mountain_bands := false
	var depr_area := 0.0
	var depr_min_ok := true
	for entry in polys:
		if entry.b < 0 or entry.b > 11 or entry.p.size() < 3:
			bands_ok = false
			break
		if entry.b >= 8:
			has_mountain_bands = true
		if entry.b == 0:
			var a: float = absf(_shoelace(entry.p))
			depr_area += a
			if a < 3500.0:   # 10 subtiles = 4000 u^2, minus Chaikin shrink tolerance
				depr_min_ok = false
	_check(bands_ok, "hills: every poly has a valid band (0-11) and >= 3 points")
	_check(has_mountain_bands, "mountains: brown/snow bands (lv 7+) present in bake")
	_check(depr_area > 0.0, "depressions: lv -1 areas present in bake")
	_check(depr_area <= 45000.0, "depressions: total within the 100-subtile budget (%.0f u2)" % depr_area)
	_check(depr_min_ok, "depressions: every lv -1 basin is >= 10 subtile units")
	var lakes := HillBaked.lakes()
	_check(lakes.size() >= 6, "lakes: organic lake polys present (%d)" % lakes.size())
	var sea := HillBaked.sea()
	_check(sea.size() >= 25, "coast: sea/coast polys present (%d)" % sea.size())
	var sea_bands_ok := true
	var has_navy := false
	for entry in sea:
		if entry.b < 0 or entry.b > 5:
			sea_bands_ok = false
		if entry.b == 0:
			has_navy = true
	_check(sea_bands_ok, "coast: sea bands within 0..5")
	_check(has_navy, "coast: lv -6 navy zone present around deep sea")
	# blocked masks may only name hill tiles, with sane bit indices
	var types := _tile_types_from_csv()
	var blocked := HillBaked.blocked()
	_check(blocked.size() > 0, "hills: blocked masks present")
	var only_hills := true
	var bits_ok := true
	for tile_id in blocked:
		if str(types.get(tile_id, "")) != "hill":
			only_hills = false
		for b in blocked[tile_id]:
			if int(b) < 0 or int(b) >= SubtileGrid.COLUMNS * SubtileGrid.ROWS:
				bits_ok = false
	_check(only_hills, "hills: blocked subtiles only on hill tiles")
	_check(bits_ok, "hills: blocked bit indices in range")
	# occupancy consumes the bake: a blocked subtile must be unbuildable
	var sample_tile: String = blocked.keys()[0]
	var bit: int = blocked[sample_tile][0]
	var col := bit % SubtileGrid.COLUMNS + 1
	var row := bit / SubtileGrid.COLUMNS + 1
	_check(TileOccupancy.is_blocked(sample_tile, col, row), "hills: TileOccupancy sees baked mask")
	_check(not SubtileGrid.is_subtile_buildable(col, row, {}, [], sample_tile),
		"hills: blocked subtile is unbuildable via SubtileGrid")

## The eight company liveries: the table loads, every livery is distinguishable from every
## other, and the New Game panel's choice reaches the match ruleset (which is what carries it
## into a save file). The distinctness check is the point of the sampler's livery band — two
## liveries that read the same on the map make the colour useless as an owner cue, and the
## raw samples DID collide (ethylene sampled a near-black navy against Graphite Black).
func _test_player_colours() -> void:
	var PlayerColours := preload("res://scripts/player_colours.gd")
	var all: Array = PlayerColours.all()
	_check(all.size() == 8, "player colours: 8 liveries load (got %d)" % all.size())
	_check(PlayerColours.has(PlayerColours.DEFAULT_KEY),
		"player colours: the default livery is in the table")

	var seen: Dictionary = {}
	var too_close := PackedStringArray()
	for a_value in all:
		var a: Dictionary = a_value
		_check(not seen.has(str(a["key"])), "player colours: '%s' appears once" % str(a["key"]))
		seen[str(a["key"])] = true
		_check(str(a["label"]) != "", "player colours: %s has a label" % str(a["key"]))
		var ca: Color = a["color"]
		for b_value in all:
			var b: Dictionary = b_value
			if str(a["key"]) >= str(b["key"]):
				continue
			var cb: Color = b["color"]
			# Plain RGB distance. Crude next to a perceptual metric, and enough to catch the
			# failure that actually happened — two liveries landing on the same dark slate.
			var d := absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
			if d < 0.22:
				too_close.append("%s vs %s (%.2f)" % [str(a["key"]), str(b["key"]), d])
	_check(too_close.is_empty(), "player colours: every livery is distinguishable (%s)"
		% ("all distinct" if too_close.is_empty() else ", ".join(too_close)))

	# A 20px swatch, the size the dropdown asks for (owner, 2026-08-27).
	var swatch: ImageTexture = PlayerColours.swatch(PlayerColours.DEFAULT_KEY, 20)
	_check(swatch != null and swatch.get_width() == 20 and swatch.get_height() == 20,
		"player colours: swatch is 20x20")

	# An unknown key must fall back rather than colour a company with nothing — this is the
	# hand-edited-save and renamed-livery path.
	_check(not PlayerColours.has("no_such_livery"),
		"player colours: an unknown key is not in the table")
	_check(PlayerColours.color_for("no_such_livery") == PlayerColours.FALLBACK,
		"player colours: an unknown key falls back")

	# The picker writes into the ruleset; that is how the livery reaches a save.
	var snap: Dictionary = SaveLoad.expand_start_config(
		{"start": true, "ruleset": {"name": "standard"}},
		{"ruleset": {"company_colour": "graphite_black"}})
	var rules: Dictionary = (snap.get("match", {}) as Dictionary).get("ruleset", {})
	_check(str(rules.get("company_colour", "")) == "graphite_black",
		"player colours: the picked livery merges into the match ruleset")


# A predetermined river crossing reserves a road corridor: a band along the river + a stub
# straight out from the bridge on each bank, so the road reaches the bridge without being
# forced over riverside buildings (the Arin overlap). Buildings keep RIVER_ROAD_PAD clear.
# Subcomponents: sizable buildings fund a second pass of round tanks + annexes, placed in spare
# space beside the parent, deterministic, never overlapping the buildings.
func _test_subcomponents() -> void:
	var nav := NavGrid.instance()
	if not nav.is_ready():
		return
	var terrain := TileMapLayer.new()
	terrain.tile_set = load("res://assets/main_tileset.tres")
	terrain.set_script(load("res://scripts/hex_map.gd"))
	add_child(terrain)
	await get_tree().process_frame
	RoadNetwork.reset()
	var bv := preload("res://scenes/building_visuals.gd").new()
	add_child(bv)
	await get_tree().process_frame
	bv.terrain_layer = terrain
	var tile_id := "tile_9_10"
	var coord: Vector2i = terrain.id_to_coord(tile_id)
	if not terrain.tiles.has(coord):
		_check(false, "subcomp: test tile exists")
		bv.queue_free(); terrain.queue_free(); return
	# two sizable buildings (industrial_factory, tile_size_used 10 -> ~3 ancillaries each)
	for i in 2:
		var iid: String = BuildingState.add_building("b_007", "", tile_id, "npc", "sub_b_%d" % i)
		bv.on_building_placed(tile_id, "b_007", "", iid, coord)
	bv._rebuild_subcomponents(tile_id)
	var n1 := (bv._subcomponents as Array).size()
	_check(n1 > 0, "subcomp: tanks/annexes placed for sizable buildings (%d)" % n1)
	bv._rebuild_subcomponents(tile_id)
	_check((bv._subcomponents as Array).size() == n1, "subcomp: rebuild is deterministic (%d)" % (bv._subcomponents as Array).size())
	var brects: Array = bv.footprint_rects_on_tile(coord)
	var max_hits := 0
	for sc in bv._subcomponents:
		var hits := 0
		for br in brects:
			if (sc.bb as Rect2).intersects(br as Rect2):
				hits += 1
		max_hits = maxi(max_hits, hits)
	# annexes attach to (overlap) their own parent; tanks sit clear. None may straddle two buildings.
	_check(max_hits <= 1, "subcomp: each ancillary touches at most its own parent (max %d)" % max_hits)
	for c in 2:
		BuildingState.remove_building("sub_b_%d" % c)
	bv.queue_free()
	terrain.queue_free()
	RoadNetwork.reset()
	await get_tree().process_frame

# The main-menu goods board fills its 7x7 (everything but the buffer-most row 0 +
# column 0) with UNIQUE goods; repeats are only allowed on that last-into-view edge.
func _test_main_menu_grid_unique() -> void:
	var grid = load("res://scripts/goods_grid.gd").new()
	grid._arrange_cells()
	var cols: int = grid.COLS
	var n_goods: int = grid._goods_with_icons().size()
	var ids := {}
	var dup := false
	var filled := 0
	for i in grid._layout.size():
		if (i / cols) == grid.REPEAT_ROW or (i % cols) == grid.REPEAT_COL:
			continue  # the "8th" cells (top row + left column) may repeat
		var good = grid._layout[i]
		if good == null:
			continue
		filled += 1
		var gid := str(good.get("id", ""))
		if ids.has(gid):
			dup = true
		ids[gid] = true
	_check(not dup, "main menu grid: the 7x7 block has no repeated goods")
	_check(filled == mini((cols - 1) * (grid.ROWS - 1), n_goods),
		"main menu grid: 7x7 filled with unique goods (%d cells, %d goods with art)" % [filled, n_goods])
	grid.free()

func _test_audio_service() -> void:
	for cue in ["CLICK", "CLICK_MENU", "CLICK_PRIMARY", "HOVER", "HAMMER", "RUBBLE", "SIGNATURE", "CASH_REGISTER", "TECH_UNLOCK", "SLOT_LEVER", "HINT"]:
		_check(Audio.get(cue) != null, "audio: %s cue imports and loads" % cue)
	# Each channel built its own independent voice pool (clicks can't steal build voices).
	var channels_ok: bool = Audio._channels.size() == Audio.CHANNELS.size()
	for ch in Audio.CHANNELS:
		if not (Audio._channels.has(ch) and Audio._channels[ch].size() == int(Audio.CHANNELS[ch])):
			channels_ok = false
	_check(channels_ok, "audio: per-track voice channels built")
	_check(Audio._music != null, "audio: dedicated music player built")
	var music_ok: bool = Audio.MUSIC_TRACKS.size() == 5
	for t in Audio.MUSIC_TRACKS:
		if t == null:
			music_ok = false
	_check(music_ok, "audio: music playlist has 5 loaded tracks")
	# Tile-view terrain ambience: six terrains, three looping slices each.
	_check(Audio._ambient != null, "audio: dedicated ambience player built")
	var ambience_ok: bool = Audio.AMBIENCE.size() == 6
	for terrain in ["sea", "deep_sea", "urban", "rural", "hill", "mountain"]:
		var clips: Array = Audio.AMBIENCE.get(terrain, [])
		if clips.size() != 3:
			ambience_ok = false
		for clip in clips:
			if clip == null or not clip.loop:   # loop=true is baked into the .import
				ambience_ok = false
	_check(ambience_ok, "audio: terrain ambience has 6×3 looping slices")
	# Volume buses: Music + SFX exist (routed to Master), and 0–100% round-trips.
	_check(AudioServer.get_bus_index(Audio.BUS_MUSIC) != -1, "audio: Music bus created")
	_check(AudioServer.get_bus_index(Audio.BUS_SFX) != -1, "audio: SFX bus created")
	Audio.set_bus_percent(Audio.BUS_MASTER, 50.0)
	_check(absf(Audio.get_bus_percent(Audio.BUS_MASTER) - 50.0) < 1.0, "audio: bus volume round-trips (50%)")
	Audio.set_bus_percent(Audio.BUS_MASTER, 0.0)
	_check(Audio.get_bus_percent(Audio.BUS_MASTER) == 0.0, "audio: bus 0% reads as muted")
	Audio.set_bus_percent(Audio.BUS_MASTER, 100.0)   # restore full so later cues aren't muted
	_check(absf(Audio.get_bus_percent(Audio.BUS_MASTER) - 100.0) < 0.5, "audio: bus 100% = full")
	for verb in ["click", "click_menu", "click_primary", "hover", "building_placed", "demolished",
			"transaction", "tech_unlocked", "turn_ready", "swap_song", "play_music", "stop_music", "fade_music",
			"tile_ambience", "stop_tile_ambience", "hint", "set_bus_percent", "get_bus_percent"]:
		_check(Audio.has_method(verb), "audio: %s() verb exists" % verb)
	Audio.click()             # must not error under the dummy driver
	Audio.click_primary()
	Audio.hover()
	Audio.building_placed()
	Audio.demolished()
	Audio.transaction()
	Audio.tech_unlocked()
	Audio.turn_ready()
	Audio.tile_ambience("sea")        # start ambience for a terrain that has it
	Audio.tile_ambience("mountain")   # switch to another terrain that has ambience
	Audio.tile_ambience("")           # unknown terrain → falls through to silence
	Audio.stop_tile_ambience()
	Audio.hint()
	_check(true, "audio: cue verbs run without error")

# The Audio autoload (presentation-layer SFX service). Headless uses the Dummy
# audio driver, so we assert wiring/state rather than actual playback: the click
# stream imports, the voice pool is built, and click() runs without erroring.
# Keybinds — what the Controls tab will and will not accept (scripts/keybinds.gd).
# The demo ships every fixed binding read-only and the map modes unbound, so the only
# behaviour worth pinning is the validator: it is the whole of what the player can do.
func _test_keybinds() -> void:
	var Keybinds = load("res://scripts/keybinds.gd")
	var saved: Dictionary = PlayerProfile.keybinds.duplicate()
	PlayerProfile.keybinds = {"logistics": KEY_J}

	var key := func(code: int, sh := false, ct := false, al := false, me := false) -> InputEventKey:
		var e := InputEventKey.new()
		e.keycode = code
		e.pressed = true
		e.shift_pressed = sh
		e.ctrl_pressed = ct
		e.alt_pressed = al
		e.meta_pressed = me
		return e

	# A free key is accepted.
	_check(bool(Keybinds.validate(key.call(KEY_K), "power").ok), "keybinds: a free letter is accepted")
	_check(bool(Keybinds.validate(key.call(KEY_F5), "power").ok), "keybinds: a function key is accepted")

	# The modifier keys themselves, and any key pressed while one is held.
	for row: Array in [["Shift", KEY_SHIFT], ["Ctrl", KEY_CTRL], ["Alt", KEY_ALT], ["Meta", KEY_META]]:
		var v: Dictionary = Keybinds.validate(key.call(int(row[1])), "power")
		_check(not bool(v.ok) and str(v.message) == Keybinds.MSG_UNUSABLE,
			"keybinds: %s is refused with 'Cannot use that key.'" % str(row[0]))
	for row2: Array in [["Shift", key.call(KEY_K, true)], ["Ctrl", key.call(KEY_K, false, true)],
			["Alt", key.call(KEY_K, false, false, true)], ["Meta", key.call(KEY_K, false, false, false, true)]]:
		var v2: Dictionary = Keybinds.validate(row2[1], "power")
		_check(not bool(v2.ok) and str(v2.message) == Keybinds.MSG_UNUSABLE,
			"keybinds: %s held with a letter is refused" % str(row2[0]))

	# Numbers are reserved for gameplay, top row and keypad alike.
	for row3: Array in [["1", KEY_1], ["0", KEY_0], ["numpad 7", KEY_KP_7]]:
		var v3: Dictionary = Keybinds.validate(key.call(int(row3[1])), "power")
		_check(not bool(v3.ok) and str(v3.message) == Keybinds.MSG_NUMBER,
			"keybinds: %s is refused as a number" % str(row3[0]))

	# Keys the rest of the game already owns, including the two added with this work.
	for row4: Array in [["C", KEY_C], ["Space", KEY_SPACE], ["Z", KEY_Z], ["Tab", KEY_TAB], ["W", KEY_W]]:
		_check(not bool(Keybinds.validate(key.call(int(row4[1])), "power").ok),
			"keybinds: %s is refused, already bound" % str(row4[0]))
	_check(not bool(Keybinds.validate(key.call(KEY_J), "power").ok),
		"keybinds: a key held by another map mode is refused")
	# ...but a row may always keep the key it already has.
	_check(bool(Keybinds.validate(key.call(KEY_J), "logistics").ok),
		"keybinds: a map mode may re-accept its own key")

	# Escape and the mouse are refused outright: Escape is the way out of every menu, and a
	# mode bound to a click would fire while the player was driving the map with the mouse.
	var esc: Dictionary = Keybinds.validate(key.call(KEY_ESCAPE), "power")
	_check(not bool(esc.ok) and str(esc.message) == Keybinds.MSG_UNUSABLE,
		"keybinds: Escape is refused")
	for btn: Array in [["left", MOUSE_BUTTON_LEFT], ["right", MOUSE_BUTTON_RIGHT],
			["middle", MOUSE_BUTTON_MIDDLE], ["wheel up", MOUSE_BUTTON_WHEEL_UP],
			["extra 1", MOUSE_BUTTON_XBUTTON1]]:
		var mb := InputEventMouseButton.new()
		mb.button_index = int(btn[1])
		mb.pressed = true
		var mv: Dictionary = Keybinds.validate(mb, "power")
		_check(not bool(mv.ok) and str(mv.message) == Keybinds.MSG_UNUSABLE,
			"keybinds: mouse %s is refused" % str(btn[0]))
	_check(Keybinds.mapmode_for_keycode(KEY_J) == "logistics", "keybinds: keycode resolves to its map mode")
	_check(Keybinds.mapmode_for_keycode(KEY_K) == "", "keybinds: an unbound keycode resolves to nothing")
	_check(Keybinds.key_name(0) == "Unbound", "keybinds: 0 reads as Unbound")

	# Every fixed row the Controls tab renders must have a label and key text to render.
	var fixed_ok := true
	for r: Dictionary in Keybinds.FIXED:
		if str(r.get("label", "")) == "" or str(r.get("keys", "")) == "":
			fixed_ok = false
	_check(fixed_ok, "keybinds: every fixed row has a label and a key to show")
	_check(Keybinds.MAPMODES.size() == 10, "keybinds: one bindable row per map mode")

	# Commit + reload round-trip, and the 0 sentinel is dropped rather than saved.
	Keybinds.set_mapmode_bindings({"power": KEY_K, "water": 0})
	_check(int(PlayerProfile.keybinds.get("power", 0)) == KEY_K, "keybinds: a binding survives commit")
	_check(not PlayerProfile.keybinds.has("water"), "keybinds: an unbound row is not persisted")

	PlayerProfile.keybinds = saved


## OPEN EVERY CORE PANEL, through the entry points a player actually uses.
##
## Worth nothing until run_tests.py began failing on SCRIPT ERROR (2026-08-29): a GDScript
## runtime error prints and CONTINUES, so a panel that threw on every open still left the
## suite green — which is how the Market crash shipped. With that gate, merely BUILDING a
## panel proves it raised nothing, and that is most of what a panel can get wrong: a null
## @onready path, a renamed node, a bad dict key, a signal bound to a method that moved.
##
## ISOLATION. Driving these panels runs real sim code — the first attempt took a loan out of
## LoanState and left roads, power and tutorial state altered, failing 17 unrelated tests
## downstream. So the whole test runs between a SaveLoad snapshot and its restore, and it is
## called LAST. Either alone would do; both together mean neither the ordering nor the
## restore has to be perfect. If you add a test after this one, keep the snapshot working.
##
## The handlers live on the HUD node (bottom_menu.gd is attached there) — NOT on the child
## HBoxContainer called "BottomMenu", which is a decoy that find_child hits first.
func _test_core_panels_open() -> void:
	var snapshot: Dictionary = SaveLoad.export_snapshot()
	var packed: PackedScene = load("res://scenes/main.tscn")
	if packed == null:
		_check(false, "core panels: main.tscn instantiates")
		return
	var inst: Node = packed.instantiate()
	add_child(inst)
	await get_tree().process_frame
	await get_tree().process_frame

	var menu: Node = null
	for candidate in [inst.find_child("HUD", true, false), inst.find_child("BottomMenu", true, false)]:
		if candidate != null and candidate.has_method("_on_market_pressed"):
			menu = candidate
			break
	_check(menu != null, "core panels: the bottom-menu handlers are reachable")
	if menu == null:
		inst.queue_free()
		SaveLoad.import_snapshot(snapshot)
		return

	# [handler, the property holding the panel it opens, human name]. Politics is absent on
	# purpose: _on_politics_pressed is a print stub, and asserting it opened something would
	# be asserting a feature that does not exist.
	# Construct is the exception: the handler opens whichever panel _active_construct_panel()
	# picks (v2 when MatchState.use_construct_panel_v2), so asking for the v1 property finds a
	# panel that legitimately stayed hidden. Checked separately, below.
	var via_menu := [
		["_on_politics_pressed", "politics_panel", "Politics"],
		["_on_resources_pressed", "resource_panel", "Resources"],
		["_on_mapmodes_pressed", "mapmodes_panel", "Mapmodes"],
		["_on_market_pressed", "market_panel", "Market"],
		["_on_buildings_pressed", "building_ledger_panel", "Buildings ledger"],
		["_on_research_pressed", "research_panel", "Research"],
		["_on_people_pressed", "people_panel", "Labour"],
	]
	for entry: Array in via_menu:
		menu.call(str(entry[0]))
		await get_tree().process_frame
		await get_tree().process_frame
		var panel = menu.get(str(entry[1]))
		_check(panel != null and is_instance_valid(panel) and (panel as Control).visible,
			"core panels: %s opens from its bottom-menu button" % str(entry[2]))
		menu.call(str(entry[0]))          # toggle shut so the next opens on a clean HUD
		await get_tree().process_frame

	# Construct, against whichever panel version is live.
	menu.call("_on_construct_pressed")
	await get_tree().process_frame
	await get_tree().process_frame
	var construct: Control = menu.call("_active_construct_panel")
	_check(construct != null and construct.visible,
		"core panels: Construct opens from its bottom-menu button")
	menu.call("_on_construct_pressed")
	await get_tree().process_frame

	# Money / Balance — the top bar's money widget, not the bottom menu.
	menu.call("_on_money_widget_clicked")
	await get_tree().process_frame
	await get_tree().process_frame
	var money = menu.get("money_panel")
	_check(money != null and (money as Control).visible, "core panels: Money opens on Balance")
	if money != null:
		(money as Control).hide()

	# The two full-screen views, through the signals the buttons emit.
	MatchState.empire_view_requested.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var empire: Node = inst.find_child("EmpireView", true, false)
	_check(empire != null and (empire as CanvasItem).visible, "core panels: the supply chain view opens")
	# The overlap audit on whatever the test game holds: the hard classes are always zero.
	var gw: Node = empire.get_node_or_null("GraphWorld") if empire != null else null
	if gw != null:
		gw.call("_reposition_panels")
		var rep: Dictionary = gw.call("audit")
		var counts: Dictionary = rep["counts"]
		for hard in ["sprite|sprite", "chip|chip", "chip|sprite", "plate|sprite", "fx|plate", "fx|sprite"]:
			_check(int(counts.get(hard, 0)) == 0, "empire audit: no %s collisions in the test game (%d)" % [hard, int(counts.get(hard, 0))])
	if empire != null and empire.has_method("toggle"):
		empire.call("toggle")
		await get_tree().process_frame

	MatchState.goods_graph_requested.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var graph: Node = inst.find_child("GoodsGraphView", true, false)
	_check(graph != null and (graph as CanvasItem).visible, "core panels: the goods graph opens")
	if graph != null and graph.has_method("toggle"):
		graph.call("toggle")
		await get_tree().process_frame

	# Encyclopedia.
	var overlay: Node = inst.find_child("SearchOverlay", true, false)
	if overlay != null and overlay.has_method("open_encyclopedia"):
		overlay.call("open_encyclopedia")
		await get_tree().process_frame
		await get_tree().process_frame
		_check((overlay as CanvasItem).visible, "core panels: the Encyclopedia opens")
		(overlay as CanvasItem).visible = false
		await get_tree().process_frame
	else:
		_check(false, "core panels: the encyclopedia overlay exposes open_encyclopedia")

	# Turn briefing (the "updates" hub behind the bell). It is NOT in main.tscn — the
	# TurnBriefing autoload builds it lazily in its own CanvasLayer, and only shows it when
	# there is something to report. Its items derive from live sim state (starvation, storage,
	# deposits) with no push API, so this asserts what is assertable without faking a crisis:
	# that expanding CONSTRUCTS the panel — the path where a build error would fire — and that
	# it shows itself exactly when it has items.
	# ...and it mounts NO UI under --headless: _sync_ui() returns early on
	# DisplayServer.get_name() == "headless", deliberately. So the assertable contract here is
	# the model half — expand() rebuilds the items and flips the flag without raising (the
	# SCRIPT ERROR gate covers the "without raising" half) — plus the headless guard itself,
	# which is worth pinning: if it ever stopped holding, every headless run would start
	# building panels nobody can see.
	TurnBriefing.expand()
	await get_tree().process_frame
	_check(TurnBriefing.expanded, "core panels: the briefing expands its model state")
	_check(TurnBriefing.get("_panel") == null,
		"core panels: the briefing mounts no UI headless (its documented guard)")
	TurnBriefing.collapse()
	await get_tree().process_frame

	inst.queue_free()
	await get_tree().process_frame
	# Put the sim back exactly as it was — opening these panels moved real state.
	SaveLoad.import_snapshot(snapshot)
	await get_tree().process_frame
