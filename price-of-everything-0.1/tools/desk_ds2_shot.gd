extends Node
## Captures of the bottom bar as the DS2 control desk: at rest, and with a panel open (its button pressed in).
## Crops the screen's foot.
##   AGENT_GODOT_WINDOW=1 godot --path . res://tools/desk_ds2_shot.tscn --quit-after 100000 -- --no-telemetry
## Writes desk_<view>.png into $DESK_SHOT_DIR (or /tmp).

const ShotHarness := preload("res://tools/shot_harness.gd")
const CROP_H := 170.0

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
	var research := game.find_child("TechButton", true, false) as Button
	await _wait(0.4)
	await _shot("desk_rest")
	research.pressed.emit()
	await _wait(0.6)
	await _shot("desk_open")
	research.pressed.emit()
	await _wait(0.4)
	get_tree().quit()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var k := float(img.get_width()) / get_viewport().get_visible_rect().size.x
	var h := int(CROP_H * k)
	img.get_region(Rect2i(0, img.get_height() - h, img.get_width(), h)).save_png(_out.path_join(name + ".png"))
	await get_tree().process_frame


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout
