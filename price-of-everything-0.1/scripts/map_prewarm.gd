extends Node
## Prewarms the map (main.tscn) BASE — HUD panels, terrain, and the first render that compiles
## shaders / uploads textures — in a hidden SubViewport while the player is on the New Game
## screen, so the loading screen never FREEZES on instantiation + first render when they hit
## Start. (See world_map._build_base / finish_build for the split.)
##
## Best-effort: if Start comes before the base is warm, is_warm() is false and the caller falls
## back to the normal threaded load. The prewarmed base carries NO simulation (world_map._ready
## stops after _build_base when prewarm_mode is set, emitting base_ready); reveal_and_finish()
## reparents the warm instance into the live tree, sets the chosen start's pending snapshot, and
## runs finish_build() so the loading screen's existing build_complete gate lights "Begin".

const MAIN_SCENE := "res://scenes/main.tscn"

var _vp: SubViewport
var _inst: Node           # the prewarmed world_map (root of main.tscn), or null
var _warm := false

signal warmed


func is_warm() -> bool:
	return _warm and is_instance_valid(_inst)


## Kick off a background prewarm (idempotent + safe to call repeatedly). Async: it awaits the
## threaded scene load, then builds the base in a hidden SubViewport. No-op if one is already
## in flight or warm.
func start_prewarm() -> void:
	if _inst != null or _vp != null:
		return
	# main.tscn is normally already requested by the menu; request it here too in case not.
	if ResourceLoader.load_threaded_get_status(MAIN_SCENE) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		ResourceLoader.load_threaded_request(MAIN_SCENE)
	while ResourceLoader.load_threaded_get_status(MAIN_SCENE) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await get_tree().process_frame
	var packed := ResourceLoader.load_threaded_get(MAIN_SCENE) as PackedScene
	if packed == null or _inst != null or _vp != null:
		return   # load failed, or a concurrent call won the race
	_vp = SubViewport.new()
	_vp.size = DisplayServer.window_get_size()
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS   # render → compile shaders, upload textures
	add_child(_vp)
	_inst = packed.instantiate()
	_inst.set("prewarm_mode", true)
	_inst.connect("base_ready", _on_base_ready)   # connect BEFORE add_child (can fire synchronously)
	_vp.add_child(_inst)


func _on_base_ready() -> void:
	_warm = true
	warmed.emit()
	# A few more rendered frames compile any remaining shader variants and finish texture
	# uploads, then stop rendering the hidden viewport — the warmth is global and persists, so
	# there's no need to keep burning GPU on it behind the menu.
	for _i in range(5):
		await get_tree().process_frame
		if _vp == null or not is_instance_valid(_vp):
			return   # already revealed
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED


## Reveal the warm base as the live scene and finish it for `start_path`. Returns the world_map
## (now current_scene), or null if not warm — in which case the caller should fall back to a
## normal load. Must be called AFTER the loading screen is shown (so it captured the old scene).
func reveal_and_finish(start_path: String, animate: bool) -> Node:
	if not is_warm():
		return null
	var inst := _inst
	_inst = null
	_warm = false
	var old_scene := get_tree().current_scene
	_vp.remove_child(inst)
	get_tree().root.add_child(inst)
	get_tree().current_scene = inst
	if old_scene != null and old_scene != inst:
		old_scene.queue_free()   # free the menu (deferred — its current frame finishes first)
	_vp.queue_free()
	_vp = null
	SaveLoad.prepare_new_game(start_path)   # this start's pending snapshot, consumed by finish_build
	inst.finish_build(animate)              # async; the loading screen polls build_complete
	return inst


## Drop an in-flight / warm prewarm (e.g. the player chose Load Game instead of a new game).
func discard() -> void:
	_warm = false
	if _inst != null and is_instance_valid(_inst):
		_inst.queue_free()
	_inst = null
	if _vp != null and is_instance_valid(_vp):
		_vp.queue_free()
	_vp = null
