extends Node
## Captures of the opening steps every new game plays (Tutorial.start_opener) in a Metal Magnate game: the
## story intro closing hands over to the welcome, then each step, then the missions appearing with the shine
## sweeping across the top bar's mission slot.
##   AGENT_GODOT_WINDOW=1 godot --path . res://tools/opener_shot.tscn --quit-after 40000 -- --no-telemetry
## Writes opener_<nn>_<step>.png and opener_shine_<n>.png into $OPENER_SHOT_DIR (or /tmp).

const ShotHarness := preload("res://tools/shot_harness.gd")
const START := "res://data/starts/metal_magnate.json"

var _out := "/tmp"


func _ready() -> void:
	var dir := OS.get_environment("OPENER_SHOT_DIR")
	if dir != "":
		_out = dir
	DirAccess.make_dir_recursive_absolute(_out)
	ShotHarness.arm_watchdog(self, 240.0)
	ShotHarness.prepare_window(get_window(), Vector2i(1920, 1080))
	TelemetryState.enabled = false
	SaveLoad.autosave_enabled = false
	AudioServer.set_bus_mute(0, true)
	SaveLoad.prepare_new_game(START)
	var world: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(world)
	await get_tree().process_frame
	get_tree().current_scene = world
	await _settle(200)
	DecisionState.enabled = false
	# Close the story intro as its Begin key does: the opener follows it.
	for layer in get_tree().root.find_children("*", "CanvasLayer", true, false):
		var sc := (layer as Node).get_script() as Script
		if sc != null and sc.resource_path.ends_with("_intro.gd"):
			layer.queue_free()
	await _settle(40)
	if not Tutorial.opener:
		push_error("opener_shot: the opener did not start")
		get_tree().quit(1)
		return
	var n := 0
	while Tutorial.active:
		var id := str((Tutorial._steps[Tutorial._index] as Dictionary).get("id", ""))
		await _wait(0.6)
		await _shot("opener_%02d_%s" % [n, id])
		n += 1
		Tutorial._advance()
		await _settle(10)
	# The missions appear and the shine sweeps across them.
	await _wait(0.45)
	await _shot("opener_shine_1")
	await _wait(0.3)
	await _shot("opener_shine_2")
	await _wait(2.0)
	await _shot("opener_after")
	get_tree().quit()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	await get_tree().process_frame


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout
