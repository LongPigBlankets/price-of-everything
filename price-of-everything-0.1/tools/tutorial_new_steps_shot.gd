extends Node
## Windowed dev shots of the buy-land + transport tutorial cards: boots the tutorial
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

	Tutorial._jump_to("buy_land")
	await _settle()
	_capture("tutorial_buy_land.png")

	Tutorial._jump_to("transport_ports")
	await _settle()
	var ev := wm.find_child("EmpireView", true, false)
	if ev != null:
		ev.call("toggle")
		await _settle()
		_capture("tutorial_transport_empire.png")
		ev.call("toggle")
		await _settle()

	Tutorial._jump_to("transport_redirect_open")
	await _settle()
	_capture("tutorial_transport_redirect.png")

	Tutorial._jump_to("transport_pentagon_revert")
	await _settle()
	_capture("tutorial_transport_revert.png")
	get_tree().quit(0)


func _settle() -> void:
	for _i in 12:
		await get_tree().process_frame


func _capture(fname: String) -> void:
	var out := ProjectSettings.globalize_path("res://" + fname)
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
