extends Node
## Captures of End Turn on the DS2 desk: at rest, held, and while a turn resolves (the button disabled and the
## roller on Process, as world_map and the turn set them). Crops the screen's bottom-right corner.
##   AGENT_GODOT_WINDOW=1 godot --path . res://tools/end_turn_shot.tscn --quit-after 100000 -- --no-telemetry
## Writes end_turn_<state>.png into $DESK_SHOT_DIR (or /tmp).

const ShotHarness := preload("res://tools/shot_harness.gd")
const CROP := Vector2(560.0, 130.0)

var _out := "/tmp"


func _ready() -> void:
	var dir := OS.get_environment("DESK_SHOT_DIR")
	if dir != "":
		_out = dir
	DirAccess.make_dir_recursive_absolute(_out)
	ShotHarness.arm_watchdog(self, 180.0)
	ShotHarness.prepare_window(get_window(), Vector2i(1920, 1080))
	TelemetryState.enabled = false
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(120)
	DecisionState.enabled = false
	if not UiPrefs.use_desk_ds2:
		UiPrefs.toggle_use_desk_ds2()
	var dock := game.find_child("EndTurnDock", true, false)
	var button := game.find_child("EndTurnButton", true, false) as Button
	await _wait(0.4)
	await _shot("end_turn_rest")
	dock.set("_btn_down", true)
	dock.queue_redraw()
	await _wait(0.2)
	await _shot("end_turn_held")
	dock.set("_btn_down", false)
	button.disabled = true
	dock.get("_roller").set_phase("Process", true)
	await _wait(0.4)
	await _shot("end_turn_resolve")
	button.disabled = false
	get_tree().quit()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var k := float(img.get_width()) / get_viewport().get_visible_rect().size.x
	var size := Vector2i(CROP * k)
	img.get_region(Rect2i(img.get_width() - size.x, img.get_height() - size.y, size.x, size.y)).save_png(_out.path_join(name + ".png"))
	await get_tree().process_frame


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout
