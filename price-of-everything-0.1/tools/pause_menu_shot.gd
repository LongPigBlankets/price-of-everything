extends Node
## Captures of the in-game menu (Esc), over the map at the start of a match.
##   AGENT_GODOT_WINDOW=1 godot --path . res://tools/pause_menu_shot.tscn --quit-after 100000 -- --no-telemetry
## Writes pause_menu.png into $PAUSE_SHOT_DIR (or /tmp).

const ShotHarness := preload("res://tools/shot_harness.gd")

var _out := "/tmp"


func _ready() -> void:
	var dir := OS.get_environment("PAUSE_SHOT_DIR")
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
	PauseMenu.open(game.find_child("HUD", true, false))
	await _wait(0.5)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out.path_join("pause_menu.png"))
	get_tree().quit()


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout
