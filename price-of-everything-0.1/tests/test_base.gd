extends Node
## Base class for every unit-test file under tests/unit/.
##
## A test file extends this, declares `const FEATURE := "<tag>"`, and optionally a
## `const TAGS := {"_test_name": ["tag", ...]}` map for tests that belong to more than
## one feature. Every `func _test_*()` in the file is discovered and run by
## tests/test_runner.gd. Tag rules:
##   * a test listed in TAGS carries exactly those tags;
##   * otherwise it carries [FEATURE];
##   * an empty tag list (FEATURE == "" or TAGS[name] == []) is a WILDCARD: the test
##     is treated as relevant to every feature and runs under any --tags filter.
##
## Shared preloads, the _check assertion and helpers used by more than one file live here.

const BuildingLevels := preload("res://scripts/building_levels.gd")
const NewGamePanel := preload("res://scripts/new_game_panel.gd")   # its SPEEDS table
const EndGameData := preload("res://scripts/end_game_data.gd")     # the end-screen assembler
const BuildingStatus := preload("res://scripts/building_status.gd")
## Minimal, zero-dependency headless test runner for price-of-everything.
##
## Fast path (one command; exit code 0 = all pass, 1 = a failure):
##     <godot> --headless res://tests/test_runner.tscn
## Or from the editor: open tests/test_runner.tscn and press F6 (Run Current Scene);
## results print in the Output panel.
##
## It runs as a SCENE (not --script) so the project autoloads — Catalog,
## Stockpile, Production, DS, etc. — are available. The goal is to catch, without
## manual clicking: script parse errors, broken @onready paths, main.tscn
const RoadRegionsLoader := preload("res://scripts/road_regions.gd")
const TutorialSteps := preload("res://scripts/tutorial/tutorial_steps.gd")
const TutorialDetectors := preload("res://scripts/tutorial/tutorial_detectors.gd")
const BuildingReadout := preload("res://scripts/building_readout.gd")
const BuildForecast := preload("res://scripts/build_forecast.gd")
const MassFormShapes := preload("res://scripts/mass_form_shapes.gd")
const AuthoredMap := preload("res://scripts/authored_map.gd")
const AuthoredRoadGeometry := preload("res://scripts/authored_road_geometry.gd")
const AuthoredRoadStyle := preload("res://scripts/authored_road_style.gd")
const AuthoredFabricPainter := preload("res://scripts/authored_fabric_painter.gd")
const MapEditorShapeToolScript := preload("res://scripts/map_editor/map_editor_shape_tool.gd")
const MapEditorRegionImportScript := preload("res://scripts/map_editor/map_editor_region_import.gd")
const ImportLiveMapScript := preload("res://tools/map_editor/import_live_map.gd")
const WorldMapScript := preload("res://scripts/world_map.gd")
const AuthoredRoadVisualsScript := preload("res://scripts/authored_road_visuals.gd")
## Editor-only, and excluded from exported builds alongside this suite. Held here because the
## editor's slot geometry had no headless coverage at all, which is how it shipped a builder
## that crashed on any document the editor had not just created.
const MapEditorSlotBoxes := preload("res://scripts/map_editor/map_editor_slot_boxes.gd")
const AuthoredSlotSizes := preload("res://scripts/authored_slot_sizes.gd")
const AppPaths := preload("res://scripts/app_paths.gd")  # saves now live in <base>/savegames/

var _passed := 0
var _failed := 0
var _failed_names: Array[String] = []

## research_unlocks.csv as an array of column->value dictionaries.
func _research_rows() -> Array:
	var file := FileAccess.open("res://data/research_unlocks.csv", FileAccess.READ)
	if file == null:
		return []
	var header := file.get_csv_line()
	var out: Array = []
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() < header.size():
			continue
		var d: Dictionary = {}
		for i in header.size():
			d[header[i]] = row[i]
		out.append(d)
	return out


func _node_tree_contains_text(root: Node, needle: String) -> bool:
	if root == null:
		return false
	if root is Label and str((root as Label).text).contains(needle):
		return true
	if root is Button and str((root as Button).text).contains(needle):
		return true
	for child in root.get_children():
		if _node_tree_contains_text(child, needle):
			return true
	return false

func _fresh_production_summary() -> Dictionary:
	# Minimal summary skeleton Production._dispatch_output_to_stockpile reads/writes.
	return {
		"produced": {},
		"transport_paid": 0.0,
		"money_out": 0.0,
		"money_in": 0.0,
		"goods_sales_revenue": 0.0,
		"goods_purchased_cost": 0.0,
		"sold": {},
	}

func _check(ok: bool, name: String) -> void:
	if ok:
		_passed += 1
		print("  PASS  ", name)
	else:
		_failed += 1
		_failed_names.append(name)
		printerr("  FAIL  ", name)

func _replace_dict(target: Dictionary, source: Dictionary) -> void:
	target.clear()
	for key in source:
		target[key] = source[key]

func _tree_has_label_text(node: Node, needle: String) -> bool:
	if needle in node.name:
		return true
	if node is Label and needle in (node as Label).text:
		return true
	if node is Button and needle in (node as Button).text:
		return true
	for child in node.get_children():
		if _tree_has_label_text(child, needle):
			return true
	return false

# Shared setup/teardown: decisions run against a clean DecisionState with the
# advisor board and turn clock under test control; every helper restores what it
# touches (the suite shares autoload state across tests).
func _decision_board_snapshot() -> Dictionary:
	return {
		"permanent": AdvisorState.permanent_advisor_ids.duplicate(),
		"recruited": AdvisorState.recruited_advisor_ids.duplicate(),
		"seats": AdvisorState.advisor_seats.duplicate(true),
		"hired": AdvisorState.advisor_hired_turn.duplicate(true),
		"loyalty": AdvisorState.advisor_loyalty.duplicate(true),
		"money": MatchState.money,
		"turn": TurnManager.current_turn,
		"phase": TurnManager.current_phase,
	}

func _decision_board_restore(snap: Dictionary) -> void:
	AdvisorState.permanent_advisor_ids = snap.permanent
	AdvisorState.recruited_advisor_ids = snap.recruited
	AdvisorState.advisor_seats = snap.seats
	AdvisorState.advisor_hired_turn = snap.hired
	AdvisorState.advisor_loyalty = snap.loyalty
	MatchState.money = snap.money
	TurnManager.current_turn = snap.turn
	TurnManager.current_phase = snap.phase
	DecisionState.reset()
	Modifiers.reset()
	EventScheduler.reset()


## Wait until a turn resolution started with TurnManager.commit_turn() has finished.
## Resolution yields a frame per phase, so a test that commits and then returns leaves it
## running across whatever test comes next.
func _await_turn_settled() -> void:
	while TurnManager.is_resolving:
		await get_tree().process_frame


## Instantiate scenes/main.tscn for one frame so its _ready runs against the live autoloads
## (NPC ports, start buildings, HUD wiring), then free it. For tests that assert on state the
## main scene seeds and cannot cheaply seed themselves.
func _boot_main_scene_once() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	if packed == null:
		return
	var inst: Node = packed.instantiate()
	add_child(inst)
	await get_tree().process_frame
	inst.queue_free()
	await get_tree().process_frame
