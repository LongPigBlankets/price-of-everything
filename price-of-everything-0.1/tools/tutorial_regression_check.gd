extends Node
## Windowed regression of tutorial controls affected by construction, research and
## council changes. Uses isolated saves; jumps past economic lessons to exercise
## both construction branches and the actual research/advisor UI actions.
const Paths := preload("res://scripts/app_paths.gd")
const Steps := preload("res://scripts/tutorial/tutorial_steps.gd")
const Detectors := preload("res://scripts/tutorial/tutorial_detectors.gd")
const Terminal := preload("res://scripts/debug_terminal.gd")
var _capper := false
var _started := false
var checks := 0
var failures := 0

func _ready() -> void:
	if get_tree().current_scene != self:
		_capper = true
		return
	Paths._base = "/tmp/poe-tutorial-regression"
	var cap: Node = (load("res://tools/tutorial_regression_check.gd") as GDScript).new()
	get_tree().root.add_child.call_deferred(cap)
	SaveLoad.prepare_new_game("res://data/starts/tutorial.json")
	get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")

func _process(_dt: float) -> void:
	if not _capper or _started:
		return
	var world := get_tree().current_scene
	if world != null and world.get("build_complete") == true and Tutorial.active:
		_started = true
		_run()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("[tutorial regression] " + message)
	else:
		print("[tutorial regression] PASS ", message)

func settle() -> void:
	for i in 35:
		await get_tree().process_frame

func node_named(id: String) -> Node:
	return Tutorial._find(id)

func tap(id: String) -> void:
	var node := node_named(id)
	check(node is Control and (node as Control).is_visible_in_tree(), id + " is visible")
	if node is BaseButton:
		check(not (node as BaseButton).disabled, id + " is enabled")
		(node as BaseButton).pressed.emit()
	elif node is Control:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		(node as Control).gui_input.emit(click)
	await settle()
	Tutorial._maybe_advance()
	await settle()

func shot(name: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/" + name + ".png")

func _run() -> void:
	await settle()
	check(Tutorial.active, "tutorial boots and displays its coach")
	check(get_tree().current_scene._expand_public_roads(20).is_empty(), "public road growth leaves tutorial infrastructure lessons in control")
	check(not Terminal.demo_is_unlocked(), "demo loyalty starts locked")
	Tutorial._jump_to("ui_primer")
	await settle()
	check(node_named("ConstructButton") != null and node_named("PeopleButton") != null, "top and bottom bar tutorial targets survive")
	await shot("tutorial_regression_primer")
	for target in ["TransportModule", "PowerModule", "RankingsModule", "GoodsGraphModule", "EncyclopediaButton"]:
		check(node_named(target) != null, target + " tutorial annotation resolves")
	Tutorial._advance()
	await settle()
	check(Tutorial.is_active_step("tile_basics_select"), "tile lesson waits for a selection")
	MatchState.focus_tile_requested.emit(Steps.MOTOR_TILE)
	await settle()
	check(Tutorial.is_active_step("tile_basics_land"), "opening a tile advances to its Land Chart")
	check(Tutorial._overlay.spotlight_ok(), "Land Chart spotlight resolves")
	Tutorial._advance()
	await settle()
	check(Tutorial.is_active_step("tile_basics_features") and Tutorial._overlay.spotlight_ok(), "tile features lesson highlights the panel")
	Tutorial._advance()
	await settle()
	check(Tutorial.is_active_step("recipe_inputs_intro"), "tile lessons return to the recipe introduction")
	Tutorial._jump_to("capital_motor_route")
	await settle()
	check(Tutorial._overlay.spotlight_ok(), "motor recipe spotlight resolves at top of building panel")
	Tutorial._jump_to("capital_port_costs")
	await settle()
	check(Tutorial._overlay.spotlight_ok(), "port terms spotlight resolves")
	# Inspect actual displayed rows, including every sea-freight class in both tables.
	var throughput_rows := 0
	for label: Label in get_tree().current_scene.find_children("*", "Label", true, false):
		if label.is_visible_in_tree() and label.text.begins_with("Throughput:"):
			throughput_rows += 1
			check(label.size.x >= 100.0, "port throughput label keeps a readable width")
	check(throughput_rows == 12, "port shows six freight classes in current terms and rate card")
	Tutorial._jump_to("goto_tile")
	await settle()
	MatchState.focus_tile_requested.emit(Steps.WINDOW_TILE)
	await settle()
	check(Tutorial.is_active_step("build_open"), "factory tile selection opens the next construction lesson")
	await tap("BLBuildButton")
	await tap("RecipeRow_r_056")
	check(Tutorial.is_active_step("build_cost") and Tutorial._overlay.spotlight_ok(), "window recipe highlights construction materials")
	await shot("tutorial_regression_materials")
	Tutorial._run_setup([{"action": "close_construct"}, {"action": "close_building_detail"}])
	BuildMode.exit_build_mode()
	# Fixture: completed early purchase and loan lessons, with enough cash to check
	# both alternative construction branches in one run.
	MatchState.money = 5000.0
	Tutorial._active_board_tiles = Steps.BOARD_TILES.duplicate()
	Tutorial._apply_board_bounds()
	TurnManager.current_turn = 20
	for iid in MatchState.tile_buildings.get(Steps.WINDOW_TILE, []):
		if str(MatchState.get_building(str(iid)).get("building_id", "")) == "b_007":
			MatchState.set_building_owner(str(iid), MatchState.LOCAL_PLAYER)
	# Exercise the real cable button: insufficient funds must not complete the step,
	# while a successful materials order must advance without the retired sourcing dialog.
	Tutorial._jump_to("lay_cable_factory")
	await settle()
	MatchState.money = 0.0
	var cable_cell := node_named("InfraCell_cables")
	var cable_button := cable_cell.find_children("*", "Button", true, false)[0] as Button
	cable_button.pressed.emit()
	await settle()
	check(Tutorial.is_active_step("lay_cable_factory"), "rejected cable purchase does not advance the tutorial")
	MatchState.money = 5000.0
	cable_button.pressed.emit()
	await settle()
	check(Detectors.poll({"kind": "tile_cabled_or_ordered", "tile": Steps.WINDOW_TILE}), "cable button creates a real construction order")
	check(Tutorial.is_active_step("run_until_running"), "cable order advances straight to ending turns")
	check(Tutorial._overlay.spotlight_ok(), "End Turn becomes the active cable lesson target")
	Tutorial._jump_to("lay_cable_factory")
	await settle()
	check(Tutorial.is_active_step("run_until_running"), "re-entering with a pending cable order recovers automatically")
	for iid in Construction.construction_projects.keys():
		Construction.cancel(str(iid))
	for branch in ["glass", "alu"]:
		var tile: String = Steps.GLASS_TILE if branch == "glass" else Steps.ALU_TILE
		var recipe := "r_053" if branch == "glass" else "r_050"
		Tutorial._jump_to("build_" + branch + "_open")
		await settle()
		await tap("BLBuildButton")
		await tap("RecipeRow_" + recipe)
		check(Tutorial.is_active_step("build_" + branch + "_confirm"), branch + " recipe advances to confirm")
		check(Tutorial._overlay.spotlight_ok(), branch + " confirm spotlight resolves")
		await shot("tutorial_regression_" + branch + "_confirm")
		await tap("BuildConfirmButton")
		check(Detectors.poll({"kind": "building_or_project_on_tile", "tile": tile, "building_id": "b_002"}), branch + " construction is queued")
		Tutorial._run_setup([{"action": "close_sourcing"}, {"action": "close_construct"}])
		BuildMode.exit_build_mode()
		# Each branch starts without the alternative branch's furnace.
		for iid in Construction.construction_projects.keys():
			Construction.cancel(str(iid))
		await settle()
	Tutorial._jump_to("alu_research")
	await settle()
	await tap("TechButton")
	var research := node_named("ResearchPanel")
	check(research is Control and research.is_visible_in_tree(), "research opens from the tutorial")
	Tutorial._jump_to("alu_research_search")
	await settle()
	var search := node_named("ResearchSearchInput") as LineEdit
	check(search != null and search.is_visible_in_tree(), "research search target is visible")
	if search != null:
		search.text = "aluminium"
		search.text_changed.emit(search.text)
	await settle()
	Tutorial._maybe_advance()
	await settle()
	check(Tutorial.is_active_step("alu_research_condition"), "search advances to the research explanation")
	check(research.tutorial_unlock_rect("Bauxite Carbochlorination").has_area(), "renovated research panel exposes the unlock spotlight")
	await shot("tutorial_regression_research")
	Tutorial._run_setup([{"action": "close_research"}])
	Tutorial._jump_to("advisors_inspect")
	await settle()
	await tap("AdvisorAddNewButton")
	var people := node_named("PeoplePanel")
	var council: Node = null
	for item in people.find_children("*", "Control", true, false):
		if item.get_script() == preload("res://scripts/advisor_council_tab.gd"):
			council = item
	check(council != null, "tutorial uses the current council tab")
	if council != null:
		var candidates: Array = council._picker_candidates()
		check(not candidates.is_empty(), "demo has a hireable advisor")
		if not candidates.is_empty():
			council._set_view({"mode": "detail", "sel_id": str(candidates[0].get("id", "")), "back": "picker"})
			await settle()
			await tap("AdvisorSeatChoice_coo")
			check(node_named("AdvisorBonusSection") != null, "What They Bring remains available without loyalty")
			check(Tutorial.is_active_step("advisors_hire"), "bonus inspection advances to hiring")
			await shot("tutorial_regression_advisor")
			await tap("AdvisorHireAssignButton")
			check(MatchState.advisor_seats.has("coo"), "advisor can be hired and assigned in the locked demo")
	Tutorial._jump_to("integration_done")
	await settle()
	check(Tutorial.setup_reached, "completion hook remains reachable")
	var bar := node_named("TopBar")
	bar._refresh_council()
	check(not bar._council_led.visible, "council lamp is hidden")
	var portrait: Control = bar._portrait_chip("vera", 30)
	check(not portrait.tooltip_text.contains("loyalty"), "council portraits hide loyalty tooltips")
	portrait.free()
	Tutorial._finish()
	people.hide()
	DecisionState.enabled = true
	DecisionState.pending_queue = [{"uid": "demo_loyalty_check", "def_id": "substation_failure",
		"target": {"scope": "tile", "tile_id": Steps.WINDOW_TILE, "name": "Stoneshore Fields"}, "turn_drawn": 20}]
	TurnBriefing.expand()
	await settle()
	var briefing: Control = TurnBriefing._panel
	var visible_labels := ""
	for label: Label in briefing.find_children("*", "Label", true, false):
		if label.is_visible_in_tree():
			visible_labels += label.text + " "
	check(not visible_labels.contains("▲") and not visible_labels.contains("▼"), "demo decisions show no loyalty arrows")
	check(not visible_labels.to_lower().contains("loyalty"), "demo decisions hide loyalty stakes")
	await shot("tutorial_regression_decisions")

	print("[tutorial regression] %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
