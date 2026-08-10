extends Node
## Windowed dev shots of the opening transport + later tutorial cards: boots the tutorial
## start via a REAL scene change (the Tutorial autoload only arms when current_scene is
## the main map), fast-forwards the sim state those steps assume (factory bought, cable
## laid), then jumps the live engine to each new step and captures the coach card.
## The scene root hands off to a capper parented to the tree root (it survives the
## scene change), same pattern as tools/tutorial_shot.gd.
##   <godot> --path . res://tools/tutorial_new_steps_shot.tscn --quit-after 3000

const MAIN_SCENE := "res://scenes/main.tscn"
const TILE := "tile_5_9"

var _is_capper := false
var _started := false
var _frames := 0


func _ready() -> void:
	# A scene root is ALSO parented to the tree root, so distinguish launcher vs
	# capper by whether this node IS the current scene.
	if get_tree().current_scene != self:
		_is_capper = true
		return
	get_window().size = Vector2i(1920, 1080)
	var cap: Node = (load("res://tools/tutorial_new_steps_shot.gd") as GDScript).new()
	get_tree().root.add_child.call_deferred(cap)
	SaveLoad.prepare_new_game("res://data/starts/tutorial.json")
	get_tree().change_scene_to_file.call_deferred(MAIN_SCENE)


func _process(_dt: float) -> void:
	if not _is_capper or _started:
		return
	_frames += 1
	var wm := get_tree().current_scene
	if wm != null and wm.get("build_complete") == true and Tutorial.active:
		_started = true
		_run()
	elif _frames > 3000:
		print("[SHOT] timed out waiting for tutorial boot: scene=%s build=%s active=%s" % [
			str(wm), str(wm.get("build_complete") if wm != null else "<null>"), str(Tutorial.active)])
		get_tree().quit(1)


func _run() -> void:
	var wm := get_tree().current_scene
	# State the lessons assume: factory bought (land granted) + the power cable laid.
	var fac_iid := ""
	for iid in MatchState.tile_buildings.get(TILE, []):
		if str(MatchState.get_building(str(iid)).get("building_id", "")) == "b_007":
			fac_iid = str(iid)
	MatchState.set_building_owner(fac_iid, MatchState.LOCAL_PLAYER)
	MatchState.add_building("b_006", "", TILE)
	print("[SHOT] owned: ", MatchState.get_tile_land_owned(TILE))

	# Let the tutorial's own boot (deferred; can re-enter the welcome step a frame
	# after `active` flips true) fully land before jumping around the steps.
	await _settle()
	await _settle()

	Tutorial._jump_to("ui_primer")
	await _settle()
	_capture("tutorial_ui_primer.png")

	Tutorial._jump_to("recipe_inputs_intro")
	await _settle()
	_capture("tutorial_recipe_inputs.png")

	Tutorial._jump_to("recipe_outputs_intro")
	await _settle_frames(75)
	_capture("tutorial_recipe_destinations_first.png")
	await _settle_frames(270)
	_capture("tutorial_recipe_destinations_full.png")

	Tutorial._jump_to("capital_motor_open")
	await _settle()
	_capture("tutorial_capital_motor.png")

	Tutorial._jump_to("capital_motor_route")
	await _settle()
	_capture("tutorial_capital_output.png")

	# Exercise the actual tutorial factory before opening the money breakdown. This
	# catches bad seeded input IDs: a shipment can arrive and pay revenue even when
	# the factory itself never runs, but only a real production dispatch pays freight.
	TurnManager.fast_mode = true
	TurnManager.phase_pause_duration = 0.0
	for _turn in 5:
		TurnManager.commit_turn()
		await TurnManager.turn_resolution_completed
	print("[SHOT] Capital transport paid: ", Production.last_turn_summary.get("transport_paid", 0.0))

	Tutorial._jump_to("capital_money_transport")
	await _settle()
	_capture("tutorial_capital_transport_cost.png")

	# Re-enter the map-watching state the real flow passes through so route captures
	# are not obscured by the factory detail panel left open by this jump harness.
	Tutorial._jump_to("capital_motor_watch")
	await _settle()

	Tutorial._jump_to("capital_road_install")
	await _settle()
	_capture("tutorial_capital_road_flash.png")

	Tutorial._jump_to("capital_rail_build")
	await _settle()
	_capture("tutorial_capital_rail_flash.png")

	Tutorial._jump_to("capital_fluids")
	await _settle()
	_capture("tutorial_capital_fluids.png")

	Tutorial._jump_to("capital_port_open")
	await _settle()
	_capture("tutorial_capital_port.png")

	Tutorial._jump_to("capital_port_costs")
	await _settle()
	_capture("tutorial_capital_port_terms.png")

	Tutorial._jump_to("buy_land")
	await _settle()
	_capture("tutorial_buy_land.png")

	Tutorial._jump_to("transport_redirect_open")
	await _settle()
	_capture("tutorial_transport_redirect.png")

	Tutorial._jump_to("transport_pentagon_revert")
	await _settle()
	_capture("tutorial_transport_revert.png")
	get_tree().quit(0)


func _settle() -> void:
	await _settle_frames(12)


func _settle_frames(count: int) -> void:
	for _i in count:
		await get_tree().process_frame


func _capture(fname: String) -> void:
	var out := ProjectSettings.globalize_path("res://" + fname)
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
